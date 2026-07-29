[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$sourcePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/pgc_quests.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_pgc_quest_xp_retirement_fixture.java"
$source = Get-Content -LiteralPath $sourcePath -Raw
$start = $source.IndexOf("public static void grantPgcNonChroniclesQuestXp")
$end = $source.IndexOf("public static void showPgcXpGrantedMessage", $start)
if ($start -lt 0 -or $end -le $start) { throw "Could not isolate PGC XP reward surface." }
$surface = $source.Substring($start, $end - $start)
foreach ($retired in @(
    "getSkillTemplate(",
    "getQuestExperienceReward(",
    "grantCraftingQuestXp(",
    "grantSocialStyleXp(",
    "grantCombatStyleXp(",
    "displayXpFlyText("
))
{
    if ($surface.Contains($retired)) { throw "PGC XP mutation remains: $retired" }
}
if (([regex]::Matches($surface, "return;")).Count -ne 2) { throw "Both PGC XP overloads are not fail-closed." }
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) { throw "PGC XP fixture is missing." }
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-pgc-quest-xp-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed") { throw "Runtime evidence is not ready." }
    foreach ($entry in @{"pgc_quests.java"=$sourcePath;"precu_pgc_quest_xp_retirement_fixture.java"=$fixturePath}.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/158-p14-pgc-quest-xp-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or $hash -ne $contract.buildEvidence.overlayPatchSha256) { throw "Patch evidence mismatch." }
}
Write-Host "Publish 14.1 PGC quest-XP retirement contract passed."
