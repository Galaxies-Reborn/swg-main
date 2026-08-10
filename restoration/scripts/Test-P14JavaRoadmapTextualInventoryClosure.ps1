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
    ([string]$manifest.contracts.p14JavaRoadmapTextualInventoryClosure)
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
    $open = $Text.IndexOf("{", $start)
    if ($open -lt 0) { throw "Missing opening brace: $Signature" }
    $depth = 0
    for ($i = $open; $i -lt $Text.Length; $i++)
    {
        if ($Text[$i] -ceq '{') { $depth++ }
        elseif ($Text[$i] -ceq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $i - $start + 1) }
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
    "Java roadmap closure is not pinned to checked-out direct source."

$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"
Assert-Contract ($null -ne (Get-Command rg -ErrorAction SilentlyContinue)) `
    "ripgrep is required for the exact Java roadmap inventory."

$categoryNames = @(
    "runtimeRetirementAndRetainedContent",
    "qaJtlAndTestDiagnostics"
)
$fileCategory = @{}
foreach ($categoryName in $categoryNames)
{
    $category = $contract.classification.$categoryName
    Assert-Contract (@($category.sourceFiles).Count -eq [int]$category.sourceFileCount) `
        "Java roadmap category source count drifted in contract: $categoryName"
    foreach ($relativePath in @($category.sourceFiles))
    {
        $relativePath = [string]$relativePath
        Assert-Contract (-not $fileCategory.ContainsKey($relativePath)) `
            "Java roadmap category files overlap: $relativePath"
        Assert-Contract (Test-Path -LiteralPath (Join-Path $scriptRoot $relativePath) -PathType Leaf) `
            "Java roadmap category source is missing: $relativePath"
        $fileCategory[$relativePath] = $categoryName
    }
}

