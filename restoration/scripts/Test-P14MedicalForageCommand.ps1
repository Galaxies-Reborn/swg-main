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
            [string]$manifest.contracts.p14MedicalForageCommand)
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
        throw "Required materialized medical-forage source is missing: $path"
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
            Where-Object { (($_ -split "`t", -1)[0]) -ceq $Key })
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

$utility = Get-Content -LiteralPath $paths.playerUtility -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$row = Get-TableRow -Path $paths.commandTable -Key "medicalForage"
$skillRow =
    Get-TableRow -Path $paths.skillTable -Key "science_medic_novice"

Write-Host "Publish 14.1 medical-forage command checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.commandSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/MedicalForageCommand.h" -and
    [string]$contract.semanticReference.managerSource -ceq
        "MMOCoreORB/src/server/zone/managers/minigames/ForageManagerImplementation.cpp") `
    -Name "p14.medical-forage.core3.pinned-command-and-manager"

Assert-Contract -Condition (
    $row.Matches.Count -eq 1 -and
    $row.Header.Count -eq 94 -and
    $row.Values.Count -eq 94 -and
    $row.Values[0] -ceq "medicalForage" -and
    $row.Values[1] -ceq "" -and
    $row.Values[3] -ceq "medicalForage" -and
    $row.Values[4] -ceq "failForage" -and
    $row.Values[7] -ceq "2" -and
    $row.Values[8] -ceq "medicalForage" -and
    $row.Values[72] -ceq "" -and
    $row.Values[73] -ceq "other" -and
    $row.Values[74] -ceq "none" -and
    $row.Values[76] -ceq "2" -and
    $row.Values[83] -ceq "0" -and
    $row.Values[84] -ceq "ALL" -and
    $row.Values[85] -ceq "NONE" -and
    $row.Values[88] -ceq "0") `
    -Name "p14.medical-forage.table.authentic-targetless-nonqueue"

Assert-Contract -Condition (
    $skillRow.Matches.Count -eq 1 -and
    ([string]$skillRow.Values[21]).Contains("medicalForage") -and
    ([string]$skillRow.Values[22]).Contains("medical_foraging")) `
    -Name "p14.medical-forage.skill-grant-and-mod"

Assert-Contract -Condition (
    $utility.Contains("public int medicalForage(") -and
    $utility.Contains("public int failForage(") -and
    $utility.Contains("handlerForPrecuMedicalForaging") -and
    $utility.Contains("PRECU_MEDICAL_FORAGE_DELAY = 8.5f") -and
    $utility.Contains("PRECU_MEDICAL_FORAGE_BASE_ACTION = 50") -and
    $utility.Contains("getAttrib(player, QUICKNESS) - 300.0f") -and
    $utility.Contains("getAttrib(self, ACTION) <= actionCost") -and
    $utility.Contains("Math.abs(start.x - current.x) <= 2.0f") -and
    $utility.Contains("Math.abs(start.z - current.z) <= 2.0f") -and
    $utility.Contains("getState(self, STATE_COMBAT) > 0")) `
    -Name "p14.medical-forage.runtime.cost-delay-movement-combat"

Assert-Contract -Condition (
    $utility.Contains("PRECU_MEDICAL_FORAGE_AREA_SIZE = 10") -and
    $utility.Contains("PRECU_MEDICAL_FORAGE_AREA_USES = 3") -and
    $utility.Contains("PRECU_MEDICAL_FORAGE_AREA_EXPIRE = 1800") -and
    $utility.Contains("PRECU_MEDICAL_FORAGE_AREA_LIMIT = 120") -and
    $utility.Contains("uses[index] >= PRECU_MEDICAL_FORAGE_AREA_USES") -and
    $utility.Contains("oldExpirations[index] <= now")) `
    -Name "p14.medical-forage.runtime.per-player-area-lifecycle"

Assert-Contract -Condition (
    $utility.Contains('getSkillStatMod(self, "medical_foraging")') -and
    $utility.Contains("15 + (skillMod * 0.6f)") -and
    $utility.Contains("rand(0, 80)") -and
    $utility.Contains("if (successRoll > chance)") -and
    $utility.Contains("rand(0, 200)") -and
    $utility.Contains("if (rewardRoll < 40)") -and
    $utility.Contains("else if (rewardRoll < 110)") -and
    $utility.Contains("rewardRoll < 170 ? 1") -and
    $utility.Contains("rewardRoll < 200 ? 60 : 200") -and
    $utility.Contains('"flora_resources"') -and
    $utility.Contains("rand(10, 40)") -and
    $utility.Contains("loot.randomizeComponent(item, level, player)") -and
    $utility.Contains("loot.randomizeMedicine(item, level)")) `
    -Name "p14.medical-forage.runtime.chance-and-reward-bands"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains('forceSuccessRoll", 0') -and
    $fixture.Contains('forceRewardRoll", 120') -and
    $fixture.Contains('forceComponentIndex", 0') -and
    $fixture.Contains("ORIGINAL_ACTION") -and
    $fixture.Contains("ORIGINAL_LOCATION") -and
    $fixture.Contains("destroyObject(reward)") -and
    $fixture.Contains("utils.removeScriptVarTree(player, RUNTIME_ROOT)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    -Name "p14.medical-forage.live.identity-bound-reversible-fixture"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 19 -and
        [int]$live.clientQueueCountAtAdmission -eq 0) `
        -Name "p14.medical-forage.status.ready"
    Assert-Contract -Condition (
        [int]$live.handlerCalls -eq 1 -and
        [int]$live.elapsedGameSeconds -ge 8 -and
        [int]$live.actionBefore -eq 500 -and
        [int]$live.actionCost -eq 45 -and
        [int]$live.actionAfter -eq 455 -and
        [int]$live.medicalForagingSkillMod -eq 10 -and
        [int]$live.chance -eq 21 -and
        [int]$live.successRoll -eq 0 -and
        [int]$live.rewardRoll -eq 120 -and
        [string]$live.rewardType -ceq "component" -and
        [string]$live.rewardTemplate -ceq
            "object/tangible/component/chemistry/biologic_effect_controller.iff" -and
        [string]$live.handlerOutcome -ceq "rewarded") `
        -Name "p14.medical-forage.live.production-reward"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [int]$live.clientQueueCountAfterCleanup -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup) `
        -Name "p14.medical-forage.live.cleanup-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 medical-forage contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 medical-forage command contract passed."
