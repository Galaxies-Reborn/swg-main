param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PolearmMasterAttack)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M315 source: $path"
}
$command = @(Rows $paths.command | Where-Object commandName -CEQ "polearmHit3")
Assert ($command.Count -eq 1) "polearmHit3 command row missing or duplicated"
$command = $command[0]
Assert ($command.scriptHook -ceq "polearmHit3" -and
    $command.characterAbility -ceq "polearmHit3" -and
    $command.failScriptHook -ceq "failSpecialAttack" -and
    $command.defaultPriority -ceq "normal" -and
    $command.defaultTime -ceq "1.5" -and $command.executeTime -ceq "1.5" -and
    $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
    $command.commandGroup -ceq "391413347" -and
    $command.addToCombatQueue -ceq "1" -and
    $command.validWeapon -ceq "POLEARM") "polearmHit3 command row drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -CEQ "polearmHit3")
$override = @(Rows $paths.overrides | Where-Object actionName -CEQ "polearmHit3")
$spam = @(Rows $paths.spam | Where-Object actionName -CEQ "polearmHit3")
Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "M315 combat tables are incomplete"
$combat = $combat[0]
$override = $override[0]
Assert ($combat.attackType -ceq "SINGLE_TARGET" -and $combat.maxRange -ceq "5" -and
    $combat.percentAddFromWeapon -ceq "4.0" -and $combat.animDefault -ceq "combo_5a" -and
    $combat.weaponType -ceq "POLEARM") "polearmHit3 combat row drifted"
Assert ($override.healthCostMultiplier -ceq "2.0" -and
    $override.actionCostMultiplier -ceq "1.5" -and
    $override.mindCostMultiplier -ceq "1.5" -and
    $override.targetPool -ceq "RANDOM" -and
    $override.speedMultiplier -ceq "2.5" -and
    $override.accuracyBonus -ceq "10" -and
    $override.animationType -ceq "INTENSITY" -and
    $override.postureDownChance -ceq "100" -and
    $override.stateEffect1 -ceq "STUN" -and
    $override.stateChance1 -ceq "75" -and
    $override.stateStrength1 -ceq "0" -and
    $override.stateDuration1 -ceq "45" -and
    $override.stateDefense1 -ceq "stun_defense" -and
    $override.stateJediDefense1 -ceq "jedi_state_defense" -and
    $override.stateResistance1 -ceq "resistance_states") "polearmHit3 override drifted"
Assert ($spam[0].combatSpam -ceq "bonebreaker") "polearmHit3 spam drifted"
$skills = Rows $paths.skills
$master = @($skills | Where-Object NAME -CEQ "combat_polearm_master")[0]
foreach ($required in @("combat_polearm_accuracy_04", "combat_polearm_speed_04",
    "combat_polearm_ability_04", "combat_polearm_support_04")) {
    Assert ([string]$master.SKILLS_REQUIRED -match "(^|,)$([regex]::Escape($required))(,|$)") "M315 master prerequisite missing: $required"
}
Assert ([string]$master.COMMANDS -match "(^|,)polearmHit3(,|$)") "M315 master command ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains("public int polearmHit3(") -and $actions.Contains('"polearmHit3"')) "polearmHit3 production hook drifted"
foreach ($token in @("POLEARM_MASTER", "ORIGINAL_POLEARM_MASTER",
    "POLEARM_HIT_THREE_COMMAND", "ORIGINAL_POLEARM_HIT_THREE_COMMAND",
    "armPolearmMaster", "polearmMaster=", "polearmHitThreeCommand=",
    "canPerformPolearmHitThree=", "isNaturalRegenerationRestored",
    "cleanupDefenderHealth=")) {
    Assert ($fixture.Contains($token)) "M315 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/313-p14-core3-polearm-master-attack.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M315 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M315 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.polearmMaster -and
        [int]$runtime.admission.canPerform.polearmHit3 -eq 0) "M315 admission proof missing"
    Assert ([string]$runtime.command.queueRemoval -ceq "Success" -and
        [int]$runtime.command.combatResult -eq 1 -and
        [int]$runtime.command.directDamage -gt 0 -and
        [string]$runtime.command.state.result -ceq "APPLIED" -and
        [string]$runtime.command.postureDown.result -ceq "APPLIED") "M315 execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.masterSurvived -and
        [bool]$runtime.persistence.commandSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientStunAbsent) "M315 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryPolearmSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M315 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 polearm master attack contract passed."
