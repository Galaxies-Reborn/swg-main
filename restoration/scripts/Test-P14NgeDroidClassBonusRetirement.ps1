[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$craftingPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/craftinglib.java"
$petPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/pet_lib.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_droid_class_bonus_retirement_fixture.java"
$crafting = Get-Content -LiteralPath $craftingPath -Raw
$pet = Get-Content -LiteralPath $petPath -Raw
$surface = $crafting + "`n" + $pet
foreach ($retired in @(
    "getSkillTemplate(",
    "craftinglib.isTrader(",
    "public static boolean isTrader(",
    "profession.equals(`"trader`")",
    "playerLevel >= 30",
    "playerLevel >= 60",
    "return 90;"
))
{
    if ($surface.Contains($retired))
    {
        throw "NGE droid class bonus remains: $retired"
    }
}
foreach ($required in @(
    "return modulePotency > 0 ? 1 : 0;",
    "if (level > 60)",
    "public static int getDroidCapLevel",
    "return 60;"
))
{
    if (-not $pet.Contains($required))
    {
        throw "Neutral droid behavior is missing: $required"
    }
}
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf))
{
    throw "Droid class-bonus fixture is missing."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-nge-droid-class-bonus-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in @{
        "craftinglib.java" = $craftingPath
        "pet_lib.java" = $petPath
        "precu_droid_class_bonus_retirement_fixture.java" = $fixturePath
    }.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Canonical source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/156-p14-nge-droid-class-bonus-retirement.patch"
    $patchText = [IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"
    $patchBytes = [Text.Encoding]::UTF8.GetBytes($patchText)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $patchHash = ([BitConverter]::ToString($sha.ComputeHash($patchBytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($patchBytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $patchHash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Canonical overlay evidence mismatch."
    }
}
Write-Host "Publish 14.1 NGE droid class-bonus retirement contract passed."
