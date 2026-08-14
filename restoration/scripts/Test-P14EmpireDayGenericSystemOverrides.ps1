param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$files = [ordered]@{
    "guard_spawner.java" = "dsrc/sku.0/sys.server/compiled/game/script/city/guard_spawner.java"
    "gcw_spawner.java" = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/script_spawner/spawner_methods/gcw_spawner.java"
    "deliver_npc_spawner.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/dynamic/deliver_npc_spawner.java"
    "flip_banner.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/flip_banner.java"
    "flip_banner_onpole.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/flip_banner_onpole.java"
}
$bodies = @{}
foreach ($entry in $files.GetEnumerator())
{
    $bodies[$entry.Key] = Get-Content (Join-Path $root $entry.Value) -Raw
    if ($bodies[$entry.Key].Contains("empireday_ceremony"))
    {
        throw "$($entry.Key) still branches on Empire Day configuration."
    }
}
foreach ($required in @(
    "messageTo(self, `"checkForStart`"",
    "gcw.getImperialPlanetControlScore(self)",
    "gcw.getRebelPlanetControlScore(self)",
    "scoreDelta >= gcw.PRECU_GCW_DIFFICULTY_SCORE_DELTA"
))
{
    if (-not $bodies["guard_spawner.java"].Contains($required)) { throw "Normal city-guard behavior is missing: $required" }
}
foreach ($required in @(
    "gcw.getImperialPlanetControlScore(self)",
    "gcw.getRebelPlanetControlScore(self)",
    "gcw.PRECU_GCW_DIFFICULTY_SCORE_DELTA",
    'webster.put("faction", faction)',
    'webster.put("hard", hard)'
))
{
    if (-not $bodies["gcw_spawner.java"].Contains($required)) { throw "Normal GCW spawn selection is missing: $required" }
}
foreach ($required in @(
    'create.object("commoner", here)',
    'attachScript(npc, "systems.missions.dynamic.mission_deliver_npc")'
))
{
    if (-not $bodies["deliver_npc_spawner.java"].Contains($required)) { throw "Normal delivery NPC path is missing: $required" }
}
if (-not $bodies["flip_banner.java"].Contains('"object/tangible/gcw/flip_banner_" + faction') -or
    -not $bodies["flip_banner_onpole.java"].Contains('"object/tangible/gcw/flip_banner_onpole_" + faction'))
{
    throw "Normal faction banner creation is missing."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-empire-day-generic-system-overrides.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or -not $contract.expected.normalGenericSystemsRetained -or
        -not $contract.expected.precuBaseControlSelection -or [int]$contract.expected.precuBaseDifficultyScoreDelta -ne 64)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $files.GetEnumerator())
    {
        $actual = (Get-FileHash (Join-Path $root $entry.Value) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/180-p14-empire-day-generic-system-overrides.patch"
    $actual = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actual -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Empire Day generic-system override contract passed."
