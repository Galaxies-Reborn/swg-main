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
    [string]$contract.status -ceq "ready" -and
    @($contract.requiredBeforeReady).Count -eq 0) -Name "p14.secondary-defense.status.ready"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq "6856f315a80b5250635b2272695caec1d64204ed" -and
    [int]$contract.semanticReference.secondaryDefenseCap -eq 125 -and
    [int]$contract.semanticReference.attackRollMinimum -eq 1 -and
    [int]$contract.semanticReference.attackRollMaximum -eq 500 -and
    [int]$contract.semanticReference.defendRollMinimum -eq 1 -and
    [int]$contract.semanticReference.defendRollMaximum -eq 200 -and
    [int]$contract.semanticReference.saberBlockRollMinimum -eq 0 -and
    [int]$contract.semanticReference.saberBlockRollMaximum -eq 100) -Name "p14.secondary-defense.core3.pin-cap-and-rolls"

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
$jediLibrary = Get-Content -LiteralPath $paths.jediLibrary -Raw
$legacyCombatBase = Get-Content -LiteralPath $paths.legacyCombatBase -Raw
$liveFixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$fixtureWeaponTemplate = Get-Content -LiteralPath $paths.fixtureWeaponTemplate -Raw
$secondary = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuSecondaryDefenseResult("
$resultCode = Get-BracedBlock -Text $combatBase -Signature "public int getPrecuSecondaryDefenseResultCode("
$counter = Get-BracedBlock -Text $combatBase -Signature "public boolean doPrecuCounterAttack("
$attackerAccuracy = Get-BracedBlock -Text $combatBase -Signature "public float getPrecuAttackerAccuracyTotal("
$hitEngine = Get-BracedBlock -Text $combatBase -Signature "public hit_result[] runHitEngine(attacker_data attackerData, weapon_data weaponData, defender_data[] defenderData, attacker_results attackerResults, defender_results[] defenderResults, combat_data actionData, boolean isTangibleAttacking, boolean isAutoAiming, int overloadDamage)"

Assert-Contract -Condition (
    $combatEngine.Contains("public boolean precuBlock = false;") -and
    $combatEngine.Contains("public boolean precuCounter = false;") -and
    $combatEngine.Contains("public boolean precuRicochet = false;")) -Name "p14.secondary-defense.hit-result.explicit-flags"
Assert-Contract -Condition (
    $hitEngine.Contains("if (precuPrimaryResult == HIT_RESULT_HIT)") -and
    $hitEngine.Contains("precuSecondaryResult = getPrecuSecondaryDefenseResult(")) -Name "p14.secondary-defense.integration.after-primary-hit-only"
Assert-Contract -Condition (
    $hitEngine.Contains("if (precuAuthoritativeAttack)") -and
    $hitEngine.Contains("precuSecondaryResult = HIT_RESULT_HIT;") -and
    $hitEngine.Contains("defResult = precuSecondaryResult;") -and
    $hitEngine.Contains("atkResult = precuPrimaryResult;") -and
    -not $hitEngine.Contains("precuPrimaryResult == PRECU_PRIMARY_RESULT_FALLBACK ?")) -Name "p14.secondary-defense.integration.precu-fails-closed"
Assert-Contract -Condition (
    $secondary.Contains('getHeldWeapon(defenderData.id)') -and
    $secondary.Contains('getCurrentWeapon(defenderData.id)') -and
    $secondary.Contains('getPrecuWeaponProfileRow(defenderWeapon)') -and
    -not $secondary.Contains('FALLBACK_NO_WEAPON')) -Name "p14.secondary-defense.runtime.exact-or-family-defender-profile"
Assert-Contract -Condition (
    $secondary.IndexOf('jedi.isLightsaber(defenderWeapon) ||', [StringComparison]::Ordinal) -ge 0 -and
    $secondary.IndexOf('jedi.isLightsaber(defenderWeapon) ||', [StringComparison]::Ordinal) -lt
        $secondary.IndexOf('getPrecuWeaponProfileRow(defenderWeapon)', [StringComparison]::Ordinal)) -Name "p14.secondary-defense.ricochet.standardized-before-profile-fallback"
Assert-Contract -Condition (
    $secondary.Contains('!ai_lib.isTurret(attackerData.id)') -and
    $secondary.Contains('combat.isRangedWeapon(weaponData.weaponType) || combat.isHeavyWeapon(weaponData.weaponType)') -and
    $secondary.Contains('getEnhancedSkillStatisticModifierUncapped(defenderData.id, "saber_block")')) -Name "p14.secondary-defense.ricochet.core3-eligibility"
Assert-Contract -Condition (
    $secondary.Contains('int saberRoll = rand(0, 100);') -and
    $secondary.Contains('int saberResult = saberBlock > 0 && saberRoll <= saberBlock ?') -and
    $secondary.Contains('HIT_RESULT_PRECU_RICOCHET : HIT_RESULT_HIT;')) -Name "p14.secondary-defense.ricochet.inclusive-saber-block-roll"
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
    $secondary.Contains('getPrecuRangedDefenseLocomotionModifier(defenderData.locomotion)') -and
    $secondary.Contains('getPrecuMeleeDefenseLocomotionModifier(defenderData.locomotion)')) -Name "p14.secondary-defense.runtime.center-and-posture"
