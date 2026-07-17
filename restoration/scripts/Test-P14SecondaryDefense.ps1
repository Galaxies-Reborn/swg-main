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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14SecondaryDefense)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized secondary-defense source is missing: $path"
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

function Get-BracedBlock
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Signature
    )

    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0)
    {
        return ""
    }
    $openBrace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($openBrace -lt 0)
    {
        return ""
    }

    $depth = 0
    for ($index = $openBrace; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{')
        {
            $depth++
        }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    return ""
}

Write-Host "Publish 14.1 Core3 secondary-defense checks:"
Assert-Contract -Condition (
    [string]$contract.status -ceq "implemented-build-verified-live-pending") -Name "p14.secondary-defense.status.live-pending"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq "6856f315a80b5250635b2272695caec1d64204ed" -and
    [int]$contract.semanticReference.secondaryDefenseCap -eq 125 -and
    [int]$contract.semanticReference.attackRollMinimum -eq 1 -and
    [int]$contract.semanticReference.attackRollMaximum -eq 500 -and
    [int]$contract.semanticReference.defendRollMinimum -eq 1 -and
    [int]$contract.semanticReference.defendRollMaximum -eq 200) -Name "p14.secondary-defense.core3.pin-cap-and-rolls"

$profileRows = @(Import-SwgTab -Path $paths.weaponProfiles)
$cdefRows = @($profileRows | Where-Object { [string]$_.templateName -ceq "object/weapon/ranged/rifle/rifle_cdef.iff" })
$unarmedRows = @($profileRows | Where-Object { [string]$_.templateName -ceq "object/weapon/melee/unarmed/unarmed_default_player.iff" })
Assert-Contract -Condition (
    $cdefRows.Count -eq 1 -and
    [string]$cdefRows[0].secondaryDefenseSkill -ceq "block" -and
    [string]$cdefRows[0].secondaryDefenseResult -ceq "BLOCK") -Name "p14.secondary-defense.profile.cdef-block"
Assert-Contract -Condition (
    $unarmedRows.Count -eq 1 -and
    [double]$unarmedRows[0].attackSpeed -eq 2 -and
    [string]$unarmedRows[0].accuracySkill -ceq "unarmed_accuracy" -and
    [string]$unarmedRows[0].defenseSkill -ceq "melee_defense" -and
    [string]$unarmedRows[0].secondaryDefenseSkill -ceq "unarmed_passive_defense" -and
    [string]$unarmedRows[0].secondaryDefenseResult -ceq "RANDOM") -Name "p14.secondary-defense.profile.player-unarmed"

