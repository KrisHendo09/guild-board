-- Guild Board social features for a group of friends. All in game, nothing goes to Discord.
--   Roster: everyone in the guild (from the guild roster, addon or not), alts grouped under their main from guild
--           notes ("alt of Kris", "Kris alt", or just "Kris"), and anyone offline 7+ days hidden until they log in.
--   Shared quests: which friends are on the same quests as you, and a heads-up when you're in their zone.
--   Death log: every death with what killed you, a Hall of Shame, and a chat line when a friend dies.
--   Dings: a popup when a friend levels, plus a level race and who's falling behind.
--   Hearths and flights: where everyone's hearth is set and which flight paths you're missing.
--   Party check: when you zone into a dungeon, a quick look at empty slots and low item level in your group.

local _, ns = ...
local SEP = ns.SEP or "^"
local GREEN, GRAY, GOLD, RED = "|cff33ff99", "|cff9d9d9d", "|cffffd100", "|cffff6060"
local AWAY_DAYS = 7

local function db() return ns.db() end
local function short(k) return ns.display(k) end
local function me() return ns.me() end

-- ===== guild roster (works for everyone, addon or not) =====
local roster = {}   -- [short name] = { name, level, class, zone, online, daysAway, note, onote, rankIndex }
local function readRoster()
  local out = {}
  for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
    local name, _, rankIndex, level, class, zone, note, onote, online, _, classFile = GetGuildRosterInfo(i)
    if name then
      local y, mo, d, h = 0, 0, 0, 0
      if not online and GetGuildRosterLastOnline then y, mo, d, h = GetGuildRosterLastOnline(i) end
      local days = (y or 0) * 365 + (mo or 0) * 30 + (d or 0) + (h or 0) / 24
      out[(name:gsub("%-.*$", ""))] = { name = name, level = level or 0, class = class or "?", classFile = classFile, zone = zone or "", online = online and true or false,
        daysAway = online and 0 or days, note = note or "", onote = onote or "", rankIndex = rankIndex or 9 }
    end
  end
  return out
end

-- alt of whom? looks at public then officer note
local function mainOf(nm, r)
  for _, note in ipairs({ r.note, r.onote }) do
    local n = (note or ""):lower()
    if n ~= "" then
      for other in pairs(roster) do
        if other ~= nm then
          local o = other:lower()
          if n == o or n:find("alt of " .. o, 1, true) or n:find(o .. "'s alt", 1, true) or n:find(o .. " alt", 1, true)
            or n:find("alt " .. o, 1, true) or n:find("main: " .. o, 1, true) or n:find("main " .. o, 1, true) then
            return other
          end
        end
      end
    end
  end
end
ns.mainOf = function(nm) local r = roster[short(nm)]; return r and mainOf(short(nm), r) end

local function active(r) return r.online or (r.daysAway or 0) < AWAY_DAYS end

