[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$builderPath = Join-Path `
    $PSScriptRoot `
    "Build-PrecuMercEntertainerElderClientTre.ps1"
if (-not (Test-Path -LiteralPath $builderPath -PathType Leaf)) {
    throw "Integrated client TRE builder is missing: '$builderPath'."
}

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $builderPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw (
        "Integrated client TRE builder has PowerShell parse errors: {0}" -f
        (($parseErrors | ForEach-Object { $_.Message }) -join "; ")
    )
}

$source = [IO.File]::ReadAllText($builderPath)
$expected = [string[]]@(
    "datatables/skill/skills.iff",
    "string/en/precu_elder.stf",
    "string/en/precu_hire_merc.stf",
    "string/en/precu_private_entertainer.stf"
)
[Array]::Sort($expected, [StringComparer]::Ordinal)

$manifestMatch = [Text.RegularExpressions.Regex]::Match(
    $source,
    '\$expectedArchivePaths\s*=\s*\[string\[\]\]@\((?<Body>.*?)\)\s*\r?\n\[Array\]::Sort',
    [Text.RegularExpressions.RegexOptions]::Singleline
)
if (-not $manifestMatch.Success) {
    throw "Could not find the canonical expectedArchivePaths declaration."
}

$actual = [System.Collections.Generic.List[string]]::new()
$pathMatches = [Text.RegularExpressions.Regex]::Matches(
    $manifestMatch.Groups["Body"].Value,
    '"(?<Path>[^"\r\n]+)"'
)
foreach ($pathMatch in $pathMatches) {
    $actual.Add($pathMatch.Groups["Path"].Value)
}
$actualArray = [string[]]$actual.ToArray()
[Array]::Sort($actualArray, [StringComparer]::Ordinal)

$manifestDifferences = @(
    Compare-Object `
        -ReferenceObject $expected `
        -DifferenceObject $actualArray `
        -CaseSensitive
)
if ($manifestDifferences.Count -gt 0 -or $actualArray.Count -ne $expected.Count) {
    throw "Integrated client TRE builder manifest is not the exact four-entry contract."
}

$requiredEvidence = [string[]]@(
    '[Parameter(Mandatory)]',
    '$compiledArchivePath = "datatables/skill/skills.iff"',
    '$compiledSourcePath = Join-Path',
    '$stfArchivePaths = [string[]]@(',
    '$sourcePath = Join-Path $serverDataRootPath',
    'foreach ($buildName in @($firstBuildName, $secondBuildName))',
    '$firstBuildHash = (Get-FileHash',
    '$secondBuildHash = (Get-FileHash',
    'if ($firstBuildHash -cne $secondBuildHash)',
    '-ArgumentList @("-l", $firstBuildName)',
    '-Description "Archive entry set"',
    '-ArgumentList @("-e", $firstBuildName, $extractionDirectoryName)',
    '-Description "Extracted archive file set"',
    '$stagedHash = (Get-FileHash',
    '$extractedHash = (Get-FileHash',
    'if ($stagedHash -cne $extractedHash)',
    '$pendingOutputPath = Join-Path $outputDirectory',
    '$pendingHash = (Get-FileHash',
    'Move-Item -LiteralPath $pendingOutputPath -Destination $outputFullPath -Force',
    'Remove-VerifiedTemporaryDirectory'
)
foreach ($needle in $requiredEvidence) {
    if (-not $source.Contains($needle)) {
        throw "Integrated client TRE builder is missing required evidence: $needle"
    }
}

foreach ($forbidden in @(
    "precu_container_droid.stf",
    "schematic_group.iff",
    "shared_character_datapad.iff",
    "object/draft_schematic/",
    "object/intangible/",
    "object/tangible/"
)) {
    if ($source.Contains($forbidden)) {
        throw "Integrated client TRE builder includes forbidden payload evidence: $forbidden"
    }
}

$parameterBlock = [Text.RegularExpressions.Regex]::Match(
    $source,
    '\[CmdletBinding\(\)\]\s*param\((?<Body>.*?)\)\s*\r?\n\s*Set-StrictMode',
    [Text.RegularExpressions.RegexOptions]::Singleline
)
if (-not $parameterBlock.Success) {
    throw "Could not find the builder's top-level parameter block."
}
$mandatoryCount = [Text.RegularExpressions.Regex]::Matches(
    $parameterBlock.Groups["Body"].Value,
    '\[Parameter\(Mandatory\)\]'
).Count
if ($mandatoryCount -ne 4) {
    throw "All four builder parameters must be mandatory; found $mandatoryCount declarations."
}

Write-Host (
    "PASS: integrated client TRE builder has an exact four-entry manifest, " +
    "strict source routing, deterministic double-build verification, exact " +
    "list/extract checks, byte comparison, and atomic publication."
)
