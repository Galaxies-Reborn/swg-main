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
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuItemLevelRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$checkedOutDsrcCommit = (& git -C (Join-Path $source "dsrc") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out dsrc commit." }

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length,
        [StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

function Get-StaticItemSkillModifierProfile([string]$Path)
{
    $lines = [IO.File]::ReadAllLines($Path)
    $headers = [regex]::Split([string]$lines[0], "`t")
    $skillModsIndex = [Array]::IndexOf($headers, "skill_mods")
    if ($skillModsIndex -lt 0)
    {
        throw "Static-item table has no skill_mods column: $Path"
    }
    $primaryRows = 0
    $expertiseRows = 0
    $additionalNgeRows = 0
    $additionalNgeOccurrences = 0
    $dataRows = 0
    $primaryModifiers = @(
        "precision_modified",
        "strength_modified",
        "stamina_modified",
        "constitution_modified",
        "agility_modified",
        "luck_modified"
    )
    $additionalExactNgeModifiers = @(
        "bh_dire_root",
        "bh_dire_snare",
        "combat_block_chance",
        "combat_block_value",
        "combat_strikethrough_chance",
        "cooldown_percent_of_group_buff",
        "incubation_time_reduction",
        "rally_point_duration",
        "tka_armor"
    )
    foreach ($line in @($lines | Select-Object -Skip 2))
    {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $fields = [regex]::Split([string]$line, "`t")
        if ($fields.Count -eq 0 -or [string]::IsNullOrWhiteSpace($fields[0])) { continue }
        $dataRows++
        if ($fields.Count -le $skillModsIndex) { continue }
        $skillMods = [string]$fields[$skillModsIndex]
        $rowHasPrimary = $false
        $rowHasExpertise = $false
        $rowHasAdditionalNge = $false
        foreach ($entry in @($skillMods -split ','))
        {
            $modifier = [string](($entry -split '=', 2)[0])
            $modifier = $modifier.Trim().Trim('"')
            if ($primaryModifiers -contains $modifier) { $rowHasPrimary = $true }
            if ($modifier.StartsWith("expertise_")) { $rowHasExpertise = $true }
            if ($additionalExactNgeModifiers -contains $modifier -or
                $modifier.StartsWith("fast_attack_line_") -or
                $modifier.StartsWith("bm_"))
            {
                $rowHasAdditionalNge = $true
                $additionalNgeOccurrences++
            }
        }
        if ($rowHasPrimary) { $primaryRows++ }
        if ($rowHasExpertise) { $expertiseRows++ }
        if ($rowHasAdditionalNge) { $additionalNgeRows++ }
    }
    return [pscustomobject]@{
        dataRows = $dataRows
        primaryRows = $primaryRows
        expertiseRows = $expertiseRows
        additionalNgeRows = $additionalNgeRows
        additionalNgeOccurrences = $additionalNgeOccurrences
    }
}

Assert-Contract ($dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink -and
    $checkedOutDsrcCommit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
    "p14.item-level.direct-source-pin"

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch)
$patchExists = Test-Path -LiteralPath $patchPath -PathType Leaf
Assert-Contract $patchExists "p14.item-level.overlay.exists"
if ($patchExists)
{
    $patch = Get-Item -LiteralPath $patchPath
    $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $sha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.item-level.overlay.authenticated"
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$relativePaths = @(
    "item/armor/dynamic_armor.java",
    "item/buff_beast_click_item.java",
    "item/buff_click_item.java",
    "item/full_heal_item.java",
    "item/levelup_orb/levelup_orb.java",
    "item/medicine/stimpack.java",
    "item/medicine/stimpack_crafted.java",
    "item/plant/force_melon.java",
    "item/skill_buff/base.java",
    "item/skillmod_click_item.java",
    "item/static_item_base.java",
    "item/survey_tool/survey_tool_script.java",
    "item/tool/reverse_engineering_poweredup_item.java",
    "item/tool/reverse_engineering_tool.java",
    "library/bio_engineer.java",
    "library/buff.java",
    "library/collection.java",
    "library/consumable.java",
    "library/healing.java",
    "library/loot.java",
    "library/magic_item.java",
    "library/player_structure.java",
    "library/reverse_engineering.java",
    "library/static_item.java",
    "player/player_utility.java",
    "systems/buff/buff_handler.java",
    "systems/combat/combat_weapon.java",
    "systems/crafting/crafting_base.java",
    "systems/crafting/clothing/crafting_base_clothing.java",
    "systems/crafting/weapon/component/crafting_weapon_component_attribute.java",
    "systems/sign/special_sign.java",
    "systems/tcg/tcg_vendor_contract.java"
)
$texts = @{}
foreach ($relativePath in $relativePaths)
{
    $path = Join-Path $scriptRoot $relativePath
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.item-level.source.$relativePath"
    $texts[$relativePath] = Get-Content -LiteralPath $path -Raw
}

$staticItem = [string]$texts["library/static_item.java"]
$dynamicArmor = [string]$texts["item/armor/dynamic_armor.java"]
$loot = [string]$texts["library/loot.java"]
$reverseEngineeringTool = [string]$texts["item/tool/reverse_engineering_tool.java"]
$reverseEngineeringPoweredItem = [string]$texts[
    "item/tool/reverse_engineering_poweredup_item.java"]
$reverseEngineering = [string]$texts["library/reverse_engineering.java"]
$magicItem = [string]$texts["library/magic_item.java"]
$craftingBase = [string]$texts["systems/crafting/crafting_base.java"]
$craftingBaseClothing = [string]$texts[
    "systems/crafting/clothing/crafting_base_clothing.java"]
$bioEngineer = [string]$texts["library/bio_engineer.java"]
$buffLibrary = [string]$texts["library/buff.java"]
$collectionLibrary = [string]$texts["library/collection.java"]
$consumable = [string]$texts["library/consumable.java"]
$healing = [string]$texts["library/healing.java"]
$playerStructure = [string]$texts["library/player_structure.java"]
$playerUtility = [string]$texts["player/player_utility.java"]
$buffHandler = [string]$texts["systems/buff/buff_handler.java"]
$specialSign = [string]$texts["systems/sign/special_sign.java"]
$tcgVendorContract = [string]$texts["systems/tcg/tcg_vendor_contract.java"]
$skillBuffItem = [string]$texts["item/skill_buff/base.java"]
$skillmodClickItem = [string]$texts["item/skillmod_click_item.java"]
$combatWeapon = [string]$texts["systems/combat/combat_weapon.java"]
$validators = Get-FunctionSlice $staticItem `
    "public static boolean validateLevelRequired(obj_id player, int requiredLevel)" `
    "public static void decrementStaticItem("
Assert-Contract (([regex]::Matches($validators, "return true;")).Count -eq 3 -and
    -not $validators.Contains("getLevel(") -and
    -not $validators.Contains("getMasterItemDictionary(") -and
    -not $validators.Contains("getStaticObjectTypeDictionary(")) `
    "p14.item-level.shared-validator-inert"

$staticTransfer = Get-FunctionSlice ([string]$texts["item/static_item_base.java"]) `
    "public int OnAboutToBeTransferred(" "public int OnTransferred("
Assert-Contract (-not $staticTransfer.Contains("requiredLevel") -and
    -not $staticTransfer.Contains("validateLevelRequired") -and
    -not $staticTransfer.Contains("SID_ITEM_LEVEL_TOO_LOW") -and
    $staticTransfer.Contains("requiredSkill") -and
    $staticTransfer.Contains("utils.meetsProfessionRequirement")) `
    "p14.item-level.static-transfer-skill-only"

$staticBaseAttributes = Get-FunctionSlice ([string]$texts["item/static_item_base.java"]) `
    "public int OnGetAttributes(" "public int handlerVersionUpdate("
$staticObjectAttributes = Get-FunctionSlice $staticItem `
    "public static void getStaticItemObjectAttributes(" `
    "public static dictionary parseSkillModifiers("
Assert-Contract (-not $staticBaseAttributes.Contains("effect_level") -and
    -not $staticBaseAttributes.Contains("requiredLevelForEffect") -and
    -not $staticObjectAttributes.Contains("required_combat_level") -and
    -not $staticObjectAttributes.Contains("effect_level") -and
    $staticObjectAttributes.Contains("required_skill") -and
    $staticObjectAttributes.Contains("reuse_time")) `
    "p14.item-level.static-attribute-presentation-retired"

$combatWeaponAttributes = Get-FunctionSlice $combatWeapon `
    "public int OnGetAttributes(" "public int handleConvertSchemSui("
Assert-Contract ($combatWeaponAttributes.Contains(
        "utils.getPrecuProfessionRequirementSkillName") -and
    $combatWeaponAttributes.Contains('skillRequired.equals("disabled")') -and
    -not $combatWeaponAttributes.Contains('@ui_roadmap:title_')) `
    "p14.item-level.weapon-requirement-precu-presentation"

$validateWorn = Get-FunctionSlice $staticItem `
    "public static void validateWornEffects(" "public static void applyWornBuffs("
$applyWorn = Get-FunctionSlice $staticItem `
    "public static void applyWornBuffs(" "public static void removeWornBuffs("
$canEquip = Get-FunctionSlice $staticItem `
    "public static boolean canEquip(" "public static void origOwnerCheckStamp("
Assert-Contract (-not $validateWorn.Contains("validateLevelRequired") -and
    -not $applyWorn.Contains("validateLevelRequired") -and
    -not $applyWorn.Contains("SID_ITEM_LEVEL_TOO_LOW") -and
    $applyWorn.Contains("buff.canApplyBuff") -and
    -not $canEquip.Contains("validateLevelRequired") -and
    $canEquip.Contains("utils.meetsProfessionRequirement")) `
    "p14.item-level.worn-effects-and-equip-skill-only"

$retiredStaticModifierPredicate = Get-FunctionSlice $staticItem `
    "public static boolean isRetiredNgeStaticItemSkillModifier(" `
    "public static void removeRetiredNgeStaticItemSkillModifiers("
$retiredStaticModifierCleanup = Get-FunctionSlice $staticItem `
    "public static void removeRetiredNgeStaticItemSkillModifiers(" `
    "public static void applyPrecuStaticItemSkillModifiers("
$precuStaticModifierApplication = Get-FunctionSlice $staticItem `
    "public static void applyPrecuStaticItemSkillModifiers(" `
    "public static boolean initializeArmor("
$staticArmorInitializer = Get-FunctionSlice $staticItem `
    "public static boolean initializeArmor(" `
    "public static boolean initializeWeapon("
$staticWeaponInitializer = Get-FunctionSlice $staticItem `
    "public static boolean initializeWeapon(" `
    "public static boolean initializeItem("
$staticItemInitializer = Get-FunctionSlice $staticItem `
    "public static boolean initializeItem(" `
    "public static boolean initializeStorytellerObject("
$retiredStaticModifierInventory = Get-FunctionSlice $staticItem `
    "public static final String[] RETIRED_NGE_STATIC_ITEM_MODIFIERS" `
    "public static final java.text.NumberFormat"
$retiredExactStaticModifiers = @(
    "bh_dire_root",
    "bh_dire_snare",
    "combat_block_chance",
    "combat_block_value",
    "combat_strikethrough_chance",
    "cooldown_percent_of_group_buff",
    "incubation_time_reduction",
    "rally_point_duration",
    "tka_armor"
)
$retiredExactStaticInventoryValid = $true
foreach ($modifier in $retiredExactStaticModifiers)
{
    if (([regex]::Matches($retiredStaticModifierInventory,
            '"' + [regex]::Escape($modifier) + '"')).Count -ne 1)
    {
        $retiredExactStaticInventoryValid = $false
    }
}

Assert-Contract ($retiredStaticModifierPredicate.Contains(
        'modifier.startsWith("expertise_")') -and
    $retiredStaticModifierPredicate.Contains(
        'modifier.startsWith("fast_attack_line_")') -and
    $retiredStaticModifierPredicate.Contains(
        'modifier.startsWith("bm_")') -and
    $retiredStaticModifierPredicate.Contains(
        "for (String legacyPrimaryModifier : LEGACY_NGE_DYNAMIC_PRIMARY_MODIFIERS)") -and
    $retiredStaticModifierPredicate.Contains("modifier.equals(legacyPrimaryModifier)") -and
    $retiredStaticModifierPredicate.Contains(
        "for (String retiredModifier : RETIRED_NGE_STATIC_ITEM_MODIFIERS)") -and
    $retiredStaticModifierPredicate.Contains("modifier.equals(retiredModifier)") -and
    $retiredExactStaticModifiers.Count -eq
        [int]$contract.expected.staticSkillModifiers.retiredExactNgeSetModifiers -and
    $retiredExactStaticInventoryValid) `
    "p14.item-level.static-modifier-retired-families"
Assert-Contract (-not $retiredStaticModifierPredicate.Contains("droid_find_speed") -and
    -not $retiredStaticModifierPredicate.Contains("resistance_") -and
    -not $retiredStaticModifierPredicate.Contains("absorption_")) `
    "p14.item-level.static-modifier-precu-families-preserved"
Assert-Contract ($retiredStaticModifierCleanup.Contains("getSkillModBonuses(item)") -and
    $retiredStaticModifierCleanup.Contains("isRetiredNgeStaticItemSkillModifier(modifier)") -and
    $retiredStaticModifierCleanup.Contains("setSkillModBonus(item, modifier, 0)") -and
    -not $retiredStaticModifierCleanup.Contains('removeObjVar(item, "skillmod.bonus")')) `
    "p14.item-level.static-modifier-persisted-exact-cleanup"
Assert-Contract ($precuStaticModifierApplication.IndexOf(
        "removeRetiredNgeStaticItemSkillModifiers(item)", [StringComparison]::Ordinal) -lt
        $precuStaticModifierApplication.IndexOf(
            "parseSkillModifiers(null, skillMods)", [StringComparison]::Ordinal) -and
    $precuStaticModifierApplication.Contains("isRetiredNgeStaticItemSkillModifier(modifier)") -and
    $precuStaticModifierApplication.Contains("setSkillModBonus(item, modifier, 0)") -and
    $precuStaticModifierApplication.Contains(
        "setSkillModBonus(item, modifier, bonuses.getInt(modifier))")) `
    "p14.item-level.static-modifier-precu-filter"

$initializerSurfaces = @(
    $staticArmorInitializer,
    $staticWeaponInitializer,
    $staticItemInitializer
)
$initializerRoutesValid = $true
foreach ($initializerSurface in $initializerSurfaces)
{
    if (([regex]::Matches($initializerSurface,
            'applyPrecuStaticItemSkillModifiers\(object, skillMods\);')).Count -ne 1 -or
        $initializerSurface.Contains("setSkillModBonus(object,"))
    {
        $initializerRoutesValid = $false
    }
}
$staticBaseInitialize = Get-FunctionSlice ([string]$texts["item/static_item_base.java"]) `
    "public int OnInitialize(" "public int OnAboutToBeTransferred("
Assert-Contract ($initializerSurfaces.Count -eq
        [int]$contract.expected.staticSkillModifiers.initializerRoutes -and
    $initializerRoutesValid -and
    $staticBaseInitialize.Contains("static_item.initializeObject(self, itemData)")) `
    "p14.item-level.static-modifier-all-initializers-and-persisted-lifecycle"

$staticModifierTables = [ordered]@{
    armor = Join-Path $source `
        "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/armor_stats.tab"
    weapon = Join-Path $source `
        "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/weapon_stats.tab"
    item = Join-Path $source `
        "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/item_stats.tab"
}
foreach ($tableName in $staticModifierTables.Keys)
{
    $profile = Get-StaticItemSkillModifierProfile $staticModifierTables[$tableName]
    Assert-Contract ($profile.dataRows -eq
            [int]$contract.expected.staticSkillModifiers.retainedDataRows.$tableName -and
        $profile.primaryRows -eq
            [int]$contract.expected.staticSkillModifiers.primaryModifierRows.$tableName -and
        $profile.expertiseRows -eq
            [int]$contract.expected.staticSkillModifiers.expertiseModifierRows.$tableName -and
        $profile.additionalNgeRows -eq
            [int]$contract.expected.staticSkillModifiers.additionalNgeModifierRows.$tableName -and
        $profile.additionalNgeOccurrences -eq
            [int]$contract.expected.staticSkillModifiers.additionalNgeModifierOccurrences.$tableName) `
        "p14.item-level.static-modifier-data-preserved.$tableName"
}

$ngeSkillModListingPath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/expertise/skill_mod_listing.tab"
$ngeSkillModListing = Get-Content -LiteralPath $ngeSkillModListingPath -Raw
$listedNgeStaticModifiers = @($retiredExactStaticModifiers | Where-Object {
    $_ -cne "rally_point_duration"
})
$listedNgeStaticInventoryValid = $true
foreach ($modifier in $listedNgeStaticModifiers)
{
    if ($ngeSkillModListing -notmatch
        ('(?m)^' + [regex]::Escape($modifier) + "`t"))
    {
        $listedNgeStaticInventoryValid = $false
    }
}
Assert-Contract ($listedNgeStaticInventoryValid -and
    $ngeSkillModListing -match '(?m)^fast_attack_line_' -and
    $ngeSkillModListing -match '(?m)^bm_incubator_dps_armor\t' -and
    $ngeSkillModListing -match '(?m)^tka_armor\t.*Innate Teras Kasi Armor') `
    "p14.item-level.static-modifier-nge-listing-authenticated"

$retiredWriterModifierInventory = Get-FunctionSlice $staticItem `
    "public static final String[] RETIRED_NGE_ITEM_WRITER_MODIFIERS" `
    "public static final String[] RETIRED_NGE_BUFF_COMBAT_MODIFIERS"
$retiredWriterModifiers = @(
    "combat_critical_hit_reduction",
    "combat_dodge",
    "combat_parry",
    "combat_evasion_chance",
    "combat_evasion_value",
    "combat_strikethrough_value",
    "commando_devastation",
    "exotic_heal_action_reduction",
    "exotic_dodge_reduction",
    "exotic_parry_reduction",
    "exotic_acid_penetration",
    "exotic_cold_penetration",
    "exotic_heat_penetration",
    "exotic_electricity_penetration"
)
$retiredWriterInventoryValid = $true
foreach ($modifier in $retiredWriterModifiers)
{
    if (([regex]::Matches($retiredWriterModifierInventory,
            '"' + [regex]::Escape($modifier) + '"')).Count -ne 1)
    {
        $retiredWriterInventoryValid = $false
    }
}
Assert-Contract ($retiredWriterModifiers.Count -eq
        [int]$contract.expected.itemModifierWriters.retiredExactNgeModifiers -and
    $retiredWriterInventoryValid -and
    $retiredStaticModifierPredicate.Contains(
        "for (String retiredModifier : RETIRED_NGE_ITEM_WRITER_MODIFIERS)")) `
    "p14.item-level.item-writer-retired-modifier-inventory"

$retiredBuffCombatModifierInventory = Get-FunctionSlice $staticItem `
    "public static final String[] RETIRED_NGE_BUFF_COMBAT_MODIFIERS" `
    "public static final java.text.NumberFormat"
$retiredBuffCombatModifiers = @(
    "combat_add_damage_dealt",
    "combat_add_damage_taken",
    "combat_all_attack_avoidance",
    "combat_all_attack_miss",
    "combat_all_attack_miss_reduction",
    "combat_all_attack_miss_vulnerability",
    "combat_block_reduction",
    "combat_critical_hit",
    "combat_divide_damage_dealt",
    "combat_divide_damage_taken",
    "combat_dodge_reduction",
    "combat_glancing",
    "combat_glancing_blow_reduction",
    "combat_melee_attack_avoidance",
    "combat_melee_attack_miss",
    "combat_melee_attack_miss_reduction",
    "combat_melee_attack_vulnerability",
    "combat_multiply_damage_dealt",
    "combat_multiply_damage_taken",
    "combat_parry_reduction",
    "combat_ranged_attack_avoidance",
    "combat_ranged_attack_miss",
    "combat_ranged_attack_miss_reduction",
    "combat_ranged_attack_vulnerability",
    "combat_subtract_damage_dealt",
    "combat_subtract_damage_taken"
)
$retiredBuffCombatInventoryValid = $true
foreach ($modifier in $retiredBuffCombatModifiers)
{
    if (([regex]::Matches($retiredBuffCombatModifierInventory,
            '"' + [regex]::Escape($modifier) + '"')).Count -ne 1)
    {
        $retiredBuffCombatInventoryValid = $false
    }
}
Assert-Contract ($retiredBuffCombatModifiers.Count -eq
        [int]$contract.expected.itemModifierWriters.retiredBuffCombatModifiers -and
    $retiredBuffCombatInventoryValid -and
    $retiredStaticModifierPredicate.Contains(
        "for (String retiredModifier : RETIRED_NGE_BUFF_COMBAT_MODIFIERS)")) `
    "p14.item-level.buff-combat-modifier-inventory"

$parseSkillModifiers = Get-FunctionSlice $staticItem `
    "public static dictionary parseSkillModifiers(" `
    "public static obj_id makeDynamicObject("
$parseFilterIndex = $parseSkillModifiers.IndexOf(
    "if (!isRetiredNgeStaticItemSkillModifier(modsArray[0]))",
    [StringComparison]::Ordinal)
$parseWriteIndex = $parseSkillModifiers.IndexOf(
    "dict.put(modsArray[0]", [StringComparison]::Ordinal)
$parserConsumers = @($skillmodClickItem, $tcgVendorContract, $specialSign)
$parserConsumersValid = @($parserConsumers | Where-Object {
    $_.Contains("static_item.parseSkillModifiers(player, skillMod)") -and
    $_.Contains("applySkillStatisticModifier(player, skillModName, skillModValue)")
}).Count -eq [int]$contract.expected.itemModifierWriters.staticParserConsumers
Assert-Contract ($parseFilterIndex -ge 0 -and $parseWriteIndex -gt $parseFilterIndex -and
    $parserConsumers.Count -eq
        [int]$contract.expected.itemModifierWriters.staticParserConsumers -and
    $parserConsumersValid) `
    "p14.item-level.static-parser-consumers-filtered"

$buffModifierPredicate = Get-FunctionSlice $buffHandler `
    "public boolean isRetiredNgeBuffSkillModifier(" `
    "public void retireNgeExpertiseModifier("
$genericBuffWriterGuards = ([regex]::Matches($buffHandler,
    [regex]::Escape("if (isPlayer(self) && isRetiredNgeBuffSkillModifier(subtype))"))).Count
Assert-Contract ($buffModifierPredicate.Contains(
        "static_item.isRetiredNgeBuffSkillModifier(modifierName)") -and
    $genericBuffWriterGuards -eq
        [int]$contract.expected.itemModifierWriters.genericPlayerBuffModifierWriters -and
    $buffHandler.Contains("else") -and
    ([regex]::Matches($buffHandler, "addSkillModModifier\(self, effectName, subtype")).Count -ge 3 -and
    [bool]$contract.expected.itemModifierWriters.npcBuffCompatibilityPreserved) `
    "p14.item-level.generic-player-buff-writers-filtered-npc-preserved"

$playerSkillStatisticCleanup = Get-FunctionSlice $staticItem `
    "public static void removeRetiredNgePlayerSkillStatistics(" `
    "public static void removeRetiredNgeStaticItemSkillModifiers("
Assert-Contract ($buffLibrary.Contains(
        "static_item.removeRetiredNgePlayerSkillStatistics(player);") -and
    $playerSkillStatisticCleanup.Contains("getSkillStatModListingForPlayer(player)") -and
    $playerSkillStatisticCleanup.Contains("isRetiredNgeStaticItemSkillModifier(modifier)") -and
    $playerSkillStatisticCleanup.Contains("getSkillStatMod(player, modifier)") -and
    $playerSkillStatisticCleanup.Contains(
        "applySkillStatisticModifier(player, modifier, -currentValue)") -and
    [bool]$contract.expected.itemModifierWriters.persistentPlayerModifierCleanup) `
    "p14.item-level.persisted-player-modifier-login-cleanup"

$collectionReward = Get-FunctionSlice $collectionLibrary `
    "public static boolean grantCollectionReward(" `
    "public static boolean updateCraftingSlot("
$collectionFilterIndex = $collectionReward.IndexOf(
    "if (static_item.isRetiredNgeStaticItemSkillModifier(skillMod1))",
    [StringComparison]::Ordinal)
$collectionWriteIndex = $collectionReward.IndexOf(
    "applySkillStatisticModifier(player, skillMod1, skillModAmount)",
    [StringComparison]::Ordinal)
Assert-Contract ($collectionFilterIndex -ge 0 -and
    $collectionWriteIndex -gt $collectionFilterIndex) `
    "p14.item-level.collection-reward-writer-filtered"

Assert-Contract ($playerUtility.Contains(
        "if (static_item.isRetiredNgeStaticItemSkillModifier(skillMod))") -and
    $playerStructure.Contains(
        "if (!static_item.isRetiredNgeStaticItemSkillModifier(skillmod) &&") -and
    $playerStructure.Contains("removeObjVar(structure, player_structure.SPECIAL_SIGN_DECREMENT_MOD)")) `
    "p14.item-level.stale-entitlement-reimbursement-filtered-cleanup-preserved"

$effectMappingPath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/effect_mapping.tab"
$buffTablePath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
$collectionRewardsPath = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/datatables/collection/rewards.tab"
$effectMappingRows = @(Import-Csv -LiteralPath $effectMappingPath -Delimiter "`t" |
    Where-Object { [string]$_.NAME -cne "s" })
$combatSkillRows = @($effectMappingRows | Where-Object {
    [string]$_.TYPE -ceq "skill" -and [string]$_.SUBTYPE -clike "combat_*"
})
$retainedPrecuCombatBuffModifiers = @("combat_haste", "combat_slow")
$retiredMappedCombatModifiers = @($combatSkillRows | Where-Object {
    [string]$_.SUBTYPE -notin $retainedPrecuCombatBuffModifiers
})
$buffRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t" |
    Where-Object { [string]$_.NAME -cne "s" })
$channelHealEffectRows = @($effectMappingRows | Where-Object {
    [string]$_.NAME -ceq "channel_heal_health"
})
$channelHealBuffRows = @($buffRows | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq "channel_heal_health"
    }).Count -gt 0
})
Assert-Contract ($channelHealEffectRows.Count -eq
        [int]$contract.expected.medicine.retainedChannelHealEffectMappings -and
    [string]$channelHealEffectRows[0].TYPE -ceq "channelHeal" -and
    [string]$channelHealEffectRows[0].SUBTYPE -ceq "health" -and
    $channelHealBuffRows.Count -eq
        [int]$contract.expected.medicine.retainedChannelHealBuffRows -and
    [string]$channelHealBuffRows[0].NAME -ceq "channel_healing" -and
    [string]$channelHealBuffRows[0].DURATION -ceq "12" -and
    [string]$channelHealBuffRows[0].IS_PERSISTENT -ceq "1" -and
    [string]$channelHealBuffRows[0].EFFECT1_PARAM -ceq "channel_heal_health" -and
    [string]$channelHealBuffRows[0].EFFECT1_VALUE -ceq "0") `
    "p14.item-level.channel-heal-data-inventory-authenticated"
Assert-Contract ($combatSkillRows.Count -eq
        [int]$contract.expected.itemModifierWriters.mappedCombatSkillModifiers -and
    @($combatSkillRows.SUBTYPE | Sort-Object -Unique).Count -eq $combatSkillRows.Count -and
    $retiredMappedCombatModifiers.Count -eq
        [int]$contract.expected.itemModifierWriters.retiredMappedCombatModifiers -and
    @($combatSkillRows | Where-Object {
        [string]$_.SUBTYPE -in $retainedPrecuCombatBuffModifiers
    }).Count -eq
        [int]$contract.expected.itemModifierWriters.retainedPrecuCombatBuffModifiers -and
    $buffRows.Count -eq [int]$contract.expected.itemModifierWriters.retainedBuffRows) `
    "p14.item-level.buff-effect-data-authenticated-preserved"

