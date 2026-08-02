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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuEncounterDifficultyAuthority)
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
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.encounter-difficulty.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $sha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.encounter-difficulty.overlay.authenticated"
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$skillPath = Join-Path $scriptRoot "library/skill.java"
$missionsPath = Join-Path $scriptRoot "library/missions.java"
$skillsTablePath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$skill = Get-Content -LiteralPath $skillPath -Raw
$missions = Get-Content -LiteralPath $missionsPath -Raw

$scoreMethod = Get-FunctionSlice $skill `
    "public static int getPrecuCombatSkillScore(" `
    "public static int getPrecuEncounterDifficulty("
$encounterMethod = Get-FunctionSlice $skill `
    "public static int getPrecuEncounterDifficulty(" `
    "public static int getPrecuGroupCombatDifficulty("
$groupMethod = Get-FunctionSlice $skill `
    "public static int getPrecuGroupCombatDifficulty(" `
    "public static int getGroupLevel("
$groupCompatibilityMethod = Get-FunctionSlice $skill `
    "public static int getGroupLevel(" `
    "public static void checkForJediAbility("

Assert-Contract ($skill.Contains("PRECU_COMBAT_SKILL_SCORE_MAX = 90") -and
    $skill.Contains("PRECU_ADVANCED_COMBAT_SKILL_WEIGHT = 3") -and
    $scoreMethod.Contains('dataTableGetInt(TBL_SKILL, learnedSkill, "POINTS_REQUIRED")') -and
    $scoreMethod.Contains("points *= PRECU_ADVANCED_COMBAT_SKILL_WEIGHT") -and
    $scoreMethod.Contains("Math.min(score, PRECU_COMBAT_SKILL_SCORE_MAX)")) `
    "p14.encounter-difficulty.skill-point-authority"

Assert-Contract ($skill.Contains('skillName.indexOf("_prereq") >= 0') -and
    $skill.Contains('skillName.startsWith("combat_brawler_")') -and
    $skill.Contains('skillName.startsWith("combat_marksman_")') -and
    $skill.Contains('skillName.startsWith("outdoors_creaturehandler_")') -and
    $skill.Contains('skillName.startsWith("outdoors_squadleader_")') -and
    $skill.Contains('skillName.startsWith("force_discipline_")')) `
    "p14.encounter-difficulty.combat-family-boundary"

Assert-Contract ($encounterMethod.Contains("Math.max(1, getPrecuCombatSkillScore(player))")) `
    "p14.encounter-difficulty.solo-minimum-one"
Assert-Contract ($groupMethod.Contains("group.isGroupObject(playerOrGroup)") -and
    $groupMethod.Contains("getGroupMemberIds(groupId)") -and
    $groupMethod.Contains("memberScore - highestScore + (highestScore / 5.0f)") -and
    $groupMethod.Contains("memberScore / 5.0f") -and
    $groupMethod.Contains("Math.round(groupDifficulty)") -and
    -not $groupMethod.Contains("getGroupObjectLevel")) `
    "p14.encounter-difficulty.publish14-group-shape"
Assert-Contract ($groupCompatibilityMethod.Contains("return getPrecuGroupCombatDifficulty(objPlayer)") -and
    -not $groupCompatibilityMethod.Contains("getLevel(") -and
    -not $groupCompatibilityMethod.Contains("getGroupObjectLevel")) `
    "p14.encounter-difficulty.shared-helper-routed"

Assert-Contract ($missions.Contains("return skill.isPrecuCombatSkillBox(skillName)") -and
    $missions.Contains("return skill.isPrecuBaseCombatSkillBox(skillName)") -and
    $missions.Contains("return skill.getPrecuCombatSkillScore(player)")) `
    "p14.encounter-difficulty.mission-authority-delegated"
$payoutMethod = Get-FunctionSlice $missions `
    "public static float alterMissionPayoutDivisor(obj_id player, float divisor, int missionLevel)" `
    "public static float alterMissionPayoutDivisorDaily(obj_id player, float divisor)"
$dailyPayoutMethod = Get-FunctionSlice $missions `
    "public static float alterMissionPayoutDivisorDaily(obj_id player, float divisor)" `
    "public static float alterMissionPayoutDivisorDaily(obj_id player)"
