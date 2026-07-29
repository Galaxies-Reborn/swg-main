[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$files = [ordered]@{
    "blueprint.java" = "blueprint"
    "blueprint_blank.java" = "blueprint_blank"
    "destructible_prop_token.java" = "destructible_prop_token"
    "effect_token.java" = "effect_token"
    "jukebox_converter_prop_token.java" = "jukebox_converter_prop_token"
    "npc_difficulty_token.java" = "npc_difficulty_token"
    "npc_token.java" = "npc_token"
    "prop_token.java" = "prop_token"
    "theater_token.java" = "theater_token"
}
$relativeRoot = "dsrc/sku.0/sys.server/compiled/game/script/systems/storyteller"
function Get-LifecycleMethod([string]$Body, [string]$Method)
{
    $pattern = "(?s)public int $Method\(obj_id self\).*?(?=\r?\n\s*public int|\z)"
    $match = [regex]::Match($Body, $pattern)
    if (-not $match.Success)
    {
        throw "Lifecycle method is missing: $Method"
    }
    return $match.Value
}
foreach ($entry in $files.GetEnumerator())
{
    $path = Join-Path $root "$relativeRoot/$($entry.Key)"
    $body = Get-Content -LiteralPath $path -Raw
    $detach = "detachScript(self, `"systems.storyteller.$($entry.Value)`")"
    if (([regex]::Matches($body, [regex]::Escape($detach))).Count -ne 2)
    {
        throw "$($entry.Key) must contain exactly two lifecycle detach calls."
    }
    foreach ($method in @("OnAttach", "OnInitialize"))
    {
        $section = Get-LifecycleMethod $body $method
        if (-not $section.Contains($detach) -or
            -not $section.Contains("return SCRIPT_CONTINUE;"))
        {
            throw "$($entry.Key) does not detach synchronously in $method."
        }
        foreach ($forbidden in @(
            "messageTo(",
            "storyteller.resetTokenDailyCount",
            "initializeBlueprint(",
            "attachScript("
        ))
        {
            if ($section.Contains($forbidden))
            {
                throw "$($entry.Key) retains lifecycle mutation in $method`: $forbidden"
            }
        }
    }
}
if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-storyteller-token-lifecycle-retirement.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or
        -not $contract.expected.deployedCleanupControllersRetained)
    {
        throw "Runtime evidence or the deployed-controller boundary is not ready."
    }
    foreach ($entry in $files.GetEnumerator())
    {
        $path = Join-Path $root "$relativeRoot/$($entry.Key)"
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
    $patchPath = Join-Path $restorationRoot "patches/dsrc/169-p14-storyteller-token-lifecycle-retirement.patch"
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
Write-Host "Publish 14.1 Storyteller token lifecycle retirement contract passed."
