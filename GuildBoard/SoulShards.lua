-- Guild Board: Soul Shard button (John's ask).
--   Warlocks get a small draggable "Soul Shards" button whenever they carry shards. Click it to delete ONE shard
--   (the game only allows one delete per click). Drag to move, the X hides it until your next login.
--   Not a warlock? /gb shards turns it on for that character so you can test it (and off again).

local _, ns = ...
local SHARD = 6265
local GREEN, GRAY = "|cff33ff99", "|cff9d9d9d"

local function store()
  if not ns.db then return {} end
  local d = ns.db()
  d.shards = type(d.shards) == "table" and d.shards or {}
  return d.shards
end
local function isLock() local _, c = UnitClass("player"); return c == "WARLOCK" end
local function testOn() return store()["test:" .. tostring(ns.me and ns.me())] == true end

local C = C_Container
local function numSlots(b) return tonumber((C and C.GetContainerNumSlots and C.GetContainerNumSlots(b)) or (GetContainerNumSlots and GetContainerNumSlots(b))) or 0 end
local function info(b, s) if C and C.GetContainerItemInfo then return C.GetContainerItemInfo(b, s) end end

-- every shard stack in your bags (bag 0-5 covers a soul bag)
local function shards()
  local out, total = {}, 0
  for b = 5, 0, -1 do
    for s = numSlots(b), 1, -1 do
      local it = info(b, s)
      if it and it.itemID == SHARD and not it.isLocked then
        out[#out + 1] = { b = b, s = s, n = it.stackCount or 1 }
        total = total + (it.stackCount or 1)
      end
    end
  end
  -- shards in regular bags go before the soul bag
  table.sort(out, function(x, y) return x.b < y.b end)
  return out, total
end

local btn, hidden
local function deleteOne()
  if InCombatLockdown and InCombatLockdown() then return end
  local list = shards()
  local st = list[1]                           -- backpack / regular bags first, so a soul bag empties last
  if not st then return end
  ClearCursor()
  if st.n > 1 then
    if C and C.SplitContainerItem then C.SplitContainerItem(st.b, st.s, 1) else SplitContainerItem(st.b, st.s, 1) end
  else
    if C and C.PickupContainerItem then C.PickupContainerItem(st.b, st.s) else PickupContainerItem(st.b, st.s) end
  end
  if CursorHasItem and CursorHasItem() then DeleteCursorItem() end
end

local function refresh()
  if not btn then return end
  local _, total = shards()
  local want = (isLock() or testOn()) and not hidden and (total > 0 or testOn())
  btn:SetShown(want and true or false)
  btn.text:SetText("Soul Shards: " .. total)
  btn.del:SetEnabled(total > 0)
end
ns.refreshShards = refresh

local function build()
  if btn then return end
  btn = CreateFrame("Frame", "GuildBoardShards", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  btn:SetSize(170, 52); btn:SetFrameStrata("MEDIUM"); btn:SetClampedToScreen(true)
  if btn.SetBackdrop then
    btn:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    btn:SetBackdropColor(0.08, 0.02, 0.12, 0.9); btn:SetBackdropBorderColor(0.6, 0.3, 0.9, 0.9)
  end
  local p = store().pos
  if p then btn:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else btn:SetPoint("CENTER", 300, -120) end
  btn:EnableMouse(true); btn:SetMovable(true); btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", btn.StartMoving)
  btn:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); local a, _, _, x, y = self:GetPoint(); store().pos = { a, x, y } end)
  local icon = btn:CreateTexture(nil, "ARTWORK"); icon:SetSize(20, 20); icon:SetPoint("TOPLEFT", 8, -6)
  icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(SHARD)) or "Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
  btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); btn.text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  local x = CreateFrame("Button", nil, btn, "UIPanelCloseButton"); x:SetSize(20, 20); x:SetPoint("TOPRIGHT", 0, 0)
  x:SetScript("OnClick", function() hidden = true; btn:Hide() end)
  btn.del = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate"); btn.del:SetSize(150, 20); btn.del:SetPoint("BOTTOM", 0, 6)
  btn.del:SetText("Delete 1 shard")
  btn.del:SetScript("OnClick", function() ns.safe("shards", deleteOne) end)
  btn.del:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Soul Shards", 1, 0.82, 0)
    GameTooltip:AddLine("Each click deletes one shard for good (the game allows one per click). Not in combat.", 1, 1, 1, true)
    GameTooltip:AddLine("Drag the box to move it. X hides it until you log in again.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  btn.del:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:Hide()
end

-- /gb shards: test mode for non-warlocks (hooked into the main /gb command)
ns.shardsCmd = function()
  local k = "test:" .. tostring(ns.me and ns.me())
  store()[k] = not (store()[k] == true) or nil
  hidden = false; build(); refresh()
  print(GREEN .. "Guild Board|r Soul Shard button test mode " .. (store()[k] and "ON" or "OFF") .. GRAY .. " (this character only)|r")
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then ns.safe("shards", build) end
  ns.safe("shards", refresh)
end)
