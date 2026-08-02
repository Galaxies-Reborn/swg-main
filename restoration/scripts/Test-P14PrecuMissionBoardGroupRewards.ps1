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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuMissionBoardGroupRewards)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

foreach ($evidence in @($contract.buildEvidence.overlayPatches))
{
    $patchPath = Join-Path $repositoryRoot ([string]$evidence.path)
    $exists = Test-Path -LiteralPath $patchPath -PathType Leaf
    Assert-Contract $exists "p14.precu-mission.overlay.exists"
    if ($exists)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and
            $sha -ceq [string]$evidence.sha256) "p14.precu-mission.overlay.authenticated"
    }
}

$missionsPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/missions.java"
$skillLibraryPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/skill.java"
$missionBasePath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
$missionDynamicPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_dynamic_base.java"
$missionPlayerPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_player.java"
$groupPath = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/GroupObject.cpp"
$configPath = Join-Path $source "src/engine/server/library/serverGame/src/shared/core/ConfigServerGame.cpp"
$skillPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"

$missions = Get-Content -LiteralPath $missionsPath -Raw
$skillLibrary = Get-Content -LiteralPath $skillLibraryPath -Raw
$missionBase = Get-Content -LiteralPath $missionBasePath -Raw
$missionDynamic = Get-Content -LiteralPath $missionDynamicPath -Raw
$missionPlayer = Get-Content -LiteralPath $missionPlayerPath -Raw
$group = Get-Content -LiteralPath $groupPath -Raw
$config = Get-Content -LiteralPath $configPath -Raw

Assert-Contract ($missionPlayer.Contains("objMissionData == null || objMissionData.length < 2") -and
    $missionPlayer.Contains("intPairedMissionDataCount") -and
    -not $missionPlayer.Contains("objMissionData.length < 10")) "p14.precu-mission.partial-board-population"
Assert-Contract ($missionPlayer.Contains("missions.getPrecuMissionGroupCombatScore(self)") -and
    -not $missionPlayer.Contains("skill.getGroupLevel(self)")) "p14.precu-mission.hidden-combat-rating"
Assert-Contract (([regex]::Matches($missionPlayer,
    'missions\.applyPrecuMissionGroupReward\(objTest, self\)')).Count -eq 2) "p14.precu-mission.combat-terminal-reward-snapshot"
Assert-Contract ($missionDynamic.Contains("region[] rgnCities = getRegionsWithMunicipalAtPoint(locMissionStart, regions.MUNI_TRUE);") -and
    $missionDynamic.Contains("rgnCities = getRegionsAtPoint(locMissionStart);")) "p14.precu-mission.delivery-location-fallback"

Assert-Contract ($missionBase.Contains("public static final int MAX_MISSIONS = 10;") -and
    $config -match 'KEY_INT\s*\(numberOfMissionsWantedInMissionBag,\s*10\)') "p14.precu-mission.ten-mission-limits"
Assert-Contract ($group.Contains("const uint32_t cs_maximumNumberInGroup = 24;")) "p14.precu-mission.party-cap-24"

Assert-Contract ($skillLibrary.Contains("PRECU_ADVANCED_COMBAT_SKILL_WEIGHT = 3") -and
    $skillLibrary.Contains("PRECU_COMBAT_SKILL_SCORE_MAX = 90") -and
    $skillLibrary.Contains("points *= PRECU_ADVANCED_COMBAT_SKILL_WEIGHT") -and
    $skillLibrary.Contains('skillName.indexOf("_prereq") >= 0') -and
    $missions.Contains("return skill.getPrecuCombatSkillScore(player)")) "p14.precu-mission.combat-skill-weighting"
Assert-Contract ($missions.Contains("PRECU_MISSION_MEMBER_REWARD_BONUS = 0.10f") -and
    $missions.Contains("(averageScore / 100.0f)") -and
    $missions.Contains("setMissionReward(missionData, scaledReward)")) "p14.precu-mission.group-credit-scaling"

$rewardStart = $missionBase.IndexOf("public void deliverReward")
$rewardEnd = $missionBase.IndexOf("String strTitleString", $rewardStart)
$rewardMethod = $missionBase.Substring($rewardStart, $rewardEnd - $rewardStart)
Assert-Contract ($rewardMethod.Contains("fullRewardEach=") -and
    $rewardMethod.Contains("for (Object recipientObject : recipients)") -and
    -not $rewardMethod.Contains("systemPayoutToGroupInternal") -and
    -not $rewardMethod.Contains("alterMissionPayoutDivisorDaily") -and
    -not $rewardMethod.Contains("getSafeDifference") -and
    -not $rewardMethod.Contains("missions.incrementDaily")) "p14.precu-mission.full-unsplit-unlimited-credit"

$skills = Import-Csv -LiteralPath $skillPath -Delimiter ([char]9)
$brawlerNovice = @($skills | Where-Object { $_.NAME -ceq "combat_brawler_novice" })[0]
$brawlerTierFour = @($skills | Where-Object { $_.NAME -ceq "combat_brawler_unarmed_04" })[0]
$riflemanTierFour = @($skills | Where-Object { $_.NAME -ceq "combat_rifleman_accuracy_04" })[0]
Assert-Contract ([int]$brawlerNovice.POINTS_REQUIRED -eq 15) "p14.precu-mission.fresh-combat-score-15"
Assert-Contract (([int]$riflemanTierFour.POINTS_REQUIRED * 3) -gt
    [int]$brawlerTierFour.POINTS_REQUIRED) "p14.precu-mission.advanced-tier-outweighs-base-tier"

$twoNoviceMultiplier = 1.0 + ((2 - 1) * 0.10) + (15 / 100.0)
$fullPartyMultiplier = 1.0 + ((24 - 1) * 0.10) + (90 / 100.0)
Assert-Contract ([Math]::Abs($twoNoviceMultiplier - 1.25) -lt 0.0001 -and
    [Math]::Abs($fullPartyMultiplier - 4.20) -lt 0.0001) "p14.precu-mission.reward-formula-examples"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.precu-mission.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU mission board/group rewards failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU mission board/group rewards passed."
