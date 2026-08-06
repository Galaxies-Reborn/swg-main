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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuCombatExpertiseIsolation)
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

$texts = [ordered]@{}
$paths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    $paths[$property.Name] = $path
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.combat-expertise-isolation.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.combat-expertise-isolation.source.$($property.Name).authenticated"
}

$combatLibrary = [string]$texts.combatLibrary
$combatBase = [string]$texts.combatBase
$basePlayer = [string]$texts.basePlayer
$buffHandler = [string]$texts.buffHandler
$buffLibrary = [string]$texts.buffLibrary
$meditationLibrary = [string]$texts.meditationLibrary
$bountyHunterShieldScript = [string]$texts.bountyHunterShieldScript
$dictionaryCost = Get-BracedBlock $combatLibrary `
    "public static int[] getActionCost(obj_id self, weapon_data weaponData, dictionary actionData)"
$typedCost = Get-BracedBlock $combatLibrary `
    "public static int[] getActionCost(obj_id self, weapon_data weaponData, combat_data actionData)"
$successCost = Get-BracedBlock $combatLibrary `
    "public static int[] getSuccessBasedSingleTargetActionCost("
$hitEngine = Get-BracedBlock $combatBase `
    "public hit_result[] runHitEngine(attacker_data attackerData, weapon_data weaponData, defender_data[] defenderData, attacker_results attackerResults, defender_results[] defenderResults, combat_data actionData, boolean isTangibleAttacking, boolean isAutoAiming, int overloadDamage)"
$primaryHitChance = Get-BracedBlock $combatBase `
    "public float getPrecuPrimaryHitChance("
$secondaryDefense = Get-BracedBlock $combatBase `
    "public int getPrecuSecondaryDefenseResult("
$glancingResolution = Get-BracedBlock $hitEngine `
    "if (hitData[i].glancing)"

foreach ($entry in @(
    @{ Name = "dictionary"; Block = $dictionaryCost },
    @{ Name = "typed"; Block = $typedCost }
))
{
    $precu = $entry.Block.IndexOf("precuHamCostModel", [StringComparison]::Ordinal)
    $expertise = $entry.Block.IndexOf("expertise_action_", [StringComparison]::Ordinal)
    Assert-Contract ($precu -ge 0 -and $expertise -gt $precu -and
        $entry.Block.Contains("return getPrecuHamActionCost")) `
        "p14.combat-expertise-isolation.ham.$($entry.Name)-precu-before-expertise"
}

$areaReturn = $successCost.IndexOf("if (!isSingleTargetAttack)", [StringComparison]::Ordinal)
$precuReturn = $successCost.IndexOf("if (actionData.precuHamCostModel > 0)", [StringComparison]::Ordinal)
$freeshotRead = $successCost.IndexOf('"freeshot_case_miss"', [StringComparison]::Ordinal)
Assert-Contract ($areaReturn -ge 0 -and $precuReturn -gt $areaReturn -and
    $freeshotRead -gt $precuReturn -and
    $successCost.Contains("return getActionCost(attacker, weaponData, actionData);")) `
    "p14.combat-expertise-isolation.ham.single-precu-bypasses-freeshot"
Assert-Contract (([regex]::Matches($successCost, '"freeshot_case_(miss|dodge|parry|crit|strikethrough)"')).Count -eq
    [int]$contract.expected.ngeFreeshotModifierReadsBypassedForPrecu) `
    "p14.combat-expertise-isolation.ham.five-nge-freeshot-reads-bounded"

$precuBranch = $hitEngine.IndexOf("if (precuAuthoritativeAttack)", [StringComparison]::Ordinal)
$precuPrimary = $hitEngine.IndexOf("precuPrimaryResult = getPrecuPrimaryAttackResult(", [StringComparison]::Ordinal)
$precuSecondary = $hitEngine.IndexOf("precuSecondaryResult = getPrecuSecondaryDefenseResult(", [StringComparison]::Ordinal)
$ngeDefender = $hitEngine.IndexOf("defResult = getDefenderResult(", [StringComparison]::Ordinal)
$ngeAttacker = $hitEngine.IndexOf("atkResult = getAttackerResult(", [StringComparison]::Ordinal)
Assert-Contract ($precuBranch -ge 0 -and $precuPrimary -gt $precuBranch -and
    $precuSecondary -gt $precuPrimary -and $ngeDefender -gt $precuSecondary -and
    $ngeAttacker -gt $ngeDefender) `
    "p14.combat-expertise-isolation.hit.precu-and-nge-mutually-exclusive"
Assert-Contract ($hitEngine.Contains("precuPrimaryResult = HIT_RESULT_HIT;") -and
    $hitEngine.Contains("precuSecondaryResult = HIT_RESULT_HIT;") -and
    -not $hitEngine.Contains("precuPrimaryResult == PRECU_PRIMARY_RESULT_FALLBACK ?")) `
    "p14.combat-expertise-isolation.hit.precu-fallback-fails-closed"
