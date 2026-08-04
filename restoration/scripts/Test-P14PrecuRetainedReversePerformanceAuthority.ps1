[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuRetainedReversePerformanceAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$texts = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.retained-reverse-performance.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.retained-reverse-performance.source.$($property.Name).authenticated"
}

$tool = [string]$texts.reverseEngineeringTool
$performance = [string]$texts.performance
$skills = [string]$texts.skills
$schematicGroups = [string]$texts.schematicGroups
$powerup = Get-SourceSlice $tool "public void createPowerup(" `
    "public void generatePowerBit("
$powerBit = Get-SourceSlice $tool "public void generatePowerBit(" `
    "public void generateModifierBit("
$upgrade = Get-SourceSlice $tool "public boolean canUpgradeAttachment(" `
    "public String getGemTemplateByClass("
$inspiration = Get-SourceSlice $performance "public static boolean inspire(" `
    "public static boolean performanceTargetedBuffFlourish("
$hologram = Get-SourceSlice $performance "public static boolean hasMaxHolo(" `
    "public static void holographicCleanup("

Assert-Contract (-not $tool.Contains("expertise_") -and
    -not $tool.Contains("getEnhancedSkillStatisticModifierUncapped") -and
    -not $tool.Contains("getReverseEngineeringBonusMultiplier") -and
    -not $tool.Contains("reverseEngineeringBonusMultiplier")) `
    "p14.retained-reverse-performance.reverse-nge-authority.retired"
Assert-Contract ($tool.Contains('"crafting_tailor_novice"') -and
    $tool.Contains('"crafting_armorsmith_novice"') -and
    $tool.Contains('"crafting_weaponsmith_novice"') -and
    $tool.Contains("hasReverseEngineeringSkill") -and
    $tool.Contains("getGemTemplateByClass")) `
    "p14.retained-reverse-performance.novice-admission.preserved"
Assert-Contract ($upgrade.Contains('"crafting_tailor_master"') -or
    ($tool.Contains('"crafting_tailor_master"') -and
     $tool.Contains('"crafting_armorsmith_master"') -and
     $tool.Contains('"crafting_weaponsmith_master"'))) `
    "p14.retained-reverse-performance.master-upgrade-authority"
Assert-Contract ($powerup.Contains('getFloatObjVar(self, "crafting.stationMod")') -and
    $powerup.Contains('getFloatObjVar(self, "res_quality")') -and
    $powerup.Contains("if(power > 117)") -and
    $powerup.Contains("+ 20") -and
    $powerBit.Contains('getFloatObjVar(self, "crafting.stationMod")') -and
    $powerBit.Contains('getFloatObjVar(self, "res_quality")') -and
    $powerBit.Contains("powerResult / maxStat > 1.25f") -and
    $powerBit.Contains("canUpgradeAttachment(player)")) `
    "p14.retained-reverse-performance.authored-item-values.preserved"
Assert-Contract (-not $powerBit.Contains('"luck"') -and
    -not $powerBit.Contains('"luck_modified"')) `
    "p14.retained-reverse-performance.nge-luck-authority.retired"

$requiredSkillRows = @(
    "crafting_tailor_novice", "crafting_tailor_master",
    "crafting_armorsmith_novice", "crafting_armorsmith_master",
    "crafting_weaponsmith_novice", "crafting_weaponsmith_master"
)
$skillRowsPresent = $true
foreach ($skillName in $requiredSkillRows)
{
    if (-not [regex]::IsMatch($skills, "(?m)^" + [regex]::Escape($skillName) + "`t"))
    {
        $skillRowsPresent = $false
    }
}
Assert-Contract $skillRowsPresent "p14.retained-reverse-performance.precu-skill-rows"
Assert-Contract ($schematicGroups.Contains("craftArtisanNewbieGroupA`tobject/draft_schematic/item/item_reverse_engineering_tool.iff") -and
    $schematicGroups.Contains("craftArtisanNewbieGroupA`tobject/draft_schematic/reverse_engineering/enhancement_module.iff")) `
    "p14.retained-reverse-performance.retained-schematics"

Assert-Contract (-not $performance.Contains("expertise_") -and
    $inspiration.Contains("if (!isNgeInspirationEnabled())") -and
    $inspiration.Contains("return false;") -and
    $inspiration.Contains("float perTickMinutesAdded = INSPIRATION_BUFF_SEGMENT;") -and
    $inspiration.Contains("private static boolean isNgeInspirationEnabled()") -and
    $hologram.Contains("int maxHoloAllowed = 1;") -and
    -not $hologram.Contains("getSkillStatisticModifier")) `
    "p14.retained-reverse-performance.performance-authority"
Assert-Contract ($performance.Contains("healing_dance_mind") -and
    $performance.Contains("healing_music_mind") -and
    $performance.Contains("holographicCleanup") -and
    $performance.Contains('"systems.skills.performance.holographic_backup"')) `
    "p14.retained-reverse-performance.precu-healing-and-hologram-lifecycle.preserved"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.retained-reverse-performance.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.retained-reverse-performance.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.reverseEngineeringTool -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.performance -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.retained-reverse-performance.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.retained-reverse-performance.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "p14.retained-reverse-performance.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU retained reverse/performance authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU retained reverse/performance authority contract passed."
