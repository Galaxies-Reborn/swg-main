[CmdletBinding()]
param(
    [string]$Container = "swg-precu",

    [ValidateRange(30, 900)]
    [int]$ReadyTimeoutSeconds = 240,

    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Docker
{
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & docker @Arguments
    if ($LASTEXITCODE -ne 0)
    {
        throw "docker $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Invoke-DockerScript
{
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][string]$Script
    )

    # PowerShell may retain CRLF in a here-string. Normalize before piping to
    # the Linux shell so a trailing carriage return cannot become part of a
    # variable value or command argument.
    $normalizedScript = $Script.Replace("`r`n", "`n")
    $normalizedScript | & docker exec -i $ContainerName sh -c "tr -d '\r' | sh -s"
    if ($LASTEXITCODE -ne 0)
    {
        throw "docker exec -i $ContainerName sh -s failed with exit code $LASTEXITCODE."
    }
}

& docker inspect $Container *> $null
if ($LASTEXITCODE -ne 0)
{
    throw "Docker container '$Container' was not found."
}

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Write-Host "Verifying direct-source post-NGE Beast Master player-runtime retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgeBeastMasterPlayerRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying direct-source post-NGE Beast Master creation-runtime retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgeBeastMasterCreationPlayerRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU combat routing closure before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuCombatRoutingClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU profession and Officer runtime authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuProfessionAuthorityClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU zone transition level authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuZoneTransitionLevelAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU dynamic mission difficulty authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuDynamicMissionDifficultyAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU GCW compatibility level authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuGcwCompatibilityLevelAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU metrics level authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuMetricsLevelAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU ground-quest XP authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuGroundquestXpAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU retained-vendor profession authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuRetainedVendorProfessionAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU crafting expertise authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuCraftingExpertiseAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU resource sampling cadence authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuResourceSamplingCadenceAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU player-vendor maintenance authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuPlayerVendorMaintenanceAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU authored healing/buff authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuAuthoredHealingBuffAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU authored movement strength authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuAuthoredMovementStrengthAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU authored armor protection authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuAuthoredArmorProtectionAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU battlefield vehicle armor authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuBattlefieldVehicleArmorAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU retained boss glancing authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuRetainedBossGlancingAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU heroic jewelry weapon-speed authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuHeroicJewelryWeaponSpeedAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU retained reverse/performance authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuRetainedReversePerformanceAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU combat expertise isolation before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuCombatExpertiseIsolation.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU DOT authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuDotAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU Smuggler content expertise authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuSmugglerContentExpertiseAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU Smuggler patrol chance authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuSmugglerPatrolChanceAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU target-dummy defense authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuTargetDummyDefenseAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU TCG barn-display authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuTcgBarnDisplayAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU space reverse-engineering authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuSpaceReverseEngineeringAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU Exar Open Hand healing authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuExarOpenHandHealingAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU Axkva Nandina healing authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuAxkvaNandinaHealingAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source

if (-not $SkipBuild)
{
    $javaDependencyClean = @'
set -eu
class_root="$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/script"
if [ -d "$class_root" ]; then
    find "$class_root" -type f -name '*.class' -delete
    test "$(find "$class_root" -type f -name '*.class' -print -quit)" = ""
fi
'@
    Write-Host "Removing compiled Java classes to enforce a complete dependency rebuild..."
    Invoke-DockerScript -ContainerName $Container -Script $javaDependencyClean
    Write-Host "Synchronizing the read-only source mount and building the writable server volume..."
    Invoke-Docker -Arguments @("exec", $Container, "/usr/local/bin/swg-entrypoint", "build")
}
else
{
    Write-Host "Reusing the existing build volume; all source/build and binary probes remain mandatory..."
}

$artifactProbe = @'
set -eu
source_outdoorsman="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/player/skill/outdoorsman.java"
work_outdoorsman="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/player/skill/outdoorsman.java"
source_corpse="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/corpse.java"
work_corpse="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/corpse.java"
source_create="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/create.java"
work_create="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/create.java"
source_loot="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/loot.java"
work_loot="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/loot.java"
source_creature_profiles="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/mob/precu_creature_combat_profiles.tab"
work_creature_profiles="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/mob/precu_creature_combat_profiles.tab"
source_combat_base="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
work_combat_base="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
source_combat_actions="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
work_combat_actions="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
source_innate="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/innate.java"
work_innate="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/innate.java"
source_species_innate="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/player/species_innate.java"
work_species_innate="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/player/species_innate.java"
source_combat_player="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_player.java"
work_combat_player="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_player.java"
source_ai_corpse="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/corpse/ai_corpse.java"
work_ai_corpse="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/corpse/ai_corpse.java"
source_combat_overrides="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
work_combat_overrides="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
source_weapon_profiles="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_profiles.tab"
work_weapon_profiles="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_profiles.tab"
source_queue="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/command/CommandQueue.cpp"
work_queue="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/command/CommandQueue.cpp"
source_queue_header="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/command/CommandQueue.h"
work_queue_header="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/command/CommandQueue.h"
source_commands="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.cpp"
work_commands="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.cpp"
source_tangible_conversation="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/TangibleObject_Conversation.cpp"
work_tangible_conversation="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/TangibleObject_Conversation.cpp"
source_player_controller="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/controller/PlayerCreatureController.cpp"
work_player_controller="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/controller/PlayerCreatureController.cpp"
source_script_methods_pvp="$SWG_SOURCE_DIR/src/engine/server/library/serverScript/src/shared/ScriptMethodsPvp.cpp"
work_script_methods_pvp="$SWG_WORK_DIR/src/engine/server/library/serverScript/src/shared/ScriptMethodsPvp.cpp"
source_client="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/core/Client.cpp"
work_client="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/core/Client.cpp"
source_creature="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
work_creature="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
source_creature_header="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/CreatureObject.h"
work_creature_header="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/CreatureObject.h"
source_group="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/GroupObject.cpp"
work_group="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/GroupObject.cpp"
source_player="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/PlayerObject.cpp"
work_player="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/PlayerObject.cpp"
source_player_header="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/PlayerObject.h"
work_player_header="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/PlayerObject.h"
source_weapon="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/WeaponObject.cpp"
work_weapon="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/WeaponObject.cpp"
source_weapon_header="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/WeaponObject.h"
work_weapon_header="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/WeaponObject.h"
source_speeds="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_speeds.tab"
work_speeds="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_speeds.tab"
source_travel="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/travel.java"
work_travel="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/library/travel.java"
source_player_travel="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/player/player_travel.java"
work_player_travel="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/player/player_travel.java"
source_command_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
work_command_table="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
source_skills="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
work_skills="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
source_buff_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
work_buff_table="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
source_combat_data="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
work_combat_data="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
source_npc_combat_dir="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/combat"
work_npc_combat_dir="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/combat"
source_conversation="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script/conversation"
work_conversation="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script/conversation"
source_script="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/script"
work_script="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/script"
source_theme_park="$source_script/theme_park"
work_theme_park="$work_script/theme_park"
source_base_class="$source_script/base_class.java"
work_base_class="$work_script/base_class.java"
source_missions="$source_script/library/missions.java"
work_missions="$work_script/library/missions.java"
source_xp_library="$source_script/library/xp.java"
work_xp_library="$work_script/library/xp.java"
source_metrics_library="$source_script/library/metrics.java"
work_metrics_library="$work_script/library/metrics.java"
source_groundquests_library="$source_script/library/groundquests.java"
work_groundquests_library="$work_script/library/groundquests.java"
source_factions_library="$source_script/library/factions.java"
work_factions_library="$work_script/library/factions.java"
source_faction_perk_library="$source_script/library/faction_perk.java"
work_faction_perk_library="$work_script/library/faction_perk.java"
source_jedi_saber_component="$source_script/systems/jedi/jedi_saber_component.java"
work_jedi_saber_component="$work_script/systems/jedi/jedi_saber_component.java"
source_gcw_library="$source_script/library/gcw.java"
work_gcw_library="$work_script/library/gcw.java"
source_gcw_city="$source_script/systems/gcw/gcw_city.java"
work_gcw_city="$work_script/systems/gcw/gcw_city.java"
source_planet_base="$source_script/planet/planet_base.java"
work_planet_base="$work_script/planet/planet_base.java"
source_live_conversions="$source_script/player/live_conversions.java"
work_live_conversions="$work_script/player/live_conversions.java"
source_cureward="$source_script/cureward/cureward.java"
work_cureward="$work_script/cureward/cureward.java"
source_open_world_battlefield="$source_script/library/battlefield.java"
work_open_world_battlefield="$work_script/library/battlefield.java"
source_trap_base="$source_script/item/trap/trap_base.java"
work_trap_base="$work_script/item/trap/trap_base.java"
source_battlefield_controller="$source_script/systems/gcw/pvp_battlefield.java"
work_battlefield_controller="$work_script/systems/gcw/pvp_battlefield.java"
source_battlefield_terminal="$source_script/systems/gcw/battlefield_terminal.java"
work_battlefield_terminal="$work_script/systems/gcw/battlefield_terminal.java"
source_battlefield_player="$source_script/systems/gcw/player_pvp.java"
work_battlefield_player="$work_script/systems/gcw/player_pvp.java"
source_player_faction="$source_script/player/player_faction.java"
work_player_faction="$work_script/player/player_faction.java"
source_static_master="$source_script/systems/gcw/static_base/master.java"
work_static_master="$work_script/systems/gcw/static_base/master.java"
source_static_base_master="$source_script/systems/gcw/static_base/base_master.java"
work_static_base_master="$work_script/systems/gcw/static_base/base_master.java"
source_static_base_spawner="$source_script/systems/gcw/static_base/base_spawner.java"
work_static_base_spawner="$work_script/systems/gcw/static_base/base_spawner.java"
source_static_spawned_object="$source_script/systems/gcw/static_base/spawned_object.java"
work_static_spawned_object="$work_script/systems/gcw/static_base/spawned_object.java"
source_static_control_terminal="$source_script/systems/gcw/static_base/control_terminal.java"
work_static_control_terminal="$work_script/systems/gcw/static_base/control_terminal.java"
source_static_control_terminal_player="$source_script/systems/gcw/static_base/control_terminal_player.java"
work_static_control_terminal_player="$work_script/systems/gcw/static_base/control_terminal_player.java"
source_hq_objective_override="$source_script/faction_perk/hq/objective_terminal_override.java"
work_hq_objective_override="$work_script/faction_perk/hq/objective_terminal_override.java"
source_hq_objective_power="$source_script/faction_perk/hq/objective_power_regulator.java"
work_hq_objective_power="$work_script/faction_perk/hq/objective_power_regulator.java"
source_hq_objective_security="$source_script/faction_perk/hq/objective_terminal_security.java"
work_hq_objective_security="$work_script/faction_perk/hq/objective_terminal_security.java"
source_hq_objective_uplink="$source_script/faction_perk/hq/objective_terminal_uplink.java"
work_hq_objective_uplink="$work_script/faction_perk/hq/objective_terminal_uplink.java"
source_hq_terminal="$source_script/faction_perk/hq/terminal.java"
work_hq_terminal="$work_script/faction_perk/hq/terminal.java"
source_municipal_starport="$source_script/structure/municipal/starport.java"
work_municipal_starport="$work_script/structure/municipal/starport.java"
source_municipal_cloner="$source_script/structure/municipal/cloning_facility.java"
work_municipal_cloner="$work_script/structure/municipal/cloning_facility.java"
source_collection_consume_click="$source_script/systems/collections/consume_click.java"
work_collection_consume_click="$work_script/systems/collections/consume_click.java"
source_city_buildout_bestine="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/tatooine/tatooine_4_3.tab"
work_city_buildout_bestine="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/tatooine/tatooine_4_3.tab"
source_city_buildout_dearic="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_5_3.tab"
work_city_buildout_dearic="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_5_3.tab"
source_city_buildout_keren="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/naboo/naboo_5_6.tab"
work_city_buildout_keren="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/naboo/naboo_5_6.tab"
source_battlefield_buildout_endor_1_1="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/endor/endor_1_1.tab"
work_battlefield_buildout_endor_1_1="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/endor/endor_1_1.tab"
source_battlefield_buildout_endor_1_8="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/endor/endor_1_8.tab"
work_battlefield_buildout_endor_1_8="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/endor/endor_1_8.tab"
source_battlefield_buildout_yavin4_3_1="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/yavin4/yavin4_3_1.tab"
work_battlefield_buildout_yavin4_3_1="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/yavin4/yavin4_3_1.tab"
source_battlefield_buildout_yavin4_5_5="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/yavin4/yavin4_5_5.tab"
work_battlefield_buildout_yavin4_5_5="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/yavin4/yavin4_5_5.tab"
source_static_buildout_corellia="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/corellia/corellia_7_2.tab"
work_static_buildout_corellia="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/corellia/corellia_7_2.tab"
source_static_buildout_talus="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_2_3.tab"
work_static_buildout_talus="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_2_3.tab"
source_static_buildout_naboo="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/naboo/naboo_5_4.tab"
work_static_buildout_naboo="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/naboo/naboo_5_4.tab"
source_faction_recruiter="$source_script/npc/faction_recruiter/faction_recruiter.java"
work_faction_recruiter="$work_script/npc/faction_recruiter/faction_recruiter.java"
source_camp_controlpanel="$source_script/systems/camping/camp_controlpanel.java"
work_camp_controlpanel="$work_script/systems/camping/camp_controlpanel.java"
source_pclib_library="$source_script/library/pclib.java"
work_pclib_library="$work_script/library/pclib.java"
source_group_library="$source_script/library/group.java"
work_group_library="$work_script/library/group.java"
source_skill_library="$source_script/library/skill.java"
work_skill_library="$work_script/library/skill.java"
source_transition_library="$source_script/library/transition.java"
work_transition_library="$work_script/library/transition.java"
source_zone_transition_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/travel/zone_transition.tab"
work_zone_transition_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/travel/zone_transition.tab"
source_utils_library="$source_script/library/utils.java"
work_utils_library="$work_script/library/utils.java"
source_vendor="$source_script/npc/vendor/vendor.java"
work_vendor="$work_script/npc/vendor/vendor.java"
source_meatlump_vendor="$source_script/theme_park/meatlump/mtp_vendor.java"
work_meatlump_vendor="$work_script/theme_park/meatlump/mtp_vendor.java"
source_nova_orion_vendor="$source_script/theme_park/dungeon/nova_orion_station/nova_orion_vendor.java"
work_nova_orion_vendor="$work_script/theme_park/dungeon/nova_orion_station/nova_orion_vendor.java"
source_stealth_library="$source_script/library/stealth.java"
work_stealth_library="$work_script/library/stealth.java"
source_luck_library="$source_script/library/luck.java"
work_luck_library="$work_script/library/luck.java"
source_crafting_library="$source_script/library/craftinglib.java"
work_crafting_library="$work_script/library/craftinglib.java"
source_resource_library="$source_script/library/resource.java"
work_resource_library="$work_script/library/resource.java"
source_player_structure_library="$source_script/library/player_structure.java"
work_player_structure_library="$work_script/library/player_structure.java"
source_crafting_base="$source_script/systems/crafting/crafting_base.java"
work_crafting_base="$work_script/systems/crafting/crafting_base.java"
source_cybernetic_crafting="$source_script/systems/crafting/armor/crafting_new_cybernetics_final.java"
work_cybernetic_crafting="$work_script/systems/crafting/armor/crafting_new_cybernetics_final.java"
source_survey_tool="$source_script/item/survey_tool/survey_tool_script.java"
work_survey_tool="$work_script/item/survey_tool/survey_tool_script.java"
source_player_vendor="$source_script/terminal/vendor.java"
work_player_vendor="$work_script/terminal/vendor.java"
source_combat_library="$source_script/library/combat.java"
work_combat_library="$work_script/library/combat.java"
source_reverse_engineering_library="$source_script/library/reverse_engineering.java"
work_reverse_engineering_library="$work_script/library/reverse_engineering.java"
source_skill_mod_listing="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/expertise/skill_mod_listing.tab"
work_skill_mod_listing="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/expertise/skill_mod_listing.tab"
source_healing_library="$source_script/library/healing.java"
work_healing_library="$work_script/library/healing.java"
source_dot_library="$source_script/library/dot.java"
work_dot_library="$work_script/library/dot.java"
source_smuggler_library="$source_script/library/smuggler.java"
work_smuggler_library="$work_script/library/smuggler.java"
source_junk_dealer_summon="$source_script/npc/junk_dealer/junk_dealer_summon.java"
work_junk_dealer_summon="$work_script/npc/junk_dealer/junk_dealer_summon.java"
source_smuggler_patrol_ai="$source_script/ai/smuggler_spawn_enemy.java"
work_smuggler_patrol_ai="$work_script/ai/smuggler_spawn_enemy.java"
source_target_dummy_library="$source_script/library/target_dummy.java"
work_target_dummy_library="$work_script/library/target_dummy.java"
source_target_simulator="$source_script/systems/tcg/target_creature.java"
work_target_simulator="$work_script/systems/tcg/target_creature.java"
source_tcg_library="$source_script/library/tcg.java"
work_tcg_library="$work_script/library/tcg.java"
source_barn_ranchhand="$source_script/systems/tcg/barn_ranchhand.java"
work_barn_ranchhand="$work_script/systems/tcg/barn_ranchhand.java"
source_barn_lite_device="$source_script/systems/tcg/barn_lite_device.java"
work_barn_lite_device="$work_script/systems/tcg/barn_lite_device.java"
source_barn_beast="$source_script/systems/tcg/barn_beast.java"
work_barn_beast="$work_script/systems/tcg/barn_beast.java"
source_space_analysis_tool="$source_script/space/crafting/analysis_tool.java"
work_space_analysis_tool="$work_script/space/crafting/analysis_tool.java"
source_space_analysis_template="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/object/tangible/ship/crafted/reverse_engineering/analysis_tool.tpf"
work_space_analysis_template="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/object/tangible/ship/crafted/reverse_engineering/analysis_tool.tpf"
source_space_armor_analysis_template="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/object/tangible/ship/crafted/reverse_engineering/armor_analysis_tool.tpf"
work_space_armor_analysis_template="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/object/tangible/ship/crafted/reverse_engineering/armor_analysis_tool.tpf"
source_reverse_loot_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/space_loot/reverse_engineering/reverse_loot.tab"
work_reverse_loot_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/space_loot/reverse_engineering/reverse_loot.tab"
source_reverse_loot_lookup_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/space_loot/reverse_engineering/reverse_loot_lookup.tab"
work_reverse_loot_lookup_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/space_loot/reverse_engineering/reverse_loot_lookup.tab"
source_exar_open_hand="$source_script/theme_park/heroic/exar_kun/open_hand.java"
work_exar_open_hand="$work_script/theme_park/heroic/exar_kun/open_hand.java"
source_exar_spawn_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/spawning/heroic/heroic_exar_kun.tab"
work_exar_spawn_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/spawning/heroic/heroic_exar_kun.tab"
source_creatures_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/mob/creatures.tab"
work_creatures_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/mob/creatures.tab"
source_exar_open_hand_template="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/object/mobile/exar_kun_open_hand.tpf"
work_exar_open_hand_template="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/object/mobile/exar_kun_open_hand.tpf"
source_ai_combat_profiles="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/ai/ai_combat_profiles.tab"
work_ai_combat_profiles="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/ai/ai_combat_profiles.tab"
source_axkva_spawn_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/spawning/heroic/heroic_axkva_min.tab"
work_axkva_spawn_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/spawning/heroic/heroic_axkva_min.tab"
source_movement_library="$source_script/library/movement.java"
work_movement_library="$work_script/library/movement.java"
source_movement_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/movement/movement.tab"
work_movement_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/movement/movement.tab"
source_armor_library="$source_script/library/armor.java"
work_armor_library="$work_script/library/armor.java"
source_battlefield_vehicle="$source_script/systems/vehicle_system/battlefield_vehicle.java"
work_battlefield_vehicle="$work_script/systems/vehicle_system/battlefield_vehicle.java"
source_battlefield_vehicle_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/vehicle/battlefield_vehicle.tab"
work_battlefield_vehicle_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/vehicle/battlefield_vehicle.tab"
source_echo_base_spawns="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/spawning/heroic/echo_base.tab"
work_echo_base_spawns="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/spawning/heroic/echo_base.tab"
source_vehicle_mine="$source_script/theme_park/heroic/echo_base/vehicle_mine.java"
work_vehicle_mine="$work_script/theme_park/heroic/echo_base/vehicle_mine.java"
source_wampa_boss="$source_script/theme_park/heroic/echo_base/wampa_boss.java"
work_wampa_boss="$work_script/theme_park/heroic/echo_base/wampa_boss.java"
source_outbreak_boss="$source_script/theme_park/outbreak/boss_fight_functionality.java"
work_outbreak_boss="$work_script/theme_park/outbreak/boss_fight_functionality.java"
source_outbreak_buildout="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/dathomir/dathomir_1_1.tab"
work_outbreak_buildout="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/dathomir/dathomir_1_1.tab"
source_heroic_random_stat_item="$source_script/item/heroic_random_stat_item.java"
work_heroic_random_stat_item="$work_script/item/heroic_random_stat_item.java"
source_master_item_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/master_item.tab"
work_master_item_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/master_item.tab"
source_heroic_drops="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/loot/loot_items/dungeon/heroic_drops.tab"
work_heroic_drops="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/loot/loot_items/dungeon/heroic_drops.tab"
source_reverse_engineering_tool="$source_script/item/tool/reverse_engineering_tool.java"
work_reverse_engineering_tool="$work_script/item/tool/reverse_engineering_tool.java"
source_performance_library="$source_script/library/performance.java"
work_performance_library="$work_script/library/performance.java"
source_skills_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
work_skills_table="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
source_schematic_group_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/crafting/schematic_group.tab"
work_schematic_group_table="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/crafting/schematic_group.tab"
source_weapons_library="$source_script/library/weapons.java"
work_weapons_library="$work_script/library/weapons.java"
source_combat_weapon="$source_script/systems/combat/combat_weapon.java"
work_combat_weapon="$work_script/systems/combat/combat_weapon.java"
source_mission_base="$source_script/systems/missions/base/mission_base.java"
work_mission_base="$work_script/systems/missions/base/mission_base.java"
source_mission_dynamic="$source_script/systems/missions/base/mission_dynamic_base.java"
work_mission_dynamic="$work_script/systems/missions/base/mission_dynamic_base.java"
source_mission_escort="$source_script/systems/missions/dynamic/mission_escort_npc.java"
work_mission_escort="$work_script/systems/missions/dynamic/mission_escort_npc.java"
source_player_utility="$source_script/player/player_utility.java"
work_player_utility="$work_script/player/player_utility.java"
source_ai="$source_script/ai/ai.java"
work_ai="$work_script/ai/ai.java"
source_base_player="$source_script/player/base/base_player.java"
work_base_player="$work_script/player/base/base_player.java"
source_buff_library="$source_script/library/buff.java"
work_buff_library="$work_script/library/buff.java"
source_performcommands="$source_script/player/skill/performcommands.java"
work_performcommands="$work_script/player/skill/performcommands.java"
source_buff_handler="$source_script/systems/buff/buff_handler.java"
work_buff_handler="$work_script/systems/buff/buff_handler.java"
source_player_stealth="$source_script/systems/skills/stealth/player_stealth.java"
work_player_stealth="$work_script/systems/skills/stealth/player_stealth.java"
source_beast_library="$source_script/library/beast_lib.java"
work_beast_library="$work_script/library/beast_lib.java"
source_beast_control_device="$source_script/ai/beast_control_device.java"
work_beast_control_device="$work_script/ai/beast_control_device.java"
source_player_beastmaster="$source_script/player/player_beastmaster.java"
work_player_beastmaster="$work_script/player/player_beastmaster.java"
source_buff_builder_cancel="$source_script/systems/buff_builder/buff_builder_cancel.java"
work_buff_builder_cancel="$work_script/systems/buff_builder/buff_builder_cancel.java"
source_buff_builder_response="$source_script/systems/buff_builder/buff_builder_response.java"
work_buff_builder_response="$work_script/systems/buff_builder/buff_builder_response.java"
source_crafting_base="$source_script/systems/crafting/crafting_base.java"
work_crafting_base="$work_script/systems/crafting/crafting_base.java"
precu_item_level_paths="item/buff_beast_click_item.java item/buff_click_item.java item/full_heal_item.java item/levelup_orb/levelup_orb.java item/medicine/stimpack.java item/medicine/stimpack_crafted.java item/plant/force_melon.java item/skillmod_click_item.java item/static_item_base.java item/survey_tool/survey_tool_script.java library/static_item.java"
precu_encounter_difficulty_paths="ai/ai.java quest/task/ground/spawn.java quest/util/dynamic_mob_opponent.java quest/utility/dynamic_spawn_off_quest_item.java systems/spawning/spawn_base.java systems/tcg/target_creature.java systems/treasure_map/base/treasure_map.java theme_park/meatlump/hideout/mtp_instance_entrance_cell.java theme_park/meatlump/quest_shuttle_comlink.java theme_park/outbreak/dynamic_spawn_off_quest_item.java"
precu_retained_system_level_paths="ai/imperial_presence/harass.java city/imperial_crackdown/imperial_trouble.java event/ewok_festival/loveday_reward_crossbow.java event/halloween/song_book.java event/lost_squadron/stolen_fighter.java library/collection.java library/groundquests.java library/npe.java library/performance.java library/smuggler.java library/space_combat.java library/township.java npc/static_quest/quest_convo.java"
precu_cosmetic_familiar_paths="ai/familiar.java"
precu_droid_detonation_paths="ai/pet.java ai/pet_control_device.java library/pet_lib.java npc/pet_deed/droid_deed.java systems/crafting/droid/modules/droid_bomb.java"
post_nge_beast_creation_paths="ai/pet_control_device.java library/beast_lib.java library/incubator.java npc/pet_deed/pet_deed.java player/base/base_player.java player/player_utility.java systems/beast/base_incubator.java systems/beast/beast_dye.java systems/beast/beast_egg.java systems/beast/beast_food.java systems/beast/beast_steroid_injector.java systems/beast/decoration_item.java systems/beast/enzyme_crafting_base.java systems/beast/enzyme_crafting_centrifuge.java systems/beast/enzyme_crafting_combiner.java systems/beast/enzyme_crafting_processor.java systems/beast/enzyme_extractor.java"
post_nge_beast_runtime_paths="ai/beast.java ai/beast_control_device.java ai/creature_combat.java conversation/trainer_beast_master.java library/beast_lib.java player/base/base_player.java player/live_conversions.java player/player_beastmaster.java systems/combat/combat_actions.java systems/combat/combat_base.java"
post_nge_officer_runtime_paths="ai/officer_pet.java systems/combat/combat_base.java systems/combat/combat_actions.java systems/combat/combat_supply_drop_controller.java systems/combat/combat_supply_drop_crate.java"
source_local_options="$SWG_SOURCE_DIR/exe/linux/localOptions.cfg"
work_local_options="$SWG_WORK_DIR/exe/linux/localOptions.cfg"
class_root="$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game"
binary="$SWG_WORK_DIR/build/bin/SwgGameServer"
server_game_archive="$SWG_WORK_DIR/build/engine/server/library/serverGame/src/libserverGame.a"

cmp -s "$source_outdoorsman" "$work_outdoorsman"
cmp -s "$source_corpse" "$work_corpse"
cmp -s "$source_create" "$work_create"
cmp -s "$source_loot" "$work_loot"
cmp -s "$source_creature_profiles" "$work_creature_profiles"
cmp -s "$source_combat_base" "$work_combat_base"
cmp -s "$source_combat_actions" "$work_combat_actions"
cmp -s "$source_innate" "$work_innate"
cmp -s "$source_species_innate" "$work_species_innate"
cmp -s "$source_combat_player" "$work_combat_player"
cmp -s "$source_ai_corpse" "$work_ai_corpse"
cmp -s "$source_combat_overrides" "$work_combat_overrides"
cmp -s "$source_weapon_profiles" "$work_weapon_profiles"
cmp -s "$source_queue" "$work_queue"
cmp -s "$source_queue_header" "$work_queue_header"
cmp -s "$source_commands" "$work_commands"
cmp -s "$source_tangible_conversation" "$work_tangible_conversation"
cmp -s "$source_player_controller" "$work_player_controller"
cmp -s "$source_script_methods_pvp" "$work_script_methods_pvp"
cmp -s "$source_client" "$work_client"
cmp -s "$source_creature" "$work_creature"
cmp -s "$source_creature_header" "$work_creature_header"
cmp -s "$source_group" "$work_group"
cmp -s "$source_player" "$work_player"
cmp -s "$source_player_header" "$work_player_header"
cmp -s "$source_weapon" "$work_weapon"
cmp -s "$source_weapon_header" "$work_weapon_header"
cmp -s "$source_speeds" "$work_speeds"
cmp -s "$source_travel" "$work_travel"
cmp -s "$source_player_travel" "$work_player_travel"
cmp -s "$source_command_table" "$work_command_table"
cmp -s "$source_skills" "$work_skills"
cmp -s "$source_buff_table" "$work_buff_table"
cmp -s "$source_combat_data" "$work_combat_data"
source_npc_tables="$(find "$source_npc_combat_dir" -maxdepth 1 -type f -name 'npc_*.tab' -printf '%f\n' | sort)"
work_npc_tables="$(find "$work_npc_combat_dir" -maxdepth 1 -type f -name 'npc_*.tab' -printf '%f\n' | sort)"
test "$source_npc_tables" = "$work_npc_tables"
test "$(printf '%s\n' "$source_npc_tables" | sed '/^$/d' | wc -l)" -eq 14
for npc_table_name in $source_npc_tables; do
    cmp -s "$source_npc_combat_dir/$npc_table_name" "$work_npc_combat_dir/$npc_table_name"
done
cmp -s "$source_missions" "$work_missions"
cmp -s "$source_xp_library" "$work_xp_library"
cmp -s "$source_metrics_library" "$work_metrics_library"
! grep -E -q '(^|[^[:alnum:]_.])getLevel[[:space:]]*\([[:space:]]*(member|killCredit|player)[[:space:]]*\)' "$work_metrics_library"
test "$(grep -E -o 'skill\.getPrecuEncounterDifficulty[[:space:]]*\([[:space:]]*(member|killCredit|player)[[:space:]]*\)' "$work_metrics_library" | wc -l)" -eq 4
test "$(grep -E -o '(^|[^[:alnum:]_.])getLevel[[:space:]]*\([[:space:]]*target[[:space:]]*\)' "$work_metrics_library" | wc -l)" -eq 1
cmp -s "$source_groundquests_library" "$work_groundquests_library"
grep -Fq 'datatables/quest/quest_experience.iff' "$work_groundquests_library"
! grep -Fq 'datatables/player/player_level.iff' "$work_groundquests_library"
! grep -Fq 'getQuestXpCap' "$work_groundquests_library"
grep -Fq 'xp.grantCombatStyleXp(player, experienceType, experienceAmount)' "$work_groundquests_library"
grep -Fq 'xp.grantCraftingQuestXp(player, experienceAmount)' "$work_groundquests_library"
grep -Fq 'xp.grantSocialStyleXp(player, experienceType, experienceAmount)' "$work_groundquests_library"
grep -Fq 'xp.grantUnmodifiedExperience(player, experienceType, experienceAmount, false)' "$work_groundquests_library"
cmp -s "$source_factions_library" "$work_factions_library"
cmp -s "$source_faction_perk_library" "$work_faction_perk_library"
cmp -s "$source_jedi_saber_component" "$work_jedi_saber_component"
cmp -s "$source_gcw_library" "$work_gcw_library"
! grep -E -q '(^|[^[:alnum:]_.])getLevel[[:space:]]*\([[:space:]]*(player|killer|obj_id)[[:space:]]*\)' "$work_gcw_library"
test "$(grep -E -o 'skill\.getPrecuEncounterDifficulty[[:space:]]*\([[:space:]]*(player|killer|obj_id)[[:space:]]*\)' "$work_gcw_library" | wc -l)" -eq 7
test "$(grep -E -o '(^|[^[:alnum:]_.])getLevel[[:space:]]*\([[:space:]]*npc[[:space:]]*\)' "$work_gcw_library" | wc -l)" -eq 1
cmp -s "$source_gcw_city" "$work_gcw_city"
cmp -s "$source_planet_base" "$work_planet_base"
cmp -s "$source_live_conversions" "$work_live_conversions"
cmp -s "$source_cureward" "$work_cureward"
cmp -s "$source_open_world_battlefield" "$work_open_world_battlefield"
cmp -s "$source_trap_base" "$work_trap_base"
cmp -s "$source_battlefield_controller" "$work_battlefield_controller"
cmp -s "$source_battlefield_terminal" "$work_battlefield_terminal"
cmp -s "$source_battlefield_player" "$work_battlefield_player"
cmp -s "$source_player_faction" "$work_player_faction"
cmp -s "$source_static_master" "$work_static_master"
cmp -s "$source_static_base_master" "$work_static_base_master"
cmp -s "$source_static_base_spawner" "$work_static_base_spawner"
cmp -s "$source_static_spawned_object" "$work_static_spawned_object"
cmp -s "$source_static_control_terminal" "$work_static_control_terminal"
cmp -s "$source_static_control_terminal_player" "$work_static_control_terminal_player"
cmp -s "$source_hq_objective_override" "$work_hq_objective_override"
cmp -s "$source_hq_objective_power" "$work_hq_objective_power"
cmp -s "$source_hq_objective_security" "$work_hq_objective_security"
cmp -s "$source_hq_objective_uplink" "$work_hq_objective_uplink"
cmp -s "$source_hq_terminal" "$work_hq_terminal"
! grep -Eq 'class_(medic|commando|smuggler|bountyhunter|officer)_phase[0-9]+_novice' \
    "$work_hq_objective_override" "$work_hq_objective_power" "$work_hq_objective_security" \
    "$work_hq_objective_uplink" "$work_hq_terminal"
cmp -s "$source_municipal_starport" "$work_municipal_starport"
cmp -s "$source_municipal_cloner" "$work_municipal_cloner"
cmp -s "$source_collection_consume_click" "$work_collection_consume_click"
cmp -s "$source_city_buildout_bestine" "$work_city_buildout_bestine"
cmp -s "$source_city_buildout_dearic" "$work_city_buildout_dearic"
cmp -s "$source_city_buildout_keren" "$work_city_buildout_keren"
cmp -s "$source_battlefield_buildout_endor_1_1" "$work_battlefield_buildout_endor_1_1"
cmp -s "$source_battlefield_buildout_endor_1_8" "$work_battlefield_buildout_endor_1_8"
cmp -s "$source_battlefield_buildout_yavin4_3_1" "$work_battlefield_buildout_yavin4_3_1"
cmp -s "$source_battlefield_buildout_yavin4_5_5" "$work_battlefield_buildout_yavin4_5_5"
cmp -s "$source_static_buildout_corellia" "$work_static_buildout_corellia"
cmp -s "$source_static_buildout_talus" "$work_static_buildout_talus"
cmp -s "$source_static_buildout_naboo" "$work_static_buildout_naboo"
cmp -s "$source_faction_recruiter" "$work_faction_recruiter"
cmp -s "$source_camp_controlpanel" "$work_camp_controlpanel"
cmp -s "$source_pclib_library" "$work_pclib_library"
cmp -s "$source_group_library" "$work_group_library"
cmp -s "$source_skill_library" "$work_skill_library"
cmp -s "$source_transition_library" "$work_transition_library"
cmp -s "$source_zone_transition_table" "$work_zone_transition_table"
cmp -s "$source_utils_library" "$work_utils_library"
cmp -s "$source_vendor" "$work_vendor"
cmp -s "$source_meatlump_vendor" "$work_meatlump_vendor"
cmp -s "$source_nova_orion_vendor" "$work_nova_orion_vendor"
grep -Fq 'public static final int NO_PROFESSION = 0;' "$work_utils_library"
grep -Fq 'if (isProfession(player, TRADER))' "$work_utils_library"
grep -Fq 'return NO_PROFESSION;' "$work_utils_library"
! grep -Fq 'getPlayerProfession(' "$work_vendor"
grep -Fq 'getQualifiedPrecuProfessionInventories' "$work_vendor"
grep -Fq 'handlePrecuProfessionInventorySelect' "$work_vendor"
grep -Fq 'utils.isPrecuRetainedItemClass(player, profession)' "$work_vendor"
! grep -Fq 'getPlayerProfession(' "$work_meatlump_vendor"
! grep -Fq 'getPlayerProfession(' "$work_nova_orion_vendor"
cmp -s "$source_stealth_library" "$work_stealth_library"
cmp -s "$source_luck_library" "$work_luck_library"
cmp -s "$source_crafting_library" "$work_crafting_library"
cmp -s "$source_resource_library" "$work_resource_library"
cmp -s "$source_player_structure_library" "$work_player_structure_library"
cmp -s "$source_crafting_base" "$work_crafting_base"
cmp -s "$source_cybernetic_crafting" "$work_cybernetic_crafting"
! grep -Fq '"expertise_resource_quality_increase"' "$work_crafting_library"
! grep -Fq '"expertise_experimentation_increase_' "$work_crafting_library"
! grep -Fq '"expertise_resource_sampling_increase"' "$work_resource_library"
! grep -Fq '"expertise_complexity_decrease_' "$work_crafting_base"
! grep -Fq '"expertise_' "$work_player_structure_library"
! grep -Fq '"expertise_cybernetic_negative_effects_reduction"' "$work_cybernetic_crafting"
grep -Fq 'removeObjVar(structure, VAR_POWER_MOD_FACTORY)' "$work_player_structure_library"
grep -Fq 'removeObjVar(structure, VAR_POWER_MOD_HARVESTER)' "$work_player_structure_library"
grep -Fq 'float reductionAmount = 1.0f - 0.4f;' "$work_cybernetic_crafting"
cmp -s "$source_survey_tool" "$work_survey_tool"
grep -Fq 'public static final int SURVEY_TOOL_DELAY = 25;' "$work_survey_tool"
! grep -Fq 'MIN_SURVEY_TOOL_DELAY' "$work_survey_tool"
! grep -Fq 'expertise_resource_sampling_time_decrease' "$work_survey_tool"
cmp -s "$source_player_vendor" "$work_player_vendor"
! grep -Fq 'expertise_vendor_cost_decrease' "$work_player_vendor"
! grep -Fq 'utils.isProfession(owner, utils.TRADER)' "$work_player_vendor"
! grep -Fq 'utils.isProfession(ownerId, utils.TRADER)' "$work_player_vendor"
grep -Fq 'hasSkill(owner, "crafting_merchant_master")' "$work_player_vendor"
grep -Fq 'hasSkill(owner, "crafting_merchant_sales_02")' "$work_player_vendor"
grep -Fq 'cost += 6 * loops;' "$work_player_vendor"
grep -Fq 'cost += 6;' "$work_player_vendor"
cmp -s "$source_combat_library" "$work_combat_library"
cmp -s "$source_reverse_engineering_library" "$work_reverse_engineering_library"
cmp -s "$source_skill_mod_listing" "$work_skill_mod_listing"
cmp -s "$source_healing_library" "$work_healing_library"
cmp -s "$source_dot_library" "$work_dot_library"
cmp -s "$source_smuggler_library" "$work_smuggler_library"
! grep -Fq 'expertise_' "$work_smuggler_library"
! grep -Fq 'sm_feeling_lucky' "$work_smuggler_library"
! grep -Fq 'ACCT_RELIC_DEALER' "$work_smuggler_library"
grep -Fq 'money.ACCT_JUNK_DEALER' "$work_smuggler_library"
grep -Fq 'int chance = (12 - tier * 2);' "$work_smuggler_library"
grep -Fq 'int chance = (12 - (dropTier * 2));' "$work_smuggler_library"
cmp -s "$source_junk_dealer_summon" "$work_junk_dealer_summon"
! grep -Fq 'expertise_' "$work_junk_dealer_summon"
! grep -Fq 'sm_junk_dealer_' "$work_junk_dealer_summon"
! grep -Fq 'buffParty' "$work_junk_dealer_summon"
! grep -Fq 'buff.applyBuff' "$work_junk_dealer_summon"
grep -Fq 'messageTo(self, "timeUp", null, 300, true);' "$work_junk_dealer_summon"
grep -Fq 'messageTo(self, "handleGreeting", null, 2.0f, false);' "$work_junk_dealer_summon"
grep -Fq 'new string_id("spam", "junk_dealer_total_profits")' "$work_junk_dealer_summon"
grep -Fq 'detachScript(self, "conversation.junk_dealer_smuggler")' "$work_junk_dealer_summon"
grep -Fq 'detachScript(self, "npc.converse.junk_dealer")' "$work_junk_dealer_summon"
cmp -s "$source_smuggler_patrol_ai" "$work_smuggler_patrol_ai"
! grep -Fq 'expertise_' "$work_smuggler_patrol_ai"
! grep -Fq 'getSmugglerRank' "$work_smuggler_patrol_ai"
! grep -Fq 'getFactionStanding' "$work_smuggler_patrol_ai"
grep -Fq 'public static final int CONTRABAND_BASE_PASS_CHANCE = 5;' "$work_smuggler_patrol_ai"
grep -Fq 'public static final int SLY_LIE_BASE_BONUS = 10;' "$work_smuggler_patrol_ai"
grep -Fq 'public static final int FAST_TALK_BASE_CHANCE = 25;' "$work_smuggler_patrol_ai"
grep -Fq 'int passChance = CONTRABAND_BASE_PASS_CHANCE;' "$work_smuggler_patrol_ai"
grep -Fq 'passChance += SLY_LIE_BASE_BONUS;' "$work_smuggler_patrol_ai"
grep -Fq 'if (rand(1, 100) > passChance)' "$work_smuggler_patrol_ai"
grep -Fq 'if (roll > FAST_TALK_BASE_CHANCE)' "$work_smuggler_patrol_ai"
cmp -s "$source_target_dummy_library" "$work_target_dummy_library"
cmp -s "$source_target_simulator" "$work_target_simulator"
! grep -Fq 'expertise_' "$work_target_dummy_library"
! grep -Fq 'armor.recalculateArmorForMob' "$work_target_dummy_library"
grep -Fq '"precu_armor_rating"' "$work_target_dummy_library"
grep -Fq '"precu_armor_lightsaber"' "$work_target_dummy_library"
grep -Fq '"ranged_defense"' "$work_target_dummy_library"
grep -Fq '"melee_defense"' "$work_target_dummy_library"
grep -Fq '"unarmed_passive_defense"' "$work_target_dummy_library"
grep -Fq 'applyPersistedTargetDummyDefenses(targetDummy)' "$work_target_dummy_library"
grep -Fq 'setObjVar(targetDummy, "precu.armor.rating", value)' "$work_target_dummy_library"
grep -Fq 'getPrecuTargetDummyArmorObjVar(defenseName)' "$work_target_dummy_library"
grep -Fq 'Enter a whole-number PRE-CU defense value.' "$work_target_simulator"
cmp -s "$source_tcg_library" "$work_tcg_library"
cmp -s "$source_barn_ranchhand" "$work_barn_ranchhand"
cmp -s "$source_barn_lite_device" "$work_barn_lite_device"
cmp -s "$source_barn_beast" "$work_barn_beast"
! grep -Fq 'expertise_' "$work_tcg_library"
! grep -Fq 'getExpertiseStat' "$work_tcg_library"
! grep -Fq 'getExpertiseSpeed' "$work_tcg_library"
! grep -Fq 'ATTENTION_PENALTY_DEBUFF' "$work_tcg_library"
! grep -Fq 'buff.applyBuff' "$work_tcg_library"
grep -Fq 'float primarySpeed = beast_lib.BEAST_WEAPON_SPEED;' "$work_tcg_library"
grep -Fq 'int healthRegen = beastStatsDict.getInt("HealthRegen");' "$work_tcg_library"
grep -Fq 'int actionRegen = beastStatsDict.getInt("ActionRegen");' "$work_tcg_library"
grep -Fq 'int intArmor = (int)(beastStatsDict.getInt("Armor")' "$work_tcg_library"
grep -Fq 'setInvulnerable(beast, true);' "$work_tcg_library"
grep -Fq 'tcg.barnDisplayBeast' "$work_barn_ranchhand"
grep -Fq 'tcg.barnDisplayBeast' "$work_barn_lite_device"
grep -Fq 'destroyObject(self);' "$work_barn_beast"
! grep -Fq 'expertise_' "$work_barn_beast"
test "$(grep -Fc 'getWeaponMinDamage(' "$work_barn_beast")" -eq 2
test "$(grep -Fc 'getWeaponMaxDamage(' "$work_barn_beast")" -eq 2
cmp -s "$source_space_analysis_tool" "$work_space_analysis_tool"
cmp -s "$source_space_analysis_template" "$work_space_analysis_template"
cmp -s "$source_space_armor_analysis_template" "$work_space_armor_analysis_template"
cmp -s "$source_reverse_loot_table" "$work_reverse_loot_table"
cmp -s "$source_reverse_loot_lookup_table" "$work_reverse_loot_lookup_table"
! grep -Fq 'expertise_' "$work_space_analysis_tool"
! grep -Fq 'getReverseEngineeringExpertiseBonus' "$work_space_analysis_tool"
! grep -Fq 'getEnhancedSkillStatisticModifier' "$work_space_analysis_tool"
test "$(grep -Fc 'public obj_id reverseEngineer' "$work_space_analysis_tool")" -eq 8
test "$(grep -Fc 'float fltBonus = getLevelBonus(player, level);' "$work_space_analysis_tool")" -eq 8
test "$(grep -Fc 'flags |= ship_component_flags.SCF_reverse_engineered;' "$work_space_analysis_tool")" -eq 8
test "$(grep -Fc 'setObjVar(self, "reverse_engineering.charges", charges);' "$work_space_analysis_tool")" -eq 8
grep -Fq 'fltBonus = 0.01f;' "$work_space_analysis_tool"
grep -Fq 'fltBonus = 0.02f;' "$work_space_analysis_tool"
grep -Fq 'fltBonus = 0.03f;' "$work_space_analysis_tool"
grep -Fq 'fltBonus = 0.04f;' "$work_space_analysis_tool"
grep -Fq 'fltBonus = 0.05f;' "$work_space_analysis_tool"
grep -Fq 'fltBonus = 0.06f;' "$work_space_analysis_tool"
grep -Fq 'getSkillStatisticModifier(player, "engineering_reverse")' "$work_space_analysis_tool"
grep -Fq 'getSkillStatisticModifier(player, "propulsion_reverse")' "$work_space_analysis_tool"
grep -Fq 'getSkillStatisticModifier(player, "systems_reverse")' "$work_space_analysis_tool"
grep -Fq 'getSkillStatisticModifier(player, "defense_reverse")' "$work_space_analysis_tool"
grep -Fq 'getReverseEngineeringLevel' "$work_space_analysis_tool"
grep -Fq 'destroyObject(objComponent);' "$work_space_analysis_tool"
grep -Fq 'calculateFiresprayGrant' "$work_space_analysis_tool"
grep -Fq 'createLegendaryLoot' "$work_space_analysis_tool"
grep -Fq '"space.crafting.analysis_tool"' "$work_space_analysis_template"
grep -Fq '"space.crafting.analysis_tool"' "$work_space_armor_analysis_template"
cmp -s "$source_exar_open_hand" "$work_exar_open_hand"
cmp -s "$source_exar_spawn_table" "$work_exar_spawn_table"
cmp -s "$source_creatures_table" "$work_creatures_table"
cmp -s "$source_exar_open_hand_template" "$work_exar_open_hand_template"
! grep -Fq 'expertise_' "$work_exar_open_hand"
! grep -Fq 'getEnhancedSkillStatisticModifierUncapped' "$work_exar_open_hand"
! grep -Fq 'healingReduction' "$work_exar_open_hand"
! grep -Fq 'float redux' "$work_exar_open_hand"
test "$(grep -Fc 'healing.healDamage(self, HEALTH, 125000);' "$work_exar_open_hand")" -eq 1
grep -Fq 'incrementAddsKilled(self);' "$work_exar_open_hand"
grep -Fq 'String sacBuff = getSacrificeBuff(self);' "$work_exar_open_hand"
grep -Fq 'kill(add);' "$work_exar_open_hand"
grep -Fq 'buff.applyBuff(self, sacBuff);' "$work_exar_open_hand"
grep -Fq 'clienteffect/bacta_bomb.cef' "$work_exar_open_hand"
test "$(grep -Ec 'sacrifice = "kun_(one|two|three|four|five|six|seven|eight)_sacrifice";' "$work_exar_open_hand")" -eq 8
awk -F '\t' '$1 == "heroic_exar_open_hand" { found++; if ($2 != "open" || $3 != "spawn_open" || $4 != "r2" || $9 != "theme_park.heroic.exar_kun.open_hand" || $11 !~ /OnDeath:triggerId:open_won/ || $12 != 1) exit 2 } END { if (found != 1) exit 3 }' "$work_exar_spawn_table"
awk -F '\t' '$1 == "heroic_exar_open_hand" { found++; if ($2 != 90 || $7 != "BOSS" || $14 != "exar_kun_open_hand.iff" || $76 != "heroic_exar_open_hand") exit 2 } END { if (found != 1) exit 3 }' "$work_creatures_table"
grep -Fq 'sharedTemplate = "object/mobile/shared_exar_kun_open_hand.iff"' "$work_exar_open_hand_template"
cmp -s "$source_ai_combat_profiles" "$work_ai_combat_profiles"
cmp -s "$source_axkva_spawn_table" "$work_axkva_spawn_table"
! grep -R -Fq --include='*.java' 'expertise_healing_reduction' "$work_script"
nandina_heal_block="$(sed -n '/public int nandina_heal(/,/public int lelli_bleed(/p' "$work_combat_actions")"
! printf '%s' "$nandina_heal_block" | grep -Fq 'getEnhancedSkillStatisticModifierUncapped'
! printf '%s' "$nandina_heal_block" | grep -Fq 'healingReduction'
! printf '%s' "$nandina_heal_block" | grep -Fq 'float redux'
test "$(printf '%s' "$nandina_heal_block" | grep -Fc 'healing.healDamage(gorvo, HEALTH, 50000);')" -eq 1
printf '%s' "$nandina_heal_block" | grep -Fq 'trial.getObjectsInDungeonWithObjVar(trial.getTop(self), "spawn_id")'
printf '%s' "$nandina_heal_block" | grep -Fq 'equals("gorvo")'
printf '%s' "$nandina_heal_block" | grep -Fq '!isIdValid(gorvo) || ai_lib.isDead(gorvo)'
printf '%s' "$nandina_heal_block" | grep -Fq 'clienteffect/bacta_bomb.cef'
awk -F '\t' '$1 == "nandina_heal" { found++ } END { if (found != 1) exit 2 }' "$work_command_table"
awk -F '\t' '$1 == "nandina_heal" { found++ } END { if (found != 1) exit 2 }' "$work_combat_data"
awk -F '\t' '$1 == "heroic_axkva_nandina" { found++; if ($3 != "nandina_heal" || $4 != 10 || $5 != 100) exit 2 } END { if (found != 1) exit 3 }' "$work_ai_combat_profiles"
awk -F '\t' '$1 == "heroic_axkva_nandina" { found++; if ($2 != "nandina" || $9 != "theme_park.heroic.axkva_min.nandina") exit 2 } END { if (found != 2) exit 3 }' "$work_axkva_spawn_table"
awk -F '\t' '$1 == "heroic_axkva_gorvo" { found++; if ($2 != "gorvo" || $9 != "theme_park.heroic.axkva_min.gorvo") exit 2 } END { if (found != 2) exit 3 }' "$work_axkva_spawn_table"
awk -F '\t' '$1 == "heroic_axkva_nandina" { found++; if ($2 != 91 || $7 != "BOSS" || $76 != "heroic_axkva_nandina") exit 2 } END { if (found != 1) exit 3 }' "$work_creatures_table"
awk -F '\t' '$1 == "heroic_axkva_gorvo" { found++; if ($2 != 91 || $7 != "BOSS" || $76 != "heroic_axkva_gorvo") exit 2 } END { if (found != 1) exit 3 }' "$work_creatures_table"
! grep -Eq 'expertise_use_buff_chance_line_|private_use_buff_chance_line_|expertise_buff_chance_line_|expertise_buff_duration_(line|group|single)_' "$work_combat_library"
grep -Fq 'public static float getAuthoredBuffDuration' "$work_combat_library"
test "$(grep -Eh 'buffDuration = (combat[.])?getAuthoredBuffDuration[(]' "$work_combat_library" "$work_healing_library" | wc -l)" -eq 4
! grep -Fq 'expertise_' "$work_healing_library"
! grep -Eq 'getExpertiseModifiedHealing|getHealingAfterReductions|getTargetHealingBonus' "$work_healing_library"
grep -Fq 'float modifiedHate = delta / HEALING_AGGRO_REDUCER;' "$work_healing_library"
cmp -s "$source_movement_library" "$work_movement_library"
cmp -s "$source_movement_table" "$work_movement_table"
! grep -Fq 'expertise_movement_buff_' "$work_movement_library"
grep -Fq 'strength = getStrength(name);' "$work_movement_library"
awk -F '\t' '$1 == "retreat" && $2 == "boost" && $3 == "82.2" { found = 1 } END { exit found ? 0 : 1 }' "$work_movement_table"
awk -F '\t' '$1 == "fs_force_run" && $2 == "boost" && $3 == "125" { found = 1 } END { exit found ? 0 : 1 }' "$work_movement_table"
cmp -s "$source_armor_library" "$work_armor_library"
! grep -Fq 'expertise_' "$work_armor_library"
! grep -Fq '"elemental_resistance"' "$work_armor_library"
grep -Fq 'getFloatObjVar(mob, OBJVAR_ARMOR_BASE + "." + OBJVAR_GENERAL_PROTECTION)' "$work_armor_library"
grep -Fq 'fltSpecialProts[intJ] += fltWeight * fltSpecialProt;' "$work_armor_library"
grep -Fq 'combat.getArmorDecayPercentage(objArmor)' "$work_armor_library"
cmp -s "$source_battlefield_vehicle" "$work_battlefield_vehicle"
cmp -s "$source_battlefield_vehicle_table" "$work_battlefield_vehicle_table"
cmp -s "$source_echo_base_spawns" "$work_echo_base_spawns"
cmp -s "$source_vehicle_mine" "$work_vehicle_mine"
! grep -Fq 'expertise_innate_protection_all' "$work_battlefield_vehicle"
grep -Fq 'setObjVar(target, armor.OBJVAR_ARMOR_BASE + "." + armor.OBJVAR_GENERAL_PROTECTION, amount);' "$work_battlefield_vehicle"
grep -Fq 'armor.recalculateArmorForMob(target);' "$work_battlefield_vehicle"
awk -F '\t' '$1 == "snowspeeder.iff" { snow++; if ($2 != "adventure2" || $3 != 600000 || $4 != 10000) exit 2 } $1 == "hoth_at_st.iff" { atst++; if ($2 != "adventure2" || $3 != 650000 || $4 != 15000) exit 3 } END { if (snow != 1 || atst != 1) exit 4 }' "$work_battlefield_vehicle_table"
awk -F '\t' '$0 ~ /systems[.]vehicle_system[.]battlefield_vehicle/ { total++; if ($1 == "object/mobile/vehicle/snowspeeder.iff") snow++; else if ($1 == "object/mobile/vehicle/hoth_at_st.iff") atst++; else exit 2 } END { if (total != 21 || snow != 13 || atst != 8) exit 3 }' "$work_echo_base_spawns"
! grep -Fq 'strength_modified' "$work_vehicle_mine"
! grep -Fq 'addSkillModModifier' "$work_vehicle_mine"
test "$(grep -Fc 'createTriggerVolume("hoth_vehicle_mine", 10.0f, true);' "$work_vehicle_mine")" -eq 1
test "$(grep -Fc 'queueCommand(self, (-1220440242),' "$work_vehicle_mine")" -eq 2
grep -Fq 'stealth.checkForAndMakeVisible(breacher);' "$work_vehicle_mine"
test "$(grep -Fc 'removeTriggerVolume("hoth_vehicle_mine");' "$work_vehicle_mine")" -eq 2
awk -F '\t' '$1 == "heroic_echo_vehicle_mine" { spawn++ } $1 ~ /^deleteSpawn:vehicle_mine_[0-9][0-9]:combat_explosion_lair_large[.]cef$/ { cleanup++ } END { if (spawn != 60 || cleanup != 60) exit 2 }' "$work_echo_base_spawns"
awk -F '\t' 'NR == 1 { for (i = 1; i <= NF; i++) column[$i] = i; next } $(column["creatureName"]) == "heroic_echo_vehicle_mine" { found++; if ($(column["BaseLevel"]) != 91 || $(column["template"]) != "vehicle_mine.iff" || $(column["scripts"]) != "theme_park.heroic.echo_base.vehicle_mine") exit 2 } END { if (found != 1) exit 3 }' "$work_creatures_table"
awk -F '\t' 'NR == 1 { for (i = 1; i <= NF; i++) column[$i] = i; next } $(column["commandName"]) == "hoth_sapper_detonate" { found++; if ($(column["scriptHook"]) != "hoth_sapper_detonate" || $(column["commandGroup"]) != "combat_ranged" || $(column["target"]) != "other" || $(column["targetType"]) != "all") exit 2 } END { if (found != 1) exit 3 }' "$work_command_table"
awk -F '\t' 'NR == 1 { for (i = 1; i <= NF; i++) column[$i] = i; next } $(column["actionName"]) == "hoth_sapper_detonate" { found++; if ($(column["attackType"]) != "AREA" || $(column["coneLength"]) != 10 || $(column["addedDamage"]) != 150000 || $(column["weaponType"]) != "RIFLE" || $(column["weaponCategory"]) != "RANGED_WEAPON" || $(column["damageType"]) != "ENERGY" || $(column["specialLine"]) != "sapper") exit 2 } END { if (found != 1) exit 3 }' "$work_combat_data"
cmp -s "$source_wampa_boss" "$work_wampa_boss"
cmp -s "$source_outbreak_boss" "$work_outbreak_boss"
cmp -s "$source_outbreak_buildout" "$work_outbreak_buildout"
! grep -Fq 'expertise_glancing_blow_reduction' "$work_wampa_boss"
! grep -Fq 'expertise_glancing_blow_reduction' "$work_outbreak_boss"
grep -Fq 'trial.setHp(self, trial.HP_UNCLE_JOE);' "$work_wampa_boss"
grep -Fq 'buff.applyBuff(self, "open_balance_buff", -1.0f);' "$work_wampa_boss"
grep -Fq 'summon_adds' "$work_wampa_boss"
grep -Fq 'trial.setHp(self, trial.HP_UNCLE_JOE);' "$work_outbreak_boss"
grep -Fq 'warnPlayerTimerBegin' "$work_outbreak_boss"
grep -Fq 'handleBossDistanceCheck' "$work_outbreak_boss"
awk -F '\t' '$1 == "heroic_echo_wampa_boss" { wampa++; if ($0 !~ /theme_park[.]heroic[.]echo_base[.]wampa_boss/) exit 2 } $1 == "outbreak_afflicted_rancor" { outbreak++; if ($0 !~ /theme_park[.]outbreak[.]boss_fight_functionality/) exit 3 } END { if (wampa != 1 || outbreak != 1) exit 4 }' "$work_creatures_table"
awk -F '\t' '$1 == "echo_base_wampa_boss" { wampa++; if ($0 !~ /wampa_boss_ice_throw_prep/) exit 2 } $1 == "outbreak_afflicted_rancor" { outbreak++; if ($0 !~ /death_troopers_afflicted_toss/) exit 3 } END { if (wampa != 1 || outbreak != 1) exit 4 }' "$work_ai_combat_profiles"
awk -F '\t' '$1 == "heroic_echo_wampa_boss" && $2 == "uncle_joe_id" { found++ } END { if (found != 1) exit 2 }' "$work_echo_base_spawns"
test "$(grep -Fc 'object/tangible/quest/outbreak/group_boss_fight_terminal.iff' "$work_outbreak_buildout")" -eq 1
test "$(grep -Fc 'outbreak_afflicted_rancor' "$work_outbreak_buildout")" -eq 1
cmp -s "$source_heroic_random_stat_item" "$work_heroic_random_stat_item"
cmp -s "$source_master_item_table" "$work_master_item_table"
cmp -s "$source_heroic_drops" "$work_heroic_drops"
cmp -s "$source_skills_table" "$work_skills_table"
cmp -s "$source_queue" "$work_queue"
grep -Fq 'getWeightedWeaponSpeedModifier' "$work_heroic_random_stat_item"
grep -Fq 'LEGACY_NGE_PRIMARY_MODIFIERS' "$work_heroic_random_stat_item"
grep -Fq 'LEGACY_NGE_ACTION_MODIFIERS' "$work_heroic_random_stat_item"
test "$(grep -Fc 'removeLegacyNgeModifiers(self);' "$work_heroic_random_stat_item")" -eq 3
test "$(grep -Fc 'if (!hasWeaponSpeedModifier(self))' "$work_heroic_random_stat_item")" -eq 3
test "$(grep -Fc 'setObjVar(self, "skillmod.bonus." +' "$work_heroic_random_stat_item")" -eq 1
! grep -Eq 'setObjVar\(.*(_modified|expertise_action_weapon_)' "$work_heroic_random_stat_item"
grep -Fq 'removeObjVar(self, objVar);' "$work_heroic_random_stat_item"
! grep -Fq 'removeObjVar(self, "skillmod.bonus");' "$work_heroic_random_stat_item"
for legacy_primary in agility_modified stamina_modified constitution_modified precision_modified strength_modified luck_modified; do
    test "$(grep -Fc "\"$legacy_primary\"" "$work_heroic_random_stat_item")" -eq 1
