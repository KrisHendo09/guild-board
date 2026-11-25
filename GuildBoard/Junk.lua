-- Guild Board: Sell junk gear at a vendor.
--   When a vendor window opens, every SOULBOUND piece of gear in your bags that is not an upgrade for your class
--   gets a red border (default bags and Bagnon), and a "Sell junk gear" button appears on the vendor window.
--   Not an upgrade means: your class can't use it (armor type, weapon skill, wrong main stat), or it scores lower
--   than what you have equipped in that slot, using simple stat weights for your class.
--   Swap gear: anything in an Equipment Manager set, anything you marked Keep (right-click the button), and
--   anything that would be an upgrade for your class's other role (tank or healer swap sets) is left alone.
--   Safety: never touches Bind on Equip, epics or better, items with no vendor price, shirts, tabards, fishing poles,
--   or gear for a slot you have empty. Sells at most 12 per click, so anything sold by mistake is still in Buyback.

local _, ns = ...
local MAXSELL = 12
local GREEN, GRAY, GOLD = "|cff33ff99", "|cff9d9d9d", "|cffffd100"

local function itemInfo(x)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not get then return end
  return get(x)
end
local function C() return C_Container end
local function numSlots(b) return (C_Container and C_Container.GetContainerNumSlots(b)) or (GetContainerNumSlots and GetContainerNumSlots(b)) or 0 end
local function slotInfo(b, s)
  if C_Container and C_Container.GetContainerItemInfo then return C_Container.GetContainerItemInfo(b, s) end
end

local EQUIP = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 } }

local W = {
  WARRIOR = "One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,One-Handed Swords,Two-Handed Swords,Polearms,Staves,Daggers,Fist Weapons,Bows,Guns,Crossbows,Thrown,Shields",
  PALADIN = "One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,One-Handed Swords,Two-Handed Swords,Polearms,Shields,Librams",
  HUNTER = "One-Handed Axes,Two-Handed Axes,One-Handed Swords,Two-Handed Swords,Polearms,Staves,Daggers,Fist Weapons,Bows,Guns,Crossbows,Thrown",
  ROGUE = "Daggers,Fist Weapons,One-Handed Swords,One-Handed Maces,Bows,Guns,Crossbows,Thrown",
  SHAMAN = "One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,Staves,Daggers,Fist Weapons,Shields,Totems",
  DRUID = "One-Handed Maces,Two-Handed Maces,Staves,Daggers,Fist Weapons,Idols",
  MAGE = "Staves,Daggers,One-Handed Swords,Wands", PRIEST = "Staves,One-Handed Maces,Daggers,Wands",
  WARLOCK = "Staves,Daggers,One-Handed Swords,Wands" }

local function armorFor(cls, level)
  if cls == "WARRIOR" or cls == "PALADIN" then return level >= 40 and "Plate" or "Mail" end
  if cls == "HUNTER" or cls == "SHAMAN" then return level >= 40 and "Mail" or "Leather" end
  if cls == "ROGUE" or cls == "DRUID" then return "Leather" end
  return "Cloth"
end

-- rough leveling stat weights per class (points per stat). DPS is weapon damage per second.
local WT = {
  WARRIOR = { STR = 2, AGI = 1.2, STA = 1, AP = 1, ARMOR = 0.02, DPS = 6 },
  PALADIN = { STR = 2, STA = 1.2, INT = 1, AGI = 0.8, SPI = 0.3, AP = 1, ARMOR = 0.02, DPS = 5 },
  SHAMAN = { STR = 2, AGI = 1, INT = 1.3, STA = 1, SPI = 0.3, AP = 1, ARMOR = 0.02, DPS = 6 },
  HUNTER = { AGI = 2, STA = 1, INT = 0.6, SPI = 0.3, AP = 1, RAP = 1, ARMOR = 0.01, DPS = 3 },
  ROGUE = { AGI = 2, STR = 1, STA = 1, AP = 1, ARMOR = 0.01, DPS = 6 },
  DRUID = { STR = 1.5, AGI = 1.5, INT = 1, STA = 1, SPI = 0.6, AP = 1, ARMOR = 0.01, DPS = 2 },
  MAGE = { INT = 1.5, SPI = 1, STA = 1, SP = 1.6, ARMOR = 0.005 },
  PRIEST = { INT = 1.5, SPI = 1.2, STA = 1, SP = 1.6, ARMOR = 0.005 },
  WARLOCK = { INT = 1.3, SPI = 0.8, STA = 1.3, SP = 1.6, ARMOR = 0.005 },
}
-- other roles people carry swap gear for. Item counts as kept if it beats what you wear under any of these.
local TANKW = { STA = 2, ARMOR = 0.06, DEF = 2, BLOCK = 1, DODGE = 2, PARRY = 2, STR = 0.8, AGI = 0.8 }
local HEALW = { INT = 2, SPI = 1, STA = 0.5, SP = 2 }
local ALT = { WARRIOR = { { TANKW, "tank" } }, PALADIN = { { TANKW, "tank" }, { HEALW, "healer" } },
  DRUID = { { TANKW, "tank" }, { HEALW, "healer" } }, SHAMAN = { { HEALW, "healer" } } }

