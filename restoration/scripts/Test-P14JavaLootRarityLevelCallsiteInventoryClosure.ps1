[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrcRoot = Join-Path $root "dsrc"
$srcRoot = Join-Path $root "src"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14JavaLootRarityLevelCallsiteInventoryClosure)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Get-TextSha256([string]$Text)
{
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing Java surface: $Signature" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { throw "Missing opening brace: $Signature" }
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
    throw "Missing closing brace: $Signature"
}

function Get-CategorySha256([object[]]$CategoryRecords)
{
    $canonical = (@($CategoryRecords | ForEach-Object {
        "$($_.Path)|$($_.Method)|$($_.Expression)"
    }) -join "`n") + "`n"
    return Get-TextSha256 $canonical
}

$directPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$nativePin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$directCommit = (& git -C $dsrcRoot rev-parse HEAD).Trim()
$nativeCommit = (& git -C $srcRoot rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $directPin.Count -eq 1 -and $nativePin.Count -eq 1 -and
    [string]$directPin[0].commit -ceq $directCommit -and
    [string]$nativePin[0].commit -ceq $nativeCommit -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $nativeCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "Loot-rarity closure is not pinned to checked-out direct source."

$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"

$pattern = [string]$contract.inventory.pattern
$matches = @($javaFiles | Select-String -Pattern $pattern)
$records = [Collections.Generic.List[object]]::new()
foreach ($match in $matches)
{
    $lines = Get-Content -LiteralPath $match.Path
    $method = ""
    for ($methodIndex = $match.LineNumber - 1; $methodIndex -ge 0; --$methodIndex)
    {
        if ($lines[$methodIndex] -match '^\s*(public|private|protected)\s+.*\([^;]*$')
        {
            $method = $lines[$methodIndex].Trim()
            break
        }
    }
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($method)) `
        "Could not classify loot-rarity reference: $($match.Path):$($match.LineNumber)"
    $records.Add([pscustomobject]@{
        Path = $match.Path.Substring($dsrcRoot.Length + 1).Replace("\", "/")
        Line = $match.LineNumber
        Method = $method
        Expression = $match.Line.Trim()
    })
}

$sortedRecords = @($records | Sort-Object Path, Line)
$sourceFiles = @($sortedRecords.Path | Sort-Object -Unique)
$canonical = (@($sortedRecords | ForEach-Object {
    "$($_.Path)|$($_.Method)|$($_.Expression)"
}) -join "`n") + "`n"
$sourceSet = ($sourceFiles -join "`n") + "`n"
$sourceContent = (@($sourceFiles | ForEach-Object {
    "$_=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dsrcRoot $_)).Hash.ToLowerInvariant()
}) -join "`n") + "`n"
Assert-Contract ($sortedRecords.Count -eq [int]$contract.inventory.callSites -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-TextSha256 $canonical) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Java loot-rarity callsite inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($sortedRecords | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
foreach ($property in @($contract.inventory.fileCounts.PSObject.Properties))
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Loot-rarity source-file count drifted: $($property.Name)"
}
Assert-Contract ($actualFileCounts.Count -eq
    @($contract.inventory.fileCounts.PSObject.Properties).Count) `
    "Loot-rarity source-file set changed."

$actualMethodCounts = @{}
foreach ($record in $sortedRecords)
{
    $name = [regex]::Match($record.Expression,
        '\b(getCashForLevel|getAdjustedCreatureLevel|generateTheftLootRare|generateTheftLoot|getRareForagedTreasureMap|getPlayerTreasureMapString)\s*\(').Groups[1].Value
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($name)) `
        "Could not identify loot-rarity method: $($record.Expression)"
    if (-not $actualMethodCounts.ContainsKey($name)) { $actualMethodCounts[$name] = 0 }
    ++$actualMethodCounts[$name]
}
foreach ($property in @($contract.inventory.methodCounts.PSObject.Properties))
{
    Assert-Contract ($actualMethodCounts.ContainsKey($property.Name) -and
        [int]$actualMethodCounts[$property.Name] -eq [int]$property.Value) `
        "Loot-rarity method count drifted: $($property.Name)"
}

