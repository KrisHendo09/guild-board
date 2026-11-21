-- Guild Board core: keeps the addon healthy across versions.
--   * Every feature runs inside ns.safe(). An error is logged (not thrown at the player). A feature that errors
--     5 times in one session switches itself off until the next /reload, so one bug can't spam or break the rest.
--   * Saved data is checked on login. Anything the wrong shape is repaired or reset, piece by piece, and data
--     older than 60 days is pruned. A schema number lets future versions migrate old data instead of choking on it.
--   * Unknown message types from newer versions are ignored, so old and new versions can share a guild.
--   * Guild officers can switch a broken feature off for everyone (/gb disable <feature>) until a fixed version
--     ships. Turning it back on: /gb enable <feature>. Only officers' switches are honored.
--   * New errors are also sent quietly over the guild addon channel (once each per session, at most 5), so the
--     maintainer's copy collects everyone's bugs in GuildBoardDB.guildErrors for triage. Only the feature name,
--     the error text and the addon version are sent.
--   * /gb bug opens a bug report with the version, game build and recent errors, ready to copy into Discord or
--     a GitHub issue.

local _, ns = ...
local unpack = unpack or table.unpack
ns.handlers = ns.handlers or {}
ns.SCHEMA = 4
local GREEN, GRAY = "|cff33ff99", "|cff9d9d9d"
local MAX_ERRORS_PER_FEATURE = 5
local errorCount, disabledThisSession = {}, {}

local function version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = get and get("GuildBoard", "Version"); return type(v) == "string" and v or "?"
end
ns.version = version

local reported, reportedCount = {}, 0
local function shareError(feature, msg, count)
  -- tell the guild about a new error once per session (max 5), so the maintainer's addon collects them
  local key = feature .. msg
  if reported[key] or reportedCount >= 5 or not ns.send then return end
  reported[key] = true; reportedCount = reportedCount + 1
  local S = ns.SEP or "^"
  ns.send(table.concat({ "B", version(), feature, count or 1, (msg:gsub("[%^|\n\r]", " ")):sub(1, 170) }, S))
end

local function logError(feature, err)
  GuildBoardDB = GuildBoardDB or {}
  GuildBoardDB.errors = type(GuildBoardDB.errors) == "table" and GuildBoardDB.errors or {}
  local e = GuildBoardDB.errors
  local msg = tostring(err):gsub("Interface\\AddOns\\", "")
  for _, old in ipairs(e) do
    if old.feature == feature and old.msg == msg then old.count = (old.count or 1) + 1; old.last = time(); shareError(feature, msg, old.count); return end
  end
  table.insert(e, 1, { feature = feature, msg = msg:sub(1, 300), count = 1, first = time(), last = time(), ver = version() })
  while #e > 20 do table.remove(e) end
  if feature ~= "data" then shareError(feature, msg, 1) end
end

function ns.featureOff(feature)
  if disabledThisSession[feature] then return true end
  local k = GuildBoardDB and GuildBoardDB.killswitch
  return type(k) == "table" and k[feature] ~= nil
end

-- run fn safely; returns ok plus fn's results
function ns.safe(feature, fn, ...)
  if ns.featureOff(feature) then return false end
  local res = { pcall(fn, ...) }
  if not res[1] then
    logError(feature, res[2])
    errorCount[feature] = (errorCount[feature] or 0) + 1
    if errorCount[feature] == MAX_ERRORS_PER_FEATURE then
      disabledThisSession[feature] = true
      print(GREEN .. "Guild Board|r: the " .. feature .. " feature hit a bug and paused itself until /reload. Type /gb bug to report it.")
    end
  end
  return unpack(res)
end

-- wrap a function so it always runs through ns.safe
function ns.guard(feature, fn)
  return function(...) return select(2, ns.safe(feature, fn, ...)) end
end

-- ===== names =====
-- WoW Forever shows names like "Jay Spaceman", but addon messages arrive from "Jay-Realm". Everything is filed
-- under the first word (what the game uses for mail and whispers); ns.display turns it back into the full name.
ns.canon = function(x)
  if not x then return x end
  x = tostring(x):gsub("%-.*$", "")
  return x:match("^(%S+)") or x
end
ns.fullNames = {}
ns.display = function(x)
  local k = ns.canon(x)
  return (k and ns.fullNames[k]) or k or "?"
