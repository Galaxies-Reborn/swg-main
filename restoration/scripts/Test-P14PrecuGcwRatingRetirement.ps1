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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuGcwRatingRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$manifestDsrc = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$manifestSrc = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$indexedDsrcCommit = (& git -C $repositoryRoot rev-parse ":dsrc").Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the parent repository's indexed dsrc gitlink." }
$checkedOutDsrcCommit = (& git -C (Join-Path $repositoryRoot "dsrc") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out dsrc commit." }
$indexedSrcCommit = (& git -C $repositoryRoot rev-parse ":src").Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the parent repository's indexed src gitlink." }
$checkedOutSrcCommit = (& git -C (Join-Path $repositoryRoot "src") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out src commit." }

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

function Get-BeforeFirstReturn([string]$Text)
{
    $index = $Text.IndexOf("return;", [System.StringComparison]::Ordinal)
    if ($index -lt 0) { return $Text }
    return $Text.Substring(0, $index + "return;".Length)
}

Assert-Contract ($manifestDsrc.Count -eq 1 -and
    [string]$manifestDsrc[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $indexedDsrcCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $checkedOutDsrcCommit -ceq [string]$contract.buildEvidence.directSourceCommit) `
    "p14.gcw-rating.direct-source-commit-synchronized"
Assert-Contract ($manifestSrc.Count -eq 1 -and
    [string]$manifestSrc[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit -and
    $indexedSrcCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit -and
    $checkedOutSrcCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "p14.gcw-rating.native-source-commit-synchronized"

foreach ($component in @("dsrc", "src"))
{
    $evidence = $contract.buildEvidence.overlayPatches.$component
    $patchPath = Join-Path $repositoryRoot ([string]$evidence.path)
    Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.gcw-rating.overlay.$component.exists"
    if (Test-Path -LiteralPath $patchPath -PathType Leaf)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and $hash -ceq [string]$evidence.sha256) `
            "p14.gcw-rating.overlay.$component.authenticated"
    }
}

$paths = [ordered]@{
    "script.library.gcw" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/gcw.java"
    "script.library.faction_perk" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/faction_perk.java"
    "script.systems.gcw.gcw_parent_object" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/gcw_parent_object.java"
    "script.faction_perk.hq.loader" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/loader.java"
    "script.faction_perk.hq.planetary_base_register" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/planetary_base_register.java"
    "script.library.guild" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/guild.java"
    "script.player.player_guild" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/player/player_guild.java"
    "script.player.player_utility" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/player/player_utility.java"
    "script.systems.city.city_hall" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/city/city_hall.java"
    "script.terminal.terminal_city" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/terminal/terminal_city.java"
    "script.terminal.terminal_gcw_publish_gift" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/terminal/terminal_gcw_publish_gift.java"
    "script.terminal.terminal_guild" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/terminal/terminal_guild.java"
    "script.library.travel" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/travel.java"
    "script.systems.spawning.spawn_base" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/spawning/spawn_base.java"
    "script.city.ship_spawner" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/city/ship_spawner.java"
    "script.item.publish_gift.gcw_mulit_image_painting" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/item/publish_gift/gcw_mulit_image_painting.java"
    "script.library.holiday" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/holiday.java"
    "script.systems.collections.collection_gcw" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/collections/collection_gcw.java"
    "datatable.item.master_item.master_item" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/master_item.tab"
    "datatable.item.master_item.item_stats" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/item_stats.tab"
    "datatable.faction_perk.hq.hq_point_values" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/faction_perk/hq/hq_point_values.tab"
    "datatable.faction_recruiter.imperial.installation" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/npc/faction_recruiter/perk_inventory/imperial/installation.tab"
    "datatable.faction_recruiter.rebel.installation" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/npc/faction_recruiter/perk_inventory/rebel/installation.tab"
    "PlayerObject.cpp" = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/PlayerObject.cpp"
    "PlayerObject.h" = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/PlayerObject.h"
    "ConsoleCommandParserServer.cpp" = Join-Path $source "src/engine/server/library/serverGame/src/shared/console/ConsoleCommandParserServer.cpp"
    "PlanetObject.cpp" = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/PlanetObject.cpp"
    "Pvp.cpp" = Join-Path $source "src/engine/server/library/serverGame/src/shared/pvp/Pvp.cpp"
    "ScriptMethodsCity.cpp" = Join-Path $source "src/engine/server/library/serverScript/src/shared/ScriptMethodsCity.cpp"
    "ScriptMethodsGuild.cpp" = Join-Path $source "src/engine/server/library/serverScript/src/shared/ScriptMethodsGuild.cpp"
    "ScriptMethodsPvp.cpp" = Join-Path $source "src/engine/server/library/serverScript/src/shared/ScriptMethodsPvp.cpp"
    "script.systems.missions.base.mission_base" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
    "script.library.groundquests" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/groundquests.java"
    "script.library.battlefield" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/battlefield.java"
    "script.systems.battlefield.player_battlefield" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/player_battlefield.java"
    "script.systems.battlefield.game_destroy" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/game_destroy.java"
    "script.systems.battlefield.game_assault" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/game_assault.java"
    "script.systems.battlefield.battlefield_utility" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/battlefield_utility.java"
    "script.library.space_combat" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/space_combat.java"
    "script.systems.gcw.space.battle_spawner" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/space/battle_spawner.java"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.gcw-rating.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) "p14.gcw-rating.source.$name.authenticated"
    }
}

$gcw = [string]$texts["script.library.gcw"]
$factionPerk = [string]$texts["script.library.faction_perk"]
$gcwParent = [string]$texts["script.systems.gcw.gcw_parent_object"]
$hqLoader = [string]$texts["script.faction_perk.hq.loader"]
$baseRegister = [string]$texts["script.faction_perk.hq.planetary_base_register"]
$guildLibrary = [string]$texts["script.library.guild"]
$playerGuild = [string]$texts["script.player.player_guild"]
$playerUtility = [string]$texts["script.player.player_utility"]
$cityHall = [string]$texts["script.systems.city.city_hall"]
$terminalCity = [string]$texts["script.terminal.terminal_city"]
$terminalGcw = [string]$texts["script.terminal.terminal_gcw_publish_gift"]
$terminalGuild = [string]$texts["script.terminal.terminal_guild"]
$travel = [string]$texts["script.library.travel"]
$ambientSpawn = [string]$texts["script.systems.spawning.spawn_base"]
$cityShipSpawner = [string]$texts["script.city.ship_spawner"]
$gcwPainting = [string]$texts["script.item.publish_gift.gcw_mulit_image_painting"]
$holiday = [string]$texts["script.library.holiday"]
$collectionGcw = [string]$texts["script.systems.collections.collection_gcw"]
$masterItems = [string]$texts["datatable.item.master_item.master_item"]
$itemStats = [string]$texts["datatable.item.master_item.item_stats"]
$hqPointValues = [string]$texts["datatable.faction_perk.hq.hq_point_values"]
$imperialInstallations = [string]$texts["datatable.faction_recruiter.imperial.installation"]
$rebelInstallations = [string]$texts["datatable.faction_recruiter.rebel.installation"]
$player = [string]$texts["PlayerObject.cpp"]
$playerHeader = [string]$texts["PlayerObject.h"]
$serverConsole = [string]$texts["ConsoleCommandParserServer.cpp"]
$planet = [string]$texts["PlanetObject.cpp"]
$nativePvp = [string]$texts["Pvp.cpp"]
$scriptCity = [string]$texts["ScriptMethodsCity.cpp"]
$scriptGuild = [string]$texts["ScriptMethodsGuild.cpp"]
$scriptPvp = [string]$texts["ScriptMethodsPvp.cpp"]
$mission = [string]$texts["script.systems.missions.base.mission_base"]
$groundquests = [string]$texts["script.library.groundquests"]
$battlefieldLibrary = [string]$texts["script.library.battlefield"]
$battlefield = [string]$texts["script.systems.battlefield.player_battlefield"]
$battlefieldDestroy = [string]$texts["script.systems.battlefield.game_destroy"]
$battlefieldAssault = [string]$texts["script.systems.battlefield.game_assault"]
$battlefieldUtility = [string]$texts["script.systems.battlefield.battlefield_utility"]
$spaceCombat = [string]$texts["script.library.space_combat"]
$spaceBattle = [string]$texts["script.systems.gcw.space.battle_spawner"]

