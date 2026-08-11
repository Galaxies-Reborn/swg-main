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
    ([string]$manifest.contracts.p14JavaPlayerLevelDatatableCallsiteInventoryClosure)
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

function Assert-Ordered([string]$Text, [string[]]$Needles, [string]$Label)
{
    $cursor = -1
    foreach ($needle in $Needles)
    {
        $cursor = $Text.IndexOf($needle, $cursor + 1, [StringComparison]::Ordinal)
        Assert-Contract ($cursor -ge 0) "$Label lost ordered boundary: $needle"
    }
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
    "Player-level datatable closure is not pinned to checked-out direct source."

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
        "Could not classify player-level datatable read: $($match.Path):$($match.LineNumber)"
    $records.Add([pscustomobject]@{
        Path = $match.Path.Substring($dsrcRoot.Length + 1).Replace("\", "/")
        Line = $match.LineNumber
        Method = $method
        Expression = $match.Line.Trim()
    })
}

$sourceFiles = @($records.Path | Sort-Object -Unique)
$sortedRecords = @($records | Sort-Object Path, Line)
$canonical = (@($sortedRecords | ForEach-Object {
    "$($_.Path)|$($_.Method)|$($_.Expression)"
}) -join "`n") + "`n"
$sourceSet = ($sourceFiles -join "`n") + "`n"
$sourceContent = (@($sourceFiles | ForEach-Object {
    "$_=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dsrcRoot $_)).Hash.ToLowerInvariant()
}) -join "`n") + "`n"
Assert-Contract ($records.Count -eq [int]$contract.inventory.callSites -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-TextSha256 $canonical) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Direct Java player-level datatable inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFiles = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFiles.Count) `
    "Player-level datatable source-file set changed."
foreach ($property in $expectedFiles)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Player-level datatable callsite count drifted: $($property.Name)"
}

$respecRecords = @($sortedRecords | Where-Object { $_.Path -like "*/library/respec.java" })
$conversionRecords = @($sortedRecords | Where-Object { $_.Path -like "*/player/live_conversions.java" })
function Get-CategorySha256([object[]]$CategoryRecords)
{
    $category = (@($CategoryRecords | ForEach-Object {
        "$($_.Path)|$($_.Method)|$($_.Expression)"
    }) -join "`n") + "`n"
    return Get-TextSha256 $category
}
Assert-Contract ($respecRecords.Count -eq [int]$contract.classification.retiredRespecCompatibility.callSites -and
    (Get-CategorySha256 $respecRecords) -ceq
        [string]$contract.classification.retiredRespecCompatibility.inventorySha256 -and
    $conversionRecords.Count -eq [int]$contract.classification.retiredLiveConversionCompatibility.callSites -and
    (Get-CategorySha256 $conversionRecords) -ceq
        [string]$contract.classification.retiredLiveConversionCompatibility.inventorySha256 -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    ($respecRecords.Count + $conversionRecords.Count) -eq $records.Count) `
    "Player-level datatable classification is incomplete."

$dependencies = @{}
foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    $dependencyStatus = [string]$dependency.status
    $playerMigrationBuildPending = ($Expectation -ceq "Build" -and
        [string]$dependencyName -ceq "p14-post-nge-player-migration-authority-retirement.json" -and
        (@("implemented-build-pending", "ready-for-live-verification") -contains $dependencyStatus))
    if ($playerMigrationBuildPending)
    {
        & (Join-Path $PSScriptRoot "Test-P14PostNgePlayerMigrationAuthorityRetirement.ps1") `
            -SourceRoot $root `
            -Expectation Build
    }
    Assert-Contract ($dependencyStatus -ceq "ready" -or $playerMigrationBuildPending) `
        "Required dependency is not Ready: $dependencyName"
    $dependencies[$dependencyName] = $dependency
}

$paths = [ordered]@{
    "library/respec.java" = Join-Path $scriptRoot "library/respec.java"
    "player/live_conversions.java" = Join-Path $scriptRoot "player/live_conversions.java"
    "player/base/base_player.java" = Join-Path $scriptRoot "player/base/base_player.java"
    "library/utils.java" = Join-Path $scriptRoot "library/utils.java"
    "systems/skills/auto_level.java" = Join-Path $scriptRoot "systems/skills/auto_level.java"
    "library/skill.java" = Join-Path $scriptRoot "library/skill.java"
}
foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant() -ceq
        [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
        "Player-level datatable source evidence drifted: $($entry.Key)"
}

$text = @{}
foreach ($entry in $paths.GetEnumerator())
{
    $text[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}
$getOldLevel = Get-BracedSurface $text["library/respec.java"] `
    "public static int getOldCombatLevel(obj_id player) throws InterruptedException"
$autoLevel = Get-BracedSurface $text["library/respec.java"] `
    "public static boolean autoLevelPlayer(obj_id player, int level, boolean withItems) throws InterruptedException"
$grantNext = Get-BracedSurface $text["player/live_conversions.java"] `
    "public void grantNextTraderAndEntertainerSkill(obj_id player) throws InterruptedException"
$runConversions = Get-BracedSurface $text["player/live_conversions.java"] `
    "public void runOncePerSessionConversions(obj_id player) throws InterruptedException"
$ctsRespec = Get-BracedSurface $text["library/utils.java"] `
    "public static void updateRespecCTSObjvars(obj_id player, dictionary[] ctsOjbvars) throws InterruptedException"
