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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuGroundLootScoutForageAuthority)
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
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.ground-loot-forage.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $sha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.ground-loot-forage.overlay.authenticated"
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$paths = [ordered]@{
    "script.library.loot" = Join-Path $scriptRoot "library/loot.java"
    "script.player.player_utility" = Join-Path $scriptRoot "player/player_utility.java"
    "script.ai.ai" = Join-Path $scriptRoot "ai/ai.java"
    "script.systems.treasure_map.base.treasure_map" = Join-Path $scriptRoot "systems/treasure_map/base/treasure_map.java"
    "datatables.item.master_item.item_stats" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/item_stats.tab"
    "datatables.item.master_item.master_item" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/master_item.tab"
    "datatables.treasure_map.treasure_map" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/treasure_map/treasure_map.tab"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.ground-loot-forage.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($actualHash -ceq [string]$contract.buildEvidence.sourceSha256.$name) `
            "p14.ground-loot-forage.source.$name.authenticated"
    }
}

$loot = [string]$texts["script.library.loot"]
$playerUtility = [string]$texts["script.player.player_utility"]
$ai = [string]$texts["script.ai.ai"]
$treasureMap = [string]$texts["script.systems.treasure_map.base.treasure_map"]
$treasureItemStats = [string]$texts["datatables.item.master_item.item_stats"]
$treasureMasterItems = [string]$texts["datatables.item.master_item.master_item"]
$treasureTable = [string]$texts["datatables.treasure_map.treasure_map"]

$addLoot = Get-FunctionSlice $loot `
    "public static boolean addLoot(obj_id target)" `
    "public static boolean addGoldenTicket("
Assert-Contract ($addLoot.Contains("addCashAsLoot(target, cash)") -and
    $addLoot.Contains("setupLootItems(target)") -and
    $addLoot.Contains("addCollectionLoot(target)") -and
    $addLoot.Contains("corpse.VAR_HAS_RESOURCE") -and
    -not $addLoot.Contains("addRareLoot") -and
    -not $addLoot.Contains("addBeastEnzymes")) `
    "p14.ground-loot-forage.authored-corpse-loot-only"

$rls = Get-FunctionSlice $loot `
    "public static boolean addRareLoot(obj_id target)" `
    "private static boolean retiredNgeAddRareLoot("
$ngeForage = Get-FunctionSlice $loot `
    "public static boolean playerForaging(obj_id player)" `
    "private static boolean retiredNgePlayerForaging("
Assert-Contract ($rls.Contains("return false;") -and
    -not $rls.Contains("rlsEnabled") -and
    $ngeForage.Contains("Rejected retired NGE Beast Master forage loot pipeline") -and
    $ngeForage.Contains("return false;")) `
    "p14.ground-loot-forage.nge-public-entrypoints-inert"

$treasureBand = Get-FunctionSlice $loot `
    "public static String getPlayerTreasureMapString(obj_id player)" `
    "public static boolean giveForagedCollectionObject("
