-- Game Plan: a small checklist you build yourself, with an arrow to the next stop.
--   Add things from the Tracker (the "+ Plan" button on a quest, turn-in or upkeep line), or paste a list of steps.
--   Left-click the minimap button or /plan opens it. Drag it anywhere. Up and down arrows reorder, x removes.
--   Click a step to point the arrow at it; otherwise the arrow follows the first open step that has a location.
--   Quests check themselves off when you turn them in. Quest locations come from Questie when it is installed.
--   /plan paste   opens a box: one step per line, then Add or Replace. Line format:
--       [both] Buy Coarse Thread @ Hillsbrad Foothills 62.2 19.0 | optional note | optional rules
--     "[both]" or "[party]" at the front shares that step with your group; "[Name]" sends it to that one person.
--     Rules (all optional, separated by ;): quest=Title; when=ready or turnin; item=Name; count=5; noitem=Name;
--       skill=Cooking; level=50; equip=Name; plevel=24; arrive=true
--   /plan arrow   arrow on or off        /plan clear   remove finished steps        /plan share   resend shared steps
local _, ns = ...
local PREFIX = "GBPLAN1"
local GOLD, GRAY, GREEN, BLUE = "|cffe8b964", "|cff9d9d9d", "|cff33ff99", "|cff66ccff"
local WIDTH, ROWH, MAXROWS = 290, 18, 12
local ARROW_TEX = "Interface\\AddOns\\GuildBoard\\arrow"

local function myName() return UnitName("player") or "?" end
local function db()
  GuildBoardDB.plan = GuildBoardDB.plan or {}
  local p, k = GuildBoardDB.plan, myName()
  p[k] = p[k] or {}
  local c = p[k]
  c.items = c.items or {}
  c.seenQ = c.seenQ or {}
  c.had = c.had or {}
  if c.arrowOn == nil then c.arrowOn = true end
  return c
end
local function say(msg) print("|cff33ff99Game Plan|r " .. msg) end
local function clean(s) return (tostring(s or ""):gsub("[%^\n\r]", " ")) end
local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local frame, rows, arrow, pasteFrame
local refresh

-- ===== items =====
local function find(key)
  for i, it in ipairs(db().items) do if it.key == key then return i, it end end
end
local function isMine(it)
  local w = it.who
  if not w or w == "" then return true end
  w = w:lower()
  if w == "both" or w == "party" then return true end
  return myName():lower():find(w, 1, true) ~= nil
end
local function addItem(it, quiet)
  if not it or not it.key or not it.text or it.text == "" then return end
  local i, old = find(it.key)
  if old then
    it.done, it.pdone = old.done, old.pdone
    db().items[i] = it
  else
    table.insert(db().items, it)
  end
  if not quiet and refresh then refresh() end
  return it
end
ns.planHas = function(key) return find(key) ~= nil end
ns.planAdd = function(it) local r = addItem(it); if ns.openPlan then ns.openPlan() end; return r end
ns.planRemove = function(key) local i = find(key); if i then table.remove(db().items, i); if refresh then refresh() end end end
ns.planToggleItem = function(it) if ns.planHas(it.key) then ns.planRemove(it.key) else ns.planAdd(it) end end

-- ===== where things are =====
local zoneCache
local function buildZones()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then return end
  local id = C_Map.GetBestMapForUnit("player")
  if not id then return end
  local top = id
  for _ = 1, 10 do
    local info = C_Map.GetMapInfo(top)
    if info and info.parentMapID and info.parentMapID > 0 then top = info.parentMapID else break end
  end
  local kids = C_Map.GetMapChildrenInfo(top, nil, true)
  if not kids or #kids == 0 then return end
  local cache = {}
  for _, k in ipairs(kids) do
    if k.name and k.mapID then
      local key = k.name:lower()
      if not cache[key] or k.mapType == 3 then cache[key] = k.mapID end
    end
  end
  zoneCache = cache
end
local function mapFor(zone)
  if not zone then return end
  if not zoneCache then buildZones() end
  return zoneCache and zoneCache[zone:lower()]
end
local function worldPos(mapID, x, y)      -- x, y in 0..100 map coordinates
  if not (mapID and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x / 100, y / 100))
  if not ok or not pos then return end
  local n, w = pos:GetXY()
  return n, w, inst
end

