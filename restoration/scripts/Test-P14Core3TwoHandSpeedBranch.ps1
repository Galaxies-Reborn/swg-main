param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3TwoHandSpeedBranch)) -Raw | ConvertFrom-Json
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
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    overrides = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M317 source: $path"
}
$specs = @(
    @{ Name = "melee2hHeadHit2"; Owner = "combat_2hsword_speed_01"; Damage = "2.5"; Speed = "1.75"; Health = "1"; Action = "1.5"; Mind = "1"; Spam = "scalpstrike" },
    @{ Name = "melee2hHeadHit3"; Owner = "combat_2hsword_speed_03"; Damage = "3.5"; Speed = "2.25"; Health = "1.5"; Action = "2"; Mind = "1.5"; Spam = "scalpslam" }
)
$commandRows = Rows $paths.command
$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.overrides
$spamRows = Rows $paths.spam
foreach ($spec in $specs) {
    $name = [string]$spec.Name
    $command = @($commandRows | Where-Object commandName -CEQ $name)
    $combat = @($combatRows | Where-Object actionName -CEQ $name)
    $override = @($overrideRows | Where-Object actionName -CEQ $name)
    $spam = @($spamRows | Where-Object actionName -CEQ $name)
    Assert ($command.Count -eq 1 -and $combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "$name tables incomplete"
    $command = $command[0]
    $combat = $combat[0]
    $override = $override[0]
    Assert ($command.scriptHook -ceq $name -and $command.characterAbility -ceq $name -and
        $command.failScriptHook -ceq "failSpecialAttack" -and
        $command.defaultPriority -ceq "normal" -and
        $command.defaultTime -ceq [string]$spec.Speed -and $command.executeTime -ceq "1.5" -and
        $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
        $command.commandGroup -ceq "391413347" -and $command.addToCombatQueue -ceq "1" -and
        $command.validWeapon -ceq "2HAND_MELEE") "$name command row drifted"
    Assert ($combat.attackType -ceq "SINGLE_TARGET" -and $combat.maxRange -ceq "3" -and
        $combat.percentAddFromWeapon -ceq [string]$spec.Damage -and
        $combat.animDefault -ceq "combo_2d" -and $combat.weaponType -ceq "2HAND_MELEE") "$name combat row drifted"
    Assert ($override.healthCostMultiplier -ceq [string]$spec.Health -and
        $override.actionCostMultiplier -ceq [string]$spec.Action -and
        $override.mindCostMultiplier -ceq [string]$spec.Mind -and
        $override.targetPool -ceq "MIND" -and
        $override.speedMultiplier -ceq [string]$spec.Speed -and
        $override.accuracyBonus -ceq "10" -and
        $override.animationType -ceq "INTENSITY") "$name override drifted"
    Assert ($spam[0].combatSpam -ceq [string]$spec.Spam) "$name spam drifted"
}
$skills = Rows $paths.skills
$skillSpecs = @(
    @{ Name = "combat_2hsword_speed_01"; Requires = "combat_2hsword_novice"; Command = "melee2hHeadHit2" },
    @{ Name = "combat_2hsword_speed_02"; Requires = "combat_2hsword_speed_01"; Command = "" },
    @{ Name = "combat_2hsword_speed_03"; Requires = "combat_2hsword_speed_02"; Command = "melee2hHeadHit3" },
    @{ Name = "combat_2hsword_speed_04"; Requires = "combat_2hsword_speed_03"; Command = "" }
)
foreach ($spec in $skillSpecs) {
    $row = @($skills | Where-Object NAME -CEQ $spec.Name)
    Assert ($row.Count -eq 1) "$($spec.Name) row missing or duplicated"
    Assert ([string]$row[0].SKILLS_REQUIRED -ceq [string]$spec.Requires) "$($spec.Name) prerequisite drifted"
    if ([string]$spec.Command) {
        Assert ([string]$row[0].COMMANDS -match ("(^|,)" + [regex]::Escape([string]$spec.Command) + "(,|$)")) "$($spec.Command) ownership drifted"
    }
}
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @(
    "TWO_HAND_SWORD_SPEED_ONE", "TWO_HAND_SWORD_SPEED_FOUR",
    "ORIGINAL_TWO_HAND_SWORD_SPEED_ONE", "ORIGINAL_TWO_HAND_SWORD_SPEED_FOUR",
    "TWO_HAND_HEAD_TWO_COMMAND", "TWO_HAND_HEAD_THREE_COMMAND",
    "ORIGINAL_TWO_HAND_HEAD_TWO_COMMAND", "ORIGINAL_TWO_HAND_HEAD_THREE_COMMAND",
    "armTwoHandSpeed", "twoHandSwordSpeedOne=", "twoHandSwordSpeedFour=",
    "twoHandHeadTwoCommand=", "twoHandHeadThreeCommand=",
    "canPerformTwoHandHeadTwo=", "canPerformTwoHandHeadThree="
)) {
    Assert ($fixture.Contains($token)) "M317 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/315-p14-core3-two-hand-speed-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M317 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M317 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.twoHandSwordNovice -and
        [bool]$runtime.admission.twoHandSwordAccuracyFour -and
        [bool]$runtime.admission.speedOne -and [bool]$runtime.admission.speedTwo -and
        [bool]$runtime.admission.speedThree -and [bool]$runtime.admission.speedFour -and
        [int]$runtime.admission.canPerform.melee2hHeadHit2 -eq 0 -and
        [int]$runtime.admission.canPerform.melee2hHeadHit3 -eq 0) "M317 admission proof missing"
    Assert (@($runtime.commands).Count -eq 2) "M317 command proof count drifted"
    foreach ($spec in $specs) {
        $execution = @($runtime.commands | Where-Object name -CEQ $spec.Name)[0]
        Assert ([string]$execution.queueRemoval -ceq "Success" -and
            [int]$execution.combatResult -eq 1 -and [int]$execution.directDamage -gt 0 -and
            [string]$execution.configuredPool -ceq "MIND" -and
            [string]$execution.resolvedPool -ceq "MIND" -and
            [int]$execution.hitLocation -eq 1 -and
            [string]$execution.combatSpam -ceq ([string]$spec.Spam + "_hit") -and
            [string]$execution.animation -ceq "combo_2d_medium" -and
            [int]$execution.animationType -eq 2) "$($spec.Name) execution proof missing"
    }
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.speedBranchSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.canPerformSurvived -and
        [bool]$runtime.persistence.weaponSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [string]$runtime.persistence.postRestartExecution.queueRemoval -ceq "Success" -and
        [int]$runtime.persistence.postRestartExecution.combatResult -eq 1 -and
        [int]$runtime.persistence.postRestartExecution.directDamage -gt 0) "M317 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporarySpeedBranchAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.fixtureWeaponAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability" -and
        -not [bool]$runtime.cleanup.postCleanupClientWeaponSatisfies) "M317 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 two-hand speed branch contract passed."
