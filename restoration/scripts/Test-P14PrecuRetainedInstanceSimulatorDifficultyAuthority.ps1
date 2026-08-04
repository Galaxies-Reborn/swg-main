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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuRetainedInstanceSimulatorDifficultyAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$paths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $source ([string]$property.Value)
}
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

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.instance-simulator.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$entrance = Get-Content -LiteralPath $paths.meatlumpEntrance -Raw
$controller = Get-Content -LiteralPath $paths.meatlumpController -Raw
$simulator = Get-Content -LiteralPath $paths.targetSimulator -Raw
$targetDummy = Get-Content -LiteralPath $paths.targetDummyLibrary -Raw
$deed = Get-Content -LiteralPath $paths.targetControllerDeed -Raw
$skill = Get-Content -LiteralPath $paths.skillLibrary -Raw
$received = Get-BracedSurface $entrance "public int OnReceivedItem"
$instanceLevel = Get-BracedSurface $entrance "public int handleInstanceCombatLevel"
$scaleInstance = Get-BracedSurface $controller "public int setMtpInstanceCombatLevel"
$simulatorSetup = Get-BracedSurface $simulator "public int handleTargetCreatureSetUp"
$manualLevel = Get-BracedSurface $simulator "public int handleTargetDummyLevelSelect"
$manualDifficulty = Get-BracedSurface $simulator "public int handleTargetDummyDifficultySelect"
$encounterAdapter = Get-BracedSurface $skill "public static int getPrecuEncounterDifficulty"

Assert-Contract ($received.Contains("isPlayer(item)") -and
    $received.Contains("instance.getInstanceOwner(building) == item") -and
    $received.Contains('webster.put("playerCombatLevel", skill.getPrecuEncounterDifficulty(item))') -and
    -not $received.Contains("getLevel(item)")) `
    "p14.instance-simulator.meatlump-skill-box-authority"
Assert-Contract ($instanceLevel.Contains("instance.getInstanceOwner(building) != player") -and
    $instanceLevel.Contains('hasObjVar(levelControlObject, "mtp_instanceCombatLevel")') -and
    $instanceLevel.Contains("if (combatLevel < 65)") -and
    $instanceLevel.Contains("combatLevel = 65") -and
    $instanceLevel.Contains('messageTo(building, "setMtpInstanceCombatLevel"')) `
    "p14.instance-simulator.meatlump-floor-owner-and-controller-flow"
Assert-Contract ($scaleInstance.Contains("if (playerCombatLevel > 65)") -and
    $scaleInstance.Contains("create.INITIALIZE_CREATURE_DO_NOT_SCALE_OBJVAR") -and
    $scaleInstance.Contains("create.initializeCreature(thing, spawnName, creatureDict, playerCombatLevel)") -and
    $scaleInstance.Contains("ai_lib.BEHAVIOR_LOITER")) `
    "p14.instance-simulator.meatlump-hostile-reinitialization"

Assert-Contract ($simulatorSetup.Contains("int combatLevel = 50") -and
    $simulatorSetup.Contains("skill.getPrecuEncounterDifficulty(owner)") -and
    -not $simulatorSetup.Contains("getLevel(owner)") -and
    $simulatorSetup.IndexOf('hasObjVar(controller, "intCombatDifficulty")', [StringComparison]::Ordinal) -gt
        $simulatorSetup.IndexOf("skill.getPrecuEncounterDifficulty(owner)", [StringComparison]::Ordinal) -and
    $simulatorSetup.Contains("target_dummy.initializeTargetDummy(self, combatLevel, difficulty)")) `
    "p14.instance-simulator.target-default-and-persisted-override"
