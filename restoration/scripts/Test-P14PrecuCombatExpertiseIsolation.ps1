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
$staticItemLibrary = [string]$texts.staticItemLibrary
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
$expertiseDamageModify = Get-BracedBlock $combatBase `
    "public int expertiseDamageModify(obj_id attacker, obj_id defender, hit_result hitData, combat_data actionData)"
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
$hitCriticalCleanup = $hitEngine.IndexOf(
    "buff.clearPostNgePlayerCriticalOverrideScriptVars(attackerData.id);",
    [StringComparison]::Ordinal)
$nextCriticalRead = $hitEngine.IndexOf('"nextCritHit"', [StringComparison]::Ordinal)
$criticalRemovalRead = $hitEngine.IndexOf('"critRemoveBuffNames"', [StringComparison]::Ordinal)
$damageCriticalCleanup = $expertiseDamageModify.IndexOf(
    "buff.clearPostNgePlayerCriticalOverrideScriptVars(attacker);",
    [StringComparison]::Ordinal)
$criticalDoubleRead = $expertiseDamageModify.IndexOf(
    '"critDoubleDamage"', [StringComparison]::Ordinal)
$criticalRootRead = $expertiseDamageModify.IndexOf(
    '"critRoot"', [StringComparison]::Ordinal)
Assert-Contract ($hitCriticalCleanup -ge 0 -and
    $nextCriticalRead -gt $hitCriticalCleanup -and
    $criticalRemovalRead -gt $hitCriticalCleanup -and
    $damageCriticalCleanup -ge 0 -and
    $criticalDoubleRead -gt $damageCriticalCleanup -and
    $criticalRootRead -gt $damageCriticalCleanup -and
    -not [bool]$contract.expected.playerNgeCriticalOverrideCombatReadsReachable) `
    "p14.combat-expertise-isolation.hit.player-critical-overrides-cleared-before-consumers"
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
$sharedBuffPredicate = Get-BracedBlock $staticItemLibrary `
    "public static boolean isRetiredNgeBuffSkillModifier(String modifier)"
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
    $buffPredicate.Contains("static_item.isRetiredNgeBuffSkillModifier(modifierName)") -and
    $sharedBuffPredicate.Contains("isRetiredNgeStaticItemSkillModifier(modifier)") -and
    $sharedBuffPredicate.Contains('modifier.equals("damage_immune")') -and
    $sharedBuffPredicate.Contains('modifier.startsWith("dot_resist_")') -and
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

$modifierInventoryBlocks = @(
    (Get-BracedBlock $staticItemLibrary `
        "public static final String[] LEGACY_NGE_DYNAMIC_PRIMARY_MODIFIERS")
    (Get-BracedBlock $staticItemLibrary `
        "public static final String[] RETIRED_NGE_STATIC_ITEM_MODIFIERS")
    (Get-BracedBlock $staticItemLibrary `
        "public static final String[] RETIRED_NGE_ITEM_WRITER_MODIFIERS")
    (Get-BracedBlock $staticItemLibrary `
        "public static final String[] RETIRED_NGE_BUFF_COMBAT_MODIFIERS")
)
$retiredExactModifierNames = @($modifierInventoryBlocks |
    ForEach-Object { [regex]::Matches($_, '"([A-Za-z0-9_]+)"') } |
    ForEach-Object { $_.Groups[1].Value } |
    Select-Object -Unique)
function Test-RetiredNgeBuffModifier([string]$Modifier)
{
    if ([string]::IsNullOrWhiteSpace($Modifier)) { return $false }
    return $Modifier.StartsWith("expertise_", [StringComparison]::Ordinal) -or
        $Modifier.StartsWith("fast_attack_line_", [StringComparison]::Ordinal) -or
        $Modifier.StartsWith("bm_", [StringComparison]::Ordinal) -or
        $Modifier.StartsWith("dot_resist_", [StringComparison]::Ordinal) -or
        $Modifier -ceq "damage_immune" -or
        $retiredExactModifierNames -ccontains $Modifier
}
$retiredModifierBuffRows = [System.Collections.Generic.List[object]]::new()
foreach ($row in @(Import-SwgTab -Path $paths.buffTable))
{
    $effectParameters = @(1..5 | ForEach-Object {
        [string]$row.("EFFECT$($_)_PARAM")
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $retiredEffectParameters = @($effectParameters | Where-Object {
        Test-RetiredNgeBuffModifier $_
    })
    if ($retiredEffectParameters.Count -eq 0) { continue }
    $retiredModifierBuffRows.Add([pscustomobject]@{
        Name = [string]$row.NAME
        RetiredEffectParameters = $retiredEffectParameters
        OtherEffectParameters = @($effectParameters | Where-Object {
            -not (Test-RetiredNgeBuffModifier $_)
        })
    })
}
$distinctRetiredModifierNames = @($retiredModifierBuffRows |
    Select-Object -ExpandProperty Name -Unique)
$distinctRetiredEffectParameters = @($retiredModifierBuffRows |
    ForEach-Object { $_.RetiredEffectParameters } | Select-Object -Unique)
$mixedRetiredModifierRows = @($retiredModifierBuffRows | Where-Object {
    $_.OtherEffectParameters.Count -gt 0
})
$retiredEffectMappingRows = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object {
        $distinctRetiredEffectParameters -ccontains [string]$_.NAME
    })
$unmappedRetiredEffectParameters = @($distinctRetiredEffectParameters |
    Where-Object {
        $_ -cnotin @($retiredEffectMappingRows | Select-Object -ExpandProperty NAME)
    })
Assert-Contract ($retiredModifierBuffRows.Count -eq
        [int]$contract.expected.retiredNgePlayerModifierBuffRows -and
    $distinctRetiredModifierNames.Count -eq
        [int]$contract.expected.retiredNgePlayerModifierBuffNames -and
    $distinctRetiredEffectParameters.Count -eq
        [int]$contract.expected.retiredNgePlayerModifierEffectParameters -and
    $retiredEffectMappingRows.Count -eq
        [int]$contract.expected.retiredNgePlayerModifierEffectMappingRows -and
    $mixedRetiredModifierRows.Count -eq
        [int]$contract.expected.retiredNgePlayerModifierMixedEffectRows -and
    $unmappedRetiredEffectParameters.Count -eq 0) `
    "p14.combat-expertise-isolation.buff.retained-modifier-data-inventory-authenticated"

$modifierBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerModifierBuff(obj_id target, buff_data data)"
$modifierBuffCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerModifierBuffState(obj_id player)"
$modifierBuffProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$modifierCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$modifierAdmissionGate = $modifierCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerModifierBuff(target, bdata)",
    [StringComparison]::Ordinal)
