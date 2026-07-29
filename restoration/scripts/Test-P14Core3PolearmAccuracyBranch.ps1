param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PolearmAccuracyBranch)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M311 source: $path"
}
$commands = @("polearmStun2", "polearmSpinAttack2")
$commandRows = Rows $paths.command
foreach ($name in $commands) {
    $rows = @($commandRows | Where-Object commandName -CEQ $name)
    Assert ($rows.Count -eq 1) "$name command row missing or duplicated"
    $row = $rows[0]
    Assert ($row.scriptHook -ceq $name -and $row.characterAbility -ceq $name -and
        $row.failScriptHook -ceq "failSpecialAttack" -and
        $row.defaultPriority -ceq "normal" -and
        $row.defaultTime -ceq "1.5" -and $row.executeTime -ceq "1.5" -and
        $row.target -ceq "other" -and $row.targetType -ceq "optional" -and
        $row.commandGroup -ceq "391413347" -and
        $row.addToCombatQueue -ceq "1" -and
        $row.validWeapon -ceq "POLEARM") "$name command row drifted"
}
$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.overrides
$spamRows = Rows $paths.spam
function Assert-Combat([string]$Name, [string]$Damage, [string]$Animation,
    [string]$Health, [string]$Action, [string]$Mind, [string]$Speed,
    [string]$AnimationType, [string]$Effect, [string]$Chance,
    [string]$Duration, [string]$ExpectedSpam) {
    $combat = @($combatRows | Where-Object actionName -CEQ $Name)
    $override = @($overrideRows | Where-Object actionName -CEQ $Name)
    $spam = @($spamRows | Where-Object actionName -CEQ $Name)
    Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "$Name tables incomplete"
    $combat = $combat[0]
    $override = $override[0]
    Assert ($combat.attackType -ceq "AREA" -and $combat.coneLength -ceq "16" -and
        $combat.percentAddFromWeapon -ceq $Damage -and
        $combat.animDefault -ceq $Animation -and
        $combat.weaponType -ceq "POLEARM") "$Name combat row drifted"
    Assert ($override.healthCostMultiplier -ceq $Health -and
        $override.actionCostMultiplier -ceq $Action -and
        $override.mindCostMultiplier -ceq $Mind -and
        $override.targetPool -ceq "RANDOM" -and
        $override.speedMultiplier -ceq $Speed -and
        $override.accuracyBonus -ceq "10" -and
        $override.animationType -ceq $AnimationType -and
        $override.stateEffect1 -ceq $Effect -and
        $override.stateChance1 -ceq $Chance -and
        $override.stateStrength1 -ceq "0" -and
        $override.stateDuration1 -ceq $Duration -and
        $override.stateDefense1 -ceq ($Effect.ToLowerInvariant() + "_defense") -and
        $override.stateJediDefense1 -ceq "jedi_state_defense" -and
        $override.stateResistance1 -ceq "resistance_states") "$Name override drifted"
    Assert ($spam[0].combatSpam -ceq $ExpectedSpam) "$Name spam drifted"
}
Assert-Combat "polearmStun2" "2.0" "lower_posture_2hmelee_5" "1.5" "1.0" "1.0" "2.0" "" "STUN" "60" "30" "breathstealer"
Assert-Combat "polearmSpinAttack2" "2.5" "combo_2c" "2.0" "1.5" "1.5" "2.5" "INTENSITY" "DIZZY" "75" "25" "limbbreaker"
$skills = Rows $paths.skills
$accuracyOne = @($skills | Where-Object NAME -CEQ "combat_polearm_accuracy_01")[0]
$accuracyTwo = @($skills | Where-Object NAME -CEQ "combat_polearm_accuracy_02")[0]
$accuracyThree = @($skills | Where-Object NAME -CEQ "combat_polearm_accuracy_03")[0]
$accuracyFour = @($skills | Where-Object NAME -CEQ "combat_polearm_accuracy_04")[0]
Assert ([string]$accuracyOne.SKILLS_REQUIRED -ceq "combat_polearm_novice") "Accuracy I prerequisite drifted"
Assert ([string]$accuracyTwo.SKILLS_REQUIRED -ceq "combat_polearm_accuracy_01") "Accuracy II prerequisite drifted"
Assert ([string]$accuracyThree.SKILLS_REQUIRED -ceq "combat_polearm_accuracy_02") "Accuracy III prerequisite drifted"
Assert ([string]$accuracyFour.SKILLS_REQUIRED -ceq "combat_polearm_accuracy_03") "Accuracy IV prerequisite drifted"
Assert ([string]$accuracyOne.COMMANDS -match "(^|,)polearmStun2(,|$)") "polearmStun2 ownership drifted"
Assert ([string]$accuracyThree.COMMANDS -match "(^|,)polearmSpinAttack2(,|$)") "polearmSpinAttack2 ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $commands) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains('"' + $name + '"')) "$name production hook drifted"
}
foreach ($token in @("POLEARM_ACCURACY_ONE", "POLEARM_ACCURACY_FOUR",
    "ORIGINAL_POLEARM_ACCURACY_ONE", "ORIGINAL_POLEARM_ACCURACY_FOUR",
    "POLEARM_STUN_TWO_COMMAND", "POLEARM_SPIN_TWO_COMMAND",
    "ORIGINAL_POLEARM_STUN_TWO_COMMAND", "ORIGINAL_POLEARM_SPIN_TWO_COMMAND",
    "armPolearmAccuracy", "polearmAccuracyOne=", "polearmAccuracyFour=",
    "polearmStunTwoCommand=", "polearmSpinTwoCommand=",
    "canPerformPolearmStunTwo=", "canPerformPolearmSpinTwo=")) {
    Assert ($fixture.Contains($token)) "M311 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/309-p14-core3-polearm-accuracy-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M311 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M311 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.accuracyBranch -and
        [int]$runtime.admission.canPerform.polearmStun2 -eq 0 -and
        [int]$runtime.admission.canPerform.polearmSpinAttack2 -eq 0) "M311 admission proof missing"
    foreach ($name in $commands) {
        $execution = $runtime.commands.$name
        Assert ([string]$execution.queueRemoval -ceq "Success" -and
            [int]$execution.combatResult -eq 1 -and
            [int]$execution.directDamage -gt 0 -and
            [string]$execution.state.result -in @("APPLIED", "RESISTED")) "$name execution proof missing"
    }
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.accuracyBranchSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientStatesAbsent) "M311 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryAccuracyBranchAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M311 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 polearm accuracy branch contract passed."