$npcRecords = @($sortedRecords | Where-Object {
    ($_.Path -like "*/library/loot.java" -and
        $_.Expression -match '\b(getCashForLevel|getAdjustedCreatureLevel|generateTheftLootRare|generateTheftLoot)\s*\(') -or
    $_.Path -like "*/library/stealth.java"
})
$mapRecords = @($sortedRecords | Where-Object {
    ($_.Path -like "*/library/loot.java" -and
        $_.Expression -match '\b(getRareForagedTreasureMap|getPlayerTreasureMapString)\s*\(') -or
    $_.Path -like "*/player/player_utility.java"
})
$diagnosticRecords = @($sortedRecords | Where-Object { $_.Path -like "*/working/dantest.java" })
Assert-Contract ($npcRecords.Count -eq [int]$contract.classification.authoredNpcCashAndTheft.callSites -and
    (Get-CategorySha256 $npcRecords) -ceq
        [string]$contract.classification.authoredNpcCashAndTheft.inventorySha256 -and
    $mapRecords.Count -eq [int]$contract.classification.precuSkillBasedTreasureMaps.callSites -and
    (Get-CategorySha256 $mapRecords) -ceq
        [string]$contract.classification.precuSkillBasedTreasureMaps.inventorySha256 -and
    $diagnosticRecords.Count -eq [int]$contract.classification.godDiagnostic.callSites -and
    (Get-CategorySha256 $diagnosticRecords) -ceq
        [string]$contract.classification.godDiagnostic.inventorySha256 -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    ($npcRecords.Count + $mapRecords.Count + $diagnosticRecords.Count) -eq $sortedRecords.Count) `
    "Loot-rarity classification is incomplete."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required dependency is not Ready: $dependencyName"
}

$paths = [ordered]@{
    "library/loot.java" = Join-Path $scriptRoot "library/loot.java"
    "library/stealth.java" = Join-Path $scriptRoot "library/stealth.java"
    "player/player_utility.java" = Join-Path $scriptRoot "player/player_utility.java"
    "working/dantest.java" = Join-Path $scriptRoot "working/dantest.java"
    "systems/treasure_map/base/treasure_map.java" = Join-Path $scriptRoot "systems/treasure_map/base/treasure_map.java"
}
$text = @{}
foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant() -ceq
        [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
        "Loot-rarity source evidence drifted: $($entry.Key)"
    $text[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

$loot = $text["library/loot.java"]
$stealth = $text["library/stealth.java"]
$playerUtility = $text["player/player_utility.java"]
$treasureMap = $text["systems/treasure_map/base/treasure_map.java"]
$cash = Get-BracedSurface $loot `
    "public static int getCashForLevel(String mobType, int level) throws InterruptedException"
$adjusted = Get-BracedSurface $loot `
    "public static int getAdjustedCreatureLevel(obj_id target, String name) throws InterruptedException"
$rareTheft = Get-BracedSurface $loot `
    "public static boolean generateTheftLootRare(obj_id container, obj_id mark, int maxItems, obj_id thief) throws InterruptedException"
$normalTheft = Get-BracedSurface $loot `
    "public static boolean generateTheftLoot(obj_id container, obj_id mark, float chanceMod, int maxItems) throws InterruptedException"
$npcMoney = Get-BracedSurface $loot `
    "public static int getNpcMoney(obj_id target) throws InterruptedException"
$playerForaging = Get-BracedSurface $loot `
    "public static boolean playerForaging(obj_id player) throws InterruptedException"
$retiredForaging = Get-BracedSurface $loot `
    "private static boolean retiredNgePlayerForaging(obj_id player) throws InterruptedException"
$mapBand = Get-BracedSurface $loot `
    "public static String getPlayerTreasureMapString(obj_id player) throws InterruptedException"
$theft = Get-BracedSurface $stealth `
    "public static boolean doTheftLoot(obj_id thief, obj_id mark) throws InterruptedException"
