param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3OneHandMasterAttack)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
$paths = @{
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    overrides = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M309 source: $path"
}
$command = @(Rows $paths.command | Where-Object commandName -CEQ "melee1hHit3")
Assert ($command.Count -eq 1) "melee1hHit3 command row missing or duplicated"
$command = $command[0]
Assert ($command.scriptHook -ceq "melee1hHit3" -and
    $command.characterAbility -ceq "melee1hHit3" -and
    $command.failScriptHook -ceq "failSpecialAttack" -and
    $command.defaultPriority -ceq "normal" -and
    $command.defaultTime -ceq "1.5" -and $command.executeTime -ceq "1.5" -and
    $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
    $command.commandGroup -ceq "391413347" -and
    $command.addToCombatQueue -ceq "1" -and
    $command.validWeapon -ceq "1HAND_MELEE") "melee1hHit3 command row drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -CEQ "melee1hHit3")
$override = @(Rows $paths.overrides | Where-Object actionName -CEQ "melee1hHit3")
$spam = @(Rows $paths.spam | Where-Object actionName -CEQ "melee1hHit3")
Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "M309 combat tables are incomplete"
$combat = $combat[0]
$override = $override[0]
Assert ($combat.attackType -ceq "SINGLE_TARGET" -and $combat.maxRange -ceq "3" -and
    $combat.percentAddFromWeapon -ceq "5.0" -and $combat.animDefault -ceq "combo_5a" -and
    $combat.weaponType -ceq "1HAND_MELEE") "melee1hHit3 combat row drifted"
Assert ($override.healthCostMultiplier -ceq "1" -and
    $override.actionCostMultiplier -ceq "1" -and
    $override.mindCostMultiplier -ceq "2" -and
    $override.targetPool -ceq "RANDOM" -and
    $override.speedMultiplier -ceq "2.25" -and
    $override.accuracyBonus -ceq "25" -and
    $override.animationType -ceq "INTENSITY" -and
    $override.stateEffect1 -ceq "BLIND" -and
    $override.stateChance1 -ceq "40" -and
    $override.stateStrength1 -ceq "0" -and
    $override.stateDuration1 -ceq "30" -and
    $override.stateDefense1 -ceq "blind_defense" -and
    $override.stateJediDefense1 -ceq "jedi_state_defense" -and
    $override.stateResistance1 -ceq "resistance_states") "melee1hHit3 override drifted"
Assert ($spam[0].combatSpam -ceq "chomok") "melee1hHit3 spam drifted"
$skills = Rows $paths.skills
$master = @($skills | Where-Object NAME -CEQ "combat_1hsword_master")[0]
foreach ($required in @("combat_1hsword_support_04", "combat_1hsword_accuracy_04",
    "combat_1hsword_speed_04", "combat_1hsword_ability_04")) {
    Assert ([string]$master.SKILLS_REQUIRED -match "(^|,)$([regex]::Escape($required))(,|$)") "M309 master prerequisite missing: $required"
}
Assert ([string]$master.COMMANDS -match "(^|,)melee1hHit3(,|$)") "M309 master command ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains("public int melee1hHit3(") -and $actions.Contains('"melee1hHit3"')) "melee1hHit3 production hook drifted"
foreach ($token in @("ONE_HAND_SWORD_MASTER", "ORIGINAL_ONE_HAND_SWORD_MASTER",
    "ONE_HAND_HIT_THREE_COMMAND", "ORIGINAL_ONE_HAND_HIT_THREE_COMMAND",
    "armOneHandMaster", "oneHandSwordMaster=", "oneHandHitThreeCommand=",
    "canPerformOneHandHitThree=")) {
    Assert ($fixture.Contains($token)) "M309 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/307-p14-core3-one-hand-master-attack.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M309 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M309 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.oneHandMaster -and
        [int]$runtime.admission.canPerform.melee1hHit3 -eq 0) "M309 admission proof missing"
    Assert ([string]$runtime.command.queueRemoval -ceq "Success" -and
        [int]$runtime.command.combatResult -eq 1 -and
        [int]$runtime.command.directDamage -gt 0 -and
        [string]$runtime.command.state.result -ceq "APPLIED") "M309 execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.masterSurvived -and
        [bool]$runtime.persistence.commandSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientBlindAbsent) "M309 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryOneHandSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M309 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 one-hand master attack contract passed."
