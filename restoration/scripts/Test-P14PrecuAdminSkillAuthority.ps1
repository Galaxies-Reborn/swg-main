[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build",
    [string]$Container = "swg-precu"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuAdminSkillAuthority)) -Raw | ConvertFrom-Json
$professionContract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-profession-root-closure.json") -Raw | ConvertFrom-Json

function Get-SourceText([string]$ContractProperty)
{
    $relative = [string]$contract.sourceFiles.$ContractProperty
    if ([string]::IsNullOrWhiteSpace($relative)) { throw "Missing source mapping: $ContractProperty" }
    return Get-Content -LiteralPath (Join-Path $root $relative) -Raw
}
function Get-Slice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Could not find source marker: $StartMarker" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Could not find source marker: $EndMarker" }
    return $Text.Substring($start, $end - $start)
}
function Assert-Contains([string]$Text, [string[]]$Required, [string]$Surface)
{
    foreach ($value in $Required)
    {
        if (-not $Text.Contains($value)) { throw "$Surface is missing required PRE-CU authority: $value" }
    }
}
function Assert-Excludes([string]$Text, [string[]]$Forbidden, [string]$Surface)
{
    foreach ($value in $Forbidden)
    {
        if ($Text.Contains($value)) { throw "$Surface retains NGE progression authority: $value" }
    }
}

$skill = Get-SourceText "skillLibrary"
$xpLibrary = Get-SourceText "xpLibrary"
$qaLibrary = Get-SourceText "qaLibrary"
$gm = Get-SourceText "gmLibrary"
$gmCommand = Get-SourceText "gmCommand"
$playerUtility = Get-SourceText "playerUtility"
$characterBuilder = Get-SourceText "characterBuilder"
$qaTool = Get-SourceText "qaTool"
$qaProfession = Get-SourceText "qaProfession"
$qaScript = Get-SourceText "qaScript"
$qaSetup = Get-SourceText "qaSetup"
$qaCharacter = Get-SourceText "qaCharacter"
$qaXp = Get-SourceText "qaXp"
$qaItem = Get-SourceText "qaItem"
$qaNge = Get-SourceText "qaNge"
$betaXpTerminal = Get-SourceText "betaXpTerminal"
$betaJedi = Get-SourceText "betaJedi"

$rootConstant = Get-Slice $skill `
    "public static final String[] PRECU_PUBLIC_PROFESSION_ROOTS" `
    "public static boolean isRetiredNgeProgressionSkillName"
