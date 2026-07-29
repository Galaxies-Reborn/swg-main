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
$manifest = Get-Content -LiteralPath (
    Join-Path $restorationRoot "manifest.json"
) -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot (
        [string]$manifest.contracts.p14EntertainerAttributeBuffSession
    )
) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$performancePath = Join-Path $root (
    [string]$contract.sourceFiles.performanceLibrary
)
$fixturePath = Join-Path $root (
    [string]$contract.sourceFiles.liveFixture
)
foreach ($path in @($performancePath, $fixturePath))
{
    if (-not (Test-Path -LiteralPath $path))
    {
        throw "Required entertainer attribute-buff source is missing: $path"
    }
}

$performance = Get-Content -LiteralPath $performancePath -Raw
foreach ($required in @(
    "beginPrecuEntertainerBuffSession(",
    "increasePrecuEntertainerBuffSession(",
    "activatePrecuEntertainerBuffSession(",
    "applyPrecuEntertainerAttributeBuff(",
    '"private_buff_mind"',
    '"accelerate_entertainer_buff"',
    '"healing_dance_mind"',
    '"healing_music_mind"',
    "PRECU_BUFF_DURATION_PER_TICK_MINUTES *",
    "PRECU_BUFF_MAX_DURATION_MINUTES",
    "PRECU_BUFF_MIN_SESSION_SECONDS",
    "PRECU_BUFF_MAX_STRENGTH_PERCENT",
    "getUnmodifiedMaxAttrib(target, MIND)",
    "getUnmodifiedMaxAttrib(target, FOCUS)",
    "getUnmodifiedMaxAttrib(target, WILLPOWER)",
    "getNamedAttribModifierValue(",
    "removeAttribOrSkillModModifier(",
    "addAttribModifiers(target, mods)"
))
{
    if (-not $performance.Contains($required))
    {
        throw "Entertainer attribute-buff runtime is missing '$required'."
    }
}
if ([regex]::Matches(
        $performance,
        "activatePrecuEntertainerBuffSession\("
    ).Count -lt 3)
{
    throw "Both watch/listen stop paths do not activate the session."
}
if ([regex]::Matches(
        $performance,
        "beginPrecuEntertainerBuffSession\("
    ).Count -lt 3)
{
    throw "Both watch/listen start paths do not initialize the session."
}

$fixture = Get-Content -LiteralPath $fixturePath -Raw
foreach ($required in @(
    "applyPrecuEntertainerAttributeBuff(",
    "weakerDanceRejected",
    "expectedMind",
    "expectedFocus",
    "expectedWillpower",
    "removeAttribOrSkillModModifier(",
    "restored"
))
{
    if (-not $fixture.Contains($required))
    {
        throw "Reversible entertainer fixture is missing '$required'."
    }
}

function Get-NormalizedSha256
{
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = [IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try
    {
        return (
            [BitConverter]::ToString($sha256.ComputeHash($bytes))
        ).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha256.Dispose()
    }
}

$sourcePaths = @{
    "performance.java" = $performancePath
    "precu_entertainer_attribute_buff_fixture.java" = $fixturePath
}
foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties)
{
    $actual = Get-NormalizedSha256 -Path $sourcePaths[$entry.Name]
    if ($actual -cne [string]$entry.Value)
    {
        throw "$($entry.Name) source hash mismatch."
    }
}

if ($Expectation -eq "Ready")
{
    if ([string]$contract.status -cne "ready" -or
        [string]$contract.runtimeEvidence.result -cne "passed" -or
        -not [bool]$contract.runtimeEvidence.restored -or
        -not [bool]$contract.runtimeEvidence.serverHealthy -or
        [int]$contract.runtimeEvidence.fatalSevereExceptionCount -ne 0)
    {
        throw "Entertainer attribute-buff runtime evidence is not ready."
    }
    $patchPath = Join-Path $restorationRoot (
        [string]$contract.buildEvidence.overlayPatch -replace
            "^restoration/", ""
    )
    $normalizedPatch = (
        [IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"
    )
    $patchBytes = [Text.Encoding]::UTF8.GetBytes($normalizedPatch)
    $patchHash = Get-NormalizedSha256 -Path $patchPath
    if ($patchBytes.Length -ne
            [long]$contract.buildEvidence.overlayPatchBytes -or
        $patchHash -cne
            [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "Canonical entertainer attribute-buff overlay mismatch."
    }
}

Write-Host "Publish 14.1 entertainer attribute-buff session contract passed."
