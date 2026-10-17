<#
  BiSGuild :: Tools\logreport.ps1 - the whole thing, in the shell every Windows machine already has.

  Arn, 4 Oct 2026: "we should ask one time copy the path to your logs folder once and from there we
  generate a ps script they can powershell to do the whole process, the powershell will hopefully
  get the most recent log and not run all the logs".

  WHY POWERSHELL AND NOT THE PYTHON ONE. dev/logreport.py does the same job and is easier to read,
  but it needs Python installed, and most of a raid does not have it. This needs nothing. The two
  are kept in step on purpose: same consumables.txt, same output file, same rules.

  WHY ONE LOG AND NOT ALL OF THEM. A Logs folder holds every night ever recorded. Reading the lot
  would take minutes and mix last February into tonight's numbers. Newest by write time, unless
  -Log names one.

  It never loads the file. ReadLines hands over one line at a time, which is why 110 MB is not a
  problem - and why every other program that tried to open it died.

      powershell -ExecutionPolicy Bypass -File Tools\logreport.ps1 -Logs "C:\...\_anniversary_\Logs"

  -Logs is the only thing it needs: the WoW folder is that one with \Logs taken off, and the addon
  folder is under it, so one path answers everything.
#>
param(
    [Parameter(Mandatory = $true)] [string] $Logs,
    [string] $Log,
    [switch] $AllPulls,
    [switch] $Review,
    # Count five-man bosses too. Useful for proving the whole chain works on a client that has no
    # raids yet; wrong for a record, because a Tuesday heroic is not a raid night.
    [switch] $Dungeons
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------ the copy first --
# NOTHING RUNS ON A COPY THAT IS NOT WHOLE (Arn, 16 Oct 2026: "we can do it like face fusion ... really
# lock it down since its a powershell its running"). Every file of the addon is checked against
# Tools\manifest.txt before a single log line is read: one changed, added or missing file and the
# script stops and says which. Tools\fingerprint.ps1 says what is counted and why.
#
# THIS CANNOT PROVE THE SCRIPT ITSELF IS GENUINE. A doctored script could simply skip these lines. That
# is what the CurseForge page's own one-line check is for - it is typed from the page, not from here.
$here = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "fingerprint.ps1")
$copy = Test-BiSGuildCopy -Root $here
if (-not $copy.ok) {
    Write-Host "STOPPED - this copy of BiS Guild is not the one that was released:" -ForegroundColor Red
    $copy.problems | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Nothing was read and nothing was written. Get a fresh copy from CurseForge (delete the"
    Write-Host "BiSGuild folder first, then install it again), or ask an officer."
    exit 1
}
Write-Host ("copy checked: every file matches - fingerprint {0}" -f $copy.fingerprint)
Write-Host "  (compare it with the CurseForge page, not with anything the addon shows you)"

# ---------------------------------------------------------------- the log ----
if (-not (Test-Path -LiteralPath $Logs)) { throw "no such folder: $Logs" }

# EVERY LOG NOT READ YET, OLDEST FIRST (16 Oct 2026). Arn put four logs in the folder and the script
# read one: "there are 4 logs tho". It took only the newest, which is right for "run it after every
# raid" and wrong for the worry the whole record exists for - "if I miss one raid night". Miss one
# run and that night was never read. So the folder is the to-do list: a log is remembered in
# WTF\BiSGuild\seen.txt by name, size and whether -Dungeons was on, and every log not on that list
# is read, oldest first, each by this same script with -Log. A log still being written has grown
# since, so it is read again; a log with no kills is remembered too, so it is not re-read forever.
$seenPath = Join-Path (Join-Path (Join-Path (Split-Path $Logs -Parent) "WTF") "BiSGuild") "seen.txt"
function Get-SeenKey($f) { "{0}|{1}|{2}" -f $f.Name, $f.Length, $(if ($Dungeons) { "d" } else { "r" }) }
function Set-Seen($f) {
    $dir = Split-Path $seenPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::AppendAllText($seenPath, (Get-SeenKey $f) + "`n", (New-Object System.Text.UTF8Encoding $false))
}

if ($Log) {
    $file = Get-Item -LiteralPath $Log
} else {
    $all = @(Get-ChildItem -LiteralPath $Logs -Filter "WoWCombatLog*.txt" | Sort-Object LastWriteTime)
    if ($all.Count -eq 0) { throw "no WoWCombatLog*.txt in $Logs" }
    $seen = @{}
    if (Test-Path -LiteralPath $seenPath) {
        foreach ($l in [System.IO.File]::ReadAllLines($seenPath)) { if ($l) { $seen[$l] = $true } }
    }
    $todo = @($all | Where-Object { -not $seen.ContainsKey((Get-SeenKey $_)) })
    if ($todo.Count -eq 0) {
        Write-Host "every log in the folder has been read already - writing the report again from the record"
        $file = $all[$all.Count - 1]
    } else {
        if ($todo.Count -gt 1) { Write-Host ("{0} logs not read yet - reading them oldest first" -f $todo.Count) }
        for ($i = 0; $i -lt $todo.Count - 1; $i++) {
            $one = @{ Logs = $Logs; Log = $todo[$i].FullName }
            if ($Dungeons) { $one.Dungeons = $true }
            if ($AllPulls) { $one.AllPulls = $true }
            try { & $PSCommandPath @one } catch { Write-Host ("  {0} could not be read: {1}" -f $todo[$i].Name, $_) }
            Write-Host ""
        }
        $file = $todo[$todo.Count - 1]
    }
}
if (-not $file) { throw "no WoWCombatLog*.txt in $Logs" }

$sizeMB = [math]::Round($file.Length / 1MB, 1)
Write-Host ("reading {0} ({1} MB)" -f $file.Name, $sizeMB)

# ------------------------------------------------------- which auras count ----
# The same file the Python one reads. Shipped beside the addon so a raider who was handed the
# folder has it too.
$listPath = Join-Path $PSScriptRoot "consumables.txt"
if (-not (Test-Path -LiteralPath $listPath)) {
    $listPath = Join-Path (Split-Path $PSScriptRoot -Parent) "dev\consumables.txt"
}
$kinds = @{}
if (Test-Path -LiteralPath $listPath) {
    foreach ($raw in [System.IO.File]::ReadLines($listPath)) {
        $line = ($raw -split "#", 2)[0].Trim()
        if (-not $line) { continue }
        $bits = $line -split "\s+", 2
        # potion: a CAST inside a boss pull (the raider card's potions, as the old raid-prep sheet
        # counted them)
        if ($bits.Count -eq 2 -and @("flask", "elixir", "scroll", "food", "potion") -contains $bits[0]) {
            $kinds[$bits[1].Trim().ToLower()] = $bits[0]
        }
    }
}
if ($kinds.Count -eq 0) { throw "consumables.txt is empty or missing ($listPath) - nothing can be judged" }

# ------------------------------------------------------- the raider card ------
# Arn, 16 Oct 2026: "type a raider name, show the gear they have ... their attendance ... how much
# they consume - what we used to put into the raider sheet and lc sheet". Kept in step with
# dev/logreport.py: same slots, same gearcheck.txt, same numbers (dev/test_logreport.py runs both
# on one log and compares every field).
$Slots = @("head", "neck", "shoulder", "shirt", "chest", "waist", "legs", "feet", "wrist", "hands",
           "finger1", "finger2", "trinket1", "trinket2", "back", "mainhand", "offhand", "ranged", "tabard")

# the top-level [...] groups of a COMBATANT_INFO line: talents, gear, auras
function Get-Brackets([string]$s) {
    $out = New-Object System.Collections.ArrayList
    $depth = 0; $start = -1
    for ($i = 0; $i -lt $s.Length; $i++) {
        $c = $s[$i]
        if ($c -eq '[') { if ($depth -eq 0) { $start = $i }; $depth++ }
        elseif ($c -eq ']') {
            $depth--
            if ($depth -eq 0 -and $start -ge 0) { [void]$out.Add($s.Substring($start, $i - $start + 1)); $start = -1 }
        }
    }
    return ,$out
}

# the gear bracket: 19 of (itemId, itemLevel, (permanent, temporary, onUse), (bonus), (gems)) ->
# @(id, ilvl, enchant, temp, @(gems)); the temporary enchant is the weapon's oil or stone
function Get-Gear([string]$body) {
    $b = Get-Brackets $body
    if ($b.Count -lt 3) { return $null }
    try { $raw = ($b[$b.Count - 2] -replace '\(', '[' -replace '\)', ']') | ConvertFrom-Json } catch { return $null }
    $out = New-Object System.Collections.ArrayList
    foreach ($t in @($raw)) {
        $t = @($t)
        if ($t.Count -lt 2) { [void]$out.Add(@(0, 0, 0, 0, @())); continue }
        $ench = if ($t.Count -gt 2) { @($t[2]) } else { @() }
        $gems = New-Object System.Collections.ArrayList
        if ($t.Count -gt 4) { foreach ($g in @($t[4])) { if ($g) { [void]$gems.Add([int]$g) } } }
        $e0 = if ($ench.Count -gt 0) { [int]$ench[0] } else { 0 }
        $e1 = if ($ench.Count -gt 1) { [int]$ench[1] } else { 0 }
        [void]$out.Add(@([int]$t[0], [int]$t[1], $e0, $e1, $gems))
    }
    if ($out.Count -lt 16) { return $null }
    return ,$out
}

# which slots should carry an enchant: DATA (gearcheck.txt), the guild's call
$checkPath = Join-Path $PSScriptRoot "gearcheck.txt"
if (-not (Test-Path -LiteralPath $checkPath)) { $checkPath = Join-Path (Split-Path $PSScriptRoot -Parent) "dev\gearcheck.txt" }
$wantEnchant = New-Object System.Collections.ArrayList
if (Test-Path -LiteralPath $checkPath) {
    foreach ($raw in [System.IO.File]::ReadLines($checkPath)) {
        $bits = (($raw -split "#", 2)[0].Trim()) -split "\s+"
        if ($bits.Count -eq 2 -and $bits[0] -eq "enchant" -and $Slots -contains $bits[1]) { [void]$wantEnchant.Add($bits[1]) }
    }
}

# ------------------------------------------------------------- one pass -------
$names = @{}          # spell id -> spell name, learned from the log itself
$guidName = @{}       # player guid -> short name
$pulls = New-Object System.Collections.ArrayList
$cur = $null

# READ IT WHILE WOW IS STILL WRITING IT (5 Oct 2026, off Arn's shell):
#
#   Exception calling "ReadLines" ... "The process cannot access the file ... because it is being
#   used by another process."
#
# [System.IO.File]::ReadLines asks for FileShare.Read - "others may read, nobody may write" - and
# the client has the log open for writing the whole time logging is on. So it refused the one case
# that matters: looking at tonight's raid before logging out of it.
#
# FileShare.ReadWrite says we do not mind it being written underneath us, which is true: we read
# forward once and a line appended behind us is simply not in this report. Telling the player to
# turn logging off first would have "worked" and been the wrong answer.
# STILL ONE LINE AT A TIME. A `foreach` over a collected `while` would read the whole 110 MB into
# memory first, which is precisely what every program that crashes on this file does.
$stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open,
                                 [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$reader = New-Object System.IO.StreamReader($stream)
while ($null -ne ($line = $reader.ReadLine())) {
    $sep = $line.IndexOf("  ")
    if ($sep -lt 0) { continue }
    $body = $line.Substring($sep + 2)
    $comma = $body.IndexOf(",")
    if ($comma -lt 0) { continue }
    $event = $body.Substring(0, $comma)

    if ($event -eq "ENCOUNTER_START") {
        # ENCOUNTER_START,<id>,"<name>",<difficulty>,<groupSize>,... - the name is quoted and could
        # hold a comma, so it is matched rather than split.
        #
        # A DUNGEON BOSS IS NOT A RAID NIGHT. The addon learned that when Arn said there are no
        # raids in Forever yet; this reader never did, so a five-man log would have produced
        # attendance indistinguishable from real raid data. groupSize is the honest line.
        $m = [regex]::Match($body, 'ENCOUNTER_START,(\d+),"(.*?)",(-?\d+),(-?\d+)')
        if ($m.Success) {
            $cur = @{ boss = $m.Groups[2].Value; size = [int]$m.Groups[4].Value; kill = $false; who = @{} }
        } else {
            $f = $body -split ","
            $cur = @{ boss = $f[2].Trim('"'); size = 0; kill = $false; who = @{} }
        }
        $cur.gear = @{}; $cur.deaths = @{}; $cur.pots = @{}; $cur.ms = 0
        [void]$pulls.Add($cur)
    }
    elseif ($event -eq "ENCOUNTER_END") {
        $f = $body -split ","
        if ($cur) {
            $cur.kill = ($f.Count -gt 5 -and $f[5].Trim() -eq "1")
            # ENCOUNTER_END,id,"name",difficulty,size,success,fightTime(ms) - the boss page's best time
            $ms = 0
            if ($f.Count -gt 6 -and [int]::TryParse($f[6].Trim(), [ref]$ms)) { $cur.ms = $ms }
        }
        $cur = $null
    }
    elseif ($event -eq "UNIT_DIED") {
        # a raider dying INSIDE a pull
        $f = $body -split ","
        if ($cur -and $f.Count -gt 6 -and $f[5].StartsWith("Player-")) {
            if (-not $cur.deaths.ContainsKey($f[5])) { $cur.deaths[$f[5]] = 0 }
            $cur.deaths[$f[5]]++
            $guidName[$f[5]] = ($f[6].Trim('"') -split "-")[0]
        }
    }
    elseif ($event -eq "SPELL_CAST_SUCCESS") {
        # a potion or healthstone used inside a pull
        $f = $body -split ","
        if ($f.Count -gt 10) {
            $sid = 0
            if ([int]::TryParse($f[9], [ref]$sid)) { $names[$sid] = $f[10].Trim('"') }
            if ($cur -and $f[1].StartsWith("Player-") -and $kinds[$f[10].Trim('"').ToLower()] -eq "potion") {
                if (-not $cur.pots.ContainsKey($f[1])) { $cur.pots[$f[1]] = 0 }
                $cur.pots[$f[1]]++
                $guidName[$f[1]] = ($f[2].Trim('"') -split "-")[0]
            }
        }
    }
    elseif ($event -eq "COMBATANT_INFO") {
        if ($cur) {
            $guid = ($body -split ",")[1]
            # the last bracket is the whole buff list: (caster, spellId, _) repeated
            $a = $body.LastIndexOf("["); $b = $body.LastIndexOf("]")
            $ids = New-Object System.Collections.ArrayList
            if ($a -ge 0 -and $b -gt $a) {
                $parts = $body.Substring($a + 1, $b - $a - 1) -split ","
                for ($i = 1; $i -lt $parts.Count; $i += 3) {
                    $n = 0
                    if ([int]::TryParse($parts[$i], [ref]$n)) { [void]$ids.Add($n) }
                }
            }
            $cur.who[$guid] = $ids
            $g = Get-Gear $body
            if ($g) { $cur.gear[$guid] = $g }
        }
    }
    elseif ($event.StartsWith("SPELL_") -and $event.Contains("_AURA_")) {
        $f = $body -split ","
        if ($f.Count -gt 11) {
            $sid = 0
            if ([int]::TryParse($f[9], [ref]$sid)) { $names[$sid] = $f[10].Trim('"') }
            foreach ($pair in @(@(1, 2), @(5, 6))) {
                $g = $f[$pair[0]]; $n = $f[$pair[1]].Trim('"')
                if ($g.StartsWith("Player-") -and $n) { $guidName[$g] = ($n -split "-")[0] }
            }
        }
    }
}
# let go of the client's file the moment we are done with it, even if something above threw
$reader.Dispose()
$stream.Dispose()

$counted = @($pulls | Where-Object { $AllPulls -or $_.kill })
# NOT $dungeons - PowerShell variable names are case-insensitive, so a local $dungeons IS the
# -Dungeons switch, and assigning an array to it makes the parameter binder throw "Cannot convert
# System.Object[] to SwitchParameter" on the NEXT run. Caught the first time this was run.
$fiveMans = @($counted | Where-Object { $_.size -gt 0 -and $_.size -le 5 })
if (-not $Dungeons) { $counted = @($counted | Where-Object { -not ($_.size -gt 0 -and $_.size -le 5) }) }
if ($counted.Count -eq 0) {
    Write-Host ("no {0} found in that log." -f $(if ($AllPulls) { "pulls" } else { "boss kills" }))
    if ($fiveMans.Count -gt 0 -and -not $Dungeons) {
        Write-Host ("  {0} five-man boss kill(s) were left out - a dungeon boss is not a raid night." -f $fiveMans.Count)
        Write-Host "  -Dungeons counts them, which is useful for testing and wrong for a record."
    }
    Set-Seen $file          # read, and nothing in it: not worth reading again
    exit 1
}

# ------------------------------------------------------------- the sums -------
function NameOf($guid) { if ($guidName.ContainsKey($guid)) { $guidName[$guid] } else { $guid } }

# THE RAIDER CARD'S NUMBERS: per raider this night. Gear, deaths and potions read EVERY pull of the
# night (a wipe is still a death); the consumables stay on the kills, as before.
$detail = @{}
function Get-Detail($who) {
    if (-not $detail.ContainsKey($who)) {
        $detail[$who] = @{ pulls = 0; flask = 0; elixir = 0; food = 0; weapon = 0; weaponSeen = 0
                           pots = 0; deaths = 0; gear = $null }
    }
    return $detail[$who]
}
$nightPulls = @($pulls | Where-Object { $Dungeons -or -not ($_.size -gt 0 -and $_.size -le 5) })
foreach ($p in $nightPulls) {
    foreach ($g in @($p.deaths.Keys)) { $d = Get-Detail (NameOf $g); $d['deaths'] += $p.deaths[$g] }
    foreach ($g in @($p.pots.Keys))   { $d = Get-Detail (NameOf $g); $d['pots'] += $p.pots[$g] }
    foreach ($g in @($p.gear.Keys))   { $d = Get-Detail (NameOf $g); $d['gear'] = $p.gear[$g] }
}

# A BOSS IS A TICKER (Arn, 16 Oct): this night's pulls, kills, fastest kill, who stood in each kill
$bossNight = @{}
foreach ($p in $nightPulls) {
    if (-not $bossNight.ContainsKey($p.boss)) {
        $bossNight[$p.boss] = @{ pulls = 0; kills = 0; best = 0; killers = (New-Object System.Collections.ArrayList) }
    }
    $b = $bossNight[$p.boss]
    $b['pulls'] += 1
    if ($p.kill) {
        $b['kills'] += 1
        if ($p.ms -and (-not $b['best'] -or $p.ms -lt $b['best'])) { $b['best'] = $p.ms }
        foreach ($g in @($p.who.Keys)) { [void]$b['killers'].Add((NameOf $g)) }
    }
}

$present = @{}; $prepared = @{}; $unknown = @{}
foreach ($p in $counted) {
    foreach ($guid in $p.who.Keys) {
        $who = if ($guidName.ContainsKey($guid)) { $guidName[$guid] } else { $guid }
        if (-not $present.ContainsKey($who)) { $present[$who] = 0; $prepared[$who] = 0 }
        $present[$who]++
        $dt = Get-Detail $who
        $dt['pulls'] += 1
        $g = $p.gear[$guid]
        if ($g -and $g.Count -gt 15 -and $g[15][0]) {
            $dt['weaponSeen'] += 1
            if ($g[15][3]) { $dt['weapon'] += 1 }
        }
        $flask = 0; $elixirs = 0; $food = 0
        foreach ($sid in $p.who[$guid]) {
            $nm = if ($names.ContainsKey($sid)) { $names[$sid] } else { "id $sid" }
            $kind = $kinds[$nm.ToLower()]
            if ($kind -eq "food") { $food++ }
            elseif ($kind -eq "flask") { $flask++ }
            elseif ($kind -eq "elixir" -or $kind -eq "scroll") { $elixirs++ }
            else { $unknown[$nm] = $true }
        }
        if (($flask -gt 0 -or $elixirs -ge 2) -and $food -gt 0) { $prepared[$who]++ }
        if ($flask -gt 0) { $dt['flask'] += 1 }
        if ($flask -eq 0 -and $elixirs -ge 2) { $dt['elixir'] += 1 }
        if ($food -gt 0) { $dt['food'] += 1 }
    }
}

if ($Review) {
    Write-Host "`nauras not in consumables.txt:`n"
    foreach ($n in ($unknown.Keys | Sort-Object)) { Write-Host ("  {0}" -f $n) }
    Write-Host "`nAdd the consumables to $listPath and run again."
    exit 0
}

$total = $counted.Count
$rows = foreach ($who in $present.Keys) {
    [pscustomobject]@{
        name     = $who
        attend   = [math]::Round(100 * $present[$who] / $total)
        consumes = if ($present[$who]) { [math]::Round(100 * $prepared[$who] / $present[$who]) } else { 0 }
    }
}
$rows = @($rows | Sort-Object @{E = "attend"; D = $true}, @{E = "consumes"; D = $true}, name)

$zones = ($counted | ForEach-Object { $_.boss } | Sort-Object -Unique) -join ", "

# ============================================================= the history ====
# Arn, 5 Oct 2026: "how are we going to keep track of how people are doing with attendance if it
# wipes the data when i reload?"
#
# The reload was never the problem - Data\Report.lua is a file and the client loads it every login.
# The real hole was underneath the question: each run read ONE log and OVERWROTE the report, so it
# only ever said what happened last night. Attendance across one raid is not attendance.
#
# So the record lives here, and the report is computed from all of it.
#
# IT LIVES IN WTF, not in the addon folder: deploy.sh wipes the addon before copying, and this
# client hands back no saved variables at all, so those were the two places it could not go. WTF is
# per client, which matches the rule that a client's record is about that client's raids.
#
# ONE LOG IS ONE NIGHT, keyed by the log's own filename. That makes re-running the same log replace
# its night instead of counting it twice - the thing a history most needs to survive. The cost is
# that logging straight through two raid nights without restarting the client counts as one; rare,
# and it makes somebody's attendance kinder rather than harsher.
# the client folder: Logs' parent. Defined here because the history needs it too, and it is
# the same one the report is written into further down.
$client = Split-Path $Logs -Parent
$wtf = Join-Path $client "WTF"
$histDir = Join-Path $wtf "BiSGuild"
$histPath = Join-Path $histDir "history.json"

# EVERY FIELD COMES BACK (16 Oct 2026): this used to rebuild a night from present/ready alone, which
# would quietly drop the raider card's detail and the boss pages the Python reader writes into the
# same file. JSON objects become hashtables, arrays stay arrays, all the way down.
function ConvertTo-Plain($o) {
    if ($null -eq $o) { return $null }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Plain $p.Value }
        return $h
    }
    if ($o -is [System.Array]) {
        $a = New-Object System.Collections.ArrayList
        foreach ($x in $o) { [void]$a.Add((ConvertTo-Plain $x)) }
        return ,$a
    }
    return $o
}

