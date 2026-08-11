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
$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14JavaCombatLevelTextualInventoryClosure)
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

function Get-CanonicalRecord([object]$Record)
{
    return "$($Record.Path):$($Record.Line):$($Record.Column)|$($Record.Value)|$($Record.Expression)"
}

function Get-InventorySha256([object[]]$Records)
{
    $rows = @($Records | ForEach-Object { Get-CanonicalRecord $_ } | Sort-Object)
    return Get-TextSha256 ($rows -join "`n")
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

function Get-JavaText([string]$RelativePath)
{
    return Get-Content -LiteralPath (Join-Path $scriptRoot $RelativePath) -Raw
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
    "Java combatLevel closure is not pinned to checked-out direct source."

$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"
Assert-Contract ($null -ne (Get-Command rg -ErrorAction SilentlyContinue)) `
    "ripgrep is required for the exact Java combatLevel inventory."

$categoryNames = @(
    "retainedContentPrecuEncounterAdapter",
    "precuCombatMath",
    "retainedEncounterMetadata",
    "retiredProgressionCompatibility",
    "legacyItemRequirementCleanup",
    "testDiagnostics"
)
$fileCategory = @{}
foreach ($categoryName in $categoryNames)
{
    $category = $contract.classification.$categoryName
    Assert-Contract (@($category.sourceFiles).Count -eq [int]$category.sourceFileCount) `
        "Java combatLevel category source count drifted in contract: $categoryName"
    foreach ($relativePath in @($category.sourceFiles))
    {
        $relativePath = [string]$relativePath
        Assert-Contract (-not $fileCategory.ContainsKey($relativePath)) `
            "Java combatLevel category files overlap: $relativePath"
        Assert-Contract (Test-Path -LiteralPath (Join-Path $scriptRoot $relativePath) -PathType Leaf) `
            "Java combatLevel category source is missing: $relativePath"
        $fileCategory[$relativePath] = $categoryName
    }
}

$rgOutput = @(& rg --json -i --glob "*.java" "combatLevel" $scriptRoot)
$rgExit = $LASTEXITCODE
Assert-Contract ($rgExit -eq 0) "Could not enumerate the Java combatLevel inventory."
$records = [Collections.Generic.List[object]]::new()
foreach ($jsonLine in $rgOutput)
{
    $entry = $jsonLine | ConvertFrom-Json
    if ([string]$entry.type -cne "match") { continue }
    $absolutePath = [string]$entry.data.path.text
    if (-not [IO.Path]::IsPathRooted($absolutePath))
    {
        $absolutePath = Join-Path $scriptRoot $absolutePath
    }
    $absolutePath = (Resolve-Path -LiteralPath $absolutePath).Path
    Assert-Contract ($absolutePath.StartsWith($scriptRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) "combatLevel match escaped the Java source root."
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $categoryName = if ($fileCategory.ContainsKey($relativePath))
    {
        [string]$fileCategory[$relativePath]
    }
    else { "unclassified" }
    $expression = ([string]$entry.data.lines.text).Trim()
    foreach ($submatch in @($entry.data.submatches))
    {
        $records.Add([pscustomobject]@{
            Path = $relativePath
            Line = [int]$entry.data.line_number
            Column = [int]$submatch.start + 1
            Value = [string]$submatch.match.text
            Expression = $expression
            Category = $categoryName
        })
    }
}

$sortedRecords = @($records | Sort-Object Path, Line, Column, Value)
$matchingLines = @($sortedRecords | ForEach-Object { "$($_.Path):$($_.Line)" } | Sort-Object -Unique)
$sourceFiles = @($sortedRecords.Path | Sort-Object -Unique)
$sourceSet = $sourceFiles -join "`n"
$sourceContent = @($sourceFiles | ForEach-Object {
    "$_|" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scriptRoot $_)).Hash.ToLowerInvariant()
}) -join "`n"
Assert-Contract ($sortedRecords.Count -eq [int]$contract.inventory.referenceOccurrences -and
    $matchingLines.Count -eq [int]$contract.inventory.matchingLines -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-InventorySha256 $sortedRecords) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Complete Java combatLevel textual inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($sortedRecords | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileCounts = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileCounts.Count -and
    $fileCategory.Count -eq $expectedFileCounts.Count) `
    "Java combatLevel source-file set changed."
foreach ($property in $expectedFileCounts)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        $fileCategory.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Java combatLevel source count drifted: $($property.Name)"
}

$classifiedCount = 0
foreach ($categoryName in $categoryNames)
{
    $classified = @($sortedRecords | Where-Object { $_.Category -ceq $categoryName })
    $classifiedLines = @($classified | ForEach-Object { "$($_.Path):$($_.Line)" } | Sort-Object -Unique)
    $classifiedFiles = @($classified.Path | Sort-Object -Unique)
    $expectedCategory = $contract.classification.$categoryName
    Assert-Contract ($classified.Count -eq [int]$expectedCategory.referenceOccurrences -and
        $classifiedLines.Count -eq [int]$expectedCategory.matchingLines -and
        $classifiedFiles.Count -eq [int]$expectedCategory.sourceFileCount -and
        (Get-InventorySha256 $classified) -ceq [string]$expectedCategory.inventorySha256) `
        "Java combatLevel classification drifted: $categoryName"
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $sortedRecords.Count -and
    @($sortedRecords | Where-Object { $_.Category -ceq "unclassified" }).Count -eq 0 -and
    [int]$contract.classification.unclassifiedReferenceOccurrences -eq 0 -and
    [bool]$contract.expected.allReferencesClassified -and
    [int]$contract.expected.playerVisibleCombatLevelProgressionOccurrences -eq 0) `
    "Java combatLevel textual inventory is not fully closed."

$retainedText = @($contract.classification.retainedContentPrecuEncounterAdapter.sourceFiles |
    ForEach-Object { Get-JavaText ([string]$_) }) -join "`n"
