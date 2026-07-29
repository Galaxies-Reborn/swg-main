[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$files = [ordered]@{
    "base_player.java" = "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
    "st_object_movement.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/storyteller/st_object_movement.java"
}
$base = Get-Content -LiteralPath (Join-Path $root $files["base_player.java"]) -Raw
$movement = Get-Content -LiteralPath (Join-Path $root $files["st_object_movement.java"]) -Raw
function Get-Method([string]$Body, [string]$Name)
{
    $pattern = "(?s)public (?:int|void) $Name\(.*?(?=\r?\n\s*public (?:int|void|boolean)|\z)"
    $match = [regex]::Match($Body, $pattern)
    if (-not $match.Success)
    {
        throw "Method is missing: $Name"
    }
    return $match.Value
}
$zoningArray = [regex]::Match(
    $base,
    "(?s)public static final String\[\] ZONING_RIGHTS_ARRAY.*?\};").Value
if (-not $zoningArray.Contains("@city/city:full_zoning_rights") -or
    $zoningArray.Contains("@city/city:st_zoning_rights"))
{
    throw "City zoning choices do not preserve only ordinary zoning."
}
$selection = Get-Method $base "handleZoningRightsSelect"
if ($selection.Contains("handleStorytellerZoningRights") -or
    -not $selection.Contains("handleCmdGrantZoningRights"))
{
    throw "City zoning selection still exposes Storyteller rights or lost ordinary rights."
}
$directZoning = Get-Method $base "cmdGrantStorytellerZoningRights"
foreach ($forbidden in @(
    "handleStorytellerZoningRights",
    "setObjVar(",
    "removeObjVar(",
    "sendSystemMessage"
))
{
    if ($directZoning.Contains($forbidden))
    {
        throw "Direct Storyteller zoning retains mutation: $forbidden"
    }
}
$handlers = @(
    "rotateStorytellerObject",
    "moveStorytellerObject",
    "storytellerItemRotateRight",
    "storytellerItemRotateLeft",
    "storytellerItemMoveForward",
    "storytellerItemMoveBack",
    "storytellerItemMoveUp",
    "storytellerItemMoveDown"
)
foreach ($handler in $handlers)
{
    $method = Get-Method $movement $handler
    if (-not $method.Contains("return SCRIPT_CONTINUE;"))
    {
        throw "Command-link handler is not retained: $handler"
    }
}
foreach ($forbidden in @(
    "setYaw(",
    "setLocation(",
    "queueCommand(",
    "canDeployStorytellerToken",
    "storytellerCreationLoc",
    "isStorytellerMoveCommandValidation",
    "dataTableGet"
))
{
    if ($movement.Contains($forbidden))
    {
        throw "Storyteller movement mutation remains: $forbidden"
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (
        Join-Path $restorationRoot "contracts/p14-storyteller-command-surface-retirement.json"
    ) -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or
        -not $contract.expected.ordinaryCityZoningRetained -or
        -not $contract.expected.csrCleanupCommandsRetained)
    {
        throw "Runtime evidence or retained compatibility boundaries are not ready."
    }
    foreach ($entry in $files.GetEnumerator())
    {
        $path = Join-Path $root $entry.Value
        $bytes = [Text.Encoding]::UTF8.GetBytes(
            ([IO.File]::ReadAllText($path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try
        {
            $actual = ([BitConverter]::ToString(
                $sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
        }
        finally
        {
            $sha.Dispose()
        }
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/170-p14-storyteller-command-surface-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(
        ([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = ([BitConverter]::ToString(
            $sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha.Dispose()
    }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $hash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Storyteller command-surface retirement contract passed."
