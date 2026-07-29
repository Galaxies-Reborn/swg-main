param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$relative = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/empire_day_interior_npc_spawner.java"
$source = Join-Path $root $relative
$body = Get-Content $source -Raw
$cleanup = [regex]::Match($body, '(?s)public void cleanupTrackedEmpireDaySpawns\(.*?(?=\r?\n\s*public int)').Value
foreach ($required in @(
    'dataTableGetNumRows(datatable)',
    '"empire_day_spawned" + i',
    'destroyObject(spawnedCreature)',
    'removeObjVar(self, trackingObjVar)',
    'removeObjVar(self, "set_room")',
    'utils.removeScriptVar(self, "spawnCounter")'
))
{
    if (-not $cleanup.Contains($required)) { throw "Interior cleanup is missing: $required" }
}
foreach ($lifecycle in @("OnAttach", "OnInitialize"))
{
    $method = [regex]::Match($body, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    $cleanupIndex = $method.IndexOf("cleanupTrackedEmpireDaySpawns(self)")
    $detachIndex = $method.IndexOf('detachScript(self, "theme_park.dungeon.empire_day_interior_npc_spawner")')
    if ($cleanupIndex -lt 0 -or $detachIndex -lt 0 -or $cleanupIndex -gt $detachIndex -or
        $method.Contains('messageTo(self, "beginEmpireDaySpawning"'))
    {
        throw "$lifecycle does not clean up and detach before scheduling."
    }
}
$datatableRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/datatables/spawning/building_spawns"
$tables = @(Get-ChildItem $datatableRoot -Filter "empire_day_*.tab" -File)
$rowCount = 0
foreach ($table in $tables)
{
    $rows = @(Get-Content $table.FullName)
    $rowCount += $rows.Count - 2
}
if ($tables.Count -ne 12 -or $rowCount -ne 317)
{
    throw "Empire Day interior table inventory drifted: tables=$($tables.Count), rows=$rowCount."
}
$buildoutRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/datatables/buildout"
$attachmentCount = 0
Get-ChildItem $buildoutRoot -Recurse -Filter *.tab -File | ForEach-Object {
    $attachmentCount += @((Get-Content $_.FullName) | Where-Object {
        $_.Contains("theme_park.dungeon.empire_day_interior_npc_spawner")
    }).Count
}
if ($attachmentCount -ne 8) { throw "Interior spawner attachment inventory drifted: $attachmentCount." }
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-empire-day-interior-spawner-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or -not $contract.expected.hostBuildingsRetained)
    {
        throw "Runtime evidence is not ready."
    }
    $actual = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."empire_day_interior_npc_spawner.java")
    {
        throw "Source evidence mismatch."
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/177-p14-empire-day-interior-spawner-retirement.patch"
    $actual = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actual -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Empire Day interior-spawner retirement contract passed."