$codeRoots = @([regex]::Matches($rootConstant, '"([a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
$expectedRoots = @($professionContract.publish14Evidence.searchableRoots)
if ($codeRoots.Count -ne 33 -or ($codeRoots -join "`n") -cne ($expectedRoots -join "`n"))
{
    throw "Admin profession roots do not exactly match the authenticated 33 public Publish 14.1 roots."
}

$skillTablePath = Join-Path $root ([string]$contract.sourceFiles.skillTable)
$skillTableLines = Get-Content -LiteralPath $skillTablePath
$rows = @(@($skillTableLines[0]) + @($skillTableLines | Select-Object -Skip 2) | ConvertFrom-Csv -Delimiter "`t")
$tableRoots = @($rows | Where-Object {
    $expectedRoots -ccontains [string]$_.NAME -and
    $_.IS_PROFESSION -eq "1" -and $_.GOD_ONLY -eq "0" -and
    $_.IS_HIDDEN -eq "0" -and $_.SEARCHABLE -eq "1"
} | ForEach-Object { $_.NAME } | Sort-Object)
if ($tableRoots.Count -ne 33 -or ($tableRoots -join "`n") -cne (($expectedRoots | Sort-Object) -join "`n"))
{
    throw "The direct skill table no longer exposes exactly the authenticated 33 public profession roots."
}
$boxCount = 0
foreach ($professionRoot in $expectedRoots)
{
    $boxes = @($rows | Where-Object {
        $_.NAME.StartsWith($professionRoot + "_", [StringComparison]::Ordinal) -and
        $_.NAME -notlike "*_prereq*" -and $_.GOD_ONLY -eq "0" -and
        $_.IS_HIDDEN -eq "0" -and $_.SEARCHABLE -eq "1"
    })
    if ($boxes.Count -ne 18 -or
        $boxes.NAME -notcontains ($professionRoot + "_novice") -or
        $boxes.NAME -notcontains ($professionRoot + "_master"))
    {
        throw "Unexpected PRE-CU skill-box shape for $professionRoot."
    }
    $boxCount += $boxes.Count
}
if ($boxCount -ne 594) { throw "The canonical public PRE-CU skill-box total is no longer 594." }
$precuXpTypes = @($rows | Where-Object {
    $skillName = [string]$_.NAME
    $isPublicProfessionSkill = $false
    foreach ($professionRoot in $expectedRoots)
    {
        if ($skillName.StartsWith($professionRoot + "_", [StringComparison]::Ordinal))
        {
            $isPublicProfessionSkill = $true
            break
        }
    }
    $isPublicProfessionSkill -and $_.GOD_ONLY -eq "0" -and
        $_.IS_HIDDEN -eq "0" -and $_.SEARCHABLE -eq "1" -and
        -not [string]::IsNullOrWhiteSpace([string]$_.XP_TYPE)
} | ForEach-Object { [string]$_.XP_TYPE } | Sort-Object -Unique)
if ($precuXpTypes.Count -ne [int]$contract.expected.precuGroundXpPools)
{
    throw "The canonical public PRE-CU ground-XP pool total is no longer $($contract.expected.precuGroundXpPools)."
}
$precuXpCatalog = Get-Slice $xpLibrary `
    "public static String[] getPrecuProgressionExperienceTypes" `
    "public static void checkAndUpdateHuntingMissions"
Assert-Contains $precuXpCatalog @(
    "skill.getPrecuPublicProfessionRoots()",
    "skill.getPrecuProfessionSkillList(",
    "skill_template.getSkillExperienceType(",
    "public static boolean isPrecuProgressionExperienceType(",
    "public static String getPrecuProgressionExperienceAccessError(",
    "space_flags.isImperialPilot(player)",
    "space_flags.isRebelPilot(player)",
    "space_flags.isNeutralPilot(player)"
) "canonical PRE-CU XP catalog"
Assert-Excludes $precuXpCatalog @(
    "dataTableGetStringColumnNoDefaults(TBL_SKILL",
    "QUEST_COMBAT",
    "QUEST_CRAFTING",
    "QUEST_SOCIAL",
    "QUEST_GENERAL",
    "COMBAT_GENERAL"
) "canonical PRE-CU XP catalog"
if ($xpLibrary.Contains("public static String[] getXpTypes("))
{
    throw "The broad all-skill-table XP catalog remains available."
}
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$catalogConsumers = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter "*.java" | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw).Contains("xp.getPrecuProgressionExperienceTypes(")
} | ForEach-Object {
    $_.FullName.Substring($scriptRoot.Length + 1).Replace("\", "/")
} | Sort-Object)
$expectedCatalogConsumers = @(
    "beta/terminal_xp.java",
    "gm/cmd.java",
    "test/qaxp.java"
)
if ($catalogConsumers.Count -ne [int]$contract.expected.canonicalPrecuXpCatalogConsumers -or
    ($catalogConsumers -join "`n") -cne ($expectedCatalogConsumers -join "`n"))
{
    throw "Canonical PRE-CU XP catalog consumer inventory changed."
}
if (@(Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter "*.java" | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw).Contains("getXpTypes(")
}).Count -ne 0)
{
    throw "A broad XP catalog reference remains in direct source."
}

$professionHelpers = Get-Slice $skill `
    "public static String[] getPrecuPublicProfessionRoots" `
    "public static boolean purchaseSkill"
