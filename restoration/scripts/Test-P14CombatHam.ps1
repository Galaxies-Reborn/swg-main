[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14CombatHam)) -Raw | ConvertFrom-Json
$gate = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.headShot1Gate)) -Raw | ConvertFrom-Json
$marksmanMatrix = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14MarksmanTier1Matrix)) -Raw | ConvertFrom-Json
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
        throw "Required materialized three-pool combat source is missing: $path"
    }
}

$text = @{}
foreach ($name in $paths.Keys)
{
    if ($name -notin @("weaponCosts", "combatOverrides"))
    {
        $text[$name] = Get-Content -LiteralPath $paths[$name] -Raw
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

Write-Host "Publish 14.1 three-pool combat runtime checks:"

Assert-Contract `
    -Condition ([string]$contract.status -ceq "ready") `
    -Name "p14.combat-ham.contract.generic-runtime-ready"
Assert-Contract `
    -Condition (([string]$gate.status -ceq "ready") -and [string]$gate.acceptanceContract -ceq "contracts/p14-headshot1.json") `
    -Name "p14.combat-ham.first-command-gate-ready"

Assert-Contract `
    -Condition ($text.scriptAttributes.Contains('JF("_drainCombatAttributes", "(JIII)Z", drainCombatAttributes)') -and $text.baseClass.Contains("private static native boolean _drainCombatAttributes(long target, int health, int action, int mind);")) `
    -Name "p14.combat-ham.native.atomic-drain-binding"
Assert-Contract `
    -Condition ($text.scriptCombat.Contains('JF("__doDamageNoWeaponToPool", "(JJIII)Z", doDamageNoWeaponToPool)') -and $text.baseClass.Contains("private static native boolean __doDamageNoWeaponToPool(long attacker, long defender, int damage, int hitLocation, int pool);")) `
    -Name "p14.combat-ham.native.explicit-pool-damage-binding"

$drainBlock = Get-BracedBlock -Text $text.creatureCpp -Signature "bool CreatureObject::drainCombatAttributes("
$firstPreflight = $drainBlock.IndexOf("for (int i = 0; i < 3; ++i)", [StringComparison]::Ordinal)
$secondMutation = if ($firstPreflight -ge 0) { $drainBlock.IndexOf("for (int i = 0; i < 3; ++i)", $firstPreflight + 1, [StringComparison]::Ordinal) } else { -1 }
$alterAt = $drainBlock.IndexOf("alterAttribute(Attributes::POOLS[i], -costs[i]", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($drainBlock.Length -gt 0 -and $drainBlock.Contains("costs[i] < 0") -and $drainBlock.Contains("getAttribute(Attributes::POOLS[i]) <= costs[i]") -and $firstPreflight -ge 0 -and $secondMutation -gt $firstPreflight -and $alterAt -gt $secondMutation) `
    -Name "p14.combat-ham.cost.atomic-preflight-before-mutation"
Assert-Contract `
    -Condition ($drainBlock.Contains("NetworkId::cms_invalid, true") -and -not $drainBlock.Contains("testIncapacitation")) `
    -Name "p14.combat-ham.cost.drain-cannot-trigger-partial-incapacitation"

$incapBlock = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::testIncapacitation("
Assert-Contract `
    -Condition ($incapBlock.Contains("health <= 0 || action <= 0 || mind <= 0") -and $incapBlock.Contains("health > 0 && action > 0 && mind > 0") -and $incapBlock.Contains("setIncapacitated(true, attackerId)") -and $incapBlock.Contains("setIncapacitated(false, attackerId)")) `
    -Name "p14.combat-ham.incapacitation.any-empty-and-all-positive-recovery"

$costAdjustment = Get-BracedBlock -Text $text.combatLibrary -Signature "private static int calculatePrecuHamCost("
$costVector = Get-BracedBlock -Text $text.combatLibrary -Signature "private static int[] getPrecuHamActionCost("
Assert-Contract `
    -Condition ($costAdjustment.Contains("governingValue - 300.0f") -and $costAdjustment.Contains("/ 1200.0f") -and $costAdjustment.Contains("Math.max(0, (int)cost)")) `
    -Name "p14.combat-ham.cost.core3-adjustment-formula"
Assert-Contract `
    -Condition (-not $text.combatLibrary.Contains("PRECU_NEUTRAL_GOVERNING_ATTRIBUTE") -and $costVector.Contains("getAttrib(self, STRENGTH)") -and $costVector.Contains("getAttrib(self, QUICKNESS)") -and $costVector.Contains("getAttrib(self, FOCUS)") -and $costVector.Contains("healthCost") -and $costVector.Contains("actionCost") -and $costVector.Contains("mindCost") -and [bool]$contract.governingAttributeSource.dynamicNineAttributeValuesReady) `
    -Name "p14.combat-ham.cost.authoritative-nine-attribute-governors"

$legacyDrain = Get-BracedBlock -Text $text.combatLibrary -Signature "public static boolean drainCombatActionAttributes(obj_id self, int[] actionCost) throws"
$optInDrain = Get-BracedBlock -Text $text.combatLibrary -Signature "public static boolean drainCombatActionAttributes(obj_id self, int[] actionCost, boolean usePrecuHam)"
$optInCheck = Get-BracedBlock -Text $text.combatLibrary -Signature "public static boolean canDrainCombatActionAttributes(obj_id self, int[] actionCost, boolean usePrecuHam)"
Assert-Contract `
    -Condition ($legacyDrain.Contains("drainAttributes(self, actionCost[1], actionCost[2])") -and -not $legacyDrain.Contains("drainCombatAttributes")) `
    -Name "p14.combat-ham.compatibility.legacy-drain-preserved"
Assert-Contract `
    -Condition ($optInDrain.Contains("if (!usePrecuHam)") -and $optInDrain.Contains("drainCombatAttributes(self, actionCost[0], actionCost[1], actionCost[2])") -and $optInCheck.Contains("getAttrib(self, pools[i]) <= actionCost[i]")) `
    -Name "p14.combat-ham.compatibility.explicit-opt-in-drain-and-check"
Assert-Contract `
    -Condition ($text.combatBase.Contains("actionData.precuHamCostModel > 0") -and $text.combatBase.Contains("if (actionData.precuTargetPool >= 0)") -and $text.combatBase.Contains("doDamageToPool(attacker, defender, hitData, actionData.precuTargetPool)") -and $text.combatBase.Contains("doDamage(attacker, defender, hitData)")) `
    -Name "p14.combat-ham.compatibility.combat-path-opt-in-with-legacy-fallback"

Assert-Contract `
    -Condition ($text.combatEngineHeader.Contains("Attributes::Enumerator targetPool") -and $text.combatEngineCpp.Contains("targetPool != Attributes::Health") -and $text.combatEngineCpp.Contains("attribMod.attrib = targetPool")) `
    -Name "p14.combat-ham.damage.explicit-primary-pool-routing"
Assert-Contract `
    -Condition ($text.combatEngineCpp.Contains("return onSuccessfulAttack(attacker, defender, damageAmount, hitLocation, Attributes::Health);") -and $text.combatEngineCpp.Contains("computeCreatureDamage(hitLocation, damageDone, Attributes::Health, damageList);")) `
    -Name "p14.combat-ham.damage.legacy-health-default"

$weaponRows = @(Import-Csv -LiteralPath $paths.weaponCosts -Delimiter "`t")
$weapon = @($weaponRows | Where-Object { $_.templateName -ceq [string]$contract.initialWeaponFixture.template })
Assert-Contract `
    -Condition ($weapon.Count -eq 1 -and [int]$weapon[0].healthCost -eq 10 -and [int]$weapon[0].actionCost -eq 15 -and [int]$weapon[0].mindCost -eq 10) `
    -Name "p14.combat-ham.data.cdef-costs-10-15-10"

$overrideRows = @(Import-Csv -LiteralPath $paths.combatOverrides -Delimiter "`t")
$productionRows = @($overrideRows | Where-Object { $_.actionName -notin @("s", "__precu_runtime_probe") })
$expectedProductionCommands = @(
    [string]$gate.feature
    @($marksmanMatrix.commands | ForEach-Object { [string]$_.name })
)
$actualProductionCommands = @($productionRows | ForEach-Object { [string]$_.actionName })
Assert-Contract `
    -Condition ($text.combatEngineScript.Contains("datatables/combat/precu_combat_overrides.iff") -and [regex]::IsMatch($text.combatEngineScript, "public int\s+precuTargetPool\s+= -1;") -and $productionRows.Count -eq $expectedProductionCommands.Count -and @($expectedProductionCommands | Where-Object { $actualProductionCommands -cnotcontains $_ }).Count -eq 0) `
    -Name "p14.combat-ham.data.separate-override-table-authenticated-production-commands"
Assert-Contract `
    -Condition ((Get-Content -LiteralPath $paths.combatOverrides -Raw).Contains([string]$gate.feature)) `
    -Name "p14.combat-ham.data.ready-command-activated"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 three-pool combat runtime contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 three-pool combat runtime contract passed."
