[CmdletBinding()]
param(
    [ValidatePattern("^[0-9]+$")][string]$PlayerOid = "44003778",
    [ValidateRange(1, [int]::MaxValue)][int]$ClientProcessId,
    [ValidatePattern("^[A-Za-z0-9_.-]+$")][string]$ContainerName = "swg-precu",
    [string]$ToolsRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ToolsRoot)) {
    $sourceRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $ToolsRoot = Join-Path $sourceRoot "pre-cu-reborn-tools"
}
$bridge = Join-Path $ToolsRoot "scripts/Invoke-PrecuBackgroundInput.ps1"
if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) { throw "Background-input helper not found: $bridge" }
function Invoke-Fixture([string]$Action, [string]$Lifecycle) {
    $serverCommand = "game tatooine runScript test.precu_meditate_fixture executeFixture $Action $PlayerOid $Lifecycle"
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
if (-not $PSBoundParameters.ContainsKey("ClientProcessId")) {
    $clients = @(Get-Process SwgClient_r -ErrorAction SilentlyContinue)
    if ($clients.Count -ne 1) { throw "Specify -ClientProcessId when exactly one SwgClient_r process is not running." }
    $ClientProcessId = $clients[0].Id
}
$lifecycle = [guid]::NewGuid().ToString("N")
$prepared = $false
try {
    $before = Invoke-Fixture prepare $lifecycle
    $prepared = $true
    if ((Field $before command) -cne "true" -or (Field $before skillBits) -cne "11111111" -or
        [int](Field $before meditateMod) -ne 15 -or [int](Field $before bleedingStrength) -ne 100 -or
        (Field $before snapshotComplete) -cne "true") { throw "Meditate preparation is not authoritative: $before" }
    & $bridge -Action QueueMeditate -ClientProcessId $ClientProcessId | Write-Host
    $executed = ""
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 250
        $executed = Invoke-Fixture status $lifecycle
    } while (((Field $executed meditating) -cne "true" -or [int](Field $executed bleedingStrength) -ne 80) -and [DateTime]::UtcNow -lt $deadline)
    if ((Field $executed meditating) -cne "true" -or [int](Field $executed bleedingStrength) -ne 80 -or
        [int](Field $executed posture) -ne 8 -or [int](Field $executed locomotion) -ne 14) {
        throw "Meditate first-tick proof failed: $executed"
    }
    & $bridge -Action Reset -ClientProcessId $ClientProcessId | Write-Host
    & $bridge -Action Stand -ClientProcessId $ClientProcessId | Write-Host
    Start-Sleep -Seconds 1
    $cleanup = Invoke-Fixture cleanup $lifecycle
    if ((Field $cleanup restored) -cne "true") { throw "Meditate cleanup failed: $cleanup" }
    $prepared = $false
    $idempotent = Invoke-Fixture cleanup $lifecycle
    if ((Field $idempotent alreadyClean) -cne "true" -or (Field $idempotent restored) -cne "true") {
        throw "Meditate idempotent cleanup failed: $idempotent"
    }
    Write-Host "Publish 14.1 meditate authenticated runtime passed."
    [pscustomobject]@{ lifecycle = $lifecycle; preparation = $before; execution = $executed; cleanup = $cleanup; idempotentCleanup = $idempotent; result = "passed" }
} finally {
    if ($prepared) {
        try {
            & $bridge -Action Reset -ClientProcessId $ClientProcessId | Write-Host
            & $bridge -Action Stand -ClientProcessId $ClientProcessId | Write-Host
            Start-Sleep -Seconds 1
            Invoke-Fixture cleanup $lifecycle | Write-Host
        } catch { Write-Warning "Best-effort meditate cleanup failed: $_" }
    }
}
