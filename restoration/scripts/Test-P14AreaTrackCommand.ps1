[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (
    Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot (
    [string]$manifest.contracts.p14AreaTrackCommand)) -Raw |
    ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}
function Get-Row([string]$Path, [string]$Key)
{
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $matches = @($lines | Select-Object -Skip 2 | Where-Object {
        (($_ -split "`t", -1)[0]) -ceq $Key })
    if ($matches.Count -ne 1) { return $null }
    $values = $matches[0] -split "`t", -1
    $row = @{}
    for ($index = 0; $index -lt $header.Count; ++$index)
        { $row[$header[$index]] = $values[$index] }
    [pscustomobject]@{Header=$header; Values=$values; Row=$row}
}
function Get-Sha256([string]$Path)
{
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.area-track.source.$($entry.Key)"
}

Write-Host "Publish 14.1 Area Track checks:"
Assert-Contract (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.command -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/AreatrackCommand.h" -and
    [string]$contract.semanticReference.choiceCallback -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/AreaTrackSuiCallback.h" -and
    [string]$contract.semanticReference.delayedTask -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/AreaTrackTask.h") `
    "p14.area-track.core3.pinned-three-part-lifecycle"

$command = Get-Row $paths.commandTable "areatrack"
Assert-Contract ($null -ne $command) "p14.area-track.command.unique"
if ($null -ne $command)
{
    Assert-Contract ($command.Header.Count -eq 94 -and
        $command.Values.Count -eq 94) "p14.area-track.command.columns-94"
    Assert-Contract ($command.Row.commandName -ceq "areatrack" -and
        $command.Row.scriptHook -ceq "areatrack" -and
        $command.Row.failScriptHook -ceq "failAreatrack" -and
        $command.Row.characterAbility -ceq "areatrack" -and
        $command.Row.target -ceq "other" -and
        $command.Row.targetType -ceq "none") `
        "p14.area-track.command.dispatch"
    Assert-Contract ($command.Row.defaultTime -ceq "1" -and
        $command.Row.addToCombatQueue -ceq "0" -and
        $command.Row.visible -ceq "2" -and
        $command.Row.cooldownGroup -ceq "defaultCooldownGroup") `
        "p14.area-track.command.timing-visibility"
}

$ranger = Get-Row $paths.skillTable "outdoors_ranger_novice"
Assert-Contract ($null -ne $ranger -and
    $ranger.Row.COMMANDS -match '(^|,|\")areatrack(,|\"|$)') `
    "p14.area-track.skill.ranger-novice-ownership"

$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$runnerPath = Join-Path $restorationRoot `
    "scripts/Invoke-P14AreaTrackRuntime.ps1"
$runner = Get-Content -LiteralPath $runnerPath -Raw
$patchPath = Join-Path $restorationRoot `
    "patches/dsrc/250-p14-area-track-command.patch"

Assert-Contract ($basePlayer.Contains("public int areatrack(") -and
    $basePlayer.Contains("public int failAreatrack(") -and
    $basePlayer.Contains('hasSkill(self, "outdoors_ranger_novice")') -and
    $basePlayer.Contains("@cmd_n:areatrack_animal") -and
    $basePlayer.Contains("@cmd_n:areatrack_npc") -and
    $basePlayer.Contains("@cmd_n:areatrack_player") -and
    $basePlayer.Contains("@skl_use:scan_type_d")) `
    "p14.area-track.production.outdoor-tiered-option-sui"
Assert-Contract ($basePlayer.Contains("PRECU_AREA_TRACK_RANGE = 512.0f") -and
    $basePlayer.Contains("PRECU_AREA_TRACK_MOVE_LIMIT = 1.0f") -and
    $basePlayer.Contains("PRECU_AREA_TRACK_DELAY_SECONDS = 6") -and
    $basePlayer.Contains('messageTo(self, "handlePrecuAreaTrackScan"') -and
    $basePlayer.Contains("utils.getDistance2D(initial, current)") -and
    $basePlayer.Contains("ai_lib.isInCombat(self)") -and
    $basePlayer.Contains("getCreaturesInRange(self,") -and
    $basePlayer.Contains("stealth.hasInvisibleBuff(creature)")) `
    "p14.area-track.production.delayed-filtered-scan"
Assert-Contract ($basePlayer.Contains('hasSkill(self, "outdoors_ranger_harvest_01")') -and
    $basePlayer.Contains('hasSkill(self, "outdoors_ranger_harvest_02")') -and
    $basePlayer.Contains('hasSkill(self, "outdoors_ranger_harvest_03")') -and
    $basePlayer.Contains('hasSkill(self, "outdoors_ranger_harvest_04")') -and
    $basePlayer.Contains('return "east"') -and
    $basePlayer.Contains("@skl_use:scan_results_d") -and
    $basePlayer.Contains("SID_SYS_SCAN_NOTHING")) `
    "p14.area-track.production.direction-distance-results"
Assert-Contract ($fixture.Contains("PLAYER_OID = 44003778L") -and
    $fixture.Contains("PLAYER_STATION_ID = 91001") -and
    $fixture.Contains('CREATURE_TYPE = "worrt"') -and
    $fixture.Contains("targetLocation.x += 10.0f") -and
    $fixture.Contains("forceCloseSUIPage(pid)") -and
    $fixture.Contains("destroyObject(target)") -and
    $fixture.Contains("revokeSkills(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)") -and
    $fixture.Contains("alreadyClean=true restored=true")) `
    "p14.area-track.fixture.identity-bound-reversible-east-target"
Assert-Contract ($runner.Contains('Invoke-ClientAction "QueueAreaTrack"') -and
    $runner.Contains('Invoke-ClientAction "SelectAreaTrackType" 0') -and
    $runner.Contains('Wait-Field $lifecycle "outcome" "optionsOpen"') -and
    $runner.Contains('Wait-Field $lifecycle "outcome" "resultsOpen" 18') -and
    $runner.Contains('$completed - $started -lt 5') -and
    $runner.Contains('(Get-Field $results "fixtureDirection") -cne "east"')) `
    "p14.area-track.runner.real-client-delayed-proof"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.area-track.patch.present"

$hashes = $contract.buildEvidence.sourceSha256
Assert-Contract ((Get-Sha256 $paths.commandTable) -ceq
    [string]$hashes.'command_table.tab') "p14.area-track.hash.command-table"
Assert-Contract ((Get-Sha256 $paths.skillTable) -ceq
    [string]$hashes.'skills.tab') "p14.area-track.hash.skills"
Assert-Contract ((Get-Sha256 $paths.basePlayer) -ceq
    [string]$hashes.'base_player.java') "p14.area-track.hash.base-player"
Assert-Contract ((Get-Sha256 $paths.liveFixture) -ceq
    [string]$hashes.'precu_area_track_command_fixture.java') `
    "p14.area-track.hash.fixture"
Assert-Contract ((Get-Sha256 $patchPath) -ceq
    [string]$contract.buildEvidence.patchSha256) `
    "p14.area-track.hash.patch"
Assert-Contract ((Get-Sha256 $runnerPath) -ceq
    [string]$contract.buildEvidence.runtimeRunnerSha256) `
    "p14.area-track.hash.runner"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 165) `
        "p14.area-track.status.ready"
    Assert-Contract ([int]$live.options.handlerCalls -eq 1 -and
        [string]$live.options.outcome -ceq "optionsOpen" -and
        [int]$live.options.optionCount -eq 3 -and
        [string]$live.scan.outcome -ceq "resultsOpen" -and
        [bool]$live.scan.fixtureTargetFound -and
        [string]$live.scan.fixtureDirection -ceq "east" -and
        [int]$live.scan.fixtureDistanceMeters -eq 10 -and
        [int]$live.scan.scanCompletedAt - [int]$live.scan.scanStartedAt -ge 5) `
        "p14.area-track.live.real-delayed-animal-scan"
    Assert-Contract ([bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [int]$live.cleanup.normalizedDatabaseMarkerCount -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.proofClientStopped -and
        [bool]$live.userClientUntouched) `
        "p14.area-track.live.cleanup-health-process-boundary"
}
if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Area Track contract failed: $($failures -join ', ')"
}
Write-Host ""
Write-Host "Publish 14.1 Area Track command contract passed."
