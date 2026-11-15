-- Guild Board: every member who runs this shares level, class, zone, professions and a short
-- note over the hidden guild addon channel. Everyone ends up with the same roster.
--   /gb             show the roster (copy it with Ctrl+C to paste in Discord)
--   /gb note text   set your note, e.g. /gb note need Medium Leather, can make armor kits
--   /gb spec text   set your spec or role, e.g. /gb spec Prot tank
--   /gb run         after a dungeon or raid: damage, healing and damage taken for the group
--   /gb run last    the same, for the last fight only
--   /gb sync        ask everyone online to resend
-- Also shares spec and average item level. Shares nothing about gold, bags or individual gear.

local _, ns = ...
local PREFIX, VER = "GBOARD1", 2
local SEP = "^"
GuildBoardDB = GuildBoardDB or {}

local queue, heardThisSession = {}, {}

local function clean(s) return (tostring(s or ""):gsub("[%^|\n\r]", " ")) end

local function myProfs()
  local out = {}
  pcall(function()
    if GetProfessions and GetProfessionInfo then
      local list = { GetProfessions() }
      for i = 1, 6 do
        if list[i] then
          local name, _, rank, max = GetProfessionInfo(list[i])
          if name then out[#out + 1] = clean(name) .. ":" .. (rank or 0) .. ":" .. (max or 0) end
        end
      end
    elseif GetNumSkillLines then
      local keep = { Alchemy=1, Blacksmithing=1, Enchanting=1, Engineering=1, Herbalism=1, Leatherworking=1, Mining=1,
        Skinning=1, Tailoring=1, Cooking=1, ["First Aid"]=1, Fishing=1, Jewelcrafting=1, Inscription=1 }
      for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
        if not isHeader and keep[name] then out[#out + 1] = name .. ":" .. (rank or 0) .. ":" .. (max or 0) end
      end
    end
  end)
  return table.concat(out, ",")
end

local function mySpec()
  if GuildBoardDB.mySpec and GuildBoardDB.mySpec ~= "" then return GuildBoardDB.mySpec end
  local name
  pcall(function()
    local idx = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization())
      or (GetSpecialization and GetSpecialization())
    if idx and idx > 0 then
      local a, b = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo)(idx)
      name = (type(b) == "string" and b) or (type(a) == "table" and a.name) or nil
    end
  end)
  -- some clients report the class name here; that is not a spec, so leave it blank
  if name and name == UnitClass("player") then name = nil end
  return name or ""
end

local function myItemLevel()
  local ilvl
  pcall(function()
    if GetAverageItemLevel then local _, equipped = GetAverageItemLevel(); ilvl = equipped end
  end)
  if not ilvl or ilvl <= 0 then
    pcall(function()
      local sum, n = 0, 0
      for slot = 1, 18 do
        if slot ~= 4 then
          local link = GetInventoryItemLink("player", slot)
          if link then
            local lvl = (C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link))
              or (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link))
            if lvl then sum = sum + lvl; n = n + 1 end
          end
        end
      end
      if n > 0 then ilvl = sum / n end
    end)
  end
  return ilvl and math.floor(ilvl + 0.5) or 0
end

local function myFields()
  local _, classFile = UnitClass("player")
  local note = clean(GuildBoardDB.myNote or ""):sub(1, 40)
  return table.concat({ clean(UnitClass("player")), UnitLevel("player") or 0, clean(GetRealZoneText()), myProfs(), note, time(), clean(mySpec()):sub(1, 16), myItemLevel(), 0 }, SEP)
end

