[CmdletBinding()]
param(
    [ValidatePattern("^[0-9]+$")]
    [string]$PlayerOid,

    [ValidateSet("Observe", "Prepare", "Conversation", "Purchase", "VerifyBoundary", "Surrender", "Cleanup")]
    [string]$Mode = "Observe",

    [ValidatePattern("^[0-9]+$")]
    [string]$TrainerOid,

    [ValidateSet("Relog", "Restart")]
    [string]$BoundaryKind,

    [string]$SnapshotPath,

    [ValidatePattern("^[A-Za-z0-9_.-]+$")]
    [string]$ContainerName = "swg-precu",

    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 30,

    [switch]$OfflineSelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$probeScript = "test.precu_phase_a_runtime"
$probeMethod = "executeProbe"
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$restorationRoot = Split-Path -Parent $PSScriptRoot
$contractPath = Join-Path $restorationRoot "contracts\phase-a.json"
$manifestPath = Join-Path $restorationRoot "manifest.json"
$runtimePatchPath = Join-Path $restorationRoot "patches\dsrc\002-phase-a-runtime-probe.patch"
$markerPatchPath = Join-Path $restorationRoot "patches\dsrc\002a-phase-a-operation-markers.patch"
$runtimeContract = (Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json).runtimeVerticalSlice
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$runtimeContractId = [string]$runtimeContract.runtimeContractId
$snapshotSchemaVersion = [int]$runtimeContract.snapshotSchemaVersion
$runnerSchemaVersion = [int]$runtimeContract.runnerSchemaVersion
$sourceMode = [string]$runtimeContract.sourceMode
$materializationFingerprint = [string]$runtimeContract.materializationFingerprint.value
$requiredContainer = [string]$runtimeContract.containerName
$stationId = [int]$runtimeContract.stationId
$noviceSkill = [string]$runtimeContract.prerequisiteSkill
$engineeringSkill = [string]$runtimeContract.skill
$xpType = [string]$runtimeContract.xpType
$trainerCost = [int]$runtimeContract.moneyCost
$xpCost = [int]$runtimeContract.xpCost
$engineeringPointCost = [int]$runtimeContract.skillPointCost
$novicePointCost = [int]$runtimeContract.prerequisiteSkillPointCost
$quietSeconds = [int]$runtimeContract.settlementQuietSeconds
$expectedCommands = @($runtimeContract.completeGrantVector.commands | ForEach-Object { [string]$_ })
$expectedMods = @($runtimeContract.completeGrantVector.skillMods.psobject.Properties | ForEach-Object { [string]$_.Name })
$expectedSchematics = @($runtimeContract.completeGrantVector.concreteSchematics | ForEach-Object { [string]$_ } | Sort-Object)
$purchaseSchematics = @($runtimeContract.completeGrantVector.purchaseSchematics | ForEach-Object { [string]$_ })
$purchaseModDeltas = $runtimeContract.completeGrantVector.purchaseSkillModDeltas
$settledOperationStates = @(
    "fundSucceeded",
    "fundFailed",
    "fundQueueFailed",
    "drainSucceeded",
    "drainFailed",
    "drainQueueFailed",
    "purchaseSucceeded",
    "paymentFailed",
    "paymentQueueFailed",
    "purchaseRefunded",
    "refundInitialFailed",
    "refundRecoveryFailed",
    "accountingRequestQueueFailed",
    "accountingQueueFailed",
    "accountingFailed",
    "purchaseRejected"
)
$recoverableSettledOperationStates = @(
    "refundInitialFailed",
    "refundRecoveryFailed"
)
$clearableOperationStates = @(
    "fundSucceeded", "fundFailed", "fundQueueFailed",
    "drainSucceeded", "drainFailed", "drainQueueFailed",
    "purchaseSucceeded", "paymentFailed", "paymentQueueFailed",
    "purchaseRefunded", "purchaseRejected"
)

if (-not $OfflineSelfTest -and [string]::IsNullOrWhiteSpace($PlayerOid))
{
    throw "PlayerOid is required unless -OfflineSelfTest is selected."
}
if (-not $OfflineSelfTest -and $sourceMode -cne "direct-branch" -and
    ($materializationFingerprint -notmatch '^[a-f0-9]{64}$' -or
     $materializationFingerprint -ceq "__PHASE_A_BUILD_FINGERPRINT__"))
{
    throw "The runtime contract contains an uninjected or invalid materialization fingerprint."
}

if ($ContainerName -cne $requiredContainer)
{
    throw "This acceptance is locked to container '$requiredContainer'; received '$ContainerName'."
}

$persistentStateFields = @(
    "HasNovice", "HasSkill", "HasCommand", "HasSchematic", "SkillCost",
    "Points", "Xp", "Cap", "SkillModValue", "Cash", "Bank", "Credits",
    "VectorCommandsOwned", "VectorCommandsExpected", "VectorModsMatched",
    "VectorModsExpected", "VectorSchematicsOwned", "VectorSchematicsExpected",
    "VectorComplete", "VectorCommands", "VectorMods", "VectorSchematics",
    "OperationAttemptId", "OperationId", "OperationKind", "OperationState",
    "OperationUpdated", "OperationLifecycleId", "OperationTrainerOid",
    "OperationSkillName", "OperationCost", "OperationProtocolVersion",
    "OperationRefundGeneration", "OperationRefundAttemptKey",
    "OperationRefundRetryConsumed", "OperationAccountingAttemptKey",
    "OperationAccountingAccount", "OperationAccountingOutcome",
    "OperationMarkerComplete", "OperationPreimageMatches",
    "NewbieFreeTrainingRouteActive"
)
$gameplayStateFields = @(
    "HasNovice", "HasSkill", "HasCommand", "HasSchematic", "SkillCost",
    "Points", "Xp", "Cap", "SkillModValue", "Cash", "Bank", "Credits",
    "VectorCommandsOwned", "VectorCommandsExpected", "VectorModsMatched",
    "VectorModsExpected", "VectorSchematicsOwned", "VectorSchematicsExpected",
    "VectorComplete", "VectorCommands", "VectorMods", "VectorSchematics",
    "NewbieFreeTrainingRouteActive"
)
$snapshotStateFields = @(
    "ContractId", "StationId", "MaterializationFingerprint", "DeployedArtifactsVerified",
    "ServerProcessToken", "LifecycleAttemptId", "LifecycleId",
    "LifecycleMarkerState", "LifecycleBaselineComplete", "HasNovice", "HasSkill",
    "HasCommand", "HasSchematic", "SkillCost", "Points", "Xp", "Cap",
    "SkillModValue", "Cash", "Bank", "Credits", "VectorCommandsOwned",
    "VectorCommandsExpected", "VectorModsMatched", "VectorModsExpected",
    "VectorSchematicsOwned", "VectorSchematicsExpected", "VectorComplete",
    "VectorCommands", "VectorMods", "VectorSchematics", "OperationAttemptId",
    "OperationId", "OperationKind", "OperationState", "OperationUpdated",
    "OperationLifecycleId", "OperationTrainerOid", "OperationSkillName",
    "OperationCost", "OperationProtocolVersion", "OperationRefundGeneration",
    "OperationRefundAttemptKey", "OperationRefundRetryConsumed",
    "OperationAccountingAttemptKey", "OperationAccountingAccount",
    "OperationAccountingOutcome", "OperationMarkerComplete", "OperationPreimageMatches",
    "RelogNoncePresent", "RestartNoncePresent", "NewbieFreeTrainingRouteActive"
)

function Invoke-Probe
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[A-Za-z0-9_./ +\-]+$")]
        [string]$Arguments
    )

    $serverCommand = "game tatooine runScript $probeScript $probeMethod $Arguments"
    $bashCommand = "cd /swg-precu/exe/linux && printf '%-1023s\0' '$serverCommand' | ./bin/ServerConsole -- @servercommon.cfg -s ServerConsole serverAddress=127.0.0.1 serverPort=61000"
    $previousErrorActionPreference = $ErrorActionPreference
    try
    {
        $ErrorActionPreference = "Continue"
        $output = @(& docker exec $ContainerName bash -lc $bashCommand 2>&1)
        $dockerExitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($dockerExitCode -ne 0)
    {
        throw "ServerConsole failed with exit code $dockerExitCode`: $($output -join [Environment]::NewLine)"
    }

    $text = ($output -join [Environment]::NewLine).Trim()
    $match = [regex]::Match($text, "(?m)(?:^|\s)(?<result>(?:action|oid|error)=[^\r\n]+)")
    if (-not $match.Success)
    {
        throw "ServerConsole returned no probe result: $text"
    }

    $resultText = $match.Groups["result"].Value.Trim()
    $values = @{}
    foreach ($token in [regex]::Matches($resultText, "(?<key>[A-Za-z][A-Za-z0-9]*)=(?<value>\S+)"))
    {
        $key = $token.Groups["key"].Value
        if ($values.ContainsKey($key))
        {
            throw "ServerConsole returned duplicate '$key': $resultText"
        }
        $values[$key] = $token.Groups["value"].Value
    }
    if ($values.ContainsKey("error"))
    {
        throw "Runtime probe rejected '$Arguments': $resultText"
    }

    [pscustomobject]@{
        Text = $resultText
        Values = $values
    }
}

function Assert-Field
{
    param(
        [Parameter(Mandatory = $true)] [object]$Result,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [string]$Expected
    )
    if (-not $Result.Values.ContainsKey($Name))
    {
        throw "Probe result is missing '$Name': $($Result.Text)"
    }
    if ([string]$Result.Values[$Name] -cne $Expected)
    {
        throw "Probe field '$Name' was '$($Result.Values[$Name])'; expected '$Expected': $($Result.Text)"
    }
}

function Get-IntegerField
{
    param([object]$Result, [string]$Name)
    if (-not $Result.Values.ContainsKey($Name))
    {
        throw "Probe result is missing '$Name': $($Result.Text)"
    }
    $value = 0
    if (-not [int]::TryParse([string]$Result.Values[$Name], [ref]$value))
    {
        throw "Probe field '$Name' is not an integer: $($Result.Text)"
    }
    return $value
}

function Get-BooleanField
{
    param([object]$Result, [string]$Name)
    if (-not $Result.Values.ContainsKey($Name))
    {
        throw "Probe result is missing '$Name': $($Result.Text)"
    }
    $value = [string]$Result.Values[$Name]
    if ($value -ceq "true") { return $true }
    if ($value -ceq "false") { return $false }
    throw "Probe field '$Name' is not a canonical boolean: $($Result.Text)"
}

function Get-TatooineServerProcessToken
{
    # This token comes from the Linux process table, not Java class state. A
    # script reload therefore cannot impersonate a game-server restart.
    $bashCommand = "pids=`$(pgrep -f '[b]in/SwgGameServer.*sceneID=tatooine' | sort -n); set -- `$pids; test `$# -eq 1 || { echo expected-one-tatooine-game-server-count-`$#-pids-`$pids >&2; exit 41; }; pid=`$1; start_ticks=`$(awk '{print `$22}' /proc/`$pid/stat); boot_id=`$(tr -d '\r\n' < /proc/sys/kernel/random/boot_id); printf '%s|%s|%s\n' `$boot_id `$pid `$start_ticks"
    $previousErrorActionPreference = $ErrorActionPreference
    try
    {
        $ErrorActionPreference = "Continue"
        $output = @(& docker exec $ContainerName bash -lc $bashCommand 2>&1)
        $dockerExitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($dockerExitCode -ne 0)
    {
        throw "Unable to identify the authoritative Tatooine SwgGameServer process: $($output -join ' ')"
    }
    $tokens = @($output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -match '^[a-f0-9-]{36}\|[0-9]+\|[0-9]+$' })
    if ($tokens.Count -ne 1)
    {
        throw "Docker returned no unique Tatooine process-lifetime token: $($output -join ' ')"
    }
    return [string]$tokens[0]
}

function Convert-IdentityMap
{
    param(
        [Parameter(Mandatory = $true)] [string]$Text,
        [Parameter(Mandatory = $true)] [string[]]$ExpectedKeys,
        [Parameter(Mandatory = $true)] [ValidateSet("Boolean", "Integer")] [string]$ValueType,
        [Parameter(Mandatory = $true)] [string]$Context
    )
    $map = [ordered]@{}
    foreach ($entry in @($Text.Split(",")))
    {
        $separator = $entry.LastIndexOf(":")
        if ($separator -le 0 -or $separator -eq ($entry.Length - 1))
        {
            throw "$Context contains malformed identity entry '$entry'."
        }
        $key = $entry.Substring(0, $separator)
        $rawValue = $entry.Substring($separator + 1)
        if ($map.Contains($key))
        {
            throw "$Context contains duplicate identity '$key'."
        }
        if ($ValueType -ceq "Boolean")
        {
            if ($rawValue -ceq "true") { $map[$key] = $true }
            elseif ($rawValue -ceq "false") { $map[$key] = $false }
            else { throw "$Context identity '$key' has non-boolean value '$rawValue'." }
        }
        else
        {
            $integerValue = 0
            if (-not [int]::TryParse($rawValue, [ref]$integerValue))
            {
                throw "$Context identity '$key' has non-integer value '$rawValue'."
            }
            $map[$key] = $integerValue
        }
    }
    $actualKeys = @($map.Keys | Sort-Object)
    $requiredKeys = @($ExpectedKeys | Sort-Object)
    if (($actualKeys -join "|") -cne ($requiredKeys -join "|"))
    {
        throw "$Context identity set drifted. actual=$($actualKeys -join ',') expected=$($requiredKeys -join ',')"
    }
    return $map
}

function Get-State
{
    $processTokenBefore = Get-TatooineServerProcessToken
    $result = Invoke-Probe -Arguments "craftingStatus $PlayerOid"
    Assert-Field -Result $result -Name "loaded" -Expected "true"
    Assert-Field -Result $result -Name "authoritative" -Expected "true"
    Assert-Field -Result $result -Name "contractId" -Expected $runtimeContractId
    Assert-Field -Result $result -Name "stationId" -Expected ([string]$stationId)
    Assert-Field -Result $result -Name "materializationFingerprint" -Expected $materializationFingerprint
    Assert-Field -Result $result -Name "deployedArtifactsVerified" -Expected "true"
    Assert-Field -Result $result -Name "skill" -Expected $engineeringSkill
    Assert-Field -Result $result -Name "noviceSkill" -Expected $noviceSkill
    Assert-Field -Result $result -Name "xpType" -Expected $xpType
    $null = Convert-IdentityMap -Text ([string]$result.Values["vectorCommands"]) -ExpectedKeys $expectedCommands -ValueType Boolean -Context "command vector"
    $null = Convert-IdentityMap -Text ([string]$result.Values["vectorMods"]) -ExpectedKeys $expectedMods -ValueType Integer -Context "skill-mod vector"
    $null = Convert-IdentityMap -Text ([string]$result.Values["vectorSchematics"]) -ExpectedKeys $expectedSchematics -ValueType Boolean -Context "schematic vector"
    $processTokenAfter = Get-TatooineServerProcessToken
    if ($processTokenAfter -cne $processTokenBefore)
    {
        throw "The authoritative Tatooine SwgGameServer process changed while its state was being sampled."
    }

    [pscustomobject]@{
        ContractId = [string]$result.Values["contractId"]
        StationId = Get-IntegerField -Result $result -Name "stationId"
        MaterializationFingerprint = [string]$result.Values["materializationFingerprint"]
        DeployedArtifactsVerified = Get-BooleanField -Result $result -Name "deployedArtifactsVerified"
        ServerProcessToken = $processTokenAfter
        LifecycleAttemptId = [string]$result.Values["lifecycleAttemptId"]
        LifecycleId = [string]$result.Values["lifecycleId"]
        LifecycleMarkerState = [string]$result.Values["lifecycleMarkerState"]
        LifecycleBaselineComplete = Get-BooleanField -Result $result -Name "lifecycleBaselineComplete"
        HasNovice = Get-BooleanField -Result $result -Name "hasNovice"
        HasSkill = Get-BooleanField -Result $result -Name "hasSkill"
        HasCommand = Get-BooleanField -Result $result -Name "hasCommand"
        HasSchematic = Get-BooleanField -Result $result -Name "hasSchematic"
        SkillCost = Get-IntegerField -Result $result -Name "skillCost"
        Points = Get-IntegerField -Result $result -Name "points"
        Xp = Get-IntegerField -Result $result -Name "xp"
        Cap = Get-IntegerField -Result $result -Name "cap"
        SkillModValue = Get-IntegerField -Result $result -Name "skillModValue"
        Cash = Get-IntegerField -Result $result -Name "cash"
        Bank = Get-IntegerField -Result $result -Name "bank"
        Credits = Get-IntegerField -Result $result -Name "credits"
        VectorCommandsOwned = Get-IntegerField -Result $result -Name "vectorCommandsOwned"
        VectorCommandsExpected = Get-IntegerField -Result $result -Name "vectorCommandsExpected"
        VectorModsMatched = Get-IntegerField -Result $result -Name "vectorModsMatched"
        VectorModsExpected = Get-IntegerField -Result $result -Name "vectorModsExpected"
        VectorSchematicsOwned = Get-IntegerField -Result $result -Name "vectorSchematicsOwned"
        VectorSchematicsExpected = Get-IntegerField -Result $result -Name "vectorSchematicsExpected"
        VectorComplete = Get-BooleanField -Result $result -Name "vectorComplete"
        VectorCommands = [string]$result.Values["vectorCommands"]
        VectorMods = [string]$result.Values["vectorMods"]
        VectorSchematics = [string]$result.Values["vectorSchematics"]
        OperationAttemptId = [string]$result.Values["operationAttemptId"]
        OperationId = [string]$result.Values["operationId"]
        OperationKind = [string]$result.Values["operationKind"]
        OperationState = [string]$result.Values["operationState"]
        OperationUpdated = Get-IntegerField -Result $result -Name "operationUpdated"
        OperationLifecycleId = [string]$result.Values["operationLifecycleId"]
        OperationTrainerOid = [string]$result.Values["operationTrainerOid"]
        OperationSkillName = [string]$result.Values["operationSkillName"]
        OperationCost = Get-IntegerField -Result $result -Name "operationCost"
        OperationProtocolVersion = Get-IntegerField -Result $result -Name "operationProtocolVersion"
        OperationRefundGeneration = Get-IntegerField -Result $result -Name "operationRefundGeneration"
        OperationRefundAttemptKey = [string]$result.Values["operationRefundAttemptKey"]
        OperationRefundRetryConsumed = Get-BooleanField -Result $result -Name "operationRefundRetryConsumed"
        OperationAccountingAttemptKey = [string]$result.Values["operationAccountingAttemptKey"]
        OperationAccountingAccount = [string]$result.Values["operationAccountingAccount"]
        OperationAccountingOutcome = [string]$result.Values["operationAccountingOutcome"]
        OperationMarkerComplete = Get-BooleanField -Result $result -Name "operationMarkerComplete"
        OperationPreimageMatches = Get-BooleanField -Result $result -Name "operationPreimageMatches"
        RelogNoncePresent = Get-BooleanField -Result $result -Name "relogNoncePresent"
        RestartNoncePresent = Get-BooleanField -Result $result -Name "restartNoncePresent"
        NewbieFreeTrainingRouteActive = Get-BooleanField -Result $result -Name "newbieFreeTrainingRouteActive"
        ProbeText = $result.Text
    }
}

function Resolve-ExternalSnapshotPath
{
    if ([string]::IsNullOrWhiteSpace($SnapshotPath))
    {
        throw "Mode $Mode requires -SnapshotPath."
    }
    $fullPath = [System.IO.Path]::GetFullPath($SnapshotPath)
    $fullRepositoryRoot = [System.IO.Path]::GetFullPath($repositoryRoot).TrimEnd("\")
    $repositoryPrefix = $fullRepositoryRoot + "\"
    if ($fullPath.Equals($fullRepositoryRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase))
    {
        throw "Snapshot must remain outside the implementation repository: $fullPath"
    }
    return $fullPath
}

function Enter-MutationLocks
{
    $resolvedSnapshotPath = Resolve-ExternalSnapshotPath
    $snapshotParent = Split-Path -Parent $resolvedSnapshotPath
    if (-not (Test-Path -LiteralPath $snapshotParent -PathType Container))
    {
        throw "Snapshot parent directory does not exist: $snapshotParent"
    }

    $playerLockRoot = Join-Path ([System.IO.Path]::GetTempPath()) "swg-precu-phase-a-locks"
    if (-not (Test-Path -LiteralPath $playerLockRoot -PathType Container))
    {
        $null = New-Item -ItemType Directory -Path $playerLockRoot -Force
    }
    $playerLockPath = Join-Path $playerLockRoot ("$ContainerName.$PlayerOid.lock")
    $snapshotLockPath = $resolvedSnapshotPath + ".lock"
    $playerStream = $null
    $snapshotStream = $null
    try
    {
        $playerStream = [System.IO.File]::Open(
            $playerLockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
        $snapshotStream = [System.IO.File]::Open(
            $snapshotLockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
    }
    catch
    {
        if ($null -ne $snapshotStream) { $snapshotStream.Dispose() }
        if ($null -ne $playerStream) { $playerStream.Dispose() }
        throw "Lifecycle lock acquisition failed closed for container/player '$ContainerName/$PlayerOid' and snapshot '$resolvedSnapshotPath': $($_.Exception.Message)"
    }

    [pscustomobject]@{
        ResolvedSnapshotPath = $resolvedSnapshotPath
        PlayerLockPath = $playerLockPath
        SnapshotLockPath = $snapshotLockPath
        PlayerStream = $playerStream
        SnapshotStream = $snapshotStream
    }
}

function Exit-MutationLocks
{
    param([object]$Locks)
    if ($null -eq $Locks) { return }
    if ($null -ne $Locks.SnapshotStream) { $Locks.SnapshotStream.Dispose() }
    if ($null -ne $Locks.PlayerStream) { $Locks.PlayerStream.Dispose() }
}

function Save-SnapshotAtomic
{
    param([Parameter(Mandatory = $true)] [object]$Snapshot)
    # Serialize only a detached, schema-validated clone.  This prevents a
    # partially mutated in-memory lifecycle from becoming durable evidence.
    $normalizedSnapshot = Copy-OfflineObject -Value $Snapshot
    Assert-LifecycleSnapshot -Lifecycle $normalizedSnapshot -CurrentIdentity $normalizedSnapshot.identity
    $resolvedPath = Resolve-ExternalSnapshotPath
    $parent = Split-Path -Parent $resolvedPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container))
    {
        throw "Snapshot parent directory does not exist: $parent"
    }
    $temporaryPath = Join-Path $parent ("." + [System.IO.Path]::GetFileName($resolvedPath) + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    $backupPath = Join-Path $parent ("." + [System.IO.Path]::GetFileName($resolvedPath) + "." + [guid]::NewGuid().ToString("N") + ".bak")
    $json = $normalizedSnapshot | ConvertTo-Json -Depth 12
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream = $null
    try
    {
        $stream = [System.IO.File]::Open($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        if (Test-Path -LiteralPath $resolvedPath -PathType Leaf)
        {
            # Windows PowerShell 5.1 rejects a null backup path even though
            # newer .NET runtimes accept it.  A same-directory backup keeps
            # replacement atomic on NTFS and is removed only after success.
            [System.IO.File]::Replace($temporaryPath, $resolvedPath, $backupPath)
            Remove-Item -LiteralPath $backupPath -Force
        }
        else
        {
            [System.IO.File]::Move($temporaryPath, $resolvedPath)
        }
    }
    finally
    {
        if ($null -ne $stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf)
        {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf)
        {
            Remove-Item -LiteralPath $backupPath -Force
        }
    }
}

function Get-ExecutionIdentity
{
    param([Parameter(Mandatory = $true)] [object]$State)
    $previousErrorActionPreference = $ErrorActionPreference
    try
    {
        $ErrorActionPreference = "Continue"
        $inspectOutput = @(& docker inspect --format '{{.Id}}|{{.Image}}|{{.Name}}' $ContainerName 2>&1)
        $inspectExitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($inspectExitCode -ne 0 -or $inspectOutput.Count -ne 1)
    {
        throw "Unable to establish unique container identity for '$ContainerName': $($inspectOutput -join ' ')"
    }
    $parts = @(([string]$inspectOutput[0]).Trim().Split("|"))
    if ($parts.Count -ne 3 -or $parts[2].TrimStart("/") -cne $ContainerName)
    {
        throw "Docker returned an unexpected container identity: $($inspectOutput[0])"
    }
    [pscustomobject]@{
        RunnerSchemaVersion = $runnerSchemaVersion
        RunnerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
        RuntimeContractId = $State.ContractId
        RuntimeMaterializationFingerprint = $State.MaterializationFingerprint
        ContractSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $contractPath).Hash
        ManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
        RuntimePatchSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimePatchPath).Hash
        MarkerPatchSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $markerPatchPath).Hash
        BaselineSuperprojectCommit = [string]$manifest.target.baselineSuperprojectCommit
        ContainerName = $ContainerName
        ContainerId = $parts[0]
        ContainerImageId = $parts[1]
    }
}

function Assert-PropertySet
{
    param([object]$Value, [string[]]$Expected, [string]$Context)
    if ($null -eq $Value)
    {
        throw "$Context is null."
    }
    $actual = @($Value.psobject.Properties.Name | Sort-Object)
    $required = @($Expected | Sort-Object)
    if (($actual -join "|") -cne ($required -join "|"))
    {
        throw "$Context property set drifted. actual=$($actual -join ',') expected=$($required -join ',')"
    }
}

function Assert-StringValue
{
    param([object]$Value, [string]$Context, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace([string]$Value)))
    {
        throw "$Context must be a non-empty string."
    }
}

function Assert-IntegerValue
{
    param([object]$Value, [string]$Context)
    if ($Value -isnot [int] -and $Value -isnot [long])
    {
        throw "$Context must be an integer."
    }
}

function Assert-UtcTimestamp
{
    param([object]$Value, [string]$Context, [switch]$AllowEmpty)
    Assert-StringValue -Value $Value -Context $Context -AllowEmpty:$AllowEmpty
    if ($AllowEmpty -and [string]::IsNullOrEmpty([string]$Value)) { return }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParseExact(
        [string]$Value,
        "o",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$parsed) -or -not ([string]$Value).EndsWith("Z", [StringComparison]::Ordinal))
    {
        throw "$Context must be an invariant UTC round-trip timestamp."
    }
}

function Convert-UtcTimestamp
{
    param([string]$Value, [string]$Context)
    Assert-UtcTimestamp -Value $Value -Context $Context
    return [DateTimeOffset]::ParseExact(
        $Value,
        "o",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal)
}

function New-StateSnapshot
{
    param([Parameter(Mandatory = $true)] [object]$State)
    $copy = [ordered]@{}
    foreach ($name in $snapshotStateFields)
    {
        $copy[$name] = $State.$name
    }
    return [pscustomobject]$copy
}

function Assert-StateShape
{
    param([object]$State, [string]$Context)
    Assert-PropertySet -Value $State -Expected $snapshotStateFields -Context $Context
    foreach ($name in @(
        "ContractId", "MaterializationFingerprint", "ServerProcessToken",
        "LifecycleAttemptId", "LifecycleId", "LifecycleMarkerState",
        "VectorCommands", "VectorMods", "VectorSchematics", "OperationAttemptId",
        "OperationId", "OperationKind", "OperationState", "OperationLifecycleId",
        "OperationTrainerOid", "OperationSkillName", "OperationRefundAttemptKey",
        "OperationAccountingAttemptKey", "OperationAccountingAccount",
        "OperationAccountingOutcome"))
    {
        Assert-StringValue -Value $State.$name -Context "$Context.$name" -AllowEmpty
    }
    foreach ($name in @("StationId", "SkillCost", "Points", "Xp", "Cap", "SkillModValue", "Cash", "Bank", "Credits", "VectorCommandsOwned", "VectorCommandsExpected", "VectorModsMatched", "VectorModsExpected", "VectorSchematicsOwned", "VectorSchematicsExpected", "OperationUpdated", "OperationCost", "OperationProtocolVersion", "OperationRefundGeneration"))
    {
        Assert-IntegerValue -Value $State.$name -Context "$Context.$name"
    }
    foreach ($name in @("DeployedArtifactsVerified", "LifecycleBaselineComplete", "HasNovice", "HasSkill", "HasCommand", "HasSchematic", "VectorComplete", "OperationRefundRetryConsumed", "OperationMarkerComplete", "OperationPreimageMatches", "RelogNoncePresent", "RestartNoncePresent", "NewbieFreeTrainingRouteActive"))
    {
        if ($State.$name -isnot [bool]) { throw "$Context.$name must be boolean." }
    }
    if ([string]$State.ContractId -cne $runtimeContractId -or [int]$State.StationId -ne $stationId -or
        [string]$State.MaterializationFingerprint -cne $materializationFingerprint -or
        -not [bool]$State.DeployedArtifactsVerified)
    {
        throw "$Context deployed runtime identity does not match this runner."
    }
    if ([string]$State.ServerProcessToken -notmatch '^[a-f0-9-]{36}\|[0-9]+\|[0-9]+$')
    {
        throw "$Context has an invalid Tatooine server-process token."
    }
    if ([string]$State.LifecycleAttemptId -cne "none" -and [string]$State.LifecycleAttemptId -notmatch '^[a-f0-9]{32}$')
    {
        throw "$Context has an invalid lifecycle attempt marker."
    }
    if ([string]$State.LifecycleId -cne "none" -and [string]$State.LifecycleId -notmatch '^[a-f0-9]{32}$')
    {
        throw "$Context has an invalid committed lifecycle marker."
    }
    if ([string]$State.LifecycleMarkerState -cnotin @("none", "partial", "complete", "corrupt"))
    {
        throw "$Context has an invalid lifecycle marker state."
    }
    if (([string]$State.LifecycleMarkerState -ceq "none" -and
            ([string]$State.LifecycleAttemptId -cne "none" -or
             [string]$State.LifecycleId -cne "none" -or $State.LifecycleBaselineComplete)) -or
        ([string]$State.LifecycleMarkerState -ceq "partial" -and
            ([string]$State.LifecycleAttemptId -eq "none" -or [string]$State.LifecycleId -cne "none")) -or
        ([string]$State.LifecycleMarkerState -ceq "complete" -and
            ([string]$State.LifecycleAttemptId -cne [string]$State.LifecycleId -or
             -not $State.LifecycleBaselineComplete)))
    {
        throw "$Context lifecycle marker fields are internally inconsistent."
    }
    if ([string]$State.LifecycleMarkerState -ceq "corrupt")
    {
        throw "$Context contains corrupt lifecycle instrumentation."
    }
    if ([string]$State.OperationAttemptId -eq "none")
    {
        if ([string]$State.OperationId -cne "none" -or
            [string]$State.OperationKind -cne "none" -or
            [string]$State.OperationState -cne "none" -or
            [string]$State.OperationLifecycleId -cne "none" -or
            [string]$State.OperationTrainerOid -cne "none" -or
            [string]$State.OperationSkillName -cne "none" -or
            [int]$State.OperationCost -ne 0 -or
            [int]$State.OperationProtocolVersion -ne 0 -or
            [int]$State.OperationRefundGeneration -ne 0 -or
            [string]$State.OperationRefundAttemptKey -cne "none" -or
            $State.OperationRefundRetryConsumed -or
            [string]$State.OperationAccountingAttemptKey -cne "none" -or
            [string]$State.OperationAccountingAccount -cne "none" -or
            [string]$State.OperationAccountingOutcome -cne "none" -or
            $State.OperationMarkerComplete)
        {
            throw "$Context contains an unanchored operation marker."
        }
    }
    elseif ([string]$State.OperationAttemptId -notmatch '^[a-f0-9]{32}$')
    {
        throw "$Context has an invalid operation attempt marker."
    }
    if ($State.OperationMarkerComplete -and
        ([string]$State.OperationId -cne [string]$State.OperationAttemptId -or
         [string]$State.OperationLifecycleId -cne [string]$State.LifecycleId -or
         [int]$State.OperationUpdated -le 0 -or
         [int]$State.OperationCost -ne $trainerCost -or
         [int]$State.OperationProtocolVersion -ne 64))
    {
        throw "$Context complete operation marker correlation is invalid."
    }
    if ($State.OperationMarkerComplete)
    {
        $operationState = [string]$State.OperationState
        $operationId = [string]$State.OperationId
        $initialRefundStates = @("refundInitialClaiming", "refundInitialDispatching", "refundInitialPending", "refundInitialFailed")
        $recoveryRefundStates = @("refundRecoveryClaiming", "refundRecoveryDispatching", "refundRecoveryPending", "refundRecoveryFailed")
        $accountingOutcomesByState = @{
            accountingRequested = @("none", "REQUEST_QUEUE_FAILED")
            accountingDispatching = @("none", "QUEUE_FAILED", "FAILED", "SUCCESS")
            accountingPending = @("none", "FAILED", "SUCCESS")
            accountingRequestQueueFailed = @("REQUEST_QUEUE_FAILED")
            accountingQueueFailed = @("QUEUE_FAILED")
            accountingFailed = @("FAILED")
            accountingSucceededCallback = @("SUCCESS")
            purchaseSucceeded = @("SUCCESS")
        }
        $refundState = $operationState -cin ($initialRefundStates + $recoveryRefundStates + @("purchaseRefunded"))
        $accountingState = $operationState -cin @($accountingOutcomesByState.Keys)
        if ($refundState)
        {
            $generation = [int]$State.OperationRefundGeneration
            $expectedGeneration = if ($operationState -cin $initialRefundStates) { 1 } elseif ($operationState -cin $recoveryRefundStates) { 2 } else { $generation }
            if ($expectedGeneration -notin @(1, 2) -or $generation -ne $expectedGeneration -or
                [string]$State.OperationRefundAttemptKey -cne "$operationId.refund.$generation" -or
                [bool]$State.OperationRefundRetryConsumed -ne ($generation -eq 2) -or
                [string]$State.OperationAccountingAttemptKey -cne "none" -or
                [string]$State.OperationAccountingAccount -cne "none" -or
                [string]$State.OperationAccountingOutcome -cne "none")
            {
                throw "$Context refund provenance is not exact for '$operationState'."
            }
        }
        elseif ($accountingState)
        {
            $allowedOutcomes = @($accountingOutcomesByState[$operationState])
            if ([string]$State.OperationAccountingAttemptKey -cne "$operationId.accounting.1" -or
                [string]$State.OperationAccountingAccount -cne "skillTrainingSystem" -or
                [string]$State.OperationAccountingOutcome -cnotin $allowedOutcomes -or
                [int]$State.OperationRefundGeneration -ne 0 -or
                [string]$State.OperationRefundAttemptKey -cne "none" -or
                [bool]$State.OperationRefundRetryConsumed)
            {
                throw "$Context accounting provenance is not exact for '$operationState'."
            }
        }
        elseif ([int]$State.OperationRefundGeneration -ne 0 -or
            [string]$State.OperationRefundAttemptKey -cne "none" -or
            [bool]$State.OperationRefundRetryConsumed -or
            [string]$State.OperationAccountingAttemptKey -cne "none" -or
            [string]$State.OperationAccountingAccount -cne "none" -or
            [string]$State.OperationAccountingOutcome -cne "none")
        {
            throw "$Context non-refund/accounting state carries attempt provenance."
        }
    }
    $null = Convert-IdentityMap -Text ([string]$State.VectorCommands) -ExpectedKeys $expectedCommands -ValueType Boolean -Context "$Context command vector"
    $null = Convert-IdentityMap -Text ([string]$State.VectorMods) -ExpectedKeys $expectedMods -ValueType Integer -Context "$Context skill-mod vector"
    $null = Convert-IdentityMap -Text ([string]$State.VectorSchematics) -ExpectedKeys $expectedSchematics -ValueType Boolean -Context "$Context schematic vector"
}

