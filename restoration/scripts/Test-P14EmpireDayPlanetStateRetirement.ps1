param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$relative = "dsrc/sku.0/sys.server/compiled/game/script/event/planet_event_handler.java"
$source = Join-Path $root $relative
$body = Get-Content $source -Raw
$cleanup = [regex]::Match($body, '(?s)private void cleanupEmpireDayEventData\(.*?(?=\r?\n\s*})\r?\n\s*}').Value
foreach ($required in @(
    'holiday.PLANET_VAR_EVENT_PREFIX + holiday.PLANET_VAR_EMPIRE_DAY',
    'removeObjVar(planet, empireDayData + holiday.PLANET_VAR_SCORE_TIMESTAMP)',
    'removeObjVar(planet, empireDayData + holiday.PLANET_VAR_SCORE)',
    'removeObjVar(planet, empireDayData)'
))
{
    if (-not $cleanup.Contains($required)) { throw "Empire Day planet cleanup is missing: $required" }
}
foreach ($handler in @("setUpEventLeaderBoard", "resetEventDataAfterDelay"))
{
    $method = [regex]::Match($body, "(?s)public int $handler\(.*?(?=\r?\n\s*public int|\r?\n\s*private)").Value
    $guard = [regex]::Match($method, '(?s)if \(eventVar\.equals\(holiday\.PLANET_VAR_EMPIRE_DAY\)\).*?return SCRIPT_CONTINUE;').Value
    if (-not $guard.Contains("cleanupEmpireDayEventData(self)"))
    {
        throw "$handler can recreate retired Empire Day state."
    }
}
$config = [regex]::Match($body, '(?s)private boolean checkForHolidayEventConfigs\(.*?(?=\r?\n\s*private void cleanupEmpireDayEventData)').Value
if (-not $config.Contains("cleanupEmpireDayEventData(planet)") -or
    $config.Contains('getConfigSetting("GameServer", "empireday_ceremony")') -or
    $config.Contains('messageTo(planet, "setUpEventLeaderBoard"'))
{
    throw "Configuration check can still create Empire Day planet state."
}
foreach ($retained in @("checkLifeDayData", "lifeDayDailyAlarm", "lifeDayScoreBoardUpdate"))
{
    if (-not $body.Contains($retained)) { throw "Life Day planet path was removed: $retained" }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-empire-day-planet-state-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or -not $contract.expected.lifeDayPlanetStateRetained)
    {
        throw "Runtime evidence is not ready."
    }
    $actual = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."planet_event_handler.java") { throw "Source evidence mismatch." }
    $patch = Join-Path $restorationRoot "patches/dsrc/179-p14-empire-day-planet-state-retirement.patch"
    $actual = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actual -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Empire Day planet-state retirement contract passed."