$modifierExistingBuffReturn = $modifierCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($modifierBuffPredicate.Contains("!isPlayer(target)") -and
    $modifierBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $modifierBuffPredicate.Contains(
        "static_item.isRetiredNgeBuffSkillModifier(getEffectParam(data, effect))") -and
    $modifierBuffCleanup.Contains("!isPlayer(player)") -and
    $modifierBuffCleanup.Contains("getAllBuffs(player)") -and
    $modifierBuffCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $modifierBuffCleanup.Contains(
        "isRetiredPostNgePlayerModifierBuff(player, data)") -and
    $modifierBuffCleanup.Contains("removeBuff(player, activeBuff)") -and
    $modifierBuffProgressionCleanup.Contains(
        "retirePostNgePlayerModifierBuffState(player);") -and
    $modifierAdmissionGate -ge 0 -and
    $modifierExistingBuffReturn -gt $modifierAdmissionGate -and
    -not [bool]$contract.expected.playerNgeModifierBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeModifierBuffStateRemoved -and
    [bool]$contract.expected.nonPlayerNgeModifierBuffCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.player-modifier-admission-and-persistence-fail-closed"

$expectedDamageDealtOverrideBuffValues = [ordered]@{
    bm_enrage = "2"
    kun_one_sacrifice = "1.25"
    kun_two_sacrifice = "1.5"
    kun_three_sacrifice = "1.75"
    kun_four_sacrifice = "2"
    kun_five_sacrifice = "2.25"
    kun_six_sacrifice = "2.5"
    kun_seven_sacrifice = "2.75"
    kun_eight_sacrifice = "3"
    minder_add_debuff = "0.5"
    open_add_debuff = "0.9"
}
$damageDealtEffectMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.TYPE -ceq "damageDealtMod" })
$damageDealtBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq "damage_dealt_mod"
    }).Count -gt 0
})
$damageDealtInventoryMatches = @($damageDealtBuffRows | Where-Object {
    $expectedDamageDealtOverrideBuffValues.Contains([string]$_.NAME) -and
    [string]$_.EFFECT1_PARAM -ceq "damage_dealt_mod" -and
    [string]$_.EFFECT1_VALUE -ceq
        [string]$expectedDamageDealtOverrideBuffValues[[string]$_.NAME] -and
    [string]$_.IS_PERSISTENT -ceq "1"
})
Assert-Contract ($damageDealtEffectMappings.Count -eq
        [int]$contract.expected.retainedNgeDamageDealtOverrideEffectMappingRows -and
    [string]$damageDealtEffectMappings[0].NAME -ceq "damage_dealt_mod" -and
    [string]$damageDealtEffectMappings[0].SUBTYPE -ceq "damage_dealt_mod" -and
    $damageDealtBuffRows.Count -eq
        [int]$contract.expected.retainedNgeDamageDealtOverrideBuffRows -and
    $damageDealtInventoryMatches.Count -eq
        [int]$contract.expected.retainedNgeDamageDealtOverrideBuffRows) `
    "p14.combat-expertise-isolation.buff.damage-dealt-override-data-inventory-authenticated"

$damageDealtEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDamageDealtOverrideEffect(String effectName)"
$damageDealtBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDamageDealtOverrideBuff(obj_id target, buff_data data)"
$damageDealtRestore = Get-BracedBlock $buffLibrary `
    "public static void restorePostNgePlayerDamageDealtOverride(obj_id player)"
$damageDealtCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerDamageDealtOverrideState(obj_id player)"
$damageDealtProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$damageDealtCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$damageDealtAdmissionGate = $damageDealtCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerDamageDealtOverrideBuff(target, bdata)",
    [StringComparison]::Ordinal)
$damageDealtExistingBuffReturn = $damageDealtCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$damageDealtScaleRead = $damageDealtRestore.IndexOf(
    'utils.getFloatScriptVar(player, "damageDealtMod.scale")',
    [StringComparison]::Ordinal)
$damageDealtStateClear = $damageDealtRestore.IndexOf(
    'utils.removeScriptVarTree(player, "damageDealtMod")',
    [StringComparison]::Ordinal)
$damageDealtScaleRestore = $damageDealtRestore.IndexOf(
    "setScale(player, recordedScale)", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_DAMAGE_DEALT_OVERRIDE_EFFECT = "damage_dealt_mod"') -and
    $damageDealtEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_DAMAGE_DEALT_OVERRIDE_EFFECT") -and
    $damageDealtBuffPredicate.Contains("!isPlayer(target)") -and
    $damageDealtBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $damageDealtBuffPredicate.Contains(
        "isRetiredPostNgePlayerDamageDealtOverrideEffect(getEffectParam(data, effect))") -and
    $damageDealtCleanup.Contains("!isPlayer(player)") -and
    $damageDealtCleanup.Contains("getAllBuffs(player)") -and
    $damageDealtCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $damageDealtCleanup.Contains("removeBuff(player, activeBuff)") -and
    $damageDealtCleanup.Contains("restorePostNgePlayerDamageDealtOverride(player)") -and
    $damageDealtProgressionCleanup.Contains(
        "retirePostNgePlayerDamageDealtOverrideState(player);") -and
    $damageDealtAdmissionGate -ge 0 -and
    $damageDealtExistingBuffReturn -gt $damageDealtAdmissionGate -and
    -not [bool]$contract.expected.playerNgeDamageDealtOverrideBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeDamageDealtOverrideStateRemoved -and
    [bool]$contract.expected.nonPlayerNgeDamageDealtOverrideCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.player-damage-dealt-override-admission-and-persistence-fail-closed"
Assert-Contract ($damageDealtRestore.Contains("!isPlayer(player)") -and
    $damageDealtRestore.Contains(
        'utils.hasScriptVar(player, "damageDealtMod.value")') -and
    $damageDealtRestore.Contains(
        'utils.hasScriptVar(player, "damageDealtMod.scale")') -and
    $damageDealtScaleRead -ge 0 -and
    $damageDealtStateClear -gt $damageDealtScaleRead -and
    $damageDealtScaleRestore -gt $damageDealtStateClear -and
    $damageDealtRestore.Contains("recordedScale > 0.0f") -and
    [bool]$contract.expected.recordedPlayerScaleRestoredFromCapturedState) `
    "p14.combat-expertise-isolation.buff.player-damage-dealt-override-scale-restoration-bounded"

$damageDealtHandlerNames = @(
    "damageDealtModAddBuffHandler",
    "damageDealtModRemoveBuffHandler"
)
$guardedDamageDealtHandlers = 0
foreach ($handlerName in $damageDealtHandlerNames)
{
    $handler = Get-BracedBlock $buffHandler ("public int " + $handlerName + "(")
    $playerGuard = $handler.IndexOf("if (isPlayer(self))", [StringComparison]::Ordinal)
    $cleanup = $handler.IndexOf(
        "buff.restorePostNgePlayerDamageDealtOverride(self);",
        [StringComparison]::Ordinal)
    $playerReturn = $handler.IndexOf("return SCRIPT_CONTINUE;", $cleanup,
        [StringComparison]::Ordinal)
    $retainedPath = if ($handlerName -ceq "damageDealtModAddBuffHandler") {
        $handler.IndexOf('utils.setScriptVar(self, "damageDealtMod.value", value)',
            [StringComparison]::Ordinal)
    } else {
        $handler.IndexOf('utils.getFloatScriptVar(self, "damageDealtMod.scale")',
            [StringComparison]::Ordinal)
    }
    if ($playerGuard -ge 0 -and $cleanup -gt $playerGuard -and
        $playerReturn -gt $cleanup -and $retainedPath -gt $playerReturn)
    {
        ++$guardedDamageDealtHandlers
    }
}
Assert-Contract ($guardedDamageDealtHandlers -eq
        [int]$contract.expected.productionDamageDealtOverrideHandlersGuarded) `
    "p14.combat-expertise-isolation.buff.damage-dealt-override-handlers-player-fail-closed"

$rawDamage = Get-BracedBlock $combatBase "public dictionary getRawDamage("
$damageDealtConsumerPlayerGuard = $rawDamage.IndexOf(
    "if (isPlayer(attacker))", [StringComparison]::Ordinal)
$damageDealtConsumerCleanup = $rawDamage.IndexOf(
    "buff.restorePostNgePlayerDamageDealtOverride(attacker);",
    [StringComparison]::Ordinal)
$damageDealtConsumerRead = $rawDamage.IndexOf(
    'utils.getFloatScriptVar(attacker, "damageDealtMod.value")',
    [StringComparison]::Ordinal)
Assert-Contract ($damageDealtConsumerPlayerGuard -ge 0 -and
    $damageDealtConsumerCleanup -gt $damageDealtConsumerPlayerGuard -and
    $damageDealtConsumerRead -gt $damageDealtConsumerCleanup -and
    $rawDamage.Contains("minDamage *= enragedMod") -and
    $rawDamage.Contains("maxDamage *= enragedMod") -and
    [bool]$contract.expected.playerDamageConsumerClearsOverrideBeforeRead) `
    "p14.combat-expertise-isolation.hit.player-damage-dealt-override-cleared-before-consumer"

$weaponSpeedEffectMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.TYPE -ceq "weaponSpeedMod" })
$weaponSpeedBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq "weapon_speed_mod"
    }).Count -gt 0
})
Assert-Contract ($weaponSpeedEffectMappings.Count -eq
        [int]$contract.expected.retainedNgeWeaponSpeedOverrideEffectMappingRows -and
    [string]$weaponSpeedEffectMappings[0].NAME -ceq "weapon_speed_mod" -and
    [string]$weaponSpeedEffectMappings[0].SUBTYPE -ceq "weapon_speed_mod" -and
    $weaponSpeedBuffRows.Count -eq
        [int]$contract.expected.retainedNgeWeaponSpeedOverrideBuffRows -and
    [string]$weaponSpeedBuffRows[0].NAME -ceq "bm_frenzy" -and
    [string]$weaponSpeedBuffRows[0].EFFECT1_PARAM -ceq "weapon_speed_mod" -and
    [string]$weaponSpeedBuffRows[0].EFFECT1_VALUE -ceq "40" -and
    [string]$weaponSpeedBuffRows[0].IS_PERSISTENT -ceq "1") `
    "p14.combat-expertise-isolation.buff.weapon-speed-override-data-inventory-authenticated"

$weaponSpeedEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerWeaponSpeedOverrideEffect(String effectName)"
$weaponSpeedBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerWeaponSpeedOverrideBuff(obj_id target, buff_data data)"
$weaponSpeedRestore = Get-BracedBlock $buffLibrary `
    "public static void restorePostNgePlayerWeaponSpeedOverride(obj_id player)"
$weaponSpeedCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerWeaponSpeedOverrideState(obj_id player)"
$weaponSpeedProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$weaponSpeedCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$weaponSpeedAdmissionGate = $weaponSpeedCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerWeaponSpeedOverrideBuff(target, bdata)",
    [StringComparison]::Ordinal)
$weaponSpeedExistingBuffReturn = $weaponSpeedCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$weaponRecordRead = $weaponSpeedRestore.IndexOf(
    'utils.getStringScriptVar(player, "recordedAttackSpeed")',
    [StringComparison]::Ordinal)
$weaponRecordClear = $weaponSpeedRestore.IndexOf(
    'utils.removeScriptVar(player, "recordedAttackSpeed")',
    [StringComparison]::Ordinal)
$weaponRecordParse = $weaponSpeedRestore.IndexOf(
    "split(weaponRecord, '-')", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_WEAPON_SPEED_OVERRIDE_EFFECT = "weapon_speed_mod"') -and
    $weaponSpeedEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_WEAPON_SPEED_OVERRIDE_EFFECT") -and
    $weaponSpeedBuffPredicate.Contains("!isPlayer(target)") -and
    $weaponSpeedBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $weaponSpeedBuffPredicate.Contains(
        "isRetiredPostNgePlayerWeaponSpeedOverrideEffect(getEffectParam(data, effect))") -and
    $weaponSpeedCleanup.Contains("!isPlayer(player)") -and
    $weaponSpeedCleanup.Contains("getAllBuffs(player)") -and
    $weaponSpeedCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $weaponSpeedCleanup.Contains("removeBuff(player, activeBuff)") -and
    $weaponSpeedCleanup.Contains("restorePostNgePlayerWeaponSpeedOverride(player)") -and
    $weaponSpeedProgressionCleanup.Contains(
        "retirePostNgePlayerWeaponSpeedOverrideState(player);") -and
    $weaponSpeedAdmissionGate -ge 0 -and
    $weaponSpeedExistingBuffReturn -gt $weaponSpeedAdmissionGate -and
    -not [bool]$contract.expected.playerNgeWeaponSpeedOverrideBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeWeaponSpeedOverrideStateRemoved -and
    [bool]$contract.expected.nonPlayerNgeWeaponSpeedOverrideCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.player-weapon-speed-override-admission-and-persistence-fail-closed"
Assert-Contract ($weaponSpeedRestore.Contains("!isPlayer(player)") -and
    $weaponSpeedRestore.Contains('utils.hasScriptVar(player, "recordedAttackSpeed")') -and
    $weaponRecordRead -ge 0 -and $weaponRecordClear -gt $weaponRecordRead -and
    $weaponRecordParse -gt $weaponRecordClear -and
    $weaponSpeedRestore.Contains("parse.length != 2") -and
    $weaponSpeedRestore.Contains("utils.isNestedWithin(weapon, player)") -and
    $weaponSpeedRestore.Contains("weaponSpeed <= 0.0f") -and
    $weaponSpeedRestore.Contains("setWeaponAttackSpeed(weapon, weaponSpeed)") -and
    $weaponSpeedRestore.Contains("weapons.setWeaponData(weapon)") -and
    $weaponSpeedRestore.Contains('utils.removeScriptVar(weapon, "isCreatureWeapon")')) `
    "p14.combat-expertise-isolation.buff.player-weapon-speed-override-restoration-bounded"

$weaponSpeedHandlerNames = @(
    "weaponSpeedModAddBuffHandler",
    "weaponSpeedModRemoveBuffHandler"
)
$guardedWeaponSpeedHandlers = 0
foreach ($handlerName in $weaponSpeedHandlerNames)
{
    $handler = Get-BracedBlock $buffHandler ("public int " + $handlerName + "(")
    $playerGuard = $handler.IndexOf("if (isPlayer(self))", [StringComparison]::Ordinal)
    $cleanup = $handler.IndexOf(
        "buff.restorePostNgePlayerWeaponSpeedOverride(self);",
        [StringComparison]::Ordinal)
    $playerReturn = $handler.IndexOf("return SCRIPT_CONTINUE;", $cleanup,
        [StringComparison]::Ordinal)
    $retainedPath = if ($handlerName -ceq "weaponSpeedModAddBuffHandler") {
        $handler.IndexOf("getCurrentWeapon(self)", [StringComparison]::Ordinal)
    } else {
        $handler.IndexOf('utils.hasScriptVar(self, "recordedAttackSpeed")',
            [StringComparison]::Ordinal)
    }
    if ($playerGuard -ge 0 -and $cleanup -gt $playerGuard -and
        $playerReturn -gt $cleanup -and $retainedPath -gt $playerReturn)
    {
        ++$guardedWeaponSpeedHandlers
    }
}
Assert-Contract ($guardedWeaponSpeedHandlers -eq
        [int]$contract.expected.productionWeaponSpeedOverrideHandlersGuarded) `
    "p14.combat-expertise-isolation.buff.weapon-speed-override-handlers-player-fail-closed"

$retiredCriticalEffects = @(
    "expertise_next_hit_crit",
    "expertise_crit_double_damage",
    "expertise_crit_root",
    "expertise_crit_remove_buff"
)
$expectedCriticalEffectTypes = [ordered]@{
    expertise_next_hit_crit = "nextHitCrit"
    expertise_crit_double_damage = "critDoubleDamage"
    expertise_crit_root = "critRoot"
    expertise_crit_remove_buff = "critOnce"
}
$criticalEffectMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { $retiredCriticalEffects -ccontains [string]$_.NAME })
$unexpectedCriticalMappings = @($criticalEffectMappings | Where-Object {
    [string]$_.TYPE -cne [string]$expectedCriticalEffectTypes[[string]$_.NAME]
})
$criticalBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        $retiredCriticalEffects -ccontains [string]$row.("EFFECT$($_)_PARAM")
    }).Count -gt 0
})
$expectedCriticalBuffNames = @("sm_end_of_the_line", "sm_nerf_herder", "sm_off_the_cuff")
$actualCriticalBuffNames = @($criticalBuffRows.NAME | Sort-Object)
$criticalSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    @("sm_end_of_the_line", "sm_nerf_herder", "sm_off_the_cuff") -ccontains
        [string]$_.COMMANDS
})
Assert-Contract ($retiredCriticalEffects.Count -eq
        [int]$contract.expected.retiredNgePlayerCriticalOverrideEffects -and
    $criticalEffectMappings.Count -eq
        [int]$contract.expected.retainedNgeCriticalOverrideEffectMappingRows -and
    $unexpectedCriticalMappings.Count -eq 0 -and
    $criticalBuffRows.Count -eq
        [int]$contract.expected.retainedNgeCriticalOverrideBuffRows -and
    ($actualCriticalBuffNames -join ([char]0)) -ceq
        ($expectedCriticalBuffNames -join ([char]0)) -and
    $criticalSkillRows.Count -eq
        [int]$contract.expected.retainedNgeCriticalOverrideExpertiseSkillRows -and
    @($criticalSkillRows | Where-Object {
        -not ([string]$_.NAME).StartsWith("expertise_sm_general_", [StringComparison]::Ordinal)
    }).Count -eq 0) `
    "p14.combat-expertise-isolation.buff.critical-override-data-inventory-authenticated"

$criticalInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_CRITICAL_OVERRIDE_EFFECTS"
$criticalEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerCriticalOverrideEffect(String effectName)"
$criticalBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerCriticalOverrideBuff(obj_id target, buff_data data)"
$criticalScriptVarCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerCriticalOverrideScriptVars(obj_id player)"
$criticalBuffCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerCriticalOverrideState(obj_id player)"
$criticalBuffProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$criticalCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$criticalAdmissionGate = $criticalCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerCriticalOverrideBuff(target, bdata)",
    [StringComparison]::Ordinal)
