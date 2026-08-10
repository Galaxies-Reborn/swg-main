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
    ([string]$manifest.contracts.p14PrecuCraftingExpertiseAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
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

$paths = [ordered]@{}
$texts = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    $paths[$property.Name] = $path
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.crafting-expertise.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.crafting-expertise.source.$($property.Name).authenticated"
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$experimentCallbackRecords = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading ([string]$contract.inventory.pattern) $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
        "p14.crafting-expertise.experiment-callback.inventory-line-parsed"
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    Assert-Contract ($absolutePath.StartsWith(
        $scriptRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) `
        "p14.crafting-expertise.experiment-callback.inventory-contained"
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $experimentCallbackRecords.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
}
$experimentCallbackRecords = @($experimentCallbackRecords | Sort-Object)
$experimentCallbackPaths = @($experimentCallbackRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') `
        "p14.crafting-expertise.experiment-callback.path-isolated"
    $Matches[1]
} | Sort-Object -Unique)
$expectedExperimentCallbackPaths = @($contract.inventory.sourcePaths | ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract ($experimentCallbackRecords.Count -eq [int]$contract.inventory.handlers -and
    $experimentCallbackRecords.Count -eq [int]$contract.expected.craftingExperimentCallbacks -and
    $experimentCallbackPaths.Count -eq [int]$contract.inventory.sourceFiles -and
    ($experimentCallbackPaths -join "`n") -ceq ($expectedExperimentCallbackPaths -join "`n") -and
    (Get-TextSha256 ($experimentCallbackRecords -join "`n")) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 ($experimentCallbackPaths -join "`n")) -ceq [string]$contract.inventory.sourceSetSha256) `
    "p14.crafting-expertise.experiment-callback.complete-inventory"

$gameplayNames = @("craftinglib", "resource", "playerStructure", "craftingBase", "cybernetic")
$gameplayText = ($gameplayNames | ForEach-Object { [string]$texts[$_] }) -join "`n"
$expertiseReads = ([regex]::Matches($gameplayText,
    'get(?:Enhanced)?SkillStatisticModifier(?:Uncapped)?\([^\r\n]*"expertise_')).Count
Assert-Contract ([int]$contract.expected.changedGameplaySourceFiles -eq $gameplayNames.Count -and
    [int]$contract.expected.historicalExecutableExpertiseReads -eq 11 -and
    $expertiseReads -eq [int]$contract.expected.remainingExecutableExpertiseReads) `
    "p14.crafting-expertise.nge-modifier-reads.retired"

$attributes = [string]$texts.attributes
Assert-Contract ($attributes.Contains('library/player_structure.java -text whitespace=cr-at-eol') -and
    $attributes.Contains('library/resource.java -text whitespace=cr-at-eol') -and
    $attributes.Contains('crafting_new_cybernetics_final.java -text whitespace=cr-at-eol')) `
    "p14.crafting-expertise.no-line-ending-bloat-policy"

$craftinglib = [string]$texts.craftinglib
$experiment = Get-SourceSlice $craftinglib `
    "public static void calcSuccessPerAttributeExperimentation" `
    "public static void storeTissueDataAsObjvars"
Assert-Contract (-not $craftinglib.Contains('"expertise_resource_quality_increase"') -and
    $craftinglib.Contains("computeWeightedAverage") -and
    $craftinglib.Contains("getCraftingInspirationBonus") -and
    $craftinglib.Contains("itemAttributeApplicableResourceValueAverage > 100.0f")) `
    "p14.crafting-expertise.resource-quality.precu-authority"
Assert-Contract (-not $experiment.Contains('"expertise_experimentation_increase_"') -and
    $experiment.Contains('getSkillStatisticModifier(player, "force_experimentation")') -and
    $experiment.Contains("cityRollAdjust") -and
    $experiment.Contains("foodRollAdjust") -and
    $experiment.Contains("luck.getPrecuCraftingLuckRoll(player)")) `
    "p14.crafting-expertise.experimentation.precu-authority"

$craftingBase = [string]$texts.craftingBase
$experimentCallback = Get-SourceSlice $craftingBase `
    "public int OnCraftingExperiment(" `
    "public int doCraftingExperiment("
$experimentImplementation = Get-SourceSlice $craftingBase `
    "public int doCraftingExperiment(" `
    "public int OnFinalizeSchematic("
