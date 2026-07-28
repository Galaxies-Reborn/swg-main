param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3UnarmedAccuracyBranch)) -Raw | ConvertFrom-Json
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
    meditation = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/meditation.java"
    teraskasi = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/skill/teraskasi.java"
    cleanup = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/skill/cleanup.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_unarmed_accuracy_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M323 source: $path"
}

$commands = Rows $paths.command
$power = @($commands | Where-Object commandName -CEQ "powerBoost")
$force = @($commands | Where-Object commandName -CEQ "forceOfWill")
Assert ($power.Count -eq 1) "powerBoost command row missing or duplicated"
Assert ($force.Count -eq 1) "forceOfWill command row missing or duplicated"
$power = $power[0]
$force = $force[0]
Assert ($power.scriptHook -ceq "cmdPowerBoost" -and
    $power.failScriptHook -ceq "cmdPowerBoostFail" -and
    $power.defaultPriority -ceq "normal" -and
    $power.characterAbility -ceq "powerBoost" -and
    $power.'L:sitting' -ceq "1" -and
    $power.'L:skillAnimating' -ceq "1" -and
    $power.targetType -ceq "none" -and
    $power.addToCombatQueue -ceq "0" -and
    $power.cooldownGroup -ceq "power_boost" -and
    $power.warmupTime -ceq "5" -and
    $power.executeTime -ceq "1" -and
    $power.cooldownTime -ceq "300") "powerBoost command row drifted"
Assert ($force.scriptHook -ceq "cmdForceOfWill" -and
    $force.defaultPriority -ceq "normal" -and
    $force.characterAbility -ceq "forceOfWill" -and
    $force.'L:incapacitated' -ceq "1" -and
    $force.targetType -ceq "none" -and
    $force.addToCombatQueue -ceq "1") "forceOfWill command row drifted"

$skills = Rows $paths.skills
$accuracy = @($skills | Where-Object NAME -like "combat_unarmed_accuracy_0*")
Assert ($accuracy.Count -eq 4) "Teras Kasi Accuracy I-IV rows are incomplete"
$expected = @(
    @("combat_unarmed_accuracy_01", "combat_unarmed_novice", "", "meditate=15"),
    @("combat_unarmed_accuracy_02", "combat_unarmed_accuracy_01", "powerBoost", "meditate=15"),
    @("combat_unarmed_accuracy_03", "combat_unarmed_accuracy_02", "", "meditate=15"),
    @("combat_unarmed_accuracy_04", "combat_unarmed_accuracy_03", "forceOfWill", "meditate=15")
)
foreach ($rowExpected in $expected) {
    $row = @($accuracy | Where-Object NAME -CEQ $rowExpected[0])
    Assert ($row.Count -eq 1) "Accuracy row missing or duplicated: $($rowExpected[0])"
    $row = $row[0]
    Assert ([string]$row.SKILLS_REQUIRED -ceq $rowExpected[1]) "Accuracy prerequisite drifted: $($rowExpected[0])"
    if ($rowExpected[2]) {
        Assert ([string]$row.COMMANDS -match "(^|,)$([regex]::Escape($rowExpected[2]))(,|$)") "Accuracy command ownership drifted: $($rowExpected[0])"
    }
    Assert ([string]$row.SKILL_MODS -match "(^|,)$([regex]::Escape($rowExpected[3]))(,|$)") "Accuracy meditate modifier drifted: $($rowExpected[0])"
}
Assert ((@($accuracy | ForEach-Object {
    $match = [regex]::Match([string]$_.SKILL_MODS, '(?:^|,)meditate=(?<value>[0-9]+)(?:,|$)')
    if ($match.Success) { [int]$match.Groups['value'].Value } else { 0 }
} | Measure-Object -Sum).Sum) -eq 60) "Accuracy branch meditate modifier total drifted"

