[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.rebornForceProgressionGate)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Gate([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-Source([string]$RelativePath)
{
    return Get-Content -LiteralPath (Join-Path $repositoryRoot $RelativePath) -Raw
}

function Get-JavaMethodBody([string]$Text, [string]$MethodName)
{
    $match = [regex]::Match($Text, "(?m)^[ \t]*(?:public|private|protected)[ \t]+(?:static[ \t]+)?[A-Za-z0-9_<>\[\]]+[ \t]+" + [regex]::Escape($MethodName) + "[ \t]*\(")
    if (-not $match.Success) { return "" }
    $open = $Text.IndexOf("{", $match.Index + $match.Length)
    if ($open -lt 0) { return "" }
    $depth = 0; $inString = $false; $escaped = $false
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        $character = $Text[$index]
        if ($escaped) { $escaped = $false; continue }
        if ($inString -and $character -eq '\') { $escaped = $true; continue }
        if ($character -eq '"') { $inString = -not $inString; continue }
        if ($inString) { continue }
        if ($character -eq '{') { $depth++ }
        elseif ($character -eq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($open, $index - $open + 1) }
        }
    }
    return ""
}

function Assert-IntConstant([string]$Text, [string]$Name, [int]$Expected)
{
    $pattern = "(?m)^[ \t]*public[ \t]+static[ \t]+final[ \t]+int[ \t]+" + [regex]::Escape($Name) + "[ \t]*=[ \t]*" + $Expected + "[ \t]*;"
    Assert-Gate ([regex]::IsMatch($Text, $pattern)) "constant.$Name=$Expected"
}

Write-Host "Reborn Force progression authoritative-source gate:"

Assert-Gate (
    [string]$contract.feature -ceq "reborn-force-progression" -and
    [string]$contract.status -ceq "authoritative-source-increment" -and
    -not [bool]$contract.acceptance.activationAuthorized -and
    -not [bool]$contract.modeContract.declaredInRuntimeConfig) `
    "contract.authoritative-source-but-inactive"

$sourceProperties = @(
    "progressionLibrary", "checkHandler", "commandTable", "threadBridge",
    "questNetworkTable", "mentorScript", "worldSpawner", "planetSpawnerHook",
    "bartenderHook", "skillPurchaseAuthority", "padawanAuthority",
    "legacyQuestAuthority", "villageAuthority", "legacyKickoffRetirement",
    "legacyDatapadRetirement", "legacyWomanRetirement", "localizationGenerator",
    "localizationTable", "clientTreBuilder", "clientTreRegression", "clientTreArtifact",
    "serverArtifactRegression", "questNetworkArtifact", "commandTableArtifact", "buildEvidence",
    "runtimeFixture", "runtimeSmoke", "smokeCompose", "smokeClientCompose", "runtimeModeBridge"
)
foreach ($propertyName in $sourceProperties)
{
    $relativePath = [string]$contract.sourceIncrement.$propertyName
    Assert-Gate (-not [string]::IsNullOrWhiteSpace($relativePath) -and (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) -PathType Leaf)) "source.exists.$propertyName"
}

$progression = Get-Source ([string]$contract.sourceIncrement.progressionLibrary)
$player = Get-Source ([string]$contract.sourceIncrement.checkHandler)
$threadSource = Get-Source ([string]$contract.sourceIncrement.threadBridge)
$mentor = Get-Source ([string]$contract.sourceIncrement.mentorScript)
$spawner = Get-Source ([string]$contract.sourceIncrement.worldSpawner)
$planet = Get-Source ([string]$contract.sourceIncrement.planetSpawnerHook)
$bartender = Get-Source ([string]$contract.sourceIncrement.bartenderHook)
$skill = Get-Source ([string]$contract.sourceIncrement.skillPurchaseAuthority)
$trials = Get-Source ([string]$contract.sourceIncrement.padawanAuthority)
$quests = Get-Source ([string]$contract.sourceIncrement.legacyQuestAuthority)
$village = Get-Source ([string]$contract.sourceIncrement.villageAuthority)
$kickoff = Get-Source ([string]$contract.sourceIncrement.legacyKickoffRetirement)
$datapad = Get-Source ([string]$contract.sourceIncrement.legacyDatapadRetirement)
$woman = Get-Source ([string]$contract.sourceIncrement.legacyWomanRetirement)
$runtimeFixture = Get-Source ([string]$contract.sourceIncrement.runtimeFixture)
$runtimeSmoke = Get-Source ([string]$contract.sourceIncrement.runtimeSmoke)
$smokeCompose = Get-Source ([string]$contract.sourceIncrement.smokeCompose)
$smokeClientCompose = Get-Source ([string]$contract.sourceIncrement.smokeClientCompose)
$runtimeModeBridge = Get-Source ([string]$contract.sourceIncrement.runtimeModeBridge)

$shadowMode = Get-JavaMethodBody $progression "isShadowEnabled"
$replacementMode = Get-JavaMethodBody $progression "isReplacementEnabled"
Assert-Gate (
    $shadowMode.Contains('getConfigSetting(CONFIG_SECTION, CONFIG_KEY)') -and
    $shadowMode.Contains('MODE_SHADOW.equals(mode)') -and
    $replacementMode.Contains('getConfigSetting(CONFIG_SECTION, CONFIG_KEY)') -and
    $replacementMode.Contains('MODE_REPLACEMENT.equals(mode)') -and
    -not $shadowMode.Contains('equalsIgnoreCase') -and
    -not $replacementMode.Contains('equalsIgnoreCase')) `
    "mode.exact-single-boundary"

$configMatches = @(& git -C (Join-Path $repositoryRoot "exe") grep -n -I -- "rebornForceProgressionMode" 2>$null)
Assert-Gate ($LASTEXITCODE -eq 1 -and $configMatches.Count -eq 0) "mode.absent-from-runtime-config"

Assert-Gate (
    $runtimeModeBridge.Contains('SWG_REBORN_FORCE_PROGRESSION_MODE') -and
    $runtimeModeBridge.Contains('off|shadow|replacement') -and
    $runtimeModeBridge.Contains('rebornForceProgressionMode=${SWG_REBORN_FORCE_PROGRESSION_MODE}') -and
    $smokeCompose.Contains('name: swg-force-progression-smoke') -and
    $smokeCompose.Contains('SWG_REBORN_FORCE_PROGRESSION_MODE: replacement') -and
    $smokeCompose.Contains('external: true') -and
    -not [regex]::IsMatch($smokeCompose, '(?m)^\s+ports:\s*$') -and
    $smokeClientCompose.Contains('SWG_PUBLIC_CONNECTION_PING_PORT: "46462"') -and
    $smokeClientCompose.Contains('SWG_PUBLIC_CONNECTION_PORT: "46463"') -and
    $smokeClientCompose.Contains('SWG_PRIVATE_CONNECTION_PORT: "46464"') -and
    $smokeClientCompose.Contains('127.0.0.1:46450-46461:44450-44461/tcp') -and
    $smokeClientCompose.Contains('127.0.0.1:46465:44465/udp') -and
    -not [regex]::IsMatch($smokeClientCompose, '(?m)^\s+-\s+"?(?!127\.0\.0\.1:)[0-9]')) `
    "mode.isolated-optional-runtime-bridge"

Assert-Gate (
    $runtimeFixture.Contains('class reborn_force_progression_runtime') -and
    $runtimeFixture.Contains('rows != 24') -and
    $runtimeFixture.Contains('echoes != 16') -and
    $runtimeFixture.Contains('threads != 7') -and
    $runtimeFixture.Contains('convergences != 1') -and
    $runtimeFixture.Contains('routes.size() != 6') -and
    $runtimeFixture.Contains('planets.size() != 10') -and
    $runtimeFixture.Contains('branches.size() != 16') -and
    $runtimeFixture.Contains('hasScript(candidate, MENTOR_SCRIPT)') -and
    $runtimeFixture.Contains('hasCondition(candidate, CONDITION_CONVERSABLE)') -and
    $runtimeFixture.Contains('playerLoaded=') -and
    $runtimeSmoke.Contains('test.reborn_force_progression_runtime') -and
    $runtimeSmoke.Contains('expectedSpawns = "4"') -and
    $runtimeSmoke.Contains('loadedSpawns = "4"')) `
    "runtime.read-only-network-acceptance-fixture"

Assert-Gate (
    $runtimeFixture.Contains('PLAYER_STATION_ID = 1001') -and
    $runtimeFixture.Contains('value.matches("[0-9a-f]{32}")') -and
    $runtimeFixture.Contains('getCleanPlayerError(player)') -and
    $runtimeFixture.Contains('quests.isActive(questName, player)') -and
    $runtimeFixture.Contains('jedi_trials.PADAWAN_INITIATE_SKBOX') -and
    $runtimeFixture.Contains('jedi_trials.JEDI_PADAWAN_SKBOX') -and
    $runtimeFixture.Contains('finally') -and
    $runtimeFixture.Contains('clearControlledPlayerState(player)') -and
    $runtimeFixture.Contains('force_progression.reconcilePlayer(player)') -and
    $runtimeFixture.Contains('MONTHLY_HINT_COOLDOWN_SECONDS - 1') -and
    $runtimeFixture.Contains('QUEST_RESULT_WRONG') -and
    $runtimeFixture.Contains('QUEST_RESULT_WAIT') -and
    $runtimeFixture.Contains('force_progression.isPreConvergenceEligible(player)') -and
    $runtimeFixture.Contains('JEDI_STATE_FORCE_SENSITIVE') -and
    $runtimeFixture.Contains('VAR_AWAKENING_NOTIFIED') -and
    $runtimeFixture.Contains('force_progression.tryBartenderHint(player, bartenderAt)') -and
    $runtimeFixture.Contains('force_progression.purchaseNextSkillInBranch') -and
    $runtimeFixture.Contains('force_progression.isPadawanReady(player)') -and
    $runtimeFixture.Contains('jedi_trials.isEligibleForJediPadawanTrials(player)') -and
    $runtimeFixture.Contains('insightEarned=64') -and
    $runtimeFixture.Contains('restored=true') -and
    $runtimeSmoke.Contains('[switch]$ExercisePlayer') -and
    $runtimeSmoke.Contains('$ContainerName -cne "swg-force-progression-smoke"') -and
    $runtimeSmoke.Contains('com.docker.compose.project') -and
    $runtimeSmoke.Contains('player $PlayerOid $lifecycle') -and
    $runtimeSmoke.Contains('padawanInitialized = "true"') -and
    [bool]$contract.sourceIncrement.authenticatedPlayerLifecycleFixtureImplemented -and
    [string]$contract.acceptance.authenticatedPlayerLifecycle.status -ceq 'java11-compiled-ready-not-run') `
    "runtime.authenticated-player-lifecycle-fail-closed-and-reversible"

$constantExpectations = [ordered]@{
    REQUIRED_ECHO_EVENTS = 8; REQUIRED_THREAD_EVENTS = 3;
    REQUIRED_CONVERGENCE_EVENTS = 1; REQUIRED_TOTAL_EVENTS = 12;
    MAX_ATTUNEMENT_EVENTS = 32; REQUIRED_ROUTE_FAMILIES = 6;
    REQUIRED_PLANETS = 5; MONTHLY_HINT_COOLDOWN_SECONDS = 2592000;
    BARTENDER_HINT_CHANCE_PERCENT = 15; BARTENDER_ROLL_COOLDOWN_SECONDS = 86400;
    FS_TREE_COUNT = 4; FS_BRANCH_COUNT = 16; FS_TIER_BOX_COUNT = 64;
    FS_POINTS_PER_QUEST_CHAIN = 4; FS_POINTS_REQUIRED_FOR_ALL_TREES = 64;
    MAX_FS_QUEST_CHAINS = 24
}
foreach ($constant in $constantExpectations.GetEnumerator())
{
    Assert-IntConstant $progression ([string]$constant.Key) ([int]$constant.Value)
}

$observe = Get-JavaMethodBody $progression "observeAttunement"
$eligible = Get-JavaMethodBody $progression "isForceSensitivityEligible"
Assert-Gate (
    $observe.Contains('isLegacyEvent(eventId)') -and
    $observe.Contains('containsEvent(records, eventId)') -and
    $observe.Contains('records.length >= MAX_ATTUNEMENT_EVENTS') -and
    -not $observe.Contains('countType(records, EVENT_ECHO) >= REQUIRED_ECHO_EVENTS') -and
    -not $observe.Contains('countType(records, EVENT_THREAD) >= REQUIRED_THREAD_EVENTS') -and
    $progression.Contains('private static boolean isPreConvergenceEligible(String[] records)') -and
    $progression.Contains('countType(records, EVENT_ECHO) >= REQUIRED_ECHO_EVENTS') -and
    $progression.Contains('countType(records, EVENT_THREAD) >= REQUIRED_THREAD_EVENTS') -and
    $eligible.Contains('countDistinctRoutes(records) >= REQUIRED_ROUTE_FAMILIES') -and
    $eligible.Contains('countDistinctPlanets(records) >= REQUIRED_PLANETS')) `
    "unlock.minimum-diversity-with-detour-capacity"

$reconcile = Get-JavaMethodBody $progression "reconcilePlayer"
$awakening = Get-JavaMethodBody $progression "awakenIfEligible"
$notify = Get-JavaMethodBody $progression "sendAwakeningNotification"
$ledgerRebuild = Get-JavaMethodBody $progression "rebuildFsCurrencyLedgers"
Assert-Gate (
    @([regex]::Matches($player, 'force_progression\.reconcilePlayer\(self\);')).Count -eq 2 -and
    $reconcile.Contains('migrateLegacyForceSensitiveState(player)') -and
    $reconcile.Contains('retireLegacyPlayerProgression(player)') -and
    $awakening.Contains('setJediState(player, JEDI_STATE_FORCE_SENSITIVE)') -and
    $awakening.Contains('VAR_AWAKENING_PENDING') -and
    $notify.Contains('new string_id(STF, "awakening")') -and
    $notify.IndexOf('sendSystemMessage(', [StringComparison]::Ordinal) -lt $notify.LastIndexOf('VAR_AWAKENING_NOTIFIED', [StringComparison]::Ordinal) -and
    $ledgerRebuild.Contains('VAR_FS_AWARD_IDS') -and
    $ledgerRebuild.Contains('VAR_FS_PURCHASE_IDS')) `
    "migration-awakening-and-ledgers.replayable"

$checkBody = Get-JavaMethodBody $player "cmdCheckForceStatus"
$handleCheck = Get-JavaMethodBody $progression "handleCheckCommand"
Assert-Gate (
    $checkBody.Contains('force_progression.handleCheckCommand(self, params);') -and
    $handleCheck.Contains('params.trim().equalsIgnoreCase("hint")') -and
    $progression.Contains('new string_id(STF, "check_insight")') -and
    $progression.Contains('new string_id(STF, "check_trees")') -and
    -not $progression.Contains('sendSystemMessageTestingOnly')) `
    "check.localized-status-and-monthly-hint"

$commandPath = Join-Path $repositoryRoot ([string]$contract.sourceIncrement.commandTable)
$commandRows = @(Get-Content -LiteralPath $commandPath | ForEach-Object {
    $fields = ([string]$_).Split("`t")
    if ($fields.Count -ge 4 -and ($fields[0] -ceq "check" -or $fields[0] -ceq "checkForceStatus")) { [pscustomobject]@{ Name = $fields[0]; Handler = $fields[3] } }
})
Assert-Gate (
    @($commandRows | Where-Object { $_.Name -ceq "check" -and $_.Handler -ceq "cmdCheckForceStatus" }).Count -eq 1 -and
    @($commandRows | Where-Object { $_.Name -ceq "checkForceStatus" -and $_.Handler -ceq "cmdCheckForceStatus" }).Count -eq 1) `
    "check.command-aliases"

$tablePath = Join-Path $repositoryRoot ([string]$contract.sourceIncrement.questNetworkTable)
$tableLines = @(Get-Content -LiteralPath $tablePath)
$headers = @($tableLines[0].Split("`t"))
$rows = @($tableLines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $headers)
$fieldWidthsValid = @($tableLines | Select-Object -Skip 2 | Where-Object { ([string]$_).Split("`t").Count -ne $headers.Count }).Count -eq 0
$catalog = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$contract.questNetwork.catalog)) -Raw | ConvertFrom-Json
$catalogIds = @($catalog.questChains | ForEach-Object { [string]$_.id } | Sort-Object)
$tableIds = @($rows | ForEach-Object { [string]$_.id } | Sort-Object)
Assert-Gate (
    $headers.Count -eq 14 -and $fieldWidthsValid -and $rows.Count -eq 24 -and
    @($rows | Where-Object { $_.event_type -ceq "ECHO" }).Count -eq 16 -and
    @($rows | Where-Object { $_.event_type -ceq "THREAD" }).Count -eq 7 -and
    @($rows | Where-Object { $_.event_type -ceq "CONVERGENCE" }).Count -eq 1 -and
    @($rows | ForEach-Object { $_.planet } | Sort-Object -Unique).Count -eq 10 -and
    @($rows | ForEach-Object { $_.route_family } | Sort-Object -Unique).Count -eq 6 -and
    @($rows | ForEach-Object { $_.branch } | Sort-Object -Unique).Count -eq 16 -and
    @($rows | Where-Object { [int]$_.answer_1 -notin 0,1,2 -or [int]$_.answer_2 -notin 0,1,2 -or [int]$_.answer_3 -notin 0,1,2 -or [int]$_.delay_seconds -ne 300 }).Count -eq 0 -and
    ($catalogIds -join '|') -ceq ($tableIds -join '|')) `
    "quest-network.24-spawns-16-echo-7-thread-1-convergence"

Assert-Gate (
    $spawner.Contains('dataTableGetNumRows(force_progression.QUEST_NETWORK_TABLE)') -and
    $spawner.Contains('create.object(row.getString("npc_type"), spawnLocation)') -and
    $spawner.Contains('getHeightAtLocation') -and
    $spawner.Contains('VAR_NPC_OWNER') -and
    $spawner.Contains('cleanup(self)') -and
    $planet.Contains('force_progression.isReplacementEnabled()') -and
    $planet.Contains('systems.reborn.force_progression.world_spawner')) `
    "quest-network.planet-owned-reconciling-spawner"

