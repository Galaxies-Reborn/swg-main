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

$fixtureScript = "test.precu_heal_mind_command_fixture"
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
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do
    {
        Start-Sleep -Milliseconds 500
        $prepared = Invoke-Fixture -Action status -Lifecycle $lifecycle
    }
    while ((Get-Field $prepared "outcome") -cne "ready" -and
        [DateTime]::UtcNow -lt $deadline)

    if ((Get-Field $prepared "outcome") -cne "ready" -or
        (Get-Field $prepared "command") -cne "true" -or
        (Get-Field $prepared "skillBits") -cne "111111" -or
        (Get-Field $prepared "petAvailable") -cne "true" -or
        (Get-Field $prepared "pcdAvailable") -cne "true" -or
        (Get-Field $prepared "pcdContained") -cne "true" -or
        (Get-Field $prepared "masterLinked") -cne "true" -or
        (Get-Field $prepared "creaturePet") -cne "true" -or
        [int](Get-Field $prepared "effectiveness") -ne 5)
    {
        throw "Heal-mind fixture preparation is not authoritative: $prepared"
    }

    $petOid = [long](Get-Field $prepared "pet")
    & $bridge -Action QueueHealMind -TargetOid $petOid `
        -ClientProcessId $ClientProcessId |
        Write-Host

    $status = ""
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do
    {
        Start-Sleep -Milliseconds 500
        $status = Invoke-Fixture -Action status -Lifecycle $lifecycle
    }
    while ((Get-Field $status "outcome") -cne "passed" -and
        [DateTime]::UtcNow -lt $deadline)

    $expectedPower = 40
    $expectedWoundCost = 2
    $passed =
        (Get-Field $status "outcome") -ceq "passed" -and
        (Get-Field $status "handlerEntered") -ceq "1" -and
        (Get-Field $status "handlerCalls") -ceq "1" -and
        [int](Get-Field $status "randomRoll") -eq 0 -and
        [int](Get-Field $status "rawPower") -eq $expectedPower -and
        [int](Get-Field $status "healPower") -eq $expectedPower -and
        [int](Get-Field $status "healedMind") -eq $expectedPower -and
        [int](Get-Field $status "targetMindAfter") -
            [int](Get-Field $status "targetMindBefore") -eq $expectedPower -and
        [int](Get-Field $status "petMindDelta") -ge $expectedPower -and
        [int](Get-Field $status "woundCost") -eq $expectedWoundCost -and
        [int](Get-Field $status "healerMindBefore") -
            [int](Get-Field $status "healerMindAfterWounds") -eq
                $expectedWoundCost -and
        [int](Get-Field $status "playerMindDelta") -eq -$expectedWoundCost -and
        [int](Get-Field $status "mindWoundDelta") -eq $expectedWoundCost -and
        [int](Get-Field $status "focusWoundDelta") -eq $expectedWoundCost -and
        [int](Get-Field $status "willpowerWoundDelta") -eq $expectedWoundCost -and
        [int](Get-Field $status "battleFatigueDelta") -eq $expectedWoundCost
    if (-not $passed)
    {
        throw "Heal-mind runtime proof failed: $status"
    }

    $cleanup = Invoke-Fixture -Action cleanup -Lifecycle $lifecycle
    if ((Get-Field $cleanup "restored") -cne "true")
    {
        throw "Heal-mind cleanup failed: $cleanup"
    }
    $armed = $false
    $idempotent = Invoke-Fixture -Action cleanup -Lifecycle $lifecycle
    if ((Get-Field $idempotent "alreadyClean") -cne "true" -or
        (Get-Field $idempotent "restored") -cne "true")
    {
        throw "Heal-mind idempotent cleanup failed: $idempotent"
    }

    Write-Host "Publish 14.1 healMind authenticated runtime passed."
    [pscustomobject]@{
        lifecycle = $lifecycle
        clientProcessId = $ClientProcessId
        petOid = [long](Get-Field $status "pet")
        pcdOid = [long](Get-Field $status "pcd")
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
            Write-Warning "Best-effort healMind cleanup failed: $_"
        }
    }
}
