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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14ForceSensitiveEligibility)
) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$jediPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.jediLibrary)
$saberPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.saberComponent)
$fixturePath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.liveFixture)

foreach ($path in @($jediPath, $saberPath, $fixturePath))
{
    if (-not (Test-Path -LiteralPath $path))
    {
        throw "Required Force-sensitive source path is missing: $path"
    }
}

$jedi = Get-Content -LiteralPath $jediPath -Raw
$forceStart = $jedi.IndexOf(
    "public static boolean isForceSensitive(obj_id player)",
    [StringComparison]::Ordinal
)
$levelStart = $jedi.IndexOf(
    "public static boolean isForceSensitiveLevelRequired",
    $forceStart + 1,
    [StringComparison]::Ordinal
)
$tuningStart = $jedi.IndexOf(
    "public static boolean canTuneLightsaberCrystal",
    $levelStart + 1,
    [StringComparison]::Ordinal
)
$tuningEnd = $jedi.IndexOf(
    "public static boolean hasAnyUltraCloak",
    $tuningStart + 1,
    [StringComparison]::Ordinal
)
if ($forceStart -lt 0 -or $levelStart -lt 0 -or
    $tuningStart -lt 0 -or $tuningEnd -lt 0)
{
    throw "Unable to isolate the Force-sensitive eligibility methods."
}

$forceMethod = $jedi.Substring($forceStart, $levelStart - $forceStart)
$levelMethod = $jedi.Substring($levelStart, $tuningStart - $levelStart)
$tuningMethod = $jedi.Substring($tuningStart, $tuningEnd - $tuningStart)
if (-not $forceMethod.Contains(
        "isJediState(player, JEDI_STATE_FORCE_SENSITIVE)"))
{
    throw "Force-sensitive eligibility does not use the native Jedi state."
}
foreach ($forbidden in @("getSkillTemplate(", "getLevel(", "startsWith("))
{
    if ($forceMethod.Contains($forbidden))
    {
        throw "Force-sensitive eligibility still contains '$forbidden'."
    }
}
if (-not $levelMethod.Contains("return false;") -or
    $levelMethod.Contains("getLevel(") -or
    $levelMethod.Contains("getSkillTemplate("))
{
    throw "The inherited level entry point does not fail closed."
}
if (-not $tuningMethod.Contains(
        'hasSkill(player, "force_title_jedi_rank_01")') -or
    $tuningMethod.Contains("getLevel(") -or
    $tuningMethod.Contains("getSkillTemplate("))
{
    throw "Crystal tuning does not use the exact Pre-CU rank skill."
}

$saber = Get-Content -LiteralPath $saberPath -Raw
$callCount = [regex]::Matches(
    $saber,
    [regex]::Escape("jedi.canTuneLightsaberCrystal(player)")
).Count
if ($callCount -ne [int]$contract.expected.saberComponentCallSites)
{
    throw "Expected $($contract.expected.saberComponentCallSites) crystal-tuning gates; found $callCount."
}
if ($saber.Contains("jedi.isForceSensitiveLevelRequired("))
{
    throw "The saber component still calls the NGE level gate."
}

$fixture = Get-Content -LiteralPath $fixturePath -Raw
foreach ($required in @(
    "setJediState(player, JEDI_STATE_FORCE_SENSITIVE)",
    "setJediState(player, JEDI_STATE_JEDI)",
    "grantSkill(player, CRYSTAL_TUNING_SKILL)",
    "revokeSkill(player, CRYSTAL_TUNING_SKILL)",
    "setJediState(player, originalState)",
    "restoredTuningSkill == tuningSkillBefore"
))
{
    if (-not $fixture.Contains($required))
    {
        throw "Reversible Force-sensitive fixture is missing '$required'."
    }
}

foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties)
{
    $path = switch ($entry.Name)
    {
        "jedi.java" { $jediPath }
        "jedi_saber_component.java" { $saberPath }
        "precu_force_sensitive_eligibility_fixture.java" { $fixturePath }
        default { throw "Unknown Force-sensitive source hash '$($entry.Name)'." }
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actual -cne [string]$entry.Value)
    {
        throw "$($entry.Name) hash mismatch. Expected $($entry.Value), got $actual."
    }
}

if ($Expectation -eq "Ready")
{
    if ([string]$contract.status -cne "ready" -or
        [string]$contract.runtimeEvidence.result -cne "passed" -or
        -not [bool]$contract.runtimeEvidence.restored)
    {
        throw "Force-sensitive eligibility does not contain passed, restored runtime evidence."
    }
    $patchPath = Join-Path $restorationRoot (
        [string]$contract.buildEvidence.overlayPatch -replace "^restoration/", ""
    )
    $actualPatchHash =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne
            [long]$contract.buildEvidence.overlayPatchBytes -or
        $actualPatchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "Force-sensitive eligibility overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 Force-sensitive eligibility contract passed."
