[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$gcwPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/gcw.java"
$instancePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/player_instance.java"
$gcw = Get-Content -LiteralPath $gcwPath -Raw
$instance = Get-Content -LiteralPath $instancePath -Raw
$gcwStart = $gcw.IndexOf("public static void gcwSetCredits")
$gcwEnd = $gcw.IndexOf("public static void gcwInvasionCreditForGCW", $gcwStart)
$instanceStart = $instance.IndexOf("public int movePlayerToInstance")
$instanceEnd = $instance.IndexOf("public int cmdShowInstanceInformation", $instanceStart)
if ($gcwStart -lt 0 -or $gcwEnd -le $gcwStart -or $instanceStart -lt 0 -or $instanceEnd -le $instanceStart) { throw "Could not isolate presentation surfaces." }
$surface = $gcw.Substring($gcwStart, $gcwEnd - $gcwStart) + "`n" + $instance.Substring($instanceStart, $instanceEnd - $instanceStart)
foreach ($retired in @("getSkillTemplate(", "getProfessionName(", "@ui_roadmap:", "Players Is:"))
{
    if ($surface.Contains($retired)) { throw "NGE presentation remains: $retired" }
}
foreach ($required in @(
    'String playerProfession = "Publish 14.1 skills";',
    "int playerLevel = 0;",
    "Progression: Publish 14.1 skills, Faction:",
    "gcw_score.setPlayerGcwData(",
    "instance.sendToEnterOne(",
    "instance.sendToEnterTwo("
))
{
    if (-not $surface.Contains($required)) { throw "Required neutral presentation or behavior is missing: $required" }
}
foreach ($counter in @("playerGCW","playerPvpKills","playerKills","playerAssists","playerCraftedItems","playerDestroyedItems"))
{
    if (-not $surface.Contains("$counter = currentData.$counter + $counter;")) { throw "GCW counter accumulation is missing: $counter" }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-neutral-progression-presentation.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed") { throw "Runtime evidence is not ready." }
    foreach ($entry in @{"gcw.java"=$gcwPath;"player_instance.java"=$instancePath}.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/159-p14-neutral-progression-presentation.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or $hash -ne $contract.buildEvidence.overlayPatchSha256) { throw "Patch evidence mismatch." }
}
Write-Host "Publish 14.1 neutral progression-presentation contract passed."
