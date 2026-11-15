# Changelog

## Guild Board

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
