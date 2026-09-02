[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/reborn-force-progression-gate.json") -Raw | ConvertFrom-Json

function Get-VerifiedIff([string]$RelativePath, [string]$ExpectedHash, [int]$ExpectedBytes, [string]$Name)
{
    $path = Join-Path $repositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "$Name is missing: $RelativePath"
    }

    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ne $ExpectedBytes)
    {
        throw "$Name byte length is $($bytes.Length); expected $ExpectedBytes. Rebuild and publish the IFF."
    }
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -cne "FORM")
    {
        throw "$Name is not an IFF FORM artifact."
    }

    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($actualHash -cne $ExpectedHash)
    {
        throw "$Name SHA-256 is $actualHash; expected $ExpectedHash. Rebuild and publish the IFF."
    }

    return [pscustomobject]@{
        Path = $path
        Bytes = $bytes
        Ascii = [Text.Encoding]::ASCII.GetString($bytes)
        Hash = $actualHash
    }
}

$questAcceptance = $contract.acceptance.serverArtifacts.questNetwork
$questArtifact = Get-VerifiedIff `
    ([string]$contract.sourceIncrement.questNetworkArtifact) `
    ([string]$questAcceptance.sha256) `
    ([int]$questAcceptance.bytes) `
    "quest_network.iff"

$catalog = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$contract.questNetwork.catalog)) -Raw | ConvertFrom-Json
$missingQuestIds = @($catalog.questChains | ForEach-Object { [string]$_.id } | Where-Object { -not $questArtifact.Ascii.Contains($_) })
$requiredQuestStrings = @("planet", "city", "npc_type", "event_type", "route_family", "branch", "ECHO", "THREAD", "CONVERGENCE")
$missingQuestStrings = @($requiredQuestStrings | Where-Object { -not $questArtifact.Ascii.Contains($_) })
if ($missingQuestIds.Count -gt 0 -or $missingQuestStrings.Count -gt 0)
{
    throw "quest_network.iff is structurally incomplete. Missing IDs: $($missingQuestIds -join ', '); missing fields: $($missingQuestStrings -join ', ')."
}

$commandAcceptance = $contract.acceptance.serverArtifacts.commandTable
$commandArtifact = Get-VerifiedIff `
    ([string]$contract.sourceIncrement.commandTableArtifact) `
    ([string]$commandAcceptance.sha256) `
    ([int]$commandAcceptance.bytes) `
    "command_table.iff"

$missingCommandStrings = @("check", "checkForceStatus", "cmdCheckForceStatus") | Where-Object { -not $commandArtifact.Ascii.Contains($_) }
if (@($missingCommandStrings).Count -gt 0)
{
    throw "command_table.iff does not contain the Reborn Force command routing: $($missingCommandStrings -join ', ')."
}

Write-Host "Reborn Force server artifacts passed: quest_network.iff $($questArtifact.Hash), command_table.iff $($commandArtifact.Hash)."