$nights = @{}
if (Test-Path -LiteralPath $histPath) {
    try {
        $raw = Get-Content -LiteralPath $histPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($n in @($raw.nights)) {
            $h = ConvertTo-Plain $n
            if (-not $h.present) { $h.present = @{} }
            if (-not $h.ready) { $h.ready = @{} }
            $nights[$h.log] = $h
        }
    } catch {
        # a half-written or hand-edited history is started over rather than crashing the run: the
        # numbers are rebuildable from the logs, and a tool that dies on its own cache is worse
        Write-Host "history.json could not be read - starting a fresh one"
        $nights = @{}
    }
}

# the filename carries when logging started: WoWCombatLog-MMDDYY_HHMMSS.txt
$stamp = ""
if ($file.Name -match 'WoWCombatLog-(\d{2})(\d{2})(\d{2})_') {
    $stamp = "20{0}-{1}-{2}" -f $Matches[3], $Matches[1], $Matches[2]
}
$thisNight = @{ log = $file.Name; date = $stamp; zones = $zones; kills = $total
                present = @{}; ready = @{}; detail = $detail; bosses = $bossNight }
foreach ($who in $present.Keys) {
    $thisNight.present[$who] = $present[$who]
    $thisNight.ready[$who]   = $prepared[$who]
}
$nights[$file.Name] = $thisNight