Assert-Contract (([regex]::Matches($hitEngine, '\bgetLevel\s*\(')).Count -eq
        [int]$contract.expected.hitEngineCombatLevelReads -and
    ([regex]::Matches($primaryHitChance, '\bgetLevel\s*\(')).Count -eq
        [int]$contract.expected.precuPrimaryDefenseCombatLevelReads -and
    ([regex]::Matches($secondaryDefense, '\bgetLevel\s*\(')).Count -eq
        [int]$contract.expected.precuSecondaryDefenseCombatLevelReads -and
    $primaryHitChance.Contains("int defenseSkillValue = 0;") -and
    $primaryHitChance.Contains(
        "getEnhancedSkillStatisticModifierUncapped(defenderData.id, defenseSkill)") -and
    $secondaryDefense.Contains("int evadeSkill = 0;") -and
    $secondaryDefense.Contains(
        "getEnhancedSkillStatisticModifierUncapped(defenderData.id, secondaryDefenseSkill)")) `
    "p14.combat-expertise-isolation.hit.combat-level-defense-seeding-retired"
Assert-Contract ($hitEngine.Contains("if (!precuAuthoritativeAttack)") -and
    [bool]$contract.expected.postNgeCommandoHeavyWeaponPlayerBonusesRetired -and
    -not $hitEngine.Contains("combat.getDevastationChance") -and
    -not $hitEngine.Contains("heavyweapons.getHeavyWeaponDotName") -and
    -not $hitEngine.Contains("commando_passive_dot") -and
    $hitEngine.Contains("addPrecuCore3HateProcess") -and
    $hitEngine.Contains("combat.addHateProcess")) `
    "p14.combat-expertise-isolation.hit.damage-and-hate-era-boundary-preserved"
Assert-Contract ($glancingResolution.Contains("minDamage *= 0.35f") -and
    $glancingResolution.Contains("maxDamage *= 0.35f") -and
    $glancingResolution.Contains('new string_id("combat_effects", "glancing_blow")') -and
    -not $glancingResolution.Contains("expertise_fs_general_alacrity_1") -and
    -not $glancingResolution.Contains("appearance/pt_jedi_alacrity.prt") -and
    ([regex]::Matches($hitEngine, 'expertise_fs_general_alacrity_1')).Count -eq
        [int]$contract.expected.glancingNgeAlacritySkillReads -and
    ([regex]::Matches($hitEngine, 'appearance/pt_jedi_alacrity[.]prt')).Count -eq
        [int]$contract.expected.glancingNgeAlacrityEffects) `
    "p14.combat-expertise-isolation.hit.glancing-nge-alacrity-retired"

$overrides = @(Import-SwgTab -Path $paths.combatOverrides)
$validPools = @("HEALTH", "ACTION", "MIND", "RANDOM", "MULTI", "NO_ATTRIBUTE")
$invalidPools = @($overrides | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.targetPool) -or
    $validPools -cnotcontains [string]$_.targetPool
})
Assert-Contract ($overrides.Count -eq [int]$contract.expected.authenticatedCombatOverrideRows -and
    $invalidPools.Count -eq 0) `
    "p14.combat-expertise-isolation.data.all-overrides-explicit-target-pool"

$displayCleanup = Get-BracedBlock $basePlayer `
    "public int setDisplayOnlyDefensiveMods(obj_id self, dictionary params)"
$cleanupKeys = @([regex]::Matches($displayCleanup, '"(display_only_[^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-Contract ($cleanupKeys.Count -eq [int]$contract.expected.legacyNgeDisplayCleanupKeys -and
    @($cleanupKeys | Select-Object -Unique).Count -eq $cleanupKeys.Count -and
    ([regex]::Matches($displayCleanup, "removeAttribOrSkillModModifier\(")).Count -eq 1 -and
    -not $displayCleanup.Contains("addSkillModModifier") -and
    -not $displayCleanup.Contains("combat.get")) `
    "p14.combat-expertise-isolation.display.cleanup-only-handler"

