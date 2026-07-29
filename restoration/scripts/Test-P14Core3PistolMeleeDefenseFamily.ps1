param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PistolMeleeDefenseFamily)) -Raw | ConvertFrom-Json
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
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M302 source: $path"
}
$names = @("pistolMeleeDefense1", "pistolMeleeDefense2")
$commands = @(Rows $paths.command | Where-Object commandName -Cin $names)
Assert ($commands.Count -eq 2) "Pistol melee-defense command family is incomplete"
foreach ($command in $commands) {
    Assert ($command.scriptHook -ceq $command.commandName -and
        $command.defaultPriority -ceq "normal" -and
        $command.defaultTime -ceq "2" -and $command.executeTime -ceq "2" -and
        $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
        $command.commandGroup -ceq "391413347" -and
        $command.addToCombatQueue -ceq "1" -and
        $command.validWeapon -ceq "PISTOL") "$($command.commandName) command row drifted"
}
$combatRows = @(Rows $paths.combat | Where-Object actionName -Cin $names)
Assert ($combatRows.Count -eq 2) "Pistol melee-defense combat family is incomplete"
$combatOne = @($combatRows | Where-Object actionName -CEQ "pistolMeleeDefense1")[0]
$combatTwo = @($combatRows | Where-Object actionName -CEQ "pistolMeleeDefense2")[0]
foreach ($combat in $combatRows) {
    Assert ($combat.validTarget -ceq "STANDARD" -and $combat.hitType -ceq "ATTACK" -and
        $combat.attackType -ceq "SINGLE_TARGET" -and $combat.maxRange -ceq "10" -and
        $combat.animDefault -ceq "ranged_melee" -and $combat.anim_pistol -ceq "ranged_melee" -and
        $combat.weaponType -ceq "PISTOL" -and $combat.weaponCategory -ceq "RANGED_WEAPON" -and
        $combat.specialLine -ceq "pistoleer") "$($combat.actionName) combat row drifted"
}
Assert ($combatOne.percentAddFromWeapon -ceq "3.0" -and
    $combatTwo.percentAddFromWeapon -ceq "4.0") "Pistol melee-defense damage multipliers drifted"
$overrides = @(Rows $paths.override | Where-Object actionName -Cin $names)
Assert ($overrides.Count -eq 2) "Pistol melee-defense overrides are incomplete"
$overrideOne = @($overrides | Where-Object actionName -CEQ "pistolMeleeDefense1")[0]
$overrideTwo = @($overrides | Where-Object actionName -CEQ "pistolMeleeDefense2")[0]
foreach ($override in $overrides) {
    Assert ($override.healthCostMultiplier -ceq "0.5" -and
        $override.mindCostMultiplier -ceq "0.5" -and $override.targetPool -ceq "RANDOM" -and
        $override.speedMultiplier -ceq "2" -and $override.accuracyBonus -ceq "50" -and
        $override.animationType -ceq "INTENSITY") "$($override.actionName) override drifted"
}
Assert ($overrideOne.actionCostMultiplier -ceq "0.75" -and
    $overrideOne.knockdownChance -ceq "100" -and
    $overrideTwo.actionCostMultiplier -ceq "1" -and
    $overrideTwo.knockdownChance -ceq "65") "Pistol melee-defense cost/chance values drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -Cin $names)
Assert ($spam.Count -eq 2 -and @($spam | Where-Object combatSpam -CNE "pistolwhip").Count -eq 0) "Pistol melee-defense spam drifted"
$skills = Rows $paths.skills
$supportOne = @($skills | Where-Object NAME -CEQ "combat_pistol_support_01")[0]
$supportTwo = @($skills | Where-Object NAME -CEQ "combat_pistol_support_02")[0]
$supportThree = @($skills | Where-Object NAME -CEQ "combat_pistol_support_03")[0]
Assert ($supportOne.SKILLS_REQUIRED -ceq "combat_pistol_novice" -and
    [string]$supportOne.COMMANDS -match "(^|,)pistolMeleeDefense1(,|$)" -and
    [string]$supportOne.SKILL_MODS -match "(^|,)melee_defense=10(,|$)" -and
    [string]$supportOne.SKILL_MODS -match "(^|,)pistol_speed=6(,|$)" -and
    $supportTwo.SKILLS_REQUIRED -ceq "combat_pistol_support_01" -and
    $supportThree.SKILLS_REQUIRED -ceq "combat_pistol_support_02" -and
    [string]$supportThree.COMMANDS -match "(^|,)pistolMeleeDefense2(,|$)" -and
    [string]$supportThree.SKILL_MODS -match "(^|,)pistol_accuracy_while_standing=15(,|$)") "Pistoleer support ownership chain drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $names) {
    Assert ($actions.Contains("public int $name(") -and
        $actions.Contains("combatStandardAction(`"$name`"")) "$name production wrapper drifted"
}
foreach ($token in @("PISTOL_MELEE_DEFENSE_ONE_COMMAND", "PISTOL_MELEE_DEFENSE_TWO_COMMAND",
    "ORIGINAL_PISTOL_SUPPORT_ONE", "ORIGINAL_PISTOL_SUPPORT_TWO", "ORIGINAL_PISTOL_SUPPORT_THREE",
    "armPistolMeleeDefense", "pistolMeleeDefenseOneDamageMultiplier=",
    "pistolMeleeDefenseOneKnockdownChance=", "pistolMeleeDefenseTwoDamageMultiplier=",
    "pistolMeleeDefenseTwoKnockdownChance=", "pistolMeleeDefenseOneHealthCost=",
    "pistolMeleeDefenseTwoActionCost=", "canPerformPistolMeleeDefenseOne=",
    "canPerformPistolMeleeDefenseTwo=", "cleanup.pistolSkills", "cleanup.pistolCommands")) {
    Assert ($fixture.Contains($token)) "M302 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/300-p14-core3-pistol-melee-defense-family.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M302 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M302 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.marksmanPistolChain -and
        [bool]$runtime.admission.pistoleerNovice -and
        [bool]$runtime.admission.pistoleerSupportChain -and
        [int]$runtime.admission.canPerform.pistolMeleeDefense1 -eq 0 -and
        [int]$runtime.admission.canPerform.pistolMeleeDefense2 -eq 0 -and
        [bool]$runtime.admission.weaponSatisfies) "M302 admission proof missing"
    $one = $runtime.commands.pistolMeleeDefense1
    $two = $runtime.commands.pistolMeleeDefense2
    Assert ([string]$one.queueRemoval -ceq "Success" -and
        [string]$one.combatSpam -ceq "pistolwhip_hit" -and
        [int]$one.configuredTargetPool -eq 3 -and
        [int]$one.knockdown.configuredChance -eq 100 -and
        [string]$one.knockdown.result -ceq "APPLIED" -and
        [int]$one.knockdown.endPosture -eq 12) "pistolMeleeDefense1 execution proof missing"
    Assert ([string]$two.queueRemoval -ceq "Success" -and
        [string]$two.combatSpam -ceq "pistolwhip_hit" -and
        [int]$two.configuredTargetPool -eq 3 -and
        [bool]$two.sharedRecoveryGuardObserved -and
        [int]$two.knockdown.configuredChance -eq 65 -and
        [int]$two.knockdown.roll -gt 65 -and
        [string]$two.knockdown.result -ceq "RESISTED") "pistolMeleeDefense2 execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientKnockdownRecoveryAbsent) "M302 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryPistolSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M302 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 pistol melee-defense family contract passed."
