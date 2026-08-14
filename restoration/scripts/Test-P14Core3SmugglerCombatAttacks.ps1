param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3SmugglerCombatAttacks)) -Raw | ConvertFrom-Json
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
    engine = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/combat_engine.java"
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    base = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    overrides = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M328 source: $path"
}
$commandRows = Rows $paths.command
$skillRows = Rows $paths.skills
$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.overrides
$spamRows = Rows $paths.spam
$expected = @{
    panicShot = @{hook="coneDelay"; attack="CONE"; damage=2.0; speed=3.0; costs=@(0.5,1.25,0.5); accuracy=50; animation="fire_1_special_single"; spam="panicshot"}
    lowBlow = @{hook="lowBlow"; attack="SINGLE_TARGET"; damage=2.0; speed=2.5; costs=@(0.5,1.0,0.5); accuracy=50; animation="fire_5_single"; spam="lowblow"}
    lastDitch = @{hook="lastDitch"; attack="SINGLE_TARGET"; damage=6.0; speed=4.0; costs=@(0.5,1.25,0.5); accuracy=60; animation="fire_1_special_single"; spam="lastditch"}
}
foreach ($name in $expected.Keys) {
    $want = $expected[$name]
    $command = @($commandRows | Where-Object commandName -CEQ $name)
    $combat = @($combatRows | Where-Object actionName -CEQ $name)
    $override = @($overrideRows | Where-Object actionName -CEQ $name)
    $spam = @($spamRows | Where-Object actionName -CEQ $name)
    Assert ($command.Count -eq 1 -and $combat.Count -eq 1 -and
        $override.Count -eq 1 -and $spam.Count -eq 1) "$name rows missing or duplicated"
    $command=$command[0]; $combat=$combat[0]; $override=$override[0]; $spam=$spam[0]
    Assert ([string]$command.commandCategory -ceq "combat" -and
        [string]$command.defaultPriority -ceq "normal" -and
        [string]$command.scriptHook -ceq $want.hook -and
        [string]$command.failScriptHook -ceq "failSpecialAttack" -and
        [double]$command.defaultTime -eq 1.5 -and
        [string]$command.characterAbility -ceq $name -and
        [string]$command.target -ceq "other" -and
        [string]$command.targetType -ceq "optional" -and
        [int]$command.commandGroup -eq 391413347 -and
        [int]$command.maxRangeToTarget -eq 0 -and
        [int]$command.addToCombatQueue -eq 1 -and
        [string]$command.validWeapon -ceq "PISTOL" -and
        [double]$command.executeTime -eq 1.5) "$name command metadata drifted"
    Assert ([double]$combat.percentAddFromWeapon -eq $want.damage -and
        [string]$combat.animDefault -ceq $want.animation -and
        [string]$combat.anim_pistol -ceq $want.animation -and
        [string]$combat.weaponType -ceq "PISTOL" -and
        [string]$combat.attackType -ceq $want.attack -and
        [string]$combat.specialLine -ceq "smuggler") "$name combat data drifted"
    Assert ([double]$override.healthCostMultiplier -eq $want.costs[0] -and
        [double]$override.actionCostMultiplier -eq $want.costs[1] -and
        [double]$override.mindCostMultiplier -eq $want.costs[2] -and
        [string]$override.targetPool -ceq "RANDOM" -and
        [double]$override.speedMultiplier -eq $want.speed -and
        [int]$override.accuracyBonus -eq $want.accuracy -and
        [string]$override.animationType -ceq "RANGED" -and
        [string]$spam.combatSpam -ceq $want.spam) "$name override or spam drifted"
}
$panicCombat = @($combatRows | Where-Object actionName -CEQ "panicShot")[0]
$panic = @($overrideRows | Where-Object actionName -CEQ "panicShot")[0]
Assert ([double]$panicCombat.coneLength -eq 64 -and [double]$panicCombat.coneWidth -eq 45 -and
    [string]$panic.stateEffect1 -ceq "NEXT_ATTACK_DELAY" -and
    [int]$panic.stateChance1 -eq 100 -and [int]$panic.stateDuration1 -eq 10 -and
    [string]$panic.stateDefense1 -ceq "warcry_defense") "panicShot cone or delay drifted"
$low = @($overrideRows | Where-Object actionName -CEQ "lowBlow")[0]
Assert ([int]$low.knockdownChance -eq 100) "lowBlow knockdown drifted"
$last = @($overrideRows | Where-Object actionName -CEQ "lastDitch")[0]
Assert ([string]$last.stateEffect1 -ceq "STUN" -and
    [int]$last.stateChance1 -eq 100 -and [int]$last.stateDuration1 -eq 30 -and
    [string]$last.stateDefense1 -ceq "stun_defense" -and
    [string]$last.stateJediDefense1 -ceq "jedi_state_defense" -and
    [string]$last.stateResistance1 -ceq "resistance_states") "lastDitch stun drifted"
$owners = @{
    combat_smuggler_combat_02="panicShot"
    combat_smuggler_combat_03="lowBlow,melee_damage_mitigation_1"
    combat_smuggler_combat_04="lastDitch"
}
foreach ($skillName in $owners.Keys) {
    $row = @($skillRows | Where-Object NAME -CEQ $skillName)
    Assert ($row.Count -eq 1 -and [string]$row[0].COMMANDS -ceq $owners[$skillName]) "$skillName ownership drifted"
}
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($pair in @(@("coneDelay","panicShot"), @("lowBlow","lowBlow"), @("lastDitch","lastDitch"))) {
    Assert ($actions.Contains("public int $($pair[0])(") -and
        $actions.Contains("combatStandardAction(`"$($pair[1])`"")) "$($pair[1]) production wrapper missing"
}
foreach ($token in @("prepareSmugglerCombat", "statusSmugglerCombat",
    "armSmugglerCombat", "cleanupSmugglerCombat", "SMUGGLER_COMBAT_SKILLS",
    "SMUGGLER_COMBAT_COMMANDS", "SMUGGLER_COMBAT_PREREQUISITES")) {
    Assert ($fixture.Contains($token)) "Fixture token missing: $token"
}
$hashNames = @{
    engine="combat_engine.java"; actions="combat_actions.java";
    base="combat_base.java"; fixture="precu_headshot1_fixture.java";
    command="command_table.tab"; skills="skills.tab";
    combat="combat_data.tab"; overrides="precu_combat_overrides.tab";
    spam="precu_combat_spam.tab"
}
foreach ($key in $hashNames.Keys) {
    Assert ((Sha $paths[$key]) -ceq [string]$contract.buildEvidence.sourceSha256.($hashNames[$key])) "M328 source hash mismatch: $key"
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M328 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [string]$runtime.admission.prerequisiteBits -ceq "111111111111" -and
        [string]$runtime.admission.skillBits -ceq "111111" -and
        [string]$runtime.admission.commandBits -ceq "111") "M328 admission proof missing"
    Assert ([bool]$runtime.commands.panicShot.serverAccepted -and
        [bool]$runtime.commands.panicShot.nextAttackDelayApplied -and
        [bool]$runtime.commands.lowBlow.serverAccepted -and
        [bool]$runtime.commands.lowBlow.knockdownApplied -and
        [bool]$runtime.commands.lastDitch.serverAccepted -and
        [bool]$runtime.commands.lastDitch.stunApplied) "M328 command proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.postRestartExecution.serverAccepted) "M328 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryPrerequisitesAbsent -and
        [bool]$runtime.cleanup.temporarySkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability" -and
        [bool]$runtime.isolatedClientsStopped -and
        [int]$runtime.connectionServerCount -eq 1) "M328 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 Smuggler combat attacks contract passed."
