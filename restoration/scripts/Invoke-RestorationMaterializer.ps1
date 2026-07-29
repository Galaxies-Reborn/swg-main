[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$StagingRoot,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$superprojectRoot = Split-Path -Parent $restorationRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force

$manifest = Get-RestorationManifest -RestorationRoot $restorationRoot
$source = Resolve-NormalizedPath -Path $SourceRoot
$stage = Resolve-NormalizedPath -Path $StagingRoot

$phaseAContractPath = Join-Path $restorationRoot ([string]$manifest.contracts.phaseA)
if (-not (Test-Path -LiteralPath $phaseAContractPath -PathType Leaf))
{
    throw "Phase-A contract not found: $phaseAContractPath"
}
$phaseAContract = Get-Content -LiteralPath $phaseAContractPath -Raw | ConvertFrom-Json
$fingerprintContract = $phaseAContract.runtimeVerticalSlice.materializationFingerprint
$fingerprintAlgorithm = [string]$fingerprintContract.algorithm
$fingerprintPlaceholder = [string]$fingerprintContract.placeholder
$fingerprintValue = [string]$fingerprintContract.value
$fingerprintFiles = @($fingerprintContract.files | ForEach-Object { [string]$_ })
if ($fingerprintAlgorithm -cne "SHA-256")
{
    throw "Unsupported Phase-A materialization fingerprint algorithm: '$fingerprintAlgorithm'."
}
if ([string]::IsNullOrWhiteSpace($fingerprintPlaceholder) -or
    $fingerprintValue -cne $fingerprintPlaceholder)
{
    throw "Canonical Phase-A contract must retain its exact materialization fingerprint placeholder."
}
if ($fingerprintFiles.Count -ne 3)
{
    throw "Phase-A materialization fingerprint must name exactly three ordered Java inputs; found $($fingerprintFiles.Count)."
}

$canonicalAcceptanceBundle = @(Get-RestorationAcceptanceBundle -RestorationRoot $restorationRoot)
$requiredAcceptancePaths = @(
    "restoration/manifest.json",
    "restoration/README.md",
    "restoration/contracts/phase-a.json",
    "restoration/patches/root/README.md",
    "restoration/patches/root/001-dedicated-transfer-server.patch",
    "restoration/patches/exe/README.md",
    "restoration/patches/exe/001-p14-xp-rate.patch",
    "restoration/patches/dsrc/README.md",
    "restoration/patches/dsrc/002-phase-a-runtime-probe.patch",
    "restoration/patches/dsrc/002a-phase-a-operation-markers.patch",
    "restoration/patches/dsrc/007-phase-a-attached-bank-dispatch.patch",
    "restoration/patches/dsrc/006-p14-mos-eisley-artisan-trainer.patch",
    "restoration/patches/src/README.md",
    "restoration/scripts/Invoke-RestorationMaterializer.ps1",
    "restoration/scripts/Restoration.Common.psm1",
    "restoration/scripts/Test-PhaseA.ps1",
    ("restoration/" + ([string]$phaseAContract.runtimeSmokeScript).Replace('\', '/')),
    ("restoration/" + ([string]$phaseAContract.runtimeTrainerPersistenceScript).Replace('\', '/'))
)
$canonicalAcceptancePaths = @($canonicalAcceptanceBundle | ForEach-Object { [string]$_.Path })
$missingAcceptancePaths = @($requiredAcceptancePaths | Where-Object { $_ -cnotin $canonicalAcceptancePaths })
if ($missingAcceptancePaths.Count -gt 0)
{
    throw "Canonical restoration acceptance bundle is incomplete: $($missingAcceptancePaths -join ', ')."
}
if ([int]$phaseAContract.runtimeVerticalSlice.runnerSchemaVersion -ne 8 -or
    [int]$phaseAContract.runtimeVerticalSlice.snapshotSchemaVersion -ne 8)
{
    throw "The restoration acceptance bundle must use Phase-A runner/snapshot schema v8."
}
$runnerRecovery = $phaseAContract.phaseAPurchaseProtocol.runnerRecoveryCheckpointing
$expectedReservationWriteOrder = @(
    "attemptId", "state=reserving", "kind", "updated", "lifecycleId", "trainerOid",
    "skillName", "cost", "preCredits", "preCash", "preBank", "preXp", "prePoints",
    "preCap", "preNovice", "preSkill", "protocolVersion", "refundGeneration",
    "refundAttemptKey", "refundRetryConsumed", "accountingAttemptKey",
    "accountingAccount", "accountingOutcome", "id", "state=reserved"
)
if ([string]$phaseAContract.runtimeVerticalSlice.runtimeContractId -cne "phase-a-trainer-persistence-v6.4" -or
    [int]$phaseAContract.phaseAPurchaseProtocol.protocolVersion -ne 64 -or
    [string]$runnerRecovery.runnerSemanticsVersion -cne "6.5" -or
    [string]$runnerRecovery.serverProtocolCompatibility -cne "v6.4-protocol-64-unchanged" -or
    (@($runnerRecovery.settlementOrdering | ForEach-Object { [string]$_ }) -join ',') -cne "synchronize-authoritative-marker,evaluate-recoverable-settled-failures,evaluate-generic-terminal-or-fail-closed" -or
    (@($runnerRecovery.recoverableSettledStates | ForEach-Object { [string]$_ }) -join ',') -cne "refundInitialFailed,refundRecoveryFailed" -or
    [string]$runnerRecovery.candidatePolicy -cne "clone-state-plus-seven-provenance-leaves-normalize-full-validate-json-roundtrip-full-validate" -or
    [string]$runnerRecovery.intentPolicy -cne "validated-atomic-snapshot-before-recovery-rpc" -or
    (@($runnerRecovery.postActionPolicy.refreshOn | ForEach-Object { [string]$_ }) -join ',') -cne "success,timeout,exception" -or
    [string]$runnerRecovery.postActionPolicy.correlatedStateDisposition -cne "normalize-validate-and-atomically-save-before-return-or-rethrow" -or
    [string]$runnerRecovery.postActionPolicy.invalidRefreshDisposition -cne "retain-last-valid-intent-snapshot" -or
    [string]$runnerRecovery.postActionPolicy.actionErrorDisposition -cne "rethrow-original-after-best-effort-refresh" -or
    [string]$runnerRecovery.recoveryAuditPolicy -cne "retain-latest-action-source-and-process-token-across-reachable-advanced-states" -or
    [string]$runnerRecovery.targetNormalizationPolicy -cne "clear-advanced-callback-accounting-and-retry-targets;retain-active-synchronous-refund-reconcile-target-until-purchaseRefunded" -or
    (@($runnerRecovery.reservationWriteOrder | ForEach-Object { [string]$_ }) -join ',') -cne ($expectedReservationWriteOrder -join ',') -or
    [string]$runnerRecovery.preDispatchPartialPolicy -cne "missing-or-reserving-requires-gap-free-observable-write-prefix-neutral-provenance-unchanged-preimage-and-no-volatile-nonces" -or
    [string]$runnerRecovery.serverReservationPrefixPolicy -cne "recompute-exact-25-write-prefix-values-immediately-before-rollback-or-clear" -or
    [string]$runnerRecovery.completeMarkerTimestampPolicy -cne "all-complete-and-terminal-markers-require-positive-operation-updated" -or
    [string]$runnerRecovery.clearSuccessPolicy -cne "require-cleared-true-plus-authoritative-marker-absent-readback" -or
    [string]$runnerRecovery.markerAbsentPolicy -cne "require-zero-operation-instrumentation-before-discard-or-clear")
{
    throw "Phase-A schema-v8 runner recovery checkpointing semantics are incomplete or incompatible with frozen protocol 64."
}
$expectedRecoveryPairs = [ordered]@{
    restartAccountingResume = [pscustomobject]@{
        Target = "resumePurchaseAccounting"
        Active = "purchaseApplying,accountingRequested,accountingDispatching,accountingPending,accountingSucceededCallback"
        Blank = "purchaseApplying,accountingRequested,accountingRequestQueueFailed,accountingDispatching,accountingPending,accountingQueueFailed,accountingFailed,accountingSucceededCallback,purchaseSucceeded"
    }
    restartCallbackReplay = [pscustomobject]@{
        Target = "requeuePurchaseCallback"
        Active = "paymentDispatching,paymentSucceededCallback,purchaseApplying"
        Blank = "paymentDispatching,paymentSucceededCallback,purchaseApplying,accountingRequested,accountingRequestQueueFailed,accountingDispatching,accountingPending,accountingQueueFailed,accountingFailed,accountingSucceededCallback,purchaseSucceeded,refundInitialClaiming,refundInitialDispatching,refundInitialPending,refundInitialFailed,purchaseRefunded"
    }
    restartRefundOutcome = [pscustomobject]@{
        Target = "reconcileRefundOutcome"
        Active = "refundInitialClaiming,refundInitialDispatching,refundInitialPending,refundInitialFailed,refundRecoveryClaiming,refundRecoveryDispatching,refundRecoveryPending,refundRecoveryFailed"
        Blank = "purchaseRefunded"
    }
    restartRefundRetry = [pscustomobject]@{
        Target = "retryPurchaseRefund"
        Active = "refundInitialClaiming,refundInitialFailed,refundRecoveryClaiming"
        Blank = "refundInitialClaiming,refundInitialDispatching,refundInitialPending,refundInitialFailed,refundRecoveryClaiming,refundRecoveryDispatching,refundRecoveryPending,refundRecoveryFailed,purchaseRefunded"
    }
}
foreach ($sourceName in $expectedRecoveryPairs.Keys)
{
    $actualPair = $runnerRecovery.allowedRecoveryPairs.$sourceName
    $expectedPair = $expectedRecoveryPairs[$sourceName]
    if ([string]$actualPair.activeTarget -cne [string]$expectedPair.Target -or
        (@($actualPair.activeStates | ForEach-Object { [string]$_ }) -join ',') -cne [string]$expectedPair.Active -or
        (@($actualPair.blankTargetStates | ForEach-Object { [string]$_ }) -join ',') -cne [string]$expectedPair.Blank)
    {
        throw "Phase-A schema-v8 recovery pair '$sourceName' is not exact."
    }
}
$canonicalRunnerPath = Join-Path $restorationRoot ([string]$phaseAContract.runtimeTrainerPersistenceScript)
$canonicalRunnerText = Get-Content -LiteralPath $canonicalRunnerPath -Raw
if ($canonicalRunnerText -notmatch '\[switch\]\$OfflineSelfTest' -or
    $canonicalRunnerText -notmatch 'OFFLINE_TRANSITION_TESTS=PASS' -or
    $canonicalRunnerText -notmatch '\$runnerSchemaVersion\s*=\s*\[int\]\$runtimeContract\.runnerSchemaVersion')
{
    throw "Canonical Phase-A runner is not the required schema-v8 offline-capable acceptance runner."
}

$canonicalPinArgs = @{
    RepositoryRoot = $superprojectRoot
    Manifest = $manifest
}
$sourcePinArgs = @{
    RepositoryRoot = $source
    Manifest = $manifest
    RequireInitialized = $true
}
Assert-RestorationPins @canonicalPinArgs | Out-Null
Assert-RestorationPins @sourcePinArgs | Out-Null

if (Test-PathWithin -Candidate $stage -Parent $superprojectRoot)
{
    throw "StagingRoot must be outside the canonical superproject: $superprojectRoot"
}
if (Test-PathWithin -Candidate $stage -Parent $source)
{
    throw "StagingRoot must be outside the initialized source checkout: $source"
}
if (Test-Path -LiteralPath $stage)
{
    if (-not (Test-Path -LiteralPath $stage -PathType Container))
    {
        throw "StagingRoot exists and is not a directory: $stage"
    }
    if (Get-ChildItem -LiteralPath $stage -Force | Select-Object -First 1)
    {
        throw "StagingRoot must not exist or must be empty: $stage"
    }
}

$patches = @()
foreach ($overlay in @($manifest.overlays))
{
    $overlayRoot = Join-Path $restorationRoot ([string]$overlay.directory)
    if (-not (Test-Path -LiteralPath $overlayRoot -PathType Container))
    {
        throw "Overlay directory is missing: $overlayRoot"
    }

    foreach ($patch in @(Get-ChildItem -LiteralPath $overlayRoot -File -Filter "*.patch" | Sort-Object Name))
    {
        $patches += [pscustomobject]@{
            Component = [string]$overlay.component
            File = $patch
        }
    }
}

function Assert-BlockedPatchFeaturesAbsent
{
    param(
        [Parameter(Mandatory = $true)][psobject]$Gate
    )

    if (@("ready", "implemented-build-verified-live-pending") -ccontains [string]$Gate.status)
    {
        return
    }

    foreach ($blockedText in @($Gate.materializerPolicy.rejectPatchTextWhileBlocked))
    {
        foreach ($patchRecord in $patches)
        {
            $patchText = Get-Content -LiteralPath $patchRecord.File.FullName -Raw
            if ($patchText.IndexOf([string]$blockedText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            {
                throw "Blocked feature '$($Gate.feature)' token '$blockedText' appears in $($patchRecord.File.FullName). Satisfy and update its gate contract first."
            }
        }
    }
}

$headShotGatePath = Join-Path $restorationRoot ([string]$manifest.contracts.headShot1Gate)
$headShotGate = Get-Content -LiteralPath $headShotGatePath -Raw | ConvertFrom-Json
Assert-BlockedPatchFeaturesAbsent -Gate $headShotGate

$marksmanTier1GatePath = Join-Path $restorationRoot ([string]$manifest.contracts.p14MarksmanTier1Matrix)
$marksmanTier1Gate = Get-Content -LiteralPath $marksmanTier1GatePath -Raw | ConvertFrom-Json
Assert-BlockedPatchFeaturesAbsent -Gate $marksmanTier1Gate

Write-Host "Restoration materialization plan"
Write-Host "  source:  $source"
Write-Host "  staging: $stage"
Write-Host "  clone:   complete superproject at $($manifest.target.baselineSuperprojectCommit)"
foreach ($pin in @($manifest.gitlinks))
{
    Write-Host "  pin:     $($pin.name) at $($pin.commit)"
}
Write-Host "  patches: $($patches.Count)"
Write-Host "  acceptance bundle: $($canonicalAcceptanceBundle.Count) current restoration files"

if (-not $Apply)
{
    Write-Host "Plan only. No files were written; pass -Apply to create the isolated stage."
    exit 0
}

if ($patches.Count -eq 0)
{
    throw "No overlay patches are registered. Refusing to create an unmodified stage."
}

$stageParent = Split-Path -Parent $stage
if (-not (Test-Path -LiteralPath $stageParent -PathType Container))
{
    New-Item -ItemType Directory -Path $stageParent | Out-Null
}

Invoke-GitChecked -Repository $stageParent -Arguments @(
    "clone",
    "--shared",
    "--no-checkout",
    $source,
    $stage
) | Out-Null
Invoke-GitChecked -Repository $stage -Arguments @(
    "checkout",
    "--detach",
    [string]$manifest.target.baselineSuperprojectCommit
) | Out-Null
Invoke-GitChecked -Repository $stage -Arguments @(
    "remote",
    "remove",
    "origin"
) | Out-Null

foreach ($pin in @($manifest.gitlinks))
{
    $componentSource = Join-Path $source ([string]$pin.path)
    $componentStage = Join-Path $stage ([string]$pin.path)
    Invoke-GitChecked -Repository $stage -Arguments @(
        "clone",
        "--shared",
        "--no-checkout",
        $componentSource,
        $componentStage
    ) | Out-Null
    Invoke-GitChecked -Repository $componentStage -Arguments @(
        "checkout",
        "--detach",
        [string]$pin.commit
    ) | Out-Null
    Invoke-GitChecked -Repository $componentStage -Arguments @(
        "remote",
        "remove",
        "origin"
    ) | Out-Null
}

foreach ($patchRecord in $patches)
{
    $componentStage = Join-Path $stage ([string]$patchRecord.Component)
    Invoke-GitChecked -Repository $componentStage -Arguments @(
        "apply",
        "--check",
        $patchRecord.File.FullName
    ) | Out-Null
    Invoke-GitChecked -Repository $componentStage -Arguments @(
        "apply",
        $patchRecord.File.FullName
    ) | Out-Null
}

$stagedRestorationRoot = Join-Path $stage "restoration"
if (-not (Test-PathWithin -Candidate $stagedRestorationRoot -Parent $stage) -or
    (Resolve-NormalizedPath -Path $stagedRestorationRoot) -eq $stage)
{
    throw "Refusing to replace an unsafe staged restoration path: $stagedRestorationRoot"
}
if (Test-Path -LiteralPath $stagedRestorationRoot)
{
    Remove-Item -LiteralPath $stagedRestorationRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stagedRestorationRoot | Out-Null
foreach ($bundleFile in $canonicalAcceptanceBundle)
{
    $stagedBundlePath = Join-Path $stage (([string]$bundleFile.Path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-PathWithin -Candidate $stagedBundlePath -Parent $stagedRestorationRoot))
    {
        throw "Acceptance bundle destination escaped staged restoration: $stagedBundlePath"
    }
    $stagedBundleParent = Split-Path -Parent $stagedBundlePath
    if (-not (Test-Path -LiteralPath $stagedBundleParent -PathType Container))
    {
        New-Item -ItemType Directory -Path $stagedBundleParent -Force | Out-Null
    }
    [System.IO.File]::Copy([string]$bundleFile.AbsolutePath, $stagedBundlePath, $true)
    [byte[]]$copiedBytes = [System.IO.File]::ReadAllBytes($stagedBundlePath)
    if ([UInt64]$copiedBytes.Length -ne [UInt64]$bundleFile.SizeBytes -or
        (Get-Sha256HexFromBytes -Bytes $copiedBytes) -cne [string]$bundleFile.Sha256)
    {
        throw "Acceptance bundle copy verification failed: $($bundleFile.Path)"
    }
}

$stagedContractRelativePath = "restoration/" + ([string]$manifest.contracts.phaseA).Replace('\', '/')
$stagedContractPath = Join-Path $stage ($stagedContractRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
if (-not (Test-PathWithin -Candidate $stagedContractPath -Parent $stage))
{
    throw "Staged Phase-A contract path escaped the isolated stage: $stagedContractPath"
}
$stagedContractParent = Split-Path -Parent $stagedContractPath
if (-not (Test-Path -LiteralPath $stagedContractParent -PathType Container))
{
    New-Item -ItemType Directory -Path $stagedContractParent | Out-Null
}
if (-not (Test-Path -LiteralPath $stagedContractPath -PathType Leaf))
{
    throw "Copied acceptance bundle omitted its Phase-A contract: $stagedContractPath"
}

# The digest is deliberately computed over placeholder-form Java bytes. The fixed
# length/path framing in Get-MaterializationFingerprint makes input boundaries and
# ordering unambiguous without ever hashing the digest back into itself.
$fingerprint = Get-MaterializationFingerprint `
    -Root $stage `
    -RelativePaths $fingerprintFiles `
    -Placeholder $fingerprintPlaceholder
$inputDigest = [string]$fingerprint.Digest
if ($inputDigest -cnotmatch '^[a-f0-9]{64}$')
{
    throw "Materialization produced an invalid SHA-256 input digest: '$inputDigest'."
}

foreach ($relativePath in $fingerprintFiles)
{
    $artifactPath = Join-Path $stage ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    Set-MaterializationFingerprintToken `
        -Path $artifactPath `
        -Placeholder $fingerprintPlaceholder `
        -Fingerprint $inputDigest
}

$stagedContractText = [System.IO.File]::ReadAllText($stagedContractPath)
$valuePattern = '(?<prefix>"value"\s*:\s*")' + [regex]::Escape($fingerprintPlaceholder) + '(?<suffix>")'
$valueMatches = [regex]::Matches($stagedContractText, $valuePattern)
if ($valueMatches.Count -ne 1)
{
    throw "Staged Phase-A contract must contain exactly one placeholder-valued materialization fingerprint; found $($valueMatches.Count)."
}
$valueMatch = $valueMatches[0]
$stagedContractText = $stagedContractText.Remove($valueMatch.Index, $valueMatch.Length).Insert(
    $valueMatch.Index,
    $valueMatch.Groups['prefix'].Value + $inputDigest + $valueMatch.Groups['suffix'].Value
)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
[System.IO.File]::WriteAllText($stagedContractPath, $stagedContractText, $utf8NoBom)
$stagedContract = Get-Content -LiteralPath $stagedContractPath -Raw | ConvertFrom-Json
if ([string]$stagedContract.runtimeVerticalSlice.materializationFingerprint.value -cne $inputDigest -or
    [string]$stagedContract.runtimeVerticalSlice.materializationFingerprint.placeholder -cne $fingerprintPlaceholder)
{
    throw "Staged Phase-A contract fingerprint injection did not preserve the contract definition."
}

$artifactRecords = @()
foreach ($relativePath in $fingerprintFiles)
{
    $artifactPath = Join-Path $stage ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    [byte[]]$artifactBytes = [System.IO.File]::ReadAllBytes($artifactPath)
    $artifactRecords += [pscustomobject][ordered]@{
        ordinal = $artifactRecords.Count
        path = $relativePath
        sizeBytes = [UInt64]$artifactBytes.Length
        sha256 = Get-Sha256HexFromBytes -Bytes $artifactBytes
    }
}
[byte[]]$stagedContractBytes = [System.IO.File]::ReadAllBytes($stagedContractPath)
$acceptanceBundleRecords = @()
foreach ($bundleFile in $canonicalAcceptanceBundle)
{
    $stagedBundlePath = Join-Path $stage (([string]$bundleFile.Path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $stagedBundlePath -PathType Leaf))
    {
        throw "Staged acceptance bundle file disappeared: $($bundleFile.Path)"
    }
    [byte[]]$stagedBundleBytes = [System.IO.File]::ReadAllBytes($stagedBundlePath)
    $stagedBundleHash = Get-Sha256HexFromBytes -Bytes $stagedBundleBytes
    $mutation = if ([string]$bundleFile.Path -ceq $stagedContractRelativePath)
    {
        "materializationFingerprint.value"
    }
    else
    {
        "none"
    }
    if ($mutation -ceq "none" -and
        ([UInt64]$stagedBundleBytes.Length -ne [UInt64]$bundleFile.SizeBytes -or
         $stagedBundleHash -cne [string]$bundleFile.Sha256))
    {
        throw "Staged acceptance file drifted after copy: $($bundleFile.Path)"
    }
    $acceptanceBundleRecords += [pscustomobject][ordered]@{
        ordinal = [int]$bundleFile.Ordinal
        path = [string]$bundleFile.Path
        canonicalSizeBytes = [UInt64]$bundleFile.SizeBytes
        canonicalSha256 = [string]$bundleFile.Sha256
        stagedSizeBytes = [UInt64]$stagedBundleBytes.Length
        stagedSha256 = $stagedBundleHash
        mutation = $mutation
    }
}
$orderedInputRecords = @(
    $fingerprint.Inputs | ForEach-Object {
        [pscustomobject][ordered]@{
            ordinal = [int]$_.Ordinal
            path = [string]$_.Path
            sizeBytes = [UInt64]$_.SizeBytes
            sha256 = [string]$_.Sha256
            placeholderOccurrences = [int]$_.PlaceholderOccurrences
        }
    }
)
$artifactManifest = [pscustomobject][ordered]@{
    schemaVersion = 2
    algorithm = $fingerprintAlgorithm
    framing = [string]$fingerprint.Framing
    placeholder = $fingerprintPlaceholder
    inputDigest = $inputDigest
    orderedInputs = $orderedInputRecords
    artifacts = $artifactRecords
    acceptanceBundle = [pscustomobject][ordered]@{
        policy = "canonical-byte-identity-except-staged-phase-a-fingerprint-value"
        exclusions = @("restoration/materialization-fingerprint.json", "**/.git/**")
        files = $acceptanceBundleRecords
    }
    stagedContract = [pscustomobject][ordered]@{
        path = $stagedContractRelativePath
        sizeBytes = [UInt64]$stagedContractBytes.Length
        sha256 = Get-Sha256HexFromBytes -Bytes $stagedContractBytes
        fingerprintValue = $inputDigest
    }
}
$artifactManifestPath = Join-Path $stage "restoration\materialization-fingerprint.json"
$artifactManifestJson = $artifactManifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText(
    $artifactManifestPath,
    $artifactManifestJson + [System.Environment]::NewLine,
    $utf8NoBom
)

Write-Host "Materialized isolated restoration stage: $stage"
Write-Host "Phase-A materialization fingerprint: $inputDigest"
Write-Host "Phase-A artifact manifest: $artifactManifestPath"
