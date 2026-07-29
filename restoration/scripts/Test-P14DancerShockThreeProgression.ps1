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
        p14DancerShockThreeProgression)
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
        throw "Required Dancer Shock III source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$shock = @($skills |
    Where-Object NAME -CEQ ([string]$e.shockThree.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Shock III checks:"
Assert-Contract (
    $shock.Count -eq 1 -and
    [string]$shock[0].PARENT -ceq [string]$e.shockThree.parent -and
    [string]$shock[0].GRAPH_TYPE -ceq
        [string]$e.shockThree.graphType -and
    [string]$shock[0].IS_TITLE -ceq
        [string]$e.shockThree.isTitle -and
    [string]$shock[0].IS_PROFESSION -ceq
        [string]$e.shockThree.isProfession -and
    [string]$shock[0].MONEY_REQUIRED -ceq
        [string]$e.shockThree.moneyRequired -and
    [string]$shock[0].POINTS_REQUIRED -ceq
        [string]$e.shockThree.pointsRequired -and
    [string]$shock[0].SKILLS_REQUIRED -ceq
        [string]$e.shockThree.skillsRequired -and
    [string]$shock[0].XP_TYPE -ceq [string]$e.shockThree.xpType -and
    [string]$shock[0].XP_COST -ceq [string]$e.shockThree.xpCost -and
    [string]$shock[0].XP_CAP -ceq [string]$e.shockThree.xpCap -and
    [string]$shock[0].COMMANDS -ceq [string]$e.shockThree.commands -and
    [string]$shock[0].SKILL_MODS -ceq
        [string]$e.shockThree.skillMods -and
    [string]$shock[0].SCHEMATICS_GRANTED -ceq
        [string]$e.shockThree.schematics -and
    [string]$shock[0].SEARCHABLE -ceq
        [string]$e.shockThree.searchable
) "p14.dancer-shock-three.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerShockThree") -and
    $fixture.Contains("purchaseDancerShockThree") -and
    $fixture.Contains("observeSurrenderDancerShockThree") -and
    $fixture.Contains("NGE_DOUBLE_MAGIC_RIBBON_ABILITY") -and
    $fixture.Contains("NGE_DOUBLE_MAGIC_RIBBON_SCHEMATIC") -and
    $fixture.Contains("PROP_ASSEMBLY_MOD")
) "p14.dancer-shock-three.fixture-production-negative-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 59
    ) "p14.dancer-shock-three.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.healingXpBefore -eq 100000 -and
        [int]$live.purchase.pointCost -eq 3 -and
        [int]$live.purchase.danceShockDelta -eq 20 -and
        [int]$live.purchase.propAssemblyDelta -eq 0 -and
        [string]$live.purchase.ngePropCommandAfter -ceq "0" -and
        -not [bool]$live.purchase.ngeRepresentativeSchematicAfter -and
        [int]$live.purchase.healingXpCapAfter -eq 500000 -and
        [bool]$live.surrender.dancerShockTwoRetained -and
        [int]$live.surrender.pointsRecovered -eq 3 -and
        [int]$live.surrender.shockTwoXpCapAfter -eq 400000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [int]$live.surrender.propAssemblyDeltaAfter -eq 0 -and
        [string]$live.surrender.ngePropCommandAfter -ceq "0" -and
        -not [bool]$live.surrender.ngeRepresentativeSchematicAfter -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-shock-three.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Shock III contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Shock III contract passed."