$retiredCollectionRewards = [ordered]@{
    heroic_axkva_min_01 = "combat_parry_reduction"
    heroic_tusken_king_01 = "combat_critical_hit_reduction"
    heroic_ig88_01 = "combat_strikethrough_value"
    heroic_star_destroyer_01 = "combat_block_reduction"
    heroic_exar_kun_01 = "combat_evasion_chance"
}
$collectionRows = @(Import-Csv -LiteralPath $collectionRewardsPath -Delimiter "`t" |
    Where-Object { [string]$_.collection_name -cne "s" })
$retiredCollectionRowsValid = $true
foreach ($entry in $retiredCollectionRewards.GetEnumerator())
{
    $matching = @($collectionRows | Where-Object {
        [string]$_.collection_name -ceq [string]$entry.Key -and
        [string]$_.skill_mod -ceq [string]$entry.Value
    })
    if ($matching.Count -ne 1) { $retiredCollectionRowsValid = $false }
}
Assert-Contract ($retiredCollectionRewards.Count -eq
        [int]$contract.expected.itemModifierWriters.retiredCollectionRewardModifiers -and
    $retiredCollectionRowsValid -and $collectionRows.Count -eq 489) `
    "p14.item-level.collection-reward-data-authenticated-preserved"

$precuBasicReverseModifiers = @(
    "general_assembly",
    "weapon_assembly",
    "armor_assembly",
    "clothing_assembly",
    "droid_assembly",
    "food_assembly"
)
$reverseBasicInventory = Get-FunctionSlice $reverseEngineeringTool `
    "public static final String[] BASIC_MOD_LIST" `
    "public static final String[] FINAL_ATTACHMENT_TEMPLATE"
$reverseBasicInventoryValid = $true
foreach ($modifier in $precuBasicReverseModifiers)
{
    if (([regex]::Matches($reverseBasicInventory,
            '"' + [regex]::Escape($modifier) + '"')).Count -ne 1)
    {
        $reverseBasicInventoryValid = $false
    }
}
$retiredPrimaryModifiers = @(
    "precision_modified", "strength_modified", "stamina_modified",
    "constitution_modified", "agility_modified", "luck_modified"
)
$reverseToolPrimaryFree = $true
foreach ($modifier in $retiredPrimaryModifiers)
{
    if ($reverseEngineeringTool.Contains('"' + $modifier + '"'))
    {
        $reverseToolPrimaryFree = $false
    }
}
Assert-Contract ($precuBasicReverseModifiers.Count -eq
        [int]$contract.expected.itemModifierWriters.precuBasicReverseModifiers -and
    $reverseBasicInventoryValid -and $reverseToolPrimaryFree -and
    $reverseBasicInventory.Contains('"camouflage"') -and
    $reverseBasicInventory.Contains('"droid_find_speed"')) `
    "p14.item-level.reverse-basic-modifiers-precu"