if (-not (Test-Path -LiteralPath $histDir)) { New-Item -ItemType Directory -Force -Path $histDir | Out-Null }
$out = [ordered]@{ version = 1; nights = @($nights.Values | Sort-Object { $_.log }) }
[System.IO.File]::WriteAllText($histPath, ($out | ConvertTo-Json -Depth 12),
                               (New-Object System.Text.UTF8Encoding $false))
Set-Seen $file              # its night is in the history now

# ------------------------------------------------- the numbers, over all of it
# A RAID DAY IS THE WHOLE DAY (Arn, 5 Oct: "i guess we can count a raid day as the whole day not
# just 3 hr window some people run more than 3 hours").
#
# The history is stored per LOG, because that is what makes re-running the same log replace its
# entry instead of counting it twice. But the UNIT is the day: logs from one date are added
# together first, so a six-hour clear in one log and a client restarted halfway through a raid both
# come out as exactly one night. Keyed by log, counted by day - each key doing the job it is good at.
#
# A NIGHT IS EARNED BY HALF ITS KILLS (Arn, 4 Oct: "if there were there for at least half the kills,
# sometimes life happens"). Asked as present*2 >= kills, never present >= kills/2: three kills and
# one attendance is 1 against 1.5, and a raid record does not go near floating point.
$days = @{}
foreach ($n in @($nights.Values)) {
    $key = if ($n.date) { $n.date } else { $n.log }     # an unparseable filename is its own day
    if (-not $days.ContainsKey($key)) { $days[$key] = @{ kills = 0; present = @{}; ready = @{} } }
    $d = $days[$key]
    $d.kills += $n.kills
    foreach ($who in $n.present.Keys) {
        if (-not $d.present.ContainsKey($who)) { $d.present[$who] = 0; $d.ready[$who] = 0 }
        $d.present[$who] += $n.present[$who]
        $d.ready[$who]   += $n.ready[$who]
    }
}

