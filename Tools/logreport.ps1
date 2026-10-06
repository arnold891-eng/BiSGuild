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

# ---------------------------------------------------------------- the log ----
if (-not (Test-Path -LiteralPath $Logs)) { throw "no such folder: $Logs" }

if ($Log) {
    $file = Get-Item -LiteralPath $Log
} else {
    $file = Get-ChildItem -LiteralPath $Logs -Filter "WoWCombatLog*.txt" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
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
        if ($bits.Count -eq 2 -and @("flask", "elixir", "scroll", "food") -contains $bits[0]) {
            $kinds[$bits[1].Trim().ToLower()] = $bits[0]
        }
    }
}
if ($kinds.Count -eq 0) { throw "consumables.txt is empty or missing ($listPath) - nothing can be judged" }

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
        [void]$pulls.Add($cur)
    }
    elseif ($event -eq "ENCOUNTER_END") {
        $f = $body -split ","
        if ($cur) { $cur.kill = ($f.Count -gt 5 -and $f[5].Trim() -eq "1") }
        $cur = $null
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
    exit 1
}

# ------------------------------------------------------------- the sums -------
$present = @{}; $prepared = @{}; $unknown = @{}
foreach ($p in $counted) {
    foreach ($guid in $p.who.Keys) {
        $who = if ($guidName.ContainsKey($guid)) { $guidName[$guid] } else { $guid }
        if (-not $present.ContainsKey($who)) { $present[$who] = 0; $prepared[$who] = 0 }
        $present[$who]++
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

$nights = @{}
if (Test-Path -LiteralPath $histPath) {
    try {
        $raw = Get-Content -LiteralPath $histPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($n in @($raw.nights)) {
            $p = @{}; $r = @{}
            foreach ($kv in $n.present.PSObject.Properties) { $p[$kv.Name] = [int]$kv.Value }
            foreach ($kv in $n.ready.PSObject.Properties)   { $r[$kv.Name] = [int]$kv.Value }
            $nights[$n.log] = @{ log = $n.log; date = $n.date; zones = $n.zones
                                 kills = [int]$n.kills; present = $p; ready = $r }
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
                present = @{}; ready = @{} }
foreach ($who in $present.Keys) {
    $thisNight.present[$who] = $present[$who]
    $thisNight.ready[$who]   = $prepared[$who]
}
$nights[$file.Name] = $thisNight

if (-not (Test-Path -LiteralPath $histDir)) { New-Item -ItemType Directory -Force -Path $histDir | Out-Null }
$out = [ordered]@{ version = 1; nights = @($nights.Values | Sort-Object { $_.log }) }
[System.IO.File]::WriteAllText($histPath, ($out | ConvertTo-Json -Depth 6),
                               (New-Object System.Text.UTF8Encoding $false))

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
foreach ($d in $days.Values) {
    foreach ($who in $d.present.Keys) {
        if (-not $earned.ContainsKey($who)) { $earned[$who] = 0; $seenPulls[$who] = 0; $readyPulls[$who] = 0 }
        if ($d.present[$who] * 2 -ge $d.kills) { $earned[$who]++ }
        $seenPulls[$who] += $d.present[$who]
        $readyPulls[$who] += $d.ready[$who]
    }
}
$raided = $days.Count
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