done
for legacy_action in expertise_action_weapon_0 expertise_action_weapon_1 expertise_action_weapon_2 expertise_action_weapon_4 expertise_action_weapon_5 expertise_action_weapon_6 expertise_action_weapon_7 expertise_action_weapon_9 expertise_action_weapon_10 expertise_action_weapon_11; do
    test "$(grep -Fc "\"$legacy_action\"" "$work_heroic_random_stat_item")" -eq 1
done
grep -Fq 'weightingRoll <= 57' "$work_heroic_random_stat_item"
grep -Fq 'weightingRoll >= 78' "$work_heroic_random_stat_item"
for speed_mod in rifle_speed carbine_speed pistol_speed onehandmelee_speed twohandmelee_speed unarmed_speed polearm_speed onehandlightsaber_speed twohandlightsaber_speed polearmlightsaber_speed; do
    test "$(grep -Fc "\"$speed_mod\"" "$work_heroic_random_stat_item")" -eq 1
    grep -Fq "$speed_mod=" "$work_skills_table"
    grep -Fq "return \"$speed_mod\";" "$work_queue"
done
awk -F '\t' '$1 ~ /^item_heroic_random_/ { total++; if ($2 !~ /^object\/tangible\/wearables\/(ring|necklace|bracelet)\// || $11 != "item.heroic_random_stat_item") exit 2 } END { if (total != 26) exit 3 }' "$work_master_item_table"
test "$(grep -Eo 'item_heroic_random_(ring|neck|bracelet_[lr])_[0-9]{2}_[0-9]{2}' "$work_heroic_drops" | wc -l)" -eq 72
test "$(grep -Eo 'item_heroic_random_(ring|neck|bracelet_[lr])_[0-9]{2}_[0-9]{2}' "$work_heroic_drops" | sort -u | wc -l)" -eq 26
grep -Fq 'owner.getEnhancedModValue(speedSkill)' "$work_queue"
grep -Fq 'return executeTime > 1.0f ? executeTime : 1.0f;' "$work_queue"
cmp -s "$source_reverse_engineering_tool" "$work_reverse_engineering_tool"
cmp -s "$source_performance_library" "$work_performance_library"
cmp -s "$source_skills_table" "$work_skills_table"
cmp -s "$source_schematic_group_table" "$work_schematic_group_table"
! grep -Fq 'expertise_' "$work_reverse_engineering_tool"
! grep -Fq 'getEnhancedSkillStatisticModifierUncapped' "$work_reverse_engineering_tool"
! grep -Fq 'reverseEngineeringBonusMultiplier' "$work_reverse_engineering_tool"
grep -Fq 'crafting_tailor_master' "$work_reverse_engineering_tool"
grep -Fq 'crafting_armorsmith_master' "$work_reverse_engineering_tool"
grep -Fq 'crafting_weaponsmith_master' "$work_reverse_engineering_tool"
grep -Fq 'getFloatObjVar(self, "crafting.stationMod")' "$work_reverse_engineering_tool"
grep -Fq 'getFloatObjVar(self, "res_quality")' "$work_reverse_engineering_tool"
! grep -Fq 'expertise_' "$work_performance_library"
grep -Fq 'if (!isNgeInspirationEnabled())' "$work_performance_library"
grep -Fq 'int maxHoloAllowed = 1;' "$work_performance_library"
awk -F '\t' '$1 == "crafting_tailor_master" { t = 1 } $1 == "crafting_armorsmith_master" { a = 1 } $1 == "crafting_weaponsmith_master" { w = 1 } END { exit t && a && w ? 0 : 1 }' "$work_skills_table"
awk -F '\t' '$1 == "craftArtisanNewbieGroupA" && $2 == "object/draft_schematic/item/item_reverse_engineering_tool.iff" { tool = 1 } $1 == "craftArtisanNewbieGroupA" && $2 == "object/draft_schematic/reverse_engineering/enhancement_module.iff" { module = 1 } END { exit tool && module ? 0 : 1 }' "$work_schematic_group_table"
cmp -s "$source_weapons_library" "$work_weapons_library"
cmp -s "$source_combat_weapon" "$work_combat_weapon"
diff -qr "$source_conversation" "$work_conversation" >/dev/null
diff -qr "$source_theme_park" "$work_theme_park" >/dev/null
! grep -R -E '(^|[^[:alnum:]_.])((combat|utils)\.)?getLevel[[:space:]]*\([[:space:]]*(player|whoTriggeredMe)[[:space:]]*\)' "$work_conversation" "$work_theme_park"
cmp -s "$source_mission_base" "$work_mission_base"
cmp -s "$source_mission_dynamic" "$work_mission_dynamic"
cmp -s "$source_mission_escort" "$work_mission_escort"
! grep -R -E '(^|[^[:alnum:]_.])getLevel[[:space:]]*\([[:space:]]*player[[:space:]]*\)' "$work_script/systems/missions"
cmp -s "$source_player_utility" "$work_player_utility"
cmp -s "$source_ai" "$work_ai"
cmp -s "$source_base_player" "$work_base_player"
cmp -s "$source_base_class" "$work_base_class"
cmp -s "$source_buff_library" "$work_buff_library"
cmp -s "$source_performcommands" "$work_performcommands"
cmp -s "$source_buff_handler" "$work_buff_handler"
display_cleanup_source="$(sed -n '/public int setDisplayOnlyDefensiveMods/,/public int OnGetAttributes/p' "$work_base_player")"
test "$(printf '%s' "$display_cleanup_source" | grep -Fc '"display_only_')" -eq 14
test "$(printf '%s' "$display_cleanup_source" | grep -Fc 'removeAttribOrSkillModModifier(')" -eq 1
! printf '%s' "$display_cleanup_source" | grep -Fq 'addSkillModModifier'
! printf '%s' "$display_cleanup_source" | grep -Fq 'combat.get'
test "$(grep -Eh 'messageTo\([^;]*"setDisplayOnlyDefensiveMods"' "$work_base_player" "$work_armor_library" "$work_reverse_engineering_library" "$work_buff_handler" | wc -l)" -eq 22
test "$(grep -Ec 'messageTo\([^;]*"setDisplayOnlyDefensiveMods"' "$work_base_player")" -eq 6
awk -F '\t' '$1 ~ /^display_only_/ { found++; if ($2 != "ALL" || $3 != "combat" || $4 != 1) exit 2 } END { if (found != 13) exit 3 }' "$work_skill_mod_listing"
grep -Fq 'modifierName.startsWith("expertise_")' "$work_buff_handler"
primary_stat_source="$(sed -n '/public boolean isRetiredNgePrimaryStatisticModifier/,/public boolean isRetiredNgeBuffSkillModifier/p' "$work_buff_handler")"
for retired_primary_stat in agility_modified constitution_modified luck_modified precision_modified stamina_modified strength_modified; do
    printf '%s' "$primary_stat_source" | grep -Fq "modifierName.equals(\"$retired_primary_stat\")"