$displayListingRows = @(Import-SwgTab -Path $paths.skillModListing |
    Where-Object { [string]$_.skill_mod -like "display_only_*" })
$uncoveredListingRows = @($displayListingRows |
    Where-Object { $cleanupKeys -cnotcontains [string]$_.skill_mod })
Assert-Contract ($displayListingRows.Count -eq [int]$contract.expected.inheritedNgeDisplayListingRows -and
    $uncoveredListingRows.Count -eq 0 -and
    @($displayListingRows | Where-Object {
        [string]$_.profession -cne "ALL" -or [string]$_.category -cne "combat" -or
        [int]$_.display -ne 1
    }).Count -eq 0) `
    "p14.combat-expertise-isolation.display.inherited-metadata-bounded"

$displayCallbackCounts = [ordered]@{
    basePlayer = ([regex]::Matches([string]$texts.basePlayer,
            'messageTo\([^;\r\n]*"setDisplayOnlyDefensiveMods"')).Count
    armorLibrary = ([regex]::Matches([string]$texts.armorLibrary,
            'messageTo\([^;\r\n]*"setDisplayOnlyDefensiveMods"')).Count
    reverseEngineering = ([regex]::Matches([string]$texts.reverseEngineering,
            'messageTo\([^;\r\n]*"setDisplayOnlyDefensiveMods"')).Count
    buffHandler = ([regex]::Matches([string]$texts.buffHandler,
            'messageTo\([^;\r\n]*"setDisplayOnlyDefensiveMods"')).Count
}
Assert-Contract ($displayCallbackCounts.basePlayer -eq [int]$contract.expected.basePlayerCleanupCallbacks -and
    ($displayCallbackCounts.Values | Measure-Object -Sum).Sum -eq
        [int]$contract.expected.productionCleanupCallbacks) `
    "p14.combat-expertise-isolation.display.production-cleanup-reachability"

$expertisePredicate = Get-BracedBlock $buffHandler `
    "public boolean isRetiredNgeExpertiseModifier(String modifierName)"
$primaryPredicate = Get-BracedBlock $buffHandler `
    "public boolean isRetiredNgePrimaryStatisticModifier(String modifierName)"
$buffPredicate = Get-BracedBlock $buffHandler `
    "public boolean isRetiredNgeBuffSkillModifier(String modifierName)"
$expertiseCleanup = Get-BracedBlock $buffHandler `
    "public void retireNgeExpertiseModifier(obj_id self, String effectName)"
$primaryModifierNames = @(
    "agility_modified", "constitution_modified", "luck_modified",
    "precision_modified", "stamina_modified", "strength_modified"
)
$primaryNamesInPredicate = @($primaryModifierNames | Where-Object {
    $primaryPredicate.Contains('modifierName.equals("' + $_ + '")')
})
Assert-Contract ($expertisePredicate.Contains('modifierName.startsWith("expertise_")') -and
    $primaryNamesInPredicate.Count -eq
        [int]$contract.expected.retiredNgePrimaryStatisticModifiers -and
    -not $primaryPredicate.Contains("milk_") -and
    $buffPredicate.Contains("isRetiredNgeExpertiseModifier(modifierName)") -and
    $buffPredicate.Contains("isRetiredNgePrimaryStatisticModifier(modifierName)") -and
    $expertiseCleanup.Contains("hasSkillModModifier(self, effectName)") -and
    $expertiseCleanup.Contains("removeAttribOrSkillModModifier(self, effectName)")) `
    "p14.combat-expertise-isolation.buff.central-cleanup-authority"

$genericExpertiseHandlers = @(
    (Get-BracedBlock $buffHandler "public int skillAddBuffHandler(")
    (Get-BracedBlock $buffHandler "public int skillPercentAddBuffHandler(")
    (Get-BracedBlock $buffHandler "public int forcePowerAddBuffHandler(")
)
$guardedGenericHandlers = @($genericExpertiseHandlers | Where-Object {
    $guard = $_.IndexOf("isRetiredNgeBuffSkillModifier(subtype)", [StringComparison]::Ordinal)
    $cleanup = $_.IndexOf("retireNgeExpertiseModifier(self, effectName)", [StringComparison]::Ordinal)
    $writer = $_.IndexOf("addSkillModModifier", [StringComparison]::Ordinal)
    $guard -ge 0 -and $cleanup -gt $guard -and $writer -gt $guard
})
$percentHandler = $genericExpertiseHandlers[1]
Assert-Contract ($genericExpertiseHandlers.Count + 1 -eq
        [int]$contract.expected.productionExpertiseBuffWriterHandlersGuarded -and
    $guardedGenericHandlers.Count -eq 3 -and
    $percentHandler.IndexOf("isRetiredNgeBuffSkillModifier(subtype)", [StringComparison]::Ordinal) -lt
        $percentHandler.IndexOf("getSkillStatisticModifier", [StringComparison]::Ordinal)) `
    "p14.combat-expertise-isolation.buff.generic-writers-guarded"

