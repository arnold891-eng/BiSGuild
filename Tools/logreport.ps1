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
    [switch] $Review
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

foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
    $sep = $line.IndexOf("  ")
    if ($sep -lt 0) { continue }
    $body = $line.Substring($sep + 2)
    $comma = $body.IndexOf(",")
    if ($comma -lt 0) { continue }
    $event = $body.Substring(0, $comma)

    if ($event -eq "ENCOUNTER_START") {
        $f = $body -split ","
        $cur = @{ boss = $f[2].Trim('"'); kill = $false; who = @{} }
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

$counted = @($pulls | Where-Object { $AllPulls -or $_.kill })
if ($counted.Count -eq 0) {
    Write-Host ("no {0} found in that log." -f $(if ($AllPulls) { "pulls" } else { "boss kills" }))
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
Write-Host ("{0} boss kill(s): {1}" -f $total, $zones)
Write-Host ("{0,-16} {1,8} {2,9}" -f "", "attend", "consumes")
foreach ($r in $rows) { Write-Host ("{0,-16} {1,7}% {2,8}%" -f $r.name, $r.attend, $r.consumes) }

# ----------------------------------------------------- hand it to the addon ---
# The WoW folder is the Logs folder with \Logs taken off, so the one path the player gave us
# reaches every installed copy of the addon.
$flavour = Split-Path (Split-Path $Logs -Parent) -Leaf
$wowRoot = Split-Path (Split-Path $Logs -Parent) -Parent
$written = @()
foreach ($dir in (Get-ChildItem -LiteralPath $wowRoot -Directory -ErrorAction SilentlyContinue)) {
    $addon = Join-Path $dir.FullName "Interface\AddOns\BiSGuild"
    if (-not (Test-Path -LiteralPath $addon)) { continue }
    $data = Join-Path $addon "Data"
    New-Item -ItemType Directory -Force -Path $data | Out-Null

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("-- Written by BiSGuild/Tools/logreport.ps1. Do not edit: the next run replaces it.")
    [void]$sb.AppendLine("-- Raid data, not source. A deploy removes it.")
    [void]$sb.AppendLine("BiSGuildReport = {")
    [void]$sb.AppendLine(("    written = {0}," -f [int][double]::Parse((Get-Date -UFormat %s))))
    [void]$sb.AppendLine(("    kills = {0}," -f $total))
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
