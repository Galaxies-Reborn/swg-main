param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3OneHandSpeedBranch)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M306 source: $path"
}
$names = @("melee1hHealthHit1", "melee1hSpinAttack2", "melee1hHealthHit2")
$commands = @(Rows $paths.command | Where-Object commandName -Cin $names)
Assert ($commands.Count -eq 3) "One-hand speed command branch is incomplete"
foreach ($command in $commands) {
    Assert ($command.scriptHook -ceq $command.commandName -and
        $command.characterAbility -ceq $command.commandName -and
        $command.failScriptHook -ceq "failSpecialAttack" -and
        $command.defaultPriority -ceq "normal" -and
        $command.defaultTime -ceq "1.5" -and $command.executeTime -ceq "1.5" -and
        $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
        $command.commandGroup -ceq "391413347" -and
        $command.addToCombatQueue -ceq "1" -and
        $command.validWeapon -ceq "1HAND_MELEE") "$($command.commandName) command row drifted"
}
$combat = @(Rows $paths.combat | Where-Object actionName -Cin $names)
$overrides = @(Rows $paths.overrides | Where-Object actionName -Cin $names)
$spam = @(Rows $paths.spam | Where-Object actionName -Cin $names)
Assert ($combat.Count -eq 3 -and $overrides.Count -eq 3 -and $spam.Count -eq 3) "M306 combat tables are incomplete"
$healthOne = @($combat | Where-Object actionName -CEQ "melee1hHealthHit1")[0]
$spinTwo = @($combat | Where-Object actionName -CEQ "melee1hSpinAttack2")[0]
$healthTwo = @($combat | Where-Object actionName -CEQ "melee1hHealthHit2")[0]
$healthOneOverride = @($overrides | Where-Object actionName -CEQ "melee1hHealthHit1")[0]
$spinTwoOverride = @($overrides | Where-Object actionName -CEQ "melee1hSpinAttack2")[0]
$healthTwoOverride = @($overrides | Where-Object actionName -CEQ "melee1hHealthHit2")[0]
Assert ($healthOne.attackType -ceq "SINGLE_TARGET" -and $healthOne.maxRange -ceq "3" -and
    $healthOne.percentAddFromWeapon -ceq "1.5" -and $healthOne.animDefault -ceq "counter_low_left" -and
    $healthOne.dotType -ceq "bleeding" -and $healthOne.dotIntensity -ceq "100" -and
    $healthOne.dotDuration -ceq "30" -and $healthOne.weaponType -ceq "1HAND_MELEE") "melee1hHealthHit1 combat row drifted"
Assert ($spinTwo.attackType -ceq "AREA" -and $spinTwo.coneLength -ceq "16" -and
    $spinTwo.maxRange -ceq "3" -and $spinTwo.percentAddFromWeapon -ceq "3.0" -and
    $spinTwo.animDefault -ceq "lower_posture_2hmelee_6" -and $spinTwo.weaponType -ceq "1HAND_MELEE") "melee1hSpinAttack2 combat row drifted"
Assert ($healthTwo.attackType -ceq "SINGLE_TARGET" -and $healthTwo.maxRange -ceq "3" -and
    $healthTwo.percentAddFromWeapon -ceq "3.0" -and $healthTwo.animDefault -ceq "combo_3c" -and
    $healthTwo.dotType -ceq "bleeding" -and $healthTwo.dotIntensity -ceq "100" -and
    $healthTwo.dotDuration -ceq "60" -and $healthTwo.weaponType -ceq "1HAND_MELEE") "melee1hHealthHit2 combat row drifted"
Assert ($healthOneOverride.healthCostMultiplier -ceq "0.5" -and
    $healthOneOverride.actionCostMultiplier -ceq "0.5" -and
    $healthOneOverride.mindCostMultiplier -ceq "0.625" -and
    $healthOneOverride.targetPool -ceq "HEALTH" -and
    $healthOneOverride.speedMultiplier -ceq "1.5" -and
    $healthOneOverride.dotAttribute -ceq "HEALTH") "melee1hHealthHit1 override drifted"
Assert ($spinTwoOverride.healthCostMultiplier -ceq "1.25" -and
    $spinTwoOverride.actionCostMultiplier -ceq "1.25" -and
    $spinTwoOverride.mindCostMultiplier -ceq "2.0" -and
    $spinTwoOverride.targetPool -ceq "RANDOM" -and
    $spinTwoOverride.speedMultiplier -ceq "2.5" -and
    $spinTwoOverride.stateEffect1 -ceq "BLIND" -and
    $spinTwoOverride.stateChance1 -ceq "40" -and
    $spinTwoOverride.stateDuration1 -ceq "30") "melee1hSpinAttack2 override drifted"