$meditation = Get-Content -LiteralPath $paths.meditation -Raw
$teraskasi = Get-Content -LiteralPath $paths.teraskasi -Raw
$cleanup = Get-Content -LiteralPath $paths.cleanup -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @(
    "POWERBOOST_RAMP = 60.0f", "POWERBOOST_BASE_DURATION = 300",
    "POWERBOOST_RAMP_TICKS = 20", "int boost = baseMind / 2",
    "(modval / 100) * POWERBOOST_BASE_DURATION",
    "MOD_POWERBOOST_DRAIN", "MOD_POWERBOOST_RESTORE",
    "MOD_POWERBOOST_MIND", "MOD_POWERBOOST_HEALTH",
    "MOD_POWERBOOST_ACTION", "beginPowerBoostMindRise",
    "duration - POWERBOOST_RAMP", "public static void endPowerBoost(",
    "MOD_FORCE_OF_WILL_PREFIX + attribute, attribute, -200",
    "MOD_FORCE_OF_WILL_PREFIX + attribute, attribute, -100",
    "300.0f, 0.0f, 0.0f", "120.0f, 0.0f, 0.0f",
    "setPostureClientImmediate(player, POSTURE_UPRIGHT)"
)) {
    Assert ($meditation.Contains($token)) "M323 meditation token missing: $token"
}
foreach ($token in @(
    "public int cmdPowerBoost(", "public int cmdPowerBoostFail(",
    "public int cmdForceOfWill(", "stamp + 3600 - now",
    "rand(0, 100)", "int delta = modval - roll",
    'recordFixtureOutcome(self, fixture, "forcePassed")',
    'applied ? "powerPassed" : "powerRejected"'
)) {
    Assert ($teraskasi.Contains($token)) "M323 Teras Kasi token missing: $token"
}
foreach ($token in @(
    "handlePowerBoostMindRise", "beginPowerBoostMindRise(self, params)",
    "handlePowerBoostWane", "handlePowerBoostEnd",
    "meditation.endPowerBoost(self, true)"
)) {
    Assert ($cleanup.Contains($token)) "M323 cleanup handler token missing: $token"
}
foreach ($token in @(
    "PLAYER_OID = 44003778L", "PLAYER_STATION_ID = 91001",
    "PROTOCOL_VERSION = 1", "FORCE_ROLL = 35",
    '"meditate", "powerBoost", "forceOfWill"',
    '"combat_unarmed_accuracy_01"', '"combat_unarmed_accuracy_04"',
    "prepare|armPower|status|clearPower|armForce|stabilize|",
    "cleanup|repairBaseline", "ACCEPTANCE_BASELINE",
    "commandBits=", "skillBits=", "forceModifierBits=",
    "snapshotComplete=", "removeObjVar(player, ROOT)"
)) {
    Assert ($fixture.Contains($token)) "M323 fixture token missing: $token"
}

$overlay = Join-Path $restorationRoot "patches/dsrc/321-p14-core3-unarmed-accuracy-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M323 overlay hash drifted"
foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties) {
    $key = switch ([string]$entry.Name) {
        "meditation.java" { "meditation" }
        "teraskasi.java" { "teraskasi" }
        "cleanup.java" { "cleanup" }
        "precu_unarmed_accuracy_fixture.java" { "fixture" }
        "command_table.tab" { "command" }
        "skills.tab" { "skills" }
        default { throw "Unexpected M323 source hash key: $($entry.Name)" }
    }
    Assert ([string]$entry.Value -ceq (Sha $paths[$key])) "M323 source hash drifted: $($entry.Name)"
}

if ($Expectation -ceq "Ready") {
    $runtime = $contract.runtimeEvidence
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$runtime.result -ceq "passed") "M323 is not Ready"
    Assert ([bool]$runtime.admission.freshAuthentication -and
        [string]$runtime.admission.commandBits -ceq "111" -and
        [string]$runtime.admission.skillBits -ceq "111111111111" -and
        [int]$runtime.admission.meditateModifier -eq 75 -and
        [bool]$runtime.admission.snapshotComplete) "M323 admission proof missing"
    Assert ([bool]$runtime.powerBoost.serverAccepted -and
        [int]$runtime.powerBoost.bonus -eq 500 -and
        [int]$runtime.powerBoost.tick -eq 25 -and
        [int]$runtime.powerBoost.durationSeconds -eq 300 -and
        [bool]$runtime.powerBoost.naturalExpiry -and
        [bool]$runtime.powerBoost.maximumsReturnedExactlyToBaseline) "M323 Power Boost proof missing"
    Assert ([bool]$runtime.forceOfWill.serverAccepted -and
        [int]$runtime.forceOfWill.roll -eq 35 -and
        [int]$runtime.forceOfWill.delta -eq 40 -and
        [string]$runtime.forceOfWill.tier -ceq "normal" -and
        [string]$runtime.forceOfWill.allNineModifierBits -ceq "111111111" -and
        [int]$runtime.forceOfWill.allNineMaximumDelta -eq -100 -and
        [bool]$runtime.forceOfWill.naturalModifierExpiry) "M323 Force of Will proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.allTwelveSkillsSurvived -and
        [bool]$runtime.persistence.allThreeCommandsSurvived -and
        [bool]$runtime.persistence.identityBoundSnapshotsSurvived -and
        [bool]$runtime.persistence.transientPowerBoostAbsent -and
        [bool]$runtime.persistence.transientForceModifiersAbsent -and
        [bool]$runtime.persistence.maximumsAtBaseline) "M323 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.acceptanceBaselineRepairIdempotent -and
        [bool]$runtime.cleanup.fixtureAbsentAfterCleanup -and
        [bool]$runtime.isolatedClientStopped -and
        [bool]$runtime.isolatedClientFilesRestoredToM322 -and
        [int]$runtime.connectionServerCount -eq 1) "M323 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 unarmed Accuracy branch contract passed."
