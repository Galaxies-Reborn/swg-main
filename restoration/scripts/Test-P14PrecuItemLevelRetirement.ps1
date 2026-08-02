[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
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

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU item-level retirement failed: $($failures -join ', ')"
}

Write-Host "Publish 14 PRE-CU item-level retirement passed."