done
! printf '%s' "$primary_stat_source" | grep -Fq 'milk_'
buff_skill_predicate_source="$(sed -n '/public boolean isRetiredNgeBuffSkillModifier/,/public void retireNgeExpertiseModifier/p' "$work_buff_handler")"
printf '%s' "$buff_skill_predicate_source" | grep -Fq 'isRetiredNgeExpertiseModifier(modifierName)'
printf '%s' "$buff_skill_predicate_source" | grep -Fq 'isRetiredNgePrimaryStatisticModifier(modifierName)'
skill_add_source="$(sed -n '/public int skillAddBuffHandler/,/public int skillRemoveBuffHandler/p' "$work_buff_handler")"
skill_percent_source="$(sed -n '/public int skillPercentAddBuffHandler/,/public int skillPercentRemoveBuffHandler/p' "$work_buff_handler")"
force_power_source="$(sed -n '/public int forcePowerAddBuffHandler/,/public int forcePowerRemoveBuffHandler/p' "$work_buff_handler")"
for expertise_writer_source in "$skill_add_source" "$skill_percent_source" "$force_power_source"; do
    printf '%s' "$expertise_writer_source" | grep -Fq 'isRetiredNgeBuffSkillModifier(subtype)'
    printf '%s' "$expertise_writer_source" | grep -Fq 'retireNgeExpertiseModifier(self, effectName)'
    printf '%s' "$expertise_writer_source" | grep -Fq 'addSkillModModifier'