Assert-Contract ($treasureBand.Contains("skill.getPrecuEncounterDifficulty(player)") -and
    -not $treasureBand.Contains("getLevel(player)")) `
    "p14.ground-loot-forage.treasure-map-hidden-skill-authority"

$treasureBands = @(
    @{ Name = "1_10"; Min = 1; Max = 10 },
    @{ Name = "11_20"; Min = 11; Max = 20 },
    @{ Name = "21_30"; Min = 21; Max = 30 },
    @{ Name = "31_40"; Min = 31; Max = 40 },
    @{ Name = "41_50"; Min = 41; Max = 50 },
    @{ Name = "51_60"; Min = 51; Max = 60 },
    @{ Name = "61_70"; Min = 61; Max = 70 },
    @{ Name = "71_80"; Min = 71; Max = 80 },
    @{ Name = "81_90"; Min = 81; Max = 90 }
)
$bandContentValid = $true
foreach ($band in $treasureBands)
{
    $itemName = "item_treasure_map_$($band.Name)"
    if ($treasureBand -notmatch [regex]::Escape('"' + $band.Name + '"') -or
        $treasureItemStats -notmatch ('(?m)^' + [regex]::Escape($itemName) +
            '\t[^\r\n]*int:min=' + $band.Min + ',int:max=' + $band.Max +
            ',string:mob=treasure_guard_') -or
        $treasureMasterItems -notmatch ('(?m)^' + [regex]::Escape($itemName) +
            '\tobject/tangible/treasure_map/treasure_map_base\.iff\t'))
    {
        $bandContentValid = $false
    }
}
$treasureRows = @(ConvertFrom-Csv -InputObject $treasureTable -Delimiter ([char]9) |
    Where-Object { [string]$_.map_level_min -match '^\d+$' })
Assert-Contract ($treasureBands.Count -eq [int]$contract.expected.treasureMapBandRows -and
    $treasureRows.Count -eq $treasureBands.Count -and
    $bandContentValid) `
    "p14.ground-loot-forage.retained-treasure-band-content-complete"

$mapGroupDifficulty = Get-FunctionSlice $treasureMap `
    "public boolean setPlayerGroupLevel(" `
    "public int findAmbushNearBy("
$mapNearbyDifficulty = Get-FunctionSlice $treasureMap `
    "public int findAmbushNearBy(" `
    "public int getEnemyReCount("
Assert-Contract ($mapGroupDifficulty.Contains("skill.getPrecuEncounterDifficulty(player)") -and
    $mapGroupDifficulty.Contains("skill.getPrecuEncounterDifficulty(groupOid)") -and
    $mapNearbyDifficulty.Contains("skill.getPrecuEncounterDifficulty(playersNear[i])") -and
    -not $treasureMap.Contains("getLevel(") -and
    $treasureMap -notmatch '(?i)combat level|player level' -and
    -not [bool]$contract.expected.treasureMapVisibleCombatLevel) `
    "p14.ground-loot-forage.treasure-encounter-precu-authority-and-language"

$corpsePrepared = Get-FunctionSlice $ai `
    "public int aiCorpsePrepared(obj_id self, dictionary params)" `
    "public int corpseCleanup(obj_id self, dictionary params)"
Assert-Contract ($corpsePrepared.Contains("loot.addLoot(self)") -and
    $corpsePrepared.Contains('getConfigSetting("EventTeam", "goldenTicket")') -and
    $corpsePrepared.Contains("loot.addGoldenTicket(killer, self)") -and
    $corpsePrepared.Contains("corpse.showLootMeParticle(self)") -and
    $corpsePrepared.Contains('setObjVar(self, "readyToLoot", true)') -and
    -not $corpsePrepared.Contains("addChronicleLoot") -and
    -not $corpsePrepared.Contains("scheduled_drop") -and
    -not $corpsePrepared.Contains("getLevel(")) `
    "p14.ground-loot-forage.global-post-era-corpse-injections-zero"

$forage = Get-FunctionSlice $playerUtility `
    "public int forage(obj_id self, obj_id target, String params, float defaultTime)" `
    "public int handlerForPlayerForaging("
