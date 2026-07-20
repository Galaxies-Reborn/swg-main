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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14NgeSkillTemplateRetirement)) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path

function Get-TableLines([string]$RelativePath)
{
    $path = Join-Path $resolvedRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required table is missing: $path"
    }
    return [System.IO.File]::ReadAllLines($path)
}

function Assert-Hash([string]$RelativePath, [string]$Expected)
{
    $path = Join-Path $resolvedRoot $RelativePath
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actual -cne $Expected)
    {
        throw "Hash mismatch for $RelativePath. Expected $Expected, got $actual."
    }
}

$skills = @(Get-TableLines ([string]$contract.sourceFiles.skillTable))
$templates = @(Get-TableLines ([string]$contract.sourceFiles.skillTemplateTable))
$rewards = @(Get-TableLines ([string]$contract.sourceFiles.roadmapRewardsTable))

if ($templates.Count -ne 3)
{
    throw "The compatibility skill-template table must contain exactly its header, type, and inert sentinel rows."
}
if ($templates[0] -cne [string]$contract.expected.skillTemplateHeader -or
    $templates[1] -cne [string]$contract.expected.skillTemplateTypes -or
    $templates[2] -cne [string]$contract.expected.skillTemplateSentinel)
{
    throw "The compatibility skill-template schema drifted."
}

$allLines = @($skills + $templates + $rewards)
$prerequisiteRows = @($skills | Where-Object { $_ -match "^[^\t]*_prereq(?:_|\t)" })
$prerequisiteReferences = @($allLines | Where-Object { $_ -match "_prereq(?:_|\t)" })

if ($prerequisiteRows.Count -ne [int]$contract.expected.remainingPrerequisiteSkillRows)
{
    throw "Expected no NGE prerequisite skill rows; found $($prerequisiteRows.Count)."
}
if ($prerequisiteReferences.Count -ne [int]$contract.expected.remainingPrerequisiteReferences)
{
    throw "Expected no NGE prerequisite references; found $($prerequisiteReferences.Count)."
}
if (($rewards.Count - 2) -ne [int]$contract.expected.roadmapRewardDataRows)
{
    throw "Roadmap reward row count drifted."
}

Assert-Hash ([string]$contract.sourceFiles.skillTable) ([string]$contract.buildEvidence.sourceSha256."skills.tab")
Assert-Hash ([string]$contract.sourceFiles.skillTemplateTable) ([string]$contract.buildEvidence.sourceSha256."skill_template.tab")
Assert-Hash ([string]$contract.sourceFiles.roadmapRewardsTable) ([string]$contract.buildEvidence.sourceSha256."item_rewards.tab")

if ($Expectation -eq "Ready")
{
    $patchPath = Join-Path $restorationRoot ([string]$contract.buildEvidence.overlayPatch -replace "^restoration/", "")
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne [long]$contract.buildEvidence.overlayPatchBytes -or
        $patchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "The retirement overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 NGE skill-template retirement contract passed."