$reversePowerBit = Get-FunctionSlice $reverseEngineeringTool `
    "public void generatePowerBit(" "public void generateModifierBit("
$reverseModifierBit = Get-FunctionSlice $reverseEngineeringTool `
    "public void generateModifierBit(" "public boolean isJunk("
$reverseInputItem = Get-FunctionSlice $reverseEngineeringTool `
    "public boolean isItemWithNPEMod(" "public int getPowerBitType("
$reverseInputBit = Get-FunctionSlice $reverseEngineeringTool `
    "public boolean isModifierBit(" "public int getFinalAttachmentLevel("
Assert-Contract ($reversePowerBit.Contains(
        "!static_item.isRetiredNgeStaticItemSkillModifier(modifier)") -and
    $reverseModifierBit.Contains(
        "!static_item.isRetiredNgeStaticItemSkillModifier(candidateModifier)") -and
    $reverseInputItem.Contains("getSkillModBonuses(item)") -and
    $reverseInputItem.Contains(
        "!static_item.isRetiredNgeStaticItemSkillModifier(modifier)") -and
    $reverseInputBit.Contains(
        "!static_item.isRetiredNgeStaticItemSkillModifier(modifier)")) `
    "p14.item-level.reverse-generation-and-input-filtered"

$reverseApplyEquipped = Get-FunctionSlice $reverseEngineering `
    "public static void applyPowerupItemEquipped(" `
    "public static boolean isPoweredUpItem("
$reverseAdd = Get-FunctionSlice $reverseEngineering `
    "public static void addModsAndScript(obj_id player, obj_id powerUp, obj_id itemToPowerUp, float" `
    "public static void removeModsAndScript("
$reverseAttached = Get-FunctionSlice $reverseEngineering `
    "public static void powerUpAttached(" "public static boolean canMakePowerUp("
