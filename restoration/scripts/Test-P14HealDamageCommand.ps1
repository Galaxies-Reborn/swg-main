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
    Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.p14HealDamageCommand)
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
        throw "Required materialized healDamage source is missing: $path"
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

$consumable = Get-Content -LiteralPath $paths.consumable -Raw
$healing = Get-Content -LiteralPath $paths.healing -Raw
$handler = Get-Content -LiteralPath $paths.commandHandler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$commandRow = Get-TableRow -Path $paths.commandTable -Key "healDamage"
$skillRow =
    Get-TableRow -Path $paths.skillTable -Key "science_medic_novice"

Write-Host "Publish 14.1 healDamage command checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.source -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/HealDamageCommand.h") `
    -Name "p14.heal-damage.core3.pinned-command"

Assert-Contract -Condition (
    $commandRow.Matches.Count -eq 1 -and
    $commandRow.Header.Count -eq 94 -and
    $commandRow.Values.Count -eq 94 -and
    $commandRow.Values[0] -ceq "healDamage" -and
    $commandRow.Values[1] -ceq "combat" -and
    $commandRow.Values[3] -ceq "cmdHealDamage" -and
    $commandRow.Values[7] -ceq "5" -and
    $commandRow.Values[72] -ceq "player.cmd.heal_damage" -and
    $commandRow.Values[73] -ceq "other" -and
    $commandRow.Values[74] -ceq "optional" -and
    $commandRow.Values[83] -ceq "1" -and
    $commandRow.Values[84] -ceq "ALL" -and
    $commandRow.Values[88] -ceq "5") `
    -Name "p14.heal-damage.table.authentic-queued-command"

Assert-Contract -Condition (
    $skillRow.Matches.Count -eq 1 -and
    $skillRow.Values.Count -eq 27 -and
    ([string]$skillRow.Values[21]).Contains("healDamage") -and
    ([string]$skillRow.Values[22]).Contains(
        "healing_injury_treatment=5") -and
    ([string]$skillRow.Values[22]).Contains(
        "healing_injury_speed=5")) `
    -Name "p14.heal-damage.skill.medic-novice-grant"

Assert-Contract -Condition (
    $healing.Contains(
        "public static final int VAR_HEALDAMAGE_COST = 50;") -and
    $healing.Contains(
        "heal_type.equals(HEAL_TYPE_MEDICAL_DAMAGE) ||") -and
    $healing.Contains("getMedicalMindCost(player, cost)") -and
    $healing.Contains(
        "Math.round(20.0f - injurySpeed / 5.0f)") -and
    $healing.Contains("return Math.max(4, roundTime);")) `
    -Name "p14.heal-damage.runtime.core3-cost-and-round-time"

Assert-Contract -Condition (
    $healing.Contains(
        "int time_remaining = healing_roundtime - getGameTime();") -and
    $healing.Contains("getGameTime() + roundtime") -and
    $healing.Contains(
        "setCanHealDamage(medic, getHealDamageRoundTime(medic));")) `
    -Name "p14.heal-damage.runtime.real-expiring-cooldown"

Assert-Contract -Condition (
    $handler.Contains("NORMAL_MEDICINE_RANGE = 7.0f") -and
    $handler.Contains("if (!canSee(self, target))") -and
    $handler.Contains("if (!pvpCanHelp(self, target) ||") -and
    $handler.Contains("!factions.pvpDoAllowedHelpCheck(self, target)") -and
    $handler.Contains("if (!healing.canHealDamage(self))") -and
    -not $handler.Contains("getState(self, STATE_COMBAT)") -and
    $consumable.Contains("float maximumNormalMedicineRange") -and
    $consumable.Contains(
        "getDistance(player, target) > maximumNormalMedicineRange")) `
    -Name "p14.heal-damage.runtime.patient-range-pvp-and-combat"

