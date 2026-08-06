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
$xpPath = Join-Path $source ([string]$contract.sourceFiles.xpLibrary)
$pgcPath = Join-Path $source ([string]$contract.sourceFiles.pgcLibrary)
$basePlayerPath = Join-Path $source ([string]$contract.sourceFiles.basePlayer)
Assert-Contract (Test-Path -LiteralPath $cppPath -PathType Leaf) "p14.persisted-nge-skills.source.cpp"
Assert-Contract (Test-Path -LiteralPath $headerPath -PathType Leaf) "p14.persisted-nge-skills.source.header"
Assert-Contract (Test-Path -LiteralPath $xpPath -PathType Leaf) "p14.persisted-nge-progression.source.xp"
Assert-Contract (Test-Path -LiteralPath $pgcPath -PathType Leaf) "p14.persisted-nge-progression.source.pgc"
Assert-Contract (Test-Path -LiteralPath $basePlayerPath -PathType Leaf) "p14.persisted-nge-progression.source.base-player"

$cpp = Get-Content -LiteralPath $cppPath -Raw
$header = Get-Content -LiteralPath $headerPath -Raw
$xp = Get-Content -LiteralPath $xpPath -Raw
$pgc = Get-Content -LiteralPath $pgcPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw

foreach ($entry in @{
    "CreatureObject.cpp" = $cppPath
    "CreatureObject.h" = $headerPath
    "xp.java" = $xpPath
    "pgc_quests.java" = $pgcPath
    "base_player.java" = $basePlayerPath
}.GetEnumerator())
{
    $actual = (Get-FileHash -LiteralPath $entry.Value -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Contract ($actual -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
        "p14.persisted-nge-progression.source.authenticated.$($entry.Key)"
}

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

$experiencePredicate = Get-FunctionSlice $cpp "bool isRetiredNgeProgressionExperienceType(" "bool isRetiredNgeProgressionCommandName("
foreach ($experienceType in @($contract.expected.retiredExactExperienceTypes))
{
    Assert-Contract ($experiencePredicate.Contains('experienceType == "' + [string]$experienceType + '"')) `
        "p14.persisted-nge-progression.retired-experience.$experienceType"
}

$load = Get-FunctionSlice $cpp "void CreatureObject::onClientAboutToLoad()" "void CreatureObject::clearRetiredNgeProgressionSkills()"
$cleanup = Get-FunctionSlice $cpp "void CreatureObject::clearRetiredNgeProgressionSkills()" "void CreatureObject::onLoadingScreenComplete()"
$experienceCleanup = Get-FunctionSlice $cpp "void CreatureObject::clearRetiredNgeProgressionExperience()" "void CreatureObject::onLoadingScreenComplete()"
$databaseLoad = Get-FunctionSlice $cpp "void CreatureObject::onLoadedFromDatabase()" "void CreatureObject::onPersistenceRelocated"
$setup = Get-FunctionSlice $cpp "void CreatureObject::setupSkillData()" "CreatureController* CreatureObject::createDefaultController"

Assert-Contract ($header.Contains("void clearRetiredNgeProgressionSkills();") -and
    $load.Contains("clearRetiredNgeProgressionSkills();") -and
    $header.Contains("void clearRetiredNgeProgressionExperience();") -and
    $load.Contains("clearRetiredNgeProgressionExperience();") -and
    $load.IndexOf("clearRetiredNgeProgressionSkills();", [StringComparison]::Ordinal) -lt
        $load.IndexOf("clearRetiredNgeProgressionExperience();", [StringComparison]::Ordinal) -and
    $load.IndexOf("clearRetiredNgeProgressionExperience();", [StringComparison]::Ordinal) -lt
        $load.IndexOf("TangibleObject::onClientAboutToLoad();", [StringComparison]::Ordinal)) `
    "p14.persisted-nge-skills.load-hook-before-baseline"

Assert-Contract ($cleanup.Contains("!isAuthoritative() || !isPlayerControlled()") -and
    $cleanup.Contains("std::vector<SkillObject const *> skillsToRetire") -and
    $cleanup.Contains("isRetiredNgeProgressionSkillName(skill->getSkillName())") -and
    $cleanup.Contains("m_skills.erase(*iter)") -and
    -not $cleanup.Contains("revokeSkill(")) `
    "p14.persisted-nge-skills.idempotent-authoritative-removal"

Assert-Contract ($experienceCleanup.Contains("!isAuthoritative() || !isPlayerControlled()") -and
    $experienceCleanup.Contains('char const * const chroniclesExperience = "chronicles";') -and
    $experienceCleanup.Contains("getExperiencePoints(chroniclesExperience)") -and
    $experienceCleanup.Contains("grantExperiencePoints(chroniclesExperience, -persistedExperience)") -and
    $experienceCleanup.Contains("if (persistedExperience > 0)")) `
    "p14.persisted-nge-progression.idempotent-experience-removal"

Assert-Contract ($databaseLoad.Contains("onClientAboutToLoad();") -and
    $databaseLoad.Contains("setupSkillData();") -and
    $databaseLoad.IndexOf("onClientAboutToLoad();", [StringComparison]::Ordinal) -lt
        $databaseLoad.IndexOf("setupSkillData();", [StringComparison]::Ordinal) -and
    $setup.Contains("m_modMap.clear();") -and $setup.Contains("clearCommands();") -and
    $setup.Contains("playerObject->clearSchematics();") -and $setup.Contains("recalculateLevel();")) `
    "p14.persisted-nge-skills.clean-set-rebuild"

$grant = Get-FunctionSlice $cpp "const bool CreatureObject::grantSkill(" "void CreatureObject::revokeSkill("
$experienceGrant = Get-FunctionSlice $cpp "const int CreatureObject::grantExperiencePoints(" "const bool CreatureObject::grantSkill("
$expertise = Get-FunctionSlice $cpp "bool CreatureObject::processExpertiseRequest(" "bool CreatureObject::clearAllExpertises()"
Assert-Contract ($grant.Contains("isRetiredNgeProgressionSkillName") -and $grant.Contains("return false;") -and
    $expertise.Contains("Rejected retired NGE expertise request") -and $expertise.Contains("return false;")) `
    "p14.persisted-nge-skills.future-grants-contained"

Assert-Contract ($experienceGrant.Contains("amount > 0") -and
    $experienceGrant.Contains("isRetiredNgeProgressionExperienceType(experienceType)") -and
    $experienceGrant.Contains("return 0;") -and
    $experienceGrant.IndexOf("isRetiredNgeProgressionExperienceType", [StringComparison]::Ordinal) -lt
        $experienceGrant.IndexOf("playerObject->grantExperiencePoints", [StringComparison]::Ordinal)) `
    "p14.persisted-nge-progression.native-positive-admission"

$xpPredicate = Get-FunctionSlice $xp "public static boolean isRetiredNgeProgressionExperienceType(" "public static int grant("
$sharedGuard = "amt > 0 && isPlayer(target) && isRetiredNgeProgressionExperienceType(xp_type)"
Assert-Contract ($xpPredicate.Contains('xpType.equals("chronicles")') -and
    ([regex]::Matches($xp, [regex]::Escape($sharedGuard))).Count -eq 3) `
    "p14.persisted-nge-progression.shared-xp-admission"

$chroniclesGrant = Get-FunctionSlice $pgc "public static int grantChronicleXp(" "public static int getConfigModifiedChroniclesXPAmount("
$chroniclesLevel = Get-FunctionSlice $pgc "public static void checkForGainedChroniclesLevel(" "public static void reportChronicleXPRequiredForNextSkill("
Assert-Contract ($chroniclesGrant.Contains("xp.isRetiredNgeProgressionExperienceType(PGC_CHRONICLES_XP_TYPE)") -and
    $chroniclesGrant.IndexOf("return 0;", [StringComparison]::Ordinal) -lt
        $chroniclesGrant.IndexOf("skill_template.getSkillTemplateSkillsByTemplateName", [StringComparison]::Ordinal) -and
    $chroniclesLevel.Contains("xp.isRetiredNgeProgressionExperienceType(PGC_CHRONICLES_XP_TYPE)") -and
    $chroniclesLevel.IndexOf("return;", [StringComparison]::Ordinal) -lt
        $chroniclesLevel.IndexOf("skill_template.getSkillTemplateSkillsByTemplateName", [StringComparison]::Ordinal)) `
    "p14.persisted-nge-progression.chronicles-entrypoints"

$transfer = Get-FunctionSlice $basePlayer "public int OnDownloadCharacter(" "public int ctsIsValid"
Assert-Contract ($transfer.Contains("expValue > 0 && xp.isRetiredNgeProgressionExperienceType(expType)") -and
    $transfer.Contains("ignored retired NGE progression experience") -and
    $transfer.IndexOf("xp.isRetiredNgeProgressionExperienceType(expType)", [StringComparison]::Ordinal) -lt
        $transfer.IndexOf("grantExperiencePoints(self, expType, expValue)", [StringComparison]::Ordinal)) `
    "p14.persisted-nge-progression.character-transfer-admission"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.persisted-nge-skills.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 persisted NGE skill retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14 persisted NGE skill retirement passed."