$grant = Get-FunctionSlice $gcw `
    "public static void _grantGcwPoints" `
    "public static void doGcwPointCsLogging"
Assert-Contract ($grant.Contains("Publish 14 faction standing and faction rank are authoritative") -and
    $grant.Contains("return;") -and
    -not $grant.Contains("pvpModifyCurrentGcwPoints") -and
    -not $grant.Contains("gcwPointBonus") -and
    -not $grant.Contains("sendSystemMessageProse") -and
    -not $grant.Contains("gcwInvasionCreditForGCW") -and
    -not $grant.Contains("grantGcwPointsToRegion")) `
    "p14.gcw-rating.central-script-pipeline-retired"
Assert-Contract ($gcw.Contains('_grantGcwPoints(null, attacker, pointValue, false, -1, "")') -and
    $gcw.Contains("_grantGcwPoints(victim, attacker, pointValue, pvpKill, point_type, information)")) `
    "p14.gcw-rating.all-shared-grants-use-retired-choke-point"

$holidayReward = Get-FunctionSlice $holiday `
    "public static boolean rewardEmpireDayPlayer" `
    "public static boolean setEventLockOutTimeStamp"
Assert-Contract ($holidayReward.Contains("getEventTokens(") -and
    $holidayReward.Contains("buff.applyBuff") -and
    $holidayReward.Contains("play2dNonLoopingSound") -and
    -not $holidayReward.Contains("pvpModifyCurrentGcwPoints") -and
    -not $holidayReward.Contains("SID_GCW_POINTS") -and
    -not [bool]$contract.expected.holidayGcwPointMessageReachable -and
    [bool]$contract.expected.holidayTokenRewardsPreserved) `
    "p14.gcw-rating.holiday-token-reward-retained-without-nge-points"

$collectionMenuRequest = Get-FunctionSlice $collectionGcw `
    "public int OnObjectMenuRequest" `
    "public int OnObjectMenuSelect"
$collectionMenuSelect = Get-FunctionSlice $collectionGcw `
    "public int OnObjectMenuSelect" `
    "public int handlerSuiGrantGcwPoints"
$collectionHandler = Get-FunctionSlice $collectionGcw `
    "public int handlerSuiGrantGcwPoints" `
    "public int __no_later_method__"
Assert-Contract ($collectionMenuRequest.Contains("return SCRIPT_CONTINUE;") -and
    -not $collectionMenuRequest.Contains("mi.addRootMenu") -and
    $collectionMenuSelect.Contains("return SCRIPT_CONTINUE;") -and
    -not $collectionMenuSelect.Contains("sui.msgbox") -and
    $collectionHandler.Contains("sui.removePid(player, PID_NAME)") -and
    -not ($collectionMenuRequest + $collectionMenuSelect + $collectionHandler).Contains("pvpModifyCurrentGcwPoints") -and
    -not $collectionHandler.Contains("decrementCount") -and
    -not $collectionHandler.Contains("destroyObject") -and
    -not $collectionHandler.Contains("sendSystemMessage(player, USED_ITEM)") -and
    -not [bool]$contract.expected.gcwCollectionConsumeReachable) `
    "p14.gcw-rating.gcw-point-collection-consume-retired-nondestructively"

$gcwItemPattern = '(?m)^(?:col_reward_(?:rebel|imperial)_gcw_|item_event_lifeday_gcw_|item_gcw_points_(?:rebel|imperial)_gcw_)'
$masterItemRows = [regex]::Matches($masterItems, $gcwItemPattern).Count
$masterItemScriptRows = [regex]::Matches($masterItems, $gcwItemPattern + '[^\r\n]*systems\.collections\.collection_gcw').Count
$itemStatRows = [regex]::Matches($itemStats, $gcwItemPattern + '[^\r\n]*collection\.gcw_point_value=').Count
Assert-Contract ($masterItemRows -eq [int]$contract.expected.gcwCollectionItemsPreserved -and
    $masterItemScriptRows -eq [int]$contract.expected.gcwCollectionItemsPreserved -and
    $itemStatRows -eq [int]$contract.expected.gcwCollectionItemsPreserved) `
    "p14.gcw-rating.gcw-point-collection-items-preserved"

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$productionWriterCalls = 0
Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java" | Where-Object {
    $_.Name -cne "base_class.java" -and -not $_.FullName.EndsWith("\hnguyen\cwdm_test.java", [System.StringComparison]::OrdinalIgnoreCase)
} | ForEach-Object {
    foreach ($line in [System.IO.File]::ReadLines($_.FullName))
    {
        if ($line.Contains("pvpModifyCurrentGcwPoints(")) { ++$productionWriterCalls }
    }
}
Assert-Contract ($productionWriterCalls -eq [int]$contract.expected.directProductionGcwPointWriterCalls) `
    "p14.gcw-rating.direct-production-gcw-point-writers-retired"

$factionalPresence = Get-FunctionSlice $player `
    "void PlayerObjectNamespace::grantGcwFactionalPresenceScore" `
    "// ======================================================================"
$retiredPresenceInputs = @("UNREF(gcwCategory);", "UNREF(po);", "UNREF(co);")
$retiredPresenceWriters = @(
    "co.getLevel()", "po.getCurrentGcwRank()", "getGcwFactionalPresenceGcwRankBonusPct",
    "getGcwFactionalPresenceLevelPct", "getGcwFactionalPresenceMountedPct",
    "getGcwFactionalPresenceAlignedCityBonusPct", "getGcwFactionalPresenceAlignedCityRankBonusPct",
    "getGcwFactionalPresenceAlignedCityAgeBonusPct", "adjustGcwImperialScore", "adjustGcwRebelScore"
)
Assert-Contract ((@($retiredPresenceInputs | Where-Object { -not $factionalPresence.Contains($_) }).Count -eq 0) -and
    (@($retiredPresenceWriters | Where-Object { $factionalPresence.Contains($_) }).Count -eq 0)) `
    "p14.gcw-rating.passive-factional-presence-writer-retired"
Assert-Contract ($player.Contains("void grantGcwFactionalPresenceScore(std::string const & gcwCategory, PlayerObject const & po, CreatureObject const & co);") -and
    $player.Contains("if (!lfgCharacterData.locationFactionalPresenceGcwRegion.empty())") -and
    $player.Contains("grantGcwFactionalPresenceScore(lfgCharacterData.locationFactionalPresenceGcwRegion, *this, *owner);")) `
    "p14.gcw-rating.regional-presentation-compatibility-retained"

