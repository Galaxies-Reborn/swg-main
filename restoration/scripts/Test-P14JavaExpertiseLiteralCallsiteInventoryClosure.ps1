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
$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14JavaExpertiseLiteralCallsiteInventoryClosure)
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

$directPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$nativePin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$directCommit = (& git -C $dsrcRoot rev-parse HEAD).Trim()
$nativeCommit = (& git -C (Join-Path $root "src") rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $directPin.Count -eq 1 -and $nativePin.Count -eq 1 -and
    [string]$directPin[0].commit -ceq $directCommit -and
    [string]$nativePin[0].commit -ceq $nativeCommit -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $nativeCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "Java expertise literal closure is not pinned to checked-out direct source."

$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"

$combatFiles = @(
    "sku.0/sys.server/compiled/game/script/library/combat.java",
    "sku.0/sys.server/compiled/game/script/library/buff.java",
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java",
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java",
    "sku.0/sys.server/compiled/game/script/systems/buff/buff_handler.java"
)
$frameworkFiles = @(
    "sku.0/sys.server/compiled/game/script/library/expertise.java",
    "sku.0/sys.server/compiled/game/script/library/skill.java",
    "sku.0/sys.server/compiled/game/script/library/respec.java",
    "sku.0/sys.server/compiled/game/script/player/live_conversions.java"
)
$spyBeastFiles = @(
    "sku.0/sys.server/compiled/game/script/library/stealth.java",
    "sku.0/sys.server/compiled/game/script/library/beast_lib.java"
)
$diagnosticFiles = @(
    "sku.0/sys.server/compiled/game/script/test/thicks_test.java",
    "sku.0/sys.server/compiled/game/script/working/jhaskell_test.java"
)

$pattern = [string]$contract.inventory.pattern
$records = [Collections.Generic.List[object]]::new()
foreach ($file in $javaFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $lines = $text -split '\r?\n'
    $relative = $file.FullName.Substring($dsrcRoot.Length + 1).Replace("\", "/")
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; ++$lineIndex)
    {
        foreach ($match in [regex]::Matches($lines[$lineIndex], $pattern))
        {
            if ($combatFiles -contains $relative) { $category = "combatBuffPlayerGuards" }
            elseif ($frameworkFiles -contains $relative) { $category = "retiredPlayerFramework" }
            elseif ($spyBeastFiles -contains $relative) { $category = "retiredSpyBeastRuntime" }
            elseif ($relative -ceq "sku.0/sys.server/compiled/game/script/item/heroic_random_stat_item.java")
            {
                $category = "retainedItemCompatibility"
            }
            elseif ($diagnosticFiles -contains $relative) { $category = "testDiagnostics" }
            else { $category = "unclassified" }
            $records.Add([pscustomobject]@{
                Path = $relative
                Line = $lineIndex + 1
                Column = $match.Index + 1
                Value = $match.Value
                Expression = $lines[$lineIndex].Trim()
                Category = $category
            })
        }
    }
}
$records = @($records | Sort-Object Path, Line, Column, Value)
$sourceFiles = @($records.Path | Sort-Object -Unique)
$matchingLines = @($records | ForEach-Object { "$($_.Path)|$($_.Line)" } | Sort-Object -Unique)
$canonical = (@($records | ForEach-Object {
    "$($_.Path)|$($_.Line)|$($_.Column)|$($_.Value)|$($_.Expression)"
}) -join "`n") + "`n"
$sourceSet = ($sourceFiles -join "`n") + "`n"
$sourceContent = (@($sourceFiles | ForEach-Object {
    "$_=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dsrcRoot $_)).Hash.ToLowerInvariant()
}) -join "`n") + "`n"
Assert-Contract ($records.Count -eq [int]$contract.inventory.referenceOccurrences -and
    $matchingLines.Count -eq [int]$contract.inventory.matchingLines -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-TextSha256 $canonical) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Java expertise literal inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileProperties = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileProperties.Count) `
    "Java expertise source-file set changed."
foreach ($property in $expectedFileProperties)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Java expertise count drifted: $($property.Name)"
}

$classificationNames = @(
    "combatBuffPlayerGuards",
    "retiredPlayerFramework",
    "retiredSpyBeastRuntime",
    "retainedItemCompatibility",
    "testDiagnostics"
)
$classifiedCount = 0
foreach ($category in $classificationNames)
{
    $classified = @($records | Where-Object { $_.Category -ceq $category })
    $categoryCanonical = (@($classified | ForEach-Object {
        "$($_.Path)|$($_.Line)|$($_.Column)|$($_.Value)|$($_.Expression)"
    }) -join "`n") + "`n"
    $expected = $contract.classification.$category
    Assert-Contract ($classified.Count -eq [int]$expected.referenceOccurrences -and
        (Get-TextSha256 $categoryCanonical) -ceq [string]$expected.inventorySha256) `
        "Java expertise classification drifted: $category"
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $records.Count -and
    @($records | Where-Object { $_.Category -ceq "unclassified" }).Count -eq 0 -and
    [int]$contract.classification.unclassifiedReferenceOccurrences -eq 0 -and
    [bool]$contract.expected.allReferencesClassified -and
    [int]$contract.expected.playerExpertiseProgressionOrGameplayAuthorityOccurrences -eq 0) `
    "Java expertise literal inventory is not fully closed."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required expertise dependency is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required expertise dependency is not Ready: $dependencyName"
}

$expertise = Get-Content -LiteralPath (Join-Path $scriptRoot "library/expertise.java") -Raw
$cache = Get-BracedSurface $expertise `
    "public static void cacheExpertiseProcReacList(obj_id player)"
