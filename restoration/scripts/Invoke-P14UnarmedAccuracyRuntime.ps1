[CmdletBinding()]
param(
    [ValidatePattern("^[0-9]+$")][string]$PlayerOid = "44003778",
    [ValidateRange(1, [int]::MaxValue)][int]$ClientProcessId,
    [ValidatePattern("^[A-Za-z0-9_.-]+$")][string]$ContainerName = "swg-precu",
    [string]$ToolsRoot,
    [ValidatePattern("^[0-9a-fA-F]{32}$")][string]$Lifecycle
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ToolsRoot)) {
    $sourceRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $ToolsRoot = Join-Path $sourceRoot "pre-cu-reborn-tools"
}
$bridge = Join-Path $ToolsRoot "scripts/Invoke-PrecuBackgroundInput.ps1"
if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) { throw "Background-input helper not found: $bridge" }
function Invoke-Fixture([string]$Action) {
    $serverCommand = "game tatooine runScript test.precu_unarmed_accuracy_fixture executeFixture $Action $PlayerOid $Lifecycle"
    $bashCommand = "cd /swg-precu/exe/linux && printf '%-1023s\0' '$serverCommand' | ./bin/ServerConsole -- @servercommon.cfg -s ServerConsole serverAddress=127.0.0.1 serverPort=61000"
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& docker exec $ContainerName bash -lc $bashCommand 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) { throw "ServerConsole failed ($exitCode): $($output -join [Environment]::NewLine)" }
    $result = @($output | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^(?:action|error|usage)' } | Select-Object -Last 1)
    if ($result.Count -ne 1 -or $result[0] -match '^(?:error|usage)') { throw "Fixture rejected '$Action': $($output -join [Environment]::NewLine)" }
    [string]$result[0]
}
function Field([string]$Text, [string]$Name) {
    $matches = [regex]::Matches($Text, "(?:^| )$([regex]::Escape($Name))=(?<value>[^ ]+)")
    if ($matches.Count -eq 0) { throw "Field '$Name' is absent: $Text" }
    $matches[$matches.Count - 1].Groups['value'].Value
}
function Wait-Status([scriptblock]$Predicate, [int]$Seconds, [string]$Failure) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        Start-Sleep -Seconds 1
        $status = Invoke-Fixture status
        if (& $Predicate $status) { return $status }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "${Failure}: $status"
}
if (-not $PSBoundParameters.ContainsKey("ClientProcessId")) {
    $clients = @(Get-Process SwgClient_r -ErrorAction SilentlyContinue)
    if ($clients.Count -ne 1) { throw "Specify -ClientProcessId when exactly one SwgClient_r process is not running." }
    $ClientProcessId = $clients[0].Id
}
if ([string]::IsNullOrWhiteSpace($Lifecycle)) { $Lifecycle = [guid]::NewGuid().ToString("N") }
$prepared = $false
try {
    $before = Invoke-Fixture prepare
    $prepared = $true
    if ((Field $before commandBits) -cne "111" -or
        (Field $before skillBits) -cne "111111111111" -or
        [int](Field $before meditateMod) -ne 75 -or
        (Field $before snapshotComplete) -cne "true") {
        throw "Accuracy preparation is not authoritative: $before"
    }
    & $bridge -Action QueueMeditate -ClientProcessId $ClientProcessId | Write-Host
    $meditating = Wait-Status { param($s) (Field $s meditating) -ceq "true" } 15 "Meditation admission failed"
    & $bridge -Action QueuePowerBoost -ClientProcessId $ClientProcessId | Write-Host
    $power = Wait-Status { param($s) (Field $s outcome) -ceq "powerPassed" -and (Field $s powerActive) -ceq "true" } 15 "Power Boost execution failed"
    if ([int](Field $power powerBonus) -ne 500 -or [int](Field $power powerTick) -ne 25 -or
        [int](Field $power powerDuration) -ne 300) { throw "Power Boost formula proof failed: $power" }
    $powerExpired = Wait-Status { param($s) (Field $s powerActive) -ceq "false" -and (Field $s powerChannelBits) -ceq "0000" } 330 "Power Boost natural expiry failed"
    $armedForce = Invoke-Fixture armForce
    & $bridge -Action QueueForceOfWill -ClientProcessId $ClientProcessId | Write-Host
    $force = Wait-Status { param($s) (Field $s outcome) -ceq "forcePassed" } 15 "Force of Will execution failed"
    if ([int](Field $force forceRoll) -ne 35 -or [int](Field $force forceDelta) -ne 40 -or
        (Field $force forceTier) -cne "normal" -or (Field $force forceModifierBits) -cne "111111111") {
        throw "Force of Will tier proof failed: $force"
    }
    $forceExpired = Wait-Status { param($s) (Field $s forceModifierBits) -ceq "000000000" } 145 "Force of Will natural expiry failed"
    $cleanup = Invoke-Fixture cleanup
    if ((Field $cleanup restored) -cne "true") { throw "Accuracy cleanup failed: $cleanup" }
    $prepared = $false
    $idempotent = Invoke-Fixture cleanup
    if ((Field $idempotent alreadyClean) -cne "true" -or (Field $idempotent restored) -cne "true") {
        throw "Accuracy idempotent cleanup failed: $idempotent"
    }
    Write-Host "Publish 14.1 unarmed Accuracy authenticated runtime passed."
    [pscustomobject]@{
        lifecycle = $Lifecycle; preparation = $before; meditation = $meditating
        power = $power; powerExpiry = $powerExpired; forceArm = $armedForce
        force = $force; forceExpiry = $forceExpired; cleanup = $cleanup
        idempotentCleanup = $idempotent; result = "passed"
    }
} finally {
    if ($prepared) {
        try {
            & $bridge -Action Reset -ClientProcessId $ClientProcessId | Write-Host
            & $bridge -Action Stand -ClientProcessId $ClientProcessId | Write-Host
            Start-Sleep -Seconds 1
            Invoke-Fixture cleanup | Write-Host
        } catch { Write-Warning "Best-effort unarmed Accuracy cleanup failed: $_" }
    }
}
