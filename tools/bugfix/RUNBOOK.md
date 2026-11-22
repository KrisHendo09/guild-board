# Bug fix schedule: runbook

Kris set this up on Nov 20, 2026. A scheduled Claude run follows this file. Feature work is NOT part of it:
features are built and released by hand from the addon dev chat. This run only fixes bugs in code that is
already released, and ships the fix on its own.

## What counts as a bug this run may fix
- A Lua error or a feature that plainly does not do what the changelog says, in the **latest released version**
  (the `## Version:` in `GuildBoard/GuildBoard.toc` on `main`).
- The file and the code that fails must exist on `main`. Kris's own PC runs an unreleased dev build with extra
  files (Junk, Lottery, AutoRoll, WeaponSwap, QuestClean, AuctionBoE and more). Errors from those are the dev
  chat's. Do not fix them here. Put them in the Drive request note (see "Hand off").
- Never add a feature, an option, a new file or a new saved-variable field. Never touch `Tasks.lua` or anything
  under Kris's installed `Interface\AddOns`. The repo is the only place this run writes code.

## Where bugs come from (check all three, skip any you cannot reach)
1. **In game reports** on the Legion: `D:\World of Warcraft\_forever_\WTF\Account\KRISXPC\SavedVariables\GuildBoard.lua`,
   tables `GuildBoardDB.guildErrors` and `GuildBoardDB.errors` (fields: ver, msg, feature, count, who, first, last).
   Read only. It is only as fresh as Kris's last logout or /reload.
2. **GitHub issues** on KrisHendo09/guild-board (open ones).
3. **Discord**: replies in the Guild Board post in #addons-forum, only if a browser on Kris's computer is
   available. Read only. Never post there by hand; announcements go through the Announce workflow.

`tools/bugfix/ledger.json` is the memory between runs: one entry per bug signature (message with line numbers
removed + version), with status `fixed`, `queued`, `needs-kris`, `dev-build` or `cannot-reproduce`, the version
it shipped in and the date. No player names in it (the repo is public). Skip anything already settled there.

## Hotfix or weekly
- **Hotfix, ship in this run:** a Lua error on the latest release seen by any guildie other than Kris alone, or a
  released feature that is broken for everyone.
- **Weekly patch, ship on Tuesday's run:** everything else that is a real bug (wrong text, layout, a minor wrong
  result). Commit the fix to `main` when you make it, release on Tuesday. A hotfix ships whatever is waiting too.
- At most one release per run and one per day. No bugs fixed means no release and no announcement.

## Gates before anything ships (all must pass)
1. You can point at the exact line and say why it fails. A guess is not a fix: mark it `needs-kris`.
2. `pip install lupa luaparser`, then before the change `python3 tools/test/smoke.py --save /tmp/base.json`
   and after it `python3 tools/test/smoke.py --against /tmp/base.json`. It must report no new or fatal errors.
   Where you can, also write a small lupa script that reproduces the reported error on the old code and shows it
   gone on the new code. Say in the commit message whether you could.
3. Small change only: `.lua` files that already exist, 60 changed lines or fewer for the whole release. The only
   toc edit allowed is the `## Version:` line.
4. If any gate fails, do not ship. Leave `main` as it was (`git reset --hard origin/main`), record `needs-kris`.

## Shipping
1. Bump the patch number in `GuildBoard/GuildBoard.toc` (1.5.1 -> 1.5.2). Add `### X.Y.Z (YYYY-MM-DD)` at the top
   of the Guild Board section in `CHANGELOG.md`, one plain "Fixed:" bullet per bug, written for guildies.