$reverseRetirement = Get-FunctionSlice $reverseEngineering `
    "public static boolean isRetiredNgePowerupModifier(" `
    "public static boolean canStaticItemBeReversedEngineered("
Assert-Contract ($reverseApplyEquipped.IndexOf(
        "isRetiredNgePowerupModifier(itemWithPowerUp)") -lt
        $reverseApplyEquipped.IndexOf("addSkillModModifier(") -and
    $reverseAdd.IndexOf("isRetiredNgePowerupModifier(powerUp)") -lt
        $reverseAdd.IndexOf("setObjVar(itemToPowerUp, ENGINEERING_MODIFIER") -and
    $reverseAttached.IndexOf("isRetiredNgePowerupModifier(itemWithPowerUp)") -lt
        $reverseAttached.IndexOf("addSkillModModifier(") -and
    $reverseRetirement.Contains("removeAttribOrSkillModModifier(") -and
    $reverseRetirement.Contains("removeModsAndScript(player, item)") -and
    $reverseRetirement.Contains("recalcPoolsIfNeeded(player, modifier)")) `
    "p14.item-level.reverse-application-and-stale-cleanup"
Assert-Contract (([regex]::Matches($reverseEngineeringPoweredItem,
        "reverse_engineering\.isRetiredNgePowerupModifier\(self\)")).Count -eq 2 -and
    ([regex]::Matches($reverseEngineeringPoweredItem,
        "reverse_engineering\.retireNgePowerupModifier\(player, self\)")).Count -eq 2 -and
    ([regex]::Matches($reverseEngineeringPoweredItem,
        "addSkillModModifier\(")).Count -eq 2) `
    "p14.item-level.powered-item-lifecycle-filtered"

$magicAppearance = Get-FunctionSlice $magicItem `
    "public static Vector getAppearanceMagicMods(" "public static obj_id makeGem("
$magicGemMods = Get-FunctionSlice $magicItem `
    "public static String[] getGemMods(" "public static String[] getPrecuMagicItemMods("
$magicFilter = Get-FunctionSlice $magicItem `
    "public static String[] getPrecuMagicItemMods(" "`n}"
Assert-Contract ($magicItem.Contains(
        "static_item.removeRetiredNgeStaticItemSkillModifiers(item)") -and
    $magicAppearance.Contains("getPrecuMagicItemMods(mods)") -and
    $magicGemMods.Contains(
        'getPrecuMagicItemMods(dataTableGetStringColumn(TBL_COST, "MOD"))') -and
    $magicFilter.Contains(
        "!static_item.isRetiredNgeStaticItemSkillModifier(modifierName)")) `
    "p14.item-level.magic-item-and-gem-filtered"

$craftingSkillModifierWriter = Get-FunctionSlice $craftingBase `
    "public boolean calcAndSetPrototypeProperty(" `
    "public void calcAndSetPrototypeProperties(obj_id prototype, draft_schematic.attribute[] itemAttributes, dictionary"
$skillBuffLegacyHandler = Get-FunctionSlice $skillBuffItem `
    "public int handleUseSkillBuff(" "public String formatTime("
