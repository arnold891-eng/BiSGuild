# BiSGuild

## 0.1.0

Fingerprint (SHA-256 of the whole addon, check it with the command on the CurseForge page): `D0375501644F887783CC69320842BDA7696F962DE882782BFE520070D68B3F33`

The first public release. Loot night, two raiders, one trinket, and everyone thinks they remember who showed up. BiS Guild read the log instead.

- **The raider terminal** (`/bisg`): RAIDERS, BOSSES, WHERE, ROSTER and LOG. Attendance, deaths, flasks and food, gear issues in red, item tooltips with the enchant, the game's own right-click menu on every name. Esc steps back a page.
- **The record comes from your combat log.** A small PowerShell script reads it, only the logs it hasn't read yet, and the addon picks the night up at `/reload`. Nothing to paste.
- **Shared with your officers.** Any officer who reads a log hands the night to the whole guild, so a missed raid still fills in. Only officers are believed. Each guild keeps its own books, so an alt in another guild never sees your main's.
- **Raid night.** Paste the Raid-Helper sign-up: who's online, absent or not in the guild, one button to invite everyone online, a pop-up when a sign-up logs in, and punctuality kept raid after raid.
- **WHERE**: your guildmates on a map, opening in OpenMap when it's installed.
- **Loot**: awards in a tamper-evident ledger per guild, `/bisl`. BiS Loot is folded in.
- **Your copy is checked, three ways.** One fingerprint covers every file, with a one-line PowerShell check on the CurseForge page. The script refuses to run on a copy that doesn't match. In game, a missing or mismatched file switches BiS Guild off and says which, and your guildmates' copies tell you if yours differs or is out of date (`/bisg copy`).
- Works with BiS Tools (invites through its party list) and OpenMap. Needs neither.

## 0.0.1

- Created from the BiS house skeleton (`_bisdev/new-addon.sh`): shared BiS channel, palette, tests, CI and
  release from GitHub already wired.
- Window: the report's "last" line keeps the kill count; the boss names moved into its tooltip. A full
  Black Temple night ran the line out of the window.
