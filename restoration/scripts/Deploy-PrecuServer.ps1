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
source_missions="$source_script/library/missions.java"
work_missions="$work_script/library/missions.java"
source_skill_library="$source_script/library/skill.java"
work_skill_library="$work_script/library/skill.java"
source_mission_base="$source_script/systems/missions/base/mission_base.java"
work_mission_base="$work_script/systems/missions/base/mission_base.java"
source_mission_dynamic="$source_script/systems/missions/base/mission_dynamic_base.java"
work_mission_dynamic="$work_script/systems/missions/base/mission_dynamic_base.java"
precu_item_level_paths="item/buff_beast_click_item.java item/buff_click_item.java item/full_heal_item.java item/levelup_orb/levelup_orb.java item/medicine/stimpack.java item/medicine/stimpack_crafted.java item/plant/force_melon.java item/skillmod_click_item.java item/static_item_base.java item/survey_tool/survey_tool_script.java library/static_item.java"
precu_encounter_difficulty_paths="ai/ai.java quest/task/ground/spawn.java quest/util/dynamic_mob_opponent.java quest/utility/dynamic_spawn_off_quest_item.java systems/spawning/spawn_base.java systems/treasure_map/base/treasure_map.java theme_park/meatlump/quest_shuttle_comlink.java theme_park/outbreak/dynamic_spawn_off_quest_item.java"
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
cmp -s "$source_combat_player" "$work_combat_player"
cmp -s "$source_ai_corpse" "$work_ai_corpse"
cmp -s "$source_combat_overrides" "$work_combat_overrides"
cmp -s "$source_weapon_profiles" "$work_weapon_profiles"
cmp -s "$source_queue" "$work_queue"
cmp -s "$source_queue_header" "$work_queue_header"
cmp -s "$source_commands" "$work_commands"
cmp -s "$source_tangible_conversation" "$work_tangible_conversation"
cmp -s "$source_player_controller" "$work_player_controller"
cmp -s "$source_client" "$work_client"
cmp -s "$source_creature" "$work_creature"
cmp -s "$source_creature_header" "$work_creature_header"
cmp -s "$source_group" "$work_group"
cmp -s "$source_player" "$work_player"
cmp -s "$source_weapon" "$work_weapon"
cmp -s "$source_weapon_header" "$work_weapon_header"
cmp -s "$source_speeds" "$work_speeds"
cmp -s "$source_travel" "$work_travel"
cmp -s "$source_player_travel" "$work_player_travel"
cmp -s "$source_command_table" "$work_command_table"
cmp -s "$source_skills" "$work_skills"
cmp -s "$source_missions" "$work_missions"
cmp -s "$source_skill_library" "$work_skill_library"
cmp -s "$source_mission_base" "$work_mission_base"
cmp -s "$source_mission_dynamic" "$work_mission_dynamic"
cmp -s "$source_script/library/pet_lib.java" "$work_script/library/pet_lib.java"
cmp -s "$source_script/ai/pet_control_device.java" "$work_script/ai/pet_control_device.java"
cmp -s "$source_script/npc/pet_deed/droid_deed.java" "$work_script/npc/pet_deed/droid_deed.java"
for precu_item_level_path in $precu_item_level_paths; do
    cmp -s "$source_script/$precu_item_level_path" "$work_script/$precu_item_level_path"
done
for precu_encounter_difficulty_path in $precu_encounter_difficulty_paths; do
    cmp -s "$source_script/$precu_encounter_difficulty_path" "$work_script/$precu_encounter_difficulty_path"
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
# localOptions.cfg is a runtime-rendered configuration, not a copied build
# artifact. Authenticate the immutable template and the required rendered
# values independently instead of demanding impossible byte equality.
grep -Fq 'clusterName=CLUSTERNAME' "$source_local_options"
grep -Fq 'transferServerAddress=HOSTIP' "$source_local_options"
grep -Fq 'clusterName=swg' "$work_local_options"
grep -Eq '^transferServerAddress=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$work_local_options"
grep -Fq '### BEGIN Docker runtime overrides' "$work_local_options"
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
! javap -classpath "$class_root" -v script.library.skill | grep -Fq 'getGroupObjectLevel'
javap -classpath "$class_root" -v script.library.missions | grep -Fq 'getPrecuCombatSkillScore'
! javap -classpath "$class_root" -v script.library.missions | grep -Fq 'getLevel'
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
strings "$server_game_archive" | grep -Fq 'recover stale-session player=%s previousNpc=%s requestedNpc=%s'
strings "$server_game_archive" | grep -Fq 'request actor=%s target=%s sequence=%u clientItems=%u'
file -L "$binary" | grep -F 'ELF 64-bit' >/dev/null
'@

Write-Host "Verifying synchronized sources, Scout bytecode, native NGE retirement, authoritative weapon cadence, and x64 architecture..."
Invoke-Docker -Arguments @("exec", $Container, "sh", "-lc", $artifactProbe)

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
