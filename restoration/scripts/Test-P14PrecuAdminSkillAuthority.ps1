[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
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
$gm = Get-SourceText "gmLibrary"
$gmCommand = Get-SourceText "gmCommand"
$playerUtility = Get-SourceText "playerUtility"
$characterBuilder = Get-SourceText "characterBuilder"
$qaTool = Get-SourceText "qaTool"
$qaProfession = Get-SourceText "qaProfession"
$qaScript = Get-SourceText "qaScript"
$qaSetup = Get-SourceText "qaSetup"
$qaCharacter = Get-SourceText "qaCharacter"

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
    "public void revokeAllSkills"
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

$qaSpec = Get-Slice $qaTool `
    "public boolean precuSpecTester" `
    "public boolean retiredNgeSpecTester"
Assert-Contains $qaSpec @(
    "skill.grantPrecuSkillWithPrerequisites(self, skillName)",
    "st.hasMoreTokens()",
    "PRE-CU skill box and missing prerequisites granted"
) "QA spec surface"
Assert-Excludes $qaSpec @("setSkillTemplate(", "autoLevelPlayer(", "expertise", "Roadmap", "roadmap") "QA spec surface"
if (([regex]::Matches($qaTool, '\bretiredNgeSpecTester\s*\(')).Count -ne 1 -or
    -not $qaTool.Contains("String[] roadmapList = new String[0];") -or
    $qaTool.Contains('attachScript(self, "test.qange")') -or
    $qaTool.Contains('"handleGiveRespecItem"'))
{
    throw "A reachable QA NGE spec or respec route remains."
}
if ($qaScript.Contains('"test.qange"') -or $qaScript.Contains('"test.qasetup"'))
{
    throw "The QA script menu still offers retired NGE setup scripts."
}

$professionMutation = Get-Slice $qaProfession `
    "public int handleProfessionDetails" `
    "public int handleTraderSelection"
Assert-Contains $professionMutation @("NGE template mastering is retired", "/qatool spec <PRE-CU skill box>") "QA profession mutation surface"
Assert-Excludes $professionMutation @("setSkillTemplate(", "grantSkillToPlayer(", "qa.revokeAllSkills(") "QA profession mutation surface"

foreach ($entry in @{
    "QA level-90 setup" = [pscustomobject]@{ Text=$qaSetup; Next="public int OnSpeaking"; Script="test.qasetup"; Message="NGE level-90 and expertise setup tool is retired" }
    "QA class/template setup" = [pscustomobject]@{ Text=$qaCharacter; Next="public int OnSpeaking"; Script="test.qa_character"; Message="NGE class/template setup tool is retired" }
}.GetEnumerator())
{
    $attach = Get-Slice $entry.Value.Text "public int OnAttach" $entry.Value.Next
    Assert-Contains $attach @(
        ('detachScript(self, "' + $entry.Value.Script + '");'),
        $entry.Value.Message,
        "return SCRIPT_CONTINUE;"
    ) $entry.Key
    Assert-Excludes $attach @("isGod(", "getGodLevel(", "attachScript(") $entry.Key
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
}
Write-Host "Publish 14.1 PRE-CU admin skill authority contract passed."