done
armor_break_source="$(sed -n '/public int armorBreakAddBuffHandler/,/public int armorBreakRemoveBuffHandler/p' "$work_buff_handler")"
printf '%s' "$armor_break_source" | grep -Fq 'retireNgeExpertiseModifier(self, effectName)'
printf '%s' "$armor_break_source" | grep -Fq 'utils.removeScriptVar(self, INITIAL_GENERAL_PROTECTION)'
! printf '%s' "$armor_break_source" | grep -Fq 'getSkillStatisticModifier'
! printf '%s' "$armor_break_source" | grep -Fq 'getEnhancedSkillStatisticModifier'
! printf '%s' "$armor_break_source" | grep -Fq 'addSkillModModifier'
stance_source="$(sed -n '/public int stanceAddBuffHandler/,/public int stanceRemoveBuffHandler/p' "$work_buff_handler")"
printf '%s' "$stance_source" | grep -Fq 'retireNgeExpertiseModifier(self, "expertise_fs_force_clarity_1_proc")'
printf '%s' "$stance_source" | grep -Fq 'retireNgeExpertiseModifier(self, "expertise_fs_flurry_charge_proc")'
! printf '%s' "$stance_source" | grep -Fq 'addSkillModModifier(self, "expertise_fs_'
buildabuff_source="$(sed -n '/public int buildabuffAddBuffHandler/,/public int buildabuffRemoveBuffHandler/p' "$work_buff_handler")"
test "$(grep -Ec 'addSkillModModifier\(self, *"expertise_' "$work_buff_handler")" -eq 3
test "$(printf '%s' "$buildabuff_source" | grep -Ec 'addSkillModModifier\(self, *"expertise_')" -eq 3
printf '%s' "$buildabuff_source" | grep -Fq 'buff.isPostNgeBuffProgressionRetired()'
cmp -s "$source_player_stealth" "$work_player_stealth"
cmp -s "$source_beast_library" "$work_beast_library"
cmp -s "$source_beast_control_device" "$work_beast_control_device"
cmp -s "$source_player_beastmaster" "$work_player_beastmaster"
cmp -s "$source_buff_builder_cancel" "$work_buff_builder_cancel"
cmp -s "$source_buff_builder_response" "$work_buff_builder_response"
cmp -s "$source_crafting_base" "$work_crafting_base"
cmp -s "$source_script/library/pet_lib.java" "$work_script/library/pet_lib.java"
cmp -s "$source_script/ai/pet_control_device.java" "$work_script/ai/pet_control_device.java"
cmp -s "$source_script/npc/pet_deed/droid_deed.java" "$work_script/npc/pet_deed/droid_deed.java"
for post_nge_beast_creation_path in $post_nge_beast_creation_paths; do
    cmp -s "$source_script/$post_nge_beast_creation_path" "$work_script/$post_nge_beast_creation_path"
done
for post_nge_beast_runtime_path in $post_nge_beast_runtime_paths; do
    cmp -s "$source_script/$post_nge_beast_runtime_path" "$work_script/$post_nge_beast_runtime_path"
done
for post_nge_officer_runtime_path in $post_nge_officer_runtime_paths; do
    cmp -s "$source_script/$post_nge_officer_runtime_path" "$work_script/$post_nge_officer_runtime_path"
done
grep -Fq 'actionName.startsWith("of_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeOfficerPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeOfficerPlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 3
! grep -Fq 'expertise_of_reinforcements_1' "$work_script/ai/officer_pet.java"
grep -Fq 'pet_lib.destroyOfficerPets(master)' "$work_script/ai/officer_pet.java"
test "$(grep -Fc 'retirePostNgeOfficerSupplyDrop(self, owner)' "$work_script/systems/combat/combat_supply_drop_controller.java")" -eq 3
grep -Fq 'isPlayer(owner)' "$work_script/systems/combat/combat_supply_drop_controller.java"
grep -Fq 'isPlayer(transferer)' "$work_script/systems/combat/combat_supply_drop_crate.java"
grep -Fq 'retirePostNgeOfficerSupplyCrate(self)' "$work_script/systems/combat/combat_supply_drop_crate.java"
grep -Fq 'actionName.startsWith("fs_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeForceSensitivePlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeForceSensitivePlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 1
grep -Fq 'buff.removeBuff(self, "fs_dot_immunity_recourse")' "$work_script/systems/combat/combat_actions.java"
grep -Fq 'actionName.startsWith("sm_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeSmugglerPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeSmugglerPlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 6
for recourse in sm_feeling_lucky_recourse sm_lucky_break_recourse sm_break_the_deal_recourse sm_melee_stun_recourse; do
    grep -Fq "buff.removeBuff(self, \"$recourse\")" "$work_script/systems/combat/combat_actions.java"
done
grep -Fq 'actionName.startsWith("bh_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeBountyHunterPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
grep -Fq 'actionName.startsWith("co_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeCommandoPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeCommandoPlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 1
grep -Fq 'isRetiredPostNgeCommandoPlayerAction(self, "co_kill_trap_1")' "$work_script/systems/combat/combat_actions.java"
! grep -R -F 'expertise_bm_' "$work_script" --include='*.java' --exclude-dir=working --exclude-dir=test
! grep -E -R 'get(Enhanced)?SkillStatisticModifier(Uncapped)?\([^\r\n]*"(bm_|incubation_time_reduction)' "$work_script" --include='*.java' --exclude-dir=working --exclude-dir=test
! grep -Fq 'playerLearnBeastMasterSkill' "$work_script/conversation/trainer_beast_master.java"
grep -Fq 'conversation/trainer_beast_master' "$work_script/conversation/trainer_beast_master.java"
grep -Fq 'retirePostNgeBeastMasterPlayerState(player)' "$work_script/conversation/trainer_beast_master.java"
grep -Fq 'isPostNgeBeastMasterPlayerRuntimeRetired()' "$work_script/player/live_conversions.java"
grep -Fq 'retirePostNgeBeastMasterPlayerState(player)' "$work_script/player/live_conversions.java"
! grep -Fq 'getSkillStatisticModifier' "$work_script/systems/beast/base_incubator.java"
! grep -Fq 'getEnhancedSkillStatisticModifier' "$work_script/systems/beast/enzyme_crafting_base.java"
! grep -Fq 'hasSkill(player, "expertise_bm_' "$work_script/systems/beast/beast_egg.java"
for precu_item_level_path in $precu_item_level_paths; do
    cmp -s "$source_script/$precu_item_level_path" "$work_script/$precu_item_level_path"
done
for precu_encounter_difficulty_path in $precu_encounter_difficulty_paths; do
    cmp -s "$source_script/$precu_encounter_difficulty_path" "$work_script/$precu_encounter_difficulty_path"
done
for precu_retained_system_level_path in $precu_retained_system_level_paths; do
    cmp -s "$source_script/$precu_retained_system_level_path" "$work_script/$precu_retained_system_level_path"
done
for precu_cosmetic_familiar_path in $precu_cosmetic_familiar_paths; do
    cmp -s "$source_script/$precu_cosmetic_familiar_path" "$work_script/$precu_cosmetic_familiar_path"
done
for precu_droid_detonation_path in $precu_droid_detonation_paths; do
    cmp -s "$source_script/$precu_droid_detonation_path" "$work_script/$precu_droid_detonation_path"
done
for conversation_file in \
    dath_bh_wanted_list_01 ep3_kachirho_missing_son ep3_myyydril_pers \
    ep3_myyydril_weaponsmith ep3_rodian_junk_dealer ep3_wke_junk_dealer \
    fan_faire_pgc_c3po imperial_empire_day_kaythree mun_quest_marauder \
    quest_crowd_pleaser_manager rebel_remembrance_day_rieekan som_kenobi_epo_qetora
do
    cmp -s "$source_conversation/$conversation_file.java" "$work_conversation/$conversation_file.java"
done
for profession_gate_file in \
    systems/missions/base/mission_terminal.java \
    systems/missions/base/mission_player.java \
    systems/missions/dynamic/mission_bounty_droid_terminal.java \
    systems/missions/dynamic/mission_bounty_informant.java \
    library/slicing.java item/container/locked_slicable.java \
    theme_park/dungeon/keypad_handler.java \
    theme_park/dungeon/geonosian_madbio_bunker/office_keypad.java \
    theme_park/dungeon/corvette/computer.java
do
    cmp -s "$source_script/$profession_gate_file" "$work_script/$profession_gate_file"
    ! grep -Fq 'class_' "$work_script/$profession_gate_file"
done
for crafting_gate_file in \
    theme_park/dungeon/death_watch_bunker/craft_armorsmith_droid.java \
    theme_park/dungeon/death_watch_bunker/craft_droidengineer_droid.java \
    theme_park/dungeon/death_watch_bunker/craft_jetpack_droid.java \
    theme_park/dungeon/death_watch_bunker/craft_tailor_droid.java \
    theme_park/dungeon/death_watch_bunker/door_lock_crafting_armor.java \
    theme_park/dungeon/death_watch_bunker/door_lock_crafting_de.java \
    theme_park/dungeon/death_watch_bunker/door_lock_crafting_tailor.java \
    theme_park/dungeon/mustafar_trials/valley_battleground/mining_droid.java \
    npc/static_quest/quest_armorsmith.java
do
    cmp -s "$source_script/$crafting_gate_file" "$work_script/$crafting_gate_file"
    ! grep -Fq 'class_' "$work_script/$crafting_gate_file"
done
# Publish 14.1 crafting Luck is a skill-modifier roll, not the later generic
# player-level-capped primary-stat proc or its forced critical-success path.
javap -classpath "$class_root" -v script.library.luck | grep -Fq 'getPrecuCraftingLuckRoll'
javap -classpath "$class_root" -v script.library.luck | grep -Fq 'force_luck'
! javap -classpath "$class_root" -v script.library.luck | grep -Fq 'luck_modified'
! javap -classpath "$class_root" -v script.library.luck | grep -Fq 'getLevel'
javap -classpath "$class_root" -v script.library.craftinglib | grep -Fq 'getPrecuCraftingLuckRoll'
! javap -classpath "$class_root" -v script.library.craftinglib | grep -Fq 'isLucky'
for crafting_expertise_class in \
    script.library.craftinglib \
    script.library.resource \
    script.library.player_structure \
    script.systems.crafting.crafting_base \
    script.systems.crafting.armor.crafting_new_cybernetics_final
do
    ! javap -classpath "$class_root" -v "$crafting_expertise_class" | grep -Fq 'expertise_'
