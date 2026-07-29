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
                p14IncapacitationRecoveryLifecycle
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] =
        Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required incapacitation source is missing: $path"
    }
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

$pclib = Get-Content -LiteralPath $paths.playerLibrary -Raw
$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw

Write-Host "Publish 14.1 incapacitation/recovery checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [int]$contract.semanticReference.rollingWindowSeconds -eq 600 -and
    [int]$contract.semanticReference.automaticDeathCount -eq 3 -and
    [int]$contract.semanticReference.timerFormula.
        boundarySeconds."-5" -eq 1 -and
    [int]$contract.semanticReference.timerFormula.
        boundarySeconds."-500" -eq 60) `
    -Name "p14.incap.core3.pinned-window-threshold-and-timer"

Assert-Contract -Condition (
    $pclib.Contains(
        'VAR_PRECU_INCAPACITATION_TIMES =') -and
    $pclib.Contains(
        '"combat.precuIncapacitationTimes"') -and
    $pclib.Contains(
        "PRECU_INCAPACITATION_WINDOW = 600") -and
    $pclib.Contains(
        "PRECU_INCAPACITATION_LIMIT = 3") -and
    $pclib.Contains("timestamp > oldestAllowed") -and
    $pclib.Contains("updated[index] = now")) `
    -Name "p14.incap.runtime.rolling-ten-minute-timestamp-vector"

Assert-Contract -Condition (
    $pclib.Contains(
        "calculatePrecuIncapacitationTimer") -and
    $pclib.Contains("if (value < 5)") -and
    $pclib.Contains("int recoveryTime = value / 5;") -and
    $pclib.Contains(
        "return recoveryTime > 60 ? 60 : recoveryTime;")) `
    -Name "p14.incap.runtime.core3-recovery-timer-formula"

Assert-Contract -Condition (
    $basePlayer.Contains(
        "pclib.addPrecuIncapacitationTime(self)") -and
    $basePlayer.Contains(
        "pclib.PRECU_INCAPACITATION_LIMIT") -and
    $basePlayer.Contains(
        "pclib.killPlayer(self, killer, true)") -and
    -not $basePlayer.Contains(
        'buff.applyBuff(self, "incapWeaken")') -and
    $basePlayer.Contains(
        'buff.removeBuff(self, "incapWeaken")')) `
    -Name "p14.incap.runtime.third-incap-death-and-nge-weakness-retired"

Assert-Contract -Condition (
    $basePlayer.Contains(
        "Math.min(condition, getAttrib(self, ACTION))") -and
    $basePlayer.Contains(
        "Math.min(condition, getAttrib(self, MIND))") -and
    $basePlayer.Contains(
        'utils.hasScriptVar(self, "incap.timeStamp")') -and
    $basePlayer.Contains(
        'params.getInt("recoveryTime")') -and
    $basePlayer.Contains(
        "getAttrib(self, HEALTH) <= 0") -and
    $basePlayer.Contains(
        "getAttrib(self, ACTION) <= 0") -and
    $basePlayer.Contains(
        "getAttrib(self, MIND) <= 0") -and
    $basePlayer.Contains("setAttrib(self, MIND, 1)")) `
    -Name "p14.incap.runtime.any-primary-recovery-and-stale-task-guard"

Assert-Contract -Condition (
    $pclib.Contains(
        "clearPrecuIncapacitationTimes(player);") -and
    $pclib.Contains(
        'utils.removeScriptVar(player, "incap.timeStamp");') -and
    [bool]$contract.runtimeContract.
        nativePostureCallbacksPreserved) `
    -Name "p14.incap.runtime.death-reset-and-native-recap-callback"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 44003778L") -and
    $fixture.Contains("PLAYER_STATION_ID = 91001") -and
    $fixture.Contains('"incapOne"') -and
    $fixture.Contains('"incapTwo"') -and
    $fixture.Contains('"incapThree"') -and
    $fixture.Contains("HEALTH,") -and
    $fixture.Contains("ACTION,") -and
    $fixture.Contains("MIND,") -and
    $fixture.Contains("pclib.resurrectPlayer(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    -Name "p14.incap.fixture.identity-bound-three-pool-and-reversible"

Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    [string]$contract.buildEvidence.sourceCommit -ceq
        "b9e9986d6" -and
    [string]$contract.buildEvidence.patchSha256 -ceq
        "2452da7334a6220b60b1565ce7f08f858b3491ed4fef1474236cfdb36541de3c" -and
    -not [string]::IsNullOrWhiteSpace(
        [string]$contract.buildEvidence.compiledSha256.
            "precu_incapacitation_recovery_fixture.class")) `
    -Name "p14.incap.build.clean-java-evidence"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 29 -and
        [bool]$contract.publicationBoundary.
            productionGameplayCodeChanged -and
        -not [bool]$contract.publicationBoundary.
            clientToolsChanged -and
        -not [bool]$contract.publicationBoundary.
            clientAssetsChanged) `
        -Name "p14.incap.status.ready-server-only-production-repair"
    Assert-Contract -Condition (
        [int]$live.timerProbe.timer0 -eq 5 -and
        [int]$live.timerProbe.timerMinus4 -eq 5 -and
        [int]$live.timerProbe.timerMinus5 -eq 1 -and
        [int]$live.timerProbe.timerMinus25 -eq 5 -and
        [int]$live.timerProbe.timerMinus100 -eq 20 -and
        [int]$live.timerProbe.timerMinus500 -eq 60) `
        -Name "p14.incap.live.timer-boundaries"
    Assert-Contract -Condition (
        [int]$live.firstIncap.recoverySeconds -eq 5 -and
        [int]$live.firstIncap.counter -eq 1 -and
        [bool]$live.firstIncap.recovered -and
        [int]$live.firstIncap.healthAfter -eq 1 -and
        [int]$live.secondIncap.recoverySeconds -eq 20 -and
        [int]$live.secondIncap.counter -eq 2 -and
        [bool]$live.secondIncap.recovered -and
        [int]$live.secondIncap.actionAfter -eq 1) `
        -Name "p14.incap.live.health-action-recovery-and-counter"
    Assert-Contract -Condition (
        [bool]$live.thirdIncap.automaticDeath -and
        [int]$live.thirdIncap.counterAfterDeath -eq 0 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.incap.live.third-mind-incap-death-reset-and-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 incapacitation contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 incapacitation/recovery contract passed."
