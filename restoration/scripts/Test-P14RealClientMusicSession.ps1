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
            [string]$manifest.contracts.p14RealClientMusicSession
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required real-client music source is missing: $path"
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
$performances = Import-TabTable -Path $paths.performanceTable
$skills = Import-TabTable -Path $paths.skillTable
$instruments = Import-TabTable -Path $paths.instrumentTable

Write-Host "Publish 14.1 real-client music-session checks:"

Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.startCommandSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/StartMusicCommand.h" -and
    [string]$contract.semanticReference.stopCommandSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/StopMusicCommand.h" -and
    [int]$contract.publish14Evidence.heartbeatSeconds -eq 10 -and
    [int]$contract.publish14Evidence.outroSeconds -eq 15
) -Name "p14.music-session.core3.pinned-start-stop-contract"

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
    [int]$song[0].actionPointsPerLoop -eq 28 -and
    [double]$song[0].loopDuration -eq 5.0 -and
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
) -Name "p14.music-session.data.song-instrument-and-abilities"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("STARWARS1_INDEX = 1") -and
    $fixture.Contains("SLITHERHORN_AUDIO_ID = 2") -and
    $fixture.Contains("REFERENCE_QUICKNESS = 400") -and
    $fixture.Contains("FLOURISH_REMAINING_ACTION = 91") -and
    $fixture.Contains("EXHAUSTION_BOUNDARY_ACTION = 25") -and
    $fixture.Contains("observeStopRequested") -and
    $fixture.Contains("observeStopComplete") -and
    $fixture.Contains("observeExhaustRequested") -and
    $fixture.Contains("POST_PERFORMANCE") -and
    $fixture.Contains("VAR_PERFORM_OUTRO")
) -Name "p14.music-session.fixture.real-command-outro-observation"

Assert-Contract -Condition (
    $fixture.Contains("ORIGINAL_ACTION_REGEN") -and
    $fixture.Contains("ORIGINAL_QUICKNESS") -and
    $fixture.Contains("ORIGINAL_POSTURE") -and
    $fixture.Contains("ORIGINAL_LOCOMOTION") -and
    $fixture.Contains("ORIGINAL_NOVICE") -and
    $fixture.Contains("ORIGINAL_INSTRUMENT_AUDIO") -and
    $fixture.Contains("createObject(INSTRUMENT_TEMPLATE") -and
    $fixture.Contains("equip(instrument, player)") -and
    $fixture.Contains("destroyObject(instrument)") -and
    $fixture.Contains("restoreSnapshot(player)")
) -Name "p14.music-session.fixture.identity-bound-reversible"

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
        [int]$build.clientNativeBuild.protocolVersion -eq 33 -and
        $patchHash -ceq [string]$build.overlayPatchSha256 -and
        $sourceHash -ceq [string]$build.sourceSha256.
            "precu_real_client_music_fixture.java" -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256.
                "precu_real_client_music_fixture.class")
    ) -Name "p14.music-session.build.ready-and-hashed"

    Assert-Contract -Condition (
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 33 -and
        [int]$live.authoritativeQuickness -eq 400 -and
        [int]$live.starwars1PerformanceIndex -eq 1 -and
        [int]$live.slitherhornAudioId -eq 2 -and
        [bool]$live.explicitSession.startAccepted -and
        [bool]$live.explicitSession.flourishAccepted -and
        [int]$live.explicitSession.flourishBeforeAction -eq 100 -and
        [int]$live.explicitSession.flourishAfterAction -eq 91 -and
        [bool]$live.explicitSession.stopAccepted -and
        [bool]$live.explicitSession.outroObserved -and
        [int]$live.explicitSession.actionAfterOutro -eq 66 -and
        [int]$live.explicitSession.performanceAfterOutro -eq 0 -and
        [bool]$live.automaticExhaustion.startAccepted -and
        [int]$live.automaticExhaustion.boundaryAction -eq 25 -and
        [bool]$live.automaticExhaustion.outroObserved -and
        [int]$live.automaticExhaustion.actionAfterHeartbeat -eq 25 -and
        [int]$live.automaticExhaustion.performanceAfterOutro -eq 0 -and
        [bool]$live.automaticExhaustion.inclusiveBoundaryPreserved -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [int]$live.cleanup.finalAction -eq 500 -and
        [int]$live.cleanup.finalQuickness -eq 400 -and
        [int]$live.cleanup.finalInstrumentAudioId -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup
    ) -Name "p14.music-session.live-instrument-outro-exhaust-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 real-client music-session contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 real-client music-session contract passed."
