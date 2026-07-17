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
$utils = Get-Content -LiteralPath $paths.utils -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$consume = Get-BracedBlock -Text $consumable `
    -Signature "public static boolean consumeItem(obj_id player, obj_id target, obj_id item, boolean checkPvpStatus)"
$applyStart = $consume.IndexOf(
    "for (attrib_mod attrib_mod : am)",
    [StringComparison]::Ordinal)
$decrement = $consume.LastIndexOf(
    "return decrementCharges(item, player);",
    [StringComparison]::Ordinal)

Write-Host "Publish 14.1 medicine-item consumption checks:"
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
