[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content (
    Join-Path $root ([string]$manifest.contracts.
        p14DancerAbilityFourProgression)
) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path

function Import-Tab([string]$Path)
{
    $lines = Get-Content $Path
    return @(@($lines[0]) + @($lines | Select-Object -Skip 2) |
        ConvertFrom-Csv -Delimiter "`t")
}

$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$fixturePath = Join-Path $source ([string]$contract.sourceFiles.fixture)
foreach ($path in @($skillsPath, $fixturePath))
{
    if (-not (Test-Path $path -PathType Leaf))
    {
        throw "Required Dancer Ability IV source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$ability = @($skills |
    Where-Object NAME -CEQ ([string]$e.abilityFour.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Ability IV checks:"
Assert-Contract (
    $ability.Count -eq 1 -and
    [string]$ability[0].PARENT -ceq [string]$e.abilityFour.parent -and
    [string]$ability[0].GRAPH_TYPE -ceq
        [string]$e.abilityFour.graphType -and
    [string]$ability[0].IS_TITLE -ceq
        [string]$e.abilityFour.isTitle -and
    [string]$ability[0].IS_PROFESSION -ceq
        [string]$e.abilityFour.isProfession -and
    [string]$ability[0].MONEY_REQUIRED -ceq
        [string]$e.abilityFour.moneyRequired -and
    [string]$ability[0].POINTS_REQUIRED -ceq
        [string]$e.abilityFour.pointsRequired -and
    [string]$ability[0].SKILLS_REQUIRED -ceq
        [string]$e.abilityFour.skillsRequired -and
    [string]$ability[0].XP_TYPE -ceq [string]$e.abilityFour.xpType -and
    [string]$ability[0].XP_COST -ceq [string]$e.abilityFour.xpCost -and
    [string]$ability[0].XP_CAP -ceq [string]$e.abilityFour.xpCap -and
    [string]$ability[0].COMMANDS -ceq
        [string]$e.abilityFour.commands -and
    [string]$ability[0].SKILL_MODS -ceq
        [string]$e.abilityFour.skillMods -and
    [string]$ability[0].SCHEMATICS_GRANTED -ceq
        [string]$e.abilityFour.schematics -and
    [string]$ability[0].SEARCHABLE -ceq
        [string]$e.abilityFour.searchable
) "p14.dancer-ability-four.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerAbilityFour") -and
    $fixture.Contains("purchaseDancerAbilityFour") -and
    $fixture.Contains("observeSurrenderDancerAbilityFour") -and
    $fixture.Contains("NGE_FLOOR_LIGHTS_ABILITY")
) "p14.dancer-ability-four.fixture.production-and-reversible"

if ($Expectation -ceq "Ready")
{
    $b = $contract.buildEvidence
    $live = $contract.liveEvidence
    $patch = Join-Path $root (
        [string]$b.overlayPatch -replace "^restoration/", "")
    Assert-Contract (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.overlayPatchSha256 -and
        (Get-FileHash $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.sourceSha256.
                "precu_entertainer_dance_one_fixture.java" -and
        (Get-FileHash $skillsPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.sourceSha256."skills.tab" -and
        [int]$b.clientNativeBuild.protocolVersion -eq 52
    ) "p14.dancer-ability-four.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 225000 -and
        [int]$live.purchase.pointCost -eq 2 -and
        [string]$live.purchase.ngeCommandAfter -ceq "0" -and
        [int]$live.purchase.danceMindDelta -eq 25 -and
        [int]$live.purchase.xpCapAfter -eq 900000 -and
        [bool]$live.surrender.dancerAbilityThreeRetained -and
        [string]$live.surrender.abilityThreeCommandsAfter -ceq "10" -and
        [string]$live.surrender.floorLightsAfter -ceq "0" -and
        [int]$live.surrender.pointsRecovered -eq 2 -and
        [int]$live.surrender.abilityThreeXpCapAfter -eq 900000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-ability-four.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Ability IV contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Ability IV contract passed."
