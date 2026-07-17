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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14PrimaryAccuracy)) -Raw | ConvertFrom-Json
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
        throw "Required materialized primary-accuracy source is missing: $path"
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

function Get-ModeledRangeAccuracy
{
    param(
        [Parameter(Mandatory = $true)][double]$Range,
        [Parameter(Mandatory = $true)][psobject]$Profile
    )

    if ($Range -ge [double]$Profile.maxRange)
    {
        return [double]$Profile.maxRangeAccuracy
    }
    if ($Range -le [double]$Profile.pointBlankRange)
    {
        return [double]$Profile.pointBlankAccuracy
    }
    $smallRange = [double]$Profile.pointBlankRange
    $bigRange = [double]$Profile.idealRange
    $smallAccuracy = [double]$Profile.pointBlankAccuracy
    $bigAccuracy = [double]$Profile.idealAccuracy
    if ($Range -gt [double]$Profile.idealRange)
    {
        $smallRange = [double]$Profile.idealRange
        $bigRange = [double]$Profile.maxRange
        $smallAccuracy = [double]$Profile.idealAccuracy
        $bigAccuracy = [double]$Profile.maxRangeAccuracy
    }
    if ($bigRange -eq $smallRange)
    {
        return [double]$Profile.idealAccuracy
    }
    return $smallAccuracy + (($Range - $smallRange) / ($bigRange - $smallRange) * ($bigAccuracy - $smallAccuracy))
}

function Get-ModeledHitChance
{
    param(
        [Parameter(Mandatory = $true)][double]$AttackerAccuracy,
        [Parameter(Mandatory = $true)][double]$TargetDefense
    )

    $roll = ($AttackerAccuracy - $TargetDefense) / 50.0
    $sign = if ($roll -gt 0.0) { 1.0 } elseif ($roll -lt 0.0) { -1.0 } else { 0.0 }
    $toHit = 75.0
    for ($index = 1; $index -le 3; $index++)
    {
        if (($roll * $sign) -gt $index)
        {
            $toHit += $sign * 25.0
            $roll -= $sign * $index
        }
        else
        {
            $toHit += ($roll / $index) * 25.0
            break
        }
    }
    return [Math]::Max(0.0, [Math]::Min(100.0, $toHit))
}

Write-Host "Publish 14.1 Core3 primary-accuracy checks:"
Assert-Contract -Condition (
    [string]$contract.status -ceq "implemented-build-verified-live-pending") -Name "p14.primary-accuracy.status.live-pending"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq "6856f315a80b5250635b2272695caec1d64204ed" -and
    [int]$contract.semanticReference.unskilledWeaponPenalty -eq -15 -and
    [int]$contract.semanticReference.primaryDefenseCap -eq 125) -Name "p14.primary-accuracy.core3.pin-and-constants"

$overrideRows = @(Import-SwgTab -Path $paths.combatOverrides)
$profileRows = @(Import-SwgTab -Path $paths.weaponProfiles)
$skillRows = @(Import-SwgTab -Path $paths.skillTable)
$headRows = @($overrideRows | Where-Object { [string]$_.actionName -ceq [string]$contract.optIn.command })
$probeRows = @($overrideRows | Where-Object { [string]$_.actionName -ceq "__precu_runtime_probe" })
$profileRows = @($profileRows | Where-Object { [string]$_.templateName -ceq [string]$contract.optIn.weaponTemplate })
$noviceRows = @($skillRows | Where-Object { [string]$_.NAME -ceq "combat_marksman_novice" })
$rifleOneRows = @($skillRows | Where-Object { [string]$_.NAME -ceq "combat_marksman_rifle_01" })

Assert-Contract -Condition (
    $headRows.Count -eq 1 -and [int]$headRows[0].accuracyBonus -eq [int]$contract.optIn.actionAccuracyBonus) -Name "p14.primary-accuracy.headshot1.opt-in-bonus"
Assert-Contract -Condition (
    $probeRows.Count -eq 1 -and [int]$probeRows[0].accuracyBonus -eq 0) -Name "p14.primary-accuracy.runtime-probe.inert"
