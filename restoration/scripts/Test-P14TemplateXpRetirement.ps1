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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14TemplateXpRetirement)) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$xpPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.xpLibrary)

if (-not (Test-Path -LiteralPath $xpPath -PathType Leaf))
{
    throw "Required source file is missing: $xpPath"
}

$xp = Get-Content -LiteralPath $xpPath -Raw

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

function Assert-FailClosed([string]$Section, [string]$Name)
{
    foreach ($forbidden in @(
        "getSkillTemplate(",
        "skill_template.",
        "getLevel(",
        "TBL_PLAYER_LEVEL_XP",
        "grant(",
        "grantCombatStyleXp(",
        "grantSocialStyleXp(",
        "grantCraftingStyleXp(",
        "displayXpFlyText(",
        "displayXpMsg("
    ))
    {
        if ($Section.Contains($forbidden))
        {
            throw "$Name still contains retired progression token '$forbidden'."
        }
    }
    if (-not $Section.Contains("return 0;"))
    {
        throw "$Name does not fail closed."
    }
}

$byTemplate = Get-Section $xp `
    "public static int grantXpByTemplate" `
    "public static int grantUnmodifiedXpByTemplate"
$unmodifiedByTemplate = Get-Section $xp `
    "public static int grantUnmodifiedXpByTemplate" `
    "public static int grantUnmodifiedXPPercentageOfLevel"
$percentageOfLevel = Get-Section $xp `
    "public static int grantUnmodifiedXPPercentageOfLevel" `
    "public static void applyHealingCredit"

Assert-FailClosed $byTemplate "grantXpByTemplate"
Assert-FailClosed $unmodifiedByTemplate "grantUnmodifiedXpByTemplate"
Assert-FailClosed $percentageOfLevel "grantUnmodifiedXPPercentageOfLevel"

if ($Expectation -eq "Ready")
{
    if ([string]$contract.status -cne "ready" -or [string]$contract.runtimeEvidence.result -cne "passed")
    {
        throw "The template XP retirement does not yet contain passed runtime evidence."
    }
    $patchPath = Join-Path $restorationRoot ([string]$contract.buildEvidence.overlayPatch -replace "^restoration/", "")
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne [long]$contract.buildEvidence.overlayPatchBytes -or
        $patchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "The template XP retirement overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 template XP retirement contract passed."
