-- Guild Board extras: gear upgrades, assumed profession mats, dungeon wants. All in game, nothing goes to Discord.
--   Gear: hover any gear that isn't Bind on Pickup and see who in the guild it is an item level upgrade for
--         (checks armor type, weapon skills, main stat and required level).
--   Mats: yellow "Could use" lines on crafting mats that match the skill bracket a guildie is leveling.
--         Blue lines elsewhere are things someone actually asked for (Alt+click).
--   Dungeons: click the minimap button to flag dungeons you want to run. Right-click it for the Guild Board window.
--         A flag turns off when you click it again, leave that dungeon after killing 3+ bosses, out-level it, or after 48 hours.

local _, ns = ...
local SEP = ns.SEP or "^"
local GOLD, GRAY, GREEN, YELLOW = "|cffffd100", "|cff9d9d9d", "|cff33ff99", "|cffffff00"
local WANT_HOURS = 48

local function db() return ns.db() end
local function short(k) return ns.short(k) end
local function info(id)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return get(id)
end

-- ===== my gear =====
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local function slotIlvl(slot)
  local link = GetInventoryItemLink("player", slot)
  if not link then return 0 end
  local l = (C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link))
    or (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link))
  if not l then l = select(4, info(link)) end
  return l or 0
end
local function myGear()
  local g = {}
  for _, s in ipairs(SLOTS) do g[s] = slotIlvl(s) end
  return g
end
local function gearString(g)
  local parts = {}
  for _, s in ipairs(SLOTS) do parts[#parts + 1] = s .. ":" .. (g[s] or 0) end
  return table.concat(parts, ",")
end
local lastGear
local function broadcastGear(force)
  local g = myGear()
  local str = gearString(g)
  if not force and str == lastGear then return end
  lastGear = str
  local ts = time()
  local cls = UnitClass("player")
  db().gear = db().gear or {}
  db().gear[ns.me()] = { ts = ts, class = cls, level = UnitLevel("player"), slots = g }
  ns.send("G" .. SEP .. ts .. SEP .. cls .. SEP .. (UnitLevel("player") or 0) .. SEP .. str)
end
ns.handlers.G = function(sender, f)
  local ts = tonumber(f[1]) or 0
  db().gear = db().gear or {}
  local cur = db().gear[sender]
  if cur and (cur.ts or 0) > ts then return end
  local slots = {}
  for s, l in (f[4] or ""):gmatch("(%d+):(%d+)") do slots[tonumber(s)] = tonumber(l) end
  db().gear[sender] = { ts = ts, class = f[2], level = tonumber(f[3]) or 0, slots = slots }
end

-- ===== who can use what =====
local EQUIP = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 } }
local SLOTNAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist",
  [10] = "Hands", [11] = "Ring", [13] = "Trinket", [15] = "Back", [16] = "Weapon", [17] = "Off hand", [18] = "Ranged" }

local function armorFor(class, level)
  if class == "Warrior" or class == "Paladin" then return level >= 40 and "Plate" or "Mail" end
  if class == "Hunter" or class == "Shaman" then return level >= 40 and "Mail" or "Leather" end
  if class == "Rogue" or class == "Druid" then return "Leather" end
  return "Cloth"
end
local W = {
  Warrior = "One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,One-Handed Swords,Two-Handed Swords,Polearms,Staves,Daggers,Fist Weapons,Bows,Guns,Crossbows,Thrown,Shields",
  Paladin = "One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,One-Handed Swords,Two-Handed Swords,Polearms,Shields,Librams",
  Hunter = "One-Handed Axes,Two-Handed Axes,One-Handed Swords,Two-Handed Swords,Polearms,Staves,Daggers,Fist Weapons,Bows,Guns,Crossbows,Thrown",
  Rogue = "Daggers,Fist Weapons,One-Handed Swords,One-Handed Maces,Bows,Guns,Crossbows,Thrown",
  Shaman = "One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,Staves,Daggers,Fist Weapons,Shields,Totems",
  Druid = "One-Handed Maces,Two-Handed Maces,Staves,Daggers,Fist Weapons,Idols",
  Mage = "Staves,Daggers,One-Handed Swords,Wands", Priest = "Staves,One-Handed Maces,Daggers,Wands",
  Warlock = "Staves,Daggers,One-Handed Swords,Wands" }