Assert-Contract ($craftingSkillModifierWriter.IndexOf(
        "static_item.isRetiredNgeStaticItemSkillModifier(modifier)") -lt
        $craftingSkillModifierWriter.IndexOf(
            "setSkillModBonus(prototype, modifier, (int)itemAttribute.currentValue)") -and
    $consumable.IndexOf(
        "static_item.isRetiredNgeStaticItemSkillModifier(mod_name)") -lt
        $consumable.IndexOf(
            "addSkillModModifier(target, mod_id, mod_name, amount, duration") -and
    ([regex]::Matches($skillBuffLegacyHandler,
        "static_item\.isRetiredNgeStaticItemSkillModifier\(skill[12]\)")).Count -eq 2 -and
    $skillBuffLegacyHandler.Contains("if (!applied)")) `
    "p14.item-level.crafting-consumable-and-legacy-buff-filtered"
Assert-Contract ($craftingBaseClothing.Contains(
        "bio_engineer.BIO_COMP_EFFECT_SKILL_MODS") -and
    $craftingBaseClothing.Contains(
        "setSkillModBonus(prototype, skill_mod, mod_val[i])") -and
    $bioEngineer.Contains('"healing_efficiency"') -and
    $consumable.Contains('"resistance_poison"') -and
    $consumable.Contains('"absorption_poison"') -and
    $consumable.Contains('"resistance_disease"') -and
    $consumable.Contains('"absorption_disease"')) `
    "p14.item-level.precu-tissue-and-medical-modifiers-preserved"

