param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$contractPath = Join-Path $repositoryRoot "restoration/contracts/p14-precu-heroic-jewelry-weapon-speed-authority.json"
$manifestPath = Join-Path $repositoryRoot "restoration/manifest.json"
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param([bool]$Condition, [string]$Name)
    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $script:failures.Add($Name)
    }
}

function Resolve-ContractPath
{
    param([string]$RelativePath)
    return Join-Path $repositoryRoot ($RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
}

function Get-JavaStringArray
{
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text,
        "public static final String\[\]\s+$([regex]::Escape($Name))\s*=\s*\{(?<body>.*?)\};",
        [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success)
    {
        return @()
    }
    return @([regex]::Matches($match.Groups['body'].Value, '"(?<value>[^"]+)"') |
        ForEach-Object { $_.Groups['value'].Value })
}

function Get-SourceSlice
{
    param([string]$Text, [string]$Start, [string]$End)
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { return "" }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

$paths = @{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Resolve-ContractPath ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $paths[$property.Name]) `
        "p14.heroic-jewelry-speed.source.$([IO.Path]::GetFileName($paths[$property.Name])).exists"
}

$itemText = Get-Content -LiteralPath $paths.heroicItemScript -Raw
$masterRows = @(Import-Csv -LiteralPath $paths.masterItems -Delimiter "`t" | Where-Object {
    $_.name -like 'item_heroic_random_*'
})
$lootText = Get-Content -LiteralPath $paths.heroicDrops -Raw
$skillText = Get-Content -LiteralPath $paths.skillTable -Raw
$queueText = Get-Content -LiteralPath $paths.commandQueue -Raw
$buffHandlerText = Get-Content -LiteralPath $paths.buffHandler -Raw
$effectRows = @(Import-Csv -LiteralPath $paths.effectMapping -Delimiter "`t")

$ranged = @(Get-JavaStringArray -Text $itemText -Name "RANGED_SPEED_MODIFIERS")
$melee = @(Get-JavaStringArray -Text $itemText -Name "MELEE_SPEED_MODIFIERS")
$lightsaber = @(Get-JavaStringArray -Text $itemText -Name "LIGHTSABER_SPEED_MODIFIERS")
$allSpeedMods = @($ranged + $melee + $lightsaber)
$expectedRanged = @('rifle_speed', 'carbine_speed', 'pistol_speed')
$expectedMelee = @('onehandmelee_speed', 'twohandmelee_speed', 'unarmed_speed', 'polearm_speed')
$expectedLightsaber = @('onehandlightsaber_speed', 'twohandlightsaber_speed', 'polearmlightsaber_speed')
Assert-Contract ($ranged.Count -eq [int]$contract.expected.rangedSpeedModifiers -and
    ($ranged -join '|') -ceq ($expectedRanged -join '|') -and
    $melee.Count -eq [int]$contract.expected.meleeSpeedModifiers -and
    ($melee -join '|') -ceq ($expectedMelee -join '|') -and
    $lightsaber.Count -eq [int]$contract.expected.lightsaberSpeedModifiers -and
    ($lightsaber -join '|') -ceq ($expectedLightsaber -join '|') -and
    ($allSpeedMods | Select-Object -Unique).Count -eq [int]$contract.expected.generatedWeaponSpeedModifiers) `
    "p14.heroic-jewelry-speed.exact-precu-speed-modifiers"

$legacyPrimary = @(Get-JavaStringArray -Text $itemText -Name "LEGACY_NGE_PRIMARY_MODIFIERS")
$legacyAction = @(Get-JavaStringArray -Text $itemText -Name "LEGACY_NGE_ACTION_MODIFIERS")
$expectedPrimary = @(
    'agility_modified', 'stamina_modified', 'constitution_modified',
    'precision_modified', 'strength_modified', 'luck_modified'
)
$expectedAction = @(
    'expertise_action_weapon_0', 'expertise_action_weapon_1',
    'expertise_action_weapon_2', 'expertise_action_weapon_4',
    'expertise_action_weapon_5', 'expertise_action_weapon_6',
    'expertise_action_weapon_7', 'expertise_action_weapon_9',
    'expertise_action_weapon_10', 'expertise_action_weapon_11'
)
Assert-Contract ($legacyPrimary.Count -eq [int]$contract.expected.legacyNgePrimaryModifiers -and
    ($legacyPrimary -join '|') -ceq ($expectedPrimary -join '|') -and
    $legacyAction.Count -eq [int]$contract.expected.legacyNgeActionModifiers -and
    ($legacyAction -join '|') -ceq ($expectedAction -join '|')) `
    "p14.heroic-jewelry-speed.exact-legacy-migration-leaves"

