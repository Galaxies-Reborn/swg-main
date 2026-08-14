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
    ([string]$manifest.contracts.p14JavaComplexLevelCallsiteInventoryClosure)
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
    "Complex level-callsite closure is not pinned to checked-out direct source."

$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"

$pattern = [string]$contract.inventory.pattern
$records = [Collections.Generic.List[object]]::new()
$totalGetLevelCalls = 0
$criticalCallers = 0
foreach ($file in $javaFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $lines = $text -split "`r?`n"
    $relative = $file.FullName.Substring($dsrcRoot.Length + 1).Replace("\", "/")
    $criticalCallers += [regex]::Matches($text, 'combat\.doCriticalHitEffect\s*\(').Count
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; ++$lineIndex)
    {
        if ($lines[$lineIndex] -notmatch '^\s*(public|private|protected)\s+.*\bgetLevel\s*\(')
        {
            $totalGetLevelCalls += [regex]::Matches($lines[$lineIndex], '\bgetLevel\s*\(').Count
        }
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
            "Could not classify complex level call in $relative."
        $records.Add([pscustomobject]@{
            Path = $relative
            Line = $lineIndex + 1
            Method = $method
            Expression = $lines[$lineIndex].Trim()
        })
    }
}

$sourceFiles = @($records.Path | Sort-Object -Unique)
$canonical = (@($records | Sort-Object Path, Line | ForEach-Object {
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
    "Complex Java level-callsite inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFiles = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFiles.Count) `
    "Complex Java level-callsite source-file set changed."
foreach ($property in $expectedFiles)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Complex Java level-callsite count drifted: $($property.Name)"
}

$dependencies = @{}
foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required dependency is not Ready: $dependencyName"
    $dependencies[$dependencyName] = $dependency
}

$playerInventory = $dependencies["p14-java-player-level-callsite-inventory-closure.json"]
$objectInventory = $dependencies["p14-java-residual-object-level-callsite-inventory-closure.json"]
$surface = $contract.completeJavaGetLevelSurface
Assert-Contract ($totalGetLevelCalls -eq [int]$surface.totalCallSites -and
    [int]$playerInventory.inventory.callSites -eq [int]$surface.playerSelfOwnerCallSites -and
    [int]$objectInventory.inventory.callSites -eq [int]$surface.residualSimpleObjectCallSites -and
    $records.Count -eq [int]$surface.complexExpressionCallSites -and
    ([int]$surface.playerSelfOwnerCallSites +
        [int]$surface.residualSimpleObjectCallSites +
        [int]$surface.complexExpressionCallSites) -eq $totalGetLevelCalls -and
    [int]$surface.unclassifiedCallSites -eq 0) `
    "The three Java getLevel inventories do not cover the complete call surface."

$combatPath = Join-Path $scriptRoot "library/combat.java"
$combatBasePath = Join-Path $scriptRoot "systems/combat/combat_base.java"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $combatPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."combat.java" -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $combatBasePath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."combat_base.java") `
    "Complex Java level-callsite source evidence drifted."

$combat = Get-Content -LiteralPath $combatPath -Raw
$combatBase = Get-Content -LiteralPath $combatBasePath -Raw
$criticalEffect = Get-BracedSurface $combat `
    "public static float doCriticalHitEffect(attacker_data attackerData, defender_data defenderData, weapon_data weaponData, hit_result hitData, combat_data actionData)"
Assert-Ordered $criticalEffect @(
    "int level = getLevel(attackerData.id);",
    "if (level == 90)",
    '"crit_fire_dot_4"',
    "else if (level >= 75)",
    '"crit_fire_dot_3"',
    "else if (level >= 50)",
    '"crit_fire_dot_2"',
    "else if (level >= 25)",
    '"crit_fire_dot_1"'
) "retained NGE critical compatibility"

$runHit = Get-BracedSurface $combatBase `
    "public hit_result[] runHitEngine(attacker_data attackerData, weapon_data weaponData, defender_data[] defenderData, attacker_results attackerResults, defender_results[] defenderResults, combat_data actionData, boolean isTangibleAttacking, boolean isAutoAiming, int overloadDamage)"
Assert-Ordered $runHit @(
    "boolean precuAuthoritativeAttack =",
    "if (precuAuthoritativeAttack)",
    "getPrecuPrimaryAttackResult(",
    "if (!precuAuthoritativeAttack && hitData[i].critical)",
    "combat.doCriticalHitEffect("
) "complex level-callsite compatibility caller"

Assert-Contract ($criticalCallers -eq [int]$contract.expected.criticalCompatibilityCallers -and
    [bool]$contract.expected.criticalCompatibilityGuardedByNonPrecuRoute -and
    [int]$contract.classification.retainedNgeCriticalCompatibility.callSites -eq 1 -and
    [string]$contract.classification.retainedNgeCriticalCompatibility.inventorySha256 -ceq
        (Get-TextSha256 $canonical) -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    [int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [int]$contract.expected.playerCombatLevelGameplayAuthorityCallSites -eq 0 -and
    [bool]$contract.expected.retainedLaterCombatContentPreserved) `
    "Complex Java level-callsite authority boundary is incomplete."

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
        "Complex Java level-callsite closure is not Ready."
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
        "Complex Java level-callsite closure is not build-eligible."
}

Write-Host "Publish 14.1 Java complex level-callsite inventory closure passed."