$npcCash = Get-BracedSurface $stealth `
    "public static int getNpcCash(obj_id mark) throws InterruptedException"
$precuScoutMap = Get-BracedSurface $playerUtility "private obj_id givePrecuScoutForageMap("

Assert-Contract ($cash.Contains('dataTableGetInt(TBL_CREATURES, mobType, "minCash")') -and
    $cash.Contains('dataTableGetInt(TBL_CREATURES, mobType, "maxCash")') -and
    -not $cash.Contains("getLevel(") -and -not $cash.Contains("isPlayer(")) `
    "Cash rarity no longer has an authored creature-table boundary."
Assert-Contract ($adjusted.Contains("int level = getLevel(target);") -and
    $adjusted.Contains('dataTableGetInt("datatables/mob/creatures.iff", name, "difficultyClass")') -and
    $normalTheft.Contains("getAdjustedCreatureLevel(mark, name)") -and
    $normalTheft.Contains('getStringObjVar(mark, "loot.lootTable")') -and
    $normalTheft.Contains('getIntObjVar(mark, "intCombatDifficulty")') -and
    $npcMoney.Contains("int level = ai_lib.getLevel(target);") -and
    $npcCash.Contains("int level = ai_lib.getLevel(mark);")) `
    "NPC cash or normal-theft authored difficulty boundary drifted."

$bands = @("1_10", "11_20", "21_30", "31_40", "41_50", "51_60", "61_70", "71_80", "81_90")
foreach ($band in $bands)
{
    Assert-Contract ($rareTheft.Contains('"' + $band + '"') -and $mapBand.Contains('"' + $band + '"')) `
        "Retained treasure band is missing: $band"
}
Assert-Contract ($bands.Count -eq [int]$contract.expected.treasureMapBandRows -and
    $rareTheft.Contains('getIntObjVar(mark, "intCombatDifficulty")') -and
    -not $rareTheft.Contains("getLevel(") -and
    $mapBand.Contains("skill.getPrecuEncounterDifficulty(player)") -and
    -not $mapBand.Contains("getLevel(player)") -and
    $precuScoutMap.Contains("loot.getPlayerTreasureMapString(player)")) `
    "Treasure-map band authority drifted from authored NPC/PRE-CU skill inputs."

Assert-Contract ($theft.Contains("int markLevel = xp.getPrecuCombatLevel(mark);") -and
    $theft.Contains("int thiefLevel = xp.getPrecuCombatLevel(thief);") -and
    $theft.Contains("if (isPlayer(mark))") -and
    -not $theft.Contains("getLevel(") -and
    ([regex]::Matches($theft, 'loot[.]generateTheftLoot[(]').Count -eq 4) -and
    ([regex]::Matches($theft, 'loot[.]generateTheftLootRare[(]').Count -eq 1)) `
    "Retained theft compatibility escaped the PRE-CU player/NPC boundary."
Assert-Contract ($playerForaging.Contains("Rejected retired NGE Beast Master forage loot pipeline") -and
    $playerForaging.Contains("return false;") -and
    -not $playerForaging.Contains("retiredNgePlayerForaging(player)") -and
    ([regex]::Matches($retiredForaging, 'getRareForagedTreasureMap[(]').Count -eq 2)) `
    "Retired NGE player forage entry point became reachable."
Assert-Contract (([regex]::Matches($treasureMap, 'skill[.]getPrecuEncounterDifficulty[(]').Count -eq
        [int]$contract.expected.treasureMapEncounterAdapterCalls) -and
    -not $treasureMap.Contains("getLevel(") -and
    $treasureMap -notmatch '(?i)combat level|player level') `
    "Treasure-map encounter scaling no longer uses only the hidden PRE-CU adapter."

