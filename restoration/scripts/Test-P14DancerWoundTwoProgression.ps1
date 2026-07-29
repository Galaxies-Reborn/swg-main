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
        p14DancerWoundTwoProgression)
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
        throw "Required Dancer Wound II source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$wound = @($skills |
    Where-Object NAME -CEQ ([string]$e.woundTwo.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Wound II checks:"
Assert-Contract (
    $wound.Count -eq 1 -and
    [string]$wound[0].PARENT -ceq [string]$e.woundTwo.parent -and
    [string]$wound[0].GRAPH_TYPE -ceq
        [string]$e.woundTwo.graphType -and
    [string]$wound[0].IS_TITLE -ceq
        [string]$e.woundTwo.isTitle -and
    [string]$wound[0].IS_PROFESSION -ceq
        [string]$e.woundTwo.isProfession -and
    [string]$wound[0].MONEY_REQUIRED -ceq
        [string]$e.woundTwo.moneyRequired -and
    [string]$wound[0].POINTS_REQUIRED -ceq
        [string]$e.woundTwo.pointsRequired -and
    [string]$wound[0].SKILLS_REQUIRED -ceq
        [string]$e.woundTwo.skillsRequired -and
    [string]$wound[0].XP_TYPE -ceq [string]$e.woundTwo.xpType -and
    [string]$wound[0].XP_COST -ceq [string]$e.woundTwo.xpCost -and
    [string]$wound[0].XP_CAP -ceq [string]$e.woundTwo.xpCap -and
    [string]$wound[0].COMMANDS -ceq [string]$e.woundTwo.commands -and
    [string]$wound[0].SKILL_MODS -ceq
        [string]$e.woundTwo.skillMods -and
    [string]$wound[0].SCHEMATICS_GRANTED -ceq
        [string]$e.woundTwo.schematics -and
    [string]$wound[0].SEARCHABLE -ceq
        [string]$e.woundTwo.searchable
) "p14.dancer-wound-two.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerWoundTwo") -and
    $fixture.Contains("purchaseDancerWoundTwo") -and
    $fixture.Contains("observeSurrenderDancerWoundTwo") -and
    $fixture.Contains("ENTERTAINER_HEALING_XP")
) "p14.dancer-wound-two.fixture.production-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 54
    ) "p14.dancer-wound-two.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.healingXpBefore -eq 50000 -and
        [int]$live.purchase.pointCost -eq 4 -and
        [int]$live.purchase.danceWoundDelta -eq 10 -and
        [int]$live.purchase.healingXpCapAfter -eq 400000 -and
        [int]$live.purchase.danceXpCapAfter -eq 350000 -and
        [bool]$live.surrender.dancerWoundOneRetained -and
        [string]$live.surrender.dancerNoviceCommandsAfter -ceq "111" -and
        [int]$live.surrender.pointsRecovered -eq 4 -and
        [int]$live.surrender.woundOneXpCapAfter -eq 200000 -and
        [int]$live.surrender.danceXpCapAfter -eq 350000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-wound-two.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Wound II contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Wound II contract passed."
