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
        p14DancerKnowledgeOneProgression)
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
        throw "Required Dancer Knowledge I source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$knowledge = @($skills |
    Where-Object NAME -CEQ ([string]$e.knowledgeOne.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Knowledge I checks:"
Assert-Contract (
    $knowledge.Count -eq 1 -and
    [string]$knowledge[0].PARENT -ceq
        [string]$e.knowledgeOne.parent -and
    [string]$knowledge[0].GRAPH_TYPE -ceq
        [string]$e.knowledgeOne.graphType -and
    [string]$knowledge[0].IS_TITLE -ceq
        [string]$e.knowledgeOne.isTitle -and
    [string]$knowledge[0].IS_PROFESSION -ceq
        [string]$e.knowledgeOne.isProfession -and
    [string]$knowledge[0].MONEY_REQUIRED -ceq
        [string]$e.knowledgeOne.moneyRequired -and
    [string]$knowledge[0].POINTS_REQUIRED -ceq
        [string]$e.knowledgeOne.pointsRequired -and
    [string]$knowledge[0].SKILLS_REQUIRED -ceq
        [string]$e.knowledgeOne.skillsRequired -and
    [string]$knowledge[0].XP_TYPE -ceq
        [string]$e.knowledgeOne.xpType -and
    [string]$knowledge[0].XP_COST -ceq
        [string]$e.knowledgeOne.xpCost -and
    [string]$knowledge[0].XP_CAP -ceq
        [string]$e.knowledgeOne.xpCap -and
    [string]$knowledge[0].COMMANDS -ceq
        [string]$e.knowledgeOne.commands -and
    [string]$knowledge[0].SKILL_MODS -ceq
        [string]$e.knowledgeOne.skillMods -and
    [string]$knowledge[0].SCHEMATICS_GRANTED -ceq
        [string]$e.knowledgeOne.schematics -and
    [string]$knowledge[0].SEARCHABLE -ceq
        [string]$e.knowledgeOne.searchable
) "p14.dancer-knowledge-one.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerKnowledgeOne") -and
    $fixture.Contains("purchaseDancerKnowledgeOne") -and
    $fixture.Contains("observeSurrenderDancerKnowledgeOne") -and
    $fixture.Contains("POPULAR_TWO_ABILITY") -and
    $fixture.Contains("TUMBLE_ABILITY") -and
    $fixture.Contains("NGE_BUNDUKI_TWO_ABILITY")
) "p14.dancer-knowledge-one.fixture-command-negative-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 61
    ) "p14.dancer-knowledge-one.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 87500 -and
        [int]$live.purchase.pointCost -eq 5 -and
        [int]$live.purchase.danceAbilityDelta -eq 10 -and
        [string]$live.purchase.popularTwoCommandAfter -ceq "1" -and
        [string]$live.purchase.tumbleCommandAfter -ceq "1" -and
        [string]$live.purchase.ngeBundukiTwoCommandAfter -ceq "0" -and
        [int]$live.purchase.danceXpCapAfter -eq 500000 -and
        [bool]$live.surrender.dancerNoviceRetained -and
        [int]$live.surrender.pointsRecovered -eq 5 -and
        [int]$live.surrender.dancerNoviceXpCapAfter -eq 350000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [string]$live.surrender.knowledgeCommandsAfter -ceq "000" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-knowledge-one.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Knowledge I contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Knowledge I contract passed."
