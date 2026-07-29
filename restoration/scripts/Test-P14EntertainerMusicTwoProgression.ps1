[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot "manifest.json"
    ) -Raw | ConvertFrom-Json
$contract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.
                p14EntertainerMusicTwoProgression
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required Entertainer Music II source is missing: $path"
    }
    $paths[[string]$property.Name] = $path
}

function Import-TabTable
{
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = Get-Content -LiteralPath $Path
    $csv = @($lines[0]) + @($lines | Select-Object -Skip 2)
    return @($csv | ConvertFrom-Csv -Delimiter "`t")
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

$skills = Import-TabTable -Path $paths.skillTable
$performances = Import-TabTable -Path $paths.performanceTable
$schematicGroups = Import-TabTable -Path $paths.schematicGroupTable
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$evidence = $contract.publish14Evidence

Write-Host "Publish 14.1 Entertainer Music II progression checks:"

$musicTwo = @(
    $skills |
    Where-Object { $_.NAME -ceq [string]$evidence.musicTwo.name }
)
Assert-Contract -Condition (
    $musicTwo.Count -eq 1 -and
    [string]$musicTwo[0].PARENT -ceq
        [string]$evidence.musicTwo.parent -and
    [string]$musicTwo[0].GRAPH_TYPE -ceq
        [string]$evidence.musicTwo.graphType -and
    [string]$musicTwo[0].MONEY_REQUIRED -ceq
        [string]$evidence.musicTwo.moneyRequired -and
    [string]$musicTwo[0].POINTS_REQUIRED -ceq
        [string]$evidence.musicTwo.pointsRequired -and
    [string]$musicTwo[0].SKILLS_REQUIRED -ceq
        [string]$evidence.musicTwo.skillsRequired -and
    [string]$musicTwo[0].XP_TYPE -ceq
        [string]$evidence.musicTwo.xpType -and
    [string]$musicTwo[0].XP_COST -ceq
        [string]$evidence.musicTwo.xpCost -and
    [string]$musicTwo[0].XP_CAP -ceq
        [string]$evidence.musicTwo.xpCap -and
    [string]$musicTwo[0].COMMANDS -ceq
        [string]$evidence.musicTwo.commands -and
    [string]$musicTwo[0].SKILL_MODS -ceq
        [string]$evidence.musicTwo.skillMods -and
    [string]$musicTwo[0].SCHEMATICS_GRANTED -ceq
        [string]$evidence.musicTwo.schematics -and
    [string]$musicTwo[0].SEARCHABLE -ceq
        [string]$evidence.musicTwo.searchable
) -Name "p14.entertainer-music-two.skill.authentic"

$song = @(
    $performances |
    Where-Object {
        $_.performanceName -ceq "starwars2" -and
        [int]$_.instrumentAudioId -eq 2
    }
)
Assert-Contract -Condition (
    $song.Count -eq 1 -and
    [string]$song[0].requiredSong -ceq
        [string]$evidence.starwarsTwoSlitherhorn.requiredSong -and
    [string]$song[0].requiredInstrument -ceq
        [string]$evidence.starwarsTwoSlitherhorn.requiredInstrument -and
    [int]$song[0].actionPointsPerLoop -eq
        [int]$evidence.starwarsTwoSlitherhorn.actionPointsPerLoop -and
    [double]$song[0].loopDuration -eq
        [double]$evidence.starwarsTwoSlitherhorn.loopDuration
) -Name "p14.entertainer-music-two.starwars2-slitherhorn.authentic"

$group = @(
    $schematicGroups |
    Where-Object { $_.GroupId -ceq "craftInstrumentGroupB" }
)
$groupSchematics = @(
    $group | ForEach-Object { [string]$_.SchematicName }
)
Assert-Contract -Condition (
    $group.Count -eq 2 -and
    @($evidence.schematicGroupB).Count -eq 2 -and
    $groupSchematics -ccontains [string]$evidence.schematicGroupB[0] -and
    $groupSchematics -ccontains [string]$evidence.schematicGroupB[1]
) -Name "p14.entertainer-music-two.fizz-schematics.authentic"

Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    $fixture.Contains("prepareTwo") -and
    $fixture.Contains("purchaseTwo") -and
    $fixture.Contains("observeStarwarsTwoStart") -and
    $fixture.Contains("observeSurrenderTwo") -and
    $fixture.Contains("hasSchematic(player, FIZZ_SCHEMATIC)") -and
    $fixture.Contains("restoreSnapshot(player)")
) -Name "p14.entertainer-music-two.fixture.production-and-reversible"

if ($Expectation -ceq "Ready")
{
    $build = $contract.buildEvidence
    $live = $contract.liveEvidence
    $patchPath =
        Join-Path $restorationRoot (
            [string]$build.overlayPatch -replace "^restoration/", ""
        )
    $patchHash =
        (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).
            Hash.ToLowerInvariant()
    $fixtureHash =
        (Get-FileHash -LiteralPath $paths.fixture -Algorithm SHA256).
            Hash.ToLowerInvariant()
    $skillsHash =
        (Get-FileHash -LiteralPath $paths.skillTable -Algorithm SHA256).
            Hash.ToLowerInvariant()

    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$build.result -ceq "passed" -and
        [string]$build.cleanApplyCheck -ceq "passed" -and
        [string]$build.reverseApplyCheck -ceq "passed" -and
        [int]$build.changedFileCount -eq 2 -and
        [string]$build.serverJavaBuild.result -ceq "passed" -and
        [string]$build.clientTableBuild.result -ceq "passed" -and
        [string]$build.clientNativeBuild.result -ceq "passed" -and
        [int]$build.clientNativeBuild.protocolVersion -eq 36 -and
        $patchHash -ceq [string]$build.overlayPatchSha256 -and
        $fixtureHash -ceq [string]$build.sourceSha256.
            "precu_entertainer_music_one_fixture.java" -and
        $skillsHash -ceq [string]$build.sourceSha256."skills.tab"
    ) -Name "p14.entertainer-music-two.build.ready-and-hashed"

    Assert-Contract -Condition (
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 36 -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.musicXpBefore -eq 5000 -and
        [int]$live.purchase.musicXpAfter -eq 0 -and
        [int]$live.purchase.pointCost -eq 3 -and
        [string]$live.purchase.commandsAfter -ceq "11" -and
        [string]$live.purchase.schematicsAfter -ceq "11" -and
        [int]$live.purchase.musicAbilityDelta -eq 5 -and
        [bool]$live.starwarsTwo.startAccepted -and
        [int]$live.starwarsTwo.performanceIndex -eq 29 -and
        [bool]$live.starwarsTwo.stopAccepted -and
        [bool]$live.starwarsTwo.outroObserved -and
        [bool]$live.surrender.clientSubmitted -and
        [bool]$live.surrender.serverRemoved -and
        [string]$live.surrender.commandsAfter -ceq "00" -and
        [string]$live.surrender.schematicsAfter -ceq "00" -and
        [int]$live.surrender.pointsRecovered -eq 3 -and
        [int]$live.surrender.musicXpRefund -eq 0 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup
    ) -Name "p14.entertainer-music-two.live-purchase-use-surrender"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Entertainer Music II contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 Entertainer Music II progression contract passed."
