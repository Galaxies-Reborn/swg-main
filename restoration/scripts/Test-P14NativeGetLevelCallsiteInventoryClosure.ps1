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
    ([string]$manifest.contracts.p14NativeGetLevelCallsiteInventoryClosure)
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
    if ($start -lt 0) { throw "Missing native surface: $Signature" }
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

$directPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$nativePin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$directCommit = (& git -C $dsrcRoot rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0) "Could not read direct-source revision."
$nativeCommit = (& git -C $srcRoot rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $directPin.Count -eq 1 -and $nativePin.Count -eq 1 -and
    [string]$directPin[0].commit -ceq $directCommit -and
    [string]$nativePin[0].commit -ceq $nativeCommit -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $nativeCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "Native getLevel closure is not pinned to checked-out direct source."

$nativeFiles = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File |
    Where-Object { $_.Extension -in ".cpp", ".h" })
Assert-Contract ($nativeFiles.Count -eq [int]$contract.inventory.cppHeaderSources) `
    "Native C++/header source inventory drifted: $($nativeFiles.Count)"

$pattern = [string]$contract.inventory.pattern
$records = [Collections.Generic.List[object]]::new()
foreach ($file in $nativeFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $lines = $text -split "`r?`n"
    $relative = $file.FullName.Substring($srcRoot.Length + 1).Replace("\", "/")
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; ++$lineIndex)
    {
        $matches = [regex]::Matches($lines[$lineIndex], $pattern)
        foreach ($ignored in $matches)
        {
            $records.Add([pscustomobject]@{
                Path = $relative
                Line = $lineIndex + 1
                Expression = $lines[$lineIndex].Trim()
                Category = ""
            })
        }
    }
}
$records = @($records | Sort-Object Path, Line, Expression)
$sourceFiles = @($records.Path | Sort-Object -Unique)
$canonical = (@($records | ForEach-Object {
    "$($_.Path)|$($_.Line)|$($_.Expression)"
}) -join "`n") + "`n"
$sourceSet = ($sourceFiles -join "`n") + "`n"
$sourceContent = (@($sourceFiles | ForEach-Object {
    "$_=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $srcRoot $_)).Hash.ToLowerInvariant()
}) -join "`n") + "`n"
Assert-Contract ($records.Count -eq [int]$contract.inventory.callSites -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-TextSha256 $canonical) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Native getLevel callsite inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileProperties = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileProperties.Count) `
    "Native getLevel source-file set changed."
foreach ($property in $expectedFileProperties)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Native getLevel count drifted: $($property.Name)"
}

foreach ($record in $records)
{
    if ($record.Path -match 'ServerObjectTemplate\.(cpp|h)$|shared/quest/Quest\.(cpp|h)$')
    {
        $record.Category = "authoredContent"
    }
    elseif ($record.Path -in @(
            "engine/server/application/PlanetServer/src/shared/PlanetProxyObject.h",
            "engine/server/application/PlanetServer/src/shared/Scene.cpp",
            "engine/server/library/serverNetworkMessages/src/shared/gamePlanetServer/UpdateObjectOnPlanetMessage.h",
            "engine/shared/library/sharedNetworkMessages/src/shared/clientGameServer/AIDebuggingMessages.h",
            "game/server/library/swgServerNetworkMessages/src/shared/jedi/MessageQueueJediData.h"
        ) -or ($record.Path -ceq "engine/server/library/serverGame/src/shared/object/CreatureObject.cpp" -and
            $record.Expression -in @(
                "static_cast<int>(getLevel()),",
                "lfgCharacterData.level = isPlayerControlled() ? 0 : getLevel();",
                "int const level = memberIsPC ? 0 : creatureObject->getLevel();"
            )))
    {
        $record.Category = "neutralCompatibilityTransport"
    }
    elseif ($record.Path -in @(
            "engine/server/library/serverScript/src/shared/ScriptMethodsObjectInfo.cpp",
            "engine/server/library/serverGame/src/shared/object/CreatureObject.h",
            "engine/server/library/serverGame/src/shared/object/ServerObject.cpp"
        ) -or ($record.Path -ceq "engine/server/library/serverGame/src/shared/controller/AiCreatureController.cpp" -and
            $record.Expression -match '(ownerLevel|targetLevel).*getLevel\('))
    {
        $record.Category = "precuDualDomainAbi"
    }
    elseif ($record.Path -ceq "engine/server/library/serverGame/src/shared/object/BuildingObject.cpp" -or
        $record.Path -match 'ConsoleCommandParser(Ai|Server|Skill)\.cpp$' -or
        ($record.Path -ceq "engine/server/library/serverGame/src/shared/controller/AiCreatureController.cpp" -and
            $record.Expression -notmatch '(ownerLevel|targetLevel).*getLevel\('))
    {
        $record.Category = "npcSentinelDiagnostics"
    }
}

