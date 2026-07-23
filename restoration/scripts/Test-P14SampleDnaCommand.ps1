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
$manifest = Get-Content -LiteralPath (
    Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot (
        [string]$manifest.contracts.p14SampleDnaCommand
    )) -Raw | ConvertFrom-Json
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
        throw "Required sampleDNA source is missing: $path"
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

function Get-TableRow
{
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $matches = @($lines | Select-Object -Skip 2 | Where-Object {
        (($_ -split "`t", -1)[0]) -ceq $Key
    })
    [pscustomobject]@{
        Header = $header
        Matches = $matches
        Values = if ($matches.Count -eq 1)
        {
            $matches[0] -split "`t", -1
        }
        else
        {
            @()
        }
    }
}

$command = Get-TableRow -Path $paths.commandTable -Key "sampleDNA"
$novice = Get-TableRow -Path $paths.skillTable `
    -Key "outdoors_bio_engineer_novice"
$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$bio = Get-Content -LiteralPath $paths.bioEngineer -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw

Write-Host "Publish 14.1 sampleDNA command checks:"
Assert-Contract -Condition (
    $command.Matches.Count -eq 1 -and
    $command.Header.Count -eq 94 -and
    $command.Values.Count -eq 94 -and
    $command.Values[0] -ceq "sampleDNA" -and
    $command.Values[3] -ceq "cmdHarvestDNA" -and
    $command.Values[4] -ceq "cmdHarvestDNAFail" -and
    $command.Values[7] -ceq "1" -and
    $command.Values[73] -ceq "other" -and
    $command.Values[74] -ceq "required" -and
    $command.Values[80] -ceq "16" -and
    $command.Values[84] -ceq "ALL") `
    -Name "p14.sample-dna.command.authentic-registration"

Assert-Contract -Condition (
    $novice.Matches.Count -eq 1 -and
    $novice.Values.Count -eq 27 -and
    ([string]$novice.Values[21]).Split(',') -ccontains "sampleDNA") `
    -Name "p14.sample-dna.skill.bio-engineer-novice-grant"

Assert-Contract -Condition (
    $basePlayer.Contains("public int cmdHarvestDNA(") -and
    $basePlayer.Contains("bio_engineer.harvestCreatureDNA(self, target);") -and
    $basePlayer.Contains("public int cmdHarvestDNAFail(") -and
    $basePlayer.Contains("bio_engineer.completeHarvest(self);")) `
    -Name "p14.sample-dna.retained-player-handler"

Assert-Contract -Condition (
    $bio.Contains("int actioncost = 100;") -and
    $bio.Contains("int mindcost = 250;") -and
    $bio.Contains('getSkillStatisticModifier(player, "dna_harvesting")') -and
    $bio.Contains("xp.grant(player, xp.BIO_ENGINEER_DNA_HARVESTING, xpAmount);") -and
    $bio.Contains("StrictMath.pow(targetDiff, 1.2f) * 5.0f") -and
    $bio.Contains("PRECU_SAMPLE_DNA_PLAYER_OID = 44003778L") -and
    $bio.Contains("PRECU_SAMPLE_DNA_STATION_ID = 91001") -and
    $bio.Contains("PRECU_SAMPLE_DNA_PROTOCOL_VERSION = 1") -and
    $bio.Contains('PRECU_SAMPLE_DNA_ROOT + ".actionCost"') -and
    $bio.Contains('PRECU_SAMPLE_DNA_ROOT + ".mindCost"')) `
    -Name "p14.sample-dna.production-cost-xp-and-isolated-telemetry"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 44003778L") -and
    $fixture.Contains("PLAYER_STATION_ID = 91001") -and
    $fixture.Contains('CREATURE_TYPE = "worrt"') -and
    $fixture.Contains('creatureData.put("lootTable", "");') -and
    $fixture.Contains("create.initializeCreature(") -and
    $fixture.Contains("create.attachCreatureScripts(") -and
    $fixture.Contains('"prepare"') -and
    $fixture.Contains('"status"') -and
    $fixture.Contains('"cleanup"')) `
    -Name "p14.sample-dna.live.disposable-real-creature"

Assert-Contract -Condition (
    $fixture.Contains("ORIGINAL_MAX_ACTION") -and
    $fixture.Contains("ORIGINAL_MAX_MIND") -and
    $fixture.Contains("ORIGINAL_XP") -and
    $fixture.Contains("ORIGINAL_POINTS") -and
    $fixture.Contains("destroyObject(target)") -and
    $fixture.Contains("destroyObject(dna)") -and
    $fixture.Contains("alreadyClean=true restored=true")) `
    -Name "p14.sample-dna.live.reversible-and-idempotent"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 155 -and
        [int]$live.handlerCalls -eq 1) `
        -Name "p14.sample-dna.status.ready"
    Assert-Contract -Condition (
        [int]$live.actionCost -eq 100 -and
        [int]$live.mindCost -eq 250 -and
        [int]$live.skillRoll -eq 1 -and
        [int]$live.survivalRoll -eq 1 -and
        [int]$live.behaviorRoll -eq 100) `
        -Name "p14.sample-dna.live.command-costs-and-rolls"
    Assert-Contract -Condition (
        [long]$live.dnaOid -gt 0 -and
        [string]$live.dnaTemplate -like
            "object/tangible/component/dna/dna_sample_*.iff" -and
        [int]$live.xpGranted -eq 92 -and
        [int]$live.xpPersisted -eq [int]$live.xpGranted -and
        [bool]$live.creatureSurvived) `
        -Name "p14.sample-dna.live.dna-xp-and-survival"
    Assert-Contract -Condition (
        [bool]$live.cleanupRestored -and
        [bool]$live.idempotentCleanupRestored -and
        [bool]$live.serverHealthy) `
        -Name "p14.sample-dna.live.cleanup-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 sampleDNA contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 sampleDNA command contract passed."
