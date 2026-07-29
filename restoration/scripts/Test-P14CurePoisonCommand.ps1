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
            [string]$manifest.contracts.p14CurePoisonCommand
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
        throw "Required materialized Cure Poison source is missing: $path"
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
    $matches = @(
        $lines |
            Select-Object -Skip 2 |
            Where-Object {
                (($_ -split "`t", -1)[0]) -ceq $Key
            })
    return [pscustomobject]@{
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

$healing = Get-Content -LiteralPath $paths.healingLibrary -Raw
$handler = Get-Content -LiteralPath $paths.handler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$row = Get-TableRow -Path $paths.commandTable -Key "curePoison"

Write-Host "Publish 14.1 Cure Poison command checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.specialization -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/CurePoisonCommand.h" -and
    [string]$contract.semanticReference.sharedCommand -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/CurePackCommand.h") `
    -Name "p14.cure-poison.core3.pinned-command"

Assert-Contract -Condition (
    $row.Matches.Count -eq 1 -and
    $row.Header.Count -eq 94 -and
    $row.Values.Count -eq 94 -and
    $row.Values[0] -ceq "curePoison" -and
    $row.Values[1] -ceq "combat" -and
    $row.Values[3] -ceq "curePoison" -and
    $row.Values[7] -ceq "5" -and
    $row.Values[8] -ceq "curePoison" -and
    $row.Values[72] -ceq "player.cmd.cure_poison" -and
    $row.Values[73] -ceq "other" -and
    $row.Values[74] -ceq "optional" -and
    $row.Values[76] -ceq "2" -and
    $row.Values[83] -ceq "0" -and
    $row.Values[84] -ceq "ALL" -and
    $row.Values[85] -ceq "NONE" -and
    $row.Values[88] -ceq "5") `
    -Name "p14.cure-poison.table.authentic-optional-nonqueued"

Assert-Contract -Condition (
    $handler.Contains("target = self;") -and
    $handler.Contains("RANGE = 7.0f") -and
    $handler.Contains("getDistance(self, target)") -and
    $handler.Contains("canSee(self, target)") -and
    $handler.Contains("pvpCanHelp(self, target)") -and
    $handler.Contains("factions.pvpDoAllowedHelpCheck") -and
    $handler.Contains("pet_lib.isCreaturePet(target)") -and
    $handler.Contains("!ai_lib.isDroid(target)") -and
    $handler.Contains("!ai_lib.isAndroid(target)") -and
    $handler.Contains("!pet_lib.isVehiclePet(target)")) `
    -Name "p14.cure-poison.runtime.organic-seven-meter-help-gates"

Assert-Contract -Condition (
    $handler.Contains("dot.isPoisoned(target)") -and
    $handler.Contains("healing.findCureDotMedicine") -and
    $handler.Contains("healing.isCurePoisonMedicine") -and
    $handler.Contains("healing.performCurePoison") -and
    $handler.Contains("healing.getDotPower") -and
    $handler.Contains("COOLDOWN_VAR") -and
    $handler.Contains('"healing.can_heal_state"') -and
    $handler.Contains("20.0f - injurySpeed / 5.0f") -and
    $handler.Contains('"heal_recovery"') -and
    $handler.Contains("Math.max(MIN_ROUND_TIME, roundTime)")) `
    -Name "p14.cure-poison.runtime.dot-medicine-and-shared-recovery"

Assert-Contract -Condition (
    $healing.Contains("VAR_CURE_POISON_COST = 100") -and
    $healing.Contains("heal_type.equals(HEAL_TYPE_MEDICAL_CURE_POISON)") -and
    $healing.Contains("? 7.0f") -and
    $healing.Contains("xp.grant(medic, xp.MEDICAL, 50)") -and
    $healing.Contains('getEnhancedSkillStatisticModifier(medic, "healing_wound_treatment")') -and
    $handler.Contains("BASE_MIND_COST = 100") -and
    $handler.Contains("healing.getMedicalMindCost")) `
    -Name "p14.cure-poison.runtime.cost-power-range-and-fixed-xp"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("science_medic_master") -and
    $fixture.Contains("science_doctor_novice") -and
    $fixture.Contains("science_doctor_wound_speed_01") -and
    $fixture.Contains("science_doctor_wound_speed_02") -and
    $fixture.Contains("POISON_STRENGTH = 90") -and
    $fixture.Contains("CURE_POWER = 200") -and
    $fixture.Contains("setCount(medicine, 2)") -and
    $fixture.Contains("ORIGINAL_MIND") -and
    $fixture.Contains("ORIGINAL_MEDICAL_XP") -and
    $fixture.Contains("ORIGINAL_POINTS") -and
    $fixture.Contains("ORIGINAL_COOLDOWN") -and
    $fixture.Contains("revokeSkills(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    -Name "p14.cure-poison.live.identity-bound-reversible-fixture"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 24) `
        -Name "p14.cure-poison.status.ready"
    Assert-Contract -Condition (
        [int]$live.handlerCalls -eq 1 -and
        [long]$live.targetOid -eq 39008597 -and
        [int]$live.poisonBefore -eq 90 -and
        [int]$live.poisonAfter -eq 0 -and
        [int]$live.poisonReduction -eq 90 -and
        [int]$live.appliedMindCost -eq
            [int]$live.expectedMindCost -and
        [int]$live.appliedChargeCost -eq 1 -and
        [int]$live.appliedMedicalXpDelta -eq 0 -and
        [int]$live.appliedRoundTime -eq
            [int]$live.expectedRoundTime -and
        [string]$live.handlerOutcome -ceq "performed") `
        -Name "p14.cure-poison.live.self-treatment"
    Assert-Contract -Condition (
        [int]$live.clientQueueCountAtAdmission -eq 0 -and
        [int]$live.clientQueueCountAfterExecution -eq 0 -and
        [int]$live.clientQueueCountAfterCleanup -eq 0 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.cure-poison.live.queue-cleanup-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Cure Poison contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Cure Poison command contract passed."