$classificationNames = @(
    "authoredContent",
    "neutralCompatibilityTransport",
    "precuDualDomainAbi",
    "npcSentinelDiagnostics"
)
$classifiedCount = 0
foreach ($category in $classificationNames)
{
    $classified = @($records | Where-Object { $_.Category -ceq $category } |
        Sort-Object Path, Line, Expression)
    $categoryCanonical = (@($classified | ForEach-Object {
        "$($_.Path)|$($_.Line)|$($_.Expression)"
    }) -join "`n") + "`n"
    $expected = $contract.classification.$category
    Assert-Contract ($classified.Count -eq [int]$expected.callSites -and
        (Get-TextSha256 $categoryCanonical) -ceq [string]$expected.inventorySha256) `
        "Native getLevel classification drifted: $category"
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $records.Count -and
    @($records | Where-Object { [string]::IsNullOrEmpty($_.Category) }).Count -eq 0 -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    [bool]$contract.expected.allCallSitesClassified -and
    [int]$contract.expected.playerCombatLevelGameplayAuthorityCallSites -eq 0) `
    "Native getLevel inventory is not fully closed."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    $allowedDependencyStatuses = if ($Expectation -eq "Ready") { @("ready") }
        else { @("implemented-build-pending", "implemented-build-verified-live-pending", "ready") }
    Assert-Contract ($allowedDependencyStatuses -contains [string]$dependency.status) `
        "Required dependency is not Ready: $dependencyName"
}

$creaturePath = Join-Path $srcRoot "engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
$creature = Get-Content -LiteralPath $creaturePath -Raw
Assert-Contract ($creature.Contains("lfgCharacterData.level = isPlayerControlled() ? 0 : getLevel();") -and
    $creature.Contains("int const level = memberIsPC ? 0 : creatureObject->getLevel();")) `
    "Player LFG/group compatibility transport is not neutral."

$scene = Get-Content -LiteralPath (Join-Path $srcRoot "engine/server/application/PlanetServer/src/shared/Scene.cpp") -Raw
$planetProxy = Get-Content -LiteralPath (Join-Path $srcRoot "engine/server/application/PlanetServer/src/shared/PlanetProxyObject.cpp") -Raw
$watcher = Get-Content -LiteralPath (Join-Path $srcRoot "engine/server/application/PlanetServer/src/shared/WatcherConnection.cpp") -Raw
$watcherMessage = Get-Content -LiteralPath (Join-Path $srcRoot "engine/shared/library/sharedNetworkMessages/src/shared/planetWatch/PlanetObjectStatusMessage.h") -Raw
Assert-Contract ($scene.Contains("msg.getLevel()") -and
    $planetProxy.Contains("m_level = level;") -and
    $planetProxy.Contains("conn.addObjectUpdate(m_objectId, m_x, m_z, m_authoritativeServer, m_interestRadius, deleteObject, m_objectTypeTag, m_level") -and
    $watcher.Contains("PlanetObjectStatusMessageData(objectId, x,z, authoritativeServer, interestRadius, static_cast<int>(deleteObject), objectTypeTag, level") -and
    $watcherMessage.Contains("Sent to:    PlanetWatcher")) `
    "Planet level compatibility chain no longer terminates in watcher telemetry."

$aiController = Get-Content -LiteralPath (Join-Path $srcRoot "engine/server/library/serverGame/src/shared/controller/AiCreatureController.cpp") -Raw
$respect = Get-BracedSurface $aiController "float AICreatureController::getRespectRadius("
Assert-Contract ($respect.Contains("Respect is only towards players") -and
    $respect.Contains("respectCreatureObject->isPlayerControlled()") -and
    $respect.Contains("ownerLevel = creatureOwner->getLevel()") -and
    $respect.Contains("targetLevel = respectCreatureObject->getLevel()") -and
    -not $respect.Contains("LevelManager")) `
    "Respect-radius compatibility helper drifted."
$scriptMethodsAi = Get-Content -LiteralPath (Join-Path $srcRoot "engine/server/library/serverScript/src/shared/ScriptMethodsAi.cpp") -Raw
Assert-Contract ($scriptMethodsAi.Contains("return aiCreatureController->getRespectRadius(targetNetworkId);")) `
    "Respect-radius Java ABI bridge was unexpectedly removed."
$javaFiles = @(Get-ChildItem -LiteralPath (Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script") -Recurse -File -Filter "*.java")
$productionRespectCalls = 0
$diagnosticRespectCalls = 0
foreach ($javaFile in $javaFiles)
{
    $relative = $javaFile.FullName.Substring(
        (Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script").Length + 1).Replace("\", "/")
    $count = [regex]::Matches((Get-Content -LiteralPath $javaFile.FullName -Raw),
        '\baiGetRespectRadius\s*\(').Count
    if ($relative -match '^test/') { $diagnosticRespectCalls += $count }
    elseif ($relative -cne "base_class.java") { $productionRespectCalls += $count }
}
Assert-Contract ($javaFiles.Count -eq [int]$contract.semanticEvidence.javaSources -and
    $productionRespectCalls -eq [int]$contract.semanticEvidence.javaRespectRadiusProductionCalls -and
    $diagnosticRespectCalls -eq [int]$contract.semanticEvidence.javaRespectRadiusDiagnosticCalls) `
    "Respect-radius bridge gained a production Java caller or lost its diagnostic."

$building = Get-Content -LiteralPath (Join-Path $srcRoot "engine/server/library/serverGame/src/shared/object/BuildingObject.cpp") -Raw
Assert-Contract ($building.Contains("!who.isPlayerControlled()") -and
    $building.Contains("who.getMasterId() == NetworkId::cms_invalid") -and
    $building.Contains("who.getLevel() < 0")) `
    "Private-building NPC sentinel lost its player exclusion."

$objectInfo = Get-Content -LiteralPath (Join-Path $srcRoot "engine/server/library/serverScript/src/shared/ScriptMethodsObjectInfo.cpp") -Raw
Assert-Contract ($objectInfo.Contains("result = creature->getLevel();")) `
    "Authenticated Java object-level ABI changed unexpectedly."
$quest = Get-Content -LiteralPath (Join-Path $srcRoot "engine/shared/library/sharedGame/src/shared/quest/Quest.cpp") -Raw
Assert-Contract ($quest.Contains("int Quest::getLevel() const") -and
    $quest.Contains("if (getLevel() < 1 || getTier() < 0)")) `
    "Authored quest-level data changed unexpectedly."

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        $contract.requiredBeforeReady.Count -eq 0) `
        "Native getLevel closure lacks Ready evidence."
    Assert-Contract ([string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "Native getLevel closure lacks authenticated live x64 evidence."
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) `
        "Native getLevel source status is invalid."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Native getLevel closure references prohibited host staging."
Write-Host "Native getLevel callsite inventory closure passed."
