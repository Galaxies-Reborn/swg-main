param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3FlushingShotTwo)) -Raw | ConvertFrom-Json
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
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M285 source: $path" }
$command = @(Rows $paths.command | Where-Object commandName -ceq "flushingShot2")
Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq "flushingShot2" -and $command[0].defaultPriority -ceq "normal" -and $command[0].defaultTime -ceq "1.5" -and $command[0].executeTime -ceq "1.5" -and $command[0].'L:kneeling' -ceq "1" -and $command[0].'L:prone' -ceq "1" -and $command[0].'S:berserk' -ceq "0" -and $command[0].target -ceq "other" -and $command[0].targetType -ceq "optional" -and $command[0].commandGroup -ceq "391413347" -and $command[0].addToCombatQueue -ceq "1" -and $command[0].validWeapon -ceq "RIFLE") "flushingShot2 command row drifted"
$owners = @(Rows $paths.skills | Where-Object { [string]$_.COMMANDS -match "(^|,)flushingShot2(,|$)" })
Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_rifleman_ability_03" -and $owners[0].SKILLS_REQUIRED -ceq "combat_rifleman_ability_02") "flushingShot2 owner drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -ceq "flushingShot2")
Assert ($combat.Count -eq 1 -and $combat[0].percentAddFromWeapon -ceq "4.0" -and $combat[0].attackType -ceq "CONE" -and $combat[0].maxRange -ceq "64" -and $combat[0].coneWidth -ceq "15" -and $combat[0].animDefault -ceq "fire_area" -and $combat[0].anim_rifle -ceq "fire_area" -and $combat[0].weaponType -ceq "RIFLE" -and $combat[0].specialLine -ceq "rifleman") "flushingShot2 combat row drifted"
$override = @(Rows $paths.override | Where-Object actionName -ceq "flushingShot2")
Assert ($override.Count -eq 1 -and $override[0].healthCostMultiplier -ceq "0.5" -and $override[0].actionCostMultiplier -ceq "0.5" -and $override[0].mindCostMultiplier -ceq "2.0" -and $override[0].targetPool -ceq "RANDOM" -and $override[0].speedMultiplier -ceq "2.0" -and $override[0].accuracyBonus -ceq "5" -and $override[0].animationType -ceq "INTENSITY" -and $override[0].stateEffect1 -ceq "STUN" -and $override[0].stateChance1 -ceq "100" -and $override[0].stateDuration1 -ceq "35" -and $override[0].stateDefense1 -ceq "stun_defense" -and $override[0].stateJediDefense1 -ceq "jedi_state_defense" -and $override[0].stateResistance1 -ceq "resistance_states" -and $override[0].stateEffect2 -ceq "POSTURE_UP" -and $override[0].stateChance2 -ceq "100" -and $override[0].stateDefense2 -ceq "posture_change_up_defense") "flushingShot2 ordered effects drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -ceq "flushingShot2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "flushingvolley") "flushingShot2 spam drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains('public int flushingShot2(') -and $actions.Contains('"flushingShot2", self, target')) "flushingShot2 dispatcher missing"
foreach ($token in @('FLUSHING_SHOT_TWO_COMMAND', 'ORIGINAL_FLUSHING_SHOT_TWO_COMMAND', 'flushingShotTwoCanPerform=', 'flushingShotTwoHealthCost=', 'flushingShotTwoDamageMultiplier=')) { Assert ($fixture.Contains($token)) "M285 fixture token missing: $token" }
$overlay = Join-Path $restorationRoot "patches/dsrc/283-p14-core3-flushing-shot-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M285 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M285 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M285 build evidence failed"
    Assert ([string]$contract.buildEvidence.cleanApplyCheck -ceq "passed") "M285 clean apply missing"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M285 runtime evidence failed"
    Assert ([string]$contract.runtimeEvidence.firstAttack.stun.result -ceq "APPLIED") "M285 STUN application missing"
    Assert ([string]$contract.runtimeEvidence.firstAttack.postureUp.result -ceq "APPLIED") "M285 posture application missing"
    Assert ([string]$contract.runtimeEvidence.recoveryAttack.postureResult -ceq "RECOVERY") "M285 posture recovery missing"
    Assert ([bool]$contract.runtimeEvidence.expiry.nativeStunCleared -and [bool]$contract.runtimeEvidence.expiry.stunBuffCleared) "M285 STUN expiry missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.diagnosticEvidenceSurvived) "M285 persistence missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) "M285 cleanup is not idempotent"
}
Write-Host "Publish 14.1 Core3 flushingShot2 contract passed."

