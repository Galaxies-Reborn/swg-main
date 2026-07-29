param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path

function Read-DataRows([string]$Path)
{
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0].Split("`t")
    return @($lines[2..($lines.Count - 1)] |
        ConvertFrom-Csv -Delimiter "`t" -Header $header)
}

$combatLibraryPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/combat.java"
$combatBasePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$skillsPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"

$library = Get-Content -LiteralPath $combatLibraryPath -Raw
$base = Get-Content -LiteralPath $combatBasePath -Raw
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$overrideRaw = Get-Content -LiteralPath $overridePath -Raw

foreach ($token in @(
    "PRECU_TARGET_POOL_RANDOM = 3",
    "int roll = rand(0, 100)",
    "if (roll <= 60)",
    "if (roll <= 95)",
    "return PRECU_TARGET_POOL_MIND"))
{
    if (-not $library.Contains($token)) { throw "RANDOM pool resolver drifted: $token" }
}

foreach ($token in @(
    "int precuResolvedTargetPool = actionData.precuTargetPool",
    "combat.resolvePrecuTargetPool(precuResolvedTargetPool)",
    "combat.selectPrecuHitLocationForPool(precuResolvedTargetPool)",
    "attacker, defender, hitData, precuResolvedTargetPool",
    "actionData,`r`n            precuResolvedTargetPool",
    '"targetPool.configured"',
    '"targetPool.resolved"'))
{
    $normalizedToken = $token.Replace("`r`n", "`n")
    $normalizedBase = $base.Replace("`r`n", "`n")
    if (-not $normalizedBase.Contains($normalizedToken)) {
        throw "Resolved-pool threading drifted: $token"
    }
}

if (-not $overrideRaw.Contains('"e(HEALTH=0,ACTION=1,MIND=2,RANDOM=3)[HEALTH]"'))
{
    throw "Pre-CU override schema does not admit RANDOM explicitly."
}

foreach ($token in @(
    "public int polearmSpinAttack1(",
    'combatStandardAction("polearmSpinAttack1"'))
{
    if (-not $actions.Contains($token)) { throw "Area command hook drifted: $token" }
}

$commandRows = Read-DataRows $commandPath
$combatRows = Read-DataRows $combatPath
$overrideRows = Read-DataRows $overridePath
$spamRows = Read-DataRows $spamPath
$skillRows = Read-DataRows $skillsPath

$command = @($commandRows | Where-Object commandName -ceq "polearmSpinAttack1")
if ($command.Count -ne 1 -or
    $command[0].scriptHook -cne "polearmSpinAttack1" -or
    $command[0].characterAbility -cne "polearmSpinAttack1" -or
    $command[0].validWeapon -cne "POLEARM" -or
    $command[0].addToCombatQueue -cne "1")
{
    throw "polearmSpinAttack1 command-table row drifted."
}

$combat = @($combatRows | Where-Object actionName -ceq "polearmSpinAttack1")
if ($combat.Count -ne 1 -or
    $combat[0].attackType -cne "AREA" -or
    $combat[0].coneLength -cne "16" -or
    $combat[0].percentAddFromWeapon -cne "1.5" -or
    $combat[0].animDefault -cne "attack_high_left_light_2" -or
    $combat[0].weaponType -cne "POLEARM")
{
    throw "polearmSpinAttack1 combat-data row drifted."
}

$override = @($overrideRows | Where-Object actionName -ceq "polearmSpinAttack1")
if ($override.Count -ne 1 -or
    $override[0].healthCostMultiplier -cne "1.5" -or
    $override[0].actionCostMultiplier -cne "1" -or
    $override[0].mindCostMultiplier -cne "1" -or
    $override[0].targetPool -cne "RANDOM" -or
    $override[0].speedMultiplier -cne "1.5" -or
    $override[0].accuracyBonus -cne "10")
{
    throw "polearmSpinAttack1 Core3 override row drifted."
}

$spam = @($spamRows | Where-Object actionName -ceq "polearmSpinAttack1")
if ($spam.Count -ne 1 -or $spam[0].combatSpam -cne "limbsmasher")
{
    throw "polearmSpinAttack1 combat-spam row drifted."
}

$skill = @($skillRows | Where-Object name -ceq "combat_brawler_polearm_04")
if ($skill.Count -ne 1 -or
    ([string]$skill[0].COMMANDS).Split(",") -cnotcontains "polearmSpinAttack1")
{
    throw "Authentic polearmSpinAttack1 skill owner drifted."
}

foreach ($token in @(
    'POLEARM_AREA_COMMAND = "polearmSpinAttack1"',
    "ORIGINAL_WOUNDS",
    "ORIGINAL_SHOCK",
    "restoreFixtureWounds(attacker)",
    "restoreFixtureWounds(defender)",
    "healWound(player, attribute, delta)",
    "setShockWound(player, originalShock)",
    "diagnosticTargetPoolConfigured",
    "diagnosticTargetPoolResolved"))
{
    if (-not $fixture.Contains($token)) { throw "Area fixture safety drifted: $token" }
}

if ($Expectation -eq "Ready")
{
    $contractPath =
        Join-Path $restorationRoot "contracts/p14-core3-random-area-combat.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.buildEvidence.javaCompile -ne "passed" -or
        $contract.buildEvidence.datatableCompile -ne "passed" -or
        $contract.buildEvidence.staticContract -ne "passed" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        $contract.runtimeEvidence.productionQueueAdmission -ne "passed" -or
        $contract.runtimeEvidence.serverRemovalStatus -ne "Success" -or
        $contract.runtimeEvidence.diagnosticConfiguredPool -ne 3 -or
        $contract.runtimeEvidence.diagnosticResolvedPool -notin @(0, 1, 2) -or
        $contract.runtimeEvidence.fixtureWoundAndShockRestoration -ne "passed" -or
        $contract.runtimeEvidence.fixtureCleanup -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Core3 RANDOM area-combat evidence is not ready."
    }
}

Write-Host "Publish 14.1 Core3 RANDOM area-combat contract passed."