$rgOutput = @(& rg --json -i --glob "*.java" '\broadmap\b' $scriptRoot)
$rgExit = $LASTEXITCODE
Assert-Contract ($rgExit -eq 0) "Could not enumerate the Java roadmap inventory."
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
        [StringComparison]::OrdinalIgnoreCase)) "Roadmap marker escaped the Java source root."
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $categoryName = if ($fileCategory.ContainsKey($relativePath))
    {
        [string]$fileCategory[$relativePath]
    }
    else { "unclassified" }
    $rawLine = [string]$entry.data.lines.text
    $expression = $rawLine.Trim()
    foreach ($submatch in @($entry.data.submatches))
    {
        $column = [int]$submatch.start + 1
        $beforeMatch = $rawLine.Substring(0, [int]$submatch.start)
        $trimmedStart = $rawLine.TrimStart()
        $context = if ($beforeMatch.Contains("//") -or
            $beforeMatch.Contains("/*") -or $trimmedStart.StartsWith("*"))
        {
            "comment"
        }
        elseif ((@($beforeMatch.ToCharArray() | Where-Object { $_ -eq '"' }).Count % 2) -eq 1)
        {
            "stringLiteral"
        }
        else { "executableIdentifierOrControl" }
        $records.Add([pscustomobject]@{
            Path = $relativePath
            Line = [int]$entry.data.line_number
            Column = $column
            Value = [string]$submatch.match.text
            Expression = $expression
            Category = $categoryName
            Context = $context
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
    $fileCategory.Count -eq $sourceFiles.Count -and
    (Get-InventorySha256 $sortedRecords) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Complete Java roadmap textual inventory drifted."

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
        "Java roadmap classification drifted: $categoryName"
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $sortedRecords.Count -and
    @($sortedRecords | Where-Object { $_.Category -ceq "unclassified" }).Count -eq 0 -and
    [int]$contract.classification.unclassifiedReferenceOccurrences -eq 0 -and
    [bool]$contract.expected.allReferencesClassified) `
    "Java roadmap inventory is not fully classified."

$commentRecords = @($sortedRecords | Where-Object { $_.Context -ceq "comment" })
$stringRecords = @($sortedRecords | Where-Object { $_.Context -ceq "stringLiteral" })
$executableRecords = @($sortedRecords | Where-Object {
    $_.Context -ceq "executableIdentifierOrControl"
})
Assert-Contract ($commentRecords.Count -eq [int]$contract.syntaxContext.commentOccurrences -and
    $stringRecords.Count -eq [int]$contract.syntaxContext.stringLiteralOccurrences -and
    $executableRecords.Count -eq [int]$contract.syntaxContext.executableIdentifierOrControlOccurrences -and
    $executableRecords.Count -eq [int]$contract.expected.executableRoadmapMarkerOccurrences) `
    "A standalone roadmap marker escaped comment/string confinement."

$skillTemplate = Get-Content -LiteralPath (Join-Path $scriptRoot "library/skill_template.java") -Raw
$pgc = Get-Content -LiteralPath (Join-Path $scriptRoot "library/pgc_quests.java") -Raw
$nativePlayer = Get-Content -LiteralPath (Join-Path $srcRoot `
    "engine/server/library/serverGame/src/shared/object/PlayerObject.cpp") -Raw
$roadmapGrant = Get-BracedSurface $skillTemplate "public static boolean grantRoadmapItem"
$chroniclesGrant = Get-BracedSurface $pgc "public static boolean grantChroniclesRoadmapItem"
Assert-Contract ($roadmapGrant.Contains("getWorkingSkill(player)") -and
    $roadmapGrant.Contains("getSkillTemplate(player)") -and
    $roadmapGrant.Contains("getRoadmapItem(player, skillTemplate, skillName)") -and
    $nativePlayer.Contains("m_skillTemplate.set(std::string());") -and
    $nativePlayer.Contains("m_workingSkill.set(std::string());")) `
    "Generic roadmap reward compatibility escaped the native empty-state boundary."
$chroniclesGuardAt = $chroniclesGrant.IndexOf("if (isRetiredChroniclesPlayerProgression())",
    [StringComparison]::Ordinal)
$chroniclesMutationAt = $chroniclesGrant.IndexOf("createObjectInInventoryAllowOverload",
    [StringComparison]::Ordinal)
Assert-Contract ($chroniclesGuardAt -ge 0 -and $chroniclesMutationAt -gt $chroniclesGuardAt -and
    $chroniclesGrant.IndexOf("return false;", $chroniclesGuardAt,
        [StringComparison]::Ordinal) -lt $chroniclesMutationAt) `
    "Chronicles roadmap item grants no longer fail closed before mutation."
Assert-Contract ($skillTemplate.Contains('datatables/roadmap/item_rewards.iff') -and
    (Get-Content -LiteralPath (Join-Path $scriptRoot "test/qatool.java") -Raw).
        Contains("NGE class, level, and roadmap mutation is retired") -and
    (Get-Content -LiteralPath (Join-Path $scriptRoot "test/qa_jtl_tools.java") -Raw).
        Contains("Select a Pilot Roadmap")) `
    "Retained reward data, retired ground tooling, or JTL pilot compatibility drifted."

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
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required dependency is not Ready: $dependencyKey"
}

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [int]$contract.expected.productionGroundRoadmapAuthorityLeaks -eq 0 -and
    [int]$contract.expected.retainedRoadmapRewardRows -eq 303 -and
    [int]$contract.expected.retainedAuthenticatedJtlPilotRoadmapSourceFiles -eq 3 -and
    [bool]$contract.expected.laterZonesQuestsConversationsNpcsAndJtlContentPreserved) `
    "Java roadmap expected PRE-CU boundary is incomplete."

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
        "Java roadmap textual inventory closure lacks Ready evidence."
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
        "Java roadmap textual inventory closure is not build-eligible."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Java roadmap textual inventory closure references forbidden host staging."

Write-Host "Complete Publish 14.1 Java roadmap textual inventory closure passed."
