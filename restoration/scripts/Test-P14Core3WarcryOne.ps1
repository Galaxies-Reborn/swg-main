param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3WarcryOne)) -Raw | ConvertFrom-Json
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
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M297 source: $path" }
$command = @(Rows $paths.command | Where-Object commandName -ceq "warcry1")
Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq "warcry1" -and $command[0].defaultPriority -ceq "normal" -and $command[0].defaultTime -ceq "1.5" -and $command[0].executeTime -ceq "1.5" -and $command[0].'L:kneeling' -ceq "1" -and $command[0].'L:prone' -ceq "1" -and $command[0].'S:berserk' -ceq "0" -and $command[0].target -ceq "other" -and $command[0].targetType -ceq "optional" -and $command[0].commandGroup -ceq "391413347" -and $command[0].maxRangeToTarget -ceq "0" -and $command[0].addToCombatQueue -ceq "1" -and $command[0].validWeapon -ceq "UNARMED") "warcry1 command row drifted"
$owners = @(Rows $paths.skills | Where-Object { [string]$_.COMMANDS -match "(^|,)warcry1(,|$)" })
Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_brawler_novice" -and [string]$owners[0].PARENT -ceq "combat_brawler") "warcry1 owner drifted"
Assert ([string]$owners[0].SKILL_MODS -notmatch "(^|,)warcry=") "warcry1 novice accuracy drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -ceq "warcry1")
Assert ($combat.Count -eq 1 -and $combat[0].percentAddFromWeapon -ceq "0.0" -and $combat[0].hitType -ceq "ATTACK" -and $combat[0].attackType -ceq "CONE" -and $combat[0].coneLength -ceq "24" -and $combat[0].coneWidth -ceq "15" -and $combat[0].maxRange -ceq "24" -and $combat[0].animDefault -ceq "warcry" -and $combat[0].anim_unarmed -ceq "warcry" -and $combat[0].weaponType -ceq "UNARMED" -and $combat[0].specialLine -ceq "brawler" -and $combat[0].triggerEffect -ceq "clienteffect/combat_special_attacker_warcry.cef" -and $combat[0].triggerEffectHardpoint -ceq "root") "warcry1 combat row drifted"
$override = @(Rows $paths.override | Where-Object actionName -ceq "warcry1")
Assert ($override.Count -eq 1 -and $override[0].healthCostMultiplier -ceq "0" -and $override[0].actionCostMultiplier -ceq "0" -and $override[0].mindCostMultiplier -ceq "0" -and $override[0].targetPool -ceq "NO_ATTRIBUTE" -and $override[0].speedMultiplier -ceq "1.0" -and $override[0].accuracyBonus -ceq "0" -and $override[0].accuracySkillMod -ceq "warcry" -and $override[0].animationType -ceq "NONE" -and $override[0].stateEffect1 -ceq "NEXT_ATTACK_DELAY" -and $override[0].stateChance1 -ceq "100" -and $override[0].stateStrength1 -ceq "0" -and $override[0].stateDuration1 -ceq "10" -and $override[0].stateDefense1 -ceq "warcry_defense" -and $override[0].stateJediDefense1 -ceq "jedi_state_defense" -and $override[0].stateResistance1 -ceq "resistance_states") "warcry1 overrides drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -ceq "warcry1")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "warcry") "warcry1 spam drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$base = Get-Content -LiteralPath $paths.base -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains('public int warcry1(') -and $actions.Contains('"warcry1", self, target')) "warcry1 dispatcher missing"
foreach ($token in @('PRECU_STATE_EFFECT_NEXT_ATTACK_DELAY = 7', 'PRECU_TARGET_POOL_NO_ATTRIBUTE = -2', 'PRECU_NEXT_ATTACK_DELAY_UNTIL', '"ARMED"')) { Assert ($base.Contains($token)) "M297 combat-base token missing: $token" }
foreach ($token in @('WARCRY_ONE_COMMAND', 'ORIGINAL_WARCRY_ONE_COMMAND', 'armWarcryOne', 'warcryOneCanPerform=', 'warcryOneHealthCost=', 'warcryOneDamageMultiplier=', 'warcryOneAccuracySkill=', 'nextAttackDelayRemaining=', 'nextAttackDelayResult=')) { Assert ($fixture.Contains($token)) "M297 fixture token missing: $token" }
$overlay = Join-Path $restorationRoot "patches/dsrc/295-p14-core3-warcry-one.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M297 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M297 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M297 build evidence failed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M297 runtime evidence failed"
    Assert ([int]$contract.runtimeEvidence.attack.damage -eq 0) "M297 zero-damage execution missing"
    Assert ([int]$contract.runtimeEvidence.attack.configuredPool -eq -2 -and [int]$contract.runtimeEvidence.attack.resolvedPool -eq -2) "M297 NO_ATTRIBUTE resolution missing"
    Assert ([string]$contract.runtimeEvidence.attack.stateEffect.result -ceq "APPLIED") "M297 delay application missing"
    Assert ([int]$contract.runtimeEvidence.attack.stateEffect.durationSeconds -eq 10) "M297 delay duration missing"
    Assert ([bool]$contract.runtimeEvidence.attack.stateEffect.defenderProductionBlocked) "M297 production delay enforcement missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.fullServerRestart) "M297 restart persistence missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.transientDelayAbsent) "M297 transient delay cleanup missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.postCleanupAbilityRejected) "M297 post-cleanup admission proof missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) "M297 cleanup idempotence missing"
}
Write-Output "Publish 14.1 Core3 warcry1 contract passed."