done
javap -classpath "$class_root" -v script.library.player_structure | grep -Fq 'player_structure.power.modifiers.factory'
javap -classpath "$class_root" -v script.library.player_structure | grep -Fq 'player_structure.power.modifiers.harvester'
javap -classpath "$class_root" -constants script.item.survey_tool.survey_tool_script | grep -Fq 'SURVEY_TOOL_DELAY = 25'
! javap -classpath "$class_root" -v script.item.survey_tool.survey_tool_script | grep -Fq 'expertise_resource_sampling_time_decrease'
! javap -classpath "$class_root" -v script.item.survey_tool.survey_tool_script | grep -Fq 'MIN_SURVEY_TOOL_DELAY'
! javap -classpath "$class_root" -v script.terminal.vendor | grep -Fq 'expertise_vendor_cost_decrease'
javap -classpath "$class_root" -v script.terminal.vendor | grep -Fq 'crafting_merchant_master'
javap -classpath "$class_root" -v script.terminal.vendor | grep -Fq 'crafting_merchant_sales_02'
! javap -classpath "$class_root" -v script.library.combat | grep -Eq 'expertise_use_buff_chance_line_|private_use_buff_chance_line_|expertise_buff_chance_line_|expertise_buff_duration_(line|group|single)_'
javap -classpath "$class_root" -v script.library.combat | grep -Fq 'getAuthoredBuffDuration'
! javap -classpath "$class_root" -v script.library.healing | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.library.healing | grep -Eq 'getExpertiseModifiedHealing|getHealingAfterReductions|getTargetHealingBonus'
javap -classpath "$class_root" -v script.library.healing | grep -Fq 'getAuthoredBuffDuration'
! javap -classpath "$class_root" -v script.library.movement | grep -Fq 'expertise_movement_buff_'
javap -classpath "$class_root" -v script.library.movement | grep -Fq 'getStrength'
! javap -classpath "$class_root" -v script.library.armor | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.library.armor | grep -Fq 'elemental_resistance'
javap -classpath "$class_root" -v script.library.armor | grep -Fq 'getArmorSpecialProtections'
javap -classpath "$class_root" -v script.library.armor | grep -Fq 'getArmorDecayPercentage'
javap -classpath "$class_root" -v script.library.combat | grep -Fq 'applyPrecuArmorProtection'
javap -classpath "$class_root" -v script.library.combat | grep -Fq 'getPrecuArmorObjectProtection'
! javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'getEnhancedSkillStatisticModifierUncapped'
! javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'reverseEngineeringBonusMultiplier'
javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'crafting_tailor_master'
javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'crafting_armorsmith_master'
javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'crafting_weaponsmith_master'
javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'crafting.stationMod'
javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'res_quality'
! javap -classpath "$class_root" -v script.library.performance | grep -Fq 'expertise_'
javap -classpath "$class_root" -v script.library.performance | grep -Fq 'isNgeInspirationEnabled'
javap -classpath "$class_root" -v script.library.performance | grep -Fq 'holographicCleanup'
javap -classpath "$class_root" -c -p script.library.combat | grep -Fq 'precuHamCostModel'
javap -classpath "$class_root" -c -p script.library.combat | grep -Fq 'freeshot_case_miss'
javap -classpath "$class_root" -c -p script.systems.combat.combat_base | grep -Fq 'getPrecuPrimaryAttackResult'
javap -classpath "$class_root" -c -p script.systems.combat.combat_base | grep -Fq 'getPrecuSecondaryDefenseResult'
javap -classpath "$class_root" -c -p script.systems.combat.combat_base | grep -Fq 'getDefenderResult'
# Production callbacks retain a persisted-state cleanup path for the NGE
# display-only combat statistics, but the PRE-CU player never recreates them.
display_cleanup_bytecode="$(javap -classpath "$class_root" -c -p script.player.base.base_player | sed -n '/public int setDisplayOnlyDefensiveMods/,/public int OnGetAttributes/p')"
test "$(printf '%s' "$display_cleanup_bytecode" | grep -Fc 'display_only_')" -eq 14
printf '%s' "$display_cleanup_bytecode" | grep -Fq 'removeAttribOrSkillModModifier'
! printf '%s' "$display_cleanup_bytecode" | grep -Fq 'addSkillModModifier'
! printf '%s' "$display_cleanup_bytecode" | grep -Fq 'script/library/combat.get'
# Production buff handlers clean retained NGE expertise modifiers without
# recreating them; dormant Build-a-Buff remains behind its earlier hard gate.
buff_handler_bytecode="$(javap -classpath "$class_root" -c -p script.systems.buff.buff_handler)"
printf '%s' "$buff_handler_bytecode" | grep -Fq 'isRetiredNgeExpertiseModifier'
printf '%s' "$buff_handler_bytecode" | grep -Fq 'isRetiredNgePrimaryStatisticModifier'
printf '%s' "$buff_handler_bytecode" | grep -Fq 'isRetiredNgeBuffSkillModifier'
for retired_primary_stat in agility_modified constitution_modified luck_modified precision_modified stamina_modified strength_modified; do
    printf '%s' "$buff_handler_bytecode" | grep -Fq "$retired_primary_stat"
done
armor_break_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int armorBreakAddBuffHandler/,/public int armorBreakRemoveBuffHandler/p')"
printf '%s' "$armor_break_bytecode" | grep -Fq 'retireNgeExpertiseModifier'
printf '%s' "$armor_break_bytecode" | grep -Fq 'amor.unmodifiedArmorValue'
! printf '%s' "$armor_break_bytecode" | grep -Fq 'getSkillStatisticModifier'
! printf '%s' "$armor_break_bytecode" | grep -Fq 'getEnhancedSkillStatisticModifier'
! printf '%s' "$armor_break_bytecode" | grep -Fq 'addSkillModModifier'
stance_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int stanceAddBuffHandler/,/public int stanceRemoveBuffHandler/p')"
printf '%s' "$stance_bytecode" | grep -Fq 'expertise_fs_force_clarity_1_proc'
printf '%s' "$stance_bytecode" | grep -Fq 'expertise_fs_flurry_charge_proc'
! printf '%s' "$stance_bytecode" | grep -Fq 'Method addSkillModModifier'
# Authenticated PRE-CU DOTs persist their era route through every pulse while
# later-content compatibility callers retain the inherited DOT path.
javap -classpath "$class_root" -v script.library.dot | grep -Fq 'applyPrecuDotEffect'
javap -classpath "$class_root" -v script.library.dot | grep -Fq '.precuAuthoritative'
javap -classpath "$class_root" -v script.library.healing | grep -Fq 'applyPrecuDotEffect'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'applyPrecuDotEffect'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'applyPrecuDotEffect'
# Retained junk and contraband content uses its authored base behavior without
# the inherited NGE Smuggler expertise tree or Feeling Lucky proc.
! javap -classpath "$class_root" -v script.library.smuggler | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.library.smuggler | grep -Fq 'sm_feeling_lucky'
! javap -classpath "$class_root" -v script.library.smuggler | grep -Fq 'ACCT_RELIC_DEALER'
javap -classpath "$class_root" -v script.library.smuggler | grep -Fq 'handleSoldJunk'
javap -classpath "$class_root" -v script.library.smuggler | grep -Fq 'script/library/money.systemPayout'
javap -classpath "$class_root" -v script.library.smuggler | grep -Fq 'spaceContrabandDropCheck'
javap -classpath "$class_root" -v script.library.smuggler | grep -Fq 'contrabandDropCheck'
! javap -classpath "$class_root" -v script.npc.junk_dealer.junk_dealer_summon | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.npc.junk_dealer.junk_dealer_summon | grep -Fq 'sm_junk_dealer_'
! javap -classpath "$class_root" -v script.npc.junk_dealer.junk_dealer_summon | grep -Fq 'buffParty'
javap -classpath "$class_root" -v script.npc.junk_dealer.junk_dealer_summon | grep -Fq 'handleGreeting'
javap -classpath "$class_root" -v script.npc.junk_dealer.junk_dealer_summon | grep -Fq 'totalProfits'
javap -classpath "$class_root" -v script.npc.junk_dealer.junk_dealer_summon | grep -Fq 'handleRunAway'
javap -classpath "$class_root" -v script.npc.junk_dealer.junk_dealer_summon | grep -Fq 'junk_dealer_total_profits'
# Retained Smuggler patrol encounters use their authored baseline probabilities
# without NGE expertise or expertise-scaled underworld rank arithmetic.
! javap -classpath "$class_root" -v script.ai.smuggler_spawn_enemy | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.ai.smuggler_spawn_enemy | grep -Fq 'getSmugglerRank'
javap -classpath "$class_root" -v script.ai.smuggler_spawn_enemy | grep -Fq 'CONTRABAND_BASE_PASS_CHANCE'
javap -classpath "$class_root" -v script.ai.smuggler_spawn_enemy | grep -Fq 'SLY_LIE_BASE_BONUS'
javap -classpath "$class_root" -v script.ai.smuggler_spawn_enemy | grep -Fq 'FAST_TALK_BASE_CHANCE'
javap -classpath "$class_root" -v script.ai.smuggler_spawn_enemy | grep -Fq 'contrabandCheckResult'
javap -classpath "$class_root" -v script.ai.smuggler_spawn_enemy | grep -Fq 'fastTalkReaction'
# Retained Echo Base vehicles consume authored armor through the PRE-CU mob
# protection objvar and cache, never through the NGE expertise statistic.
! javap -classpath "$class_root" -v script.systems.vehicle_system.battlefield_vehicle | grep -Fq 'expertise_innate_protection_all'
javap -classpath "$class_root" -v script.systems.vehicle_system.battlefield_vehicle | grep -Fq 'armor.general_protection'
javap -classpath "$class_root" -v script.systems.vehicle_system.battlefield_vehicle | grep -Fq 'recalculateArmorForMob'
# Retained Echo Base mines preserve their trigger and sapper command lifecycle but
# cannot seed the NGE strength primary statistic into the PRE-CU ruleset.
! javap -classpath "$class_root" -v script.theme_park.heroic.echo_base.vehicle_mine | grep -Fq 'strength_modified'
javap -classpath "$class_root" -v script.theme_park.heroic.echo_base.vehicle_mine | grep -Fq 'hoth_vehicle_mine'
javap -classpath "$class_root" -c script.theme_park.heroic.echo_base.vehicle_mine | grep -Fq -- '-1220440242'
javap -classpath "$class_root" -v script.theme_park.heroic.echo_base.vehicle_mine | grep -Fq 'checkForAndMakeVisible'
javap -classpath "$class_root" -v script.theme_park.heroic.echo_base.vehicle_mine | grep -Fq 'removeTriggerVolume'
# Retained later bosses keep their encounter lifecycle but cannot seed the NGE
# glancing-blow expertise statistic into the PRE-CU combat route.
! javap -classpath "$class_root" -v script.theme_park.heroic.echo_base.wampa_boss | grep -Fq 'expertise_glancing_blow_reduction'
javap -classpath "$class_root" -v script.theme_park.heroic.echo_base.wampa_boss | grep -Fq 'open_balance_buff'
javap -classpath "$class_root" -v script.theme_park.heroic.echo_base.wampa_boss | grep -Fq 'summon_adds'
! javap -classpath "$class_root" -v script.theme_park.outbreak.boss_fight_functionality | grep -Fq 'expertise_glancing_blow_reduction'
javap -classpath "$class_root" -v script.theme_park.outbreak.boss_fight_functionality | grep -Fq 'warnPlayerTimerBegin'
javap -classpath "$class_root" -v script.theme_park.outbreak.boss_fight_functionality | grep -Fq 'handleBossDistanceCheck'
# Retained heroic jewelry writes only an authenticated Publish 14.1 weapon
# speed modifier. Its explicit NGE symbols exist solely to migrate exact leaves
# from persisted items; they cannot appear in the generation writer.
javap -classpath "$class_root" -v script.item.heroic_random_stat_item | grep -Fq 'getWeightedWeaponSpeedModifier'
javap -classpath "$class_root" -v script.item.heroic_random_stat_item | grep -Fq 'removeLegacyNgeModifiers'
heroic_generation_bytecode="$(javap -classpath "$class_root" -c -p script.item.heroic_random_stat_item | sed -n '/public int generateRandomStats/,/public void removeLegacyNgeModifiers/p')"
printf '%s\n' "$heroic_generation_bytecode" | grep -Fq 'setObjVar'
! printf '%s\n' "$heroic_generation_bytecode" | grep -Eq '(_modified|expertise_action_weapon_)'
for legacy_action in expertise_action_weapon_0 expertise_action_weapon_1 expertise_action_weapon_2 expertise_action_weapon_4 expertise_action_weapon_5 expertise_action_weapon_6 expertise_action_weapon_7 expertise_action_weapon_9 expertise_action_weapon_10 expertise_action_weapon_11; do
    javap -classpath "$class_root" -v script.item.heroic_random_stat_item | grep -Fq "String $legacy_action"
done
for legacy_primary in agility_modified stamina_modified constitution_modified precision_modified strength_modified luck_modified; do
    javap -classpath "$class_root" -v script.item.heroic_random_stat_item | grep -Fq "String $legacy_primary"
done
for speed_mod in rifle_speed carbine_speed pistol_speed onehandmelee_speed twohandmelee_speed unarmed_speed polearm_speed onehandlightsaber_speed twohandlightsaber_speed polearmlightsaber_speed; do
    javap -classpath "$class_root" -v script.item.heroic_random_stat_item | grep -Fq "$speed_mod"
