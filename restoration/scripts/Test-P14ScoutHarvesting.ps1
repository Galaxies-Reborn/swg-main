[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param([bool]$Condition, [string]$Name)
    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$corpsePath = Join-Path $scriptRoot "library/corpse.java"
$aiCorpsePath = Join-Path $scriptRoot "corpse/ai_corpse.java"
$outdoorsmanPath = Join-Path $scriptRoot "player/skill/outdoorsman.java"

foreach ($path in @($corpsePath, $aiCorpsePath, $outdoorsmanPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.scout-harvest.source.$([IO.Path]::GetFileName($path))"
}

$corpse = Get-Content -LiteralPath $corpsePath -Raw
$aiCorpse = Get-Content -LiteralPath $aiCorpsePath -Raw
$outdoorsman = Get-Content -LiteralPath $outdoorsmanPath -Raw

Assert-Contract ($corpse.Contains('SKILL_NOVICE_SCOUT = "outdoors_scout_novice"')) `
    "p14.scout-harvest.exact-skill"
Assert-Contract ($corpse.Contains("public static boolean canPlayerHarvestCreature") -and
    $corpse.Contains("hasSkill(player, SKILL_NOVICE_SCOUT)")) `
    "p14.scout-harvest.shared-admission"
Assert-Contract ($corpse.Contains("if (!canPlayerHarvestCreature(player, true))") -and
    $corpse.Contains("public static boolean harvestCreatureCorpse")) `
    "p14.scout-harvest.extraction-fails-closed"
Assert-Contract ($aiCorpse.Contains("corpse.canPlayerHarvestCreature(player, false) && canHarvest") -and
    $aiCorpse.Contains("harvestMenuItem && !corpse.canPlayerHarvestCreature(player, true)")) `
    "p14.scout-harvest.menu-and-selection-gated"
Assert-Contract ($outdoorsman.Contains("!corpse.canPlayerHarvestCreature(self, true)")) `
    "p14.scout-harvest.command-gated"

if ($failures.Count -gt 0)
{
    throw "Publish 14 Scout harvesting contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14 Scout harvesting contract passed."