function Assert-StatePersistentEquals
{
    param([object]$Actual, [object]$Expected, [string]$Context)
    foreach ($name in $persistentStateFields)
    {
        if ($Actual.$name -ne $Expected.$name)
        {
            throw "$Context mismatch '$name': actual=$($Actual.$name) expected=$($Expected.$name)"
        }
    }
}

function Assert-NoOperationInstrumentation
{
    param([object]$State, [string]$Context)
    if ([string]$State.OperationAttemptId -cne "none" -or
        [string]$State.OperationId -cne "none" -or
        [string]$State.OperationKind -cne "none" -or
        [string]$State.OperationState -cne "none" -or
        [int]$State.OperationUpdated -ne 0 -or
        [string]$State.OperationLifecycleId -cne "none" -or
        [string]$State.OperationTrainerOid -cne "none" -or
        [string]$State.OperationSkillName -cne "none" -or
        [int]$State.OperationCost -ne 0 -or
        [int]$State.OperationProtocolVersion -ne 0 -or
        [int]$State.OperationRefundGeneration -ne 0 -or
        [string]$State.OperationRefundAttemptKey -cne "none" -or
        $State.OperationRefundRetryConsumed -or
        [string]$State.OperationAccountingAttemptKey -cne "none" -or
        [string]$State.OperationAccountingAccount -cne "none" -or
        [string]$State.OperationAccountingOutcome -cne "none" -or
        $State.OperationMarkerComplete -or
        $State.OperationPreimageMatches)
    {
        throw "$Context retains operation instrumentation."
    }
}

function Assert-StateGameplayEquals
{
    param([object]$Actual, [object]$Expected, [string]$Context)
    foreach ($name in $gameplayStateFields)
    {
        if ($Actual.$name -ne $Expected.$name)
        {
            throw "$Context mismatch '$name': actual=$($Actual.$name) expected=$($Expected.$name)"
        }
    }
}

function Assert-ExecutionIdentity
{
    param([object]$Actual, [object]$Expected)
    $fields = @("RunnerSchemaVersion", "RunnerSha256", "RuntimeContractId", "RuntimeMaterializationFingerprint", "ContractSha256", "ManifestSha256", "RuntimePatchSha256", "MarkerPatchSha256", "BaselineSuperprojectCommit", "ContainerName", "ContainerId", "ContainerImageId")
    Assert-PropertySet -Value $Expected -Expected $fields -Context "snapshot.identity"
    foreach ($field in $fields)
    {
        if ($field -ceq "RunnerSchemaVersion")
        {
            Assert-IntegerValue -Value $Expected.$field -Context "snapshot.identity.$field"
            if ([int]$Actual.$field -ne [int]$Expected.$field)
            {
                throw "Execution identity mismatch '$field': current=$($Actual.$field) snapshot=$($Expected.$field)"
            }
            continue
        }
        Assert-StringValue -Value $Expected.$field -Context "snapshot.identity.$field"
        if ([string]$Actual.$field -cne [string]$Expected.$field)
        {
            throw "Execution identity mismatch '$field': current=$($Actual.$field) snapshot=$($Expected.$field)"
        }
    }
}

function Assert-PreparedRelation
{
    param([object]$Lifecycle)
    $baseline = $Lifecycle.baseline
    $prepared = $Lifecycle.prepared
    if ($null -eq $prepared) { throw "Prepared lifecycle state is missing." }
    if (-not $prepared.HasNovice -or $prepared.HasSkill -or $prepared.HasCommand -or $prepared.HasSchematic)
    {
        throw "Prepared lifecycle has invalid skill ownership."
    }
    if ([int]$prepared.Xp -ne ([int]$baseline.Xp + $xpCost) -or
        [int]$prepared.Credits -ne ([int]$baseline.Credits + $trainerCost) -or
        [int]$prepared.Cash -ne [int]$baseline.Cash -or
        [int]$prepared.Bank -ne ([int]$baseline.Bank + $trainerCost) -or
        [int]$prepared.Cap -ne 1500)
    {
        throw "Prepared lifecycle does not contain the exact XP/bank-funded credit setup."
    }
    $expectedPreparedPoints = [int]$baseline.Points - ($(if ([bool]$Lifecycle.noviceAdded) { $novicePointCost } else { 0 }))
    if ([int]$prepared.Points -ne $expectedPreparedPoints -or [int]$prepared.Points -lt $engineeringPointCost)
    {
        throw "Prepared lifecycle skill-point relation is invalid."
    }
    Assert-NoOperationInstrumentation -State $prepared -Context "Prepared lifecycle"
    if ([string]$prepared.LifecycleAttemptId -cne [string]$Lifecycle.lifecycleId -or
        [string]$prepared.LifecycleId -cne [string]$Lifecycle.lifecycleId -or
        [string]$prepared.LifecycleMarkerState -cne "complete" -or
        -not $prepared.LifecycleBaselineComplete -or
        $prepared.RelogNoncePresent -or $prepared.RestartNoncePresent)
    {
        throw "Prepared lifecycle marker/nonces are not exact."
    }
    $commands = Convert-IdentityMap -Text ([string]$prepared.VectorCommands) -ExpectedKeys $expectedCommands -ValueType Boolean -Context "prepared commands"
    if (-not [bool]$commands[$expectedCommands[0]] -or [bool]$commands[$expectedCommands[1]])
    {
        throw "Prepared command identities are not exact novice-only ownership."
    }
    $schematics = Convert-IdentityMap -Text ([string]$prepared.VectorSchematics) -ExpectedKeys $expectedSchematics -ValueType Boolean -Context "prepared schematics"
    foreach ($name in $expectedSchematics)
    {
        $expectedOwned = $name -cnotin $purchaseSchematics
        if ([bool]$schematics[$name] -ne $expectedOwned)
        {
            throw "Prepared schematic identity '$name' was '$($schematics[$name])'; expected '$expectedOwned'."
        }
    }
    $preparedMods = Convert-IdentityMap -Text ([string]$prepared.VectorMods) -ExpectedKeys $expectedMods -ValueType Integer -Context "prepared mods"
    $preparedModsMatched = 0
    foreach ($name in $expectedMods)
    {
        $absolute = [int]$runtimeContract.completeGrantVector.skillMods.$name
        $preparedExpected = $absolute - [int]$purchaseModDeltas.$name
        if ([int]$preparedMods[$name] -ne $preparedExpected)
        {
            throw "Prepared modifier '$name' is not the exact contract absolute-minus-purchase delta."
        }
        if ($preparedExpected -eq $absolute) { $preparedModsMatched++ }
    }
    if ($prepared.VectorComplete -or $prepared.NewbieFreeTrainingRouteActive -or
        [int]$prepared.VectorCommandsOwned -ne 1 -or
        [int]$prepared.VectorCommandsExpected -ne $expectedCommands.Count -or
        [int]$prepared.VectorModsMatched -ne $preparedModsMatched -or
        [int]$prepared.VectorModsExpected -ne $expectedMods.Count -or
        [int]$prepared.VectorSchematicsOwned -ne ($expectedSchematics.Count - $purchaseSchematics.Count) -or
        [int]$prepared.VectorSchematicsExpected -ne $expectedSchematics.Count)
    {
        throw "Prepared identity-vector counts/flags drifted from the exact contract."
    }
}

function Assert-HeldRelation
{
    param([object]$Lifecycle, [object]$Held)
    $prepared = $Lifecycle.prepared
    $evidence = $Lifecycle.purchaseEvidence
    if ($null -eq $evidence) { throw "Held lifecycle lacks immutable purchase evidence." }
    if (-not $Held.HasNovice -or -not $Held.HasSkill -or -not $Held.HasCommand -or -not $Held.HasSchematic)
    {
        throw "Held lifecycle is missing Engineering I ownership/grants."
    }
    $bankDebit = [Math]::Min([int]$prepared.Bank, $trainerCost)
    $cashDebit = $trainerCost - $bankDebit
    if ([int]$Held.Cash -ne ([int]$prepared.Cash - $cashDebit) -or
        [int]$Held.Bank -ne ([int]$prepared.Bank - $bankDebit) -or
        [int]$Held.Credits -ne ([int]$prepared.Credits - $trainerCost) -or
        [int]$Held.Xp -ne ([int]$prepared.Xp - $xpCost) -or
        [int]$Held.Points -ne ([int]$prepared.Points - $engineeringPointCost) -or
        [int]$Held.Cap -ne 2000 -or [int]$Held.SkillCost -ne $engineeringPointCost)
    {
        throw "Held lifecycle does not contain the exact bank-first cash/bank/credit/XP/point debit."
    }
    if ([string]$Held.OperationAttemptId -cne [string]$evidence.operationId -or
        [string]$Held.OperationId -cne [string]$evidence.operationId -or
        [string]$Held.OperationKind -cne "purchase" -or
        [string]$Held.OperationState -cne "purchaseSucceeded" -or
        [int]$Held.OperationUpdated -le 0 -or
        [string]$Held.OperationLifecycleId -cne [string]$evidence.lifecycleId -or
        [string]$Held.OperationTrainerOid -cne [string]$evidence.trainerOid -or
        [string]$Held.OperationSkillName -cne [string]$evidence.skillName -or
        [int]$Held.OperationCost -ne [int]$evidence.cost -or
        [int]$Held.OperationProtocolVersion -ne 64 -or
        [int]$Held.OperationRefundGeneration -ne 0 -or
        [string]$Held.OperationRefundAttemptKey -cne "none" -or
        [bool]$Held.OperationRefundRetryConsumed -or
        [string]$Held.OperationAccountingAttemptKey -cne [string]$evidence.accountingAttemptKey -or
        [string]$Held.OperationAccountingAccount -cne "skillTrainingSystem" -or
        [string]$Held.OperationAccountingOutcome -cne "SUCCESS" -or
        -not $Held.OperationMarkerComplete)
    {
        throw "Held lifecycle lacks a terminal production purchase marker."
    }
    if ([string]$Held.LifecycleAttemptId -cne [string]$Lifecycle.lifecycleId -or
        [string]$Held.LifecycleId -cne [string]$Lifecycle.lifecycleId -or
        [string]$Held.LifecycleMarkerState -cne "complete" -or
        -not $Held.LifecycleBaselineComplete)
    {
        throw "Held lifecycle is not owned by the snapshot lifecycle marker."
    }
    if ($Held.NewbieFreeTrainingRouteActive)
    {
        throw "Held purchase used the excluded newbie free-training route."
    }
    if ([string]$evidence.outcomeSource -ceq "callback")
    {
        if ([string]$Held.ServerProcessToken -cne [string]$evidence.originProcessToken -or
            [string]$evidence.outcomeProcessToken -cne [string]$evidence.originProcessToken -or
            -not $Held.RelogNoncePresent -or $Held.RestartNoncePresent)
        {
            throw "Callback-held volatile process/relog proof is not exact."
        }
    }
    elseif ([string]$evidence.outcomeSource -ceq "restartAccountingResume")
    {
        if ([string]$Held.ServerProcessToken -cne [string]$evidence.outcomeProcessToken -or
            [string]$evidence.outcomeProcessToken -ceq [string]$evidence.originProcessToken -or
            $Held.RelogNoncePresent -or $Held.RestartNoncePresent)
        {
            throw "Recovered held state lacks the exact changed-process/vanished-volatile proof."
        }
    }
    elseif ([string]$evidence.outcomeSource -ceq "restartCallbackReplay")
    {
        if ([string]$Held.ServerProcessToken -cne [string]$evidence.outcomeProcessToken -or
            [string]$evidence.outcomeProcessToken -ceq [string]$evidence.originProcessToken -or
            -not $Held.RelogNoncePresent -or $Held.RestartNoncePresent)
        {
            throw "Replayed callback held state lacks exact changed-process/relog proof."
        }
    }
    else
    {
        throw "Held purchase evidence has unsupported outcome source '$($evidence.outcomeSource)'."
    }
    if ($null -ne $Lifecycle.operation -and
        ([string]$Lifecycle.operation.kind -cne "purchase" -or
         [string]$Lifecycle.operation.id -cne [string]$evidence.operationId))
    {
        throw "Held operation is not the snapshot's correlated purchase operation."
    }
    $commands = Convert-IdentityMap -Text ([string]$Held.VectorCommands) -ExpectedKeys $expectedCommands -ValueType Boolean -Context "held commands"
    foreach ($name in $expectedCommands)
    {
        if (-not [bool]$commands[$name]) { throw "Held command identity '$name' is missing." }
    }
    $schematics = Convert-IdentityMap -Text ([string]$Held.VectorSchematics) -ExpectedKeys $expectedSchematics -ValueType Boolean -Context "held schematics"
    foreach ($name in $expectedSchematics)
    {
        if (-not [bool]$schematics[$name]) { throw "Held schematic identity '$name' is missing." }
    }
    $preparedMods = Convert-IdentityMap -Text ([string]$prepared.VectorMods) -ExpectedKeys $expectedMods -ValueType Integer -Context "prepared mods"
    $heldMods = Convert-IdentityMap -Text ([string]$Held.VectorMods) -ExpectedKeys $expectedMods -ValueType Integer -Context "held mods"
    foreach ($name in $expectedMods)
    {
        $absolute = [int]$runtimeContract.completeGrantVector.skillMods.$name
        $delta = [int]$purchaseModDeltas.$name
        $preparedExpected = $absolute - $delta
        if ([int]$preparedMods[$name] -ne $preparedExpected -or
            [int]$heldMods[$name] -ne $absolute -or
            [int]$heldMods[$name] -ne ([int]$preparedMods[$name] + $delta))
        {
            throw "Exact prepared/held modifier contract failed for '$name'."
        }
    }
    if (-not [bool]$Held.VectorComplete -or
        [int]$Held.VectorCommandsOwned -ne $expectedCommands.Count -or
        [int]$Held.VectorCommandsExpected -ne $expectedCommands.Count -or
        [int]$Held.VectorModsMatched -ne $expectedMods.Count -or
        [int]$Held.VectorModsExpected -ne $expectedMods.Count -or
        [int]$Held.VectorSchematicsExpected -ne $expectedSchematics.Count -or
        [int]$Held.VectorSchematicsOwned -ne $expectedSchematics.Count)
    {
        throw "Held identity-vector counts drifted from the contract."
    }
}

function Assert-BoundaryShape
{
    param([object]$Boundary, [string]$Context)
    Assert-PropertySet -Value $Boundary -Expected @("Kind", "OperationId", "ServerProcessToken", "VerifiedAtUtc") -Context $Context
    foreach ($name in @("Kind", "OperationId", "ServerProcessToken", "VerifiedAtUtc"))
    {
        Assert-StringValue -Value $Boundary.$name -Context "$Context.$name"
    }
    if ([string]$Boundary.OperationId -notmatch '^[a-f0-9]{32}$' -or
        [string]$Boundary.ServerProcessToken -notmatch '^[a-f0-9-]{36}\|[0-9]+\|[0-9]+$')
    {
        throw "$Context operation/process identity is invalid."
    }
    Assert-UtcTimestamp -Value $Boundary.VerifiedAtUtc -Context "$Context.VerifiedAtUtc"
}

function Assert-PurchaseEvidenceShape
{
    param([object]$Lifecycle)
    $evidence = $Lifecycle.purchaseEvidence
    if ($null -eq $evidence) { return }
    Assert-PropertySet -Value $evidence -Expected @(
        "operationId", "lifecycleId", "trainerOid", "skillName", "cost",
        "accountingAttemptKey", "originProcessToken", "outcomeProcessToken",
        "outcomeSource", "terminalAtUtc"
    ) -Context "snapshot.purchaseEvidence"
    foreach ($name in @("operationId", "lifecycleId", "trainerOid", "skillName", "accountingAttemptKey", "originProcessToken", "outcomeProcessToken", "outcomeSource", "terminalAtUtc"))
    {
        Assert-StringValue -Value $evidence.$name -Context "snapshot.purchaseEvidence.$name"
    }
    Assert-IntegerValue -Value $evidence.cost -Context "snapshot.purchaseEvidence.cost"
    Assert-UtcTimestamp -Value $evidence.terminalAtUtc -Context "snapshot.purchaseEvidence.terminalAtUtc"
    if ([string]$evidence.operationId -notmatch '^[a-f0-9]{32}$' -or
        [string]$evidence.lifecycleId -cne [string]$Lifecycle.lifecycleId -or
        [string]$evidence.trainerOid -notmatch '^[0-9]+$' -or
        [string]$evidence.skillName -cne $engineeringSkill -or
        [int]$evidence.cost -ne $trainerCost -or
        [string]$evidence.accountingAttemptKey -cne "$($evidence.operationId).accounting.1" -or
        [string]$evidence.originProcessToken -notmatch '^[a-f0-9-]{36}\|[0-9]+\|[0-9]+$' -or
        [string]$evidence.outcomeProcessToken -notmatch '^[a-f0-9-]{36}\|[0-9]+\|[0-9]+$' -or
        [string]$evidence.outcomeSource -cnotin @("callback", "restartAccountingResume", "restartCallbackReplay"))
    {
        throw "Snapshot purchase evidence identity is invalid."
    }
    if (([string]$evidence.outcomeSource -ceq "callback" -and
            [string]$evidence.originProcessToken -cne [string]$evidence.outcomeProcessToken) -or
        ([string]$evidence.outcomeSource -cin @("restartAccountingResume", "restartCallbackReplay") -and
            [string]$evidence.originProcessToken -ceq [string]$evidence.outcomeProcessToken))
    {
        throw "Snapshot purchase evidence process/source relation is invalid."
    }
    if ($null -ne $Lifecycle.conversation -and
        [string]$Lifecycle.conversation.trainerOid -cne [string]$evidence.trainerOid)
    {
        throw "Snapshot purchase evidence is not correlated with the queued trainer."
    }
    if ($null -ne $Lifecycle.operation -and
        ([string]$Lifecycle.operation.id -cne [string]$evidence.operationId -or
         [string]$Lifecycle.operation.lifecycleId -cne [string]$evidence.lifecycleId -or
         [string]$Lifecycle.operation.trainerOid -cne [string]$evidence.trainerOid -or
         [string]$Lifecycle.operation.skillName -cne [string]$evidence.skillName -or
         [int]$Lifecycle.operation.cost -ne [int]$evidence.cost -or
         [string]$Lifecycle.operation.accountingAttemptKey -cne [string]$evidence.accountingAttemptKey -or
         [string]$Lifecycle.operation.accountingOutcome -cne "SUCCESS"))
    {
        throw "Snapshot purchase evidence is not correlated with its operation record."
    }
}

