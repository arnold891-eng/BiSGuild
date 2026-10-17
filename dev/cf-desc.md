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

One number covers **every file** of the addon. Change one letter anywhere, add a file or take one
away, and it changes. Copy this line, put your WoW folder where it says, and paste it into
PowerShell (it only reads; it changes nothing):

    $a='<your WoW folder>\Interface\AddOns\BiSGuild';$l=[string[]](ls -LiteralPath $a -Recurse -File|%{$r=$_.FullName.Substring($a.Length+1).Replace('\','/');if($r -notmatch '(^|/)\.|\.md$|^(Data/Report\.lua|Core/Build\.lua|Tools/manifest\.txt)$'){(Get-FileHash -A SHA256 -LiteralPath $_.FullName).Hash+' '+$r}});[Array]::Sort($l,[StringComparer]::Ordinal);[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($l -join "`n")+"`n"))).Replace('-','')

The answer must be exactly this, for **the current version**:

    Fingerprint   E22C6B157846971787956C3B647D7A6F9522BA658D7102423CF5FF3B81E72C7C
`/bisg script` in game shows the same line and a number too — but **take the line from this page and
compare against this page**. Whoever doctors a copy can change what the addon shows you just as
easily, and then both agree and you feel like you checked something. **The only number that helps is
this one, because it is the one they cannot edit.** If your answer differs, **stop** and ask an
officer.

The addon checks itself as well, three ways:

- **The script refuses to run** on a copy whose files do not match the list it shipped with, and
  says which file is wrong.
- **In game**, a file that is missing, broke while loading, or is left over from an older version
  switches BiS Guild off and says which.
- **Your guild**: every copy tells your guildmates its version and fingerprint at login. Yours tells
  you if it is different from everyone else's, or older; officers can see who runs what (`/bisg copy`).

What this does and does not prove, plainly:

- It catches a swapped, added or missing file, and a half-finished, half-updated or corrupted
  download.
- It does **not** catch somebody giving you a completely fake BiSGuild: they would change every
  number in it, and its checks would tell you everything is fine. Nothing inside a file can prove
  the file is genuine. Where you got it is the only real answer — which is why that is the first
  thing this page says.

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
2