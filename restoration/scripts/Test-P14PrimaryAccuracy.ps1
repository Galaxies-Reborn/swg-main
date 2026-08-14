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
    [string]$contract.status -ceq "ready") -Name "p14.primary-accuracy.status.ready"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq "6856f315a80b5250635b2272695caec1d64204ed" -and
    [int]$contract.semanticReference.unskilledWeaponPenalty -eq -15 -and
    [int]$contract.semanticReference.primaryDefenseCap -eq 125) -Name "p14.primary-accuracy.core3.pin-and-constants"

$commandRows = @(Import-SwgTab -Path $paths.commandTable)
$overrideRows = @(Import-SwgTab -Path $paths.combatOverrides)
$profileRows = @(Import-SwgTab -Path $paths.weaponProfiles)
$skillRows = @(Import-SwgTab -Path $paths.skillTable)
$headRows = @($overrideRows | Where-Object { [string]$_.actionName -ceq [string]$contract.optIn.command })
$headCommands = @($commandRows | Where-Object { [string]$_.commandName -ceq [string]$contract.optIn.command })
$probeRows = @($overrideRows | Where-Object { [string]$_.actionName -ceq "__precu_runtime_probe" })
$profileRows = @($profileRows | Where-Object { [string]$_.templateName -ceq [string]$contract.optIn.weaponTemplate })
$noviceRows = @($skillRows | Where-Object { [string]$_.NAME -ceq "combat_marksman_novice" })
$rifleOneRows = @($skillRows | Where-Object { [string]$_.NAME -ceq "combat_marksman_rifle_01" })

Assert-Contract -Condition (
    $headRows.Count -eq 1 -and [int]$headRows[0].accuracyBonus -eq [int]$contract.optIn.actionAccuracyBonus) -Name "p14.primary-accuracy.headshot1.opt-in-bonus"
Assert-Contract -Condition (
    $headCommands.Count -eq 1 -and
    [double]$headCommands[0].maxRangeToTarget -eq [double]$contract.optIn.clientMaxRangeToTarget) -Name "p14.primary-accuracy.headshot1.client-admission-range"
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
    $noviceRows.Count -eq 1 -and [string]$noviceRows[0].SKILL_MODS -match 'rifle_accuracy=10' -and
    $rifleOneRows.Count -eq 1 -and [string]$rifleOneRows[0].SKILL_MODS -match 'rifle_accuracy=10') -Name "p14.primary-accuracy.fixture.skill-modifiers"

