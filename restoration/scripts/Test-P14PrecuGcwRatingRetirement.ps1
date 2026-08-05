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
    "script.library.gcw" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/gcw.java"
    "PlayerObject.cpp" = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/PlayerObject.cpp"
    "PlayerObject.h" = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/PlayerObject.h"
    "ScriptMethodsPvp.cpp" = Join-Path $source "src/engine/server/library/serverScript/src/shared/ScriptMethodsPvp.cpp"
    "script.systems.missions.base.mission_base" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
    "script.library.groundquests" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/groundquests.java"
    "script.systems.battlefield.player_battlefield" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/player_battlefield.java"
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
$player = [string]$texts["PlayerObject.cpp"]
$playerHeader = [string]$texts["PlayerObject.h"]
$scriptPvp = [string]$texts["ScriptMethodsPvp.cpp"]
$mission = [string]$texts["script.systems.missions.base.mission_base"]
$groundquests = [string]$texts["script.library.groundquests"]
$battlefield = [string]$texts["script.systems.battlefield.player_battlefield"]
$spaceCombat = [string]$texts["script.library.space_combat"]
$spaceBattle = [string]$texts["script.systems.gcw.space.battle_spawner"]

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
    (@($requiredResets | Where-Object { -not $retire.Contains($_) }).Count -eq 0)) `
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
    (Get-BeforeFirstReturn (Get-FunctionSlice $player "void PlayerObject::modifyCurrentGcwPoints" "void PlayerObject::modifyCurrentGcwRating")).Contains("retirePostNgeGcwRatingState();")) `
    "p14.gcw-rating.direct-holiday-and-collection-bypasses-closed-natively"

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

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) `
    "p14.gcw-rating.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU GCW rating retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU GCW rating retirement passed."
