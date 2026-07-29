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
            [string]$manifest.contracts.p14FirstAidCommand)
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
        throw "Required materialized first-aid source is missing: $path"
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
$row = Get-TableRow -Path $paths.commandTable -Key "firstAid"

Write-Host "Publish 14.1 first-aid command checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.source -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/FirstAidCommand.h") `
    -Name "p14.first-aid.core3.pinned-command"

Assert-Contract -Condition (
    $row.Matches.Count -eq 1 -and
    $row.Header.Count -eq 94 -and
    $row.Values.Count -eq 94 -and
    $row.Values[0] -ceq "firstAid" -and
    $row.Values[1] -ceq "combat" -and
    $row.Values[3] -ceq "cmdFirstAid" -and
    $row.Values[7] -ceq "5" -and
    $row.Values[8] -ceq "firstAid" -and
    $row.Values[72] -ceq "player.cmd.first_aid" -and
    $row.Values[73] -ceq "other" -and
    $row.Values[74] -ceq "optional" -and
    $row.Values[76] -ceq "2" -and
    $row.Values[83] -ceq "0" -and
    $row.Values[84] -ceq "ALL" -and
    $row.Values[85] -ceq "NONE" -and
    $row.Values[88] -ceq "5") `
    -Name "p14.first-aid.table.authentic-optional-nonqueue"

Assert-Contract -Condition (
    $handler.Contains("target = self;") -and
    $handler.Contains("FIRST_AID_RANGE = 6.0f") -and
    $handler.Contains("getDistance(self, target)") -and
    $handler.Contains("canSee(self, target)") -and
    $handler.Contains("pvpCanHelp(self, target)") -and
    $handler.Contains("factions.pvpDoAllowedHelpCheck") -and
    $handler.Contains("pet_lib.isCreaturePet(target)") -and
    $handler.Contains("!ai_lib.isDroid(target)") -and
    $handler.Contains("!pet_lib.isVehiclePet(target)")) `
    -Name "p14.first-aid.runtime.organic-six-meter-help-gates"

Assert-Contract -Condition (
    $handler.Contains('getSkillStatMod(self, "healing_injury_treatment")') -and
    $handler.Contains("int requestedReduction = treatment * 3;") -and
    $handler.Contains("dot.reduceDotTypeStrength(") -and
    $handler.Contains("dot.DOT_BLEEDING") -and
    $handler.Contains('"heal_self" : "heal_other"') -and
    $handler.Contains("healing.playHealDamageEffect") -and
    -not $handler.Contains("VAR_FIRSTAID_COST") -and
    -not $handler.Contains("consumeObject(") -and
    -not $handler.Contains("modifyExperiencePoints(")) `
    -Name "p14.first-aid.runtime.treatment-no-cost-no-xp"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("TREATMENT = 35") -and
    $fixture.Contains("BLEEDING_STRENGTH = 90") -and
    $fixture.Contains("dot.getDotScriptVarName(DOT_ID)") -and
    $fixture.Contains("dot.VAR_STRENGTH") -and
    $fixture.Contains("ORIGINAL_COMMAND") -and
    $fixture.Contains("ORIGINAL_MOD") -and
    $fixture.Contains("ORIGINAL_HEALTH") -and
    $fixture.Contains("ORIGINAL_MIND") -and
    $fixture.Contains("ORIGINAL_MEDICAL_XP") -and
    $fixture.Contains("incompleteSnapshot=true cleared=true") -and
    $fixture.Contains("String[] leaves =")) `
    -Name "p14.first-aid.live.identity-bound-reversible-fixture"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 20 -and
        [int]$live.clientQueueCountAtAdmission -eq 0) `
        -Name "p14.first-aid.status.ready"
    Assert-Contract -Condition (
        [int]$live.handlerCalls -eq 1 -and
        [long]$live.targetOid -eq 39008597 -and
        [int]$live.treatmentSkillMod -eq 35 -and
        [int]$live.requestedBleedingReduction -eq 105 -and
        [int]$live.reportedBleedingReduction -eq 90 -and
        -not [bool]$live.bleedingAfter -and
        [int]$live.mindCost -eq 0 -and
        [int]$live.healthBefore -eq [int]$live.healthAfter -and
        [int]$live.mindBefore -eq [int]$live.mindAfter -and
        [int]$live.medicalXpBefore -eq [int]$live.medicalXpAfter -and
        [string]$live.handlerOutcome -ceq "performed") `
        -Name "p14.first-aid.live.production-reduction-zero-cost"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [int]$live.clientQueueCountAfterCleanup -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup) `
        -Name "p14.first-aid.live.cleanup-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 first-aid contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 first-aid command contract passed."
