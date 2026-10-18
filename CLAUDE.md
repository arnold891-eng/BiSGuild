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
  derivation and it works at any depth. Builds the one-line check (`P.CheckCommand`, rule `P.SKIP`).
- **The fingerprint (16 Oct 2026).** One SHA-256 for every shipped file: `Tools/fingerprint.ps1` says
  which files and why, `Tools/stamp.ps1` writes it into `Tools/manifest.txt`, `Core/Build.lua`,
  `dev/cf-desc.md` and the CHANGELOG's top entry. **Run `Tools\stamp.ps1` after ANY change to a
  shipped file or the version** - the suite works the number out again on its own and goes red
  until you do. `logreport.ps1` refuses to run on a copy whose files do not match. Every Lua file of
  ours ENDS with `ns.parts["<path>"] = "<version>"` (stamp rewrites it); `Core/Copies.lua` checks
  them at login and switches a copy that is not whole off, and swaps version + fingerprint with
  guildmates (GLOG `BUILD`, `/bisg copy`). `.gitattributes` says `* -text`: the hash is of exact
  bytes, so git must never touch line endings. None of it proves a wholly fake addon is fake - only
  the CurseForge page's own line and number can, and the addon says so.
- **The number lives in the release notes (17 Oct 2026, Arn: "we change to release note").** Each
  release's CHANGELOG entry - fingerprint as its first line - goes up as that file's notes on
  CurseForge; the page's check block sends people to the Files tab and carries no number, so a
  release never needs a page edit. `dev/cf-desc.md` keeps a record line above `---` (never pasted)
  that stamp step 4 still rewrites. **Owed with the next shipped change:** stamp.ps1's closing line
  still says "Paste ... onto the CurseForge page" - make it "the number rides the release notes", and
  every new release's top CHANGELOG entry must keep its `Fingerprint (SHA-256` line.
- **Published only on CurseForge and GitHub** (Arn, 17 Oct) - the page says any other copy isn't ours.
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
  Since 16 Oct also three THIRD-PARTY libs, BiS Tools' copies byte for byte (the suite checks):
  `LibStub`, `CallbackHandler-1.0`, `HereBeDragons` (BSD) - sources and commits in
  `Libs/THIRD-PARTY.txt`. Never edit them. The suites compile HereBeDragons but never run it (it drives
  the client's map engine); `dev/tests.lua` swaps in a strict pins stand-in.
- `Core/Store.lua`, `Core/Share.lua`: the guild's record (`BiSGuildDB.record`) and its sharing over
  LibBiSComm GUILD ("GLOG", officers believed). `Core/Terminal.lua`, `Core/Where.lua`: the raider
  terminal and its WHERE page. `Core/Pins.lua`: guildmates' dots on the world map. Plan: `dev/TERMINAL.md`.
- `dev/tests.lua`: headless suite on `dev/kit.lua` (Nebbinator's strict harness, verbatim). Loads the TOC's
  files in order, fails on any global not in `ALLOWED`. `dev/theme.lua`: the palette law.
- `dev/release.ps1`: zip + CurseForge upload (normally GitHub runs it on a tag — see
  `../_bisdev/docs/playbook.md`).
- `.github/workflows/check.yml` (every push/PR) and `release.yml` (tag = release, PR = dry run).
