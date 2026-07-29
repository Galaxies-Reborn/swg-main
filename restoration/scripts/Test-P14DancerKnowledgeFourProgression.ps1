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
        p14DancerKnowledgeFourProgression)
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
        throw "Required Dancer Knowledge IV source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$knowledge = @($skills |
    Where-Object NAME -CEQ ([string]$e.knowledgeFour.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Knowledge IV checks:"
Assert-Contract (
    $knowledge.Count -eq 1 -and
    [string]$knowledge[0].PARENT -ceq
        [string]$e.knowledgeFour.parent -and
    [string]$knowledge[0].GRAPH_TYPE -ceq
        [string]$e.knowledgeFour.graphType -and
    [string]$knowledge[0].IS_TITLE -ceq
        [string]$e.knowledgeFour.isTitle -and
    [string]$knowledge[0].IS_PROFESSION -ceq
        [string]$e.knowledgeFour.isProfession -and
    [string]$knowledge[0].MONEY_REQUIRED -ceq
        [string]$e.knowledgeFour.moneyRequired -and
    [string]$knowledge[0].POINTS_REQUIRED -ceq
        [string]$e.knowledgeFour.pointsRequired -and
    [string]$knowledge[0].SKILLS_REQUIRED -ceq
        [string]$e.knowledgeFour.skillsRequired -and
    [string]$knowledge[0].XP_TYPE -ceq
        [string]$e.knowledgeFour.xpType -and
    [string]$knowledge[0].XP_COST -ceq
        [string]$e.knowledgeFour.xpCost -and
    [string]$knowledge[0].XP_CAP -ceq
        [string]$e.knowledgeFour.xpCap -and
    [string]$knowledge[0].COMMANDS -ceq
        [string]$e.knowledgeFour.commands -and
    [string]$knowledge[0].SKILL_MODS -ceq
        [string]$e.knowledgeFour.skillMods -and
    [string]$knowledge[0].SEARCHABLE -ceq
        [string]$e.knowledgeFour.searchable
) "p14.dancer-knowledge-four.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerKnowledgeFour") -and
    $fixture.Contains("purchaseDancerKnowledgeFour") -and
    $fixture.Contains("observeSurrenderDancerKnowledgeFour") -and
    $fixture.Contains("BREAKDANCE_TWO_ABILITY") -and
    $fixture.Contains("EXOTIC_ABILITY") -and
    $fixture.Contains("EXOTIC_TWO_ABILITY")
) "p14.dancer-knowledge-four.fixture-command-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 64
    ) "p14.dancer-knowledge-four.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 225000 -and
        [int]$live.purchase.pointCost -eq 2 -and
        [int]$live.purchase.danceAbilityDelta -eq 10 -and
        [string]$live.purchase.knowledgeFourCommandsAfter -ceq "111" -and
        [int]$live.purchase.danceXpCapAfter -eq 900000 -and
        [bool]$live.surrender.dancerKnowledgeThreeRetained -and
        [int]$live.surrender.pointsRecovered -eq 2 -and
        [string]$live.surrender.knowledgeThreeCommandsAfter -ceq "11" -and
        [string]$live.surrender.knowledgeFourCommandsAfter -ceq "000" -and
        [int]$live.surrender.knowledgeThreeXpCapAfter -eq 900000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-knowledge-four.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Knowledge IV contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Knowledge IV contract passed."
