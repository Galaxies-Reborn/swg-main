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
            [string]$manifest.contracts.p14CloneDecayReport
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$cloningPath =
    Join-Path $source ([string]$contract.sourceFiles.cloningLibrary)
$basePlayerPath =
    Join-Path $source ([string]$contract.sourceFiles.basePlayer)
$fixturePath =
    Join-Path $source ([string]$contract.sourceFiles.fixture)
foreach ($path in @($cloningPath, $basePlayerPath, $fixturePath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required clone-decay-report source is missing: $path"
    }
}

$cloning = Get-Content -LiteralPath $cloningPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$decayStart =
    $cloning.IndexOf(
        "public static void applyPrecuCloneItemDecay",
        [System.StringComparison]::Ordinal)
$decayEnd =
    $cloning.IndexOf(
        "public static obj_id[] getAllRepairItems",
        [System.StringComparison]::Ordinal)
if ($decayStart -lt 0 -or $decayEnd -le $decayStart)
{
    throw "Unable to isolate the clone-decay/report implementation window."
}
$decayWindow =
    $cloning.Substring($decayStart, $decayEnd - $decayStart)

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

Write-Host "Publish 14.1 clone decay-report checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [int]$contract.semanticReference.deathType -eq 0 -and
    [string]$contract.semanticReference.windowType -ceq
        "CLONE_REQUEST_DECAY" -and
    [bool]$contract.semanticReference.noReportForPlayerDeathBlow) `
    -Name "p14.clone-decay-report.core3.pinned-pve-only-contract"

Assert-Contract -Condition (
    $cloning.Contains(
        'PRECU_DECAY_REPORT_TITLE =') -and
    $cloning.Contains(
        '"DECAY REPORT"') -and
    $cloning.Contains(
        '"The following report summarizes the status of your items "') -and
    $cloning.Contains(
        '"after the decay event."') -and
    $cloning.Contains(
        '"\\#00FF00DECAYED ITEMS"')) `
    -Name "p14.clone-decay-report.runtime.authentic-copy-and-header"

$damageIndex =
    $decayWindow.IndexOf(
        "pclib.damageAndDecayItem(",
        [System.StringComparison]::Ordinal)
$recordIndex =
    $decayWindow.IndexOf(
        "decayedItems = utils.addElement(decayedItems, item)",
        [System.StringComparison]::Ordinal)
$showIndex =
    $decayWindow.IndexOf(
        "showPrecuCloneDecayReport(player, decayedItems)",
        [System.StringComparison]::Ordinal)
Assert-Contract -Condition (
    $decayWindow.Contains("if (!isDamagedOnClone(player, item))") -and
    $damageIndex -ge 0 -and
    $recordIndex -gt $damageIndex -and
    $showIndex -gt $recordIndex) `
    -Name "p14.clone-decay-report.runtime.only-actually-decayed-items"

Assert-Contract -Condition (
    $decayWindow.Contains(
        "utils.hasScriptVar(player, PRECU_DECAY_REPORT_SUI)") -and
    $decayWindow.Contains("forceCloseSUIPage(") -and
    $decayWindow.Contains(
        "utils.removeScriptVarTree(player, PRECU_DECAY_REPORT_ROOT)") -and
    $decayWindow.Contains(
        '"handleDecayReport"')) `
    -Name "p14.clone-decay-report.runtime.stale-page-and-handler"

Assert-Contract -Condition (
    $decayWindow.Contains("sui.listboxButtonSetup(pid, sui.OK_ONLY)") -and
    $decayWindow.Contains(
        "PRECU_DECAY_REPORT_HEADER") -and
    $decayWindow.Contains(
        "100.0f * hitpoints / maxHitpoints") -and
    $decayWindow.Contains(
        '" (@" + conditionPercent + "%)"') -and
    $decayWindow.Contains("showSUIPage(pid)") -and
    $decayWindow.Contains("flushSUIPage(pid)") -and
    $decayWindow.Contains(
        "utils.setScriptVar(player, PRECU_DECAY_REPORT_SUI, pid)")) `
    -Name "p14.clone-decay-report.runtime.post-decay-rows-and-real-list"

Assert-Contract -Condition (
    $basePlayer.Contains(
        "public int handleDecayReport(") -and
    $basePlayer.Contains(
        'utils.removeScriptVarTree(self, "decayReport")')) `
    -Name "p14.clone-decay-report.runtime.residue-free-close-handler"

Assert-Contract -Condition (
    $fixture.Contains(
        '" decayReportActive=" +') -and
    $fixture.Contains(
        "cloninglib.PRECU_DECAY_REPORT_SUI") -and
    $fixture.Contains(
        "cloninglib.PRECU_DECAY_REPORT_ROOT") -and
    $fixture.Contains("forceCloseSUIPage(")) `
    -Name "p14.clone-decay-report.fixture.observable-and-owned-cleanup"

if ($Expectation -ceq "Ready")
{
    $build = $contract.buildEvidence
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$build.result -ceq "passed" -and
        [int]$build.changedSourceCount -eq 2 -and
        @($build.buildPasses).Count -eq 2 -and
        [int]$build.buildPasses[0].compiledSourceCount -eq 1 -and
        [int]$build.buildPasses[1].compiledSourceCount -eq 1 -and
        [string]$build.buildPasses[0].result -ceq "passed" -and
        [string]$build.buildPasses[1].result -ceq "passed" -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256."cloninglib.class") -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256.
                "precu_clone_penalty_fixture.class") -and
        [string]$build.runtimeLoad.result -ceq "passed" -and
        [bool]$build.runtimeLoad.fixtureObserverLoaded -and
        [string]$build.finalValidation.result -ceq "passed" -and
        [int]$build.finalValidation.compiledSourceCount -eq 0) `
        -Name "p14.clone-decay-report.build.ready-and-compiled"
    Assert-Contract -Condition (
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 31 -and
        [bool]$live.realListRendered -and
        [bool]$live.authenticTitle -and
        [bool]$live.authenticPrompt -and
        [bool]$live.greenHeader -and
        [int]$live.insuredConditionPercent -eq 99 -and
        [int]$live.uninsuredConditionPercent -eq 95 -and
        [bool]$live.closeRemovedScriptVars -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.clone-decay-report.live.client-render-close-and-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 clone decay-report contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 clone decay-report contract passed."