Assert-Contains $professionHelpers @(
    'dataTableGetStringColumnNoDefaults(TBL_SKILL, "NAME")',
    'dataTableGetInt(TBL_SKILL, row, "GOD_ONLY") != 0',
    'dataTableGetInt(TBL_SKILL, row, "IS_HIDDEN") != 0',
    'dataTableGetInt(TBL_SKILL, row, "SEARCHABLE") != 1',
    "collectPrecuSkillPrerequisites(player, prerequisite, orderedSkills, visitedSkills)",
    "pointsRequired > getAvailableSkillPoints(player)",
    "grantSkillToPlayer(player, (String)orderedSkill)",
    "purchaseSkill(player, skillName)",
    'setWorkingSkill(player, "")',
    "recalcPlayerPools(player, true)"
) "PRE-CU skill helper"
Assert-Excludes $professionHelpers @(
    "setSkillTemplate(",
    "autoLevelPlayer(",
    "autoAllocateExpertiseByLevel(",
    "fullExpertiseReset(",
    "skill_template.TEMPLATE_TABLE",
    "grantRoadmapItem("
) "PRE-CU skill helper"
if (-not $skill.Contains("public static final int SKILL_POINT_CAP = 250;"))
{
    throw "The PRE-CU 250-point cap is missing."
}

Assert-Contains $gm @(
    "public static final String[] PRECU_SKILL_OPTIONS",
    "Select PRE-CU Skill Box",
    "Earn Current PRE-CU Skill",
    "return skill.getPrecuPublicProfessionRoots();",
    'newList[i] = "@skl_n:" + list[i] + "_novice";'
) "GM skill menu"
Assert-Excludes $gm @("ROADMAP_SKILL_OPTIONS", "getRoadmapList", "convertRoadmapNames", "@ui_roadmap:") "GM skill menu"
if (-not $gmCommand.Contains("gm.PRECU_SKILL_OPTIONS")) { throw "The GM command does not open the PRE-CU skill menu." }

$gmSurface = Get-Slice $playerUtility `
    "public int handleGmGrantSkillOptions" `
    "public int cmdAutoDeclineDuel"
Assert-Contains $gmSurface @(
    "gm.getPrecuProfessionList()",
    "skill.getPrecuProfessionSkillList(",
    "skill.grantPrecuSkillWithPrerequisites(",
    "skill.purchaseWorkingPrecuSkillForTesting(",
    "gm.PRECU_SKILL_OPTIONS"
) "GM progression surface"
Assert-Excludes $gmSurface @(
    "Roadmap",
    "roadmap",
    "setSkillTemplate(",
    "autoLevelPlayer(",
    "skill_template.",
    "respec.",
    "grantSkill(target"
) "GM progression surface"

$builderSurface = Get-Slice $characterBuilder `
    "public void handlePrecuSkills" `
    "public void handlePetAbilityOption"
Assert-Contains $builderSurface @(
    "gm.getPrecuProfessionList()",
    "skill.getPrecuProfessionSkillList(",
    "skill.grantPrecuSkillWithPrerequisites(",
    "skill.purchaseWorkingPrecuSkillForTesting(",
    "PRECU_SKILL_OPTIONS"
) "test-center skill surface"
Assert-Excludes $builderSurface @(
    "Roadmap",
    "roadmap",
    "setSkillTemplate(",
    "autoLevelPlayer(",
    "autoAllocateExpertiseByLevel(",
    "fullExpertiseReset(",
    "revokeAllSkills(",
    "skill_template."
) "test-center skill surface"
Assert-Excludes $characterBuilder @(
    "getSkillTemplate(",
    "setSkillTemplate(",
    "autoLevelPlayer(",
    "autoAllocateExpertiseByLevel(",
    "fullExpertiseReset(",
    "revokeAllSkills("
) "complete test-center source"
$publishOptions = Get-Slice $characterBuilder `
    "public int handlePublishOptions" `
    "public void flagAllHeroicInstances"
Assert-Contains $publishOptions @(
    "PUB27_HEAVYPACK",
    "generateGenerationSabers(",
    "PUB27_TRAPS",
    "PRE-CU skills were not changed",
    "Jedi gear issued"
) "test-center Publish content surface"
Assert-Excludes $publishOptions @(
    "getSkillTemplate(",
    "setSkillTemplate(",
    "autoLevelPlayer(",
    "fullExpertiseReset(",
    "revokeAllSkills(",
    "grantExperiencePoints(",
    "setWorkingSkill("
) "test-center Publish content surface"

$gmXpSurface = Get-Slice $gmCommand `
    "public int cmdSetExperience" `
    "public void showSetExperienceSyntax"