done
# The retained simulator exposes only the armor and defense statistics consumed
# by the authoritative Publish 14.1 combat route.
! javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'armor.recalculateArmorForMob'
javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'precu_armor_rating'
javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'precu_armor_lightsaber'
javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'ranged_defense'
javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'melee_defense'
javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'unarmed_passive_defense'
javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'applyPersistedTargetDummyDefenses'
javap -classpath "$class_root" -v script.library.target_dummy | grep -Fq 'precu.armor.rating'
javap -classpath "$class_root" -v script.systems.tcg.target_creature | grep -Fq 'Enter a whole-number PRE-CU defense value.'
# Retained TCG barn representations use authored and stored display values only;
# post-NGE Beast Master expertise and attention mechanics never enter the path.
! javap -classpath "$class_root" -v script.library.tcg | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.library.tcg | grep -Fq 'getExpertiseStat'
! javap -classpath "$class_root" -v script.library.tcg | grep -Fq 'getExpertiseSpeed'
! javap -classpath "$class_root" -v script.library.tcg | grep -Fq 'ATTENTION_PENALTY_DEBUFF'
javap -classpath "$class_root" -v script.library.tcg | grep -Fq 'barnDisplayBeast'
javap -classpath "$class_root" -v script.library.tcg | grep -Fq 'initializeBeastStatsFromBarn'
javap -classpath "$class_root" -v script.library.tcg | grep -Fq 'HealthRegen'
javap -classpath "$class_root" -v script.library.tcg | grep -Fq 'setInvulnerable'
javap -classpath "$class_root" -v script.systems.tcg.barn_ranchhand | grep -Fq 'barnDisplayBeast'
javap -classpath "$class_root" -v script.systems.tcg.barn_lite_device | grep -Fq 'barnDisplayBeast'
javap -classpath "$class_root" -v script.systems.tcg.barn_beast | grep -Fq 'barnStorage.'
javap -classpath "$class_root" -v script.systems.tcg.barn_beast | grep -Fq 'beast_roaming'
javap -classpath "$class_root" -v script.systems.tcg.barn_beast | grep -Fq 'destroyObject'
! javap -classpath "$class_root" -v script.systems.tcg.barn_beast | grep -Fq 'expertise_'
javap -classpath "$class_root" -v script.systems.tcg.barn_beast | grep -Fq 'getWeaponMinDamage'
javap -classpath "$class_root" -v script.systems.tcg.barn_beast | grep -Fq 'getWeaponMaxDamage'
# Retained JTL component reverse engineering uses its authored level curve and
# PRE-CU Shipwright reverse modifiers, never the later trader expertise tree.
! javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'getReverseEngineeringExpertiseBonus'
javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'getLevelBonus'
javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'reverseEngineerArmor'
javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'reverseEngineerWeapon'
# ship_component_flags.SCF_reverse_engineered is a compile-time constant, so
# javac legally inlines its value. Authenticate the named constant in source
# above and the emitted flag objvar path here.
javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'ship_comp.flags'
javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'reverse_engineering.charges'
javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'calculateFiresprayGrant'
javap -classpath "$class_root" -v script.space.crafting.analysis_tool | grep -Fq 'createLegendaryLoot'
# The retained Open Hand encounter heals its authored fixed amount after a
# sacrifice and cannot inherit the later NGE healing-reduction statistic.
! javap -classpath "$class_root" -v script.theme_park.heroic.exar_kun.open_hand | grep -Fq 'expertise_healing_reduction'
! javap -classpath "$class_root" -v script.theme_park.heroic.exar_kun.open_hand | grep -Fq 'getEnhancedSkillStatisticModifierUncapped'
javap -classpath "$class_root" -v script.theme_park.heroic.exar_kun.open_hand | grep -Fq '125000'
javap -classpath "$class_root" -v script.theme_park.heroic.exar_kun.open_hand | grep -Fq 'sacrificeAdd'
javap -classpath "$class_root" -v script.theme_park.heroic.exar_kun.open_hand | grep -Fq 'incrementAddsKilled'
javap -classpath "$class_root" -v script.theme_park.heroic.exar_kun.open_hand | grep -Fq 'getSacrificeBuff'
javap -classpath "$class_root" -v script.theme_park.heroic.exar_kun.open_hand | grep -Fq 'clienteffect/bacta_bomb.cef'
# Nandina's retained Axkva encounter heal uses its authored fixed amount and
# cannot inherit the later NGE healing-reduction statistic from Gorvo.
! javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'expertise_healing_reduction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'nandina_heal'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq '50000'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'spawn_id'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'clienteffect/bacta_bomb.cef'
# Publish 14.1 crystal quality is an authored property of the crystal/loot
# result, never a derivative of the receiving player's NGE combat level.
javap -classpath "$class_root" -v script.systems.jedi.jedi_saber_component | grep -Fq 'initializePrecuCrystal'
javap -classpath "$class_root" -v script.systems.jedi.jedi_saber_component | grep -Fq 'Crystal item level = '
javap -classpath "$class_root" -v script.systems.jedi.jedi_saber_component | grep -Fq 'canTuneLightsaberCrystal'
! javap -classpath "$class_root" -v script.systems.jedi.jedi_saber_component | grep -Fq 'getLevel'
grep -Fq 'rand(1, 50)' "$work_jedi_saber_component"
grep -Fq 'getIntObjVar(self, levelObjVar)' "$work_jedi_saber_component"
# Publish 14.1 has an entertainer attribute-buff session, but no native NGE
# Buff Builder or general/TCG percentage-XP progression layer.
buff_progression_retired_bytecode="$(javap -classpath "$class_root" -c script.library.buff | sed -n '/isPostNgeBuffProgressionRetired/,/retirePostNgeBuffProgression/p')"
printf '%s' "$buff_progression_retired_bytecode" | grep -Fq 'iconst_1'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgeBuffProgression'
javap -classpath "$class_root" -v script.player.skill.performcommands | grep -Fq 'isPostNgeBuffProgressionRetired'
javap -classpath "$class_root" -v script.player.skill.performcommands | grep -Fq 'retirePostNgeBuffProgression'
javap -classpath "$class_root" -v script.systems.buff.buff_handler | grep -Fq 'isPostNgeBuffProgressionRetired'
javap -classpath "$class_root" -v script.systems.buff_builder.buff_builder_cancel | grep -Fq 'retirePostNgeBuffProgression'
javap -classpath "$class_root" -v script.systems.buff_builder.buff_builder_response | grep -Fq 'retirePostNgeBuffProgression'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeBuffProgression'
javap -classpath "$class_root" -v script.library.xp | grep -Fq 'isPostNgeBuffProgressionRetired'
javap -classpath "$class_root" -v script.systems.crafting.crafting_base | grep -Fq 'isPostNgeBuffProgressionRetired'
javap -classpath "$class_root" -v script.library.gcw | grep -Fq 'isPostNgeBuffProgressionRetired'
# Publish 14.1 Ranger/Rifleman stealth remains authoritative. Retire the NGE
# Spy player runtime while retaining the two expansion-device commands.
spy_skill_retired_bytecode="$(javap -classpath "$class_root" -c script.library.skill | sed -n '/isRetiredPostNgeSpySkill/,/grant(/p')"
printf '%s' "$spy_skill_retired_bytecode" | grep -Fq 'class_spy_'
printf '%s' "$spy_skill_retired_bytecode" | grep -Fq 'expertise_sp_'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeSpyPlayerState'
javap -classpath "$class_root" -v script.systems.skills.stealth.player_stealth | grep -Fq 'isRetiredPostNgeSpyBuffName'
javap -classpath "$class_root" -v script.systems.skills.stealth.player_stealth | grep -Fq 'retirePostNgeSpyPlayerState'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeSpyPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'sp_hide_device_1'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'sp_neutralize_device_1'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeSpyPlayerAction'
javap -classpath "$class_root" -v script.systems.buff.buff_handler | grep -Fq 'isRetiredPostNgeSpyBuffName'
# Publish 14.1 Squad Leader remains authoritative. Retire the post-NGE Officer
# command family and every delayed/persisted player reinforcement surface.
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeOfficerPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'of_'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeOfficerPlayerAction'
javap -classpath "$class_root" -v script.ai.officer_pet | grep -Fq 'retirePostNgeOfficerPet'
javap -classpath "$class_root" -v script.ai.officer_pet | grep -Fq 'destroyOfficerPets'
! javap -classpath "$class_root" -v script.ai.officer_pet | grep -Fq 'expertise_of_reinforcements_1'
javap -classpath "$class_root" -v script.systems.combat.combat_supply_drop_controller | grep -Fq 'retirePostNgeOfficerSupplyDrop'
javap -classpath "$class_root" -v script.systems.combat.combat_supply_drop_controller | grep -Fq 'destroyOfficerPets'
javap -classpath "$class_root" -v script.systems.combat.combat_supply_drop_crate | grep -Fq 'retirePostNgeOfficerSupplyCrate'
javap -classpath "$class_root" -v script.systems.combat.combat_supply_drop_crate | grep -Fq 'no_access_not_in_group'
# Publish 14.1 Jedi and Village rows use their classic force*, saber*, heal*,
# mindBlast*, and jediMindTrick commands; fs_* is retained NGE compatibility.
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeForceSensitivePlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'fs_'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeForceSensitivePlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'fs_dot_immunity_recourse'
# Publish 14.1 Smuggler uses combat_smuggler skill boxes and classic named
# commands; sm_* remains retained NGE compatibility without player authority.
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeSmugglerPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'sm_'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeSmugglerPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'sm_inspect_cargo'
# Publish 14.1 Bounty Hunter and Commando use their combat_bountyhunter and
# combat_commando trees; bh_* and co_* remain NPC/content compatibility only.
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeBountyHunterPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeCommandoPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeCommandoPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'co_kill_trap_1'
# Publish 14.1 Creature Handler remains authoritative. Retain Beast Master
# assets for later-content loading but retire their player combat runtime.
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'isPostNgeBeastMasterPlayerRuntimeRetired'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'bm_player_buff'
! javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'expertise_bm_'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'beast_master.known_skills'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'setBeastmasterPetCommands'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'removeBatchObjVar'
javap -classpath "$class_root" -v script.ai.beast_control_device | grep -Fq 'isRetiredPostNgeBeastMasterPlayer'
! javap -classpath "$class_root" -v script.ai.beast | grep -Fq 'expertise_'
! javap -classpath "$class_root" -v script.ai.creature_combat | grep -Fq 'expertise_bm_'
! javap -classpath "$class_root" -v script.conversation.trainer_beast_master | grep -Fq 'playerLearnBeastMasterSkill'
javap -classpath "$class_root" -v script.conversation.trainer_beast_master | grep -Fq 'conversation/trainer_beast_master'
javap -classpath "$class_root" -v script.conversation.trainer_beast_master | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.player.live_conversions | grep -Fq 'isPostNgeBeastMasterPlayerRuntimeRetired'
javap -classpath "$class_root" -v script.player.live_conversions | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.player.player_beastmaster | grep -Fq 'handleRetirePostNgeBeastMasterPlayerState'
! javap -classpath "$class_root" -v script.player.player_beastmaster | grep -Fq 'expertise_bm_'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeBeastMasterPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeBeastMasterPlayer'
! javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'expertise_bm_'
# Retire the remaining NGE Beast Master player creation and conversion
# surfaces without deleting retained content or PRE-CU Bio-Engineer crafting.
javap -classpath "$class_root" -constants script.library.incubator | grep -Fq 'POST_NGE_BEAST_MASTER_CREATION_PLAYER_RUNTIME_RETIRED = true'
javap -classpath "$class_root" -v script.library.incubator | grep -Fq 'retirePostNgeBeastMasterCreationPlayerState'
javap -classpath "$class_root" -v script.library.incubator | grep -Fq 'retirePostNgeIncubatorStationState'
! javap -classpath "$class_root" -v script.library.incubator | grep -Fq 'expertise_bm_'
! javap -classpath "$class_root" -v script.library.incubator | grep -Fq 'incubation_time_reduction'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'createHolopetCubeFromEgg'
javap -classpath "$class_root" -v script.systems.beast.base_incubator | grep -Fq 'OnIncubatorCommitted'
javap -classpath "$class_root" -v script.systems.beast.base_incubator | grep -Fq 'isPostNgeBeastMasterCreationPlayerRuntimeRetired'
! javap -classpath "$class_root" -v script.systems.beast.base_incubator | grep -Fq 'getEnhancedSkillStatisticModifier'
javap -classpath "$class_root" -v script.systems.beast.enzyme_crafting_base | grep -Fq 'isPostNgeBeastMasterCreationPlayerRuntimeRetired'
javap -classpath "$class_root" -v script.systems.beast.enzyme_crafting_base | grep -Fq 'terminateProcess'
! javap -classpath "$class_root" -v script.systems.beast.enzyme_crafting_base | grep -Fq 'getEnhancedSkillStatisticModifier'
javap -classpath "$class_root" -v script.systems.beast.beast_egg | grep -Fq 'isRetiredPostNgeBeastMasterCreationPlayer'
! javap -classpath "$class_root" -v script.systems.beast.beast_egg | grep -Fq 'expertise_bm_'
javap -classpath "$class_root" -v script.systems.beast.enzyme_extractor | grep -Fq 'isRetiredPostNgeBeastMasterCreationPlayer'
javap -classpath "$class_root" -v script.ai.pet_control_device | grep -Fq 'isRetiredPostNgeBeastMasterCreationPlayer'
javap -classpath "$class_root" -v script.npc.pet_deed.pet_deed | grep -Fq 'isRetiredPostNgeBeastMasterCreationPlayer'
javap -classpath "$class_root" -v script.player.player_utility | grep -Fq 'isRetiredPostNgeBeastMasterCreationPlayer'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeBeastMasterCreationPlayerState'
# Retained Restuss content keeps its authored advanced-area threshold, but
# player admission is governed by the hidden PRE-CU combat skill-box score.
javap -classpath "$class_root" -c script.player.base.base_player | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -c script.player.base.base_player | grep -Fq 'bipush        75'
# localOptions.cfg is a runtime-rendered configuration, not a copied build
# artifact. Authenticate the immutable template before restart; the rendered
# values are verified after the container's run path regenerates them.
grep -Fq 'clusterName=CLUSTERNAME' "$source_local_options"
grep -Fq 'transferServerAddress=HOSTIP' "$source_local_options"
javap -classpath "$class_root" -c script.player.skill.outdoorsman | grep -Fq 'corpse.canPlayerHarvestCreature'
javap -classpath "$class_root" -c script.library.corpse | grep -Fq 'String outdoors_scout_novice'
javap -classpath "$class_root" -c script.library.corpse | grep -Fq 'Method canPlayerHarvestCreature'
javap -classpath "$class_root" -v script.library.corpse | grep -Fq 'Rejected creature resource extraction without Novice Scout'
javap -classpath "$class_root" -v script.library.create | grep -Fq 'datatables/mob/precu_creature_combat_profiles.iff'
javap -classpath "$class_root" -v script.library.create | grep -Fq 'precu.combatProfile'
javap -classpath "$class_root" -v script.library.loot | grep -Fq 'Rejected NGE creature-resource loot injection'
javap -classpath "$class_root" -c script.systems.crafting.droid.modules.harvest_module | grep -Fq 'corpse.canPlayerHarvestCreature'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'getPrecuWeaponProfileRow'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'defenseSkill2'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'precu.combatProfile'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'reinstateNgeInvisFromCombat'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'addPrecuCore3HateProcess'
javap -classpath "$class_root" -v script.corpse.ai_corpse | grep -Fq 'Rejected corpse callback without Novice Scout'
javap -classpath "$class_root" -c script.corpse.ai_corpse | grep -Fq 'corpse.canPlayerHarvestCreature'
! javap -classpath "$class_root" -v script.systems.combat.combat_player | grep -Fq 'expertise_stance_riposte'
! javap -classpath "$class_root" -v script.systems.combat.combat_player | grep -Fq 'bh_relentless_onslaught'
! javap -classpath "$class_root" -v script.systems.combat.combat_player | grep -Fq 'expertise_of_last_words_1'
javap -classpath "$class_root" -c script.library.travel | grep -Fq 'rejected retired NGE group-pickup travel'
javap -classpath "$class_root" -v script.player.player_travel | grep -Fq 'Ignored retired NGE group-pickup travel request'
! grep -R -Fq 'class_' "$work_conversation"
javap -classpath "$class_root" -v script.conversation.ep3_myyydril_weaponsmith | grep -Fq 'crafting_weaponsmith_novice'
javap -classpath "$class_root" -v script.conversation.ep3_kachirho_missing_son | grep -Fq 'combat_smuggler_underworld_01'
javap -classpath "$class_root" -v script.conversation.som_kenobi_epo_qetora | grep -Fq 'combat_smuggler_novice'
javap -classpath "$class_root" -v script.conversation.imperial_empire_day_kaythree | grep -Fq 'crafting_architect_novice'
! javap -classpath "$class_root" -v script.conversation.fan_faire_pgc_c3po | grep -Fq 'class_chronicles_novice'
! javap -classpath "$class_root" -v script.conversation.fan_faire_pgc_c3po | grep -Fq 'grantSkill'
javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'combat_bountyhunter_novice'
javap -classpath "$class_root" -v script.systems.missions.base.mission_terminal | grep -Fq 'combat_smuggler_slicing_01'
javap -classpath "$class_root" -v script.item.container.locked_slicable | grep -Fq 'combat_smuggler_novice'
javap -classpath "$class_root" -v script.theme_park.dungeon.corvette.computer | grep -Fq 'combat_smuggler_slicing_04'
javap -classpath "$class_root" -v script.theme_park.dungeon.corvette.computer | grep -Fq 'combat_smuggler_master'
! javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'class_bountyhunter'
! javap -classpath "$class_root" -v script.systems.missions.base.mission_terminal | grep -Fq 'class_smuggler'
! javap -classpath "$class_root" -v script.theme_park.dungeon.corvette.computer | grep -Fq 'class_smuggler'
javap -classpath "$class_root" -v script.library.missions | grep -Fq 'PRECU_ADVANCED_COMBAT_SKILL_WEIGHT'
javap -classpath "$class_root" -v script.library.missions | grep -Fq 'precuMission.creditMultiplier'
javap -classpath "$class_root" -constants script.systems.missions.base.mission_base | grep -Fq 'MAX_MISSIONS = 10'
javap -classpath "$class_root" -v script.systems.missions.base.mission_base | grep -Fq 'fullRewardEach='
javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'insufficient-mission-placeholders'
javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'getPrecuMissionGroupCombatScore'
javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getPrecuCombatSkillScore'
javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getPrecuGroupCombatDifficulty'
javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getPrecuProfessionSkillScore'
javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getPrecuCraftingContentDifficulty'
javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getPrecuEntertainerContentDifficulty'
transition_bytecode="$(javap -classpath "$class_root" -c -p script.library.transition)"
test "$(printf '%s\n' "$transition_bytecode" | grep -Fc 'script/library/skill.getPrecuEncounterDifficulty')" -eq 3
! printf '%s\n' "$transition_bytecode" | grep -Fq 'getLevel'
javap -classpath "$class_root" -v script.conversation.corellia_coronet_vani_korr | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.conversation.imperial_defensive_supply_terminal | grep -Fq 'getPrecuCraftingContentDifficulty'
javap -classpath "$class_root" -v script.conversation.som_pei_yi | grep -Fq 'getPrecuEntertainerContentDifficulty'
javap -classpath "$class_root" -v script.theme_park.outbreak.camp_defense | grep -Fq 'getPrecuEncounterDifficulty'
! javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getGroupObjectLevel'
groundquest_xp_bytecode="$(javap -classpath "$class_root" -v script.library.groundquests)"
printf '%s' "$groundquest_xp_bytecode" | grep -Fq 'datatables/quest/quest_experience.iff'
! printf '%s' "$groundquest_xp_bytecode" | grep -Fq 'datatables/player/player_level.iff'
! printf '%s' "$groundquest_xp_bytecode" | grep -Fq 'getQuestXpCap'
printf '%s' "$groundquest_xp_bytecode" | grep -Fq 'grantCombatStyleXp'
printf '%s' "$groundquest_xp_bytecode" | grep -Fq 'grantCraftingQuestXp'
printf '%s' "$groundquest_xp_bytecode" | grep -Fq 'grantSocialStyleXp'
printf '%s' "$groundquest_xp_bytecode" | grep -Fq 'grantUnmodifiedExperience'
javap -classpath "$class_root" -v script.npc.static_quest.quest_convo | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.library.collection | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.library.space_combat | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.library.space_combat | grep -Fq 'grantCombatStyleXp'
javap -classpath "$class_root" -v script.library.performance | grep -Fq 'getPrecuEntertainerContentDifficulty'
javap -classpath "$class_root" -v script.event.halloween.song_book | grep -Fq 'getPrecuEntertainerContentDifficulty'
javap -classpath "$class_root" -c -p script.library.utils | grep -Fq 'testItemLevelRequirements'
javap -classpath "$class_root" -v script.library.utils | grep -Fq 'isPrecuRetainedItemClass'
javap -classpath "$class_root" -v script.library.utils | grep -Fq 'outdoors_ranger_novice'
javap -classpath "$class_root" -constants script.library.utils | grep -Fq 'NO_PROFESSION = 0'
retained_vendor_bytecode="$(javap -classpath "$class_root" -c -p script.npc.vendor.vendor)"
printf '%s' "$retained_vendor_bytecode" | grep -Fq 'getQualifiedPrecuProfessionInventories'
printf '%s' "$retained_vendor_bytecode" | grep -Fq 'handlePrecuProfessionInventorySelect'
printf '%s' "$retained_vendor_bytecode" | grep -Fq 'script/library/utils.isPrecuRetainedItemClass'
printf '%s' "$retained_vendor_bytecode" | grep -Fq 'script/library/sui.listbox'
! printf '%s' "$retained_vendor_bytecode" | grep -Fq 'getPlayerProfession'
! javap -classpath "$class_root" -v script.theme_park.meatlump.mtp_vendor | grep -Fq 'getPlayerProfession'
! javap -classpath "$class_root" -v script.theme_park.dungeon.nova_orion_station.nova_orion_vendor | grep -Fq 'getPlayerProfession'
javap -classpath "$class_root" -v script.item.gcw_buff_banner.banner_buff_manager | grep -Fq 'getPlayerProfession'
javap -classpath "$class_root" -constants script.library.stealth | grep -Fq 'PRECU_TRAPPING_SKILL_MOD = "trapping"'
javap -classpath "$class_root" -constants script.library.stealth | grep -Fq 'PRECU_CAMOUFLAGE_SKILL_MOD = "camouflage"'
! javap -classpath "$class_root" -v script.library.stealth | grep -Fq 'ranger_trap'
javap -classpath "$class_root" -c -p script.library.weapons | grep -Fq 'restorePrecuWeaponRange'
javap -classpath "$class_root" -c -p script.systems.combat.combat_weapon | grep -Fq 'retireNgeWeaponDamageSkillMods'
! grep -Fq 'expertise_range_bonus' "$work_weapons_library"
! grep -Fq 'PLAYER_ATTACKER_DAMAGE_LEVEL_MULTIPLIER' "$work_combat_weapon"
! grep -Fq 'PLAYER_COMBAT_BASE_DAMAGE' "$work_combat_weapon"
! grep -Fq 'setDamageSkillMods' "$work_combat_weapon"
javap -classpath "$class_root" -v script.library.missions | grep -Fq 'getPrecuCombatSkillScore'
! javap -classpath "$class_root" -v script.library.missions | grep -Fq 'getLevel'
javap -classpath "$class_root" -constants script.library.xp | grep -Fq 'PRECU_GROUP_XP_MULTIPLIER = 1.2f'
javap -classpath "$class_root" -constants script.library.xp | grep -Fq 'PRECU_COMBAT_XP_DIFFICULTY_CAP = 25'
javap -classpath "$class_root" -constants script.library.xp | grep -Fq 'PRECU_COMBAT_XP_PER_DIFFICULTY = 300'
javap -classpath "$class_root" -v script.library.xp | grep -Fq 'combat.intCombatXP'
javap -classpath "$class_root" -v script.library.xp | grep -Fq 'capPrecuCombatXp'
javap -classpath "$class_root" -v script.library.xp | grep -Fq 'private_jedi_difficulty'
javap -classpath "$class_root" -c -p script.library.xp | grep -Fq 'getPrecuWeaponCombatLevel'
javap -classpath "$class_root" -c -p script.library.xp | grep -Fq 'getPrecuCombatLevel'
metrics_level_authority_bytecode="$(javap -classpath "$class_root" -c -p script.library.metrics)"
test "$(printf '%s' "$metrics_level_authority_bytecode" | grep -Fc 'Method script/library/skill.getPrecuEncounterDifficulty' || true)" -eq 4
test "$(printf '%s' "$metrics_level_authority_bytecode" | grep -Fc 'Method getLevel' || true)" -eq 1
test "$(printf '%s' "$metrics_level_authority_bytecode" | grep -Fc 'Method script/library/skill.getGroupLevel' || true)" -eq 1
javap -classpath "$class_root" -c -p script.systems.combat.combat_base | grep -Fq 'getPrecuWeaponCombatLevel'
javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | grep -Fq 'getPrecuCombatLevel'
stealth_detect_bytecode="$(javap -classpath "$class_root" -c script.library.stealth | sed -n '/public static float getDetectChance(/,/public static float getDetectChanceWithDetailedOutput(/p')"
test "$(printf '%s' "$stealth_detect_bytecode" | grep -Fc 'script/library/xp.getPrecuCombatLevel' || true)" -eq 2
! printf '%s' "$stealth_detect_bytecode" | grep -Fq 'Method script/base_class.getLevel'
stealth_detect_detailed_bytecode="$(javap -classpath "$class_root" -c script.library.stealth | sed -n '/public static float getDetectChanceWithDetailedOutput(/,/public static boolean activeDetectHiddenTarget(/p')"
test "$(printf '%s' "$stealth_detect_detailed_bytecode" | grep -Fc 'script/library/xp.getPrecuCombatLevel' || true)" -eq 2
! printf '%s' "$stealth_detect_detailed_bytecode" | grep -Fq 'Method script/base_class.getLevel'
! javap -classpath "$class_root" -v script.library.xp | grep -Fq 'player_level.iff'
! javap -classpath "$class_root" -v script.library.xp | grep -Fq 'free_trial_level_cap'
! javap -classpath "$class_root" -v script.library.missions | grep -Fq 'prose_mission_xp_amount'
! javap -classpath "$class_root" -v script.library.group | grep -Fq 'grantMissionXp'
! javap -classpath "$class_root" -v script.systems.missions.base.mission_base | grep -Fq 'grantMissionXp'
! javap -classpath "$class_root" -v script.systems.missions.base.mission_base | grep -Fq 'distributeMissionXpToGroup'
javap -classpath "$class_root" -c -p script.library.factions | grep -Fq 'awardPrecuNpcCombatFaction'
! javap -classpath "$class_root" -v script.library.factions | grep -Fq 'incrementGCWStanding'
javap -classpath "$class_root" -c script.base_class | grep -Fq 'pvpSetPrecuFactionRank'
javap -classpath "$class_root" -c script.library.factions | grep -Fq 'pvpSetPrecuFactionRank'
javap -classpath "$class_root" -constants script.library.factions | grep -Fq 'FACTION_RATING_DECLARABLE_MIN = 200.0f'
javap -classpath "$class_root" -constants script.library.factions | grep -Fq 'NON_ALIGNED_FACTION_MAX = 1000.0f'
javap -classpath "$class_root" -v script.library.factions | grep -Fq 'getRankCost'
javap -classpath "$class_root" -constants script.library.faction_perk | grep -Fq 'PRECU_CATEGORY_WEAPONS_ARMOR'
javap -classpath "$class_root" -constants script.library.faction_perk | grep -Fq 'PRECU_COMM_LINK_MIN_RANK = 7'
javap -classpath "$class_root" -constants script.library.faction_perk | grep -Fq 'PRECU_COMM_LINK_MAX_TEMPLATE_RANK = 12'
javap -classpath "$class_root" -v script.library.faction_perk | grep -Fq 'precuFactionPerkPurchase'
javap -classpath "$class_root" -v script.library.faction_perk | grep -Fq 'getPrecuEncounterDifficulty'
! javap -classpath "$class_root" -v script.library.faction_perk | grep -Fq 'getLevel'
javap -classpath "$class_root" -v script.library.faction_perk | grep -Fq 'datatables/npc/faction_recruiter/perk_inventory/'
! javap -classpath "$class_root" -v script.library.faction_perk | grep -Fq 'gcw_rewards.iff'
! javap -classpath "$class_root" -v script.library.faction_perk | grep -Fq 'money.requestPayment'
javap -classpath "$class_root" -v script.npc.faction_recruiter.faction_recruiter | grep -Fq 'npc.vendor.vendor'
javap -classpath "$class_root" -v script.npc.faction_recruiter.faction_recruiter | grep -Fq 'displayItemPurchaseSUI'
! javap -classpath "$class_root" -v script.systems.camping.camp_controlpanel | grep -Fq 'faction_perk'
gcw_grant_bytecode="$(javap -classpath "$class_root" -c script.library.gcw | sed -n '/public static void _grantGcwPoints/,/public static void doGcwPointCsLogging/p')"
printf '%s' "$gcw_grant_bytecode" | grep -Fq '0: return'
! printf '%s' "$gcw_grant_bytecode" | grep -Fq 'pvpModifyCurrentGcwPoints'
! printf '%s' "$gcw_grant_bytecode" | grep -Fq 'gcwInvasionCreditForGCW'
! printf '%s' "$gcw_grant_bytecode" | grep -Fq 'grantGcwPointsToRegion'
gcw_level_authority_bytecode="$(javap -classpath "$class_root" -c -p script.library.gcw)"
test "$(printf '%s' "$gcw_level_authority_bytecode" | grep -Fc 'Method script/library/skill.getPrecuEncounterDifficulty' || true)" -eq 7
test "$(printf '%s' "$gcw_level_authority_bytecode" | grep -Fc 'Method getLevel' || true)" -eq 1
gcw_city_retired_bytecode="$(javap -classpath "$class_root" -c script.library.gcw | sed -n '/isPostNgeCityInvasionRetired/,/assignScanInterests/p')"
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'iconst_1'
javap -classpath "$class_root" -c -p script.systems.gcw.gcw_city | grep -Fq 'retirePostNgeCityInvasion'
javap -classpath "$class_root" -c -p script.planet.planet_base | grep -Fq 'retirePostNgeCityInvasionState'
! javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'gcw.invasionRunning.bestine'
gcw_battlefield_retired_bytecode="$(javap -classpath "$class_root" -c script.library.gcw | sed -n '/isPostNgeQueuedBattlefieldRetired/,/assignScanInterests/p')"
printf '%s' "$gcw_battlefield_retired_bytecode" | grep -Fq 'iconst_1'
javap -classpath "$class_root" -c -p script.systems.gcw.pvp_battlefield | grep -Fq 'retirePostNgeQueuedBattlefield'
javap -classpath "$class_root" -c -p script.systems.gcw.battlefield_terminal | grep -Fq 'retirePostNgeQueuedBattlefieldTerminal'
javap -classpath "$class_root" -c -p script.systems.gcw.player_pvp | grep -Fq 'retirePostNgeQueuedBattlefieldPlayer'
javap -classpath "$class_root" -c -p script.player.base.base_player | grep -Fq 'retirePostNgeQueuedBattlefieldPlayerState'
javap -classpath "$class_root" -v script.player.live_conversions | grep -Fq 'systems.gcw.player_pvp'
javap -classpath "$class_root" -constants script.player.live_conversions | grep -Fq 'POST_NGE_PLAYER_MIGRATION_RUNTIME_RETIRED = true'
javap -classpath "$class_root" -c script.player.live_conversions | grep -Fq 'cureward.cureward'
javap -classpath "$class_root" -constants script.cureward.cureward | grep -Fq 'COMBAT_UPGRADE_REWARD_RUNTIME_RETIRED = true'
! javap -classpath "$class_root" -v script.cureward.cureward | grep -Fq 'frn_loyalty_award_plaque_'
open_world_battlefield_build_bytecode="$(javap -classpath "$class_root" -c -p script.library.battlefield | sed -n '/public static boolean canBuildBattlefieldStructure(/,/public static boolean canBuildReinforcement(/p')"
test "$(printf '%s' "$open_world_battlefield_build_bytecode" | grep -Fc 'crafting_artisan_novice' || true)" -eq 1
printf '%s' "$open_world_battlefield_build_bytecode" | grep -Fq 'Method hasSkill'
! printf '%s' "$open_world_battlefield_build_bytecode" | grep -Fq 'script/library/utils.isProfession'
! printf '%s' "$open_world_battlefield_build_bytecode" | grep -Fq 'TRADER'
trap_admission_bytecode="$(javap -classpath "$class_root" -c -p script.item.trap.trap_base | sed -n '/public int OnObjectMenuSelect(/,/public void trapUsed(/p')"
test "$(printf '%s' "$trap_admission_bytecode" | grep -Fc 'trapping' || true)" -eq 1
test "$(printf '%s' "$trap_admission_bytecode" | grep -Fc 'outdoors_scout_novice' || true)" -eq 1
printf '%s' "$trap_admission_bytecode" | grep -Fq 'Method hasSkill'
printf '%s' "$trap_admission_bytecode" | grep -Fq '88718951'
javap -classpath "$class_root" -c script.library.skill | grep -Fq 'isRetiredNgeProgressionSkillName'
cts_upload_bytecode="$(javap -classpath "$class_root" -c script.player.base.base_player | sed -n '/OnUploadCharacter/,/OnDownloadCharacter/p')"
printf '%s' "$cts_upload_bytecode" | grep -Fq 'using PRE-CU skill-box authority'
! printf '%s' "$cts_upload_bytecode" | grep -Fq 'getSkillTemplate'
! printf '%s' "$cts_upload_bytecode" | grep -Fq 'getWorkingSkill'
! printf '%s' "$cts_upload_bytecode" | grep -Fq 'getCommandListingForPlayer'
cts_download_bytecode="$(javap -classpath "$class_root" -c script.player.base.base_player | sed -n '/OnDownloadCharacter/,/OnSkillModDone/p')"
printf '%s' "$cts_download_bytecode" | grep -Fq 'isRetiredNgeProgressionSkillName'
printf '%s' "$cts_download_bytecode" | grep -Fq 'reattachQuestScripts'
! printf '%s' "$cts_download_bytecode" | grep -Fq 'setSkillTemplate'
! printf '%s' "$cts_download_bytecode" | grep -Fq 'grantCommand'
javap -classpath "$class_root" -v script.systems.battlefield.player_battlefield | grep -Fq 'addFactionStanding'
gcw_static_retired_bytecode="$(javap -classpath "$class_root" -c script.library.gcw | sed -n '/isPostNgeFixedStaticBaseRetired/,/getPub30StaticBaseControllerId/p')"
printf '%s' "$gcw_static_retired_bytecode" | grep -Fq 'iconst_1'
javap -classpath "$class_root" -c -p script.player.player_faction | grep -Fq 'cleanupRetiredFixedStaticBaseState'
javap -classpath "$class_root" -c -p script.systems.gcw.static_base.master | grep -Fq 'cleanupRetiredFixedStaticBase'
javap -classpath "$class_root" -c -p script.systems.gcw.static_base.base_master | grep -Fq 'cleanupRetiredFixedStaticBase'
javap -classpath "$class_root" -c -p script.systems.gcw.static_base.base_spawner | grep -Fq 'cleanupRetiredFixedStaticBaseSpawns'
javap -classpath "$class_root" -c -p script.systems.gcw.static_base.spawned_object | grep -Fq 'cleanupRetiredFixedStaticBaseSpawn'
javap -classpath "$class_root" -c -p script.systems.gcw.static_base.control_terminal | grep -Fq 'cleanupRetiredFixedStaticBaseTerminal'
javap -classpath "$class_root" -c -p script.systems.gcw.static_base.control_terminal_player | grep -Fq 'cleanupRetiredFixedStaticBaseCapture'
javap -classpath "$class_root" -v script.structure.municipal.starport | grep -Fq 'object/tangible/gcw/static_base/invisible_beacon.iff'
javap -classpath "$class_root" -v script.structure.municipal.cloning_facility | grep -Fq 'object/tangible/gcw/static_base/invisible_cloner_'
javap -classpath "$class_root" -v script.systems.collections.consume_click | grep -Fq 'object/tangible/collection/col_gcw_static_base_'
javap -classpath "$class_root" -v script.library.hq | grep -Fq 'faction_perk.hq.terminal_cloning_override'
javap -classpath "$class_root" -v script.faction_perk.hq.loader | grep -Fq 'handleDelayedRefundChecker'
javap -classpath "$class_root" -v script.faction_perk.hq.terminal | grep -Fq 'OnObjectMenuRequest'
javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_override | grep -Fq 'outdoors_bio_engineer_novice'
javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_override | grep -Fq 'outdoors_bio_engineer_dna_harvesting_04'
javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_override | grep -Fq 'outdoors_bio_engineer_master'
javap -classpath "$class_root" -c script.faction_perk.hq.objective_terminal_override | grep -Fq 'sipush        1000'
javap -classpath "$class_root" -v script.faction_perk.hq.objective_power_regulator | grep -Fq 'combat_commando_heavyweapon_speed_02'
javap -classpath "$class_root" -c script.faction_perk.hq.objective_power_regulator | grep -Fq 'sipush        1000'
javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_security | grep -Fq 'combat_smuggler_slicing_01'
javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_security | grep -Fq 'combat_smuggler_slicing_04'
javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_uplink | grep -Fq 'combat_bountyhunter_investigation_02'
javap -classpath "$class_root" -c script.faction_perk.hq.objective_terminal_uplink | grep -Fq 'sipush        1000'
javap -classpath "$class_root" -v script.faction_perk.hq.terminal | grep -Fq 'outdoors_squadleader_novice'
! javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_override | grep -Eq 'class_(medic|commando|smuggler|bountyhunter|officer)_phase'
! javap -classpath "$class_root" -v script.faction_perk.hq.objective_power_regulator | grep -Eq 'class_(medic|commando|smuggler|bountyhunter|officer)_phase'
! javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_security | grep -Eq 'class_(medic|commando|smuggler|bountyhunter|officer)_phase'
! javap -classpath "$class_root" -v script.faction_perk.hq.objective_terminal_uplink | grep -Eq 'class_(medic|commando|smuggler|bountyhunter|officer)_phase'
! javap -classpath "$class_root" -v script.faction_perk.hq.terminal | grep -Eq 'class_(medic|commando|smuggler|bountyhunter|officer)_phase'
javap -classpath "$class_root" -constants script.library.skill | grep -Fq 'PRECU_PHASE_TWO_COMBAT_SCORE = 25'
javap -classpath "$class_root" -constants script.library.skill | grep -Fq 'PRECU_PHASE_THREE_COMBAT_SCORE = 50'
javap -classpath "$class_root" -constants script.library.skill | grep -Fq 'PRECU_PHASE_FOUR_COMBAT_SCORE = 75'
javap -classpath "$class_root" -c script.library.skill | sed -n '/getProfessionPhase/,/validateExpertise/p' | grep -Fq 'getPrecuCombatSkillScore'
javap -classpath "$class_root" -v script.library.utils | grep -Fq 'combat_smuggler_underworld_01'
! javap -classpath "$class_root" -v script.library.utils | grep -Eq 'class_(bountyhunter|commando|domestics|engineering|entertainer|forcesensitive|medic|munitions|officer|smuggler|spy|structures|trader)'
javap -classpath "$class_root" -v script.library.ai_lib | grep -Fq 'combat_smuggler_master'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'outdoors_squadleader_novice'
javap -classpath "$class_root" -v script.library.xp | grep -Fq 'outdoors_squadleader_novice'
javap -classpath "$class_root" -v script.player.cmd.register | grep -Fq 'social_dancer_novice'
javap -classpath "$class_root" -v script.player.cmd.register | grep -Fq 'social_musician_novice'
javap -classpath "$class_root" -v script.terminal.terminal_crafting_display | grep -Fq 'crafting_shipwright_novice'
javap -classpath "$class_root" -v script.item.tool.reverse_engineering_tool | grep -Fq 'crafting_weaponsmith_novice'
javap -classpath "$class_root" -v script.theme_park.dungeon.mustafar_trials.valley_battleground.demolition_generator | grep -Fq 'combat_commando_support_04'
javap -classpath "$class_root" -v script.systems.crafting.weapon.lightsaber.crafting_melee_lightsaber_training | grep -Fq 'jedi_padawan_novice'
awk -F '\t' '$13 ~ /gcw_city_bestine[.]iff/ { found++; if ($12 != "systems.dungeon_sequencer.sequence_controller") exit 2 } END { if (found != 1) exit 3 }' "$work_city_buildout_bestine"
awk -F '\t' '$13 ~ /gcw_city_dearic[.]iff/ { found++; if ($12 != "systems.dungeon_sequencer.sequence_controller") exit 2 } END { if (found != 1) exit 3 }' "$work_city_buildout_dearic"
awk -F '\t' '$13 ~ /gcw_city_keren[.]iff/ { found++; if ($12 != "systems.dungeon_sequencer.sequence_controller") exit 2 } END { if (found != 1) exit 3 }' "$work_city_buildout_keren"
awk -F '\t' '$13 ~ /(battlefieldName|terminalName)/ { found++; if ($12 != "") exit 2 } END { if (found != 5) exit 3 }' "$work_battlefield_buildout_endor_1_1"
awk -F '\t' '$13 ~ /(battlefieldName|terminalName)/ { found++; if ($12 != "") exit 2 } END { if (found != 2) exit 3 }' "$work_battlefield_buildout_endor_1_8"
awk -F '\t' '$13 ~ /(battlefieldName|terminalName)/ { found++; if ($12 != "") exit 2 } END { if (found != 7) exit 3 }' "$work_battlefield_buildout_yavin4_3_1"
awk -F '\t' '$13 ~ /(battlefieldName|terminalName)/ { found++; if ($12 != "") exit 2 } END { if (found != 6) exit 3 }' "$work_battlefield_buildout_yavin4_5_5"
awk -F '\t' 'BEGIN { split("-1950861366 -1861947162 -1704050194 -1583793873 -1043449019 -899991077 -485623403", a, " "); for (i in a) ids[a[i]]=1 } ($1 in ids) { found++; if ($12 != "" || $13 ~ /(gcw[.]static_base|travel[.]|collection[.]gcw|scriptString)/) exit 2 } END { if (found != 7) exit 3 }' "$work_static_buildout_corellia"
awk -F '\t' 'BEGIN { split("-2064109315 -1916708911 -1610009447 -1839426456 -1682065689 -376575756 -336486068", a, " "); for (i in a) ids[a[i]]=1 } ($1 in ids) { found++; if ($12 != "" || $13 ~ /(gcw[.]static_base|travel[.]|collection[.]gcw|scriptString)/) exit 2 } END { if (found != 7) exit 3 }' "$work_static_buildout_talus"
awk -F '\t' 'BEGIN { split("-1946025983 -949623093 -1925852435 -1288314132 -1202557081 -1156051021 -859124609", a, " "); for (i in a) ids[a[i]]=1 } ($1 in ids) { found++; if ($12 != "" || $13 ~ /(gcw[.]static_base|travel[.]|collection[.]gcw|scriptString)/) exit 2 } END { if (found != 7) exit 3 }' "$work_static_buildout_naboo"
javap -classpath "$class_root" -c -p script.library.xp | grep -Fq 'getPrecuFactionKillRecipient'
! javap -classpath "$class_root" -v script.library.xp | grep -Fq 'grantModifiedGcwPoints'
! javap -classpath "$class_root" -v script.library.xp | grep -Fq 'GCW_POINT_TYPE_GROUND_PVE'
! javap -classpath "$class_root" -v script.library.pclib | grep -Fq 'releaseGcwPointCredit'
! javap -classpath "$class_root" -v script.library.pclib | grep -Fq 'ACCT_CLONING'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'cloning_sickness'
! javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'TRIAL_LEVEL_CAP'
javap -classpath "$class_root" -c script.player.base.base_player | grep -Fq 'grantUnmodifiedExperienceOnSelf'
javap -classpath "$class_root" -constants script.player.player_utility | grep -Fq 'PRECU_SCOUT_FORAGE_DELAY = 8.5f'
javap -classpath "$class_root" -constants script.player.player_utility | grep -Fq 'PRECU_SCOUT_FORAGE_BASE_ACTION = 50'
javap -classpath "$class_root" -constants script.player.player_utility | grep -Fq 'PRECU_SCOUT_FORAGE_AREA_USES = 3'
javap -classpath "$class_root" -v script.player.player_utility | grep -Fq 'outdoors_scout_camp_01'
javap -classpath "$class_root" -v script.player.player_utility | grep -Fq 'getPrecuScoutForageActionCost'
javap -classpath "$class_root" -v script.player.player_utility | grep -Fq 'reservePrecuScoutForageArea'
javap -classpath "$class_root" -v script.player.player_utility | grep -Fq 'item_treasure_map_1_10'
! javap -classpath "$class_root" -v script.player.player_utility | grep -Fq 'script/library/loot.playerForaging'
loot_add_bytecode="$(javap -classpath "$class_root" -c script.library.loot | sed -n '/public static boolean addLoot/,/public static boolean addGoldenTicket/p')"
printf '%s' "$loot_add_bytecode" | grep -Fq 'setupLootItems'
printf '%s' "$loot_add_bytecode" | grep -Fq 'addCollectionLoot'
! printf '%s' "$loot_add_bytecode" | grep -Fq 'addRareLoot'
! printf '%s' "$loot_add_bytecode" | grep -Fq 'addBeastEnzymes'
javap -classpath "$class_root" -v script.library.loot | grep -Fq 'Rejected retired NGE Beast Master forage loot pipeline'
javap -classpath "$class_root" -v script.library.loot | grep -Fq 'getPrecuEncounterDifficulty'
! javap -classpath "$class_root" -v script.ai.ai | grep -Fq 'addChronicleLoot'
! javap -classpath "$class_root" -v script.ai.ai | grep -Fq 'scheduled_drop'
javap -classpath "$class_root" -v script.ai.ai | grep -Fq 'goldenTicket'
javap -classpath "$class_root" -v script.quest.task.ground.spawn | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.quest.util.dynamic_mob_opponent | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.quest.utility.dynamic_spawn_off_quest_item | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.systems.spawning.spawn_base | grep -Fq 'getGroupLevel'
javap -classpath "$class_root" -v script.systems.treasure_map.base.treasure_map | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.systems.tcg.target_creature | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.theme_park.meatlump.hideout.mtp_instance_entrance_cell | grep -Fq 'getPrecuEncounterDifficulty'
! javap -classpath "$class_root" -v script.theme_park.meatlump.hideout.mtp_instance_entrance_cell | grep -Fq 'getLevel'
grep -Fq 'getLevel(self)' "$work_script/systems/tcg/target_creature.java"
! grep -Fq 'getLevel(owner)' "$work_script/systems/tcg/target_creature.java"
javap -classpath "$class_root" -v script.theme_park.meatlump.quest_shuttle_comlink | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.theme_park.outbreak.dynamic_spawn_off_quest_item | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.ai.ai | grep -Fq 'getPrecuEncounterDifficulty'
! javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'getLevel'
mission_dynamic_bytecode="$(javap -classpath "$class_root" -c -p script.systems.missions.base.mission_dynamic_base)"
test "$(printf '%s' "$mission_dynamic_bytecode" | grep -Fc 'Method script/library/skill.getPrecuEncounterDifficulty')" -eq 2
! printf '%s' "$mission_dynamic_bytecode" | grep -Fq 'Method getLevel'
! javap -classpath "$class_root" -c -p script.systems.missions.dynamic.mission_escort_npc | grep -Fq 'Method getLevel'
javap -classpath "$class_root" -v script.ai.familiar | grep -Fq 'removePetBuff'
! javap -classpath "$class_root" -v script.ai.familiar | grep -Fq 'getLevel'
! grep -Fq 'buff.applyBuff' "$work_script/ai/familiar.java"
grep -Fq 'buff.removeBuff(master, numbuff)' "$work_script/ai/familiar.java"
javap -classpath "$class_root" -constants script.systems.crafting.droid.modules.droid_bomb | grep -Fq 'PRECU_DETONATION_MIN_DAMAGE = 150'
javap -classpath "$class_root" -constants script.systems.crafting.droid.modules.droid_bomb | grep -Fq 'PRECU_DETONATION_MAX_DAMAGE = 200'
javap -classpath "$class_root" -constants script.systems.crafting.droid.modules.droid_bomb | grep -Fq 'PRECU_DETONATION_RADIUS = 17'
javap -classpath "$class_root" -constants script.systems.crafting.droid.modules.droid_bomb | grep -Fq 'PRECU_PLAYER_DAMAGE_MULTIPLIER = 0.25f'
! javap -classpath "$class_root" -v script.systems.crafting.droid.modules.droid_bomb | grep -Fq 'getLevel'
javap -classpath "$class_root" -constants script.library.pet_lib | grep -Fq 'DETONATION_DROID_MIN_DAMAGE = 150'
javap -classpath "$class_root" -constants script.library.pet_lib | grep -Fq 'DETONATION_DROID_MAX_DAMAGE = 200'
javap -classpath "$class_root" -c script.ai.pet | grep -Eq 'sipush[[:space:]]+150'
javap -classpath "$class_root" -c script.ai.pet | grep -Eq 'sipush[[:space:]]+200'
javap -classpath "$class_root" -c script.ai.pet_control_device | grep -Fq 'getDetonationDroidMinDamage'
javap -classpath "$class_root" -c script.ai.pet_control_device | grep -Fq 'getDetonationDroidMaxDamage'
javap -classpath "$class_root" -c script.npc.pet_deed.droid_deed | grep -Fq 'getDetonationDroidMinDamage'
javap -classpath "$class_root" -c script.npc.pet_deed.droid_deed | grep -Fq 'getDetonationDroidMaxDamage'
javap -classpath "$class_root" -constants script.library.innate | grep -Fq 'DURATION_VIT = 600.0f'
! javap -classpath "$class_root" -v script.library.innate | grep -Fq 'VALUE_EQUALIZE_AMOUNT'
equalize_bytecode="$(javap -classpath "$class_root" -c -p script.library.innate | sed -n '/equalizeEffect/,/doAntiModCheck/p')"
printf '%s' "$equalize_bytecode" | grep -Fq 'idiv'
test "$(printf '%s' "$equalize_bytecode" | grep -Fc 'Method addAttribModifier')" -eq 3
javap -classpath "$class_root" -v script.player.species_innate | grep -Fq 'private_innate_regeneration'
javap -classpath "$class_root" -v script.player.species_innate | grep -Fq 'private_innate_vitalize'
javap -classpath "$class_root" -v script.player.species_innate | grep -Fq 'private_innate_equilibrium'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'private_innate_roar'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'wookieeRoar'
grep -Fq 'datastorage * pet_lib.DETONATION_DROID_MIN_DAMAGE' "$work_script/ai/pet.java"
grep -Fq 'datastorage * pet_lib.getDetonationDroidMinDamage()' "$work_script/ai/pet_control_device.java"
grep -Fq 'datastorage * pet_lib.getDetonationDroidMinDamage()' "$work_script/npc/pet_deed/droid_deed.java"
grep -Fq 'int target_min_damage = min_dam' "$work_script/systems/crafting/droid/modules/droid_bomb.java"
grep -Fq 'getAttackableTargetsInRadius(droid, PRECU_DETONATION_RADIUS, true)' "$work_script/systems/crafting/droid/modules/droid_bomb.java"
javap -classpath "$class_root" -constants script.item.survey_tool.survey_tool_script | grep -Fq 'PRECU_SAMPLE_ACTION_BASE_COST = 124'
javap -classpath "$class_root" -constants script.item.survey_tool.survey_tool_script | grep -Fq 'PRECU_SAMPLE_QUICKNESS_DIVISOR = 12.5f'
! javap -classpath "$class_root" -v script.item.buff_click_item | grep -Fq 'required_level_for_effect'
! javap -classpath "$class_root" -v script.item.full_heal_item | grep -Fq 'required_level_for_effect'
! javap -classpath "$class_root" -v script.item.levelup_orb.levelup_orb | grep -Fq 'player_level.iff'
! javap -classpath "$class_root" -v script.item.levelup_orb.levelup_orb | grep -Fq 'combat_general'
javap -classpath "$class_root" -v script.item.levelup_orb.levelup_orb | grep -Fq 'item.special.nomove'
javap -classpath "$class_root" -v script.item.levelup_orb.levelup_orb | grep -Fq 'detachScript'
! javap -classpath "$class_root" -v script.item.medicine.stimpack | grep -Fq 'combat_level_required'
! javap -classpath "$class_root" -v script.item.medicine.stimpack_crafted | grep -Fq 'combat_level_required'
javap -classpath "$class_root" -v script.item.plant.force_melon | grep -Fq 'healing.combat_level_required'
javap -classpath "$class_root" -v script.item.plant.force_melon | grep -Fq 'removeObjVar'
javap -classpath "$class_root" -constants script.library.pet_lib | grep -Fq 'MAX_NONCH_PET_LEVEL = 10'
javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'canCallCreaturePet'
javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'outdoors_creaturehandler_novice'
javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'tame_level'
javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'tame_aggro'
javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'control_exceeded'
! javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'MAX_PET_LEVELS_ABOVE_CALLER'
! javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'tame_level_bonus'
javap -classpath "$class_root" -v script.ai.pet_control_device | grep -Fq 'canCallCreaturePet'
! javap -classpath "$class_root" -v script.ai.pet_control_device | grep -Fq 'cant_call_level'
javap -classpath "$class_root" -v script.npc.pet_deed.droid_deed | grep -Fq 'createCraftedCreatureDevice'
! javap -classpath "$class_root" -v script.npc.pet_deed.droid_deed | grep -Fq 'MAX_PET_LEVELS_ABOVE_CALLER'
! javap -classpath "$class_root" -v script.npc.pet_deed.droid_deed | grep -Fq 'SID_SYS_CANT_CALL_LEVEL'
! javap -classpath "$class_root" -v script.npc.pet_deed.droid_deed | grep -Fq 'getLevel'
javap -classpath "$class_root" -v script.theme_park.dungeon.death_watch_bunker.craft_armorsmith_droid | grep -Fq 'crafting_armorsmith_master'
javap -classpath "$class_root" -v script.theme_park.dungeon.death_watch_bunker.craft_jetpack_droid | grep -Fq 'crafting_artisan_master'
javap -classpath "$class_root" -v script.theme_park.dungeon.mustafar_trials.valley_battleground.mining_droid | grep -Fq 'crafting_droidengineer_novice'
javap -classpath "$class_root" -v script.npc.static_quest.quest_armorsmith | grep -Fq 'crafting_armorsmith_master'
! javap -classpath "$class_root" -v script.theme_park.dungeon.death_watch_bunker.craft_armorsmith_droid | grep -Fq 'class_munitions'
! javap -classpath "$class_root" -v script.theme_park.dungeon.death_watch_bunker.craft_jetpack_droid | grep -Fq 'class_engineering'
! javap -classpath "$class_root" -v script.theme_park.dungeon.mustafar_trials.valley_battleground.mining_droid | grep -Fq 'class_engineering'
! javap -classpath "$class_root" -v script.npc.static_quest.quest_armorsmith | grep -Fq 'class_munitions'
grep -Fq 'calculatePrecuAttackTime' "$work_queue"
grep -Fq 'isWeaponCadenceAttack' "$work_queue"
grep -Fq 'if (!owner.isPlayerControlled())' "$work_queue"
grep -Fq 'PreCuCombatCadence' "$work_queue"
grep -Fq 'canHarvestPrecuCreatureResources' "$work_queue"
grep -Fq 'outdoors_scout_novice' "$work_queue"
grep -Fq 'PreCuScoutHarvest' "$work_queue"
grep -Fq 'rejected phase=execute' "$work_queue"
grep -Fq 'primary=%d classified=%d speedSkill=%s familySpeed=%d' "$work_queue"
grep -Fq 'unclassified time=' "$work_queue"
grep -Fq 'm_lastWeaponCadenceAttackTime' "$work_queue_header"
grep -Fq 'm_lastWeaponCadenceInterval' "$work_queue_header"
grep -Fq 'm_lastWeaponCadenceAttackTime = s_currentTime' "$work_queue"
grep -Fq 'm_nextEventTime = earliestAttackTime' "$work_queue"
grep -Fq 'gate time=' "$work_queue"
grep -Fq 'logs/precuCombatCadence.log{c-*:c+PreCuCombatCadence}' "$work_local_options"
grep -Fq 'logs/precuScoutHarvest.log{c-*:c+PreCuScoutHarvest}' "$work_local_options"
grep -Fq 'logs/precuNpcConversation.log{c-*:c+PreCuConversation}' "$work_local_options"
grep -Fq 'logs/precuObjectMenu.log{c-*:c+PreCuObjectMenu}' "$work_local_options"
grep -Fq 'command-start actor=%s target=%s starter=%d result=%d' "$work_commands"
grep -Fq 'recover stale-session player=%s previousNpc=%s requestedNpc=%s' "$work_tangible_conversation"
grep -Fq 'ignored cleanup-veto player=%s npc=%s' "$work_tangible_conversation"
grep -Fq 'session-ended player=%s npc=%s' "$work_tangible_conversation"
grep -Fq 'request actor=%s target=%s sequence=%u clientItems=%u' "$work_player_controller"
grep -Fq 'reason=target-not-authoritative' "$work_player_controller"
grep -Fq 'reason=script-complete' "$work_player_controller"
grep -Fq 'Ignored retired NGE ExpertiseRequestMessage' "$work_client"
! grep -Fq 'ExpertiseRequestMessage const m' "$work_client"
grep -Fq 'isRetiredNgeProgressionSkillName' "$work_creature"
grep -Fq 'Rejected retired NGE expertise request' "$work_creature"
grep -Fq 'clearRetiredNgeProgressionSkills' "$work_creature"
grep -Fq 'm_skills.erase(*iter)' "$work_creature"
grep -Fq 'clearRetiredNgeProgressionSkills' "$work_creature_header"
grep -Fq 'Ignored retired NGE createGroupPickup command' "$work_commands"
grep -Fq 'Ignored retired NGE useGroupPickup command' "$work_commands"
grep -Fq 'return 0;' "$work_group"
grep -Fq 'const uint32_t cs_maximumNumberInGroup = 24;' "$work_group"
grep -Fq 'reuseableWp.groupPickupWp' "$work_player"
grep -Fq 'normalizePrecuAttackSpeed' "$work_weapon"
grep -Fq 'getStoredAttackTime' "$work_weapon_header"
awk -F '	' '$1 ~ /^harvestCorpse$/ { found=1; if ($9 !~ /^harvestCorpse$/) exit 2 } END { if (!found) exit 3 }' "$work_command_table"
awk -F '	' '$1 ~ /^species_(bothan|human|moncal|rodian|trandoshan|twilek|wookiee|zabrak|ithorian|sullustan)$/ { found++; if ($23 ~ /creature_harvesting/) exit 2 } END { if (found != 10) exit 3 }' "$work_skills"
awk -F '	' '$1 ~ /^outdoors_scout_novice$/ { found=1; if ($22 !~ /harvestCorpse/ || $23 !~ /creature_harvesting=15/) exit 2 } END { if (!found) exit 3 }' "$work_skills"
awk -F '	' '$1 ~ /^species_(bothan|human|moncal|rodian|trandoshan|twilek|wookiee|zabrak|ithorian|sullustan)$/ { found++; if ($22 ~ /_ability_1/ || $23 ~ /_ability_1|creature_harvesting/) exit 2; expected["species_bothan"]="camouflage=15,take_cover=10"; expected["species_human"]="leadership=10,general_experimentation=15"; expected["species_moncal"]="alert=15,weapon_assembly=10,structure_assembly=10"; expected["species_rodian"]="blind_defense=15,onehandmelee_accuracy=10,twohandmelee_accuracy=10,weapon_assembly=10"; expected["species_trandoshan"]="unarmed_accuracy=10,unarmed_speed=5,unarmed_damage=15,melee_defense=10,private_innate_regeneration=1"; expected["species_twilek"]="healing_dance_wound=15,healing_music_wound=5,healing_dance_shock=15,healing_music_shock=5"; expected["species_wookiee"]="trapping=10,tame_bonus=10,rescue=10,warcry=10,private_innate_roar=1"; expected["species_zabrak"]="dizzy_defense=10,stun_defense=10,intimidate_defense=10,anti_shock=5,private_innate_equilibrium=1,private_innate_vitalize=1"; expected["species_ithorian"]="dizzy_defense=10,stun_defense=10,tame_bonus=10,melee_defense=10,chassis_assembly=10,power_systems=10,shields_assembly=10,advanced_assembly=10"; expected["species_sullustan"]="engine_assembly=10,booster_assembly=10,weapon_systems=10,trapping=10"; value=$23; gsub(/^"|"$/, "", value); if (value != expected[$1]) exit 4; if ($1 == "species_trandoshan" && $22 !~ /regeneration/) exit 5; if ($1 == "species_wookiee" && $22 !~ /wookieeRoar/) exit 6; if ($1 == "species_zabrak" && ($22 !~ /vitalize/ || $22 !~ /equilibrium/)) exit 7 } END { if (found != 10) exit 3 }' "$work_skills"
awk -F '	' '$1 == "regeneration" { r++; if ($87 != "innate_regeneration" || $90 != 3600) exit 2 } $1 == "vitalize" { v++; if ($87 != "innate_vitalize" || $90 != 3600) exit 3 } $1 == "equilibrium" { e++; if ($87 != "innate_equilibrium" || $90 != 3600) exit 4 } $1 == "wookieeRoar" { w++; if ($2 != "combat" || $74 != "enemy" || $75 != "required" || $79 != "combat_general" || $83 != "combat" || $84 != 1 || $85 != "ALL" || $87 != "innate_roar" || $88 != 0 || $89 != 1 || $90 != 300) exit 5 } END { if (r != 1 || v != 1 || e != 1 || w != 1) exit 6 }' "$work_command_table"
awk -F '	' '$1 == "innate_regeneration" { r++; if ($7 != 300 || $8 != "constitution" || $9 != 175) exit 2 } $1 == "innate_vitalize" { v++; if ($7 != 600 || $8 != "health" || $9 != 50 || $10 != "action" || $11 != 50 || $12 != "mind" || $13 != 50) exit 3 } $1 == "innate_wookiee_roar" { w++; if ($8 != "" || $10 != "" || $12 != "" || $14 != "" || $16 != "") exit 4 } END { if (r != 1 || v != 1 || w != 1) exit 5 }' "$work_buff_table"
awk -F '	' '$1 == "wookieeRoar" { found++; if ($42 != "CONE" || $43 != 15 || $44 != 90 || $46 != 15 || $56 != 0 || $57 != 0 || $59 != 0 || $82 != "UNARMED" || $83 != "MELEE_WEAPON" || $92 != "ACTION_NAME") exit 2 } END { if (found != 1) exit 3 }' "$work_combat_data"
awk -F '	' '$1 == "wookieeRoar" { found++; if ($5 != "NO_ATTRIBUTE" || $11 != "INTIMIDATE" || $12 != 100 || $14 != 60 || $15 != "intimidate_defense" || $16 != "jedi_state_defense" || $17 != "resistance_states" || $38 != "intimidate") exit 2 } END { if (found != 1) exit 3 }' "$work_combat_overrides"
awk -F '	' '$1 ~ /^kreetle$/ { found=1; if ($3 != 3 || $5 != 35 || $6 != 45 || $8 != 90 || $9 != 110) exit 2 } END { if (!found) exit 3 }' "$work_creature_profiles"
awk -F '	' '$1 ~ /^lesser_desert_womprat$/ { found=1; if ($2 !~ /^lesser_desert_womp_rat$/ || $3 != 5 || $5 != 45 || $6 != 50) exit 2 } END { if (!found) exit 3 }' "$work_creature_profiles"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_speeds.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_profiles.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/skill/skills.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/command/command_table.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/buff/buff.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/datatables/mob/precu_creature_combat_profiles.iff"
nm -C "$server_game_archive" | grep -Fq 'WeaponObjectNamespace::normalizePrecuAttackSpeed'
nm -C "$server_game_archive" | grep -Fq 'WeaponObject::getAttackTime() const'
nm -C "$server_game_archive" | grep -Fq 'CreatureObject::processExpertiseRequest'
nm -C "$server_game_archive" | grep -Fq 'CreatureObject::clearRetiredNgeProgressionSkills()'
nm -C "$server_game_archive" | grep -Fq 'GroupObject::getSecondsLeftOnGroupPickup() const'
nm -C "$server_game_archive" | grep -Fq 'TangibleObject::startNpcConversation'
nm -C "$server_game_archive" | grep -Fq 'TangibleObject::endNpcConversation()'
nm -C "$server_game_archive" | grep -Fq 'PlayerObject::retirePostNgeGcwRatingState()'
strings "$server_game_archive" | grep -Fq 'recover stale-session player=%s previousNpc=%s requestedNpc=%s'
strings "$server_game_archive" | grep -Fq 'request actor=%s target=%s sequence=%u clientItems=%u'
strings "$binary" | grep -Fq '_pvpSetPrecuFactionRank'
file -L "$binary" | grep -F 'ELF 64-bit' >/dev/null
'@

