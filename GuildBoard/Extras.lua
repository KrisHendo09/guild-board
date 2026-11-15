-- Guild Board extras: gear upgrades, assumed profession mats, dungeon wants. All in game, nothing goes to Discord.
--   Gear: hover any gear that isn't Bind on Pickup and see who in the guild it is an item level upgrade for
--         (checks armor type, weapon skills, main stat and required level).
--   Mats: yellow "Could use" lines on crafting mats that match the skill bracket a guildie is leveling.
--         Blue lines elsewhere are things someone actually asked for (Alt+click).
--   Dungeons: click the minimap button to flag dungeons you want to run. Right-click it for the Guild Board window.
--         A flag turns off when you click it again, kill the last boss, out-level the dungeon, or after 48 hours.

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
local M = {
  LW = { { 1, 75, "2318,2934,783,2320" }, { 75, 150, "2319,4232,2321" }, { 150, 200, "4234,4235,4291" }, { 200, 250, "4304,8169" }, { 250, 300, "8170" } },
  BS = { { 1, 75, "2840,2835" }, { 75, 125, "2841,3576,2836" }, { 125, 200, "3575,2838,3859" }, { 200, 250, "3860,7912" }, { 250, 300, "12359,12365" } },
  TA = { { 1, 75, "2589,2996,2320" }, { 75, 125, "2592,2997,2321" }, { 125, 200, "4306,4305,4291" }, { 200, 250, "4338,4339" }, { 250, 300, "14047" } },
  FA = { { 1, 80, "2589" }, { 80, 150, "2592" }, { 150, 210, "4306" }, { 210, 260, "4338" }, { 260, 300, "14047" } },
  AL = { { 1, 60, "2447,765,3371" }, { 60, 110, "2450,785,2453" }, { 110, 165, "2453,3355,3356,3357,3369" }, { 165, 215, "3821,3358,3818" } },
  EN = { { 1, 90, "10940,10938" }, { 90, 150, "10940,10939,10998" }, { 150, 200, "11083,11134,10978" }, { 200, 250, "11137" } },
  EG = { { 1, 75, "2840,2835,2589" }, { 75, 150, "2841,2836,2592" }, { 150, 200, "3575,2838,3859" }, { 200, 250, "3860,7912,4338" } },
}
local PROF = { Leatherworking = "LW", Blacksmithing = "BS", Tailoring = "TA", ["First Aid"] = "FA", Alchemy = "AL", Enchanting = "EN", Engineering = "EG" }
local SHORT = { LW = "LW", BS = "BS", TA = "Tailoring", FA = "First Aid", AL = "Alchemy", EN = "Enchanting", EG = "Engineering" }

local function matsLines(id)
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
          for _, b in ipairs(M[code]) do
            if rank >= b[1] and rank < b[2] and ("," .. b[3] .. ","):find("," .. id .. ",", 1, true) then
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
table.insert(ns.tipExtras, matsLines)
table.insert(ns.tipExtras, upgradeLines)

-- ===== dungeon wants =====
local DUNGEONS = {
  { "RFC", "Ragefire Chasm", 13, 18, "Taragaman the Hungerer" },
  { "WC", "Wailing Caverns", 17, 24, "Mutanus the Devourer" },
  { "DM", "The Deadmines", 17, 26, "Edwin VanCleef" },
  { "SFK", "Shadowfang Keep", 22, 30, "Archmage Arugal" },
  { "BFD", "Blackfathom Deeps", 24, 32, "Aku'mai" },
  { "STOCKS", "The Stockade", 24, 32, "Bazil Thredd" },
  { "GNOMER", "Gnomeregan", 29, 38, "Mekgineer Thermaplugg" },
  { "RFK", "Razorfen Kraul", 29, 38, "Charlga Razorflank" },
  { "SMGY", "SM Graveyard", 28, 38, "Bloodmage Thalnos" },
  { "SMLIB", "SM Library", 29, 39, "Arcanist Doan" },
  { "SMARM", "SM Armory", 32, 42, "Herod" },
  { "SMCATH", "SM Cathedral", 35, 45, "High Inquisitor Whitemane" },
  { "RFD", "Razorfen Downs", 37, 46, "Amnennar the Coldbringer" },
  { "ULDA", "Uldaman", 41, 51, "Archaedas" },
  { "ZF", "Zul'Farrak", 44, 54, "Chief Ukorz Sandscalp" },
  { "MARA", "Maraudon", 46, 55, "Princess Theradras" },
  { "ST", "Sunken Temple", 50, 56, "Shade of Eranikus" },
  { "BRD", "Blackrock Depths", 52, 60, "Emperor Dagran Thaurissan" },
}
local BYKEY = {}
for _, d in ipairs(DUNGEONS) do BYKEY[d[1]] = d end

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
    b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
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
    if btn == "RightButton" then SlashCmdList["GUILDBOARD"]("") else togglePicker(b) end
  end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(b, "ANCHOR_LEFT"); GameTooltip:SetText("Guild Board")
    GameTooltip:AddLine("Left-click: pick dungeons you want to run", 1, 1, 1)
    GameTooltip:AddLine("Right-click: guild window", 1, 1, 1)
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

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "ENCOUNTER_END", "BOSS_KILL" }) do pcall(ev.RegisterEvent, ev, e) end
local gearTimer
ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4, a5)
  if e == "PLAYER_LOGIN" then
    pcall(makeMinimapButton)
    C_Timer.NewTicker(600, function() local before = wantsString(); myWants(); if wantsString() ~= before then pcall(broadcastWants) end end)
  elseif e == "PLAYER_EQUIPMENT_CHANGED" then
    if gearTimer then return end
    gearTimer = true
    C_Timer.After(10, function() gearTimer = nil; pcall(broadcastGear, false) end)
  elseif e == "PLAYER_LEVEL_UP" then
    C_Timer.After(5, function() pcall(broadcastGear, true); pcall(broadcastWants) end)
  else
    local name = (e == "ENCOUNTER_END") and a2 or a2
    local success = (e == "BOSS_KILL") or a5 == 1
    if success and name then
      for k in pairs(myWants()) do
        if BYKEY[k][5] == name then
          myWants()[k] = nil
          print(GREEN .. "Guild Board|r: " .. BYKEY[k][2] .. " done. Took it off your list.")
          pcall(broadcastWants)
        end
      end
    end
  end
end)
