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
            [string]$manifest.contracts.p14DiagnoseCommand)
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
        throw "Required materialized diagnose source is missing: $path"
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

$handler = Get-Content -LiteralPath $paths.diagnoseHandler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$row = Get-TableRow -Path $paths.commandTable -Key "diagnose"
$skillRow =
    Get-TableRow -Path $paths.skillTable -Key "science_medic_novice"
$nonCombatRow =
    Get-TableRow -Path $paths.nonCombatTable -Key "diagnose"

Write-Host "Publish 14.1 diagnose command checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.source -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/DiagnoseCommand.h") `
    -Name "p14.diagnose.core3.pinned-command"

Assert-Contract -Condition (
    $row.Matches.Count -eq 1 -and
    $row.Header.Count -eq 94 -and
    $row.Values.Count -eq 94 -and
    $row.Values[0] -ceq "diagnose" -and
    $row.Values[1] -ceq "combat" -and
    $row.Values[3] -ceq "cmdDiagnose" -and
    $row.Values[4] -ceq "cmdFailDiagnose" -and
    $row.Values[7] -ceq "5" -and
    $row.Values[72] -ceq "player.cmd.diagnose" -and
    $row.Values[73] -ceq "other" -and
    $row.Values[74] -ceq "required" -and
    $row.Values[80] -ceq "6" -and
    $row.Values[83] -ceq "0" -and
    $row.Values[84] -ceq "ALL" -and
    $row.Values[88] -ceq "5") `
    -Name "p14.diagnose.table.authentic-required-nonqueue"

Assert-Contract -Condition (
    $skillRow.Matches.Count -eq 1 -and
    ([string]$skillRow.Values[21]).Contains("diagnose") -and
    $nonCombatRow.Matches.Count -eq 1) `
    -Name "p14.diagnose.skill-and-noncombat-data"

$orderedNames = @(
    '"Health"',
    '"Strength"',
    '"Constitution"',
    '"Action"',
    '"Quickness"',
    '"Stamina"',
    '"Mind"',
    '"Focus"',
    '"Willpower"'
)
$positions = @($orderedNames | ForEach-Object { $handler.IndexOf($_) })
Assert-Contract -Condition (
    -not ($positions -contains -1) -and
    (($positions -join ",") -ceq
        (($positions | Sort-Object) -join ",")) -and
    $handler.Contains('"Battle Fatigue -- "') -and
    $handler.Contains("entries[ATTRIBUTES.length]") -and
    $handler.Contains("entries.length") -and
    $handler.Contains("sui.OK_ONLY")) `
    -Name "p14.diagnose.sui.ten-entry-precu-order"

Assert-Contract -Condition (
    $handler.Contains("DIAGNOSE_RANGE = 6.0f") -and
    $handler.Contains("!isMob(target)") -and
    $handler.Contains("!ai_lib.isDroid(target)") -and
    $handler.Contains("!ai_lib.isAndroid(target)") -and
    $handler.Contains("!vehicle.isDriveableVehicle(target)") -and
    $handler.Contains("factions.pvpDoAllowedHelpCheck") -and
    -not $handler.Contains("canSee(self, target)") -and
    -not $handler.Contains("setAttrib(target") -and
    -not $handler.Contains("addWound(target")) `
    -Name "p14.diagnose.runtime.read-only-organic-gates"

Assert-Contract -Condition (
    $handler.Contains("utils.hasScriptVar(self, SUI_PID)") -and
    $handler.Contains("sui.closeSUI(self, oldPid)") -and
    $handler.Contains('"Patient " + patientName') -and
    $handler.Contains('"precu.diagnoseCommandFixture"') -and
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("ORIGINAL_CURRENT") -and
    $fixture.Contains("ORIGINAL_WOUNDS") -and
    $fixture.Contains("ORIGINAL_BATTLE_FATIGUE") -and
    $fixture.Contains("getIntArrayObjVar") -and
    -not $fixture.Contains("import script.library.sui") -and
    -not $fixture.Contains("sui.closeSUI(player")) `
    -Name "p14.diagnose.live.identity-reversible-and-console-safe"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 18) `
        -Name "p14.diagnose.status.ready"
    Assert-Contract -Condition (
        [string]$live.handlerOutcome -ceq "displayed" -and
        [int]$live.entryCount -eq 10 -and
        [int]$live.suiPid -ge 0 -and
        (@($live.observedWounds) -join ",") -ceq
            "11,22,33,44,55,66,77,88,99" -and
        [int]$live.observedBattleFatigue -eq 321 -and
        [int]$live.clientQueueCountAtAdmission -eq 0) `
        -Name "p14.diagnose.live.sui-and-values"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [int]$live.clientQueueCountAfterCleanup -eq 0) `
        -Name "p14.diagnose.live.cleanup-restored"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 diagnose contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 diagnose command contract passed."