$cacheGuard = $cache.IndexOf("proc.isRetiredPostNgePlayerProcActor(player)", [StringComparison]::Ordinal)
$cacheRead = $cache.IndexOf("getSkillStatModListingForPlayer(player)", [StringComparison]::Ordinal)
$autoAllocate = Get-BracedSurface $expertise `
    "public static void autoAllocateExpertiseByLevel(obj_id player, boolean onLevel)"
$allowedSkill = Get-BracedSurface $expertise `
    "public static boolean isProfAllowedSkill(obj_id player, String skillName)"
Assert-Contract ($cacheGuard -ge 0 -and $cacheGuard -lt $cacheRead -and
    $autoAllocate -match '\{\s*return;\s*\}$' -and
    $allowedSkill -match '\{\s*return false;\s*\}$') `
    "Expertise admission or proc caching no longer fails closed."

$skill = Get-Content -LiteralPath (Join-Path $scriptRoot "library/skill.java") -Raw
Assert-Contract ($skill.Contains('skillName.equals("expertise")') -and
    $skill.Contains('skillName.startsWith("expertise_")') -and
    $skill.Contains('skillName.startsWith("internal_expertise_")') -and
    $skill.Contains("if (isPlayer(target) && isRetiredNgeProgressionSkillName(skillName))")) `
    "Shared skill admission no longer rejects expertise roots."

$respec = Get-Content -LiteralPath (Join-Path $scriptRoot "library/respec.java") -Raw
Assert-Contract ($respec.Contains("NGE_PLAYER_RESPEC_RUNTIME_RETIRED = true") -and
    [regex]::Matches($respec, 'retireNgePlayerRespecEntrypoint\(player\)').Count -eq
        [int]$contract.expected.playerRespecGuardedEntrypoints) `
    "Player-facing NGE respec entrypoints are no longer fail-closed."
$liveConversions = Get-Content -LiteralPath (Join-Path $scriptRoot "player/live_conversions.java") -Raw
Assert-Contract ($liveConversions.Contains('removeObjVar(player, "expertise_reset")') -and
    $liveConversions.Contains("retirePostNgePlayerMigrationState")) `
    "Persisted NGE expertise migration state is not retired."

$heroic = Get-Content -LiteralPath (Join-Path $scriptRoot "item/heroic_random_stat_item.java") -Raw
Assert-Contract ([regex]::Matches($heroic, '"expertise_action_weapon_[0-9]+"').Count -eq 10 -and
    [regex]::Matches($heroic, 'setObjVar\([^\r\n]*expertise_action_weapon_').Count -eq
        [int]$contract.expected.heroicExpertiseWriters -and
    [regex]::Matches($heroic, 'removeLegacyNgeModifiers\(self\);').Count -eq 3) `
    "Heroic item expertise compatibility names gained writer authority."
$beast = Get-Content -LiteralPath (Join-Path $scriptRoot "library/beast_lib.java") -Raw
Assert-Contract ($beast.Contains('removeAttribOrSkillModModifier(beast, "expertise_damage_line_beast_only")')) `
    "Retained Beast expertise reference is no longer cleanup-only."

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        $contract.requiredBeforeReady.Count -eq 0 -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "Java expertise literal closure lacks Ready evidence."
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "Java expertise literal source status is invalid."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Java expertise literal closure references prohibited host staging."
Write-Host "Java expertise_* literal callsite inventory closure passed."
