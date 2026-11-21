-- Guild Board: Auto-roll (right-click the minimap button > Auto-roll to turn it on or off, per character).
--   When ON, group loot rolls get handled for you:
--     Bind on Equip            -> left alone, you roll yourself (they sell on the AH)
--     Quest items              -> left alone
--     Gear you can Need that is an upgrade (or could be tank/healer swap gear) -> left alone so you can Need it
--     Other gear               -> Greed
--     Everything else          -> Pass
--   Turning it ON also turns on auto loot. Every auto roll prints one line in chat.

local _, ns = ...
local GREEN, GRAY, YELLOW = "|cff33ff99", "|cff9d9d9d", "|cffffff00"
local PASS, GREED = 0, 2

local function store()
  if not (ns.db and ns.me) then return {} end
  local d = ns.db()
  d.autoRoll = type(d.autoRoll) == "table" and d.autoRoll or {}
  return d.autoRoll
end
ns.autoRollOn = function() return store()[ns.me()] == true end

ns.toggleAutoRoll = function()
  local s, me = store(), ns.me()
  s[me] = not (s[me] == true) or nil
  if s[me] and SetCVar then SetCVar("autoLootDefault", "1") end
  print(GREEN .. "Guild Board|r auto-roll is " .. (s[me] and "ON" .. GRAY .. " (BoE, quest items and upgrades stay manual; Greed other gear, Pass the rest)|r" or "OFF"))
end

local function info(link)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not get then return end
  return get(link)
end
local function instant(link)
  local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not get then return end
  local _, _, _, equipLoc, _, classID = get(link)
  return classID, equipLoc
end

-- returns PASS, GREED, or nil (leave it to you) plus a reason
local function decide(rollID)
  local _, _, _, quality, bop, canNeed, canGreed = GetLootRollItemInfo(rollID)
  local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
  if not link then return nil, "no item info" end
  local bindType = select(14, info(link))
  local classID, equipLoc = instant(link)
  if bindType == 2 or (not bop and (classID == 2 or classID == 4) and bindType ~= 1) then return nil, "BoE, your call" end
  if classID == 12 or bindType == 4 then return nil, "quest item" end
  if (quality or 0) >= 4 then return nil, "epic, your call" end
  local gear = (classID == 2 or classID == 4) and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
  if gear then
    if canNeed and ns.junkIsUpgrade then
      local _, cls = UnitClass("player")
      local up, why = ns.junkIsUpgrade(link, cls, UnitLevel("player") or 1)
      if up and why ~= "not gear" then return nil, "upgrade (" .. why .. ")" end
    end
    if canGreed then return GREED, "gear" end
    return PASS, "gear, Greed not allowed"
  end
  return PASS, "not gear"
end

local mine = {}                                   -- rollIDs we rolled on, so we only confirm our own
local ev = CreateFrame("Frame")
ev:RegisterEvent("START_LOOT_ROLL")
ev:RegisterEvent("CONFIRM_LOOT_ROLL")
ev:SetScript("OnEvent", function(_, e, rollID, rollType)
  if not ns.autoRollOn() then return end
  ns.safe("autoroll", function()
    if e == "START_LOOT_ROLL" then
      local roll, why = decide(rollID)
      local link = GetLootRollItemLink(rollID) or "item"
      if roll == nil then
        print(GREEN .. "Guild Board|r " .. link .. YELLOW .. " roll it yourself|r" .. GRAY .. " (" .. why .. ")|r")
        return
      end
      mine[rollID] = roll
      RollOnLoot(rollID, roll)
      print(GREEN .. "Guild Board|r " .. (roll == GREED and "Greed" or "Pass") .. " on " .. link .. GRAY .. " (" .. why .. ")|r")
    elseif e == "CONFIRM_LOOT_ROLL" and mine[rollID] ~= nil and mine[rollID] == rollType then
      ConfirmLootRoll(rollID, rollType)
      if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_LOOT_ROLL") end
      mine[rollID] = nil
    end
  end)
end)
