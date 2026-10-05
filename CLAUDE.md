Read ../_bisdev/CLAUDE.md first.

## Layout (BiSGuild only)

- `BiSGuild.toc`: the load order and the only place the version lives (`## Version`). It also carries
  `## X-Curse-Project-ID` (0 until the CurseForge project exists) and `## X-CurseForge-GameVersionType`,
  which `dev/release.ps1` reads.
- `Core/Init.lua`: the house skeleton from `_bisdev/new-addon.sh` — palette per call (`ns.T`), `ns.VERSION`
  from the TOC, `ns.Print`, `BiSGuildDB` defaults, the shared BiS channel booted with its off switch saved,
  and `/bisg`, which hands straight to `ns.Say`.
- `Core/Nights.lua`: **the rules, and nothing that reads the client** — so a whole raid tier runs through
  the suite in a millisecond. A night is a run of kills with no three-hour gap (the same rule as
  BiSMemories 0.4.0, on purpose: two addons that disagreed about what night it was would be worse than
  either being wrong alone). A night is **earned by being there for at least half its kills** — Arn,
  4 Oct 2026: *"if there were there for at least half the kills, sometimes life happens"*. Asked as
  `seen * 2 >= total`, never `seen >= total / 2`: a person's raid record does not go near floating
  point. A night where nothing died counts for nobody and against nobody.
- `Core/Roster.lua`: the only file that asks the client anything. Every name goes through `lib.Short`,
  which answers nil for a secret value (LibBiSComm minor 7) — an attendance list uses names as table
  keys, and one secret would be a red error in the middle of a boss kill.
- `Core/Watch.lua`: `BOSS_KILL` **and** `ENCOUNTER_END`, because neither is reliable alone and only the
  second can tell a kill from a wipe. Both fire for one kill on some clients, so the same boss inside
  `W.SETTLE` seconds is the same kill — counted twice, a two-boss night becomes a four-boss night and
  everyone's half moves.
- `Core/Say.lua`: reading it back. Every number can be opened up — the percentage, the nights behind it,
  the kills behind those — because the first thing a council does is say "that is not right".
- `Libs/`: embedded `BiSTheme/Console.lua` and `LibBiSComm-1.0` — copies, see `../_bisdev/CLAUDE.md`.
- `dev/tests.lua`: headless suite on `dev/kit.lua` (Nebbinator's strict harness, verbatim). Loads the TOC's
  files in order, fails on any global not in `ALLOWED`. `dev/theme.lua`: the palette law.
- `dev/release.ps1`: zip + CurseForge upload (normally GitHub runs it on a tag — see
  `../_bisdev/docs/playbook.md`).
- `.github/workflows/check.yml` (every push/PR) and `release.yml` (tag = release, PR = dry run).
