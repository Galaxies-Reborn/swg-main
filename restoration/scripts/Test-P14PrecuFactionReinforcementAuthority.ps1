[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuFactionReinforcementAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$dataRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables"
$factionPerkPath = Join-Path $scriptRoot "library/faction_perk.java"
$skillPath = Join-Path $scriptRoot "library/skill.java"
$staticItemPath = Join-Path $scriptRoot "library/static_item.java"
$combatActionsPath = Join-Path $scriptRoot "systems/combat/combat_actions.java"
$commLinkPath = Join-Path $scriptRoot "item/gcw_buff_banner/pvp_lieutenant_comm_link.java"
$creaturesPath = Join-Path $dataRoot "mob/creatures.tab"
$masterItemPath = Join-Path $dataRoot "item/master_item/master_item.tab"
$gcwRewardsPath = Join-Path $dataRoot "npc/faction_recruiter/perk_inventory/gcw_rewards.tab"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { return "" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

$paths = @($factionPerkPath, $skillPath, $staticItemPath, $combatActionsPath,
    $commLinkPath, $creaturesPath, $masterItemPath, $gcwRewardsPath)
foreach ($path in $paths)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.faction-reinforcement.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$factionPerk = Get-Content -LiteralPath $factionPerkPath -Raw
$skillLibrary = Get-Content -LiteralPath $skillPath -Raw
$staticItem = Get-Content -LiteralPath $staticItemPath -Raw
$combatActions = Get-Content -LiteralPath $combatActionsPath -Raw
$commLink = Get-Content -LiteralPath $commLinkPath -Raw

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $factionPerkPath).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.faction-reinforcement.$($property.Name).authenticated"
}

$spawn = Get-BracedSurface $factionPerk "public static boolean spawnTroopers(obj_id player, String faction, int rank)"
$execute = Get-BracedSurface $factionPerk "public static boolean executeComlinkReinforcements"
$encounter = Get-BracedSurface $skillLibrary "public static int getPrecuEncounterDifficulty"
$action = Get-BracedSurface $combatActions "public int gcw_reward_comlink"
$menu = Get-BracedSurface $commLink "public int OnObjectMenuSelect"

Assert-Contract ($factionPerk.Contains("PRECU_COMM_LINK_MIN_RANK = 7") -and
    $factionPerk.Contains("PRECU_COMM_LINK_MAX_TEMPLATE_RANK = 12") -and
    $spawn.Contains("rank < PRECU_COMM_LINK_MIN_RANK")) `
    "p14.faction-reinforcement.rank-admission"
Assert-Contract ($spawn.Contains("pvpGetCurrentGcwRank(player)") -and
    $spawn.Contains("Math.min(rank, PRECU_COMM_LINK_MAX_TEMPLATE_RANK)") -and
    $spawn.Contains('"gcw_comm_link_reinforcement_" + faction + "_" + reinforcementRank')) `
    "p14.faction-reinforcement.restored-rank-and-authored-template"
Assert-Contract ($spawn.Contains("int atLevel = skill.getPrecuEncounterDifficulty(player);") -and
    $spawn.Contains("create.object(toSpawn, getLocation(player), atLevel)") -and
    -not $spawn.Contains("getLevel(")) `
    "p14.faction-reinforcement.precu-combat-difficulty"
Assert-Contract ($encounter.Contains("getPrecuCombatSkillScore(player)") -and
    -not $encounter.Contains("getLevel(")) `
    "p14.faction-reinforcement.skill-box-derived-adapter"

Assert-Contract ($menu.Contains("factions.isRebel(player)") -and
    $menu.Contains("factions.isImperial(player)") -and
    $menu.Contains("factions.isDeclared(player)") -and
    $menu.Contains("queueCommand(player, (-447180069)")) `
    "p14.faction-reinforcement.item-entrypoint-guards"
Assert-Contract ($action.Contains("faction_perk.executeComlinkReinforcements(self)") -and
    $execute.Contains("static_item.validateLevelRequired(player, comlink)") -and
    $execute.Contains("spawnTroopers(player)") -and
    $execute.Contains("COMM_COOLDOWN") -and
    $execute.Contains("world != player")) `
    "p14.faction-reinforcement.live-command-cooldown-and-indoor-path"

$levelValidator = Get-BracedSurface $staticItem "public static boolean validateLevelRequired(obj_id player, obj_id item)"
Assert-Contract ($levelValidator.Contains("return true;") -and
    -not $levelValidator.Contains("getLevel(")) `
    "p14.faction-reinforcement.retained-item-level-gate-inert"

$creatures = @(Import-Csv -LiteralPath $creaturesPath -Delimiter "`t" | Where-Object {
    $_.creatureName -match '^gcw_comm_link_reinforcement_(imperial|rebel)_(7|8|9|10|11|12)$'
})
$expectedNames = foreach ($faction in @("imperial", "rebel")) {
    foreach ($rank in 7..12) { "gcw_comm_link_reinforcement_${faction}_${rank}" }
}
$actualNames = @($creatures | ForEach-Object { [string]$_.creatureName } | Sort-Object)
Assert-Contract ($creatures.Count -eq [int]$contract.diagnosis.authoredReinforcementRows -and
    (@(Compare-Object -ReferenceObject ($expectedNames | Sort-Object) -DifferenceObject $actualNames).Count -eq 0)) `
    "p14.faction-reinforcement.authored-template-band"

$masterItems = @(Import-Csv -LiteralPath $masterItemPath -Delimiter "`t" | Where-Object {
    $_.name -match '^item_pvp_lieutenant_comm_link_(imperial|rebel)_reward_04_01$'
})
$rewardRows = @(Import-Csv -LiteralPath $gcwRewardsPath -Delimiter "`t" | Where-Object {
    $_.template -match '^static:item_pvp_lieutenant_comm_link_(imperial|rebel)_reward_04_01$'
})
Assert-Contract ($masterItems.Count -eq 2 -and $rewardRows.Count -eq 2 -and
    @($rewardRows | Where-Object { [int]$_.requiredGcwRank -eq 7 }).Count -eq 2) `
    "p14.faction-reinforcement.retained-items-and-rank-cost-rows"

$continuity = [ordered]@{
    skillLibrarySha256 = $skillPath
    staticItemLibrarySha256 = $staticItemPath
    combatActionsSha256 = $combatActionsPath
    commLinkItemScriptSha256 = $commLinkPath
    creatureTableSha256 = $creaturesPath
    masterItemTableSha256 = $masterItemPath
    gcwRewardsTableSha256 = $gcwRewardsPath
}
foreach ($name in $continuity.Keys)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $continuity[$name]).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.$name) "p14.faction-reinforcement.continuity.$name"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.faction-reinforcement.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.faction-reinforcement.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.faction-reinforcement.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.faction-reinforcement.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.faction-reinforcement.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU faction reinforcement authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU faction reinforcement authority contract passed."
