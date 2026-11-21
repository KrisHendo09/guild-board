-- Party Sync data: party members with Guild Board trade repair %, bag space and shareable quests. The Party tab of
-- the tracker (Tracker.lua) shows it. Right-click the minimap button > Tracker, or /gb party. Everyone in your group with Guild Board
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
-- Have I finished this quest before? The per-quest flag is not reliable on every client, so this also reads the full
-- completed list (two different calls, whichever exists) and Questie's own record, and trusts any of them.
local doneSet, doneAt
local function completedSet()
  if doneSet and GetTime() - doneAt < 120 then return doneSet end
  local set = {}
  if GetQuestsCompleted then
    local ok, t = pcall(GetQuestsCompleted)
    if ok and type(t) == "table" then for id, v in pairs(t) do if v then set[id] = true end end end
  end
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, t = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(t) == "table" then for _, id in ipairs(t) do set[id] = true end end
  end
  if Questie and Questie.db and Questie.db.char and type(Questie.db.char.complete) == "table" then
    for id, v in pairs(Questie.db.char.complete) do if v then set[id] = true end end
  end
  doneSet, doneAt = set, GetTime()
  return set
end
local function completed(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id); if ok and v then return true end
  end
  if IsQuestFlaggedCompleted then
    local ok, v = pcall(IsQuestFlaggedCompleted, id); if ok and v then return true end
  end
  return completedSet()[id] and true or false
end
-- With Questie: is the quest before this one in its chain done? Without Questie this says yes and the game decides.
local function prereqOK(id)
  if not (QuestieLoader and QuestieLoader.ImportModule) then return true end
  local ok, res = pcall(function()
    local QDB = QuestieLoader:ImportModule("QuestieDB")
    local q = QDB.GetQuest(id)
    if not q then return true end
    local group = q.preQuestGroup
    if type(group) == "table" and #group > 0 then
      for _, pid in ipairs(group) do if pid > 0 and not completed(pid) then return false end end
    end
    local single = q.preQuestSingle
    if type(single) == "table" and #single > 0 then
      for _, pid in ipairs(single) do if completed(math.abs(pid)) then return true end end
      return false
    end
    return true
  end)
  if not ok then return true end
  return res
end

-- A share that bounced: remember who, which quest and why, so it stops being offered.
local lastShare                     -- { id, at, asker }
local giveFail, takeFail = {}, {}   -- [who][id] = { txt, till }
local FAIL = {
  { g = "ERR_QUEST_PUSH_PREREQUISITE_S", find = "prerequisite", txt = "needs an earlier quest first", keep = 1800 },
  { g = "ERR_QUEST_PUSH_ALREADY_DONE_S", find = "completed that quest", txt = "already finished it", keep = 86400 },
  { g = "ERR_QUEST_PUSH_ONQUEST_S", find = "already on that quest", txt = "already has it", keep = 900 },
  { g = "ERR_QUEST_PUSH_LOG_FULL_S", find = "log is full", txt = "quest log is full", keep = 300 },
  { g = "ERR_QUEST_PUSH_INVALID_S", find = "not eligible", txt = "can't take it", keep = 1800 },
}
local function failReason(msg)
  local low = msg:lower()
  for _, f in ipairs(FAIL) do
    local gs = _G[f.g]
    if type(gs) == "string" then
      local pat = gs:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", ".+")
      if msg:find(pat) then return f end
    end
    if low:find(f.find, 1, true) then return f end
  end
  if low:find("that quest", 1, true) then return { txt = "can't take it right now", keep = 900 } end
end
local function shareQuest(id, asker)
  lastShare = { id = id, at = GetTime(), asker = asker }
  if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id)
  elseif GetQuestLogIndexByID and SelectQuestLogEntry then SelectQuestLogEntry(GetQuestLogIndexByID(id)) end
  if QuestLogPushQuest then QuestLogPushQuest() end
end
local function failed(tbl, who, id)
  local f = tbl[who] and tbl[who][id]
  if f and GetTime() < f.till then return f.txt end
  if f then tbl[who][id] = nil end
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

-- M^chunk^of^id~level~zone|id~level~zone...   so the other side can show where a quest is and what level
local function questMeta()
  local out, zone = {}, ""
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local q = C_QuestLog.GetInfo(i)
      if q then
        if q.isHeader then zone = q.title or ""
        elseif q.questID then out[q.questID] = { level = q.level or 0, zone = zone } end
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, GetNumQuestLogEntries() do
      local title, level, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
      if isHeader then zone = title or "" elseif id then out[id] = { level = level or 0, zone = zone } end
    end
  end
  return out
