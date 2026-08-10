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
    ([string]$manifest.contracts.p14JavaResidualObjectLevelCallsiteInventoryClosure)
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
    "Residual object-level closure is not pinned to checked-out direct source."

$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"

$pattern = [string]$contract.inventory.pattern
$records = [Collections.Generic.List[object]]::new()
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
        $records.Add([pscustomobject]@{
            Path = $relative
            Line = $lineIndex + 1
            Method = $method
            Expression = $lines[$lineIndex].Trim()
            Category = ""
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
    "Residual Java object-level callsite inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileProperties = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileProperties.Count) `
    "Residual Java object-level source-file set changed."
foreach ($property in $expectedFileProperties)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Residual Java object-level count drifted: $($property.Name)"
}

foreach ($record in $records)
{
    if ($record.Path -match '/(library/combat|systems/combat/combat_base|systems/combat/combat_base_old)\.java$')
    {
        $record.Category = "precuBypassedOrPlayerExcludedCombat"
    }
    elseif ($record.Path -match '/beta/' -or $record.Path -match '/test/')
    {
        $record.Category = "adminTestDiagnostics"
    }
    elseif ($record.Path -match '/library/(beast_lib|bounty_hunter|storyteller)\.java$' -or
        $record.Path -match '/event/ewok_festival/' -or
        $record.Path -match '/ai/smuggler_spawn_enemy\.java$' -or
        $record.Path -match '/systems/storyteller/')
    {
        $record.Category = "retainedLaterContent"
    }
    elseif ($record.Path -match '/item/trap/' -or
        $record.Path -match '/library/(bio_engineer|corpse|factions|loot|metrics|scout|xp)\.java$' -or
        $record.Path -match '/player/player_building\.java$' -or
        $record.Path -match '/player/skill/taming\.java$' -or
        $record.Path -match '/systems/crafting/droid/modules/(harvest_module|trap_thrower)\.java$')
    {
        $record.Category = "precuPlayerFacingNpcSystems"
    }
    else
    {
        $record.Category = "retainedCreaturePetSystems"
    }
}

$classificationNames = @(
    "precuBypassedOrPlayerExcludedCombat",
    "precuPlayerFacingNpcSystems",
    "retainedCreaturePetSystems",
    "retainedLaterContent",
    "adminTestDiagnostics"
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
        "Residual Java object-level classification drifted: $category"
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $records.Count -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    [bool]$contract.expected.allCallSitesClassified -and
    [int]$contract.expected.playerCombatLevelGameplayAuthorityCallSites -eq 0 -and
    [int]$contract.expected.closedPlayerSelfOwnerCallSitesExcluded -eq 56) `
    "Residual Java object-level inventory is not fully closed."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required dependency is not Ready: $dependencyName"
}

$criticalPaths = [ordered]@{
    "combat.java" = "library/combat.java"
    "combat_base.java" = "systems/combat/combat_base.java"
    "bounty_hunter.java" = "library/bounty_hunter.java"
    "beast_lib.java" = "library/beast_lib.java"
    "player_building.java" = "player/player_building.java"
    "xp.java" = "library/xp.java"
}
foreach ($entry in $criticalPaths.GetEnumerator())
{
    $criticalPath = Join-Path $scriptRoot $entry.Value
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $criticalPath).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.criticalSourceSha256.PSObject.Properties[$entry.Key].Value
    Assert-Contract ($actualHash -ceq $expectedHash) `
        "Critical object-level source evidence drifted: $($entry.Key)"
}

$combat = Get-Content -LiteralPath (Join-Path $scriptRoot "library/combat.java") -Raw
$combatBase = Get-Content -LiteralPath (Join-Path $scriptRoot "systems/combat/combat_base.java") -Raw
$bounty = Get-Content -LiteralPath (Join-Path $scriptRoot "library/bounty_hunter.java") -Raw
$beast = Get-Content -LiteralPath (Join-Path $scriptRoot "library/beast_lib.java") -Raw
$building = Get-Content -LiteralPath (Join-Path $scriptRoot "player/player_building.java") -Raw