$earned = @{}; $seenPulls = @{}; $readyPulls = @{}
$attended = @{}       # who -> the days they earned, for the raider card
foreach ($key in @($days.Keys | Sort-Object)) {
    $d = $days[$key]
    foreach ($who in $d.present.Keys) {
        if (-not $earned.ContainsKey($who)) { $earned[$who] = 0; $seenPulls[$who] = 0; $readyPulls[$who] = 0 }
        if ($d.present[$who] * 2 -ge $d.kills) {
            $earned[$who]++
            if (-not $attended.ContainsKey($who)) { $attended[$who] = New-Object System.Collections.ArrayList }
            [void]$attended[$who].Add($key)
        }
        $seenPulls[$who] += $d.present[$who]
        $readyPulls[$who] += $d.ready[$who]
    }
}
$raided = $days.Count

# ONE CARD PER RAIDER from every night on record (same rules as dev/logreport.py build_cards)
function Get-NightKey($n) { if ($n.date) { $n.date } else { $n.log } }
$byDate = @($nights.Values | Sort-Object { Get-NightKey $_ })
$cards = @{}
foreach ($n in $byDate) {
    $date = Get-NightKey $n
    if (-not $n.detail) { continue }
    foreach ($who in @($n.detail.Keys)) {
        $dd = $n.detail[$who]
        if (-not $cards.ContainsKey($who)) { $cards[$who] = @{ deaths = 0; pots = 0; last = $null; gear = $null; gearDate = $null } }
        $c = $cards[$who]
        $c['deaths'] += [int]$dd.deaths
        $c['pots'] += [int]$dd.pots
        if ([int]$dd.pulls -gt 0) {
            $c['last'] = @{ date = $date }
            foreach ($k in @("pulls", "flask", "elixir", "food", "weapon", "weaponSeen", "pots", "deaths")) { $c['last'][$k] = [int]$dd[$k] }
        }
        if ($dd.gear) { $c['gear'] = $dd.gear; $c['gearDate'] = $date }
    }
}
foreach ($who in @($cards.Keys)) {
    $c = $cards[$who]
    # an assignment, not `= if ... { $list }`: PowerShell unrolls a one-item list that comes out of an
    # if-expression into the item itself, and a raider with one night became the string "2026-10-16"
    # (dev/test_logreport.py caught it against the Python reader)
    if ($attended.ContainsKey($who)) { $c['attended'] = $attended[$who] }
    else { $c['attended'] = New-Object System.Collections.ArrayList }
    $iss = New-Object System.Collections.ArrayList
    if ($c.gear) {
        foreach ($slot in $wantEnchant) {
            $i = [array]::IndexOf($Slots, $slot)
            if ($i -lt $c.gear.Count -and $c.gear[$i][0] -and -not $c.gear[$i][2]) {
                [void]$iss.Add(@{ slot = $slot; item = [int]$c.gear[$i][0]; what = "no enchant" })
            }
        }
    }
    $c['issues'] = $iss
}

