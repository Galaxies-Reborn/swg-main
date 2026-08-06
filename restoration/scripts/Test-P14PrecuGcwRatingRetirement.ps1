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
$manifestExe = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "exe" })
$indexedDsrcCommit = (& git -C $repositoryRoot rev-parse ":dsrc").Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the parent repository's indexed dsrc gitlink." }
$checkedOutDsrcCommit = (& git -C (Join-Path $repositoryRoot "dsrc") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out dsrc commit." }
$indexedSrcCommit = (& git -C $repositoryRoot rev-parse ":src").Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the parent repository's indexed src gitlink." }
$checkedOutSrcCommit = (& git -C (Join-Path $repositoryRoot "src") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out src commit." }
$indexedExeCommit = (& git -C $repositoryRoot rev-parse ":exe").Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the parent repository's indexed exe gitlink." }
$checkedOutExeCommit = (& git -C (Join-Path $repositoryRoot "exe") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out exe commit." }

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
Assert-Contract ($manifestExe.Count -eq 1 -and
    [string]$manifestExe[0].commit -ceq [string]$contract.buildEvidence.serverConfigCommit -and
    $indexedExeCommit -ceq [string]$contract.buildEvidence.serverConfigCommit -and
    $checkedOutExeCommit -ceq [string]$contract.buildEvidence.serverConfigCommit) `
    "p14.gcw-rating.server-config-commit-synchronized"

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
    "attributes" = Join-Path $source "dsrc/.gitattributes"
    "script.library.gcw" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/gcw.java"
    "script.library.factions" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/factions.java"
    "script.player.player_faction" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/player/player_faction.java"
    "script.systems.gcw.pvp_region_bonus_controller" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/pvp_region_bonus_controller.java"
    "template.gcw.pvp_region_watcher" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/object/tangible/gcw/pvp_region_watcher.tpf"
    "script.library.faction_perk" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/faction_perk.java"
    "script.systems.gcw.gcw_parent_object" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/gcw_parent_object.java"
    "script.systems.gcw.gcw_data_updater" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/gcw_data_updater.java"
    "script.planet.planet_base" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/planet/planet_base.java"
    "script.city.guard_spawner" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/city/guard_spawner.java"
    "script.theme_park.script_spawner.spawner_methods.gcw_spawner" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/theme_park/script_spawner/spawner_methods/gcw_spawner.java"
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
    "buildout.corellia_7_2" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/corellia/corellia_7_2.tab"
    "buildout.talus_2_3" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_2_3.tab"
    "buildout.rori_7_7" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/rori/rori_7_7.tab"
    "buildout.naboo_5_4" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/naboo/naboo_5_4.tab"
    "script.library.force_rank" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/force_rank.java"
    "script.library.jedi_trials" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/jedi_trials.java"
    "script.npc.faction_recruiter.player_recruiter" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/npc/faction_recruiter/player_recruiter.java"
    "script.systems.gcw.player_force_rank" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/player_force_rank.java"
    "script.systems.gcw.enclave_controller" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/enclave_controller.java"
    "script.theme_park.jedi_trials.knight_trials" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/theme_park/jedi_trials/knight_trials.java"
    "datatable.pvp.force_rank_xp" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank_xp.tab"
    "datatable.pvp.force_rank_light" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank.tab"
    "datatable.pvp.force_rank_dark" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank_dark.tab"
    "config.localOptions" = Join-Path $source "exe/linux/localOptions.cfg"
    "docker.compose.precu" = Join-Path $source "docker-compose.precu.yml"
    "docker.entrypoint" = Join-Path $source "docker/entrypoint.sh"
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
$factions = [string]$texts["script.library.factions"]
$playerFaction = [string]$texts["script.player.player_faction"]
$pvpRegionController = [string]$texts["script.systems.gcw.pvp_region_bonus_controller"]
$pvpRegionWatcherTemplate = [string]$texts["template.gcw.pvp_region_watcher"]
$factionPerk = [string]$texts["script.library.faction_perk"]
$gcwParent = [string]$texts["script.systems.gcw.gcw_parent_object"]
$gcwDataUpdater = [string]$texts["script.systems.gcw.gcw_data_updater"]
$planetBase = [string]$texts["script.planet.planet_base"]
$guardSpawner = [string]$texts["script.city.guard_spawner"]
$gcwSpawner = [string]$texts["script.theme_park.script_spawner.spawner_methods.gcw_spawner"]
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
$forceRank = [string]$texts["script.library.force_rank"]
$jediTrials = [string]$texts["script.library.jedi_trials"]
$factionRecruiterPlayer = [string]$texts["script.npc.faction_recruiter.player_recruiter"]
$playerForceRank = [string]$texts["script.systems.gcw.player_force_rank"]
$enclaveController = [string]$texts["script.systems.gcw.enclave_controller"]
$knightTrials = [string]$texts["script.theme_park.jedi_trials.knight_trials"]
$forceRankXp = [string]$texts["datatable.pvp.force_rank_xp"]
$forceRankLight = [string]$texts["datatable.pvp.force_rank_light"]
$forceRankDark = [string]$texts["datatable.pvp.force_rank_dark"]
$localOptions = [string]$texts["config.localOptions"]
$dockerCompose = [string]$texts["docker.compose.precu"]
$dockerEntrypoint = [string]$texts["docker.entrypoint"]

$pvpRegionFlag = Get-FunctionSlice $gcw `
    "public static boolean isPostNgePvpRegionBonusRetired()" `
    "public static final String GCW_TUTORIAL_FLAG"
Assert-Contract ($pvpRegionFlag.Contains("fixed-base/Restuss") -and
    $pvpRegionFlag.Contains("ordinary open-world PvP") -and
    $pvpRegionFlag.Contains("return true;") -and
    -not [bool]$contract.expected.postNgePvpRegionBonusControllerReachable) `
    "p14.gcw-rating.pvp-region-bonus-authoritative-retirement-flag"

$releaseRegionCredit = Get-FunctionSlice $gcw "public static boolean releaseGcwPointCredit" "public static void notifyPvpRegionWatcherOfDeath"
$releaseRegionPrefix = $releaseRegionCredit.Substring(0, $releaseRegionCredit.IndexOf("obj_id[] gcwEnemiesList", [System.StringComparison]::Ordinal))
Assert-Contract ($releaseRegionPrefix.Contains("isPostNgePvpRegionBonusRetired()") -and
    $releaseRegionPrefix.Contains("removeScriptVar(player, PVP_REGION_ACTIVITY_PERFORMED)") -and
    $releaseRegionPrefix.Contains("removeBatchScriptVar(player, LIST_CREDIT_FOR_KILLS)") -and
    $releaseRegionPrefix.Contains("return false;")) `
    "p14.gcw-rating.pvp-region-kill-credit-fails-closed"
$notifyRegionDeath = Get-FunctionSlice $gcw "public static void notifyPvpRegionWatcherOfDeath" "public static boolean isAlreadyInArray"
Assert-Contract ($notifyRegionDeath.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
    $notifyRegionDeath.IndexOf("getPvpRegionControllerIdByPlayer", [System.StringComparison]::Ordinal) -and
    $notifyRegionDeath.Contains("removeScriptVar(player, PVP_REGION_ACTIVITY_PERFORMED)")) `
    "p14.gcw-rating.pvp-region-death-notification-fails-closed"
$verifyRegion = Get-FunctionSlice $gcw "public static boolean verifyPvpRegionStatus" "public static int getNpcKillCredit"
Assert-Contract ($verifyRegion.IndexOf("return false;", [System.StringComparison]::Ordinal) -lt
    $verifyRegion.IndexOf("getPvpRegionControllerIdByPlayer", [System.StringComparison]::Ordinal) -and
    $verifyRegion.Contains("removeScriptVar(player, PVP_REGION_ACTIVITY_PERFORMED)")) `
    "p14.gcw-rating.pvp-region-status-fails-closed"
foreach ($functionSpec in @(
    @{ Start = "public static void registerPvpRegionControllerWithPlanet"; Next = "public static obj_id getPvpRegionControllerIdByName"; Return = "return;"; Active = "obj_id planetId" },
    @{ Start = "public static obj_id getPvpRegionControllerIdByName"; Next = "public static obj_id getPvpRegionControllerIdByPlayer"; Return = "return null;"; Active = "obj_id planetId" },
    @{ Start = "public static obj_id getPvpRegionControllerIdByPlayer"; Next = "public static void notifyPvpRegionControllerOfPlayerEnter"; Return = "return null;"; Active = "region[] regionList" },
    @{ Start = "public static void notifyPvpRegionControllerOfPlayerEnter"; Next = "public static void makeBattlefieldRegion"; Return = "return;"; Active = "dictionary dict" },
    @{ Start = "public static void getRegionToRegister"; Next = "public static boolean isPlayerValidOnBattlefield"; Return = "return;"; Active = "if (!isIdValid(controller))" }
))
{
    $slice = Get-FunctionSlice $gcw $functionSpec.Start $functionSpec.Next
    Assert-Contract ($slice.Contains("isPostNgePvpRegionBonusRetired()") -and
        $slice.IndexOf([string]$functionSpec.Return, [System.StringComparison]::Ordinal) -ge 0 -and
        $slice.IndexOf([string]$functionSpec.Return, [System.StringComparison]::Ordinal) -lt
        $slice.IndexOf([string]$functionSpec.Active, [System.StringComparison]::Ordinal)) `
        "p14.gcw-rating.pvp-region.$($functionSpec.Start.Split(' ')[3]).fails-closed"
}

$playerRegionCleanup = Get-FunctionSlice $playerFaction "public void cleanupRetiredPvpRegionBonusState" "public int OnAttach"
Assert-Contract ($playerRegionCleanup.Contains("isPostNgePvpRegionBonusRetired()") -and
    $playerRegionCleanup.Contains("removeScriptVar(self, gcw.PVP_REGION_ACTIVITY_PERFORMED)")) `
    "p14.gcw-rating.pvp-region-player-state-cleanup"
foreach ($entrypoint in @("OnAttach", "OnInitialize", "OnLogin"))
{
    Assert-Contract ([regex]::IsMatch($playerFaction, "(?s)public int $entrypoint\([^}]+cleanupRetiredPvpRegionBonusState\(self\)")) `
        "p14.gcw-rating.pvp-region-player-entrypoint.$entrypoint.cleans"
}
$receiveRegionBonus = Get-FunctionSlice $playerFaction "public int recievePvpRegionBonus" "public int cmdFactionalHelper"
Assert-Contract ($receiveRegionBonus.Contains("isPostNgePvpRegionBonusRetired()") -and
    $receiveRegionBonus.IndexOf("cleanupRetiredPvpRegionBonusState(self)", [System.StringComparison]::Ordinal) -lt
    $receiveRegionBonus.IndexOf("hasScriptVar(self, gcw.PVP_REGION_ACTIVITY_PERFORMED)", [System.StringComparison]::Ordinal)) `
    "p14.gcw-rating.pvp-region-player-bonus-fails-closed"

$controllerCleanup = Get-FunctionSlice $pvpRegionController "private void retirePostNgePvpRegionBonus" "public int OnAttach"
Assert-Contract ($controllerCleanup.Contains("trial.bumpSession(self)") -and
    $controllerCleanup.Contains("utils.getObjIdScriptVar(planet, registration) == self") -and
    $controllerCleanup.Contains("removeScriptVar(planet, registration)") -and
    $controllerCleanup.Contains("removeScriptVarTree(self, GCW_REGION_DATA)") -and
    $controllerCleanup.Contains('removeScriptVar(self, "pvp_region")') -and
    $controllerCleanup.Contains("detachScript(self, SCRIPT_NAME)")) `
    "p14.gcw-rating.pvp-region-persisted-controller-cleans"
foreach ($entrypoint in @("OnAttach", "OnInitialize", "cycleUpdate", "diedInPvpRegion"))
{
    Assert-Contract ([regex]::IsMatch($pvpRegionController,
        "(?s)public int $entrypoint\([^}]+isPostNgePvpRegionBonusRetired\(\)[^}]+retirePostNgePvpRegionBonus\(self\)[^}]+return SCRIPT_CONTINUE;")) `
        "p14.gcw-rating.pvp-region-controller-entrypoint.$entrypoint.cleans"
}

Assert-Contract ($pvpRegionWatcherTemplate.Contains('sharedTemplate = "object/tangible/gcw/shared_pvp_region_watcher.iff"') -and
    [regex]::IsMatch($pvpRegionWatcherTemplate, '(?m)^scripts\s*=\s*\[\s*\]\s*$') -and
    -not $pvpRegionWatcherTemplate.Contains("systems.gcw.pvp_region_bonus_controller") -and
    -not [bool]$contract.expected.pvpRegionWatcherTemplateScriptsAttached) `
    "p14.gcw-rating.pvp-region-watcher-template-controller-detached"

$watcherRows = [ordered]@{
    "buildout.corellia_7_2" = "-537065502"
    "buildout.talus_2_3" = "-1324255298"
    "buildout.rori_7_7" = "-512151733"
    "buildout.naboo_5_4" = "-529152824"
}
foreach ($name in $watcherRows.Keys)
{
    $rows = @(([string]$texts[$name] -split "`r?`n") | Where-Object { $_.StartsWith([string]$watcherRows[$name] + "`t", [System.StringComparison]::Ordinal) })
    $valid = $rows.Count -eq 1
    if ($valid)
    {
        $columns = $rows[0].Split("`t", [System.StringSplitOptions]::None)
        $valid = $columns.Count -eq 13 -and
            $columns[2] -ceq "object/tangible/gcw/pvp_region_watcher.iff" -and
            $columns[11].Length -eq 0
    }
    Assert-Contract $valid "p14.gcw-rating.$name.pvp-region-watcher-inert-scenery-retained"
}
Assert-Contract (-not [bool]$contract.expected.pvpRegionWatcherBuildoutScriptsAttached -and
    [bool]$contract.expected.persistedPvpRegionControllerStateScrubbed -and
    [bool]$contract.expected.stalePvpRegionPlayerStateScrubbed -and
    [int]$contract.expected.pvpRegionWatcherSceneryPreserved -eq 4) `
    "p14.gcw-rating.pvp-region-contract-expectations"

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
$warRetire = Get-FunctionSlice $terminalGcw "private void retirePostNgeWarTerminalState" "public int OnObjectMenuRequest"
$warMenuRequest = Get-FunctionSlice $terminalGcw "public int OnObjectMenuRequest" "public int OnObjectMenuSelect"
$warMenuSelect = Get-FunctionSlice $terminalGcw "public int OnObjectMenuSelect" "public int OnClusterWideDataResponse"
$warStaleSelection = Get-FunctionSlice $terminalGcw `
    "else if (item == menu_info_types.SERVER_MENU1 || item == menu_info_types.SERVER_MENU3)" `
    "else if (item == menu_info_types.SERVER_MENU2)"
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

$requiredWarTerminalCleanup = @(
    'removeObjVar(self, "gcwWarIntelPadMostRecentAction")',
    'utils.removeScriptVar(player, "gcw.gcwPersonalContributionTablePid")',
    'utils.removeLocalVar(playerObject, "gcwContributionTrackingLastUpdated")',
    'utils.removeLocalVar(playerObject, "gcwContributionTrackingColumnName")',
    'utils.removeLocalVar(playerObject, "gcwContributionTrackingColumnType")',
    'utils.removeLocalVar(playerObject, "gcwContributionTrackingColumn0")',
    'utils.removeLocalVar(playerObject, "gcwContributionTrackingColumn1")'
)
Assert-Contract ($warRetire.Contains("action == menu_info_types.SERVER_MENU1 || action == menu_info_types.SERVER_MENU3") -and
    (@($requiredWarTerminalCleanup | Where-Object { -not $warRetire.Contains($_) }).Count -eq 0) -and
    $warMenuRequest.Contains("retirePostNgeWarTerminalState(self, player);") -and
    $warMenuSelect.Contains("retirePostNgeWarTerminalState(self, player);") -and
    -not $warMenuRequest.Contains("menu_info_types.SERVER_MENU1") -and
    -not $warMenuRequest.Contains("menu_info_types.SERVER_MENU3") -and
    $warStaleSelection.Contains("retirePostNgeWarTerminalState(self, player);") -and
    $warStaleSelection.Contains("return SCRIPT_CONTINUE;") -and
    -not $terminalGcw.Contains("battlefield_war_terminal_menu") -and
    -not $terminalGcw.Contains("gcw_personal_contribution_war_terminal_menu") -and
    -not $terminalGcw.Contains("displayBattlefieldSui") -and
    -not $terminalGcw.Contains("getGcwContributionTrackingTableDictionary") -and
    -not $terminalGcw.Contains("gcw_personal_contribution_sui_table_header") -and
    -not [bool]$contract.expected.warTerminalQueuedBattlefieldActionReachable -and
    -not [bool]$contract.expected.warTerminalPersonalContributionReachable -and
    [bool]$contract.expected.staleContributionLedgerStateScrubbed) `
    "p14.gcw-rating.war-terminal-queue-and-contribution-retired"
Assert-Contract ($warMenuRequest.Contains("SERVER_MENU5, SID_MENU_GCW") -and
    $warMenuRequest.Contains("SERVER_MENU6, SID_MENU_GCW_REPORT") -and
    $warMenuRequest.Contains("SERVER_MENU2, SID_MENU_GCW_FACTIONAL_PRESENCE") -and
    $warMenuSelect.Contains("getGcwFactionalPresenceTableDictionary()") -and
    $terminalGcw.Contains("getGcwGroupImperialScorePercentile(strSubCategory)") -and
    [bool]$contract.expected.warTerminalReportPreserved -and
    [bool]$contract.expected.warTerminalFactionPresencePreserved) `
    "p14.gcw-rating.war-terminal-report-and-faction-presence-preserved"

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
    $gcw.Contains("getImperialPlanetControlScore(target)") -and
    [bool]$contract.expected.regionalScoreAndContentCompatibilityPreserved -and
    -not [bool]$contract.expected.postNgeRegionalDefenderMembershipReachable -and
    -not [bool]$contract.expected.postNgeRegionalDefenderBonusReachable -and
    -not [bool]$contract.expected.postNgeRegionalDefenderTitlesReachable -and
    -not [bool]$contract.expected.postNgeRegionalDefenderPresentationReachable -and
    [bool]$contract.expected.staleRegionalDefenderPlayerStateScrubbed) `
    "p14.gcw-rating.regional-content-preserved-with-defender-system-retired"

$legacyPeriodicUpdate = Get-FunctionSlice $gcwParent `
    "public int updateGCWData" `
    "public int updateGCWScore"
$legacyDeltaForwarder = Get-FunctionSlice $gcwParent `
    "public int updateGCWScore" `
    "public int synchronizeGCWScore"
$legacyAbsoluteForwarder = Get-FunctionSlice $gcwParent `
    "public int synchronizeGCWScore" `
    "}`n}"
$masterLookup = Get-FunctionSlice $gcw `
    "public static obj_id getGCWMasterObject(location locTest)" `
    "public static boolean isPrecuGcwControlPlanet"
$precuPercentile = Get-FunctionSlice $gcw `
    "public static int getImperialPercentileByRegion" `
    "public static int getRebelPercentileByRegion"
$gcwDictionary = Get-FunctionSlice $gcw `
    "public static dictionary getGCWDictionary" `
    "public static int getImperialPlanetControlScore"
$imperialRatio = Get-FunctionSlice $gcw `
    "public static float getImperialRatio" `
    "public static float getRebelRatio"
$rebelRatio = Get-FunctionSlice $gcw `
    "public static float getRebelRatio" `
    "public static void incrementGCWStanding"
$baseDestroy = Get-FunctionSlice $hqLoader `
    "public int OnDestroy" `
    "private void setCWData"
$planetReconciliation = Get-FunctionSlice $planetBase `
    "public int reconcilePrecuGcwBaseControl" `
    "public int OnClusterWideDataResponse"
$planetAbsoluteResponse = Get-FunctionSlice $planetBase `
    "public int OnClusterWideDataResponse" `
    "public int updateGCWScore"
$planetDeltaUpdate = Get-FunctionSlice $planetBase `
    "public int updateGCWScore" `
    "public int synchronizeGCWScore"
$planetAbsoluteUpdate = Get-FunctionSlice $planetBase `
    "public int synchronizeGCWScore" `
    "public int updateGCWData"
Assert-Contract (-not $legacyPeriodicUpdate.Contains("setObjVar") -and
    -not $legacyPeriodicUpdate.Contains("getImperialPercentileByRegion") -and
    -not $legacyPeriodicUpdate.Contains("getRebelPercentileByRegion") -and
    -not $legacyPeriodicUpdate.Contains('messageTo(self, "updateGCWData"')) `
    "p14.gcw-rating.nge-percentile-planet-overwrite-retired"
Assert-Contract ($legacyDeltaForwarder.Contains("gcw.changeGCWScore(getLocation(self)") -and
    $legacyAbsoluteForwarder.Contains("gcw.synchronizePlanetaryBaseControlScore(getLocation(self)") -and
    -not $gcwParent.Contains("ensurePrecuControlScoreState") -and
    -not $gcwParent.Contains("setObjVar(self")) `
    "p14.gcw-rating.legacy-master-object-demoted-to-forwarder"
Assert-Contract ($masterLookup.Contains("isPrecuGcwControlPlanet(locTest.area)") -and
    $masterLookup.Contains("return getPlanetByName(locTest.area);") -and
    -not $masterLookup.Contains("gcw_master_objects") -and
    -not $masterLookup.Contains("strObjId") -and
    -not [bool]$contract.expected.legacyGcwMasterObjectIdsRequired) `
    "p14.gcw-rating.planet-object-is-control-authority"
Assert-Contract ($precuPercentile.Contains("getImperialPlanetControlScore(target)") -and
    $precuPercentile.Contains("getRebelPlanetControlScore(target)") -and
    $precuPercentile.Contains("(long)imperial * 100L") -and
    -not $precuPercentile.Contains("getGcwImperialScorePercentile") -and
    [bool]$contract.expected.precuBaseDerivedRegionalPresentation) `
    "p14.gcw-rating.regional-presentation-derived-from-base-control"
Assert-Contract ($gcwDictionary.Contains("getImperialPlanetControlScore(self)") -and
    $gcwDictionary.Contains("getRebelPlanetControlScore(self)") -and
    $imperialRatio.Contains("getImperialPlanetControlScore(objNPC)") -and
    $imperialRatio.Contains("getRebelPlanetControlScore(objNPC)") -and
    $rebelRatio.Contains("getImperialPlanetControlScore(objNPC)") -and
    $rebelRatio.Contains("getRebelPlanetControlScore(objNPC)") -and
    -not ($gcwDictionary + $imperialRatio + $rebelRatio).Contains("getIntObjVar") -and
    [bool]$contract.expected.precuPlanetRatioReadsDirect) `
    "p14.gcw-rating.legacy-score-readers-use-planet-authority"
Assert-Contract ($planetDeltaUpdate.Contains('params.containsKey("intScoreChange")') -and
    $planetDeltaUpdate.Contains('params.containsKey("strFaction")') -and
    $planetDeltaUpdate.Contains('"Imperial".equals(faction)') -and
    $planetDeltaUpdate.Contains('"Rebel".equals(faction)') -and
    $planetDeltaUpdate.Contains("clampPrecuGcwScore(adjustedScore)") -and
    $planetDeltaUpdate.Contains("setObjVar(self, scoreObjVar")) `
    "p14.gcw-rating.precu-base-delta-handler-on-planet"
Assert-Contract ($planetAbsoluteUpdate.Contains('params.containsKey("imperialScore")') -and
    $planetAbsoluteUpdate.Contains('params.containsKey("rebelScore")') -and
    $planetAbsoluteUpdate.Contains("applyPrecuGcwControlScores(self")) `
    "p14.gcw-rating.precu-base-absolute-synchronizer-on-planet"

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
Assert-Contract ($hqLoader.Contains('PRECU_BASE_CWD_MANAGER = "gcw_player_base"') -and
    $hqLoader.Contains('PRECU_BASE_CWD_ELEMENT_PREFIX = "base_cwdata_manager"') -and
    $baseDestroy.Contains('removeClusterWideData(PRECU_BASE_CWD_MANAGER, PRECU_BASE_CWD_ELEMENT_PREFIX + "-" + self, 0)') -and
    $baseDestroy.IndexOf("removeClusterWideData", [System.StringComparison]::Ordinal) -lt
        $baseDestroy.IndexOf("gcw.decrementGCWScore", [System.StringComparison]::Ordinal) -and
    [bool]$contract.expected.destroyedPlayerBaseRegistryRecordRemoved) `
    "p14.gcw-rating.destroyed-base-removed-from-authoritative-registry"
Assert-Contract ($baseRegister.Contains("PRECU_BASE_RECONCILIATION_PULSE = 3600.0f") -and
    $baseRegister.Contains("setBaseCount(self, rebel, imperial)") -and
    $baseRegister.Contains("releaseClusterWideDataLock(manage_name, lock_key)") -and
    -not $baseRegister.Contains("synchronizePlanetaryBaseControlScore") -and
    -not $baseRegister.Contains("controlScore")) `
    "p14.gcw-rating.base-register-retained-for-placement-counts-only"
Assert-Contract ($planetReconciliation.Contains('getClusterWideData("gcw_player_base", "base_cwdata_manager*", false, self)') -and
    $planetReconciliation.Contains("PRECU_GCW_RECONCILIATION_PULSE") -and
    $planetAbsoluteResponse.Contains('dataItem.containsKey("pointValue")') -and
    $planetAbsoluteResponse.Contains("imperialScore += pointValue") -and
    $planetAbsoluteResponse.Contains("rebelScore += pointValue") -and
    $planetAbsoluteResponse.Contains("applyPrecuGcwControlScores(self") -and
    [int]$contract.expected.precuPlayerBaseReconciliationSeconds -eq 3600) `
    "p14.gcw-rating.planet-periodic-absolute-reconciliation"

$classicControlPlanets = @("tatooine", "corellia", "dantooine", "dathomir", "endor", "lok", "naboo", "rori", "talus", "yavin4")
$allControlPlanetsPresent = $true
foreach ($controlPlanet in $classicControlPlanets)
{
    if (-not $gcw.Contains('"' + $controlPlanet + '"')) { $allControlPlanetsPresent = $false }
}
Assert-Contract ($allControlPlanetsPresent -and
    $classicControlPlanets.Count -eq [int]$contract.expected.precuPlanetControlSceneCount -and
    [bool]$contract.expected.precuPlanetObjectControlAuthority) `
    "p14.gcw-rating.ten-classic-ground-planets-covered"
Assert-Contract ($gcwDataUpdater.Contains("getImperialPlanetControlScore(self)") -and
    $gcwDataUpdater.Contains("getRebelPlanetControlScore(self)") -and
    $gcwDataUpdater.Contains("oldWinner != newWinner") -and
    -not $gcwDataUpdater.Contains("getImperialPercentileByRegion") -and
    -not $gcwDataUpdater.Contains("getRebelPercentileByRegion")) `
    "p14.gcw-rating.retained-gcw-content-uses-raw-base-totals"
Assert-Contract ($gcw.Contains("PRECU_GCW_DIFFICULTY_SCORE_DELTA = 64") -and
    $guardSpawner.Contains("scoreDelta >= gcw.PRECU_GCW_DIFFICULTY_SCORE_DELTA") -and
    $gcwSpawner.Contains("imperialScore - rebelScore >= gcw.PRECU_GCW_DIFFICULTY_SCORE_DELTA") -and
    $gcwSpawner.Contains("rebelScore - imperialScore >= gcw.PRECU_GCW_DIFFICULTY_SCORE_DELTA") -and
    [int]$contract.expected.precuBaseDifficultyScoreDelta -eq 64) `
    "p14.gcw-rating.precu-base-difference-drives-difficulty"

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
    (@($requiredResets | Where-Object { -not $retire.Contains($_) }).Count -eq 0) -and
    $retire.Contains('removeObjVarItem("gcwContributionTracking")') -and
    $retire.Contains('removeObjVarItem("gcwContributionTrackingLastUpdated")')) `
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

$nativeContributionRead = Get-FunctionSlice $scriptPvp `
    "jobject JNICALL ScriptMethodsPvpNamespace::getGcwContributionTrackingTableDictionary" `
    "jobjectArray JNICALL ScriptMethodsPvpNamespace::getGcwDefenderRegions"
Assert-Contract ($nativeContributionRead.Contains("UNREF(env);") -and
    $nativeContributionRead.Contains("UNREF(self);") -and
    $nativeContributionRead.Contains("UNREF(player);") -and
    $nativeContributionRead.Contains("return 0;") -and
    -not $nativeContributionRead.Contains("JavaLibrary::getObject") -and
    -not $nativeContributionRead.Contains("gcwContribution") -and
    -not $nativeContributionRead.Contains("JavaDictionaryPtr")) `
    "p14.gcw-rating.native-contribution-ledger-read-inert"

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

$frsConfigLines = @($localOptions -split "`r?`n" | Where-Object { $_ -match '^enableFRS=' })
$startPlanetLines = @($dockerCompose -split "`r?`n" | Where-Object { $_.Contains('SWG_START_PLANETS: ${SWG_PRECU_START_PLANETS:-') })
$defaultPlanets = @()
if ($startPlanetLines.Count -eq 1)
{
    $defaultPlanets = @((($startPlanetLines[0] -split ':-', 2)[1].Trim().TrimEnd('}')) -split ',')
}
Assert-Contract ($frsConfigLines.Count -eq 1 -and
    $frsConfigLines[0] -ceq "enableFRS=1" -and
    $startPlanetLines.Count -eq 1 -and
    @($defaultPlanets | Where-Object { $_ -ceq "yavin4" }).Count -eq 1 -and
    [bool]$contract.expected.precuForceRankingSystemEnabled -and
    [bool]$contract.expected.precuFrsYavinEnclavesReachable) `
    "p14.gcw-rating.precu-frs-enabled-with-yavin-enclaves"

$runtimeConfigSync = Get-FunctionSlice $dockerEntrypoint "sync_runtime_config_files()" "apply_runtime_scene_profile()"
$runtimeServiceAddresses = Get-FunctionSlice $dockerEntrypoint "write_runtime_service_addresses()" "ensure_runtime_symlinks()"
$runtimeInit = Get-FunctionSlice $dockerEntrypoint "init_server()" "build_server()"
$runtimeRun = Get-FunctionSlice $dockerEntrypoint "run_server()" "mark_git_safe"
Assert-Contract ($runtimeConfigSync.Contains("for config_file in localOptions.cfg logServerTargets.cfg taskmanager.rc") -and
    $runtimeServiceAddresses.Contains('s|^(transferServerAddress=).*|\\1${node_address}|') -and
    $runtimeServiceAddresses.Contains('s|^(clusterName=).*|\\1${SWG_CLUSTER_NAME}|') -and
    $runtimeInit.IndexOf("sync_runtime_config_files", [System.StringComparison]::Ordinal) -lt $runtimeInit.IndexOf("write_runtime_network_config", [System.StringComparison]::Ordinal) -and
    $runtimeRun.IndexOf("sync_runtime_config_files", [System.StringComparison]::Ordinal) -lt $runtimeRun.IndexOf("write_runtime_network_config", [System.StringComparison]::Ordinal) -and
    [bool]$contract.expected.runtimeSceneProfileRehydratesCanonicalConfig) `
    "p14.gcw-rating.runtime-scene-profile-rehydrates-canonical-config"

$frsEnabledHelper = Get-FunctionSlice $forceRank `
    "public static boolean isForceRankingEnabled()" `
    "public static boolean addToForceRankSystem"
$frsAddPlayer = Get-FunctionSlice $forceRank `
    "public static boolean addToForceRankSystem" `
    "public static boolean removeFromForceRankSystem"
Assert-Contract ($frsEnabledHelper.Contains('getConfigSetting("GameServer", "enableFRS")') -and
    $frsEnabledHelper.Contains('config.equals("1")') -and
    $frsAddPlayer.Contains("if (!isForceRankingEnabled())") -and
    $frsAddPlayer.Contains("setJediState(player, JEDI_STATE_FORCE_RANKED_LIGHT)") -and
    $frsAddPlayer.Contains('pvpSetAlignedFaction(player, getFactionId("Rebel"))') -and
    $frsAddPlayer.Contains('pvpSetAlignedFaction(player, getFactionId("Imperial"))') -and
    $frsAddPlayer.Contains("pvpMakeDeclared(player)") -and
    $frsAddPlayer.Contains("grantSkill(player, rank_skill)")) `
    "p14.gcw-rating.precu-frs-enrollment-and-faction-authority"

$frsPlayerInitialize = Get-FunctionSlice $playerForceRank `
    "public int OnInitialize" `
    "public int OnAttach"
$frsPlayerAttach = Get-FunctionSlice $playerForceRank `
    "public int OnAttach" `
    "public int OnDetach"
$frsPlayerLogin = Get-FunctionSlice $playerForceRank `
    "public int OnLogin" `
    "public int OnSkillRevoked"
$frsPlayerValidate = Get-FunctionSlice $playerForceRank `
    "public int msgValidateFRSPlayerData" `
    "public int cmdShowCouncilRank"
Assert-Contract ($frsPlayerInitialize.Contains("force_rank.isForceRankingEnabled()") -and
    $frsPlayerInitialize.Contains('force_rank.getEnclaveObjId(self, force_rank.getCouncilAffiliation(self), "enclaveIdResponse")') -and
    $frsPlayerInitialize.Contains("return SCRIPT_CONTINUE;") -and
    $frsPlayerAttach.Contains("force_rank.isForceRankingEnabled()") -and
    $frsPlayerAttach.Contains("force_rank.getEnclaveObjId") -and
    $frsPlayerLogin.Contains("force_rank.isForceRankingEnabled()") -and
    $frsPlayerLogin.Contains("force_rank.requestExperienceDebt(self)") -and
    $frsPlayerValidate.Contains("force_rank.isForceRankingEnabled()") -and
    $frsPlayerValidate.Contains("force_rank.resyncForceRankSkills(self)") -and
    $frsPlayerValidate.Contains("pvpMakeDeclared(self)") -and
    -not $frsPlayerValidate.Contains("removeFromForceRankSystem") -and
    [bool]$contract.expected.precuFrsPlayerLifecycleRetained) `
    "p14.gcw-rating.precu-frs-player-lifecycle-restored"

$enclaveInitializeDisabledBoundary = Get-FunctionSlice $enclaveController `
    "public int OnInitialize" `
    'LOG("force_rank", "enclave_controller.OnInitialize -- " + self)'
$enclavePulse = Get-FunctionSlice $enclaveController `
    "public int msgEnclavePulse" `
    "public int msgValidateFRSPlayerData"
Assert-Contract ($enclaveInitializeDisabledBoundary.Contains("force_rank.isForceRankingEnabled()") -and
    $enclaveInitializeDisabledBoundary.Contains("force_rank.makeAllCellsPublic(self)") -and
    -not $enclaveInitializeDisabledBoundary.Contains("removeObjVar") -and
    -not $enclaveInitializeDisabledBoundary.Contains("resetEnclaveData") -and
    -not $enclaveInitializeDisabledBoundary.Contains("resetClusterData") -and
    -not $enclaveInitializeDisabledBoundary.Contains("createEnclaveTerminals") -and
    $enclavePulse.Contains("force_rank.isForceRankingEnabled()") -and
    $enclavePulse.Contains("force_rank.performEnclaveMaintenance(self)") -and
    [bool]$contract.expected.precuFrsPersistentCouncilDataPreservedWhenDisabled) `
    "p14.gcw-rating.precu-frs-disabled-boundary-preserves-council-data"

$playerCovert = Get-FunctionSlice $playerFaction "public int msgGoCovert" "public int msgGoOnLeave"
$playerOnLeave = Get-FunctionSlice $playerFaction "public int msgGoOnLeave" "public int msgGoOvert"
$playerOvert = Get-FunctionSlice $playerFaction "public int msgGoOvert" "public int gcwStatus"
$recruiterCovert = Get-FunctionSlice $factionRecruiterPlayer "public int msgGoCovert" "public int msgFactionTrainingTypeSelected"
$rankedJediFactionBoundaries = $playerCovert + $playerOnLeave + $playerOvert + $recruiterCovert
Assert-Contract ($playerCovert.Contains('hasSkill(self, "force_rank_light_novice")') -and
    $playerOnLeave.Contains('hasSkill(self, "force_rank_light_novice")') -and
    $playerOvert.Contains('hasSkill(self, "force_rank_light_novice")') -and
    $recruiterCovert.Contains('hasSkill(self, "force_rank_light_novice")') -and
    -not $rankedJediFactionBoundaries.Contains('hasScript(self, "force_rank_') -and
    [bool]$contract.expected.precuFrsRankedJediFactionStatusEnforced) `
    "p14.gcw-rating.precu-frs-ranked-jedi-remain-overt"

$jediTrialEligibility = Get-FunctionSlice $jediTrials `
    "public static boolean isEligibleForJediKnightTrials" `
    "public static int isEligibleForJediKnightTrialsPointsRemaining"
$knightTrialInitialize = Get-FunctionSlice $knightTrials `
    "public int OnInitialize" `
    "public int handleForceShrineTrialMessage"
Assert-Contract ($jediTrialEligibility.Contains("force_rank.isForceRankingEnabled()") -and
    $knightTrialInitialize.Contains("force_rank.isForceRankingEnabled()") -and
    -not ($jediTrialEligibility + $knightTrialInitialize).Contains('getConfigSetting("GameServer", "enableFRS")') -and
    [bool]$contract.expected.precuFrsJediTrialsEnabled) `
    "p14.gcw-rating.precu-frs-jedi-trials-use-authoritative-enable-gate"

Assert-Contract ($forceRank.Contains("REQUEST_DEMOTION_COST = 2000") -and
    $forceRank.Contains("VOTE_CHALLENGE_COST = 1000") -and
    [int]$contract.expected.precuFrsRequestDemotionCost -eq 2000 -and
    [int]$contract.expected.precuFrsVoteChallengeCost -eq 1000) `
    "p14.gcw-rating.precu-frs-publish14-costs"

$expectedFrsRows = [ordered]@{
    "nj_xp_gain" = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    "nj_xp_loss" = @(1000, 1250, 1759, 2250, 3000, 3750, 4750, 5500, 6750, 7750, 8750, 10000)
    "bh_xp_gain" = @(500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500)
    "bh_xp_loss" = @(1000, 1250, 1759, 2250, 3000, 3750, 4750, 5500, 6750, 7750, 8750, 10000)
    "pw_xp_gain" = @(200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200)
    "pw_xp_loss" = @(500, 650, 1000, 1250, 1750, 2250, 2750, 2350, 4000, 4500, 5000, 6000)
    "r0_xp_gain" = @(750, 750, 750, 750, 750, 750, 750, 750, 750, 750, 750, 750)
    "r0_xp_loss" = @(250, 500, 750, 1000, 1500, 2000, 2500, 3000, 3750, 4250, 5000, 5750)
    "r1_xp_gain" = @(900, 900, 900, 900, 900, 900, 900, 900, 900, 900, 900, 900)
    "r1_xp_loss" = @(100, 250, 500, 900, 1300, 1750, 2250, 2750, 3500, 4150, 4750, 5500)
}
$rankGain = @(1250, 2250, 3000, 3750, 4500, 5500, 6500, 7500, 8750, 9750)
$genericRankLoss = @(100, 250, 500, 900, 1300, 1750, 2250, 2750, 3500, 4150, 4750, 5500)
for ($rank = 2; $rank -le 11; ++$rank)
{
    $expectedFrsRows["r${rank}_xp_gain"] = @($rankGain[$rank - 2]) * 12
    $expectedFrsRows["r${rank}_xp_loss"] = $genericRankLoss
}
$frsXpLines = @($forceRankXp -split "`r?`n" | Where-Object { $_.Length -gt 0 })
$actualFrsRows = @{}
for ($row = 2; $row -lt $frsXpLines.Count; ++$row)
{
    $columns = @($frsXpLines[$row] -split "`t")
    if ($columns.Count -eq 13)
    {
        $actualFrsRows[$columns[0]] = @($columns[1..12] | ForEach-Object { [int]$_ })
    }
}
$frsMatrixExact = $frsXpLines.Count -eq 32 -and $actualFrsRows.Count -eq $expectedFrsRows.Count
foreach ($key in $expectedFrsRows.Keys)
{
    $frsMatrixExact = $frsMatrixExact -and $actualFrsRows.ContainsKey($key) -and
        (($actualFrsRows[$key] -join ',') -ceq ($expectedFrsRows[$key] -join ','))
}
Assert-Contract ($frsMatrixExact -and [bool]$contract.expected.precuFrsExperienceMatrixExact) `
    "p14.gcw-rating.precu-frs-publish14-experience-matrix"

$rankXp = @(0, 5000, 15000, 25000, 35000, 50000, 70000, 90000, 130000, 180000, 250000, 400000)
$rankCaps = @(-1, 10, 10, 10, 10, 9, 9, 9, 8, 8, 11, 1)
$frsRankDataExact = $true
foreach ($table in @(@{ Text = $forceRankLight; Prefix = "force_rank_light_" }, @{ Text = $forceRankDark; Prefix = "force_rank_dark_" }))
{
    $lines = @($table.Text -split "`r?`n" | Where-Object { $_.Length -gt 0 })
    $frsRankDataExact = $frsRankDataExact -and $lines.Count -eq 14
    for ($rank = 0; $rank -le 11; ++$rank)
    {
        $columns = @($lines[$rank + 2] -split "`t")
        $expectedSkill = if ($rank -eq 0) { "$($table.Prefix)novice" } elseif ($rank -eq 11) { "$($table.Prefix)master" } else { "$($table.Prefix)rank_$($rank.ToString('00'))" }
        $frsRankDataExact = $frsRankDataExact -and $columns.Count -eq 4 -and
            [int]$columns[0] -eq $rank -and $columns[1] -ceq $expectedSkill -and
            [int]$columns[2] -eq $rankCaps[$rank] -and [int]$columns[3] -eq $rankXp[$rank]
    }
}
Assert-Contract ($frsRankDataExact -and [bool]$contract.expected.precuFrsRankDataExact) `
    "p14.gcw-rating.precu-frs-publish14-rank-data"

$frsRuntime = $forceRank + $jediTrials + $playerForceRank + $enclaveController + $knightTrials
$frsNgeDependencies = [regex]::Matches($frsRuntime, 'getLevel\s*\(|getSkillTemplate\s*\(|utils\.isProfession\s*\(|expertise', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
Assert-Contract ($frsNgeDependencies -eq [int]$contract.expected.precuFrsRuntimeNgeProgressionDependencies) `
    "p14.gcw-rating.precu-frs-no-nge-progression-authority"

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
Assert-Contract ($playerFaction.Contains("public int cmdPVP") -and
    $playerFaction.Contains("factions.isInAdhocPvpArea(self)") -and
    $playerFaction.Contains("pvpMakeDeclared(self)") -and
    [bool]$contract.expected.precuOpenWorldPvpPreserved) `
    "p14.gcw-rating.precu-open-world-pvp-preserved"

$neutralMercenaryRetired = Get-FunctionSlice $factions `
    "public static boolean isPostNgeNeutralMercenaryRetired()" `
    "public static void cleanupRetiredNeutralMercenaryState"
$neutralMercenaryCleanup = Get-FunctionSlice $factions `
    "public static void cleanupRetiredNeutralMercenaryState" `
    "public static void goCovertWithDelay"
$neutralMercenaryConfig = @($localOptions -split "`r?`n" | Where-Object { $_ -match '^enable(Covert|Overt)(Imperial|Rebel)Mercenary=' })
$expectedNeutralMercenaryConfig = @(
    "enableCovertImperialMercenary=false",
    "enableOvertImperialMercenary=false",
    "enableCovertRebelMercenary=false",
    "enableOvertRebelMercenary=false"
)
Assert-Contract ($neutralMercenaryRetired.Contains("return true;") -and
    $neutralMercenaryCleanup.Contains("forceCloseSUIPage(pageId)") -and
    $neutralMercenaryCleanup.Contains('utils.removeScriptVarTree(player, "factionalHelper")') -and
    $neutralMercenaryCleanup.Contains('removeObjVar(player, "factionalHelper")') -and
    $neutralMercenaryCleanup.Contains("pvpNeutralSetMercenaryFaction(player, 0, false)") -and
    [bool]$contract.expected.staleNeutralMercenaryStateScrubbed) `
    "p14.gcw-rating.stale-neutral-mercenary-state-scrubbed"

