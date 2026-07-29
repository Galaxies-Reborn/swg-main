[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$files = [ordered]@{
    "tcg_vendor_contract.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/tcg/tcg_vendor_contract.java"
    "consume_relic_booster_pack.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/player_quest/consume_relic_booster_pack.java"
}
$tcg = Get-Content -LiteralPath (Join-Path $root $files["tcg_vendor_contract.java"]) -Raw
$chronicles = Get-Content -LiteralPath (Join-Path $root $files["consume_relic_booster_pack.java"]) -Raw
$surface = $tcg + "`n" + $chronicles
foreach ($retired in @(
    "getSkillTemplate(",
    'classTemplate.startsWith("trader")',
    'professionTemplate.startsWith("trader")',
    'professionTemplate.startsWith("entertainer")'
))
{
    if ($surface.Contains($retired))
    {
        throw "Later class-progression behavior remains: $retired"
    }
}
foreach ($required in @(
    "private static boolean isTcgVendorContractEnabled()",
    "private static boolean isChroniclesBoosterPackEnabled()"
))
{
    if (-not $surface.Contains($required))
    {
        throw "Retirement helper is missing: $required"
    }
}
if (([regex]::Matches($tcg, "if \(!isTcgVendorContractEnabled\(\)\)")).Count -ne 5)
{
    throw "Expected five guarded TCG entrypoints."
}
if (([regex]::Matches($chronicles, "if \(!isChroniclesBoosterPackEnabled\(\)\)")).Count -ne 3)
{
    throw "Expected three guarded Chronicles entrypoints."
}
foreach ($helper in @("isTcgVendorContractEnabled", "isChroniclesBoosterPackEnabled"))
{
    $start = $surface.IndexOf("private static boolean $helper()")
    $end = $surface.IndexOf("`n    }", $start)
    if ($start -lt 0 -or $end -le $start -or
        -not $surface.Substring($start, $end - $start).Contains("return false;"))
    {
        throw "$helper does not fail closed."
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-tcg-chronicles-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $files.GetEnumerator())
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
    $patchPath = Join-Path $restorationRoot "patches/dsrc/165-p14-tcg-chronicles-retirement.patch"
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
Write-Host "Publish 14.1 TCG/Chronicles retirement contract passed."
