[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuDotAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedBlock([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$texts = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.precu-dot.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.precu-dot.source.$($property.Name).authenticated"
}

$dot = [string]$texts.dot
$healing = [string]$texts.healing
$combatBase = [string]$texts.combatBase
$combatActions = [string]$texts.combatActions
$normalApply = Get-BracedBlock $dot `
    "public static boolean applyDotEffect(obj_id target, obj_id attacker, String type, String dot_id, int attribute, int potency, int strength, int duration, boolean verbose, String handler)"
$precuApply = Get-BracedBlock $dot `
    "public static boolean applyPrecuDotEffect(obj_id target, obj_id attacker, String type, String dot_id, int attribute, int potency, int strength, int duration)"
$application = Get-BracedBlock $dot `
    "private static boolean applyDotEffectInternal(obj_id target, obj_id attacker, String type, String dot_id, int attribute, int potency, int strength, int duration, boolean verbose, String handler, boolean precuAuthoritative)"
$pulse = Get-BracedBlock $dot `
    "public static boolean applyDotDamage(obj_id target, String dot_id)"

Assert-Contract ($normalApply.Contains("applyDotEffectInternal") -and
    $normalApply.Contains("verbose, handler, false")) `
    "p14.precu-dot.dispatch.compatibility-helper-preserved"
Assert-Contract ($precuApply.Contains("applyDotEffectInternal") -and
    $precuApply.Contains("true, null, true")) `
    "p14.precu-dot.dispatch.precu-helper-authenticated"

$applicationExpertise = Get-SourceSlice $application `
    "if (!precuAuthoritative)" "int dissipation_mod;"
Assert-Contract ($application.Contains("attemptDotResist(target, type, potency, true)") -and
    $applicationExpertise.Contains('"expertise_dot_increase"')) `
    "p14.precu-dot.application.resistance-preserved-expertise-bounded"
Assert-Contract (([regex]::Matches($application,
        'dissipation_mod = getEnhancedSkillStatisticModifier\(target, "dissipation_')).Count -eq
        [int]$contract.expected.classicAbsorptionFamilies -and
    $application.Contains("duration = (int)(duration * (1.0f - (dissipation_mod / 100.0f)))")) `
    "p14.precu-dot.application.classic-dissipation-preserved"
Assert-Contract ($application.Contains("VAR_PRECU_AUTHORITATIVE, true") -and
    $application.Contains("removeScriptVar(target, VAR_DOT_ROOT + dot_id + VAR_PRECU_AUTHORITATIVE)")) `
    "p14.precu-dot.application.authority-persisted-and-reset"

Assert-Contract ($pulse.Contains("getBooleanScriptVar(target, dotScriptVar + VAR_PRECU_AUTHORITATIVE)") -and
    $pulse.Contains("absorption_mod > 50") -and $pulse.Contains("absorption_mod = 50")) `
    "p14.precu-dot.pulse.authority-loaded-and-classic-cap-preserved"
$pulseSetup = Get-SourceSlice $pulse "int absorption_mod = 0;" "switch (type)"
Assert-Contract ($pulseSetup.Contains("precuAuthoritative ? 0") -and
    $pulseSetup.Contains('"dot_vulnerability_all"') -and
    $pulseSetup.Contains("if (!precuAuthoritative)") -and
    $pulseSetup.Contains("armor.getCombatArmorSpecialProtections") -and
    $pulseSetup.Contains("armor.getCombatArmorGeneralProtection")) `
    "p14.precu-dot.pulse.general-vulnerability-and-armor-bounded"

$families = @(
    @{ Constant = "BLEEDING"; Absorption = "bleeding"; Vulnerability = "bleed" },
    @{ Constant = "POISON"; Absorption = "poison"; Vulnerability = "poison" },
    @{ Constant = "DISEASE"; Absorption = "disease"; Vulnerability = "disease" },
    @{ Constant = "FIRE"; Absorption = "fire"; Vulnerability = "fire" },
    @{ Constant = "ACID"; Absorption = "acid"; Vulnerability = "acid" },
    @{ Constant = "ENERGY"; Absorption = "energy"; Vulnerability = "energy" }
)
foreach ($family in $families)
{
    $case = Get-SourceSlice $pulse "case DOT_$($family.Constant):" "break;"
    Assert-Contract ($case.Contains("absorption_$($family.Absorption)") -and
        $case.Contains("if (!precuAuthoritative)") -and
        $case.Contains("dot_vulnerability_$($family.Vulnerability)") -and
        $case.Contains("absorption_mod /= MOD_DIVISOR") -and
        $case.Contains('"expertise_dot_absorption_all"') -and
        $case.Contains("DOT_ARMOR_MITIGATION_PERCENT")) `
        "p14.precu-dot.pulse.$($family.Absorption)-classic-absorption-nge-layers-bounded"
}

$genericDamage = Get-SourceSlice $pulse `
    "if (!precuAuthoritative && vulnerability_mod > 0)" "int dotAttribute = getDotAttribute"
Assert-Contract ($genericDamage.Contains("if (!precuAuthoritative)") -and
    $genericDamage.Contains('"combat_multiply_damage_taken"') -and
    $genericDamage.Contains('"combat_divide_damage_taken"')) `
    "p14.precu-dot.pulse.generic-damage-modifiers-bounded"
Assert-Contract ($pulse.Contains("if (!precuAuthoritative && attemptDotResist(target, type, 100, false))")) `
    "p14.precu-dot.pulse.repeat-resistance-bounded"

$wrappedDamage = Get-BracedBlock $combatBase `
    "public void doWrappedDamage(obj_id attacker, obj_id defender, weapon_data weaponData, hit_result hitData, combat_data actionData, int overloadDamage)"
$compatibilityDot = $wrappedDamage.IndexOf("dot.applyDotEffect(", [StringComparison]::Ordinal)
$precuDot = $wrappedDamage.IndexOf("dot.applyPrecuDotEffect(", [StringComparison]::Ordinal)
Assert-Contract ($wrappedDamage.Contains("if (!precuAuthoritativeAttack)") -and
    $compatibilityDot -ge 0 -and $precuDot -gt $compatibilityDot) `
    "p14.precu-dot.callers.combat-era-branches-preserved"

$medicine = Get-BracedBlock $healing `
    "public static boolean performDotApplication(obj_id medic, obj_id target, String heal_type, obj_id med_obj)"
Assert-Contract ($medicine.Contains("dot.applyPrecuDotEffect(") -and
    -not $medicine.Contains("dot.applyDotEffect(")) `
    "p14.precu-dot.callers.combat-medic-authenticated"

foreach ($handlerName in @("creatureAreaDiseaseSuccess", "creatureAreaPoisonSuccess"))
{
    $handler = Get-BracedBlock $combatActions "public int $handlerName(obj_id self, dictionary params)"
    Assert-Contract ($handler.Contains('hasObjVar(self, "precu.combatProfile")') -and
        $handler.Contains("dot.applyPrecuDotEffect(") -and
        $handler.Contains("dot.applyDotEffect(")) `
        "p14.precu-dot.callers.$handlerName-profile-gated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.precu-dot.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.precu-dot.direct-source-pin"
    $compiledHashesValid = $true
    foreach ($property in $contract.buildEvidence.compiledClassSha256.PSObject.Properties)
    {
        if ([string]$property.Value -notmatch '^[a-f0-9]{64}$') { $compiledHashesValid = $false }
    }
    Assert-Contract ($compiledHashesValid -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.precu-dot.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.precu-dot.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.precu-dot.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU DOT authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU DOT authority contract passed."
