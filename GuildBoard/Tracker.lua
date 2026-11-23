-- Tracker: one small window with three tabs.
--   Personal: Upkeep (repair, empty slots, bags, trainer, profession caps, reagents), quests ready to turn in,
--             and the next items from Claude's list when Kris's Claude Tasks addon is loaded.
--   Party:    what to fix first (quests to share, who needs to repair or empty bags), then the quests the group
--             has in common, current zone first, plus any plan Claude Tasks shares with you by name.
--   Dungeon:  opens by itself when you zone in. Who needs to repair or clear bags, where everyone is (area name and
--             in range or not; the game gives no position inside a dungeon), quests for this dungeon and who has
--             them, bosses down, and a one-click run report.
--   Share:    every quest you can share with someone in the group (Share button) and every quest they have that
--             you could take (Ask button: their Guild Board shares it, you get the normal accept popup).
-- "+ Plan" on a line adds it to your Game Plan (Plan.lua): the small checklist with the arrow.
-- The Party quest list shows 5, More shows up to 20. Skip takes a quest off the list; the "skipped" line brings any of them back.
-- Everything is worked out on your own PC. Items clear themselves when they're done; nothing to tick off.
-- The gear button picks what each tab tracks (saved per character). Hides in combat. Only opens when you ask:
-- minimap right-click menu or /gb track. X or Esc closes it.
local _, ns = ...
local YELLOW, GREEN, RED, GRAY, GOLD = "|cffffd100", "|cff33ff99", "|cffff5533", "|cff9d9d9d", "|cffe8b964"
local CT_PREFIX = "CTASKS1"

local DEFAULTS = {
  repair = true, repairPct = 50, slots = true, bags = true, bagFree = 4, trainer = true, profcap = true,
  reagents = false, turnins = true, claude = true,
  pshare = true, pquests = true, pupkeep = true, pgear = false, pdungeons = false, pclaude = false,   -- shared plan is opt-in
  hideCombat = true, fade = false,
}
local LABELS = {
  { "Personal" },
  { "repair", "Repair at 50% or a broken item" }, { "slots", "Empty gear slots" }, { "bags", "Bags under 4 free" },
  { "trainer", "Class trainer visits" }, { "profcap", "Profession rank caps" }, { "reagents", "Reagents (ankhs, shards, ammo)" },
  { "turnins", "Quests ready to turn in" }, { "claude", "To-Do steps" },
  { "Party" },
  { "pshare", "Quests to share" }, { "pquests", "Shared quests in order" }, { "pupkeep", "Party repair and bags" },
  { "pgear", "Gear check" }, { "pdungeons", "Dungeons everyone wants" },
  { "Window" }, { "hideCombat", "Hide in combat" }, { "fade", "Fade when your mouse is not on it" },
}

local function db()
  GuildBoardDB.tracker = GuildBoardDB.tracker or {}
  local t = GuildBoardDB.tracker
  local me = ns.me and ns.me() or "?"
  t[me] = t[me] or {}
  local c = t[me]
  c.opts = c.opts or {}
  for k, v in pairs(DEFAULTS) do if c.opts[k] == nil then c.opts[k] = v end end
  return c
end
local function opt(k) return db().opts[k] end

-- ===== personal checks =====
local SLOTNAME = { [1] = "head", [2] = "neck", [3] = "shoulders", [5] = "chest", [6] = "waist", [7] = "legs", [8] = "feet",
  [9] = "wrists", [10] = "hands", [11] = "ring", [12] = "ring", [15] = "back", [16] = "main hand" }
local ALWAYS = { 5, 6, 7, 8, 9, 10, 16 }
local LATER = { 1, 2, 3, 11, 12, 15 }          -- only count from level 25: nobody has a neck at 15

local REAGENTS = {   -- class = { minLevel, itemID, keepAtLeast, label }
  SHAMAN = { 30, 17030, 2, "Ankhs" }, WARLOCK = { 10, 6265, 3, "Soul Shards" }, MAGE = { 20, 17031, 2, "Runes of Teleportation" },
  ROGUE = { 22, 5140, 3, "Flash Powder" },
}

