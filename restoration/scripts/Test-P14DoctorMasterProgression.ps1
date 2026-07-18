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
            [string]$manifest.contracts.p14DoctorMasterProgression
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
        throw "Required materialized Master Doctor source is missing: $path"
    }
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

function Get-KeyedTable
{
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $rows = @{}
    foreach ($line in ($lines | Select-Object -Skip 2))
    {
        $values = $line -split "`t", -1
        if ($values.Count -gt 0)
        {
            $rows[[string]$values[0]] = $values
        }
    }
    return [pscustomobject]@{
        Header = $header
        Rows = $rows
    }
}

function Get-Column
{
    param(
        [Parameter(Mandatory = $true)]$Table,
        [AllowEmptyString()][string[]]$Row,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $index = [array]::IndexOf($Table.Header, $Name)
    if ($index -lt 0 -or $index -ge $Row.Count)
    {
        return $null
    }
    $value = [string]$Row[$index]
    if ($value.Length -ge 2 -and
        $value.StartsWith('"') -and
        $value.EndsWith('"'))
    {
        return $value.Substring(1, $value.Length - 2).Replace('""', '"')
    }
    return $value
}

$skills = Get-KeyedTable -Path $paths.skillTable
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$schematicLines =
    Get-Content -LiteralPath $paths.schematicGroupTable |
    Select-Object -Skip 2
$expected = $contract.skill
$row = $skills.Rows[[string]$expected.name]

Write-Host "Publish 14.1 Master Doctor progression checks:"

Assert-Contract -Condition (
    $null -ne $row -and
    (Get-Column $skills $row "PARENT") -ceq
        [string]$expected.parent -and
    (Get-Column $skills $row "GRAPH_TYPE") -ceq
        [string]$expected.graphType -and
    (Get-Column $skills $row "GOD_ONLY") -ceq "0" -and
    (Get-Column $skills $row "IS_TITLE") -ceq "1" -and
    (Get-Column $skills $row "IS_PROFESSION") -ceq "0" -and
    (Get-Column $skills $row "IS_HIDDEN") -ceq "0" -and
    (Get-Column $skills $row "MONEY_REQUIRED") -ceq
        [string]$expected.moneyRequired -and
    (Get-Column $skills $row "POINTS_REQUIRED") -ceq
        [string]$expected.pointsRequired -and
    (Get-Column $skills $row "SKILLS_REQUIRED") -ceq
        [string]$expected.skillsRequired -and
    (Get-Column $skills $row "XP_TYPE") -ceq
        [string]$expected.xpType -and
    (Get-Column $skills $row "XP_COST") -ceq
        [string]$expected.xpCost -and
    (Get-Column $skills $row "XP_CAP") -ceq
        [string]$expected.xpCap -and
    (Get-Column $skills $row "COMMANDS") -ceq
        [string]$expected.commands -and
    (Get-Column $skills $row "SKILL_MODS") -ceq
        [string]$expected.skillMods -and
    (Get-Column $skills $row "SCHEMATICS_GRANTED") -ceq
        [string]$expected.schematics -and
    (Get-Column $skills $row "SEARCHABLE") -ceq "1") `
    -Name "p14.doctor-master.skill.authentic-row"

foreach ($command in $contract.rejectedNgeCommands)
{
    Assert-Contract -Condition (
        -not (Get-Column $skills $row "COMMANDS").Split(',').Contains(
            [string]$command
        )) -Name "p14.doctor-master.reject-command.$command"
}
foreach ($modifier in $contract.rejectedNgeSkillMods)
{
    Assert-Contract -Condition (
        -not (Get-Column $skills $row "SKILL_MODS").Contains(
            ([string]$modifier + "=")
        )) -Name "p14.doctor-master.reject-modifier.$modifier"
}

foreach ($group in $contract.schematicGroups.psobject.Properties)
{
    $actual = @(
        $schematicLines |
        ForEach-Object {
            $parts = $_ -split "`t", -1
            if ($parts[0] -ceq [string]$group.Name)
            {
                [string]$parts[1]
            }
        }
    )
    $groupExpected = @(
        $group.Value |
        ForEach-Object { [string]$_ }
    )
    Assert-Contract -Condition (
        $actual.Count -eq $groupExpected.Count -and
        @($actual | Where-Object {
            $_ -notin $groupExpected
        }).Count -eq 0 -and
        @($groupExpected | Where-Object {
            $_ -notin $actual
        }).Count -eq 0) `
        -Name "p14.doctor-master.schematic-group.$($group.Name)"
}

$templatesPresent = $true
foreach ($template in $contract.retainedSharedTemplates)
{
    $templatesPresent =
        $templatesPresent -and
        (Test-Path -LiteralPath (
            Join-Path $source ([string]$template)
        ) -PathType Leaf)
}
Assert-Contract -Condition $templatesPresent `
    -Name "p14.doctor-master.schematic-templates.retained"

