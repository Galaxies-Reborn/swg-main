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
    "item/skillmod_click_item.java",
    "item/static_item_base.java",
    "item/survey_tool/survey_tool_script.java",
    "library/loot.java",
    "library/static_item.java"
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
Assert-Contract $sourceHashesCurrent "p14.item-level.dynamic-loot-source-hashes"

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

$forceMelon = [string]$texts["item/plant/force_melon.java"]
Assert-Contract ($forceMelon.Contains('removeObjVar(self, "healing.combat_level_required")') -and
    -not $forceMelon.Contains('setObjVar(self, "healing.combat_level_required"')) `
    "p14.item-level.force-melon-stale-level-cleanup"

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
    Assert-Contract ($compiledHashes.Count -eq 13 -and
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
