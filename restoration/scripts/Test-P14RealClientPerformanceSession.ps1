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
            [string]$manifest.contracts.p14RealClientPerformanceSession
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required real-client performance source is missing: $path"
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

Write-Host "Publish 14.1 real-client performance-session checks:"

Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.startCommandSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/StartDanceCommand.h" -and
    [string]$contract.semanticReference.stopCommandSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/StopDanceCommand.h" -and
    [int]$contract.publish14Evidence.performanceIndex -eq 283 -and
    [int]$contract.publish14Evidence.loopSeconds -eq 10
) -Name "p14.performance-session.core3.pinned-start-stop-contract"

$rhythmic = @(
    $performances |
    Where-Object {
        $_.performanceName -ceq "rhythmic" -and
        $_.type -ceq "dance"
    }
)
$novice = @(
    $skills |
    Where-Object { $_.NAME -ceq "social_entertainer_novice" }
)
Assert-Contract -Condition (
    $rhythmic.Count -eq 1 -and
    [string]$rhythmic[0].requiredDance -ceq
        "startDance+rhythmic" -and
    [int]$rhythmic[0].actionPointsPerLoop -eq 28 -and
    [double]$rhythmic[0].loopDuration -eq 10.0 -and
    $novice.Count -eq 1 -and
    [string]$novice[0].COMMANDS -match
        "(^|,)startDance\+rhythmic(,|$)" -and
    [string]$novice[0].COMMANDS -match
        "(^|,)flourish\+1(,|$)"
) -Name "p14.performance-session.data.rhythmic-and-novice-grants"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("RHYTHMIC_INDEX = 283") -and
    $fixture.Contains("REFERENCE_QUICKNESS = 400") -and
    $fixture.Contains("FLOURISH_REMAINING_ACTION = 91") -and
    $fixture.Contains("EXHAUSTION_BOUNDARY_ACTION = 25") -and
    $fixture.Contains("observeStart") -and
    $fixture.Contains("observeFlourish") -and
    $fixture.Contains("observeStop") -and
    $fixture.Contains("observeExhaustStart") -and
    $fixture.Contains("observeExhausted")
) -Name "p14.performance-session.fixture.real-command-observation"

Assert-Contract -Condition (
    $fixture.Contains("ORIGINAL_ACTION_REGEN") -and
    $fixture.Contains("ORIGINAL_POSTURE") -and
    $fixture.Contains("ORIGINAL_LOCOMOTION") -and
    $fixture.Contains("ORIGINAL_NOVICE") -and
    $fixture.Contains("restoreSnapshot(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)") -and
    $fixture.Contains("VAR_PERFORM_NO_GROUP_DANCE") -and
    $fixture.Contains("detachScript(")
) -Name "p14.performance-session.fixture.identity-bound-reversible"

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
        [int]$build.clientNativeBuild.protocolVersion -eq 32 -and
        $patchHash -ceq [string]$build.overlayPatchSha256 -and
        $sourceHash -ceq [string]$build.sourceSha256.
            "precu_real_client_performance_fixture.java" -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256.
                "precu_real_client_performance_fixture.class")
    ) -Name "p14.performance-session.build.ready-and-hashed"

    Assert-Contract -Condition (
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 32 -and
        [int]$live.authoritativeQuickness -eq 400 -and
        [int]$live.rhythmicPerformanceIndex -eq 283 -and
        [bool]$live.explicitSession.startAccepted -and
        [bool]$live.explicitSession.flourishAccepted -and
        [int]$live.explicitSession.flourishBeforeAction -eq 100 -and
        [int]$live.explicitSession.flourishAfterAction -eq 91 -and
        [bool]$live.explicitSession.stopAccepted -and
        [int]$live.explicitSession.performanceAfterStop -eq 0 -and
        -not [bool]$live.explicitSession.heartbeatScriptAfterStop -and
        [bool]$live.automaticExhaustion.startAccepted -and
        [int]$live.automaticExhaustion.boundaryAction -eq 25 -and
        [int]$live.automaticExhaustion.performanceAfterHeartbeat -eq 0 -and
        [int]$live.automaticExhaustion.actionAfterHeartbeat -eq 25 -and
        [bool]$live.automaticExhaustion.inclusiveBoundaryPreserved -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [int]$live.cleanup.finalAction -eq 500 -and
        [int]$live.cleanup.finalPerformanceIndex -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup
    ) -Name "p14.performance-session.live.start-flourish-stop-exhaust-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 real-client performance-session contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 real-client performance-session contract passed."
