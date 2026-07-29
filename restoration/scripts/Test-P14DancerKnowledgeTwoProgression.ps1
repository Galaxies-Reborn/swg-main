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
        p14DancerKnowledgeTwoProgression)
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
        throw "Required Dancer Knowledge II source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$knowledge = @($skills |
    Where-Object NAME -CEQ ([string]$e.knowledgeTwo.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Knowledge II checks:"
Assert-Contract (
    $knowledge.Count -eq 1 -and
    [string]$knowledge[0].PARENT -ceq
        [string]$e.knowledgeTwo.parent -and
    [string]$knowledge[0].GRAPH_TYPE -ceq
        [string]$e.knowledgeTwo.graphType -and
    [string]$knowledge[0].IS_TITLE -ceq
        [string]$e.knowledgeTwo.isTitle -and
    [string]$knowledge[0].IS_PROFESSION -ceq
        [string]$e.knowledgeTwo.isProfession -and
    [string]$knowledge[0].MONEY_REQUIRED -ceq
        [string]$e.knowledgeTwo.moneyRequired -and
    [string]$knowledge[0].POINTS_REQUIRED -ceq
        [string]$e.knowledgeTwo.pointsRequired -and
    [string]$knowledge[0].SKILLS_REQUIRED -ceq
        [string]$e.knowledgeTwo.skillsRequired -and
    [string]$knowledge[0].XP_TYPE -ceq
        [string]$e.knowledgeTwo.xpType -and
    [string]$knowledge[0].XP_COST -ceq
        [string]$e.knowledgeTwo.xpCost -and
    [string]$knowledge[0].XP_CAP -ceq
        [string]$e.knowledgeTwo.xpCap -and
    [string]$knowledge[0].COMMANDS -ceq
        [string]$e.knowledgeTwo.commands -and
    [string]$knowledge[0].SKILL_MODS -ceq
        [string]$e.knowledgeTwo.skillMods -and
    [string]$knowledge[0].SEARCHABLE -ceq
        [string]$e.knowledgeTwo.searchable
) "p14.dancer-knowledge-two.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerKnowledgeTwo") -and
    $fixture.Contains("purchaseDancerKnowledgeTwo") -and
    $fixture.Contains("observeSurrenderDancerKnowledgeTwo") -and
    $fixture.Contains("POPLOCK_TWO_ABILITY") -and
    $fixture.Contains("TUMBLE_TWO_ABILITY")
) "p14.dancer-knowledge-two.fixture-command-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 62
    ) "p14.dancer-knowledge-two.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 125000 -and
        [int]$live.purchase.pointCost -eq 4 -and
        [int]$live.purchase.danceAbilityDelta -eq 10 -and
        [string]$live.purchase.knowledgeTwoCommandsAfter -ceq "11" -and
        [int]$live.purchase.danceXpCapAfter -eq 700000 -and
        [bool]$live.surrender.dancerKnowledgeOneRetained -and
        [int]$live.surrender.pointsRecovered -eq 4 -and
        [string]$live.surrender.knowledgeOneCommandsAfter -ceq "110" -and
        [string]$live.surrender.knowledgeTwoCommandsAfter -ceq "00" -and
        [int]$live.surrender.knowledgeOneXpCapAfter -eq 500000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-knowledge-two.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Knowledge II contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Knowledge II contract passed."
