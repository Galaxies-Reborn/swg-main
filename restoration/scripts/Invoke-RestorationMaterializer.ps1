[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$StagingRoot,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$superprojectRoot = Split-Path -Parent $restorationRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force

$manifest = Get-RestorationManifest -RestorationRoot $restorationRoot
$source = Resolve-NormalizedPath -Path $SourceRoot
$stage = Resolve-NormalizedPath -Path $StagingRoot

$canonicalPinArgs = @{
    RepositoryRoot = $superprojectRoot
    Manifest = $manifest
}
$sourcePinArgs = @{
    RepositoryRoot = $source
    Manifest = $manifest
    RequireInitialized = $true
}
Assert-RestorationPins @canonicalPinArgs | Out-Null
Assert-RestorationPins @sourcePinArgs | Out-Null

if (Test-PathWithin -Candidate $stage -Parent $superprojectRoot)
{
    throw "StagingRoot must be outside the canonical superproject: $superprojectRoot"
}
if (Test-PathWithin -Candidate $stage -Parent $source)
{
    throw "StagingRoot must be outside the initialized source checkout: $source"
}
if (Test-Path -LiteralPath $stage)
{
    if (-not (Test-Path -LiteralPath $stage -PathType Container))
    {
        throw "StagingRoot exists and is not a directory: $stage"
    }
    if (Get-ChildItem -LiteralPath $stage -Force | Select-Object -First 1)
    {
        throw "StagingRoot must not exist or must be empty: $stage"
    }
}

$patches = @()
foreach ($overlay in @($manifest.overlays))
{
    $overlayRoot = Join-Path $restorationRoot ([string]$overlay.directory)
    if (-not (Test-Path -LiteralPath $overlayRoot -PathType Container))
    {
        throw "Overlay directory is missing: $overlayRoot"
    }

    foreach ($patch in @(Get-ChildItem -LiteralPath $overlayRoot -File -Filter "*.patch" | Sort-Object Name))
    {
        $patches += [pscustomobject]@{
            Component = [string]$overlay.component
            File = $patch
        }
    }
}

$headShotGatePath = Join-Path $restorationRoot ([string]$manifest.contracts.headShot1Gate)
$headShotGate = Get-Content -LiteralPath $headShotGatePath -Raw | ConvertFrom-Json
if ([string]$headShotGate.status -ne "ready")
{
    $blockedText = [string]$headShotGate.materializerPolicy.rejectPatchTextWhileBlocked
    foreach ($patchRecord in $patches)
    {
        $patchText = Get-Content -LiteralPath $patchRecord.File.FullName -Raw
        if ($patchText.IndexOf($blockedText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
        {
            throw "Blocked feature '$($headShotGate.feature)' appears in $($patchRecord.File.FullName). Satisfy and update its gate contract first."
        }
    }
}

Write-Host "Restoration materialization plan"
Write-Host "  source:  $source"
Write-Host "  staging: $stage"
foreach ($pin in @($manifest.gitlinks))
{
    Write-Host "  clone:   $($pin.name) at $($pin.commit)"
}
Write-Host "  patches: $($patches.Count)"

if (-not $Apply)
{
    Write-Host "Plan only. No files were written; pass -Apply to create the isolated stage."
    exit 0
}

if ($patches.Count -eq 0)
{
    throw "No overlay patches are registered. Refusing to create an unmodified stage."
}

if (-not (Test-Path -LiteralPath $stage))
{
    New-Item -ItemType Directory -Path $stage | Out-Null
}

foreach ($pin in @($manifest.gitlinks))
{
    $componentSource = Join-Path $source ([string]$pin.path)
    $componentStage = Join-Path $stage ([string]$pin.name)
    Invoke-GitChecked -Repository $stage -Arguments @(
        "clone",
        "--shared",
        "--no-checkout",
        $componentSource,
        $componentStage
    ) | Out-Null
    Invoke-GitChecked -Repository $componentStage -Arguments @(
        "checkout",
        "--detach",
        [string]$pin.commit
    ) | Out-Null
}

foreach ($patchRecord in $patches)
{
    $componentStage = Join-Path $stage ([string]$patchRecord.Component)
    Invoke-GitChecked -Repository $componentStage -Arguments @(
        "apply",
        "--check",
        $patchRecord.File.FullName
    ) | Out-Null
    Invoke-GitChecked -Repository $componentStage -Arguments @(
        "apply",
        $patchRecord.File.FullName
    ) | Out-Null
}

Write-Host "Materialized isolated restoration stage: $stage"
