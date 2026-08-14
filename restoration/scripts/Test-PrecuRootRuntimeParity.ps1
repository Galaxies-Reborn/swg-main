[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$canonicalRoot = Split-Path -Parent $restorationRoot
$materializedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$runtimeFiles = @(
    ".gitattributes",
    ".gitignore",
    "README.md",
    "build.xml",
    "docker-compose.precu.yml",
    "docker/README.md",
    "docker/entrypoint.sh",
    "exec.sh"
)

function Read-NormalizedText
{
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw).Replace("`r`n", "`n")
}

foreach ($relativePath in $runtimeFiles)
{
    $canonicalPath = Join-Path $canonicalRoot ($relativePath -replace "/", "\")
    $materializedPath = Join-Path $materializedRoot ($relativePath -replace "/", "\")
    if (-not (Test-Path -LiteralPath $canonicalPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $materializedPath -PathType Leaf))
    {
        Write-Host "  [FAIL] $relativePath (missing)"
        $failures.Add($relativePath)
        continue
    }

    $matches = (Read-NormalizedText -Path $canonicalPath) -ceq
        (Read-NormalizedText -Path $materializedPath)
    if ($matches)
    {
        Write-Host "  [PASS] $relativePath"
    }
    else
    {
        Write-Host "  [FAIL] $relativePath (content drift)"
        $failures.Add($relativePath)
    }
}

if ($failures.Count -gt 0)
{
    throw "Materialized root runtime drifted: $($failures -join ', ')"
}

Write-Host "Pre-CU root runtime parity passed."