# ONE PAGE PER BOSS (same rules as dev/logreport.py build_bosses)
$bossPages = @{}
foreach ($n in $byDate) {
    $date = Get-NightKey $n
    if (-not $n.bosses) { continue }
    foreach ($boss in @($n.bosses.Keys)) {
        $b = $n.bosses[$boss]
        if (-not $bossPages.ContainsKey($boss)) {
            $bossPages[$boss] = @{ kills = 0; wipes = 0; best = 0; first = $null
                                   nights = (New-Object System.Collections.ArrayList); killers = @{} }
        }
        $pg = $bossPages[$boss]
        $pg['kills'] += [int]$b.kills
        $pg['wipes'] += [int]$b.pulls - [int]$b.kills
        if ([int]$b.kills -gt 0) {
            if (-not $pg['first']) { $pg['first'] = $date }
            if (-not $pg['nights'].Contains($date)) { [void]$pg['nights'].Add($date) }
        }
        if ([int]$b.best -and (-not $pg['best'] -or [int]$b.best -lt $pg['best'])) { $pg['best'] = [int]$b.best }
        foreach ($who in @($b.killers)) {
            if (-not $pg['killers'].ContainsKey($who)) { $pg['killers'][$who] = 0 }
            $pg['killers'][$who] += 1
        }
    }
}

