param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3IntimidateTwo)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Rows([string]$Path) { $lines = Get-Content -LiteralPath $Path; $header = $lines[0] -split "`t", -1; @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header) }
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
$paths = @{
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    base = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M296 source: $path" }
$command = @(Rows $paths.command | Where-Object commandName -ceq "intimidate2")
Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq "intimidate2" -and $command[0].defaultPriority -ceq "normal" -and $command[0].defaultTime -ceq "1.5" -and $command[0].executeTime -ceq "1.5" -and $command[0].'L:kneeling' -ceq "1" -and $command[0].'L:prone' -ceq "1" -and $command[0].'S:berserk' -ceq "0" -and $command[0].target -ceq "other" -and $command[0].targetType -ceq "optional" -and $command[0].commandGroup -ceq "391413347" -and $command[0].maxRangeToTarget -ceq "0" -and $command[0].addToCombatQueue -ceq "1" -and $command[0].validWeapon -ceq "UNARMED") "intimidate2 command row drifted"
$owners = @(Rows $paths.skills | Where-Object { [string]$_.COMMANDS -match "(^|,)intimidate2(,|$)" })
Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_brawler_master" -and [string]$owners[0].PARENT -ceq "combat_brawler") "intimidate2 owner drifted"
Assert ([string]$owners[0].SKILL_MODS -match "(^|,)intimidate=20(,|$)") "intimidate2 master accuracy drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -ceq "intimidate2")
Assert ($combat.Count -eq 1 -and $combat[0].percentAddFromWeapon -ceq "0.0" -and $combat[0].hitType -ceq "ATTACK" -and $combat[0].attackType -ceq "SINGLE_TARGET" -and $combat[0].maxRange -ceq "24" -and $combat[0].animDefault -ceq "intimidate" -and $combat[0].anim_unarmed -ceq "intimidate" -and $combat[0].weaponType -ceq "UNARMED" -and $combat[0].specialLine -ceq "brawler" -and $combat[0].triggerEffect -ceq "clienteffect/combat_special_attacker_intimidate.cef" -and $combat[0].triggerEffectHardpoint -ceq "root") "intimidate2 combat row drifted"
$override = @(Rows $paths.override | Where-Object actionName -ceq "intimidate2")
Assert ($override.Count -eq 1 -and $override[0].healthCostMultiplier -ceq "0" -and $override[0].actionCostMultiplier -ceq "0" -and $override[0].mindCostMultiplier -ceq "0" -and $override[0].targetPool -ceq "NO_ATTRIBUTE" -and $override[0].speedMultiplier -ceq "1.0" -and $override[0].accuracyBonus -ceq "0" -and $override[0].accuracySkillMod -ceq "intimidate" -and $override[0].animationType -ceq "NONE" -and $override[0].stateEffect1 -ceq "INTIMIDATE" -and $override[0].stateChance1 -ceq "100" -and $override[0].stateStrength1 -ceq "0" -and $override[0].stateDuration1 -ceq "120") "intimidate2 overrides drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -ceq "intimidate2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "intim") "intimidate2 spam drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$base = Get-Content -LiteralPath $paths.base -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains('public int intimidate2(') -and $actions.Contains('"intimidate2", self, target')) "intimidate2 dispatcher missing"
foreach ($token in @('PRECU_STATE_EFFECT_INTIMIDATE = 6', 'PRECU_TARGET_POOL_NO_ATTRIBUTE = -2', 'STATE_INTIMIDATED', '"intimidate"')) { Assert ($base.Contains($token)) "M296 combat-base token missing: $token" }
foreach ($token in @('INTIMIDATE_TWO_COMMAND', 'ORIGINAL_INTIMIDATE_TWO_COMMAND', 'BRAWLER_MASTER', 'ORIGINAL_BRAWLER_MASTER', 'intimidateTwoCanPerform=', 'intimidateTwoHealthCost=', 'intimidateTwoDamageMultiplier=', 'intimidateTwoAccuracySkill=', 'defenderIntimidateState=', 'defenderIntimidateBuff=')) { Assert ($fixture.Contains($token)) "M296 fixture token missing: $token" }
$overlay = Join-Path $restorationRoot "patches/dsrc/294-p14-core3-intimidate-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M296 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M296 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M296 build evidence failed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M296 runtime evidence failed"
    Assert ([int]$contract.runtimeEvidence.attack.damage -eq 0) "M296 zero-damage execution missing"
    Assert ([int]$contract.runtimeEvidence.attack.configuredPool -eq -2 -and [int]$contract.runtimeEvidence.attack.resolvedPool -eq -2) "M296 NO_ATTRIBUTE resolution missing"
    Assert ([string]$contract.runtimeEvidence.attack.stateEffect.result -ceq "APPLIED") "M296 INTIMIDATE application missing"
    Assert ([int]$contract.runtimeEvidence.attack.stateEffect.durationSeconds -eq 120) "M296 INTIMIDATE duration missing"
    Assert ([int]$contract.runtimeEvidence.admission.intimidateAccuracySkill -eq 20) "M296 master accuracy missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.fullServerRestart) "M296 restart persistence missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.transientIntimidateAbsent) "M296 transient INTIMIDATE cleanup missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.postCleanupAbilityRejected) "M296 post-cleanup admission proof missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) "M296 cleanup idempotence missing"
}
Write-Output "Publish 14.1 Core3 intimidate2 contract passed."
