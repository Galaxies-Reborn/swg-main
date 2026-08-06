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
$buffHandler = [string]$texts.buffHandler
$normalApply = Get-BracedBlock $dot `
    "public static boolean applyDotEffect(obj_id target, obj_id attacker, String type, String dot_id, int attribute, int potency, int strength, int duration, boolean verbose, String handler)"
$precuApply = Get-BracedBlock $dot `
    "public static boolean applyPrecuDotEffect(obj_id target, obj_id attacker, String type, String dot_id, int attribute, int potency, int strength, int duration)"
$application = Get-BracedBlock $dot `
    "private static boolean applyDotEffectInternal(obj_id target, obj_id attacker, String type, String dot_id, int attribute, int potency, int strength, int duration, boolean verbose, String handler)"
$pulse = Get-BracedBlock $dot `
    "public static boolean applyDotDamage(obj_id target, String dot_id)"
$applicationResistance = Get-BracedBlock $dot `
    "public static boolean attemptDotResist(obj_id target, String type, int potency, boolean showResistFlytext)"
$laterDotImmunity = Get-BracedBlock $dot `
    "public static boolean checkForDotImmunity(obj_id target, String type)"

Assert-Contract ($normalApply.Contains("applyDotEffectInternal") -and
    $normalApply.Contains("verbose, handler)") -and
    -not $normalApply.Contains("false")) `
    "p14.precu-dot.dispatch.retained-helper-uses-precu-resolution"
Assert-Contract ($precuApply.Contains("applyDotEffectInternal") -and
    $precuApply.Contains("true, null")) `
    "p14.precu-dot.dispatch.precu-helper-authenticated"

Assert-Contract ($application.Contains("attemptDotResist(target, type, potency, true)") -and
    -not $application.Contains("precuAuthoritative") -and
    -not $application.Contains('"expertise_')) `
    "p14.precu-dot.application.resistance-preserved-nge-expertise-retired"
Assert-Contract (([regex]::Matches($application,
        'dissipation_mod = getEnhancedSkillStatisticModifier\(target, "dissipation_')).Count -eq
        [int]$contract.expected.classicAbsorptionFamilies -and
    $application.Contains("duration = (int)(duration * (1.0f - (dissipation_mod / 100.0f)))")) `
    "p14.precu-dot.application.classic-dissipation-preserved"
Assert-Contract (-not $dot.Contains("VAR_PRECU_AUTHORITATIVE") -and
    -not $application.Contains("precuAuthoritative")) `
    "p14.precu-dot.application.no-divergent-era-marker"
Assert-Contract ($applicationResistance.Contains('"resistance_bleeding"') -and
    $applicationResistance.Contains('"resistance_poison"') -and
    $applicationResistance.Contains('"resistance_disease"') -and
    $applicationResistance.Contains('"resistance_fire"') -and
    -not $applicationResistance.Contains('"dot_resist_')) `
    "p14.precu-dot.application.classic-specific-resistance-preserved"
$playerImmunityGuard = $laterDotImmunity.IndexOf("if (isPlayer(target))", [StringComparison]::Ordinal)
$laterDotModifierRead = $laterDotImmunity.IndexOf('"dot_resist_"', [StringComparison]::Ordinal)
Assert-Contract ($playerImmunityGuard -ge 0 -and
    $laterDotImmunity.IndexOf("return false;", $playerImmunityGuard, [StringComparison]::Ordinal) -gt
        $playerImmunityGuard -and
    $laterDotModifierRead -gt $playerImmunityGuard) `
    "p14.precu-dot.application.player-later-immunity-consumer-retired"

$dotImmunityPredicate = Get-BracedBlock $buffHandler `
    "public boolean isRetiredNgeDotImmunityModifier(String modifierName)"
$buffSkillPredicate = Get-BracedBlock $buffHandler `
    "public boolean isRetiredNgeBuffSkillModifier(String modifierName)"
$skillWriter = Get-BracedBlock $buffHandler `
    "public int skillAddBuffHandler(obj_id self, String effectName, String subtype, float duration, float value, String buffName, obj_id caster)"
Assert-Contract ($dotImmunityPredicate.Contains('modifierName.equals("damage_immune")') -and
    $dotImmunityPredicate.Contains('modifierName.startsWith("dot_resist_")') -and
    $buffSkillPredicate.Contains("isRetiredNgeDotImmunityModifier(modifierName)") -and
    $skillWriter.Contains("isRetiredNgeBuffSkillModifier(subtype)")) `
    "p14.precu-dot.buff.player-later-immunity-writers-retired"

$immunityHandler = Get-BracedBlock $buffHandler `
    "public int immunityAddBuffHandler(obj_id self, String effectName, String subtype, float duration, float value, String buffName, obj_id caster)"
