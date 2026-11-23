-- Guild Board: "What's in Guild Board" popup.
--   Shows at login and after /reload: every feature with a one-line plain-English summary. Click one for the details.
--   Tick "Don't show again until the next version" and it stays away until Guild Board updates.
--   Open it any time: /gb help, or right-click the minimap button > What's in Guild Board.

local _, ns = ...
local GOLD, GRAY, GREEN, WHITE = "|cffffd100", "|cff9d9d9d", "|cff33ff99", "|cffffffff"

-- new = this feature arrived (or changed a lot) in that version; it gets a NEW tag while you're on that version
local FEATURES = {
  { "Item tooltips", "See who in the guild needs an item, can make it, or would use it.",
    "Hover any item. Guild Board adds lines to the tooltip:\n\n" ..
    "- Guild needs: who asked for it and how many.\n- Crafters: who in the guild can make it.\n- Upgrade for: guildies who would wear it.\n\n" ..
    "Crafters show up after that person opens their profession window once." },
  { "I need this (Alt+click)", "Alt+click any item to tell the guild you need it.",
    "Alt+click an item in your bags, a chat link, the auction house or a recipe. A box asks how many.\n\n" ..
    "Guildies see it on that item's tooltip. Your need counts down by itself as the items land in your bags, and clears at zero." },
  { "Send needs (mailbox)", "At a mailbox, one button fills in a mail to whoever needs what you carry.",
    "Open a mailbox. If you carry something a guildie asked for, a button shows \"Give <name> <item>\".\n\n" ..
    "Click it and the mail is filled in for you. Nothing goes out until you click Send yourself.", "1.6" },
  { "Party & Upkeep", "Left-click the minimap button. Your to-fix list and your group's quests.",
    "Left-click the Guild Board minimap button to open it. Four tabs:\n\n" ..
    "- Personal: repairs, empty gear slots, full bags, trainer visits, quests to turn in.\n" ..
    "- Party: quests your group has in common.\n- Share: quests you can share or ask for.\n- Dungeon: your dungeon run.\n\n" ..
    "The * button picks what each tab shows, and has Fade and Hide in combat.", "1.6" },
  { "Party quests: Skip and Track", "Quests your group shares, in order. Skip the ones you don't want, Track the rest.",
    "The Party tab lists quests everyone in your group has, closest first.\n\n" ..
    "- Skip takes one off the list. The \"skipped\" line at the bottom brings it back.\n" ..
    "- Track puts it in your quest tracker, same as shift-clicking it in your quest log. Click again to Untrack.\n\n" ..
    "Only party members running Guild Board are counted.", "1.6" },
  { "Share and Ask", "Share a quest with someone who can take it, or ask someone to share theirs.",
    "The Share tab shows quests you have that a party member could take: click Share.\n\n" ..
    "It also shows quests they have that you could take: click Ask and their Guild Board shares it for them. Nothing goes to chat." },
  { "Dungeon tab", "Zone into a dungeon: who needs to repair, where everyone is, and the dungeon's quests.",
    "Opens by itself when you zone into a dungeon.\n\n" ..
    "- Who needs to repair or clear bags before the first pull.\n- Where everyone is (area name, in range or not).\n" ..
    "- Every quest anyone in the group has for that dungeon, who has it and who's done, with Share or Ask buttons.\n- Bosses down and a one-click run report.", "1.6" },
  { "Sell junk gear", "At a vendor, one button sells soulbound gear that isn't an upgrade for you.",
    "Open a vendor. Junk gear gets a red border and a \"Sell junk gear\" button shows up.\n\n" ..
    "It leaves alone: Bind on Equip, epics, gear in an equipment set, swap gear for your tank or healer role, and anything you marked Keep (right-click the button).\n\n" ..
    "It sells 12 at most per click, so a mistake is still in Buyback.", "1.6" },
  { "Auto-roll", "Off until you turn it on. Greeds gear you can't use, passes the rest.",
    "Turn it on from the minimap right-click menu (per character).\n\n" ..
    "- Bind on Equip and quest items: left for you to roll.\n- Upgrades you could Need: left for you.\n- Other gear: Greed.\n- Everything else: Pass.\n\n" ..
    "Each auto roll prints one line in chat.", "1.6" },
  { "Abandon gray quests", "A button in your quest log drops every quest that's gray for your level.",
    "Open your quest log and click \"Abandon gray quests\". Hover it first to see the list.\n\n" ..
    "It asks once before doing anything, and never drops a quest that's already complete.", "1.6" },
  { "Ding popups", "When you or a guildie levels, it shows the new spells and class quests that opened up.",
    "Level up and a popup names the key spells now waiting at your trainer and any class quest that just opened.\n\n" ..
    "When a guildie dings, their popup shows the same for their class. Levels are WoW Forever's.", "1.6" },
  { "Soul Shard button", "Warlocks: a small box that deletes one Soul Shard per click.",
    "Shows for warlocks carrying shards. Click \"Delete 1 shard\" to destroy one (the game allows one per click). Not in combat.\n\n" ..
    "Drag the box to move it. The X hides it until you log in again. Not a warlock? /gb shards turns it on to try it.", "1.6" },
  { "Guild quests & flights", "Right-click menu: everyone's level, zone, notes and professions in one list.",
    "Right-click the minimap button > Guild quests & flights (or type /gb).\n\n" ..
    "Set your own note with /gb note and your role with /gb spec. Ctrl+C copies the list for Discord." },
  { "Dungeons everyone wants", "Right-click menu: pick dungeons you want to run and see who wants the same.",
    "Right-click the minimap button > Dungeons. Tick the ones you want and guildies see it, so it's easy to find a group." },
  { "Character Card", "Shift+click the minimap button to copy a summary of your character.",
    "Handy for pasting your gear and stats into Discord or a chat with someone helping you." },
  { "Versions and bugs", "Hover the minimap button to see if you're up to date. /gb bug if something breaks.",
    "- The minimap tooltip shows your version and says OUT OF DATE when a newer one is out.\n" ..
    "- /gb versions shows who is on which version.\n- /gb bug shows any errors so you can report them in Discord.\n\n" ..
    "If a feature hits a bug it pauses itself until /reload so it can't spam you.", "1.6" },
}

