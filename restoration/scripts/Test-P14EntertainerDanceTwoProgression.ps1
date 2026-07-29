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
        p14EntertainerDanceTwoProgression)
) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path

function Import-Tab([string]$Path)
{
    $lines = Get-Content $Path
    return @(@($lines[0]) + @($lines | Select-Object -Skip 2) |
        ConvertFrom-Csv -Delimiter "`t")
}

$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$performancePath =
    Join-Path $source ([string]$contract.sourceFiles.performanceTable)
$fixturePath = Join-Path $source ([string]$contract.sourceFiles.fixture)
foreach ($path in @($skillsPath, $performancePath, $fixturePath))
{
    if (-not (Test-Path $path -PathType Leaf))
    {
        throw "Required Dance II source is missing: $path"
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

$e = $contract.publish14Evidence
$row = @(Import-Tab $skillsPath |
    Where-Object NAME -CEQ ([string]$e.danceTwo.name))
$dance = @(Import-Tab $performancePath |
    Where-Object performanceName -CEQ "rhythmic2")
$fixture = Get-Content $fixturePath -Raw

Write-Host "Publish 14.1 Entertainer Dance II checks:"
Assert-Contract (
    $row.Count -eq 1 -and
    [string]$row[0].PARENT -ceq [string]$e.danceTwo.parent -and
    [string]$row[0].GRAPH_TYPE -ceq [string]$e.danceTwo.graphType -and
    [string]$row[0].MONEY_REQUIRED -ceq
        [string]$e.danceTwo.moneyRequired -and
    [string]$row[0].POINTS_REQUIRED -ceq
        [string]$e.danceTwo.pointsRequired -and
    [string]$row[0].SKILLS_REQUIRED -ceq
        [string]$e.danceTwo.skillsRequired -and
    [string]$row[0].XP_TYPE -ceq [string]$e.danceTwo.xpType -and
    [string]$row[0].XP_COST -ceq [string]$e.danceTwo.xpCost -and
    [string]$row[0].XP_CAP -ceq [string]$e.danceTwo.xpCap -and
    [string]$row[0].COMMANDS -ceq [string]$e.danceTwo.commands -and
    [string]$row[0].SKILL_MODS -ceq [string]$e.danceTwo.skillMods -and
    [string]$row[0].SCHEMATICS_GRANTED -ceq "" -and
    [string]$row[0].SEARCHABLE -ceq [string]$e.danceTwo.searchable
) "p14.entertainer-dance-two.skill.authentic"

Assert-Contract (
    $dance.Count -eq 1 -and
    [string]$dance[0].requiredDance -ceq
        [string]$e.rhythmicTwo.requiredDance -and
    [int]$dance[0].actionPointsPerLoop -eq 32 -and
    [double]$dance[0].loopDuration -eq 10
) "p14.entertainer-dance-two.rhythmic-two.authentic"

Assert-Contract (
    $fixture.Contains("purchaseWithoutHolocron") -and
    $fixture.Contains("observeRhythmicTwoStart") -and
    $fixture.Contains("observeSurrenderTwo") -and
    $fixture.Contains("DANCE_TWO_POINT_COST")
) "p14.entertainer-dance-two.fixture.production-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 41
    ) "p14.entertainer-dance-two.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 5000 -and
        [int]$live.purchase.pointCost -eq 3 -and
        [string]$live.purchase.commandsAfter -ceq "11" -and
        [int]$live.purchase.xpCapAfter -eq 30000 -and
        [bool]$live.rhythmicTwo.startAccepted -and
        [int]$live.rhythmicTwo.performanceIndex -eq 284 -and
        [bool]$live.rhythmicTwo.stopCompleted -and
        [bool]$live.surrender.serverRemoved -and
        [bool]$live.surrender.danceOneRetained -and
        [string]$live.surrender.danceTwoCommandsAfter -ceq "00" -and
        [string]$live.surrender.danceOneCommandsAfter -ceq "11" -and
        [int]$live.surrender.pointsRecovered -eq 3 -and
        [int]$live.surrender.danceOneXpCapAfter -eq 10000 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.entertainer-dance-two.live-purchase-use-surrender"
}

if ($failures.Count)
{
    throw "Dance II contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Entertainer Dance II contract passed."
