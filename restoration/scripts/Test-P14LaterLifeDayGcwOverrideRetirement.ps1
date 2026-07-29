param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"

foreach ($contractName in @(
    "p14-life-day-lineage-boundary.json",
    "p14-later-life-day-city-spawner-retirement.json",
    "p14-life-day-2004-admission-restoration.json",
    "p14-later-life-day-scoreboard-retirement.json",
    "p14-later-life-day-stap-admission-retirement.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required Life Day dependency is not ready: $contractName."
    }
}

$gcwPath = Join-Path $scriptRoot "library/gcw.java"
$gcw = Get-Content -LiteralPath $gcwPath -Raw
$method = [regex]::Match(
    $gcw,
    '(?s)public static boolean gcwIsInvasionCityOn\(.*?(?=\r?\n\s*public static)').Value
if (-not $method)
{
    throw "GCW invasion admission method is missing."
}
foreach ($retired in @(
    '"lifeday"',
    'city.equalsIgnoreCase("dearic")',
    "life day is turned on"
))
{
    if ($method.Contains($retired))
    {
        throw "Later Life Day GCW override remains: $retired."
    }
}
foreach ($retained in @(
    'getConfigSetting("GameServer", "gcwcity" + city)',
    'cityConfig == null',
    'return false;',
    'return true;'
))
{
    if (-not $method.Contains($retained))
    {
        throw "Ordinary GCW invasion configuration drifted: $retained."
    }
}

$holidayController = Get-Content (Join-Path $scriptRoot "event/holiday_controller.java") -Raw
if (-not $holidayController.Contains("refreshPrecuLifeDayPlanets(true)") -or
    -not $holidayController.Contains("refreshPrecuLifeDayPlanets(false)"))
{
    throw "Original 2004 Life Day admission was not retained."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-later-life-day-gcw-override-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.expected.gcwLifeDayReferences -ne 0 -or
        $contract.expected.dearicLifeDaySuppression -or
        -not $contract.expected.ordinaryCityConfigGateRetained -or
        -not $contract.expected.original2004AdmissionRetained -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Later Life Day GCW override-retirement evidence is not ready."
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $gcwPath).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."gcw.java")
    {
        throw "GCW source evidence mismatch."
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/195-p14-later-life-day-gcw-override-retirement.patch"
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
Write-Host "Publish 14.1 later Life Day GCW override-retirement contract passed."