end
local function learnNames()
  local me = UnitName and UnitName("player")
  if me then ns.fullNames[ns.canon(me)] = me end
  for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
    local n = GetGuildRosterInfo(i)
    if n then n = n:gsub("%-.*$", ""); ns.fullNames[ns.canon(n)] = n end
  end
end
ns.learnNames = learnNames

-- ===== saved data repair and migration =====
local SHAPES = { members = "table", needs = "table", crafts = "table", myNeeds = "table", myCrafts = "table", gear = "table",
  wants = "table", myWants = "table", quests = "table", deaths = "table", hearths = "table", myFlights = "table",
  errors = "table", guildErrors = "table", killswitch = "table", switchLog = "table", myNote = "string", mySpec = "string", mmAngle = "number", schema = "number" }

local function repair()
  if type(GuildBoardDB) ~= "table" then GuildBoardDB = {} end
  local db = GuildBoardDB
  local fixed = 0
  for k, want in pairs(SHAPES) do
    if db[k] ~= nil and type(db[k]) ~= want then db[k] = nil; fixed = fixed + 1 end
  end
  -- per-member tables: drop any entry that is not a table
  for _, k in ipairs({ "members", "needs", "crafts", "gear", "wants", "quests", "hearths" }) do
    if db[k] then
      for who, v in pairs(db[k]) do if type(v) ~= "table" then db[k][who] = nil; fixed = fixed + 1 end end
    end
  end
  -- file everyone under one name (1.3 and older saved "Jay Spaceman" and "Jay-Realm" as two people); newest copy wins
  for _, k in ipairs({ "members", "needs", "crafts", "gear", "wants", "quests", "hearths", "versions" }) do
    if db[k] then
      local merged = {}
      for who, v in pairs(db[k]) do
        local key = ns.canon(who)
        local old = merged[key]
        local t = function(e) return tonumber(e.ts) or tonumber(e.at) or 0 end
        if not old or t(v) > t(old) then merged[key] = v end
        if key ~= who then fixed = fixed + 0 end
      end
      db[k] = merged
    end
  end
  -- prune anything nobody has refreshed in 60 days
  local cutoff = time() - 60 * 86400
  for _, k in ipairs({ "members", "needs", "crafts", "gear", "wants", "quests", "hearths" }) do
    if db[k] then
      for who, v in pairs(db[k]) do if (tonumber(v.ts) or 0) > 0 and v.ts < cutoff then db[k][who] = nil end end
    end
  end
  -- migrations between schema versions go here, oldest first
  local from = tonumber(db.schema) or 1
  if from < 3 then db.deaths = db.deaths or {} end
  db.schema = ns.SCHEMA
  if fixed > 0 then logError("data", "repaired " .. fixed .. " damaged saved entries on login") end
end
ns.repair = repair