Assert-Gate (
    $mentor.Contains('force_progression.beginQuestChain') -and
    $mentor.Contains('force_progression.answerQuestChain') -and
    $mentor.Contains('force_progression.isQuestChainCompleted(player, questId)') -and
    $mentor.Contains('force_progression.purchaseNextSkillInBranch') -and
    $mentor.Contains('new string_id(force_progression.STF') -and
    -not $mentor.Contains('sendSystemMessageTestingOnly')) `
    "quest-network.localized-trial-and-error-mentor"

$purchase = Get-JavaMethodBody $progression "purchaseFsSkill"
$skillPurchase = Get-JavaMethodBody $skill "purchaseSkill"
$skillPointCost = Get-JavaMethodBody $skill "getSkillPointCost"
$masterGrant = Get-JavaMethodBody $progression "grantEligibleTreeMasters"
Assert-Gate (
    $skillPurchase.Contains('force_progression.isReplacementEnabled()') -and
    $skillPurchase.Contains('return force_progression.purchaseFsSkill(player, skillName);') -and
    $purchase.Contains('hasCompletedMentorForSkill(player, skillName)') -and
    $purchase.Contains('spendFsQuestPoint(player, skillName)') -and
    $skillPointCost.Contains('force_progression.isReplacementEnabled() && skillName.startsWith("force_sensitive_")') -and
    $skillPointCost.Contains('return 0;') -and
    $masterGrant.Contains('getSkillPrerequisiteSkills(masterSkill)') -and
    -not $purchase.Contains('getAvailableSkillPoints')) `
    "fs-learning.mentor-gated-Insight-authority"

