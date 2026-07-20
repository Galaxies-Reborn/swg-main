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
if ($body.Contains('startUniverseWideEvent("empireday_ceremony")') -or
    $body.Contains('getConfigSetting("GameServer", "empireday_ceremony")'))
{
    throw "Empire Day can still be started from the holiday controller."
}
$retire = [regex]::Match($body, '(?s)private void retireEmpireDayEvent\(.*?(?=\r?\n\s*})\r?\n\s*}').Value
if (-not $retire.Contains('getCurrentUniverseWideEvents().indexOf("empireday_ceremony")') -or
    -not $retire.Contains('stopUniverseWideEvent("empireday_ceremony")'))
{
    throw "Stale Empire Day universe-event cleanup is missing."
}
foreach ($lifecycle in @("OnAttach", "OnInitialize"))
{
    $method = [regex]::Match($body, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    if (-not $method.Contains("empiredayServerStart(self, null)") -or
        $method.Contains('messageTo(self, "empiredayServerStart"'))
    {
        throw "$lifecycle does not synchronously retire Empire Day."
    }
}
$speech = [regex]::Match($body, '(?s)public int OnHearSpeech\(.*?(?=\r?\n\s*private void startHolidayEvent)').Value
foreach ($command in @("empiredayStart", "empiredayStop", "empiredayStartForReals", "empiredayStopForReals"))
{
    $case = [regex]::Match($speech, "(?s)case `"$command`":(.*?)(?=case |})").Groups[1].Value
    if (-not $case.Contains("retireEmpireDayEvent()") -or
        $case.Contains("startHolidayEvent") -or $case.Contains("startHolidayEventForReals"))
    {
        throw "Operator command is not retired: $command"
    }
}
foreach ($retained in @(
    'startHolidayEvent(speaker, "lifeday"'
))
{
    if (-not $speech.Contains($retained)) { throw "Shared holiday branch was removed: $retained" }
}
if (-not $body.Contains("Empire Day Event Running = False (Publish 14.1)"))
{
    throw "Operator attributes do not report the retirement boundary."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-empire-day-control-plane-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or -not $contract.expected.otherHolidayBranchesRetained)
    {
        throw "Runtime evidence is not ready."
    }
    $actual = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."holiday_controller.java")
    {
        $laterContract = Get-Content (Join-Path $restorationRoot "contracts/p14-later-holiday-control-plane-retirement.json") -Raw | ConvertFrom-Json
        if ($laterContract.status -ne "ready" -or
            $actual -ne $laterContract.buildEvidence.sourceSha256."holiday_controller.java")
        {
            throw "Source evidence mismatch."
        }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/178-p14-empire-day-control-plane-retirement.patch"
    $actual = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actual -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Empire Day control-plane retirement contract passed."