Assert ($healthTwoOverride.healthCostMultiplier -ceq "0.75" -and
    $healthTwoOverride.actionCostMultiplier -ceq "0.75" -and
    $healthTwoOverride.mindCostMultiplier -ceq "1.25" -and
    $healthTwoOverride.targetPool -ceq "HEALTH" -and
    $healthTwoOverride.speedMultiplier -ceq "2.0" -and
    $healthTwoOverride.dotAttribute -ceq "HEALTH") "melee1hHealthHit2 override drifted"
Assert (@($spam | Where-Object actionName -CEQ "melee1hHealthHit1")[0].combatSpam -ceq "shiim" -and
    @($spam | Where-Object actionName -CEQ "melee1hSpinAttack2")[0].combatSpam -ceq "blindspin" -and
    @($spam | Where-Object actionName -CEQ "melee1hHealthHit2")[0].combatSpam -ceq "shiimshiak") "M306 spam drifted"
$skills = Rows $paths.skills
$novice = @($skills | Where-Object NAME -CEQ "combat_1hsword_novice")[0]
$speedOne = @($skills | Where-Object NAME -CEQ "combat_1hsword_speed_01")[0]
$speedTwo = @($skills | Where-Object NAME -CEQ "combat_1hsword_speed_02")[0]
$speedThree = @($skills | Where-Object NAME -CEQ "combat_1hsword_speed_03")[0]
$speedFour = @($skills | Where-Object NAME -CEQ "combat_1hsword_speed_04")[0]
Assert ($novice.SKILLS_REQUIRED -ceq "combat_brawler_1handmelee_04" -and
    $speedOne.SKILLS_REQUIRED -ceq "combat_1hsword_novice" -and
    [string]$speedOne.COMMANDS -match "(^|,)melee1hHealthHit1(,|$)" -and
    $speedTwo.SKILLS_REQUIRED -ceq "combat_1hsword_speed_01" -and
    $speedThree.SKILLS_REQUIRED -ceq "combat_1hsword_speed_02" -and
    [string]$speedThree.COMMANDS -match "(^|,)melee1hSpinAttack2(,|$)" -and
    $speedFour.SKILLS_REQUIRED -ceq "combat_1hsword_speed_03" -and
    [string]$speedFour.COMMANDS -match "(^|,)melee1hHealthHit2(,|$)") "M306 ownership chain drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $names) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains("`"$name`"")) "$name production hook drifted"
}
foreach ($token in @("ONE_HAND_SWORD_SPEED_ONE", "ONE_HAND_SWORD_SPEED_TWO",
    "ONE_HAND_SWORD_SPEED_THREE", "ONE_HAND_SWORD_SPEED_FOUR",
    "ONE_HAND_HEALTH_HIT_ONE_COMMAND", "ONE_HAND_SPIN_ATTACK_TWO_COMMAND",
    "ONE_HAND_HEALTH_HIT_TWO_COMMAND", "armOneHandSpeed",
    "oneHandHealthHitOneCanPerform=", "oneHandSpinAttackTwoCanPerform=",
    "oneHandHealthHitTwoCanPerform=")) {
    Assert ($fixture.Contains($token)) "M306 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/304-p14-core3-one-hand-speed-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M306 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M306 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.oneHandSpeedFour -and
        [int]$runtime.admission.canPerform.melee1hHealthHit1 -eq 0 -and
        [int]$runtime.admission.canPerform.melee1hSpinAttack2 -eq 0 -and
        [int]$runtime.admission.canPerform.melee1hHealthHit2 -eq 0) "M306 admission proof missing"
    foreach ($name in $names) {
        $execution = $runtime.commands.$name
        Assert ([string]$execution.queueRemoval -ceq "Success" -and
            [int]$execution.combatResult -eq 1 -and
            [int]$execution.directDamage -gt 0) "$name execution proof missing"
    }
    Assert ([int]$runtime.commands.melee1hHealthHit1.bleedingDot.strength -eq 100 -and
        [int]$runtime.commands.melee1hHealthHit1.bleedingDot.attribute -eq 0 -and
        [int]$runtime.commands.melee1hHealthHit2.bleedingDot.strength -eq 100 -and
        [int]$runtime.commands.melee1hHealthHit2.bleedingDot.attribute -eq 0 -and
        [string]$runtime.commands.melee1hSpinAttack2.attackType -ceq "AREA" -and
        [int]$runtime.commands.melee1hSpinAttack2.areaRange -eq 16 -and
        [int]$runtime.commands.melee1hSpinAttack2.state.type -eq 2 -and
        [string]$runtime.commands.melee1hSpinAttack2.state.result -ceq "APPLIED") "M306 combat semantics proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientBlindAbsent -and
        [bool]$runtime.persistence.transientBleedingAbsent) "M306 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryOneHandSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M306 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 one-hand speed branch contract passed."
