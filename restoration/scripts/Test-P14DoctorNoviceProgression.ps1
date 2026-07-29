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
            [string]$manifest.contracts.p14DoctorNoviceProgression
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
        throw "Required materialized Doctor source is missing: $path"
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
$commands = Get-KeyedTable -Path $paths.commandTable
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$schematicLines =
    Get-Content -LiteralPath $paths.schematicGroupTable |
    Select-Object -Skip 2
$rootExpected = $contract.rootSkill
$rootRow = $skills.Rows[[string]$rootExpected.name]
$expected = $contract.skill
$row = $skills.Rows[[string]$expected.name]
$commandExpected = $contract.command
$commandRow = $commands.Rows[[string]$commandExpected.name]

Write-Host "Publish 14.1 novice Doctor progression checks:"

Assert-Contract -Condition (
    $null -ne $rootRow -and
    (Get-Column $skills $rootRow "PARENT") -ceq
        [string]$rootExpected.parent -and
    (Get-Column $skills $rootRow "GRAPH_TYPE") -ceq
        [string]$rootExpected.graphType -and
    (Get-Column $skills $rootRow "GOD_ONLY") -ceq
        [string]$rootExpected.godOnly -and
    (Get-Column $skills $rootRow "IS_PROFESSION") -ceq
        [string]$rootExpected.isProfession -and
    (Get-Column $skills $rootRow "IS_HIDDEN") -ceq
        [string]$rootExpected.isHidden -and
    (Get-Column $skills $rootRow "SEARCHABLE") -ceq
        [string]$rootExpected.searchable) `
    -Name "p14.doctor-novice.root.authentic-row"

Assert-Contract -Condition (
    $null -ne $row -and
    (Get-Column $skills $row "PARENT") -ceq
        [string]$expected.parent -and
    (Get-Column $skills $row "GRAPH_TYPE") -ceq
        [string]$expected.graphType -and
    (Get-Column $skills $row "GOD_ONLY") -ceq "0" -and
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
    -Name "p14.doctor-novice.skill.authentic-row"

Assert-Contract -Condition (
    $null -ne $commandRow -and
    (Get-Column $commands $commandRow "commandCategory") -ceq
        [string]$commandExpected.commandCategory -and
    (Get-Column $commands $commandRow "defaultPriority") -ceq
        [string]$commandExpected.defaultPriority -and
    (Get-Column $commands $commandRow "scriptHook") -ceq
        [string]$commandExpected.scriptHook -and
    (Get-Column $commands $commandRow "target") -ceq
        [string]$commandExpected.target -and
    (Get-Column $commands $commandRow "targetType") -ceq
        [string]$commandExpected.targetType -and
    (Get-Column $commands $commandRow "defaultTime") -ceq
        [string]$commandExpected.defaultTime) `
    -Name "p14.doctor-novice.command.heal-state-row"

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
        $group.Value | ForEach-Object { [string]$_ }
    )
    Assert-Contract -Condition (
        $actual.Count -eq $groupExpected.Count -and
        @($actual | Where-Object {
            $_ -notin $groupExpected
        }).Count -eq 0 -and
        @($groupExpected | Where-Object {
            $_ -notin $actual
        }).Count -eq 0) `
        -Name "p14.doctor-novice.schematic-group.$($group.Name)"
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
    -Name "p14.doctor-novice.schematic-templates.retained"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("science_medic_master") -and
    $fixture.Contains("science_doctor_novice") -and
    $fixture.Contains("purchaseWithoutHolocron") -and
    $fixture.Contains("skill.hasRequiredSkillsForSkillPurchase") -and
    $fixture.Contains("skill.hasRequiredXpForSkillPurchase") -and
    $fixture.Contains("skill.grantSkillToPlayer") -and
    $fixture.Contains("skill.deductXpCostForSkillPurchase") -and
    $fixture.Contains("revokePrerequisites(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    -Name "p14.doctor-novice.fixture.production-and-reversible"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$live.result -ceq "passed") `
        -Name "p14.doctor-novice.status.ready"
    Assert-Contract -Condition (
        [string]$live.prerequisites -ceq
            "111111111111111111" -and
        [string]$live.novice -ceq "1" -and
        [string]$live.commands -ceq "11" -and
        [string]$live.schematics -ceq "1111" -and
        [int]$live.modifierDeltas.healing_wound_treatment -eq 5 -and
        [int]$live.modifierDeltas.healing_wound_speed -eq 5 -and
        [int]$live.modifierDeltas.medicine_assembly -eq 10 -and
        [int]$live.modifierDeltas.medicine_experimentation -eq 10 -and
        [int]$live.modifierDeltas.healing_ability -eq 5) `
        -Name "p14.doctor-novice.live-ownership-modifiers"
    Assert-Contract -Condition (
        [int]$live.medicalXpAfter -eq 0 -and
        [int]$live.medicalXpCapAfter -eq 30000 -and
        [int]$live.craftingXpAfter -eq 0 -and
        [int]$live.craftingXpCapAfter -eq 17500 -and
        [int]$live.availableSkillPointsAfter -eq 167 -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.doctor-novice.live-costs-cleanup-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 novice Doctor contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 novice Doctor progression contract passed."
