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
    if id and myShareable()[id] then pcall(shareQuest, id) end
  end
end

-- ===== what the tracker reads =====
ns.party = {
  units = partyUnits, durability = durability, bagFree = bagFree, completed = completed,
  shareable = myShareable, share = shareQuest,
  ask = function(owner, id) sendParty("A" .. SEP .. owner .. SEP .. id) end,
  zone = function(name) sendParty("Z" .. SEP .. tostring(name or ""):gsub("%^", " "):sub(1, 60)) end,
  data = function() return data end,
}
local lastSent = 0
ns.partyRefresh = function(force)            -- ask the party for fresh status, at most every 4 seconds
  if not inParty() then return end
  if not force and time() - lastSent < 4 then return end
  lastSent = time()
  sendParty("S"); sendStatus()
end
ns.refreshParty = function() if ns.trackerRefresh then ns.trackerRefresh() end end
ns.partySync = function() if ns.openTracker then ns.openTracker("party") end; ns.partyRefresh(true) end

local pev = CreateFrame("Frame")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do pcall(pev.RegisterEvent, pev, e) end
local pwait
pev:SetScript("OnEvent", function()
  if pwait then return end
  pwait = true
  C_Timer.After(3, function() pwait = nil; pcall(ns.partyRefresh) end)
end)
