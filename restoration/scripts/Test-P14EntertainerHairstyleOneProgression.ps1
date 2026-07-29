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
        p14EntertainerHairstyleOneProgression)
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
        throw "Required Hairstyle I source is missing: $path"
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

$e = $contract.publish14Evidence.hairstyleOne
$row = @(Import-Tab $skillsPath |
    Where-Object NAME -CEQ ([string]$e.name))
$fixture = Get-Content $fixturePath -Raw

Write-Host "Publish 14.1 Entertainer Hairstyle I checks:"
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
) "p14.entertainer-hairstyle-one.skill.authentic"

Assert-Contract (
    $fixture.Contains("hasRequiredSkillsForSkillPurchase") -and
    $fixture.Contains("deductXpCostForSkillPurchase") -and
    $fixture.Contains("observeSurrender") -and
    $fixture.Contains("HAIR_ONE_COMMAND")
) "p14.entertainer-hairstyle-one.fixture.production-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 44
    ) "p14.entertainer-hairstyle-one.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.imageDesignerXpBefore -eq 1000 -and
        [int]$live.purchase.pointCost -eq 2 -and
        [bool]$live.purchase.privateHairCommandAfter -and
        [int]$live.purchase.hairDelta -eq 1 -and
        [int]$live.purchase.xpCapAfter -eq 10000 -and
        [bool]$live.surrender.serverRemoved -and
        -not [bool]$live.surrender.privateHairCommandAfter -and
        [int]$live.surrender.pointsRecovered -eq 2 -and
        [int]$live.surrender.noviceXpCapAfter -eq 2000 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.entertainer-hairstyle-one.live-purchase-surrender"
}

if ($failures.Count)
{
    throw "Hairstyle I contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Entertainer Hairstyle I contract passed."
