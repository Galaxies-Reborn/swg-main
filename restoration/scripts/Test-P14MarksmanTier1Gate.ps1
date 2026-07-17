[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14MarksmanTier1Matrix)) -Raw | ConvertFrom-Json
$headShotContract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14HeadShot1)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized Marksman tier-I source is missing: $path"
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

function Get-ModeledCost
{
    param(
        [Parameter(Mandatory = $true)][int]$Governor,
        [Parameter(Mandatory = $true)][int]$BaseCost,
        [Parameter(Mandatory = $true)][double]$Multiplier
    )

    $cost = $BaseCost * $Multiplier
    $cost -= (($Governor - 300.0) / 1200.0) * $cost
    return [Math]::Max(0, [int][Math]::Truncate($cost))
}

Write-Host "Publish 14.1 Marksman tier-I expansion gate checks:"
Assert-Contract -Condition ([string]$contract.status -ceq "blocked") -Name "p14.marksman-tier1.gate.blocked"
Assert-Contract -Condition ([bool]$contract.semanticReference.currentMatchesPinned) -Name "p14.marksman-tier1.core3.current-matches-pin"
Assert-Contract -Condition (-not [bool]$contract.excludedPriorReconstruction.balanceAuthority) -Name "p14.marksman-tier1.prior-balance-reconstruction-excluded"
Assert-Contract -Condition ([string]$headShotContract.status -ceq "ready") -Name "p14.marksman-tier1.prerequisite.headshot1-ready"
Assert-Contract -Condition (
    @($headShotContract.acceptanceBoundary.deferredToMarksmanTier1Matrix).Count -eq 2) -Name "p14.marksman-tier1.prerequisite.speed-and-accuracy-deferred"

$blockedTokens = @($contract.materializerPolicy.rejectPatchTextWhileBlocked | ForEach-Object { [string]$_ })
Assert-Contract -Condition (
    $blockedTokens.Count -eq 2 -and
    $blockedTokens -contains "bodyShot1" -and
    $blockedTokens -contains "legShot1") -Name "p14.marksman-tier1.materializer.blocks-both-candidates"

$commandRows = @(Import-SwgTab -Path $paths.commandTable)
$combatRows = @(Import-SwgTab -Path $paths.combatData)
$skillRows = @(Import-SwgTab -Path $paths.skillTable)
$overrideRows = @(Import-SwgTab -Path $paths.combatOverrides)
$weaponRows = @(Import-SwgTab -Path $paths.weaponCosts)
$combatActions = Get-Content -LiteralPath $paths.combatActions -Raw

$weapons = @($contract.commands | ForEach-Object { [string]$_.weaponType })
$pools = @($contract.commands | ForEach-Object { [string]$_.targetPool })
Assert-Contract -Condition (
    ($weapons -join ',') -ceq "PISTOL,CARBINE" -and
    ($pools -join ',') -ceq "HEALTH,ACTION") -Name "p14.marksman-tier1.matrix.pistol-health-carbine-action"

foreach ($candidate in @($contract.commands))
{
    $name = [string]$candidate.name
    $skillName = [string]$candidate.skill
    $templateName = [string]$candidate.weaponTemplate
    $commandMatches = @($commandRows | Where-Object { [string]$_.commandName -ceq $name })
    $combatMatches = @($combatRows | Where-Object { [string]$_.actionName -ceq $name })
    $overrideMatches = @($overrideRows | Where-Object { [string]$_.actionName -ceq $name })
    $weaponMatches = @($weaponRows | Where-Object { [string]$_.templateName -ceq $templateName })
    $skillMatches = @($skillRows | Where-Object { [string]$_.NAME -ceq $skillName })

    Assert-Contract -Condition (
        $commandMatches.Count -eq 0 -and
        $combatMatches.Count -eq 0 -and
        $overrideMatches.Count -eq 0 -and
        $weaponMatches.Count -eq 0 -and
        -not $combatActions.Contains("public int $name(")) -Name "p14.marksman-tier1.$name.production-inert-while-blocked"

    $grants = if ($skillMatches.Count -eq 1) {
        @(([string]$skillMatches[0].COMMANDS).Trim('"').Split(',') | Where-Object { $_ -ne "" })
    } else {
        @()
    }
    Assert-Contract -Condition (
        $skillMatches.Count -eq 1 -and
        @($grants | Where-Object { $_ -ceq $name }).Count -eq 0) -Name "p14.marksman-tier1.$name.skill-grant-inert-while-blocked"

    $costs = @(
        Get-ModeledCost -Governor ([int]$contract.fixture.governingStrength) -BaseCost ([int]$contract.fixture.baseHealthCost) -Multiplier ([double]$candidate.healthCostMultiplier)
        Get-ModeledCost -Governor ([int]$contract.fixture.governingQuickness) -BaseCost ([int]$contract.fixture.baseActionCost) -Multiplier ([double]$candidate.actionCostMultiplier)
        Get-ModeledCost -Governor ([int]$contract.fixture.governingFocus) -BaseCost ([int]$contract.fixture.baseMindCost) -Multiplier ([double]$candidate.mindCostMultiplier)
    )
    $expected = @(
        [int]$candidate.expectedFixtureHealthCost,
        [int]$candidate.expectedFixtureActionCost,
        [int]$candidate.expectedFixtureMindCost
    )
    Assert-Contract -Condition (($costs -join ',') -ceq ($expected -join ',')) -Name "p14.marksman-tier1.$name.modeled-fixture-cost"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Marksman tier-I expansion gate failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Marksman tier-I expansion remains safely blocked."
