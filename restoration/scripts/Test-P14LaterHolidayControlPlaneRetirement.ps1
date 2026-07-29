param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$relative = "dsrc/sku.0/sys.server/compiled/game/script/event/holiday_controller.java"
$source = Join-Path $root $relative
$body = Get-Content $source -Raw

foreach ($holidayName in @("halloween", "loveday"))
{
    if ($body.Contains("startHolidayEvent(speaker, `"$holidayName`"") -or
        $body.Contains("startHolidayEventForReals(speaker, `"$holidayName`"") -or
        $body.Contains("startUniverseWideEvent(`"$holidayName`")") -or
        $body.Contains("getConfigSetting(`"GameServer`", `"$holidayName`")"))
    {
        throw "$holidayName can still be started from the shared holiday controller."
    }
    foreach ($lifecycle in @("OnAttach", "OnInitialize"))
    {
        $method = [regex]::Match($body, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
        if (-not $method.Contains("$($holidayName)ServerStart(self, null)") -or
            $method.Contains("messageTo(self, `"$($holidayName)ServerStart`""))
        {
            throw "$lifecycle does not synchronously retire $holidayName."
        }
    }
    $serverStart = [regex]::Match(
        $body,
        "(?s)public int $($holidayName)ServerStart\(.*?(?=\r?\n\s*public|\r?\n\s*private)"
    ).Value
    if (-not $serverStart.Contains("retireHolidayEvent(`"$holidayName`")"))
    {
        throw "$holidayName server-start handler does not retire stale state."
    }
}

$speech = [regex]::Match($body, '(?s)public int OnHearSpeech\(.*?(?=\r?\n\s*private void startHolidayEvent)').Value
foreach ($holidayName in @("halloween", "loveday"))
{
    foreach ($suffix in @("Start", "Stop", "StartForReals", "StopForReals"))
    {
        $command = "$holidayName$suffix"
        $case = [regex]::Match($speech, "(?s)case `"$command`":(.*?)(?=case |})").Groups[1].Value
        if (-not $case.Contains("retireLaterHolidayEvent") -or
            $case.Contains("startHolidayEvent") -or $case.Contains("startHolidayEventForReals"))
        {
            throw "Operator command is not retired: $command"
        }
    }
}

foreach ($retained in @(
    'messageTo(self, "lifedayServerStart"',
    'startHolidayEvent(speaker, "lifeday"',
    'startHolidayEventForReals(speaker, "lifeday"',
    'startUniverseWideEvent("lifeday")'
))
{
    if (-not $body.Contains($retained)) { throw "2004 Life Day control path was removed: $retained" }
}

if (-not $body.Contains("Halloween Event Running = False (Publish 14.1)") -or
    -not $body.Contains("Love Day Event Running = False (Publish 14.1)"))
{
    throw "Operator attributes do not report the later-holiday retirement boundary."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-later-holiday-control-plane-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or -not $contract.expected.lifeDayControlPlaneRetained)
    {
        throw "Runtime evidence is not ready."
    }
    $actual = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."holiday_controller.java") { throw "Source evidence mismatch." }
    $patch = Join-Path $restorationRoot "patches/dsrc/181-p14-later-holiday-control-plane-retirement.patch"
    $actual = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actual -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 later-holiday control-plane retirement contract passed."