function Assert-LifecycleSnapshot
{
    param([object]$Lifecycle, [object]$CurrentIdentity)

    $topFields = @(
        "schemaVersion", "playerOid", "lifecycleId", "createdAtUtc", "phase",
        "identity", "setup", "noviceAdded", "baseline", "prepared",
        "conversation", "operation", "purchaseEvidence", "held", "boundaries", "surrendered",
        "cleanup", "final", "lastError"
    )
    Assert-PropertySet -Value $Lifecycle -Expected $topFields -Context "snapshot"
    Assert-IntegerValue -Value $Lifecycle.schemaVersion -Context "snapshot.schemaVersion"
    if ([int]$Lifecycle.schemaVersion -ne $snapshotSchemaVersion -or
        $Lifecycle.playerOid -isnot [string] -or [string]$Lifecycle.playerOid -cne $PlayerOid -or
        $Lifecycle.lifecycleId -isnot [string] -or [string]$Lifecycle.lifecycleId -notmatch '^[a-f0-9]{32}$')
    {
        throw "Snapshot schema/player/lifecycle does not match this v8 runner."
    }
    Assert-UtcTimestamp -Value $Lifecycle.createdAtUtc -Context "snapshot.createdAtUtc"
    Assert-ExecutionIdentity -Actual $CurrentIdentity -Expected $Lifecycle.identity

    $activePhases = @(
        "lifecyclePending", "preparing", "fundingPending", "prepared",
        "conversationPending", "conversationQueued", "purchasePending", "held",
        "restartBoundaryArming", "relogVerified", "restartVerified"
    )
    $cleanupPhases = @("cleanupPending", "releasePending")
    $terminalPhases = @("complete", "cleaned")
    $legalPhases = @($activePhases + $cleanupPhases + $terminalPhases)
    if ($Lifecycle.phase -isnot [string] -or [string]$Lifecycle.phase -cnotin $legalPhases)
    {
        throw "Snapshot phase '$($Lifecycle.phase)' is illegal."
    }
    if ($Lifecycle.noviceAdded -isnot [bool]) { throw "snapshot.noviceAdded must be boolean." }
    if ($null -ne $Lifecycle.lastError -and $Lifecycle.lastError -isnot [string])
    {
        throw "snapshot.lastError must be null or string."
    }

    $cleanupOrigin = $null
    if ([string]$Lifecycle.phase -cin ($cleanupPhases + $terminalPhases))
    {
        Assert-PropertySet -Value $Lifecycle.cleanup -Expected @("origin", "startedAtUtc", "stage") -Context "snapshot.cleanup"
        Assert-StringValue -Value $Lifecycle.cleanup.origin -Context "snapshot.cleanup.origin"
        if ([string]$Lifecycle.cleanup.origin -cnotin $activePhases)
        {
            throw "snapshot.cleanup.origin '$($Lifecycle.cleanup.origin)' is illegal."
        }
        Assert-UtcTimestamp -Value $Lifecycle.cleanup.startedAtUtc -Context "snapshot.cleanup.startedAtUtc"
        Assert-StringValue -Value $Lifecycle.cleanup.stage -Context "snapshot.cleanup.stage"
        if ([string]$Lifecycle.cleanup.stage -cnotin @("starting", "operationResolved", "recoveredHeld", "surrenderPending", "surrendered", "baselineCleanup", "releasePending"))
        {
            throw "snapshot.cleanup.stage '$($Lifecycle.cleanup.stage)' is illegal."
        }
        $cleanupOrigin = [string]$Lifecycle.cleanup.origin
    }
    elseif ($null -ne $Lifecycle.cleanup)
    {
        throw "Active phase '$($Lifecycle.phase)' cannot carry cleanup metadata."
    }

    Assert-PropertySet -Value $Lifecycle.setup -Expected @(
        "novice", "xp", "funding", "cleanupXp", "cleanupCredits",
        "cleanupNovice", "boundaryMarkers"
    ) -Context "snapshot.setup"
    $setupEnums = @{
        novice = @("pending", "complete", "notNeeded")
        xp = @("notStarted", "pending", "complete")
        funding = @("notStarted", "pending", "complete")
        cleanupXp = @("notStarted", "pending", "complete", "notNeeded")
        cleanupCredits = @("notStarted", "pending", "complete", "notNeeded")
        cleanupNovice = @("notStarted", "pending", "complete", "notNeeded")
        boundaryMarkers = @("notStarted", "pending", "complete", "notNeeded")
    }
    foreach ($name in $setupEnums.Keys)
    {
        Assert-StringValue -Value $Lifecycle.setup.$name -Context "snapshot.setup.$name"
        if ([string]$Lifecycle.setup.$name -cnotin $setupEnums[$name])
        {
            throw "snapshot.setup.$name has illegal state '$($Lifecycle.setup.$name)'."
        }
    }

    Assert-StateShape -State $Lifecycle.baseline -Context "snapshot.baseline"
    Assert-NoOperationInstrumentation -State $Lifecycle.baseline -Context "Snapshot baseline"
    if ([string]$Lifecycle.baseline.LifecycleMarkerState -cne "none" -or
        [string]$Lifecycle.baseline.LifecycleAttemptId -cne "none" -or
        [string]$Lifecycle.baseline.LifecycleId -cne "none" -or
        $Lifecycle.baseline.LifecycleBaselineComplete -or
        $Lifecycle.baseline.RelogNoncePresent -or $Lifecycle.baseline.RestartNoncePresent)
    {
        throw "Snapshot baseline contains lifecycle instrumentation."
    }
    if ($null -ne $Lifecycle.prepared)
    {
        Assert-StateShape -State $Lifecycle.prepared -Context "snapshot.prepared"
        Assert-PreparedRelation -Lifecycle $Lifecycle
    }
    Assert-PurchaseEvidenceShape -Lifecycle $Lifecycle
    if ($null -ne $Lifecycle.held)
    {
        Assert-StateShape -State $Lifecycle.held -Context "snapshot.held"
        Assert-HeldRelation -Lifecycle $Lifecycle -Held $Lifecycle.held
    }
    if (($null -eq $Lifecycle.held) -ne ($null -eq $Lifecycle.purchaseEvidence))
    {
        throw "Snapshot held state and immutable purchase evidence must appear together."
    }
    if ($null -ne $Lifecycle.surrendered)
    {
        Assert-StateShape -State $Lifecycle.surrendered -Context "snapshot.surrendered"
        if ($null -eq $Lifecycle.held -or $null -eq $Lifecycle.prepared)
        {
            throw "Surrendered evidence requires prepared and held evidence."
        }
        Assert-SurrenderRelation -Lifecycle $Lifecycle -Surrendered $Lifecycle.surrendered
    }
    if ($null -ne $Lifecycle.final) { Assert-StateShape -State $Lifecycle.final -Context "snapshot.final" }

    Assert-PropertySet -Value $Lifecycle.boundaries -Expected @("relog", "restart") -Context "snapshot.boundaries"
    if ($null -ne $Lifecycle.boundaries.relog)
    {
        Assert-BoundaryShape -Boundary $Lifecycle.boundaries.relog -Context "snapshot.boundaries.relog"
    }
    if ($null -ne $Lifecycle.boundaries.restart)
    {
        Assert-BoundaryShape -Boundary $Lifecycle.boundaries.restart -Context "snapshot.boundaries.restart"
    }

    if ($null -ne $Lifecycle.conversation)
    {
        Assert-PropertySet -Value $Lifecycle.conversation -Expected @("trainerOid", "status", "queuedAtUtc") -Context "snapshot.conversation"
        Assert-StringValue -Value $Lifecycle.conversation.trainerOid -Context "snapshot.conversation.trainerOid"
        Assert-StringValue -Value $Lifecycle.conversation.status -Context "snapshot.conversation.status"
        Assert-UtcTimestamp -Value $Lifecycle.conversation.queuedAtUtc -Context "snapshot.conversation.queuedAtUtc" -AllowEmpty
        if ([string]$Lifecycle.conversation.trainerOid -notmatch '^[0-9]+$' -or
            [string]$Lifecycle.conversation.status -cnotin @("pending", "queued") -or
            ([string]$Lifecycle.conversation.status -ceq "pending" -and
                -not [string]::IsNullOrEmpty([string]$Lifecycle.conversation.queuedAtUtc)) -or
            ([string]$Lifecycle.conversation.status -ceq "queued" -and
                [string]::IsNullOrEmpty([string]$Lifecycle.conversation.queuedAtUtc)))
        {
            throw "Snapshot conversation identity/status/timestamp is invalid."
        }
    }

    $nonterminalOperationStates = @(
        "checkpointed", "reserving", "reserved", "enqueueing", "queued",
        "paymentDispatching", "paymentSucceededCallback", "paymentFailedCallback",
        "purchaseApplying", "refundInitialClaiming", "refundInitialDispatching",
        "refundInitialPending", "refundRecoveryClaiming", "refundRecoveryDispatching",
        "refundRecoveryPending", "accountingRequested", "accountingDispatching",
        "accountingPending", "accountingSucceededCallback"
    )
    $purchaseRecoveryTargets = @(
        "resumePurchaseAccounting", "requeuePurchaseCallback",
        "reconcileRefundOutcome", "retryPurchaseRefund"
    )
    if ($null -ne $Lifecycle.operation)
    {
        Assert-PropertySet -Value $Lifecycle.operation -Expected @(
            "id", "kind", "state", "serverProcessToken", "lifecycleId", "trainerOid",
            "skillName", "cost", "protocolVersion", "refundGeneration",
            "refundAttemptKey", "refundRetryConsumed", "accountingAttemptKey",
            "accountingAccount", "accountingOutcome", "reconcileTarget", "recovery",
            "checkpointedAtUtc", "terminalAtUtc", "before"
        ) -Context "snapshot.operation"
        foreach ($name in @("id", "kind", "state", "serverProcessToken", "lifecycleId", "trainerOid", "skillName", "refundAttemptKey", "accountingAttemptKey", "accountingAccount", "accountingOutcome", "reconcileTarget"))
        {
            Assert-StringValue -Value $Lifecycle.operation.$name -Context "snapshot.operation.$name" -AllowEmpty:($name -ceq "reconcileTarget")
        }
        Assert-UtcTimestamp -Value $Lifecycle.operation.checkpointedAtUtc -Context "snapshot.operation.checkpointedAtUtc"
        Assert-UtcTimestamp -Value $Lifecycle.operation.terminalAtUtc -Context "snapshot.operation.terminalAtUtc" -AllowEmpty
        Assert-StateShape -State $Lifecycle.operation.before -Context "snapshot.operation.before"
        Assert-NoOperationInstrumentation -State $Lifecycle.operation.before -Context "snapshot.operation.before"
        if ([string]$Lifecycle.operation.before.ServerProcessToken -cne [string]$Lifecycle.operation.serverProcessToken -or
            [string]$Lifecycle.operation.before.LifecycleAttemptId -cne [string]$Lifecycle.lifecycleId -or
            [string]$Lifecycle.operation.before.LifecycleId -cne [string]$Lifecycle.lifecycleId -or
            [string]$Lifecycle.operation.before.LifecycleMarkerState -cne "complete" -or
            -not $Lifecycle.operation.before.LifecycleBaselineComplete -or
            $Lifecycle.operation.before.RelogNoncePresent -or $Lifecycle.operation.before.RestartNoncePresent)
        {
            throw "Snapshot operation.before is not a clean lifecycle-owned checkpoint."
        }
        Assert-IntegerValue -Value $Lifecycle.operation.cost -Context "snapshot.operation.cost"
        Assert-IntegerValue -Value $Lifecycle.operation.protocolVersion -Context "snapshot.operation.protocolVersion"
        Assert-IntegerValue -Value $Lifecycle.operation.refundGeneration -Context "snapshot.operation.refundGeneration"
        if ($Lifecycle.operation.refundRetryConsumed -isnot [bool])
        {
            throw "snapshot.operation.refundRetryConsumed must be boolean."
        }
        if ([int]$Lifecycle.operation.cost -ne $trainerCost -or
            [int]$Lifecycle.operation.protocolVersion -ne 64 -or
            [string]$Lifecycle.operation.id -notmatch '^[a-f0-9]{32}$' -or
            [string]$Lifecycle.operation.kind -cnotin @("fund", "drain", "purchase") -or
            [string]$Lifecycle.operation.lifecycleId -cne [string]$Lifecycle.lifecycleId -or
            [string]$Lifecycle.operation.serverProcessToken -notmatch '^[a-f0-9-]{36}\|[0-9]+\|[0-9]+$' -or
            [string]$Lifecycle.operation.state -cnotin ($nonterminalOperationStates + $settledOperationStates) -or
            [string]$Lifecycle.operation.reconcileTarget -cnotin (@("", "clearReserved") + $settledOperationStates + $purchaseRecoveryTargets))
        {
            throw "Snapshot operation identity/state is invalid."
        }
        $statesByKind = @{
            fund = @("checkpointed", "reserving", "reserved", "enqueueing", "queued", "fundSucceeded", "fundFailed", "fundQueueFailed")
            drain = @("checkpointed", "reserving", "reserved", "enqueueing", "queued", "drainSucceeded", "drainFailed", "drainQueueFailed")
            purchase = @(
                "checkpointed", "reserving", "reserved", "enqueueing", "queued",
                "paymentDispatching", "paymentSucceededCallback", "paymentFailedCallback",
                "purchaseApplying", "refundInitialClaiming", "refundInitialDispatching",
                "refundInitialPending", "refundInitialFailed", "refundRecoveryClaiming",
                "refundRecoveryDispatching", "refundRecoveryPending", "refundRecoveryFailed",
                "accountingRequested", "accountingRequestQueueFailed", "accountingDispatching",
                "accountingPending", "accountingQueueFailed", "accountingFailed",
                "accountingSucceededCallback",
                "purchaseSucceeded", "paymentFailed", "paymentQueueFailed",
                "purchaseRefunded", "purchaseRejected"
            )
        }
        if ([string]$Lifecycle.operation.state -cnotin $statesByKind[[string]$Lifecycle.operation.kind])
        {
            throw "Snapshot operation state '$($Lifecycle.operation.state)' is illegal for '$($Lifecycle.operation.kind)'."
        }
        $snapshotOperationState = [string]$Lifecycle.operation.state
        $initialRefundStates = @("refundInitialClaiming", "refundInitialDispatching", "refundInitialPending", "refundInitialFailed")
        $recoveryRefundStates = @("refundRecoveryClaiming", "refundRecoveryDispatching", "refundRecoveryPending", "refundRecoveryFailed")
        $accountingOutcomesByState = @{
            accountingRequested = @("none", "REQUEST_QUEUE_FAILED")
            accountingDispatching = @("none", "QUEUE_FAILED", "FAILED", "SUCCESS")
            accountingPending = @("none", "FAILED", "SUCCESS")
            accountingRequestQueueFailed = @("REQUEST_QUEUE_FAILED")
            accountingQueueFailed = @("QUEUE_FAILED")
            accountingFailed = @("FAILED")
            accountingSucceededCallback = @("SUCCESS")
            purchaseSucceeded = @("SUCCESS")
        }
        if ($snapshotOperationState -cin ($initialRefundStates + $recoveryRefundStates + @("purchaseRefunded")))
        {
            $expectedGeneration = if ($snapshotOperationState -cin $initialRefundStates) { 1 } elseif ($snapshotOperationState -cin $recoveryRefundStates) { 2 } else { [int]$Lifecycle.operation.refundGeneration }
            if ($expectedGeneration -notin @(1, 2) -or
                [int]$Lifecycle.operation.refundGeneration -ne $expectedGeneration -or
                [string]$Lifecycle.operation.refundAttemptKey -cne "$($Lifecycle.operation.id).refund.$expectedGeneration" -or
                [bool]$Lifecycle.operation.refundRetryConsumed -ne ($expectedGeneration -eq 2) -or
                [string]$Lifecycle.operation.accountingAttemptKey -cne "none" -or
                [string]$Lifecycle.operation.accountingAccount -cne "none" -or
                [string]$Lifecycle.operation.accountingOutcome -cne "none")
            {
                throw "Snapshot operation refund provenance is not exact for '$snapshotOperationState'."
            }
        }
        elseif ($snapshotOperationState -cin @($accountingOutcomesByState.Keys))
        {
            $allowedAccountingOutcomes = @($accountingOutcomesByState[$snapshotOperationState])
            if ([string]$Lifecycle.operation.accountingAttemptKey -cne "$($Lifecycle.operation.id).accounting.1" -or
                [string]$Lifecycle.operation.accountingAccount -cne "skillTrainingSystem" -or
                [string]$Lifecycle.operation.accountingOutcome -cnotin $allowedAccountingOutcomes -or
                [int]$Lifecycle.operation.refundGeneration -ne 0 -or
                [string]$Lifecycle.operation.refundAttemptKey -cne "none" -or
                [bool]$Lifecycle.operation.refundRetryConsumed)
            {
                throw "Snapshot operation accounting provenance is not exact for '$snapshotOperationState'."
            }
        }
        elseif ([int]$Lifecycle.operation.refundGeneration -ne 0 -or
            [string]$Lifecycle.operation.refundAttemptKey -cne "none" -or
            [bool]$Lifecycle.operation.refundRetryConsumed -or
            [string]$Lifecycle.operation.accountingAttemptKey -cne "none" -or
            [string]$Lifecycle.operation.accountingAccount -cne "none" -or
            [string]$Lifecycle.operation.accountingOutcome -cne "none")
        {
            throw "Snapshot operation state '$snapshotOperationState' carries impossible attempt provenance."
        }
        if ([string]$Lifecycle.operation.reconcileTarget -cnotin (@("", "clearReserved") + $purchaseRecoveryTargets) -and
            [string]$Lifecycle.operation.reconcileTarget -cnotin $statesByKind[[string]$Lifecycle.operation.kind])
        {
            throw "Snapshot reconciliation target '$($Lifecycle.operation.reconcileTarget)' is illegal for '$($Lifecycle.operation.kind)'."
        }
        $reconcilePairValid =
            [string]$Lifecycle.operation.reconcileTarget -ceq "" -or
            ([string]$Lifecycle.operation.reconcileTarget -ceq "clearReserved" -and
                [string]$Lifecycle.operation.state -cin @("checkpointed", "reserving", "reserved")) -or
            ([string]$Lifecycle.operation.reconcileTarget -ceq "resumePurchaseAccounting" -and
                [string]$Lifecycle.operation.state -cin @("purchaseApplying", "accountingRequested", "accountingDispatching", "accountingPending", "accountingSucceededCallback")) -or
            ([string]$Lifecycle.operation.reconcileTarget -ceq "requeuePurchaseCallback" -and
                [string]$Lifecycle.operation.state -cin @("paymentDispatching", "paymentSucceededCallback", "purchaseApplying")) -or
            ([string]$Lifecycle.operation.reconcileTarget -ceq "reconcileRefundOutcome" -and
                [string]$Lifecycle.operation.state -cin @("refundInitialClaiming", "refundInitialDispatching", "refundInitialPending", "refundInitialFailed", "refundRecoveryClaiming", "refundRecoveryDispatching", "refundRecoveryPending", "refundRecoveryFailed")) -or
            ([string]$Lifecycle.operation.reconcileTarget -ceq "retryPurchaseRefund" -and
                [string]$Lifecycle.operation.state -cin @("refundInitialClaiming", "refundInitialFailed", "refundRecoveryClaiming"))
        if (-not $reconcilePairValid)
        {
            throw "Snapshot reconciliation state/target transition is not conservative."
        }
        if ([string]$Lifecycle.operation.kind -ceq "purchase")
        {
            if ([string]$Lifecycle.operation.trainerOid -notmatch '^[0-9]+$' -or
                [string]$Lifecycle.operation.skillName -cne $engineeringSkill)
            {
                throw "Snapshot purchase operation lacks exact trainer/skill correlation."
            }
        }
        elseif ([string]$Lifecycle.operation.trainerOid -cne "none" -or
            [string]$Lifecycle.operation.skillName -cne "none")
        {
            throw "Non-purchase operation carries purchase-only correlation."
        }
        if ($null -ne $Lifecycle.operation.recovery)
        {
            Assert-PropertySet -Value $Lifecycle.operation.recovery -Expected @("source", "serverProcessToken", "recoveredAtUtc") -Context "snapshot.operation.recovery"
            $recoverySource = [string]$Lifecycle.operation.recovery.source
            Assert-StringValue -Value $Lifecycle.operation.recovery.serverProcessToken -Context "snapshot.operation.recovery.serverProcessToken"
            $accountingRecoveryStates = @(
                "purchaseApplying", "accountingRequested", "accountingRequestQueueFailed",
                "accountingDispatching", "accountingPending", "accountingQueueFailed",
                "accountingFailed", "accountingSucceededCallback", "purchaseSucceeded"
            )
            $callbackReplayStates = @(
                "paymentDispatching", "paymentSucceededCallback", "purchaseApplying",
                "accountingRequested", "accountingRequestQueueFailed", "accountingDispatching",
                "accountingPending", "accountingQueueFailed", "accountingFailed",
                "accountingSucceededCallback", "purchaseSucceeded",
                "refundInitialClaiming", "refundInitialDispatching", "refundInitialPending",
                "refundInitialFailed", "purchaseRefunded"
            )
            $refundRetryStates = @(
                "refundInitialClaiming", "refundInitialDispatching", "refundInitialPending",
                "refundInitialFailed", "refundRecoveryClaiming", "refundRecoveryDispatching",
                "refundRecoveryPending", "refundRecoveryFailed", "purchaseRefunded"
            )
            $recoveryPairValid =
                ($recoverySource -ceq "restartAccountingResume" -and
                    (([string]$Lifecycle.operation.reconcileTarget -ceq "resumePurchaseAccounting" -and
                        [string]$Lifecycle.operation.state -cin @("purchaseApplying", "accountingRequested", "accountingDispatching", "accountingPending", "accountingSucceededCallback")) -or
                     ([string]$Lifecycle.operation.reconcileTarget -ceq "" -and
                        [string]$Lifecycle.operation.state -cin $accountingRecoveryStates))) -or
                ($recoverySource -ceq "restartCallbackReplay" -and
                    (([string]$Lifecycle.operation.reconcileTarget -ceq "requeuePurchaseCallback" -and
                        [string]$Lifecycle.operation.state -cin @("paymentDispatching", "paymentSucceededCallback", "purchaseApplying")) -or
                     ([string]$Lifecycle.operation.reconcileTarget -ceq "" -and
                        [string]$Lifecycle.operation.state -cin $callbackReplayStates))) -or
                ($recoverySource -ceq "restartRefundOutcome" -and
                    (([string]$Lifecycle.operation.reconcileTarget -ceq "reconcileRefundOutcome" -and
                        [string]$Lifecycle.operation.state -cin @("refundInitialClaiming", "refundInitialDispatching", "refundInitialPending", "refundInitialFailed", "refundRecoveryClaiming", "refundRecoveryDispatching", "refundRecoveryPending", "refundRecoveryFailed")) -or
                     ([string]$Lifecycle.operation.reconcileTarget -ceq "" -and
                        [string]$Lifecycle.operation.state -ceq "purchaseRefunded"))) -or
                ($recoverySource -ceq "restartRefundRetry" -and
                    (([string]$Lifecycle.operation.reconcileTarget -ceq "retryPurchaseRefund" -and
                        [string]$Lifecycle.operation.state -cin @("refundInitialClaiming", "refundInitialFailed", "refundRecoveryClaiming")) -or
                     ([string]$Lifecycle.operation.reconcileTarget -ceq "" -and
                        [string]$Lifecycle.operation.state -cin $refundRetryStates)))
            if ([string]$Lifecycle.operation.kind -cne "purchase" -or
                -not $recoveryPairValid -or
                [string]$Lifecycle.operation.recovery.serverProcessToken -notmatch '^[a-f0-9-]{36}\|[0-9]+\|[0-9]+$' -or
                [string]$Lifecycle.operation.recovery.serverProcessToken -ceq [string]$Lifecycle.operation.serverProcessToken)
            {
                throw "Snapshot operation recovery is not an exact changed-process purchase action."
            }
            Assert-UtcTimestamp -Value $Lifecycle.operation.recovery.recoveredAtUtc -Context "snapshot.operation.recovery.recoveredAtUtc"
        }
        $operationIsSettled = [string]$Lifecycle.operation.state -cin $settledOperationStates
        if ($operationIsSettled -eq [string]::IsNullOrEmpty([string]$Lifecycle.operation.terminalAtUtc))
        {
            throw "Snapshot operation terminal state/timestamp relation is invalid."
        }
    }

    $effectivePhase = if ([string]$Lifecycle.phase -cin ($cleanupPhases + $terminalPhases)) { $cleanupOrigin } else { [string]$Lifecycle.phase }
    $preparedOrigins = @("prepared", "conversationPending", "conversationQueued", "purchasePending", "held", "restartBoundaryArming", "relogVerified", "restartVerified")
    $conversationOrigins = @("conversationPending", "conversationQueued", "purchasePending", "held", "restartBoundaryArming", "relogVerified", "restartVerified")
    $queuedConversationOrigins = @("conversationQueued", "purchasePending", "held", "restartBoundaryArming", "relogVerified", "restartVerified")
    $heldOrigins = @("held", "restartBoundaryArming", "relogVerified", "restartVerified")
    if ($effectivePhase -cin $preparedOrigins -and $null -eq $Lifecycle.prepared) { throw "Origin '$effectivePhase' requires prepared evidence." }
    if ($effectivePhase -cnotin $preparedOrigins -and $null -ne $Lifecycle.prepared) { throw "Origin '$effectivePhase' cannot carry prepared evidence." }
    if ($effectivePhase -cin $conversationOrigins -and $null -eq $Lifecycle.conversation) { throw "Origin '$effectivePhase' requires conversation evidence." }
    if ($effectivePhase -cnotin $conversationOrigins -and $null -ne $Lifecycle.conversation) { throw "Origin '$effectivePhase' cannot carry conversation evidence." }
    $requiresHeld = $effectivePhase -cin $heldOrigins
    $allowsRecoveredHeld = [string]$Lifecycle.phase -cin ($cleanupPhases + $terminalPhases) -and $cleanupOrigin -ceq "purchasePending"
    if ($requiresHeld -and $null -eq $Lifecycle.held) { throw "Origin '$effectivePhase' requires held evidence." }
    if (-not $requiresHeld -and -not $allowsRecoveredHeld -and $null -ne $Lifecycle.held) { throw "Origin '$effectivePhase' cannot carry held evidence." }
    if ($effectivePhase -cin $queuedConversationOrigins -and [string]$Lifecycle.conversation.status -cne "queued")
    {
        throw "Origin '$effectivePhase' requires a queued same-trainer conversation."
    }
    if ($effectivePhase -ceq "conversationPending" -and [string]$Lifecycle.conversation.status -cne "pending")
    {
        throw "conversationPending requires pending conversation evidence."
    }
    if ($effectivePhase -cin @("relogVerified", "restartVerified") -and $null -eq $Lifecycle.boundaries.relog)
    {
        throw "Origin '$effectivePhase' requires relog evidence."
    }
    if ($effectivePhase -ceq "restartVerified" -and $null -eq $Lifecycle.boundaries.restart)
    {
        throw "restartVerified requires restart evidence."
    }

    if ($null -ne $Lifecycle.boundaries.relog)
    {
        if ($null -eq $Lifecycle.held -or [string]$Lifecycle.boundaries.relog.Kind -cne "Relog" -or
            [string]$Lifecycle.boundaries.relog.OperationId -cne [string]$Lifecycle.held.OperationId -or
            [string]$Lifecycle.boundaries.relog.ServerProcessToken -cne [string]$Lifecycle.held.ServerProcessToken)
        {
            throw "Relog boundary is not exactly correlated with held purchase/process evidence."
        }
    }
    if ($null -ne $Lifecycle.boundaries.restart)
    {
        if ($null -eq $Lifecycle.held -or [string]$Lifecycle.boundaries.restart.Kind -cne "Restart" -or
            [string]$Lifecycle.boundaries.restart.OperationId -cne [string]$Lifecycle.held.OperationId -or
            [string]$Lifecycle.boundaries.restart.ServerProcessToken -ceq [string]$Lifecycle.held.ServerProcessToken)
        {
            throw "Restart boundary is not exactly correlated with changed-process held evidence."
        }
    }

    if ([string]$Lifecycle.phase -cin $activePhases)
    {
        if ($null -ne $Lifecycle.final) { throw "Active phase cannot carry final evidence." }
        if ([string]$Lifecycle.phase -ceq "lifecyclePending" -and
            ($null -ne $Lifecycle.operation -or $null -ne $Lifecycle.prepared -or $null -ne $Lifecycle.conversation -or $null -ne $Lifecycle.held))
        {
            throw "lifecyclePending contains impossible later state."
        }
        if ([string]$Lifecycle.phase -ceq "fundingPending" -and
            ($null -eq $Lifecycle.operation -or [string]$Lifecycle.operation.kind -cne "fund"))
        {
            throw "fundingPending requires its correlated fund operation."
        }
        if ([string]$Lifecycle.phase -ceq "prepared" -and $null -ne $Lifecycle.operation)
        {
            throw "prepared cannot retain an operation."
        }
        if ([string]$Lifecycle.phase -cin @("conversationPending", "conversationQueued") -and $null -ne $Lifecycle.operation)
        {
            throw "Conversation phases cannot retain an operation."
        }
        if ([string]$Lifecycle.phase -ceq "purchasePending" -and
            ($null -eq $Lifecycle.operation -or [string]$Lifecycle.operation.kind -cne "purchase" -or $null -ne $Lifecycle.held))
        {
            throw "purchasePending requires its correlated purchase operation and no held state."
        }
        if ([string]$Lifecycle.phase -cin $heldOrigins -and
            ($null -eq $Lifecycle.operation -or [string]$Lifecycle.operation.kind -cne "purchase" -or
             [string]$Lifecycle.operation.state -cne "purchaseSucceeded" -or
             [string]$Lifecycle.held.OperationId -cne [string]$Lifecycle.operation.id))
        {
            throw "Held/boundary phase requires the exact terminal purchase operation."
        }
    }
    elseif ([string]$Lifecycle.phase -cin $cleanupPhases)
    {
        if ($null -ne $Lifecycle.final) { throw "Cleanup/release phase cannot carry final evidence." }
        if ([string]$Lifecycle.phase -ceq "releasePending" -and $null -ne $Lifecycle.operation)
        {
            throw "releasePending cannot retain an operation."
        }
        if ([string]$Lifecycle.phase -ceq "releasePending" -and
            [string]$Lifecycle.cleanup.stage -cne "releasePending")
        {
            throw "releasePending requires cleanup.stage=releasePending."
        }
        if ([string]$Lifecycle.phase -ceq "releasePending")
        {
            foreach ($name in @("cleanupXp", "cleanupCredits", "cleanupNovice", "boundaryMarkers"))
            {
                if ([string]$Lifecycle.setup.$name -cnotin @("complete", "notNeeded"))
                {
                    throw "releasePending requires terminal setup.$name."
                }
            }
        }
        if ($null -ne $Lifecycle.operation)
        {
            if ([string]$Lifecycle.operation.kind -ceq "fund" -and $cleanupOrigin -cnotin @("preparing", "fundingPending"))
            {
                throw "Cleanup fund operation is impossible for origin '$cleanupOrigin'."
            }
            if ([string]$Lifecycle.operation.kind -ceq "purchase" -and $cleanupOrigin -cnotin @("purchasePending", "held", "restartBoundaryArming", "relogVerified", "restartVerified"))
            {
                throw "Cleanup purchase operation is impossible for origin '$cleanupOrigin'."
            }
            if ([string]$Lifecycle.operation.kind -ceq "drain" -and $cleanupOrigin -ceq "lifecyclePending")
            {
                throw "Cleanup drain operation is impossible before lifecycle establishment."
            }
        }
    }
    else
    {
        if ($null -eq $Lifecycle.final -or $null -ne $Lifecycle.operation)
        {
            throw "Terminal phase requires final evidence and no operation."
        }
        if ([string]$Lifecycle.cleanup.stage -cne "releasePending")
        {
            throw "Terminal snapshot requires a completed release stage."
        }
        Assert-StatePersistentEquals -Actual $Lifecycle.final -Expected $Lifecycle.baseline -Context "Terminal final/baseline"
        Assert-NoOperationInstrumentation -State $Lifecycle.final -Context "Terminal final evidence"
        if ([string]$Lifecycle.final.LifecycleMarkerState -cne "none" -or
            [string]$Lifecycle.final.LifecycleAttemptId -cne "none" -or
            [string]$Lifecycle.final.LifecycleId -cne "none" -or
            $Lifecycle.final.LifecycleBaselineComplete -or
            $Lifecycle.final.RelogNoncePresent -or $Lifecycle.final.RestartNoncePresent)
        {
            throw "Terminal final evidence retains lifecycle instrumentation."
        }
        foreach ($name in @("cleanupXp", "cleanupCredits", "cleanupNovice", "boundaryMarkers"))
        {
            if ([string]$Lifecycle.setup.$name -cnotin @("complete", "notNeeded"))
            {
                throw "Terminal snapshot has incomplete setup.$name."
            }
        }
        if ([string]$Lifecycle.phase -ceq "complete" -and
            ($cleanupOrigin -cne "restartVerified" -or $null -eq $Lifecycle.surrendered -or
             $null -eq $Lifecycle.purchaseEvidence -or $null -eq $Lifecycle.held -or
             $null -eq $Lifecycle.boundaries.relog -or $null -eq $Lifecycle.boundaries.restart))
        {
            throw "complete requires the full purchase/boundary/surrender lifecycle."
        }
        if ([string]$Lifecycle.phase -ceq "cleaned" -and $cleanupOrigin -ceq "purchasePending" -and
            ($null -eq $Lifecycle.purchaseEvidence -or $null -eq $Lifecycle.held -or
             $null -eq $Lifecycle.surrendered -or
             [string]$Lifecycle.purchaseEvidence.outcomeSource -cnotin @("restartAccountingResume", "restartCallbackReplay") -or
             [string]$Lifecycle.held.OperationId -cne [string]$Lifecycle.purchaseEvidence.operationId))
        {
            throw "Recovered purchase cleanup requires durable held/surrendered lineage through terminal cleaned."
        }
    }

    $createdTime = Convert-UtcTimestamp -Value ([string]$Lifecycle.createdAtUtc) -Context "snapshot.createdAtUtc"
    if ($null -ne $Lifecycle.cleanup -and
        (Convert-UtcTimestamp -Value ([string]$Lifecycle.cleanup.startedAtUtc) -Context "snapshot.cleanup.startedAtUtc") -lt $createdTime)
    {
        throw "Cleanup timestamp precedes lifecycle creation."
    }
    if ($null -ne $Lifecycle.conversation -and -not [string]::IsNullOrEmpty([string]$Lifecycle.conversation.queuedAtUtc) -and
        (Convert-UtcTimestamp -Value ([string]$Lifecycle.conversation.queuedAtUtc) -Context "snapshot.conversation.queuedAtUtc") -lt $createdTime)
    {
        throw "Conversation timestamp precedes lifecycle creation."
    }
    if ($null -ne $Lifecycle.operation)
    {
        $checkpointTime = Convert-UtcTimestamp -Value ([string]$Lifecycle.operation.checkpointedAtUtc) -Context "snapshot.operation.checkpointedAtUtc"
        if ($checkpointTime -lt $createdTime) { throw "Operation checkpoint precedes lifecycle creation." }
        if (-not [string]::IsNullOrEmpty([string]$Lifecycle.operation.terminalAtUtc) -and
            (Convert-UtcTimestamp -Value ([string]$Lifecycle.operation.terminalAtUtc) -Context "snapshot.operation.terminalAtUtc") -lt $checkpointTime)
        {
            throw "Operation terminal timestamp precedes its checkpoint."
        }
    }
    if ($null -ne $Lifecycle.boundaries.relog -and $null -ne $Lifecycle.boundaries.restart -and
        (Convert-UtcTimestamp -Value ([string]$Lifecycle.boundaries.restart.VerifiedAtUtc) -Context "snapshot.boundaries.restart.VerifiedAtUtc") -lt
        (Convert-UtcTimestamp -Value ([string]$Lifecycle.boundaries.relog.VerifiedAtUtc) -Context "snapshot.boundaries.relog.VerifiedAtUtc"))
    {
        throw "Restart boundary timestamp precedes relog verification."
    }
    foreach ($boundaryName in @("relog", "restart"))
    {
        $boundary = $Lifecycle.boundaries.$boundaryName
        if ($null -ne $boundary -and
            (Convert-UtcTimestamp -Value ([string]$boundary.VerifiedAtUtc) -Context "snapshot.boundaries.$boundaryName.VerifiedAtUtc") -lt $createdTime)
        {
            throw "$boundaryName boundary timestamp precedes lifecycle creation."
        }
    }
}

function Get-Snapshot
{
    param([Parameter(Mandatory = $true)] [object]$CurrentIdentity)
    $resolvedPath = Resolve-ExternalSnapshotPath
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf))
    {
        throw "Snapshot does not exist: $resolvedPath"
    }
    $lifecycle = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json
    Assert-LifecycleSnapshot -Lifecycle $lifecycle -CurrentIdentity $CurrentIdentity
    return $lifecycle
}

function Assert-CurrentLifecycleMarker
{
    param([object]$Lifecycle, [object]$State)
    $attempt = [string]$State.LifecycleAttemptId
    $actual = [string]$State.LifecycleId
    $markerState = [string]$State.LifecycleMarkerState
    $expected = [string]$Lifecycle.lifecycleId
    if ([string]$Lifecycle.phase -cin @("complete", "cleaned"))
    {
        if ($markerState -cne "none" -or $attempt -cne "none" -or $actual -cne "none")
        {
            throw "Terminal lifecycle retained active marker state '$markerState/$attempt/$actual'."
        }
        return
    }
    if ([string]$Lifecycle.phase -ceq "lifecyclePending")
    {
        $ownedPartial = $markerState -ceq "partial" -and $attempt -ceq $expected -and $actual -ceq "none"
        $ownedComplete = $markerState -ceq "complete" -and $attempt -ceq $expected -and
            $actual -ceq $expected -and $State.LifecycleBaselineComplete
        if ($markerState -cne "none" -and -not $ownedPartial -and -not $ownedComplete)
        {
            throw "Lifecycle establishment is not the snapshot's exact partial/complete marker: '$markerState/$attempt/$actual'."
        }
        return
    }
    if ([string]$Lifecycle.phase -cin @("cleanupPending", "releasePending") -and
        [string]$Lifecycle.cleanup.origin -ceq "lifecyclePending")
    {
        $ownedPartial = $markerState -ceq "partial" -and $attempt -ceq $expected -and $actual -ceq "none"
        $ownedComplete = $markerState -ceq "complete" -and $attempt -ceq $expected -and
            $actual -ceq $expected -and $State.LifecycleBaselineComplete
        if ($markerState -cne "none" -and -not $ownedPartial -and -not $ownedComplete)
        {
            throw "lifecyclePending cleanup refuses foreign/corrupt marker '$markerState/$attempt/$actual'."
        }
        return
    }
    if ([string]$Lifecycle.phase -cin @("cleanupPending", "releasePending") -and $markerState -ceq "none")
    {
        Assert-StatePersistentEquals -Actual $State -Expected $Lifecycle.baseline -Context "Released cleanup baseline"
        Assert-NoOperationInstrumentation -State $State -Context "Released cleanup state"
        if ($State.RelogNoncePresent -or $State.RestartNoncePresent)
        {
            throw "Released cleanup state retains lifecycle instrumentation."
        }
        return
    }
    if ($markerState -cne "complete" -or $attempt -cne $expected -or
        $actual -cne $expected -or -not $State.LifecycleBaselineComplete)
    {
        throw "Authoritative lifecycle marker mismatch: current='$markerState/$attempt/$actual' snapshot='$expected'."
    }
}

function Assert-TerminalCleanupNoOp
{
    param([object]$Lifecycle, [object]$State)
    if ([string]$Lifecycle.phase -cnotin @("complete", "cleaned"))
    {
        throw "Terminal no-op assertion received nonterminal phase '$($Lifecycle.phase)'."
    }
    Assert-StatePersistentEquals -Actual $State -Expected $Lifecycle.final -Context "Terminal current/final"
    Assert-StatePersistentEquals -Actual $State -Expected $Lifecycle.baseline -Context "Terminal current/baseline"
    Assert-NoOperationInstrumentation -State $State -Context "Terminal cleanup no-op"
    if ([string]$State.LifecycleMarkerState -cne "none" -or
        [string]$State.LifecycleAttemptId -cne "none" -or
        [string]$State.LifecycleId -cne "none" -or
        $State.LifecycleBaselineComplete -or
        $State.RelogNoncePresent -or $State.RestartNoncePresent)
    {
        throw "Terminal cleanup no-op found active lifecycle instrumentation."
    }
}

function Get-StateFingerprint
{
    param([object]$State)
    return ($State | Select-Object -Property $snapshotStateFields | ConvertTo-Json -Compress -Depth 4)
}

function Wait-ForState
{
    param([scriptblock]$Predicate, [string]$Context)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do
    {
        $state = Get-State
        if (& $Predicate $state) { return $state }
        Start-Sleep -Milliseconds 250
    }
    while ([DateTime]::UtcNow -lt $deadline)
    throw "$Context timed out. Last state: $($state.ProbeText)"
}