local function db() GuildBoardDB = GuildBoardDB or {}; return GuildBoardDB end
local function version() return (ns.version and ns.version()) or "?" end
local function mm(v) return tostring(v):match("^(%d+%.%d+)") end

local frame, rows, sel = nil, {}, nil
local ROWH, LISTW, DETW = 34, 330, 290

local function pickRow(i)
  sel = i
  local f = FEATURES[i]
  for j, r in ipairs(rows) do if j == i then r.hl:Show() else r.hl:Hide() end end
  frame.dTitle:SetText(f[1])
  frame.dBody:SetText(f[3])
end

local function build()
  frame = CreateFrame("Frame", "GuildBoardHelp", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(LISTW + DETW + 30, 84 + #FEATURES * ROWH); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.06, 0.05, 0.04, 0.96); frame:SetBackdropBorderColor(0.9, 0.72, 0.4, 0.95)
  end
  tinsert(UISpecialFrames, "GuildBoardHelp")      -- Esc closes it
  local t = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); t:SetPoint("TOPLEFT", 14, -12)
  t:SetText("What's in Guild Board " .. GRAY .. version() .. "|r")
  local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
  sub:SetText("Click any feature to read more.")
  local x = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", 0, 0)

  local cur = mm(version())
  for i, f in ipairs(FEATURES) do
    local r = CreateFrame("Button", nil, frame)
    r:SetSize(LISTW, ROWH - 2); r:SetPoint("TOPLEFT", 10, -48 - (i - 1) * ROWH)
    r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetColorTexture(0.9, 0.72, 0.4, 0.18); r.hl:Hide()
    local hov = r:CreateTexture(nil, "HIGHLIGHT"); hov:SetAllPoints(); hov:SetColorTexture(1, 1, 1, 0.06)
    local name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); name:SetPoint("TOPLEFT", 6, -2)
    name:SetText(f[1] .. ((f[4] and f[4] == cur) and (GREEN .. "  NEW|r") or ""))
    local line = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    line:SetWidth(LISTW - 12); line:SetJustifyH("LEFT"); line:SetWordWrap(false); line:SetText(f[2])
    r:SetScript("OnClick", function() pickRow(i) end)
    r:SetScript("OnEnter", function(b)
      GameTooltip:SetOwner(b, "ANCHOR_LEFT"); GameTooltip:SetText(f[1]); GameTooltip:AddLine(f[2], 1, 1, 1, true)
      GameTooltip:AddLine("Click for more", 0.6, 0.6, 0.6); GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
  end

  -- detail pane on the right
  local pane = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  pane:SetPoint("TOPLEFT", 10 + LISTW + 8, -48); pane:SetPoint("BOTTOMRIGHT", -10, 40)
  if pane.SetBackdrop then
    pane:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    pane:SetBackdropColor(0, 0, 0, 0.45); pane:SetBackdropBorderColor(0.5, 0.42, 0.3, 0.8)
  end
  frame.dTitle = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); frame.dTitle:SetPoint("TOPLEFT", 10, -10)
  frame.dTitle:SetWidth(DETW - 20); frame.dTitle:SetJustifyH("LEFT")
  frame.dBody = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); frame.dBody:SetPoint("TOPLEFT", frame.dTitle, "BOTTOMLEFT", 0, -8)
  frame.dBody:SetWidth(DETW - 20); frame.dBody:SetJustifyH("LEFT"); frame.dBody:SetJustifyV("TOP"); frame.dBody:SetSpacing(2)

  -- don't show again until the next version
  local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate"); cb:SetSize(22, 22); cb:SetPoint("BOTTOMLEFT", 10, 10)
  local lab = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); lab:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  lab:SetText("Don't show this again until the next version")
  cb:SetScript("OnClick", function(self) db().helpHideFor = self:GetChecked() and version() or nil end)
  frame.cb = cb
  local ok = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); ok:SetSize(90, 22); ok:SetPoint("BOTTOMRIGHT", -12, 10)
  ok:SetText("Got it"); ok:SetScript("OnClick", function() frame:Hide() end)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("RIGHT", ok, "LEFT", -10, 0)
  hint:SetText("/gb help opens this any time")
  frame:Hide()
end

ns.toggleHelp = function()
  if not frame then build() end
  if frame:IsShown() then frame:Hide(); return end
  frame.cb:SetChecked(db().helpHideFor == version())
  if not sel then
    sel = 1
    local cur = mm(version())        -- open on the first new feature, if there is one
    for i, f in ipairs(FEATURES) do if f[4] and f[4] == cur then sel = i; break end end
  end
  pickRow(sel)
  frame:Show()
end

-- show at login and after /reload, unless ticked for this version
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  C_Timer.After(6, function()
    ns.safe("help", function()
      if ns.featureOff and ns.featureOff("help") then return end
      if db().helpHideFor == version() then return end
      if InCombatLockdown and InCombatLockdown() then return end
      if not (frame and frame:IsShown()) then ns.toggleHelp() end
    end)
  end)
end)