$markers = @(
    "PLAYER_OID = 39008597L",
    "PLAYER_STATION_ID = 1001",
    "science_medic_master",
    "science_doctor_support_04",
    "science_doctor_master",
    "place_hospital",
    "bactaJab_2",
    "battle_firerate_mitigate_3",
    "private_place_hospital",
    "grantPrerequisites",
    "purchaseWithoutHolocron",
    "skill.getAvailableSkillPoints",
    "skill.hasRequiredSkillsForSkillPurchase",
    "skill.hasRequiredXpForSkillPurchase",
    "skill.grantSkillToPlayer",
    "skill.deductXpCostForSkillPurchase",
    "revokeSkill(player, MASTER)",
    "revokePrerequisites(player)",
    "removeObjVar(player, ROOT)"
)
$fixtureComplete = $true
foreach ($marker in $markers)
{
    $fixtureComplete = $fixtureComplete -and $fixture.Contains($marker)
}
Assert-Contract -Condition (
    $fixtureComplete -and
    -not $fixture.Contains("skill.purchaseSkill")) `
    -Name "p14.doctor-master.fixture-production-and-rollback"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.clientAssetPublication.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -ge 27) `
        -Name "p14.doctor-master.status.ready"
    Assert-Contract -Condition (
        [string]$live.prerequisites -ceq
            "11111111111111111111111111111111111" -and
        [string]$live.master -ceq "1" -and
        [string]$live.command -ceq "1" -and
        [string]$live.ngeCommands -ceq "000000" -and
        [string]$live.schematics -ceq "11111111111111" -and
        [int]$live.modifierDeltas.healing_wound_treatment -eq 25 -and
        [int]$live.modifierDeltas.healing_wound_speed -eq 25 -and
        [int]$live.modifierDeltas.healing_ability -eq 10 -and
        [int]$live.modifierDeltas.private_place_hospital -eq 100 -and
        [int]$live.modifierDeltas.melee_defense -eq 0 -and
        [int]$live.modifierDeltas.ranged_defense -eq 0 -and
        [int]$live.modifierDeltas.buffing_efficiency -eq 0 -and
        [int]$live.modifierDeltas.healing_efficiency -eq 0 -and
        [int]$live.modifierDeltas.cure_efficiency -eq 0) `
        -Name "p14.doctor-master.live-vector"
    Assert-Contract -Condition (
        [int]$live.medicalXpAfter -eq 0 -and
        [int]$live.medicalXpCapAfter -eq 80000 -and
        [int]$live.craftingXpAfter -eq 0 -and
        [int]$live.craftingXpCapAfter -eq 44000 -and
        [int]$live.availableSkillPointsAfter -eq 110 -and
        [int]$live.clientQueueCountAfterPurchase -eq 0 -and
        [int]$live.clientQueueCountAfterCleanup -eq 0 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.doctor-master.live-costs-cleanup-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Master Doctor contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Master Doctor progression contract passed."