$defenderRegionList = Get-FunctionSlice $scriptPvp `
    "jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegions(" `
    "jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsCitiesImperial("
Assert-Contract ($defenderRegionList.Contains("return 0;") -and
    -not $defenderRegionList.Contains("Pvp::getAllGcwScoreCategory")) `
    "p14.gcw-rating.regional-defender-membership-list-retired"

$defenderQueryFunctions = [ordered]@{
    citiesImperial = @("jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsCitiesImperial", "jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsCitiesRebel")
    citiesRebel = @("jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsCitiesRebel", "jint JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsCitiesVersion")
    guildsImperial = @("jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsGuildsImperial", "jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsGuildsRebel")
    guildsRebel = @("jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsGuildsRebel", "jint JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionsGuildsVersion")
    cityDetailsImperial = @("jintArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionCitiesImperial", "jintArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionCitiesRebel")
    cityDetailsRebel = @("jintArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionCitiesRebel", "jintArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionGuildsImperial")
    guildDetailsImperial = @("jintArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionGuildsImperial", "jintArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionGuildsRebel")
    guildDetailsRebel = @("jintArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionGuildsRebel", "jfloat JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionImperialBonus")
}
foreach ($name in $defenderQueryFunctions.Keys)
{
    $markers = $defenderQueryFunctions[$name]
    $slice = Get-FunctionSlice $scriptPvp $markers[0] $markers[1]
    Assert-Contract ($slice.Contains("return 0;") -and
        -not $slice.Contains("getGcwRegionDefenderCities") -and
        -not $slice.Contains("getGcwRegionDefenderGuilds") -and
        -not $slice.Contains("Pvp::getAllGcwScoreCategory")) `
        "p14.gcw-rating.regional-defender-query.$name.retired"
}

$scriptImperialBonus = Get-FunctionSlice $scriptPvp `
    "jfloat JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionImperialBonus" `
    "jfloat JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionRebelBonus"
$scriptRebelBonus = Get-FunctionSlice $scriptPvp `
    "jfloat JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegionRebelBonus" `
    "// ======================================================================"
$pvpImperialBonus = Get-FunctionSlice $nativePvp `
    "float Pvp::getGcwDefenderRegionImperialBonus" `
    "float Pvp::getGcwDefenderRegionRebelBonus"
$pvpRebelBonus = Get-FunctionSlice $nativePvp `
    "float Pvp::getGcwDefenderRegionRebelBonus" `
    "bool Pvp::getGcwDefenderRegionBonus"
$pvpDefenderBonus = Get-FunctionSlice $nativePvp `
    "bool Pvp::getGcwDefenderRegionBonus" `
    "void PvpNamespace::loadGcwRankTable"
Assert-Contract ($scriptImperialBonus.Contains("return 0.0f;") -and
    $scriptRebelBonus.Contains("return 0.0f;") -and
    -not $scriptImperialBonus.Contains("Pvp::getGcwDefenderRegionImperialBonus") -and
    -not $scriptRebelBonus.Contains("Pvp::getGcwDefenderRegionRebelBonus") -and
    $pvpImperialBonus.Contains("return 0.0f;") -and
    $pvpRebelBonus.Contains("return 0.0f;") -and
    $pvpDefenderBonus.Contains("bonus = 0.0f;") -and
    $pvpDefenderBonus.Contains("return false;")) `
    "p14.gcw-rating.regional-defender-bonus-retired"

$cityGetRegion = Get-FunctionSlice $scriptCity `
    "jstring JNICALL ScriptMethodsCityNamespace::cityGetGcwDefenderRegion" `
    "jint JNICALL ScriptMethodsCityNamespace::cityGetTimeJoinedGcwDefenderRegion"
$citySetRegion = Get-FunctionSlice $scriptCity `
    "void JNICALL ScriptMethodsCityNamespace::citySetGcwDefenderRegion" `
    "void JNICALL ScriptMethodsCityNamespace::citySetLeader"
$guildGetRegion = Get-FunctionSlice $scriptGuild `
    "jstring JNICALL ScriptMethodsGuildNamespace::guildGetCurrentGcwDefenderRegion" `
    "jint JNICALL ScriptMethodsGuildNamespace::guildGetTimeJoinedCurrentGcwDefenderRegion"
$guildPreviousRegion = Get-FunctionSlice $scriptGuild `
    "jstring JNICALL ScriptMethodsGuildNamespace::guildGetPreviousGcwDefenderRegion" `
    "jint JNICALL ScriptMethodsGuildNamespace::guildGetTimeLeftPreviousGcwDefenderRegion"
$guildSetRegion = Get-FunctionSlice $scriptGuild `
    "void JNICALL ScriptMethodsGuildNamespace::guildSetGcwDefenderRegion" `
    "void JNICALL ScriptMethodsGuildNamespace::guildAddCreatorMember"
Assert-Contract ($cityGetRegion.Contains('JavaString emptyRegion("")') -and
    -not $cityGetRegion.Contains("CityInterface::getCityInfo") -and
    $citySetRegion.Contains("CityInterface::setCityGcwDefenderRegion(cityId, std::string(), 0, false)") -and
    -not $citySetRegion.Contains("Pvp::getGcwScoreCategory") -and
    $guildGetRegion.Contains('JavaString emptyRegion("")') -and
    $guildPreviousRegion.Contains('JavaString emptyRegion("")') -and
    $guildSetRegion.Contains("GuildInterface::setGuildGcwDefenderRegion(guildId, std::string())") -and
    -not $guildSetRegion.Contains("Pvp::getGcwScoreCategory")) `
    "p14.gcw-rating.regional-defender-membership-mutation-retired"

$playerDefenderUpdate = Get-FunctionSlice $player `
    "void PlayerObject::updateGcwDefenderRegionInfo()" `
    "void PlayerObject::squelch("
$playerSetTitle = Get-FunctionSlice $player `
    "void PlayerObject::setTitle(" `
    "std::string const &PlayerObject::getTitle()"
