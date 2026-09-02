[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$builderScript = Join-Path $PSScriptRoot "Build-RebornForceProgressionClientTre.ps1"
$stringGenerator = Join-Path $PSScriptRoot "New-RebornForceProgressionStringTable.ps1"
$serverDataRoot = Join-Path $repositoryRoot "serverdata"
$treeFileBuilder = Join-Path $repositoryRoot "tools/TreeFileBuilder.exe"
$checkedArtifact = Join-Path $restorationRoot "artifacts/reborn_force_progression_client.tre"
$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temporaryOutput = Join-Path $temporaryBase ("reborn-force-progression-client-test-{0}-{1}.tre" -f $PID, [Guid]::NewGuid().ToString("N"))

foreach ($path in @($builderScript, $stringGenerator, $treeFileBuilder, $checkedArtifact))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required client localization build input is missing: '$path'."
    }
}

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($builderScript, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0)
{
    throw "Client TRE builder has parse errors: $($parseErrors.Message -join '; ')."
}

$builderSource = [IO.File]::ReadAllText($builderScript)
foreach ($evidence in @(
    '$archivePath = "string/en/quest/force_sensitive/reborn_progression.stf"',
    'foreach ($buildName in @($firstName, $secondName))',
    'if ($firstHash -cne $secondHash)',
    '-ArgumentList @("-l", $firstName)',
    '-ArgumentList @("-e", $firstName, $extractedName)',
    'if ($sourceHash -cne $extractedHash)',
    'Move-Item -LiteralPath $pendingOutput -Destination $outputFullPath -Force',
    'Remove-VerifiedTemporaryDirectory'
))
{
    if (-not $builderSource.Contains($evidence))
    {
        throw "Client TRE builder is missing required evidence: $evidence"
    }
}

& $stringGenerator -Check | Out-Host
try
{
    $result = & $builderScript `
        -ServerDataRoot $serverDataRoot `
        -TreeFileBuilder $treeFileBuilder `
        -OutputPath $temporaryOutput
    if ($result.EntryCount -ne 1 -or
        [string]$result.Entry -cne "string/en/quest/force_sensitive/reborn_progression.stf")
    {
        throw "Disposable client TRE did not contain the exact one-entry manifest."
    }
    $temporaryHash = (Get-FileHash -LiteralPath $temporaryOutput -Algorithm SHA256).Hash
    $artifactHash = (Get-FileHash -LiteralPath $checkedArtifact -Algorithm SHA256).Hash
    if ($temporaryHash -cne [string]$result.SHA256 -or $temporaryHash -cne $artifactHash)
    {
        throw "Checked client TRE is stale: built=$temporaryHash artifact=$artifactHash result=$($result.SHA256)."
    }
    Write-Host "PASS: Reborn Force progression client TRE is deterministic, exact, extracted-byte verified, and current ($artifactHash)."
}
finally
{
    if (Test-Path -LiteralPath $temporaryOutput -PathType Leaf)
    {
        $resolvedOutput = (Resolve-Path -LiteralPath $temporaryOutput).ProviderPath
        $resolvedBase = (Resolve-Path -LiteralPath $temporaryBase).ProviderPath.TrimEnd('\', '/')
        $leaf = [IO.Path]::GetFileName($resolvedOutput)
        if ([IO.Path]::GetDirectoryName($resolvedOutput) -cne $resolvedBase -or
            -not $leaf.StartsWith("reborn-force-progression-client-test-", [StringComparison]::Ordinal) -or
            [IO.Path]::GetExtension($resolvedOutput) -cne ".tre")
        {
            throw "Refusing to remove unverified client TRE test output '$resolvedOutput'."
        }
        Remove-Item -LiteralPath $resolvedOutput -Force
    }
}
