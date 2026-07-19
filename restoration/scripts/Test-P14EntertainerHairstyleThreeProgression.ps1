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
        p14EntertainerHairstyleThreeProgression)
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
        throw "Required Hairstyle III source is missing: $path"
    }
}

$e = $contract.publish14Evidence.hairstyleThree
$row = @(Import-Tab $skillsPath |
    Where-Object NAME -CEQ ([string]$e.name))
$fixture = Get-Content $fixturePath -Raw
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Entertainer Hairstyle III checks:"
Assert-Contract (
    $row.Count -eq 1 -and
    [string]$row[0].PARENT -ceq [string]$e.parent -and
    [string]$row[0].GRAPH_TYPE -ceq [string]$e.graphType -and
    [string]$row[0].MONEY_REQUIRED -ceq [string]$e.moneyRequired -and
    [string]$row[0].POINTS_REQUIRED -ceq [string]$e.pointsRequired -and
    [string]$row[0].SKILLS_REQUIRED -ceq [string]$e.skillsRequired -and
    [string]$row[0].XP_TYPE -ceq [string]$e.xpType -and
    [string]$row[0].XP_COST -ceq [string]$e.xpCost -and
    [string]$row[0].XP_CAP -ceq [string]$e.xpCap -and
    [string]$row[0].COMMANDS -ceq [string]$e.commands -and
    [string]$row[0].SKILL_MODS -ceq [string]$e.skillMods -and
    [string]$row[0].SCHEMATICS_GRANTED -ceq "" -and
    [string]$row[0].SEARCHABLE -ceq [string]$e.searchable
) "p14.entertainer-hairstyle-three.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareThree") -and
    $fixture.Contains("purchaseThree") -and
    $fixture.Contains("observeSurrenderThree") -and
    $fixture.Contains("HAIR_THREE_COMMAND")
) "p14.entertainer-hairstyle-three.fixture.production-and-reversible"

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
                "precu_entertainer_hairstyle_fixture.java" -and
        (Get-FileHash $skillsPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.sourceSha256."skills.tab" -and
        [int]$b.clientNativeBuild.protocolVersion -eq 46
    ) "p14.entertainer-hairstyle-three.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.imageDesignerXpBefore -eq 10000 -and
        [int]$live.purchase.pointCost -eq 4 -and
        [bool]$live.purchase.tierThreeCommandAfter -and
        [int]$live.purchase.hairDelta -eq 1 -and
        [int]$live.purchase.faceDelta -eq 0 -and
        [int]$live.purchase.markingsDelta -eq 0 -and
        [int]$live.purchase.xpCapAfter -eq 30000 -and
        [bool]$live.surrender.hairstyleOneRetained -and
        [bool]$live.surrender.hairstyleTwoRetained -and
        [bool]$live.surrender.tierOneCommandAfter -and
        [bool]$live.surrender.tierTwoCommandAfter -and
        -not [bool]$live.surrender.tierThreeCommandAfter -and
        [int]$live.surrender.pointsRecovered -eq 4 -and
        [int]$live.surrender.hairstyleTwoXpCapAfter -eq 20000 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.entertainer-hairstyle-three.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Hairstyle III contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Entertainer Hairstyle III contract passed."