# EVERY RAID DAY AS ONE RECORD (same rules as dev/logreport.py build_nightly): what BiS Guild keeps
# in its saved variables and shares with the guild. Logs from one date are added together.
$nightFields = @("present", "ready", "pulls", "flask", "elixir", "food", "weapon", "weaponSeen", "pots", "deaths")
$nightly = @{}
foreach ($n in $byDate) {
    $date = Get-NightKey $n
    if (-not $nightly.ContainsKey($date)) { $nightly[$date] = @{ kills = 0; raiders = @{}; bosses = @{} } }
    $nd = $nightly[$date]
    $nd['kills'] += [int]$n.kills
    $whoAll = @{}
    foreach ($who in @($n.present.Keys)) { $whoAll[$who] = $true }
    if ($n.detail) { foreach ($who in @($n.detail.Keys)) { $whoAll[$who] = $true } }
    foreach ($who in @($whoAll.Keys)) {
        if (-not $nd.raiders.ContainsKey($who)) {
            $r = @{}
            foreach ($k in $nightFields) { $r[$k] = 0 }
            $nd.raiders[$who] = $r
        }
        $r = $nd.raiders[$who]
        if ($n.present.ContainsKey($who)) { $r['present'] += [int]$n.present[$who] }
        if ($n.ready.ContainsKey($who)) { $r['ready'] += [int]$n.ready[$who] }
        if ($n.detail -and $n.detail.ContainsKey($who)) {
            $dd = $n.detail[$who]
            foreach ($k in $nightFields[2..($nightFields.Count - 1)]) { $r[$k] += [int]$dd[$k] }
        }
    }
    if ($n.bosses) {
        foreach ($boss in @($n.bosses.Keys)) {
            $b = $n.bosses[$boss]
            if (-not $nd.bosses.ContainsKey($boss)) {
                $nd.bosses[$boss] = @{ pulls = 0; kills = 0; best = 0; killers = (New-Object System.Collections.ArrayList) }
            }
            $pb = $nd.bosses[$boss]
            $pb['pulls'] += [int]$b.pulls
            $pb['kills'] += [int]$b.kills
            if ([int]$b.best -and (-not $pb['best'] -or [int]$b.best -lt $pb['best'])) { $pb['best'] = [int]$b.best }
            foreach ($who in @($b.killers)) { if ($null -ne $who) { [void]$pb['killers'].Add([string]$who) } }
        }
    }
}
# one order, so both readers and every copy say the same - ORDINAL, as Python sorts, not the culture's
foreach ($nd in @($nightly.Values)) {
    foreach ($pb in @($nd.bosses.Values)) { $pb['killers'].Sort([System.StringComparer]::Ordinal) }
}

