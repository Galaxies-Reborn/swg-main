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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14JavaProfessionLevelAliasCallsiteInventoryClosure)
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
    $category = (@($CategoryRecords | ForEach-Object {
        "$($_.Path)|$($_.Method)|$($_.Expression)"
    }) -join "`n") + "`n"
    return Get-TextSha256 $category
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
    "Profession-level alias closure is not pinned to checked-out direct source."

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
        "Could not classify profession-level alias: $($match.Path):$($match.LineNumber)"
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
    "Java profession-level alias inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
foreach ($property in @($contract.inventory.fileCounts.PSObject.Properties))
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Profession-level alias file count drifted: $($property.Name)"
}
Assert-Contract ($actualFileCounts.Count -eq
    @($contract.inventory.fileCounts.PSObject.Properties).Count) `
    "Profession-level alias source-file set changed."

$actualMethodCounts = @{}
foreach ($record in $records)
{
    $name = [regex]::Match($record.Expression,
        '\b(getProfessionLevelArray|getCombatLevel|getEntertainerLevel|getTraderLevel|setProfessionLevel|setProfessionLevelArray)\s*\(').Groups[1].Value
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($name)) `
        "Could not identify profession-level alias method: $($record.Expression)"
    if (-not $actualMethodCounts.ContainsKey($name)) { $actualMethodCounts[$name] = 0 }
    ++$actualMethodCounts[$name]
}
foreach ($property in @($contract.inventory.methodCounts.PSObject.Properties))
{
    Assert-Contract ($actualMethodCounts.ContainsKey($property.Name) -and
        [int]$actualMethodCounts[$property.Name] -eq [int]$property.Value) `
        "Profession-level alias method count drifted: $($property.Name)"
}

$respecRecords = @($sortedRecords | Where-Object { $_.Path -like "*/library/respec.java" })
$simulatorRecords = @($sortedRecords | Where-Object { $_.Path -like "*/simulator/combat_simulator_user.java" })
Assert-Contract ($respecRecords.Count -eq [int]$contract.classification.retiredRespecCompatibility.callSites -and
    (Get-CategorySha256 $respecRecords) -ceq
        [string]$contract.classification.retiredRespecCompatibility.inventorySha256 -and
    $simulatorRecords.Count -eq [int]$contract.classification.retainedNpcCombatSimulatorUi.callSites -and
    (Get-CategorySha256 $simulatorRecords) -ceq
        [string]$contract.classification.retainedNpcCombatSimulatorUi.inventorySha256 -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    ($respecRecords.Count + $simulatorRecords.Count) -eq $records.Count) `
    "Profession-level alias classification is incomplete."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    $dependencyStatus = [string]$dependency.status
    $playerMigrationBuildPending = ($Expectation -ceq "Build" -and
        [string]$dependencyName -ceq "p14-post-nge-player-migration-authority-retirement.json" -and
        $dependencyStatus -ceq "implemented-build-pending")
    if ($playerMigrationBuildPending)
    {
        & (Join-Path $PSScriptRoot "Test-P14PostNgePlayerMigrationAuthorityRetirement.ps1") `
            -SourceRoot $root `
            -Expectation Build
    }
    Assert-Contract ($dependencyStatus -ceq "ready" -or $playerMigrationBuildPending) `
        "Required dependency is not Ready: $dependencyName"
}

$paths = [ordered]@{
    "library/respec.java" = Join-Path $scriptRoot "library/respec.java"
    "simulator/combat_simulator_user.java" = Join-Path $scriptRoot "simulator/combat_simulator_user.java"
    "library/utils.java" = Join-Path $scriptRoot "library/utils.java"
    "player/live_conversions.java" = Join-Path $scriptRoot "player/live_conversions.java"
}
$text = @{}
foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant() -ceq
        [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
        "Profession-level alias source evidence drifted: $($entry.Key)"
    $text[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

$handleRespec = Get-BracedSurface $text["library/respec.java"] `
    "public static void handleNpcRespec(obj_id player, String skillTemplateName) throws InterruptedException"
$getArray = Get-BracedSurface $text["library/respec.java"] `
    "public static int[] getProfessionLevelArray(obj_id player) throws InterruptedException"
$setLevel = Get-BracedSurface $text["library/respec.java"] `
    "public static void setProfessionLevel(obj_id player, int profType, int level) throws InterruptedException"
$setArray = Get-BracedSurface $text["library/respec.java"] `
    "public static void setProfessionLevelArray(obj_id player, int[] profLevelArray) throws InterruptedException"
$ctsRespec = Get-BracedSurface $text["library/utils.java"] `
    "public static void updateRespecCTSObjvars(obj_id player, dictionary[] ctsOjbvars) throws InterruptedException"
$simulatorSet = Get-BracedSurface $text["simulator/combat_simulator_user.java"] `
    "public void setProfessionLevel() throws InterruptedException"
$simulatorSetOk = Get-BracedSurface $text["simulator/combat_simulator_user.java"] `
    "public int setProfessionLevelOk(obj_id self, dictionary params) throws InterruptedException"

Assert-Ordered $handleRespec @(
    "if (retireNgePlayerRespecEntrypoint(player))",
    "return;",
    "setProfessionLevel(player, PROF_LEVEL_COMBAT",
    "targetLevel = getCombatLevel(player)",
    "targetLevel = getEntertainerLevel(player)",
    "targetLevel = getTraderLevel(player)"
) "NGE respec profession-level alias retirement"
Assert-Contract ($getArray.Contains("if (!hasObjVar(player, PROF_LEVEL_ARRAY))") -and
    $getArray.Contains("return getIntArrayObjVar(player, PROF_LEVEL_ARRAY)") -and
    $setLevel.Contains("int[] profLevelArray = getProfessionLevelArray(player)") -and
    $setLevel.Contains("setObjVar(player, PROF_LEVEL_ARRAY, profLevelArray)") -and
    $setArray.Contains("setObjVar(player, PROF_LEVEL_ARRAY, profLevelArray)")) `
    "Respec profession-level compatibility storage boundary drifted."
Assert-Ordered $ctsRespec @(
    "if (isPostNgeCtsProgressionRestorationRetired())",
    'removeObjVar(player, "respecsBought")',
    "removeObjVar(player, respec.PROF_LEVEL_ARRAY)",
    "return;",
    "setObjVar(player, respec.PROF_LEVEL_ARRAY"
) "CTS profession-level array retirement"
Assert-Contract ($text["player/live_conversions.java"].Contains(
        'removeObjVar(player, "playerRespec");') -and
    $text["player/live_conversions.java"].Contains(
        'removeObjVar(player, "combatLevel");') -and
    $simulatorSet.Contains('"combat_simulator." + actor + ".professions"') -and
    $simulatorSetOk.Contains('"combat_simulator.current_profession"') -and
    $simulatorSetOk.Contains('"combat_simulator." + actor + ".professions"') -and
    -not $simulatorSet.Contains("respec.") -and
    -not $simulatorSetOk.Contains("respec.")) `
    "Persisted respec cleanup or retained NPC simulator boundary drifted."

$joinedJava = ($javaFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
$qualifiedExternal = [regex]::Matches($joinedJava,
    '\brespec\.(getProfessionLevelArray|getCombatLevel|getEntertainerLevel|getTraderLevel|setProfessionLevel|setProfessionLevelArray)\s*\(').Count
Assert-Contract ($qualifiedExternal -eq [int]$contract.expected.qualifiedExternalRespecAliasCalls -and
    [int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [int]$contract.expected.retiredRespecCompatibilityCalls -eq $respecRecords.Count -and
    [int]$contract.expected.retainedNpcCombatSimulatorUiCalls -eq $simulatorRecords.Count -and
    [int]$contract.expected.unclassifiedCalls -eq 0 -and
    -not [bool]$contract.expected.playerProfessionLevelArrayRuntimeAuthority -and
    [bool]$contract.expected.persistedProfessionLevelArrayRemoved -and
    [bool]$contract.expected.retainedNpcCombatSimulatorPreserved) `
    "Java profession-level alias authority boundary is incomplete."

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
        "Profession-level alias callsite closure is not Ready."
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
        "Profession-level alias callsite closure is not build-eligible."
}

Write-Host "Publish 14.1 Java profession-level alias callsite inventory closure passed."
