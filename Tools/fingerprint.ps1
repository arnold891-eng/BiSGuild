<#
  BiSGuild :: Tools\fingerprint.ps1 - one number for the whole addon, and the check against it.

  Dot-sourced by logreport.ps1 (which refuses to run on a copy that fails the check) and by
  stamp.ps1 (which writes the number into the places that publish it). Nothing here runs by itself.

  Arn, 16 Oct 2026: "we can do it like face fusion and there are multiple places that need to match
  up for the hash to work ... really lock it down since its a powershell its running".

  THE FINGERPRINT. Every file of the addon, hashed one by one with SHA-256, written as a line
  "<HASH> <path>", the lines sorted, joined with a newline each - and that text hashed once more.
  That text IS Tools\manifest.txt, so the fingerprint is also simply its Get-FileHash. Change one
  character in any file and the number moves. Add a file and it moves. Take one away and it moves.

  WHICH FILES. All of them except four kinds, each for a reason:
    * anything starting with a dot - .gitattributes and the like, which deploy copies and
      CurseForge does not; they are git's, not the game's
    * *.md - the readme and the changelog are words, never run, and the changelog CARRIES the
      fingerprint, which would make it change itself
    * Data\Report.lua - the script writes it after every raid, so it is a different file every night
    * Core\Build.lua and Tools\manifest.txt - they hold the number, so they cannot be inside it.
      Instead they are checked for being EXACTLY what the number says they should be, so nothing
      can be smuggled into them either.

  WHAT IT PROVES, said plainly because a check that is oversold is worse than none: a swapped,
  added, missing, half-updated or corrupted file - caught. Somebody handing you a whole fake addon -
  not caught by anything inside that addon, this file included, because they would change this file
  too. The one check a faker cannot reach is the CurseForge page's own command and number.

  THE RULE IS IN THREE PLACES THAT MUST AGREE: here, the one-line check on the CurseForge page
  (dev\cf-desc.md, and the addon's /bisg script) and the Lua suite (dev\tests.lua), which works it out
  again on its own, so a mistake in one of them cannot hide behind the others.
#>

# The paths left out, as one pattern. The one-line check on the CurseForge page uses this same text.
$script:BiSGuildSkip = '(^|/)\.|\.md$|^(Data/Report\.lua|Core/Build\.lua|Tools/manifest\.txt)$'

function Get-BiSGuildLines {
    <# The manifest's lines for the addon folder $Root. With -Files, only those relative paths (the
       way stamp.ps1 asks: what git ships, not what happens to be lying in the repo). #>
    param([Parameter(Mandatory = $true)][string] $Root, [string[]] $Files)
    $Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    if (-not $Files) {
        $Files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
            $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
        })
    }
    $lines = @()
    foreach ($rel in $Files) {
        $rel = $rel.Replace('\', '/')
        if ($rel -match $script:BiSGuildSkip) { continue }
        $full = Join-Path $Root $rel
        $lines += ((Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash + ' ' + $rel)
    }
    $lines = [string[]] $lines
    [Array]::Sort($lines, [StringComparer]::Ordinal)
    return , $lines
}

function Get-BiSGuildText([string[]] $Lines) {
    if ($Lines.Count -eq 0) { return "" }
    return ($Lines -join "`n") + "`n"
}

function Get-BiSGuildHash([string] $Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    return ([BitConverter]::ToString($bytes)).Replace('-', '')
}

function Get-BiSGuildParts([string] $Root) {
    <# Our own Lua files, in the TOC's order: everything it loads except the libraries and the
       report the script writes. Each one ends by writing its version into ns.parts. #>
    $toc = [System.IO.File]::ReadAllLines((Join-Path $Root "BiSGuild.toc"))
    $parts = @()
    foreach ($l in $toc) {
        $l = $l.Trim()
        if ($l -eq "" -or $l.StartsWith("#")) { continue }
        $rel = $l.Replace('\', '/')
        if ($rel -like "Libs/*" -or $rel -eq "Data/Report.lua" -or $rel -eq "Core/Build.lua") { continue }
        $parts += $rel
    }
    return , ([string[]] $parts)
}

function Get-BiSGuildVersion([string] $Root) {
    foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $Root "BiSGuild.toc"))) {
        if ($l -match '^## Version:\s*(\S+)') { return $Matches[1] }
    }
    throw "no ## Version in BiSGuild.toc"
}

