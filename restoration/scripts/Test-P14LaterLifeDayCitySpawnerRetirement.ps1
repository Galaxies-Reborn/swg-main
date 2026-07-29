param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$serverGame = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$scriptRoot = Join-Path $serverGame "script"
$buildoutRoot = Join-Path $serverGame "datatables/buildout"

foreach ($contractName in @(
    "p14-life-day-lineage-boundary.json",
    "p14-love-day-generic-spawner-retirement.json",
    "p14-later-holiday-reward-anchor-retirement.json",
    "p14-storyteller-band-spawner-retirement.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required later-Life-Day dependency is not ready: $contractName."
    }
}

$spawningPath = Join-Path $scriptRoot "library/spawning.java"
$spawning = Get-Content $spawningPath -Raw
foreach ($required in @(
    "isRetiredLoveDaySpawner",
    'getStringObjVar(spawner, "eventRequired").equals("loveday")',
    'getStringObjVar(spawner, "eventRequired").equals("life_day")',
    'spawn.startsWith("loveday_")',
    "cleanupRetiredSpawnerChildren",
    'getObjIdObjVar(child, "objParent") == spawner'
))
{
    if (-not $spawning.Contains($required))
    {
        throw "Later Life Day generic-spawner boundary is missing: $required."
    }
}
if ($spawning.Contains('getStringObjVar(spawner, "eventRequired").equals("lifeday")') -or
    $spawning.Contains('spawn.startsWith("lifeday_")'))
{
    throw "The retained 2004 Life Day event entered the generic-spawner predicate."
}

