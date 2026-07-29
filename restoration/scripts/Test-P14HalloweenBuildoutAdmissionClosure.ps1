param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$serverGame = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$sharedGame = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game"
$scriptRoot = Join-Path $serverGame "script"

$areaFiles = [ordered]@{
    "areas_naboo.tab" = Join-Path $sharedGame "datatables/buildout/areas_naboo.tab"
    "areas_tatooine.tab" = Join-Path $sharedGame "datatables/buildout/areas_tatooine.tab"
}
$expectedAreas = [ordered]@{
    "areas_naboo.tab" = "server_halloween_moenia"
    "areas_tatooine.tab" = "server_halloween_mos_eisley"
}
foreach ($entry in $expectedAreas.GetEnumerator())
{
    $matches = @(Get-Content $areaFiles[$entry.Key] | Where-Object {
        $columns = $_ -split "`t", -1
        $columns[0] -eq $entry.Value -and $columns[24] -eq "halloween"
    })
    if ($matches.Count -ne 1)
    {
        throw "$($entry.Value) is not exactly gated by eventRequired=halloween."
    }
}

$buildoutFiles = [ordered]@{
    "server_halloween_moenia.tab" = Join-Path $serverGame "datatables/buildout/naboo/server_halloween_moenia.tab"
    "server_halloween_mos_eisley.tab" = Join-Path $serverGame "datatables/buildout/tatooine/server_halloween_mos_eisley.tab"
}
$totalRows = 0
$areaSpawners = 0
$skeletonSpawners = 0
$vendorSpawners = 0
$passiveRows = 0
foreach ($path in $buildoutFiles.Values)
{
    $rows = @(Get-Content $path | Select-Object -Skip 2)
    $totalRows += $rows.Count
    foreach ($line in $rows)
    {
        $columns = $line -split "`t", -1
        if ($columns[2] -eq "object/tangible/ground_spawning/area_spawner.iff")
        {
            $areaSpawners++
            if ($columns[12] -match 'strSpawns\|4\|(halloween_+skeleton)\|')
            {
                $skeletonSpawners++
            }
            elseif ($columns[12] -match 'strSpawns\|4\|halloween_vendor\|')
            {
                $vendorSpawners++
            }
            else
            {
                throw "Unexpected Halloween area spawner row: $line"
            }
        }
        else
        {
            $passiveRows++
            if ($columns[11])
            {
                throw "Halloween passive decoration unexpectedly carries a script: $line"
            }
        }
    }
}
if ($totalRows -ne 664 -or $passiveRows -ne 638 -or $areaSpawners -ne 26 -or
    $skeletonSpawners -ne 24 -or $vendorSpawners -ne 2)
{
    throw "Halloween buildout inventory drifted: total=$totalRows passive=$passiveRows spawners=$areaSpawners skeleton=$skeletonSpawners vendor=$vendorSpawners."
}

$controllerPath = Join-Path $scriptRoot "event/holiday_controller.java"
$controller = Get-Content $controllerPath -Raw
$halloweenStart = [regex]::Match($controller, '(?s)public int halloweenServerStart\(.*?(?=\r?\n\s*public)').Value
if (-not $halloweenStart.Contains('retireHolidayEvent("halloween")') -or
    $controller.Contains('startUniverseWideEvent("halloween")'))
{
    throw "Halloween startup is not fail-closed."
}
foreach ($speech in @("halloweenStart", "halloweenStop", "halloweenStartForReals", "halloweenStopForReals"))
{
    $case = [regex]::Match($controller, "(?s)case `"$speech`":.*?(?=\r?\n\s*case|\r?\n\s*})").Value
    if (-not $case.Contains('retireLaterHolidayEvent(speaker, "halloween"'))
    {
        throw "Halloween operator path is not fail-closed: $speech"
    }
}
foreach ($helper in @("startHolidayEvent", "startHolidayEventForReals", "stopHolidayEvent", "stopHolidayEventForReals"))
{
    $callers = @([regex]::Matches($controller, "\b$helper\("))
    if ($callers.Count -ne 2 -or -not $controller.Contains("$helper(speaker, `"lifeday`""))
    {
        throw "Shared holiday helper is no longer Life Day-only: $helper"
    }
}
$directStarts = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File |
    Select-String -Pattern 'startUniverseWideEvent\("halloween"\)')
if ($directStarts.Count -ne 0)
{
    throw "A direct Halloween start entrypoint remains."
}

$buildoutManagerPath = Join-Path $root "src/engine/server/library/serverGame/src/shared/core/ServerBuildoutManager.cpp"
$planetObjectPath = Join-Path $root "src/engine/server/library/serverGame/src/shared/object/PlanetObject.cpp"
$buildoutManager = Get-Content $buildoutManagerPath -Raw
$planetObject = Get-Content $planetObjectPath -Raw
foreach ($required in @(
    'if (!buildoutRow.m_eventRequired.empty())',
    'if (!eventCurrentlyRunning)',
    'continue; // We found an event object but their event isn''t started yet.',
    'void ServerBuildoutManager::onEventStarted(std::string const & eventName)',
    'void ServerBuildoutManager::onEventStopped(std::string const & eventName)',
    '(*objIter).loadedObject = nullptr;'
))
{
    if (-not $buildoutManager.Contains($required))
    {
        throw "Engine required-event lifecycle evidence is missing: $required"
    }
}
if (-not $planetObject.Contains("ServerBuildoutManager::onEventStopped(oldList[i])") -or
    -not $planetObject.Contains("ServerBuildoutManager::onEventStarted(newList[i])"))
{
    throw "Planet event-list changes do not drive buildout lifecycle callbacks."
}

$dathomir = Join-Path $serverGame "datatables/buildout/dathomir/dathomir_1_1.tab"
$incidental = @(Get-Content $dathomir | Where-Object {
    $_.Contains("object/static/halloween/item_skull_candle1.iff")
})
if ($incidental.Count -ne 1)
{
    throw "Dathomir incidental static-prop boundary drifted."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-halloween-buildout-admission-closure.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or -not $contract.buildEvidence.evidenceOnly -or
        $contract.expected.halloweenStartEntrypoints -ne 0 -or
        -not $contract.expected.staleEventStopUnloadsBuildout -or
        -not $contract.expected.lifeDayAdmissionRetained)
    {
        throw "Halloween buildout admission evidence is not ready."
    }
    $hashFiles = [ordered]@{
        "areas_naboo.tab" = $areaFiles["areas_naboo.tab"]
        "areas_tatooine.tab" = $areaFiles["areas_tatooine.tab"]
        "server_halloween_moenia.tab" = $buildoutFiles["server_halloween_moenia.tab"]
        "server_halloween_mos_eisley.tab" = $buildoutFiles["server_halloween_mos_eisley.tab"]
        "holiday_controller.java" = $controllerPath
        "ServerBuildoutManager.cpp" = $buildoutManagerPath
        "PlanetObject.cpp" = $planetObjectPath
    }
    foreach ($entry in $hashFiles.GetEnumerator())
    {
        $actual = (Get-FileHash $entry.Value -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
}
Write-Host "Publish 14.1 Halloween buildout-admission closure contract passed."