local MAIN = { WARRIOR = { STR = 1, AGI = 1 }, PALADIN = { STR = 1, INT = 1 }, HUNTER = { AGI = 1 }, ROGUE = { AGI = 1 },
  SHAMAN = { STR = 1, AGI = 1, INT = 1 }, DRUID = { STR = 1, AGI = 1, INT = 1 }, MAGE = { INT = 1 }, PRIEST = { INT = 1 }, WARLOCK = { INT = 1 } }

local function stats(link)
  local get = (C_Item and C_Item.GetItemStats) or GetItemStats
  local raw = get and get(link) or {}
  local s = {}
  for k, v in pairs(raw) do
    local key
    if k:find("STRENGTH") then key = "STR" elseif k:find("AGILITY") then key = "AGI" elseif k:find("INTELLECT") then key = "INT"
    elseif k:find("STAMINA") then key = "STA" elseif k:find("SPIRIT") then key = "SPI"
    elseif k:find("RANGED_ATTACK_POWER") then key = "RAP" elseif k:find("ATTACK_POWER") then key = "AP"
    elseif k:find("SPELL_POWER") or k:find("SPELL_DAMAGE") then key = "SP"
    elseif k:find("HEALING") then key = "SP"
    elseif k:find("DEFENSE") then key = "DEF" elseif k:find("BLOCK") then key = "BLOCK"
    elseif k:find("DODGE") then key = "DODGE" elseif k:find("PARRY") then key = "PARRY"
    elseif k:find("DAMAGE_PER_SECOND") then key = "DPS" elseif k == "RESISTANCE0_NAME" then key = "ARMOR" end
    if key then s[key] = (s[key] or 0) + (tonumber(v) or 0) end
  end
  return s
end

local function score(link, cls, wt)
  if not link then return 0 end
  local w, s, t = wt or WT[cls] or WT.WARRIOR, stats(link), 0
  for k, v in pairs(s) do t = t + (w[k] or 0) * v end
  return t
end

local function canUse(cls, level, equipLoc, itemClass, subType, link)
  if itemClass == "Armor" then
    if equipLoc == "INVTYPE_SHIELD" then return (W[cls] or ""):find("Shields", 1, true) ~= nil end
    if (subType == "Cloth" or subType == "Leather" or subType == "Mail" or subType == "Plate") and equipLoc ~= "INVTYPE_CLOAK" then
      local want = armorFor(cls, level)
      local order = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }
      if order[subType] > order[want] then return false end        -- can't wear it
      if order[subType] < order[want] then return "lower" end      -- can wear it, but it's the wrong armor type
    end
  elseif itemClass == "Weapon" then
    if not (W[cls] or ""):find(subType or "?", 1, true) then return false end
  end
  local s, ok, any = stats(link), false, false
  for _, k in ipairs({ "STR", "AGI", "INT" }) do
    if s[k] then any = true; if MAIN[cls] and MAIN[cls][k] then ok = true end end
  end
  if any and not ok then return false end
  return true
end