$retiredDefenderTitles = @("city_gcw_region_defender", "guild_gcw_region_defender", "imperial_gcw_war_planner", "rebel_gcw_war_planner")
Assert-Contract ($playerDefenderUpdate.Contains("m_cityGcwDefenderRegion.set(std::make_pair(std::string(), std::make_pair(false, false)))") -and
    $playerDefenderUpdate.Contains("m_guildGcwDefenderRegion.set(std::make_pair(std::string(), std::make_pair(false, false)))") -and
    $playerDefenderUpdate.Contains('modifyCollectionSlotValue("imperial_gcw_war_planner", -1ll)') -and
    $playerDefenderUpdate.Contains('modifyCollectionSlotValue("rebel_gcw_war_planner", -1ll)') -and
    (@($retiredDefenderTitles | Where-Object { -not $playerSetTitle.Contains($_) -or -not $playerDefenderUpdate.Contains($_) }).Count -eq 0) -and
    -not $playerDefenderUpdate.Contains("CityInterface::getCityInfo") -and
    -not $playerDefenderUpdate.Contains("GuildInterface::getGuildInfo") -and
    -not $playerDefenderUpdate.Contains("getGcwImperialScorePercentile")) `
    "p14.gcw-rating.regional-defender-player-state-and-titles-scrubbed"

$cityMenuRequest = Get-FunctionSlice $terminalCity "public int OnObjectMenuRequest" "public int OnObjectMenuSelect"
$cityMenuSelect = Get-FunctionSlice $terminalCity "public int OnObjectMenuSelect" "public void forceUpdate"
$cityInfo = Get-FunctionSlice $terminalCity "public void showCityInfo" "public void showCitizensList"
$guildMenuRequest = Get-FunctionSlice $terminalGuild "public int OnObjectMenuRequest" "public int OnObjectMenuSelect"
$guildMenuSelect = Get-FunctionSlice $terminalGuild "public int OnObjectMenuSelect" "public obj_id getMenuContextObjId"
$guildInfo = Get-FunctionSlice $guildLibrary "public static void showGuildInfo" "public static void showGuildEnemies"
$warMenuRequest = Get-FunctionSlice $terminalGcw "public int OnObjectMenuRequest" "public int OnObjectMenuSelect"
$warDefenderSelection = Get-FunctionSlice $terminalGcw `
    "else if (item == menu_info_types.SERVER_MENU4)" `
    "return SCRIPT_CONTINUE;"
Assert-Contract (-not $cityMenuRequest.Contains("SERVER_MENU17, SID_BEGIN_GCW_REGION_DEFENDER") -and
    -not $cityMenuRequest.Contains("SERVER_MENU18, SID_END_GCW_REGION_DEFENDER") -and
    $cityMenuSelect.Contains("item == menu_info_types.SERVER_MENU17 || item == menu_info_types.SERVER_MENU18") -and
    $cityMenuSelect.Contains('citySetGcwDefenderRegion(city_id, "", 0, false)') -and
    -not $cityMenuSelect.Contains("Select a GCW region") -and
    -not $cityInfo.Contains("GCW Region Defender") -and
    -not $guildMenuRequest.Contains("SERVER_MENU22, SID_END_GCW_REGION_DEFENDER") -and
    -not $guildMenuRequest.Contains("SERVER_MENU23, SID_BEGIN_GCW_REGION_DEFENDER") -and
    $guildMenuSelect.Contains("item == menu_info_types.SERVER_MENU22 || item == menu_info_types.SERVER_MENU23") -and
    $guildMenuSelect.Contains('guildSetGcwDefenderRegion(guildId, "")') -and
    -not $guildMenuSelect.Contains("Select a GCW region") -and
    -not $guildInfo.Contains("GCW Region Defender") -and
    -not $warMenuRequest.Contains("menu_info_types.SERVER_MENU4") -and
    $warDefenderSelection.Contains("gcw.gcwRegionDefenderTablePid") -and
    $warDefenderSelection.Contains("gcw.gcwRegionDefenderDetailsTablePid") -and
    -not $warDefenderSelection.Contains("getGcwDefenderRegions") -and
    -not $warDefenderSelection.Contains("sui.tableColumnMajor")) `
    "p14.gcw-rating.regional-defender-terminal-presentation-retired"

Assert-Contract (-not $playerUtility.Contains("GCW Region Defender Rebel Bonus") -and
    -not $playerUtility.Contains("selectedGcwDefenderRegion") -and
    -not $playerUtility.Contains("getGcwDefenderRegions()") -and
    $playerUtility.Contains('citySetGcwDefenderRegion(cityId, "", 0, false)') -and
    -not $playerGuild.Contains("selectedGcwDefenderRegion") -and
    -not $playerGuild.Contains("getGcwDefenderRegions()") -and
    $playerGuild.Contains('guildSetGcwDefenderRegion(guildId, "")') -and
    -not $cityHall.Contains('messageTo(self, "retryDepersistCityGcwRegionDefender"') -and
    -not $cityHall.Contains("cityGcwRegionDefender.region") -and
    $cityHall.Contains('citySetGcwDefenderRegion(city_id, "", 0, false)')) `
    "p14.gcw-rating.regional-defender-stale-callbacks-cleanup-only"

Assert-Contract ($terminalGcw.Contains("getGcwGroupImperialScorePercentile(strSubCategory)") -and
    $gcw.Contains("getGcwImperialScorePercentile(category)") -and
    [bool]$contract.expected.regionalScoreAndContentCompatibilityPreserved -and
    -not [bool]$contract.expected.postNgeRegionalDefenderMembershipReachable -and
    -not [bool]$contract.expected.postNgeRegionalDefenderBonusReachable -and
    -not [bool]$contract.expected.postNgeRegionalDefenderTitlesReachable -and
    -not [bool]$contract.expected.postNgeRegionalDefenderPresentationReachable -and
    [bool]$contract.expected.staleRegionalDefenderPlayerStateScrubbed) `
    "p14.gcw-rating.regional-content-preserved-with-defender-system-retired"

$periodicOverwrite = Get-FunctionSlice $gcwParent `
    "public int updateGCWData" `
    "public int updateGCWScore"
$deltaUpdate = Get-FunctionSlice $gcwParent `
    "public int updateGCWScore" `
    "public int synchronizeGCWScore"
$absoluteUpdate = Get-FunctionSlice $gcwParent `
    "public int synchronizeGCWScore" `
    "private void ensurePrecuControlScoreState"
Assert-Contract ($periodicOverwrite.Contains("ensurePrecuControlScoreState(self);") -and
    -not $periodicOverwrite.Contains("getImperialPercentileByRegion") -and
    -not $periodicOverwrite.Contains("getRebelPercentileByRegion") -and
    -not $periodicOverwrite.Contains('messageTo(self, "updateGCWData"')) `
    "p14.gcw-rating.nge-percentile-planet-overwrite-retired"
Assert-Contract ($deltaUpdate.Contains('params.containsKey("intScoreChange")') -and
    $deltaUpdate.Contains('params.containsKey("strFaction")') -and
    $deltaUpdate.Contains('"Imperial".equals(faction)') -and
    $deltaUpdate.Contains('"Rebel".equals(faction)') -and
    $deltaUpdate.Contains('Math.max(0L, adjustedScore)') -and
    $deltaUpdate.Contains('setObjVar(self, scoreObjVar, newScore)')) `
    "p14.gcw-rating.precu-base-delta-handler-restored"