ns.rosterText = function()
  local L = {}
  local addon = (GuildBoardDB and GuildBoardDB.members) or {}
  local byShort = {}
  for key, m in pairs(addon) do byShort[short(key)] = m end
  local mains, alts, hidden = {}, {}, 0
  for nm, r in pairs(roster) do
    if not active(r) then hidden = hidden + 1
    else
      local main = mainOf(nm, r)
      if main and roster[main] then alts[main] = alts[main] or {}; table.insert(alts[main], nm)
      else mains[#mains + 1] = nm end
    end
  end
  -- mains whose only active character is an alt still show
  for main in pairs(alts) do
    local found = false
    for _, m in ipairs(mains) do if m == main then found = true end end
    if not found then mains[#mains + 1] = main end
  end
  table.sort(mains, function(a, b) local x, y = roster[a], roster[b]; if x.level ~= y.level then return x.level > y.level end return a < b end)
  L[#L + 1] = "GUILD BOARD  (" .. #mains .. " players, " .. date("%b %d %H:%M") .. ")" .. (hidden > 0 and ("  " .. hidden .. " offline " .. AWAY_DAYS .. "+ days hidden") or "")
  L[#L + 1] = ""
  local function line(nm, indent)
    local r = roster[nm]; local m = byShort[nm] or {}
    local status = r.online and "online" or (r.daysAway < 1 and "today" or (math.floor(r.daysAway) .. "d ago"))
    local profs = {}
    for p in (m.profs or ""):gmatch("[^,]+") do local pn, rank = p:match("^(.-):(%d+):"); if pn then profs[#profs + 1] = pn .. " " .. rank end end
    L[#L + 1] = string.format("%s%-22s %2d %-8s %-19s %s%s", indent, nm:sub(1, 22), r.level, r.class, (r.zone or ""):sub(1, 19), status,
      (m.ilvl or 0) > 0 and ("  ilvl " .. m.ilvl) or "")
    if #profs > 0 then L[#L + 1] = indent .. "    " .. table.concat(profs, ", ") end
    if m.note and m.note ~= "" then L[#L + 1] = indent .. "    Note: " .. m.note end
  end
  for _, nm in ipairs(mains) do
    if roster[nm] and active(roster[nm]) then line(nm, "") else L[#L + 1] = nm .. GRAY .. " (main, away)|r" end
    for _, a in ipairs(alts[nm] or {}) do line(a, "  alt ") end
  end
  -- who can make what (addon users)
  local byProf = {}
  for key, m in pairs(addon) do
    for p in (m.profs or ""):gmatch("[^,]+") do
      local pn, rank = p:match("^(.-):(%d+):")
      if pn and roster[short(key)] and active(roster[short(key)]) then byProf[pn] = byProf[pn] or {}; table.insert(byProf[pn], { short(key), tonumber(rank) }) end
    end
  end
  for pn, list in pairs(byProf) do
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i, x in ipairs(list) do list[i] = x[1] .. " " .. x[2] end
  end
  local names = {}
  for pn in pairs(byProf) do names[#names + 1] = pn end
  table.sort(names)
  if #names > 0 then L[#L + 1] = ""; L[#L + 1] = "WHO CAN MAKE WHAT" end
  for _, pn in ipairs(names) do L[#L + 1] = pn .. ": " .. table.concat(byProf[pn], ", ") end
  return table.concat(L, "\n")
end

-- ===== dings and level race =====
local lastLevels, baseline = {}, false
local function checkDings()
  if ns.featureOff("dings") then return end
  for nm, r in pairs(roster) do
    local old = lastLevels[nm]
    if baseline and old and r.level > old and nm ~= short(me()) then
      local msg = nm .. " hit " .. r.level .. "!"
      local extra = ns.unlockText and ns.unlockText(r.classFile or r.class, old, r.level, false)
      if extra then msg = msg .. " " .. extra end
      if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo.GUILD or { r = 0.25, g = 1, b = 0.25 }) end
      print(GREEN .. "Guild Board|r: " .. msg)
      if PlaySound and SOUNDKIT and SOUNDKIT.UI_GUILD_LEVEL_UP then pcall(PlaySound, SOUNDKIT.UI_GUILD_LEVEL_UP) end
    end
    lastLevels[nm] = r.level
  end
  baseline = true
end

local function raceText()
  local rows, sum, n = {}, 0, 0
  for nm, r in pairs(roster) do
    if active(r) and not mainOf(nm, r) then rows[#rows + 1] = { nm = nm, lv = r.level }; sum = sum + r.level; n = n + 1 end
  end
  if n == 0 then return "" end
  table.sort(rows, function(a, b) return a.lv > b.lv end)
  local avg = sum / n
  local L = { "", string.format("LEVEL RACE (group average %.1f)", avg) }
  local parts, behind = {}, {}
  local mine = UnitName("player")
  for i, r in ipairs(rows) do
    if i <= 5 or r.nm == mine then parts[#parts + 1] = i .. ". " .. r.nm .. " " .. r.lv end
    if r.lv <= avg - 3 then behind[#behind + 1] = r.nm .. " (" .. r.lv .. ")" end
  end
  L[#L + 1] = table.concat(parts, "   ")
  if #behind > 0 then L[#L + 1] = "Falling behind, worth a dungeon carry: " .. table.concat(behind, ", ") end
  return table.concat(L, "\n")
end

-- ===== shared quests =====
local function myQuests()
  local out = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local q = C_QuestLog.GetInfo(i)
      if q and not q.isHeader and q.questID then out[q.questID] = q.title end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, GetNumQuestLogEntries() do
      local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
      if title and not isHeader and id then out[id] = title end
    end
  end
  return out
end

ns.myQuests = myQuests

local lastQuests
local function broadcastQuests(force)
  if ns.featureOff("quests") then return end
  local ids = {}
  for id in pairs(myQuests()) do ids[#ids + 1] = id end
  table.sort(ids)
  local s = table.concat(ids, ",")
  local zone = GetRealZoneText() or ""
  if not force and s .. zone == lastQuests then return end
  lastQuests = s .. zone
  ns.send("Q" .. SEP .. time() .. SEP .. ns.clean(zone):sub(1, 30) .. SEP .. s:sub(1, 200))
end

ns.handlers.Q = function(sender, f)
  db().quests = db().quests or {}
  local ids = {}
  for id in (f[3] or ""):gmatch("%d+") do ids[tonumber(id)] = true end
  db().quests[sender] = { ts = tonumber(f[1]) or 0, zone = f[2] or "", ids = ids }
end

local function sharedText()
  local mine = myQuests()
  local L = { "", "SHARED QUESTS" }
  local any = false
  for id, title in pairs(mine) do
    local who = {}
    for key, q in pairs(db().quests or {}) do
      local r = roster[short(key)]
      if key ~= me() and q.ids and q.ids[id] and (not r or active(r)) then who[#who + 1] = short(key) .. (q.zone ~= "" and (" (" .. q.zone .. ")") or "") end
    end
    if #who > 0 then any = true; table.sort(who); L[#L + 1] = title .. ": " .. table.concat(who, ", ") end
  end
  if not any then L[#L + 1] = "nobody else with the addon is on your quests right now" end
  return table.concat(L, "\n")
end

local toldZone = {}
local function zoneHeadsUp()
  if ns.featureOff("quests") then return end
  local zone = GetRealZoneText() or ""
  if zone == "" or toldZone[zone] then return end
  local mine = myQuests()
  local hits = {}
  for key, q in pairs(db().quests or {}) do
    local r = roster[short(key)]
    if key ~= me() and q.zone == zone and r and r.online then
      local n = 0
      for id in pairs(q.ids or {}) do if mine[id] then n = n + 1 end end
      if n > 0 then hits[#hits + 1] = short(key) .. " (" .. n .. " shared)" end
    end
  end
  if #hits > 0 then
    toldZone[zone] = true
    print(GREEN .. "Guild Board|r: also questing in " .. zone .. ": " .. table.concat(hits, ", ") .. ". /gb shows which quests.")
  end
end

-- ===== death log =====
local lastHit
local ENV = { Falling = "falling", Drowning = "drowning", Fatigue = "fatigue", Fire = "fire", Lava = "lava", Slime = "slime" }
local function onCombatLog()
  if not CombatLogGetCurrentEventInfo then return end
  local _, sub, _, srcGUID, srcName, _, _, dstGUID, _, _, _, a12 = CombatLogGetCurrentEventInfo()
  if issecretvalue and (issecretvalue(dstGUID) or issecretvalue(srcName)) then return end
  if dstGUID ~= UnitGUID("player") then return end
  if sub == "ENVIRONMENTAL_DAMAGE" then
    lastHit = { name = ENV[a12] or tostring(a12 or "the world"), level = "", t = time() }
  elseif sub and sub:find("_DAMAGE$") and srcName then
    local lvl
    for _, u in ipairs({ "target", "focus", "mouseover", "targettarget" }) do
      if UnitExists(u) and UnitGUID(u) == srcGUID then lvl = UnitLevel(u) end
    end
    lastHit = { name = srcName, level = lvl and (lvl < 0 and "??" or tostring(lvl)) or "", t = time() }
  end
end

local function addDeath(who, killer, klvl, lvl, zone, ts)
  db().deaths = db().deaths or {}
  for _, d in ipairs(db().deaths) do if d.who == who and math.abs((d.ts or 0) - ts) < 5 then return false end end
  table.insert(db().deaths, 1, { who = who, killer = killer, klvl = klvl, lvl = tonumber(lvl) or 0, zone = zone, ts = ts })
  while #db().deaths > 300 do table.remove(db().deaths) end
  return true
end

local function onDeath()
  if ns.featureOff("deaths") then return end
  -- Forever forbids addons from reading the combat log, so the killer is taken from your target if it was fighting you
  local killer, klvl = "something", ""
  if UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then
    killer = UnitName("target") or killer
    local l = UnitLevel("target"); klvl = l and (l < 0 and "??" or tostring(l)) or ""
  end
  if lastHit and time() - lastHit.t <= 10 then killer, klvl = lastHit.name, lastHit.level end
  local lvl, zone, ts = UnitLevel("player") or 0, GetRealZoneText() or "", time()
  addDeath(me(), killer, klvl, lvl, zone, ts)
  ns.send(table.concat({ "K", ts, ns.clean(killer):sub(1, 40), klvl, lvl, ns.clean(zone):sub(1, 30) }, SEP))
end

ns.handlers.K = function(sender, f)
  local ts, killer, klvl, lvl, zone = tonumber(f[1]) or time(), f[2] or "something", f[3] or "", f[4] or "0", f[5] or ""
  if addDeath(sender, killer, klvl, lvl, zone, ts) and time() - ts < 300 then
    print(RED .. "Guild Board|r: " .. short(sender) .. " died to " .. killer .. (klvl ~= "" and (" (lvl " .. klvl .. ")") or "") .. " in " .. zone .. " at level " .. lvl .. ".")
  end
end

local function shameText()
  local L = { "", "HALL OF SHAME (last 7 days)" }
  local week = time() - 7 * 86400
  local counts, worst = {}, nil
  local recent = {}
  for _, d in ipairs(db().deaths or {}) do
    if (d.ts or 0) >= week then
      counts[short(d.who)] = (counts[short(d.who)] or 0) + 1
      local kl = tonumber(d.klvl)
      if kl and d.lvl and (not worst or (d.lvl - kl) > (worst.lvl - tonumber(worst.klvl))) then worst = d end
      if #recent < 5 then recent[#recent + 1] = d end
    end
  end
  local rows = {}
  for nm, n in pairs(counts) do rows[#rows + 1] = { nm = nm, n = n } end
  if #rows == 0 then L[#L + 1] = "nobody died this week. suspicious."; return table.concat(L, "\n") end
  table.sort(rows, function(a, b) return a.n > b.n end)
  local parts = {}
  for _, r in ipairs(rows) do parts[#parts + 1] = r.nm .. " " .. r.n end
  L[#L + 1] = "Deaths: " .. table.concat(parts, ", ")
  if worst then L[#L + 1] = string.format("Worst death: %s, level %d, killed by %s (lvl %s) in %s", short(worst.who), worst.lvl, worst.killer, worst.klvl, worst.zone) end
  for _, d in ipairs(recent) do
    L[#L + 1] = string.format("  %s  %s died to %s%s in %s at %d", date("%a %H:%M", d.ts), short(d.who), d.killer,
      (d.klvl ~= "" and (" (lvl " .. d.klvl .. ")") or ""), d.zone, d.lvl)
  end
  return table.concat(L, "\n")
end

-- ===== hearths and flight paths =====
local function scanFlights()
  db().myFlights = db().myFlights or {}
  if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID()) or {}) do
      local st = node.state
      local E = Enum and Enum.FlightPathState
      if node.name and (not E or st == E.Reachable or st == E.Current) then db().myFlights[(node.name:gsub(",.*$", ""))] = true end
    end
    return
  end
  if not NumTaxiNodes then return end
  for i = 1, NumTaxiNodes() do
    local t = TaxiNodeGetType and TaxiNodeGetType(i)
    local name = TaxiNodeName(i)
    if name and (t == "REACHABLE" or t == "CURRENT") then db().myFlights[(name:gsub(",.*$", ""))] = true end
  end
end

local function broadcastHearth()
  if ns.featureOff("hearths") then return end
  local fl = {}
  for n in pairs(db().myFlights or {}) do fl[#fl + 1] = ns.clean(n):gsub(";", " ") end
  table.sort(fl)
  local ts = time()
  local bind = ns.clean(GetBindLocation and GetBindLocation() or "")
  local chunks, cur = {}, {}
  for _, n in ipairs(fl) do
    if #table.concat(cur, ";") + #n > 180 then chunks[#chunks + 1] = table.concat(cur, ";"); cur = {} end
    cur[#cur + 1] = n
  end
  chunks[#chunks + 1] = table.concat(cur, ";")
  for i, c in ipairs(chunks) do ns.send(table.concat({ "H", ts, i, #chunks, bind:sub(1, 30), c }, SEP)) end
end

local pendingH = {}
ns.handlers.H = function(sender, f)
  db().hearths = db().hearths or {}
  local ts, part, total = tonumber(f[1]) or 0, tonumber(f[2]) or 1, tonumber(f[3]) or 1
  local p = pendingH[sender]
  if not p or p.ts ~= ts then p = { ts = ts, got = 0, flights = {} }; pendingH[sender] = p end
  for n in (f[5] or ""):gmatch("[^;]+") do p.flights[n] = true end
  p.got = p.got + 1
  if p.got >= total then db().hearths[sender] = { ts = ts, bind = f[4] or "", flights = p.flights }; pendingH[sender] = nil end
end

local function hearthText()
  local L = { "", "HEARTHS AND FLIGHT PATHS" }
  local all = {}
  local hearths = {}
  for key, h in pairs(db().hearths or {}) do
    local r = roster[short(key)]
    if key ~= me() and (not r or active(r)) then
      hearths[#hearths + 1] = short(key) .. ": " .. (h.bind ~= "" and h.bind or "?")
      for n in pairs(h.flights or {}) do all[n] = true end
    end
  end
  table.sort(hearths)
  L[#L + 1] = "You: " .. (GetBindLocation and GetBindLocation() or "?") .. (#hearths > 0 and ("   " .. table.concat(hearths, "   ")) or "")
  local missing = {}
  for n in pairs(all) do if not (db().myFlights or {})[n] then missing[#missing + 1] = n end end
  table.sort(missing)
  if #missing > 0 then L[#L + 1] = "Flight paths friends have that you don't: " .. table.concat(missing, ", ")
  else L[#L + 1] = "You have every flight path your friends have (open a flight master to refresh)." end
  return table.concat(L, "\n")
end

-- ===== party check on dungeon entry =====
local CORE = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16 }
local SN = { [1] = "Head", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [15] = "Back", [16] = "Weapon" }
local function partyCheck(announce)
  if ns.featureOff("partycheck") then return nil end
  local units = { "player" }
  for i = 1, 4 do if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end end
  if #units < 2 then return nil end
  local info, sum, n, nodata = {}, 0, 0, {}
  for _, u in ipairs(units) do
    local nm = UnitName(u)
    local g
    for key, v in pairs(db().gear or {}) do if ns.canon(key) == ns.canon(nm) then g = v end end
    if u == "player" then g = { slots = {} }; for _, s in ipairs(CORE) do local l = GetInventoryItemLink("player", s); g.slots[s] = l and 1 or 0 end end
    if g and g.slots then
      local empty, tot, c = {}, 0, 0
      local low = (UnitLevel(u) or 60) < 25
      for _, s in ipairs(CORE) do
        local v = g.slots[s] or 0
        if v == 0 then
          if not (low and (s == 1 or s == 3)) then empty[#empty + 1] = SN[s] end
        else tot = tot + v; c = c + 1 end
      end
      local avg = c > 0 and tot / c or 0
      info[#info + 1] = { nm = nm, empty = empty, avg = avg, self = (u == "player") }
      if u ~= "player" and avg > 0 then sum = sum + avg; n = n + 1 end
    else
      nodata[#nodata + 1] = nm
    end
  end
  local groupAvg = n > 0 and sum / n or 0
  local notes = {}
  for _, x in ipairs(info) do
    if #x.empty > 0 then notes[#notes + 1] = (x.self and "you" or x.nm) .. " has nothing on " .. table.concat(x.empty, ", ") end
    if not x.self and groupAvg > 0 and x.avg > 0 and x.avg < groupAvg * 0.7 then notes[#notes + 1] = x.nm .. " is well under the group's item level" end
  end
  local text = #notes > 0 and table.concat(notes, "; ") or "everyone looks geared"
  if #nodata > 0 then text = text .. GRAY .. " (no addon data for " .. table.concat(nodata, ", ") .. ")|r" end
  if announce then print(GREEN .. "Guild Board|r party check: " .. text) end
  return text
end

ns.partyGearText = function()
  local t = partyCheck(false)
  return t and ("|cffffd100GEAR CHECK|r\n" .. t) or nil
end

-- ===== window sections =====
-- the guild window shows these in this order (the roster and level race live on the Discord board now)
ns.windowSections = { shared = sharedText, shame = shameText, hearths = hearthText }
ns.socialText = function()
  local parts = {}
  for _, fn in ipairs({ raceText, sharedText, shameText, hearthText }) do
    local ok, t = ns.safe("window", fn)
    if ok and t then parts[#parts + 1] = t end
  end
  local ok, pc = ns.safe("partycheck", partyCheck, false)
  if ok and pc then parts[#parts + 1] = "\nPARTY CHECK\n" .. pc end
  return table.concat(parts, "\n")
end

-- ===== wiring =====
local prevMore = ns.broadcastMore
ns.broadcastMore = function()
  if prevMore then prevMore() end
  C_Timer.After(8, function() ns.safe("quests", broadcastQuests, true) end)
  C_Timer.After(10, function() ns.safe("hearths", broadcastHearth) end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "GUILD_ROSTER_UPDATE", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD",
  "TAXIMAP_OPENED", "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
local qTimer
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then
    C_Timer.NewTicker(60, function()
      if GuildRoster then pcall(GuildRoster) elseif C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    end)
  elseif e == "GUILD_ROSTER_UPDATE" then
    pcall(ns.learnNames)
    ns.safe("roster", function() roster = readRoster() end)
    ns.safe("dings", checkDings)
  elseif e == "QUEST_LOG_UPDATE" then
    if qTimer then return end
    qTimer = true
    C_Timer.After(15, function() qTimer = nil; ns.safe("quests", broadcastQuests, false) end)
  elseif e == "ZONE_CHANGED_NEW_AREA" then
    C_Timer.After(5, function() ns.safe("quests", broadcastQuests, false); ns.safe("quests", zoneHeadsUp) end)
  elseif e == "PLAYER_DEAD" then
    ns.safe("deaths", onDeath)
  elseif e == "TAXIMAP_OPENED" then
    ns.safe("hearths", function() local before = 0; for _ in pairs(db().myFlights or {}) do before = before + 1 end
      scanFlights(); local after = 0; for _ in pairs(db().myFlights or {}) do after = after + 1 end
      if after ~= before then broadcastHearth() end end)
  elseif e == "HEARTHSTONE_BOUND" then
    C_Timer.After(2, function() ns.safe("hearths", broadcastHearth) end)
  elseif e == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(6, function()
      local _, itype = GetInstanceInfo()
      if itype == "party" then ns.safe("partycheck", partyCheck, true) end
    end)
  end
end)
