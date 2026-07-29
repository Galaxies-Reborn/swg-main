param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"

foreach ($contractName in @(
    "p14-later-life-day-city-spawner-retirement.json",
    "p14-life-day-2004-admission-restoration.json",
    "p14-life-day-2004-quest-state-machine.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required Life Day dependency is not ready: $contractName."
    }
}

$planetPath = Join-Path $scriptRoot "event/planet_event_handler.java"
$buffPath = Join-Path $scriptRoot "systems/buff/buff_handler.java"
$planet = Get-Content -LiteralPath $planetPath -Raw
$buff = Get-Content -LiteralPath $buffPath -Raw

function Get-JavaMethod
{
    param([string]$Body, [string]$Name)
    $match = [regex]::Match(
        $Body,
        "(?s)(?:public|private)\s+\w+\s+$([regex]::Escape($Name))\(.*?(?=\r?\n\s*(?:public|private)\s+\w+\s+\w+\(|\z)")
    if (-not $match.Success)
    {
        throw "Required method is missing: $Name."
    }
    return $match.Value
}

foreach ($methodName in @("OnAttach", "OnInitialize"))
{
    $method = Get-JavaMethod $planet $methodName
    if (-not $method.Contains("cleanupFactionalLifeDayData(self)") -or
        $method.Contains("checkLifeDayData(self)"))
    {
        throw "$methodName can still initialize the later factional Life Day scoreboard."
    }
}

foreach ($methodName in @("checkLifeDayData", "lifeDayDailyAlarm", "lifeDayScoreBoardUpdate"))
{
    $method = Get-JavaMethod $planet $methodName
    if (-not $method.Contains("isFactionalLifeDayScoreboardRetired()") -or
        -not $method.Contains("cleanupFactionalLifeDayData(self)") -or
        -not $method.Contains("return"))
    {
        throw "Planet scoreboard callback does not fail closed: $methodName."
    }
}

$planetCleanup = Get-JavaMethod $planet "cleanupFactionalLifeDayData"
if (-not $planetCleanup.Contains('removeObjVar(planet, "lifeday")') -or
    $planetCleanup.Contains("lifeday04"))
{
    throw "Planet cleanup crossed the original 2004 Life Day namespace boundary."
}

foreach ($methodName in @(
    "lifedayCompetitiveBuffRemoveBuffHandler",
    "scoreBoardCheck",
    "updateScore",
    "checkLifeDayData",
    "newLifeDayDay",
    "newLifeDayTimeStamp"
))
{
    $method = Get-JavaMethod $buff $methodName
    if (-not $method.Contains("isFactionalLifeDayScoreboardRetired()") -or
        -not $method.Contains("removeObjVar(") -or
        -not $method.Contains('"lifeday"') -or
        -not $method.Contains("return"))
    {
        throw "Persisted Life Day scoreboard callback does not fail closed: $methodName."
    }
    if ($method.Contains("lifeday04"))
    {
        throw "Later scoreboard cleanup mutates the original 2004 namespace: $methodName."
    }
}
if ([regex]::Matches($planet + $buff, "private boolean isFactionalLifeDayScoreboardRetired").Count -ne 2)
{
    throw "Later Life Day retirement guards are incomplete."
}

$targetAdmission = Get-Content (Join-Path $scriptRoot "event/holiday_controller.java") -Raw
$targetQuest = Get-Content (Join-Path $scriptRoot "conversation/lifeday04a.java") -Raw
if (-not $targetAdmission.Contains("refreshPrecuLifeDayPlanets(true)") -or
    -not $targetAdmission.Contains("refreshPrecuLifeDayPlanets(false)") -or
    -not $targetQuest.Contains("lifeday04.convTracker") -or
    -not $targetQuest.Contains("lifeday04.rewarded"))
{
    throw "Original 2004 Life Day admission or quest state was not retained."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-later-life-day-scoreboard-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        -not $contract.expected.targetNamespaceRetained -or
        $contract.expected.activeTargetAnchorCount -ne 1 -or
        $contract.expected.activeLaterScoreboardObjvarCount -ne 0 -or
        $contract.expected.postCleanupTargetAnchorCount -ne 0 -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or
        $contract.runtimeEvidence.structuredLogFatalSevereExceptionCount -ne 0)
    {
        throw "Later Life Day scoreboard retirement evidence is not ready."
    }
    foreach ($entry in @{
        "planet_event_handler.java" = $planetPath
        "buff_handler.java" = $buffPath
    }.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)."
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/193-p14-later-life-day-scoreboard-retirement.patch"
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
Write-Host "Publish 14.1 later Life Day scoreboard-retirement contract passed."
