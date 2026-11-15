-- Guild Board: needs and crafters.
--   Alt+click any item (bags, chat link, auction house, recipe) to say you need it. A box asks how many.
--   Guildies with the addon see it on that item's tooltip: "Guild needs: Kris 10".
--   At a mailbox, a "Send needs" button fills in a mail to whoever needs what you are carrying. You still click Send.
--   Open your profession window once and guildies' tooltips show you as a crafter of everything you know how to make.
-- Your needs count down by themselves as the items land in your bags, and clear at zero.

local _, ns = ...
ns.handlers = ns.handlers or {}
local SEP = ns.SEP or "^"
local GOLD, GRAY, GREEN, BLUE = "|cffffd100", "|cff9d9d9d", "|cff33ff99", "|cff4fa3ff"

local function db()
  GuildBoardDB = GuildBoardDB or {}
  GuildBoardDB.needs = GuildBoardDB.needs or {}      -- [member] = { ts = n, items = { [itemID] = remaining } }
  GuildBoardDB.crafts = GuildBoardDB.crafts or {}    -- [member] = { ts = n, items = { [itemID] = true } }
  GuildBoardDB.myNeeds = GuildBoardDB.myNeeds or {}  -- [itemID] = target total count in bags + bank
  return GuildBoardDB
end

local function me()
  local name, realm = UnitFullName and UnitFullName("player")
  if not name then name = UnitName("player") end
  realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
  return realm ~= "" and (name .. "-" .. realm) or name
end
local function short(key) return (key or "?"):gsub("%-.*$", "") end
local function itemCount(id)
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, true)) or (GetItemCount and GetItemCount(id, true)) or 0
  return n or 0
end
local function itemName(id)
  local n = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)) or (GetItemInfo and GetItemInfo(id))
  return n or ("item " .. id)
end
local function idFromLink(link) return link and tonumber(tostring(link):match("item:(%d+)")) end

-- ===== my needs =====
local function myRemaining()
  local out = {}
  for id, target in pairs(db().myNeeds) do
    local left = target - itemCount(id)
    if left > 0 then out[id] = left else db().myNeeds[id] = nil end
  end
  return out
end

