<#
.SYNOPSIS
Builds and verifies the Reborn Force progression client localization TRE.

.DESCRIPTION
Stages exactly quest/force_sensitive/reborn_progression.stf, builds the archive
twice, requires deterministic output, verifies the exact archive manifest,
extracts it, byte-compares it with the source, and publishes atomically.
#>
[CmdletBinding()]
param(
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

function Resolve-RequiredPath
{
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet("Leaf", "Container")][string]$PathType,
        [Parameter(Mandatory)][string]$Description
    )
    if (-not (Test-Path -LiteralPath $Path -PathType $PathType))
    {
        throw "$Description was not found at '$Path'."
    }
    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Invoke-TreeTool
{
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogStem
    )
    $stdoutPath = Join-Path $WorkingDirectory "$LogStem.stdout.log"
    $stderrPath = Join-Path $WorkingDirectory "$LogStem.stderr.log"
    $process = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WorkingDirectory $WorkingDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -Wait `
        -PassThru
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { [IO.File]::ReadAllText($stdoutPath) } else { "" }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { [IO.File]::ReadAllText($stderrPath) } else { "" }
    if ($process.ExitCode -ne 0)
    {
        throw "'$FilePath' failed with exit code $($process.ExitCode).`n$stdout`n$stderr"
    }
    return [pscustomobject]@{ StandardOutput = $stdout; StandardError = $stderr }
}

function Remove-VerifiedTemporaryDirectory
{
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$TemporaryBase
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath.TrimEnd('\', '/')
    $resolvedBase = (Resolve-Path -LiteralPath $TemporaryBase).ProviderPath.TrimEnd('\', '/')
    $prefix = $resolvedBase + [IO.Path]::DirectorySeparatorChar
    $leaf = [IO.Path]::GetFileName($resolvedPath)
    if (-not $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $leaf.StartsWith("reborn-force-progression-tre-", [StringComparison]::Ordinal))
    {
        throw "Refusing to remove unverified temporary directory '$resolvedPath'."
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

$archivePath = "string/en/quest/force_sensitive/reborn_progression.stf"
$serverDataRootPath = Resolve-RequiredPath -Path $ServerDataRoot -PathType Container -Description "Serverdata root"
$sourcePath = Resolve-RequiredPath `
    -Path (Join-Path $serverDataRootPath ($archivePath.Replace('/', '\'))) `
    -PathType Leaf `
    -Description "Reborn Force progression localization table"
if ((Get-Item -LiteralPath $sourcePath).Length -eq 0)
{
    throw "Localization table is empty: '$sourcePath'."
}

$builderPath = Resolve-RequiredPath -Path $TreeFileBuilder -PathType Leaf -Description "TreeFileBuilder"
$builderDirectory = Split-Path -Parent $builderPath
$builderExtension = [IO.Path]::GetExtension($builderPath)
$extractorName = if ([string]::IsNullOrEmpty($builderExtension)) { "TreeFileExtractor" } else { "TreeFileExtractor$builderExtension" }
$extractorPath = Resolve-RequiredPath `
    -Path (Join-Path $builderDirectory $extractorName) `
    -PathType Leaf `
    -Description "TreeFileExtractor"

$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($outputFullPath) -ine ".tre")
{
    throw "OutputPath must end in .tre: '$outputFullPath'."
}
$outputDirectory = Split-Path -Parent $outputFullPath
if ([string]::IsNullOrWhiteSpace($outputDirectory))
{
    throw "OutputPath must have a parent directory."
}

$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temporaryRoot = Join-Path $temporaryBase ("reborn-force-progression-tre-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString("N"))
$pendingOutput = $null
try
{
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $temporaryRoot = (Resolve-Path -LiteralPath $temporaryRoot).ProviderPath
    $stagedPath = Join-Path $temporaryRoot ($archivePath.Replace('/', '\'))
    New-Item -ItemType Directory -Path (Split-Path -Parent $stagedPath) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $stagedPath

    $responseFile = "__reborn_force_progression.rsp"
    $firstName = "__reborn_force_progression.first.tre"
    $secondName = "__reborn_force_progression.second.tre"
    [IO.File]::WriteAllText(
        (Join-Path $temporaryRoot $responseFile),
        "$archivePath @ $archivePath`n",
        [Text.UTF8Encoding]::new($false))

    foreach ($buildName in @($firstName, $secondName))
    {
        [void](Invoke-TreeTool `
            -FilePath $builderPath `
            -ArgumentList @("-r", $responseFile, $buildName) `
            -WorkingDirectory $temporaryRoot `
            -LogStem ([IO.Path]::GetFileNameWithoutExtension($buildName)))
        $buildPath = Join-Path $temporaryRoot $buildName
        if (-not (Test-Path -LiteralPath $buildPath -PathType Leaf) -or (Get-Item -LiteralPath $buildPath).Length -eq 0)
        {
            throw "TreeFileBuilder did not produce '$buildPath'."
        }
    }

    $firstPath = Join-Path $temporaryRoot $firstName
    $secondPath = Join-Path $temporaryRoot $secondName
    $firstHash = (Get-FileHash -LiteralPath $firstPath -Algorithm SHA256).Hash
    $secondHash = (Get-FileHash -LiteralPath $secondPath -Algorithm SHA256).Hash
    if ($firstHash -cne $secondHash)
    {
        throw "TRE output is not deterministic: $firstHash != $secondHash."
    }

    $listResult = Invoke-TreeTool `
        -FilePath $extractorPath `
        -ArgumentList @("-l", $firstName) `
        -WorkingDirectory $temporaryRoot `
        -LogStem "__reborn_force_progression.list"
    $listedLines = @($listResult.StandardOutput -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($listedLines.Count -ne 1 -or $listedLines[0] -notmatch "^(?<Path>[^`t]+)`t[0-9]+$" -or $Matches.Path.Replace('\', '/') -cne $archivePath)
    {
        throw "TRE manifest is not the exact one-entry localization contract: $($listedLines -join '; ')."
    }

    $extractedName = "__reborn_force_progression.extracted"
    [void](Invoke-TreeTool `
        -FilePath $extractorPath `
        -ArgumentList @("-e", $firstName, $extractedName) `
        -WorkingDirectory $temporaryRoot `
        -LogStem "__reborn_force_progression.extract")
    $extractedRoot = Join-Path $temporaryRoot $extractedName
    $extractedFiles = @(Get-ChildItem -LiteralPath $extractedRoot -Recurse -File)
    $extractedPath = Join-Path $extractedRoot ($archivePath.Replace('/', '\'))
    if ($extractedFiles.Count -ne 1 -or -not (Test-Path -LiteralPath $extractedPath -PathType Leaf))
    {
        throw "Extracted TRE is not the exact one-entry localization contract."
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    $extractedHash = (Get-FileHash -LiteralPath $extractedPath -Algorithm SHA256).Hash
    if ($sourceHash -cne $extractedHash)
    {
        throw "Extracted localization bytes differ from the source STF."
    }

    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container))
    {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $outputLeaf = Split-Path -Leaf $outputFullPath
    $pendingOutput = Join-Path $outputDirectory (".$outputLeaf.build-$PID-$([Guid]::NewGuid().ToString('N')).tmp")
    Copy-Item -LiteralPath $firstPath -Destination $pendingOutput
    if ((Get-FileHash -LiteralPath $pendingOutput -Algorithm SHA256).Hash -cne $firstHash)
    {
        throw "Pending TRE publication changed bytes."
    }
    Move-Item -LiteralPath $pendingOutput -Destination $outputFullPath -Force
    $pendingOutput = $null
    if ((Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash -cne $firstHash)
    {
        throw "Published TRE changed bytes."
    }

    [pscustomobject]@{
        Path = $outputFullPath
        SHA256 = $firstHash
        EntryCount = 1
        Entry = $archivePath
        SourceSHA256 = $sourceHash
    }
}
finally
{
    if ($pendingOutput -and (Test-Path -LiteralPath $pendingOutput -PathType Leaf))
    {
        Remove-Item -LiteralPath $pendingOutput -Force
    }
    if ($temporaryRoot)
    {
        Remove-VerifiedTemporaryDirectory -Path $temporaryRoot -TemporaryBase $temporaryBase
    }
}
