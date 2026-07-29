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
            [string]$manifest.contracts.p14EntertainerMindHealing
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] =
        Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required entertainer-healing source is missing: $path"
    }
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

$performanceSource =
    Get-Content -LiteralPath $paths.performanceLibrary -Raw
$xpSource = Get-Content -LiteralPath $paths.xpLibrary -Raw
$activeDance = Get-Content -LiteralPath $paths.activeDance -Raw
$activeMusic = Get-Content -LiteralPath $paths.activeMusic -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$performances = Import-TabTable -Path $paths.performanceTable
$skills = Import-TabTable -Path $paths.skillTable

Write-Host "Publish 14.1 entertainer Mind-healing checks:"

Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [int]$contract.semanticReference.heartbeatSeconds -eq 10 -and
    [int]$contract.semanticReference.healRangeMeters -eq 60 -and
    [int]$contract.semanticReference.groupXpRangeMeters -eq 40 -and
    [int]$contract.semanticReference.buildingBattleFatigueModifier -eq 5 -and
    [string]$contract.semanticReference.xpType -ceq
        "entertainer_healing") `
    -Name "p14.entertainer-healing.core3.pinned-contract"

Assert-Contract -Condition (
    [int]$contract.publish14Evidence.performanceRows -eq 154 -and
    [string]$contract.publish14Evidence.performanceIffSha256 -ceq
        "17b1e439ea81beebd96c0722258348851a1f826c8da88d396f823916626cd6f6" -and
    [int]$contract.publish14Evidence.skillsRows -eq 1068 -and
    [string]$contract.publish14Evidence.skillsIffSha256 -ceq
        "1eddc5d8b14b325e478bd1c53486576b82ef7347118e92f831f5bba45dcc7e45" -and
    [int]$contract.performanceMerge.matchedPublish14Rows -eq 154 -and
    [int]$contract.performanceMerge.preservedLaterRows -eq 157 -and
    $performances.Count -eq 311) `
    -Name "p14.entertainer-healing.data.lossless-154-plus-157-merge"

$basic = @(
    $performances |
    Where-Object {
        $_.performanceName -ceq "basic" -and $_.type -ceq "dance"
    }
)
$expectedBasic = $contract.performanceMerge.basicDance
Assert-Contract -Condition (
    $basic.Count -eq 1 -and
    [string]$basic[0].actionPointsPerLoop -ceq
        [string]$expectedBasic.actionPointsPerLoop -and
    [string]$basic[0].loopDuration -ceq
        [string]$expectedBasic.loopDuration -and
    [string]$basic[0].flourishXpMod -ceq
        [string]$expectedBasic.flourishXpMod -and
    [string]$basic[0].healMindWound -ceq
        [string]$expectedBasic.healMindWound -and
    [string]$basic[0].healShockWound -ceq
        [string]$expectedBasic.healShockWound -and
    [string]$basic[0].requiredSkillMod -ceq
        [string]$expectedBasic.requiredSkillMod -and
    [string]$basic[0].requiredSkillModValue -ceq
        [string]$expectedBasic.requiredSkillModValue) `
    -Name "p14.entertainer-healing.data.basic-dance-retail-values"

foreach ($expected in $contract.healingBranch)
{
    $row = @($skills | Where-Object { $_.NAME -ceq [string]$expected.name })
    Assert-Contract -Condition (
        $row.Count -eq 1 -and
        [string]$row[0].PARENT -ceq [string]$expected.parent -and
        [string]$row[0].POINTS_REQUIRED -ceq [string]$expected.points -and
        [string]$row[0].SKILLS_REQUIRED -ceq [string]$expected.required -and
        [string]$row[0].XP_TYPE -ceq
            [string]$contract.skillBranchShared.xpType -and
        [string]$row[0].XP_COST -ceq [string]$expected.xpCost -and
        [string]$row[0].XP_CAP -ceq [string]$expected.xpCap -and
        [string]$row[0].SKILL_MODS -ceq
            [string]$contract.skillBranchShared.skillMods -and
        [string]$row[0].SCHEMATICS_GRANTED -ceq "") `
        -Name "p14.entertainer-healing.skill.$($expected.name)"
}