$padawanEligibility = Get-JavaMethodBody $trials "isEligibleForJediPadawanTrials"
$padawanInitialize = Get-JavaMethodBody $trials "initializePadawanTrials"
Assert-Gate (
    $padawanEligibility.Contains('force_progression.isPadawanReady(player)') -and
    $padawanInitialize.Contains('force_progression.isReplacementEnabled() && !force_progression.isPadawanReady(player)') -and
    (Get-JavaMethodBody $progression "isPadawanReady").Contains('hasLearnedAllFsTrees(player)')) `
    "padawan.all-four-trees-at-authority"

$bartenderHint = Get-JavaMethodBody $progression "tryBartenderHint"
Assert-Gate (
    $bartender.Contains('force_progression.tryBartenderHint(speaker, getCalendarTime())') -and
    $bartender.Contains('new string_id(force_progression.STF, forceHint)') -and
    $bartenderHint.Contains('getJediState(player) < JEDI_STATE_FORCE_SENSITIVE') -and
    $bartenderHint.Contains('BARTENDER_ROLL_COOLDOWN_SECONDS') -and
    $bartenderHint.Contains('rand(1, 100) > BARTENDER_HINT_CHANCE_PERCENT')) `
    "bartender.post-awakening-optional-bounded-hint"

$questActivate = Get-JavaMethodBody $quests "activate"
Assert-Gate (
    $questActivate.Contains('force_progression.isRetiredLegacyQuest(questName)') -and
    $kickoff.Contains('force_progression.isReplacementEnabled()') -and
    $datapad.Contains('force_progression.isReplacementEnabled()') -and
    $woman.Contains('force_progression.isReplacementEnabled()') -and
    (Get-JavaMethodBody $village "isVillageEligible").Contains('force_progression.isReplacementEnabled()') -and
    (Get-JavaMethodBody $village "makeVillageEligible").Contains('force_progression.isReplacementEnabled()') -and
    (Get-JavaMethodBody $village "unlockBranch").Contains('force_progression.isReplacementEnabled()') -and
    (Get-JavaMethodBody $village "showBranchUnlockSUI").Contains('force_progression.isReplacementEnabled()') -and
    (Get-JavaMethodBody $village "unlockBranchSUI").Contains('force_progression.isReplacementEnabled()')) `
    "legacy.old-man-sith-mellichae-village-retired"

$allImplemented = $true
foreach ($property in @("forceSensitiveAwardAuthorityImplemented", "legacyRetirementHooksImplemented", "villageNpcQuestScriptsImplemented", "bartenderHookImplemented", "fsSkillPurchaseAuthorityImplemented", "padawanAuthorityImplemented", "playerMigrationImplemented", "localizedMessagesImplemented", "clientLocalizationPackageImplemented", "serverDataArtifactsImplemented"))
{
    if (-not [bool]$contract.sourceIncrement.$property) { $allImplemented = $false }
}
Assert-Gate ($allImplemented -and [string]$contract.legacyRetirement.status -ceq "replacement-guarded-source-complete") "contract.all-authorities-implemented"

& (Join-Path $repositoryRoot ([string]$contract.sourceIncrement.localizationGenerator)) -Check | Out-Host
$stfPath = Join-Path $repositoryRoot ([string]$contract.sourceIncrement.localizationTable)
$stream = [IO.File]::OpenRead($stfPath)
$reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::UTF8, $false)
$localizedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
try
{
    $magic = $reader.ReadUInt32(); $version = $reader.ReadByte(); $nextId = $reader.ReadUInt32(); $count = $reader.ReadUInt32()
    for ($index = 0; $index -lt $count; ++$index)
    {
        [void]$reader.ReadUInt32(); [void]$reader.ReadUInt32(); $length = $reader.ReadUInt32(); [void]$reader.ReadBytes([int]$length * 2)
    }
    for ($index = 0; $index -lt $count; ++$index)
    {
        [void]$reader.ReadUInt32(); $length = $reader.ReadUInt32(); [void]$localizedNames.Add([Text.Encoding]::ASCII.GetString($reader.ReadBytes([int]$length)))
    }
}
finally { $reader.Dispose(); $stream.Dispose() }
$requiredLocalization = @("awakening", "migration_complete", "check_strong", "check_insight", "check_trees", "padawan_ready")
$requiredLocalization += @($rows | ForEach-Object { "npc_" + $_.id; "quest_" + $_.id + "_cue" })
$requiredLocalization += @($rows | ForEach-Object { $_.route_family.ToLowerInvariant() } | Sort-Object -Unique | ForEach-Object {
    $route = $_
    foreach ($stage in 1..3)
    {
        "route_${route}_step_$stage"
        foreach ($choice in 0..2) { "route_${route}_step_${stage}_choice_$choice" }
    }
})
$missingLocalization = @($requiredLocalization | Where-Object { -not $localizedNames.Contains($_) })
Assert-Gate ($magic -eq 0xabcd -and $version -eq 1 -and $nextId -eq $count + 1 -and $count -eq 163 -and $missingLocalization.Count -eq 0) "localization.canonical-163-entry-table"

& (Join-Path $repositoryRoot ([string]$contract.sourceIncrement.clientTreRegression)) | Out-Host
& (Join-Path $repositoryRoot ([string]$contract.sourceIncrement.serverArtifactRegression)) | Out-Host

$buildEvidence = Get-Content -LiteralPath (Join-Path $repositoryRoot ([string]$contract.sourceIncrement.buildEvidence)) -Raw | ConvertFrom-Json
Assert-Gate (
    -not [bool]$buildEvidence.environment.dependenciesStarted -and
    -not [bool]$buildEvidence.environment.oracleStarted -and
    -not [bool]$buildEvidence.environment.gameServerStarted -and
    [string]$buildEvidence.successfulTargets.compileJava.status -ceq "passed" -and
    [int]$buildEvidence.successfulTargets.compileJava.sourceFiles -eq 5745 -and
    [string]$buildEvidence.successfulTargets.compileTab.status -ceq "passed" -and
    [string]$buildEvidence.successfulTargets.compileSrc.status -ceq "passed" -and
    [int]$buildEvidence.successfulTargets.compileSrc.serverExecutables -eq 13 -and
    [string]$buildEvidence.successfulTargets.compileChat.status -ceq "passed" -and
    [int]$buildEvidence.successfulTargets.compileChat.chatExecutables -eq 2) `
    "build-evidence.non-live-java-data-native-chat-passed"

