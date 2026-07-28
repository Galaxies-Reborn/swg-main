param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3UnarmedSpeedBranch)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M321 source: $path"
}

$commandRows = Rows $paths.command
foreach ($name in @("unarmedKnockdown1", "unarmedKnockdown2")) {
    $rows = @($commandRows | Where-Object commandName -CEQ $name)
    Assert ($rows.Count -eq 1) "$name command row missing or duplicated"
    $row = $rows[0]
    Assert ($row.scriptHook -ceq $name -and $row.characterAbility -ceq $name -and
        $row.failScriptHook -ceq "failSpecialAttack" -and
        $row.defaultPriority -ceq "normal" -and
        $row.defaultTime -ceq "1.5" -and $row.executeTime -ceq "1.5" -and
        $row.target -ceq "other" -and $row.targetType -ceq "optional" -and
        $row.maxRangeToTarget -ceq "0" -and $row.commandGroup -ceq "391413347" -and
        $row.addToCombatQueue -ceq "1" -and $row.validWeapon -ceq "UNARMED") "$name command row drifted"
}

$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.overrides
$spamRows = Rows $paths.spam
$expected = @{
    unarmedKnockdown1 = @{
        damage = "1.0"; animation = "knockdown_unarmed_2"; cost = "1";
        speed = "1.5"; spam = "sleepingkrayt"; state = ""; chance = ""; duration = ""
    }
    unarmedKnockdown2 = @{
        damage = "1.5"; animation = "knockdown_unarmed_3"; cost = "1.5";
        speed = "2"; spam = "chargingwampa"; state = "DIZZY"; chance = "75"; duration = "40"
    }
}
foreach ($name in $expected.Keys) {
    $combat = @($combatRows | Where-Object actionName -CEQ $name)
    $override = @($overrideRows | Where-Object actionName -CEQ $name)
    $spam = @($spamRows | Where-Object actionName -CEQ $name)
    Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "M321 combat tables incomplete: $name"
    $combat = $combat[0]
    $override = $override[0]
    $want = $expected[$name]
    Assert ($combat.attackType -ceq "SINGLE_TARGET" -and $combat.maxRange -ceq "5" -and
        $combat.percentAddFromWeapon -ceq $want.damage -and
        $combat.animDefault -ceq $want.animation -and $combat.weaponType -ceq "UNARMED") "$name combat row drifted"
    Assert ($override.healthCostMultiplier -ceq $want.cost -and
        $override.actionCostMultiplier -ceq $want.cost -and
        $override.mindCostMultiplier -ceq $want.cost -and
        $override.targetPool -ceq "RANDOM" -and $override.speedMultiplier -ceq $want.speed -and
        $override.accuracyBonus -ceq "15" -and $override.animationType -ceq "NONE" -and
        $override.knockdownChance -ceq "100" -and
        $override.stateEffect1 -ceq $want.state -and
        $override.stateChance1 -ceq $want.chance -and
        $override.stateDuration1 -ceq $want.duration) "$name override drifted"
    if ($name -ceq "unarmedKnockdown2") {
        Assert ($override.stateStrength1 -ceq "0" -and
            $override.stateDefense1 -ceq "dizzy_defense" -and
            $override.stateJediDefense1 -ceq "jedi_state_defense" -and
            $override.stateResistance1 -ceq "resistance_states") "$name dizzy defenses drifted"
    }
    Assert ($spam[0].combatSpam -ceq $want.spam) "$name spam drifted"
}

$skillRows = Rows $paths.skills
$chain = [ordered]@{
    combat_unarmed_novice = "combat_brawler_unarmed_04"
    combat_unarmed_speed_01 = "combat_unarmed_novice"
    combat_unarmed_speed_02 = "combat_unarmed_speed_01"
    combat_unarmed_speed_03 = "combat_unarmed_speed_02"
    combat_unarmed_speed_04 = "combat_unarmed_speed_03"
}
foreach ($entry in $chain.GetEnumerator()) {
    $row = @($skillRows | Where-Object NAME -CEQ $entry.Key)
    Assert ($row.Count -eq 1 -and [string]$row[0].SKILLS_REQUIRED -ceq $entry.Value) "M321 skill prerequisite drifted: $($entry.Key)"
}
$speedOne = @($skillRows | Where-Object NAME -CEQ "combat_unarmed_speed_01")[0]
$speedFour = @($skillRows | Where-Object NAME -CEQ "combat_unarmed_speed_04")[0]
Assert ([string]$speedOne.COMMANDS -match "(^|,)unarmedKnockdown1(,|$)" -and
    [string]$speedFour.COMMANDS -match "(^|,)unarmedKnockdown2(,|$)") "M321 command ownership drifted"

