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
    ([string]$manifest.contracts.p14JavaExplicitNgeTextualInventoryClosure)
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
    "Java explicit-NGE closure is not pinned to checked-out direct source."

$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"
Assert-Contract ($null -ne (Get-Command rg -ErrorAction SilentlyContinue)) `
    "ripgrep is required for the exact Java explicit-NGE inventory."

$categoryNames = @(
    "runtimePrecuGuardsAndRetainedContent",
    "administrativeAndDeveloperDiagnostics",
    "testDiagnosticsAndFixtures"
)
$fileCategory = @{}
foreach ($categoryName in $categoryNames)
{
    $category = $contract.classification.$categoryName
    Assert-Contract (@($category.sourceFiles).Count -eq [int]$category.sourceFileCount) `
        "Java explicit-NGE category source count drifted in contract: $categoryName"
    foreach ($relativePath in @($category.sourceFiles))
    {
        $relativePath = [string]$relativePath
        Assert-Contract (-not $fileCategory.ContainsKey($relativePath)) `
            "Java explicit-NGE category files overlap: $relativePath"
        Assert-Contract (Test-Path -LiteralPath (Join-Path $scriptRoot $relativePath) -PathType Leaf) `
            "Java explicit-NGE category source is missing: $relativePath"
        $fileCategory[$relativePath] = $categoryName
    }
}

$rgOutput = @(& rg --json -i --glob "*.java" '\bNGE\b' $scriptRoot)
$rgExit = $LASTEXITCODE
Assert-Contract ($rgExit -eq 0) "Could not enumerate the Java explicit-NGE inventory."
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
        [StringComparison]::OrdinalIgnoreCase)) "NGE marker escaped the Java source root."
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
$actualInventorySha256 = Get-InventorySha256 $sortedRecords
$actualSourceSetSha256 = Get-TextSha256 $sourceSet
$actualSourceContentSha256 = Get-TextSha256 $sourceContent
Assert-Contract ($sortedRecords.Count -eq [int]$contract.inventory.referenceOccurrences -and
    $matchingLines.Count -eq [int]$contract.inventory.matchingLines -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    $fileCategory.Count -eq $sourceFiles.Count -and
    $actualInventorySha256 -ceq [string]$contract.inventory.inventorySha256 -and
    $actualSourceSetSha256 -ceq [string]$contract.inventory.sourceSetSha256 -and
    $actualSourceContentSha256 -ceq [string]$contract.inventory.sourceContentSha256) `
    "Complete Java explicit-NGE textual inventory drifted: occurrences=$($sortedRecords.Count), lines=$($matchingLines.Count), files=$($sourceFiles.Count), inventory=$actualInventorySha256, sourceSet=$actualSourceSetSha256, sourceContent=$actualSourceContentSha256."

$classifiedCount = 0
foreach ($categoryName in $categoryNames)
{
    $classified = @($sortedRecords | Where-Object { $_.Category -ceq $categoryName })
    $classifiedLines = @($classified | ForEach-Object { "$($_.Path):$($_.Line)" } | Sort-Object -Unique)
    $classifiedFiles = @($classified.Path | Sort-Object -Unique)
    $expectedCategory = $contract.classification.$categoryName
    $actualCategorySha256 = Get-InventorySha256 $classified
    Assert-Contract ($classified.Count -eq [int]$expectedCategory.referenceOccurrences -and
        $classifiedLines.Count -eq [int]$expectedCategory.matchingLines -and
        $classifiedFiles.Count -eq [int]$expectedCategory.sourceFileCount -and
        $actualCategorySha256 -ceq [string]$expectedCategory.inventorySha256) `
        "Java explicit-NGE classification drifted: $categoryName; occurrences=$($classified.Count), lines=$($classifiedLines.Count), files=$($classifiedFiles.Count), inventory=$actualCategorySha256."
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $sortedRecords.Count -and
    @($sortedRecords | Where-Object { $_.Category -ceq "unclassified" }).Count -eq 0 -and
    [int]$contract.classification.unclassifiedReferenceOccurrences -eq 0 -and
    [bool]$contract.expected.allReferencesClassified) `
    "Java explicit-NGE inventory is not fully classified."

$commentRecords = @($sortedRecords | Where-Object { $_.Context -ceq "comment" })
$stringRecords = @($sortedRecords | Where-Object { $_.Context -ceq "stringLiteral" })
$executableRecords = @($sortedRecords | Where-Object {
    $_.Context -ceq "executableIdentifierOrControl"
})
$runtimeStrings = @($stringRecords | Where-Object {
    $_.Category -ceq "runtimePrecuGuardsAndRetainedContent"
})
Assert-Contract ($commentRecords.Count -eq [int]$contract.syntaxContext.commentOccurrences -and
    $stringRecords.Count -eq [int]$contract.syntaxContext.stringLiteralOccurrences -and
    $executableRecords.Count -eq
        [int]$contract.syntaxContext.executableIdentifierOrControlOccurrences -and
    $runtimeStrings.Count -eq [int]$contract.syntaxContext.runtimeRetirementStringOccurrences -and
    $executableRecords.Count -eq [int]$contract.expected.executableNgeMarkerOccurrences) `
    "An explicit NGE marker escaped comment/string confinement."
