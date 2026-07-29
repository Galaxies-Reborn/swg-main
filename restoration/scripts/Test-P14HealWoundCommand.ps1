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
            [string]$manifest.contracts.p14HealWoundCommand)
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
        throw "Required materialized healWound source is missing: $path"
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

$healing = Get-Content -LiteralPath $paths.healing -Raw
$consumable = Get-Content -LiteralPath $paths.consumable -Raw
$handler = Get-Content -LiteralPath $paths.commandHandler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$commandRow = Get-TableRow -Path $paths.commandTable -Key "healWound"
$skillRow = Get-TableRow -Path $paths.skillTable -Key "science_medic_novice"

Write-Host "Publish 14.1 healWound command checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.source -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/HealWoundCommand.h") `
    -Name "p14.heal-wound.core3.pinned-command"

Assert-Contract -Condition (
    $commandRow.Matches.Count -eq 1 -and
    $commandRow.Header.Count -eq 94 -and
    $commandRow.Values.Count -eq 94 -and
    $commandRow.Header[0] -ceq "commandName" -and
    $commandRow.Values[0] -ceq "healWound" -and
    $commandRow.Values[1] -ceq "combat" -and
    $commandRow.Values[3] -ceq "cmdHealWound" -and
    $commandRow.Values[7] -ceq "7" -and
    $commandRow.Values[72] -ceq "player.cmd.heal_wound" -and
    $commandRow.Values[73] -ceq "other" -and
    $commandRow.Values[74] -ceq "optional" -and
    $commandRow.Values[83] -ceq "1" -and
    $commandRow.Values[84] -ceq "ALL" -and
    $commandRow.Values[88] -ceq "7") `
    -Name "p14.heal-wound.table.authentic-queued-command"

$noviceCommands = @(
    ([string]$skillRow.Values[21]).Trim('"').Split(
        ",",
        [System.StringSplitOptions]::RemoveEmptyEntries))
$requiredCommands = @(
    "private_medic_novice",
    "healDamage",
    "healWound",
    "medicalForage",
    "tendWound",
    "tendDamage",
    "diagnose")
Assert-Contract -Condition (
    $skillRow.Matches.Count -eq 1 -and
    $skillRow.Header.Count -eq 27 -and
    $skillRow.Values.Count -eq 27 -and
    $requiredCommands.Count -eq $noviceCommands.Count -and
    @($requiredCommands | Where-Object { $_ -cnotin $noviceCommands }).Count -eq
        0 -and
    ([string]$skillRow.Values[22]).Contains(
        "healing_wound_treatment=5") -and
    ([string]$skillRow.Values[22]).Contains("healing_ability=5") -and
    ([string]$skillRow.Values[22]).Contains(
        "medical_foraging=10")) `
    -Name "p14.heal-wound.skill.medic-novice-command-surface"

Assert-Contract -Condition (
    $healing.Contains("public static final int VAR_HEALWOUND_COST = 50;") -and
    $healing.Contains(
        "((getAttrib(medic, FOCUS) - 300.0f) / 1200.0f) * cost") -and
    $healing.Contains("return Math.max(0, (int)cost);") -and
    $healing.Contains(
        "Math.round(woundSpeed * -2.0f / 25.0f + 20.0f)") -and
    $healing.Contains("return Math.max(3, roundTime);")) `
    -Name "p14.heal-wound.runtime.core3-cost-and-round-time"

