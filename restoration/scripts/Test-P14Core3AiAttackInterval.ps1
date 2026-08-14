[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$queuePath = Join-Path $root "src/engine/server/library/serverGame/src/shared/command/CommandQueue.cpp"
$queueHeaderPath = Join-Path $root "src/engine/server/library/serverGame/src/shared/command/CommandQueue.h"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_ai_attack_interval_runtime.java"
$queue = Get-Content -LiteralPath $queuePath -Raw
$queueHeader = Get-Content -LiteralPath $queueHeaderPath -Raw
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf))
{
    throw "Core3 AI cadence runtime fixture is missing."
}
$fixture = Get-Content -LiteralPath $fixturePath -Raw

$start = $queue.IndexOf("float calculatePrecuAttackTime(", [StringComparison]::Ordinal)
$end = $queue.IndexOf("float getCommandExecuteTime(", $start, [StringComparison]::Ordinal)
if ($start -lt 0 -or $end -le $start) { throw "Could not isolate the PRE-CU attack-time resolver." }
$timing = $queue.Substring($start, $end - $start)

$aiGuard = $timing.IndexOf("if (!owner.isPlayerControlled())", [StringComparison]::Ordinal)
$aiReturn = $timing.IndexOf("return 2.0f;", $aiGuard, [StringComparison]::Ordinal)
$modifier = $timing.IndexOf("int speedModifier", [StringComparison]::Ordinal)
$formula = $timing.IndexOf("speedMultiplier * weaponAttackSpeed", [StringComparison]::Ordinal)
$floor = $timing.IndexOf("return executeTime > 1.0f ? executeTime : 1.0f;", [StringComparison]::Ordinal)
if ($aiGuard -lt 0 -or $aiReturn -le $aiGuard -or $modifier -le $aiReturn)
{
    throw "Core3's two-second AI interval is not enforced before inherited speed modifiers."
}
if ($formula -le $modifier -or $floor -le $formula)
{
    throw "The player weapon-speed formula or one-second floor was not retained."
}

$executeStart = $queue.IndexOf("float getCommandExecuteTime(", [StringComparison]::Ordinal)
$executeEnd = $queue.IndexOf("using namespace CommandQueueNamespace;", $executeStart, [StringComparison]::Ordinal)
if ($executeStart -lt 0 -or $executeEnd -le $executeStart) { throw "Could not isolate command timing routing." }
$execute = $queue.Substring($executeStart, $executeEnd - $executeStart)
foreach ($required in @(
    "command.isPrimaryCommand()",
    "isWeaponCadenceAttack(command)",
    "return command.m_execTime;",
    "calculatePrecuAttackTime(owner, *weapon"
))
{
    if (-not $execute.Contains($required)) { throw "Attack timing routing is incomplete: $required" }
}

foreach ($required in @(
    "m_lastWeaponCadenceAttackTime = s_currentTime",
    "m_lastWeaponCadenceInterval = m_commandTimes[TimerClass_Execute]",
    "m_state.get() == State_Waiting",
    "double const earliestAttackTime",
    "m_nextEventTime = earliestAttackTime",
    "gate time="
))
{
    if (-not $queue.Contains($required)) { throw "Global attack cadence guard is incomplete: $required" }
}
foreach ($required in @("m_lastWeaponCadenceAttackTime", "m_lastWeaponCadenceInterval"))
{
    if (-not $queueHeader.Contains($required)) { throw "Global cadence state is missing: $required" }
}
foreach ($required in @(
    "PLAYER_OID = 44003778L",
    "PLAYER_STATION_ID = 91001",
    'ATTACK_COMMAND = "meleeHit"',
    "playerStateMutated=false",
    "createFixtureCreature",
    "queueCommand(",
    "destroyTracked(",
    "action=cleanup alreadyClean=true restored=true"
))
{
    if (-not $fixture.Contains($required))
    {
        throw "Core3 AI cadence runtime fixture is incomplete: $required"
    }
}