$reverseMods = Get-Content -LiteralPath (Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/datatables/crafting/reverse_engineering_mods.tab") -Raw
$reverseSpecialMods = Get-Content -LiteralPath (Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/datatables/crafting/reverse_engineering_special_mods.tab") -Raw
$magicModCosts = Get-Content -LiteralPath (Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/datatables/magic_item/mod_cost.tab") -Raw
Assert-Contract ($reverseMods -match '(?m)^expertise_damage_weapon_0\t' -and
    $reverseMods -match '(?m)^general_assembly\t' -and
    $reverseMods -match '(?m)^resistance_poison\t' -and
    $reverseSpecialMods -match '(?m)^bm_xp_mod_boost\t' -and
    $reverseSpecialMods -match '(?m)^armor_assembly\t' -and
    $magicModCosts -match '(?m)^precision_modified\t' -and
    $magicModCosts -match '(?m)^weapon_assembly\t') `
    "p14.item-level.compatibility-modifier-data-preserved-runtime-filtered"

$legacyDynamicPrimaryModifiers = @(
    "precision_modified",
    "strength_modified",
    "stamina_modified",
    "constitution_modified",
    "agility_modified",
    "luck_modified"
)
$legacyModifierInventory = Get-FunctionSlice $staticItem `
    "public static final String[] LEGACY_NGE_DYNAMIC_PRIMARY_MODIFIERS" `
    "public static final java.text.NumberFormat"
$generateDynamicBonuses = Get-FunctionSlice $staticItem `
    "public static void generateItemStatBonuses(" `
    "public static void removeLegacyNgeDynamicPrimaryModifiers("
$cleanupDynamicBonuses = Get-FunctionSlice $staticItem `
    "public static void removeLegacyNgeDynamicPrimaryModifiers(" `
    "public static int generateStatMod("
$dynamicNameSuffix = Get-FunctionSlice $staticItem `
    "public static String getArmorNameSuffix(" `
    "public static void setupJunkDealerPrice("
$legacyInventoryExact = $true
$generationLegacyFree = $true
$suffixLegacyFree = $true
foreach ($modifier in $legacyDynamicPrimaryModifiers)
{
    if (([regex]::Matches($legacyModifierInventory,
            [regex]::Escape('"' + $modifier + '"'))).Count -ne 1)
    {
        $legacyInventoryExact = $false
    }
    if ($generateDynamicBonuses.Contains($modifier))
    {
        $generationLegacyFree = $false
    }
    if ($dynamicNameSuffix.Contains($modifier))
    {
        $suffixLegacyFree = $false
    }
}
Assert-Contract ($legacyDynamicPrimaryModifiers.Count -eq 6 -and
    $legacyInventoryExact) `
    "p14.item-level.dynamic-loot-legacy-primary-inventory"
Assert-Contract ($generateDynamicBonuses.StartsWith(
        "public static void generateItemStatBonuses(") -and
    $generateDynamicBonuses.IndexOf("removeLegacyNgeDynamicPrimaryModifiers(item)",
        [StringComparison]::Ordinal) -lt
        $generateDynamicBonuses.IndexOf("setObjVar(", [StringComparison]::Ordinal) -and
    ([regex]::Matches($generateDynamicBonuses, "setObjVar\(")).Count -eq 1 -and
    $generateDynamicBonuses.Contains(
        'setObjVar(item, "skillmod.bonus.camouflage", camouflageBonus)') -and
    $generationLegacyFree -and
    -not $generateDynamicBonuses.Contains('"skillmod.bonus." +')) `
    "p14.item-level.dynamic-loot-precu-camouflage-only"
Assert-Contract ($cleanupDynamicBonuses.Contains(
        "for (String modifier : LEGACY_NGE_DYNAMIC_PRIMARY_MODIFIERS)") -and
    $cleanupDynamicBonuses.Contains('String objVar = "skillmod.bonus." + modifier') -and
    $cleanupDynamicBonuses.Contains("removeObjVar(item, objVar)") -and
    -not $cleanupDynamicBonuses.Contains('removeObjVar(item, "skillmod.bonus")')) `
    "p14.item-level.dynamic-loot-exact-stale-leaf-cleanup"
Assert-Contract ($dynamicNameSuffix.Contains(
    "removeLegacyNgeDynamicPrimaryModifiers(item)") -and
    ([regex]::Matches($dynamicNameSuffix, '"camouflage"')).Count -eq 1 -and
    $suffixLegacyFree) `
    "p14.item-level.dynamic-loot-precu-name-suffix"

$dynamicAttach = Get-FunctionSlice $dynamicArmor `
    "public int OnAttach(" "public int OnInitialize("
$dynamicInitialize = Get-FunctionSlice $dynamicArmor `
    "public int OnInitialize(" "public int OnAboutToBeTransferred("
$dynamicTransfer = Get-FunctionSlice $dynamicArmor `
    "public int OnAboutToBeTransferred(" "public int OnTransferred("
$dynamicCleanupCalls = ([regex]::Matches($dynamicArmor,
    "static_item\.removeLegacyNgeDynamicPrimaryModifiers\(self\);")).Count
Assert-Contract ($dynamicCleanupCalls -eq 3 -and
    $dynamicAttach.Contains("removeLegacyNgeDynamicPrimaryModifiers") -and
    $dynamicInitialize.Contains("removeLegacyNgeDynamicPrimaryModifiers") -and
    $dynamicTransfer.Contains("removeLegacyNgeDynamicPrimaryModifiers")) `
    "p14.item-level.dynamic-loot-persisted-cleanup-lifecycle"
Assert-Contract ($dynamicInitialize.Contains("static_item.setupDynamicArmor") -and
    $dynamicTransfer.Contains("dynamic_item.required_skill") -and
    $dynamicTransfer.Contains("utils.meetsProfessionRequirement")) `
    "p14.item-level.dynamic-loot-lifecycle-and-skill-admission-preserved"

$createLootItem = Get-FunctionSlice $loot `
    "public static obj_id createLootItem(" `
    "public static boolean addMilkOrEgg("
$makeDynamicObject = Get-FunctionSlice $staticItem `
    "public static obj_id makeDynamicObject(" `
    "public static obj_id setupDynamicArmor("
$setupDynamicArmor = Get-FunctionSlice $staticItem `
    "public static obj_id setupDynamicArmor(obj_id objArmor, int intLevel, dictionary" `
    "public static obj_id setupDynamicWeapon("
$dynamicArmorTypes = Get-Content -LiteralPath (Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/datatables/item/dynamic_item/types/armor.tab") -Raw
$dynamicClothingTypes = Get-Content -LiteralPath (Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/datatables/item/dynamic_item/types/clothing.tab") -Raw
$skills = Get-Content -LiteralPath (Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab") -Raw
Assert-Contract ($createLootItem.Contains('strLootToMake.startsWith("dynamic_")') -and
    $createLootItem.Contains(
        "static_item.makeDynamicObject(strLootToMake, objContainer, intLevel)") -and
    $makeDynamicObject.Contains('strName.startsWith("dynamic_armor")') -and
    $makeDynamicObject.Contains('strName.startsWith("dynamic_clothing")') -and
    $makeDynamicObject.Contains("return setupDynamicArmor(") -and
    ([regex]::Matches($makeDynamicObject, "generateItemStatBonuses\(")).Count -eq 1 -and
    ([regex]::Matches($setupDynamicArmor, "generateItemStatBonuses\(")).Count -eq 1 -and
    $dynamicArmorTypes.Contains("dynamic_armor_standard") -and
    $dynamicClothingTypes.Contains("dynamic_clothing_standard")) `
    "p14.item-level.dynamic-loot-production-route-preserved"
Assert-Contract ($skills -match '(?m)^species_bothan\t.*camouflage=15' -and
    $skills -match '(?m)^outdoors_ranger_(master|movement_01)\t.*camouflage=') `
    "p14.item-level.dynamic-loot-camouflage-precu-authenticated"

$sourceHashPaths = @{
    staticItem = "dsrc/sku.0/sys.server/compiled/game/script/library/static_item.java"
    buffLibrary = "dsrc/sku.0/sys.server/compiled/game/script/library/buff.java"
    collectionLibrary = "dsrc/sku.0/sys.server/compiled/game/script/library/collection.java"
    playerStructure = "dsrc/sku.0/sys.server/compiled/game/script/library/player_structure.java"
    playerUtility = "dsrc/sku.0/sys.server/compiled/game/script/player/player_utility.java"
    buffHandler = "dsrc/sku.0/sys.server/compiled/game/script/systems/buff/buff_handler.java"
    specialSign = "dsrc/sku.0/sys.server/compiled/game/script/systems/sign/special_sign.java"
    tcgVendorContract = "dsrc/sku.0/sys.server/compiled/game/script/systems/tcg/tcg_vendor_contract.java"
    combatWeapon = "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_weapon.java"
    effectMapping = "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/effect_mapping.tab"
    buffTable = "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
    collectionRewards = "dsrc/sku.0/sys.server/compiled/game/datatables/collection/rewards.tab"
    dynamicArmor = "dsrc/sku.0/sys.server/compiled/game/script/item/armor/dynamic_armor.java"
    loot = "dsrc/sku.0/sys.server/compiled/game/script/library/loot.java"
    dynamicArmorTypes = "dsrc/sku.0/sys.server/compiled/game/datatables/item/dynamic_item/types/armor.tab"
    dynamicClothingTypes = "dsrc/sku.0/sys.server/compiled/game/datatables/item/dynamic_item/types/clothing.tab"
    skills = "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    stimpack = "dsrc/sku.0/sys.server/compiled/game/script/item/medicine/stimpack.java"
    stimpackCrafted = "dsrc/sku.0/sys.server/compiled/game/script/item/medicine/stimpack_crafted.java"
    forceMelon = "dsrc/sku.0/sys.server/compiled/game/script/item/plant/force_melon.java"
    skillBuffItem = "dsrc/sku.0/sys.server/compiled/game/script/item/skill_buff/base.java"
    reverseEngineeringPoweredItem = "dsrc/sku.0/sys.server/compiled/game/script/item/tool/reverse_engineering_poweredup_item.java"
    reverseEngineeringTool = "dsrc/sku.0/sys.server/compiled/game/script/item/tool/reverse_engineering_tool.java"
    bioEngineer = "dsrc/sku.0/sys.server/compiled/game/script/library/bio_engineer.java"
    consumable = "dsrc/sku.0/sys.server/compiled/game/script/library/consumable.java"
    healing = "dsrc/sku.0/sys.server/compiled/game/script/library/healing.java"
    magicItem = "dsrc/sku.0/sys.server/compiled/game/script/library/magic_item.java"
    reverseEngineering = "dsrc/sku.0/sys.server/compiled/game/script/library/reverse_engineering.java"
    craftingBase = "dsrc/sku.0/sys.server/compiled/game/script/systems/crafting/crafting_base.java"
    craftingBaseClothing = "dsrc/sku.0/sys.server/compiled/game/script/systems/crafting/clothing/crafting_base_clothing.java"
    weaponComponentAttributes = "dsrc/sku.0/sys.server/compiled/game/script/systems/crafting/weapon/component/crafting_weapon_component_attribute.java"
    reverseEngineeringMods = "dsrc/sku.0/sys.server/compiled/game/datatables/crafting/reverse_engineering_mods.tab"
    reverseEngineeringSpecialMods = "dsrc/sku.0/sys.server/compiled/game/datatables/crafting/reverse_engineering_special_mods.tab"
    magicItemModCost = "dsrc/sku.0/sys.server/compiled/game/datatables/magic_item/mod_cost.tab"
    armorStats = "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/armor_stats.tab"
    itemStats = "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/item_stats.tab"
    masterItem = "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/master_item.tab"
    weaponStats = "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/weapon_stats.tab"
    skillModListing = "dsrc/sku.0/sys.shared/compiled/game/datatables/expertise/skill_mod_listing.tab"
    advancedSearch = "dsrc/sku.0/sys.shared/compiled/game/datatables/commodity/advanced_search_attribute.tab"
    channelledStimA = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/channelled_stimpack/stimpack_a.tpf"
    channelledStimB = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/channelled_stimpack/stimpack_b.tpf"
    channelledStimC = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/channelled_stimpack/stimpack_c.tpf"
    instantStimA = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/instant_stimpack/stimpack_a.tpf"
    instantStimB = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/instant_stimpack/stimpack_b.tpf"
    instantStimC = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/instant_stimpack/stimpack_c.tpf"
    instantStimD = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/instant_stimpack/stimpack_d.tpf"
    instantStimE = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/instant_stimpack/stimpack_e.tpf"
    instantStimNoob = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/instant_stimpack/stimpack_noob.tpf"
    instantStimSyren = "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine/instant_stimpack/stimpack_syren.tpf"
}
$sourceHashesCurrent = $true
foreach ($entry in $sourceHashPaths.GetEnumerator())
{
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        (Join-Path $source $entry.Value)).Hash.ToLowerInvariant()
    if ($actualHash -cne [string]$contract.buildEvidence.sourceSha256.($entry.Key))
    {
        $sourceHashesCurrent = $false
    }
}
Assert-Contract $sourceHashesCurrent "p14.item-level.source-hashes"

$clickPaths = @(
    "item/buff_beast_click_item.java",
    "item/buff_click_item.java",
    "item/full_heal_item.java",
    "item/skillmod_click_item.java"
)
foreach ($relativePath in $clickPaths)
{
    $text = [string]$texts[$relativePath]
    Assert-Contract (-not $text.Contains("getLevel(") -and
        -not $text.Contains("required_level_for_effect") -and
        -not $text.Contains("validateLevelRequired") -and
        -not $text.Contains("SID_ITEM_LEVEL_TOO_LOW")) `
        "p14.item-level.click-item-no-combat-level.$relativePath"
}
Assert-Contract (([string]$texts["item/buff_click_item.java"]).Contains("buff.canApplyBuff") -and
    ([string]$texts["item/buff_click_item.java"]).Contains("sendCooldownGroupTimingOnly") -and
    ([string]$texts["item/buff_click_item.java"]).Contains("decrementStaticItem")) `
    "p14.item-level.click-item-lifecycle-preserved"
Assert-Contract (([string]$texts["item/skillmod_click_item.java"]).Contains("requiredSkill") -and
    ([string]$texts["item/skillmod_click_item.java"]).Contains("utils.meetsProfessionRequirement")) `
    "p14.item-level.skillmod-profession-gate-preserved"

$levelUpOrb = [string]$texts["item/levelup_orb/levelup_orb.java"]
Assert-Contract (-not $levelUpOrb.Contains("getLevel(") -and
    -not $levelUpOrb.Contains("player_level.iff") -and
    -not $levelUpOrb.Contains("xp.grant") -and
    -not $levelUpOrb.Contains("menu_info_types.ITEM_USE") -and
    $levelUpOrb.Contains('detachScript(self, "item.special.nomove")') -and
    $levelUpOrb.Contains("return SCRIPT_OVERRIDE")) `
    "p14.item-level.level-up-orb-inert-and-movable"

$stim = [string]$texts["item/medicine/stimpack.java"]
$craftedStim = [string]$texts["item/medicine/stimpack_crafted.java"]
$itemCombatLevelCleanup = Get-FunctionSlice $staticItem `
    "public static void removeLegacyNgeItemCombatLevelRequirement(" `
    "public static int generateStatMod("
Assert-Contract (-not $stim.Contains("combat_level_required") -and
    -not $stim.Contains("getLevel(") -and
    $stim.Contains('buff.hasBuff(player, "feign_death")') -and
    $stim.Contains("healing.useHealDamageItem")) `
    "p14.item-level.looted-stim-level-retired"
Assert-Contract (-not $craftedStim.Contains("combat_level_required") -and
    -not $craftedStim.Contains("getLevel(") -and
    $craftedStim.Contains('buff.hasBuff(player, "feign_death")') -and
    -not $craftedStim.Contains('buff.hasBuff(player, "recent_heal")') -and
    -not $craftedStim.Contains("healing.useChannelHealItem") -and
    ([regex]::Matches($craftedStim, "healing[.]useHealDamageItem")).Count -eq 2 -and
    $craftedStim.Contains('hasObjVar(self, "healing.pool")') -and
    [bool]$contract.expected.medicine.channelledStimImmediateHealAdapter) `
    "p14.item-level.crafted-stim-level-retired"
Assert-Contract (([regex]::Matches($stim,
        "static_item\.removeLegacyNgeItemCombatLevelRequirement\(self\);")).Count -eq 4 -and
    ([regex]::Matches($craftedStim,
        "static_item\.removeLegacyNgeItemCombatLevelRequirement\(self\);")).Count -eq 4 -and
    $itemCombatLevelCleanup.Contains(
        'hasObjVar(item, "healing.combat_level_required")') -and
    ([regex]::Matches($itemCombatLevelCleanup,
        'removeObjVar\(item, "healing\.combat_level_required"\)')).Count -eq 1 -and
    -not $itemCombatLevelCleanup.Contains('removeObjVar(item, "healing")')) `
    "p14.item-level.persisted-stim-exact-level-cleanup"

$channelHealEffectPredicate = Get-FunctionSlice $buffLibrary `
    "public static boolean isRetiredPostNgePlayerChannelHealEffect(" `
    "public static boolean isRetiredPostNgePlayerChannelHealBuff("
$channelHealBuffPredicate = Get-FunctionSlice $buffLibrary `
    "public static boolean isRetiredPostNgePlayerChannelHealBuff(" `
    "public static void clearPostNgePlayerChannelHealState("
$channelHealStateCleanup = Get-FunctionSlice $buffLibrary `
    "public static void clearPostNgePlayerChannelHealState(" `
    "public static void retirePostNgePlayerChannelHealState("
$channelHealLifecycleCleanup = Get-FunctionSlice $buffLibrary `
    "public static void retirePostNgePlayerChannelHealState(" `
    "public static boolean isRetiredPostNgePlayerModifierBuff("
$channelHealProgressionCleanup = Get-FunctionSlice $buffLibrary `
    "public static void retirePostNgeBuffProgression(" `
    "public static boolean canApplyBuff("
$channelHealAdmission = Get-FunctionSlice $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static int[] getGroups("
$channelHealAdmissionGate = $channelHealAdmission.IndexOf(
    "isRetiredPostNgePlayerChannelHealBuff(target, bdata)",
    [StringComparison]::Ordinal)
$channelHealExistingBuffReturn = $channelHealAdmission.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_CHANNEL_HEAL_EFFECT = "channel_heal_health"') -and
    $channelHealBuffPredicate.Contains("!isPlayer(target)") -and
    $channelHealBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $channelHealStateCleanup.Contains("!isPlayer(player)") -and
    $channelHealStateCleanup.Contains(
        'utils.getIntScriptVar(player, "channelHeal.suiPid")') -and
    $channelHealStateCleanup.Contains(
        "getIntObjVar(player, sui.COUNTDOWNTIMER_SUI_VAR) == channelHealSuiPid") -and
    $channelHealStateCleanup.Contains("if (ownsCountdown)") -and
    $channelHealStateCleanup.Contains('utils.removeScriptVarTree(player, "channelHeal")') -and
    $channelHealStateCleanup.Contains("forceCloseSUIPage(channelHealSuiPid)") -and
    $channelHealLifecycleCleanup.Contains("getAllBuffs(player)") -and
    $channelHealLifecycleCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $channelHealLifecycleCleanup.Contains("removeBuff(player, activeBuff)") -and
    $channelHealLifecycleCleanup.Contains("clearPostNgePlayerChannelHealState(player)") -and
    $channelHealProgressionCleanup.Contains("retirePostNgePlayerChannelHealState(player);") -and
    $channelHealAdmissionGate -ge 0 -and
    $channelHealExistingBuffReturn -gt $channelHealAdmissionGate -and
    -not [bool]$contract.expected.medicine.postCombatBalanceChannelHealPlayerReachable) `
    "p14.item-level.channel-heal-admission-persistence-and-state-fail-closed"

$channelHealAdapter = Get-FunctionSlice $healing `
    "public static boolean useChannelHealItem(obj_id user, obj_id item, int attrib)" `
    "public static boolean useHealPetItem("
$channelHealAdapterGuard = $channelHealAdapter.IndexOf(
    "if (isIdValid(user) && exists(user) && isPlayer(user))",
    [StringComparison]::Ordinal)
$channelHealAdapterCleanup = $channelHealAdapter.IndexOf(
    "buff.retirePostNgePlayerChannelHealState(user);",
    [StringComparison]::Ordinal)
$channelHealAdapterReturn = $channelHealAdapter.IndexOf(
    "return useHealDamageItem(user, item, attrib);",
    [StringComparison]::Ordinal)
$channelHealLegacyMessage = $channelHealAdapter.IndexOf(
    'messageTo(user, "channelHeal"', [StringComparison]::Ordinal)
$channelHealLegacyDecrement = $channelHealAdapter.IndexOf(
    "decrementCount(item);", [StringComparison]::Ordinal)
$channelHealCallback = Get-FunctionSlice $playerUtility `
    "public int channelHeal(obj_id self, dictionary params)" `
    "public int residentLinkFalse("
$channelHealCallbackGuard = $channelHealCallback.IndexOf(
    "if (isPlayer(self) && buff.isPostNgeBuffProgressionRetired())",
    [StringComparison]::Ordinal)
$channelHealCallbackCleanup = $channelHealCallback.IndexOf(
    "buff.retirePostNgePlayerChannelHealState(self);",
    [StringComparison]::Ordinal)
$channelHealCallbackReturn = $channelHealCallback.IndexOf(
    "return SCRIPT_CONTINUE;", $channelHealCallbackCleanup,
    [StringComparison]::Ordinal)
$channelHealCallbackWriter = $channelHealCallback.IndexOf(
    "healing.healDamage(self, self, attrib, healPerTick);",
    [StringComparison]::Ordinal)
$channelHealCallbackRequeue = $channelHealCallback.IndexOf(
    'messageTo(self, "channelHeal"', [StringComparison]::Ordinal)
Assert-Contract ($channelHealAdapterGuard -ge 0 -and
    $channelHealAdapterCleanup -gt $channelHealAdapterGuard -and
    $channelHealAdapterReturn -gt $channelHealAdapterCleanup -and
    $channelHealLegacyMessage -gt $channelHealAdapterReturn -and
    $channelHealLegacyDecrement -gt $channelHealAdapterReturn -and
    $channelHealCallbackGuard -ge 0 -and
    $channelHealCallbackCleanup -gt $channelHealCallbackGuard -and
    $channelHealCallbackReturn -gt $channelHealCallbackCleanup -and
    $channelHealCallbackWriter -gt $channelHealCallbackReturn -and
    $channelHealCallbackRequeue -gt $channelHealCallbackReturn -and
    [bool]$contract.expected.medicine.channelHealNonPlayerCompatibilityPreserved) `
    "p14.item-level.channel-heal-player-adapter-and-callback-fail-closed"

$channelHealHandlerExpectations = @(
    [pscustomobject]@{
        Slice = Get-FunctionSlice $buffHandler "public int OnCreatureDamaged(" `
            "public int attribAddBuffHandler("
        Cleanup = "buff.retirePostNgePlayerChannelHealState(self);"
        Return = "return SCRIPT_CONTINUE;"
        RetainedWriter = 'buff.hasBuff(self, "channel_healing")'
    },
    [pscustomobject]@{
        Slice = Get-FunctionSlice $buffHandler "public void channelHealAddBuffHandler(" `
            "public void channelHealRemoveBuffHandler("
        Cleanup = "buff.retirePostNgePlayerChannelHealState(self);"
        Return = "return;"
        RetainedWriter = "healing.useChannelHealItem(self, self, myAttribute)"
    },
    [pscustomobject]@{
        Slice = Get-FunctionSlice $buffHandler "public void channelHealRemoveBuffHandler(" `
            "public int getAttributeType("
        Cleanup = "buff.clearPostNgePlayerChannelHealState(self);"
        Return = "return;"
        RetainedWriter = 'utils.getIntScriptVar(self, "channelHeal.suiPid")'
    }
)
$guardedChannelHealHandlers = 0
foreach ($handlerExpectation in $channelHealHandlerExpectations)
{
    $guard = $handlerExpectation.Slice.IndexOf("if (isPlayer(self))",
        [StringComparison]::Ordinal)
    $cleanup = $handlerExpectation.Slice.IndexOf($handlerExpectation.Cleanup,
        [StringComparison]::Ordinal)
    $playerReturn = $handlerExpectation.Slice.IndexOf($handlerExpectation.Return, $cleanup,
        [StringComparison]::Ordinal)
    $retainedWriter = $handlerExpectation.Slice.IndexOf($handlerExpectation.RetainedWriter,
        [StringComparison]::Ordinal)
    if ($guard -ge 0 -and $cleanup -gt $guard -and
        $playerReturn -gt $cleanup -and $retainedWriter -gt $playerReturn)
    {
        ++$guardedChannelHealHandlers
    }
}
Assert-Contract ($guardedChannelHealHandlers -eq 3) `
    "p14.item-level.channel-heal-handlers-player-fail-closed"

$forceMelon = [string]$texts["item/plant/force_melon.java"]
Assert-Contract (([regex]::Matches($forceMelon,
        "static_item\.removeLegacyNgeItemCombatLevelRequirement\(self\);")).Count -eq 1 -and
    -not $forceMelon.Contains('setObjVar(self, "healing.combat_level_required"')) `
    "p14.item-level.force-melon-stale-level-cleanup"

$legacyCombatLevelPattern =
    '(?i)required[_ ]combat[_ ]level|combat[_ ]level[_ ]required|healing_combat_level_required|healing\.combat_level_required'
$itemStatsPath = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/item_stats.tab"
$masterItemPath = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/master_item.tab"
$advancedSearchPath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/commodity/advanced_search_attribute.tab"
$itemStatsLines = @(Get-Content -LiteralPath $itemStatsPath)
$masterItemLines = @(Get-Content -LiteralPath $masterItemPath)
$advancedSearchLines = @(Get-Content -LiteralPath $advancedSearchPath)
$expectedHealingPower = [ordered]@{
    item_stimpack_a_02_01 = 700
    item_stimpack_b_02_01 = 1600
    item_stimpack_c_02_01 = 2800
    item_stimpack_d_02_01 = 4000
    item_stimpack_e_02_01 = 4800
    item_tow_commander_stim_04_01 = 1500
    item_content_stim_donuts_02_01 = 485
    item_content_stim_fish_02_01 = 485
    item_content_stim_dragonet_steak_02_01 = 485
    item_content_stimpack_high_03_01 = 4500
    item_content_stimpack_high_04_01 = 4500
    item_gcw_base_health_a_03_01 = 3500
    item_gcw_base_health_b_03_01 = 4000
    item_gcw_base_health_c_03_01 = 4500
    item_gcw_base_health_d_03_01 = 5000
    item_gcw_base_health_e_04_01 = 5500
    item_gcw_base_action_a_03_01 = 1750
    item_gcw_base_action_b_03_01 = 2000
    item_gcw_base_action_c_03_01 = 2250
    item_gcw_base_action_d_03_01 = 2500
    item_gcw_base_action_e_04_01 = 2750
    item_off_temp_stimpack_02_01 = 945
    item_off_temp_stimpack_02_02 = 1505
    item_off_temp_stimpack_02_03 = 1910
    item_off_temp_stimpack_02_04 = 2485
    item_off_temp_stimpack_02_05 = 2975
    item_off_temp_stimpack_02_06 = 3465
}
$retainedStimRowsValid = $true
$retainedStimBindingsValid = $true
$retainedActionPoolRows = 0
foreach ($entry in $expectedHealingPower.GetEnumerator())
{
    $itemRows = @($itemStatsLines | Where-Object {
        [string]($_ -split "`t", 2)[0] -ceq [string]$entry.Key
    })
    if ($itemRows.Count -ne 1)
    {
        $retainedStimRowsValid = $false
    }
    else
    {
        $fields = [regex]::Split([string]$itemRows[0], "`t")
        $objvars = if ($fields.Count -gt 3) { [string]$fields[3] } else { "" }
        if (-not $objvars.Contains("int:healing.power=$($entry.Value)") -or
            $objvars -match $legacyCombatLevelPattern)
        {
            $retainedStimRowsValid = $false
        }
        if ([string]$entry.Key -like "item_gcw_base_action_*")
        {
            if ($objvars.Contains("int:healing.pool=2")) { $retainedActionPoolRows++ }
            else { $retainedStimRowsValid = $false }
        }
    }
    $masterRows = @($masterItemLines | Where-Object {
        [string]($_ -split "`t", 2)[0] -ceq [string]$entry.Key
    })
    if ($masterRows.Count -ne 1)
    {
        $retainedStimBindingsValid = $false
    }
    else
    {
        $masterFields = [regex]::Split([string]$masterRows[0], "`t")
        if ($masterFields.Count -le 10 -or
            [string]$masterFields[10] -notmatch
                '(^|,)item\.medicine\.stimpack(,|$)')
        {
            $retainedStimBindingsValid = $false
        }
    }
}
Assert-Contract ($expectedHealingPower.Count -eq 27 -and
    $retainedStimRowsValid -and $retainedActionPoolRows -eq 5 -and
    @($itemStatsLines | Where-Object {
        $_ -match $legacyCombatLevelPattern
    }).Count -eq 0) `
    "p14.item-level.static-stim-metadata-retired-content-preserved"
Assert-Contract $retainedStimBindingsValid `
    "p14.item-level.static-stim-master-bindings-preserved"

$templateRelativePaths = @(
    "channelled_stimpack/stimpack_a.tpf",
    "channelled_stimpack/stimpack_b.tpf",
    "channelled_stimpack/stimpack_c.tpf",
    "instant_stimpack/stimpack_a.tpf",
    "instant_stimpack/stimpack_b.tpf",
    "instant_stimpack/stimpack_c.tpf",
    "instant_stimpack/stimpack_d.tpf",
    "instant_stimpack/stimpack_e.tpf",
    "instant_stimpack/stimpack_noob.tpf",
    "instant_stimpack/stimpack_syren.tpf"
)
$templateRoot = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine"
$templateTexts = @{}
foreach ($relativePath in $templateRelativePaths)
{
    $path = Join-Path $templateRoot $relativePath
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.item-level.template.$relativePath"
    $templateTexts[$relativePath] = Get-Content -LiteralPath $path -Raw
}
$templateCombatLevelWriters = @($templateTexts.Values | Where-Object {
    [string]$_ -match $legacyCombatLevelPattern
})
Assert-Contract ($templateRelativePaths.Count -eq 10 -and
    $templateCombatLevelWriters.Count -eq 0 -and
    [string]$templateTexts["channelled_stimpack/stimpack_a.tpf"] -match
        'objvars =\+ \["healing\.power" = 1000\]' -and
    [string]$templateTexts["channelled_stimpack/stimpack_b.tpf"] -match
        'objvars =\+ \["healing\.power" = 2000\]' -and
    [string]$templateTexts["channelled_stimpack/stimpack_c.tpf"] -match
        'objvars =\+ \["healing\.power" = 4000\]' -and
    @($templateTexts.Values | Where-Object {
        [string]$_ -match 'scripts = \["item\.medicine\.stimpack_crafted"\]'
    }).Count -eq [int]$contract.expected.medicine.retainedChannelledStimTemplates -and
    [string]$templateTexts["instant_stimpack/stimpack_noob.tpf"] -match
        'objvars =\+ \["noTrade" = 1\]' -and
    [string]$templateTexts["instant_stimpack/stimpack_syren.tpf"] -match
        'objvars =\+ \["healing\.power" = 1500, "charges" = 3\]') `
    "p14.item-level.stim-template-level-retired-content-preserved"

$advancedCategories = @($advancedSearchLines | Select-Object -Skip 2 |
    Where-Object { -not [string]::IsNullOrWhiteSpace(
        [string]($_ -split "`t", 2)[0]) })
$wearableCategoryRows = @($advancedSearchLines | Where-Object {
    $_ -match '^misc_container_wearable\tbio_link\t'
})
Assert-Contract (@($advancedSearchLines | Where-Object {
        $_ -match $legacyCombatLevelPattern
    }).Count -eq 0 -and
    $advancedCategories.Count -eq 134 -and
    $wearableCategoryRows.Count -eq 1) `
    "p14.item-level.market-combat-level-filters-retired-taxonomy-preserved"

$weaponComponentAttributes = [string]$texts[
    "systems/crafting/weapon/component/crafting_weapon_component_attribute.java"]
Assert-Contract (-not ($weaponComponentAttributes -match $legacyCombatLevelPattern) -and
    $weaponComponentAttributes.Contains("int coreLevel = 0") -and
    $weaponComponentAttributes.Contains('"coreLevel"') -and
    $weaponComponentAttributes.Contains("weapons.getWeaponCoreData(coreLevel)")) `
    "p14.item-level.weapon-core-false-level-presentation-retired"

$survey = [string]$texts["item/survey_tool/survey_tool_script.java"]
$sampleLoop = Get-FunctionSlice $survey "public int sampleLoop(" `
    "public int handleRadioactiveConfirm("
Assert-Contract ($survey.Contains("PRECU_SAMPLE_ACTION_BASE_COST = 124") -and
    $survey.Contains("PRECU_SAMPLE_QUICKNESS_DIVISOR = 12.5f") -and
    $sampleLoop.Contains("getAttrib(player, QUICKNESS)") -and
    $sampleLoop.Contains("Math.max(0, PRECU_SAMPLE_ACTION_BASE_COST") -and
    $sampleLoop.Contains("drainAttributes(player, actioncost, 0)") -and
    -not $sampleLoop.Contains("getLevel(player)")) `
    "p14.item-level.sampling-quickness-formula"
Assert-Contract ((124 - [int](300 / 12.5)) -eq 100 -and
    (124 - [int](1500 / 12.5)) -eq 4) `
    "p14.item-level.sampling-formula-examples"

$itemPlayerLevelReads = @(Get-ChildItem -LiteralPath (Join-Path $scriptRoot "item") `
    -Filter "*.java" -File -Recurse | Select-String -Pattern `
    'getLevel\((player|transferer|user|who|self)\)')
Assert-Contract ($itemPlayerLevelReads.Count -eq 0) `
    "p14.item-level.item-tree-player-level-reads-zero"

Assert-Contract ($contract.status -in @("implemented-build-pending", "ready")) `
    "p14.item-level.contract.status"

if ($Expectation -eq "Ready")
{
    $compiledHashes = @($contract.buildEvidence.compiledClassSha256.PSObject.Properties)
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.item-level.ready-evidence"
    Assert-Contract ($compiledHashes.Count -eq 29 -and
        @($compiledHashes | Where-Object {
            [string]$_.Value -notmatch '^[a-f0-9]{64}$'
        }).Count -eq 0) `
        "p14.item-level.compiled-class-evidence"
    Assert-Contract ([string]$contract.buildEvidence.architecture -like
            "ELF 64-bit*" -and
        [string]$contract.buildEvidence.serverBinarySha256 -match
            '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        [int]$contract.runtimeEvidence.liveGameProcessCount -eq
            [int]$contract.runtimeEvidence.liveGameProcessesMappedBuiltBinary) `
        "p14.item-level.x64-runtime-evidence"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU item-level retirement failed: $($failures -join ', ')"
}

Write-Host "Publish 14 PRE-CU item-level retirement passed."