local MAIN = { Warrior = { STR = 1, AGI = 1 }, Paladin = { STR = 1, INT = 1 }, Hunter = { AGI = 1 }, Rogue = { AGI = 1 },
  Shaman = { STR = 1, AGI = 1, INT = 1 }, Druid = { STR = 1, AGI = 1, INT = 1 }, Mage = { INT = 1 }, Priest = { INT = 1 }, Warlock = { INT = 1 } }

local function itemStats(link)
  local get = (C_Item and C_Item.GetItemStats) or GetItemStats
  local st = get and get(link) or {}
  local has = {}
  for k in pairs(st) do
    if k:find("STRENGTH") then has.STR = 1 elseif k:find("AGILITY") then has.AGI = 1 elseif k:find("INTELLECT") then has.INT = 1 end
  end
  return has
end

local function canUse(class, level, equipLoc, itemClass, subType, minLevel, link)
  if (minLevel or 0) > (level or 0) + 3 then return false end
  if itemClass == "Armor" then
    if equipLoc == "INVTYPE_SHIELD" then return (W[class] or ""):find("Shields", 1, true) ~= nil end
    if subType == "Cloth" or subType == "Leather" or subType == "Mail" or subType == "Plate" then
      if equipLoc ~= "INVTYPE_CLOAK" and subType ~= armorFor(class, level) then return false end
    end
  elseif itemClass == "Weapon" then
    if not (W[class] or ""):find(subType or "?", 1, true) then return false end
  end
  local has = itemStats(link)
  if has.STR or has.AGI or has.INT then
    local ok = false
    for k in pairs(has) do if MAIN[class] and MAIN[class][k] then ok = true end end
    if not ok then return false end
  end
  return true
end

