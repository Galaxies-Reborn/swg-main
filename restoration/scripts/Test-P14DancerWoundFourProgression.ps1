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
        p14DancerWoundFourProgression)
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
        throw "Required Dancer Wound IV source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$wound = @($skills |
    Where-Object NAME -CEQ ([string]$e.woundFour.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Wound IV checks:"
Assert-Contract (
    $wound.Count -eq 1 -and
    [string]$wound[0].PARENT -ceq [string]$e.woundFour.parent -and
    [string]$wound[0].GRAPH_TYPE -ceq
        [string]$e.woundFour.graphType -and
    [string]$wound[0].IS_TITLE -ceq
        [string]$e.woundFour.isTitle -and
    [string]$wound[0].IS_PROFESSION -ceq
        [string]$e.woundFour.isProfession -and
    [string]$wound[0].MONEY_REQUIRED -ceq
        [string]$e.woundFour.moneyRequired -and
    [string]$wound[0].POINTS_REQUIRED -ceq
        [string]$e.woundFour.pointsRequired -and
    [string]$wound[0].SKILLS_REQUIRED -ceq
        [string]$e.woundFour.skillsRequired -and
    [string]$wound[0].XP_TYPE -ceq [string]$e.woundFour.xpType -and
    [string]$wound[0].XP_COST -ceq [string]$e.woundFour.xpCost -and
    [string]$wound[0].XP_CAP -ceq [string]$e.woundFour.xpCap -and
    [string]$wound[0].COMMANDS -ceq [string]$e.woundFour.commands -and
    [string]$wound[0].SKILL_MODS -ceq
        [string]$e.woundFour.skillMods -and
    [string]$wound[0].SCHEMATICS_GRANTED -ceq
        [string]$e.woundFour.schematics -and
    [string]$wound[0].SEARCHABLE -ceq
        [string]$e.woundFour.searchable
) "p14.dancer-wound-four.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerWoundFour") -and
    $fixture.Contains("purchaseDancerWoundFour") -and
    $fixture.Contains("observeSurrenderDancerWoundFour") -and
    $fixture.Contains("ENTERTAINER_HEALING_XP")
) "p14.dancer-wound-four.fixture.production-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 56
    ) "p14.dancer-wound-four.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.healingXpBefore -eq 125000 -and
        [int]$live.purchase.pointCost -eq 2 -and
        [int]$live.purchase.danceWoundDelta -eq 15 -and
        [int]$live.purchase.healingXpCapAfter -eq 500000 -and
        [int]$live.purchase.danceXpCapAfter -eq 350000 -and
        [bool]$live.surrender.dancerWoundThreeRetained -and
        [string]$live.surrender.dancerNoviceCommandsAfter -ceq "111" -and
        [int]$live.surrender.pointsRecovered -eq 2 -and
        [int]$live.surrender.woundThreeXpCapAfter -eq 500000 -and
        [int]$live.surrender.danceXpCapAfter -eq 350000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-wound-four.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Wound IV contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Wound IV contract passed."
