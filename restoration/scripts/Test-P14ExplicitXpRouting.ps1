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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14ExplicitXpRouting)) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$xpPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.xpLibrary)
$basePlayerPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.playerInitialization)
$runtimeProbePath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.runtimeProbe)

foreach ($path in @($xpPath, $basePlayerPath, $runtimeProbePath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required source file is missing: $path"
    }
}

$xp = Get-Content -LiteralPath $xpPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$runtimeProbe = Get-Content -LiteralPath $runtimeProbePath -Raw

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

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message)
{
    if (-not $Text.Contains($Needle))
    {
        throw $Message
    }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message)
{
    if ($Text.Contains($Needle))
    {
        throw $Message
    }
}

$unmodified = Get-Section $xp `
    "public static boolean _grantUnmodifiedExperience" `
    "public static boolean grantCraftingXpChance"
$activeRoutes = Get-Section $xp `
    "public static int grantSocialStyleXp" `
    "public static void displayXpMsg"

Assert-NotContains $unmodified "skill_template.isQualifiedForWorkingSkill" "XP accumulation still qualifies an NGE working skill."
Assert-NotContains $unmodified "skill_template.earnWorkingSkill" "XP accumulation still auto-awards an NGE working skill."
Assert-NotContains $activeRoutes "skill_template." "An active style XP route still consults the retired class template."
Assert-NotContains $basePlayer "skill_template.validateWorkingSkill(self);" "Player initialization still validates the retired working skill."
Assert-NotContains $xp "TRADER_XP_MOD" "The fixed NGE trader XP multiplier is still present."
Assert-NotContains $xp "ENTERTAINER_XP_MOD" "The fixed NGE entertainer XP multiplier is still present."
Assert-NotContains $xp "CRAFTING_MERCHANT_EXCHANGE_RATE" "The NGE crafting-to-merchant template exchange is still present."

Assert-Contains $activeRoutes "return grant(player, directXpType, amount, false);" "Explicit style XP routes do not grant their normalized XP type."
Assert-Contains $activeRoutes "return grant(player, CRAFTING_GENERAL, amount, false);" "Generic crafting quest XP does not fall back to crafting_general."
Assert-Contains $xp "return COMBAT_GENERAL;" "Generic combat quest XP does not fall back to combat_general."
Assert-Contains $xp "return ENTERTAINER;" "Generic social quest XP does not fall back to entertainer."
Assert-Contains $xp "return CRAFTING_GENERAL;" "Generic crafting XP does not fall back to crafting_general."
Assert-Contains $xp "xpType = COMBAT_GENERAL;" "Combined combat XP messages still depend on a working class template."
Assert-Contains $runtimeProbe "int baselineSkills = getSkillCount(player);" "The XP-routing runtime probe does not lock its pre-grant skill count."
Assert-Contains $runtimeProbe "boolean skillsStable = observedSkills == baselineSkills;" "The XP-routing runtime probe does not verify that XP cannot auto-award a skill."
Assert-Contains $runtimeProbe "grantExperiencePoints(player, effectiveType, -delta);" "The XP-routing runtime probe does not restore its XP mutation."

$expectedHashes = $contract.buildEvidence.sourceSha256
$actualProbeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeProbePath).Hash.ToLowerInvariant()
if ($actualProbeHash -cne [string]$expectedHashes."precu_xp_routing_runtime.java")
{
    throw "precu_xp_routing_runtime.java hash mismatch. Expected $($expectedHashes.'precu_xp_routing_runtime.java'), got $actualProbeHash."
}

if ($Expectation -eq "Ready")
{
    $patchPath = Join-Path $restorationRoot ([string]$contract.buildEvidence.overlayPatch -replace "^restoration/", "")
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne [long]$contract.buildEvidence.overlayPatchBytes -or
        $patchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "The explicit XP-routing overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 explicit XP-routing contract passed."
