param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3BountyHunterDroidControlBranch)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M325 source: $path"
}
$commands = @("underHandShot", "knockdownFire", "confusionShot")
$commandRows = Rows $paths.command
$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.overrides
$spamRows = Rows $paths.spam
$skillRows = Rows $paths.skills
foreach ($name in $commands) {
    $row = @($commandRows | Where-Object commandName -CEQ $name)
    Assert ($row.Count -eq 1) "$name command row missing or duplicated"
    $row = $row[0]
    Assert ([string]$row.commandCategory -ceq "combat" -and
        [string]$row.defaultPriority -ceq "normal" -and
        [string]$row.scriptHook -ceq $name -and
        [string]$row.failScriptHook -ceq "failSpecialAttack" -and
        [double]$row.defaultTime -eq 1.5 -and
        [string]$row.characterAbility -ceq $name -and
        [string]$row.target -ceq "other" -and
        [string]$row.targetType -ceq "optional" -and
        [int]$row.commandGroup -eq 391413347 -and
        [int]$row.maxRangeToTarget -eq 0 -and
        [int]$row.addToCombatQueue -eq 1 -and
        [string]$row.validWeapon -ceq "CARBINE" -and
        [double]$row.executeTime -eq 1.5) "$name command metadata drifted"
}
$skillExpectations = @{
    combat_bountyhunter_droidcontrol_01 = "underHandShot"
    combat_bountyhunter_droidcontrol_02 = ""
    combat_bountyhunter_droidcontrol_03 = "knockdownFire"
    combat_bountyhunter_droidcontrol_04 = "confusionShot"
}
foreach ($skillName in $skillExpectations.Keys) {
    $row = @($skillRows | Where-Object NAME -CEQ $skillName)
    Assert ($row.Count -eq 1) "$skillName missing or duplicated"
    Assert ([string]$row[0].COMMANDS -ceq $skillExpectations[$skillName]) "$skillName command ownership drifted"
}
$expected = @{
    underHandShot = @{damage=3.0; speed=1.5; animation="fire_7_single"; spam="underhandshot"; kd=85}
    knockdownFire = @{damage=2.5; speed=2.0; animation="fire_3_single"; spam="knockdownfire"; kd=85}
    confusionShot = @{damage=3.0; speed=2.3; animation="fire_5_special_single"; spam="confusionshot"; kd=0}
}
foreach ($name in $commands) {
    $combat = @($combatRows | Where-Object actionName -CEQ $name)
    $override = @($overrideRows | Where-Object actionName -CEQ $name)
    $spam = @($spamRows | Where-Object actionName -CEQ $name)
    Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "$name combat rows missing or duplicated"
    $combat = $combat[0]; $override = $override[0]; $spam = $spam[0]; $want = $expected[$name]
    Assert ([double]$combat.percentAddFromWeapon -eq [double]$want.damage -and
        [string]$combat.animDefault -ceq [string]$want.animation -and
        [string]$combat.anim_carbine -ceq [string]$want.animation -and
        [string]$combat.weaponType -ceq "CARBINE" -and
        [string]$combat.attackType -ceq "SINGLE_TARGET" -and
        [string]$combat.specialLine -ceq "bounty_hunter") "$name combat data drifted"
    Assert ([double]$override.healthCostMultiplier -eq 1 -and
        [double]$override.actionCostMultiplier -eq 1 -and
        [double]$override.mindCostMultiplier -eq 1 -and
        [string]$override.targetPool -ceq "RANDOM" -and
        [double]$override.speedMultiplier -eq [double]$want.speed -and
        [int]$override.accuracyBonus -eq 0 -and
        [string]$override.animationType -ceq "RANGED" -and
        [string]$spam.combatSpam -ceq [string]$want.spam) "$name override or spam drifted"
}
$under = @($overrideRows | Where-Object actionName -CEQ "underHandShot")[0]
$knock = @($overrideRows | Where-Object actionName -CEQ "knockdownFire")[0]
$confusion = @($overrideRows | Where-Object actionName -CEQ "confusionShot")[0]
Assert ([int]$under.knockdownChance -eq 85) "underHandShot knockdown drifted"
Assert ([string]$knock.stateEffect1 -ceq "DIZZY" -and
    [int]$knock.stateChance1 -eq 85 -and [int]$knock.stateDuration1 -eq 10 -and
    [string]$knock.stateDefense1 -ceq "dizzy_defense" -and
    [string]$knock.stateJediDefense1 -ceq "jedi_state_defense" -and
    [string]$knock.stateResistance1 -ceq "resistance_states" -and
    [int]$knock.knockdownChance -eq 85) "knockdownFire state contract drifted"