-- returns true when this bag item should be kept (could be an upgrade), plus a reason for the tooltip
local function isUpgrade(link, cls, level)
  local _, _, quality, _, minLevel, itemClass, subType, _, equipLoc = itemInfo(link)
  local slots = equipLoc and EQUIP[equipLoc]
  if not slots then return true, "not gear" end
  local use = canUse(cls, level, equipLoc, itemClass, subType, link)
  if not use then return false, "your class can't use it" end
  if use == "lower" then return false, "wrong armor type for you" end
  if (minLevel or 0) > level then return true, "for later" end
  local function compare(wt)
    local mine, have = score(link, cls, wt)
    if equipLoc == "INVTYPE_2HWEAPON" then
      if not GetInventoryItemLink("player", 16) then return nil end
      have = score(GetInventoryItemLink("player", 16), cls, wt) + score(GetInventoryItemLink("player", 17), cls, wt)
    else
      for _, sl in ipairs(slots) do
        local l = GetInventoryItemLink("player", sl)
        if not l then return nil end
        local v = score(l, cls, wt)
        if not have or v < have then have = v end
      end
    end
    return mine, have or 0
  end
  local mine, have = compare()
  if not mine then return true, "slot empty" end
  if mine > have then return true, "better than what you wear" end
  for _, alt in ipairs(ALT[cls] or {}) do
    local m, h = compare(alt[1])
    if m and m > h then return true, "could be " .. alt[2] .. " swap gear", "swap" end
  end
  return false, string.format("worse than what you wear (%d vs %d)", math.floor(mine + 0.5), math.floor(have + 0.5))
end

-- items you told it to keep, per character: GuildBoardDB.junkKeep[you][itemID] = true
local function keepTable()
  if not (ns.db and ns.me) then return {} end
  local d = ns.db()
  d.junkKeep = type(d.junkKeep) == "table" and d.junkKeep or {}
  d.junkKeep[ns.me()] = d.junkKeep[ns.me()] or {}
  return d.junkKeep[ns.me()]
end

-- item IDs in any Equipment Manager set
local function setItems()
  local ids = {}
  local E = C_EquipmentSet
  if not (E and E.GetEquipmentSetIDs and E.GetItemIDs) then return ids end
  local ok, sets = pcall(E.GetEquipmentSetIDs)
  if not ok or type(sets) ~= "table" then return ids end
  for _, sid in ipairs(sets) do
    local ok2, items = pcall(E.GetItemIDs, sid)
    if ok2 and type(items) == "table" then for _, id in pairs(items) do if type(id) == "number" and id > 0 then ids[id] = true end end end
  end
  return ids
end


-- shared upgrade check for AuctionBoE.lua and AutoRoll.lua: accepts the class token or the class name
ns.junkIsUpgrade = function(link, cls, level)
  local _, tok = UnitClass("player")
  if not WT[cls] then cls = tok end
  return isUpgrade(link, cls, level or UnitLevel("player") or 1)
end

local list, kept, ahWorth = {}, {}, {}
local function boeOn() return ns.db and ns.db().junkBoE and true or false end
local function ahPrice(link)
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (A and A.GetAuctionPriceByItemLink) then return end
  local ok, v = pcall(A.GetAuctionPriceByItemLink, "GuildBoard", link)
  if ok and type(v) == "number" and v > 0 then return v end
