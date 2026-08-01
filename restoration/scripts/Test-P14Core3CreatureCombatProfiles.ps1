[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3CreatureCombatProfiles)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param([bool]$Condition, [string]$Name)
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

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $base = if ([string]$property.Name -in @("overlay", "generator")) { $restorationRoot } else { $source }
    $paths[[string]$property.Name] = Join-Path $base ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.creature-profile.source.$([IO.Path]::GetFileName($path))"
}

$rows = @(Import-SwgTab -Path $paths.profileTable)
$fallbacks = @($rows | Where-Object { [string]$_.creatureName -like "__level_*" })
$exact = @($rows | Where-Object {
    [string]$_.creatureName -notlike "__level_*" -and
    [string]$_.creatureName -ceq [string]$_.sourceKey })
$aliases = @($rows | Where-Object {
    [string]$_.creatureName -notlike "__level_*" -and
    [string]$_.creatureName -cne [string]$_.sourceKey })
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths.profileTable).Hash.ToLowerInvariant()

Write-Host "Publish 14.1 Core3 creature-combat profile checks:"
Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) "p14.creature-profile.status"
Assert-Contract ([string]$contract.semanticReference.pinnedCommit -ceq "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8") "p14.creature-profile.core3-pin"
Assert-Contract ($rows.Count -eq 4205 -and $exact.Count -eq 3622 -and $aliases.Count -eq 83 -and $fallbacks.Count -eq 500) "p14.creature-profile.cardinality"
Assert-Contract (($rows.creatureName | Sort-Object -Unique).Count -eq $rows.Count) "p14.creature-profile.unique-keys"
Assert-Contract ($hash -ceq [string]$contract.semanticReference.tableSha256) "p14.creature-profile.table-hash"

foreach ($expected in $contract.representativeProfiles.psobject.Properties)
{
    $row = @($rows | Where-Object { [string]$_.creatureName -ceq [string]$expected.Name })
    $matches = $row.Count -eq 1
    if ($matches)
    {
        foreach ($field in $expected.Value.psobject.Properties)
        {
            if ([string]$row[0].($field.Name) -cne [string]$field.Value)
            {
                $matches = $false
                break
            }
        }
    }
    Assert-Contract $matches "p14.creature-profile.representative.$($expected.Name)"
}

$create = Get-Content -LiteralPath $paths.createLibrary -Raw
$corpse = Get-Content -LiteralPath $paths.corpseLibrary -Raw
$loot = Get-Content -LiteralPath $paths.lootLibrary -Raw
$generator = Get-Content -LiteralPath $paths.generator -Raw
$overlayHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths.overlay).Hash.ToLowerInvariant()

Assert-Contract ($generator.Contains("6ea64f60ef33b89121c2a8d188b93f4bc6f158e8") -and
    $generator.Contains("Expected 3622 unique complete Core3 creature profiles") -and
    $generator.Contains('$level -le 500')) "p14.creature-profile.generator-pinned"
Assert-Contract ($create.Contains('PRECU_CREATURE_COMBAT_PROFILE_TABLE = "datatables/mob/precu_creature_combat_profiles.iff"') -and
    $create.Contains('precuCombatProfile.getInt("damageMin")') -and
    $create.Contains('precuCombatProfile.getInt("baseHAM")') -and
    $create.Contains('precuCombatProfile.getFloat("chanceHit") * 100.0f') -and
    $create.Contains('setObjVar(creature, "precu.combatProfile"') -and
    $create.Contains('initializeArmor(creature, creatureDict, 0)')) "p14.creature-profile.factory-route"
Assert-Contract ((-not $create.Contains('float damagePerSecond = dataTableGetFloat(STAT_BALANCE_TABLE')) -and
    (-not $create.Contains('int avgAttribHealth = dataTableGetInt(STAT_BALANCE_TABLE')) -and
    (-not $create.Contains('int avgAttribAction = dataTableGetInt(STAT_BALANCE_TABLE'))) "p14.creature-profile.nge-scaling-retired"
Assert-Contract ($corpse.Contains('Rejected creature resource extraction without Novice Scout') -and
    $corpse.Contains('!canPlayerHarvestCreature(harvestingPlayer, true)')) "p14.creature-profile.harvest-final-gate"
Assert-Contract ($loot.Contains('Rejected NGE creature-resource loot injection') -and
    (-not $loot.Contains('finalAmount += corpse.extractCorpseResource'))) "p14.creature-profile.resource-loot-retired"
Assert-Contract ($overlayHash -ceq [string]$contract.buildEvidence.overlaySha256 -and
    (Get-Item -LiteralPath $paths.overlay).Length -eq [int64]$contract.buildEvidence.overlayBytes) "p14.creature-profile.overlay-evidence"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Core3 creature-combat profile contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14.1 Core3 creature-combat profile contract passed."