Assert-Contract -Condition ($profileRows.Count -eq 1) -Name "p14.primary-accuracy.cdef-profile.unique"
$profile = $profileRows[0]
Assert-Contract -Condition (
    [double]$profile.pointBlankRange -eq 0 -and [double]$profile.pointBlankAccuracy -eq 20 -and
    [double]$profile.idealRange -eq 15 -and [double]$profile.idealAccuracy -eq 50 -and
    [double]$profile.maxRange -eq 64 -and [double]$profile.maxRangeAccuracy -eq -80) -Name "p14.primary-accuracy.cdef-profile.range-curve"
Assert-Contract -Condition (
    [string]$profile.accuracySkill -ceq "rifle_accuracy" -and
    [string]$profile.categoryAccuracySkill -ceq "ranged_accuracy" -and
    [string]$profile.defenseSkill -ceq "ranged_defense" -and
    [string]$profile.weaponFamily -ceq "rifle" -and
    [double]$profile.postureMultiplier -eq 2.5) -Name "p14.primary-accuracy.cdef-profile.modifiers"
Assert-Contract -Condition (
    $noviceRows.Count -eq 1 -and [string]$noviceRows[0].SKILL_MODS -match 'ranged_accuracy=10' -and
    $rifleOneRows.Count -eq 1 -and [string]$rifleOneRows[0].SKILL_MODS -match 'rifle_accuracy=10') -Name "p14.primary-accuracy.fixture.skill-modifiers"