Assert-Contains $gmXpSurface @(
    "xp.getPrecuProgressionExperienceTypes()",
    "xp.isPrecuProgressionExperienceType(xp_type)",
    "xp.grantUnmodifiedExperience(",
    "PRE-CU XP TYPES",
    "Canonical Publish 14.1 skill XP pools"
) "GM set-experience surface"
Assert-Excludes $gmXpSurface @(
    "xp.getXpTypes(",
    "dataTableGetStringColumn",
    "combat_general",
    "quest_combat",
    "quest_crafting",
    "quest_social",
    "quest_general"
) "GM set-experience surface"

$qaXpRouteCount = ([regex]::Matches($qaTool, [regex]::Escape("qaxp.toolMainMenu("))).Count
if ($qaXpRouteCount -ne [int]$contract.expected.qaXpCanonicalEntryPoints)
{
    throw "The QA tool does not expose exactly two canonical PRE-CU XP entry points."
}
Assert-Excludes $qaTool @(
    "XP_TOOL_MENU",
    "Beta XP Dispenser",
    "xp.getXpTypes(",
    "initializeXpTool(",
    "setXpTypesScriptVar(",
    '"combat_general"',
    '"quest_combat"',
    '"quest_crafting"',
    '"quest_social"',
    '"quest_general"'
) "complete QA XP routing source"
Assert-Excludes $qaLibrary @(
    "public static void revokeAllSkills(",
    'grantExperiencePoints(player, "combat_general"',
    'setSkillTemplate(player, "")'
) "shared QA library"

$qaSpec = Get-Slice $qaTool `
    "public boolean precuSpecTester" `
    "public boolean retiredNgeSpecTester"
Assert-Contains $qaSpec @(
    "skill.grantPrecuSkillWithPrerequisites(self, skillName)",
    "st.hasMoreTokens()",
    "PRE-CU skill box and missing prerequisites granted"
) "QA spec surface"
Assert-Excludes $qaSpec @("setSkillTemplate(", "autoLevelPlayer(", "expertise", "Roadmap", "roadmap") "QA spec surface"
$retiredSpec = Get-Slice $qaTool `
    "public boolean retiredNgeSpecTester" `
    "public boolean mulipleStaticSpawn"
Assert-Contains $retiredSpec @(
    "NGE class, level, and roadmap mutation is retired",
    "return false;"
) "retired QA NGE spec surface"
Assert-Excludes $retiredSpec @(
    "setSkillTemplate(",
    "getLevel(",
    "grantExperiencePoints(",
    "grantSkillToPlayer(",
    "revokeAllSkills(",
    "spawnItems(",
    "attainCorrectFaction"
) "retired QA NGE spec surface"
Assert-Excludes $qaTool @(
    "utils.fullExpertiseReset(",
    'grantSkill(self, "expertise")',
    'attachScript(self, "test.qaprofession")',
    "qaprofession.mainMenu",
    "PROFESSION_TOOL_MENU",
    "setSkillTemplate(",
    "autoLevelPlayer(",
    "getLevel("
) "complete QA tool source"
if (([regex]::Matches($qaTool, '\bretiredNgeSpecTester\s*\(')).Count -ne 1 -or
    $qaTool.Contains('attachScript(self, "test.qange")') -or
    $qaTool.Contains('"handleGiveRespecItem"'))
{
    throw "A reachable QA NGE spec or respec route remains."
}
if ($qaScript.Contains('"test.qange"') -or
    $qaScript.Contains('"test.qasetup"') -or
    $qaScript.Contains('"test.qaprofession"'))
{
    throw "The QA script menu still offers retired NGE setup scripts."
}