function Get-BiSGuildBuildLua([string] $Version, [string] $Fingerprint, [string[]] $Parts) {
    <# Core\Build.lua, exactly. The Lua suite builds the same text and the two must agree. #>
    $t = "-- BiSGuild :: Core/Build.lua - written by Tools\stamp.ps1. Never edit it by hand.`n"
    $t += "--`n"
    $t += "-- What this copy says it is. Every file of ours ends by writing its version into ns.parts, and`n"
    $t += "-- Core/Copies.lua checks them against this list at login: a file missing, failing to load, or`n"
    $t += "-- left over from another version, and BiS Guild says so and stops. The fingerprint is the`n"
    $t += "-- SHA-256 of Tools/manifest.txt. This file is not inside it (it holds it); logreport.ps1 checks`n"
    $t += "-- instead that it is exactly this text and nothing else.`n"
    $t += "local _, ns = ...`n"
    $t += "ns.BUILD = {`n"
    $t += "    version = `"$Version`",`n"
    $t += "    fingerprint = `"$Fingerprint`",`n"
    $t += "    parts = {`n"
    foreach ($p in $Parts) { $t += "        `"$p`",`n" }
    $t += "    },`n"
    $t += "}`n"
    return $t
}

function Test-BiSGuildCopy {
    <# Is the installed copy at $Root whole? Returns @{ ok; fingerprint; problems }. #>
    param([Parameter(Mandatory = $true)][string] $Root)
    $Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    $problems = @()
    $lines = Get-BiSGuildLines -Root $Root
    $fingerprint = Get-BiSGuildHash (Get-BiSGuildText $lines)

    $manifestPath = Join-Path $Root "Tools\manifest.txt"
    $promised = $fingerprint             # what Core\Build.lua must carry: the manifest's own hash
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $problems += "Tools\manifest.txt is missing"
    } else {
        $expect = @{}
        foreach ($l in [System.IO.File]::ReadAllLines($manifestPath)) {
            if ($l -match '^([0-9A-F]{64}) (.+)$') { $expect[$Matches[2]] = $Matches[1] }
            elseif ($l -ne "") { $problems += "Tools\manifest.txt has a line it should not: $l" }
        }
        $have = @{}
        foreach ($l in $lines) { if ($l -match '^([0-9A-F]{64}) (.+)$') { $have[$Matches[2]] = $Matches[1] } }
        foreach ($p in ($expect.Keys | Sort-Object)) {
            if (-not $have.ContainsKey($p)) { $problems += "$p is missing" }
            elseif ($have[$p] -ne $expect[$p]) { $problems += "$p has been changed" }
        }
        foreach ($p in ($have.Keys | Sort-Object)) {
            if (-not $expect.ContainsKey($p)) { $problems += "$p should not be there" }
        }
        $raw = [System.IO.File]::ReadAllText($manifestPath)
        $promised = Get-BiSGuildHash $raw
        if ($problems.Count -eq 0 -and $raw -ne (Get-BiSGuildText $lines)) {
            $problems += "Tools\manifest.txt is not written the way stamp.ps1 writes it"
        }
    }

    $buildPath = Join-Path $Root "Core\Build.lua"
    if (-not (Test-Path -LiteralPath $buildPath)) {
        $problems += "Core\Build.lua is missing"
    } else {
        $want = Get-BiSGuildBuildLua (Get-BiSGuildVersion $Root) $promised (Get-BiSGuildParts $Root)
        if ([System.IO.File]::ReadAllText($buildPath) -ne $want) {
            $problems += "Core\Build.lua is not the one this copy was built with"
        }
    }
    return @{ ok = ($problems.Count -eq 0); fingerprint = $fingerprint; problems = $problems }
}