Assert-Contract -Condition (
    $secondary.Contains('int attackRoll = rand(1, 500);') -and
    $secondary.Contains('int defendRoll = rand(1, 200);') -and
    $secondary.Contains('int result = accuracyTotal + attackRoll <= evadeTotal + defendRoll ?') -and
    $secondary.Contains('defendResult : HIT_RESULT_HIT;')) -Name "p14.secondary-defense.runtime.core3-roll-equation"
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
    $counter.Contains('setObjVar(attacker, "combat.boolCounterAttack", true);') -and
    $counter.Contains('startCombat(defender, attacker);') -and
    $counter.Contains('return queueCommand(') -and
    $counter.Contains('PRECU_COUNTERATTACK_COMMAND') -and
    $counter.Contains('COMMAND_PRIORITY_FRONT') -and
    $combatBase.Contains('"secondary.counterQueued"') -and
    $combatBase.Contains('public static final int PRECU_COUNTERATTACK_COMMAND = 1957054281;')) -Name "p14.secondary-defense.counter.basic-response-command"
Assert-Contract -Condition (
    $legacyCombatBase.Contains('queueCommand(objDefender, (1957054281), objAttacker, "", COMMAND_PRIORITY_FRONT);') -and
    $legacyCombatBase.Contains('cbtDefenderResults[intI].result = COMBAT_RESULT_COUNTER;')) -Name "p14.secondary-defense.counter.legacy-swgsource-plumbing"
Assert-Contract -Condition (
    $combatBase.Contains('case HIT_RESULT_PRECU_RICOCHET:') -and
    $combatBase.Contains('hitData[i].precuRicochet = true;') -and
    $combatBase.Contains('else if (hitData[i].precuRicochet)') -and
    $combatBase.Contains('defenderResults[i].result = COMBAT_RESULT_LIGHTSABER_BLOCK;')) -Name "p14.secondary-defense.ricochet.zero-damage-lightsaber-result"
Assert-Contract -Condition (
    $combatBase.IndexOf('else if (hitData[i].precuRicochet)', [StringComparison]::Ordinal) -gt
        $combatBase.IndexOf('else if (hitData[i].parry)', [StringComparison]::Ordinal) -and
    $combatBase.IndexOf('else if (hitData[i].precuRicochet)', [StringComparison]::Ordinal) -gt
        $combatBase.IndexOf('queueCommand(defenderData[i].id, (1345072218)', [StringComparison]::Ordinal)) -Name "p14.secondary-defense.ricochet.bypasses-nge-parry-proc-reflect"
Assert-Contract -Condition (
    $combatBase.Contains('"secondary.blockBaseBefore"') -and
    $combatBase.Contains('"secondary.blockBaseAfter"') -and
    $combatBase.Contains('"secondary.blockElementalBefore"') -and
    $combatBase.Contains('"secondary.blockElementalAfter"') -and
    $combatBase.Contains('"secondary.ngeParryBranch"') -and
    $combatBase.Contains('"secondary.reflectQueued"')) -Name "p14.secondary-defense.live.outcome-telemetry"
Assert-Contract -Condition (
    $secondary.Contains('"FALLBACK_NO_PROFILE"') -and
    $secondary.Contains('"FALLBACK_INCOMPLETE_PROFILE"') -and
    $secondary.Contains('"secondary.resultName", "FALLBACK"')) -Name "p14.secondary-defense.live.fallback-telemetry"
Assert-Contract -Condition (
    $liveFixture.Contains('equalsIgnoreCase("armSecondaryBlock")') -and
    $liveFixture.Contains('equalsIgnoreCase("armSecondaryDodge")') -and
    $liveFixture.Contains('equalsIgnoreCase("armSecondaryCounter")') -and
    $liveFixture.Contains('equalsIgnoreCase("armSecondaryRicochet")') -and
    $liveFixture.Contains('equalsIgnoreCase("armSecondaryFallback")') -and
    $liveFixture.Contains('"private_center_of_being", 1000') -and
    $liveFixture.Contains('"ricochet", "saber_block", 101') -and
    $liveFixture.Contains('LIGHTSABER_TEMPLATE') -and
    $liveFixture.Contains('FALLBACK_WEAPON_TEMPLATE')) -Name "p14.secondary-defense.live.reversible-controls"
Assert-Contract -Condition (
    $fixtureWeaponTemplate.Contains('@base object/weapon/ranged/pistol/pistol_dl44.iff') -and
    $fixtureWeaponTemplate.Contains('@class weapon_object_template 11') -and
    $fixtureWeaponTemplate.Contains('sharedTemplate = "object/weapon/ranged/pistol/shared_pistol_dl44.iff"') -and
    $fixtureWeaponTemplate.Contains('objvars = +["isLightsaber"=1]') -and
    -not $fixtureWeaponTemplate.Contains('weaponType = WT_1handLightsaber') -and
    $jediLibrary.Contains('hasObjVar(objWeapon, "isLightsaber")') -and
    $jediLibrary.Contains('getIntObjVar(objWeapon, "isLightsaber") == 1')) -Name "p14.secondary-defense.live.cross-version-ricochet-adapter"
