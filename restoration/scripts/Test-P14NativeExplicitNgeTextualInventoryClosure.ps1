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
    ([string]$manifest.contracts.p14NativeExplicitNgeTextualInventoryClosure)
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
    "Native explicit-NGE inventory is not pinned to checked-out direct source."

$extensions = @($contract.inventory.extensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
$nativeFiles = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File |
    Where-Object { $extensions -ccontains $_.Extension.ToLowerInvariant() })
Assert-Contract ($nativeFiles.Count -eq [int]$contract.inventory.nativeSources) `
    "Native C/C++ source inventory drifted: $($nativeFiles.Count)"

$pattern = [string]$contract.inventory.pattern
$records = [Collections.Generic.List[object]]::new()
foreach ($file in $nativeFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $lines = $text -split "`r?`n"
    $relative = $file.FullName.Substring($srcRoot.Length + 1).Replace("\", "/")
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; ++$lineIndex)
    {
        foreach ($match in [regex]::Matches($lines[$lineIndex], $pattern))
        {
            $before = $lines[$lineIndex].Substring(0, $match.Index)
            $quoteCount = [regex]::Matches($before, '(?<!\\)"').Count
            $commentIndex = $lines[$lineIndex].IndexOf("//", [StringComparison]::Ordinal)
            $kind = if (($quoteCount % 2) -eq 1)
            {
                "string"
            }
            elseif ($commentIndex -ge 0 -and $commentIndex -lt $match.Index)
            {
                "comment"
            }
            else
            {
                "other"
            }
            $records.Add([pscustomobject]@{
                Path = $relative
                Line = $lineIndex + 1
                Column = $match.Index + 1
                Kind = $kind
                Expression = $lines[$lineIndex].Trim()
            })
        }
    }
}

$sourceFiles = @($records.Path | Sort-Object -Unique)
$canonical = (@($records | Sort-Object Path, Line, Column | ForEach-Object {
    "$($_.Path)|$($_.Line)|$($_.Column)|$($_.Kind)|$($_.Expression)"
}) -join "`n") + "`n"
$sourceSet = ($sourceFiles -join "`n") + "`n"
$sourceContent = (@($sourceFiles | ForEach-Object {
    "$_=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $srcRoot $_)).Hash.ToLowerInvariant()
}) -join "`n") + "`n"
Assert-Contract ($records.Count -eq [int]$contract.inventory.occurrences -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-TextSha256 $canonical) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Native explicit-NGE textual inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileProperties = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileProperties.Count) `
    "Native explicit-NGE source-file set drifted."
foreach ($property in $expectedFileProperties)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Native explicit-NGE count drifted: $($property.Name)"
}