Assert-Contract ($absoluteUpdate.Contains('params.containsKey("imperialScore")') -and
    $absoluteUpdate.Contains('params.containsKey("rebelScore")') -and
    $absoluteUpdate.Contains('setObjVar(self, "Imperial.controlScore", Math.max(0, params.getInt("imperialScore")))') -and
    $absoluteUpdate.Contains('setObjVar(self, "Rebel.controlScore", Math.max(0, params.getInt("rebelScore")))')) `
    "p14.gcw-rating.precu-base-absolute-synchronizer-restored"

$changePlanetScore = Get-FunctionSlice $gcw `
    "public static void changeGCWScore" `
    "public static void synchronizePlanetaryBaseControlScore"
$synchronizePlanetScore = Get-FunctionSlice $gcw `
    "public static void synchronizePlanetaryBaseControlScore" `
    "public static void incrementGCWScore"
$killAccumulator = Get-FunctionSlice $gcw `
    "public static void checkAndUpdateGCWStanding" `
    "public static obj_id getPub30StaticBaseControllerId"
Assert-Contract ($changePlanetScore.Contains('intValue == 0') -and
    $changePlanetScore.Contains('!"Imperial".equals(strFaction)') -and
    $changePlanetScore.Contains('!"Rebel".equals(strFaction)') -and
    $changePlanetScore.Contains('isIdValid(objParent)') -and
    $changePlanetScore.Contains('messageTo(objParent, "updateGCWScore"')) `
    "p14.gcw-rating.base-delta-message-validated"
Assert-Contract ($synchronizePlanetScore.Contains('Math.max(0, imperialScore)') -and
    $synchronizePlanetScore.Contains('Math.max(0, rebelScore)') -and
    $synchronizePlanetScore.Contains('messageTo(objParent, "synchronizeGCWScore"')) `
    "p14.gcw-rating.base-absolute-message-validated"
Assert-Contract ($killAccumulator.Contains('removeObjVar(self, "gcw.intKillScore")') -and
    -not $killAccumulator.Contains("changeGCWScore") -and
    -not $killAccumulator.Contains("earned_gcw_points")) `
    "p14.gcw-rating.non-base-kill-planet-score-retired"

$basePointLookup = Get-FunctionSlice $factionPerk `
    "public static int grabFactionBasePointValue" `
    "public static boolean executeComlinkReinforcements"
Assert-Contract ($basePointLookup.Contains("int default_point_value = 0;") -and
    $basePointLookup.Contains("if (point_value < 0)")) `
    "p14.gcw-rating.unknown-later-base-has-no-control-authority"
Assert-Contract ($hqLoader.Contains('dungeon_info.put("pointValue", Math.max(0, faction_perk.grabFactionBasePointValue(self)))')) `
    "p14.gcw-rating.base-registry-records-authored-point-value"
Assert-Contract ($baseRegister.Contains("PRECU_BASE_RECONCILIATION_PULSE = 3600.0f") -and
    $baseRegister.Contains('dataItem.containsKey("pointValue")') -and
    $baseRegister.Contains("rebelScore += pointValue") -and
    $baseRegister.Contains("imperialScore += pointValue") -and
    $baseRegister.Contains("setBaseCount(self, rebel, imperial)") -and
    $baseRegister.Contains("gcw.synchronizePlanetaryBaseControlScore(getLocation(self), imperialScore, rebelScore)") -and
    $baseRegister.Contains("releaseClusterWideDataLock(manage_name, lock_key)")) `
    "p14.gcw-rating.base-registry-periodic-absolute-reconciliation"

$expectedBaseValues = [ordered]@{
    "object/building/faction_perk/hq/hq_s01_imp.iff" = 1
    "object/building/faction_perk/hq/hq_s01_imp_pvp.iff" = 2
    "object/building/faction_perk/hq/hq_s02_imp.iff" = 3
    "object/building/faction_perk/hq/hq_s02_imp_pvp.iff" = 6
    "object/building/faction_perk/hq/hq_s03_imp.iff" = 4
    "object/building/faction_perk/hq/hq_s03_imp_pvp.iff" = 8
    "object/building/faction_perk/hq/hq_s04_imp.iff" = 10
    "object/building/faction_perk/hq/hq_s04_imp_pvp.iff" = 20
    "object/building/faction_perk/hq/hq_s01_rebel.iff" = 1
    "object/building/faction_perk/hq/hq_s01_rebel_pvp.iff" = 2
    "object/building/faction_perk/hq/hq_s02_rebel.iff" = 3
    "object/building/faction_perk/hq/hq_s02_rebel_pvp.iff" = 6
    "object/building/faction_perk/hq/hq_s03_rebel.iff" = 4
    "object/building/faction_perk/hq/hq_s03_rebel_pvp.iff" = 8
    "object/building/faction_perk/hq/hq_s04_rebel.iff" = 10
    "object/building/faction_perk/hq/hq_s04_rebel_pvp.iff" = 20
}
$baseValueRows = [ordered]@{}
foreach ($line in ($hqPointValues -split "`r?`n" | Select-Object -Skip 2 | Where-Object { $_.Length -gt 0 }))
{
    $columns = $line -split "`t"
    if ($columns.Count -eq 2)
    {
        $baseValueRows[$columns[0]] = [int]$columns[1]
    }
}
$baseValuesMatch = $baseValueRows.Count -eq $expectedBaseValues.Count
foreach ($template in $expectedBaseValues.Keys)
{
    $baseValuesMatch = $baseValuesMatch -and $baseValueRows.Contains($template) -and
        $baseValueRows[$template] -eq $expectedBaseValues[$template]
}
Assert-Contract ($baseValuesMatch -and -not $hqPointValues.Contains("hq_s05")) `
    "p14.gcw-rating.exact-precu-player-base-point-values"
$requiredRecruiterBaseTiers = @("hq_s01", "hq_s02", "hq_s03", "hq_s04")
Assert-Contract ((@($requiredRecruiterBaseTiers | Where-Object {
        -not $imperialInstallations.Contains($_) -or -not $rebelInstallations.Contains($_)
    }).Count -eq 0) -and
    -not $imperialInstallations.Contains("hq_s05") -and -not $rebelInstallations.Contains("hq_s05")) `
    "p14.gcw-rating.precu-recruiter-excludes-later-s05-base"

$retire = Get-FunctionSlice $player `
    "void PlayerObject::retirePostNgeGcwRatingState()" `
    "void PlayerObject::clearSessionActivity()"
