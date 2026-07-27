param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3MarksmanTumbleFamily)) -Raw | ConvertFrom-Json
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
    base = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M303 source: $path"
}
$names = @("tumbleToProne", "tumbleToKneeling", "tumbleToStanding")
$commands = @(Rows $paths.command | Where-Object commandName -Cin $names)
Assert ($commands.Count -eq 3) "Marksman tumble command family is incomplete"
foreach ($command in $commands) {
    Assert ($command.scriptHook -ceq $command.commandName -and
        $command.characterAbility -ceq $command.commandName -and
        $command.failScriptHook -ceq "failSpecialAttack" -and
        $command.defaultPriority -ceq "normal" -and
        $command.defaultTime -ceq "3" -and $command.executeTime -ceq "3" -and
        $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
        $command.commandGroup -ceq "-560185247" -and
        $command.addToCombatQueue -ceq "1" -and
        $command.validWeapon -ceq "ALL") "$($command.commandName) command row drifted"
    foreach ($field in @("L:standing", "L:walking", "L:running", "L:kneeling", "L:prone",
        "L:blocking", "S:combat", "S:peace", "S:aiming", "S:tumbling")) {
        Assert ($command.$field -ceq "1") "$($command.commandName) $field state drifted"
    }
    foreach ($field in @("L:sneaking", "L:climbingStationary", "L:climbing", "L:hovering",
        "L:flying", "L:knockedDown", "L:incapacitated", "L:dead", "R:cover", "S:cover",
        "S:alert", "S:frozen", "S:swimming", "S:ridingMount", "S:pilotingShip")) {
        Assert ($command.$field -ceq "0") "$($command.commandName) $field state drifted"
    }
}
$skills = Rows $paths.skills
$support = @($skills | Where-Object NAME -CEQ "combat_marksman_support_02")[0]
Assert ($support.PARENT -ceq "combat_marksman_support_01" -and
    $support.SKILLS_REQUIRED -ceq "combat_marksman_support_01" -and
    [string]$support.COMMANDS -match "(^|,)tumbleToProne(,|$)" -and
    [string]$support.COMMANDS -match "(^|,)tumbleToKneeling(,|$)" -and
    [string]$support.COMMANDS -match "(^|,)tumbleToStanding(,|$)" -and
    [string]$support.SKILL_MODS -match "(^|,)melee_defense=2(,|$)" -and
    [string]$support.SKILL_MODS -match "(^|,)aim=10(,|$)") "Marksman support ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$base = Get-Content -LiteralPath $paths.base -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $names) {
    Assert ($actions.Contains("public int $name(") -and
        $actions.Contains("`"$name`"")) "$name production hook drifted"
}
foreach ($token in @("calculatePrecuTumbleActionCost", "performPrecuTumble", "100.0f",
    "QUICKNESS", "POSTURE_PRONE", "POSTURE_CROUCHED", "POSTURE_UPRIGHT", "tumble_facing",
    "STATE_DIZZY", "STATE_TUMBLING", "tum_prone", "tum_kneel", "tum_standing",
    "tumble.actionCost", "tumble.meleeDefenseAfter", "tumble.rangedDefenseAfter",
    "tumble.modifiersApplied", "tumble.meleeDefenseBonus", "tumble.rangedDefenseBonus",
    "tumble.initialState", "tumble.buffSeconds", "tumble.expired")) {
    Assert ($actions.Contains($token)) "M303 production token missing: $token"
}
foreach ($token in @("PRECU_TUMBLE_MELEE_MODIFIER", "PRECU_TUMBLE_RANGED_MODIFIER")) {
    Assert ($base.Contains($token)) "M303 combat-base token missing: $token"
}
foreach ($token in @("TUMBLE_TO_PRONE_COMMAND", "TUMBLE_TO_KNEELING_COMMAND",
    "TUMBLE_TO_STANDING_COMMAND", "ORIGINAL_SUPPORT_TWO", "armMarksmanTumble",
    "canPerformTumbleToProne=", "canPerformTumbleToKneeling=", "canPerformTumbleToStanding=",
    "tumbleMeleeModifierPresent=", "tumbleRangedModifierPresent=",
    "cleanup.marksmanTumbleSkills", "cleanup.marksmanTumbleCommands")) {
    Assert ($fixture.Contains($token)) "M303 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/301-p14-core3-marksman-tumble-family.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M303 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M303 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.marksmanSupportTwo -and
        [int]$runtime.admission.canPerform.tumbleToProne -eq 1 -and
        [int]$runtime.admission.canPerform.tumbleToKneeling -eq 1 -and
        [int]$runtime.admission.canPerform.tumbleToStanding -eq 1) "M303 admission proof missing"
    foreach ($name in $names) {
        $execution = $runtime.commands.$name
        Assert ([string]$execution.queueRemoval -ceq "Success" -and
            [string]$execution.result -ceq "SUCCESS" -and
            [int]$execution.actionBefore - [int]$execution.actionAfter -eq [int]$execution.actionCost -and
            [bool]$execution.modifiersApplied -and
            [int]$execution.meleeDefenseBonus -eq 50 -and
            [int]$execution.rangedDefenseBonus -eq 50 -and
            [int]$execution.initialState -eq 1 -and
            [int]$execution.expired -eq 1) "$name execution proof missing"
    }
    Assert ([int]$runtime.commands.tumbleToProne.endPosture -eq 2 -and
        [int]$runtime.commands.tumbleToKneeling.endPosture -eq 1 -and
        [int]$runtime.commands.tumbleToStanding.endPosture -eq 0) "M303 posture sequence proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientModifiersAbsent -and
        [bool]$runtime.persistence.tumblingStateAbsent) "M303 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.originalMarksmanOwnershipRestored -and
        [bool]$runtime.cleanup.originalCommandsRestored -and
        [bool]$runtime.cleanup.postCleanupOriginalAbilityRetained -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Success") "M303 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 Marksman tumble family contract passed."
