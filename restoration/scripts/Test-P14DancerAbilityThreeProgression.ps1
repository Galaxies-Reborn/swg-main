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
        p14DancerAbilityThreeProgression)
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
        throw "Required Dancer Ability III source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$ability = @($skills |
    Where-Object NAME -CEQ ([string]$e.abilityThree.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Ability III checks:"
Assert-Contract (
    $ability.Count -eq 1 -and
    [string]$ability[0].PARENT -ceq [string]$e.abilityThree.parent -and
    [string]$ability[0].GRAPH_TYPE -ceq
        [string]$e.abilityThree.graphType -and
    [string]$ability[0].IS_TITLE -ceq
        [string]$e.abilityThree.isTitle -and
    [string]$ability[0].IS_PROFESSION -ceq
        [string]$e.abilityThree.isProfession -and
    [string]$ability[0].MONEY_REQUIRED -ceq
        [string]$e.abilityThree.moneyRequired -and
    [string]$ability[0].POINTS_REQUIRED -ceq
        [string]$e.abilityThree.pointsRequired -and
    [string]$ability[0].SKILLS_REQUIRED -ceq
        [string]$e.abilityThree.skillsRequired -and
    [string]$ability[0].XP_TYPE -ceq [string]$e.abilityThree.xpType -and
    [string]$ability[0].XP_COST -ceq [string]$e.abilityThree.xpCost -and
    [string]$ability[0].XP_CAP -ceq [string]$e.abilityThree.xpCap -and
    [string]$ability[0].COMMANDS -ceq
        [string]$e.abilityThree.commands -and
    [string]$ability[0].SKILL_MODS -ceq
        [string]$e.abilityThree.skillMods -and
    [string]$ability[0].SCHEMATICS_GRANTED -ceq
        [string]$e.abilityThree.schematics -and
    [string]$ability[0].SEARCHABLE -ceq
        [string]$e.abilityThree.searchable
) "p14.dancer-ability-three.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerAbilityThree") -and
    $fixture.Contains("purchaseDancerAbilityThree") -and
    $fixture.Contains("observeSurrenderDancerAbilityThree") -and
    $fixture.Contains("SMOKE_BOMB_ABILITY") -and
    $fixture.Contains("NGE_CENTER_STAGE_ABILITY")
) "p14.dancer-ability-three.fixture.production-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 51
    ) "p14.dancer-ability-three.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 175000 -and
        [int]$live.purchase.pointCost -eq 3 -and
        [string]$live.purchase.commandsAfter -ceq "10" -and
        [int]$live.purchase.danceMindDelta -eq 20 -and
        [int]$live.purchase.xpCapAfter -eq 900000 -and
        [bool]$live.surrender.dancerAbilityTwoRetained -and
        [string]$live.surrender.abilityTwoCommandsAfter -ceq "10" -and
        [string]$live.surrender.abilityThreeCommandsAfter -ceq "00" -and
        [int]$live.surrender.pointsRecovered -eq 3 -and
        [int]$live.surrender.abilityTwoXpCapAfter -eq 700000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-ability-three.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Ability III contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Ability III contract passed."
