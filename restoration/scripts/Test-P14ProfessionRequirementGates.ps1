[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    "contracts/p14-profession-requirement-gates.json") -Raw | ConvertFrom-Json
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$paths = @(
    "library/utils.java",
    "library/content.java",
    "library/static_item.java",
    "item/armor/dynamic_armor.java",
    "item/static_item_base.java",
    "item/skillmod_click_item.java",
    "item/loot_schematic/loot_schematic.java"
)
$texts = @{}
foreach ($relative in $paths)
{
    $path = Join-Path $scriptRoot $relative
    $source = Get-Content -LiteralPath $path -Raw
    $texts[$relative] = $source
    if ($relative -ne "library/utils.java" -and $source.Contains("getSkillTemplate("))
    {
        throw "Direct class-template requirement remains in $relative"
    }
}
$utils = [string]$texts["library/utils.java"]
foreach ($required in @(
    "meetsProfessionRequirement",
    "hasSkill(player, requirement)",
    'requirement.equals("trader")',
    'requirement.equals("entertainer")',
    'requirement.equals("spy")',
    "getPrecuProfessionRequirementSkillName"
))
{
    if (-not $utils.Contains($required)) { throw "Missing requirement boundary: $required" }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length,
        [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$professionSlice = Get-FunctionSlice $utils `
    "public static boolean isProfession(" `
    "public static boolean isPrecuRetainedItemClass("
$adapterSlice = Get-FunctionSlice $utils `
    "public static boolean isPrecuRetainedItemClass(" `
    "public static String getPrecuRetainedItemClassName("
$presentationSlice = Get-FunctionSlice $utils `
    "public static String getPrecuProfessionRequirementSkillName(" `
    "public static boolean meetsProfessionRequirement("
$requirementSlice = Get-FunctionSlice $utils `
    "public static boolean meetsProfessionRequirement(" `
    "public static int getPlayerProfession("

if ($professionSlice -notmatch '(?s)case SPY:\s*return false;' -or
    $professionSlice.Contains("outdoors_ranger_novice"))
{
    throw "Global NGE Spy profession identity is no longer fail-closed."
}
if (-not $adapterSlice.Contains("profession == SPY") -or
    -not $adapterSlice.Contains('hasSkill(player, "outdoors_ranger_novice")') -or
    $requirementSlice -notmatch '(?s)requirement[.]equals[(]"spy"[)].*?return isPrecuRetainedItemClass[(]player, SPY[)];')
{
    throw "Named retained Spy item admission does not map locally to PRE-CU Ranger."
}
foreach ($mapping in $contract.expected.namedCompatibilitySkillMappings.PSObject.Properties)
{
    $requirementMarker = 'requirement.equals("{0}")' -f $mapping.Name
    $skillMarker = 'return "{0}";' -f [string]$mapping.Value
    if (-not $presentationSlice.Contains($requirementMarker) -or
        -not $presentationSlice.Contains($skillMarker))
    {
        throw "Missing PRE-CU presentation mapping for '$($mapping.Name)'."
    }
}
if (-not $presentationSlice.Contains("return requirement;"))
{
    throw "Exact Publish 14.1 skill presentation no longer passes through."
}

$presentationConsumers = @(
    "library/static_item.java",
    "item/armor/dynamic_armor.java",
    "item/static_item_base.java",
    "item/loot_schematic/loot_schematic.java"
)
$presentationAdapterCalls = 0
foreach ($relative in $presentationConsumers)
{
    $text = [string]$texts[$relative]
    $presentationAdapterCalls +=
        [regex]::Matches($text, "getPrecuProfessionRequirementSkillName[(]").Count
    if ($text -match 'new string_id[(]"ui_roadmap",\s*(?:requiredSkill|requiredSkillToEquip|skill_req)' -or
        $text -match '"@skl_n:"\s*[+]\s*(?:requiredSkill|requiredSkillToEquip|skill_req)(?:\W|$)')
    {
        throw "NGE Roadmap/raw class presentation remains in $relative."
    }
}
if ($presentationAdapterCalls -ne [int]$contract.expected.presentationAdapterCalls)
{
    throw "Expected $($contract.expected.presentationAdapterCalls) PRE-CU presentation adapters; found $presentationAdapterCalls."
}

$masterItemPath = Join-Path $root `
    "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/master_item.tab"
$masterItemLines = @(Get-Content -LiteralPath $masterItemPath)
$headers = $masterItemLines[0].Split([char]9)
$requiredSkillIndex = [Array]::IndexOf($headers, "required_skill")
if ($requiredSkillIndex -lt 0) { throw "master_item.tab has no required_skill column." }
$actualNamedCounts = @{}
for ($row = 2; $row -lt $masterItemLines.Count; $row++)
{
    if ([string]::IsNullOrWhiteSpace($masterItemLines[$row])) { continue }
    $columns = $masterItemLines[$row].Split([char]9)
    if ($requiredSkillIndex -ge $columns.Length) { continue }
    $requirement = $columns[$requiredSkillIndex]
    if ([string]::IsNullOrWhiteSpace($requirement)) { continue }
    if (-not $actualNamedCounts.ContainsKey($requirement))
    {
        $actualNamedCounts[$requirement] = 0
    }
    $actualNamedCounts[$requirement]++
}
$expectedNamedCounts = $contract.expected.masterItemNamedRequirementCounts
if ($actualNamedCounts.Count -ne @($expectedNamedCounts.PSObject.Properties).Count)
{
    throw "Unexpected named profession-token set in master_item.tab."
}
foreach ($expected in $expectedNamedCounts.PSObject.Properties)
{
    if (-not $actualNamedCounts.ContainsKey($expected.Name) -or
        [int]$actualNamedCounts[$expected.Name] -ne [int]$expected.Value)
    {
        throw "Named requirement count drifted for '$($expected.Name)'."
    }
}

if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    $dsrcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "dsrc" })
    $checkedOutDsrcCommit = (& git -C (Join-Path $root "dsrc") rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $dsrcPin.Count -ne 1 -or
        [string]$dsrcPin[0].commit -cne [string]$contract.buildEvidence.directSourceGitlink -or
        $checkedOutDsrcCommit -cne [string]$contract.buildEvidence.directSourceGitlink)
    {
        throw "Direct-source profession requirement evidence is not pinned to the checked-out dsrc commit."
    }
    foreach ($entry in $contract.sourceFiles.PSObject.Properties)
    {
        $path = Join-Path $root ([string]$entry.Value)
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$entry.Name].Value
        if ($actualHash -cne $expectedHash)
        {
            throw "Profession requirement source hash drifted for '$($entry.Name)'."
        }
    }
}
Write-Host "Publish 14.1 profession requirement gates contract passed."
