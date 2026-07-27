param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3OneHandAccuracyBranch)) -Raw | ConvertFrom-Json
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
    combatBase = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    overrides = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M305 source: $path"
}
$names = @("melee1hScatterHit1", "melee1hDizzyHit2", "melee1hScatterHit2")
$commands = @(Rows $paths.command | Where-Object commandName -Cin $names)
Assert ($commands.Count -eq 3) "One-hand accuracy command branch is incomplete"
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
Assert ($combat.Count -eq 3 -and $overrides.Count -eq 3 -and $spam.Count -eq 3) "M305 combat tables are incomplete"
$scatterOne = @($combat | Where-Object actionName -CEQ "melee1hScatterHit1")[0]
$dizzyTwo = @($combat | Where-Object actionName -CEQ "melee1hDizzyHit2")[0]
$scatterTwo = @($combat | Where-Object actionName -CEQ "melee1hScatterHit2")[0]
$scatterOneOverride = @($overrides | Where-Object actionName -CEQ "melee1hScatterHit1")[0]
$dizzyTwoOverride = @($overrides | Where-Object actionName -CEQ "melee1hDizzyHit2")[0]
$scatterTwoOverride = @($overrides | Where-Object actionName -CEQ "melee1hScatterHit2")[0]
Assert ($scatterOne.attackType -ceq "SINGLE_TARGET" -and
    $scatterOne.maxRange -ceq "3" -and $scatterOne.percentAddFromWeapon -ceq "3.0" -and
    $scatterOne.animDefault -ceq "combo_3b" -and $scatterOne.weaponType -ceq "1HAND_MELEE") "melee1hScatterHit1 combat row drifted"
Assert ($dizzyTwo.attackType -ceq "AREA" -and $dizzyTwo.coneLength -ceq "16" -and
    $dizzyTwo.maxRange -ceq "3" -and $dizzyTwo.percentAddFromWeapon -ceq "3.5" -and
    $dizzyTwo.animDefault -ceq "combo_4a" -and $dizzyTwo.weaponType -ceq "1HAND_MELEE") "melee1hDizzyHit2 combat row drifted"
Assert ($scatterTwo.attackType -ceq "SINGLE_TARGET" -and
    $scatterTwo.maxRange -ceq "3" -and $scatterTwo.percentAddFromWeapon -ceq "4.0" -and
    $scatterTwo.animDefault -ceq "combo_5b" -and $scatterTwo.weaponType -ceq "1HAND_MELEE") "melee1hScatterHit2 combat row drifted"
Assert ($scatterOneOverride.healthCostMultiplier -ceq "1.0" -and
    $scatterOneOverride.actionCostMultiplier -ceq "1.0" -and
    $scatterOneOverride.mindCostMultiplier -ceq "1.5" -and
    $scatterOneOverride.targetPool -ceq "MULTI" -and
    $scatterOneOverride.speedMultiplier -ceq "1.5") "melee1hScatterHit1 override drifted"
Assert ($dizzyTwoOverride.healthCostMultiplier -ceq "0.75" -and
    $dizzyTwoOverride.actionCostMultiplier -ceq "0.75" -and
    $dizzyTwoOverride.mindCostMultiplier -ceq "1.25" -and
    $dizzyTwoOverride.targetPool -ceq "RANDOM" -and
    $dizzyTwoOverride.speedMultiplier -ceq "2.25" -and
    $dizzyTwoOverride.stateEffect1 -ceq "DIZZY" -and
    $dizzyTwoOverride.stateChance1 -ceq "100" -and
    $dizzyTwoOverride.stateDuration1 -ceq "50") "melee1hDizzyHit2 override drifted"
Assert ($scatterTwoOverride.healthCostMultiplier -ceq "1.25" -and
    $scatterTwoOverride.actionCostMultiplier -ceq "1.25" -and
    $scatterTwoOverride.mindCostMultiplier -ceq "2.0" -and
    $scatterTwoOverride.targetPool -ceq "MULTI" -and
    $scatterTwoOverride.speedMultiplier -ceq "2.5") "melee1hScatterHit2 override drifted"
