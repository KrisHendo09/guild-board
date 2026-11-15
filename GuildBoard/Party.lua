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

local function pushable(id)
  if C_QuestLog and C_QuestLog.IsPushableQuest then return C_QuestLog.IsPushableQuest(id) end
  return true
end
local function completed(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
  if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) end
  return false
end
local function shareQuest(id)
  if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id)
  elseif GetQuestLogIndexByID and SelectQuestLogEntry then SelectQuestLogEntry(GetQuestLogIndexByID(id)) end
  if QuestLogPushQuest then QuestLogPushQuest() end
end
-- only quests that can actually be shared go out (no battleground, escort or class quests)
local function myShareable()
  local out = {}
  for id, title in pairs(ns.myQuests and ns.myQuests() or {}) do if pushable(id) then out[id] = title end end
  return out
end

local function chunked(ids, head)
  table.sort(ids)
  local chunks, cur = {}, ""
  for _, id in ipairs(ids) do
    local add = (cur == "" and "" or ",") .. id
    if #cur + #add > 170 then chunks[#chunks + 1] = cur; cur = tostring(id) else cur = cur .. add end
  end
  chunks[#chunks + 1] = cur
  for i, c in ipairs(chunks) do sendParty(head .. SEP .. i .. SEP .. #chunks .. SEP .. c) end
end

-- status: P^dur%^broken^free^total^level^chunk^chunks^shareable quest IDs
local function sendStatus()
  local d, broken = durability()
  local free, total = bagFree()
  local ids = {}
  for id in pairs(myShareable()) do ids[#ids + 1] = id end
  chunked(ids, table.concat({ "P", d, broken, free, total, UnitLevel("player") or 0 }, SEP))
end

local data = {}        -- [name] = { dur, broken, free, total, level, quests = {[id]=true}, wants = {[id]=true}, at }
local function slot(name) data[name] = data[name] or { quests = {}, wants = {} }; return data[name] end

-- someone's shareable quests arrived: tell them which ones I can actually take (not in my log, not done before)
local function answerTakes(owner)
  local d = data[owner]; if not d then return end
  local mine = ns.myQuests and ns.myQuests() or {}
  local ids = {}
  for id in pairs(d.quests) do if not mine[id] and not completed(id) then ids[#ids + 1] = id end end
  chunked(ids, "T" .. SEP .. owner)
end

local pendingAnswer = {}
ns.onParty = function(kind, sender, f)
  local me = ns.me()
  if kind == "S" then
    if sender ~= me then sendStatus() end
  elseif kind == "P" then
    if sender == me then return end
    local d = slot(sender)
    local chunk, of = tonumber(f[6]) or 1, tonumber(f[7]) or 1
    if chunk == 1 then d.quests = {} end
    d.dur, d.broken, d.free, d.total, d.level = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    d.at = time()
    for id in (f[8] or ""):gmatch("%d+") do d.quests[tonumber(id)] = true end
    if chunk >= of and not pendingAnswer[sender] then
      pendingAnswer[sender] = true
      C_Timer.After(0.5, function() pendingAnswer[sender] = nil; pcall(answerTakes, sender) end)
    end
    if ns.refreshParty then ns.refreshParty() end
  elseif kind == "T" then
    if sender == me or ns.canon(f[1]) ~= me then return end
    local d = slot(sender)
    if (tonumber(f[2]) or 1) == 1 then d.wants = {} end
    for id in (f[4] or ""):gmatch("%d+") do d.wants[tonumber(id)] = true end
    d.answered = true
    if ns.refreshParty then ns.refreshParty() end
  end
end

-- ===== window =====
-- built as fixed-height rows so every Share button sits on the same line as its quest
local frame, rows = nil, {}
local ROWH, MAXROWS, WIDTH = 20, 30, 460
local function build()
  frame = CreateFrame("Frame", "GuildBoardPartyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, 300); frame:SetPoint("CENTER", 180, 40); frame:SetFrameStrata("DIALOG")
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.05, 0.04, 0.03, 0.94); frame:SetBackdropBorderColor(0.9, 0.72, 0.4, 0.9)
  end
  frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12); title:SetText("Party Sync")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  local again = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); again:SetSize(84, 20); again:SetPoint("TOPRIGHT", -34, -10)
  again:SetText("Refresh"); again:SetScript("OnClick", function() ns.partySync() end)
  for i = 1, MAXROWS do
    local y = -40 - (i - 1) * ROWH
    local r = { y = y }
    r.btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); r.btn:SetSize(54, 18); r.btn:SetPoint("TOPLEFT", 12, y + 1); r.btn:SetText("Share"); r.btn:Hide()
    r.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT", 16, y - 3); r.text:SetWidth(WIDTH - 32); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("TOPRIGHT", -16, y - 3); r.right:SetJustifyH("RIGHT")
    rows[i] = r
  end
  tinsert(UISpecialFrames, "GuildBoardPartyFrame")
end

local function render()
  if not frame or not frame:IsShown() then return end
  local out = {}     -- { text, right, share = questID, header = true }
  local function add(t, right, share) out[#out + 1] = { t = t, r = right, share = share } end
  local function head(t) if #out > 0 then add("") end add(YELLOW .. t .. "|r") end
  local units = partyUnits()
  local function member(name, lvl, d, broken, free)
    local rep = d and (((d < 25 or (broken or 0) > 0) and RED or d < 60 and YELLOW or GREEN) .. "repair " .. d .. "%|r") or GRAY .. "no addon|r"
    if broken and broken > 0 then rep = rep .. RED .. " (" .. broken .. " broken)|r" end
    local bag = free and (((free <= 2) and RED or free <= 6 and YELLOW or GREEN) .. "bags " .. free .. " free|r") or ""
    add(ns.display(name) .. GRAY .. "  lvl " .. (lvl or "?") .. "|r", rep .. "     " .. bag)
  end
  head("GROUP")
  if #units == 0 then add(GRAY .. "You're not in a party.|r") end
  local md, mb = durability(); local mf = bagFree()
  member(ns.me(), UnitLevel("player"), md, mb, mf)
  local mine = myShareable()
  local share, ask, waiting = {}, {}, false
  for _, u in ipairs(units) do
    local nm = ns.canon(UnitName(u)); local d = data[nm]
    member(nm, UnitLevel(u), d and d.dur, d and d.broken, d and d.free)
    if d then
      if d.answered then
        for id in pairs(d.wants) do if mine[id] then share[#share + 1] = { id = id, title = mine[id], who = nm } end end
      else waiting = true end
      local all = ns.myQuests and ns.myQuests() or {}
      for id in pairs(d.quests) do if not all[id] and not completed(id) then ask[#ask + 1] = { id = id, who = nm } end end
    end
  end
  if #units > 0 then
    head("YOU CAN SHARE")
    table.sort(share, function(a, b) return a.title < b.title end)
    if #share == 0 then add(GRAY .. (waiting and "checking..." or "nothing they can take") .. "|r") end
    for _, s in ipairs(share) do add(s.title, GRAY .. ns.display(s.who) .. "|r", s.id) end
    head("ASK THEM TO SHARE")
    if #ask == 0 then add(GRAY .. "nothing you can take|r") end
    local titled = {}
    for _, a in ipairs(ask) do
      local t = (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(a.id)) or ("Quest " .. a.id)
      titled[#titled + 1] = { t = t, who = a.who }
    end
    table.sort(titled, function(a, b) return a.t < b.t end)
    for _, a in ipairs(titled) do add(a.t, GRAY .. ns.display(a.who) .. "|r") end
    if ns.partyGearText then
      local g = ns.partyGearText()
      if g then head("GEAR CHECK"); add((g:gsub("^|cffffd100GEAR CHECK|r\n", ""))) end
    end
  end
  local n = math.min(#out, MAXROWS)
  if #out > MAXROWS then out[MAXROWS] = { t = GRAY .. "+" .. (#out - MAXROWS + 1) .. " more|r" } end
  for i, r in ipairs(rows) do
    local o = out[i]
    if o and i <= n then
      r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", o.share and 74 or 16, r.y - 3)
      r.text:SetWidth(WIDTH - (o.share and 200 or 32))
      r.text:SetText(o.t or ""); r.right:SetText(o.r or "")
      if o.share then
        r.btn:SetScript("OnClick", function() shareQuest(o.share) end); r.btn:Show()
      else r.btn:Hide() end
    else r.text:SetText(""); r.right:SetText(""); r.btn:Hide() end
  end
  frame:SetHeight(52 + n * ROWH)
end
ns.refreshParty = function() C_Timer.After(0.2, function() pcall(render) end) end

ns.partySync = function()
  if not frame then build() end
  frame:Show()
  if inParty() then
    data = {}
    sendParty("S")
    sendStatus()
    C_Timer.After(3, function() pcall(render) end)
  end
  render()
end
