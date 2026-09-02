[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $restorationRoot "manifest.json"
$materializerPath = Join-Path $PSScriptRoot "Invoke-RestorationMaterializer.ps1"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.rebornForceThreadsGate)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$materializer = Get-Content -LiteralPath $materializerPath -Raw
$modelTestPath = Join-Path $PSScriptRoot ([IO.Path]::GetFileName(
    [string]$contract.activationCriteria.referenceModelTest
))

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

Write-Host "Reborn Force Threads blocked-gate checks:"

Assert-Contract -Condition (
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    [string]$manifest.contracts.rebornForceThreadsGate -ceq
        "contracts/reborn-force-threads-gate.json" -and
    (Test-Path -LiteralPath $contractPath -PathType Leaf)) `
    -Name "reborn.force-threads.manifest.registration"

Assert-Contract -Condition (
    [int]$contract.schemaVersion -eq 1 -and
    [string]$contract.feature -ceq "reborn-force-threads" -and
    [string]$contract.status -ceq "blocked" -and
    [string]$contract.implementationBoundary.currentPhase -ceq "shadow-development" -and
    [bool]$contract.implementationBoundary.isolatedSourceDevelopmentWhileBlocked) `
    -Name "reborn.force-threads.default.blocked"

$permittedModes = @($contract.implementationBoundary.permittedPreAwardModes | ForEach-Object { [string]$_ })
$forbiddenEffects = @($contract.implementationBoundary.forbiddenWhileBlocked | ForEach-Object { [string]$_ })
Assert-Contract -Condition (
    [string]$contract.implementationBoundary.defaultMode -ceq "off" -and
    ($permittedModes -join ",") -ceq "off,shadow" -and
    [string]$contract.implementationBoundary.shadowEffects -ceq "telemetry-and-gm-inspection-only" -and
    $forbiddenEffects.Count -eq 5 -and
    $forbiddenEffects -contains "Force-sensitive or Jedi state mutation") `
    -Name "reborn.force-threads.shadow.no-gameplay-effects"

$domains = @($contract.shadowVerticalSlice.causalDomains | ForEach-Object { [string]$_ })
Assert-Contract -Condition (
    ($domains -join ",") -ceq "PROVENANCE,SHELTER,OUTCOME" -and
    [string]$contract.shadowVerticalSlice.participants -ceq "three-distinct-station-ids" -and
    -not [bool]$contract.shadowVerticalSlice.sameAccountCredit -and
    -not [bool]$contract.shadowVerticalSlice.directTransferCredit -and
    [int]$contract.shadowVerticalSlice.minimumObservedShelterSeconds -eq 180 -and
    [bool]$contract.shadowVerticalSlice.originMayBeOffline -and
    [string]$contract.shadowVerticalSlice.deliverySemantics -ceq
        "at-least-once-transport-exactly-once-credit") `
    -Name "reborn.force-threads.vertical-slice.causal-boundary"

$requiredLeaves = @($contract.persistenceContract.requiredLeaves | ForEach-Object { [string]$_ })
$expectedLeaves = @("schema", "state", "tokens", "ledger", "outbox", "quarantineReason", "lastReconcile")
Assert-Contract -Condition (
    [string]$contract.persistenceContract.root -ceq "reborn.forceThreads" -and
    ($requiredLeaves -join ",") -ceq ($expectedLeaves -join ",") -and
    [bool]$contract.persistenceContract.senderOutboxBeforeDelivery -and
    [bool]$contract.persistenceContract.originLedgerReadbackBeforeAcknowledge -and
    [string]$contract.persistenceContract.malformedOrFutureSchemaDisposition -ceq
        "quarantine-and-fail-closed-for-credit" -and
    [string]$contract.persistenceContract.ordinaryGameplayFailurePolicy -ceq "fail-open") `
    -Name "reborn.force-threads.persistence.fail-closed-credit"

Assert-Contract -Condition (
    [int]$contract.provisionalLimits.maximumDepth -eq 3 -and
    [int]$contract.provisionalLimits.maximumActiveTokens -eq 8 -and
    [int]$contract.provisionalLimits.maximumOutboxRecords -eq 8 -and
    [int]$contract.provisionalLimits.maximumSealedSummaries -eq 32 -and
    [int]$contract.provisionalLimits.maximumDedupeIds -eq 64 -and
    [int]$contract.provisionalLimits.maximumOfflineMailboxRecords -eq 16 -and
    [int]$contract.provisionalLimits.tokenLifetimeHours -eq 72 -and
    [int]$contract.provisionalLimits.maximumPersistentBytes -eq 16384) `
    -Name "reborn.force-threads.persistence.bounded"

