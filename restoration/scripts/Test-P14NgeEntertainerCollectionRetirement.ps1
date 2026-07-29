[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$collectionPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/collection.java"
$handlerPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/buff/buff_handler.java"
$performancePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/performance.java"
foreach ($path in @($collectionPath, $handlerPath, $performancePath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required source is missing: $path"
    }
}

$collection = Get-Content -LiteralPath $collectionPath -Raw
$handler = Get-Content -LiteralPath $handlerPath -Raw
$retiredSurface = $collection + "`n" + $handler
foreach ($retired in @(
    "entertainerBuffCollection",
    "col_ent_invis_buff_tracker",
    "ENT_BUFF_COLLECTION_01",
    "UPDATED_ENTERTAINER_COLLECTION",
    "CONST_ROLL_CHANCE"
))
{
    if ($retiredSurface.Contains($retired))
    {
        throw "Later entertainer Collection surface remains active: $retired"
    }
}
if ($collection.Contains("getSkillTemplate("))
{
    throw "Collection library still contains an NGE class-template read."
}
foreach ($preserved in @(
    "buildabuffAddBuffHandler",
    'case "flush_with_success":',
    'addSkillModModifier(self, "buildabuff_" + effect',
    'messageTo(self, "setDisplayOnlyDefensiveMods"'
))
{
    if (-not $handler.Contains($preserved))
    {
        throw "Build-a-Buff core behavior was not preserved: $preserved"
    }
}
$performance = Get-Content -LiteralPath $performancePath -Raw
foreach ($preserved in @(
    "beginPrecuEntertainerBuffSession(",
    "activatePrecuEntertainerBuffSession(",
    "applyPrecuEntertainerAttributeBuff(",
    '"healing_dance_mind"',
    '"healing_music_mind"'
))
{
    if (-not $performance.Contains($preserved))
    {
        throw "Authentic entertainer session was not preserved: $preserved"
    }
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-nge-entertainer-collection-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in @{
        "collection.java" = $collectionPath
        "buff_handler.java" = $handlerPath
    }.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Canonical source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/155-p14-nge-entertainer-collection-retirement.patch"
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
Write-Host "Publish 14.1 NGE entertainer Collection retirement contract passed."