Assert-Contract ($manualLevel.Contains("level < 1 || level > 100") -and
    $manualLevel.Contains("target_dummy.initializeTargetDummy(self, level, difficulty)") -and
    $manualDifficulty.Contains("int combatLevel = getLevel(self)") -and
    $manualDifficulty.Contains("target_dummy.initializeTargetDummy(self, combatLevel, difficulty_selected)")) `
    "p14.instance-simulator.manual-and-npc-level-state-preserved"
Assert-Contract ($encounterAdapter.Contains("Math.max(1, getPrecuCombatSkillScore(player))") -and
    $skill.Contains("PRECU_COMBAT_SKILL_SCORE_MAX = 90")) `
    "p14.instance-simulator.authenticated-skill-box-adapter"

Assert-Contract ($deed.Contains("target_dummy.setTargetDummyOwner(self)") -and
    $deed.Contains("target_dummy.createTargetDummy(self, player)") -and
    $targetDummy.Contains("createTargetDummy") -and
    $targetDummy.Contains("npc = create.object(toCreate, createLoc)")) `
    "p14.instance-simulator.live-target-controller-path"
$targetDefinitions = @(Import-Csv -LiteralPath $paths.targetCreatureDefinitions -Delimiter "`t" | Where-Object {
    $_.creatureName -in @("tcg_target_creature_acklay", "tcg_target_dummy")
})
Assert-Contract ($targetDefinitions.Count -eq 2 -and
    @($targetDefinitions | Where-Object {
        $_.scripts -ne "systems.tcg.target_creature" -or $_.objvars -notmatch '(^|,)int:isTargetDummy=1(,|$)'
    }).Count -eq 0) "p14.instance-simulator.live-target-creature-definitions"
$masterItems = @(Import-Csv -LiteralPath $paths.masterItems -Delimiter "`t" | Where-Object {
    $_.name -in @("item_tcg_loot_reward_series1_target_creature",
        "item_tcg_loot_reward_series3_target_dummy")
})
Assert-Contract ($masterItems.Count -eq [int]$contract.diagnosis.retainedTargetControllerItems -and
    @($masterItems | Where-Object {
        $_.scripts -notmatch '(^|,)systems\.tcg\.target_creature_deed(,|$)'
    }).Count -eq 0) "p14.instance-simulator.retained-target-controller-items"

$buildout = Get-Content -LiteralPath $paths.meatlumpBuildout -Raw
$spawns = Get-Content -LiteralPath $paths.meatlumpSpawns -Raw
Assert-Contract ([regex]::Matches($buildout,
    [regex]::Escape("theme_park.meatlump.hideout.mtp_instance_entrance_cell")).Count -eq
    [int]$contract.diagnosis.activeMeatlumpEntranceBuildoutRows -and
    [regex]::Matches($spawns,
        [regex]::Escape("mtp_hideout_instance_entryb_controller.iff")).Count -eq 2) `
    "p14.instance-simulator.live-meatlump-buildout-and-controllers"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.instance-simulator.$($property.Name).authenticated"
}
$continuity = [ordered]@{
    skillLibrarySha256 = $paths.skillLibrary
    meatlumpControllerSha256 = $paths.meatlumpController
    targetDummyLibrarySha256 = $paths.targetDummyLibrary
    targetControllerDeedSha256 = $paths.targetControllerDeed
    targetCreatureDefinitionsSha256 = $paths.targetCreatureDefinitions
    meatlumpBuildoutSha256 = $paths.meatlumpBuildout
    meatlumpSpawnsSha256 = $paths.meatlumpSpawns
    masterItemsSha256 = $paths.masterItems
}
foreach ($name in $continuity.Keys)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $continuity[$name]).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.$name) "p14.instance-simulator.continuity.$name"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.instance-simulator.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.instance-simulator.direct-source-pin"
    Assert-Contract (@($contract.buildEvidence.compiledClassSha256.PSObject.Properties |
        Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0 -and
        [bool]$contract.runtimeEvidence.compiledClassesPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.instance-simulator.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.instance-simulator.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.instance-simulator.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU retained instance/simulator difficulty authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU retained instance/simulator difficulty authority contract passed."
