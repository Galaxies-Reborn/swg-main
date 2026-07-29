param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"

foreach ($contractName in @(
    "p14-life-day-lineage-boundary.json",
    "p14-later-life-day-city-spawner-retirement.json",
    "p14-later-holiday-control-plane-retirement.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required Life Day dependency is not ready: $contractName."
    }
}

$paths = [ordered]@{
    "holiday_controller.java" = Join-Path $scriptRoot "event/holiday_controller.java"
    "planet_base.java" = Join-Path $scriptRoot "planet/planet_base.java"
    "city_spawner.java" = Join-Path $scriptRoot "event/lifeday/city_spawner.java"
    "lifeday_spawner.java" = Join-Path $scriptRoot "event/lifeday/lifeday_spawner.java"
    "celebrity_lifeday_spawner.java" = Join-Path $scriptRoot "npc/celebrity/lifeday_spawner.java"
    "precu_lifeday_2004_fixture.java" = Join-Path $scriptRoot "test/precu_lifeday_2004_fixture.java"
    "precu_profession_requirement_fixture.java" = Join-Path $scriptRoot "test/precu_profession_requirement_fixture.java"
}
$source = [ordered]@{}
foreach ($entry in $paths.GetEnumerator())
{
    $source[$entry.Key] = Get-Content $entry.Value -Raw
}

$holiday = $source["holiday_controller.java"]
foreach ($required in @(
    "refreshPrecuLifeDayPlanets(true)",
    "refreshPrecuLifeDayPlanets(false)",
    'params.put("active", active)',
    '"tatooine"',
    '"corellia"',
    '"naboo"',
    '"dathomir"',
    '"endor"',
    '"yavin4"'
))
{
    if (-not $holiday.Contains($required))
    {
        throw "Life Day control-plane admission is missing: $required."
    }
}

$planet = $source["planet_base.java"]
foreach ($required in @(
    '"refreshPrecuLifeDayFromState", null, 780.0f',
    "refreshPrecuLifeDayAnchors",
    'return "event.lifeday.city_spawner"',
    'return "event.lifeday.lifeday_spawner"',
    "getNameForPlanetObject(self)",
    '"retirePrecuLifeDayAnchors"'
))
{
    if (-not $planet.Contains($required))
    {
        throw "Life Day planet lifecycle is missing: $required."
    }
}

$city = $source["city_spawner.java"]
$forest = $source["lifeday_spawner.java"]
foreach ($body in @($city, $forest))
{
    foreach ($required in @(
        'private static final String OWNER_VAR = "precuLifeDay.anchor"',
        "getNameForPlanetObject(self)",
        "!myPlanet.equals(getCurrentSceneName())",
        'setObjVar(anchor, "objParent", self)',
        "getObjIdObjVar(child, `"objParent`") == self",
        "retirePrecuLifeDayAnchors",
        "detachScript(self"
    ))
    {
        if (-not $body.Contains($required))
        {
            throw "Life Day authoritative-owned spawner behavior is missing: $required."
        }
    }
}
foreach ($coordinate in @(
    "{131,52,-5384}",
    "{-5545,23,-6177}",
    "{-5557,-150,0}"
))
{
    if (-not $city.Contains($coordinate))
    {
        throw "Original Life Day city coordinate is missing: $coordinate."
    }
}
if (-not $forest.Contains("LOCS[locStart + i]"))
{
    throw "Forest Life Day anchors do not use distinct coordinates."
}
$locBlock = [regex]::Match(
    $forest,
    "(?s)private static final int\[\]\[\] LOCS\s*=\s*\{(.*?)\};").Groups[1].Value
$locations = @([regex]::Matches(
    $locBlock,
    "\{\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\}") |
    ForEach-Object { "$($_.Groups[1].Value),$($_.Groups[2].Value),$($_.Groups[3].Value)" })
if ($locations.Count -ne 12 -or @($locations | Sort-Object -Unique).Count -ne 12)
{
    throw "Original Life Day forest coordinate matrix drifted."
}

$celebrity = $source["celebrity_lifeday_spawner.java"]
foreach ($required in @(
    'private static final String OWNER_VAR = "precuLifeDay.celebrity"',
    'setObjVar(celeb, "objParent", self)',
    "attachScript(celeb, script)",
    "getAllObjectsWithObjVar",
    "destroyObject(child)"
))
{
    if (-not $celebrity.Contains($required))
    {
        throw "Original Life Day quest-NPC lifecycle is missing: $required."
    }
}

$driver = $source["precu_lifeday_2004_fixture.java"]
$professionFixture = $source["precu_profession_requirement_fixture.java"]
foreach ($required in @(
    "39008597L",
    "PLAYER_STATION_ID = 1001",
    '"precu.fixture.lifeday.active"',
    '"refreshPrecuLifeDayAnchors"',
    "detachScript(self, DRIVER)"
))
{
    if (-not $driver.Contains($required))
    {
        throw "Identity-locked Life Day lifecycle driver is missing: $required."
    }
}
foreach ($required in @(
    '"lifeday-on:"',
    '"lifeday-off:"',
    "executeLifeDayLifecycle",
    "attachScript(player, LIFEDAY_DRIVER)"
))
{
    if (-not $professionFixture.Contains($required))
    {
        throw "Life Day console bridge is missing: $required."
    }
}

$spawning = Get-Content (Join-Path $scriptRoot "library/spawning.java") -Raw
if (-not $spawning.Contains('getStringObjVar(spawner, "eventRequired").equals("life_day")') -or
    $spawning.Contains('getStringObjVar(spawner, "eventRequired").equals("lifeday")'))
{
    throw "Later factional Life Day retirement boundary drifted."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-life-day-2004-admission-restoration.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.expected.fullClusterCityAnchors -ne 3 -or
        $contract.expected.fullClusterForestAnchors -ne 12 -or
        $contract.expected.fullClusterQuestNpcs -ne 15 -or
        $contract.expected.singleSceneRuntimeAnchors -ne 1 -or
        -not $contract.expected.sceneAuthoritativeCreation -or
        -not $contract.expected.ownedCleanup -or
        $contract.runtimeEvidence.postCleanupAnchorCount -ne 0 -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Life Day 2004 admission-restoration evidence is not ready."
    }
    foreach ($entry in $paths.GetEnumerator())
    {
        $actual = (Get-FileHash $entry.Value -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)."
        }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/191-p14-life-day-2004-admission-restoration.patch"
    $actualPatchHash = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actualPatchHash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Life Day 2004 admission-restoration contract passed."
