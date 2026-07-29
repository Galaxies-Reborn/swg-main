param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$files = [ordered]@{
    "lifeday_tree.java" = @{Path="dsrc/sku.0/sys.server/compiled/game/script/event/lifeday/lifeday_tree.java"; Script="event.lifeday.lifeday_tree"}
    "fountain.java" = @{Path="dsrc/sku.0/sys.server/compiled/game/script/event/ewok_festival/fountain.java"; Script="event.ewok_festival.fountain"}
}
foreach ($entry in $files.GetEnumerator())
{
    $body = Get-Content (Join-Path $root $entry.Value.Path) -Raw
    $detach = "detachScript(self, `"$($entry.Value.Script)`")"
    if (([regex]::Matches($body, [regex]::Escape($detach))).Count -ne 2) { throw "$($entry.Key) must detach twice." }
    foreach ($method in @("OnAttach", "OnInitialize"))
    {
        $lifecycle = [regex]::Match($body, "(?s)public int $method\(obj_id self\).*?(?=\r?\n\s*(?:public|private))").Value
        if (-not $lifecycle.Contains($detach) -or $lifecycle.Contains("messageTo(")) { throw "$($entry.Key) lifecycle remains active: $method" }
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-later-holiday-reward-anchor-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed") { throw "Runtime evidence is not ready." }
    foreach ($entry in $files.GetEnumerator())
    {
        $path = Join-Path $root $entry.Value.Path
        $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/174-p14-later-holiday-reward-anchor-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patch) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or $actual -ne $contract.buildEvidence.overlayPatchSha256) { throw "Patch evidence mismatch." }
}
Write-Host "Publish 14.1 later holiday reward-anchor retirement contract passed."
