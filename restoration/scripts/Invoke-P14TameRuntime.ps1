[CmdletBinding()]
param(
    [ValidateSet("Full", "PrepareStore", "VerifyRecall", "Cleanup")]
    [string]$Mode = "Full",

    [ValidatePattern("^[0-9]+$")]
    [string]$PlayerOid = "44003778",

    [ValidateRange(1, [int]::MaxValue)]
    [int]$ClientProcessId,

    [ValidatePattern("^[A-Za-z0-9_.-]+$")]
    [string]$ContainerName = "swg-precu",

    [ValidatePattern("^[a-f0-9]{32}$")]
    [string]$Lifecycle,

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

$fixtureScript = "test.precu_tame_command_fixture"
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
        [ValidateSet("prepare", "status", "store", "call", "cleanup")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[a-f0-9]{32}$")]
        [string]$FixtureLifecycle
    )

    $arguments = "$Action $PlayerOid $FixtureLifecycle"
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

function Wait-ForStatus
{
    param(
        [Parameter(Mandatory = $true)][string]$FixtureLifecycle,
        [Parameter(Mandatory = $true)][scriptblock]$Ready,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $status = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do
    {
        Start-Sleep -Milliseconds 500
        $status = Invoke-Fixture -Action status `
            -FixtureLifecycle $FixtureLifecycle
    }
    while (-not (& $Ready $status) -and [DateTime]::UtcNow -lt $deadline)
    return $status
}

function Assert-Prepared
{
    param([Parameter(Mandatory = $true)][string]$Status)
    if ((Get-Field $Status "command") -cne "true" -or
        (Get-Field $Status "skillBits") -cne "11" -or
        [int](Get-Field $Status "tameLevel") -ne 12 -or
        [int](Get-Field $Status "tameNonAggro") -ne 5 -or
        (Get-Field $Status "targetAvailable") -cne "true" -or
        [int](Get-Field $Status "targetLevel") -ne 6)
    {
        throw "Tame fixture preparation is not authoritative: $Status"
    }
}

function Assert-Tamed
{
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [ValidateSet("true", "false")]
        [string]$ExpectedPetPersisted = "true"
    )
    $xpDelta = [int](Get-Field $Status "xpDelta")
    $xpGranted = [int](Get-Field $Status "xpGranted")
    $passed =
        (Get-Field $Status "outcome") -ceq "passed" -and
        (Get-Field $Status "handlerEntered") -ceq "1" -and
        (Get-Field $Status "handlerCalls") -ceq "1" -and
        (Get-Field $Status "phaseCallbacks") -ceq "3" -and
        [int](Get-Field $Status "chance") -gt 0 -and
        (Get-Field $Status "roll") -ceq "0" -and
        (Get-Field $Status "pcdAvailable") -ceq "true" -and
        (Get-Field $Status "pcdContained") -ceq "true" -and
        (Get-Field $Status "pcdCreatureName") -ceq "worrt" -and
        (Get-Field $Status "pcdScript") -ceq "true" -and
        (Get-Field $Status "growthStage") -ceq "1" -and
        (Get-Field $Status "petAvailable") -ceq "true" -and
        (Get-Field $Status "masterLinked") -ceq "true" -and
        (Get-Field $Status "petScript") -ceq "true" -and
        (Get-Field $Status "babyScript") -ceq "false" -and
        (Get-Field $Status "petPersisted") -ceq $ExpectedPetPersisted -and
        (Get-Field $Status "storeError") -ceq "0" -and
        (Get-Field $Status "callError") -ceq "0" -and
        $xpGranted -eq 120 -and
        $xpDelta -eq $xpGranted
    if (-not $passed)
    {
        throw "Tame command runtime proof failed: $Status"
    }
}

function Assert-Stored
{
    param([Parameter(Mandatory = $true)][string]$Status)
    if ((Get-Field $Status "pcdAvailable") -cne "true" -or
        (Get-Field $Status "pcdContained") -cne "true" -or
        (Get-Field $Status "pcdStored") -cne "true" -or
        (Get-Field $Status "pcdCreatureName") -cne "worrt" -or
        (Get-Field $Status "pcdScript") -cne "true" -or
        (Get-Field $Status "growthStage") -cne "1" -or
        (Get-Field $Status "petAvailable") -cne "false" -or
        [int](Get-Field $Status "storedCount") -ne 1 -or
        [int](Get-Field $Status "xpDelta") -ne 120)
    {
        throw "Tame PCD storage/persistence proof failed: $Status"
    }
}

function Invoke-Cleanup
{
    param([Parameter(Mandatory = $true)][string]$FixtureLifecycle)
    $cleanup = Invoke-Fixture -Action cleanup `
        -FixtureLifecycle $FixtureLifecycle
    if ((Get-Field $cleanup "restored") -cne "true")
    {
        throw "Tame cleanup failed: $cleanup"
    }
    $idempotent = Invoke-Fixture -Action cleanup `
        -FixtureLifecycle $FixtureLifecycle
    if ((Get-Field $idempotent "alreadyClean") -cne "true" -or
        (Get-Field $idempotent "restored") -cne "true")
    {
        throw "Tame idempotent cleanup failed: $idempotent"
    }
    return @($cleanup, $idempotent)
}

if ($Mode -ne "PrepareStore" -and $Mode -ne "Full" -and
    [string]::IsNullOrWhiteSpace($Lifecycle))
{
    throw "Mode $Mode requires -Lifecycle."
}
if ([string]::IsNullOrWhiteSpace($Lifecycle))
{
    $Lifecycle = [guid]::NewGuid().ToString("N")
}

if ($Mode -eq "Cleanup")
{
    $cleanupResults = Invoke-Cleanup -FixtureLifecycle $Lifecycle
    [pscustomobject]@{
        mode = $Mode
        lifecycle = $Lifecycle
        cleanup = $cleanupResults[0]
        idempotentCleanup = $cleanupResults[1]
        result = "passed"
    }
    return
}

if ($Mode -eq "VerifyRecall")
{
    $persisted = Invoke-Fixture -Action status -FixtureLifecycle $Lifecycle
    Assert-Stored -Status $persisted
    Invoke-Fixture -Action call -FixtureLifecycle $Lifecycle | Write-Host
    $recalled = Wait-ForStatus -FixtureLifecycle $Lifecycle -TimeoutSeconds 15 `
        -Ready { param($text) (Get-Field $text "petAvailable") -ceq "true" }
    Assert-Tamed -Status $recalled -ExpectedPetPersisted "false"
    $cleanupResults = Invoke-Cleanup -FixtureLifecycle $Lifecycle
    Write-Host "Publish 14.1 tame restart persistence and recall passed."
    [pscustomobject]@{
        mode = $Mode
        lifecycle = $Lifecycle
        persisted = $persisted
        recalled = $recalled
        cleanup = $cleanupResults[0]
        idempotentCleanup = $cleanupResults[1]
        result = "passed"
    }
    return
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

$armed = $false
try
{
    $prepared = Invoke-Fixture -Action prepare -FixtureLifecycle $Lifecycle
    $armed = $true
    Assert-Prepared -Status $prepared
    $targetOid = [long](Get-Field $prepared "target")

    & $bridge -Action QueueTame -TargetOid $targetOid `
        -ClientProcessId $ClientProcessId | Write-Host

    $tamed = Wait-ForStatus -FixtureLifecycle $Lifecycle -TimeoutSeconds 45 `
        -Ready { param($text) (Get-Field $text "outcome") -ceq "passed" }
    Assert-Tamed -Status $tamed
    $pcdOid = [long](Get-Field $tamed "pcd")

    Invoke-Fixture -Action store -FixtureLifecycle $Lifecycle | Write-Host
    $stored = Wait-ForStatus -FixtureLifecycle $Lifecycle -TimeoutSeconds 15 `
        -Ready { param($text) (Get-Field $text "petAvailable") -ceq "false" }
    Assert-Stored -Status $stored

    if ($Mode -eq "PrepareStore")
    {
        $armed = $false
        Write-Host "Publish 14.1 tame command and PCD storage passed; fixture remains armed for a real restart."
        [pscustomobject]@{
            mode = $Mode
            lifecycle = $Lifecycle
            clientProcessId = $ClientProcessId
            targetOid = $targetOid
            pcdOid = $pcdOid
            preparation = $prepared
            tamed = $tamed
            stored = $stored
            result = "passed"
        }
        return
    }

    Invoke-Fixture -Action call -FixtureLifecycle $Lifecycle | Write-Host
    $recalled = Wait-ForStatus -FixtureLifecycle $Lifecycle -TimeoutSeconds 15 `
        -Ready { param($text) (Get-Field $text "petAvailable") -ceq "true" }
    Assert-Tamed -Status $recalled -ExpectedPetPersisted "false"
    $cleanupResults = Invoke-Cleanup -FixtureLifecycle $Lifecycle
    $armed = $false
    Write-Host "Publish 14.1 tame authenticated runtime passed."
    [pscustomobject]@{
        mode = $Mode
        lifecycle = $Lifecycle
        clientProcessId = $ClientProcessId
        targetOid = $targetOid
        pcdOid = $pcdOid
        preparation = $prepared
        tamed = $tamed
        stored = $stored
        recalled = $recalled
        cleanup = $cleanupResults[0]
        idempotentCleanup = $cleanupResults[1]
        result = "passed"
    }
}
finally
{
    if ($armed)
    {
        try
        {
            Invoke-Fixture -Action cleanup `
                -FixtureLifecycle $Lifecycle | Write-Host
        }
        catch
        {
            Write-Warning "Best-effort tame cleanup failed: $_"
        }
    }
}
