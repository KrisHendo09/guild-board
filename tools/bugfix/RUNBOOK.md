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
4. `git tag vX.Y.Z && git push origin vX.Y.Z`. The Release workflow makes the GitHub release, attaches the zips
   and uploads to CurseForge. Wait for it and check it: the run succeeded, the release has GuildBoard.zip, and the
   log says "Uploaded to CurseForge". If it failed, stop here and tell Kris. Do not announce a release that is
   not downloadable.
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

## Tell Kris
End every run with a short summary (no em dashes): bugs seen, what shipped and where, what is waiting on him.
Nothing found and nothing to ship is a one-line summary.
