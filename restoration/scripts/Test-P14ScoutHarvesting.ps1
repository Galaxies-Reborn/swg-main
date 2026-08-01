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
$droidHarvesterPath = Join-Path $scriptRoot "systems/crafting/droid/modules/harvest_module.java"
$skillsPath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$commandTablePath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"

foreach ($path in @($corpsePath, $aiCorpsePath, $outdoorsmanPath, $droidHarvesterPath,
    $skillsPath, $commandTablePath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.scout-harvest.source.$([IO.Path]::GetFileName($path))"
}

$corpse = Get-Content -LiteralPath $corpsePath -Raw
$aiCorpse = Get-Content -LiteralPath $aiCorpsePath -Raw
$outdoorsman = Get-Content -LiteralPath $outdoorsmanPath -Raw
$droidHarvester = Get-Content -LiteralPath $droidHarvesterPath -Raw

function Get-TabRows
{
    param([string]$Path)
    $lines = @(Get-Content -LiteralPath $Path)
    $header = [regex]::Split($lines[0], "`t")
    $rows = @{}
    foreach ($line in $lines | Select-Object -Skip 2)
    {
        if ([string]::IsNullOrEmpty($line)) { continue }
        $fields = [regex]::Split($line, "`t")
        $row = @{}
        for ($i = 0; $i -lt $header.Count; $i++)
        {
            $row[$header[$i]] = if ($i -lt $fields.Count) { $fields[$i] } else { "" }
        }
        $rows[$fields[0]] = $row
    }
    return $rows
}

$skills = Get-TabRows -Path $skillsPath
$commands = Get-TabRows -Path $commandTablePath

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
Assert-Contract ($droidHarvester.Contains("corpse.canPlayerHarvestCreature(player, false)") -and
    ([regex]::Matches($droidHarvester, [regex]::Escape("!corpse.canPlayerHarvestCreature(player, true)")).Count -eq 2) -and
    $droidHarvester.Contains("!corpse.canPlayerHarvestCreature(master, false)")) `
    "p14.scout-harvest.droid-paths-gated"
Assert-Contract ($commands.ContainsKey("harvestCorpse") -and
    $commands["harvestCorpse"]["characterAbility"] -eq "harvestCorpse") `
    "p14.scout-harvest.native-command-requires-scout-ability"
Assert-Contract ($skills.ContainsKey("outdoors_scout_novice") -and
    $skills["outdoors_scout_novice"]["COMMANDS"].Trim('"').Split(',') -contains "harvestCorpse" -and
    $skills["outdoors_scout_novice"]["SKILL_MODS"].Trim('"').Split(',') -contains "creature_harvesting=15") `
    "p14.scout-harvest.novice-scout-grants-ability-and-mod"

$species = @("bothan", "human", "moncal", "rodian", "trandoshan", "twilek",
    "wookiee", "zabrak", "ithorian", "sullustan")
$speciesAreClean = $true
foreach ($name in $species)
{
    $rowName = "species_$name"
    $speciesAreClean = $speciesAreClean -and $skills.ContainsKey($rowName) -and
        $skills[$rowName]["SKILL_MODS"] -notmatch '(^|,)creature_harvesting(=|,|$)' -and
        $skills[$rowName]["COMMANDS"] -notmatch '(^|,)harvestCorpse(,|$)'
}
Assert-Contract $speciesAreClean "p14.scout-harvest.species-do-not-grant-harvesting"

if ($failures.Count -gt 0)
{
    throw "Publish 14 Scout harvesting contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14 Scout harvesting contract passed."