Assert-Contract ($forage.Contains('hasSkill(self, "outdoors_scout_camp_01")') -and
    $forage.Contains('PRECU_SCOUT_FORAGE + ".pending"') -and
    $forage.Contains('PRECU_MEDICAL_FORAGE + ".pending"') -and
    $forage.Contains("getMountId(self)") -and
    $forage.Contains("isIdValid(start.cell)") -and
    $forage.Contains("getPrecuScoutForageActionCost(self)") -and
    $forage.Contains("drainAttributes(self, actionCost, 0)") -and
    $forage.Contains("PRECU_SCOUT_FORAGE_DELAY")) `
    "p14.ground-loot-forage.scout-admission-action-delay"

$handler = Get-FunctionSlice $playerUtility `
    "public int handlerForPlayerForaging(obj_id self, dictionary params)" `
    "private int getPrecuScoutForageActionCost("
Assert-Contract ($handler.Contains("isSamePrecuMedicalForagePosition(start, current)") -and
    $handler.Contains("STATE_COMBAT") -and
    $handler.Contains("reservePrecuScoutForageArea(self, start)") -and
    $handler.Contains('getSkillStatMod(self, "foraging")') -and
    $handler.Contains("15 + (skillMod * 0.8f)") -and
    $handler.Contains("rand(0, 80)") -and
    $handler.Contains('hasSkill(self, "outdoors_scout_camp_03")') -and
    $handler.Contains('hasSkill(self, "outdoors_scout_master")') -and
    $handler.Contains("rewardRoll < 160") -and
    $handler.Contains("rewardRoll < 200")) `
    "p14.ground-loot-forage.core3-success-and-reward-rolls"

$action = Get-FunctionSlice $playerUtility `
    "private int getPrecuScoutForageActionCost(" `
    "private boolean reservePrecuScoutForageArea("
$area = Get-FunctionSlice $playerUtility `
    "private boolean reservePrecuScoutForageArea(" `
    "private void storePrecuScoutForageAreas("
Assert-Contract ($playerUtility.Contains("PRECU_SCOUT_FORAGE_BASE_ACTION = 50") -and
    $playerUtility.Contains("PRECU_SCOUT_FORAGE_DELAY = 8.5f") -and
    $action.Contains("getAttrib(player, QUICKNESS) - 300.0f") -and
    $action.Contains("/ 1200.0f") -and
    $playerUtility.Contains("PRECU_SCOUT_FORAGE_AREA_SIZE = 10") -and
    $playerUtility.Contains("PRECU_SCOUT_FORAGE_AREA_USES = 3") -and
    $playerUtility.Contains("PRECU_SCOUT_FORAGE_AREA_EXPIRE = 1800") -and
    $playerUtility.Contains("PRECU_SCOUT_FORAGE_AREA_LIMIT = 120") -and
    $area.Contains("PRECU_SCOUT_FORAGE_AREA_SIZE") -and
    $area.Contains("PRECU_SCOUT_FORAGE_AREA_USES")) `
    "p14.ground-loot-forage.quickness-and-area-exhaustion"

$food = Get-FunctionSlice $playerUtility `
    "private obj_id givePrecuScoutForageFood(" `
    "private obj_id givePrecuScoutForageBait("
$bait = Get-FunctionSlice $playerUtility `
    "private obj_id givePrecuScoutForageBait(" `
    "private obj_id givePrecuScoutForageMap("
$map = Get-FunctionSlice $playerUtility `
    "private obj_id givePrecuScoutForageMap(" `
    "public int medicalForage("
Assert-Contract (([regex]::Matches($playerUtility, 'object/tangible/food/foraged/')).Count -ge 27 -and
    $playerUtility.Contains("edible_jar_funk.iff") -and
    $playerUtility.Contains("bait_chum.iff") -and
    $food.Contains("rand(0, 9999999)") -and
    $food.Contains("PRECU_SCOUT_FORAGE_FOOD_WEIGHT") -and
    $bait.Contains("PRECU_SCOUT_FORAGE_BAIT") -and
    $map.Contains("loot.getPlayerTreasureMapString(player)") -and
    $map.Contains('map = "item_treasure_map_1_10"')) `
    "p14.ground-loot-forage.authored-food-bait-map-pools"

$medicalForage = Get-FunctionSlice $playerUtility `
    "public int medicalForage(" `
    "public int handlerForMedicalForaging("
Assert-Contract ($medicalForage.Contains('PRECU_MEDICAL_FORAGE + ".pending"') -and
    $medicalForage.Contains('PRECU_SCOUT_FORAGE + ".pending"')) `
    "p14.ground-loot-forage.medical-forage-mutual-exclusion-preserved"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.ground-loot-forage.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU ground loot and Scout forage authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU ground loot and Scout forage authority passed."