$retainedAdapterCalls = [regex]::Matches($retainedText,
    'skill[.]getPrecuEncounterDifficulty\s*[(]').Count
$retainedGetLevelCalls = [regex]::Matches($retainedText, '\bgetLevel\s*[(]').Count
Assert-Contract ($retainedAdapterCalls -eq
        [int]$contract.expected.retainedContentPrecuEncounterAdapterCalls -and
    $retainedGetLevelCalls -eq [int]$contract.expected.retainedContentGetLevelCalls) `
    "Retained content escaped the PRE-CU encounter-difficulty adapter."

$precuCombatRecords = @($sortedRecords | Where-Object { $_.Category -ceq "precuCombatMath" })
Assert-Contract (@($precuCombatRecords | Where-Object {
    $_.Expression -notmatch '\bgetPrecu(?:Weapon)?CombatLevel\b'
}).Count -eq 0) "A combatLevel occurrence escaped PRE-CU combat math."

$storyteller = Get-JavaText "library/storyteller.java"
$targetDummy = Get-JavaText "library/target_dummy.java"
$targetCreature = Get-JavaText "systems/tcg/target_creature.java"
$treasureGuard = Get-JavaText "systems/treasure_map/base/treasure_guard.java"
$metadataText = $storyteller + "`n" + $targetDummy + "`n" +
    (Get-JavaText "systems/storyteller/npc_token.java") + "`n" + $targetCreature + "`n" + $treasureGuard
Assert-Contract ($metadataText -notmatch 'getLevel\s*[(]\s*player\s*[)]' -and
    $storyteller.Contains("getLevel(validStoryObject)") -and
    $targetCreature.Contains("getLevel(self)") -and
    $targetCreature.Contains("skill.getPrecuEncounterDifficulty(owner)") -and
    $targetDummy.Contains("initializeTargetDummy") -and
    $treasureGuard.Contains('getIntObjVar(self, "intCombatDifficulty")')) `
    "Retained authored encounter metadata became player combat-level progression."

$basePlayer = Get-JavaText "player/base/base_player.java"
$baseLevelCallback = Get-BracedSurface $basePlayer `
    "public int OnCombatLevelChanged(obj_id self, int oldCombatLevel, int newCombatLevel) throws InterruptedException"
$levelRewards = Get-BracedSurface $basePlayer `
    "public void grantLevelSpecificRewards(obj_id player, int newCombatLevel) throws InterruptedException"
$skillText = Get-JavaText "library/skill.java"
$statMessages = Get-BracedSurface $skillText `
    "public static void sendlevelUpStatChangeSystemMessages(obj_id player, int oldCombatLevel, int newCombatLevel) throws InterruptedException"
$npeJournal = Get-JavaText "npe/trigger_journal.java"
$npeLevelCallback = Get-BracedSurface $npeJournal `
    "public int OnCombatLevelChanged(obj_id self, int oldCombatLevel, int newCombatLevel) throws InterruptedException"
Assert-Contract ($baseLevelCallback.Contains("recomputeCommandSeries(self)") -and
    -not $baseLevelCallback.Contains("grantLevelSpecificRewards") -and
    -not $baseLevelCallback.Contains("grantSkill") -and
    -not $levelRewards.Contains("createObject") -and
    -not $levelRewards.Contains("grantSkill") -and
    -not $statMessages.Contains("sendSystemMessage") -and
    $npeLevelCallback.Contains("retireNgeLevelGuidance(self)")) `
    "Combat-level callbacks regained NGE reward, stat-message, or NPE guidance authority."

$respec = Get-JavaText "library/respec.java"
$utils = Get-JavaText "library/utils.java"
$ctsRespec = Get-BracedSurface $utils `
    "public static void updateRespecCTSObjvars(obj_id player, dictionary[] ctsOjbvars) throws InterruptedException"
$ctsGuard = $ctsRespec.IndexOf("if (isPostNgeCtsProgressionRestorationRetired())",
    [StringComparison]::Ordinal)
