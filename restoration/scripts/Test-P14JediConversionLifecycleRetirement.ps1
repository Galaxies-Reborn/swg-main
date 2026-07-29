param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14JediConversionLifecycleRetirement)) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$conversionPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.jediConversion)

if (-not (Test-Path -LiteralPath $conversionPath -PathType Leaf))
{
    throw "Required source file is missing: $conversionPath"
}

$conversion = Get-Content -LiteralPath $conversionPath -Raw

function Get-Section([string]$Text, [string]$Start, [string]$End)
{
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0)
    {
        throw "Missing section start: $Start"
    }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($endIndex -lt 0)
    {
        throw "Missing section end: $End"
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Assert-InertLifecycle([string]$Section, [string]$Name)
{
    if (-not $Section.Contains('detachScript(self, "player.player_jedi_conversion");'))
    {
        throw "$Name does not detach the inherited conversion script."
    }
    foreach ($forbidden in @(
        "convertOldJedi(",
        "setSkillTemplate(",
        "setWorkingSkill(",
        "combatLevel",
        "forceSensitiveSui(",
        "jediSui(",
        "regularSkillSui("
    ))
    {
        if ($Section.Contains($forbidden))
        {
            throw "$Name still invokes inherited conversion behavior '$forbidden'."
        }
    }
}

$onAttach = Get-Section $conversion `
    "public int OnAttach(obj_id self)" `
    "public void convertOldJedi(obj_id self)"
$onLogin = Get-Section $conversion `
    "public int OnLogin(obj_id self)" `
    "public int OnInitialize(obj_id self)"
$onInitialize = Get-Section $conversion `
    "public int OnInitialize(obj_id self)" `
    "public void restartConversionSUI()"

Assert-InertLifecycle $onAttach "OnAttach"
Assert-InertLifecycle $onLogin "OnLogin"
Assert-InertLifecycle $onInitialize "OnInitialize"

$convertCallCount = ([regex]::Matches($conversion, "\bconvertOldJedi\s*\(")).Count
if ($convertCallCount -ne 1)
{
    throw "convertOldJedi must remain as one uncalled historical method; found $convertCallCount references."
}
if (-not $conversion.Contains('setObjVar(self, "combatLevel", 80);'))
{
    throw "The historical conversion body was removed instead of being isolated."
}

$actualSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $conversionPath).Hash.ToLowerInvariant()
if ($actualSourceHash -cne [string]$contract.buildEvidence.sourceSha256."player_jedi_conversion.java")
{
    throw "player_jedi_conversion.java hash mismatch. Expected $($contract.buildEvidence.sourceSha256.'player_jedi_conversion.java'), got $actualSourceHash."
}

if ($Expectation -eq "Ready")
{
    if ([string]$contract.status -cne "ready" -or [string]$contract.runtimeEvidence.result -cne "passed")
    {
        throw "The Jedi conversion lifecycle retirement does not yet contain passed runtime evidence."
    }
    $patchPath = Join-Path $restorationRoot ([string]$contract.buildEvidence.overlayPatch -replace "^restoration/", "")
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne [long]$contract.buildEvidence.overlayPatchBytes -or
        $patchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "The Jedi conversion lifecycle overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 Jedi conversion lifecycle retirement contract passed."
