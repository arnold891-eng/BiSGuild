# BiSGuild — the CurseForge page

Paste this into the project description when the version changes. **The hash block must be updated
every release** — that is the whole point of it: the number on this page is one that whoever hands
you a doctored copy of the addon does not control.

Regenerate with `.\Tools\stamp.ps1`.

---

## ⚠️ This addon comes with a PowerShell script. Read this.

BiSGuild works out raid attendance and consumables from **your own combat log**. A World of Warcraft
addon is not allowed to read files off your disk — that rule is what stops addons rifling through
your documents, and it is a good rule. So the reading is done by a small PowerShell script that
ships inside the addon, and the addon just tells you the command to run it.

**A PowerShell script can do anything you can do on your computer.** Only run this one if you got
BiSGuild from this CurseForge page or from your own guild officers. **If somebody sent you a copy,
do not run it** — however helpful they seem. That is the check that actually matters; everything
below is a second line of defence.

### Checking your copy has not been tampered with

In PowerShell:

    Get-FileHash -Algorithm SHA256 "<your WoW folder>\Interface\AddOns\BiSGuild\Tools\logreport.ps1"

The answer must be exactly this, for **the current version**:

    SHA-256   BBFE79CFAD1180A03054E72B4BFFFFA54742C28196BC1981F268EA0D91B4C827

`/bisg script` in game also shows a number — but **compare against this page, not against that**.
Whoever tampers with the script can change the number the addon shows you just as easily, and then
both of them agree and you feel like you checked something. **The only number that helps is this
one, because it is the one they cannot edit.** If what `Get-FileHash` tells you differs from the
line above, **stop** and ask an officer.

What this does and does not prove, plainly:

- It catches somebody swapping **only the script** inside an otherwise real addon.
- It catches a half-finished or corrupted download.
- It does **not** catch somebody giving you a completely fake BiSGuild, because they would change
  the number in it too. Nothing inside a file can prove the file is genuine. Where you got it is the
  only real answer — which is why that is the first thing this page says.

---

## What it does

- **Attendance** — a raid night is earned by being there for at least half its boss kills. Life
  happens; leaving at nine for a sick child does not cost you the night.
- **Consumables** — at each pull, did you have a flask (or a battle and a guardian elixir) and food.
- **Tonight is never in the numbers.** Whoever is rolling on loot is standing in the raid by
  definition, so the record is what they did *before* tonight. The night joins once it ends.

Both come from the combat log, so they say what happened, not what anyone remembers.

## Setting it up

1. `/bisg logs <paste the path to your WoW Logs folder>` — once, ever.
2. After a raid, `/bisg script` and run the line it gives you.
3. `/reload`, then `/bisg report`.

Nothing is typed into a box in game and nothing is uploaded anywhere. The script reads the newest
log on your own disk and writes the two percentages into the addon.