# any value as Lua: numbers, strings, lists, string-keyed tables (a $null is left out)
function ConvertTo-Lua($v, [string]$ind) {
    if ($null -eq $v) { return "nil" }
    if ($v -is [bool]) { if ($v) { return "true" } else { return "false" } }
    if ($v -is [string]) { return '"' + ($v -replace '\\', '\\' -replace '"', '\"') + '"' }
    if ($v -is [System.Collections.IDictionary]) {
        $inner = $ind + "    "
        $parts = New-Object System.Collections.ArrayList
        foreach ($k in @($v.Keys | Sort-Object { [string]$_ })) {
            if ($null -eq $v[$k]) { continue }
            $key = if ([string]$k -match '^[A-Za-z_][A-Za-z0-9_]*$') { [string]$k } else { '[' + (ConvertTo-Lua ([string]$k) "") + ']' }
            [void]$parts.Add(("{0}{1} = {2}," -f $inner, $key, (ConvertTo-Lua $v[$k] $inner)))
        }
        return "{`n" + ($parts -join "`n") + "`n" + $ind + "}"
    }
    if ($v -is [System.Collections.IEnumerable]) {
        $items = New-Object System.Collections.ArrayList
        foreach ($x in $v) { [void]$items.Add((ConvertTo-Lua $x $ind)) }
        return "{ " + ($items -join ", ") + " }"
    }
    return [string]$v
}
$rows = foreach ($who in $earned.Keys) {
    [pscustomobject]@{
        name     = $who
        attend   = [math]::Round(100 * $earned[$who] / $raided)
        consumes = if ($seenPulls[$who]) { [math]::Round(100 * $readyPulls[$who] / $seenPulls[$who]) } else { 0 }
    }
}
$rows = @($rows | Sort-Object @{E = "attend"; D = $true}, @{E = "consumes"; D = $true}, name)

