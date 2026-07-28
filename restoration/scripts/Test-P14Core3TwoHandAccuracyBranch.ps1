param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3TwoHandAccuracyBranch)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M316 source: $path"
}
$commands = @("melee2hArea1", "melee2hArea2", "melee2hArea3")
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
        $row.validWeapon -ceq "2HAND_MELEE") "$name command row drifted"
}
$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.overrides
$spamRows = Rows $paths.spam
function Assert-Area([string]$Name, [string]$Damage, [string]$Animation,
    [string]$Health, [string]$Action, [string]$Mind, [string]$Speed,
    [string]$ExpectedSpam, [bool]$Terminal) {
    $combat = @($combatRows | Where-Object actionName -CEQ $Name)
    $override = @($overrideRows | Where-Object actionName -CEQ $Name)
    $spam = @($spamRows | Where-Object actionName -CEQ $Name)
    Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "$Name tables incomplete"
    $combat = $combat[0]
    $override = $override[0]
    Assert ($combat.attackType -ceq "AREA" -and $combat.coneLength -ceq "16" -and
        $combat.maxRange -ceq "5" -and $combat.percentAddFromWeapon -ceq $Damage -and
        $combat.animDefault -ceq $Animation -and
        $combat.weaponType -ceq "2HAND_MELEE") "$Name combat row drifted"
    Assert ($override.healthCostMultiplier -ceq $Health -and
        $override.actionCostMultiplier -ceq $Action -and
        $override.mindCostMultiplier -ceq $Mind -and
        $override.targetPool -ceq "RANDOM" -and
        $override.speedMultiplier -ceq $Speed -and
        $override.accuracyBonus -ceq "10" -and
        $override.animationType -ceq "NONE" -and
        $override.postureDownChance -ceq "100") "$Name override drifted"
    if ($Terminal) {
        Assert ($override.stateEffect1 -ceq "DIZZY" -and
            $override.stateChance1 -ceq "30" -and
            $override.stateStrength1 -ceq "0" -and
            $override.stateDuration1 -ceq "30" -and
            $override.stateDefense1 -ceq "dizzy_defense" -and
            $override.stateJediDefense1 -ceq "jedi_state_defense" -and
            $override.stateResistance1 -ceq "resistance_states") "$Name terminal state drifted"
    }
    else {
        Assert ([string]::IsNullOrEmpty([string]$override.stateEffect1)) "$Name gained an unexpected state"
    }
    Assert ($spam[0].combatSpam -ceq $ExpectedSpam) "$Name spam drifted"
}
Assert-Area "melee2hArea1" "2.0" "lower_posture_2hmelee_2" "0.5" "1.5" "0.50" "1.5" "descendingstrike" $false
Assert-Area "melee2hArea2" "3.0" "lower_posture_2hmelee_4" "1" "2" "1" "2" "descendingslam" $false
Assert-Area "melee2hArea3" "3.0" "lower_posture_2hmelee_5" "1.5" "2.5" "1.5" "2.5" "domination" $true
$skills = Rows $paths.skills
$novice = @($skills | Where-Object NAME -CEQ "combat_2hsword_novice")[0]
$accuracyOne = @($skills | Where-Object NAME -CEQ "combat_2hsword_accuracy_01")[0]
$accuracyTwo = @($skills | Where-Object NAME -CEQ "combat_2hsword_accuracy_02")[0]
$accuracyThree = @($skills | Where-Object NAME -CEQ "combat_2hsword_accuracy_03")[0]
$accuracyFour = @($skills | Where-Object NAME -CEQ "combat_2hsword_accuracy_04")[0]
Assert ([string]$novice.SKILLS_REQUIRED -ceq "combat_brawler_2handmelee_04") "Two-hand novice prerequisite drifted"
Assert ([string]$accuracyOne.SKILLS_REQUIRED -ceq "combat_2hsword_novice") "Accuracy I prerequisite drifted"
Assert ([string]$accuracyTwo.SKILLS_REQUIRED -ceq "combat_2hsword_accuracy_01") "Accuracy II prerequisite drifted"
Assert ([string]$accuracyThree.SKILLS_REQUIRED -ceq "combat_2hsword_accuracy_02") "Accuracy III prerequisite drifted"
Assert ([string]$accuracyFour.SKILLS_REQUIRED -ceq "combat_2hsword_accuracy_03") "Accuracy IV prerequisite drifted"
Assert ([string]$accuracyOne.COMMANDS -match "(^|,)melee2hArea1(,|$)") "melee2hArea1 ownership drifted"
Assert ([string]$accuracyTwo.COMMANDS -match "(^|,)melee2hArea2(,|$)") "melee2hArea2 ownership drifted"
Assert ([string]$accuracyFour.COMMANDS -match "(^|,)melee2hArea3(,|$)") "melee2hArea3 ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $commands) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains('"' + $name + '"')) "$name production hook drifted"
}
foreach ($token in @("TWO_HAND_SWORD_ACCURACY_ONE", "TWO_HAND_SWORD_ACCURACY_FOUR",
    "ORIGINAL_TWO_HAND_SWORD_ACCURACY_ONE", "ORIGINAL_TWO_HAND_SWORD_ACCURACY_FOUR",
    "TWO_HAND_ACCURACY_AREA_ONE_COMMAND", "TWO_HAND_ACCURACY_AREA_THREE_COMMAND",
    "ORIGINAL_TWO_HAND_ACCURACY_AREA_ONE_COMMAND", "ORIGINAL_TWO_HAND_ACCURACY_AREA_THREE_COMMAND",
    "armTwoHandAccuracy", "twoHandSwordAccuracyOne=", "twoHandSwordAccuracyFour=",
    "twoHandAccuracyAreaOneCommand=", "twoHandAccuracyAreaThreeCommand=",
    "canPerformTwoHandAccuracyAreaOne=", "canPerformTwoHandAccuracyAreaThree=",
    "The master box depends on every polearm branch")) {
    Assert ($fixture.Contains($token)) "M316 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/314-p14-core3-two-hand-accuracy-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M316 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M316 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.brawlerTwoHandFour -and
        [bool]$runtime.admission.twoHandSwordNovice -and
        [bool]$runtime.admission.twoHandSwordAccuracyOne -and
        [bool]$runtime.admission.twoHandSwordAccuracyTwo -and
        [bool]$runtime.admission.twoHandSwordAccuracyThree -and
        [bool]$runtime.admission.twoHandSwordAccuracyFour -and
        [int]$runtime.admission.canPerform.melee2hArea1 -eq 0 -and
        [int]$runtime.admission.canPerform.melee2hArea2 -eq 0 -and
        [int]$runtime.admission.canPerform.melee2hArea3 -eq 0) "M316 admission proof missing"
    Assert (@($runtime.commands).Count -eq 3) "M316 command proof count drifted"
    foreach ($name in $commands) {
        $execution = @($runtime.commands | Where-Object name -CEQ $name)[0]
        Assert ([string]$execution.queueRemoval -ceq "Success" -and
            [int]$execution.combatResult -eq 1 -and
            [int]$execution.directDamage -gt 0 -and
            [string]$execution.configuredPool -ceq "RANDOM" -and
            [string]$execution.postureDown.result -ceq "APPLIED") "$name execution proof missing"
    }
    $terminal = @($runtime.commands | Where-Object name -CEQ "melee2hArea3")[0]
    Assert ([int]$terminal.state.type -eq 1 -and
        [int]$terminal.state.chance -eq 30 -and
        [int]$terminal.state.duration -eq 30 -and
        [string]$terminal.state.result -in @("APPLIED", "RESISTED")) "M316 DIZZY proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.branchSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.canPerformSurvived -and
        [bool]$runtime.persistence.weaponSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientDizzyAbsent) "M316 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.masterPrerequisiteOrderingRepaired -and
        [bool]$runtime.cleanup.temporaryTwoHandSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M316 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 two-hand accuracy branch contract passed."