Assert-Contract -Condition (
    $performanceSource.Contains(
        "public static final float PERFORMANCE_HEAL_RANGE = 60.0f") -and
    $performanceSource.Contains(
        "PRECU_HEALING_XP_GROUP_RANGE = 40.0f") -and
    $performanceSource.Contains(
        "PRECU_BUILDING_SHOCK_HEAL_MOD = 5") -and
    $performanceSource.Contains(
        "getPerformanceWatchersInRange(actor, PERFORMANCE_HEAL_RANGE)") -and
    $performanceSource.Contains(
        "getPerformanceListenersInRange(actor, PERFORMANCE_HEAL_RANGE)") -and
    $performanceSource.Contains(
        "amountHealed += applyPrecuEntertainerHealing(")) `
    -Name "p14.entertainer-healing.runtime.self-and-60m-patrons"

Assert-Contract -Condition (
    $performanceSource.Contains(
        "getPerformanceHealWoundMod(performanceIndex) *") -and
    $performanceSource.Contains("(woundSkillValue / 100.0f)") -and
    $performanceSource.Contains(
        "getPerformanceHealShockMod(performanceIndex) *") -and
    $performanceSource.Contains(
        "int flourishMultiplier = Math.max(0, flourishCount) + 1") -and
    $performanceSource -match "target,\s+MIND," -and
    $performanceSource -match "target,\s+FOCUS," -and
    $performanceSource -match "target,\s+WILLPOWER," -and
    $performanceSource.Contains("amountHealed += woundHeal") -and
    $performanceSource.Contains("amountHealed += shockHeal")) `
    -Name "p14.entertainer-healing.runtime.formula-and-four-channels"

Assert-Contract -Condition (
    $xpSource.Contains(
        'ENTERTAINER_HEALING = "entertainer_healing"') -and
    $performanceSource.Contains(
        "xp.grant(actor, xp.ENTERTAINER_HEALING, amount)") -and
    $performanceSource.Contains(
        "getDistance(actor, member) > PRECU_HEALING_XP_GROUP_RANGE") -and
    $performanceSource.Contains(
        '!hasSkill(member, "social_entertainer_novice")') -and
    $performanceSource.Contains(
        "hasScript(member, DANCE_HEARTBEAT_SCRIPT)") -and
    $performanceSource.Contains(
        "hasScript(member, MUSIC_HEARTBEAT_SCRIPT)")) `
    -Name "p14.entertainer-healing.runtime.solo-and-active-group-xp"

Assert-Contract -Condition (
    $performanceSource.Contains(
        '!hasSkill(actor, "social_entertainer_novice")') -and
    -not $activeDance.Contains(
        'grantExperiencePoints(self, "entertainer_healing"') -and
    -not $activeMusic.Contains(
        'grantExperiencePoints(self, "entertainer_healing"')) `
    -Name "p14.entertainer-healing.runtime.novice-gate-no-nge-conversion"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("FLOURISH_COUNT = 2") -and
    $fixture.Contains("EXPECTED_HEAL = 3") -and
    $fixture.Contains("EXPECTED_XP = 6") -and
    $fixture.Contains("xpDelivery=asynchronous") -and
    $fixture.Contains("action=status passed=") -and
    $fixture.Contains("restoreSkills(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    -Name "p14.entertainer-healing.fixture.identity-bound-reversible"

if ($Expectation -ceq "Ready")
{
    $build = $contract.buildEvidence
    $live = $contract.liveEvidence
    $assets = $contract.clientAssetPublication
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$build.result -ceq "passed" -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256."performance.class") -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$build.compiledSha256.
                "precu_entertainer_healing_fixture.class") -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$assets.performanceIffSha256) -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$assets.skillsIffSha256)) `
        -Name "p14.entertainer-healing.build.ready-and-published"
    Assert-Contract -Condition (
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 31 -and
        [int]$live.basicDancePerformanceIndex -eq 281 -and
        [int]$live.expectedPerChannelHeal -eq 3 -and
        [int]$live.expectedAmountHealed -eq 6 -and
        [int]$live.expectedHealingXp -eq 6 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.entertainer-healing.live.exact-heal-xp-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 entertainer Mind-healing contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 entertainer Mind-healing contract passed."
