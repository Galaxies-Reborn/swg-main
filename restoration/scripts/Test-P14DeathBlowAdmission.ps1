[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot "manifest.json"
    ) -Raw | ConvertFrom-Json
$contract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.p14DeathBlowAdmission
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] =
        Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required death-blow source is missing: $path"
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

function Get-CommandRows
{
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $result = @{}
    foreach ($line in @($lines | Select-Object -Skip 2))
    {
        $values = $line -split "`t", -1
        if ($values.Count -lt 1 -or
            $values[0] -notin @("coupDeGrace", "deathBlow"))
        {
            continue
        }
        $fields = @{}
        for ($index = 0; $index -lt $header.Count; ++$index)
        {
            $fields[$header[$index]] =
                if ($index -lt $values.Count)
                {
                    $values[$index]
                }
                else
                {
                    ""
                }
        }
        $result[$values[0]] = $fields
    }
    return $result
}

$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$playerLibrary = Get-Content -LiteralPath $paths.playerLibrary -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$fixtureNormalized = $fixture.Replace("`r`n", "`n")
$fixtureHamRestoreIndex =
    $fixture.IndexOf("boolean hamReady =")
$fixtureVictimStateIndex =
    $fixture.IndexOf("boolean victimState =")
$rows = Get-CommandRows -Path $paths.commandTable

Write-Host "Publish 14.1 death-blow admission checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [int]$contract.semanticReference.serverRangeMeters -eq 5 -and
    [bool]$contract.semanticReference.lineOfSightRequired -and
    [bool]$contract.semanticReference.targetFeignDeathRejected) `
    -Name "p14.death-blow.core3.pinned-five-meter-los-and-feign"

$rowsMatch = $rows.Count -eq 2
foreach ($name in @("coupDeGrace", "deathBlow"))
{
    $row = $rows[$name]
    $rowsMatch = $rowsMatch -and
        $null -ne $row -and
        [string]$row["scriptHook"] -ceq "cmdCoupDeGrace" -and
        [string]$row["target"] -ceq "enemy" -and
        [string]$row["targetType"] -ceq "required" -and
        [int]$row["defaultTime"] -eq 3 -and
        [int]$row["executeTime"] -eq 1 -and
        [int]$row["addToCombatQueue"] -eq 1 -and
        [int]$row["maxRangeToTarget"] -eq 16
}
Assert-Contract -Condition $rowsMatch `
    -Name "p14.death-blow.table.authentic-dual-queued-sixteen-meter-rows"

Assert-Contract -Condition (
    $basePlayer.Contains("RANGE_COUP_DE_GRACE = 5.0f") -and
    $basePlayer.Contains("killer == victim || isDead(victim)") -and
    $basePlayer.Contains("getState(victim, STATE_FEIGN_DEATH) == 1") -and
    $basePlayer.Contains("!canSee(killer, victim)") -and
    $basePlayer.Contains("distance > RANGE_COUP_DE_GRACE") -and
    $basePlayer.Contains("pvpCanAttack(killer, victim)") -and
    $basePlayer.Contains("if (canDeathBlow(self, target))")) `
    -Name "p14.death-blow.runtime.shared-authoritative-admission"

Assert-Contract -Condition (
    $basePlayer.Contains("pclib.coupDeGrace(target, self)") -and
    $playerLibrary.Contains(
        "public static void coupDeGrace(obj_id victim, obj_id killer)") -and
    $playerLibrary.Contains("playerDeath(victim, killer, dueling);")) `
    -Name "p14.death-blow.runtime.retained-execution-and-death-path"

Assert-Contract -Condition (
    $fixture.Contains("ATTACKER_OID = 44003778L") -and
    $fixture.Contains("ATTACKER_STATION_ID = 91001") -and
    $fixture.Contains("VICTIM_OID = 39008597L") -and
    $fixture.Contains("VICTIM_STATION_ID = 1001") -and
    $fixture.Contains('"prepareFar"') -and
    $fixture.Contains('"armFeign"') -and
    $fixture.Contains('"armNear"') -and
    $fixture.Contains("6.0f") -and
    $fixture.Contains("4.0f") -and
    $fixtureNormalized.Contains(
        "FIXTURE_INCAP_HEALTH =`n" +
        "        -100") -and
    $fixture.Contains("pclib.resurrectPlayer(victim)") -and
    $fixture.Contains("grantCommand(attacker, COMMAND)") -and
    $fixture.Contains("revokeCommand(attacker, COMMAND)") -and
    $fixture.Contains("ORIGINAL_COMMAND") -and
    $fixture.Contains("getGameTime() + 60") -and
    $fixture.Contains('"incap.timeStamp"') -and
    $fixture.Contains('"stabilize"') -and
    $fixture.Contains(
        '"action=stabilize result=passed "') -and
    $fixture.Contains("private String stabilize(") -and
    $fixtureHamRestoreIndex -ge 0 -and
    $fixtureVictimStateIndex -gt
        $fixtureHamRestoreIndex -and
    $fixtureNormalized.Contains(
        "(feigning ||`n" +
        "                isIncapacitated(victim))") -and
    $fixtureNormalized.Contains(
        "POSTURE_INCAPACITATED) &`n" +
        "            setState(`n" +
        "                victim,`n" +
        "                STATE_FEIGN_DEATH,`n" +
        "                feigning)") -and
    $fixture.Contains("removeObjVar(attacker, ROOT)") -and
    $fixture.Contains("removeObjVar(victim, ROOT)") -and
    -not $fixture.Contains("cmdCoupDeGrace(") -and
    -not $fixture.Contains("canDeathBlow(") -and
    -not $fixture.Contains("pclib.coupDeGrace(")) `
    -Name "p14.death-blow.fixture.layered-real-command-and-reversible"

if ([string]$contract.buildEvidence.result -ceq "passed")
{
    Assert-Contract -Condition (
        [string]$contract.buildEvidence.sourceCommit -ceq
            "897262339" -and
        [string]$contract.buildEvidence.patchSha256 -ceq
            "b367c5455e306f8794709b672ed3c5477c9be3bf2c3db882279845a1c1b3f2a3" -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$contract.buildEvidence.compiledSha256.
                "base_player.class") -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$contract.buildEvidence.compiledSha256.
                "precu_death_blow_fixture.class")) `
        -Name "p14.death-blow.build.clean-java-evidence"
}

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 30) `
        -Name "p14.death-blow.status.ready-protocol-thirty"
    Assert-Contract -Condition (
        [bool]$live.far.clientQueued -and
        [int]$live.far.distanceCentimeters -eq 600 -and
        -not [bool]$live.far.victimDeadAfter -and
        [bool]$live.feign.clientQueued -and
        -not [bool]$live.feign.victimDeadAfter -and
        [bool]$live.near.clientQueued -and
        [int]$live.near.distanceCentimeters -eq 400 -and
        [bool]$live.near.victimDeadAfter) `
        -Name "p14.death-blow.live.far-feign-rejected-near-executed"
    Assert-Contract -Condition (
        [bool]$live.cleanup.deathFixtureRestored -and
        [bool]$live.cleanup.headShotFixtureRestored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.death-blow.live.layered-exact-cleanup-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 death-blow contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 death-blow admission contract passed."
