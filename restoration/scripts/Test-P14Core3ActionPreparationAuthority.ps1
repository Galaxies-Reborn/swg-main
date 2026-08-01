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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3ActionPreparationAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

$combatPath = Join-Path $source ([string]$contract.sourceFiles.combatBase)
$combatDataPath = Join-Path $source ([string]$contract.sourceFiles.combatData)
$overridesPath = Join-Path $source ([string]$contract.sourceFiles.combatOverrides)
foreach ($path in @($combatPath, $combatDataPath, $overridesPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.action-preparation.source.$([IO.Path]::GetFileName($path))"
}

$combat = Get-Content -LiteralPath $combatPath -Raw
$sourceHash = (Get-FileHash -LiteralPath $combatPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Contract ($sourceHash -ceq [string]$contract.buildEvidence.materializedCombatBaseSha256) "p14.action-preparation.source.authenticated-hash"

$overrideCall = $combat.IndexOf('actionData = attackOverrideByBuff(self, actionData);', [StringComparison]::Ordinal)
$authorityBeforeOverride = $combat.LastIndexOf('isPrecuAuthoritativeAttack(self, actionData);', $overrideCall, [StringComparison]::Ordinal)
Assert-Contract ($overrideCall -gt 0 -and $authorityBeforeOverride -ge 0 -and
    $combat.Contains('if (!precuAuthoritativeAction)')) "p14.action-preparation.command-identity"

Assert-Contract ($combat.Contains('if (!isTangibleAttacking && !precuAuthoritativeAction)') -and
    $combat.Contains('actionData = modifyActionDataByExpertise(self, actionData);') -and
    $combat.Contains('int killMeterCost = precuAuthoritativeAction ? 0 :') -and
    $combat.Contains('if (!precuAuthoritativeAction && killMeterCost > 0)')) "p14.action-preparation.expertise-and-vigor-contained"

Assert-Contract ($combat.Contains('!isPrecuAuthoritativeAttack(objOwner, actionData)') -and
    $combat.Contains('"preparation.ngeDelayApplied", 0')) "p14.action-preparation.delay.authored"

Assert-Contract ($combat.Contains('actionData.maxRange : Math.max(10.0f, weaponData.maxRange)') -and
    $combat.Contains('else if (actionData.overloadWeaponType == WEAPON_TYPE_THROWN)') -and
    $combat.Contains('"preparation.ngeRangeApplied", 0')) "p14.action-preparation.range.core3"

Assert-Contract ($combat.Contains('if (!precuAuthoritativeAction)') -and
    $combat.Contains('"expertise_cone_length_single_"') -and
    $combat.Contains('"expertise_area_size_single_"') -and
    $combat.Contains('"preparation.ngeGeometryApplied", 0')) "p14.action-preparation.geometry.authored"

$precuWeaponBranch = $combat.IndexOf('weapon_data precuWeaponData = weapons.getNewWeaponData(objWeapon);', [StringComparison]::Ordinal)
$ngeOverloadBranch = $combat.IndexOf('if (actionData.overloadWeapon > 0)', $precuWeaponBranch, [StringComparison]::Ordinal)
$ngeElementBranch = $combat.IndexOf('weaponData.elementalValue = isPlayer(self) ? weaponData.elementalValue * 2', $ngeOverloadBranch, [StringComparison]::Ordinal)
Assert-Contract ($precuWeaponBranch -gt 0 -and $ngeOverloadBranch -gt $precuWeaponBranch -and
    $ngeElementBranch -gt $ngeOverloadBranch -and
    $combat.Contains('"preparation.ngeElementalMultiplierApplied", 0') -and
    $combat.Contains('"preparation.ngeWeaponOverloadApplied", 0')) "p14.action-preparation.weapon-values.raw"

$rampageBranch = $combat.IndexOf('int rampageAttacks = getEnhancedSkillStatisticModifierUncapped', [StringComparison]::Ordinal)
$rampageGuard = $combat.LastIndexOf('if (!precuAuthoritativeAttack)', $rampageBranch, [StringComparison]::Ordinal)
Assert-Contract ($rampageBranch -gt 0 -and $rampageGuard -ge 0) "p14.action-preparation.rampage.contained"

$combatRows = @(Import-SwgTab -Path $combatDataPath)
$burst = @($combatRows | Where-Object actionName -ceq 'burstShot1')
$lunge = @($combatRows | Where-Object actionName -ceq 'unarmedLunge1')
$flame = @($combatRows | Where-Object actionName -ceq 'flameCone1')
$autoArea = @($combatRows | Where-Object actionName -ceq 'fullAutoArea1')
$rowsValid = $burst.Count -eq 1 -and [double]$burst[0].maxRange -eq 64 -and
    [string]$burst[0].attackType -ceq 'SINGLE_TARGET' -and
    $lunge.Count -eq 1 -and [double]$lunge[0].maxRange -eq 20 -and
    [string]$lunge[0].attackType -ceq 'SINGLE_TARGET' -and
    $flame.Count -eq 1 -and [double]$flame[0].coneLength -eq 16 -and
    [double]$flame[0].coneWidth -eq 45 -and
    [string]$flame[0].attackType -ceq 'CONE' -and
    $autoArea.Count -eq 1 -and [double]$autoArea[0].coneLength -eq 64 -and
    [double]$autoArea[0].coneWidth -eq 30 -and
    [string]$autoArea[0].attackType -ceq 'CONE'
Assert-Contract $rowsValid "p14.action-preparation.authored-command-values"

$overrides = @(Import-SwgTab -Path $overridesPath)
$authenticated = @($overrides | Where-Object { @('burstShot1', 'unarmedLunge1', 'flameCone1', 'fullAutoArea1') -ccontains [string]$_.actionName })
Assert-Contract ($authenticated.Count -eq 4) "p14.action-preparation.actions.authenticated"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) "p14.action-preparation.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 Core3 action-preparation authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 Core3 action-preparation authority passed."
