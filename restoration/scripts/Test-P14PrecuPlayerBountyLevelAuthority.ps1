[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Build", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuPlayerBountyLevelAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-DockerArtifactEvidence([string]$Container, [string]$Path)
{
    $hashOutput = (& docker exec $Container sha256sum $Path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($hashOutput)) { return $null }
    $statOutput = (& docker exec $Container stat -Lc "%s|%i" $Path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($statOutput)) { return $null }
    $statParts = $statOutput.Split('|')
    if ($statParts.Count -ne 2) { return $null }
    return [pscustomobject]@{
        Sha256 = $hashOutput.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[0]
        Bytes = [long]$statParts[0]
        Inode = [long]$statParts[1]
    }
}

function Assert-DockerArtifactSet(
    [string]$Container,
    [string]$Root,
    [object]$ArtifactSet,
    [bool]$RequireInode,
    [string]$NamePrefix)
{
    foreach ($property in $ArtifactSet.PSObject.Properties)
    {
        $expected = $property.Value
        $pathProperty = $expected.PSObject.Properties['path']
        $artifactPath = if ($null -ne $pathProperty) { [string]$pathProperty.Value } else { "$Root$($property.Name)" }
        $actual = Get-DockerArtifactEvidence -Container $Container -Path $artifactPath
        $inodeMatches = -not $RequireInode -or ($null -ne $actual -and [long]$expected.inode -eq $actual.Inode)
        Assert-Contract (
            $null -ne $actual -and
            [string]$expected.sha256 -ceq $actual.Sha256 -and
            [long]$expected.bytes -eq $actual.Bytes -and
            $inodeMatches) "$NamePrefix.$($property.Name)"
    }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { return "" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

function Compress-Whitespace([string]$Text)
{
    return [regex]::Replace($Text, '\s+', ' ').Trim()
}

$paths = [ordered]@{}
$texts = @{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($name in $paths.Keys)
{
    $path = $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.player-bounty.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $hashProperty = $contract.buildEvidence.sourceSha256.PSObject.Properties[$name]
        Assert-Contract ($null -ne $hashProperty -and $actualHash -ceq [string]$hashProperty.Value) `
            "p14.player-bounty.source.$name.authenticated"
    }
}
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")

$expected = $contract.expected
Assert-Contract (
    [string]$expected.terminalAdmissionSkill -ceq "combat_bountyhunter_novice" -and
    [string]$expected.playerTargetAdmissionSkill -ceq "combat_bountyhunter_investigation_03" -and
    [string]$expected.jediTitleSkill -ceq "force_title_jedi_rank_02" -and
    [int]$expected.visibilityThreshold -eq 1500 -and
    [int]$expected.visibilityCap -eq 8000 -and
    [int]$expected.visibilityDecaySeconds -eq (21 * 24 * 60 * 60) -and
    [int]$expected.visibilityDecayTickSeconds -eq (60 * 60) -and
    [int]$expected.maximumExistingHunters -eq 5 -and
    [int]$expected.recentKillBufferSeconds -eq (30 * 60) -and
    [int]$expected.hunterTargetCooldownSeconds -eq (24 * 60 * 60) -and
    [int]$expected.hunterBountyHunterXpDivisor -eq 50 -and
    [int]$expected.hunterBountyHunterXpGrantCount -eq 1 -and
    [int]$expected.forceCureActiveProducerCalls -eq 1 -and
    [int]$expected.activeVisibilityProducerCalls -eq 8 -and
    [int]$expected.retainedUnreachableVisibilityProducerCalls -eq 1 -and
    [int]$expected.totalTextualVisibilityProducerCalls -eq 9 -and
    [int]$expected.forceRankMinimum -eq 0 -and
    [int]$expected.forceRankMaximum -eq 11 -and
    [int]$expected.lightCouncilValue -eq 2 -and
    [int]$expected.darkCouncilValue -eq 1 -and
    [int]$expected.compatibilityLevelValue -eq 0) `
    "p14.player-bounty.contract-era-values-pinned"
Assert-Contract (
    [bool]$expected.canonicalJediRewardPrecedesSmugglerReward -and
    [bool]$expected.simultaneousJediAndSmugglerStatePreserved -and
    [bool]$expected.normalAndSmugglerMissionProvenanceDisjoint -and
    [bool]$expected.cooldownRequiresAcceptedAssignment -and
    [bool]$expected.singlePendingAssignmentPerHunter -and
    [bool]$expected.callbackTargetCorrelationRequired -and
    [bool]$expected.samePlanetSelectionBoundedToPopulatedEntries -and
    [bool]$expected.targetSpecificFailureCleanup -and
    [bool]$expected.rewardRevalidatesCurrentProvenance -and
    [bool]$expected.invalidAcceptedMissionFailsClosed -and
    [bool]$expected.titleLossCancelsOnlyJediMissions -and
    [bool]$expected.invalidFrsStateCanonicalizesToJedi -and
    [bool]$expected.nonKillSmugglerCancellationProvenanceScoped -and
    [bool]$expected.successfulKillClearsAllHunterAssignments -and
    [bool]$expected.hunterCreditRewardUsesMissionSnapshot -and
    -not [bool]$expected.factionStandingRewardSideEffect -and
    -not [bool]$expected.pvpRatingRewardSideEffect -and
    -not [bool]$expected.manualPlayerBountyFunding -and
    -not [bool]$expected.ordinaryPvpKillBountyWriter -and
    [bool]$expected.npcBountyFallbackPreserved -and
    [bool]$expected.laterSmugglerBountyContentPreserved) `
    "p14.player-bounty.contract-precedence-pinned"

$jedi = [string]$texts["jedi"]
Assert-Contract (
    $jedi.Contains('JEDI_BOUNTY_TITLE_SKILL = "force_title_jedi_rank_02"') -and
    $jedi.Contains("MAX_JEDI_VISIBILITY = 8000") -and
    $jedi.Contains("BOUNTY_VISIBILITY_THRESHHOLD = 1500") -and
    $jedi.Contains("VISIBILITY_DECAY_TIME_SECONDS = 21 * 24 * 60 * 60") -and
    $jedi.Contains("VISIBILITY_DECAY_TICK_SECONDS = 60 * 60") -and
    $jedi.Contains("VISIBILITY_WITNESS_RANGE = 32") -and
    $jedi.Contains("NONCOMBAT_VISIBILITY = 10") -and
    $jedi.Contains("COMBAT_VISIBILITY = 25") -and
    $jedi.Contains("SABER_EQUIP_VISIBILITY = 10")) `
    "p14.player-bounty.jedi-visibility-constants"
Assert-Contract (
    $jedi.Contains("ENEMY_VISIBILITY_MULTIPLIER = 1.0f") -and
    $jedi.Contains("NEUTRAL_VISIBILITY_MULTIPLIER = 0.5f") -and
    $jedi.Contains("FRIENDLY_VISIBILITY_MULTIPLIER = 0.25f")) `
    "p14.player-bounty.witness-faction-weights"

$jediProvenance = Get-BracedSurface $jedi "public static boolean hasPlayerBountyJediProvenance("
$witnessAdmission = Get-BracedSurface $jedi "private static boolean isValidVisibilityWitness("
$witnessValue = Get-BracedSurface $jedi "public static int getJediActionVisibilityValue("
$actionProducer = Get-BracedSurface $jedi "public static void jediActionPerformed("
$visibilityDecay = Get-BracedSurface $jedi "public static void decayJediVisibility("
Assert-Contract (
    $jediProvenance.Contains("hasSkill(player, JEDI_BOUNTY_TITLE_SKILL)") -and
    $witnessAdmission.Contains("witness != player") -and
    $witnessAdmission.Contains("!isDead(witness)") -and
    $witnessAdmission.Contains("!isIncapacitated(witness)") -and
    $witnessAdmission.Contains("canSee(witness, player)") -and
    $witnessValue.Contains("getNPCsInRange") -and
    $witnessValue.Contains("getPlayerCreaturesInRange") -and
    $witnessValue.Contains("getVisibilityWitnessMultiplier")) `
    "p14.player-bounty.exact-title-and-witness-admission"
Assert-Contract (
    $actionProducer.Contains("decayJediVisibility(objPlayer)") -and
    $actionProducer.Contains("getJediActionVisibilityValue") -and
    $actionProducer.Contains("Math.min(MAX_JEDI_VISIBILITY") -and
    $visibilityDecay.Contains("getCalendarTime()") -and
    $visibilityDecay.Contains("VAR_VISIBILITY_DECAY_REMAINDER") -and
    $visibilityDecay.Contains("(float)elapsed * MAX_JEDI_VISIBILITY / VISIBILITY_DECAY_TIME_SECONDS") -and
    $visibilityDecay.Contains("Math.max(0, currentVisibility - decay)")) `
    "p14.player-bounty.capped-elapsed-visibility-decay"

$basePlayer = [string]$texts["basePlayer"]
$startDecay = Get-BracedSurface $basePlayer "public void startJediVisibilityDecay("
$handleDecay = Get-BracedSurface $basePlayer "public int handleJediVisibilityDecay("
Assert-Contract (
    $startDecay.Contains("jedi.decayJediVisibility(self)") -and
    $startDecay.Contains("jedi.VISIBILITY_DECAY_TICK_SECONDS") -and
    $handleDecay.Contains("jedi.SCRIPTVAR_VISIBILITY_DECAY_SEQUENCE") -and
    $handleDecay.Contains("jedi.decayJediVisibility(self)") -and
    $handleDecay.Contains("jedi.VISIBILITY_DECAY_TICK_SECONDS")) `
    "p14.player-bounty.hourly-player-decay-lifecycle"

$jediActionRows = @(Import-SwgTab -Path $paths["jediActions"])
$jediCombatRows = @(Import-SwgTab -Path $paths["jediCombatData"])
Assert-Contract (
    $jediActionRows.Count -eq [int]$expected.jediActionRows -and
    @($jediActionRows | Where-Object { [int]$_.intVisibilityValue -ne [int]$expected.actionVisibilityValue -or [int]$_.intVisibilityRange -ne [int]$expected.visibilityWitnessRangeMeters }).Count -eq 0) `
    "p14.player-bounty.jedi-action-table-cardinality-and-values"
Assert-Contract (
    $jediCombatRows.Count -eq [int]$expected.jediCombatRows -and
    @($jediCombatRows | Where-Object { [int]$_.intVisibilityValue -ne [int]$expected.combatVisibilityValue -or [int]$_.intVisibilityRange -ne [int]$expected.visibilityWitnessRangeMeters }).Count -eq 0) `
    "p14.player-bounty.jedi-combat-table-cardinality-and-values"
$jediLibraryProducerCount = [regex]::Matches($jedi, 'jedi\.jediActionPerformed\(').Count
$combatProducerCount = [regex]::Matches([string]$texts["combatBase"], 'jedi\.jediActionPerformed\(').Count
$saberProducerCount = [regex]::Matches([string]$texts["combatPlayer"], 'jedi\.jediActionPerformed\(').Count
$forceCureHelper = Get-BracedSurface ([string]$texts["jediBase"]) `
    "public static boolean performPrecuForceCureCommand("
$legacyHeal = Get-BracedSurface ([string]$texts["jediBase"]) `
    "public boolean doJediHealCommand("
$forceCureProducerCount = [regex]::Matches(
    $forceCureHelper, 'jedi\.jediActionPerformed\(').Count
$legacyHealProducerCount = [regex]::Matches(
    $legacyHeal, 'jedi\.jediActionPerformed\(').Count
Assert-Contract (
    $jediLibraryProducerCount -eq [int]$expected.jediLibraryActionProducerCalls -and
    $combatProducerCount -eq [int]$expected.combatResolutionProducerCalls -and
    $saberProducerCount -eq [int]$expected.saberEquipProducerCalls -and
    $forceCureProducerCount -eq [int]$expected.forceCureActiveProducerCalls -and
    ($jediLibraryProducerCount + $combatProducerCount + $saberProducerCount +
        $forceCureProducerCount) -eq [int]$expected.activeVisibilityProducerCalls -and
    $legacyHealProducerCount -eq [int]$expected.retainedUnreachableVisibilityProducerCalls -and
    ($jediLibraryProducerCount + $combatProducerCount + $saberProducerCount +
        $forceCureProducerCount + $legacyHealProducerCount) -eq
        [int]$expected.totalTextualVisibilityProducerCalls -and
    ([string]$texts["combatBase"]).Contains("jedi.COMBAT_VISIBILITY") -and
    ([string]$texts["combatPlayer"]).Contains("jedi.SABER_EQUIP_VISIBILITY")) `
    "p14.player-bounty.visibility-producer-cardinality"

$dsrcRoot = Join-Path $source "dsrc"
$legacyMethodReferences = @(& git -C $dsrcRoot grep -n -I -E 'doJediHealCommand' -- '*.java' '*.tab' '*.tpf' 2>$null)
$legacyMethodGrepExit = $LASTEXITCODE
$activeHelperReferences = @(& git -C $dsrcRoot grep -n -I -E `
    'performPrecuForceCureCommand' -- '*.java' '*.tab' '*.tpf' 2>$null)
$activeHelperGrepExit = $LASTEXITCODE
Assert-Contract (
    $legacyHeal.Contains("jedi.jediActionPerformed(self, intVisibilityValue, intVisibilityRange)") -and
    $legacyMethodGrepExit -eq 0 -and $legacyMethodReferences.Count -eq 1 -and
    [string]$legacyMethodReferences[0] -match 'systems/jedi/jedi_base\.java:' -and
    $activeHelperGrepExit -eq 0 -and $activeHelperReferences.Count -eq 4 -and
    @($activeHelperReferences | Where-Object {
        [string]$_ -match 'systems/combat/combat_actions\.java:'
    }).Count -eq 3 -and
    @($activeHelperReferences | Where-Object {
        [string]$_ -match 'systems/jedi/jedi_base\.java:'
    }).Count -eq 1 -and
    -not [regex]::IsMatch([string]$texts["jediBase"], 'public\s+(?:int|boolean|void)\s+(?:On|handle)[A-Z]')) `
    "p14.player-bounty.active-and-retained-jedi-base-producer-split"

$missionBoard = Get-BracedSurface ([string]$texts["missionPlayer"]) "public int OnPlayerRequestMissionBoard("
Assert-Contract (
    $missionBoard.Contains('hasObjVar(objMissionTerminal, "intBounty")') -and
    $missionBoard.Contains('!hasSkill(self, "combat_bountyhunter_novice")') -and
    $missionBoard.Contains("createJediBountyMission") -and
    $missionBoard.Contains("createDynamicBountyMission")) `
    "p14.player-bounty.novice-terminal-and-npc-fallback"

$playerBounty = Get-BracedSurface ([string]$texts["missionDynamic"]) "public obj_id createJediBountyMission(obj_id objMissionData, obj_id objCreator, String strFaction, int hunterLevel, obj_id bountyHunterId, int flag)"
$compactPlayerBounty = Compress-Whitespace $playerBounty
Assert-Contract ($playerBounty.Contains('!hasSkill(bountyHunterId, "combat_bountyhunter_investigation_03")')) `
    "p14.player-bounty.investigation-three-admission"
Assert-Contract (
    $compactPlayerBounty.Contains("requestJedi(jedi.BOUNTY_VISIBILITY_THRESHHOLD, IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, -5, bounty_hunter.PLAYER_BOUNTY_JEDI_STATE_MASK)") -and
    $compactPlayerBounty.Contains("requestJedi(IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, -5, IGNORE_JEDI_STAT)") -and
    -not $playerBounty.Contains("15000") -and
    -not $playerBounty.Contains("-3") -and
    -not $playerBounty.Contains("bhMin") -and
    -not $playerBounty.Contains("bhMax") -and
    -not [regex]::IsMatch($playerBounty, 'hunterLevel\s*[<>]=?')) `
    "p14.player-bounty.normal-and-smuggler-query-contracts"
Assert-Contract (
    $playerBounty.Contains('getIntArray("bountyValue")') -and
    $playerBounty.Contains('getIntArray("smugglerBountyValue")') -and
    $playerBounty.Contains("DATA_PLAYER_BOUNTY_KILL_BUFFER_UNTIL") -and
    $playerBounty.Contains("isPlayerBountyMissionCooldownActive") -and
    $playerBounty.Contains("hasPlayerBountyAccountConflict") -and
    $playerBounty.Contains("selectedBountyValues") -and
    $playerBounty.Contains("PLAYER_BOUNTY_JEDI_STATE_MASK") -and
    $playerBounty.Contains("BOUNTY_FLAG_SMUGGLER") -and
    $playerBounty.Contains("PLAYER_BOUNTY_PROVENANCE_SMUGGLER") -and
    $playerBounty.Contains("PLAYER_BOUNTY_PROVENANCE_JEDI") -and
    $playerBounty.Contains("setMissionReward(objMissionData, jediBountyValue)")) `
    "p14.player-bounty.disjoint-query-reward-and-provenance"
Assert-Contract (
    [regex]::Matches($playerBounty, 'rand\(0,\s*SamePlanetCounter\s*-\s*1\)').Count -eq 2 -and
    -not $playerBounty.Contains("SamePlanetObjId.length - 1")) `
    "p14.player-bounty.same-planet-selection-populated-bound"

$investigationRow = ([string]$texts["skillTable"] -split "\r?\n" | Where-Object { $_.StartsWith("combat_bountyhunter_investigation_03" + [char]9) })
Assert-Contract (@($investigationRow).Count -eq 1 -and [string]$investigationRow -match 'combat_bountyhunter_investigation_02' -and [string]$investigationRow -match 'droid_track') `
    "p14.player-bounty.investigation-three-authored-skill"

$bountyHunter = [string]$texts["bountyHunter"]
$accountConflict = Get-BracedSurface $bountyHunter "public static boolean hasPlayerBountyAccountConflict("
$targetValidation = Get-BracedSurface $bountyHunter "public static boolean isValidPlayerBountyTarget(obj_id hunter, obj_id target, int provenance,"
Assert-Contract (
    $bountyHunter.Contains("MAX_ACTIVE_PLAYER_BOUNTIES = 5") -and
    $bountyHunter.Contains("PLAYER_BOUNTY_KILL_BUFFER_SECONDS = 30 * 60") -and
    $bountyHunter.Contains("PLAYER_BOUNTY_MISSION_COOLDOWN_SECONDS = 24 * 60 * 60") -and
    $targetValidation.Contains('combat_bountyhunter_investigation_03') -and
    $targetValidation.Contains("hasPlayerBountyAccountConflict") -and
    $targetValidation.Contains('getBoolean("online")') -and
    $targetValidation.Contains("hasMaxBountyMissionsOnTarget") -and
    $targetValidation.Contains("isPlayerBountyKillBufferActive") -and
    $targetValidation.Contains("isPlayerBountyMissionCooldownActive") -and
    $targetValidation.Contains("PLAYER_BOUNTY_PROVENANCE_JEDI") -and
    $targetValidation.Contains("PLAYER_BOUNTY_PROVENANCE_SMUGGLER") -and
    $targetValidation.Contains('getInt("smugglerBountyValue")') -and
    $targetValidation.Contains('getInt("bountyValue")') -and
    $targetValidation.Contains("jedi.BOUNTY_VISIBILITY_THRESHHOLD") -and
    $targetValidation.Contains("PLAYER_BOUNTY_JEDI_STATE_MASK")) `
    "p14.player-bounty.script-acceptance-revalidation"
Assert-Contract (
    $accountConflict.Contains("getPlayerStationId(hunter)") -and
    $accountConflict.Contains("getPlayerStationId(target)") -and
    $accountConflict.Contains("getJediBounties(target)") -and
    $accountConflict.Contains("getPlayerStationId(existingHunter)") -and
    $accountConflict.Contains("allowExistingAssignment")) `
    "p14.player-bounty.script-account-and-existing-hunter-boundary"

$assignMission = Get-BracedSurface ([string]$texts["missionPlayer"]) "public int OnAssignMission("
$confirmMission = Get-BracedSurface ([string]$texts["missionPlayer"]) "public int msgJediMissionStartConfirmed("
$failedMission = Get-BracedSurface ([string]$texts["missionPlayer"]) "public int msgJediMissionStartFailed("
$pendingGuardIndex = $assignMission.IndexOf('utils.hasScriptVar(self, "bounty_hunter.jedi_mission")', [StringComparison]::Ordinal)
$nativeRequestIndex = $assignMission.IndexOf("if (!requestJediBounty(", [StringComparison]::Ordinal)
$confirmRevalidationIndex = $confirmMission.IndexOf("bounty_hunter.isValidPlayerBountyTarget(self, target, provenance, true)", [StringComparison]::Ordinal)
$confirmAcceptedIndex = $confirmMission.IndexOf("setObjVar(jedi_mission, bounty_hunter.VAR_PLAYER_BOUNTY_ASSIGNMENT_ACCEPTED, 1)", [StringComparison]::Ordinal)
$confirmStartIndex = $confirmMission.IndexOf("startMission(jedi_mission)", [StringComparison]::Ordinal)
Assert-Contract (
    $assignMission.Contains("bounty_hunter.isValidPlayerBountyTarget") -and
    $assignMission.Contains("if (!requestJediBounty(") -and
    $pendingGuardIndex -ge 0 -and $nativeRequestIndex -gt $pendingGuardIndex -and
    $failedMission.Contains('utils.removeScriptVar(self, "bounty_hunter.jedi_mission")') -and
    $confirmMission.Contains("bounty_hunter.isValidPlayerBountyTarget(self, target, provenance, true)") -and
    $confirmMission.Contains('params.getObjId("jedi")') -and
    $confirmMission.Contains("confirmedTarget != target") -and
    $confirmMission.Contains("bounty_hunter.recordPlayerBountyMissionCooldown") -and
    [regex]::Matches($confirmMission, 'clearPlayerBountyPersonalEnemyFlags\(').Count -eq 3 -and
    [regex]::Matches($confirmMission, 'removeJediBounty\(').Count -eq 3 -and
    $confirmMission.Contains("removeJediBounty(target, self)") -and
    $confirmRevalidationIndex -ge 0 -and
    $confirmAcceptedIndex -gt $confirmRevalidationIndex -and
    $confirmStartIndex -gt $confirmAcceptedIndex) `
    "p14.player-bounty.pre-request-and-callback-revalidation"

$missionEnd = Get-BracedSurface ([string]$texts["missionBounty"]) "public int OnEndMission("
Assert-Contract (
    $missionEnd.Contains("bounty_hunter.VAR_PLAYER_BOUNTY_ASSIGNMENT_ACCEPTED") -and
    $missionEnd.Contains("bounty_hunter.VAR_PLAYER_BOUNTY_PROVENANCE") -and
    $missionEnd.Contains("bounty_hunter.recordPlayerBountyMissionCooldown") -and
    $missionEnd.Contains('getObjIdObjVar(self, "objTarget")')) `
    "p14.player-bounty.mission-end-cooldown-persistence"

$migrateSmuggler = Get-BracedSurface $basePlayer "public void migrateLegacySmugglerBounty("
$migrationCallIndex = $basePlayer.IndexOf("migrateLegacySmugglerBounty(self);", [StringComparison]::Ordinal)
$legacyPurgeIndex = if ($migrationCallIndex -ge 0) { $basePlayer.IndexOf('removeObjVar(self, "bounty.amount");', $migrationCallIndex, [StringComparison]::Ordinal) } else { -1 }
Assert-Contract (
    $migrateSmuggler.Contains('quest/smuggle_pvp_4') -and
    $migrateSmuggler.Contains('quest/smuggle_pvp_5') -and
    $migrateSmuggler.Contains('getIntObjVar(self, "bounty.amount")') -and
    $migrateSmuggler.Contains("questMaximum = tierFiveActive ? 22000 : 17000") -and
    $migrateSmuggler.Contains('setObjVar(self, "smuggler.bounty", smugglerBounty)') -and
    $migrateSmuggler.Contains('updateJediScriptData(self, "smuggler", 1)') -and
    $migrateSmuggler.Contains('updateJediScriptData(self, "smugglerBountyValue", smugglerBounty)') -and
    $migrationCallIndex -ge 0 -and $legacyPurgeIndex -gt $migrationCallIndex) `
    "p14.player-bounty.legacy-smuggler-migration-before-purge"

foreach ($brokerName in @("broker4", "broker5"))
{
    $broker = [string]$texts[$brokerName]
    Assert-Contract (
        $broker.Contains('setObjVar(player, "smuggler.bounty", mission_bounty)') -and
        $broker.Contains('updateJediScriptData(player, "smuggler", 1)') -and
        $broker.Contains('updateJediScriptData(player, "smugglerBountyValue", mission_bounty)') -and
        $broker.Contains("setJediBountyValue(player, mission_bounty)") -and
        -not $broker.Contains("bounty.amount")) `
        "p14.player-bounty.$brokerName.explicit-smuggler-tag"
}
$smuggler = [string]$texts["smuggler"]
$clearSmuggler = Get-BracedSurface $smuggler "public static void clearSmugglerPlayerBounty("
Assert-Contract (
    $clearSmuggler.Contains("bounty_hunter.notifyPlayerBountyMissionsIncomplete") -and
    $clearSmuggler.Contains("PLAYER_BOUNTY_PROVENANCE_SMUGGLER") -and
    $clearSmuggler.Contains('removeObjVar(target, "smuggler.bounty")') -and
    $clearSmuggler.Contains('updateJediScriptData(target, "smuggler", 0)') -and
    $clearSmuggler.Contains('updateJediScriptData(target, "smugglerBountyValue", 0)') -and
    -not $clearSmuggler.Contains("removeAllJediBounties") -and
    -not $smuggler.Contains("bounty.amount")) `
    "p14.player-bounty.smuggler-lifecycle-cancels-only-tagged-channel"

$handleIncomplete = Get-BracedSurface $basePlayer "public int handleBountyMissionIncomplete("
Assert-Contract (
    $handleIncomplete.Contains("params.getInt(bounty_hunter.VAR_PLAYER_BOUNTY_PROVENANCE)") -and
    $handleIncomplete.Contains("getIntObjVar(mission, bounty_hunter.VAR_PLAYER_BOUNTY_PROVENANCE) != provenance") -and
    $handleIncomplete.Contains("return SCRIPT_CONTINUE") -and
    $handleIncomplete.Contains("removeJediBounty(target, self)")) `
    "p14.player-bounty.incomplete-notification-provenance-filter"

$winBounty = Get-BracedSurface $bountyHunter "public static void winBountyMission("
$loseBounty = Get-BracedSurface $bountyHunter "public static void loseBountyMission("
$failInvalidBounty = Get-BracedSurface $bountyHunter "public static void failInvalidPlayerBountyMission("
$currentProvenance = Get-BracedSurface $bountyHunter "public static boolean hasCurrentPlayerBountyProvenance("
$notifyIncomplete = Get-BracedSurface $bountyHunter "public static void notifyPlayerBountyMissionsIncomplete("
$xpLoss = Get-BracedSurface $bountyHunter "public static void applyJediBountyExperienceLoss("
$awardPlayerBounty = Get-BracedSurface $basePlayer "public int handleAwardedPlayerBounty("
Assert-Contract (
    $winBounty.Contains("getMissionReward(mission)") -and
    [regex]::Matches($winBounty, 'money\.systemPayout\(money\.ACCT_BOUNTY,\s*hunter,\s*bountyValue,').Count -eq 1 -and
    [regex]::Matches($winBounty, 'xp\.grant\(hunter,\s*xp\.BOUNTYHUNTER,\s*bountyValue\s*/\s*50\)').Count -eq 1 -and
    $winBounty.Contains("hasCurrentPlayerBountyProvenance(target, provenance)") -and
    $winBounty.Contains("notifyPlayerBountyMissionsIncomplete(target, provenance)") -and
    $winBounty.Contains("failInvalidPlayerBountyMission(hunter, target, mission)") -and
    $winBounty.Contains("recordPlayerBountyKill(target)") -and
    $winBounty.Contains('messageTo(hunter1, "handleBountyMissionIncomplete"') -and
    -not $winBounty.Contains("d.put(VAR_PLAYER_BOUNTY_PROVENANCE") -and
    $winBounty.Contains("PLAYER_BOUNTY_PROVENANCE_JEDI") -and
    $winBounty.Contains("PLAYER_BOUNTY_PROVENANCE_SMUGGLER") -and
    $winBounty.Contains("setJediVisibility(target, 0)") -and
    $winBounty.Contains("applyJediBountyExperienceLoss(target, bountyValue)") -and
    $winBounty.Contains('removeObjVar(target, "smuggler.bounty")') -and
    $winBounty.Contains('updateJediScriptData(target, "smugglerBountyValue", 0)') -and
    -not $awardPlayerBounty.Contains("xp.grant") -and
    $winBounty.Contains("removeAllJediBounties(target)")) `
    "p14.player-bounty.credit-xp-and-all-hunter-success-cleanup"
Assert-Contract (
    $currentProvenance.Contains("jedi.hasPlayerBountyJediProvenance(target)") -and
    $currentProvenance.Contains('getIntObjVar(target, "smuggler.bounty") > 0') -and
    $notifyIncomplete.Contains("VAR_PLAYER_BOUNTY_PROVENANCE") -and
    $notifyIncomplete.Contains('messageTo(hunter, "handleBountyMissionIncomplete"') -and
    $failInvalidBounty.Contains("VAR_PLAYER_BOUNTY_ASSIGNMENT_ACCEPTED") -and
    $failInvalidBounty.Contains("recordPlayerBountyMissionCooldown") -and
    $failInvalidBounty.Contains("clearPlayerBountyPersonalEnemyFlags") -and
    $failInvalidBounty.Contains("removeJediBounty(target, hunter)") -and
    $failInvalidBounty.Contains("endMission(mission)")) `
    "p14.player-bounty.reward-provenance-and-invalid-mission-fail-closed"

$skillRevoked = Get-BracedSurface $basePlayer "public int OnSkillRevoked("
Assert-Contract (
    $skillRevoked.Contains("jedi.JEDI_BOUNTY_TITLE_SKILL") -and
    $skillRevoked.Contains("bounty_hunter.notifyPlayerBountyMissionsIncomplete(self") -and
    $skillRevoked.Contains("bounty_hunter.PLAYER_BOUNTY_PROVENANCE_JEDI")) `
    "p14.player-bounty.title-loss-cancels-only-jedi-provenance"
Assert-Contract (
    -not $bountyHunter.Contains("getBountyFactionPointAdjustment") -and
    -not $bountyHunter.Contains("pvp.getCurrentPvPRating") -and
    -not $winBounty.Contains("grantCombatFaction") -and
    -not $winBounty.Contains("incrementGCWStanding") -and
    -not $winBounty.Contains("pvpModifyCurrentGcwPoints") -and
    -not $awardPlayerBounty.Contains("grantCombatFaction") -and
    -not $awardPlayerBounty.Contains("incrementGCWStanding") -and
    -not $awardPlayerBounty.Contains("pvpModifyCurrentGcwPoints")) `
    "p14.player-bounty.no-faction-or-pvp-rating-reward-side-effect"
Assert-Contract (
    $loseBounty.Contains("getBountyMission(hunter, target)") -and
    $loseBounty.Contains("clearPlayerBountyPersonalEnemyFlags(hunter, target)") -and
    $loseBounty.Contains("removeJediBounty(target, hunter)")) `
    "p14.player-bounty.target-specific-loss-cleanup"
Assert-Contract (
    $bountyHunter.Contains("MIN_JEDI_BOUNTY_XP_LOSS = 50000") -and
    $bountyHunter.Contains("MAX_JEDI_BOUNTY_XP_LOSS = 500000") -and
    $xpLoss.Contains("(long)bountyValue * 2L") -and
    $xpLoss.Contains("xp.JEDI_GENERAL") -and
    $xpLoss.Contains("Math.min(xpLoss, Math.max(0, currentXp))") -and
    $xpLoss.Contains("grantExperiencePoints(target, xp.JEDI_GENERAL, -actualLoss)")) `
    "p14.player-bounty.normal-success-jedi-xp-loss"

$syncKillBuffer = Get-BracedSurface $bountyHunter "public static void syncPlayerBountyKillBuffer("
$recordKillBuffer = Get-BracedSurface $bountyHunter "public static void recordPlayerBountyKill("
$recordMissionCooldown = Get-BracedSurface $bountyHunter "public static void recordPlayerBountyMissionCooldown("
Assert-Contract (
    $syncKillBuffer.Contains("VAR_PLAYER_BOUNTY_LAST_KILL_TIME") -and
    $syncKillBuffer.Contains("PLAYER_BOUNTY_KILL_BUFFER_SECONDS") -and
    $syncKillBuffer.Contains("DATA_PLAYER_BOUNTY_KILL_BUFFER_UNTIL") -and
    $recordKillBuffer.Contains("getCalendarTime()") -and
    $recordKillBuffer.Contains("PLAYER_BOUNTY_KILL_BUFFER_SECONDS") -and
    $recordMissionCooldown.Contains("VAR_PLAYER_BOUNTY_COOLDOWN_RECORDED") -and
    $recordMissionCooldown.Contains("hasObjVar(mission, VAR_PLAYER_BOUNTY_COOLDOWN_RECORDED)") -and
    $recordMissionCooldown.Contains("setObjVar(mission, VAR_PLAYER_BOUNTY_COOLDOWN_RECORDED, 1)") -and
    $recordMissionCooldown.Contains("PLAYER_BOUNTY_MISSION_COOLDOWN_SECONDS")) `
    "p14.player-bounty.kill-buffer-and-mission-cooldown-persistence"

$showManualBounty = Get-BracedSurface $bountyHunter "public static void showSetBountySUI("
$deathBounty = Get-BracedSurface ([string]$texts["pvp"]) "public static void incrementPlayerDeathBounty("
$legacySetBounty = Get-BracedSurface $basePlayer "public int handleSetBounty("
$legacySetBountyTransaction = Get-BracedSurface $basePlayer "public int handleSetBountyTransaction("
Assert-Contract (
    $showManualBounty.Contains('utils.removeScriptVar(player, "setbounty.killer")') -and
    -not $showManualBounty.Contains("createSUIPage") -and
    -not $deathBounty.Contains("setJediBountyValue") -and
    -not $deathBounty.Contains("setObjVar") -and
    -not $legacySetBounty.Contains("money.pay") -and
    -not $legacySetBountyTransaction.Contains("setJediBountyValue") -and
    -not ([string]$texts["pclib"]).Contains("pvp.incrementPlayerDeathBounty(") -and
    -not ([string]$texts["pclib"]).Contains("bounty_hunter.showSetBountySUI(")) `
    "p14.player-bounty.manual-and-kill-writers-retired"

$aggregateWriterMatches = @(Select-String -LiteralPath $javaFiles.FullName -Pattern 'setObjVar\([^;\r\n]*"bounty\.amount"')
$manualWriterCalls = @(Select-String -LiteralPath $javaFiles.FullName -Pattern 'bounty_hunter\.showSetBountySUI\(')
$killWriterCalls = @(Select-String -LiteralPath $javaFiles.FullName -Pattern 'pvp\.incrementPlayerDeathBounty\(')
Assert-Contract ($aggregateWriterMatches.Count -eq 0 -and $manualWriterCalls.Count -eq 0 -and $killWriterCalls.Count -eq 0) `
    "p14.player-bounty.no-production-aggregate-manual-or-kill-writers"
Assert-Contract (
    ([string]$texts["combatActions"]).Contains("dictionary bountyData = requestJedi(infoTarget)") -and
    ([string]$texts["combatActions"]).Contains('bountyData.getInt("bountyValue")') -and
    -not ([string]$texts["combatActions"]).Contains('getIntObjVar(infoTarget, "bounty.amount")')) `
    "p14.player-bounty.inside-information-authoritative-consumer"

Assert-Contract (
    [regex]::Matches([string]$texts["forceRank"], 'setJediBountyValue\([^,]+,\s*0\)').Count -eq 2 -and
    [regex]::Matches([string]$texts["playerForceRank"], 'setJediBountyValue\([^,]+,\s*0\)').Count -eq 3) `
    "p14.player-bounty.force-rank-resynchronization-cardinality"

$swgCreature = [string]$texts["swgCreature"]
$registryState = Get-BracedSurface $swgCreature "JediState getRegistryJediState(SwgCreatureObject const & creature)"
$getBountyValue = Get-BracedSurface $swgCreature "int SwgCreatureObject::getBountyValue() const"
$synchronizeRegistry = Get-BracedSurface $swgCreature "void SwgCreatureObject::synchronizeJediBountyRegistry()"
$grantJediSkill = Get-BracedSurface $swgCreature "const bool SwgCreatureObject::grantSkill("
$revokeJediSkill = Get-BracedSurface $swgCreature "void SwgCreatureObject::revokeSkill("
Assert-Contract (
    $swgCreature.Contains('cms_jediTitleSkill = "force_title_jedi_rank_02"') -and
    $swgCreature.Contains('cms_jediDisciplinePrefix = "force_discipline"') -and
    $swgCreature.Contains('cms_forceRankObjvar = "force_rank.rank"') -and
    $swgCreature.Contains('cms_forceRankCouncilObjvar = "force_rank.council"') -and
    $getBountyValue.Contains("getSpentJediSkillPoints()) * 1000LL") -and
    $getBountyValue.Contains("forceRank) * 100000LL") -and
    $getBountyValue.Contains("std::max(25000LL") -and
    $getBountyValue.Contains("std::max(50000LL") -and
    $getBountyValue.IndexOf("hasPreCuJediTitle()", [StringComparison]::Ordinal) -lt $getBountyValue.IndexOf("cms_smugglerBountyObjvar", [StringComparison]::Ordinal)) `
    "p14.player-bounty.native-canonical-title-skill-rank-reward"
Assert-Contract (
    $registryState.Contains("forceRank >= 0 && forceRank <= 11") -and
    $registryState.Contains("forceRankCouncil == 1 || forceRankCouncil == 2") -and
    $registryState.Contains("forceRankCouncil == 2") -and
    $registryState.Contains("JS_forceRankedLight") -and
    $registryState.Contains("forceRankCouncil == 1") -and
    $registryState.Contains("JS_forceRankedDark") -and
    $registryState.Contains("return JS_jedi")) `
    "p14.player-bounty.native-frs-state-canonicalization"
Assert-Contract (
    $synchronizeRegistry.Contains("titleJedi ? getBountyValue() : smugglerBounty") -and
    $synchronizeRegistry.Contains("visibility, bountyValue, 0, 0") -and
    $synchronizeRegistry.Contains("cms_smugglerScriptData, 1") -and
    $synchronizeRegistry.Contains("cms_smugglerBountyScriptData, smugglerBounty") -and
    $synchronizeRegistry.Contains("cms_smugglerScriptData") -and
    $synchronizeRegistry.Contains("cms_smugglerBountyScriptData")) `
    "p14.player-bounty.native-dual-registry-precedence"
Assert-Contract (
    $grantJediSkill.Contains("affectsPreCuJediRegistry(newSkill.getSkillName())") -and
    $grantJediSkill.Contains("synchronizeJediBountyRegistry()") -and
    $revokeJediSkill.Contains("affectsPreCuJediRegistry(oldSkill.getSkillName())") -and
    $revokeJediSkill.Contains("synchronizeJediBountyRegistry()")) `
    "p14.player-bounty.native-skill-change-reward-resynchronization"
Assert-Contract (
    ([string]$texts["swgCreatureHeader"]).Contains("synchronizeJediBountyRegistry") -and
    ([string]$texts["swgCreatureHeader"]).Contains("getSpentJediSkillPoints")) `
    "p14.player-bounty.native-creature-contract-surface"

$skillObject = [string]$texts["skillObject"]
$skillPointLoad = Get-BracedSurface $skillObject "bool SkillObject::load("
Assert-Contract (
    $skillObject.Contains('ms_skillPointCostLabel               = "POINTS_REQUIRED"') -and
    $skillObject.Contains("int SkillObject::getSkillPointCost() const") -and
    $skillPointLoad.Contains("findColumnNumber(SkillObject::ms_skillPointCostLabel)") -and
    $skillPointLoad.Contains("skillData.skillPointCost = dataTable.getIntValue") -and
    ([string]$texts["skillObjectHeader"]).Contains("getSkillPointCost") -and
    ([string]$texts["skillObjectHeader"]).Contains("int                                         skillPointCost")) `
    "p14.player-bounty.native-skill-point-source-authority"

$swgPlayer = [string]$texts["swgPlayer"]
$nativeVisibilitySetter = Get-BracedSurface $swgPlayer "void SwgPlayerObject::setJediVisibility(int visibility)"
$nativeStateSetter = Get-BracedSurface $swgPlayer "void SwgPlayerObject::setJediState(JediState state)"
$nativeAuthoritySetter = Get-BracedSurface $swgPlayer "void SwgPlayerObject::virtualOnSetAuthority()"
Assert-Contract (
    $nativeVisibilitySetter.Contains("hasPreCuJediTitle") -and
    $nativeVisibilitySetter.Contains("visibility > 8000") -and
    $nativeVisibilitySetter.Contains("setObjVarItem(OBJVAR_JEDI_VISIBILITY, visibility)") -and
    $nativeVisibilitySetter.Contains("synchronizeJediBountyRegistry")) `
    "p14.player-bounty.native-visibility-authoritative-sync"
Assert-Contract (
    $nativeStateSetter.Contains("owner->synchronizeJediBountyRegistry()") -and
    $nativeAuthoritySetter.Contains("owner->synchronizeJediBountyRegistry()")) `
    "p14.player-bounty.native-state-and-authority-resynchronization"

$jediManager = [string]$texts["jediManager"]
$smugglerReward = Get-BracedSurface $jediManager "int JediManagerObject::getSmugglerBountyValue("
$availableTarget = Get-BracedSurface $jediManager "bool JediManagerObject::isAvailableBountyTarget("
$managerQuery = Get-BracedSurface $jediManager "void JediManagerObject::getJedi(int visibility, int bountyValue, int minLevel, int maxLevel,"
$managerRequest = Get-BracedSurface $jediManager "void JediManagerObject::requestJediBounty("
Assert-Contract (
    $jediManager.Contains("cms_minimumJediBountyVisibility = 1500") -and
    $jediManager.Contains("cms_maximumActiveHunters = 5") -and
    $smugglerReward.Contains("cms_smugglerBountyValueScriptData") -and
    $smugglerReward.Contains("!titleJedi") -and
    $availableTarget.Contains("hasBountyTargetProvenance") -and
    $availableTarget.Contains("!m_jediOnline[index]") -and
    $availableTarget.Contains("m_jediBountyValue[index] <= 0") -and
    $availableTarget.Contains("cms_bountyKillBufferScriptData") -and
    $availableTarget.Contains("getSmugglerBountyValue(index)") -and
    $managerQuery.Contains("m_jediBounties[i->second].size() >= cms_maximumActiveHunters") -and
    $managerQuery.Contains("m_jediVisibility[i->second] < visibility") -and
    $managerQuery.Contains("m_jediBounties[i->second].size() >= static_cast<size_t>(-bounties)") -and
    $managerQuery.Contains("(state & m_jediState[i->second]) == 0")) `
    "p14.player-bounty.native-availability-and-dual-reward-filters"
Assert-Contract (
    $managerRequest.Contains("targetId != hunterId") -and
    $managerRequest.Contains("isAvailableBountyTarget(index)") -and
    $managerRequest.Contains("cms_minimumJediBountyVisibility") -and
    $managerRequest.Contains("cms_maximumActiveHunters") -and
    $managerRequest.Contains("getPlayerStationId(hunterId)") -and
    $managerRequest.Contains("getPlayerStationId(targetId)") -and
    $managerRequest.Contains("hunterStationId == targetStationId") -and
    $managerRequest.Contains("getPlayerStationId(*i) == hunterStationId")) `
    "p14.player-bounty.native-acceptance-revalidation"
Assert-Contract (
    ([string]$texts["jediManagerHeader"]).Contains("getSmugglerBountyValue") -and
    ([string]$texts["jediManagerHeader"]).Contains("hasBountyTargetProvenance") -and
    ([string]$texts["jediManagerHeader"]).Contains("isAvailableBountyTarget")) `
    "p14.player-bounty.native-manager-contract-surface"

$addJedi = Get-BracedSurface $jediManager "void JediManagerObject::addJedi("
$updateJedi = Get-BracedSurface $jediManager "void JediManagerObject::updateJedi(const NetworkId & id, int visibility,"
$queryJedi = $managerQuery
$singleJedi = Get-BracedSurface $jediManager "void JediManagerObject::getJedi(const NetworkId & id,"
$databaseBounties = Get-BracedSurface $jediManager "void JediManagerObject::addJediBounties("
Assert-Contract (
    $addJedi.Contains("UNREF(level);") -and
    $addJedi.Contains("int const preCuPlayerLevel = 0;") -and
    $updateJedi.Contains("UNREF(level);") -and
    $updateJedi.Contains("m_jediLevel.set(index, 0)") -and
    $queryJedi.Contains("UNREF(minLevel);") -and
    $queryJedi.Contains("UNREF(maxLevel);") -and
    $queryJedi.Contains("jediLevel->push_back(0)") -and
    $singleJedi.Contains('returnParams.addParam(0, "level")') -and
    [regex]::Matches($databaseBounties, 'm_jediLevel\.(?:push_back|set)\([^\r\n]*0\)').Count -eq 2) `
    "p14.player-bounty.registry-level-neutralization-preserved"

$scriptMethodsJedi = [string]$texts["scriptMethodsJedi"]
$nativeBountySetter = Get-BracedSurface $scriptMethodsJedi "jboolean JNICALL ScriptMethodsJediNamespace::setJediBountyValue("
$nativeBountyRequest = Get-BracedSurface $scriptMethodsJedi "jboolean JNICALL ScriptMethodsJediNamespace::requestJediBounty("
Assert-Contract (
    $nativeBountySetter.Contains("hasPreCuJediTitle") -and
    $nativeBountySetter.Contains("synchronizeJediBountyRegistry") -and
    $nativeBountySetter.Contains("cms_smugglerBountyObjvar") -and
    $nativeBountySetter.Contains("bountyValue == smugglerBounty") -and
    -not $scriptMethodsJedi.Contains("bounty.amount")) `
    "p14.player-bounty.native-script-setter-precedence"
Assert-Contract (
    $nativeBountyRequest.Contains("hunterId == targetId") -and
    $nativeBountyRequest.Contains("getPlayerStationId(targetId)") -and
    $nativeBountyRequest.Contains("hasPreCuJediTitle") -and
    $nativeBountyRequest.Contains("cms_minimumJediBountyVisibility")) `
    "p14.player-bounty.native-script-request-revalidation"

if ($Expectation -in @("Build", "Ready"))
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    Assert-Contract ($dsrcPin.Count -eq 1 -and $srcPin.Count -eq 1 -and [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink -and [string]$srcPin[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.player-bounty.direct-source-pins"
    Assert-Contract (-not [bool]$contract.buildEvidence.historicalCompiledEvidenceOnly -and
        [string]$contract.buildEvidence.historicalCompiledEvidenceDirectSourceCommit -cne
            [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.player-bounty.current-build-evidence-not-historical"
    Assert-Contract (
        [string]$contract.buildEvidence.deploymentParentCommit -ceq "4fd53029ef9fe8dc7863325adb3ec30793980478" -and
        [string]$contract.buildEvidence.fullJavaCompile.result -ceq "passed" -and
        [int]$contract.buildEvidence.fullJavaCompile.sourceCount -eq 5717 -and
        [int]$contract.buildEvidence.fullJavaCompile.classCount -eq 5751 -and
        [bool]$contract.buildEvidence.fullJavaCompile.zeroClassDependencyClean -and
        [string]$contract.buildEvidence.result -ceq "passed") `
        "p14.player-bounty.clean-build-evidence"
    Assert-Contract (
        [string]$contract.buildEvidence.sourceWorkParity.result -ceq "passed" -and
        [int]$contract.buildEvidence.sourceWorkParity.checkedFiles -eq 28 -and
        [int]$contract.buildEvidence.sourceWorkParity.matchedFiles -eq 28) `
        "p14.player-bounty.source-work-parity-evidence"
    Assert-Contract (
        @($contract.buildEvidence.compiledJavaArtifacts.PSObject.Properties).Count -eq 17 -and
        @($contract.buildEvidence.compiledDataArtifacts.PSObject.Properties).Count -eq 3 -and
        @($contract.buildEvidence.nativeObjectArtifacts.PSObject.Properties).Count -eq 5 -and
        @($contract.buildEvidence.nativeArchiveArtifacts.PSObject.Properties).Count -eq 2) `
        "p14.player-bounty.artifact-cardinality"

    $container = [string]$contract.runtimeEvidence.container
    Assert-DockerArtifactSet -Container $container -Root "/swg-precu/data/sku.0/sys.server/compiled/game/" `
        -ArtifactSet $contract.buildEvidence.compiledJavaArtifacts -RequireInode $false -NamePrefix "p14.player-bounty.class"
    Assert-DockerArtifactSet -Container $container -Root "/swg-precu/data/" `
        -ArtifactSet $contract.buildEvidence.compiledDataArtifacts -RequireInode $false -NamePrefix "p14.player-bounty.iff"
    Assert-DockerArtifactSet -Container $container -Root "" `
        -ArtifactSet $contract.buildEvidence.nativeObjectArtifacts -RequireInode $true -NamePrefix "p14.player-bounty.native-object"
    Assert-DockerArtifactSet -Container $container -Root "" `
        -ArtifactSet $contract.buildEvidence.nativeArchiveArtifacts -RequireInode $true -NamePrefix "p14.player-bounty.native-archive"
    $binary = Get-DockerArtifactEvidence -Container $container -Path ([string]$contract.buildEvidence.serverBinary.path)
    Assert-Contract (
        $null -ne $binary -and
        [string]$contract.buildEvidence.serverBinary.sha256 -ceq $binary.Sha256 -and
        [long]$contract.buildEvidence.serverBinary.bytes -eq $binary.Bytes -and
        [long]$contract.buildEvidence.serverBinary.inode -eq $binary.Inode) `
        "p14.player-bounty.server-binary-identity"
    $binaryFile = (& docker exec $container file -L ([string]$contract.buildEvidence.serverBinary.path) 2>&1 | Out-String)
    $binaryNotes = (& docker exec $container readelf -n ([string]$contract.buildEvidence.serverBinary.path) 2>&1 | Out-String)
    Assert-Contract (
        $LASTEXITCODE -eq 0 -and
        $binaryFile.Contains("ELF 64-bit") -and
        $binaryFile.Contains("x86-64") -and
        $binaryNotes.Contains([string]$contract.buildEvidence.serverBinary.buildIdSha1)) `
        "p14.player-bounty.server-binary-elf64-build-id"

    $parityMatches = 0
    foreach ($property in $contract.sourceFiles.PSObject.Properties)
    {
        $relativePath = ([string]$property.Value).Replace('\', '/')
        & docker exec $container cmp -s "/swg-precu-source/$relativePath" "/swg-precu/$relativePath"
        if ($LASTEXITCODE -eq 0) { ++$parityMatches }
    }
    Assert-Contract ($parityMatches -eq 28) "p14.player-bounty.live-source-work-parity"

    $inspection = @((& docker inspect $container 2>&1 | Out-String) | ConvertFrom-Json)[0]
    Assert-Contract (
        [string]$inspection.State.Status -ceq "running" -and
        [string]$inspection.State.Health.Status -ceq [string]$contract.runtimeEvidence.containerHealth -and
        [string]$inspection.State.StartedAt -ceq [string]$contract.runtimeEvidence.containerStartedAt -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers) `
        "p14.player-bounty.container-runtime-evidence"
    $gamePids = @(& docker exec $container pgrep -x SwgGameServer)
    $mappedCount = 0
    foreach ($gamePidValue in $gamePids)
    {
        $processIdentity = (& docker exec $container stat -Lc "%i|%s" "/proc/$gamePidValue/exe" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $processIdentity -ceq "$($contract.runtimeEvidence.liveBinaryInode)|$($contract.runtimeEvidence.liveBinarySizeBytes)") { ++$mappedCount }
    }
    Assert-Contract (
        $gamePids.Count -eq [int]$contract.runtimeEvidence.liveGameProcessCount -and
        $mappedCount -eq $gamePids.Count -and
        [bool]$contract.runtimeEvidence.allLiveGameProcessesMatchBinary) `
        "p14.player-bounty.all-live-processes-map-binary"
    $logs = (& docker logs --since ([string]$contract.runtimeEvidence.containerStartedAt) $container 2>&1 | Out-String)
    $badLogLines = @($logs -split "`n" | Select-String -Pattern "FATAL|SEVERE|Exception|undefined symbol|ORA-|ConGenericMessage constructed with empty message")
    $readyMarkers = @($logs -split "`n" | Select-String -SimpleMatch "Cluster swg is ready for players.")
    Assert-Contract (
        $badLogLines.Count -eq 0 -and
        $readyMarkers.Count -ge 1 -and
        [string]$contract.runtimeEvidence.postStartLogAudit.result -ceq "passed") `
        "p14.player-bounty.clean-ready-post-start-logs"

    if ($Expectation -eq "Ready")
    {
        Assert-Contract (
            [string]$contract.status -ceq "ready" -and
            [string]$contract.liveGameplayEvidence.result -ceq "passed" -and
            $contract.requiredBeforeReady.Count -eq 0) `
            "p14.player-bounty.ready-evidence"
    }
    else
    {
        Assert-Contract (
            [string]$contract.status -ceq "implemented-build-verified-live-pending" -and
            [string]$contract.liveGameplayEvidence.result -ceq "pending" -and
            [bool]$contract.liveGameplayEvidence.clientClosedDuringDeploymentEvidenceCapture -and
            $contract.requiredBeforeReady.Count -eq 1) `
            "p14.player-bounty.build-verified-live-pending-truthful"
    }
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) `
        "p14.player-bounty.source-status"
    if ([string]$contract.status -ceq "implemented-build-pending")
    {
        Assert-Contract ([bool]$contract.buildEvidence.historicalCompiledEvidenceOnly -and
            [string]$contract.buildEvidence.historicalCompiledEvidenceDirectSourceCommit -ceq
                "6955b771580e324b770c1a8d809a5d094e75a75a" -and
            [string]$contract.buildEvidence.directSourceGitlink -ceq
                "10f2b88285969329effcfc3aba975c17118fd0b4" -and
            [string]$contract.buildEvidence.scope -cmatch
                'Current 10f2b882 source hashes authenticate source only' -and
            [string]$contract.liveGameplayEvidence.result -ceq "pending" -and
            $contract.requiredBeforeReady.Count -eq 2) `
            "p14.player-bounty.pending-evidence-truthful"
    }
    elseif ([string]$contract.status -ceq "implemented-build-verified-live-pending")
    {
        Assert-Contract (
            [string]$contract.buildEvidence.result -ceq "passed" -and
            [string]$contract.runtimeEvidence.result -ceq "passed" -and
            [string]$contract.liveGameplayEvidence.result -ceq "pending" -and
            $contract.requiredBeforeReady.Count -eq 1) `
            "p14.player-bounty.deployed-evidence-truthful"
    }
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) `
    "p14.player-bounty.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU player bounty level authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU player bounty level authority contract passed."
