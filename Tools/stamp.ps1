<#
  BiSGuild :: Tools\stamp.ps1 - the addon's fingerprint, into every place that must agree on it.

      .\Tools\stamp.ps1           work it out and write it everywhere
      .\Tools\stamp.ps1 -Check    say whether every place still agrees; exit 1 if not

  RUN IT AFTER ANY CHANGE TO A SHIPPED FILE, and after bumping ## Version. The suite goes red until
  you do - and a red suite stops the release - so a stale number cannot reach CurseForge again
  (5 Oct 2026: it did, a day stale, and a mismatch reads as "you were given a doctored addon").

  WHAT "THE ADDON" IS: what git ships (tracked, or new and not ignored), minus the dev side - the
  same rule as _bisdev\release\stage.ps1 - minus what Tools\fingerprint.ps1 leaves out and says why.

  WHERE THE NUMBER GOES, and all of them must agree (Arn, 16 Oct: "multiple places that need to
  match up for the hash to work"):
    Tools\manifest.txt      every file and its hash; the fingerprint is this file's own hash
    Core\Build.lua          what the copy says it is, in game and to guildmates
    dev\cf-desc.md          the CurseForge page - the one place a faker cannot reach
    CHANGELOG.md            the top entry, which is also the release notes CurseForge shows
  and every one of our Lua files ends with its version (ns.parts), which this rewrites from the TOC.

  THE NUMBER IN THE DOWNLOAD PROVES NOTHING BY ITSELF. Whoever doctors a copy restamps it too. The
  check that counts is the CurseForge page's own command and number against the copy on your disk.
#>
param([switch] $Check)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "fingerprint.ps1")
$utf8 = New-Object System.Text.UTF8Encoding $false
$bad = @()

function Read-Text($p) { return [System.IO.File]::ReadAllText($p) }
function Save-Text($p, $t) { [System.IO.File]::WriteAllText($p, $t, $utf8) }

$version = Get-BiSGuildVersion $root
$parts = Get-BiSGuildParts $root

# 1. every Lua file of ours ends with its version - first, because those files are in the hash
foreach ($p in $parts) {
    $path = Join-Path $root $p
    $text = Read-Text $path
    $line = "ns.parts[`"$p`"] = `"$version`""
    $re = 'ns\.parts\["' + [regex]::Escape($p) + '"\] = "[^"]*"'
    if ($text -notmatch $re) {
        $bad += "$p does not end with its ns.parts line"
        continue
    }
    $new = [regex]::Replace($text, $re, $line.Replace('$', '$$'))
    if ($new -ne $text) {
        if ($Check) { $bad += "$p says another version than $version" } else { Save-Text $path $new; Write-Host "$p : $version" }
    }
}

# 2. what ships, as git sees it
$NEVER = @("dev", "test", "CLAUDE.md", ".pkgmeta")
$raw = @(& git -C $root -c core.quotepath=off ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0 -or $raw.Count -eq 0) { throw "git could not list the addon's files" }
$files = @($raw | Where-Object {
    $top = ($_ -split "/")[0]
    -not ($NEVER -contains $top) -and -not $top.StartsWith(".") -and (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf)
} | Sort-Object -Unique)

$lines = Get-BiSGuildLines -Root $root -Files $files
$manifest = Get-BiSGuildText $lines
$fp = Get-BiSGuildHash $manifest
Write-Host "fingerprint : $fp  ($($lines.Count) files, BiSGuild $version)"

function Put($rel, $want, $label) {
    $path = Join-Path $root $rel
    $have = if (Test-Path -LiteralPath $path) { Read-Text $path } else { $null }
    if ($have -eq $want) { Write-Host "$rel : agrees"; return }
    if ($Check) { $script:bad += "$rel ($label) is out of date" } else { Save-Text $path $want; Write-Host "$rel : written" }
}

# 3. the manifest and the build file
Put "Tools\manifest.txt" $manifest "the list of files"
Put "Core\Build.lua" (Get-BiSGuildBuildLua $version $fp $parts) "what the copy says it is"

# 4. the CurseForge page: the number line in its check block
$cf = Join-Path $root "dev\cf-desc.md"
$text = Read-Text $cf
$re = '(?m)^(    Fingerprint   )[0-9A-F]{64}[ \t]*$'      # not \s*: that eats the blank line after it
if ($text -notmatch $re) { $bad += "dev\cf-desc.md has no '    Fingerprint   <64 hex>' line" }
else { Put "dev\cf-desc.md" ([regex]::Replace($text, $re, ('${1}' + $fp))) "the CurseForge page" }

# 5. the changelog's top entry: one line straight under its heading - ONLY IF IT ALREADY HAS ONE.
#    Arn, 16 Oct, before the first release: "dont put the fingerprint lets get approved first". The
#    line is opt-in per release: put "Fingerprint (SHA-256" under the heading and this keeps it right.
$cl = Join-Path $root "CHANGELOG.md"
$text = Read-Text $cl
$fline = "Fingerprint (SHA-256 of the whole addon, check it with the command on the CurseForge page): ``$fp``"
$m = [regex]::Match($text, '(?m)^## [^\n]*\n')
if (-not $m.Success) { $bad += "CHANGELOG.md has no ## entry" }
elseif ($text.Substring($m.Index + $m.Length) -notmatch '^\nFingerprint \(SHA-256') { Write-Host "CHANGELOG.md : no fingerprint line in the top entry - left alone" }
else {
    $at = $m.Index + $m.Length
    $rest = $text.Substring($at)
    $rest = [regex]::Replace($rest, '^\nFingerprint \(SHA-256[^\n]*\n', '')
    Put "CHANGELOG.md" ($text.Substring(0, $at) + "`n" + $fline + "`n" + $rest) "the release notes"
}

if ($bad.Count -gt 0) {
    Write-Host ""
    $bad | ForEach-Object { Write-Host "MISMATCH - $_" }
    Write-Host "Run .\Tools\stamp.ps1 (without -Check) and commit what it writes."
    exit 1
}
if (-not $Check) {
    Write-Host ""
    Write-Host "Paste dev\cf-desc.md's check block onto the CurseForge page when this version goes up."
}
