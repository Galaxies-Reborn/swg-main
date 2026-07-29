[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$itemRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/item"
$senatorPath = Join-Path $itemRoot "wearable/senator_crate.java"
$fryerPath = Join-Path $itemRoot "ice_cream_fryer/fryer.java"
foreach ($path in @($senatorPath, $fryerPath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required item source is missing: $path"
    }
}

$remainingReads = Get-ChildItem -LiteralPath $itemRoot -Recurse -Filter "*.java" |
    Select-String -SimpleMatch "getSkillTemplate("
if ($remainingReads)
{
    throw "Item scripts still contain getSkillTemplate reads: $($remainingReads.Path -join ', ')"
}

$senator = Get-Content -LiteralPath $senatorPath -Raw
foreach ($preserved in @(
    "grantSenatorClothes(player);",
    "int pSpecies = getSpecies(player);",
    "int pGender = getGender(player);"
))
{
    if (-not $senator.Contains($preserved))
    {
        throw "Senator-crate grant behavior was not preserved: $preserved"
    }
}

$fryer = Get-Content -LiteralPath $fryerPath -Raw
foreach ($retired in @(
    'startsWith("trader_0a")',
    "TRADER buff consumable",
    "DOMESTICS BUFF BEING CREATED"
))
{
    if ($fryer.Contains($retired))
    {
        throw "Later Trader-Domestics branch remains active: $retired"
    }
}
foreach ($preserved in @(
    "if (!currentBuff.equals(domesticBuff))",
    "setFourthIngredient(fryer, generatedItem, row)",
    "activateFryer(obj_id fryer, obj_id objPlayer)",
    "createEdible(obj_id fryer, obj_id player, int row)",
    "makeItemCRCArray()",
    "calcCurrentContentsCRC(obj_id fryer)",
    "decayFryer(obj_id fryer, obj_id user)",
    "repairFryerPopup(obj_id fryer, obj_id repairTool, obj_id player)"
))
{
    if (-not $fryer.Contains($preserved))
    {
        throw "Required fryer behavior was not preserved: $preserved"
    }
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-item-class-read-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in @{
        "senator_crate.java" = $senatorPath
        "fryer.java" = $fryerPath
    }.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Canonical source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/154-p14-item-class-read-retirement.patch"
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
Write-Host "Publish 14.1 item class-read retirement contract passed."
