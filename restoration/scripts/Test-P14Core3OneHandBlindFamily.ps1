param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3OneHandBlindFamily)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M304 source: $path"
}
$names = @("melee1hBlindHit1", "melee1hBlindHit2")
$commands = @(Rows $paths.command | Where-Object commandName -Cin $names)
Assert ($commands.Count -eq 2) "One-hand blind command family is incomplete"
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
Assert ($combat.Count -eq 2 -and $overrides.Count -eq 2 -and $spam.Count -eq 2) "M304 combat tables are incomplete"
$one = @($combat | Where-Object actionName -CEQ "melee1hBlindHit1")[0]
$two = @($combat | Where-Object actionName -CEQ "melee1hBlindHit2")[0]
$oneOverride = @($overrides | Where-Object actionName -CEQ "melee1hBlindHit1")[0]
$twoOverride = @($overrides | Where-Object actionName -CEQ "melee1hBlindHit2")[0]
Assert ($one.attackType -ceq "SINGLE_TARGET" -and $one.maxRange -ceq "3" -and
    $one.percentAddFromWeapon -ceq "2.0" -and $one.animDefault -ceq "combo_4b" -and
    $one.weaponType -ceq "1HAND_MELEE") "melee1hBlindHit1 combat row drifted"
Assert ($two.attackType -ceq "AREA" -and $two.coneLength -ceq "16" -and
    $two.maxRange -ceq "3" -and $two.percentAddFromWeapon -ceq "2.5" -and
    $two.animDefault -ceq "combo_2b" -and $two.weaponType -ceq "1HAND_MELEE") "melee1hBlindHit2 combat row drifted"
Assert ($oneOverride.healthCostMultiplier -ceq "0.5" -and
    $oneOverride.actionCostMultiplier -ceq "0.5" -and
    $oneOverride.mindCostMultiplier -ceq "0.625" -and
    $oneOverride.speedMultiplier -ceq "1.5" -and
    $oneOverride.stateEffect1 -ceq "BLIND" -and
    $oneOverride.stateChance1 -ceq "100" -and
    $oneOverride.stateDuration1 -ceq "30") "melee1hBlindHit1 override drifted"
Assert ($twoOverride.healthCostMultiplier -ceq "0.75" -and
    $twoOverride.actionCostMultiplier -ceq "0.75" -and
    $twoOverride.mindCostMultiplier -ceq "1.25" -and
    $twoOverride.speedMultiplier -ceq "2.25" -and
    $twoOverride.stateEffect1 -ceq "BLIND" -and
    $twoOverride.stateChance1 -ceq "100" -and
    $twoOverride.stateDuration1 -ceq "50") "melee1hBlindHit2 override drifted"
Assert (@($spam | Where-Object actionName -CEQ "melee1hBlindHit1")[0].combatSpam -ceq "blindingstab" -and
    @($spam | Where-Object actionName -CEQ "melee1hBlindHit2")[0].combatSpam -ceq "blindingslash") "M304 spam drifted"
$skills = Rows $paths.skills
$novice = @($skills | Where-Object NAME -CEQ "combat_1hsword_novice")[0]
$supportOne = @($skills | Where-Object NAME -CEQ "combat_1hsword_support_01")[0]
$supportTwo = @($skills | Where-Object NAME -CEQ "combat_1hsword_support_02")[0]
$supportThree = @($skills | Where-Object NAME -CEQ "combat_1hsword_support_03")[0]
Assert ($novice.SKILLS_REQUIRED -ceq "combat_brawler_1handmelee_04" -and
    $supportOne.SKILLS_REQUIRED -ceq "combat_1hsword_novice" -and
    [string]$supportOne.COMMANDS -match "(^|,)melee1hBlindHit1(,|$)" -and
    $supportTwo.SKILLS_REQUIRED -ceq "combat_1hsword_support_01" -and
    $supportThree.SKILLS_REQUIRED -ceq "combat_1hsword_support_02" -and
    [string]$supportThree.COMMANDS -match "(^|,)melee1hBlindHit2(,|$)") "M304 ownership chain drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $names) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains("`"$name`"")) "$name production hook drifted"
}
foreach ($token in @("ONE_HAND_SWORD_NOVICE", "ONE_HAND_SWORD_SUPPORT_ONE",
    "ONE_HAND_SWORD_SUPPORT_TWO", "ONE_HAND_SWORD_SUPPORT_THREE",
    "ONE_HAND_BLIND_HIT_ONE_COMMAND", "ONE_HAND_BLIND_HIT_TWO_COMMAND",
    "armOneHandBlind", "oneHandBlindHitOneCanPerform=",
    "oneHandBlindHitTwoCanPerform=")) {
    Assert ($fixture.Contains($token)) "M304 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/302-p14-core3-one-hand-blind-family.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M304 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M304 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.oneHandSupportThree -and
        [int]$runtime.admission.canPerform.melee1hBlindHit1 -eq 0 -and
        [int]$runtime.admission.canPerform.melee1hBlindHit2 -eq 0) "M304 admission proof missing"
    foreach ($name in $names) {
        $execution = $runtime.commands.$name
        Assert ([string]$execution.queueRemoval -ceq "Success" -and
            [int]$execution.combatResult -eq 1 -and
            [int]$execution.directDamage -gt 0 -and
            [int]$execution.state.type -eq 2 -and
            [int]$execution.state.chance -eq 100 -and
            [string]$execution.state.result -ceq "APPLIED") "$name execution proof missing"
    }
    Assert ([string]$runtime.commands.melee1hBlindHit1.attackType -ceq "SINGLE_TARGET" -and
        [string]$runtime.commands.melee1hBlindHit2.attackType -ceq "AREA" -and
        [int]$runtime.commands.melee1hBlindHit2.areaRange -eq 16) "M304 target-shape proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientBlindAbsent) "M304 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryOneHandSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M304 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 one-hand blind family contract passed."