$requiredResets = @(
    'cancelMessageTo("C++RecalculateGcwRating")',
    "m_currentGcwPoints = 0", "m_currentGcwRating = -1", "m_currentPvpKills = 0",
    "m_lifetimeGcwPoints = 0", "m_maxGcwImperialRating = -1", "m_maxGcwRebelRating = -1",
    "m_lifetimePvpKills = 0", "m_nextGcwRatingCalcTime = 0", "m_currentGcwRank = 0",
    "m_currentGcwRankProgress = 0.0f", "m_maxGcwImperialRank = 0", "m_maxGcwRebelRank = 0",
    "m_gcwRatingActualCalcTime = 0"
)
Assert-Contract ($playerHeader.Contains("void  retirePostNgeGcwRatingState();") -and
    (@($requiredResets | Where-Object { -not $retire.Contains($_) }).Count -eq 0)) `
    "p14.gcw-rating.authoritative-persisted-state-scrub"

$endBaselines = Get-FunctionSlice $player "void PlayerObject::endBaselines()" "void PlayerObject::onLoadedFromDatabase()"
Assert-Contract ($endBaselines.Contains("retirePostNgeGcwRatingState();") -and
    -not $endBaselines.Contains("Pvp::getRankInfo(m_currentGcwRating.get())")) `
    "p14.gcw-rating.player-load-scrubs-before-later-rank-derivation"

