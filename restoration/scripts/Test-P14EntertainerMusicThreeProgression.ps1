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
        p14EntertainerMusicThreeProgression)
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
        throw "Required Music III source is missing: $path"
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
    Where-Object NAME -CEQ ([string]$e.musicThree.name))
$song = @(Import-Tab $performancePath |
    Where-Object {
        $_.performanceName -ceq "folk" -and
        [int]$_.instrumentAudioId -eq 2
    })
$fixture = Get-Content $fixturePath -Raw

Write-Host "Publish 14.1 Entertainer Music III checks:"
Assert-Contract (
    $row.Count -eq 1 -and
    [string]$row[0].PARENT -ceq [string]$e.musicThree.parent -and
    [string]$row[0].GRAPH_TYPE -ceq [string]$e.musicThree.graphType -and
    [string]$row[0].MONEY_REQUIRED -ceq
        [string]$e.musicThree.moneyRequired -and
    [string]$row[0].POINTS_REQUIRED -ceq
        [string]$e.musicThree.pointsRequired -and
    [string]$row[0].SKILLS_REQUIRED -ceq
        [string]$e.musicThree.skillsRequired -and
    [string]$row[0].XP_TYPE -ceq [string]$e.musicThree.xpType -and
    [string]$row[0].XP_COST -ceq [string]$e.musicThree.xpCost -and
    [string]$row[0].XP_CAP -ceq [string]$e.musicThree.xpCap -and
    [string]$row[0].COMMANDS -ceq [string]$e.musicThree.commands -and
    [string]$row[0].SKILL_MODS -ceq [string]$e.musicThree.skillMods -and
    [string]$row[0].SCHEMATICS_GRANTED -ceq "" -and
    [string]$row[0].SEARCHABLE -ceq [string]$e.musicThree.searchable
) "p14.entertainer-music-three.skill.authentic"

Assert-Contract (
    $song.Count -eq 1 -and
    [string]$song[0].requiredSong -ceq
        [string]$e.folkSlitherhorn.requiredSong -and
    [string]$song[0].requiredInstrument -ceq
        [string]$e.folkSlitherhorn.requiredInstrument -and
    [int]$song[0].actionPointsPerLoop -eq 36 -and
    [double]$song[0].loopDuration -eq 5
) "p14.entertainer-music-three.folk-slitherhorn.authentic"

Assert-Contract (
    $fixture.Contains("prepareThree") -and
    $fixture.Contains("purchaseThree") -and
    $fixture.Contains("observeFolkStart") -and
    $fixture.Contains("observeSurrenderThree") -and
    $fixture.Contains("FANFAR_ABILITY")
) "p14.entertainer-music-three.fixture.production-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 37
    ) "p14.entertainer-music-three.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.musicXpBefore -eq 15000 -and
        [int]$live.purchase.pointCost -eq 4 -and
        [string]$live.purchase.commandsAfter -ceq "111" -and
        [int]$live.purchase.xpCapAfter -eq 90000 -and
        [bool]$live.folk.startAccepted -and
        [int]$live.folk.performanceIndex -eq 43 -and
        [bool]$live.folk.stopCompleted -and
        [bool]$live.surrender.serverRemoved -and
        [string]$live.surrender.commandsAfter -ceq "000" -and
        [int]$live.surrender.pointsRecovered -eq 4 -and
        [int]$live.surrender.xpCapAfter -eq 30000 -and
        [bool]$live.surrender.musicTwoSchematicsRetained -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.entertainer-music-three.live-purchase-use-surrender"
}

if ($failures.Count)
{
    throw "Music III contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Entertainer Music III contract passed."
