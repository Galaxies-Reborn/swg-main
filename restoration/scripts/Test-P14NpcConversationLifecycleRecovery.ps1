[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14NpcConversationLifecycleRecovery)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

foreach ($evidence in @($contract.buildEvidence.overlayPatches))
{
    $patchPath = Join-Path $repositoryRoot ([string]$evidence.path)
    $exists = Test-Path -LiteralPath $patchPath -PathType Leaf
    Assert-Contract $exists ("p14.npc-conversation.overlay." + [string]$evidence.component + ".exists")
    if ($exists)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and
            $sha -ceq [string]$evidence.sha256) `
            ("p14.npc-conversation.overlay." + [string]$evidence.component + ".authenticated")
    }
}

$commandPath = Join-Path $source ([string]$contract.sourceFiles.commandDispatch)
$lifecyclePath = Join-Path $source ([string]$contract.sourceFiles.conversationLifecycle)
$configPath = Join-Path $source ([string]$contract.sourceFiles.runtimeConfig)
Assert-Contract (Test-Path -LiteralPath $commandPath -PathType Leaf) "p14.npc-conversation.source.command"
Assert-Contract (Test-Path -LiteralPath $lifecyclePath -PathType Leaf) "p14.npc-conversation.source.lifecycle"
Assert-Contract (Test-Path -LiteralPath $configPath -PathType Leaf) "p14.npc-conversation.source.config"

$commands = Get-Content -LiteralPath $commandPath -Raw
$lifecycle = Get-Content -LiteralPath $lifecyclePath -Raw
$config = Get-Content -LiteralPath $configPath -Raw
$start = Get-FunctionSlice $lifecycle "bool TangibleObject::startNpcConversation(" "void TangibleObject::endNpcConversation(StringId"
$end = Get-FunctionSlice $lifecycle "void TangibleObject::endNpcConversation()" "void TangibleObject::clearNpcConversation()"
$commandStart = Get-FunctionSlice $commands "static void commandFuncNpcConversationStart(" "static void commandFuncNpcConversationStop("

Assert-Contract ($lifecycle.Contains('#include "sharedLog/Log.h"') -and
    $start.Contains("starter != NpcConversationData::CS_Player") -and
    $start.Contains("recover stale-session") -and
    $start.Contains("endNpcConversation();") -and
    $start.Contains("stale-session-cleanup-failed") -and
    $start.Contains("session-started")) "p14.npc-conversation.fresh-request-recovers-stale-session"

Assert-Contract ($end.Contains("TRIG_END_NPC_CONVERSATION") -and
    $end.Contains("TRIG_END_CONVERSATION") -and
    $end.Contains("ignored cleanup-veto") -and
    $end.Contains("npc->removeConversation(getNetworkId())") -and
    $end.Contains("removeConversation(m_npcConversation->getNPC())") -and
    $end.Contains("delete m_npcConversation") -and
    $end.Contains("m_npcConversation = nullptr") -and
    -not $end.Contains("if(overridden)") -and
    -not $end.Contains("if (overridden)`r`n`t`t`t`t`t`treturn")) `
    "p14.npc-conversation.cleanup-is-non-vetoable"

Assert-Contract ($commandStart.Contains("reason=actor-unavailable") -and
    $commandStart.Contains("reason=target-unavailable") -and
    $commandStart.Contains("reason=manipulation-check") -and
    $commandStart.Contains("reason=bad-params") -and
    $commandStart.Contains("command-start actor=%s target=%s starter=%d result=%d")) `
    "p14.npc-conversation.command-telemetry"

Assert-Contract ($config.Contains("logs/precuNpcConversation.log{c-*:c+PreCuConversation}")) `
    "p14.npc-conversation.dedicated-log-target"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.npc-conversation.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 NPC conversation lifecycle recovery failed: $($failures -join ', ')"
}
Write-Host "Publish 14 NPC conversation lifecycle recovery passed."