Assert-Contract -Condition (
    $handler.Contains("getState(self, STATE_COMBAT) == 1") -and
    $handler.Contains("getState(target, STATE_COMBAT) == 1") -and
    $handler.Contains(
        "getDistance(self, target) > consumable.MAX_AFFECT_DISTANCE") -and
    $consumable.Contains("MAX_AFFECT_DISTANCE = 6.0f") -and
    $handler.Contains("if (!canSee(self, target))") -and
    $handler.Contains("if (!pvpCanHelp(self, target) ||") -and
    $handler.Contains("!factions.pvpDoAllowedHelpCheck(self, target)") -and
    $handler.Contains("if (!healing.canHealWound(self))")) `
    -Name "p14.heal-wound.runtime.authoritative-gates"

Assert-Contract -Condition (
    $handler.Contains("healing.getHealWoundMedicineAttribute(medicine)") -and
    $handler.Contains("healing.performMedicalHealWound(") -and
    $healing.Contains("!applyHealingCost(") -and
    $healing.Contains(
        "setCanHealWound(medic, getHealWoundRoundTime(medic));") -and
    $healing.Contains("consumable.decrementCharges(med_obj, medic)")) `
    -Name "p14.heal-wound.runtime.production-medicine-path"

Assert-Contract -Condition (
    $healing.Contains("case HEAL_TYPE_MEDICAL_WOUND:") -and
    $healing.Contains(
        "experience = (int) (total_healed * 2.5f);") -and
    $healing.Contains("xp.grant(player, exp_type, experience);") -and
    -not $healing.Contains(
        "xp.grantCombatStyleXp(player, exp_type, experience);")) `
    -Name "p14.heal-wound.runtime.immediate-medical-xp"

Assert-Contract -Condition (
    $handler.Contains('"precu.healWoundCommandFixture"') -and
    $handler.Contains("boolean fixture =") -and
    $handler.Contains('FIXTURE_ROOT + ".handlerCalls"') -and
    $handler.Contains('FIXTURE_ROOT + ".expectedMedicalXp"')) `
    -Name "p14.heal-wound.live.telemetry-opt-in-only"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains('"prepare"') -and
    $fixture.Contains('"markQueue"') -and
    $fixture.Contains('"markCooldown"') -and
    $fixture.Contains('"cleanup"') -and
    $fixture.Contains('create.CREATURE_TABLE, "bantha"') -and
    $fixture.Contains("setMaster(patient, player);") -and
    $fixture.Contains("setCount(medicine, 2);")) `
    -Name "p14.heal-wound.live.identity-patient-and-actions"

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
    -Name "p14.heal-wound.live.reversible-owned-state"

if ($Expectation -ceq "Ready")
{
    $first = $contract.liveEvidence.firstQueue
    $cooldown = $contract.liveEvidence.cooldownQueue
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        -Name "p14.heal-wound.status.ready"
    Assert-Contract -Condition (
        [string]$first.handlerOutcome -ceq "performed" -and
        [int]$first.appliedWoundHeal -gt 0 -and
        [int]$first.appliedMindCost -eq [int]$first.expectedMindCost -and
        [int]$first.appliedChargeCost -eq 1 -and
        [int]$first.expectedMedicalXp -eq
            [int]([int]$first.appliedWoundHeal * 2.5) -and
        [int]$first.appliedMedicalXp -eq [int]$first.expectedMedicalXp -and
        [int]$first.expectedRoundTimeSeconds -eq 20) `
        -Name "p14.heal-wound.live.success-cost-charge-xp"
    Assert-Contract -Condition (
        [string]$cooldown.handlerOutcome -ceq
            "canHealWoundRejected" -and
        [int]$cooldown.handlerCalls -eq 2 -and
        [int]$cooldown.retainedQueueDeltaSeconds -eq 7 -and
        [int]$cooldown.additionalWoundHeal -eq 0 -and
        [int]$cooldown.additionalChargeCost -eq 0 -and
        [int]$cooldown.additionalMedicalXp -eq 0 -and
        [int]$cooldown.cooldownRemainingAtObservation -gt 0 -and
        [int]$cooldown.clientQueueCountAtObservation -eq 0) `
        -Name "p14.heal-wound.live.retained-queue-cooldown-rejection"
    Assert-Contract -Condition (
        [bool]$contract.liveEvidence.cleanup.restored -and
        [int]$contract.liveEvidence.cleanup.clientQueueCount -eq 0) `
        -Name "p14.heal-wound.live.cleanup-restored"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 healWound contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 healWound command contract passed."
