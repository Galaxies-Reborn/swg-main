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
$queue = Get-Content -LiteralPath $queuePath -Raw
$queueHeader = Get-Content -LiteralPath $queueHeaderPath -Raw

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

if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-core3-ai-attack-interval.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.buildEvidence.cppCompile -ne "passed" -or
        $contract.buildEvidence.architecture -ne "x86-64" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
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
}

Write-Host "Publish 14 Core3 AI attack-interval contract passed."
