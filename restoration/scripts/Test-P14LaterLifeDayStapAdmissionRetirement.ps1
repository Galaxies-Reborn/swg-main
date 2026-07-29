param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$serverGame = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$scriptRoot = Join-Path $serverGame "script"

foreach ($contractName in @(
    "p14-life-day-lineage-boundary.json",
    "p14-later-life-day-city-spawner-retirement.json",
    "p14-life-day-2004-admission-restoration.json",
    "p14-later-life-day-scoreboard-retirement.json",
    "p14-storyteller-band-spawner-retirement.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required Life Day dependency is not ready: $contractName."
    }
}

$cantinaPath = Join-Path $serverGame "datatables/spawning/building_spawns/mos_espa_cantina.tab"
$cantinaRows = @(Get-Content -LiteralPath $cantinaPath | Select-Object -Skip 2)
$tkRows = @($cantinaRows | Where-Object { ($_ -split "`t", -1)[0] -eq "stormtrooper_fat_tk555" })
$lifeDayRows = @($cantinaRows | Where-Object { ($_ -split "`t", -1)[2] -eq "lifeday" })
$candyRows = @($lifeDayRows | Where-Object {
    ($_ -split "`t", -1)[0] -eq "object/static/item/item_wrapped_candy.iff"
})
$foodRows = @($lifeDayRows | Where-Object {
    ($_ -split "`t", -1)[0] -eq "object/static/item/item_container_organic_food.iff"
})
if ($tkRows.Count -ne 0 -or $lifeDayRows.Count -ne 6 -or
    $candyRows.Count -ne 5 -or $foodRows.Count -ne 1)
{
    throw "Mos Espa cantina Life Day partition drifted: tk=$($tkRows.Count) passive=$($lifeDayRows.Count) candy=$($candyRows.Count) food=$($foodRows.Count)."
}

$buildingSpawnRoot = Join-Path $serverGame "datatables/spawning/building_spawns"
$tkProducerRows = @(Get-ChildItem $buildingSpawnRoot -Recurse -Filter *.tab -File |
    Select-String -SimpleMatch "stormtrooper_fat_tk555")
if ($tkProducerRows.Count -ne 0)
{
    throw "A normal TK-555 building-spawn producer remains."
}

$lifeDayVendorPath = Join-Path $scriptRoot "conversation/lifeday_vendor.java"
$lifeDayVendor = Get-Content -LiteralPath $lifeDayVendorPath -Raw
$questGrantFiles = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | Where-Object {
    (Get-Content $_.FullName -Raw).Contains('groundquests.grantQuest(player, "lifeday_stap_1")')
})
if ($questGrantFiles.Count -ne 1 -or
    $questGrantFiles[0].FullName -ne $lifeDayVendorPath -or
    -not $lifeDayVendor.Contains('groundquests.grantQuest(player, "lifeday_stap_1")'))
{
    throw "Life Day STAP quest-grant boundary drifted."
}

$figrinPath = Join-Path $serverGame "datatables/spawning/holiday/figrin_dan_lifeday.tab"
$figrin = Get-Content -LiteralPath $figrinPath -Raw
if (-not $figrin.Contains("lifeday_saun_dann") -or
    -not $figrin.Contains("lifeday_wookiee_vendor"))
{
    throw "Life Day STAP quest-grant NPC inventory drifted."
}
$bandSpawner = Get-Content (Join-Path $scriptRoot "systems/storyteller/events/figrin_dan_band_spawner.java") -Raw
foreach ($lifecycle in @("OnAttach", "OnInitialize"))
{
    $method = [regex]::Match($bandSpawner, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    if (-not $method.Contains('detachScript(self, "systems.storyteller.events.figrin_dan_band_spawner")'))
    {
        throw "Saun Dann can still be admitted through the Figrin Dan producer: $lifecycle."
    }
}

foreach ($persistedScript in @(
    "conversation/lifeday_vendor.java",
    "conversation/stap_quest_tk555.java",
    "conversation/stap_quest_master_1.java",
    "conversation/stap_quest_master_2.java",
    "conversation/stap_quest_jawa_droid.java",
    "conversation/tatooine_espa_watto.java"
))
{
    if (-not (Test-Path (Join-Path $scriptRoot $persistedScript)))
    {
        throw "Persisted Life Day STAP compatibility script is missing: $persistedScript."
    }
}

$targetCandyPath = Join-Path $serverGame "datatables/buildout/tatooine/lifeday_mos_espa.tab"
$targetCandyRows = @(Get-Content $targetCandyPath | Select-Object -Skip 2)
$holidayController = Get-Content (Join-Path $scriptRoot "event/holiday_controller.java") -Raw
if ($targetCandyRows.Count -ne 38 -or
    -not $holidayController.Contains("refreshPrecuLifeDayPlanets(true)") -or
    -not $holidayController.Contains("refreshPrecuLifeDayPlanets(false)"))
{
    throw "Original 2004 Life Day admission was not retained."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-later-life-day-stap-admission-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.expected.tk555NormalWorldProducers -ne 0 -or
        $contract.expected.passiveCantinaLifeDayRows -ne 6 -or
        -not $contract.expected.persistedQuestScriptsRetained -or
        -not $contract.expected.original2004AdmissionRetained -or
        $contract.runtimeEvidence.tk555ObjectCount -ne 0 -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Later Life Day STAP admission-retirement evidence is not ready."
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $cantinaPath).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."mos_espa_cantina.tab")
    {
        throw "Cantina source evidence mismatch."
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/194-p14-later-life-day-stap-admission-retirement.patch"
    $patchText = [IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"
    $patchBytes = [Text.Encoding]::UTF8.GetBytes($patchText)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $patchHash = ([BitConverter]::ToString($sha.ComputeHash($patchBytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($patchBytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $patchHash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Overlay evidence mismatch."
    }
}
Write-Host "Publish 14.1 later Life Day STAP admission-retirement contract passed."