local function needsString()
  local parts = {}
  for id, left in pairs(myRemaining()) do parts[#parts + 1] = id .. ":" .. left end
  return table.concat(parts, ",")
end

local lastSent
local function broadcastNeeds(force)
  local s = needsString()
  if not force and s == lastSent then return end
  lastSent = s
  local ts = time()
  db().needs[me()] = { ts = ts, items = myRemaining() }
  ns.send("N" .. SEP .. ts .. SEP .. s:sub(1, 230))
end

local function setNeed(id, count)
  if not id then return end
  count = tonumber(count) or 0
  if count <= 0 then
    db().myNeeds[id] = nil
    print(GREEN .. "Guild Board|r: no longer need " .. itemName(id))
  else
    db().myNeeds[id] = itemCount(id) + count
    print(GREEN .. "Guild Board|r: you need " .. count .. " " .. itemName(id) .. ". Guildies will see it on the tooltip.")
  end
  broadcastNeeds(true)
end
ns.setNeed = setNeed

ns.handlers.N = function(sender, f)
  local ts, list = tonumber(f[1]) or 0, f[2] or ""
  local cur = db().needs[sender]
  if cur and (cur.ts or 0) > ts then return end
  local items = {}
  for id, n in list:gmatch("(%d+):(%d+)") do items[tonumber(id)] = tonumber(n) end
  db().needs[sender] = { ts = ts, items = items }
end

-- ===== what I can craft =====
local function scanRecipes()
  local found = {}
  pcall(function()
    if GetNumTradeSkills then
      for i = 1, GetNumTradeSkills() do
        local _, kind = GetTradeSkillInfo(i)
        if kind ~= "header" and kind ~= "subheader" then
          local id = idFromLink(GetTradeSkillItemLink(i)); if id then found[id] = true end
        end
      end
    end
  end)
  pcall(function()
    if GetNumCrafts then
      for i = 1, GetNumCrafts() do
        local id = idFromLink(GetCraftItemLink and GetCraftItemLink(i)); if id then found[id] = true end
      end
    end
  end)
  pcall(function()
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic then
      for _, rid in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(rid)
        if not info or info.learned then
          local sc = C_TradeSkillUI.GetRecipeSchematic(rid, false)
          if sc and sc.outputItemID then found[sc.outputItemID] = true end
        end
      end
    end
  end)
  local mine = db().myCrafts or {}
  for id in pairs(found) do mine[id] = true end   -- keep recipes from other professions already scanned
  db().myCrafts = mine
end

local function broadcastCrafts()
  local ids = {}
  for id in pairs(db().myCrafts or {}) do ids[#ids + 1] = tostring(id) end
  if #ids == 0 then return end
  table.sort(ids)
  local chunks, cur = {}, {}
  for _, id in ipairs(ids) do
    if #table.concat(cur, ",") + #id > 200 then chunks[#chunks + 1] = table.concat(cur, ","); cur = {} end
    cur[#cur + 1] = id
  end
  if #cur > 0 then chunks[#chunks + 1] = table.concat(cur, ",") end
  local ts = time()
  local items = {}
  for _, id in ipairs(ids) do items[tonumber(id)] = true end
  db().crafts[me()] = { ts = ts, items = items }
  for i, c in ipairs(chunks) do ns.send("C" .. SEP .. ts .. SEP .. i .. SEP .. #chunks .. SEP .. c) end
end

local pending = {}
ns.handlers.C = function(sender, f)
  local ts, part, total, list = tonumber(f[1]) or 0, tonumber(f[2]) or 1, tonumber(f[3]) or 1, f[4] or ""
  local cur = db().crafts[sender]
  if cur and (cur.ts or 0) >= ts then return end
  local p = pending[sender]
  if not p or p.ts ~= ts then p = { ts = ts, got = 0, items = {} }; pending[sender] = p end
  for id in list:gmatch("%d+") do p.items[tonumber(id)] = true end
  p.got = p.got + 1
  if p.got >= total then db().crafts[sender] = { ts = ts, items = p.items }; pending[sender] = nil end
end

-- ===== new version notice =====
local function myVersion()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return (get and get("GuildBoard", "Version")) or "0"
end
local function newer(a, b)   -- is version a newer than b
  local x, y = { tostring(a):match("(%d+)%.?(%d*)%.?(%d*)") }, { tostring(b):match("(%d+)%.?(%d*)%.?(%d*)") }
  for i = 1, 3 do
    local p, q = tonumber(x[i]) or 0, tonumber(y[i]) or 0
    if p ~= q then return p > q end
  end
  return false
end
local told
ns.handlers.V = function(sender, f)
  local theirs = f[1]
  if told or not theirs or not newer(theirs, myVersion()) then return end
  told = true
  C_Timer.After(8, function()
    print(GREEN .. "Guild Board|r: " .. short(sender) .. " has version " .. theirs .. " (you have " .. myVersion() .. "). Update from the link pinned in #addons: github.com/KrisHendo09/guild-board/releases/latest")
  end)
end

ns.me, ns.short, ns.db, ns.itemName = me, short, db, itemName
ns.broadcastExtra = function()
  ns.send("V" .. SEP .. myVersion())
  if ns.broadcastMore then pcall(ns.broadcastMore) end
  broadcastNeeds(true)
  C_Timer.After(4, function() pcall(broadcastCrafts) end)
end

-- ===== tooltip =====
local function addLines(tip, id)
  if not id or not tip or tip.gbDone == id then return end
  if not tip.gbHooked and tip.HookScript then
    tip.gbHooked = true
    pcall(tip.HookScript, tip, "OnTooltipCleared", function(t) t.gbDone = nil end)
  end
  tip.gbDone = id
  local self = me()
  local needers, makers = {}, {}
  if ns.featureOff("needs") then db().needs = db().needs end
  for who, n in pairs(ns.featureOff("needs") and {} or db().needs) do
    local left = n.items and n.items[id]
    if left and left > 0 and who ~= self then needers[#needers + 1] = short(who) .. " " .. left end
  end
  for who, c in pairs(ns.featureOff("crafts") and {} or db().crafts) do
    if c.items and c.items[id] and who ~= self then makers[#makers + 1] = short(who) end
  end
  local mineLeft = myRemaining()[id]
  local extra = {}
  for _, x in ipairs(ns.tipExtras or {}) do
    local ok, lines = ns.safe(x[1], x[2], id)
    if ok and lines then for _, l in ipairs(lines) do extra[#extra + 1] = l end end
  end
  if #needers > 0 or #makers > 0 or mineLeft or #extra > 0 then tip:AddLine(" ") end
  if #needers > 0 then table.sort(needers); tip:AddLine(BLUE .. "Guild needs:|r " .. table.concat(needers, ", "), 1, 1, 1, true) end
  if mineLeft then tip:AddLine(BLUE .. "You need:|r " .. mineLeft .. GRAY .. "  (Alt+click to change)|r", 1, 1, 1) end
  for _, l in ipairs(extra) do tip:AddLine(l, 1, 1, 1, true) end
  if #makers > 0 then table.sort(makers); tip:AddLine(GOLD .. "Guild can make:|r " .. table.concat(makers, ", "), 1, 1, 1, true) end
  if not mineLeft and IsAltKeyDown and IsAltKeyDown() then tip:AddLine(GRAY .. "Alt+click: I need this (Guild Board)|r") end
  tip:Show()
end

local function hookTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
      ns.safe("tooltip", addLines, tip, data and data.id)
    end)
  end
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip and tip.HookScript then
      pcall(tip.HookScript, tip, "OnTooltipSetItem", function(t)
        local _, link = t:GetItem(); ns.safe("tooltip", addLines, t, idFromLink(link))
      end)
    end
  end
end

-- ===== Alt+click to set a need =====
StaticPopupDialogs["GUILDBOARD_NEED"] = {
  text = "How many %s do you need?\n(0 removes it)",
  button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
  hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnShow = function(self) local e = self.editBox or self.EditBox; e:SetNumeric(true); e:SetText("10"); e:HighlightText(); e:SetFocus() end,
  OnAccept = function(self, data) local e = self.editBox or self.EditBox; setNeed(data, e:GetText()) end,
  EditBoxOnEnterPressed = function(self, data) setNeed(data, self:GetText()); self:GetParent():Hide() end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function askNeed(link)
  local id = idFromLink(link); if not id then return end
  StaticPopup_Show("GUILDBOARD_NEED", itemName(id), nil, id)
end
ns.askNeed = askNeed

local function hookClicks()
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() and link then pcall(askNeed, link) end
    end)
  end
end

-- ===== mailbox button =====
local function bagSlots()
  local C = C_Container
  local nslots = C and C.GetContainerNumSlots or GetContainerNumSlots
  local info = function(b, s)
    if C and C.GetContainerItemInfo then local t = C.GetContainerItemInfo(b, s); return t and t.itemID, t and t.stackCount, t and t.isLocked end
    local _, count, locked, _, _, _, link = GetContainerItemInfo(b, s); return idFromLink(link), count, locked
  end
  return nslots, info
end

local function fillMail()
  local self = me()
  local nslots, info = bagSlots()
  local have = {}
  for b = 0, 4 do
    for s = 1, (nslots(b) or 0) do
      local id, count, locked = info(b, s)
      if id and not locked then have[id] = have[id] or {}; table.insert(have[id], { b = b, s = s, n = count or 1 }) end
    end
  end
  for who, n in pairs(db().needs) do
    if who ~= self then
      for id, left in pairs(n.items or {}) do
        if left > 0 and have[id] then
          local to = Ambiguate and Ambiguate(who, "mail") or short(who)
          SendMailNameEditBox:SetText(to)
          if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(itemName(id)) end
          local slot, sent = 1, 0
          for _, st in ipairs(have[id]) do
            if sent >= left or slot > (ATTACHMENTS_MAX_SEND or 12) then break end
            local take = math.min(st.n, left - sent)
            ClearCursor()
            if take < st.n then
              if C_Container and C_Container.SplitContainerItem then C_Container.SplitContainerItem(st.b, st.s, take) else SplitContainerItem(st.b, st.s, take) end
            else
              if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(st.b, st.s) else PickupContainerItem(st.b, st.s) end
            end
            ClickSendMailItemButton(slot)
            slot, sent = slot + 1, sent + take
          end
          print(GREEN .. "Guild Board|r: mail ready for " .. short(who) .. ": " .. sent .. " " .. itemName(id) .. ". Click Send.")
          return
        end
      end
    end
  end
  print(GREEN .. "Guild Board|r: you are not carrying anything a guildie needs.")
end

local mailButton
local function makeMailButton()
  if mailButton or not SendMailFrame then return end
  mailButton = CreateFrame("Button", "GuildBoardMailButton", SendMailFrame, "UIPanelButtonTemplate")
  mailButton:SetSize(110, 22)
  mailButton:SetPoint("BOTTOMLEFT", SendMailFrame, "TOPLEFT", 70, -62)
  mailButton:SetText("Send needs")
  mailButton:SetScript("OnClick", function() local ok, err = pcall(fillMail); if not ok then print("Guild Board: " .. tostring(err)) end end)
  mailButton:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:SetText("Guild Board")
    GameTooltip:AddLine("Fills in a mail to a guildie who needs something you are carrying. You still click Send.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  mailButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ===== events =====
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "MAIL_SHOW" }) do
  pcall(ev.RegisterEvent, ev, e)
end
local bagTimer, scanTimer
ev:SetScript("OnEvent", ns.guard("needs", function(_, e)
  if e == "PLAYER_LOGIN" then
    db(); pcall(hookTooltips); pcall(hookClicks)
  elseif e == "BAG_UPDATE_DELAYED" then
    if bagTimer then return end
    bagTimer = true
    C_Timer.After(5, function() bagTimer = nil; pcall(broadcastNeeds, false) end)
  elseif e == "MAIL_SHOW" then
    pcall(makeMailButton)
  else
    if scanTimer then return end
    scanTimer = true
    C_Timer.After(2, function()
      scanTimer = nil
      local before = 0; for _ in pairs(db().myCrafts or {}) do before = before + 1 end
      pcall(scanRecipes)
      local after = 0; for _ in pairs(db().myCrafts or {}) do after = after + 1 end
      if after ~= before then pcall(broadcastCrafts) end
    end)
  end
end))

-- text block for the /gb window
ns.needsText = function()
  local L, any = { "", "GUILD NEEDS (Alt+click any item to add yours)" }, false
  for who, n in pairs(db().needs) do
    for id, left in pairs(n.items or {}) do
      if left > 0 then any = true; L[#L + 1] = string.format("%-14s %3d  %s", short(who), left, itemName(id)) end
    end
  end
  if not any then L[#L + 1] = "nobody needs anything right now" end
  return table.concat(L, "\n")
end