$classificationMap = [ordered]@{
    explanatoryComments = "comment"
    retirementTelemetryStrings = "string"
    executableOrControlIdentifiers = "other"
}
$classifiedCount = 0
foreach ($entry in $classificationMap.GetEnumerator())
{
    $classified = @($records | Where-Object { $_.Kind -ceq $entry.Value } |
        Sort-Object Path, Line, Column)
    $categoryCanonical = (@($classified | ForEach-Object {
        "$($_.Path)|$($_.Line)|$($_.Column)|$($_.Kind)|$($_.Expression)"
    }) -join "`n") + "`n"
    $expected = $contract.classification.PSObject.Properties[$entry.Key].Value
    Assert-Contract ($classified.Count -eq [int]$expected.occurrences -and
        (Get-TextSha256 $categoryCanonical) -ceq [string]$expected.inventorySha256) `
        "Native explicit-NGE classification drifted: $($entry.Key)"
    $classifiedCount += $classified.Count
}
$telemetry = @($records | Where-Object { $_.Kind -ceq "string" })
Assert-Contract (@($telemetry | Where-Object {
        $_.Expression -notmatch '(?i)\b(ignored|rejected|retired)\b'
    }).Count -eq 0) `
    "A native NGE string is not bounded retirement telemetry."
Assert-Contract ($classifiedCount -eq $records.Count -and
    [int]$contract.classification.unclassifiedOccurrences -eq 0 -and
    [int]$contract.classification.executableOrControlIdentifiers.occurrences -eq 0 -and
    [bool]$contract.expected.allOccurrencesClassified -and
    [int]$contract.expected.nativeNgeGameplayAuthorityOccurrences -eq 0) `
    "Native explicit-NGE inventory is not fully closed."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required native explicit-NGE dependency is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    $dependencyStatus = [string]$dependency.status
    $dependencyEligible = $dependencyStatus -ceq "ready" -or
        ($Expectation -ceq "Build" -and
            $dependencyStatus -ceq "implemented-build-pending" -and
            @($dependency.requiredBeforeReady).Count -gt 0)
    Assert-Contract $dependencyEligible `
        "Required native explicit-NGE dependency is not eligible for $Expectation verification: $dependencyName"
}

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [bool]$contract.expected.precuSkillBoxXpHamAndCadenceAuthorityPreserved -and
    [bool]$contract.expected.laterZonesQuestsConversationsAndNpcCompatibilityPreserved) `
    "Native explicit-NGE closure claims an invalid preservation boundary."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        [int]$contract.runtimeEvidence.sourceWorkParityFiles -eq $sourceFiles.Count -and
        [int]$contract.runtimeEvidence.hostArtifactOrStagingDirectories -eq 0 -and
        $contract.requiredBeforeReady.Count -eq 0) `
        "Native explicit-NGE closure lacks complete Ready evidence."

    $container = [string]$contract.runtimeEvidence.container
    $health = (& docker inspect $container --format '{{.State.Health.Status}}').Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $health -ceq "healthy") `
        "Native explicit-NGE runtime container is not healthy."
    foreach ($relative in $sourceFiles)
    {
        & docker exec $container cmp -s "/swg-precu-source/src/$relative" "/swg-precu/src/$relative"
        Assert-Contract ($LASTEXITCODE -eq 0) `
            "Native explicit-NGE source/work parity failed: $relative"
    }

    $serverPid = (& docker exec $container pgrep -n SwgGameServer).Trim()
    $serverExe = (& docker exec $container readlink -f "/proc/$serverPid/exe").Trim()
    $binaryHash = ((& docker exec $container sha256sum $serverExe).Trim() -split ' ')[0]
    $binaryFile = (& docker exec $container file $serverExe).Trim()
    $binaryNotes = @(& docker exec $container readelf -n $serverExe)
    $buildLine = @($binaryNotes | Select-String 'Build ID:')
    $buildId = if ($buildLine.Count -eq 1)
    {
        ($buildLine[0].Line -replace '^.*Build ID:\s*', '').Trim()
    }
    else { "" }
    Assert-Contract ($binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $buildId -ceq [string]$contract.buildEvidence.serverBinaryBuildId -and
        $binaryFile -like "*ELF 64-bit LSB*x86-64*") `
        "Native explicit-NGE live binary identity drifted."

    $gameCount = [int]((& docker exec $container sh -c `
        "ps -eo comm= | grep -xc SwgGameServer").Trim())
    $planetCount = [int]((& docker exec $container sh -c `
        "ps -eo comm= | grep -xc PlanetServer").Trim())
    Assert-Contract ($gameCount -eq [int]$contract.runtimeEvidence.liveGameProcessCount -and
        $planetCount -eq [int]$contract.runtimeEvidence.livePlanetProcessCount) `
        "Native explicit-NGE live process topology drifted."
    $readyMarker = @(& docker logs $container 2>&1 | Select-String -SimpleMatch `
        "Cluster swg is ready for players.")
    Assert-Contract ($readyMarker.Count -ge 1) `
        "Native explicit-NGE runtime lacks the player-ready cluster marker."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) `
        "Native explicit-NGE source status is invalid."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Native explicit-NGE closure references prohibited host staging."
Write-Host "Complete Publish 14.1 native explicit-NGE textual inventory closure passed."
