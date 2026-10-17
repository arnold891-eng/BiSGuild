# BiSGuild

## Unreleased

Fingerprint (SHA-256 of the whole addon, check it with the command on the CurseForge page): `E22C6B157846971787956C3B647D7A6F9522BA658D7102423CF5FF3B81E72C7C`

- **Your copy is checked, three ways.** One fingerprint covers every file of the addon, published on the CurseForge page with a one-line PowerShell check you can run yourself. The log script refuses to run if any file was changed, added or removed, and says which. In game, a file that is missing, broke while loading, or is left over from an older version switches BiS Guild off and says why.
- **Your guild checks too.** At login each copy tells guildmates its version and fingerprint. Yours tells you if it differs from everyone else's or is out of date; `/bisg copy` shows how yours compares, and officers see who runs what.
- Shared messaging library updated (LibBiSComm minor 10): after a boss, when the game lifts its chat lockdown, BiS addons say hello again so group lists stay current; it respects a realm that blocks addon messages, picks the raid channel only when the game confirms you are in a raid, and ignores anyone flooding it.

## 0.0.1

- Created from the BiS house skeleton (`_bisdev/new-addon.sh`): shared BiS channel, palette, tests, CI and
  release from GitHub already wired.
- Window: the report's "last" line keeps the kill count; the boss names moved into its tooltip. A full
  Black Temple night ran the line out of the window.
