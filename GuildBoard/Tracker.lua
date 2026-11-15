-- Tracker: one small window with two tabs.
--   Personal: Upkeep (repair, empty slots, bags, trainer, profession caps, reagents), quests ready to turn in,
--             and the next items from Claude's list when Kris's Claude Tasks addon is loaded.
--   Party:    what to fix first (quests to share, who needs to repair or empty bags), then the quests the group
--             has in common, current zone first, plus any plan Claude Tasks shares with you by name.
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
  hideCombat = true,
}
local LABELS = {
  { "Personal" },
  { "repair", "Repair at 50% or a broken item" }, { "slots", "Empty gear slots" }, { "bags", "Bags under 4 free" },
  { "trainer", "Class trainer visits" }, { "profcap", "Profession rank caps" }, { "reagents", "Reagents (ankhs, shards, ammo)" },
  { "turnins", "Quests ready to turn in" }, { "claude", "Claude's list" },
  { "Party" },
  { "pshare", "Quests to share" }, { "pquests", "Shared quests in order" }, { "pupkeep", "Party repair and bags" },
  { "pgear", "Gear check" }, { "pdungeons", "Dungeons everyone wants" }, { "pclaude", "Shared plan from your partner" },
  { "Window" }, { "hideCombat", "Hide in combat" },
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
          out[#out + 1] = { id = q.questID, title = q.title or ("Quest " .. q.questID), zone = zone, complete = done }
        end
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, GetNumQuestLogEntries() do
      local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
      if isHeader then zone = title or ""
      elseif title and id then
        local done = isComplete == 1 or isComplete == true
        if done and GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) == 0 then done = false end
        out[#out + 1] = { id = id, title = title, zone = zone, complete = done }
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
  if #up > 0 then add(GOLD .. "UPKEEP|r", true); for _, t in ipairs(up) do add(t) end end

  if opt("turnins") then
    local ready, here = {}, GetRealZoneText and GetRealZoneText() or ""
    for _, q in ipairs(questLog()) do if q.complete then ready[#ready + 1] = q end end
    table.sort(ready, function(a, b) if (a.zone == here) ~= (b.zone == here) then return a.zone == here end return a.title < b.title end)
    if #ready > 0 then
      add(GOLD .. "TURN IN|r" .. GRAY .. (#ready > 5 and ("  " .. #ready - 5 .. " more") or "") .. "|r", true)
      for i = 1, math.min(#ready, 5) do add(ready[i].title .. GRAY .. "  " .. ready[i].zone .. "|r") end
    end
  end

  if opt("claude") and ClaudeTasks_List and ClaudeTasks_List.tasks and #ClaudeTasks_List.tasks > 0 then
    local done = (ClaudeTasksDB and ClaudeTasksDB.listId == ClaudeTasks_List.id and ClaudeTasksDB.done) or {}
    local me, n, shown = (UnitName("player") or ""):lower(), 0, {}
    for i, t in ipairs(ClaudeTasks_List.tasks) do
      local mine = not t.who or t.who == "" or t.who:lower() == "both" or me:find(t.who:lower(), 1, true)
      if mine and not done[i] then n = n + 1; if #shown < 3 then shown[#shown + 1] = t.text end end
    end
    if n > 0 then
      add(GOLD .. "FROM CLAUDE|r" .. GRAY .. (n > 3 and ("  " .. n - 3 .. " more in /ct") or "") .. "|r", true)
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
      if d.answered then for id in pairs(d.wants or {}) do if mine[id] then share[#share + 1] = { id = id, title = mine[id], who = nm } end end end
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
    if #rows > 0 then
      add(GOLD .. "TOGETHER, IN ORDER|r", true)
      for i, r in ipairs(rows) do
        add(i .. ". " .. r.q.title .. (r.q.complete and (GREEN .. "  turn in|r") or "") .. GRAY .. "  " .. r.q.zone .. "|r")
      end
    end
  end

  if opt("pclaude") then
    local src = ctasks
    if ClaudeTasks_List and ClaudeTasks_List.tasks and #ClaudeTasks_List.tasks > 0 then src = ClaudeTasks_List end   -- Kris's own copy
    -- only tasks Claude addressed to you by name, or to "both"/"party". Untagged tasks are the sender's own, so a
    -- random guildie who groups with Kris never sees his to-do list.
    local me = (UnitName("player") or ""):lower()
    local list = {}
    for _, t in pairs(src.tasks or {}) do
      local w = t and t.who and t.who:lower() or ""
      if w == "both" or w == "party" or (w ~= "" and src ~= ClaudeTasks_List and me:find(w, 1, true)) then list[#list + 1] = t.text end
    end
    if #list > 0 then
      local from = src == ClaudeTasks_List and "YOUR SHARED PLAN" or ("PLAN FROM " .. (ns.display(src.from or "?")):upper())
      add(GOLD .. from .. "|r", true); for _, t in ipairs(list) do add(t) end
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

-- ===== window =====
local frame, rows, tabs, settings = nil, {}, {}, nil
local ROWH, MAXROWS, WIDTH = 18, 24, 330

local function makeSettings()
  settings = CreateFrame("Frame", "GuildBoardTrackerSettings", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  settings:SetSize(250, 40 + #LABELS * 20); settings:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0); settings:SetFrameStrata("DIALOG")
  if settings.SetBackdrop then
    settings:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    settings:SetBackdropColor(0.05, 0.04, 0.03, 0.95); settings:SetBackdropBorderColor(0.9, 0.72, 0.4, 0.9)
  end
  local t = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 12, -10); t:SetText("What to track")
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
      cb:SetScript("OnClick", function(self) db().opts[l[1]] = self:GetChecked() and true or false; ns.trackerRefresh() end)
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
  for i, name in ipairs({ "personal", "party" }) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(76, 18); b:SetPoint("TOPLEFT", 8 + (i - 1) * 80, -6); b:SetText(name == "personal" and "Personal" or "Party")
    b:SetScript("OnClick", function() db().tab = name; if name == "party" then ns.partyRefresh(true) end; ns.trackerRefresh() end)
    tabs[name] = b
  end
  local gear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); gear:SetSize(22, 18); gear:SetPoint("TOPRIGHT", -30, -6); gear:SetText("*")
  gear:SetScript("OnClick", function() if not settings then makeSettings() end; settings:SetShown(not settings:IsShown()) end)
  gear:SetScript("OnEnter", function(b) GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:SetText("What to track"); GameTooltip:Show() end)
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
    r.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT", 12, y - 2); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    rows[i] = r
  end
end

local function render()
  if not frame then return end
  local c = db()
  local tab = c.tab or "personal"
  local out = {}
  local function add(t, header, shareId) out[#out + 1] = { t = t, h = header, share = shareId } end
  local ok, err
  if tab == "party" then ok, err = pcall(party, add) else ok, err = pcall(personal, add) end
  if not ok then add(RED .. "Tracker error: " .. tostring(err) .. "|r"); if ns.logError then pcall(ns.logError, "tracker", tostring(err)) end end
  if #out == 0 then add(GREEN .. "All clear.|r" .. GRAY .. (tab == "personal" and " Nothing to fix or turn in." or "") .. "|r") end
  for name, b in pairs(tabs) do if name == tab then b:LockHighlight() else b:UnlockHighlight() end end
  if #out > MAXROWS then out[MAXROWS] = { t = GRAY .. "+" .. (#out - MAXROWS + 1) .. " more|r" } end
  local n = math.min(#out, MAXROWS)
  for i, r in ipairs(rows) do
    local o = out[i]
    if o and i <= n then
      r.text:SetWidth(WIDTH - (o.share and 96 or 24))
      r.text:SetText(o.t or "")
      if o.share then
        r.btn:SetScript("OnClick", function() ns.party.share(o.share); C_Timer.After(1, function() ns.partyRefresh(true) end) end)
        r.btn:Show()
      else r.btn:Hide() end
    else r.text:SetText(""); r.btn:Hide() end
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
  "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do pcall(ev.RegisterEvent, ev, e) end
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
  else
    ns.trackerRefresh()
  end
end)
