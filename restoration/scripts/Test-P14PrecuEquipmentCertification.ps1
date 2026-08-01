[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
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
        $failures.Add($Name)
    }
}

function Get-FunctionSlice
{
    param([string]$Text, [string]$Start, [string]$Next)
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length,
        [StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$scriptRoot = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/script"
$paths = @{
    Combat = Join-Path $scriptRoot "library/combat.java"
    CombatBase = Join-Path $scriptRoot "systems/combat/combat_base.java"
    CombatWeapon = Join-Path $scriptRoot "systems/combat/combat_weapon.java"
    Utils = Join-Path $scriptRoot "library/utils.java"
    DynamicArmor = Join-Path $scriptRoot "item/armor/dynamic_armor.java"
    StaticBase = Join-Path $scriptRoot "item/static_item_base.java"
    StaticItem = Join-Path $scriptRoot "library/static_item.java"
}

foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.precu-equipment.source.$($entry.Key)"
}

$combat = Get-Content -LiteralPath $paths.Combat -Raw
$starter = Get-FunctionSlice -Text $combat `
    -Start "public static boolean isPrecuStarterWeapon(" `
    -Next "public static boolean hasCertification(obj_id objPlayer, obj_id objWeapon, boolean verbose)"
$certification = Get-FunctionSlice -Text $combat `
    -Start "public static boolean hasCertification(obj_id objPlayer, obj_id objWeapon, boolean verbose)" `
    -Next "public static void applyCombatSpeedDelay("
$missChance = Get-FunctionSlice -Text $combat `
    -Start "public static float getMissChance(" `
    -Next "public static float getAttackerMissChance("

Assert-Contract ($starter.Contains("legacyLevel >= 0 && legacyLevel <= 1") -and
    $starter.Contains('dynamic_item.intLevelRequired') -and
    $starter.Contains('"weapon_level"')) `
    "p14.precu-equipment.legacy-cl1-starter-marker"
Assert-Contract ($certification.Contains("hasCert && isPrecuStarterWeapon(objWeapon)") -and
    $certification.IndexOf("isPrecuStarterWeapon", [StringComparison]::Ordinal) -lt
        $certification.IndexOf("getRequiredCertifications", [StringComparison]::Ordinal)) `
    "p14.precu-equipment.cl1-certified-before-skill-gate"
Assert-Contract ($combat.Contains("PRECU_UNCERTIFIED_WEAPON_MISS_PENALTY = 50.0f") -and
    $missChance.Contains("!hasCertification(attacker, currentWeapon, false)") -and
    $missChance.Contains("missChance += PRECU_UNCERTIFIED_WEAPON_MISS_PENALTY")) `
    "p14.precu-equipment.uncertified-heavy-accuracy-penalty"

$combatBase = Get-Content -LiteralPath $paths.CombatBase -Raw
$rawDamage = Get-FunctionSlice -Text $combatBase `
    -Start "public dictionary getRawDamage(" `
    -Next "public float getWeaponPercentAddFromWeapon("
Assert-Contract (-not $rawDamage.Contains("checkWeaponCerts") -and
    -not $rawDamage.Contains("minDamage = 5.0f") -and
    -not $rawDamage.Contains("maxDamage = 10.0f") -and
    $rawDamage.Contains("weaponData.elementalValue")) `
    "p14.precu-equipment.damage-speed-element-preserved"

$weapon = Get-Content -LiteralPath $paths.CombatWeapon -Raw
$weaponTransfer = Get-FunctionSlice -Text $weapon `
    -Start "public int OnAboutToBeTransferred(" `
    -Next "public int OnTransferred("
$weaponAttributes = Get-FunctionSlice -Text $weapon `
    -Start "public int OnGetAttributes(" `
    -Next "public int OnGetSkillMods("
Assert-Contract ($weaponTransfer.Contains("return SCRIPT_CONTINUE") -and
    -not $weaponTransfer.Contains("hasCertification") -and
    -not $weaponTransfer.Contains("SCRIPT_OVERRIDE")) `
    "p14.precu-equipment.uncertified-weapon-equip-allowed"
Assert-Contract (-not $weaponAttributes.Contains("healing_combat_level_required")) `
    "p14.precu-equipment.weapon-level-attribute-retired"

$utils = Get-Content -LiteralPath $paths.Utils -Raw
$revalidate = Get-FunctionSlice -Text $utils `
    -Start "public static int unequipAndNotifyUncerted(" `
    -Next "public static int getIntObjVar("
Assert-Contract (-not $revalidate.Contains("!combat.hasCertification(player, weapon)") -and
    -not $revalidate.Contains('"weapon_lost_cert"')) `
    "p14.precu-equipment.weapon-not-auto-unequipped"

$dynamicArmor = Get-Content -LiteralPath $paths.DynamicArmor -Raw
$armorTransfer = Get-FunctionSlice -Text $dynamicArmor `
    -Start "public int OnAboutToBeTransferred(" `
    -Next "public int OnTransferred("
$armorAttributes = Get-FunctionSlice -Text $dynamicArmor `
    -Start "public int OnGetAttributes(" `
    -Next "public int OnGetSkillMods("
Assert-Contract (-not $armorTransfer.Contains("getLevel(") -and
    -not $armorTransfer.Contains("SID_ITEM_LEVEL_TOO_LOW") -and
    $armorTransfer.Contains("requiredSkill")) `
    "p14.precu-equipment.dynamic-armor-level-gate-retired"
Assert-Contract (-not $armorAttributes.Contains("required_combat_level")) `
    "p14.precu-equipment.dynamic-armor-level-attribute-retired"

$staticBase = Get-Content -LiteralPath $paths.StaticBase -Raw
$staticTransfer = Get-FunctionSlice -Text $staticBase `
    -Start "public int OnAboutToBeTransferred(" `
    -Next "public int OnTransferred("
$staticAttributes = Get-FunctionSlice -Text $staticBase `
    -Start "public int OnGetAttributes(" `
    -Next "public int handlerVersionUpdate("
Assert-Contract ($staticTransfer.Contains("boolean precuEquipment = itemType == 1 || itemType == 2") -and
    $staticTransfer.Contains("itemType != 1") -and
    $staticTransfer.Contains("!precuEquipment && !static_item.validateLevelRequired")) `
    "p14.precu-equipment.static-weapon-armor-level-bypass"
Assert-Contract (-not $staticAttributes.Contains("required_combat_level")) `
    "p14.precu-equipment.static-equipment-level-attribute-retired"

$staticItem = Get-Content -LiteralPath $paths.StaticItem -Raw
$objectValidation = Get-FunctionSlice -Text $staticItem `
    -Start "public static boolean validateLevelRequired(obj_id player, obj_id item)" `
    -Next "public static boolean validateLevelRequiredForWornEffect("
$staticWeaponAttributes = Get-FunctionSlice -Text $staticItem `
    -Start "public static void getStaticWeaponObjectAttributes(" `
    -Next "public static void getStaticArmorObjectAttributes("
$staticArmorAttributes = Get-FunctionSlice -Text $staticItem `
    -Start "public static void getStaticArmorObjectAttributes(" `
    -Next "public static void getStaticItemObjectAttributes("
Assert-Contract ($objectValidation.Contains("GOT_weapon") -and
    $objectValidation.Contains("GOT_armor") -and
    $objectValidation.Contains("return true;")) `
    "p14.precu-equipment.worn-equipment-never-level-invalidated"
Assert-Contract (-not $staticWeaponAttributes.Contains("healing_combat_level_required") -and
    -not $staticArmorAttributes.Contains("healing_combat_level_required")) `
    "p14.precu-equipment.static-level-attributes-retired"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU equipment certification contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14 PRE-CU equipment certification contract passed."