local function questLog()                 -- [id] = { title, complete }, count, [title] = state
  local out, n, byTitle = {}, 0, {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local q = C_QuestLog.GetInfo(i)
      if q and not q.isHeader and q.questID then
        local done = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID)) and true or false
        out[q.questID] = { title = q.title, complete = done }
        n = n + 1
        if q.title then if done then byTitle[q.title] = "ready" elseif not byTitle[q.title] then byTitle[q.title] = "active" end end
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, GetNumQuestLogEntries() do
      local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
      if not isHeader and title then
        local done = (isComplete == 1 or isComplete == true)
        if questID then out[questID] = { title = title, complete = done } end
        n = n + 1
        if done then byTitle[title] = "ready" elseif not byTitle[title] then byTitle[title] = "active" end
      end
    end
  end
  return out, n, byTitle
end

-- Questie knows where quest targets and turn-ins stand. Everything here is wrapped: no Questie, no location.
local spotCache = {}
local function questieSpot(id, complete)
  if not QuestieLoader or not QuestieLoader.ImportModule then return end
  local key = id .. (complete and "c" or "o")
  local hit = spotCache[key]
  if hit and GetTime() - hit.at < 6 then return hit.map, hit.x, hit.y end
  local ok, map, x, y = pcall(function()
    local QDB = QuestieLoader:ImportModule("QuestieDB")
    local ZDB = QuestieLoader:ImportModule("ZoneDB")
    local q = QDB.GetQuest(id)
    if not q then return end
    local cands = {}
    local function addSpawns(kind, eid)
      local e = (kind == "object") and QDB:GetObject(eid) or QDB:GetNPC(eid)
      for area, list in pairs((e and e.spawns) or {}) do
        local m = ZDB:GetUiMapIdByAreaId(area)
        if m then
          for _, xy in ipairs(list) do
            if #cands < 300 and xy[1] and xy[2] and xy[1] >= 0 then cands[#cands + 1] = { m, xy[1], xy[2] } end
          end
        end
      end
    end
    if not complete then
      for _, o in ipairs(q.ObjectiveData or {}) do
        if (o.Type == "monster" or o.Type == "object") and o.Id then addSpawns(o.Type, o.Id) end
      end
    end
    if complete or #cands == 0 then
      local f = q.Finisher
      if f and f.Id and (complete or #cands == 0) then addSpawns(f.Type, f.Id) end
    end
    if #cands == 0 then return end
    local pn, pw, _, pinst = UnitPosition("player")
    local best, bestD
    for _, c in ipairs(cands) do
      local n, w, inst = worldPos(c[1], c[2], c[3])
      if n and pn and (not inst or not pinst or inst == pinst) then
        local d = (n - pn) ^ 2 + (w - pw) ^ 2
        if not bestD or d < bestD then best, bestD = c, d end
      end
    end
    best = best or cands[1]
    return best[1], best[2], best[3]
  end)
  if not ok then map = nil end
  spotCache[key] = { at = GetTime(), map = map, x = x, y = y }
  return map, x, y
end

local function locate(it, log)            -- returns mapID, x, y for a step, or nil
  if it.x and it.y and (it.zone or it.mapID) then
    local m = it.mapID or mapFor(it.zone)
    if m then return m, it.x, it.y end
    return nil
  end
  if it.questID then
    local q = log and log[it.questID]
    if q then return questieSpot(it.questID, q.complete) end
  end
end

-- ===== auto check =====
local function skillRank(name)
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local n, isHeader, _, rank = GetSkillLineInfo(i)
      if not isHeader and n == name then return rank end
    end
  end
  if GetProfessions and GetProfessionInfo then
    local list = { GetProfessions() }
    for i = 1, 6 do
      if list[i] then
        local n, _, rank = GetProfessionInfo(list[i])
        if n == name then return rank end
      end
    end
  end
end
local function itemCount(name)
  if C_Item and C_Item.GetItemCount then local ok, n = pcall(C_Item.GetItemCount, name); if ok and n then return n end end
  if GetItemCount then local ok, n = pcall(GetItemCount, name); if ok and n then return n end end
end
local function rulesMet(it, byTitle, qcount)
  local a, c = it.auto, db()
  if type(a) ~= "table" then return false end
  local any = false
  if a.quest then
    any = true
    local st = byTitle[a.quest]
    if st then c.seenQ[a.quest] = true end
    local turnedIn = c.seenQ[a.quest] and not st and qcount > 0
    if a.when == "ready" then
      if st ~= "ready" and not turnedIn then return false end
    elseif not turnedIn then return false end
  end
  if a.item then any = true; local n = itemCount(a.item); if not n or n < (tonumber(a.count) or 1) then return false end end
  if a.noitem then
    any = true
    local n = itemCount(a.noitem)
    if n and n > 0 then c.had[a.noitem] = true end
    if not (c.had[a.noitem] and n == 0) then return false end
  end
  if a.skill then any = true; local r = skillRank(a.skill); if not r or r < (tonumber(a.level) or 1) then return false end end
  if a.equip then any = true; if not (IsEquippedItem and IsEquippedItem(a.equip)) then return false end end
  if a.plevel then any = true; if (UnitLevel("player") or 0) < tonumber(a.plevel) then return false end end
  if a.arrive then
    any = true
    local m, x, y = locate(it)
    local tn, tw, tinst = worldPos(m, x or 0, y or 0)
    local pn, pw, _, pinst = UnitPosition("player")
    if not (tn and pn) or (tinst and pinst and tinst ~= pinst) then return false end
    if (tn - pn) ^ 2 + (tw - pw) ^ 2 > 225 then return false end
  end
  return any
end

local send
local loginAt
local function markDone(it, auto)
  it.done = true
  if auto then say("done: " .. plain(it.text)) end
  if PlaySound then pcall(PlaySound, 856) end
  if ((it.who and it.who ~= "") or it.from) and send then send("D^" .. clean(it.key) .. "^1") end
end
local function autoTick()
  if not loginAt or GetTime() - loginAt < 12 then return end
  local c = db()
  local log, qcount, byTitle = questLog()
  local changed = false
  for _, it in ipairs(c.items) do
    if not it.done and not it.noAuto and isMine(it) then
      if it.questID then
        local q = log[it.questID]
        if q then
          c.seenQ[it.questID] = true
          if it.ready ~= q.complete then it.ready = q.complete; changed = true end
        elseif c.seenQ[it.questID] and qcount > 0 then
          markDone(it, true); changed = true
        end
      elseif it.auto then
        local ok, met = pcall(rulesMet, it, byTitle, qcount)
        if ok and met then markDone(it, true); changed = true end
      end
    end
  end
  if changed and refresh then refresh() end
end

-- ===== sharing over the party channel (silent) =====
local queue, sentAt, lastFull = {}, {}, -1000
local function chan()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end
send = function(msg) if chan() then queue[#queue + 1] = msg:sub(1, 250) end end
local function packRules(a)
  local parts = {}
  for k, v in pairs(a) do parts[#parts + 1] = k .. "=" .. (clean(tostring(v)):gsub("[|=;]", " ")) end
  return table.concat(parts, ";")
end
local function parseRules(s)
  local a, n = {}, 0
  for pair in (s or ""):gmatch("[^;]+") do
    local k, v = pair:match("^%s*(%w+)%s*=%s*(.-)%s*$")
    if k and v ~= "" then
      if v == "true" then a[k] = true else a[k] = tonumber(v) or v end
      n = n + 1
    end
  end
  if n > 0 then return a end
end
local function sendItem(it)
  if not it.who or it.who == "" or it.from then return end       -- only steps I marked as shared, never ones I was sent
  send(table.concat({ "I", clean(it.key), clean(it.who), clean(it.zone), it.x or "", it.y or "", clean(it.text):sub(1, 150) }, "^"))
  if it.note and it.note ~= "" then send("N^" .. clean(it.key) .. "^" .. clean(it.note):sub(1, 200)) end
  if type(it.auto) == "table" then send("A^" .. clean(it.key) .. "^" .. packRules(it.auto)) end
  if it.done then send("D^" .. clean(it.key) .. "^1") end
end
local function shareAll(force)
  if not chan() then return end
  local now = GetTime()
  if not force and now - lastFull < 60 then return end
  lastFull = now
  for _, it in ipairs(db().items) do sendItem(it) end
  send("R")
end
local function onMessage(msg, sender)
  local mine_at = sentAt[msg]
  if mine_at and GetTime() - mine_at < 8 then sentAt[msg] = nil; return end
  local name = (Ambiguate and Ambiguate(sender or "", "short")) or (sender or ""):match("^[^-]+") or "?"
  if name == myName() then return end
  local kind, key, p2, p3, p4, p5, p6 = strsplit("^", msg)
  if kind == "R" then
    if GetTime() - lastFull > 10 then lastFull = GetTime(); for _, it in ipairs(db().items) do sendItem(it) end end
  elseif kind == "I" and key then
    local who = (p2 or ""):lower()
    if who == "both" or who == "party" or (who ~= "" and myName():lower():find(who, 1, true)) then
      local _, old = find(key)
      addItem({ key = key, from = name, text = p6 or "", zone = (p3 ~= "" and p3 or nil), x = tonumber(p4), y = tonumber(p5),
                note = old and old.note, auto = old and old.auto }, true)
      if refresh then refresh() end
    end
  elseif kind == "N" and key then
    local _, it = find(key)
    if it and it.from then it.note = p2 end
  elseif kind == "A" and key then
    local _, it = find(key)
    if it and it.from then it.auto = parseRules(p2) end
  elseif kind == "D" and key then
    local _, it = find(key)
    if it then it.pdone = (p2 == "1") and name or nil; if refresh then refresh() end end
  end
end

-- ===== paste =====
local function parseLine(line)
  line = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
  line = line:gsub("^[%-%*%d%.%)]+%s+", "")                     -- "1. ", "- ", "* "
  if line == "" then return end
  local who
  local tag, rest = line:match("^%[([^%]]+)%]%s*(.*)$")
  if tag then who, line = tag, rest end
  local head, note, rules = line, nil, nil
  local a, b, c = line:match("^(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
  if a then head, note, rules = a, b, c
  else
    a, b = line:match("^(.-)%s*|%s*(.-)%s*$")
    if a then head, note = a, b end
  end
  if note and note:find("=") and not rules and parseRules(note) and not note:find("%s%a+%s%a+%s") then rules, note = note, nil end
  local text, zone, x, y = head:match("^(.-)%s*@%s*(.-)%s+([%d%.]+)[,%s]+([%d%.]+)%s*$")
  if not text then text = head end
  if text == "" then return end
  return { key = "p:" .. clean(text):sub(1, 60), text = clean(text), who = who, zone = zone, x = tonumber(x), y = tonumber(y),
           note = (note and note ~= "") and note or nil, auto = parseRules(rules) }
end
local function importText(text, replace)
  local c = db()
  if replace then
    local keep = {}
    for _, it in ipairs(c.items) do if it.from or not (it.key or ""):find("^p:") then keep[#keep + 1] = it end end
    c.items = keep
  end
  local n = 0
  for line in (text or ""):gmatch("[^\r\n]+") do
    local it = parseLine(line)
    if it then addItem(it, true); n = n + 1 end
  end
  c.shown = true
  say(n .. " step" .. (n == 1 and "" or "s") .. " added.")
  lastFull = -1000
  shareAll(true)
  if ns.openPlan then ns.openPlan() end
end
ns.planImport = importText

local function showPaste()
  if not pasteFrame then
    local f = CreateFrame("Frame", "GuildBoardPlanPaste", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(520, 340); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f:SetBackdropColor(0, 0, 0, 0.92)
    end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); title:SetText("Game Plan: paste steps, one per line (Ctrl+V)")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", 0, -26); hint:SetText("Buy thread @ Hillsbrad Foothills 62.2 19.0 | note      Start a line with [both] to share it")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    local scroll = CreateFrame("ScrollFrame", "GuildBoardPlanPasteScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -44); scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    local edit = CreateFrame("EditBox", "GuildBoardPlanPasteEdit", scroll)
    edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal); edit:SetWidth(470); edit:SetAutoFocus(false)
    if edit.SetMaxLetters then edit:SetMaxLetters(0) end
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    local addB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); addB:SetSize(120, 22); addB:SetPoint("BOTTOMLEFT", 14, 10); addB:SetText("Add to plan")
    addB:SetScript("OnClick", function() pcall(importText, edit:GetText(), false); f:Hide() end)
    local repB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); repB:SetSize(160, 22); repB:SetPoint("LEFT", addB, "RIGHT", 8, 0); repB:SetText("Replace pasted steps")
    repB:SetScript("OnClick", function() pcall(importText, edit:GetText(), true); f:Hide() end)
    tinsert(UISpecialFrames, "GuildBoardPlanPaste")
    pasteFrame = f
  end
  pasteFrame.edit:SetText("")
  pasteFrame:Show()
  pasteFrame.edit:SetFocus()
end
ns.planPaste = function() local ok, err = pcall(showPaste); if not ok then say("paste window error: " .. tostring(err)) end end

-- ===== window =====
local function visible()
  local out = {}
  for i, it in ipairs(db().items) do if isMine(it) then out[#out + 1] = { i = i, it = it } end end
  return out
end
local function target(log)
  local c = db()
  if c.pin then
    local _, it = find(c.pin)
    if it and not it.done then local m, x, y = locate(it, log); if m then return it, m, x, y end end
  end
  for _, it in ipairs(c.items) do
    if not it.done and isMine(it) then
      local m, x, y = locate(it, log)
      if m then return it, m, x, y end
    end
  end
end

local function move(i, dir)
  local items = db().items
  local j = i + dir
  while items[j] and not isMine(items[j]) do j = j + dir end
  if items[i] and items[j] then items[i], items[j] = items[j], items[i] end
end

local function small(parent, label, tip)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(16, 16); b:SetText(label)
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function build()
  frame = CreateFrame("Frame", "GuildBoardPlan", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, 60); frame:SetFrameStrata("MEDIUM"); frame:SetClampedToScreen(true)
  local c = db()
  if c.pos then frame:SetPoint(c.pos[1], UIParent, c.pos[1], c.pos[2], c.pos[3]) else frame:SetPoint("LEFT", UIParent, "LEFT", 30, 60) end
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
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", 10, -8)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() db().shown = false; frame:Hide(); if arrow then arrow:Hide() end end)
  local pasteB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); pasteB:SetSize(48, 18); pasteB:SetPoint("TOPRIGHT", -28, -5); pasteB:SetText("Paste")
  pasteB:SetScript("OnClick", function() ns.planPaste() end)
  local clearB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); clearB:SetSize(48, 18); clearB:SetPoint("RIGHT", pasteB, "LEFT", -2, 0); clearB:SetText("Clear")
  clearB:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Remove finished steps"); GameTooltip:Show() end)
  clearB:SetScript("OnLeave", function() GameTooltip:Hide() end)
  clearB:SetScript("OnClick", function()
    local keep = {}
    for _, it in ipairs(db().items) do if not it.done then keep[#keep + 1] = it end end
    db().items = keep; refresh()
  end)
  frame:SetScript("OnHide", function() if arrow and UIParent:IsShown() then arrow:Hide() end end)
  tinsert(UISpecialFrames, "GuildBoardPlan")
  rows = {}
  for i = 1, MAXROWS do
    local y = -28 - (i - 1) * ROWH
    local r = { y = y }
    r.cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate"); r.cb:SetSize(18, 18); r.cb:SetPoint("TOPLEFT", 6, y + 1)
    r.hit = CreateFrame("Button", nil, frame); r.hit:SetSize(WIDTH - 84, ROWH); r.hit:SetPoint("TOPLEFT", 26, y)
    r.hit:RegisterForClicks("LeftButtonUp")
    r.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT", 26, y - 2); r.text:SetWidth(WIDTH - 84); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.del = small(frame, "x", "Remove"); r.del:SetPoint("TOPRIGHT", -6, y)
    r.down = small(frame, "v", "Move down"); r.down:SetPoint("RIGHT", r.del, "LEFT", -1, 0)
    r.up = small(frame, "^", "Move up"); r.up:SetPoint("RIGHT", r.down, "LEFT", -1, 0)
    rows[i] = r
  end
  frame.more = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

  arrow = CreateFrame("Frame", "GuildBoardPlanArrow", UIParent)
  arrow:SetSize(56, 56); arrow:SetFrameStrata("MEDIUM"); arrow:SetClampedToScreen(true)
  if c.apos then arrow:SetPoint(c.apos[1], UIParent, c.apos[1], c.apos[2], c.apos[3]) else arrow:SetPoint("CENTER", UIParent, "CENTER", 0, 220) end
  arrow:EnableMouse(true); arrow:SetMovable(true); arrow:RegisterForDrag("LeftButton")
  arrow:SetScript("OnDragStart", arrow.StartMoving)
  arrow:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint(); db().apos = { p, x, y }
  end)
  arrow.tex = arrow:CreateTexture(nil, "ARTWORK"); arrow.tex:SetAllPoints(arrow); arrow.tex:SetTexture(ARROW_TEX)
  arrow.dist = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal"); arrow.dist:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
  arrow.label = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); arrow.label:SetPoint("TOP", arrow.dist, "BOTTOM", 0, -2)
  arrow.label:SetWidth(240); arrow.label:SetJustifyH("CENTER")
  local acc, slow, cur = 0, 0, nil
  arrow:SetScript("OnUpdate", function(self, el)
    acc = acc + el; slow = slow + el
    if acc < 0.05 then return end
    acc = 0
    if slow > 1 or not cur then
      slow = 0
      local log = questLog()
      local it, m, x, y = target(log)
      if not it then self:Hide(); return end
      local n, w, inst = worldPos(m, x, y)
      cur = { n = n, w = w, inst = inst, text = plain(it.text), x = x, y = y }
      self.label:SetText(cur.text)
    end
    local pn, pw, _, pinst = UnitPosition("player")
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not (cur.n and pn) then self.tex:Hide(); self.dist:SetText(string.format("%.1f, %.1f", cur.x or 0, cur.y or 0)); return end
    if cur.inst and pinst and cur.inst ~= pinst then self.tex:Hide(); self.dist:SetText("Other continent"); return end
    local dn, dw = cur.n - pn, cur.w - pw
    local dist = math.sqrt(dn * dn + dw * dw)
    self.tex:Show()
    if dist < 12 then
      self.tex:SetRotation(0); self.tex:SetVertexColor(0.2, 1, 0.2); self.dist:SetText("You're here")
    else
      self.tex:SetVertexColor(1, 0.82, 0)
      if facing then self.tex:SetRotation(math.atan2(dw, dn) - facing) end
      self.dist:SetText(string.format("%d yd", dist))
    end
  end)
  arrow.reset = function() cur = nil end