if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-core3-ai-attack-interval.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
        ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.buildEvidence.cppCompile -ne "passed" -or
        $contract.buildEvidence.architecture -ne "x86-64" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or
        @($contract.requiredBeforeReady).Count -ne 0)
    {
        throw "Core3 AI attack-interval evidence is not ready."
    }
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $queuePath).Hash.ToLowerInvariant()
    $headerHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $queueHeaderPath).Hash.ToLowerInvariant()
    if ($sourceHash -ne $contract.buildEvidence.sourceSha256."CommandQueue.cpp")
    {
        throw "CommandQueue source evidence mismatch."
    }
    if ($headerHash -ne $contract.buildEvidence.sourceSha256."CommandQueue.h")
    {
        throw "CommandQueue header evidence mismatch."
    }
    $fixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixturePath).Hash.ToLowerInvariant()
    if ($fixtureHash -ne $contract.buildEvidence.runtimeFixtureSourceSha256)
    {
        throw "Core3 AI cadence fixture source evidence mismatch."
    }
    $dsrcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "dsrc" })
    $srcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "src" })
    $checkedOutDsrc = (& git -C (Join-Path $root "dsrc") rev-parse HEAD).Trim()
    $checkedOutSrc = (& git -C (Join-Path $root "src") rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $dsrcPin.Count -ne 1 -or $srcPin.Count -ne 1 -or
        [string]$dsrcPin[0].commit -cne [string]$contract.buildEvidence.directSourceGitlink -or
        [string]$srcPin[0].commit -cne [string]$contract.buildEvidence.nativeSourceCommit -or
        $checkedOutDsrc -cne [string]$contract.buildEvidence.directSourceGitlink -or
        $checkedOutSrc -cne [string]$contract.buildEvidence.nativeSourceCommit)
    {
        throw "Core3 AI cadence direct-source pin evidence mismatch."
    }
    $ai = $contract.runtimeEvidence.currentBuildAiValidation
    $player = $contract.runtimeEvidence.currentProcessPlayerCadenceValidation
    if ([string]$ai.result -cne "passed" -or
        [int]$ai.attackEvents -lt 3 -or
        [int]$ai.consecutiveSameServerOwnerPairs -lt 2 -or
        [double]$ai.assignedIntervalSeconds -ne 2.0 -or
        [double]$ai.minimumObservedConsecutiveSeconds -lt 1.95 -or
        [int]$ai.pairsBelow1_95Seconds -ne 0 -or
        [int]$ai.gateEvents -lt 1 -or
        -not [bool]$ai.cleanupRestored -or
        -not [bool]$ai.secondCleanupAlreadyClean -or
        [bool]$ai.playerStateMutated -or
        [string]$player.result -cne "passed" -or
        [int]$player.playerAttackEvents -lt 2 -or
        [int]$player.pairsBelowAssignedInterval -ne 0)
    {
        throw "Core3 AI cadence live interval evidence is incomplete."
    }
    foreach ($patchEvidence in @(
        [pscustomobject]@{
            Path = $contract.buildEvidence.overlayPatch
            Bytes = $contract.buildEvidence.overlayPatchBytes
            Sha256 = $contract.buildEvidence.overlayPatchSha256
        },
        [pscustomobject]@{
            Path = $contract.buildEvidence.retargetGuardPatch.path
            Bytes = $contract.buildEvidence.retargetGuardPatch.bytes
            Sha256 = $contract.buildEvidence.retargetGuardPatch.sha256
        }
    ))
    {
        $patchPath = Join-Path (Split-Path -Parent $restorationRoot) $patchEvidence.Path
        $patch = Get-Item -LiteralPath $patchPath
        $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
        if ($patch.Length -ne $patchEvidence.Bytes -or $patchHash -ne $patchEvidence.Sha256)
        {
            throw "Core3 AI interval patch evidence mismatch: $($patchEvidence.Path)"
        }
    }
    $contractText = Get-Content -LiteralPath $contractPath -Raw
    if ($contractText.Contains("/Artifacts/") -or
        $contractText.Contains("/Staging/"))
    {
        throw "Core3 AI cadence contract references host staging."
    }
}

Write-Host "Publish 14 Core3 AI attack-interval contract passed."