$armorBreak = Get-BracedBlock $buffHandler "public int armorBreakAddBuffHandler("
$armorBreakRemove = Get-BracedBlock $buffHandler "public int armorBreakRemoveBuffHandler("
Assert-Contract ($armorBreak.Contains("retireNgeExpertiseModifier(self, effectName)") -and
    $armorBreak.Contains("utils.removeScriptVar(self, INITIAL_GENERAL_PROTECTION)") -and
    $armorBreak.Contains('buff.applyBuff(self, caster, "bh_crit_hit_vuln")') -and
    -not $armorBreak.Contains("getSkillStatisticModifier") -and
    -not $armorBreak.Contains("getEnhancedSkillStatisticModifier") -and
    -not $armorBreak.Contains("addSkillModModifier") -and
    [int]$contract.expected.armorBreakNgeExpertiseReads -eq 0 -and
    [int]$contract.expected.armorBreakNgeExpertiseWrites -eq 0 -and
    $armorBreakRemove.Contains("utils.removeScriptVar(self, INITIAL_GENERAL_PROTECTION)")) `
    "p14.combat-expertise-isolation.buff.armor-break-cleanup-only"

$stanceHandler = Get-BracedBlock $buffHandler "public int stanceAddBuffHandler("
Assert-Contract ($stanceHandler.Contains('retireNgeExpertiseModifier(self, "expertise_fs_force_clarity_1_proc")') -and
    $stanceHandler.Contains('retireNgeExpertiseModifier(self, "expertise_fs_flurry_charge_proc")') -and
    $stanceHandler.Contains('messageTo(self, "cacheExpertiseProcReacList"') -and
    -not $stanceHandler.Contains('addSkillModModifier(self, "expertise_fs_force_clarity_1_proc"') -and
    -not $stanceHandler.Contains('addSkillModModifier(self, "expertise_fs_flurry_charge_proc"') -and
    [int]$contract.expected.directStanceExpertiseWriters -eq 0) `
    "p14.combat-expertise-isolation.buff.stance-procs-cleanup-only"

$buildABuff = Get-BracedBlock $buffHandler "public int buildabuffAddBuffHandler("
$literalExpertiseWriters = ([regex]::Matches($buffHandler,
        'addSkillModModifier\(self,\s*"expertise_')).Count
$buildLiteralExpertiseWriters = ([regex]::Matches($buildABuff,
        'addSkillModModifier\(self,\s*"expertise_')).Count
Assert-Contract ($literalExpertiseWriters -eq
        [int]$contract.expected.remainingLiteralExpertiseBuffWriters -and
    $buildLiteralExpertiseWriters -eq $literalExpertiseWriters -and
    $buildABuff.IndexOf("buff.isPostNgeBuffProgressionRetired()", [StringComparison]::Ordinal) -lt
        $buildABuff.IndexOf("performance.buildabuff.buffComponentKeys", [StringComparison]::Ordinal)) `
    "p14.combat-expertise-isolation.buff.remaining-literals-fail-closed"

$buffProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$meditationBuffCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeMeditationBuffs(obj_id player)"
$meditationStart = Get-BracedBlock $meditationLibrary `
    "public static boolean startMeditation(obj_id player)"
