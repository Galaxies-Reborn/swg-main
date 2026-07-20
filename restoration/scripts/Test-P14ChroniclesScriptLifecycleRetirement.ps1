[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$files = [ordered]@{
    "player_saga_quest.java" = "dsrc/sku.0/sys.server/compiled/game/script/player/player_saga_quest.java"
    "storyteller_commands.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/storyteller/storyteller_commands.java"
}
$saga = Get-Content -LiteralPath (Join-Path $root $files["player_saga_quest.java"]) -Raw
$storyteller = Get-Content -LiteralPath (Join-Path $root $files["storyteller_commands.java"]) -Raw
$basePlayer = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java") -Raw
$liveConversions = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/live_conversions.java") -Raw
if (([regex]::Matches(
    $saga,
    [regex]::Escape('detachScript(self, "player.player_saga_quest")'))).Count -ne 3)
{
    throw "Player saga script is not detached at all three lifecycle boundaries."
}
if (([regex]::Matches(
    $storyteller,
    [regex]::Escape('detachScript(self, "systems.storyteller.storyteller_commands")'))).Count -ne 2)
{
    throw "Storyteller commands are not detached at attach and initialize."
}
$newbieStart = $saga.IndexOf("public int OnNewbieTutorialResponse")
$newbieEnd = $saga.IndexOf("public int handleChroniclesTermsOfService", $newbieStart)
if ($newbieStart -lt 0 -or $newbieEnd -le $newbieStart)
{
    throw "Chronicles client-ready handler boundary is missing."
}
$newbie = $saga.Substring($newbieStart, $newbieEnd - $newbieStart)
foreach ($forbidden in @(
    "handleChroniclesTermsOfService",
    "handleChroniclesReserveReminder",
    "chroniclesTermsOfServiceShown"
))
{
    if ($newbie.Contains($forbidden))
    {
        throw "Chronicles client-ready mutation remains: $forbidden"
    }
}
if (-not $basePlayer.Contains('detachScript(self, "player.player_saga_quest")') -or
    -not $liveConversions.Contains('detachScript(self, "player.live_conversions")') -or
    -not $liveConversions.Contains('attachScript(player, "systems.storyteller.storyteller_commands")'))
{
    throw "Compatibility attachment/detachment inventory changed."
}
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$attachmentHits = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter "*.java" | ForEach-Object {
    $body = Get-Content -LiteralPath $_.FullName -Raw
    if ($body -match '(?m)^\s*attachScript\(player,\s*"systems\.storyteller\.storyteller_commands"\);')
    {
        $_.FullName.Substring($scriptRoot.Length + 1).Replace("\", "/")
    }
})
if (@($attachmentHits).Count -ne 1 -or
    $attachmentHits[0] -cne "player/live_conversions.java")
{
    throw "A new Chronicles/Storyteller attachment path exists."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-chronicles-script-lifecycle-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
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
    $patchPath = Join-Path $restorationRoot "patches/dsrc/167-p14-chronicles-script-lifecycle-retirement.patch"
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
Write-Host "Publish 14.1 Chronicles script lifecycle retirement contract passed."
