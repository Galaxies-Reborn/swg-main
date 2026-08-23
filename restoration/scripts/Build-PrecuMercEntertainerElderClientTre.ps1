<#
.SYNOPSIS
Builds and verifies the canonical Pre-CU mercenary, private entertainer, and
Elder-skill client TRE.

.DESCRIPTION
Stages the exact four-file client payload from the compiled shared-data and
serverdata roots. The script builds the same staged snapshot twice, requires
byte-identical archives, verifies the archive manifest with TreeFileExtractor,
extracts every entry, and byte-compares the extracted files with their staged
sources. OutputPath is replaced only after all verification succeeds.

.PARAMETER CompiledSharedRoot
Root containing datatables/skill/skills.iff at its archive-relative path.

.PARAMETER ServerDataRoot
Root containing the three dedicated string/en/*.stf files at their
archive-relative paths.

.PARAMETER TreeFileBuilder
Path to TreeFileBuilder or TreeFileBuilder.exe. A matching TreeFileExtractor
must be present in the same directory.

.PARAMETER OutputPath
Destination .tre path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CompiledSharedRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerDataRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TreeFileBuilder,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RequiredFileSystemPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet("Leaf", "Container")][string]$PathType,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType $PathType)) {
        throw "$Description was not found at '$Path'."
    }

    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Invoke-TreeTool {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogStem
    )

    $standardOutputPath = Join-Path $WorkingDirectory "$LogStem.stdout.log"
    $standardErrorPath = Join-Path $WorkingDirectory "$LogStem.stderr.log"
    $process = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WorkingDirectory $WorkingDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $standardOutputPath `
        -RedirectStandardError $standardErrorPath `
        -Wait `
        -PassThru

    $standardOutput = if (Test-Path -LiteralPath $standardOutputPath -PathType Leaf) {
        [IO.File]::ReadAllText($standardOutputPath)
    }
    else {
        ""
    }
    $standardError = if (Test-Path -LiteralPath $standardErrorPath -PathType Leaf) {
        [IO.File]::ReadAllText($standardErrorPath)
    }
    else {
        ""
    }

    if ($process.ExitCode -ne 0) {
        $details = @($standardOutput.Trim(), $standardError.Trim()) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        throw (
            "'{0}' failed with exit code {1}.{2}{3}" -f
            $FilePath,
            $process.ExitCode,
            [Environment]::NewLine,
            ($details -join [Environment]::NewLine)
        )
    }

    return [pscustomobject]@{
        StandardOutput = $standardOutput
        StandardError = $standardError
    }
}

function Get-RelativeFilePaths {
    param([Parameter(Mandatory)][string]$Root)

    $rootWithSeparator = $Root.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar

    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -File |
            ForEach-Object {
                $_.FullName.Substring($rootWithSeparator.Length).Replace("\", "/")
            }
    )
}

function Assert-ExactPathSet {
    param(
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Actual,
        [Parameter(Mandatory)][string]$Description
    )

    $differences = @(
        Compare-Object `
            -ReferenceObject $Expected `
            -DifferenceObject $Actual `
            -CaseSensitive
    )
    if ($differences.Count -gt 0 -or $Expected.Count -ne $Actual.Count) {
        $differenceText = @(
            $differences | ForEach-Object { "  {0} {1}" -f $_.SideIndicator, $_.InputObject }
        )
        throw (
            "{0} did not match the canonical manifest ({1} expected, {2} actual).{3}{4}" -f
            $Description,
            $Expected.Count,
            $Actual.Count,
            [Environment]::NewLine,
            ($differenceText -join [Environment]::NewLine)
        )
    }
}

function Remove-VerifiedTemporaryDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$TemporaryBase
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $resolvedBase = (Resolve-Path -LiteralPath $TemporaryBase).ProviderPath.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $basePrefix = $resolvedBase + [IO.Path]::DirectorySeparatorChar
    $leafName = [IO.Path]::GetFileName($resolvedPath)

    if (-not $resolvedPath.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $leafName.StartsWith(
            "precu-merc-entertainer-elder-tre-",
            [StringComparison]::Ordinal)) {
        throw "Refusing to recursively remove unverified temporary path '$resolvedPath'."
    }

    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

$expectedArchivePaths = [string[]]@(
    "datatables/skill/skills.iff",
    "string/en/precu_elder.stf",
    "string/en/precu_hire_merc.stf",
    "string/en/precu_private_entertainer.stf"
)
[Array]::Sort($expectedArchivePaths, [StringComparer]::Ordinal)

$compiledSharedRootPath = Resolve-RequiredFileSystemPath `
    -Path $CompiledSharedRoot `
    -PathType Container `
    -Description "Compiled shared root"
$serverDataRootPath = Resolve-RequiredFileSystemPath `
    -Path $ServerDataRoot `
    -PathType Container `
    -Description "Serverdata root"
$treeFileBuilderPath = Resolve-RequiredFileSystemPath `
    -Path $TreeFileBuilder `
    -PathType Leaf `
    -Description "TreeFileBuilder"

$builderDirectory = Split-Path -Parent $treeFileBuilderPath
$builderExtension = [IO.Path]::GetExtension($treeFileBuilderPath)
$extractorNames = if ([string]::IsNullOrEmpty($builderExtension)) {
    @("TreeFileExtractor", "TreeFileExtractor.exe")
}
else {
    @("TreeFileExtractor$builderExtension")
}
$treeFileExtractorPath = $null
foreach ($extractorName in $extractorNames) {
    $candidate = Join-Path $builderDirectory $extractorName
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $treeFileExtractorPath = (Resolve-Path -LiteralPath $candidate).ProviderPath
        break
    }
}
if (-not $treeFileExtractorPath) {
    throw (
        "TreeFileExtractor was not found next to TreeFileBuilder. Checked: {0}" -f
        (($extractorNames | ForEach-Object { Join-Path $builderDirectory $_ }) -join ", ")
    )
}

$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($outputFullPath) -ine ".tre") {
    throw "OutputPath must end in .tre: '$outputFullPath'."
}
if (Test-Path -LiteralPath $outputFullPath -PathType Container) {
    throw "OutputPath identifies a directory: '$outputFullPath'."
}
$outputDirectory = Split-Path -Parent $outputFullPath
if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
    throw "OutputPath does not have a valid parent directory: '$outputFullPath'."
}

$sourceByArchivePath = @{}
$compiledArchivePath = "datatables/skill/skills.iff"
$compiledSourcePath = Join-Path `
    $compiledSharedRootPath `
    ($compiledArchivePath.Replace("/", "\"))
if (-not (Test-Path -LiteralPath $compiledSourcePath -PathType Leaf)) {
    throw "Canonical compiled TRE input is missing: '$compiledSourcePath'."
}
if ((Get-Item -LiteralPath $compiledSourcePath).Length -eq 0) {
    throw "Canonical compiled TRE input is empty: '$compiledSourcePath'."
}
$sourceByArchivePath[$compiledArchivePath] =
    (Resolve-Path -LiteralPath $compiledSourcePath).ProviderPath

$stfArchivePaths = [string[]]@(
    "string/en/precu_elder.stf",
    "string/en/precu_hire_merc.stf",
    "string/en/precu_private_entertainer.stf"
)
foreach ($archivePath in $stfArchivePaths) {
    $sourcePath = Join-Path $serverDataRootPath ($archivePath.Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Canonical serverdata TRE input is missing: '$sourcePath'."
    }
    if ((Get-Item -LiteralPath $sourcePath).Length -eq 0) {
        throw "Canonical serverdata TRE input is empty: '$sourcePath'."
    }
    $sourceByArchivePath[$archivePath] =
        (Resolve-Path -LiteralPath $sourcePath).ProviderPath
}

$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temporaryRoot = Join-Path $temporaryBase (
    "precu-merc-entertainer-elder-tre-{0}-{1}" -f
    $PID,
    [Guid]::NewGuid().ToString("N")
)
$pendingOutputPath = $null

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $temporaryRoot = (Resolve-Path -LiteralPath $temporaryRoot).ProviderPath

    foreach ($archivePath in $expectedArchivePaths) {
        $stagedPath = Join-Path $temporaryRoot ($archivePath.Replace("/", "\"))
        $stagedDirectory = Split-Path -Parent $stagedPath
        New-Item -ItemType Directory -Path $stagedDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourceByArchivePath[$archivePath] -Destination $stagedPath
    }

    $stagedPaths = [string[]](Get-RelativeFilePaths -Root $temporaryRoot)
    [Array]::Sort($stagedPaths, [StringComparer]::Ordinal)
    Assert-ExactPathSet `
        -Expected $expectedArchivePaths `
        -Actual $stagedPaths `
        -Description "Staged file set"

    $responseFileName = "__precu_merc_entertainer_elder.rsp"
    $firstBuildName = "__precu_merc_entertainer_elder.first.tre"
    $secondBuildName = "__precu_merc_entertainer_elder.second.tre"
    $responseLines = $expectedArchivePaths | ForEach-Object { "$_ @ $_" }
    $utf8WithoutBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText(
        (Join-Path $temporaryRoot $responseFileName),
        (($responseLines -join "`n") + "`n"),
        $utf8WithoutBom
    )

    foreach ($buildName in @($firstBuildName, $secondBuildName)) {
        $buildResult = Invoke-TreeTool `
            -FilePath $treeFileBuilderPath `
            -ArgumentList @("-r", $responseFileName, $buildName) `
            -WorkingDirectory $temporaryRoot `
            -LogStem ([IO.Path]::GetFileNameWithoutExtension($buildName))
        if (-not [string]::IsNullOrWhiteSpace($buildResult.StandardOutput)) {
            Write-Host $buildResult.StandardOutput.TrimEnd()
        }
        if (-not [string]::IsNullOrWhiteSpace($buildResult.StandardError)) {
            Write-Warning $buildResult.StandardError.TrimEnd()
        }

        $buildPath = Join-Path $temporaryRoot $buildName
        if (-not (Test-Path -LiteralPath $buildPath -PathType Leaf) -or
            (Get-Item -LiteralPath $buildPath).Length -eq 0) {
            throw "TreeFileBuilder did not create a non-empty archive: '$buildPath'."
        }
    }

    $firstBuildPath = Join-Path $temporaryRoot $firstBuildName
    $secondBuildPath = Join-Path $temporaryRoot $secondBuildName
    $firstBuildHash = (Get-FileHash -LiteralPath $firstBuildPath -Algorithm SHA256).Hash
    $secondBuildHash = (Get-FileHash -LiteralPath $secondBuildPath -Algorithm SHA256).Hash
    if ($firstBuildHash -cne $secondBuildHash) {
        throw (
            "TreeFileBuilder output was not deterministic for the staged snapshot: {0} != {1}." -f
            $firstBuildHash,
            $secondBuildHash
        )
    }

    $listResult = Invoke-TreeTool `
        -FilePath $treeFileExtractorPath `
        -ArgumentList @("-l", $firstBuildName) `
        -WorkingDirectory $temporaryRoot `
        -LogStem "__precu_merc_entertainer_elder.list"
    if (-not [string]::IsNullOrWhiteSpace($listResult.StandardError)) {
        Write-Warning $listResult.StandardError.TrimEnd()
    }

    $listedPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $listResult.StandardOutput -split "`r?`n") {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -notmatch "^(?<Path>[^`t]+)`t[0-9]+$") {
            throw "TreeFileExtractor returned an unexpected list line: '$line'."
        }
        $listedPaths.Add($Matches.Path.Replace("\", "/"))
    }
    $listedPathArray = [string[]]$listedPaths.ToArray()
    [Array]::Sort($listedPathArray, [StringComparer]::Ordinal)
    Assert-ExactPathSet `
        -Expected $expectedArchivePaths `
        -Actual $listedPathArray `
        -Description "Archive entry set"

    $extractionDirectoryName = "__precu_merc_entertainer_elder.extracted"
    $extractResult = Invoke-TreeTool `
        -FilePath $treeFileExtractorPath `
        -ArgumentList @("-e", $firstBuildName, $extractionDirectoryName) `
        -WorkingDirectory $temporaryRoot `
        -LogStem "__precu_merc_entertainer_elder.extract"
    if (-not [string]::IsNullOrWhiteSpace($extractResult.StandardError)) {
        Write-Warning $extractResult.StandardError.TrimEnd()
    }

    $extractionRoot = Join-Path $temporaryRoot $extractionDirectoryName
    $extractedPaths = [string[]](Get-RelativeFilePaths -Root $extractionRoot)
    [Array]::Sort($extractedPaths, [StringComparer]::Ordinal)
    Assert-ExactPathSet `
        -Expected $expectedArchivePaths `
        -Actual $extractedPaths `
        -Description "Extracted archive file set"

    foreach ($archivePath in $expectedArchivePaths) {
        $nativeRelativePath = $archivePath.Replace("/", "\")
        $stagedHash = (Get-FileHash `
            -LiteralPath (Join-Path $temporaryRoot $nativeRelativePath) `
            -Algorithm SHA256).Hash
        $extractedHash = (Get-FileHash `
            -LiteralPath (Join-Path $extractionRoot $nativeRelativePath) `
            -Algorithm SHA256).Hash
        if ($stagedHash -cne $extractedHash) {
            throw "Extracted archive bytes do not match the staged input for '$archivePath'."
        }
    }

    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $outputLeaf = Split-Path -Leaf $outputFullPath
    $pendingOutputPath = Join-Path $outputDirectory (
        ".{0}.build-{1}-{2}.tmp" -f
        $outputLeaf,
        $PID,
        [Guid]::NewGuid().ToString("N")
    )
    Copy-Item -LiteralPath $firstBuildPath -Destination $pendingOutputPath
    $pendingHash = (Get-FileHash -LiteralPath $pendingOutputPath -Algorithm SHA256).Hash
    if ($pendingHash -cne $firstBuildHash) {
        throw "Pending archive hash changed while copying to '$pendingOutputPath'."
    }
    Move-Item -LiteralPath $pendingOutputPath -Destination $outputFullPath -Force
    $pendingOutputPath = $null

    $finalHash = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash
    if ($finalHash -cne $firstBuildHash) {
        throw "Published archive hash changed while moving to '$outputFullPath'."
    }

    Write-Host "Verified archive contents ($($expectedArchivePaths.Count) entries):"
    foreach ($archivePath in $expectedArchivePaths) {
        Write-Host "  $archivePath"
    }

    [pscustomobject]@{
        Path = $outputFullPath
        SHA256 = $finalHash
        EntryCount = $expectedArchivePaths.Count
        Entries = $expectedArchivePaths
        TreeFileBuilder = $treeFileBuilderPath
        TreeFileExtractor = $treeFileExtractorPath
        CompiledSource = $sourceByArchivePath[$compiledArchivePath]
        ServerDataSources = @(
            $stfArchivePaths | ForEach-Object { $sourceByArchivePath[$_] }
        )
    }
}
finally {
    if ($pendingOutputPath -and (Test-Path -LiteralPath $pendingOutputPath -PathType Leaf)) {
        Remove-Item -LiteralPath $pendingOutputPath -Force -ErrorAction SilentlyContinue
    }
    if ($temporaryRoot) {
        Remove-VerifiedTemporaryDirectory `
            -Path $temporaryRoot `
            -TemporaryBase $temporaryBase
    }
}