$meditationTick = Get-BracedBlock $basePlayer `
    "public int handleMeditationTick(obj_id self, dictionary params)"
$retiredMeditationNames = @([regex]::Matches($meditationBuffCleanup,
        '"fs_meditate_[123]"') | ForEach-Object { $_.Value.Trim('"') })
Assert-Contract ($buffProgressionCleanup.Contains("retirePostNgeMeditationBuffs(player);") -and
    $retiredMeditationNames.Count -eq [int]$contract.expected.retiredNgeMeditationBuffs -and
    @($retiredMeditationNames | Select-Object -Unique).Count -eq
        [int]$contract.expected.retiredNgeMeditationBuffs -and
    $meditationBuffCleanup.Contains("removeBuff(player, retiredBuff);") -and
    -not $meditationLibrary.Contains("MEDITATE_BUFFS") -and
    -not $meditationLibrary.Contains("fs_meditate_")) `
    "p14.combat-expertise-isolation.meditation.exact-nge-buffs-retired"
Assert-Contract ($meditationStart.IndexOf("buff.retirePostNgeMeditationBuffs(player);",
        [StringComparison]::Ordinal) -ge 0 -and
    $meditationStart.IndexOf("buff.retirePostNgeMeditationBuffs(player);",
        [StringComparison]::Ordinal) -lt
        $meditationStart.IndexOf("setState(player, STATE_MEDITATE, true);",
            [StringComparison]::Ordinal)) `
    "p14.combat-expertise-isolation.meditation.cleanup-dominates-start"
Assert-Contract ([bool]$contract.expected.meditationTickRandomGrantRetired -and
    $meditationTick.Contains("meditation.trance(self)") -and
    $meditationTick.Contains("messageTo(self, meditation.HANDLER_MEDITATION_TICK") -and
    -not $meditationTick.Contains("MEDITATE_BUFFS") -and
    -not $meditationTick.Contains("fs_meditate_") -and
    -not $meditationTick.Contains("buff.applyBuff") -and
    -not $meditationTick.Contains("utils.isProfession(self, utils.FORCE_SENSITIVE)") -and
    -not $meditationTick.Contains("utils.setScriptVar(self, meditation.VAR_MEDITATION_BASE")) `
    "p14.combat-expertise-isolation.meditation.random-tick-grant-retired"
$meditationRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    [string]$_.NAME -match '^fs_meditate_[123]$'
})
Assert-Contract ($meditationRows.Count -eq
        [int]$contract.expected.retainedNgeMeditationCompatibilityRows -and
    @($meditationRows | Where-Object {
        ([string]$_.EFFECT1_PARAM -notlike "expertise_*") -or
        ([string]$_.EFFECT3_PARAM -cne "expertise_resource_quality_increase")
    }).Count -eq 0) `
    "p14.combat-expertise-isolation.meditation.compatibility-rows-preserved"

$forceSensitiveStanceInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_FORCE_SENSITIVE_STANCE_BUFFS"
$forceSensitiveStancePredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgeForceSensitiveStanceBuff(String buffName)"
$forceSensitiveStanceCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeForceSensitiveStanceState(obj_id player)"
$forceSensitiveCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$isInStance = Get-BracedBlock $buffLibrary `
    "public static boolean isInStance(obj_id player)"
$isInFocus = Get-BracedBlock $buffLibrary `
    "public static boolean isInFocus(obj_id player)"
$retiredForceSensitiveStanceNames = @([regex]::Matches(
        $forceSensitiveStanceInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$forceSensitiveStanceRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object {
        $retiredForceSensitiveStanceNames -ccontains [string]$_.NAME
    })
$forceSensitiveGenericGate = $forceSensitiveCanApplyBuff.IndexOf(
    "isRetiredPostNgeForceSensitiveStanceBuff(bdata.buffName)",
    [StringComparison]::Ordinal)
$forceSensitiveExistingBuffReturn = $forceSensitiveCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$forceSensitiveHandlerGate = $stanceHandler.IndexOf(
    "buff.isRetiredPostNgeForceSensitiveStanceBuff(buffName)",
    [StringComparison]::Ordinal)
$forceSensitiveHandlerCleanup = $stanceHandler.IndexOf(
    "buff.retirePostNgeForceSensitiveStanceState(self);",
    [StringComparison]::Ordinal)
$forceSensitiveHandlerVisual = $stanceHandler.IndexOf(
    "buff.playStanceVisual(self, effectName);", [StringComparison]::Ordinal)
$forceSensitiveInvisHandler = Get-BracedBlock $buffHandler `
    "public void invisBuffAddBuffHandler(obj_id self"
$forceSensitiveInvisHandlerGate = $forceSensitiveInvisHandler.IndexOf(
    "buff.isRetiredPostNgeForceSensitiveStanceBuff(buffName)",
    [StringComparison]::Ordinal)
