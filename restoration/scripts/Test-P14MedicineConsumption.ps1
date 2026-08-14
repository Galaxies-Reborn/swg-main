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
    Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.p14MedicineConsumption)
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
        throw "Required materialized medicine source is missing: $path"
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
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0)
    {
        return ""
    }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{')
        {
            ++$depth
        }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    return ""
}

$consumable = Get-Content -LiteralPath $paths.consumable -Raw
$healing = Get-Content -LiteralPath $paths.healing -Raw
$classicStimpack = Get-Content -LiteralPath $paths.classicStimpack -Raw
$craftedStimpack = Get-Content -LiteralPath $paths.craftedStimpack -Raw
$otherStimpack = Get-Content -LiteralPath $paths.otherStimpack -Raw
$utils = Get-Content -LiteralPath $paths.utils -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$consumeEntry = Get-BracedBlock -Text $consumable `
    -Signature "public static boolean consumeItem(obj_id player, obj_id target, obj_id item, boolean checkPvpStatus)"
$consume = $consumeEntry
if ($consumeEntry.Contains("MAX_AFFECT_DISTANCE") -and
    $consumable.Contains("float maximumNormalMedicineRange)"))
{
    $consume = Get-BracedBlock -Text $consumable `
        -Signature "public static boolean consumeItem(`r`n        obj_id player,`r`n        obj_id target,`r`n        obj_id item,`r`n        boolean checkPvpStatus,`r`n        float maximumNormalMedicineRange)"
    if ([string]::IsNullOrEmpty($consume))
    {
        $normalizedConsumable = $consumable.Replace("`r`n", "`n")
        $consume = Get-BracedBlock -Text $normalizedConsumable `
            -Signature "public static boolean consumeItem(`n        obj_id player,`n        obj_id target,`n        obj_id item,`n        boolean checkPvpStatus,`n        float maximumNormalMedicineRange)"
    }
}
$applyStart = $consume.IndexOf(
    "for (attrib_mod attrib_mod : am)",
    [StringComparison]::Ordinal)
$decrement = $consume.LastIndexOf(
    "return decrementCharges(item, player);",
    [StringComparison]::Ordinal)
$classicHealDamageItem = Get-BracedBlock -Text $healing `
    -Signature "public static boolean useHealDamageItem(obj_id user, obj_id target, obj_id item, int attrib)"

Write-Host "Publish 14.1 medicine-item consumption checks:"
$dsrcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "dsrc"
})
Assert-Contract -Condition (
    $dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq
        [string]$contract.buildEvidence.directSourceCommit) `
    -Name "p14.medicine.direct-source-pin"
