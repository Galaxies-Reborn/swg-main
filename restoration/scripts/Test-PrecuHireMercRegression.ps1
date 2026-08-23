[CmdletBinding()]
param(
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceRoot))
{
    $SourceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Assert-True([bool]$Condition, [string]$Message)
{
    if (-not $Condition)
    {
        throw $Message
    }
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message)
{
    Assert-True ([regex]::IsMatch(
        $Text,
        $Pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline)) $Message
}

function Read-Text([string]$Path)
{
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing $Path"
    return [IO.File]::ReadAllText($Path)
}

$dsrc = Join-Path $SourceRoot "dsrc"
$serverGame = Join-Path $dsrc "sku.0/sys.server/compiled/game"
$mercPath = Join-Path $serverGame "script/library/mercenary.java"
$paymentPath = Join-Path $serverGame `
    "script/player/mercenary_hire_payment.java"
$terminalScriptPath = Join-Path $serverGame `
    "script/systems/missions/base/hire_merc_terminal.java"
$aiPath = Join-Path $serverGame "script/ai/mercenary_party_member.java"
$tpfRelative = "sku.0/sys.server/compiled/game/object/tangible/terminal/terminal_mission.tpf"
$tpfPath = Join-Path $dsrc $tpfRelative
$missionTerminalPath = Join-Path $serverGame `
    "script/systems/missions/base/mission_terminal.java"
$missionBasePath = Join-Path $serverGame `
    "script/systems/missions/base/mission_base.java"
$groupPath = Join-Path $serverGame "script/library/group.java"
$combatDataPath = Join-Path $dsrc `
    "sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$creaturesRelative = `
    "sku.0/sys.server/compiled/game/datatables/mob/creatures.tab"
$creaturesPath = Join-Path $serverGame "datatables/mob/creatures.tab"
$generator = Join-Path $SourceRoot `
    "restoration/scripts/New-PrecuHireMercStringTable.ps1"
$stfPath = Join-Path $SourceRoot `
    "serverdata/string/en/precu_hire_merc.stf"

$merc = Read-Text $mercPath
$payment = Read-Text $paymentPath
$terminal = Read-Text $terminalScriptPath
$ai = Read-Text $aiPath
$missionBase = Read-Text $missionBasePath
$groupSource = Read-Text $groupPath
$generatorSource = Read-Text $generator

# Terminal exposure is additive, localized, and fail-closed.
$tpf = Read-Text $tpfPath
Assert-Match $tpf `
    'scripts\s*=\s*\+\["systems\.missions\.base\.mission_terminal","systems\.missions\.base\.hire_merc_terminal","planet_map\.map_loc"\]' `
    "Mission terminal template does not attach the dedicated merc script."
Assert-Match $terminal 'SERVER_MENU1,\s*mercenary\.SID_HIRE' `
    "Hire a Merc is not exposed on SERVER_MENU1."
Assert-Match $terminal 'utils\.packStringId\(mercenary\.SID_TITLE\)' `
    "The roster title is not localized."
Assert-Match $terminal 'stock mission browser''s tabs are client-authored' `
    "The native-tab engine boundary is no longer documented in code."
foreach ($role in @("intArtisan", "intScout", "intEntertainer", "intBounty", "intNewbie"))
{
    Assert-True ($merc.Contains("hasObjVar(terminal, `"$role`")")) `
        "Combat-terminal filter no longer excludes $role."
}
foreach ($template in @(
    "terminal_mission.iff",
    "terminal_mission_imperial.iff",
    "terminal_mission_rebel.iff"))
{
    Assert-True ($merc.Contains($template)) `
        "Combat-terminal allow-list is missing $template."
}
Assert-Match $merc `
    'MAX_PARTY_MEMBERS\s*=\s*squad_leader\.MAX_GROUP_SIZE;' `
    "Merc hiring must honor the native twenty-member group capacity."

$missionTerminalDiff = & git -C $dsrc diff --name-only -- `
    "sku.0/sys.server/compiled/game/script/systems/missions/base/mission_terminal.java"
Assert-True ([string]::IsNullOrWhiteSpace(($missionTerminalDiff -join ""))) `
    "mission_terminal.java must remain untouched."
$tpfNumstat = (& git -C $dsrc diff --numstat -- $tpfRelative) -join "`n"
Assert-Match $tpfNumstat '^1\s+1\s+' `
    "terminal_mission.tpf must retain a semantic one-line diff."
[byte[]]$tpfBytes = [IO.File]::ReadAllBytes($tpfPath)
Assert-True ($tpfBytes.Length -gt 2 -and
    $tpfBytes[$tpfBytes.Length - 1] -ne 10 -and
    $tpfBytes[$tpfBytes.Length - 1] -ne 13) `
    "terminal_mission.tpf must retain its no-final-newline form."
$tpfText = [Text.Encoding]::UTF8.GetString($tpfBytes)
$withoutCrlf = $tpfText.Replace("`r`n", "")
Assert-True (-not $withoutCrlf.Contains("`r") -and
    -not $withoutCrlf.Contains("`n")) `
    "terminal_mission.tpf must retain legacy CRLF line endings."

# Every ground combat/support family is visible and array-aligned.
$expectedKeys = @(
    "novice_brawler", "novice_marksman", "novice_medic", "bounty_hunter",
    "carbineer", "combat_medic", "commando", "creature_handler", "doctor",
    "fencer", "pikeman", "pistoleer", "rifleman", "ranger", "smuggler",
    "squad_leader", "swordsman", "teras_kasi_artist")
$archMatch = [regex]::Match(
    $merc,
    'ARCHETYPE_KEYS\s*=\s*\{(?<body>.*?)\};',
    [Text.RegularExpressions.RegexOptions]::Singleline)
Assert-True $archMatch.Success "Could not parse mercenary archetype roster."
$actualKeys = @([regex]::Matches($archMatch.Groups["body"].Value, '"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-True (($actualKeys -join "|") -ceq ($expectedKeys -join "|")) `
    "Mercenary roster is missing, reordered, or includes a noncombat family."
foreach ($forbidden in @("artisan", "crafter", "entertainer", "musician", "dancer", "pilot", "shipwright"))
{
    Assert-True ($actualKeys -cnotcontains $forbidden) `
        "Roster includes forbidden family $forbidden."
}
$creatureBlock = [regex]::Match(
    $merc,
    'CREATURE_TYPES\s*=\s*\{(?<body>.*?)\};',
    [Text.RegularExpressions.RegexOptions]::Singleline).Groups["body"].Value
Assert-True ([regex]::Matches($creatureBlock, '"([^"]+)"').Count -eq
    $expectedKeys.Count) "Creature mapping is not roster-aligned."
$abilityBlock = [regex]::Match(
    $merc,
    'COMBAT_ABILITIES\s*=\s*\{(?<body>.*?)\};\s*// 0 =',
    [Text.RegularExpressions.RegexOptions]::Singleline).Groups["body"].Value
Assert-True ([regex]::Matches($abilityBlock, '\{[^{}]+\}').Count -eq
    $expectedKeys.Count) "Ability mapping is not roster-aligned."
$creatureNames = @([regex]::Matches($creatureBlock, '"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-True ($creatureNames -ccontains "precu_hire_merc_swordsman") `
    "Swordsman no longer uses its dedicated neutral creature row."
Assert-True ($creatureNames -cnotcontains "heroic_exar_wordbearer") `
    "Swordsman must not inherit the heroic boss profile."
$abilityRows = @([regex]::Matches($abilityBlock, '\{(?<row>[^{}]+)\}') |
    ForEach-Object {
        ,@([regex]::Matches($_.Groups["row"].Value, '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value })
    })
$expectedWeaponTypes = @(
    "UNARMED", "RIFLE", "PISTOL", "CARBINE", "CARBINE", "PISTOL",
    "CARBINE", "CARBINE", "PISTOL", "1HAND_MELEE", "POLEARM", "PISTOL",
    "RIFLE", "CARBINE", "PISTOL", "RIFLE", "2HAND_MELEE", "UNARMED")

$combatRows = Import-Csv -LiteralPath $combatDataPath -Delimiter "`t"
$weaponByAction = @{}
foreach ($row in $combatRows)
{
    if (-not [string]::IsNullOrWhiteSpace($row.actionName))
    {
        $weaponByAction[$row.actionName] = $row.weaponType
    }
}
$creatureRows = Import-Csv -LiteralPath $creaturesPath -Delimiter "`t"
$swordsmanRows = @($creatureRows | Where-Object {
    $_.creatureName -ceq "precu_hire_merc_swordsman"
})
Assert-True ($swordsmanRows.Count -eq 1) `
    "Dedicated neutral Swordsman row is missing or duplicated."
$swordsmanRow = $swordsmanRows[0]
Assert-True ($swordsmanRow.difficultyClass -ceq "NORMAL") `
    "Swordsman source must retain NORMAL difficulty."
foreach ($immunity in @(
    "rootImmune", "snareImmune", "stunImmune", "mezImmune", "tauntImmune"))
{
    Assert-True ($swordsmanRow.$immunity -ceq "0") `
        "Swordsman source must not inherit $immunity."
}
Assert-True ($swordsmanRow.primary_weapon_specials -ceq "none" -and
    $swordsmanRow.secondary_weapon_specials -ceq "none" -and
    $swordsmanRow.death_blow -ceq "no" -and
    $swordsmanRow.stealingFlags -ceq "NOTHING") `
    "Swordsman source must not expose boss specials, death blows, or theft."
$creaturesNumstat = (& git -C $dsrc diff --numstat -- $creaturesRelative) -join "`n"
Assert-Match $creaturesNumstat '^1\s+0\s+' `
    "creatures.tab must retain an exact one-row insertion diff."
$primaryByCreature = @{}
foreach ($row in $creatureRows)
{
    if ($creatureNames -ccontains $row.creatureName)
    {
        $primaryByCreature[$row.creatureName] = $row.primary_weapon
    }
}
function Get-WeaponType([string]$Weapon)
{
    if ($Weapon -match 'unarmed') { return "UNARMED" }
    if ($Weapon -match '2h_sword') { return "2HAND_MELEE" }
    if ($Weapon -match 'polearm') { return "POLEARM" }
    if ($Weapon -match 'sword') { return "1HAND_MELEE" }
    if ($Weapon -match 'carbine') { return "CARBINE" }
    if ($Weapon -match 'rifle') { return "RIFLE" }
    if ($Weapon -match 'pistol') { return "PISTOL" }
    return "UNKNOWN"
}
for ($i = 0; $i -lt $expectedKeys.Count; ++$i)
{
    Assert-True ($primaryByCreature.ContainsKey($creatureNames[$i])) `
        "Creature row $($creatureNames[$i]) is missing."
    $actualWeaponType = Get-WeaponType $primaryByCreature[$creatureNames[$i]]
    Assert-True ($actualWeaponType -ceq $expectedWeaponTypes[$i]) `
        "$($expectedKeys[$i]) source weapon is $actualWeaponType, expected $($expectedWeaponTypes[$i])."
    foreach ($ability in $abilityRows[$i])
    {
        Assert-True ($weaponByAction.ContainsKey($ability)) `
            "Combat ability $ability is missing from combat_data.tab."
        Assert-True ($weaponByAction[$ability] -ceq $expectedWeaponTypes[$i]) `
            "$($expectedKeys[$i]) queues $ability ($($weaponByAction[$ability])) with a $($expectedWeaponTypes[$i]) weapon."
    }
}
foreach ($key in $expectedKeys)
{
    Assert-True ($generatorSource.Contains("Name = `"archetype_$key`"")) `
        "Localized roster is missing archetype_$key."
}

# Combat level controls creature/HAM/weapon profile and ability tier.
Assert-Match $merc 'skill\.getPrecuEncounterDifficulty\(player\)' `
    "Player PRE-CU combat level is not used."
Assert-Match $merc 'create\.createCreature\(\s*CREATURE_TYPES\[archetype\],\s*spawn,\s*level' `
    "Bounded combat level is not passed to creature profile creation."
Assert-Match $merc 'VAR_WEAPON_QUALITY,\s*level' `
    "Scaled weapon-quality inspection value is missing."
Assert-Match $merc 'getAbilityTierForLevel\(level\)' `
    "Level-gated role abilities are missing."
Assert-Match $ai 'combat\.canPerformAction\(bestAbility, self\).*combat\.ACTION_SUCCESS' `
    "Mercenary abilities bypass the authoritative weapon/HAM precheck."
Assert-Match $ai 'distance >= weaponRange\.maxRange.*distance >= actionData\.maxRange.*!canSee\(self, target\)' `
    "Mercenary abilities bypass weapon/action range or line of sight."
Assert-Match $ai 'if \(queueCommand\(self, getStringCrc\(bestAbility\.toLowerCase\(\)\).*SV_LAST_ABILITY' `
    "Failed ability queues still consume the custom cooldown."

# Debit envelope, durable restart ledger, idempotency, and rollback/refund.
foreach ($field in @(
    "DICT_CODE", "DICT_PLAYER_ID", "DICT_TARGET_ID", "DICT_ACCT_NAME",
    "DICT_AMOUNT", "DICT_TOTAL"))
{
    Assert-True ($merc.Contains("params.containsKey(money.$field)")) `
        "Payment callback no longer authenticates money.$field."
}
Assert-Match $merc 'params\.getObjId\(money\.DICT_PLAYER_ID\) == player' `
    "Payment player provenance is not checked."
Assert-Match $merc 'params\.getObjId\(money\.DICT_TARGET_ID\) == obj_id\.NULL_ID' `
    "Named-account null target is not checked."
Assert-Match $merc 'params\.getInt\(money\.DICT_AMOUNT\) == cost.*params\.getInt\(money\.DICT_TOTAL\) == cost' `
    "Payment amount and total are not both checked."
Assert-Match $merc 'setObjVar\(player, VAR_TX_STARTED, getCalendarTime\(\)\)' `
    "Transaction start time is not restart-safe calendar time."
foreach ($field in @(
    "VAR_TX_NONCE", "VAR_TX_PLAYER", "VAR_TX_STATE", "VAR_TX_TERMINAL",
    "VAR_TX_COST", "VAR_TX_HIRED", "VAR_TX_ACCOUNT"))
{
    Assert-True ($merc.Contains($field)) "Durable ledger is missing $field."
}
Assert-Match $merc 'boolean dispatched = money\.requestPayment.*if \(!dispatched\).*clearPendingHire\(player\).*detachScript' `
    "Authoritative no-debit dispatch failure is not unlocked."
Assert-Match $merc 'removeObjVar\(player, VAR_TX_ROOT\)' `
    "Durable transaction tree is not cleared atomically."
Assert-Match $merc 'utils\.removeScriptVarTree\(player, LEGACY_SV_PENDING\)' `
    "Legacy transient transaction tree is not cleaned."
Assert-Match $payment 'public int OnInitialize.*reconcileHireMercTransaction' `
    "Restart reconciliation hook is missing."
Assert-Match $payment 'STATE_DEBITED.*rollbackHire.*queueRefund' `
    "Accepted debit cannot resume into rollback/refund."
Assert-Match $payment 'STATE_ENROLLING.*VAR_ACTIVE.*isEnrollmentComplete' `
    "Restart enrollment cannot recognize an already committed party member."
Assert-Match $payment 'STATE_REFUNDING means a named-account transfer is already in flight' `
    "Refund reconciliation no longer guards against duplicate credit."
Assert-Match $payment 'STATE_DEBITED\).*prepareHire' `
    "Payment success has no idempotent state barrier before spawn."
Assert-Match $payment 'VAR_TX_REFUND_ATTEMPT' `
    "Refund callback generations are not persisted."

# Native party enrollment is proved, and every failed spawn is fully rolled back.
Assert-Match $merc 'queueCommand\(groupLeader, \(-2007999144\), hired' `
    "Native group invitation command is missing."
Assert-Match $ai 'queueCommand\(self, \(-1449236473\), null' `
    "Native group acceptance command is missing."
Assert-Match $merc 'playerGroup != hiredGroup' `
    "Hire activation does not prove shared group membership."
Assert-Match $merc 'hasScript\(hired, group\.SCRIPT_GROUP_MEMBER\)' `
    "Native group-member script is not verified."
Assert-Match $merc 'rollbackHire.*queueCommand\(hired, \(1348589140\).*setMaster\(hired, null\).*removeObjVar\(hired, VAR_ROOT\).*destroyObject\(hired\)' `
    "Rollback does not clear group, master, merc state, and spawned NPC."

# Mission payouts remain player-only despite real NPC party membership.
Assert-Match $missionBase 'group\.getPCMembersInRange\(' `
    "Dynamic mission reward path no longer uses the PC-only helper."
Assert-Match $groupSource 'getPCMembersInRange.*isPlayer\(member\)' `
    "PC-only group helper no longer filters NPC party members."
Assert-Match $merc 'VAR_NO_MISSION_CREDIT,\s*1' `
    "Mercenary no-mission-credit marker is missing."

# Leader gate, target-family isolation, healing, and vehicle synchronization.
Assert-Match $ai 'if \(!ai_lib\.isInCombat\(leader\)\).*suppressCombat\(self\)' `
    "Mercenary can engage before the party leader."
Assert-Match $ai 'candidateName\.equals\(expectedName\)' `
    "Follow-on targeting no longer requires the same creature name."
Assert-Match $ai 'candidateAnchor ==\s*utils\.getObjIdScriptVar\(self, SV_FOCUS_ANCHOR\)' `
    "Follow-on targeting no longer requires the same mission/lair anchor."
Assert-Match $ai 'return !isIdValid\(candidateAnchor\)' `
    "Wilderness targets can bleed into anchored mission spawns."
Assert-Match $ai 'applyDamageHealing\(patient, self, attribute, amount, true\)' `
    "Support archetypes cannot heal party primary pools."
$vehicleBlock = [regex]::Match(
    $ai,
    'private void manageVehicle(?<body>.*?)private obj_id createOwnVehicle',
    [Text.RegularExpressions.RegexOptions]::Singleline).Groups["body"].Value
Assert-True ($vehicleBlock.IndexOf("doesMountHaveRoom(leaderMount)") -ge 0 -and
    $vehicleBlock.IndexOf("doesMountHaveRoom(leaderMount)") -lt
    $vehicleBlock.IndexOf("createOwnVehicle(self)")) `
    "Mercenary does not try the leader's passenger seat before its fallback."
Assert-Match $ai 'if \(!isIdValid\(leaderMount\)\).*dismountCreature\(self\).*destroyOwnVehicle' `
    "Mercenary does not dismount with the party leader."
Assert-Match $ai 'detachScript\(ownVehicle, VEHICLE_PING_SCRIPT\)' `
    "Ephemeral fallback vehicle is still subject to VCD ping destruction."
Assert-Match $ai 'Native mount locomotion is rider-driven.*ai_lib\.aiFollow\(self, leader' `
    "Fallback vehicle has no mounted-rider follow path."
Assert-Match $ai 'OnIncapacitated.*destroyObject\(weapon\).*utils\.emptyContainer\(inventory\)' `
    "Defeated mercenaries can leak scaled equipment or source inventory as loot."

& $generator -Check
Assert-True (Test-Path -LiteralPath $stfPath -PathType Leaf) `
    "Generated precu_hire_merc.stf is missing."

Write-Host "PRE-CU Hire a Merc regression checks passed (18 combat/support families)."