Write-Host "Verifying synchronized sources, PRE-CU GCW retirement, Scout bytecode, native NGE retirement, authoritative weapon cadence, and x64 architecture..."
Invoke-DockerScript -ContainerName $Container -Script $artifactProbe

$restartAt = [DateTimeOffset]::UtcNow.ToString("o")
Write-Host "Restarting '$Container' only after artifact verification..."
Invoke-Docker -Arguments @("restart", $Container)

$deadline = [DateTimeOffset]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
$clusterReady = $false
do
{
    $state = (& docker inspect --format "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $Container).Trim()
    if ($LASTEXITCODE -ne 0)
    {
        throw "Unable to read state for '$Container'."
    }

    if ($state -like "running healthy*")
    {
        $logs = (& docker logs --since $restartAt $Container 2>&1 | Out-String)
        if ($logs.Contains("Cluster swg is ready for players."))
        {
            $clusterReady = $true
            break
        }
    }

    Start-Sleep -Seconds 5
}
while ([DateTimeOffset]::UtcNow -lt $deadline)

if (-not $clusterReady)
{
    throw "'$Container' did not report a healthy, player-ready cluster within $ReadyTimeoutSeconds seconds."
}

$runtimeConfigProbe = @'
set -eu
cfg="$SWG_WORK_DIR/exe/linux/localOptions.cfg"
grep -Fq 'clusterName=swg' "$cfg"
grep -Eq '^transferServerAddress=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$cfg"
grep -Fq '### BEGIN Docker runtime overrides' "$cfg"
'@
Write-Host "Verifying the restarted server rendered its runtime configuration..."
Invoke-DockerScript -ContainerName $Container -Script $runtimeConfigProbe

Write-Host "Verifying a live game process mapped the newly built server binary..."
$gamePids = @(& docker exec $Container pgrep -f "bin/SwgGameServer")
if ($LASTEXITCODE -ne 0 -or $gamePids.Count -eq 0)
{
    throw "No live SwgGameServer process was found in '$Container'."
}
$gamePid = [string]($gamePids | Select-Object -First 1)
$workDir = (& docker exec $Container printenv SWG_WORK_DIR).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($workDir))
{
    throw "Unable to resolve SWG_WORK_DIR in '$Container'."
}
$processInode = (& docker exec $Container stat -Lc "%i" "/proc/$gamePid/exe").Trim()
$binaryInode = (& docker exec $Container stat -Lc "%i" "$workDir/build/bin/SwgGameServer").Trim()
$processSize = (& docker exec $Container stat -Lc "%s" "/proc/$gamePid/exe").Trim()
$binarySize = (& docker exec $Container stat -Lc "%s" "$workDir/build/bin/SwgGameServer").Trim()
if ($LASTEXITCODE -ne 0 -or $processInode -cne $binaryInode -or $processSize -cne $binarySize)
{
    throw "Live SwgGameServer process $gamePid does not map the newly built binary."
}
Write-Host "PRE-CU server deployment passed: synchronized, x64, healthy, and ready for players."
