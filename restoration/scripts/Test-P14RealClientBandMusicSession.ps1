[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot "manifest.json"
    ) -Raw | ConvertFrom-Json
$contract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.
                p14RealClientBandMusicSession
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required band-music source is missing: $path"
    }
    $paths[[string]$property.Name] = $path
}

function Import-TabTable
{
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = Get-Content -LiteralPath $Path
    $csv = @($lines[0]) + @($lines | Select-Object -Skip 2)
    return @($csv | ConvertFrom-Csv -Delimiter "`t")
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$performanceLibrary =
    Get-Content -LiteralPath $paths.performanceLibrary -Raw
$performances = Import-TabTable -Path $paths.performanceTable
$skills = Import-TabTable -Path $paths.skillTable
$instruments = Import-TabTable -Path $paths.instrumentTable

Write-Host "Publish 14.1 real-client band-music checks:"

Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.startBandSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/StartBandCommand.h" -and
    [string]$contract.semanticReference.stopBandSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/StopBandCommand.h" -and
    [string]$contract.semanticReference.bandFlourishSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/BandFlourishCommand.h" -and
    [int]$contract.publish14Evidence.bandMemberRangeMeters -eq 50 -and
    [int]$contract.publish14Evidence.outroSeconds -eq 15
) -Name "p14.band-music.core3.pinned-command-contract"

$song = @(
    $performances |
    Where-Object {
        $_.performanceName -ceq "starwars1" -and
        [int]$_.instrumentAudioId -eq 2
    }
)
$human = @(
    $skills |
    Where-Object { $_.NAME -ceq "species_human" }
)
$novice = @(
    $skills |
    Where-Object { $_.NAME -ceq "social_entertainer_novice" }
)
$slitherhorn = @(
    $instruments |
    Where-Object {
        $_.serverTemplateName -ceq
            "object/tangible/instrument/slitherhorn.iff"
    }
)
Assert-Contract -Condition (
    $song.Count -eq 1 -and
    [string]$song[0].requiredSong -ceq
        "startMusic+starwars1" -and
    [string]$song[0].requiredInstrument -ceq "slitherhorn" -and
    $human.Count -eq 1 -and
    [string]$human[0].COMMANDS -match
        "(^|,)startMusic\+starwars1(,|$)" -and
    [string]$human[0].COMMANDS -match
        "(^|,)slitherhorn(,|$)" -and
    $novice.Count -eq 1 -and
    [string]$novice[0].COMMANDS -match
        "(^|,)flourish\+1(,|$)" -and
    $slitherhorn.Count -eq 1 -and
    [int]$slitherhorn[0].instrumentAudioId -eq 2
) -Name "p14.band-music.data.song-instrument-and-abilities"

Assert-Contract -Condition (
    $performanceLibrary.Contains(
        "PERFORMANCE_BAND_MEMBER_RANGE = 50.0f") -and
    $performanceLibrary.Contains(
        "startPlaying(player, memberPerformanceIndex, performanceStartTime") -and
    $performanceLibrary.Contains(
        "applyPerformanceFlourishActionCost(player)") -and
    $performanceLibrary.Contains(
        '"OnClearBandOutro"') -and
    $performanceLibrary.Contains(
        "PERFORMANCE_OUTRO_ROUNDTIME")
) -Name "p14.band-music.retained-synchronization-cost-outro"

Assert-Contract -Condition (
    $fixture.Contains("LEADER_OID = 39008597L") -and
    $fixture.Contains("LEADER_STATION_ID = 1001") -and
    $fixture.Contains("MEMBER_OID = 44003778L") -and
    $fixture.Contains("MEMBER_STATION_ID = 91001") -and
    $fixture.Contains("group.inSameGroup(leader, member)") -and
    $fixture.Contains("getGroupLeaderId(groupId) == leader") -and
    $fixture.Contains("leaderStart == memberStart") -and
    $fixture.Contains("LEADER_QUICKNESS = 400") -and
    $fixture.Contains("MEMBER_QUICKNESS = 300") -and
    $fixture.Contains("LEADER_FLOURISH_ACTION = 91") -and
    $fixture.Contains("MEMBER_FLOURISH_ACTION = 90") -and
    $fixture.Contains("LEADER_STOPPED_ACTION = 66") -and
    $fixture.Contains("MEMBER_STOPPED_ACTION = 62") -and
    $fixture.Contains("groupStillActiveUseRealClientDisband")
) -Name "p14.band-music.fixture.group-sync-and-real-client-boundary"

