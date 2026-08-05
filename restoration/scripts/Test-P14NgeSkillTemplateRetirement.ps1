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

function Get-FunctionSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
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

$nativePlayerObjectPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.nativePlayerObject)
if (-not (Test-Path -LiteralPath $nativePlayerObjectPath -PathType Leaf))
{
    throw "Native PlayerObject source is missing: $nativePlayerObjectPath"
}
$nativePlayerObject = Get-Content -LiteralPath $nativePlayerObjectPath -Raw
$skillTemplateSetter = Get-FunctionSlice $nativePlayerObject `
    "bool PlayerObject::setSkillTemplate" "std::string const & PlayerObject::getWorkingSkill"
$workingSkillSetter = Get-FunctionSlice $nativePlayerObject `
    "bool PlayerObject::setWorkingSkill" "void PlayerObject::setPendingRequestQuestInformation"
if (-not $skillTemplateSetter.Contains("m_skillTemplate.set(std::string());") -or
    $skillTemplateSetter.Contains("m_skillTemplate.set(templateName)") -or
    $skillTemplateSetter.Contains("TRIG_SKILL_TEMPLATE_CHANGED") -or
    -not $skillTemplateSetter.Contains("LfgCharacterData::Prof_Unknown") -or
    -not $skillTemplateSetter.Contains("Ignored retired NGE skill template"))
{
    throw "Native skill-template state is not fail-closed to the PRE-CU empty/unknown representation."
}
if (-not $workingSkillSetter.Contains("m_workingSkill.set(std::string());") -or
    $workingSkillSetter.Contains("m_workingSkill.set(skillName)") -or
    $workingSkillSetter.Contains("TRIG_WORKING_SKILL_CHANGED") -or
    -not $workingSkillSetter.Contains("Ignored retired NGE working skill"))
{
    throw "Native working-skill state is not fail-closed to the PRE-CU empty representation."
}
Assert-Hash ([string]$contract.sourceFiles.nativePlayerObject) `
    ([string]$contract.buildEvidence.sourceSha256."PlayerObject.cpp")

if ($Expectation -eq "Ready")
{
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    if ($srcPin.Count -ne 1 -or
        [string]$srcPin[0].commit -cne [string]$contract.buildEvidence.nativeSourceCommit)
    {
        throw "The native source gitlink does not match the authenticated skill-template retirement source."
    }
    $patchPath = Join-Path $restorationRoot ([string]$contract.buildEvidence.overlayPatch -replace "^restoration/", "")
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne [long]$contract.buildEvidence.overlayPatchBytes -or
        $patchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "The retirement overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 NGE skill-template retirement contract passed."
