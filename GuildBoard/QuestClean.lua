-- Guild Board: "Abandon gray quests" button on the quest log.
--   Gray = too low to give real XP (the game's own gray color for your level).
--   Never abandons a quest that's already complete (turn those in for the reward), and asks once before it does anything.
--   Hover the button to see the list. Shift+drag to move it.

local _, ns = ...
local GREEN, GRAY = "|cff33ff99", "|cff9d9d9d"

local function isGray(qlevel)
  if not qlevel or qlevel <= 0 then return false end
  local me = UnitLevel("player") or 1
  if GetQuestDifficultyColor and QuestDifficultyColors and QuestDifficultyColors.trivial then
    return GetQuestDifficultyColor(qlevel) == QuestDifficultyColors.trivial
  end
  local range = (UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player")) or (GetQuestGreenRange and GetQuestGreenRange()) or 8
  return me - qlevel > range
end

local function grays()
  local out = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, tonumber((C_QuestLog.GetNumQuestLogEntries())) or 0 do
      local q = C_QuestLog.GetInfo(i)
      if q and not q.isHeader and q.questID then
        local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID)
        if not done and (q.isTrivial or isGray(q.level)) then out[#out + 1] = { id = q.questID, i = i, title = q.title or "?", level = q.level } end
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, GetNumQuestLogEntries() do
      local title, qlevel, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
      if title and not isHeader and not (isComplete == 1 or isComplete == true) and isGray(qlevel) then
        out[#out + 1] = { id = id, i = i, title = title, level = qlevel }
      end
    end
  end
  return out
end

local function abandonOne(q)
  if C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
    C_QuestLog.SetSelectedQuest(q.id); C_QuestLog.SetAbandonQuest(); C_QuestLog.AbandonQuest()
  elseif SelectQuestLogEntry and SetAbandonQuest and AbandonQuest then
    -- old API works by log index, which shifts after each abandon, so find it fresh by title
    for i = 1, GetNumQuestLogEntries() do
      local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
      if not isHeader and (id == q.id or title == q.title) then SelectQuestLogEntry(i); SetAbandonQuest(); AbandonQuest(); break end
    end
  end
end

local btn
local function refresh()
  if not btn then return end
  local n = #grays()
  btn:SetText(n > 0 and ("Abandon gray (" .. n .. ")") or "No gray quests")
  btn:SetEnabled(n > 0)
end

local function run()
  local list = grays()
  for k, q in ipairs(list) do
    C_Timer.After(0.3 * (k - 1), function() ns.safe("questclean", abandonOne, q) end)
  end
  print(GREEN .. "Guild Board|r abandoned " .. #list .. " gray quest" .. (#list == 1 and "" or "s") .. "." .. GRAY .. " Completed quests were kept.|r")
  C_Timer.After(0.3 * #list + 0.5, function() ns.safe("questclean", refresh) end)
end

StaticPopupDialogs["GUILDBOARD_ABANDON_GRAY"] = {
  text = "Abandon %s gray quest(s)?\n\n%s",
  button1 = YES or "Yes", button2 = NO or "No",
  OnAccept = function() ns.safe("questclean", run) end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function click()
  local list = grays()
  if #list == 0 then return end
  local names = {}
  for k, q in ipairs(list) do
    if k > 10 then names[#names + 1] = "+" .. (#list - 10) .. " more"; break end
    names[#names + 1] = "[" .. (q.level or "?") .. "] " .. q.title
  end
  StaticPopup_Show("GUILDBOARD_ABANDON_GRAY", #list, table.concat(names, "\n"))
end

local function build()
  local host = QuestLogFrame or (QuestMapFrame and WorldMapFrame)
  if btn or not host then return end
  btn = CreateFrame("Button", "GuildBoardAbandonGray", host, "UIPanelButtonTemplate")
  btn:SetSize(150, 22); btn:SetFrameStrata("HIGH"); btn:SetClampedToScreen(true)
  if ns.db and not ns.db().grayBtnPos2 then ns.db().grayBtnPos = nil; ns.db().grayBtnPos2 = true end   -- drop the old spot that sat on the search box
  local p = ns.db and ns.db().grayBtnPos
  if p then btn:SetPoint(p[1], host, p[1], p[2], p[3])
  elseif QuestLogFrameAbandonButton and QuestLogFrameAbandonButton:IsShown() then btn:SetPoint("BOTTOMLEFT", QuestLogFrameAbandonButton, "TOPLEFT", 0, 4)
  else btn:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 12, -2) end   -- hangs just under the quest log so it never covers the search box
  btn:SetMovable(true); btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
  btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, _, _, x, y = self:GetPoint(); if ns.db then ns.db().grayBtnPos = { a, x, y } end
  end)
  btn:SetScript("OnClick", function() ns.safe("questclean", click) end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Abandon gray quests", 1, 0.82, 0)
    local list = grays()
    for k, q in ipairs(list) do
      if k > 15 then GameTooltip:AddLine("+" .. (#list - 15) .. " more", 0.6, 0.6, 0.6); break end
      GameTooltip:AddDoubleLine(q.title, "level " .. (q.level or "?"), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Completed quests are never touched. Asks before abandoning.", 0.5, 0.8, 1, true)
    GameTooltip:AddLine("Shift+drag to move.", 0.5, 0.8, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  host:HookScript("OnShow", function() ns.safe("questclean", refresh) end)
  refresh()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then ns.safe("questclean", build)
  elseif btn and btn:IsVisible() then ns.safe("questclean", refresh) end
end)
