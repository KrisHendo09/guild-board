FishFocusDB = FishFocusDB or { enabled = true }
local saved, fishing, restoreTimer = nil, false, nil
local CVARS = {
  Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_SFXVolume = "1.0",
  Sound_MasterVolume = "1.0", Sound_MusicVolume = "0", Sound_AmbienceVolume = "0",
  Sound_DialogVolume = "0", Sound_EnableSoundWhenGameIsInBG = "1",
}

local bar = CreateFrame("StatusBar", "FishFocusBar", UIParent)
bar:SetSize(420, 34); bar:SetPoint("CENTER", 0, -180)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.2, 0.6, 1)
local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); txt:SetPoint("CENTER")
txt:SetText("FISHING... listen for the splash")
bar:Hide()

local function isFishing()
  local name, _, _, startMS, endMS = UnitChannelInfo("player")
  if name and name:find("Fishing") then return true, startMS, endMS end
end

local function applySound()
  if saved then return end
  saved = {}
  for k, v in pairs(CVARS) do saved[k] = GetCVar(k); SetCVar(k, v) end
end
local function restoreSound()
  if not saved then return end
  for k, v in pairs(saved) do if v then SetCVar(k, v) end end
  saved = nil
end

bar:SetScript("OnUpdate", function(self)
  if not self.endT then return end
  local now = GetTime()
  local left = self.endT - now
  self:SetValue(math.max(0, now - self.startT))
  local pulse = 0.5 + 0.5 * math.abs(math.sin(now * 3))
  self:SetStatusBarColor(0.2 * pulse, 0.6 * pulse, 1 * pulse)
  if left < 4 then txt:SetText(string.format("Recast soon... %.0fs", math.max(0, left))) end
end)

local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
f:SetScript("OnEvent", function(_, ev)
  if not FishFocusDB.enabled then return end
  if ev == "UNIT_SPELLCAST_CHANNEL_START" then
    local yes, s, e = isFishing()
    if not yes then return end
    fishing = true
    if restoreTimer then restoreTimer:Cancel(); restoreTimer = nil end
    applySound()
    bar.startT, bar.endT = s / 1000, e / 1000
    bar:SetMinMaxValues(0, bar.endT - bar.startT)
    txt:SetText("FISHING... listen for the splash")
    bar:Show()
  elseif ev == "UNIT_SPELLCAST_CHANNEL_STOP" and fishing then
    fishing = false
    bar:Hide()
    restoreTimer = C_Timer.NewTimer(20, function() restoreTimer = nil; if not fishing then restoreSound() end end)
  end
end)

SLASH_FISHFOCUS1 = "/fishfocus"
SlashCmdList.FISHFOCUS = function()
  FishFocusDB.enabled = not FishFocusDB.enabled
  if not FishFocusDB.enabled then restoreSound(); bar:Hide() end
  print("|cff33ccffFish Focus|r " .. (FishFocusDB.enabled and "ON" or "OFF"))
end
