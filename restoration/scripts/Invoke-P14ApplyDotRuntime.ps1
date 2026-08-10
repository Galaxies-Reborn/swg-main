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
        "test.precu_apply_dot_command_fixture executeFixture $arguments"
    $bashCommand = "cd /swg-precu/exe/linux && printf '%-1023s\0' " +
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
function Invoke-ClientAction([string]$Action, [long]$TargetOid = 0)
{
    $arguments = @{
        Action = $Action
        ClientProcessId = $ClientProcessId
    }
    if ($TargetOid -gt 0) { $arguments.TargetOid = $TargetOid }
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
    if ((Get-Field $prepared "poisonCommand") -cne "true" -or
        (Get-Field $prepared "diseaseCommand") -cne "true" -or
        [int](Get-Field $prepared "poisonCharges") -ne 2 -or
        [int](Get-Field $prepared "diseaseCharges") -ne 2)
        { throw "Apply DOT fixture preparation failed: $prepared" }
    $target = [long](Get-Field $prepared "target")
    $expectedCost = [int](Get-Field $prepared "expectedMindCost")
    $expectedStrength = [int](Get-Field $prepared "expectedStrength")
    Invoke-ClientAction "Stand"
    Invoke-ClientAction "QueueApplyPoison" $target
    $poison = Wait-Field $lifecycle "poisonOutcome" "performed"
    if ([int](Get-Field $poison "poisonHandlerCalls") -ne 1 -or
        [int](Get-Field $poison "poisonCharges") -ne 1 -or
        [int](Get-Field $poison "poisonStrength") -ne $expectedStrength -or
        [int](Get-Field $poison "poisonMindCost") -ne $expectedCost -or
        [int](Get-Field $poison "poisonChargeCost") -ne 1)
        { throw "Apply Poison production proof failed: $poison" }
    Invoke-ClientAction "QueueApplyDisease" $target
    $disease = Wait-Field $lifecycle "diseaseOutcome" "performed"
    if ([int](Get-Field $disease "diseaseHandlerCalls") -ne 1 -or
        [int](Get-Field $disease "diseaseCharges") -ne 1 -or
        [int](Get-Field $disease "diseaseStrength") -ne $expectedStrength -or
        [int](Get-Field $disease "diseaseMindCost") -ne $expectedCost -or
        [int](Get-Field $disease "diseaseChargeCost") -ne 1)
        { throw "Apply Disease production proof failed: $disease" }
    $cleanup = Invoke-Fixture "cleanup" $lifecycle
    if ((Get-Field $cleanup "restored") -cne "true")
        { throw "Apply DOT cleanup failed: $cleanup" }
    $armed = $false
    $idempotent = Invoke-Fixture "cleanup" $lifecycle
    if ((Get-Field $idempotent "alreadyClean") -cne "true" -or
        (Get-Field $idempotent "restored") -cne "true")
        { throw "Apply DOT idempotent cleanup failed: $idempotent" }
    Write-Host "Publish 14.1 Apply Poison / Disease authenticated runtime passed."
    [pscustomobject]@{lifecycle=$lifecycle; clientProcessId=$ClientProcessId;
        preparation=$prepared; poison=$poison; disease=$disease;
        cleanup=$cleanup; idempotentCleanup=$idempotent; result="passed"}
}
finally
{
    if ($armed)
    {
        try { Invoke-Fixture "cleanup" $lifecycle | Write-Host }
        catch { Write-Warning "Best-effort Apply DOT cleanup failed: $_" }
    }
}
