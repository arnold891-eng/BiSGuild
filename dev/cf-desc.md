# BiS Guild — CurseForge page text

Paste everything below the line into the project description, in the Markdown editor. **The check
block's number changes every release** — `.\Tools\stamp.ps1` rewrites it here; paste the page again
when the version goes up. The number on the live page is the one a faker cannot reach, so a stale
one there is worse than none.

In the house voice (`_bisdev/docs/voice.md`): the opener and the script section talk; lists stay flat.

**Name:** BiS Guild
**Summary (the one-liner):** Your guild's raid record, read from the combat log: who showed, who came prepared, who's late, who's geared. For WoW Forever.

---

# BiS Guild

**Your guild's raid record, read from the combat log. For WoW Forever.**

Loot night. Two raiders want the same trinket. One has been to every raid this month, flasked, on time. The other hasn't. Everyone in the room thinks they remember which is which. BiS Guild doesn't remember. It read the log.

## What you get

`/bisg` opens the raider terminal. Five tabs.

- **RAIDERS** — everyone who has raided with you: attendance, last raid, flask or elixirs, deaths, and gear issues in red, like a slot that should be enchanted and isn't. Sorted by class the way a raid sheet reads, pugs at the bottom. Click a name for their whole card.
- **BOSSES** — every boss you've killed: kills, wipes, your best time, the night it first died, and who was there.
- **WHERE** — your guildmates on a map, right now. Click one and the map opens on their zone. With OpenMap installed, one button opens it there.
- **ROSTER** — paste the Raid-Helper sign-up and see who's online, who's absent, who isn't in the guild. One button invites everyone online.
- **LOG** — where the numbers come from (below).

Hover any item for its tooltip, enchant included. Right-click any name for the game's own player menu. Esc steps back a page; keep pressing and it closes.

## Raid night, handled

- **The raid at a glance.** Title, start time, a countdown, and how many sign-ups are online.
- **A pop-up when a sign-up logs in**, with an invite button on it. From two hours before the raid until four hours after.
- **Punctuality.** On time, late and by how long, or a no-show, kept raid after raid. "Late twice in eight" says more than one bad night. An invite that went out late is never held against the raider.
- **Loot.** Every award goes into a tamper-evident ledger, kept per guild. `/bisl` shows it.

## Shared with your officers

Any officer who reads a log hands the night to everyone else in the guild. Miss a raid and your copy still fills in. Nights, gear and punctuality are only taken from officers, so nobody can write themselves into the record. The guild master sets who counts as an officer once, with one line in the Guild Information text.

Your alts keep their own books. A character in another guild sees that guild's record, never your main's.

## The numbers come from your combat log

An addon isn't allowed to read files off your disk, and that's a good rule. So BiS Guild ships a small PowerShell script that reads the log for you. `/bisg logs <your Logs folder>` once. After a raid, `/bisg script` gives you the line to run. `/reload` and the night is in. Nothing to paste, nothing uploaded anywhere.

- **Attendance**: a raid night counts if you were there for at least half its boss kills. Leaving at nine for a sick kid doesn't cost you the night.
- **Consumables**: at each pull, a flask (or a battle and a guardian elixir) and food.
- **Gear**: what each raider wore at the pull, straight from the log. No inspecting.

A 110 MB log takes seconds. It reads one line at a time, and only the logs it hasn't read yet.

## ⚠️ Before you run the script

**A PowerShell script can do anything you can do on your computer.** We publish BiS Guild in two places only: **this CurseForge page** and **its GitHub page** (github.com/arnold891-eng/BiSGuild). Anywhere else (another website, a file in Discord, a "fixed" copy somebody sends you) isn't us, however official it looks, so don't run it. Where you got it is the check that matters. Everything below is the second line.

### Check your copy

One number covers every file of the addon. Change one letter anywhere, add a file or take one away, and it changes. Copy this line, put your WoW folder where it says, and paste it into PowerShell. It only reads; it changes nothing.

    $a='<your WoW folder>\Interface\AddOns\BiSGuild';$l=[string[]](ls -LiteralPath $a -Recurse -File|%{$r=$_.FullName.Substring($a.Length+1).Replace('\','/');if($r -notmatch '(^|/)\.|\.md$|^(Data/Report\.lua|Core/Build\.lua|Tools/manifest\.txt)$'){(Get-FileHash -A SHA256 -LiteralPath $_.FullName).Hash+' '+$r}});[Array]::Sort($l,[StringComparer]::Ordinal);[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($l -join "`n")+"`n"))).Replace('-','')

The answer must be exactly this, for **the current version**:

    Fingerprint   93B8570923F7CCE40F422614E08BFBD59C527287E992460939285076C5EF67AC

The addon shows you a number too. **Compare with this page, not with that.** Whoever doctors a copy can change what the addon shows just as easily. If your answer differs, stop and ask an officer.

The addon checks itself as well:

- **The script won't run** on a copy whose files don't match the list it shipped with. It names the file that's wrong.
- **In game**, a file that's missing, broke while loading, or is left over from an older version switches BiS Guild off and says which.
- **Your guild checks too.** Each copy tells your guildmates its version and fingerprint at login. Yours tells you if it differs from everyone else's or is out of date. `/bisg copy` shows how yours compares; officers see who runs what.

What none of this can catch is a completely fake BiS Guild. A fake controls everything it shows you, its checks included. Nothing inside a file can prove the file is genuine. That's why this section starts with where you got it.

## Works with

- **BiS Tools** — when it's installed, invites go through its party list. Without it, BiS Guild invites on its own.
- **OpenMap** — when it's installed, the WHERE tab can open a guildmate's spot in it.
- **Other addons** can read the record through `BiSGuildAPI`.

Neither is needed. BiS Guild works alone.

## Commands

| | |
|---|---|
| `/bisg` | open the terminal |
| `/bisg logs <path>` | tell it where your Logs folder is, once |
| `/bisg script` | the line to run after a raid |
| `/bisg copy` | is this copy whole, and does it match your guild's |
| `/bisg logins on` / `off` | the pop-up when a sign-up logs in |
| `/bisg dots on` / `off` | guildmates on the world map |
| `/bisl` | the loot ledger |

Part of the BiS family. Talks to the other BiS addons over one shared channel; `/biscomm off` silences it.
