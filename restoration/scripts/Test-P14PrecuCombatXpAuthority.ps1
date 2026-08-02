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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuCombatXpAuthority)
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
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.combat-xp.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $sha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.combat-xp.overlay.authenticated"
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$paths = [ordered]@{
    "script.library.xp" = Join-Path $scriptRoot "library/xp.java"
    "script.library.missions" = Join-Path $scriptRoot "library/missions.java"
    "script.library.group" = Join-Path $scriptRoot "library/group.java"
    "script.systems.missions.base.mission_base" = Join-Path $scriptRoot "systems/missions/base/mission_base.java"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.combat-xp.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($actualHash -ceq [string]$contract.buildEvidence.sourceSha256.$name) `
            "p14.combat-xp.source.$name.authenticated"
    }
}

$xp = [string]$texts["script.library.xp"]
$missions = [string]$texts["script.library.missions"]
$group = [string]$texts["script.library.group"]
$missionBase = [string]$texts["script.systems.missions.base.mission_base"]

$seed = Get-FunctionSlice $xp `
    "public static int getLevelBasedXP(obj_id player, obj_id npc)" `
    "public static int getLevelBasedXP(int level)"
Assert-Contract ($seed.Contains('hasObjVar(npc, "combat.intCombatXP")') -and
    $seed.Contains('getIntObjVar(npc, "combat.intCombatXP")') -and
    $seed.Contains("getLevel(npc)") -and
    -not $seed.Contains("getLevel(player)") -and
    -not $seed.Contains("getAiLevelDiff") -and
    -not $seed.Contains("aiIsAggressive")) `
    "p14.combat-xp.authored-creature-seed"

$groupModifier = Get-FunctionSlice $xp `
    "public static int applyGroupXpModifier(" `
    "public static int applyInspirationBuffXpModifier("
Assert-Contract ($xp.Contains("PRECU_GROUP_XP_MULTIPLIER = 1.20f") -and
    $groupModifier.Contains("getActiveGroupSize(gid) < 2") -and
    $groupModifier.Contains("Math.round(amt * PRECU_GROUP_XP_MULTIPLIER)") -and
    -not $xp.Contains("GROUP_XP_DIVIDER") -and
    -not $xp.Contains("GROUP_XP_BONUS")) `
    "p14.combat-xp.fixed-group-multiplier"

$difficulty = Get-FunctionSlice $xp `
    "public static int getPrecuCombatXpDifficulty(" `
    "public static int capPrecuCombatXp("
$cap = Get-FunctionSlice $xp `
    "public static int capPrecuCombatXp(" `
    "public static String getWeaponXpType("
$award = Get-FunctionSlice $xp `
    "public static void grantCombatXpPerAttackType(" `
    "public static int grantSocialStyleXp("
$capIndex = $award.IndexOf("capPrecuCombatXp(player, xpType, amt)", [System.StringComparison]::Ordinal)
$groupIndex = $award.IndexOf("applyGroupXpModifier(player, amt)", $capIndex, [System.StringComparison]::Ordinal)
Assert-Contract ($xp.Contains("PRECU_COMBAT_XP_DIFFICULTY_CAP = 25") -and
    $xp.Contains("PRECU_COMBAT_XP_PER_DIFFICULTY = 300") -and
    $difficulty.Contains('"private_" + weaponType + "_combat_difficulty"') -and
    $difficulty.Contains('"private_jedi_difficulty"') -and
    $cap.Contains("getPrecuCombatXpDifficulty(player, xpType) * PRECU_COMBAT_XP_PER_DIFFICULTY") -and
    $capIndex -ge 0 -and $groupIndex -gt $capIndex) `
    "p14.combat-xp.weapon-skill-cap-before-group-bonus"

$flyText = Get-FunctionSlice $xp `
    "public static void displayXpFlyText(" `
    "public static float getGroupXpModifierPercentageOfMax("
Assert-Contract (-not $flyText.Contains("isFreeTrialAccount") -and
    -not $flyText.Contains("getLevel(") -and
    -not $flyText.Contains("hasReachedMaxTutorialLevel") -and
    -not $xp.Contains("TBL_PLAYER_LEVEL_XP") -and
    -not $xp.Contains("free_trial_level_cap")) `
    "p14.combat-xp.level-gated-presentation-zero"

$missionXp = Get-FunctionSlice $xp `
    "public static void grantMissionXp(" `
    "public static int grantCollectionSpaceXP("
$dailyLimit = Get-FunctionSlice $missions `
    "public static int getDailyMissionXpLimit(" `
    "public static void sendBountyFail("
$dailyCount = Get-FunctionSlice $missions `
    "public static int getPlayerDailyCount(" `
    "public static float alterMissionPayoutDivisor("
$loginCleanup = Get-FunctionSlice $missions `
    "public static void initializeDailyOnLogin(" `
    "public static boolean isDestroyMission("
$groupMissionXp = Get-FunctionSlice $group `
    "public static boolean distributeMissionXpToGroup(" `
    "}`n}"
Assert-Contract ($missionXp.Contains("public static int getMissionXpAmount") -and
    $missionXp.Contains("public static int grantCollectionXP") -and
    ([regex]::Matches($missionXp, "return 0;")).Count -ge 2 -and
    -not $missionXp.Contains("dataTableGetInt") -and
    -not $missionXp.Contains("grantCombatStyleXp") -and
    $dailyLimit.Contains("return 0;") -and
    $dailyCount.Contains("return 0;") -and
    $dailyCount.Contains("return false;") -and
    $loginCleanup.Contains("clearDailyObjVars(player)") -and
    $loginCleanup.Contains("removeObjVar(player, DAILY_MISSION_OBJVAR)") -and
    $groupMissionXp.Contains("return false;") -and
    -not $groupMissionXp.Contains("grantMissionXp")) `
    "p14.combat-xp.daily-mission-and-collection-level-xp-inert"

$rewardStart = $missionBase.IndexOf("public void deliverReward", [System.StringComparison]::Ordinal)
$rewardEnd = $missionBase.IndexOf("String strTitleString", $rewardStart, [System.StringComparison]::Ordinal)
$reward = if ($rewardStart -ge 0 -and $rewardEnd -gt $rewardStart) {
    $missionBase.Substring($rewardStart, $rewardEnd - $rewardStart)
} else { "" }
Assert-Contract ($reward.Contains("fullRewardEach=") -and
    $reward.Contains("for (Object recipientObject : recipients)") -and
    -not $reward.Contains("grantMissionXp") -and
    -not $reward.Contains("distributeMissionXpToGroup") -and
    -not $reward.Contains("systemPayoutToGroupInternal")) `
    "p14.combat-xp.mission-credit-path-preserved"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.combat-xp.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU combat XP authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU combat XP authority passed."
