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
            [string]$manifest.contracts.p14HealEnhanceCommand
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
        throw "Required materialized Heal Enhance source is missing: $path"
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

$consumable = Get-Content -LiteralPath $paths.consumableLibrary -Raw
$healing = Get-Content -LiteralPath $paths.healingLibrary -Raw
$handler = Get-Content -LiteralPath $paths.handler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$row = Get-TableRow -Path $paths.commandTable -Key "healEnhance"

Write-Host "Publish 14.1 Heal Enhance command checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.command -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/HealEnhanceCommand.h") `
    -Name "p14.heal-enhance.core3.pinned-command"

Assert-Contract -Condition (
    $row.Matches.Count -eq 1 -and
    $row.Header.Count -eq 94 -and
    $row.Values.Count -eq 94 -and
    $row.Values[0] -ceq "healEnhance" -and
    $row.Values[1] -ceq "combat" -and
    $row.Values[3] -ceq "healEnhance" -and
    $row.Values[7] -ceq "7" -and
    $row.Values[8] -ceq "healEnhance" -and
    $row.Values[72] -ceq "player.cmd.heal_enhance" -and
    $row.Values[73] -ceq "other" -and
    $row.Values[74] -ceq "optional" -and
    $row.Values[76] -ceq "2" -and
    $row.Values[83] -ceq "1" -and
    $row.Values[84] -ceq "ALL" -and
    $row.Values[85] -ceq "NONE" -and
    $row.Values[88] -ceq "7") `
    -Name "p14.heal-enhance.table.authentic-optional-queued"

Assert-Contract -Condition (
    $handler.Contains("target = self;") -and
    $handler.Contains("parsePatient(self, params)") -and
    $handler.Contains("isEligiblePatient(self, parameterTarget)") -and
    $handler.Contains("RANGE = 7.0f") -and
    $handler.Contains("getDistance(self, target)") -and
    $handler.Contains("canSee(self, target)") -and
    $handler.Contains("pvpCanHelp(self, target)") -and
    $handler.Contains("factions.pvpDoAllowedHelpCheck") -and
    $handler.Contains("pet_lib.isCreaturePet(target)") -and
    $handler.Contains("!ai_lib.isDroid(target)") -and
    $handler.Contains("!ai_lib.isAndroid(target)") -and
    $handler.Contains("!pet_lib.isVehiclePet(target)") -and
    $handler.Contains("getState(self, STATE_COMBAT)") -and
    $handler.Contains("getState(target, STATE_COMBAT)")) `
    -Name "p14.heal-enhance.runtime.organic-range-combat-help-gates"

Assert-Contract -Condition (
    $handler.Contains("healing.canHealWound(self)") -and
    $handler.Contains("healing.findBuffMedicine") -and
    $handler.Contains("healing.isBuffMedicine") -and
    $handler.Contains("healing.performHealEnhance") -and
    $handler.Contains("healing.getHealEnhanceRoundTime") -and
    $handler.Contains("healing.setCanHealWound") -and
    $handler.Contains("healing.playHealEnhanceEffect") -and
    $handler.Contains("doAnimationAction")) `
    -Name "p14.heal-enhance.runtime.location-medicine-recovery-effects"

Assert-Contract -Condition (
    $healing.Contains("VAR_HEALENHANCE_COST = 150") -and
    $healing.Contains("getHealEnhanceMedicineAttribute") -and
    $healing.Contains("getHealEnhanceRoundTime") -and
    $healing.Contains('"healing_wound_speed"') -and
    $healing.Contains('"heal_recovery"') -and
    $healing.Contains("Math.max(3, roundTime)") -and
    $healing.Contains("heal_type.equals(HEAL_TYPE_MEDICAL_BUFF)") -and
    $healing.Contains("total_healed * 2.5f") -and
    $healing.Contains("immediateGrant = true") -and
    $healing.Contains("net_buff_amount") -and
    $consumable.Contains("if (healing.isBuffMedicine(item))") -and
    $consumable.Contains("return am;") -and
    $handler.Contains("BASE_MIND_COST = 150") -and
    $handler.Contains("healing.getMedicalMindCost")) `
    -Name "p14.heal-enhance.runtime.cost-power-recovery-and-xp"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("science_medic_master") -and
    $fixture.Contains("science_doctor_novice") -and
    $fixture.Contains("science_doctor_wound_01") -and
    $fixture.Contains("science_doctor_wound_02") -and
    $fixture.Contains("BUFF_POWER = 200") -and
    $fixture.Contains("BUFF_DURATION = 1800.0f") -and
    $fixture.Contains("setCount(medicine, 2)") -and
    $fixture.Contains("setMaster(patient, player)") -and
    $fixture.Contains("patientPetPreparationFailed") -and
    $fixture.Contains("pet_lib.isCreaturePet(patient)") -and
    $fixture.Contains('setObjVar(patient, "medpower", 1.0f)') -and
    $fixture.Contains("ORIGINAL_FACILITY") -and
    $fixture.Contains("ORIGINAL_MIND") -and
    $fixture.Contains("ORIGINAL_MEDICAL_XP") -and
    $fixture.Contains("ORIGINAL_POINTS") -and
    $fixture.Contains("ORIGINAL_COOLDOWN") -and
    $fixture.Contains("revokeSkills(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    -Name "p14.heal-enhance.live.identity-bound-reversible-fixture"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 26) `
        -Name "p14.heal-enhance.status.ready"
    Assert-Contract -Condition (
        [int]$live.handlerCalls -eq 1 -and
        [int]$live.buffBefore -eq 0 -and
        [int]$live.buffAfter -gt 0 -and
        [int]$live.amountEnhanced -eq
            [int]$live.buffAfter -and
        [int]$live.appliedMindCost -eq
            [int]$live.expectedMindCost -and
        [int]$live.appliedChargeCost -eq 1 -and
        [int]$live.medicalXpDelta -eq
            [int]$live.expectedMedicalXp -and
        [int]$live.appliedRoundTime -eq
            [int]$live.expectedRoundTime -and
        [string]$live.handlerOutcome -ceq "performed") `
        -Name "p14.heal-enhance.live.pet-enhancement"
    Assert-Contract -Condition (
        [int]$live.clientQueueCountAfterExecution -eq 0 -and
        [int]$live.clientQueueCountAfterCleanup -eq 0 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.heal-enhance.live.queue-cleanup-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Heal Enhance contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Heal Enhance command contract passed."
