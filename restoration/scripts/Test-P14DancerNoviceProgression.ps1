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
        p14DancerNoviceProgression)
) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path

function Import-Tab([string]$Path)
{
    $lines = Get-Content $Path
    return @(@($lines[0]) + @($lines | Select-Object -Skip 2) |
        ConvertFrom-Csv -Delimiter "`t")
}

$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$performancePath = Join-Path $source (
    [string]$contract.sourceFiles.performanceTable)
$fixturePath = Join-Path $source ([string]$contract.sourceFiles.fixture)
foreach ($path in @($skillsPath, $performancePath, $fixturePath))
{
    if (-not (Test-Path $path -PathType Leaf))
    {
        throw "Required Dancer novice source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$performances = Import-Tab $performancePath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$rootRow = @($skills | Where-Object NAME -CEQ ([string]$e.root.name))
$novice = @($skills | Where-Object NAME -CEQ ([string]$e.novice.name))
$popular = @($performances |
    Where-Object performanceName -CEQ "popular")
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer novice checks:"
Assert-Contract (
    $rootRow.Count -eq 1 -and
    [string]$rootRow[0].PARENT -ceq [string]$e.root.parent -and
    [string]$rootRow[0].GRAPH_TYPE -ceq [string]$e.root.graphType -and
    [string]$rootRow[0].IS_PROFESSION -ceq
        [string]$e.root.isProfession -and
    [string]$rootRow[0].SEARCHABLE -ceq [string]$e.root.searchable
) "p14.dancer-novice.root.authentic"

Assert-Contract (
    $novice.Count -eq 1 -and
    [string]$novice[0].PARENT -ceq [string]$e.novice.parent -and
    [string]$novice[0].GRAPH_TYPE -ceq [string]$e.novice.graphType -and
    [string]$novice[0].IS_TITLE -ceq [string]$e.novice.isTitle -and
    [string]$novice[0].MONEY_REQUIRED -ceq
        [string]$e.novice.moneyRequired -and
    [string]$novice[0].POINTS_REQUIRED -ceq
        [string]$e.novice.pointsRequired -and
    [string]$novice[0].SKILLS_REQUIRED -ceq
        [string]$e.novice.skillsRequired -and
    [string]$novice[0].XP_TYPE -ceq [string]$e.novice.xpType -and
    [string]$novice[0].XP_COST -ceq [string]$e.novice.xpCost -and
    [string]$novice[0].XP_CAP -ceq [string]$e.novice.xpCap -and
    [string]$novice[0].COMMANDS -ceq [string]$e.novice.commands -and
    [string]$novice[0].SKILL_MODS -ceq [string]$e.novice.skillMods -and
    [string]$novice[0].SCHEMATICS_GRANTED -ceq
        [string]$e.novice.schematics -and
    [string]$novice[0].SEARCHABLE -ceq [string]$e.novice.searchable
) "p14.dancer-novice.skill.authentic"

Assert-Contract (
    $popular.Count -eq 1 -and
    [string]$popular[0].requiredDance -ceq
        [string]$e.popularDance.requiredDance -and
    [int]$popular[0].danceVisualId -eq
        [int]$e.popularDance.danceVisualId -and
    [int]$popular[0].actionPointsPerLoop -eq
        [int]$e.popularDance.actionPointsPerLoop -and
    [int]$popular[0].loopDuration -eq
        [int]$e.popularDance.loopDuration -and
    [string]$popular[0].requiredSkillMod -ceq
        [string]$e.popularDance.requiredSkillMod -and
    [int]$popular[0].requiredSkillModValue -eq
        [int]$e.popularDance.requiredSkillModValue
) "p14.dancer-novice.popular.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerNovice") -and
    $fixture.Contains("purchaseDancerNovice") -and
    $fixture.Contains("observePopularStart") -and
    $fixture.Contains("observeSurrenderDancerNovice") -and
    $fixture.Contains("NGE_PROP_SCHEMATIC")
) "p14.dancer-novice.fixture.production-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 48
    ) "p14.dancer-novice.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 50000 -and
        [int]$live.purchase.pointCost -eq 6 -and
        [string]$live.purchase.commandsAfter -ceq "111" -and
        [string]$live.purchase.ngeCommandsAfter -ceq "000" -and
        [int]$live.purchase.danceAbilityDelta -eq 10 -and
        [int]$live.purchase.danceWoundDelta -eq 5 -and
        [int]$live.purchase.danceShockDelta -eq 10 -and
        [int]$live.purchase.danceMindDelta -eq 10 -and
        [int]$live.purchase.xpCapAfter -eq 350000 -and
        [int]$live.popular.performanceIndex -eq 291 -and
        [int]$live.popular.quicknessAdjustedActionCost -eq 36 -and
        [bool]$live.popular.stopCompleted -and
        [bool]$live.surrender.entertainerDanceFourRetained -and
        [bool]$live.surrender.entertainerHealingFourRetained -and
        [int]$live.surrender.pointsRecovered -eq 6 -and
        [int]$live.surrender.danceFourXpCapAfter -eq 150000 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-novice.live-purchase-performance-surrender"
}
if ($failures.Count)
{
    throw "Dancer novice contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer novice contract passed."