Assert-Contract (@($runtimeStrings | Where-Object {
    $_.Expression -notmatch '(?i)(retir|reject|ignor|omit|not reimbursed)'
}).Count -eq [int]$contract.expected.productionNgeGrantOrAdmissionStringOccurrences) `
    "A runtime NGE string no longer reports rejection, omission, or cleanup."

Assert-Contract ((Get-Content -LiteralPath (Join-Path $scriptRoot "developer/script_editor.java") -Raw).
        Contains("nge-swg-master/utils/mocha/script_prep2.py") -and
    (Get-Content -LiteralPath (Join-Path $scriptRoot "combat_engine.java") -Raw).
        Contains("without NGE reflect logic") -and
    (Get-Content -LiteralPath (Join-Path $scriptRoot "player/player_saga_quest.java") -Raw).
        Contains("Chronicles is an NGE-only progression system") -and
    (Get-Content -LiteralPath (Join-Path $scriptRoot "systems/jedi/jedi_saber_component.java") -Raw).
        Contains("NGE combat level")) `
    "Representative developer, combat, Chronicles, or Jedi marker classification drifted."

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
    if ($dependencyKey -ceq "p14DataGrantPersistenceClosure" -and
        $dependencyStatus -ceq "implemented-build-pending")
    {
        & (Join-Path $PSScriptRoot "Test-P14DataGrantPersistenceClosure.ps1") `
            -SourceRoot $root `
            -Expectation Source
    }
    elseif ($dependencyKey -ceq "p14ChroniclesScriptLifecycleRetirement" -and
        $dependencyStatus -ceq "implemented-build-pending")
    {
        & (Join-Path $PSScriptRoot "Test-P14ChroniclesScriptLifecycleRetirement.ps1") `
            -SourceRoot $root `
            -Expectation Build
    }
    Assert-Contract ($dependencyStatus -ceq "ready" -or
        (@("p14DataGrantPersistenceClosure", "p14ChroniclesScriptLifecycleRetirement") -contains
            $dependencyKey -and
            $dependencyStatus -ceq "implemented-build-pending")) `
        "Required dependency is not Ready: $dependencyKey"
}

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [bool]$contract.expected.laterZonesQuestsConversationsAndNpcCompatibilityPreserved) `
    "Java explicit-NGE expected PRE-CU boundary is incomplete."

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
        "Java explicit-NGE textual inventory closure lacks Ready evidence."
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
        "Java explicit-NGE textual inventory closure is not build-eligible."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Java explicit-NGE textual inventory closure references forbidden host staging."

Write-Host "Complete Publish 14.1 Java explicit-NGE textual inventory closure passed."
