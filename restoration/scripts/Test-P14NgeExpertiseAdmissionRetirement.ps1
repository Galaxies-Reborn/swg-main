[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path (Resolve-Path -LiteralPath $SourceRoot).Path "dsrc/sku.0/sys.server/compiled/game/script/library/expertise.java"
$source = Get-Content -LiteralPath $sourcePath -Raw
foreach ($retired in @("getSkillTemplate(", 'grantSkill(player, "expertise")', "DATATABLE_EXPERTISE", 'profession.equals("trader")'))
{
    if ($source.Contains($retired)) { throw "NGE expertise admission remains: $retired" }
}
$autoStart = $source.IndexOf("public static void autoAllocateExpertiseByLevel")
$introStart = $source.IndexOf("public static void displayIntroductionToExpertise", $autoStart)
$admitStart = $source.IndexOf("public static boolean isProfAllowedSkill")
if ($autoStart -lt 0 -or $introStart -lt 0 -or $admitStart -lt 0) { throw "Expertise boundary methods are missing." }
$auto = $source.Substring($autoStart, $introStart - $autoStart)
$admit = $source.Substring($admitStart)
if (-not $auto.Contains("return;") -or -not $admit.Contains("return false;")) { throw "Expertise boundary does not fail closed." }
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-nge-expertise-admission-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed") { throw "Runtime evidence is not ready." }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."expertise.java") { throw "Source evidence mismatch." }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/157-p14-nge-expertise-admission-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or $hash -ne $contract.buildEvidence.overlayPatchSha256) { throw "Patch evidence mismatch." }
}
Write-Host "Publish 14.1 NGE expertise admission retirement contract passed."