Assert-Contract ($respec.Contains("NGE_PLAYER_RESPEC_RUNTIME_RETIRED = true") -and
    ([regex]::Matches($respec,
        [regex]::Escape("if (retireNgePlayerRespecEntrypoint(player))"))).Count -eq
        [int]$contract.expected.playerRespecGuardedEntrypoints -and
    $ctsGuard -ge 0 -and
    $ctsRespec.IndexOf("respec.autoLevelPlayer", [StringComparison]::Ordinal) -gt $ctsGuard -and
    $ctsRespec.IndexOf("return;", $ctsGuard, [StringComparison]::Ordinal) -gt $ctsGuard) `
    "Inherited respec or CTS combat-level restoration is not fail-closed."

$liveConversions = Get-JavaText "player/live_conversions.java"
$jediConversion = Get-JavaText "player/player_jedi_conversion.java"
$runOnceRefs = @(& rg -n --glob "*.java" '\brunOncePerSessionConversions\s*[(]' $scriptRoot)
Assert-Contract ($LASTEXITCODE -eq 0 -and $runOnceRefs.Count -eq 1 -and
    $liveConversions.Contains('removeObjVar(player, "combatLevel")') -and
    ([regex]::Matches($liveConversions,
        'detachScript[(]self, "player[.]live_conversions"[)]')).Count -eq 3 -and
    $jediConversion.Contains("retireNgeJediConversionState") -and
    $jediConversion -notmatch 'setObjVar\s*[(][^;]*"combatLevel"') `
    "Retired live/Jedi conversion combat-level state became reachable or writable."

$stim = Get-JavaText "item/medicine/stimpack.java"
$craftedStim = Get-JavaText "item/medicine/stimpack_crafted.java"
$forceMelon = Get-JavaText "item/plant/force_melon.java"
$staticItem = Get-JavaText "library/static_item.java"
$itemCleanup = Get-BracedSurface $staticItem `
    "public static void removeLegacyNgeItemCombatLevelRequirement(obj_id item) throws InterruptedException"
$itemCallText = $stim + "`n" + $craftedStim + "`n" + $forceMelon
Assert-Contract (([regex]::Matches($itemCallText,
        'static_item[.]removeLegacyNgeItemCombatLevelRequirement[(]self[)];')).Count -eq
        [int]$contract.expected.legacyItemCleanupCallSites -and
    $itemCleanup.Contains('hasObjVar(item, "healing.combat_level_required")') -and
    ([regex]::Matches($itemCleanup,
        'removeObjVar[(]item, "healing[.]combat_level_required"[)]')).Count -eq 1 -and
    -not $itemCleanup.Contains('removeObjVar(item, "healing")')) `
    "Legacy item combat-level requirement cleanup drifted."

foreach ($dependencyKey in @($contract.requiredReadyContractKeys))
{
    $dependencyKey = [string]$dependencyKey
    $manifestProperty = @($manifest.contracts.PSObject.Properties |
        Where-Object { $_.Name -ceq $dependencyKey })
    Assert-Contract ($manifestProperty.Count -eq 1) `
        "Required contract key is missing from the manifest: $dependencyKey"
    $dependencyPath = Join-Path $restorationRoot ([string]$manifestProperty[0].Value)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyKey"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    $dependencyStatus = [string]$dependency.status
    if ($dependencyKey -ceq "p14PrecuCombatXpAuthority" -and
        $dependencyStatus -ceq "implemented-build-pending")
    {
        & (Join-Path $PSScriptRoot "Test-P14PrecuCombatXpAuthority.ps1") `
            -SourceRoot $root
    }
    $playerMigrationBuildPending = ($Expectation -ceq "Build" -and
        $dependencyKey -ceq "p14PostNgePlayerMigrationAuthorityRetirement" -and
        (@("implemented-build-pending", "ready-for-live-verification") -contains $dependencyStatus))
    if ($playerMigrationBuildPending)
    {
        & (Join-Path $PSScriptRoot "Test-P14PostNgePlayerMigrationAuthorityRetirement.ps1") `
            -SourceRoot $root `
            -Expectation Build
    }
    Assert-Contract ($dependencyStatus -ceq "ready" -or
        ($dependencyKey -ceq "p14PrecuCombatXpAuthority" -and
            $dependencyStatus -ceq "implemented-build-pending") -or
        $playerMigrationBuildPending) `
        "Required dependency is not Ready: $dependencyKey"
}

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    -not [bool]$contract.expected.playerCombatLevelRewards -and
    -not [bool]$contract.expected.playerCombatLevelStatMessages -and
    [bool]$contract.expected.laterZonesQuestsConversationsAndNpcCompatibilityPreserved) `
    "Java combatLevel expected PRE-CU boundary is incomplete."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.containerHealth -ceq "healthy" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [int]$contract.runtimeEvidence.javaSources -eq 5717 -and
        [int]$contract.runtimeEvidence.javaClasses -eq 5751 -and
        [int]$contract.runtimeEvidence.liveGameProcessCount -eq 15 -and
        [int]$contract.runtimeEvidence.livePlanetProcessCount -eq 15 -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Java combatLevel textual inventory closure lacks Ready evidence."
    $container = [string]$contract.runtimeEvidence.container
    $state = (& docker inspect --format `
        "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $container).Trim()
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
        "Java combatLevel textual inventory closure is not build-eligible."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Java combatLevel textual inventory closure references forbidden host staging."

Write-Host "Complete Publish 14.1 Java combatLevel textual inventory closure passed."
