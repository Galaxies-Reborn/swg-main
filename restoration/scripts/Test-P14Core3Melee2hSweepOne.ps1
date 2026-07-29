param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3Melee2hSweepOne)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Rows([string]$Path) { $lines = Get-Content -LiteralPath $Path; $header = $lines[0] -split "`t", -1; @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header) }
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
$paths = @{
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M291 source: $path" }
$command = @(Rows $paths.command | Where-Object commandName -ceq "melee2hSweep1")
Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq "melee2hSweep1" -and $command[0].defaultPriority -ceq "normal" -and $command[0].defaultTime -ceq "1.5" -and $command[0].executeTime -ceq "1.5" -and $command[0].'L:kneeling' -ceq "1" -and $command[0].'L:prone' -ceq "1" -and $command[0].'S:berserk' -ceq "0" -and $command[0].target -ceq "other" -and $command[0].targetType -ceq "optional" -and $command[0].commandGroup -ceq "391413347" -and $command[0].maxRangeToTarget -ceq "0" -and $command[0].addToCombatQueue -ceq "1" -and $command[0].validWeapon -ceq "2HAND_MELEE") "melee2hSweep1 command row drifted"
$owners = @(Rows $paths.skills | Where-Object { [string]$_.COMMANDS -match "(^|,)melee2hSweep1(,|$)" })
Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_brawler_2handmelee_03" -and $owners[0].PARENT -ceq "combat_brawler_2handmelee_02") "melee2hSweep1 owner drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -ceq "melee2hSweep1")
Assert ($combat.Count -eq 1 -and $combat[0].percentAddFromWeapon -ceq "1.5" -and $combat[0].attackType -ceq "SINGLE_TARGET" -and $combat[0].maxRange -ceq "3" -and $combat[0].animDefault -ceq "lower_posture_2hmelee_3" -and $combat[0].anim_onehandmelee -ceq "" -and $combat[0].anim_twohandmelee -ceq "lower_posture_2hmelee_3" -and $combat[0].anim_polearm -ceq "" -and $combat[0].weaponType -ceq "2HAND_MELEE" -and $combat[0].specialLine -ceq "brawler") "melee2hSweep1 combat row drifted"
$override = @(Rows $paths.override | Where-Object actionName -ceq "melee2hSweep1")
Assert ($override.Count -eq 1 -and $override[0].healthCostMultiplier -ceq "0.75" -and $override[0].actionCostMultiplier -ceq "1.5" -and $override[0].mindCostMultiplier -ceq "0.75" -and $override[0].targetPool -ceq "RANDOM" -and $override[0].speedMultiplier -ceq "1.5" -and $override[0].accuracyBonus -ceq "10" -and $override[0].animationType -ceq "NONE" -and $override[0].postureDownChance -ceq "100") "melee2hSweep1 overrides drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -ceq "melee2hSweep1")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "sweep") "melee2hSweep1 spam drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains('public int melee2hSweep1(') -and $actions.Contains('"melee2hSweep1", self, target')) "melee2hSweep1 dispatcher missing"
foreach ($token in @('BRAWLER_TWO_HAND_ONE', 'BRAWLER_TWO_HAND_TWO', 'BRAWLER_TWO_HAND_THREE', 'TWO_HAND_SWEEP_ONE_COMMAND', 'ORIGINAL_TWO_HAND_SWEEP_ONE_COMMAND', 'twoHandSweepOneCanPerform=', 'twoHandSweepOneHealthCost=', 'twoHandSweepOneDamageMultiplier=')) { Assert ($fixture.Contains($token)) "M291 fixture token missing: $token" }
$overlay = Join-Path $restorationRoot "patches/dsrc/289-p14-core3-melee2h-sweep-one.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M291 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M291 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M291 build evidence failed"
    Assert ([string]$contract.buildEvidence.cleanApplyCheck -ceq "passed") "M291 clean apply missing"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M291 runtime evidence failed"
    Assert ([string]$contract.runtimeEvidence.firstAttack.postureDown.result -ceq "APPLIED") "M291 posture-down application missing"
    Assert ([string]$contract.runtimeEvidence.recoveryAttack.postureResult -ceq "RECOVERY") "M291 posture recovery missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.fullServerRestart) "M291 restart persistence missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) "M291 cleanup idempotence missing"
}
Write-Output "Publish 14.1 Core3 melee2hSweep1 contract passed."