end

refresh = function()
  if not frame then return end
  local c = db()
  local vis = visible()
  local open = 0
  for _, v in ipairs(vis) do if not v.it.done then open = open + 1 end end
  frame.title:SetText(GOLD .. "Game Plan|r" .. GRAY .. "  " .. open .. " to do|r")
  local n = math.min(#vis, MAXROWS)
  for i, r in ipairs(rows) do
    local v = vis[i]
    if v and i <= n then
      local it = v.it
      local t = plain(it.text)
      if it.done then t = GRAY .. t .. "|r"
      else
        if it.ready then t = t .. GREEN .. "  turn in|r" end
        if c.pin == it.key then t = GOLD .. "> |r" .. t end
      end
      if it.from then t = t .. BLUE .. "  from " .. it.from .. "|r" end
      if it.pdone then t = t .. GREEN .. "  (" .. it.pdone .. " done)|r" end
      r.text:SetText(t)
      r.cb:SetChecked(it.done and true or false)
      r.cb:SetScript("OnClick", function(self)
        if self:GetChecked() then markDone(it, false) else it.done = nil; it.noAuto = true; if (it.who and it.who ~= "") or it.from then send("D^" .. clean(it.key) .. "^0") end end
        if c.pin == it.key then c.pin = nil end
        refresh()
      end)
      r.hit:SetScript("OnClick", function() c.pin = (c.pin ~= it.key) and it.key or nil; refresh() end)
      r.hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(plain(it.text), 1, 0.82, 0, 1, true)
        if it.note then GameTooltip:AddLine(it.note, 1, 1, 1, true) end
        if it.zone and it.x then GameTooltip:AddLine(string.format("%s %.1f, %.1f", it.zone, it.x, it.y or 0), 0.6, 0.6, 0.6) end
        GameTooltip:AddLine("Click: point the arrow here", 0.5, 0.8, 1)
        GameTooltip:Show()
      end)
      r.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r.up:SetScript("OnClick", function() move(v.i, -1); refresh() end)
      r.down:SetScript("OnClick", function() move(v.i, 1); refresh() end)
      r.del:SetScript("OnClick", function() table.remove(c.items, v.i); if c.pin == it.key then c.pin = nil end; refresh() end)
      r.cb:Show(); r.hit:Show(); r.up:Show(); r.down:Show(); r.del:Show()
    else
      r.text:SetText(""); r.cb:Hide(); r.hit:Hide(); r.up:Hide(); r.down:Hide(); r.del:Hide()
    end
  end
  frame.more:ClearAllPoints()
  local extra = 0
  if #vis == 0 then
    frame.more:SetPoint("TOPLEFT", 12, -30)
    frame.more:SetText("Empty. Open the Tracker and press + Plan on a line,\nor press Paste to drop in a list of steps.")
    extra = 30
  elseif #vis > MAXROWS then
    frame.more:SetPoint("TOPLEFT", 26, -28 - n * ROWH - 2)
    frame.more:SetText("+" .. (#vis - MAXROWS) .. " more. Clear finished steps to see them.")
    extra = 16
  else frame.more:SetText("") end
  frame:SetHeight(36 + n * ROWH + extra)
  if arrow then
    if arrow.reset then arrow.reset() end
    if c.arrowOn and c.shown and frame:IsShown() and target(questLog()) then arrow:Show() else arrow:Hide() end
  end
  if ns.trackerRefresh then ns.trackerRefresh() end
end
ns.planRefresh = function() if refresh then refresh() end end

ns.openPlan = function()
  if not frame then build() end
  db().shown = true
  frame:Show()
  pcall(refresh)
end
ns.togglePlan = function()
  if frame and frame:IsShown() then db().shown = false; frame:Hide(); if arrow then arrow:Hide() end else ns.openPlan() end
end

-- A private list file (the optional ClaudeTasks data addon) drops straight in, no pasting needed.
local function importListFile()
  local L = ClaudeTasks_List
  if type(L) ~= "table" or type(L.tasks) ~= "table" or #L.tasks == 0 then return end
  local c = db()
  if c.lastList == L.id then return end
  local keep = {}
  for _, it in ipairs(c.items) do if not it.list then keep[#keep + 1] = it end end
  c.items = keep
  for i, t in ipairs(L.tasks) do
    if t and t.text then
      addItem({ key = "l:" .. tostring(L.id) .. ":" .. i, list = true, text = t.text, who = t.who, zone = t.zone, x = t.x, y = t.y,
                note = t.note, auto = t.auto }, true)
    end
  end
  c.lastList = L.id
  c.shown = true
  say("new steps loaded: " .. (L.title or ""))
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do pcall(ev.RegisterEvent, ev, e) end
local rosterWait
ev:SetScript("OnEvent", function(_, e, ...)
  if e == "PLAYER_LOGIN" then
    loginAt = GetTime()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    pcall(buildZones)
    pcall(importListFile)
    C_Timer.NewTicker(2, function() pcall(autoTick) end)
    C_Timer.NewTicker(0.4, function()
      if #queue == 0 then return end
      local ch = chan()
      if not ch then queue = {}; return end
      local m = table.remove(queue, 1)
      sentAt[m] = GetTime()
      pcall(function()
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, m, ch)
        elseif SendAddonMessage then SendAddonMessage(PREFIX, m, ch) end
      end)
    end)
    C_Timer.After(8, function() pcall(shareAll) end)
    if db().shown then C_Timer.After(1, function() pcall(ns.openPlan) end) end
  elseif e == "CHAT_MSG_ADDON" then
    local prefix, msg, _, sender = ...
    if prefix == PREFIX and msg then pcall(onMessage, msg, sender or "") end
  elseif e == "GROUP_ROSTER_UPDATE" then
    if not rosterWait then rosterWait = true; C_Timer.After(5, function() rosterWait = nil; pcall(shareAll) end) end
  else
    if not zoneCache then pcall(buildZones) end
  end
end)

SLASH_GBPLAN1 = "/plan"
SLASH_GBPLAN2 = "/gameplan"
SlashCmdList["GBPLAN"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "paste" then ns.planPaste()
  elseif msg == "arrow" then db().arrowOn = not db().arrowOn; say("arrow " .. (db().arrowOn and "on" or "off")); if refresh then refresh() end
  elseif msg == "clear" then
    local keep = {}
    for _, it in ipairs(db().items) do if not it.done then keep[#keep + 1] = it end end
    db().items = keep; if refresh then refresh() end
  elseif msg == "share" then lastFull = -1000; shareAll(true); say(chan() and "shared steps sent to your party" or "you are not in a party")
  else ns.togglePlan() end
end