$precuDifficulty = Get-BracedSurface $text["library/skill.java"] `
    "public static int getPrecuEncounterDifficulty(obj_id player) throws InterruptedException"

Assert-Contract (([regex]::Matches($getOldLevel, $pattern)).Count -eq 3 -and
    ([regex]::Matches($autoLevel, $pattern)).Count -eq 1 -and
    ([regex]::Matches($grantNext, $pattern)).Count -eq 1) `
    "Player-level datatable reads escaped their compatibility helpers."
Assert-Ordered $ctsRespec @(
    "if (isPostNgeCtsProgressionRestorationRetired())",
    'removeObjVar(player, "respecsBought")',
    "removeObjVar(player, respec.PROF_LEVEL_ARRAY)",
    "return;",
    "respec.autoLevelPlayer("
) "CTS NGE auto-level retirement"
Assert-Ordered $text["systems/skills/auto_level.java"] @(
    "private static boolean isNgeAutoLevelItemEnabled()",
    "return false;",
    "public int OnObjectMenuRequest",
    "if (!isNgeAutoLevelItemEnabled())",
    "public int handlerSuiAutoLevel",
    "if (!isNgeAutoLevelItemEnabled())",
    "respec.autoLevelPlayer("
) "NGE auto-level item retirement"
Assert-Ordered $text["player/live_conversions.java"] @(
    "public int OnInitialize",
    'detachScript(self, "player.live_conversions")',
    "public int OnLogin",
    'detachScript(self, "player.live_conversions")',
    "public int OnNewbieTutorialResponse",
    'detachScript(self, "player.live_conversions")'
) "live-conversion self-retirement"
Assert-Ordered $text["player/base/base_player.java"] @(
    "public int OnInitialize",
    "script.player.live_conversions.retirePostNgePlayerMigrationState(self)",
    'if (hasScript(self, "player.live_conversions"))',
    'detachScript(self, "player.live_conversions")',
    "public int OnLogin",
    "script.player.live_conversions.retirePostNgePlayerMigrationState(self)"
) "base-player migration retirement"
Assert-Contract ($text["library/respec.java"].Contains(
        "public static final boolean NGE_PLAYER_RESPEC_RUNTIME_RETIRED = true;") -and
    ([regex]::Matches($text["library/respec.java"],
        'if \(retireNgePlayerRespecEntrypoint\(player\)\)')).Count -eq 5 -and
    $runConversions.Contains("forceRespecBasedOnConfig(player);") -and
    -not $precuDifficulty.Contains("getLevel(") -and
    -not ([regex]::IsMatch($precuDifficulty, $pattern)) -and
    $precuDifficulty.Contains("getPrecuCombatSkillScore(player)") -and
    $text["library/skill.java"].Contains(
        "public static int getPrecuCombatSkillScore(obj_id player) throws InterruptedException")) `
    "PRE-CU difficulty or retired respec/live-conversion authority boundary drifted."

$allJava = $javaFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
$joinedJava = $allJava -join "`n"
Assert-Contract (([regex]::Matches($joinedJava, '\bgetOldCombatLevel\s*\(')).Count -eq
        [int]$contract.expected.getOldCombatLevelReferences -and
    ([regex]::Matches($joinedJava, '\bgrantNextTraderAndEntertainerSkill\s*\(')).Count -eq
        [int]$contract.expected.grantNextTraderAndEntertainerSkillReferences -and
    ([regex]::Matches($joinedJava, '\brunOncePerSessionConversions\s*\(')).Count -eq
        [int]$contract.expected.runOncePerSessionConversionsReferences -and
    ([regex]::Matches($joinedJava, '\bautoLevelPlayer\s*\(')).Count -eq
        [int]$contract.expected.autoLevelPlayerReferences -and
    ([regex]::Matches($joinedJava, '\bgetPrecuEncounterDifficulty\s*\(')).Count -eq
        [int]$contract.expected.precuEncounterDifficultyReferences) `
    "Player-level compatibility caller inventory drifted."

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [int]$contract.expected.directPlayerLevelDatatableReads -eq $records.Count -and
    [int]$contract.expected.retiredRespecReads -eq $respecRecords.Count -and
    [int]$contract.expected.retiredLiveConversionReads -eq $conversionRecords.Count -and
    [int]$contract.expected.unclassifiedReads -eq 0 -and
    -not [bool]$contract.expected.precuEncounterDifficultyReadsPlayerLevelDatatable -and
    [bool]$contract.expected.retainedLaterContentPreserved -and
    [bool]$contract.expected.playerLevelDatatablesPreservedAsCompatibilityData) `
    "Direct Java player-level datatable authority boundary is incomplete."

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
        "Player-level datatable callsite closure is not Ready."
    $container = [string]$contract.runtimeEvidence.container
    $state = (& docker inspect --format "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $container).Trim()
    $processNames = @(& docker exec $container ps -eo comm= | ForEach-Object { $_.Trim() })
    Assert-Contract ($state -ceq "running healthy" -and
        @($processNames | Where-Object { $_ -ceq "SwgGameServer" }).Count -eq 15 -and
        @($processNames | Where-Object { $_ -ceq "PlanetServer" }).Count -eq 15) `
        "Deployed PRE-CU x64 runtime topology drifted."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) `
        "Player-level datatable callsite closure is not build-eligible."
}

Write-Host "Publish 14.1 Java player-level datatable callsite inventory closure passed."
