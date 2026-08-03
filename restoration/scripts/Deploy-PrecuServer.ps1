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

if (-not $SkipBuild)
{
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
source_factions_library="$source_script/library/factions.java"
work_factions_library="$work_script/library/factions.java"
source_faction_perk_library="$source_script/library/faction_perk.java"
work_faction_perk_library="$work_script/library/faction_perk.java"
source_gcw_library="$source_script/library/gcw.java"
work_gcw_library="$work_script/library/gcw.java"
source_gcw_city="$source_script/systems/gcw/gcw_city.java"
work_gcw_city="$work_script/systems/gcw/gcw_city.java"
source_planet_base="$source_script/planet/planet_base.java"
work_planet_base="$work_script/planet/planet_base.java"
source_live_conversions="$source_script/player/live_conversions.java"
work_live_conversions="$work_script/player/live_conversions.java"
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
source_utils_library="$source_script/library/utils.java"
work_utils_library="$work_script/library/utils.java"
source_stealth_library="$source_script/library/stealth.java"
work_stealth_library="$work_script/library/stealth.java"
source_luck_library="$source_script/library/luck.java"
work_luck_library="$work_script/library/luck.java"
source_crafting_library="$source_script/library/craftinglib.java"
work_crafting_library="$work_script/library/craftinglib.java"
source_weapons_library="$source_script/library/weapons.java"
work_weapons_library="$work_script/library/weapons.java"
source_combat_weapon="$source_script/systems/combat/combat_weapon.java"
work_combat_weapon="$work_script/systems/combat/combat_weapon.java"
source_mission_base="$source_script/systems/missions/base/mission_base.java"
work_mission_base="$work_script/systems/missions/base/mission_base.java"
source_mission_dynamic="$source_script/systems/missions/base/mission_dynamic_base.java"
work_mission_dynamic="$work_script/systems/missions/base/mission_dynamic_base.java"
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
precu_encounter_difficulty_paths="ai/ai.java quest/task/ground/spawn.java quest/util/dynamic_mob_opponent.java quest/utility/dynamic_spawn_off_quest_item.java systems/spawning/spawn_base.java systems/treasure_map/base/treasure_map.java theme_park/meatlump/quest_shuttle_comlink.java theme_park/outbreak/dynamic_spawn_off_quest_item.java"
precu_retained_system_level_paths="ai/imperial_presence/harass.java city/imperial_crackdown/imperial_trouble.java event/ewok_festival/loveday_reward_crossbow.java event/halloween/song_book.java event/lost_squadron/stolen_fighter.java library/collection.java library/groundquests.java library/npe.java library/performance.java library/smuggler.java library/space_combat.java library/township.java npc/static_quest/quest_convo.java"
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
cmp -s "$source_missions" "$work_missions"
cmp -s "$source_xp_library" "$work_xp_library"
cmp -s "$source_factions_library" "$work_factions_library"
cmp -s "$source_faction_perk_library" "$work_faction_perk_library"
cmp -s "$source_gcw_library" "$work_gcw_library"
cmp -s "$source_gcw_city" "$work_gcw_city"
cmp -s "$source_planet_base" "$work_planet_base"
cmp -s "$source_live_conversions" "$work_live_conversions"
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
cmp -s "$source_utils_library" "$work_utils_library"
cmp -s "$source_stealth_library" "$work_stealth_library"
cmp -s "$source_luck_library" "$work_luck_library"
cmp -s "$source_crafting_library" "$work_crafting_library"
cmp -s "$source_weapons_library" "$work_weapons_library"
cmp -s "$source_combat_weapon" "$work_combat_weapon"
diff -qr "$source_conversation" "$work_conversation" >/dev/null
diff -qr "$source_theme_park" "$work_theme_park" >/dev/null
! grep -R -E '(^|[^[:alnum:]_.])((combat|utils)\.)?getLevel[[:space:]]*\([[:space:]]*(player|whoTriggeredMe)[[:space:]]*\)' "$work_conversation" "$work_theme_park"
cmp -s "$source_mission_base" "$work_mission_base"
cmp -s "$source_mission_dynamic" "$work_mission_dynamic"
cmp -s "$source_player_utility" "$work_player_utility"
cmp -s "$source_ai" "$work_ai"
cmp -s "$source_base_player" "$work_base_player"
cmp -s "$source_base_class" "$work_base_class"
cmp -s "$source_buff_library" "$work_buff_library"
cmp -s "$source_performcommands" "$work_performcommands"
cmp -s "$source_buff_handler" "$work_buff_handler"
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
for precu_item_level_path in $precu_item_level_paths; do
    cmp -s "$source_script/$precu_item_level_path" "$work_script/$precu_item_level_path"
done
for precu_encounter_difficulty_path in $precu_encounter_difficulty_paths; do
    cmp -s "$source_script/$precu_encounter_difficulty_path" "$work_script/$precu_encounter_difficulty_path"
done
for precu_retained_system_level_path in $precu_retained_system_level_paths; do
    cmp -s "$source_script/$precu_retained_system_level_path" "$work_script/$precu_retained_system_level_path"
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
# Publish 14.1 Creature Handler remains authoritative. Retain Beast Master
# assets for later-content loading but retire their player combat runtime.
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'isPostNgeBeastMasterPlayerRuntimeRetired'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'bm_player_buff'
javap -classpath "$class_root" -v script.ai.beast_control_device | grep -Fq 'isRetiredPostNgeBeastMasterPlayer'
javap -classpath "$class_root" -v script.player.player_beastmaster | grep -Fq 'handleRetirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeBeastMasterPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeBeastMasterPlayer'
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
javap -classpath "$class_root" -v script.conversation.corellia_coronet_vani_korr | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.conversation.imperial_defensive_supply_terminal | grep -Fq 'getPrecuCraftingContentDifficulty'
javap -classpath "$class_root" -v script.conversation.som_pei_yi | grep -Fq 'getPrecuEntertainerContentDifficulty'
javap -classpath "$class_root" -v script.theme_park.outbreak.camp_defense | grep -Fq 'getPrecuEncounterDifficulty'
! javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getGroupObjectLevel'
javap -classpath "$class_root" -v script.library.groundquests | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.npc.static_quest.quest_convo | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.library.collection | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.library.space_combat | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.library.space_combat | grep -Fq 'grantCombatStyleXp'
javap -classpath "$class_root" -v script.library.performance | grep -Fq 'getPrecuEntertainerContentDifficulty'
javap -classpath "$class_root" -v script.event.halloween.song_book | grep -Fq 'getPrecuEntertainerContentDifficulty'
javap -classpath "$class_root" -c -p script.library.utils | grep -Fq 'testItemLevelRequirements'
javap -classpath "$class_root" -v script.library.utils | grep -Fq 'isPrecuRetainedItemClass'
javap -classpath "$class_root" -v script.library.utils | grep -Fq 'outdoors_ranger_novice'
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
javap -classpath "$class_root" -c -p script.systems.combat.combat_base | grep -Fq 'getPrecuWeaponCombatLevel'
javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | grep -Fq 'getPrecuCombatLevel'
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
javap -classpath "$class_root" -v script.library.faction_perk | grep -Fq 'precuFactionPerkPurchase'
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
javap -classpath "$class_root" -v script.theme_park.meatlump.quest_shuttle_comlink | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.theme_park.outbreak.dynamic_spawn_off_quest_item | grep -Fq 'getPrecuEncounterDifficulty'
javap -classpath "$class_root" -v script.ai.ai | grep -Fq 'getPrecuEncounterDifficulty'
! javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'getLevel'
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
awk -F '	' '$1 ~ /^kreetle$/ { found=1; if ($3 != 3 || $5 != 35 || $6 != 45 || $8 != 90 || $9 != 110) exit 2 } END { if (!found) exit 3 }' "$work_creature_profiles"
awk -F '	' '$1 ~ /^lesser_desert_womprat$/ { found=1; if ($2 !~ /^lesser_desert_womp_rat$/ || $3 != 5 || $5 != 45 || $6 != 50) exit 2 } END { if (!found) exit 3 }' "$work_creature_profiles"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_speeds.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_profiles.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/skill/skills.iff"
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
