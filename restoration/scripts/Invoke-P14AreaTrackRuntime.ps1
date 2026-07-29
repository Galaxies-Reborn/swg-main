[CmdletBinding()]
param(
    [ValidatePattern("^[0-9]+$")][string]$PlayerOid = "44003778",
    [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)]
    [int]$ClientProcessId,
    [ValidatePattern("^[A-Za-z0-9_.-]+$")][string]$ContainerName = "swg-precu",
    [string]$ToolsRoot,
    [string]$ClientRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ToolsRoot))
{
    $sourceRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $ToolsRoot = Join-Path $sourceRoot "pre-cu-reborn-tools"
}
if ([string]::IsNullOrWhiteSpace($ClientRoot))
{
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $ToolsRoot)
    $ClientRoot = Join-Path $workspaceRoot "PreCU-Client"
}
$bridge = Join-Path $ToolsRoot "scripts/Invoke-PrecuBackgroundInput.ps1"
$expectedClient = (Resolve-Path (Join-Path $ClientRoot "SwgClient_r.exe")).Path
$process = Get-Process -Id $ClientProcessId -ErrorAction Stop
if ([string]$process.Path -cne $expectedClient)
{
    throw "Process $ClientProcessId is not the isolated proof client: $($process.Path)"
}

function Invoke-Fixture([string]$Action, [string]$Lifecycle)
{
    $arguments = "$Action $PlayerOid $Lifecycle"
    $serverCommand = "game tatooine runScript " +
        "test.precu_area_track_command_fixture executeFixture $arguments"
    $bashCommand = "cd /swg-precu/exe/linux && printf '%-1024s' " +
        "'$serverCommand' | ./bin/ServerConsole -- @servercommon.cfg " +
        "-s ServerConsole serverAddress=127.0.0.1 serverPort=61000"
    $previous = $ErrorActionPreference
    try
    {
        $ErrorActionPreference = "Continue"
        $output = @(& docker exec $ContainerName bash -lc $bashCommand 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0)
        { throw "ServerConsole failed ($exitCode): $($output -join "`n")" }
    $result = @($output | ForEach-Object {[string]$_} | Where-Object {
        $_ -match '^(?:action|error):?=' -or $_ -match '^usage:' } |
        Select-Object -Last 1)
    if ($result.Count -ne 1)
        { throw "No fixture result for '$arguments': $($output -join "`n")" }
    if ($result[0] -match '^(?:error|usage)')
        { throw "Fixture rejected '$arguments': $($result[0])" }
    [string]$result[0]
}
function Get-Field([string]$Text, [string]$Name)
{
    $matches = [regex]::Matches($Text,
        "(?:^| )$([regex]::Escape($Name))=(?<value>[^ ]+)")
    if ($matches.Count -eq 0) { throw "Field '$Name' is absent: $Text" }
    $matches[$matches.Count - 1].Groups["value"].Value
}
function Invoke-ClientAction([string]$Action, [int]$SelectionIndex = -1)
{
    $arguments = @{
        Action = $Action
        ClientProcessId = $ClientProcessId
    }
    if ($SelectionIndex -ge 0) { $arguments.SelectionIndex = $SelectionIndex }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do
    {
        try { & $bridge @arguments | Write-Host; return }
        catch { $lastError = $_; Start-Sleep -Milliseconds 500 }
    }
    while ([DateTime]::UtcNow -lt $deadline)
    throw "Client action '$Action' was not delivered: $lastError"
}
function Wait-Field([string]$Lifecycle, [string]$Field, [string]$Value,
    [int]$TimeoutSeconds = 12)
{
    $status = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do
    {
        Start-Sleep -Milliseconds 250
        $status = Invoke-Fixture "status" $Lifecycle
    }
    while ((Get-Field $status $Field) -cne $Value -and
        [DateTime]::UtcNow -lt $deadline)
    $status
}

$lifecycle = [guid]::NewGuid().ToString("N")
$armed = $false
try
{
    $loaded = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    do
    {
        try { $prepared = Invoke-Fixture "prepare" $lifecycle; $loaded = $true }
        catch
        {
            if ($_.Exception.Message -notmatch 'error=playerUnavailable') { throw }
            Start-Sleep -Seconds 1
        }
    }
    while (-not $loaded -and [DateTime]::UtcNow -lt $deadline)
    if (-not $loaded) { throw "Proof avatar did not become authoritative." }
    $armed = $true
    if ((Get-Field $prepared "command") -cne "true" -or
        (Get-Field $prepared "directionTier") -cne "true" -or
        (Get-Field $prepared "npcTier") -cne "true" -or
        (Get-Field $prepared "distanceTier") -cne "true" -or
        (Get-Field $prepared "playerTier") -cne "true" -or
        (Get-Field $prepared "targetAvailable") -cne "true")
        { throw "Area Track fixture preparation failed: $prepared" }

    Invoke-ClientAction "Stand"
    Invoke-ClientAction "QueueAreaTrack"
    $options = Wait-Field $lifecycle "outcome" "optionsOpen"
    if ([int](Get-Field $options "handlerCalls") -ne 1 -or
        [int](Get-Field $options "optionCount") -ne 3 -or
        [int](Get-Field $options "optionPid") -le 0)
        { throw "Area Track production option SUI failed: $options" }

    Invoke-ClientAction "SelectAreaTrackType" 0
    $results = Wait-Field $lifecycle "outcome" "resultsOpen" 18
    $distance = [int](Get-Field $results "fixtureDistance")
    $started = [int](Get-Field $results "scanStartedAt")
    $completed = [int](Get-Field $results "scanCompletedAt")
    if ([int](Get-Field $results "selectedType") -ne 0 -or
        [int](Get-Field $results "resultCount") -lt 1 -or
        [int](Get-Field $results "fixtureTargetFound") -ne 1 -or
        (Get-Field $results "fixtureDirection") -cne "east" -or
        $distance -lt 9 -or $distance -gt 11 -or
        [int](Get-Field $results "resultsPid") -le 0 -or
        $completed - $started -lt 5)
        { throw "Area Track delayed production scan failed: $results" }

    $cleanup = Invoke-Fixture "cleanup" $lifecycle
    if ((Get-Field $cleanup "restored") -cne "true")
        { throw "Area Track cleanup failed: $cleanup" }
    $armed = $false
    $idempotent = Invoke-Fixture "cleanup" $lifecycle
    if ((Get-Field $idempotent "alreadyClean") -cne "true" -or
        (Get-Field $idempotent "restored") -cne "true")
        { throw "Area Track idempotent cleanup failed: $idempotent" }
    Write-Host "Publish 14.1 Area Track authenticated runtime passed."
    [pscustomobject]@{lifecycle=$lifecycle; clientProcessId=$ClientProcessId;
        preparation=$prepared; options=$options; results=$results;
        cleanup=$cleanup; idempotentCleanup=$idempotent; result="passed"}
}
finally
{
    if ($armed)
    {
        try { Invoke-Fixture "cleanup" $lifecycle | Write-Host }
        catch { Write-Warning "Best-effort Area Track cleanup failed: $_" }
    }
}