$playerLevelPatterns = @(
    '(?<![A-Za-z0-9_\.])getLevel\s*\(\s*player\s*\)',
    '\bsetLevel\s*\(', '\bsetSkillTemplate\s*\(', '\bgetSkillTemplate\s*\(',
    '\bcombatLevel\b', '\bplayerLevel\b'
)
$playerLevelMatches = @($playerLevelPatterns | Where-Object {
    [regex]::IsMatch($experimentCallback + $experimentImplementation, $_)
})
Assert-Contract ([int]$contract.inventory.precuExperimentDispatchers -eq 1 -and
    [regex]::Matches($experimentCallback, '\bdoCraftingExperiment\s*\(').Count -eq
        [int]$contract.expected.craftingExperimentPrecuDispatches -and
    $experimentCallback.Contains('"skipCraftingExperiment"') -and
    $experimentImplementation.Contains("craftinglib.calcExpFullSinglePointValue") -and
    $experimentImplementation.Contains("craftinglib.calcPerExperimentationCheckMod") -and
    $experimentImplementation.Contains("craftinglib.calcSuccessPerAttributeExperimentation") -and
    $experimentImplementation.Contains('obj_attributes[i].equals("coreLevel")') -and
    $experimentImplementation.Contains("objectAttribs[i].currentValue = coreLevel;") -and
    -not $experimentImplementation.Contains('"expertise_') -and
    $playerLevelMatches.Count -eq [int]$contract.expected.craftingExperimentPlayerLevelReadsOrWrites) `
    "p14.crafting-expertise.experiment-callback.precu-authority"
Assert-Contract (-not $craftingBase.Contains('"expertise_complexity_decrease_"') -and
    $craftingBase.Contains("calcAndSetPrototypeProperties") -and
    $craftingBase.Contains("xp.grantCraftingStyleXp")) `
    "p14.crafting-expertise.complexity.retired"

$resource = [string]$texts.resource
Assert-Contract (-not $resource.Contains('"expertise_resource_sampling_increase"') -and
    $resource.Contains('buff.hasBuff(user, "tcg_series4_falleens_fist")') -and
    $resource.Contains("addResourceToContainer")) `
    "p14.crafting-expertise.sampling.precu-authority"

$structure = [string]$texts.playerStructure
$power = Get-SourceSlice $structure `
    "public static float expertiseModifyPowerRate" `
    "public static boolean addStructure"
$management = Get-SourceSlice $structure `
    "public static boolean applyManagementMods(obj_id structure, obj_id player)" `
    "public static boolean applyManagementMods(obj_id structure, int mods)"
Assert-Contract (-not $structure.Contains('"expertise_harvester_collection_increase"') -and
    -not $structure.Contains('"expertise_havester_storage_increase"') -and
    -not $structure.Contains('"expertise_factory_energy_decrease"') -and
    -not $structure.Contains('"expertise_harvester_energy_decrease"') -and
    -not $structure.Contains('"expertise_factory_maintenance_decrease"') -and
    -not $structure.Contains('"expertise_harvester_maintenance_decrease"') -and
    $structure.Contains('deed_info.getInt("current_extraction")') -and
    $structure.Contains('deed_info.getInt("max_extraction")') -and
    $structure.Contains('deed_info.getInt("max_hopper")')) `
    "p14.crafting-expertise.structure.authored-values"
Assert-Contract ($power.Contains("removeObjVar(structure, VAR_POWER_MOD_FACTORY)") -and
    $power.Contains("removeObjVar(structure, VAR_POWER_MOD_HARVESTER)") -and
    $power.Contains("return power_rate;") -and
    $management.Contains('getSkillStatMod(player, "structure_maintenance_mod")') -and
    $management.Contains('getSkillStatMod(player, "factory_efficiency")')) `
    "p14.crafting-expertise.structure.stale-state-and-precu-mods"

$cybernetic = [string]$texts.cybernetic
Assert-Contract (-not $cybernetic.Contains('"expertise_cybernetic_negative_effects_reduction"') -and
    $cybernetic.Contains("float reductionAmount = 1.0f - 0.4f;") -and
    $cybernetic.Contains("protectionAmount *= reductionAmount;")) `
    "p14.crafting-expertise.cybernetic.base-penalty"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.crafting-expertise.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.crafting-expertise.direct-source-pin"
    $compiledHashesValid = $true
    foreach ($property in $contract.buildEvidence.compiledClassSha256.PSObject.Properties)
    {
        if ([string]$property.Value -notmatch '^[a-f0-9]{64}$') { $compiledHashesValid = $false }
    }
    Assert-Contract ($compiledHashesValid -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.crafting-expertise.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.crafting-expertise.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.crafting-expertise.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU crafting expertise authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU crafting expertise authority contract passed."