local function upgradeLines(id)
  local name, link, _, ilvl, minLevel, itemClass, subType, _, equipLoc, _, _, _, _, bindType = info(id)
  if not equipLoc or not EQUIP[equipLoc] or bindType == 1 then return nil end
  ilvl = (C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)) or ilvl or 0
  local hits = {}
  local all = {}
  for k, v in pairs(db().gear or {}) do all[k] = v end
  all[ns.me()] = { class = UnitClass("player"), level = UnitLevel("player"), slots = myGear() }
  for who, g in pairs(all) do
    if canUse(g.class, g.level, equipLoc, itemClass, subType, minLevel, link) then
      local worst
      for _, s in ipairs(EQUIP[equipLoc]) do
        local have = g.slots and g.slots[s] or 0
        if not worst or have < worst then worst = have end
      end
      local gain = ilvl - (worst or 0)
      if gain > 0 then
        hits[#hits + 1] = { who = (who == ns.me() and "you" or short(who)), gain = gain, slot = SLOTNAME[EQUIP[equipLoc][1]] or "" }
      end
    end
  end
  if #hits == 0 then return nil end
  table.sort(hits, function(a, b) return a.gain > b.gain end)
  local parts = {}
  for i, h in ipairs(hits) do if i <= 5 then parts[#parts + 1] = h.who .. " +" .. h.gain end end
  return { GREEN .. "Upgrade for:|r " .. table.concat(parts, ", ") .. GRAY .. " (" .. hits[1].slot .. ", item level)|r" }
end

-- ===== assumed mats by profession skill (yellow) =====
-- Brackets follow the WoW Forever 1-300 leveling routes (rankedboost.com, Nov 2026). Vendor items (thread, salt,
-- dye, vials, flux, spices) are left out because nobody needs those sent to them. Matched by item name.
local M = {
  LW = { { 1, 90, "Light Leather" }, { 50, 65, "Light Hide" }, { 117, 130, "Light Hide" }, { 90, 145, "Medium Hide" },
         { 101, 145, "Medium Leather" }, { 145, 195, "Heavy Leather" }, { 155, 195, "Heavy Hide" }, { 195, 225, "Thick Leather" },
         { 225, 300, "Rugged Leather" }, { 262, 275, "Heavy Scorpid Scale" } },
  BS = { { 1, 75, "Rough Stone,Copper Bar" }, { 75, 150, "Bronze Bar,Coarse Stone,Medium Leather,Silver Bar" },
         { 150, 225, "Mageweave Cloth,Mithril Bar,Bronze Bar,Solid Stone,Heavy Stone,Steel Bar,Iron Bar,Coarse Stone,Medium Leather,Truesilver Bar,Silver Bar" },
         { 225, 300, "Thorium Bar,Mithril Bar,Thick Leather,Rugged Leather,Solid Stone,Blue Sapphire,Purple Lotus,Dense Stone,Iron Bar" } },
  TA = { { 1, 75, "Linen Cloth" }, { 75, 150, "Wool Cloth,Silk Cloth,Heavy Leather" }, { 150, 225, "Mageweave Cloth,Silk Cloth,Heavy Leather" },
         { 225, 300, "Runecloth,Dream Dust,Rugged Leather,Star Ruby" } },
  FA = { { 1, 75, "Linen Cloth,Peacebloom" }, { 75, 150, "Wool Cloth,Bruiseweed,Peacebloom" },
         { 150, 225, "Silk Cloth,Mageweave Cloth,Thick Leather,Liferoot" }, { 225, 300, "Mageweave Cloth,Runecloth" } },
  AL = { { 1, 75, "Silverleaf,Peacebloom,Mageroyal" }, { 75, 150, "Mageroyal,Peacebloom,Swiftthistle,Briarthorn,Bruiseweed,Stranglekelp" },
         { 150, 225, "Mageroyal,Stranglekelp,Wild Steelbloom,Kingsblood,Goldthorn,Fadeleaf" },
         { 225, 300, "Goldthorn,Fadeleaf,Arthas' Tears,Gromsblood,Dream Dust,Dreamfoil" } },
  EN = { { 1, 25, "Mote of Magic" }, { 25, 70, "Lesser Magic Essence" }, { 99, 100, "Lesser Magic Essence" }, { 70, 140, "Strange Dust" },
         { 130, 140, "Lesser Astral Essence" }, { 140, 200, "Soul Dust" }, { 200, 258, "Vision Dust" }, { 258, 284, "Greater Nether Essence" },
         { 284, 300, "Dream Dust" } },
  EG = { { 1, 75, "Linen Cloth,Copper Bar,Rough Stone" }, { 75, 150, "Wool Cloth,Linen Cloth,Copper Bar,Bronze Bar,Rough Stone,Heavy Stone,Medium Leather" },
         { 150, 225, "Wool Cloth,Mithril Bar,Iron Bar,Solid Stone,Bronze Bar,Medium Leather,Gold Bar" },
         { 225, 300, "Runecloth,Mageweave Cloth,Thorium Bar,Solid Stone,Mithril Bar,Dense Stone" } },
}
local PROF = { Leatherworking = "LW", Blacksmithing = "BS", Tailoring = "TA", ["First Aid"] = "FA", Alchemy = "AL", Enchanting = "EN", Engineering = "EG" }
local SHORT = { LW = "LW", BS = "BS", TA = "Tailoring", FA = "First Aid", AL = "Alchemy", EN = "Enchanting", EG = "Engineering" }

local function matsLines(id)
  local iname = info(id)
  if not iname then return nil end
  local who = {}
  local self = ns.me()
  local needs = db().needs or {}
  for key, m in pairs((GuildBoardDB and GuildBoardDB.members) or {}) do
    local asked = needs[key] and needs[key].items and (needs[key].items[id] or 0) > 0
    if key ~= self and not asked then
      for p in (m.profs or ""):gmatch("[^,]+") do
        local pn, rank = p:match("^(.-):(%d+):%d+$")
        local code = pn and PROF[pn]
        rank = tonumber(rank)
        if code and rank then
          local seen = false
          for _, b in ipairs(M[code]) do
            if rank >= b[1] and rank < b[2] and ("," .. b[3] .. ","):find("," .. iname .. ",", 1, true) and not seen then
              seen = true
              who[#who + 1] = short(key) .. " (" .. SHORT[code] .. " " .. rank .. ")"
            end
          end
        end
      end
    end
  end
  if #who == 0 then return nil end
  table.sort(who)
  return { YELLOW .. "Could use (leveling):|r " .. table.concat(who, ", ") }
end

ns.tipExtras = ns.tipExtras or {}
table.insert(ns.tipExtras, { "mats", matsLines })
table.insert(ns.tipExtras, { "upgrades", upgradeLines })

-- ===== dungeon wants =====
-- WoW Forever dungeon list and level ranges (warcrafttavern.com, Nov 2026). The last field is a word from the
-- instance name; leaving that instance after killing at least one boss takes the flag off.
local DUNGEONS = {
  { "RFC", "Ragefire Chasm", 13, 18, "Ragefire" }, { "HOT", "Hall of Thanes", 13, 20, "Thanes" },
  { "ROL", "Ruins of Lordaeron", 15, 22, "Lordaeron" }, { "WC", "Wailing Caverns", 15, 24, "Wailing" },
  { "DM", "Deadmines", 17, 26, "Deadmines" }, { "SFK", "Shadowfang Keep", 20, 30, "Shadowfang" },
  { "BFD", "Blackfathom Deeps", 24, 32, "Blackfathom" }, { "STOCKS", "The Stockade", 25, 29, "Stockade" },
  { "EXC", "Excavation Site", 26, 33, "Excavation" }, { "DAL", "City of Dalaran", 28, 35, "Dalaran" },
  { "RFK", "Razorfen Kraul", 29, 38, "Kraul" }, { "GNOMER", "Gnomeregan", 29, 38, "Gnomeregan" },
  { "SMGY", "SM Graveyard", 30, 38, "Scarlet" }, { "SMLIB", "SM Library", 33, 41, "Scarlet" },
  { "DROWN", "The Drowned City", 35, 42, "Drowned" }, { "SMARM", "SM Armory", 36, 44, "Scarlet" },
  { "RFD", "Razorfen Downs", 37, 46, "Downs" }, { "SMCATH", "SM Cathedral", 38, 46, "Scarlet" },
  { "KROL", "Krol'dok Stronghold", 40, 47, "Krol" }, { "ULDA", "Uldaman", 41, 51, "Uldaman" },
  { "ZF", "Zul'Farrak", 44, 54, "Farrak" }, { "MARA", "Maraudon", 46, 55, "Maraudon" },
  { "ALCAZ", "Alcaz Prison", 48, 55, "Alcaz" }, { "ST", "Sunken Temple", 50, 60, "Temple" },
  { "BRD", "Blackrock Depths", 52, 60, "Depths" }, { "DME", "Dire Maul East", 54, 60, "Dire Maul" },
  { "LBRS", "Lower Blackrock Spire", 55, 60, "Spire" }, { "BMH", "Blackmaw Hold", 55, 60, "Blackmaw" },
  { "DMW", "Dire Maul West", 56, 60, "Dire Maul" }, { "DMN", "Dire Maul North", 56, 60, "Dire Maul" },
  { "SHAPER", "Shaper's Terrace", 58, 60, "Shaper" }, { "STRATL", "Stratholme Main Gate", 58, 60, "Stratholme" },
  { "STRATU", "Stratholme Service Gate", 58, 60, "Stratholme" }, { "SCHOLO", "Scholomance", 58, 60, "Scholomance" },
  { "UBRS", "Upper Blackrock Spire", 59, 60, "Spire" },
}
local BYKEY = {}
for _, d in ipairs(DUNGEONS) do BYKEY[d[1]] = d end
ns.dungeonByKey = BYKEY

local function myWants()
  db().myWants = db().myWants or {}
  local lvl = UnitLevel("player") or 0
  for k, exp in pairs(db().myWants) do
    local d = BYKEY[k]
    if not d or exp < time() or lvl > d[4] then db().myWants[k] = nil end
  end
  return db().myWants
end
local function wantsString()
  local p = {}
  for k, exp in pairs(myWants()) do p[#p + 1] = k .. ":" .. exp end
  return table.concat(p, ",")
end
local function broadcastWants()
  local ts = time()
  db().wants = db().wants or {}
  local copy = {}
  for k, v in pairs(myWants()) do copy[k] = v end
  db().wants[ns.me()] = { ts = ts, level = UnitLevel("player"), items = copy }
  ns.send("W" .. SEP .. ts .. SEP .. (UnitLevel("player") or 0) .. SEP .. wantsString())
end

ns.handlers.W = function(sender, f)
  local ts = tonumber(f[1]) or 0
  db().wants = db().wants or {}
  local cur = db().wants[sender]
  if cur and (cur.ts or 0) > ts then return end
  local items = {}
  for k, exp in (f[3] or ""):gmatch("(%w+):(%d+)") do items[k] = tonumber(exp) end
  local lvl = UnitLevel("player") or 0
  for k in pairs(items) do
    local d = BYKEY[k]
    if d and not (cur and cur.items and cur.items[k]) and lvl >= d[3] and lvl <= d[4] then
      print(GREEN .. "Guild Board|r: " .. short(sender) .. " wants " .. d[2] .. " (you're in range)")
    end
  end
  db().wants[sender] = { ts = ts, level = tonumber(f[2]) or 0, items = items }
end

local function toggleWant(k)
  if ns.featureOff("dungeons") then print(GREEN .. "Guild Board|r: dungeon flags are switched off right now."); return end
  local w = myWants()
  if w[k] then w[k] = nil else w[k] = time() + WANT_HOURS * 3600 end
  broadcastWants()
  if ns.refreshPicker then ns.refreshPicker() end
end

ns.wantsText = function()
  local L = { "", "DUNGEONS (click the minimap button to flag one)" }
  local any = false
  local now = time()
  local all = {}
  for k, v in pairs(db().wants or {}) do all[k] = v end
  all[ns.me()] = { level = UnitLevel("player"), items = myWants() }
  for _, d in ipairs(DUNGEONS) do
    local want, range = {}, {}
    for who, w in pairs(all) do
      local exp = w.items and w.items[d[1]]
      if exp and exp > now and (w.level or 0) <= d[4] then want[#want + 1] = short(who) .. " (" .. math.floor((exp - now) / 3600) .. "h)" end
    end
    if #want > 0 then
      any = true
      for key, m in pairs((GuildBoardDB and GuildBoardDB.members) or {}) do
        if key ~= ns.me() and (m.level or 0) >= d[3] and (m.level or 0) <= d[4] then range[#range + 1] = short(key) end
      end
      local lv = UnitLevel("player") or 0
      if lv >= d[3] and lv <= d[4] then range[#range + 1] = "you" end
      table.sort(want); table.sort(range)
      L[#L + 1] = string.format("%s (%d-%d): wants %s", d[2], d[3], d[4], table.concat(want, ", "))
      L[#L + 1] = "    in range: " .. table.concat(range, ", ")
    end
  end
  if not any then L[#L + 1] = "nobody has flagged a dungeon" end
  return table.concat(L, "\n")
end

-- ===== minimap button and picker =====
local picker
local function buildPicker()
  picker = CreateFrame("Frame", "GuildBoardPicker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  picker:SetSize(230, 40); picker:SetFrameStrata("DIALOG")
  if picker.SetBackdrop then
    picker:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    picker:SetBackdropColor(0, 0, 0, 0.92)
  end
  picker:EnableMouse(true)
  picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  picker.title:SetPoint("TOP", 0, -8)
  picker.rows = {}
  local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  tinsert(UISpecialFrames, "GuildBoardPicker")
  picker:Hide()
end

ns.refreshPicker = function()
  if not picker or not picker:IsShown() then return end
  local lvl = UnitLevel("player") or 0
  local w = myWants()
  for _, r in ipairs(picker.rows) do r:Hide() end
  local n = 0
  for _, d in ipairs(DUNGEONS) do
    if lvl >= d[3] - 2 and lvl <= d[4] then
      n = n + 1
      local r = picker.rows[n]
      if not r then
        r = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
        r:SetSize(22, 22)
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.label:SetPoint("LEFT", r, "RIGHT", 2, 0)
        picker.rows[n] = r
      end
      r:SetPoint("TOPLEFT", 10, -26 - (n - 1) * 22)
      r.label:SetText(d[2] .. GRAY .. "  " .. d[3] .. "-" .. d[4] .. "|r")
      r:SetChecked(w[d[1]] ~= nil)
      r:SetScript("OnClick", function() toggleWant(d[1]) end)
      r:Show()
    end
  end
  picker.title:SetText(n > 0 and "Dungeons I want to run" or "No dungeons in your level range")
  picker:SetHeight(40 + n * 22)
end

local function togglePicker(anchor)
  if not picker then buildPicker() end
  if picker:IsShown() then picker:Hide(); return end
  picker:ClearAllPoints(); picker:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
  picker:Show(); ns.refreshPicker()
end

-- right-click menu on the minimap button
local menu
local function toggleMenu(anchor)
  if not menu then
    menu = CreateFrame("Frame", "GuildBoardMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetSize(150, 118); menu:SetFrameStrata("DIALOG")
    if menu.SetBackdrop then
      menu:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      menu:SetBackdropColor(0, 0, 0, 0.92)
    end
    local items = {
      { "Tracker", function() if ns.toggleTracker then ns.toggleTracker() end end },
      { "Party tab", function() if ns.partySync then ns.partySync() end end },
      { "Guild window", function() SlashCmdList["GUILDBOARD"]("") end },
      { "Character Card", function() if ns.paste then ns.paste() end end },
    }
    -- Kris's private Claude Tasks list, only when that addon is installed
    if SlashCmdList and SlashCmdList["CLAUDETASKS"] then
      table.insert(items, 1, { "Claude list", function() SlashCmdList["CLAUDETASKS"]("") end })
    end
    menu:SetHeight(16 + #items * 26)
    for i, it in ipairs(items) do
      local b = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
      b:SetSize(134, 22); b:SetPoint("TOP", 0, -8 - (i - 1) * 26); b:SetText(it[1])
      b:SetScript("OnClick", function() menu:Hide(); local ok, err = pcall(it[2]); if not ok then print("Guild Board: " .. tostring(err)) end end)
    end
    tinsert(UISpecialFrames, "GuildBoardMenu")
  end
  if menu:IsShown() then menu:Hide(); return end
  menu:ClearAllPoints(); menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0); menu:Show()
end

local function makeMinimapButton()
  if not Minimap then return end
  local b = CreateFrame("Button", "GuildBoardMinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore"); icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local function place()
    local a = math.rad(db().mmAngle or 200)
    -- ride just outside the minimap's edge (the modern minimap is bigger than the old fixed 80 px radius)
    local r = ((Minimap:GetWidth() or 140) / 2) + 14
    b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  place()
  b:SetScript("OnDragStart", function()
    b:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter(); local s = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      db().mmAngle = math.deg(math.atan2(cy / s - my, cx / s - mx)); place()
    end)
  end)
  b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, btn)
    if IsShiftKeyDown() and ns.paste then ns.paste()
    elseif btn == "RightButton" then toggleMenu(b) else togglePicker(b) end
  end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(b, "ANCHOR_LEFT"); GameTooltip:SetText("Guild Board")
    GameTooltip:AddLine("Left-click: pick dungeons you want to run", 1, 1, 1)
    GameTooltip:AddLine("Right-click: tracker, party tab, guild window, Character Card", 1, 1, 1)
    GameTooltip:AddLine("Shift+click: Character Card (copy your character to paste)", 1, 1, 1)
    GameTooltip:AddLine("Alt+click any item: I need this", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ===== wiring =====
ns.broadcastMore = function()
  C_Timer.After(2, function() pcall(broadcastGear, true) end)
  C_Timer.After(6, function() pcall(broadcastWants) end)
end

local inside, kills = nil, 0
local function checkInstance()
  local name, itype = GetInstanceInfo()
  if itype == "party" or itype == "raid" then
    if inside ~= name then inside, kills = name, 0 end
    return
  end
  if inside and kills >= 3 then
    local done = {}
    for k in pairs(myWants()) do
      local d = BYKEY[k]
      if d and inside:find(d[5], 1, true) then myWants()[k] = nil; done[#done + 1] = d[2] end
    end
    if #done > 0 then
      print(GREEN .. "Guild Board|r: " .. table.concat(done, ", ") .. " done. Took it off your list.")
      pcall(broadcastWants)
    end
  end
  inside, kills = nil, 0
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "ENCOUNTER_END", "BOSS_KILL", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
local gearTimer
ev:SetScript("OnEvent", ns.guard("extras", function(_, e, a1, a2, a3, a4, a5)
  if e == "PLAYER_LOGIN" then
    pcall(makeMinimapButton)
    C_Timer.NewTicker(600, function() local before = wantsString(); myWants(); if wantsString() ~= before then pcall(broadcastWants) end end)
  elseif e == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(2, function() pcall(checkInstance) end)
  elseif e == "PLAYER_EQUIPMENT_CHANGED" then
    if gearTimer then return end
    gearTimer = true
    C_Timer.After(10, function() gearTimer = nil; pcall(broadcastGear, false) end)
  elseif e == "PLAYER_LEVEL_UP" then
    C_Timer.After(5, function() pcall(broadcastGear, true); pcall(broadcastWants) end)
  elseif e == "BOSS_KILL" or (e == "ENCOUNTER_END" and a5 == 1) then
    if inside then kills = kills + 1 end
  end
end))