$groundLoot = Get-Content -LiteralPath (Join-Path $restorationRoot `
    "contracts/p14-precu-ground-loot-scout-forage-authority.json") -Raw | ConvertFrom-Json
$mobileStealth = Get-Content -LiteralPath (Join-Path $restorationRoot `
    "contracts/p14-precu-mobile-stealth-detection-authority.json") -Raw | ConvertFrom-Json
$combatXp = Get-Content -LiteralPath (Join-Path $restorationRoot `
    "contracts/p14-precu-combat-xp-authority.json") -Raw | ConvertFrom-Json
$encounter = Get-Content -LiteralPath (Join-Path $restorationRoot `
    "contracts/p14-precu-encounter-difficulty-authority.json") -Raw | ConvertFrom-Json
Assert-Contract ([int]$groundLoot.expected.treasureMapBandRows -eq $bands.Count -and
    [string]$groundLoot.expected.treasureMapDifficultyAuthority -ceq "skill.getPrecuEncounterDifficulty" -and
    [bool]$mobileStealth.expected.playerTheftAndDecoyInvocationRetired -and
    [bool]$mobileStealth.expected.retainedNpcTheftAndDecoyCompatibilityPreserved -and
    -not ([string]$combatXp.auditBoundary.notClaimedComplete).StartsWith("loot rarity") -and
    -not ([string]$encounter.auditBoundary.notClaimedComplete).StartsWith("loot rarity")) `
    "Dependency authority or reconciled audit boundary drifted."

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [int]$contract.expected.authoredNpcCashAndTheftCalls -eq $npcRecords.Count -and
    [int]$contract.expected.precuSkillBasedTreasureMapCalls -eq $mapRecords.Count -and
    [int]$contract.expected.godDiagnosticCalls -eq $diagnosticRecords.Count -and
    [int]$contract.expected.unclassifiedCalls -eq 0 -and
    -not [bool]$contract.expected.playerCombatLevelLootAuthority -and
    [bool]$contract.expected.playerSpyTheftInvocationRetired -and
    [bool]$contract.expected.npcTheftCompatibilityPreserved -and
    [bool]$contract.expected.retiredNgePlayerForageEntrypointInert -and
    [bool]$contract.expected.laterTreasureMapAndNpcContentPreserved) `
    "Loot-rarity expected authority boundary is incomplete."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.architecture -like "ELF 64-bit*" -and
        [string]$contract.buildEvidence.serverBinarySha256 -ceq
            "e126d8f5b0ff65bb908d2bce7922282aaceb4d2eaf454adbeb3eb51ff61720f8" -and
        [string]$contract.buildEvidence.serverBinaryBuildId -ceq
            "0ac0c8a439a388150c4a0f687874d1b38edc9eed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.containerHealth -ceq "healthy" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [int]$contract.runtimeEvidence.javaSources -eq 5717 -and
        [int]$contract.runtimeEvidence.javaClasses -eq 5751 -and
        [int]$contract.runtimeEvidence.liveGameProcessCount -eq 15 -and
        [int]$contract.runtimeEvidence.livePlanetProcessCount -eq 15 -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Loot-rarity callsite closure is not Ready."
    $container = [string]$contract.runtimeEvidence.container
    $state = (& docker inspect --format "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $container).Trim()
    $processNames = @(& docker exec $container ps -eo comm= | ForEach-Object { $_.Trim() })
    $binaryHash = ((& docker exec $container sha256sum /swg-precu/build/bin/SwgGameServer) -split '\s+')[0]
    Assert-Contract ($state -ceq "running healthy" -and
        @($processNames | Where-Object { $_ -ceq "SwgGameServer" }).Count -eq 15 -and
        @($processNames | Where-Object { $_ -ceq "PlanetServer" }).Count -eq 15 -and
        $binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256) `
        "Deployed PRE-CU x64 runtime topology or binary drifted."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) `
        "Loot-rarity callsite closure is not build-eligible."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Loot-rarity closure references forbidden host staging."

Write-Host "Publish 14.1 Java loot-rarity level callsite inventory closure passed."
