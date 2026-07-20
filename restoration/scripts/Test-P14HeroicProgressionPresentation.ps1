[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$relativeFiles = [ordered]@{
    "tusken_controller.java" = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/heroic/tusken/tusken_controller.java"
    "axkva_controller.java" = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/heroic/axkva_min/axkva_controller.java"
    "sd_controller.java" = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/heroic/star_destroyer/sd_controller.java"
    "ig88.java" = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/heroic/ig88/ig88.java"
    "exar_controller.java" = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/heroic/exar_kun/exar_controller.java"
    "echo_controller.java" = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/heroic/echo_base/echo_controller.java"
}
$texts = [ordered]@{}
foreach ($entry in $relativeFiles.GetEnumerator())
{
    $texts[$entry.Key] = Get-Content -LiteralPath (Join-Path $root $entry.Value) -Raw
}
$surface = ($texts.Values -join "`n")
foreach ($retired in @("getSkillTemplate(", "getProfessionName(", "profession is "))
{
    if ($surface.Contains($retired))
    {
        throw "NGE Heroic presentation remains: $retired"
    }
}
$neutralCount = ([regex]::Matches(
    $surface,
    "progression is Publish 14\.1 skills\.")).Count
if ($neutralCount -ne 7)
{
    throw "Expected seven neutral Heroic progression labels; found $neutralCount."
}
$awardCount = ([regex]::Matches($surface, '"handleAwardtoken"')).Count
if ($awardCount -ne 7)
{
    throw "Expected seven preserved Heroic token-award calls; found $awardCount."
}
foreach ($required in @(
    "instance.setClock(",
    "trial.setDungeonCleanOutTimer(",
    "winSuiDisplay(players,",
    "Players earned "
))
{
    if (-not $surface.Contains($required))
    {
        throw "Required Heroic behavior is missing: $required"
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-heroic-progression-presentation.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $relativeFiles.GetEnumerator())
    {
        $path = Join-Path $root $entry.Value
        $bytes = [Text.Encoding]::UTF8.GetBytes(
            ([IO.File]::ReadAllText($path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try
        {
            $actual = ([BitConverter]::ToString(
                $sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
        }
        finally
        {
            $sha.Dispose()
        }
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/162-p14-heroic-progression-presentation.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha.Dispose()
    }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $hash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Heroic progression-presentation contract passed."
