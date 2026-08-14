[CmdletBinding()]
param(
    [ValidatePattern("^[0-9]+$")]
    [string]$PlayerOid = "44003778",

    [ValidateRange(1, [int]::MaxValue)]
    [int]$ClientProcessId,

    [ValidatePattern("^[A-Za-z0-9_.-]+$")]
    [string]$ContainerName = "swg-precu",

    [string]$ToolsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ToolsRoot))
{
    $sourceRoot = Split-Path -Parent (
        Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot
        )
    )
    $ToolsRoot = Join-Path $sourceRoot "pre-cu-reborn-tools"
}

$fixtureScript = "test.precu_sample_dna_command_fixture"
$fixtureMethod = "executeFixture"
$bridge = Join-Path $ToolsRoot "scripts/Invoke-PrecuBackgroundInput.ps1"
if (-not (Test-Path -LiteralPath $bridge -PathType Leaf))
{
    throw "Background-input helper not found: $bridge"
}

function Invoke-Fixture
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("prepare", "status", "cleanup")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[a-f0-9]{32}$")]
        [string]$Lifecycle
    )

    $arguments = "$Action $PlayerOid $Lifecycle"
    $serverCommand =
        "game tatooine runScript $fixtureScript $fixtureMethod $arguments"
    $bashCommand =
        "cd /swg-precu/exe/linux && printf '%-1023s\0' '$serverCommand' | " +
        "./bin/ServerConsole -- @servercommon.cfg -s ServerConsole " +
        "serverAddress=127.0.0.1 serverPort=61000"
    $previous = $ErrorActionPreference
    try
    {
        $ErrorActionPreference = "Continue"
        $output = @(& docker exec $ContainerName bash -lc $bashCommand 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $previous
    }
    if ($exitCode -ne 0)
    {
        throw "ServerConsole failed ($exitCode): $($output -join [Environment]::NewLine)"
    }
    $result = @($output | ForEach-Object { [string]$_ } |
        Where-Object {
            $_ -match '^(?:action|error):?=' -or $_ -match '^usage:'
        } | Select-Object -Last 1)
    if ($result.Count -ne 1)
    {
        throw "No fixture result for '$arguments': $($output -join [Environment]::NewLine)"
    }
    if ($result[0] -match '^(?:error|usage)')
    {
        throw "Fixture rejected '$arguments': $($result[0])"
    }
    return [string]$result[0]
}

function Get-Field
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $match = [regex]::Match($Text, "(?:^| )$([regex]::Escape($Name))=([^ ]+)")
    if (-not $match.Success)
    {
        throw "Field '$Name' is absent: $Text"
    }
    return $match.Groups[1].Value
}

if (-not $PSBoundParameters.ContainsKey("ClientProcessId"))
{
    $clients = @(Get-Process SwgClient_r -ErrorAction SilentlyContinue)
    if ($clients.Count -ne 1)
    {
        throw "Specify -ClientProcessId when exactly one SwgClient_r process is not running."
    }
    $ClientProcessId = $clients[0].Id
}

$lifecycle = [guid]::NewGuid().ToString("N")
$armed = $false
try
{
    $prepared = Invoke-Fixture -Action prepare -Lifecycle $lifecycle
    $armed = $true
    if ((Get-Field $prepared "command") -cne "true" -or
        (Get-Field $prepared "skillBits") -cne "111" -or
        [int](Get-Field $prepared "dnaHarvesting") -lt 30)
    {
        throw "Fixture preparation is not authoritative: $prepared"
    }
    $targetOid = [long](Get-Field $prepared "target")

    & $bridge -Action QueueSampleDNA -TargetOid $targetOid -ClientProcessId $ClientProcessId | Write-Host

    $status = ""
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do
    {
        Start-Sleep -Milliseconds 500
        $status = Invoke-Fixture -Action status -Lifecycle $lifecycle
    }
    while (((Get-Field $status "outcome") -cne "passed" -or
        [int](Get-Field $status "xpDelta") -ne
            [int](Get-Field $status "xpGranted")) -and
        [DateTime]::UtcNow -lt $deadline)

    $xpDelta = [int](Get-Field $status "xpDelta")
    $xpGranted = [int](Get-Field $status "xpGranted")
    $passed =
        (Get-Field $status "outcome") -ceq "passed" -and
        (Get-Field $status "handlerEntered") -ceq "1" -and
        (Get-Field $status "handlerCalls") -ceq "1" -and
        (Get-Field $status "skillRoll") -ceq "1" -and
        (Get-Field $status "survivalRoll") -ceq "1" -and
        (Get-Field $status "behaviorRoll") -ceq "100" -and
        (Get-Field $status "actionCost") -ceq "100" -and
        (Get-Field $status "mindCost") -ceq "250" -and
        (Get-Field $status "dnaAvailable") -ceq "true" -and
        (Get-Field $status "targetAvailable") -ceq "true" -and
        (Get-Field $status "targetDead") -ceq "false" -and
        (Get-Field $status "creatureSurvived") -ceq "1" -and
        (Get-Field $status "harvesting") -ceq "false" -and
        $xpGranted -gt 0 -and
        $xpDelta -eq $xpGranted
    if (-not $passed)
    {
        throw "sampleDNA runtime proof failed: $status"
    }

    $cleanup = Invoke-Fixture -Action cleanup -Lifecycle $lifecycle
    if ((Get-Field $cleanup "restored") -cne "true")
    {
        throw "sampleDNA cleanup failed: $cleanup"
    }
    $armed = $false
    $idempotent = Invoke-Fixture -Action cleanup -Lifecycle $lifecycle
    if ((Get-Field $idempotent "alreadyClean") -cne "true" -or
        (Get-Field $idempotent "restored") -cne "true")
    {
        throw "sampleDNA idempotent cleanup failed: $idempotent"
    }

    Write-Host "Publish 14.1 sampleDNA authenticated runtime passed."
    [pscustomobject]@{
        lifecycle = $lifecycle
        clientProcessId = $ClientProcessId
        targetOid = $targetOid
        preparation = $prepared
        status = $status
        cleanup = $cleanup
        idempotentCleanup = $idempotent
        result = "passed"
    }
}
finally
{
    if ($armed)
    {
        try
        {
            Invoke-Fixture -Action cleanup -Lifecycle $lifecycle | Write-Host
        }
        catch
        {
            Write-Warning "Best-effort sampleDNA cleanup failed: $_"
        }
    }
}