Assert-Gate (
    [int]$buildEvidence.successfulTargets.compileMiff.sourceFiles -eq 336 -and
    [int]$buildEvidence.successfulTargets.compileMiff.missingOutputs -eq 0 -and
    [string]$buildEvidence.blockedTargets.compileTpf.antStatus -ceq "reported-success" -and
    [int]$buildEvidence.blockedTargets.compileTpf.sourceFiles -eq 63456 -and
    [int]$buildEvidence.blockedTargets.compileTpf.compilerErrorLines -eq 17595 -and
    -not [bool]$buildEvidence.blockedTargets.compileTpf.acceptedAsClean -and
    -not [bool]$buildEvidence.blockedTargets.compileTpf.featureIntroducesTpfChanges -and
    [string]$buildEvidence.blockedTargets.loadTemplates.status -ceq "not-run" -and
    [string]$buildEvidence.blockedTargets.fullCompile.status -ceq "blocked") `
    "build-evidence.template-errors-explicitly-block-full-build"

$acceptDelivery = Get-JavaMethodBody $threadSource "acceptDelivery"
Assert-Gate (
    $acceptDelivery.Contains('force_progression.observeAttunement(') -and
    $acceptDelivery.Contains('force_progression.EVENT_THREAD') -and
    $acceptDelivery.Contains('force_progression.ROUTE_FELLOWSHIP') -and
    $acceptDelivery.Contains('"galactic"')) `
    "thread-bridge.optional-fellowship-credit"

& (Join-Path $PSScriptRoot "Test-RebornForceProgressionModel.ps1") | Out-Host

if ($failures.Count -gt 0)
{
    throw "Reborn Force progression gate failed: $($failures -join ', ')"
}

Write-Host "Reborn Force progression authoritative source passed; runtime activation remains intentionally absent."