$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$combatEngine = Get-Content -LiteralPath $paths.combatEngine -Raw
$legacyCombatBase = Get-Content -LiteralPath $paths.legacyCombatBase -Raw
$secondary = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuSecondaryDefenseResult("
$resultCode = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuSecondaryDefenseResultCode("
$counter = Get-BracedBlock -Text $combatBase -Signature "public void doPrecuCounterAttack("
$attackerAccuracy = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuAttackerAccuracyTotal("

Assert-Contract -Condition (
    $combatEngine.Contains("public boolean precuBlock = false;") -and
    $combatEngine.Contains("public boolean precuCounter = false;")) -Name "p14.secondary-defense.hit-result.explicit-flags"
Assert-Contract -Condition (
    $combatBase.Contains("if (precuPrimaryResult == HIT_RESULT_HIT)") -and
    $combatBase.Contains("precuSecondaryResult = getPrecuSecondaryDefenseResult(attackerData, defenderData[i], weaponData, actionData);")) -Name "p14.secondary-defense.integration.after-primary-hit-only"
Assert-Contract -Condition (
    $combatBase.Contains("if (precuSecondaryResult == PRECU_SECONDARY_RESULT_FALLBACK)") -and
    $combatBase.Contains("precuPrimaryResult = PRECU_PRIMARY_RESULT_FALLBACK;") -and
    $combatBase.Contains("int defResult = precuPrimaryResult == PRECU_PRIMARY_RESULT_FALLBACK ? getDefenderResult") -and
    $combatBase.Contains("int atkResult = precuPrimaryResult == PRECU_PRIMARY_RESULT_FALLBACK ? getAttackerResult")) -Name "p14.secondary-defense.integration.complete-nge-fallback"
Assert-Contract -Condition (
    $secondary.Contains('getCurrentWeapon(defenderData.id)') -and
    $secondary.Contains('dataTableSearchColumnForString(getTemplateName(defenderWeapon), "templateName", PRECU_WEAPON_PROFILES)') -and
    ([regex]::Matches($secondary, 'return PRECU_SECONDARY_RESULT_FALLBACK;').Count -ge 4)) -Name "p14.secondary-defense.runtime.exact-defender-profile"
Assert-Contract -Condition (
    $secondary.Contains('getState(defenderData.id, STATE_INTIMIDATED) > 0') -and
    $secondary.Contains('getState(defenderData.id, STATE_BERSERK) > 0') -and
    $secondary.Contains('vehicle.isVehicle(defenderData.id)')) -Name "p14.secondary-defense.runtime.core3-state-suppression"
Assert-Contract -Condition (
    $secondary.Contains('int evadeSkill = getLevel(defenderData.id);') -and
    $secondary.Contains('getEnhancedSkillStatisticModifierUncapped(defenderData.id, secondaryDefenseSkill)') -and
    $secondary.Contains('getEnhancedSkillStatisticModifierUncapped(defenderData.id, "private_" + secondaryDefenseSkill)') -and
    $secondary.Contains('if (evadeSkill > 125)')) -Name "p14.secondary-defense.runtime.skill-stack-and-cap"
Assert-Contract -Condition (
    $secondary.Contains('getEnhancedSkillStatisticModifierUncapped(defenderData.id, "private_center_of_being")') -and
    $secondary.Contains('getPrecuRangedDefenseLocomotionModifier(defenderData.locomotion)')) -Name "p14.secondary-defense.runtime.center-and-posture"
Assert-Contract -Condition (
    $secondary.Contains('int attackRoll = rand(1, 500);') -and
    $secondary.Contains('int defendRoll = rand(1, 200);') -and
    $secondary.Contains('accuracyTotal + attackRoll <= evadeTotal + defendRoll ? defendResult : HIT_RESULT_HIT;')) -Name "p14.secondary-defense.runtime.core3-roll-equation"
Assert-Contract -Condition (
    $resultCode.Contains('secondaryDefenseResult.equals("BLOCK")') -and
    $resultCode.Contains('secondaryDefenseResult.equals("DODGE")') -and
    $resultCode.Contains('secondaryDefenseResult.equals("COUNTER")')) -Name "p14.secondary-defense.runtime.profile-result-map"
Assert-Contract -Condition (
    $resultCode.Contains('int resultRoll = rand(1, 3);') -and
    $resultCode.Contains('resultRoll == 1 ? HIT_RESULT_BLOCK : resultRoll == 2 ? HIT_RESULT_DODGE : HIT_RESULT_PRECU_COUNTER;')) -Name "p14.secondary-defense.runtime.unarmed-random-map"
Assert-Contract -Condition (
    $attackerAccuracy.Contains('getPrecuWeaponRangeModifier(attackerData, defenderData, weaponRow)') -and
    $secondary.Contains('getPrecuAttackerAccuracyTotal(attackerData, defenderData, attackerWeaponRow, accuracyBonus)')) -Name "p14.secondary-defense.runtime.shared-primary-accuracy-total"

Assert-Contract -Condition (
    $combatBase.Contains('hitData[i].precuBlock = true;') -and
    $combatBase.Contains('hitData[i].blockResult = true;') -and
    $combatBase.Contains('if (precuPrimaryResult == PRECU_PRIMARY_RESULT_FALLBACK)')) -Name "p14.secondary-defense.block.separate-from-nge-block"
Assert-Contract -Condition (
    $combatBase.Contains('hitData[i].damage = hitData[i].damage / 2;') -and
    $combatBase.Contains('weaponData.elementalValue = weaponData.elementalValue / 2;') -and
    $combatBase.Contains('hitData[i].blockedDamage += damageBeforeBlock - hitData[i].damage;') -and
    $combatBase.Contains('weaponData.elementalValue = originalElementalValue;')) -Name "p14.secondary-defense.block.half-base-and-elemental"
Assert-Contract -Condition (
    $combatBase.Contains('defenderResults[i].result = hitData[i].precuBlock ? COMBAT_RESULT_BLOCK : COMBAT_RESULT_HIT;')) -Name "p14.secondary-defense.block.result-visible"
Assert-Contract -Condition (
    $resultCode.Contains('return HIT_RESULT_DODGE;') -and
    $combatBase.Contains('hitData[i].success = false;') -and
    $combatBase.Contains('hitData[i].dodge = true;')) -Name "p14.secondary-defense.dodge.negates-damage"
Assert-Contract -Condition (
    $combatBase.Contains('case HIT_RESULT_PRECU_COUNTER:') -and
    $combatBase.Contains('hitData[i].precuCounter = true;') -and
    $combatBase.Contains('else if (hitData[i].precuCounter)') -and
    $combatBase.Contains('defenderResults[i].result = COMBAT_RESULT_COUNTER;')) -Name "p14.secondary-defense.counter.negates-damage-and-reports"
Assert-Contract -Condition (
    $counter.Contains('startCombat(defender, attacker);') -and
    $counter.Contains('queueCommand(defender, PRECU_COUNTERATTACK_COMMAND, attacker, "", COMMAND_PRIORITY_FRONT);') -and
    $combatBase.Contains('public static final int PRECU_COUNTERATTACK_COMMAND = 1957054281;')) -Name "p14.secondary-defense.counter.basic-response-command"
Assert-Contract -Condition (
    $legacyCombatBase.Contains('queueCommand(objDefender, (1957054281), objAttacker, "", COMMAND_PRIORITY_FRONT);') -and
    $legacyCombatBase.Contains('cbtDefenderResults[intI].result = COMBAT_RESULT_COUNTER;')) -Name "p14.secondary-defense.counter.legacy-swgsource-plumbing"

$successfulPairs = 0
for ($attackRoll = [int]$contract.semanticReference.attackRollMinimum; $attackRoll -le [int]$contract.semanticReference.attackRollMaximum; $attackRoll++)
{
    for ($defendRoll = [int]$contract.semanticReference.defendRollMinimum; $defendRoll -le [int]$contract.semanticReference.defendRollMaximum; $defendRoll++)
    {
        if ([double]$contract.modeledAcceptance.attackerAccuracyTotal + $attackRoll -le
            [double]$contract.modeledAcceptance.defenderStandingEvadeTotal + $defendRoll)
        {
            $successfulPairs++
        }
    }
}
$totalPairs = ([int]$contract.semanticReference.attackRollMaximum - [int]$contract.semanticReference.attackRollMinimum + 1) *
    ([int]$contract.semanticReference.defendRollMaximum - [int]$contract.semanticReference.defendRollMinimum + 1)
$secondaryChance = $successfulPairs / [double]$totalPairs
Assert-Contract -Condition (
    $successfulPairs -eq [int]$contract.modeledAcceptance.successfulSecondaryPairs -and
    $totalPairs -eq [int]$contract.modeledAcceptance.totalRollPairs -and
    [Math]::Abs($secondaryChance - [double]$contract.modeledAcceptance.totalSecondaryChance) -lt 0.000000001) -Name "p14.secondary-defense.model.neutral-total-chance"
Assert-Contract -Condition (
    [Math]::Abs(($secondaryChance / 3.0) - [double]$contract.modeledAcceptance.eachUnarmedOutcomeChance) -lt 0.000000001) -Name "p14.secondary-defense.model.each-unarmed-outcome"
Assert-Contract -Condition (
    @($contract.narrowBoundary.deferred | Where-Object { [string]$_ -match 'ricochet' }).Count -eq 1) -Name "p14.secondary-defense.boundary.ricochet-explicitly-deferred"
Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    @($contract.buildEvidence.targets).Count -eq 3) -Name "p14.secondary-defense.isolated-build.evidence"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 secondary-defense contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Core3 block/dodge/counter implementation passed its build/static gate; live outcomes and lightsaber ricochet remain pending."