$universalPlayerGuard = $immunityHandler.IndexOf('isPlayer(self) && subtype.equals("dot_immunity") && wholeValue == IMMUNITY_TO_ALL_DOTS', [StringComparison]::Ordinal)
$universalDotPurge = $immunityHandler.IndexOf('buff.performBuffDotImmunity(self, "all")', [StringComparison]::Ordinal)
Assert-Contract ($universalPlayerGuard -ge 0 -and
    $universalDotPurge -gt $universalPlayerGuard -and
    ([regex]::Matches($immunityHandler, [regex]::Escape("buff.performBuffDotImmunity(self,"))).Count -eq
        [int]$contract.expected.retainedNpcAndSpecificDotImmunityHandlers) `
    "p14.precu-dot.buff.player-universal-purge-retired-specific-and-npc-preserved"

$damageImmuneHandler = Get-BracedBlock $buffHandler `
    "public int damageImmuneAddBuffHandler(obj_id self, String effectName, String subtype, float duration, float value, String buffName, obj_id caster)"
$damageImmunePlayerGuard = $damageImmuneHandler.IndexOf("if (isPlayer(self))", [StringComparison]::Ordinal)
$damageImmunePurge = $damageImmuneHandler.IndexOf('buff.performBuffDotImmunity(self, "all")', [StringComparison]::Ordinal)
Assert-Contract ($damageImmunePlayerGuard -ge 0 -and
    $damageImmuneHandler.Contains('removeAttribOrSkillModModifier(self, "damageImmuneDotResistAll")') -and
    $damageImmuneHandler.Contains('removeAttribOrSkillModModifier(self, "damageImmuneDamageImmune")') -and
    $damageImmunePurge -gt $damageImmunePlayerGuard) `
    "p14.precu-dot.buff.player-full-damage-immunity-ingress-retired"

Assert-Contract ($pulse.Contains("absorption_mod > 50") -and
    $pulse.Contains("absorption_mod = 50") -and
    -not $pulse.Contains("precuAuthoritative") -and
    -not $pulse.Contains('"dot_vulnerability_') -and
    -not $pulse.Contains('"expertise_') -and
    -not $pulse.Contains("DOT_ARMOR_MITIGATION_PERCENT") -and
    -not $pulse.Contains('"combat_multiply_damage_') -and
    -not $pulse.Contains('"combat_divide_damage_') -and
    -not $pulse.Contains("attemptDotResist(target, type, 100, false)")) `
    "p14.precu-dot.pulse.nge-layers-retired-classic-cap-preserved"

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
        -not $case.Contains("precuAuthoritative") -and
        -not $case.Contains("dot_vulnerability_") -and
        -not $case.Contains("expertise_") -and
        -not $case.Contains("DOT_ARMOR_MITIGATION_PERCENT")) `
        "p14.precu-dot.pulse.$($family.Absorption)-classic-absorption-only"
}

$buffDot = Get-BracedBlock $dot `
    "public static boolean applyBuffDotDamage(obj_id target, obj_id caster, String buffName, int strength, String type)"
Assert-Contract (([regex]::Matches($buffDot,
        'absorption_mod \+= getEnhancedSkillStatisticModifier\(target, "absorption_')).Count -eq
        [int]$contract.expected.retainedBuffDotTypes -and
    $buffDot.Contains("absorption_mod > 50") -and
    -not $buffDot.Contains('"dot_vulnerability_') -and
    -not $buffDot.Contains('"expertise_') -and
    -not $buffDot.Contains("DOT_ARMOR_MITIGATION_PERCENT") -and
    -not $buffDot.Contains('"combat_multiply_damage_') -and
    -not $buffDot.Contains('"combat_divide_damage_')) `
    "p14.precu-dot.buff-table.authored-types-use-precu-resolution"

$wrappedDamage = Get-BracedBlock $combatBase `
    "public void doWrappedDamage(obj_id attacker, obj_id defender, weapon_data weaponData, hit_result hitData, combat_data actionData, int overloadDamage)"
Assert-Contract ($wrappedDamage.Contains("if (!precuAuthoritativeAttack)") -and
    ([regex]::Matches($wrappedDamage, [regex]::Escape("dot.applyPrecuDotEffect("))).Count -eq 2 -and
    -not $wrappedDamage.Contains("dot.applyDotEffect(") -and
    -not $wrappedDamage.Contains('"expertise_dot_')) `
    "p14.precu-dot.callers.all-combat-branches-use-authored-precu-dots"

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
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready-for-live-verification", "ready") -contains
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
