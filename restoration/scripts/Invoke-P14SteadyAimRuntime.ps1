[CmdletBinding()]
param(
    [ValidatePattern("^[0-9]+$")]
    [string]$LeaderOid = "44003778",

    [ValidatePattern("^[0-9]+$")]
    [string]$MemberOid = "207005062",

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$LeaderClientProcessId,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MemberClientProcessId,

    [ValidatePattern("^[A-Za-z0-9_.-]+$")]
    [string]$ContainerName = "swg-precu",

    [string]$ToolsRoot,

    [string]$ClientRoot,

    [string]$LeaderClientRoot,

    [string]$MemberClientRoot
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
if (-not [string]::IsNullOrWhiteSpace($ClientRoot))
{
    if ([string]::IsNullOrWhiteSpace($LeaderClientRoot))
    {
        $LeaderClientRoot = $ClientRoot
    }
    if ([string]::IsNullOrWhiteSpace($MemberClientRoot))
    {
        $MemberClientRoot = $ClientRoot
    }
}
if ([string]::IsNullOrWhiteSpace($LeaderClientRoot))
{
    $workspaceRoot = Split-Path -Parent (
        Split-Path -Parent $ToolsRoot
    )
    $LeaderClientRoot = Join-Path $workspaceRoot "PreCU-Client"
}
if ([string]::IsNullOrWhiteSpace($MemberClientRoot))
{
    $MemberClientRoot = $LeaderClientRoot
}

$fixtureScript = "test.precu_steady_aim_command_fixture"
$fixtureMethod = "executeFixture"
$bridge = Join-Path $ToolsRoot "scripts/Invoke-PrecuBackgroundInput.ps1"
$expectedLeaderClient = (Resolve-Path -LiteralPath (
    Join-Path $LeaderClientRoot "SwgClient_r.exe")).Path
$expectedMemberClient = (Resolve-Path -LiteralPath (
    Join-Path $MemberClientRoot "SwgClient_r.exe")).Path
if (-not (Test-Path -LiteralPath $bridge -PathType Leaf))
{
    throw "Background-input helper not found: $bridge"
}
if ($LeaderClientProcessId -eq $MemberClientProcessId)
{
    throw "Leader and member must use distinct client processes."
}
foreach ($client in @(
    [pscustomobject]@{
        ProcessId = $LeaderClientProcessId
        ExpectedPath = $expectedLeaderClient
    },
    [pscustomobject]@{
        ProcessId = $MemberClientProcessId
        ExpectedPath = $expectedMemberClient
    }))
{
    $processId = [int]$client.ProcessId
    $expectedClient = [string]$client.ExpectedPath
    $process = Get-Process -Id $processId -ErrorAction Stop
    if ([string]$process.Path -cne $expectedClient)
    {
        throw "Process $processId is not the isolated proof client: $($process.Path)"
    }
}

function Invoke-Fixture
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("recover", "prepare", "observeGrouped", "observeCommand",
            "observeUngrouped", "status", "cleanup")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[a-f0-9]{32}$")]
        [string]$Lifecycle
    )

    $arguments = "$Action $LeaderOid $MemberOid $Lifecycle"
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
    $pattern = "(?:^| )$([regex]::Escape($Name))=(?<value>[^ ]+)"
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -eq 0)
    {
        throw "Field '$Name' is absent: $Text"
    }
    return $matches[$matches.Count - 1].Groups["value"].Value
}

function Invoke-ClientAction
{
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][int]$ProcessId
    )
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do
    {
        try
        {
            & $bridge -Action $Action -ClientProcessId $ProcessId | Write-Host
            return
        }
        catch
        {
            $lastError = $_
            Start-Sleep -Milliseconds 500
        }
    }
    while ([DateTime]::UtcNow -lt $deadline)
    throw "Client action '$Action' was not delivered to process ${ProcessId}: $lastError"
}

function Wait-FixtureField
{
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$Lifecycle,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][string]$Value,
        [int]$TimeoutSeconds = 10
    )
    $observed = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do
    {
        Start-Sleep -Milliseconds 250
        $observed = [string](Invoke-Fixture -Action $Action -Lifecycle $Lifecycle)
    }
    while ((Get-Field $observed $Field) -cne $Value -and
        [DateTime]::UtcNow -lt $deadline)
    return $observed
}