Assert ([string]$confusion.stateEffect1 -ceq "DIZZY" -and
    [int]$confusion.stateChance1 -eq 100 -and [int]$confusion.stateDuration1 -eq 10 -and
    [string]$confusion.stateEffect2 -ceq "STUN" -and
    [int]$confusion.stateChance2 -eq 100 -and [int]$confusion.stateDuration2 -eq 10 -and
    [string]$confusion.stateDefense2 -ceq "stun_defense" -and
    [string]$confusion.stateJediDefense2 -ceq "jedi_state_defense" -and
    [string]$confusion.stateResistance2 -ceq "resistance_states") "confusionShot dual-state contract drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $commands) {
    Assert ($actions.Contains("public int $name(") -and
        $actions.Contains("combatStandardAction(`"$name`"")) "$name production wrapper missing"
}
foreach ($token in @(
    "prepareBountyHunterDroidControl", "statusBountyHunterDroidControl",
    "armBountyHunterDroidControl", "cleanupBountyHunterDroidControl",
    "BOUNTY_HUNTER_DROID_CONTROL_SKILLS",
    "BOUNTY_HUNTER_DROID_CONTROL_COMMANDS",
    "BOUNTY_HUNTER_DROID_CONTROL_PREREQUISITES",
    "ORIGINAL_BOUNTY_HUNTER_DROID_CONTROL_SKILL_BITS",
    "ORIGINAL_BOUNTY_HUNTER_DROID_CONTROL_COMMAND_BITS",
    "ORIGINAL_BOUNTY_HUNTER_DROID_CONTROL_PREREQUISITE_BITS",
    "recoverBountyHunterDroidControl")) {
    Assert ($fixture.Contains($token)) "Fixture token missing: $token"
}
$hashNames = @{
    actions="combat_actions.java"; fixture="precu_headshot1_fixture.java";
    command="command_table.tab"; skills="skills.tab"; combat="combat_data.tab";
    overrides="precu_combat_overrides.tab"; spam="precu_combat_spam.tab"
}
foreach ($key in $hashNames.Keys) {
    Assert ((Sha $paths[$key]) -ceq [string]$contract.buildEvidence.sourceSha256.($hashNames[$key])) "M325 source hash mismatch: $key"
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M325 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [string]$runtime.admission.prerequisiteBits -ceq "1111111" -and
        [string]$runtime.admission.skillBits -ceq "111111" -and
        [string]$runtime.admission.commandBits -ceq "111" -and
        [bool]$runtime.admission.marksmanMaster -and
        [bool]$runtime.admission.scoutMovementFour -and
        [bool]$runtime.admission.clientWeaponStatus.satisfies) "M325 admission proof missing"
    Assert ([bool]$runtime.commands.underHandShot.serverAccepted -and
        [bool]$runtime.commands.knockdownFire.serverAccepted -and
        [bool]$runtime.commands.confusionShot.serverAccepted) "M325 command proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.allPrerequisitesSurvived -and
        [bool]$runtime.persistence.allSkillsSurvived -and
        [bool]$runtime.persistence.allCommandsSurvived -and
        [bool]$runtime.persistence.postRestartExecution.serverAccepted) "M325 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.prerequisiteSnapshotRestored -and
        [bool]$runtime.cleanup.temporaryPrerequisitesAbsent -and
        [bool]$runtime.cleanup.temporarySkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability" -and
        [bool]$runtime.isolatedClientsStopped -and
        [int]$runtime.connectionServerCount -eq 1) "M325 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 Bounty Hunter Droid Control branch contract passed."
