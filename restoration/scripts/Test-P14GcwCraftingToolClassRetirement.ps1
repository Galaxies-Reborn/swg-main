[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-gcw-crafting-tool-class-retirement.json") -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$sourcePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/crafting/item/crafting_gcw_tools.java"
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf))
{
    throw "Required GCW crafting-tool source is missing: $sourcePath"
}
$source = Get-Content -LiteralPath $sourcePath -Raw
foreach ($retired in @(
    "getSkillTemplate(",
    "getProfessionName(",
    "profession.equals(`"trader`")",
    "Unable to get player's"
))
{
    if ($source.Contains($retired))
    {
        throw "NGE GCW crafting-tool class distinction remains active: $retired"
    }
}
foreach ($preserved in @(
    "int fatigue = 1;",
    'names[idx] = "charges";',
    'names[idx] = "power";',
    'names[idx] = "fatigue";'
))
{
    if (-not $source.Contains($preserved))
    {
        throw "Required GCW crafting-tool attribute was not preserved: $preserved"
    }
}

if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."crafting_gcw_tools.java")
    {
        throw "Canonical crafting_gcw_tools.java evidence mismatch."
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/150-p14-gcw-crafting-tool-class-retirement.patch"
    $patchText = [IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"
    $patchBytes = [Text.Encoding]::UTF8.GetBytes($patchText)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $patchHash = ([BitConverter]::ToString($sha.ComputeHash($patchBytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($patchBytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $patchHash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Canonical overlay evidence mismatch."
    }
}
Write-Host "Publish 14.1 GCW crafting-tool class-retirement contract passed."
