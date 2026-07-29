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
$bodies = @{}
foreach ($entry in $files.GetEnumerator())
{
    $bodies[$entry.Key] = Get-Content (Join-Path $scriptRoot $entry.Value) -Raw
}
$library = $bodies["spawning.java"]
foreach ($required in @(
    "isRetiredLoveDaySpawner",
    'getStringObjVar(spawner, "eventRequired").equals("loveday")',
    'spawn.startsWith("loveday_")',
    "cleanupRetiredSpawnerChildren",
    'getAllObjectsWithObjVar(getLocation(spawner), 32000.0f, "objParent")',
    'getObjIdObjVar(child, "objParent") == spawner'
))
{
    if (-not $library.Contains($required)) { throw "Love Day generic-spawner boundary is missing: $required" }
}
if ($library.Contains('spawn.startsWith("lifeday_")') -or
    $library.Contains('getStringObjVar(spawner, "eventRequired").equals("lifeday")'))
{
    throw "The separate Life Day event was included in the Love Day predicate."
}

$handlers = [ordered]@{
    "spawner_area.java" = @("OnAttach", "OnInitialize", "doSpawnEvent", "createMob", "OnLocationReceived", "spawnDestroyed")
    "spawner_random.java" = @("OnAttach", "OnInitialize", "OnHearSpeech", "doSpawnEvent", "createMob", "spawnDestroyed")
}
foreach ($entry in $handlers.GetEnumerator())
{
    $body = $bodies[$entry.Key]
    foreach ($handler in $entry.Value)
    {
        $method = [regex]::Match($body, "(?s)public (?:int|void) $handler\(.*?(?=\r?\n\s*public (?:int|void|boolean|float)|\r?\n})").Value
        if (-not $method.Contains("spawning.isRetiredLoveDaySpawner(self)"))
        {
            throw "$($entry.Key) handler is not Love Day guarded: $handler"
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
            throw "$($entry.Key) $lifecycle does not clean authoritatively before detaching."
        }
    }
}
foreach ($lifecycle in @("OnAttach", "OnInitialize"))
{
    $method = [regex]::Match($bodies["spawner_patrol.java"], "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    if (-not $method.Contains("spawning.cleanupRetiredSpawnerChildren(self)"))
    {
        throw "Historical Empire Day patrol cleanup is not authoritative: $lifecycle"
    }
}

$buildoutRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/datatables/buildout"
$counts = @{spawner_area=0; spawner_random=0}
$eventFiles = @{}
Get-ChildItem $buildoutRoot -Recurse -Filter *.tab -File | ForEach-Object {
    $relative = $_.FullName.Substring($buildoutRoot.Length + 1)
    foreach ($line in Get-Content $_.FullName)
    {
        if ($line -notmatch 'systems\.spawning\.(spawner_area|spawner_random)') { continue }
        $type = $Matches[1]
        $retired = $line.Contains("eventRequired|4|loveday")
        if (-not $retired -and $line -match 'strSpawns\|4\|([^|]+)')
        {
            $retired = $Matches[1].StartsWith("loveday_")
        }
        if ($retired)
        {
            $counts[$type]++
            $eventFiles[$relative] = $true
        }
    }
}
if ($counts.spawner_area -ne 11 -or $counts.spawner_random -ne 11 -or $eventFiles.Count -ne 5)
{
    throw "Love Day generic-spawner inventory drifted: area=$($counts.spawner_area), random=$($counts.spawner_random), files=$($eventFiles.Count)."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-love-day-generic-spawner-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or -not $contract.expected.ordinarySpawnersRetained -or
        -not $contract.expected.lifeDaySpawnersRetained)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $files.GetEnumerator())
    {
        $actual = (Get-FileHash (Join-Path $scriptRoot $entry.Value) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/183-p14-love-day-generic-spawner-retirement.patch"
    $actual = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actual -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Love Day generic-spawner retirement contract passed."