Assert-Contract -Condition (
    [string]$contract.identityAndPrivacy.progressScope -ceq "per-character" -and
    [bool]$contract.identityAndPrivacy.serverPrivateStationIdsAllowedForValidation -and
    -not [bool]$contract.identityAndPrivacy.rawStationIdsInTelemetryOrNarrative -and
    -not [bool]$contract.identityAndPrivacy.ipAddressEligibilityDecisions -and
    -not [bool]$contract.identityAndPrivacy.chatOrFreeTextPersistence -and
    -not [bool]$contract.identityAndPrivacy.socialGraphExposure) `
    -Name "reborn.force-threads.identity-and-privacy"

$requirements = @($contract.requiredBeforeReady | ForEach-Object { [string]$_ })
Assert-Contract -Condition (
    $requirements.Count -eq 10 -and
    $requirements -contains "deterministic reference model and adversarial event-log fixtures" -and
    $requirements -contains "approved twelve-event Force progression policy with alternate routes and a non-mandatory hint system" -and
    $requirements -contains "feature-off proof of zero writes, zero messages, and zero progression effects" -and
    $requirements -contains "three explicitly approved disposable runtime identities") `
    -Name "reborn.force-threads.readiness.requirements-retained"

Assert-Contract -Condition (
    [string]$contract.activationCriteria.gateTest -ceq "scripts/Test-RebornForceThreadsGate.ps1" -and
    [string]$contract.activationCriteria.referenceModelTest -ceq "scripts/Test-RebornForceThreadsModel.ps1" -and
    [string]$contract.activationCriteria.awardAuthority -ceq "separate-future-gate" -and
    -not [bool]$contract.activationCriteria.retroactiveCredit -and
    -not [bool]$contract.activationCriteria.pvpOrDuelEdgesInitiallyAllowed) `
    -Name "reborn.force-threads.activation.separate-award-gate"

Assert-Contract -Condition (
    (Test-Path -LiteralPath $modelTestPath -PathType Leaf) -and
    [string]$contract.developmentEvidence.referenceModel -ceq
        "implemented-and-static-tests-passing" -and
    [int]$contract.developmentEvidence.scenarioCount -eq 15) `
    -Name "reborn.force-threads.reference-model.registered"

$blockedTokens = @($contract.materializerPolicy.rejectPatchTextWhileBlocked | ForEach-Object { [string]$_ })
$expectedTokens = @("reborn-force-threads", "reborn.forceThreads", "force_threads", "forceThreads")
Assert-Contract -Condition (
    $blockedTokens.Count -eq $expectedTokens.Count -and
    ($blockedTokens -join ",") -ceq ($expectedTokens -join ",")) `
    -Name "reborn.force-threads.materializer.blocked-token-policy"

$gatePathLoad = '$forceThreadsGatePath = Join-Path $restorationRoot ([string]$manifest.contracts.rebornForceThreadsGate)'
$gateContractLoad = '$forceThreadsGate = Get-Content -LiteralPath $forceThreadsGatePath -Raw | ConvertFrom-Json'
$gateAssertion = 'Assert-BlockedPatchFeaturesAbsent -Gate $forceThreadsGate'
$gatePathIndex = $materializer.IndexOf($gatePathLoad, [StringComparison]::Ordinal)
$gateContractIndex = $materializer.IndexOf($gateContractLoad, [StringComparison]::Ordinal)
$gateAssertionIndex = $materializer.IndexOf($gateAssertion, [StringComparison]::Ordinal)
Assert-Contract -Condition (
    $materializer.Contains('function Assert-BlockedPatchFeaturesAbsent') -and
    $materializer.Contains('@("ready", "implemented-build-verified-live-pending")') -and
    $materializer.Contains('[System.StringComparison]::OrdinalIgnoreCase') -and
    $gatePathIndex -ge 0 -and
    $gateContractIndex -gt $gatePathIndex -and
    $gateAssertionIndex -gt $gateContractIndex) `
    -Name "reborn.force-threads.materializer.fail-closed-integration"

$patchFiles = @(Get-ChildItem -LiteralPath (Join-Path $restorationRoot "patches") -Recurse -File -Filter "*.patch")
$blockedMatches = [System.Collections.Generic.List[string]]::new()
foreach ($patchFile in $patchFiles)
{
    $patchText = Get-Content -LiteralPath $patchFile.FullName -Raw
    foreach ($blockedToken in $blockedTokens)
    {
        if ($patchText.IndexOf($blockedToken, [StringComparison]::OrdinalIgnoreCase) -ge 0)
        {
            $blockedMatches.Add("$($patchFile.FullName):$blockedToken")
        }
    }
}
Assert-Contract -Condition ($blockedMatches.Count -eq 0) `
    -Name "reborn.force-threads.archived-overlays.no-blocked-gameplay-patches"

if (Test-Path -LiteralPath $modelTestPath -PathType Leaf)
{
    & $modelTestPath | Out-Host
}

if ($failures.Count -gt 0)
{
    throw "Reborn Force Threads blocked gate failed: $($failures -join ', ')"
}

Write-Host "Reborn Force Threads blocked gate passed; gameplay patch admission remains closed."