Assert (@($spam | Where-Object actionName -CEQ "melee1hScatterHit1")[0].combatSpam -ceq "scatterstab" -and
    @($spam | Where-Object actionName -CEQ "melee1hDizzyHit2")[0].combatSpam -ceq "skullslash" -and
    @($spam | Where-Object actionName -CEQ "melee1hScatterHit2")[0].combatSpam -ceq "scattershiak") "M305 spam drifted"
$skills = Rows $paths.skills
$novice = @($skills | Where-Object NAME -CEQ "combat_1hsword_novice")[0]
$accuracyOne = @($skills | Where-Object NAME -CEQ "combat_1hsword_accuracy_01")[0]
$accuracyTwo = @($skills | Where-Object NAME -CEQ "combat_1hsword_accuracy_02")[0]
$accuracyThree = @($skills | Where-Object NAME -CEQ "combat_1hsword_accuracy_03")[0]
$accuracyFour = @($skills | Where-Object NAME -CEQ "combat_1hsword_accuracy_04")[0]
Assert ($novice.SKILLS_REQUIRED -ceq "combat_brawler_1handmelee_04" -and
    $accuracyOne.SKILLS_REQUIRED -ceq "combat_1hsword_novice" -and
    [string]$accuracyOne.COMMANDS -match "(^|,)melee1hScatterHit1(,|$)" -and
    $accuracyTwo.SKILLS_REQUIRED -ceq "combat_1hsword_accuracy_01" -and
    $accuracyThree.SKILLS_REQUIRED -ceq "combat_1hsword_accuracy_02" -and
    [string]$accuracyThree.COMMANDS -match "(^|,)melee1hDizzyHit2(,|$)" -and
    $accuracyFour.SKILLS_REQUIRED -ceq "combat_1hsword_accuracy_03" -and
    [string]$accuracyFour.COMMANDS -match "(^|,)melee1hScatterHit2(,|$)") "M305 ownership chain drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $names) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains("`"$name`"")) "$name production hook drifted"
}
Assert ($combatBase.Contains("PRECU_TARGET_POOL_MULTI = 4") -and
    $combatBase.Contains("precuAllPoolDamage")) "M305 all-pool production semantics missing"
foreach ($token in @("ONE_HAND_SWORD_ACCURACY_ONE", "ONE_HAND_SWORD_ACCURACY_TWO",
    "ONE_HAND_SWORD_ACCURACY_THREE", "ONE_HAND_SWORD_ACCURACY_FOUR",
    "ONE_HAND_SCATTER_HIT_ONE_COMMAND", "ONE_HAND_DIZZY_HIT_TWO_COMMAND",
    "ONE_HAND_SCATTER_HIT_TWO_COMMAND", "armOneHandAccuracy",
    "oneHandScatterHitOneCanPerform=", "oneHandDizzyHitTwoCanPerform=",
    "oneHandScatterHitTwoCanPerform=")) {
    Assert ($fixture.Contains($token)) "M305 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/303-p14-core3-one-hand-accuracy-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M305 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M305 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.oneHandAccuracyFour -and
        [int]$runtime.admission.canPerform.melee1hScatterHit1 -eq 0 -and
        [int]$runtime.admission.canPerform.melee1hDizzyHit2 -eq 0 -and
        [int]$runtime.admission.canPerform.melee1hScatterHit2 -eq 0) "M305 admission proof missing"
    foreach ($name in $names) {
        $execution = $runtime.commands.$name
        Assert ([string]$execution.queueRemoval -ceq "Success" -and
            [int]$execution.combatResult -eq 1 -and
            [int]$execution.directDamage -gt 0) "$name execution proof missing"
    }
    Assert ([int]$runtime.commands.melee1hScatterHit1.poolDamageMask -eq 7 -and
        [int]$runtime.commands.melee1hScatterHit2.poolDamageMask -eq 7 -and
        [int]$runtime.commands.melee1hDizzyHit2.state.type -eq 1 -and
        [string]$runtime.commands.melee1hDizzyHit2.state.result -ceq "APPLIED" -and
        [string]$runtime.commands.melee1hDizzyHit2.attackType -ceq "AREA" -and
        [int]$runtime.commands.melee1hDizzyHit2.areaRange -eq 16) "M305 combat semantics proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientDizzyAbsent) "M305 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryOneHandSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M305 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 one-hand accuracy branch contract passed."