$forceSensitiveInvisHandlerEffect = $forceSensitiveInvisHandler.IndexOf(
    "stealth.invisBuffAdded(self, effectName);", [StringComparison]::Ordinal)
Assert-Contract ($retiredForceSensitiveStanceNames.Count -eq
        [int]$contract.expected.retiredNgeForceSensitiveStanceStateBuffs -and
    @($retiredForceSensitiveStanceNames | Select-Object -Unique).Count -eq
        $retiredForceSensitiveStanceNames.Count -and
    $forceSensitiveStancePredicate.Contains(
        "for (String retiredBuff : RETIRED_POST_NGE_FORCE_SENSITIVE_STANCE_BUFFS)") -and
    $forceSensitiveStanceCleanup.Contains("!isPlayer(player)") -and
    $forceSensitiveStanceCleanup.Contains("removeBuff(player, retiredBuff);") -and
    $forceSensitiveStanceCleanup.Contains('"expertise_fs_force_clarity_1_proc"') -and
    $forceSensitiveStanceCleanup.Contains('"expertise_fs_flurry_charge_proc"') -and
    $buffProgressionCleanup.Contains(
        "retirePostNgeForceSensitiveStanceState(player);") -and
    $basePlayer.Contains(
        "buff.retirePostNgeForceSensitiveStanceState(self);") -and
    $forceSensitiveGenericGate -ge 0 -and
    $forceSensitiveExistingBuffReturn -gt $forceSensitiveGenericGate -and
    [bool]$contract.expected.forceSensitiveStanceHandlerPlayerFailClosed -and
    $forceSensitiveHandlerGate -ge 0 -and
    $forceSensitiveHandlerCleanup -gt $forceSensitiveHandlerGate -and
    $forceSensitiveHandlerVisual -gt $forceSensitiveHandlerCleanup -and
    $forceSensitiveInvisHandlerGate -ge 0 -and
    $forceSensitiveInvisHandlerEffect -gt $forceSensitiveInvisHandlerGate -and
    $isInStance.Contains("retirePostNgeForceSensitiveStanceState(player);") -and
    $isInStance.Contains("return false;") -and
    $isInStance.Contains("return true;") -and
    $isInFocus.Contains("retirePostNgeForceSensitiveStanceState(player);") -and
    $isInFocus.Contains("return false;") -and
    $isInFocus.Contains("return true;")) `
    "p14.combat-expertise-isolation.force-sensitive-stances.all-player-paths-fail-closed"
Assert-Contract ($forceSensitiveStanceRows.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveStanceCompatibilityRows -and
    @($forceSensitiveStanceRows | Select-Object -ExpandProperty NAME -Unique).Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveStanceCompatibilityRows -and
    @($retiredForceSensitiveStanceNames | Where-Object {
        $_ -cnotin @($forceSensitiveStanceRows |
            Select-Object -ExpandProperty NAME)
    }).Count -eq
        [int]$contract.expected.historicalForceSensitiveStanceCleanupOnlyNames -and
    $retiredForceSensitiveStanceNames -ccontains "fs_imp_force_drain_4" -and
    $retiredForceSensitiveStanceNames -ccontains "invis_fs_buff_invis_1" -and
    -not ($retiredForceSensitiveStanceNames -ccontains "invis_forceCloak") -and
    [bool]$contract.expected.precuCenterOfBeingPreserved -and
    -not ($retiredForceSensitiveStanceNames -ccontains "centerofbeing") -and
    @(Import-SwgTab -Path $paths.buffTable | Where-Object {
        [string]$_.NAME -ceq "centerofbeing" -and
        [string]$_.EFFECT1_PARAM -ceq "private_center_of_being"
    }).Count -eq 1) `
    "p14.combat-expertise-isolation.force-sensitive-stances.compatibility-and-precu-center-boundary"

$bountyHunterShieldPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgeBountyHunterShieldBuff(String buffName)"
$bountyHunterShieldCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBountyHunterShieldState(obj_id player)"
$canApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$bountyHunterShieldHandler = Get-BracedBlock $buffHandler `
    "public int bhShieldsAddBuffHandler("
$bountyHunterShieldCallbacks = @(
    (Get-BracedBlock $bountyHunterShieldScript "public int OnAttach(")
    (Get-BracedBlock $bountyHunterShieldScript "public int OnInitialize(")
    (Get-BracedBlock $bountyHunterShieldScript "public int OnCreatureDamaged(")
)
$retiredBountyHunterShieldNames = @(
    "bh_shields_handler", "bh_shields", "bh_shields_block", "bh_shields_charged"
)
$predicateNames = @($retiredBountyHunterShieldNames | Where-Object {
    $bountyHunterShieldPredicate.Contains('buffName.equals("' + $_ + '")')
})
$cleanupNames = @([regex]::Matches($bountyHunterShieldCleanup,
        '"(bh_shields(?:_handler|_block|_charged)?)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-Contract ($predicateNames.Count -eq
        [int]$contract.expected.retiredNgeBountyHunterShieldBuffs -and
    $cleanupNames.Count -eq [int]$contract.expected.retiredNgeBountyHunterShieldBuffs -and
    @($cleanupNames | Select-Object -Unique).Count -eq $cleanupNames.Count -and
    $bountyHunterShieldCleanup.Contains("!isPlayer(player)") -and
    $bountyHunterShieldCleanup.Contains("removeBuff(player, retiredBuff);") -and
    $bountyHunterShieldCleanup.Contains('detachScript(player, "player.skill.bh_shields");') -and
    $buffProgressionCleanup.Contains("retirePostNgeBountyHunterShieldState(player);")) `
    "p14.combat-expertise-isolation.bounty-hunter-shields.persisted-state-retired"
$genericShieldGate = $canApplyBuff.IndexOf(
    "isRetiredPostNgeBountyHunterShieldBuff(bdata.buffName)",
    [StringComparison]::Ordinal)
$genericExistingBuffReturn = $canApplyBuff.IndexOf("hasBuff(target, nameCrc)",
    [StringComparison]::Ordinal)
$handlerPlayerGate = $bountyHunterShieldHandler.IndexOf("if (isPlayer(self))",
    [StringComparison]::Ordinal)
$handlerCleanup = $bountyHunterShieldHandler.IndexOf(
    "buff.retirePostNgeBountyHunterShieldState(self);", [StringComparison]::Ordinal)
$handlerAttach = $bountyHunterShieldHandler.IndexOf(
    'attachScript(self, "player.skill.bh_shields");', [StringComparison]::Ordinal)
$guardedShieldCallbacks = @($bountyHunterShieldCallbacks | Where-Object {
    $_.Contains("if (isPlayer(self))") -and
    $_.Contains("buff.retirePostNgeBountyHunterShieldState(self);")
})
$damageCallback = $bountyHunterShieldCallbacks[2]
Assert-Contract ($genericShieldGate -ge 0 -and
    $genericExistingBuffReturn -gt $genericShieldGate -and
    $handlerPlayerGate -ge 0 -and $handlerCleanup -gt $handlerPlayerGate -and
    $handlerAttach -gt $handlerCleanup -and
    $guardedShieldCallbacks.Count -eq
        [int]$contract.expected.retiredBountyHunterShieldScriptCallbacks -and
    $damageCallback.IndexOf("buff.retirePostNgeBountyHunterShieldState(self);",
        [StringComparison]::Ordinal) -lt
        $damageCallback.IndexOf("buff.applyBuff", [StringComparison]::Ordinal)) `
    "p14.combat-expertise-isolation.bounty-hunter-shields.all-player-writers-fail-closed"
$bountyHunterShieldRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $retiredBountyHunterShieldNames -ccontains [string]$_.NAME
})
Assert-Contract ($bountyHunterShieldRows.Count -eq
        [int]$contract.expected.retainedNgeBountyHunterShieldCompatibilityRows -and
    @($bountyHunterShieldRows | Select-Object -ExpandProperty NAME -Unique).Count -eq
        [int]$contract.expected.retainedNgeBountyHunterShieldCompatibilityRows) `
    "p14.combat-expertise-isolation.bounty-hunter-shields.compatibility-rows-preserved"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.combat-expertise-isolation.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.combat-expertise-isolation.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.combatLibrary -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.combatBase -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.basePlayer -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.buffHandler -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.buffLibrary -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.meditationLibrary -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.bountyHunterShieldScript -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.combat-expertise-isolation.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.combat-expertise-isolation.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "p14.combat-expertise-isolation.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU combat expertise isolation failed: $($failures -join ', ')"
}
Write-Host "PRE-CU combat expertise isolation contract passed."