Write-Host ("this log: {0} boss kill(s): {1}" -f $total, $zones)
Write-Host ("over {0} raid night(s) on record:" -f $raided)
Write-Host ("{0,-16} {1,8} {2,9}" -f "", "attend", "consumes")
foreach ($r in $rows) { Write-Host ("{0,-16} {1,7}% {2,8}%" -f $r.name, $r.attend, $r.consumes) }

# ----------------------------------------------------- hand it to the addon ---
# The WoW folder is the Logs folder with \Logs taken off, so the one path the player gave us
# reaches every installed copy of the addon.
# THE REPORT GOES WHERE THE LOG CAME FROM, AND NOWHERE ELSE (5 Oct 2026).
#
# This used to write into every client installed beside this one. It sounded generous and it was
# wrong: Arn read a Forever dungeon log and it overwrote the Black Temple report sitting in TBC.
# A client's raid record is about THAT client's raids, and quietly replacing one set of numbers with
# an unrelated set is the worst thing a tool like this can do - the numbers still look right.
#
# Logs and Interface are siblings inside the client folder, so dropping \Logs is the whole
# derivation, and it works at any depth. Somebody who wants the numbers in two clients runs it
# twice, which is a sentence, not a surprise.
$roots = @()
if ($client) { $roots += $client }
$written = @()
foreach ($root in $roots) {
    $addon = Join-Path $root "Interface\AddOns\BiSGuild"
    if (-not (Test-Path -LiteralPath $addon)) { continue }
    $data = Join-Path $addon "Data"
    New-Item -ItemType Directory -Force -Path $data | Out-Null

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("-- Written by BiSGuild/Tools/logreport.ps1. Do not edit: the next run replaces it.")
    [void]$sb.AppendLine("-- Raid data, not source. A deploy removes it.")
    [void]$sb.AppendLine("BiSGuildReport = {")
    [void]$sb.AppendLine(("    written = {0}," -f [int][double]::Parse((Get-Date -UFormat %s))))
    [void]$sb.AppendLine(("    kills = {0}," -f $total))
    [void]$sb.AppendLine(("    nights = {0}," -f $raided))
    [void]$sb.AppendLine(("    zones = `"{0}`"," -f ($zones -replace '"', '\"')))
    [void]$sb.AppendLine("    rows = {")
    foreach ($r in $rows) {
        [void]$sb.AppendLine(("        {{ name = `"{0}`", attend = {1}, consumes = {2} }}," -f ($r.name -replace '"', '\"'), $r.attend, $r.consumes))
    }
    [void]$sb.AppendLine("    },")
    # the raid days on record, one card per raider, one page per boss (the raider terminal reads these)
    [void]$sb.AppendLine(("    days = {0}," -f (ConvertTo-Lua (@($days.Keys | Sort-Object)) "    ")))
    [void]$sb.AppendLine(("    cards = {0}," -f (ConvertTo-Lua $cards "    ")))
    [void]$sb.AppendLine(("    bosses = {0}," -f (ConvertTo-Lua $bossPages "    ")))
    # every raid day as one record: what the addon keeps and shares with the guild
    [void]$sb.AppendLine(("    nightly = {0}," -f (ConvertTo-Lua $nightly "    ")))
    [void]$sb.AppendLine("}")

    $out = Join-Path $data "Report.lua"
    [System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
    $written += $out
}

Write-Host ""
if ($written.Count -gt 0) {
    foreach ($w in $written) { Write-Host "written: $w" }
    Write-Host "/reload in the client and the numbers are there. Nothing to paste."
} else {
    Write-Host "no BiSGuild addon folder found under $wowRoot - is it installed?"
}