Assert-Contract -Condition (
    $liveFixture.Contains('clearSecondaryDefenseControl(defender)') -and
    $liveFixture.Contains('applySkillStatisticModifier(defender, controlMod, -controlDelta)') -and
    $liveFixture.Contains('ORIGINAL_CENTER_OF_BEING') -and
    $liveFixture.Contains('ORIGINAL_SABER_BLOCK') -and
    $liveFixture.Contains('destroyOwnedWeapon(') -and
    -not $liveFixture.Contains('queueCommand(') -and
    $liveFixture.Contains('equipOverride(weapon, defender)') -and
    $liveFixture.Contains('COMBAT_WEAPON_SCRIPT') -and
    [string]$contract.liveFixture.commandExecutionOwner -match 'ClientCommandQueue' -and
    [string]$contract.liveFixture.weaponEquipOwner -match 'client inventory equip') -Name "p14.secondary-defense.live.ownership-and-cleanup"
Assert-Contract -Condition (
    [string]$contract.liveEvidence.clientExecutableSha256 -ceq
        "62E9056500758B0F1F7706F4ECC71441BE73E059112098AC9521BFF08457DCFC" -and
    [string]$contract.liveEvidence.publishedClientExecutableSha256 -ceq
        "17882CC8C9EB3933AABD8F7241D36EBADAF67B8667670D29F2B9499C78AA1375" -and
    [string]$contract.liveEvidence.publishedClientToolsCommit -ceq
        "305f0eb5b2b899c0f3b04706b80fb57d94cf76d8" -and
    [string]$contract.liveEvidence.publishedClientProtocolSmoke -match 'protocol 14' -and
    [string]$contract.liveEvidence.canonicalPatchSha256 -ceq
        "87EB6BE24C5A5B7A9C84EC904662ABC7BE01CBCA7C8D0C1B578578914EF292F9" -and
    [string]$contract.liveEvidence.block.secondaryResult -ceq "BLOCK" -and
    [int]$contract.liveEvidence.block.baseBefore -eq 43 -and
    [int]$contract.liveEvidence.block.baseAfter -eq 21 -and
    [string]$contract.liveEvidence.dodge.secondaryResult -ceq "DODGE" -and
    [bool]$contract.liveEvidence.dodge.defenderHamUnchanged -and
    [string]$contract.liveEvidence.counter.secondaryResult -ceq "COUNTER" -and
    [int]$contract.liveEvidence.counter.counterDispatched -eq 1) -Name "p14.secondary-defense.live.block-dodge-counter"
Assert-Contract -Condition (
    [string]$contract.liveEvidence.ricochet.secondaryProfile -ceq "LIGHTSABER" -and
    [string]$contract.liveEvidence.ricochet.secondaryResult -ceq "RICOCHET" -and
    [int]$contract.liveEvidence.ricochet.saberBlock -eq 101 -and
    [int]$contract.liveEvidence.ricochet.saberRoll -le 101 -and
    [bool]$contract.liveEvidence.ricochet.defenderHamUnchanged -and
    [int]$contract.liveEvidence.ricochet.ngeParryBranch -eq 0 -and
    [int]$contract.liveEvidence.ricochet.reflectQueued -eq 0 -and
    [string]$contract.liveEvidence.missingProfileFallback.secondaryProfile -ceq
        "FALLBACK_NO_PROFILE" -and
    [string]$contract.liveEvidence.missingProfileFallback.secondaryResult -ceq
        "FALLBACK" -and
    [int]$contract.liveEvidence.missingProfileFallback.defenderMindBefore -gt
        [int]$contract.liveEvidence.missingProfileFallback.defenderMindAfter) -Name "p14.secondary-defense.live.ricochet-and-fallback"
Assert-Contract -Condition (
    [bool]$contract.liveEvidence.cleanup.marksmanRestored -and
    [bool]$contract.liveEvidence.cleanup.headShotRestored -and
    [int]$contract.liveEvidence.cleanup.fixtureWeaponsRemaining -eq 0 -and
    [int]$contract.liveEvidence.cleanup.diagnosticEnabledAfterCleanup -eq 0 -and
    -not [bool]$contract.liveEvidence.cleanup.pvpCanAttackAfterCleanup) -Name "p14.secondary-defense.live.cleanup"

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
    @($contract.narrowBoundary.included | Where-Object { [string]$_ -match 'ricochet' }).Count -eq 1 -and
    @($contract.narrowBoundary.deferred | Where-Object { [string]$_ -match 'ricochet' }).Count -eq 0) -Name "p14.secondary-defense.boundary.ricochet-included"
Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    @($contract.buildEvidence.targets).Count -eq 6) -Name "p14.secondary-defense.isolated-build.evidence"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 secondary-defense contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Core3 block/dodge/counter/ricochet implementation passed its build, static, and live acceptance gates; additional defender weapon profiles remain deferred."