$criticalExistingBuffReturn = $criticalCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$criticalInventoryNames = @([regex]::Matches($criticalInventory,
        '"([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
$criticalScriptVarNames = @([regex]::Matches($criticalScriptVarCleanup,
        'removeScriptVarTree\(player, "([A-Za-z0-9_]+)"\)') |
    ForEach-Object { $_.Groups[1].Value })
Assert-Contract ($criticalInventoryNames.Count -eq $retiredCriticalEffects.Count -and
    @($retiredCriticalEffects | Where-Object {
        $criticalInventoryNames -ccontains $_
    }).Count -eq $retiredCriticalEffects.Count -and
    $criticalEffectPredicate.Contains("RETIRED_POST_NGE_PLAYER_CRITICAL_OVERRIDE_EFFECTS") -and
    $criticalBuffPredicate.Contains("!isPlayer(target)") -and
    $criticalBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $criticalBuffPredicate.Contains(
        "isRetiredPostNgePlayerCriticalOverrideEffect(getEffectParam(data, effect))") -and
    $criticalScriptVarCleanup.Contains("!isPlayer(player)") -and
    $criticalScriptVarNames.Count -eq
        [int]$contract.expected.retiredNgePlayerCriticalOverrideScriptVars -and
    $criticalBuffCleanup.Contains("getAllBuffs(player)") -and
    $criticalBuffCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $criticalBuffCleanup.Contains("removeBuff(player, activeBuff)") -and
    $criticalBuffCleanup.Contains("clearPostNgePlayerCriticalOverrideScriptVars(player)") -and
    $criticalBuffProgressionCleanup.Contains(
        "retirePostNgePlayerCriticalOverrideState(player);") -and
    $criticalAdmissionGate -ge 0 -and
    $criticalExistingBuffReturn -gt $criticalAdmissionGate -and
    -not [bool]$contract.expected.playerNgeCriticalOverrideBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeCriticalOverrideStateRemoved -and
    [bool]$contract.expected.nonPlayerNgeCriticalOverrideCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.player-critical-override-admission-and-persistence-fail-closed"

$criticalHandlerSignatures = @(
    "nextHitCritAddBuffHandler",
    "nextHitCritRemoveBuffHandler",
    "critDoubleDamageAddBuffHandler",
    "critDoubleDamageRemoveBuffHandler",
    "critRootAddBuffHandler",
    "critRootRemoveBuffHandler",
    "critOnceAddBuffHandler",
    "critOnceRemoveBuffHandler"
)
$guardedCriticalHandlers = 0
foreach ($handlerName in $criticalHandlerSignatures)
{
    $handler = Get-BracedBlock $buffHandler ("public int " + $handlerName + "(")
    $playerGuard = $handler.IndexOf("if (isPlayer(self))", [StringComparison]::Ordinal)
    $cleanup = $handler.IndexOf(
        "buff.clearPostNgePlayerCriticalOverrideScriptVars(self);",
        [StringComparison]::Ordinal)
    $retainedWriter = $handler.IndexOf("utils.", $cleanup + 1, [StringComparison]::Ordinal)
    if ($playerGuard -ge 0 -and $cleanup -gt $playerGuard -and $retainedWriter -gt $cleanup -and
        $handler.IndexOf("return SCRIPT_CONTINUE;", $cleanup,
            [StringComparison]::Ordinal) -lt $retainedWriter)
    {
        ++$guardedCriticalHandlers
    }
}
Assert-Contract ($guardedCriticalHandlers -eq
        [int]$contract.expected.productionCriticalOverrideHandlersGuarded) `
    "p14.combat-expertise-isolation.buff.critical-override-handlers-player-fail-closed"

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
        [string]$contract.buildEvidence.compiledClassSha256.staticItemLibrary -match '^[a-f0-9]{64}$' -and
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
