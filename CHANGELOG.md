# Changelog

## Guild Board

### Unreleased
- Party tab: each quest has a Track button that adds it to your objective tracker, same as shift-clicking it in the quest log. Click again to Untrack.
- The minimap button's tooltip shows your version and says if you're out of date.
- Guildie ding popups only list what opened at their newest level, so a two-level jump stays one short line.

### 1.6.0 (2026-11-21)
- **Dungeon quests for the whole group:** the Dungeon tab now lists every quest anyone in your party has for that dungeon, who has it and who already finished it. Share it with one click, or Ask the person who has it. Synced silently between Guild Board users.
- **Ding popups (Blexas):** when you or a guildie levels up, the popup now names the iconic trainer spells and class quests that just opened up for that class, checked against WoW Forever levels.
- **Soul Shard button (John):** warlocks get a small draggable box with a Delete 1 shard button. Not a warlock? `/gb shards` turns it on to test.
- **Sell junk** now protects your swap gear and has a Keep list for anything you never want sold (medi). Selling BoE gear is an opt-in checkbox.
- **Auto-roll:** off by default. Turn it on from the minimap menu to Greed on gear and Pass on the rest.
- **Abandon gray quests:** one button in the quest log drops every quest that is gray to you.
- **Smart Send needs:** the mail button now reads "Give <name> <item>" and fills in the full name.
- **Minimap left-click opens Party & Upkeep.** The To-Do List is out for now and will come back in a later update.
- The guild window is now "Guild quests & flights". The Character Card is Shift+click only.
- Fixed: Party & Upkeep threw an error inside dungeons.

### 1.5.1 (2026-11-15)
Same-day cleanup from the first hour of 1.5.0.
- **Renamed for clarity:** Game Plan is now **To-Do List** and Tracker is now **Party & Upkeep**. Same windows, same buttons, clearer names. `/todo` opens the list; `/plan` still works.
- **Skip is now a button.** The checkbox on Party quests looked like "track this". It is now a Skip button, and the "skipped" line at the bottom opens the list so you can bring any one of them back.
- Skips clear themselves when you turn the quest in or drop it.
- The + Plan button is now **+ To-Do**, and shows **On list** once added.
- The Party & Upkeep window is a little wider so quest names and zones are not cut off.
- The empty To-Do List now tells you exactly where to click to add something.

### 1.5.0 (2026-11-15)
- **Game Plan:** left-click the minimap button for your own checklist with an arrow to the next stop. Add things from the Tracker with + Plan, reorder with the up and down buttons, tick or remove steps. Quests check themselves off when turned in. Quest locations use Questie when it is installed. `/plan paste` takes a pasted list of steps; start a line with `[both]` to share it with your party.
- **Tracker:** one window for upkeep and group play (right-click menu or `/gb track`), with Personal, Party, Share and Dungeon tabs.
- **Party tab:** quests your group has in common, 5 at a time with More for up to 20, and a box on each quest to skip it.
- **Share tab:** Share any quest a party member can take. Ask for a quest they have and their Guild Board shares it for them.
- **Dungeon tab:** opens by itself when you zone into a dungeon. Who needs to repair or clear bags, where everyone is (area name, in range or not), quests for that dungeon and who has them, bosses down, one-click run report.
- **Minimap button:** left-click is now Game Plan. Dungeons moved into the right-click menu, which also has Tracker, Sync guild, Guild window and Character Card.
- **Sync guild** in the menu asks everyone online to resend their info, same as `/gb sync`.
- Nothing new posts to chat or Discord. Party features use the silent addon channel and only see people who run Guild Board.
- Known limits: the game gives addons no position inside a dungeon, so there are no party dots on a map, only area names and range. The arrow needs Questie for quest locations.

### 1.4.0 (2026-11-15)
- Fixed: guildies with a two-part name showed up twice in needs, and "Send needs" could address a mail to yourself. Old duplicate entries are merged on login.
- Fixed: the "Send needs" button was hidden behind the mail window; it now sits just outside its top right corner.
- Fixed: officers with a two-part name could not use the kill switch.
- Fixed: bug reports showed "(nil)" for the game build.
- The minimap button now sits outside the minimap's edge instead of inside it. Drag it around the ring as before.
- New Character Card: Shift+click the minimap button (or /gb card, /cp) to copy your character summary. It replaces the separate Claude Paste addon; you can delete the old ClaudePaste folder.
- Out of date? The addon now nags you on screen with a raid warning at login and every 45 minutes until you update.
- `/gb versions` shows which guildies are on which version (green = newest, orange = needs to update).

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

## Claude Paste (retired in Guild Board 1.4.0, now built in)

### 1.0 (2026-11-14)
- First version: `/cp` opens a window with character, stats, professions, gear, talents, quests and bags, ready to copy.

## Fish Focus

### 1.0.1 (2026-11-15)
- Fixed: a /reload, logout or disconnect while fishing could leave your music, ambience and voices muted. Your normal sound now always comes back.

### 1.0 (2026-11-14)
- First version: sound boost and cast bar while fishing, restored when you stop. `/fishfocus` toggles it.

## Known gaps
- The `/gb run` report has not been confirmed in a real dungeon run yet.
