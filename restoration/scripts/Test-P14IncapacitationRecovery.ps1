[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Build", "Ready")]
    [string]$Expectation = "Source"
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
$nineAttributeContract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.p14NineAttributeRuntime
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

function Get-BracedBlock
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Signature
    )

    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $openBrace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($openBrace -lt 0) { return "" }
    $depth = 0
    for ($index = $openBrace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

$pclib = Get-Content -LiteralPath $paths.playerLibrary -Raw
$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$combatLibrary = Get-Content -LiteralPath $paths.combatLibrary -Raw

Write-Host "Publish 14.1 incapacitation/recovery checks:"
Assert-Contract -Condition (
    @("implemented-build-pending", "ready") -contains [string]$contract.status -and
    [string]$contract.runtimeContract.legacyCombatHealthRegenScriptVar -ceq
        "fltNonCombatHealthRegen" -and
    [string]$contract.runtimeContract.timerReadiness -match "incap.timeStamp") `
    -Name "p14.incap.contract.status-and-regeneration-timer-dependency"
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

$doCombatDebuffs = Get-BracedBlock -Text $combatLibrary `
    -Signature "public static void doCombatDebuffs(obj_id self)"
$clearCombatDebuffs = Get-BracedBlock -Text $combatLibrary `
    -Signature "public static boolean clearCombatDebuffs(obj_id self)"
$recapacitationDelay = Get-BracedBlock -Text $basePlayer `
    -Signature "public int recapacitationDelay(obj_id self, dictionary params)"
$staleVar = '"fltNonCombatHealthRegen"'
$staleRemove = 'utils.removeScriptVar(self, "fltNonCombatHealthRegen");'
Assert-Contract -Condition (
    [regex]::Matches($combatLibrary, [regex]::Escape($staleVar)).Count -eq 2 -and
    [regex]::Matches($combatLibrary, [regex]::Escape($staleRemove)).Count -eq 2 -and
    -not [regex]::IsMatch($combatLibrary,
        'setRegenRate\s*\([^;\r\n]*\bHEALTH\b|setScriptVar\s*\([^;\r\n]*"fltNonCombatHealthRegen"') -and
    -not $combatLibrary.Contains("getHealthRegenRate(self)") -and
    -not $combatLibrary.Contains('getFloatScriptVar(self, "fltNonCombatHealthRegen")')) `
    -Name "p14.incap.regeneration.no-combat-health-override-writer"
Assert-Contract -Condition (
    [regex]::Matches($doCombatDebuffs, [regex]::Escape($staleRemove)).Count -eq 1 -and
    [regex]::Matches($clearCombatDebuffs, [regex]::Escape($staleRemove)).Count -eq 1 -and
    -not $doCombatDebuffs.Contains("hasScriptVar") -and
    -not $clearCombatDebuffs.Contains("hasScriptVar") -and
    $clearCombatDebuffs.Contains(
        'return getGameTime() > utils.getIntScriptVar(self, "incap.timeStamp");')) `
    -Name "p14.incap.regeneration.stale-var-remove-only-and-readiness-independent"
$guardIndex = $recapacitationDelay.IndexOf(
    '!utils.hasScriptVar(self, "incap.timeStamp")', [StringComparison]::Ordinal)
$clearIndex = $recapacitationDelay.IndexOf(
    'if (!combat.clearCombatDebuffs(self))', [StringComparison]::Ordinal)
$recoverIndex = $recapacitationDelay.IndexOf(
    'if (getAttrib(self, HEALTH) <= 0)', [StringComparison]::Ordinal)
Assert-Contract -Condition (
    $guardIndex -ge 0 -and $clearIndex -gt $guardIndex -and
    $recapacitationDelay.Contains('params.getInt("recoveryTime")') -and
    [regex]::IsMatch($recapacitationDelay,
        'utils\.getIntScriptVar\s*\(\s*self,\s*"incap\.timeStamp"\s*\)') -and
    $recapacitationDelay.Contains('"recapacitationDelay"') -and
    $recoverIndex -gt $clearIndex) `
    -Name "p14.incap.runtime.timestamp-guard-readiness-requeue-before-recovery"

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

$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$combatHash = (Get-FileHash -LiteralPath $paths.combatLibrary -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Contract -Condition (
    $dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
    $combatHash -ceq [string]$contract.buildEvidence.sourceSha256.combatLibrary) `
    -Name "p14.incap.source.direct-pin-and-combat-library-hash"

if ($Expectation -ceq "Source")
{
    Assert-Contract -Condition (
        ([string]$contract.status -ceq "implemented-build-pending" -and
            [string]$contract.buildEvidence.result -ceq "pending" -and
            @($contract.requiredBeforeReady).Count -ge 1) -or
        ([string]$contract.status -ceq "ready" -and
            [string]$contract.buildEvidence.result -ceq "passed" -and
            @($contract.requiredBeforeReady).Count -eq 0)) `
        -Name "p14.incap.status.truthful-source-or-ready-transition"
}
else
{
    $delegated = $contract.buildEvidence.delegatedDeploymentEvidence
    $delegatedArtifacts = @($delegated.authenticatedArtifacts | ForEach-Object { [string]$_ })
    $expectedDelegatedArtifacts = @(
        "combat.class",
        "CreatureObject.cpp.o",
        "libserverGame.a",
        "SwgGameServer"
    )
    $nineCombatClass = $nineAttributeContract.buildEvidence.regenerationCompiledJavaArtifacts.artifacts."combat.class"
    Assert-Contract -Condition (
        [string]$delegated.contract -ceq "contracts/p14-nine-attribute-runtime.json" -and
        [string]$delegated.expectation -ceq "Build" -and
        ($delegatedArtifacts -join "`n") -ceq ($expectedDelegatedArtifacts -join "`n") -and
        [bool]$delegated.includesExactLiveProcessAndPostStartLogAudit -and
        [string]$delegated.result -ceq "passed" -and
        [string]$contract.buildEvidence.currentCompiledSha256."combat.class" -ceq
            [string]$nineCombatClass.sha256 -and
        [string]$nineAttributeContract.buildEvidence.result -ceq "passed" -and
        [string]$nineAttributeContract.runtimeEvidence.result -ceq "passed") `
        -Name "p14.incap.build.exact-nine-attribute-deployment-delegation"

    & (Join-Path $PSScriptRoot "Test-P14NineAttributeRuntime.ps1") `
        -SourceRoot $SourceRoot `
        -Expectation Build

    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.sourceWorkParity.result -ceq "passed" -and
        [int]$contract.buildEvidence.sourceWorkParity.checkedFiles -eq 1 -and
        [int]$contract.buildEvidence.sourceWorkParity.matchedFiles -eq 1 -and
        [string]$contract.buildEvidence.currentCompiledSha256."combat.class" -match '^[a-f0-9]{64}$' -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        -Name "p14.incap.build.current-java-and-deployment-evidence"
}

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
