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
            [string]$manifest.contracts.p14PerformanceActionDrain
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required performance Action-drain source is missing: $path"
    }
    $paths[[string]$property.Name] = $path
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

$performance =
    Get-Content -LiteralPath $paths.performanceLibrary -Raw
$dance = Get-Content -LiteralPath $paths.activeDance -Raw
$music = Get-Content -LiteralPath $paths.activeMusic -Raw
$juggle = Get-Content -LiteralPath $paths.activeJuggle -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw

Write-Host "Publish 14.1 performance Action-drain checks:"

Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [int]$contract.semanticReference.heartbeatSeconds -eq 10 -and
    [string]$contract.semanticReference.damageChannel -ceq "Action" -and
    [string]$contract.semanticReference.exhaustionRule -ceq
        "reject when current Action is less than or equal to calculated cost"
) -Name "p14.performance-action.core3.pinned-contract"

Assert-Contract -Condition (
    $performance.Contains(
        "baseCost -") -and
    $performance.Contains(
        "(getAttrib(actor, QUICKNESS) - 300)") -and
    $performance.Contains(
        "1200.0f) * baseCost") -and
    $performance.Contains(
        "return (int)adjustedCost;") -and
    $performance.Contains(
        "getAttrib(actor, ACTION) <= actionCost")
) -Name "p14.performance-action.loop.quickness-truncate-boundary"

Assert-Contract -Condition (
    $performance.Contains(
        "(int)(getAttrib(actor, QUICKNESS) / 35.0f)") -and
    $performance.Contains(
        "float flourishActionDrain = baseActionDrain / 2.0f") -and
    $performance.Contains(
        "(flourishActionDrain * 10.0f + 0.5f) / 10.0f") -and
    $performance.Contains(
        "applyPerformanceFlourishActionCost(actor)") -and
    $performance.Contains(
        "applyPerformanceFlourishActionCost(player)")
) -Name "p14.performance-action.flourish.distinct-solo-band-formula"

Assert-Contract -Condition (
    $dance.Contains(
        "performance.applyPerformanceLoopActionCost(self)") -and
    $music.Contains(
        "performance.applyPerformanceLoopActionCost(self)") -and
    $juggle.Contains(
        "performance.applyPerformanceLoopActionCost(self)") -and
    -not $performance.Contains("applyPerformanceActionCost(") -and
    -not $dance.Contains("applyPerformanceActionCost(") -and
    -not $music.Contains("applyPerformanceActionCost(") -and
    -not $juggle.Contains("applyPerformanceActionCost(")
) -Name "p14.performance-action.runtime.all-heartbeats-no-nge-stub"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("REFERENCE_QUICKNESS = 400") -and
    $fixture.Contains("loopCost == 25") -and
    $fixture.Contains("loopRemaining == 75") -and
    $fixture.Contains("flourishCost == 9") -and
    $fixture.Contains("flourishRemaining == 91") -and
    $fixture.Contains("finally") -and
    $fixture.Contains("restored = restoreSnapshot(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")
) -Name "p14.performance-action.fixture.identity-bound-reversible"

if ($Expectation -ceq "Ready")
{
    $build = $contract.buildEvidence
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$build.result -ceq "passed" -and
        [string]$build.cleanApplyCheck -ceq "passed" -and
        [string]$build.reverseApplyCheck -ceq "passed" -and
        [int]$build.changedFileCount -eq 5 -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256."performance.class") -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256.
                "precu_performance_action_drain_fixture.class")
    ) -Name "p14.performance-action.build.ready-and-compiled"

    Assert-Contract -Condition (
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 31 -and
        [int]$live.basicDancePerformanceIndex -eq 281 -and
        [int]$live.authoritativeQuickness -eq 400 -and
        [int]$live.loop.cost -eq 25 -and
        [int]$live.loop.afterAction -eq 75 -and
        [bool]$live.loop.exactCostRejected -and
        [int]$live.flourish.cost -eq 9 -and
        [int]$live.flourish.afterAction -eq 91 -and
        [bool]$live.flourish.exactCostRejected -and
        [bool]$live.interruptedLifecycleRecovery.restored -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [int]$live.cleanup.finalAction -eq 500 -and
        [int]$live.cleanup.finalQuickness -eq 400 -and
        [int]$live.cleanup.finalPerformanceIndex -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup
    ) -Name "p14.performance-action.live.exact-cost-boundary-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 performance Action-drain contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 performance Action-drain contract passed."