Assert-Contract -Condition (
    $fixture.Contains("ORIGINAL_LOCATION") -and
    $fixture.Contains("ORIGINAL_ACTION_REGEN") -and
    $fixture.Contains("ORIGINAL_QUICKNESS") -and
    $fixture.Contains("ORIGINAL_POSTURE") -and
    $fixture.Contains("ORIGINAL_LOCOMOTION") -and
    $fixture.Contains("ORIGINAL_NOVICE") -and
    $fixture.Contains("ORIGINAL_INSTRUMENT_AUDIO") -and
    $fixture.Contains("createObject(INSTRUMENT_TEMPLATE") -and
    $fixture.Contains("destroyObject(instrument)") -and
    $fixture.Contains("restorePair(leader, member)")
) -Name "p14.band-music.fixture.two-player-reversible-preimage"

if ($Expectation -ceq "Ready")
{
    $build = $contract.buildEvidence
    $live = $contract.liveEvidence
    $patchPath =
        Join-Path $restorationRoot (
            [string]$build.overlayPatch -replace "^restoration/", ""
        )
    $sourceHash =
        (Get-FileHash -LiteralPath $paths.fixture -Algorithm SHA256).
            Hash.ToLowerInvariant()
    $patchHash =
        (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).
            Hash.ToLowerInvariant()

    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$build.result -ceq "passed" -and
        [string]$build.cleanApplyCheck -ceq "passed" -and
        [string]$build.reverseApplyCheck -ceq "passed" -and
        [int]$build.changedFileCount -eq 1 -and
        [string]$build.serverJavaBuild.result -ceq "passed" -and
        [string]$build.clientNativeBuild.result -ceq "passed" -and
        [int]$build.clientNativeBuild.protocolVersion -eq 34 -and
        $patchHash -ceq [string]$build.overlayPatchSha256 -and
        $sourceHash -ceq [string]$build.sourceSha256.
            "precu_real_client_band_music_fixture.java" -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256.
                "precu_real_client_band_music_fixture.class")
    ) -Name "p14.band-music.build.ready-and-hashed"

    Assert-Contract -Condition (
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 34 -and
        [long]$live.leader.playerOid -eq 39008597 -and
        [long]$live.member.playerOid -eq 44003778 -and
        [bool]$live.groupLifecycle.inviteAccepted -and
        [bool]$live.groupLifecycle.joinAccepted -and
        [bool]$live.groupLifecycle.sameGroupObserved -and
        [bool]$live.bandSession.startAccepted -and
        [bool]$live.bandSession.synchronizedStartTime -and
        [int]$live.bandSession.leaderActionAfterFlourish -eq 91 -and
        [int]$live.bandSession.memberActionAfterFlourish -eq 90 -and
        [bool]$live.bandSession.stopAccepted -and
        [bool]$live.bandSession.bothOutrosObserved -and
        [int]$live.bandSession.leaderActionAfterOutro -eq 66 -and
        [int]$live.bandSession.memberActionAfterOutro -eq 62 -and
        [bool]$live.groupLifecycle.disbandAccepted -and
        [bool]$live.groupLifecycle.ungroupedObserved -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup -and
        [bool]$live.bothClientBridgesHealthyAfterCleanup
    ) -Name "p14.band-music.live-group-sync-cost-outro-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 real-client band-music contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 real-client band-music contract passed."
