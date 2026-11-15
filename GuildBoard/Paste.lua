-- Character Card (was the separate Claude Paste addon): Shift+click the minimap button, /gb card or /cp opens a text summary
-- of your character (gear, bags, quests, talents, professions) to paste to Kris or Claude.
local _, ns = ...
-- Press Ctrl+C (it is already selected), then paste it in Discord.

local tip = CreateFrame("GameTooltip", "GuildBoardPasteTip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")

local SLOTS = { "Head","Neck","Shoulder","Back","Chest","Wrist","Hands","Waist","Legs","Feet",
  "Finger0","Finger1","Trinket0","Trinket1","MainHand","SecondaryHand","Ranged" }

local function try(lines, title, fn)
  local ok, err = pcall(fn)
  if not ok then lines[#lines + 1] = "[" .. title .. " failed: " .. tostring(err) .. "]" end
end

local function gearStats(slotId)
  tip:ClearLines(); tip:SetOwner(WorldFrame, "ANCHOR_NONE")
  if not pcall(tip.SetInventoryItem, tip, "player", slotId) then return "" end
  local out = {}
  for i = 2, tip:NumLines() do
    local l = _G["GuildBoardPasteTipTextLeft" .. i]
    local t = l and l:GetText()
    if t and (t:match("^%+%d") or t:match("Damage") or t:match("Armor$") or t:match("^Equip:")) then
      out[#out + 1] = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
  end
  return table.concat(out, ", ")
end

local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function build()
  local L = {}
  local function add(s) L[#L + 1] = s end

  try(L, "player", function()
    local m = GetMoney() or 0
    add(string.format("== %s, level %d %s %s ==", UnitName("player") or "?", UnitLevel("player") or 0, UnitRace("player") or "", UnitClass("player") or ""))
    add(string.format("XP %d/%d, rested %d, gold %dg %ds %dc", UnitXP("player") or 0, UnitXPMax("player") or 0, GetXPExhaustion() or 0,
      math.floor(m / 10000), math.floor((m % 10000) / 100), m % 100))
    add(string.format("Where: %s, %s", GetSubZoneText() or "", GetRealZoneText() or ""))
    local names = { "Str", "Agi", "Sta", "Int", "Spi" }
    local st = {}
    for i = 1, 5 do local _, eff = UnitStat("player", i); st[#st + 1] = names[i] .. " " .. tostring(eff) end
    local base, pos, neg = UnitAttackPower("player")
    local _, armor = UnitArmor("player")
    st[#st + 1] = "AP " .. ((base or 0) + (pos or 0) + (neg or 0))
    st[#st + 1] = "Armor " .. tostring(armor)
    if GetCritChance then st[#st + 1] = string.format("Crit %.1f%%", GetCritChance()) end
    add("Stats: " .. table.concat(st, ", ") .. string.format(", HP %d, Mana/Power %d", UnitHealthMax("player") or 0, UnitPowerMax("player") or 0))
  end)

  try(L, "professions", function()
    local out = {}
    if GetProfessions and GetProfessionInfo then
      local list = { GetProfessions() }
      for i = 1, 6 do
        if list[i] then
          local name, _, rank, max = GetProfessionInfo(list[i])
          out[#out + 1] = string.format("%s %d/%d", name or "?", rank or 0, max or 0)
        end
      end
    elseif GetNumSkillLines then
      for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
        if not isHeader and max and max > 1 then out[#out + 1] = string.format("%s %d/%d", name or "?", rank or 0, max) end
      end
    end
    add("Professions: " .. (#out > 0 and table.concat(out, ", ") or "none found"))
  end)

  add(""); add("-- GEAR --")
  try(L, "gear", function()
    for _, s in ipairs(SLOTS) do
      local id = GetInventorySlotInfo(s .. "Slot")
      local link = GetInventoryItemLink("player", id)
      if link then
        local name = link:match("%[(.-)%]") or link
        local cur, max = GetInventoryItemDurability(id)
        local stats = gearStats(id)
        add(s .. ": " .. name .. (stats ~= "" and (" (" .. stats .. ")") or "") .. ((cur and max and max > 0 and cur / max < 0.35) and " LOW DURABILITY" or ""))
      else
        add(s .. ": empty")
      end
    end
  end)

  add(""); add("-- TALENTS --")
  try(L, "talents", function()
    local n = 0
    if C_ClassTalents and C_Traits and C_ClassTalents.GetActiveConfigID then
      local configID = C_ClassTalents.GetActiveConfigID()
      local cfg = configID and C_Traits.GetConfigInfo(configID)
      if cfg and cfg.treeIDs then
        for _, treeID in ipairs(cfg.treeIDs) do
          local row = {}
          for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local nd = C_Traits.GetNodeInfo(configID, nodeID)
            if nd and (nd.currentRank or 0) > 0 then
              local entryID = (nd.activeEntry and nd.activeEntry.entryID) or (nd.entryIDs and nd.entryIDs[1])
              local name
              if entryID then
                local e = C_Traits.GetEntryInfo(configID, entryID)
                local d = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
                if d then name = d.overrideName or spellName(d.spellID) end
              end
              row[#row + 1] = string.format("%s %d/%d", tostring(name or nodeID), nd.currentRank or 0, nd.maxRanks or 0)
              n = n + 1
            end
          end
          if #row > 0 then add(table.concat(row, ", ")) end
          if C_Traits.GetTreeCurrencyInfo then
            local cur = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
            if cur and cur[1] then add("Unspent points: " .. tostring(cur[1].quantity)) end
          end
        end
      end
    end
    if n == 0 and GetNumTalentTabs and GetNumTalentTabs() > 0 then
      for t = 1, GetNumTalentTabs() do
        local row = {}
        for i = 1, (GetNumTalents(t) or 0) do
          local name, _, _, _, rank, maxRank = GetTalentInfo(t, i)
          if type(name) == "string" and (rank or 0) > 0 then row[#row + 1] = string.format("%s %d/%d", name, rank, maxRank or 0); n = n + 1 end
        end
        if #row > 0 then add(table.concat(row, ", ")) end
      end
    end
    if n == 0 then add("none spent (or could not read)") end
  end)

  add(""); add("-- QUESTS --")
  try(L, "quests", function()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
      local zone = ""
      for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
          if info.isHeader then zone = info.title or ""
          else
            local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
            local parts = {}
            local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(info.questID)
            if objs and not done then for _, o in ipairs(objs) do if not o.finished then parts[#parts + 1] = tostring(o.text) end end end
            add(string.format("[%s] %s (%s)%s", tostring(info.level or "?"), info.title or "?", zone,
              done and " DONE, turn in" or (#parts > 0 and (": " .. table.concat(parts, "; ")) or "")))
          end
        end
      end
    elseif GetNumQuestLogEntries then
      local zone = ""
      for i = 1, GetNumQuestLogEntries() do
        local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if isHeader then zone = title or ""
        elseif title then add(string.format("[%s] %s (%s)%s", tostring(level or "?"), title, zone, (isComplete == 1 or isComplete == true) and " DONE, turn in" or "")) end
      end
    end
  end)

  add(""); add("-- BAGS --")
  try(L, "bags", function()
    local counts, order, free, total = {}, {}, 0, 0
    for b = 0, 5 do
      local n = (C_Container and C_Container.GetContainerNumSlots(b)) or (GetContainerNumSlots and GetContainerNumSlots(b)) or 0
      for s = 1, n do
        total = total + 1
        local link, count
        if C_Container then
          local info = C_Container.GetContainerItemInfo(b, s)
          if info then link, count = info.hyperlink, info.stackCount end
        else
          local _, c, _, _, _, _, l = GetContainerItemInfo(b, s); link, count = l, c
        end
        if link then
          local name = link:match("%[(.-)%]") or link
          if not counts[name] then counts[name] = 0; order[#order + 1] = name end
          counts[name] = counts[name] + (count or 1)
        else
          free = free + 1
        end
      end
    end
    add(string.format("%d free of %d slots", free, total))
    local row = {}
    for _, name in ipairs(order) do row[#row + 1] = name .. (counts[name] > 1 and (" x" .. counts[name]) or "") end
    add(table.concat(row, ", "))
  end)

  return table.concat(L, "\n")
end

local frame
local function show()
  if not frame then
    frame = CreateFrame("Frame", "GuildBoardPasteFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(560, 420); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
    if frame.SetBackdrop then
      frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      frame:SetBackdropColor(0, 0, 0, 0.92)
    end
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10); title:SetText("Character Card: press Ctrl+C, then paste in Discord. Esc closes.")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    local scroll = CreateFrame("ScrollFrame", "GuildBoardPasteScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32); scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local edit = CreateFrame("EditBox", "GuildBoardPasteEdit", scroll)
    edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal); edit:SetWidth(510); edit:SetAutoFocus(false)
    if edit.SetMaxLetters then edit:SetMaxLetters(0) end
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)
    frame.edit = edit
  end
  local text = build()
  frame.edit:SetText(text)
  frame:Show()
  frame.edit:SetFocus(); frame.edit:HighlightText()
  print("|cff33ff99Character Card|r: " .. #text .. " characters ready. Ctrl+C to copy.")
end

ns.paste = function() local ok, err = pcall(show); if not ok then print("Character Card error: " .. tostring(err)) end end
-- keep /cp working for anyone used to it; if the old standalone Claude Paste addon is still installed, it keeps /cp and this one stays out of the way
if not SlashCmdList["CLAUDEPASTE"] then
  SLASH_CLAUDEPASTE1 = "/cp"
  SLASH_CLAUDEPASTE2 = "/claudepaste"
  SlashCmdList["CLAUDEPASTE"] = ns.paste
end