end
local function sendMeta()
  local meta, mine = questMeta(), myShareable()
  local parts = {}
  for id in pairs(mine) do
    local m = meta[id]
    if m then
      local done = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
      parts[#parts + 1] = id .. "~" .. m.level .. "~" .. tostring(m.zone):gsub("[%^|~]", " ") .. "~" .. (done and 1 or 0)
    end
  end
  table.sort(parts)
  local chunks, cur = {}, ""
  for _, p in ipairs(parts) do
    if #cur + #p + 1 > 200 then chunks[#chunks + 1] = cur; cur = p else cur = (cur == "" and p) or (cur .. "|" .. p) end
  end
  if cur ~= "" then chunks[#chunks + 1] = cur end
  for i, c in ipairs(chunks) do sendParty("M" .. SEP .. i .. SEP .. #chunks .. SEP .. c) end
end

local data = {}        -- [name] = { dur, broken, free, total, level, quests = {[id]=true}, wants = {[id]=true}, meta = {[id]={level,zone}}, at }
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
    if sender ~= me then sendStatus(); pcall(sendMeta) end
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
  elseif kind == "Z" then
    -- where a party member is standing (area name only; the game gives addons no position inside a dungeon)
    if sender == me then return end
    slot(sender).sub = f[1]
    if ns.refreshParty then ns.refreshParty() end
    if ns.trackerRefresh then ns.trackerRefresh() end
  elseif kind == "A" then
    -- a party member pressed Ask on one of my quests: share it with the party (they get the normal accept popup)
    if sender == me or ns.canon(f[1]) ~= me then return end
    local id = tonumber(f[2])
    if id and myShareable()[id] then pcall(shareQuest, id, sender) end
  elseif kind == "F" then
    -- I asked for a quest and the game refused it on their side: stop offering it to me
    if sender == me or ns.canon(f[1]) ~= me then return end
    local id = tonumber(f[2])
    if id then
      takeFail[sender] = takeFail[sender] or {}
      takeFail[sender][id] = { txt = f[3] or "can't take it", till = GetTime() + (tonumber(f[4]) or 900) }
      if ns.trackerRefresh then ns.trackerRefresh() end
    end
  elseif kind == "M" then
    if sender == me then return end
    local d = slot(sender)
    if (tonumber(f[1]) or 1) == 1 then d.meta = {} end
    d.meta = d.meta or {}
    for item in (f[3] or ""):gmatch("[^|]+") do
      local id, lvl, zone, done = item:match("^(%d+)~(%-?%d+)~([^~]*)~?(%d?)$")
      if id then d.meta[tonumber(id)] = { level = tonumber(lvl), zone = zone, done = done == "1" } end
    end
    if ns.trackerRefresh then ns.trackerRefresh() end
  end
end

-- ===== what the tracker reads =====
ns.party = {
  units = partyUnits, durability = durability, bagFree = bagFree, completed = completed,
  shareable = myShareable, share = shareQuest, prereqOK = prereqOK,
  giveBlocked = function(who, id) return failed(giveFail, who, id) end,
  takeBlocked = function(who, id) return failed(takeFail, who, id) end,
  ask = function(owner, id) sendParty("A" .. SEP .. owner .. SEP .. id) end,
  zone = function(name) sendParty("Z" .. SEP .. tostring(name or ""):gsub("%^", " "):sub(1, 60)) end,
  data = function() return data end,
}
local lastSent = 0
ns.partyRefresh = function(force)            -- ask the party for fresh status, at most every 4 seconds
  if not inParty() then return end
  if not force and time() - lastSent < 4 then return end
  lastSent = time()
  sendParty("S"); sendStatus(); pcall(sendMeta)
end
ns.refreshParty = function() if ns.trackerRefresh then ns.trackerRefresh() end end
ns.partySync = function() if ns.openTracker then ns.openTracker("party") end; ns.partyRefresh(true) end

-- the game's own "can't share" lines (the yellow text) are the only way to learn a share bounced
local function onSystem(msg)
  if type(msg) ~= "string" or not lastShare or GetTime() - lastShare.at > 6 then return end
  local f = failReason(msg)
  if not f then return end
  local who
  for _, u in ipairs(partyUnits()) do
    local full = UnitName(u)
    if full and msg:find(full, 1, true) then who = ns.canon(full) end
  end
  if not who then return end
  giveFail[who] = giveFail[who] or {}
  giveFail[who][lastShare.id] = { txt = f.txt, till = GetTime() + f.keep }
  if lastShare.asker and lastShare.asker == who then
    sendParty(table.concat({ "F", who, lastShare.id, f.txt, f.keep }, SEP))
  end
  if ns.trackerRefresh then ns.trackerRefresh() end
end
local sysev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }) do pcall(sysev.RegisterEvent, sysev, e) end
sysev:SetScript("OnEvent", function(_, e, a1, a2)
  local msg = (e == "CHAT_MSG_SYSTEM") and a1 or (type(a2) == "string" and a2 or a1)
  pcall(onSystem, msg)
end)

local pev = CreateFrame("Frame")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do pcall(pev.RegisterEvent, pev, e) end
local pwait
pev:SetScript("OnEvent", function()
  if pwait then return end
  pwait = true
  C_Timer.After(3, function() pwait = nil; pcall(ns.partyRefresh) end)
end)
