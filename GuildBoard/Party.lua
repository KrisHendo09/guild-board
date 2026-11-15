-- Party Sync: right-click the minimap button > Party Sync (or /gb party). Everyone in your group with Guild Board
-- answers with their repair %, free bag slots and quest list, and you get one window that shows:
--   * who needs to repair and who is nearly out of bag space
--   * quests you can share with someone who doesn't have them, each with a Share button (WoW needs the click)
--   * quests a party member has that you don't, so you know to ask them to share
-- Talks over the party channel only, never guild or Discord. Party members without the addon still show up,
-- just without repair and bag numbers.
local _, ns = ...
local SEP = "^"
local PREFIX = "GBOARD1"
local GREEN, YELLOW, RED, GRAY = "|cff33ff99", "|cffffd100", "|cffff5533", "|cff9d9d9d"
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local function partyUnits()
  local u = {}
  if IsInRaid and IsInRaid() then return u end              -- party sync is for 5-man groups
  for i = 1, 4 do if UnitExists("party" .. i) then u[#u + 1] = "party" .. i end end
  return u
end
local function inParty() return #partyUnits() > 0 end

local function durability()
  local cur, max, broken = 0, 0, 0
  for _, s in ipairs(SLOTS) do
    local c, m = GetInventoryItemDurability(s)
    if c and m and m > 0 then cur, max = cur + c, max + m; if c == 0 then broken = broken + 1 end end
  end
  return max > 0 and math.floor(cur / max * 100 + 0.5) or 100, broken
end

local function bagFree()
  local free, total = 0, 0
  local C = C_Container
  for b = 0, 4 do
    local n = (C and C.GetContainerNumSlots and C.GetContainerNumSlots(b)) or (GetContainerNumSlots and GetContainerNumSlots(b)) or 0
    local f = (C and C.GetContainerNumFreeSlots and C.GetContainerNumFreeSlots(b)) or (GetContainerNumFreeSlots and GetContainerNumFreeSlots(b)) or 0
    total, free = total + (n or 0), free + (f or 0)
  end
  return free, total
end

local function sendParty(msg)
  if not inParty() then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, msg:sub(1, 250), "PARTY")
  elseif SendAddonMessage then SendAddonMessage(PREFIX, msg:sub(1, 250), "PARTY") end
end

