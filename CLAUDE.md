Read ../_bisdev/CLAUDE.md first.

## Layout (BiSGuild only)

- `BiSGuild.toc`: the load order and the only place the version lives (`## Version`). It also carries
  `## X-Curse-Project-ID` (0 until the CurseForge project exists) and `## X-CurseForge-GameVersionType`,
  which `dev/release.ps1` reads.
- `Core/Init.lua`: the house skeleton from `_bisdev/new-addon.sh` — palette per call (`ns.T`), `ns.VERSION`
  from the TOC, `ns.Print`, `BiSGuildDB` defaults, the shared BiS channel booted with its off switch saved,
  and `/bisg`, which hands straight to `ns.Say`.
- `Core/Report.lua`: what the combat log said. `BiSGuildReport` is written into `Data/Report.lua` by
  the script and loaded like any other file, so `/reload` IS the import - nothing is typed or pasted.
  Also remembers where the player's Logs folder is (asked once) and builds the PowerShell line from
  it: `Logs` and `Interface` are SIBLINGS inside the client folder, so dropping `\Logs` is the whole
  derivation and it works at any depth. Carries `P.SCRIPT_SHA`, which is **not** proof of anything on
  its own - a faked addon fakes it too; the CurseForge page is the only number worth comparing.
- `Core/Window.lua`: the window. A terminal, on purpose (Arn: "the more we make it look like a
  powershell window the better"): PowerShell's own `#012456`, Arial Narrow, a `PS>` prompt, a cursor
  blinking at 2 Hz. **The command does not exist until the warning is answered** - the box is empty
  and the warning covers it, ten frame levels up so nothing can print through its words. The hash
  check lives inside the warning and types itself out.
- **Nothing is collected in game.** The addon used to count boss kills and who was standing there;
  that was a second source of truth against the combat log, and when two disagree the one people
  believe is the one on the website (Arn, 5 Oct: "we can get rid of the attendence and consume check
  lets do logs for that"). `dev/logreport.py` and `Tools/logreport.ps1` read the log instead - one
  line at a time, so 110 MB costs seconds and not memory, and with `FileShare.ReadWrite` so it works
  while WoW still has the file open. Which auras count is DATA (`dev/consumables.txt`), never a rule
  in the code: the buff does not carry its item's name.
- `Core/Say.lua`: the slash commands. Bare `/bisg` opens the window; `report`, `logs <path>` and
  `script` are the rest, and anything unrecognised is the report, because there is nothing else it
  could mean now.
- `Libs/`: embedded `BiSTheme/Console.lua` and `LibBiSComm-1.0` — copies, see `../_bisdev/CLAUDE.md`.
- `dev/tests.lua`: headless suite on `dev/kit.lua` (Nebbinator's strict harness, verbatim). Loads the TOC's
  files in order, fails on any global not in `ALLOWED`. `dev/theme.lua`: the palette law.
- `dev/release.ps1`: zip + CurseForge upload (normally GitHub runs it on a tag — see
  `../_bisdev/docs/playbook.md`).
- `.github/workflows/check.yml` (every push/PR) and `release.yml` (tag = release, PR = dry run).
