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
        p14DancerMasterProgression)
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
        throw "Required Dancer master source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$master = @($skills |
    Where-Object NAME -CEQ ([string]$e.master.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer master checks:"
Assert-Contract (
    $master.Count -eq 1 -and
    [string]$master[0].PARENT -ceq [string]$e.master.parent -and
    [string]$master[0].GRAPH_TYPE -ceq
        [string]$e.master.graphType -and
    [string]$master[0].IS_TITLE -ceq [string]$e.master.isTitle -and
    [string]$master[0].IS_PROFESSION -ceq
        [string]$e.master.isProfession -and
    [string]$master[0].MONEY_REQUIRED -ceq
        [string]$e.master.moneyRequired -and
    [string]$master[0].POINTS_REQUIRED -ceq
        [string]$e.master.pointsRequired -and
    [string]$master[0].SKILLS_REQUIRED -ceq
        [string]$e.master.skillsRequired -and
    [string]$master[0].XP_TYPE -ceq [string]$e.master.xpType -and
    [string]$master[0].XP_COST -ceq [string]$e.master.xpCost -and
    [string]$master[0].XP_CAP -ceq [string]$e.master.xpCap -and
    [string]$master[0].COMMANDS -ceq [string]$e.master.commands -and
    [string]$master[0].SKILL_MODS -ceq [string]$e.master.skillMods -and
    [string]$master[0].SCHEMATICS_GRANTED -ceq
        [string]$e.master.schematics -and
    [string]$master[0].SEARCHABLE -ceq [string]$e.master.searchable
) "p14.dancer-master.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerMaster") -and
    $fixture.Contains("purchaseDancerMaster") -and
    $fixture.Contains("observeSurrenderDancerMaster") -and
    $fixture.Contains("NGE_DOUBLE_SPARK_RIBBON_ABILITY") -and
    $fixture.Contains("NGE_DOUBLE_SPARK_RIBBON_SCHEMATIC") -and
    $fixture.Contains("PRIVATE_PLACE_CANTINA_MOD") -and
    $fixture.Contains("PRIVATE_PLACE_THEATER_MOD")
) "p14.dancer-master.fixture-four-branch-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 65
    ) "p14.dancer-master.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 0 -and
        [int]$live.purchase.danceXpAfter -eq 0 -and
        [int]$live.purchase.pointCost -eq 1 -and
        [string]$live.purchase.masterCommandsAfter -ceq "11111" -and
        [string]$live.purchase.modifierDeltasAfter -ceq
            "10,15,25,25,7,7,100,100" -and
        [int]$live.purchase.propAssemblyDelta -eq 0 -and
        -not [bool]$live.purchase.ngePropCommandPresent -and
        -not [bool]$live.purchase.ngePropSchematicPresent -and
        [bool]$live.surrender.abilityFourRetained -and
        [bool]$live.surrender.woundFourRetained -and
        [bool]$live.surrender.knowledgeFourRetained -and
        [bool]$live.surrender.shockFourRetained -and
        [int]$live.surrender.pointsRecovered -eq 1 -and
        [string]$live.surrender.masterCommandsAfter -ceq "00000" -and
        [string]$live.surrender.modifierDeltasAfter -ceq
            "0,0,0,0,0,0,0,0" -and
        [int]$live.surrender.danceXpCapAfter -eq 900000 -and
        [int]$live.surrender.healingXpCapAfter -eq 500000 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-master.live-zero-xp-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer master contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer master contract passed."