$primaryPredicate = Get-SourceSlice -Text $buffHandlerText `
    -Start "public boolean isRetiredNgePrimaryStatisticModifier(String modifierName)" `
    -End "public boolean isRetiredNgeBuffSkillModifier(String modifierName)"
$buffPredicate = Get-SourceSlice -Text $buffHandlerText `
    -Start "public boolean isRetiredNgeBuffSkillModifier(String modifierName)" `
    -End "public void retireNgeExpertiseModifier(obj_id self, String effectName)"
$primaryPredicateNames = @($expectedPrimary | Where-Object {
    $primaryPredicate.Contains('modifierName.equals("' + $_ + '")')
})
$milkModifiers = @("milk_quantity_modified", "milk_exceptional_modified", "milk_stun_modified")
$mappedPrimary = @($effectRows | Where-Object { $expectedPrimary -ccontains [string]$_.NAME })
$mappedMilk = @($effectRows | Where-Object { $milkModifiers -ccontains [string]$_.NAME })
Assert-Contract ($primaryPredicateNames.Count -eq
        [int]$contract.expected.genericBuffPrimaryModifiersRetired -and
    @($primaryPredicateNames | Select-Object -Unique).Count -eq $expectedPrimary.Count -and
    @($milkModifiers | Where-Object { $primaryPredicate.Contains($_) }).Count -eq 0 -and
    $buffPredicate.Contains("static_item.isRetiredNgeBuffSkillModifier(modifierName)") -and
    $mappedPrimary.Count -eq $expectedPrimary.Count -and
    @($mappedPrimary | Where-Object {
        [string]$_.TYPE -cne "skill" -or [string]$_.SUBTYPE -cne [string]$_.NAME
    }).Count -eq 0 -and
    $mappedMilk.Count -eq [int]$contract.expected.retainedCreatureMilkModifiers) `
    "p14.heroic-jewelry-speed.generic-buff-primary-boundary"

$genericBuffWriters = @(
    (Get-SourceSlice -Text $buffHandlerText -Start "public int skillAddBuffHandler(" -End "public int skillRemoveBuffHandler(")
    (Get-SourceSlice -Text $buffHandlerText -Start "public int skillPercentAddBuffHandler(" -End "public int skillPercentRemoveBuffHandler(")
    (Get-SourceSlice -Text $buffHandlerText -Start "public int forcePowerAddBuffHandler(" -End "public int forcePowerRemoveBuffHandler(")
)
$guardedBuffWriters = @($genericBuffWriters | Where-Object {
    $guard = $_.IndexOf("isRetiredNgeBuffSkillModifier(subtype)", [StringComparison]::Ordinal)
    $writer = $_.IndexOf("addSkillModModifier", [StringComparison]::Ordinal)
    $guard -ge 0 -and $writer -gt $guard
})
Assert-Contract ($genericBuffWriters.Count -eq
        [int]$contract.expected.genericBuffWriterHandlersGuarded -and
    $guardedBuffWriters.Count -eq $genericBuffWriters.Count) `
    "p14.heroic-jewelry-speed.generic-buff-writers-guarded"
Assert-Contract (-not $itemText.Contains('STAT_ONE') -and
    -not $itemText.Contains('STAT_TWO') -and
    -not $itemText.Contains('STAT_VALS') -and
    $itemText.Contains("public static final int WEAPON_SPEED_VALUE = $($contract.expected.generatedWeaponSpeedValue);") -and
    $itemText.Contains('"skillmod.bonus." + getWeightedWeaponSpeedModifier()') -and
    ([regex]::Matches($itemText, 'setObjVar\(self, "skillmod[.]bonus')).Count -eq
        [int]$contract.expected.generatedModifiersPerItem -and
    -not [regex]::IsMatch($itemText,
        'setObjVar\([^\r\n]*(?:_modified|expertise_action_weapon_)')) `
    "p14.heroic-jewelry-speed.nge-writers-retired"
Assert-Contract (([regex]::Matches($itemText,
    'removeLegacyNgeModifiers\(self\);')).Count -eq
        [int]$contract.expected.legacyMigrationCallSites -and
    ([regex]::Matches($itemText,
        'if \(!hasWeaponSpeedModifier\(self\)\)')).Count -eq
        [int]$contract.expected.legacyMigrationCallSites -and
    $itemText.Contains('removeObjVar(self, objVar);') -and
    -not $itemText.Contains('removeObjVar(self, "skillmod.bonus");')) `
    "p14.heroic-jewelry-speed.persisted-item-migration"
