[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$c = Get-Content (Join-Path $root ([string]$manifest.contracts.p14PikemanProfessionClosure)) -Raw | ConvertFrom-Json
$skill = Join-Path (Resolve-Path $SourceRoot).Path ([string]$c.sourceFiles.skillTable)
$lines = Get-Content $skill
$e = $c.publish14Evidence
$family = @($lines | Where-Object {
    $_.StartsWith([string]$e.family.prefix) -and
    -not $_.StartsWith([string]$e.excludedCompatibilityPrefix)
} | Sort-Object)
$text = ($family -join "`n") + "`n"
$sha = [Security.Cryptography.SHA256]::Create()
try { $hash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) | ForEach-Object { $_.ToString("x2") }) -join "") }
finally { $sha.Dispose() }
$compat = @($lines | Where-Object { $_.StartsWith([string]$e.excludedCompatibilityPrefix) })
if ($family.Count -ne [int]$e.family.rowCount -or $compat.Count -ne 7 -or $hash -cne [string]$e.family.normalizedSortedRowsSha256) {
    throw "Pikeman canonical-family check failed."
}
if ($Expectation -ceq "Ready") {
    $b = $c.buildEvidence
    $patch = Join-Path $root ([string]$b.overlayPatch -replace "^restoration/", "")
    if (
        [string]$c.status -cne "ready" -or
        (Get-Item $patch).Length -ne [int64]$b.overlayPatchBytes -or
        (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$b.overlayPatchSha256 -or
        (Get-FileHash $skill -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$b.sourceSha256."skills.tab" -or
        -not [bool]$c.runtimeEvidence.graphVisible -or
        -not [bool]$c.runtimeEvidence.serverHealthy -or
        [int]$c.runtimeEvidence.fatalOrExceptionCount -ne 0
    ) { throw "Pikeman ready evidence check failed." }
}
Write-Host "Publish 14.1 Pikeman profession closure passed."