$runHit = Get-BracedSurface $combatBase `
    "public hit_result[] runHitEngine(attacker_data attackerData, weapon_data weaponData, defender_data[] defenderData, attacker_results attackerResults, defender_results[] defenderResults, combat_data actionData, boolean isTangibleAttacking, boolean isAutoAiming, int overloadDamage)"
Assert-Ordered $runHit @(
    "boolean precuAuthoritativeAttack =",
    "if (precuAuthoritativeAttack)",
    "getPrecuPrimaryAttackResult(",
    "getPrecuSecondaryDefenseResult(",
    "else",
    "getDefenderResult(",
    "getAttackerResult("
) "PRE-CU hit routing"

$rawDamage = Get-BracedSurface $combatBase `
    "public dictionary getRawDamage(obj_id attacker, obj_id defender, weapon_data weaponData, combat_data actionData, hit_result hitData, float minDamage, float maxDamage, int numTargets)"
Assert-Ordered $rawDamage @(
    "if (isPrecuAuthoritativeAttack(attacker, actionData))",
    "return getPrecuCore3RawDamage(",
    'getEnhancedSkillStatisticModifierUncapped(attacker, "level_add_to_damage")',
    "getLevel(attacker)"
) "PRE-CU raw-damage routing"

$aiLevel = Get-BracedSurface $combat `
    "public static int getAiLevelDiff(obj_id attacker, obj_id defender)"
Assert-Ordered $aiLevel @(
    "if (isPlayer(attacker))",
    "return 0;",
    "getLevel(attacker)",
    "getLevel(defender)"
) "AI level-difference player exclusion"

$critical = Get-BracedSurface $combat `
    "public static float getAttackerCritMod(obj_id attacker)"
Assert-Contract ($critical.Contains(
    "isPlayer(attacker) ? 5.0f : getLevel(attacker) * 0.15f")) `
    "Critical modifier can derive player authority from object level."

$killMeter = Get-BracedSurface $combatBase `
    "public void doKillMeterUpdate(obj_id attacker, obj_id defender, int damage)"
Assert-Ordered $killMeter @(
    "boolean playerAttacker = isPlayer(attacker)",
    "boolean playerDefender = isPlayer(defender)",
    "boolean compatibleAttacker = !playerAttacker",
    "boolean compatibleDefender = !playerDefender",
    "getLevel(attacker)",
    "getLevel(defender)"
) "kill-meter player exclusion"

$bountyCheck = Get-BracedSurface $bounty `
    "public static boolean canCheckForBounty(obj_id player, obj_id target)"
Assert-Ordered $bountyCheck @(
    "if (!ai_lib.isNpc(target))",
    "return false;",
    "int targetLevel = getLevel(target)"
) "NPC bounty target boundary"

$enzyme = Get-BracedSurface $beast `
    "public static obj_id generateTypeThreeEnzyme(obj_id player, obj_id target, float enzymePurity, float enzymeMutagen, String trait)"
Assert-Ordered $enzyme @(
    "if (isRetiredPostNgeBeastMasterPlayer(player))",
    "return obj_id.NULL_ID;",
    "getLevel(target)",
    "getLevel(player)"
) "Beast Master enzyme retirement"

$privacy = Get-BracedSurface $building `
    "public int setPrivacy(obj_id self, obj_id target, String params, float defaultTime)"
Assert-Contract ($privacy.Contains(
    "isPlayer(object) || (isMob(object) && isIdValid(getMaster(object))) || (isMob(object) && (getLevel(object)) >= 10)")) `
    "Building privacy can evaluate player object level."

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [bool]$contract.expected.laterZonesQuestsConversationsAndNpcCompatibilityPreserved) `
    "Aggregate closure claims an invalid mutation boundary."

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
        [long]$contract.runtimeEvidence.liveBinaryInode -eq 12141610 -and
        [long]$contract.runtimeEvidence.liveBinaryBytes -eq 22561064 -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Residual Java object-level callsite closure is not Ready."
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
        "Residual Java object-level closure is not build-eligible."
}

Write-Host "Publish 14.1 Java residual object-level callsite inventory closure passed."
