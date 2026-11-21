-- Guild Board: what a ding unlocks (Blexas's feature requests 2 and 3, Nov 20 2026).
--   When you level, a popup lists the iconic trainer spells now waiting at your trainer and any class quest that
--   just opened. When a guildie levels, their ding popup (Social.lua) adds the same for their class.
--   Spell levels are WoW Forever's (checked against method.gg's Forever spell lists, Nov 20 2026); class quest
--   levels from ConquestCapped's Forever class quest table. Rank 1 only, no talents. "(tome)" = learned from a book.

local _, ns = ...
local GREEN, GOLD = "|cff33ff99", "|cffffd100"

local SPELLS = {
  WARRIOR = { { 4, "Charge" }, { 24, "Execute" }, { 28, "Shield Wall" }, { 30, "Intercept" }, { 36, "Whirlwind" }, { 38, "Pummel" }, { 50, "Recklessness" } },
  PALADIN = { { 8, "Hammer of Justice" }, { 10, "Lay on Hands" }, { 10, "Blessing of Protection" }, { 18, "Blessing of Freedom" }, { 20, "Exorcism" },
    { 30, "Divine Intervention" }, { 34, "Divine Shield" }, { 42, "Cleanse" }, { 44, "Hammer of Wrath" }, { 52, "Greater Blessing of Might" },
    { 54, "Greater Blessing of Wisdom" }, { 60, "Greater Blessing of Kings" } },
  HUNTER = { { 14, "Eyes of the Beast" }, { 18, "Multi-Shot" }, { 20, "Aimed Shot" }, { 20, "Aspect of the Cheetah" }, { 20, "Freezing Trap" },
    { 30, "Feign Death" }, { 40, "Aspect of the Pack" }, { 40, "Volley" }, { 60, "Tranquilizing Shot (tome)" } },
  ROGUE = { { 10, "Sap" }, { 10, "Sprint" }, { 12, "Kick" }, { 22, "Vanish" }, { 30, "Kidney Shot" }, { 34, "Blind" } },
  PRIEST = { { 10, "Resurrection" }, { 14, "Psychic Scream" }, { 20, "Fear Ward" }, { 20, "Devouring Plague" }, { 22, "Mind Vision" },
    { 30, "Mind Control" }, { 30, "Divine Spirit" }, { 32, "Shadow Word: Death" }, { 34, "Levitate" }, { 48, "Prayer of Fortitude (tome)" } },
  SHAMAN = { { 12, "Purge" }, { 18, "Tremor Totem" }, { 20, "Ghost Wolf" }, { 20, "Frost Shock" }, { 22, "Water Breathing" }, { 28, "Water Walking" },
    { 30, "Reincarnation" }, { 30, "Astral Recall" }, { 30, "Windfury Weapon" }, { 32, "Windfury Totem" }, { 32, "Chain Lightning" }, { 40, "Chain Heal" } },
  MAGE = { { 8, "Polymorph" }, { 10, "Frost Nova" }, { 12, "Slow Fall" }, { 20, "Blink" }, { 20, "Teleports" }, { 20, "Evocation" },
    { 24, "Counterspell" }, { 40, "Portals" }, { 56, "Arcane Brilliance (tome)" } },
  WARLOCK = { { 8, "Fear" }, { 10, "Create Healthstone" }, { 18, "Create Soulstone" }, { 20, "Ritual of Summoning" }, { 22, "Eye of Kilrogg" },
    { 28, "Banish" }, { 30, "Subjugate Demon" }, { 40, "Howl of Terror" }, { 42, "Death Coil" } },
  DRUID = { { 10, "Teleport: Moonglade" }, { 18, "Hibernate" }, { 20, "Rebirth" }, { 26, "Dash" }, { 30, "Travel Form" }, { 30, "Tranquility" },
    { 36, "Pounce" }, { 40, "Dire Bear Form" }, { 40, "Innervate" }, { 40, "Hurricane" } },
}

local QUESTS = {
  DRUID = { { 10, "Bear Form" }, { 14, "Cure Poison" }, { 16, "Aquatic Form" }, { 20, "Cat Form" } },
  HUNTER = { { 10, "pet taming" }, { 60, "Rhok'delar bow" } },
  PALADIN = { { 12, "Redemption" }, { 20, "class weapon" }, { 40, "Warhorse" }, { 60, "Charger" } },
  PRIEST = { { 10, "first racial spell" }, { 20, "second racial spell" } },
  ROGUE = { { 20, "Poisons" }, { 23, "spy chain (Ruby-Adorned Blade)" } },
  SHAMAN = { { 4, "Earth Totem" }, { 10, "Fire Totem" }, { 20, "Water Totem" }, { 30, "Air Totem + weapon" }, { 60, "Darkreaver" } },
  WARLOCK = { { 10, "Voidwalker" }, { 20, "Succubus" }, { 30, "Felhunter" }, { 40, "Felsteed" }, { 60, "Dreadsteed" } },
  WARRIOR = { { 10, "Defensive Stance" }, { 30, "Berserker Stance + Whirlwind Axe" } },
}

-- class can be the token ("SHAMAN") or a localized name ("Shaman"); levels above `from` up to and including `to`
local function token(class)
  if not class then return end
  local up = tostring(class):upper():gsub("%s", "")
  if SPELLS[up] or QUESTS[up] then return up end
  if LOCALIZED_CLASS_NAMES_MALE then for k, v in pairs(LOCALIZED_CLASS_NAMES_MALE) do if v == class then return k end end end
  if LOCALIZED_CLASS_NAMES_FEMALE then for k, v in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do if v == class then return k end end end
end
local function pick(list, from, to)
  local out = {}
  for _, e in ipairs(list or {}) do if e[1] > from and e[1] <= to then out[#out + 1] = e[2] end end
  return out
end
ns.unlocksFor = function(class, from, to)
  local t = token(class)
  if not t or not from or not to or to <= from then return {}, {} end
  return pick(SPELLS[t], from, to), pick(QUESTS[t], from, to)
end
local function join(list)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
-- one short line for a ding popup; nil when nothing iconic opened
ns.unlockText = function(class, from, to, self)
  local sp, qs = ns.unlocksFor(class, from, to)
  local parts = {}
  if #sp > 0 then parts[#parts + 1] = join(sp) .. (self and " at your trainer" or ((#sp > 1) and " are available" or " is available")) end
  if #qs > 0 then parts[#parts + 1] = (self and "Your " or "") .. join(qs) .. " quest" .. (#qs > 1 and "s are" or " is") .. " up" end
  if #parts == 0 then return end
  return table.concat(parts, ". ") .. "!"
end

-- your own ding
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, _, level)
  ns.safe("dings", function()
    if ns.featureOff and ns.featureOff("dings") then return end
    level = tonumber(level) or UnitLevel("player")
    local _, cls = UnitClass("player")
    local txt = ns.unlockText(cls, level - 1, level, true)
    if not txt then return end
    local msg = "Level " .. level .. "! " .. txt
    if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, msg, { r = 1, g = 0.82, b = 0 }) end
    print(GREEN .. "Guild Board|r " .. GOLD .. msg .. "|r")
  end)
end)