local function send(msg)
  if not (IsInGuild and IsInGuild()) then return end
  queue[#queue + 1] = msg:sub(1, 250)
end

local function broadcastSelf()
  send("D" .. SEP .. VER .. SEP .. myFields())
  if ns.broadcastExtra then pcall(ns.broadcastExtra) end
end
ns.send, ns.SEP, ns.clean = send, SEP, clean

local function store(key, class, level, zone, profs, note, ts, via, spec, ilvl, dps)
  ts = tonumber(ts) or 0; level = tonumber(level) or 0
  if key == "" or level < 1 then return end
  GuildBoardDB.members = GuildBoardDB.members or {}
  local cur = GuildBoardDB.members[key]
  if cur and (cur.ts or 0) >= ts then return end
  GuildBoardDB.members[key] = { class = class, level = level, zone = zone, profs = profs, note = note, ts = ts, via = via,
    spec = spec or "", ilvl = tonumber(ilvl) or 0, dps = tonumber(dps) or 0 }
end

local function shareKnown()
  -- after a random wait, pass along what we know about members who are not online to say it themselves
  local delay = 3 + math.random() * 8
  C_Timer.After(delay, function()
    broadcastSelf()
    local n = 0
    for key, m in pairs(GuildBoardDB.members or {}) do
      if not heardThisSession[key] and (time() - (m.ts or 0)) < 60 * 86400 and n < 40 then
        send(table.concat({ "E", key, m.class or "", m.level or 0, m.zone or "", m.profs or "", m.note or "", m.ts or 0, m.spec or "", m.ilvl or 0, m.dps or 0 }, SEP))
        n = n + 1
      end
    end
  end)
end

local function onMessage(prefix, msg, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" then return end
  local kind, rest = msg:match("^(%u)%^?(.*)$")
  local f = { strsplit(SEP, rest or "") }
  if kind == "D" then
    heardThisSession[sender] = true
    store(sender, f[2], f[3], f[4], f[5], f[6], f[7], "self", f[8], f[9], f[10])
  elseif kind == "E" then
    heardThisSession[f[1]] = true          -- someone already relayed it, no need for us to
    store(f[1], f[2], f[3], f[4], f[5], f[6], f[7], "relay", f[8], f[9], f[10])
  elseif kind == "R" then
    shareKnown()
  elseif ns.handlers and ns.handlers[kind] then
    ns.handlers[kind](sender, f)
  end
end

-- ===== roster window =====
local function rosterText()
  local rows = {}
  for key, m in pairs(GuildBoardDB.members or {}) do rows[#rows + 1] = { key = key, m = m } end
  table.sort(rows, function(a, b) if a.m.level ~= b.m.level then return a.m.level > b.m.level end return a.key < b.key end)
  local L = { "GUILD BOARD  (" .. #rows .. " members reporting, " .. date("%b %d %H:%M") .. ")", "" }
  local byProf = {}
  for _, r in ipairs(rows) do
    local m = r.m
    local name = r.key:gsub("%-.*$", "")
    local profs = {}
    for p in (m.profs or ""):gmatch("[^,]+") do
      local pn, rank, max = p:match("^(.-):(%d+):(%d+)$")
      if pn then
        profs[#profs + 1] = pn .. " " .. rank
        byProf[pn] = byProf[pn] or {}
        table.insert(byProf[pn], { name = name, rank = tonumber(rank) })
      end
    end
    local age = math.floor((time() - (m.ts or 0)) / 3600)
    local seen = age < 1 and "now" or (age < 48 and (age .. "h ago") or (math.floor(age / 24) .. "d ago"))
    local what = ((m.spec and m.spec ~= "" and m.spec ~= m.class) and (m.spec .. " ") or "") .. (m.class or "?")
    local extra = ((m.ilvl or 0) > 0 and ("  ilvl " .. m.ilvl) or "")
    L[#L + 1] = string.format("%-14s %2d %-22s %s%s", name, m.level, what, m.zone or "", extra)
    L[#L + 1] = "    " .. (#profs > 0 and table.concat(profs, ", ") or "no professions") .. "   (seen " .. seen .. ")"
    if m.note and m.note ~= "" then L[#L + 1] = "    Note: " .. m.note end
  end
  L[#L + 1] = ""; L[#L + 1] = "WHO CAN MAKE WHAT (highest skill first)"
  local names = {}
  for pn in pairs(byProf) do names[#names + 1] = pn end
  table.sort(names)
  for _, pn in ipairs(names) do
    table.sort(byProf[pn], function(a, b) return a.rank > b.rank end)
    local who = {}
    for _, w in ipairs(byProf[pn]) do who[#who + 1] = w.name .. " " .. w.rank end
    L[#L + 1] = pn .. ": " .. table.concat(who, ", ")
  end
  if ns.needsText then local ok, t = pcall(ns.needsText); if ok then L[#L + 1] = t end end
  return table.concat(L, "\n")
end

-- ===== run report (reads the game's built-in damage meter) =====
local function fmt(n)
  n = n or 0
  if n >= 1000000 then return string.format("%.2fm", n / 1000000) end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n))
end

local function meterSection(L, title, sessionType, dmType, perSecLabel)
  local ok, err = pcall(function()
    local sess = C_DamageMeter.GetCombatSessionFromType(sessionType, dmType)
    if not sess or not sess.combatSources or (issecretvalue and issecretvalue(sess.combatSources)) then
      L[#L + 1] = title .. ": no data"; return
    end
    local secs = sess.durationSeconds
    if issecretvalue and issecretvalue(secs) then secs = nil end
    local rows, total = {}, 0
    for _, src in ipairs(sess.combatSources) do
      local amt, name = src.totalAmount, src.name
      if not (issecretvalue and (issecretvalue(amt) or issecretvalue(name))) and (amt or 0) > 0 then
        rows[#rows + 1] = { name = tostring(name or "?"), amt = amt }; total = total + amt
      end
    end
    if #rows == 0 then L[#L + 1] = title .. ": nothing recorded"; return end
    table.sort(rows, function(a, b) return a.amt > b.amt end)
    L[#L + 1] = title .. "  (group total " .. fmt(total) .. ")"
    for i, r in ipairs(rows) do
      if i > 25 then break end
      local per = (secs and secs > 0 and perSecLabel) and ("  " .. fmt(r.amt / secs) .. " " .. perSecLabel) or ""
      L[#L + 1] = string.format("%2d. %-20s %8s%s  %d%%", i, r.name, fmt(r.amt), per, math.floor(r.amt / total * 100 + 0.5))
    end
  end)
  if not ok then L[#L + 1] = title .. ": could not read (" .. tostring(err) .. ")" end
  L[#L + 1] = ""
end

local function runText(lastOnly)
  local L = {}
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType and Enum.DamageMeterType) then
    return "The game's damage meter is not available on this client, so there is no run data to report."
  end
  local st = lastOnly and Enum.DamageMeterSessionType.Current or Enum.DamageMeterSessionType.Overall
  local secs
  pcall(function()
    local sess = C_DamageMeter.GetCombatSessionFromType(st, Enum.DamageMeterType.DamageDone)
    if sess and not (issecretvalue and issecretvalue(sess.durationSeconds)) then secs = sess.durationSeconds end
  end)
  L[#L + 1] = (lastOnly and "LAST FIGHT" or "RUN REPORT") .. ": " .. (GetRealZoneText() or "?") .. ", " .. date("%b %d %H:%M")
  if secs and secs > 0 then L[#L + 1] = string.format("Time in combat: %d:%02d", math.floor(secs / 60), math.floor(secs % 60)) end
  L[#L + 1] = ""
  meterSection(L, "DAMAGE DONE", st, Enum.DamageMeterType.DamageDone, "dps")
  meterSection(L, "HEALING DONE", st, Enum.DamageMeterType.HealingDone, "hps")
  meterSection(L, "DAMAGE TAKEN", st, Enum.DamageMeterType.DamageTaken, nil)
  if not lastOnly then L[#L + 1] = "Covers everything since the damage meter was last reset. Reset it before the next run." end
  return table.concat(L, "\n")
end

local frame
local function show(text)
  if not frame then
    frame = CreateFrame("Frame", "GuildBoardFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(600, 440); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
    if frame.SetBackdrop then
      frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      frame:SetBackdropColor(0, 0, 0, 0.92)
    end
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); title:SetText("Guild Board: Ctrl+C copies it for Discord. Esc closes.")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    local scroll = CreateFrame("ScrollFrame", "GuildBoardScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32); scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local edit = CreateFrame("EditBox", "GuildBoardEdit", scroll)
    edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal); edit:SetWidth(550); edit:SetAutoFocus(false)
    if edit.SetMaxLetters then edit:SetMaxLetters(0) end
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)
    frame.edit = edit
  end
  frame.edit:SetText(text or rosterText())
  frame:Show(); frame.edit:SetFocus(); frame.edit:HighlightText()
end

-- ===== wiring =====
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    pcall(onMessage, ...)
  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(3, function() pcall(broadcastSelf) end)
  elseif event == "PLAYER_ENTERING_WORLD" and not ev.started then
    ev.started = true
    local ok = pcall(function()
      if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
      elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
    end)
    -- one message every 1.3s keeps us far under the game's addon chat limit
    C_Timer.NewTicker(1.3, function()
      local msg = table.remove(queue, 1)
      if msg then
        pcall(function()
          if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
          elseif SendAddonMessage then SendAddonMessage(PREFIX, msg, "GUILD") end
        end)
      end
    end)
    C_Timer.After(12, function() pcall(broadcastSelf); send("R") end)
    C_Timer.NewTicker(900, function() pcall(broadcastSelf) end)   -- refresh every 15 min
  end
end)

SLASH_GUILDBOARD1 = "/gb"
SLASH_GUILDBOARD2 = "/guildboard"
SlashCmdList["GUILDBOARD"] = function(arg)
  arg = arg or ""
  local cmd, rest = arg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "note" then
    GuildBoardDB.myNote = clean(rest):sub(1, 60)
    pcall(broadcastSelf)
    print("|cff33ff99Guild Board|r: note set to \"" .. GuildBoardDB.myNote .. "\"")
  elseif cmd == "spec" then
    GuildBoardDB.mySpec = clean(rest):sub(1, 16)
    pcall(broadcastSelf)
    print("|cff33ff99Guild Board|r: spec set to \"" .. GuildBoardDB.mySpec .. "\"")
  elseif cmd == "run" then
    local ok, err = pcall(function() show(runText(rest:lower() == "last")) end)
    if not ok then print("Guild Board error: " .. tostring(err)) end
  elseif cmd == "sync" then
    pcall(broadcastSelf); send("R")
    print("|cff33ff99Guild Board|r: asked everyone online to resend. Give it 15 seconds, then /gb")
  else
    local ok, err = pcall(show)
    if not ok then print("Guild Board error: " .. tostring(err)) end
  end
end