Assert-Contract ($payoutMethod.Contains("return divisor") -and
    -not $payoutMethod.Contains("getLevel(") -and
    -not $payoutMethod.Contains("levelDelta") -and
    $dailyPayoutMethod.Contains("return divisor") -and
    -not $dailyPayoutMethod.Contains("getPlayerDailyCount")) `
    "p14.encounter-difficulty.latent-mission-penalties-inert"

$consumerExpectations = @(
    @{ Path = "quest/task/ground/spawn.java"; Needle = "skill.getPrecuEncounterDifficulty(player)" },
    @{ Path = "quest/util/dynamic_mob_opponent.java"; Needle = "skill.getPrecuEncounterDifficulty(playerEnemy)" },
    @{ Path = "quest/utility/dynamic_spawn_off_quest_item.java"; Needle = "skill.getPrecuEncounterDifficulty(player)" },
    @{ Path = "theme_park/outbreak/dynamic_spawn_off_quest_item.java"; Needle = "skill.getPrecuEncounterDifficulty(player)" },
    @{ Path = "systems/spawning/spawn_base.java"; Needle = "return skill.getGroupLevel(objPlayer)" },
    @{ Path = "systems/treasure_map/base/treasure_map.java"; Needle = "skill.getPrecuEncounterDifficulty(player)" },
    @{ Path = "systems/treasure_map/base/treasure_map.java"; Needle = "skill.getPrecuEncounterDifficulty(groupOid)" },
    @{ Path = "systems/treasure_map/base/treasure_map.java"; Needle = "skill.getPrecuEncounterDifficulty(playersNear[i])" },
    @{ Path = "theme_park/meatlump/quest_shuttle_comlink.java"; Needle = "skill.getPrecuEncounterDifficulty(player)" },
    @{ Path = "ai/ai.java"; Needle = "skill.getPrecuEncounterDifficulty(giver)" },
    @{ Path = "systems/missions/base/mission_player.java"; Needle = "int intPlayerDifficulty = intLevel" }
)
$allConsumersRouted = $true
$closedSurface = $skill + "`n" + $missions
foreach ($expectation in $consumerExpectations)
{
    $path = Join-Path $scriptRoot ([string]$expectation.Path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        $allConsumersRouted = $false
        continue
    }
    $text = Get-Content -LiteralPath $path -Raw
    if (-not $text.Contains([string]$expectation.Needle))
    {
        $allConsumersRouted = $false
    }
    $closedSurface += "`n" + $text
}
Assert-Contract $allConsumersRouted "p14.encounter-difficulty.retained-consumers-routed"
Assert-Contract (-not [regex]::IsMatch($closedSurface,
    'getLevel\s*\(\s*(player|objPlayer|giver|playerEnemy|groupOid|playersNear\[i\])\s*\)')) `
    "p14.encounter-difficulty.closed-player-level-surface-zero"

$skills = Import-Csv -LiteralPath $skillsTablePath -Delimiter ([char]9)
$brawlerNovice = @($skills | Where-Object { $_.NAME -ceq "combat_brawler_novice" })[0]
$brawlerTierFour = @($skills | Where-Object { $_.NAME -ceq "combat_brawler_unarmed_04" })[0]
$riflemanTierFour = @($skills | Where-Object { $_.NAME -ceq "combat_rifleman_accuracy_04" })[0]
Assert-Contract ([int]$brawlerNovice.POINTS_REQUIRED -eq 15 -and
    (([int]$riflemanTierFour.POINTS_REQUIRED * 3) -gt [int]$brawlerTierFour.POINTS_REQUIRED)) `
    "p14.encounter-difficulty.authored-score-examples"

function Get-GroupDifficulty([int[]]$Scores)
{
    $highest = 0
    $difficulty = 0.0
    foreach ($score in $Scores)
    {
        if ($score -gt $highest)
        {
            $difficulty += $score - $highest + ($highest / 5.0)
            $highest = $score
        }
        else
        {
            $difficulty += $score / 5.0
        }
    }
    return [Math]::Max(1, [Math]::Round($difficulty, 0, [MidpointRounding]::AwayFromZero))
}
Assert-Contract ((Get-GroupDifficulty @(15)) -eq 15 -and
    (Get-GroupDifficulty @(15, 15)) -eq 18 -and
    (Get-GroupDifficulty @(90, 90)) -eq 108 -and
    (Get-GroupDifficulty @(15, 90, 30)) -eq 99) `
    "p14.encounter-difficulty.group-model-examples"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.encounter-difficulty.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU encounter difficulty authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU encounter difficulty authority passed."