-- status: P^dur%^broken^free^total^level^chunk^chunks^questIDs(comma)
local function sendStatus()
  local d, broken = durability()
  local free, total = bagFree()
  local ids = {}
  for id in pairs(ns.myQuests and ns.myQuests() or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local chunks, cur = {}, ""
  for _, id in ipairs(ids) do
    local add = (cur == "" and "" or ",") .. id
    if #cur + #add > 180 then chunks[#chunks + 1] = cur; cur = tostring(id) else cur = cur .. add end
  end
  chunks[#chunks + 1] = cur
  for i, c in ipairs(chunks) do
    sendParty(table.concat({ "P", d, broken, free, total, UnitLevel("player") or 0, i, #chunks, c }, SEP))
  end
end

local data = {}        -- [name] = { dur, broken, free, total, level, quests = {[id]=true}, at }
ns.onParty = function(kind, sender, f)
  if kind == "S" then
    if sender ~= ns.me() then sendStatus() end
  elseif kind == "P" then
    local d = data[sender]
    local chunk = tonumber(f[6]) or 1
    if not d or chunk == 1 then d = { quests = {} }; data[sender] = d end
    d.dur, d.broken, d.free, d.total, d.level = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    d.at = time()
    for id in (f[8] or ""):gmatch("%d+") do d.quests[tonumber(id)] = true end
    if ns.refreshParty then ns.refreshParty() end
  end
end

local function pushable(id)
  if C_QuestLog and C_QuestLog.IsPushableQuest then return C_QuestLog.IsPushableQuest(id) end
  return true
end
local function shareQuest(id)
  if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id)
  elseif GetQuestLogIndexByID and SelectQuestLogEntry then SelectQuestLogEntry(GetQuestLogIndexByID(id)) end
  if QuestLogPushQuest then QuestLogPushQuest() end
end

-- ===== window =====
local frame, lines, buttons
local MAXB = 10
local function build()
  frame = CreateFrame("Frame", "GuildBoardPartyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(470, 470); frame:SetPoint("CENTER", 180, 40); frame:SetFrameStrata("DIALOG")
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0, 0, 0, 0.9)
  end
  frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  local again = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); again:SetSize(90, 22); again:SetPoint("TOPLEFT", 10, -8)
  again:SetText("Sync again"); again:SetScript("OnClick", function() ns.partySync() end)
  lines = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lines:SetPoint("TOPLEFT", 14, -40); lines:SetWidth(440); lines:SetJustifyH("LEFT"); lines:SetJustifyV("TOP")
  buttons = {}
  for i = 1, MAXB do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); b:SetSize(60, 18); b:Hide()
    b:SetText("Share"); buttons[i] = b
  end
  tinsert(UISpecialFrames, "GuildBoardPartyFrame")
end

local function render()
  if not frame or not frame:IsShown() then return end
  local L = { YELLOW .. "PARTY SYNC|r" }
  local units = partyUnits()
  if #units == 0 then L[#L + 1] = GRAY .. "You're not in a party.|r" end
  local myD, myB = durability(); local myF, myT = bagFree()
  local function row(name, lvl, d, broken, free, total)
    local dtxt = d and ((d < 25 or (broken or 0) > 0) and RED or d < 60 and YELLOW or GREEN) .. d .. "%|r" or GRAY .. "no addon|r"
    if broken and broken > 0 then dtxt = dtxt .. RED .. " (" .. broken .. " broken)|r" end
    local btxt = free and ((free <= 2) and RED or free <= 6 and YELLOW or GREEN) .. free .. " free|r" or ""
    return string.format("%s  lvl %s   repair %s   bags %s", ns.display(name), lvl or "?", dtxt, btxt)
  end
  L[#L + 1] = row(ns.me(), UnitLevel("player"), myD, myB, myF, myT)
  local mine = ns.myQuests and ns.myQuests() or {}
  local share, ask = {}, {}
  for _, u in ipairs(units) do
    local nm = ns.canon(UnitName(u)); local d = data[nm]
    L[#L + 1] = row(nm, UnitLevel(u), d and d.dur, d and d.broken, d and d.free, d and d.total)
    if d then
      for id, title in pairs(mine) do if not d.quests[id] and pushable(id) then share[#share + 1] = { id = id, title = title, who = nm } end end
      for id in pairs(d.quests) do if not mine[id] then ask[id] = ask[id] or {}; table.insert(ask[id], nm) end end
    end
  end
  for _, b in ipairs(buttons) do b:Hide() end
  L[#L + 1] = ""
  L[#L + 1] = YELLOW .. "YOU CAN SHARE|r " .. GRAY .. "(they still have to accept)|r"
  local base = #L
  if #share == 0 then L[#L + 1] = GRAY .. "nothing to share|r" end
  table.sort(share, function(a, b) return a.title < b.title end)
  for i, s in ipairs(share) do
    if i > MAXB then L[#L + 1] = GRAY .. "+" .. (#share - MAXB) .. " more|r"; break end
    L[#L + 1] = "        " .. s.title .. GRAY .. "  for " .. ns.display(s.who) .. "|r"
    local b = buttons[i]
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", lines, "TOPLEFT", -4, -((base + i - 1) * 14.5) + 2)
    b:SetScript("OnClick", function() shareQuest(s.id) end); b:Show()
  end
  local n = 0
  for _ in pairs(ask) do n = n + 1 end
  if n > 0 then
    L[#L + 1] = ""; L[#L + 1] = YELLOW .. "ASK THEM TO SHARE|r " .. GRAY .. "(quests your party has that you don't)|r"
    local parts = {}
    for id, who in pairs(ask) do
      local t = (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)) or ("quest " .. id)
      parts[#parts + 1] = t .. GRAY .. " (" .. ns.display(who[1]) .. ")|r"
    end
    table.sort(parts)
    for i = 1, math.min(#parts, 8) do L[#L + 1] = "  " .. parts[i] end
  end
  if ns.partyGearText then local g = ns.partyGearText(); if g and g ~= "" then L[#L + 1] = ""; L[#L + 1] = g end end
  lines:SetText(table.concat(L, "\n"))
  frame:SetHeight(math.max(200, lines:GetStringHeight() + 60))
end
ns.refreshParty = function() C_Timer.After(0.2, function() pcall(render) end) end

ns.partySync = function()
  if not frame then build() end
  frame:Show()
  if inParty() then
    data = {}
    sendParty("S")
    sendStatus()
    C_Timer.After(2.5, function() pcall(render) end)
  end
  render()
end