Assert-Contract -Condition (
    $handler.Contains("healing.findHealDamageMedicine(self, target)") -and
    $handler.Contains("healing.performMedicalHealDamage(") -and
    $healing.Contains("getAttrib(target, HEALTH) - before[0]") -and
    $healing.Contains("getAttrib(target, ACTION) - before[1]") -and
    $healing.Contains("getAttrib(target, MIND) - before[2]") -and
    $healing.Contains("delta[0],") -and
    $healing.Contains("delta[1]") -and
    $healing.Contains(
        "experience = Math.round(total_healed * 0.25f);") -and
    $healing.Contains("!isPlayer(target)") -and
    $healing.Contains("xp.grant(player, exp_type, experience);")) `
    -Name "p14.heal-damage.runtime.three-pool-and-xp-boundary"

Assert-Contract -Condition (
    $handler.Contains('"precu.healDamageCommandFixture"') -and
    $handler.Contains('FIXTURE_ROOT + ".handlerCalls"') -and
    $handler.Contains('FIXTURE_ROOT + ".appliedHealthHeal"') -and
    $handler.Contains('FIXTURE_ROOT + ".appliedActionHeal"') -and
    $handler.Contains('FIXTURE_ROOT + ".appliedMindHeal"')) `
    -Name "p14.heal-damage.live.telemetry-opt-in-only"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains('"prepare"') -and
    $fixture.Contains('"markQueue"') -and
    $fixture.Contains('"markCooldown"') -and
    $fixture.Contains('"cleanup"') -and
    $fixture.Contains('create.CREATURE_TABLE, "bantha"') -and
    $fixture.Contains("setCount(medicine, 2);") -and
    $fixture.Contains("modifiers = new attrib_mod[3]")) `
    -Name "p14.heal-damage.live.identity-patient-and-actions"

Assert-Contract -Condition (
    $fixture.Contains("ORIGINAL_MEDICAL_XP") -and
    $fixture.Contains("ORIGINAL_MIND") -and
    $fixture.Contains("ORIGINAL_SHOCK") -and
    $fixture.Contains("ORIGINAL_NOVICE") -and
    $fixture.Contains("ORIGINAL_INJURY_ONE") -and
    $fixture.Contains("ORIGINAL_COMMAND") -and
    $fixture.Contains("ORIGINAL_COOLDOWN") -and
    $fixture.Contains("destroyObject(medicine);") -and
    $fixture.Contains("destroyObject(patient);") -and
    $fixture.Contains("removeObjVar(player, ROOT);")) `
    -Name "p14.heal-damage.live.reversible-owned-state"

if ($Expectation -ceq "Ready")
{
    $first = $contract.liveEvidence.firstQueue
    $cooldown = $contract.liveEvidence.cooldownQueue
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        -Name "p14.heal-damage.status.ready"
    Assert-Contract -Condition (
        [string]$first.handlerOutcome -ceq "performed" -and
        [int]$first.appliedHealthHeal -gt 0 -and
        [int]$first.appliedActionHeal -gt 0 -and
        [int]$first.appliedMindHeal -gt 0 -and
        [int]$first.appliedMindCost -eq
            [int]$first.expectedMindCost -and
        [int]$first.appliedChargeCost -eq 1 -and
        [int]$first.appliedMedicalXp -eq 0 -and
        [int]$first.expectedRoundTimeSeconds -ge 4) `
        -Name "p14.heal-damage.live.success-cost-charge-and-pet-xp"
    Assert-Contract -Condition (
        [string]$cooldown.handlerOutcome -ceq
            "canHealDamageRejected" -and
        [int]$cooldown.handlerCalls -eq 2 -and
        [int]$cooldown.retainedQueueDeltaSeconds -eq 5 -and
        [int]$cooldown.additionalHealthHeal -eq 0 -and
        [int]$cooldown.additionalActionHeal -eq 0 -and
        [int]$cooldown.additionalMindHeal -eq 0 -and
        [int]$cooldown.additionalMindCost -eq 0 -and
        [int]$cooldown.additionalChargeCost -eq 0 -and
        [int]$cooldown.additionalMedicalXp -eq 0 -and
        [int]$cooldown.cooldownRemainingAtObservation -gt 0 -and
        [int]$cooldown.clientQueueCountAtObservation -eq 0) `
        -Name "p14.heal-damage.live.retained-queue-cooldown-rejection"
    Assert-Contract -Condition (
        [bool]$contract.liveEvidence.cleanup.restored -and
        [int]$contract.liveEvidence.cleanup.clientQueueCount -eq 0) `
        -Name "p14.heal-damage.live.cleanup-restored"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 healDamage contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 healDamage command contract passed."
