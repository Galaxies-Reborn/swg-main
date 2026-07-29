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
                p14EntertainerMusicOneProgression
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required Entertainer Music I source is missing: $path"
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
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$evidence = $contract.publish14Evidence

Write-Host "Publish 14.1 Entertainer Music I progression checks:"

$root = @(
    $skills |
    Where-Object { $_.NAME -ceq [string]$evidence.root.name }
)
$novice = @(
    $skills |
    Where-Object { $_.NAME -ceq [string]$evidence.novice.name }
)
$musicOne = @(
    $skills |
    Where-Object { $_.NAME -ceq [string]$evidence.musicOne.name }
)

Assert-Contract -Condition (
    $root.Count -eq 1 -and
    [string]$root[0].PARENT -ceq [string]$evidence.root.parent -and
    [string]$root[0].GRAPH_TYPE -ceq
        [string]$evidence.root.graphType -and
    [string]$root[0].IS_PROFESSION -ceq
        [string]$evidence.root.isProfession -and
    [string]$root[0].SEARCHABLE -ceq
        [string]$evidence.root.searchable
) -Name "p14.entertainer-music-one.root.authentic"

Assert-Contract -Condition (
    $novice.Count -eq 1 -and
    [string]$novice[0].PARENT -ceq
        [string]$evidence.novice.parent -and
    [string]$novice[0].GRAPH_TYPE -ceq
        [string]$evidence.novice.graphType -and
    [string]$novice[0].MONEY_REQUIRED -ceq
        [string]$evidence.novice.moneyRequired -and
    [string]$novice[0].POINTS_REQUIRED -ceq
        [string]$evidence.novice.pointsRequired -and
    [string]$novice[0].XP_TYPE -ceq
        [string]$evidence.novice.xpType -and
    [string]$novice[0].XP_COST -ceq
        [string]$evidence.novice.xpCost -and
    [string]$novice[0].XP_CAP -ceq
        [string]$evidence.novice.xpCap -and
    [string]$novice[0].COMMANDS -ceq
        [string]$evidence.novice.commands -and
    [string]$novice[0].SKILL_MODS -ceq
        [string]$evidence.novice.skillMods -and
    [string]$novice[0].SCHEMATICS_GRANTED -ceq
        [string]$evidence.novice.schematics -and
    [string]$novice[0].SEARCHABLE -ceq
        [string]$evidence.novice.searchable
) -Name "p14.entertainer-music-one.novice.authentic"

Assert-Contract -Condition (
    $musicOne.Count -eq 1 -and
    [string]$musicOne[0].PARENT -ceq
        [string]$evidence.musicOne.parent -and
    [string]$musicOne[0].GRAPH_TYPE -ceq
        [string]$evidence.musicOne.graphType -and
    [string]$musicOne[0].MONEY_REQUIRED -ceq
        [string]$evidence.musicOne.moneyRequired -and
    [string]$musicOne[0].POINTS_REQUIRED -ceq
        [string]$evidence.musicOne.pointsRequired -and
    [string]$musicOne[0].SKILLS_REQUIRED -ceq
        [string]$evidence.musicOne.skillsRequired -and
    [string]$musicOne[0].XP_TYPE -ceq
        [string]$evidence.musicOne.xpType -and
    [string]$musicOne[0].XP_COST -ceq
        [string]$evidence.musicOne.xpCost -and
    [string]$musicOne[0].XP_CAP -ceq
        [string]$evidence.musicOne.xpCap -and
    [string]$musicOne[0].COMMANDS -ceq
        [string]$evidence.musicOne.commands -and
    [string]$musicOne[0].SKILL_MODS -ceq
        [string]$evidence.musicOne.skillMods -and
    [string]$musicOne[0].SCHEMATICS_GRANTED -ceq
        [string]$evidence.musicOne.schematics -and
    [string]$musicOne[0].SEARCHABLE -ceq
        [string]$evidence.musicOne.searchable
) -Name "p14.entertainer-music-one.skill.authentic"

$rock = @(
    $performances |
    Where-Object {
        $_.performanceName -ceq "rock" -and
        [int]$_.instrumentAudioId -eq
            [int]$evidence.rockSlitherhorn.instrumentAudioId
    }
)
Assert-Contract -Condition (
    $rock.Count -eq 1 -and
    [string]$rock[0].requiredSong -ceq
        [string]$evidence.rockSlitherhorn.requiredSong -and
    [string]$rock[0].requiredInstrument -ceq
        [string]$evidence.rockSlitherhorn.requiredInstrument -and
    [int]$rock[0].actionPointsPerLoop -eq
        [int]$evidence.rockSlitherhorn.actionPointsPerLoop -and
    [double]$rock[0].loopDuration -eq
        [double]$evidence.rockSlitherhorn.loopDuration
) -Name "p14.entertainer-music-one.rock-slitherhorn.authentic"

Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("purchaseWithoutHolocron") -and
    $fixture.Contains("skill.hasRequiredSkillsForSkillPurchase") -and
    $fixture.Contains("skill.hasRequiredXpForSkillPurchase") -and
    $fixture.Contains("skill.grantSkillToPlayer") -and
    $fixture.Contains("skill.deductXpCostForSkillPurchase") -and
    $fixture.Contains("observeRockStart") -and
    $fixture.Contains("observeRockStopRequested") -and
    $fixture.Contains("observeRockStopComplete") -and
    $fixture.Contains("observeSurrender") -and
    $fixture.Contains("restoreSnapshot(player)") -and
    $fixture.Contains("destroyObject(instrument)")
) -Name "p14.entertainer-music-one.fixture.production-and-reversible"

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
        [int]$build.clientNativeBuild.protocolVersion -eq 35 -and
        $patchHash -ceq [string]$build.overlayPatchSha256 -and
        $fixtureHash -ceq [string]$build.sourceSha256.
            "precu_entertainer_music_one_fixture.java" -and
        $skillsHash -ceq [string]$build.sourceSha256."skills.tab" -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256.
                "precu_entertainer_music_one_fixture.class") -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256."skills.iff")
    ) -Name "p14.entertainer-music-one.build.ready-and-hashed"

    Assert-Contract -Condition (
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 35 -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.musicXpBefore -eq 1000 -and
        [int]$live.purchase.musicXpAfter -eq 0 -and
        [int]$live.purchase.pointCost -eq 2 -and
        [string]$live.purchase.commandsAfter -ceq "111" -and
        [int]$live.purchase.musicAbilityDelta -eq 5 -and
        [bool]$live.rock.startAccepted -and
        [int]$live.rock.performanceIndex -eq
            [int]$evidence.rockSlitherhorn.performanceIndex -and
        [int]$live.rock.instrumentAudioId -eq 2 -and
        [bool]$live.rock.stopAccepted -and
        [bool]$live.rock.outroObserved -and
        [bool]$live.surrender.clientSubmitted -and
        [bool]$live.surrender.serverRemoved -and
        [string]$live.surrender.commandsAfter -ceq "000" -and
        [int]$live.surrender.musicAbilityDelta -eq 0 -and
        [int]$live.surrender.pointsRecovered -eq 2 -and
        [int]$live.surrender.musicXpRefund -eq 0 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup
    ) -Name "p14.entertainer-music-one.live-purchase-use-surrender"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Entertainer Music I contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 Entertainer Music I progression contract passed."