Assert-Contains $qaXp @(
    "public static void toolMainMenu(",
    "xp.getPrecuProgressionExperienceTypes()",
    "xp.isPrecuProgressionExperienceType(",
    "xp.getPrecuProgressionExperienceAccessError(",
    "skill_template.getSkillExperienceType(",
    "skill.isPrecuPublicProfessionSkillName(",
    "obj_id player = self;",
    "xp.grant(player, xpType, amt, false)",
    "xp.grantUnmodifiedExperience(player, xpType, -amt, false)",
    "PRE-CU XP Tool"
) "reachable QA XP tool"
Assert-Excludes $qaXp @(
    "getSkillTemplate(",
    "grantXpByTemplate(",
    "getPrecuXpTypes(",
    "qa.findTarget(",
    "XP_QUEST",
    "xp.NON_COMBAT",
    "setSkillTemplate(",
    "autoLevelPlayer("
) "reachable QA XP tool"
$pilotPrestigePools = @([regex]::Matches($precuXpCatalog, 'SPACE_PRESTIGE_([A-Z_]+)') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if ($pilotPrestigePools.Count -ne [int]$contract.expected.retainedPilotPrestigePools)
{
    throw "The reachable QA XP tool does not retain exactly three explicit pilot prestige pools."
}

Assert-Contains $betaXpTerminal @(
    "PRE-CU XP Dispenser",
    "xp.getPrecuProgressionExperienceTypes()",
    "xp.getPrecuProgressionExperienceAccessError(",
    "utils.setScriptVar(player, VAR_DESIRED_XP_TYPE, xpType)",
    "utils.removeScriptVar(player, VAR_DESIRED_XP_TYPE)",
    "xp.grant(player, xpType, amt, false)",
    "isAuthorizedPlayer(player)"
) "beta XP terminal"
Assert-Excludes $betaXpTerminal @(
    "Beta XP Dispenser",
    "xp.getXpTypes(",
    "getStringObjVar(player, VAR_DESIRED_XP_TYPE)",
    "setObjVar(player, VAR_DESIRED_XP_TYPE",
    "grantExperiencePoints("
) "beta XP terminal"

Assert-Contains $qaItem @(
    "Get Later-Content Item Packs",
    'ITEM_REWARD_TABLE = "datatables/roadmap/item_rewards.iff"',
    "getAllEquipmentOfType(self, searchInt)",
    "buildTheSUI(self, allRowsOfEquipment)",
    "getArmorList(player)"
) "reachable QA item tool"
Assert-Excludes $qaItem @(
    "getSkillTemplate(",
    "getLevel(",
    '"required_level"',
    "getAllEquipmentOfProfession(",
    "getAllEquipmentOfCombatLevelOrBelow(",
    "getHighestTierItems(",
    "handleLevelOptions(",
    "getLevelsToDisplay(",
    "armorLevelMenu"
) "reachable QA item tool"

$qaStubs = [ordered]@{
    "QA level-90 setup" = [pscustomobject]@{ Text=$qaSetup; Class="qasetup"; Script="test.qasetup"; Message="NGE level-90 and expertise setup tool is retired" }
    "QA class/template setup" = [pscustomobject]@{ Text=$qaCharacter; Class="qa_character"; Script="test.qa_character"; Message="NGE class/template setup tool is retired" }
    "QA profession/roadmap assistant" = [pscustomobject]@{ Text=$qaProfession; Class="qaprofession"; Script="test.qaprofession"; Message="NGE profession and roadmap assistant is retired" }
    "QA combat-level respec" = [pscustomobject]@{ Text=$qaNge; Class="qange"; Script="test.qange"; Message="NGE combat-level respec tool is retired" }
}
if ($qaStubs.Count -ne [int]$contract.expected.minimalFailClosedQaStubs)
{
    throw "The fail-closed QA compatibility-stub inventory changed."
}
foreach ($entry in $qaStubs.GetEnumerator())
{
    Assert-Contains $entry.Value.Text @(
        ("public class " + $entry.Value.Class + " extends script.base_script"),
        "public int OnAttach",
        ('detachScript(self, "' + $entry.Value.Script + '");'),
        $entry.Value.Message,
        "/qatool spec <PRE-CU skill box>",
        "return SCRIPT_CONTINUE;"
    ) $entry.Key
    Assert-Excludes $entry.Value.Text @(
        "isGod(",
        "getGodLevel(",
        "attachScript(",
        "setSkillTemplate(",
        "autoLevelPlayer(",
        "autoAllocateExpertiseByLevel(",
        "fullExpertiseReset(",
        "grantSkillToPlayer(",
        "dataTable"
    ) $entry.Key
    if (([regex]::Matches($entry.Value.Text, '\bpublic int\s+')).Count -ne 1)
    {
        throw "$($entry.Key) is not a minimal fail-closed compatibility stub."
    }
    $lineCount = ($entry.Value.Text.TrimEnd("`r", "`n") -split "\r?\n").Count
    if ($lineCount -ne [int]$contract.expected.qaStubLinesEach)
    {
        throw "$($entry.Key) is not the expected minimal line count."
    }
}

Assert-Contains $betaJedi @(
    "public class tc_jedi extends script.base_script",
    "public int OnAttach",
    "public int OnInitialize",
    'detachScript(self, "beta.tc_jedi");',
    "The NGE Jedi conversion is retired",
    "PRE-CU Jedi progression is preserved"
) "beta Jedi conversion stub"
Assert-Excludes $betaJedi @(
    "revokeSkills(",
    "revokeExperience(",
    "grantExperiencePoints(",
    "getXpTypes(",
    "player.player_jedi_conversion",
    "jedi.totalPoints",
    "attachScript("
) "beta Jedi conversion stub"
if (([regex]::Matches($betaJedi, '\bpublic int\s+')).Count -ne 2)
{
    throw "The beta Jedi conversion identity is not a minimal two-lifecycle fail-closed stub."
}

if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "PRE-CU admin skill runtime evidence is not ready."
    }
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    $checkedOutDsrcCommit = (& git -C (Join-Path $root "dsrc") rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $dsrcPin.Count -ne 1 -or
        [string]$dsrcPin[0].commit -cne [string]$contract.buildEvidence.directSourceGitlink -or
        $checkedOutDsrcCommit -cne [string]$contract.buildEvidence.directSourceGitlink)
    {
        throw "PRE-CU admin skill authority is not pinned to the checked-out direct dsrc commit."
    }
    foreach ($property in $contract.sourceFiles.PSObject.Properties)
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root ([string]$property.Value))).Hash.ToLowerInvariant()
        if ($actual -ne [string]$contract.buildEvidence.sourceSha256.($property.Name))
        {
            throw "PRE-CU admin source evidence mismatch: $($property.Name)"
        }
    }
    $classRoot = [string]$contract.buildEvidence.compiledClassRoot
    $classFiles = @($contract.compiledClasses.PSObject.Properties)
    if ($classFiles.Count -ne 17) { throw "PRE-CU admin compiled-class inventory is incomplete." }
    foreach ($property in $classFiles)
    {
        $classPath = $classRoot + "/" + [string]$property.Value
        $hashOutput = (& docker exec $Container sha256sum $classPath).Trim()
        if ($LASTEXITCODE -ne 0) { throw "Unable to hash deployed class: $($property.Name)" }
        $actualHash = ($hashOutput -split '\s+')[0]
        $actualBytes = [int64]((& docker exec $Container stat -c "%s" $classPath).Trim())
        if ($LASTEXITCODE -ne 0 -or
            $actualHash -cne [string]$contract.buildEvidence.classSha256.($property.Name) -or
            $actualBytes -ne [int64]$contract.buildEvidence.classBytes.($property.Name))
        {
            throw "PRE-CU admin compiled-class evidence mismatch: $($property.Name)"
        }
    }
    $classCount = @(& docker exec $Container find ($classRoot + "/script") -type f -name "*.class").Count
    $sourceCount = @(& docker exec $Container find "/swg-precu-source/dsrc/sku.0/sys.server/compiled/game/script" -type f -name "*.java").Count
    if ($classCount -ne [int]$contract.buildEvidence.javaClassesEmitted -or
        $sourceCount -ne [int]$contract.buildEvidence.javaSourcesCompiled)
    {
        throw "Canonical clean Java source/class counts do not match deployed evidence."
    }
    foreach ($property in $contract.sourceFiles.PSObject.Properties)
    {
        $relative = ([string]$property.Value).Substring(5).Replace('\', '/')
        & docker exec $Container cmp -s ("/swg-precu-source/dsrc/" + $relative) ("/swg-precu/dsrc/" + $relative)
        if ($LASTEXITCODE -ne 0) { throw "Direct/work source parity mismatch: $($property.Name)" }
    }
    $skillBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.library.skill | Out-String)
    $xpLibraryBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.library.xp | Out-String)
    $qaLibraryBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.library.qa | Out-String)
    Assert-Contains $skillBytecode @(
        "collectPrecuSkillPrerequisites",
        "getAvailableSkillPoints",
        "grantSkillToPlayer",
        "purchaseSkill"
    ) "deployed PRE-CU skill bytecode"
    Assert-Contains $xpLibraryBytecode @(
        "getPrecuProgressionExperienceTypes",
        "isPrecuProgressionExperienceType",
        "getPrecuProgressionExperienceAccessError",
        "getPrecuPublicProfessionRoots:",
        "getPrecuProfessionSkillList:",
        "getSkillExperienceType:",
        "prestige_imperial",
        "prestige_rebel",
        "prestige_pilot"
    ) "deployed canonical PRE-CU XP catalog bytecode"
    Assert-Excludes $xpLibraryBytecode @(
        "public static java.lang.String[] getXpTypes("
    ) "deployed canonical PRE-CU XP catalog bytecode"
    $playerUtilityBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.player.player_utility | Out-String)
    $gmCommandBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.gm.cmd | Out-String)
    $builderBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.terminal.terminal_character_builder | Out-String)
    $qaToolBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.test.qatool | Out-String)
    $qaXpBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.test.qaxp | Out-String)
    $qaItemBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.test.qaitem | Out-String)
    $qaNgeBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.test.qange | Out-String)
    $betaXpTerminalBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.beta.terminal_xp | Out-String)
    $betaJediBytecode = (& docker exec $Container javap -classpath $classRoot -c -p script.beta.tc_jedi | Out-String)
    foreach ($entry in @{
        "deployed GM bytecode" = $playerUtilityBytecode
        "deployed test-center bytecode" = $builderBytecode
        "deployed QA spec bytecode" = $qaToolBytecode
    }.GetEnumerator())
    {
        Assert-Contains $entry.Value @("grantPrecuSkillWithPrerequisites") $entry.Key
    }
    Assert-Contains $playerUtilityBytecode @("purchaseWorkingPrecuSkillForTesting", "getPrecuProfessionSkillList") "deployed GM bytecode"
    Assert-Contains $builderBytecode @("purchaseWorkingPrecuSkillForTesting", "getPrecuProfessionSkillList") "deployed test-center bytecode"
    Assert-Excludes $builderBytecode @(
        "getSkillTemplate:",
        "setSkillTemplate:",
        "autoLevelPlayer:",
        "autoAllocateExpertiseByLevel:",
        "fullExpertiseReset:",
        "revokeAllSkills:"
    ) "complete deployed test-center bytecode"
    Assert-Excludes $qaToolBytecode @(
        "setSkillTemplate:",
        "autoLevelPlayer:",
        "fullExpertiseReset:",
        "getLevel:"
    ) "complete deployed QA tool bytecode"
    Assert-Contains $qaToolBytecode @(
        "script/test/qaxp.toolMainMenu:"
    ) "deployed QA XP routing bytecode"
    Assert-Excludes $qaToolBytecode @(
        "Beta XP Dispenser",
        "XP_TOOL_MENU",
        "getXpTypes:"
    ) "deployed QA XP routing bytecode"
    Assert-Contains $gmCommandBytecode @(
        "getPrecuProgressionExperienceTypes:",
        "isPrecuProgressionExperienceType:",
        "grantUnmodifiedExperience:",
        "PRE-CU XP TYPES"
    ) "deployed GM set-experience bytecode"
    Assert-Excludes $gmCommandBytecode @(
        "getXpTypes:"
    ) "deployed GM set-experience bytecode"
    Assert-Excludes $qaLibraryBytecode @(
        "public static void revokeAllSkills("
    ) "deployed shared QA library bytecode"
    if (([regex]::Matches($qaToolBytecode, "Method retiredNgeSpecTester")).Count -ne 0)
    {
        throw "Deployed QA bytecode calls the retired NGE spec implementation."
    }
    Assert-Contains $qaXpBytecode @(
        "getPrecuProgressionExperienceTypes:",
        "isPrecuProgressionExperienceType:",
        "getPrecuProgressionExperienceAccessError:",
        "getSkillExperienceType:",
        "isPrecuPublicProfessionSkillName:",
        "script/library/xp.grant:",
        "script/library/xp.grantUnmodifiedExperience:",
        "PRE-CU XP Tool"
    ) "deployed QA XP bytecode"
    Assert-Excludes $qaXpBytecode @(
        "getSkillTemplate:",
        "grantXpByTemplate:",
        "setSkillTemplate:",
        "autoLevelPlayer:",
        "getXpTypes:",
        "getPrecuXpTypes:",
        "XP_QUEST",
        "NON_COMBAT"
    ) "deployed QA XP bytecode"
    Assert-Contains $betaXpTerminalBytecode @(
        "PRE-CU XP Dispenser",
        "getPrecuProgressionExperienceTypes:",
        "getPrecuProgressionExperienceAccessError:",
        "setScriptVar:",
        "removeScriptVar:",
        "script/library/xp.grant:"
    ) "deployed beta XP terminal bytecode"
    Assert-Excludes $betaXpTerminalBytecode @(
        "Beta XP Dispenser",
        "getXpTypes:",
        "setObjVar:",
        "getStringObjVar:"
    ) "deployed beta XP terminal bytecode"
    Assert-Contains $qaItemBytecode @(
        "Get Later-Content Item Packs",
        "datatables/roadmap/item_rewards.iff",
        "getAllEquipmentOfType:",
        "buildTheSUI:",
        "getArmorList:"
    ) "deployed QA item bytecode"
    Assert-Excludes $qaItemBytecode @(
        "getSkillTemplate:",
        "getLevel:",
        "required_level",
        "getAllEquipmentOfProfession:",
        "getAllEquipmentOfCombatLevelOrBelow:",
        "getHighestTierItems:",
        "handleLevelOptions:",
        "getLevelsToDisplay:",
        "armorLevelMenu"
    ) "deployed QA item bytecode"
    foreach ($className in @("script.test.qasetup", "script.test.qa_character", "script.test.qaprofession", "script.test.qange"))
    {
        $bytecode = (& docker exec $Container javap -classpath $classRoot -c -p $className | Out-String)
        Assert-Contains $bytecode @("public int OnAttach", "detachScript", "/qatool spec <PRE-CU skill box>") "deployed $className stub"
        Assert-Excludes $bytecode @(
            "OnSpeaking",
            "setSkillTemplate",
            "autoLevelPlayer",
            "autoAllocateExpertiseByLevel",
            "fullExpertiseReset",
            "grantSkillToPlayer",
            "dataTable"
        ) "deployed $className stub"
    }
    Assert-Contains $betaJediBytecode @(
        "public int OnAttach",
        "public int OnInitialize",
        "detachScript",
        "The NGE Jedi conversion is retired",
        "PRE-CU Jedi progression is preserved"
    ) "deployed beta Jedi conversion stub"
    Assert-Excludes $betaJediBytecode @(
        "revokeSkills",
        "revokeExperience",
        "grantExperiencePoints",
        "getXpTypes",
        "player_jedi_conversion",
        "jedi.totalPoints",
        "attachScript"
    ) "deployed beta Jedi conversion stub"
    $state = (& docker inspect --format "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $Container).Trim()
    if ($LASTEXITCODE -ne 0 -or $state -cne "running healthy")
    {
        throw "PRE-CU x64 server is not running and healthy."
    }
    $processNames = @(& docker exec $Container ps -eo comm= | ForEach-Object { $_.Trim() })
    foreach ($property in $contract.runtimeEvidence.processCounts.PSObject.Properties)
    {
        $expectedName = [string]$property.Name
        $commName = $expectedName.Substring(0, [Math]::Min(15, $expectedName.Length))
        $actualCount = @($processNames | Where-Object { $_ -ceq $commName }).Count
        if ($actualCount -ne [int]$property.Value)
        {
            throw "Unexpected deployed process count: $($property.Name)=$actualCount"
        }
    }
    $logs = (& docker logs --since ([string]$contract.runtimeEvidence.containerStartedAt) $Container 2>&1 | Out-String)
    if (([regex]::Matches($logs, [regex]::Escape("Cluster swg is ready for players."))).Count -ne 1 -or
        $logs -match '(?i)fatal|severe|exception|\berror\b|ConGenericMessage constructed with empty message|undefined symbol|symbol lookup error|ABI|ORA-[0-9]+|segmentation fault|core dumped')
    {
        throw "Fresh deployed server logs do not match the clean player-ready evidence."
    }
}
Write-Host "Publish 14.1 PRE-CU admin skill authority contract passed."
