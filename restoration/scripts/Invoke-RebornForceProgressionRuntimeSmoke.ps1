[CmdletBinding()]
param(
    [ValidatePattern("^[A-Za-z0-9_.-]+$")]
    [string]$ContainerName = "swg-force-progression-smoke",

    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 30,

    [switch]$ExercisePlayer,

    [ValidatePattern("^39008597$")]
    [string]$PlayerOid = "39008597"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$probeScript = "test.reborn_force_progression_runtime"
$probeMethod = "executeProbe"
if ($ExercisePlayer)
{
    if ($ContainerName -cne "swg-force-progression-smoke")
    {
        throw "The mutating player exercise is restricted to swg-force-progression-smoke."
    }
    $composeProjectOutput = @(& docker inspect $ContainerName --format '{{ index .Config.Labels "com.docker.compose.project" }}' 2>$null)
    $inspectExitCode = $LASTEXITCODE
    $composeProject = ($composeProjectOutput -join "").Trim()
    if ($inspectExitCode -ne 0 -or $composeProject -cne "swg-force-progression-smoke")
    {
        throw "The player exercise requires the isolated swg-force-progression-smoke Compose project."
    }
    $lifecycle = [Guid]::NewGuid().ToString("N")
    $probeArguments = "player $PlayerOid $lifecycle"
}
else
{
    $probeArguments = "tatooine"
}
$serverCommand = "game tatooine runScript $probeScript $probeMethod $probeArguments"
$bashCommand =
    "cd /swg-force-progression-smoke/exe/linux && " +
    "printf '%-1023s\0' '$serverCommand' | " +
    "timeout $($TimeoutSeconds)s ./bin/ServerConsole -- @servercommon.cfg -s ServerConsole " +
    "serverAddress=127.0.0.1 serverPort=61000"

$previousErrorActionPreference = $ErrorActionPreference
try
{
    $ErrorActionPreference = "Continue"
    $output = @(& docker exec $ContainerName bash -lc $bashCommand 2>&1)
    $dockerExitCode = $LASTEXITCODE
}
finally
{
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($dockerExitCode -ne 0)
{
    throw "ServerConsole failed ($dockerExitCode): $($output -join [Environment]::NewLine)"
}

$text = ($output -join [Environment]::NewLine).Trim()
$match = [regex]::Match($text, "(?m)(?:^|\s)(?<result>(?:action|error)=[^\r\n]+)")
if (-not $match.Success)
{
    throw "ServerConsole returned no Force progression result: $text"
}
$resultText = $match.Groups["result"].Value.Trim()
$values = @{}
foreach ($token in [regex]::Matches($resultText, "(?<key>[A-Za-z][A-Za-z0-9]*)=(?<value>\S+)"))
{
    $key = $token.Groups["key"].Value
    if ($values.ContainsKey($key))
    {
        throw "ServerConsole returned duplicate '$key': $resultText"
    }
    $values[$key] = $token.Groups["value"].Value
}
if ($values.ContainsKey("error"))
{
    throw "Force progression runtime probe failed: $resultText"
}

if ($ExercisePlayer)
{
    $expected = [ordered]@{
        action = "player"
        passed = "true"
        migration = "true"
        migrationCredit = "12"
        hintBoundary = "true"
        wrongAnswerCooldown = "true"
        eventCount = "12"
        status = "strong"
        completedQuests = "16"
        insightEarned = "64"
        insightSpent = "64"
        insightAvailable = "0"
        trees = "4"
        padawanReady = "true"
        padawanInitialized = "true"
        bartenderThrottle = "true"
        restored = "true"
    }
}
else
{
    $expected = [ordered]@{
        action = "inspect"
        mode = "replacement"
        planet = "tatooine"
        rows = "24"
        echo = "16"
        thread = "7"
        convergence = "1"
        routes = "6"
        planets = "10"
        branches = "16"
        expectedSpawns = "4"
        loadedSpawns = "4"
        exactSpawns = "true"
        authoritative = "true"
        mentorScript = "true"
        invulnerable = "true"
        conversable = "true"
        owner = "true"
        spawnerScript = "true"
    }
}
foreach ($entry in $expected.GetEnumerator())
{
    if (-not $values.ContainsKey($entry.Key) -or
        [string]$values[$entry.Key] -cne [string]$entry.Value)
    {
        throw "Expected $($entry.Key)=$($entry.Value): $resultText"
    }
}
if (-not $ExercisePlayer -and
    (-not $values.ContainsKey("playerLoaded") -or
    [string]$values.playerLoaded -notin @("true", "false")))
{
    throw "Probe omitted canonical playerLoaded state: $resultText"
}

[pscustomobject]@{
    Status = "passed"
    Container = $ContainerName
    Exercise = $(if ($ExercisePlayer) { "player" } else { "network" })
    PlayerLoaded = $(if ($ExercisePlayer) { $true } else { [bool]::Parse([string]$values.playerLoaded) })
    Result = $resultText
}
