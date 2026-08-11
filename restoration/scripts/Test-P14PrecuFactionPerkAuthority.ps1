[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuFactionPerkAuthority)
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
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.faction-perk.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $sha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.faction-perk.overlay.authenticated"
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$paths = [ordered]@{
    "script.library.factions" = Join-Path $scriptRoot "library/factions.java"
    "script.library.faction_perk" = Join-Path $scriptRoot "library/faction_perk.java"
    "script.npc.faction_recruiter" = Join-Path $scriptRoot "npc/faction_recruiter/faction_recruiter.java"
    "script.systems.camping.camp_controlpanel" = Join-Path $scriptRoot "systems/camping/camp_controlpanel.java"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.faction-perk.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($actualHash -ceq [string]$contract.buildEvidence.sourceSha256.$name) `
            "p14.faction-perk.source.$name.authenticated"
    }
}
$dsrcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "dsrc"
})
Assert-Contract ($dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq
        [string]$contract.buildEvidence.directSourceGitlink) `
    "p14.faction-perk.direct-source-pin"

$factions = [string]$texts["script.library.factions"]
$perk = [string]$texts["script.library.faction_perk"]
$recruiter = [string]$texts["script.npc.faction_recruiter"]
$camp = [string]$texts["script.systems.camping.camp_controlpanel"]

$cap = Get-FunctionSlice $factions `
    "public static float getFactionMax(obj_id target, String factionName)" `
    "public static void validateFactionStanding"
Assert-Contract ($cap.Contains('normalizedFaction.equals("rebel")') -and
    $cap.Contains('normalizedFaction.equals("imperial")') -and
    $cap.Contains("return NON_ALIGNED_FACTION_MAX") -and
    $cap.Contains("pvpGetCurrentGcwRank(target)") -and
    $cap.Contains("Math.max(NON_ALIGNED_FACTION_MAX, getRankCost(rank) * 20.0f)")) `
    "p14.faction-perk.rank-scaled-standing-cap"

$prejudice = Get-FunctionSlice $perk `
    "public static int prejudicePerkCost" `
    "public static float getFactionPrejudice"
Assert-Contract ($prejudice.Contains("getFactionPrejudice(species, faction)") -and
    -not $prejudice.Contains("expertise") -and
    -not $prejudice.Contains("getExpertiseModifier")) `
    "p14.faction-perk.species-prejudice-without-nge-expertise"

$categoryMenu = Get-FunctionSlice $perk `
    "public static boolean displayAvailableFactionItemRanks" `
    "public static boolean isValidPrecuFactionPurchase"
$categoryTables = Get-FunctionSlice $perk `
    "public static String[] getPrecuCategoryTables" `
    "public static String getPrecuCategoryTitle"
$availability = Get-FunctionSlice $perk `
    "public static boolean isAvailablePrecuFactionItem" `
    "public static String getPrecuFactionItemName"
Assert-Contract ($categoryMenu.Contains("PRECU_CATEGORY_FURNITURE") -and
    $categoryMenu.Contains("PRECU_CATEGORY_WEAPONS_ARMOR") -and
    $categoryMenu.Contains("PRECU_CATEGORY_INSTALLATIONS") -and
    $categoryMenu.Contains("PRECU_CATEGORY_UNIFORMS") -and
    $categoryMenu.Contains("PRECU_CATEGORY_HIRELINGS") -and
    $categoryMenu.Contains("PRECU_CATEGORY_SCHEMATICS") -and
    $categoryMenu.Contains("factions.isDeclared(player)") -and
    $categoryMenu.Contains('toLower(playerGcwFaction).equals("imperial")')) `
    "p14.faction-perk.precu-category-and-declaration-menu"
Assert-Contract ($categoryTables.Contains('TBL_PERK_INVENTORY_BASE + toLower(faction) + "/"') -and
    $categoryTables.Contains('base + "furniture.iff"') -and
    $categoryTables.Contains('base + "weapon.iff"') -and
    $categoryTables.Contains('base + "installation.iff"') -and
    $categoryTables.Contains('base + "uniform.iff"') -and
    $categoryTables.Contains('base + "hireling.iff"') -and
    $categoryTables.Contains('base + "schematic.iff"') -and
    -not $categoryTables.Contains("equipment.iff") -and
    -not $categoryTables.Contains("gcw_rewards.iff")) `
    "p14.faction-perk.faction-specific-tables-no-nge-equipment"
Assert-Contract ($availability.Contains('row.getInt("declared") == 1') -and
    $availability.Contains("factions.isDeclared(player)") -and
    $availability.Contains("hasSchematic(player, template)") -and
    -not $availability.Contains("requiredLevel") -and
    -not $availability.Contains("requiredClasses") -and
    -not $availability.Contains("requiredSkills")) `
    "p14.faction-perk.row-admission-without-nge-progression"

$purchaseDisplay = Get-FunctionSlice $perk `
    "public static boolean displayItemPurchaseSUI(obj_id player, String category" `
    "public static float getModifiedGCWCost"
$purchase = Get-FunctionSlice $perk `
    "public static void factionItemPurchased(dictionary params, float systemMultiplier)" `
    "public static boolean isPrecuCategoryTable"
$activePurchaseSurface = $categoryMenu + $purchaseDisplay + $purchase + $prejudice
Assert-Contract ($purchaseDisplay.Contains('" (Faction Points: " + cost + ")"') -and
    $purchase.Contains("isPrecuCategoryTable(perksDatatable, faction, category)") -and
    $purchase.Contains("dataTableGetRow(perksDatatable, idx)") -and
    $purchase.Contains("isAvailablePrecuFactionItem(player, row)") -and
    $purchase.Contains("standing < cost + factions.FACTION_RATING_DECLARABLE_MIN") -and
    $purchase.Contains("addUnmodifiedFactionStanding(player, faction, -cost, false)")) `
    "p14.faction-perk.faction-point-transaction-and-reserve"
Assert-Contract ($purchase.Contains("temp_schematic.revoke(player, item_template)") -and
    $purchase.Contains("revokeSchematic(player, item_template)") -and
    $purchase.Contains("destroyObject(grantedObject)") -and
    $purchase.IndexOf("if (!granted)", [System.StringComparison]::Ordinal) -lt
        $purchase.IndexOf("addUnmodifiedFactionStanding", [System.StringComparison]::Ordinal)) `
    "p14.faction-perk.create-then-deduct-with-rollback"
Assert-Contract (-not $activePurchaseSurface.Contains("gcw_rewards.iff") -and
    -not $activePurchaseSurface.Contains("money.hasFunds") -and
    -not $activePurchaseSurface.Contains("money.requestPayment") -and
    -not $activePurchaseSurface.Contains("getModifiedGCWCost(") -and
    -not $activePurchaseSurface.Contains("requiredLevel") -and
    -not $activePurchaseSurface.Contains("requiredClasses") -and
    -not $activePurchaseSurface.Contains("expertise_faction_cost_bonus")) `
    "p14.faction-perk.nge-catalog-credit-level-and-price-paths-unreachable"

$release = Get-FunctionSlice $factions `
    "public static boolean releaseFactionHirelings" `
    "public static boolean isNewlyDeclared"
Assert-Contract ($purchase.Contains("pet_lib.PET_CTRL_DEVICE_TEMPLATE") -and
    $purchase.Contains('setObjVar(grantedObject, "ai.pet.type", pet_lib.PET_TYPE_NPC)') -and
    $purchase.Contains("VAR_FACTION_HIRELING") -and
    $purchase.Contains('attachScript(grantedObject, "ai.pet_control_device")') -and
    $release.Contains("CALLABLE_TYPE_COMBAT_PET") -and
    $release.Contains("callable.getCallableCD(hireling)") -and
    $release.Contains("VAR_FACTION_HIRELING")) `
    "p14.faction-perk.hireling-control-device-lifecycle"

$onAttach = Get-FunctionSlice $recruiter `
    "public int OnAttach(obj_id self)" `
    "public int OnInitialize(obj_id self)"
$onInitialize = Get-FunctionSlice $recruiter `
    "public int OnInitialize(obj_id self)" `
    "public int OnObjectMenuRequest"
Assert-Contract ($onAttach.Contains('detachScript(self, "npc.vendor.vendor")') -and
    $onAttach.Contains('removeObjVar(self, "item.vendor.vendor_table")') -and
    $onInitialize.Contains('detachScript(self, "npc.vendor.vendor")') -and
    $onInitialize.Contains('removeObjVar(self, "item.vendor.vendor_table")') -and
    -not ($onAttach + $onInitialize).Contains('attachScript(self, "npc.vendor.vendor")')) `
    "p14.faction-perk.recruiter-vendor-precedence-retired"
Assert-Contract ($recruiter.Contains('utils.getStringBatchScriptVar(self, categoriesVar)') -and
    $recruiter.Contains("displayItemPurchaseSUI(player, categories[idx], playerGcwFaction, self)")) `
    "p14.faction-perk.stable-category-selection"
Assert-Contract (-not $camp.Contains("faction_perk") -and
    -not $camp.Contains("msgFactionItemPurchaseSelected") -and
    -not $camp.Contains("requisition") -and
    $camp.Contains("showStatus(self, player)") -and
    $camp.Contains("SID_MNU_DISBAND") -and
    $camp.Contains("if (owner == player)") -and
    $camp.Contains("camping.awardCampExperienceAndNuke(master);") -and
    -not $camp.Contains("camping.nukeCamp(master);") -and
    [bool]$contract.expected.ownerRadialCampDisbandPreserved) `
    "p14.faction-perk.camp-field-requisition-retired-owner-disband-preserved"
Assert-Contract (-not $patchText.Contains("/mission/") -and
    -not $patchText.Contains("missions.java") -and
    -not $patchText.Contains("mission_terminal")) `
    "p14.faction-perk.mission-terminal-source-untouched"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.faction-perk.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU faction perk authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU faction perk authority passed."