function Wait-ForQuietState
{
    param([object]$InitialState, [scriptblock]$Predicate, [string]$Context)
    if (-not (& $Predicate $InitialState))
    {
        throw "$Context did not enter its required state: $($InitialState.ProbeText)"
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $stableSince = [DateTime]::UtcNow
    $fingerprint = Get-StateFingerprint -State $InitialState
    $state = $InitialState
    do
    {
        Start-Sleep -Milliseconds 250
        $current = Get-State
        if (-not (& $Predicate $current))
        {
            throw "$Context left its required state during settlement: $($current.ProbeText)"
        }
        $currentFingerprint = Get-StateFingerprint -State $current
        if ($currentFingerprint -cne $fingerprint)
        {
            $fingerprint = $currentFingerprint
            $stableSince = [DateTime]::UtcNow
        }
        $state = $current
        if (([DateTime]::UtcNow - $stableSince).TotalSeconds -ge $quietSeconds)
        {
            return $state
        }
    }
    while ([DateTime]::UtcNow -lt $deadline)
    throw "$Context did not remain quiet for $quietSeconds seconds. Last state: $($state.ProbeText)"
}

function Wait-ForTerminalOperation
{
    param([string]$OperationId, [string]$OperationKind, [string]$Context)
    $terminal = Wait-ForState -Context $Context -Predicate {
        param($state)
        if ($state.OperationAttemptId -cne $OperationId -or
            $state.OperationId -cne $OperationId -or
            $state.OperationKind -cne $OperationKind -or
            -not $state.OperationMarkerComplete)
        {
            throw "$Context operation marker mismatch: $($state.ProbeText)"
        }
        return $state.OperationState -cin $settledOperationStates
    }
    $terminalState = [string]$terminal.OperationState
    return Wait-ForQuietState -InitialState $terminal -Context "$Context terminal settlement" -Predicate {
        param($state)
        $state.OperationAttemptId -ceq $OperationId -and
            $state.OperationId -ceq $OperationId -and
            $state.OperationKind -ceq $OperationKind -and
            $state.OperationState -ceq $terminalState
    }
}

function New-TrackedOperation
{
    param(
        [ValidateSet("fund", "drain", "purchase")] [string]$Kind,
        [Parameter(Mandatory = $true)] [string]$ServerProcessToken,
        [Parameter(Mandatory = $true)] [object]$Before,
        [Parameter(Mandatory = $true)] [string]$LifecycleId,
        [string]$TrainerOid = "none",
        [string]$SkillName = "none"
    )
    [pscustomobject]@{
        id = [guid]::NewGuid().ToString("N")
        kind = $Kind
        state = "checkpointed"
        serverProcessToken = $ServerProcessToken
        lifecycleId = $LifecycleId
        trainerOid = $TrainerOid
        skillName = $SkillName
        cost = $trainerCost
        protocolVersion = 64
        refundGeneration = 0
        refundAttemptKey = "none"
        refundRetryConsumed = $false
        accountingAttemptKey = "none"
        accountingAccount = "none"
        accountingOutcome = "none"
        reconcileTarget = ""
        recovery = $null
        checkpointedAtUtc = [DateTime]::UtcNow.ToString("o")
        terminalAtUtc = ""
        before = New-StateSnapshot -State $Before
    }
}

function Assert-ExactTrackedOperationMarker
{
    param([object]$Lifecycle, [object]$State, [string]$Context)
    $operation = $Lifecycle.operation
    if ($null -eq $operation -or
        [string]$State.OperationAttemptId -cne [string]$operation.id -or
        [string]$State.OperationId -cne [string]$operation.id -or
        [string]$State.OperationKind -cne [string]$operation.kind -or
        [string]$State.OperationLifecycleId -cne [string]$operation.lifecycleId -or
        [string]$State.OperationTrainerOid -cne [string]$operation.trainerOid -or
        [string]$State.OperationSkillName -cne [string]$operation.skillName -or
        [int]$State.OperationUpdated -le 0 -or
        [int]$State.OperationCost -ne [int]$operation.cost -or
        [int]$State.OperationProtocolVersion -ne [int]$operation.protocolVersion -or
        -not [bool]$State.OperationMarkerComplete)
    {
        throw "$Context lacks exact immutable operation identity/provenance."
    }
}

function Get-NormalizedTrackedOperationReconcileTarget
{
    param([object]$Lifecycle, [object]$State)
    if ($null -eq $Lifecycle.operation -or $null -eq $Lifecycle.operation.recovery)
    {
        return ""
    }
    # Refund-outcome reconciliation is synchronous and remains an outstanding
    # intent until the authoritative marker proves purchaseRefunded.  Every
    # other recovery RPC may advance through multiple durable states; its
    # historical recovery source is retained while the action target is cleared.
    if ([string]$Lifecycle.operation.recovery.source -ceq "restartRefundOutcome" -and
        [string]$State.OperationState -cin @(
            "refundInitialClaiming", "refundInitialDispatching", "refundInitialPending",
            "refundInitialFailed", "refundRecoveryClaiming", "refundRecoveryDispatching",
            "refundRecoveryPending", "refundRecoveryFailed"))
    {
        return "reconcileRefundOutcome"
    }
    return ""
}

function New-ValidatedTrackedOperationStateCandidate
{
    param(
        [Parameter(Mandatory = $true)] [object]$Lifecycle,
        [Parameter(Mandatory = $true)] [object]$State,
        [ValidateSet("", "clearReserved", "resumePurchaseAccounting", "requeuePurchaseCallback", "reconcileRefundOutcome", "retryPurchaseRefund")]
        [string]$ReconcileTarget = "",
        [ValidateSet("", "restartAccountingResume", "restartCallbackReplay", "restartRefundOutcome", "restartRefundRetry")]
        [string]$RecoverySource = "",
        [string]$RecoveryProcessToken = ""
    )
    if ($null -eq $Lifecycle.operation)
    {
        throw "Cannot synchronize a missing tracked operation."
    }
    # Get-State carries ProbeText for diagnostics.  Durable state has an exact
    # schema, so detach/canonicalize at this boundary and never persist the
    # diagnostic field.
    $State = New-StateSnapshot -State $State
    Assert-StateShape -State $State -Context "authoritative tracked operation"
    Assert-ExactTrackedOperationMarker -Lifecycle $Lifecycle -State $State -Context "Authoritative operation synchronization"
    $candidate = Copy-OfflineObject -Value $Lifecycle
    $operation = $candidate.operation
    $operation.state = [string]$State.OperationState
    $operation.protocolVersion = [int]$State.OperationProtocolVersion
    $operation.refundGeneration = [int]$State.OperationRefundGeneration
    $operation.refundAttemptKey = [string]$State.OperationRefundAttemptKey
    $operation.refundRetryConsumed = [bool]$State.OperationRefundRetryConsumed
    $operation.accountingAttemptKey = [string]$State.OperationAccountingAttemptKey
    $operation.accountingAccount = [string]$State.OperationAccountingAccount
    $operation.accountingOutcome = [string]$State.OperationAccountingOutcome
    $operation.reconcileTarget = $ReconcileTarget
    if ([string]$State.OperationState -cin $settledOperationStates)
    {
        if ([string]::IsNullOrEmpty([string]$operation.terminalAtUtc))
        {
            $operation.terminalAtUtc = [DateTime]::UtcNow.ToString("o")
        }
    }
    else
    {
        $operation.terminalAtUtc = ""
    }

    if (-not [string]::IsNullOrEmpty($RecoverySource))
    {
        $targetBySource = @{
            restartAccountingResume = "resumePurchaseAccounting"
            restartCallbackReplay = "requeuePurchaseCallback"
            restartRefundOutcome = "reconcileRefundOutcome"
            restartRefundRetry = "retryPurchaseRefund"
        }
        if ([string]$targetBySource[$RecoverySource] -cne $ReconcileTarget -or
            $RecoveryProcessToken -notmatch '^[a-f0-9-]{36}\|[0-9]+\|[0-9]+$' -or
            $RecoveryProcessToken -ceq [string]$operation.serverProcessToken -or
            ($null -ne $Lifecycle.operation.recovery -and
                $RecoveryProcessToken -ceq [string]$Lifecycle.operation.recovery.serverProcessToken))
        {
            throw "Recovery intent is not an exact new changed-process action."
        }
        if ($RecoverySource -ceq "restartRefundRetry" -and
            $null -ne $Lifecycle.operation.recovery -and
            [string]$Lifecycle.operation.recovery.source -ceq "restartRefundRetry" -and
            [int]$State.OperationRefundGeneration -eq 1)
        {
            throw "Generation-one refund retry intent has already been consumed."
        }
        $operation.recovery = [pscustomobject]@{
            source = $RecoverySource
            serverProcessToken = $RecoveryProcessToken
            recoveredAtUtc = [DateTime]::UtcNow.ToString("o")
        }
    }
    elseif ($ReconcileTarget -cin @(
            "resumePurchaseAccounting", "requeuePurchaseCallback",
            "reconcileRefundOutcome", "retryPurchaseRefund") -and
        $null -eq $operation.recovery)
    {
        throw "A recovery target cannot be checkpointed without exact recovery provenance."
    }

    Assert-LifecycleSnapshot -Lifecycle $candidate -CurrentIdentity $candidate.identity
    $roundTrip = Copy-OfflineObject -Value $candidate
    Assert-LifecycleSnapshot -Lifecycle $roundTrip -CurrentIdentity $roundTrip.identity
    return $roundTrip
}

function Set-TrackedOperationFromState
{
    param(
        [object]$Lifecycle,
        [object]$State,
        [ValidateSet("", "clearReserved", "resumePurchaseAccounting", "requeuePurchaseCallback", "reconcileRefundOutcome", "retryPurchaseRefund")]
        [string]$ReconcileTarget = ""
    )
    $candidate = New-ValidatedTrackedOperationStateCandidate `
        -Lifecycle $Lifecycle `
        -State $State `
        -ReconcileTarget $ReconcileTarget
    # Replace the operation atomically only after the cloned candidate and its
    # serialized form have both passed the complete snapshot validator.
    $Lifecycle.operation = $candidate.operation
}

function Clear-TerminalOperation
{
    param([object]$Lifecycle, [object]$State)
    if ($null -eq $Lifecycle.operation) { return $State }
    $operationId = [string]$Lifecycle.operation.id
    if ($State.OperationAttemptId -ceq "none")
    {
        Assert-NoOperationInstrumentation -State $State -Context "Marker-cleared terminal operation"
        if ([string]$Lifecycle.operation.state -cnotin $clearableOperationStates)
        {
            throw "Refusing to forget non-clearable operation '$($Lifecycle.operation.state)' after its marker disappeared."
        }
        Confirm-TerminalOperationEffect -Lifecycle $Lifecycle -State $State -MarkerAlreadyCleared
        $Lifecycle.operation = $null
        Save-SnapshotAtomic -Snapshot $Lifecycle
        return $State
    }
    Assert-ExactTrackedOperationMarker -Lifecycle $Lifecycle -State $State -Context "Terminal operation clear"
    if ($State.OperationState -cnotin $settledOperationStates)
    {
        $State = Wait-ForTerminalOperation -OperationId $operationId -OperationKind ([string]$Lifecycle.operation.kind) -Context "Tracked operation recovery"
    }
    $normalizedTarget = Get-NormalizedTrackedOperationReconcileTarget -Lifecycle $Lifecycle -State $State
    Set-TrackedOperationFromState -Lifecycle $Lifecycle -State $State -ReconcileTarget $normalizedTarget
    Save-SnapshotAtomic -Snapshot $Lifecycle
    if ([string]$State.OperationState -cnotin $clearableOperationStates)
    {
        throw "Operation '$operationId' reached non-clearable terminal state '$($State.OperationState)'; durable recovery evidence is retained."
    }
    Confirm-TerminalOperationEffect -Lifecycle $Lifecycle -State $State
    # Confirm may synthesize recovered purchase evidence/held state.  Persist
    # that full validated lineage before destructively removing the server
    # marker so response loss remains marker-cleared replayable.
    Save-SnapshotAtomic -Snapshot $Lifecycle
    $cleared = Invoke-Probe -Arguments "clearOperation $PlayerOid $operationId $($Lifecycle.lifecycleId)"
    Assert-Field -Result $cleared -Name "cleared" -Expected "true"
    $State = Wait-ForState -Context "operation-marker cleanup" -Predicate {
        param($current)
        $current.OperationAttemptId -ceq "none" -and
            $current.OperationId -ceq "none" -and $current.OperationState -ceq "none"
    }
    Confirm-TerminalOperationEffect -Lifecycle $Lifecycle -State $State -MarkerAlreadyCleared
    $Lifecycle.operation = $null
    Save-SnapshotAtomic -Snapshot $Lifecycle
    return $State
}

function Invoke-Surrender
{
    param([object]$Lifecycle)
    $queued = Invoke-Probe -Arguments "queueSurrender $PlayerOid $engineeringSkill $($Lifecycle.lifecycleId)"
    Assert-Field -Result $queued -Name "queued" -Expected "true"
    Assert-Field -Result $queued -Name "verification" -Expected "pending"
    $removed = Wait-ForState -Context "Engineering surrender" -Predicate { param($state) -not $state.HasSkill }
    return Wait-ForQuietState -InitialState $removed -Context "Engineering surrender settlement" -Predicate { param($state) -not $state.HasSkill }
}

function Assert-SurrenderRelation
{
    param([object]$Lifecycle, [object]$Surrendered)
    if ($null -eq $Lifecycle.purchaseEvidence -or $null -eq $Lifecycle.held -or
        [string]$Lifecycle.held.OperationId -cne [string]$Lifecycle.purchaseEvidence.operationId)
    {
        throw "Surrender lacks immutable purchase/lifecycle/trainer lineage."
    }
    if ($Surrendered.HasSkill -or $Surrendered.HasCommand -or $Surrendered.HasSchematic)
    {
        throw "Surrender retained Engineering I state: $($Surrendered.ProbeText)"
    }
    if ([int]$Surrendered.Cash -ne [int]$Lifecycle.held.Cash -or
        [int]$Surrendered.Bank -ne [int]$Lifecycle.held.Bank -or
        [int]$Surrendered.Credits -ne [int]$Lifecycle.held.Credits -or
        [int]$Surrendered.Xp -ne [int]$Lifecycle.held.Xp)
    {
        throw "Surrender changed cash/bank/credits or refunded XP: $($Surrendered.ProbeText)"
    }
    if ([int]$Surrendered.Points -ne ([int]$Lifecycle.held.Points + $engineeringPointCost))
    {
        throw "Surrender did not return exactly $engineeringPointCost skill points."
    }
    foreach ($name in @("VectorCommands", "VectorMods", "VectorSchematics"))
    {
        if ([string]$Surrendered.$name -cne [string]$Lifecycle.prepared.$name)
        {
            throw "Surrender did not restore exact prepared identity vector '$name'."
        }
    }
    Assert-NoOperationInstrumentation -State $Surrendered -Context "Correlated surrendered state"
    if ([string]$Surrendered.LifecycleAttemptId -cne [string]$Lifecycle.purchaseEvidence.lifecycleId -or
        [string]$Surrendered.LifecycleId -cne [string]$Lifecycle.purchaseEvidence.lifecycleId -or
        [string]$Surrendered.LifecycleMarkerState -cne "complete" -or
        -not $Surrendered.LifecycleBaselineComplete)
    {
        throw "Surrendered state is not owned by the exact purchase lifecycle."
    }
}

function Assert-ReservedOperationClearable
{
    param([object]$Lifecycle, [object]$State)
    # The external checkpoint is deliberately written before dispatch. If the
    # server persists its reserved marker and then dies before the runner can
    # refresh its snapshot, the only safe skew is checkpointed -> reserved.
    # Both forms still require the exact operation identity and unchanged
    # pre-dispatch gameplay state before the reserved marker may be cleared.
    if ($null -eq $Lifecycle.operation -or
        [string]$Lifecycle.operation.state -cnotin @("checkpointed", "reserving", "reserved") -or
        [string]$State.OperationAttemptId -cne [string]$Lifecycle.operation.id -or
        [string]$State.OperationState -cnotin @("missing", "reserving", "reserved") -or
        -not $State.OperationPreimageMatches -or
        $State.RelogNoncePresent -or $State.RestartNoncePresent)
    {
        throw "Pre-dispatch operation recovery identity/state is not exact."
    }
    foreach ($relation in @(
        @("OperationId", "none", [string]$Lifecycle.operation.id),
        @("OperationKind", "missing", [string]$Lifecycle.operation.kind),
        @("OperationLifecycleId", "missing", [string]$Lifecycle.operation.lifecycleId),
        @("OperationTrainerOid", "missing", [string]$Lifecycle.operation.trainerOid),
        @("OperationSkillName", "missing", [string]$Lifecycle.operation.skillName)))
    {
        $actual = [string]$State.($relation[0])
        if ($actual -cne [string]$relation[1] -and $actual -cne [string]$relation[2])
        {
            throw "Partial pre-dispatch marker field '$($relation[0])' is not correlated."
        }
    }
    if ([int]$State.OperationCost -notin @(0, [int]$Lifecycle.operation.cost))
    {
        throw "Partial pre-dispatch marker cost is not correlated."
    }
    $operationState = [string]$State.OperationState
    $partialStringLeaves = @(
        [string]$State.OperationRefundAttemptKey,
        [string]$State.OperationAccountingAttemptKey,
        [string]$State.OperationAccountingAccount,
        [string]$State.OperationAccountingOutcome
    )
    if ([int]$State.OperationRefundGeneration -ne 0 -or
        [bool]$State.OperationRefundRetryConsumed -or
        @($partialStringLeaves | Where-Object { $_ -cnotin @("missing", "none") }).Count -ne 0)
    {
        throw "Pre-dispatch operation carries non-neutral refund/accounting provenance."
    }
    if ([int]$State.OperationProtocolVersion -notin @(0, [int]$Lifecycle.operation.protocolVersion) -or
        [int]$State.OperationUpdated -lt 0)
    {
        throw "Pre-dispatch operation carries an invalid protocol or update value."
    }

    $visibleReservationPrefix = @(
        [pscustomobject]@{ Name = "kind"; Present = ([string]$State.OperationKind -cne "missing") },
        [pscustomobject]@{ Name = "updated"; Present = ([int]$State.OperationUpdated -gt 0) },
        [pscustomobject]@{ Name = "lifecycleId"; Present = ([string]$State.OperationLifecycleId -cne "missing") },
        [pscustomobject]@{ Name = "trainerOid"; Present = ([string]$State.OperationTrainerOid -cne "missing") },
        [pscustomobject]@{ Name = "skillName"; Present = ([string]$State.OperationSkillName -cne "missing") },
        [pscustomobject]@{ Name = "cost"; Present = ([int]$State.OperationCost -ne 0) },
        [pscustomobject]@{ Name = "protocolVersion"; Present = ([int]$State.OperationProtocolVersion -ne 0) },
        [pscustomobject]@{ Name = "refundAttemptKey"; Present = ([string]$State.OperationRefundAttemptKey -cne "missing") },
        [pscustomobject]@{ Name = "accountingAttemptKey"; Present = ([string]$State.OperationAccountingAttemptKey -cne "missing") },
        [pscustomobject]@{ Name = "accountingAccount"; Present = ([string]$State.OperationAccountingAccount -cne "missing") },
        [pscustomobject]@{ Name = "accountingOutcome"; Present = ([string]$State.OperationAccountingOutcome -cne "missing") },
        [pscustomobject]@{ Name = "id"; Present = ([string]$State.OperationId -cne "none") }
    )
    $prefixGap = $false
    foreach ($leaf in $visibleReservationPrefix)
    {
        if (-not $leaf.Present)
        {
            $prefixGap = $true
        }
        elseif ($prefixGap)
        {
            throw "Pre-dispatch operation contains a visible write-order gap before '$($leaf.Name)'."
        }
    }

    if ($operationState -ceq "missing" -and
        ($State.OperationMarkerComplete -or
         @($visibleReservationPrefix | Where-Object { $_.Present }).Count -ne 0))
    {
        throw "Attempt-only operation contains leaves beyond its ID-first write."
    }
    if ($operationState -ceq "reserving" -and $State.OperationMarkerComplete)
    {
        throw "Reserving operation was incorrectly reported as complete."
    }
    if ($operationState -ceq "reserved" -and
        (-not $State.OperationMarkerComplete -or
         @($visibleReservationPrefix | Where-Object { -not $_.Present }).Count -ne 0))
    {
        throw "Reserved marker was published without its complete record."
    }
    Assert-StateGameplayEquals -Actual $State -Expected $Lifecycle.operation.before -Context "Reserved operation checkpoint"
    return "clearReserved"
}

function Assert-UnqueuedOperationDiscardable
{
    param([object]$Lifecycle, [object]$State)
    if ($null -eq $Lifecycle.operation -or [string]$Lifecycle.operation.state -cne "checkpointed" -or
        [string]$State.OperationAttemptId -cne "none")
    {
        throw "Unqueued recovery identity/state is not exact."
    }
    Assert-NoOperationInstrumentation -State $State -Context "Unqueued operation discard"
    Assert-StateGameplayEquals -Actual $State -Expected $Lifecycle.operation.before -Context "Unqueued operation checkpoint"
    return "discardCheckpoint"
}

function Resolve-TrackedOperationForCleanup
{
    param(
        [object]$Lifecycle,
        [object]$State,
        [scriptblock]$ReservedProbeInvoker,
        [scriptblock]$ReservedStateReader,
        [scriptblock]$ReservedSnapshotWriter
    )
    if ($null -eq $ReservedProbeInvoker)
    {
        $ReservedProbeInvoker = { param($Command) Invoke-Probe -Arguments $Command }
    }
    if ($null -eq $ReservedStateReader)
    {
        $ReservedStateReader = { Get-State }
    }
    if ($null -eq $ReservedSnapshotWriter)
    {
        $ReservedSnapshotWriter = { param($Snapshot) Save-SnapshotAtomic -Snapshot $Snapshot }
    }
    if ($null -eq $Lifecycle.operation)
    {
        if ($State.OperationAttemptId -cne "none")
        {
            throw "Snapshot has no operation but the fixture has an unexpected marker: $($State.ProbeText)"
        }
        return $State
    }

    $operation = $Lifecycle.operation
    $operationId = [string]$operation.id
    $operationKind = [string]$operation.kind
    if ($State.OperationAttemptId -ceq "none")
    {
        Assert-NoOperationInstrumentation -State $State -Context "Tracked operation marker absence"
        if ([string]$operation.state -cin @("checkpointed", "reserving", "reserved") -or [string]$operation.reconcileTarget -ceq "clearReserved")
        {
            if ([string]$operation.state -ceq "checkpointed")
            {
                $null = Assert-UnqueuedOperationDiscardable -Lifecycle $Lifecycle -State $State
            }
            else
            {
                Assert-StateGameplayEquals -Actual $State -Expected $operation.before -Context "Cleared reserved operation checkpoint"
            }
            $Lifecycle.operation = $null
            Save-SnapshotAtomic -Snapshot $Lifecycle
            return $State
        }
        if ([string]$operation.state -cin $settledOperationStates)
        {
            Confirm-TerminalOperationEffect -Lifecycle $Lifecycle -State $State -MarkerAlreadyCleared
            $Lifecycle.operation = $null
            Save-SnapshotAtomic -Snapshot $Lifecycle
            return $State
        }
        throw "Tracked operation disappeared from unsafe state '$($operation.state)'; recovery remains fail-closed."
    }
    if ([string]$State.OperationState -cin @("missing", "reserving", "reserved"))
    {
        $null = Assert-ReservedOperationClearable -Lifecycle $Lifecycle -State $State
        if ([string]$State.OperationState -cne "reserved")
        {
            $reservedCandidate = Copy-OfflineObject -Value $Lifecycle
            $reservedCandidate.operation.reconcileTarget = "clearReserved"
            Assert-LifecycleSnapshot -Lifecycle $reservedCandidate -CurrentIdentity $reservedCandidate.identity
            $reservedCandidate = Copy-OfflineObject -Value $reservedCandidate
            Assert-LifecycleSnapshot -Lifecycle $reservedCandidate -CurrentIdentity $reservedCandidate.identity
        }
        else
        {
            $reservedCandidate = New-ValidatedTrackedOperationStateCandidate `
                -Lifecycle $Lifecycle `
                -State $State `
                -ReconcileTarget "clearReserved"
        }
        & $ReservedSnapshotWriter $reservedCandidate | Out-Null
        $Lifecycle.operation = $reservedCandidate.operation
        $operation = $Lifecycle.operation
        $cleared = & $ReservedProbeInvoker "clearOperation $PlayerOid $operationId $($Lifecycle.lifecycleId)"
        Assert-Field -Result $cleared -Name "cleared" -Expected "true"
        $State = & $ReservedStateReader
        if ([string]$State.OperationAttemptId -cne "none") { throw "Pre-dispatch operation clear did not settle." }
        Assert-NoOperationInstrumentation -State $State -Context "Cleared pre-dispatch operation"
        Assert-StateGameplayEquals -Actual $State -Expected $operation.before -Context "Cleared reserved operation"
        $Lifecycle.operation = $null
        & $ReservedSnapshotWriter $Lifecycle | Out-Null
        return $State
    }

    Assert-ExactTrackedOperationMarker -Lifecycle $Lifecycle -State $State -Context "Tracked cleanup resolution"

    # Persist the complete live marker before choosing a settlement path.  This
    # normalization clears recovery actions that have already advanced while
    # preserving the one synchronous refund-reconciliation intent.
    $normalizedTarget = Get-NormalizedTrackedOperationReconcileTarget -Lifecycle $Lifecycle -State $State
    $liveCandidate = New-ValidatedTrackedOperationStateCandidate `
        -Lifecycle $Lifecycle `
        -State $State `
        -ReconcileTarget $normalizedTarget
    Save-SnapshotAtomic -Snapshot $liveCandidate
    $Lifecycle.operation = $liveCandidate.operation
    $operation = $Lifecycle.operation

    $plan = Get-TrackedOperationSettlementPlan -Lifecycle $Lifecycle -State $State
    if ([string]$plan.action -ceq "wait")
    {
        $State = Wait-ForTerminalOperation -OperationId $operationId -OperationKind $operationKind -Context "Tracked same-process operation settlement"
    }
    elseif ([string]$plan.action -ceq "recover")
    {
        $recoveryResult = Invoke-TrackedPurchaseRecovery `
            -Lifecycle $Lifecycle `
            -State $State `
            -Decision ([string]$plan.recoveryDecision)
        $State = $recoveryResult.state
        $Lifecycle.operation = $recoveryResult.lifecycle.operation
        $operation = $Lifecycle.operation
    }
    elseif ([string]$plan.action -ceq "failClosed")
    {
        throw "Operation '$operationId' is '$($State.OperationState)' after a server restart, but it matches none of the exact DEBIT/HELD/REFUND/accounting recovery proofs. It remains fail-closed."
    }
    elseif ([string]$plan.action -cne "terminal")
    {
        throw "Unknown tracked-operation settlement plan '$($plan.action)'."
    }

    if ([string]$State.OperationState -cnotin $settledOperationStates)
    {
        throw "Tracked operation is in unsupported nonterminal state '$($State.OperationState)'."
    }
    $normalizedTarget = Get-NormalizedTrackedOperationReconcileTarget -Lifecycle $Lifecycle -State $State
    $terminalCandidate = New-ValidatedTrackedOperationStateCandidate `
        -Lifecycle $Lifecycle `
        -State $State `
        -ReconcileTarget $normalizedTarget
    Save-SnapshotAtomic -Snapshot $terminalCandidate
    $Lifecycle.operation = $terminalCandidate.operation
    return Clear-TerminalOperation -Lifecycle $Lifecycle -State $State
}

function Assert-GameplayExceptBalances
{
    param([object]$Actual, [object]$Expected, [string]$Context)
    foreach ($name in $gameplayStateFields)
    {
        if ($name -cin @("Cash", "Bank", "Credits")) { continue }
        if ($Actual.$name -ne $Expected.$name)
        {
            throw "$Context mismatch '$name': actual=$($Actual.$name) expected=$($Expected.$name)"
        }
    }
}

function Assert-ExactPurchaseOperationLineage
{
    param([object]$Lifecycle, [object]$State)
    $operation = $Lifecycle.operation
    if ($null -eq $operation -or [string]$operation.kind -cne "purchase" -or
        $null -eq $Lifecycle.prepared -or
        [string]$operation.id -notmatch '^[a-f0-9]{32}$' -or
        [string]$operation.lifecycleId -cne [string]$Lifecycle.lifecycleId -or
        [string]$operation.trainerOid -notmatch '^[0-9]+$' -or
        [string]$operation.skillName -cne $engineeringSkill -or
        [int]$operation.cost -ne $trainerCost -or
        [string]$State.OperationAttemptId -cne [string]$operation.id -or
        [string]$State.OperationId -cne [string]$operation.id -or
        [string]$State.OperationKind -cne "purchase" -or
        [string]$State.OperationLifecycleId -cne [string]$operation.lifecycleId -or
        [string]$State.OperationTrainerOid -cne [string]$operation.trainerOid -or
        [string]$State.OperationSkillName -cne [string]$operation.skillName -or
        [int]$State.OperationUpdated -le 0 -or
        [int]$State.OperationCost -ne [int]$operation.cost -or
        -not $State.OperationMarkerComplete)
    {
        throw "Purchase recovery lacks exact operation/player/trainer/skill/cost/lifecycle correlation."
    }
    Assert-PreparedRelation -Lifecycle $Lifecycle
    Assert-StateGameplayEquals -Actual $operation.before -Expected $Lifecycle.prepared -Context "Purchase operation durable preimage"
}

function Assert-ExactPurchaseDebitVector
{
    param([object]$Lifecycle, [object]$State)
    Assert-ExactPurchaseOperationLineage -Lifecycle $Lifecycle -State $State
    $before = $Lifecycle.operation.before
    $bankDebit = [Math]::Min([int]$before.Bank, $trainerCost)
    $cashDebit = $trainerCost - $bankDebit
    Assert-GameplayExceptBalances -Actual $State -Expected $before -Context "Purchase DEBIT vector"
    if ([int]$State.Cash -ne ([int]$before.Cash - $cashDebit) -or
        [int]$State.Bank -ne ([int]$before.Bank - $bankDebit) -or
        [int]$State.Credits -ne ([int]$before.Credits - $trainerCost) -or
        $State.RelogNoncePresent -or $State.RestartNoncePresent)
    {
        throw "Purchase DEBIT vector is not the exact bank-first post-debit/no-grant state."
    }
}

function Assert-ExactPurchaseRefundVector
{
    param([object]$Lifecycle, [object]$State)
    Assert-ExactPurchaseOperationLineage -Lifecycle $Lifecycle -State $State
    Assert-StateGameplayEquals -Actual $State -Expected $Lifecycle.operation.before -Context "Purchase REFUND vector"
    if ($State.RelogNoncePresent -or $State.RestartNoncePresent)
    {
        throw "Purchase REFUND vector retained volatile purchase witnesses."
    }
}

function New-PurchaseSuccessCandidate
{
    param([object]$Lifecycle, [object]$State)
    $candidate = New-StateSnapshot -State $State
    $candidate.OperationId = [string]$Lifecycle.operation.id
    $candidate.OperationKind = "purchase"
    $candidate.OperationState = "purchaseSucceeded"
    $candidate.OperationProtocolVersion = 64
    $candidate.OperationRefundGeneration = 0
    $candidate.OperationRefundAttemptKey = "none"
    $candidate.OperationRefundRetryConsumed = $false
    $candidate.OperationAccountingAttemptKey = "$($Lifecycle.operation.id).accounting.1"
    $candidate.OperationAccountingAccount = "skillTrainingSystem"
    $candidate.OperationAccountingOutcome = "SUCCESS"
    return $candidate
}

function New-PurchaseEvidence
{
    param(
        [object]$Lifecycle,
        [object]$State,
        [ValidateSet("callback", "restartAccountingResume", "restartCallbackReplay")] [string]$OutcomeSource
    )
    $operation = $Lifecycle.operation
    if ($null -eq $operation -or [string]$operation.kind -cne "purchase")
    {
        throw "Purchase evidence requires the tracked purchase operation."
    }
    [pscustomobject]@{
        operationId = [string]$operation.id
        lifecycleId = [string]$operation.lifecycleId
        trainerOid = [string]$operation.trainerOid
        skillName = [string]$operation.skillName
        cost = [int]$operation.cost
        accountingAttemptKey = [string]$State.OperationAccountingAttemptKey
        originProcessToken = [string]$operation.serverProcessToken
        outcomeProcessToken = [string]$State.ServerProcessToken
        outcomeSource = $OutcomeSource
        terminalAtUtc = [DateTime]::UtcNow.ToString("o")
    }
}

function Assert-PersistentAccountingResumeEffect
{
    param([object]$Lifecycle, [object]$State)
    $operation = $Lifecycle.operation
    Assert-ExactPurchaseOperationLineage -Lifecycle $Lifecycle -State $State
    if ($null -eq $operation -or [string]$operation.kind -cne "purchase" -or
        [string]$State.ServerProcessToken -ceq [string]$operation.serverProcessToken -or
        [string]$State.OperationAttemptId -cne [string]$operation.id -or
        [string]$State.OperationId -cne [string]$operation.id -or
        [string]$State.OperationKind -cne "purchase" -or
        [string]$State.OperationState -cnotin @("purchaseApplying", "accountingRequested", "accountingDispatching", "accountingPending", "accountingSucceededCallback") -or
        [string]$State.OperationLifecycleId -cne [string]$operation.lifecycleId -or
        [string]$State.OperationTrainerOid -cne [string]$operation.trainerOid -or
        [string]$State.OperationSkillName -cne [string]$operation.skillName -or
        [int]$State.OperationCost -ne [int]$operation.cost -or
        -not $State.OperationMarkerComplete -or
        $State.RelogNoncePresent -or $State.RestartNoncePresent)
    {
        throw "Restart recovery lacks changed-process, vanished-volatile, durable purchase correlation."
    }
    $candidateLifecycle = Copy-OfflineObject -Value $Lifecycle
    $candidateLifecycle.operation.recovery = [pscustomobject]@{
        source = "restartAccountingResume"
        serverProcessToken = [string]$State.ServerProcessToken
        recoveredAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    $candidate = New-PurchaseSuccessCandidate -Lifecycle $candidateLifecycle -State $State
    $candidateLifecycle.operation.state = "purchaseSucceeded"
    $candidateLifecycle.operation.accountingAttemptKey = [string]$candidate.OperationAccountingAttemptKey
    $candidateLifecycle.operation.accountingAccount = "skillTrainingSystem"
    $candidateLifecycle.operation.accountingOutcome = "SUCCESS"
    $candidateLifecycle.purchaseEvidence = New-PurchaseEvidence -Lifecycle $candidateLifecycle -State $candidate -OutcomeSource "restartAccountingResume"
    Assert-HeldRelation -Lifecycle $candidateLifecycle -Held $candidate
}

function Get-PurchaseRecoveryDecision
{
    param([object]$Lifecycle, [object]$State)
    $operation = $Lifecycle.operation
    if ($null -eq $operation -or [string]$operation.kind -cne "purchase" -or
        [string]$State.ServerProcessToken -ceq [string]$operation.serverProcessToken)
    {
        return ""
    }
    if ($null -ne $operation.recovery -and
        [string]$State.ServerProcessToken -ceq [string]$operation.recovery.serverProcessToken)
    {
        return ""
    }

    # HELD takes precedence over DEBIT.  It proves the gameplay grant only;
    # named-account settlement still requires the durable accounting protocol.
    if ([string]$State.OperationState -cin @(
            "purchaseApplying", "accountingRequested", "accountingDispatching",
            "accountingPending", "accountingSucceededCallback"))
    {
        try
        {
            Assert-PersistentAccountingResumeEffect -Lifecycle $Lifecycle -State $State
            $accountingResumeSafe =
                ([string]$State.OperationState -ceq "purchaseApplying" -and
                    [string]$State.OperationAccountingAttemptKey -ceq "none" -and
                    [string]$State.OperationAccountingOutcome -ceq "none") -or
                ([string]$State.OperationState -ceq "accountingRequested" -and
                    [string]$State.OperationAccountingAttemptKey -ceq "$($operation.id).accounting.1" -and
                    [string]$State.OperationAccountingAccount -ceq "skillTrainingSystem" -and
                    [string]$State.OperationAccountingOutcome -ceq "none") -or
                ([string]$State.OperationState -cin @("accountingDispatching", "accountingPending", "accountingSucceededCallback") -and
                    [string]$State.OperationAccountingAttemptKey -ceq "$($operation.id).accounting.1" -and
                    [string]$State.OperationAccountingAccount -ceq "skillTrainingSystem" -and
                    [string]$State.OperationAccountingOutcome -ceq "SUCCESS")
            if ($accountingResumeSafe) { return "resumePurchaseAccounting" }
        }
        catch { }
    }

    if ([string]$State.OperationState -cin @(
            "paymentDispatching", "paymentSucceededCallback", "purchaseApplying"))
    {
        try
        {
            Assert-ExactPurchaseDebitVector -Lifecycle $Lifecycle -State $State
            return "requeuePurchaseCallback"
        }
        catch { return "" }
    }

    $refundStates = @(
        "refundInitialClaiming", "refundInitialDispatching", "refundInitialPending",
        "refundInitialFailed", "refundRecoveryClaiming", "refundRecoveryDispatching",
        "refundRecoveryPending", "refundRecoveryFailed")
    if ([string]$State.OperationState -cin $refundStates)
    {
        try
        {
            Assert-ExactPurchaseRefundVector -Lifecycle $Lifecycle -State $State
            return "reconcileRefundOutcome"
        }
        catch { }
        $retryClaimSafe =
            ([string]$State.OperationState -cin @("refundInitialClaiming", "refundInitialFailed") -and
                [int]$State.OperationRefundGeneration -eq 1 -and
                [string]$State.OperationRefundAttemptKey -ceq "$($operation.id).refund.1" -and
                -not [bool]$State.OperationRefundRetryConsumed) -or
            ([string]$State.OperationState -ceq "refundRecoveryClaiming" -and
                [int]$State.OperationRefundGeneration -eq 2 -and
                [string]$State.OperationRefundAttemptKey -ceq "$($operation.id).refund.2" -and
                [bool]$State.OperationRefundRetryConsumed)
        if ($retryClaimSafe -and
            [int]$State.OperationRefundGeneration -eq 1 -and
            $null -ne $operation.recovery -and
            [string]$operation.recovery.source -ceq "restartRefundRetry")
        {
            return ""
        }
        if ($retryClaimSafe)
        {
            try
            {
                Assert-ExactPurchaseDebitVector -Lifecycle $Lifecycle -State $State
                return "retryPurchaseRefund"
            }
            catch { }
        }
        return ""
    }

    return ""
}

function Get-TrackedOperationSettlementPlan
{
    param([object]$Lifecycle, [object]$State)
    if ($null -eq $Lifecycle.operation)
    {
        throw "Settlement planning requires a tracked operation."
    }
    $operation = $Lifecycle.operation
    $sameProcessBoundary =
        [string]$State.ServerProcessToken -ceq [string]$operation.serverProcessToken -or
        ($null -ne $operation.recovery -and
            [string]$State.ServerProcessToken -ceq [string]$operation.recovery.serverProcessToken)
    if ($sameProcessBoundary)
    {
        $action = if ([string]$State.OperationState -cin $settledOperationStates) { "terminal" } else { "wait" }
        return [pscustomobject]@{ action = $action; recoveryDecision = "" }
    }

    # Recoverable settled failures must be planned before the generic terminal
    # branch.  In particular, generation-one refund failure + exact DEBIT is
    # the durable gateway to its one generation-two compensation attempt.
    if ([string]$State.OperationState -cin $recoverableSettledOperationStates -or
        [string]$State.OperationState -cnotin $settledOperationStates)
    {
        $decision = Get-PurchaseRecoveryDecision -Lifecycle $Lifecycle -State $State
        if (-not [string]::IsNullOrEmpty($decision))
        {
            return [pscustomobject]@{ action = "recover"; recoveryDecision = $decision }
        }
    }
    if ([string]$State.OperationState -cin $settledOperationStates)
    {
        return [pscustomobject]@{ action = "terminal"; recoveryDecision = "" }
    }
    return [pscustomobject]@{ action = "failClosed"; recoveryDecision = "" }
}

function Invoke-TrackedPurchaseRecovery
{
    param(
        [Parameter(Mandatory = $true)] [object]$Lifecycle,
        [Parameter(Mandatory = $true)] [object]$State,
        [ValidateSet("resumePurchaseAccounting", "requeuePurchaseCallback", "reconcileRefundOutcome", "retryPurchaseRefund")]
        [string]$Decision,
        [scriptblock]$ProbeInvoker,
        [scriptblock]$StateReader,
        [scriptblock]$TerminalWaiter,
        [scriptblock]$SnapshotWriter
    )
    if ($null -eq $ProbeInvoker)
    {
        $ProbeInvoker = { param($Command) Invoke-Probe -Arguments $Command }
    }
    if ($null -eq $StateReader)
    {
        $StateReader = { Get-State }
    }
    if ($null -eq $TerminalWaiter)
    {
        $TerminalWaiter = {
            param($OperationId, $OperationKind, $Context)
            Wait-ForTerminalOperation -OperationId $OperationId -OperationKind $OperationKind -Context $Context
        }
    }
    if ($null -eq $SnapshotWriter)
    {
        $SnapshotWriter = { param($Snapshot) Save-SnapshotAtomic -Snapshot $Snapshot }
    }

    $operationId = [string]$Lifecycle.operation.id
    $operationKind = [string]$Lifecycle.operation.kind
    $sourceByDecision = @{
        resumePurchaseAccounting = "restartAccountingResume"
        requeuePurchaseCallback = "restartCallbackReplay"
        reconcileRefundOutcome = "restartRefundOutcome"
        retryPurchaseRefund = "restartRefundRetry"
    }
    $intent = New-ValidatedTrackedOperationStateCandidate `
        -Lifecycle $Lifecycle `
        -State $State `
        -ReconcileTarget $Decision `
        -RecoverySource ([string]$sourceByDecision[$Decision]) `
        -RecoveryProcessToken ([string]$State.ServerProcessToken)
    & $SnapshotWriter $intent | Out-Null
    $Lifecycle.operation = $intent.operation

    $actionError = $null
    $actionState = $null
    try
    {
        if ($Decision -ceq "resumePurchaseAccounting")
        {
            $resumed = & $ProbeInvoker "resumePurchaseAccounting $PlayerOid $operationId $($Lifecycle.lifecycleId)"
            Assert-Field -Result $resumed -Name "transferRetried" -Expected "false"
            if ([string]$resumed.Values["reconciled"] -ceq "true")
            {
                $actionState = & $StateReader
            }
            else
            {
                Assert-Field -Result $resumed -Name "requestQueued" -Expected "true"
                $actionState = & $TerminalWaiter $operationId $operationKind "Changed-process accounting resume"
            }
        }
        elseif ($Decision -ceq "requeuePurchaseCallback")
        {
            $requeued = & $ProbeInvoker "requeuePurchaseCallback $PlayerOid $operationId $($Lifecycle.lifecycleId)"
            Assert-Field -Result $requeued -Name "queued" -Expected "true"
            $actionState = & $TerminalWaiter $operationId $operationKind "Changed-process trainer callback replay"
        }
        elseif ($Decision -ceq "reconcileRefundOutcome")
        {
            $reconciled = & $ProbeInvoker "reconcileRefundOutcome $PlayerOid $operationId $($Lifecycle.lifecycleId)"
            Assert-Field -Result $reconciled -Name "reconciled" -Expected "true"
            Assert-Field -Result $reconciled -Name "transferRetried" -Expected "false"
            $actionState = & $StateReader
            if ([string]$actionState.OperationState -cne "purchaseRefunded")
            {
                throw "Refund reconciliation did not persist terminal 'purchaseRefunded'."
            }
        }
        else
        {
            $generation = [int]$State.OperationRefundGeneration
            $attemptKey = [string]$State.OperationRefundAttemptKey
            $retried = & $ProbeInvoker "retryPurchaseRefund $PlayerOid $operationId $($Lifecycle.lifecycleId) $generation $attemptKey"
            Assert-Field -Result $retried -Name "queued" -Expected "true"
            $actionState = & $TerminalWaiter $operationId $operationKind "Changed-process one-shot refund retry"
        }
    }
    catch
    {
        $actionError = $_
    }

    # Always re-read after the RPC path, including assertion failures and wait
    # timeouts.  If the direct read itself fails, an already-returned wait state
    # is still authoritative enough to checkpoint; otherwise retain the intent.
    $refreshError = $null
    $refreshedState = $null
    try
    {
        $refreshedState = & $StateReader
        $normalizedTarget = Get-NormalizedTrackedOperationReconcileTarget -Lifecycle $Lifecycle -State $refreshedState
        $postAction = New-ValidatedTrackedOperationStateCandidate `
            -Lifecycle $Lifecycle `
            -State $refreshedState `
            -ReconcileTarget $normalizedTarget
        & $SnapshotWriter $postAction | Out-Null
        $Lifecycle.operation = $postAction.operation
    }
    catch
    {
        $refreshError = $_
        if ($null -ne $actionState)
        {
            try
            {
                $normalizedTarget = Get-NormalizedTrackedOperationReconcileTarget -Lifecycle $Lifecycle -State $actionState
                $postAction = New-ValidatedTrackedOperationStateCandidate `
                    -Lifecycle $Lifecycle `
                    -State $actionState `
                    -ReconcileTarget $normalizedTarget
                & $SnapshotWriter $postAction | Out-Null
                $Lifecycle.operation = $postAction.operation
                $refreshedState = $actionState
                $refreshError = $null
            }
            catch
            {
                $refreshError = $_
            }
        }
    }
    if ($null -ne $actionError)
    {
        throw $actionError
    }
    if ($null -ne $refreshError)
    {
        throw "Recovery action completed but its authoritative post-action state could not be checkpointed. Cause: $($refreshError.Exception.Message)"
    }
    return [pscustomobject]@{ lifecycle = $Lifecycle; state = $refreshedState; decision = $Decision }
}

