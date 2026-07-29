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
        Join-Path $restorationRoot ([string]$manifest.contracts.p14BattleFatigue)
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
        throw "Required materialized battle-fatigue source is missing: $path"
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

function Get-ModeledBattleFatigueMultiplier
{
    param([Parameter(Mandatory = $true)][int]$Shock)

    $ratio = (1250.0 - $Shock) / 1000.0
    if ($ratio -gt 1.0)
    {
        return 1.0
    }
    if ($ratio -lt 0.25)
    {
        return 0.25
    }
    return $ratio
}

$healing = Get-Content -LiteralPath $paths.healing -Raw
$consumable = Get-Content -LiteralPath $paths.consumable -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$shockModifier = Get-BracedBlock -Text $healing `
    -Signature "public static float applyShockWoundModifier("
$modifyMedicine = Get-BracedBlock -Text $healing `
    -Signature "public static attrib_mod[] modifyMedicineAttributes("
$shockCall = $consumable.IndexOf(
    "healing.applyShockWoundModifier(multiplier, target)",
    [StringComparison]::Ordinal)
$medicineCall = $consumable.IndexOf(
    "healing.modifyMedicineAttributes(am, final_multiplier)",
    [StringComparison]::Ordinal)

Write-Host "Publish 14.1 battle-fatigue medicine checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.scope -ceq
        "patient-side medical treatment power" -and
    -not [bool]$contract.integrationContract.combatAccuracyModifier) `
    -Name "p14.battle-fatigue.core3.pin-and-medical-scope"
Assert-Contract -Condition (
    $shockModifier.Contains("float shock = getShockWound(player);") -and
    $shockModifier.Contains("(1250.0f - shock) / 1000.0f") -and
    $shockModifier.Contains("shock_mult > 1.0f") -and
    $shockModifier.Contains("shock_mult < 0.25f")) `
    -Name "p14.battle-fatigue.runtime.exact-bounded-equation"
Assert-Contract -Condition (
    $shockCall -ge 0 -and
    $medicineCall -gt $shockCall -and
    $consumable.Contains("float multiplier = healing.getHealingMultiplier(player, item);") -and
    $modifyMedicine.Contains("attrib_mod.getAttack() == AM_HEAL_WOUND") -and
    $modifyMedicine.Contains("attrib_mod.getDecay() == MOD_POOL")) `
    -Name "p14.battle-fatigue.runtime.patient-before-medicine-modification"

foreach ($boundary in @($contract.semanticReference.boundaries))
{
    $actual = Get-ModeledBattleFatigueMultiplier -Shock ([int]$boundary.shock)
    $expected = [double]$boundary.multiplier
    $scaled = [int][Math]::Truncate(100.0 * $actual)
    Assert-Contract -Condition (
        [Math]::Abs($actual - $expected) -lt 0.000001 -and
        $scaled -eq [int]$boundary.scaledMedicine100) `
        -Name "p14.battle-fatigue.boundary.shock-$([int]$boundary.shock)"
}

Assert-Contract -Condition (
    $fixture.Contains("PATIENT_OID = 39008597L") -and
    $fixture.Contains("PATIENT_STATION_ID = 1001") -and
    $fixture.Contains('equalsIgnoreCase("arm250")') -and
    $fixture.Contains('equalsIgnoreCase("arm251")') -and
    $fixture.Contains('equalsIgnoreCase("arm500")') -and
    $fixture.Contains('equalsIgnoreCase("arm1000")')) `
    -Name "p14.battle-fatigue.live.identity-and-boundary-actions"
Assert-Contract -Condition (
    $fixture.Contains("setShockWound(patient, shock)") -and
    $fixture.Contains(
        "healing.applyShockWoundModifier(1.0f, patient)") -and
    -not $fixture.Contains("consumeItem(") -and
    -not $fixture.Contains("modifyMedicineAttributes(")) `
    -Name "p14.battle-fatigue.live.production-equation-without-fabricated-heal"
Assert-Contract -Condition (
    $fixture.Contains("ORIGINAL_SHOCK") -and
    $fixture.Contains("setShockWound(patient, originalShock)") -and
    $fixture.Contains("removeObjVar(patient, ROOT)")) `
    -Name "p14.battle-fatigue.live.exact-reversible-shock-control"

if ($Expectation -ceq "Ready")
{
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed") `
        -Name "p14.battle-fatigue.status.ready"
    Assert-Contract -Condition (
        [string]$contract.liveEvidence.result -ceq "passed" -and
        @($contract.liveEvidence.observations).Count -eq 4 -and
        [bool]$contract.liveEvidence.cleanup.restored -and
        [bool]$contract.liveEvidence.cleanup.fixtureRootAbsent) `
        -Name "p14.battle-fatigue.live.boundaries-and-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 battle-fatigue contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 battle-fatigue medical scaling contract passed."