$mutationFunctions = [ordered]@{
    modifyCurrentGcwPoints = @("void PlayerObject::modifyCurrentGcwPoints", "void PlayerObject::modifyCurrentGcwRating")
    modifyCurrentGcwRating = @("void PlayerObject::modifyCurrentGcwRating", "void PlayerObject::modifyCurrentPvpKills")
    modifyCurrentPvpKills = @("void PlayerObject::modifyCurrentPvpKills", "void PlayerObject::modifyLifetimeGcwPoints")
    modifyLifetimeGcwPoints = @("void PlayerObject::modifyLifetimeGcwPoints", "void PlayerObject::modifyMaxGcwImperialRating")
    modifyMaxGcwImperialRating = @("void PlayerObject::modifyMaxGcwImperialRating", "void PlayerObject::modifyMaxGcwRebelRating")
    modifyMaxGcwRebelRating = @("void PlayerObject::modifyMaxGcwRebelRating", "void PlayerObject::modifyLifetimePvpKills")
    modifyLifetimePvpKills = @("void PlayerObject::modifyLifetimePvpKills", "void PlayerObject::modifyNextGcwRatingCalcTime")
    modifyNextGcwRatingCalcTime = @("void PlayerObject::modifyNextGcwRatingCalcTime", "void PlayerObject::ctsUseOnlySetGcwInfo")
    ctsUseOnlySetGcwInfo = @("void PlayerObject::ctsUseOnlySetGcwInfo", "void PlayerObject::setNextGcwRatingCalcTime")
    setNextGcwRatingCalcTime = @("void PlayerObject::setNextGcwRatingCalcTime", "void PlayerObject::handleRecalculateGcwRating")
    handleRecalculateGcwRating = @("void PlayerObject::handleRecalculateGcwRating", "void PlayerObject::sendRecalculateGcwRatingMessageTo")
}
foreach ($name in $mutationFunctions.Keys)
{
    $markers = $mutationFunctions[$name]
    $slice = Get-FunctionSlice $player $markers[0] $markers[1]
    $activePrefix = Get-BeforeFirstReturn $slice
    Assert-Contract ($activePrefix.Contains("retirePostNgeGcwRatingState();")) `
        "p14.gcw-rating.native-entrypoint.$name.retired"
}

$sendRecalc = Get-FunctionSlice $player `
    "void PlayerObject::sendRecalculateGcwRatingMessageTo" `
    "bool PlayerObject::needsGcwRatingRecalculated"
$needsRecalc = Get-FunctionSlice $player `
    "bool PlayerObject::needsGcwRatingRecalculated" `
    "void PlayerObject::retirePostNgeGcwRatingState"
Assert-Contract ($sendRecalc.Contains("retirePostNgeGcwRatingState();") -and
    -not $sendRecalc.Contains("MessageToQueue::getInstance().sendMessageToC") -and
    $needsRecalc.Contains("return false;") -and
    -not $needsRecalc.Contains("Pvp::calculateRatingAdjustment")) `
    "p14.gcw-rating.weekly-scheduler-and-decay-inert"

$nativeBridge = Get-FunctionSlice $scriptPvp `
    "void JNICALL ScriptMethodsPvpNamespace::pvpModifyCurrentGcwPoints" `
    "void JNICALL ScriptMethodsPvpNamespace::pvpModifyCurrentPvpKills"
Assert-Contract ($nativeBridge.Contains("player->modifyCurrentGcwPoints(adjustment, true)") -and
    -not $nativeBridge.Contains("getGcwDefenderRegionBonus") -and
    (Get-BeforeFirstReturn (Get-FunctionSlice $player "void PlayerObject::modifyCurrentGcwPoints" "void PlayerObject::modifyCurrentGcwRating")).Contains("retirePostNgeGcwRatingState();")) `
    "p14.gcw-rating.native-compatibility-bridge-inert"

$scriptImperialScoreWriter = Get-FunctionSlice $scriptPvp `
    "void JNICALL ScriptMethodsPvpNamespace::adjustGcwImperialScore" `
    "void JNICALL ScriptMethodsPvpNamespace::adjustGcwRebelScore"
$scriptRebelScoreWriter = Get-FunctionSlice $scriptPvp `
    "void JNICALL ScriptMethodsPvpNamespace::adjustGcwRebelScore" `
    "jint JNICALL ScriptMethodsPvpNamespace::getGcwImperialScorePercentile"
$scriptImperialScoreWriterActive = Get-BeforeFirstReturn $scriptImperialScoreWriter
$scriptRebelScoreWriterActive = Get-BeforeFirstReturn $scriptRebelScoreWriter
Assert-Contract ($scriptImperialScoreWriterActive.Contains("UNREF(adjustment);") -and
    $scriptRebelScoreWriterActive.Contains("UNREF(adjustment);") -and
    -not $scriptImperialScoreWriterActive.Contains("ServerUniverse::getInstance().adjustGcwImperialScore") -and
    -not $scriptRebelScoreWriterActive.Contains("ServerUniverse::getInstance().adjustGcwRebelScore")) `
    "p14.gcw-rating.regional-score-script-writers-retired"

$consoleImperialScoreWriter = Get-FunctionSlice $serverConsole `
    'else if (isAbbrev(argv[0], "adjustGcwImperialScore"))' `
    'else if (isAbbrev(argv[0], "adjustGcwRebelScore"))'
$consoleRebelScoreWriter = Get-FunctionSlice $serverConsole `
    'else if (isAbbrev(argv[0], "adjustGcwRebelScore"))' `
    'else if (isAbbrev(argv[0], "decayGcwScore"))'
$consoleScoreDecay = Get-FunctionSlice $serverConsole `
    'else if (isAbbrev(argv[0], "decayGcwScore"))' `
    'else if (isAbbrev(argv[0], "showGcwFactionalPresence"))'
Assert-Contract ($consoleImperialScoreWriter.Contains("Publish 14 regional GCW score adjustment is retired") -and
    $consoleRebelScoreWriter.Contains("Publish 14 regional GCW score adjustment is retired") -and
    $consoleScoreDecay.Contains("Publish 14 regional GCW score decay is retired") -and
    -not $consoleImperialScoreWriter.Contains("ServerUniverse::getInstance().adjustGcwImperialScore") -and
    -not $consoleRebelScoreWriter.Contains("ServerUniverse::getInstance().adjustGcwRebelScore") -and
    -not $consoleScoreDecay.Contains('MessageToQueue::sendMessageToC')) `
    "p14.gcw-rating.regional-score-admin-writers-retired"

$planetImperialScoreWriter = Get-FunctionSlice $planet `
    "void PlanetObject::adjustGcwImperialScore" `
    "void PlanetObject::adjustGcwRebelScore"
$planetRebelScoreWriter = Get-FunctionSlice $planet `
    "void PlanetObject::adjustGcwRebelScore" `
    "int PlanetObject::getGcwImperialScorePercentile"
$planetImperialScoreWriterActive = Get-BeforeFirstReturn $planetImperialScoreWriter
$planetRebelScoreWriterActive = Get-BeforeFirstReturn $planetRebelScoreWriter
Assert-Contract ($planetImperialScoreWriterActive.Contains("UNREF(adjustment);") -and
    $planetRebelScoreWriterActive.Contains("UNREF(adjustment);") -and
    -not $planetImperialScoreWriterActive.Contains("m_gcwImperialScoreAdjustment.insert") -and
    -not $planetRebelScoreWriterActive.Contains("m_gcwRebelScoreAdjustment.insert")) `
    "p14.gcw-rating.regional-score-native-adjustment-queue-retired"

$trackingUpdate = Get-FunctionSlice $planet `
    "void PlanetObject::updateGcwTrackingData()" `
    "void PlanetObject::adjustGcwImperialScore"
$trackingGateStart = $trackingUpdate.IndexOf("Publish 14 has no regional-score adjustment pipeline", [System.StringComparison]::Ordinal)
$trackingLegacyStart = if ($trackingGateStart -ge 0) {
    $trackingUpdate.IndexOf("if (m_nextGcwTrackingUpdate == 0)", $trackingGateStart, [System.StringComparison]::Ordinal)
} else { -1 }
$trackingGate = if ($trackingGateStart -ge 0 -and $trackingLegacyStart -gt $trackingGateStart) {
    $trackingUpdate.Substring($trackingGateStart, $trackingLegacyStart - $trackingGateStart)
} else { "" }
Assert-Contract ($trackingGate.Contains("m_gcwImperialScoreAdjustment.clear();") -and
    $trackingGate.Contains("m_gcwRebelScoreAdjustment.clear();") -and
    $trackingGate.Contains("m_nextGcwTrackingUpdate = 0;") -and
    $trackingGate.Contains("return;") -and
    $trackingUpdate.Contains("GcwScoreStatRaw") -and
    $trackingUpdate.Contains("GcwScoreStatPct")) `
    "p14.gcw-rating.regional-score-cross-server-writer-retired-read-broadcast-preserved"

$scheduledDecay = Get-FunctionSlice $planet `
    'else if (message.getMethod() == "C++DoGcwDecay")' `
    'else if (message.getMethod() == "C++DoGcwDecayImmediate")'
$immediateDecay = Get-FunctionSlice $planet `
    'else if (message.getMethod() == "C++DoGcwDecayImmediate")' `
    "void PlanetObject::endBaselines()"
$scheduledDecayActive = Get-BeforeFirstReturn $scheduledDecay
$immediateDecayActive = Get-BeforeFirstReturn $immediateDecay
$endBaselines = Get-FunctionSlice $planet `
    "void PlanetObject::endBaselines()" `
    "void PlanetObject::setConnectedCharacterLfgData"
$endBaselinesActive = Get-BeforeFirstReturn $endBaselines
Assert-Contract ($scheduledDecayActive.Contains('removeObjVarItem("gcwScore.nextDecayTime")') -and
    $immediateDecayActive.Contains('removeObjVarItem("gcwScore.nextDecayTime")') -and
    $endBaselinesActive.Contains('removeObjVarItem("gcwScore.nextDecayTime")') -and
    -not $scheduledDecayActive.Contains("m_gcwImperialScore.set") -and
    -not $scheduledDecayActive.Contains("m_gcwRebelScore.set") -and
    -not $immediateDecayActive.Contains("m_gcwImperialScore.set") -and
    -not $immediateDecayActive.Contains("m_gcwRebelScore.set") -and
    -not $endBaselinesActive.Contains('MessageToQueue::sendMessageToC(getNetworkId(), "C++DoGcwDecay"') -and
    $endBaselinesActive.Contains("m_gcwImperialScore.set") -and
    $endBaselinesActive.Contains("m_gcwRebelScore.set")) `
    "p14.gcw-rating.regional-score-weekly-and-immediate-decay-retired-read-state-preserved"

Assert-Contract (-not [bool]$contract.expected.regionalScoreScriptMutationReachable -and
    -not [bool]$contract.expected.regionalScoreAdminMutationReachable -and
    -not [bool]$contract.expected.regionalScoreNativeQueueMutationReachable -and
    -not [bool]$contract.expected.regionalScoreCrossServerMutationReachable -and
    -not [bool]$contract.expected.regionalScoreWeeklyOrImmediateDecayReachable -and
    [bool]$contract.expected.regionalScoreReadCompatibilityPreserved -and
    $scriptPvp.Contains("ServerUniverse::getInstance().getGcwImperialScorePercentile") -and
    $scriptPvp.Contains("ServerUniverse::getInstance().getGcwGroupImperialScorePercentile")) `
    "p14.gcw-rating.regional-score-read-compatibility-only"

$travelPerk = Get-FunctionSlice $travel `
    "public static boolean qualifiesForGcwTravelPerks" `
    "public static boolean restrictedByGcwTravelRestrictions"
$travelRestriction = Get-FunctionSlice $travel `
    "public static boolean restrictedByGcwTravelRestrictions" `
    "public static int getGcwTravelRestrictionsSurcharge"
$travelSurcharge = Get-FunctionSlice $travel `
    "public static int getGcwTravelRestrictionsSurcharge" `
    "public static String getGcwTravelRestrictionsAvailableStarport"
$travelStarport = Get-FunctionSlice $travel `
    "public static String getGcwTravelRestrictionsAvailableStarport" `
    "public static obj_id getTravelShuttle"
Assert-Contract ($travelPerk.Contains("return false;") -and
    $travelRestriction.Contains("return false;") -and
    $travelSurcharge.Contains("return 0;") -and
    $travelStarport.Contains("return null;") -and
    -not ($travelPerk + $travelRestriction + $travelSurcharge + $travelStarport).Contains("ScorePercentile") -and
    -not ($travelPerk + $travelRestriction + $travelSurcharge + $travelStarport).Contains("pvpGetCurrentGcwRank") -and
    -not [bool]$contract.expected.regionalScoreTravelGameplayAuthority) `
    "p14.gcw-rating.regional-score-travel-gameplay-retired"

$ambientSelection = Get-FunctionSlice $ambientSpawn `
    "public int[] getValidSpawn" `
    "public boolean checkDifficulty"
$ambientCompatibility = Get-FunctionSlice $ambientSpawn `
    "public boolean checkGalacticCivilWarStandings" `
    "public boolean __no_later_method__"
$spawnListRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/spawning/spawn_lists"
$authoredFactionRows = 0
Get-ChildItem -LiteralPath $spawnListRoot -Recurse -File -Filter "*.tab" | ForEach-Object {
    $rows = @(Get-Content -LiteralPath $_.FullName)
    if ($rows.Count -lt 3) { return }
    $columns = $rows[0] -split "`t", -1
    $factionColumn = [Array]::IndexOf($columns, "intGCWFaction")
    if ($factionColumn -lt 0) { return }
    for ($row = 2; $row -lt $rows.Count; ++$row)
    {
        $values = $rows[$row] -split "`t", -1
        if ($values.Count -gt $factionColumn -and $values[$factionColumn] -match "^[1-9]") { ++$authoredFactionRows }
    }
}
Assert-Contract ($ambientSelection.Contains("checkDifficulty(intMinDifficulty, intMaxDifficulty, dctPlayerStats)") -and
    -not $ambientSelection.Contains("intGCW") -and
    -not $ambientSelection.Contains("checkGalacticCivilWarStandings") -and
    -not $ambientSpawn.Contains("getGcwGroupImperialScorePercentile") -and
    -not $ambientSpawn.Contains("getGcwImperialScorePercentile") -and
    $ambientCompatibility.Contains("return true;") -and
    $authoredFactionRows -eq [int]$contract.expected.authoredAmbientFactionRowsEligibleForNormalSelection -and
    -not [bool]$contract.expected.regionalScoreAmbientSpawnAuthority) `
    "p14.gcw-rating.regional-score-ambient-spawn-authority-retired"

$spaceBattleStart = Get-FunctionSlice $spaceBattle `
    "public int startSpaceGCWBattle" `
    "public void makeComponentsUntargetable"
Assert-Contract ($spaceBattleStart.Contains('rand(0, 1) == 0 ? "imperial" : "rebel"') -and
    -not $spaceBattleStart.Contains("getGcw") -and
    -not [bool]$contract.expected.regionalScoreSpaceBattleSideAuthority) `
    "p14.gcw-rating.regional-score-space-battle-side-authority-retired"
Assert-Contract ($terminalGcw.Contains("getGcwGroupImperialScorePercentile(strSubCategory)") -and
    $cityShipSpawner.Contains("getGcwImperialScorePercentile") -and
    $gcwPainting.Contains("getGcwGroupImperialScorePercentile") -and
    [bool]$contract.expected.regionalScorePresentationReadCompatibilityPreserved) `
    "p14.gcw-rating.regional-score-presentation-remains-read-only"

Assert-Contract ($mission.Contains("transferBankCreditsFromNamedAccount(money.ACCT_MISSION_DYNAMIC, recipient, intReward") -and
    $mission.Contains("factions.awardFactionStanding(objPlayer, strFaction, intFactionReward)") -and
    $mission.Contains("fullRewardEach=") -and
    $mission.Contains("split=false dailyCashPenalty=false")) `
    "p14.gcw-rating.mission-credit-and-standing-rewards-retained"
Assert-Contract ($groundquests.Contains("money.bankTo(money.ACCT_NEW_PLAYER_QUESTS, player, bankCredits)") -and
    $groundquests.Contains("factions.setFactionStanding(player, factionName, currentFactionStanding + factionAmount)") -and
    $groundquests.Contains("static_item.createNewItemFunction(grantGcwRebReward, playerInv)")) `
    "p14.gcw-rating.groundquest-independent-rewards-retained"
Assert-Contract ($battlefield.Contains("factions.addFactionStanding(self, faction, standing)") -and
    -not $battlefield.Contains("item_battlefield_rebel_token_") -and
    -not $battlefield.Contains("item_battlefield_imperial_token_")) `
    "p14.gcw-rating.precu-open-world-battlefield-standing-retained"
Assert-Contract ($battlefieldLibrary.Contains("STARTING_BUILD_POINTS = 500") -and
    $battlefieldLibrary.Contains("MAXIMUM_POPULATION = 50") -and
    $battlefieldLibrary.Contains("MAXIMUM_FACTION_SIZE_DIFFERENCE = 5") -and
    $battlefieldLibrary.Contains("factions.addFactionStanding(player, faction, amt * -1)") -and
    $battlefieldDestroy.Contains("if (total_time < 900)") -and
    $battlefieldDestroy.Contains("if (percent_time > 0.1)") -and
    $battlefieldDestroy.Contains('params.put("standing", 25.0f)') -and
    $battlefieldAssault.Contains("if (total_time < 900)") -and
    $battlefieldAssault.Contains("if (percent_time > 0.1)") -and
    $battlefieldAssault.Contains('params.put("standing", 25.0f)') -and
    -not ($battlefieldLibrary + $battlefield + $battlefieldDestroy + $battlefieldAssault).Contains("getLevel(") -and
    -not ($battlefieldLibrary + $battlefield + $battlefieldDestroy + $battlefieldAssault).Contains("expertise") -and
    -not ($battlefieldLibrary + $battlefield + $battlefieldDestroy + $battlefieldAssault).Contains("item_battlefield_") -and
    [bool]$contract.expected.precuOpenWorldBattlefieldBalanceAudited -and
    [int]$contract.expected.precuOpenWorldBattlefieldRewardStanding -eq 25 -and
    [int]$contract.expected.precuOpenWorldBattlefieldMinimumRewardSeconds -eq 900 -and
    [double]$contract.expected.precuOpenWorldBattlefieldMinimumParticipationFraction -eq 0.1) `
    "p14.gcw-rating.precu-open-world-battlefield-balance-audited"
Assert-Contract ($battlefieldUtility.Contains("public int OnSpeaking") -and
    $battlefieldUtility.Contains("sendSystemMessageTestingOnly") -and
    -not [bool]$contract.expected.battlefieldUtilityProductionAttachmentReachable) `
    "p14.gcw-rating.battlefield-utility-remains-dormant-testing-surface"
Assert-Contract ($spaceCombat.Contains("public static void doFactionPointGrant") -and
    $spaceCombat.Contains("factions.addFactionStanding(objPlayer, factions.FACTION_IMPERIAL, intImperialFactionPoints)") -and
    $spaceCombat.Contains("factions.addFactionStanding(objPlayer, factions.FACTION_REBEL, intRebelFactionPoints)")) `
    "p14.gcw-rating.space-faction-standing-retained"
Assert-Contract ($spaceBattle.Contains("awardGcwTokens(player, awardedTokens") -and
    $spaceBattle.Contains('static_item.createNewItemFunction("item_" + factionType + "_station_token_01_01"')) `
    "p14.gcw-rating.space-battle-token-rewards-retained"

$patchText = (Get-Content -LiteralPath (Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatches.dsrc.path)) -Raw) +
    (Get-Content -LiteralPath (Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatches.src.path)) -Raw)
Assert-Contract (-not $patchText.Contains("systems/missions/") -and
    -not $patchText.Contains("mission_terminal") -and
    -not $patchText.Contains("mission_base.java")) `
    "p14.gcw-rating.mission-terminal-source-untouched"

Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) `
    "p14.gcw-rating.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU GCW rating retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU GCW rating retirement passed."
