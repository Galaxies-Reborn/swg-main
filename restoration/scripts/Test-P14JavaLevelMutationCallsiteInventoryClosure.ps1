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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14JavaLevelMutationCallsiteInventoryClosure)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

function Assert-Contract
{
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-TextSha256
{
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BracedSurface
{
    param([string]$Text, [string]$Signature)
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing source surface: $Signature" }
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
$nativeCommit = (& git -C $srcRoot rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $directPin.Count -eq 1 -and $nativePin.Count -eq 1 -and
    [string]$directPin[0].commit -ceq $directCommit -and
    [string]$nativePin[0].commit -ceq $nativeCommit -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $nativeCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "Java level-mutation closure is not pinned to the checked-out direct source."

$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"

$pattern = [string]$contract.inventory.pattern
$records = [System.Collections.Generic.List[object]]::new()
foreach ($file in $javaFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $lines = $text -split "`r?`n"
    $relative = $file.FullName.Substring($dsrcRoot.Length + 1).Replace("\", "/")
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; ++$lineIndex)
    {
        if ($lines[$lineIndex] -notmatch $pattern) { continue }
        $method = ""
        for ($methodIndex = $lineIndex; $methodIndex -ge 0; --$methodIndex)
        {
            if ($lines[$methodIndex] -match '^\s*(public|private|protected)\s+.*\([^;]*$')
            {
                $method = $lines[$methodIndex].Trim()
                break
            }
        }
        Assert-Contract (-not [string]::IsNullOrWhiteSpace($method)) `
            "Could not classify method for $relative line $($lineIndex + 1)."
        $category = if ($relative -match '/base_class\.java$')
        {
            "nativeScriptBridge"
        }
        elseif ($relative -match '/player/base/base_player\.java$')
        {
            "precuPlayerRefresh"
        }
        elseif ($relative -match '/library/combat\.java$' -or $relative -match '/working/')
        {
            "dormantCompatibility"
        }
        else
        {
            "retainedNonPlayerContent"
        }
        $records.Add([pscustomobject]@{
            Path = $relative
            Line = $lineIndex + 1
            Method = $method
            Expression = $lines[$lineIndex].Trim()
            Category = $category
        })
    }
}

$sourceFiles = @($records.Path | Sort-Object -Unique)
$canonical = (@($records | Sort-Object Path, Line | ForEach-Object {
    "$($_.Path)|$($_.Method)|$($_.Expression)"
}) -join "`n") + "`n"
$sourceSet = ($sourceFiles -join "`n") + "`n"
$sourceContent = (@($sourceFiles | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dsrcRoot $_)).Hash.ToLowerInvariant()
    "$_=$hash"
}) -join "`n") + "`n"
Assert-Contract ($records.Count -eq [int]$contract.inventory.callSites -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-TextSha256 $canonical) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Residual Java level-mutation callsite inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileProperties = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileProperties.Count) `
    "Residual Java level-mutation source-file set changed."
foreach ($property in $expectedFileProperties)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Residual Java level-mutation count drifted: $($property.Name)"
}

foreach ($name in @("setLevel", "recalculateLevel", "getGroupObjectLevel"))
{
    $count = @($records | Where-Object { $_.Expression -match ("\b" + $name + "\s*\(") }).Count
    Assert-Contract ($count -eq [int]$contract.inventory.methodCounts.$name) `
        "Residual Java level method count drifted: $name"
}

$classificationNames = @(
    "nativeScriptBridge",
    "precuPlayerRefresh",
    "retainedNonPlayerContent",
    "dormantCompatibility"
)
$classifiedCount = 0
foreach ($category in $classificationNames)
{
    $classified = @($records | Where-Object { $_.Category -ceq $category } | Sort-Object Path, Line)
    $categoryCanonical = (@($classified | ForEach-Object {
        "$($_.Path)|$($_.Method)|$($_.Expression)"
    }) -join "`n") + "`n"
    $expected = $contract.classification.$category
    Assert-Contract ($classified.Count -eq [int]$expected.callSites -and
        (Get-TextSha256 $categoryCanonical) -ceq [string]$expected.inventorySha256) `
        "Residual Java level-mutation classification drifted: $category"
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $records.Count -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    [bool]$contract.expected.allCallSitesClassified) `
    "Residual Java level-mutation inventory is not completely classified."

$nativePaths = [ordered]@{
    "CreatureObject.cpp" = Join-Path $srcRoot "engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
    "CreatureObject.h" = Join-Path $srcRoot "engine/server/library/serverGame/src/shared/object/CreatureObject.h"
    "ScriptMethodsObjectInfo.cpp" = Join-Path $srcRoot "engine/server/library/serverScript/src/shared/ScriptMethodsObjectInfo.cpp"
}
foreach ($entry in $nativePaths.GetEnumerator())
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant() -ceq
        [string]$contract.buildEvidence.nativeSourceSha256.($entry.Key)) `
        "Native level-mutation evidence drifted: $($entry.Key)"
}

$creature = Get-Content -LiteralPath $nativePaths["CreatureObject.cpp"] -Raw
$creatureHeader = Get-Content -LiteralPath $nativePaths["CreatureObject.h"] -Raw
$scriptMethods = Get-Content -LiteralPath $nativePaths["ScriptMethodsObjectInfo.cpp"] -Raw
$setLevel = Get-BracedSurface $creature "void CreatureObject::setLevel(int level)"
$recalculate = Get-BracedSurface $creature "void CreatureObject::recalculateLevel()"
$levelData = Get-BracedSurface $creature "void CreatureObject::setLevelData"
$jniSet = Get-BracedSurface $scriptMethods "jboolean JNICALL ScriptMethodsObjectInfoNamespace::setLevel"
$jniRecalculate = Get-BracedSurface $scriptMethods "jboolean JNICALL ScriptMethodsObjectInfoNamespace::recalculateLevel"
Assert-Contract ($setLevel.Contains("PlayerObject * const playerObject") -and
    $setLevel.Contains("if (playerObject == nullptr)") -and
    $setLevel.Contains("m_level = (int16) level;") -and
    $setLevel.Contains("setLevelData(0, 0, 0);") -and
    -not $setLevel.Contains("LevelManager")) `
    "Native setLevel no longer preserves the player/NPC authority split."
Assert-Contract ($recalculate.Contains("if (playerObject != nullptr)") -and
    $recalculate.Contains("setLevelData(0, 0, 0);") -and
    -not $recalculate.Contains("calculateLevelData") -and
    -not $recalculate.Contains("LevelManager")) `
    "Native recalculateLevel regained NGE player-level authority."
Assert-Contract ($levelData.Contains("getPreCuPlayerCombatDifficulty(*this)") -and
    $levelData.Contains("m_totalLevelXp = 0;") -and
    $levelData.Contains("m_levelHealthGranted = 0;") -and
    $levelData.Contains("m_level = preCuDifficulty;") -and
    $levelData.Contains("group->setMemberLevel(getNetworkId(), preCuDifficulty)")) `
    "Native level data no longer refreshes the hidden PRE-CU difficulty safely."
Assert-Contract ($creatureHeader.Contains("Attributes::Health == attribute && !isPlayerControlled()") -and
    $jniSet.Contains("creature->setLevel(forcedLevel);") -and
    $jniRecalculate.Contains("creature->recalculateLevel();")) `
    "Native player Health guard or Java bridge linkage drifted."

$basePlayer = Get-Content -LiteralPath (Join-Path $scriptRoot "player/base/base_player.java") -Raw
$initialize = Get-BracedSurface $basePlayer "public int OnInitialize(obj_id self)"
Assert-Contract ($initialize.Contains("recalculateLevel(self);") -and
    [bool]$contract.expected.precuPlayerDifficultyRefreshes -and
    -not $initialize.Contains("setLevel(self")) `
    "Player initialization no longer uses the PRE-CU difficulty refresh boundary."

$lostSquadron = Get-Content -LiteralPath (Join-Path $scriptRoot "event/lost_squadron/stolen_fighter.java") -Raw
$ragtag = Get-Content -LiteralPath (Join-Path $scriptRoot "conversation/mtp_ragtag_ames_missd.java") -Raw
$stealth = Get-Content -LiteralPath (Join-Path $scriptRoot "library/stealth.java") -Raw
Assert-Contract ($lostSquadron.Contains("skill.getPrecuEncounterDifficulty(whoTriggeredMe)") -and
    $lostSquadron.Contains("setLevel(thug, playerLevel + levelMod)") -and
    $ragtag.Contains("skill.getPrecuEncounterDifficulty(player)") -and
    $ragtag.Contains("setLevel(npc, mobLevel + 10)") -and
    $stealth.Contains("xp.getPrecuCombatLevel(spy)") -and
    $stealth.Contains("setLevel(hologram, hologramLevel)") -and
    [bool]$contract.expected.retainedNpcLevelMutationPreserved) `
    "Retained non-player content level adapters drifted."

$allJava = $javaFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
$allJavaText = $allJava -join "`n"
$combat = Get-Content -LiteralPath (Join-Path $scriptRoot "library/combat.java") -Raw
Assert-Contract (([regex]::Matches($combat, '\bgetWeaponDamage\s*\(')).Count -eq 1 -and
    ([regex]::Matches($combat, '\bgetAiDamage\s*\(')).Count -eq 2 -and
    ([regex]::Matches($combat, '\bgetAiLevelDiff\s*\(')).Count -eq 2 -and
    ([regex]::Matches($combat, '\bgetConBalanceScalar\s*\(')).Count -eq 2 -and
    ([regex]::Matches($allJavaText, '\bgetWeaponDamage\s*\(')).Count -eq 1 -and
    [bool]$contract.expected.dormantLegacyDamageHelperReachable -eq $false) `
    "Dormant inherited AI level-damage helper gained a production caller."
Assert-Contract (([regex]::Matches($allJavaText,
    'attachScript\s*\([^;]*"working\.difficultytest"')).Count -eq 0 -and
    [bool]$contract.expected.workingDifficultyDiagnosticAttached -eq $false) `
    "Working difficulty diagnostic gained a production attachment."

foreach ($dependency in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependency)
    $dependencyContract = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependencyContract.status -ceq "ready") `
        "Required level-authority contract is not Ready: $dependency"
}

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers) `
        "Java level-mutation callsite closure lacks Ready evidence."
    $state = (& docker inspect --format "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" `
        ([string]$contract.runtimeEvidence.container)).Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $state -ceq "running healthy") `
        "PRE-CU x64 server is not running and healthy."
    $processNames = @(& docker exec ([string]$contract.runtimeEvidence.container) ps -eo comm= |
        ForEach-Object { $_.Trim() })
    Assert-Contract (@($processNames | Where-Object { $_ -ceq "SwgGameServer" }).Count -eq
        [int]$contract.runtimeEvidence.liveGameProcessCount -and
        @($processNames | Where-Object { $_ -ceq "PlanetServer" }).Count -eq
        [int]$contract.runtimeEvidence.livePlanetProcessCount) `
        "Deployed server process topology drifted."
    $classCount = @(& docker exec ([string]$contract.runtimeEvidence.container) find `
        "/swg-precu/data/sku.0/sys.server/compiled/game/script" -type f -name "*.class").Count
    $sourceCount = @(& docker exec ([string]$contract.runtimeEvidence.container) find `
        "/swg-precu-source/dsrc/sku.0/sys.server/compiled/game/script" -type f -name "*.java").Count
    Assert-Contract ($sourceCount -eq [int]$contract.runtimeEvidence.javaSources -and
        $classCount -eq [int]$contract.runtimeEvidence.javaClasses) `
        "Deployed Java source/class totals drifted."
    $binary = "/swg-precu/exe/linux/bin/SwgGameServer"
    $binaryHash = ((& docker exec ([string]$contract.runtimeEvidence.container) sha256sum $binary) -split '\s+')[0]
    $binaryNotes = (& docker exec ([string]$contract.runtimeEvidence.container) readelf -n $binary | Out-String)
    Assert-Contract ($binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $binaryNotes.Contains([string]$contract.buildEvidence.serverBinaryBuildId)) `
        "Deployed x64 server binary evidence drifted."
}

Write-Host "Publish 14.1 Java level-mutation callsite inventory closure passed."