local function questLog()        -- { id, title, zone, complete }
  local out, zone = {}, ""
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local q = C_QuestLog.GetInfo(i)
      if q then
        if q.isHeader then zone = q.title or ""
        elseif q.questID then
          local done = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID)) or false
          -- "go talk to X" quests have no objectives and count as complete the moment you take them; skip those
          if done and C_QuestLog.GetQuestObjectives then
            local objs = C_QuestLog.GetQuestObjectives(q.questID)
            if not objs or #objs == 0 then done = false end
          end
          out[#out + 1] = { id = q.questID, title = q.title or ("Quest " .. q.questID), zone = zone, complete = done, level = q.level }
        end
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, GetNumQuestLogEntries() do
      local title, qlevel, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
      if isHeader then zone = title or ""
      elseif title and id then
        local done = isComplete == 1 or isComplete == true
        if done and GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) == 0 then done = false end
        out[#out + 1] = { id = id, title = title, zone = zone, complete = done, level = qlevel }
      end
    end
  end
  return out
end

local function profCaps()
  local out = {}
  local s = ns.myProfs and ns.myProfs() or ""
  for name, rank, max in s:gmatch("([^:,]+):(%d+):(%d+)") do
    rank, max = tonumber(rank), tonumber(max)
    if max > 0 and max < 300 and rank >= max - 5 then out[#out + 1] = name .. " " .. rank .. "/" .. max .. ": train the next rank" end
  end
  return out
end

local function personal(add)
  local P = ns.party
  local level = UnitLevel("player") or 1
  local up = {}
  if opt("repair") and P then
    local d, broken = P.durability()
    if broken > 0 or d <= (opt("repairPct") or 50) then
      up[#up + 1] = (broken > 0 and RED or YELLOW) .. "Repair:|r " .. d .. "%" .. (broken > 0 and (RED .. " (" .. broken .. " broken)|r") or "")
    end
  end
  if opt("slots") then
    local empty = {}
    local function check(list) for _, s in ipairs(list) do if not GetInventoryItemLink("player", s) then empty[#empty + 1] = SLOTNAME[s] end end end
    check(ALWAYS); if level >= 25 then check(LATER) end
    if #empty > 0 then up[#up + 1] = YELLOW .. "Nothing on:|r " .. table.concat(empty, ", ") end
  end
  if opt("bags") and P then
    local free = P.bagFree()
    if free < (opt("bagFree") or 4) then up[#up + 1] = (free <= 1 and RED or YELLOW) .. "Bags:|r " .. free .. " free" end
  end
  if opt("trainer") then
    local c = db()
    c.trainedAt = c.trainedAt or level
    if level > c.trainedAt and level % 2 == 0 then up[#up + 1] = YELLOW .. "Class trainer:|r new ranks at " .. level end
  end
  if opt("profcap") then for _, t in ipairs(profCaps()) do up[#up + 1] = YELLOW .. "Profession:|r " .. t end end
  if opt("reagents") then
    local _, cls = UnitClass("player")
    local r = REAGENTS[cls or ""]
    if r and level >= r[1] then
      local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(r[2])) or (GetItemCount and GetItemCount(r[2])) or 0
      if n < r[3] then up[#up + 1] = YELLOW .. r[4] .. ":|r " .. n .. " left" end
    end
    if cls == "HUNTER" then
      local ammo = GetInventoryItemCount and GetInventoryItemCount("player", 0) or 0
      if ammo > 0 and ammo < 200 then up[#up + 1] = YELLOW .. "Ammo:|r " .. ammo .. " left" end
    end
  end
  if #up > 0 then
    add(GOLD .. "UPKEEP|r", true)
    for _, t in ipairs(up) do
      local p = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      add(t, false, nil, { plan = { key = "u:" .. (p:match("^([^:]+)") or p), text = p } })
    end
  end

  if opt("turnins") then
    local ready, here = {}, GetRealZoneText and GetRealZoneText() or ""
    for _, q in ipairs(questLog()) do if q.complete then ready[#ready + 1] = q end end
    table.sort(ready, function(a, b) if (a.zone == here) ~= (b.zone == here) then return a.zone == here end return a.title < b.title end)
    if #ready > 0 then
      add(GOLD .. "TURN IN|r" .. GRAY .. (#ready > 5 and ("  " .. #ready - 5 .. " more") or "") .. "|r", true)
      for i = 1, math.min(#ready, 5) do
        add(ready[i].title .. GRAY .. "  " .. ready[i].zone .. "|r", false, nil, { plan = { key = "q" .. ready[i].id, text = ready[i].title, questID = ready[i].id } })
      end
    end
  end

  -- old standalone Claude Tasks addon only; Game Plan (Plan.lua) replaced it
  if opt("claude") and SlashCmdList["CLAUDETASKS"] and ClaudeTasks_List and ClaudeTasks_List.tasks and #ClaudeTasks_List.tasks > 0 then
    local done = (ClaudeTasksDB and ClaudeTasksDB.listId == ClaudeTasks_List.id and ClaudeTasksDB.done) or {}
    local me, n, shown = (UnitName("player") or ""):lower(), 0, {}
    for i, t in ipairs(ClaudeTasks_List.tasks) do
      local mine = not t.who or t.who == "" or t.who:lower() == "both" or me:find(t.who:lower(), 1, true)
      if mine and not done[i] then n = n + 1; if #shown < 3 then shown[#shown + 1] = t.text end end
    end
    if n > 0 then
      add(GOLD .. "TO-DO LIST|r" .. GRAY .. (n > 3 and ("  " .. n - 3 .. " more in /ct") or "") .. "|r", true)
      for _, t in ipairs(shown) do add(t) end
    end
  end
end

-- ===== party =====
local ctasks = { tasks = {} }         -- Kris's shared Claude list, heard over the party channel
local function party(add, shareBtn)
  local P = ns.party
  local units = P and P.units() or {}
  if #units == 0 then add(GRAY .. "Not in a party. Group up and this fills in.|r"); return end
  local data = P.data()
  local first = {}
  -- who can't be read
  local missing = {}
  for _, u in ipairs(units) do local nm = ns.canon(UnitName(u)); if not data[nm] then missing[#missing + 1] = ns.display(nm) end end

  local share = {}
  if opt("pshare") then
    local mine = P.shareable()
    for nm, d in pairs(data) do
      if d.answered then
        for id in pairs(d.wants or {}) do
          if mine[id] and not (P.giveBlocked and P.giveBlocked(nm, id)) then share[#share + 1] = { id = id, title = mine[id], who = nm } end
        end
      end
    end
    table.sort(share, function(a, b) return a.title < b.title end)
  end
  if opt("pupkeep") then
    for nm, d in pairs(data) do
      if d.dur and ((d.broken or 0) > 0 or d.dur <= 50) then first[#first + 1] = ns.display(nm) .. RED .. " needs to repair (" .. d.dur .. "%)|r" end
      if d.free and d.free <= 2 then first[#first + 1] = ns.display(nm) .. YELLOW .. " has " .. d.free .. " bag slots|r" end
    end
    local md = P.durability()
    if md <= 50 then first[#first + 1] = "You" .. RED .. " need to repair (" .. md .. "%)|r" end
  end
  if #share > 0 or #first > 0 then
    add(GOLD .. "FIRST|r", true)
    if #share > 0 then
      local whoSet = {}
      for _, s in ipairs(share) do whoSet[ns.display(s.who)] = true end
      local whos = {}; for w in pairs(whoSet) do whos[#whos + 1] = w end
      add("Share " .. #share .. " quest" .. (#share > 1 and "s" or "") .. " with " .. table.concat(whos, ", ") .. GRAY .. "  next: " .. share[1].title .. "|r", false, share[1].id)
    end
    for _, t in ipairs(first) do add(t) end
  end

  if opt("pquests") then
    -- quests at least one party member also has, current zone first, then the ones most of the group has
    local here = GetRealZoneText and GetRealZoneText() or ""
    local rows = {}
    for _, q in ipairs(questLog()) do
      local n = 0
      for _, d in pairs(data) do if d.quests and d.quests[q.id] then n = n + 1 end end
      if n > 0 then rows[#rows + 1] = { q = q, n = n } end
    end
    table.sort(rows, function(a, b)
      local ah, bh = a.q.zone == here, b.q.zone == here
      if ah ~= bh then return ah end
      if a.q.zone ~= b.q.zone then return a.q.zone < b.q.zone end
      if a.n ~= b.n then return a.n > b.n end
      return a.q.title < b.q.title
    end)
    -- Skip button drops a quest off the list. "N skipped" opens the list so any one of them can be brought back.
    local c = db()
    c.skip = c.skip or {}
    local skip = c.skip
    local inLog = {}
    for _, q in ipairs(questLog()) do inLog[q.id] = true end
    for id in pairs(skip) do if not inLog[id] then skip[id] = nil end end      -- turned in or dropped: forget the skip
    local kept, skipped = {}, {}
    for _, r in ipairs(rows) do if skip[r.q.id] then skipped[#skipped + 1] = r else kept[#kept + 1] = r end end
    if #kept > 0 or #skipped > 0 then
      add(GOLD .. "TOGETHER, IN ORDER|r", true)
      local limit = c.moreQuests and 20 or 5
      for i, r in ipairs(kept) do
        if i > limit then break end
        add(i .. ". " .. r.q.title .. (r.q.complete and (GREEN .. "  turn in|r") or "") .. GRAY .. "  " .. r.q.zone .. "|r", false, nil,
          { skipId = r.q.id, track = r.q.id, plan = { key = "q" .. r.q.id, text = r.q.title, questID = r.q.id } })
      end
      if #kept > limit then
        add(GRAY .. "+" .. (#kept - limit) .. " more|r", false, nil, c.moreQuests and { btn = "Less", fn = function() db().moreQuests = false end }
          or { btn = "More", fn = function() db().moreQuests = true end })
      elseif c.moreQuests and #kept > 5 then
        add("", false, nil, { btn = "Less", fn = function() db().moreQuests = false end })
      end
      if #skipped > 0 then
        add(GRAY .. #skipped .. " skipped|r", false, nil, c.showSkipped and { btn = "Hide", fn = function() db().showSkipped = false end }
          or { btn = "Show", fn = function() db().showSkipped = true end })
        if c.showSkipped then
          for _, r in ipairs(skipped) do
            local id = r.q.id
            add(GRAY .. "    " .. r.q.title .. "  " .. r.q.zone .. "|r", false, nil, { btn = "Bring back", fn = function() db().skip[id] = nil end })
          end
          if #skipped > 1 then add("", false, nil, { btn = "All back", fn = function() db().skip = {}; db().showSkipped = false end }) end
        end
      end
    end
  end

  if opt("pdungeons") and ns.dungeonByKey then
    local count, people = {}, 1
    for _ in pairs(data) do people = people + 1 end
    local function tally(items) for k in pairs(items or {}) do count[k] = (count[k] or 0) + 1 end end
    tally(GuildBoardDB.myWants)
    for nm in pairs(data) do local w = GuildBoardDB.wants and GuildBoardDB.wants[nm]; tally(w and w.items) end
    local hits = {}
    for k, n in pairs(count) do if n >= 2 and ns.dungeonByKey[k] then hits[#hits + 1] = ns.dungeonByKey[k][2] .. GRAY .. " (" .. n .. " want it)|r" end end
    if #hits > 0 then add(GOLD .. "DUNGEONS YOU BOTH WANT|r", true); for _, h in ipairs(hits) do add(h) end end
  end

  if opt("pgear") and ns.partyGearText then
    local g = ns.partyGearText()
    if g then add(GOLD .. "GEAR CHECK|r", true); add((g:gsub("^|cffffd100GEAR CHECK|r\n", ""))) end
  end

  if #missing > 0 then add(""); add(GRAY .. table.concat(missing, ", ") .. " doesn't have Guild Board (or hasn't answered yet)|r") end
end

-- ===== share tab =====
local function questTitle(id)
  local ok, t
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then ok, t = pcall(C_QuestLog.GetTitleForQuestID, id); if ok and t and t ~= "" then return t end end
  if C_QuestLog and C_QuestLog.GetQuestInfo then ok, t = pcall(C_QuestLog.GetQuestInfo, id); if ok and type(t) == "string" and t ~= "" then return t end end
  return "Quest " .. id
end
local function shareTab(add)
  local P = ns.party
  local units = P and P.units() or {}
  if #units == 0 then add(GRAY .. "Not in a party. Group up and this fills in.|r"); return end
  local data = P.data()
  local mine = P.shareable()
  local log = ns.myQuests and ns.myQuests() or {}
  local here = GetRealZoneText and GetRealZoneText() or ""
  local myMeta = {}
  for _, q in ipairs(questLog()) do myMeta[q.id] = q end
  local give, take, waiting, blocked = {}, {}, {}, {}
  for nm, d in pairs(data) do
    if d.answered then
      for id in pairs(d.wants or {}) do
        if mine[id] then
          local why = P.giveBlocked and P.giveBlocked(nm, id)
          local m = myMeta[id] or {}
          if why then blocked[#blocked + 1] = mine[id] .. GRAY .. "  " .. ns.display(nm) .. " " .. why .. "|r"
          else give[#give + 1] = { id = id, title = mine[id], who = nm, zone = m.zone or "", level = m.level or 0 } end
        end
      end
    else waiting[#waiting + 1] = ns.display(nm) end
    for id in pairs(d.quests or {}) do
      if not log[id] and not P.completed(id) then
        local m = (d.meta and d.meta[id]) or {}
        local title = questTitle(id)
        local why = (P.takeBlocked and P.takeBlocked(nm, id)) or ((P.prereqOK and not P.prereqOK(id)) and "you need an earlier quest first")
        if why then blocked[#blocked + 1] = title .. GRAY .. "  " .. why .. "|r"
        else take[#take + 1] = { id = id, title = title, who = nm, zone = m.zone or "", level = m.level or 0 } end
      end
    end
  end
  -- your current zone first, then by zone, then by level
  local function order(a, b)
    local ah, bh = a.zone == here and a.zone ~= "", b.zone == here and b.zone ~= ""
    if ah ~= bh then return ah end
    if a.zone ~= b.zone then return a.zone < b.zone end
    if a.level ~= b.level then return a.level < b.level end
    if a.title ~= b.title then return a.title < b.title end
    return a.who < b.who
  end
  table.sort(give, order); table.sort(take, order)
  local function line(s2, dir)
    local lv = (s2.level and s2.level > 0) and (YELLOW .. "[" .. s2.level .. "]|r ") or ""
    local z = (s2.zone and s2.zone ~= "") and ("  " .. s2.zone) or ""
    return lv .. s2.title .. GRAY .. z .. "  " .. dir .. " " .. ns.display(s2.who) .. "|r"
  end
  local room = 20
  if #give > 0 then
    add(GOLD .. "YOU CAN SHARE|r", true)
    for i, s2 in ipairs(give) do
      if i > 10 then add(GRAY .. "+" .. (#give - 10) .. " more after these|r"); break end
      add(line(s2, "to"), false, nil, { btn = "Share", fn = function() P.share(s2.id); C_Timer.After(1.5, function() ns.partyRefresh(true) end) end })
      room = room - 1
    end
  end
  if #take > 0 then
    add(GOLD .. "THEY CAN SHARE WITH YOU|r", true)
    for i, s2 in ipairs(take) do
      if i > math.max(room - 2, 5) then add(GRAY .. "+" .. (#take - i + 1) .. " more after these|r"); break end
      add(line(s2, "from"), false, nil, { btn = "Ask", fn = function() P.ask(s2.who, s2.id); C_Timer.After(2, function() ns.partyRefresh(true) end) end })
    end
  end
  if #give == 0 and #take == 0 then add(GREEN .. "Nothing to share.|r" .. GRAY .. " You both have the same shareable quests.|r") end
  if #blocked > 0 then
    table.sort(blocked)
    add(GOLD .. "CAN'T BE SHARED|r", true)
    for i, t in ipairs(blocked) do
      if i > 5 then add(GRAY .. "+" .. (#blocked - 5) .. " more|r"); break end
      add(GRAY .. t .. "|r")
    end
  end
  if #waiting > 0 then add(GRAY .. "Still waiting to hear from " .. table.concat(waiting, ", ") .. "|r") end
end

-- ===== dungeon tab =====
-- Opens by itself when you zone into a dungeon or raid, and hands the window back when you leave.
local bossKills, wasInDungeon, lastZoneSent = {}, nil, nil
local function inDungeon()
  if not IsInInstance then return false end
  local inside, kind = IsInInstance()
  return inside and (kind == "party" or kind == "raid") and true or false
end
local function myArea()
  local s = GetSubZoneText and GetSubZoneText() or ""
  if s == "" and GetMinimapZoneText then s = GetMinimapZoneText() or "" end
  return s
end
-- Inside instances the game can hand back "secret" values for unit state; comparing one throws an error
-- (that was the Tracker.lua:432 error). Read them through this and treat secrets as unknown.
local function unitState(fn, u)
  if not fn then return nil end
  local ok, a, b = pcall(fn, u)
  if not ok then return nil end
  if issecretvalue and ((a ~= nil and issecretvalue(a)) or (b ~= nil and issecretvalue(b))) then return nil end
  return a, b
end
local function dungeonTab(add)
  if not inDungeon() then add(GRAY .. "Not in a dungeon. This tab fills in by itself when you zone in.|r"); return end
  local name = (GetInstanceInfo and GetInstanceInfo()) or (GetRealZoneText and GetRealZoneText()) or "Dungeon"
  local P = ns.party
  local units = P and P.units() or {}
  local data = P and P.data() or {}
  local level = UnitLevel("player") or 1

  -- fix before you pull
  local bad, unknown = {}, {}
  if P then
    local d, broken = P.durability()
    if (broken or 0) > 0 or d <= 50 then bad[#bad + 1] = "You" .. RED .. " need to repair (" .. d .. "%)|r" end
    local free = P.bagFree()
    if free <= 3 then bad[#bad + 1] = "You" .. YELLOW .. " have " .. free .. " bag slots|r" end
  end
  local empty = {}
  local function check(list) for _, sl in ipairs(list) do if not GetInventoryItemLink("player", sl) then empty[#empty + 1] = SLOTNAME[sl] end end end
  check(ALWAYS); if level >= 25 then check(LATER) end
  if #empty > 0 then bad[#bad + 1] = "You" .. YELLOW .. " have nothing on: " .. table.concat(empty, ", ") .. "|r" end
  for _, u in ipairs(units) do
    local full = UnitName(u)
    local nm = ns.canon(full)
    local d = data[nm]
    if d and d.dur then
      if (d.broken or 0) > 0 or d.dur <= 50 then bad[#bad + 1] = ns.display(nm) .. RED .. " needs to repair (" .. d.dur .. "%)|r" end
      if d.free and d.free <= 3 then bad[#bad + 1] = ns.display(nm) .. YELLOW .. " has " .. d.free .. " bag slots|r" end
    else unknown[#unknown + 1] = full or "?" end
  end
  add(GOLD .. name:upper() .. "|r", true)
  if #bad > 0 then for _, t in ipairs(bad) do add(t) end
  elseif #unknown == 0 then add(GREEN .. "Everyone is repaired and has bag space.|r")
  else add(GREEN .. "You're repaired and have bag space.|r") end

  -- where everyone is
  add(GOLD .. "WHERE EVERYONE IS|r", true)
  local here = myArea()
  add("You" .. GRAY .. "  " .. (here ~= "" and here or name) .. "|r")
  for _, u in ipairs(units) do
    local full = UnitName(u) or "?"
    local d = data[ns.canon(full)]
    local state = ""
    local online = unitState(UnitIsConnected, u)
    local dead = unitState(UnitIsDeadOrGhost, u)
    if online == false then state = RED .. "offline|r"
    elseif dead == true then state = RED .. "dead|r"
    else
      local inR, checked = unitState(UnitInRange, u)
      if checked == false or inR == nil then state = ""
      elseif inR == true then state = GREEN .. "with you|r"
      else state = YELLOW .. "out of range|r" end
    end
    local sub = d and d.sub and d.sub ~= "" and d.sub or nil
    add(full .. "  " .. state .. GRAY .. (sub and ("  " .. sub) or "") .. "|r")
  end

  -- quests for this dungeon, across the whole party. Everyone's Guild Board sends its quest log silently over the
  -- party addon channel when you zone in (and whenever quests change), so this shows who has what, who's done,
  -- and gives a Share button (you have it, they can take it) or an Ask button (they have it, you can take it).
  local mine = P and P.shareable() or {}
  local myLog = {}
  for _, q in ipairs(questLog()) do if q.zone == name then myLog[q.id] = q end end
  local ids, seen = {}, {}
  local function addId(id) if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  for id in pairs(myLog) do addId(id) end
  for _, d in pairs(data) do for id, m in pairs(d.meta or {}) do if m.zone == name then addId(id) end end end
  table.sort(ids, function(a, b) return (myLog[a] and 0 or 1) < (myLog[b] and 0 or 1) or ((myLog[a] and 0 or 1) == (myLog[b] and 0 or 1) and a < b) end)
  add(GOLD .. "QUESTS FOR THIS DUNGEON|r", true)
  if #ids == 0 then add(GRAY .. (#units > 0 and "Nobody in the group has a quest for here." or "None in your log.") .. "|r") end
  for i, id in ipairs(ids) do
    if i > 10 then add(GRAY .. "+" .. (#ids - 10) .. " more|r"); break end
    local q = myLog[id]
    local title = q and q.title or questTitle(id)
    local who, takers, owner = {}, {}, nil
    if q then who[#who + 1] = "you" .. (q.complete and (GREEN .. " (done)|r") or "") end
    for nm, d in pairs(data) do
      local m = d.meta and d.meta[id]
      if m or (d.quests and d.quests[id]) then
        who[#who + 1] = ns.display(nm) .. ((m and m.done) and (GREEN .. " (done)|r") or "")
        owner = owner or nm
      elseif d.answered and d.wants and d.wants[id] and not (P.giveBlocked and P.giveBlocked(nm, id)) then
        takers[#takers + 1] = ns.display(nm)
      end
    end
    local t = title .. GRAY .. "  " .. table.concat(who, ", ") .. "|r"
    if q and mine[id] and #takers > 0 then
      add(t .. YELLOW .. "  " .. table.concat(takers, ", ") .. " can take it|r", false, nil,
        { btn = "Share", fn = function() P.share(id); C_Timer.After(1, function() ns.partyRefresh(true) end) end })
    elseif not q and owner then
      local why = (P.takeBlocked and P.takeBlocked(owner, id)) or ((P.completed and P.completed(id)) and "you already did it")
        or ((P.prereqOK and not P.prereqOK(id)) and "you need an earlier quest first")
      if why then add(t .. GRAY .. "  (" .. why .. ")|r")
      else add(t, false, nil, { btn = "Ask", fn = function() P.ask(owner, id) end }) end
    else
      add(t)
    end
  end

  if #bossKills > 0 then
    add(GOLD .. "BOSSES DOWN|r", true)
    for _, b in ipairs(bossKills) do add(GREEN .. "x |r" .. b) end
  end

  add(GOLD .. "TOOLS|r", true)
  add("Run report: damage, healing, damage taken", false, nil, { btn = "Open", fn = function() SlashCmdList["GUILDBOARD"]("run") end })
  if #unknown > 0 then add(GRAY .. table.concat(unknown, ", ") .. ": no Guild Board, so no repair or bag info|r") end
end

local function dungeonCheck()
  local now = inDungeon()
  if now and not wasInDungeon then
    bossKills = {}
    local c = db()
    if c.tab ~= "dungeon" then c.prevTab = c.tab end
    if ns.partyRefresh then ns.partyRefresh(true) end
    ns.openTracker("dungeon")
  elseif wasInDungeon and not now then
    local c = db()
    if c.tab == "dungeon" then c.tab = c.prevTab or "party" end
  end
  wasInDungeon = now
  if now and ns.party and ns.party.zone then
    local a = myArea()
    if a ~= lastZoneSent then lastZoneSent = a; ns.party.zone(a) end
  end
end

-- ===== window =====
local frame, rows, tabs, settings = nil, {}, {}, nil
local ROWH, MAXROWS, WIDTH = 18, 34, 370

local function makeSettings()
  settings = CreateFrame("Frame", "GuildBoardTrackerSettings", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  settings:SetSize(250, 40 + #LABELS * 20); settings:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0); settings:SetFrameStrata("DIALOG")
  if settings.SetBackdrop then
    settings:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    settings:SetBackdropColor(0.05, 0.04, 0.03, 0.95); settings:SetBackdropBorderColor(0.9, 0.72, 0.4, 0.9)
  end
  local t = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 12, -10); t:SetText("Options")
  local y = -32
  local hasCT = ClaudeTasks_List ~= nil or (ctasks and ctasks.id ~= nil)
  local shown = {}
  for _, l in ipairs(LABELS) do
    if hasCT or (l[1] ~= "claude" and l[1] ~= "pclaude") then shown[#shown + 1] = l end
  end
  settings:SetHeight(40 + #shown * 20)
  for _, l in ipairs(shown) do
    if not l[2] then
      local h = settings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); h:SetPoint("TOPLEFT", 12, y - 4); h:SetText(l[1]:upper())
    else
      local cb = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
      cb:SetSize(20, 20); cb:SetPoint("TOPLEFT", 10, y + 2)
      cb:SetChecked(opt(l[1]) and true or false)
      cb:SetScript("OnClick", function(self)
        db().opts[l[1]] = self:GetChecked() and true or false
        if l[1] == "hideCombat" and frame and InCombatLockdown and InCombatLockdown() then
          if opt("hideCombat") then frame:Hide() elseif db().shown then frame:Show() end
        end
        if l[1] == "fade" and ns.trackerFade then ns.trackerFade() end
        ns.trackerRefresh()
      end)
      local lab = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); lab:SetPoint("LEFT", cb, "RIGHT", 2, 0); lab:SetText(l[2])
    end
    y = y - 20
  end
  settings:Hide()
end

local function build()
  frame = CreateFrame("Frame", "GuildBoardTracker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, 120); frame:SetFrameStrata("MEDIUM"); frame:SetClampedToScreen(true)
  local c = db()
  if c.pos then frame:SetPoint(c.pos[1], UIParent, c.pos[1], c.pos[2], c.pos[3]) else frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120) end
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.05, 0.04, 0.03, 0.85); frame:SetBackdropBorderColor(0.9, 0.72, 0.4, 0.8)
  end
  frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint(); db().pos = { p, x, y }
  end)
  local TABNAME = { personal = "Personal", party = "Party", share = "Share", dungeon = "Dungeon" }
  for i, name in ipairs({ "personal", "party", "share", "dungeon" }) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(66, 18); b:SetPoint("TOPLEFT", 8 + (i - 1) * 67, -6); b:SetText(TABNAME[name])
    b:SetScript("OnClick", function() db().tab = name; if name ~= "personal" then ns.partyRefresh(true) end; ns.trackerRefresh() end)
    tabs[name] = b
  end
  local gear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); gear:SetSize(22, 18); gear:SetPoint("TOPRIGHT", -30, -6); gear:SetText("*")
  gear:SetScript("OnClick", function() if not settings then makeSettings() end; settings:SetShown(not settings:IsShown()) end)
  gear:SetScript("OnEnter", function(b) GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:SetText("Options"); GameTooltip:AddLine("What to track, fade, hide in combat", 1, 1, 1); GameTooltip:Show() end)
  gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() db().shown = false; frame:Hide(); if settings then settings:Hide() end end)
  frame:SetScript("OnHide", function() if settings then settings:Hide() end end)
  tinsert(UISpecialFrames, "GuildBoardTracker")      -- Esc closes it
  for i = 1, MAXROWS do
    local y = -30 - (i - 1) * ROWH
    local r = { y = y }
    r.btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); r.btn:SetSize(64, 16); r.btn:SetPoint("TOPRIGHT", -8, y + 1)
    r.btn:SetText("Share next"); r.btn:Hide()
    r.skip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); r.skip:SetSize(40, 16); r.skip:SetPoint("RIGHT", r.btn, "LEFT", -3, 0)
    r.skip:SetText("Skip"); r.skip:Hide()
    r.skip:SetScript("OnEnter", function(b)
      GameTooltip:SetOwner(b, "ANCHOR_LEFT"); GameTooltip:SetText("Skip this quest")
      GameTooltip:AddLine("Takes it off this list. Bring it back from the \"skipped\" line at the bottom.", 1, 1, 1, true); GameTooltip:Show()
    end)
    r.skip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT", 12, y - 2); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    rows[i] = r
  end
end

-- fade: see-through until your mouse is over the window (or its options)
local FADED = 0.35
local fadeTick
ns.trackerFade = function()
  if not frame then return end
  if not opt("fade") then
    if fadeTick then fadeTick:Cancel(); fadeTick = nil end
    frame:SetAlpha(1); return
  end
  if fadeTick or not (C_Timer and C_Timer.NewTicker) then return end
  fadeTick = C_Timer.NewTicker(0.15, function()
    if not frame or not frame:IsShown() then return end
    local over = (MouseIsOver and MouseIsOver(frame)) or (settings and settings:IsShown() and MouseIsOver and MouseIsOver(settings))
    local want = over and 1 or FADED
    local a = frame:GetAlpha()
    if math.abs(a - want) > 0.01 then frame:SetAlpha(a + (want - a) * 0.5) end
  end)
end

-- quest log tracking (the same watch list shift-click in the quest log uses)
local function isWatched(id)
  if C_QuestLog and C_QuestLog.GetQuestWatchType then return C_QuestLog.GetQuestWatchType(id) ~= nil end
  local idx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
  return idx and IsQuestWatched and IsQuestWatched(idx) and true or false
end
local function toggleWatch(id)
  if isWatched(id) then
    if C_QuestLog and C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(id)
    else local idx = C_QuestLog.GetLogIndexForQuestID(id); if idx and RemoveQuestWatch then RemoveQuestWatch(idx) end end
    return
  end
  local ok
  if C_QuestLog and C_QuestLog.AddQuestWatch then ok = C_QuestLog.AddQuestWatch(id)
  else local idx = C_QuestLog.GetLogIndexForQuestID(id); if idx and AddQuestWatch then AddQuestWatch(idx); ok = true end end
  if ok == false then print("|cff33ff99Guild Board|r Your quest tracker is full. Untrack something first.") end
end

local function render()
  if not frame then return end
  local c = db()
  local tab = c.tab or "personal"
  local out = {}
  local function add(t, header, shareId, x) out[#out + 1] = { t = t, h = header, share = shareId, x = x } end
  local ok, err
  if tab == "party" then ok, err = pcall(party, add) elseif tab == "share" then ok, err = pcall(shareTab, add)
  elseif tab == "dungeon" then ok, err = pcall(dungeonTab, add) else ok, err = pcall(personal, add) end
  if not ok then add(RED .. "Tracker error: " .. tostring(err) .. "|r"); if ns.logError then pcall(ns.logError, "tracker", tostring(err)) end end
  if #out == 0 then add(GREEN .. "All clear.|r" .. GRAY .. (tab == "personal" and " Nothing to fix or turn in." or "") .. "|r") end
  for name, b in pairs(tabs) do if name == tab then b:LockHighlight() else b:UnlockHighlight() end end
  if #out > MAXROWS then out[MAXROWS] = { t = GRAY .. "+" .. (#out - MAXROWS + 1) .. " more|r" } end
  local n = math.min(#out, MAXROWS)
  for i, r in ipairs(rows) do
    local o = out[i]
    if o and i <= n then
      local x = o.x
      local skipId = x and x.skipId
      local hasBtn = o.share or (x and (x.btn or x.plan))
      r.text:SetWidth(WIDTH - (hasBtn and 96 or 24) - (skipId and 44 or 0))
      r.text:SetText(o.t or "")
      if skipId then
        r.skip:SetScript("OnClick", function() local c2 = db(); c2.skip = c2.skip or {}; c2.skip[skipId] = true; ns.trackerRefresh() end)
        r.skip:Show()
      else r.skip:Hide() end
      r.btn:SetScript("OnEnter", nil); r.btn:SetScript("OnLeave", nil)
      if o.share then
        r.btn:SetText("Share next")
        r.btn:SetScript("OnClick", function() ns.party.share(o.share); C_Timer.After(1, function() ns.partyRefresh(true) end) end)
        r.btn:Show()
      elseif x and x.btn then
        r.btn:SetText(x.btn)
        r.btn:SetScript("OnClick", function() pcall(x.fn); ns.trackerRefresh() end)
        r.btn:Show()
      elseif x and x.plan and ns.planToggleItem then
        r.btn:SetText(ns.planHas(x.plan.key) and "On list" or "+ To-Do")
        r.btn:SetScript("OnClick", function() pcall(ns.planToggleItem, x.plan); ns.trackerRefresh() end)
        r.btn:Show()
      elseif x and x.track then
        local qid = x.track
        r.btn:SetText(isWatched(qid) and "Untrack" or "Track")
        r.btn:SetScript("OnClick", function() toggleWatch(qid); ns.trackerRefresh() end)
        r.btn:SetScript("OnEnter", function(b)
          GameTooltip:SetOwner(b, "ANCHOR_LEFT"); GameTooltip:SetText(isWatched(qid) and "Stop tracking" or "Track this quest")
          GameTooltip:AddLine("Same as shift-clicking it in your quest log: shows it in the objective tracker.", 1, 1, 1, true); GameTooltip:Show()
        end)
        r.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.btn:Show()
      else r.btn:Hide() end
    else r.text:SetText(""); r.btn:Hide(); r.skip:Hide() end
  end
  frame:SetHeight(38 + n * ROWH)
end

local pending
ns.trackerRefresh = function()
  if not frame or not frame:IsShown() or pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = nil; pcall(render) end)
end
ns.openTracker = function(tab)
  if not frame then build() end
  local c = db()
  if tab then c.tab = tab end
  c.shown = true
  if not (opt("hideCombat") and InCombatLockdown and InCombatLockdown()) then frame:Show() end
  ns.trackerFade()
  pcall(render)
end
ns.toggleTracker = function()
  if frame and frame:IsShown() then db().shown = false; frame:Hide() else ns.openTracker() end
end

-- Kris's Claude Tasks list over the party channel (read only; his Claude Tasks addon sends it)
local function onCT(msg, sender)
  local who = ns.canon(sender)
  if who == ns.me() then return end
  local kind, p1, p2, p3, p4, p5, p6, p7 = strsplit("^", msg)
  if kind == "H" then
    if ctasks.id ~= p1 then ctasks = { id = p1, title = p3, from = who, tasks = {} } end
  elseif kind == "T" and p1 == ctasks.id then
    local i = tonumber(p2)
    if i then ctasks.tasks[i] = { who = (p3 ~= "" and p3 or nil), text = p7 or "" } end
  elseif kind == "D" and p1 == ctasks.id then
    local i = tonumber(p2)
    if i and ctasks.tasks[i] and p3 == "1" then ctasks.tasks[i] = nil end
  end
  ns.trackerRefresh()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY",
  "PLAYER_EQUIPMENT_CHANGED", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "TRAINER_SHOW", "SKILL_LINES_CHANGED", "CHAT_MSG_ADDON",
  "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "BOSS_KILL", "ENCOUNTER_END", "PLAYER_DEAD", "UNIT_CONNECTION", "QUEST_WATCH_LIST_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
local rangeTick
ev:SetScript("OnEvent", function(_, e, ...)
  if e == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, CT_PREFIX) end
    -- the tracker never opens by itself; the minimap button or /gb track opens it
  elseif e == "CHAT_MSG_ADDON" then
    local prefix, msg, _, sender = ...
    if prefix == CT_PREFIX and msg then pcall(onCT, msg, sender or "") end
  elseif e == "PLAYER_REGEN_DISABLED" then
    if frame and opt("hideCombat") then frame:Hide() end
  elseif e == "PLAYER_REGEN_ENABLED" then
    if frame and db().shown == true then frame:Show(); ns.trackerRefresh() end
  elseif e == "TRAINER_SHOW" then
    local isProf = IsTradeskillTrainer and IsTradeskillTrainer()
    if not isProf then db().trainedAt = UnitLevel("player") end
    ns.trackerRefresh()
  elseif e == "BOSS_KILL" or e == "ENCOUNTER_END" then
    local _, bname, _, _, success = ...
    if e == "BOSS_KILL" or success == 1 then
      bname = tostring(bname or "Boss")
      local seen = false
      for _, b in ipairs(bossKills) do if b == bname then seen = true end end
      if not seen then bossKills[#bossKills + 1] = bname end
    end
    ns.trackerRefresh()
  elseif e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" or e == "ZONE_CHANGED" or e == "ZONE_CHANGED_INDOORS" then
    pcall(dungeonCheck)
    -- range and dead/offline states change without an event, so the dungeon tab ticks while you're inside
    if not rangeTick and C_Timer and C_Timer.NewTicker then
      rangeTick = C_Timer.NewTicker(3, function() if wasInDungeon and frame and frame:IsShown() and db().tab == "dungeon" then ns.trackerRefresh() end end)
    end
    ns.trackerRefresh()
  else
    ns.trackerRefresh()
  end
end)