$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in @("unarmedKnockdown1", "unarmedKnockdown2")) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains('"' + $name + '"')) "$name production hook drifted"
}
foreach ($token in @("TERAS_KASI_ROOT", "TERAS_KASI_NOVICE", "TERAS_KASI_SPEED_ONE",
    "TERAS_KASI_SPEED_TWO", "TERAS_KASI_SPEED_THREE", "TERAS_KASI_SPEED_FOUR",
    "UNARMED_KNOCKDOWN_ONE_COMMAND", "UNARMED_KNOCKDOWN_TWO_COMMAND",
    "prepareUnarmedSpeed", "armUnarmedSpeed", "statusUnarmedSpeed", "cleanupUnarmedSpeed",
    "unarmedKnockdownOneCanPerform=", "unarmedKnockdownTwoCanPerform=", "unarmedSpeedModifier=")) {
    Assert ($fixture.Contains($token)) "M321 fixture token missing: $token"
}

$overlay = Join-Path $restorationRoot "patches/dsrc/319-p14-core3-unarmed-speed-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M321 overlay hash drifted"
foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties) {
    $pathKey = switch ([string]$entry.Name) {
        "combat_actions.java" { "actions" }
        "precu_headshot1_fixture.java" { "fixture" }
        "command_table.tab" { "command" }
        "skills.tab" { "skills" }
        "combat_data.tab" { "combat" }
        "precu_combat_overrides.tab" { "overrides" }
        "precu_combat_spam.tab" { "spam" }
        default { throw "Unexpected M321 source hash key: $($entry.Name)" }
    }
    Assert ([string]$entry.Value -ceq (Sha $paths[$pathKey])) "M321 source hash drifted: $($entry.Name)"
}

if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M321 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.root -and [bool]$runtime.admission.novice -and
        [bool]$runtime.admission.speedOne -and [bool]$runtime.admission.speedTwo -and
        [bool]$runtime.admission.speedThree -and [bool]$runtime.admission.speedFour -and
        [int]$runtime.admission.canPerform[0] -eq 0 -and [int]$runtime.admission.canPerform[1] -eq 0 -and
        [int]$runtime.admission.unarmedSpeedModifier -eq 40 -and
        [bool]$runtime.admission.clientWeaponStatus.satisfies) "M321 admission proof missing"
    Assert ([bool]$runtime.commands.unarmedKnockdown1.serverAccepted -and
        [string]$runtime.commands.unarmedKnockdown1.combatSpam -ceq "sleepingkrayt_hit" -and
        [string]$runtime.commands.unarmedKnockdown1.animation -ceq "knockdown_unarmed_2" -and
        [string]$runtime.commands.unarmedKnockdown1.knockdown.result -ceq "APPLIED" -and
        [bool]$runtime.commands.unarmedKnockdown2.serverAccepted -and
        [string]$runtime.commands.unarmedKnockdown2.combatSpam -ceq "chargingwampa_hit" -and
        [string]$runtime.commands.unarmedKnockdown2.animation -ceq "knockdown_unarmed_3" -and
        [string]$runtime.commands.unarmedKnockdown2.dizzy.result -ceq "APPLIED" -and
        [string]$runtime.commands.unarmedKnockdown2.knockdown.result -ceq "APPLIED") "M321 execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.allSpeedSkillsSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.canPerformSurvived -and
        [bool]$runtime.persistence.transientDizzyAbsent -and
        [bool]$runtime.persistence.transientKnockdownPostureAbsent -and
        [bool]$runtime.persistence.transientKnockdownRecoveryAbsent -and
        [bool]$runtime.persistence.postRestartExecution.serverAccepted) "M321 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.identityBoundSnapshotsRestored -and
        [bool]$runtime.cleanup.fixtureAbsentAfterCleanup -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability" -and
        [bool]$runtime.isolatedClientsStopped -and
        [bool]$runtime.isolatedClientFilesRestoredToM320 -and
        [int]$runtime.connectionServerCount -eq 1) "M321 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 unarmed speed branch contract passed."
