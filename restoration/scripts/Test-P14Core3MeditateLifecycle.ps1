param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3MeditateLifecycle)) -Raw | ConvertFrom-Json
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
    player = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_meditate_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M322 source: $path"
}

$commands = Rows $paths.command
$command = @($commands | Where-Object commandName -CEQ "meditate")
Assert ($command.Count -eq 1) "meditate command row missing or duplicated"
$command = $command[0]
Assert ($command.scriptHook -ceq "cmdMeditate" -and
    $command.failScriptHook -ceq "cmdMeditateFail" -and
    $command.defaultPriority -ceq "normal" -and
    $command.characterAbility -ceq "meditate" -and
    $command.'L:sitting' -ceq "1" -and
    $command.targetType -ceq "none" -and
    $command.addToCombatQueue -ceq "0") "meditate command row drifted"

$skills = Rows $paths.skills
$novice = @($skills | Where-Object NAME -CEQ "combat_unarmed_novice")
Assert ($novice.Count -eq 1) "combat_unarmed_novice row missing or duplicated"
$novice = $novice[0]
Assert ([string]$novice.SKILLS_REQUIRED -ceq "combat_brawler_unarmed_04" -and
    [string]$novice.COMMANDS -match "(^|,)meditate(,|$)" -and
    [string]$novice.SKILL_MODS -match "(^|,)meditate=15(,|$)" -and
    [string]$novice.SKILL_MODS -match "(^|,)private_med_dot=5(,|$)") "combat_unarmed_novice meditate ownership drifted"

$meditation = Get-Content -LiteralPath $paths.meditation -Raw
$player = Get-Content -LiteralPath $paths.player -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @(
    "INITIAL_DELAY = 3.5f", "TIME_TICK = 5.0f",
    "dot.isBleeding(player) && modval >= 15",
    "dot.isPoisoned(player) && modval >= 30",
    "dot.isDiseased(player) && modval >= 45",
    "15 + (modval / 3)", "modval >= 75", "modval >= 100",
    "20 + rand(0, 10)", "30 + rand(0, 20)",
    "new int[ATTRIBUTE_NAMES.length]", "sendSystemMessageProse(player, message)",
    "return TIME_TICK"
)) {
    Assert ($meditation.Contains($token)) "M322 meditation token missing: $token"
}
foreach ($token in @(
    "ai_lib.isInCombat(self)", "public int cmdMeditate(",
    "meditation.startMeditation(self)", "float delay = meditation.trance(self)",
    "trial.getSessionDict(self, meditation.HANDLER_MEDITATION_TICK), delay, false"
)) {
    Assert ($player.Contains($token)) "M322 player handler token missing: $token"
}
foreach ($token in @(
    "PLAYER_OID = 44003778L", "PLAYER_STATION_ID = 91001",
    "PROTOCOL_VERSION = 1", 'DOT_ID = "precu_meditate_fixture_bleed"',
    "BLEEDING_STRENGTH = 100", "prepare|arm|status|cleanup",
    "ORIGINAL_POINTS", "ORIGINAL_POSTURE", "ORIGINAL_LOCOMOTION",
    "combat_brawler_unarmed_04", "combat_unarmed_novice",
    "setPostureClientImmediate(player, POSTURE_SITTING)",
    "dot.getDotStrength(player, DOT_ID) == BLEEDING_STRENGTH",
    "removeObjVar(player, ROOT)"
)) {
    Assert ($fixture.Contains($token)) "M322 fixture token missing: $token"
}

$overlay = Join-Path $restorationRoot "patches/dsrc/320-p14-core3-meditate-lifecycle.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M322 overlay hash drifted"
foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties) {
    $key = switch ([string]$entry.Name) {
        "meditation.java" { "meditation" }
        "base_player.java" { "player" }
        "precu_meditate_fixture.java" { "fixture" }
        "command_table.tab" { "command" }
        "skills.tab" { "skills" }
        default { throw "Unexpected M322 source hash key: $($entry.Name)" }
    }
    Assert ([string]$entry.Value -ceq (Sha $paths[$key])) "M322 source hash drifted: $($entry.Name)"
}

if ($Expectation -ceq "Ready") {
    $runtime = $contract.runtimeEvidence
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$runtime.result -ceq "passed") "M322 is not Ready"
    Assert ([bool]$runtime.admission.freshAuthentication -and
        [bool]$runtime.admission.command -and
        [string]$runtime.admission.fixtureSkillBits -ceq "11111111" -and
        [int]$runtime.admission.meditateModifier -eq 15 -and
        [int]$runtime.admission.bleedingStrength -eq 100 -and
        [bool]$runtime.admission.snapshotComplete) "M322 admission proof missing"
    Assert ([bool]$runtime.execution.serverAccepted -and
        [bool]$runtime.execution.meditating -and
        [int]$runtime.execution.initialBleedingStrength -eq 100 -and
        [int]$runtime.execution.firstObservedBleedingStrength -eq 80 -and
        [int]$runtime.execution.exactReductionPerTick -eq 20) "M322 first-tick proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.allFixtureSkillsSurvived -and
        [bool]$runtime.persistence.commandSurvived -and
        [bool]$runtime.persistence.identityBoundSnapshotsSurvived -and
        [bool]$runtime.persistence.transientMeditationAbsent -and
        [bool]$runtime.persistence.transientBleedingAbsent -and
        [bool]$runtime.persistence.postRestartExecution.serverAccepted -and
        [int]$runtime.persistence.postRestartExecution.firstObservedBleedingStrength -eq 80) "M322 restart proof missing"
    Assert ([bool]$runtime.cleanup.clientInputResetBeforeRestore -and
        [bool]$runtime.cleanup.clientStandBeforeRestore -and
        [bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.fixtureAbsentAfterCleanup -and
        [bool]$runtime.isolatedClientStopped -and
        [bool]$runtime.isolatedClientFilesRestoredToM321 -and
        [int]$runtime.connectionServerCount -eq 1) "M322 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 meditate lifecycle contract passed."
