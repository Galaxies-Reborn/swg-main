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
            [string]$manifest.contracts.p14HospitalPlacementCertification
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
        throw "Required hospital-certification source is missing: $path"
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

function Get-TableRows
{
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $matches = @(
        $lines |
            Select-Object -Skip 2 |
            Where-Object {
                (($_ -split "`t", -1)[0]) -ceq $Key
            })
    $rows = @()
    foreach ($match in $matches)
    {
        $values = $match -split "`t", -1
        $fields = @{}
        for ($index = 0; $index -lt $header.Count; ++$index)
        {
            $fields[$header[$index]] = if ($index -lt $values.Count)
            {
                $values[$index]
            }
            else
            {
                ""
            }
        }
        $rows += [pscustomobject]@{
            Values = $values
            Fields = $fields
        }
    }
    return @($rows)
}

$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$playerStructure =
    Get-Content -LiteralPath $paths.playerStructureLibrary -Raw
$hospitalRows = @(
    foreach ($template in $contract.swgSourcePlacementContract.templates)
    {
        $rows = @(Get-TableRows -Path $paths.structureTable -Key $template)
        [pscustomobject]@{
            Template = [string]$template
            Rows = $rows
        }
    })
$masterRows = @(
    Get-TableRows -Path $paths.skillsTable -Key (
        [string]$contract.swgSourcePlacementContract.masterSkill
    ))
$commandRows = @(
    Get-TableRows -Path $paths.commandTable -Key (
        [string]$contract.swgSourcePlacementContract.masterAbility
    ))

Write-Host "Publish 14.1 hospital-placement certification checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.core3AbilityRequired -ceq
        "place_hospital" -and
    [int]$contract.semanticReference.core3CityRankRequired -eq 3 -and
    @($contract.semanticReference.templates).Count -eq 3) `
    -Name "p14.hospital.core3.pinned-ability-and-city-rank"

Assert-Contract -Condition (
    $playerStructure.Contains(
        "public static boolean canOwnStructure(") -and
    $playerStructure.Contains(
        "getSkillStatMod(player, skill_mod) < " +
        "dataTableGetInt(PLAYER_STRUCTURE_DATATABLE, idx, " +
        "DATATABLE_COL_SKILL_MOD_VALUE)") -and
    $playerStructure.Contains(
        "DATATABLE_COL_SKILL_MOD_MESSAGE") -and
    $playerStructure.Contains(
        "if (!canOwnStructure(template, player, true))") -and
    $playerStructure.Contains(
        "if (!player_structure.canPlaceStructure(")) `
    -Name "p14.hospital.runtime.retained-placement-admission-chain"

$allHospitalRowsMatch = $hospitalRows.Count -eq 3
foreach ($entry in $hospitalRows)
{
    if ($entry.Rows.Count -ne 1)
    {
        $allHospitalRowsMatch = $false
        continue
    }
    $fields = $entry.Rows[0].Fields
    $allHospitalRowsMatch = $allHospitalRowsMatch -and
        $fields["CITY_RANK"] -ceq "3" -and
        $fields["MAINT_RATE"] -ceq "13" -and
        $fields["DECAY_RATE"] -ceq "5" -and
        $fields["CONDITION"] -ceq "7200" -and
        $fields["REDEED_COST"] -ceq "2500" -and
        $fields["HAS_SIGN"] -ceq "1" -and
        $fields["SKILLMOD"] -ceq "private_place_hospital" -and
        $fields["SKILLMODVALUE"] -ceq "100" -and
        $fields["SKILLMOD_MESSAGE"] -ceq "place_hospital" -and
        $fields["VERSION"] -ceq "4"
}
Assert-Contract -Condition $allHospitalRowsMatch `
    -Name "p14.hospital.table.three-exact-retail-rows"

Assert-Contract -Condition (
    $masterRows.Count -eq 1 -and
    $masterRows[0].Fields["COMMANDS"] -ceq "place_hospital" -and
    $masterRows[0].Fields["SKILL_MODS"].Contains(
        "private_place_hospital=100") -and
    $commandRows.Count -eq 0 -and
    -not [bool]$contract.swgSourcePlacementContract.commandTableRowExpected) `
    -Name "p14.hospital.skill.ability-and-modifier-not-slash-row"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains('MASTER = "science_doctor_master"') -and
    $fixture.Contains('COMMAND = "place_hospital"') -and
    $fixture.Contains('MOD = "private_place_hospital"') -and
    $fixture.Contains("REQUIRED_MOD = 100") -and
    $fixture.Contains('buildGateBits(player).equals("000")') -and
    $fixture.Contains('buildRowBits().equals("111")') -and
    $fixture.Contains("grantSkill(player, MASTER)") -and
    $fixture.Contains("revokeSkill(player, MASTER)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    -Name "p14.hospital.fixture.identity-bound-reversible-certification"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 29 -and
        -not [bool]$contract.publicationBoundary.productionGameplayCodeChanged -and
        -not [bool]$contract.publicationBoundary.clientToolsChanged -and
        -not [bool]$contract.publicationBoundary.clientAssetsChanged) `
        -Name "p14.hospital.status.ready-retained-production-path"
    Assert-Contract -Condition (
        [string]$live.prepare.rowBits -ceq "111" -and
        [string]$live.prepare.gateBits -ceq "000" -and
        -not [bool]$live.prepare.master -and
        -not [bool]$live.prepare.command -and
        [int]$live.prepare.modifierDelta -eq 0 -and
        [string]$live.grant.rowBits -ceq "111" -and
        [string]$live.grant.gateBits -ceq "111" -and
        [bool]$live.grant.granted -and
        [bool]$live.grant.master -and
        [bool]$live.grant.command -and
        [int]$live.grant.modifierDelta -eq 100) `
        -Name "p14.hospital.live.negative-to-positive-three-template-gate"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [string]$live.cleanup.rowBits -ceq "111" -and
        [string]$live.cleanup.gateBits -ceq "000" -and
        -not [bool]$live.cleanup.master -and
        -not [bool]$live.cleanup.command -and
        [int]$live.cleanup.modifierDelta -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.hospital.live.exact-idempotent-cleanup-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 hospital contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 hospital-placement certification contract passed."
