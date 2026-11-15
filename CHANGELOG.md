# Changelog

## Unreleased
- The minimap button now sits outside the minimap's edge instead of inside it. Drag it around the ring as before.
- Fixed: guildies with a two-part name (like Jay Spaceman) showed up twice in needs, and "Send needs" could address a mail to yourself. Old duplicate entries are merged on login. (reported by jspaceman)
- Fixed: the "Send needs" button was hidden behind the mail window; it now sits just outside its top right corner. (reported by jspaceman)
- Fixed: officers with a two-part name could not use the kill switch.
- Fixed: bug reports showed "(nil)" for the game build.
- The separate Claude Paste addon is retired. Its feature lives in Guild Board now; you can delete the old ClaudePaste folder.
- Claude Paste is built in: Shift+click the minimap button (or /gb paste, /cp) to copy your character summary.
- Out of date? The addon now nags you on screen with a raid warning at login and every 45 minutes until you update.
- `/gb versions` shows which guildies are on which version (green = newest, orange = needs to update).

## Guild Board

### 1.3.1 (2026-11-15)
- Officer kill switch now records who flipped a feature and keeps a history (who, what, when), shown in `/gb bug`. Everyone also sees a chat line when a feature is switched back on.
- First version published to CurseForge.

### 1.3.0 (2026-11-15)
Big one, built for a guild of friends. Everything stays in game.
- **Needs:** Alt+click any item to say you need it. Friends see it in blue on the tooltip; it counts down as items arrive.
- **Mats for leveling:** yellow tooltip line when a friend's profession skill is in the range where that material levels it (WoW Forever leveling routes).
- **Upgrades:** green tooltip line when a non-BoP item is an item level upgrade for a friend who can use it.
- **Crafters:** gold tooltip line showing who knows the recipe.
- **Mailbox button:** Send needs fills in a mail to whoever needs what you carry.
- **Dungeon flags:** new minimap button; tick dungeons you want to run (WoW Forever dungeon list and level ranges). Auto-off after 48h, out-leveling, or leaving after 3+ boss kills.
- **Guild window:** roster from the guild list with alts grouped by guild notes, players offline 7+ days hidden, plus dungeon flags, needs, level race, shared quests, Hall of Shame, hearths and flight paths, party gear check.
- **Social:** level-up popups, death log with chat line, heads-up when friends quest in your zone, party gear check on entering a dungeon.
- **Version check:** tells you once when a guildmate has a newer version.
- **Self-heal:** every feature is error-guarded; a feature that keeps erroring pauses itself until /reload; saved data is checked and repaired on login and old data pruned; unknown messages from newer versions are ignored.
- **Bug reports:** `/gb bug` makes a report to paste. New errors are also shared quietly with the guild so the maintainer can fix them.
- **Officer kill switch:** `/gb disable <feature>` turns a broken feature off for the whole guild until a fix ships. 
- Known limits: Forever closes the combat log to addons, so the death log may show "something" as the killer. Scarlet Monastery and Dire Maul wings share an instance name, so finishing one wing clears all your flags for that dungeon.

### 1.2.1 (2026-11-14)
- Confirmed working between players: three characters from two accounts showed up on each other's board.
- Fixed spec showing the class name (for example "Shaman Shaman"). It is now blank until you set it with `/gb spec`.
- Note: item level is the game's average across all slots, so empty slots pull it down.

### 1.2 (2026-11-14)
- Added `/gb run` and `/gb run last`: damage done, healing done and damage taken per player, read from the game's built-in damage meter.
- Removed DPS from the guild roster and removed the `/gb dps` command. DPS now only appears in a run report someone chooses to post.

### 1.1 (2026-11-14)
- Roster now shares spec and average item level.
- Added `/gb spec` to set spec or role by hand.
- Added an opt-in DPS column (removed again in 1.2).

### 1.0 (2026-11-14)
- First version: level, class, zone, professions and a note shared over the guild addon channel, with relaying for offline members.
- `/gb` roster window with a "who can make what" list.

## Claude Paste

### 1.0 (2026-11-14)
- First version: `/cp` opens a window with character, stats, professions, gear, talents, quests and bags, ready to copy.

## Fish Focus

### 1.0 (2026-11-14)
- First version: sound boost and cast bar while fishing, restored when you stop. `/fishfocus` toggles it.

## Known gaps
- The `/gb run` report has not been confirmed in a real dungeon run yet.
