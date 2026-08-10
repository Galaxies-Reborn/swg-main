[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuGroundquestXpAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    if ([string]::IsNullOrEmpty($EndMarker)) { return $Text.Substring($start) }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

function Test-CallbackInventory(
    [object]$Inventory,
    [int]$ExpectedHandlers,
    [string]$Name)
{
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(& rg -n --no-heading ([string]$Inventory.pattern) `
        $scriptRoot --glob "*.java"))
    {
        Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
            "p14.groundquest-xp.$Name.inventory-line-parsed"
        $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
        Assert-Contract ($absolutePath.StartsWith(
            $scriptRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) `
            "p14.groundquest-xp.$Name.inventory-contained"
        $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
        $records.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
    }
    $records = @($records | Sort-Object)
    $paths = @($records | ForEach-Object {
        Assert-Contract ($_ -match '^(.*?):\d+\|') `
            "p14.groundquest-xp.$Name.path-isolated"
        $Matches[1]
    } | Sort-Object -Unique)
    $expectedPaths = @($Inventory.sourcePaths | ForEach-Object {
        [string]$_
    } | Sort-Object)
    Assert-Contract ($records.Count -eq [int]$Inventory.handlers -and
        $records.Count -eq $ExpectedHandlers -and
        $paths.Count -eq [int]$Inventory.sourceFiles -and
        ($paths -join "`n") -ceq ($expectedPaths -join "`n") -and
        (Get-TextSha256 ($records -join "`n")) -ceq [string]$Inventory.inventorySha256 -and
        (Get-TextSha256 ($paths -join "`n")) -ceq [string]$Inventory.sourceSetSha256) `
        "p14.groundquest-xp.$Name.complete-inventory"
    return $records
}

$sourcePaths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $sourcePaths[$property.Name] = Join-Path $source ([string]$property.Value)
}
$texts = @{}
foreach ($name in $sourcePaths.Keys)
{
    $path = $sourcePaths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.groundquest-xp.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) `
            "p14.groundquest-xp.source.$name.authenticated"
    }
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$questRewardRecords = @(Test-CallbackInventory $contract.inventory `
    ([int]$contract.expected.questRewardCallbacks) "reward-callback")
$questCompletionRecords = @(Test-CallbackInventory $contract.completionInventory `
    ([int]$contract.expected.questCompletionCallbacks) "completion-callback")
$questClearRecords = @(Test-CallbackInventory $contract.clearInventory `
    ([int]$contract.expected.questClearCallbacks) "clear-callback")

$groundquests = [string]$texts.groundquests
$reward = Get-SourceSlice $groundquests `
    "public static int getQuestExperienceReward(" `
    "public static void createQuestWaypoints("
Assert-Contract ($reward.Contains('dataTableGetInt(QUEST_EXPERIENCE_TABLE, "" + questLevel, tierColumns[questTier - 1])') -and
    -not $reward.Contains("getPrecuEncounterDifficulty") -and
    -not $groundquests.Contains("getQuestXpCap") -and
    -not $groundquests.Contains("datatables/player/player_level.iff")) `
    "p14.groundquest-xp.nge-player-level-cap-retired"
Assert-Contract ([regex]::Matches($groundquests,
        'dataTableGetInt\(QUEST_EXPERIENCE_TABLE,').Count -eq
        [int]$contract.expected.authoredQuestExperienceTableReads -and
    $reward.Contains("questLevel < 1") -and
    $reward.Contains("questTier > 6") -and
    $reward.Contains("tierColumns[questTier - 1]")) `
    "p14.groundquest-xp.authored-level-tier-table-preserved"

$basePlayer = [string]$texts.basePlayer
$questRewardCallback = Get-SourceSlice $basePlayer `
    "public int OnQuestReceivedReward(" `
    "public int OnQuestCompleted("
$ngeProgressionPatterns = @(
    '(?<![A-Za-z0-9_\.])getLevel\s*\(', '\bsetLevel\s*\(',
    '\bsetSkillTemplate\s*\(', '\bskill\.(grant|grantSkill|purchaseSkill)',
    '\bgrantSkill\s*\(', '\brevokeSkill\s*\(', '\bexpertise\.',
    '\bprofession\.'
)
$ngeProgressionMatches = @($ngeProgressionPatterns | Where-Object {
    [regex]::IsMatch($questRewardCallback, $_)
})
Assert-Contract ([int]$contract.inventory.productionContentDispatchers -eq 1 -and
    [regex]::Matches($questRewardCallback, 'groundquests\.grantQuestReward\s*\(').Count -eq
        [int]$contract.expected.questRewardContentDispatches -and
    [regex]::Matches($questRewardCallback, 'metrics\.doQuestMetrics\s*\(').Count -eq
        [int]$contract.expected.questRewardMetricsDispatches -and
    $questRewardCallback.Contains("groundquests.getQuestExperienceReward(self, questLevel, questTier, experienceAmount)") -and
    $questRewardCallback.Contains("grantGcwReward") -and
    $questRewardCallback.Contains("bankCredits") -and
    $questRewardCallback.Contains("exclusiveItemChoice") -and
    $ngeProgressionMatches.Count -eq [int]$contract.expected.questRewardNgePlayerProgressionMutations) `
    "p14.groundquest-xp.reward-callback.content-preserved-progression-isolated"

$completionProductionRecords = @($questCompletionRecords | Where-Object {
    $_ -notmatch '^test/'
})
$completionTestRecords = @($questCompletionRecords | Where-Object {
    $_ -match '^test/'
})
Assert-Contract ($completionProductionRecords.Count -eq
        [int]$contract.expected.questCompletionProductionCallbacks -and
    $completionTestRecords.Count -eq [int]$contract.expected.questCompletionTestCallbacks -and
    [int]$contract.completionInventory.productionHandlers -eq
        [int]$contract.expected.questCompletionProductionCallbacks -and
    [int]$contract.completionInventory.testHandlers -eq
        [int]$contract.expected.questCompletionTestCallbacks -and
    [int]$contract.clearInventory.productionHandlers -eq
        [int]$contract.expected.questClearCallbacks) `
    "p14.groundquest-xp.lifecycle-callback.classification"

$baseCompletion = Get-SourceSlice $basePlayer `
    "public int OnQuestCompleted(" "public int OnQuestCleared("
$baseClear = Get-SourceSlice $basePlayer `
    "public int OnQuestCleared(" "public int OnRequestStaticItemData("
$obiwanCompletion = Get-SourceSlice ([string]$texts.obiwanMonitor) `
    "public int OnQuestCompleted(" "public int OnSomeTaskActivated("
$testCompletion = Get-SourceSlice ([string]$texts.testQuestListener) `
    "public int OnQuestCompleted(" "public int OnQuestActivated("
$lifecycleBodies = $baseCompletion + "`n" + $baseClear + "`n" +
    $obiwanCompletion + "`n" + $testCompletion
$lifecycleProgressionPatterns = @(
    '(?<![A-Za-z0-9_\.])getLevel\s*\(', '\bsetLevel\s*\(',
    '\bgetCombatLevel\s*\(', '\bsetCombatLevel\s*\(',
    '\bgrantSkill\s*\(', '\brevokeSkill\s*\(',
    '\bsetSkillTemplate\s*\(', '\bsetJediState\s*\(',
    '\bgrantExperiencePoints\s*\(', '\bxp\.(grant|grantUnmodifiedExperience)',
    '\bexpertise\.', '\bprofession\.', '\broadmap\.'
)
$lifecycleProgressionMatches = @($lifecycleProgressionPatterns | Where-Object {
    [regex]::IsMatch($lifecycleBodies, $_)
})
Assert-Contract ($baseCompletion.Contains("groundquests.requestGrantQuest(self, conditionalQuestToGrant);") -and
    $baseCompletion.Contains("collection.grantQuestBasedCollections(questString, self);") -and
    $baseCompletion.Contains("smuggler.removeFromBountyTerminal(self, questCrc, false);") -and
    $baseClear.Contains("groundquests.applyQuestPenalty(self, factionName, factionAmount);") -and
    $baseClear.Contains("smuggler.removeFromBountyTerminal(self, questCrc, true);") -and
    [bool]$contract.expected.conditionalQuestChainsPreserved -and
    [bool]$contract.expected.questCollectionRewardsPreserved -and
    [bool]$contract.expected.smugglerBountyCleanupPreserved -and
    [bool]$contract.expected.authoredQuestClearPenaltiesPreserved) `
    "p14.groundquest-xp.base-lifecycle-content-preserved"
Assert-Contract ($obiwanCompletion.Contains('questName.indexOf("som_kenobi")') -and
    $obiwanCompletion.Contains('planetName.startsWith("mustafar")') -and
    $obiwanCompletion.Contains("mustafar.hasCompletedTrials(self)") -and
    $obiwanCompletion.Contains("mustafar.canCallObiwan(self)") -and
    $obiwanCompletion.Contains('messageTo(self, "callObiWanNow"') -and
    [bool]$contract.expected.mustafarObiwanSequencePreserved) `
    "p14.groundquest-xp.mustafar-completion-preserved"
Assert-Contract ($testCompletion.Contains('debugSpeakMsg(self, "OnQuestCompleted called with: " + questCrc);') -and
    $lifecycleProgressionMatches.Count -eq
        [int]$contract.expected.questLifecycleNgePlayerProgressionMutations) `
    "p14.groundquest-xp.lifecycle-progression-isolated"

$scriptFunctionTable = [string]$texts.scriptFunctionTable
$nativeRegistrations = [regex]::Matches($scriptFunctionTable,
    '\{Scripting::TRIG_QUEST_(COMPLETED|CLEARED|GRANT_REWARD),').Count
$nativeDispatchers = [regex]::Matches([string]$texts.playerObject,
    'trigAllScripts\(Scripting::TRIG_QUEST_(COMPLETED|CLEARED|GRANT_REWARD),').Count
Assert-Contract ($nativeRegistrations -eq
        [int]$contract.expected.nativeQuestLifecycleTriggerRegistrations -and
    $nativeDispatchers -eq [int]$contract.expected.nativeQuestLifecycleDispatchers) `
    "p14.groundquest-xp.native-lifecycle-boundary"

$dataGrantContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14DataGrantPersistenceClosure)) -Raw | ConvertFrom-Json
Assert-Contract ([string]$dataGrantContract.status -ceq "ready" -and
    [bool]$contract.expected.collectionDataGrantDependencyReady) `
    "p14.groundquest-xp.collection-data-grant-dependency"
Assert-Contract ([regex]::Matches($groundquests,
        'getQuestExperienceReward\s*\(').Count -eq
        [int]$contract.expected.groundquestRewardCalculations -and
    [regex]::Matches($basePlayer,
        'groundquests\.getQuestExperienceReward\s*\(').Count -eq
        [int]$contract.expected.rewardMetricCalculations) `
    "p14.groundquest-xp.reward-and-metric-calculations-preserved"
Assert-Contract ([regex]::Matches($groundquests,
        'xp\.grantCombatStyleXp\s*\(').Count -eq
        [int]$contract.expected.combatXpRoutes -and
    [regex]::Matches($groundquests,
        'xp\.grantCraftingQuestXp\s*\(').Count -eq
        [int]$contract.expected.craftingXpRoutes -and
    [regex]::Matches($groundquests,
        'xp\.grantSocialStyleXp\s*\(').Count -eq
        [int]$contract.expected.socialXpRoutes -and
    [regex]::Matches($groundquests,
        'xp\.grantUnmodifiedExperience\s*\(').Count -eq
        [int]$contract.expected.explicitOtherXpRoutes) `
    "p14.groundquest-xp.explicit-precu-routes-preserved"
Assert-Contract ($groundquests.Contains("money.bankTo(money.ACCT_NEW_PLAYER_QUESTS, player, bankCredits)") -and
    $groundquests.Contains("factions.setFactionStanding(player, factionName, currentFactionStanding + factionAmount)") -and
    $groundquests.Contains("static_item.createNewItemFunction(grantGcwRebReward, playerInv)")) `
    "p14.groundquest-xp.independent-rewards-preserved"

$xp = [string]$texts.xp
$unmodified = Get-SourceSlice $xp `
    "public static boolean grantUnmodifiedExperience(obj_id target, String xp_type, int amt, boolean verbose" `
    "public static boolean _grantUnmodifiedExperience("
$routes = Get-SourceSlice $xp `
    "public static int grantSocialStyleXp(" `
    "public static void displayXpMsg("
Assert-Contract ($unmodified.Contains("int currentXp = getExperiencePoints(target, xp_type);") -and
    $unmodified.Contains("int xpCap = getExperienceCap(target, xp_type);") -and
    $unmodified.Contains("return currentXp < xpCap;") -and
    $routes.Contains("return grant(player, directXpType, amount, false);") -and
    $routes.Contains("return grant(player, CRAFTING_GENERAL, amount, false);")) `
    "p14.groundquest-xp.precu-xp-pool-cap-preserved"

$playerObject = [string]$texts.playerObject
$nativeGrant = Get-SourceSlice $playerObject `
    "int PlayerObject::grantExperiencePoints(" `
    "bool PlayerObject::grantSchematicGroup("
Assert-Contract ($nativeGrant.Contains("int const limit = getExperienceLimit(experienceType);") -and
    $nativeGrant.Contains("if ((total > limit) && (limit >= 0))") -and
    $nativeGrant.Contains("total = limit;") -and
    $nativeGrant.Contains("m_experiencePoints.set(experienceType, total);")) `
    "p14.groundquest-xp.native-xp-limit-preserved"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.groundquest-xp.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.groundquest-xp.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.groundquests -match
            '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.basePlayer -match
            '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.obiwanMonitor -match
            '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        [int]$contract.runtimeEvidence.liveGameProcessCount -eq 15 -and
        [int]$contract.runtimeEvidence.liveGameProcessesMappedBuiltBinary -eq 15 -and
        [bool]$contract.runtimeEvidence.clientResponsive -and
        [int]$contract.runtimeEvidence.hostArtifactOrStagingDirectories -eq 0) `
        "p14.groundquest-xp.live-evidence"

    $container = [string]$contract.runtimeEvidence.container
    $health = (& docker inspect $container --format '{{.State.Health.Status}}').Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $health -ceq "healthy") `
        "p14.groundquest-xp.live-container-health"
    foreach ($property in $contract.sourceFiles.PSObject.Properties)
    {
        $relativePath = ([string]$property.Value).Replace("\", "/")
        & docker exec $container cmp -s "/swg-precu-source/$relativePath" `
            "/swg-precu/$relativePath"
        Assert-Contract ($LASTEXITCODE -eq 0) `
            "p14.groundquest-xp.source-work-parity.$($property.Name)"
    }

    $classPaths = [ordered]@{
        groundquests = "/swg-precu/data/sku.0/sys.server/compiled/game/script/library/groundquests.class"
        basePlayer = "/swg-precu/data/sku.0/sys.server/compiled/game/script/player/base/base_player.class"
        obiwanMonitor = "/swg-precu/data/sku.0/sys.server/compiled/game/script/theme_park/dungeon/mustafar_trials/obiwan_finale/obiwan_quest_monitor.class"
    }
    foreach ($name in $classPaths.Keys)
    {
        $classHash = ((& docker exec $container sha256sum $classPaths[$name]).Trim() -split '\s+')[0]
        $classBytes = [int]((& docker exec $container stat -c '%s' $classPaths[$name]).Trim())
        Assert-Contract ($classHash -ceq
                [string]$contract.buildEvidence.compiledClassSha256.PSObject.Properties[$name].Value -and
            $classBytes -eq
                [int]$contract.buildEvidence.compiledClassBytes.PSObject.Properties[$name].Value) `
            "p14.groundquest-xp.live-bytecode.$name"
    }

    $serverPid = (& docker exec $container pgrep -n SwgGameServer).Trim()
    $serverExe = (& docker exec $container readlink -f "/proc/$serverPid/exe").Trim()
    $binaryHash = ((& docker exec $container sha256sum $serverExe).Trim() -split '\s+')[0]
    $buildLine = @(& docker exec $container readelf -n $serverExe | Select-String 'Build ID:')
    $buildId = ($buildLine[0].Line -replace '^.*Build ID:\s*', '').Trim()
    Assert-Contract ($binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $buildId -ceq [string]$contract.buildEvidence.serverBinaryBuildId) `
        "p14.groundquest-xp.live-binary-identity"

    $client = Get-Process -Id ([int]$contract.runtimeEvidence.clientProcessId) `
        -ErrorAction SilentlyContinue
    Assert-Contract ($null -ne $client -and $client.Responding -and
        $client.ProcessName -ceq [string]$contract.runtimeEvidence.clientProcessName) `
        "p14.groundquest-xp.client-responsive"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.groundquest-xp.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.groundquest-xp.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU ground-quest XP authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU ground-quest XP authority contract passed."