foreach ($property in
    $contract.buildEvidence.currentSourceSha256.psobject.Properties)
{
    $actualHash =
        (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $paths[[string]$property.Name]).Hash.ToLowerInvariant()
    Assert-Contract -Condition (
        [string]$actualHash -ceq [string]$property.Value) `
        -Name "p14.medicine.source.$([string]$property.Name).authenticated"
}
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.scope -ceq
        "patient-side wound-pack treatment after battle-fatigue scaling" -and
    [int]$contract.semanticReference.patientShock -eq 1000 -and
    [double]$contract.semanticReference.minimumBattleFatigueMultiplier -eq
        0.25) `
    -Name "p14.medicine.core3.pin-and-patient-scope"
Assert-Contract -Condition (
    $consume.Contains("obj_id owner = utils.getContainingPlayer(item);") -and
    $consume.Contains("if (player == owner)") -and
    $consume.Contains("return false;")) `
    -Name "p14.medicine.runtime.inventory-ownership-retained"
Assert-Contract -Condition (
    $consume.Contains(
        "int skillMod = getSkillStatMod(player, skillReq[i]);") -and
    $consume.Contains("if (skillMod < skillMin[i])") -and
    $consume.Contains(
        "healing.applyShockWoundModifier(multiplier, target)") -and
    $consume.Contains(
        "healing.modifyMedicineAttributes(am, final_multiplier)")) `
    -Name "p14.medicine.runtime.skill-and-patient-fatigue-gates"
Assert-Contract -Condition (
    $applyStart -ge 0 -and
    $consume.IndexOf(
        "utils.addAttribMod(target, attrib_mod);",
        $applyStart,
        [StringComparison]::Ordinal) -gt $applyStart -and
    -not $consume.Contains(
        "if (attrib_mod.getAttribute() == HEALTH)") -and
    -not $consume.Contains("LOOKS LIKE HEALTH TO ME")) `
    -Name "p14.medicine.runtime.all-validated-attributes-applied"

$medicineObserver = $contract.productionContract.campHealingObserver
$medicineObserverPattern =
    '(?s)healing\.healDamage\s*\(\s*player\s*,\s*target\s*,\s*attrib_mod\.getAttribute\(\)\s*,\s*attrib_mod\.getValue\(\)\s*,\s*notifyCampHealing\s*\)'
Assert-Contract -Condition (
    [string]$medicineObserver.scope -ceq
        "ordinary non-revive medicine" -and
    [bool]$medicineObserver.firstPositiveInstantPoolModifierNotifies -and
    -not [bool]$medicineObserver.subsequentInstantPoolModifiersNotify -and
    [bool]$medicineObserver.notificationUsesMedicineUserAsHealer -and
    [bool]$medicineObserver.clampedAppliedDeltaZeroStillCountsAsAuthoredEvent -and
    -not [bool]$medicineObserver.woundHealingNotifies -and
    -not [bool]$medicineObserver.timedBuffEnhancementAndNonPoolModifiersNotify -and
    $consume.Contains("boolean medicine = healing.isMedicine(item);") -and
    $consume.Contains("boolean revivePack = healing.isRevivePack(item);") -and
    $consume.Contains("boolean notifiedMedicinePool = false;") -and
    $consume.Contains("attrib_mod.getValue() > 0") -and
    $consume.Contains("attrib_mod.getDuration() <= 0.0f") -and
    $consume.Contains(
        "(int)attrib_mod.getDecay() == (int)MOD_POOL") -and
    [regex]::IsMatch(
        $consume,
        '(?s)boolean notifyCampHealing\s*=\s*revivePack\s*\|\|\s*\(medicine\s*&&\s*!notifiedMedicinePool\)') -and
    [regex]::Matches($consume, $medicineObserverPattern).Count -eq 1 -and
    [regex]::IsMatch(
        $consume,
        '(?s)healing\.healDamage\s*\([^;]+notifyCampHealing\s*\);\s*if\s*\(medicine\s*&&\s*!revivePack\)\s*\{\s*notifiedMedicinePool\s*=\s*true;') -and
    [regex]::IsMatch(
        $consume,
        '(?s)else\s*\{\s*utils\.addAttribMod\(target, attrib_mod\);') -and
    -not [regex]::IsMatch(
        $consume,
        '(?s)if\s*\([^)]*delta\s*>\s*0[^)]*\)\s*\{\s*notifiedMedicinePool\s*=\s*true;')) `
    -Name "p14.medicine.runtime.first-authored-pool-observer-only"

$classicStimObserverPattern =
    '(?s)healDamage\s*\(\s*user\s*,\s*target\s*,\s*attrib\s*,\s*toHeal\s*,\s*true\s*\)'
Assert-Contract -Condition (
    [int]$medicineObserver.classicUseHealDamageItemNotificationsPerSuccessfulUse -eq 1 -and
    [int]$medicineObserver.classicUseHealDamageItemBattleFatigueCreditsPerPositiveHeal -eq 1 -and
    (@($medicineObserver.classicProducerScripts) -join ",") -ceq
        "item.medicine.stimpack,item.medicine.stimpack_crafted,item.medicine.stimpack_other" -and
    -not [string]::IsNullOrEmpty($classicHealDamageItem) -and
    [regex]::Matches(
        $classicHealDamageItem,
        $classicStimObserverPattern).Count -eq 1 -and
    [regex]::Matches(
        $classicHealDamageItem,
        'pvp\.bfCreditForHealing\s*\(\s*user\s*,\s*delta\s*\)').Count -eq 1 -and
    [regex]::Matches(
        $classicHealDamageItem,
        '\bhealDamage\s*\(').Count -eq 1 -and
    $classicStimpack.Contains(
        "healing.useHealDamageItem(player, self, attrib)") -and
    $classicStimpack.Contains(
        "healing.useHealDamageItem(player, self)") -and
    $craftedStimpack.Contains(
        "healing.useHealDamageItem(player, self, attrib)") -and
    $craftedStimpack.Contains(
        "healing.useHealDamageItem(player, self)") -and
    $otherStimpack.Contains(
        "healing.useHealDamageItem(player, target, self)")) `
    -Name "p14.medicine.runtime.classic-stim-producer-observer-and-bf"
Assert-Contract -Condition (
    $decrement -gt $applyStart -and
    $consumable.Contains("else if (charges > 1)") -and
    $consumable.Contains("incrementCount(item, -1);")) `
    -Name "p14.medicine.runtime.apply-before-single-charge-decrement"
Assert-Contract -Condition (
    $utils.Contains(
        "litmus = healWound(target, attrib, amt) != ATTRIB_ERROR;") -and
    $healing.Contains(
        "tmp = utils.createHealWoundAttribMod(")) `
    -Name "p14.medicine.runtime.persistent-wound-seam"

Assert-Contract -Condition (
    $fixture.Contains("HEALER_OID = 39008597L") -and
    $fixture.Contains("HEALER_STATION_ID = 1001") -and
    $fixture.Contains('"consumeHealth"') -and
    $fixture.Contains('"consumeStrength"') -and
    $fixture.Contains('"consumeConstitution"') -and
    $fixture.Contains('"consumeAction"') -and
    $fixture.Contains('"consumeQuickness"') -and
    $fixture.Contains('"consumeStamina"')) `
    -Name "p14.medicine.live.identity-and-actions"
Assert-Contract -Condition (
    $fixture.Contains(
        'createObject("object/mobile/human_male.iff", targetLocation)') -and
    $fixture.Contains(
        '"object/tangible/medicine/medpack_wound_health.iff"') -and
    $fixture.Contains(
        '"object/tangible/medicine/medpack_wound_strength.iff"') -and
    $fixture.Contains(
        '"object/tangible/medicine/medpack_wound_constitution.iff"') -and
    $fixture.Contains(
        '"object/tangible/medicine/medpack_wound_action.iff"') -and
    $fixture.Contains(
        '"object/tangible/medicine/medpack_wound_quickness.iff"') -and
    $fixture.Contains(
        '"object/tangible/medicine/medpack_wound_stamina.iff"') -and
    $fixture.Contains(
        "obj_id medicine = createObject(template, inventory,") -and
    $fixture.Contains("setCount(medicine, 2);")) `
    -Name "p14.medicine.live.real-patient-items-and-charges"
Assert-Contract -Condition (
    $fixture.Contains("private static final int[] CONSUME_ATTRIBUTES") -and
    $fixture.Contains("for (int attribute : CONSUME_ATTRIBUTES)") -and
    $fixture.Contains("setMaxAttrib(target, attribute, TEST_MAX)") -and
    $fixture.Contains("setAttrib(target, attribute, TEST_MAX)")) `
    -Name "p14.medicine.live.six-attribute-patient-configuration"
Assert-Contract -Condition (
    $fixture.Contains(
        "consumable.consumeItem(healer, target, medicine, false)") -and
    $fixture.Contains("int beforeWound = getAttribWound(") -and
    $fixture.Contains("int afterWound = getAttribWound(") -and
    $fixture.Contains("int charges = isIdValid(medicine)")) `
    -Name "p14.medicine.live.production-consume-observation"
Assert-Contract -Condition (
    $fixture.Contains("destroyTrackedItem(healer);") -and
    $fixture.Contains("destroyTrackedTarget(healer);") -and
    $fixture.Contains("removeObjVar(healer, ROOT);") -and
    -not $fixture.Contains("setAttrib(healer") -and
    -not $fixture.Contains("setShockWound(healer")) `
    -Name "p14.medicine.live.disposable-target-exact-cleanup"

if ($Expectation -ceq "Ready")
{
    $before = $contract.liveEvidence.beforeRepair
    $after = $contract.liveEvidence.afterRepair
    $matrix = $contract.liveEvidence.sixAttributeMatrix
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed") `
        -Name "p14.medicine.status.ready"
    Assert-Contract -Condition (
        [int]$before.health.healed -gt 0 -and
        [int]$before.action.healed -eq 0 -and
        [int]$before.health.remainingCharges -eq 1 -and
        [int]$before.action.remainingCharges -eq 1) `
        -Name "p14.medicine.live.before-repair-defect-isolated"
    Assert-Contract -Condition (
        [string]$contract.liveEvidence.result -ceq "passed" -and
        [int]$after.health.healed -gt 0 -and
        [int]$after.action.healed -gt 0 -and
        [int]$after.health.remainingCharges -eq 1 -and
        [int]$after.action.remainingCharges -eq 1 -and
        [bool]$contract.liveEvidence.cleanup.fixtureRootAbsent -and
        [bool]$contract.liveEvidence.cleanup.healerHamMutated -eq $false) `
        -Name "p14.medicine.live.health-action-charges-and-cleanup"
    $matrixAttributes = @(
        "health",
        "strength",
        "constitution",
        "action",
        "quickness",
        "stamina")
    $matrixPassed = [string]$matrix.result -ceq "passed"
    foreach ($attributeName in $matrixAttributes)
    {
        $entry = $matrix.attributes.$attributeName
        $matrixPassed =
            $matrixPassed -and
            $null -ne $entry -and
            [int]$entry.beforeWound -eq 400 -and
            [int]$entry.afterWound -lt 400 -and
            [int]$entry.healed -gt 0 -and
            [int]$entry.remainingCharges -eq 1
    }
    Assert-Contract -Condition $matrixPassed `
        -Name "p14.medicine.live.six-attribute-real-item-matrix"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 medicine consumption contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 medicine-item consumption contract passed."