$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$primaryResult = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuPrimaryAttackResult("
$primaryChance = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuPrimaryHitChance("
$attackerAccuracy = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuAttackerAccuracyTotal("
$rangeCurve = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuWeaponRangeModifier("
$equation = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuHitChanceEquation("
$attackPosture = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuRangedAttackLocomotionModifier("
$defensePosture = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuRangedDefenseLocomotionModifier("

Assert-Contract -Condition (
    $primaryChance.Contains('dataTableSearchColumnForString(actionData.actionName, "actionName", PRECU_COMBAT_OVERRIDES)') -and
    $primaryChance.Contains('dataTableSearchColumnForString(weaponTemplate, "templateName", PRECU_WEAPON_PROFILES)')) -Name "p14.primary-accuracy.runtime.exact-opt-in-and-profile"
Assert-Contract -Condition (
    ([regex]::Matches($primaryChance, 'return -1\.0f;').Count -ge 3) -and
    $primaryChance.Contains('if (accuracyBonus <= 0 || !isIdValid(weaponData.id))')) -Name "p14.primary-accuracy.runtime.fail-closed"
Assert-Contract -Condition (
    $primaryChance.Contains('getPrecuAttackerAccuracyTotal(attackerData, defenderData, weaponRow, accuracyBonus)') -and
    $attackerAccuracy.Contains('accuracySkillValue = -15;') -and
    $attackerAccuracy.Contains('getEnhancedSkillStatisticModifierUncapped(attackerData.id, categoryAccuracySkill)') -and
    $attackerAccuracy.Contains('getEnhancedSkillStatisticModifierUncapped(attackerData.id, "private_ranged_accuracy_bonus")')) -Name "p14.primary-accuracy.runtime.attacker-modifier-stack"
Assert-Contract -Condition (
    $primaryChance.Contains('int defenseSkillValue = getLevel(defenderData.id);') -and
    $primaryChance.Contains('if (defenseSkillValue > 125)') -and
    $primaryChance.Contains('getEnhancedSkillStatisticModifierUncapped(defenderData.id, "private_group_" + defenseSkill)') -and
    $primaryChance.Contains('getEnhancedSkillStatisticModifierUncapped(defenderData.id, "private_dodge_attack")')) -Name "p14.primary-accuracy.runtime.defender-modifier-stack"
Assert-Contract -Condition (
    $rangeCurve.Contains('attackerData.worldPos.distance(defenderData.worldPos) - (attackerData.radius + defenderData.radius)') -and
    $rangeCurve.Contains('return smallAccuracy + ((currentRange - smallRange) / (bigRange - smallRange) * (bigAccuracy - smallAccuracy));')) -Name "p14.primary-accuracy.runtime.range-interpolation"
Assert-Contract -Condition (
    $equation.Contains('(attackerAccuracy - targetDefense) / 50.0f') -and
    $equation.Contains('float toHit = 75.0f;') -and
    $equation.Contains('for (int i = 1; i <= 3; i++)') -and
    $equation.Contains('toHit += sign * 25.0f;')) -Name "p14.primary-accuracy.runtime.core3-equation"
Assert-Contract -Condition (
    $attackPosture.Contains('case LOCOMOTION_RUNNING:') -and $attackPosture.Contains('return -60;') -and
    $attackPosture.Contains('case LOCOMOTION_PRONE:') -and $attackPosture.Contains('return 30;') -and
    $defensePosture.Contains('case LOCOMOTION_STANDING:') -and $defensePosture.Contains('return -10;') -and
    $defensePosture.Contains('case LOCOMOTION_RUNNING:') -and $defensePosture.Contains('return 45;')) -Name "p14.primary-accuracy.runtime.core3-locomotion-table"
Assert-Contract -Condition (
    $primaryResult.Contains('int hitRoll = rand(0, 100);') -and
    $primaryResult.Contains('int result = hitRoll <= hitChance ? HIT_RESULT_HIT : HIT_RESULT_MISS;') -and
    $primaryResult.Contains('return result;') -and
    $combatBase.Contains('int defResult = precuPrimaryResult == PRECU_PRIMARY_RESULT_FALLBACK ? getDefenderResult(attackerData, defenderData[i], actionData, isAutoAiming) : precuSecondaryResult;') -and
    $combatBase.Contains('int atkResult = precuPrimaryResult == PRECU_PRIMARY_RESULT_FALLBACK ? getAttackerResult(attackerData, defenderData[i], actionData, isAutoAiming) : precuPrimaryResult;')) -Name "p14.primary-accuracy.runtime.authoritative-no-hybrid-primary"

$dormant = Get-Content -LiteralPath $paths.dormantHitEngine -Raw
Assert-Contract -Condition (
    $dormant.Contains('// TODO: COMBAT_UPGRADE: Add Accuracy') -and
    $dormant.Contains('//result.baseRoll = random.rand(1, 250);') -and
    $dormant.Contains('result.baseRoll = skillMod + attacker.scriptMod;')) -Name "p14.primary-accuracy.dormant-engine.excluded-as-authority"

$neutralIdeal = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 15 -Profile $profile) - 15 + 5) -TargetDefense -9
$marksmanIdeal = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 15 -Profile $profile) + 20 + 5) -TargetDefense -9
$marksmanMax = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 64 -Profile $profile) + 20 + 5) -TargetDefense -9
$marksmanRunning = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 15 -Profile $profile) + 20 + 5 - 150) -TargetDefense -9
$withoutActionBonus = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 64 -Profile $profile) + 20) -TargetDefense -9
Assert-Contract -Condition ([Math]::Abs($neutralIdeal - [double]$contract.modeledAcceptance.neutralIdealRangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.neutral-ideal"
Assert-Contract -Condition ([Math]::Abs($marksmanIdeal - [double]$contract.modeledAcceptance.marksmanNoviceRifleOneIdealRangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.marksman-ideal"
Assert-Contract -Condition ([Math]::Abs($marksmanMax - [double]$contract.modeledAcceptance.marksmanNoviceRifleOneMaxRangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.marksman-max"
Assert-Contract -Condition ([Math]::Abs($marksmanRunning - [double]$contract.modeledAcceptance.marksmanNoviceRifleOneRunningIdealRangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.running-ideal"
Assert-Contract -Condition ([Math]::Abs($withoutActionBonus - [double]$contract.modeledAcceptance.maxRangeChanceWithoutActionBonus) -lt 0.000001) -Name "p14.primary-accuracy.model.action-bonus-observable"
Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    @($contract.buildEvidence.targets).Count -eq 3) -Name "p14.primary-accuracy.isolated-build.evidence"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 primary-accuracy contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Core3 primary-accuracy implementation passed its build/static gate; live accuracy remains pending and secondary outcomes are gated separately."
