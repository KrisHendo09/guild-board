# Guild Board and friends: WoW Forever addons

Small addons for World of Warcraft: Forever. Each folder is one addon.

| Addon | What it does | Command |
|---|---|---|
| **Guild Board** | Guildmates who run it share level, class, spec, item level, zone, professions and a short note with each other in game. Also builds a damage, healing and damage-taken report after a dungeon or raid. | `/gb` |
| **Claude Paste** | One click gives you a copy-and-paste summary of your character: gear, talents, quests, bags, professions. | `/cp` |
| **Fish Focus** | While you fish it turns the game sound up, mutes music, and shows a cast bar, so the bobber splash is easy to catch. | `/fishfocus` |

## Install

1. Open the [Releases](../../releases) page and download the zip for the addon you want.
2. Right-click the zip and choose Extract All.
3. Move the addon folder into `World of Warcraft\_forever_\Interface\AddOns`.
   It should look like `AddOns\GuildBoard\GuildBoard.toc`, not a folder inside a folder.
4. Restart WoW. On the character select screen click AddOns and make sure it is checked.

To update, download the new zip and replace the old folder.

## Guild Board commands

- `/gb` shows the roster and a "who can make what" list. Ctrl+C copies it for Discord.
- `/gb note <text>` sets your note, for example `/gb note need Medium Leather`.
- `/gb spec <text>` sets your spec or role if the game does not report it.
- `/gb run` shows a report for the whole run. `/gb run last` covers the last fight.
- `/gb sync` asks everyone online to resend.

## What is shared

Guild Board only talks over the game's guild addon channel, so only your guild sees it.
It shares level, class, spec, average item level, zone, professions and your note.
It never shares gold, bags or individual gear. None of these addons contact the internet.

## Changes

See [CHANGELOG.md](CHANGELOG.md).