$neutralMercenaryLibraryMethods = @(
    (Get-FunctionSlice $factions "public static boolean canChangeNeutralMercenaryStatus" "public static boolean neutralMercenaryStatusMenu"),
    (Get-FunctionSlice $factions "public static boolean neutralMercenaryStatusMenu" "public static boolean setNeturalMercenaryCovert"),
    (Get-FunctionSlice $factions "public static boolean setNeturalMercenaryCovert" "public static boolean setNeturalMercenaryOvert"),
    (Get-FunctionSlice $factions "public static boolean setNeturalMercenaryOvert" "public static boolean removeNeturalMercenary"),
    (Get-FunctionSlice $factions "public static boolean removeNeturalMercenary" "__end_of_factions__")
)
$neutralMercenaryPlayerMethods = @(
    (Get-FunctionSlice $playerFaction "public int cmdFactionalHelper" "public int handleFactionalHelperChoice"),
    (Get-FunctionSlice $playerFaction "public int handleFactionalHelperChoice" "public int executeFactionalHelperChoice"),
    (Get-FunctionSlice $playerFaction "public int executeFactionalHelperChoice" "public int cmdGcwScore")
)
$neutralMercenaryLifecycle = @(
    (Get-FunctionSlice $playerFaction "public int OnAttach" "public int OnInitialize"),
    (Get-FunctionSlice $playerFaction "public int OnInitialize" "public int OnLogin"),
    (Get-FunctionSlice $playerFaction "public int OnLogin" "public int cmdPVP")
)
Assert-Contract (@($neutralMercenaryLibraryMethods | Where-Object { -not $_.Contains("isPostNgeNeutralMercenaryRetired()") -or -not $_.Contains("cleanupRetiredNeutralMercenaryState(player)") }).Count -eq 0 -and
    @($neutralMercenaryPlayerMethods | Where-Object { -not $_.Contains("factions.isPostNgeNeutralMercenaryRetired()") -or -not $_.Contains("factions.cleanupRetiredNeutralMercenaryState(self)") }).Count -eq 0 -and
    @($neutralMercenaryLifecycle | Where-Object { -not $_.Contains("factions.cleanupRetiredNeutralMercenaryState(self)") }).Count -eq 0 -and
    $neutralMercenaryConfig.Count -eq 4 -and
    @($expectedNeutralMercenaryConfig | Where-Object { $neutralMercenaryConfig -cnotcontains $_ }).Count -eq 0 -and
    -not [bool]$contract.expected.postNgeNeutralMercenaryStatusReachable -and
    -not [bool]$contract.expected.postNgeNeutralMercenaryWriterReachable) `
    "p14.gcw-rating.post-nge-neutral-mercenary-runtime-retired"

Assert-Contract ($factions.Contains("public static boolean joinFaction") -and
    $factions.Contains("pvpSetAlignedFaction(player, faction_id)") -and
    $factions.Contains("pvpMakeCovert(player)") -and
    $factions.Contains("public static void goCovert") -and
    $factions.Contains("pvpMakeCovert(objPlayer)") -and
    $factions.Contains("public static void goOvert") -and
    $factions.Contains("pvpMakeDeclared(objPlayer)") -and
    $factions.Contains("public static void goOnLeave") -and
    $factions.Contains("pvpMakeOnLeave(objPlayer)") -and
    [bool]$contract.expected.precuFactionEnlistmentTransitionsPreserved) `
    "p14.gcw-rating.precu-faction-enlistment-transitions-preserved"
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