Assert-Contract ($itemText.Contains("weightingRoll <= $($contract.expected.rangedWeightMaximum)") -and
    $itemText.Contains("weightingRoll >= $($contract.expected.lightsaberWeightMinimum)") -and
    $itemText.Contains('return weaponChoices[rand(0, weaponChoices.length - 1)];')) `
    "p14.heroic-jewelry-speed.weighting-preserved"
Assert-Contract (([regex]::Matches($itemText,
    'messageTo\(self, "generateRandomStats", null, 3, false\);')).Count -eq 2 -and
    ([regex]::Matches($itemText,
        'if \(!hasWeaponSpeedModifier\(self\)\)')).Count -eq 3) `
    "p14.heroic-jewelry-speed.delayed-idempotent-lifecycle"

$boundRows = @($masterRows | Where-Object { $_.scripts -ceq 'item.heroic_random_stat_item' })
Assert-Contract ($masterRows.Count -eq [int]$contract.expected.heroicJewelryDefinitions -and
    $boundRows.Count -eq [int]$contract.expected.heroicJewelryScriptBindings -and
    @($masterRows | Where-Object { $_.template_name -notmatch '^object/tangible/wearables/(ring|necklace|bracelet)/' }).Count -eq 0) `
    "p14.heroic-jewelry-speed.master-item-bindings"
$lootMatches = @([regex]::Matches($lootText,
    'item_heroic_random_(?:ring|neck|bracelet_[lr])_\d{2}_\d{2}') | ForEach-Object { $_.Value })
$uniqueLoot = @($lootMatches | Sort-Object -Unique)
$masterNames = @($masterRows.name | Sort-Object -Unique)
Assert-Contract ($lootMatches.Count -eq [int]$contract.expected.heroicLootOccurrences -and
    $uniqueLoot.Count -eq [int]$contract.expected.heroicLootUniqueItems -and
    @(Compare-Object -ReferenceObject $masterNames -DifferenceObject $uniqueLoot).Count -eq 0) `
    "p14.heroic-jewelry-speed.heroic-loot-reachability"

$missingSkillMods = @($allSpeedMods | Where-Object {
    -not [regex]::IsMatch($skillText, [regex]::Escape($_) + '=')
})
Assert-Contract ($missingSkillMods.Count -eq 0) "p14.heroic-jewelry-speed.skill-table-authority"
$mappingStart = $queueText.IndexOf('char const * getPrecuWeaponSpeedSkill', [StringComparison]::Ordinal)
$cadenceStart = $queueText.IndexOf('float calculatePrecuAttackTime', [StringComparison]::Ordinal)
$executeStart = $queueText.IndexOf('float getCommandExecuteTime', [StringComparison]::Ordinal)
$mapping = if ($mappingStart -ge 0 -and $cadenceStart -gt $mappingStart) {
    $queueText.Substring($mappingStart, $cadenceStart - $mappingStart)
} else { '' }
$cadence = if ($cadenceStart -ge 0 -and $executeStart -gt $cadenceStart) {
    $queueText.Substring($cadenceStart, $executeStart - $cadenceStart)
} else { '' }
$missingNativeMappings = @($allSpeedMods | Where-Object {
    ([regex]::Matches($mapping, '"' + [regex]::Escape($_) + '"')).Count -ne 1
})
Assert-Contract ($missingNativeMappings.Count -eq 0 -and
    $cadence.Contains('owner.getEnhancedModValue(speedSkill)') -and
    $cadence.Contains('return 2.0f;') -and
    $cadence.Contains('return executeTime > 1.0f ? executeTime : 1.0f;')) `
    "p14.heroic-jewelry-speed.native-cadence-consumer"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.heroic-jewelry-speed.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.heroic-jewelry-speed.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.heroic-jewelry-speed.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.heroicItemScript -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.buffHandler -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.heroic-jewelry-speed.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.heroic-jewelry-speed.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.heroic-jewelry-speed.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU heroic jewelry weapon-speed authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU heroic jewelry weapon-speed authority contract passed."