$lifecycle = [guid]::NewGuid().ToString("N")
$armed = $false
$grouped = $false
try
{
    $recovery = ""
    $loadDeadline = [DateTime]::UtcNow.AddSeconds(90)
    do
    {
        try
        {
            $recovery = [string](
                Invoke-Fixture -Action recover -Lifecycle $lifecycle)
        }
        catch
        {
            if ($_.Exception.Message -match
                'error=recoveryRequiresUngroupedPlayers')
            {
                Invoke-ClientAction -Action DisbandGroup `
                    -ProcessId $LeaderClientProcessId
                Start-Sleep -Seconds 1
            }
            elseif ($_.Exception.Message -notmatch
                'error=(?:leader|member)NotLoaded')
            {
                throw
            }
            else
            {
                Start-Sleep -Seconds 1
            }
        }
    }
    while ([string]::IsNullOrWhiteSpace($recovery) -and
        [DateTime]::UtcNow -lt $loadDeadline)
    if ([string]::IsNullOrWhiteSpace($recovery))
    {
        throw "Both proof avatars did not become authoritative within 90 seconds."
    }
    if ((Get-Field $recovery "restored") -cne "true")
    {
        throw "Steady Aim preflight recovery failed: $recovery"
    }

    $prepared = [string](Invoke-Fixture -Action prepare -Lifecycle $lifecycle)
    $armed = $true
    if ((Get-Field $prepared "grouped") -cne "false" -or
        (Get-Field $prepared "steadyAimSkill") -cne "true" -or
        (Get-Field $prepared "steadyAimCommand") -cne "true" -or
        [int](Get-Field $prepared "leaderWounds") -ne 45 -or
        [int](Get-Field $prepared "memberWounds") -ne 46 -or
        [int](Get-Field $prepared "leaderHealth") -ne 500 -or
        [int](Get-Field $prepared "leaderAction") -ne 500 -or
        [int](Get-Field $prepared "leaderMind") -ne 500)
    {
        throw "Steady Aim fixture preparation is not authoritative: $prepared"
    }
    $leaderHealthBefore = [int](Get-Field $prepared "leaderHealth")
    $leaderActionBefore = [int](Get-Field $prepared "leaderAction")
    $leaderMindBefore = [int](Get-Field $prepared "leaderMind")
    $memberHealthBefore = [int](Get-Field $prepared "memberHealth")
    $memberActionBefore = [int](Get-Field $prepared "memberAction")
    $memberMindBefore = [int](Get-Field $prepared "memberMind")
    $leaderPrivateAimBefore = [int](Get-Field $prepared "leaderPrivateAim")
    $memberPrivateAimBefore = [int](Get-Field $prepared "memberPrivateAim")
    Invoke-ClientAction -Action Stand -ProcessId $LeaderClientProcessId
    Invoke-ClientAction -Action Stand -ProcessId $MemberClientProcessId
    $postureProof = ""
    $postureDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do
    {
        Start-Sleep -Milliseconds 250
        $postureProof = [string](
            Invoke-Fixture -Action status -Lifecycle $lifecycle)
    }
    while (((Get-Field $postureProof "leaderPosture") -cne "0" -or
        (Get-Field $postureProof "memberPosture") -cne "0") -and
        [DateTime]::UtcNow -lt $postureDeadline)
    if ((Get-Field $postureProof "leaderPosture") -cne "0" -or
        (Get-Field $postureProof "memberPosture") -cne "0")
    {
        throw "Real-client upright posture proof failed: $postureProof"
    }

    Start-Sleep -Seconds 5
    $groupProof = ""
    for ($attempt = 1; $attempt -le 3; ++$attempt)
    {
        Invoke-ClientAction -Action TargetSquadCounterpart `
            -ProcessId $LeaderClientProcessId
        Start-Sleep -Seconds 1
        Invoke-ClientAction -Action InviteTarget `
            -ProcessId $LeaderClientProcessId
        Start-Sleep -Seconds 2
        Invoke-ClientAction -Action JoinGroup `
            -ProcessId $MemberClientProcessId
        $groupProof = Wait-FixtureField -Action observeGrouped `
            -Lifecycle $lifecycle -Field passed -Value true `
            -TimeoutSeconds 5
        if ((Get-Field $groupProof "passed") -ceq "true")
        {
            break
        }
    }
    if ((Get-Field $groupProof "passed") -cne "true" -or
        (Get-Field $groupProof "leaderOwnsGroup") -cne "true" -or
        [int](Get-Field $groupProof "groupSize") -ne 2)
    {
        throw "Real-client group formation proof failed: $groupProof"
    }
    $grouped = $true

    Invoke-ClientAction -Action QueueSteadyAim -ProcessId $LeaderClientProcessId
    $commandProof = Wait-FixtureField -Action observeCommand `
        -Lifecycle $lifecycle -Field passed -Value true
    $expectedHealthCost = 46
    $expectedActionCost = 110
    $expectedMindCost = 129
    if ((Get-Field $commandProof "outcome") -cne "passed" -or
        [int](Get-Field $commandProof "handlerCalls") -ne 1 -or
        [int](Get-Field $commandProof "adjustedBaseCost") -ne 110 -or
        [int](Get-Field $commandProof "healthCost") -ne $expectedHealthCost -or
        [int](Get-Field $commandProof "actionCost") -ne $expectedActionCost -or
        [int](Get-Field $commandProof "mindCost") -ne $expectedMindCost -or
        [int](Get-Field $commandProof "skillMod") -ne 0 -or
        [int](Get-Field $commandProof "amount") -ne 5 -or
        [int](Get-Field $commandProof "membersApplied") -ne 2 -or
        [int](Get-Field $commandProof "leaderWounds") -ne 45 -or
        [int](Get-Field $commandProof "memberWounds") -ne 46 -or
        [int](Get-Field $commandProof "leaderPrivateAim") -ne
            ($leaderPrivateAimBefore + 5) -or
        [int](Get-Field $commandProof "memberPrivateAim") -ne
            ($memberPrivateAimBefore + 5) -or
        [int](Get-Field $commandProof "leaderHealth") -ne
            ($leaderHealthBefore - $expectedHealthCost) -or
        [int](Get-Field $commandProof "leaderAction") -ne
            ($leaderActionBefore - $expectedActionCost) -or
        [int](Get-Field $commandProof "leaderMind") -ne
            ($leaderMindBefore - $expectedMindCost) -or
        [int](Get-Field $commandProof "memberHealth") -ne $memberHealthBefore -or
        [int](Get-Field $commandProof "memberAction") -ne $memberActionBefore -or
        [int](Get-Field $commandProof "memberMind") -ne $memberMindBefore)
    {
        throw "Steady Aim production command proof failed: $commandProof"
    }

    Invoke-ClientAction -Action DisbandGroup -ProcessId $LeaderClientProcessId
    $ungroupProof = Wait-FixtureField -Action observeUngrouped `
        -Lifecycle $lifecycle -Field passed -Value true
    if ((Get-Field $ungroupProof "passed") -cne "true" -or
        (Get-Field $ungroupProof "grouped") -cne "false")
    {
        throw "Real-client group dissolution proof failed: $ungroupProof"
    }
    $grouped = $false

    $cleanup = [string](Invoke-Fixture -Action cleanup -Lifecycle $lifecycle)
    if ((Get-Field $cleanup "restored") -cne "true")
    {
        throw "Steady Aim cleanup failed: $cleanup"
    }
    $armed = $false
    $idempotent = [string](Invoke-Fixture -Action cleanup -Lifecycle $lifecycle)
    if ((Get-Field $idempotent "alreadyClean") -cne "true" -or
        (Get-Field $idempotent "restored") -cne "true")
    {
        throw "Steady Aim idempotent cleanup failed: $idempotent"
    }

    Write-Host "Publish 14.1 steadyaim authenticated two-client runtime passed."
    [pscustomobject]@{
        lifecycle = $lifecycle
        leaderClientProcessId = $LeaderClientProcessId
        memberClientProcessId = $MemberClientProcessId
        preparation = $prepared
        preflightRecovery = $recovery
        posture = $postureProof
        groupFormation = $groupProof
        command = $commandProof
        groupDissolution = $ungroupProof
        cleanup = $cleanup
        idempotentCleanup = $idempotent
        result = "passed"
    }
}
finally
{
    if ($armed)
    {
        if ($grouped)
        {
            try
            {
                Invoke-ClientAction -Action DisbandGroup `
                    -ProcessId $LeaderClientProcessId
                Start-Sleep -Seconds 1
            }
            catch
            {
                Write-Warning "Best-effort real-client disband failed: $_"
            }
        }
        try
        {
            Invoke-Fixture -Action cleanup -Lifecycle $lifecycle | Write-Host
        }
        catch
        {
            Write-Warning "Best-effort steadyaim cleanup failed: $_"
        }
    }
}
