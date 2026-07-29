[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$sourcePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/gcw_city_pylon.java"
$source = Get-Content -LiteralPath $sourcePath -Raw
$start = $source.IndexOf("public int OnObjectMenuSelect")
$end = $source.LastIndexOf("`n}")
if ($start -lt 0 -or $end -le $start)
{
    throw "Could not isolate GCW pylon construction surface."
}
$surface = $source.Substring($start, $end - $start)
foreach ($retired in @(
    "getSkillTemplate(",
    "getProfessionName(",
    'buff.applyBuff(player, "gcw_fatigue")',
    'profession.equals("trader")'
))
{
    if ($surface.Contains($retired))
    {
        throw "NGE GCW pylon behavior remains: $retired"
    }
}
foreach ($required in @(
    'buff.applyBuffWithStackCount(player, "gcw_fatigue", 5);',
    "completed += bestToolValue;",
    "groundquests.sendSignal(player, gcw.GCW_CONSTRUCTION_SIGNAL",
    "trial.addNonInstanceFactionParticipant(player, self);",
    "gcw.gcwInvasionCreditForCrafting(player);",
    "startConstructionAttempt(self, player);"
))
{
    if (-not $surface.Contains($required))
    {
        throw "Required neutral pylon behavior is missing: $required"
    }
}
if (([regex]::Matches($surface, [regex]::Escape("completed += bestToolValue;"))).Count -ne 1)
{
    throw "Construction value must be added exactly once."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-gcw-pylon-class-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(
        ([IO.File]::ReadAllText($sourcePath) -replace "`r`n", "`n"))
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
    if ($actual -ne $contract.buildEvidence.sourceSha256."gcw_city_pylon.java")
    {
        throw "Source evidence mismatch."
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/164-p14-gcw-pylon-class-retirement.patch"
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
Write-Host "Publish 14.1 GCW pylon class-retirement contract passed."
