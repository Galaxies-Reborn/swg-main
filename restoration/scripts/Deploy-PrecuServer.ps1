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
source_queue="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/command/CommandQueue.cpp"
work_queue="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/command/CommandQueue.cpp"
source_queue_header="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/command/CommandQueue.h"
work_queue_header="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/command/CommandQueue.h"
source_commands="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.cpp"
work_commands="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.cpp"
source_client="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/core/Client.cpp"
work_client="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/core/Client.cpp"
source_creature="$SWG_SOURCE_DIR/src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
work_creature="$SWG_WORK_DIR/src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
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
cmp -s "$source_queue" "$work_queue"
cmp -s "$source_queue_header" "$work_queue_header"
cmp -s "$source_commands" "$work_commands"
cmp -s "$source_client" "$work_client"
cmp -s "$source_creature" "$work_creature"
cmp -s "$source_group" "$work_group"
cmp -s "$source_player" "$work_player"
cmp -s "$source_weapon" "$work_weapon"
cmp -s "$source_weapon_header" "$work_weapon_header"
cmp -s "$source_speeds" "$work_speeds"
cmp -s "$source_travel" "$work_travel"
cmp -s "$source_player_travel" "$work_player_travel"
cmp -s "$source_command_table" "$work_command_table"
cmp -s "$source_skills" "$work_skills"
javap -classpath "$class_root" -c script.player.skill.outdoorsman | grep -Fq 'corpse.canPlayerHarvestCreature'
javap -classpath "$class_root" -c script.library.corpse | grep -Fq 'String outdoors_scout_novice'
javap -classpath "$class_root" -c script.library.corpse | grep -Fq 'Method canPlayerHarvestCreature'
javap -classpath "$class_root" -v script.library.corpse | grep -Fq 'Rejected creature resource extraction without Novice Scout'
javap -classpath "$class_root" -v script.library.create | grep -Fq 'datatables/mob/precu_creature_combat_profiles.iff'
javap -classpath "$class_root" -v script.library.create | grep -Fq 'precu.combatProfile'
javap -classpath "$class_root" -v script.library.loot | grep -Fq 'Rejected NGE creature-resource loot injection'
javap -classpath "$class_root" -c script.systems.crafting.droid.modules.harvest_module | grep -Fq 'corpse.canPlayerHarvestCreature'
javap -classpath "$class_root" -c script.library.travel | grep -Fq 'rejected retired NGE group-pickup travel'
javap -classpath "$class_root" -v script.player.player_travel | grep -Fq 'Ignored retired NGE group-pickup travel request'
grep -Fq 'calculatePrecuAttackTime' "$work_queue"
grep -Fq 'isWeaponCadenceAttack' "$work_queue"
grep -Fq 'if (!owner.isPlayerControlled())' "$work_queue"
grep -Fq 'PreCuCombatCadence' "$work_queue"
grep -Fq 'm_lastWeaponCadenceAttackTime' "$work_queue_header"
grep -Fq 'm_lastWeaponCadenceInterval' "$work_queue_header"
grep -Fq 'm_lastWeaponCadenceAttackTime = s_currentTime' "$work_queue"
grep -Fq 'm_nextEventTime = earliestAttackTime' "$work_queue"
grep -Fq 'gate time=' "$work_queue"
grep -Fq 'logs/precuCombatCadence.log{c-*:c+PreCuCombatCadence}' "$work_local_options"
grep -Fq 'Ignored retired NGE ExpertiseRequestMessage' "$work_client"
! grep -Fq 'ExpertiseRequestMessage const m' "$work_client"
grep -Fq 'isRetiredNgeProgressionSkillName' "$work_creature"
grep -Fq 'Rejected retired NGE expertise request' "$work_creature"
grep -Fq 'Ignored retired NGE createGroupPickup command' "$work_commands"
grep -Fq 'Ignored retired NGE useGroupPickup command' "$work_commands"
grep -Fq 'return 0;' "$work_group"
grep -Fq 'reuseableWp.groupPickupWp' "$work_player"
grep -Fq 'normalizePrecuAttackSpeed' "$work_weapon"
grep -Fq 'getStoredAttackTime' "$work_weapon_header"
awk -F '	' '$1 ~ /^harvestCorpse$/ { found=1; if ($9 !~ /^harvestCorpse$/) exit 2 } END { if (!found) exit 3 }' "$work_command_table"
awk -F '	' '$1 ~ /^species_(bothan|human|moncal|rodian|trandoshan|twilek|wookiee|zabrak|ithorian|sullustan)$/ { found++; if ($23 ~ /creature_harvesting/) exit 2 } END { if (found != 10) exit 3 }' "$work_skills"
awk -F '	' '$1 ~ /^outdoors_scout_novice$/ { found=1; if ($22 !~ /harvestCorpse/ || $23 !~ /creature_harvesting=15/) exit 2 } END { if (!found) exit 3 }' "$work_skills"
awk -F '	' '$1 ~ /^kreetle$/ { found=1; if ($3 != 3 || $5 != 35 || $6 != 45 || $8 != 90 || $9 != 110) exit 2 } END { if (!found) exit 3 }' "$work_creature_profiles"
awk -F '	' '$1 ~ /^lesser_desert_womprat$/ { found=1; if ($2 !~ /^lesser_desert_womp_rat$/ || $3 != 5 || $5 != 45 || $6 != 50) exit 2 } END { if (!found) exit 3 }' "$work_creature_profiles"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_speeds.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/skill/skills.iff"
test -f "$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/datatables/mob/precu_creature_combat_profiles.iff"
nm -C "$server_game_archive" | grep -Fq 'WeaponObjectNamespace::normalizePrecuAttackSpeed'
nm -C "$server_game_archive" | grep -Fq 'WeaponObject::getAttackTime() const'
nm -C "$server_game_archive" | grep -Fq 'CreatureObject::processExpertiseRequest'
nm -C "$server_game_archive" | grep -Fq 'GroupObject::getSecondsLeftOnGroupPickup() const'
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
