[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-corvette-loot-admission.json") -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$relativePaths = @(
    "dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/corvette/loot.java",
    "dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/corvette/disk_loot.java",
    "dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/corvette/r2_loot.java"
)
$paths = $relativePaths | ForEach-Object { Join-Path $root $_ }
$sources = @{}
foreach ($path in $paths)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required Corvette source is missing: $path"
    }
    $sources[(Split-Path -Leaf $path)] = Get-Content -LiteralPath $path -Raw
}
$combined = ($sources.Values -join "`n")
foreach ($retired in @(
    "getSkillTemplate(",
    "startsWith(`"trader`")",
    "startsWith(`"entertainer`")",
    "no_trader_farming_allowed"
))
{
    if ($combined.Contains($retired))
    {
        throw "NGE Corvette class exclusion remains active: $retired"
    }
}
foreach ($source in $sources.Values)
{
    if (-not $source.Contains("if (item == menu_info_types.ITEM_OPEN)"))
    {
        throw "A Corvette ITEM_OPEN path was not preserved."
    }
}
if (-not $sources["loot.java"].Contains("spawnEnemies(self, player)") -or
    -not $sources["disk_loot.java"].Contains("setOwner(self, player)") -or
    -not $sources["r2_loot.java"].Contains('messageTo(self, "makeMoreLoot", null, 600, true)'))
{
    throw "A Corvette ownership, spawn, or respawn behavior was not preserved."
}

if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($path in $paths)
    {
        $leaf = Split-Path -Leaf $path
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.$leaf)
        {
            throw "Canonical source evidence mismatch for $leaf."
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/149-p14-corvette-loot-admission.patch"
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
Write-Host "Publish 14.1 Corvette loot-admission contract passed."
