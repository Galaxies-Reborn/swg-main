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

$fixtureScript = "test.precu_berserk_two_command_fixture"
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
        "cd /swg-precu/exe/linux && printf '%-1024s' '$serverCommand' | " +
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
    $pattern = "(?:^| )$([regex]::Escape($Name))=(?<value>[^ ]+)"
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -eq 0)
    {
        throw "Field '$Name' is absent: $Text"
    }
    return $matches[$matches.Count - 1].Groups["value"].Value
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
    $prepared = [string](Invoke-Fixture -Action prepare -Lifecycle $lifecycle)
    $armed = $true
    if ((Get-Field $prepared "outcome") -cne "ready" -or
        (Get-Field $prepared "command") -cne "true" -or
        (Get-Field $prepared "skillBits") -cne "1111111111111111111" -or
        [int](Get-Field $prepared "berserkModifier") -ne 20 -or
        [int](Get-Field $prepared "health") -lt 500 -or
        [int](Get-Field $prepared "action") -lt 500 -or
        [int](Get-Field $prepared "mind") -lt 500)
    {
        throw "Berserk-two fixture preparation is not authoritative: $prepared"
    }

    & $bridge -Action QueueBerserk2 -ClientProcessId $ClientProcessId |
        Write-Host

    $activated = ""
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do
    {
        Start-Sleep -Milliseconds 250
        $activated = [string](Invoke-Fixture -Action status -Lifecycle $lifecycle)
    }
    while ((Get-Field $activated "outcome") -cne "passed" -and
        [DateTime]::UtcNow -lt $deadline)

    $remaining = [int](Get-Field $activated "remaining")
    $expectedHealthCost = [int][math]::Floor(
        100 - (([int](Get-Field $prepared "strength") - 300) / 1200.0) * 100)
    $expectedActionCost = [int][math]::Floor(
        100 - (([int](Get-Field $prepared "quickness") - 300) / 1200.0) * 100)
    $expectedMindCost = [int][math]::Floor(
        50 - (([int](Get-Field $prepared "focus") - 300) / 1200.0) * 50)
    $expectedHealthCost = [math]::Max(0, $expectedHealthCost)
    $expectedActionCost = [math]::Max(0, $expectedActionCost)
    $expectedMindCost = [math]::Max(0, $expectedMindCost)
    $activationPassed =
        (Get-Field $activated "outcome") -ceq "passed" -and
        (Get-Field $activated "handlerEntered") -ceq "1" -and
        (Get-Field $activated "handlerCalls") -ceq "1" -and
        [int](Get-Field $activated "randomRoll") -eq 5 -and
        [int](Get-Field $activated "berserkModifier") -eq 20 -and
        [int](Get-Field $activated "chanceTotal") -eq 25 -and
        [int](Get-Field $activated "healthCost") -eq $expectedHealthCost -and
        [int](Get-Field $activated "actionCost") -eq $expectedActionCost -and
        [int](Get-Field $activated "mindCost") -eq $expectedMindCost -and
        [int](Get-Field $activated "healthBefore") -
            [int](Get-Field $activated "healthAfter") -eq
                $expectedHealthCost -and
        [int](Get-Field $activated "actionBefore") -
            [int](Get-Field $activated "actionAfter") -eq
                $expectedActionCost -and
        [int](Get-Field $activated "mindBefore") -
            [int](Get-Field $activated "mindAfter") -eq $expectedMindCost -and
        [int](Get-Field $activated "berserkState") -eq 1 -and
        $remaining -ge 35 -and $remaining -le 40
    if (-not $activationPassed)
    {
        throw "Berserk-two activation proof failed: $activated"
    }

    $expired = $activated
    $deadline = [DateTime]::UtcNow.AddSeconds(50)
    do
    {
        Start-Sleep -Milliseconds 500
        $expired = [string](Invoke-Fixture -Action status -Lifecycle $lifecycle)
    }
    while ((Get-Field $expired "outcome") -cne "expired" -and
        [DateTime]::UtcNow -lt $deadline)
    if ((Get-Field $expired "outcome") -cne "expired" -or
        [int](Get-Field $expired "berserkState") -ne 0 -or
        [int](Get-Field $expired "expiresAt") -ne 0 -or
        [int](Get-Field $expired "expiredAt") -le 0)
    {
        throw "Berserk-two expiry proof failed: $expired"
    }

    $cleanup = [string](Invoke-Fixture -Action cleanup -Lifecycle $lifecycle)
    if ((Get-Field $cleanup "restored") -cne "true")
    {
        throw "Berserk-two cleanup failed: $cleanup"
    }
    $armed = $false
    $idempotent = [string](Invoke-Fixture -Action cleanup -Lifecycle $lifecycle)
    if ((Get-Field $idempotent "alreadyClean") -cne "true" -or
        (Get-Field $idempotent "restored") -cne "true")
    {
        throw "Berserk-two idempotent cleanup failed: $idempotent"
    }

    Write-Host "Publish 14.1 berserk2 authenticated runtime passed."
    [pscustomobject]@{
        lifecycle = $lifecycle
        clientProcessId = $ClientProcessId
        preparation = $prepared
        activation = $activated
        expiration = $expired
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
            Write-Warning "Best-effort berserk2 cleanup failed: $_"
        }
    }
}
