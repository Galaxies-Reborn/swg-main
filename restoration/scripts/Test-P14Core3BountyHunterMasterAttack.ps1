param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3BountyHunterMasterAttack)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M327 source: $path"
}
$commandRows = Rows $paths.command
$skillRows = Rows $paths.skills
$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.overrides
$spamRows = Rows $paths.spam
$expected = @{
    sprayShot = @{weapon="CARBINE"; damage=4.0; speed=3.5; costs=@(1.0,1.0,1.0); pool="RANDOM"; accuracy=0; animation="fire_7_single"; spam="sprayshot"}
    fastBlast = @{weapon="PISTOL"; damage=6.0; speed=3.05; costs=@(1.5,1.5,1.0); pool="MULTI"; accuracy=95; animation="fire_5_special_single"; spam="fastblast"}
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
    Assert ([string]::IsNullOrEmpty([string]$command.commandCategory) -and
        [string]$command.defaultPriority -ceq "normal" -and
        [string]$command.scriptHook -ceq $name -and
        [string]$command.failScriptHook -ceq "failSpecialAttack" -and
        [double]$command.defaultTime -eq 1.5 -and
        [string]$command.characterAbility -ceq $name -and
        [string]$command.target -ceq "other" -and
        [string]$command.targetType -ceq "optional" -and
        [int]$command.commandGroup -eq 391413347 -and
        [int]$command.maxRangeToTarget -eq 0 -and
        [int]$command.addToCombatQueue -eq 1 -and
        [string]$command.validWeapon -ceq $want.weapon -and
        [double]$command.executeTime -eq 1.5) "$name command metadata drifted"
    $weaponAnimation = if ($want.weapon -ceq "PISTOL") {
        [string]$combat.anim_pistol
    } else { [string]$combat.anim_carbine }
    Assert ([double]$combat.percentAddFromWeapon -eq $want.damage -and
        [string]$combat.animDefault -ceq $want.animation -and
        $weaponAnimation -ceq $want.animation -and
        [string]$combat.weaponType -ceq $want.weapon -and
        [string]$combat.attackType -ceq "SINGLE_TARGET" -and
        [string]$combat.specialLine -ceq "bounty_hunter") "$name combat data drifted"
    Assert ([double]$override.healthCostMultiplier -eq $want.costs[0] -and
        [double]$override.actionCostMultiplier -eq $want.costs[1] -and
        [double]$override.mindCostMultiplier -eq $want.costs[2] -and
        [string]$override.targetPool -ceq $want.pool -and
        [double]$override.speedMultiplier -eq $want.speed -and
        [int]$override.accuracyBonus -eq $want.accuracy -and
        [string]$override.animationType -ceq "RANGED" -and
        [string]$spam.combatSpam -ceq $want.spam) "$name override or spam drifted"
}
$master = @($skillRows | Where-Object NAME -CEQ "combat_bountyhunter_master")
Assert ($master.Count -eq 1 -and
    [string]$master[0].SKILLS_REQUIRED -ceq "combat_bountyhunter_investigation_04,combat_bountyhunter_droidcontrol_04,combat_bountyhunter_droidresponse_04,combat_bountyhunter_support_04" -and
    [string]$master[0].COMMANDS -ceq "sprayShot,fastBlast,fireLightningCone2,ranged_damage_mitigation_3") "Bounty Hunter master ownership drifted"
$spray = @($overrideRows | Where-Object actionName -CEQ "sprayShot")[0]
Assert ([string]$spray.stateEffect1 -ceq "DIZZY" -and
    [int]$spray.stateChance1 -eq 60 -and [int]$spray.stateDuration1 -eq 30 -and
    [string]$spray.stateDefense1 -ceq "dizzy_defense" -and
    [string]$spray.stateEffect2 -ceq "BLIND" -and
    [int]$spray.stateChance2 -eq 100 -and [int]$spray.stateDuration2 -eq 30 -and
    [string]$spray.stateDefense2 -ceq "blind_defense" -and
    [string]$spray.stateEffect3 -ceq "STUN" -and
    [int]$spray.stateChance3 -eq 30 -and [int]$spray.stateDuration3 -eq 10 -and
    [string]$spray.stateDefense3 -ceq "stun_defense" -and
    [string]$spray.stateJediDefense1 -ceq "jedi_state_defense" -and
    [string]$spray.stateResistance1 -ceq "resistance_states") "sprayShot states drifted"
$fast = @($overrideRows | Where-Object actionName -CEQ "fastBlast")[0]
Assert ([double]$fast.healthDamageMultiplier -eq 0.33 -and
    [double]$fast.actionDamageMultiplier -eq 0.33 -and
    [double]$fast.mindDamageMultiplier -eq 0.33) "fastBlast pool multipliers drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$engine = Get-Content -LiteralPath $paths.engine -Raw
$base = Get-Content -LiteralPath $paths.base -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $expected.Keys) {
    Assert ($actions.Contains("public int $name(") -and
        $actions.Contains("combatStandardAction(`"$name`"")) "$name production wrapper missing"
}
foreach ($token in @("precuHealthDamageMultiplier",
    "precuActionDamageMultiplier", "precuMindDamageMultiplier")) {
    Assert ($engine.Contains($token) -and $base.Contains($token)) "Pool multiplier token missing: $token"
}
foreach ($token in @("prepareBountyHunterMaster", "statusBountyHunterMaster",
    "armBountyHunterMasterCarbine", "armBountyHunterMasterPistol",
    "cleanupBountyHunterMaster", "BOUNTY_HUNTER_MASTER_SKILLS",
    "BOUNTY_HUNTER_MASTER_COMMANDS", "BOUNTY_HUNTER_MASTER_PREREQUISITES")) {
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
    Assert ((Sha $paths[$key]) -ceq [string]$contract.buildEvidence.sourceSha256.($hashNames[$key])) "M327 source hash mismatch: $key"
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M327 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [string]$runtime.admission.prerequisiteBits -ceq "1111111" -and
        [string]$runtime.admission.skillBits -ceq "1111111111111111111" -and
        [string]$runtime.admission.commandBits -ceq "11") "M327 admission proof missing"
    Assert ([bool]$runtime.commands.sprayShot.serverAccepted -and
        [bool]$runtime.commands.fastBlast.serverAccepted -and
        [int]$runtime.commands.fastBlast.poolDamageActiveMask -eq 7 -and
        [double]$runtime.commands.fastBlast.healthMultiplier -eq 0.33 -and
        [double]$runtime.commands.fastBlast.actionMultiplier -eq 0.33 -and
        [double]$runtime.commands.fastBlast.mindMultiplier -eq 0.33) "M327 command proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.postRestartExecution.serverAccepted) "M327 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryPrerequisitesAbsent -and
        [bool]$runtime.cleanup.temporarySkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability" -and
        [bool]$runtime.isolatedClientsStopped -and
        [int]$runtime.connectionServerCount -eq 1) "M327 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 Bounty Hunter master attack contract passed."
