[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $root ([string]$manifest.contracts.p14StandardProfessionMatrixClosure)) -Raw | ConvertFrom-Json
$skillPath = Join-Path (Resolve-Path -LiteralPath $SourceRoot).Path ([string]$contract.sourceFiles.skillTable)
$lines = Get-Content -LiteralPath $skillPath

foreach ($family in @($contract.families)) {
    $rows = @($lines | Where-Object {
        $name = ($_ -split "`t", 2)[0]
        $name -ceq [string]$family.root -or
            ($name.StartsWith([string]$family.root + "_") -and
                -not $name.StartsWith([string]$family.root + "_prereq"))
    } | Sort-Object)
    $text = ($rows -join "`n") + "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) |
            ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally { $sha.Dispose() }
    if ($rows.Count -ne 19 -or
        [Text.Encoding]::UTF8.GetByteCount($text) -ne [int]$family.bytes -or
        $hash -cne [string]$family.sha256) {
        throw "Standard family failed: $($family.root)"
    }
}

$header = $lines[0].Split("`t")
$skills = @($lines[2..($lines.Count - 1)] | ConvertFrom-Csv -Delimiter "`t" -Header $header)
$artisan = @($skills | Where-Object NAME -CEQ "crafting_artisan_novice")
$override = $contract.galaxiesRebornOverride
$commands = @()
if ($artisan.Count -eq 1) {
    $commands = @(([string]$artisan[0].COMMANDS).Split(","))
}
if ($artisan.Count -ne 1 -or
    [int]$artisan[0].MONEY_REQUIRED -ne [int]$override.noviceQualification.moneyRequired -or
    [int]$artisan[0].POINTS_REQUIRED -ne [int]$override.noviceQualification.pointsRequired -or
    [string]$artisan[0].SKILLS_REQUIRED -cne [string]$override.noviceQualification.skillsRequired -or
    [string]$artisan[0].XP_TYPE -cne [string]$override.noviceQualification.xpType -or
    [int]$artisan[0].XP_COST -ne [int]$override.noviceQualification.xpCost -or
    [int]$artisan[0].XP_CAP -ne [int]$override.noviceQualification.xpCap -or
    ($commands -join ",") -cne (@($override.noviceCommands) -join ",")) {
    throw "Galaxies Reborn Artisan novice override failed."
}
$artisanFamily = @($contract.families | Where-Object { [string]$_.root -ceq "crafting_artisan" })
if ($artisanFamily.Count -ne 1 -or
    [string]$override.ownerContract -cne "contracts/p14-precu-base-novice-learning.json" -or
    [string]$override.directSourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
    (Get-FileHash -LiteralPath $skillPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$override.sourceSha256 -or
    [int]$override.currentArtisanFamily.normalizedSortedRowsBytes -ne [int]$artisanFamily[0].bytes -or
    [string]$override.currentArtisanFamily.normalizedSortedRowsSha256 -cne [string]$artisanFamily[0].sha256 -or
    [int]$override.historicalPublish14ArtisanFamily.normalizedSortedRowsBytes -ne 4730 -or
    [string]$override.historicalPublish14ArtisanFamily.normalizedSortedRowsSha256 -cne "544196581dde753456f50a24c8bc91a97345d94e55cdf4ccc2e0a8201976d8d2") {
    throw "Galaxies Reborn Artisan family owner or historical Publish 14 baseline failed."
}

if ($Expectation -ceq "Ready") {
    $build = $contract.buildEvidence
    $patch = Join-Path $root ([string]$build.overlayPatch -replace "^restoration/", "")
    if ((Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$build.overlayPatchSha256 -or
        [string]$build.sourceSha256."skills.tab" -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$build.sourceSha256."skills.tab" -ceq [string]$override.sourceSha256 -or
        [string]$contract.runtimeEvidence.result -cne "passed" -or
        [int]$contract.runtimeEvidence.graphVisibleCount -ne 15) {
        throw "Standard matrix historical ready evidence failed."
    }
}
Write-Host "Publish 14.1 historical standard profession matrix plus Galaxies Reborn Artisan override passed."
