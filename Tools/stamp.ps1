<#
  BiSGuild :: Tools\stamp.ps1 - the fingerprint of logreport.ps1, into the places that publish it.

      .\Tools\stamp.ps1           recompute and write it
      .\Tools\stamp.ps1 -Check    say whether they still agree; exit 1 if not

  THE HASH IS ONLY WORTH SOMETHING WHERE IT IS PUBLISHED. Arn, 4 Oct 2026: "every time we update the
  addon right at top we put the hash... people can check that way that they are getting the right
  version", and "we put it in the curseforge description like this is the most up to date hash".

  That is the whole idea. A number inside the download proves nothing - whoever changed the script
  changes the number too. A number on the CurseForge page is one the person handing you a doctored
  copy does not control, so comparing the two is a real check.

  So this writes the hash in three places and they must agree:
    Core\Report.lua        P.SCRIPT_SHA - what the addon shows the player in game
    dev\cf-desc.md         the CurseForge page text, which is the published authority
    CHANGELOG.md           at the top of the release, so old versions can be checked too

  RUN IT WHENEVER logreport.ps1 CHANGES. The Lua suite can only check the shape of the constant -
  Lua 5.1 cannot compute SHA-256 - so nothing catches a forgotten restamp automatically yet.
#>
param([switch] $Check)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $PSScriptRoot "logreport.ps1"
if (-not (Test-Path -LiteralPath $script)) { throw "no logreport.ps1 beside this" }

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script).Hash
Write-Host "logreport.ps1 : $hash"

$lua = Join-Path $root "Core\Report.lua"
$text = [System.IO.File]::ReadAllText($lua)
$current = ([regex]'P\.SCRIPT_SHA = "([0-9A-Fa-f]{64})"').Match($text).Groups[1].Value

if ($Check) {
    if ($current -eq $hash) { Write-Host "Core\Report.lua : agrees"; exit 0 }
    Write-Host "Core\Report.lua : $current"
    Write-Host ""
    Write-Host "MISMATCH - logreport.ps1 changed and was not restamped. Run .\Tools\stamp.ps1"
    exit 1
}

if ($current -eq $hash) {
    Write-Host "Core\Report.lua : already correct"
} else {
    $text = $text -replace 'P\.SCRIPT_SHA = "[0-9A-Fa-f]{64}"', ('P.SCRIPT_SHA = "{0}"' -f $hash)
    [System.IO.File]::WriteAllText($lua, $text, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Core\Report.lua : updated"
}

Write-Host ""
Write-Host "Now put this on the CurseForge page and at the top of the release notes:"
Write-Host ""
Write-Host "  SHA-256 of Tools\logreport.ps1"
Write-Host "  $hash"
Write-Host ""
Write-Host "  Check yours with:  Get-FileHash -Algorithm SHA256 `"<addon>\Tools\logreport.ps1`""