-- ===== errors reported by guildmates (read by the maintainer's Claude sync) =====
ns.handlers.B = function(sender, f)
  GuildBoardDB.guildErrors = type(GuildBoardDB.guildErrors) == "table" and GuildBoardDB.guildErrors or {}
  local g = GuildBoardDB.guildErrors
  local ver, feature, count, msg = f[1] or "?", f[2] or "?", tonumber(f[3]) or 1, f[4] or ""
  for _, x in ipairs(g) do
    if x.who == sender and x.feature == feature and x.msg == msg then x.count = math.max(x.count, count); x.last = time(); x.ver = ver; return end
  end
  table.insert(g, 1, { who = sender, ver = ver, feature = feature, msg = msg, count = count, first = time(), last = time() })
  while #g > 100 do table.remove(g) end
end

-- ===== officer kill switch =====
local function isOfficer(name)
  if not (IsInGuild and IsInGuild()) then return false end
  local short = ns.canon(name or "")
  for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
    local n, _, rankIndex = GetGuildRosterInfo(i)
    if n and ns.canon(n) == short then return (rankIndex or 99) <= 1 end
  end
  return false
end
ns.isOfficer = isOfficer

ns.handlers.X = function(sender, f)
  local feature, onoff = f[1], f[2]
  if not feature or feature == "" or not isOfficer(sender) then return end
  GuildBoardDB.killswitch = GuildBoardDB.killswitch or {}
  local who = sender:gsub("%-.*$", "")
  GuildBoardDB.switchLog = type(GuildBoardDB.switchLog) == "table" and GuildBoardDB.switchLog or {}
  if onoff == "off" then
    if not GuildBoardDB.killswitch[feature] then
      print(GREEN .. "Guild Board|r: " .. who .. " switched off " .. feature .. " for the guild until a fix ships.")
    end
    GuildBoardDB.killswitch[feature] = { by = who, at = time() }
  else
    if GuildBoardDB.killswitch[feature] then print(GREEN .. "Guild Board|r: " .. who .. " switched " .. feature .. " back on.") end
    GuildBoardDB.killswitch[feature] = nil
  end
  -- keep a history of who flipped what, newest first
  table.insert(GuildBoardDB.switchLog, 1, { feature = feature, state = onoff, by = who, at = time() })
  while #GuildBoardDB.switchLog > 50 do table.remove(GuildBoardDB.switchLog) end
end

function ns.setFeature(feature, on)
  if not isOfficer(UnitName("player")) then print(GREEN .. "Guild Board|r: only guild officers can switch features for everyone."); return end
  ns.handlers.X(UnitName("player"), { feature, on and "on" or "off" })
  ns.send("X" .. (ns.SEP or "^") .. feature .. (ns.SEP or "^") .. (on and "on" or "off"))
  print(GREEN .. "Guild Board|r: " .. feature .. " is now " .. (on and "on" or "off") .. " for everyone running 1.3 or newer.")
end

-- ===== bug report =====
function ns.bugText(note)
  local L = {}
  local gameVersion, build
  if GetBuildInfo then gameVersion, build = GetBuildInfo() end
  L[#L + 1] = "Version " .. version() .. "  |  game " .. tostring(gameVersion or "?") .. " build " .. tostring(build or "?") .. "  |  " .. date("%Y-%m-%d %H:%M")
  L[#L + 1] = "Character level " .. (UnitLevel("player") or "?") .. " " .. (UnitClass("player") or "?") .. ", in " .. (GetRealZoneText() or "?")
  local off = {}
  for k in pairs(disabledThisSession) do off[#off + 1] = k .. " (paused)" end
  for k, v in pairs(GuildBoardDB.killswitch or {}) do
    off[#off + 1] = k .. " (switched off by " .. (type(v) == "table" and (v.by or "?") .. " " .. date("%m-%d %H:%M", v.at or 0) or "an officer") .. ")"
  end
  if #off > 0 then L[#L + 1] = "Switched off: " .. table.concat(off, ", ") end
  L[#L + 1] = ""
  L[#L + 1] = "What happened: " .. (note and note ~= "" and note or "(type it here before you copy)")
  L[#L + 1] = ""
  local e = GuildBoardDB.errors or {}
  if #e == 0 then L[#L + 1] = "No errors recorded." end
  for i, x in ipairs(e) do
    if i > 8 then break end
    L[#L + 1] = string.format("[%s] x%d %s (v%s): %s", x.feature or "?", x.count or 1, date("%m-%d %H:%M", x.last or 0), x.ver or "?", x.msg or "?")
  end
  L[#L + 1] = ""
  local log = GuildBoardDB.switchLog or {}
  if #log > 0 then
    L[#L + 1] = "Officer switch history:"
    for i, x in ipairs(log) do
      if i > 5 then break end
      L[#L + 1] = string.format("  %s %s turned %s %s", date("%m-%d %H:%M", x.at or 0), x.by or "?", x.feature or "?", x.state or "?")
    end
    L[#L + 1] = ""
  end
  L[#L + 1] = "Post this in #addons on Discord or at github.com/KrisHendo09/guild-board/issues"
  return table.concat(L, "\n")
end

function ns.clearErrors() GuildBoardDB.errors = {}; for k in pairs(disabledThisSession) do disabledThisSession[k] = nil end; errorCount = {} end

local core = CreateFrame("Frame")
core:RegisterEvent("PLAYER_LOGIN")
core:SetScript("OnEvent", function()
  pcall(learnNames)
  local ok, err = pcall(repair)
  if not ok then GuildBoardDB = { schema = ns.SCHEMA }; logError("data", "saved data was unreadable and was reset: " .. tostring(err)) end
  if GuildRoster then pcall(GuildRoster) elseif C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
end)