end
local function scan()
  wipe(list); wipe(kept); wipe(ahWorth)
  local boe = boeOn()
  local keep, sets = keepTable(), setItems()
  local _, cls = UnitClass("player")
  local level = UnitLevel("player") or 1
  for b = 0, 4 do
    for s = 1, numSlots(b) do
      local it = slotInfo(b, s)
      if it and it.hyperlink and (it.isBound or boe) and not it.isLocked then
        local _, _, quality, _, _, itemClass, subType, _, equipLoc, _, sellPrice = itemInfo(it.hyperlink)
        quality = it.quality or quality
        if equipLoc and EQUIP[equipLoc] and (quality or 0) <= 3 and (sellPrice or 0) > 0
           and equipLoc ~= "INVTYPE_BODY" and equipLoc ~= "INVTYPE_TABARD" and subType ~= "Fishing Poles" then
          local id = it.itemID
          local up, why, swap = isUpgrade(it.hyperlink, cls, level)
          if id and keep[id] then kept[#kept + 1] = { link = it.hyperlink, id = id, why = "you marked it Keep", mine = true }
          elseif id and sets[id] then kept[#kept + 1] = { link = it.hyperlink, id = id, why = "in an equipment set" }
          elseif swap then kept[#kept + 1] = { link = it.hyperlink, id = id, why = why }
          elseif not up and not it.isBound and (function()
              local ah = ahPrice(it.hyperlink)
              return ah and ah >= 10000 and ah >= sellPrice * 3
            end)() then
            ahWorth[#ahWorth + 1] = { link = it.hyperlink, ah = ahPrice(it.hyperlink) }
          elseif not up then
            list[#list + 1] = { b = b, s = s, link = it.hyperlink, id = id, price = sellPrice * (it.stackCount or 1), why = why }
          end
        end
      end
    end
  end
  return list
end

-- ===== red borders on bag buttons (Blizzard bags and Bagnon) =====
local marked = {}
local function clearMarks()
  for f in pairs(marked) do if f.gbJunk then f.gbJunk:Hide() end end
  wipe(marked)
end
local function buttonPos(f)
  local b
  if f.GetBagID then b = f:GetBagID() elseif f.GetBag then b = f:GetBag() elseif type(f.bag) == "number" then b = f.bag end
  if type(b) ~= "number" or not f.GetID then return end
  return b, f:GetID()
end
-- Some frames answer IsObjectType/IsVisible with a secret value that errors when tested, so test inside pcall.
local function shownButton(f)
  if f.IsObjectType and f:IsObjectType("Button") and f:IsVisible() then return true end
  return false
end
local function mark()
  clearMarks()
  if #list == 0 then return end
  local want = {}
  for _, e in ipairs(list) do want[e.b .. ":" .. e.s] = true end
  local f = EnumerateFrames()
  while f do
    local okShown, shown = pcall(shownButton, f)
    if okShown and shown then
      local ok, b, s = pcall(buttonPos, f)
      if ok and b and s and want[b .. ":" .. s] then
        if not f.gbJunk then
          local t = f:CreateTexture(nil, "OVERLAY")
          t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); t:SetBlendMode("ADD")
          t:SetVertexColor(1, 0.15, 0.15); t:SetPoint("CENTER")
          local w = f:GetWidth() or 37; t:SetSize(w * 1.8, w * 1.8)
          f.gbJunk = t
        end
        f.gbJunk:Show(); marked[f] = true
      end
    end
    f = EnumerateFrames(f)
  end
end

-- ===== the vendor button =====
local btn
local function money(c)
  return (GetCoinTextureString and GetCoinTextureString(c)) or (math.floor(c / 10000) .. "g " .. math.floor(c % 10000 / 100) .. "s")
end
local function refresh()
  if not btn then return end
  scan()
  local total = 0
  for _, e in ipairs(list) do total = total + e.price end
  local word = boeOn() and "Sell junk + BoE (" or "Sell junk gear ("
  btn:SetText(#list > 0 and (word .. #list .. ")") or "No junk gear")
  if btn.boe then btn.boe:SetChecked(boeOn()) end
  btn:SetEnabled(#list > 0)
  btn.total = total
  mark()
end

local function sell()
  if not (MerchantFrame and MerchantFrame:IsShown()) then return end
  scan()
  local n = math.min(#list, MAXSELL)
  local sold = 0
  for i = 1, n do
    local e = list[i]
    C_Timer.After(0.25 * (i - 1), function()
      if MerchantFrame:IsShown() then
        local it = slotInfo(e.b, e.s)
        if it and it.hyperlink == e.link then
          if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(e.b, e.s) else UseContainerItem(e.b, e.s) end
        end
      end
    end)
    sold = sold + e.price
  end
  print(GREEN .. "Guild Board|r sold " .. n .. " pieces of junk gear for " .. money(sold) .. (#list > n and (". " .. (#list - n) .. " more: click again.") or ".") .. GRAY .. " Changed your mind? It's in the Buyback tab.|r")
  C_Timer.After(0.25 * n + 0.5, function() ns.safe("junk", refresh) end)
end

local function build()
  if btn or not MerchantFrame then return end
  btn = CreateFrame("Button", "GuildBoardSellJunk", MerchantFrame, "UIPanelButtonTemplate")
  btn:SetSize(170, 22)
  btn:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -40, -28)
  btn:SetFrameStrata("HIGH")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(_, mb)
    if mb == "RightButton" then ns.safe("junk", ns.toggleJunkKeep) else ns.safe("junk", sell) end
  end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(boeOn() and "Sell soulbound + BoE gear that isn't an upgrade" or "Sell soulbound gear that isn't an upgrade", 1, 0.82, 0)
    for i, e in ipairs(list) do
      if i > 15 then GameTooltip:AddLine("+" .. (#list - 15) .. " more", 0.6, 0.6, 0.6); break end
      GameTooltip:AddDoubleLine(e.link, e.why, 1, 1, 1, 0.6, 0.6, 0.6)
    end
    if #list > 0 then GameTooltip:AddLine("Total " .. money(self.total or 0) .. ". Sells 12 per click; mistakes stay in Buyback.", 0.5, 0.8, 1, true) end
    if #kept > 0 then GameTooltip:AddLine("Leaving " .. #kept .. " swap/kept piece" .. (#kept > 1 and "s" or "") .. " alone.", 0.4, 1, 0.4) end
    if #ahWorth > 0 then
      GameTooltip:AddLine("Skipping " .. #ahWorth .. " BoE worth more on the AH:", 1, 0.5, 0)
      for i, e in ipairs(ahWorth) do if i > 5 then break end; GameTooltip:AddDoubleLine(e.link, money(e.ah), 1, 1, 1, 1, 0.82, 0) end
    end
    GameTooltip:AddLine("Right-click: pick what to keep.", 0.5, 0.8, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- BoE toggle: tick it to sell Bind on Equip gear too (crafted leveling stuff)
  local cb = CreateFrame("CheckButton", "GuildBoardSellBoE", btn, "UICheckButtonTemplate")
  cb:SetSize(24, 24); cb:SetPoint("RIGHT", btn, "LEFT", -2, 0)
  cb:SetChecked(boeOn())
  cb:SetScript("OnClick", function(self) ns.db().junkBoE = self:GetChecked() and true or nil; ns.safe("junk", refresh) end)
  cb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Include BoE gear", 1, 0.82, 0)
    GameTooltip:AddLine("Sells Bind on Equip pieces too, like crafted leveling gear. Upgrades, kept items and anything worth 1g+ on the AH (3x vendor) are left alone.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn.boe = cb
end

-- ===== Keep panel: right-click the sell button. One click per item, no typing. =====
local kp
local ROWS = 14
local function kpFill()
  if not kp or not kp:IsShown() then return end
  scan()
  local rows = {}
  for _, e in ipairs(list) do rows[#rows + 1] = { link = e.link, id = e.id, why = e.why, act = "Keep" } end
  for _, e in ipairs(kept) do rows[#rows + 1] = { link = e.link, id = e.id, why = e.why, act = e.mine and "Sell ok" or nil } end
  for i = 1, ROWS do
    local r, d = kp.rows[i], rows[i]
    if d then
      r.text:SetText(d.link); r.why:SetText(d.why)
      if d.act and d.id then
        r.b:SetText(d.act); r.b:Show()
        r.b:SetScript("OnClick", function()
          keepTable()[d.id] = (d.act == "Keep") or nil
          refresh(); kpFill()
        end)
      else r.b:Hide() end
      r:Show()
    else r:Hide() end
  end
  kp:SetHeight(40 + math.min(#rows, ROWS) * 20 + (#rows == 0 and 20 or 0))
  kp.empty:SetShown(#rows == 0)
end

ns.toggleJunkKeep = function()
  if not kp then
    kp = CreateFrame("Frame", "GuildBoardJunkKeep", MerchantFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    kp:SetSize(380, 80); kp:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, -20); kp:SetFrameStrata("DIALOG")
    if kp.SetBackdrop then
      kp:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      kp:SetBackdropColor(0.05, 0.04, 0.03, 0.94); kp:SetBackdropBorderColor(0.9, 0.72, 0.4, 0.8)
    end
    local t = kp:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 10, -8); t:SetText(GOLD .. "Keep or sell|r")
    local close = CreateFrame("Button", nil, kp, "UIPanelCloseButton"); close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 2, 2)
    kp.empty = kp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); kp.empty:SetPoint("TOPLEFT", 10, -32); kp.empty:SetText("No gear to sell or keep.")
    kp.rows = {}
    for i = 1, ROWS do
      local r = CreateFrame("Frame", nil, kp); r:SetSize(360, 20); r:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 20)
      r.b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.b:SetSize(62, 18); r.b:SetPoint("RIGHT", 0, 0)
      r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", 0, 0); r.text:SetWidth(150); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
      r.why = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.why:SetPoint("LEFT", r.text, "RIGHT", 4, 0); r.why:SetPoint("RIGHT", r.b, "LEFT", -4, 0); r.why:SetJustifyH("LEFT"); r.why:SetWordWrap(false)
      kp.rows[i] = r
    end
  end
  if kp:IsShown() then kp:Hide() else kp:Show(); kpFill() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function(_, e)
  if e == "MERCHANT_SHOW" then
    ns.safe("junk", build)
    C_Timer.After(0.3, function() ns.safe("junk", refresh) end)     -- give Bagnon a moment to draw its bag
  elseif e == "MERCHANT_CLOSED" then
    clearMarks(); if kp then kp:Hide() end
  elseif e == "BAG_UPDATE_DELAYED" and MerchantFrame and MerchantFrame:IsShown() then
    ns.safe("junk", refresh); ns.safe("junk", kpFill)
  end
end)