function Get-ConservativeReconcileTarget
{
    param([object]$Lifecycle, [object]$State)
    $decision = Get-PurchaseRecoveryDecision -Lifecycle $Lifecycle -State $State
    if ($decision -ceq "resumePurchaseAccounting") { return $decision }
    return ""
}

function Confirm-TerminalOperationEffect
{
    param([object]$Lifecycle, [object]$State, [switch]$MarkerAlreadyCleared)
    $operation = $Lifecycle.operation
    $terminal = [string]$operation.state
    if (-not $MarkerAlreadyCleared) { $terminal = [string]$State.OperationState }
    if ($MarkerAlreadyCleared)
    {
        Assert-NoOperationInstrumentation -State $State -Context "Marker-cleared terminal effect"
        if ([string]$operation.lifecycleId -cne [string]$Lifecycle.lifecycleId -or
            [string]$State.LifecycleAttemptId -cne [string]$Lifecycle.lifecycleId -or
            [string]$State.LifecycleId -cne [string]$Lifecycle.lifecycleId -or
            [string]$State.LifecycleMarkerState -cne "complete" -or
            -not $State.LifecycleBaselineComplete)
        {
            throw "Marker-cleared terminal effect lacks exact active-lifecycle lineage."
        }
    }
    else
    {
        Assert-ExactTrackedOperationMarker -Lifecycle $Lifecycle -State $State -Context "Terminal effect"
        $expectedProvenance = @{
            OperationAttemptId = [string]$operation.id
            OperationId = [string]$operation.id
            OperationKind = [string]$operation.kind
            OperationLifecycleId = [string]$operation.lifecycleId
            OperationTrainerOid = [string]$operation.trainerOid
            OperationSkillName = [string]$operation.skillName
            OperationCost = [int]$operation.cost
            OperationState = [string]$operation.state
            OperationProtocolVersion = [int]$operation.protocolVersion
            OperationRefundGeneration = [int]$operation.refundGeneration
            OperationRefundAttemptKey = [string]$operation.refundAttemptKey
            OperationRefundRetryConsumed = [bool]$operation.refundRetryConsumed
            OperationAccountingAttemptKey = [string]$operation.accountingAttemptKey
            OperationAccountingAccount = [string]$operation.accountingAccount
            OperationAccountingOutcome = [string]$operation.accountingOutcome
        }
        foreach ($name in $expectedProvenance.Keys)
        {
            if ($State.$name -ne $expectedProvenance[$name])
            {
                throw "Terminal effect provenance '$name' differs: authoritative=$($State.$name) snapshot=$($expectedProvenance[$name])."
            }
        }
        if (-not $State.OperationMarkerComplete)
        {
            throw "Terminal effect does not carry a complete authoritative operation marker."
        }
    }
    if ($terminal -cin @("refundInitialFailed", "refundRecoveryFailed"))
    {
        if (-not $MarkerAlreadyCleared) { Assert-ExactPurchaseDebitVector -Lifecycle $Lifecycle -State $State }
        throw "Refund terminal failure retains durable compensation provenance; refusing cleanup."
    }
    if ($terminal -cin @("accountingRequestQueueFailed", "accountingQueueFailed", "accountingFailed"))
    {
        throw "Accounting terminal failure retains an unsettled named-account outcome; refusing cleanup."
    }
    if ($terminal -ceq "fundSucceeded")
    {
        Assert-GameplayExceptBalances -Actual $State -Expected $operation.before -Context "Fund terminal effect"
        if ([int]$State.Cash -ne [int]$operation.before.Cash -or
            [int]$State.Bank -ne ([int]$operation.before.Bank + $trainerCost) -or
            [int]$State.Credits -ne ([int]$operation.before.Credits + $trainerCost))
        {
            throw "Fund terminal bank-only balance effect is not exact."
        }
        return
    }
    if ($terminal -ceq "drainSucceeded")
    {
        Assert-GameplayExceptBalances -Actual $State -Expected $operation.before -Context "Drain terminal effect"
        if ([int]$State.Cash -ne [int]$operation.before.Cash -or
            [int]$State.Bank -ne ([int]$operation.before.Bank - $trainerCost) -or
            [int]$State.Credits -ne ([int]$operation.before.Credits - $trainerCost))
        {
            throw "Drain terminal bank-only balance effect is not exact."
        }
        return
    }
    if ($terminal -ceq "purchaseSucceeded")
    {
        if ([int]$operation.refundGeneration -ne 0 -or
            [string]$operation.refundAttemptKey -cne "none" -or
            [bool]$operation.refundRetryConsumed -or
            [string]$operation.accountingAttemptKey -cne "$($operation.id).accounting.1" -or
            [string]$operation.accountingAccount -cne "skillTrainingSystem" -or
            [string]$operation.accountingOutcome -cne "SUCCESS")
        {
            throw "Purchase success lacks exact named-account SUCCESS provenance."
        }
        if ($null -ne $Lifecycle.held -and $null -ne $Lifecycle.purchaseEvidence)
        {
            if ($MarkerAlreadyCleared)
            {
                Assert-StateGameplayEquals -Actual $State -Expected $Lifecycle.held -Context "Marker-cleared correlated purchase gameplay"
                if ([string]$Lifecycle.purchaseEvidence.operationId -cne [string]$operation.id -or
                    [string]$Lifecycle.purchaseEvidence.lifecycleId -cne [string]$operation.lifecycleId -or
                    [string]$Lifecycle.purchaseEvidence.trainerOid -cne [string]$operation.trainerOid -or
                    [string]$Lifecycle.purchaseEvidence.skillName -cne [string]$operation.skillName -or
                    [int]$Lifecycle.purchaseEvidence.cost -ne [int]$operation.cost -or
                    [string]$Lifecycle.purchaseEvidence.accountingAttemptKey -cne [string]$operation.accountingAttemptKey -or
                    [string]$State.LifecycleAttemptId -cne [string]$Lifecycle.purchaseEvidence.lifecycleId -or
                    [string]$State.LifecycleId -cne [string]$Lifecycle.purchaseEvidence.lifecycleId -or
                    [string]$State.LifecycleMarkerState -cne "complete" -or
                    -not $State.LifecycleBaselineComplete)
                {
                    throw "Marker-cleared purchase lacks exact lifecycle/evidence lineage."
                }
            }
            else
            {
                Assert-StatePersistentEquals -Actual $State -Expected $Lifecycle.held -Context "Persisted correlated purchase effect"
            }
            return
        }
        $source = $(if ($null -ne $operation.recovery -and
                [string]$operation.recovery.source -ceq "restartCallbackReplay")
            { "restartCallbackReplay" }
            elseif ($null -ne $operation.recovery -and
                [string]$operation.recovery.source -ceq "restartAccountingResume")
            { "restartAccountingResume" }
            else { "callback" })
        $validatedLifecycle = Copy-OfflineObject -Value $Lifecycle
        $validatedLifecycle.purchaseEvidence = New-PurchaseEvidence -Lifecycle $validatedLifecycle -State $State -OutcomeSource $source
        $candidate = New-PurchaseSuccessCandidate -Lifecycle $validatedLifecycle -State $State
        $validatedLifecycle.held = New-StateSnapshot -State $candidate
        Assert-HeldRelation -Lifecycle $validatedLifecycle -Held $validatedLifecycle.held
        $Lifecycle.purchaseEvidence = $validatedLifecycle.purchaseEvidence
        $Lifecycle.held = $validatedLifecycle.held
        return
    }
    if ($terminal -ceq "purchaseRefunded")
    {
        if ([int]$operation.refundGeneration -notin @(1, 2) -or
            [string]$operation.refundAttemptKey -cne "$($operation.id).refund.$($operation.refundGeneration)" -or
            [bool]$operation.refundRetryConsumed -ne ([int]$operation.refundGeneration -eq 2) -or
            [string]$operation.accountingAttemptKey -cne "none" -or
            [string]$operation.accountingAccount -cne "none" -or
            [string]$operation.accountingOutcome -cne "none")
        {
            throw "Purchase refund lacks exact generation-scoped provenance."
        }
        if ($MarkerAlreadyCleared)
        {
            Assert-StateGameplayEquals -Actual $State -Expected $operation.before -Context "Marker-cleared REFUND vector"
        }
        else
        {
            Assert-ExactPurchaseRefundVector -Lifecycle $Lifecycle -State $State
        }
        return
    }
    if ($terminal -cin @("fundFailed", "fundQueueFailed", "drainFailed", "drainQueueFailed", "paymentFailed", "paymentQueueFailed", "purchaseRejected"))
    {
        Assert-StateGameplayEquals -Actual $State -Expected $operation.before -Context "Terminal no-effect/refund operation"
        return
    }
    throw "Terminal state '$terminal' has no safe automatic cleanup relation; recovery remains fail-closed."
}

function Invoke-BaselineCleanup
{
    param([object]$Lifecycle, [ValidateSet("complete", "cleaned")] [string]$CompletionPhase)
    if ([string]$Lifecycle.phase -cnotin @("cleanupPending", "releasePending"))
    {
        $origin = [string]$Lifecycle.phase
        $Lifecycle.cleanup = [pscustomobject]@{ origin = $origin; startedAtUtc = [DateTime]::UtcNow.ToString("o"); stage = "starting" }
        $Lifecycle.phase = "cleanupPending"
        Save-SnapshotAtomic -Snapshot $Lifecycle
    }
    $state = Get-State
    Assert-CurrentLifecycleMarker -Lifecycle $Lifecycle -State $state

    if ([string]$Lifecycle.cleanup.origin -ceq "lifecyclePending")
    {
        # Establishment recovery is metadata-only. Prove the complete external
        # baseline and zero operation/nonce residue before any clear request;
        # gameplay drift exits without a gameplay mutation.
        Assert-StateGameplayEquals -Actual $state -Expected $Lifecycle.baseline -Context "lifecyclePending zero-gameplay cleanup"
        Assert-NoOperationInstrumentation -State $state -Context "lifecyclePending zero-gameplay cleanup"
        if ($state.RelogNoncePresent -or $state.RestartNoncePresent)
        {
            throw "lifecyclePending cleanup found impossible volatile instrumentation."
        }
        if ([string]$state.LifecycleMarkerState -cne "none")
        {
            $Lifecycle.cleanup.stage = "releasePending"
            $Lifecycle.phase = "releasePending"
            Save-SnapshotAtomic -Snapshot $Lifecycle
            try
            {
                $released = Invoke-Probe -Arguments "clearLifecycle $PlayerOid $($Lifecycle.lifecycleId)"
                Assert-Field -Result $released -Name "cleared" -Expected "true"
            }
            catch
            {
                $state = Get-State
                if ([string]$state.LifecycleMarkerState -cne "none") { throw }
            }
            $state = Get-State
        }
        Assert-StateGameplayEquals -Actual $state -Expected $Lifecycle.baseline -Context "Released lifecyclePending baseline"
        Assert-NoOperationInstrumentation -State $state -Context "Released lifecyclePending state"
        if ([string]$state.LifecycleMarkerState -cne "none" -or
            [string]$state.LifecycleAttemptId -cne "none" -or
            [string]$state.LifecycleId -cne "none" -or
            $state.RelogNoncePresent -or $state.RestartNoncePresent)
        {
            throw "lifecyclePending metadata release did not prove zero residue."
        }
        foreach ($name in @("cleanupXp", "cleanupCredits", "cleanupNovice", "boundaryMarkers"))
        {
            $Lifecycle.setup.$name = "notNeeded"
        }
        $Lifecycle.operation = $null
        $Lifecycle.cleanup.stage = "releasePending"
        $Lifecycle.final = New-StateSnapshot -State $state
        $Lifecycle.phase = $CompletionPhase
        $Lifecycle.lastError = $null
        Save-SnapshotAtomic -Snapshot $Lifecycle
        return $state
    }

    if ([string]$state.LifecycleMarkerState -ceq "none")
    {
        Assert-StatePersistentEquals -Actual $state -Expected $Lifecycle.baseline -Context "Released cleanup baseline"
        Assert-NoOperationInstrumentation -State $state -Context "Released lifecycle"
        if ($state.RelogNoncePresent -or $state.RestartNoncePresent)
        {
            throw "Released lifecycle still has operation/boundary instrumentation."
        }
        foreach ($name in @("cleanupXp", "cleanupCredits", "cleanupNovice", "boundaryMarkers"))
        {
            if ([string]$Lifecycle.setup.$name -cnotin @("complete", "notNeeded")) { $Lifecycle.setup.$name = "notNeeded" }
        }
        $Lifecycle.operation = $null
        $Lifecycle.cleanup.stage = "releasePending"
        $Lifecycle.final = New-StateSnapshot -State $state
        $Lifecycle.phase = $CompletionPhase
        $Lifecycle.lastError = $null
        Save-SnapshotAtomic -Snapshot $Lifecycle
        return $state
    }

    $state = Resolve-TrackedOperationForCleanup -Lifecycle $Lifecycle -State $state
    if ($null -ne $Lifecycle.purchaseEvidence -and $null -ne $Lifecycle.held -and
        [string]$Lifecycle.cleanup.origin -ceq "purchasePending")
    {
        $Lifecycle.cleanup.stage = "recoveredHeld"
    }
    else
    {
        $Lifecycle.cleanup.stage = "operationResolved"
    }
    Save-SnapshotAtomic -Snapshot $Lifecycle

    if ($state.RelogNoncePresent -or $state.RestartNoncePresent)
    {
        $Lifecycle.setup.boundaryMarkers = "pending"
        Save-SnapshotAtomic -Snapshot $Lifecycle
        $markers = Invoke-Probe -Arguments "clearBoundaryMarkers $PlayerOid $($Lifecycle.lifecycleId)"
        Assert-Field -Result $markers -Name "cleared" -Expected "true"
        $state = Wait-ForState -Context "boundary-marker cleanup" -Predicate {
            param($current)
            -not $current.RelogNoncePresent -and -not $current.RestartNoncePresent
        }
        $Lifecycle.setup.boundaryMarkers = "complete"
        Save-SnapshotAtomic -Snapshot $Lifecycle
    }
    else { $Lifecycle.setup.boundaryMarkers = "notNeeded"; Save-SnapshotAtomic -Snapshot $Lifecycle }

    if ($state.HasSkill)
    {
        if ($null -eq $Lifecycle.held) { throw "Refusing to surrender an uncorrelated skill during cleanup." }
        Assert-StateGameplayEquals -Actual $state -Expected $Lifecycle.held -Context "Correlated cleanup-held state"
        $Lifecycle.cleanup.stage = "surrenderPending"
        Save-SnapshotAtomic -Snapshot $Lifecycle
        $state = Invoke-Surrender -Lifecycle $Lifecycle
        Assert-SurrenderRelation -Lifecycle $Lifecycle -Surrendered $state
        $Lifecycle.surrendered = New-StateSnapshot -State $state
        $Lifecycle.cleanup.stage = "surrendered"
        Save-SnapshotAtomic -Snapshot $Lifecycle
    }
    elseif ($null -ne $Lifecycle.held -and $null -eq $Lifecycle.surrendered)
    {
        # A crash may occur after the queued surrender removed the skill but
        # before evidence was serialized. Accept only the exact correlated
        # surrendered vector, then checkpoint it before baseline cleanup.
        Assert-SurrenderRelation -Lifecycle $Lifecycle -Surrendered $state
        $Lifecycle.surrendered = New-StateSnapshot -State $state
        $Lifecycle.cleanup.stage = "surrendered"
        Save-SnapshotAtomic -Snapshot $Lifecycle
    }
    if ($null -ne $Lifecycle.purchaseEvidence -and
        ($null -eq $Lifecycle.held -or $null -eq $Lifecycle.surrendered))
    {
        throw "Purchase cleanup cannot advance without correlated held and surrendered evidence."
    }
    $Lifecycle.cleanup.stage = "baselineCleanup"
    Save-SnapshotAtomic -Snapshot $Lifecycle

    $xpDelta = [int]$state.Xp - [int]$Lifecycle.baseline.Xp
    if ($xpDelta -eq $xpCost)
    {
        $Lifecycle.setup.cleanupXp = "pending"
        Save-SnapshotAtomic -Snapshot $Lifecycle
        $xpCleanup = Invoke-Probe -Arguments "grantXp $PlayerOid $xpType -$xpCost $($Lifecycle.lifecycleId)"
        Assert-Field -Result $xpCleanup -Name "setup" -Expected "administrative"
        $state = Wait-ForState -Context "XP cleanup" -Predicate { param($current) $current.Xp -eq [int]$Lifecycle.baseline.Xp }
        $Lifecycle.setup.cleanupXp = "complete"
        Save-SnapshotAtomic -Snapshot $Lifecycle
    }
    elseif ($xpDelta -ne 0)
    {
        throw "Refusing ambiguous XP cleanup delta $xpDelta."
    }
    else { $Lifecycle.setup.cleanupXp = "notNeeded"; Save-SnapshotAtomic -Snapshot $Lifecycle }

    $creditDelta = [int]$state.Credits - [int]$Lifecycle.baseline.Credits
    if ($creditDelta -eq $trainerCost)
    {
        $Lifecycle.setup.cleanupCredits = "pending"
        $Lifecycle.operation = New-TrackedOperation -Kind "drain" -ServerProcessToken $state.ServerProcessToken -Before $state -LifecycleId ([string]$Lifecycle.lifecycleId)
        Save-SnapshotAtomic -Snapshot $Lifecycle
        $drain = Invoke-Probe -Arguments "drainTrainerCost $PlayerOid $($Lifecycle.operation.id) $($Lifecycle.lifecycleId)"
        Assert-Field -Result $drain -Name "queued" -Expected "true"
        $afterQueue = Get-State
        if ([string]$afterQueue.OperationAttemptId -cne [string]$Lifecycle.operation.id -or
            [string]$afterQueue.OperationId -cne [string]$Lifecycle.operation.id -or
            [string]$afterQueue.OperationKind -cne "drain" -or
            [string]$afterQueue.OperationLifecycleId -cne [string]$Lifecycle.lifecycleId -or
            -not $afterQueue.OperationMarkerComplete)
        {
            throw "Credit cleanup dispatch did not publish the exact authoritative operation record."
        }
        Set-TrackedOperationFromState -Lifecycle $Lifecycle -State $afterQueue
        Save-SnapshotAtomic -Snapshot $Lifecycle
        $state = Wait-ForTerminalOperation -OperationId ([string]$Lifecycle.operation.id) -OperationKind "drain" -Context "credit cleanup transfer"
        if ($state.OperationState -cne "drainSucceeded")
        {
            Set-TrackedOperationFromState -Lifecycle $Lifecycle -State $state
            Save-SnapshotAtomic -Snapshot $Lifecycle
            throw "Credit cleanup reached terminal failure '$($state.OperationState)'; snapshot retained."
        }
        Set-TrackedOperationFromState -Lifecycle $Lifecycle -State $state
        Save-SnapshotAtomic -Snapshot $Lifecycle
        $state = Clear-TerminalOperation -Lifecycle $Lifecycle -State $state
        if ([int]$state.Credits -ne [int]$Lifecycle.baseline.Credits)
        {
            throw "Credit cleanup callback completed without restoring the baseline balance."
        }
        $Lifecycle.setup.cleanupCredits = "complete"
        Save-SnapshotAtomic -Snapshot $Lifecycle
    }
    elseif ($creditDelta -ne 0)
    {
        throw "Refusing ambiguous credit cleanup delta $creditDelta."
    }
    else { $Lifecycle.setup.cleanupCredits = "notNeeded"; Save-SnapshotAtomic -Snapshot $Lifecycle }

    if ([bool]$Lifecycle.noviceAdded -and $state.HasNovice)
    {
        if ($state.HasSkill) { throw "Refusing to revoke setup novice while Engineering I remains owned." }
        $Lifecycle.setup.cleanupNovice = "pending"
        Save-SnapshotAtomic -Snapshot $Lifecycle
        $revoke = Invoke-Probe -Arguments "revoke $PlayerOid $noviceSkill $($Lifecycle.lifecycleId)"
        Assert-Field -Result $revoke -Name "hasSkill" -Expected "false"
        $state = Wait-ForState -Context "novice cleanup" -Predicate { param($current) -not $current.HasNovice }
        $Lifecycle.setup.cleanupNovice = "complete"
        Save-SnapshotAtomic -Snapshot $Lifecycle
    }
    else { $Lifecycle.setup.cleanupNovice = "notNeeded"; Save-SnapshotAtomic -Snapshot $Lifecycle }

    $state = Get-State
    Assert-StatePersistentEquals -Actual $state -Expected $Lifecycle.baseline -Context "Final fixture baseline"
    if ($state.RelogNoncePresent -or $state.RestartNoncePresent)
    {
        throw "Final baseline retained a volatile boundary nonce."
    }
    Assert-NoOperationInstrumentation -State $state -Context "Pre-release baseline"
    if ([string]$state.LifecycleId -cne [string]$Lifecycle.lifecycleId)
    {
        throw "Baseline restoration is not owned by the exact lifecycle or retains an operation."
    }
    $Lifecycle.phase = "releasePending"
    $Lifecycle.cleanup.stage = "releasePending"
    Save-SnapshotAtomic -Snapshot $Lifecycle
    $released = Invoke-Probe -Arguments "clearLifecycle $PlayerOid $($Lifecycle.lifecycleId)"
    Assert-Field -Result $released -Name "cleared" -Expected "true"
    $state = Get-State
    Assert-StatePersistentEquals -Actual $state -Expected $Lifecycle.baseline -Context "Released final fixture baseline"
    Assert-NoOperationInstrumentation -State $state -Context "Released final baseline"
    if ([string]$state.LifecycleMarkerState -cne "none" -or
        [string]$state.LifecycleAttemptId -cne "none" -or
        [string]$state.LifecycleId -cne "none" -or
        $state.LifecycleBaselineComplete -or
        $state.RelogNoncePresent -or $state.RestartNoncePresent)
    {
        throw "Lifecycle release did not remove all instrumentation."
    }
    $Lifecycle.final = New-StateSnapshot -State $state
    $Lifecycle.phase = $CompletionPhase
    $Lifecycle.lastError = $null
    Save-SnapshotAtomic -Snapshot $Lifecycle
    return $state
}

function Copy-OfflineObject
{
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 16 | ConvertFrom-Json)
}

function New-ValidatedPreparedLifecycleCandidate
{
    param([object]$Lifecycle, [object]$PreparedState, [object]$CurrentIdentity)
    $candidate = Copy-OfflineObject -Value $Lifecycle
    $candidate.setup.funding = "complete"
    $candidate.prepared = New-StateSnapshot -State $PreparedState
    $candidate.phase = "prepared"
    Assert-PreparedRelation -Lifecycle $candidate
    Assert-LifecycleSnapshot -Lifecycle $candidate -CurrentIdentity $CurrentIdentity
    return $candidate
}

function New-ValidatedHeldLifecycleCandidate
{
    param(
        [object]$Lifecycle,
        [object]$HeldState,
        [object]$CurrentIdentity,
        [ValidateSet("callback", "restartAccountingResume", "restartCallbackReplay")] [string]$OutcomeSource
    )
    $candidate = Copy-OfflineObject -Value $Lifecycle
    $candidate.purchaseEvidence = New-PurchaseEvidence -Lifecycle $candidate -State $HeldState -OutcomeSource $OutcomeSource
    $candidate.held = New-StateSnapshot -State $HeldState
    $candidate.phase = "held"
    Assert-HeldRelation -Lifecycle $candidate -Held $candidate.held
    Assert-LifecycleSnapshot -Lifecycle $candidate -CurrentIdentity $CurrentIdentity
    return $candidate
}

function New-ValidatedLastErrorLifecycleCandidate
{
    param([object]$Lifecycle, [string]$Message, [object]$CurrentIdentity)
    $candidate = Copy-OfflineObject -Value $Lifecycle
    $candidate.lastError = $Message
    Assert-LifecycleSnapshot -Lifecycle $candidate -CurrentIdentity $CurrentIdentity
    return $candidate
}

function Assert-OfflineThrows
{
    param([scriptblock]$Action, [string]$Name)
    $threw = $false
    try { & $Action }
    catch { $threw = $true }
    if (-not $threw) { throw "Offline negative test '$Name' did not fail closed." }
}

function New-OfflineState
{
    param([string]$Lifecycle = "none")
    $commandVector = ($expectedCommands | ForEach-Object { "$_`:false" }) -join ","
    $modVector = ($expectedMods | ForEach-Object { "$_`:0" }) -join ","
    $schematicVector = ($expectedSchematics | ForEach-Object { "$_`:false" }) -join ","
    return [pscustomobject]@{
        ContractId = $runtimeContractId; StationId = $stationId
        MaterializationFingerprint = $materializationFingerprint; DeployedArtifactsVerified = $true
        ServerProcessToken = "00000000-0000-0000-0000-000000000001|41|99"
        LifecycleAttemptId = $Lifecycle; LifecycleId = $Lifecycle
        LifecycleMarkerState = $(if ($Lifecycle -ceq "none") { "none" } else { "complete" })
        LifecycleBaselineComplete = ($Lifecycle -cne "none")
        HasNovice = $true; HasSkill = $false; HasCommand = $false; HasSchematic = $false
        SkillCost = 0; Points = 250; Xp = 0; Cap = 1500; SkillModValue = 0
        Cash = 0; Bank = 0; Credits = 0
        VectorCommandsOwned = 1; VectorCommandsExpected = $expectedCommands.Count
        VectorModsMatched = 0; VectorModsExpected = $expectedMods.Count
        VectorSchematicsOwned = 0; VectorSchematicsExpected = $expectedSchematics.Count
        VectorComplete = $false; VectorCommands = $commandVector; VectorMods = $modVector; VectorSchematics = $schematicVector
        OperationAttemptId = "none"; OperationId = "none"; OperationKind = "none"; OperationState = "none"; OperationUpdated = 0
        OperationLifecycleId = "none"; OperationTrainerOid = "none"; OperationSkillName = "none"
        OperationCost = 0; OperationProtocolVersion = 0
        OperationRefundGeneration = 0; OperationRefundAttemptKey = "none"; OperationRefundRetryConsumed = $false
        OperationAccountingAttemptKey = "none"; OperationAccountingAccount = "none"; OperationAccountingOutcome = "none"
        OperationMarkerComplete = $false; OperationPreimageMatches = $false
        RelogNoncePresent = $false; RestartNoncePresent = $false; NewbieFreeTrainingRouteActive = $false
        ProbeText = "offline=true"
    }
}

function New-OfflineIdentity
{
    return [pscustomobject]@{
        RunnerSchemaVersion = $runnerSchemaVersion
        RunnerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
        RuntimeContractId = $runtimeContractId
        RuntimeMaterializationFingerprint = $materializationFingerprint
        ContractSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $contractPath).Hash
        ManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
        RuntimePatchSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimePatchPath).Hash
        MarkerPatchSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $markerPatchPath).Hash
        BaselineSuperprojectCommit = [string]$manifest.target.baselineSuperprojectCommit
        ContainerName = $ContainerName; ContainerId = "offline-container"; ContainerImageId = "offline-image"
    }
}

function New-OfflineLifecycle
{
    param([object]$Identity)
    $now = [DateTime]::UtcNow.ToString("o")
    return [pscustomobject]@{
        schemaVersion = $snapshotSchemaVersion; playerOid = "91001"
        lifecycleId = "11111111111111111111111111111111"; createdAtUtc = $now; phase = "lifecyclePending"
        identity = $Identity
        setup = [pscustomobject]@{ novice = "notNeeded"; xp = "notStarted"; funding = "notStarted"; cleanupXp = "notStarted"; cleanupCredits = "notStarted"; cleanupNovice = "notStarted"; boundaryMarkers = "notStarted" }
        noviceAdded = $false; baseline = New-StateSnapshot -State (New-OfflineState)
        prepared = $null; conversation = $null; operation = $null; purchaseEvidence = $null; held = $null
        boundaries = [pscustomobject]@{ relog = $null; restart = $null }
        surrendered = $null; cleanup = $null; final = $null; lastError = $null
    }
}

function New-OfflinePreparedState
{
    param([object]$Lifecycle)
    $state = New-OfflineState -Lifecycle $Lifecycle.lifecycleId
    $state.Xp = $xpCost; $state.Cash = 0; $state.Bank = $trainerCost; $state.Credits = $trainerCost
    $state.Cap = 1500; $state.SkillModValue = 20
    $commandMap = @($expectedCommands | ForEach-Object { "$_`:" + $(if ($_ -ceq $expectedCommands[0]) { "true" } else { "false" }) })
    $state.VectorCommands = $commandMap -join ","; $state.VectorCommandsOwned = 1
    $modEntries = @(); $matched = 0
    foreach ($name in $expectedMods)
    {
        $absolute = [int]$runtimeContract.completeGrantVector.skillMods.$name
        $value = $absolute - [int]$purchaseModDeltas.$name
        if ($value -eq $absolute) { $matched++ }
        $modEntries += "$name`:$value"
    }
    $state.VectorMods = $modEntries -join ","; $state.VectorModsMatched = $matched
    $schematicEntries = @(); $owned = 0
    foreach ($name in $expectedSchematics)
    {
        $has = $name -cnotin $purchaseSchematics
        if ($has) { $owned++ }
        $schematicEntries += "$name`:" + $(if ($has) { "true" } else { "false" })
    }
    $state.VectorSchematics = $schematicEntries -join ","; $state.VectorSchematicsOwned = $owned
    return $state
}

function New-OfflineHeldState
{
    param([object]$Lifecycle, [object]$Prepared, [string]$OperationId)
    $state = Copy-OfflineObject -Value $Prepared
    $state.HasSkill = $true; $state.HasCommand = $true; $state.HasSchematic = $true
    $state.SkillCost = $engineeringPointCost; $state.Points = [int]$Prepared.Points - $engineeringPointCost
    $state.Xp = [int]$Prepared.Xp - $xpCost; $state.Cash = 0; $state.Bank = 0; $state.Credits = 0
    $state.Cap = 2000; $state.SkillModValue = 30
    $state.VectorCommands = ($expectedCommands | ForEach-Object { "$_`:true" }) -join ","
    $state.VectorCommandsOwned = $expectedCommands.Count
    $state.VectorMods = ($expectedMods | ForEach-Object { "$_`:" + [string]$runtimeContract.completeGrantVector.skillMods.$_ }) -join ","
    $state.VectorModsMatched = $expectedMods.Count
    $state.VectorSchematics = ($expectedSchematics | ForEach-Object { "$_`:true" }) -join ","
    $state.VectorSchematicsOwned = $expectedSchematics.Count; $state.VectorComplete = $true
    $state.OperationAttemptId = $OperationId; $state.OperationId = $OperationId
    $state.OperationKind = "purchase"; $state.OperationState = "purchaseSucceeded"; $state.OperationUpdated = 1
    $state.OperationLifecycleId = [string]$Lifecycle.lifecycleId
    $state.OperationTrainerOid = "70001"; $state.OperationSkillName = $engineeringSkill
    $state.OperationCost = $trainerCost; $state.OperationProtocolVersion = 64
    $state.OperationRefundGeneration = 0; $state.OperationRefundAttemptKey = "none"; $state.OperationRefundRetryConsumed = $false
    $state.OperationAccountingAttemptKey = "$OperationId.accounting.1"
    $state.OperationAccountingAccount = "skillTrainingSystem"; $state.OperationAccountingOutcome = "SUCCESS"
    $state.OperationMarkerComplete = $true
    $state.OperationPreimageMatches = $false
    $state.RelogNoncePresent = $true; $state.RestartNoncePresent = $false
    return $state
}

function New-OfflinePurchaseCrashState
{
    param(
        [object]$Lifecycle,
        [string]$OperationState,
        [ValidateSet("PRE", "DEBIT", "HELD", "REFUND")] [string]$Vector,
        [switch]$ChangedProcess
    )
    $operation = $Lifecycle.operation
    if ($null -eq $operation) { throw "Offline purchase crash state requires an operation." }
    if ($Vector -ceq "HELD")
    {
        $state = New-OfflineHeldState -Lifecycle $Lifecycle -Prepared $Lifecycle.prepared -OperationId ([string]$operation.id)
        $state.RelogNoncePresent = $false
    }
    else
    {
        $state = Copy-OfflineObject -Value $Lifecycle.prepared
        if ($Vector -ceq "DEBIT")
        {
            $bankDebit = [Math]::Min([int]$state.Bank, $trainerCost)
            $cashDebit = $trainerCost - $bankDebit
            $state.Cash = [int]$state.Cash - $cashDebit
            $state.Bank = [int]$state.Bank - $bankDebit
            $state.Credits = [int]$state.Credits - $trainerCost
        }
        $state.OperationAttemptId = [string]$operation.id
        $state.OperationId = [string]$operation.id
        $state.OperationKind = "purchase"
        $state.OperationUpdated = 1
        $state.OperationLifecycleId = [string]$operation.lifecycleId
        $state.OperationTrainerOid = [string]$operation.trainerOid
        $state.OperationSkillName = [string]$operation.skillName
        $state.OperationCost = [int]$operation.cost
        $state.OperationMarkerComplete = $true
        $state.OperationPreimageMatches = ($Vector -cin @("PRE", "REFUND"))
        $state.RelogNoncePresent = $false
        $state.RestartNoncePresent = $false
    }
    $state.OperationState = $OperationState
    $state.OperationProtocolVersion = 64
    $state.OperationRefundGeneration = 0
    $state.OperationRefundAttemptKey = "none"
    $state.OperationRefundRetryConsumed = $false
    $state.OperationAccountingAttemptKey = "none"
    $state.OperationAccountingAccount = "none"
    $state.OperationAccountingOutcome = "none"
    if ($OperationState -cin @("refundInitialClaiming", "refundInitialDispatching", "refundInitialPending", "refundInitialFailed", "purchaseRefunded"))
    {
        $state.OperationRefundGeneration = 1
        $state.OperationRefundAttemptKey = "$($operation.id).refund.1"
    }
    elseif ($OperationState -cin @("refundRecoveryClaiming", "refundRecoveryDispatching", "refundRecoveryPending", "refundRecoveryFailed"))
    {
        $state.OperationRefundGeneration = 2
        $state.OperationRefundAttemptKey = "$($operation.id).refund.2"
        $state.OperationRefundRetryConsumed = $true
    }
    elseif ($OperationState -cin @("accountingRequested", "accountingRequestQueueFailed", "accountingDispatching", "accountingPending", "accountingQueueFailed", "accountingFailed", "accountingSucceededCallback", "purchaseSucceeded"))
    {
        $state.OperationAccountingAttemptKey = "$($operation.id).accounting.1"
        $state.OperationAccountingAccount = "skillTrainingSystem"
        $state.OperationAccountingOutcome = switch ($OperationState)
        {
            "accountingRequestQueueFailed" { "REQUEST_QUEUE_FAILED" }
            "accountingQueueFailed" { "QUEUE_FAILED" }
            "accountingFailed" { "FAILED" }
            "accountingSucceededCallback" { "SUCCESS" }
            "purchaseSucceeded" { "SUCCESS" }
            default { "none" }
        }
    }
    if ($ChangedProcess)
    {
        $state.ServerProcessToken = "00000000-0000-0000-0000-000000000009|49|109"
    }
    return $state
}

