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
        p14EntertainerMasterProgression)
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
        throw "Required Entertainer master source is missing: $path"
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
    Where-Object NAME -CEQ ([string]$e.master.name))
$song = @(Import-Tab $performancePath |
    Where-Object {
        $_.performanceName -ceq "ceremonial" -and
        [int]$_.instrumentAudioId -eq 2
    })
$fixture = Get-Content $fixturePath -Raw

Write-Host "Publish 14.1 Entertainer master checks:"
Assert-Contract (
    $row.Count -eq 1 -and
    [string]$row[0].PARENT -ceq [string]$e.master.parent -and
    [string]$row[0].GRAPH_TYPE -ceq [string]$e.master.graphType -and
    [string]$row[0].MONEY_REQUIRED -ceq
        [string]$e.master.moneyRequired -and
    [string]$row[0].POINTS_REQUIRED -ceq
        [string]$e.master.pointsRequired -and
    [string]$row[0].SKILLS_REQUIRED -ceq
        [string]$e.master.skillsRequired -and
    [string]$row[0].XP_TYPE -ceq "" -and
    [string]$row[0].XP_COST -ceq "0" -and
    [string]$row[0].XP_CAP -ceq "0" -and
    [string]$row[0].COMMANDS -ceq [string]$e.master.commands -and
    [string]$row[0].SKILL_MODS -ceq [string]$e.master.skillMods -and
    [string]$row[0].SCHEMATICS_GRANTED -ceq "" -and
    [string]$row[0].SEARCHABLE -ceq [string]$e.master.searchable
) "p14.entertainer-master.skill.authentic"

Assert-Contract (
    $song.Count -eq 1 -and
    [string]$song[0].requiredSong -ceq
        [string]$e.ceremonialSlitherhorn.requiredSong -and
    [string]$song[0].requiredInstrument -ceq
        [string]$e.ceremonialSlitherhorn.requiredInstrument -and
    [int]$song[0].actionPointsPerLoop -eq 40 -and
    [double]$song[0].loopDuration -eq 5
) "p14.entertainer-master.ceremonial-slitherhorn.authentic"

Assert-Contract (
    $fixture.Contains("prepareMaster") -and
    $fixture.Contains("purchaseMaster") -and
    $fixture.Contains("observeCeremonialStart") -and
    $fixture.Contains("observeSurrenderMaster") -and
    $fixture.Contains("MANDOVIOL_ABILITY")
) "p14.entertainer-master.fixture.production-and-reversible"

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
                "precu_entertainer_music_one_fixture.java" -and
        (Get-FileHash $skillsPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.sourceSha256."skills.tab" -and
        [int]$b.clientNativeBuild.protocolVersion -eq 39
    ) "p14.entertainer-master.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [string]$live.qualification.prerequisiteVector -ceq "1111" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.pointCost -eq 6 -and
        [string]$live.purchase.commandsAfter -ceq "11111" -and
        [int]$live.purchase.musicAbilityDelta -eq 10 -and
        [int]$live.purchase.danceAbilityDelta -eq 10 -and
        [int]$live.purchase.musicWoundDelta -eq 10 -and
        [int]$live.purchase.danceWoundDelta -eq 10 -and
        [int]$live.purchase.xpSpent -eq 0 -and
        [bool]$live.ceremonial.startAccepted -and
        [int]$live.ceremonial.performanceIndex -eq 71 -and
        [bool]$live.ceremonial.stopCompleted -and
        [bool]$live.surrender.serverRemoved -and
        [string]$live.surrender.commandsAfter -ceq "00000" -and
        [int]$live.surrender.pointsRecovered -eq 6 -and
        [string]$live.surrender.prerequisiteVectorRetained -ceq "1111" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.entertainer-master.live-purchase-use-surrender"
}

if ($failures.Count)
{
    throw "Entertainer master contract failed: " +
        ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Entertainer master contract passed."