$scriptFiles = [ordered]@{
    "spawner_area.java" = Join-Path $scriptRoot "systems/spawning/spawner_area.java"
    "spawner_random.java" = Join-Path $scriptRoot "systems/spawning/spawner_random.java"
}
$handlers = [ordered]@{
    "spawner_area.java" = @("OnAttach", "OnInitialize", "doSpawnEvent", "createMob", "OnLocationReceived", "spawnDestroyed")
    "spawner_random.java" = @("OnAttach", "OnInitialize", "OnHearSpeech", "doSpawnEvent", "createMob", "spawnDestroyed")
}
foreach ($entry in $handlers.GetEnumerator())
{
    $body = Get-Content $scriptFiles[$entry.Key] -Raw
    foreach ($handler in $entry.Value)
    {
        $method = [regex]::Match($body, "(?s)public (?:int|void) $handler\(.*?(?=\r?\n\s*public (?:int|void|boolean|float)|\r?\n})").Value
        if (-not $method.Contains("spawning.isRetiredLoveDaySpawner(self)"))
        {
            throw "$($entry.Key) does not guard queued producer $handler."
        }
    }
    foreach ($lifecycle in @("OnAttach", "OnInitialize"))
    {
        $method = [regex]::Match($body, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
        $cleanup = $method.IndexOf("spawning.cleanupRetiredSpawnerChildren(self)")
        $destroy = $method.IndexOf("OnDestroy(self)")
        $detach = $method.IndexOf("detachScript(self")
        if ($cleanup -lt 0 -or $destroy -lt 0 -or $detach -lt 0 -or
            $cleanup -gt $destroy -or $destroy -gt $detach)
        {
            throw "$($entry.Key) $lifecycle is not cleanup-first."
        }
    }
}

$laterBuildouts = @(
    Join-Path $buildoutRoot "corellia/lifeday_doaba_guerfel.tab"
    Join-Path $buildoutRoot "talus/lifeday_dearic.tab"
    Join-Path $buildoutRoot "tatooine/lifeday_wayfar.tab"
)
$counts = [ordered]@{ area = 0; random = 0; tree = 0; unclassified = 0 }
foreach ($path in $laterBuildouts)
{
    foreach ($line in Get-Content $path | Select-Object -Skip 2)
    {
        $columns = $line -split "`t", -1
        if ($columns[11] -eq "systems.spawning.spawner_area" -and
            $columns[12].Contains("eventRequired|4|life_day"))
        {
            $counts.area++
        }
        elseif ($columns[11] -eq "systems.spawning.spawner_random" -and
            $columns[12].Contains("eventRequired|4|life_day"))
        {
            $counts.random++
        }
        elseif ($columns[2] -eq "object/tangible/holiday/life_day/main_lifeday_tree.iff" -and
            $columns[11].Contains("systems.storyteller.events.figrin_dan_band_spawner") -and
            $columns[11].Contains("event.lifeday.lifeday_tree"))
        {
            $counts.tree++
        }
        else
        {
            $counts.unclassified++
        }
    }
}
if ($counts.area -ne 18 -or $counts.random -ne 6 -or $counts.tree -ne 3 -or $counts.unclassified -ne 0)
{
    throw "Later Life Day city partition drifted: $($counts | ConvertTo-Json -Compress)."
}

$bandSpawner = Get-Content (Join-Path $scriptRoot "systems/storyteller/events/figrin_dan_band_spawner.java") -Raw
$lifeDayTree = Get-Content (Join-Path $scriptRoot "event/lifeday/lifeday_tree.java") -Raw
foreach ($lifecycle in @("OnAttach", "OnInitialize"))
{
    $bandMethod = [regex]::Match($bandSpawner, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    $treeMethod = [regex]::Match($lifeDayTree, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    if (-not $bandMethod.Contains('detachScript(self, "systems.storyteller.events.figrin_dan_band_spawner")') -or
        -not $treeMethod.Contains('detachScript(self, "event.lifeday.lifeday_tree")'))
    {
        throw "Later Life Day main-tree anchor is no longer inert: $lifecycle."
    }
}

$mosEspaRows = @(Get-Content (Join-Path $buildoutRoot "tatooine/lifeday_mos_espa.tab") | Select-Object -Skip 2)
if ($mosEspaRows.Count -ne 38 -or
    @($mosEspaRows | Where-Object { $_.Contains("systems.spawning.spawner_") }).Count -ne 0)
{
    throw "Target Mos Espa route was conflated with later generic spawners."
}
$orbRows = 0
foreach ($relative in @("dathomir/dathomir_3_2_ws.tab", "endor/endor_4_4_ws.tab", "yavin4/yavin4_4_3_ws.tab"))
{
    $orbRows += @(Get-Content (Join-Path $buildoutRoot $relative) | Where-Object {
        $_.Contains("object/tangible/loot/quest/lifeday_orb.iff")
    }).Count
}
if ($orbRows -ne 6)
{
    throw "Target forest-orb route drifted."
}
foreach ($targetScript in @(
    "event/lifeday/city_spawner.java",
    "event/lifeday/lifeday_spawner.java",
    "conversation/lifeday04a.java",
    "conversation/lifeday04b.java",
    "conversation/lifeday04c.java",
    "conversation/lifeday04d.java",
    "conversation/lifeday04e.java"
))
{
    if (-not (Test-Path (Join-Path $scriptRoot $targetScript)))
    {
        throw "Retained 2004 Life Day source is missing: $targetScript."
    }
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-later-life-day-city-spawner-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or
        -not $contract.expected.authoritativeChildCleanup -or
        -not $contract.expected.lifeDayUniverseEventRetained)
    {
        throw "Later Life Day city-spawner runtime evidence is not ready."
    }
    $hashFiles = [ordered]@{
        "spawning.java" = $spawningPath
        "spawner_area.java" = $scriptFiles["spawner_area.java"]
        "spawner_random.java" = $scriptFiles["spawner_random.java"]
    }
    foreach ($entry in $hashFiles.GetEnumerator())
    {
        $actual = (Get-FileHash $entry.Value -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)."
        }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/190-p14-later-life-day-city-spawner-retirement.patch"
    $actualPatchHash = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actualPatchHash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 later Life Day city-spawner retirement contract passed."