$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$primaryResult = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuPrimaryAttackResult("
$primaryChance = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuPrimaryHitChance("
$attackerAccuracy = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuAttackerAccuracyTotal("
$rangeCurve = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuWeaponRangeModifier("
$equation = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuHitChanceEquation("
$attackPosture = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuRangedAttackLocomotionModifier("
$defensePosture = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuRangedDefenseLocomotionModifier("
$liveFixture = Get-Content -LiteralPath $paths.liveFixture -Raw

Assert-Contract -Condition (
    $primaryChance.Contains('dataTableSearchColumnForString(actionData.actionName, "actionName", PRECU_COMBAT_OVERRIDES)') -and
    $primaryChance.Contains('if (!isPrecuAuthoritativeAttack(attackerData.id, actionData))') -and
    $primaryChance.Contains('int weaponRow = getPrecuWeaponProfileRow(weaponData);')) -Name "p14.primary-accuracy.runtime.authenticated-action-or-profile"
Assert-Contract -Condition (
    $primaryChance.Contains('int accuracyBonus = actionRow >= 0 ?') -and
    $primaryChance.Contains('getPrecuActionAccuracyBonus(attackerData.id, actionRow) : 0;') -and
    $primaryChance.Contains('if (weaponRow < 0)') -and
    -not $primaryChance.Contains('accuracyBonus <= 0')) -Name "p14.primary-accuracy.runtime.zero-bonus-is-valid"
Assert-Contract -Condition (
    $primaryChance.Contains('getPrecuAttackerAccuracyTotal(attackerData, defenderData, weaponRow, accuracyBonus)') -and
    $attackerAccuracy.Contains('accuracySkillValue = -15;') -and
    $attackerAccuracy.Contains('getEnhancedSkillStatisticModifierUncapped(attackerData.id, categoryAccuracySkill)') -and
    $attackerAccuracy.Contains('"private_ranged_accuracy_bonus"') -and
    $attackerAccuracy.Contains('"private_melee_accuracy_bonus"')) -Name "p14.primary-accuracy.runtime.attacker-modifier-stack"
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
Assert-Contract -Condition (
    $liveFixture.Contains('equalsIgnoreCase("armPrimaryIdeal")') -and
    $liveFixture.Contains('armPrimaryRange(attacker, defender, args[3], "ideal", 16.0f)') -and
    $liveFixture.Contains('equalsIgnoreCase("armPrimaryNearMax")') -and
    $liveFixture.Contains('armPrimaryRange(attacker, defender, args[3], "nearMax", 64.0f)') -and
    $liveFixture.Contains('equalsIgnoreCase("armPrimaryFallback")') -and
    $liveFixture.Contains('armPrimaryRange(attacker, defender, args[3], "fallback", 6.0f)') -and
    $liveFixture.Contains('resetLiveDiagnostic(attacker);') -and
    $liveFixture.Contains('float attackerX = 1000.0f;') -and
    $liveFixture.Contains('float attackerZ = 1000.0f;') -and
    $liveFixture.Contains('float defenderZ = attackerZ + centerSeparationMeters;') -and
    $liveFixture.Contains('getHeightAtLocation(attackerX, attackerZ)') -and
    $liveFixture.Contains('getHeightAtLocation(defenderX, defenderZ)') -and
    $liveFixture.Contains('boolean pvpReady =') -and
    $liveFixture.Contains('pvpCanAttack(attacker, defender) &') -and
    $liveFixture.Contains('if (!moved || !stateReady || !pvpReady || !hamReady ||') -and
    $liveFixture.Contains('setLocation(attacker, attackerDestination)') -and
    $liveFixture.Contains('setLocation(defender, defenderDestination)') -and
    -not $liveFixture.Contains('setWeaponRangeInfo(') -and
    $liveFixture.Contains('" globalMaxCombatRange=" + combat_engine.getMaxCombatRange()') -and
    $liveFixture.Contains('" attackerWeaponMaxRange=" +') -and
    $liveFixture.Contains('" headShot1MaxRange=" + headShotMaxRange') -and
    $liveFixture.Contains('" lineOfSight=" + canSee(attacker, defender)')) -Name "p14.primary-accuracy.fixture.reversible-range-controls"

$dormant = Get-Content -LiteralPath $paths.dormantHitEngine -Raw
Assert-Contract -Condition (
    $dormant.Contains('// TODO: COMBAT_UPGRADE: Add Accuracy') -and
    $dormant.Contains('//result.baseRoll = random.rand(1, 250);') -and
    $dormant.Contains('result.baseRoll = skillMod + attacker.scriptMod;')) -Name "p14.primary-accuracy.dormant-engine.excluded-as-authority"

$neutralIdeal = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 15 -Profile $profile) - 15 + 5) -TargetDefense -9
$marksmanIdeal = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 15 -Profile $profile) + 20 + 5) -TargetDefense -9
$marksmanNearMax = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 63 -Profile $profile) + 20 + 5) -TargetDefense -9
$marksmanMax = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 64 -Profile $profile) + 20 + 5) -TargetDefense -9
$marksmanRunning = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 15 -Profile $profile) + 20 + 5 - 150) -TargetDefense -9
$withoutActionBonus = Get-ModeledHitChance -AttackerAccuracy ((Get-ModeledRangeAccuracy -Range 64 -Profile $profile) + 20) -TargetDefense -9
Assert-Contract -Condition ([Math]::Abs($neutralIdeal - [double]$contract.modeledAcceptance.neutralIdealRangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.neutral-ideal"
Assert-Contract -Condition ([Math]::Abs($marksmanIdeal - [double]$contract.modeledAcceptance.marksmanNoviceRifleOneIdealRangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.marksman-ideal"
Assert-Contract -Condition ([Math]::Abs($marksmanNearMax - [double]$contract.modeledAcceptance.marksmanNoviceRifleOneNearMax63RangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.marksman-near-max"
Assert-Contract -Condition ([Math]::Abs($marksmanMax - [double]$contract.modeledAcceptance.marksmanNoviceRifleOneMaxRangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.marksman-max"
Assert-Contract -Condition ([Math]::Abs($marksmanRunning - [double]$contract.modeledAcceptance.marksmanNoviceRifleOneRunningIdealRangeChance) -lt 0.000001) -Name "p14.primary-accuracy.model.running-ideal"
Assert-Contract -Condition ([Math]::Abs($withoutActionBonus - [double]$contract.modeledAcceptance.maxRangeChanceWithoutActionBonus) -lt 0.000001) -Name "p14.primary-accuracy.model.action-bonus-observable"
Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    @($contract.buildEvidence.targets).Count -eq 5 -and
    [string]$contract.buildEvidence.materializationFingerprint -ceq "87692599a2e9509d6f551fff30cdcf3ee1d5c7531caba1d383bce4d7268bec7e" -and
    [string]$contract.buildEvidence.compiledSha256.combatBase -ceq "c623c033e34ca52d1787b74ba41c0257184c4ba183230f4a93b47a15111ace6f" -and
    [string]$contract.buildEvidence.compiledSha256.liveFixture -ceq "708fc824e45c2aa9a1a3f539831c334dee69d70930410a09d2a72fb4bc08dafd" -and
    [string]$contract.buildEvidence.compiledSha256.commandTable -ceq "e756e50ecd19d60620d88a22bf721b594fea2268607a6dd614af9f39f537f083") -Name "p14.primary-accuracy.isolated-build.evidence"

$ideal = $contract.liveEvidence.idealRange
$nearMaximum = $contract.liveEvidence.nearMaximumRange
$fallback = $contract.liveEvidence.fallbackControl
Assert-Contract -Condition (
    [string]$contract.liveEvidence.lifecycle -ceq "f2b6c3e59f874b77a217202607170013" -and
    [string]$contract.liveEvidence.container -ceq "swg-precu" -and
    [int]$contract.liveEvidence.clientBridgeProtocol -eq 13 -and
    [string]$contract.liveEvidence.clientExeSha256 -ceq "10f643b881239550ad4c479d706d32eab7326670ce987bb5288ce316063bb909" -and
    [string]$contract.liveEvidence.serverBinarySha256 -ceq "2c309c5ede3d4bc417fc6094110c4135dacc621272b31e3b2247a340c4d5f001" -and
    [string]$contract.liveEvidence.compiledCombatBaseSha256 -ceq "c623c033e34ca52d1787b74ba41c0257184c4ba183230f4a93b47a15111ace6f" -and
    [string]$contract.liveEvidence.compiledFixtureSha256 -ceq "708fc824e45c2aa9a1a3f539831c334dee69d70930410a09d2a72fb4bc08dafd" -and
    [string]$contract.liveEvidence.compiledCommandTableSha256 -ceq "e756e50ecd19d60620d88a22bf721b594fea2268607a6dd614af9f39f537f083") -Name "p14.primary-accuracy.live.identity-and-artifacts"
Assert-Contract -Condition (
    [string]$contract.clientAssetPublication.status -ceq "published" -and
    [string]$contract.clientAssetPublication.commit -ceq "5f18e2956d878b6b9fc2f929a0c1a00ddbb4caed" -and
    [string]$contract.clientAssetPublication.sha256 -ceq "e756e50ecd19d60620d88a22bf721b594fea2268607a6dd614af9f39f537f083" -and
    [string]$contract.clientToolPublication.status -ceq "published" -and
    [string]$contract.clientToolPublication.commit -ceq "47c7a55cdf9bec5459cbb6c04dd9fca5bf053b5e" -and
    [int]$contract.clientToolPublication.clientBridgeProtocol -eq 13) -Name "p14.primary-accuracy.client-publications"
Assert-Contract -Condition (
    [string]$ideal.command -ceq "headShot1" -and
    [int]$ideal.distanceCentimeters -eq 1504 -and
    [string]$ideal.queueResult -ceq "Success" -and
    [int]$ideal.serverExecuteMaxMs -eq 4725 -and
    [int]$ideal.primaryAccuracySkill -eq 20 -and
    [int]$ideal.primaryAccuracyBonus -eq 5 -and
    [Math]::Abs([double]$ideal.primaryAccuracyTotal - 74.884445) -lt 0.000001 -and
    [double]$ideal.primaryDefenseTotal -eq -9.0 -and
    [double]$ideal.hitChance -eq 100.0 -and
    [string]$ideal.result -ceq "HIT" -and
    [string]$ideal.secondaryProfile -ceq "RANDOM" -and
    [string]$ideal.secondaryResult -ceq "HIT" -and
    [int]$ideal.defenderMindAfter -lt [int]$ideal.defenderMindBefore) -Name "p14.primary-accuracy.live.ideal-range"
Assert-Contract -Condition (
    [string]$nearMaximum.command -ceq "headShot1" -and
    [int]$nearMaximum.distanceCentimeters -eq 6299 -and
    [string]$nearMaximum.queueResult -ceq "Success" -and
    [int]$nearMaximum.serverExecuteMaxMs -eq 4725 -and
    [int]$nearMaximum.primaryAccuracySkill -eq 20 -and
    [int]$nearMaximum.primaryAccuracyBonus -eq 5 -and
    [Math]::Abs([double]$nearMaximum.primaryAccuracyTotal - -52.323494) -lt 0.000001 -and
    [double]$nearMaximum.primaryDefenseTotal -eq -9.0 -and
    [Math]::Abs([double]$nearMaximum.hitChance - 53.338253) -lt 0.000001 -and
    [string]$nearMaximum.result -ceq "HIT" -and
    [string]$nearMaximum.secondaryProfile -ceq "RANDOM" -and
    [string]$nearMaximum.secondaryResult -ceq "HIT" -and
    [int]$nearMaximum.defenderMindAfter -lt [int]$nearMaximum.defenderMindBefore) -Name "p14.primary-accuracy.live.near-maximum-range"
Assert-Contract -Condition (
    [string]$fallback.command -ceq "headShot2" -and
    [int]$fallback.distanceCentimeters -eq 720 -and
    [string]$fallback.queueResult -ceq "Success" -and
    [int]$fallback.serverExecuteMaxMs -eq 1500 -and
    [string]$fallback.diagnosticPrimaryResult -ceq "FALLBACK" -and
    [int]$fallback.attackerActionAfter -lt [int]$fallback.attackerActionBefore -and
    [int]$fallback.defenderHealthAfter -lt [int]$fallback.defenderHealthBefore) -Name "p14.primary-accuracy.live.non-opted-fallback"
Assert-Contract -Condition (
    [bool]$contract.liveEvidence.cleanup.tier1Restored -and
    [bool]$contract.liveEvidence.cleanup.headShotLayerRestored -and
    [bool]$contract.liveEvidence.cleanup.skillsRemoved -and
    [bool]$contract.liveEvidence.cleanup.fixtureWeaponsRemoved -and
    [bool]$contract.liveEvidence.cleanup.pvpRestored -and
    [bool]$contract.liveEvidence.cleanup.hamRestored -and
    [bool]$contract.liveEvidence.cleanup.diagnosticObjvarsRemoved -and
    @($contract.requiredBeforeReady).Count -eq 0) -Name "p14.primary-accuracy.live.cleanup-and-ready-boundary"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 primary-accuracy contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Core3 primary-accuracy build/static, live execution, fallback, and cleanup acceptance passed; secondary outcomes remain gated separately."
