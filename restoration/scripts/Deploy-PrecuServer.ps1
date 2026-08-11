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
Write-Host "Verifying Publish 14 authoritative weapon speeds and authored default-unarmed cadence before build..."
& (Join-Path $PSScriptRoot "Test-P14AuthoritativeWeaponSpeeds.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying Publish 14 PRE-CU faction and cloning authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuFactionCloningAuthority.ps1") `
    -SourceRoot $repositoryRoot
Write-Host "Verifying direct-source post-NGE Beast Master player-runtime retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgeBeastMasterPlayerRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the player-owned retained-content controller closure before build..."
& (Join-Path $PSScriptRoot "Test-P14PlayerOwnedRetainedContentControllerClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the data-grant and persistence closure before build..."
& (Join-Path $PSScriptRoot "Test-P14DataGrantPersistenceClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying authentic Publish 14 camp XP routing before build..."
& (Join-Path $PSScriptRoot "Test-P14ExplicitXpRouting.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the native healing-received observer and wound authority before build..."
& (Join-Path $PSScriptRoot "Test-P14Wounds.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying camp-observer cardinality across PRE-CU medical actions before build..."
& (Join-Path $PSScriptRoot "Test-P14HealDamageCommand.ps1") -SourceRoot $repositoryRoot -Expectation Build
& (Join-Path $PSScriptRoot "Test-P14MedicineConsumption.ps1") -SourceRoot $repositoryRoot -Expectation Build
& (Join-Path $PSScriptRoot "Test-P14TendingCommands.ps1") -SourceRoot $repositoryRoot -Expectation Build
& (Join-Path $PSScriptRoot "Test-P14QuickHealCommand.ps1") -SourceRoot $repositoryRoot -Expectation Build
& (Join-Path $PSScriptRoot "Test-P14RevivePlayerCommand.ps1") -SourceRoot $repositoryRoot -Expectation Build
& (Join-Path $PSScriptRoot "Test-P14HealMindCommand.ps1") -SourceRoot $repositoryRoot -Expectation Build
& (Join-Path $PSScriptRoot "Test-P14PrecuAuthoredHealingBuffAuthority.ps1") -SourceRoot $repositoryRoot -Expectation Source
Write-Host "Verifying camp control-panel faction isolation and owner disband continuity before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuFactionPerkAuthority.ps1") -SourceRoot $repositoryRoot
Write-Host "Verifying PRE-CU Force-sensitive Village quest authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuVillageQuestAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying retained NPE combat-level guidance retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14NpeCombatLevelGuidanceRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying NPE class progression and profession reward retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14NpeClassProgressionRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying post-NGE Rare Loot player-runtime retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgeRareLootPlayerRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying post-Publish-14 armor conversion retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostP14ArmorConversionRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying post-Publish-14 veteran respec item retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostP14VeteranRespecItemRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying post-NGE player XP-buff admission retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgePlayerXpBuffAdmissionRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the complete PRE-CU TCG instant-XP compatibility adapter before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuTcgInstantXpAdapter.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying direct-source post-NGE Beast Master creation-runtime retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgeBeastMasterCreationPlayerRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying direct-source PRE-CU cosmetic-familiar authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuCosmeticFamiliarAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying post-NGE Spy player-runtime retirement against current direct source before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgeSpyPlayerRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot
Write-Host "Verifying PRE-CU mobile stealth, theft, decoy difficulty, and post-Publish-14 player-invisibility retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuMobileStealthDetectionAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying PRE-CU Restuss admission authority against current direct source before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuRestussAdmissionAuthority.ps1") `
    -SourceRoot $repositoryRoot
Write-Host "Verifying the direct-source PRE-CU combat routing closure before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuCombatRoutingClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU Center of Being lifecycle before build..."
& (Join-Path $PSScriptRoot "Test-P14CenterOfBeingLifecycle.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the direct-source PRE-CU Teras Kasi ability branch before build..."
& (Join-Path $PSScriptRoot "Test-P14Core3UnarmedAbilityBranchClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying pinned Core3 damage and NGE kill-meter player isolation before build..."
& (Join-Path $PSScriptRoot "Test-P14Core3DamageAuthority.ps1") `
    -SourceRoot $repositoryRoot
Write-Host "Verifying the direct-source PRE-CU profession and Officer runtime authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuProfessionAuthorityClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying direct-source post-NGE passive profession runtime retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgePassiveProfessionRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying direct-source post-NGE droid combat-module runtime retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgeDroidCombatModuleRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source command callback inventory closure before build..."
& (Join-Path $PSScriptRoot "Test-P14DirectCommandCallbackInventoryClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying direct-source post-NGE player proc runtime retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgePlayerProcRuntimeRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying direct-source NGE expertise admission retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14NgeExpertiseAdmissionRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the complete Java expertise literal inventory before build..."
& (Join-Path $PSScriptRoot "Test-P14JavaExpertiseLiteralCallsiteInventoryClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the complete Java combatLevel textual inventory before build..."
& (Join-Path $PSScriptRoot "Test-P14JavaCombatLevelTextualInventoryClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the complete Java explicit NGE textual inventory before build..."
& (Join-Path $PSScriptRoot "Test-P14JavaExplicitNgeTextualInventoryClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the complete Java roadmap textual inventory before build..."
& (Join-Path $PSScriptRoot "Test-P14JavaRoadmapTextualInventoryClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the complete Java skill-grant callback inventory before build..."
& (Join-Path $PSScriptRoot "Test-P14JavaSkillGrantCallbackInventoryClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the complete native explicit NGE textual inventory before build..."
& (Join-Path $PSScriptRoot "Test-P14NativeExplicitNgeTextualInventoryClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the direct-source PRE-CU zone transition level authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuZoneTransitionLevelAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying the direct-source PRE-CU dynamic mission difficulty authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuDynamicMissionDifficultyAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying PRE-CU player-bounty skill and level authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuPlayerBountyLevelAuthority.ps1") -SourceRoot $repositoryRoot -Expectation Source
Write-Host "Verifying PRE-CU authored AI aggro-radius authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuAiAggroRadiusAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Source
Write-Host "Verifying kill-triggered creature level-up retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuCreatureLevelUpRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying the complete native getLevel callsite inventory before build..."
& (Join-Path $PSScriptRoot "Test-P14NativeGetLevelCallsiteInventoryClosure.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying direct-source post-NGE buff progression retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14PostNgeBuffProgressionRetirement.ps1") `
    -SourceRoot $repositoryRoot
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
Write-Host "Verifying the direct-source PRE-CU item-level and dynamic-loot authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuItemLevelRetirement.ps1") `
    -SourceRoot $repositoryRoot
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
Write-Host "Verifying player-facing NGE respec and veteran migration retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14RespecAutolevelEntrypointRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying canonical PRE-CU admin and test-center skill authority before build..."
& (Join-Path $PSScriptRoot "Test-P14PrecuAdminSkillAuthority.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying Java player-level table service retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14JavaPlayerLevelTableServiceRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
& (Join-Path $PSScriptRoot "Test-P14PostNgePlayerMigrationAuthorityRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build
Write-Host "Verifying native NGE skill and blank-ability command admission retirement before build..."
& (Join-Path $PSScriptRoot "Test-P14NativeNgeSkillAdmissionRetirement.ps1") `
    -SourceRoot $repositoryRoot `
    -Expectation Build

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
source_commands_header="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.h"
work_commands_header="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.h"
source_connection_server="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/network/ConnectionServerConnection.cpp"
work_connection_server="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/network/ConnectionServerConnection.cpp"
source_tangible_conversation="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/TangibleObject_Conversation.cpp"
work_tangible_conversation="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/TangibleObject_Conversation.cpp"
source_player_controller="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/controller/PlayerCreatureController.cpp"
work_player_controller="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/controller/PlayerCreatureController.cpp"
source_creature_controller="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/controller/CreatureController.cpp"
work_creature_controller="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/controller/CreatureController.cpp"
source_script_methods_pvp="$SWG_SOURCE_DIR/src/engine/server/library/serverScript/src/shared/ScriptMethodsPvp.cpp"
work_script_methods_pvp="$SWG_WORK_DIR/src/engine/server/library/serverScript/src/shared/ScriptMethodsPvp.cpp"
source_script_methods_attributes="$SWG_SOURCE_DIR/src/engine/server/library/serverScript/src/shared/ScriptMethodsAttributes.cpp"
work_script_methods_attributes="$SWG_WORK_DIR/src/engine/server/library/serverScript/src/shared/ScriptMethodsAttributes.cpp"
source_script_function_header="$SWG_SOURCE_DIR/src/engine/server/library/serverScript/src/shared/ScriptFunctionTable.h"
work_script_function_header="$SWG_WORK_DIR/src/engine/server/library/serverScript/src/shared/ScriptFunctionTable.h"
source_script_function_table="$SWG_SOURCE_DIR/src/engine/server/library/serverScript/src/shared/ScriptFunctionTable.cpp"
work_script_function_table="$SWG_WORK_DIR/src/engine/server/library/serverScript/src/shared/ScriptFunctionTable.cpp"
source_alter_attribute_message_header="$SWG_SOURCE_DIR/src/engine/server/library/serverNetworkMessages/src/shared/gameGameServer/MessageQueueAlterAttribute.h"
work_alter_attribute_message_header="$SWG_WORK_DIR/src/engine/server/library/serverNetworkMessages/src/shared/gameGameServer/MessageQueueAlterAttribute.h"
source_alter_attribute_message="$SWG_SOURCE_DIR/src/engine/server/library/serverNetworkMessages/src/shared/gameGameServer/MessageQueueAlterAttribute.cpp"
work_alter_attribute_message="$SWG_WORK_DIR/src/engine/server/library/serverNetworkMessages/src/shared/gameGameServer/MessageQueueAlterAttribute.cpp"
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
source_unarmed_default="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/object/weapon/melee/unarmed/unarmed_default_player.tpf"
work_unarmed_default="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/object/weapon/melee/unarmed/unarmed_default_player.tpf"
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
source_buff_effect_mapping="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/buff/effect_mapping.tab"
work_buff_effect_mapping="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/buff/effect_mapping.tab"
source_collection_rewards="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/collection/rewards.tab"
work_collection_rewards="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/collection/rewards.tab"
source_combat_data="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
work_combat_data="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
source_proc_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/proc/proc.tab"
work_proc_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/proc/proc.tab"
source_item_sets="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/item_sets.tab"
work_item_sets="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/item_sets.tab"
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
source_pvp_aura_controller="$source_script/player/gcw/pvp_aura_buff_controller.java"
work_pvp_aura_controller="$work_script/player/gcw/pvp_aura_buff_controller.java"
source_faction_perk_library="$source_script/library/faction_perk.java"
work_faction_perk_library="$work_script/library/faction_perk.java"
source_jedi_saber_component="$source_script/systems/jedi/jedi_saber_component.java"
work_jedi_saber_component="$work_script/systems/jedi/jedi_saber_component.java"
source_gcw_library="$source_script/library/gcw.java"
work_gcw_library="$work_script/library/gcw.java"
source_gcw_city="$source_script/systems/gcw/gcw_city.java"
work_gcw_city="$work_script/systems/gcw/gcw_city.java"
source_gcw_city_pylon="$source_script/systems/gcw/gcw_city_pylon.java"
work_gcw_city_pylon="$work_script/systems/gcw/gcw_city_pylon.java"
source_gcw_supply_terminal="$source_script/terminal/gcw_supply_terminal.java"
work_gcw_supply_terminal="$work_script/terminal/gcw_supply_terminal.java"
source_imperial_general="$source_script/conversation/imperial_general.java"
work_imperial_general="$work_script/conversation/imperial_general.java"
source_rebel_general="$source_script/conversation/rebel_general.java"
work_rebel_general="$work_script/conversation/rebel_general.java"
source_imperial_offensive_supply="$source_script/conversation/imperial_offensive_supply_terminal.java"
work_imperial_offensive_supply="$work_script/conversation/imperial_offensive_supply_terminal.java"
source_imperial_defensive_supply="$source_script/conversation/imperial_defensive_supply_terminal.java"
work_imperial_defensive_supply="$work_script/conversation/imperial_defensive_supply_terminal.java"
source_rebel_offensive_supply="$source_script/conversation/rebel_offensive_supply_terminal.java"
work_rebel_offensive_supply="$work_script/conversation/rebel_offensive_supply_terminal.java"
source_rebel_defensive_supply="$source_script/conversation/rebel_defensive_supply_terminal.java"
work_rebel_defensive_supply="$work_script/conversation/rebel_defensive_supply_terminal.java"
retired_city_asset_runtime_specs="gcw_barricade:9 gcw_damaged_vehicle:8 gcw_npc_hurt:7 gcw_turret:7 gcw_patrol:11 gcw_vehicle_patrol:8 gcw_vehicle_boss_patrol:4 gcw_smuggler_device:5 gcw_tower:9 gcw_defensive_general_boss:5 gcw_entertainer_faction_quest:3 gcw_city_kit:5 gcw_city_kit_barricade:2 gcw_city_kit_damaged_vehicle:3 gcw_city_kit_entertainer:3 gcw_city_kit_medic:3 gcw_city_kit_patrol:2 gcw_city_kit_tower:2 gcw_city_kit_turret:2 gcw_city_kit_vehicle:2 gcw_city_kit_vehicle_boss:2 gcw_patrol_point_npc_ai:2"
source_planet_base="$source_script/planet/planet_base.java"
work_planet_base="$work_script/planet/planet_base.java"
source_live_conversions="$source_script/player/live_conversions.java"
work_live_conversions="$work_script/player/live_conversions.java"
source_respec="$source_script/library/respec.java"
work_respec="$work_script/library/respec.java"
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
source_battlefield_imperial_vendor="$source_script/conversation/imperial_pvp_bf_vendor.java"
work_battlefield_imperial_vendor="$work_script/conversation/imperial_pvp_bf_vendor.java"
source_battlefield_rebel_vendor="$source_script/conversation/rebel_pvp_bf_vendor.java"
work_battlefield_rebel_vendor="$work_script/conversation/rebel_pvp_bf_vendor.java"
source_dsrc_attributes="$SWG_SOURCE_DIR/dsrc/.gitattributes"
work_dsrc_attributes="$SWG_WORK_DIR/dsrc/.gitattributes"
source_creatures_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/mob/creatures.tab"
work_creatures_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/mob/creatures.tab"
source_talus_vendor_buildout="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_3_6.tab"
work_talus_vendor_buildout="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_3_6.tab"
source_rori_vendor_buildout="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/rori/rori_6_1.tab"
work_rori_vendor_buildout="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/buildout/rori/rori_6_1.tab"
source_player_faction="$source_script/player/player_faction.java"
work_player_faction="$work_script/player/player_faction.java"
source_player_utility="$source_script/player/player_utility.java"
work_player_utility="$work_script/player/player_utility.java"
source_force_rank="$source_script/library/force_rank.java"
work_force_rank="$work_script/library/force_rank.java"
source_jedi_trials="$source_script/library/jedi_trials.java"
work_jedi_trials="$work_script/library/jedi_trials.java"
source_frs_recruiter="$source_script/npc/faction_recruiter/player_recruiter.java"
work_frs_recruiter="$work_script/npc/faction_recruiter/player_recruiter.java"
source_player_force_rank="$source_script/systems/gcw/player_force_rank.java"
work_player_force_rank="$work_script/systems/gcw/player_force_rank.java"
source_enclave_controller="$source_script/systems/gcw/enclave_controller.java"
work_enclave_controller="$work_script/systems/gcw/enclave_controller.java"
source_knight_trials="$source_script/theme_park/jedi_trials/knight_trials.java"
work_knight_trials="$work_script/theme_park/jedi_trials/knight_trials.java"
source_force_rank_xp="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank_xp.tab"
work_force_rank_xp="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank_xp.tab"
source_force_rank_light="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank.tab"
work_force_rank_light="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank.tab"
source_force_rank_dark="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank_dark.tab"
work_force_rank_dark="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/pvp/force_rank_dark.tab"
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
source_faction_recruiter_imperial_conversation="$source_script/conversation/faction_recruiter_imperial.java"
work_faction_recruiter_imperial_conversation="$work_script/conversation/faction_recruiter_imperial.java"
source_faction_recruiter_rebel_conversation="$source_script/conversation/faction_recruiter_rebel.java"
work_faction_recruiter_rebel_conversation="$work_script/conversation/faction_recruiter_rebel.java"
source_regional_mission_terminal_spawner="$source_script/systems/gcw/flip_terminal_spawner.java"
work_regional_mission_terminal_spawner="$work_script/systems/gcw/flip_terminal_spawner.java"
source_regional_mission_terminal_template="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/object/tangible/gcw/flip_terminal_spawner.tpf"
work_regional_mission_terminal_template="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/object/tangible/gcw/flip_terminal_spawner.tpf"
source_camp_controlpanel="$source_script/systems/camping/camp_controlpanel.java"
work_camp_controlpanel="$work_script/systems/camping/camp_controlpanel.java"
source_camp_master="$source_script/systems/camping/camp_master.java"
work_camp_master="$work_script/systems/camping/camp_master.java"
source_camping_library="$source_script/library/camping.java"
work_camping_library="$work_script/library/camping.java"
source_pclib_library="$source_script/library/pclib.java"
work_pclib_library="$work_script/library/pclib.java"
source_group_library="$source_script/library/group.java"
work_group_library="$work_script/library/group.java"
source_skill_library="$source_script/library/skill.java"
work_skill_library="$work_script/library/skill.java"
source_proc_library="$source_script/library/proc.java"
work_proc_library="$work_script/library/proc.java"
source_expertise_library="$source_script/library/expertise.java"
work_expertise_library="$work_script/library/expertise.java"
source_cybernetic_library="$source_script/library/cybernetic.java"
work_cybernetic_library="$work_script/library/cybernetic.java"
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
source_heavyweapons_library="$source_script/library/heavyweapons.java"
work_heavyweapons_library="$work_script/library/heavyweapons.java"
source_reverse_engineering_library="$source_script/library/reverse_engineering.java"
work_reverse_engineering_library="$work_script/library/reverse_engineering.java"
source_skill_mod_listing="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/expertise/skill_mod_listing.tab"
work_skill_mod_listing="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/expertise/skill_mod_listing.tab"
source_healing_library="$source_script/library/healing.java"
work_healing_library="$work_script/library/healing.java"
source_consumable_library="$source_script/library/consumable.java"
work_consumable_library="$work_script/library/consumable.java"
source_quick_heal_command="$source_script/player/cmd/quick_heal.java"
work_quick_heal_command="$work_script/player/cmd/quick_heal.java"
source_classic_stimpack="$source_script/item/medicine/stimpack.java"
work_classic_stimpack="$work_script/item/medicine/stimpack.java"
source_crafted_stimpack="$source_script/item/medicine/stimpack_crafted.java"
work_crafted_stimpack="$work_script/item/medicine/stimpack_crafted.java"
source_other_stimpack="$source_script/item/medicine/stimpack_other.java"
work_other_stimpack="$work_script/item/medicine/stimpack_other.java"
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
source_item_stats_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/item_stats.tab"
work_item_stats_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/item_stats.tab"
source_armor_stats_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/armor_stats.tab"
work_armor_stats_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/armor_stats.tab"
source_weapon_stats_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/weapon_stats.tab"
work_weapon_stats_table="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/weapon_stats.tab"
source_advanced_search_table="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/commodity/advanced_search_attribute.tab"
work_advanced_search_table="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/commodity/advanced_search_attribute.tab"
source_medicine_template_root="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine"
work_medicine_template_root="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/object/tangible/medicine"
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
source_event_tool="$source_script/event/event_tool.java"
work_event_tool="$work_script/event/event_tool.java"
source_pgc_library="$source_script/library/pgc_quests.java"
work_pgc_library="$work_script/library/pgc_quests.java"
source_player_saga="$source_script/player/player_saga_quest.java"
work_player_saga="$work_script/player/player_saga_quest.java"
source_storyteller_commands="$source_script/systems/storyteller/storyteller_commands.java"
work_storyteller_commands="$work_script/systems/storyteller/storyteller_commands.java"
source_pet_library="$source_script/library/pet_lib.java"
work_pet_library="$work_script/library/pet_lib.java"
source_buff_library="$source_script/library/buff.java"
work_buff_library="$work_script/library/buff.java"
source_static_item_library="$source_script/library/static_item.java"
work_static_item_library="$work_script/library/static_item.java"
source_gcw_banner_manager="$source_script/item/gcw_buff_banner/banner_buff_manager.java"
work_gcw_banner_manager="$work_script/item/gcw_buff_banner/banner_buff_manager.java"
source_bh_shields="$source_script/player/skill/bh_shields.java"
work_bh_shields="$work_script/player/skill/bh_shields.java"
source_meditation_library="$source_script/library/meditation.java"
work_meditation_library="$work_script/library/meditation.java"
source_performcommands="$source_script/player/skill/performcommands.java"
work_performcommands="$work_script/player/skill/performcommands.java"
source_buff_handler="$source_script/systems/buff/buff_handler.java"
work_buff_handler="$work_script/systems/buff/buff_handler.java"
source_gcw_recruitment_letter="$source_script/item/publish_gift/recruitment_letter.java"
work_gcw_recruitment_letter="$work_script/item/publish_gift/recruitment_letter.java"
source_publish_gifts="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/veteran_rewards/publish_gift.tab"
work_publish_gifts="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/veteran_rewards/publish_gift.tab"
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
precu_item_level_paths="item/armor/dynamic_armor.java item/buff_beast_click_item.java item/buff_click_item.java item/full_heal_item.java item/levelup_orb/levelup_orb.java item/medicine/stimpack.java item/medicine/stimpack_crafted.java item/plant/force_melon.java item/skillmod_click_item.java item/static_item_base.java item/survey_tool/survey_tool_script.java library/buff.java library/collection.java library/healing.java library/player_structure.java library/static_item.java player/player_utility.java systems/buff/buff_handler.java systems/crafting/weapon/component/crafting_weapon_component_attribute.java systems/sign/special_sign.java systems/tcg/tcg_vendor_contract.java"
precu_stim_template_paths="channelled_stimpack/stimpack_a.tpf channelled_stimpack/stimpack_b.tpf channelled_stimpack/stimpack_c.tpf instant_stimpack/stimpack_a.tpf instant_stimpack/stimpack_b.tpf instant_stimpack/stimpack_c.tpf instant_stimpack/stimpack_d.tpf instant_stimpack/stimpack_e.tpf instant_stimpack/stimpack_noob.tpf instant_stimpack/stimpack_syren.tpf"
precu_encounter_difficulty_paths="ai/ai.java quest/task/ground/spawn.java quest/util/dynamic_mob_opponent.java quest/utility/dynamic_spawn_off_quest_item.java systems/spawning/spawn_base.java systems/tcg/target_creature.java systems/treasure_map/base/treasure_map.java theme_park/meatlump/hideout/mtp_instance_entrance_cell.java theme_park/meatlump/quest_shuttle_comlink.java theme_park/outbreak/dynamic_spawn_off_quest_item.java"
precu_retained_system_level_paths="ai/imperial_presence/harass.java city/imperial_crackdown/imperial_trouble.java event/ewok_festival/loveday_reward_crossbow.java event/halloween/song_book.java event/lost_squadron/stolen_fighter.java library/collection.java library/groundquests.java library/npe.java library/performance.java library/smuggler.java library/space_combat.java library/township.java npc/static_quest/quest_convo.java"
precu_cosmetic_familiar_paths="ai/familiar.java"
precu_droid_detonation_paths="ai/pet.java ai/pet_control_device.java library/pet_lib.java npc/pet_deed/droid_deed.java systems/crafting/droid/modules/droid_bomb.java"
post_nge_beast_creation_paths="ai/pet_control_device.java library/beast_lib.java library/incubator.java npc/pet_deed/pet_deed.java player/base/base_player.java player/player_utility.java systems/beast/base_incubator.java systems/beast/beast_dye.java systems/beast/beast_egg.java systems/beast/beast_food.java systems/beast/beast_steroid_injector.java systems/beast/decoration_item.java systems/beast/enzyme_crafting_base.java systems/beast/enzyme_crafting_centrifuge.java systems/beast/enzyme_crafting_combiner.java systems/beast/enzyme_crafting_processor.java systems/beast/enzyme_extractor.java"
post_nge_beast_runtime_paths="ai/beast.java ai/beast_control_device.java ai/creature_combat.java conversation/trainer_beast_master.java item/loot_schematic/loot_schematic.java library/beast_lib.java player/base/base_player.java player/live_conversions.java player/player_beastmaster.java systems/combat/combat_actions.java systems/combat/combat_base.java"
post_nge_officer_runtime_paths="ai/officer_pet.java systems/combat/combat_base.java systems/combat/combat_actions.java systems/combat/combat_supply_drop_controller.java systems/combat/combat_supply_drop_crate.java"
source_bounty_jedi="$source_script/library/jedi.java"
work_bounty_jedi="$work_script/library/jedi.java"
source_bounty_hunter="$source_script/library/bounty_hunter.java"
work_bounty_hunter="$work_script/library/bounty_hunter.java"
source_bounty_pclib="$source_script/library/pclib.java"
work_bounty_pclib="$work_script/library/pclib.java"
source_bounty_pvp="$source_script/library/pvp.java"
work_bounty_pvp="$work_script/library/pvp.java"
source_bounty_smuggler="$source_script/library/smuggler.java"
work_bounty_smuggler="$work_script/library/smuggler.java"
source_bounty_force_rank="$source_script/library/force_rank.java"
work_bounty_force_rank="$work_script/library/force_rank.java"
source_bounty_player_force_rank="$source_script/systems/gcw/player_force_rank.java"
work_bounty_player_force_rank="$work_script/systems/gcw/player_force_rank.java"
source_bounty_base_player="$source_script/player/base/base_player.java"
work_bounty_base_player="$work_script/player/base/base_player.java"
source_bounty_combat_base="$source_script/systems/combat/combat_base.java"
work_bounty_combat_base="$work_script/systems/combat/combat_base.java"
source_bounty_combat_player="$source_script/systems/combat/combat_player.java"
work_bounty_combat_player="$work_script/systems/combat/combat_player.java"
source_bounty_combat_actions="$source_script/systems/combat/combat_actions.java"
work_bounty_combat_actions="$work_script/systems/combat/combat_actions.java"
source_bounty_jedi_base="$source_script/systems/jedi/jedi_base.java"
work_bounty_jedi_base="$work_script/systems/jedi/jedi_base.java"
source_bounty_mission_dynamic="$source_script/systems/missions/base/mission_dynamic_base.java"
work_bounty_mission_dynamic="$work_script/systems/missions/base/mission_dynamic_base.java"
source_bounty_mission_player="$source_script/systems/missions/base/mission_player.java"
work_bounty_mission_player="$work_script/systems/missions/base/mission_player.java"
source_bounty_mission_bounty="$source_script/systems/missions/dynamic/mission_bounty.java"
work_bounty_mission_bounty="$work_script/systems/missions/dynamic/mission_bounty.java"
source_bounty_broker_4="$source_script/conversation/generic_broker_4.java"
work_bounty_broker_4="$work_script/conversation/generic_broker_4.java"
source_bounty_broker_5="$source_script/conversation/generic_broker_5.java"
work_bounty_broker_5="$work_script/conversation/generic_broker_5.java"
source_bounty_jedi_actions="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/jedi/jedi_actions.tab"
work_bounty_jedi_actions="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/jedi/jedi_actions.tab"
source_bounty_jedi_combat_data="$SWG_SOURCE_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/jedi/jedi_combat_data.tab"
work_bounty_jedi_combat_data="$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/jedi/jedi_combat_data.tab"
source_bounty_skills="$SWG_SOURCE_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
work_bounty_skills="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
source_bounty_skill_object="$SWG_SOURCE_DIR/src/engine/shared/library/sharedSkillSystem/src/shared/SkillObject.cpp"
work_bounty_skill_object="$SWG_WORK_DIR/src/engine/shared/library/sharedSkillSystem/src/shared/SkillObject.cpp"
source_bounty_skill_object_header="$SWG_SOURCE_DIR/src/engine/shared/library/sharedSkillSystem/src/shared/SkillObject.h"
work_bounty_skill_object_header="$SWG_WORK_DIR/src/engine/shared/library/sharedSkillSystem/src/shared/SkillObject.h"
source_bounty_swg_creature="$SWG_SOURCE_DIR/src/game/server/application/SwgGameServer/src/shared/object/SwgCreatureObject.cpp"
work_bounty_swg_creature="$SWG_WORK_DIR/src/game/server/application/SwgGameServer/src/shared/object/SwgCreatureObject.cpp"
source_bounty_swg_creature_header="$SWG_SOURCE_DIR/src/game/server/application/SwgGameServer/src/shared/object/SwgCreatureObject.h"
work_bounty_swg_creature_header="$SWG_WORK_DIR/src/game/server/application/SwgGameServer/src/shared/object/SwgCreatureObject.h"
source_bounty_swg_player="$SWG_SOURCE_DIR/src/game/server/application/SwgGameServer/src/shared/object/SwgPlayerObject.cpp"
work_bounty_swg_player="$SWG_WORK_DIR/src/game/server/application/SwgGameServer/src/shared/object/SwgPlayerObject.cpp"
source_bounty_jedi_manager="$SWG_SOURCE_DIR/src/game/server/application/SwgGameServer/src/shared/object/JediManagerObject.cpp"
work_bounty_jedi_manager="$SWG_WORK_DIR/src/game/server/application/SwgGameServer/src/shared/object/JediManagerObject.cpp"
source_bounty_jedi_manager_header="$SWG_SOURCE_DIR/src/game/server/application/SwgGameServer/src/shared/object/JediManagerObject.h"
work_bounty_jedi_manager_header="$SWG_WORK_DIR/src/game/server/application/SwgGameServer/src/shared/object/JediManagerObject.h"
source_bounty_script_methods_jedi="$SWG_SOURCE_DIR/src/engine/server/library/serverScript/src/shared/ScriptMethodsJedi.cpp"
work_bounty_script_methods_jedi="$SWG_WORK_DIR/src/engine/server/library/serverScript/src/shared/ScriptMethodsJedi.cpp"
source_local_options="$SWG_SOURCE_DIR/exe/linux/localOptions.cfg"
work_local_options="$SWG_WORK_DIR/exe/linux/localOptions.cfg"
class_root="$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game"
binary="$SWG_WORK_DIR/build/bin/SwgGameServer"
server_game_archive="$SWG_WORK_DIR/build/engine/server/library/serverGame/src/libserverGame.a"
server_script_archive="$SWG_WORK_DIR/build/engine/server/library/serverScript/src/libserverScript.a"
server_network_messages_archive="$SWG_WORK_DIR/build/engine/server/library/serverNetworkMessages/src/libserverNetworkMessages.a"
shared_skill_system_archive="$SWG_WORK_DIR/build/engine/shared/library/sharedSkillSystem/src/libsharedSkillSystem.a"

cmp -s "$source_bounty_jedi" "$work_bounty_jedi"
cmp -s "$source_bounty_hunter" "$work_bounty_hunter"
cmp -s "$source_bounty_pclib" "$work_bounty_pclib"
cmp -s "$source_bounty_pvp" "$work_bounty_pvp"
cmp -s "$source_bounty_smuggler" "$work_bounty_smuggler"
cmp -s "$source_bounty_force_rank" "$work_bounty_force_rank"
cmp -s "$source_bounty_player_force_rank" "$work_bounty_player_force_rank"
cmp -s "$source_bounty_base_player" "$work_bounty_base_player"
cmp -s "$source_bounty_combat_base" "$work_bounty_combat_base"
cmp -s "$source_bounty_combat_player" "$work_bounty_combat_player"
cmp -s "$source_bounty_combat_actions" "$work_bounty_combat_actions"
cmp -s "$source_bounty_jedi_base" "$work_bounty_jedi_base"
cmp -s "$source_bounty_mission_dynamic" "$work_bounty_mission_dynamic"
cmp -s "$source_bounty_mission_player" "$work_bounty_mission_player"
cmp -s "$source_bounty_mission_bounty" "$work_bounty_mission_bounty"
cmp -s "$source_bounty_broker_4" "$work_bounty_broker_4"
cmp -s "$source_bounty_broker_5" "$work_bounty_broker_5"
cmp -s "$source_bounty_jedi_actions" "$work_bounty_jedi_actions"
cmp -s "$source_bounty_jedi_combat_data" "$work_bounty_jedi_combat_data"
cmp -s "$source_bounty_skills" "$work_bounty_skills"
cmp -s "$source_bounty_skill_object" "$work_bounty_skill_object"
cmp -s "$source_bounty_skill_object_header" "$work_bounty_skill_object_header"
cmp -s "$source_bounty_swg_creature" "$work_bounty_swg_creature"
cmp -s "$source_bounty_swg_creature_header" "$work_bounty_swg_creature_header"
cmp -s "$source_bounty_swg_player" "$work_bounty_swg_player"
cmp -s "$source_bounty_jedi_manager" "$work_bounty_jedi_manager"
cmp -s "$source_bounty_jedi_manager_header" "$work_bounty_jedi_manager_header"
cmp -s "$source_bounty_script_methods_jedi" "$work_bounty_script_methods_jedi"

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
cmp -s "$source_commands_header" "$work_commands_header"
cmp -s "$source_connection_server" "$work_connection_server"
cmp -s "$source_tangible_conversation" "$work_tangible_conversation"
cmp -s "$source_player_controller" "$work_player_controller"
cmp -s "$source_creature_controller" "$work_creature_controller"
cmp -s "$source_script_methods_pvp" "$work_script_methods_pvp"
cmp -s "$source_script_methods_attributes" "$work_script_methods_attributes"
cmp -s "$source_script_function_header" "$work_script_function_header"
cmp -s "$source_script_function_table" "$work_script_function_table"
cmp -s "$source_alter_attribute_message_header" "$work_alter_attribute_message_header"
cmp -s "$source_alter_attribute_message" "$work_alter_attribute_message"
cmp -s "$source_client" "$work_client"
cmp -s "$source_creature" "$work_creature"
cmp -s "$source_creature_header" "$work_creature_header"
cmp -s "$source_group" "$work_group"
cmp -s "$source_player" "$work_player"
cmp -s "$source_player_header" "$work_player_header"
cmp -s "$source_weapon" "$work_weapon"
cmp -s "$source_weapon_header" "$work_weapon_header"
cmp -s "$source_speeds" "$work_speeds"
cmp -s "$source_unarmed_default" "$work_unarmed_default"
cmp -s "$source_travel" "$work_travel"
cmp -s "$source_player_travel" "$work_player_travel"
cmp -s "$source_command_table" "$work_command_table"
awk -F '\t' '
BEGIN {
    split("bleedingShot confusionShot eyeShot fastBlast forceOfWill knockdownFire lastDitch lowBlow meditate panicShot powerBoost sprayShot torsoShot tumbleToKneeling tumbleToProne tumbleToStanding underHandShot", retained_names, " ")
    for (slot in retained_names) retained[retained_names[slot]] = 1
    split("startDance startMusic stopDance stopMusic groupdance", noncombat_names, " ")
    for (slot in noncombat_names) noncombat[noncombat_names[slot]] = 1
}
NR > 2 && ($1 in retained) {
    retained_seen[$1]++
    if ($2 != "combat") exit 2
}
NR > 2 && ($1 in noncombat) {
    noncombat_seen[$1]++
    if ($2 == "combat") exit 3
}
END {
    for (name in retained) if (retained_seen[name] != 1) exit 4
    for (name in noncombat) if (noncombat_seen[name] != 1) exit 5
}
' "$work_command_table"
awk -F '\t' '$1 == "centerOfBeing" { found++; if ($2 != "combat") exit 2 } END { if (found != 1) exit 3 }' "$work_command_table"
awk -F '\t' '
NR == 1 {
    for (column = 1; column <= NF; column++) field[$column] = column
    next
}
NR > 2 && ($1 == "unarmedDizzy1" || $1 == "unarmedCombo1" || $1 == "unarmedCombo2") {
    found[$1]++
    expectedTime["unarmedDizzy1"] = 2
    expectedTime["unarmedCombo1"] = 2
    expectedTime["unarmedCombo2"] = 4
    if ($(field["commandCategory"]) != "combat" ||
        $(field["scriptHook"]) != $1 ||
        $(field["defaultTime"]) != expectedTime[$1] ||
        $(field["executeTime"]) != expectedTime[$1] ||
        $(field["validWeapon"]) != "UNARMED" ||
        $(field["addToCombatQueue"]) != 1) exit 2
}
END {
    if (found["unarmedDizzy1"] != 1 ||
        found["unarmedCombo1"] != 1 ||
        found["unarmedCombo2"] != 1) exit 3
}
' "$work_command_table"
cmp -s "$source_skills" "$work_skills"
cmp -s "$source_buff_table" "$work_buff_table"
cmp -s "$source_buff_effect_mapping" "$work_buff_effect_mapping"
cmp -s "$source_collection_rewards" "$work_collection_rewards"
cmp -s "$source_combat_data" "$work_combat_data"
cmp -s "$source_proc_table" "$work_proc_table"
cmp -s "$source_item_sets" "$work_item_sets"
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
cmp -s "$source_pvp_aura_controller" "$work_pvp_aura_controller"
cmp -s "$source_faction_perk_library" "$work_faction_perk_library"
cmp -s "$source_jedi_saber_component" "$work_jedi_saber_component"
cmp -s "$source_gcw_library" "$work_gcw_library"
! grep -E -q '(^|[^[:alnum:]_.])getLevel[[:space:]]*\([[:space:]]*(player|killer|obj_id)[[:space:]]*\)' "$work_gcw_library"
test "$(grep -E -o 'skill\.getPrecuEncounterDifficulty[[:space:]]*\([[:space:]]*(player|killer|obj_id)[[:space:]]*\)' "$work_gcw_library" | wc -l)" -eq 7
test "$(grep -E -o '(^|[^[:alnum:]_.])getLevel[[:space:]]*\([[:space:]]*npc[[:space:]]*\)' "$work_gcw_library" | wc -l)" -eq 1
cmp -s "$source_gcw_city" "$work_gcw_city"
cmp -s "$source_gcw_city_pylon" "$work_gcw_city_pylon"
cmp -s "$source_gcw_supply_terminal" "$work_gcw_supply_terminal"
cmp -s "$source_imperial_general" "$work_imperial_general"
cmp -s "$source_rebel_general" "$work_rebel_general"
cmp -s "$source_imperial_offensive_supply" "$work_imperial_offensive_supply"
cmp -s "$source_imperial_defensive_supply" "$work_imperial_defensive_supply"
cmp -s "$source_rebel_offensive_supply" "$work_rebel_offensive_supply"
cmp -s "$source_rebel_defensive_supply" "$work_rebel_defensive_supply"
retired_city_asset_source_guard_count=0
for retired_city_asset_spec in $retired_city_asset_runtime_specs; do
    retired_city_asset_name="${retired_city_asset_spec%%:*}"
    retired_city_asset_expected_guards="${retired_city_asset_spec##*:}"
    retired_city_asset_source="$source_script/systems/gcw/$retired_city_asset_name.java"
    retired_city_asset_work="$work_script/systems/gcw/$retired_city_asset_name.java"
    cmp -s "$retired_city_asset_source" "$retired_city_asset_work"
    retired_city_asset_actual_guards="$(grep -Fc 'gcw.isPostNgeCityInvasionRetired()' "$retired_city_asset_work")"
    test "$retired_city_asset_actual_guards" -eq "$retired_city_asset_expected_guards"
    retired_city_asset_source_guard_count=$((retired_city_asset_source_guard_count + retired_city_asset_actual_guards))
done
test "$retired_city_asset_source_guard_count" -eq 104
cmp -s "$source_planet_base" "$work_planet_base"
cmp -s "$source_live_conversions" "$work_live_conversions"
cmp -s "$source_respec" "$work_respec"
cmp -s "$source_cureward" "$work_cureward"
cmp -s "$source_open_world_battlefield" "$work_open_world_battlefield"
cmp -s "$source_trap_base" "$work_trap_base"
cmp -s "$source_battlefield_controller" "$work_battlefield_controller"
cmp -s "$source_battlefield_terminal" "$work_battlefield_terminal"
cmp -s "$source_battlefield_player" "$work_battlefield_player"
cmp -s "$source_battlefield_imperial_vendor" "$work_battlefield_imperial_vendor"
cmp -s "$source_battlefield_rebel_vendor" "$work_battlefield_rebel_vendor"
cmp -s "$source_dsrc_attributes" "$work_dsrc_attributes"
cmp -s "$source_creatures_table" "$work_creatures_table"
cmp -s "$source_talus_vendor_buildout" "$work_talus_vendor_buildout"
cmp -s "$source_rori_vendor_buildout" "$work_rori_vendor_buildout"
cmp -s "$source_player_faction" "$work_player_faction"
cmp -s "$source_player_utility" "$work_player_utility"
grep -Fq 'cleanupRetiredCityInvasionPlayerState' "$work_gcw_library"
grep -Fq '!isPlayer(player)' "$work_gcw_library"
test "$(grep -Fc 'gcw.cleanupRetiredCityInvasionPlayerState(self);' "$work_player_faction")" -ge 7
test "$(grep -Fc 'gcw.cleanupRetiredCityInvasionPlayerState(self);' "$work_player_utility")" -eq 7
test "$(grep -Fc 'isPostNgeCityInvasionRetired()' "$work_gcw_library")" -ge 31
test "$(grep -Fc 'gcw.isPostNgeCityInvasionRetired()' "$work_gcw_city_pylon")" -eq 10
test "$(grep -Fc 'gcw.isPostNgeCityInvasionRetired()' "$work_gcw_supply_terminal")" -eq 12
for retired_city_conversation in "$work_imperial_general" "$work_rebel_general" "$work_imperial_offensive_supply" "$work_imperial_defensive_supply" "$work_rebel_offensive_supply" "$work_rebel_defensive_supply"; do
    test "$(grep -Fc 'gcw.isPostNgeCityInvasionRetired()' "$retired_city_conversation")" -eq 5
done
for retired_city_marker in BUFF_PLAYER_FATIGUE BUFF_SPY_EXPLOSIVES ENTERTAIN_GCW_TROOPS_PID TRADER_REPAIR_PID SPY_SCOUT_PID SPY_DESTROY_PID gcwSetCredits awardGcwInvasionParticipants gcwGetActiveCities gcwGetNextInvasionTime gcw.sliceSequence gcw.terminalScanTier retiredCityQuests gcw_construct_vehicle_boss; do
    grep -Fq "$retired_city_marker" "$work_gcw_library"
done
cmp -s "$source_force_rank" "$work_force_rank"
cmp -s "$source_jedi_trials" "$work_jedi_trials"
cmp -s "$source_frs_recruiter" "$work_frs_recruiter"
cmp -s "$source_player_force_rank" "$work_player_force_rank"
cmp -s "$source_enclave_controller" "$work_enclave_controller"
cmp -s "$source_knight_trials" "$work_knight_trials"
cmp -s "$source_force_rank_xp" "$work_force_rank_xp"
cmp -s "$source_force_rank_light" "$work_force_rank_light"
cmp -s "$source_force_rank_dark" "$work_force_rank_dark"
grep -Fxq 'enableFRS=1' "$source_local_options"
grep -Fxq 'enableCovertImperialMercenary=false' "$source_local_options"
grep -Fxq 'enableOvertImperialMercenary=false' "$source_local_options"
grep -Fxq 'enableCovertRebelMercenary=false' "$source_local_options"
grep -Fxq 'enableOvertRebelMercenary=false' "$source_local_options"
grep -Fq 'SWG_PRECU_START_PLANETS:-tatooine,corellia,naboo,yavin4,' "$SWG_SOURCE_DIR/docker-compose.precu.yml"
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
cmp -s "$source_faction_recruiter_imperial_conversation" "$work_faction_recruiter_imperial_conversation"
cmp -s "$source_faction_recruiter_rebel_conversation" "$work_faction_recruiter_rebel_conversation"
cmp -s "$source_regional_mission_terminal_spawner" "$work_regional_mission_terminal_spawner"
cmp -s "$source_regional_mission_terminal_template" "$work_regional_mission_terminal_template"
cmp -s "$source_camp_controlpanel" "$work_camp_controlpanel"
cmp -s "$source_camp_master" "$work_camp_master"
cmp -s "$source_camping_library" "$work_camping_library"
cmp -s "$source_pclib_library" "$work_pclib_library"
cmp -s "$source_group_library" "$work_group_library"
cmp -s "$source_skill_library" "$work_skill_library"
cmp -s "$source_proc_library" "$work_proc_library"
cmp -s "$source_proc_table" "$work_proc_table"
test "$(awk -F '\t' 'NR > 2 { count++ } END { print count + 0 }' "$work_proc_table")" -eq 97
test "$(awk -F '\t' 'NR > 2 { proc[$1] = 1 } END { for (name in proc) count++; print count + 0 }' "$work_proc_table")" -eq 96
awk -F '\t' 'NR > 2 {
    matched = 0
    for (column = 8; column <= 16; column += 2)
        if ($column == "proc_buff" || $column == "reac_buff") matched = 1
    count += matched
} END { if (count != 72) exit 3 }' "$work_buff_table"
awk -F '\t' 'NR == FNR {
    if (FNR > 2) proc[$1] = 1
    next
} FNR > 2 && ($1 in proc) { command[$1]++ }
END {
    for (name in command) commandCount++
    if (commandCount != 96) exit 2
    for (name in proc) if (command[name] != 1) exit 3
}' "$work_proc_table" "$work_command_table"
awk -F '\t' 'NR == FNR {
    if (FNR > 2) proc[$1] = 1
    next
} FNR > 2 && ($1 in proc) { combat[$1]++ }
END {
    for (name in combat) combatCount++
    if (combatCount != 96) exit 2
    for (name in proc) if (combat[name] != 1) exit 3
}' "$work_proc_table" "$work_combat_data"
proc_buff_predicate_source="$(sed -n '/private static boolean isPostNgePlayerProcEffectParameter/,/public static boolean isRetiredPostNgePlayerProcAction/p' "$work_proc_library")"
printf '%s' "$proc_buff_predicate_source" | grep -Fq '"proc_buff".equals(effectParameter)'
printf '%s' "$proc_buff_predicate_source" | grep -Fq '"reac_buff".equals(effectParameter)'
test "$(printf '%s' "$proc_buff_predicate_source" | grep -Ec 'isPostNgePlayerProcEffectParameter\(data\.effect[1-5]Param\)')" -eq 5
printf '%s' "$proc_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerProcActor(player)'
proc_action_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProcAction/,/public static void retirePostNgePlayerProcState/p' "$work_proc_library")"
printf '%s' "$proc_action_predicate_source" | grep -Fq 'isRetiredPostNgePlayerProcActor(actor)'
printf '%s' "$proc_action_predicate_source" | grep -Fq 'dataTableGetRow(PROC_TABLE, actionName) != null'
proc_cleanup_source="$(sed -n '/public static void retirePostNgePlayerProcState/,/public static void executeProcEffects/p' "$work_proc_library")"
printf '%s' "$proc_cleanup_source" | grep -Fq 'buff.getAllBuffs(player)'
printf '%s' "$proc_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$proc_cleanup_source" | grep -Fq 'isRetiredPostNgePlayerProcBuff(player, data)'
printf '%s' "$proc_cleanup_source" | grep -Fq 'buff.removeBuff(player, activeBuff)'
proc_buff_add_source="$(sed -n '/public void procBuffAddBuffHandler/,/public void procBuffRemoveBuffHandler/p' "$work_buff_handler")"
proc_buff_remove_source="$(sed -n '/public void procBuffRemoveBuffHandler/,/public void reactiveBuffAddBuffHandler/p' "$work_buff_handler")"
reactive_buff_add_source="$(sed -n '/public void reactiveBuffAddBuffHandler/,/public void reactiveBuffRemoveBuffHandler/p' "$work_buff_handler")"
reactive_buff_remove_source="$(sed -n '/public void reactiveBuffRemoveBuffHandler/,/public int stanceAddBuffHandler/p' "$work_buff_handler")"
for proc_effect_add_source in "$proc_buff_add_source" "$reactive_buff_add_source"; do
    proc_effect_add_predicate_line="$(printf '%s\n' "$proc_effect_add_source" | grep -Fn 'proc.isRetiredPostNgePlayerProcActor(self)' | head -1 | cut -d: -f1)"
    proc_effect_add_cleanup_line="$(printf '%s\n' "$proc_effect_add_source" | grep -Fn 'proc.retirePostNgePlayerProcState(self);' | head -1 | cut -d: -f1)"
    proc_effect_add_return_line="$(printf '%s\n' "$proc_effect_add_source" | grep -Fn 'return;' | head -1 | cut -d: -f1)"
    proc_effect_add_parse_line="$(printf '%s\n' "$proc_effect_add_source" | grep -Fn 'effectName = effectName.substring' | head -1 | cut -d: -f1)"
    proc_effect_add_writer_line="$(printf '%s\n' "$proc_effect_add_source" | grep -Fn 'utils.setScriptVar' | head -1 | cut -d: -f1)"
    for proc_effect_add_line in "$proc_effect_add_predicate_line" "$proc_effect_add_cleanup_line" "$proc_effect_add_return_line" "$proc_effect_add_parse_line" "$proc_effect_add_writer_line"; do
        test -n "$proc_effect_add_line"
    done
    test "$proc_effect_add_predicate_line" -lt "$proc_effect_add_cleanup_line"
    test "$proc_effect_add_cleanup_line" -lt "$proc_effect_add_return_line"
    test "$proc_effect_add_return_line" -lt "$proc_effect_add_parse_line"
    test "$proc_effect_add_parse_line" -lt "$proc_effect_add_writer_line"
done
! printf '%s' "$proc_buff_remove_source" | grep -Fq 'retirePostNgePlayerProcState'
printf '%s' "$proc_buff_remove_source" | grep -Fq 'utils.removeScriptVar(self, "procBuffEffects")'
printf '%s' "$proc_buff_remove_source" | grep -Fq 'proc.buildCurrentProcList(self)'
! printf '%s' "$reactive_buff_remove_source" | grep -Fq 'retirePostNgePlayerProcState'
printf '%s' "$reactive_buff_remove_source" | grep -Fq 'utils.removeScriptVar(self, "reacBuffEffects")'
printf '%s' "$reactive_buff_remove_source" | grep -Fq 'proc.buildCurrentReacList(self)'
proc_standard_action_source="$(sed -n '/public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)/,/combat.revealPrecuFeignDeath(self, "combatCommand")/p' "$work_combat_base")"
printf '%s' "$proc_standard_action_source" | grep -Fq 'proc.isRetiredPostNgePlayerProcAction(self, actionName)'
printf '%s' "$proc_standard_action_source" | grep -Fq 'proc.retirePostNgePlayerProcState(self);'
proc_direct_action_source="$(sed -n '/public int expertise_fs_flurry_charge_proc/,/public int meleeHit/p' "$work_combat_actions")"
printf '%s' "$proc_direct_action_source" | grep -Fq 'proc.isRetiredPostNgePlayerProcAction(self, "expertise_fs_flurry_charge_proc")'
printf '%s' "$proc_direct_action_source" | grep -Fq 'proc.retirePostNgePlayerProcState(self);'
proc_direct_gate_line="$(printf '%s\n' "$proc_direct_action_source" | grep -Fn 'proc.isRetiredPostNgePlayerProcAction' | head -1 | cut -d: -f1)"
proc_direct_effect_line="$(printf '%s\n' "$proc_direct_action_source" | grep -Fn 'buff.isInStance(self)' | head -1 | cut -d: -f1)"
test "$proc_direct_gate_line" -lt "$proc_direct_effect_line"
cmp -s "$source_expertise_library" "$work_expertise_library"
grep -Fq 'if (proc.isRetiredPostNgePlayerProcActor(player))' "$work_expertise_library"
grep -Fq 'proc.retirePostNgePlayerProcState(player);' "$work_expertise_library"
cmp -s "$source_cybernetic_library" "$work_cybernetic_library"
grep -Fq 'isRetiredPostNgePlayerCyberneticCommandActor(player)' "$work_cybernetic_library"
grep -Fq 'retirePostNgePlayerCyberneticCommandState(player);' "$work_cybernetic_library"
cybernetic_retirement_source="$(sed -n '/POST_NGE_CYBERNETIC_PLAYER_COMMANDS/,/public static final int CYBERNETIC_FULL_ARM_COST/p' "$work_cybernetic_library")"
for retired_cybernetic_modifier in cybernetic_healing_mod cybernetic_heavy_weapon_legs cybernetic_melee_acc cybernetic_melee_def cybernetic_ranged_acc cybernetic_ranged_range cybernetic_run_buff cybernetic_throw_range; do
    printf '%s' "$cybernetic_retirement_source" | grep -Fq "\"$retired_cybernetic_modifier\""
done
printf '%s' "$cybernetic_retirement_source" | grep -Fq '"cyberneticLegs"'
printf '%s' "$cybernetic_retirement_source" | grep -Fq 'applySkillStatisticModifier(player, retiredModifier, -currentValue);'
cybernetic_run_boost_source="$(sed -n '/public static void applyRunBoostMod/,/public static void grantSpecialCommands/p' "$work_cybernetic_library")"
test "$(printf '%s' "$cybernetic_run_boost_source" | grep -Fc 'if (isRetiredPostNgePlayerCyberneticCommandActor(player))')" -eq 2
cybernetic_skill_modifier_source="$(sed -n '/public static void grantCyberneticSkillMods/,/public static void validateSkillMods/p' "$work_cybernetic_library")"
test "$(printf '%s' "$cybernetic_skill_modifier_source" | grep -Fc 'if (isRetiredPostNgePlayerCyberneticCommandActor(player))')" -eq 2
cybernetic_combat_accessor_source="$(sed -n '/public static float getThrowRangeMod/,/public static void grantCyberneticSkillMods/p' "$work_cybernetic_library")"
test "$(printf '%s' "$cybernetic_combat_accessor_source" | grep -Fc 'if (isRetiredPostNgePlayerCyberneticCommandActor(player))')" -eq 7
cybernetic_validate_source="$(sed -n '/public static void validateSkillMods/,/public static void revokeAllOccurancesOfCommand/p' "$work_cybernetic_library")"
printf '%s' "$cybernetic_validate_source" | grep -Fq 'movement.refresh(player);'
printf '%s' "$cybernetic_validate_source" | grep -Fq 'return;'
cmp -s "$source_transition_library" "$work_transition_library"
cmp -s "$source_zone_transition_table" "$work_zone_transition_table"
cmp -s "$source_utils_library" "$work_utils_library"
grep -Fq 'public static boolean isPostNgeCtsProgressionRestorationRetired()' "$work_utils_library"
grep -Fq 'if (isPostNgeCtsProgressionRestorationRetired())' "$work_utils_library"
grep -Fq 'removeObjVar(player, respec.PROF_LEVEL_ARRAY);' "$work_utils_library"
grep -Fq 'beast_lib.retirePostNgeBeastMasterPlayerState(player);' "$work_utils_library"
grep -Fq 'public static boolean isRetiredPostNgePlayerOwnedBeast(obj_id beast)' "$work_beast_library"
test "$(grep -Fc 'isRetiredPostNgePlayerOwnedBeast(beast)' "$work_beast_library")" -eq 6
beast_controller_source="$work_script/ai/beast.java"
grep -Fq 'public boolean retirePostNgePlayerOwnedRuntime(obj_id self)' "$beast_controller_source"
test "$(grep -Fc 'retirePostNgePlayerOwnedRuntime(self)' "$beast_controller_source")" -eq 4
grep -Fq 'beast_lib.retirePostNgeBeastMasterPlayerState(master);' "$beast_controller_source"
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
grep -Fq '"invis_cover"' "$work_stealth_library"
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
cmp -s "$source_heavyweapons_library" "$work_heavyweapons_library"
! grep -Fq 'isCommandoBonus' "$work_combat_library"
! grep -Fq 'getDevastationChance' "$work_combat_library"
! grep -Eq 'commando_passive_dot|commando_devastation|expertise_devastation_bonus|heavyweapons\.getHeavyWeaponDotName' "$work_combat_base"
heavy_weapon_dot_guard="$(sed -n '/public static String getHeavyWeaponDotName(obj_id player, int elementalDamageType/,+8p' "$work_heavyweapons_library")"
printf '%s' "$heavy_weapon_dot_guard" | grep -Fq 'if (isPlayer(player))'
printf '%s' "$heavy_weapon_dot_guard" | grep -Fq 'return null;'
printf '%s' "$heavy_weapon_dot_guard" | grep -Fq 'int playerLevel = getLevel(player);'
grep -Fq 'ATTACK_NAME_BASE_SINGLE = "co_hw_dot_"' "$work_heavyweapons_library"
grep -Fq 'ATTACK_NAME_BASE_AREA = "co_ae_hw_dot_"' "$work_heavyweapons_library"
cmp -s "$source_reverse_engineering_library" "$work_reverse_engineering_library"
cmp -s "$source_skill_mod_listing" "$work_skill_mod_listing"
cmp -s "$source_healing_library" "$work_healing_library"
cmp -s "$source_consumable_library" "$work_consumable_library"
cmp -s "$source_quick_heal_command" "$work_quick_heal_command"
cmp -s "$source_classic_stimpack" "$work_classic_stimpack"
cmp -s "$source_crafted_stimpack" "$work_crafted_stimpack"
cmp -s "$source_other_stimpack" "$work_other_stimpack"
cmp -s "$source_dot_library" "$work_dot_library"
dot_immunity_source="$(sed -n '/public static boolean checkForDotImmunity/,/public static int getElementalGroupResist/p' "$work_dot_library")"
dot_immunity_player_guard_line="$(printf '%s\n' "$dot_immunity_source" | grep -Fn 'if (isPlayer(target))' | head -1 | cut -d: -f1)"
dot_immunity_later_modifier_line="$(printf '%s\n' "$dot_immunity_source" | grep -Fn '"dot_resist_"' | head -1 | cut -d: -f1)"
test -n "$dot_immunity_player_guard_line"
test -n "$dot_immunity_later_modifier_line"
test "$dot_immunity_player_guard_line" -lt "$dot_immunity_later_modifier_line"
printf '%s\n' "$dot_immunity_source" | sed -n "${dot_immunity_player_guard_line},${dot_immunity_later_modifier_line}p" | grep -Fq 'return false;'
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
cmp -s "$source_buff_effect_mapping" "$work_buff_effect_mapping"
awk -F '\t' '
    $1 == "expertise_junk_dealer" && $2 == "junkDealer" && $3 == "expertise_junk_dealer" { ++matches }
    END { exit matches == 1 ? 0 : 1 }
' "$work_buff_effect_mapping"
awk -F '\t' '
    $1 == "expertise_buff_best_deal_ever" || $1 == "expertise_junk_dealer_cut" { ++matches }
    END { exit matches == 2 ? 0 : 1 }
' "$work_skill_mod_listing"
awk -F '\t' '
    $1 == "expertise_sm_path_under_the_counter_1" ||
    $1 == "expertise_sm_path_under_the_counter_2" ||
    $1 == "expertise_sm_path_best_deal_ever_1" ||
    $1 == "expertise_sm_path_best_deal_ever_2" { ++matches }
    END { exit matches == 4 ? 0 : 1 }
' "$work_skills"
cmp -s "$source_buff_library" "$work_buff_library"
cmp -s "$source_buff_handler" "$work_buff_handler"
junk_dealer_expertise_source="$(sed -n '/private static final String RETIRED_POST_NGE_JUNK_DEALER_EXPERTISE_EFFECT/,/private static final String\[\] RETIRED_POST_NGE_FORCE_SENSITIVE_STANCE_BUFFS/p' "$work_buff_library")"
printf '%s' "$junk_dealer_expertise_source" | grep -Fq '"expertise_junk_dealer"'
printf '%s' "$junk_dealer_expertise_source" | grep -Fq 'isRetiredPostNgeJunkDealerExpertiseEffect'
printf '%s' "$junk_dealer_expertise_source" | grep -Fq 'isRetiredPostNgeJunkDealerExpertiseBuff'
printf '%s' "$junk_dealer_expertise_source" | grep -Fq 'clearPostNgeJunkDealerExpertiseState'
printf '%s' "$junk_dealer_expertise_source" | grep -Fq 'utils.removeScriptVar(dealer, "junkDealerBuffer")'
printf '%s' "$junk_dealer_expertise_source" | grep -Fq '"junkDealerPrecision"'
printf '%s' "$junk_dealer_expertise_source" | grep -Fq '"junkDealerDamageDecrease"'
junk_dealer_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
junk_dealer_admission_line="$(printf '%s\n' "$junk_dealer_admission_source" | grep -Fn 'isRetiredPostNgeJunkDealerExpertiseBuff(bdata)' | head -1 | cut -d: -f1)"
junk_dealer_player_gate_line="$(printf '%s\n' "$junk_dealer_admission_source" | grep -Fn 'if (isPlayer(target) &&' | head -1 | cut -d: -f1)"
junk_dealer_existing_line="$(printf '%s\n' "$junk_dealer_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$junk_dealer_admission_line"
test -n "$junk_dealer_player_gate_line"
test -n "$junk_dealer_existing_line"
test "$junk_dealer_admission_line" -lt "$junk_dealer_player_gate_line"
test "$junk_dealer_player_gate_line" -lt "$junk_dealer_existing_line"
junk_dealer_add_source="$(sed -n '/public int junkDealerAddBuffHandler/,/public int junkDealerRemoveBuffHandler/p' "$work_buff_handler")"
junk_dealer_remove_source="$(sed -n '/public int junkDealerRemoveBuffHandler/,/public int commandoSnareBonusAddBuffHandler/p' "$work_buff_handler")"
for junk_dealer_handler_source in "$junk_dealer_add_source" "$junk_dealer_remove_source"; do
    printf '%s' "$junk_dealer_handler_source" | grep -Fq 'buff.isPostNgeBuffProgressionRetired()'
    printf '%s' "$junk_dealer_handler_source" | grep -Fq 'buff.isRetiredPostNgeJunkDealerExpertiseEffect(effectName)'
    printf '%s' "$junk_dealer_handler_source" | grep -Fq 'buff.clearPostNgeJunkDealerExpertiseState(self);'
done
junk_dealer_add_cleanup_line="$(printf '%s\n' "$junk_dealer_add_source" | grep -Fn 'clearPostNgeJunkDealerExpertiseState' | head -1 | cut -d: -f1)"
junk_dealer_add_read_line="$(printf '%s\n' "$junk_dealer_add_source" | grep -Fn 'getObjIdScriptVar(self, "junkDealerBuffer")' | head -1 | cut -d: -f1)"
junk_dealer_remove_cleanup_line="$(printf '%s\n' "$junk_dealer_remove_source" | grep -Fn 'clearPostNgeJunkDealerExpertiseState' | head -1 | cut -d: -f1)"
junk_dealer_remove_write_line="$(printf '%s\n' "$junk_dealer_remove_source" | grep -Fn 'removeAttribOrSkillModModifier(self, "junkDealerPrecision")' | head -1 | cut -d: -f1)"
test "$junk_dealer_add_cleanup_line" -lt "$junk_dealer_add_read_line"
test "$junk_dealer_remove_cleanup_line" -lt "$junk_dealer_remove_write_line"
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
grep -Fq 'new string_id("combat_effects", "glancing_blow")' "$work_combat_base"
! grep -Fq 'expertise_fs_general_alacrity_1' "$work_combat_base"
! grep -Fq 'appearance/pt_jedi_alacrity.prt' "$work_combat_base"
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
cmp -s "$source_item_stats_table" "$work_item_stats_table"
cmp -s "$source_armor_stats_table" "$work_armor_stats_table"
cmp -s "$source_weapon_stats_table" "$work_weapon_stats_table"
cmp -s "$source_advanced_search_table" "$work_advanced_search_table"
for precu_stim_template_path in $precu_stim_template_paths; do
    cmp -s "$source_medicine_template_root/$precu_stim_template_path" "$work_medicine_template_root/$precu_stim_template_path"
done
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
grep -Eq '^attackSpeed[[:space:]]*=[[:space:]]*2\.0[[:space:]]*$' "$work_unarmed_default"
! grep -Eq '^attackSpeed[[:space:]]*=[[:space:]]*0\.5(0)?[[:space:]]*$' "$work_unarmed_default"
base_player_initialize_source="$(sed -n '/public int OnInitialize(/,/public int handleJediVisibilityDecay(/p' "$work_base_player")"
printf '%s\n' "$base_player_initialize_source" | grep -Fq 'object/weapon/melee/unarmed/unarmed_default_player.iff'
! printf '%s\n' "$base_player_initialize_source" | grep -Fq 'float fltWeaponSpeed = getWeaponAttackSpeed(objWeapon)'
! printf '%s\n' "$base_player_initialize_source" | grep -Fq 'setWeaponAttackSpeed(objWeapon, 0.50f)'
! printf '%s\n' "$base_player_initialize_source" | grep -Fq 'fltWeaponSpeed != 0.50f'
cmp -s "$source_event_tool" "$work_event_tool"
cmp -s "$source_pgc_library" "$work_pgc_library"
cmp -s "$source_player_saga" "$work_player_saga"
cmp -s "$source_storyteller_commands" "$work_storyteller_commands"
cmp -s "$source_pet_library" "$work_pet_library"
cmp -s "$source_base_class" "$work_base_class"
cmp -s "$source_buff_library" "$work_buff_library"
cmp -s "$source_static_item_library" "$work_static_item_library"
cmp -s "$source_buff_table" "$work_buff_table"
cmp -s "$source_buff_effect_mapping" "$work_buff_effect_mapping"
cmp -s "$source_gcw_banner_manager" "$work_gcw_banner_manager"
cmp -s "$source_bh_shields" "$work_bh_shields"
cmp -s "$source_meditation_library" "$work_meditation_library"
cmp -s "$source_performcommands" "$work_performcommands"
cmp -s "$source_buff_handler" "$work_buff_handler"
cmp -s "$source_gcw_recruitment_letter" "$work_gcw_recruitment_letter"
cmp -s "$source_publish_gifts" "$work_publish_gifts"
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
printf '%s' "$buff_skill_predicate_source" | grep -Fq 'static_item.isRetiredNgeBuffSkillModifier(modifierName)'
shared_buff_skill_predicate_source="$(sed -n '/public static boolean isRetiredNgeBuffSkillModifier/,/public static void removeRetiredNgePlayerSkillStatistics/p' "$work_static_item_library")"
printf '%s' "$shared_buff_skill_predicate_source" | grep -Fq 'isRetiredNgeStaticItemSkillModifier(modifier)'
printf '%s' "$shared_buff_skill_predicate_source" | grep -Fq 'modifier.equals("damage_immune")'
printf '%s' "$shared_buff_skill_predicate_source" | grep -Fq 'modifier.startsWith("dot_resist_")'
retired_player_modifier_regex='^(expertise_|fast_attack_line_|bm_|dot_resist_)|^(agility_modified|constitution_modified|luck_modified|precision_modified|stamina_modified|strength_modified|attack_override_by_buff|bh_dire_root|bh_dire_snare|combat_block_chance|combat_block_value|combat_strikethrough_chance|cooldown_percent_of_group_buff|incubation_time_reduction|rally_point_duration|tka_armor|combat_critical_hit_reduction|combat_dodge|combat_parry|combat_evasion_chance|combat_evasion_value|combat_strikethrough_value|commando_devastation|exotic_heal_action_reduction|exotic_dodge_reduction|exotic_parry_reduction|exotic_acid_penetration|exotic_cold_penetration|exotic_heat_penetration|exotic_electricity_penetration|combat_add_damage_dealt|combat_add_damage_taken|combat_all_attack_avoidance|combat_all_attack_miss|combat_all_attack_miss_reduction|combat_all_attack_miss_vulnerability|combat_block_reduction|combat_critical_hit|combat_divide_damage_dealt|combat_divide_damage_taken|combat_dodge_reduction|combat_glancing|combat_glancing_blow_reduction|combat_melee_attack_avoidance|combat_melee_attack_miss|combat_melee_attack_miss_reduction|combat_melee_attack_vulnerability|combat_multiply_damage_dealt|combat_multiply_damage_taken|combat_parry_reduction|combat_ranged_attack_avoidance|combat_ranged_attack_miss|combat_ranged_attack_miss_reduction|combat_ranged_attack_vulnerability|combat_subtract_damage_dealt|combat_subtract_damage_taken|crit_always|critical_hit_vulnerable|damage_immune|flurry_cooldown_modifier|freeshot_case_crit|freeshot_case_dodge|freeshot_case_miss|freeshot_case_parry|freeshot_case_strikethrough|glancing_blow_vulnerable|hit_always|of_inspired_action_chance|strikethrough_vulnerable)$'
awk -F '\t' -v retired="$retired_player_modifier_regex" 'NR > 2 {
    matched = 0
    mixed = 0
    for (column = 8; column <= 16; column += 2) {
        if ($column ~ retired) {
            matched = 1
            modifiers[$column] = 1
        } else if ($column != "") {
            mixed = 1
        }
    }
    if (matched) {
        rows++
        names[$1] = 1
        if (mixed) mixedRows++
    }
} END {
    for (name in names) nameCount++
    for (modifier in modifiers) modifierCount++
    if (rows != 1001 || nameCount != 1001 || modifierCount != 197 || mixedRows != 135) exit 3
}' "$work_buff_table"
awk -F '\t' -v retired="$retired_player_modifier_regex" 'NR == FNR {
    if (FNR > 2) {
        for (column = 8; column <= 16; column += 2)
            if ($column ~ retired) modifiers[$column] = 1
    }
    next
} FNR > 2 && ($1 in modifiers) { mapped++ }
END {
    for (modifier in modifiers) modifierCount++
    if (modifierCount != 197 || mapped != 206) exit 3
}' "$work_buff_table" "$work_buff_effect_mapping"
player_modifier_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerModifierBuff/,/public static void retirePostNgePlayerModifierBuffState/p' "$work_buff_library")"
printf '%s' "$player_modifier_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$player_modifier_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$player_modifier_buff_predicate_source" | grep -Fq 'static_item.isRetiredNgeBuffSkillModifier(getEffectParam(data, effect))'
player_modifier_buff_cleanup_source="$(sed -n '/public static void retirePostNgePlayerModifierBuffState/,/public static void retirePostNgeBuffProgression/p' "$work_buff_library")"
printf '%s' "$player_modifier_buff_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$player_modifier_buff_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$player_modifier_buff_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$player_modifier_buff_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerModifierBuffState(player);' "$work_buff_library"
test "$(awk -F '\t' '$1 == "attack_override_by_buff" && $2 == "skill" && $3 == "attack_override_by_buff" { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 2
awk -F '\t' 'NR > 2 {
    uses = 0
    for (column = 8; column <= 16; column += 2)
        if ($column == "attack_override_by_buff") uses++
    if (uses > 0) {
        rows++
        effectUses += uses
        names[$1] = 1
        if ($1 !~ /^attack_override_fs_dm_[1-7][|]fs_flurry_[1-7]$/ ||
            $8 != "attack_override_by_buff" || $9 != 1) exit 2
    }
} END {
    for (name in names) nameCount++
    if (rows != 7 || nameCount != 7 || effectUses != 7) exit 3
}' "$work_buff_table"
attack_override_modifier_inventory_source="$(sed -n '/public static final String\[\] RETIRED_NGE_BUFF_COMBAT_MODIFIERS/,/public static final java.text.NumberFormat/p' "$work_static_item_library")"
test "$(printf '%s' "$attack_override_modifier_inventory_source" | grep -Fc '"attack_override_by_buff"')" -eq 1
attack_override_source="$(sed -n '/public combat_data attackOverrideByBuff/,/public void doKillMeterUpdate/p' "$work_combat_base")"
attack_override_guard_line="$(printf '%s\n' "$attack_override_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
attack_override_cleanup_line="$(printf '%s\n' "$attack_override_source" | grep -Fn 'static_item.removeRetiredNgePlayerSkillStatistics(self);' | head -1 | cut -d: -f1)"
attack_override_return_line="$(printf '%s\n' "$attack_override_source" | grep -Fn 'return actionData;' | head -1 | cut -d: -f1)"
attack_override_reader_line="$(printf '%s\n' "$attack_override_source" | grep -Fn 'getEnhancedSkillStatisticModifierUncapped(self, "attack_override_by_buff")' | head -1 | cut -d: -f1)"
test -n "$attack_override_guard_line"
test -n "$attack_override_cleanup_line"
test -n "$attack_override_return_line"
test -n "$attack_override_reader_line"
test "$attack_override_guard_line" -lt "$attack_override_cleanup_line"
test "$attack_override_cleanup_line" -lt "$attack_override_return_line"
test "$attack_override_return_line" -lt "$attack_override_reader_line"
test "$(grep -Fc 'attackOverrideByBuff(' "$work_combat_base")" -eq 2
attack_override_call_line="$(grep -Fn 'actionData = attackOverrideByBuff(self, actionData);' "$work_combat_base" | head -1 | cut -d: -f1)"
attack_override_caller_guard_line="$(head -n "$attack_override_call_line" "$work_combat_base" | grep -Fn 'if (!precuAuthoritativeAction)' | tail -1 | cut -d: -f1)"
test -n "$attack_override_caller_guard_line"
test "$attack_override_caller_guard_line" -lt "$attack_override_call_line"
retired_buff_command_grants="bh_flawless_strike co_enrage_1 en_action_regen fs_set_heroic_taunt_1 of_deadeye_debuff sm_how_are_you trader_heal trandoshan_ability_1"
test "$(printf '%s\n' $retired_buff_command_grants | wc -l)" -eq 8
for retired_buff_command_grant in $retired_buff_command_grants; do
    awk -F '\t' -v command="$retired_buff_command_grant" '$1 == command && $2 == "commandGrant" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
done
test "$(awk -F '\t' '$2 == "commandGrant" { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 8
awk -F '\t' -v commands="$retired_buff_command_grants" '
BEGIN {
    split(commands, commandList, " ")
    for (commandIndex in commandList) retired[commandList[commandIndex]] = 1
}
NR > 2 {
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2) {
        if ($parameterColumn in retired) {
            rows++
            names[$1] = 1
            break
        }
    }
}
END {
    for (name in names) distinctNames++
    if (rows != 10 || distinctNames != 10) exit 3
}' "$work_buff_table"
player_command_grant_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_BUFF_COMMAND_GRANTS/,/public static boolean isRetiredPostNgePlayerBuffCommandGrant/p' "$work_buff_library")"
for retired_buff_command_grant in $retired_buff_command_grants; do
    test "$(printf '%s' "$player_command_grant_inventory_source" | grep -Fc "\"$retired_buff_command_grant\"")" -eq 1
done
player_command_grant_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerBuffCommandGrant/,/public static boolean isRetiredPostNgePlayerCommandGrantBuff/p' "$work_buff_library")"
printf '%s' "$player_command_grant_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_BUFF_COMMAND_GRANTS'
player_command_grant_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCommandGrantBuff/,/public static void retirePostNgePlayerCommandGrantBuffState/p' "$work_buff_library")"
printf '%s' "$player_command_grant_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$player_command_grant_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$player_command_grant_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerBuffCommandGrant(getEffectParam(data, effect))'
player_command_grant_cleanup_source="$(sed -n '/public static void retirePostNgePlayerCommandGrantBuffState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
printf '%s' "$player_command_grant_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$player_command_grant_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$player_command_grant_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$player_command_grant_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s' "$player_command_grant_cleanup_source" | grep -Fq 'while (hasCommand(player, retiredCommand))'
printf '%s' "$player_command_grant_cleanup_source" | grep -Fq 'revokeCommand(player, retiredCommand)'
grep -Fq 'retirePostNgePlayerCommandGrantBuffState(player);' "$work_buff_library"
command_grant_add_source="$(sed -n '/public int commandGrantAddBuffHandler/,/public int commandGrantRemoveBuffHandler/p' "$work_buff_handler")"
command_grant_remove_source="$(sed -n '/public int commandGrantRemoveBuffHandler/,/public int OnGroupMembersChanged/p' "$work_buff_handler")"
printf '%s' "$command_grant_add_source" | grep -Fq 'isPlayer(self)'
printf '%s' "$command_grant_add_source" | grep -Fq 'buff.isRetiredPostNgePlayerBuffCommandGrant(subType)'
printf '%s' "$command_grant_add_source" | grep -Fq 'while (hasCommand(self, subType))'
printf '%s' "$command_grant_add_source" | grep -Fq 'revokeCommand(self, subType)'
printf '%s' "$command_grant_add_source" | grep -Fq 'grantCommand(self, subType)'
test "$(printf '%s\n' "$command_grant_add_source" | grep -Fn 'buff.isRetiredPostNgePlayerBuffCommandGrant(subType)' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$command_grant_add_source" | grep -Fn 'grantCommand(self, subType)' | head -1 | cut -d: -f1)"
printf '%s' "$command_grant_remove_source" | grep -Fq 'isPlayer(self)'
printf '%s' "$command_grant_remove_source" | grep -Fq 'buff.isRetiredPostNgePlayerBuffCommandGrant(subType)'
printf '%s' "$command_grant_remove_source" | grep -Fq 'while (hasCommand(self, subType))'
printf '%s' "$command_grant_remove_source" | grep -Fq 'revokeCommand(self, subType)'
awk -F '\t' '$1 == "immediate_action_drain" && $2 == "actionDrain" && $3 == "immediate_action_drain" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
BEGIN {
    expected["bh_intimidate"] = "1|1|immediate_action_drain|1||0||0||0||0"
    expected["me_traumatize_1"] = "1|1|immediate_action_drain|1|expertise_action_all|-50||0||0||0"
}
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2) {
        if ($parameterColumn == "immediate_action_drain") ownsEffect = 1
    }
    if (ownsEffect) {
        rows++
        if (!($1 in expected) || seen[$1]++) exit 2
        actual = $7 "|" $22 "|" $8 "|" $9 "|" $10 "|" $11 "|" $12 "|" $13 "|" $14 "|" $15 "|" $16 "|" $17
        if (actual != expected[$1]) exit 2
    }
}
END {
    if (rows != 2) exit 3
    for (name in expected) if (seen[name] != 1) exit 3
}
' "$work_buff_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_ACTION_DRAIN_EFFECT = "immediate_action_drain"' "$work_buff_library"
action_drain_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerActionDrainEffect/,/public static boolean isRetiredPostNgePlayerActionDrainBuff/p' "$work_buff_library")"
printf '%s' "$action_drain_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_ACTION_DRAIN_EFFECT'
action_drain_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerActionDrainBuff/,/public static void retirePostNgePlayerActionDrainState/p' "$work_buff_library")"
printf '%s' "$action_drain_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$action_drain_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$action_drain_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerActionDrainEffect(getEffectParam(data, effect))'
action_drain_cleanup_source="$(sed -n '/public static void retirePostNgePlayerActionDrainState/,/private static final String RETIRED_POST_NGE_PLAYER_ACTION_BURN_EFFECT/p' "$work_buff_library")"
printf '%s' "$action_drain_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$action_drain_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$action_drain_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$action_drain_cleanup_source" | grep -Fq 'isRetiredPostNgePlayerActionDrainBuff(player, data)'
printf '%s' "$action_drain_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerActionDrainState(player);' "$work_buff_library"
action_drain_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
action_drain_admission_line="$(printf '%s\n' "$action_drain_admission_source" | grep -Fn 'isRetiredPostNgePlayerActionDrainBuff(target, bdata)' | head -1 | cut -d: -f1)"
action_drain_refresh_line="$(printf '%s\n' "$action_drain_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$action_drain_admission_line"
test -n "$action_drain_refresh_line"
test "$action_drain_admission_line" -lt "$action_drain_refresh_line"
action_drain_add_source="$(sed -n '/public int actionDrainAddBuffHandler/,/public int actionDrainRemoveBuffHandler/p' "$work_buff_handler")"
action_drain_guard_line="$(printf '%s\n' "$action_drain_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
action_drain_cleanup_line="$(printf '%s\n' "$action_drain_add_source" | grep -Fn 'buff.retirePostNgePlayerActionDrainState(self);' | head -1 | cut -d: -f1)"
action_drain_return_line="$(printf '%s\n' "$action_drain_add_source" | awk -v cleanup="$action_drain_cleanup_line" 'NR > cleanup && /return SCRIPT_CONTINUE;/ { print NR; exit }')"
action_drain_cap_line="$(printf '%s\n' "$action_drain_add_source" | grep -Fn 'if (value > getAction(self))' | head -1 | cut -d: -f1)"
action_drain_write_line="$(printf '%s\n' "$action_drain_add_source" | grep -Fn 'drainAttributes(self, (int)value, 0);' | head -1 | cut -d: -f1)"
action_drain_immunity_check_line="$(printf '%s\n' "$action_drain_add_source" | grep -Fn 'buff.hasBuff(self, "action_drain_immunity")' | head -1 | cut -d: -f1)"
action_drain_immunity_apply_line="$(printf '%s\n' "$action_drain_add_source" | grep -Fn 'buff.applyBuff(self, self, "action_drain_immunity")' | head -1 | cut -d: -f1)"
test "$action_drain_guard_line" -lt "$action_drain_cleanup_line"
test "$action_drain_cleanup_line" -lt "$action_drain_return_line"
test "$action_drain_return_line" -lt "$action_drain_cap_line"
test "$action_drain_cap_line" -lt "$action_drain_write_line"
test "$action_drain_write_line" -lt "$action_drain_immunity_check_line"
test "$action_drain_immunity_check_line" -lt "$action_drain_immunity_apply_line"
awk -F '\t' '$1 == "action_burn" && $2 == "actionBurn" && $3 == "action_burn" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
BEGIN {
    expected["me_rheumatic_calamity_1"] = "10|1|action_burn|65||0||0||0||0"
    expected["closed_fist_toxin"] = "60|1|action_burn|100||0||0||0||0"
    expected["jedi_statue_dark_debuff_light"] = "30|1|action_burn|100|private_armor_break|100|combat_parry_reduction|-200|expertise_block_chance|-20||0"
    expected["wod_agony"] = "30|1|action_burn|25||0||0||0||0"
    expected["of_deadeye_debuff"] = "15|1|action_burn|50|glancing_blow_vulnerable|30||0||0||0"
}
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2) {
        if ($parameterColumn == "action_burn") ownsEffect = 1
    }
    if (ownsEffect) {
        rows++
        if (!($1 in expected) || seen[$1]++) exit 2
        actual = $7 "|" $22 "|" $8 "|" $9 "|" $10 "|" $11 "|" $12 "|" $13 "|" $14 "|" $15 "|" $16 "|" $17
        if (actual != expected[$1]) exit 2
    }
}
END {
    if (rows != 5) exit 3
    for (name in expected) if (seen[name] != 1) exit 3
}
' "$work_buff_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_ACTION_BURN_EFFECT = "action_burn"' "$work_buff_library"
action_burn_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerActionBurnEffect/,/public static boolean isRetiredPostNgePlayerActionBurnBuff/p' "$work_buff_library")"
printf '%s' "$action_burn_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_ACTION_BURN_EFFECT'
action_burn_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerActionBurnBuff/,/public static void clearPostNgePlayerActionBurnScriptVars/p' "$work_buff_library")"
printf '%s' "$action_burn_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$action_burn_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$action_burn_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerActionBurnEffect(getEffectParam(data, effect))'
action_burn_script_var_cleanup_source="$(sed -n '/public static void clearPostNgePlayerActionBurnScriptVars/,/public static void retirePostNgePlayerActionBurnState/p' "$work_buff_library")"
printf '%s' "$action_burn_script_var_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$action_burn_script_var_cleanup_source" | grep -Fq 'utils.removeScriptVarTree(player, "buff.action_burn")'
action_burn_cleanup_source="$(sed -n '/public static void retirePostNgePlayerActionBurnState/,/private static final String RETIRED_POST_NGE_PLAYER_ACTION_REGEN_EFFECT/p' "$work_buff_library")"
printf '%s' "$action_burn_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$action_burn_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$action_burn_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$action_burn_cleanup_source" | grep -Fq 'isRetiredPostNgePlayerActionBurnBuff(player, data)'
action_burn_remove_line="$(printf '%s\n' "$action_burn_cleanup_source" | grep -Fn 'removeBuff(player, activeBuff)' | head -1 | cut -d: -f1)"
action_burn_clear_line="$(printf '%s\n' "$action_burn_cleanup_source" | grep -Fn 'clearPostNgePlayerActionBurnScriptVars(player);' | head -1 | cut -d: -f1)"
test -n "$action_burn_remove_line"
test -n "$action_burn_clear_line"
test "$action_burn_remove_line" -lt "$action_burn_clear_line"
grep -Fq 'retirePostNgePlayerActionBurnState(player);' "$work_buff_library"
action_burn_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
action_burn_admission_line="$(printf '%s\n' "$action_burn_admission_source" | grep -Fn 'isRetiredPostNgePlayerActionBurnBuff(target, bdata)' | head -1 | cut -d: -f1)"
action_burn_refresh_line="$(printf '%s\n' "$action_burn_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$action_burn_admission_line"
test -n "$action_burn_refresh_line"
test "$action_burn_admission_line" -lt "$action_burn_refresh_line"
action_burn_add_source="$(sed -n '/public int actionBurnAddBuffHandler/,/public int actionBurnRemoveBuffHandler/p' "$work_buff_handler")"
action_burn_add_guard_line="$(printf '%s\n' "$action_burn_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
action_burn_add_cleanup_line="$(printf '%s\n' "$action_burn_add_source" | grep -Fn 'buff.retirePostNgePlayerActionBurnState(self);' | head -1 | cut -d: -f1)"
action_burn_add_return_line="$(printf '%s\n' "$action_burn_add_source" | awk -v cleanup="$action_burn_add_cleanup_line" 'NR > cleanup && /return SCRIPT_CONTINUE;/ { print NR; exit }')"
action_burn_add_write_line="$(printf '%s\n' "$action_burn_add_source" | grep -Fn 'utils.setScriptVar(self, "buff.action_burn.value", value)' | head -1 | cut -d: -f1)"
test "$action_burn_add_guard_line" -lt "$action_burn_add_cleanup_line"
test "$action_burn_add_cleanup_line" -lt "$action_burn_add_return_line"
test "$action_burn_add_return_line" -lt "$action_burn_add_write_line"
action_burn_remove_source="$(sed -n '/public int actionBurnRemoveBuffHandler/,/public int actionRegenAddBuffHandler/p' "$work_buff_handler")"
action_burn_remove_guard_line="$(printf '%s\n' "$action_burn_remove_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
action_burn_remove_cleanup_line="$(printf '%s\n' "$action_burn_remove_source" | grep -Fn 'buff.clearPostNgePlayerActionBurnScriptVars(self);' | head -1 | cut -d: -f1)"
action_burn_remove_return_line="$(printf '%s\n' "$action_burn_remove_source" | awk -v cleanup="$action_burn_remove_cleanup_line" 'NR > cleanup && /return SCRIPT_CONTINUE;/ { print NR; exit }')"
action_burn_remove_write_line="$(printf '%s\n' "$action_burn_remove_source" | grep -Fn 'utils.removeScriptVar(self, "buff.action_burn.value")' | head -1 | cut -d: -f1)"
test "$action_burn_remove_guard_line" -lt "$action_burn_remove_cleanup_line"
test "$action_burn_remove_cleanup_line" -lt "$action_burn_remove_return_line"
test "$action_burn_remove_return_line" -lt "$action_burn_remove_write_line"
action_burn_dictionary_cost_source="$(sed -n '/public static int\[\] getActionCost(obj_id self, weapon_data weaponData, dictionary actionData)/,/public static int\[\] getActionCost(obj_id self, weapon_data weaponData, combat_data actionData)/p' "$work_combat_library")"
action_burn_typed_cost_source="$(sed -n '/public static int\[\] getActionCost(obj_id self, weapon_data weaponData, combat_data actionData)/,/public static int\[\] getSuccessBasedSingleTargetActionCost/p' "$work_combat_library")"
for action_burn_consumer_source in "$action_burn_dictionary_cost_source" "$action_burn_typed_cost_source"; do
    test "$(printf '%s' "$action_burn_consumer_source" | grep -Fc 'buff.retirePostNgePlayerActionBurnState(self);')" -eq 1
    action_burn_consumer_guard_line="$(printf '%s\n' "$action_burn_consumer_source" | grep -Fn 'if (isPlayer(self))' | tail -1 | cut -d: -f1)"
    action_burn_consumer_cleanup_line="$(printf '%s\n' "$action_burn_consumer_source" | grep -Fn 'buff.retirePostNgePlayerActionBurnState(self);' | head -1 | cut -d: -f1)"
    action_burn_consumer_read_line="$(printf '%s\n' "$action_burn_consumer_source" | grep -Fn 'utils.hasScriptVar(self, "buff.action_burn.value")' | head -1 | cut -d: -f1)"
    test "$action_burn_consumer_guard_line" -lt "$action_burn_consumer_cleanup_line"
    test "$action_burn_consumer_cleanup_line" -lt "$action_burn_consumer_read_line"
done
awk -F '\t' '$1 == "action_regen" && $2 == "actionRegen" && $3 == "N_A" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2) {
        if ($parameterColumn == "action_regen") ownsEffect = 1
    }
    if (ownsEffect) {
        rows++
        if ($1 != "sp_action_regen" || $7 != "15" ||
            $8 != "action_regen" || $9 != "0" ||
            $10 != "movement" || $11 != "2" ||
            $22 != "1" || $23 != "0" || $25 != "1" ||
            $26 != "1" || $27 != "1" || $30 != "1") exit 2
    }
}
END { if (rows != 1) exit 3 }
' "$work_buff_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_ACTION_REGEN_EFFECT = "action_regen"' "$work_buff_library"
action_regen_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerActionRegenEffect/,/public static boolean isRetiredPostNgePlayerActionRegenBuff/p' "$work_buff_library")"
printf '%s' "$action_regen_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_ACTION_REGEN_EFFECT'
action_regen_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerActionRegenBuff/,/public static void retirePostNgePlayerActionRegenState/p' "$work_buff_library")"
printf '%s' "$action_regen_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$action_regen_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$action_regen_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerActionRegenEffect(getEffectParam(data, effect))'
action_regen_cleanup_source="$(sed -n '/public static void retirePostNgePlayerActionRegenState/,/private static final String RETIRED_POST_NGE_PLAYER_DAMAGE_DEALT_OVERRIDE_EFFECT/p' "$work_buff_library")"
printf '%s' "$action_regen_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$action_regen_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$action_regen_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$action_regen_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerActionRegenState(player);' "$work_buff_library"
action_regen_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
action_regen_admission_line="$(printf '%s\n' "$action_regen_admission_source" | grep -Fn 'isRetiredPostNgePlayerActionRegenBuff(target, bdata)' | head -1 | cut -d: -f1)"
action_regen_refresh_line="$(printf '%s\n' "$action_regen_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$action_regen_admission_line"
test -n "$action_regen_refresh_line"
test "$action_regen_admission_line" -lt "$action_regen_refresh_line"
action_regen_add_source="$(sed -n '/public int actionRegenAddBuffHandler/,/public int actionRegenRemoveBuffHandler/p' "$work_buff_handler")"
action_regen_add_guard_line="$(printf '%s\n' "$action_regen_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
action_regen_add_cleanup_line="$(printf '%s\n' "$action_regen_add_source" | grep -Fn 'buff.retirePostNgePlayerActionRegenState(self);' | head -1 | cut -d: -f1)"
action_regen_add_return_line="$(printf '%s\n' "$action_regen_add_source" | awk -v cleanup="$action_regen_add_cleanup_line" 'NR > cleanup && /return SCRIPT_CONTINUE;/ { print NR; exit }')"
action_regen_add_max_line="$(printf '%s\n' "$action_regen_add_source" | grep -Fn 'int actionMax = getMaxAction(self);' | head -1 | cut -d: -f1)"
test "$action_regen_add_guard_line" -lt "$action_regen_add_cleanup_line"
test "$action_regen_add_cleanup_line" -lt "$action_regen_add_return_line"
test "$action_regen_add_return_line" -lt "$action_regen_add_max_line"
action_regen_tick_source="$(sed -n '/public int actionRegenBuff(obj_id self, dictionary params)/,/public int bodyguardDefenderAddBuffHandler/p' "$work_buff_handler")"
action_regen_tick_guard_line="$(printf '%s\n' "$action_regen_tick_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
action_regen_tick_cleanup_line="$(printf '%s\n' "$action_regen_tick_source" | grep -Fn 'buff.retirePostNgePlayerActionRegenState(self);' | head -1 | cut -d: -f1)"
action_regen_tick_return_line="$(printf '%s\n' "$action_regen_tick_source" | awk -v cleanup="$action_regen_tick_cleanup_line" 'NR > cleanup && /return SCRIPT_CONTINUE;/ { print NR; exit }')"
action_regen_tick_buff_line="$(printf '%s\n' "$action_regen_tick_source" | grep -Fn 'buff.hasBuff(self, buffName)' | head -1 | cut -d: -f1)"
action_regen_tick_heal_line="$(printf '%s\n' "$action_regen_tick_source" | grep -Fn 'healing.healDamage(self, ACTION, (int)healAmount);' | head -1 | cut -d: -f1)"
action_regen_tick_requeue_line="$(printf '%s\n' "$action_regen_tick_source" | grep -Fn 'messageTo(self, "actionRegenBuff", params, 1.0f, false);' | head -1 | cut -d: -f1)"
test "$action_regen_tick_guard_line" -lt "$action_regen_tick_cleanup_line"
test "$action_regen_tick_cleanup_line" -lt "$action_regen_tick_return_line"
test "$action_regen_tick_return_line" -lt "$action_regen_tick_buff_line"
test "$action_regen_tick_buff_line" -lt "$action_regen_tick_heal_line"
test "$action_regen_tick_heal_line" -lt "$action_regen_tick_requeue_line"
awk -F '\t' '$1 == "damage_dealt_mod" && $2 == "damageDealtMod" && $3 == "damage_dealt_mod" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
BEGIN {
    expected["bm_enrage"] = "2"
    expected["kun_one_sacrifice"] = "1.25"
    expected["kun_two_sacrifice"] = "1.5"
    expected["kun_three_sacrifice"] = "1.75"
    expected["kun_four_sacrifice"] = "2"
    expected["kun_five_sacrifice"] = "2.25"
    expected["kun_six_sacrifice"] = "2.5"
    expected["kun_seven_sacrifice"] = "2.75"
    expected["kun_eight_sacrifice"] = "3"
    expected["minder_add_debuff"] = "0.5"
    expected["open_add_debuff"] = "0.9"
}
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2) {
        if ($parameterColumn == "damage_dealt_mod") ownsEffect = 1
    }
    if (ownsEffect) {
        rows++
        seen[$1]++
        if (!($1 in expected) || $8 != "damage_dealt_mod" || $9 != expected[$1] || $30 != "1") exit 2
    }
}
END {
    if (rows != 11) exit 3
    for (name in expected) if (seen[name] != 1) exit 4
}
' "$work_buff_table"
damage_dealt_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerDamageDealtOverrideEffect/,/public static boolean isRetiredPostNgePlayerDamageDealtOverrideBuff/p' "$work_buff_library")"
printf '%s' "$damage_dealt_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_DAMAGE_DEALT_OVERRIDE_EFFECT'
grep -Fq 'RETIRED_POST_NGE_PLAYER_DAMAGE_DEALT_OVERRIDE_EFFECT = "damage_dealt_mod"' "$work_buff_library"
damage_dealt_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerDamageDealtOverrideBuff/,/public static void restorePostNgePlayerDamageDealtOverride/p' "$work_buff_library")"
printf '%s' "$damage_dealt_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$damage_dealt_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$damage_dealt_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerDamageDealtOverrideEffect(getEffectParam(data, effect))'
damage_dealt_restore_source="$(sed -n '/public static void restorePostNgePlayerDamageDealtOverride/,/public static void retirePostNgePlayerDamageDealtOverrideState/p' "$work_buff_library")"
damage_dealt_scale_read_line="$(printf '%s\n' "$damage_dealt_restore_source" | grep -Fn 'utils.getFloatScriptVar(player, "damageDealtMod.scale")' | head -1 | cut -d: -f1)"
damage_dealt_state_clear_line="$(printf '%s\n' "$damage_dealt_restore_source" | grep -Fn 'utils.removeScriptVarTree(player, "damageDealtMod")' | head -1 | cut -d: -f1)"
damage_dealt_scale_restore_line="$(printf '%s\n' "$damage_dealt_restore_source" | grep -Fn 'setScale(player, recordedScale)' | head -1 | cut -d: -f1)"
test "$damage_dealt_scale_read_line" -lt "$damage_dealt_state_clear_line"
test "$damage_dealt_state_clear_line" -lt "$damage_dealt_scale_restore_line"
printf '%s' "$damage_dealt_restore_source" | grep -Fq 'recordedScale > 0.0f'
damage_dealt_cleanup_source="$(sed -n '/public static void retirePostNgePlayerDamageDealtOverrideState/,/private static final String RETIRED_POST_NGE_PLAYER_WEAPON_SPEED_OVERRIDE_EFFECT/p' "$work_buff_library")"
printf '%s' "$damage_dealt_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$damage_dealt_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$damage_dealt_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s' "$damage_dealt_cleanup_source" | grep -Fq 'restorePostNgePlayerDamageDealtOverride(player)'
grep -Fq 'retirePostNgePlayerDamageDealtOverrideState(player);' "$work_buff_library"
damage_dealt_add_source="$(sed -n '/public int damageDealtModAddBuffHandler/,/public int damageDealtModRemoveBuffHandler/p' "$work_buff_handler")"
damage_dealt_remove_source="$(sed -n '/public int damageDealtModRemoveBuffHandler/,/public int weaponSpeedModAddBuffHandler/p' "$work_buff_handler")"
for damage_dealt_handler_source in "$damage_dealt_add_source" "$damage_dealt_remove_source"; do
    damage_dealt_player_guard_line="$(printf '%s\n' "$damage_dealt_handler_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
    damage_dealt_player_restore_line="$(printf '%s\n' "$damage_dealt_handler_source" | grep -Fn 'buff.restorePostNgePlayerDamageDealtOverride(self);' | head -1 | cut -d: -f1)"
    damage_dealt_player_return_line="$(printf '%s\n' "$damage_dealt_handler_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)"
    test "$damage_dealt_player_guard_line" -lt "$damage_dealt_player_restore_line"
    test "$damage_dealt_player_restore_line" -lt "$damage_dealt_player_return_line"
done
test "$damage_dealt_player_return_line" -lt "$(printf '%s\n' "$damage_dealt_remove_source" | grep -Fn 'utils.getFloatScriptVar(self, "damageDealtMod.scale")' | head -1 | cut -d: -f1)"
test "$(printf '%s\n' "$damage_dealt_add_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$damage_dealt_add_source" | grep -Fn 'utils.setScriptVar(self, "damageDealtMod.value", value)' | head -1 | cut -d: -f1)"
raw_damage_source="$(sed -n '/public dictionary getRawDamage(/,/public dictionary getPrecuCore3RawDamage(/p' "$work_combat_base")"
damage_dealt_consumer_guard_line="$(printf '%s\n' "$raw_damage_source" | grep -Fn 'if (isPlayer(attacker))' | head -1 | cut -d: -f1)"
damage_dealt_consumer_cleanup_line="$(printf '%s\n' "$raw_damage_source" | grep -Fn 'buff.restorePostNgePlayerDamageDealtOverride(attacker);' | head -1 | cut -d: -f1)"
damage_dealt_consumer_read_line="$(printf '%s\n' "$raw_damage_source" | grep -Fn 'utils.getFloatScriptVar(attacker, "damageDealtMod.value")' | head -1 | cut -d: -f1)"
test "$damage_dealt_consumer_guard_line" -lt "$damage_dealt_consumer_cleanup_line"
test "$damage_dealt_consumer_cleanup_line" -lt "$damage_dealt_consumer_read_line"
printf '%s' "$raw_damage_source" | grep -Fq 'minDamage *= enragedMod'
printf '%s' "$raw_damage_source" | grep -Fq 'maxDamage *= enragedMod'
awk -F '\t' '$1 == "weapon_speed_mod" && $2 == "weaponSpeedMod" && $3 == "weapon_speed_mod" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2) {
        if ($parameterColumn == "weapon_speed_mod") ownsEffect = 1
    }
    if (ownsEffect) {
        rows++
        if ($1 != "bm_frenzy" || $8 != "weapon_speed_mod" || $9 != "40" || $30 != "1") exit 2
    }
}
END { if (rows != 1) exit 3 }
' "$work_buff_table"
weapon_speed_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerWeaponSpeedOverrideEffect/,/public static boolean isRetiredPostNgePlayerWeaponSpeedOverrideBuff/p' "$work_buff_library")"
printf '%s' "$weapon_speed_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_WEAPON_SPEED_OVERRIDE_EFFECT'
grep -Fq 'RETIRED_POST_NGE_PLAYER_WEAPON_SPEED_OVERRIDE_EFFECT = "weapon_speed_mod"' "$work_buff_library"
weapon_speed_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerWeaponSpeedOverrideBuff/,/public static void restorePostNgePlayerWeaponSpeedOverride/p' "$work_buff_library")"
printf '%s' "$weapon_speed_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$weapon_speed_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$weapon_speed_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerWeaponSpeedOverrideEffect(getEffectParam(data, effect))'
weapon_speed_restore_source="$(sed -n '/public static void restorePostNgePlayerWeaponSpeedOverride/,/public static void retirePostNgePlayerWeaponSpeedOverrideState/p' "$work_buff_library")"
weapon_speed_record_read_line="$(printf '%s\n' "$weapon_speed_restore_source" | grep -Fn 'utils.getStringScriptVar(player, "recordedAttackSpeed")' | head -1 | cut -d: -f1)"
weapon_speed_record_clear_line="$(printf '%s\n' "$weapon_speed_restore_source" | grep -Fn 'utils.removeScriptVar(player, "recordedAttackSpeed")' | head -1 | cut -d: -f1)"
weapon_speed_record_parse_line="$(printf '%s\n' "$weapon_speed_restore_source" | grep -Fn "split(weaponRecord, '-')" | head -1 | cut -d: -f1)"
test "$weapon_speed_record_read_line" -lt "$weapon_speed_record_clear_line"
test "$weapon_speed_record_clear_line" -lt "$weapon_speed_record_parse_line"
printf '%s' "$weapon_speed_restore_source" | grep -Fq 'utils.isNestedWithin(weapon, player)'
printf '%s' "$weapon_speed_restore_source" | grep -Fq 'weaponSpeed <= 0.0f'
printf '%s' "$weapon_speed_restore_source" | grep -Fq 'setWeaponAttackSpeed(weapon, weaponSpeed)'
printf '%s' "$weapon_speed_restore_source" | grep -Fq 'weapons.setWeaponData(weapon)'
printf '%s' "$weapon_speed_restore_source" | grep -Fq 'utils.removeScriptVar(weapon, "isCreatureWeapon")'
weapon_speed_cleanup_source="$(sed -n '/public static void retirePostNgePlayerWeaponSpeedOverrideState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_CRITICAL_OVERRIDE_EFFECTS/p' "$work_buff_library")"
printf '%s' "$weapon_speed_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$weapon_speed_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$weapon_speed_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s' "$weapon_speed_cleanup_source" | grep -Fq 'restorePostNgePlayerWeaponSpeedOverride(player)'
grep -Fq 'retirePostNgePlayerWeaponSpeedOverrideState(player);' "$work_buff_library"
weapon_speed_add_source="$(sed -n '/public int weaponSpeedModAddBuffHandler/,/public int weaponSpeedModRemoveBuffHandler/p' "$work_buff_handler")"
weapon_speed_remove_source="$(sed -n '/public int weaponSpeedModRemoveBuffHandler/,/public int commandGrantAddBuffHandler/p' "$work_buff_handler")"
for weapon_speed_handler_source in "$weapon_speed_add_source" "$weapon_speed_remove_source"; do
    weapon_speed_player_guard_line="$(printf '%s\n' "$weapon_speed_handler_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
    weapon_speed_player_restore_line="$(printf '%s\n' "$weapon_speed_handler_source" | grep -Fn 'buff.restorePostNgePlayerWeaponSpeedOverride(self);' | head -1 | cut -d: -f1)"
    weapon_speed_player_return_line="$(printf '%s\n' "$weapon_speed_handler_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)"
    test "$weapon_speed_player_guard_line" -lt "$weapon_speed_player_restore_line"
    test "$weapon_speed_player_restore_line" -lt "$weapon_speed_player_return_line"
done
test "$weapon_speed_player_return_line" -lt "$(printf '%s\n' "$weapon_speed_remove_source" | grep -Fn 'utils.hasScriptVar(self, "recordedAttackSpeed")' | head -1 | cut -d: -f1)"
test "$(printf '%s\n' "$weapon_speed_add_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$weapon_speed_add_source" | grep -Fn 'getCurrentWeapon(self)' | head -1 | cut -d: -f1)"
retired_critical_override_effects="expertise_next_hit_crit expertise_crit_double_damage expertise_crit_root expertise_crit_remove_buff"
test "$(printf '%s\n' $retired_critical_override_effects | wc -l)" -eq 4
for retired_critical_override_effect in $retired_critical_override_effects; do
    case "$retired_critical_override_effect" in
        expertise_next_hit_crit) expected_critical_override_type=nextHitCrit ;;
        expertise_crit_double_damage) expected_critical_override_type=critDoubleDamage ;;
        expertise_crit_root) expected_critical_override_type=critRoot ;;
        expertise_crit_remove_buff) expected_critical_override_type=critOnce ;;
        *) exit 3 ;;
    esac
    awk -F '\t' -v effect="$retired_critical_override_effect" -v type="$expected_critical_override_type" '$1 == effect && $2 == type { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
done
awk -F '\t' -v effects="$retired_critical_override_effects" '
BEGIN {
    split(effects, effectList, " ")
    for (effectIndex in effectList) retired[effectList[effectIndex]] = 1
}
NR > 2 {
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2) {
        if ($parameterColumn in retired) {
            rows++
            names[$1] = 1
            break
        }
    }
}
END {
    if (!("sm_off_the_cuff" in names) || !("sm_end_of_the_line" in names) || !("sm_nerf_herder" in names)) exit 2
    for (name in names) distinctNames++
    if (rows != 3 || distinctNames != 3) exit 3
}' "$work_buff_table"
critical_override_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_CRITICAL_OVERRIDE_EFFECTS/,/public static boolean isRetiredPostNgePlayerCriticalOverrideEffect/p' "$work_buff_library")"
for retired_critical_override_effect in $retired_critical_override_effects; do
    test "$(printf '%s' "$critical_override_inventory_source" | grep -Fc "\"$retired_critical_override_effect\"")" -eq 1
done
critical_override_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCriticalOverrideEffect/,/public static boolean isRetiredPostNgePlayerCriticalOverrideBuff/p' "$work_buff_library")"
printf '%s' "$critical_override_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_CRITICAL_OVERRIDE_EFFECTS'
critical_override_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCriticalOverrideBuff/,/public static void clearPostNgePlayerCriticalOverrideScriptVars/p' "$work_buff_library")"
printf '%s' "$critical_override_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$critical_override_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$critical_override_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerCriticalOverrideEffect(getEffectParam(data, effect))'
critical_override_script_var_cleanup_source="$(sed -n '/public static void clearPostNgePlayerCriticalOverrideScriptVars/,/public static void retirePostNgePlayerCriticalOverrideState/p' "$work_buff_library")"
printf '%s' "$critical_override_script_var_cleanup_source" | grep -Fq '!isPlayer(player)'
for retired_critical_override_script_var in nextCritHit critDoubleDamage critRoot critRemoveBuffNames; do
    test "$(printf '%s' "$critical_override_script_var_cleanup_source" | grep -Fc "utils.removeScriptVarTree(player, \"$retired_critical_override_script_var\")")" -eq 1
done
critical_override_cleanup_source="$(sed -n '/public static void retirePostNgePlayerCriticalOverrideState/,/public static boolean isRetiredPostNgePlayerLuckHitOverrideEffect/p' "$work_buff_library")"
printf '%s' "$critical_override_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$critical_override_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$critical_override_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s' "$critical_override_cleanup_source" | grep -Fq 'clearPostNgePlayerCriticalOverrideScriptVars(player)'
grep -Fq 'retirePostNgePlayerCriticalOverrideState(player);' "$work_buff_library"
for critical_override_handler in nextHitCritAddBuffHandler nextHitCritRemoveBuffHandler critDoubleDamageAddBuffHandler critDoubleDamageRemoveBuffHandler critRootAddBuffHandler critRootRemoveBuffHandler critOnceAddBuffHandler critOnceRemoveBuffHandler; do
    critical_override_handler_source="$(sed -n "/public int $critical_override_handler(/,/^    }/p" "$work_buff_handler")"
    critical_override_handler_guard_line="$(printf '%s\n' "$critical_override_handler_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
    critical_override_handler_cleanup_line="$(printf '%s\n' "$critical_override_handler_source" | grep -Fn 'buff.clearPostNgePlayerCriticalOverrideScriptVars(self);' | head -1 | cut -d: -f1)"
    critical_override_handler_return_line="$(printf '%s\n' "$critical_override_handler_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)"
    critical_override_handler_writer_line="$(printf '%s\n' "$critical_override_handler_source" | grep -Fn 'utils.' | head -1 | cut -d: -f1)"
    test "$critical_override_handler_guard_line" -lt "$critical_override_handler_cleanup_line"
    test "$critical_override_handler_cleanup_line" -lt "$critical_override_handler_return_line"
    test "$critical_override_handler_return_line" -lt "$critical_override_handler_writer_line"
done
critical_override_hit_cleanup_line="$(grep -Fn 'buff.clearPostNgePlayerCriticalOverrideScriptVars(attackerData.id);' "$work_combat_base" | head -1 | cut -d: -f1)"
critical_override_next_hit_read_line="$(grep -Fn '"nextCritHit"' "$work_combat_base" | head -1 | cut -d: -f1)"
critical_override_remove_read_line="$(grep -Fn '"critRemoveBuffNames"' "$work_combat_base" | head -1 | cut -d: -f1)"
critical_override_damage_cleanup_line="$(grep -Fn 'buff.clearPostNgePlayerCriticalOverrideScriptVars(attacker);' "$work_combat_base" | head -1 | cut -d: -f1)"
critical_override_double_read_line="$(grep -Fn '"critDoubleDamage"' "$work_combat_base" | head -1 | cut -d: -f1)"
critical_override_root_read_line="$(grep -Fn '"critRoot"' "$work_combat_base" | head -1 | cut -d: -f1)"
test "$critical_override_hit_cleanup_line" -lt "$critical_override_next_hit_read_line"
test "$critical_override_hit_cleanup_line" -lt "$critical_override_remove_read_line"
test "$critical_override_damage_cleanup_line" -lt "$critical_override_double_read_line"
test "$critical_override_damage_cleanup_line" -lt "$critical_override_root_read_line"
# Shifty Setup is retained NGE Spy compatibility data. Its generic
# onAttackRemove state must be unreachable and cleared for PRE-CU players,
# while non-player content retains the original handler path.
awk -F '\t' '$1 == "on_attack_remove" { found++; if ($2 != "onAttackRemove" || $3 != "on_attack_remove") exit 2 } END { if (found != 2) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '$1 == "sp_shifty_setup" { found++; if ($14 != "on_attack_remove" || $15 != 1) exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && $1 == "expertise_sp_shifty_setup_1" { found++; if ($(fieldIndex["COMMANDS"]) != "sp_shifty_setup") exit 2 }
END { if (found != 1) exit 3 }
' "$work_skills_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_EFFECT = "on_attack_remove"' "$work_buff_library"
grep -Fq 'RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_BUFF = "sp_shifty_setup"' "$work_buff_library"
spy_shifty_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerOnAttackRemoveBuff(obj_id target/,/public static void clearPostNgePlayerOnAttackRemoveState/p' "$work_buff_library")"
printf '%s\n' "$spy_shifty_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$spy_shifty_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$spy_shifty_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerOnAttackRemoveEffect(getEffectParam(data, effect))'
spy_shifty_state_source="$(sed -n '/public static void clearPostNgePlayerOnAttackRemoveState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_LUCK_HIT_OVERRIDE_EFFECTS/p' "$work_buff_library")"
printf '%s\n' "$spy_shifty_state_source" | grep -Fq 'utils.removeScriptVarTree(player, ON_ATTACK_REMOVE)'
printf '%s\n' "$spy_shifty_state_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s\n' "$spy_shifty_state_source" | grep -Fq 'clearPostNgePlayerOnAttackRemoveState(player)'
grep -Fq 'retirePostNgePlayerOnAttackRemoveState(player);' "$work_buff_library"
spy_shifty_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static float getBuffTimeRemaining/p' "$work_buff_library")"
spy_shifty_admission_line="$(printf '%s\n' "$spy_shifty_admission_source" | grep -Fn 'isRetiredPostNgePlayerOnAttackRemoveBuff(target, bdata)' | head -1 | cut -d: -f1)"
spy_shifty_existing_line="$(printf '%s\n' "$spy_shifty_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$spy_shifty_admission_line"
test -n "$spy_shifty_existing_line"
test "$spy_shifty_admission_line" -lt "$spy_shifty_existing_line"
verify_spy_shifty_source_handler()
{
    spy_shifty_method="$1"
    spy_shifty_next="$2"
    spy_shifty_source="$(sed -n "/public int $spy_shifty_method/,/public int $spy_shifty_next/p" "$work_buff_handler")"
    spy_shifty_guard_line="$(printf '%s\n' "$spy_shifty_source" | grep -Fn 'isPlayer(self)' | head -1 | cut -d: -f1)"
    spy_shifty_effect_line="$(printf '%s\n' "$spy_shifty_source" | grep -Fn 'isRetiredPostNgePlayerOnAttackRemoveEffect(effectName)' | head -1 | cut -d: -f1)"
    spy_shifty_name_line="$(printf '%s\n' "$spy_shifty_source" | grep -Fn 'isRetiredPostNgePlayerOnAttackRemoveBuffName(buffName)' | head -1 | cut -d: -f1)"
    spy_shifty_cleanup_line="$(printf '%s\n' "$spy_shifty_source" | grep -Fn 'buff.clearPostNgePlayerOnAttackRemoveState(self);' | head -1 | cut -d: -f1)"
    spy_shifty_return_line="$(printf '%s\n' "$spy_shifty_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
    spy_shifty_writer_line="$(printf '%s\n' "$spy_shifty_source" | grep -Fn 'Vector removeBuffs' | head -1 | cut -d: -f1)"
    test "$spy_shifty_guard_line" -lt "$spy_shifty_effect_line"
    test "$spy_shifty_guard_line" -lt "$spy_shifty_name_line"
    test "$spy_shifty_name_line" -lt "$spy_shifty_cleanup_line"
    test "$spy_shifty_cleanup_line" -lt "$spy_shifty_return_line"
    test "$spy_shifty_return_line" -lt "$spy_shifty_writer_line"
}
verify_spy_shifty_source_handler onAttackRemoveAddBuffHandler onAttackRemoveRemoveBuffHandler
verify_spy_shifty_source_handler onAttackRemoveRemoveBuffHandler supression_handlerAddBuffHandler
spy_shifty_combat_cleanup_line="$(grep -Fn 'buff.clearPostNgePlayerOnAttackRemoveState(attackerData.id);' "$work_combat_base" | head -1 | cut -d: -f1)"
spy_shifty_combat_consumer_line="$(grep -Fn 'utils.hasScriptVar(attackerData.id, buff.ON_ATTACK_REMOVE)' "$work_combat_base" | head -1 | cut -d: -f1)"
test -n "$spy_shifty_combat_cleanup_line"
test -n "$spy_shifty_combat_consumer_line"
test "$spy_shifty_combat_cleanup_line" -lt "$spy_shifty_combat_consumer_line"
retired_luck_hit_effects="sm_impossible_odds sm_skullduggery"
test "$(printf '%s\n' $retired_luck_hit_effects | wc -l)" -eq 2
for retired_luck_hit_effect in $retired_luck_hit_effects; do
    case "$retired_luck_hit_effect" in
        sm_impossible_odds)
            expected_luck_hit_type=hitByLuck
            expected_luck_hit_subtype=combat_all_attack_hit_by_luck
            ;;
        sm_skullduggery)
            expected_luck_hit_type=missByLuck
            expected_luck_hit_subtype=combat_all_attack_miss_by_luck
            ;;
        *) exit 3 ;;
    esac
    awk -F '\t' -v effect="$retired_luck_hit_effect" -v type="$expected_luck_hit_type" -v subtype="$expected_luck_hit_subtype" '$1 == effect && $2 == type && $3 == subtype { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
done
awk -F '\t' '
BEGIN {
    expected["sm_impossible_odds"] = "4|1|sm_impossible_odds|4||0||0||0||0"
    expected["sm_skullduggery"] = "4|1|sm_skullduggery|4||0||0||0||0"
}
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2) {
        if ($parameterColumn == "sm_impossible_odds" || $parameterColumn == "sm_skullduggery") ownsEffect = 1
    }
    if (ownsEffect) {
        rows++
        if (!($1 in expected) || seen[$1]++) exit 2
        actual = $7 "|" $30 "|" $8 "|" $9 "|" $10 "|" $11 "|" $12 "|" $13 "|" $14 "|" $15 "|" $16 "|" $17
        if (actual != expected[$1]) exit 2
    }
}
END {
    if (rows != 2 || !("sm_impossible_odds" in seen) || !("sm_skullduggery" in seen)) exit 3
}' "$work_buff_table"
luck_hit_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_LUCK_HIT_OVERRIDE_EFFECTS/,/public static boolean isRetiredPostNgePlayerLuckHitOverrideEffect/p' "$work_buff_library")"
for retired_luck_hit_effect in $retired_luck_hit_effects; do
    test "$(printf '%s' "$luck_hit_inventory_source" | grep -Fc "\"$retired_luck_hit_effect\"")" -eq 1
done
luck_hit_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerLuckHitOverrideEffect/,/public static boolean isRetiredPostNgePlayerLuckHitOverrideBuff/p' "$work_buff_library")"
printf '%s' "$luck_hit_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_LUCK_HIT_OVERRIDE_EFFECTS'
luck_hit_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerLuckHitOverrideBuff/,/public static void clearPostNgePlayerLuckHitOverrideModifiers/p' "$work_buff_library")"
printf '%s' "$luck_hit_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$luck_hit_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$luck_hit_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerLuckHitOverrideEffect(getEffectParam(data, effect))'
luck_hit_modifier_cleanup_source="$(sed -n '/public static void clearPostNgePlayerLuckHitOverrideModifiers/,/public static void retirePostNgePlayerLuckHitOverrideState/p' "$work_buff_library")"
printf '%s' "$luck_hit_modifier_cleanup_source" | grep -Fq '!isPlayer(player)'
for retired_luck_hit_modifier in hitByLuck increaseHitByLuck missByLuck; do
    test "$(printf '%s' "$luck_hit_modifier_cleanup_source" | grep -Fc "\"$retired_luck_hit_modifier\"")" -eq 1
done
printf '%s' "$luck_hit_modifier_cleanup_source" | grep -Fq 'hasSkillModModifier(player, retiredModifier)'
printf '%s' "$luck_hit_modifier_cleanup_source" | grep -Fq 'removeAttribOrSkillModModifier(player, retiredModifier)'
luck_hit_cleanup_source="$(sed -n '/public static void retirePostNgePlayerLuckHitOverrideState/,/public static boolean isRetiredPostNgePlayerForsakeFearChannelEffect/p' "$work_buff_library")"
printf '%s' "$luck_hit_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$luck_hit_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$luck_hit_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s' "$luck_hit_cleanup_source" | grep -Fq 'clearPostNgePlayerLuckHitOverrideModifiers(player)'
grep -Fq 'retirePostNgePlayerLuckHitOverrideState(player);' "$work_buff_library"
for luck_hit_handler in missByLuckAddBuffHandler hitByLuckAddBuffHandler; do
    luck_hit_handler_source="$(sed -n "/public int $luck_hit_handler(/,/^    }/p" "$work_buff_handler")"
    luck_hit_handler_guard_line="$(printf '%s\n' "$luck_hit_handler_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
    luck_hit_handler_cleanup_line="$(printf '%s\n' "$luck_hit_handler_source" | grep -Fn 'buff.retirePostNgePlayerLuckHitOverrideState(self);' | head -1 | cut -d: -f1)"
    luck_hit_handler_return_line="$(printf '%s\n' "$luck_hit_handler_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)"
    luck_hit_handler_writer_line="$(printf '%s\n' "$luck_hit_handler_source" | grep -Fn 'getSkillStatisticModifier(caster' | head -1 | cut -d: -f1)"
    test "$luck_hit_handler_guard_line" -lt "$luck_hit_handler_cleanup_line"
    test "$luck_hit_handler_cleanup_line" -lt "$luck_hit_handler_return_line"
    test "$luck_hit_handler_return_line" -lt "$luck_hit_handler_writer_line"
done
for luck_hit_handler in missByLuckRemoveBuffHandler hitByLuckRemoveBuffHandler; do
    luck_hit_handler_source="$(sed -n "/public int $luck_hit_handler(/,/^    }/p" "$work_buff_handler")"
    luck_hit_handler_guard_line="$(printf '%s\n' "$luck_hit_handler_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
    luck_hit_handler_cleanup_line="$(printf '%s\n' "$luck_hit_handler_source" | grep -Fn 'buff.clearPostNgePlayerLuckHitOverrideModifiers(self);' | head -1 | cut -d: -f1)"
    luck_hit_handler_return_line="$(printf '%s\n' "$luck_hit_handler_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)"
    luck_hit_handler_writer_line="$(printf '%s\n' "$luck_hit_handler_source" | grep -Fn 'removeAttribOrSkillModModifier(self' | head -1 | cut -d: -f1)"
    test "$luck_hit_handler_guard_line" -lt "$luck_hit_handler_cleanup_line"
    test "$luck_hit_handler_cleanup_line" -lt "$luck_hit_handler_return_line"
    test "$luck_hit_handler_return_line" -lt "$luck_hit_handler_writer_line"
done
awk -F '\t' '$1 == "expertise_channel_action_heal" && $2 == "expertiseChannelActionHeal" && $3 == "expertise_channel_action_heal" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2)
        if ($parameterColumn == "expertise_channel_action_heal") ownsEffect = 1
    if (ownsEffect) {
        rows++
        actual = $1 "|" $7 "|" $30 "|" $8 "|" $9 "|" $10 "|" $11 "|" $12 "|" $13 "|" $14 "|" $15 "|" $16 "|" $17
        if (actual != "fs_forsake_fear|10|1|group|0|expertise_channel_action_heal|6||0||0||0") exit 2
    }
}
END { if (rows != 1) exit 3 }' "$work_buff_table"
awk -F '\t' '$1 == "expertise_fs_path_forsake_fear_1" && $22 == "fs_forsake_fear" { found++ } END { if (found != 1) exit 3 }' "$work_skills_table"
forsake_fear_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerForsakeFearChannelEffect/,/public static boolean isRetiredPostNgePlayerForsakeFearChannelBuff/p' "$work_buff_library")"
printf '%s' "$forsake_fear_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_FORSAKE_FEAR_CHANNEL_EFFECT'
grep -Fq 'RETIRED_POST_NGE_PLAYER_FORSAKE_FEAR_CHANNEL_EFFECT = "expertise_channel_action_heal"' "$work_buff_library"
forsake_fear_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerForsakeFearChannelBuff/,/public static void clearPostNgePlayerForsakeFearChannelState/p' "$work_buff_library")"
printf '%s' "$forsake_fear_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$forsake_fear_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$forsake_fear_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerForsakeFearChannelEffect(getEffectParam(data, effect))'
forsake_fear_state_cleanup_source="$(sed -n '/public static void clearPostNgePlayerForsakeFearChannelState/,/public static void retirePostNgePlayerForsakeFearChannelState/p' "$work_buff_library")"
printf '%s' "$forsake_fear_state_cleanup_source" | grep -Fq '!isPlayer(player)'
for forsake_fear_state_key in ForsakeFearSUIPID lastForsakeFearPulse totalForsakeFearPulses channelForsakeFearCancelled channelForsakeFearSuccessful; do
    test "$(printf '%s' "$forsake_fear_state_cleanup_source" | grep -Fc "utils.removeScriptVar(player, \"buff_handler.$forsake_fear_state_key\")")" -eq 1
done
printf '%s' "$forsake_fear_state_cleanup_source" | grep -Fq 'getIntObjVar(player, sui.COUNTDOWNTIMER_SUI_VAR) == forsakeFearSuiPid'
printf '%s' "$forsake_fear_state_cleanup_source" | grep -Fq 'if (ownsCountdown)'
printf '%s' "$forsake_fear_state_cleanup_source" | grep -Fq 'forceCloseSUIPage(forsakeFearSuiPid)'
printf '%s' "$forsake_fear_state_cleanup_source" | grep -Fq 'removeObjVar(player, sui.COUNTDOWNTIMER_SUI_VAR)'
printf '%s' "$forsake_fear_state_cleanup_source" | grep -Fq 'utils.removeScriptVarTree(player, sui.COUNTDOWNTIMER_VAR)'
printf '%s' "$forsake_fear_state_cleanup_source" | grep -Fq 'detachScript(player, sui.COUNTDOWNTIMER_PLAYER_SCRIPT)'
forsake_fear_lifecycle_cleanup_source="$(sed -n '/public static void retirePostNgePlayerForsakeFearChannelState/,/public static boolean isRetiredPostNgePlayerChannelHealEffect/p' "$work_buff_library")"
printf '%s' "$forsake_fear_lifecycle_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$forsake_fear_lifecycle_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$forsake_fear_lifecycle_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s' "$forsake_fear_lifecycle_cleanup_source" | grep -Fq 'clearPostNgePlayerForsakeFearChannelState(player)'
grep -Fq 'retirePostNgePlayerForsakeFearChannelState(player);' "$work_buff_library"
forsake_fear_add_source="$(sed -n '/public int expertiseChannelActionHealAddBuffHandler/,/public int expertiseChannelActionHealRemoveBuffHandler/p' "$work_buff_handler")"
forsake_fear_remove_source="$(sed -n '/public int expertiseChannelActionHealRemoveBuffHandler/,/public int onIncapHealAddBuffHandler/p' "$work_buff_handler")"
forsake_fear_channel_source="$(sed -n '/public int channelForsakeFear(/,/public int checkChannelForsakeFear/p' "$work_buff_handler")"
forsake_fear_check_source="$(sed -n '/public int checkChannelForsakeFear/,/public int channelForsakeFearCountdownHandler/p' "$work_buff_handler")"
forsake_fear_countdown_source="$(sed -n '/public int channelForsakeFearCountdownHandler/,/public int actionDrainAddBuffHandler/p' "$work_buff_handler")"
forsake_fear_add_guard_line="$(printf '%s\n' "$forsake_fear_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
forsake_fear_add_cleanup_line="$(printf '%s\n' "$forsake_fear_add_source" | grep -Fn 'buff.retirePostNgePlayerForsakeFearChannelState(self);' | head -1 | cut -d: -f1)"
forsake_fear_add_writer_line="$(printf '%s\n' "$forsake_fear_add_source" | grep -Fn 'utils.setScriptVar(self, "buff_handler.lastForsakeFearPulse"' | head -1 | cut -d: -f1)"
test "$forsake_fear_add_guard_line" -lt "$forsake_fear_add_cleanup_line"
test "$forsake_fear_add_cleanup_line" -lt "$forsake_fear_add_writer_line"
forsake_fear_remove_guard_line="$(printf '%s\n' "$forsake_fear_remove_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
forsake_fear_remove_cleanup_line="$(printf '%s\n' "$forsake_fear_remove_source" | grep -Fn 'buff.clearPostNgePlayerForsakeFearChannelState(self);' | head -1 | cut -d: -f1)"
forsake_fear_remove_writer_line="$(printf '%s\n' "$forsake_fear_remove_source" | grep -Fn 'utils.getIntScriptVar(self, "buff_handler.channelForsakeFearCancelled"' | head -1 | cut -d: -f1)"
test "$forsake_fear_remove_guard_line" -lt "$forsake_fear_remove_cleanup_line"
test "$forsake_fear_remove_cleanup_line" -lt "$forsake_fear_remove_writer_line"
for forsake_fear_callback_source in "$forsake_fear_channel_source" "$forsake_fear_check_source" "$forsake_fear_countdown_source"; do
    forsake_fear_callback_guard_line="$(printf '%s\n' "$forsake_fear_callback_source" | grep -Fn 'isPlayer(player)' | head -1 | cut -d: -f1)"
    forsake_fear_callback_cleanup_line="$(printf '%s\n' "$forsake_fear_callback_source" | grep -Fn 'buff.clearPostNgePlayerForsakeFearChannelState(player);' | head -1 | cut -d: -f1)"
    forsake_fear_callback_return_line="$(printf '%s\n' "$forsake_fear_callback_source" | grep -Fn 'return SCRIPT_CONTINUE;' | awk -F: -v cleanup="$forsake_fear_callback_cleanup_line" '$1 > cleanup { print $1; exit }')"
    test "$forsake_fear_callback_guard_line" -lt "$forsake_fear_callback_cleanup_line"
    test "$forsake_fear_callback_cleanup_line" -lt "$forsake_fear_callback_return_line"
done
forsake_fear_channel_heal_line="$(printf '%s\n' "$forsake_fear_channel_source" | grep -Fn 'healAttribPercent(player, ACTION' | head -1 | cut -d: -f1)"
forsake_fear_check_requeue_line="$(printf '%s\n' "$forsake_fear_check_source" | grep -Fn 'channelForsakeFear(player, buffName, false);' | head -1 | cut -d: -f1)"
forsake_fear_countdown_writer_line="$(printf '%s\n' "$forsake_fear_countdown_source" | grep -Fn 'sui.getIntButtonPressed(params)' | head -1 | cut -d: -f1)"
test "$forsake_fear_channel_source" != ""
test "$forsake_fear_channel_heal_line" -gt "$(printf '%s\n' "$forsake_fear_channel_source" | grep -Fn 'buff.clearPostNgePlayerForsakeFearChannelState(player);' | head -1 | cut -d: -f1)"
test "$forsake_fear_check_requeue_line" -gt "$(printf '%s\n' "$forsake_fear_check_source" | grep -Fn 'buff.clearPostNgePlayerForsakeFearChannelState(player);' | head -1 | cut -d: -f1)"
test "$forsake_fear_countdown_writer_line" -gt "$(printf '%s\n' "$forsake_fear_countdown_source" | grep -Fn 'buff.clearPostNgePlayerForsakeFearChannelState(player);' | head -1 | cut -d: -f1)"
dot_immunity_predicate_source="$(sed -n '/public boolean isRetiredNgeDotImmunityModifier/,/public boolean isRetiredNgeBuffSkillModifier/p' "$work_buff_handler")"
printf '%s' "$dot_immunity_predicate_source" | grep -Fq 'modifierName.equals("damage_immune")'
printf '%s' "$dot_immunity_predicate_source" | grep -Fq 'modifierName.startsWith("dot_resist_")'
skill_add_source="$(sed -n '/public int skillAddBuffHandler/,/public int skillRemoveBuffHandler/p' "$work_buff_handler")"
skill_percent_source="$(sed -n '/public int skillPercentAddBuffHandler/,/public int skillPercentRemoveBuffHandler/p' "$work_buff_handler")"
force_power_source="$(sed -n '/public int forcePowerAddBuffHandler/,/public int forcePowerRemoveBuffHandler/p' "$work_buff_handler")"
for expertise_writer_source in "$skill_add_source" "$skill_percent_source" "$force_power_source"; do
    printf '%s' "$expertise_writer_source" | grep -Fq 'isRetiredNgeBuffSkillModifier(subtype)'
    printf '%s' "$expertise_writer_source" | grep -Fq 'retireNgeExpertiseModifier(self, effectName)'
    printf '%s' "$expertise_writer_source" | grep -Fq 'addSkillModModifier'
done
dot_universal_immunity_source="$(sed -n '/public int immunityAddBuffHandler/,/public int immunityRemoveBuffHandler/p' "$work_buff_handler")"
dot_universal_player_guard_line="$(printf '%s\n' "$dot_universal_immunity_source" | grep -Fn 'isPlayer(self) && subtype.equals("dot_immunity") && wholeValue == IMMUNITY_TO_ALL_DOTS' | head -1 | cut -d: -f1)"
dot_universal_purge_line="$(printf '%s\n' "$dot_universal_immunity_source" | grep -Fn 'buff.performBuffDotImmunity(self, "all")' | head -1 | cut -d: -f1)"
test -n "$dot_universal_player_guard_line"
test -n "$dot_universal_purge_line"
test "$dot_universal_player_guard_line" -lt "$dot_universal_purge_line"
damage_immune_source="$(sed -n '/public int damageImmuneAddBuffHandler/,/public int damageImmuneRemoveBuffHandler/p' "$work_buff_handler")"
damage_immune_player_guard_line="$(printf '%s\n' "$damage_immune_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
damage_immune_purge_line="$(printf '%s\n' "$damage_immune_source" | grep -Fn 'buff.performBuffDotImmunity(self, "all")' | head -1 | cut -d: -f1)"
test -n "$damage_immune_player_guard_line"
test -n "$damage_immune_purge_line"
test "$damage_immune_player_guard_line" -lt "$damage_immune_purge_line"
printf '%s\n' "$damage_immune_source" | grep -Fq 'removeAttribOrSkillModModifier(self, "damageImmuneDotResistAll")'
printf '%s\n' "$damage_immune_source" | grep -Fq 'removeAttribOrSkillModModifier(self, "damageImmuneDamageImmune")'
awk -F '\t' '
    $2 == "dotReduction" || $2 == "dotDivisor" {
        ++rows
        ++names[$1]
        if ($1 != $3) { exit 2 }
        if ($2 == "dotReduction") { reduction[$1]=1 }
        if ($2 == "dotDivisor") { divisor[$1]=1 }
    }
    END {
        for (name in names) {
            ++unique
            if (names[name] != 2) { exit 3 }
        }
        for (name in reduction) { ++reduction_count }
        for (name in divisor) { ++divisor_count }
        if (rows != 48 || unique != 24 || reduction_count != 12 || divisor_count != 12) { exit 4 }
    }
' "$work_buff_effect_mapping"
awk -F '\t' '
    function mutation(value) {
        return value ~ /^dot_(reduction|divisor)_/
    }
    mutation($8) || mutation($10) || mutation($12) || mutation($14) || mutation($16) {
        ++rows
        found[$1]=1
    }
    END {
        expected["fs_hermetic_touch"]=1
        expected["me_cure_affliction_1"]=1
        expected["me_stasis_1"]=1
        expected["me_stasis_self_1"]=1
        expected["of_purge_1"]=1
        expected["sp_covert_mastery"]=1
        expected["sp_run_its_course"]=1
        expected["wod_adaptive_biology"]=1
        if (rows != 8) { exit 2 }
        for (name in found) { if (!(name in expected)) { exit 3 } }
        for (name in expected) { if (!(name in found)) { exit 4 } }
    }
' "$work_buff_table"
dot_stack_mutation_source="$(sed -n '/private static final String RETIRED_POST_NGE_PLAYER_DOT_REDUCTION_EFFECT_PREFIX/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_DAMAGE_REDUCTION_MODIFIERS/p' "$work_buff_library")"
printf '%s\n' "$dot_stack_mutation_source" | grep -Fq '"dot_reduction_"'
printf '%s\n' "$dot_stack_mutation_source" | grep -Fq '"dot_divisor_"'
printf '%s\n' "$dot_stack_mutation_source" | grep -Fq 'isRetiredPostNgePlayerDotStackMutationBuff'
printf '%s\n' "$dot_stack_mutation_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$dot_stack_mutation_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerDotStackMutationState(player);' "$work_buff_library"
dot_stack_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
dot_stack_admission_line="$(printf '%s\n' "$dot_stack_admission_source" | grep -Fn 'isRetiredPostNgePlayerDotStackMutationBuff(target, bdata)' | head -1 | cut -d: -f1)"
dot_stack_existing_line="$(printf '%s\n' "$dot_stack_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$dot_stack_admission_line"
test -n "$dot_stack_existing_line"
test "$dot_stack_admission_line" -lt "$dot_stack_existing_line"
dot_reduction_handler_source="$(sed -n '/public int dotReductionAddBuffHandler/,/public int dotReductionRemoveBuffHandler/p' "$work_buff_handler")"
dot_divisor_handler_source="$(sed -n '/public int dotDivisorAddBuffHandler/,/public int dotDivisorRemoveBuffHandler/p' "$work_buff_handler")"
dot_reduction_guard_line="$(printf '%s\n' "$dot_reduction_handler_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
dot_reduction_mutation_line="$(printf '%s\n' "$dot_reduction_handler_source" | grep -Fn 'buff.reduceBuffDotStackCount' | head -1 | cut -d: -f1)"
dot_divisor_guard_line="$(printf '%s\n' "$dot_divisor_handler_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
dot_divisor_mutation_line="$(printf '%s\n' "$dot_divisor_handler_source" | grep -Fn 'buff.divideBuffDotStackCount' | head -1 | cut -d: -f1)"
test -n "$dot_reduction_guard_line"
test -n "$dot_reduction_mutation_line"
test -n "$dot_divisor_guard_line"
test -n "$dot_divisor_mutation_line"
test "$dot_reduction_guard_line" -lt "$dot_reduction_mutation_line"
test "$dot_divisor_guard_line" -lt "$dot_divisor_mutation_line"
test "$(printf '%s\n' "$dot_reduction_handler_source" | grep -Fc 'buff.reduceBuffDotStackCount')" -eq 9
test "$(printf '%s\n' "$dot_divisor_handler_source" | grep -Fc 'buff.divideBuffDotStackCount')" -eq 9
# The sole inherited group effect is entirely post-Publish-14 player combat
# authority. Keep all authored rows plus NPC propagation and removal cleanup,
# while rejecting the complete exact player inventory before aura mutation.
test "$(awk -F '\t' '$1 == "group" && $2 == "group" { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 1
retired_player_group_buffs='sl_group_run sl_group_acc sl_group_def sl_group_crit_hit sl_group_armor sl_group_regen sl_group_armor_break sl_group_red_cooldown sl_group_retreat sl_group_charge co_base_of_operations veteranPlayerBuff fs_forsake_fear of_buff_def_1 of_buff_def_2 of_buff_def_3 of_buff_def_4 of_buff_def_5 of_buff_def_6 of_buff_def_7 of_buff_def_8 of_buff_def_9 of_focus_fire_1 of_focus_fire_2 of_focus_fire_3 of_focus_fire_4 of_focus_fire_5 of_focus_fire_6 of_inspiration_1 of_inspiration_2 of_inspiration_3 of_inspiration_4 of_inspiration_5 of_inspiration_6 of_scatter_1 of_charge_1 of_drillmaster_1 human_ability_1'
test "$(printf '%s\n' $retired_player_group_buffs | wc -l)" -eq 38
awk -F '\t' -v retired="$retired_player_group_buffs" '
    BEGIN {
        split(retired, retired_names, " ")
        for (idx in retired_names) { retired_set[retired_names[idx]]=1 }
    }
    NR == 1 {
        for (column = 1; column <= NF; column++) {
            header = $column
            sub(/\r$/, "", header)
            field_index[header] = column
        }
        next
    }
    NR > 2 {
        owns_group = 0
        for (effect = 1; effect <= 5; effect++) {
            if ($(field_index["EFFECT" effect "_PARAM"]) == "group") {
                owns_group = 1
            }
        }
        if (!owns_group) { next }
        name = $(field_index["NAME"])
        ++rows
        if (name in retired_set) { ++retired_rows; ++retired_found[name] }
        else { ++unclassified_rows }
    }
    END {
        if (rows != 38 || retired_rows != 38 || unclassified_rows != 0) exit 2
        for (name in retired_set) { if (retired_found[name] != 1) exit 3 }
    }
' "$work_buff_table"
group_buff_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_GROUP_BUFFS/,/public static boolean isRetiredPostNgePlayerGroupBuffName/p' "$work_buff_library")"
test "$(printf '%s\n' "$group_buff_inventory_source" | grep -Ec '^[[:space:]]*"[^"]+"[,;]?$')" -eq 38
for retired_player_group_buff in $retired_player_group_buffs; do
    printf '%s\n' "$group_buff_inventory_source" | grep -Fq "\"$retired_player_group_buff\""
done
group_buff_cleanup_source="$(sed -n '/public static void retirePostNgePlayerGroupBuffState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_FLAT_ATTRIBUTE_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$group_buff_cleanup_source" | grep -Fq 'isPlayer(player)'
printf '%s\n' "$group_buff_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerGroupBuffState(player);' "$work_buff_library"
group_buff_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
group_buff_admission_line="$(printf '%s\n' "$group_buff_admission_source" | grep -Fn 'isRetiredPostNgePlayerGroupBuff(target, bdata)' | head -1 | cut -d: -f1)"
group_buff_existing_line="$(printf '%s\n' "$group_buff_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$group_buff_admission_line"
test -n "$group_buff_existing_line"
test "$group_buff_admission_line" -lt "$group_buff_existing_line"
group_buff_add_handler_source="$(sed -n '/public int groupAddBuffHandler/,/public int groupRemoveBuffHandler/p' "$work_buff_handler")"
group_buff_remove_handler_source="$(sed -n '/public int groupRemoveBuffHandler/,/public int OnTriggerVolumeEntered/p' "$work_buff_handler")"
group_buff_add_player_line="$(printf '%s\n' "$group_buff_add_handler_source" | grep -Fn 'if (isPlayer(self)' | head -1 | cut -d: -f1)"
group_buff_add_predicate_line="$(printf '%s\n' "$group_buff_add_handler_source" | grep -Fn 'buff.isRetiredPostNgePlayerGroupBuffName(buffName)' | head -1 | cut -d: -f1)"
group_buff_add_mutation_line="$(printf '%s\n' "$group_buff_add_handler_source" | grep -Fn 'effectName = effectName.substring' | head -1 | cut -d: -f1)"
test -n "$group_buff_add_player_line"
test -n "$group_buff_add_predicate_line"
test -n "$group_buff_add_mutation_line"
test "$group_buff_add_player_line" -le "$group_buff_add_predicate_line"
test "$group_buff_add_predicate_line" -lt "$group_buff_add_mutation_line"
printf '%s\n' "$group_buff_remove_handler_source" | grep -Fq 'utils.removeScriptVar(self, var)'
printf '%s\n' "$group_buff_remove_handler_source" | grep -Fq 'messageTo(groupMember, "setGroupBuffs"'
printf '%s\n' "$group_buff_remove_handler_source" | grep -Fq 'removeTriggerVolume("group_buff_breach")'
! printf '%s\n' "$group_buff_remove_handler_source" | grep -Fq 'isRetiredPostNgePlayerGroupBuffName'
# The exact inherited flat-HAM player reward inventory is post-NGE combat
# authority. Keep its content rows and generic non-player/cleanup machinery,
# while rejecting those names before player mutation.
flat_attribute_effect_specs='action:action constitution:constitution health:health mind:mind stamina:stamina strength:strength willpower:willpower'
test "$(awk -F '\t' '$2 == "attrib" { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 7
for flat_attribute_effect_spec in $flat_attribute_effect_specs; do
    flat_attribute_effect_name="${flat_attribute_effect_spec%%:*}"
    flat_attribute_effect_subtype="${flat_attribute_effect_spec#*:}"
    awk -F '\t' -v name="$flat_attribute_effect_name" -v subtype="$flat_attribute_effect_subtype" '
        $1 == name && $2 == "attrib" && $3 == subtype { found++ }
        END { if (found != 1) exit 3 }
    ' "$work_buff_effect_mapping"
done
retired_player_flat_attribute_buffs='crystal_buff holocron_1 holocron_4 holocron_5 holocron_6 trivialComboRngSpeed towConstStamina_1 towConstStamina_2 towConstWillpower_1 towConstWillpower_2 towStaminaWillpower_1 towStaminaWillpower_2 forceCrystalForce'
preserved_flat_attribute_buffs='testHealthBuff1 testHealthBuff2 testConstBuff1 testConstBuff2 testAttribBuff1 testAttribBuff2 testDebuff1 testDebuff2 testMedBoost1 testMedBoost2 testColdSnare1 testColdSnare2 testLongBuff bindingStrike bindingStrike_1 innate_regeneration innate_vitalize powerBoost minder_add_debuff jedi_statue_self_dps_debuff'
test "$(printf '%s\n' $retired_player_flat_attribute_buffs | wc -l)" -eq 13
test "$(printf '%s\n' $preserved_flat_attribute_buffs | wc -l)" -eq 20
awk -F '\t' -v retired="$retired_player_flat_attribute_buffs" -v preserved="$preserved_flat_attribute_buffs" '
    BEGIN {
        split(retired, retired_names, " ")
        for (idx in retired_names) { retired_set[retired_names[idx]]=1 }
        split(preserved, preserved_names, " ")
        for (idx in preserved_names) { preserved_set[preserved_names[idx]]=1 }
    }
    NR == 1 {
        for (column = 1; column <= NF; column++) {
            header = $column
            sub(/\r$/, "", header)
            field_index[header] = column
        }
        next
    }
    NR > 2 {
        owns_flat_attribute = 0
        for (effect = 1; effect <= 5; effect++) {
            parameter = $(field_index["EFFECT" effect "_PARAM"])
            if (parameter == "action" || parameter == "constitution" ||
                parameter == "health" || parameter == "mind" ||
                parameter == "stamina" || parameter == "strength" ||
                parameter == "willpower") {
                owns_flat_attribute = 1
            }
        }
        if (!owns_flat_attribute) { next }
        name = $(field_index["NAME"])
        ++rows
        if (name in retired_set) { ++retired_rows; ++retired_found[name] }
        else if (name in preserved_set) { ++preserved_rows; ++preserved_found[name] }
        else { ++unclassified_rows }
    }
    END {
        if (rows != 33 || retired_rows != 13 || preserved_rows != 20 || unclassified_rows != 0) exit 2
        for (name in retired_set) { if (retired_found[name] != 1) exit 3 }
        for (name in preserved_set) { if (preserved_found[name] != 1) exit 4 }
    }
' "$work_buff_table"
flat_attribute_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_FLAT_ATTRIBUTE_BUFFS/,/public static boolean isRetiredPostNgePlayerFlatAttributeBuffName/p' "$work_buff_library")"
test "$(printf '%s\n' "$flat_attribute_inventory_source" | grep -Ec '^[[:space:]]*"[^"]+"[,;]?$')" -eq 13
for retired_player_flat_attribute_buff in $retired_player_flat_attribute_buffs; do
    printf '%s\n' "$flat_attribute_inventory_source" | grep -Fq "\"$retired_player_flat_attribute_buff\""
done
flat_attribute_cleanup_source="$(sed -n '/public static void retirePostNgePlayerFlatAttributeState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_ATTRIBUTE_PERCENT_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$flat_attribute_cleanup_source" | grep -Fq 'isPlayer(player)'
printf '%s\n' "$flat_attribute_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerFlatAttributeState(player);' "$work_buff_library"
flat_attribute_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
flat_attribute_admission_line="$(printf '%s\n' "$flat_attribute_admission_source" | grep -Fn 'isRetiredPostNgePlayerFlatAttributeBuff(target, bdata)' | head -1 | cut -d: -f1)"
flat_attribute_existing_line="$(printf '%s\n' "$flat_attribute_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$flat_attribute_admission_line"
test -n "$flat_attribute_existing_line"
test "$flat_attribute_admission_line" -lt "$flat_attribute_existing_line"
flat_attribute_add_handler_source="$(sed -n '/public int attribAddBuffHandler/,/public int attribRemoveBuffHandler/p' "$work_buff_handler")"
flat_attribute_remove_handler_source="$(sed -n '/public int attribRemoveBuffHandler/,/public int attribPercentAddBuffHandler/p' "$work_buff_handler")"
flat_attribute_add_player_line="$(printf '%s\n' "$flat_attribute_add_handler_source" | grep -Fn 'if (isPlayer(self)' | head -1 | cut -d: -f1)"
flat_attribute_add_predicate_line="$(printf '%s\n' "$flat_attribute_add_handler_source" | grep -Fn 'buff.isRetiredPostNgePlayerFlatAttributeBuffName(buffName)' | head -1 | cut -d: -f1)"
flat_attribute_add_attribute_line="$(printf '%s\n' "$flat_attribute_add_handler_source" | grep -Fn 'int attribute = ATTRIB_ERROR' | head -1 | cut -d: -f1)"
flat_attribute_add_writer_line="$(printf '%s\n' "$flat_attribute_add_handler_source" | grep -Fn 'addAttribModifier(self, am)' | head -1 | cut -d: -f1)"
test -n "$flat_attribute_add_player_line"
test -n "$flat_attribute_add_predicate_line"
test -n "$flat_attribute_add_attribute_line"
test -n "$flat_attribute_add_writer_line"
test "$flat_attribute_add_player_line" -le "$flat_attribute_add_predicate_line"
test "$flat_attribute_add_predicate_line" -lt "$flat_attribute_add_attribute_line"
test "$flat_attribute_add_predicate_line" -lt "$flat_attribute_add_writer_line"
printf '%s\n' "$flat_attribute_remove_handler_source" | grep -Fq 'removeAttribOrSkillModModifier(self, effectName)'
! printf '%s\n' "$flat_attribute_remove_handler_source" | grep -Fq 'isRetiredPostNgePlayerFlatAttributeBuffName'
# The retained generic percentage-HAM machinery remains available for
# authenticated PRE-CU and later-content exceptions, but its exact inherited
# post-NGE player inventory is rejected before any attribute mutation.
attribute_percent_effect_specs='actionPercent:action constitutionPercent:constitution healthPercent:health mindPercent:mind staminaPercent:stamina willpowerPercent:willpower'
test "$(awk -F '\t' '$2 == "attribPercent" { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 6
for attribute_percent_effect_spec in $attribute_percent_effect_specs; do
    attribute_percent_effect_name="${attribute_percent_effect_spec%%:*}"
    attribute_percent_effect_subtype="${attribute_percent_effect_spec#*:}"
    awk -F '\t' -v name="$attribute_percent_effect_name" -v subtype="$attribute_percent_effect_subtype" '
        $1 == name && $2 == "attribPercent" && $3 == subtype { found++ }
        END { if (found != 1) exit 3 }
    ' "$work_buff_effect_mapping"
done
retired_player_attribute_percent_buffs='nutrientInjection nutrientInjection_1 nutrientInjection_2 endorphineInjection endorphineInjection_1 serotoninInjection serotoninInjection_1 hemorrhage hemorrhage_1 traumatize traumatize_1 forceSap forceSap_1 holocron_8 sl_group_regen sl_group_retreat combatRegenDebuff treasure_bonus_combat_critical_hit treasure_bonus_heal_health_action'
preserved_attribute_percent_buffs='frogBuff emboldenPet bio_etheric_shock torpor vacuity biological_suppression insidiousMalady insidiousMalady_1 insidiousMalady_2 insidiousMalady_3 insidiousMalady_4 euphoria cloning_sickness death_troopers_infection_2 death_troopers_infection_3'
test "$(printf '%s\n' $retired_player_attribute_percent_buffs | wc -l)" -eq 19
test "$(printf '%s\n' $preserved_attribute_percent_buffs | wc -l)" -eq 15
awk -F '\t' -v retired="$retired_player_attribute_percent_buffs" -v preserved="$preserved_attribute_percent_buffs" '
    BEGIN {
        split(retired, retired_names, " ")
        for (idx in retired_names) { retired_set[retired_names[idx]]=1 }
        split(preserved, preserved_names, " ")
        for (idx in preserved_names) { preserved_set[preserved_names[idx]]=1 }
    }
    NR == 1 {
        for (column = 1; column <= NF; column++) {
            header = $column
            sub(/\r$/, "", header)
            field_index[header] = column
        }
        next
    }
    NR > 2 {
        owns_attribute_percent = 0
        for (effect = 1; effect <= 5; effect++) {
            parameter = $(field_index["EFFECT" effect "_PARAM"])
            if (parameter == "actionPercent" || parameter == "constitutionPercent" ||
                parameter == "healthPercent" || parameter == "mindPercent" ||
                parameter == "staminaPercent" || parameter == "willpowerPercent") {
                owns_attribute_percent = 1
            }
        }
        if (!owns_attribute_percent) { next }
        name = $(field_index["NAME"])
        ++rows
        if (name in retired_set) { ++retired_rows; ++retired_found[name] }
        else if (name in preserved_set) { ++preserved_rows; ++preserved_found[name] }
        else { ++unclassified_rows }
    }
    END {
        if (rows != 34 || retired_rows != 19 || preserved_rows != 15 || unclassified_rows != 0) exit 2
        for (name in retired_set) { if (retired_found[name] != 1) exit 3 }
        for (name in preserved_set) { if (preserved_found[name] != 1) exit 4 }
    }
' "$work_buff_table"
attribute_percent_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_ATTRIBUTE_PERCENT_BUFFS/,/public static boolean isRetiredPostNgePlayerAttributePercentBuffName/p' "$work_buff_library")"
test "$(printf '%s\n' "$attribute_percent_inventory_source" | grep -Ec '^[[:space:]]*"[^"]+"[,;]?$')" -eq 19
for retired_player_attribute_percent_buff in $retired_player_attribute_percent_buffs; do
    printf '%s\n' "$attribute_percent_inventory_source" | grep -Fq "\"$retired_player_attribute_percent_buff\""
done
attribute_percent_cleanup_source="$(sed -n '/public static void retirePostNgePlayerAttributePercentState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_DAMAGE_REDUCTION_MODIFIERS/p' "$work_buff_library")"
printf '%s\n' "$attribute_percent_cleanup_source" | grep -Fq 'isPlayer(player)'
printf '%s\n' "$attribute_percent_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerAttributePercentState(player);' "$work_buff_library"
attribute_percent_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
attribute_percent_admission_line="$(printf '%s\n' "$attribute_percent_admission_source" | grep -Fn 'isRetiredPostNgePlayerAttributePercentBuff(target, bdata)' | head -1 | cut -d: -f1)"
attribute_percent_existing_line="$(printf '%s\n' "$attribute_percent_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$attribute_percent_admission_line"
test -n "$attribute_percent_existing_line"
test "$attribute_percent_admission_line" -lt "$attribute_percent_existing_line"
attribute_percent_add_handler_source="$(sed -n '/public int attribPercentAddBuffHandler/,/public int attribPercentRemoveBuffHandler/p' "$work_buff_handler")"
attribute_percent_remove_handler_source="$(sed -n '/public int attribPercentRemoveBuffHandler/,/public int skillAddBuffHandler/p' "$work_buff_handler")"
attribute_percent_add_player_line="$(printf '%s\n' "$attribute_percent_add_handler_source" | grep -Fn 'if (isPlayer(self)' | head -1 | cut -d: -f1)"
attribute_percent_add_predicate_line="$(printf '%s\n' "$attribute_percent_add_handler_source" | grep -Fn 'buff.isRetiredPostNgePlayerAttributePercentBuffName(buffName)' | head -1 | cut -d: -f1)"
attribute_percent_add_attribute_line="$(printf '%s\n' "$attribute_percent_add_handler_source" | grep -Fn 'int attribute = ATTRIB_ERROR' | head -1 | cut -d: -f1)"
attribute_percent_add_writer_line="$(printf '%s\n' "$attribute_percent_add_handler_source" | grep -Fn 'addAttribModifier(self, am)' | head -1 | cut -d: -f1)"
test -n "$attribute_percent_add_player_line"
test -n "$attribute_percent_add_predicate_line"
test -n "$attribute_percent_add_attribute_line"
test -n "$attribute_percent_add_writer_line"
test "$attribute_percent_add_player_line" -le "$attribute_percent_add_predicate_line"
test "$attribute_percent_add_predicate_line" -lt "$attribute_percent_add_attribute_line"
test "$attribute_percent_add_predicate_line" -lt "$attribute_percent_add_writer_line"
printf '%s\n' "$attribute_percent_remove_handler_source" | grep -Fq 'removeAttribOrSkillModModifier(self, effectName)'
! printf '%s\n' "$attribute_percent_remove_handler_source" | grep -Fq 'isRetiredPostNgePlayerAttributePercentBuffName'
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
force_sensitive_stance_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_FORCE_SENSITIVE_STANCE_BUFFS/,/public static boolean isRetiredPostNgeForceSensitiveStanceBuff/p' "$work_buff_library")"
force_sensitive_stance_cleanup_source="$(sed -n '/public static void retirePostNgeForceSensitiveStanceState/,/public static boolean isRetiredPostNgeBountyHunterShieldBuff/p' "$work_buff_library")"
retired_force_sensitive_stance_buffs="fs_buff_def_1_1 fs_buff_ca_1 jedi_reflect_flurry fs_saber_shackle_1 fs_saber_shackle_2 fs_saber_shackle_3 fs_saber_shackle_4 fs_soothing_aura_1 fs_soothing_aura_2 fs_soothing_aura_3 fs_soothing_aura_4 fs_anticipate_aggression_1 fs_anticipate_aggression_2 fs_reactive_response_1 fs_reactive_response_2 fs_perceptive_sentinel_1 fs_perceptive_sentinel_2 fs_perceptive_sentinel_3 fs_perceptive_sentinel_4 fs_saber_reflect fs_ruthless_precision_1 fs_ruthless_precision_2 fs_ruthless_precision_3 fs_ruthless_precision_4 fs_tempt_hatred_1 fs_tempt_hatred_2 fs_wracking_energy_1 fs_wracking_energy_2 fs_wracking_energy_3 fs_wracking_energy_4 fs_imp_force_drain_1 fs_imp_force_drain_2 fs_imp_force_drain_3 fs_imp_force_drain_4 invis_fs_buff_invis_1"
test "$(printf '%s\n' $retired_force_sensitive_stance_buffs | wc -l)" -eq 35
retained_force_sensitive_stance_rows=0
for retired_force_sensitive_stance_buff in $retired_force_sensitive_stance_buffs; do
    printf '%s' "$force_sensitive_stance_inventory_source" | grep -Fq "\"$retired_force_sensitive_stance_buff\""
    if awk -F '\t' -v name="$retired_force_sensitive_stance_buff" '$1 == name { found=1 } END { exit(found ? 0 : 1) }' "$work_buff_table"; then
        retained_force_sensitive_stance_rows=$((retained_force_sensitive_stance_rows + 1))
    fi
done
test "$retained_force_sensitive_stance_rows" -eq 34
! awk -F '\t' '$1 == "fs_imp_force_drain_4" { found=1 } END { exit(found ? 0 : 1) }' "$work_buff_table"
awk -F '\t' '$1 == "invis_fs_buff_invis_1" { found++ } END { if (found != 1) exit 3 }' "$work_buff_table"
awk -F '\t' '$1 == "invis_forceCloak" { found++ } END { if (found != 1) exit 3 }' "$work_buff_table"
! printf '%s' "$force_sensitive_stance_inventory_source" | grep -Fq '"invis_forceCloak"'
awk -F '\t' '$1 == "centerofbeing" { found++; if ($8 != "private_center_of_being") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
printf '%s' "$force_sensitive_stance_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$force_sensitive_stance_cleanup_source" | grep -Fq 'removeBuff(player, retiredBuff)'
test "$(printf '%s' "$force_sensitive_stance_cleanup_source" | grep -Ec '"(stanceParry|stanceEvasion|stanceConstitution|focusStamina|focusStrength|expertise_fs_force_clarity_1_proc|expertise_fs_flurry_charge_proc)"')" -eq 7
printf '%s' "$force_sensitive_stance_cleanup_source" | grep -Fq 'utils.removeScriptVarTree(player, "expertise_stance_critical")'
printf '%s' "$force_sensitive_stance_cleanup_source" | grep -Fq 'utils.removeScriptVarTree(player, "stance.expertise_stance")'
printf '%s' "$force_sensitive_stance_cleanup_source" | grep -Fq 'utils.removeScriptVarTree(player, "stance.expertise_focus")'
grep -Fq 'retirePostNgeForceSensitiveStanceState(player);' "$work_buff_library"
awk -F '\t' '$1 == "forceThrow" && $2 == "forceThrow" && $3 == "forceThrow" { found++ } END { if (found != 2) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '$1 ~ /^(forceThrow|fs_force_throw_[1-4]|fs_force_throw_root)$/ { found++ } END { if (found != 6) exit 3 }' "$work_buff_table"
awk -F '\t' '{ for (i = 1; i <= NF; i++) if ($i == "forceThrow1" || $i == "forceThrow2") { found++; break } } END { if (found != 5) exit 3 }' "$work_skills_table"
awk -F '\t' '$1 == "class_forcesensitive_phase1_02" || $1 ~ /^expertise_fs_general_improved_(force_throw_[12]|crippling_accuracy_[123])$/ { found++ } END { if (found != 6) exit 3 }' "$work_skills_table"
awk -F '\t' '{ for (i = 1; i <= NF; i++) { value = $i; gsub(/^"|"$/, "", value); if (value == "fs_buff_ca_1,forceThrow") { found++; break } } } END { if (found != 1) exit 3 }' "$work_skills_table"
force_throw_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerForceThrowEffect/,/public static boolean isRetiredPostNgePlayerForceThrowBuffName/p' "$work_buff_library")"
force_throw_name_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerForceThrowBuffName/,/public static boolean isRetiredPostNgePlayerForceThrowBuff(obj_id/p' "$work_buff_library")"
force_throw_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerForceThrowBuff(obj_id/,/public static void retirePostNgePlayerForceThrowState/p' "$work_buff_library")"
force_throw_cleanup_source="$(sed -n '/public static void retirePostNgePlayerForceThrowState/,/private static final String RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_BUFF/p' "$work_buff_library")"
printf '%s' "$force_throw_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_FORCE_THROW_EFFECT'
printf '%s' "$force_throw_name_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_FORCE_THROW_CONTROL_BUFF_PREFIX'
printf '%s' "$force_throw_name_predicate_source" | grep -Fq 'buffName.startsWith'
printf '%s' "$force_throw_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$force_throw_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerForceThrowBuffName(data.buffName)'
printf '%s' "$force_throw_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$force_throw_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$force_throw_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$force_throw_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$force_throw_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerForceThrowState(player);' "$work_buff_library"
damage_reduction_modifiers="expertise_damage_decrease_chance expertise_sm_rank_damage_bonus expertise_damage_reduce_anticipate_aggression damage_decrease_percentage area_damage_decrease_percentage area_damage_resist_full_percentage expertise_damage_decrease_percentage"
test "$(printf '%s\n' $damage_reduction_modifiers | wc -l)" -eq 7
awk -F '\t' '
$1 ~ /^(expertise_damage_decrease_chance|expertise_sm_rank_damage_bonus|expertise_damage_reduce_anticipate_aggression|damage_decrease_percentage|area_damage_decrease_percentage|area_damage_resist_full_percentage|expertise_damage_decrease_percentage)$/ {
    found++
    if (($1 == "damage_decrease_percentage" && $2 == "skill" && $3 == "damage_decrease_percentage") ||
        ($1 == "expertise_damage_decrease_chance" && $2 == "skill" && $3 == "expertise_damage_decrease_chance") ||
        ($1 == "expertise_damage_decrease_percentage" && $2 == "expertiseDamageDecrease" && $3 == "expertise_damage_decrease_percentage") ||
        ($1 == "expertise_damage_reduce_anticipate_aggression" && $2 == "skill" && $3 == "expertise_damage_reduce_anticipate_aggression") ||
        ($1 == "expertise_sm_rank_damage_bonus" && $2 == "skill" && $3 == "expertise_sm_rank_damage_bonus")) valid++
}
END { if (found != 5 || valid != 5) exit 3 }
' "$work_buff_effect_mapping"
awk -F '\t' '
{
    relevant = 0
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^(expertise_damage_decrease_chance|expertise_sm_rank_damage_bonus|expertise_damage_reduce_anticipate_aggression|damage_decrease_percentage|area_damage_decrease_percentage|area_damage_resist_full_percentage|expertise_damage_decrease_percentage)$/) relevant = 1
    }
    if (relevant) {
        if ($1 !~ /^(co_stand_fast|fs_anticipate_aggression_[12]|sm_spot_a_sucker_[1-4]_[67]|sm_underworld_damage_[1-3])$/) exit 2
        found++
    }
}
END { if (found != 14) exit 3 }
' "$work_buff_table"
awk -F '\t' '
{
    relevant = 0
    for (i = 1; i <= NF; i++) {
        value = $i
        gsub(/^"|"$/, "", value)
        count = split(value, parts, ",")
        for (part = 1; part <= count; part++) {
            if (parts[part] ~ /^(damage_decrease_percentage|area_damage_resist_full_percentage|expertise_damage_decrease_percentage)=/) relevant = 1
        }
    }
    if (relevant) {
        if ($1 !~ /^expertise_(co_(blast_resistance_[1-4]|deflective_armor_[1-4]|stand_fast_1|imp_stand_fast_[1-3])|sm_general_idiot_proof_plan_[12])$/) exit 2
        found++
    }
}
END { if (found != 14) exit 3 }
' "$work_skills_table"
damage_reduction_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_DAMAGE_REDUCTION_MODIFIERS/,/public static boolean isRetiredPostNgePlayerDamageReductionModifier/p' "$work_buff_library")"
damage_reduction_modifier_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerDamageReductionModifier/,/public static boolean isRetiredPostNgePlayerDamageReductionBuff/p' "$work_buff_library")"
damage_reduction_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerDamageReductionBuff/,/public static void clearPostNgePlayerDamageReductionState/p' "$work_buff_library")"
damage_reduction_clear_source="$(sed -n '/public static void clearPostNgePlayerDamageReductionState/,/public static void retirePostNgePlayerDamageReductionState/p' "$work_buff_library")"
damage_reduction_retire_source="$(sed -n '/public static void retirePostNgePlayerDamageReductionState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
for damage_reduction_modifier in $damage_reduction_modifiers; do
    printf '%s' "$damage_reduction_inventory_source" | grep -Fq "\"$damage_reduction_modifier\""
done
test "$(printf '%s' "$damage_reduction_inventory_source" | grep -Ec '^        "[^"]+"[,]?$')" -eq 7
printf '%s' "$damage_reduction_modifier_predicate_source" | grep -Fq 'modifierName.equals(retiredModifier)'
printf '%s' "$damage_reduction_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s' "$damage_reduction_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s' "$damage_reduction_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerDamageReductionModifier(getEffectParam(data, effect))'
printf '%s' "$damage_reduction_clear_source" | grep -Fq 'removeAttribOrSkillModModifier(player, retiredModifier)'
printf '%s' "$damage_reduction_clear_source" | grep -Fq 'retiredModifier + "_" + effect'
printf '%s' "$damage_reduction_clear_source" | grep -Fq 'applySkillStatisticModifier(player, retiredModifier, -currentValue)'
printf '%s' "$damage_reduction_clear_source" | grep -Fq 'junkDealerDamageDecrease'
printf '%s' "$damage_reduction_retire_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$damage_reduction_retire_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s' "$damage_reduction_retire_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s' "$damage_reduction_retire_source" | grep -Fq 'clearPostNgePlayerDamageReductionState(player)'
grep -Fq 'retirePostNgePlayerDamageReductionState(player);' "$work_buff_library"
passive_profession_cleanup_source="$(sed -n '/private void retirePostNgePassiveProfessionState/,/private void retirePostNgeQueuedBattlefieldPlayerState/p' "$work_base_player")"
printf '%s' "$passive_profession_cleanup_source" | grep -Fq 'buff.retirePostNgeForceSensitiveStanceState(self);'
printf '%s' "$passive_profession_cleanup_source" | grep -Fq 'combat.retirePostNgeKillMeterPlayerState(self);'
printf '%s' "$passive_profession_cleanup_source" | grep -Fq 'pet_lib.retirePostNgeDroidCombatModuleState(self);'
! printf '%s' "$passive_profession_cleanup_source" | grep -Eq 'jedi\.JEDI_(STANCE|FOCUS)'
droid_module_player_inventory_source="$(sed -n '/RETIRED_POST_NGE_DROID_COMBAT_MODULE_PLAYER_ACTIONS/,/RETIRED_POST_NGE_DROID_COMBAT_MODULE_SERVER_ACTIONS/p' "$work_pet_library")"
droid_module_server_inventory_source="$(sed -n '/RETIRED_POST_NGE_DROID_COMBAT_MODULE_SERVER_ACTIONS/,/RETIRED_POST_NGE_DROID_COMBAT_MODULE_BUFFS/p' "$work_pet_library")"
droid_module_buff_inventory_source="$(sed -n '/RETIRED_POST_NGE_DROID_COMBAT_MODULE_BUFFS/,/SID_SYS_CANT_TAME/p' "$work_pet_library")"
test "$(printf '%s' "$droid_module_player_inventory_source" | grep -Ec '^        "droid_(flame_jet|droideka_shield|battery_dump|regenerative_plating|electrical_shock|torturous_needle)_[123]"[,]?$')" -eq 18
test "$(printf '%s' "$droid_module_server_inventory_source" | grep -Ec '^        "server_droid_(flame_jet|battery_dump|regenerative_plating|electrical_shock|torturous_needle)_[123]"[,]?$')" -eq 15
test "$(printf '%s' "$droid_module_buff_inventory_source" | grep -Ec '^        "droideka_shield_[123]"[,]?$')" -eq 3
droid_module_validate_source="$(sed -n '/public static obj_id validateDroidCommand/,/public static boolean isRetiredPostNgeDroidCombatModuleAction/p' "$work_pet_library")"
printf '%s' "$droid_module_validate_source" | grep -Fq 'retirePostNgeDroidCombatModuleState(player);'
printf '%s' "$droid_module_validate_source" | grep -Fq 'if (isIdValid(player) && isPlayer(player))'
droid_module_predicate_source="$(sed -n '/public static boolean isRetiredPostNgeDroidCombatModuleAction/,/public static void retirePostNgeDroidCombatModuleState/p' "$work_pet_library")"
printf '%s' "$droid_module_predicate_source" | grep -Fq 'obj_id master = getMaster(actor);'
printf '%s' "$droid_module_predicate_source" | grep -Fq 'isPlayer(master)'
droid_module_cleanup_source="$(sed -n '/public static void retirePostNgeDroidCombatModuleState/,/^}/p' "$work_pet_library")"
printf '%s' "$droid_module_cleanup_source" | grep -Fq 'while (hasCommand(player, retiredAction))'
printf '%s' "$droid_module_cleanup_source" | grep -Fq 'buff.removeBuff(droid, retiredBuff);'
droid_module_standard_action_source="$(sed -n '/public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)/,/public boolean doCombatPreCheck/p' "$work_combat_base")"
printf '%s' "$droid_module_standard_action_source" | grep -Fq 'pet_lib.isRetiredPostNgeDroidCombatModuleAction(self, actionName)'
printf '%s' "$droid_module_standard_action_source" | grep -Fq 'pet_lib.retirePostNgeDroidCombatModuleState(player);'
test "$(grep -Fc 'pet_lib.validateDroidCommand(self)' "$work_combat_actions")" -eq 18
awk -F '\t' '$1 ~ /^(droid_(flame_jet|droideka_shield|battery_dump|regenerative_plating|electrical_shock|torturous_needle)_[123]|server_droid_(flame_jet|battery_dump|regenerative_plating|electrical_shock|torturous_needle)_[123])$/ { found++ } END { if (found != 33) exit 3 }' "$work_command_table"
awk -F '\t' '$1 ~ /^(droid_(flame_jet|droideka_shield|battery_dump|regenerative_plating|electrical_shock|torturous_needle)_[123]|server_droid_(flame_jet|battery_dump|regenerative_plating|electrical_shock|torturous_needle)_[123])$/ { found++ } END { if (found != 33) exit 3 }' "$work_combat_data"
awk -F '\t' '$1 ~ /^droideka_shield_[123]$/ { found++ } END { if (found != 3) exit 3 }' "$work_buff_table"
awk -F '\t' '$1 == "detonateDroid" { found++ } END { if (found != 1) exit 3 }' "$work_command_table"
kill_meter_cleanup_source="$(sed -n '/public static void retirePostNgeKillMeterPlayerState/,/public static boolean setKillMeter/p' "$work_combat_library")"
printf '%s' "$kill_meter_cleanup_source" | grep -Fq 'if (!isPlayer(player))'
printf '%s' "$kill_meter_cleanup_source" | grep -Fq 'incrementKillMeter(player, -current);'
printf '%s' "$kill_meter_cleanup_source" | grep -Fq 'utils.removeScriptVarTree(player, "km");'
kill_meter_set_source="$(sed -n '/public static boolean setKillMeter/,/public static boolean modifyKillMeter/p' "$work_combat_library")"
kill_meter_modify_source="$(sed -n '/public static boolean modifyKillMeter/,/public static boolean canDrainKillMeter/p' "$work_combat_library")"
kill_meter_can_drain_source="$(sed -n '/public static boolean canDrainKillMeter/,/public static boolean drainKillMeter/p' "$work_combat_library")"
kill_meter_drain_source="$(sed -n '/public static boolean drainKillMeter/,/public static location getCommandGroundTargetLocation/p' "$work_combat_library")"
for kill_meter_player_gate_source in "$kill_meter_set_source" "$kill_meter_modify_source" "$kill_meter_can_drain_source" "$kill_meter_drain_source"; do
    printf '%s' "$kill_meter_player_gate_source" | grep -Fq 'if (isPlayer(player))'
    printf '%s' "$kill_meter_player_gate_source" | grep -Fq 'retirePostNgeKillMeterPlayerState(player);'
done
kill_meter_update_source="$(sed -n '/public void doKillMeterUpdate/,/^    }/p' "$work_combat_base")"
printf '%s' "$kill_meter_update_source" | grep -Fq 'boolean compatibleAttacker = !playerAttacker'
printf '%s' "$kill_meter_update_source" | grep -Fq 'boolean compatibleDefender = !playerDefender'
printf '%s' "$kill_meter_update_source" | grep -Fq '"km.damage_done"'
printf '%s' "$kill_meter_update_source" | grep -Fq '"km.damage_taken"'
for centralized_kill_meter_source in "$work_gcw_library" "$work_xp_library" "$work_combat_actions" "$work_combat_base"; do
    ! grep -Fq 'incrementKillMeter(' "$centralized_kill_meter_source"
done
test "$(grep -Eh 'combat\.modifyKillMeter\(' "$work_gcw_library" "$work_xp_library" "$work_combat_actions" "$work_combat_base" | wc -l)" -eq 7
stance_query_source="$(sed -n '/public static boolean isInStance/,/public static boolean playStanceVisual/p' "$work_buff_library")"
test "$(printf '%s' "$stance_query_source" | grep -Fc 'retirePostNgeForceSensitiveStanceState(player);')" -eq 2
! printf '%s' "$stance_query_source" | grep -Eq 'hasBuff\(player, "fs_buff_(def_1_1|ca_1)"\)'
precu_center_of_being_source="$(sed -n '/public int centerOfBeing/,/public int forceFocus/p' "$work_combat_actions")"
printf '%s' "$precu_center_of_being_source" | grep -Fq 'hasSkill(self, "combat_brawler_novice")'
printf '%s' "$precu_center_of_being_source" | grep -Fq '"centerofbeing"'
printf '%s' "$precu_center_of_being_source" | grep -Fq 'center_of_being_duration_'
printf '%s' "$precu_center_of_being_source" | grep -Fq '_center_of_being_efficacy'
printf '%s' "$precu_center_of_being_source" | grep -Fq 'combat.drainCombatActionAttributes'
! printf '%s' "$precu_center_of_being_source" | grep -Eq 'fs_buff_(def_1_1|ca_1)'
gcw_banner_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_GCW_BANNER_BUFFS/,/public static boolean isRetiredPostNgeGcwBannerBuff/p' "$work_buff_library")"
gcw_banner_cleanup_source="$(sed -n '/public static void retirePostNgeGcwBannerBuffState/,/public static boolean isRetiredPostNgeBountyHunterShieldBuff/p' "$work_buff_library")"
retired_gcw_banner_buffs="banner_buff_commando banner_buff_smuggler banner_buff_medic banner_buff_officer banner_buff_spy banner_buff_bounty_hunter banner_buff_force_sensitive banner_buff_trader banner_buff_entertainer"
test "$(printf '%s\n' $retired_gcw_banner_buffs | wc -l)" -eq 9
retained_gcw_banner_rows=0
for retired_gcw_banner_buff in $retired_gcw_banner_buffs; do
    printf '%s' "$gcw_banner_inventory_source" | grep -Fq "\"$retired_gcw_banner_buff\""
    if awk -F '\t' -v name="$retired_gcw_banner_buff" '$1 == name && $6 ~ /^Roadmap\./ { found=1 } END { exit(found ? 0 : 1) }' "$work_buff_table"; then
        retained_gcw_banner_rows=$((retained_gcw_banner_rows + 1))
    fi
done
test "$retained_gcw_banner_rows" -eq 9
printf '%s' "$gcw_banner_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$gcw_banner_cleanup_source" | grep -Fq 'removeBuff(player, retiredBuff)'
grep -Fq 'retirePostNgeGcwBannerBuffState(player);' "$work_buff_library"
gcw_banner_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
printf '%s' "$gcw_banner_admission_source" | grep -Fq 'isRetiredPostNgeGcwBannerBuff(bdata.buffName)'
test "$(printf '%s' "$gcw_banner_admission_source" | grep -nF 'isRetiredPostNgeGcwBannerBuff(bdata.buffName)' | cut -d: -f1)" -lt "$(printf '%s' "$gcw_banner_admission_source" | grep -nF 'hasBuff(target, nameCrc)' | cut -d: -f1)"
control_immunity_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_P14_PLAYER_CONTROL_IMMUNITY_BUFFS/,/public static boolean isRetiredPostP14PlayerControlImmunityBuff/p' "$work_buff_library")"
control_immunity_cleanup_source="$(sed -n '/public static void retirePostP14PlayerControlImmunityState/,/public static boolean isRetiredPostNgeBountyHunterShieldBuff/p' "$work_buff_library")"
retired_player_control_immunity_buffs="action_drain_immunity dazeBlockDebuff gcw_base_critical_heal_recourse mezBlockDebuff player_armor_break_immunity player_mez_immunity player_root_immunity player_slow_immunity player_snare_immunity towHk47MoveImmuneItem towMafosaMezImmune treasure_bonus_snare_immunity"
test "$(printf '%s\n' $retired_player_control_immunity_buffs | wc -l)" -eq 12
for retired_player_control_immunity_buff in $retired_player_control_immunity_buffs; do
    printf '%s' "$control_immunity_inventory_source" | grep -Fq "\"$retired_player_control_immunity_buff\""
    awk -F '\t' -v name="$retired_player_control_immunity_buff" '$1 == name { found++ } END { if (found != 1) exit 3 }' "$work_buff_table"
done
printf '%s' "$control_immunity_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$control_immunity_cleanup_source" | grep -Fq 'removeBuff(player, retiredBuff)'
grep -Fq 'retirePostP14PlayerControlImmunityState(player);' "$work_buff_library"
printf '%s' "$gcw_banner_admission_source" | grep -Fq 'isRetiredPostP14PlayerControlImmunityBuff(bdata.buffName)'
test "$(printf '%s' "$gcw_banner_admission_source" | grep -nF 'isRetiredPostP14PlayerControlImmunityBuff(bdata.buffName)' | cut -d: -f1)" -lt "$(printf '%s' "$gcw_banner_admission_source" | grep -nF 'hasBuff(target, nameCrc)' | cut -d: -f1)"
awk -F '\t' '$1 == "towHk47MoveImmuneItem" { found++; if ($2 != "snare" || $3 != "root" || $4 != "nullification") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
awk -F '\t' '$1 == "towMafosaMezImmune" { found++; if ($2 != "mez" || $3 != "root" || $4 != "nullification") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
for retained_control_item in 'item_tow_hk47_move_immune_06_01:towHk47MoveImmuneItem' 'item_tow_mafosa_mez_immune_06_01:towMafosaMezImmune' 'item_treasure_map_bonus_consumable_04_03:treasure_bonus_snare_immunity'; do
    retained_control_name="${retained_control_item%%:*}"
    retained_control_buff="${retained_control_item#*:}"
    awk -F '\t' -v name="$retained_control_name" '$1 == name { found++ } END { if (found != 1) exit 3 }' "$work_master_item_table"
    awk -F '\t' -v name="$retained_control_name" -v buff="$retained_control_buff" '$1 == name { found++; if (index($0, "\t" buff "\t") == 0) exit 2 } END { if (found != 1) exit 3 }' "$work_item_stats_table"
done
for boss_control_immunity_buff in boss_snare_immunity boss_root_immunity boss_mez_immunity; do
    ! printf '%s' "$control_immunity_inventory_source" | grep -Fq "\"$boss_control_immunity_buff\""
    grep -Fq "buff.applyBuff(self, \"$boss_control_immunity_buff\")" "$work_script/npc/boss/boss_movement_buff.java"
done
avoid_incap_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_P14_PLAYER_AVOID_INCAP_HEAL_BUFFS/,/public static boolean isRetiredPostP14PlayerAvoidIncapHealBuff/p' "$work_buff_library")"
avoid_incap_cleanup_source="$(sed -n '/public static void retirePostP14PlayerAvoidIncapHealState/,/public static boolean isRetiredPostNgeBountyHunterShieldBuff/p' "$work_buff_library")"
retired_player_avoid_incap_buffs="gcw_base_critical_heal_a gcw_base_critical_heal_b gcw_base_critical_heal_c gcw_base_critical_heal_d gcw_base_critical_heal_e pvp_last_man_ability pvp_last_man_rebel_ability tusken_endurance"
test "$(printf '%s\n' $retired_player_avoid_incap_buffs | wc -l)" -eq 8
for retired_player_avoid_incap_buff in $retired_player_avoid_incap_buffs; do
    printf '%s' "$avoid_incap_inventory_source" | grep -Fq "\"$retired_player_avoid_incap_buff\""
    awk -F '\t' -v name="$retired_player_avoid_incap_buff" '$1 == name { found++; if ($8 != "avoid_incap_heal") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
done
printf '%s' "$avoid_incap_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$avoid_incap_cleanup_source" | grep -Fq 'removeBuff(player, retiredBuff)'
printf '%s' "$avoid_incap_cleanup_source" | grep -Fq 'utils.removeScriptVar(player, "buff_handler.gcw_critical_heal")'
grep -Fq 'retirePostP14PlayerAvoidIncapHealState(player);' "$work_buff_library"
printf '%s' "$gcw_banner_admission_source" | grep -Fq 'isRetiredPostP14PlayerAvoidIncapHealBuff(bdata.buffName)'
test "$(printf '%s' "$gcw_banner_admission_source" | grep -nF 'isRetiredPostP14PlayerAvoidIncapHealBuff(bdata.buffName)' | cut -d: -f1)" -lt "$(printf '%s' "$gcw_banner_admission_source" | grep -nF 'hasBuff(target, nameCrc)' | cut -d: -f1)"
avoid_incap_effect_add_source="$(sed -n '/public int onIncapHealAddBuffHandler/,/public int onIncapHealRemoveBuffHandler/p' "$work_buff_handler")"
avoid_incap_effect_remove_source="$(sed -n '/public int onIncapHealRemoveBuffHandler/,/public int healEffectAddBuffHandler/p' "$work_buff_handler")"
avoid_incap_effect_guard_source_line="$(printf '%s\n' "$avoid_incap_effect_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
avoid_incap_effect_cleanup_source_line="$(printf '%s\n' "$avoid_incap_effect_add_source" | grep -Fn 'buff.retirePostP14PlayerAvoidIncapHealState(self);' | head -1 | cut -d: -f1)"
avoid_incap_effect_return_source_line="$(printf '%s\n' "$avoid_incap_effect_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
avoid_incap_effect_write_source_line="$(printf '%s\n' "$avoid_incap_effect_add_source" | grep -Fn 'utils.setScriptVar(self, "buff_handler." + subtype, value);' | head -1 | cut -d: -f1)"
test -n "$avoid_incap_effect_guard_source_line" -a -n "$avoid_incap_effect_cleanup_source_line" -a -n "$avoid_incap_effect_return_source_line" -a -n "$avoid_incap_effect_write_source_line"
test "$avoid_incap_effect_guard_source_line" -lt "$avoid_incap_effect_cleanup_source_line"
test "$avoid_incap_effect_cleanup_source_line" -lt "$avoid_incap_effect_return_source_line"
test "$avoid_incap_effect_return_source_line" -lt "$avoid_incap_effect_write_source_line"
! printf '%s' "$avoid_incap_effect_remove_source" | grep -Fq 'retirePostP14PlayerAvoidIncapHealState'
printf '%s' "$avoid_incap_effect_remove_source" | grep -Fq 'utils.removeScriptVar(self, "buff_handler." + subtype)'
awk -F '\t' '$2 == "onIncapHeal" { found++; if ($1 != "avoid_incap_heal" || $3 != "gcw_critical_heal") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
critical_heal_source="$(sed -n '/public boolean performCriticalHeal/,/public void sendSmugglerSystemBootstrap/p' "$work_base_player")"
printf '%s' "$critical_heal_source" | grep -Fq 'buff.isPostNgeBuffProgressionRetired()'
printf '%s' "$critical_heal_source" | grep -Fq 'buff.retirePostP14PlayerAvoidIncapHealState(self);'
test "$(printf '%s' "$critical_heal_source" | grep -nF 'buff.isPostNgeBuffProgressionRetired()' | cut -d: -f1)" -lt "$(printf '%s' "$critical_heal_source" | grep -nF 'buff.getAllBuffs(self)' | cut -d: -f1)"
! printf '%s' "$critical_heal_source" | grep -Fq 'avoidIncapacitation'
awk -F '\t' '$1 ~ /^avoidIncapacitation(_[1-5])?$/ { found++; if ($8 != "avoid_incap") exit 2 } END { if (found != 6) exit 3 }' "$work_buff_table"
grep -Fq 'buff.hasBuff(player, "avoidIncapacitation")' "$work_script/library/jedi.java"
grep -Fq 'meditation.forceOfWill(self, delta)' "$work_script/player/skill/teraskasi.java"
for retained_avoid_incap_item in 'item_gcw_base_reactive_critical_heal_a_03_01:gcw_base_critical_heal_a' 'item_gcw_base_reactive_critical_heal_b_03_01:gcw_base_critical_heal_b' 'item_gcw_base_reactive_critical_heal_c_03_01:gcw_base_critical_heal_c' 'item_gcw_base_reactive_critical_heal_d_03_01:gcw_base_critical_heal_d' 'item_gcw_base_reactive_critical_heal_e_04_01:gcw_base_critical_heal_e' 'item_cs_reactive_critical_heal_e_04_01:gcw_base_critical_heal_e'; do
    retained_avoid_incap_name="${retained_avoid_incap_item%%:*}"
    retained_avoid_incap_buff="${retained_avoid_incap_item#*:}"
    awk -F '\t' -v name="$retained_avoid_incap_name" '$1 == name { found++ } END { if (found != 1) exit 3 }' "$work_master_item_table"
    awk -F '\t' -v name="$retained_avoid_incap_name" -v buff="$retained_avoid_incap_buff" '$1 == name { found++; if (index($0, "\t" buff "\t") == 0) exit 2 } END { if (found != 1) exit 3 }' "$work_item_stats_table"
done
awk -F '\t' '$1 == "command_pvp_last_man_ability" || $1 == "command_pvp_last_man_rebel_ability" { found++ } END { if (found != 2) exit 3 }' "$work_command_table"
grep -Fq 'buffHandler:add:tusken_endurance:player' "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/spawning/heroic/tusken/cloning.tab"
pvp_reward_buff_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PVP_REWARD_BUFFS/,/public static boolean isRetiredPostNgePvpRewardBuff/p' "$work_factions_library")"
retired_pvp_reward_buffs="pvp_aura_buff_self pvp_aura_buff_target pvp_aura_buff_rebel_self pvp_aura_buff_rebel_target pvp_retaliation_ability pvp_retaliation_rebel_ability pvp_adrenaline_ability pvp_adrenaline_rebel_ability pvp_unstoppable_ability pvp_unstoppable_rebel_ability pvp_last_man_ability pvp_last_man_rebel_ability"
test "$(printf '%s\n' $retired_pvp_reward_buffs | wc -l)" -eq 12
for retired_pvp_reward_buff in $retired_pvp_reward_buffs; do
    printf '%s' "$pvp_reward_buff_inventory_source" | grep -Fq "\"$retired_pvp_reward_buff\""
done
grep -Fq 'for (String buffName : RETIRED_POST_NGE_PVP_REWARD_BUFFS)' "$work_factions_library"
printf '%s' "$gcw_banner_admission_source" | grep -Fq 'factions.isRetiredPostNgePvpRewardBuff(bdata.buffName)'
test "$(printf '%s' "$gcw_banner_admission_source" | grep -nF 'factions.isRetiredPostNgePvpRewardBuff(bdata.buffName)' | cut -d: -f1)" -lt "$(printf '%s' "$gcw_banner_admission_source" | grep -nF 'hasBuff(target, nameCrc)' | cut -d: -f1)"
pvp_reward_action_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PVP_REWARD_PLAYER_ACTIONS/,/public static boolean isRetiredPostNgePvpRewardPlayerAction/p' "$work_combat_base")"
retired_pvp_reward_actions="command_pvp_adrenaline_ability command_pvp_adrenaline_rebel_ability command_pvp_last_man_ability command_pvp_last_man_rebel_ability command_pvp_retaliation_ability command_pvp_retaliation_rebel_ability command_pvp_unstoppable_ability command_pvp_unstoppable_rebel_ability pvp_adrenaline_ability pvp_adrenaline_rebel_ability pvp_airstrike_ability pvp_airstrike_rebel_ability pvp_aura_buff_rebel_self pvp_aura_buff_self pvp_last_man_ability pvp_last_man_rebel_ability pvp_retaliation_ability pvp_retaliation_rebel_ability pvp_unstoppable_ability pvp_unstoppable_rebel_ability"
test "$(printf '%s\n' $retired_pvp_reward_actions | wc -l)" -eq 20
for retired_pvp_reward_action in $retired_pvp_reward_actions; do
    printf '%s' "$pvp_reward_action_inventory_source" | grep -Fq "\"$retired_pvp_reward_action\""
done
pvp_reward_standard_action_source="$(sed -n '/public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)/,/combat.revealPrecuFeignDeath(self, "combatCommand")/p' "$work_combat_base")"
printf '%s' "$pvp_reward_standard_action_source" | grep -Fq 'isRetiredPostNgePvpRewardPlayerAction(self, actionName)'
printf '%s' "$pvp_reward_standard_action_source" | grep -Fq 'factions.retirePostNgePvpRewardState(self);'
test "$(grep -Ec '^    public int ((command_)?pvp_(aura_buff_(rebel_)?self|retaliation(_rebel)?_ability|adrenaline(_rebel)?_ability|unstoppable(_rebel)?_ability|last_man(_rebel)?_ability|airstrike(_rebel)?_ability))\(' "$work_combat_actions")" -eq 20
test "$(grep -Fc 'factions.retirePostNgePvpRewardState(self);' "$work_pvp_aura_controller")" -eq 3
test "$(grep -Fc 'if (isPlayer(self))' "$work_pvp_aura_controller")" -eq 3
grep -Fq 'isMob(self) && !isPlayer(self)' "$work_pvp_aura_controller"
grep -Fq 'buff.applyBuff(players, "pvp_aura_buff_rebel_target")' "$work_pvp_aura_controller"
grep -Fq 'buff.applyBuff(players, "pvp_aura_buff_target")' "$work_pvp_aura_controller"
pvp_aura_effect_add_source="$(sed -n '/public int pvpAuraBuffSelfAddBuffHandler/,/public int pvpAuraBuffSelfRemoveBuffHandler/p' "$work_buff_handler")"
pvp_aura_effect_remove_source="$(sed -n '/public int pvpAuraBuffSelfRemoveBuffHandler/,/public int nextHitCritAddBuffHandler/p' "$work_buff_handler")"
pvp_aura_effect_guard_source_line="$(printf '%s\n' "$pvp_aura_effect_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
pvp_aura_effect_cleanup_source_line="$(printf '%s\n' "$pvp_aura_effect_add_source" | grep -Fn 'factions.retirePostNgePvpRewardState(self);' | head -1 | cut -d: -f1)"
pvp_aura_effect_return_source_line="$(printf '%s\n' "$pvp_aura_effect_add_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)"
pvp_aura_effect_attach_source_line="$(printf '%s\n' "$pvp_aura_effect_add_source" | grep -Fn 'attachScript(self, "player.gcw.pvp_aura_buff_controller")' | head -1 | cut -d: -f1)"
for pvp_aura_effect_source_line in "$pvp_aura_effect_guard_source_line" "$pvp_aura_effect_cleanup_source_line" "$pvp_aura_effect_return_source_line" "$pvp_aura_effect_attach_source_line"; do
    test -n "$pvp_aura_effect_source_line"
done
test "$pvp_aura_effect_guard_source_line" -lt "$pvp_aura_effect_cleanup_source_line"
test "$pvp_aura_effect_cleanup_source_line" -lt "$pvp_aura_effect_return_source_line"
test "$pvp_aura_effect_return_source_line" -lt "$pvp_aura_effect_attach_source_line"
! printf '%s' "$pvp_aura_effect_remove_source" | grep -Fq 'retirePostNgePvpRewardState'
printf '%s' "$pvp_aura_effect_remove_source" | grep -Fq 'detachScript(self, "player.gcw.pvp_aura_buff_controller")'
printf '%s' "$pvp_aura_effect_remove_source" | grep -Fq 'removeObjVar(self, "pvp_aura_buff.faction")'
! grep -Eq 'getPlayerProfession|getBannerBuff|buffPlayers|buff\.applyBuff' "$work_gcw_banner_manager"
grep -Fq 'messageTo(self, "handleDeleteSelf", null, 180.0f, false);' "$work_gcw_banner_manager"
test "$(grep -Fc 'trial.cleanupObject(self);' "$work_gcw_banner_manager")" -eq 2
gcw_commando_retirement_source="$(sed -n '/public static boolean isRetiredPostNgeCommandoPlayerAction/,/public static boolean isRetiredPostNgeMedicPlayerAction/p' "$work_combat_base")"
printf '%s' "$gcw_commando_retirement_source" | grep -Fq 'isPlayer(self)'
printf '%s' "$gcw_commando_retirement_source" | grep -Fq 'actionName.startsWith("co_")'
printf '%s' "$gcw_commando_retirement_source" | grep -Fq 'actionName.startsWith("kill_meter_co_")'
printf '%s' "$gcw_commando_retirement_source" | grep -Fq 'actionName.startsWith("expertise_co_")'
printf '%s' "$gcw_commando_retirement_source" | grep -Fq 'actionName.equals("banner_buff_commando")'
buildabuff_source="$(sed -n '/public int buildabuffAddBuffHandler/,/public int buildabuffRemoveBuffHandler/p' "$work_buff_handler")"
buildabuff_remove_source="$(sed -n '/public int buildabuffRemoveBuffHandler/,/public int meDoomAddBuffHandler/p' "$work_buff_handler")"
test "$(grep -Ec 'addSkillModModifier\(self, *"expertise_' "$work_buff_handler")" -eq 3
test "$(printf '%s' "$buildabuff_source" | grep -Ec 'addSkillModModifier\(self, *"expertise_')" -eq 3
printf '%s' "$buildabuff_source" | grep -Fq 'buff.isPostNgeBuffProgressionRetired()'
buildabuff_guard_line="$(printf '%s\n' "$buildabuff_source" | grep -Fn 'buff.isPostNgeBuffProgressionRetired()' | head -1 | cut -d: -f1)"
buildabuff_state_read_line="$(printf '%s\n' "$buildabuff_source" | grep -Fn 'performance.buildabuff.buffComponentKeys' | head -1 | cut -d: -f1)"
test "$buildabuff_guard_line" -lt "$buildabuff_state_read_line"
for buildabuff_reactive_heal_action in expertise_buildabuff_heal_1_reac expertise_buildabuff_heal_2_reac expertise_buildabuff_heal_3_reac; do
    printf '%s' "$buildabuff_source" | grep -Fq "addSkillModModifier(self, \"$buildabuff_reactive_heal_action\""
    printf '%s' "$buildabuff_remove_source" | grep -Fq "removeAttribOrSkillModModifier(self, \"$buildabuff_reactive_heal_action\")"
done
meditation_cleanup_source="$(sed -n '/public static void retirePostNgeMeditationBuffs/,/public static final String DOT_BLEEDING/p' "$work_buff_library")"
printf '%s' "$meditation_cleanup_source" | grep -Fq 'removeBuff(player, retiredBuff)'
test "$(printf '%s' "$meditation_cleanup_source" | grep -Ec '"fs_meditate_[123]"')" -eq 3
for retired_meditation_buff in fs_meditate_1 fs_meditate_2 fs_meditate_3; do
    printf '%s' "$meditation_cleanup_source" | grep -Fq "\"$retired_meditation_buff\""
done
grep -Fq 'retirePostNgeMeditationBuffs(player);' "$work_buff_library"
meditation_start_source="$(sed -n '/public static boolean startMeditation/,/public static void endMeditation/p' "$work_meditation_library")"
printf '%s' "$meditation_start_source" | grep -Fq 'buff.retirePostNgeMeditationBuffs(player);'
! grep -Fq 'fs_meditate_' "$work_meditation_library"
meditation_tick_source="$(sed -n '/public int handleMeditationTick/,/public int msgCoupDeGraceAuthoritativeCheck/p' "$work_base_player")"
printf '%s' "$meditation_tick_source" | grep -Fq 'meditation.trance(self)'
printf '%s' "$meditation_tick_source" | grep -Fq 'messageTo(self, meditation.HANDLER_MEDITATION_TICK'
! printf '%s' "$meditation_tick_source" | grep -Eq 'MEDITATE_BUFFS|fs_meditate_|buff\.applyBuff|utils\.isProfession\(self, utils\.FORCE_SENSITIVE\)|utils\.setScriptVar\(self, meditation\.VAR_MEDITATION_BASE'
awk -F '\t' '$1 ~ /^fs_meditate_[123]$/ { found++; if ($8 !~ /^expertise_/ || $12 != "expertise_resource_quality_increase") exit 2 } END { if (found != 3) exit 3 }' "$work_buff_table"
bounty_hunter_shield_predicate_source="$(sed -n '/public static boolean isRetiredPostNgeBountyHunterShieldBuff/,/public static void retirePostNgeBountyHunterShieldState/p' "$work_buff_library")"
bounty_hunter_shield_cleanup_source="$(sed -n '/public static void retirePostNgeBountyHunterShieldState/,/public static void retirePostNgeBuffProgression/p' "$work_buff_library")"
for retired_bounty_hunter_shield_buff in bh_shields_handler bh_shields bh_shields_block bh_shields_charged; do
    printf '%s' "$bounty_hunter_shield_predicate_source" | grep -Fq "buffName.equals(\"$retired_bounty_hunter_shield_buff\")"
    printf '%s' "$bounty_hunter_shield_cleanup_source" | grep -Fq "\"$retired_bounty_hunter_shield_buff\""
done
printf '%s' "$bounty_hunter_shield_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s' "$bounty_hunter_shield_cleanup_source" | grep -Fq 'removeBuff(player, retiredBuff)'
printf '%s' "$bounty_hunter_shield_cleanup_source" | grep -Fq 'detachScript(player, "player.skill.bh_shields")'
grep -Fq 'retirePostNgeBountyHunterShieldState(player);' "$work_buff_library"
can_apply_buff_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgeForceSensitiveStanceBuff(bdata.buffName)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgeBountyHunterShieldBuff(bdata.buffName)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'proc.isRetiredPostNgePlayerProcBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerCommandGrantBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerDamageDealtOverrideBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerWeaponSpeedOverrideBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerCriticalOverrideBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerLuckHitOverrideBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerForsakeFearChannelBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerRadarInvisibilityBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerForceThrowBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerDamageReductionBuff(target, bdata)'
printf '%s' "$can_apply_buff_source" | grep -Fq 'isRetiredPostNgePlayerModifierBuff(target, bdata)'
force_sensitive_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgeForceSensitiveStanceBuff(bdata.buffName)' | head -1 | cut -d: -f1)"
proc_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'proc.isRetiredPostNgePlayerProcBuff(target, bdata)' | head -1 | cut -d: -f1)"
command_grant_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerCommandGrantBuff(target, bdata)' | head -1 | cut -d: -f1)"
damage_dealt_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerDamageDealtOverrideBuff(target, bdata)' | head -1 | cut -d: -f1)"
weapon_speed_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerWeaponSpeedOverrideBuff(target, bdata)' | head -1 | cut -d: -f1)"
critical_override_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerCriticalOverrideBuff(target, bdata)' | head -1 | cut -d: -f1)"
luck_hit_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerLuckHitOverrideBuff(target, bdata)' | head -1 | cut -d: -f1)"
forsake_fear_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerForsakeFearChannelBuff(target, bdata)' | head -1 | cut -d: -f1)"
radar_invisibility_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerRadarInvisibilityBuff(target, bdata)' | head -1 | cut -d: -f1)"
force_throw_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerForceThrowBuff(target, bdata)' | head -1 | cut -d: -f1)"
damage_reduction_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerDamageReductionBuff(target, bdata)' | head -1 | cut -d: -f1)"
modifier_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerModifierBuff(target, bdata)' | head -1 | cut -d: -f1)"
generic_existing_buff_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$damage_reduction_generic_gate_line"
test -n "$modifier_generic_gate_line"
test -n "$generic_existing_buff_line"
test "$force_sensitive_generic_gate_line" -lt "$generic_existing_buff_line"
test "$proc_generic_gate_line" -lt "$generic_existing_buff_line"
test "$command_grant_generic_gate_line" -lt "$generic_existing_buff_line"
test "$damage_dealt_generic_gate_line" -lt "$generic_existing_buff_line"
test "$weapon_speed_generic_gate_line" -lt "$generic_existing_buff_line"
test "$critical_override_generic_gate_line" -lt "$generic_existing_buff_line"
test "$luck_hit_generic_gate_line" -lt "$generic_existing_buff_line"
test "$forsake_fear_generic_gate_line" -lt "$generic_existing_buff_line"
test "$radar_invisibility_generic_gate_line" -lt "$generic_existing_buff_line"
test "$force_throw_generic_gate_line" -lt "$generic_existing_buff_line"
profession_movement_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerProfessionMovementBuff(target, bdata)' | head -1 | cut -d: -f1)"
test -n "$profession_movement_generic_gate_line"
test "$profession_movement_generic_gate_line" -lt "$generic_existing_buff_line"
profession_immunity_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerProfessionImmunityBuff(target, bdata)' | head -1 | cut -d: -f1)"
test -n "$profession_immunity_generic_gate_line"
test "$profession_immunity_generic_gate_line" -lt "$generic_existing_buff_line"
profession_inspiration_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerProfessionInspirationBuff(target, bdata)' | head -1 | cut -d: -f1)"
test -n "$profession_inspiration_generic_gate_line"
test "$profession_inspiration_generic_gate_line" -lt "$generic_existing_buff_line"
profession_proxy_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerProfessionProxyBuff(target, bdata)' | head -1 | cut -d: -f1)"
test -n "$profession_proxy_generic_gate_line"
test "$profession_proxy_generic_gate_line" -lt "$generic_existing_buff_line"
commando_suppression_generic_gate_line="$(printf '%s\n' "$can_apply_buff_source" | grep -Fn 'isRetiredPostNgePlayerCommandoSuppressionBuff(target, bdata)' | head -1 | cut -d: -f1)"
test -n "$commando_suppression_generic_gate_line"
test "$commando_suppression_generic_gate_line" -lt "$generic_existing_buff_line"
test "$damage_reduction_generic_gate_line" -lt "$modifier_generic_gate_line"
test "$modifier_generic_gate_line" -lt "$generic_existing_buff_line"
force_sensitive_stance_handler_gate_line="$(printf '%s\n' "$stance_source" | grep -Fn 'buff.isRetiredPostNgeForceSensitiveStanceBuff(buffName)' | head -1 | cut -d: -f1)"
force_sensitive_stance_handler_cleanup_line="$(printf '%s\n' "$stance_source" | grep -Fn 'buff.retirePostNgeForceSensitiveStanceState(self);' | head -1 | cut -d: -f1)"
force_sensitive_stance_visual_line="$(printf '%s\n' "$stance_source" | grep -Fn 'buff.playStanceVisual(self, effectName);' | head -1 | cut -d: -f1)"
test "$force_sensitive_stance_handler_gate_line" -lt "$force_sensitive_stance_handler_cleanup_line"
test "$force_sensitive_stance_handler_cleanup_line" -lt "$force_sensitive_stance_visual_line"
force_sensitive_invis_handler_source="$(sed -n '/public void invisBuffAddBuffHandler/,/public void noBreakInvisRemoveBuffHandler/p' "$work_buff_handler")"
force_sensitive_invis_handler_gate_line="$(printf '%s\n' "$force_sensitive_invis_handler_source" | grep -Fn 'buff.isRetiredPostNgeForceSensitiveStanceBuff(buffName)' | head -1 | cut -d: -f1)"
force_sensitive_invis_handler_effect_line="$(printf '%s\n' "$force_sensitive_invis_handler_source" | grep -Fn 'stealth.invisBuffAdded(self, effectName);' | head -1 | cut -d: -f1)"
test "$force_sensitive_invis_handler_gate_line" -lt "$force_sensitive_invis_handler_effect_line"
force_throw_add_source="$(sed -n '/public int forceThrowAddBuffHandler/,/public int forceThrowRemoveBuffHandler/p' "$work_buff_handler")"
movement_add_source="$(sed -n '/public int movementAddBuffHandler/,/public int movementRemoveBuffHandler/p' "$work_buff_handler")"
movement_remove_source="$(sed -n '/public int movementRemoveBuffHandler/,/public int exclusiveProxyAddBuffHandler/p' "$work_buff_handler")"
profession_movement_prefixes='bh_ bm_ co_ en_ fs_ me_ of_ sm_ sp_ sl_group_'
test "$(printf '%s\n' $profession_movement_prefixes | wc -l)" -eq 10
test "$(awk -F '\t' '$1 == "movement" && $2 == "movement" { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 1
awk -F '\t' -v retired_prefixes="$profession_movement_prefixes" '
    BEGIN {
        split(retired_prefixes, prefixes, " ")
        expected["bh_"] = 13
        expected["bm_"] = 8
        expected["co_"] = 8
        expected["en_"] = 3
        expected["fs_"] = 16
        expected["me_"] = 5
        expected["of_"] = 14
        expected["sm_"] = 39
        expected["sp_"] = 4
        expected["sl_group_"] = 3
    }
    NR == 1 {
        for (field = 1; field <= NF; field++) {
            field_index[$field] = field
        }
        next
    }
    NR == 2 { next }
    {
        owns_movement = 0
        for (effect = 1; effect <= 5; effect++) {
            if ($(field_index["EFFECT" effect "_PARAM"]) == "movement") {
                owns_movement = 1
            }
        }
        if (!owns_movement) { next }
        movement_rows++
        retired = 0
        for (prefix_index in prefixes) {
            prefix = prefixes[prefix_index]
            if (substr($1, 1, length(prefix)) == prefix) {
                retired = 1
                retired_prefix_count[prefix]++
                break
            }
        }
        if (retired) {
            retired_rows++
            retired_name_rows[$1]++
        } else {
            preserved_rows++
        }
    }
    END {
        for (name in retired_name_rows) { retired_names++ }
        if (movement_rows != 224 || retired_rows != 113 || retired_names != 112 || preserved_rows != 111) exit 20
        if (retired_name_rows["fs_force_run"] != 2) exit 21
        for (prefix in expected) {
            if (retired_prefix_count[prefix] != expected[prefix]) exit 22
        }
    }
' "$work_buff_table"
profession_movement_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_PROFESSION_MOVEMENT_BUFF_PREFIXES/,/public static boolean isRetiredPostNgePlayerProfessionMovementBuffName/p' "$work_buff_library")"
test "$(printf '%s\n' "$profession_movement_inventory_source" | grep -Ec '^[[:space:]]*"[^"]+"[,;]?$')" -eq 11
for profession_movement_prefix in $profession_movement_prefixes; do
    printf '%s\n' "$profession_movement_inventory_source" | grep -Fq "\"$profession_movement_prefix\""
done
printf '%s\n' "$profession_movement_inventory_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_PROFESSION_MOVEMENT_TABLE_BUFF'
printf '%s\n' "$profession_movement_inventory_source" | grep -Fq '"en_unhealthy_fixation_debuff"'
awk -F '\t' '$1 == "en_unhealthy_stun" { found++; if ($2 != "enUnhealthyStun" || $3 != "en_unhealthy_stun") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '$1 == "en_unhealthy_fixation_debuff" { found++; if ($7 != 1 || $8 != "en_unhealthy_stun") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
awk -F '\t' '$1 == "en_unhealthy_fixation" { found++; if ($4 != "en_unhealthy_fixation" || $74 != "enemy" || $75 != "required") exit 2 } END { if (found != 1) exit 3 }' "$work_command_table"
awk -F '\t' '$1 == "en_unhealthy_fixation" { found++; if ($8 != "NON_DAMAGE_ATTACK" || $65 != "en_unhealthy_fixation_debuff" || $89 != "en_unhealthy_fixation_debuff") exit 2 } END { if (found != 1) exit 3 }' "$work_combat_data"
awk -F '\t' '$1 == "en_unhealthy_fixation_debuff" { found++; if ($2 != "root" || $4 != 1 || $5 != 1 || $6 != 1) exit 2 } END { if (found != 1) exit 3 }' "$work_movement_table"
awk -F '\t' '$1 ~ /^expertise_en_(unhealthy_fixation_1|allure_[1-4])$/ { found++ } END { if (found != 5) exit 3 }' "$work_skills"
profession_movement_name_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProfessionMovementBuffName/,/public static boolean isRetiredPostNgePlayerProfessionMovementBuff(/p' "$work_buff_library")"
profession_movement_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProfessionMovementBuff(/,/public static void retirePostNgePlayerProfessionMovementBuffState/p' "$work_buff_library")"
profession_movement_cleanup_source="$(sed -n '/public static void retirePostNgePlayerProfessionMovementBuffState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_GROUP_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$profession_movement_name_predicate_source" | grep -Fq 'buffName.startsWith(retiredPrefix)'
printf '%s\n' "$profession_movement_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$profession_movement_buff_predicate_source" | grep -Fq '"movement".equals(getEffectParam(data, effect))'
profession_movement_table_gate_line="$(printf '%s\n' "$profession_movement_buff_predicate_source" | grep -Fn 'data.buffName.equals(RETIRED_POST_NGE_PLAYER_PROFESSION_MOVEMENT_TABLE_BUFF)' | head -1 | cut -d: -f1)"
profession_movement_effect_scan_line="$(printf '%s\n' "$profession_movement_buff_predicate_source" | grep -Fn '"movement".equals(getEffectParam(data, effect))' | head -1 | cut -d: -f1)"
test -n "$profession_movement_table_gate_line" -a -n "$profession_movement_effect_scan_line"
test "$profession_movement_table_gate_line" -lt "$profession_movement_effect_scan_line"
printf '%s\n' "$profession_movement_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$profession_movement_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$profession_movement_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
sed -n '/public static void retirePostNgeBuffProgression/,/public static final String DOT_BLEEDING/p' "$work_buff_library" | grep -Fq 'retirePostNgePlayerProfessionMovementBuffState(player);'
! printf '%s\n' "$movement_remove_source" | grep -Fq 'isRetiredPostNgePlayerProfessionMovementBuffName'
printf '%s\n' "$movement_remove_source" | grep -Fq 'movement.removeMovementModifier(self, effectName);'
force_throw_add_guard_line="$(printf '%s\n' "$force_throw_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerForceThrowEffect(effectName))' | head -1 | cut -d: -f1)"
force_throw_add_return_line="$(printf '%s\n' "$force_throw_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
force_throw_owner_read_line="$(printf '%s\n' "$force_throw_add_source" | grep -Fn 'utils.getObjIdScriptVar(self, "buffOwner." + buffCrc)' | head -1 | cut -d: -f1)"
test "$force_throw_add_guard_line" -lt "$force_throw_add_return_line"
test "$force_throw_add_return_line" -lt "$force_throw_owner_read_line"
movement_add_profession_guard_line="$(printf '%s\n' "$movement_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerProfessionMovementBuffName(buffName))' | head -1 | cut -d: -f1)"
movement_add_force_throw_guard_line="$(printf '%s\n' "$movement_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerForceThrowBuffName(buffName))' | head -1 | cut -d: -f1)"
movement_add_writer_line="$(printf '%s\n' "$movement_add_source" | grep -Fn 'movement.applyMovementModifier(self, effectName, value);' | head -1 | cut -d: -f1)"
test -n "$movement_add_profession_guard_line"
test -n "$movement_add_force_throw_guard_line"
test -n "$movement_add_writer_line"
test "$movement_add_profession_guard_line" -lt "$movement_add_force_throw_guard_line"
test "$movement_add_force_throw_guard_line" -lt "$movement_add_writer_line"
test "$(printf '%s\n' "$movement_add_source" | grep -Fc 'return SCRIPT_OVERRIDE;')" -eq 2
profession_immunity_mapping_names='buff_purge debuff_purge dot_immunity movement_immunity state_immunity'
retired_profession_immunity_names='bm_pet_cure me_serotonin_boost_1 me_serotonin_purge_1 me_stasis_1 me_stasis_self_1 of_stimulator_1 sp_covert_mastery'
preserved_later_content_immunity_names='gcw_stim_remove_debuff_01 ice_cream_remove_debuff treasure_bonus_combat_dodge'
test "$(printf '%s\n' $profession_immunity_mapping_names | wc -l)" -eq 5
test "$(printf '%s\n' $retired_profession_immunity_names | wc -l)" -eq 7
test "$(printf '%s\n' $preserved_later_content_immunity_names | wc -l)" -eq 3
awk -F '\t' -v expected_names="$profession_immunity_mapping_names" '
    FNR == 1 {
        for (field = 1; field <= NF; field++) field_index[$field] = field
        split(expected_names, names, " ")
        for (name_index in names) expected[names[name_index]] = 1
        next
    }
    FNR == 2 { next }
    $(field_index["TYPE"]) == "immunity" {
        row_count++
        seen[$1]++
        if (!($1 in expected)) exit 48
    }
    END {
        if (row_count != 5) exit 49
        for (name in expected) if (seen[name] != 1) exit 50
    }
' "$work_buff_effect_mapping"
awk -F '\t' \
    -v mapping_names="$profession_immunity_mapping_names" \
    -v retired_names="$retired_profession_immunity_names" \
    -v preserved_names="$preserved_later_content_immunity_names" '
    BEGIN {
        split(mapping_names, names, " ")
        for (name_index in names) mapping[names[name_index]] = 1
        split(retired_names, names, " ")
        for (name_index in names) retired[names[name_index]] = 1
        split(preserved_names, names, " ")
        for (name_index in names) preserved[names[name_index]] = 1
    }
    FNR == 1 {
        for (field = 1; field <= NF; field++) field_index[$field] = field
        next
    }
    FNR == 2 { next }
    {
        uses = 0
        for (effect = 1; effect <= 5; effect++) {
            parameter = $(field_index["EFFECT" effect "_PARAM"])
            if (parameter in mapping) uses++
        }
        if (uses > 0) {
            row_count++
            use_count += uses
            if ($1 in retired) {
                retired_rows++
                retired_uses += uses
                retired_seen[$1]++
            } else if ($1 in preserved) {
                preserved_rows++
                preserved_uses += uses
                preserved_seen[$1]++
            } else {
                exit 51
            }
        }
    }
    END {
        if (row_count != 10 || use_count != 13) exit 52
        if (retired_rows != 7 || retired_uses != 10) exit 53
        if (preserved_rows != 3 || preserved_uses != 3) exit 54
        for (name in retired) if (retired_seen[name] != 1) exit 55
        for (name in preserved) if (preserved_seen[name] != 1) exit 56
    }
' "$work_buff_table"
profession_immunity_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_PROFESSION_IMMUNITY_BUFFS/,/public static boolean isRetiredPostNgePlayerProfessionImmunityBuffName/p' "$work_buff_library")"
test "$(printf '%s\n' "$profession_immunity_inventory_source" | grep -Ec '^[[:space:]]*"[^"]+"[,;]?$')" -eq 7
for profession_immunity_name in $retired_profession_immunity_names; do
    printf '%s\n' "$profession_immunity_inventory_source" | grep -Fq "\"$profession_immunity_name\""
done
profession_immunity_name_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProfessionImmunityBuffName/,/public static boolean isRetiredPostNgePlayerProfessionImmunityBuff(/p' "$work_buff_library")"
profession_immunity_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProfessionImmunityBuff(/,/public static void retirePostNgePlayerProfessionImmunityState/p' "$work_buff_library")"
profession_immunity_cleanup_source="$(sed -n '/public static void retirePostNgePlayerProfessionImmunityState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_PROFESSION_INSPIRATION_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$profession_immunity_name_predicate_source" | grep -Fq 'buffName.equals(retiredBuff)'
printf '%s\n' "$profession_immunity_buff_predicate_source" | grep -Fq 'isPlayer(target)'
printf '%s\n' "$profession_immunity_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerProfessionImmunityBuffName(data.buffName)'
printf '%s\n' "$profession_immunity_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$profession_immunity_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$profession_immunity_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$profession_immunity_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
sed -n '/public static void retirePostNgeBuffProgression/,/public static final String DOT_BLEEDING/p' "$work_buff_library" | grep -Fq 'retirePostNgePlayerProfessionImmunityState(player);'
profession_immunity_add_source="$(sed -n '/public int immunityAddBuffHandler/,/public int dotReductionAddBuffHandler/p' "$work_buff_handler")"
profession_immunity_remove_source="$(sed -n '/public int immunityRemoveBuffHandler/,/public int expertiseImmunityAddBuffHandler/p' "$work_buff_handler")"
profession_immunity_guard_line="$(printf '%s\n' "$profession_immunity_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerProfessionImmunityBuffName(buffName))' | head -1 | cut -d: -f1)"
profession_immunity_cleanup_line="$(printf '%s\n' "$profession_immunity_add_source" | grep -Fn 'buff.retirePostNgePlayerProfessionImmunityState(self);' | head -1 | cut -d: -f1)"
profession_immunity_return_line="$(printf '%s\n' "$profession_immunity_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | awk -F: -v cleanup="$profession_immunity_cleanup_line" '$1 > cleanup { print $1; exit }')"
profession_immunity_dot_writer_line="$(printf '%s\n' "$profession_immunity_add_source" | grep -Fn 'buff.performBuffDotImmunity' | head -1 | cut -d: -f1)"
profession_immunity_modifier_writer_line="$(printf '%s\n' "$profession_immunity_add_source" | grep -Fn 'removeAllModifiersOfType' | head -1 | cut -d: -f1)"
profession_immunity_buff_reader_line="$(printf '%s\n' "$profession_immunity_add_source" | grep -Fn 'getAllBuffs(self)' | head -1 | cut -d: -f1)"
profession_immunity_scriptvar_writer_line="$(printf '%s\n' "$profession_immunity_add_source" | grep -Fn 'utils.setScriptVar(self' | head -1 | cut -d: -f1)"
for profession_immunity_source_line in "$profession_immunity_guard_line" "$profession_immunity_cleanup_line" "$profession_immunity_return_line" "$profession_immunity_dot_writer_line" "$profession_immunity_modifier_writer_line" "$profession_immunity_buff_reader_line" "$profession_immunity_scriptvar_writer_line"; do
    test -n "$profession_immunity_source_line"
done
test "$profession_immunity_guard_line" -lt "$profession_immunity_cleanup_line"
test "$profession_immunity_cleanup_line" -lt "$profession_immunity_return_line"
test "$profession_immunity_return_line" -lt "$profession_immunity_dot_writer_line"
test "$profession_immunity_return_line" -lt "$profession_immunity_modifier_writer_line"
test "$profession_immunity_return_line" -lt "$profession_immunity_buff_reader_line"
test "$profession_immunity_return_line" -lt "$profession_immunity_scriptvar_writer_line"
! printf '%s\n' "$profession_immunity_remove_source" | grep -Fq 'isRetiredPostNgePlayerProfessionImmunityBuffName'
printf '%s\n' "$profession_immunity_remove_source" | grep -Fq 'utils.removeScriptVarTree'
printf '%s\n' "$profession_immunity_remove_source" | grep -Fq 'return SCRIPT_CONTINUE;'
profession_inspiration_names='general_inspiration artisan_inspiration entertainer_inspiration scout_inspiration chef_inspiration tailor_inspiration bioengineer_inspiration merchant_inspiration imagedesigner_inspiration musician_inspiration ranger_inspiration architect_inspiration droidengineer_inspiration weaponsmith_inspiration shipwright_inspiration armorsmith_inspiration dancer_inspiration'
test "$(printf '%s\n' $profession_inspiration_names | wc -l)" -eq 17
awk -F '\t' -v retired_names="$profession_inspiration_names" '
    NR == FNR {
        if (FNR > 2) effect_type[$1] = $2
        next
    }
    FNR == 1 {
        for (field = 1; field <= NF; field++) field_index[$field] = field
        split(retired_names, expected_names, " ")
        for (expected_index in expected_names) expected[expected_names[expected_index]] = expected_index
        next
    }
    FNR == 2 { next }
    ($1 in expected) {
        row_count++
        row_names[row_count] = $1
        if ($(field_index["DURATION"]) != "300" ||
            $(field_index["VISIBLE"]) != "1" ||
            $(field_index["IS_PERSISTENT"]) != "1") exit 30
        for (effect = 1; effect <= 5; effect++) {
            param = $(field_index["EFFECT" effect "_PARAM"])
            if (param == "") continue
            effect_uses++
            type_count[effect_type[param]]++
        }
    }
    END {
        if (row_count != 17 || effect_uses != 33) exit 31
        for (row_index = 1; row_index <= 17; row_index++) {
            if (row_names[row_index] != expected_names[row_index]) exit 32
        }
        if (type_count["xpBonus"] != 16 || type_count["xpBonusGeneral"] != 1 ||
            type_count["craftBonus"] != 9 || type_count["scriptVar"] != 6 ||
            type_count["skill"] != 1) exit 33
    }
' "$work_buff_effect_mapping" "$work_buff_table"
profession_inspiration_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_PROFESSION_INSPIRATION_BUFFS/,/public static boolean isRetiredPostNgePlayerProfessionInspirationBuffName/p' "$work_buff_library")"
test "$(printf '%s\n' "$profession_inspiration_inventory_source" | grep -Ec '^[[:space:]]*"[^"]+"[,;]?$')" -eq 17
profession_inspiration_inventory_index=0
for profession_inspiration_name in $profession_inspiration_names; do
    profession_inspiration_inventory_index=$((profession_inspiration_inventory_index + 1))
    test "$(printf '%s\n' "$profession_inspiration_inventory_source" | grep -Fn "\"$profession_inspiration_name\"" | head -1 | cut -d: -f1)" -eq $((profession_inspiration_inventory_index + 2))
done
profession_inspiration_name_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProfessionInspirationBuffName/,/public static boolean isRetiredPostNgePlayerProfessionInspirationBuff(/p' "$work_buff_library")"
profession_inspiration_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProfessionInspirationBuff(/,/public static void clearPostNgePlayerProfessionInspirationScriptVars/p' "$work_buff_library")"
profession_inspiration_scriptvar_cleanup_source="$(sed -n '/public static void clearPostNgePlayerProfessionInspirationScriptVars/,/public static void retirePostNgePlayerProfessionInspirationState/p' "$work_buff_library")"
profession_inspiration_cleanup_source="$(sed -n '/public static void retirePostNgePlayerProfessionInspirationState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_GROUP_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$profession_inspiration_name_predicate_source" | grep -Fq 'buffName.equals(retiredBuff)'
printf '%s\n' "$profession_inspiration_buff_predicate_source" | grep -Fq 'isPlayer(target)'
printf '%s\n' "$profession_inspiration_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerProfessionInspirationBuffName(data.buffName)'
printf '%s\n' "$profession_inspiration_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$profession_inspiration_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$profession_inspiration_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s\n' "$profession_inspiration_cleanup_source" | grep -Fq 'clearPostNgePlayerProfessionInspirationScriptVars(player);'
sed -n '/public static void retirePostNgeBuffProgression/,/public static final String DOT_BLEEDING/p' "$work_buff_library" | grep -Fq 'retirePostNgePlayerProfessionInspirationState(player);'
for profession_inspiration_scriptvar in buff.xpBonus buff.xpBonusGeneral buff.craftBonus buff.faction buff.instrument buff.prop buff.holoemote; do
    printf '%s\n' "$profession_inspiration_scriptvar_cleanup_source" | grep -Fq "utils.removeScriptVarTree(player, \"$profession_inspiration_scriptvar\");"
done
printf '%s\n' "$profession_inspiration_scriptvar_cleanup_source" | grep -Fq 'utils.removeScriptVarTree(player, "buff." + retiredBuff);'
grep -Fq 'if (!isNgeInspirationEnabled())' "$work_performance_library"
sed -n '/private static boolean isNgeInspirationEnabled/,/private static String getFormattedInspirationDuration/p' "$work_performance_library" | grep -Fq 'return false;'
scriptvar_add_source="$(sed -n '/public int scriptVarAddBuffHandler/,/public int scriptVarRemoveBuffHandler/p' "$work_buff_handler")"
scriptvar_remove_source="$(sed -n '/public int scriptVarRemoveBuffHandler/,/public int xpBonusAddBuffHandler/p' "$work_buff_handler")"
craft_bonus_add_source="$(sed -n '/public int craftBonusAddBuffHandler/,/public int craftBonusRemoveBuffHandler/p' "$work_buff_handler")"
craft_bonus_remove_source="$(sed -n '/public int craftBonusRemoveBuffHandler/,/public int forcePowerAddBuffHandler/p' "$work_buff_handler")"
scriptvar_add_guard_line="$(printf '%s\n' "$scriptvar_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerProfessionInspirationBuffName(buffName))' | head -1 | cut -d: -f1)"
scriptvar_add_cleanup_line="$(printf '%s\n' "$scriptvar_add_source" | grep -Fn 'buff.clearPostNgePlayerProfessionInspirationScriptVars(self);' | head -1 | cut -d: -f1)"
scriptvar_add_writer_line="$(printf '%s\n' "$scriptvar_add_source" | grep -Fn 'utils.setScriptVar(self, "buff." + effectName + ".value", value);' | head -1 | cut -d: -f1)"
craft_bonus_add_guard_line="$(printf '%s\n' "$craft_bonus_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerProfessionInspirationBuffName(buffName))' | head -1 | cut -d: -f1)"
craft_bonus_add_cleanup_line="$(printf '%s\n' "$craft_bonus_add_source" | grep -Fn 'buff.clearPostNgePlayerProfessionInspirationScriptVars(self);' | head -1 | cut -d: -f1)"
craft_bonus_add_writer_line="$(printf '%s\n' "$craft_bonus_add_source" | grep -Fn 'utils.setScriptVar(self, "buff.craftBonus.types", intValue);' | head -1 | cut -d: -f1)"
test "$scriptvar_add_guard_line" -lt "$scriptvar_add_cleanup_line"
test "$scriptvar_add_cleanup_line" -lt "$scriptvar_add_writer_line"
test "$craft_bonus_add_guard_line" -lt "$craft_bonus_add_cleanup_line"
test "$craft_bonus_add_cleanup_line" -lt "$craft_bonus_add_writer_line"
! printf '%s\n' "$scriptvar_remove_source" | grep -Fq 'isRetiredPostNgePlayerProfessionInspirationBuffName'
printf '%s\n' "$scriptvar_remove_source" | grep -Fq 'utils.removeScriptVarTree'
! printf '%s\n' "$craft_bonus_remove_source" | grep -Fq 'isRetiredPostNgePlayerProfessionInspirationBuffName'
printf '%s\n' "$craft_bonus_remove_source" | grep -Fq 'utils.removeScriptVarTree(self, "buff.craftBonus");'
profession_proxy_names='exclusive_proxy_bh_del_cc_1 exclusive_proxy_bh_del_cc_2 exclusive_proxy_bh_del_cc_3 exclusive_proxy_bh_del_dm_cc_dot_1 exclusive_proxy_bh_del_dm_cc_dot_2 exclusive_proxy_bh_del_dm_cc_dot_3 exclusive_proxy_of_last_words exclude_self_exclusive_proxy_of_last_words exclusive_proxy_bh_dire_root_1 exclusive_proxy_of_vortex_root_1 exclusive_proxy_of_vortex_root_2 exclusive_proxy_of_vortex_root_3 exclusive_proxy_of_vortex_root_4 exclusive_proxy_of_vortex_root_5 of_pt_proxy_1 of_pt_proxy_2 of_pt_proxy_3 of_pt_proxy_4 of_pt_proxy_5 of_pt_proxy_6 of_pt_proxy_7 of_pt_proxy_8 bh_del_cc_1 bh_del_cc_2 bh_del_cc_3 bh_del_dm_cc_dot_1 bh_del_dm_cc_dot_2 bh_del_dm_cc_dot_3 of_last_words of_last_words_recourse bh_dire_root_1 bh_dire_snare_1 dire_root_recourse dire_snare_recourse of_vortex_root of_vortex_snare of_vortex_bleed_1 of_vortex_bleed_2 of_vortex_bleed_3 of_vortex_bleed_4 of_vortex_bleed_5'
test "$(printf '%s\n' $profession_proxy_names | wc -l)" -eq 41
awk -F '\t' -v retired_names="$profession_proxy_names" '
    FNR == 1 {
        for (field = 1; field <= NF; field++) field_index[$field] = field
        split(retired_names, expected_names, " ")
        for (expected_index in expected_names) expected[expected_names[expected_index]] = 1
        next
    }
    FNR == 2 { next }
    ($1 in expected) {
        row_count++
        seen[$1]++
        if ($(field_index["IS_PERSISTENT"]) != "1") exit 34
        if ($(field_index["VISIBLE"]) == "1") visible_count++
    }
    END {
        if (row_count != 41 || visible_count != 36) exit 35
        for (expected_name in expected) if (seen[expected_name] != 1) exit 36
    }
' "$work_buff_table"
awk -F '\t' '
    FNR == 1 {
        for (field = 1; field <= NF; field++) field_index[$field] = field
        next
    }
    FNR == 2 { next }
    $(field_index["TYPE"]) == "exclusiveProxy" {
        exclusive_count++
        seen[$1]++
    }
    $(field_index["TYPE"]) == "paintTarget" {
        paint_count++
        seen[$1]++
    }
    $(field_index["TYPE"]) == "excludeSelf" {
        exclude_self_count++
        seen[$1]++
    }
    END {
        if (exclusive_count != 6 || paint_count != 1 || exclude_self_count != 1) exit 37
        if (seen["exclusive_proxy"] != 1 ||
            seen["exclusive_proxy_of_vortex_root_1"] != 1 ||
            seen["exclusive_proxy_of_vortex_root_2"] != 1 ||
            seen["exclusive_proxy_of_vortex_root_3"] != 1 ||
            seen["exclusive_proxy_of_vortex_root_4"] != 1 ||
            seen["exclusive_proxy_of_vortex_root_5"] != 1 ||
            seen["exclude_self"] != 1 ||
            seen["paint_target"] != 1) exit 38
    }
' "$work_buff_effect_mapping"
profession_proxy_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_PROFESSION_PROXY_BUFFS/,/public static boolean isRetiredPostNgePlayerProfessionProxyBuffName/p' "$work_buff_library")"
test "$(printf '%s\n' "$profession_proxy_inventory_source" | grep -Ec '^[[:space:]]*"[^"]+"[,;]?$')" -eq 41
profession_proxy_inventory_index=0
for profession_proxy_name in $profession_proxy_names; do
    profession_proxy_inventory_index=$((profession_proxy_inventory_index + 1))
    test "$(printf '%s\n' "$profession_proxy_inventory_source" | grep -Fn "\"$profession_proxy_name\"" | head -1 | cut -d: -f1)" -eq $((profession_proxy_inventory_index + 2))
done
profession_proxy_name_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProfessionProxyBuffName/,/public static boolean isRetiredPostNgePlayerProfessionProxyBuff(/p' "$work_buff_library")"
profession_proxy_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerProfessionProxyBuff(/,/public static void retirePostNgePlayerProfessionProxyState/p' "$work_buff_library")"
profession_proxy_cleanup_source="$(sed -n '/public static void retirePostNgePlayerProfessionProxyState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_GROUP_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$profession_proxy_name_predicate_source" | grep -Fq 'buffName.equals(retiredBuff)'
printf '%s\n' "$profession_proxy_buff_predicate_source" | grep -Fq 'isPlayer(target)'
printf '%s\n' "$profession_proxy_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerProfessionProxyBuffName(data.buffName)'
printf '%s\n' "$profession_proxy_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$profession_proxy_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$profession_proxy_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$profession_proxy_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
sed -n '/public static void retirePostNgeBuffProgression/,/public static final String DOT_BLEEDING/p' "$work_buff_library" | grep -Fq 'retirePostNgePlayerProfessionProxyState(player);'
exclusive_proxy_add_source="$(sed -n '/public int exclusiveProxyAddBuffHandler/,/public int exclusiveProxyRemoveBuffHandler/p' "$work_buff_handler")"
exclusive_proxy_remove_source="$(sed -n '/public int exclusiveProxyRemoveBuffHandler/,/public int excludeSelfAddBuffHandler/p' "$work_buff_handler")"
exclude_self_add_source="$(sed -n '/public int excludeSelfAddBuffHandler/,/public int excludeSelfRemoveBuffHandler/p' "$work_buff_handler")"
exclude_self_remove_source="$(sed -n '/public int excludeSelfRemoveBuffHandler/,/public int delayAttackAddBuffHandler/p' "$work_buff_handler")"
exclusive_proxy_guard_line="$(printf '%s\n' "$exclusive_proxy_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerProfessionProxyBuffName(buffName))' | head -1 | cut -d: -f1)"
exclusive_proxy_cleanup_line="$(printf '%s\n' "$exclusive_proxy_add_source" | grep -Fn 'buff.retirePostNgePlayerProfessionProxyState(self);' | head -1 | cut -d: -f1)"
exclusive_proxy_return_line="$(printf '%s\n' "$exclusive_proxy_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
exclusive_proxy_read_line="$(printf '%s\n' "$exclusive_proxy_add_source" | grep -Fn 'buff.getAllBuffs(self)' | head -1 | cut -d: -f1)"
exclusive_proxy_writer_line="$(printf '%s\n' "$exclusive_proxy_add_source" | grep -Fn 'buff.applyBuff(self, caster, s)' | head -1 | cut -d: -f1)"
for profession_proxy_source_line in "$exclusive_proxy_guard_line" "$exclusive_proxy_cleanup_line" "$exclusive_proxy_return_line" "$exclusive_proxy_read_line" "$exclusive_proxy_writer_line"; do
    test -n "$profession_proxy_source_line"
done
test "$exclusive_proxy_guard_line" -lt "$exclusive_proxy_cleanup_line"
test "$exclusive_proxy_cleanup_line" -lt "$exclusive_proxy_return_line"
test "$exclusive_proxy_return_line" -lt "$exclusive_proxy_read_line"
test "$exclusive_proxy_return_line" -lt "$exclusive_proxy_writer_line"
! printf '%s\n' "$exclusive_proxy_remove_source" | grep -Fq 'isRetiredPostNgePlayerProfessionProxyBuffName'
printf '%s\n' "$exclusive_proxy_remove_source" | grep -Fq 'return SCRIPT_CONTINUE;'
exclude_self_guard_line="$(printf '%s\n' "$exclude_self_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerProfessionProxyBuffName(buffName))' | head -1 | cut -d: -f1)"
exclude_self_cleanup_line="$(printf '%s\n' "$exclude_self_add_source" | grep -Fn 'buff.retirePostNgePlayerProfessionProxyState(self);' | head -1 | cut -d: -f1)"
exclude_self_return_line="$(printf '%s\n' "$exclude_self_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
exclude_self_read_line="$(printf '%s\n' "$exclude_self_add_source" | grep -Fn 'buff.getAllBuffs(self)' | head -1 | cut -d: -f1)"
exclude_self_writer_line="$(printf '%s\n' "$exclude_self_add_source" | grep -Fn 'buff.applyBuff(groupMember, self, actualBuff)' | head -1 | cut -d: -f1)"
for profession_proxy_source_line in "$exclude_self_guard_line" "$exclude_self_cleanup_line" "$exclude_self_return_line" "$exclude_self_read_line" "$exclude_self_writer_line"; do
    test -n "$profession_proxy_source_line"
done
test "$exclude_self_guard_line" -lt "$exclude_self_cleanup_line"
test "$exclude_self_cleanup_line" -lt "$exclude_self_return_line"
test "$exclude_self_return_line" -lt "$exclude_self_read_line"
test "$exclude_self_return_line" -lt "$exclude_self_writer_line"
! printf '%s\n' "$exclude_self_remove_source" | grep -Fq 'isRetiredPostNgePlayerProfessionProxyBuffName'
printf '%s\n' "$exclude_self_remove_source" | grep -Fq 'return SCRIPT_CONTINUE;'
profession_heal_effect_mapping_names='healing_action healing_health'
test "$(printf '%s\n' $profession_heal_effect_mapping_names | wc -l)" -eq 2
awk -F '\t' -v expected_names="$profession_heal_effect_mapping_names" '
    FNR == 1 {
        for (field = 1; field <= NF; field++) field_index[$field] = field
        split(expected_names, names, " ")
        for (name_index in names) expected[names[name_index]] = 1
        next
    }
    FNR == 2 { next }
    $(field_index["TYPE"]) == "healEffect" {
        row_count++
        seen[$1]++
        if (!($1 in expected)) exit 39
    }
    END {
        if (row_count != 2) exit 40
        for (name in expected) if (seen[name] != 1) exit 41
    }
' "$work_buff_effect_mapping"
retired_profession_heal_effect_names='of_inspiration_1 of_inspiration_2 of_inspiration_3 of_inspiration_4 of_inspiration_5 of_inspiration_6 of_last_words sp_set_perfect_opportunity'
preserved_later_content_heal_effect_names='treasure_bonus_combat_strikethrough_chance treasure_bonus_heal_health_action ig_head_buff_2 ice_cream_heal_health ice_cream_heal_action'
test "$(printf '%s\n' $retired_profession_heal_effect_names | wc -l)" -eq 8
test "$(printf '%s\n' $preserved_later_content_heal_effect_names | wc -l)" -eq 5
awk -F '\t' \
    -v mapping_names="$profession_heal_effect_mapping_names" \
    -v retired_names="$retired_profession_heal_effect_names" \
    -v preserved_names="$preserved_later_content_heal_effect_names" '
    BEGIN {
        split(mapping_names, names, " ")
        for (name_index in names) mapping[names[name_index]] = 1
        split(retired_names, names, " ")
        for (name_index in names) retired[names[name_index]] = 1
        split(preserved_names, names, " ")
        for (name_index in names) preserved[names[name_index]] = 1
    }
    FNR == 1 {
        for (field = 1; field <= NF; field++) field_index[$field] = field
        next
    }
    FNR == 2 { next }
    {
        uses = 0
        for (effect = 1; effect <= 5; effect++) {
            parameter = $(field_index["EFFECT" effect "_PARAM"])
            if (parameter in mapping) uses++
        }
        if (uses > 0) {
            row_count++
            use_count += uses
            if ($1 in retired) {
                retired_rows++
                retired_uses += uses
                retired_seen[$1]++
            } else if ($1 in preserved) {
                preserved_rows++
                preserved_uses += uses
                preserved_seen[$1]++
            } else {
                exit 42
            }
        }
    }
    END {
        if (row_count != 13 || use_count != 15) exit 43
        if (retired_rows != 8 || retired_uses != 9) exit 44
        if (preserved_rows != 5 || preserved_uses != 6) exit 45
        for (name in retired) if (retired_seen[name] != 1) exit 46
        for (name in preserved) if (preserved_seen[name] != 1) exit 47
    }
' "$work_buff_table"
profession_heal_add_source="$(sed -n '/public int healEffectAddBuffHandler/,/public int healEffectRemoveBuffHandler/p' "$work_buff_handler")"
profession_heal_remove_source="$(sed -n '/public int healEffectRemoveBuffHandler/,/public int buildabuffAddBuffHandler/p' "$work_buff_handler")"
profession_heal_player_guard_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
profession_heal_inspiration_predicate_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'isRetiredPostNgePlayerProfessionInspirationBuffName' | head -1 | cut -d: -f1)"
profession_heal_inspiration_cleanup_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'retirePostNgePlayerProfessionInspirationState' | head -1 | cut -d: -f1)"
profession_heal_inspiration_return_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | awk -F: -v cleanup="$profession_heal_inspiration_cleanup_line" '$1 > cleanup { print $1; exit }')"
profession_heal_proxy_predicate_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'isRetiredPostNgePlayerProfessionProxyBuffName' | head -1 | cut -d: -f1)"
profession_heal_proxy_cleanup_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'retirePostNgePlayerProfessionProxyState' | head -1 | cut -d: -f1)"
profession_heal_proxy_return_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | awk -F: -v cleanup="$profession_heal_proxy_cleanup_line" '$1 > cleanup { print $1; exit }')"
profession_heal_spy_predicate_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'isRetiredPostNgeSpyBuffName' | head -1 | cut -d: -f1)"
profession_heal_spy_cleanup_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'retirePostNgeSpyPlayerState' | head -1 | cut -d: -f1)"
profession_heal_spy_return_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | awk -F: -v cleanup="$profession_heal_spy_cleanup_line" '$1 > cleanup { print $1; exit }')"
profession_heal_action_writer_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'healing.healDamage(self, ACTION, (int)value);' | head -1 | cut -d: -f1)"
profession_heal_health_writer_line="$(printf '%s\n' "$profession_heal_add_source" | grep -Fn 'healing.healDamage(caster, self, HEALTH, (int)value, false);' | head -1 | cut -d: -f1)"
for profession_heal_source_line in "$profession_heal_player_guard_line" "$profession_heal_inspiration_predicate_line" "$profession_heal_inspiration_cleanup_line" "$profession_heal_inspiration_return_line" "$profession_heal_proxy_predicate_line" "$profession_heal_proxy_cleanup_line" "$profession_heal_proxy_return_line" "$profession_heal_spy_predicate_line" "$profession_heal_spy_cleanup_line" "$profession_heal_spy_return_line" "$profession_heal_action_writer_line" "$profession_heal_health_writer_line"; do
    test -n "$profession_heal_source_line"
done
test "$profession_heal_player_guard_line" -lt "$profession_heal_inspiration_predicate_line"
test "$profession_heal_inspiration_predicate_line" -lt "$profession_heal_inspiration_cleanup_line"
test "$profession_heal_inspiration_cleanup_line" -lt "$profession_heal_inspiration_return_line"
test "$profession_heal_inspiration_return_line" -lt "$profession_heal_proxy_predicate_line"
test "$profession_heal_proxy_predicate_line" -lt "$profession_heal_proxy_cleanup_line"
test "$profession_heal_proxy_cleanup_line" -lt "$profession_heal_proxy_return_line"
test "$profession_heal_proxy_return_line" -lt "$profession_heal_spy_predicate_line"
test "$profession_heal_spy_predicate_line" -lt "$profession_heal_spy_cleanup_line"
test "$profession_heal_spy_cleanup_line" -lt "$profession_heal_spy_return_line"
test "$profession_heal_spy_return_line" -lt "$profession_heal_action_writer_line"
test "$profession_heal_spy_return_line" -lt "$profession_heal_health_writer_line"
! printf '%s\n' "$profession_heal_remove_source" | grep -Fq 'isRetiredPostNgePlayerProfession'
! printf '%s\n' "$profession_heal_remove_source" | grep -Fq 'isRetiredPostNgeSpyBuffName'
printf '%s\n' "$profession_heal_remove_source" | grep -Fq 'return SCRIPT_CONTINUE;'
officer_action_predicate_source="$(sed -n '/public static boolean isRetiredPostNgeOfficerPlayerAction/,/public static boolean isRetiredPostNgeForceSensitivePlayerAction/p' "$work_combat_base")"
bounty_hunter_action_predicate_source="$(sed -n '/public static boolean isRetiredPostNgeBountyHunterPlayerAction/,/public static boolean isRetiredPostNgeCommandoPlayerAction/p' "$work_combat_base")"
for officer_proxy_action in 'actionName.startsWith("of_")' 'actionName.equals("paintTarget")' 'actionName.startsWith("paintTarget_")' 'actionName.equals("applyVortexSnare")'; do
    printf '%s\n' "$officer_action_predicate_source" | grep -Fq "$officer_proxy_action"
done
for bounty_hunter_proxy_action in 'actionName.startsWith("bh_")' 'actionName.equals("dire_root_recourse")' 'actionName.equals("dire_snare_recourse")' 'actionName.equals("bountycheck")'; do
    printf '%s\n' "$bounty_hunter_action_predicate_source" | grep -Fq "$bounty_hunter_proxy_action"
done
combat_standard_admission_source="$(sed -n '/public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)/,/public hit_result\[\] runHitEngine/p' "$work_combat_base")"
officer_admission_line="$(printf '%s\n' "$combat_standard_admission_source" | grep -Fn 'isRetiredPostNgeOfficerPlayerAction(self, actionName)' | head -1 | cut -d: -f1)"
bounty_hunter_admission_line="$(printf '%s\n' "$combat_standard_admission_source" | grep -Fn 'isRetiredPostNgeBountyHunterPlayerAction(self, actionName)' | head -1 | cut -d: -f1)"
precu_admission_authority_line="$(printf '%s\n' "$combat_standard_admission_source" | grep -Fn 'combat.revealPrecuFeignDeath(self, "combatCommand")' | head -1 | cut -d: -f1)"
test "$officer_admission_line" -lt "$bounty_hunter_admission_line"
test "$bounty_hunter_admission_line" -lt "$precu_admission_authority_line"
paint_target_source="$(sed -n '/public int paintTarget(/,/public int blueGlowie/p' "$work_combat_actions")"
printf '%s\n' "$paint_target_source" | grep -Fq 'combatStandardAction("paintTarget", self, target, params, "", "")'
for profession_proxy_direct_spec in \
    'applyVortexSnare|isRetiredPostNgeOfficerPlayerAction(self, "applyVortexSnare")|buff.hasBuff(self, "of_vortex_snare")|getBaseCooldownTime' \
    'dire_root_recourse|isRetiredPostNgeBountyHunterPlayerAction(self, "dire_root_recourse")|buff.hasBuff(self, "dire_root_recourse")|dire_snare_recourse' \
    'dire_snare_recourse|isRetiredPostNgeBountyHunterPlayerAction(self, "dire_snare_recourse")|buff.hasBuff(self, "dire_snare_recourse")|bountycheck' \
    'bountycheck|isRetiredPostNgeBountyHunterPlayerAction(self, "bountycheck")|bounty_hunter.canCheckForBounty(self, target)|fs_drain_1'; do
    profession_proxy_direct_name="${profession_proxy_direct_spec%%|*}"
    profession_proxy_direct_rest="${profession_proxy_direct_spec#*|}"
    profession_proxy_direct_predicate="${profession_proxy_direct_rest%%|*}"
    profession_proxy_direct_rest="${profession_proxy_direct_rest#*|}"
    profession_proxy_direct_mutation="${profession_proxy_direct_rest%%|*}"
    profession_proxy_direct_next="${profession_proxy_direct_rest#*|}"
    profession_proxy_direct_source="$(sed -n "/public int $profession_proxy_direct_name(/,/public .* $profession_proxy_direct_next(/p" "$work_combat_actions")"
    profession_proxy_direct_predicate_line="$(printf '%s\n' "$profession_proxy_direct_source" | grep -Fn "$profession_proxy_direct_predicate" | head -1 | cut -d: -f1)"
    profession_proxy_direct_return_line="$(printf '%s\n' "$profession_proxy_direct_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
    profession_proxy_direct_mutation_line="$(printf '%s\n' "$profession_proxy_direct_source" | grep -Fn "$profession_proxy_direct_mutation" | head -1 | cut -d: -f1)"
    test -n "$profession_proxy_direct_predicate_line"
    test "$profession_proxy_direct_predicate_line" -lt "$profession_proxy_direct_return_line"
    test "$profession_proxy_direct_return_line" -lt "$profession_proxy_direct_mutation_line"
done
commando_suppression_names='co_supressing_handler co_supressing_fire_0 co_supressing_fire_1 co_supressing_fire_2 co_supressing_fire_3 co_supressing_fire_4'
test "$(printf '%s\n' $commando_suppression_names | wc -l)" -eq 6
awk -F '\t' -v retired_names="$commando_suppression_names" '
    FNR == 1 {
        for (field = 1; field <= NF; field++) field_index[$field] = field
        split(retired_names, expected_names, " ")
        for (expected_index in expected_names) expected[expected_names[expected_index]] = 1
        next
    }
    FNR == 2 { next }
    ($1 in expected) {
        row_count++
        seen[$1]++
        if ($(field_index["IS_PERSISTENT"]) != "1") exit 39
        if ($1 == "co_supressing_handler") {
            if ($(field_index["VISIBLE"]) != "0" ||
                $(field_index["EFFECT1_PARAM"]) != "supression_handler") exit 40
        } else {
            if ($(field_index["VISIBLE"]) != "1" ||
                $(field_index["EFFECT1_PARAM"]) != "glancing_blow_vulnerable" ||
                $(field_index["EFFECT2_PARAM"]) != "supress_movement") exit 41
        }
    }
    END {
        if (row_count != 6) exit 42
        for (expected_name in expected) if (seen[expected_name] != 1) exit 43
    }
' "$work_buff_table"
awk -F '\t' '
    FNR <= 2 { next }
    $1 == "supression_handler" && $2 == "supression_handler" && $3 == "supressingFire" { handler_count++ }
    $1 == "supress_movement" && $2 == "movementSupressingEffect" && $3 == "supress_movement" { movement_count++ }
    END { if (handler_count != 2 || movement_count != 2) exit 44 }
' "$work_buff_effect_mapping"
awk -F '\t' 'FNR > 2 && $1 == "co_suppressing_fire" { found++; if ($9 != "co_suppressing_fire") exit 45 } END { if (found != 1) exit 46 }' "$work_command_table"
awk -F '\t' 'FNR > 2 && $1 == "co_suppressing_fire" { found++; if ($65 != "co_supressing_handler") exit 47 } END { if (found != 1) exit 48 }' "$work_combat_data"
awk -F '\t' 'FNR > 2 && ($1 == "expertise_co_suppressing_fire_1" || $1 ~ /^expertise_co_suppression_efficiency_[1-4]$/) { found++ } END { if (found != 5) exit 49 }' "$work_skills_table"
test "$(awk -F '\t' 'FNR > 2 && ($1 == "suppressionFire1" || $1 == "suppressionFire2") { found++ } END { print found + 0 }' "$work_command_table")" -eq 2
test "$(awk -F '\t' 'FNR > 2 && ($1 == "suppressionFire1" || $1 == "suppressionFire2") { found++ } END { print found + 0 }' "$work_combat_data")" -eq 2
test "$(awk -F '\t' 'FNR > 2 && ($1 == "suppressionFire1" || $1 == "suppressionFire2") { found++ } END { print found + 0 }' "$work_combat_overrides")" -eq 2
commando_suppression_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_COMMANDO_SUPPRESSION_BUFFS/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_COMMANDO_SUPPRESSION_EFFECTS/p' "$work_buff_library")"
for commando_suppression_name in $commando_suppression_names; do
    printf '%s\n' "$commando_suppression_inventory_source" | grep -Fq "\"$commando_suppression_name\""
done
! printf '%s\n' "$commando_suppression_inventory_source" | grep -Fq '"suppressionFire"'
commando_suppression_effect_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_COMMANDO_SUPPRESSION_EFFECTS/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_COMMANDO_SUPPRESSION_MODIFIERS/p' "$work_buff_library")"
printf '%s\n' "$commando_suppression_effect_source" | grep -Fq '"supression_handler"'
printf '%s\n' "$commando_suppression_effect_source" | grep -Fq '"supress_movement"'
! printf '%s\n' "$commando_suppression_effect_source" | grep -Fq '"suppression"'
commando_suppression_modifier_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_COMMANDO_SUPPRESSION_MODIFIERS/,/public static boolean isRetiredPostNgePlayerCommandoSuppressionBuffName/p' "$work_buff_library")"
for commando_suppression_modifier in glancing_blow_vulnerable expertise_supression_speed expertise_supression_glance; do
    printf '%s\n' "$commando_suppression_modifier_source" | grep -Fq "\"$commando_suppression_modifier\""
done
commando_suppression_cleanup_source="$(sed -n '/public static void retirePostNgePlayerCommandoSuppressionState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_GROUP_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$commando_suppression_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s\n' "$commando_suppression_cleanup_source" | grep -Fq '"supress_movement".equals(getEffectParam(data, effect))'
printf '%s\n' "$commando_suppression_cleanup_source" | grep -Fq 'if (removedMovementSuppression)'
printf '%s\n' "$commando_suppression_cleanup_source" | grep -Fq 'removeSlowDownEffect(player)'
sed -n '/public static void retirePostNgeBuffProgression/,/public static final String DOT_BLEEDING/p' "$work_buff_library" | grep -Fq 'retirePostNgePlayerCommandoSuppressionState(player);'
commando_suppression_nested_add_source="$(sed -n '/public int supression_handlerAddBuffHandler/,/public int supression_handlerRemoveBuffHandler/p' "$work_buff_handler")"
commando_suppression_nested_remove_source="$(sed -n '/public int supression_handlerRemoveBuffHandler/,/public int movementSupressingEffectAddBuffHandler/p' "$work_buff_handler")"
commando_suppression_movement_add_source="$(sed -n '/public int movementSupressingEffectAddBuffHandler/,/public int movementSupressingEffectRemoveBuffHandler/p' "$work_buff_handler")"
commando_suppression_movement_remove_source="$(sed -n '/public int movementSupressingEffectRemoveBuffHandler/,/public int damageImmuneAddBuffHandler/p' "$work_buff_handler")"
for commando_suppression_add_source in "$commando_suppression_nested_add_source" "$commando_suppression_movement_add_source"; do
    commando_suppression_guard_line="$(printf '%s\n' "$commando_suppression_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
    commando_suppression_cleanup_line="$(printf '%s\n' "$commando_suppression_add_source" | grep -Fn 'buff.retirePostNgePlayerCommandoSuppressionState(self);' | head -1 | cut -d: -f1)"
    commando_suppression_return_line="$(printf '%s\n' "$commando_suppression_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
    test "$commando_suppression_guard_line" -lt "$commando_suppression_cleanup_line"
    test "$commando_suppression_cleanup_line" -lt "$commando_suppression_return_line"
done
test "$(printf '%s\n' "$commando_suppression_nested_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$commando_suppression_nested_add_source" | grep -Fn 'getEnhancedSkillStatisticModifierUncapped' | head -1 | cut -d: -f1)"
test "$(printf '%s\n' "$commando_suppression_nested_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$commando_suppression_nested_add_source" | grep -Fn 'buff.applyBuff' | head -1 | cut -d: -f1)"
test "$(printf '%s\n' "$commando_suppression_movement_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$commando_suppression_movement_add_source" | grep -Fn 'addSlowDownEffect' | head -1 | cut -d: -f1)"
! printf '%s\n' "$commando_suppression_nested_remove_source" | grep -Fq 'retirePostNgePlayerCommandoSuppressionState'
! printf '%s\n' "$commando_suppression_movement_remove_source" | grep -Fq 'retirePostNgePlayerCommandoSuppressionState'
damage_reduction_add_source="$(sed -n '/public int expertiseDamageDecreaseAddBuffHandler/,/public int expertiseDamageDecreaseRemoveBuffHandler/p' "$work_buff_handler")"
damage_reduction_remove_source="$(sed -n '/public int expertiseDamageDecreaseRemoveBuffHandler/,/public int onAttackRemoveAddBuffHandler/p' "$work_buff_handler")"
damage_reduction_add_guard_line="$(printf '%s\n' "$damage_reduction_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
damage_reduction_add_cleanup_line="$(printf '%s\n' "$damage_reduction_add_source" | grep -Fn 'buff.retirePostNgePlayerDamageReductionState(self);' | head -1 | cut -d: -f1)"
damage_reduction_add_return_line="$(printf '%s\n' "$damage_reduction_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
damage_reduction_add_read_line="$(printf '%s\n' "$damage_reduction_add_source" | grep -Fn 'getSkillStatisticModifier(self, "expertise_damage_decrease_percentage")' | head -1 | cut -d: -f1)"
damage_reduction_remove_guard_line="$(printf '%s\n' "$damage_reduction_remove_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
damage_reduction_remove_cleanup_line="$(printf '%s\n' "$damage_reduction_remove_source" | grep -Fn 'buff.clearPostNgePlayerDamageReductionState(self);' | head -1 | cut -d: -f1)"
damage_reduction_remove_return_line="$(printf '%s\n' "$damage_reduction_remove_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
damage_reduction_remove_truncation_line="$(printf '%s\n' "$damage_reduction_remove_source" | grep -Fn 'effectName.lastIndexOf("_")' | head -1 | cut -d: -f1)"
damage_reduction_remove_read_line="$(printf '%s\n' "$damage_reduction_remove_source" | grep -Fn 'getSkillStatisticModifier(self, "expertise_damage_decrease_percentage")' | head -1 | cut -d: -f1)"
for damage_reduction_source_line in "$damage_reduction_add_guard_line" "$damage_reduction_add_cleanup_line" "$damage_reduction_add_return_line" "$damage_reduction_add_read_line" "$damage_reduction_remove_guard_line" "$damage_reduction_remove_cleanup_line" "$damage_reduction_remove_return_line" "$damage_reduction_remove_truncation_line" "$damage_reduction_remove_read_line"; do
    test -n "$damage_reduction_source_line"
done
test "$damage_reduction_add_guard_line" -lt "$damage_reduction_add_cleanup_line"
test "$damage_reduction_add_cleanup_line" -lt "$damage_reduction_add_return_line"
test "$damage_reduction_add_return_line" -lt "$damage_reduction_add_read_line"
test "$damage_reduction_remove_guard_line" -lt "$damage_reduction_remove_cleanup_line"
test "$damage_reduction_remove_cleanup_line" -lt "$damage_reduction_remove_return_line"
test "$damage_reduction_remove_return_line" -lt "$damage_reduction_remove_truncation_line"
test "$damage_reduction_remove_truncation_line" -lt "$damage_reduction_remove_read_line"
damage_reduction_combat_source="$(sed -n '/public int expertiseDamageModify/,/public void doWrappedDamage/p' "$work_combat_base")"
damage_reduction_attacker_guard_line="$(printf '%s\n' "$damage_reduction_combat_source" | grep -Fn 'if (isPlayer(attacker))' | head -1 | cut -d: -f1)"
damage_reduction_attacker_cleanup_line="$(printf '%s\n' "$damage_reduction_combat_source" | grep -Fn 'buff.clearPostNgePlayerDamageReductionState(attacker);' | head -1 | cut -d: -f1)"
damage_reduction_defender_guard_line="$(printf '%s\n' "$damage_reduction_combat_source" | grep -Fn 'if (isPlayer(defender) && defender != attacker)' | head -1 | cut -d: -f1)"
damage_reduction_defender_cleanup_line="$(printf '%s\n' "$damage_reduction_combat_source" | grep -Fn 'buff.clearPostNgePlayerDamageReductionState(defender);' | head -1 | cut -d: -f1)"
damage_reduction_first_read_line="$(printf '%s\n' "$damage_reduction_combat_source" | grep -Fn 'getSkillStatisticModifier(attacker, "expertise_damage_decrease_chance")' | head -1 | cut -d: -f1)"
for damage_reduction_source_line in "$damage_reduction_attacker_guard_line" "$damage_reduction_attacker_cleanup_line" "$damage_reduction_defender_guard_line" "$damage_reduction_defender_cleanup_line" "$damage_reduction_first_read_line"; do
    test -n "$damage_reduction_source_line"
done
test "$damage_reduction_attacker_guard_line" -lt "$damage_reduction_attacker_cleanup_line"
test "$damage_reduction_attacker_cleanup_line" -lt "$damage_reduction_defender_guard_line"
test "$damage_reduction_defender_guard_line" -lt "$damage_reduction_defender_cleanup_line"
test "$damage_reduction_defender_cleanup_line" -lt "$damage_reduction_first_read_line"
for damage_reduction_combat_modifier in expertise_damage_decrease_chance expertise_sm_rank_damage_bonus expertise_damage_reduce_anticipate_aggression damage_decrease_percentage area_damage_decrease_percentage area_damage_resist_full_percentage; do
    printf '%s' "$damage_reduction_combat_source" | grep -Fq "\"$damage_reduction_combat_modifier\""
done
test "$(awk -F '\t' '$2 == "bmBeastFamily" { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 3
awk -F '\t' '$1 == "bm_beast_family_all" && $2 == "bmBeastFamily" && $3 == "all" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '$1 == "bm_beast_family_monkey" && $2 == "bmBeastFamily" && $3 == "monkey" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '$1 == "bm_beast_family_pig" && $2 == "bmBeastFamily" && $3 == "pig" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
for beast_family_buff_spec in \
    bm_truffle_pig:bm_beast_family_pig \
    bm_helper_monkey_domestic:bm_beast_family_monkey \
    bm_helper_monkey_engineering:bm_beast_family_monkey \
    bm_helper_monkey_structure:bm_beast_family_monkey \
    bm_helper_monkey_munitions:bm_beast_family_monkey \
    bm_helper_monkey_jedi:bm_beast_family_monkey \
    bm_helper_monkey_shipwright:bm_beast_family_monkey; do
    beast_family_buff_name="${beast_family_buff_spec%%:*}"
    beast_family_effect_name="${beast_family_buff_spec#*:}"
    awk -F '\t' -v name="$beast_family_buff_name" -v effect="$beast_family_effect_name" '
        $1 == name {
            found++
            if ($2 != "bm_player_buff" || $8 != effect) exit 2
        }
        END { if (found != 1) exit 3 }
    ' "$work_buff_table"
done
test "$(awk -F '\t' '
    $1 ~ /^(bm_truffle_pig|bm_helper_monkey_(domestic|engineering|structure|munitions|jedi|shipwright))$/ {
        for (column = 8; column <= 16; column += 2)
            if ($column ~ /^bm_beast_family_(all|monkey|pig)$/) uses++
    }
    END { print uses + 0 }
' "$work_buff_table")" -eq 7
beast_family_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_BEAST_FAMILY_BUFFS/,/public static boolean isRetiredPostNgePlayerBeastFamilyBuffName/p' "$work_buff_library")"
test "$(printf '%s\n' "$beast_family_inventory_source" | grep -Ec '^[[:space:]]+"bm_(truffle_pig|helper_monkey_(domestic|engineering|structure|munitions|jedi|shipwright))"[,]?$')" -eq 7
beast_family_cleanup_source="$(sed -n '/public static void retirePostNgePlayerBeastFamilyBuffState/,/private static final String\[\] RETIRED_POST_NGE_PLAYER_PROFESSION_MOVEMENT_BUFF_PREFIXES/p' "$work_buff_library")"
printf '%s' "$beast_family_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s' "$beast_family_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerBeastFamilyBuffState(player);' "$work_buff_library"
beast_family_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
beast_family_admission_line="$(printf '%s\n' "$beast_family_admission_source" | grep -Fn 'isRetiredPostNgePlayerBeastFamilyBuff(target, bdata)' | head -1 | cut -d: -f1)"
beast_family_existing_line="$(printf '%s\n' "$beast_family_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$beast_family_admission_line"
test -n "$beast_family_existing_line"
test "$beast_family_admission_line" -lt "$beast_family_existing_line"
beast_family_add_source="$(sed -n '/public void bmBeastFamilyAddBuffHandler/,/public void bmBeastFamilyRemoveBuffHandler/p' "$work_buff_handler")"
beast_family_add_identity_line="$(printf '%s\n' "$beast_family_add_source" | grep -Fn 'isRetiredPostNgePlayerBeastFamilyBuffName(buffName)' | head -1 | cut -d: -f1)"
beast_family_add_player_line="$(printf '%s\n' "$beast_family_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
beast_family_add_cleanup_line="$(printf '%s\n' "$beast_family_add_source" | grep -Fn 'retirePostNgeBeastMasterPlayerState(self);' | head -1 | cut -d: -f1)"
beast_family_add_return_line="$(printf '%s\n' "$beast_family_add_source" | grep -Fn 'return;' | head -1 | cut -d: -f1)"
beast_family_add_owned_line="$(printf '%s\n' "$beast_family_add_source" | grep -Fn 'isRetiredPostNgePlayerOwnedBeast(self)' | head -1 | cut -d: -f1)"
beast_family_add_nested_line="$(printf '%s\n' "$beast_family_add_source" | grep -Fn 'buff.applyBuff(master, self, buffName)' | head -1 | cut -d: -f1)"
for beast_family_source_line in "$beast_family_add_identity_line" "$beast_family_add_player_line" "$beast_family_add_cleanup_line" "$beast_family_add_return_line" "$beast_family_add_owned_line" "$beast_family_add_nested_line"; do
    test -n "$beast_family_source_line"
done
test "$beast_family_add_identity_line" -lt "$beast_family_add_player_line"
test "$beast_family_add_player_line" -lt "$beast_family_add_cleanup_line"
test "$beast_family_add_cleanup_line" -lt "$beast_family_add_return_line"
test "$beast_family_add_return_line" -lt "$beast_family_add_owned_line"
test "$beast_family_add_owned_line" -lt "$beast_family_add_nested_line"
printf '%s' "$beast_family_add_source" | grep -Fq 'retirePostNgeBeastMasterPlayerState(master);'
printf '%s' "$beast_family_add_source" | grep -Fq 'buff.removeBuff(self, buffName);'
beast_family_remove_source="$(sed -n '/public void bmBeastFamilyRemoveBuffHandler/,/public String getInitialBuffName/p' "$work_buff_handler")"
! printf '%s' "$beast_family_remove_source" | grep -Fq 'isRetiredPostNgePlayerBeastFamilyBuffName'
printf '%s' "$beast_family_remove_source" | grep -Fq 'buff.removeBuff(player, buffName);'
printf '%s' "$beast_family_remove_source" | grep -Fq 'buff.removeBuff(beast, buffName);'
verify_beast_family_direct_callback_source()
{
    beast_family_callback_name="$1"
    beast_family_callback_next="$2"
    beast_family_callback_source="$(sed -n "/public int $beast_family_callback_name(/,/public int $beast_family_callback_next(/p" "$work_player_beastmaster")"
    beast_family_callback_guard_line="$(printf '%s\n' "$beast_family_callback_source" | grep -Fn 'beast_lib.isRetiredPostNgeBeastMasterPlayer(self)' | head -1 | cut -d: -f1)"
    beast_family_callback_cleanup_line="$(printf '%s\n' "$beast_family_callback_source" | grep -Fn 'beast_lib.retirePostNgeBeastMasterPlayerState(self);' | head -1 | cut -d: -f1)"
    beast_family_callback_return_line="$(printf '%s\n' "$beast_family_callback_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
    beast_family_callback_read_line="$(printf '%s\n' "$beast_family_callback_source" | grep -Fn 'buff.hasBuff(player' | head -1 | cut -d: -f1)"
    for beast_family_callback_line in "$beast_family_callback_guard_line" "$beast_family_callback_cleanup_line" "$beast_family_callback_return_line" "$beast_family_callback_read_line"; do
        test -n "$beast_family_callback_line"
    done
    test "$beast_family_callback_guard_line" -lt "$beast_family_callback_cleanup_line"
    test "$beast_family_callback_cleanup_line" -lt "$beast_family_callback_return_line"
    test "$beast_family_callback_return_line" -lt "$beast_family_callback_read_line"
}
verify_beast_family_direct_callback_source bm_pig_forage bm_helper_monkey_domestic
verify_beast_family_direct_callback_source bm_helper_monkey_domestic bm_helper_monkey_engineering
verify_beast_family_direct_callback_source bm_helper_monkey_engineering bm_helper_monkey_structure
verify_beast_family_direct_callback_source bm_helper_monkey_structure bm_helper_monkey_munitions
verify_beast_family_direct_callback_source bm_helper_monkey_munitions bm_helper_monkey_jedi
verify_beast_family_direct_callback_source bm_helper_monkey_jedi bm_helper_monkey_shipwright
verify_beast_family_direct_callback_source bm_helper_monkey_shipwright bm_dancing_cat
awk -F '\t' '$1 == "battlefield_communcations_glow" && $2 == "battlefieldCommuncationsGlow" && $3 == "battlefield_communcations_glow" { found++ } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '$1 == "battlefield_communication_run" && $2 == "battlefield_communication_run" && $6 == "command.battlefield_communication_run" && $7 == 90 && $8 == "battlefield_communcations_glow" && $20 == "appearance/pt_battlefield_runner.prt" && $22 == 1 && $26 == 1 && $30 == 1 { found++ } END { if (found != 1) exit 3 }' "$work_buff_table"
test "$(grep -Fc 'buff.applyBuff(player, "battlefield_communication_run");' "$work_battlefield_controller")" -eq 1
test "$((
    $(grep -Fc 'buff.hasBuff(who, "battlefield_communication_run")' "$work_script/library/pvp.java") +
    $(grep -Fc '"battlefield_communication_run")' "$work_script/library/stealth.java") +
    $(grep -Fc 'buff.hasBuff(self, "battlefield_communication_run")' "$work_base_player") +
    $(grep -Fc 'buff.hasBuff(player, "battlefield_communication_run")' "$work_battlefield_terminal")
))" -eq 13
queued_battlefield_communication_identity_source="$(sed -n '/private static final String RETIRED_POST_NGE_PLAYER_QUEUED_BATTLEFIELD_COMMUNICATION_BUFF/,/private static final String RETIRED_POST_NGE_PLAYER_RADAR_INVISIBILITY_EFFECT/p' "$work_buff_library")"
printf '%s' "$queued_battlefield_communication_identity_source" | grep -Fq '"battlefield_communication_run"'
printf '%s' "$queued_battlefield_communication_identity_source" | grep -Fq 'isPlayer(target) && data != null'
printf '%s' "$queued_battlefield_communication_identity_source" | grep -Fq 'removeBuff(player, RETIRED_POST_NGE_PLAYER_QUEUED_BATTLEFIELD_COMMUNICATION_BUFF)'
queued_battlefield_communication_progression_source="$(sed -n '/public static void retirePostNgeBuffProgression/,/public static void retirePostNgeMeditationBuffs/p' "$work_buff_library")"
printf '%s' "$queued_battlefield_communication_progression_source" | grep -Fq 'retirePostNgePlayerQueuedBattlefieldCommunicationState(player);'
queued_battlefield_communication_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static boolean applyBuff(obj_id target, String name)/p' "$work_buff_library")"
queued_battlefield_communication_admission_line="$(printf '%s\n' "$queued_battlefield_communication_admission_source" | grep -Fn 'isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuff(target, bdata)' | head -1 | cut -d: -f1)"
queued_battlefield_communication_existing_line="$(printf '%s\n' "$queued_battlefield_communication_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$queued_battlefield_communication_admission_line"
test -n "$queued_battlefield_communication_existing_line"
test "$queued_battlefield_communication_admission_line" -lt "$queued_battlefield_communication_existing_line"
queued_battlefield_communication_add_source="$(sed -n '/public int battlefieldCommuncationsGlowAddBuffHandler/,/public int battlefieldCommuncationsGlowRemoveBuffHandler/p' "$work_buff_handler")"
printf '%s' "$queued_battlefield_communication_add_source" | grep -Fq 'if (isPlayer(self) && buff.isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuffName(buffName))'
queued_battlefield_communication_guard_line="$(printf '%s\n' "$queued_battlefield_communication_add_source" | grep -Fn 'if (isPlayer(self)' | head -1 | cut -d: -f1)"
queued_battlefield_communication_name_line="$(printf '%s\n' "$queued_battlefield_communication_add_source" | grep -Fn 'isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuffName(buffName)' | head -1 | cut -d: -f1)"
queued_battlefield_communication_cleanup_line="$(printf '%s\n' "$queued_battlefield_communication_add_source" | grep -Fn 'retirePostNgePlayerQueuedBattlefieldCommunicationState(self);' | head -1 | cut -d: -f1)"
queued_battlefield_communication_return_line="$(printf '%s\n' "$queued_battlefield_communication_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
queued_battlefield_communication_writer_line="$(printf '%s\n' "$queued_battlefield_communication_add_source" | grep -Fn 'buff.removeBuff(self, "battlefield_radar_invisibility")' | head -1 | cut -d: -f1)"
for queued_battlefield_communication_source_line in "$queued_battlefield_communication_guard_line" "$queued_battlefield_communication_name_line" "$queued_battlefield_communication_cleanup_line" "$queued_battlefield_communication_return_line" "$queued_battlefield_communication_writer_line"; do
    test -n "$queued_battlefield_communication_source_line"
done
test "$queued_battlefield_communication_guard_line" -le "$queued_battlefield_communication_name_line"
test "$queued_battlefield_communication_name_line" -lt "$queued_battlefield_communication_cleanup_line"
test "$queued_battlefield_communication_cleanup_line" -lt "$queued_battlefield_communication_return_line"
test "$queued_battlefield_communication_return_line" -lt "$queued_battlefield_communication_writer_line"
queued_battlefield_communication_remove_source="$(sed -n '/public int battlefieldCommuncationsGlowRemoveBuffHandler/,/public int empireDayImperialRecruitmentAddBuffHandler/p' "$work_buff_handler")"
! printf '%s' "$queued_battlefield_communication_remove_source" | grep -Fq 'isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuffName'
printf '%s' "$queued_battlefield_communication_remove_source" | grep -Fq 'buff.applyBuff(self, "battlefield_radar_invisibility");'
bounty_hunter_shield_handler_source="$(sed -n '/public int bhShieldsAddBuffHandler/,/public int bhShieldsRemoveBuffHandler/p' "$work_buff_handler")"
printf '%s' "$bounty_hunter_shield_handler_source" | grep -Fq 'if (isPlayer(self))'
printf '%s' "$bounty_hunter_shield_handler_source" | grep -Fq 'buff.retirePostNgeBountyHunterShieldState(self);'
test "$(grep -Fc 'buff.retirePostNgeBountyHunterShieldState(self);' "$work_bh_shields")" -eq 3
test "$(grep -Fc 'if (isPlayer(self))' "$work_bh_shields")" -eq 3
awk -F '\t' '$1 ~ /^bh_shields(_handler|_block|_charged)?$/ { found++ } END { if (found != 4) exit 3 }' "$work_buff_table"
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
test "$(grep -Fc 'isRetiredPostNgeOfficerPlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 4
! grep -Fq 'expertise_of_reinforcements_1' "$work_script/ai/officer_pet.java"
grep -Fq 'pet_lib.destroyOfficerPets(master)' "$work_script/ai/officer_pet.java"
test "$(grep -Fc 'retirePostNgeOfficerSupplyDrop(self, owner)' "$work_script/systems/combat/combat_supply_drop_controller.java")" -eq 3
grep -Fq 'isPlayer(owner)' "$work_script/systems/combat/combat_supply_drop_controller.java"
grep -Fq 'isPlayer(transferer)' "$work_script/systems/combat/combat_supply_drop_crate.java"
grep -Fq 'retirePostNgeOfficerSupplyCrate(self)' "$work_script/systems/combat/combat_supply_drop_crate.java"
force_sensitive_action_predicate_source="$(sed -n '/public static boolean isRetiredPostNgeForceSensitivePlayerAction/,/public static boolean isRetiredPostNgeSmugglerPlayerAction/p' "$work_script/systems/combat/combat_base.java")"
printf '%s' "$force_sensitive_action_predicate_source" | grep -Fq 'actionName.startsWith("fs_")'
printf '%s' "$force_sensitive_action_predicate_source" | grep -Fq 'actionName.equals("forceThrow")'
! printf '%s' "$force_sensitive_action_predicate_source" | grep -Fq 'actionName.startsWith("forceThrow")'
grep -Fq 'isRetiredPostNgeForceSensitivePlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeForceSensitivePlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 1
grep -Fq 'buff.removeBuff(self, "fs_dot_immunity_recourse")' "$work_script/systems/combat/combat_actions.java"
force_throw_action_source="$(sed -n '/public int forceThrow(/,/public int ambush(/p' "$work_script/systems/combat/combat_actions.java")"
printf '%s' "$force_throw_action_source" | grep -Fq 'combatStandardAction("forceThrow"'
grep -Fq 'actionName.startsWith("sm_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeSmugglerPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeSmugglerPlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 6
for recourse in sm_feeling_lucky_recourse sm_lucky_break_recourse sm_break_the_deal_recourse sm_melee_stun_recourse; do
    grep -Fq "buff.removeBuff(self, \"$recourse\")" "$work_script/systems/combat/combat_actions.java"
done
grep -Fq 'actionName.startsWith("bh_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeBountyHunterPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
grep -Fq 'actionName.startsWith("co_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'actionName.startsWith("kill_meter_co_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'actionName.startsWith("expertise_co_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeCommandoPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeCommandoPlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 1
grep -Fq 'isRetiredPostNgeCommandoPlayerAction(self, "co_kill_trap_1")' "$work_script/systems/combat/combat_actions.java"
grep -Fq 'actionName.startsWith("me_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'actionName.equals("expertise_dueterium_rounds_proc")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'actionName.equals("expertise_poison_knuckle_proc")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeMedicPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeMedicPlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 17
grep -Fq 'actionName.startsWith("en_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'actionName.startsWith("expertise_buildabuff_")' "$work_script/systems/combat/combat_base.java"
grep -Fq 'isRetiredPostNgeEntertainerPlayerAction(self, actionName)' "$work_script/systems/combat/combat_base.java"
test "$(grep -Fc 'isRetiredPostNgeEntertainerPlayerAction(self, "' "$work_script/systems/combat/combat_actions.java")" -eq 2
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
retired_buff_combat_modifiers="combat_add_damage_dealt combat_add_damage_taken combat_all_attack_avoidance combat_all_attack_miss combat_all_attack_miss_reduction combat_all_attack_miss_vulnerability combat_block_reduction combat_critical_hit combat_divide_damage_dealt combat_divide_damage_taken combat_dodge_reduction combat_glancing combat_glancing_blow_reduction combat_melee_attack_avoidance combat_melee_attack_miss combat_melee_attack_miss_reduction combat_melee_attack_vulnerability combat_multiply_damage_dealt combat_multiply_damage_taken combat_parry_reduction combat_ranged_attack_avoidance combat_ranged_attack_miss combat_ranged_attack_miss_reduction combat_ranged_attack_vulnerability combat_subtract_damage_dealt combat_subtract_damage_taken crit_always critical_hit_vulnerable flurry_cooldown_modifier freeshot_case_crit freeshot_case_dodge freeshot_case_miss freeshot_case_parry freeshot_case_strikethrough glancing_blow_vulnerable hit_always of_inspired_action_chance strikethrough_vulnerable"
test "$(printf '%s\n' $retired_buff_combat_modifiers | wc -l)" -eq 38
retired_buff_modifier_inventory_source="$(sed -n '/public static final String\[\] RETIRED_NGE_BUFF_COMBAT_MODIFIERS/,/public static final java.text.NumberFormat/p' "$work_script/library/static_item.java")"
for retired_buff_combat_modifier in $retired_buff_combat_modifiers; do
    test "$(printf '%s\n' "$retired_buff_modifier_inventory_source" | grep -Fc "\"$retired_buff_combat_modifier\"")" -eq 1
    awk -F '\t' -v modifier="$retired_buff_combat_modifier" '$2 == "skill" && $3 == modifier { found++ } END { if (found != 1) exit 2 }' "$work_buff_effect_mapping"
done
test "$(awk -F '\t' '$2 == "skill" && $3 ~ /^freeshot_case_(miss|dodge|parry|crit|strikethrough)$/ { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 5
awk -F '\t' '$1 == "sp_preparation" { found++; if ($8 != "expertise_damage_all" || $10 != "freeshot_case_crit" || $12 != "freeshot_case_strikethrough") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
awk -F '\t' '$1 == "expertise_sp_equilibrium" { found++; if ($23 != "\"freeshot_case_miss=1,freeshot_case_dodge=1,freeshot_case_parry=1\"") exit 2 } END { if (found != 1) exit 3 }' "$work_skills_table"
spy_freeshot_source="$(sed -n '/public static int\[\] getSuccessBasedSingleTargetActionCost(/,/public static void setPersistCombatMode/p' "$work_combat_library")"
printf '%s\n' "$spy_freeshot_source" | awk '
/if \(actionData.precuHamCostModel > 0\)/ { precu = NR }
/if \(isPlayer\(attacker\)\)/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics\(attacker\)/ { cleanup = NR }
/return getActionCost\(attacker, weaponData, actionData\);/ && cleanup > 0 && earlyReturn == 0 { earlyReturn = NR }
/getEnhancedSkillStatisticModifierUncapped\(attacker, "freeshot_case_miss"\)/ { reader = NR }
END { if (!(precu > 0 && guard > precu && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
awk -F '\t' '
NR > 2 {
    matched = 0
    for (column = 8; column <= 16; column += 2) {
        if ($column == "critical_hit_vulnerable") { critical++; uses++; matched = 1 }
        else if ($column == "glancing_blow_vulnerable") { glancing++; uses++; matched = 1 }
        else if ($column == "strikethrough_vulnerable") { strikethrough++; uses++; matched = 1 }
    }
    if (matched) { rows++; names[$1] = 1 }
}
END {
    for (name in names) nameCount++
    if (rows != 64 || nameCount != 64 || uses != 66 || critical != 26 ||
        glancing != 39 || strikethrough != 1) exit 3
}' "$work_buff_table"
hit_table_glancing_source="$(sed -n '/public static float getAttackerGlancingReduction(/,/public static float getPunishingBlowChance/p' "$work_combat_library")"
printf '%s\n' "$hit_table_glancing_source" | awk '
/if \(isPlayer\(attacker\)\)/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics\(attacker\)/ { cleanup = NR }
/return 0[.]0f;/ { earlyReturn = NR }
/getEnhancedSkillStatisticModifierUncapped\(attacker, "glancing_blow_vulnerable"\)/ { reader = NR }
END { if (!(guard > 0 && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
hit_table_critical_source="$(sed -n '/public static float getDefenderCriticalChance(/,/public static float getStrikethroughChance/p' "$work_combat_library")"
printf '%s\n' "$hit_table_critical_source" | awk '
/if \(isPlayer\(defender\)\)/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics\(defender\)/ { cleanup = NR }
/return 0[.]0f;/ { earlyReturn = NR }
/getEnhancedSkillStatisticModifierUncapped\(defender, "critical_hit_vulnerable"\)/ { reader = NR }
END { if (!(guard > 0 && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
hit_table_strikethrough_source="$(sed -n '/public static float getDefenderStrikethroughReduction(/,/public static float getStrikethroughValue/p' "$work_combat_library")"
printf '%s\n' "$hit_table_strikethrough_source" | awk '
/if \(isPlayer\(player\)\)/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics\(player\)/ { cleanup = NR }
/return 0[.]0f;/ { earlyReturn = NR }
/getEnhancedSkillStatisticModifierUncapped\(player, "strikethrough_vulnerable"\)/ { reader = NR }
END { if (!(guard > 0 && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
lucky_break_buff_source="$(awk -F '\t' '$1 == "sm_lucky_break" { print }' "$work_buff_table")"
test "$(printf '%s\n' "$lucky_break_buff_source" | wc -l)" -eq 1
printf '%s\n' "$lucky_break_buff_source" | awk -F '\t' '$8 == "expertise_critical_niche_all" && $10 == "hit_always" && $12 == "crit_always" { found++ } END { if (found != 1) exit 2 }'
lucky_break_defender_source="$(sed -n '/public int getSingleTargetDefenderResult(/,/public int getSingleTargetAttackResult(/p' "$work_script/systems/combat/combat_base.java")"
lucky_break_attack_source="$(sed -n '/public int getSingleTargetAttackResult(/,/public void displayHitTable(/p' "$work_script/systems/combat/combat_base.java")"
printf '%s\n' "$lucky_break_defender_source" | awk '/isPlayer\(attacker\) \? 0/ { guard = NR } /getEnhancedSkillStatisticModifierUncapped\(attacker, "hit_always"\)/ { reader = NR } END { if (!(guard > 0 && reader > guard)) exit 2 }'
printf '%s\n' "$lucky_break_attack_source" | awk '/isPlayer\(attacker\) \? 0/ { guard = NR } /getEnhancedSkillStatisticModifierUncapped\(attacker, "crit_always"\)/ { reader = NR } END { if (!(guard > 0 && reader > guard)) exit 2 }'
awk -F '\t' '
$1 ~ /^set_bonus_jedi_dps_[123]$/ {
    found++
    matches = 0
    for (column = 8; column <= 16; column += 2)
        if ($column == "flurry_cooldown_modifier") matches++
    if (matches != 1) exit 2
    names[$1] = 1
}
END {
    for (name in names) nameCount++
    if (found != 3 || nameCount != 3) exit 3
}' "$work_buff_table"
awk -F '\t' '$1 == "set_bonus_officer_utility_b_3" { found++; if ($16 != "of_inspired_action_chance") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
awk -F '\t' '$1 == "of_inspired_action_chance" { found++; if ($2 != "officer_1a" || $3 != "officer" || $4 != 1) exit 2 } END { if (found != 1) exit 3 }' "$work_skill_mod_listing"
inspired_action_source="$(sed -n '/public void doInspiredAction(/,/public int of_last_words_recourse(/p' "$work_combat_actions")"
printf '%s\n' "$inspired_action_source" | awk '
/if \(isPlayer\(officer\)\)/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics\(officer\)/ { cleanup = NR }
/return;/ && cleanup > 0 && earlyReturn == 0 { earlyReturn = NR }
/getEnhancedSkillStatisticModifierUncapped\(officer, "of_inspired_action_chance"\)/ { reader = NR }
END { if (!(guard > 0 && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
test "$(awk -F '\t' '$2 == "skill" && $3 ~ /^combat_/ { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 37
test "$(awk -F '\t' '$2 == "skill" && ($3 == "combat_haste" || $3 == "combat_slow") { found++ } END { print found + 0 }' "$work_buff_effect_mapping")" -eq 2
test "$(awk -F '\t' 'NR > 2 && $1 != "" { found++ } END { print found + 0 }' "$work_buff_table")" -eq 1993
static_modifier_predicate_source="$(sed -n '/public static boolean isRetiredNgeStaticItemSkillModifier/,/public static void removeRetiredNgePlayerSkillStatistics/p' "$work_script/library/static_item.java")"
printf '%s\n' "$static_modifier_predicate_source" | grep -Fq 'RETIRED_NGE_BUFF_COMBAT_MODIFIERS'
parse_skill_modifiers_source="$(sed -n '/public static dictionary parseSkillModifiers/,/public static obj_id makeDynamicObject/p' "$work_script/library/static_item.java")"
printf '%s\n' "$parse_skill_modifiers_source" | grep -Fq 'if (!isRetiredNgeStaticItemSkillModifier(modsArray[0]))'
test "$(printf '%s\n' "$parse_skill_modifiers_source" | grep -Fn 'isRetiredNgeStaticItemSkillModifier' | head -n 1 | cut -d: -f1)" -lt "$(printf '%s\n' "$parse_skill_modifiers_source" | grep -Fn 'dict.put' | head -n 1 | cut -d: -f1)"
for static_parser_consumer in item/skillmod_click_item.java systems/sign/special_sign.java systems/tcg/tcg_vendor_contract.java; do
    grep -Fq 'static_item.parseSkillModifiers(player, skillMod)' "$work_script/$static_parser_consumer"
    grep -Fq 'applySkillStatisticModifier(player, skillModName, skillModValue)' "$work_script/$static_parser_consumer"
done
player_modifier_cleanup_source="$(sed -n '/public static void removeRetiredNgePlayerSkillStatistics/,/public static void removeRetiredNgeStaticItemSkillModifiers/p' "$work_script/library/static_item.java")"
printf '%s\n' "$player_modifier_cleanup_source" | grep -Fq 'getSkillStatModListingForPlayer(player)'
printf '%s\n' "$player_modifier_cleanup_source" | grep -Fq 'isRetiredNgeStaticItemSkillModifier(modifier)'
printf '%s\n' "$player_modifier_cleanup_source" | grep -Fq 'applySkillStatisticModifier(player, modifier, -currentValue)'
grep -Fq 'static_item.removeRetiredNgePlayerSkillStatistics(player);' "$work_buff_library"
collection_reward_source="$(sed -n '/public static boolean grantCollectionReward/,/public static boolean updateCraftingSlot/p' "$work_script/library/collection.java")"
printf '%s\n' "$collection_reward_source" | grep -Fq 'if (static_item.isRetiredNgeStaticItemSkillModifier(skillMod1))'
test "$(printf '%s\n' "$collection_reward_source" | grep -Fn 'isRetiredNgeStaticItemSkillModifier(skillMod1)' | head -n 1 | cut -d: -f1)" -lt "$(printf '%s\n' "$collection_reward_source" | grep -Fn 'applySkillStatisticModifier(player, skillMod1, skillModAmount)' | head -n 1 | cut -d: -f1)"
retired_collection_reward_specs="heroic_axkva_min_01:combat_parry_reduction heroic_tusken_king_01:combat_critical_hit_reduction heroic_ig88_01:combat_strikethrough_value heroic_star_destroyer_01:combat_block_reduction heroic_exar_kun_01:combat_evasion_chance"
test "$(printf '%s\n' $retired_collection_reward_specs | wc -l)" -eq 5
for retired_collection_reward_spec in $retired_collection_reward_specs; do
    retired_collection_name="${retired_collection_reward_spec%%:*}"
    retired_collection_modifier="${retired_collection_reward_spec##*:}"
    awk -F '\t' -v collection="$retired_collection_name" -v modifier="$retired_collection_modifier" '$1 == collection && $11 == modifier { found++ } END { if (found != 1) exit 2 }' "$work_collection_rewards"
done
grep -Fq 'if (static_item.isRetiredNgeStaticItemSkillModifier(skillMod))' "$work_player_utility"
grep -Fq 'if (!static_item.isRetiredNgeStaticItemSkillModifier(skillmod) &&' "$work_player_structure_library"
grep -Fq 'removeObjVar(structure, player_structure.SPECIAL_SIGN_DECREMENT_MOD);' "$work_player_structure_library"
buff_skill_predicate_source="$(sed -n '/public boolean isRetiredNgeBuffSkillModifier/,/public void retireNgeExpertiseModifier/p' "$work_buff_handler")"
printf '%s\n' "$buff_skill_predicate_source" | grep -Fq 'static_item.isRetiredNgeBuffSkillModifier(modifierName)'
for generic_buff_writer in skillAddBuffHandler skillPercentAddBuffHandler forcePowerAddBuffHandler; do
    generic_buff_writer_source="$(sed -n "/public int $generic_buff_writer/,/public int .*RemoveBuffHandler/p" "$work_buff_handler")"
    printf '%s\n' "$generic_buff_writer_source" | grep -Fq 'if (isPlayer(self) && isRetiredNgeBuffSkillModifier(subtype))'
    printf '%s\n' "$generic_buff_writer_source" | grep -Fq 'addSkillModModifier'
done
item_level_cleanup_source="$(sed -n '/public static void removeLegacyNgeItemCombatLevelRequirement(/,/public static int generateStatMod(/p' "$work_script/library/static_item.java")"
test "$(printf '%s\n' "$item_level_cleanup_source" | grep -Fc 'hasObjVar(item, "healing.combat_level_required")')" -eq 1
test "$(printf '%s\n' "$item_level_cleanup_source" | grep -Fc 'removeObjVar(item, "healing.combat_level_required")')" -eq 1
! printf '%s\n' "$item_level_cleanup_source" | grep -Fq 'removeObjVar(item, "healing")'
test "$(grep -Fc 'static_item.removeLegacyNgeItemCombatLevelRequirement(self);' "$work_script/item/medicine/stimpack.java")" -eq 4
test "$(grep -Fc 'static_item.removeLegacyNgeItemCombatLevelRequirement(self);' "$work_script/item/medicine/stimpack_crafted.java")" -eq 4
test "$(grep -Fc 'static_item.removeLegacyNgeItemCombatLevelRequirement(self);' "$work_script/item/plant/force_melon.java")" -eq 1
crafted_stim_source="$(cat "$work_script/item/medicine/stimpack_crafted.java")"
! printf '%s\n' "$crafted_stim_source" | grep -Fq 'buff.hasBuff(player, "recent_heal")'
! printf '%s\n' "$crafted_stim_source" | grep -Fq 'healing.useChannelHealItem'
test "$(printf '%s\n' "$crafted_stim_source" | grep -Fc 'healing.useHealDamageItem')" -eq 2
printf '%s\n' "$crafted_stim_source" | grep -Fq 'hasObjVar(self, "healing.pool")'
awk -F '\t' '$1 == "channel_heal_health" { found++; if ($2 != "channelHeal" || $3 != "health") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '$1 == "channel_healing" { found++; if ($7 != 12 || $8 != "channel_heal_health" || $9 != 0 || $30 != 1) exit 2 } END { if (found != 1) exit 3 }' "$work_buff_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_CHANNEL_HEAL_EFFECT = "channel_heal_health"' "$work_buff_library"
channel_heal_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerChannelHealBuff/,/public static void clearPostNgePlayerChannelHealState/p' "$work_buff_library")"
printf '%s\n' "$channel_heal_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$channel_heal_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$channel_heal_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerChannelHealEffect(getEffectParam(data, effect))'
channel_heal_state_cleanup_source="$(sed -n '/public static void clearPostNgePlayerChannelHealState/,/public static void retirePostNgePlayerChannelHealState/p' "$work_buff_library")"
printf '%s\n' "$channel_heal_state_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$channel_heal_state_cleanup_source" | grep -Fq 'utils.getIntScriptVar(player, "channelHeal.suiPid")'
printf '%s\n' "$channel_heal_state_cleanup_source" | grep -Fq 'getIntObjVar(player, sui.COUNTDOWNTIMER_SUI_VAR) == channelHealSuiPid'
printf '%s\n' "$channel_heal_state_cleanup_source" | grep -Fq 'utils.removeScriptVarTree(player, "channelHeal")'
printf '%s\n' "$channel_heal_state_cleanup_source" | grep -Fq 'if (ownsCountdown)'
printf '%s\n' "$channel_heal_state_cleanup_source" | grep -Fq 'forceCloseSUIPage(channelHealSuiPid)'
channel_heal_lifecycle_cleanup_source="$(sed -n '/public static void retirePostNgePlayerChannelHealState/,/public static boolean isRetiredPostNgePlayerRadarInvisibilityEffect/p' "$work_buff_library")"
printf '%s\n' "$channel_heal_lifecycle_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$channel_heal_lifecycle_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$channel_heal_lifecycle_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s\n' "$channel_heal_lifecycle_cleanup_source" | grep -Fq 'clearPostNgePlayerChannelHealState(player)'
grep -Fq 'retirePostNgePlayerChannelHealState(player);' "$work_buff_library"
channel_heal_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
channel_heal_admission_gate_line="$(printf '%s\n' "$channel_heal_admission_source" | grep -Fn 'isRetiredPostNgePlayerChannelHealBuff(target, bdata)' | head -1 | cut -d: -f1)"
channel_heal_existing_return_line="$(printf '%s\n' "$channel_heal_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$channel_heal_admission_gate_line" -lt "$channel_heal_existing_return_line"
channel_heal_adapter_source="$(sed -n '/public static boolean useChannelHealItem(obj_id user, obj_id item, int attrib)/,/public static boolean useHealPetItem/p' "$work_healing_library")"
channel_heal_adapter_guard_line="$(printf '%s\n' "$channel_heal_adapter_source" | grep -Fn 'if (isIdValid(user) && exists(user) && isPlayer(user))' | head -1 | cut -d: -f1)"
channel_heal_adapter_cleanup_line="$(printf '%s\n' "$channel_heal_adapter_source" | grep -Fn 'buff.retirePostNgePlayerChannelHealState(user);' | head -1 | cut -d: -f1)"
channel_heal_adapter_return_line="$(printf '%s\n' "$channel_heal_adapter_source" | grep -Fn 'return useHealDamageItem(user, item, attrib);' | head -1 | cut -d: -f1)"
channel_heal_adapter_message_line="$(printf '%s\n' "$channel_heal_adapter_source" | grep -Fn 'messageTo(user, "channelHeal"' | head -1 | cut -d: -f1)"
channel_heal_adapter_decrement_line="$(printf '%s\n' "$channel_heal_adapter_source" | grep -Fn 'decrementCount(item);' | head -1 | cut -d: -f1)"
test "$channel_heal_adapter_guard_line" -lt "$channel_heal_adapter_cleanup_line"
test "$channel_heal_adapter_cleanup_line" -lt "$channel_heal_adapter_return_line"
test "$channel_heal_adapter_return_line" -lt "$channel_heal_adapter_message_line"
test "$channel_heal_adapter_return_line" -lt "$channel_heal_adapter_decrement_line"
channel_heal_callback_source="$(sed -n '/public int channelHeal(obj_id self, dictionary params)/,/public int residentLinkFalse/p' "$work_player_utility")"
channel_heal_callback_guard_line="$(printf '%s\n' "$channel_heal_callback_source" | grep -Fn 'if (isPlayer(self) && buff.isPostNgeBuffProgressionRetired())' | head -1 | cut -d: -f1)"
channel_heal_callback_cleanup_line="$(printf '%s\n' "$channel_heal_callback_source" | grep -Fn 'buff.retirePostNgePlayerChannelHealState(self);' | head -1 | cut -d: -f1)"
channel_heal_callback_writer_line="$(printf '%s\n' "$channel_heal_callback_source" | grep -Fn 'healing.healDamage(self, self, attrib, healPerTick);' | head -1 | cut -d: -f1)"
channel_heal_callback_requeue_line="$(printf '%s\n' "$channel_heal_callback_source" | grep -Fn 'messageTo(self, "channelHeal"' | head -1 | cut -d: -f1)"
test "$channel_heal_callback_guard_line" -lt "$channel_heal_callback_cleanup_line"
test "$channel_heal_callback_cleanup_line" -lt "$channel_heal_callback_writer_line"
test "$channel_heal_callback_cleanup_line" -lt "$channel_heal_callback_requeue_line"
channel_heal_damage_source="$(sed -n '/public int OnCreatureDamaged/,/public int attribAddBuffHandler/p' "$work_buff_handler")"
channel_heal_add_source="$(sed -n '/public void channelHealAddBuffHandler/,/public void channelHealRemoveBuffHandler/p' "$work_buff_handler")"
channel_heal_remove_source="$(sed -n '/public void channelHealRemoveBuffHandler/,/public int getAttributeType/p' "$work_buff_handler")"
for channel_heal_handler_spec in damage:retirePostNgePlayerChannelHealState:hasBuff add:retirePostNgePlayerChannelHealState:useChannelHealItem remove:clearPostNgePlayerChannelHealState:getIntScriptVar; do
    channel_heal_handler_name="${channel_heal_handler_spec%%:*}"
    channel_heal_handler_fields="${channel_heal_handler_spec#*:}"
    channel_heal_handler_cleanup="${channel_heal_handler_fields%%:*}"
    channel_heal_handler_writer="${channel_heal_handler_fields##*:}"
    case "$channel_heal_handler_name" in
        damage) channel_heal_handler_source="$channel_heal_damage_source" ;;
        add) channel_heal_handler_source="$channel_heal_add_source" ;;
        remove) channel_heal_handler_source="$channel_heal_remove_source" ;;
        *) exit 1 ;;
    esac
    channel_heal_handler_guard_line="$(printf '%s\n' "$channel_heal_handler_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
    channel_heal_handler_cleanup_line="$(printf '%s\n' "$channel_heal_handler_source" | grep -Fn "$channel_heal_handler_cleanup" | head -1 | cut -d: -f1)"
    channel_heal_handler_writer_line="$(printf '%s\n' "$channel_heal_handler_source" | grep -Fn "$channel_heal_handler_writer" | head -1 | cut -d: -f1)"
    test "$channel_heal_handler_guard_line" -lt "$channel_heal_handler_cleanup_line"
    test "$channel_heal_handler_cleanup_line" -lt "$channel_heal_handler_writer_line"
    printf '%s\n' "$channel_heal_handler_source" | head -n "$channel_heal_handler_writer_line" | tail -n "+$channel_heal_handler_cleanup_line" | grep -Eq 'return( SCRIPT_CONTINUE)?;'
done
awk -F '\t' '$1 == "radar_invis" { found++; if ($2 != "radarInvis" || $3 != "radar_invis") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2)
        if ($parameterColumn == "radar_invis") ownsEffect = 1
    if (ownsEffect) {
        rows++
        seen[$1]++
        actual = $1 "|" $7 "|" $30 "|" $8 "|" $9 "|" $10 "|" $11 "|" $12 "|" $13 "|" $14 "|" $15 "|" $16 "|" $17
        if ($1 == "battlefield_radar_invisibility" && actual != "battlefield_radar_invisibility|900|1|radar_invis|0||0||0||0||0") exit 2
        if ($1 == "bh_take_cover" && actual != "bh_take_cover|40|1|expertise_glancing_blow_ranged|40|expertise_damage_all|10|radar_invis|0||0||0") exit 2
        if ($1 == "co_mirror_armor" && actual != "co_mirror_armor|120|1|radar_invis|0||0||0||0||0") exit 2
    }
}
END {
    if (rows != 3 || seen["battlefield_radar_invisibility"] != 1 || seen["bh_take_cover"] != 1 || seen["co_mirror_armor"] != 1) exit 3
}' "$work_buff_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_RADAR_INVISIBILITY_EFFECT = "radar_invis"' "$work_buff_library"
radar_invisibility_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerRadarInvisibilityEffect/,/public static boolean isRetiredPostNgePlayerRadarInvisibilityBuff/p' "$work_buff_library")"
printf '%s\n' "$radar_invisibility_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_RADAR_INVISIBILITY_EFFECT'
radar_invisibility_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerRadarInvisibilityBuff/,/public static void retirePostNgePlayerRadarInvisibilityState/p' "$work_buff_library")"
printf '%s\n' "$radar_invisibility_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$radar_invisibility_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$radar_invisibility_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerRadarInvisibilityEffect(getEffectParam(data, effect))'
radar_invisibility_cleanup_source="$(sed -n '/public static void retirePostNgePlayerRadarInvisibilityState/,/public static boolean isRetiredPostNgePlayerCooldownExecutionEffect/p' "$work_buff_library")"
printf '%s\n' "$radar_invisibility_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$radar_invisibility_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$radar_invisibility_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$radar_invisibility_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
radar_invisibility_owned_repair_line="$(printf '%s\n' "$radar_invisibility_cleanup_source" | grep -Fn 'if (removedOwnedRadarInvisibility)' | head -1 | cut -d: -f1)"
radar_invisibility_visibility_repair_line="$(printf '%s\n' "$radar_invisibility_cleanup_source" | grep -Fn 'setVisibleOnMapAndRadar(player, true);' | head -1 | cut -d: -f1)"
test "$radar_invisibility_owned_repair_line" -lt "$radar_invisibility_visibility_repair_line"
grep -Fq 'retirePostNgePlayerRadarInvisibilityState(player);' "$work_buff_library"
radar_invisibility_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
radar_invisibility_admission_gate_line="$(printf '%s\n' "$radar_invisibility_admission_source" | grep -Fn 'isRetiredPostNgePlayerRadarInvisibilityBuff(target, bdata)' | head -1 | cut -d: -f1)"
radar_invisibility_existing_return_line="$(printf '%s\n' "$radar_invisibility_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$radar_invisibility_admission_gate_line" -lt "$radar_invisibility_existing_return_line"
radar_invisibility_add_source="$(sed -n '/public int radarInvisAddBuffHandler/,/public int radarInvisRemoveBuffHandler/p' "$work_buff_handler")"
radar_invisibility_remove_source="$(sed -n '/public int radarInvisRemoveBuffHandler/,/public int onTargetAddBuffHandler/p' "$work_buff_handler")"
radar_invisibility_add_guard_line="$(printf '%s\n' "$radar_invisibility_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
radar_invisibility_add_repair_line="$(printf '%s\n' "$radar_invisibility_add_source" | grep -Fn 'setVisibleOnMapAndRadar(self, true);' | head -1 | cut -d: -f1)"
radar_invisibility_add_return_line="$(printf '%s\n' "$radar_invisibility_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
radar_invisibility_retained_hide_line="$(printf '%s\n' "$radar_invisibility_add_source" | grep -Fn 'setVisibleOnMapAndRadar(self, false);' | head -1 | cut -d: -f1)"
test "$radar_invisibility_add_guard_line" -lt "$radar_invisibility_add_repair_line"
test "$radar_invisibility_add_repair_line" -lt "$radar_invisibility_add_return_line"
test "$radar_invisibility_add_return_line" -lt "$radar_invisibility_retained_hide_line"
radar_invisibility_remove_guard_line="$(printf '%s\n' "$radar_invisibility_remove_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
radar_invisibility_remove_repair_line="$(printf '%s\n' "$radar_invisibility_remove_source" | grep -Fn 'setVisibleOnMapAndRadar(self, true);' | head -1 | cut -d: -f1)"
radar_invisibility_remove_return_line="$(printf '%s\n' "$radar_invisibility_remove_source" | grep -Fn 'return SCRIPT_CONTINUE;' | head -1 | cut -d: -f1)"
radar_invisibility_retained_restore_line="$(printf '%s\n' "$radar_invisibility_remove_source" | grep -Fn 'setVisibleOnMapAndRadar(self, true);' | tail -1 | cut -d: -f1)"
test "$radar_invisibility_remove_guard_line" -lt "$radar_invisibility_remove_repair_line"
test "$radar_invisibility_remove_repair_line" -lt "$radar_invisibility_remove_return_line"
test "$radar_invisibility_remove_return_line" -lt "$radar_invisibility_retained_restore_line"
awk -F '\t' '$1 == "cooldown_execute_all" { found++; if ($2 != "cooldownModify" || $3 != "cooldown_execute_all") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2)
        if ($parameterColumn == "cooldown_execute_all") ownsEffect = 1
    if (ownsEffect) {
        rows++
        seen[$1]++
        actual = $1 "|" $7 "|" $30 "|" $8 "|" $9 "|" $10 "|" $11 "|" $12 "|" $13 "|" $14 "|" $15 "|" $16 "|" $17
        if ($1 == "jedi_statue_dark_debuff_dark" && actual != "jedi_statue_dark_debuff_dark|30|1|cooldown_execute_all|12|expertise_damage_to_healing_fs_ae_dm_cc|100|private_armor_break|100|combat_parry_reduction|-150|expertise_block_chance|-15") exit 2
        if ($1 == "lelli_stun" && actual != "lelli_stun|15|1|cooldown_execute_all|15||0||0||0||0") exit 2
        if ($1 == "sp_fld_debuff_ca" && actual != "sp_fld_debuff_ca|3|1|cooldown_execute_all|3|stifle|3||0||0||0") exit 2
    }
}
END {
    if (rows != 3 || seen["jedi_statue_dark_debuff_dark"] != 1 || seen["lelli_stun"] != 1 || seen["sp_fld_debuff_ca"] != 1) exit 3
}' "$work_buff_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_COOLDOWN_EXECUTION_EFFECT = "cooldown_execute_all"' "$work_buff_library"
cooldown_execution_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCooldownExecutionEffect/,/public static boolean isRetiredPostNgePlayerCooldownExecutionBuff/p' "$work_buff_library")"
printf '%s\n' "$cooldown_execution_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_COOLDOWN_EXECUTION_EFFECT'
cooldown_execution_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCooldownExecutionBuff/,/public static void retirePostNgePlayerCooldownExecutionState/p' "$work_buff_library")"
printf '%s\n' "$cooldown_execution_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$cooldown_execution_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$cooldown_execution_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerCooldownExecutionEffect(getEffectParam(data, effect))'
cooldown_execution_cleanup_source="$(sed -n '/public static void retirePostNgePlayerCooldownExecutionState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
printf '%s\n' "$cooldown_execution_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$cooldown_execution_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$cooldown_execution_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$cooldown_execution_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerCooldownExecutionState(player);' "$work_buff_library"
cooldown_execution_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
cooldown_execution_admission_gate_line="$(printf '%s\n' "$cooldown_execution_admission_source" | grep -Fn 'isRetiredPostNgePlayerCooldownExecutionBuff(target, bdata)' | head -1 | cut -d: -f1)"
cooldown_execution_existing_return_line="$(printf '%s\n' "$cooldown_execution_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$cooldown_execution_admission_gate_line" -lt "$cooldown_execution_existing_return_line"
cooldown_execution_add_source="$(sed -n '/public int cooldownModifyAddBuffHandler/,/public int cooldownModifyRemoveBuffHandler/p' "$work_buff_handler")"
cooldown_execution_guard_line="$(printf '%s\n' "$cooldown_execution_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
cooldown_execution_return_line="$(printf '%s\n' "$cooldown_execution_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
cooldown_execution_retained_subtype_line="$(printf '%s\n' "$cooldown_execution_add_source" | grep -Fn 'subtype.equals("cooldown_execute_all")' | head -1 | cut -d: -f1)"
cooldown_execution_retained_writer_line="$(printf '%s\n' "$cooldown_execution_add_source" | grep -Fn 'sendCooldownGroupTimingOnly(self, groupCrc, value);' | head -1 | cut -d: -f1)"
test "$cooldown_execution_guard_line" -lt "$cooldown_execution_return_line"
test "$cooldown_execution_return_line" -lt "$cooldown_execution_retained_subtype_line"
test "$cooldown_execution_retained_subtype_line" -lt "$cooldown_execution_retained_writer_line"
awk -F '\t' '$1 == "saber_intercept" { found++; if ($2 != "saberIntercept" || $3 != "saber_intercept") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2)
        if ($parameterColumn == "saber_intercept") ownsEffect = 1
    if (ownsEffect) {
        rows++
        actual = $1 "|" $7 "|" $30 "|" $8 "|" $9
        if (actual != "fs_saber_intercept|10|1|saber_intercept|1") exit 2
    }
}
END { if (rows != 1) exit 3 }
' "$work_buff_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_SABER_INTERCEPT_EFFECT = "saber_intercept"' "$work_buff_library"
saber_intercept_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerSaberInterceptEffect/,/public static boolean isRetiredPostNgePlayerSaberInterceptBuff/p' "$work_buff_library")"
printf '%s\n' "$saber_intercept_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_SABER_INTERCEPT_EFFECT'
saber_intercept_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerSaberInterceptBuff/,/public static void retirePostNgePlayerSaberInterceptState/p' "$work_buff_library")"
printf '%s\n' "$saber_intercept_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$saber_intercept_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$saber_intercept_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerSaberInterceptEffect(getEffectParam(data, effect))'
saber_intercept_cleanup_source="$(sed -n '/public static void retirePostNgePlayerSaberInterceptState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
printf '%s\n' "$saber_intercept_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$saber_intercept_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$saber_intercept_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$saber_intercept_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerSaberInterceptState(player);' "$work_buff_library"
saber_intercept_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
saber_intercept_admission_gate_line="$(printf '%s\n' "$saber_intercept_admission_source" | grep -Fn 'isRetiredPostNgePlayerSaberInterceptBuff(target, bdata)' | head -1 | cut -d: -f1)"
saber_intercept_existing_return_line="$(printf '%s\n' "$saber_intercept_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$saber_intercept_admission_gate_line" -lt "$saber_intercept_existing_return_line"
saber_intercept_add_source="$(sed -n '/public int saberInterceptAddBuffHandler/,/public int saberInterceptRemoveBuffHandler/p' "$work_buff_handler")"
saber_intercept_guard_line="$(printf '%s\n' "$saber_intercept_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerSaberInterceptEffect(effectName))' | head -1 | cut -d: -f1)"
saber_intercept_return_line="$(printf '%s\n' "$saber_intercept_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
saber_intercept_retained_writer_line="$(printf '%s\n' "$saber_intercept_add_source" | grep -Fn 'utils.setScriptVar(self, combat.DAMAGE_REDIRECT, caster);' | head -1 | cut -d: -f1)"
test "$saber_intercept_guard_line" -lt "$saber_intercept_return_line"
test "$saber_intercept_return_line" -lt "$saber_intercept_retained_writer_line"
awk -F '\t' '
$1 == "protect_master" {
    foundProtect++
    if ($2 != "bodyguardDefender" || $3 != "protect_master") exit 2
}
$1 == "shield_master_pet" {
    foundPet++
    if ($2 != "bodyguardDefender" || $3 != "shield_master_pet") exit 2
}
$1 == "shield_master_player" {
    foundPlayer++
    if ($2 != "bodyguardMaster" || $3 != "shield_master_player") exit 2
}
END { if (foundProtect != 1 || foundPet != 1 || foundPlayer != 1) exit 3 }
' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 && ($1 == "bm_shield_master_pet" ||
    $1 == "bm_shield_master_player" || $1 == "bodyguard") {
    rows++
    actual = $1 "|" $7 "|" $8
    if (actual != "bm_shield_master_pet|12|shield_master_pet" &&
        actual != "bm_shield_master_player|12|shield_master_player" &&
        actual != "bodyguard|-1|protect_master") exit 2
}
END { if (rows != 3) exit 3 }
' "$work_buff_table"
test "$(grep -Ec '^        "(bm_shield_master_pet|bm_shield_master_player|bodyguard)"[,]?$' "$work_buff_library")" -eq 3
test "$(grep -Ec '^        "(protect_master|shield_master_pet|shield_master_player)"[,]?$' "$work_buff_library")" -eq 3
damage_redirect_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerDamageRedirectBuff(obj_id target/,/public static void clearPostNgePlayerDamageRedirectState/p' "$work_buff_library")"
printf '%s\n' "$damage_redirect_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$damage_redirect_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$damage_redirect_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerDamageRedirectEffect(getEffectParam(data, effect))'
damage_redirect_cleanup_source="$(sed -n '/public static void clearPostNgePlayerDamageRedirectState/,/private static final String RETIRED_POST_NGE_PLAYER_PISTOL_WHIP_CONTROL_EFFECT/p' "$work_buff_library")"
printf '%s\n' "$damage_redirect_cleanup_source" | grep -Fq 'utils.removeScriptVar(player, combat.DAMAGE_REDIRECT);'
printf '%s\n' "$damage_redirect_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$damage_redirect_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$damage_redirect_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerDamageRedirectState(player);' "$work_buff_library"
damage_redirect_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
damage_redirect_admission_gate_line="$(printf '%s\n' "$damage_redirect_admission_source" | grep -Fn 'isRetiredPostNgePlayerDamageRedirectBuff(target, bdata)' | head -1 | cut -d: -f1)"
damage_redirect_existing_return_line="$(printf '%s\n' "$damage_redirect_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$damage_redirect_admission_gate_line" -lt "$damage_redirect_existing_return_line"
bodyguard_defender_add_source="$(sed -n '/public int bodyguardDefenderAddBuffHandler/,/public int bodyguardDefenderRemoveBuffHandler/p' "$work_buff_handler")"
bodyguard_defender_remove_source="$(sed -n '/public int bodyguardDefenderRemoveBuffHandler/,/public int cooldownModifyAddBuffHandler/p' "$work_buff_handler")"
bodyguard_master_add_source="$(sed -n '/public int bodyguardMasterAddBuffHandler/,/public int bodyguardMasterRemoveBuffHandler/p' "$work_buff_handler")"
bodyguard_master_remove_source="$(sed -n '/public int bodyguardMasterRemoveBuffHandler/,/public int onNextAttackAddBuffHandler/p' "$work_buff_handler")"
for damage_redirect_handler_source in "$bodyguard_defender_add_source" "$bodyguard_defender_remove_source" "$bodyguard_master_add_source" "$bodyguard_master_remove_source"; do
    printf '%s\n' "$damage_redirect_handler_source" | grep -Fq 'isRetiredPostNgePlayerDamageRedirectEffect(effectName)'
    printf '%s\n' "$damage_redirect_handler_source" | grep -Fq 'isRetiredPostNgePlayerDamageRedirectBuffName(buffName)'
    printf '%s\n' "$damage_redirect_handler_source" | grep -Fq 'return SCRIPT_OVERRIDE;'
done
test "$(printf '%s\n%s\n' "$bodyguard_defender_add_source" "$bodyguard_defender_remove_source" | grep -Fc 'if (isPlayer(master))')" -eq 4
bodyguard_defender_return_line="$(printf '%s\n' "$bodyguard_defender_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
bodyguard_defender_writer_line="$(printf '%s\n' "$bodyguard_defender_add_source" | grep -Fn 'utils.setScriptVar(master, combat.DAMAGE_REDIRECT, self);' | head -1 | cut -d: -f1)"
test "$bodyguard_defender_return_line" -lt "$bodyguard_defender_writer_line"
damage_redirect_consumer_source="$(sed -n '/public static obj_id directDamageToDifferentTarget/,/public static float getMissChance/p' "$work_combat_library")"
damage_redirect_consumer_guard_line="$(printf '%s\n' "$damage_redirect_consumer_source" | grep -Fn 'if (isPlayer(defender))' | head -1 | cut -d: -f1)"
damage_redirect_consumer_cleanup_line="$(printf '%s\n' "$damage_redirect_consumer_source" | grep -Fn 'retirePostNgePlayerDamageRedirectState(defender);' | head -1 | cut -d: -f1)"
damage_redirect_consumer_return_line="$(printf '%s\n' "$damage_redirect_consumer_source" | grep -Fn 'return defender;' | head -1 | cut -d: -f1)"
damage_redirect_consumer_beast_line="$(printf '%s\n' "$damage_redirect_consumer_source" | grep -Fn 'if (buff.hasBuff(defender, "bm_shield_master_player"))' | head -1 | cut -d: -f1)"
damage_redirect_consumer_script_var_line="$(printf '%s\n' "$damage_redirect_consumer_source" | grep -Fn 'if (utils.hasScriptVar(defender, DAMAGE_REDIRECT))' | head -1 | cut -d: -f1)"
test "$damage_redirect_consumer_guard_line" -lt "$damage_redirect_consumer_cleanup_line"
test "$damage_redirect_consumer_cleanup_line" -lt "$damage_redirect_consumer_return_line"
test "$damage_redirect_consumer_return_line" -lt "$damage_redirect_consumer_beast_line"
test "$damage_redirect_consumer_beast_line" -lt "$damage_redirect_consumer_script_var_line"
awk -F '\t' '$1 == "sm_pistol_whip" { found++; if ($2 != "pistolWhip" || $3 != "sm_pistol_whip") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2)
        if ($parameterColumn == "sm_pistol_whip") ownsEffect = 1
    if (ownsEffect) {
        rows++
        actual = $1 "|" $7 "|" $23 "|" $30 "|" $8 "|" $9
        if (actual != "sm_pistol_whip|2|1|1|sm_pistol_whip|0") exit 2
    }
}
END { if (rows != 1) exit 3 }
' "$work_buff_table"
awk -F '\t' '
NR > 2 {
    ngeOwner = index($22, "sm_pistol_whip_1") > 0 ||
        index($23, "expertise_stun_line_sm_pistol_whip=") > 0 ||
        index($23, "expertise_buff_duration_line_sm_pistol_whip=") > 0
    if (ngeOwner) ngeRows++
    precuOwner = ($1 == "combat_pistol_support_01" && index($22, "pistolMeleeDefense1") > 0) ||
        ($1 == "combat_pistol_support_03" && index($22, "pistolMeleeDefense2") > 0)
    if (precuOwner) precuRows++
}
END { if (ngeRows != 5 || precuRows != 2) exit 3 }
' "$work_skills_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_PISTOL_WHIP_CONTROL_EFFECT = "sm_pistol_whip"' "$work_buff_library"
pistol_whip_control_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerPistolWhipControlEffect/,/public static boolean isRetiredPostNgePlayerPistolWhipControlBuff/p' "$work_buff_library")"
printf '%s\n' "$pistol_whip_control_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_PISTOL_WHIP_CONTROL_EFFECT'
pistol_whip_control_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerPistolWhipControlBuff/,/public static void retirePostNgePlayerPistolWhipControlState/p' "$work_buff_library")"
printf '%s\n' "$pistol_whip_control_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$pistol_whip_control_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$pistol_whip_control_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerPistolWhipControlEffect(getEffectParam(data, effect))'
pistol_whip_control_cleanup_source="$(sed -n '/public static void retirePostNgePlayerPistolWhipControlState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
printf '%s\n' "$pistol_whip_control_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$pistol_whip_control_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$pistol_whip_control_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$pistol_whip_control_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
grep -Fq 'retirePostNgePlayerPistolWhipControlState(player);' "$work_buff_library"
pistol_whip_control_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
pistol_whip_control_admission_gate_line="$(printf '%s\n' "$pistol_whip_control_admission_source" | grep -Fn 'isRetiredPostNgePlayerPistolWhipControlBuff(target, bdata)' | head -1 | cut -d: -f1)"
pistol_whip_control_existing_return_line="$(printf '%s\n' "$pistol_whip_control_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$pistol_whip_control_admission_gate_line" -lt "$pistol_whip_control_existing_return_line"
pistol_whip_control_add_source="$(sed -n '/public int pistolWhipAddBuffHandler/,/public int pistolWhipRemoveBuffHandler/p' "$work_buff_handler")"
pistol_whip_control_guard_line="$(printf '%s\n' "$pistol_whip_control_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerPistolWhipControlEffect(effectName))' | head -1 | cut -d: -f1)"
pistol_whip_control_return_line="$(printf '%s\n' "$pistol_whip_control_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
pistol_whip_control_expertise_line="$(printf '%s\n' "$pistol_whip_control_add_source" | grep -Fn 'getSkillStatisticModifier(caster, "expertise_stun_line_sm_pistol_whip")' | head -1 | cut -d: -f1)"
pistol_whip_control_retained_writer_line="$(printf '%s\n' "$pistol_whip_control_add_source" | grep -Fn 'movementAddBuffHandler(self, effectName, subtype, duration, value, buffName, caster);' | head -1 | cut -d: -f1)"
test "$pistol_whip_control_guard_line" -lt "$pistol_whip_control_return_line"
test "$pistol_whip_control_return_line" -lt "$pistol_whip_control_expertise_line"
test "$pistol_whip_control_expertise_line" -lt "$pistol_whip_control_retained_writer_line"
awk -F '\t' '
$1 == "expertise_sly_lie" { found++; if ($2 != "slyLie" || $3 != "expertise_sly_lie") exit 2 }
$1 == "expertise_fast_talk" { found++; if ($2 != "fastTalk" || $3 != "expertise_fast_talk") exit 2 }
END { if (found != 2) exit 3 }
' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2)
        if ($parameterColumn == "expertise_sly_lie" || $parameterColumn == "expertise_fast_talk") ownsEffect = 1
    if (ownsEffect) {
        rows++
        actual = $1 "|" $7 "|" $23 "|" $30 "|" $8 "|" $9
        expected = $1 == "sm_sly_lie" ? "sm_sly_lie|600|0|1|expertise_sly_lie|0" : ($1 == "sm_fast_talk" ? "sm_fast_talk|600|0|1|expertise_fast_talk|0" : "")
        if (actual != expected) exit 2
    }
}
END { if (rows != 2) exit 3 }
' "$work_buff_table"
awk -F '\t' '
NR > 2 {
    ngeOwner = index($22, "sm_sly_lie") > 0 || index($22, "sm_fast_talk") > 0 ||
        index($23, "expertise_half_truth=") > 0 || index($23, "expertise_innocent_cargo=") > 0 ||
        index($23, "expertise_fake_id=") > 0 || index($23, "expertise_sly_lie_bonus=") > 0 ||
        index($23, "expertise_sly_lie_rank=") > 0 || index($23, "expertise_fast_talk_bonus=") > 0 ||
        index($23, "expertise_fast_talk_rank=") > 0
    if (ngeOwner) ngeRows++
    precuOwner = ($1 == "combat_smuggler_novice" && index($22, "slice_containers") > 0) ||
        ($1 == "combat_smuggler_slicing_01" && index($22, "slice_terminals") > 0) ||
        ($1 == "combat_smuggler_slicing_02" && index($22, "slice_weaponsbasic") > 0) ||
        ($1 == "combat_smuggler_slicing_03" && index($22, "slice_armor") > 0) ||
        ($1 == "combat_smuggler_slicing_04" && index($22, "slice_weaponsadvanced") > 0) ||
        ($1 == "combat_smuggler_combat_01" && index($22, "feignDeath") > 0) ||
        ($1 == "combat_smuggler_combat_02" && index($22, "panicShot") > 0) ||
        ($1 == "combat_smuggler_combat_03" && index($22, "lowBlow") > 0) ||
        ($1 == "combat_smuggler_combat_04" && index($22, "lastDitch") > 0)
    if (precuOwner) precuRows++
}
END { if (ngeRows != 2 || precuRows != 9) exit 3 }
' "$work_skills_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_SMUGGLER_TRICK_EFFECTS' "$work_buff_library"
grep -Fq '"expertise_sly_lie"' "$work_buff_library"
grep -Fq '"expertise_fast_talk"' "$work_buff_library"
smuggler_trick_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerSmugglerTrickEffect/,/public static boolean isRetiredPostNgePlayerSmugglerTrickBuff/p' "$work_buff_library")"
printf '%s\n' "$smuggler_trick_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_SMUGGLER_TRICK_EFFECTS'
smuggler_trick_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerSmugglerTrickBuff/,/public static void clearPostNgePlayerSmugglerTrickModifiers/p' "$work_buff_library")"
printf '%s\n' "$smuggler_trick_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$smuggler_trick_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$smuggler_trick_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerSmugglerTrickEffect(getEffectParam(data, effect))'
smuggler_trick_modifier_cleanup_source="$(sed -n '/public static void clearPostNgePlayerSmugglerTrickModifiers/,/public static void retirePostNgePlayerSmugglerTrickState/p' "$work_buff_library")"
for smuggler_trick_modifier in slyLieDodge innocentCargoStrikethrough fastTalkAgility; do
    printf '%s\n' "$smuggler_trick_modifier_cleanup_source" | grep -Fq "$smuggler_trick_modifier"
done
printf '%s\n' "$smuggler_trick_modifier_cleanup_source" | grep -Fq 'removeAttribOrSkillModModifier'
smuggler_trick_state_cleanup_source="$(sed -n '/public static void retirePostNgePlayerSmugglerTrickState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
printf '%s\n' "$smuggler_trick_state_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$smuggler_trick_state_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$smuggler_trick_state_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$smuggler_trick_state_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s\n' "$smuggler_trick_state_cleanup_source" | grep -Fq 'clearPostNgePlayerSmugglerTrickModifiers(player);'
grep -Fq 'retirePostNgePlayerSmugglerTrickState(player);' "$work_buff_library"
smuggler_trick_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
smuggler_trick_admission_gate_line="$(printf '%s\n' "$smuggler_trick_admission_source" | grep -Fn 'isRetiredPostNgePlayerSmugglerTrickBuff(target, bdata)' | head -1 | cut -d: -f1)"
smuggler_trick_existing_return_line="$(printf '%s\n' "$smuggler_trick_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$smuggler_trick_admission_gate_line" -lt "$smuggler_trick_existing_return_line"
for smuggler_trick_handler in slyLie fastTalk; do
    smuggler_trick_add_source="$(sed -n "/public int ${smuggler_trick_handler}AddBuffHandler/,/public int ${smuggler_trick_handler}RemoveBuffHandler/p" "$work_buff_handler")"
    smuggler_trick_guard_line="$(printf '%s\n' "$smuggler_trick_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerSmugglerTrickEffect(effectName))' | head -1 | cut -d: -f1)"
    smuggler_trick_cleanup_line="$(printf '%s\n' "$smuggler_trick_add_source" | grep -Fn 'buff.clearPostNgePlayerSmugglerTrickModifiers(self);' | head -1 | cut -d: -f1)"
    smuggler_trick_return_line="$(printf '%s\n' "$smuggler_trick_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
    smuggler_trick_expertise_line="$(printf '%s\n' "$smuggler_trick_add_source" | grep -Fn 'getSkillStatisticModifier' | head -1 | cut -d: -f1)"
    smuggler_trick_writer_line="$(printf '%s\n' "$smuggler_trick_add_source" | grep -Fn 'skillAddBuffHandler' | head -1 | cut -d: -f1)"
    test "$smuggler_trick_guard_line" -lt "$smuggler_trick_cleanup_line"
    test "$smuggler_trick_cleanup_line" -lt "$smuggler_trick_return_line"
    test "$smuggler_trick_return_line" -lt "$smuggler_trick_expertise_line"
    test "$smuggler_trick_expertise_line" -lt "$smuggler_trick_writer_line"
done
awk -F '\t' '
$2 == "aggroChannel" {
    found++
    if ($1 == "aggro_channel_self" && $3 == "self") selfRows++
    if ($1 == "aggro_channel_target" && $3 == "target") targetRows++
}
END { if (found != 2 || selfRows != 1 || targetRows != 1) exit 3 }
' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 {
    ownsEffect = 0
    for (parameterColumn = 8; parameterColumn <= 16; parameterColumn += 2)
        if ($parameterColumn == "aggro_channel_self" || $parameterColumn == "aggro_channel_target") ownsEffect = 1
    if (ownsEffect) {
        rows++
        if (($1 != "aggroChannelTarget" && $1 != "aggroChannelself") ||
            $2 != "of_aggro_channel" || $7 != -1 || $30 != 1) exit 2
    }
}
END { if (rows != 2) exit 3 }
' "$work_buff_table"
awk -F '\t' '
NR > 2 && $1 ~ /^expertise_of_aggro_channel_[123]$/ {
    rows++
    if (index($23, "expertise_aggro_channel=") == 0) exit 2
    if (index($22, "of_aggro_channel") > 0) commandOwners++
}
END { if (rows != 3 || commandOwners != 1) exit 3 }
' "$work_skills_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_AGGRO_CHANNEL_EFFECTS' "$work_buff_library"
grep -Fq '"aggro_channel_self"' "$work_buff_library"
grep -Fq '"aggro_channel_target"' "$work_buff_library"
aggro_channel_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerAggroChannelEffect/,/public static boolean isRetiredPostNgePlayerAggroChannelBuff/p' "$work_buff_library")"
printf '%s\n' "$aggro_channel_effect_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_AGGRO_CHANNEL_EFFECTS'
aggro_channel_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerAggroChannelBuff/,/public static void retirePostNgePlayerAggroChannelState/p' "$work_buff_library")"
printf '%s\n' "$aggro_channel_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$aggro_channel_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$aggro_channel_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerAggroChannelEffect(getEffectParam(data, effect))'
aggro_channel_state_cleanup_source="$(sed -n '/public static void retirePostNgePlayerAggroChannelState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
printf '%s\n' "$aggro_channel_state_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$aggro_channel_state_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$aggro_channel_state_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$aggro_channel_state_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s\n' "$aggro_channel_state_cleanup_source" | grep -Fq 'utils.removeScriptVar(player, AGGRO_TRANSFER_TO);'
grep -Fq 'retirePostNgePlayerAggroChannelState(player);' "$work_buff_library"
aggro_channel_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
aggro_channel_admission_gate_line="$(printf '%s\n' "$aggro_channel_admission_source" | grep -Fn 'isRetiredPostNgePlayerAggroChannelBuff(target, bdata)' | head -1 | cut -d: -f1)"
aggro_channel_existing_return_line="$(printf '%s\n' "$aggro_channel_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$aggro_channel_admission_gate_line" -lt "$aggro_channel_existing_return_line"
aggro_channel_add_source="$(sed -n '/public int aggroChannelAddBuffHandler/,/public int aggroChannelRemoveBuffHandler/p' "$work_buff_handler")"
aggro_channel_guard_line="$(printf '%s\n' "$aggro_channel_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerAggroChannelEffect(effectName))' | head -1 | cut -d: -f1)"
aggro_channel_cleanup_line="$(printf '%s\n' "$aggro_channel_add_source" | grep -Fn 'buff.retirePostNgePlayerAggroChannelState(self);' | head -1 | cut -d: -f1)"
aggro_channel_return_line="$(printf '%s\n' "$aggro_channel_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
aggro_channel_caster_check_line="$(printf '%s\n' "$aggro_channel_add_source" | grep -Fn 'if (!exists(caster) || !isIdValid(caster))' | head -1 | cut -d: -f1)"
aggro_channel_apply_line="$(printf '%s\n' "$aggro_channel_add_source" | grep -Fn 'buff.applyBuff(caster, self, "aggroChannelself");' | head -1 | cut -d: -f1)"
aggro_channel_script_var_line="$(printf '%s\n' "$aggro_channel_add_source" | grep -Fn 'utils.setScriptVar(self, buff.AGGRO_TRANSFER_TO, caster);' | head -1 | cut -d: -f1)"
test "$aggro_channel_guard_line" -lt "$aggro_channel_cleanup_line"
test "$aggro_channel_cleanup_line" -lt "$aggro_channel_return_line"
test "$aggro_channel_return_line" -lt "$aggro_channel_caster_check_line"
test "$aggro_channel_caster_check_line" -lt "$aggro_channel_apply_line"
test "$aggro_channel_apply_line" -lt "$aggro_channel_script_var_line"
aggro_channel_hate_source="$(sed -n '/public static void addHateProcess/,/public static boolean canSee/p' "$work_combat_library")"
aggro_channel_consumer_cleanup_line="$(printf '%s\n' "$aggro_channel_hate_source" | grep -Fn 'buff.retirePostNgePlayerAggroChannelState(attacker);' | head -1 | cut -d: -f1)"
aggro_channel_consumer_expertise_line="$(printf '%s\n' "$aggro_channel_hate_source" | grep -Fn 'getEnhancedSkillStatisticModifier(attacker, "expertise_aggro_channel")' | head -1 | cut -d: -f1)"
aggro_channel_consumer_transfer_line="$(printf '%s\n' "$aggro_channel_hate_source" | grep -Fn 'addHate(defender, transferTo, hateTransfered);' | head -1 | cut -d: -f1)"
printf '%s\n' "$aggro_channel_hate_source" | grep -Fq 'if (isPlayer(attacker) &&'
printf '%s\n' "$aggro_channel_hate_source" | grep -Fq 'utils.hasScriptVar(attacker, buff.AGGRO_TRANSFER_TO)'
test "$aggro_channel_consumer_cleanup_line" -lt "$aggro_channel_consumer_expertise_line"
test "$aggro_channel_consumer_expertise_line" -lt "$aggro_channel_consumer_transfer_line"
commando_deferred_actions='kill_meter_co_it_burns_proc kill_meter_co_armor_splash_proc kill_meter_co_youll_regret_that_reac expertise_co_burst_fire_proc'
for commando_deferred_action in $commando_deferred_actions; do
    test "$(awk -F '\t' -v name="$commando_deferred_action" 'NR > 2 && $1 == name { found++; if ($4 != name) exit 2 } END { print found + 0 }' "$work_command_table")" -eq 1
    test "$(awk -F '\t' -v name="$commando_deferred_action" 'NR > 2 && $1 == name { found++ } END { print found + 0 }' "$work_combat_data")" -eq 1
    grep -Fq "public int $commando_deferred_action(" "$work_combat_actions"
done
test "$(grep -Ec '^    public int (kill_meter_co_(it_burns_proc|armor_splash_proc|youll_regret_that_reac)|expertise_co_burst_fire_proc)\(' "$work_combat_actions")" -eq 4
awk -F '\t' '$1 == "kill_meter_co_youll_regret_that_reac" { found++; if ($68 != "co_youll_regret_that") exit 2 } END { if (found != 1) exit 3 }' "$work_combat_data"
awk -F '\t' '$1 == "commando_snare_bonus" { found++; if ($2 != "commandoSnareBonus" || $3 != "commando_snare_bonus") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
awk -F '\t' '
NR > 2 && $8 == "commando_snare_bonus" {
    found++
    if ($1 != "co_youll_regret_that" || $2 != "youll_regret_that" || $7 != 30 || $30 != 1) exit 2
}
END { if (found != 1) exit 3 }
' "$work_buff_table"
awk -F '\t' '
NR > 2 && $1 ~ /^expertise_co_youll_regret_that_[1-4]$/ {
    found++
    if (index($23, "expertise_youll_regret_that=1000") == 0) exit 2
    if ($1 == "expertise_co_youll_regret_that_1" &&
        index($23, "kill_meter_co_youll_regret_that_reac=100") == 0) exit 2
}
END { if (found != 4) exit 3 }
' "$work_skills_table"
commando_player_action_source="$(sed -n '/public static boolean isRetiredPostNgeCommandoPlayerAction/,/public static boolean isRetiredPostNgeMedicPlayerAction/p' "$work_combat_base")"
printf '%s\n' "$commando_player_action_source" | grep -Fq 'actionName.startsWith("co_")'
printf '%s\n' "$commando_player_action_source" | grep -Fq 'actionName.startsWith("kill_meter_co_")'
printf '%s\n' "$commando_player_action_source" | grep -Fq 'actionName.startsWith("expertise_co_")'
printf '%s\n' "$commando_player_action_source" | grep -Fq 'actionName.equals("banner_buff_commando")'
grep -Fq 'RETIRED_POST_NGE_PLAYER_COMMANDO_SNARE_ARMOR_EFFECT = "commando_snare_bonus"' "$work_buff_library"
grep -Fq 'RETIRED_POST_NGE_PLAYER_COMMANDO_SNARE_ARMOR_MODIFIER = "commandoInnateArmorBonus"' "$work_buff_library"
commando_snare_armor_effect_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCommandoSnareArmorEffect/,/public static boolean isRetiredPostNgePlayerCommandoSnareArmorBuff/p' "$work_buff_library")"
printf '%s\n' "$commando_snare_armor_effect_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_COMMANDO_SNARE_ARMOR_EFFECT'
commando_snare_armor_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCommandoSnareArmorBuff/,/public static void clearPostNgePlayerCommandoSnareArmorModifier/p' "$work_buff_library")"
printf '%s\n' "$commando_snare_armor_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$commando_snare_armor_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$commando_snare_armor_predicate_source" | grep -Fq 'isRetiredPostNgePlayerCommandoSnareArmorEffect(getEffectParam(data, effect))'
commando_snare_armor_modifier_cleanup_source="$(sed -n '/public static void clearPostNgePlayerCommandoSnareArmorModifier/,/public static void retirePostNgePlayerCommandoSnareArmorState/p' "$work_buff_library")"
printf '%s\n' "$commando_snare_armor_modifier_cleanup_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$commando_snare_armor_modifier_cleanup_source" | grep -Fq 'hasSkillModModifier'
printf '%s\n' "$commando_snare_armor_modifier_cleanup_source" | grep -Fq 'removeAttribOrSkillModModifier'
printf '%s\n' "$commando_snare_armor_modifier_cleanup_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_COMMANDO_SNARE_ARMOR_MODIFIER'
commando_snare_armor_state_cleanup_source="$(sed -n '/public static void retirePostNgePlayerCommandoSnareArmorState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
printf '%s\n' "$commando_snare_armor_state_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$commando_snare_armor_state_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$commando_snare_armor_state_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s\n' "$commando_snare_armor_state_cleanup_source" | grep -Fq 'clearPostNgePlayerCommandoSnareArmorModifier(player);'
grep -Fq 'retirePostNgePlayerCommandoSnareArmorState(player);' "$work_buff_library"
commando_snare_armor_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
commando_snare_armor_admission_line="$(printf '%s\n' "$commando_snare_armor_admission_source" | grep -Fn 'isRetiredPostNgePlayerCommandoSnareArmorBuff(target, bdata)' | head -1 | cut -d: -f1)"
commando_snare_armor_existing_line="$(printf '%s\n' "$commando_snare_armor_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test "$commando_snare_armor_admission_line" -lt "$commando_snare_armor_existing_line"
commando_snare_armor_add_source="$(sed -n '/public int commandoSnareBonusAddBuffHandler/,/public int commandoSnareBonusRemoveBuffHandler/p' "$work_buff_handler")"
commando_snare_armor_validity_line="$(printf '%s\n' "$commando_snare_armor_add_source" | grep -Fn 'if (!isIdValid(self))' | head -1 | cut -d: -f1)"
commando_snare_armor_guard_line="$(printf '%s\n' "$commando_snare_armor_add_source" | grep -Fn 'if (isPlayer(self) && buff.isRetiredPostNgePlayerCommandoSnareArmorEffect(effectName))' | head -1 | cut -d: -f1)"
commando_snare_armor_cleanup_line="$(printf '%s\n' "$commando_snare_armor_add_source" | grep -Fn 'buff.retirePostNgePlayerCommandoSnareArmorState(self);' | head -1 | cut -d: -f1)"
commando_snare_armor_return_line="$(printf '%s\n' "$commando_snare_armor_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | awk -F: -v cleanup="$commando_snare_armor_cleanup_line" '$1 > cleanup { print $1; exit }')"
commando_snare_armor_movement_line="$(printf '%s\n' "$commando_snare_armor_add_source" | grep -Fn 'movement.getAllModifiers(self)' | head -1 | cut -d: -f1)"
commando_snare_armor_expertise_line="$(printf '%s\n' "$commando_snare_armor_add_source" | grep -Fn 'getSkillStatisticModifier(self, "expertise_youll_regret_that")' | head -1 | cut -d: -f1)"
commando_snare_armor_writer_line="$(printf '%s\n' "$commando_snare_armor_add_source" | grep -Fn 'skillAddBuffHandler(self, "commandoInnateArmorBonus", "expertise_innate_protection_all"' | head -1 | cut -d: -f1)"
test "$commando_snare_armor_validity_line" -lt "$commando_snare_armor_guard_line"
test "$commando_snare_armor_guard_line" -lt "$commando_snare_armor_cleanup_line"
test "$commando_snare_armor_cleanup_line" -lt "$commando_snare_armor_return_line"
test "$commando_snare_armor_return_line" -lt "$commando_snare_armor_movement_line"
test "$commando_snare_armor_movement_line" -lt "$commando_snare_armor_expertise_line"
test "$commando_snare_armor_expertise_line" -lt "$commando_snare_armor_writer_line"
commando_snare_armor_remove_source="$(sed -n '/public int commandoSnareBonusRemoveBuffHandler/,/public int commandoFlashBangAddBuffHandler/p' "$work_buff_handler")"
printf '%s\n' "$commando_snare_armor_remove_source" | grep -Fq 'removeAttribOrSkillModModifier(self, "commandoInnateArmorBonus")'
printf '%s\n' "$commando_snare_armor_remove_source" | grep -Fq 'messageTo(self, "recalcArmor"'
awk -F '\t' '
BEGIN {
    expected["expertise_flash_bang"] = "commandoFlashBang|expertise_flash_bang"
    expected["expertise_muscle_spasm"] = "commandoMuscleSpasm|expertise_muscle_spasm"
    expected["expertise_on_target"] = "onTarget|expertise_on_target"
    expected["expertise_riddle_armor"] = "commandoRiddleArmor|expertise_riddle_armor"
}
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && ($(fieldIndex["NAME"]) in expected) {
    found++
    signature = $(fieldIndex["TYPE"]) "|" $(fieldIndex["SUBTYPE"])
    if (signature != expected[$(fieldIndex["NAME"])]) exit 2
}
END { if (found != 4) exit 3 }
' "$work_buff_effect_mapping"
awk -F '\t' '
BEGIN {
    expected["co_armor_cracker"] = "playerArmorReduce|15|1|1|expertise_riddle_armor|0||0||0||0||0"
    expected["co_base_of_operations"] = "base_of_operations|600|0|0|group|0|expertise_innate_protection_all|1000|expertise_critical_niche_all|5||0||0"
    expected["co_flash_bang"] = "flash_bang|30|1|1|expertise_flash_bang|0||0||0||0||0"
    expected["co_muscle_spasm"] = "muscle_spasm|10|1|1|expertise_muscle_spasm|0||0||0||0||0"
    expected["co_pos_sec_action_1"] = "co_pos_sec_action|-1|0|1|expertise_action_all|10||0||0||0||0"
    expected["co_pos_sec_action_2"] = "co_pos_sec_action|-1|0|1|expertise_action_all|20||0||0||0||0"
    expected["co_pos_sec_action_3"] = "co_pos_sec_action|-1|0|1|expertise_action_all|30||0||0||0||0"
    expected["co_pos_sec_critical_1"] = "co_pos_sec_critical|-1|0|1|expertise_critical_hit_reduction|5|expertise_critical_niche_all|2||0||0||0"
    expected["co_pos_sec_critical_2"] = "co_pos_sec_critical|-1|0|1|expertise_critical_hit_reduction|10|expertise_critical_niche_all|4||0||0||0"
    expected["co_pos_sec_critical_3"] = "co_pos_sec_critical|-1|0|1|expertise_critical_hit_reduction|15|expertise_critical_niche_all|6||0||0||0"
    expected["co_pos_sec_critical_4"] = "co_pos_sec_critical|-1|0|1|expertise_critical_hit_reduction|20|expertise_critical_niche_all|8||0||0||0"
    expected["co_pos_sec_proc_1"] = "co_pos_sec_proc|-1|0|1|expertise_co_burst_fire_proc|10|expertise_devastation_bonus|50||0||0||0"
    expected["co_pos_sec_proc_2"] = "co_pos_sec_proc|-1|0|1|expertise_co_burst_fire_proc|20|expertise_devastation_bonus|100||0||0||0"
    expected["co_position_secured"] = "position_secured|600|0|0|precision_modified|200|strength_modified|200|movement|0|expertise_on_target|0||0"
    expected["co_riddle_armor"] = "playerArmorReduce|15|1|1|expertise_riddle_armor|0||0||0||0||0"
    expected["grenadier_kinetic"] = "krix_grenadier_kinetic|15|1|1|expertise_riddle_armor|-2250||0||0||0||0"
}
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && ($(fieldIndex["NAME"]) in expected) {
    found++
    signature = $(fieldIndex["GROUP1"]) "|" $(fieldIndex["DURATION"]) "|" \
        $(fieldIndex["DEBUFF"]) "|" $(fieldIndex["IS_PERSISTENT"]) "|" \
        $(fieldIndex["EFFECT1_PARAM"]) "|" $(fieldIndex["EFFECT1_VALUE"]) "|" \
        $(fieldIndex["EFFECT2_PARAM"]) "|" $(fieldIndex["EFFECT2_VALUE"]) "|" \
        $(fieldIndex["EFFECT3_PARAM"]) "|" $(fieldIndex["EFFECT3_VALUE"]) "|" \
        $(fieldIndex["EFFECT4_PARAM"]) "|" $(fieldIndex["EFFECT4_VALUE"]) "|" \
        $(fieldIndex["EFFECT5_PARAM"]) "|" $(fieldIndex["EFFECT5_VALUE"])
    if (signature != expected[$(fieldIndex["NAME"])]) exit 2
}
END { if (found != 16) exit 3 }
' "$work_buff_table"
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && $(fieldIndex["commandName"]) ~ /^(co_armor_cracker|co_position_secured|co_riddle_armor)$/ {
    found++
    if ($(fieldIndex["scriptHook"]) != $(fieldIndex["commandName"])) exit 2
}
END { if (found != 3) exit 3 }
' "$work_command_table"
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && $(fieldIndex["actionName"]) ~ /^(co_armor_cracker|co_base_of_operations|co_position_secured|co_riddle_armor)$/ { found++ }
END { if (found != 4) exit 3 }
' "$work_combat_data"
awk -F '\t' '
NR > 2 && $1 ~ /^expertise_co_(position_secured_1|imp_position_secured_[1-3]|burst_fire_[1-2]|on_target_[1-4]|base_of_operations_1|flashbang_[1-2]|riddle_armor_1|imp_riddle_armor_[1-2]|armor_cracker_1)$/ { found++ }
END { if (found != 17) exit 3 }
' "$work_skills_table"
awk -F '\t' '
NR > 2 && $1 ~ /^(expertise_co_flash_bang|expertise_co_muscle_spasm|expertise_riddle_armor)$/ { found++ }
END { if (found != 3) exit 3 }
' "$work_skill_mod_listing"
commando_specialized_effect_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_COMMANDO_SPECIALIZED_EFFECTS/,/};/p' "$work_buff_library")"
test "$(printf '%s\n' "$commando_specialized_effect_inventory_source" | grep -Ec '^[[:space:]]*"[A-Za-z0-9_]+",?[[:space:]]*$')" -eq 4
for commando_specialized_effect in expertise_flash_bang expertise_muscle_spasm expertise_riddle_armor expertise_on_target; do
    printf '%s\n' "$commando_specialized_effect_inventory_source" | grep -Fq "\"$commando_specialized_effect\""
done
commando_specialized_buff_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_COMMANDO_SPECIALIZED_BUFFS/,/};/p' "$work_buff_library")"
test "$(printf '%s\n' "$commando_specialized_buff_inventory_source" | grep -Ec '^[[:space:]]*"[A-Za-z0-9_]+",?[[:space:]]*$')" -eq 16
for commando_specialized_buff in co_flash_bang co_muscle_spasm co_riddle_armor co_armor_cracker grenadier_kinetic co_position_secured co_pos_sec_action_1 co_pos_sec_action_2 co_pos_sec_action_3 co_pos_sec_proc_1 co_pos_sec_proc_2 co_pos_sec_critical_1 co_pos_sec_critical_2 co_pos_sec_critical_3 co_pos_sec_critical_4 co_base_of_operations; do
    printf '%s\n' "$commando_specialized_buff_inventory_source" | grep -Fq "\"$commando_specialized_buff\""
done
commando_specialized_modifier_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_COMMANDO_SPECIALIZED_MODIFIERS/,/};/p' "$work_buff_library")"
test "$(printf '%s\n' "$commando_specialized_modifier_inventory_source" | grep -Ec '^[[:space:]]*"[A-Za-z0-9_]+",?[[:space:]]*$')" -eq 21
for commando_specialized_modifier in commandoFlashBang commandoMuscleSpasm precision_modified strength_modified glancing_blow_vulnerable expertise_riddle_armor expertise_innate_protection_all expertise_critical_hit_reduction expertise_critical_niche_all expertise_co_burst_fire_proc expertise_devastation_bonus expertise_action_all expertise_co_flash_bang expertise_co_muscle_spasm expertise_action_line_co_imp_pos_sec expertise_co_pos_secured_line_armor expertise_co_pos_secured_line_boo_critical expertise_co_pos_secured_line_burst_fire_devastation_bonus expertise_co_pos_secured_line_burst_fire_proc expertise_co_pos_secured_line_critical expertise_co_pos_secured_line_protection; do
    printf '%s\n' "$commando_specialized_modifier_inventory_source" | grep -Fq "\"$commando_specialized_modifier\""
done
commando_specialized_effect_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCommandoSpecializedEffect/,/public static boolean isRetiredPostNgePlayerCommandoSpecializedBuffName/p' "$work_buff_library")"
printf '%s\n' "$commando_specialized_effect_source" | grep -Fq 'effectName.equals(retiredEffect)'
printf '%s\n' "$commando_specialized_effect_source" | grep -Fq 'effectName.startsWith(retiredEffect + "_")'
commando_specialized_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerCommandoSpecializedBuff(obj_id target/,/public static void clearPostNgePlayerCommandoSpecializedModifiers/p' "$work_buff_library")"
printf '%s\n' "$commando_specialized_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$commando_specialized_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerCommandoSpecializedBuffName(data.buffName)'
printf '%s\n' "$commando_specialized_buff_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$commando_specialized_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerCommandoSpecializedEffect(getEffectParam(data, effect))'
commando_specialized_modifier_cleanup_source="$(sed -n '/public static void clearPostNgePlayerCommandoSpecializedModifiers/,/public static void clearPostNgePlayerCommandoSpecializedBuffs/p' "$work_buff_library")"
printf '%s\n' "$commando_specialized_modifier_cleanup_source" | grep -Fq 'hasSkillModModifier(player, retiredModifier)'
printf '%s\n' "$commando_specialized_modifier_cleanup_source" | grep -Fq 'retiredModifier + "_" + effect'
printf '%s\n' "$commando_specialized_modifier_cleanup_source" | grep -Fq 'getSkillStatMod(player, retiredModifier)'
printf '%s\n' "$commando_specialized_modifier_cleanup_source" | grep -Fq 'applySkillStatisticModifier(player, retiredModifier, -currentValue)'
printf '%s\n' "$commando_specialized_modifier_cleanup_source" | grep -Fq 'messageTo(player, "recalcArmor"'
printf '%s\n' "$commando_specialized_modifier_cleanup_source" | grep -Fq 'combat.cacheCombatData(player)'
commando_specialized_buff_cleanup_source="$(sed -n '/public static void clearPostNgePlayerCommandoSpecializedBuffs/,/public static void retirePostNgePlayerCommandoSpecializedState/p' "$work_buff_library")"
printf '%s\n' "$commando_specialized_buff_cleanup_source" | grep -Fq '!retiredBuff.equals("co_position_secured")'
printf '%s\n' "$commando_specialized_buff_cleanup_source" | grep -Fq 'removeBuff(player, retiredBuff)'
commando_specialized_state_cleanup_source="$(sed -n '/public static void retirePostNgePlayerCommandoSpecializedState/,/private static final String RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_EFFECT_PREFIX/p' "$work_buff_library")"
commando_specialized_parent_remove_line="$(printf '%s\n' "$commando_specialized_state_cleanup_source" | grep -Fn 'removeBuff(player, "co_position_secured")' | head -1 | cut -d: -f1)"
commando_specialized_child_remove_line="$(printf '%s\n' "$commando_specialized_state_cleanup_source" | grep -Fn 'clearPostNgePlayerCommandoSpecializedBuffs(player);' | head -1 | cut -d: -f1)"
commando_specialized_modifier_remove_line="$(printf '%s\n' "$commando_specialized_state_cleanup_source" | grep -Fn 'clearPostNgePlayerCommandoSpecializedModifiers(player);' | head -1 | cut -d: -f1)"
test -n "$commando_specialized_parent_remove_line"
test -n "$commando_specialized_child_remove_line"
test -n "$commando_specialized_modifier_remove_line"
test "$commando_specialized_parent_remove_line" -lt "$commando_specialized_child_remove_line"
test "$commando_specialized_child_remove_line" -lt "$commando_specialized_modifier_remove_line"
grep -Fq 'retirePostNgePlayerCommandoSpecializedState(player);' "$work_buff_library"
commando_specialized_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups/p' "$work_buff_library")"
commando_specialized_admission_line="$(printf '%s\n' "$commando_specialized_admission_source" | grep -Fn 'isRetiredPostNgePlayerCommandoSpecializedBuff(target, bdata)' | head -1 | cut -d: -f1)"
commando_specialized_existing_line="$(printf '%s\n' "$commando_specialized_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$commando_specialized_admission_line"
test -n "$commando_specialized_existing_line"
test "$commando_specialized_admission_line" -lt "$commando_specialized_existing_line"
verify_commando_specialized_source_handler()
{
    commando_specialized_method="$1"
    commando_specialized_next_method="$2"
    commando_specialized_cleanup_marker="$3"
    commando_specialized_additional_cleanup_marker="$4"
    commando_specialized_retained_marker="$5"
    commando_specialized_requires_effect_predicate="$6"
    commando_specialized_handler_source="$(sed -n "/public int $commando_specialized_method(/,/public int $commando_specialized_next_method(/p" "$work_buff_handler")"
    commando_specialized_guard_line="$(printf '%s\n' "$commando_specialized_handler_source" | grep -Fn 'isPlayer(self)' | head -1 | cut -d: -f1)"
    commando_specialized_cleanup_line="$(printf '%s\n' "$commando_specialized_handler_source" | grep -Fn "$commando_specialized_cleanup_marker" | head -1 | cut -d: -f1)"
    commando_specialized_cleanup_end_line="$commando_specialized_cleanup_line"
    if test -n "$commando_specialized_additional_cleanup_marker"; then
        commando_specialized_additional_cleanup_line="$(printf '%s\n' "$commando_specialized_handler_source" | grep -Fn "$commando_specialized_additional_cleanup_marker" | head -1 | cut -d: -f1)"
        test -n "$commando_specialized_additional_cleanup_line"
        test "$commando_specialized_cleanup_line" -lt "$commando_specialized_additional_cleanup_line"
        commando_specialized_cleanup_end_line="$commando_specialized_additional_cleanup_line"
    fi
    commando_specialized_return_line="$(printf '%s\n' "$commando_specialized_handler_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | awk -F: -v cleanup="$commando_specialized_cleanup_end_line" '$1 > cleanup { print $1; exit }')"
    commando_specialized_retained_line="$(printf '%s\n' "$commando_specialized_handler_source" | grep -Fn "$commando_specialized_retained_marker" | head -1 | cut -d: -f1)"
    test -n "$commando_specialized_guard_line"
    test -n "$commando_specialized_cleanup_line"
    test -n "$commando_specialized_return_line"
    test -n "$commando_specialized_retained_line"
    test "$commando_specialized_guard_line" -lt "$commando_specialized_cleanup_line"
    test "$commando_specialized_cleanup_end_line" -lt "$commando_specialized_return_line"
    test "$commando_specialized_return_line" -lt "$commando_specialized_retained_line"
    if test "$commando_specialized_requires_effect_predicate" -eq 1; then
        printf '%s\n' "$commando_specialized_handler_source" | grep -Fq 'buff.isRetiredPostNgePlayerCommandoSpecializedEffect(effectName)'
    fi
}
verify_commando_specialized_source_handler commandoFlashBangAddBuffHandler commandoFlashBangRemoveBuffHandler 'buff.retirePostNgePlayerCommandoSpecializedState(self);' '' 'effectName = effectName.substring' 0
verify_commando_specialized_source_handler commandoFlashBangRemoveBuffHandler commandoMuscleSpasmAddBuffHandler 'buff.clearPostNgePlayerCommandoSpecializedModifiers(self);' '' 'removeAttribOrSkillModModifier(self, "commandoFlashBang")' 0
verify_commando_specialized_source_handler commandoMuscleSpasmAddBuffHandler commandoMuscleSpasmRemoveBuffHandler 'buff.retirePostNgePlayerCommandoSpecializedState(self);' '' 'effectName = effectName.substring' 0
verify_commando_specialized_source_handler commandoMuscleSpasmRemoveBuffHandler commandoRiddleArmorAddBuffHandler 'buff.clearPostNgePlayerCommandoSpecializedModifiers(self);' '' 'removeAttribOrSkillModModifier(self, "commandoMuscleSpasm")' 0
verify_commando_specialized_source_handler commandoRiddleArmorAddBuffHandler commandoRiddleArmorRemoveBuffHandler 'buff.retirePostNgePlayerCommandoSpecializedState(self);' '' 'String tempEffectName = effectName.substring' 0
verify_commando_specialized_source_handler commandoRiddleArmorRemoveBuffHandler radarInvisAddBuffHandler 'buff.clearPostNgePlayerCommandoSpecializedModifiers(self);' '' 'removeAttribOrSkillModModifier(self, effectName)' 0
verify_commando_specialized_source_handler onTargetAddBuffHandler onTargetRemoveBuffHandler 'buff.retirePostNgePlayerCommandoSpecializedState(self);' '' 'if (subtype.equals("expertise_on_target"))' 1
verify_commando_specialized_source_handler onTargetRemoveBuffHandler immunityAddBuffHandler 'buff.clearPostNgePlayerCommandoSpecializedBuffs(self);' 'buff.clearPostNgePlayerCommandoSpecializedModifiers(self);' 'if (hasSkillModModifier(self, effectName))' 1
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && $1 ~ /^expertise_(dot|movement)_immunity$/ {
    found++
    if ($1 == "expertise_dot_immunity") {
        dotFound++
        if ($(fieldIndex["TYPE"]) != "expertiseImmunity" || $(fieldIndex["SUBTYPE"]) != "dot_immunity") exit 2
    } else {
        movementFound++
        if ($(fieldIndex["TYPE"]) != "expertiseImmunity" || $(fieldIndex["SUBTYPE"]) != "movement_immunity") exit 2
    }
}
END { if (found != 2 || dotFound != 1 || movementFound != 1) exit 3 }
' "$work_buff_effect_mapping"
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && ($1 ~ /^fs_sh_[0-3]$/ || $1 == "fs_dot_immunity_recourse") {
    found++
    if ($(fieldIndex["GROUP1"]) != "fsCure" || $(fieldIndex["IS_PERSISTENT"]) != 1) exit 2
    if ($1 ~ /^fs_sh_[0-3]$/) {
        healingFound++
        if ($(fieldIndex["DEBUFF"]) != 0 || $(fieldIndex["EFFECT1_PARAM"]) != "expertise_dot_immunity" ||
            $(fieldIndex["EFFECT1_VALUE"]) != 5 || $(fieldIndex["CALLBACK"]) != "fs_dot_immunity_recourse") exit 2
    } else {
        recourseFound++
        if ($(fieldIndex["DEBUFF"]) != 1 || $(fieldIndex["EFFECT1_PARAM"]) != "" ||
            $(fieldIndex["CALLBACK"]) != "none") exit 2
    }
}
END { if (found != 5 || healingFound != 4 || recourseFound != 1) exit 3 }
' "$work_buff_table"
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && $1 ~ /^fs_sh_[0-3]$/ {
    found++
    if ($(fieldIndex["scriptHook"]) != $1 || $(fieldIndex["displayGroup"]) != "combat" ||
        $(fieldIndex["addToCombatQueue"]) != 1) exit 2
}
END { if (found != 4) exit 3 }
' "$work_command_table"
awk -F '\t' '
BEGIN {
    damage["fs_sh_0"] = 800; damage["fs_sh_1"] = 2500; damage["fs_sh_2"] = 3500; damage["fs_sh_3"] = 5000
    action["fs_sh_0"] = 200; action["fs_sh_1"] = 450; action["fs_sh_2"] = 800; action["fs_sh_3"] = 1150
}
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && $1 ~ /^fs_sh_[0-3]$/ {
    found++
    if ($(fieldIndex["validTarget"]) != "NONE" || $(fieldIndex["hitType"]) != "HEAL" ||
        $(fieldIndex["addedDamage"]) != damage[$1] || $(fieldIndex["actionCost"]) != action[$1] ||
        $(fieldIndex["specialLine"]) != "fs_heal" || $(fieldIndex["performance_spam"]) != "perform_notarget") exit 2
}
END { if (found != 4) exit 3 }
' "$work_combat_data"
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
NR > 2 && $1 ~ /^class_forcesensitive_phase[1-4]_(05|04)$/ {
    value = $(fieldIndex["COMMANDS"]); gsub(/^"|"$/, "", value)
    if (value ~ /(^|,)fs_sh_[0-3](,|$)/) found++
}
END { if (found != 4) exit 3 }
' "$work_skills_table"
fs_expertise_immunity_buff_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_FORCE_SENSITIVE_EXPERTISE_IMMUNITY_BUFFS/,/};/p' "$work_buff_library")"
for fs_expertise_immunity_buff in fs_sh_0 fs_sh_1 fs_sh_2 fs_sh_3 fs_dot_immunity_recourse; do
    printf '%s\n' "$fs_expertise_immunity_buff_inventory_source" | grep -Fq "\"$fs_expertise_immunity_buff\""
done
test "$(printf '%s\n' "$fs_expertise_immunity_buff_inventory_source" | grep -Ec '^[[:space:]]+"(fs_sh_[0-3]|fs_dot_immunity_recourse)"[,]?$')" -eq 5
fs_expertise_immunity_effect_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_FORCE_SENSITIVE_EXPERTISE_IMMUNITY_EFFECTS/,/};/p' "$work_buff_library")"
for fs_expertise_immunity_effect in expertise_dot_immunity expertise_movement_immunity; do
    printf '%s\n' "$fs_expertise_immunity_effect_inventory_source" | grep -Fq "\"$fs_expertise_immunity_effect\""
done
test "$(printf '%s\n' "$fs_expertise_immunity_effect_inventory_source" | grep -Ec '^[[:space:]]+"expertise_(dot|movement)_immunity"[,]?$')" -eq 2
fs_expertise_immunity_effect_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect/,/public static boolean isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuff(obj_id target/p' "$work_buff_library")"
printf '%s\n' "$fs_expertise_immunity_effect_predicate_source" | grep -Fq 'effectName.equals(retiredEffect)'
! printf '%s\n' "$fs_expertise_immunity_effect_predicate_source" | grep -Fq 'startsWith'
fs_expertise_immunity_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuff(obj_id target/,/public static void clearPostNgePlayerForceSensitiveExpertiseImmunityResidue/p' "$work_buff_library")"
printf '%s\n' "$fs_expertise_immunity_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$fs_expertise_immunity_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuffName(data.buffName)'
printf '%s\n' "$fs_expertise_immunity_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect(getEffectParam(data, effect))'
fs_expertise_immunity_residue_source="$(sed -n '/public static void clearPostNgePlayerForceSensitiveExpertiseImmunityResidue/,/public static void retirePostNgePlayerForceSensitiveExpertiseImmunityState/p' "$work_buff_library")"
printf '%s\n' "$fs_expertise_immunity_residue_source" | grep -Fq '!isPlayer(player)'
for fs_expertise_immunity_residue in immunity.dot.all immunity.movement.snare immunity.movement.root; do
    printf '%s\n' "$fs_expertise_immunity_residue_source" | grep -Fq "\"$fs_expertise_immunity_residue\""
done
printf '%s\n' "$fs_expertise_immunity_residue_source" | grep -Fq 'stopClientEffectObjByLabel(player, "expertise_dot")'
printf '%s\n' "$fs_expertise_immunity_residue_source" | grep -Fq 'stopClientEffectObjByLabel(player, "expertise_movement")'
fs_expertise_immunity_state_source="$(sed -n '/public static void retirePostNgePlayerForceSensitiveExpertiseImmunityState/,/private static final String\[\] RETIRED_POST_NGE_GCW_BANNER_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$fs_expertise_immunity_state_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$fs_expertise_immunity_state_source" | grep -Fq 'removeBuff(player, retiredBuff)'
printf '%s\n' "$fs_expertise_immunity_state_source" | grep -Fq 'clearPostNgePlayerForceSensitiveExpertiseImmunityResidue(player);'
grep -Fq 'retirePostNgePlayerForceSensitiveExpertiseImmunityState(player);' "$work_buff_library"
fs_expertise_immunity_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static float getBuffTimeRemaining/p' "$work_buff_library")"
fs_expertise_immunity_admission_line="$(printf '%s\n' "$fs_expertise_immunity_admission_source" | grep -Fn 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuff(target, bdata)' | head -1 | cut -d: -f1)"
fs_expertise_immunity_existing_line="$(printf '%s\n' "$fs_expertise_immunity_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$fs_expertise_immunity_admission_line"
test -n "$fs_expertise_immunity_existing_line"
test "$fs_expertise_immunity_admission_line" -lt "$fs_expertise_immunity_existing_line"
verify_fs_expertise_immunity_source_handler()
{
    fs_expertise_immunity_method="$1"
    fs_expertise_immunity_next_method="$2"
    fs_expertise_immunity_cleanup_marker="$3"
    fs_expertise_immunity_retained_marker="$4"
    fs_expertise_immunity_handler_source="$(sed -n "/public int $fs_expertise_immunity_method/,/public int $fs_expertise_immunity_next_method/p" "$work_buff_handler")"
    fs_expertise_immunity_guard_line="$(printf '%s\n' "$fs_expertise_immunity_handler_source" | grep -Fn 'isPlayer(self)' | head -1 | cut -d: -f1)"
    fs_expertise_immunity_effect_line="$(printf '%s\n' "$fs_expertise_immunity_handler_source" | grep -Fn 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect(effectName)' | head -1 | cut -d: -f1)"
    fs_expertise_immunity_name_line="$(printf '%s\n' "$fs_expertise_immunity_handler_source" | grep -Fn 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuffName(buffName)' | head -1 | cut -d: -f1)"
    fs_expertise_immunity_cleanup_line="$(printf '%s\n' "$fs_expertise_immunity_handler_source" | grep -Fn "$fs_expertise_immunity_cleanup_marker" | head -1 | cut -d: -f1)"
    fs_expertise_immunity_return_line="$(printf '%s\n' "$fs_expertise_immunity_handler_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | awk -F: -v cleanup="$fs_expertise_immunity_cleanup_line" '$1 > cleanup { print $1; exit }')"
    fs_expertise_immunity_retained_line="$(printf '%s\n' "$fs_expertise_immunity_handler_source" | grep -Fn "$fs_expertise_immunity_retained_marker" | head -1 | cut -d: -f1)"
    test -n "$fs_expertise_immunity_guard_line"
    test -n "$fs_expertise_immunity_effect_line"
    test -n "$fs_expertise_immunity_name_line"
    test -n "$fs_expertise_immunity_cleanup_line"
    test -n "$fs_expertise_immunity_return_line"
    test -n "$fs_expertise_immunity_retained_line"
    test "$fs_expertise_immunity_guard_line" -lt "$fs_expertise_immunity_effect_line"
    test "$fs_expertise_immunity_guard_line" -lt "$fs_expertise_immunity_name_line"
    test "$fs_expertise_immunity_name_line" -lt "$fs_expertise_immunity_cleanup_line"
    test "$fs_expertise_immunity_cleanup_line" -lt "$fs_expertise_immunity_return_line"
    test "$fs_expertise_immunity_return_line" -lt "$fs_expertise_immunity_retained_line"
}
verify_fs_expertise_immunity_source_handler expertiseImmunityAddBuffHandler expertiseImmunityRemoveBuffHandler 'buff.retirePostNgePlayerForceSensitiveExpertiseImmunityState(self);' 'if (!buff.isInStance(self))'
verify_fs_expertise_immunity_source_handler expertiseImmunityRemoveBuffHandler expertiseChannelActionHealAddBuffHandler 'buff.clearPostNgePlayerForceSensitiveExpertiseImmunityResidue(self);' 'return immunityRemoveBuffHandler'
grep -Fq 'public int immunityAddBuffHandler' "$work_buff_handler"
grep -Fq 'public int immunityRemoveBuffHandler' "$work_buff_handler"
awk -F '\t' '$1 == "dot_immunity" && $2 == "immunity" && $3 == "dot_immunity" { dotFound++ } $1 == "movement_immunity" && $2 == "immunity" && $3 == "movement_immunity" { movementFound++ } END { if (dotFound != 1 || movementFound != 1) exit 3 }' "$work_buff_effect_mapping"
# The retained NGE Bounty Hunter Flawless Strike set chain remains available
# to expansion content, but its player buff, nested proc, residue, and four
# action entrypoints must all fail closed before inherited writers execute.
awk -F '\t' '$1 ~ /^(set_bonus_bh_utility_a_[123]|bh_flawless_strike|bh_flawless_proc_chance_1|flawless_bead_[123])$/ { found++ } END { if (found != 8) exit 3 }' "$work_buff_table"
awk -F '\t' '$1 == "bh_flawless_proc_chance" { found++; if ($2 != "bhFlawless" || $3 != "bh_flawless_proc_chance") exit 2 } END { if (found != 1) exit 3 }' "$work_buff_effect_mapping"
for bounty_hunter_flawless_action in bh_flawless_strike set_bonus_bh_utility_a_1 set_bonus_bh_utility_a_2 set_bonus_bh_utility_a_3; do
    awk -F '\t' -v name="$bounty_hunter_flawless_action" '
    NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
    NR > 2 && $1 == name { found++; if ($(fieldIndex["scriptHook"]) != name) exit 2 }
    END { if (found != 1) exit 3 }
    ' "$work_command_table"
    awk -F '\t' -v name="$bounty_hunter_flawless_action" 'NR > 2 && $1 == name { found++ } END { if (found != 1) exit 3 }' "$work_combat_data"
done
for bounty_hunter_flawless_set_action in set_bonus_bh_utility_a_1 set_bonus_bh_utility_a_2 set_bonus_bh_utility_a_3; do
    awk -F '\t' -v name="$bounty_hunter_flawless_set_action" 'NR > 2 && $1 == name { found++; if ($2 != 10) exit 2 } END { if (found != 1) exit 3 }' "$work_proc_table"
done
awk -F '\t' '$1 == 10002 && $3 ~ /^set_bonus_bh_utility_a_[123]$/ { found++; effects[$3]++ } END { if (found != 3 || effects["set_bonus_bh_utility_a_1"] != 1 || effects["set_bonus_bh_utility_a_2"] != 1 || effects["set_bonus_bh_utility_a_3"] != 1) exit 3 }' "$work_item_sets"
bounty_hunter_flawless_buff_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_BOUNTY_HUNTER_FLAWLESS_BUFFS/,/};/p' "$work_buff_library")"
for bounty_hunter_flawless_buff in set_bonus_bh_utility_a_1 set_bonus_bh_utility_a_2 set_bonus_bh_utility_a_3 bh_flawless_strike bh_flawless_proc_chance_1 flawless_bead_1 flawless_bead_2 flawless_bead_3; do
    printf '%s\n' "$bounty_hunter_flawless_buff_inventory_source" | grep -Fq "\"$bounty_hunter_flawless_buff\""
done
test "$(printf '%s\n' "$bounty_hunter_flawless_buff_inventory_source" | grep -Ec '^[[:space:]]+"(set_bonus_bh_utility_a_[123]|bh_flawless_strike|bh_flawless_proc_chance_1|flawless_bead_[123])"[,]?$')" -eq 8
bounty_hunter_flawless_modifier_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_BOUNTY_HUNTER_FLAWLESS_MODIFIERS/,/};/p' "$work_buff_library")"
for bounty_hunter_flawless_modifier in bh_flawless_bead flawless_bead expertise_cooldown_line_bh_flawless_strike set_bonus_bh_utility_a_1 set_bonus_bh_utility_a_2 set_bonus_bh_utility_a_3; do
    printf '%s\n' "$bounty_hunter_flawless_modifier_inventory_source" | grep -Fq "\"$bounty_hunter_flawless_modifier\""
done
test "$(printf '%s\n' "$bounty_hunter_flawless_modifier_inventory_source" | grep -Ec '^[[:space:]]+"(bh_flawless_bead|flawless_bead|expertise_cooldown_line_bh_flawless_strike|set_bonus_bh_utility_a_[123])"[,]?$')" -eq 6
bounty_hunter_flawless_action_inventory_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_PLAYER_BOUNTY_HUNTER_FLAWLESS_ACTIONS/,/};/p' "$work_buff_library")"
test "$(printf '%s\n' "$bounty_hunter_flawless_action_inventory_source" | grep -Ec '^[[:space:]]+"(bh_flawless_strike|set_bonus_bh_utility_a_[123])"[,]?$')" -eq 4
bounty_hunter_flawless_buff_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerBountyHunterFlawlessBuff(obj_id target/,/public static void clearPostNgePlayerBountyHunterFlawlessResidue/p' "$work_buff_library")"
printf '%s\n' "$bounty_hunter_flawless_buff_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$bounty_hunter_flawless_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerBountyHunterFlawlessBuffName(data.buffName)'
printf '%s\n' "$bounty_hunter_flawless_buff_predicate_source" | grep -Fq 'isRetiredPostNgePlayerBountyHunterFlawlessEffect(getEffectParam(data, effect))'
bounty_hunter_flawless_residue_source="$(sed -n '/public static void clearPostNgePlayerBountyHunterFlawlessResidue/,/public static void retirePostNgePlayerBountyHunterFlawlessState/p' "$work_buff_library")"
printf '%s\n' "$bounty_hunter_flawless_residue_source" | grep -Fq 'removeBuff(player, "bh_flawless_proc_chance_1")'
printf '%s\n' "$bounty_hunter_flawless_residue_source" | grep -Fq 'removeAttribOrSkillModModifier(player, retiredModifier)'
printf '%s\n' "$bounty_hunter_flawless_residue_source" | grep -Fq 'applySkillStatisticModifier(player, retiredModifier, -currentValue)'
printf '%s\n' "$bounty_hunter_flawless_residue_source" | grep -Fq 'revokeCommand(player, retiredAction)'
bounty_hunter_flawless_state_source="$(sed -n '/public static void retirePostNgePlayerBountyHunterFlawlessState/,/private static final String\[\] RETIRED_POST_NGE_GCW_BANNER_BUFFS/p' "$work_buff_library")"
printf '%s\n' "$bounty_hunter_flawless_state_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$bounty_hunter_flawless_state_source" | grep -Fq 'removeBuff(player, retiredBuff)'
printf '%s\n' "$bounty_hunter_flawless_state_source" | grep -Fq 'clearPostNgePlayerBountyHunterFlawlessResidue(player);'
grep -Fq 'retirePostNgePlayerBountyHunterFlawlessState(player);' "$work_buff_library"
bounty_hunter_flawless_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static float getBuffTimeRemaining/p' "$work_buff_library")"
bounty_hunter_flawless_admission_line="$(printf '%s\n' "$bounty_hunter_flawless_admission_source" | grep -Fn 'isRetiredPostNgePlayerBountyHunterFlawlessBuff(target, bdata)' | head -1 | cut -d: -f1)"
bounty_hunter_flawless_existing_line="$(printf '%s\n' "$bounty_hunter_flawless_admission_source" | grep -Fn 'hasBuff(target, nameCrc)' | head -1 | cut -d: -f1)"
test -n "$bounty_hunter_flawless_admission_line"
test -n "$bounty_hunter_flawless_existing_line"
test "$bounty_hunter_flawless_admission_line" -lt "$bounty_hunter_flawless_existing_line"
bounty_hunter_flawless_action_source="$(sed -n '/public static boolean isRetiredPostNgeBountyHunterPlayerAction/,/public static boolean isRetiredPostNgeCommandoPlayerAction/p' "$work_combat_base")"
printf '%s\n' "$bounty_hunter_flawless_action_source" | grep -Fq 'isPlayer(self)'
printf '%s\n' "$bounty_hunter_flawless_action_source" | grep -Fq 'actionName.startsWith("bh_")'
for bounty_hunter_flawless_set_action in set_bonus_bh_utility_a_1 set_bonus_bh_utility_a_2 set_bonus_bh_utility_a_3; do
    printf '%s\n' "$bounty_hunter_flawless_action_source" | grep -Fq "actionName.equals(\"$bounty_hunter_flawless_set_action\")"
done
verify_bounty_hunter_flawless_source_handler()
{
    bounty_hunter_flawless_method="$1"
    bounty_hunter_flawless_next_method="$2"
    bounty_hunter_flawless_cleanup_marker="$3"
    bounty_hunter_flawless_retained_marker="$4"
    bounty_hunter_flawless_handler_source="$(sed -n "/public int $bounty_hunter_flawless_method/,/public int $bounty_hunter_flawless_next_method/p" "$work_buff_handler")"
    bounty_hunter_flawless_guard_line="$(printf '%s\n' "$bounty_hunter_flawless_handler_source" | grep -Fn 'isPlayer(self)' | head -1 | cut -d: -f1)"
    bounty_hunter_flawless_effect_line="$(printf '%s\n' "$bounty_hunter_flawless_handler_source" | grep -Fn 'isRetiredPostNgePlayerBountyHunterFlawlessEffect(effectName)' | head -1 | cut -d: -f1)"
    bounty_hunter_flawless_name_line="$(printf '%s\n' "$bounty_hunter_flawless_handler_source" | grep -Fn 'isRetiredPostNgePlayerBountyHunterFlawlessBuffName(buffName)' | head -1 | cut -d: -f1)"
    bounty_hunter_flawless_cleanup_line="$(printf '%s\n' "$bounty_hunter_flawless_handler_source" | grep -Fn "$bounty_hunter_flawless_cleanup_marker" | head -1 | cut -d: -f1)"
    bounty_hunter_flawless_return_line="$(printf '%s\n' "$bounty_hunter_flawless_handler_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | awk -F: -v cleanup="$bounty_hunter_flawless_cleanup_line" '$1 > cleanup { print $1; exit }')"
    bounty_hunter_flawless_retained_line="$(printf '%s\n' "$bounty_hunter_flawless_handler_source" | grep -Fn "$bounty_hunter_flawless_retained_marker" | head -1 | cut -d: -f1)"
    test "$bounty_hunter_flawless_guard_line" -lt "$bounty_hunter_flawless_effect_line"
    test "$bounty_hunter_flawless_guard_line" -lt "$bounty_hunter_flawless_name_line"
    test "$bounty_hunter_flawless_name_line" -lt "$bounty_hunter_flawless_cleanup_line"
    test "$bounty_hunter_flawless_cleanup_line" -lt "$bounty_hunter_flawless_return_line"
    test "$bounty_hunter_flawless_return_line" -lt "$bounty_hunter_flawless_retained_line"
}
verify_bounty_hunter_flawless_source_handler bhFlawlessAddBuffHandler bhFlawlessRemoveBuffHandler 'buff.retirePostNgePlayerBountyHunterFlawlessState(self);' 'buff.applyBuff(self, "bh_flawless_proc_chance_1")'
verify_bounty_hunter_flawless_source_handler bhFlawlessRemoveBuffHandler mtpMeatlumpAngryAddBuffHandler 'buff.clearPostNgePlayerBountyHunterFlawlessResidue(self);' 'buff.removeBuff(self, "bh_flawless_proc_chance_1")'
medic_deferred_dot_proc_actions='expertise_dueterium_rounds_proc expertise_poison_knuckle_proc'
for medic_deferred_dot_proc_action in $medic_deferred_dot_proc_actions; do
    awk -F '\t' -v name="$medic_deferred_dot_proc_action" '
    NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
    NR > 2 && $1 == name {
        found++
        if ($(fieldIndex["scriptHook"]) != name || $(fieldIndex["failScriptHook"]) != "failProc" ||
            $(fieldIndex["displayGroup"]) != "combat" || $(fieldIndex["addToCombatQueue"]) != 0 ||
            $(fieldIndex["toolbarOnly"]) != 1 || $(fieldIndex["fromServerOnly"]) != 1) exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_command_table"
    awk -F '\t' -v name="$medic_deferred_dot_proc_action" '
    NR == 1 { for (column = 1; column <= NF; column++) fieldIndex[$column] = column; next }
    NR > 2 && $1 == name {
        found++
        if ($(fieldIndex["commandType"]) != "LEFT_CLICK_DEFAULT" ||
            $(fieldIndex["validTarget"]) != "STANDARD" || $(fieldIndex["hitType"]) != "ATTACK" ||
            $(fieldIndex["percentAddFromWeapon"]) != 0.55 || $(fieldIndex["dotIntensity"]) != 0 ||
            $(fieldIndex["dotDuration"]) != 6 || $(fieldIndex["specialLine"]) != "no_proc") exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_combat_data"
    awk -F '\t' -v name="$medic_deferred_dot_proc_action" '
    NR > 2 && $1 == name {
        found++
        explanation = $6
        sub(/\r$/, "", explanation)
        if ($2 != 5 || explanation != "Medic expertise proc") exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_proc_table"
    grep -Fq "public int $medic_deferred_dot_proc_action(" "$work_combat_actions"
done
test "$(grep -Ec '^    public int expertise_(dueterium_rounds|poison_knuckle)_proc\(' "$work_combat_actions")" -eq 2
awk -F '\t' '$1 == "expertise_dueterium_rounds_proc" { found++; if ($3 != "Medic:ProcFireDoT" || $62 != "fire") exit 2 } END { if (found != 1) exit 3 }' "$work_combat_data"
awk -F '\t' '$1 == "expertise_poison_knuckle_proc" { found++; if ($3 != "Medic:ProcPoisonDoT" || $62 != "poison") exit 2 } END { if (found != 1) exit 3 }' "$work_combat_data"
awk -F '\t' '$1 == "expertise_me_dueterium_rounds_1" { found++; if ($23 != "expertise_dueterium_rounds_proc=5") exit 2 } $1 == "expertise_me_poison_knuckle_1" { found++; if ($23 != "expertise_poison_knuckle_proc=5") exit 2 } END { if (found != 2) exit 3 }' "$work_skills_table"
awk -F '\t' '$1 == "science_combatmedic_novice" { poison++; if ($22 !~ /(^|,)applyPoison(,|$)/) exit 2 } $1 == "science_combatmedic_healing_range_02" { disease++; if ($22 !~ /(^|,)applyDisease(,|$)/) exit 2 } END { if (poison != 1 || disease != 1) exit 3 }' "$work_skills_table"
medic_player_action_source="$(sed -n '/public static boolean isRetiredPostNgeMedicPlayerAction/,/public static boolean isRetiredPostNgeEntertainerPlayerAction/p' "$work_combat_base")"
printf '%s\n' "$medic_player_action_source" | grep -Fq 'return isPlayer(self)'
printf '%s\n' "$medic_player_action_source" | grep -Fq 'actionName.startsWith("me_")'
printf '%s\n' "$medic_player_action_source" | grep -Fq 'actionName.equals("expertise_dueterium_rounds_proc")'
printf '%s\n' "$medic_player_action_source" | grep -Fq 'actionName.equals("expertise_poison_knuckle_proc")'
generic_proc_gate_line="$(grep -Fn 'if (proc.isRetiredPostNgePlayerProcAction(self, actionName))' "$work_combat_base" | head -1 | cut -d: -f1)"
medic_action_gate_line="$(grep -Fn 'if (isRetiredPostNgeMedicPlayerAction(self, actionName))' "$work_combat_base" | head -1 | cut -d: -f1)"
test "$generic_proc_gate_line" -lt "$medic_action_gate_line"
entertainer_buildabuff_reactive_heal_specs='expertise_buildabuff_heal_1_reac:200:Buildabuffreactiveheallvl10:Buildabuff_Reactive_Heal_(level_10) expertise_buildabuff_heal_2_reac:400:Buildabuffreactiveheallvl40:Buildabuff_Reactive_Heal_(level_40) expertise_buildabuff_heal_3_reac:800:Buildabuffreactiveheallvl70:Buildabuff_Reactive_Heal_(level_70)'
for entertainer_buildabuff_reactive_heal_spec in $entertainer_buildabuff_reactive_heal_specs; do
    entertainer_buildabuff_reactive_heal_action="${entertainer_buildabuff_reactive_heal_spec%%:*}"
    entertainer_buildabuff_reactive_heal_fields="${entertainer_buildabuff_reactive_heal_spec#*:}"
    entertainer_buildabuff_reactive_heal_damage="${entertainer_buildabuff_reactive_heal_fields%%:*}"
    entertainer_buildabuff_reactive_heal_fields="${entertainer_buildabuff_reactive_heal_fields#*:}"
    entertainer_buildabuff_reactive_heal_comment="${entertainer_buildabuff_reactive_heal_fields%%:*}"
    entertainer_buildabuff_reactive_heal_explanation="${entertainer_buildabuff_reactive_heal_fields#*:}"
    entertainer_buildabuff_reactive_heal_explanation="$(printf '%s' "$entertainer_buildabuff_reactive_heal_explanation" | tr '_' ' ')"
    awk -F '\t' -v name="$entertainer_buildabuff_reactive_heal_action" '
    NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
    NR > 2 && $(fieldIndex["commandName"]) == name {
        found++
        if ($(fieldIndex["scriptHook"]) != name || $(fieldIndex["failScriptHook"]) != "failProc" ||
            $(fieldIndex["displayGroup"]) != "combat" || $(fieldIndex["addToCombatQueue"]) != 0 ||
            $(fieldIndex["cooldownGroup"]) != "reac_heal" || $(fieldIndex["cooldownTime"]) != 3 ||
            $(fieldIndex["toolbarOnly"]) != 1 || $(fieldIndex["fromServerOnly"]) != 1) exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_command_table"
    awk -F '\t' -v name="$entertainer_buildabuff_reactive_heal_action" -v damage="$entertainer_buildabuff_reactive_heal_damage" -v comment="$entertainer_buildabuff_reactive_heal_comment" '
    NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
    NR > 2 && $(fieldIndex["actionName"]) == name {
        found++
        if ($(fieldIndex["comments"]) != comment || $(fieldIndex["validTarget"]) != "NONE" ||
            $(fieldIndex["hitType"]) != "HEAL" || $(fieldIndex["healAttrib"]) != "HEALTH" ||
            $(fieldIndex["attackType"]) != "SINGLE_TARGET" || $(fieldIndex["addedDamage"]) != damage ||
            $(fieldIndex["percentAddFromWeapon"]) != 0 || $(fieldIndex["specialLine"]) != "no_proc") exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_combat_data"
    awk -F '\t' -v name="$entertainer_buildabuff_reactive_heal_action" -v expected="$entertainer_buildabuff_reactive_heal_explanation" '
    NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
    NR > 2 && $(fieldIndex["procString"]) == name {
        found++
        explanation = $(fieldIndex["explanation"])
        sub(/\r$/, "", explanation)
        if ($(fieldIndex["procChance"]) != 8 || explanation != expected) exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_proc_table"
    entertainer_buildabuff_reactive_heal_handler_source="$(sed -n "/public int $entertainer_buildabuff_reactive_heal_action(/,/return SCRIPT_CONTINUE;/p" "$work_combat_actions")"
    printf '%s' "$entertainer_buildabuff_reactive_heal_handler_source" | grep -Fq "public int $entertainer_buildabuff_reactive_heal_action("
    printf '%s' "$entertainer_buildabuff_reactive_heal_handler_source" | grep -Fq 'combatStandardAction('
done
test "$(grep -Ec '^    public int expertise_buildabuff_heal_[123]_reac\(' "$work_combat_actions")" -eq 3
precu_entertainer_core_skills='social_entertainer_novice social_entertainer_master social_dancer_novice social_dancer_master social_musician_novice social_musician_master'
for precu_entertainer_core_skill in $precu_entertainer_core_skills; do
    awk -F '\t' -v name="$precu_entertainer_core_skill" '
    NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
    NR > 2 && $(fieldIndex["NAME"]) == name { found++ }
    END { if (found != 1) exit 3 }
    ' "$work_skills_table"
done
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
NR > 2 && $(fieldIndex["NAME"]) == "social_entertainer_novice" {
    found++
    commands = $(fieldIndex["COMMANDS"])
    skillMods = $(fieldIndex["SKILL_MODS"])
    gsub(/^"|"$/, "", commands)
    gsub(/^"|"$/, "", skillMods)
    commands = "," commands ","
    skillMods = "," skillMods ","
    if (commands !~ /,startDance,/ || commands !~ /,startMusic,/ || commands !~ /,flourish\+1,/ ||
        skillMods !~ /,healing_dance_wound=5,/ || skillMods !~ /,healing_music_wound=5,/) exit 2
}
END { if (found != 1) exit 3 }
' "$work_skills_table"
precu_entertainer_core_command_specs='startDance:cmdStartDance startMusic:cmdStartMusic stopDance:cmdStopDance stopMusic:cmdStopMusic flourish:cmdFlourish'
for precu_entertainer_core_command_spec in $precu_entertainer_core_command_specs; do
    precu_entertainer_core_command="${precu_entertainer_core_command_spec%%:*}"
    precu_entertainer_core_hook="${precu_entertainer_core_command_spec#*:}"
    awk -F '\t' -v name="$precu_entertainer_core_command" -v hook="$precu_entertainer_core_hook" '
    NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
    NR > 2 && $(fieldIndex["commandName"]) == name {
        found++
        if ($(fieldIndex["scriptHook"]) != hook) exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_command_table"
done
entertainer_player_action_source="$(sed -n '/public static boolean isRetiredPostNgeEntertainerPlayerAction/,/private static final String\[\] RETIRED_POST_NGE_PVP_REWARD_PLAYER_ACTIONS/p' "$work_combat_base")"
printf '%s\n' "$entertainer_player_action_source" | grep -Fq 'return isPlayer(self)'
printf '%s\n' "$entertainer_player_action_source" | grep -Fq 'actionName.startsWith("en_")'
printf '%s\n' "$entertainer_player_action_source" | grep -Fq 'actionName.startsWith("expertise_buildabuff_")'
entertainer_action_gate_line="$(grep -Fn 'if (isRetiredPostNgeEntertainerPlayerAction(self, actionName))' "$work_combat_base" | head -1 | cut -d: -f1)"
test "$generic_proc_gate_line" -lt "$entertainer_action_gate_line"
medic_doom_actions='me_dm_dot_1 me_dm_dot_2 me_dm_dot_3 me_dm_dot_4 me_dm_dot_5 me_dm_dot_6 me_induce_insanity_1 me_bacta_resistance_1 me_electrolyte_drain_1 me_traumatize_5 me_thyroid_rupture_1'
for medic_doom_action in $medic_doom_actions; do
    awk -F '\t' -v name="$medic_doom_action" '
    NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
    NR > 2 && $(fieldIndex["commandName"]) == name {
        found++
        if ($(fieldIndex["scriptHook"]) != name || $(fieldIndex["displayGroup"]) != "combat" ||
            $(fieldIndex["addToCombatQueue"]) != 1) exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_command_table"
    awk -F '\t' -v name="$medic_doom_action" '
    NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
    NR > 2 && $(fieldIndex["actionName"]) == name {
        found++
        specialLine = $(fieldIndex["specialLine"])
        if ($(fieldIndex["validTarget"]) != "STANDARD" ||
            $(fieldIndex["attackType"]) != "SINGLE_TARGET" ||
            (specialLine != "me_dot" && specialLine != "me_debuff")) exit 2
    }
    END { if (found != 1) exit 3 }
    ' "$work_combat_data"
    medic_doom_action_source="$(sed -n "/public int $medic_doom_action(/,/return SCRIPT_CONTINUE;/p" "$work_combat_actions")"
    medic_doom_action_gate_line="$(printf '%s\n' "$medic_doom_action_source" | grep -Fn "combatStandardAction(\"$medic_doom_action\"" | head -1 | cut -d: -f1)"
    medic_doom_action_proc_line="$(printf '%s\n' "$medic_doom_action_source" | grep -Fn 'doDoom(self, target);' | head -1 | cut -d: -f1)"
    test -n "$medic_doom_action_gate_line"
    test -n "$medic_doom_action_proc_line"
    test "$medic_doom_action_gate_line" -lt "$medic_doom_action_proc_line"
done
test "$(grep -Fc 'doDoom(self, target);' "$work_combat_actions")" -eq 11
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
NR > 2 && $(fieldIndex["NAME"]) == "me_doom" {
    found++
    if ($(fieldIndex["TYPE"]) != "meDoom" || $(fieldIndex["SUBTYPE"]) != "me_doom") exit 2
}
END { if (found != 1) exit 3 }
' "$work_buff_effect_mapping"
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
NR > 2 && $(fieldIndex["NAME"]) == "me_doom" {
    found++
    if ($(fieldIndex["GROUP1"]) != "meDoom" || $(fieldIndex["DURATION"]) != 10 ||
        $(fieldIndex["EFFECT1_PARAM"]) != "me_doom" || $(fieldIndex["EFFECT1_VALUE"]) != 1 ||
        $(fieldIndex["DEBUFF"]) != 1 || $(fieldIndex["IS_PERSISTENT"]) != 1) exit 2
}
NR > 2 && $(fieldIndex["NAME"]) == "set_bonus_medic_utility_b_3" {
    setBonus++
    if ($(fieldIndex["EFFECT5_PARAM"]) != "me_doom_chance" || $(fieldIndex["EFFECT5_VALUE"]) != 20) exit 4
}
END { if (found != 1 || setBonus != 1) exit 3 }
' "$work_buff_table"
awk -F '\t' '
NR == 1 { for (column = 1; column <= NF; column++) { header = $column; sub(/\r$/, "", header); fieldIndex[header] = column } next }
NR > 2 && $(fieldIndex["skill_mod"]) == "me_doom_chance" {
    found++
    comment = $(fieldIndex["comment"])
    sub(/\r$/, "", comment)
    if ($(fieldIndex["profession"]) != "medic_1a" || $(fieldIndex["category"]) != "medic" || comment != "DOOM Chance") exit 2
}
END { if (found != 1) exit 3 }
' "$work_skill_mod_listing"
medic_doom_proc_source="$(sed -n '/public void doDoom(obj_id attacker, obj_id defender)/,/public int of_buff_def_1/p' "$work_combat_actions")"
medic_doom_attacker_guard_line="$(printf '%s\n' "$medic_doom_proc_source" | grep -Fn 'if (isPlayer(attacker))' | head -1 | cut -d: -f1)"
medic_doom_defender_guard_line="$(printf '%s\n' "$medic_doom_proc_source" | grep -Fn 'if (isPlayer(defender))' | head -1 | cut -d: -f1)"
medic_doom_chance_read_line="$(printf '%s\n' "$medic_doom_proc_source" | grep -Fn 'getEnhancedSkillStatisticModifierUncapped(attacker, "me_doom_chance")' | head -1 | cut -d: -f1)"
medic_doom_state_write_line="$(printf '%s\n' "$medic_doom_proc_source" | grep -Fn 'utils.setScriptVar(defender, "me_doom.doom_owner", attacker);' | head -1 | cut -d: -f1)"
test -n "$medic_doom_attacker_guard_line"
test -n "$medic_doom_defender_guard_line"
test -n "$medic_doom_chance_read_line"
test -n "$medic_doom_state_write_line"
test "$medic_doom_attacker_guard_line" -lt "$medic_doom_defender_guard_line"
test "$medic_doom_defender_guard_line" -lt "$medic_doom_chance_read_line"
test "$medic_doom_chance_read_line" -lt "$medic_doom_state_write_line"
printf '%s\n' "$medic_doom_proc_source" | grep -Fq 'buff.retirePostNgePlayerMedicDoomState(attacker);'
printf '%s\n' "$medic_doom_proc_source" | grep -Fq 'buff.retirePostNgePlayerMedicDoomState(defender);'
medic_doom_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerMedicDoomBuff/,/public static void clearPostNgePlayerMedicDoomState/p' "$work_buff_library")"
printf '%s\n' "$medic_doom_predicate_source" | grep -Fq 'isPlayer(target)'
printf '%s\n' "$medic_doom_predicate_source" | grep -Fq 'RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_BUFF.equals(data.buffName)'
medic_doom_clear_source="$(sed -n '/public static void clearPostNgePlayerMedicDoomState/,/public static void retirePostNgePlayerMedicDoomState/p' "$work_buff_library")"
printf '%s\n' "$medic_doom_clear_source" | grep -Fq 'utils.removeScriptVarTree(player, RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_BUFF);'
printf '%s\n' "$medic_doom_clear_source" | grep -Fq 'hasSkillModModifier(player, RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_MODIFIER)'
printf '%s\n' "$medic_doom_clear_source" | grep -Fq 'removeAttribOrSkillModModifier(player, RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_MODIFIER);'
medic_doom_cleanup_source="$(sed -n '/public static void retirePostNgePlayerMedicDoomState/,/public static boolean isRetiredPostNgePlayerModifierBuff/p' "$work_buff_library")"
printf '%s\n' "$medic_doom_cleanup_source" | grep -Fq 'removeBuff(player, RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_BUFF);'
printf '%s\n' "$medic_doom_cleanup_source" | grep -Fq 'clearPostNgePlayerMedicDoomState(player);'
grep -Fq 'retirePostNgePlayerMedicDoomState(player);' "$work_buff_library"
medic_doom_admission_line="$(grep -Fn 'isRetiredPostNgePlayerMedicDoomBuff(target, bdata)' "$work_buff_library" | head -1 | cut -d: -f1)"
generic_existing_buff_line="$(grep -Fn 'if (hasBuff(target, nameCrc))' "$work_buff_library" | head -1 | cut -d: -f1)"
test "$medic_doom_admission_line" -lt "$generic_existing_buff_line"
medic_doom_add_source="$(sed -n '/public int meDoomAddBuffHandler/,/public int meDoomRemoveBuffHandler/p' "$work_buff_handler")"
medic_doom_add_guard_line="$(printf '%s\n' "$medic_doom_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
medic_doom_add_state_read_line="$(printf '%s\n' "$medic_doom_add_source" | grep -Fn 'utils.getObjIdScriptVar(self, "me_doom.doom_owner")' | head -1 | cut -d: -f1)"
test "$medic_doom_add_guard_line" -lt "$medic_doom_add_state_read_line"
printf '%s\n' "$medic_doom_add_source" | grep -Fq 'buff.retirePostNgePlayerMedicDoomState(self);'
test "$(printf '%s\n' "$medic_doom_add_source" | grep -Fc 'dot.applyDotEffect')" -eq 2
medic_doom_remove_source="$(sed -n '/public int meDoomRemoveBuffHandler/,/public int cacheExpertiseProcReacList/p' "$work_buff_handler")"
medic_doom_remove_guard_line="$(printf '%s\n' "$medic_doom_remove_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
medic_doom_remove_state_read_line="$(printf '%s\n' "$medic_doom_remove_source" | grep -Fn 'utils.getObjIdScriptVar(self, "me_doom.doom_owner")' | head -1 | cut -d: -f1)"
test "$medic_doom_remove_guard_line" -lt "$medic_doom_remove_state_read_line"
printf '%s\n' "$medic_doom_remove_source" | grep -Fq 'buff.clearPostNgePlayerMedicDoomState(self);'
test "$(printf '%s\n' "$medic_doom_remove_source" | grep -Fc 'buff.applyBuff(self, self, "me_doom", 10.0f);')" -eq 2
awk -F '\t' '
BEGIN {
    split("dt_vulnerability_acid dt_vulnerability_cold dt_vulnerability_electricity dt_vulnerability_exclusive_acid dt_vulnerability_exclusive_cold dt_vulnerability_exclusive_electricity dt_vulnerability_exclusive_heat dt_vulnerability_heat", names, " ")
    for (i = 1; i <= 8; i++) expected[names[i]] = 1
}
NR == 1 {
    for (column = 1; column <= NF; column++) {
        header = $column
        sub(/\r$/, "", header)
        fieldIndex[header] = column
    }
    next
}
NR > 2 {
    name = $(fieldIndex["NAME"])
    if (name in expected) {
        found[name]++
        if ($(fieldIndex["TYPE"]) != "vulnerability" || $(fieldIndex["SUBTYPE"]) != name) exit 2
    }
}
END {
    total = 0
    for (name in expected) {
        if (found[name] != 1) exit 3
        total += found[name]
    }
    if (total != 8) exit 4
}
' "$work_buff_effect_mapping"
awk -F '\t' '
BEGIN {
    expected["acid_aspect|-1|0|1|dt_vulnerability_exclusive_electricity|100"] = 1
    expected["caretaker_blast|30|1|1|dt_vulnerability_electricity|2"] = 1
    expected["closed_fist_burn_debuff_1|60|1|1|dt_vulnerability_heat|2"] = 1
    expected["closed_fist_burn_debuff_2|60|1|1|dt_vulnerability_heat|4"] = 1
    expected["closed_fist_burn_debuff_3|60|1|1|dt_vulnerability_heat|8"] = 1
    expected["cold_aspect|-1|0|1|dt_vulnerability_exclusive_heat|100"] = 1
    expected["elec_aspect|-1|0|1|dt_vulnerability_exclusive_acid|100"] = 1
    expected["heat_aspect|-1|0|1|dt_vulnerability_exclusive_cold|100"] = 1
    expected["kun_wrath_ward_acid|10|0|1|dt_vulnerability_acid|0.1"] = 1
    expected["kun_wrath_ward_cold|10|0|1|dt_vulnerability_cold|0.1"] = 1
    expected["kun_wrath_ward_electrical|10|0|1|dt_vulnerability_electricity|0.1"] = 1
    expected["kun_wrath_ward_heat|10|0|1|dt_vulnerability_heat|0.1"] = 1
}
NR == 1 {
    for (column = 1; column <= NF; column++) {
        header = $column
        sub(/\r$/, "", header)
        fieldIndex[header] = column
    }
    next
}
NR > 2 {
    vulnerability = 0
    for (effect = 1; effect <= 5; effect++) {
        param = $(fieldIndex["EFFECT" effect "_PARAM"])
        if (param ~ /^dt_vulnerability_/) vulnerability = 1
    }
    if (vulnerability) {
        signature = $(fieldIndex["NAME"]) "|" $(fieldIndex["DURATION"]) "|" $(fieldIndex["DEBUFF"]) "|" $(fieldIndex["IS_PERSISTENT"]) "|" $(fieldIndex["EFFECT1_PARAM"]) "|" $(fieldIndex["EFFECT1_VALUE"])
        found[signature]++
        rows++
        if (!(signature in expected)) exit 2
    }
}
END {
    if (rows != 12) exit 3
    for (signature in expected) if (found[signature] != 1) exit 4
}
' "$work_buff_table"
grep -Fq 'RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_EFFECT_PREFIX = "dt_vulnerability_"' "$work_buff_library"
grep -Fq 'RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_STATE = "elemental_vulnerability"' "$work_buff_library"
elemental_vulnerability_effect_source="$(sed -n '/public static boolean isRetiredPostNgePlayerElementalVulnerabilityEffect/,/public static boolean isRetiredPostNgePlayerElementalVulnerabilityBuff/p' "$work_buff_library")"
printf '%s\n' "$elemental_vulnerability_effect_source" | grep -Fq 'effectName.startsWith(RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_EFFECT_PREFIX)'
elemental_vulnerability_predicate_source="$(sed -n '/public static boolean isRetiredPostNgePlayerElementalVulnerabilityBuff/,/public static void clearPostNgePlayerElementalVulnerabilityState/p' "$work_buff_library")"
printf '%s\n' "$elemental_vulnerability_predicate_source" | grep -Fq '!isPlayer(target)'
printf '%s\n' "$elemental_vulnerability_predicate_source" | grep -Fq 'effect <= MAX_EFFECTS'
printf '%s\n' "$elemental_vulnerability_predicate_source" | grep -Fq 'isRetiredPostNgePlayerElementalVulnerabilityEffect(getEffectParam(data, effect))'
elemental_vulnerability_clear_source="$(sed -n '/public static void clearPostNgePlayerElementalVulnerabilityState/,/public static void retirePostNgePlayerElementalVulnerabilityState/p' "$work_buff_library")"
printf '%s\n' "$elemental_vulnerability_clear_source" | grep -Fq '!isPlayer(player)'
printf '%s\n' "$elemental_vulnerability_clear_source" | grep -Fq 'utils.removeScriptVarTree(player, RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_STATE);'
elemental_vulnerability_cleanup_source="$(sed -n '/public static void retirePostNgePlayerElementalVulnerabilityState/,/private static final String RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_BUFF/p' "$work_buff_library")"
printf '%s\n' "$elemental_vulnerability_cleanup_source" | grep -Fq 'getAllBuffs(player)'
printf '%s\n' "$elemental_vulnerability_cleanup_source" | grep -Fq 'combat_engine.getBuffData(activeBuff)'
printf '%s\n' "$elemental_vulnerability_cleanup_source" | grep -Fq 'removeBuff(player, activeBuff)'
printf '%s\n' "$elemental_vulnerability_cleanup_source" | grep -Fq 'clearPostNgePlayerElementalVulnerabilityState(player);'
test "$(grep -Fc 'retirePostNgePlayerElementalVulnerabilityState(player);' "$work_buff_library")" -eq 1
elemental_vulnerability_admission_source="$(sed -n '/public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)/,/public static int\[\] getGroups(buff_data bdata)/p' "$work_buff_library")"
elemental_vulnerability_admission_line="$(printf '%s\n' "$elemental_vulnerability_admission_source" | grep -Fn 'isRetiredPostNgePlayerElementalVulnerabilityBuff(target, bdata)' | head -1 | cut -d: -f1)"
elemental_vulnerability_existing_line="$(printf '%s\n' "$elemental_vulnerability_admission_source" | grep -Fn 'if (hasBuff(target, nameCrc))' | head -1 | cut -d: -f1)"
test -n "$elemental_vulnerability_admission_line"
test -n "$elemental_vulnerability_existing_line"
test "$elemental_vulnerability_admission_line" -lt "$elemental_vulnerability_existing_line"
elemental_vulnerability_add_source="$(sed -n '/public int vulnerabilityAddBuffHandler/,/public void clog/p' "$work_buff_handler")"
elemental_vulnerability_add_guard_line="$(printf '%s\n' "$elemental_vulnerability_add_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
elemental_vulnerability_add_cleanup_line="$(printf '%s\n' "$elemental_vulnerability_add_source" | grep -Fn 'buff.retirePostNgePlayerElementalVulnerabilityState(self);' | head -1 | cut -d: -f1)"
elemental_vulnerability_add_override_line="$(printf '%s\n' "$elemental_vulnerability_add_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
elemental_vulnerability_add_writer_line="$(printf '%s\n' "$elemental_vulnerability_add_source" | grep -Fn 'utils.setScriptVar(self, "elemental_vulnerability.type_" + type, type);' | head -1 | cut -d: -f1)"
test "$elemental_vulnerability_add_guard_line" -lt "$elemental_vulnerability_add_cleanup_line"
test "$elemental_vulnerability_add_cleanup_line" -lt "$elemental_vulnerability_add_override_line"
test "$elemental_vulnerability_add_override_line" -lt "$elemental_vulnerability_add_writer_line"
test "$(printf '%s\n' "$elemental_vulnerability_add_source" | grep -Fc 'utils.setScriptVar(self, "elemental_vulnerability.type_')" -eq 3
elemental_vulnerability_remove_source="$(sed -n '/public int vulnerabilityRemoveBuffHandler/,/public int removeIncapWeakenAddBuffHandler/p' "$work_buff_handler")"
elemental_vulnerability_remove_guard_line="$(printf '%s\n' "$elemental_vulnerability_remove_source" | grep -Fn 'if (isPlayer(self))' | head -1 | cut -d: -f1)"
elemental_vulnerability_remove_cleanup_line="$(printf '%s\n' "$elemental_vulnerability_remove_source" | grep -Fn 'buff.clearPostNgePlayerElementalVulnerabilityState(self);' | head -1 | cut -d: -f1)"
elemental_vulnerability_remove_override_line="$(printf '%s\n' "$elemental_vulnerability_remove_source" | grep -Fn 'return SCRIPT_OVERRIDE;' | head -1 | cut -d: -f1)"
elemental_vulnerability_remove_writer_line="$(printf '%s\n' "$elemental_vulnerability_remove_source" | grep -Fn 'utils.removeScriptVar(self, "elemental_vulnerability.type_" + type);' | head -1 | cut -d: -f1)"
test "$elemental_vulnerability_remove_guard_line" -lt "$elemental_vulnerability_remove_cleanup_line"
test "$elemental_vulnerability_remove_cleanup_line" -lt "$elemental_vulnerability_remove_override_line"
test "$elemental_vulnerability_remove_override_line" -lt "$elemental_vulnerability_remove_writer_line"
test "$(printf '%s\n' "$elemental_vulnerability_remove_source" | grep -Fc 'utils.removeScriptVar(self, "elemental_vulnerability.type_')" -eq 3
elemental_vulnerability_consumer_source="$(sed -n '/public void doWrappedDamage(obj_id attacker, obj_id defender, weapon_data weaponData, hit_result hitData, combat_data actionData, int overloadDamage)/,/public obj_id\[\] truncateTargetArray/p' "$work_combat_base")"
elemental_vulnerability_consumer_guard_line="$(printf '%s\n' "$elemental_vulnerability_consumer_source" | grep -Fn 'if (isPlayer(defender) && utils.hasScriptVarTree(defender, "elemental_vulnerability"))' | head -1 | cut -d: -f1)"
elemental_vulnerability_consumer_cleanup_line="$(printf '%s\n' "$elemental_vulnerability_consumer_source" | grep -Fn 'buff.retirePostNgePlayerElementalVulnerabilityState(defender);' | head -1 | cut -d: -f1)"
elemental_vulnerability_consumer_first_read_line="$(printf '%s\n' "$elemental_vulnerability_consumer_source" | grep -Fn 'utils.hasScriptVar(defender, "elemental_vulnerability.type_heat")' | head -1 | cut -d: -f1)"
test "$elemental_vulnerability_consumer_guard_line" -lt "$elemental_vulnerability_consumer_cleanup_line"
test "$elemental_vulnerability_consumer_cleanup_line" -lt "$elemental_vulnerability_consumer_first_read_line"
test "$(printf '%s\n' "$elemental_vulnerability_consumer_source" | grep -Ec 'if \(!isPlayer\(defender\) && utils\.hasScriptVar\(defender, "elemental_vulnerability\.type_(heat|electrical|cold|acid)"\)\)')" -eq 4
legacy_item_combat_level_pattern='required[ _]combat[ _]level|combat[ _]level[ _]required|healing_combat_level_required|healing\.combat_level_required'
! grep -E -i -q "$legacy_item_combat_level_pattern" "$work_item_stats_table"
! grep -E -i -q "$legacy_item_combat_level_pattern" "$work_advanced_search_table"
for precu_stim_template_path in $precu_stim_template_paths; do
    ! grep -E -i -q "$legacy_item_combat_level_pattern" "$work_medicine_template_root/$precu_stim_template_path"
done
retained_stim_rows='item_stimpack_a_02_01=700 item_stimpack_b_02_01=1600 item_stimpack_c_02_01=2800 item_stimpack_d_02_01=4000 item_stimpack_e_02_01=4800 item_tow_commander_stim_04_01=1500 item_content_stim_donuts_02_01=485 item_content_stim_fish_02_01=485 item_content_stim_dragonet_steak_02_01=485 item_content_stimpack_high_03_01=4500 item_content_stimpack_high_04_01=4500 item_gcw_base_health_a_03_01=3500 item_gcw_base_health_b_03_01=4000 item_gcw_base_health_c_03_01=4500 item_gcw_base_health_d_03_01=5000 item_gcw_base_health_e_04_01=5500 item_gcw_base_action_a_03_01=1750 item_gcw_base_action_b_03_01=2000 item_gcw_base_action_c_03_01=2250 item_gcw_base_action_d_03_01=2500 item_gcw_base_action_e_04_01=2750 item_off_temp_stimpack_02_01=945 item_off_temp_stimpack_02_02=1505 item_off_temp_stimpack_02_03=1910 item_off_temp_stimpack_02_04=2485 item_off_temp_stimpack_02_05=2975 item_off_temp_stimpack_02_06=3465'
for retained_stim_row in $retained_stim_rows; do
    retained_stim_name="${retained_stim_row%%=*}"
    retained_stim_power="${retained_stim_row#*=}"
    awk -F '\t' -v name="$retained_stim_name" -v power="$retained_stim_power" '$1 == name { found++; if (index($4, "int:healing.power=" power) == 0) exit 2 } END { if (found != 1) exit 3 }' "$work_item_stats_table"
    awk -F '\t' -v name="$retained_stim_name" '$1 == name { found++; if ($11 !~ /(^|,)item[.]medicine[.]stimpack(,|$)/) exit 2 } END { if (found != 1) exit 3 }' "$work_master_item_table"
done
awk -F '\t' '$1 ~ /^item_gcw_base_action_[a-e]_/ { found++; if (index($4, "int:healing.pool=2") == 0) exit 2 } END { if (found != 5) exit 3 }' "$work_item_stats_table"
awk -F '\t' 'NR > 2 && $1 != "" { found++ } END { if (found != 134) exit 2 }' "$work_advanced_search_table"
test "$(awk -F '\t' '$1 == "misc_container_wearable" && $2 == "bio_link" { found++ } END { print found + 0 }' "$work_advanced_search_table")" -eq 1
grep -Fq 'objvars =+ ["healing.power" = 1000]' "$work_medicine_template_root/channelled_stimpack/stimpack_a.tpf"
grep -Fq 'objvars =+ ["healing.power" = 2000]' "$work_medicine_template_root/channelled_stimpack/stimpack_b.tpf"
grep -Fq 'objvars =+ ["healing.power" = 4000]' "$work_medicine_template_root/channelled_stimpack/stimpack_c.tpf"
test "$(grep -Fh 'scripts = ["item.medicine.stimpack_crafted"]' "$work_medicine_template_root"/channelled_stimpack/stimpack_?.tpf | wc -l)" -eq 3
grep -Fq 'objvars =+ ["noTrade" = 1]' "$work_medicine_template_root/instant_stimpack/stimpack_noob.tpf"
grep -Fq 'objvars =+ ["healing.power" = 1500, "charges" = 3]' "$work_medicine_template_root/instant_stimpack/stimpack_syren.tpf"
! grep -E -i -q "$legacy_item_combat_level_pattern" "$work_script/systems/crafting/weapon/component/crafting_weapon_component_attribute.java"
grep -Fq 'int coreLevel = 0' "$work_script/systems/crafting/weapon/component/crafting_weapon_component_attribute.java"
grep -Fq 'weapons.getWeaponCoreData(coreLevel)' "$work_script/systems/crafting/weapon/component/crafting_weapon_component_attribute.java"
dynamic_generation_source="$(sed -n '/public static void generateItemStatBonuses(/,/public static void removeLegacyNgeDynamicPrimaryModifiers(/p' "$work_script/library/static_item.java")"
dynamic_cleanup_source="$(sed -n '/public static void removeLegacyNgeDynamicPrimaryModifiers(/,/public static int generateStatMod(/p' "$work_script/library/static_item.java")"
dynamic_suffix_source="$(sed -n '/public static String getArmorNameSuffix(/,/public static void setupJunkDealerPrice(/p' "$work_script/library/static_item.java")"
static_modifier_predicate_source="$(sed -n '/public static boolean isRetiredNgeStaticItemSkillModifier(/,/public static void removeRetiredNgeStaticItemSkillModifiers(/p' "$work_script/library/static_item.java")"
static_modifier_cleanup_source="$(sed -n '/public static void removeRetiredNgeStaticItemSkillModifiers(/,/public static void applyPrecuStaticItemSkillModifiers(/p' "$work_script/library/static_item.java")"
static_modifier_apply_source="$(sed -n '/public static void applyPrecuStaticItemSkillModifiers(/,/public static boolean initializeArmor(/p' "$work_script/library/static_item.java")"
printf '%s\n' "$static_modifier_predicate_source" | grep -Fq 'modifier.startsWith("expertise_")'
printf '%s\n' "$static_modifier_predicate_source" | grep -Fq 'modifier.startsWith("fast_attack_line_")'
printf '%s\n' "$static_modifier_predicate_source" | grep -Fq 'modifier.startsWith("bm_")'
printf '%s\n' "$static_modifier_predicate_source" | grep -Fq 'LEGACY_NGE_DYNAMIC_PRIMARY_MODIFIERS'
printf '%s\n' "$static_modifier_predicate_source" | grep -Fq 'RETIRED_NGE_STATIC_ITEM_MODIFIERS'
printf '%s\n' "$static_modifier_cleanup_source" | grep -Fq 'getSkillModBonuses(item)'
printf '%s\n' "$static_modifier_cleanup_source" | grep -Fq 'setSkillModBonus(item, modifier, 0)'
printf '%s\n' "$static_modifier_apply_source" | grep -Fq 'removeRetiredNgeStaticItemSkillModifiers(item)'
printf '%s\n' "$static_modifier_apply_source" | grep -Fq 'parseSkillModifiers(null, skillMods)'
printf '%s\n' "$static_modifier_apply_source" | grep -Fq 'setSkillModBonus(item, modifier, bonuses.getInt(modifier))'
test "$(grep -Fc 'applyPrecuStaticItemSkillModifiers(object, skillMods);' "$work_script/library/static_item.java")" -eq 3
! grep -Fq 'setSkillModBonus(object,' "$work_script/library/static_item.java"
grep -Fq 'static_item.initializeObject(self, itemData)' "$work_script/item/static_item_base.java"
printf '%s\n' "$static_modifier_predicate_source" | grep -Fq 'RETIRED_NGE_ITEM_WRITER_MODIFIERS'
for retired_item_writer_modifier in combat_critical_hit_reduction combat_dodge combat_parry combat_evasion_chance combat_evasion_value combat_strikethrough_value commando_devastation exotic_heal_action_reduction exotic_dodge_reduction exotic_parry_reduction exotic_acid_penetration exotic_cold_penetration exotic_heat_penetration exotic_electricity_penetration; do
    test "$(grep -Fc "\"$retired_item_writer_modifier\"" "$work_script/library/static_item.java")" -eq 1
done
reverse_basic_modifier_source="$(sed -n '/public static final String\[\] BASIC_MOD_LIST/,/public static final String\[\] FINAL_ATTACHMENT_TEMPLATE/p' "$work_script/item/tool/reverse_engineering_tool.java")"
for precu_reverse_basic_modifier in general_assembly weapon_assembly armor_assembly clothing_assembly droid_assembly food_assembly; do
    test "$(printf '%s\n' "$reverse_basic_modifier_source" | grep -Fc "\"$precu_reverse_basic_modifier\"")" -eq 1
done
printf '%s\n' "$reverse_basic_modifier_source" | grep -Fq '"camouflage"'
printf '%s\n' "$reverse_basic_modifier_source" | grep -Fq '"droid_find_speed"'
for retired_reverse_primary in precision_modified strength_modified stamina_modified constitution_modified agility_modified luck_modified; do
    ! grep -Fq "\"$retired_reverse_primary\"" "$work_script/item/tool/reverse_engineering_tool.java"
done
test "$(grep -Fc 'static_item.isRetiredNgeStaticItemSkillModifier' "$work_script/item/tool/reverse_engineering_tool.java")" -eq 4
test "$(grep -Fc 'isRetiredNgePowerupModifier' "$work_script/library/reverse_engineering.java")" -eq 4
grep -Fq 'removeAttribOrSkillModModifier(player, slotName + "_powerup")' "$work_script/library/reverse_engineering.java"
grep -Fq 'removeModsAndScript(player, item)' "$work_script/library/reverse_engineering.java"
test "$(grep -Fc 'reverse_engineering.isRetiredNgePowerupModifier(self)' "$work_script/item/tool/reverse_engineering_poweredup_item.java")" -eq 2
test "$(grep -Fc 'reverse_engineering.retireNgePowerupModifier(player, self)' "$work_script/item/tool/reverse_engineering_poweredup_item.java")" -eq 2
grep -Fq 'getPrecuMagicItemMods(mods)' "$work_script/library/magic_item.java"
grep -Fq 'getPrecuMagicItemMods(dataTableGetStringColumn(TBL_COST, "MOD"))' "$work_script/library/magic_item.java"
grep -Fq '!static_item.isRetiredNgeStaticItemSkillModifier(modifierName)' "$work_script/library/magic_item.java"
grep -Fq 'static_item.isRetiredNgeStaticItemSkillModifier(modifier)' "$work_script/systems/crafting/crafting_base.java"
grep -Fq 'static_item.isRetiredNgeStaticItemSkillModifier(mod_name)' "$work_script/library/consumable.java"
test "$(grep -Ec 'static_item.isRetiredNgeStaticItemSkillModifier\(skill[12]\)' "$work_script/item/skill_buff/base.java")" -eq 2
grep -Fq 'bio_engineer.BIO_COMP_EFFECT_SKILL_MODS' "$work_script/systems/crafting/clothing/crafting_base_clothing.java"
grep -Fq 'setSkillModBonus(prototype, skill_mod, mod_val[i])' "$work_script/systems/crafting/clothing/crafting_base_clothing.java"
for precu_medical_item_modifier in resistance_poison absorption_poison resistance_disease absorption_disease; do
    grep -Fq "\"$precu_medical_item_modifier\"" "$work_script/library/consumable.java"
done
grep -Eq '^expertise_damage_weapon_0[[:space:]]' "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/crafting/reverse_engineering_mods.tab"
grep -Eq '^general_assembly[[:space:]]' "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/crafting/reverse_engineering_mods.tab"
grep -Eq '^bm_xp_mod_boost[[:space:]]' "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/crafting/reverse_engineering_special_mods.tab"
grep -Eq '^armor_assembly[[:space:]]' "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/crafting/reverse_engineering_special_mods.tab"
grep -Eq '^precision_modified[[:space:]]' "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/magic_item/mod_cost.tab"
for item_writer_parity_path in item/skill_buff/base.java item/tool/reverse_engineering_poweredup_item.java item/tool/reverse_engineering_tool.java library/consumable.java library/magic_item.java library/reverse_engineering.java library/static_item.java systems/crafting/crafting_base.java systems/crafting/clothing/crafting_base_clothing.java; do
    cmp -s "$source_script/$item_writer_parity_path" "$work_script/$item_writer_parity_path"
done
for static_modifier_table_profile in \
    "$work_armor_stats_table:1559:1326:0:0:0" \
    "$work_weapon_stats_table:325:126:0:0:0" \
    "$work_item_stats_table:4793:1113:129:67:99"
do
    static_modifier_table="${static_modifier_table_profile%%:*}"
    static_modifier_expected="${static_modifier_table_profile#*:}"
    static_modifier_rows="${static_modifier_expected%%:*}"
    static_modifier_expected="${static_modifier_expected#*:}"
    static_modifier_primary_rows="${static_modifier_expected%%:*}"
    static_modifier_expected="${static_modifier_expected#*:}"
    static_modifier_expertise_rows="${static_modifier_expected%%:*}"
    static_modifier_expected="${static_modifier_expected#*:}"
    static_modifier_additional_rows="${static_modifier_expected%%:*}"
    static_modifier_additional_occurrences="${static_modifier_expected#*:}"
    awk -F '\t' -v expected_rows="$static_modifier_rows" -v expected_primary="$static_modifier_primary_rows" -v expected_expertise="$static_modifier_expertise_rows" -v expected_additional="$static_modifier_additional_rows" -v expected_occurrences="$static_modifier_additional_occurrences" '
        NR == 1 { for (i = 1; i <= NF; i++) if ($i == "skill_mods") skillmods = i; next }
        NR == 2 { next }
        $1 != "" {
            rows++
            primary = 0
            expertise = 0
            additional = 0
            count = split($skillmods, entries, ",")
            for (entry = 1; entry <= count; entry++) {
                split(entries[entry], pair, "=")
                modifier = pair[1]
                gsub(/^"|"$/, "", modifier)
                if (modifier == "precision_modified" || modifier == "strength_modified" || modifier == "stamina_modified" || modifier == "constitution_modified" || modifier == "agility_modified" || modifier == "luck_modified") primary = 1
                if (index(modifier, "expertise_") == 1) expertise = 1
                if (modifier == "bh_dire_root" || modifier == "bh_dire_snare" || modifier == "combat_block_chance" || modifier == "combat_block_value" || modifier == "combat_strikethrough_chance" || modifier == "cooldown_percent_of_group_buff" || modifier == "incubation_time_reduction" || modifier == "rally_point_duration" || modifier == "tka_armor" || index(modifier, "fast_attack_line_") == 1 || index(modifier, "bm_") == 1) {
                    additional = 1
                    additional_occurrences++
                }
            }
            primary_rows += primary
            expertise_rows += expertise
            additional_rows += additional
        }
        END { if (!skillmods || rows != expected_rows || primary_rows != expected_primary || expertise_rows != expected_expertise || additional_rows != expected_additional || additional_occurrences != expected_occurrences) exit 2 }
    ' "$static_modifier_table"
done
for listed_nge_static_modifier in bh_dire_root bh_dire_snare combat_block_chance combat_block_value combat_strikethrough_chance cooldown_percent_of_group_buff incubation_time_reduction tka_armor; do
    grep -Eq "^${listed_nge_static_modifier}[[:space:]]" "$work_skill_mod_listing"
done
grep -Eq '^fast_attack_line_[^[:space:]]+[[:space:]]' "$work_skill_mod_listing"
grep -Eq '^bm_incubator_dps_armor[[:space:]]' "$work_skill_mod_listing"
grep -Eq '^tka_armor[[:space:]].*Innate Teras Kasi Armor' "$work_skill_mod_listing"
grep -Eq '^combat_bountyhunter_(master|investigation_0[1-3])[[:space:]].*droid_find_speed=' "$work_skills"
! printf '%s\n%s\n' "$static_modifier_predicate_source" "$static_modifier_cleanup_source" | grep -Eq 'droid_find_speed|resistance_|absorption_'
printf '%s\n' "$dynamic_generation_source" | grep -Fq 'removeLegacyNgeDynamicPrimaryModifiers(item)'
test "$(printf '%s\n' "$dynamic_generation_source" | grep -Fc 'setObjVar(')" -eq 1
printf '%s\n' "$dynamic_generation_source" | grep -Fq 'setObjVar(item, "skillmod.bonus.camouflage", camouflageBonus)'
printf '%s\n' "$dynamic_cleanup_source" | grep -Fq 'for (String modifier : LEGACY_NGE_DYNAMIC_PRIMARY_MODIFIERS)'
printf '%s\n' "$dynamic_cleanup_source" | grep -Fq 'removeObjVar(item, objVar)'
! printf '%s\n' "$dynamic_cleanup_source" | grep -Fq 'removeObjVar(item, "skillmod.bonus")'
printf '%s\n' "$dynamic_suffix_source" | grep -Fq 'removeLegacyNgeDynamicPrimaryModifiers(item)'
printf '%s\n' "$dynamic_suffix_source" | grep -Fq '"camouflage"'
for legacy_dynamic_primary in precision_modified strength_modified stamina_modified constitution_modified agility_modified luck_modified; do
    test "$(grep -Fc "\"$legacy_dynamic_primary\"" "$work_script/library/static_item.java")" -eq 1
    ! printf '%s\n' "$dynamic_generation_source" | grep -Fq "$legacy_dynamic_primary"
    ! printf '%s\n' "$dynamic_suffix_source" | grep -Fq "$legacy_dynamic_primary"
done
test "$(grep -Fc 'static_item.removeLegacyNgeDynamicPrimaryModifiers(self);' "$work_script/item/armor/dynamic_armor.java")" -eq 3
grep -Fq 'static_item.makeDynamicObject(strLootToMake, objContainer, intLevel)' "$work_script/library/loot.java"
grep -Fq 'dynamic_armor_standard' "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/dynamic_item/types/armor.tab"
grep -Fq 'dynamic_clothing_standard' "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/item/dynamic_item/types/clothing.tab"
grep -Eq '^species_bothan[[:space:]].*camouflage=15' "$work_skills"
grep -Eq '^outdoors_ranger_(master|movement_01)[[:space:]].*camouflage=' "$work_skills"
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
# Camp XP is granted only from compiled Publish 14.1 camp lifecycle classes,
# and healing credit reaches it only through the explicit native observer seam.
for camp_xp_class in \
    script/base_class.class \
    script/library/camping.class \
    script/library/healing.class \
    script/library/consumable.class \
    script/player/base/base_player.class \
    script/player/cmd/quick_heal.class \
    script/systems/buff/buff_handler.class \
    script/systems/camping/camp_master.class \
    script/systems/camping/camp_controlpanel.class \
    script/event/event_tool.class \
    script/item/medicine/stimpack.class \
    script/item/medicine/stimpack_crafted.class \
    script/item/medicine/stimpack_other.class
do
    test -f "$class_root/$camp_xp_class"
done
base_class_camp_signatures="$(javap -classpath "$class_root" -constants -p script.base_class)"
printf '%s\n' "$base_class_camp_signatures" | grep -Fq 'TRIG_HEALING_RECEIVED = 308'
printf '%s\n' "$base_class_camp_signatures" | grep -Fq '_healDamage(long, long, int, int, boolean)'
printf '%s\n' "$base_class_camp_signatures" | grep -Fq 'applyDamageHealing(script.obj_id, script.obj_id, int, int, boolean)'

camping_constants="$(javap -classpath "$class_root" -constants -p script.library.camping)"
printf '%s\n' "$camping_constants" | grep -Fq 'HEARTBEAT_RESTORE = 60.0f'
printf '%s\n' "$camping_constants" | grep -Fq 'CAMP_NATURAL_EXPIRY = 3300.0f'
printf '%s\n' "$camping_constants" | grep -Fq 'CAMP_XP_DURATION = 3600'
printf '%s\n' "$camping_constants" | grep -Fq 'CAMP_XP_FULL_DURATION = 900'
printf '%s\n' "$camping_constants" | grep -Fq 'registerCampVisitor(script.obj_id, script.obj_id)'
printf '%s\n' "$camping_constants" | grep -Fq 'recordCampHealingEvent(script.obj_id)'
printf '%s\n' "$camping_constants" | grep -Fq 'calculateCampExperience(script.obj_id)'
printf '%s\n' "$camping_constants" | grep -Fq 'claimCampExperience(script.obj_id)'
printf '%s\n' "$camping_constants" | grep -Fq 'awardCampExperienceAndNuke(script.obj_id)'
camping_verbose="$(javap -classpath "$class_root" -v script.library.camping)"
for camp_state_marker in \
    camp.healingXp camp.uniqueVisitors camp.xpClaimed \
    camp.abandonSequence camp.abandonPending
do
    printf '%s\n' "$camping_verbose" | grep -Fq "$camp_state_marker"
done
camping_code="$(javap -classpath "$class_root" -c -p script.library.camping)"
record_camp_healing_code="$(printf '%s\n' "$camping_code" | sed -n '/recordCampHealingEvent/,/calculateCampExperience/p')"
calculate_camp_xp_code="$(printf '%s\n' "$camping_code" | sed -n '/calculateCampExperience/,/claimCampExperience/p')"
claim_camp_xp_code="$(printf '%s\n' "$camping_code" | sed -n '/claimCampExperience/,/awardCampExperienceAndNuke/p')"
printf '%s\n' "$record_camp_healing_code" | grep -Eq 'sipush[[:space:]]+180'
printf '%s\n' "$calculate_camp_xp_code" | grep -Eq 'bipush[[:space:]]+30'
printf '%s\n' "$calculate_camp_xp_code" | grep -Eq 'ldc.*float 900\.0f'
printf '%s\n' "$claim_camp_xp_code" | grep -Fq 'script/library/pclib.msgGrantXP'
printf '%s\n' "$claim_camp_xp_code" | grep -Fq 'String camp'
! printf '%s\n' "$claim_camp_xp_code" | grep -Fq 'script/library/group.'

camp_master_code="$(javap -classpath "$class_root" -c -p script.systems.camping.camp_master)"
camp_panel_code="$(javap -classpath "$class_root" -c -p script.systems.camping.camp_controlpanel)"
printf '%s\n' "$camp_master_code" | grep -Fq 'handleCampNaturalExpiry'
printf '%s\n' "$camp_master_code" | grep -Fq 'handleCampHealingReceived'
printf '%s\n' "$camp_master_code" | grep -Fq 'handleCampRestoreHeartbeat'
test "$(printf '%s\n' "$camp_master_code" | grep -Fc 'script/library/camping.nukeCamp')" -eq 12
test "$(printf '%s\n' "$camp_master_code" | grep -Fc 'script/library/camping.awardCampExperienceAndNuke')" -eq 1
test "$(printf '%s\n' "$camp_panel_code" | grep -Fc 'script/library/camping.awardCampExperienceAndNuke')" -eq 1
! printf '%s\n' "$camp_panel_code" | grep -Fq 'script/library/camping.nukeCamp'

base_player_camp_code="$(javap -classpath "$class_root" -c -p script.player.base.base_player)"
printf '%s\n' "$base_player_camp_code" | grep -Fq 'OnHealingReceived'
printf '%s\n' "$base_player_camp_code" | grep -Fq 'handleHealOverTimeTick'
printf '%s\n' "$base_player_camp_code" | grep -Fq 'script/library/camping.getCurrentCamp'
printf '%s\n' "$base_player_camp_code" | grep -Fq 'handleCampHealingReceived'
printf '%s\n' "$base_player_camp_code" | grep -Fq 'notifyCampHealing'

healing_camp_code="$(javap -classpath "$class_root" -c -p script.library.healing)"
printf '%s\n' "$healing_camp_code" | grep -Fq 'applyDamageHealing'
printf '%s\n' "$healing_camp_code" | grep -Fq 'performHealDamage'
printf '%s\n' "$healing_camp_code" | grep -Fq 'startHealOverTime'
printf '%s\n' "$healing_camp_code" | grep -Fq 'useHealDamageItem'
source_aware_heal_code="$(printf '%s\n' "$healing_camp_code" | sed -n '/public static int healDamage(script.obj_id, script.obj_id, int, int) throws/,/public static int healDamage(script.obj_id, script.obj_id, int, int, boolean) throws/p')"
test "$(printf '%s\n' "$source_aware_heal_code" | grep -Fc 'healDamage:(Lscript/obj_id;Lscript/obj_id;IIZ)I')" -eq 1
test "$(printf '%s\n' "$source_aware_heal_code" | grep -Fc 'script/library/pvp.bfCreditForHealing')" -eq 1
classic_stim_heal_code="$(printf '%s\n' "$healing_camp_code" | sed -n '/useHealDamageItem(script.obj_id, script.obj_id, script.obj_id, int)/,/useChannelHealItem/p')"
test "$(printf '%s\n' "$classic_stim_heal_code" | grep -Fc 'healDamage:(Lscript/obj_id;Lscript/obj_id;IIZ)I')" -eq 1
test "$(printf '%s\n' "$classic_stim_heal_code" | grep -Fc 'script/library/pvp.bfCreditForHealing')" -eq 1

consumable_camp_code="$(javap -classpath "$class_root" -c -p script.library.consumable)"
printf '%s\n' "$consumable_camp_code" | grep -Fq 'script/library/healing.isRevivePack'
printf '%s\n' "$consumable_camp_code" | grep -Fq 'script/library/healing.isMedicine'
printf '%s\n' "$consumable_camp_code" | grep -Fq 'script/library/healing.healDamage:(Lscript/obj_id;Lscript/obj_id;IIZ)I'
quick_heal_code="$(javap -classpath "$class_root" -c -p script.player.cmd.quick_heal)"
test "$(printf '%s\n' "$quick_heal_code" | grep -Fc 'script/library/healing.healDamage:(Lscript/obj_id;Lscript/obj_id;IIZ)I')" -eq 2
heal_mind_code="$(printf '%s\n' "$base_player_camp_code" | sed -n '/public int healMind(/,/private boolean isPrecuHealMindFixture/p')"
test "$(printf '%s\n' "$heal_mind_code" | grep -Fc 'script/library/healing.healDamage:(Lscript/obj_id;Lscript/obj_id;II)I')" -eq 1
avoid_incap_heal_code="$(printf '%s\n' "$base_player_camp_code" | sed -n '/public boolean performCriticalHeal(/,/public void sendSmugglerSystemBootstrap/p')"
test "$(printf '%s\n' "$avoid_incap_heal_code" | grep -Fc 'script/library/healing.healDamage:(Lscript/obj_id;Lscript/obj_id;IIZ)I')" -eq 1
healing_buff_code="$(javap -classpath "$class_root" -c -p script.systems.buff.buff_handler | sed -n '/public int healEffectAddBuffHandler(/,/public int healEffectRemoveBuffHandler/p')"
test "$(printf '%s\n' "$healing_buff_code" | grep -Fc 'script/library/healing.healDamage:(Lscript/obj_id;Lscript/obj_id;IIZ)I')" -eq 1
event_damage_code="$(javap -classpath "$class_root" -c -p script.event.event_tool | sed -n '/public int eventDamage(/,/public int eventMoveToMe/p')"
test "$(printf '%s\n' "$event_damage_code" | grep -Fc 'script/library/healing.healDamage:(Lscript/obj_id;Lscript/obj_id;IIZ)I')" -eq 1
for classic_stim_class in \
    script.item.medicine.stimpack \
    script.item.medicine.stimpack_crafted \
    script.item.medicine.stimpack_other
do
    javap -classpath "$class_root" -c -p "$classic_stim_class" | grep -Fq 'script/library/healing.useHealDamageItem'
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
for retained_spy_freeshot_modifier in freeshot_case_miss freeshot_case_dodge freeshot_case_parry freeshot_case_crit freeshot_case_strikethrough; do
    javap -classpath "$class_root" -c -p script.library.combat | grep -Fq "$retained_spy_freeshot_modifier"
done
combat_base_code="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base)"
printf '%s' "$combat_base_code" | grep -Fq 'getPrecuPrimaryAttackResult'
printf '%s' "$combat_base_code" | grep -Fq 'getPrecuSecondaryDefenseResult'
printf '%s' "$combat_base_code" | grep -Fq 'getDefenderResult'
# Authenticated PRE-CU hit resolution is skill-modifier based. Combat level may
# remain in later-content helpers, but it cannot enter these three live methods.
hit_engine_bytecode="$(printf '%s' "$combat_base_code" | sed -n '/public script.combat_engine\$hit_result\[\] runHitEngine(.*boolean, boolean, int)/,/public void applyPrecuWounds/p')"
precu_primary_bytecode="$(printf '%s' "$combat_base_code" | sed -n '/public float getPrecuPrimaryHitChance/,/private int getPrecuActionAccuracyBonus/p')"
precu_secondary_bytecode="$(printf '%s' "$combat_base_code" | sed -n '/public int getPrecuSecondaryDefenseResult(script.combat_engine\$attacker_data/,/public int getPrecuSecondaryDefenseResultCode/p')"
for precu_hit_block in "$hit_engine_bytecode" "$precu_primary_bytecode" "$precu_secondary_bytecode"; do
    test -n "$precu_hit_block"
    ! printf '%s' "$precu_hit_block" | grep -Fq 'Method getLevel'
done
printf '%s' "$precu_primary_bytecode" | grep -Fq 'getEnhancedSkillStatisticModifierUncapped'
printf '%s' "$precu_secondary_bytecode" | grep -Fq 'getEnhancedSkillStatisticModifierUncapped'
combat_base_bytecode="$(javap -classpath "$class_root" -v script.systems.combat.combat_base)"
printf '%s' "$combat_base_bytecode" | grep -Fq 'glancing_blow'
! printf '%s' "$combat_base_bytecode" | grep -Fq 'expertise_fs_general_alacrity_1'
! printf '%s' "$combat_base_bytecode" | grep -Fq 'appearance/pt_jedi_alacrity.prt'
# Player-facing NGE profession respec entrypoints and the veteran migration
# primary-stat buff remain link-compatible but compile behind shared denial.
javap -classpath "$class_root" -c -p script.library.respec | grep -Fq 'retireNgePlayerRespecEntrypoint'
javap -classpath "$class_root" -v script.library.respec | grep -Fq 'retirePostNgePlayerMigrationState'
javap -classpath "$class_root" -v script.player.live_conversions | grep -Fq 'veteranPlayerBuff'
javap -classpath "$class_root" -v script.player.live_conversions | grep -Fq 'revokeCommand'
javap -classpath "$class_root" -v script.player.live_conversions | grep -Fq 'removeBuff'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeMigrationPlayerAction'
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
printf '%s' "$stance_bytecode" | grep -Fq 'isRetiredPostNgeForceSensitiveStanceBuff'
printf '%s' "$stance_bytecode" | grep -Fq 'retirePostNgeForceSensitiveStanceState'
invis_buff_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public void invisBuffAddBuffHandler/,/public void noBreakInvisRemoveBuffHandler/p')"
printf '%s' "$invis_buff_handler_bytecode" | grep -Fq 'isRetiredPostNgeForceSensitiveStanceBuff'
printf '%s' "$invis_buff_handler_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$invis_buff_handler_bytecode" | grep -Fq 'invisBuffAdded'
force_throw_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int forceThrowAddBuffHandler/,/public int forceThrowRemoveBuffHandler/p')"
force_throw_add_player_line="$(printf '%s\n' "$force_throw_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
force_throw_add_predicate_line="$(printf '%s\n' "$force_throw_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerForceThrowEffect' | head -1 | cut -d: -f1)"
force_throw_add_owner_line="$(printf '%s\n' "$force_throw_add_bytecode" | grep -Fn 'utils.getObjIdScriptVar' | head -1 | cut -d: -f1)"
test "$force_throw_add_player_line" -lt "$force_throw_add_predicate_line"
test "$force_throw_add_predicate_line" -lt "$force_throw_add_owner_line"
movement_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int movementAddBuffHandler/,/public int movementRemoveBuffHandler/p')"
movement_add_player_line="$(printf '%s\n' "$movement_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
movement_add_profession_predicate_line="$(printf '%s\n' "$movement_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerProfessionMovementBuffName' | head -1 | cut -d: -f1)"
movement_add_force_throw_predicate_line="$(printf '%s\n' "$movement_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerForceThrowBuffName' | head -1 | cut -d: -f1)"
movement_add_writer_line="$(printf '%s\n' "$movement_add_bytecode" | grep -Fn 'applyMovementModifier' | head -1 | cut -d: -f1)"
test "$movement_add_player_line" -lt "$movement_add_profession_predicate_line"
test "$movement_add_profession_predicate_line" -lt "$movement_add_force_throw_predicate_line"
test "$movement_add_force_throw_predicate_line" -lt "$movement_add_writer_line"
scriptvar_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int scriptVarAddBuffHandler/,/public int scriptVarRemoveBuffHandler/p')"
scriptvar_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int scriptVarRemoveBuffHandler/,/public int xpBonusAddBuffHandler/p')"
craft_bonus_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int craftBonusAddBuffHandler/,/public int craftBonusRemoveBuffHandler/p')"
craft_bonus_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int craftBonusRemoveBuffHandler/,/public int forcePowerAddBuffHandler/p')"
scriptvar_add_player_line="$(printf '%s\n' "$scriptvar_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
scriptvar_add_predicate_line="$(printf '%s\n' "$scriptvar_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerProfessionInspirationBuffName' | head -1 | cut -d: -f1)"
scriptvar_add_cleanup_line="$(printf '%s\n' "$scriptvar_add_bytecode" | grep -Fn 'clearPostNgePlayerProfessionInspirationScriptVars' | head -1 | cut -d: -f1)"
scriptvar_add_writer_line="$(printf '%s\n' "$scriptvar_add_bytecode" | grep -Fn 'utils.setScriptVar' | head -1 | cut -d: -f1)"
craft_bonus_add_player_line="$(printf '%s\n' "$craft_bonus_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
craft_bonus_add_predicate_line="$(printf '%s\n' "$craft_bonus_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerProfessionInspirationBuffName' | head -1 | cut -d: -f1)"
craft_bonus_add_cleanup_line="$(printf '%s\n' "$craft_bonus_add_bytecode" | grep -Fn 'clearPostNgePlayerProfessionInspirationScriptVars' | head -1 | cut -d: -f1)"
craft_bonus_add_writer_line="$(printf '%s\n' "$craft_bonus_add_bytecode" | grep -Fn 'utils.setScriptVar' | head -1 | cut -d: -f1)"
test "$scriptvar_add_player_line" -lt "$scriptvar_add_predicate_line"
test "$scriptvar_add_predicate_line" -lt "$scriptvar_add_cleanup_line"
test "$scriptvar_add_cleanup_line" -lt "$scriptvar_add_writer_line"
test "$craft_bonus_add_player_line" -lt "$craft_bonus_add_predicate_line"
test "$craft_bonus_add_predicate_line" -lt "$craft_bonus_add_cleanup_line"
test "$craft_bonus_add_cleanup_line" -lt "$craft_bonus_add_writer_line"
! printf '%s\n' "$scriptvar_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionInspirationBuffName'
printf '%s\n' "$scriptvar_remove_bytecode" | grep -Fq 'utils.removeScriptVarTree'
! printf '%s\n' "$craft_bonus_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionInspirationBuffName'
printf '%s\n' "$craft_bonus_remove_bytecode" | grep -Fq 'utils.removeScriptVarTree'
# Every retained ground DOT now resolves through the same PRE-CU application
# and pulse path; no divergent era marker or NGE DOT modifier survives.
dot_bytecode="$(javap -classpath "$class_root" -v script.library.dot)"
printf '%s' "$dot_bytecode" | grep -Fq 'applyPrecuDotEffect'
! printf '%s' "$dot_bytecode" | grep -Fq '.precuAuthoritative'
! printf '%s' "$dot_bytecode" | grep -Fq 'expertise_dot_'
! printf '%s' "$dot_bytecode" | grep -Fq 'dot_vulnerability_'
! printf '%s' "$dot_bytecode" | grep -Fq 'combat_multiply_damage_'
! printf '%s' "$dot_bytecode" | grep -Fq 'combat_divide_damage_'
dot_immunity_bytecode="$(javap -classpath "$class_root" -c -p script.library.dot | sed -n '/public static boolean checkForDotImmunity/,/public static int getElementalGroupResist/p')"
dot_immunity_player_guard_bytecode_line="$(printf '%s\n' "$dot_immunity_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
dot_immunity_later_modifier_bytecode_line="$(printf '%s\n' "$dot_immunity_bytecode" | grep -Fn 'dot_resist_' | head -1 | cut -d: -f1)"
test -n "$dot_immunity_player_guard_bytecode_line"
test -n "$dot_immunity_later_modifier_bytecode_line"
test "$dot_immunity_player_guard_bytecode_line" -lt "$dot_immunity_later_modifier_bytecode_line"
dot_immunity_predicate_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public boolean isRetiredNgeDotImmunityModifier/,/public boolean isRetiredNgeBuffSkillModifier/p')"
printf '%s\n' "$dot_immunity_predicate_bytecode" | grep -Fq 'damage_immune'
printf '%s\n' "$dot_immunity_predicate_bytecode" | grep -Fq 'dot_resist_'
dot_universal_immunity_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int immunityAddBuffHandler/,/public int immunityRemoveBuffHandler/p')"
dot_universal_player_guard_bytecode_line="$(printf '%s\n' "$dot_universal_immunity_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
dot_universal_purge_bytecode_line="$(printf '%s\n' "$dot_universal_immunity_bytecode" | grep -Fn 'performBuffDotImmunity' | tail -1 | cut -d: -f1)"
test -n "$dot_universal_player_guard_bytecode_line"
test -n "$dot_universal_purge_bytecode_line"
test "$dot_universal_player_guard_bytecode_line" -lt "$dot_universal_purge_bytecode_line"
damage_immune_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int damageImmuneAddBuffHandler/,/public int damageImmuneRemoveBuffHandler/p')"
damage_immune_player_guard_bytecode_line="$(printf '%s\n' "$damage_immune_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
damage_immune_purge_bytecode_line="$(printf '%s\n' "$damage_immune_bytecode" | grep -Fn 'performBuffDotImmunity' | head -1 | cut -d: -f1)"
test -n "$damage_immune_player_guard_bytecode_line"
test -n "$damage_immune_purge_bytecode_line"
test "$damage_immune_player_guard_bytecode_line" -lt "$damage_immune_purge_bytecode_line"
printf '%s\n' "$damage_immune_bytecode" | grep -Fq 'damageImmuneDotResistAll'
printf '%s\n' "$damage_immune_bytecode" | grep -Fq 'damageImmuneDamageImmune'
dot_stack_buff_bytecode="$(javap -classpath "$class_root" -c -p script.library.buff)"
printf '%s\n' "$dot_stack_buff_bytecode" | grep -Fq 'dot_reduction_'
printf '%s\n' "$dot_stack_buff_bytecode" | grep -Fq 'dot_divisor_'
printf '%s\n' "$dot_stack_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerDotStackMutationBuff'
printf '%s\n' "$dot_stack_buff_bytecode" | grep -Fq 'retirePostNgePlayerDotStackMutationState'
dot_stack_admission_bytecode="$(printf '%s\n' "$dot_stack_buff_bytecode" | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
dot_stack_admission_bytecode_line="$(printf '%s\n' "$dot_stack_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerDotStackMutationBuff' | head -1 | cut -d: -f1)"
dot_stack_existing_bytecode_line="$(printf '%s\n' "$dot_stack_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$dot_stack_admission_bytecode_line"
test -n "$dot_stack_existing_bytecode_line"
test "$dot_stack_admission_bytecode_line" -lt "$dot_stack_existing_bytecode_line"
dot_reduction_handler_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int dotReductionAddBuffHandler/,/public int dotReductionRemoveBuffHandler/p')"
dot_divisor_handler_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int dotDivisorAddBuffHandler/,/public int dotDivisorRemoveBuffHandler/p')"
dot_reduction_guard_bytecode_line="$(printf '%s\n' "$dot_reduction_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
dot_reduction_mutation_bytecode_line="$(printf '%s\n' "$dot_reduction_handler_bytecode" | grep -Fn 'reduceBuffDotStackCount' | head -1 | cut -d: -f1)"
dot_divisor_guard_bytecode_line="$(printf '%s\n' "$dot_divisor_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
dot_divisor_mutation_bytecode_line="$(printf '%s\n' "$dot_divisor_handler_bytecode" | grep -Fn 'divideBuffDotStackCount' | head -1 | cut -d: -f1)"
test -n "$dot_reduction_guard_bytecode_line"
test -n "$dot_reduction_mutation_bytecode_line"
test -n "$dot_divisor_guard_bytecode_line"
test -n "$dot_divisor_mutation_bytecode_line"
test "$dot_reduction_guard_bytecode_line" -lt "$dot_reduction_mutation_bytecode_line"
test "$dot_divisor_guard_bytecode_line" -lt "$dot_divisor_mutation_bytecode_line"
group_buff_bytecode="$dot_stack_buff_bytecode"
printf '%s\n' "$group_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerGroupBuffName'
printf '%s\n' "$group_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerGroupBuff'
printf '%s\n' "$group_buff_bytecode" | grep -Fq 'retirePostNgePlayerGroupBuffState'
for retired_player_group_buff in $retired_player_group_buffs; do
    printf '%s\n' "$group_buff_bytecode" | grep -Fq "$retired_player_group_buff"
done
group_buff_admission_bytecode="$(printf '%s\n' "$group_buff_bytecode" | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
group_buff_admission_bytecode_line="$(printf '%s\n' "$group_buff_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerGroupBuff' | head -1 | cut -d: -f1)"
group_buff_existing_bytecode_line="$(printf '%s\n' "$group_buff_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$group_buff_admission_bytecode_line"
test -n "$group_buff_existing_bytecode_line"
test "$group_buff_admission_bytecode_line" -lt "$group_buff_existing_bytecode_line"
group_buff_add_handler_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int groupAddBuffHandler/,/public int groupRemoveBuffHandler/p')"
group_buff_remove_handler_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int groupRemoveBuffHandler/,/public int OnTriggerVolumeEntered/p')"
group_buff_add_player_bytecode_line="$(printf '%s\n' "$group_buff_add_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
group_buff_add_predicate_bytecode_line="$(printf '%s\n' "$group_buff_add_handler_bytecode" | grep -Fn 'isRetiredPostNgePlayerGroupBuffName' | head -1 | cut -d: -f1)"
group_buff_add_mutation_bytecode_line="$(printf '%s\n' "$group_buff_add_handler_bytecode" | grep -Fn 'lastIndexOf' | head -1 | cut -d: -f1)"
test -n "$group_buff_add_player_bytecode_line"
test -n "$group_buff_add_predicate_bytecode_line"
test -n "$group_buff_add_mutation_bytecode_line"
test "$group_buff_add_player_bytecode_line" -lt "$group_buff_add_predicate_bytecode_line"
test "$group_buff_add_predicate_bytecode_line" -lt "$group_buff_add_mutation_bytecode_line"
printf '%s\n' "$group_buff_remove_handler_bytecode" | grep -Fq 'removeScriptVar'
printf '%s\n' "$group_buff_remove_handler_bytecode" | grep -Fq 'setGroupBuffs'
printf '%s\n' "$group_buff_remove_handler_bytecode" | grep -Fq 'removeTriggerVolume'
! printf '%s\n' "$group_buff_remove_handler_bytecode" | grep -Fq 'isRetiredPostNgePlayerGroupBuffName'
flat_attribute_buff_bytecode="$dot_stack_buff_bytecode"
printf '%s\n' "$flat_attribute_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerFlatAttributeBuffName'
printf '%s\n' "$flat_attribute_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerFlatAttributeBuff'
printf '%s\n' "$flat_attribute_buff_bytecode" | grep -Fq 'retirePostNgePlayerFlatAttributeState'
for retired_player_flat_attribute_buff in $retired_player_flat_attribute_buffs; do
    printf '%s\n' "$flat_attribute_buff_bytecode" | grep -Fq "$retired_player_flat_attribute_buff"
done
flat_attribute_admission_bytecode="$(printf '%s\n' "$flat_attribute_buff_bytecode" | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
flat_attribute_admission_bytecode_line="$(printf '%s\n' "$flat_attribute_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerFlatAttributeBuff' | head -1 | cut -d: -f1)"
flat_attribute_existing_bytecode_line="$(printf '%s\n' "$flat_attribute_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$flat_attribute_admission_bytecode_line"
test -n "$flat_attribute_existing_bytecode_line"
test "$flat_attribute_admission_bytecode_line" -lt "$flat_attribute_existing_bytecode_line"
flat_attribute_add_handler_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int attribAddBuffHandler/,/public int attribRemoveBuffHandler/p')"
flat_attribute_remove_handler_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int attribRemoveBuffHandler/,/public int attribPercentAddBuffHandler/p')"
flat_attribute_add_player_bytecode_line="$(printf '%s\n' "$flat_attribute_add_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
flat_attribute_add_predicate_bytecode_line="$(printf '%s\n' "$flat_attribute_add_handler_bytecode" | grep -Fn 'isRetiredPostNgePlayerFlatAttributeBuffName' | head -1 | cut -d: -f1)"
flat_attribute_add_writer_bytecode_line="$(printf '%s\n' "$flat_attribute_add_handler_bytecode" | grep -Fn 'Method addAttribModifier' | head -1 | cut -d: -f1)"
test -n "$flat_attribute_add_player_bytecode_line"
test -n "$flat_attribute_add_predicate_bytecode_line"
test -n "$flat_attribute_add_writer_bytecode_line"
test "$flat_attribute_add_player_bytecode_line" -lt "$flat_attribute_add_predicate_bytecode_line"
test "$flat_attribute_add_predicate_bytecode_line" -lt "$flat_attribute_add_writer_bytecode_line"
printf '%s\n' "$flat_attribute_remove_handler_bytecode" | grep -Fq 'removeAttribOrSkillModModifier'
! printf '%s\n' "$flat_attribute_remove_handler_bytecode" | grep -Fq 'isRetiredPostNgePlayerFlatAttributeBuffName'
attribute_percent_buff_bytecode="$dot_stack_buff_bytecode"
printf '%s\n' "$attribute_percent_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerAttributePercentBuffName'
printf '%s\n' "$attribute_percent_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerAttributePercentBuff'
printf '%s\n' "$attribute_percent_buff_bytecode" | grep -Fq 'retirePostNgePlayerAttributePercentState'
for retired_player_attribute_percent_buff in $retired_player_attribute_percent_buffs; do
    printf '%s\n' "$attribute_percent_buff_bytecode" | grep -Fq "$retired_player_attribute_percent_buff"
done
attribute_percent_admission_bytecode="$(printf '%s\n' "$attribute_percent_buff_bytecode" | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
attribute_percent_admission_bytecode_line="$(printf '%s\n' "$attribute_percent_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerAttributePercentBuff' | head -1 | cut -d: -f1)"
attribute_percent_existing_bytecode_line="$(printf '%s\n' "$attribute_percent_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$attribute_percent_admission_bytecode_line"
test -n "$attribute_percent_existing_bytecode_line"
test "$attribute_percent_admission_bytecode_line" -lt "$attribute_percent_existing_bytecode_line"
attribute_percent_add_handler_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int attribPercentAddBuffHandler/,/public int attribPercentRemoveBuffHandler/p')"
attribute_percent_remove_handler_bytecode="$(printf '%s\n' "$buff_handler_bytecode" | sed -n '/public int attribPercentRemoveBuffHandler/,/public int skillAddBuffHandler/p')"
attribute_percent_add_player_bytecode_line="$(printf '%s\n' "$attribute_percent_add_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
attribute_percent_add_predicate_bytecode_line="$(printf '%s\n' "$attribute_percent_add_handler_bytecode" | grep -Fn 'isRetiredPostNgePlayerAttributePercentBuffName' | head -1 | cut -d: -f1)"
attribute_percent_add_writer_bytecode_line="$(printf '%s\n' "$attribute_percent_add_handler_bytecode" | grep -Fn 'Method addAttribModifier' | head -1 | cut -d: -f1)"
test -n "$attribute_percent_add_player_bytecode_line"
test -n "$attribute_percent_add_predicate_bytecode_line"
test -n "$attribute_percent_add_writer_bytecode_line"
test "$attribute_percent_add_player_bytecode_line" -lt "$attribute_percent_add_predicate_bytecode_line"
test "$attribute_percent_add_predicate_bytecode_line" -lt "$attribute_percent_add_writer_bytecode_line"
printf '%s\n' "$attribute_percent_remove_handler_bytecode" | grep -Fq 'removeAttribOrSkillModModifier'
! printf '%s\n' "$attribute_percent_remove_handler_bytecode" | grep -Fq 'isRetiredPostNgePlayerAttributePercentBuffName'
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
junk_dealer_buff_bytecode="$(javap -classpath "$class_root" -c -p script.library.buff)"
printf '%s' "$junk_dealer_buff_bytecode" | grep -Fq 'isRetiredPostNgeJunkDealerExpertiseEffect'
printf '%s' "$junk_dealer_buff_bytecode" | grep -Fq 'isRetiredPostNgeJunkDealerExpertiseBuff'
printf '%s' "$junk_dealer_buff_bytecode" | grep -Fq 'clearPostNgeJunkDealerExpertiseState'
printf '%s' "$junk_dealer_buff_bytecode" | grep -Fq 'expertise_junk_dealer'
printf '%s' "$junk_dealer_buff_bytecode" | grep -Fq 'junkDealerBuffer'
printf '%s' "$junk_dealer_buff_bytecode" | grep -Fq 'junkDealerPrecision'
printf '%s' "$junk_dealer_buff_bytecode" | grep -Fq 'junkDealerDamageDecrease'
junk_dealer_admission_bytecode="$(printf '%s' "$junk_dealer_buff_bytecode" | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
junk_dealer_admission_bytecode_line="$(printf '%s\n' "$junk_dealer_admission_bytecode" | grep -Fn 'isRetiredPostNgeJunkDealerExpertiseBuff' | head -1 | cut -d: -f1)"
junk_dealer_player_gate_bytecode_line="$(printf '%s\n' "$junk_dealer_admission_bytecode" | grep -Fn 'Method isPlayer' | tail -1 | cut -d: -f1)"
test -n "$junk_dealer_admission_bytecode_line"
test -n "$junk_dealer_player_gate_bytecode_line"
test "$junk_dealer_admission_bytecode_line" -lt "$junk_dealer_player_gate_bytecode_line"
junk_dealer_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int junkDealerAddBuffHandler/,/public int junkDealerRemoveBuffHandler/p')"
junk_dealer_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int junkDealerRemoveBuffHandler/,/public int commandoSnareBonusAddBuffHandler/p')"
for junk_dealer_handler_bytecode in "$junk_dealer_add_bytecode" "$junk_dealer_remove_bytecode"; do
    printf '%s' "$junk_dealer_handler_bytecode" | grep -Fq 'isPostNgeBuffProgressionRetired'
    printf '%s' "$junk_dealer_handler_bytecode" | grep -Fq 'isRetiredPostNgeJunkDealerExpertiseEffect'
    printf '%s' "$junk_dealer_handler_bytecode" | grep -Fq 'clearPostNgeJunkDealerExpertiseState'
done
junk_dealer_add_cleanup_bytecode_line="$(printf '%s\n' "$junk_dealer_add_bytecode" | grep -Fn 'clearPostNgeJunkDealerExpertiseState' | head -1 | cut -d: -f1)"
junk_dealer_add_read_bytecode_line="$(printf '%s\n' "$junk_dealer_add_bytecode" | grep -Fn 'getObjIdScriptVar' | head -1 | cut -d: -f1)"
junk_dealer_remove_cleanup_bytecode_line="$(printf '%s\n' "$junk_dealer_remove_bytecode" | grep -Fn 'clearPostNgeJunkDealerExpertiseState' | head -1 | cut -d: -f1)"
junk_dealer_remove_write_bytecode_line="$(printf '%s\n' "$junk_dealer_remove_bytecode" | grep -Fn 'removeAttribOrSkillModModifier' | head -1 | cut -d: -f1)"
test "$junk_dealer_add_cleanup_bytecode_line" -lt "$junk_dealer_add_read_bytecode_line"
test "$junk_dealer_remove_cleanup_bytecode_line" -lt "$junk_dealer_remove_write_bytecode_line"
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
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgeMeditationBuffs'
for retired_meditation_buff in fs_meditate_1 fs_meditate_2 fs_meditate_3; do
    javap -classpath "$class_root" -v script.library.buff | grep -Fq "$retired_meditation_buff"
done
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostNgeBountyHunterShieldBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgeBountyHunterShieldState'
for retired_bounty_hunter_shield_buff in bh_shields_handler bh_shields bh_shields_block bh_shields_charged; do
    javap -classpath "$class_root" -v script.library.buff | grep -Fq "$retired_bounty_hunter_shield_buff"
done
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostNgeForceSensitiveStanceBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgeForceSensitiveStanceState'
for retired_force_sensitive_stance_buff in $retired_force_sensitive_stance_buffs; do
    javap -classpath "$class_root" -v script.library.buff | grep -Fq "$retired_force_sensitive_stance_buff"
done
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostNgePlayerForceThrowBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgePlayerForceThrowState'
buff_library_bytecode="$(javap -classpath "$class_root" -c -p script.library.buff)"
force_throw_buff_predicate_bytecode="$(printf '%s' "$buff_library_bytecode" | sed -n '/public static boolean isRetiredPostNgePlayerForceThrowBuff(script.obj_id, script.combat_engine.buff_data)/,/public static void retirePostNgePlayerForceThrowState/p')"
printf '%s' "$force_throw_buff_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$force_throw_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerForceThrowBuffName'
printf '%s' "$force_throw_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerForceThrowEffect'
force_throw_cleanup_bytecode="$(printf '%s' "$buff_library_bytecode" | sed -n '/public static void retirePostNgePlayerForceThrowState/,/public static boolean isRetiredPostNgePlayerMedicDoomBuff/p')"
printf '%s' "$force_throw_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$force_throw_cleanup_bytecode" | grep -Fq 'getBuffData'
printf '%s' "$force_throw_cleanup_bytecode" | grep -Fq 'removeBuff'
force_throw_admission_bytecode="$(printf '%s' "$buff_library_bytecode" | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
force_throw_admission_line="$(printf '%s\n' "$force_throw_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerForceThrowBuff' | head -1 | cut -d: -f1)"
force_throw_existing_line="$(printf '%s\n' "$force_throw_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test "$force_throw_admission_line" -lt "$force_throw_existing_line"
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeForceSensitiveStanceState'
center_of_being_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | sed -n '/public int centerOfBeing/,/public int forceFocus/p')"
printf '%s' "$center_of_being_bytecode" | grep -Fq 'combat_brawler_novice'
printf '%s' "$center_of_being_bytecode" | grep -Fq 'centerofbeing'
printf '%s' "$center_of_being_bytecode" | grep -Fq 'drainCombatActionAttributes'
! printf '%s' "$center_of_being_bytecode" | grep -Eq 'fs_buff_(def_1_1|ca_1)'
combat_actions_signatures="$(javap -classpath "$class_root" -p script.systems.combat.combat_actions)"
printf '%s' "$combat_actions_signatures" | grep -Fq 'public int unarmedDizzy1('
printf '%s' "$combat_actions_signatures" | grep -Fq 'public int unarmedCombo1('
printf '%s' "$combat_actions_signatures" | grep -Fq 'public int unarmedCombo2('
printf '%s' "$combat_actions_signatures" | grep -Fq 'private boolean performPrecuUnarmedCombo('
unarmed_combo_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | sed -n '/public int unarmedCombo1/,/public int intimidate1/p')"
printf '%s' "$unarmed_combo_bytecode" | grep -Fq 'precuTargetPool'
printf '%s' "$unarmed_combo_bytecode" | grep -Fq 'precuHealthDamageMultiplier'
printf '%s' "$unarmed_combo_bytecode" | grep -Fq 'precuActionDamageMultiplier'
printf '%s' "$unarmed_combo_bytecode" | grep -Fq 'precuMindDamageMultiplier'
bounty_hunter_shield_script_bytecode="$(javap -classpath "$class_root" -c -p script.player.skill.bh_shields)"
test "$(printf '%s' "$bounty_hunter_shield_script_bytecode" | grep -Fc 'retirePostNgeBountyHunterShieldState')" -eq 3
printf '%s' "$bounty_hunter_shield_script_bytecode" | grep -Fq 'public int OnAttach'
printf '%s' "$bounty_hunter_shield_script_bytecode" | grep -Fq 'public int OnInitialize'
printf '%s' "$bounty_hunter_shield_script_bytecode" | grep -Fq 'public int OnCreatureDamaged'
javap -classpath "$class_root" -v script.systems.buff.buff_handler | grep -Fq 'retirePostNgeBountyHunterShieldState'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostNgePlayerBountyHunterFlawlessBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'clearPostNgePlayerBountyHunterFlawlessResidue'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgePlayerBountyHunterFlawlessState'
for bounty_hunter_flawless_buff in set_bonus_bh_utility_a_1 set_bonus_bh_utility_a_2 set_bonus_bh_utility_a_3 bh_flawless_strike bh_flawless_proc_chance_1 flawless_bead_1 flawless_bead_2 flawless_bead_3; do
    javap -classpath "$class_root" -v script.library.buff | grep -Fq "$bounty_hunter_flawless_buff"
done
for bounty_hunter_flawless_modifier in bh_flawless_bead flawless_bead expertise_cooldown_line_bh_flawless_strike; do
    javap -classpath "$class_root" -v script.library.buff | grep -Fq "$bounty_hunter_flawless_modifier"
done
bounty_hunter_flawless_cleanup_bytecode="$(printf '%s' "$buff_library_bytecode" | sed -n '/public static void clearPostNgePlayerBountyHunterFlawlessResidue/,/public static void retirePostNgePlayerBountyHunterFlawlessState/p')"
printf '%s' "$bounty_hunter_flawless_cleanup_bytecode" | grep -Fq 'bh_flawless_proc_chance_1'
printf '%s' "$bounty_hunter_flawless_cleanup_bytecode" | grep -Fq 'removeAttribOrSkillModModifier'
printf '%s' "$bounty_hunter_flawless_cleanup_bytecode" | grep -Fq 'applySkillStatisticModifier'
printf '%s' "$bounty_hunter_flawless_cleanup_bytecode" | grep -Fq 'revokeCommand'
bounty_hunter_flawless_state_bytecode="$(printf '%s' "$buff_library_bytecode" | sed -n '/public static void retirePostNgePlayerBountyHunterFlawlessState/,/private static final java.lang.String\[\] RETIRED_POST_NGE_GCW_BANNER_BUFFS/p')"
printf '%s' "$bounty_hunter_flawless_state_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$bounty_hunter_flawless_state_bytecode" | grep -Fq 'clearPostNgePlayerBountyHunterFlawlessResidue'
bounty_hunter_flawless_admission_bytecode="$(printf '%s' "$buff_library_bytecode" | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
bounty_hunter_flawless_admission_line="$(printf '%s\n' "$bounty_hunter_flawless_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerBountyHunterFlawlessBuff' | head -1 | cut -d: -f1)"
bounty_hunter_flawless_existing_line="$(printf '%s\n' "$bounty_hunter_flawless_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$bounty_hunter_flawless_admission_line"
test -n "$bounty_hunter_flawless_existing_line"
test "$bounty_hunter_flawless_admission_line" -lt "$bounty_hunter_flawless_existing_line"
bounty_hunter_flawless_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int bhFlawlessAddBuffHandler/,/public int bhFlawlessRemoveBuffHandler/p')"
printf '%s' "$bounty_hunter_flawless_add_bytecode" | grep -Fq 'isRetiredPostNgePlayerBountyHunterFlawlessEffect'
printf '%s' "$bounty_hunter_flawless_add_bytecode" | grep -Fq 'isRetiredPostNgePlayerBountyHunterFlawlessBuffName'
bounty_hunter_flawless_add_cleanup_line="$(printf '%s\n' "$bounty_hunter_flawless_add_bytecode" | grep -Fn 'retirePostNgePlayerBountyHunterFlawlessState' | head -1 | cut -d: -f1)"
bounty_hunter_flawless_add_nested_line="$(printf '%s\n' "$bounty_hunter_flawless_add_bytecode" | grep -Fn 'bh_flawless_proc_chance_1' | head -1 | cut -d: -f1)"
test "$bounty_hunter_flawless_add_cleanup_line" -lt "$bounty_hunter_flawless_add_nested_line"
bounty_hunter_flawless_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int bhFlawlessRemoveBuffHandler/,/public int mtpMeatlumpAngryAddBuffHandler/p')"
printf '%s' "$bounty_hunter_flawless_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerBountyHunterFlawlessEffect'
printf '%s' "$bounty_hunter_flawless_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerBountyHunterFlawlessBuffName'
bounty_hunter_flawless_remove_cleanup_line="$(printf '%s\n' "$bounty_hunter_flawless_remove_bytecode" | grep -Fn 'clearPostNgePlayerBountyHunterFlawlessResidue' | head -1 | cut -d: -f1)"
bounty_hunter_flawless_remove_nested_line="$(printf '%s\n' "$bounty_hunter_flawless_remove_bytecode" | grep -Fn 'bh_flawless_proc_chance_1' | head -1 | cut -d: -f1)"
test "$bounty_hunter_flawless_remove_cleanup_line" -lt "$bounty_hunter_flawless_remove_nested_line"
javap -classpath "$class_root" -c script.library.meditation | grep -Fq 'retirePostNgeMeditationBuffs'
! javap -classpath "$class_root" -v script.library.meditation | grep -Fq 'fs_meditate_'
meditation_tick_bytecode="$(javap -classpath "$class_root" -c script.player.base.base_player | sed -n '/handleMeditationTick/,/msgCoupDeGraceAuthoritativeCheck/p')"
printf '%s' "$meditation_tick_bytecode" | grep -Fq 'meditation.trance'
printf '%s' "$meditation_tick_bytecode" | grep -Fq 'messageTo'
! printf '%s' "$meditation_tick_bytecode" | grep -Eq 'MEDITATE_BUFFS|fs_meditate_|buff\.applyBuff|utils\.isProfession|VAR_MEDITATION_BASE'
javap -classpath "$class_root" -v script.player.skill.performcommands | grep -Fq 'isPostNgeBuffProgressionRetired'
javap -classpath "$class_root" -v script.player.skill.performcommands | grep -Fq 'retirePostNgeBuffProgression'
javap -classpath "$class_root" -v script.systems.buff.buff_handler | grep -Fq 'isPostNgeBuffProgressionRetired'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostNgeGcwConsumableBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgeGcwConsumableBuffState'
for retired_gcw_consumable_buff in tcg_series3_hh_15_torpedo_warhead tcg_series7_rocket_launcher gcw_mini_turret gcw_rocket_turret; do
    javap -classpath "$class_root" -v script.library.buff | grep -Fq "$retired_gcw_consumable_buff"
done
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostP14PlayerControlImmunityBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostP14PlayerControlImmunityState'
for retired_player_control_immunity_buff in $retired_player_control_immunity_buffs; do
    javap -classpath "$class_root" -v script.library.buff | grep -Fq "$retired_player_control_immunity_buff"
done
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostP14PlayerAvoidIncapHealBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostP14PlayerAvoidIncapHealState'
for retired_player_avoid_incap_buff in $retired_player_avoid_incap_buffs; do
    javap -classpath "$class_root" -v script.library.buff | grep -Fq "$retired_player_avoid_incap_buff"
done
avoid_incap_effect_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/onIncapHealAddBuffHandler/,/onIncapHealRemoveBuffHandler/p')"
avoid_incap_effect_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/onIncapHealRemoveBuffHandler/,/healEffectAddBuffHandler/p')"
avoid_incap_effect_guard_bytecode_line="$(printf '%s\n' "$avoid_incap_effect_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
avoid_incap_effect_cleanup_bytecode_line="$(printf '%s\n' "$avoid_incap_effect_handler_bytecode" | grep -Fn 'script/library/buff.retirePostP14PlayerAvoidIncapHealState' | head -1 | cut -d: -f1)"
avoid_incap_effect_return_bytecode_line="$(printf '%s\n' "$avoid_incap_effect_handler_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
avoid_incap_effect_write_bytecode_line="$(printf '%s\n' "$avoid_incap_effect_handler_bytecode" | grep -Fn 'script/library/utils.setScriptVar' | head -1 | cut -d: -f1)"
test -n "$avoid_incap_effect_guard_bytecode_line" -a -n "$avoid_incap_effect_cleanup_bytecode_line" -a -n "$avoid_incap_effect_return_bytecode_line" -a -n "$avoid_incap_effect_write_bytecode_line"
test "$avoid_incap_effect_guard_bytecode_line" -lt "$avoid_incap_effect_cleanup_bytecode_line"
test "$avoid_incap_effect_cleanup_bytecode_line" -lt "$avoid_incap_effect_return_bytecode_line"
test "$avoid_incap_effect_return_bytecode_line" -lt "$avoid_incap_effect_write_bytecode_line"
! printf '%s' "$avoid_incap_effect_remove_bytecode" | grep -Fq 'retirePostP14PlayerAvoidIncapHealState'
printf '%s' "$avoid_incap_effect_remove_bytecode" | grep -Fq 'script/library/utils.removeScriptVar'
critical_heal_bytecode="$(javap -classpath "$class_root" -c script.player.base.base_player | sed -n '/public boolean performCriticalHeal/,/public void sendSmugglerSystemBootstrap/p')"
printf '%s' "$critical_heal_bytecode" | grep -Fq 'script/library/buff.isPostNgeBuffProgressionRetired'
printf '%s' "$critical_heal_bytecode" | grep -Fq 'script/library/buff.retirePostP14PlayerAvoidIncapHealState'
test "$(printf '%s' "$critical_heal_bytecode" | grep -nF 'script/library/buff.isPostNgeBuffProgressionRetired' | cut -d: -f1)" -lt "$(printf '%s' "$critical_heal_bytecode" | grep -nF 'script/library/buff.getAllBuffs' | cut -d: -f1)"
javap -classpath "$class_root" -v script.library.factions | grep -Fq 'isRetiredPostNgePvpRewardBuff'
for retired_pvp_reward_buff in $retired_pvp_reward_buffs; do
    javap -classpath "$class_root" -v script.library.factions | grep -Fq "$retired_pvp_reward_buff"
done
javap -classpath "$class_root" -c script.library.buff | grep -Fq 'script/library/factions.isRetiredPostNgePvpRewardBuff'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgePvpRewardPlayerAction'
for retired_pvp_reward_action in $retired_pvp_reward_actions; do
    javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq "$retired_pvp_reward_action"
done
pvp_reward_standard_action_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base | sed -n '/public boolean combatStandardAction(java.lang.String, script.obj_id, script.obj_id, script.obj_id, java.lang.String, script.combat_engine.combat_data, boolean, boolean, int)/,/public boolean/p')"
printf '%s' "$pvp_reward_standard_action_bytecode" | grep -Fq 'isRetiredPostNgePvpRewardPlayerAction'
printf '%s' "$pvp_reward_standard_action_bytecode" | grep -Fq 'script/library/factions.retirePostNgePvpRewardState'
test "$(javap -classpath "$class_root" -c script.player.gcw.pvp_aura_buff_controller | grep -Fc 'script/library/factions.retirePostNgePvpRewardState')" -eq 3
pvp_aura_effect_handler_bytecode="$(javap -classpath "$class_root" -c -p script.systems.buff.buff_handler)"
pvp_aura_effect_add_bytecode="$(printf '%s' "$pvp_aura_effect_handler_bytecode" | sed -n '/pvpAuraBuffSelfAddBuffHandler/,/pvpAuraBuffSelfRemoveBuffHandler/p')"
pvp_aura_effect_remove_bytecode="$(printf '%s' "$pvp_aura_effect_handler_bytecode" | sed -n '/pvpAuraBuffSelfRemoveBuffHandler/,/nextHitCritAddBuffHandler/p')"
pvp_aura_effect_guard_bytecode_line="$(printf '%s\n' "$pvp_aura_effect_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
pvp_aura_effect_cleanup_bytecode_line="$(printf '%s\n' "$pvp_aura_effect_add_bytecode" | grep -Fn 'script/library/factions.retirePostNgePvpRewardState' | head -1 | cut -d: -f1)"
pvp_aura_effect_return_bytecode_line="$(printf '%s\n' "$pvp_aura_effect_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
pvp_aura_effect_attach_bytecode_line="$(printf '%s\n' "$pvp_aura_effect_add_bytecode" | grep -Fn 'Method attachScript' | head -1 | cut -d: -f1)"
for pvp_aura_effect_bytecode_line in "$pvp_aura_effect_guard_bytecode_line" "$pvp_aura_effect_cleanup_bytecode_line" "$pvp_aura_effect_return_bytecode_line" "$pvp_aura_effect_attach_bytecode_line"; do
    test -n "$pvp_aura_effect_bytecode_line"
done
test "$pvp_aura_effect_guard_bytecode_line" -lt "$pvp_aura_effect_cleanup_bytecode_line"
test "$pvp_aura_effect_cleanup_bytecode_line" -lt "$pvp_aura_effect_return_bytecode_line"
test "$pvp_aura_effect_return_bytecode_line" -lt "$pvp_aura_effect_attach_bytecode_line"
! printf '%s' "$pvp_aura_effect_remove_bytecode" | grep -Fq 'retirePostNgePvpRewardState'
printf '%s' "$pvp_aura_effect_remove_bytecode" | grep -Fq 'Method detachScript'
printf '%s' "$pvp_aura_effect_remove_bytecode" | grep -Fq 'Method removeObjVar'
gcw_bonus_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int gcwBonusGeneralAddBuffHandler/,/public int gcwBonusGeneralRemoveBuffHandler/p')"
printf '%s' "$gcw_bonus_handler_bytecode" | grep -Fq 'script/library/buff.isPostNgeBuffProgressionRetired'
printf '%s' "$gcw_bonus_handler_bytecode" | grep -Fq 'script/library/utils.removeScriptVarTree'
test "$(printf '%s' "$gcw_bonus_handler_bytecode" | grep -Fn 'script/library/buff.isPostNgeBuffProgressionRetired' | head -n 1 | cut -d: -f1)" -lt "$(printf '%s' "$gcw_bonus_handler_bytecode" | grep -Fn 'script/library/utils.setScriptVar' | head -n 1 | cut -d: -f1)"
gcw_mini_turret_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int gcwMiniTurretAddBuffHandler/,/public int gcwMiniTurretRemoveBuffHandler/p')"
printf '%s' "$gcw_mini_turret_handler_bytecode" | grep -Fq 'script/library/buff.isPostNgeBuffProgressionRetired'
printf '%s' "$gcw_mini_turret_handler_bytecode" | grep -Fq 'script/library/buff.removeBuff'
test "$(printf '%s' "$gcw_mini_turret_handler_bytecode" | grep -Fn 'script/library/buff.isPostNgeBuffProgressionRetired' | head -n 1 | cut -d: -f1)" -lt "$(printf '%s' "$gcw_mini_turret_handler_bytecode" | grep -Fn 'script/library/advanced_turret.createTurret' | head -n 1 | cut -d: -f1)"
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
stealth_bytecode="$(javap -classpath "$class_root" -c -p script.library.stealth)"
stealth_theft_bytecode="$(printf '%s' "$stealth_bytecode" | sed -n '/public static boolean doTheftLoot/,/public static boolean hasStealingLootTableEntry/p')"
test "$(printf '%s' "$stealth_theft_bytecode" | grep -Fc 'script/library/xp.getPrecuCombatLevel')" -eq 2
! printf '%s' "$stealth_theft_bytecode" | grep -Fq 'script/base_class.getLevel'
stealth_decoy_bytecode="$(printf '%s' "$stealth_bytecode" | sed -n '/public static script.obj_id createDecoy/,/public static boolean isDecoy/p')"
test "$(printf '%s' "$stealth_decoy_bytecode" | grep -Fc 'script/library/xp.getPrecuCombatLevel')" -eq 1
! printf '%s' "$stealth_decoy_bytecode" | grep -Fq 'script/base_class.getLevel'
# Publish 14.1 retains mask scent, Ranger conceal, and invis_cover, but not the
# later Ranger blend/camouflage, Spy stealth/smoke, Smuggler ally-invisibility,
# urban/wilderness stealth, or Force Cloak player action/buff families.
post_p14_invisibility_retirement_bytecode="$(printf '%s' "$stealth_bytecode" | sed -n '/public static boolean isRetiredPostP14PlayerInvisibilityName/,/public static void setBioProbeData/p')"
for retired_invisibility_action in \
  blendIn camouflageAlly camouflageSelf stealth stealth_1 stealth_2 \
  smokeGrenade smokeGrenade_1 smokeGrenade_2 sm_buff_invis_ally_1 \
  urbanStealth wildernessStealth forceCloak
do
  printf '%s' "$stealth_bytecode" | grep -Fq "$retired_invisibility_action"
done
for retired_invisibility_buff in \
  invis_blendIn invis_camouflage invis_urbanStealth invis_wildernessStealth \
  invis_forceCloak invis_stealth invis_stealth_1 invis_stealth_2 \
  invis_smokeGrenade invis_smokeGrenade_1 invis_smokeGrenade_2 \
  invis_sm_buff_invis_1
do
  printf '%s' "$post_p14_invisibility_retirement_bytecode" | grep -Fq "$retired_invisibility_buff"
done
! printf '%s' "$post_p14_invisibility_retirement_bytecode" | grep -Fq 'invis_cover'
printf '%s' "$post_p14_invisibility_retirement_bytecode" | grep -Fq 'retirePostP14PlayerInvisibilityState'
assert_stealth_retirement_guard()
{
  guarded_method_bytecode="$(printf '%s' "$stealth_bytecode" | sed -n "/$1/,/$2/p")"
  printf '%s' "$guarded_method_bytecode" | grep -Fq "$3"
  printf '%s' "$guarded_method_bytecode" | grep -Fq 'retirePostP14PlayerInvisibilityState'
}
assert_stealth_retirement_guard 'canPerformSmokeGrenade' 'canPerformWithoutTrace' 'isRetiredPostP14PlayerInvisibilityAction'
assert_stealth_retirement_guard 'canPerformStationaryInvis' 'public static void smokeGrenade' 'isRetiredPostP14PlayerInvisibilityAction'
assert_stealth_retirement_guard 'public static void smokeGrenade' 'public static void bothanInnate' 'isRetiredPostP14PlayerInvisibilityAction'
assert_stealth_retirement_guard 'canPerformStealth' 'public static void stealth' 'isRetiredPostP14PlayerInvisibilityAction'
assert_stealth_retirement_guard 'public static void stealth' 'public static void withoutTrace' 'isRetiredPostP14PlayerInvisibilityAction'
assert_stealth_retirement_guard 'invisBuffAdded' 'canPerformCamouflageSelf' 'isRetiredPostP14PlayerInvisibilityName'
assert_stealth_retirement_guard 'canPerformCamouflageSelf' 'public static void camouflageSelf' 'isRetiredPostP14PlayerInvisibilityAction'
assert_stealth_retirement_guard 'public static void camouflageSelf' 'canPerformCamouflageAlly' 'isRetiredPostP14PlayerInvisibilityAction'
assert_stealth_retirement_guard 'canPerformCamouflageAlly' 'canPerformUrbanStealth' 'isRetiredPostP14PlayerInvisibilityAction'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostP14PlayerInvisibilityName'
javap -classpath "$class_root" -v script.library.jedi | grep -Fq 'isRetiredPostP14PlayerInvisibilityAction'
javap -classpath "$class_root" -v script.systems.buff.buff_handler | grep -Fq 'retirePostP14PlayerInvisibilityState'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostP14PlayerInvisibilityAction'
javap -classpath "$class_root" -v script.systems.skills.stealth.hep | grep -Fq 'retirePostP14PlayerInvisibilityState'
javap -classpath "$class_root" -v script.systems.skills.stealth.player_stealth | grep -Fq 'retirePostP14PlayerInvisibilityState'
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
# mindBlast*, and jediMindTrick commands. The fs_* family and exact unnumbered
# forceThrow action are retained NGE compatibility; forceThrow1/2 stay classic.
combat_base_actions_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base)"
spy_action_bytecode="$(printf '%s' "$combat_base_actions_bytecode" | sed -n '/public static boolean isRetiredPostNgeSpyPlayerAction/,/public static boolean isRetiredPostNgeBeastMasterPlayerAction/p')"
for prefixless_spy_action in terminateTarget stealth smokeGrenade; do
    printf '%s' "$spy_action_bytecode" | grep -Fq "$prefixless_spy_action"
done
officer_action_bytecode="$(printf '%s' "$combat_base_actions_bytecode" | sed -n '/public static boolean isRetiredPostNgeOfficerPlayerAction/,/public static boolean isRetiredPostNgeForceSensitivePlayerAction/p')"
for prefixless_officer_action in entrench actOfWar actOfWar_1 actOfWar_2 actOfWar_3; do
    printf '%s' "$officer_action_bytecode" | grep -Fq "$prefixless_officer_action"
done
! printf '%s' "$officer_action_bytecode" | grep -Fq 'groupWaypoint'
force_sensitive_action_bytecode="$(printf '%s' "$combat_base_actions_bytecode" | sed -n '/public static boolean isRetiredPostNgeForceSensitivePlayerAction/,/public static boolean isRetiredPostNgeSmugglerPlayerAction/p')"
printf '%s' "$force_sensitive_action_bytecode" | grep -Fq 'fs_'
printf '%s' "$force_sensitive_action_bytecode" | grep -Fq 'forceThrow'
for prefixless_force_sensitive_action in forceRun forceFocus forceStrike saberBlock; do
    printf '%s' "$force_sensitive_action_bytecode" | grep -Fq "$prefixless_force_sensitive_action"
done
! printf '%s' "$force_sensitive_action_bytecode" | grep -Eq 'forceRun[123]|forceThrow[12]'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeForceSensitivePlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'fs_dot_immunity_recourse'
force_throw_action_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | sed -n '/public int forceThrow(/,/public int ambush(/p')"
printf '%s' "$force_throw_action_bytecode" | grep -Fq 'forceThrow'
printf '%s' "$force_throw_action_bytecode" | grep -Fq 'combatStandardAction'
# Publish 14.1 Smuggler uses combat_smuggler skill boxes and classic named
# commands; sm_* remains retained NGE compatibility without player authority.
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeSmugglerPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'sm_'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeSmugglerPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'sm_inspect_cargo'
smuggler_action_bytecode="$(printf '%s' "$combat_base_actions_bytecode" | sed -n '/public static boolean isRetiredPostNgeSmugglerPlayerAction/,/public static boolean isRetiredPostNgeBountyHunterPlayerAction/p')"
for prefixless_smuggler_action in cheapShot blastAway hipShot; do
    printf '%s' "$smuggler_action_bytecode" | grep -Fq "$prefixless_smuggler_action"
done
# Publish 14.1 Bounty Hunter and Commando use their combat_bountyhunter and
# combat_commando trees; bh_* and co_* remain NPC/content compatibility only.
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeBountyHunterPlayerAction'
bounty_hunter_action_bytecode="$(printf '%s' "$combat_base_actions_bytecode" | sed -n '/public static boolean isRetiredPostNgeBountyHunterPlayerAction/,/public static boolean isRetiredPostNgeCommandoPlayerAction/p')"
printf '%s' "$bounty_hunter_action_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$bounty_hunter_action_bytecode" | grep -Fq 'bh_'
printf '%s' "$bounty_hunter_action_bytecode" | grep -Fq 'Method java/lang/String.startsWith'
for bounty_hunter_flawless_set_action in set_bonus_bh_utility_a_1 set_bonus_bh_utility_a_2 set_bonus_bh_utility_a_3; do
    printf '%s' "$bounty_hunter_action_bytecode" | grep -Fq "$bounty_hunter_flawless_set_action"
done
for prefixless_bounty_hunter_action in assault crippleShot ambush; do
    printf '%s' "$bounty_hunter_action_bytecode" | grep -Fq "$prefixless_bounty_hunter_action"
done
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeCommandoPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeCommandoPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'co_kill_trap_1'
commando_action_bytecode="$(printf '%s' "$combat_base_actions_bytecode" | sed -n '/public static boolean isRetiredPostNgeCommandoPlayerAction/,/public static boolean isRetiredPostNgeMedicPlayerAction/p')"
for prefixless_commando_action in demolition stunGrenade barrage barrage_1 barrage_2 barrage_3; do
    printf '%s' "$commando_action_bytecode" | grep -Fq "$prefixless_commando_action"
done
! javap -classpath "$class_root" -v script.library.combat | grep -Eq 'isCommandoBonus|getDevastationChance'
! javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Eq 'commando_passive_dot|commando_devastation|expertise_devastation_bonus|getHeavyWeaponDotName'
heavy_weapon_dot_bytecode="$(javap -classpath "$class_root" -c -p script.library.heavyweapons | sed -n '/getHeavyWeaponDotName(script.obj_id, int, boolean)/,/^$/p')"
printf '%s' "$heavy_weapon_dot_bytecode" | grep -Fq 'Method isPlayer:'
printf '%s' "$heavy_weapon_dot_bytecode" | grep -Fq 'Method getLevel:'
heavy_weapon_player_guard_line="$(printf '%s\n' "$heavy_weapon_dot_bytecode" | grep -nF 'Method isPlayer:' | head -n1 | cut -d: -f1)"
heavy_weapon_level_line="$(printf '%s\n' "$heavy_weapon_dot_bytecode" | grep -nF 'Method getLevel:' | head -n1 | cut -d: -f1)"
test -n "$heavy_weapon_player_guard_line"
test -n "$heavy_weapon_level_line"
test "$heavy_weapon_player_guard_line" -lt "$heavy_weapon_level_line"
javap -classpath "$class_root" -constants script.library.heavyweapons | grep -Fq 'ATTACK_NAME_BASE_SINGLE = "co_hw_dot_"'
javap -classpath "$class_root" -constants script.library.heavyweapons | grep -Fq 'ATTACK_NAME_BASE_AREA = "co_ae_hw_dot_"'
kill_meter_cleanup_bytecode="$(javap -classpath "$class_root" -c -p script.library.combat | sed -n '/retirePostNgeKillMeterPlayerState/,/setKillMeter/p')"
printf '%s' "$kill_meter_cleanup_bytecode" | grep -Fq 'getKillMeter'
printf '%s' "$kill_meter_cleanup_bytecode" | grep -Fq 'incrementKillMeter'
printf '%s' "$kill_meter_cleanup_bytecode" | grep -Fq 'removeScriptVarTree'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeKillMeterPlayerState'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeDroidCombatModuleState'
javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'RETIRED_POST_NGE_DROID_COMBAT_MODULE_PLAYER_ACTIONS'
javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'server_droid_torturous_needle_3'
javap -classpath "$class_root" -v script.library.pet_lib | grep -Fq 'droideka_shield_3'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeDroidCombatModuleAction'
for kill_meter_writer_class in script.library.gcw script.library.xp script.systems.combat.combat_actions script.systems.combat.combat_base; do
    javap -classpath "$class_root" -v "$kill_meter_writer_class" | grep -Fq 'modifyKillMeter'
    ! javap -classpath "$class_root" -v "$kill_meter_writer_class" | grep -Fq 'incrementKillMeter'
done
# Publish 14.1 Medic/Doctor/Combat Medic and Entertainer/Dancer/Musician/
# Image Designer trees remain authoritative; me_* and en_* are compatibility.
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeMedicPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeEntertainerPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeMedicPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeEntertainerPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'me_buff_health_1'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'en_holographic_image'
medic_action_bytecode="$(printf '%s' "$combat_base_actions_bytecode" | sed -n '/public static boolean isRetiredPostNgeMedicPlayerAction/,/public static boolean isRetiredPostNgeEntertainerPlayerAction/p')"
for prefixless_medic_action in targetAnatomy neurotoxin; do
    printf '%s' "$medic_action_bytecode" | grep -Fq "$prefixless_medic_action"
done
# Publish 14.1 Creature Handler remains authoritative. Retain Beast Master
# assets for later-content loading but retire their player combat runtime.
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'isPostNgeBeastMasterPlayerRuntimeRetired'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'isRetiredPostNgePlayerOwnedBeast'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'bm_player_buff'
! javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'expertise_bm_'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'beast_master.known_skills'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'setBeastmasterPetCommands'
javap -classpath "$class_root" -v script.library.beast_lib | grep -Fq 'removeBatchObjVar'
javap -classpath "$class_root" -v script.ai.beast_control_device | grep -Fq 'isRetiredPostNgeBeastMasterPlayer'
! javap -classpath "$class_root" -v script.ai.beast | grep -Fq 'expertise_'
beast_controller_bytecode="$(javap -classpath "$class_root" -c script.ai.beast)"
printf '%s' "$beast_controller_bytecode" | grep -Fq 'public boolean retirePostNgePlayerOwnedRuntime'
printf '%s' "$beast_controller_bytecode" | grep -Fq 'beast_lib.isRetiredPostNgePlayerOwnedBeast'
printf '%s' "$beast_controller_bytecode" | grep -Fq 'beast_lib.retirePostNgeBeastMasterPlayerState'
test "$(printf '%s' "$beast_controller_bytecode" | grep -Fc 'retirePostNgePlayerOwnedRuntime')" -eq 5
javap -classpath "$class_root" -v script.library.pgc_quests | grep -Fq 'retireChroniclesPlayerProgressionState'
javap -classpath "$class_root" -v script.library.pgc_quests | grep -Fq 'PGC_STORED_CHRONICLE_GOLD_TOKENS_INDEX'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retireChroniclesPlayerProgressionState'
javap -classpath "$class_root" -v script.player.player_saga_quest | grep -Fq 'isRetiredChroniclesPlayerProgression'
javap -classpath "$class_root" -v script.systems.storyteller.storyteller_commands | grep -Fq 'retireChroniclesPlayerProgressionState'
! javap -classpath "$class_root" -v script.ai.creature_combat | grep -Fq 'expertise_bm_'
! javap -classpath "$class_root" -v script.conversation.trainer_beast_master | grep -Fq 'playerLearnBeastMasterSkill'
javap -classpath "$class_root" -v script.conversation.trainer_beast_master | grep -Fq 'conversation/trainer_beast_master'
javap -classpath "$class_root" -v script.conversation.trainer_beast_master | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.player.live_conversions | grep -Fq 'isPostNgeBeastMasterPlayerRuntimeRetired'
javap -classpath "$class_root" -v script.player.live_conversions | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.player.player_beastmaster | grep -Fq 'handleRetirePostNgeBeastMasterPlayerState'
! javap -classpath "$class_root" -v script.player.player_beastmaster | grep -Fq 'expertise_bm_'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostNgePlayerBeastFamilyBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgePlayerBeastFamilyBuffState'
beast_family_add_bytecode="$(javap -classpath "$class_root" -c -p script.systems.buff.buff_handler | sed -n '/public void bmBeastFamilyAddBuffHandler/,/public void bmBeastFamilyRemoveBuffHandler/p')"
beast_family_bytecode_identity_line="$(printf '%s\n' "$beast_family_add_bytecode" | grep -nF 'isRetiredPostNgePlayerBeastFamilyBuffName' | head -1 | cut -d: -f1)"
beast_family_bytecode_player_line="$(printf '%s\n' "$beast_family_add_bytecode" | grep -nF 'Method isPlayer:' | head -1 | cut -d: -f1)"
beast_family_bytecode_cleanup_line="$(printf '%s\n' "$beast_family_add_bytecode" | grep -nF 'retirePostNgeBeastMasterPlayerState' | head -1 | cut -d: -f1)"
beast_family_bytecode_return_line="$(printf '%s\n' "$beast_family_add_bytecode" | grep -nE '^[[:space:]]+[0-9]+: return$' | head -1 | cut -d: -f1)"
beast_family_bytecode_owned_line="$(printf '%s\n' "$beast_family_add_bytecode" | grep -nF 'isRetiredPostNgePlayerOwnedBeast' | head -1 | cut -d: -f1)"
beast_family_bytecode_nested_line="$(printf '%s\n' "$beast_family_add_bytecode" | grep -nF 'Method script/library/buff.applyBuff:' | head -1 | cut -d: -f1)"
for beast_family_bytecode_line in "$beast_family_bytecode_identity_line" "$beast_family_bytecode_player_line" "$beast_family_bytecode_cleanup_line" "$beast_family_bytecode_return_line" "$beast_family_bytecode_owned_line" "$beast_family_bytecode_nested_line"; do
    test -n "$beast_family_bytecode_line"
done
test "$beast_family_bytecode_identity_line" -lt "$beast_family_bytecode_player_line"
test "$beast_family_bytecode_player_line" -lt "$beast_family_bytecode_cleanup_line"
test "$beast_family_bytecode_cleanup_line" -lt "$beast_family_bytecode_return_line"
test "$beast_family_bytecode_return_line" -lt "$beast_family_bytecode_owned_line"
test "$beast_family_bytecode_owned_line" -lt "$beast_family_bytecode_nested_line"
verify_beast_family_direct_callback_bytecode()
{
    beast_family_callback_name="$1"
    beast_family_callback_next="$2"
    beast_family_callback_bytecode="$(javap -classpath "$class_root" -c -p script.player.player_beastmaster | sed -n "/public int $beast_family_callback_name(/,/public int $beast_family_callback_next(/p")"
    beast_family_callback_guard_line="$(printf '%s\n' "$beast_family_callback_bytecode" | grep -nF 'isRetiredPostNgeBeastMasterPlayer' | head -1 | cut -d: -f1)"
    beast_family_callback_cleanup_line="$(printf '%s\n' "$beast_family_callback_bytecode" | grep -nF 'retirePostNgeBeastMasterPlayerState' | head -1 | cut -d: -f1)"
    beast_family_callback_return_line="$(printf '%s\n' "$beast_family_callback_bytecode" | grep -nE '^[[:space:]]+[0-9]+: ireturn$' | head -1 | cut -d: -f1)"
    beast_family_callback_read_line="$(printf '%s\n' "$beast_family_callback_bytecode" | grep -nF 'Method script/library/buff.hasBuff:' | head -1 | cut -d: -f1)"
    for beast_family_callback_line in "$beast_family_callback_guard_line" "$beast_family_callback_cleanup_line" "$beast_family_callback_return_line" "$beast_family_callback_read_line"; do
        test -n "$beast_family_callback_line"
    done
    test "$beast_family_callback_guard_line" -lt "$beast_family_callback_cleanup_line"
    test "$beast_family_callback_cleanup_line" -lt "$beast_family_callback_return_line"
    test "$beast_family_callback_return_line" -lt "$beast_family_callback_read_line"
}
verify_beast_family_direct_callback_bytecode bm_pig_forage bm_helper_monkey_domestic
verify_beast_family_direct_callback_bytecode bm_helper_monkey_domestic bm_helper_monkey_engineering
verify_beast_family_direct_callback_bytecode bm_helper_monkey_engineering bm_helper_monkey_structure
verify_beast_family_direct_callback_bytecode bm_helper_monkey_structure bm_helper_monkey_munitions
verify_beast_family_direct_callback_bytecode bm_helper_monkey_munitions bm_helper_monkey_jedi
verify_beast_family_direct_callback_bytecode bm_helper_monkey_jedi bm_helper_monkey_shipwright
verify_beast_family_direct_callback_bytecode bm_helper_monkey_shipwright bm_dancing_cat
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuff'
javap -classpath "$class_root" -v script.library.buff | grep -Fq 'retirePostNgePlayerQueuedBattlefieldCommunicationState'
queued_battlefield_communication_admission_bytecode="$(javap -classpath "$class_root" -c -p script.library.buff | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
queued_battlefield_communication_bytecode_admission_line="$(printf '%s\n' "$queued_battlefield_communication_admission_bytecode" | grep -nF 'isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuff' | head -1 | cut -d: -f1)"
queued_battlefield_communication_bytecode_existing_line="$(printf '%s\n' "$queued_battlefield_communication_admission_bytecode" | grep -nF 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$queued_battlefield_communication_bytecode_admission_line"
test -n "$queued_battlefield_communication_bytecode_existing_line"
test "$queued_battlefield_communication_bytecode_admission_line" -lt "$queued_battlefield_communication_bytecode_existing_line"
queued_battlefield_communication_add_bytecode="$(javap -classpath "$class_root" -c -p script.systems.buff.buff_handler | sed -n '/battlefieldCommuncationsGlowAddBuffHandler/,/battlefieldCommuncationsGlowRemoveBuffHandler/p')"
queued_battlefield_communication_bytecode_name_line="$(printf '%s\n' "$queued_battlefield_communication_add_bytecode" | grep -nF 'isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuffName' | head -1 | cut -d: -f1)"
queued_battlefield_communication_bytecode_cleanup_line="$(printf '%s\n' "$queued_battlefield_communication_add_bytecode" | grep -nF 'retirePostNgePlayerQueuedBattlefieldCommunicationState' | head -1 | cut -d: -f1)"
queued_battlefield_communication_bytecode_return_line="$(printf '%s\n' "$queued_battlefield_communication_add_bytecode" | grep -nE '^[[:space:]]+[0-9]+: ireturn$' | head -1 | cut -d: -f1)"
queued_battlefield_communication_bytecode_writer_line="$(printf '%s\n' "$queued_battlefield_communication_add_bytecode" | grep -nF 'Method script/library/buff.removeBuff:' | head -1 | cut -d: -f1)"
for queued_battlefield_communication_bytecode_line in "$queued_battlefield_communication_bytecode_name_line" "$queued_battlefield_communication_bytecode_cleanup_line" "$queued_battlefield_communication_bytecode_return_line" "$queued_battlefield_communication_bytecode_writer_line"; do
    test -n "$queued_battlefield_communication_bytecode_line"
done
test "$queued_battlefield_communication_bytecode_name_line" -lt "$queued_battlefield_communication_bytecode_cleanup_line"
test "$queued_battlefield_communication_bytecode_cleanup_line" -lt "$queued_battlefield_communication_bytecode_return_line"
test "$queued_battlefield_communication_bytecode_return_line" -lt "$queued_battlefield_communication_bytecode_writer_line"
queued_battlefield_communication_remove_bytecode="$(javap -classpath "$class_root" -c -p script.systems.buff.buff_handler | sed -n '/battlefieldCommuncationsGlowRemoveBuffHandler/,/empireDayImperialRecruitmentAddBuffHandler/p')"
! printf '%s' "$queued_battlefield_communication_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuffName'
printf '%s' "$queued_battlefield_communication_remove_bytecode" | grep -Fq 'Method script/library/buff.applyBuff:'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'isRetiredPostNgeBeastMasterPlayerAction'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'isRetiredPostNgeBeastMasterPlayer'
! javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'expertise_bm_'
javap -classpath "$class_root" -v script.item.loot_schematic.loot_schematic | grep -Fq 'isRetiredPostNgePlayerKnowledgeItem'
javap -classpath "$class_root" -v script.item.loot_schematic.loot_schematic | grep -Fq 'retirePostNgePlayerKnowledgeItemState'
javap -classpath "$class_root" -v script.item.loot_schematic.loot_schematic | grep -Fq 'retirePostNgeBeastMasterPlayerState'
javap -classpath "$class_root" -constants script.item.loot_schematic.loot_schematic | grep -Fq 'TYPE_SKILL = 2'
javap -classpath "$class_root" -constants script.item.loot_schematic.loot_schematic | grep -Fq 'TYPE_ABILITY = 3'
javap -classpath "$class_root" -constants script.item.loot_schematic.loot_schematic | grep -Fq 'TYPE_BEAST_ABILITY = 5'
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
grep -Fxq 'transferServerPort=50005' "$source_local_options"
grep -Fxq 'centralServerServiceBindPort=50005' "$source_local_options"
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
regional_mission_terminal_bytecode="$(javap -classpath "$class_root" -c -p script.systems.gcw.flip_terminal_spawner)"
printf '%s' "$regional_mission_terminal_bytecode" | grep -Fq 'isPostNgeRegionalMissionTerminalRetired'
printf '%s' "$regional_mission_terminal_bytecode" | grep -Fq 'retireSpawner'
printf '%s' "$regional_mission_terminal_bytecode" | grep -Fq 'detachScript'
! printf '%s' "$regional_mission_terminal_bytecode" | grep -Fq 'createObject'
! printf '%s' "$regional_mission_terminal_bytecode" | grep -Fq 'getImperialPercentileByRegion'
! printf '%s' "$regional_mission_terminal_bytecode" | grep -Fq 'getRebelPercentileByRegion'
strings "$class_root/object/tangible/gcw/flip_terminal_spawner.iff" | grep -Fq 'systems.gcw.gcw_data_updater'
! strings "$class_root/object/tangible/gcw/flip_terminal_spawner.iff" | grep -Fq 'systems.gcw.flip_terminal_spawner'
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
gcw_banner_manager_bytecode="$(javap -classpath "$class_root" -c -p script.item.gcw_buff_banner.banner_buff_manager)"
printf '%s' "$gcw_banner_manager_bytecode" | grep -Fq 'handleDeleteSelf'
printf '%s' "$gcw_banner_manager_bytecode" | grep -Fq 'float 180.0f'
test "$(printf '%s' "$gcw_banner_manager_bytecode" | grep -Fc 'script/library/trial.cleanupObject')" -eq 2
! printf '%s' "$gcw_banner_manager_bytecode" | grep -Eq 'getPlayerProfession|getBannerBuff|buffPlayers|script/library/buff.applyBuff'
gcw_banner_buff_bytecode="$(javap -classpath "$class_root" -v script.library.buff)"
printf '%s' "$gcw_banner_buff_bytecode" | grep -Fq 'isRetiredPostNgeGcwBannerBuff'
printf '%s' "$gcw_banner_buff_bytecode" | grep -Fq 'retirePostNgeGcwBannerBuffState'
for retired_gcw_banner_buff in $retired_gcw_banner_buffs; do
    printf '%s' "$gcw_banner_buff_bytecode" | grep -Fq "$retired_gcw_banner_buff"
done
javap -classpath "$class_root" -v script.systems.combat.combat_base | grep -Fq 'banner_buff_commando'
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
neutral_mercenary_retired_bytecode="$(javap -classpath "$class_root" -c -p script.library.factions | sed -n '/isPostNgeNeutralMercenaryRetired/,/cleanupRetiredNeutralMercenaryState/p')"
printf '%s' "$neutral_mercenary_retired_bytecode" | grep -Fq 'iconst_1'
javap -classpath "$class_root" -c -p script.library.factions | grep -Fq 'cleanupRetiredNeutralMercenaryState'
javap -classpath "$class_root" -c -p script.library.factions | grep -Fq 'pvpNeutralSetMercenaryFaction'
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
imperial_recruiter_reward_bytecode="$(javap -classpath "$class_root" -c script.conversation.faction_recruiter_imperial | sed -n '/faction_recruiter_imperial_action_showFactionGcwRewardUi/,/faction_recruiter_imperial_action_enablePVPTimer/p')"
printf '%s' "$imperial_recruiter_reward_bytecode" | grep -Fq 'faction_recruiter_imperial_action_showGcwRewardsList'
! printf '%s' "$imperial_recruiter_reward_bytecode" | grep -Fq 'showInventorySUI'
rebel_recruiter_reward_bytecode="$(javap -classpath "$class_root" -c script.conversation.faction_recruiter_rebel | sed -n '/faction_recruiter_rebel_action_showFactionGcwRewardUi/,/faction_recruiter_rebel_action_enablePVPTimer/p')"
printf '%s' "$rebel_recruiter_reward_bytecode" | grep -Fq 'faction_recruiter_rebel_action_showGcwRewardsList'
! printf '%s' "$rebel_recruiter_reward_bytecode" | grep -Fq 'showInventorySUI'
! javap -classpath "$class_root" -v script.systems.camping.camp_controlpanel | grep -Fq 'faction_perk'
gcw_grant_bytecode="$(javap -classpath "$class_root" -c script.library.gcw | sed -n '/public static void _grantGcwPoints/,/public static void doGcwPointCsLogging/p')"
printf '%s' "$gcw_grant_bytecode" | grep -Fq '0: return'
! printf '%s' "$gcw_grant_bytecode" | grep -Fq 'pvpModifyCurrentGcwPoints'
! printf '%s' "$gcw_grant_bytecode" | grep -Fq 'gcwInvasionCreditForGCW'
! printf '%s' "$gcw_grant_bytecode" | grep -Fq 'grantGcwPointsToRegion'
gcw_recruitment_letter_bytecode="$(javap -classpath "$class_root" -c -p script.item.publish_gift.recruitment_letter)"
gcw_recruitment_letter_request="$(printf '%s' "$gcw_recruitment_letter_bytecode" | sed -n '/public int OnObjectMenuRequest/,/public int OnObjectMenuSelect/p')"
gcw_recruitment_letter_select="$(printf '%s' "$gcw_recruitment_letter_bytecode" | sed -n '/public int OnObjectMenuSelect/,/public boolean isOwner/p')"
printf '%s' "$gcw_recruitment_letter_request" | grep -Fq '0: iconst_1'
printf '%s' "$gcw_recruitment_letter_request" | grep -Fq '1: ireturn'
printf '%s' "$gcw_recruitment_letter_select" | grep -Fq '0: iconst_1'
printf '%s' "$gcw_recruitment_letter_select" | grep -Fq '1: ireturn'
! printf '%s' "$gcw_recruitment_letter_bytecode" | grep -Eq 'grantUnmodifiedGcwPoints|destroyObject|CustomerServiceLog|addRootMenu'
awk -F '\t' '$1 == "item_gcw_recruitment_letter_01_01" { found++; if ($2 + 0 != 31) exit 2 } END { if (found != 1) exit 3 }' "$work_publish_gifts"
awk -F '\t' '$1 == "item_gcw_recruitment_letter_01_01" { found++; if (index($0, "item.publish_gift.recruitment_letter") == 0) exit 2 } END { if (found != 1) exit 3 }' "$work_master_item_table"
gcw_level_authority_bytecode="$(javap -classpath "$class_root" -c -p script.library.gcw)"
test "$(printf '%s' "$gcw_level_authority_bytecode" | grep -Fc 'Method script/library/skill.getPrecuEncounterDifficulty' || true)" -eq 7
test "$(printf '%s' "$gcw_level_authority_bytecode" | grep -Fc 'Method getLevel' || true)" -eq 1
gcw_city_retired_bytecode="$(javap -classpath "$class_root" -c script.library.gcw | sed -n '/isPostNgeCityInvasionRetired/,/assignScanInterests/p')"
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'iconst_1'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'cleanupRetiredCityInvasionPlayerState'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'gcw.score.pid'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'destroyWaypointInDatapad'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'gcw_fatigue'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'gcw_spy_destroy_patrol_explosive_stack'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'gcw_entertainment.gcw_entertainment_pid'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'traderRepairPid'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'spyScoutPid'
printf '%s' "$gcw_city_retired_bytecode" | grep -Fq 'spyDestroyPid'
test "$(printf '%s' "$gcw_city_retired_bytecode" | grep -Fc 'Method isPostNgeCityInvasionRetired' || true)" -ge 30
javap -classpath "$class_root" -c -p script.systems.gcw.gcw_city | grep -Fq 'retirePostNgeCityInvasion'
javap -classpath "$class_root" -c -p script.planet.planet_base | grep -Fq 'retirePostNgeCityInvasionState'
! javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'gcw.invasionRunning.bestine'
test "$(javap -classpath "$class_root" -c -p script.player.player_faction | grep -Fc 'Method script/library/gcw.cleanupRetiredCityInvasionPlayerState' || true)" -ge 7
test "$(javap -classpath "$class_root" -c -p script.player.player_utility | grep -Fc 'Method script/library/gcw.cleanupRetiredCityInvasionPlayerState' || true)" -eq 7
test "$(javap -classpath "$class_root" -c -p script.systems.gcw.gcw_city_pylon | grep -Fc 'Method script/library/gcw.isPostNgeCityInvasionRetired' || true)" -eq 10
test "$(javap -classpath "$class_root" -c -p script.terminal.gcw_supply_terminal | grep -Fc 'Method script/library/gcw.isPostNgeCityInvasionRetired' || true)" -eq 12
retired_city_conversation_guard_count=0
for retired_city_conversation_class in script.conversation.imperial_general script.conversation.rebel_general script.conversation.imperial_offensive_supply_terminal script.conversation.imperial_defensive_supply_terminal script.conversation.rebel_offensive_supply_terminal script.conversation.rebel_defensive_supply_terminal; do
    conversation_guard_count="$(javap -classpath "$class_root" -c -p "$retired_city_conversation_class" | grep -Fc 'Method script/library/gcw.isPostNgeCityInvasionRetired' || true)"
    test "$conversation_guard_count" -eq 5
    retired_city_conversation_guard_count=$((retired_city_conversation_guard_count + conversation_guard_count))
done
test "$retired_city_conversation_guard_count" -eq 30
retired_city_asset_bytecode_guard_count=0
for retired_city_asset_spec in $retired_city_asset_runtime_specs; do
    retired_city_asset_name="${retired_city_asset_spec%%:*}"
    retired_city_asset_expected_guards="${retired_city_asset_spec##*:}"
    retired_city_asset_actual_guards="$(javap -classpath "$class_root" -c -p "script.systems.gcw.$retired_city_asset_name" | grep -Fc 'Method script/library/gcw.isPostNgeCityInvasionRetired' || true)"
    test "$retired_city_asset_actual_guards" -eq "$retired_city_asset_expected_guards"
    retired_city_asset_bytecode_guard_count=$((retired_city_asset_bytecode_guard_count + retired_city_asset_actual_guards))
done
test "$retired_city_asset_bytecode_guard_count" -eq 104
gcw_battlefield_retired_bytecode="$(javap -classpath "$class_root" -c script.library.gcw | sed -n '/isPostNgeQueuedBattlefieldRetired/,/assignScanInterests/p')"
printf '%s' "$gcw_battlefield_retired_bytecode" | grep -Fq 'iconst_1'
javap -classpath "$class_root" -c -p script.systems.gcw.pvp_battlefield | grep -Fq 'retirePostNgeQueuedBattlefield'
javap -classpath "$class_root" -c -p script.systems.gcw.battlefield_terminal | grep -Fq 'retirePostNgeQueuedBattlefieldTerminal'
javap -classpath "$class_root" -c -p script.systems.gcw.player_pvp | grep -Fq 'retirePostNgeQueuedBattlefieldPlayer'
for battlefield_vendor_class in imperial_pvp_bf_vendor rebel_pvp_bf_vendor; do
    battlefield_vendor_bytecode="$(javap -classpath "$class_root" -c -p "script.conversation.$battlefield_vendor_class")"
    printf '%s' "$battlefield_vendor_bytecode" | grep -Fq 'retirePostNgeQueuedBattlefieldVendor'
    printf '%s' "$battlefield_vendor_bytecode" | grep -Fq 'Method script/library/gcw.isPostNgeQueuedBattlefieldRetired'
    printf '%s' "$battlefield_vendor_bytecode" | grep -Fq 'item.vendor.container_list'
    printf '%s' "$battlefield_vendor_bytecode" | grep -Fq 'npc.vendor.vendor'
    printf '%s' "$battlefield_vendor_bytecode" | grep -Fq 'destroyObject'
    ! printf '%s' "$battlefield_vendor_bytecode" | grep -Fq 'showInventorySUI'
done
test "$(grep -Ec '^pvp_bf_(imperial|rebel)_vendor[[:space:]]' "$work_creatures_table")" -eq 2
grep -E '^pvp_bf_imperial_vendor[[:space:]].*imperial_pvp_bf_rewards.*npc\.vendor\.vendor,conversation\.imperial_pvp_bf_vendor' "$work_creatures_table" >/dev/null
grep -E '^pvp_bf_rebel_vendor[[:space:]].*rebel_pvp_bf_rewards.*npc\.vendor\.vendor,conversation\.rebel_pvp_bf_vendor' "$work_creatures_table" >/dev/null
grep -E 'strName\|4\|pvp_bf_imp_vendor.*strSpawns\|4\|pvp_bf_imperial_vendor' "$work_talus_vendor_buildout" >/dev/null
grep -E 'strName\|4\|rebel_pvp_bf_vendor.*strSpawns\|4\|pvp_bf_rebel_vendor' "$work_rori_vendor_buildout" >/dev/null
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
grep -Fq '{ "crafting_artisan_novice", "crafting_artisan" }' "$work_connection_server"
grep -Fq '{ "combat_brawler_novice", "combat_brawler" }' "$work_connection_server"
grep -Fq '{ "social_entertainer_novice", "social_entertainer" }' "$work_connection_server"
grep -Fq '{ "combat_marksman_novice", "combat_marksman" }' "$work_connection_server"
grep -Fq '{ "science_medic_novice", "science_medic" }' "$work_connection_server"
grep -Fq '{ "outdoors_scout_novice", "outdoors_scout" }' "$work_connection_server"
grep -Fq 'owns none of the six direct PRE-CU novice profession skills' "$work_connection_server"
! grep -Fq 'findProfessionForSkill' "$work_connection_server"
! grep -Fq 'PlayerCreationManager::getProfessionVector' "$work_connection_server"
grep -Fq 'getPrecuCtsStatAllocation(NetworkId const & actor, std::vector<int> & allocation)' "$work_commands_header"
grep -Fq 'applyPrecuCtsStatAllocation(NetworkId const & actor, std::vector<int> const & allocation)' "$work_commands_header"
cts_native_source="$(sed -n '/bool CommandCppFuncs::getPrecuCtsStatAllocation/,/bool CommandCppFuncs::canCommitStatMigration/p' "$work_commands")"
test "$(printf '%s' "$cts_native_source" | grep -Fc '!creature->isPlayerControlled()')" -eq 2
test "$(printf '%s' "$cts_native_source" | grep -Fc 'CommandCppFuncsNamespace::cms_statMigrationObjVarRoot')" -eq 2
printf '%s' "$cts_native_source" | grep -Fq 'CommandCppFuncsNamespace::validateStatMigrationTargets(*creature, currentAllocation)'
printf '%s' "$cts_native_source" | grep -Fq 'CommandCppFuncsNamespace::validateStatMigrationTargets(*creature, allocation)'
test "$(printf '%s' "$cts_native_source" | grep -Fc 'CommandCppFuncsNamespace::applyStatMigration(*creature, allocation)')" -eq 1
grep -Fq 'JF("_getPrecuCtsStatAllocation", "(J)[I", getPrecuCtsStatAllocation)' "$work_script_methods_attributes"
grep -Fq 'JF("_applyPrecuCtsStatAllocation", "(J[I)Z", applyPrecuCtsStatAllocation)' "$work_script_methods_attributes"
grep -Fq 'GetArrayLength(allocation) != Attributes::NumberOfAttributes' "$work_script_methods_attributes"
grep -Fq 'GetIntArrayRegion(allocation, 0, Attributes::NumberOfAttributes, values)' "$work_script_methods_attributes"
javap -classpath "$class_root" -p -s script.base_class | grep -Fq '_getPrecuCtsStatAllocation'
javap -classpath "$class_root" -p -s script.base_class | grep -Fq 'descriptor: (J)[I'
javap -classpath "$class_root" -p -s script.base_class | grep -Fq '_applyPrecuCtsStatAllocation'
javap -classpath "$class_root" -p -s script.base_class | grep -Fq 'descriptor: (J[I)Z'
nm -C "$server_game_archive" | grep -Fq 'CommandCppFuncs::getPrecuCtsStatAllocation'
nm -C "$server_game_archive" | grep -Fq 'CommandCppFuncs::applyPrecuCtsStatAllocation'
strings "$binary" | grep -Fq '_getPrecuCtsStatAllocation'
strings "$binary" | grep -Fq '_applyPrecuCtsStatAllocation'
cts_upload_bytecode="$(javap -classpath "$class_root" -c script.player.base.base_player | sed -n '/OnUploadCharacter/,/OnDownloadCharacter/p')"
printf '%s' "$cts_upload_bytecode" | grep -Fq 'using PRE-CU skill-box authority'
printf '%s' "$cts_upload_bytecode" | grep -Fq 'precu.statMigration'
printf '%s' "$cts_upload_bytecode" | grep -Fq 'precuCtsStatAllocationVersion'
printf '%s' "$cts_upload_bytecode" | grep -Fq 'precuCtsStatAllocation'
printf '%s' "$cts_upload_bytecode" | grep -Fq 'getPrecuCtsStatAllocation'
! printf '%s' "$cts_upload_bytecode" | grep -Fq 'getSkillTemplate'
! printf '%s' "$cts_upload_bytecode" | grep -Fq 'getWorkingSkill'
! printf '%s' "$cts_upload_bytecode" | grep -Fq 'getCommandListingForPlayer'
cts_download_bytecode="$(javap -classpath "$class_root" -c script.player.base.base_player | sed -n '/OnDownloadCharacter/,/OnSkillModDone/p')"
printf '%s' "$cts_download_bytecode" | grep -Fq 'isRetiredNgeProgressionSkillName'
printf '%s' "$cts_download_bytecode" | grep -Fq 'reattachQuestScripts'
printf '%s' "$cts_download_bytecode" | grep -Fq 'precuCtsStatAllocationVersion'
printf '%s' "$cts_download_bytecode" | grep -Fq 'precuCtsStatAllocation'
printf '%s' "$cts_download_bytecode" | grep -Fq 'applyPrecuCtsStatAllocation'
! printf '%s' "$cts_download_bytecode" | grep -Fq 'setSkillTemplate'
! printf '%s' "$cts_download_bytecode" | grep -Fq 'grantCommand'
javap -classpath "$class_root" -v script.systems.battlefield.player_battlefield | grep -Fq 'addFactionStanding'
gcw_static_retired_bytecode="$(javap -classpath "$class_root" -c script.library.gcw | sed -n '/isPostNgeFixedStaticBaseRetired/,/getPub30StaticBaseControllerId/p')"
printf '%s' "$gcw_static_retired_bytecode" | grep -Fq 'iconst_1'
javap -classpath "$class_root" -c -p script.player.player_faction | grep -Fq 'cleanupRetiredFixedStaticBaseState'
javap -classpath "$class_root" -c -p script.player.player_faction | grep -Fq 'cleanupRetiredNeutralMercenaryState'
javap -classpath "$class_root" -constants script.library.force_rank | grep -Fq 'REQUEST_DEMOTION_COST = 2000'
javap -classpath "$class_root" -constants script.library.force_rank | grep -Fq 'VOTE_CHALLENGE_COST = 1000'
javap -classpath "$class_root" -c -p script.library.force_rank | grep -Fq 'isForceRankingEnabled'
javap -classpath "$class_root" -c -p script.systems.gcw.player_force_rank | grep -Fq 'getEnclaveObjId'
javap -classpath "$class_root" -c -p script.systems.gcw.enclave_controller | grep -Fq 'performEnclaveMaintenance'
javap -classpath "$class_root" -c -p script.library.jedi_trials | grep -Fq 'isForceRankingEnabled'
javap -classpath "$class_root" -c -p script.theme_park.jedi_trials.knight_trials | grep -Fq 'isForceRankingEnabled'
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
expertise_cache_bytecode="$(javap -classpath "$class_root" -c script.library.expertise | sed -n '/cacheExpertiseProcReacList/,/autoAllocateExpertiseByLevel/p')"
printf '%s' "$expertise_cache_bytecode" | grep -Fq 'proc.isRetiredPostNgePlayerProcActor'
printf '%s' "$expertise_cache_bytecode" | grep -Fq 'proc.retirePostNgePlayerProcState'
printf '%s' "$expertise_cache_bytecode" | grep -Fq 'getSkillStatModListingForPlayer'
proc_bytecode="$(javap -classpath "$class_root" -c -p script.library.proc)"
printf '%s' "$proc_bytecode" | grep -Fq 'isRetiredPostNgePlayerProcBuff'
printf '%s' "$proc_bytecode" | grep -Fq 'isRetiredPostNgePlayerProcAction'
proc_cleanup_bytecode="$(printf '%s' "$proc_bytecode" | sed -n '/retirePostNgePlayerProcState/,/executeProcEffects/p')"
printf '%s' "$proc_cleanup_bytecode" | grep -Fq 'buff.getAllBuffs'
printf '%s' "$proc_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$proc_cleanup_bytecode" | grep -Fq 'buff.removeBuff'
buff_admission_bytecode="$(javap -classpath "$class_root" -c -p script.library.buff | sed -n '/canApplyBuff(script.obj_id, script.obj_id, int)/,/applyBuff(script.obj_id, java.lang.String)/p')"
printf '%s' "$buff_admission_bytecode" | grep -Fq 'proc.isRetiredPostNgePlayerProcBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerCommandGrantBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerActionRegenBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerDamageDealtOverrideBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerWeaponSpeedOverrideBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerCriticalOverrideBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerLuckHitOverrideBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerForsakeFearChannelBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerChannelHealBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerRadarInvisibilityBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionMovementBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionImmunityBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionInspirationBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionProxyBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerCommandoSuppressionBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerDamageReductionBuff'
printf '%s' "$buff_admission_bytecode" | grep -Fq 'isRetiredPostNgePlayerModifierBuff'
buff_modifier_bytecode="$(javap -classpath "$class_root" -c -p script.library.buff)"
for profession_movement_prefix in $profession_movement_prefixes; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "$profession_movement_prefix"
done
profession_movement_name_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerProfessionMovementBuffName(java.lang.String)/,/isRetiredPostNgePlayerProfessionMovementBuff(script.obj_id, script.combat_engine\$buff_data)/p')"
printf '%s' "$profession_movement_name_predicate_bytecode" | grep -Fq 'java/lang/String.startsWith'
profession_movement_buff_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerProfessionMovementBuff(script.obj_id, script.combat_engine\$buff_data)/,/retirePostNgePlayerProfessionMovementBuffState/p')"
printf '%s' "$profession_movement_buff_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$profession_movement_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionMovementBuffName'
printf '%s' "$profession_movement_buff_predicate_bytecode" | grep -Fq 'String movement'
profession_movement_table_bytecode_line="$(printf '%s\n' "$profession_movement_buff_predicate_bytecode" | grep -Fn 'String en_unhealthy_fixation_debuff' | head -1 | cut -d: -f1)"
profession_movement_effect_bytecode_line="$(printf '%s\n' "$profession_movement_buff_predicate_bytecode" | grep -Fn 'String movement' | head -1 | cut -d: -f1)"
test -n "$profession_movement_table_bytecode_line" -a -n "$profession_movement_effect_bytecode_line"
test "$profession_movement_table_bytecode_line" -lt "$profession_movement_effect_bytecode_line"
profession_movement_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerProfessionMovementBuffState/,/isRetiredPostNgePlayerGroupBuffName/p')"
printf '%s' "$profession_movement_cleanup_bytecode" | grep -Fq 'Method getAllBuffs'
printf '%s' "$profession_movement_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$profession_movement_cleanup_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerProfessionMovementBuffState'
for profession_immunity_name in $retired_profession_immunity_names; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "$profession_immunity_name"
done
profession_immunity_name_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerProfessionImmunityBuffName(java.lang.String)/,/isRetiredPostNgePlayerProfessionImmunityBuff(script.obj_id, script.combat_engine\$buff_data)/p')"
printf '%s' "$profession_immunity_name_predicate_bytecode" | grep -Fq 'java/lang/String.equals'
profession_immunity_buff_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerProfessionImmunityBuff(script.obj_id, script.combat_engine\$buff_data)/,/retirePostNgePlayerProfessionImmunityState/p')"
printf '%s' "$profession_immunity_buff_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$profession_immunity_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionImmunityBuffName'
profession_immunity_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerProfessionImmunityState/,/isRetiredPostNgePlayerProfessionInspirationBuffName/p')"
printf '%s' "$profession_immunity_cleanup_bytecode" | grep -Fq 'Method getAllBuffs'
printf '%s' "$profession_immunity_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$profession_immunity_cleanup_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerProfessionImmunityState'
profession_immunity_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int immunityAddBuffHandler/,/public int dotReductionAddBuffHandler/p')"
profession_immunity_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int immunityRemoveBuffHandler/,/public int expertiseImmunityAddBuffHandler/p')"
profession_immunity_player_bytecode_line="$(printf '%s\n' "$profession_immunity_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
profession_immunity_predicate_bytecode_line="$(printf '%s\n' "$profession_immunity_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerProfessionImmunityBuffName' | head -1 | cut -d: -f1)"
profession_immunity_cleanup_bytecode_line="$(printf '%s\n' "$profession_immunity_add_bytecode" | grep -Fn 'retirePostNgePlayerProfessionImmunityState' | head -1 | cut -d: -f1)"
profession_immunity_return_bytecode_line="$(printf '%s\n' "$profession_immunity_add_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$profession_immunity_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
profession_immunity_dot_writer_bytecode_line="$(printf '%s\n' "$profession_immunity_add_bytecode" | grep -Fn 'performBuffDotImmunity' | head -1 | cut -d: -f1)"
profession_immunity_modifier_writer_bytecode_line="$(printf '%s\n' "$profession_immunity_add_bytecode" | grep -Fn 'removeAllModifiersOfType' | head -1 | cut -d: -f1)"
profession_immunity_buff_reader_bytecode_line="$(printf '%s\n' "$profession_immunity_add_bytecode" | grep -Fn 'buff.getAllBuffs' | head -1 | cut -d: -f1)"
profession_immunity_scriptvar_writer_bytecode_line="$(printf '%s\n' "$profession_immunity_add_bytecode" | grep -Fn 'utils.setScriptVar' | head -1 | cut -d: -f1)"
for profession_immunity_bytecode_line in "$profession_immunity_player_bytecode_line" "$profession_immunity_predicate_bytecode_line" "$profession_immunity_cleanup_bytecode_line" "$profession_immunity_return_bytecode_line" "$profession_immunity_dot_writer_bytecode_line" "$profession_immunity_modifier_writer_bytecode_line" "$profession_immunity_buff_reader_bytecode_line" "$profession_immunity_scriptvar_writer_bytecode_line"; do
    test -n "$profession_immunity_bytecode_line"
done
test "$profession_immunity_player_bytecode_line" -lt "$profession_immunity_predicate_bytecode_line"
test "$profession_immunity_predicate_bytecode_line" -lt "$profession_immunity_cleanup_bytecode_line"
test "$profession_immunity_cleanup_bytecode_line" -lt "$profession_immunity_return_bytecode_line"
test "$profession_immunity_return_bytecode_line" -lt "$profession_immunity_dot_writer_bytecode_line"
test "$profession_immunity_return_bytecode_line" -lt "$profession_immunity_modifier_writer_bytecode_line"
test "$profession_immunity_return_bytecode_line" -lt "$profession_immunity_buff_reader_bytecode_line"
test "$profession_immunity_return_bytecode_line" -lt "$profession_immunity_scriptvar_writer_bytecode_line"
! printf '%s' "$profession_immunity_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionImmunityBuffName'
printf '%s' "$profession_immunity_remove_bytecode" | grep -Fq 'utils.removeScriptVarTree'
printf '%s' "$profession_immunity_remove_bytecode" | grep -Fq 'ireturn'
for profession_inspiration_name in $profession_inspiration_names; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "$profession_inspiration_name"
done
profession_inspiration_name_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerProfessionInspirationBuffName(java.lang.String)/,/isRetiredPostNgePlayerProfessionInspirationBuff(script.obj_id, script.combat_engine\$buff_data)/p')"
printf '%s' "$profession_inspiration_name_predicate_bytecode" | grep -Fq 'java/lang/String.equals'
profession_inspiration_buff_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerProfessionInspirationBuff(script.obj_id, script.combat_engine\$buff_data)/,/clearPostNgePlayerProfessionInspirationScriptVars/p')"
printf '%s' "$profession_inspiration_buff_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$profession_inspiration_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionInspirationBuffName'
profession_inspiration_scriptvar_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerProfessionInspirationScriptVars/,/retirePostNgePlayerProfessionInspirationState/p')"
printf '%s' "$profession_inspiration_scriptvar_cleanup_bytecode" | grep -Fq 'utils.removeScriptVarTree'
for profession_inspiration_scriptvar in buff.xpBonus buff.xpBonusGeneral buff.craftBonus buff.faction buff.instrument buff.prop buff.holoemote; do
    printf '%s' "$profession_inspiration_scriptvar_cleanup_bytecode" | grep -Fq "$profession_inspiration_scriptvar"
done
profession_inspiration_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerProfessionInspirationState/,/isRetiredPostNgePlayerGroupBuffName/p')"
printf '%s' "$profession_inspiration_cleanup_bytecode" | grep -Fq 'Method getAllBuffs'
printf '%s' "$profession_inspiration_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$profession_inspiration_cleanup_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$profession_inspiration_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerProfessionInspirationScriptVars'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerProfessionInspirationState'
for profession_proxy_name in $profession_proxy_names; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "$profession_proxy_name"
done
profession_proxy_name_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerProfessionProxyBuffName(java.lang.String)/,/isRetiredPostNgePlayerProfessionProxyBuff(script.obj_id, script.combat_engine\$buff_data)/p')"
printf '%s' "$profession_proxy_name_predicate_bytecode" | grep -Fq 'java/lang/String.equals'
profession_proxy_buff_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerProfessionProxyBuff(script.obj_id, script.combat_engine\$buff_data)/,/retirePostNgePlayerProfessionProxyState/p')"
printf '%s' "$profession_proxy_buff_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$profession_proxy_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionProxyBuffName'
profession_proxy_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerProfessionProxyState/,/isRetiredPostNgePlayerGroupBuffName/p')"
printf '%s' "$profession_proxy_cleanup_bytecode" | grep -Fq 'Method getAllBuffs'
printf '%s' "$profession_proxy_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$profession_proxy_cleanup_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerProfessionProxyState'
exclusive_proxy_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int exclusiveProxyAddBuffHandler/,/public int exclusiveProxyRemoveBuffHandler/p')"
exclusive_proxy_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int exclusiveProxyRemoveBuffHandler/,/public int excludeSelfAddBuffHandler/p')"
exclude_self_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int excludeSelfAddBuffHandler/,/public int excludeSelfRemoveBuffHandler/p')"
exclude_self_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int excludeSelfRemoveBuffHandler/,/public int delayAttackAddBuffHandler/p')"
exclusive_proxy_predicate_bytecode_line="$(printf '%s\n' "$exclusive_proxy_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerProfessionProxyBuffName' | head -1 | cut -d: -f1)"
exclusive_proxy_cleanup_bytecode_line="$(printf '%s\n' "$exclusive_proxy_add_bytecode" | grep -Fn 'retirePostNgePlayerProfessionProxyState' | head -1 | cut -d: -f1)"
exclusive_proxy_return_bytecode_line="$(printf '%s\n' "$exclusive_proxy_add_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$exclusive_proxy_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
exclusive_proxy_read_bytecode_line="$(printf '%s\n' "$exclusive_proxy_add_bytecode" | grep -Fn 'buff.getAllBuffs' | head -1 | cut -d: -f1)"
exclusive_proxy_writer_bytecode_line="$(printf '%s\n' "$exclusive_proxy_add_bytecode" | grep -Fn 'buff.applyBuff' | head -1 | cut -d: -f1)"
for profession_proxy_bytecode_line in "$exclusive_proxy_predicate_bytecode_line" "$exclusive_proxy_cleanup_bytecode_line" "$exclusive_proxy_return_bytecode_line" "$exclusive_proxy_read_bytecode_line" "$exclusive_proxy_writer_bytecode_line"; do
    test -n "$profession_proxy_bytecode_line"
done
test "$exclusive_proxy_predicate_bytecode_line" -lt "$exclusive_proxy_cleanup_bytecode_line"
test "$exclusive_proxy_cleanup_bytecode_line" -lt "$exclusive_proxy_return_bytecode_line"
test "$exclusive_proxy_return_bytecode_line" -lt "$exclusive_proxy_read_bytecode_line"
test "$exclusive_proxy_return_bytecode_line" -lt "$exclusive_proxy_writer_bytecode_line"
! printf '%s' "$exclusive_proxy_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionProxyBuffName'
printf '%s' "$exclusive_proxy_remove_bytecode" | grep -Fq 'ireturn'
exclude_self_predicate_bytecode_line="$(printf '%s\n' "$exclude_self_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerProfessionProxyBuffName' | head -1 | cut -d: -f1)"
exclude_self_cleanup_bytecode_line="$(printf '%s\n' "$exclude_self_add_bytecode" | grep -Fn 'retirePostNgePlayerProfessionProxyState' | head -1 | cut -d: -f1)"
exclude_self_return_bytecode_line="$(printf '%s\n' "$exclude_self_add_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$exclude_self_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
exclude_self_read_bytecode_line="$(printf '%s\n' "$exclude_self_add_bytecode" | grep -Fn 'buff.getAllBuffs' | head -1 | cut -d: -f1)"
exclude_self_writer_bytecode_line="$(printf '%s\n' "$exclude_self_add_bytecode" | grep -Fn 'buff.applyBuff' | head -1 | cut -d: -f1)"
for profession_proxy_bytecode_line in "$exclude_self_predicate_bytecode_line" "$exclude_self_cleanup_bytecode_line" "$exclude_self_return_bytecode_line" "$exclude_self_read_bytecode_line" "$exclude_self_writer_bytecode_line"; do
    test -n "$profession_proxy_bytecode_line"
done
test "$exclude_self_predicate_bytecode_line" -lt "$exclude_self_cleanup_bytecode_line"
test "$exclude_self_cleanup_bytecode_line" -lt "$exclude_self_return_bytecode_line"
test "$exclude_self_return_bytecode_line" -lt "$exclude_self_read_bytecode_line"
test "$exclude_self_return_bytecode_line" -lt "$exclude_self_writer_bytecode_line"
! printf '%s' "$exclude_self_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfessionProxyBuffName'
printf '%s' "$exclude_self_remove_bytecode" | grep -Fq 'ireturn'
profession_heal_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int healEffectAddBuffHandler/,/public int healEffectRemoveBuffHandler/p')"
profession_heal_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int healEffectRemoveBuffHandler/,/public int buildabuffAddBuffHandler/p')"
profession_heal_player_guard_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
profession_heal_inspiration_predicate_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerProfessionInspirationBuffName' | head -1 | cut -d: -f1)"
profession_heal_inspiration_cleanup_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'retirePostNgePlayerProfessionInspirationState' | head -1 | cut -d: -f1)"
profession_heal_inspiration_return_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$profession_heal_inspiration_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
profession_heal_proxy_predicate_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerProfessionProxyBuffName' | head -1 | cut -d: -f1)"
profession_heal_proxy_cleanup_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'retirePostNgePlayerProfessionProxyState' | head -1 | cut -d: -f1)"
profession_heal_proxy_return_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$profession_heal_proxy_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
profession_heal_spy_predicate_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'isRetiredPostNgeSpyBuffName' | head -1 | cut -d: -f1)"
profession_heal_spy_cleanup_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'retirePostNgeSpyPlayerState' | head -1 | cut -d: -f1)"
profession_heal_spy_return_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$profession_heal_spy_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
profession_heal_first_writer_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'script/library/healing.healDamage' | head -1 | cut -d: -f1)"
profession_heal_second_writer_bytecode_line="$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fn 'script/library/healing.healDamage' | tail -1 | cut -d: -f1)"
test "$(printf '%s\n' "$profession_heal_add_bytecode" | grep -Fc 'script/library/healing.healDamage')" -eq 2
for profession_heal_bytecode_line in "$profession_heal_player_guard_bytecode_line" "$profession_heal_inspiration_predicate_bytecode_line" "$profession_heal_inspiration_cleanup_bytecode_line" "$profession_heal_inspiration_return_bytecode_line" "$profession_heal_proxy_predicate_bytecode_line" "$profession_heal_proxy_cleanup_bytecode_line" "$profession_heal_proxy_return_bytecode_line" "$profession_heal_spy_predicate_bytecode_line" "$profession_heal_spy_cleanup_bytecode_line" "$profession_heal_spy_return_bytecode_line" "$profession_heal_first_writer_bytecode_line" "$profession_heal_second_writer_bytecode_line"; do
    test -n "$profession_heal_bytecode_line"
done
test "$profession_heal_player_guard_bytecode_line" -lt "$profession_heal_inspiration_predicate_bytecode_line"
test "$profession_heal_inspiration_predicate_bytecode_line" -lt "$profession_heal_inspiration_cleanup_bytecode_line"
test "$profession_heal_inspiration_cleanup_bytecode_line" -lt "$profession_heal_inspiration_return_bytecode_line"
test "$profession_heal_inspiration_return_bytecode_line" -lt "$profession_heal_proxy_predicate_bytecode_line"
test "$profession_heal_proxy_predicate_bytecode_line" -lt "$profession_heal_proxy_cleanup_bytecode_line"
test "$profession_heal_proxy_cleanup_bytecode_line" -lt "$profession_heal_proxy_return_bytecode_line"
test "$profession_heal_proxy_return_bytecode_line" -lt "$profession_heal_spy_predicate_bytecode_line"
test "$profession_heal_spy_predicate_bytecode_line" -lt "$profession_heal_spy_cleanup_bytecode_line"
test "$profession_heal_spy_cleanup_bytecode_line" -lt "$profession_heal_spy_return_bytecode_line"
test "$profession_heal_spy_return_bytecode_line" -lt "$profession_heal_first_writer_bytecode_line"
test "$profession_heal_spy_return_bytecode_line" -lt "$profession_heal_second_writer_bytecode_line"
! printf '%s' "$profession_heal_remove_bytecode" | grep -Fq 'isRetiredPostNgePlayerProfession'
! printf '%s' "$profession_heal_remove_bytecode" | grep -Fq 'isRetiredPostNgeSpyBuffName'
printf '%s' "$profession_heal_remove_bytecode" | grep -Fq 'ireturn'
profession_proxy_combat_base_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base)"
officer_action_predicate_bytecode="$(printf '%s' "$profession_proxy_combat_base_bytecode" | sed -n '/isRetiredPostNgeOfficerPlayerAction/,/isRetiredPostNgeForceSensitivePlayerAction/p')"
for officer_proxy_action in 'String of_' 'String paintTarget' 'String paintTarget_' 'String applyVortexSnare'; do
    printf '%s' "$officer_action_predicate_bytecode" | grep -Fq "$officer_proxy_action"
done
bounty_hunter_action_predicate_bytecode="$(printf '%s' "$profession_proxy_combat_base_bytecode" | sed -n '/isRetiredPostNgeBountyHunterPlayerAction/,/isRetiredPostNgeCommandoPlayerAction/p')"
for bounty_hunter_proxy_action in 'String bh_' 'String dire_root_recourse' 'String dire_snare_recourse' 'String bountycheck'; do
    printf '%s' "$bounty_hunter_action_predicate_bytecode" | grep -Fq "$bounty_hunter_proxy_action"
done
profession_proxy_combat_actions_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_actions)"
paint_target_bytecode="$(printf '%s' "$profession_proxy_combat_actions_bytecode" | sed -n '/public int paintTarget/,/public int blueGlowie/p')"
printf '%s' "$paint_target_bytecode" | grep -Fq 'String paintTarget'
printf '%s' "$paint_target_bytecode" | grep -Fq 'combatStandardAction'
for profession_proxy_direct_spec in \
    'applyVortexSnare|isRetiredPostNgeOfficerPlayerAction|buff.hasBuff|getBaseCooldownTime' \
    'dire_root_recourse|isRetiredPostNgeBountyHunterPlayerAction|buff.hasBuff|dire_snare_recourse' \
    'dire_snare_recourse|isRetiredPostNgeBountyHunterPlayerAction|buff.hasBuff|bountycheck' \
    'bountycheck|isRetiredPostNgeBountyHunterPlayerAction|bounty_hunter.canCheckForBounty|fs_drain_1'; do
    profession_proxy_direct_name="${profession_proxy_direct_spec%%|*}"
    profession_proxy_direct_rest="${profession_proxy_direct_spec#*|}"
    profession_proxy_direct_predicate="${profession_proxy_direct_rest%%|*}"
    profession_proxy_direct_rest="${profession_proxy_direct_rest#*|}"
    profession_proxy_direct_mutation="${profession_proxy_direct_rest%%|*}"
    profession_proxy_direct_next="${profession_proxy_direct_rest#*|}"
    profession_proxy_direct_bytecode="$(printf '%s' "$profession_proxy_combat_actions_bytecode" | sed -n "/public int $profession_proxy_direct_name/,/public .* $profession_proxy_direct_next/p")"
    profession_proxy_direct_predicate_bytecode_line="$(printf '%s\n' "$profession_proxy_direct_bytecode" | grep -Fn "$profession_proxy_direct_predicate" | head -1 | cut -d: -f1)"
    profession_proxy_direct_return_bytecode_line="$(printf '%s\n' "$profession_proxy_direct_bytecode" | grep -Fn 'ireturn' | awk -F: -v predicate="$profession_proxy_direct_predicate_bytecode_line" '$1 > predicate { print $1; exit }')"
    profession_proxy_direct_mutation_bytecode_line="$(printf '%s\n' "$profession_proxy_direct_bytecode" | grep -Fn "$profession_proxy_direct_mutation" | head -1 | cut -d: -f1)"
    test -n "$profession_proxy_direct_predicate_bytecode_line"
    test "$profession_proxy_direct_predicate_bytecode_line" -lt "$profession_proxy_direct_return_bytecode_line"
    test "$profession_proxy_direct_return_bytecode_line" -lt "$profession_proxy_direct_mutation_bytecode_line"
done
for commando_suppression_name in $commando_suppression_names; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "$commando_suppression_name"
done
commando_suppression_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerCommandoSuppressionState/,/isRetiredPostNgePlayerGroupBuffName/p')"
printf '%s' "$commando_suppression_cleanup_bytecode" | grep -Fq 'Method getAllBuffs'
printf '%s' "$commando_suppression_cleanup_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$commando_suppression_cleanup_bytecode" | grep -Fq 'String supress_movement'
printf '%s' "$commando_suppression_cleanup_bytecode" | grep -Fq 'Method removeSlowDownEffect'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerCommandoSuppressionState'
commando_suppression_nested_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int supression_handlerAddBuffHandler/,/public int supression_handlerRemoveBuffHandler/p')"
commando_suppression_movement_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/public int movementSupressingEffectAddBuffHandler/,/public int movementSupressingEffectRemoveBuffHandler/p')"
for commando_suppression_add_bytecode in "$commando_suppression_nested_add_bytecode" "$commando_suppression_movement_add_bytecode"; do
    commando_suppression_cleanup_bytecode_line="$(printf '%s\n' "$commando_suppression_add_bytecode" | grep -Fn 'retirePostNgePlayerCommandoSuppressionState' | head -1 | cut -d: -f1)"
    commando_suppression_return_bytecode_line="$(printf '%s\n' "$commando_suppression_add_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$commando_suppression_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
    test -n "$commando_suppression_cleanup_bytecode_line"
    test -n "$commando_suppression_return_bytecode_line"
done
test "$(printf '%s\n' "$commando_suppression_nested_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$commando_suppression_nested_add_bytecode" | grep -Fn 'getEnhancedSkillStatisticModifierUncapped' | head -1 | cut -d: -f1)"
test "$(printf '%s\n' "$commando_suppression_movement_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$commando_suppression_movement_add_bytecode" | grep -Fn 'addSlowDownEffect' | head -1 | cut -d: -f1)"
performance_bytecode="$(javap -classpath "$class_root" -c -p script.library.performance)"
performance_inspiration_gate_bytecode="$(printf '%s' "$performance_bytecode" | sed -n '/public static boolean inspire(script.obj_id, java.lang.String)/,/private static boolean isNgeInspirationEnabled/p')"
printf '%s' "$performance_inspiration_gate_bytecode" | grep -Fq 'isNgeInspirationEnabled'
performance_inspiration_enabled_bytecode="$(printf '%s' "$performance_bytecode" | sed -n '/private static boolean isNgeInspirationEnabled/,/private static java.lang.String getFormattedInspirationDuration/p')"
printf '%s' "$performance_inspiration_enabled_bytecode" | grep -Fq 'iconst_0'
printf '%s' "$performance_inspiration_enabled_bytecode" | grep -Fq 'ireturn'
for damage_reduction_modifier in $damage_reduction_modifiers; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "$damage_reduction_modifier"
done
damage_reduction_modifier_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerDamageReductionModifier(java.lang.String)/,/isRetiredPostNgePlayerDamageReductionBuff/p')"
printf '%s' "$damage_reduction_modifier_predicate_bytecode" | grep -Fq 'java/lang/String.equals'
damage_reduction_buff_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerDamageReductionBuff/,/clearPostNgePlayerDamageReductionState/p')"
printf '%s' "$damage_reduction_buff_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$damage_reduction_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerDamageReductionModifier'
damage_reduction_clear_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerDamageReductionState/,/retirePostNgePlayerDamageReductionState/p')"
printf '%s' "$damage_reduction_clear_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$damage_reduction_clear_bytecode" | grep -Fq 'Method hasSkillModModifier'
printf '%s' "$damage_reduction_clear_bytecode" | grep -Fq 'Method removeAttribOrSkillModModifier'
printf '%s' "$damage_reduction_clear_bytecode" | grep -Fq 'Method getSkillStatMod'
printf '%s' "$damage_reduction_clear_bytecode" | grep -Fq 'Method applySkillStatisticModifier'
printf '%s' "$damage_reduction_clear_bytecode" | grep -Fq 'junkDealerDamageDecrease'
damage_reduction_retire_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerDamageReductionState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$damage_reduction_retire_bytecode" | grep -Fq 'Method getAllBuffs'
printf '%s' "$damage_reduction_retire_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$damage_reduction_retire_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$damage_reduction_retire_bytecode" | grep -Fq 'clearPostNgePlayerDamageReductionState'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerDamageReductionState'
damage_reduction_admission_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/canApplyBuff(script.obj_id, script.obj_id, int)/,/getGroups/p')"
damage_reduction_admission_line="$(printf '%s\n' "$damage_reduction_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerDamageReductionBuff' | head -1 | cut -d: -f1)"
damage_reduction_modifier_gate_line="$(printf '%s\n' "$damage_reduction_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerModifierBuff' | head -1 | cut -d: -f1)"
damage_reduction_existing_line="$(printf '%s\n' "$damage_reduction_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$damage_reduction_admission_line"
test -n "$damage_reduction_modifier_gate_line"
test -n "$damage_reduction_existing_line"
test "$damage_reduction_admission_line" -lt "$damage_reduction_modifier_gate_line"
test "$damage_reduction_modifier_gate_line" -lt "$damage_reduction_existing_line"
buff_command_grant_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerBuffCommandGrant(java.lang.String)/,/isRetiredPostNgePlayerCommandGrantBuff/p')"
printf '%s' "$buff_command_grant_predicate_bytecode" | grep -Fq 'RETIRED_POST_NGE_PLAYER_BUFF_COMMAND_GRANTS'
buff_command_grant_buff_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCommandGrantBuff/,/retirePostNgePlayerCommandGrantBuffState/p')"
printf '%s' "$buff_command_grant_buff_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_command_grant_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerBuffCommandGrant'
buff_command_grant_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerCommandGrantBuffState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$buff_command_grant_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_command_grant_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_command_grant_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_command_grant_cleanup_bytecode" | grep -Fq 'hasCommand'
printf '%s' "$buff_command_grant_cleanup_bytecode" | grep -Fq 'revokeCommand'
buff_action_drain_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerActionDrainEffect(java.lang.String)/,/isRetiredPostNgePlayerActionDrainBuff/p')"
printf '%s' "$buff_action_drain_effect_predicate_bytecode" | grep -Fq 'immediate_action_drain'
buff_action_drain_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerActionDrainBuff/,/retirePostNgePlayerActionDrainState/p')"
printf '%s' "$buff_action_drain_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_action_drain_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerActionDrainEffect'
buff_action_drain_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerActionDrainState/,/isRetiredPostNgePlayerActionBurnEffect/p')"
printf '%s' "$buff_action_drain_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_action_drain_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_action_drain_cleanup_bytecode" | grep -Fq 'removeBuff'
buff_action_burn_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerActionBurnEffect(java.lang.String)/,/isRetiredPostNgePlayerActionBurnBuff/p')"
printf '%s' "$buff_action_burn_effect_predicate_bytecode" | grep -Fq 'action_burn'
buff_action_burn_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerActionBurnBuff/,/clearPostNgePlayerActionBurnScriptVars/p')"
printf '%s' "$buff_action_burn_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_action_burn_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerActionBurnEffect'
buff_action_burn_script_var_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerActionBurnScriptVars/,/retirePostNgePlayerActionBurnState/p')"
printf '%s' "$buff_action_burn_script_var_cleanup_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_action_burn_script_var_cleanup_bytecode" | grep -Fq 'buff.action_burn'
printf '%s' "$buff_action_burn_script_var_cleanup_bytecode" | grep -Fq 'utils.removeScriptVarTree'
buff_action_burn_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerActionBurnState/,/isRetiredPostNgePlayerActionRegenEffect/p')"
printf '%s' "$buff_action_burn_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_action_burn_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_action_burn_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_action_burn_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerActionBurnScriptVars'
buff_action_regen_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerActionRegenEffect(java.lang.String)/,/isRetiredPostNgePlayerActionRegenBuff/p')"
printf '%s' "$buff_action_regen_effect_predicate_bytecode" | grep -Fq 'action_regen'
buff_action_regen_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerActionRegenBuff/,/retirePostNgePlayerActionRegenState/p')"
printf '%s' "$buff_action_regen_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_action_regen_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerActionRegenEffect'
buff_action_regen_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerActionRegenState/,/isRetiredPostNgePlayerDamageDealtOverrideEffect/p')"
printf '%s' "$buff_action_regen_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_action_regen_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_action_regen_cleanup_bytecode" | grep -Fq 'removeBuff'
buff_progression_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/retirePostNgeMeditationBuffs/p')"
printf '%s' "$buff_progression_cleanup_bytecode" | grep -Fq 'retirePostNgePlayerActionDrainState'
printf '%s' "$buff_progression_cleanup_bytecode" | grep -Fq 'retirePostNgePlayerActionBurnState'
printf '%s' "$buff_progression_cleanup_bytecode" | grep -Fq 'retirePostNgePlayerActionRegenState'
buff_damage_dealt_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerDamageDealtOverrideEffect(java.lang.String)/,/isRetiredPostNgePlayerDamageDealtOverrideBuff/p')"
printf '%s' "$buff_damage_dealt_effect_predicate_bytecode" | grep -Fq 'damage_dealt_mod'
buff_damage_dealt_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerDamageDealtOverrideBuff/,/restorePostNgePlayerDamageDealtOverride/p')"
printf '%s' "$buff_damage_dealt_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_damage_dealt_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerDamageDealtOverrideEffect'
buff_damage_dealt_restore_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/restorePostNgePlayerDamageDealtOverride/,/retirePostNgePlayerDamageDealtOverrideState/p')"
printf '%s' "$buff_damage_dealt_restore_bytecode" | grep -Fq 'damageDealtMod.value'
printf '%s' "$buff_damage_dealt_restore_bytecode" | grep -Fq 'damageDealtMod.scale'
printf '%s' "$buff_damage_dealt_restore_bytecode" | grep -Fq 'utils.removeScriptVarTree'
printf '%s' "$buff_damage_dealt_restore_bytecode" | grep -Fq 'setScale'
buff_damage_dealt_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerDamageDealtOverrideState/,/isRetiredPostNgePlayerWeaponSpeedOverrideEffect/p')"
printf '%s' "$buff_damage_dealt_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_damage_dealt_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_damage_dealt_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_damage_dealt_cleanup_bytecode" | grep -Fq 'restorePostNgePlayerDamageDealtOverride'
buff_weapon_speed_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerWeaponSpeedOverrideEffect(java.lang.String)/,/isRetiredPostNgePlayerWeaponSpeedOverrideBuff/p')"
printf '%s' "$buff_weapon_speed_effect_predicate_bytecode" | grep -Fq 'weapon_speed_mod'
buff_weapon_speed_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerWeaponSpeedOverrideBuff/,/restorePostNgePlayerWeaponSpeedOverride/p')"
printf '%s' "$buff_weapon_speed_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_weapon_speed_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerWeaponSpeedOverrideEffect'
buff_weapon_speed_restore_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/restorePostNgePlayerWeaponSpeedOverride/,/retirePostNgePlayerWeaponSpeedOverrideState/p')"
printf '%s' "$buff_weapon_speed_restore_bytecode" | grep -Fq 'recordedAttackSpeed'
printf '%s' "$buff_weapon_speed_restore_bytecode" | grep -Fq 'utils.isNestedWithin'
printf '%s' "$buff_weapon_speed_restore_bytecode" | grep -Fq 'setWeaponAttackSpeed'
printf '%s' "$buff_weapon_speed_restore_bytecode" | grep -Fq 'weapons.setWeaponData'
printf '%s' "$buff_weapon_speed_restore_bytecode" | grep -Fq 'isCreatureWeapon'
buff_weapon_speed_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerWeaponSpeedOverrideState/,/RETIRED_POST_NGE_PLAYER_CRITICAL_OVERRIDE_EFFECTS/p')"
printf '%s' "$buff_weapon_speed_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_weapon_speed_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_weapon_speed_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_weapon_speed_cleanup_bytecode" | grep -Fq 'restorePostNgePlayerWeaponSpeedOverride'
buff_critical_override_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCriticalOverrideEffect(java.lang.String)/,/isRetiredPostNgePlayerCriticalOverrideBuff/p')"
printf '%s' "$buff_critical_override_effect_predicate_bytecode" | grep -Fq 'RETIRED_POST_NGE_PLAYER_CRITICAL_OVERRIDE_EFFECTS'
buff_critical_override_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCriticalOverrideBuff/,/clearPostNgePlayerCriticalOverrideScriptVars/p')"
printf '%s' "$buff_critical_override_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_critical_override_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerCriticalOverrideEffect'
buff_critical_override_script_var_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerCriticalOverrideScriptVars/,/retirePostNgePlayerCriticalOverrideState/p')"
printf '%s' "$buff_critical_override_script_var_cleanup_bytecode" | grep -Fq 'isPlayer'
for retired_critical_override_script_var in nextCritHit critDoubleDamage critRoot critRemoveBuffNames; do
    printf '%s' "$buff_critical_override_script_var_cleanup_bytecode" | grep -Fq "$retired_critical_override_script_var"
done
buff_critical_override_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerCriticalOverrideState/,/isRetiredPostNgePlayerLuckHitOverrideEffect/p')"
printf '%s' "$buff_critical_override_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_critical_override_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_critical_override_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_critical_override_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerCriticalOverrideScriptVars'
for spy_shifty_symbol in isRetiredPostNgePlayerOnAttackRemoveEffect isRetiredPostNgePlayerOnAttackRemoveBuffName isRetiredPostNgePlayerOnAttackRemoveBuff clearPostNgePlayerOnAttackRemoveState retirePostNgePlayerOnAttackRemoveState on_attack_remove sp_shifty_setup onAttackRemoveBuffList; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "$spy_shifty_symbol"
done
spy_shifty_buff_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerOnAttackRemoveBuff(script.obj_id, script.combat_engine.buff_data)/,/clearPostNgePlayerOnAttackRemoveState/p')"
printf '%s' "$spy_shifty_buff_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$spy_shifty_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerOnAttackRemoveEffect'
spy_shifty_state_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerOnAttackRemoveState/,/isRetiredPostNgePlayerLuckHitOverrideEffect/p')"
printf '%s' "$spy_shifty_state_bytecode" | grep -Fq 'removeScriptVarTree'
printf '%s' "$spy_shifty_state_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$spy_shifty_state_bytecode" | grep -Fq 'clearPostNgePlayerOnAttackRemoveState'
spy_shifty_admission_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/public static boolean canApplyBuff(script.obj_id, script.obj_id, int)/,/public static boolean applyBuff(script.obj_id, java.lang.String)/p')"
spy_shifty_admission_line="$(printf '%s\n' "$spy_shifty_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerOnAttackRemoveBuff' | head -1 | cut -d: -f1)"
spy_shifty_existing_line="$(printf '%s\n' "$spy_shifty_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test "$spy_shifty_admission_line" -lt "$spy_shifty_existing_line"
spy_shifty_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/onAttackRemoveAddBuffHandler/,/supression_handlerAddBuffHandler/p')"
test "$(printf '%s' "$spy_shifty_handler_bytecode" | grep -Fc 'isRetiredPostNgePlayerOnAttackRemoveEffect')" -eq 2
test "$(printf '%s' "$spy_shifty_handler_bytecode" | grep -Fc 'isRetiredPostNgePlayerOnAttackRemoveBuffName')" -eq 2
test "$(printf '%s' "$spy_shifty_handler_bytecode" | grep -Fc 'clearPostNgePlayerOnAttackRemoveState')" -eq 2
printf '%s' "$spy_shifty_handler_bytecode" | grep -Fq 'java/util/Vector'
spy_shifty_combat_cleanup_line="$(printf '%s\n' "$combat_base_actions_bytecode" | grep -Fn 'clearPostNgePlayerOnAttackRemoveState' | head -1 | cut -d: -f1)"
spy_shifty_combat_consumer_line="$(printf '%s\n' "$combat_base_actions_bytecode" | grep -Fn 'onAttackRemoveBuffList' | head -1 | cut -d: -f1)"
test -n "$spy_shifty_combat_cleanup_line"
test -n "$spy_shifty_combat_consumer_line"
test "$spy_shifty_combat_cleanup_line" -lt "$spy_shifty_combat_consumer_line"
buff_luck_hit_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerLuckHitOverrideEffect(java.lang.String)/,/isRetiredPostNgePlayerLuckHitOverrideBuff/p')"
printf '%s' "$buff_luck_hit_effect_predicate_bytecode" | grep -Fq 'RETIRED_POST_NGE_PLAYER_LUCK_HIT_OVERRIDE_EFFECTS'
buff_luck_hit_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerLuckHitOverrideBuff/,/clearPostNgePlayerLuckHitOverrideModifiers/p')"
printf '%s' "$buff_luck_hit_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_luck_hit_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerLuckHitOverrideEffect'
buff_luck_hit_modifier_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerLuckHitOverrideModifiers/,/retirePostNgePlayerLuckHitOverrideState/p')"
printf '%s' "$buff_luck_hit_modifier_cleanup_bytecode" | grep -Fq 'isPlayer'
for retired_luck_hit_modifier in hitByLuck increaseHitByLuck missByLuck; do
    printf '%s' "$buff_luck_hit_modifier_cleanup_bytecode" | grep -Fq "$retired_luck_hit_modifier"
done
printf '%s' "$buff_luck_hit_modifier_cleanup_bytecode" | grep -Fq 'hasSkillModModifier'
printf '%s' "$buff_luck_hit_modifier_cleanup_bytecode" | grep -Fq 'removeAttribOrSkillModModifier'
buff_luck_hit_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerLuckHitOverrideState/,/isRetiredPostNgePlayerForsakeFearChannelEffect/p')"
printf '%s' "$buff_luck_hit_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_luck_hit_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_luck_hit_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_luck_hit_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerLuckHitOverrideModifiers'
buff_forsake_fear_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerForsakeFearChannelEffect(java.lang.String)/,/isRetiredPostNgePlayerForsakeFearChannelBuff/p')"
printf '%s' "$buff_forsake_fear_effect_predicate_bytecode" | grep -Fq 'expertise_channel_action_heal'
buff_forsake_fear_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerForsakeFearChannelBuff/,/clearPostNgePlayerForsakeFearChannelState/p')"
printf '%s' "$buff_forsake_fear_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_forsake_fear_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerForsakeFearChannelEffect'
buff_forsake_fear_state_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerForsakeFearChannelState/,/retirePostNgePlayerForsakeFearChannelState/p')"
printf '%s' "$buff_forsake_fear_state_cleanup_bytecode" | grep -Fq 'isPlayer'
for forsake_fear_state_key in ForsakeFearSUIPID lastForsakeFearPulse totalForsakeFearPulses channelForsakeFearCancelled channelForsakeFearSuccessful; do
    printf '%s' "$buff_forsake_fear_state_cleanup_bytecode" | grep -Fq "$forsake_fear_state_key"
done
printf '%s' "$buff_forsake_fear_state_cleanup_bytecode" | grep -Fq 'countdown_sui.sui_pid'
printf '%s' "$buff_forsake_fear_state_cleanup_bytecode" | grep -Fq 'forceCloseSUIPage'
printf '%s' "$buff_forsake_fear_state_cleanup_bytecode" | grep -Fq 'removeObjVar'
printf '%s' "$buff_forsake_fear_state_cleanup_bytecode" | grep -Fq 'removeScriptVarTree'
printf '%s' "$buff_forsake_fear_state_cleanup_bytecode" | grep -Fq 'detachScript'
buff_forsake_fear_lifecycle_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerForsakeFearChannelState/,/isRetiredPostNgePlayerChannelHealEffect/p')"
printf '%s' "$buff_forsake_fear_lifecycle_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_forsake_fear_lifecycle_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_forsake_fear_lifecycle_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_forsake_fear_lifecycle_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerForsakeFearChannelState'
buff_channel_heal_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerChannelHealEffect(java.lang.String)/,/isRetiredPostNgePlayerChannelHealBuff/p')"
printf '%s' "$buff_channel_heal_effect_predicate_bytecode" | grep -Fq 'channel_heal_health'
buff_channel_heal_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerChannelHealBuff/,/clearPostNgePlayerChannelHealState/p')"
printf '%s' "$buff_channel_heal_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_channel_heal_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerChannelHealEffect'
buff_channel_heal_state_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerChannelHealState/,/retirePostNgePlayerChannelHealState/p')"
printf '%s' "$buff_channel_heal_state_cleanup_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_channel_heal_state_cleanup_bytecode" | grep -Fq 'channelHeal.suiPid'
printf '%s' "$buff_channel_heal_state_cleanup_bytecode" | grep -Fq 'countdown_sui.sui_pid'
printf '%s' "$buff_channel_heal_state_cleanup_bytecode" | grep -Fq 'removeScriptVarTree'
printf '%s' "$buff_channel_heal_state_cleanup_bytecode" | grep -Fq 'forceCloseSUIPage'
printf '%s' "$buff_channel_heal_state_cleanup_bytecode" | grep -Fq 'removeObjVar'
printf '%s' "$buff_channel_heal_state_cleanup_bytecode" | grep -Fq 'detachScript'
buff_channel_heal_lifecycle_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerChannelHealState/,/isRetiredPostNgePlayerRadarInvisibilityEffect/p')"
printf '%s' "$buff_channel_heal_lifecycle_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_channel_heal_lifecycle_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_channel_heal_lifecycle_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_channel_heal_lifecycle_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerChannelHealState'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerChannelHealState'
buff_radar_invisibility_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerRadarInvisibilityEffect(java.lang.String)/,/isRetiredPostNgePlayerRadarInvisibilityBuff/p')"
printf '%s' "$buff_radar_invisibility_effect_predicate_bytecode" | grep -Fq 'radar_invis'
buff_radar_invisibility_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerRadarInvisibilityBuff/,/retirePostNgePlayerRadarInvisibilityState/p')"
printf '%s' "$buff_radar_invisibility_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_radar_invisibility_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerRadarInvisibilityEffect'
buff_radar_invisibility_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerRadarInvisibilityState/,/isRetiredPostNgePlayerCooldownExecutionEffect/p')"
printf '%s' "$buff_radar_invisibility_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_radar_invisibility_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_radar_invisibility_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_radar_invisibility_cleanup_bytecode" | grep -Fq 'setVisibleOnMapAndRadar'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerRadarInvisibilityState'
buff_cooldown_execution_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCooldownExecutionEffect(java.lang.String)/,/isRetiredPostNgePlayerCooldownExecutionBuff/p')"
printf '%s' "$buff_cooldown_execution_effect_predicate_bytecode" | grep -Fq 'cooldown_execute_all'
buff_cooldown_execution_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCooldownExecutionBuff/,/retirePostNgePlayerCooldownExecutionState/p')"
printf '%s' "$buff_cooldown_execution_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_cooldown_execution_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerCooldownExecutionEffect'
buff_cooldown_execution_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerCooldownExecutionState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$buff_cooldown_execution_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_cooldown_execution_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_cooldown_execution_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerCooldownExecutionState'
buff_handler_bytecode="$(javap -classpath "$class_root" -c -p script.systems.buff.buff_handler)"
proc_buff_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/procBuffAddBuffHandler/,/procBuffRemoveBuffHandler/p')"
proc_buff_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/procBuffRemoveBuffHandler/,/reactiveBuffAddBuffHandler/p')"
reactive_buff_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/reactiveBuffAddBuffHandler/,/reactiveBuffRemoveBuffHandler/p')"
reactive_buff_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/reactiveBuffRemoveBuffHandler/,/stanceAddBuffHandler/p')"
for proc_effect_add_bytecode in "$proc_buff_add_bytecode" "$reactive_buff_add_bytecode"; do
    proc_effect_add_predicate_bytecode_line="$(printf '%s\n' "$proc_effect_add_bytecode" | grep -Fn 'script/library/proc.isRetiredPostNgePlayerProcActor' | head -1 | cut -d: -f1)"
    proc_effect_add_cleanup_bytecode_line="$(printf '%s\n' "$proc_effect_add_bytecode" | grep -Fn 'script/library/proc.retirePostNgePlayerProcState' | head -1 | cut -d: -f1)"
    proc_effect_add_return_bytecode_line="$(printf '%s\n' "$proc_effect_add_bytecode" | grep -Fn 'return' | head -1 | cut -d: -f1)"
    proc_effect_add_parse_bytecode_line="$(printf '%s\n' "$proc_effect_add_bytecode" | grep -Fn 'java/lang/String.substring' | head -1 | cut -d: -f1)"
    proc_effect_add_writer_bytecode_line="$(printf '%s\n' "$proc_effect_add_bytecode" | grep -Fn 'script/library/utils.setScriptVar' | head -1 | cut -d: -f1)"
    for proc_effect_add_bytecode_line in "$proc_effect_add_predicate_bytecode_line" "$proc_effect_add_cleanup_bytecode_line" "$proc_effect_add_return_bytecode_line" "$proc_effect_add_parse_bytecode_line" "$proc_effect_add_writer_bytecode_line"; do
        test -n "$proc_effect_add_bytecode_line"
    done
    test "$proc_effect_add_predicate_bytecode_line" -lt "$proc_effect_add_cleanup_bytecode_line"
    test "$proc_effect_add_cleanup_bytecode_line" -lt "$proc_effect_add_return_bytecode_line"
    test "$proc_effect_add_return_bytecode_line" -lt "$proc_effect_add_parse_bytecode_line"
    test "$proc_effect_add_parse_bytecode_line" -lt "$proc_effect_add_writer_bytecode_line"
done
! printf '%s' "$proc_buff_remove_bytecode" | grep -Fq 'retirePostNgePlayerProcState'
printf '%s' "$proc_buff_remove_bytecode" | grep -Fq 'String procBuffEffects'
printf '%s' "$proc_buff_remove_bytecode" | grep -Fq 'script/library/utils.removeScriptVar'
printf '%s' "$proc_buff_remove_bytecode" | grep -Fq 'script/library/proc.buildCurrentProcList'
! printf '%s' "$reactive_buff_remove_bytecode" | grep -Fq 'retirePostNgePlayerProcState'
printf '%s' "$reactive_buff_remove_bytecode" | grep -Fq 'String reacBuffEffects'
printf '%s' "$reactive_buff_remove_bytecode" | grep -Fq 'script/library/utils.removeScriptVar'
printf '%s' "$reactive_buff_remove_bytecode" | grep -Fq 'script/library/proc.buildCurrentReacList'
damage_reduction_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/expertiseDamageDecreaseAddBuffHandler/,/expertiseDamageDecreaseRemoveBuffHandler/p')"
damage_reduction_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/expertiseDamageDecreaseRemoveBuffHandler/,/onAttackRemoveAddBuffHandler/p')"
damage_reduction_add_guard_bytecode_line="$(printf '%s\n' "$damage_reduction_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
damage_reduction_add_cleanup_bytecode_line="$(printf '%s\n' "$damage_reduction_add_bytecode" | grep -Fn 'retirePostNgePlayerDamageReductionState' | head -1 | cut -d: -f1)"
damage_reduction_add_return_bytecode_line="$(printf '%s\n' "$damage_reduction_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
damage_reduction_add_read_bytecode_line="$(printf '%s\n' "$damage_reduction_add_bytecode" | grep -Fn 'Method getSkillStatisticModifier' | head -1 | cut -d: -f1)"
damage_reduction_remove_guard_bytecode_line="$(printf '%s\n' "$damage_reduction_remove_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
damage_reduction_remove_cleanup_bytecode_line="$(printf '%s\n' "$damage_reduction_remove_bytecode" | grep -Fn 'clearPostNgePlayerDamageReductionState' | head -1 | cut -d: -f1)"
damage_reduction_remove_return_bytecode_line="$(printf '%s\n' "$damage_reduction_remove_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
damage_reduction_remove_truncation_bytecode_line="$(printf '%s\n' "$damage_reduction_remove_bytecode" | grep -Fn 'java/lang/String.lastIndexOf' | head -1 | cut -d: -f1)"
damage_reduction_remove_read_bytecode_line="$(printf '%s\n' "$damage_reduction_remove_bytecode" | grep -Fn 'Method getSkillStatisticModifier' | head -1 | cut -d: -f1)"
for damage_reduction_bytecode_line in "$damage_reduction_add_guard_bytecode_line" "$damage_reduction_add_cleanup_bytecode_line" "$damage_reduction_add_return_bytecode_line" "$damage_reduction_add_read_bytecode_line" "$damage_reduction_remove_guard_bytecode_line" "$damage_reduction_remove_cleanup_bytecode_line" "$damage_reduction_remove_return_bytecode_line" "$damage_reduction_remove_truncation_bytecode_line" "$damage_reduction_remove_read_bytecode_line"; do
    test -n "$damage_reduction_bytecode_line"
done
test "$damage_reduction_add_guard_bytecode_line" -lt "$damage_reduction_add_cleanup_bytecode_line"
test "$damage_reduction_add_cleanup_bytecode_line" -lt "$damage_reduction_add_return_bytecode_line"
test "$damage_reduction_add_return_bytecode_line" -lt "$damage_reduction_add_read_bytecode_line"
test "$damage_reduction_remove_guard_bytecode_line" -lt "$damage_reduction_remove_cleanup_bytecode_line"
test "$damage_reduction_remove_cleanup_bytecode_line" -lt "$damage_reduction_remove_return_bytecode_line"
test "$damage_reduction_remove_return_bytecode_line" -lt "$damage_reduction_remove_truncation_bytecode_line"
test "$damage_reduction_remove_truncation_bytecode_line" -lt "$damage_reduction_remove_read_bytecode_line"
channel_heal_damage_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/OnCreatureDamaged/,/attribAddBuffHandler/p')"
channel_heal_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/channelHealAddBuffHandler/,/channelHealRemoveBuffHandler/p')"
channel_heal_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/channelHealRemoveBuffHandler/,/getAttributeType/p')"
for channel_heal_handler_spec in damage:retirePostNgePlayerChannelHealState:hasBuff add:retirePostNgePlayerChannelHealState:useChannelHealItem remove:clearPostNgePlayerChannelHealState:getIntScriptVar; do
    channel_heal_handler_name="${channel_heal_handler_spec%%:*}"
    channel_heal_handler_fields="${channel_heal_handler_spec#*:}"
    channel_heal_handler_cleanup="${channel_heal_handler_fields%%:*}"
    channel_heal_handler_writer="${channel_heal_handler_fields##*:}"
    case "$channel_heal_handler_name" in
        damage) channel_heal_handler_bytecode="$channel_heal_damage_bytecode" ;;
        add) channel_heal_handler_bytecode="$channel_heal_add_bytecode" ;;
        remove) channel_heal_handler_bytecode="$channel_heal_remove_bytecode" ;;
        *) exit 1 ;;
    esac
    channel_heal_handler_guard_bytecode_line="$(printf '%s\n' "$channel_heal_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
    channel_heal_handler_cleanup_bytecode_line="$(printf '%s\n' "$channel_heal_handler_bytecode" | grep -Fn "$channel_heal_handler_cleanup" | head -1 | cut -d: -f1)"
    channel_heal_handler_writer_bytecode_line="$(printf '%s\n' "$channel_heal_handler_bytecode" | grep -Fn "$channel_heal_handler_writer" | head -1 | cut -d: -f1)"
    test "$channel_heal_handler_guard_bytecode_line" -lt "$channel_heal_handler_cleanup_bytecode_line"
    test "$channel_heal_handler_cleanup_bytecode_line" -lt "$channel_heal_handler_writer_bytecode_line"
    printf '%s\n' "$channel_heal_handler_bytecode" | head -n "$channel_heal_handler_writer_bytecode_line" | tail -n "+$channel_heal_handler_cleanup_bytecode_line" | grep -Eq '[[:space:]](i)?return$'
done
radar_invisibility_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/radarInvisAddBuffHandler/,/radarInvisRemoveBuffHandler/p')"
radar_invisibility_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/radarInvisRemoveBuffHandler/,/onTargetAddBuffHandler/p')"
for radar_invisibility_handler_bytecode in "$radar_invisibility_add_bytecode" "$radar_invisibility_remove_bytecode"; do
    radar_invisibility_guard_bytecode_line="$(printf '%s\n' "$radar_invisibility_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
    radar_invisibility_first_visibility_bytecode_line="$(printf '%s\n' "$radar_invisibility_handler_bytecode" | grep -Fn 'Method setVisibleOnMapAndRadar' | head -1 | cut -d: -f1)"
    radar_invisibility_player_return_bytecode_line="$(printf '%s\n' "$radar_invisibility_handler_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
    radar_invisibility_retained_visibility_bytecode_line="$(printf '%s\n' "$radar_invisibility_handler_bytecode" | grep -Fn 'Method setVisibleOnMapAndRadar' | tail -1 | cut -d: -f1)"
    test "$(printf '%s\n' "$radar_invisibility_handler_bytecode" | grep -Fc 'Method setVisibleOnMapAndRadar')" -eq 2
    test "$radar_invisibility_guard_bytecode_line" -lt "$radar_invisibility_first_visibility_bytecode_line"
    test "$radar_invisibility_first_visibility_bytecode_line" -lt "$radar_invisibility_player_return_bytecode_line"
    test "$radar_invisibility_player_return_bytecode_line" -lt "$radar_invisibility_retained_visibility_bytecode_line"
done
cooldown_execution_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/cooldownModifyAddBuffHandler/,/cooldownModifyRemoveBuffHandler/p')"
cooldown_execution_guard_bytecode_line="$(printf '%s\n' "$cooldown_execution_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
cooldown_execution_player_return_bytecode_line="$(printf '%s\n' "$cooldown_execution_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
cooldown_execution_retained_writer_bytecode_line="$(printf '%s\n' "$cooldown_execution_add_bytecode" | grep -Fn 'Method getCommandListingForPlayer' | head -1 | cut -d: -f1)"
test "$cooldown_execution_guard_bytecode_line" -lt "$cooldown_execution_player_return_bytecode_line"
test "$cooldown_execution_player_return_bytecode_line" -lt "$cooldown_execution_retained_writer_bytecode_line"
buff_saber_intercept_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerSaberInterceptEffect(java.lang.String)/,/isRetiredPostNgePlayerSaberInterceptBuff/p')"
printf '%s' "$buff_saber_intercept_effect_predicate_bytecode" | grep -Fq 'saber_intercept'
buff_saber_intercept_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerSaberInterceptBuff/,/retirePostNgePlayerSaberInterceptState/p')"
printf '%s' "$buff_saber_intercept_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_saber_intercept_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerSaberInterceptEffect'
buff_saber_intercept_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerSaberInterceptState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$buff_saber_intercept_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_saber_intercept_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_saber_intercept_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerSaberInterceptState'
saber_intercept_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/saberInterceptAddBuffHandler/,/saberInterceptRemoveBuffHandler/p')"
saber_intercept_guard_bytecode_line="$(printf '%s\n' "$saber_intercept_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
saber_intercept_predicate_bytecode_line="$(printf '%s\n' "$saber_intercept_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerSaberInterceptEffect' | head -1 | cut -d: -f1)"
saber_intercept_player_return_bytecode_line="$(printf '%s\n' "$saber_intercept_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
saber_intercept_retained_writer_bytecode_line="$(printf '%s\n' "$saber_intercept_add_bytecode" | grep -Fn 'Method script/library/utils.setScriptVar' | head -1 | cut -d: -f1)"
test "$saber_intercept_guard_bytecode_line" -lt "$saber_intercept_predicate_bytecode_line"
test "$saber_intercept_predicate_bytecode_line" -lt "$saber_intercept_player_return_bytecode_line"
test "$saber_intercept_player_return_bytecode_line" -lt "$saber_intercept_retained_writer_bytecode_line"
buff_pistol_whip_control_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerPistolWhipControlEffect(java.lang.String)/,/isRetiredPostNgePlayerPistolWhipControlBuff/p')"
printf '%s' "$buff_pistol_whip_control_effect_predicate_bytecode" | grep -Fq 'sm_pistol_whip'
buff_pistol_whip_control_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerPistolWhipControlBuff/,/retirePostNgePlayerPistolWhipControlState/p')"
printf '%s' "$buff_pistol_whip_control_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_pistol_whip_control_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerPistolWhipControlEffect'
buff_pistol_whip_control_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerPistolWhipControlState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$buff_pistol_whip_control_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_pistol_whip_control_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_pistol_whip_control_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerPistolWhipControlState'
pistol_whip_control_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/pistolWhipAddBuffHandler/,/pistolWhipRemoveBuffHandler/p')"
pistol_whip_control_guard_bytecode_line="$(printf '%s\n' "$pistol_whip_control_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
pistol_whip_control_predicate_bytecode_line="$(printf '%s\n' "$pistol_whip_control_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerPistolWhipControlEffect' | head -1 | cut -d: -f1)"
pistol_whip_control_player_return_bytecode_line="$(printf '%s\n' "$pistol_whip_control_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
pistol_whip_control_expertise_bytecode_line="$(printf '%s\n' "$pistol_whip_control_add_bytecode" | grep -Fn 'Method getSkillStatisticModifier' | head -1 | cut -d: -f1)"
pistol_whip_control_retained_writer_bytecode_line="$(printf '%s\n' "$pistol_whip_control_add_bytecode" | grep -Fn 'Method movementAddBuffHandler' | head -1 | cut -d: -f1)"
test "$pistol_whip_control_guard_bytecode_line" -lt "$pistol_whip_control_predicate_bytecode_line"
test "$pistol_whip_control_predicate_bytecode_line" -lt "$pistol_whip_control_player_return_bytecode_line"
test "$pistol_whip_control_player_return_bytecode_line" -lt "$pistol_whip_control_expertise_bytecode_line"
test "$pistol_whip_control_expertise_bytecode_line" -lt "$pistol_whip_control_retained_writer_bytecode_line"
buff_smuggler_trick_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerSmugglerTrickEffect(java.lang.String)/,/isRetiredPostNgePlayerSmugglerTrickBuff/p')"
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'expertise_sly_lie'
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'expertise_fast_talk'
printf '%s' "$buff_smuggler_trick_effect_predicate_bytecode" | grep -Fq 'RETIRED_POST_NGE_PLAYER_SMUGGLER_TRICK_EFFECTS'
buff_smuggler_trick_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerSmugglerTrickBuff/,/clearPostNgePlayerSmugglerTrickModifiers/p')"
printf '%s' "$buff_smuggler_trick_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_smuggler_trick_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerSmugglerTrickEffect'
buff_smuggler_trick_modifier_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerSmugglerTrickModifiers/,/retirePostNgePlayerSmugglerTrickState/p')"
for smuggler_trick_modifier in slyLieDodge innocentCargoStrikethrough fastTalkAgility; do
    printf '%s' "$buff_smuggler_trick_modifier_cleanup_bytecode" | grep -Fq "$smuggler_trick_modifier"
done
printf '%s' "$buff_smuggler_trick_modifier_cleanup_bytecode" | grep -Fq 'removeAttribOrSkillModModifier'
buff_smuggler_trick_state_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerSmugglerTrickState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$buff_smuggler_trick_state_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_smuggler_trick_state_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_smuggler_trick_state_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_smuggler_trick_state_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerSmugglerTrickModifiers'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerSmugglerTrickState'
for smuggler_trick_handler in slyLie fastTalk; do
    smuggler_trick_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n "/${smuggler_trick_handler}AddBuffHandler/,/${smuggler_trick_handler}RemoveBuffHandler/p")"
    smuggler_trick_guard_bytecode_line="$(printf '%s\n' "$smuggler_trick_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
    smuggler_trick_predicate_bytecode_line="$(printf '%s\n' "$smuggler_trick_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerSmugglerTrickEffect' | head -1 | cut -d: -f1)"
    smuggler_trick_cleanup_bytecode_line="$(printf '%s\n' "$smuggler_trick_add_bytecode" | grep -Fn 'clearPostNgePlayerSmugglerTrickModifiers' | head -1 | cut -d: -f1)"
    smuggler_trick_player_return_bytecode_line="$(printf '%s\n' "$smuggler_trick_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
    smuggler_trick_expertise_bytecode_line="$(printf '%s\n' "$smuggler_trick_add_bytecode" | grep -Fn 'Method getSkillStatisticModifier' | head -1 | cut -d: -f1)"
    smuggler_trick_writer_bytecode_line="$(printf '%s\n' "$smuggler_trick_add_bytecode" | grep -Fn 'Method skillAddBuffHandler' | head -1 | cut -d: -f1)"
    test "$smuggler_trick_guard_bytecode_line" -lt "$smuggler_trick_predicate_bytecode_line"
    test "$smuggler_trick_predicate_bytecode_line" -lt "$smuggler_trick_cleanup_bytecode_line"
    test "$smuggler_trick_cleanup_bytecode_line" -lt "$smuggler_trick_player_return_bytecode_line"
    test "$smuggler_trick_player_return_bytecode_line" -lt "$smuggler_trick_expertise_bytecode_line"
    test "$smuggler_trick_expertise_bytecode_line" -lt "$smuggler_trick_writer_bytecode_line"
done
action_drain_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/actionDrainAddBuffHandler/,/actionDrainRemoveBuffHandler/p')"
action_drain_cleanup_bytecode_line="$(printf '%s\n' "$action_drain_add_bytecode" | grep -Fn 'retirePostNgePlayerActionDrainState' | head -1 | cut -d: -f1)"
action_drain_guard_bytecode_line="$(printf '%s\n' "$action_drain_add_bytecode" | head -n "$action_drain_cleanup_bytecode_line" | grep -Fn 'Method isPlayer' | tail -1 | cut -d: -f1)"
action_drain_cap_bytecode_line="$(printf '%s\n' "$action_drain_add_bytecode" | grep -Fn 'Method getAction' | head -1 | cut -d: -f1)"
action_drain_write_bytecode_line="$(printf '%s\n' "$action_drain_add_bytecode" | grep -Fn 'Method drainAttributes' | head -1 | cut -d: -f1)"
action_drain_immunity_check_bytecode_line="$(printf '%s\n' "$action_drain_add_bytecode" | grep -Fn 'Method script/library/buff.hasBuff' | head -1 | cut -d: -f1)"
action_drain_immunity_apply_bytecode_line="$(printf '%s\n' "$action_drain_add_bytecode" | grep -Fn 'Method script/library/buff.applyBuff' | head -1 | cut -d: -f1)"
test "$action_drain_guard_bytecode_line" -lt "$action_drain_cleanup_bytecode_line"
test "$action_drain_cleanup_bytecode_line" -lt "$action_drain_cap_bytecode_line"
test "$action_drain_cap_bytecode_line" -lt "$action_drain_write_bytecode_line"
test "$action_drain_write_bytecode_line" -lt "$action_drain_immunity_check_bytecode_line"
test "$action_drain_immunity_check_bytecode_line" -lt "$action_drain_immunity_apply_bytecode_line"
action_burn_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/actionBurnAddBuffHandler/,/actionBurnRemoveBuffHandler/p')"
action_burn_add_cleanup_bytecode_line="$(printf '%s\n' "$action_burn_add_bytecode" | grep -Fn 'retirePostNgePlayerActionBurnState' | head -1 | cut -d: -f1)"
action_burn_add_guard_bytecode_line="$(printf '%s\n' "$action_burn_add_bytecode" | head -n "$action_burn_add_cleanup_bytecode_line" | grep -Fn 'Method isPlayer' | tail -1 | cut -d: -f1)"
action_burn_add_write_bytecode_line="$(printf '%s\n' "$action_burn_add_bytecode" | grep -Fn 'String buff.action_burn.value' | head -1 | cut -d: -f1)"
test "$action_burn_add_guard_bytecode_line" -lt "$action_burn_add_cleanup_bytecode_line"
test "$action_burn_add_cleanup_bytecode_line" -lt "$action_burn_add_write_bytecode_line"
action_burn_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/actionBurnRemoveBuffHandler/,/actionRegenAddBuffHandler/p')"
action_burn_remove_cleanup_bytecode_line="$(printf '%s\n' "$action_burn_remove_bytecode" | grep -Fn 'clearPostNgePlayerActionBurnScriptVars' | head -1 | cut -d: -f1)"
action_burn_remove_guard_bytecode_line="$(printf '%s\n' "$action_burn_remove_bytecode" | head -n "$action_burn_remove_cleanup_bytecode_line" | grep -Fn 'Method isPlayer' | tail -1 | cut -d: -f1)"
action_burn_remove_write_bytecode_line="$(printf '%s\n' "$action_burn_remove_bytecode" | grep -Fn 'String buff.action_burn.value' | head -1 | cut -d: -f1)"
test "$action_burn_remove_guard_bytecode_line" -lt "$action_burn_remove_cleanup_bytecode_line"
test "$action_burn_remove_cleanup_bytecode_line" -lt "$action_burn_remove_write_bytecode_line"
combat_library_bytecode="$(javap -classpath "$class_root" -c -p script.library.combat)"
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'bm_shield_master_pet'
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'bm_shield_master_player'
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'bodyguard'
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'protect_master'
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'shield_master_pet'
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'shield_master_player'
buff_damage_redirect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerDamageRedirectBuff(script.obj_id, script.combat_engine[$]buff_data)/,/clearPostNgePlayerDamageRedirectState/p')"
printf '%s' "$buff_damage_redirect_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$buff_damage_redirect_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerDamageRedirectBuffName'
printf '%s' "$buff_damage_redirect_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerDamageRedirectEffect'
buff_damage_redirect_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerDamageRedirectState/,/isRetiredPostNgePlayerPistolWhipControlEffect/p')"
printf '%s' "$buff_damage_redirect_cleanup_bytecode" | grep -Fq 'String damage_redirect'
printf '%s' "$buff_damage_redirect_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_damage_redirect_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_damage_redirect_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerDamageRedirectState'
for damage_redirect_handler in bodyguardDefenderAdd bodyguardDefenderRemove bodyguardMasterAdd bodyguardMasterRemove; do
    damage_redirect_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n "/${damage_redirect_handler}BuffHandler/,/ireturn/p")"
    printf '%s' "$damage_redirect_handler_bytecode" | grep -Fq 'Method isPlayer'
    printf '%s' "$damage_redirect_handler_bytecode" | grep -Fq 'isRetiredPostNgePlayerDamageRedirectEffect'
    printf '%s' "$damage_redirect_handler_bytecode" | grep -Fq 'isRetiredPostNgePlayerDamageRedirectBuffName'
    printf '%s' "$damage_redirect_handler_bytecode" | grep -Fq 'ireturn'
done
bodyguard_defender_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/bodyguardDefenderAddBuffHandler/,/cooldownModifyAddBuffHandler/p')"
test "$(printf '%s' "$bodyguard_defender_bytecode" | grep -Fc 'Method isPlayer')" -ge 6
bodyguard_defender_player_return_bytecode_line="$(printf '%s\n' "$bodyguard_defender_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
bodyguard_defender_retained_writer_bytecode_line="$(printf '%s\n' "$bodyguard_defender_bytecode" | grep -Fn 'Method script/library/utils.setScriptVar' | head -1 | cut -d: -f1)"
test "$bodyguard_defender_player_return_bytecode_line" -lt "$bodyguard_defender_retained_writer_bytecode_line"
damage_redirect_consumer_bytecode="$(printf '%s' "$combat_library_bytecode" | sed -n '/directDamageToDifferentTarget(script.obj_id, script.obj_id)/,/getMissChance/p')"
damage_redirect_consumer_guard_bytecode_line="$(printf '%s\n' "$damage_redirect_consumer_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
damage_redirect_consumer_cleanup_bytecode_line="$(printf '%s\n' "$damage_redirect_consumer_bytecode" | grep -Fn 'retirePostNgePlayerDamageRedirectState' | head -1 | cut -d: -f1)"
damage_redirect_consumer_return_bytecode_line="$(printf '%s\n' "$damage_redirect_consumer_bytecode" | grep -Fn 'areturn' | head -1 | cut -d: -f1)"
damage_redirect_consumer_beast_bytecode_line="$(printf '%s\n' "$damage_redirect_consumer_bytecode" | grep -Fn 'String bm_shield_master_player' | head -1 | cut -d: -f1)"
damage_redirect_consumer_script_var_bytecode_line="$(printf '%s\n' "$damage_redirect_consumer_bytecode" | grep -Fn 'String damage_redirect' | head -1 | cut -d: -f1)"
test "$damage_redirect_consumer_guard_bytecode_line" -lt "$damage_redirect_consumer_cleanup_bytecode_line"
test "$damage_redirect_consumer_cleanup_bytecode_line" -lt "$damage_redirect_consumer_return_bytecode_line"
test "$damage_redirect_consumer_return_bytecode_line" -lt "$damage_redirect_consumer_beast_bytecode_line"
test "$damage_redirect_consumer_beast_bytecode_line" -lt "$damage_redirect_consumer_script_var_bytecode_line"
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'aggro_channel_self'
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'aggro_channel_target'
buff_aggro_channel_effect_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerAggroChannelEffect(java.lang.String)/,/isRetiredPostNgePlayerAggroChannelBuff/p')"
printf '%s' "$buff_aggro_channel_effect_predicate_bytecode" | grep -Fq 'RETIRED_POST_NGE_PLAYER_AGGRO_CHANNEL_EFFECTS'
buff_aggro_channel_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerAggroChannelBuff/,/retirePostNgePlayerAggroChannelState/p')"
printf '%s' "$buff_aggro_channel_predicate_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$buff_aggro_channel_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerAggroChannelEffect'
buff_aggro_channel_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerAggroChannelState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$buff_aggro_channel_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_aggro_channel_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_aggro_channel_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$buff_aggro_channel_cleanup_bytecode" | grep -Fq 'aggroBuffTransfer'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerAggroChannelState'
aggro_channel_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/aggroChannelAddBuffHandler/,/aggroChannelRemoveBuffHandler/p')"
aggro_channel_guard_bytecode_line="$(printf '%s\n' "$aggro_channel_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
aggro_channel_predicate_bytecode_line="$(printf '%s\n' "$aggro_channel_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerAggroChannelEffect' | head -1 | cut -d: -f1)"
aggro_channel_cleanup_bytecode_line="$(printf '%s\n' "$aggro_channel_add_bytecode" | grep -Fn 'retirePostNgePlayerAggroChannelState' | head -1 | cut -d: -f1)"
aggro_channel_player_return_bytecode_line="$(printf '%s\n' "$aggro_channel_add_bytecode" | grep -Fn 'ireturn' | head -1 | cut -d: -f1)"
aggro_channel_caster_check_bytecode_line="$(printf '%s\n' "$aggro_channel_add_bytecode" | grep -Fn 'Method exists' | head -1 | cut -d: -f1)"
aggro_channel_apply_bytecode_line="$(printf '%s\n' "$aggro_channel_add_bytecode" | grep -Fn 'Method script/library/buff.applyBuff' | head -1 | cut -d: -f1)"
aggro_channel_script_var_bytecode_line="$(printf '%s\n' "$aggro_channel_add_bytecode" | grep -Fn 'Method script/library/utils.setScriptVar' | head -1 | cut -d: -f1)"
test "$aggro_channel_guard_bytecode_line" -lt "$aggro_channel_predicate_bytecode_line"
test "$aggro_channel_predicate_bytecode_line" -lt "$aggro_channel_cleanup_bytecode_line"
test "$aggro_channel_cleanup_bytecode_line" -lt "$aggro_channel_player_return_bytecode_line"
test "$aggro_channel_player_return_bytecode_line" -lt "$aggro_channel_caster_check_bytecode_line"
test "$aggro_channel_caster_check_bytecode_line" -lt "$aggro_channel_apply_bytecode_line"
test "$aggro_channel_apply_bytecode_line" -lt "$aggro_channel_script_var_bytecode_line"
aggro_channel_consumer_bytecode="$(printf '%s' "$combat_library_bytecode" | sed -n '/addHateProcess(script.obj_id, script.obj_id, script.combat_engine[$]hit_result, script.combat_engine[$]combat_data)/,/canSee(script.obj_id, script.obj_id)/p')"
aggro_channel_consumer_cleanup_bytecode_line="$(printf '%s\n' "$aggro_channel_consumer_bytecode" | grep -Fn 'retirePostNgePlayerAggroChannelState' | head -1 | cut -d: -f1)"
aggro_channel_consumer_expertise_bytecode_line="$(printf '%s\n' "$aggro_channel_consumer_bytecode" | grep -Fn 'expertise_aggro_channel' | head -1 | cut -d: -f1)"
aggro_channel_consumer_transfer_bytecode_line="$(printf '%s\n' "$aggro_channel_consumer_bytecode" | grep -Fn 'Method addHate' | awk -F: -v expertise="$aggro_channel_consumer_expertise_bytecode_line" '$1 > expertise { print $1; exit }')"
printf '%s' "$aggro_channel_consumer_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$aggro_channel_consumer_bytecode" | grep -Fq 'aggroBuffTransfer'
test "$aggro_channel_consumer_cleanup_bytecode_line" -lt "$aggro_channel_consumer_expertise_bytecode_line"
test "$aggro_channel_consumer_expertise_bytecode_line" -lt "$aggro_channel_consumer_transfer_bytecode_line"
commando_player_action_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base | sed -n '/isRetiredPostNgeCommandoPlayerAction/,/isRetiredPostNgeMedicPlayerAction/p')"
printf '%s' "$commando_player_action_bytecode" | grep -Fq 'String co_'
printf '%s' "$commando_player_action_bytecode" | grep -Fq 'String kill_meter_co_'
printf '%s' "$commando_player_action_bytecode" | grep -Fq 'String expertise_co_'
printf '%s' "$commando_player_action_bytecode" | grep -Fq 'String banner_buff_commando'
medic_player_action_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base | sed -n '/isRetiredPostNgeMedicPlayerAction/,/isRetiredPostNgeEntertainerPlayerAction/p')"
printf '%s' "$medic_player_action_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$medic_player_action_bytecode" | grep -Fq 'String me_'
printf '%s' "$medic_player_action_bytecode" | grep -Fq 'String expertise_dueterium_rounds_proc'
printf '%s' "$medic_player_action_bytecode" | grep -Fq 'String expertise_poison_knuckle_proc'
for medic_deferred_dot_proc_action in expertise_dueterium_rounds_proc expertise_poison_knuckle_proc; do
    medic_deferred_dot_proc_handler_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | sed -n "/public int $medic_deferred_dot_proc_action(/,/ireturn/p")"
    printf '%s' "$medic_deferred_dot_proc_handler_bytecode" | grep -Fq "String $medic_deferred_dot_proc_action"
    printf '%s' "$medic_deferred_dot_proc_handler_bytecode" | grep -Fq 'Method combatStandardAction'
done
entertainer_player_action_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base | sed -n '/isRetiredPostNgeEntertainerPlayerAction/,/isRetiredPostNgePvpRewardPlayerAction/p')"
printf '%s' "$entertainer_player_action_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$entertainer_player_action_bytecode" | grep -Fq 'String en_'
printf '%s' "$entertainer_player_action_bytecode" | grep -Fq 'String expertise_buildabuff_'
for entertainer_buildabuff_reactive_heal_action in expertise_buildabuff_heal_1_reac expertise_buildabuff_heal_2_reac expertise_buildabuff_heal_3_reac; do
    entertainer_buildabuff_reactive_heal_handler_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | sed -n "/public int $entertainer_buildabuff_reactive_heal_action(/,/ireturn/p")"
    printf '%s' "$entertainer_buildabuff_reactive_heal_handler_bytecode" | grep -Fq "String $entertainer_buildabuff_reactive_heal_action"
    printf '%s' "$entertainer_buildabuff_reactive_heal_handler_bytecode" | grep -Fq 'Method combatStandardAction'
done
buildabuff_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/buildabuffAddBuffHandler/,/buildabuffRemoveBuffHandler/p')"
buildabuff_add_guard_bytecode_line="$(printf '%s\n' "$buildabuff_add_bytecode" | grep -Fn 'isPostNgeBuffProgressionRetired' | head -1 | cut -d: -f1)"
buildabuff_add_cleanup_bytecode_line="$(printf '%s\n' "$buildabuff_add_bytecode" | grep -Fn 'buildabuffRemoveBuffHandler' | head -1 | cut -d: -f1)"
test -n "$buildabuff_add_guard_bytecode_line"
test -n "$buildabuff_add_cleanup_bytecode_line"
test "$buildabuff_add_guard_bytecode_line" -lt "$buildabuff_add_cleanup_bytecode_line"
buildabuff_class_constants="$(javap -classpath "$class_root" -verbose -p script.systems.buff.buff_handler)"
printf '%s' "$buildabuff_class_constants" | grep -Fq 'performance.buildabuff.buffComponentKeys'
buildabuff_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/buildabuffRemoveBuffHandler/,/meDoomAddBuffHandler/p')"
for entertainer_buildabuff_reactive_heal_action in expertise_buildabuff_heal_1_reac expertise_buildabuff_heal_2_reac expertise_buildabuff_heal_3_reac; do
    printf '%s' "$buildabuff_class_constants" | grep -Fq "$entertainer_buildabuff_reactive_heal_action"
    printf '%s' "$buildabuff_remove_bytecode" | grep -Fq "String $entertainer_buildabuff_reactive_heal_action"
done
medic_doom_proc_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | sed -n '/public void doDoom(/,/public int of_buff_def_1/p')"
medic_doom_proc_is_player_lines="$(printf '%s\n' "$medic_doom_proc_bytecode" | grep -Fn 'Method isPlayer' | cut -d: -f1)"
medic_doom_proc_attacker_guard_bytecode_line="$(printf '%s\n' "$medic_doom_proc_is_player_lines" | sed -n '1p')"
medic_doom_proc_defender_guard_bytecode_line="$(printf '%s\n' "$medic_doom_proc_is_player_lines" | sed -n '2p')"
medic_doom_proc_chance_bytecode_line="$(printf '%s\n' "$medic_doom_proc_bytecode" | grep -Fn 'String me_doom_chance' | head -1 | cut -d: -f1)"
medic_doom_proc_state_bytecode_line="$(printf '%s\n' "$medic_doom_proc_bytecode" | grep -Fn 'String me_doom.doom_owner' | head -1 | cut -d: -f1)"
test -n "$medic_doom_proc_attacker_guard_bytecode_line"
test -n "$medic_doom_proc_defender_guard_bytecode_line"
test -n "$medic_doom_proc_chance_bytecode_line"
test -n "$medic_doom_proc_state_bytecode_line"
test "$medic_doom_proc_attacker_guard_bytecode_line" -lt "$medic_doom_proc_defender_guard_bytecode_line"
test "$medic_doom_proc_defender_guard_bytecode_line" -lt "$medic_doom_proc_chance_bytecode_line"
test "$medic_doom_proc_chance_bytecode_line" -lt "$medic_doom_proc_state_bytecode_line"
test "$(printf '%s\n' "$medic_doom_proc_bytecode" | grep -Fc 'retirePostNgePlayerMedicDoomState')" -eq 2
medic_doom_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerMedicDoomBuff/,/clearPostNgePlayerMedicDoomState/p')"
printf '%s' "$medic_doom_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$medic_doom_predicate_bytecode" | grep -Fq 'String me_doom'
medic_doom_clear_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerMedicDoomState/,/retirePostNgePlayerMedicDoomState/p')"
printf '%s' "$medic_doom_clear_bytecode" | grep -Fq 'Method script/library/utils.removeScriptVarTree'
printf '%s' "$medic_doom_clear_bytecode" | grep -Fq 'Method hasSkillModModifier'
printf '%s' "$medic_doom_clear_bytecode" | grep -Fq 'Method removeAttribOrSkillModModifier'
printf '%s' "$medic_doom_clear_bytecode" | grep -Fq 'String me_doom_chance'
medic_doom_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerMedicDoomState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$medic_doom_cleanup_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$medic_doom_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerMedicDoomState'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerMedicDoomState'
printf '%s' "$buff_modifier_bytecode" | sed -n '/canApplyBuff(script.obj_id, script.obj_id, int)/,/getGroups/p' | grep -Fq 'isRetiredPostNgePlayerMedicDoomBuff'
medic_doom_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/meDoomAddBuffHandler/,/meDoomRemoveBuffHandler/p')"
medic_doom_add_guard_bytecode_line="$(printf '%s\n' "$medic_doom_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
medic_doom_add_state_bytecode_line="$(printf '%s\n' "$medic_doom_add_bytecode" | grep -Fn 'String me_doom.doom_owner' | head -1 | cut -d: -f1)"
test "$medic_doom_add_guard_bytecode_line" -lt "$medic_doom_add_state_bytecode_line"
printf '%s' "$medic_doom_add_bytecode" | grep -Fq 'retirePostNgePlayerMedicDoomState'
test "$(printf '%s' "$medic_doom_add_bytecode" | grep -Fc 'Method script/library/dot.applyDotEffect')" -eq 2
medic_doom_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/meDoomRemoveBuffHandler/,/cacheExpertiseProcReacList/p')"
medic_doom_remove_guard_bytecode_line="$(printf '%s\n' "$medic_doom_remove_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
medic_doom_remove_state_bytecode_line="$(printf '%s\n' "$medic_doom_remove_bytecode" | grep -Fn 'String me_doom.doom_owner' | head -1 | cut -d: -f1)"
test "$medic_doom_remove_guard_bytecode_line" -lt "$medic_doom_remove_state_bytecode_line"
printf '%s' "$medic_doom_remove_bytecode" | grep -Fq 'clearPostNgePlayerMedicDoomState'
test "$(printf '%s' "$medic_doom_remove_bytecode" | grep -Fc 'Method script/library/buff.applyBuff')" -eq 2
elemental_vulnerability_effect_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerElementalVulnerabilityEffect(java.lang.String)/,/isRetiredPostNgePlayerElementalVulnerabilityBuff/p')"
printf '%s' "$elemental_vulnerability_effect_bytecode" | grep -Fq 'String dt_vulnerability_'
printf '%s' "$elemental_vulnerability_effect_bytecode" | grep -Fq 'String.startsWith'
elemental_vulnerability_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerElementalVulnerabilityBuff/,/clearPostNgePlayerElementalVulnerabilityState/p')"
printf '%s' "$elemental_vulnerability_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$elemental_vulnerability_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerElementalVulnerabilityEffect'
elemental_vulnerability_clear_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerElementalVulnerabilityState/,/retirePostNgePlayerElementalVulnerabilityState/p')"
printf '%s' "$elemental_vulnerability_clear_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$elemental_vulnerability_clear_bytecode" | grep -Fq 'Method script/library/utils.removeScriptVarTree'
printf '%s' "$elemental_vulnerability_clear_bytecode" | grep -Fq 'String elemental_vulnerability'
elemental_vulnerability_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerElementalVulnerabilityState/,/isRetiredPostNgePlayerMedicDoomBuff/p')"
printf '%s' "$elemental_vulnerability_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$elemental_vulnerability_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$elemental_vulnerability_cleanup_bytecode" | grep -Fq 'removeBuff'
printf '%s' "$elemental_vulnerability_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerElementalVulnerabilityState'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerElementalVulnerabilityState'
elemental_vulnerability_admission_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/canApplyBuff(script.obj_id, script.obj_id, int)/,/getGroups/p')"
elemental_vulnerability_admission_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerElementalVulnerabilityBuff' | head -1 | cut -d: -f1)"
elemental_vulnerability_existing_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test "$elemental_vulnerability_admission_bytecode_line" -lt "$elemental_vulnerability_existing_bytecode_line"
elemental_vulnerability_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/vulnerabilityAddBuffHandler/,/public void clog/p')"
elemental_vulnerability_add_guard_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
elemental_vulnerability_add_cleanup_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_add_bytecode" | grep -Fn 'retirePostNgePlayerElementalVulnerabilityState' | head -1 | cut -d: -f1)"
elemental_vulnerability_add_writer_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_add_bytecode" | grep -Fn 'Method script/library/utils.setScriptVar' | head -1 | cut -d: -f1)"
test "$elemental_vulnerability_add_guard_bytecode_line" -lt "$elemental_vulnerability_add_cleanup_bytecode_line"
test "$elemental_vulnerability_add_cleanup_bytecode_line" -lt "$elemental_vulnerability_add_writer_bytecode_line"
test "$(printf '%s' "$elemental_vulnerability_add_bytecode" | grep -Fc 'Method script/library/utils.setScriptVar')" -eq 3
elemental_vulnerability_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/vulnerabilityRemoveBuffHandler/,/removeIncapWeakenAddBuffHandler/p')"
elemental_vulnerability_remove_guard_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_remove_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
elemental_vulnerability_remove_cleanup_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_remove_bytecode" | grep -Fn 'clearPostNgePlayerElementalVulnerabilityState' | head -1 | cut -d: -f1)"
elemental_vulnerability_remove_writer_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_remove_bytecode" | grep -Fn 'Method script/library/utils.removeScriptVar' | head -1 | cut -d: -f1)"
test "$elemental_vulnerability_remove_guard_bytecode_line" -lt "$elemental_vulnerability_remove_cleanup_bytecode_line"
test "$elemental_vulnerability_remove_cleanup_bytecode_line" -lt "$elemental_vulnerability_remove_writer_bytecode_line"
test "$(printf '%s' "$elemental_vulnerability_remove_bytecode" | grep -Fc 'Method script/library/utils.removeScriptVar')" -eq 3
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'commando_snare_bonus'
printf '%s' "$buff_modifier_bytecode" | grep -Fq 'commandoInnateArmorBonus'
commando_snare_armor_effect_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCommandoSnareArmorEffect(java.lang.String)/,/isRetiredPostNgePlayerCommandoSnareArmorBuff/p')"
printf '%s' "$commando_snare_armor_effect_bytecode" | grep -Fq 'commando_snare_bonus'
commando_snare_armor_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCommandoSnareArmorBuff/,/clearPostNgePlayerCommandoSnareArmorModifier/p')"
printf '%s' "$commando_snare_armor_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$commando_snare_armor_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerCommandoSnareArmorEffect'
commando_snare_armor_modifier_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerCommandoSnareArmorModifier/,/retirePostNgePlayerCommandoSnareArmorState/p')"
printf '%s' "$commando_snare_armor_modifier_cleanup_bytecode" | grep -Fq 'Method hasSkillModModifier'
printf '%s' "$commando_snare_armor_modifier_cleanup_bytecode" | grep -Fq 'Method removeAttribOrSkillModModifier'
printf '%s' "$commando_snare_armor_modifier_cleanup_bytecode" | grep -Fq 'commandoInnateArmorBonus'
commando_snare_armor_state_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerCommandoSnareArmorState/,/isRetiredPostNgePlayerModifierBuff/p')"
printf '%s' "$commando_snare_armor_state_cleanup_bytecode" | grep -Fq 'Method getAllBuffs'
printf '%s' "$commando_snare_armor_state_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$commando_snare_armor_state_cleanup_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$commando_snare_armor_state_cleanup_bytecode" | grep -Fq 'clearPostNgePlayerCommandoSnareArmorModifier'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerCommandoSnareArmorState'
printf '%s' "$buff_modifier_bytecode" | sed -n '/canApplyBuff(script.obj_id, script.obj_id, int)/,/getGroups/p' | grep -Fq 'isRetiredPostNgePlayerCommandoSnareArmorBuff'
commando_snare_armor_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/commandoSnareBonusAddBuffHandler/,/commandoSnareBonusRemoveBuffHandler/p')"
commando_snare_armor_validity_bytecode_line="$(printf '%s\n' "$commando_snare_armor_add_bytecode" | grep -Fn 'Method isIdValid' | head -1 | cut -d: -f1)"
commando_snare_armor_guard_bytecode_line="$(printf '%s\n' "$commando_snare_armor_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
commando_snare_armor_predicate_bytecode_line="$(printf '%s\n' "$commando_snare_armor_add_bytecode" | grep -Fn 'isRetiredPostNgePlayerCommandoSnareArmorEffect' | head -1 | cut -d: -f1)"
commando_snare_armor_cleanup_bytecode_line="$(printf '%s\n' "$commando_snare_armor_add_bytecode" | grep -Fn 'retirePostNgePlayerCommandoSnareArmorState' | head -1 | cut -d: -f1)"
commando_snare_armor_return_bytecode_line="$(printf '%s\n' "$commando_snare_armor_add_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$commando_snare_armor_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
commando_snare_armor_movement_bytecode_line="$(printf '%s\n' "$commando_snare_armor_add_bytecode" | grep -Fn 'movement.getAllModifiers' | head -1 | cut -d: -f1)"
commando_snare_armor_expertise_bytecode_line="$(printf '%s\n' "$commando_snare_armor_add_bytecode" | grep -Fn 'expertise_youll_regret_that' | head -1 | cut -d: -f1)"
commando_snare_armor_writer_bytecode_line="$(printf '%s\n' "$commando_snare_armor_add_bytecode" | grep -Fn 'Method skillAddBuffHandler' | head -1 | cut -d: -f1)"
test -n "$commando_snare_armor_validity_bytecode_line"
test -n "$commando_snare_armor_guard_bytecode_line"
test -n "$commando_snare_armor_predicate_bytecode_line"
test -n "$commando_snare_armor_cleanup_bytecode_line"
test -n "$commando_snare_armor_return_bytecode_line"
test -n "$commando_snare_armor_movement_bytecode_line"
test -n "$commando_snare_armor_expertise_bytecode_line"
test -n "$commando_snare_armor_writer_bytecode_line"
test "$commando_snare_armor_validity_bytecode_line" -lt "$commando_snare_armor_guard_bytecode_line"
test "$commando_snare_armor_guard_bytecode_line" -lt "$commando_snare_armor_predicate_bytecode_line"
test "$commando_snare_armor_predicate_bytecode_line" -lt "$commando_snare_armor_cleanup_bytecode_line"
test "$commando_snare_armor_cleanup_bytecode_line" -lt "$commando_snare_armor_return_bytecode_line"
test "$commando_snare_armor_return_bytecode_line" -lt "$commando_snare_armor_movement_bytecode_line"
test "$commando_snare_armor_movement_bytecode_line" -lt "$commando_snare_armor_expertise_bytecode_line"
test "$commando_snare_armor_expertise_bytecode_line" -lt "$commando_snare_armor_writer_bytecode_line"
commando_snare_armor_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/commandoSnareBonusRemoveBuffHandler/,/commandoFlashBangAddBuffHandler/p')"
printf '%s' "$commando_snare_armor_remove_bytecode" | grep -Fq 'commandoInnateArmorBonus'
printf '%s' "$commando_snare_armor_remove_bytecode" | grep -Fq 'String recalcArmor'
for commando_specialized_effect in expertise_flash_bang expertise_muscle_spasm expertise_riddle_armor expertise_on_target; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "String $commando_specialized_effect"
done
for commando_specialized_buff in co_flash_bang co_muscle_spasm co_riddle_armor co_armor_cracker grenadier_kinetic co_position_secured co_pos_sec_action_1 co_pos_sec_action_2 co_pos_sec_action_3 co_pos_sec_proc_1 co_pos_sec_proc_2 co_pos_sec_critical_1 co_pos_sec_critical_2 co_pos_sec_critical_3 co_pos_sec_critical_4 co_base_of_operations; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "String $commando_specialized_buff"
done
for commando_specialized_modifier in commandoFlashBang commandoMuscleSpasm precision_modified strength_modified glancing_blow_vulnerable expertise_riddle_armor expertise_innate_protection_all expertise_critical_hit_reduction expertise_critical_niche_all expertise_co_burst_fire_proc expertise_devastation_bonus expertise_action_all expertise_co_flash_bang expertise_co_muscle_spasm expertise_action_line_co_imp_pos_sec expertise_co_pos_secured_line_armor expertise_co_pos_secured_line_boo_critical expertise_co_pos_secured_line_burst_fire_devastation_bonus expertise_co_pos_secured_line_burst_fire_proc expertise_co_pos_secured_line_critical expertise_co_pos_secured_line_protection; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "String $commando_specialized_modifier"
done
commando_specialized_effect_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCommandoSpecializedEffect/,/isRetiredPostNgePlayerCommandoSpecializedBuffName/p')"
printf '%s' "$commando_specialized_effect_bytecode" | grep -Fq 'Method java/lang/String.equals'
printf '%s' "$commando_specialized_effect_bytecode" | grep -Fq 'Method java/lang/String.startsWith'
commando_specialized_buff_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerCommandoSpecializedBuff(script.obj_id, script.combat_engine[$]buff_data)/,/clearPostNgePlayerCommandoSpecializedModifiers/p')"
printf '%s' "$commando_specialized_buff_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$commando_specialized_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerCommandoSpecializedBuffName'
printf '%s' "$commando_specialized_buff_predicate_bytecode" | grep -Fq 'Method getEffectParam'
printf '%s' "$commando_specialized_buff_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerCommandoSpecializedEffect'
commando_specialized_modifier_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerCommandoSpecializedModifiers/,/clearPostNgePlayerCommandoSpecializedBuffs/p')"
printf '%s' "$commando_specialized_modifier_cleanup_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$commando_specialized_modifier_cleanup_bytecode" | grep -Fq 'Method hasSkillModModifier'
printf '%s' "$commando_specialized_modifier_cleanup_bytecode" | grep -Fq 'Method removeAttribOrSkillModModifier'
printf '%s' "$commando_specialized_modifier_cleanup_bytecode" | grep -Fq 'Method getSkillStatMod'
printf '%s' "$commando_specialized_modifier_cleanup_bytecode" | grep -Fq 'Method applySkillStatisticModifier'
printf '%s' "$commando_specialized_modifier_cleanup_bytecode" | grep -Fq 'String recalcArmor'
printf '%s' "$commando_specialized_modifier_cleanup_bytecode" | grep -Fq 'Method script/library/combat.cacheCombatData'
commando_specialized_buff_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerCommandoSpecializedBuffs/,/retirePostNgePlayerCommandoSpecializedState/p')"
printf '%s' "$commando_specialized_buff_cleanup_bytecode" | grep -Fq 'String co_position_secured'
printf '%s' "$commando_specialized_buff_cleanup_bytecode" | grep -Fq 'Method hasBuff'
printf '%s' "$commando_specialized_buff_cleanup_bytecode" | grep -Fq 'Method removeBuff'
commando_specialized_state_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerCommandoSpecializedState/,/isRetiredPostNgePlayerElementalVulnerabilityEffect/p')"
commando_specialized_parent_remove_bytecode_line="$(printf '%s\n' "$commando_specialized_state_cleanup_bytecode" | grep -Fn 'Method removeBuff' | head -1 | cut -d: -f1)"
commando_specialized_child_remove_bytecode_line="$(printf '%s\n' "$commando_specialized_state_cleanup_bytecode" | grep -Fn 'clearPostNgePlayerCommandoSpecializedBuffs' | head -1 | cut -d: -f1)"
commando_specialized_modifier_remove_bytecode_line="$(printf '%s\n' "$commando_specialized_state_cleanup_bytecode" | grep -Fn 'clearPostNgePlayerCommandoSpecializedModifiers' | head -1 | cut -d: -f1)"
test -n "$commando_specialized_parent_remove_bytecode_line"
test -n "$commando_specialized_child_remove_bytecode_line"
test -n "$commando_specialized_modifier_remove_bytecode_line"
test "$commando_specialized_parent_remove_bytecode_line" -lt "$commando_specialized_child_remove_bytecode_line"
test "$commando_specialized_child_remove_bytecode_line" -lt "$commando_specialized_modifier_remove_bytecode_line"
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerCommandoSpecializedState'
commando_specialized_admission_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/canApplyBuff(script.obj_id, script.obj_id, int)/,/getGroups/p')"
commando_specialized_admission_bytecode_line="$(printf '%s\n' "$commando_specialized_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerCommandoSpecializedBuff' | head -1 | cut -d: -f1)"
commando_specialized_existing_bytecode_line="$(printf '%s\n' "$commando_specialized_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$commando_specialized_admission_bytecode_line"
test -n "$commando_specialized_existing_bytecode_line"
test "$commando_specialized_admission_bytecode_line" -lt "$commando_specialized_existing_bytecode_line"
verify_commando_specialized_bytecode_handler()
{
    commando_specialized_method="$1"
    commando_specialized_next_method="$2"
    commando_specialized_cleanup_marker="$3"
    commando_specialized_additional_cleanup_marker="$4"
    commando_specialized_retained_marker="$5"
    commando_specialized_requires_effect_predicate="$6"
    commando_specialized_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n "/$commando_specialized_method/,/$commando_specialized_next_method/p")"
    commando_specialized_guard_bytecode_line="$(printf '%s\n' "$commando_specialized_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
    commando_specialized_cleanup_bytecode_line="$(printf '%s\n' "$commando_specialized_handler_bytecode" | grep -Fn "$commando_specialized_cleanup_marker" | head -1 | cut -d: -f1)"
    commando_specialized_cleanup_end_bytecode_line="$commando_specialized_cleanup_bytecode_line"
    if test -n "$commando_specialized_additional_cleanup_marker"; then
        commando_specialized_additional_cleanup_bytecode_line="$(printf '%s\n' "$commando_specialized_handler_bytecode" | grep -Fn "$commando_specialized_additional_cleanup_marker" | head -1 | cut -d: -f1)"
        test -n "$commando_specialized_additional_cleanup_bytecode_line"
        test "$commando_specialized_cleanup_bytecode_line" -lt "$commando_specialized_additional_cleanup_bytecode_line"
        commando_specialized_cleanup_end_bytecode_line="$commando_specialized_additional_cleanup_bytecode_line"
    fi
    commando_specialized_return_bytecode_line="$(printf '%s\n' "$commando_specialized_handler_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$commando_specialized_cleanup_end_bytecode_line" '$1 > cleanup { print $1; exit }')"
    commando_specialized_retained_bytecode_line="$(printf '%s\n' "$commando_specialized_handler_bytecode" | grep -Fn "$commando_specialized_retained_marker" | head -1 | cut -d: -f1)"
    test -n "$commando_specialized_guard_bytecode_line"
    test -n "$commando_specialized_cleanup_bytecode_line"
    test -n "$commando_specialized_return_bytecode_line"
    test -n "$commando_specialized_retained_bytecode_line"
    test "$commando_specialized_guard_bytecode_line" -lt "$commando_specialized_cleanup_bytecode_line"
    test "$commando_specialized_cleanup_end_bytecode_line" -lt "$commando_specialized_return_bytecode_line"
    test "$commando_specialized_return_bytecode_line" -lt "$commando_specialized_retained_bytecode_line"
    if test "$commando_specialized_requires_effect_predicate" -eq 1; then
        printf '%s\n' "$commando_specialized_handler_bytecode" | grep -Fq 'isRetiredPostNgePlayerCommandoSpecializedEffect'
    fi
}
verify_commando_specialized_bytecode_handler commandoFlashBangAddBuffHandler commandoFlashBangRemoveBuffHandler retirePostNgePlayerCommandoSpecializedState '' expertise_co_flash_bang 0
verify_commando_specialized_bytecode_handler commandoFlashBangRemoveBuffHandler commandoMuscleSpasmAddBuffHandler clearPostNgePlayerCommandoSpecializedModifiers '' 'String commandoFlashBang' 0
verify_commando_specialized_bytecode_handler commandoMuscleSpasmAddBuffHandler commandoMuscleSpasmRemoveBuffHandler retirePostNgePlayerCommandoSpecializedState '' expertise_co_muscle_spasm 0
verify_commando_specialized_bytecode_handler commandoMuscleSpasmRemoveBuffHandler commandoRiddleArmorAddBuffHandler clearPostNgePlayerCommandoSpecializedModifiers '' 'String commandoMuscleSpasm' 0
verify_commando_specialized_bytecode_handler commandoRiddleArmorAddBuffHandler commandoRiddleArmorRemoveBuffHandler retirePostNgePlayerCommandoSpecializedState '' 'String expertise_riddle_armor' 0
verify_commando_specialized_bytecode_handler commandoRiddleArmorRemoveBuffHandler radarInvisAddBuffHandler clearPostNgePlayerCommandoSpecializedModifiers '' 'Method removeAttribOrSkillModModifier' 0
verify_commando_specialized_bytecode_handler onTargetAddBuffHandler onTargetRemoveBuffHandler retirePostNgePlayerCommandoSpecializedState '' 'String expertise_action_line_co_imp_pos_sec' 1
verify_commando_specialized_bytecode_handler onTargetRemoveBuffHandler immunityAddBuffHandler clearPostNgePlayerCommandoSpecializedBuffs clearPostNgePlayerCommandoSpecializedModifiers 'Method hasSkillModModifier' 1
for fs_expertise_immunity_effect in expertise_dot_immunity expertise_movement_immunity; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "String $fs_expertise_immunity_effect"
done
for fs_expertise_immunity_buff in fs_sh_0 fs_sh_1 fs_sh_2 fs_sh_3 fs_dot_immunity_recourse; do
    printf '%s' "$buff_modifier_bytecode" | grep -Fq "String $fs_expertise_immunity_buff"
done
fs_expertise_immunity_effect_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect/,/isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuff(script.obj_id/p')"
printf '%s' "$fs_expertise_immunity_effect_bytecode" | grep -Fq 'Method java/lang/String.equals'
! printf '%s' "$fs_expertise_immunity_effect_bytecode" | grep -Fq 'Method java/lang/String.startsWith'
fs_expertise_immunity_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuff(script.obj_id/,/clearPostNgePlayerForceSensitiveExpertiseImmunityResidue/p')"
printf '%s' "$fs_expertise_immunity_predicate_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$fs_expertise_immunity_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuffName'
printf '%s' "$fs_expertise_immunity_predicate_bytecode" | grep -Fq 'Method getEffectParam'
printf '%s' "$fs_expertise_immunity_predicate_bytecode" | grep -Fq 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect'
fs_expertise_immunity_residue_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/clearPostNgePlayerForceSensitiveExpertiseImmunityResidue/,/retirePostNgePlayerForceSensitiveExpertiseImmunityState/p')"
printf '%s' "$fs_expertise_immunity_residue_bytecode" | grep -Fq 'Method isPlayer'
for fs_expertise_immunity_residue in immunity.dot.all immunity.movement.snare immunity.movement.root; do
    printf '%s' "$fs_expertise_immunity_residue_bytecode" | grep -Fq "String $fs_expertise_immunity_residue"
done
printf '%s' "$fs_expertise_immunity_residue_bytecode" | grep -Fq 'String expertise_dot'
printf '%s' "$fs_expertise_immunity_residue_bytecode" | grep -Fq 'String expertise_movement'
printf '%s' "$fs_expertise_immunity_residue_bytecode" | grep -Fq 'Method stopClientEffectObjByLabel'
fs_expertise_immunity_state_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerForceSensitiveExpertiseImmunityState/,/isRetiredPostNgeGcwBannerBuff/p')"
printf '%s' "$fs_expertise_immunity_state_bytecode" | grep -Fq 'Method isPlayer'
printf '%s' "$fs_expertise_immunity_state_bytecode" | grep -Fq 'Method hasBuff'
printf '%s' "$fs_expertise_immunity_state_bytecode" | grep -Fq 'Method removeBuff'
printf '%s' "$fs_expertise_immunity_state_bytecode" | grep -Fq 'clearPostNgePlayerForceSensitiveExpertiseImmunityResidue'
printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgeBuffProgression/,/canApplyBuff(script.obj_id, java.lang.String)/p' | grep -Fq 'retirePostNgePlayerForceSensitiveExpertiseImmunityState'
fs_expertise_immunity_admission_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/canApplyBuff(script.obj_id, script.obj_id, int)/,/getGroups/p')"
fs_expertise_immunity_admission_bytecode_line="$(printf '%s\n' "$fs_expertise_immunity_admission_bytecode" | grep -Fn 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuff' | head -1 | cut -d: -f1)"
fs_expertise_immunity_existing_bytecode_line="$(printf '%s\n' "$fs_expertise_immunity_admission_bytecode" | grep -Fn 'Method hasBuff' | head -1 | cut -d: -f1)"
test -n "$fs_expertise_immunity_admission_bytecode_line"
test -n "$fs_expertise_immunity_existing_bytecode_line"
test "$fs_expertise_immunity_admission_bytecode_line" -lt "$fs_expertise_immunity_existing_bytecode_line"
verify_fs_expertise_immunity_bytecode_handler()
{
    fs_expertise_immunity_method="$1"
    fs_expertise_immunity_next_method="$2"
    fs_expertise_immunity_cleanup_marker="$3"
    fs_expertise_immunity_retained_marker="$4"
    fs_expertise_immunity_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n "/$fs_expertise_immunity_method/,/$fs_expertise_immunity_next_method/p")"
    fs_expertise_immunity_guard_line="$(printf '%s\n' "$fs_expertise_immunity_handler_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
    fs_expertise_immunity_effect_line="$(printf '%s\n' "$fs_expertise_immunity_handler_bytecode" | grep -Fn 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect' | head -1 | cut -d: -f1)"
    fs_expertise_immunity_name_line="$(printf '%s\n' "$fs_expertise_immunity_handler_bytecode" | grep -Fn 'isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuffName' | head -1 | cut -d: -f1)"
    fs_expertise_immunity_cleanup_line="$(printf '%s\n' "$fs_expertise_immunity_handler_bytecode" | grep -Fn "$fs_expertise_immunity_cleanup_marker" | head -1 | cut -d: -f1)"
    fs_expertise_immunity_return_line="$(printf '%s\n' "$fs_expertise_immunity_handler_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$fs_expertise_immunity_cleanup_line" '$1 > cleanup { print $1; exit }')"
    fs_expertise_immunity_retained_line="$(printf '%s\n' "$fs_expertise_immunity_handler_bytecode" | grep -Fn "$fs_expertise_immunity_retained_marker" | head -1 | cut -d: -f1)"
    test -n "$fs_expertise_immunity_guard_line"
    test -n "$fs_expertise_immunity_effect_line"
    test -n "$fs_expertise_immunity_name_line"
    test -n "$fs_expertise_immunity_cleanup_line"
    test -n "$fs_expertise_immunity_return_line"
    test -n "$fs_expertise_immunity_retained_line"
    test "$fs_expertise_immunity_guard_line" -lt "$fs_expertise_immunity_effect_line"
    test "$fs_expertise_immunity_guard_line" -lt "$fs_expertise_immunity_name_line"
    test "$fs_expertise_immunity_name_line" -lt "$fs_expertise_immunity_cleanup_line"
    test "$fs_expertise_immunity_cleanup_line" -lt "$fs_expertise_immunity_return_line"
    test "$fs_expertise_immunity_return_line" -lt "$fs_expertise_immunity_retained_line"
}
verify_fs_expertise_immunity_bytecode_handler expertiseImmunityAddBuffHandler expertiseImmunityRemoveBuffHandler retirePostNgePlayerForceSensitiveExpertiseImmunityState isInStance
verify_fs_expertise_immunity_bytecode_handler expertiseImmunityRemoveBuffHandler expertiseChannelActionHealAddBuffHandler clearPostNgePlayerForceSensitiveExpertiseImmunityResidue immunityRemoveBuffHandler
ordinary_immunity_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/immunityAddBuffHandler/,/dotReductionAddBuffHandler/p')"
ordinary_immunity_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/immunityRemoveBuffHandler/,/expertiseImmunityAddBuffHandler/p')"
for ordinary_immunity_name in dot_immunity movement_immunity; do
    printf '%s' "$ordinary_immunity_add_bytecode" | grep -Fq "String $ordinary_immunity_name"
    printf '%s' "$ordinary_immunity_remove_bytecode" | grep -Fq "String $ordinary_immunity_name"
done
action_burn_dictionary_cost_bytecode="$(printf '%s' "$combat_library_bytecode" | sed -n '/getActionCost(script.obj_id, script.combat_engine[$]weapon_data, script.dictionary)/,/getActionCost(script.obj_id, script.combat_engine[$]weapon_data, script.combat_engine[$]combat_data)/p')"
action_burn_typed_cost_bytecode="$(printf '%s' "$combat_library_bytecode" | sed -n '/getActionCost(script.obj_id, script.combat_engine[$]weapon_data, script.combat_engine[$]combat_data)/,/getSuccessBasedSingleTargetActionCost/p')"
for action_burn_consumer_bytecode in "$action_burn_dictionary_cost_bytecode" "$action_burn_typed_cost_bytecode"; do
    test "$(printf '%s' "$action_burn_consumer_bytecode" | grep -Fc 'retirePostNgePlayerActionBurnState')" -eq 1
    action_burn_consumer_cleanup_bytecode_line="$(printf '%s\n' "$action_burn_consumer_bytecode" | grep -Fn 'retirePostNgePlayerActionBurnState' | head -1 | cut -d: -f1)"
    action_burn_consumer_guard_bytecode_line="$(printf '%s\n' "$action_burn_consumer_bytecode" | head -n "$action_burn_consumer_cleanup_bytecode_line" | grep -Fn 'Method isPlayer' | tail -1 | cut -d: -f1)"
    action_burn_consumer_read_bytecode_line="$(printf '%s\n' "$action_burn_consumer_bytecode" | grep -Fn 'String buff.action_burn.value' | head -1 | cut -d: -f1)"
    test "$action_burn_consumer_guard_bytecode_line" -lt "$action_burn_consumer_cleanup_bytecode_line"
    test "$action_burn_consumer_cleanup_bytecode_line" -lt "$action_burn_consumer_read_bytecode_line"
done
action_regen_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/actionRegenAddBuffHandler/,/actionRegenRemoveBuffHandler/p')"
action_regen_add_guard_bytecode_line="$(printf '%s\n' "$action_regen_add_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
action_regen_add_cleanup_bytecode_line="$(printf '%s\n' "$action_regen_add_bytecode" | grep -Fn 'retirePostNgePlayerActionRegenState' | head -1 | cut -d: -f1)"
action_regen_add_max_bytecode_line="$(printf '%s\n' "$action_regen_add_bytecode" | grep -Fn 'Method getMaxAction' | head -1 | cut -d: -f1)"
test "$action_regen_add_guard_bytecode_line" -lt "$action_regen_add_cleanup_bytecode_line"
test "$action_regen_add_cleanup_bytecode_line" -lt "$action_regen_add_max_bytecode_line"
action_regen_tick_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/actionRegenBuff(script.obj_id, script.dictionary)/,/bodyguardDefenderAddBuffHandler/p')"
action_regen_tick_guard_bytecode_line="$(printf '%s\n' "$action_regen_tick_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
action_regen_tick_cleanup_bytecode_line="$(printf '%s\n' "$action_regen_tick_bytecode" | grep -Fn 'retirePostNgePlayerActionRegenState' | head -1 | cut -d: -f1)"
action_regen_tick_buff_bytecode_line="$(printf '%s\n' "$action_regen_tick_bytecode" | grep -Fn 'Method script/library/buff.hasBuff' | head -1 | cut -d: -f1)"
action_regen_tick_heal_bytecode_line="$(printf '%s\n' "$action_regen_tick_bytecode" | grep -Fn 'Method script/library/healing.healDamage' | head -1 | cut -d: -f1)"
action_regen_tick_requeue_bytecode_line="$(printf '%s\n' "$action_regen_tick_bytecode" | grep -Fn 'Method messageTo' | tail -1 | cut -d: -f1)"
test "$action_regen_tick_guard_bytecode_line" -lt "$action_regen_tick_cleanup_bytecode_line"
test "$action_regen_tick_cleanup_bytecode_line" -lt "$action_regen_tick_buff_bytecode_line"
test "$action_regen_tick_buff_bytecode_line" -lt "$action_regen_tick_heal_bytecode_line"
test "$action_regen_tick_heal_bytecode_line" -lt "$action_regen_tick_requeue_bytecode_line"
damage_dealt_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/damageDealtModAddBuffHandler/,/damageDealtModRemoveBuffHandler/p')"
printf '%s' "$damage_dealt_add_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$damage_dealt_add_bytecode" | grep -Fq 'buff.restorePostNgePlayerDamageDealtOverride'
printf '%s' "$damage_dealt_add_bytecode" | grep -Fq 'damageDealtMod.value'
printf '%s' "$damage_dealt_add_bytecode" | grep -Fq 'setScale'
damage_dealt_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/damageDealtModRemoveBuffHandler/,/weaponSpeedModAddBuffHandler/p')"
printf '%s' "$damage_dealt_remove_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$damage_dealt_remove_bytecode" | grep -Fq 'buff.restorePostNgePlayerDamageDealtOverride'
printf '%s' "$damage_dealt_remove_bytecode" | grep -Fq 'damageDealtMod.scale'
printf '%s' "$damage_dealt_remove_bytecode" | grep -Fq 'setScale'
weapon_speed_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/weaponSpeedModAddBuffHandler/,/weaponSpeedModRemoveBuffHandler/p')"
printf '%s' "$weapon_speed_add_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$weapon_speed_add_bytecode" | grep -Fq 'buff.restorePostNgePlayerWeaponSpeedOverride'
printf '%s' "$weapon_speed_add_bytecode" | grep -Fq 'setWeaponAttackSpeed'
weapon_speed_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/weaponSpeedModRemoveBuffHandler/,/commandGrantAddBuffHandler/p')"
printf '%s' "$weapon_speed_remove_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$weapon_speed_remove_bytecode" | grep -Fq 'buff.restorePostNgePlayerWeaponSpeedOverride'
printf '%s' "$weapon_speed_remove_bytecode" | grep -Fq 'setWeaponAttackSpeed'
critical_override_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/nextHitCritAddBuffHandler/,/junkDealerAddBuffHandler/p')"
test "$(printf '%s' "$critical_override_handler_bytecode" | grep -Fc 'isPlayer')" -eq 8
test "$(printf '%s' "$critical_override_handler_bytecode" | grep -Fc 'buff.clearPostNgePlayerCriticalOverrideScriptVars')" -eq 8
for retired_critical_override_script_var in nextCritHit critDoubleDamage critRoot critRemoveBuffNames; do
    printf '%s' "$critical_override_handler_bytecode" | grep -Fq "$retired_critical_override_script_var"
done
luck_hit_handler_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/missByLuckAddBuffHandler/,/pistolWhipAddBuffHandler/p')"
test "$(printf '%s' "$luck_hit_handler_bytecode" | grep -Fc 'isPlayer')" -eq 4
test "$(printf '%s' "$luck_hit_handler_bytecode" | grep -Fc 'buff.retirePostNgePlayerLuckHitOverrideState')" -eq 2
test "$(printf '%s' "$luck_hit_handler_bytecode" | grep -Fc 'buff.clearPostNgePlayerLuckHitOverrideModifiers')" -eq 2
for retired_luck_hit_modifier in hitByLuck increaseHitByLuck missByLuck; do
    printf '%s' "$luck_hit_handler_bytecode" | grep -Fq "$retired_luck_hit_modifier"
done
forsake_fear_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/expertiseChannelActionHealAddBuffHandler/,/expertiseChannelActionHealRemoveBuffHandler/p')"
forsake_fear_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/expertiseChannelActionHealRemoveBuffHandler/,/onIncapHealAddBuffHandler/p')"
forsake_fear_channel_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/channelForsakeFear(script.obj_id, java.lang.String, boolean)/,/checkChannelForsakeFear/p')"
forsake_fear_check_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/checkChannelForsakeFear/,/channelForsakeFearCountdownHandler/p')"
forsake_fear_countdown_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/channelForsakeFearCountdownHandler/,/actionDrainAddBuffHandler/p')"
for forsake_fear_add_remove_bytecode in "$forsake_fear_add_bytecode" "$forsake_fear_remove_bytecode"; do
    forsake_fear_guard_bytecode_line="$(printf '%s\n' "$forsake_fear_add_remove_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
    forsake_fear_cleanup_bytecode_line="$(printf '%s\n' "$forsake_fear_add_remove_bytecode" | grep -Fn 'PostNgePlayerForsakeFearChannelState' | head -1 | cut -d: -f1)"
    forsake_fear_return_bytecode_line="$(printf '%s\n' "$forsake_fear_add_remove_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$forsake_fear_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
    test "$forsake_fear_guard_bytecode_line" -lt "$forsake_fear_cleanup_bytecode_line"
    test "$forsake_fear_cleanup_bytecode_line" -lt "$forsake_fear_return_bytecode_line"
done
for forsake_fear_callback_bytecode in "$forsake_fear_channel_bytecode" "$forsake_fear_check_bytecode" "$forsake_fear_countdown_bytecode"; do
    forsake_fear_guard_bytecode_line="$(printf '%s\n' "$forsake_fear_callback_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
    forsake_fear_cleanup_bytecode_line="$(printf '%s\n' "$forsake_fear_callback_bytecode" | grep -Fn 'clearPostNgePlayerForsakeFearChannelState' | head -1 | cut -d: -f1)"
    forsake_fear_return_bytecode_line="$(printf '%s\n' "$forsake_fear_callback_bytecode" | grep -Fn 'ireturn' | awk -F: -v cleanup="$forsake_fear_cleanup_bytecode_line" '$1 > cleanup { print $1; exit }')"
    test "$forsake_fear_guard_bytecode_line" -lt "$forsake_fear_cleanup_bytecode_line"
    test "$forsake_fear_cleanup_bytecode_line" -lt "$forsake_fear_return_bytecode_line"
done
printf '%s' "$forsake_fear_channel_bytecode" | grep -Fq 'healAttribPercent'
printf '%s' "$forsake_fear_check_bytecode" | grep -Fq 'channelForsakeFear'
printf '%s' "$forsake_fear_countdown_bytecode" | grep -Fq 'sui.getIntButtonPressed'
command_grant_add_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/commandGrantAddBuffHandler/,/commandGrantRemoveBuffHandler/p')"
printf '%s' "$command_grant_add_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$command_grant_add_bytecode" | grep -Fq 'buff.isRetiredPostNgePlayerBuffCommandGrant'
printf '%s' "$command_grant_add_bytecode" | grep -Fq 'hasCommand'
printf '%s' "$command_grant_add_bytecode" | grep -Fq 'revokeCommand'
printf '%s' "$command_grant_add_bytecode" | grep -Fq 'grantCommand'
command_grant_remove_bytecode="$(printf '%s' "$buff_handler_bytecode" | sed -n '/commandGrantRemoveBuffHandler/,/OnGroupMembersChanged/p')"
printf '%s' "$command_grant_remove_bytecode" | grep -Fq 'isPlayer'
printf '%s' "$command_grant_remove_bytecode" | grep -Fq 'buff.isRetiredPostNgePlayerBuffCommandGrant'
printf '%s' "$command_grant_remove_bytecode" | grep -Fq 'hasCommand'
printf '%s' "$command_grant_remove_bytecode" | grep -Fq 'revokeCommand'
buff_modifier_predicate_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/isRetiredPostNgePlayerModifierBuff/,/retirePostNgePlayerModifierBuffState/p')"
printf '%s' "$buff_modifier_predicate_bytecode" | grep -Fq 'static_item.isRetiredNgeBuffSkillModifier'
buff_modifier_cleanup_bytecode="$(printf '%s' "$buff_modifier_bytecode" | sed -n '/retirePostNgePlayerModifierBuffState/,/retirePostNgeBuffProgression/p')"
printf '%s' "$buff_modifier_cleanup_bytecode" | grep -Fq 'getAllBuffs'
printf '%s' "$buff_modifier_cleanup_bytecode" | grep -Fq 'combat_engine.getBuffData'
printf '%s' "$buff_modifier_cleanup_bytecode" | grep -Fq 'removeBuff'
combat_base_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base)"
printf '%s' "$combat_base_bytecode" | grep -Fq 'proc.isRetiredPostNgePlayerProcAction'
printf '%s' "$combat_base_bytecode" | grep -Fq 'proc.retirePostNgePlayerProcState'
test "$(printf '%s' "$combat_base_bytecode" | grep -Fc 'buff.clearPostNgePlayerCriticalOverrideScriptVars')" -eq 2
attack_override_bytecode="$(printf '%s' "$combat_base_bytecode" | sed -n '/^  public script.combat_engine[$]combat_data attackOverrideByBuff(/,/^  public void doKillMeterUpdate/p')"
attack_override_guard_bytecode_line="$(printf '%s\n' "$attack_override_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
attack_override_cleanup_bytecode_line="$(printf '%s\n' "$attack_override_bytecode" | grep -Fn 'removeRetiredNgePlayerSkillStatistics' | head -1 | cut -d: -f1)"
attack_override_return_bytecode_line="$(printf '%s\n' "$attack_override_bytecode" | grep -Fn 'areturn' | head -1 | cut -d: -f1)"
attack_override_reader_bytecode_line="$(printf '%s\n' "$attack_override_bytecode" | grep -Fn 'String attack_override_by_buff' | head -1 | cut -d: -f1)"
test -n "$attack_override_guard_bytecode_line"
test -n "$attack_override_cleanup_bytecode_line"
test -n "$attack_override_return_bytecode_line"
test -n "$attack_override_reader_bytecode_line"
test "$attack_override_guard_bytecode_line" -lt "$attack_override_cleanup_bytecode_line"
test "$attack_override_cleanup_bytecode_line" -lt "$attack_override_return_bytecode_line"
test "$attack_override_return_bytecode_line" -lt "$attack_override_reader_bytecode_line"
damage_reduction_combat_bytecode="$(printf '%s' "$combat_base_bytecode" | sed -n '/public int expertiseDamageModify/,/public void doWrappedDamage/p')"
damage_reduction_combat_first_guard_line="$(printf '%s\n' "$damage_reduction_combat_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
damage_reduction_combat_first_cleanup_line="$(printf '%s\n' "$damage_reduction_combat_bytecode" | grep -Fn 'clearPostNgePlayerDamageReductionState' | head -1 | cut -d: -f1)"
damage_reduction_combat_second_cleanup_line="$(printf '%s\n' "$damage_reduction_combat_bytecode" | grep -Fn 'clearPostNgePlayerDamageReductionState' | tail -1 | cut -d: -f1)"
damage_reduction_combat_first_read_line="$(printf '%s\n' "$damage_reduction_combat_bytecode" | grep -Fn 'String expertise_damage_decrease_chance' | head -1 | cut -d: -f1)"
test -n "$damage_reduction_combat_first_guard_line"
test -n "$damage_reduction_combat_first_cleanup_line"
test -n "$damage_reduction_combat_second_cleanup_line"
test -n "$damage_reduction_combat_first_read_line"
test "$(printf '%s' "$damage_reduction_combat_bytecode" | grep -Fc 'clearPostNgePlayerDamageReductionState')" -eq 2
test "$damage_reduction_combat_first_guard_line" -lt "$damage_reduction_combat_first_cleanup_line"
test "$damage_reduction_combat_first_cleanup_line" -lt "$damage_reduction_combat_second_cleanup_line"
test "$damage_reduction_combat_second_cleanup_line" -lt "$damage_reduction_combat_first_read_line"
for damage_reduction_combat_modifier in expertise_damage_decrease_chance expertise_sm_rank_damage_bonus expertise_damage_reduce_anticipate_aggression damage_decrease_percentage area_damage_decrease_percentage area_damage_resist_full_percentage; do
    printf '%s' "$damage_reduction_combat_bytecode" | grep -Fq "String $damage_reduction_combat_modifier"
done
elemental_vulnerability_consumer_bytecode="$(printf '%s' "$combat_base_bytecode" | sed -n '/^  public void doWrappedDamage(.*combat_data, int)/,/^  public script.obj_id\[\] truncateTargetArray/p')"
elemental_vulnerability_consumer_guard_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_consumer_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
elemental_vulnerability_consumer_cleanup_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_consumer_bytecode" | grep -Fn 'retirePostNgePlayerElementalVulnerabilityState' | head -1 | cut -d: -f1)"
elemental_vulnerability_consumer_first_read_bytecode_line="$(printf '%s\n' "$elemental_vulnerability_consumer_bytecode" | grep -Fn 'String elemental_vulnerability.type_heat' | head -1 | cut -d: -f1)"
test -n "$elemental_vulnerability_consumer_guard_bytecode_line"
test -n "$elemental_vulnerability_consumer_cleanup_bytecode_line"
test -n "$elemental_vulnerability_consumer_first_read_bytecode_line"
test "$elemental_vulnerability_consumer_guard_bytecode_line" -lt "$elemental_vulnerability_consumer_cleanup_bytecode_line"
test "$elemental_vulnerability_consumer_cleanup_bytecode_line" -lt "$elemental_vulnerability_consumer_first_read_bytecode_line"
test "$(printf '%s' "$elemental_vulnerability_consumer_bytecode" | grep -Fc 'retirePostNgePlayerElementalVulnerabilityState')" -eq 1
for elemental_vulnerability_state in heat electrical cold acid; do
    printf '%s' "$elemental_vulnerability_consumer_bytecode" | grep -Fq "String elemental_vulnerability.type_$elemental_vulnerability_state"
done
raw_damage_bytecode="$(printf '%s' "$combat_base_bytecode" | sed -n '/^  public script.dictionary getRawDamage(/,/^  public script.dictionary getPrecuCore3RawDamage(/p')"
damage_dealt_bytecode_cleanup_line="$(printf '%s\n' "$raw_damage_bytecode" | grep -Fn 'buff.restorePostNgePlayerDamageDealtOverride' | head -1 | cut -d: -f1)"
damage_dealt_bytecode_read_line="$(printf '%s\n' "$raw_damage_bytecode" | grep -Fn 'damageDealtMod.value' | head -1 | cut -d: -f1)"
test "$damage_dealt_bytecode_cleanup_line" -lt "$damage_dealt_bytecode_read_line"
printf '%s' "$raw_damage_bytecode" | grep -Fq 'isPlayer'
proc_direct_action_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_actions | sed -n '/expertise_fs_flurry_charge_proc/,/meleeHit/p')"
printf '%s' "$proc_direct_action_bytecode" | grep -Fq 'proc.isRetiredPostNgePlayerProcAction'
printf '%s' "$proc_direct_action_bytecode" | grep -Fq 'proc.retirePostNgePlayerProcState'
cybernetic_bytecode="$(javap -classpath "$class_root" -c -p script.library.cybernetic)"
cybernetic_constants="$(javap -classpath "$class_root" -v script.library.cybernetic)"
printf '%s' "$cybernetic_bytecode" | grep -Fq 'isRetiredPostNgePlayerCyberneticCommandActor'
printf '%s' "$cybernetic_bytecode" | grep -Fq 'retirePostNgePlayerCyberneticCommandState'
printf '%s' "$cybernetic_bytecode" | grep -Fq 'revokeCommand'
printf '%s' "$cybernetic_bytecode" | grep -Fq 'removeBuff'
for retired_cybernetic_modifier in cybernetic_healing_mod cybernetic_heavy_weapon_legs cybernetic_melee_acc cybernetic_melee_def cybernetic_ranged_acc cybernetic_ranged_range cybernetic_run_buff cybernetic_throw_range; do
    printf '%s' "$cybernetic_constants" | grep -Fq "$retired_cybernetic_modifier"
done
printf '%s' "$cybernetic_constants" | grep -Fq 'cyberneticLegs'
cybernetic_cleanup_bytecode="$(printf '%s' "$cybernetic_bytecode" | sed -n '/retirePostNgePlayerCyberneticCommandState/,/installCybernetics/p')"
printf '%s' "$cybernetic_cleanup_bytecode" | grep -Fq 'getSkillStatMod'
printf '%s' "$cybernetic_cleanup_bytecode" | grep -Fq 'applySkillStatisticModifier'
cybernetic_grant_bytecode="$(printf '%s' "$cybernetic_bytecode" | sed -n '/grantSpecialCommands/,/revokeSpecialCommands/p')"
printf '%s' "$cybernetic_grant_bytecode" | grep -Fq 'isRetiredPostNgePlayerCyberneticCommandActor'
printf '%s' "$cybernetic_grant_bytecode" | grep -Fq 'grantCommand'
cybernetic_run_boost_bytecode="$(printf '%s' "$cybernetic_bytecode" | sed -n '/applyRunBoostMod/,/grantSpecialCommands/p')"
test "$(printf '%s' "$cybernetic_run_boost_bytecode" | grep -Fc 'isRetiredPostNgePlayerCyberneticCommandActor')" -ge 2
cybernetic_skill_modifier_bytecode="$(printf '%s' "$cybernetic_bytecode" | sed -n '/grantCyberneticSkillMods/,/validateSkillMods/p')"
test "$(printf '%s' "$cybernetic_skill_modifier_bytecode" | grep -Fc 'isRetiredPostNgePlayerCyberneticCommandActor')" -ge 2
cybernetic_combat_accessor_bytecode="$(printf '%s' "$cybernetic_bytecode" | sed -n '/getThrowRangeMod/,/grantCyberneticSkillMods/p')"
test "$(printf '%s' "$cybernetic_combat_accessor_bytecode" | grep -Fc 'isRetiredPostNgePlayerCyberneticCommandActor')" -ge 7
cybernetic_validate_bytecode="$(printf '%s' "$cybernetic_bytecode" | sed -n '/validateSkillMods/,/revokeAllOccurancesOfCommand/p')"
printf '%s' "$cybernetic_validate_bytecode" | grep -Fq 'movement.refresh'
printf '%s' "$cybernetic_validate_bytecode" | grep -Fq 'getInstalledCybernetics'
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
species_retirement_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base | sed -n '/public static boolean isRetiredPostNgeSpeciesPlayerAction/,/public static boolean isRetiredPostNgeSpyPlayerAction/p')"
species_retirement_constants="$(javap -classpath "$class_root" -v script.systems.combat.combat_base)"
for retired_species_action in human_ability_1 wookiee_ability_1 rodian_ability_1 bothan_ability_1 ithorian_ability_1 twilek_ability_1 sullustan_ability_1 moncal_ability_1 trandoshan_ability_1 zabrak_ability_1; do
    printf '%s' "$species_retirement_constants" | grep -Fq "$retired_species_action"
done
printf '%s' "$species_retirement_bytecode" | grep -Fq 'Method hasCommand'
printf '%s' "$species_retirement_bytecode" | grep -Fq 'Method revokeCommand'
printf '%s' "$species_retirement_bytecode" | grep -Fq 'Method script/library/buff.removeBuff'
printf '%s' "$species_retirement_bytecode" | grep -Fq 'healing.hot_id'
species_standard_action_bytecode="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base | sed -n '/public boolean combatStandardAction(java.lang.String, script.obj_id, script.obj_id, script.obj_id, java.lang.String, script.combat_engine.combat_data, boolean, boolean, int)/,/public boolean doCombatPreCheck/p')"
printf '%s' "$species_standard_action_bytecode" | grep -Fq 'Method isRetiredPostNgeSpeciesPlayerAction'
printf '%s' "$species_standard_action_bytecode" | grep -Fq 'Method retirePostNgeSpeciesAbilityState'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'retirePostNgeSpeciesAbilityState'
grep -Fq 'datastorage * pet_lib.DETONATION_DROID_MIN_DAMAGE' "$work_script/ai/pet.java"
grep -Fq 'datastorage * pet_lib.getDetonationDroidMinDamage()' "$work_script/ai/pet_control_device.java"
grep -Fq 'datastorage * pet_lib.getDetonationDroidMinDamage()' "$work_script/npc/pet_deed/droid_deed.java"
grep -Fq 'int target_min_damage = min_dam' "$work_script/systems/crafting/droid/modules/droid_bomb.java"
grep -Fq 'getAttackableTargetsInRadius(droid, PRECU_DETONATION_RADIUS, true)' "$work_script/systems/crafting/droid/modules/droid_bomb.java"
javap -classpath "$class_root" -constants script.item.survey_tool.survey_tool_script | grep -Fq 'PRECU_SAMPLE_ACTION_BASE_COST = 124'
javap -classpath "$class_root" -constants script.item.survey_tool.survey_tool_script | grep -Fq 'PRECU_SAMPLE_QUICKNESS_DIVISOR = 12.5f'
! javap -classpath "$class_root" -v script.item.buff_click_item | grep -Fq 'required_level_for_effect'
tcg_instant_buff_bytecode="$(javap -classpath "$class_root" -c -p script.library.buff)"
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series1_nuna_ball_advertisement'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series2_versafunction88_datapad'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series9_lepese_dictionary'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerBuildABuffOrXpGrantBuff'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series1_radtrooper_badge'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series1_hans_hydrospanner'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series2_mandalorian_strongbox'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series2_keelkana_tooth'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series3_general_grievous_gutsack'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series5_klorri_clan_shield'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'tcg_series6_ponda_baba_arm'
printf '%s\n' "$tcg_instant_buff_bytecode" | grep -Fq 'isRetiredPostNgePlayerTcgXpBonusBuff'
tcg_instant_click_bytecode="$(javap -classpath "$class_root" -c -p script.item.buff_click_item)"
printf '%s\n' "$tcg_instant_click_bytecode" | grep -Fq 'isRetiredPostNgePlayerInstantXpGrantBuffName'
printf '%s\n' "$tcg_instant_click_bytecode" | grep -Fq 'isRetiredPostNgePlayerTcgXpBonusBuffName'
tcg_instant_adapter_bytecode="$(printf '%s\n' "$tcg_instant_click_bytecode" | sed -n '/public void grantPrecuTcgXpReplacement/,/^}/p')"
printf '%s\n' "$tcg_instant_adapter_bytecode" | grep -Fq 'grantRandomCollectionItem'
printf '%s\n' "$tcg_instant_adapter_bytecode" | grep -Fq 'decrementStaticItem'
test "$(printf '%s\n' "$tcg_instant_adapter_bytecode" | grep -Fc 'decrementStaticItem')" -eq 1
! printf '%s\n' "$tcg_instant_adapter_bytecode" | grep -Fq 'applyBuff'
! javap -classpath "$class_root" -v script.item.full_heal_item | grep -Fq 'required_level_for_effect'
! javap -classpath "$class_root" -v script.item.levelup_orb.levelup_orb | grep -Fq 'player_level.iff'
! javap -classpath "$class_root" -v script.item.levelup_orb.levelup_orb | grep -Fq 'combat_general'
javap -classpath "$class_root" -v script.item.levelup_orb.levelup_orb | grep -Fq 'item.special.nomove'
javap -classpath "$class_root" -v script.item.levelup_orb.levelup_orb | grep -Fq 'detachScript'
! javap -classpath "$class_root" -v script.item.medicine.stimpack | grep -Fq 'combat_level_required'
! javap -classpath "$class_root" -v script.item.medicine.stimpack_crafted | grep -Fq 'combat_level_required'
test "$(javap -classpath "$class_root" -c -p script.item.medicine.stimpack | grep -Fc 'removeLegacyNgeItemCombatLevelRequirement')" -eq 4
crafted_stim_bytecode="$(javap -classpath "$class_root" -c -p script.item.medicine.stimpack_crafted)"
test "$(printf '%s\n' "$crafted_stim_bytecode" | grep -Fc 'removeLegacyNgeItemCombatLevelRequirement')" -eq 4
! printf '%s\n' "$crafted_stim_bytecode" | grep -Fq 'recent_heal'
! printf '%s\n' "$crafted_stim_bytecode" | grep -Fq 'useChannelHealItem'
test "$(printf '%s\n' "$crafted_stim_bytecode" | grep -Fc 'Method script/library/healing.useHealDamageItem')" -eq 2
healing_bytecode="$(javap -classpath "$class_root" -c -p script.library.healing)"
channel_heal_adapter_bytecode="$(printf '%s\n' "$healing_bytecode" | sed -n '/useChannelHealItem(script.obj_id, script.obj_id, int)/,/useHealPetItem/p')"
channel_heal_adapter_guard_bytecode_line="$(printf '%s\n' "$channel_heal_adapter_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
channel_heal_adapter_cleanup_bytecode_line="$(printf '%s\n' "$channel_heal_adapter_bytecode" | grep -Fn 'retirePostNgePlayerChannelHealState' | head -1 | cut -d: -f1)"
channel_heal_adapter_return_bytecode_line="$(printf '%s\n' "$channel_heal_adapter_bytecode" | grep -Fn 'useHealDamageItem' | head -1 | cut -d: -f1)"
channel_heal_adapter_message_bytecode_line="$(printf '%s\n' "$channel_heal_adapter_bytecode" | grep -Fn 'String channelHeal' | head -1 | cut -d: -f1)"
channel_heal_adapter_decrement_bytecode_line="$(printf '%s\n' "$channel_heal_adapter_bytecode" | grep -Fn 'Method decrementCount' | head -1 | cut -d: -f1)"
test "$channel_heal_adapter_guard_bytecode_line" -lt "$channel_heal_adapter_cleanup_bytecode_line"
test "$channel_heal_adapter_cleanup_bytecode_line" -lt "$channel_heal_adapter_return_bytecode_line"
test "$channel_heal_adapter_return_bytecode_line" -lt "$channel_heal_adapter_message_bytecode_line"
test "$channel_heal_adapter_return_bytecode_line" -lt "$channel_heal_adapter_decrement_bytecode_line"
player_utility_bytecode="$(javap -classpath "$class_root" -c -p script.player.player_utility)"
channel_heal_callback_bytecode="$(printf '%s\n' "$player_utility_bytecode" | sed -n '/channelHeal(script.obj_id, script.dictionary)/,/residentLinkFalse/p')"
channel_heal_callback_guard_bytecode_line="$(printf '%s\n' "$channel_heal_callback_bytecode" | grep -Fn 'Method isPlayer' | head -1 | cut -d: -f1)"
channel_heal_callback_cleanup_bytecode_line="$(printf '%s\n' "$channel_heal_callback_bytecode" | grep -Fn 'retirePostNgePlayerChannelHealState' | head -1 | cut -d: -f1)"
channel_heal_callback_writer_bytecode_line="$(printf '%s\n' "$channel_heal_callback_bytecode" | grep -Fn 'Method script/library/healing.healDamage' | head -1 | cut -d: -f1)"
channel_heal_callback_requeue_bytecode_line="$(printf '%s\n' "$channel_heal_callback_bytecode" | grep -Fn 'String channelHeal' | tail -1 | cut -d: -f1)"
test "$channel_heal_callback_guard_bytecode_line" -lt "$channel_heal_callback_cleanup_bytecode_line"
test "$channel_heal_callback_cleanup_bytecode_line" -lt "$channel_heal_callback_writer_bytecode_line"
test "$channel_heal_callback_cleanup_bytecode_line" -lt "$channel_heal_callback_requeue_bytecode_line"
test "$(javap -classpath "$class_root" -c -p script.item.plant.force_melon | grep -Fc 'removeLegacyNgeItemCombatLevelRequirement')" -eq 1
static_item_bytecode="$(javap -classpath "$class_root" -c -p script.library.static_item)"
printf '%s\n' "$static_item_bytecode" | sed -n '/public static boolean isRetiredNgeBuffSkillModifier/,/public static void removeRetiredNgePlayerSkillStatistics/p' | grep -Fq 'isRetiredNgeStaticItemSkillModifier'
item_level_cleanup_bytecode="$(printf '%s\n' "$static_item_bytecode" | sed -n '/public static void removeLegacyNgeItemCombatLevelRequirement(/,/public static int generateStatMod(/p')"
printf '%s\n' "$item_level_cleanup_bytecode" | grep -Fq 'healing.combat_level_required'
printf '%s\n' "$item_level_cleanup_bytecode" | grep -Fq 'removeObjVar'
static_modifier_predicate_bytecode="$(printf '%s\n' "$static_item_bytecode" | sed -n '/public static boolean isRetiredNgeStaticItemSkillModifier(/,/public static void removeRetiredNgeStaticItemSkillModifiers(/p')"
static_modifier_cleanup_bytecode="$(printf '%s\n' "$static_item_bytecode" | sed -n '/public static void removeRetiredNgeStaticItemSkillModifiers(/,/public static void applyPrecuStaticItemSkillModifiers(/p')"
static_modifier_apply_bytecode="$(printf '%s\n' "$static_item_bytecode" | sed -n '/public static void applyPrecuStaticItemSkillModifiers(/,/public static boolean initializeArmor(/p')"
printf '%s\n' "$static_modifier_predicate_bytecode" | grep -Fq 'expertise_'
printf '%s\n' "$static_modifier_predicate_bytecode" | grep -Fq 'fast_attack_line_'
printf '%s\n' "$static_modifier_predicate_bytecode" | grep -Fq 'bm_'
printf '%s\n' "$static_modifier_predicate_bytecode" | grep -Fq 'LEGACY_NGE_DYNAMIC_PRIMARY_MODIFIERS'
printf '%s\n' "$static_modifier_predicate_bytecode" | grep -Fq 'RETIRED_NGE_STATIC_ITEM_MODIFIERS'
printf '%s\n' "$static_modifier_predicate_bytecode" | grep -Fq 'RETIRED_NGE_ITEM_WRITER_MODIFIERS'
printf '%s\n' "$static_modifier_predicate_bytecode" | grep -Fq 'RETIRED_NGE_BUFF_COMBAT_MODIFIERS'
printf '%s\n' "$static_modifier_cleanup_bytecode" | grep -Fq 'getSkillModBonuses'
printf '%s\n' "$static_modifier_cleanup_bytecode" | grep -Fq 'setSkillModBonus'
printf '%s\n' "$static_modifier_apply_bytecode" | grep -Fq 'removeRetiredNgeStaticItemSkillModifiers'
printf '%s\n' "$static_modifier_apply_bytecode" | grep -Fq 'parseSkillModifiers'
printf '%s\n' "$static_modifier_apply_bytecode" | grep -Fq 'setSkillModBonus'
test "$(printf '%s\n' "$static_item_bytecode" | grep -Fc 'Method applyPrecuStaticItemSkillModifiers')" -eq 3
for retired_static_primary in precision_modified strength_modified stamina_modified constitution_modified agility_modified luck_modified; do
    printf '%s\n' "$static_item_bytecode" | grep -Fq "$retired_static_primary"
done
for retired_static_set_modifier in bh_dire_root bh_dire_snare combat_block_chance combat_block_value combat_strikethrough_chance cooldown_percent_of_group_buff incubation_time_reduction rally_point_duration tka_armor; do
    printf '%s\n' "$static_item_bytecode" | grep -Fq "$retired_static_set_modifier"
done
for retired_item_writer_modifier in combat_critical_hit_reduction combat_dodge combat_parry combat_evasion_chance combat_evasion_value combat_strikethrough_value commando_devastation exotic_heal_action_reduction exotic_dodge_reduction exotic_parry_reduction exotic_acid_penetration exotic_cold_penetration exotic_heat_penetration exotic_electricity_penetration; do
    printf '%s\n' "$static_item_bytecode" | grep -Fq "$retired_item_writer_modifier"
done
for retired_buff_combat_modifier in $retired_buff_combat_modifiers; do
    printf '%s\n' "$static_item_bytecode" | grep -Fq "$retired_buff_combat_modifier"
done
spy_freeshot_bytecode="$(printf '%s\n' "$combat_library_bytecode" | sed -n '/getSuccessBasedSingleTargetActionCost(/,/setPersistCombatMode/p')"
printf '%s\n' "$spy_freeshot_bytecode" | awk '
/Field script\/combat_engine\$combat_data.precuHamCostModel/ { precu = NR }
/Method isPlayer:/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics/ { cleanup = NR }
/areturn/ && cleanup > 0 && earlyReturn == 0 { earlyReturn = NR }
/String freeshot_case_miss/ { reader = NR }
END { if (!(precu > 0 && guard > precu && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
hit_table_glancing_bytecode="$(printf '%s\n' "$combat_library_bytecode" | sed -n '/getAttackerGlancingReduction(/,/getPunishingBlowChance/p')"
printf '%s\n' "$hit_table_glancing_bytecode" | awk '
/Method isPlayer:/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics/ { cleanup = NR }
/freturn/ && cleanup > 0 && earlyReturn == 0 { earlyReturn = NR }
/String glancing_blow_vulnerable/ { reader = NR }
END { if (!(guard > 0 && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
hit_table_critical_bytecode="$(printf '%s\n' "$combat_library_bytecode" | sed -n '/getDefenderCriticalChance(/,/getStrikethroughChance/p')"
printf '%s\n' "$hit_table_critical_bytecode" | awk '
/Method isPlayer:/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics/ { cleanup = NR }
/freturn/ && cleanup > 0 && earlyReturn == 0 { earlyReturn = NR }
/String critical_hit_vulnerable/ { reader = NR }
END { if (!(guard > 0 && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
hit_table_strikethrough_bytecode="$(printf '%s\n' "$combat_library_bytecode" | sed -n '/getDefenderStrikethroughReduction(/,/getStrikethroughValue/p')"
printf '%s\n' "$hit_table_strikethrough_bytecode" | awk '
/Method isPlayer:/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics/ { cleanup = NR }
/freturn/ && cleanup > 0 && earlyReturn == 0 { earlyReturn = NR }
/String strikethrough_vulnerable/ { reader = NR }
END { if (!(guard > 0 && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
lucky_break_defender_bytecode="$(printf '%s\n' "$combat_base_bytecode" | sed -n '/public int getSingleTargetDefenderResult(/,/public int getSingleTargetAttackResult(/p')"
lucky_break_attack_bytecode="$(printf '%s\n' "$combat_base_bytecode" | sed -n '/public int getSingleTargetAttackResult(/,/public void displayHitTable(/p')"
printf '%s\n' "$lucky_break_defender_bytecode" | awk '/Method isPlayer:/ { guard = NR } /String hit_always/ { reader = NR } END { if (!(guard > 0 && reader > guard)) exit 2 }'
printf '%s\n' "$lucky_break_attack_bytecode" | awk '/Method isPlayer:/ { guard = NR } /String crit_always/ { reader = NR } END { if (!(guard > 0 && reader > guard)) exit 2 }'
inspired_action_bytecode="$(printf '%s\n' "$profession_proxy_combat_actions_bytecode" | sed -n '/public void doInspiredAction(/,/public int of_last_words_recourse(/p')"
printf '%s\n' "$inspired_action_bytecode" | awk '
/Method isPlayer:/ { guard = NR }
/removeRetiredNgePlayerSkillStatistics/ { cleanup = NR }
/return/ && cleanup > 0 && earlyReturn == 0 { earlyReturn = NR }
/String of_inspired_action_chance/ { reader = NR }
END { if (!(guard > 0 && cleanup > guard && earlyReturn > cleanup && reader > earlyReturn)) exit 2 }'
parse_skill_modifiers_bytecode="$(printf '%s\n' "$static_item_bytecode" | sed -n '/public static script.dictionary parseSkillModifiers/,/public static script.obj_id makeDynamicObject/p')"
printf '%s\n' "$parse_skill_modifiers_bytecode" | grep -Fq 'isRetiredNgeStaticItemSkillModifier'
printf '%s\n' "$parse_skill_modifiers_bytecode" | grep -Fq 'script/dictionary.put'
player_modifier_cleanup_bytecode="$(printf '%s\n' "$static_item_bytecode" | sed -n '/public static void removeRetiredNgePlayerSkillStatistics/,/public static void removeRetiredNgeStaticItemSkillModifiers/p')"
printf '%s\n' "$player_modifier_cleanup_bytecode" | grep -Fq 'getSkillStatModListingForPlayer'
printf '%s\n' "$player_modifier_cleanup_bytecode" | grep -Fq 'isRetiredNgeStaticItemSkillModifier'
printf '%s\n' "$player_modifier_cleanup_bytecode" | grep -Fq 'getSkillStatMod'
printf '%s\n' "$player_modifier_cleanup_bytecode" | grep -Fq 'applySkillStatisticModifier'
javap -classpath "$class_root" -c -p script.library.buff | grep -Fq 'removeRetiredNgePlayerSkillStatistics'
javap -classpath "$class_root" -c -p script.library.collection | grep -Fq 'isRetiredNgeStaticItemSkillModifier'
javap -classpath "$class_root" -c -p script.library.player_structure | grep -Fq 'isRetiredNgeStaticItemSkillModifier'
javap -classpath "$class_root" -c -p script.player.player_utility | grep -Fq 'isRetiredNgeStaticItemSkillModifier'
for static_parser_consumer_class in script.item.skillmod_click_item script.systems.sign.special_sign script.systems.tcg.tcg_vendor_contract; do
    static_parser_consumer_bytecode="$(javap -classpath "$class_root" -c -p "$static_parser_consumer_class")"
    printf '%s\n' "$static_parser_consumer_bytecode" | grep -Fq 'parseSkillModifiers'
    printf '%s\n' "$static_parser_consumer_bytecode" | grep -Fq 'applySkillStatisticModifier'
done
buff_handler_item_bytecode="$(javap -classpath "$class_root" -c -p script.systems.buff.buff_handler)"
printf '%s\n' "$buff_handler_item_bytecode" | grep -Fq 'static_item.isRetiredNgeBuffSkillModifier'
for generic_buff_writer in skillAddBuffHandler skillPercentAddBuffHandler forcePowerAddBuffHandler; do
    generic_buff_writer_bytecode="$(printf '%s\n' "$buff_handler_item_bytecode" | sed -n "/public int $generic_buff_writer/,/public int .*RemoveBuffHandler/p")"
    printf '%s\n' "$generic_buff_writer_bytecode" | grep -Fq 'isPlayer'
    printf '%s\n' "$generic_buff_writer_bytecode" | grep -Fq 'isRetiredNgeBuffSkillModifier'
    printf '%s\n' "$generic_buff_writer_bytecode" | grep -Fq 'addSkillModModifier'
done
reverse_tool_bytecode="$(javap -classpath "$class_root" -c -p script.item.tool.reverse_engineering_tool)"
for precu_reverse_basic_modifier in general_assembly weapon_assembly armor_assembly clothing_assembly droid_assembly food_assembly; do
    printf '%s\n' "$reverse_tool_bytecode" | grep -Fq "$precu_reverse_basic_modifier"
done
test "$(printf '%s\n' "$reverse_tool_bytecode" | grep -Fc 'isRetiredNgeStaticItemSkillModifier')" -eq 4
reverse_engineering_bytecode="$(javap -classpath "$class_root" -c -p script.library.reverse_engineering)"
printf '%s\n' "$reverse_engineering_bytecode" | grep -Fq 'isRetiredNgePowerupModifier'
printf '%s\n' "$reverse_engineering_bytecode" | grep -Fq 'retireNgePowerupModifier'
printf '%s\n' "$reverse_engineering_bytecode" | grep -Fq 'removeAttribOrSkillModModifier'
powered_item_bytecode="$(javap -classpath "$class_root" -c -p script.item.tool.reverse_engineering_poweredup_item)"
test "$(printf '%s\n' "$powered_item_bytecode" | grep -Fc 'isRetiredNgePowerupModifier')" -eq 2
test "$(printf '%s\n' "$powered_item_bytecode" | grep -Fc 'retireNgePowerupModifier')" -eq 2
javap -classpath "$class_root" -c -p script.library.magic_item | grep -Fq 'getPrecuMagicItemMods'
javap -classpath "$class_root" -c -p script.systems.crafting.crafting_base | grep -Fq 'isRetiredNgeStaticItemSkillModifier'
javap -classpath "$class_root" -c -p script.library.consumable | grep -Fq 'isRetiredNgeStaticItemSkillModifier'
test "$(javap -classpath "$class_root" -c -p script.item.skill_buff.base | grep -Fc 'isRetiredNgeStaticItemSkillModifier')" -eq 2
javap -classpath "$class_root" -v script.systems.crafting.clothing.crafting_base_clothing | grep -Fq 'BIO_COMP_EFFECT_SKILL_MODS'
! javap -classpath "$class_root" -v script.systems.crafting.weapon.component.crafting_weapon_component_attribute | grep -E -i -q "$legacy_item_combat_level_pattern"
javap -classpath "$class_root" -v script.systems.crafting.weapon.component.crafting_weapon_component_attribute | grep -Fq 'getWeaponCoreData'
compiled_item_stats="$class_root/datatables/item/master_item/item_stats.iff"
compiled_advanced_search="$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/commodity/advanced_search_attribute.iff"
test -f "$compiled_item_stats"
test -f "$compiled_advanced_search"
! strings "$compiled_item_stats" | grep -E -i -q "$legacy_item_combat_level_pattern"
! strings "$compiled_advanced_search" | grep -E -i -q "$legacy_item_combat_level_pattern"
for precu_stim_template_path in $precu_stim_template_paths; do
    compiled_stim_template="$class_root/object/tangible/medicine/${precu_stim_template_path%.tpf}.iff"
    test -f "$compiled_stim_template"
    ! strings "$compiled_stim_template" | grep -E -i -q "$legacy_item_combat_level_pattern"
done
dynamic_generation_bytecode="$(printf '%s\n' "$static_item_bytecode" | sed -n '/public static void generateItemStatBonuses(/,/public static void removeLegacyNgeDynamicPrimaryModifiers(/p')"
dynamic_cleanup_bytecode="$(printf '%s\n' "$static_item_bytecode" | sed -n '/public static void removeLegacyNgeDynamicPrimaryModifiers(/,/public static int generateStatMod(/p')"
printf '%s\n' "$dynamic_generation_bytecode" | grep -Fq 'skillmod.bonus.camouflage'
printf '%s\n' "$dynamic_generation_bytecode" | grep -Fq 'removeLegacyNgeDynamicPrimaryModifiers'
printf '%s\n' "$dynamic_cleanup_bytecode" | grep -Fq 'removeObjVar'
for legacy_dynamic_primary in precision_modified strength_modified stamina_modified constitution_modified agility_modified luck_modified; do
    printf '%s\n' "$static_item_bytecode" | grep -Fq "$legacy_dynamic_primary"
    ! printf '%s\n' "$dynamic_generation_bytecode" | grep -Fq "$legacy_dynamic_primary"
done
test "$(javap -classpath "$class_root" -c -p script.item.armor.dynamic_armor | grep -Fc 'removeLegacyNgeDynamicPrimaryModifiers')" -eq 3
javap -classpath "$class_root" -c -p script.library.loot | grep -Fq 'makeDynamicObject'
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
grep -Fq 'skillName.find("bh_title") == 0' "$work_creature"
awk -F '\t' '$1 ~ /^bh_title/ { found++; names[$1]++; if ($1 != "bh_titleinformant" && $1 != "bh_title_inspector" && $1 != "bh_title_agent") exit 2; if ($5 != 1 || $22 != "" || $23 != "") exit 3 } END { if (found != 3 || names["bh_titleinformant"] != 1 || names["bh_title_inspector"] != 1 || names["bh_title_agent"] != 1) exit 4 }' "$work_skills"
grep -Fq 'isRetiredNgeProgressionCommandName' "$work_creature"
grep -Fq 'ignored as a retired NGE progression command' "$work_creature"
grep -Fq 'commandName == "bountycheck"' "$work_creature"
! grep -Fq 'commandName == "groupdance"' "$work_creature"
! grep -Fq 'commandName == "imagedesign"' "$work_creature"
grep -Fq 'Rejected retired NGE expertise request' "$work_creature"
grep -Fq 'clearRetiredNgeProgressionSkills' "$work_creature"
grep -Fq 'm_skills.erase(*iter)' "$work_creature"
retired_skill_cleanup_source="$(sed -n '/void CreatureObject::clearRetiredNgeProgressionSkills()/,/void CreatureObject::clearRetiredNgeProgressionExperience()/p' "$work_creature")"
printf '%s' "$retired_skill_cleanup_source" | grep -Fq 'PlayerCreatureController::getPlayerObject(this)'
printf '%s' "$retired_skill_cleanup_source" | grep -Fq 'isRetiredNgeProgressionSkillName(playerObject->getTitle())'
printf '%s' "$retired_skill_cleanup_source" | grep -Fq 'playerObject->setTitle(std::string());'
! printf '%s' "$retired_skill_cleanup_source" | grep -Fq 'revokeSkill('
grep -Fq 'clearRetiredNgeProgressionSkills' "$work_creature_header"
grep -Fq 'Ignored retired NGE createGroupPickup command' "$work_commands"
grep -Fq 'Ignored retired NGE useGroupPickup command' "$work_commands"
grep -Fq 'return 0;' "$work_group"
grep -Fq 'const uint32_t cs_maximumNumberInGroup = 24;' "$work_group"
grep -Fq 'reuseableWp.groupPickupWp' "$work_player"
grep -Fq 'normalizePrecuAttackSpeed' "$work_weapon"
grep -Fq 'getStoredAttackTime' "$work_weapon_header"
species_retirement_list_source="$(sed -n '/private static final String\[\] RETIRED_POST_NGE_SPECIES_PLAYER_ACTIONS/,/public static boolean isRetiredPostNgeSpeciesPlayerAction/p' "$work_combat_base")"
test "$(printf '%s' "$species_retirement_list_source" | grep -Eoc '"[a-z]+_ability_1"')" -eq 10
for retired_species_action in human_ability_1 wookiee_ability_1 rodian_ability_1 bothan_ability_1 ithorian_ability_1 twilek_ability_1 sullustan_ability_1 moncal_ability_1 trandoshan_ability_1 zabrak_ability_1; do
    printf '%s' "$species_retirement_list_source" | grep -Fq "\"$retired_species_action\""
done
! printf '%s' "$species_retirement_list_source" | grep -Eq '"(regeneration|wookieeRoar|vitalize|equilibrium)"'
species_retirement_cleanup_source="$(sed -n '/public static void retirePostNgeSpeciesAbilityState/,/public static boolean isRetiredPostNgeSpyPlayerAction/p' "$work_combat_base")"
printf '%s' "$species_retirement_cleanup_source" | grep -Fq 'while (hasCommand(player, retiredAction))'
printf '%s' "$species_retirement_cleanup_source" | grep -Fq 'revokeCommand(player, retiredAction)'
printf '%s' "$species_retirement_cleanup_source" | grep -Fq 'buff.removeBuff(player, "invis_bothan_ability_1")'
printf '%s' "$species_retirement_cleanup_source" | grep -Fq 'utils.removeScriptVar(player, healing.VAR_PLAYER_HOT_ID)'
grep -Fq 'script.systems.combat.combat_base.retirePostNgeSpeciesAbilityState(self);' "$work_base_player"
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
test -f "$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/object/weapon/melee/unarmed/unarmed_default_player.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_profiles.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/skill/skills.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/command/command_table.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/buff/buff.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/datatables/mob/precu_creature_combat_profiles.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/datatables/pvp/force_rank_xp.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/datatables/pvp/force_rank.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/datatables/pvp/force_rank_dark.iff"
test -f "$server_script_archive"
test -f "$server_network_messages_archive"
grep -Fq 'TRIG_HEALING_RECEIVED = 308' "$work_script_function_header"
grep -Fq '{Scripting::TRIG_HEALING_RECEIVED, "OnHealingReceived", "Oi"}' "$work_script_function_table"
grep -Fq 'JF("_healDamage", "(JJIIZ)I", healDamage)' "$work_script_methods_attributes"
grep -Fq 'CreatureObject::healDamage(Attributes::Enumerator attribute, int amount' "$work_creature"
grep -Fq 'notifyHealingReceived && delta > 0 && source.isValid()' "$work_creature"
grep -Fq 'params.addParam(appliedDelta);' "$work_creature"
! grep -Fq 'appliedDelta > 0' "$work_creature"
grep -Fq 'bool notifyHealingReceived = false' "$work_creature_header"
grep -Fq 'NetworkId         m_source;' "$work_alter_attribute_message_header"
grep -Fq 'bool              m_notifyHealingReceived;' "$work_alter_attribute_message_header"
grep -Fq 'Archive::put(target, msg->m_notifyHealingReceived);' "$work_alter_attribute_message"
grep -Fq 'Archive::get(source, notifyHealingReceived);' "$work_alter_attribute_message"
grep -Fq 'msg->getNotifyHealingReceived()' "$work_creature_controller"
nm -C "$server_game_archive" | grep -Fq 'CreatureObject::healDamage(int, int, NetworkId const&, bool)'
nm -C "$server_game_archive" | grep -Fq 'CreatureObject::alterAttribute(int, int, bool, NetworkId const&, bool, bool)'
nm -C "$server_script_archive" | grep -Fq 'ScriptMethodsAttributesNamespace::healDamage'
nm -C "$server_network_messages_archive" | grep -Fq 'MessageQueueAlterAttribute::MessageQueueAlterAttribute(int, int, bool, NetworkId const&, bool)'
strings "$binary" | grep -Fq '_healDamage'
strings "$binary" | grep -Fq 'OnHealingReceived'
nm -C "$server_game_archive" | grep -Fq 'WeaponObjectNamespace::normalizePrecuAttackSpeed'
nm -C "$server_game_archive" | grep -Fq 'WeaponObject::getAttackTime() const'
nm -C "$server_game_archive" | grep -Fq 'CreatureObject::processExpertiseRequest'
nm -C "$server_game_archive" | grep -Fq 'CreatureObject::clearRetiredNgeProgressionSkills()'
nm -C "$server_game_archive" | grep -Fq 'CreatureObjectNamespace::isRetiredNgeProgressionCommandName'
nm -C "$server_game_archive" | grep -Fq 'CreatureObject::clearRetiredNgeProgressionCommands()'
strings "$binary" | grep -Fq 'Retired %u persisted NGE progression command(s) while loading player %s'
nm -C "$server_game_archive" | grep -Fq 'GroupObject::getSecondsLeftOnGroupPickup() const'
nm -C "$server_game_archive" | grep -Fq 'TangibleObject::startNpcConversation'
nm -C "$server_game_archive" | grep -Fq 'TangibleObject::endNpcConversation()'
nm -C "$server_game_archive" | grep -Fq 'PlayerObject::retirePostNgeGcwRatingState()'
strings "$server_game_archive" | grep -Fq 'recover stale-session player=%s previousNpc=%s requestedNpc=%s'
strings "$server_game_archive" | grep -Fq 'request actor=%s target=%s sequence=%u clientItems=%u'
strings "$server_game_archive" | grep -Fq 'ignored as a retired NGE progression command'
strings "$binary" | grep -Fq '_pvpSetPrecuFactionRank'

# Publish 14.1 player bounties are produced by witnessed exact-title Jedi
# visibility and a canonical skill/rank reward.  The retained later Smuggler
# path is explicitly tagged and carries a separate reward/provenance channel.
awk -F '\t' '
NR == 1 {
    for (column = 1; column <= NF; column++) field[$column] = column
    next
}
NR > 2 {
    found++
    if ($(field["intVisibilityValue"]) != 10 || $(field["intVisibilityRange"]) != 32) exit 2
}
END { if (found != 49) exit 3 }
' "$work_bounty_jedi_actions"
awk -F '\t' '
NR == 1 {
    for (column = 1; column <= NF; column++) field[$column] = column
    next
}
NR > 2 {
    found++
    if ($(field["intVisibilityValue"]) != 25 || $(field["intVisibilityRange"]) != 32) exit 2
}
END { if (found != 59) exit 3 }
' "$work_bounty_jedi_combat_data"
awk -F '\t' '$1 == "combat_bountyhunter_investigation_03" { found++; if ($0 !~ /combat_bountyhunter_investigation_02/ || $0 !~ /droid_track/) exit 2 } END { if (found != 1) exit 3 }' "$work_bounty_skills"

grep -Fq 'JEDI_BOUNTY_TITLE_SKILL = "force_title_jedi_rank_02"' "$work_bounty_jedi"
grep -Fq 'MAX_JEDI_VISIBILITY = 8000' "$work_bounty_jedi"
grep -Fq 'BOUNTY_VISIBILITY_THRESHHOLD = 1500' "$work_bounty_jedi"
grep -Fq 'VISIBILITY_DECAY_TIME_SECONDS = 21 * 24 * 60 * 60' "$work_bounty_jedi"
grep -Fq 'VISIBILITY_DECAY_TICK_SECONDS = 60 * 60' "$work_bounty_jedi"
grep -Fq 'ENEMY_VISIBILITY_MULTIPLIER = 1.0f' "$work_bounty_jedi"
grep -Fq 'NEUTRAL_VISIBILITY_MULTIPLIER = 0.5f' "$work_bounty_jedi"
grep -Fq 'FRIENDLY_VISIBILITY_MULTIPLIER = 0.25f' "$work_bounty_jedi"
test "$(grep -Fc 'jedi.jediActionPerformed(' "$work_bounty_jedi")" -eq 5
test "$(grep -Fc 'jedi.jediActionPerformed(' "$work_bounty_combat_base")" -eq 1
test "$(grep -Fc 'jedi.jediActionPerformed(' "$work_bounty_combat_player")" -eq 1
test "$(grep -Fc 'jedi.jediActionPerformed(' "$work_bounty_jedi_base")" -eq 1
test "$(grep -R -F --include='*.java' 'jedi.jediActionPerformed(' "$work_script" | wc -l)" -eq 8
test "$(grep -R -E --include='*.java' --include='*.tab' --include='*.tpf' 'doJediHealCommand' "$SWG_WORK_DIR/dsrc/sku.0" | wc -l)" -eq 1
! grep -R -E --include='*.java' --include='*.tab' --include='*.tpf' 'systems[./]jedi[./]jedi_base|extends[[:space:]]+([^[:space:]]*[.])?jedi_base' "$SWG_WORK_DIR/dsrc/sku.0"
grep -Fq 'MAX_ACTIVE_PLAYER_BOUNTIES = 5' "$work_bounty_hunter"
grep -Fq 'PLAYER_BOUNTY_PROVENANCE_JEDI = 1' "$work_bounty_hunter"
grep -Fq 'PLAYER_BOUNTY_PROVENANCE_SMUGGLER = 2' "$work_bounty_hunter"
grep -Fq 'PLAYER_BOUNTY_KILL_BUFFER_SECONDS = 30 * 60' "$work_bounty_hunter"
grep -Fq 'PLAYER_BOUNTY_MISSION_COOLDOWN_SECONDS = 24 * 60 * 60' "$work_bounty_hunter"
grep -Fq 'int smugglerReward = targetData.getInt("smugglerBountyValue")' "$work_bounty_hunter"
grep -Fq 'recordPlayerBountyKill(target)' "$work_bounty_hunter"
grep -Fq 'recordPlayerBountyMissionCooldown' "$work_bounty_hunter"
grep -Fq 'getPlayerStationId(existingHunter)' "$work_bounty_hunter"
grep -Fq 'hasCurrentPlayerBountyProvenance(target, provenance)' "$work_bounty_hunter"
grep -Fq 'notifyPlayerBountyMissionsIncomplete(target, provenance)' "$work_bounty_hunter"
grep -Fq 'failInvalidPlayerBountyMission(hunter, target, mission)' "$work_bounty_hunter"
grep -Fq 'xp.grant(hunter, xp.BOUNTYHUNTER, bountyValue / 50)' "$work_bounty_hunter"
grep -Fq 'messageTo(hunter1, "handleBountyMissionIncomplete"' "$work_bounty_hunter"
grep -Fq 'setJediVisibility(target, 0)' "$work_bounty_hunter"
grep -Fq '(long)bountyValue * 2L' "$work_bounty_hunter"
! grep -Fq 'getBountyFactionPointAdjustment' "$work_bounty_hunter"
! grep -Fq 'pvp.getCurrentPvPRating' "$work_bounty_hunter"
grep -Fq 'removeAllJediBounties(target)' "$work_bounty_hunter"
grep -Fq 'obj_id mission = getBountyMission(hunter, target)' "$work_bounty_hunter"
grep -Fq 'requestJedi(jedi.BOUNTY_VISIBILITY_THRESHHOLD' "$work_bounty_mission_dynamic"
grep -Fq 'IGNORE_JEDI_STAT, -5, bounty_hunter.PLAYER_BOUNTY_JEDI_STATE_MASK' "$work_bounty_mission_dynamic"
grep -Fq 'IGNORE_JEDI_STAT, -5,' "$work_bounty_mission_dynamic"
grep -Fq 'getIntArray("smugglerBountyValue")' "$work_bounty_mission_dynamic"
grep -Fq 'getIntArray(bounty_hunter.DATA_PLAYER_BOUNTY_KILL_BUFFER_UNTIL)' "$work_bounty_mission_dynamic"
grep -Fq 'bounty_hunter.isPlayerBountyMissionCooldownActive' "$work_bounty_mission_dynamic"
grep -Fq 'bounty_hunter.hasPlayerBountyAccountConflict' "$work_bounty_mission_dynamic"
grep -Fq 'PLAYER_BOUNTY_PROVENANCE_SMUGGLER' "$work_bounty_mission_dynamic"
grep -Fq 'PLAYER_BOUNTY_PROVENANCE_JEDI' "$work_bounty_mission_dynamic"
test "$(grep -Fc 'rand(0, SamePlanetCounter - 1)' "$work_bounty_mission_dynamic")" -eq 2
! grep -Fq 'SamePlanetObjId.length - 1' "$work_bounty_mission_dynamic"
! grep -Fq 'requestJedi(IGNORE_JEDI_STAT, 15000' "$work_bounty_mission_dynamic"
! grep -Fq 'IGNORE_JEDI_STAT, -3)' "$work_bounty_mission_dynamic"
grep -Fq 'bounty_hunter.isValidPlayerBountyTarget(self, target, provenance)' "$work_bounty_mission_player"
grep -Fq 'bounty_hunter.isValidPlayerBountyTarget(self, target, provenance, true)' "$work_bounty_mission_player"
grep -Fq 'if (!requestJediBounty(target, self,' "$work_bounty_mission_player"
grep -Fq 'utils.hasScriptVar(self, "bounty_hunter.jedi_mission")' "$work_bounty_mission_player"
grep -Fq 'params.getObjId("jedi")' "$work_bounty_mission_player"
grep -Fq 'confirmedTarget != target' "$work_bounty_mission_player"
grep -Fq 'createDynamicBountyMission' "$work_bounty_mission_player"
grep -Fq 'setObjVar(jedi_mission, bounty_hunter.VAR_PLAYER_BOUNTY_ASSIGNMENT_ACCEPTED, 1)' "$work_bounty_mission_player"
grep -Fq 'bounty_hunter.recordPlayerBountyMissionCooldown' "$work_bounty_mission_player"
grep -Fq 'bounty_hunter.VAR_PLAYER_BOUNTY_ASSIGNMENT_ACCEPTED' "$work_bounty_mission_bounty"
grep -Fq 'bounty_hunter.recordPlayerBountyMissionCooldown' "$work_bounty_mission_bounty"
confirmed_bounty_assignment_source="$(sed -n '/public int msgJediMissionStartConfirmed(/,/public int msgJediMissionStartFailed(/p' "$work_bounty_mission_player")"
test "$(printf '%s\n' "$confirmed_bounty_assignment_source" | grep -Fc 'clearPlayerBountyPersonalEnemyFlags')" -eq 3
test "$(printf '%s\n' "$confirmed_bounty_assignment_source" | grep -Fc 'removeJediBounty')" -eq 3
grep -Fq 'migrateLegacySmugglerBounty(self);' "$work_bounty_base_player"
grep -Fq 'groundquests.isQuestActive(self, "quest/smuggle_pvp_4")' "$work_bounty_base_player"
grep -Fq 'groundquests.isQuestActive(self, "quest/smuggle_pvp_5")' "$work_bounty_base_player"
grep -Fq 'questMaximum = tierFiveActive ? 22000 : 17000' "$work_bounty_base_player"
grep -Fq 'updateJediScriptData(self, "smugglerBountyValue", smugglerBounty)' "$work_bounty_base_player"
grep -Fq 'bounty_hunter.notifyPlayerBountyMissionsIncomplete(self,' "$work_bounty_base_player"
migration_line="$(grep -Fn 'migrateLegacySmugglerBounty(self);' "$work_bounty_base_player" | head -1 | cut -d: -f1)"
aggregate_purge_line="$(grep -Fn 'removeObjVar(self, "bounty.amount");' "$work_bounty_base_player" | head -1 | cut -d: -f1)"
test "$migration_line" -lt "$aggregate_purge_line"
for bounty_broker in "$work_bounty_broker_4" "$work_bounty_broker_5"; do
    grep -Fq 'setObjVar(player, "smuggler.bounty", mission_bounty)' "$bounty_broker"
    grep -Fq 'updateJediScriptData(player, "smuggler", 1)' "$bounty_broker"
    grep -Fq 'updateJediScriptData(player, "smugglerBountyValue", mission_bounty)' "$bounty_broker"
    ! grep -Fq 'bounty.amount' "$bounty_broker"
done
grep -Fq 'updateJediScriptData(self, "smugglerBountyValue", 0)' "$work_bounty_smuggler"
grep -Fq 'PLAYER_BOUNTY_PROVENANCE_SMUGGLER' "$work_bounty_smuggler"
grep -Fq 'bounty_hunter.notifyPlayerBountyMissionsIncomplete' "$work_bounty_smuggler"
! grep -Fq 'removeAllJediBounties' "$work_bounty_smuggler"
! grep -Fq 'bounty.amount' "$work_bounty_smuggler"
grep -Fq 'getIntObjVar(mission, bounty_hunter.VAR_PLAYER_BOUNTY_PROVENANCE) != provenance' "$work_bounty_base_player"
player_bounty_callback_source="$(sed -n '/public int handleAwardedPlayerBounty(/,/public int handleSurveyToolbarSetup(/p' "$work_bounty_base_player")"
! printf '%s\n' "$player_bounty_callback_source" | grep -Eq 'xp\.grant|grantCombatFaction|incrementGCWStanding|pvpModifyCurrentGcwPoints'
grep -Fq 'dictionary bountyData = requestJedi(infoTarget)' "$work_bounty_combat_actions"
grep -Fq 'bountyData.getInt("bountyValue")' "$work_bounty_combat_actions"
! grep -Fq 'getIntObjVar(infoTarget, "bounty.amount")' "$work_bounty_combat_actions"
! grep -R -Eq --include='*.java' 'setObjVar\([^;]*"bounty\.amount"' "$work_script"
! grep -R -Fq --include='*.java' 'pvp.incrementPlayerDeathBounty(' "$work_script"
! grep -R -Fq --include='*.java' 'bounty_hunter.showSetBountySUI(' "$work_script"

for bounty_class in \
    script/library/jedi.class \
    script/library/bounty_hunter.class \
    script/library/pclib.class \
    script/library/pvp.class \
    script/library/smuggler.class \
    script/library/force_rank.class \
    script/systems/gcw/player_force_rank.class \
    script/player/base/base_player.class \
    script/systems/combat/combat_base.class \
    script/systems/combat/combat_player.class \
    script/systems/combat/combat_actions.class \
    script/systems/jedi/jedi_base.class \
    script/systems/missions/base/mission_dynamic_base.class \
    script/systems/missions/base/mission_player.class \
    script/systems/missions/dynamic/mission_bounty.class \
    script/conversation/generic_broker_4.class \
    script/conversation/generic_broker_5.class
do
    test -f "$class_root/$bounty_class"
done
weapon_base_player_bytecode="$(javap -classpath "$class_root" -c -p script.player.base.base_player)"
weapon_base_player_initialize_bytecode="$(printf '%s\n' "$weapon_base_player_bytecode" | awk '
/^  public int OnInitialize\(/ { capture = 1; print; next }
capture && /^  (public|private|protected)/ { exit }
capture { print }
')"
printf '%s\n' "$weapon_base_player_initialize_bytecode" | grep -Fq 'object/weapon/melee/unarmed/unarmed_default_player.iff'
! printf '%s\n' "$weapon_base_player_initialize_bytecode" | grep -Fq 'getWeaponAttackSpeed'
! printf '%s\n' "$weapon_base_player_initialize_bytecode" | grep -Fq 'setWeaponAttackSpeed'
test -f "$class_root/datatables/jedi/jedi_actions.iff"
test -f "$class_root/datatables/jedi/jedi_combat_data.iff"
bounty_jedi_constants="$(javap -classpath "$class_root" -constants -p script.library.jedi)"
printf '%s\n' "$bounty_jedi_constants" | grep -Fq 'JEDI_BOUNTY_TITLE_SKILL = "force_title_jedi_rank_02"'
printf '%s\n' "$bounty_jedi_constants" | grep -Fq 'MAX_JEDI_VISIBILITY = 8000'
printf '%s\n' "$bounty_jedi_constants" | grep -Fq 'BOUNTY_VISIBILITY_THRESHHOLD = 1500'
printf '%s\n' "$bounty_jedi_constants" | grep -Fq 'VISIBILITY_DECAY_TIME_SECONDS = 1814400'
printf '%s\n' "$bounty_jedi_constants" | grep -Fq 'VISIBILITY_DECAY_TICK_SECONDS = 3600'
printf '%s\n' "$bounty_jedi_constants" | grep -Fq 'NONCOMBAT_VISIBILITY = 10'
printf '%s\n' "$bounty_jedi_constants" | grep -Fq 'COMBAT_VISIBILITY = 25'
printf '%s\n' "$bounty_jedi_constants" | grep -Fq 'SABER_EQUIP_VISIBILITY = 10'
bounty_jedi_bytecode="$(javap -classpath "$class_root" -c -p script.library.jedi)"
printf '%s\n' "$bounty_jedi_bytecode" | grep -Fq 'hasPlayerBountyJediProvenance'
printf '%s\n' "$bounty_jedi_bytecode" | grep -Fq 'getJediActionVisibilityValue'
printf '%s\n' "$bounty_jedi_bytecode" | grep -Fq 'decayJediVisibility'
bounty_hunter_constants="$(javap -classpath "$class_root" -constants -p script.library.bounty_hunter)"
printf '%s\n' "$bounty_hunter_constants" | grep -Fq 'MAX_ACTIVE_PLAYER_BOUNTIES = 5'
printf '%s\n' "$bounty_hunter_constants" | grep -Fq 'PLAYER_BOUNTY_PROVENANCE_JEDI = 1'
printf '%s\n' "$bounty_hunter_constants" | grep -Fq 'PLAYER_BOUNTY_PROVENANCE_SMUGGLER = 2'
printf '%s\n' "$bounty_hunter_constants" | grep -Fq 'PLAYER_BOUNTY_KILL_BUFFER_SECONDS = 1800'
printf '%s\n' "$bounty_hunter_constants" | grep -Fq 'PLAYER_BOUNTY_MISSION_COOLDOWN_SECONDS = 86400'
bounty_hunter_bytecode="$(javap -classpath "$class_root" -c -p script.library.bounty_hunter)"
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'isValidPlayerBountyTarget'
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'applyJediBountyExperienceLoss'
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'recordPlayerBountyKill'
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'recordPlayerBountyMissionCooldown'
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'hasPlayerBountyAccountConflict'
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'hasCurrentPlayerBountyProvenance'
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'notifyPlayerBountyMissionsIncomplete'
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'failInvalidPlayerBountyMission'
printf '%s\n' "$bounty_hunter_bytecode" | grep -Fq 'script/library/xp.grant'
! javap -classpath "$class_root" -v script.library.bounty_hunter | grep -Fq 'getBountyFactionPointAdjustment'
! javap -classpath "$class_root" -v script.library.bounty_hunter | grep -Fq 'bounty.amount'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'smugglerBountyValue'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'quest/smuggle_pvp_4'
javap -classpath "$class_root" -v script.player.base.base_player | grep -Fq 'quest/smuggle_pvp_5'
javap -classpath "$class_root" -v script.systems.missions.base.mission_dynamic_base | grep -Fq 'bounty.precuProvenance'
javap -classpath "$class_root" -v script.systems.missions.base.mission_dynamic_base | grep -Fq 'smugglerBountyValue'
javap -classpath "$class_root" -v script.systems.missions.base.mission_dynamic_base | grep -Fq 'precuBountyKillBufferUntil'
javap -classpath "$class_root" -v script.systems.missions.base.mission_dynamic_base | grep -Fq 'isPlayerBountyMissionCooldownActive'
javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'isValidPlayerBountyTarget'
javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'bounty.precuAssignmentAccepted'
javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'bounty_hunter.jedi_mission'
javap -classpath "$class_root" -v script.systems.missions.base.mission_player | grep -Fq 'recordPlayerBountyMissionCooldown'
javap -classpath "$class_root" -v script.systems.missions.dynamic.mission_bounty | grep -Fq 'bounty.precuAssignmentAccepted'
javap -classpath "$class_root" -v script.systems.missions.dynamic.mission_bounty | grep -Fq 'recordPlayerBountyMissionCooldown'
javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'requestJedi'
! javap -classpath "$class_root" -v script.systems.combat.combat_actions | grep -Fq 'bounty.amount'
javap -classpath "$class_root" -v script.systems.jedi.jedi_base | grep -Fq 'doJediHealCommand'
javap -classpath "$class_root" -v script.systems.jedi.jedi_base | grep -Fq 'jediActionPerformed'

grep -Fq 'ms_skillPointCostLabel               = "POINTS_REQUIRED"' "$work_bounty_skill_object"
grep -Fq 'int SkillObject::getSkillPointCost() const' "$work_bounty_skill_object"
grep -Fq 'findColumnNumber(SkillObject::ms_skillPointCostLabel)' "$work_bounty_skill_object"
grep -Fq 'skillData.skillPointCost = dataTable.getIntValue' "$work_bounty_skill_object"
grep -Fq 'getSkillPointCost' "$work_bounty_skill_object_header"
grep -Fq 'cms_jediTitleSkill = "force_title_jedi_rank_02"' "$work_bounty_swg_creature"
grep -Fq 'cms_jediDisciplinePrefix = "force_discipline"' "$work_bounty_swg_creature"
grep -Fq 'cms_forceRankObjvar = "force_rank.rank"' "$work_bounty_swg_creature"
grep -Fq 'cms_forceRankCouncilObjvar = "force_rank.council"' "$work_bounty_swg_creature"
grep -Fq 'forceRank >= 0 && forceRank <= 11' "$work_bounty_swg_creature"
grep -Fq 'forceRankCouncil == 1 || forceRankCouncil == 2' "$work_bounty_swg_creature"
grep -Fq 'return JS_jedi;' "$work_bounty_swg_creature"
grep -Fq 'getSpentJediSkillPoints()) * 1000LL' "$work_bounty_swg_creature"
grep -Fq 'static_cast<long long>(forceRank) * 100000LL' "$work_bounty_swg_creature"
grep -Fq 'std::max(25000LL' "$work_bounty_swg_creature"
grep -Fq 'std::max(50000LL' "$work_bounty_swg_creature"
grep -Fq 'titleJedi ? getBountyValue() : smugglerBounty' "$work_bounty_swg_creature"
grep -Fq 'cms_smugglerBountyScriptData, smugglerBounty' "$work_bounty_swg_creature"
grep -Fq 'affectsPreCuJediRegistry(newSkill.getSkillName())' "$work_bounty_swg_creature"
grep -Fq 'affectsPreCuJediRegistry(oldSkill.getSkillName())' "$work_bounty_swg_creature"
grep -Fq 'synchronizeJediBountyRegistry' "$work_bounty_swg_creature_header"
grep -Fq 'owner->synchronizeJediBountyRegistry();' "$work_bounty_swg_player"
grep -Fq 'visibility > 8000' "$work_bounty_swg_player"
grep -Fq 'cms_minimumJediBountyVisibility = 1500' "$work_bounty_jedi_manager"
grep -Fq 'cms_maximumActiveHunters = 5' "$work_bounty_jedi_manager"
grep -Fq 'getSmugglerBountyValue' "$work_bounty_jedi_manager"
grep -Fq 'cms_smugglerBountyValueScriptData' "$work_bounty_jedi_manager"
grep -Fq 'isAvailableBountyTarget(index)' "$work_bounty_jedi_manager"
grep -Fq 'hunterStationId == targetStationId' "$work_bounty_jedi_manager"
grep -Fq 'getSmugglerBountyValue' "$work_bounty_jedi_manager_header"
grep -Fq 'jediCreature->synchronizeJediBountyRegistry();' "$work_bounty_script_methods_jedi"
! grep -Fq 'bounty.amount' "$work_bounty_swg_creature"
! grep -Fq 'bounty.amount' "$work_bounty_jedi_manager"
! grep -Fq 'bounty.amount' "$work_bounty_script_methods_jedi"

test -f "$shared_skill_system_archive"
nm -C "$shared_skill_system_archive" | grep -Fq 'SkillObject::getSkillPointCost() const'
nm -C "$server_script_archive" | grep -Fq 'ScriptMethodsJediNamespace::setJediBountyValue'
nm -C "$server_script_archive" | grep -Fq 'ScriptMethodsJediNamespace::requestJediBounty'
nm -C "$binary" | grep -Fq 'SwgCreatureObject::synchronizeJediBountyRegistry()'
nm -C "$binary" | grep -Fq 'SwgCreatureObject::getBountyValue() const'
nm -C "$binary" | grep -Fq 'SwgCreatureObject::grantSkill(SkillObject const&)'
nm -C "$binary" | grep -Fq 'SwgCreatureObject::revokeSkill(SkillObject const&, bool)'
nm -C "$binary" | grep -Fq 'SkillObject::getSkillPointCost() const'
nm -C "$binary" | grep -Fq 'SwgPlayerObject::setJediVisibility(int)'
nm -C "$binary" | grep -Fq 'SwgPlayerObject::setJediState(JediState)'
nm -C "$binary" | grep -Fq 'SwgPlayerObject::virtualOnSetAuthority()'
nm -C "$binary" | grep -Fq 'JediManagerObject::getSmugglerBountyValue(int) const'
nm -C "$binary" | grep -Fq 'JediManagerObject::isAvailableBountyTarget(int) const'
strings "$binary" | grep -Fq 'force_title_jedi_rank_02'
strings "$binary" | grep -Fq 'force_rank.council'
strings "$binary" | grep -Fq 'smugglerBountyValue'
strings "$binary" | grep -Fq 'POINTS_REQUIRED'
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
grep -Fxq 'enableFRS=1' "$cfg"
grep -Fxq 'enableCovertImperialMercenary=false' "$cfg"
grep -Fxq 'enableOvertImperialMercenary=false' "$cfg"
grep -Fxq 'enableCovertRebelMercenary=false' "$cfg"
grep -Fxq 'enableOvertRebelMercenary=false' "$cfg"
grep -Eq '^transferServerAddress=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$cfg"
grep -Fxq 'transferServerPort=50005' "$cfg"
grep -Fxq 'centralServerServiceBindPort=50005' "$cfg"
grep -Fq '### BEGIN Docker runtime overrides' "$cfg"
'@
Write-Host "Verifying the restarted server rendered its runtime configuration..."
Invoke-DockerScript -ContainerName $Container -Script $runtimeConfigProbe

$runtimeTransferServerProbe = @'
set -eu
transfer_pid=""
transfer_listener=""
for attempt in $(seq 1 30); do
    transfer_pid="$(pgrep -xo TransferServer || true)"
    transfer_listener="$(ss -H -ltnp 'sport = :50005' 2>/dev/null || true)"
    if [ -n "$transfer_pid" ] &&
       [ "$(pgrep -xc TransferServer || true)" -eq 1 ] &&
       [ "$(printf '%s\n' "$transfer_listener" | sed '/^$/d' | wc -l)" -eq 1 ] &&
       printf '%s\n' "$transfer_listener" | grep -Fq 'TransferServer' &&
       printf '%s\n' "$transfer_listener" | grep -Fq "pid=$transfer_pid,"; then
        break
    fi
    sleep 1
done
test -n "$transfer_pid"
test "$(pgrep -xc TransferServer)" -eq 1
test "$(printf '%s\n' "$transfer_listener" | sed '/^$/d' | wc -l)" -eq 1
printf '%s\n' "$transfer_listener" | grep -Fq 'TransferServer'
printf '%s\n' "$transfer_listener" | grep -Fq "pid=$transfer_pid,"
sleep 3
test "$(pgrep -xo TransferServer)" = "$transfer_pid"
transfer_listener="$(ss -H -ltnp 'sport = :50005')"
test "$(printf '%s\n' "$transfer_listener" | sed '/^$/d' | wc -l)" -eq 1
printf '%s\n' "$transfer_listener" | grep -Fq 'TransferServer'
printf '%s\n' "$transfer_listener" | grep -Fq "pid=$transfer_pid,"
'@
Write-Host "Verifying one stable TransferServer owns native port 50005..."
Invoke-DockerScript -ContainerName $Container -Script $runtimeTransferServerProbe

Write-Host "Verifying every live game process mapped the newly built server binary..."
$gamePids = @(& docker exec $Container pgrep -f "bin/SwgGameServer")
if ($LASTEXITCODE -ne 0 -or $gamePids.Count -eq 0)
{
    throw "No live SwgGameServer process was found in '$Container'."
}
$workDir = (& docker exec $Container printenv SWG_WORK_DIR).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($workDir))
{
    throw "Unable to resolve SWG_WORK_DIR in '$Container'."
}
$binaryInode = (& docker exec $Container stat -Lc "%i" "$workDir/build/bin/SwgGameServer").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($binaryInode))
{
    throw "Unable to authenticate the newly built SwgGameServer inode."
}
$binarySize = (& docker exec $Container stat -Lc "%s" "$workDir/build/bin/SwgGameServer").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($binarySize))
{
    throw "Unable to authenticate the newly built SwgGameServer size."
}
foreach ($gamePidValue in $gamePids)
{
    $gamePid = ([string]$gamePidValue).Trim()
    if ([string]::IsNullOrWhiteSpace($gamePid))
    {
        throw "The live SwgGameServer process inventory contained an empty PID."
    }
    $processInode = (& docker exec $Container stat -Lc "%i" "/proc/$gamePid/exe").Trim()
    if ($LASTEXITCODE -ne 0)
    {
        throw "Unable to authenticate live SwgGameServer process $gamePid."
    }
    $processSize = (& docker exec $Container stat -Lc "%s" "/proc/$gamePid/exe").Trim()
    if ($LASTEXITCODE -ne 0 -or $processInode -cne $binaryInode -or $processSize -cne $binarySize)
    {
        throw "Live SwgGameServer process $gamePid does not map the newly built binary."
    }
}
Write-Host "Verified $($gamePids.Count) live SwgGameServer process(es) against the newly built binary."
Write-Host "PRE-CU server deployment passed: synchronized, x64, healthy, and ready for players."