2. Write `images/announce/X.Y.Z.json`: `{"from": "Slixx", "embeds": [{"title": "Guild Board X.Y.Z: bug fixes",
   "link": true, "description": "..."}], "footer": "Something busted? Type /gb bug in game  ·  For the Horde"}`.
   The description lists the fixes in a few short lines and ends with: update in the CurseForge app (Push To Prod:
   Guild Board, https://www.curseforge.com/wow/addons/push-to-prod-guild-board) or download from GitHub, then
   fully restart WoW. No image, no em dashes, short.
3. Update `tools/bugfix/ledger.json`. Commit as `KrisHendo09 <KrisHendo09@users.noreply.github.com>`, push `main`.
4. Start the Release workflow (this run cannot push tags, the workflow makes the tag and the release itself):
   `gh api -X POST repos/KrisHendo09/guild-board/actions/workflows/release.yml/dispatches -f ref=main -f 'inputs[version]=X.Y.Z'`.
   It attaches the zips and uploads to CurseForge. Wait for it and check it: the run succeeded, the release has
   GuildBoard.zip, and the log says "Uploaded to CurseForge". If it failed, stop here and tell Kris. Do not
   announce a release that is not downloadable.
5. Announce: `gh api -X POST repos/KrisHendo09/guild-board/actions/workflows/announce.yml/dispatches -f ref=main
   -f 'inputs[file]=X.Y.Z.json' -f 'inputs[ping]=everyone' -F 'inputs[cleanup]=false'`. Check that run too.
   Kris approved the @everyone ping for bug fix releases on Nov 20, 2026. Never ping for anything else.

## Hand off (every run that shipped, or found dev-build bugs)
Write a dated note in Kris's Google Drive, My Drive > Claude > Personal > Gaming, named
`Addon request YYYY-MM-DD - <topic>.md`: what shipped (version, files, the diff in words) so the addon dev chat
merges it into the working copy on the Legion before the next feature release, plus any dev-build errors found.
Kris's PC stays on the dev build, so his game will say he is out of date until the dev chat merges. That is expected.

## If a fix goes wrong
A new error at the lines you changed, reported after your release: revert that commit and ship the revert as the
next patch the same way, and say so plainly in the notes.

## Guild feedback from Discord (added Nov 22, 2026)
Kris asked for the daily run to also tidy the Discord and hand guild feedback to the dev push.

Where: #guild-board (https://discord.com/channels/1568419835799543808/1571322080543375440) and the Guild Board
forum post (https://discord.com/channels/1568419835799543808/1572061287817547899). Read them in Kris's Chrome
(Claude in Chrome). Scroll to the top of each so every message loads; Discord unloads messages as you scroll.

1. **Log.** For every message from a person (not an APP/webhook post) whose id is not already in
   `data/feedback.json` (`items[].src`, `discord_done`, `discord_logged_keep`), decide what it is:
   - a bug report or a feature request: add an item `{who, kind: bug|feature, title (short, plain), status: queued,
     date, src: "discord <id>"}`. `who` is the Discord display name's first word as people know it.
   - chatter, thanks, a question, a GIF: nothing to log.
   - a troll: see Dunce corner.
2. **Hand off.** If anything new was logged, write one note to Kris's Drive folder Claude > Personal > Gaming >
   Guild Feedback (id 1SOqr0nDVxgR22bfe-4WCnqpUcg2HUA9I) named `YYYY-MM-DD Guild feedback.md`: a "For the dev push"
   list (each request or bug in a few lines, who asked, and its Discord id), then every message's full text as
   posted. This copy is the only record once Discord is cleaned, so copy text exactly. Bugs in released code that
   pass the gates are still yours to fix as usual; features are always the addon dev chat's.
3. **Credit.** An item becomes `status: shipped` (with `version`) when the released CHANGELOG or release notes say
   it shipped. The addon dev chat credits requesters by name, e.g. "(thanks Blexas)". A bug you fix yourself
   from a guild report is credited the same way in your CHANGELOG line. Declined ideas get `status: declined`.
   Shipped and queued items show on the Wall of Heroes under HELPED BUILD IT; declined ones don't.
4. **Clean up.** Kris approved this on Nov 22, 2026. Delete a message only when all of these hold: its text is in
   a Drive note (step 2 or an earlier day's), it is at least 12 hours old, it is not an APP/webhook post, it is not
   pinned, and it is not one of Kris's (slixx) posts from the last 24 hours. Kris's older posts do get deleted.
   Delete through Discord's own message menu (right-click, Delete Message, confirm). Never delete the board
   images or the announcements. Add each deleted id to `discord_done` (and drop it from `discord_logged_keep`).
   If a delete fails twice, leave it and say so. Ids you logged but could not delete yet go in
   `discord_logged_keep`.

## Dunce corner (added Nov 22, 2026)
Kris: if someone posts a request or bug report meant to break the addon or do something sneaky or nasty, put them
in the dunce corner. It shows on the Wall of Heroes for 7 days: a painted goblin in a dunce cap with their name
and a short line saying what they asked for.
- Counts: a request to hurt or rob other players (steal gold, items, mail, crypto, accounts), act on other
  players without their click, leak private info, grief or spam, run pasted code, or anything plainly a joke at
  the guild's expense dressed up as a request. A fake bug nobody else can see counts only when it is obviously
  made up.
- Does not count: honest bad ideas, blunt feedback, swearing, jokes that are not requests.
- Add `{who, why, at (unix time of the message), src: "discord <id>"}` to `dunce` in `data/feedback.json`. `why`
  is one short, funny, clean line (no slurs, nothing sexual, no real-life info), under 40 characters if you can.
- Never build it. Log it in the Drive note under "Dunce corner" so Kris and the dev chat see it.
- The board redraws on its own (GitHub, every hour at :07) from `data/feedback.json` on main, so pushing the file
  is all it takes. No separate post, no ping.

## Tell Kris
End every run with a short summary (no em dashes): bugs seen, what shipped and where, what is waiting on him.
Include what was logged, deleted and dunced. Nothing found and nothing to ship is a one-line summary.
