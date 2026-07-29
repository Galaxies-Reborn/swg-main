param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3OneHandAbilityBranch)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M307 source: $path"
}
$names = @("melee1hBodyHit2", "melee1hBodyHit3")
$commands = @(Rows $paths.command | Where-Object commandName -Cin $names)
Assert ($commands.Count -eq 2) "One-hand ability commands are incomplete"
foreach ($command in $commands) {
    Assert ($command.scriptHook -ceq $command.commandName -and
        $command.characterAbility -ceq $command.commandName -and
        $command.failScriptHook -ceq "failSpecialAttack" -and
        $command.defaultPriority -ceq "normal" -and
        $command.executeTime -ceq "1.5" -and
        $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
        $command.commandGroup -ceq "391413347" -and
        $command.addToCombatQueue -ceq "1" -and
        $command.validWeapon -ceq "1HAND_MELEE") "$($command.commandName) command row drifted"
}
$bodyTwoCommand = @($commands | Where-Object commandName -CEQ "melee1hBodyHit2")[0]
$bodyThreeCommand = @($commands | Where-Object commandName -CEQ "melee1hBodyHit3")[0]
Assert ($bodyTwoCommand.defaultTime -ceq "2" -and $bodyThreeCommand.defaultTime -ceq "2.25") "M307 command timing drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -Cin $names)
$overrides = @(Rows $paths.overrides | Where-Object actionName -Cin $names)
$spam = @(Rows $paths.spam | Where-Object actionName -Cin $names)
Assert ($combat.Count -eq 2 -and $overrides.Count -eq 2 -and $spam.Count -eq 2) "M307 combat tables are incomplete"
$bodyTwo = @($combat | Where-Object actionName -CEQ "melee1hBodyHit2")[0]
$bodyThree = @($combat | Where-Object actionName -CEQ "melee1hBodyHit3")[0]
$bodyTwoOverride = @($overrides | Where-Object actionName -CEQ "melee1hBodyHit2")[0]
$bodyThreeOverride = @($overrides | Where-Object actionName -CEQ "melee1hBodyHit3")[0]
Assert ($bodyTwo.attackType -ceq "SINGLE_TARGET" -and $bodyTwo.maxRange -ceq "3" -and
    $bodyTwo.percentAddFromWeapon -ceq "2.5" -and $bodyTwo.animDefault -ceq "combo_4b" -and
    $bodyTwo.weaponType -ceq "1HAND_MELEE") "melee1hBodyHit2 combat row drifted"
Assert ($bodyThree.attackType -ceq "SINGLE_TARGET" -and $bodyThree.maxRange -ceq "3" -and
    $bodyThree.percentAddFromWeapon -ceq "3.5" -and $bodyThree.animDefault -ceq "combo_3a" -and
    $bodyThree.weaponType -ceq "1HAND_MELEE") "melee1hBodyHit3 combat row drifted"
Assert ($bodyTwoOverride.healthCostMultiplier -ceq "0.75" -and
    $bodyTwoOverride.actionCostMultiplier -ceq "0.75" -and
    $bodyTwoOverride.mindCostMultiplier -ceq "1.25" -and
    $bodyTwoOverride.targetPool -ceq "HEALTH" -and
    $bodyTwoOverride.speedMultiplier -ceq "2" -and
    $bodyTwoOverride.accuracyBonus -ceq "25" -and
    $bodyTwoOverride.animationType -ceq "INTENSITY") "melee1hBodyHit2 override drifted"
Assert ($bodyThreeOverride.healthCostMultiplier -ceq "1" -and
    $bodyThreeOverride.actionCostMultiplier -ceq "1" -and
    $bodyThreeOverride.mindCostMultiplier -ceq "2" -and
    $bodyThreeOverride.targetPool -ceq "HEALTH" -and
    $bodyThreeOverride.speedMultiplier -ceq "2.25" -and
    $bodyThreeOverride.accuracyBonus -ceq "25" -and
    $bodyThreeOverride.animationType -ceq "INTENSITY") "melee1hBodyHit3 override drifted"
Assert (@($spam | Where-Object actionName -CEQ "melee1hBodyHit2")[0].combatSpam -ceq "saisun" -and
    @($spam | Where-Object actionName -CEQ "melee1hBodyHit3")[0].combatSpam -ceq "saitok") "M307 spam drifted"
$skills = Rows $paths.skills
$novice = @($skills | Where-Object NAME -CEQ "combat_1hsword_novice")[0]
$abilityOne = @($skills | Where-Object NAME -CEQ "combat_1hsword_ability_01")[0]
$abilityTwo = @($skills | Where-Object NAME -CEQ "combat_1hsword_ability_02")[0]
$abilityThree = @($skills | Where-Object NAME -CEQ "combat_1hsword_ability_03")[0]
$abilityFour = @($skills | Where-Object NAME -CEQ "combat_1hsword_ability_04")[0]
Assert ($novice.SKILLS_REQUIRED -ceq "combat_brawler_1handmelee_04" -and
    $abilityOne.SKILLS_REQUIRED -ceq "combat_1hsword_novice" -and
    [string]$abilityOne.COMMANDS -match "(^|,)melee1hBodyHit2(,|$)" -and
    [string]$abilityOne.COMMANDS -match "(^|,)melee_damage_mitigation_1(,|$)" -and
    $abilityTwo.SKILLS_REQUIRED -ceq "combat_1hsword_ability_01" -and
    $abilityThree.SKILLS_REQUIRED -ceq "combat_1hsword_ability_02" -and
    [string]$abilityThree.COMMANDS -match "(^|,)melee1hBodyHit3(,|$)" -and
    [string]$abilityThree.COMMANDS -match "(^|,)melee_damage_mitigation_2(,|$)" -and
    $abilityFour.SKILLS_REQUIRED -ceq "combat_1hsword_ability_03") "M307 ownership chain drifted"
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @("ONE_HAND_SWORD_ABILITY_ONE", "ONE_HAND_SWORD_ABILITY_TWO",
    "ONE_HAND_SWORD_ABILITY_THREE", "ONE_HAND_SWORD_ABILITY_FOUR",
    "ONE_HAND_BODY_TWO_COMMAND", "ONE_HAND_BODY_THREE_COMMAND",
    "armOneHandAbility", "canPerformOneHandBodyTwo=", "canPerformOneHandBodyThree=")) {
    Assert ($fixture.Contains($token)) "M307 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/305-p14-core3-one-hand-ability-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M307 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M307 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.oneHandAbilityFour -and
        [int]$runtime.admission.canPerform.melee1hBodyHit2 -eq 0 -and
        [int]$runtime.admission.canPerform.melee1hBodyHit3 -eq 0) "M307 admission proof missing"
    foreach ($name in $names) {
        $execution = $runtime.commands.$name
        Assert ([string]$execution.queueRemoval -ceq "Success" -and
            [int]$execution.combatResult -eq 1 -and
            [int]$execution.directDamage -gt 0 -and
            [string]$execution.resolvedPool -ceq "HEALTH") "$name execution proof missing"
    }
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived) "M307 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryOneHandSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M307 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 one-hand ability branch contract passed."
