param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$files = [ordered]@{
    "spawning.java" = "library/spawning.java"
    "spawner_area.java" = "systems/spawning/spawner_area.java"
    "spawner_random.java" = "systems/spawning/spawner_random.java"
    "spawner_patrol.java" = "systems/spawning/spawner_patrol.java"
}
$library = Get-Content (Join-Path $scriptRoot $files["spawning.java"]) -Raw
$families = @(
    "at_st_empire_day_",
    "imp_empireday_",
    "reb_empireday_",
    "imperial_emperorsday_",
    "rebel_emperorsday_",
    "imperial_detainment_",
    "imperial_marine_detainment_",
    "rebel_detainment_"
)
if (-not $library.Contains("isRetiredEmpireDaySpawner") -or
    -not $library.Contains('getStringObjVar(spawner, "eventRequired").equals("empireday_ceremony")'))
{
    throw "Shared Empire Day retirement predicate is incomplete."
}
foreach ($family in $families)
{
    if (-not $library.Contains("spawn.startsWith(`"$family`")")) { throw "Missing retired spawn family: $family" }
}
$handlers = [ordered]@{
    "spawner_area.java" = @("OnAttach", "OnInitialize", "doSpawnEvent", "spawnDestroyed")
    "spawner_random.java" = @("OnAttach", "OnInitialize", "OnHearSpeech", "doSpawnEvent", "spawnDestroyed")
    "spawner_patrol.java" = @("OnAttach", "OnInitialize", "startTheaterFromBuildout", "doInitialSpawn", "doSpawnEvent", "spawnDestroyed")
}
foreach ($entry in $handlers.GetEnumerator())
{
    $body = Get-Content (Join-Path $scriptRoot $files[$entry.Key]) -Raw
    foreach ($handler in $entry.Value)
    {
        $method = [regex]::Match($body, "(?s)public (?:int|void) $handler\(.*?(?=\r?\n\s*public (?:int|void|boolean|float)|\r?\n})").Value
        if (-not $method.Contains("spawning.isRetiredEmpireDaySpawner(self)"))
        {
            throw "$($entry.Key) handler is not guarded: $handler"
        }
    }
    foreach ($lifecycle in @("OnAttach", "OnInitialize"))
    {
        $method = [regex]::Match($body, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
        $cleanup = $method.IndexOf("OnDestroy(self);")
        $detach = $method.IndexOf("detachScript(self, `"systems.spawning.$($entry.Key.Replace('.java', ''))`")")
        if ($cleanup -lt 0 -or $detach -lt 0 -or $cleanup -gt $detach)
        {
            throw "$($entry.Key) $lifecycle does not clean up before detaching."
        }
    }
}
$buildoutRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/datatables/buildout"
$counts = @{spawner_area=0; spawner_patrol=0; spawner_random=0}
$eventFiles = @{}
Get-ChildItem $buildoutRoot -Recurse -Filter *.tab -File | ForEach-Object {
    $relative = $_.FullName.Substring($buildoutRoot.Length + 1)
    foreach ($line in Get-Content $_.FullName)
    {
        if ($line -notmatch 'systems\.spawning\.(spawner_area|spawner_patrol|spawner_random)') { continue }
        $type = $Matches[1]
        $retired = $false
        if ($type -eq "spawner_random")
        {
            $retired = $line.Contains("eventRequired|4|empireday_ceremony")
        }
        elseif ($line -match 'strSpawns\|4\|([^|]+)')
        {
            $spawn = $Matches[1]
            foreach ($family in $families)
            {
                if ($spawn.StartsWith($family)) { $retired = $true; break }
            }
        }
        if ($retired)
        {
            $counts[$type]++
            $eventFiles[$relative] = $true
        }
    }
}
if ($counts.spawner_area -ne 315 -or $counts.spawner_patrol -ne 34 -or
    $counts.spawner_random -ne 8 -or $eventFiles.Count -ne 11)
{
    throw "Later event spawner inventory drifted: area=$($counts.spawner_area), patrol=$($counts.spawner_patrol), random=$($counts.spawner_random), files=$($eventFiles.Count)."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-empire-day-spawner-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.expected.ordinarySpawnersRetained -or -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $files.GetEnumerator())
    {
        $actual = (Get-FileHash (Join-Path $scriptRoot $entry.Value) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/176-p14-empire-day-spawner-retirement.patch"
    $actual = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actual -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Empire/Remembrance Day spawner retirement contract passed."
