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
    "library/consumable.java",
    "library/loot.java",
    "library/magic_item.java",
    "library/reverse_engineering.java",
    "library/static_item.java",
    "systems/crafting/crafting_base.java",
    "systems/crafting/clothing/crafting_base_clothing.java",
    "systems/crafting/weapon/component/crafting_weapon_component_attribute.java"
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
$consumable = [string]$texts["library/consumable.java"]
$skillBuffItem = [string]$texts["item/skill_buff/base.java"]
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
    "public static final java.text.NumberFormat"
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
    $craftedStim.Contains('buff.hasBuff(player, "recent_heal")') -and
    $craftedStim.Contains("healing.useChannelHealItem")) `
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
    }).Count -eq 3 -and
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
    Assert-Contract ($compiledHashes.Count -eq 21 -and
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
