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
$questRewardRecords = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading ([string]$contract.inventory.pattern) $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
        "p14.groundquest-xp.reward-callback.inventory-line-parsed"
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    Assert-Contract ($absolutePath.StartsWith(
        $scriptRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) `
        "p14.groundquest-xp.reward-callback.inventory-contained"
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $questRewardRecords.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
}
$questRewardRecords = @($questRewardRecords | Sort-Object)
$questRewardPaths = @($questRewardRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') `
        "p14.groundquest-xp.reward-callback.path-isolated"
    $Matches[1]
} | Sort-Object -Unique)
$expectedQuestRewardPaths = @($contract.inventory.sourcePaths | ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract ($questRewardRecords.Count -eq [int]$contract.inventory.handlers -and
    $questRewardRecords.Count -eq [int]$contract.expected.questRewardCallbacks -and
    $questRewardPaths.Count -eq [int]$contract.inventory.sourceFiles -and
    ($questRewardPaths -join "`n") -ceq ($expectedQuestRewardPaths -join "`n") -and
    (Get-TextSha256 ($questRewardRecords -join "`n")) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 ($questRewardPaths -join "`n")) -ceq [string]$contract.inventory.sourceSetSha256) `
    "p14.groundquest-xp.reward-callback.complete-inventory"

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
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.groundquest-xp.live-evidence"
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
