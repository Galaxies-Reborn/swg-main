param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3TwoHandMasterAttack)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M320 source: $path"
}
$command = @(Rows $paths.command | Where-Object commandName -CEQ "melee2hHit3")
Assert ($command.Count -eq 1) "melee2hHit3 command row missing or duplicated"
$command = $command[0]
Assert ($command.scriptHook -ceq "melee2hHit3" -and
    $command.characterAbility -ceq "melee2hHit3" -and
    $command.failScriptHook -ceq "failSpecialAttack" -and
    $command.defaultPriority -ceq "normal" -and
    $command.defaultTime -ceq "1.5" -and $command.executeTime -ceq "1.5" -and
    $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
    $command.maxRangeToTarget -ceq "0" -and $command.commandGroup -ceq "391413347" -and
    $command.addToCombatQueue -ceq "1" -and
    $command.validWeapon -ceq "2HAND_MELEE") "melee2hHit3 command row drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -CEQ "melee2hHit3")
$override = @(Rows $paths.overrides | Where-Object actionName -CEQ "melee2hHit3")
$spam = @(Rows $paths.spam | Where-Object actionName -CEQ "melee2hHit3")
Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "M320 combat tables are incomplete"
$combat = $combat[0]
$override = $override[0]
Assert ($combat.attackType -ceq "SINGLE_TARGET" -and $combat.maxRange -ceq "3" -and
    $combat.percentAddFromWeapon -ceq "4.0" -and $combat.animDefault -ceq "combo_4a" -and
    $combat.weaponType -ceq "2HAND_MELEE") "melee2hHit3 combat row drifted"
Assert ($override.healthCostMultiplier -ceq "1.25" -and
    $override.actionCostMultiplier -ceq "2" -and
    $override.mindCostMultiplier -ceq "1.25" -and
    $override.targetPool -ceq "RANDOM" -and $override.speedMultiplier -ceq "2.5" -and
    $override.accuracyBonus -ceq "10" -and $override.animationType -ceq "INTENSITY" -and
    $override.postureDownChance -ceq "0" -and $override.stateEffect1 -ceq "DIZZY" -and
    $override.stateChance1 -ceq "50" -and $override.stateStrength1 -ceq "0" -and
    $override.stateDuration1 -ceq "30" -and $override.stateDefense1 -ceq "dizzy_defense" -and
    $override.stateJediDefense1 -ceq "jedi_state_defense" -and
    $override.stateResistance1 -ceq "resistance_states") "melee2hHit3 override drifted"
Assert ($spam[0].combatSpam -ceq "viciousstrike") "melee2hHit3 spam drifted"
$master = @(Rows $paths.skills | Where-Object NAME -CEQ "combat_2hsword_master")
Assert ($master.Count -eq 1) "combat_2hsword_master row missing or duplicated"
$master = $master[0]
foreach ($required in @("combat_2hsword_accuracy_04", "combat_2hsword_speed_04",
    "combat_2hsword_ability_04", "combat_2hsword_support_04")) {
    Assert ([string]$master.SKILLS_REQUIRED -match "(^|,)$([regex]::Escape($required))(,|$)") "M320 master prerequisite missing: $required"
}
Assert ([string]$master.COMMANDS -match "(^|,)melee2hHit3(,|$)") "M320 master command ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains("public int melee2hHit3(") -and $actions.Contains('"melee2hHit3"')) "melee2hHit3 production hook drifted"
foreach ($token in @("TWO_HAND_SWORD_MASTER", "ORIGINAL_TWO_HAND_SWORD_MASTER",
    "TWO_HAND_HIT_THREE_COMMAND", "ORIGINAL_TWO_HAND_HIT_THREE_COMMAND",
    "armTwoHandMaster", "twoHandSwordMaster=", "twoHandHitThreeCommand=",
    "twoHandHitThreeCanPerform=")) {
    Assert ($fixture.Contains($token)) "M320 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/318-p14-core3-two-hand-master-attack.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M320 overlay hash drifted"
foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties) {
    $pathKey = switch ([string]$entry.Name) {
        "combat_actions.java" { "actions" }
        "precu_headshot1_fixture.java" { "fixture" }
        "command_table.tab" { "command" }
        "skills.tab" { "skills" }
        "combat_data.tab" { "combat" }
        "precu_combat_overrides.tab" { "overrides" }
        "precu_combat_spam.tab" { "spam" }
        default { throw "Unexpected M320 source hash key: $($entry.Name)" }
    }
    Assert ([string]$entry.Value -ceq (Sha $paths[$pathKey])) "M320 source hash drifted: $($entry.Name)"
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M320 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and [bool]$runtime.admission.accuracyFour -and
        [bool]$runtime.admission.speedFour -and [bool]$runtime.admission.abilityFour -and
        [bool]$runtime.admission.supportFour -and [bool]$runtime.admission.twoHandSwordMaster -and
        [int]$runtime.admission.canPerform -eq 0 -and [bool]$runtime.admission.clientWeaponStatus.satisfies) "M320 admission proof missing"
    Assert ([string]$runtime.command.queueStatus -ceq "Success" -and [int]$runtime.command.combatResult -eq 1 -and
        [int]$runtime.command.directDamage -gt 0 -and [string]$runtime.command.configuredPool -ceq "RANDOM" -and
        [string]$runtime.command.combatSpam -ceq "viciousstrike_hit" -and
        [string]$runtime.command.animation -ceq "combo_4a_medium" -and
        [string]$runtime.command.state.type -ceq "DIZZY" -and
        @("APPLIED", "RESISTED") -ccontains [string]$runtime.command.state.result) "M320 execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and [bool]$runtime.persistence.allTerminalBranchesSurvived -and
        [bool]$runtime.persistence.masterSurvived -and [bool]$runtime.persistence.commandSurvived -and
        [bool]$runtime.persistence.canPerformSurvived -and [bool]$runtime.persistence.weaponSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and [bool]$runtime.persistence.transientDizzyAbsent -and
        [string]$runtime.persistence.postRestartExecution.queueStatus -ceq "Success" -and
        [int]$runtime.persistence.postRestartExecution.directDamage -gt 0) "M320 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.identityBoundSnapshotsRestored -and [bool]$runtime.cleanup.temporaryTerminalBranchesAbsent -and
        [bool]$runtime.cleanup.temporaryMasterAbsent -and [bool]$runtime.cleanup.temporaryCommandAbsent -and
        [bool]$runtime.cleanup.fixtureWeaponAbsent -and -not [bool]$runtime.cleanup.postCleanupClientWeaponSatisfies -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability" -and
        [bool]$runtime.isolatedClientsStopped -and [int]$runtime.connectionServerCount -eq 1) "M320 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 two-hand master attack contract passed."
