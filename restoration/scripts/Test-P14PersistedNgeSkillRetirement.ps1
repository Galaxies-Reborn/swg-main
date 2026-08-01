[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PersistedNgeSkillRetirement)) -Raw | ConvertFrom-Json
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

$cppPath = Join-Path $source ([string]$contract.sourceFiles.creatureObject)
$headerPath = Join-Path $source ([string]$contract.sourceFiles.creatureObjectHeader)
Assert-Contract (Test-Path -LiteralPath $cppPath -PathType Leaf) "p14.persisted-nge-skills.source.cpp"
Assert-Contract (Test-Path -LiteralPath $headerPath -PathType Leaf) "p14.persisted-nge-skills.source.header"

$cpp = Get-Content -LiteralPath $cppPath -Raw
$header = Get-Content -LiteralPath $headerPath -Raw

foreach ($evidence in @($contract.buildEvidence.overlayPatches))
{
    $patchPath = Join-Path (Split-Path -Parent $restorationRoot) ([string]$evidence.path)
    $exists = Test-Path -LiteralPath $patchPath -PathType Leaf
    Assert-Contract $exists "p14.persisted-nge-skills.overlay.exists"
    if ($exists)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and
            $sha -ceq [string]$evidence.sha256) "p14.persisted-nge-skills.overlay.authenticated"
    }
}

$predicate = Get-FunctionSlice $cpp "bool isRetiredNgeProgressionSkillName(" "// ----------------------------------------------------------------------"
Assert-Contract ($predicate.Contains('skillName.find("class_") == 0') -and
    $predicate.Contains('skillName == "expertise"') -and
    $predicate.Contains('skillName.find("expertise_") == 0') -and
    $predicate.Contains('skillName.find("internal_expertise_") == 0')) `
    "p14.persisted-nge-skills.retired-families"

$load = Get-FunctionSlice $cpp "void CreatureObject::onClientAboutToLoad()" "void CreatureObject::clearRetiredNgeProgressionSkills()"
$cleanup = Get-FunctionSlice $cpp "void CreatureObject::clearRetiredNgeProgressionSkills()" "void CreatureObject::onLoadingScreenComplete()"
$databaseLoad = Get-FunctionSlice $cpp "void CreatureObject::onLoadedFromDatabase()" "void CreatureObject::onPersistenceRelocated"
$setup = Get-FunctionSlice $cpp "void CreatureObject::setupSkillData()" "CreatureController* CreatureObject::createDefaultController"

Assert-Contract ($header.Contains("void clearRetiredNgeProgressionSkills();") -and
    $load.Contains("clearRetiredNgeProgressionSkills();") -and
    $load.IndexOf("clearRetiredNgeProgressionSkills();", [StringComparison]::Ordinal) -lt
        $load.IndexOf("TangibleObject::onClientAboutToLoad();", [StringComparison]::Ordinal)) `
    "p14.persisted-nge-skills.load-hook-before-baseline"

Assert-Contract ($cleanup.Contains("!isAuthoritative() || !isPlayerControlled()") -and
    $cleanup.Contains("std::vector<SkillObject const *> skillsToRetire") -and
    $cleanup.Contains("isRetiredNgeProgressionSkillName(skill->getSkillName())") -and
    $cleanup.Contains("m_skills.erase(*iter)") -and
    -not $cleanup.Contains("revokeSkill(")) `
    "p14.persisted-nge-skills.idempotent-authoritative-removal"

Assert-Contract ($databaseLoad.Contains("onClientAboutToLoad();") -and
    $databaseLoad.Contains("setupSkillData();") -and
    $databaseLoad.IndexOf("onClientAboutToLoad();", [StringComparison]::Ordinal) -lt
        $databaseLoad.IndexOf("setupSkillData();", [StringComparison]::Ordinal) -and
    $setup.Contains("m_modMap.clear();") -and $setup.Contains("clearCommands();") -and
    $setup.Contains("playerObject->clearSchematics();") -and $setup.Contains("recalculateLevel();")) `
    "p14.persisted-nge-skills.clean-set-rebuild"

$grant = Get-FunctionSlice $cpp "const bool CreatureObject::grantSkill(" "void CreatureObject::revokeSkill("
$expertise = Get-FunctionSlice $cpp "bool CreatureObject::processExpertiseRequest(" "bool CreatureObject::clearAllExpertises()"
Assert-Contract ($grant.Contains("isRetiredNgeProgressionSkillName") -and $grant.Contains("return false;") -and
    $expertise.Contains("Rejected retired NGE expertise request") -and $expertise.Contains("return false;")) `
    "p14.persisted-nge-skills.future-grants-contained"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.persisted-nge-skills.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 persisted NGE skill retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14 persisted NGE skill retirement passed."
