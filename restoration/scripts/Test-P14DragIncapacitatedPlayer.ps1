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
            [string]$manifest.contracts.p14DragIncapacitatedPlayer)
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
        throw "Required materialized drag source is missing: $path"
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

$handler = Get-Content -LiteralPath $paths.handler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$row =
    Get-TableRow `
        -Path $paths.commandTable `
        -Key "dragIncapacitatedPlayer"

Write-Host "Publish 14.1 incapacitated-player drag checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.source -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/DragIncapacitatedPlayerCommand.h" -and
    [string]$contract.clientTableReference.sha256 -ceq
        "f7acb20472cbfc78a182703b8cfbf48a3eeaa84af32acd5e638f9342822258d8") `
    -Name "p14.drag.core3-and-retail-pins"

Assert-Contract -Condition (
    $row.Matches.Count -eq 1 -and
    $row.Header.Count -eq 94 -and
    $row.Values.Count -eq 94 -and
    $row.Values[0] -ceq "dragIncapacitatedPlayer" -and
    $row.Values[1] -ceq "combat" -and
    $row.Values[3] -ceq "cmdDragIncapPlayer" -and
    $row.Values[7] -ceq "2" -and
    $row.Values[8] -ceq "dragIncapacitatedPlayer" -and
    $row.Values[9] -ceq "1" -and
    $row.Values[10] -ceq "0" -and
    $row.Values[11] -ceq "1" -and
    $row.Values[12] -ceq "1" -and
    $row.Values[13] -ceq "0" -and
    $row.Values[72] -ceq "player.cmd.drag_incap_player" -and
    $row.Values[73] -ceq "other" -and
    $row.Values[74] -ceq "optional" -and
    $row.Values[76] -ceq "2" -and
    $row.Values[83] -ceq "0" -and
    $row.Values[84] -ceq "ALL" -and
    $row.Values[85] -ceq "NONE" -and
    $row.Values[88] -ceq "2") `
    -Name "p14.drag.table.authentic-two-second-nonqueue"

Assert-Contract -Condition (
    $handler.Contains('"science_medic_injury_speed_02"') -and
    $handler.Contains("BASE_RANGE = 10.0f") -and
    $handler.Contains("RANGE_PER_MOD = 0.2f") -and
    $handler.Contains("MAX_MOVEMENT = 5.0f") -and
    $handler.Contains("MINIMUM_DISTANCE = 0.01f") -and
    $handler.Contains("group.inSameGroup(self, target)") -and
    $handler.Contains("pclib.hasConsent(self, target)") -and
    $handler.Contains("pvpCanHelp(self, target)") -and
    $handler.Contains("factions.pvpDoAllowedHelpCheck") -and
    $handler.Contains("canSee(self, target)") -and
    $handler.Contains("isIncapacitated(target)") -and
    $handler.Contains("isDead(target)") -and
    $handler.Contains("isIdValid(medicLocation.cell)") -and
    $handler.Contains("getHeightAtLocation") -and
    $handler.Contains("setLocation(target, destination)") -and
    $handler.Contains("faceTo(target, self)") -and
    $handler.Contains("pvpHelpPerformed(self, target)") -and
    -not $handler.Contains("corpse.dragPlayerCorpse") -and
    -not $handler.Contains("healing.getDragPlayerRange")) `
    -Name "p14.drag.runtime.core3-boundary"

Assert-Contract -Condition (
    $fixture.Contains("MEDIC_OID = 39008597L") -and
    $fixture.Contains("MEDIC_STATION_ID = 1001") -and
    $fixture.Contains("PATIENT_OID = 44003778L") -and
    $fixture.Contains("PATIENT_STATION_ID = 91001") -and
    $fixture.Contains("HEALING_ABILITY = 10") -and
    $fixture.Contains("ORIGINAL_LOCATION") -and
    $fixture.Contains("ORIGINAL_POSTURE") -and
    $fixture.Contains("ORIGINAL_LOCOMOTION") -and
    $fixture.Contains("ORIGINAL_HEALTH") -and
    $fixture.Contains("ORIGINAL_ACTION") -and
    $fixture.Contains("ORIGINAL_MIND") -and
    $fixture.Contains("ORIGINAL_MEDICAL_XP") -and
    $fixture.Contains("group.inSameGroup(medic, patient)") -and
    $fixture.Contains("pclib.hasConsent(medic, patient)") -and
    -not $fixture.Contains("createGroup") -and
    -not $fixture.Contains("pclib.consent(")) `
    -Name "p14.drag.live.two-client-reversible-fixture"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 21 -and
        [int]$live.clientQueueCountAtAdmission -eq 0) `
        -Name "p14.drag.status.ready"
    Assert-Contract -Condition (
        [int]$live.handlerCalls -eq 1 -and
        [long]$live.targetOid -eq 44003778 -and
        [int]$live.healingAbility -eq 10 -and
        [int]$live.maximumRangeCentimeters -eq 1200 -and
        [int]$live.preDistanceCentimeters -ge 890 -and
        [int]$live.preDistanceCentimeters -le 910 -and
        [int]$live.movedCentimeters -ge 499 -and
        [int]$live.movedCentimeters -le 501 -and
        [int]$live.postDistanceCentimeters -lt
            [int]$live.preDistanceCentimeters -and
        [bool]$live.grouped -and
        -not [bool]$live.consented -and
        [bool]$live.patientIncapacitatedAfter -and
        [string]$live.handlerOutcome -ceq "performed") `
        -Name "p14.drag.live.production-five-meter-group-drag"
    Assert-Contract -Condition (
        [int]$live.medicHealthBefore -eq
            [int]$live.medicHealthAfter -and
        [int]$live.medicActionBefore -eq
            [int]$live.medicActionAfter -and
        [int]$live.medicMindBefore -eq
            [int]$live.medicMindAfter -and
        [int]$live.patientHealthBefore -eq
            [int]$live.patientHealthAfter -and
        [int]$live.patientActionBefore -eq
            [int]$live.patientActionAfter -and
        [int]$live.patientMindBefore -eq
            [int]$live.patientMindAfter -and
        [int]$live.medicalXpBefore -eq
            [int]$live.medicalXpAfter) `
        -Name "p14.drag.live.zero-ham-and-xp-mutation"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.groupDisbanded -and
        [int]$live.clientQueueCountAfterCleanup -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup) `
        -Name "p14.drag.live.cleanup-group-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 drag contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 incapacitated-player drag contract passed."