function New-OfflineOriginLifecycle
{
    param([string]$Origin, [object]$Identity)
    $lifecycle = New-OfflineLifecycle -Identity $Identity
    $lifecycle.phase = $Origin
    if ($Origin -ceq "lifecyclePending" -or $Origin -ceq "preparing") { return $lifecycle }

    $preparedState = New-OfflinePreparedState -Lifecycle $lifecycle
    if ($Origin -ceq "fundingPending")
    {
        $before = New-StateSnapshot -State $preparedState
        $before.Cash = 0; $before.Credits = 0
        $lifecycle.operation = New-TrackedOperation -Kind "fund" -ServerProcessToken $before.ServerProcessToken -Before $before -LifecycleId $lifecycle.lifecycleId
        $lifecycle.operation.id = "44444444444444444444444444444444"
        return $lifecycle
    }

    $lifecycle.prepared = New-StateSnapshot -State $preparedState
    if ($Origin -ceq "prepared") { return $lifecycle }
    $conversationStatus = $(if ($Origin -ceq "conversationPending") { "pending" } else { "queued" })
    $lifecycle.conversation = [pscustomobject]@{ trainerOid = "70001"; status = $conversationStatus; queuedAtUtc = $(if ($conversationStatus -ceq "queued") { [DateTime]::UtcNow.ToString("o") } else { "" }) }
    if ($Origin -in @("conversationPending", "conversationQueued")) { return $lifecycle }

    $operationId = "55555555555555555555555555555555"
    $operationState = $(if ($Origin -ceq "purchasePending") { "checkpointed" } else { "purchaseSucceeded" })
    $lifecycle.operation = New-TrackedOperation -Kind "purchase" -ServerProcessToken $preparedState.ServerProcessToken -Before $preparedState -LifecycleId $lifecycle.lifecycleId -TrainerOid "70001" -SkillName $engineeringSkill
    $lifecycle.operation.id = $operationId
    $lifecycle.operation.state = $operationState
    if ($operationState -ceq "purchaseSucceeded")
    {
        $lifecycle.operation.accountingAttemptKey = "$operationId.accounting.1"
        $lifecycle.operation.accountingAccount = "skillTrainingSystem"
        $lifecycle.operation.accountingOutcome = "SUCCESS"
        $lifecycle.operation.terminalAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    if ($Origin -ceq "purchasePending") { return $lifecycle }

    $offlineHeldState = New-OfflineHeldState -Lifecycle $lifecycle -Prepared $preparedState -OperationId $operationId
    $lifecycle.purchaseEvidence = New-PurchaseEvidence -Lifecycle $lifecycle -State $offlineHeldState -OutcomeSource "callback"
    $lifecycle.held = New-StateSnapshot -State $offlineHeldState
    if ($Origin -ceq "held" -or $Origin -ceq "restartBoundaryArming") { return $lifecycle }
    $lifecycle.boundaries.relog = [pscustomobject]@{ Kind = "Relog"; OperationId = $operationId; ServerProcessToken = $preparedState.ServerProcessToken; VerifiedAtUtc = [DateTime]::UtcNow.ToString("o") }
    if ($Origin -ceq "relogVerified") { return $lifecycle }
    $lifecycle.boundaries.restart = [pscustomobject]@{ Kind = "Restart"; OperationId = $operationId; ServerProcessToken = "00000000-0000-0000-0000-000000000002|42|100"; VerifiedAtUtc = [DateTime]::UtcNow.ToString("o") }
    return $lifecycle
}

function Get-PostDispatchCheckpointState
{
    param([object]$State)
    # Never synthesize queued from an RPC return. Persist only the marker state
    # read authoritatively after dispatch; synchronous terminals remain terminal.
    return [string]$State.OperationState
}

function Get-OfflinePhaseACallbackDecision
{
    param(
        [string]$ExpectedId,
        [string]$ActualId,
        [string]$ExpectedKind,
        [string]$ActualKind,
        [string]$ExpectedLifecycle,
        [string]$ActualLifecycle,
        [string]$State,
        [string[]]$AllowedStates,
        [bool]$PreimageComplete = $true,
        [bool]$PreimageLifecycleExact = $true,
        [bool]$AuthoritativeBalancesExact = $true,
        [bool]$AuthoritativeGameplayExact = $true
    )
    if ($ExpectedId -cne $ActualId -or $ExpectedKind -cne $ActualKind -or
        $ExpectedLifecycle -cne $ActualLifecycle -or $State -cnotin $AllowedStates -or
        -not $PreimageComplete -or -not $PreimageLifecycleExact -or
        -not $AuthoritativeBalancesExact -or -not $AuthoritativeGameplayExact)
    {
        return "quarantine"
    }
    return "apply"
}

function Invoke-OfflineSelfTest
{
    $originalPlayerOid = $PlayerOid
    $originalSnapshotPath = $SnapshotPath
    Set-Variable -Name PlayerOid -Scope Script -Value "91001"
    try
    {
        $identity = New-OfflineIdentity
        $lifecycle = New-OfflineLifecycle -Identity $identity
        Assert-LifecycleSnapshot -Lifecycle $lifecycle -CurrentIdentity $identity

        $origins = @("lifecyclePending", "preparing", "fundingPending", "prepared", "conversationPending", "conversationQueued", "purchasePending", "held", "restartBoundaryArming", "relogVerified", "restartVerified")
        foreach ($origin in $origins)
        {
            $originLifecycle = New-OfflineOriginLifecycle -Origin $origin -Identity $identity
            Assert-LifecycleSnapshot -Lifecycle $originLifecycle -CurrentIdentity $identity
            $originLifecycle.phase = "cleanupPending"
            $originLifecycle.cleanup = [pscustomobject]@{ origin = $origin; startedAtUtc = [DateTime]::UtcNow.ToString("o"); stage = "starting" }
            Assert-LifecycleSnapshot -Lifecycle $originLifecycle -CurrentIdentity $identity
        }
        $cleanup = New-OfflineOriginLifecycle -Origin "lifecyclePending" -Identity $identity
        $cleanup.phase = "cleanupPending"
        $cleanup.cleanup = [pscustomobject]@{ origin = "lifecyclePending"; startedAtUtc = [DateTime]::UtcNow.ToString("o"); stage = "starting" }
        Write-Host "[PASS] early-cleanup-origins"

        $wrongCase = Copy-OfflineObject -Value $cleanup
        $wrongCase.phase = "CleanupPending"
        Assert-OfflineThrows -Name "case-sensitive-enum" -Action { Assert-LifecycleSnapshot -Lifecycle $wrongCase -CurrentIdentity $identity }
        $wrongKind = New-OfflineOriginLifecycle -Origin "fundingPending" -Identity $identity
        $wrongKind.phase = "cleanupPending"
        $wrongKind.cleanup = [pscustomobject]@{ origin = "fundingPending"; startedAtUtc = [DateTime]::UtcNow.ToString("o"); stage = "starting" }
        $wrongKind.operation.state = "purchaseSucceeded"
        $wrongKind.operation.terminalAtUtc = [DateTime]::UtcNow.ToString("o")
        Assert-OfflineThrows -Name "per-kind-operation-state" -Action { Assert-LifecycleSnapshot -Lifecycle $wrongKind -CurrentIdentity $identity }
        Write-Host "[PASS] case-sensitive-per-kind-schemas"

        $badTime = Copy-OfflineObject -Value $cleanup
        $badTime.cleanup.startedAtUtc = ([DateTime]::UtcNow.AddDays(-2).ToString("o"))
        Assert-OfflineThrows -Name "timestamp-order" -Action { Assert-LifecycleSnapshot -Lifecycle $badTime -CurrentIdentity $identity }

        $activeState = New-OfflineState -Lifecycle "22222222222222222222222222222222"
        Assert-OfflineThrows -Name "lifecycle-mismatch" -Action { Assert-CurrentLifecycleMarker -Lifecycle $lifecycle -State $activeState }
        $partialLifecycleState = New-OfflineState
        $partialLifecycleState.LifecycleAttemptId = $lifecycle.lifecycleId
        $partialLifecycleState.LifecycleMarkerState = "partial"
        Assert-CurrentLifecycleMarker -Lifecycle $lifecycle -State $partialLifecycleState
        $partialCleanup = Copy-OfflineObject -Value $lifecycle
        $partialCleanup.phase = "cleanupPending"
        $partialCleanup.cleanup = [pscustomobject]@{ origin = "lifecyclePending"; startedAtUtc = [DateTime]::UtcNow.ToString("o"); stage = "starting" }
        Assert-CurrentLifecycleMarker -Lifecycle $partialCleanup -State $partialLifecycleState
        $gameplayMutationCounter = [pscustomobject]@{ Value = 0 }
        $driftedPartialState = Copy-OfflineObject -Value $partialLifecycleState
        $driftedPartialState.Xp = 1
        Assert-OfflineThrows -Name "lifecyclePending-zero-gameplay-drift" -Action {
            Assert-StateGameplayEquals -Actual $driftedPartialState -Expected $lifecycle.baseline -Context "offline lifecyclePending drift"
            $gameplayMutationCounter.Value++
        }
        if ([int]$gameplayMutationCounter.Value -ne 0) { throw "lifecyclePending drift crossed a gameplay mutation boundary." }
        Write-Host "[PASS] lifecycle-mismatch"

        $releasePending = Copy-OfflineObject -Value $cleanup
        $releasePending.phase = "releasePending"
        $releasePending.cleanup.stage = "releasePending"
        foreach ($name in @("cleanupXp", "cleanupCredits", "cleanupNovice", "boundaryMarkers")) { $releasePending.setup.$name = "notNeeded" }
        Assert-LifecycleSnapshot -Lifecycle $releasePending -CurrentIdentity $identity
        Assert-CurrentLifecycleMarker -Lifecycle $releasePending -State $releasePending.baseline
        Assert-StatePersistentEquals -Actual $releasePending.baseline -Expected $releasePending.baseline -Context "Offline releasePending replay"
        Write-Host "[PASS] releasePending-replay"

        $terminal = Copy-OfflineObject -Value $cleanup
        $terminal.phase = "cleaned"
        $terminal.cleanup.stage = "releasePending"
        foreach ($name in @("cleanupXp", "cleanupCredits", "cleanupNovice", "boundaryMarkers")) { $terminal.setup.$name = "notNeeded" }
        $terminal.final = Copy-OfflineObject -Value $terminal.baseline
        Assert-LifecycleSnapshot -Lifecycle $terminal -CurrentIdentity $identity
        Assert-TerminalCleanupNoOp -Lifecycle $terminal -State $terminal.final
        $driftedFinal = Copy-OfflineObject -Value $terminal.final
        $driftedFinal.Cash = 1; $driftedFinal.Credits = 1
        Assert-OfflineThrows -Name "terminal-noop-drift" -Action { Assert-TerminalCleanupNoOp -Lifecycle $terminal -State $driftedFinal }
        Write-Host "[PASS] terminal-noop-zero-mutations"

        $wrongIdentity = Copy-OfflineObject -Value $identity
        $wrongIdentity.RunnerSha256 = ("f" * 64)
        Assert-OfflineThrows -Name "runner-identity" -Action { Assert-ExecutionIdentity -Actual $identity -Expected $wrongIdentity }
        Write-Host "[PASS] runner-hash-drift"

        $wrongFingerprintIdentity = Copy-OfflineObject -Value $identity
        $wrongFingerprintIdentity.RuntimeMaterializationFingerprint = ("e" * 64)
        Assert-OfflineThrows -Name "fingerprint-drift" -Action { Assert-ExecutionIdentity -Actual $identity -Expected $wrongFingerprintIdentity }
        Write-Host "[PASS] fingerprint-drift"

        $before = New-OfflineState -Lifecycle $lifecycle.lifecycleId
        $beforeSnapshot = New-StateSnapshot -State $before
        $operationId = "33333333333333333333333333333333"
        $reservedLifecycle = Copy-OfflineObject -Value $cleanup
        $reservedLifecycle.operation = New-TrackedOperation -Kind "fund" -ServerProcessToken $before.ServerProcessToken -Before $beforeSnapshot -LifecycleId $lifecycle.lifecycleId
        $reservedLifecycle.operation.id = $operationId
        $reservedLifecycle.operation.state = "reserved"
        $reservedState = Copy-OfflineObject -Value $before
        $reservedState.OperationAttemptId = $operationId; $reservedState.OperationId = $operationId
        $reservedState.OperationKind = "fund"; $reservedState.OperationState = "reserved"
        $reservedState.OperationUpdated = 1
        $reservedState.OperationLifecycleId = $lifecycle.lifecycleId
        $reservedState.OperationTrainerOid = "none"; $reservedState.OperationSkillName = "none"
        $reservedState.OperationCost = $trainerCost; $reservedState.OperationProtocolVersion = 64
        $reservedState.OperationMarkerComplete = $true
        $reservedState.OperationPreimageMatches = $true
        if ((Assert-ReservedOperationClearable -Lifecycle $reservedLifecycle -State $reservedState) -cne "clearReserved") { throw "Reserved decision drifted." }
        $checkpointedReservedLifecycle = Copy-OfflineObject -Value $reservedLifecycle
        $checkpointedReservedLifecycle.operation.state = "checkpointed"
        if ((Assert-ReservedOperationClearable -Lifecycle $checkpointedReservedLifecycle -State $reservedState) -cne "clearReserved") { throw "Checkpointed-to-reserved crash recovery decision drifted." }
        $partialState = Copy-OfflineObject -Value $reservedState
        $partialState.OperationId = "none"; $partialState.OperationKind = "missing"
        $partialState.OperationState = "reserving"; $partialState.OperationLifecycleId = "missing"
        $partialState.OperationTrainerOid = "missing"; $partialState.OperationSkillName = "missing"
        $partialState.OperationCost = 0; $partialState.OperationUpdated = 0
        $partialState.OperationProtocolVersion = 0
        $partialState.OperationRefundAttemptKey = "missing"
        $partialState.OperationAccountingAttemptKey = "missing"
        $partialState.OperationAccountingAccount = "missing"
        $partialState.OperationAccountingOutcome = "missing"
        $partialState.OperationMarkerComplete = $false
        if ((Assert-ReservedOperationClearable -Lifecycle $checkpointedReservedLifecycle -State $partialState) -cne "clearReserved") { throw "Checkpointed-to-reserving crash recovery decision drifted." }
        $attemptOnlyState = Copy-OfflineObject -Value $before
        $attemptOnlyState.OperationAttemptId = $operationId
        $attemptOnlyState.OperationId = "none"; $attemptOnlyState.OperationKind = "missing"
        $attemptOnlyState.OperationState = "missing"; $attemptOnlyState.OperationUpdated = 0
        $attemptOnlyState.OperationLifecycleId = "missing"; $attemptOnlyState.OperationTrainerOid = "missing"
        $attemptOnlyState.OperationSkillName = "missing"; $attemptOnlyState.OperationCost = 0
        $attemptOnlyState.OperationRefundAttemptKey = "missing"
        $attemptOnlyState.OperationAccountingAttemptKey = "missing"
        $attemptOnlyState.OperationAccountingAccount = "missing"
        $attemptOnlyState.OperationAccountingOutcome = "missing"
        $attemptOnlyState.OperationMarkerComplete = $false; $attemptOnlyState.OperationPreimageMatches = $true
        if ((Assert-ReservedOperationClearable -Lifecycle $checkpointedReservedLifecycle -State $attemptOnlyState) -cne "clearReserved") { throw "Checkpointed-to-attempt-only crash recovery decision drifted." }
        $attemptResidual = Copy-OfflineObject -Value $attemptOnlyState
        $attemptResidual.OperationKind = "fund"
        Assert-OfflineThrows -Name "attempt-only-residual" -Action { $null = Assert-ReservedOperationClearable -Lifecycle $checkpointedReservedLifecycle -State $attemptResidual }

        $visiblePrefixTemplate = Copy-OfflineObject -Value $reservedState
        $visiblePrefixTemplate.OperationState = "reserving"
        $visiblePrefixTemplate.OperationMarkerComplete = $false
        $visiblePrefixLeaves = @(
            [pscustomobject]@{ Property = "OperationKind"; Absent = "missing"; Present = "fund" },
            [pscustomobject]@{ Property = "OperationUpdated"; Absent = 0; Present = 1 },
            [pscustomobject]@{ Property = "OperationLifecycleId"; Absent = "missing"; Present = $lifecycle.lifecycleId },
            [pscustomobject]@{ Property = "OperationTrainerOid"; Absent = "missing"; Present = "none" },
            [pscustomobject]@{ Property = "OperationSkillName"; Absent = "missing"; Present = "none" },
            [pscustomobject]@{ Property = "OperationCost"; Absent = 0; Present = $trainerCost },
            [pscustomobject]@{ Property = "OperationProtocolVersion"; Absent = 0; Present = 64 },
            [pscustomobject]@{ Property = "OperationRefundAttemptKey"; Absent = "missing"; Present = "none" },
            [pscustomobject]@{ Property = "OperationAccountingAttemptKey"; Absent = "missing"; Present = "none" },
            [pscustomobject]@{ Property = "OperationAccountingAccount"; Absent = "missing"; Present = "none" },
            [pscustomobject]@{ Property = "OperationAccountingOutcome"; Absent = "missing"; Present = "none" },
            [pscustomobject]@{ Property = "OperationId"; Absent = "none"; Present = $operationId }
        )
        for ($cut = 0; $cut -le $visiblePrefixLeaves.Count; $cut++)
        {
            $visiblePrefixState = Copy-OfflineObject -Value $visiblePrefixTemplate
            for ($index = 0; $index -lt $visiblePrefixLeaves.Count; $index++)
            {
                $leaf = $visiblePrefixLeaves[$index]
                $visiblePrefixState.($leaf.Property) = $(if ($index -lt $cut) { $leaf.Present } else { $leaf.Absent })
            }
            if ((Assert-ReservedOperationClearable -Lifecycle $checkpointedReservedLifecycle -State $visiblePrefixState) -cne "clearReserved")
            {
                throw "Observable reservation prefix cut $cut was rejected."
            }
        }
        for ($gap = 0; $gap -lt ($visiblePrefixLeaves.Count - 1); $gap++)
        {
            $visibleGapState = Copy-OfflineObject -Value $visiblePrefixTemplate
            for ($index = 0; $index -lt $visiblePrefixLeaves.Count; $index++)
            {
                $leaf = $visiblePrefixLeaves[$index]
                $visibleGapState.($leaf.Property) = $(if ($index -lt $gap) { $leaf.Present } else { $leaf.Absent })
            }
            $laterLeaf = $visiblePrefixLeaves[$gap + 1]
            $visibleGapState.($laterLeaf.Property) = $laterLeaf.Present
            Assert-OfflineThrows -Name "visible-reservation-prefix-gap-$gap" -Action {
                $null = Assert-ReservedOperationClearable -Lifecycle $checkpointedReservedLifecycle -State $visibleGapState
            }
        }

        $impossibleVisiblePrefix = Copy-OfflineObject -Value $visiblePrefixTemplate
        foreach ($leaf in $visiblePrefixLeaves)
        {
            $impossibleVisiblePrefix.($leaf.Property) = $leaf.Absent
        }
        $impossibleVisiblePrefix.OperationLifecycleId = [string]$lifecycle.lifecycleId
        $impossibleVisiblePrefixCalls = [pscustomobject]@{ Probe = 0; Read = 0; Write = 0 }
        Assert-OfflineThrows -Name "resolve-visible-reservation-prefix-gap" -Action {
            $null = Resolve-TrackedOperationForCleanup `
                -Lifecycle $checkpointedReservedLifecycle `
                -State $impossibleVisiblePrefix `
                -ReservedProbeInvoker { param($command) $impossibleVisiblePrefixCalls.Probe++; throw "visible gap reached clear RPC" } `
                -ReservedStateReader { $impossibleVisiblePrefixCalls.Read++; throw "visible gap reached state refresh" } `
                -ReservedSnapshotWriter { param($snapshot) $impossibleVisiblePrefixCalls.Write++; throw "visible gap reached snapshot write" }
        }
        if ($impossibleVisiblePrefixCalls.Probe -ne 0 -or
            $impossibleVisiblePrefixCalls.Read -ne 0 -or
            $impossibleVisiblePrefixCalls.Write -ne 0 -or
            $null -eq $checkpointedReservedLifecycle.operation)
        {
            throw "Impossible visible reservation prefix crossed a Resolve mutation boundary."
        }
        foreach ($partialControlStateName in @("missing", "reserving"))
        {
            $partialControlLifecycle = New-OfflineOriginLifecycle -Origin "fundingPending" -Identity $identity
            $partialControlLifecycle.phase = "cleanupPending"
            $partialControlLifecycle.cleanup = [pscustomobject]@{
                origin = "fundingPending"
                startedAtUtc = [DateTime]::UtcNow.ToString("o")
                stage = "starting"
            }
            $partialControlState = Copy-OfflineObject -Value $partialControlLifecycle.operation.before
            $partialControlState.OperationAttemptId = [string]$partialControlLifecycle.operation.id
            $partialControlState.OperationId = "none"
            $partialControlState.OperationKind = "missing"
            $partialControlState.OperationState = $partialControlStateName
            $partialControlState.OperationLifecycleId = "missing"
            $partialControlState.OperationTrainerOid = "missing"
            $partialControlState.OperationSkillName = "missing"
            $partialControlState.OperationCost = 0
            $partialControlState.OperationProtocolVersion = 0
            $partialControlState.OperationRefundAttemptKey = "missing"
            $partialControlState.OperationAccountingAttemptKey = "missing"
            $partialControlState.OperationAccountingAccount = "missing"
            $partialControlState.OperationAccountingOutcome = "missing"
            $partialControlState.OperationMarkerComplete = $false
            $partialControlState.OperationPreimageMatches = $true
            $partialControlCleared = Copy-OfflineObject -Value $partialControlLifecycle.operation.before
            $partialControlSnapshots = New-Object System.Collections.ArrayList
            $partialControlResult = Resolve-TrackedOperationForCleanup `
                -Lifecycle $partialControlLifecycle `
                -State $partialControlState `
                -ReservedProbeInvoker { param($command) [pscustomobject]@{ Text = $command; Values = @{ cleared = "true" } } } `
                -ReservedStateReader { $partialControlCleared } `
                -ReservedSnapshotWriter {
                    param($snapshot)
                    Assert-LifecycleSnapshot -Lifecycle $snapshot -CurrentIdentity $identity
                    [void]$partialControlSnapshots.Add((Copy-OfflineObject -Value $snapshot))
                }
            if ([string]$partialControlResult.OperationAttemptId -cne "none" -or
                $partialControlSnapshots.Count -ne 2 -or
                [string]$partialControlSnapshots[0].operation.reconcileTarget -cne "clearReserved" -or
                $null -ne $partialControlSnapshots[1].operation)
            {
                throw "Resolve control path rejected or incompletely cleared checkpointed->$partialControlStateName recovery."
            }
        }
        $residualPartialLifecycle = New-OfflineOriginLifecycle -Origin "fundingPending" -Identity $identity
        $residualPartialLifecycle.phase = "cleanupPending"
        $residualPartialLifecycle.cleanup = [pscustomobject]@{
            origin = "fundingPending"
            startedAtUtc = [DateTime]::UtcNow.ToString("o")
            stage = "starting"
        }
        $residualPartialState = Copy-OfflineObject -Value $residualPartialLifecycle.operation.before
        $residualPartialState.OperationAttemptId = [string]$residualPartialLifecycle.operation.id
        $residualPartialState.OperationId = "none"
        $residualPartialState.OperationKind = "missing"
        $residualPartialState.OperationState = "reserving"
        $residualPartialState.OperationLifecycleId = "missing"
        $residualPartialState.OperationTrainerOid = "missing"
        $residualPartialState.OperationSkillName = "missing"
        $residualPartialState.OperationCost = 0
        $residualPartialState.OperationProtocolVersion = 64
        $residualPartialState.OperationRefundGeneration = 2
        $residualPartialState.OperationRefundAttemptKey = "stale.refund.2"
        $residualPartialState.OperationRefundRetryConsumed = $true
        $residualPartialState.OperationAccountingAttemptKey = "stale.accounting.1"
        $residualPartialState.OperationAccountingAccount = "skillTrainingSystem"
        $residualPartialState.OperationAccountingOutcome = "SUCCESS"
        $residualPartialState.OperationMarkerComplete = $false
        $residualPartialState.OperationPreimageMatches = $true
        $residualPartialCalls = [pscustomobject]@{ Probe = 0; Read = 0; Write = 0 }
        Assert-OfflineThrows -Name "resolve-residual-partial-provenance" -Action {
            $null = Resolve-TrackedOperationForCleanup `
                -Lifecycle $residualPartialLifecycle `
                -State $residualPartialState `
                -ReservedProbeInvoker { param($command) $residualPartialCalls.Probe++; throw "residual partial reached clear RPC" } `
                -ReservedStateReader { $residualPartialCalls.Read++; throw "residual partial reached state refresh" } `
                -ReservedSnapshotWriter { param($snapshot) $residualPartialCalls.Write++; throw "residual partial reached snapshot write" }
        }
        if ($residualPartialCalls.Probe -ne 0 -or $residualPartialCalls.Read -ne 0 -or
            $residualPartialCalls.Write -ne 0 -or $null -eq $residualPartialLifecycle.operation)
        {
            throw "Residual partial provenance crossed a Resolve mutation boundary."
        }
        $reservedDrift = Copy-OfflineObject -Value $reservedState; $reservedDrift.Xp = 1
        Assert-OfflineThrows -Name "reserved-drift" -Action { $null = Assert-ReservedOperationClearable -Lifecycle $reservedLifecycle -State $reservedDrift }
        Assert-OfflineThrows -Name "checkpointed-reserved-drift" -Action { $null = Assert-ReservedOperationClearable -Lifecycle $checkpointedReservedLifecycle -State $reservedDrift }
        $fundLifecycle = Copy-OfflineObject -Value $reservedLifecycle
        $fundLifecycle.operation.state = "fundSucceeded"
        $fundLifecycle.operation.terminalAtUtc = [DateTime]::UtcNow.ToString("o")
        $fundState = Copy-OfflineObject -Value $reservedState
        $fundState.OperationState = "fundSucceeded"
        $fundState.Cash = [int]$before.Cash
        $fundState.Bank = [int]$before.Bank + $trainerCost
        $fundState.Credits = [int]$before.Credits + $trainerCost
        Confirm-TerminalOperationEffect -Lifecycle $fundLifecycle -State $fundState
        $zeroUpdatedFundState = Copy-OfflineObject -Value $fundState
        $zeroUpdatedFundState.OperationUpdated = 0
        Assert-OfflineThrows -Name "complete-marker-zero-updated-fund-terminal" -Action {
            Confirm-TerminalOperationEffect -Lifecycle $fundLifecycle -State $zeroUpdatedFundState
        }
        $wrongFundSplit = Copy-OfflineObject -Value $fundState
        $wrongFundSplit.Cash = [int]$wrongFundSplit.Cash + $trainerCost
        $wrongFundSplit.Bank = [int]$wrongFundSplit.Bank - $trainerCost
        Assert-OfflineThrows -Name "fund-bank-only-split" -Action { Confirm-TerminalOperationEffect -Lifecycle $fundLifecycle -State $wrongFundSplit }

        $drainBefore = Copy-OfflineObject -Value $before
        $drainBefore.Bank = $trainerCost; $drainBefore.Credits = $trainerCost
        $drainLifecycle = Copy-OfflineObject -Value $reservedLifecycle
        $drainLifecycle.operation.kind = "drain"; $drainLifecycle.operation.state = "drainSucceeded"
        $drainLifecycle.operation.before = New-StateSnapshot -State $drainBefore
        $drainLifecycle.operation.terminalAtUtc = [DateTime]::UtcNow.ToString("o")
        $drainState = Copy-OfflineObject -Value $drainBefore
        $drainState.OperationAttemptId = $operationId; $drainState.OperationId = $operationId
        $drainState.OperationKind = "drain"; $drainState.OperationState = "drainSucceeded"
        $drainState.OperationLifecycleId = $lifecycle.lifecycleId
        $drainState.OperationTrainerOid = "none"; $drainState.OperationSkillName = "none"
        $drainState.OperationUpdated = 1; $drainState.OperationCost = $trainerCost; $drainState.OperationProtocolVersion = 64
        $drainState.OperationMarkerComplete = $true
        $drainState.Bank = 0; $drainState.Credits = 0
        Confirm-TerminalOperationEffect -Lifecycle $drainLifecycle -State $drainState
        $zeroUpdatedDrainState = Copy-OfflineObject -Value $drainState
        $zeroUpdatedDrainState.OperationUpdated = 0
        Assert-OfflineThrows -Name "complete-marker-zero-updated-drain-terminal" -Action {
            Confirm-TerminalOperationEffect -Lifecycle $drainLifecycle -State $zeroUpdatedDrainState
        }
        $wrongDrainSplit = Copy-OfflineObject -Value $drainState
        $wrongDrainSplit.Cash = 1; $wrongDrainSplit.Bank = -1
        Assert-OfflineThrows -Name "drain-bank-only-split" -Action { Confirm-TerminalOperationEffect -Lifecycle $drainLifecycle -State $wrongDrainSplit }
        Write-Host "[PASS] reserved-recovery"

        $checkpointLifecycle = Copy-OfflineObject -Value $reservedLifecycle
        $checkpointLifecycle.operation.state = "checkpointed"
        if ((Assert-UnqueuedOperationDiscardable -Lifecycle $checkpointLifecycle -State $before) -cne "discardCheckpoint") { throw "Checkpoint decision drifted." }
        foreach ($ambiguousState in @("enqueueing", "queued"))
        {
            $checkpointLifecycle.operation.state = $ambiguousState
            $reservedState.OperationState = $ambiguousState
            if (-not [string]::IsNullOrEmpty((Get-ConservativeReconcileTarget -Lifecycle $checkpointLifecycle -State $reservedState)))
            {
                throw "Absent $ambiguousState effect was unsafely inferred terminal."
            }
        }
        $recoveredLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $recoveredLifecycle.phase = "cleanupPending"
        $recoveredLifecycle.cleanup = [pscustomobject]@{ origin = "purchasePending"; startedAtUtc = [DateTime]::UtcNow.ToString("o"); stage = "starting" }
        $recoveredLifecycle.operation.state = "purchaseApplying"
        $recoveryState = New-OfflinePurchaseCrashState -Lifecycle $recoveredLifecycle -OperationState "purchaseApplying" -Vector "HELD" -ChangedProcess
        if ((Get-ConservativeReconcileTarget -Lifecycle $recoveredLifecycle -State $recoveryState) -cne "resumePurchaseAccounting")
        {
            throw "Exact changed-process HELD effect did not select accounting resume."
        }
        $wrongSplitRecovery = Copy-OfflineObject -Value $recoveryState
        $wrongSplitRecovery.Cash = [int]$wrongSplitRecovery.Cash + 1
        $wrongSplitRecovery.Bank = [int]$wrongSplitRecovery.Bank - 1
        if (-not [string]::IsNullOrEmpty((Get-ConservativeReconcileTarget -Lifecycle $recoveredLifecycle -State $wrongSplitRecovery)))
        {
            throw "Compensating cash/bank drift was unsafely reconciled from total credits."
        }
        $recoveredLifecycle.operation.recovery = [pscustomobject]@{ source = "restartAccountingResume"; serverProcessToken = $recoveryState.ServerProcessToken; recoveredAtUtc = [DateTime]::UtcNow.ToString("o") }
        $recoveredLifecycle.operation.reconcileTarget = ""
        $recoveryState = New-PurchaseSuccessCandidate -Lifecycle $recoveredLifecycle -State $recoveryState
        Set-TrackedOperationFromState -Lifecycle $recoveredLifecycle -State $recoveryState
        $recoveredLifecycle.purchaseEvidence = New-PurchaseEvidence -Lifecycle $recoveredLifecycle -State $recoveryState -OutcomeSource "restartAccountingResume"
        $recoveredLifecycle.held = New-StateSnapshot -State $recoveryState
        $recoveredLifecycle.cleanup.stage = "recoveredHeld"
        Assert-LifecycleSnapshot -Lifecycle $recoveredLifecycle -CurrentIdentity $identity
        $recoveredLifecycle = Copy-OfflineObject -Value $recoveredLifecycle
        Assert-LifecycleSnapshot -Lifecycle $recoveredLifecycle -CurrentIdentity $identity

        $recoveredSurrendered = Copy-OfflineObject -Value $recoveredLifecycle.held
        $recoveredSurrendered.HasSkill = $false; $recoveredSurrendered.HasCommand = $false; $recoveredSurrendered.HasSchematic = $false
        $recoveredSurrendered.Points = $recoveredLifecycle.prepared.Points
        $recoveredSurrendered.Cap = $recoveredLifecycle.prepared.Cap
        $recoveredSurrendered.SkillModValue = $recoveredLifecycle.prepared.SkillModValue
        foreach ($name in @("VectorCommandsOwned", "VectorCommandsExpected", "VectorModsMatched", "VectorModsExpected", "VectorSchematicsOwned", "VectorSchematicsExpected", "VectorComplete", "VectorCommands", "VectorMods", "VectorSchematics"))
        {
            $recoveredSurrendered.$name = $recoveredLifecycle.prepared.$name
        }
        $recoveredSurrendered.OperationAttemptId = "none"; $recoveredSurrendered.OperationId = "none"
        $recoveredSurrendered.OperationKind = "none"; $recoveredSurrendered.OperationState = "none"; $recoveredSurrendered.OperationUpdated = 0
        $recoveredSurrendered.OperationLifecycleId = "none"; $recoveredSurrendered.OperationTrainerOid = "none"; $recoveredSurrendered.OperationSkillName = "none"
        $recoveredSurrendered.OperationCost = 0; $recoveredSurrendered.OperationProtocolVersion = 0
        $recoveredSurrendered.OperationRefundGeneration = 0; $recoveredSurrendered.OperationRefundAttemptKey = "none"; $recoveredSurrendered.OperationRefundRetryConsumed = $false
        $recoveredSurrendered.OperationAccountingAttemptKey = "none"; $recoveredSurrendered.OperationAccountingAccount = "none"; $recoveredSurrendered.OperationAccountingOutcome = "none"
        $recoveredSurrendered.OperationMarkerComplete = $false; $recoveredSurrendered.OperationPreimageMatches = $false
        Assert-SurrenderRelation -Lifecycle $recoveredLifecycle -Surrendered $recoveredSurrendered
        $recoveredLifecycle.surrendered = New-StateSnapshot -State $recoveredSurrendered
        $recoveredLifecycle.operation = $null
        $recoveredLifecycle.cleanup.stage = "releasePending"
        foreach ($name in @("cleanupXp", "cleanupCredits", "cleanupNovice", "boundaryMarkers")) { $recoveredLifecycle.setup.$name = "notNeeded" }
        $recoveredLifecycle.final = Copy-OfflineObject -Value $recoveredLifecycle.baseline
        $recoveredLifecycle.phase = "cleaned"
        Assert-LifecycleSnapshot -Lifecycle $recoveredLifecycle -CurrentIdentity $identity
        $recoveredLifecycle = Copy-OfflineObject -Value $recoveredLifecycle
        Assert-LifecycleSnapshot -Lifecycle $recoveredLifecycle -CurrentIdentity $identity
        Write-Host "[PASS] ambiguous-enqueueing-queued-fail-closed"

        $callbackState = Copy-OfflineObject -Value $reservedState
        $callbackState.OperationState = "fundSucceeded"
        if ((Get-PostDispatchCheckpointState -State $callbackState) -cne "fundSucceeded" -or
            (Get-PostDispatchCheckpointState -State $reservedState) -cne [string]$reservedState.OperationState)
        {
            throw "Post-dispatch checkpoint would downgrade a synchronous terminal callback."
        }
        $callbackId = "99999999999999999999999999999999"
        $callbackLifecycle = $lifecycle.lifecycleId
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "enqueueing" @("enqueueing")) -cne "apply") { throw "Exact payment request was quarantined." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentDispatching" @("enqueueing")) -cne "quarantine") { throw "Duplicate payment request escaped its one-shot state." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentDispatching" @()) -cne "quarantine") { throw "Impossible tagged pay-deposit stage was not quarantined." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentDispatching" @("paymentDispatching")) -cne "apply") { throw "Exact pay-pass stage was quarantined." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentSucceededCallback" @("paymentDispatching")) -cne "quarantine") { throw "Duplicate pay-pass escaped its one-shot state." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "enqueueing" @("enqueueing", "paymentDispatching")) -cne "apply") { throw "Exact direct-NSF pay-fail alternate was quarantined." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentFailedCallback" @("enqueueing", "paymentDispatching")) -cne "quarantine") { throw "Duplicate pay-fail escaped its one-shot state." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentSucceededCallback" @("paymentSucceededCallback")) -cne "apply") { throw "Exact trainer success callback was quarantined." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "purchaseApplying" @("paymentSucceededCallback")) -cne "quarantine") { throw "Duplicate trainer callback escaped its one-shot state." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentSucceededCallback" @("paymentSucceededCallback") -PreimageComplete $false) -cne "quarantine") { throw "Trainer callback missing a durable preimage leaf escaped quarantine." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentSucceededCallback" @("paymentSucceededCallback") -PreimageLifecycleExact $false) -cne "quarantine") { throw "Trainer callback with lifecycle/preimage drift escaped quarantine." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentSucceededCallback" @("paymentSucceededCallback") -AuthoritativeBalancesExact $false) -cne "quarantine") { throw "Inter-handler trainer callback balance drift escaped quarantine." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentSucceededCallback" @("paymentSucceededCallback") -AuthoritativeGameplayExact $false) -cne "quarantine") { throw "Inter-handler trainer callback gameplay drift escaped quarantine." }
        if ((Get-OfflinePhaseACallbackDecision $callbackId $callbackId "purchase" "purchase" $callbackLifecycle $callbackLifecycle "paymentFailedCallback" @("paymentFailedCallback") -AuthoritativeBalancesExact $false) -cne "quarantine") { throw "Failed-payment callback with a debit escaped quarantine." }
        foreach ($case in @(
            @("partial-id", "", "purchase", $callbackLifecycle, "paymentSucceededCallback"),
            @("stale-id", "88888888888888888888888888888888", "purchase", $callbackLifecycle, "paymentSucceededCallback"),
            @("stale-kind", $callbackId, "fund", $callbackLifecycle, "paymentSucceededCallback"),
            @("stale-lifecycle", $callbackId, "purchase", "77777777777777777777777777777777", "paymentSucceededCallback"),
            @("terminal-replay", $callbackId, "purchase", $callbackLifecycle, "purchaseSucceeded"),
            @("refund-transition-replay", $callbackId, "purchase", $callbackLifecycle, "refundRecoveryFailed")))
        {
            if ((Get-OfflinePhaseACallbackDecision $callbackId ([string]$case[1]) "purchase" ([string]$case[2]) $callbackLifecycle ([string]$case[3]) ([string]$case[4]) @("paymentSucceededCallback")) -cne "quarantine")
            {
                throw "Tagged callback case '$($case[0])' escaped quarantine."
            }
        }

        $crashLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        foreach ($stateName in @("paymentDispatching", "paymentSucceededCallback", "purchaseApplying"))
        {
            $debitCrash = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState $stateName -Vector "DEBIT" -ChangedProcess
            if ((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $debitCrash) -cne "requeuePurchaseCallback")
            {
                throw "Changed-process $stateName + DEBIT did not select the exact trainer callback replay."
            }
        }
        $sameProcessDebit = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "paymentSucceededCallback" -Vector "DEBIT"
        if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $sameProcessDebit)))
        {
            throw "Same-process callback state was unsafely inferred recoverable."
        }
        $ambiguousPayment = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "paymentDispatching" -Vector "PRE" -ChangedProcess
        if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $ambiguousPayment)))
        {
            throw "Changed-process paymentDispatching + PRE escaped ambiguity quarantine."
        }
        $heldCrash = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "purchaseApplying" -Vector "HELD" -ChangedProcess
        if ((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $heldCrash) -cne "resumePurchaseAccounting")
        {
            throw "purchaseApplying + HELD did not retain accounting-resume precedence."
        }
        $accountingRequested = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "accountingRequested" -Vector "HELD" -ChangedProcess
        if ((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $accountingRequested) -cne "resumePurchaseAccounting")
        {
            throw "Durable accountingRequested + HELD was not safely replayable."
        }
        $accountingInflight = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "accountingDispatching" -Vector "HELD" -ChangedProcess
        if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $accountingInflight)))
        {
            throw "Accounting dispatch with no callback outcome escaped ambiguity quarantine."
        }
        $accountingSuccessCut = Copy-OfflineObject -Value $accountingInflight
        $accountingSuccessCut.OperationAccountingOutcome = "SUCCESS"
        if ((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $accountingSuccessCut) -cne "resumePurchaseAccounting")
        {
            throw "Durable accounting SUCCESS callback cut was not safely finalizable."
        }
        foreach ($failureCut in @(
                [pscustomobject]@{ State = "accountingRequested"; Outcome = "REQUEST_QUEUE_FAILED" },
                [pscustomobject]@{ State = "accountingDispatching"; Outcome = "QUEUE_FAILED" },
                [pscustomobject]@{ State = "accountingDispatching"; Outcome = "FAILED" },
                [pscustomobject]@{ State = "accountingPending"; Outcome = "FAILED" }))
        {
            $accountingFailureCut = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState ([string]$failureCut.State) -Vector "HELD" -ChangedProcess
            $accountingFailureCut.OperationAccountingOutcome = [string]$failureCut.Outcome
            Assert-StateShape -State $accountingFailureCut -Context "Accounting failure crash cut"
            if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $accountingFailureCut)))
            {
                throw "Accounting failure crash cut '$($failureCut.State)/$($failureCut.Outcome)' became recoverable."
            }
            $accountingFailureLifecycle = Copy-OfflineObject -Value $crashLifecycle
            Set-TrackedOperationFromState -Lifecycle $accountingFailureLifecycle -State $accountingFailureCut
            Assert-LifecycleSnapshot -Lifecycle $accountingFailureLifecycle -CurrentIdentity $identity
        }
        $invalidAccountingFailureCut = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "accountingRequested" -Vector "HELD" -ChangedProcess
        $invalidAccountingFailureCut.OperationAccountingOutcome = "FAILED"
        Assert-OfflineThrows -Name "accounting-requested-invalid-failure-cut" -Action {
            Assert-StateShape -State $invalidAccountingFailureCut -Context "Invalid accounting request failure cut"
        }
        $invalidAccountingFailureCut = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "accountingPending" -Vector "HELD" -ChangedProcess
        $invalidAccountingFailureCut.OperationAccountingOutcome = "REQUEST_QUEUE_FAILED"
        Assert-OfflineThrows -Name "accounting-pending-invalid-request-cut" -Action {
            Assert-StateShape -State $invalidAccountingFailureCut -Context "Invalid accounting pending request cut"
        }
        $invalidAccountingFailureCut.OperationAccountingOutcome = "QUEUE_FAILED"
        Assert-OfflineThrows -Name "accounting-pending-invalid-queue-cut" -Action {
            Assert-StateShape -State $invalidAccountingFailureCut -Context "Invalid accounting pending queue cut"
        }
        $partialGrant = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "purchaseApplying" -Vector "DEBIT" -ChangedProcess
        $partialGrant.HasSkill = $true
        if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $partialGrant)))
        {
            throw "Partial purchase grant was not quarantined."
        }
        $invalidLineage = Copy-OfflineObject -Value $crashLifecycle
        $invalidLineage.prepared.Xp = [int]$invalidLineage.prepared.Xp + 1
        $invalidLineage.operation.before.Xp = [int]$invalidLineage.operation.before.Xp + 1
        $internallyConsistent = New-OfflinePurchaseCrashState -Lifecycle $invalidLineage -OperationState "paymentSucceededCallback" -Vector "DEBIT" -ChangedProcess
        if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $invalidLineage -State $internallyConsistent)))
        {
            throw "Semantically invalid but internally consistent preimage escaped lifecycle quarantine."
        }

        foreach ($stateName in @(
                "refundInitialClaiming", "refundInitialDispatching", "refundInitialPending", "refundInitialFailed",
                "refundRecoveryClaiming", "refundRecoveryDispatching", "refundRecoveryPending", "refundRecoveryFailed"))
        {
            $refundCrash = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState $stateName -Vector "REFUND" -ChangedProcess
            if ((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $refundCrash) -cne "reconcileRefundOutcome")
            {
                throw "$stateName + REFUND did not reconcile without a second transfer."
            }
        }
        foreach ($stateName in @("refundInitialClaiming", "refundInitialFailed", "refundRecoveryClaiming"))
        {
            $refundDebit = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState $stateName -Vector "DEBIT" -ChangedProcess
            if ((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $refundDebit) -cne "retryPurchaseRefund")
            {
                throw "$stateName + DEBIT did not retain its exact generation-scoped dispatch claim."
            }
        }
        foreach ($stateName in @("refundInitialDispatching", "refundInitialPending", "refundRecoveryDispatching", "refundRecoveryPending", "refundRecoveryFailed"))
        {
            $ambiguousRefundDebit = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState $stateName -Vector "DEBIT" -ChangedProcess
            if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $ambiguousRefundDebit)))
            {
                throw "$stateName + DEBIT escaped one-shot refund ambiguity quarantine."
            }
        }
        $sameRecoveryProcess = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "paymentSucceededCallback" -Vector "DEBIT" -ChangedProcess
        $sameRecoveryProcessLifecycle = Copy-OfflineObject -Value $crashLifecycle
        $sameRecoveryProcessLifecycle.operation.recovery = [pscustomobject]@{
            source = "restartCallbackReplay"
            serverProcessToken = [string]$sameRecoveryProcess.ServerProcessToken
            recoveredAtUtc = [DateTime]::UtcNow.ToString("o")
        }
        if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $sameRecoveryProcessLifecycle -State $sameRecoveryProcess)))
        {
            throw "Same recovery-process callback state was unsafely inferred recoverable."
        }
        $completedRefundRetry = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "refundRecoveryPending" -Vector "REFUND" -ChangedProcess
        if ((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $completedRefundRetry) -cne "reconcileRefundOutcome")
        {
            throw "Completed refund retry was not terminalized from authoritative REFUND."
        }
        $refundDrift = New-OfflinePurchaseCrashState -Lifecycle $crashLifecycle -OperationState "refundInitialPending" -Vector "DEBIT" -ChangedProcess
        $refundDrift.Bank = [int]$refundDrift.Bank + 1
        if (-not [string]::IsNullOrEmpty((Get-PurchaseRecoveryDecision -Lifecycle $crashLifecycle -State $refundDrift)))
        {
            throw "Mismatched refund balance drift escaped quarantine."
        }

        # Exercise the same settlement planner and recovery orchestrator used by
        # Resolve-TrackedOperationForCleanup.  This makes the settled
        # refundInitialFailed -> retry path reachable through production control
        # flow rather than proving only its leaf decision function.
        $initialFailureLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $initialFailure = New-OfflinePurchaseCrashState -Lifecycle $initialFailureLifecycle -OperationState "refundInitialFailed" -Vector "DEBIT" -ChangedProcess
        $initialFailurePlan = Get-TrackedOperationSettlementPlan -Lifecycle $initialFailureLifecycle -State $initialFailure
        if ([string]$initialFailurePlan.action -cne "recover" -or
            [string]$initialFailurePlan.recoveryDecision -cne "retryPurchaseRefund")
        {
            throw "Settled generation-one refund failure was handled as terminal before its one-shot retry."
        }
        foreach ($refundStateName in @("refundInitialFailed", "refundRecoveryFailed"))
        {
            $refundProof = New-OfflinePurchaseCrashState -Lifecycle $initialFailureLifecycle -OperationState $refundStateName -Vector "REFUND" -ChangedProcess
            $refundPlan = Get-TrackedOperationSettlementPlan -Lifecycle $initialFailureLifecycle -State $refundProof
            if ([string]$refundPlan.action -cne "recover" -or
                [string]$refundPlan.recoveryDecision -cne "reconcileRefundOutcome")
            {
                throw "$refundStateName + REFUND was terminalized before authoritative reconciliation."
            }
        }
        $sameProcessInitialFailure = New-OfflinePurchaseCrashState -Lifecycle $initialFailureLifecycle -OperationState "refundInitialFailed" -Vector "DEBIT"
        if ([string](Get-TrackedOperationSettlementPlan -Lifecycle $initialFailureLifecycle -State $sameProcessInitialFailure).action -cne "terminal")
        {
            throw "Same-process settled refund failure was incorrectly replayed."
        }
        $recoveryFailureDebit = New-OfflinePurchaseCrashState -Lifecycle $initialFailureLifecycle -OperationState "refundRecoveryFailed" -Vector "DEBIT" -ChangedProcess
        if ([string](Get-TrackedOperationSettlementPlan -Lifecycle $initialFailureLifecycle -State $recoveryFailureDebit).action -cne "terminal")
        {
            throw "Generation-two refund failure attempted a forbidden third transfer."
        }
        foreach ($ambiguousStateName in @(
                "refundInitialDispatching", "refundInitialPending",
                "refundRecoveryDispatching", "refundRecoveryPending"))
        {
            $ambiguousInflight = New-OfflinePurchaseCrashState -Lifecycle $initialFailureLifecycle -OperationState $ambiguousStateName -Vector "DEBIT" -ChangedProcess
            if ([string](Get-TrackedOperationSettlementPlan -Lifecycle $initialFailureLifecycle -State $ambiguousInflight).action -cne "failClosed")
            {
                throw "Ambiguous in-flight refund '$ambiguousStateName' did not remain fail-closed."
            }
        }
        foreach ($nonClearable in @(
                "refundInitialFailed", "refundRecoveryFailed", "refundRecoveryClaiming",
                "refundRecoveryDispatching", "refundRecoveryPending",
                "accountingRequestQueueFailed", "accountingQueueFailed", "accountingFailed"))
        {
            if ($nonClearable -cin $clearableOperationStates)
            {
                throw "Recovery queue/failure/in-flight state '$nonClearable' became clearable."
            }
        }

        $retryTerminal = New-OfflinePurchaseCrashState -Lifecycle $initialFailureLifecycle -OperationState "refundRecoveryFailed" -Vector "DEBIT" -ChangedProcess
        $retryTerminal | Add-Member -NotePropertyName ProbeText -NotePropertyValue "offline raw Get-State diagnostic"
        $retrySnapshots = New-Object System.Collections.ArrayList
        $retryResult = Invoke-TrackedPurchaseRecovery `
            -Lifecycle $initialFailureLifecycle `
            -State $initialFailure `
            -Decision "retryPurchaseRefund" `
            -ProbeInvoker { param($command) [pscustomobject]@{ Text = $command; Values = @{ queued = "true" } } } `
            -StateReader { $retryTerminal } `
            -TerminalWaiter { param($id, $kind, $context) $retryTerminal } `
            -SnapshotWriter { param($snapshot) [void]$retrySnapshots.Add((Copy-OfflineObject -Value $snapshot)) }
        if ([string]$retryResult.decision -cne "retryPurchaseRefund" -or
            [string]$retryResult.state.OperationState -cne "refundRecoveryFailed" -or
            $retrySnapshots.Count -ne 2 -or
            [string]$retrySnapshots[0].operation.reconcileTarget -cne "retryPurchaseRefund" -or
            [string]$retrySnapshots[0].operation.recovery.source -cne "restartRefundRetry" -or
            [string]$retrySnapshots[1].operation.reconcileTarget -cne "" -or
            [int]$retrySnapshots[1].operation.refundGeneration -ne 2 -or
            -not [bool]$retrySnapshots[1].operation.refundRetryConsumed -or
            ($retrySnapshots[1] | ConvertTo-Json -Compress -Depth 20) -match '"ProbeText"')
        {
            throw "End-to-end generation-one failure -> generation-two retry checkpoints were not exact or retained raw ProbeText."
        }
        foreach ($snapshot in @($retrySnapshots))
        {
            $reload = $snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            Assert-LifecycleSnapshot -Lifecycle $reload -CurrentIdentity $identity
        }
        $newProcessInitialFailure = New-OfflinePurchaseCrashState -Lifecycle $retrySnapshots[0] -OperationState "refundInitialFailed" -Vector "DEBIT" -ChangedProcess
        $newProcessInitialFailure.ServerProcessToken = "00000000-0000-0000-0000-000000000010|50|110"
        $reusePlan = Get-TrackedOperationSettlementPlan -Lifecycle $retrySnapshots[0] -State $newProcessInitialFailure
        if ([string]$reusePlan.action -cne "terminal" -or
            -not [string]::IsNullOrEmpty([string]$reusePlan.recoveryDecision))
        {
            throw "Consumed generation-one refund retry was reusable after another restart."
        }

        $timeoutLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $timeoutInitialFailure = New-OfflinePurchaseCrashState -Lifecycle $timeoutLifecycle -OperationState "refundInitialFailed" -Vector "DEBIT" -ChangedProcess
        $timeoutLive = New-OfflinePurchaseCrashState -Lifecycle $timeoutLifecycle -OperationState "refundRecoveryPending" -Vector "DEBIT" -ChangedProcess
        $timeoutSnapshots = New-Object System.Collections.ArrayList
        $timeoutMessage = ""
        try
        {
            $null = Invoke-TrackedPurchaseRecovery `
                -Lifecycle $timeoutLifecycle `
                -State $timeoutInitialFailure `
                -Decision "retryPurchaseRefund" `
                -ProbeInvoker { param($command) [pscustomobject]@{ Text = $command; Values = @{ queued = "true" } } } `
                -StateReader { $timeoutLive } `
                -TerminalWaiter { param($id, $kind, $context) throw "offline retry wait timeout" } `
                -SnapshotWriter { param($snapshot) [void]$timeoutSnapshots.Add((Copy-OfflineObject -Value $snapshot)) }
        }
        catch
        {
            $timeoutMessage = $_.Exception.Message
        }
        if ($timeoutMessage -cnotmatch 'offline retry wait timeout' -or
            $timeoutSnapshots.Count -ne 2 -or
            [string]$timeoutLifecycle.operation.state -cne "refundRecoveryPending" -or
            [string]$timeoutLifecycle.operation.reconcileTarget -cne "" -or
            [string]$timeoutLifecycle.operation.recovery.source -cne "restartRefundRetry")
        {
            throw "Recovery wait timeout did not refresh/checkpoint generation-two live state before rethrow."
        }
        foreach ($snapshot in @($timeoutSnapshots))
        {
            $reload = $snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            Assert-LifecycleSnapshot -Lifecycle $reload -CurrentIdentity $identity
        }

        $invalidRefreshLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $invalidRefreshInitial = New-OfflinePurchaseCrashState -Lifecycle $invalidRefreshLifecycle -OperationState "refundInitialFailed" -Vector "DEBIT" -ChangedProcess
        $invalidRefreshLive = New-OfflinePurchaseCrashState -Lifecycle $invalidRefreshLifecycle -OperationState "refundRecoveryPending" -Vector "DEBIT" -ChangedProcess
        $invalidRefreshLive.OperationAccountingOutcome = "FAILED"
        $invalidRefreshSnapshots = New-Object System.Collections.ArrayList
        $invalidRefreshMessage = ""
        try
        {
            $null = Invoke-TrackedPurchaseRecovery `
                -Lifecycle $invalidRefreshLifecycle `
                -State $invalidRefreshInitial `
                -Decision "retryPurchaseRefund" `
                -ProbeInvoker { param($command) [pscustomobject]@{ Text = $command; Values = @{ queued = "true" } } } `
                -StateReader { $invalidRefreshLive } `
                -TerminalWaiter { param($id, $kind, $context) throw "offline invalid-refresh timeout" } `
                -SnapshotWriter { param($snapshot) [void]$invalidRefreshSnapshots.Add((Copy-OfflineObject -Value $snapshot)) }
        }
        catch
        {
            $invalidRefreshMessage = $_.Exception.Message
        }
        if ($invalidRefreshMessage -cnotmatch 'offline invalid-refresh timeout' -or
            $invalidRefreshSnapshots.Count -ne 1 -or
            [string]$invalidRefreshLifecycle.operation.state -cne "refundInitialFailed" -or
            [string]$invalidRefreshLifecycle.operation.reconcileTarget -cne "retryPurchaseRefund" -or
            [string]$invalidRefreshLifecycle.operation.recovery.source -cne "restartRefundRetry")
        {
            throw "Invalid authoritative refresh did not preserve the last valid recovery intent."
        }
        Assert-LifecycleSnapshot -Lifecycle $invalidRefreshLifecycle -CurrentIdentity $identity
        if (($invalidRefreshLifecycle | ConvertTo-Json -Compress -Depth 20) -cne
            ($invalidRefreshSnapshots[0] | ConvertTo-Json -Compress -Depth 20))
        {
            throw "Rejected post-action synchronization mutated the checkpointed recovery intent."
        }

        $accountingLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $accountingSuccessCut = New-OfflinePurchaseCrashState -Lifecycle $accountingLifecycle -OperationState "accountingPending" -Vector "HELD" -ChangedProcess
        $accountingSuccessCut.OperationAccountingOutcome = "SUCCESS"
        $accountingPlan = Get-TrackedOperationSettlementPlan -Lifecycle $accountingLifecycle -State $accountingSuccessCut
        if ([string]$accountingPlan.action -cne "recover" -or
            [string]$accountingPlan.recoveryDecision -cne "resumePurchaseAccounting")
        {
            throw "Durable accounting SUCCESS cut did not enter the production resume orchestrator."
        }
        $accountingTerminal = New-OfflinePurchaseCrashState -Lifecycle $accountingLifecycle -OperationState "purchaseSucceeded" -Vector "HELD" -ChangedProcess
        $accountingSnapshots = New-Object System.Collections.ArrayList
        $accountingResult = Invoke-TrackedPurchaseRecovery `
            -Lifecycle $accountingLifecycle `
            -State $accountingSuccessCut `
            -Decision "resumePurchaseAccounting" `
            -ProbeInvoker { param($command) [pscustomobject]@{ Text = $command; Values = @{ transferRetried = "false"; reconciled = "true" } } } `
            -StateReader { $accountingTerminal } `
            -TerminalWaiter { param($id, $kind, $context) throw "accounting waiter must not run for reconciled SUCCESS" } `
            -SnapshotWriter { param($snapshot) [void]$accountingSnapshots.Add((Copy-OfflineObject -Value $snapshot)) }
        if ([string]$accountingResult.state.OperationState -cne "purchaseSucceeded" -or
            $accountingSnapshots.Count -ne 2 -or
            [string]$accountingSnapshots[0].operation.reconcileTarget -cne "resumePurchaseAccounting" -or
            [string]$accountingSnapshots[1].operation.reconcileTarget -cne "" -or
            [string]$accountingSnapshots[1].operation.recovery.source -cne "restartAccountingResume" -or
            [string]$accountingSnapshots[1].operation.accountingOutcome -cne "SUCCESS")
        {
            throw "Accounting resume did not terminalize only the durable SUCCESS outcome."
        }
        foreach ($snapshot in @($accountingSnapshots))
        {
            $reload = $snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            Assert-LifecycleSnapshot -Lifecycle $reload -CurrentIdentity $identity
        }
        $accountingAmbiguousLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $accountingAmbiguous = New-OfflinePurchaseCrashState -Lifecycle $accountingAmbiguousLifecycle -OperationState "accountingPending" -Vector "HELD" -ChangedProcess
        if ([string](Get-TrackedOperationSettlementPlan -Lifecycle $accountingAmbiguousLifecycle -State $accountingAmbiguous).action -cne "failClosed")
        {
            throw "Accounting pending without SUCCESS was allowed into resume orchestration."
        }

        $callbackLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $callbackCut = New-OfflinePurchaseCrashState -Lifecycle $callbackLifecycle -OperationState "paymentSucceededCallback" -Vector "DEBIT" -ChangedProcess
        $accountingCut = New-OfflinePurchaseCrashState -Lifecycle $callbackLifecycle -OperationState "accountingPending" -Vector "HELD" -ChangedProcess
        $callbackSnapshots = New-Object System.Collections.ArrayList
        $callbackMessage = ""
        try
        {
            $null = Invoke-TrackedPurchaseRecovery `
                -Lifecycle $callbackLifecycle `
                -State $callbackCut `
                -Decision "requeuePurchaseCallback" `
                -ProbeInvoker { param($command) throw "offline callback RPC exception" } `
                -StateReader { $accountingCut } `
                -TerminalWaiter { param($id, $kind, $context) throw "terminal waiter must not run" } `
                -SnapshotWriter { param($snapshot) [void]$callbackSnapshots.Add((Copy-OfflineObject -Value $snapshot)) }
        }
        catch
        {
            $callbackMessage = $_.Exception.Message
        }
        if ($callbackMessage -cnotmatch 'offline callback RPC exception' -or
            $callbackSnapshots.Count -ne 2 -or
            [string]$callbackLifecycle.operation.state -cne "accountingPending" -or
            [string]$callbackLifecycle.operation.reconcileTarget -cne "" -or
            [string]$callbackLifecycle.operation.recovery.source -cne "restartCallbackReplay")
        {
            throw "Callback RPC exception did not checkpoint its advanced accounting cut before rethrow."
        }
        foreach ($snapshot in @($callbackSnapshots))
        {
            $reload = $snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            Assert-LifecycleSnapshot -Lifecycle $reload -CurrentIdentity $identity
        }

        # Historical recovery provenance must survive every reachable advanced
        # state and a real JSON reload without manufacturing an invalid pair.
        $callbackIntent = $callbackSnapshots[0]
        foreach ($advancedStateName in @(
                "paymentDispatching", "paymentSucceededCallback", "purchaseApplying",
                "accountingRequested", "accountingRequestQueueFailed", "accountingDispatching",
                "accountingPending", "accountingQueueFailed", "accountingFailed",
                "accountingSucceededCallback", "purchaseSucceeded",
                "refundInitialClaiming", "refundInitialDispatching", "refundInitialPending",
                "refundInitialFailed", "purchaseRefunded"))
        {
            $advancedVector = if ($advancedStateName -ceq "purchaseRefunded") { "REFUND" } elseif ($advancedStateName -like 'refund*') { "DEBIT" } else { "HELD" }
            $advancedState = New-OfflinePurchaseCrashState -Lifecycle $callbackIntent -OperationState $advancedStateName -Vector $advancedVector -ChangedProcess
            $advancedCandidate = New-ValidatedTrackedOperationStateCandidate -Lifecycle $callbackIntent -State $advancedState -ReconcileTarget ""
            $advancedReload = $advancedCandidate | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            Assert-LifecycleSnapshot -Lifecycle $advancedReload -CurrentIdentity $identity
        }
        $retryIntent = $retrySnapshots[0]
        foreach ($advancedStateName in @(
                "refundInitialClaiming", "refundInitialDispatching", "refundInitialPending",
                "refundInitialFailed", "refundRecoveryClaiming", "refundRecoveryDispatching",
                "refundRecoveryPending", "refundRecoveryFailed", "purchaseRefunded"))
        {
            $advancedVector = if ($advancedStateName -ceq "purchaseRefunded") { "REFUND" } else { "DEBIT" }
            $advancedState = New-OfflinePurchaseCrashState -Lifecycle $retryIntent -OperationState $advancedStateName -Vector $advancedVector -ChangedProcess
            if ($advancedStateName -ceq "purchaseRefunded")
            {
                $advancedState.OperationRefundGeneration = 2
                $advancedState.OperationRefundAttemptKey = "$($retryIntent.operation.id).refund.2"
                $advancedState.OperationRefundRetryConsumed = $true
            }
            $advancedCandidate = New-ValidatedTrackedOperationStateCandidate -Lifecycle $retryIntent -State $advancedState -ReconcileTarget ""
            $advancedReload = $advancedCandidate | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            Assert-LifecycleSnapshot -Lifecycle $advancedReload -CurrentIdentity $identity
        }

        $illegalActiveCallbackState = New-OfflinePurchaseCrashState -Lifecycle $callbackIntent -OperationState "accountingRequested" -Vector "HELD" -ChangedProcess
        Assert-OfflineThrows -Name "callback-active-target-advanced-state" -Action {
            $null = New-ValidatedTrackedOperationStateCandidate `
                -Lifecycle $callbackIntent `
                -State $illegalActiveCallbackState `
                -ReconcileTarget "requeuePurchaseCallback"
        }
        foreach ($illegalRetryStateName in @("refundInitialDispatching", "refundInitialPending", "refundRecoveryDispatching", "refundRecoveryPending"))
        {
            $illegalActiveRetryState = New-OfflinePurchaseCrashState -Lifecycle $retryIntent -OperationState $illegalRetryStateName -Vector "DEBIT" -ChangedProcess
            Assert-OfflineThrows -Name "retry-active-target-$illegalRetryStateName" -Action {
                $null = New-ValidatedTrackedOperationStateCandidate `
                    -Lifecycle $retryIntent `
                    -State $illegalActiveRetryState `
                    -ReconcileTarget "retryPurchaseRefund"
            }
        }
        $invalidRecoveryAttemptKey = New-OfflinePurchaseCrashState -Lifecycle $retryIntent -OperationState "refundRecoveryClaiming" -Vector "DEBIT" -ChangedProcess
        $invalidRecoveryAttemptKey.OperationRefundAttemptKey = "$($retryIntent.operation.id).refund.1"
        Assert-OfflineThrows -Name "recovery-generation-attempt-key" -Action {
            $null = New-ValidatedTrackedOperationStateCandidate -Lifecycle $retryIntent -State $invalidRecoveryAttemptKey
        }
        $invalidRecoveryConsumed = New-OfflinePurchaseCrashState -Lifecycle $retryIntent -OperationState "refundRecoveryClaiming" -Vector "DEBIT" -ChangedProcess
        $invalidRecoveryConsumed.OperationRefundRetryConsumed = $false
        Assert-OfflineThrows -Name "recovery-generation-consumed-flag" -Action {
            $null = New-ValidatedTrackedOperationStateCandidate -Lifecycle $retryIntent -State $invalidRecoveryConsumed
        }

        $immutableLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $immutableTerminal = New-OfflinePurchaseCrashState -Lifecycle $immutableLifecycle -OperationState "purchaseRejected" -Vector "PRE" -ChangedProcess
        $immutableTerminal | Add-Member -NotePropertyName ProbeText -NotePropertyValue "offline raw mismatched terminal marker"
        $immutableCandidate = New-ValidatedTrackedOperationStateCandidate -Lifecycle $immutableLifecycle -State $immutableTerminal
        $immutableLifecycle.operation = $immutableCandidate.operation
        foreach ($immutableDrift in @(
                [pscustomobject]@{ Name = "OperationTrainerOid"; Value = "999999" },
                [pscustomobject]@{ Name = "OperationSkillName"; Value = "wrong_skill" },
                [pscustomobject]@{ Name = "OperationCost"; Value = ($trainerCost + 1) },
                [pscustomobject]@{ Name = "OperationProtocolVersion"; Value = 65 }))
        {
            $driftedTerminal = Copy-OfflineObject -Value $immutableTerminal
            $driftedTerminal.([string]$immutableDrift.Name) = $immutableDrift.Value
            $driftedTerminal | Add-Member -NotePropertyName ProbeText -NotePropertyValue "offline raw immutable drift" -Force
            Assert-OfflineThrows -Name "immutable-sync-$($immutableDrift.Name)" -Action {
                $null = New-ValidatedTrackedOperationStateCandidate -Lifecycle $immutableLifecycle -State $driftedTerminal
            }
            Assert-OfflineThrows -Name "immutable-terminal-$($immutableDrift.Name)" -Action {
                Confirm-TerminalOperationEffect -Lifecycle $immutableLifecycle -State $driftedTerminal
            }
        }

        $timestampLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $timestampTerminal = New-OfflineHeldState `
            -Lifecycle $timestampLifecycle `
            -Prepared $timestampLifecycle.prepared `
            -OperationId ([string]$timestampLifecycle.operation.id)
        $zeroUpdatedTerminal = Copy-OfflineObject -Value $timestampTerminal
        $zeroUpdatedTerminal.OperationUpdated = 0
        Assert-OfflineThrows -Name "complete-marker-zero-updated-shape" -Action {
            Assert-StateShape -State $zeroUpdatedTerminal -Context "offline zero-updated complete marker"
        }
        $beforeZeroUpdatedSync = $timestampLifecycle | ConvertTo-Json -Compress -Depth 20
        Assert-OfflineThrows -Name "complete-marker-zero-updated-sync" -Action {
            $null = New-ValidatedTrackedOperationStateCandidate `
                -Lifecycle $timestampLifecycle `
                -State $zeroUpdatedTerminal
        }
        $afterZeroUpdatedSync = $timestampLifecycle | ConvertTo-Json -Compress -Depth 20
        if ($beforeZeroUpdatedSync -cne $afterZeroUpdatedSync)
        {
            throw "Rejected zero-updated operation synchronization mutated the source lifecycle."
        }
        $timestampCandidate = New-ValidatedTrackedOperationStateCandidate `
            -Lifecycle $timestampLifecycle `
            -State $timestampTerminal
        $timestampLifecycle.operation = $timestampCandidate.operation
        $timestampHeldCandidate = New-ValidatedHeldLifecycleCandidate `
            -Lifecycle $timestampLifecycle `
            -HeldState $timestampTerminal `
            -CurrentIdentity $identity `
            -OutcomeSource "callback"
        Assert-LifecycleSnapshot -Lifecycle $timestampHeldCandidate -CurrentIdentity $identity
        Assert-OfflineThrows -Name "complete-marker-zero-updated-held-candidate" -Action {
            $null = New-ValidatedHeldLifecycleCandidate `
                -Lifecycle $timestampLifecycle `
                -HeldState $zeroUpdatedTerminal `
                -CurrentIdentity $identity `
                -OutcomeSource "callback"
        }
        Assert-OfflineThrows -Name "complete-marker-zero-updated-terminal" -Action {
            Confirm-TerminalOperationEffect -Lifecycle $timestampLifecycle -State $zeroUpdatedTerminal
        }

        $preClearLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $preClearLifecycle.phase = "cleanupPending"
        $preClearLifecycle.cleanup = [pscustomobject]@{
            origin = "purchasePending"
            startedAtUtc = [DateTime]::UtcNow.ToString("o")
            stage = "starting"
        }
        $preClearTerminal = New-OfflineHeldState `
            -Lifecycle $preClearLifecycle `
            -Prepared $preClearLifecycle.prepared `
            -OperationId ([string]$preClearLifecycle.operation.id)
        $preClearCandidate = New-ValidatedTrackedOperationStateCandidate -Lifecycle $preClearLifecycle -State $preClearTerminal
        $preClearLifecycle.operation = $preClearCandidate.operation
        Confirm-TerminalOperationEffect -Lifecycle $preClearLifecycle -State $preClearTerminal
        $preClearDurable = $preClearLifecycle | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        Assert-LifecycleSnapshot -Lifecycle $preClearDurable -CurrentIdentity $identity
        if ($null -eq $preClearDurable.purchaseEvidence -or $null -eq $preClearDurable.held)
        {
            throw "Pre-clear durable snapshot omitted synthesized purchase lineage."
        }
        $markerClearedAfterPreClear = Copy-OfflineObject -Value $preClearTerminal
        foreach ($name in @(
                "OperationAttemptId", "OperationId", "OperationKind", "OperationState",
                "OperationLifecycleId", "OperationTrainerOid", "OperationSkillName",
                "OperationRefundAttemptKey", "OperationAccountingAttemptKey",
                "OperationAccountingAccount", "OperationAccountingOutcome"))
        {
            $markerClearedAfterPreClear.$name = "none"
        }
        foreach ($name in @("OperationUpdated", "OperationCost", "OperationProtocolVersion", "OperationRefundGeneration"))
        {
            $markerClearedAfterPreClear.$name = 0
        }
        $markerClearedAfterPreClear.OperationRefundRetryConsumed = $false
        $markerClearedAfterPreClear.OperationMarkerComplete = $false
        $markerClearedAfterPreClear.OperationPreimageMatches = $false
        Confirm-TerminalOperationEffect -Lifecycle $preClearDurable -State $markerClearedAfterPreClear -MarkerAlreadyCleared

        $invalidSyncLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $invalidSyncState = New-OfflinePurchaseCrashState -Lifecycle $invalidSyncLifecycle -OperationState "refundInitialFailed" -Vector "DEBIT" -ChangedProcess
        $invalidSyncState.OperationAccountingOutcome = "FAILED"
        $beforeInvalidSync = $invalidSyncLifecycle | ConvertTo-Json -Compress -Depth 20
        Assert-OfflineThrows -Name "invalid-operation-sync-candidate" -Action {
            $null = New-ValidatedTrackedOperationStateCandidate -Lifecycle $invalidSyncLifecycle -State $invalidSyncState
        }
        $afterInvalidSync = $invalidSyncLifecycle | ConvertTo-Json -Compress -Depth 20
        if ($beforeInvalidSync -cne $afterInvalidSync)
        {
            throw "Rejected operation synchronization mutated the last valid lifecycle."
        }
        $invalidRecoveryToken = Copy-OfflineObject -Value $callbackSnapshots[1]
        $invalidRecoveryToken.operation.recovery.serverProcessToken = "garbage"
        Assert-OfflineThrows -Name "invalid-recovery-process-token" -Action {
            Assert-LifecycleSnapshot -Lifecycle $invalidRecoveryToken -CurrentIdentity $identity
        }
        Write-Host "[PASS] callback-before-queued-non-downgrade"

        $heldLifecycle = New-OfflineOriginLifecycle -Origin "held" -Identity $identity
        $badHeld = Copy-OfflineObject -Value $heldLifecycle.held
        $badHeld.Cap = 1999
        Assert-OfflineThrows -Name "held-cap" -Action { Assert-HeldRelation -Lifecycle $heldLifecycle -Held $badHeld }
        $badHeld = Copy-OfflineObject -Value $heldLifecycle.held
        $badHeld.RelogNoncePresent = $false
        Assert-OfflineThrows -Name "held-nonce" -Action { Assert-HeldRelation -Lifecycle $heldLifecycle -Held $badHeld }
        $wrongPreparedSplit = Copy-OfflineObject -Value $heldLifecycle
        $wrongPreparedSplit.prepared.Cash = [int]$wrongPreparedSplit.prepared.Cash + 1
        $wrongPreparedSplit.prepared.Bank = [int]$wrongPreparedSplit.prepared.Bank - 1
        Assert-OfflineThrows -Name "prepared-cash-bank-split" -Action { Assert-PreparedRelation -Lifecycle $wrongPreparedSplit }
        $badHeld = Copy-OfflineObject -Value $heldLifecycle.held
        $badHeld.Cash = [int]$badHeld.Cash + 1
        $badHeld.Bank = [int]$badHeld.Bank - 1
        Assert-OfflineThrows -Name "held-cash-bank-split" -Action { Assert-HeldRelation -Lifecycle $heldLifecycle -Held $badHeld }

        Confirm-TerminalOperationEffect -Lifecycle $heldLifecycle -State $heldLifecycle.held
        $markerPresentOperationDrift = Copy-OfflineObject -Value $heldLifecycle.held
        $markerPresentOperationDrift.OperationUpdated = [int]$markerPresentOperationDrift.OperationUpdated + 1
        Assert-OfflineThrows -Name "marker-present-operation-drift" -Action { Confirm-TerminalOperationEffect -Lifecycle $heldLifecycle -State $markerPresentOperationDrift }
        $markerClearedState = Copy-OfflineObject -Value $heldLifecycle.held
        $markerClearedState.OperationAttemptId = "none"; $markerClearedState.OperationId = "none"
        $markerClearedState.OperationKind = "none"; $markerClearedState.OperationState = "none"
        $markerClearedState.OperationUpdated = 0; $markerClearedState.OperationLifecycleId = "none"
        $markerClearedState.OperationTrainerOid = "none"; $markerClearedState.OperationSkillName = "none"
        $markerClearedState.OperationCost = 0; $markerClearedState.OperationProtocolVersion = 0
        $markerClearedState.OperationRefundGeneration = 0; $markerClearedState.OperationRefundAttemptKey = "none"; $markerClearedState.OperationRefundRetryConsumed = $false
        $markerClearedState.OperationAccountingAttemptKey = "none"; $markerClearedState.OperationAccountingAccount = "none"; $markerClearedState.OperationAccountingOutcome = "none"
        $markerClearedState.OperationMarkerComplete = $false
        $markerClearedState.OperationPreimageMatches = $false
        Confirm-TerminalOperationEffect -Lifecycle $heldLifecycle -State $markerClearedState -MarkerAlreadyCleared
        $markerClearedInstrumentation = Copy-OfflineObject -Value $markerClearedState
        $markerClearedInstrumentation.OperationAttemptId = [string]$heldLifecycle.operation.id
        Assert-OfflineThrows -Name "marker-cleared-instrumentation" -Action { Confirm-TerminalOperationEffect -Lifecycle $heldLifecycle -State $markerClearedInstrumentation -MarkerAlreadyCleared }
        $markerClearedDrift = Copy-OfflineObject -Value $markerClearedState
        $markerClearedDrift.Cash = [int]$markerClearedDrift.Cash + 1
        $markerClearedDrift.Credits = [int]$markerClearedDrift.Credits + 1
        Assert-OfflineThrows -Name "marker-cleared-gameplay-drift" -Action { Confirm-TerminalOperationEffect -Lifecycle $heldLifecycle -State $markerClearedDrift -MarkerAlreadyCleared }
        $markerClearedWrongLineage = Copy-OfflineObject -Value $heldLifecycle
        $markerClearedWrongLineage.purchaseEvidence.lifecycleId = "77777777777777777777777777777777"
        Assert-OfflineThrows -Name "marker-cleared-lineage" -Action { Confirm-TerminalOperationEffect -Lifecycle $markerClearedWrongLineage -State $markerClearedState -MarkerAlreadyCleared }

        $preparePrior = New-OfflineOriginLifecycle -Origin "preparing" -Identity $identity
        Assert-LifecycleSnapshot -Lifecycle $preparePrior -CurrentIdentity $identity
        $invalidPreparedCandidateState = New-OfflinePreparedState -Lifecycle $preparePrior
        $invalidPreparedCandidateState.Cash = [int]$invalidPreparedCandidateState.Cash + 1
        Assert-OfflineThrows -Name "prepare-candidate-assertion" -Action {
            $null = New-ValidatedPreparedLifecycleCandidate -Lifecycle $preparePrior -PreparedState $invalidPreparedCandidateState -CurrentIdentity $identity
        }
        if ($null -ne $preparePrior.prepared -or [string]$preparePrior.phase -cne "preparing")
        {
            throw "Prepare candidate assertion mutated the last valid lifecycle."
        }
        $prepareReload = New-ValidatedLastErrorLifecycleCandidate -Lifecycle $preparePrior -Message "offline prepare assertion" -CurrentIdentity $identity
        $prepareReload = Copy-OfflineObject -Value $prepareReload
        Assert-LifecycleSnapshot -Lifecycle $prepareReload -CurrentIdentity $identity
        if ($null -ne $prepareReload.prepared -or [string]$prepareReload.phase -cne "preparing")
        {
            throw "Prepare assertion catch did not preserve a reload-valid prior snapshot."
        }

        $purchasePrior = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $purchasePrior.operation.state = "purchaseSucceeded"
        $purchasePrior.operation.accountingAttemptKey = "$($purchasePrior.operation.id).accounting.1"
        $purchasePrior.operation.accountingAccount = "skillTrainingSystem"
        $purchasePrior.operation.accountingOutcome = "SUCCESS"
        $purchasePrior.operation.terminalAtUtc = [DateTime]::UtcNow.ToString("o")
        Assert-LifecycleSnapshot -Lifecycle $purchasePrior -CurrentIdentity $identity
        $invalidHeldCandidateState = New-OfflineHeldState -Lifecycle $purchasePrior -Prepared $purchasePrior.prepared -OperationId ([string]$purchasePrior.operation.id)
        $invalidHeldCandidateState.Cash = [int]$invalidHeldCandidateState.Cash + 1
        $invalidHeldCandidateState.Bank = [int]$invalidHeldCandidateState.Bank - 1
        Assert-OfflineThrows -Name "purchase-candidate-assertion" -Action {
            $null = New-ValidatedHeldLifecycleCandidate -Lifecycle $purchasePrior -HeldState $invalidHeldCandidateState -CurrentIdentity $identity -OutcomeSource "callback"
        }
        if ($null -ne $purchasePrior.purchaseEvidence -or $null -ne $purchasePrior.held -or
            [string]$purchasePrior.phase -cne "purchasePending")
        {
            throw "Purchase candidate assertion mutated the last valid lifecycle."
        }
        $purchaseReload = New-ValidatedLastErrorLifecycleCandidate -Lifecycle $purchasePrior -Message "offline purchase assertion" -CurrentIdentity $identity
        $purchaseReload = Copy-OfflineObject -Value $purchaseReload
        Assert-LifecycleSnapshot -Lifecycle $purchaseReload -CurrentIdentity $identity
        if ($null -ne $purchaseReload.purchaseEvidence -or $null -ne $purchaseReload.held -or
            [string]$purchaseReload.phase -cne "purchasePending")
        {
            throw "Purchase assertion catch did not preserve a reload-valid prior snapshot."
        }

        $refundLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $refundState = New-OfflinePurchaseCrashState -Lifecycle $refundLifecycle -OperationState "purchaseRefunded" -Vector "REFUND" -ChangedProcess
        Set-TrackedOperationFromState -Lifecycle $refundLifecycle -State $refundState
        Confirm-TerminalOperationEffect -Lifecycle $refundLifecycle -State $refundState
        $falseRefundSuccess = New-OfflinePurchaseCrashState -Lifecycle $refundLifecycle -OperationState "purchaseRefunded" -Vector "DEBIT" -ChangedProcess
        Assert-OfflineThrows -Name "refund-success-still-debited" -Action { Confirm-TerminalOperationEffect -Lifecycle $refundLifecycle -State $falseRefundSuccess }

        $refundFailureLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $refundFailureState = New-OfflinePurchaseCrashState -Lifecycle $refundFailureLifecycle -OperationState "refundRecoveryFailed" -Vector "DEBIT" -ChangedProcess
        Set-TrackedOperationFromState -Lifecycle $refundFailureLifecycle -State $refundFailureState
        Assert-ExactPurchaseDebitVector -Lifecycle $refundFailureLifecycle -State $refundFailureState
        Assert-OfflineThrows -Name "refund-failure-retains-intent" -Action { Confirm-TerminalOperationEffect -Lifecycle $refundFailureLifecycle -State $refundFailureState }
        $falseRefundFailure = New-OfflinePurchaseCrashState -Lifecycle $refundFailureLifecycle -OperationState "refundRecoveryFailed" -Vector "REFUND" -ChangedProcess
        Assert-OfflineThrows -Name "refund-failure-restored" -Action { Assert-ExactPurchaseDebitVector -Lifecycle $refundFailureLifecycle -State $falseRefundFailure }
        $refundGameplayDrift = Copy-OfflineObject -Value $refundFailureState
        $refundGameplayDrift.Points = [int]$refundGameplayDrift.Points - 1
        Assert-OfflineThrows -Name "refund-failure-gameplay-drift" -Action { Assert-ExactPurchaseDebitVector -Lifecycle $refundFailureLifecycle -State $refundGameplayDrift }

        $replayLifecycle = New-OfflineOriginLifecycle -Origin "purchasePending" -Identity $identity
        $replayHeld = New-OfflineHeldState -Lifecycle $replayLifecycle -Prepared $replayLifecycle.prepared -OperationId ([string]$replayLifecycle.operation.id)
        $replayHeld.ServerProcessToken = "00000000-0000-0000-0000-000000000009|49|109"
        $replayHeld.RelogNoncePresent = $true
        Set-TrackedOperationFromState -Lifecycle $replayLifecycle -State $replayHeld
        $replayLifecycle.operation.recovery = [pscustomobject]@{ source = "restartCallbackReplay"; serverProcessToken = $replayHeld.ServerProcessToken; recoveredAtUtc = [DateTime]::UtcNow.ToString("o") }
        $replayLifecycle.operation.reconcileTarget = ""
        $replayLifecycle.purchaseEvidence = New-PurchaseEvidence -Lifecycle $replayLifecycle -State $replayHeld -OutcomeSource "restartCallbackReplay"
        $replayLifecycle.held = New-StateSnapshot -State $replayHeld
        $replayLifecycle.phase = "held"
        Assert-LifecycleSnapshot -Lifecycle $replayLifecycle -CurrentIdentity $identity
        $sameTokenReplay = Copy-OfflineObject -Value $replayLifecycle
        $sameTokenReplay.purchaseEvidence.outcomeProcessToken = [string]$sameTokenReplay.purchaseEvidence.originProcessToken
        Assert-OfflineThrows -Name "replay-same-process-evidence" -Action { Assert-LifecycleSnapshot -Lifecycle $sameTokenReplay -CurrentIdentity $identity }
        $missingRelogReplay = Copy-OfflineObject -Value $replayLifecycle
        $missingRelogReplay.held.RelogNoncePresent = $false
        Assert-OfflineThrows -Name "replay-missing-relog" -Action { Assert-LifecycleSnapshot -Lifecycle $missingRelogReplay -CurrentIdentity $identity }
        Write-Host "[PASS] negative-held-relations"

        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("phase-a-lock-test-" + [guid]::NewGuid().ToString("N"))
        $null = New-Item -ItemType Directory -Path $tempRoot
        $firstLocks = $null
        $thirdLocks = $null
        try
        {
            Set-Variable -Name SnapshotPath -Scope Script -Value (Join-Path $tempRoot "one.json")
            $firstLocks = Enter-MutationLocks
            Set-Variable -Name SnapshotPath -Scope Script -Value (Join-Path $tempRoot "two.json")
            Assert-OfflineThrows -Name "player-lock-exclusion" -Action { $null = Enter-MutationLocks }
            Set-Variable -Name PlayerOid -Scope Script -Value "91002"
            Set-Variable -Name SnapshotPath -Scope Script -Value (Join-Path $tempRoot "one.json")
            Assert-OfflineThrows -Name "snapshot-lock-exclusion" -Action { $null = Enter-MutationLocks }
            # Failed snapshot acquisition must dispose the second player's first
            # lock; prove it can immediately acquire a different snapshot.
            Set-Variable -Name SnapshotPath -Scope Script -Value (Join-Path $tempRoot "three.json")
            $thirdLocks = Enter-MutationLocks
        }
        finally
        {
            Exit-MutationLocks -Locks $thirdLocks
            Exit-MutationLocks -Locks $firstLocks
            Set-Variable -Name PlayerOid -Scope Script -Value "91001"
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
        Write-Host "[PASS] lock-contention-two-snapshots-one-player"
        Write-Host "OFFLINE_TRANSITION_TESTS=PASS"
    }
    finally
    {
        if (-not [string]::IsNullOrWhiteSpace([string]$originalPlayerOid))
        {
            Set-Variable -Name PlayerOid -Scope Script -Value $originalPlayerOid
        }
        Set-Variable -Name SnapshotPath -Scope Script -Value $originalSnapshotPath
    }
}

$mutationLocks = $null
try
{
    if ($OfflineSelfTest)
    {
        Invoke-OfflineSelfTest
        exit 0
    }
    if ($Mode -cne "Observe") { $mutationLocks = Enter-MutationLocks }

    # Mutating modes hold both locks before this first authoritative observation.
    $observed = Get-State
    $executionIdentity = Get-ExecutionIdentity -State $observed
    Write-Host "[PASS] Fixture observation: $($observed.ProbeText)"

    if ($Mode -ceq "Observe")
    {
        $inspection = Invoke-Probe -Arguments "inspectTrainer $PlayerOid"
        Write-Host "[INFO] Trainer inspection: $($inspection.Text)"
        Write-Host "Observation-only trainer/persistence probe passed; no state was mutated."
        exit 0
    }

    if ($Mode -ceq "Prepare")
    {
        $resolvedSnapshotPath = Resolve-ExternalSnapshotPath
        if (Test-Path -LiteralPath $resolvedSnapshotPath) { throw "Refusing to overwrite an existing trainer lifecycle snapshot: $resolvedSnapshotPath" }
        if ([string]$observed.LifecycleMarkerState -cne "none" -or
            [string]$observed.LifecycleAttemptId -cne "none" -or
            [string]$observed.LifecycleId -cne "none")
        {
            throw "Fixture retains lifecycle instrumentation '$($observed.LifecycleMarkerState)/$($observed.LifecycleAttemptId)/$($observed.LifecycleId)'."
        }
        if ($observed.NewbieFreeTrainingRouteActive -or $observed.HasSkill -or $observed.HasCommand -or $observed.HasSchematic)
        {
            throw "Fixture is not a clean non-newbie Engineering baseline."
        }
        if ($observed.Xp -ne 0 -or $observed.Credits -ne 0) { throw "Trainer lifecycle requires zero XP and zero credits." }
        if ($observed.OperationAttemptId -cne "none" -or $observed.OperationId -cne "none" -or
            $observed.OperationMarkerComplete -or $observed.RelogNoncePresent -or $observed.RestartNoncePresent)
        {
            throw "Fixture retains prior trainer acceptance instrumentation."
        }
        $lifecycleId = [guid]::NewGuid().ToString("N")
        $lifecycle = [pscustomobject]@{
            schemaVersion = $snapshotSchemaVersion
            playerOid = $PlayerOid
            lifecycleId = $lifecycleId
            createdAtUtc = [DateTime]::UtcNow.ToString("o")
            phase = "lifecyclePending"
            identity = $executionIdentity
            setup = [pscustomobject]@{
                novice = $(if ($observed.HasNovice) { "notNeeded" } else { "pending" })
                xp = "notStarted"; funding = "notStarted"; cleanupXp = "notStarted"
                cleanupCredits = "notStarted"; cleanupNovice = "notStarted"; boundaryMarkers = "notStarted"
            }
            noviceAdded = (-not $observed.HasNovice)
            baseline = New-StateSnapshot -State $observed
            prepared = $null; conversation = $null; operation = $null; purchaseEvidence = $null; held = $null
            boundaries = [pscustomobject]@{ relog = $null; restart = $null }
            surrendered = $null; cleanup = $null; final = $null; lastError = $null
        }
        # Durable checkpoint precedes the first server mutation.
        Save-SnapshotAtomic -Snapshot $lifecycle
        try
        {
            $begun = Invoke-Probe -Arguments "beginLifecycle $PlayerOid $lifecycleId"
            Assert-Field -Result $begun -Name "established" -Expected "true"
            Assert-Field -Result $begun -Name "lifecycleMarkerState" -Expected "complete"
            $observed = Get-State
            Assert-CurrentLifecycleMarker -Lifecycle $lifecycle -State $observed
            if ([string]$observed.LifecycleMarkerState -cne "complete" -or
                [string]$observed.LifecycleAttemptId -cne $lifecycleId -or
                [string]$observed.LifecycleId -cne $lifecycleId -or
                -not $observed.LifecycleBaselineComplete)
            {
                throw "Lifecycle establishment response did not match the authoritative complete marker."
            }
            $lifecycle.phase = "preparing"
            Save-SnapshotAtomic -Snapshot $lifecycle

            if ([bool]$lifecycle.noviceAdded)
            {
                $grant = Invoke-Probe -Arguments "grant $PlayerOid $noviceSkill $lifecycleId"
                Assert-Field -Result $grant -Name "result" -Expected "true"
                $null = Wait-ForState -Context "novice setup" -Predicate { param($state) $state.HasNovice }
                $lifecycle.setup.novice = "complete"
                Save-SnapshotAtomic -Snapshot $lifecycle
            }
            $lifecycle.setup.xp = "pending"
            Save-SnapshotAtomic -Snapshot $lifecycle
            $xpSetup = Invoke-Probe -Arguments "grantXp $PlayerOid $xpType $xpCost $lifecycleId"
            Assert-Field -Result $xpSetup -Name "setup" -Expected "administrative"
            $fundBefore = Wait-ForState -Context "XP setup" -Predicate { param($state) $state.Xp -eq $xpCost }
            $lifecycle.setup.xp = "complete"
            $lifecycle.setup.funding = "pending"
            $lifecycle.operation = New-TrackedOperation -Kind "fund" -ServerProcessToken $fundBefore.ServerProcessToken -Before $fundBefore -LifecycleId $lifecycleId
            $lifecycle.phase = "fundingPending"
            Save-SnapshotAtomic -Snapshot $lifecycle
            $funding = Invoke-Probe -Arguments "fundTrainerCost $PlayerOid $($lifecycle.operation.id) $lifecycleId"
            Assert-Field -Result $funding -Name "queued" -Expected "true"
            $afterQueue = Get-State
            if ([string]$afterQueue.OperationAttemptId -cne [string]$lifecycle.operation.id -or
                [string]$afterQueue.OperationId -cne [string]$lifecycle.operation.id -or
                [string]$afterQueue.OperationKind -cne "fund" -or
                [string]$afterQueue.OperationLifecycleId -cne $lifecycleId -or
                -not $afterQueue.OperationMarkerComplete)
            {
                throw "Funding dispatch did not publish the exact authoritative operation record."
            }
            Set-TrackedOperationFromState -Lifecycle $lifecycle -State $afterQueue
            Save-SnapshotAtomic -Snapshot $lifecycle
            $funded = Wait-ForTerminalOperation -OperationId ([string]$lifecycle.operation.id) -OperationKind "fund" -Context "administrative trainer funding"
            Set-TrackedOperationFromState -Lifecycle $lifecycle -State $funded
            # The preparing origin permits both the terminal fund marker and its
            # post-clear null state, so every atomic checkpoint remains reloadable.
            $lifecycle.phase = "preparing"
            Save-SnapshotAtomic -Snapshot $lifecycle
            if ($funded.OperationState -cne "fundSucceeded") { throw "Trainer funding terminal failure '$($funded.OperationState)'." }
            Confirm-TerminalOperationEffect -Lifecycle $lifecycle -State $funded
            $prepared = Clear-TerminalOperation -Lifecycle $lifecycle -State $funded
            $lifecycle = New-ValidatedPreparedLifecycleCandidate `
                -Lifecycle $lifecycle `
                -PreparedState $prepared `
                -CurrentIdentity $executionIdentity
            Save-SnapshotAtomic -Snapshot $lifecycle
            Write-Host "[PASS] Exact XP/credit preparation checkpointed; snapshot=$resolvedSnapshotPath lifecycle=$lifecycleId"
        }
        catch
        {
            $lifecycle = New-ValidatedLastErrorLifecycleCandidate `
                -Lifecycle $lifecycle `
                -Message $_.Exception.Message `
                -CurrentIdentity $executionIdentity
            Save-SnapshotAtomic -Snapshot $lifecycle
            throw "Prepare stopped fail-closed with its recovery snapshot intact. Cause: $($_.Exception.Message)"
        }
        exit 0
    }

    $lifecycle = Get-Snapshot -CurrentIdentity $executionIdentity
    Assert-CurrentLifecycleMarker -Lifecycle $lifecycle -State $observed

    if ($Mode -ceq "Cleanup" -and [string]$lifecycle.phase -cin @("complete", "cleaned"))
    {
        Assert-TerminalCleanupNoOp -Lifecycle $lifecycle -State $observed
        Write-Host "[PASS] Terminal cleanup is an immutable no-op; no snapshot or server mutation was attempted."
        exit 0
    }

    if ($Mode -ceq "Conversation")
    {
        if ([string]$lifecycle.phase -cne "prepared") { throw "Conversation requires phase prepared." }
        Assert-StatePersistentEquals -Actual $observed -Expected $lifecycle.prepared -Context "Prepared fixture"
        $selectedTrainer = $TrainerOid
        if ([string]::IsNullOrWhiteSpace($selectedTrainer))
        {
            $found = Invoke-Probe -Arguments "findTrainer $PlayerOid"
            Assert-Field -Result $found -Name "trainerFound" -Expected "true"
            Assert-Field -Result $found -Name "fullyValidated" -Expected "true"
            $selectedTrainer = [string]$found.Values["trainerOid"]
        }
        $lifecycle.conversation = [pscustomobject]@{ trainerOid = $selectedTrainer; status = "pending"; queuedAtUtc = "" }
        $lifecycle.phase = "conversationPending"
        Save-SnapshotAtomic -Snapshot $lifecycle
        $conversation = Invoke-Probe -Arguments "queueTrainerConversation $PlayerOid $selectedTrainer $($lifecycle.lifecycleId)"
        Assert-Field -Result $conversation -Name "queued" -Expected "true"
        Assert-Field -Result $conversation -Name "purchaseMutation" -Expected "false"
        $lifecycle.conversation.status = "queued"
        $lifecycle.conversation.queuedAtUtc = [DateTime]::UtcNow.ToString("o")
        $lifecycle.phase = "conversationQueued"
        Save-SnapshotAtomic -Snapshot $lifecycle
        Write-Host "[PASS] Production trainer conversation queued for $selectedTrainer."
        exit 0
    }

    if ($Mode -ceq "Purchase")
    {
        if ([string]$lifecycle.phase -ceq "purchasePending")
        {
            if ($null -eq $lifecycle.operation -or
                [string]$observed.OperationAttemptId -cne [string]$lifecycle.operation.id -or
                [string]$observed.OperationId -cne [string]$lifecycle.operation.id -or
                [string]$observed.OperationKind -cne "purchase" -or
                [string]$observed.OperationLifecycleId -cne [string]$lifecycle.lifecycleId -or
                [string]$observed.OperationState -cne "purchaseSucceeded")
            {
                throw "Pending purchase is not the exact terminal correlated operation."
            }
            Set-TrackedOperationFromState -Lifecycle $lifecycle -State $observed
            $lifecycle = New-ValidatedHeldLifecycleCandidate `
                -Lifecycle $lifecycle `
                -HeldState $observed `
                -CurrentIdentity $executionIdentity `
                -OutcomeSource "callback"
            Save-SnapshotAtomic -Snapshot $lifecycle
            Write-Host "[PASS] Adopted the exact terminal trainer callback after interrupted probe parsing."
            exit 0
        }
        if ([string]$lifecycle.phase -cne "conversationQueued") { throw "Purchase requires conversationQueued." }
        Assert-StatePersistentEquals -Actual $observed -Expected $lifecycle.prepared -Context "Prepared purchase fixture"
        $selectedTrainer = [string]$lifecycle.conversation.trainerOid
        if (-not [string]::IsNullOrWhiteSpace($TrainerOid) -and $TrainerOid -cne $selectedTrainer) { throw "Trainer correlation mismatch." }
        $lifecycle.operation = New-TrackedOperation -Kind "purchase" -ServerProcessToken $observed.ServerProcessToken -Before $observed -LifecycleId ([string]$lifecycle.lifecycleId) -TrainerOid $selectedTrainer -SkillName $engineeringSkill
        $lifecycle.phase = "purchasePending"
        Save-SnapshotAtomic -Snapshot $lifecycle
        try
        {
            $purchase = Invoke-Probe -Arguments "trainerPurchase $PlayerOid $selectedTrainer $engineeringSkill $($lifecycle.operation.id) $($lifecycle.lifecycleId)"
            Assert-Field -Result $purchase -Name "path" -Expected "skillteacherPaymentHandler"
            Assert-Field -Result $purchase -Name "conversationUi" -Expected "false"
            Assert-Field -Result $purchase -Name "queued" -Expected "true"
            $afterQueue = Get-State
            if ([string]$afterQueue.OperationAttemptId -cne [string]$lifecycle.operation.id -or
                [string]$afterQueue.OperationId -cne [string]$lifecycle.operation.id -or
                [string]$afterQueue.OperationKind -cne "purchase" -or
                [string]$afterQueue.OperationLifecycleId -cne [string]$lifecycle.lifecycleId -or
                [string]$afterQueue.OperationTrainerOid -cne $selectedTrainer -or
                [string]$afterQueue.OperationSkillName -cne $engineeringSkill -or
                -not $afterQueue.OperationMarkerComplete)
            {
                throw "Purchase dispatch did not publish the exact authoritative trainer operation record."
            }
            Set-TrackedOperationFromState -Lifecycle $lifecycle -State $afterQueue
            Save-SnapshotAtomic -Snapshot $lifecycle
            $held = Wait-ForTerminalOperation -OperationId ([string]$lifecycle.operation.id) -OperationKind "purchase" -Context "production trainer purchase"
            Set-TrackedOperationFromState -Lifecycle $lifecycle -State $held
            Save-SnapshotAtomic -Snapshot $lifecycle
            if ($held.OperationState -cne "purchaseSucceeded") { throw "Trainer purchase terminal failure '$($held.OperationState)'." }
            $lifecycle = New-ValidatedHeldLifecycleCandidate `
                -Lifecycle $lifecycle `
                -HeldState $held `
                -CurrentIdentity $executionIdentity `
                -OutcomeSource "callback"
            Save-SnapshotAtomic -Snapshot $lifecycle
            Write-Host "[PASS] Correlated trainer callback produced the exact held grant vector."
        }
        catch
        {
            $lifecycle = New-ValidatedLastErrorLifecycleCandidate `
                -Lifecycle $lifecycle `
                -Message $_.Exception.Message `
                -CurrentIdentity $executionIdentity
            Save-SnapshotAtomic -Snapshot $lifecycle
            throw "Purchase stopped fail-closed. No cleanup occurs until the tracked payment/refund callback is terminal; its operation checkpoint remains intact. Cause: $($_.Exception.Message)"
        }
        exit 0
    }

    if ($Mode -ceq "VerifyBoundary")
    {
        if ([string]::IsNullOrWhiteSpace($BoundaryKind)) { throw "VerifyBoundary requires BoundaryKind." }
        if ($null -eq $lifecycle.held -or $null -eq $lifecycle.operation -or [string]$lifecycle.operation.state -cne "purchaseSucceeded")
        {
            throw "Boundary verification requires the terminal correlated purchase."
        }
        Assert-StatePersistentEquals -Actual $observed -Expected $lifecycle.held -Context "Held persistence"
        if ($BoundaryKind -ceq "Relog")
        {
            if ([string]$lifecycle.phase -cnotin @("held", "restartBoundaryArming")) { throw "Relog phase order is invalid." }
            if ($observed.ServerProcessToken -cne [string]$lifecycle.held.ServerProcessToken -or $observed.RelogNoncePresent) { throw "Relog proof failed." }
            if ([string]$lifecycle.phase -ceq "held")
            {
                $lifecycle.boundaries.relog = [pscustomobject]@{ Kind = "Relog"; OperationId = [string]$lifecycle.operation.id; ServerProcessToken = [string]$observed.ServerProcessToken; VerifiedAtUtc = [DateTime]::UtcNow.ToString("o") }
                $lifecycle.phase = "restartBoundaryArming"
                Save-SnapshotAtomic -Snapshot $lifecycle
            }
            if (-not $observed.RestartNoncePresent)
            {
                $armed = Invoke-Probe -Arguments "armRestartBoundary $PlayerOid $($lifecycle.operation.id) $($lifecycle.lifecycleId)"
                Assert-Field -Result $armed -Name "armed" -Expected "true"
                $observed = Wait-ForState -Context "restart boundary arming" -Predicate { param($state) $state.RestartNoncePresent }
            }
            $lifecycle.phase = "relogVerified"
            Save-SnapshotAtomic -Snapshot $lifecycle
            Write-Host "[PASS] Relog boundary independently verified."
            exit 0
        }
        if ([string]$lifecycle.phase -cne "relogVerified" -or $null -eq $lifecycle.boundaries.relog) { throw "Restart requires relog proof first." }
        if ($observed.RestartNoncePresent -or $observed.ServerProcessToken -ceq [string]$lifecycle.held.ServerProcessToken) { throw "Restart proof failed." }
        $lifecycle.boundaries.restart = [pscustomobject]@{ Kind = "Restart"; OperationId = [string]$lifecycle.operation.id; ServerProcessToken = [string]$observed.ServerProcessToken; VerifiedAtUtc = [DateTime]::UtcNow.ToString("o") }
        $lifecycle.phase = "restartVerified"
        Save-SnapshotAtomic -Snapshot $lifecycle
        Write-Host "[PASS] Restart boundary independently verified."
        exit 0
    }

    if ($Mode -ceq "Surrender")
    {
        if ([string]$lifecycle.phase -cne "restartVerified") { throw "Surrender requires both ordered relog and server-restart boundaries." }
        Assert-StatePersistentEquals -Actual $observed -Expected $lifecycle.held -Context "Pre-surrender held state"
        $lifecycle.cleanup = [pscustomobject]@{ origin = "restartVerified"; startedAtUtc = [DateTime]::UtcNow.ToString("o"); stage = "starting" }
        $lifecycle.phase = "cleanupPending"
        Save-SnapshotAtomic -Snapshot $lifecycle
        $observed = Clear-TerminalOperation -Lifecycle $lifecycle -State $observed
        $surrendered = Invoke-Surrender -Lifecycle $lifecycle
        Assert-SurrenderRelation -Lifecycle $lifecycle -Surrendered $surrendered
        $lifecycle.surrendered = New-StateSnapshot -State $surrendered
        Save-SnapshotAtomic -Snapshot $lifecycle
        $null = Invoke-BaselineCleanup -Lifecycle $lifecycle -CompletionPhase "complete"
        Write-Host "[PASS] Surrender and exact baseline restoration completed."
        exit 0
    }

    if ($Mode -ceq "Cleanup")
    {
        $null = Invoke-BaselineCleanup -Lifecycle $lifecycle -CompletionPhase "cleaned"
        Write-Host "[PASS] Fail-safe cleanup restored the exact baseline and released lifecycle ownership."
        exit 0
    }
    throw "Unhandled mode '$Mode'."
}
finally
{
    Exit-MutationLocks -Locks $mutationLocks
}
