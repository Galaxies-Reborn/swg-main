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
$combatActions = [string]$texts.combatActions
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

$actionDrainEffectMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.TYPE -ceq "actionDrain" })
$actionDrainBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq "immediate_action_drain"
    }).Count -gt 0
})
$actionDrainActualSignatures = @($actionDrainBuffRows | ForEach-Object {
    $row = $_
    @(
        [string]$row.NAME,
        [string]$row.DURATION,
        [string]$row.IS_PERSISTENT,
        [string]$row.EFFECT1_PARAM,
        [string]$row.EFFECT1_VALUE,
        [string]$row.EFFECT2_PARAM,
        [string]$row.EFFECT2_VALUE,
        [string]$row.EFFECT3_PARAM,
        [string]$row.EFFECT3_VALUE,
        [string]$row.EFFECT4_PARAM,
        [string]$row.EFFECT4_VALUE,
        [string]$row.EFFECT5_PARAM,
        [string]$row.EFFECT5_VALUE
    ) -join "|"
} | Sort-Object)
$actionDrainExpectedSignatures = @(
    "bh_intimidate|1|1|immediate_action_drain|1||0||0||0||0",
    "me_traumatize_1|1|1|immediate_action_drain|1|expertise_action_all|-50||0||0||0"
)
Assert-Contract ([int]$contract.expected.retiredNgePlayerActionDrainEffects -eq 1 -and
    $actionDrainEffectMappings.Count -eq
        [int]$contract.expected.retainedNgeActionDrainEffectMappingRows -and
    [string]$actionDrainEffectMappings[0].NAME -ceq "immediate_action_drain" -and
    [string]$actionDrainEffectMappings[0].SUBTYPE -ceq "immediate_action_drain" -and
    $actionDrainBuffRows.Count -eq
        [int]$contract.expected.retainedNgeActionDrainBuffRows -and
    (($actionDrainActualSignatures -join "`n") -ceq
        ($actionDrainExpectedSignatures -join "`n"))) `
    "p14.combat-expertise-isolation.buff.action-drain-data-inventory-authenticated"

$actionDrainEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerActionDrainEffect(String effectName)"
$actionDrainBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerActionDrainBuff(obj_id target, buff_data data)"
$actionDrainCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerActionDrainState(obj_id player)"
$actionDrainProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$actionDrainCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$actionDrainAdmissionGate = $actionDrainCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerActionDrainBuff(target, bdata)",
    [StringComparison]::Ordinal)
$actionDrainExistingBuffReturn = $actionDrainCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_ACTION_DRAIN_EFFECT = "immediate_action_drain"') -and
    $actionDrainEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_ACTION_DRAIN_EFFECT") -and
    $actionDrainBuffPredicate.Contains("!isPlayer(target)") -and
    $actionDrainBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $actionDrainBuffPredicate.Contains(
        "isRetiredPostNgePlayerActionDrainEffect(getEffectParam(data, effect))") -and
    $actionDrainCleanup.Contains("!isPlayer(player)") -and
    $actionDrainCleanup.Contains("getAllBuffs(player)") -and
    $actionDrainCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $actionDrainCleanup.Contains(
        "isRetiredPostNgePlayerActionDrainBuff(player, data)") -and
    $actionDrainCleanup.Contains("removeBuff(player, activeBuff)") -and
    $actionDrainProgressionCleanup.Contains(
        "retirePostNgePlayerActionDrainState(player);") -and
    $actionDrainAdmissionGate -ge 0 -and
    $actionDrainExistingBuffReturn -gt $actionDrainAdmissionGate -and
    -not [bool]$contract.expected.playerNgeActionDrainBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeActionDrainStateRemoved) `
    "p14.combat-expertise-isolation.buff.player-action-drain-admission-and-persistence-fail-closed"

$actionDrainAdd = Get-BracedBlock $buffHandler `
    "public int actionDrainAddBuffHandler("
$actionDrainGuard = $actionDrainAdd.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$actionDrainCleanupCall = $actionDrainAdd.IndexOf(
    "buff.retirePostNgePlayerActionDrainState(self);",
    [StringComparison]::Ordinal)
$actionDrainReturn = $actionDrainAdd.IndexOf(
    "return SCRIPT_CONTINUE;", $actionDrainCleanupCall,
    [StringComparison]::Ordinal)
$actionDrainCap = $actionDrainAdd.IndexOf(
    "if (value > getAction(self))", [StringComparison]::Ordinal)
$actionDrainWrite = $actionDrainAdd.IndexOf(
    "drainAttributes(self, (int)value, 0);", [StringComparison]::Ordinal)
$actionDrainImmunityCheck = $actionDrainAdd.IndexOf(
    'buff.hasBuff(self, "action_drain_immunity")',
    [StringComparison]::Ordinal)
$actionDrainImmunityApply = $actionDrainAdd.IndexOf(
    'buff.applyBuff(self, self, "action_drain_immunity")',
    [StringComparison]::Ordinal)
Assert-Contract ($actionDrainGuard -ge 0 -and
    $actionDrainCleanupCall -gt $actionDrainGuard -and
    $actionDrainReturn -gt $actionDrainCleanupCall -and
    $actionDrainCap -gt $actionDrainReturn -and
    $actionDrainWrite -gt $actionDrainCap -and
    $actionDrainImmunityCheck -gt $actionDrainWrite -and
    $actionDrainImmunityApply -gt $actionDrainImmunityCheck -and
    [int]$contract.expected.productionActionDrainHandlersGuarded -eq 1 -and
    -not [bool]$contract.expected.immediatePlayerActionDrainReachable -and
    [bool]$contract.expected.nonPlayerNgeActionDrainCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.action-drain-handler-player-fail-closed"

$actionBurnEffectMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.TYPE -ceq "actionBurn" })
$actionBurnBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq "action_burn"
    }).Count -gt 0
})
$actionBurnActualSignatures = @($actionBurnBuffRows | ForEach-Object {
    $row = $_
    @(
        [string]$row.NAME,
        [string]$row.DURATION,
        [string]$row.IS_PERSISTENT,
        [string]$row.EFFECT1_PARAM,
        [string]$row.EFFECT1_VALUE,
        [string]$row.EFFECT2_PARAM,
        [string]$row.EFFECT2_VALUE,
        [string]$row.EFFECT3_PARAM,
        [string]$row.EFFECT3_VALUE,
        [string]$row.EFFECT4_PARAM,
        [string]$row.EFFECT4_VALUE,
        [string]$row.EFFECT5_PARAM,
        [string]$row.EFFECT5_VALUE
    ) -join "|"
} | Sort-Object)
$actionBurnExpectedSignatures = @(
    "closed_fist_toxin|60|1|action_burn|100||0||0||0||0",
    "jedi_statue_dark_debuff_light|30|1|action_burn|100|private_armor_break|100|combat_parry_reduction|-200|expertise_block_chance|-20||0",
    "me_rheumatic_calamity_1|10|1|action_burn|65||0||0||0||0",
    "of_deadeye_debuff|15|1|action_burn|50|glancing_blow_vulnerable|30||0||0||0",
    "wod_agony|30|1|action_burn|25||0||0||0||0"
)
Assert-Contract ([int]$contract.expected.retiredNgePlayerActionBurnEffects -eq 1 -and
    $actionBurnEffectMappings.Count -eq
        [int]$contract.expected.retainedNgeActionBurnEffectMappingRows -and
    [string]$actionBurnEffectMappings[0].NAME -ceq "action_burn" -and
    [string]$actionBurnEffectMappings[0].SUBTYPE -ceq "action_burn" -and
    $actionBurnBuffRows.Count -eq
        [int]$contract.expected.retainedNgeActionBurnBuffRows -and
    (($actionBurnActualSignatures -join "`n") -ceq
        ($actionBurnExpectedSignatures -join "`n"))) `
    "p14.combat-expertise-isolation.buff.action-burn-data-inventory-authenticated"

$actionBurnEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerActionBurnEffect(String effectName)"
$actionBurnBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerActionBurnBuff(obj_id target, buff_data data)"
$actionBurnScriptVarCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerActionBurnScriptVars(obj_id player)"
$actionBurnCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerActionBurnState(obj_id player)"
$actionBurnProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$actionBurnCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$actionBurnAdmissionGate = $actionBurnCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerActionBurnBuff(target, bdata)",
    [StringComparison]::Ordinal)
$actionBurnExistingBuffReturn = $actionBurnCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$actionBurnActiveRead = $actionBurnCleanup.IndexOf(
    "getAllBuffs(player)", [StringComparison]::Ordinal)
$actionBurnActiveRemoval = $actionBurnCleanup.IndexOf(
    "removeBuff(player, activeBuff)", [StringComparison]::Ordinal)
$actionBurnFinalClear = $actionBurnCleanup.IndexOf(
    "clearPostNgePlayerActionBurnScriptVars(player);",
    [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_ACTION_BURN_EFFECT = "action_burn"') -and
    $actionBurnEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_ACTION_BURN_EFFECT") -and
    $actionBurnBuffPredicate.Contains("!isPlayer(target)") -and
    $actionBurnBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $actionBurnBuffPredicate.Contains(
        "isRetiredPostNgePlayerActionBurnEffect(getEffectParam(data, effect))") -and
    $actionBurnScriptVarCleanup.Contains("!isPlayer(player)") -and
    $actionBurnScriptVarCleanup.Contains(
        'utils.removeScriptVarTree(player, "buff.action_burn")') -and
    $actionBurnCleanup.Contains("!isPlayer(player)") -and
    $actionBurnActiveRead -ge 0 -and
    $actionBurnCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $actionBurnCleanup.Contains(
        "isRetiredPostNgePlayerActionBurnBuff(player, data)") -and
    $actionBurnActiveRemoval -gt $actionBurnActiveRead -and
    $actionBurnFinalClear -gt $actionBurnActiveRemoval -and
    $actionBurnProgressionCleanup.Contains(
        "retirePostNgePlayerActionBurnState(player);") -and
    $actionBurnAdmissionGate -ge 0 -and
    $actionBurnExistingBuffReturn -gt $actionBurnAdmissionGate -and
    -not [bool]$contract.expected.playerNgeActionBurnBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeActionBurnStateRemoved -and
    [bool]$contract.expected.stalePlayerActionBurnScriptVarsRemoved) `
    "p14.combat-expertise-isolation.buff.player-action-burn-admission-and-persistence-fail-closed"

$actionBurnAdd = Get-BracedBlock $buffHandler `
    "public int actionBurnAddBuffHandler("
$actionBurnRemove = Get-BracedBlock $buffHandler `
    "public int actionBurnRemoveBuffHandler("
$actionBurnAddGuard = $actionBurnAdd.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$actionBurnAddCleanup = $actionBurnAdd.IndexOf(
    "buff.retirePostNgePlayerActionBurnState(self);",
    [StringComparison]::Ordinal)
$actionBurnAddReturn = $actionBurnAdd.IndexOf(
    "return SCRIPT_CONTINUE;", $actionBurnAddCleanup,
    [StringComparison]::Ordinal)
$actionBurnAddWrite = $actionBurnAdd.IndexOf(
    'utils.setScriptVar(self, "buff.action_burn.value", value)',
    [StringComparison]::Ordinal)
$actionBurnRemoveGuard = $actionBurnRemove.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$actionBurnRemoveCleanup = $actionBurnRemove.IndexOf(
    "buff.clearPostNgePlayerActionBurnScriptVars(self);",
    [StringComparison]::Ordinal)
$actionBurnRemoveReturn = $actionBurnRemove.IndexOf(
    "return SCRIPT_CONTINUE;", $actionBurnRemoveCleanup,
    [StringComparison]::Ordinal)
$actionBurnRemoveWrite = $actionBurnRemove.IndexOf(
    'utils.removeScriptVar(self, "buff.action_burn.value")',
    [StringComparison]::Ordinal)
Assert-Contract ($actionBurnAddGuard -ge 0 -and
    $actionBurnAddCleanup -gt $actionBurnAddGuard -and
    $actionBurnAddReturn -gt $actionBurnAddCleanup -and
    $actionBurnAddWrite -gt $actionBurnAddReturn -and
    $actionBurnRemoveGuard -ge 0 -and
    $actionBurnRemoveCleanup -gt $actionBurnRemoveGuard -and
    $actionBurnRemoveReturn -gt $actionBurnRemoveCleanup -and
    $actionBurnRemoveWrite -gt $actionBurnRemoveReturn -and
    [int]$contract.expected.productionActionBurnHandlersGuarded -eq 2 -and
    [bool]$contract.expected.nonPlayerNgeActionBurnCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.action-burn-handlers-player-fail-closed"

$actionBurnGuardedConsumers = 0
foreach ($actionCostConsumer in @($dictionaryCost, $typedCost))
{
    $actionBurnConsumerCleanup = $actionCostConsumer.IndexOf(
        "buff.retirePostNgePlayerActionBurnState(self);",
        [StringComparison]::Ordinal)
    $actionBurnConsumerRead = $actionCostConsumer.IndexOf(
        'utils.hasScriptVar(self, "buff.action_burn.value")',
        [StringComparison]::Ordinal)
    if ($actionBurnConsumerCleanup -ge 0 -and
        $actionBurnConsumerRead -gt $actionBurnConsumerCleanup)
    {
        $actionBurnConsumerGuard = $actionCostConsumer.LastIndexOf(
            "if (isPlayer(self))", $actionBurnConsumerCleanup,
            [StringComparison]::Ordinal)
        if ($actionBurnConsumerGuard -ge 0)
        {
            ++$actionBurnGuardedConsumers
        }
    }
}
Assert-Contract ($actionBurnGuardedConsumers -eq
        [int]$contract.expected.productionActionBurnConsumersGuarded -and
    -not [bool]$contract.expected.playerNgeActionBurnCombatReadsReachable) `
    "p14.combat-expertise-isolation.ham.player-action-burn-cleared-before-consumers"

$actionRegenEffectMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.TYPE -ceq "actionRegen" })
$actionRegenBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq "action_regen"
    }).Count -gt 0
})
Assert-Contract ($actionRegenEffectMappings.Count -eq
        [int]$contract.expected.retainedNgeActionRegenEffectMappingRows -and
    [string]$actionRegenEffectMappings[0].NAME -ceq "action_regen" -and
    [string]$actionRegenEffectMappings[0].SUBTYPE -ceq "N_A" -and
    $actionRegenBuffRows.Count -eq
        [int]$contract.expected.retainedNgeActionRegenBuffRows -and
    [string]$actionRegenBuffRows[0].NAME -ceq "sp_action_regen" -and
    [string]$actionRegenBuffRows[0].DURATION -ceq "15" -and
    [string]$actionRegenBuffRows[0].EFFECT1_PARAM -ceq "action_regen" -and
    [string]$actionRegenBuffRows[0].EFFECT1_VALUE -ceq "0" -and
    [string]$actionRegenBuffRows[0].EFFECT2_PARAM -ceq "movement" -and
    [string]$actionRegenBuffRows[0].EFFECT2_VALUE -ceq "2" -and
    [string]$actionRegenBuffRows[0].IS_PERSISTENT -ceq "1") `
    "p14.combat-expertise-isolation.buff.action-regen-data-inventory-authenticated"

$actionRegenEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerActionRegenEffect(String effectName)"
$actionRegenBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerActionRegenBuff(obj_id target, buff_data data)"
$actionRegenCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerActionRegenState(obj_id player)"
$actionRegenProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$actionRegenCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$actionRegenAdmissionGate = $actionRegenCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerActionRegenBuff(target, bdata)",
    [StringComparison]::Ordinal)
$actionRegenExistingBuffReturn = $actionRegenCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_ACTION_REGEN_EFFECT = "action_regen"') -and
    $actionRegenEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_ACTION_REGEN_EFFECT") -and
    $actionRegenBuffPredicate.Contains("!isPlayer(target)") -and
    $actionRegenBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $actionRegenBuffPredicate.Contains(
        "isRetiredPostNgePlayerActionRegenEffect(getEffectParam(data, effect))") -and
    $actionRegenCleanup.Contains("!isPlayer(player)") -and
    $actionRegenCleanup.Contains("getAllBuffs(player)") -and
    $actionRegenCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $actionRegenCleanup.Contains("removeBuff(player, activeBuff)") -and
    $actionRegenProgressionCleanup.Contains(
        "retirePostNgePlayerActionRegenState(player);") -and
    $actionRegenAdmissionGate -ge 0 -and
    $actionRegenExistingBuffReturn -gt $actionRegenAdmissionGate -and
    -not [bool]$contract.expected.playerNgeActionRegenBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeActionRegenStateRemoved -and
    [bool]$contract.expected.nonPlayerNgeActionRegenCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.player-action-regen-admission-and-persistence-fail-closed"

$actionRegenAdd = Get-BracedBlock $buffHandler `
    "public int actionRegenAddBuffHandler("
$actionRegenTick = Get-BracedBlock $buffHandler `
    "public int actionRegenBuff(obj_id self, dictionary params)"
$actionRegenAddGuard = $actionRegenAdd.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$actionRegenAddCleanup = $actionRegenAdd.IndexOf(
    "buff.retirePostNgePlayerActionRegenState(self);",
    [StringComparison]::Ordinal)
$actionRegenAddReturn = $actionRegenAdd.IndexOf(
    "return SCRIPT_CONTINUE;", $actionRegenAddCleanup,
    [StringComparison]::Ordinal)
$actionRegenAddWrite = $actionRegenAdd.IndexOf(
    "int actionMax = getMaxAction(self);", [StringComparison]::Ordinal)
$actionRegenTickGuard = $actionRegenTick.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$actionRegenTickCleanup = $actionRegenTick.IndexOf(
    "buff.retirePostNgePlayerActionRegenState(self);",
    [StringComparison]::Ordinal)
$actionRegenTickReturn = $actionRegenTick.IndexOf(
    "return SCRIPT_CONTINUE;", $actionRegenTickCleanup,
    [StringComparison]::Ordinal)
$actionRegenTickBuffCheck = $actionRegenTick.IndexOf(
    "if (!buff.hasBuff(self, buffName))", [StringComparison]::Ordinal)
$actionRegenTickHeal = $actionRegenTick.IndexOf(
    "healing.healDamage(self, ACTION, (int)healAmount);",
    [StringComparison]::Ordinal)
Assert-Contract ($actionRegenAddGuard -ge 0 -and
    $actionRegenAddCleanup -gt $actionRegenAddGuard -and
    $actionRegenAddReturn -gt $actionRegenAddCleanup -and
    $actionRegenAddWrite -gt $actionRegenAddReturn -and
    $actionRegenTickGuard -ge 0 -and
    $actionRegenTickCleanup -gt $actionRegenTickGuard -and
    $actionRegenTickReturn -gt $actionRegenTickCleanup -and
    $actionRegenTickBuffCheck -gt $actionRegenTickReturn -and
    $actionRegenTickHeal -gt $actionRegenTickBuffCheck -and
    [int]$contract.expected.productionActionRegenPlayerExecutionGuards -eq 2 -and
    -not [bool]$contract.expected.delayedPlayerActionRegenCallbackReachable) `
    "p14.combat-expertise-isolation.buff.action-regen-handlers-player-fail-closed"

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

$shiftySetupMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -ceq "on_attack_remove" })
$shiftySetupBuffRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object { [string]$_.NAME -ceq "sp_shifty_setup" })
$shiftySetupSkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object { [string]$_.NAME -ceq "expertise_sp_shifty_setup_1" })
Assert-Contract ($shiftySetupMappings.Count -eq
        [int]$contract.expected.retainedNgeSpyShiftySetupEffectMappingRows -and
    @($shiftySetupMappings | Where-Object {
        [string]$_.TYPE -ceq "onAttackRemove" -and
        [string]$_.SUBTYPE -ceq "on_attack_remove"
    }).Count -eq $shiftySetupMappings.Count -and
    $shiftySetupBuffRows.Count -eq
        [int]$contract.expected.retainedNgeSpyShiftySetupBuffRows -and
    [string]$shiftySetupBuffRows[0].EFFECT4_PARAM -ceq "on_attack_remove" -and
    $shiftySetupSkillRows.Count -eq
        [int]$contract.expected.retainedNgeSpyShiftySetupExpertiseSkillRows -and
    [string]$shiftySetupSkillRows[0].COMMANDS -ceq "sp_shifty_setup") `
    "p14.combat-expertise-isolation.spy-shifty-setup.data-authenticated"

$shiftySetupEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerOnAttackRemoveEffect(String effectName)"
$shiftySetupBuffNamePredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerOnAttackRemoveBuffName(String buffName)"
$shiftySetupBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerOnAttackRemoveBuff(obj_id target, buff_data data)"
$shiftySetupResidueCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerOnAttackRemoveState(obj_id player)"
$shiftySetupStateCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerOnAttackRemoveState(obj_id player)"
$shiftySetupProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$shiftySetupCanApply = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$shiftySetupAdmissionGate = $shiftySetupCanApply.IndexOf(
    "isRetiredPostNgePlayerOnAttackRemoveBuff(target, bdata)",
    [StringComparison]::Ordinal)
$shiftySetupExistingBuffReturn = $shiftySetupCanApply.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$shiftySetupCombatCleanup = $hitEngine.IndexOf(
    "buff.clearPostNgePlayerOnAttackRemoveState(attackerData.id);",
    [StringComparison]::Ordinal)
$shiftySetupCombatConsumer = $hitEngine.IndexOf(
    "utils.hasScriptVar(attackerData.id, buff.ON_ATTACK_REMOVE)",
    [StringComparison]::Ordinal)
Assert-Contract (([regex]::Matches($buffLibrary,
        'RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_EFFECT\s*=\s*"on_attack_remove"')).Count -eq 1 -and
    ([regex]::Matches($buffLibrary,
        'RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_BUFF\s*=\s*"sp_shifty_setup"')).Count -eq 1 -and
    $shiftySetupEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_EFFECT") -and
    $shiftySetupBuffNamePredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_BUFF") -and
    $shiftySetupBuffPredicate.Contains("!isPlayer(target)") -and
    $shiftySetupBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $shiftySetupBuffPredicate.Contains(
        "isRetiredPostNgePlayerOnAttackRemoveEffect(getEffectParam(data, effect))") -and
    $shiftySetupResidueCleanup.Contains(
        "utils.removeScriptVarTree(player, ON_ATTACK_REMOVE)") -and
    $shiftySetupStateCleanup.Contains("removeBuff(player, activeBuff)") -and
    $shiftySetupStateCleanup.Contains("clearPostNgePlayerOnAttackRemoveState(player)") -and
    $shiftySetupProgressionCleanup.Contains(
        "retirePostNgePlayerOnAttackRemoveState(player);") -and
    $shiftySetupAdmissionGate -ge 0 -and
    $shiftySetupExistingBuffReturn -gt $shiftySetupAdmissionGate -and
    $shiftySetupCombatCleanup -ge 0 -and
    $shiftySetupCombatConsumer -gt $shiftySetupCombatCleanup -and
    [int]$contract.expected.retiredNgePlayerSpyShiftySetupScriptVars -eq 1 -and
    -not [bool]$contract.expected.playerNgeSpyShiftySetupBuffAdmissionReachable -and
    -not [bool]$contract.expected.playerNgeSpyShiftySetupCombatConsumerReachable -and
    [bool]$contract.expected.persistedPlayerNgeSpyShiftySetupStateRemoved -and
    [bool]$contract.expected.nonPlayerNgeSpyShiftySetupCompatibilityPreserved) `
    "p14.combat-expertise-isolation.spy-shifty-setup.admission-state-and-consumer-fail-closed"

$shiftySetupHandlerNames = @(
    "onAttackRemoveAddBuffHandler", "onAttackRemoveRemoveBuffHandler"
)
$guardedShiftySetupHandlers = 0
foreach ($handlerName in $shiftySetupHandlerNames)
{
    $handler = Get-BracedBlock $buffHandler ("public int " + $handlerName + "(")
    $guard = $handler.IndexOf("isPlayer(self)", [StringComparison]::Ordinal)
    $effect = $handler.IndexOf(
        "isRetiredPostNgePlayerOnAttackRemoveEffect(effectName)",
        [StringComparison]::Ordinal)
    $name = $handler.IndexOf(
        "isRetiredPostNgePlayerOnAttackRemoveBuffName(buffName)",
        [StringComparison]::Ordinal)
    $cleanup = $handler.IndexOf(
        "buff.clearPostNgePlayerOnAttackRemoveState(self);",
        [StringComparison]::Ordinal)
    $playerReturn = $handler.IndexOf("return SCRIPT_OVERRIDE;", $cleanup,
        [StringComparison]::Ordinal)
    $retainedWriter = $handler.IndexOf("Vector removeBuffs", $playerReturn,
        [StringComparison]::Ordinal)
    if ($guard -ge 0 -and $effect -gt $guard -and $name -gt $guard -and
        $cleanup -gt $name -and $playerReturn -gt $cleanup -and
        $retainedWriter -gt $playerReturn)
    {
        ++$guardedShiftySetupHandlers
    }
}
Assert-Contract ($guardedShiftySetupHandlers -eq
        [int]$contract.expected.productionSpyShiftySetupHandlersGuarded) `
    "p14.combat-expertise-isolation.spy-shifty-setup.two-handlers-player-fail-closed"

$expectedLuckHitEffectTypes = [ordered]@{
    sm_impossible_odds = "hitByLuck"
    sm_skullduggery = "missByLuck"
}
$luckHitEffectMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { $expectedLuckHitEffectTypes.Contains([string]$_.NAME) })
$unexpectedLuckHitMappings = @($luckHitEffectMappings | Where-Object {
    [string]$_.TYPE -cne [string]$expectedLuckHitEffectTypes[[string]$_.NAME]
})
$luckHitBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        $expectedLuckHitEffectTypes.Contains([string]$row.("EFFECT$($_)_PARAM"))
    }).Count -gt 0
})
$luckHitActualSignatures = @($luckHitBuffRows | ForEach-Object {
    $row = $_
    @(
        [string]$row.NAME,
        [string]$row.DURATION,
        [string]$row.IS_PERSISTENT,
        [string]$row.EFFECT1_PARAM,
        [string]$row.EFFECT1_VALUE,
        [string]$row.EFFECT2_PARAM,
        [string]$row.EFFECT2_VALUE,
        [string]$row.EFFECT3_PARAM,
        [string]$row.EFFECT3_VALUE,
        [string]$row.EFFECT4_PARAM,
        [string]$row.EFFECT4_VALUE,
        [string]$row.EFFECT5_PARAM,
        [string]$row.EFFECT5_VALUE
    ) -join "|"
} | Sort-Object)
$luckHitExpectedSignatures = @(
    "sm_impossible_odds|4|1|sm_impossible_odds|4||0||0||0||0",
    "sm_skullduggery|4|1|sm_skullduggery|4||0||0||0||0"
)
$luckHitSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    @("sm_impossible_odds", "sm_skullduggery") -ccontains [string]$_.COMMANDS
})
Assert-Contract ($expectedLuckHitEffectTypes.Count -eq
        [int]$contract.expected.retiredNgePlayerLuckHitOverrideEffects -and
    $luckHitEffectMappings.Count -eq
        [int]$contract.expected.retainedNgeLuckHitOverrideEffectMappingRows -and
    $unexpectedLuckHitMappings.Count -eq 0 -and
    $luckHitBuffRows.Count -eq
        [int]$contract.expected.retainedNgeLuckHitOverrideBuffRows -and
    (($luckHitActualSignatures -join "`n") -ceq
        ($luckHitExpectedSignatures -join "`n")) -and
    $luckHitSkillRows.Count -eq
        [int]$contract.expected.retainedNgeLuckHitOverrideExpertiseSkillRows -and
    @($luckHitSkillRows | Where-Object {
        -not ([string]$_.NAME).StartsWith("expertise_sm_path_", [StringComparison]::Ordinal)
    }).Count -eq 0) `
    "p14.combat-expertise-isolation.buff.luck-hit-override-data-inventory-authenticated"

$luckHitInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_LUCK_HIT_OVERRIDE_EFFECTS"
$luckHitEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerLuckHitOverrideEffect(String effectName)"
$luckHitBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerLuckHitOverrideBuff(obj_id target, buff_data data)"
$luckHitModifierCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerLuckHitOverrideModifiers(obj_id player)"
$luckHitBuffCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerLuckHitOverrideState(obj_id player)"
$luckHitProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$luckHitCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$luckHitAdmissionGate = $luckHitCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerLuckHitOverrideBuff(target, bdata)",
    [StringComparison]::Ordinal)
$luckHitExistingBuffReturn = $luckHitCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$luckHitInventoryNames = @([regex]::Matches($luckHitInventory,
        '"([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
$luckHitModifierNames = @([regex]::Matches($luckHitModifierCleanup,
        '"(hitByLuck|increaseHitByLuck|missByLuck)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-Contract ($luckHitInventoryNames.Count -eq $expectedLuckHitEffectTypes.Count -and
    @($expectedLuckHitEffectTypes.Keys | Where-Object {
        $luckHitInventoryNames -ccontains $_
    }).Count -eq $expectedLuckHitEffectTypes.Count -and
    $luckHitEffectPredicate.Contains("RETIRED_POST_NGE_PLAYER_LUCK_HIT_OVERRIDE_EFFECTS") -and
    $luckHitBuffPredicate.Contains("!isPlayer(target)") -and
    $luckHitBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $luckHitBuffPredicate.Contains(
        "isRetiredPostNgePlayerLuckHitOverrideEffect(getEffectParam(data, effect))") -and
    $luckHitModifierCleanup.Contains("!isPlayer(player)") -and
    $luckHitModifierNames.Count -eq
        [int]$contract.expected.retiredNgePlayerLuckHitOverrideModifiers -and
    @($luckHitModifierNames | Select-Object -Unique).Count -eq $luckHitModifierNames.Count -and
    $luckHitModifierCleanup.Contains("hasSkillModModifier(player, retiredModifier)") -and
    $luckHitModifierCleanup.Contains("removeAttribOrSkillModModifier(player, retiredModifier)") -and
    $luckHitBuffCleanup.Contains("getAllBuffs(player)") -and
    $luckHitBuffCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $luckHitBuffCleanup.Contains("removeBuff(player, activeBuff)") -and
    $luckHitBuffCleanup.Contains("clearPostNgePlayerLuckHitOverrideModifiers(player)") -and
    $luckHitProgressionCleanup.Contains(
        "retirePostNgePlayerLuckHitOverrideState(player);") -and
    $luckHitAdmissionGate -ge 0 -and
    $luckHitExistingBuffReturn -gt $luckHitAdmissionGate -and
    -not [bool]$contract.expected.playerNgeLuckHitOverrideBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeLuckHitOverrideStateRemoved -and
    [bool]$contract.expected.stalePlayerLuckHitOverrideModifiersRemoved -and
    [bool]$contract.expected.nonPlayerNgeLuckHitOverrideCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.player-luck-hit-override-admission-and-persistence-fail-closed"

$luckHitHandlerExpectations = @(
    [pscustomobject]@{
        Name = "missByLuckAddBuffHandler"
        Cleanup = "buff.retirePostNgePlayerLuckHitOverrideState(self);"
        RetainedWriter = 'getSkillStatisticModifier(caster, "expertise_miss_by_luck")'
    },
    [pscustomobject]@{
        Name = "missByLuckRemoveBuffHandler"
        Cleanup = "buff.clearPostNgePlayerLuckHitOverrideModifiers(self);"
        RetainedWriter = 'removeAttribOrSkillModModifier(self, "missByLuck")'
    },
    [pscustomobject]@{
        Name = "hitByLuckAddBuffHandler"
        Cleanup = "buff.retirePostNgePlayerLuckHitOverrideState(self);"
        RetainedWriter = 'getSkillStatisticModifier(caster, "expertise_hit_by_luck")'
    },
    [pscustomobject]@{
        Name = "hitByLuckRemoveBuffHandler"
        Cleanup = "buff.clearPostNgePlayerLuckHitOverrideModifiers(self);"
        RetainedWriter = 'removeAttribOrSkillModModifier(self, "hitByLuck")'
    }
)
$guardedLuckHitHandlers = 0
foreach ($handlerExpectation in $luckHitHandlerExpectations)
{
    $handler = Get-BracedBlock $buffHandler ("public int " + $handlerExpectation.Name + "(")
    $playerGuard = $handler.IndexOf("if (isPlayer(self))", [StringComparison]::Ordinal)
    $cleanup = $handler.IndexOf($handlerExpectation.Cleanup, [StringComparison]::Ordinal)
    $playerReturn = $handler.IndexOf("return SCRIPT_CONTINUE;", $cleanup,
        [StringComparison]::Ordinal)
    $retainedWriter = $handler.IndexOf($handlerExpectation.RetainedWriter,
        [StringComparison]::Ordinal)
    if ($playerGuard -ge 0 -and $cleanup -gt $playerGuard -and
        $playerReturn -gt $cleanup -and $retainedWriter -gt $playerReturn)
    {
        ++$guardedLuckHitHandlers
    }
}
Assert-Contract ($guardedLuckHitHandlers -eq
        [int]$contract.expected.productionLuckHitOverrideHandlersGuarded) `
    "p14.combat-expertise-isolation.buff.luck-hit-override-handlers-player-fail-closed"

$forsakeFearEffect = "expertise_channel_action_heal"
$forsakeFearMappings = @(Import-SwgTab -Path $paths.buffEffectMapping | Where-Object {
    [string]$_.NAME -ceq $forsakeFearEffect
})
$forsakeFearBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq $forsakeFearEffect
    }).Count -gt 0
})
$forsakeFearSignatures = @($forsakeFearBuffRows | ForEach-Object {
    $row = $_
    @(
        [string]$row.NAME,
        [string]$row.DURATION,
        [string]$row.IS_PERSISTENT,
        [string]$row.EFFECT1_PARAM,
        [string]$row.EFFECT1_VALUE,
        [string]$row.EFFECT2_PARAM,
        [string]$row.EFFECT2_VALUE,
        [string]$row.EFFECT3_PARAM,
        [string]$row.EFFECT3_VALUE,
        [string]$row.EFFECT4_PARAM,
        [string]$row.EFFECT4_VALUE,
        [string]$row.EFFECT5_PARAM,
        [string]$row.EFFECT5_VALUE
    ) -join "|"
})
$forsakeFearSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    [string]$_.COMMANDS -ceq "fs_forsake_fear"
})
Assert-Contract ($forsakeFearMappings.Count -eq
        [int]$contract.expected.retainedNgeForsakeFearEffectMappingRows -and
    [string]$forsakeFearMappings[0].TYPE -ceq "expertiseChannelActionHeal" -and
    [string]$forsakeFearMappings[0].SUBTYPE -ceq $forsakeFearEffect -and
    $forsakeFearBuffRows.Count -eq
        [int]$contract.expected.retainedNgeForsakeFearBuffRows -and
    (($forsakeFearSignatures -join "`n") -ceq
        "fs_forsake_fear|10|1|group|0|expertise_channel_action_heal|6||0||0||0") -and
    $forsakeFearSkillRows.Count -eq
        [int]$contract.expected.retainedNgeForsakeFearExpertiseSkillRows -and
    [string]$forsakeFearSkillRows[0].NAME -ceq "expertise_fs_path_forsake_fear_1") `
    "p14.combat-expertise-isolation.buff.forsake-fear-data-inventory-authenticated"

$forsakeFearEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerForsakeFearChannelEffect(String effectName)"
$forsakeFearBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerForsakeFearChannelBuff(obj_id target, buff_data data)"
$forsakeFearStateCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerForsakeFearChannelState(obj_id player)"
$forsakeFearLifecycleCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerForsakeFearChannelState(obj_id player)"
$forsakeFearProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$forsakeFearCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$forsakeFearAdmissionGate = $forsakeFearCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerForsakeFearChannelBuff(target, bdata)",
    [StringComparison]::Ordinal)
$forsakeFearExistingBuffReturn = $forsakeFearCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$forsakeFearStateKeys = @([regex]::Matches($forsakeFearStateCleanup,
        'utils[.]removeScriptVar[(]player, "buff_handler[.]([A-Za-z0-9_]+)"[)]') |
    ForEach-Object { $_.Groups[1].Value })
$forceSensitivePlayerAction = Get-BracedBlock $combatBase `
    "public static boolean isRetiredPostNgeForceSensitivePlayerAction(obj_id self, String actionName)"
$standardCombatAction = Get-BracedBlock $combatBase `
    "public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)"
Assert-Contract ($forsakeFearEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_FORSAKE_FEAR_CHANNEL_EFFECT") -and
    $buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_FORSAKE_FEAR_CHANNEL_EFFECT = "expertise_channel_action_heal"') -and
    $forsakeFearBuffPredicate.Contains("!isPlayer(target)") -and
    $forsakeFearBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $forsakeFearBuffPredicate.Contains(
        "isRetiredPostNgePlayerForsakeFearChannelEffect(getEffectParam(data, effect))") -and
    $forsakeFearStateCleanup.Contains("!isPlayer(player)") -and
    $forsakeFearStateKeys.Count -eq
        [int]$contract.expected.retiredNgePlayerForsakeFearScriptVars -and
    @($forsakeFearStateKeys | Select-Object -Unique).Count -eq $forsakeFearStateKeys.Count -and
    $forsakeFearStateCleanup.Contains(
        "getIntObjVar(player, sui.COUNTDOWNTIMER_SUI_VAR) == forsakeFearSuiPid") -and
    $forsakeFearStateCleanup.Contains("if (ownsCountdown)") -and
    $forsakeFearStateCleanup.Contains("forceCloseSUIPage(forsakeFearSuiPid)") -and
    $forsakeFearStateCleanup.Contains("removeObjVar(player, sui.COUNTDOWNTIMER_SUI_VAR)") -and
    $forsakeFearStateCleanup.Contains(
        "utils.removeScriptVarTree(player, sui.COUNTDOWNTIMER_VAR)") -and
    $forsakeFearStateCleanup.Contains(
        "detachScript(player, sui.COUNTDOWNTIMER_PLAYER_SCRIPT)") -and
    $forsakeFearLifecycleCleanup.Contains("getAllBuffs(player)") -and
    $forsakeFearLifecycleCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $forsakeFearLifecycleCleanup.Contains("removeBuff(player, activeBuff)") -and
    $forsakeFearLifecycleCleanup.Contains(
        "clearPostNgePlayerForsakeFearChannelState(player)") -and
    $forsakeFearProgressionCleanup.Contains(
        "retirePostNgePlayerForsakeFearChannelState(player);") -and
    $forsakeFearAdmissionGate -ge 0 -and
    $forsakeFearExistingBuffReturn -gt $forsakeFearAdmissionGate -and
    $forceSensitivePlayerAction.Contains('actionName.startsWith("fs_")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeForceSensitivePlayerAction(self, actionName)") -and
    -not [bool]$contract.expected.playerNgeForsakeFearCommandExecutionReachable -and
    -not [bool]$contract.expected.playerNgeForsakeFearBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeForsakeFearStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeForsakeFearScriptVarsRemoved -and
    [bool]$contract.expected.forsakeFearCountdownCleanupOwnershipBounded -and
    -not [bool]$contract.expected.playerNgeForsakeFearActionHealReachable -and
    [bool]$contract.expected.nonPlayerNgeForsakeFearCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.forsake-fear-admission-persistence-and-command-fail-closed"

$forsakeFearHandlerExpectations = @(
    [pscustomobject]@{
        Name = "expertiseChannelActionHealAddBuffHandler"
        Guard = "if (isPlayer(self))"
        Cleanup = "buff.retirePostNgePlayerForsakeFearChannelState(self);"
        RetainedWriter = 'utils.setScriptVar(self, "buff_handler.lastForsakeFearPulse"'
    },
    [pscustomobject]@{
        Name = "expertiseChannelActionHealRemoveBuffHandler"
        Guard = "if (isPlayer(self))"
        Cleanup = "buff.clearPostNgePlayerForsakeFearChannelState(self);"
        RetainedWriter = 'utils.getIntScriptVar(self, "buff_handler.channelForsakeFearCancelled"'
    },
    [pscustomobject]@{
        Name = "channelForsakeFear"
        Guard = "if (isPlayer(player))"
        Cleanup = "buff.clearPostNgePlayerForsakeFearChannelState(player);"
        RetainedWriter = "healAttribPercent(player, ACTION"
    },
    [pscustomobject]@{
        Name = "checkChannelForsakeFear"
        Guard = "isPlayer(player)"
        Cleanup = "buff.clearPostNgePlayerForsakeFearChannelState(player);"
        RetainedWriter = "channelForsakeFear(player, buffName, false);"
    },
    [pscustomobject]@{
        Name = "channelForsakeFearCountdownHandler"
        Guard = "isPlayer(player)"
        Cleanup = "buff.clearPostNgePlayerForsakeFearChannelState(player);"
        RetainedWriter = "sui.getIntButtonPressed(params)"
    }
)
$guardedForsakeFearHandlers = 0
foreach ($handlerExpectation in $forsakeFearHandlerExpectations)
{
    $handler = Get-BracedBlock $buffHandler ("public int " + $handlerExpectation.Name + "(")
    $playerGuard = $handler.IndexOf($handlerExpectation.Guard,
        [StringComparison]::Ordinal)
    $cleanup = $handler.IndexOf($handlerExpectation.Cleanup,
        [StringComparison]::Ordinal)
    $playerReturn = $handler.IndexOf("return SCRIPT_CONTINUE;", $cleanup,
        [StringComparison]::Ordinal)
    $retainedWriter = $handler.IndexOf($handlerExpectation.RetainedWriter,
        [StringComparison]::Ordinal)
    if ($playerGuard -ge 0 -and $cleanup -gt $playerGuard -and
        $playerReturn -gt $cleanup -and $retainedWriter -gt $playerReturn)
    {
        ++$guardedForsakeFearHandlers
    }
}
Assert-Contract ($guardedForsakeFearHandlers -eq
        [int]$contract.expected.productionForsakeFearExecutionGuards) `
    "p14.combat-expertise-isolation.buff.forsake-fear-handlers-and-callbacks-player-fail-closed"

$radarInvisibilityEffect = "radar_invis"
$radarInvisibilityMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -ceq $radarInvisibilityEffect })
$radarInvisibilityBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq $radarInvisibilityEffect
    }).Count -gt 0
})
$radarInvisibilitySignatures = @($radarInvisibilityBuffRows | ForEach-Object {
    $row = $_
    @(
        [string]$row.NAME,
        [string]$row.DURATION,
        [string]$row.IS_PERSISTENT,
        [string]$row.EFFECT1_PARAM,
        [string]$row.EFFECT1_VALUE,
        [string]$row.EFFECT2_PARAM,
        [string]$row.EFFECT2_VALUE,
        [string]$row.EFFECT3_PARAM,
        [string]$row.EFFECT3_VALUE,
        [string]$row.EFFECT4_PARAM,
        [string]$row.EFFECT4_VALUE,
        [string]$row.EFFECT5_PARAM,
        [string]$row.EFFECT5_VALUE
    ) -join "|"
} | Sort-Object)
$expectedRadarInvisibilitySignatures = @(
    "battlefield_radar_invisibility|900|1|radar_invis|0||0||0||0||0",
    "bh_take_cover|40|1|expertise_glancing_blow_ranged|40|expertise_damage_all|10|radar_invis|0||0||0",
    "co_mirror_armor|120|1|radar_invis|0||0||0||0||0"
)
Assert-Contract ($radarInvisibilityMappings.Count -eq
        [int]$contract.expected.retainedNgeRadarInvisibilityEffectMappingRows -and
    [string]$radarInvisibilityMappings[0].TYPE -ceq "radarInvis" -and
    [string]$radarInvisibilityMappings[0].SUBTYPE -ceq $radarInvisibilityEffect -and
    $radarInvisibilityBuffRows.Count -eq
        [int]$contract.expected.retainedNgeRadarInvisibilityBuffRows -and
    (($radarInvisibilitySignatures -join "`n") -ceq
        ($expectedRadarInvisibilitySignatures -join "`n"))) `
    "p14.combat-expertise-isolation.buff.radar-invisibility-data-inventory-authenticated"

$radarInvisibilityEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerRadarInvisibilityEffect(String effectName)"
$radarInvisibilityBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerRadarInvisibilityBuff(obj_id target, buff_data data)"
$radarInvisibilityCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerRadarInvisibilityState(obj_id player)"
$radarInvisibilityProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$radarInvisibilityCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$radarInvisibilityAdmissionGate = $radarInvisibilityCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerRadarInvisibilityBuff(target, bdata)",
    [StringComparison]::Ordinal)
$radarInvisibilityExistingBuffReturn = $radarInvisibilityCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$radarInvisibilityOwnedRepair = $radarInvisibilityCleanup.IndexOf(
    "if (removedOwnedRadarInvisibility)", [StringComparison]::Ordinal)
$radarInvisibilityVisibilityRepair = $radarInvisibilityCleanup.IndexOf(
    "setVisibleOnMapAndRadar(player, true);", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_RADAR_INVISIBILITY_EFFECT = "radar_invis"') -and
    $radarInvisibilityEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_RADAR_INVISIBILITY_EFFECT") -and
    $radarInvisibilityBuffPredicate.Contains("!isPlayer(target)") -and
    $radarInvisibilityBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $radarInvisibilityBuffPredicate.Contains(
        "isRetiredPostNgePlayerRadarInvisibilityEffect(getEffectParam(data, effect))") -and
    $radarInvisibilityCleanup.Contains("!isPlayer(player)") -and
    $radarInvisibilityCleanup.Contains("getAllBuffs(player)") -and
    $radarInvisibilityCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $radarInvisibilityCleanup.Contains("removeBuff(player, activeBuff)") -and
    $radarInvisibilityOwnedRepair -ge 0 -and
    $radarInvisibilityVisibilityRepair -gt $radarInvisibilityOwnedRepair -and
    $radarInvisibilityProgressionCleanup.Contains(
        "retirePostNgePlayerRadarInvisibilityState(player);") -and
    $radarInvisibilityAdmissionGate -ge 0 -and
    $radarInvisibilityExistingBuffReturn -gt $radarInvisibilityAdmissionGate -and
    -not [bool]$contract.expected.playerNgeRadarInvisibilityBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeRadarInvisibilityStateRemoved -and
    [bool]$contract.expected.ownedPlayerRadarVisibilityRestored) `
    "p14.combat-expertise-isolation.buff.player-radar-invisibility-admission-persistence-and-repair-fail-closed"

$radarInvisibilityAddHandler = Get-BracedBlock $buffHandler `
    "public int radarInvisAddBuffHandler("
$radarInvisibilityRemoveHandler = Get-BracedBlock $buffHandler `
    "public int radarInvisRemoveBuffHandler("
$radarInvisibilityAddGuard = $radarInvisibilityAddHandler.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$radarInvisibilityAddRepair = $radarInvisibilityAddHandler.IndexOf(
    "setVisibleOnMapAndRadar(self, true);", [StringComparison]::Ordinal)
$radarInvisibilityAddReturn = $radarInvisibilityAddHandler.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$radarInvisibilityRetainedHide = $radarInvisibilityAddHandler.IndexOf(
    "setVisibleOnMapAndRadar(self, false);", [StringComparison]::Ordinal)
$radarInvisibilityRemoveGuard = $radarInvisibilityRemoveHandler.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$radarInvisibilityRemoveRepair = $radarInvisibilityRemoveHandler.IndexOf(
    "setVisibleOnMapAndRadar(self, true);", [StringComparison]::Ordinal)
$radarInvisibilityRemoveReturn = $radarInvisibilityRemoveHandler.IndexOf(
    "return SCRIPT_CONTINUE;", [StringComparison]::Ordinal)
$radarInvisibilityRetainedRestore = $radarInvisibilityRemoveHandler.LastIndexOf(
    "setVisibleOnMapAndRadar(self, true);", [StringComparison]::Ordinal)
Assert-Contract ($radarInvisibilityAddGuard -ge 0 -and
    $radarInvisibilityAddRepair -gt $radarInvisibilityAddGuard -and
    $radarInvisibilityAddReturn -gt $radarInvisibilityAddRepair -and
    $radarInvisibilityRetainedHide -gt $radarInvisibilityAddReturn -and
    $radarInvisibilityRemoveGuard -ge 0 -and
    $radarInvisibilityRemoveRepair -gt $radarInvisibilityRemoveGuard -and
    $radarInvisibilityRemoveReturn -gt $radarInvisibilityRemoveRepair -and
    $radarInvisibilityRetainedRestore -gt $radarInvisibilityRemoveReturn -and
    [int]$contract.expected.productionRadarInvisibilityHandlersGuarded -eq 2 -and
    [bool]$contract.expected.nonPlayerNgeRadarInvisibilityCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.radar-invisibility-handlers-player-fail-closed"

$cooldownExecutionEffect = "cooldown_execute_all"
$cooldownExecutionMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -ceq $cooldownExecutionEffect })
$cooldownExecutionBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq $cooldownExecutionEffect
    }).Count -gt 0
})
$cooldownExecutionSignatures = @($cooldownExecutionBuffRows | ForEach-Object {
    $row = $_
    @(
        [string]$row.NAME,
        [string]$row.DURATION,
        [string]$row.IS_PERSISTENT,
        [string]$row.EFFECT1_PARAM,
        [string]$row.EFFECT1_VALUE,
        [string]$row.EFFECT2_PARAM,
        [string]$row.EFFECT2_VALUE,
        [string]$row.EFFECT3_PARAM,
        [string]$row.EFFECT3_VALUE,
        [string]$row.EFFECT4_PARAM,
        [string]$row.EFFECT4_VALUE,
        [string]$row.EFFECT5_PARAM,
        [string]$row.EFFECT5_VALUE
    ) -join "|"
} | Sort-Object)
$expectedCooldownExecutionSignatures = @(
    "jedi_statue_dark_debuff_dark|30|1|cooldown_execute_all|12|expertise_damage_to_healing_fs_ae_dm_cc|100|private_armor_break|100|combat_parry_reduction|-150|expertise_block_chance|-15",
    "lelli_stun|15|1|cooldown_execute_all|15||0||0||0||0",
    "sp_fld_debuff_ca|3|1|cooldown_execute_all|3|stifle|3||0||0||0"
)
Assert-Contract ($cooldownExecutionMappings.Count -eq
        [int]$contract.expected.retainedNgeCooldownExecutionEffectMappingRows -and
    [string]$cooldownExecutionMappings[0].TYPE -ceq "cooldownModify" -and
    [string]$cooldownExecutionMappings[0].SUBTYPE -ceq $cooldownExecutionEffect -and
    $cooldownExecutionBuffRows.Count -eq
        [int]$contract.expected.retainedNgeCooldownExecutionBuffRows -and
    (($cooldownExecutionSignatures -join "`n") -ceq
        ($expectedCooldownExecutionSignatures -join "`n"))) `
    "p14.combat-expertise-isolation.buff.cooldown-execution-data-inventory-authenticated"

$cooldownExecutionEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerCooldownExecutionEffect(String effectName)"
$cooldownExecutionBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerCooldownExecutionBuff(obj_id target, buff_data data)"
$cooldownExecutionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerCooldownExecutionState(obj_id player)"
$cooldownExecutionProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$cooldownExecutionCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$cooldownExecutionAdmissionGate = $cooldownExecutionCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerCooldownExecutionBuff(target, bdata)",
    [StringComparison]::Ordinal)
$cooldownExecutionExistingBuffReturn = $cooldownExecutionCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_COOLDOWN_EXECUTION_EFFECT = "cooldown_execute_all"') -and
    $cooldownExecutionEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_COOLDOWN_EXECUTION_EFFECT") -and
    $cooldownExecutionBuffPredicate.Contains("!isPlayer(target)") -and
    $cooldownExecutionBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $cooldownExecutionBuffPredicate.Contains(
        "isRetiredPostNgePlayerCooldownExecutionEffect(getEffectParam(data, effect))") -and
    $cooldownExecutionCleanup.Contains("!isPlayer(player)") -and
    $cooldownExecutionCleanup.Contains("getAllBuffs(player)") -and
    $cooldownExecutionCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $cooldownExecutionCleanup.Contains("removeBuff(player, activeBuff)") -and
    $cooldownExecutionProgressionCleanup.Contains(
        "retirePostNgePlayerCooldownExecutionState(player);") -and
    $cooldownExecutionAdmissionGate -ge 0 -and
    $cooldownExecutionExistingBuffReturn -gt $cooldownExecutionAdmissionGate -and
    -not [bool]$contract.expected.playerNgeCooldownExecutionBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeCooldownExecutionStateRemoved) `
    "p14.combat-expertise-isolation.buff.player-cooldown-execution-admission-and-persistence-fail-closed"

$cooldownExecutionAddHandler = Get-BracedBlock $buffHandler `
    "public int cooldownModifyAddBuffHandler("
$cooldownExecutionHandlerGuard = $cooldownExecutionAddHandler.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$cooldownExecutionHandlerReturn = $cooldownExecutionAddHandler.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$cooldownExecutionRetainedSubtype = $cooldownExecutionAddHandler.IndexOf(
    'subtype.equals("cooldown_execute_all")', [StringComparison]::Ordinal)
$cooldownExecutionRetainedWriter = $cooldownExecutionAddHandler.IndexOf(
    "sendCooldownGroupTimingOnly(self, groupCrc, value);",
    [StringComparison]::Ordinal)
Assert-Contract ($cooldownExecutionHandlerGuard -ge 0 -and
    $cooldownExecutionHandlerReturn -gt $cooldownExecutionHandlerGuard -and
    $cooldownExecutionRetainedSubtype -gt $cooldownExecutionHandlerReturn -and
    $cooldownExecutionRetainedWriter -gt $cooldownExecutionRetainedSubtype -and
    [int]$contract.expected.productionCooldownExecutionHandlersGuarded -eq 1 -and
    -not [bool]$contract.expected.globalPlayerCooldownExecutionReachable -and
    [bool]$contract.expected.nonPlayerNgeCooldownExecutionCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.cooldown-execution-handler-player-fail-closed"

$saberInterceptEffect = "saber_intercept"
$saberInterceptMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -ceq $saberInterceptEffect })
$saberInterceptBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq $saberInterceptEffect
    }).Count -gt 0
})
$saberInterceptSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    $commands = ([string]$_.COMMANDS).Trim('"') -split ','
    $commands -ccontains "fs_saber_intercept_1"
})
Assert-Contract ($saberInterceptMappings.Count -eq
        [int]$contract.expected.retainedNgeSaberInterceptEffectMappingRows -and
    [string]$saberInterceptMappings[0].TYPE -ceq "saberIntercept" -and
    [string]$saberInterceptMappings[0].SUBTYPE -ceq $saberInterceptEffect -and
    $saberInterceptBuffRows.Count -eq
        [int]$contract.expected.retainedNgeSaberInterceptBuffRows -and
    [string]$saberInterceptBuffRows[0].NAME -ceq "fs_saber_intercept" -and
    [string]$saberInterceptBuffRows[0].DURATION -ceq "10" -and
    [string]$saberInterceptBuffRows[0].IS_PERSISTENT -ceq "1" -and
    [string]$saberInterceptBuffRows[0].EFFECT1_PARAM -ceq $saberInterceptEffect -and
    [string]$saberInterceptBuffRows[0].EFFECT1_VALUE -ceq "1" -and
    $saberInterceptSkillRows.Count -eq
        [int]$contract.expected.retainedNgeSaberInterceptSkillRows -and
    [string]$saberInterceptSkillRows[0].NAME -ceq "class_forcesensitive_phase3_novice") `
    "p14.combat-expertise-isolation.buff.saber-intercept-data-inventory-authenticated"

$saberInterceptEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerSaberInterceptEffect(String effectName)"
$saberInterceptBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerSaberInterceptBuff(obj_id target, buff_data data)"
$saberInterceptCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerSaberInterceptState(obj_id player)"
$saberInterceptProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$saberInterceptCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$saberInterceptAdmissionGate = $saberInterceptCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerSaberInterceptBuff(target, bdata)",
    [StringComparison]::Ordinal)
$saberInterceptExistingBuffReturn = $saberInterceptCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_SABER_INTERCEPT_EFFECT = "saber_intercept"') -and
    $saberInterceptEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_SABER_INTERCEPT_EFFECT") -and
    $saberInterceptBuffPredicate.Contains("!isPlayer(target)") -and
    $saberInterceptBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $saberInterceptBuffPredicate.Contains(
        "isRetiredPostNgePlayerSaberInterceptEffect(getEffectParam(data, effect))") -and
    $saberInterceptCleanup.Contains("!isPlayer(player)") -and
    $saberInterceptCleanup.Contains("getAllBuffs(player)") -and
    $saberInterceptCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $saberInterceptCleanup.Contains("removeBuff(player, activeBuff)") -and
    $saberInterceptProgressionCleanup.Contains(
        "retirePostNgePlayerSaberInterceptState(player);") -and
    $saberInterceptAdmissionGate -ge 0 -and
    $saberInterceptExistingBuffReturn -gt $saberInterceptAdmissionGate -and
    $forceSensitivePlayerAction.Contains('actionName.startsWith("fs_")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeForceSensitivePlayerAction(self, actionName)") -and
    -not [bool]$contract.expected.playerNgeSaberInterceptCommandExecutionReachable -and
    -not [bool]$contract.expected.playerNgeSaberInterceptBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeSaberInterceptStateRemoved) `
    "p14.combat-expertise-isolation.buff.saber-intercept-admission-persistence-and-command-fail-closed"

$saberInterceptAddHandler = Get-BracedBlock $buffHandler `
    "public int saberInterceptAddBuffHandler("
$saberInterceptRemoveHandler = Get-BracedBlock $buffHandler `
    "public int saberInterceptRemoveBuffHandler("
$saberInterceptHandlerGuard = $saberInterceptAddHandler.IndexOf(
    "if (isPlayer(self) &&", [StringComparison]::Ordinal)
$saberInterceptHandlerPredicate = $saberInterceptAddHandler.IndexOf(
    "buff.isRetiredPostNgePlayerSaberInterceptEffect(effectName)",
    [StringComparison]::Ordinal)
$saberInterceptHandlerReturn = $saberInterceptAddHandler.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$saberInterceptRetainedWriter = $saberInterceptAddHandler.IndexOf(
    "utils.setScriptVar(self, combat.DAMAGE_REDIRECT, caster);",
    [StringComparison]::Ordinal)
Assert-Contract ($saberInterceptHandlerGuard -ge 0 -and
    $saberInterceptHandlerPredicate -gt $saberInterceptHandlerGuard -and
    $saberInterceptHandlerReturn -gt $saberInterceptHandlerPredicate -and
    $saberInterceptRetainedWriter -gt $saberInterceptHandlerReturn -and
    $saberInterceptRemoveHandler.Contains(
        "utils.removeScriptVar(self, combat.DAMAGE_REDIRECT);") -and
    [int]$contract.expected.productionSaberInterceptHandlersGuarded -eq 1 -and
    -not [bool]$contract.expected.playerNgeSaberInterceptDamageRedirectReachable -and
    [bool]$contract.expected.nonPlayerNgeSaberInterceptCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.saber-intercept-handler-player-fail-closed"

$damageRedirectEffectNames = @("protect_master", "shield_master_pet", "shield_master_player")
$damageRedirectBuffNames = @("bm_shield_master_pet", "bm_shield_master_player", "bodyguard")
$damageRedirectMappings = @(Import-SwgTab -Path $paths.buffEffectMapping | Where-Object {
    $damageRedirectEffectNames -ccontains [string]$_.NAME
})
$damageRedirectMappingSignatures = @($damageRedirectMappings | ForEach-Object {
    "$($_.NAME)|$($_.TYPE)|$($_.SUBTYPE)"
} | Sort-Object)
$expectedDamageRedirectMappingSignatures = @(
    "protect_master|bodyguardDefender|protect_master",
    "shield_master_pet|bodyguardDefender|shield_master_pet",
    "shield_master_player|bodyguardMaster|shield_master_player"
) | Sort-Object
$damageRedirectBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $damageRedirectBuffNames -ccontains [string]$_.NAME
})
$damageRedirectBuffSignatures = @($damageRedirectBuffRows | ForEach-Object {
    "$($_.NAME)|$($_.DURATION)|$($_.EFFECT1_PARAM)"
} | Sort-Object)
$expectedDamageRedirectBuffSignatures = @(
    "bm_shield_master_pet|12|shield_master_pet",
    "bm_shield_master_player|12|shield_master_player",
    "bodyguard|-1|protect_master"
) | Sort-Object
Assert-Contract ($damageRedirectMappings.Count -eq
        [int]$contract.expected.retainedNgeDamageRedirectEffectMappingRows -and
    (($damageRedirectMappingSignatures -join ',') -ceq
        ($expectedDamageRedirectMappingSignatures -join ',')) -and
    $damageRedirectBuffRows.Count -eq
        [int]$contract.expected.retainedNgeDamageRedirectBuffRows -and
    (($damageRedirectBuffSignatures -join ',') -ceq
        ($expectedDamageRedirectBuffSignatures -join ','))) `
    "p14.combat-expertise-isolation.buff.damage-redirect-data-inventory-authenticated"

$damageRedirectBuffNamePredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDamageRedirectBuffName(String buffName)"
$damageRedirectEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDamageRedirectEffect(String effectName)"
$damageRedirectBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDamageRedirectBuff(obj_id target, buff_data data)"
$damageRedirectClear = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerDamageRedirectState(obj_id player)"
$damageRedirectCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerDamageRedirectState(obj_id player)"
$damageRedirectProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$damageRedirectCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$damageRedirectAdmissionGate = $damageRedirectCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerDamageRedirectBuff(target, bdata)",
    [StringComparison]::Ordinal)
$damageRedirectExistingBuffReturn = $damageRedirectCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract (([regex]::Matches($buffLibrary,
        '"bm_shield_master_pet"|"bm_shield_master_player"|"bodyguard"')).Count -eq 3 -and
    ([regex]::Matches($buffLibrary,
        '"protect_master"|"shield_master_pet"|"shield_master_player"')).Count -eq 3 -and
    $damageRedirectBuffPredicate.Contains("!isPlayer(target)") -and
    $damageRedirectBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $damageRedirectClear.Contains("utils.removeScriptVar(player, combat.DAMAGE_REDIRECT);") -and
    $damageRedirectCleanup.Contains("getAllBuffs(player)") -and
    $damageRedirectCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $damageRedirectCleanup.Contains("removeBuff(player, activeBuff)") -and
    $damageRedirectCleanup.Contains("clearPostNgePlayerDamageRedirectState(player);") -and
    $damageRedirectProgressionCleanup.Contains(
        "retirePostNgePlayerDamageRedirectState(player);") -and
    $damageRedirectAdmissionGate -ge 0 -and
    $damageRedirectExistingBuffReturn -gt $damageRedirectAdmissionGate -and
    -not [bool]$contract.expected.playerNgeDamageRedirectBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeDamageRedirectStateRemoved) `
    "p14.combat-expertise-isolation.buff.damage-redirect-admission-and-persistence-fail-closed"

$bodyguardDefenderAdd = Get-BracedBlock $buffHandler `
    "public int bodyguardDefenderAddBuffHandler("
$bodyguardDefenderRemove = Get-BracedBlock $buffHandler `
    "public int bodyguardDefenderRemoveBuffHandler("
$bodyguardMasterAdd = Get-BracedBlock $buffHandler `
    "public int bodyguardMasterAddBuffHandler("
$bodyguardMasterRemove = Get-BracedBlock $buffHandler `
    "public int bodyguardMasterRemoveBuffHandler("
$damageRedirectHandlers = @(
    $bodyguardDefenderAdd,
    $bodyguardDefenderRemove,
    $bodyguardMasterAdd,
    $bodyguardMasterRemove
)
$damageRedirectGuardedHandlers = @($damageRedirectHandlers | Where-Object {
    $_.Contains("isRetiredPostNgePlayerDamageRedirectEffect(effectName)") -and
    $_.Contains("isRetiredPostNgePlayerDamageRedirectBuffName(buffName)") -and
    $_.Contains("return SCRIPT_OVERRIDE;")
})
$damageRedirectPlayerMasterGuards =
    ([regex]::Matches($bodyguardDefenderAdd + $bodyguardDefenderRemove,
        'if \(isPlayer\(master\)\)')).Count
$damageRedirectDefenderReturn = $bodyguardDefenderAdd.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$damageRedirectDefenderWriter = $bodyguardDefenderAdd.IndexOf(
    "utils.setScriptVar(master, combat.DAMAGE_REDIRECT, self);",
    [StringComparison]::Ordinal)
Assert-Contract ($damageRedirectGuardedHandlers.Count -eq
        [int]$contract.expected.productionDamageRedirectHandlersGuarded -and
    $damageRedirectPlayerMasterGuards -eq
        [int]$contract.expected.productionDamageRedirectPlayerMasterGuards -and
    $damageRedirectDefenderReturn -ge 0 -and
    $damageRedirectDefenderWriter -gt $damageRedirectDefenderReturn -and
    $bodyguardDefenderAdd.Contains('buff.applyBuff(master, self, "bodyguard");') -and
    $bodyguardDefenderRemove.Contains('buff.removeBuff(master, "bodyguard");') -and
    [bool]$contract.expected.nonPlayerNgeDamageRedirectCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.damage-redirect-handlers-player-fail-closed"

$damageRedirectConsumer = Get-BracedBlock $combatLibrary `
    "public static obj_id directDamageToDifferentTarget(obj_id attacker, obj_id defender)"
$damageRedirectConsumerGuard = $damageRedirectConsumer.IndexOf(
    "if (isPlayer(defender))", [StringComparison]::Ordinal)
$damageRedirectConsumerCleanup = $damageRedirectConsumer.IndexOf(
    "buff.retirePostNgePlayerDamageRedirectState(defender);",
    [StringComparison]::Ordinal)
$damageRedirectConsumerReturn = $damageRedirectConsumer.IndexOf(
    "return defender;", $damageRedirectConsumerCleanup,
    [StringComparison]::Ordinal)
$damageRedirectBeastBranch = $damageRedirectConsumer.IndexOf(
    'if (buff.hasBuff(defender, "bm_shield_master_player"))',
    [StringComparison]::Ordinal)
$damageRedirectScriptVarBranch = $damageRedirectConsumer.IndexOf(
    "if (utils.hasScriptVar(defender, DAMAGE_REDIRECT))",
    [StringComparison]::Ordinal)
Assert-Contract ($damageRedirectConsumerGuard -ge 0 -and
    $damageRedirectConsumerCleanup -gt $damageRedirectConsumerGuard -and
    $damageRedirectConsumerReturn -gt $damageRedirectConsumerCleanup -and
    $damageRedirectBeastBranch -gt $damageRedirectConsumerReturn -and
    $damageRedirectScriptVarBranch -gt $damageRedirectBeastBranch -and
    -not [bool]$contract.expected.playerNgeDamageRedirectConsumerReachable) `
    "p14.combat-expertise-isolation.damage.damage-redirect-player-consumer-fail-closed"

$forceThrowCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object { [string]$_.commandName -ceq "forceThrow" })
$forceThrowCombatRows = @(Import-SwgTab -Path $paths.combatData |
    Where-Object { [string]$_.actionName -ceq "forceThrow" })
$forceThrowMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -ceq "forceThrow" })
$forceThrowBuffNames = @(
    "forceThrow",
    "fs_force_throw_1",
    "fs_force_throw_2",
    "fs_force_throw_3",
    "fs_force_throw_4",
    "fs_force_throw_root"
)
$forceThrowBuffRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object { $forceThrowBuffNames -ccontains [string]$_.NAME })
$forceThrowBuffSignatures = @($forceThrowBuffRows | ForEach-Object {
    @(
        [string]$_.NAME,
        [string]$_.GROUP1,
        [string]$_.DURATION,
        [string]$_.EFFECT1_PARAM,
        [string]$_.EFFECT1_VALUE,
        [string]$_.DEBUFF,
        [string]$_.IS_PERSISTENT
    ) -join "|"
} | Sort-Object)
$expectedForceThrowBuffSignatures = @(
    "forceThrow|forceThrowHandler|15|forceThrow|0|1|1",
    "fs_force_throw_1|forceThrowSnare|15|movement|60|1|1",
    "fs_force_throw_2|forceThrowSnare|15|movement|65|1|1",
    "fs_force_throw_3|forceThrowSnare|15|movement|70|1|1",
    "fs_force_throw_4|forceThrowSnare|15|movement|75|1|1",
    "fs_force_throw_root|forceThrowRoot|15|movement|0|1|1"
) | Sort-Object
$forceThrowNgeSkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object {
        [string]$_.NAME -ceq "class_forcesensitive_phase1_02" -or
            [string]$_.NAME -cmatch '^expertise_fs_general_improved_(?:force_throw_[12]|crippling_accuracy_[123])$'
    })
$precuForceThrowSkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object {
        [string]$_.NAME -cmatch '^(?:jedi_|force_discipline_)' -and
            (([string]$_.COMMANDS).Trim('"') -split ',' -cmatch '^forceThrow[12]$').Count -gt 0
    })
$precuForceThrowCommands = @($precuForceThrowSkillRows | ForEach-Object {
    ([string]$_.COMMANDS).Trim('"') -split ','
} | Where-Object { $_ -cmatch '^forceThrow[12]$' } | Sort-Object -Unique)
Assert-Contract ($forceThrowCommandRows.Count -eq
        [int]$contract.expected.retainedNgeForceThrowCommandRows -and
    [string]$forceThrowCommandRows[0].scriptHook -ceq "forceThrow" -and
    [string]$forceThrowCommandRows[0].displayGroup -ceq "combat" -and
    [string]$forceThrowCommandRows[0].addToCombatQueue -ceq "1" -and
    $forceThrowCombatRows.Count -eq
        [int]$contract.expected.retainedNgeForceThrowCombatRows -and
    [string]$forceThrowCombatRows[0].hitType -ceq "DELAY_ATTACK" -and
    [string]$forceThrowCombatRows[0].validTarget -ceq "STANDARD" -and
    [string]$forceThrowCombatRows[0].percentAddFromWeapon -ceq "1" -and
    $forceThrowMappings.Count -eq
        [int]$contract.expected.retainedNgeForceThrowEffectMappingRows -and
    @($forceThrowMappings | Where-Object {
        [string]$_.TYPE -ceq "forceThrow" -and
            [string]$_.SUBTYPE -ceq "forceThrow"
    }).Count -eq $forceThrowMappings.Count -and
    $forceThrowBuffRows.Count -eq
        [int]$contract.expected.retainedNgeForceThrowBuffRows -and
    (($forceThrowBuffSignatures -join "`n") -ceq
        ($expectedForceThrowBuffSignatures -join "`n")) -and
    $forceThrowNgeSkillRows.Count -eq
        [int]$contract.expected.retainedNgeForceThrowSkillRows -and
    $precuForceThrowSkillRows.Count -eq 5 -and
    $precuForceThrowCommands.Count -eq
        [int]$contract.expected.precuForceThrowCommandsPreserved -and
    ($precuForceThrowCommands -join "`n") -ceq "forceThrow1`nforceThrow2") `
    "p14.combat-expertise-isolation.buff.force-throw-data-and-precu-boundary-authenticated"

$forceThrowEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerForceThrowEffect(String effectName)"
$forceThrowNamePredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerForceThrowBuffName(String buffName)"
$forceThrowBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerForceThrowBuff(obj_id target, buff_data data)"
$forceThrowCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerForceThrowState(obj_id player)"
$forceThrowProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$forceThrowAdmission = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$forceThrowAdmissionGate = $forceThrowAdmission.IndexOf(
    "isRetiredPostNgePlayerForceThrowBuff(target, bdata)",
    [StringComparison]::Ordinal)
$forceThrowExistingBuffReturn = $forceThrowAdmission.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$forceThrowAction = Get-BracedBlock $combatActions "public int forceThrow("
$forceThrowAdd = Get-BracedBlock $buffHandler "public int forceThrowAddBuffHandler("
$movementAdd = Get-BracedBlock $buffHandler "public int movementAddBuffHandler("
$forceThrowAddGuard = $forceThrowAdd.IndexOf(
    "if (isPlayer(self) &&", [StringComparison]::Ordinal)
$forceThrowAddPredicate = $forceThrowAdd.IndexOf(
    "buff.isRetiredPostNgePlayerForceThrowEffect(effectName)",
    [StringComparison]::Ordinal)
$forceThrowAddReturn = $forceThrowAdd.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$forceThrowOwnerRead = $forceThrowAdd.IndexOf(
    'utils.getObjIdScriptVar(self, "buffOwner." + buffCrc)',
    [StringComparison]::Ordinal)
$movementAddGuard = $movementAdd.IndexOf(
    "if (isPlayer(self) &&", [StringComparison]::Ordinal)
$movementAddPredicate = $movementAdd.IndexOf(
    "buff.isRetiredPostNgePlayerForceThrowBuffName(buffName)",
    [StringComparison]::Ordinal)
$movementAddReturn = $movementAdd.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$movementAddWriter = $movementAdd.IndexOf(
    "movement.applyMovementModifier(self, effectName, value);",
    [StringComparison]::Ordinal)
Assert-Contract ($forceSensitivePlayerAction.Contains('actionName.equals("forceThrow")') -and
    -not $forceSensitivePlayerAction.Contains('actionName.startsWith("forceThrow")') -and
    $forceThrowAction.Contains('combatStandardAction("forceThrow"') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeForceSensitivePlayerAction(self, actionName)") -and
    $forceThrowEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_FORCE_THROW_EFFECT") -and
    $forceThrowNamePredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_FORCE_THROW_CONTROL_BUFF_PREFIX") -and
    $forceThrowNamePredicate.Contains("buffName.startsWith") -and
    $forceThrowBuffPredicate.Contains("!isPlayer(target)") -and
    $forceThrowBuffPredicate.Contains(
        "isRetiredPostNgePlayerForceThrowBuffName(data.buffName)") -and
    $forceThrowBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $forceThrowCleanup.Contains("!isPlayer(player)") -and
    $forceThrowCleanup.Contains("getAllBuffs(player)") -and
    $forceThrowCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $forceThrowCleanup.Contains("removeBuff(player, activeBuff)") -and
    $forceThrowProgressionCleanup.Contains(
        "retirePostNgePlayerForceThrowState(player);") -and
    $forceThrowAdmissionGate -ge 0 -and
    $forceThrowExistingBuffReturn -gt $forceThrowAdmissionGate -and
    -not [bool]$contract.expected.playerNgeForceThrowActionReachable -and
    -not [bool]$contract.expected.playerNgeForceThrowBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeForceThrowStateRemoved -and
    [bool]$contract.expected.nonPlayerNgeForceThrowCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.force-throw-action-admission-and-persistence-fail-closed"
Assert-Contract ($forceThrowAddGuard -ge 0 -and
    $forceThrowAddPredicate -gt $forceThrowAddGuard -and
    $forceThrowAddReturn -gt $forceThrowAddPredicate -and
    $forceThrowOwnerRead -gt $forceThrowAddReturn -and
    $movementAddGuard -ge 0 -and
    $movementAddPredicate -gt $movementAddGuard -and
    $movementAddReturn -gt $movementAddPredicate -and
    $movementAddWriter -gt $movementAddReturn -and
    [int]$contract.expected.productionForceThrowControlHandlersGuarded -eq 2 -and
    -not [bool]$contract.expected.playerNgeForceThrowMovementControlReachable -and
    [bool]$contract.expected.nonPlayerNgeForceThrowCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.force-throw-control-handlers-player-fail-closed"

$damageReductionModifiers = @(
    "expertise_damage_decrease_chance",
    "expertise_sm_rank_damage_bonus",
    "expertise_damage_reduce_anticipate_aggression",
    "damage_decrease_percentage",
    "area_damage_decrease_percentage",
    "area_damage_resist_full_percentage",
    "expertise_damage_decrease_percentage"
)
$damageReductionMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { $damageReductionModifiers -ccontains [string]$_.NAME })
$damageReductionMappingSignatures = @($damageReductionMappings | ForEach-Object {
    "{0}|{1}|{2}" -f [string]$_.NAME, [string]$_.TYPE, [string]$_.SUBTYPE
} | Sort-Object)
$expectedDamageReductionMappingSignatures = @(
    "damage_decrease_percentage|skill|damage_decrease_percentage",
    "expertise_damage_decrease_chance|skill|expertise_damage_decrease_chance",
    "expertise_damage_decrease_percentage|expertiseDamageDecrease|expertise_damage_decrease_percentage",
    "expertise_damage_reduce_anticipate_aggression|skill|expertise_damage_reduce_anticipate_aggression",
    "expertise_sm_rank_damage_bonus|skill|expertise_sm_rank_damage_bonus"
) | Sort-Object
$damageReductionBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        $damageReductionModifiers -ccontains [string]$row.("EFFECT$($_)_PARAM")
    }).Count -gt 0
})
$damageReductionBuffNames = @($damageReductionBuffRows |
    Select-Object -ExpandProperty NAME | Sort-Object)
$expectedDamageReductionBuffNames = @(
    "co_stand_fast",
    "fs_anticipate_aggression_1",
    "fs_anticipate_aggression_2",
    "sm_spot_a_sucker_1_6",
    "sm_spot_a_sucker_1_7",
    "sm_spot_a_sucker_2_6",
    "sm_spot_a_sucker_2_7",
    "sm_spot_a_sucker_3_6",
    "sm_spot_a_sucker_3_7",
    "sm_spot_a_sucker_4_6",
    "sm_spot_a_sucker_4_7",
    "sm_underworld_damage_1",
    "sm_underworld_damage_2",
    "sm_underworld_damage_3"
) | Sort-Object
$damageReductionSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    $skillMods = ([string]$_.SKILL_MODS).Trim('"') -split ','
    @($skillMods | Where-Object {
        $modifierName = ($_ -split '=', 2)[0]
        $damageReductionModifiers -ccontains $modifierName
    }).Count -gt 0
})
$damageReductionSkillNames = @($damageReductionSkillRows |
    Select-Object -ExpandProperty NAME | Sort-Object)
$expectedDamageReductionSkillNames = @(
    "expertise_co_blast_resistance_1",
    "expertise_co_blast_resistance_2",
    "expertise_co_blast_resistance_3",
    "expertise_co_blast_resistance_4",
    "expertise_co_deflective_armor_1",
    "expertise_co_deflective_armor_2",
    "expertise_co_deflective_armor_3",
    "expertise_co_deflective_armor_4",
    "expertise_co_imp_stand_fast_1",
    "expertise_co_imp_stand_fast_2",
    "expertise_co_imp_stand_fast_3",
    "expertise_co_stand_fast_1",
    "expertise_sm_general_idiot_proof_plan_1",
    "expertise_sm_general_idiot_proof_plan_2"
) | Sort-Object
Assert-Contract ($damageReductionMappings.Count -eq
        [int]$contract.expected.retainedNgeDamageReductionEffectMappingRows -and
    ($damageReductionMappingSignatures -join "`n") -ceq
        ($expectedDamageReductionMappingSignatures -join "`n") -and
    $damageReductionBuffRows.Count -eq
        [int]$contract.expected.retainedNgeDamageReductionBuffRows -and
    ($damageReductionBuffNames -join "`n") -ceq
        ($expectedDamageReductionBuffNames -join "`n") -and
    $damageReductionSkillRows.Count -eq
        [int]$contract.expected.retainedNgeDamageReductionSkillRows -and
    ($damageReductionSkillNames -join "`n") -ceq
        ($expectedDamageReductionSkillNames -join "`n")) `
    "p14.combat-expertise-isolation.buff.damage-reduction-data-inventory-authenticated"

$damageReductionModifierInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_DAMAGE_REDUCTION_MODIFIERS"
$damageReductionInventoryNames = @([regex]::Matches(
    $damageReductionModifierInventory, '"([^"]+)"') | ForEach-Object {
        $_.Groups[1].Value
    } | Sort-Object)
$damageReductionModifierPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDamageReductionModifier(String modifierName)"
$damageReductionBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDamageReductionBuff(obj_id target, buff_data data)"
$damageReductionStateClear = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerDamageReductionState(obj_id player)"
$damageReductionStateRetire = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerDamageReductionState(obj_id player)"
$damageReductionProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$damageReductionAdmission = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$damageReductionAdmissionGate = $damageReductionAdmission.IndexOf(
    "isRetiredPostNgePlayerDamageReductionBuff(target, bdata)",
    [StringComparison]::Ordinal)
$damageReductionGenericModifierGate = $damageReductionAdmission.IndexOf(
    "isRetiredPostNgePlayerModifierBuff(target, bdata)",
    [StringComparison]::Ordinal)
$damageReductionExistingBuffReturn = $damageReductionAdmission.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($damageReductionInventoryNames.Count -eq
        [int]$contract.expected.retiredNgePlayerDamageReductionModifiers -and
    ($damageReductionInventoryNames -join "`n") -ceq
        (($damageReductionModifiers | Sort-Object) -join "`n") -and
    $damageReductionModifierPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_DAMAGE_REDUCTION_MODIFIERS") -and
    $damageReductionModifierPredicate.Contains("modifierName.equals(retiredModifier)") -and
    $damageReductionBuffPredicate.Contains("!isPlayer(target)") -and
    $damageReductionBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $damageReductionBuffPredicate.Contains(
        "isRetiredPostNgePlayerDamageReductionModifier(getEffectParam(data, effect))") -and
    $damageReductionAdmissionGate -ge 0 -and
    $damageReductionGenericModifierGate -gt $damageReductionAdmissionGate -and
    $damageReductionExistingBuffReturn -gt $damageReductionGenericModifierGate -and
    -not [bool]$contract.expected.playerNgeDamageReductionBuffAdmissionReachable -and
    [bool]$contract.expected.nonPlayerNgeDamageReductionCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.damage-reduction-admission-player-fail-closed"
Assert-Contract ($damageReductionStateClear.Contains("!isPlayer(player)") -and
    $damageReductionStateClear.Contains("hasSkillModModifier(player, retiredModifier)") -and
    $damageReductionStateClear.Contains("removeAttribOrSkillModModifier(player, retiredModifier)") -and
    $damageReductionStateClear.Contains('retiredModifier + "_" + effect') -and
    $damageReductionStateClear.Contains("getSkillStatMod(player, retiredModifier)") -and
    $damageReductionStateClear.Contains(
        "applySkillStatisticModifier(player, retiredModifier, -currentValue)") -and
    $damageReductionStateClear.Contains('"junkDealerDamageDecrease"') -and
    $damageReductionStateRetire.Contains("getAllBuffs(player)") -and
    $damageReductionStateRetire.Contains("combat_engine.getBuffData(activeBuff)") -and
    $damageReductionStateRetire.Contains(
        "isRetiredPostNgePlayerDamageReductionBuff(player, data)") -and
    $damageReductionStateRetire.Contains("removeBuff(player, activeBuff)") -and
    $damageReductionStateRetire.Contains("clearPostNgePlayerDamageReductionState(player)") -and
    $damageReductionProgressionCleanup.Contains(
        "retirePostNgePlayerDamageReductionState(player);") -and
    [bool]$contract.expected.persistedPlayerNgeDamageReductionStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeDamageReductionModifiersRemoved) `
    "p14.combat-expertise-isolation.buff.damage-reduction-persistence-and-stale-state-retired"

$damageReductionAdd = Get-BracedBlock $buffHandler `
    "public int expertiseDamageDecreaseAddBuffHandler("
$damageReductionRemove = Get-BracedBlock $buffHandler `
    "public int expertiseDamageDecreaseRemoveBuffHandler("
$damageReductionAddGuard = $damageReductionAdd.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$damageReductionAddCleanup = $damageReductionAdd.IndexOf(
    "buff.retirePostNgePlayerDamageReductionState(self);", [StringComparison]::Ordinal)
$damageReductionAddReturn = $damageReductionAdd.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$damageReductionAddRead = $damageReductionAdd.IndexOf(
    'getSkillStatisticModifier(self, "expertise_damage_decrease_percentage")',
    [StringComparison]::Ordinal)
$damageReductionRemoveGuard = $damageReductionRemove.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$damageReductionRemoveCleanup = $damageReductionRemove.IndexOf(
    "buff.clearPostNgePlayerDamageReductionState(self);", [StringComparison]::Ordinal)
$damageReductionRemoveReturn = $damageReductionRemove.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$damageReductionRemoveTruncation = $damageReductionRemove.IndexOf(
    'effectName.lastIndexOf("_")', [StringComparison]::Ordinal)
$damageReductionRemoveRead = $damageReductionRemove.IndexOf(
    'getSkillStatisticModifier(self, "expertise_damage_decrease_percentage")',
    [StringComparison]::Ordinal)
Assert-Contract ($damageReductionAddGuard -ge 0 -and
    $damageReductionAddCleanup -gt $damageReductionAddGuard -and
    $damageReductionAddReturn -gt $damageReductionAddCleanup -and
    $damageReductionAddRead -gt $damageReductionAddReturn -and
    $damageReductionRemoveGuard -ge 0 -and
    $damageReductionRemoveCleanup -gt $damageReductionRemoveGuard -and
    $damageReductionRemoveReturn -gt $damageReductionRemoveCleanup -and
    $damageReductionRemoveTruncation -gt $damageReductionRemoveReturn -and
    $damageReductionRemoveRead -gt $damageReductionRemoveTruncation -and
    [int]$contract.expected.productionDamageReductionHandlersGuarded -eq 2 -and
    [bool]$contract.expected.nonPlayerNgeDamageReductionCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.damage-reduction-handlers-player-fail-closed"

$damageReductionAttackerGuard = $expertiseDamageModify.IndexOf(
    "if (isPlayer(attacker))", [StringComparison]::Ordinal)
$damageReductionAttackerCleanup = $expertiseDamageModify.IndexOf(
    "buff.clearPostNgePlayerDamageReductionState(attacker);", [StringComparison]::Ordinal)
$damageReductionDefenderGuard = $expertiseDamageModify.IndexOf(
    "if (isPlayer(defender) && defender != attacker)", [StringComparison]::Ordinal)
$damageReductionDefenderCleanup = $expertiseDamageModify.IndexOf(
    "buff.clearPostNgePlayerDamageReductionState(defender);", [StringComparison]::Ordinal)
$damageReductionFirstAttackerRead = $expertiseDamageModify.IndexOf(
    'getSkillStatisticModifier(attacker, "expertise_damage_decrease_chance")',
    [StringComparison]::Ordinal)
$damageReductionFirstDefenderRead = $expertiseDamageModify.IndexOf(
    'getSkillStatisticModifier(defender, "expertise_damage_reduce_anticipate_aggression")',
    [StringComparison]::Ordinal)
$damageReductionCombatReadNames = @([regex]::Matches(
    $expertiseDamageModify,
    'getSkillStatisticModifier\((?:attacker|defender),\s*"([^"]+)"\)') |
    ForEach-Object { $_.Groups[1].Value } | Where-Object {
        $damageReductionModifiers -ccontains $_
    })
Assert-Contract ($damageReductionAttackerGuard -ge 0 -and
    $damageReductionAttackerCleanup -gt $damageReductionAttackerGuard -and
    $damageReductionDefenderGuard -gt $damageReductionAttackerCleanup -and
    $damageReductionDefenderCleanup -gt $damageReductionDefenderGuard -and
    $damageReductionFirstAttackerRead -gt $damageReductionDefenderCleanup -and
    $damageReductionFirstDefenderRead -gt $damageReductionFirstAttackerRead -and
    $damageReductionCombatReadNames.Count -eq 6 -and
    @($damageReductionCombatReadNames | Sort-Object -Unique).Count -eq 6 -and
    -not [bool]$contract.expected.playerNgeDamageReductionCombatReadsReachable -and
    [bool]$contract.expected.nonPlayerNgeDamageReductionCompatibilityPreserved) `
    "p14.combat-expertise-isolation.damage.damage-reduction-player-reads-cleared-before-consumption"

$pistolWhipControlEffect = "sm_pistol_whip"
$pistolWhipControlMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -ceq $pistolWhipControlEffect })
$pistolWhipControlBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        [string]$row.("EFFECT$($_)_PARAM") -ceq $pistolWhipControlEffect
    }).Count -gt 0
})
$pistolWhipControlSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    $commands = ([string]$_.COMMANDS).Trim('"') -split ','
    $skillMods = ([string]$_.SKILL_MODS).Trim('"') -split ','
    $commands -ccontains "sm_pistol_whip_1" -or
        @($skillMods | Where-Object {
            $_ -match '^expertise_(stun|buff_duration)_line_sm_pistol_whip='
        }).Count -gt 0
})
$precuPistolMeleeDefenseSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    $commands = ([string]$_.COMMANDS).Trim('"') -split ','
    $commands -ccontains "pistolMeleeDefense1" -or
        $commands -ccontains "pistolMeleeDefense2"
})
Assert-Contract ($pistolWhipControlMappings.Count -eq
        [int]$contract.expected.retainedNgePistolWhipControlEffectMappingRows -and
    [string]$pistolWhipControlMappings[0].TYPE -ceq "pistolWhip" -and
    [string]$pistolWhipControlMappings[0].SUBTYPE -ceq $pistolWhipControlEffect -and
    $pistolWhipControlBuffRows.Count -eq
        [int]$contract.expected.retainedNgePistolWhipControlBuffRows -and
    [string]$pistolWhipControlBuffRows[0].NAME -ceq "sm_pistol_whip" -and
    [string]$pistolWhipControlBuffRows[0].DURATION -ceq "2" -and
    [string]$pistolWhipControlBuffRows[0].DEBUFF -ceq "1" -and
    [string]$pistolWhipControlBuffRows[0].IS_PERSISTENT -ceq "1" -and
    $pistolWhipControlSkillRows.Count -eq
        [int]$contract.expected.retainedNgePistolWhipControlSkillRows -and
    $precuPistolMeleeDefenseSkillRows.Count -eq
        [int]$contract.expected.retainedPrecuPistolMeleeDefenseSkillRows -and
    @($precuPistolMeleeDefenseSkillRows | Select-Object -ExpandProperty NAME) -contains
        "combat_pistol_support_01" -and
    @($precuPistolMeleeDefenseSkillRows | Select-Object -ExpandProperty NAME) -contains
        "combat_pistol_support_03" -and
    [bool]$contract.expected.precuPistolMeleeDefensePreserved) `
    "p14.combat-expertise-isolation.buff.pistol-whip-control-data-and-precu-boundary-authenticated"

$pistolWhipControlEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerPistolWhipControlEffect(String effectName)"
$pistolWhipControlBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerPistolWhipControlBuff(obj_id target, buff_data data)"
$pistolWhipControlCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerPistolWhipControlState(obj_id player)"
$pistolWhipControlProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$pistolWhipControlCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$pistolWhipControlAdmissionGate = $pistolWhipControlCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerPistolWhipControlBuff(target, bdata)",
    [StringComparison]::Ordinal)
$pistolWhipControlExistingBuffReturn = $pistolWhipControlCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$smugglerPlayerAction = Get-BracedBlock $combatBase `
    "public static boolean isRetiredPostNgeSmugglerPlayerAction(obj_id self, String actionName)"
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_PISTOL_WHIP_CONTROL_EFFECT = "sm_pistol_whip"') -and
    $pistolWhipControlEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_PISTOL_WHIP_CONTROL_EFFECT") -and
    $pistolWhipControlBuffPredicate.Contains("!isPlayer(target)") -and
    $pistolWhipControlBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $pistolWhipControlBuffPredicate.Contains(
        "isRetiredPostNgePlayerPistolWhipControlEffect(getEffectParam(data, effect))") -and
    $pistolWhipControlCleanup.Contains("!isPlayer(player)") -and
    $pistolWhipControlCleanup.Contains("getAllBuffs(player)") -and
    $pistolWhipControlCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $pistolWhipControlCleanup.Contains("removeBuff(player, activeBuff)") -and
    $pistolWhipControlProgressionCleanup.Contains(
        "retirePostNgePlayerPistolWhipControlState(player);") -and
    $pistolWhipControlAdmissionGate -ge 0 -and
    $pistolWhipControlExistingBuffReturn -gt $pistolWhipControlAdmissionGate -and
    $smugglerPlayerAction.Contains('actionName.startsWith("sm_")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeSmugglerPlayerAction(self, actionName)") -and
    -not [bool]$contract.expected.playerNgePistolWhipCommandExecutionReachable -and
    -not [bool]$contract.expected.playerNgePistolWhipBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgePistolWhipStateRemoved) `
    "p14.combat-expertise-isolation.buff.pistol-whip-control-admission-persistence-and-command-fail-closed"

$pistolWhipControlAddHandler = Get-BracedBlock $buffHandler `
    "public int pistolWhipAddBuffHandler("
$pistolWhipControlRemoveHandler = Get-BracedBlock $buffHandler `
    "public int pistolWhipRemoveBuffHandler("
$pistolWhipControlHandlerGuard = $pistolWhipControlAddHandler.IndexOf(
    "if (isPlayer(self) &&", [StringComparison]::Ordinal)
$pistolWhipControlHandlerPredicate = $pistolWhipControlAddHandler.IndexOf(
    "buff.isRetiredPostNgePlayerPistolWhipControlEffect(effectName)",
    [StringComparison]::Ordinal)
$pistolWhipControlHandlerReturn = $pistolWhipControlAddHandler.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$pistolWhipControlExpertiseRead = $pistolWhipControlAddHandler.IndexOf(
    'getSkillStatisticModifier(caster, "expertise_stun_line_sm_pistol_whip")',
    [StringComparison]::Ordinal)
$pistolWhipControlRetainedWriter = $pistolWhipControlAddHandler.IndexOf(
    "movementAddBuffHandler(self, effectName, subtype, duration, value, buffName, caster);",
    [StringComparison]::Ordinal)
Assert-Contract ($pistolWhipControlHandlerGuard -ge 0 -and
    $pistolWhipControlHandlerPredicate -gt $pistolWhipControlHandlerGuard -and
    $pistolWhipControlHandlerReturn -gt $pistolWhipControlHandlerPredicate -and
    $pistolWhipControlExpertiseRead -gt $pistolWhipControlHandlerReturn -and
    $pistolWhipControlRetainedWriter -gt $pistolWhipControlExpertiseRead -and
    $pistolWhipControlRemoveHandler.Contains(
        "movementRemoveBuffHandler(self, effectName, subtype, duration, value, buffName, caster);") -and
    [int]$contract.expected.productionPistolWhipControlHandlersGuarded -eq 1 -and
    -not [bool]$contract.expected.playerNgePistolWhipMovementControlReachable -and
    [bool]$contract.expected.nonPlayerNgePistolWhipCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.pistol-whip-control-handler-player-fail-closed"

$smugglerTrickEffects = @("expertise_sly_lie", "expertise_fast_talk")
$smugglerTrickMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { $smugglerTrickEffects -ccontains [string]$_.NAME })
$smugglerTrickBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | Where-Object {
        $smugglerTrickEffects -ccontains [string]$row.("EFFECT$($_)_PARAM")
    }).Count -gt 0
})
$smugglerTrickSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    $commands = ([string]$_.COMMANDS).Trim('"') -split ','
    $skillMods = ([string]$_.SKILL_MODS).Trim('"') -split ','
    $commands -ccontains "sm_sly_lie" -or
        $commands -ccontains "sm_fast_talk" -or
        @($skillMods | Where-Object {
            $_ -match '^expertise_(half_truth|innocent_cargo|fake_id|sly_lie_(bonus|rank)|fast_talk_(bonus|rank))='
        }).Count -gt 0
})
$precuSmugglerCommands = @(
    "slice_containers",
    "slice_terminals",
    "slice_weaponsbasic",
    "slice_armor",
    "slice_weaponsadvanced",
    "feignDeath",
    "panicShot",
    "lowBlow",
    "lastDitch"
)
$precuSmugglerSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    $commands = ([string]$_.COMMANDS).Trim('"') -split ','
    @($precuSmugglerCommands | Where-Object { $commands -ccontains $_ }).Count -gt 0
})
$slyLieMapping = @($smugglerTrickMappings | Where-Object {
    [string]$_.NAME -ceq "expertise_sly_lie"
})
$fastTalkMapping = @($smugglerTrickMappings | Where-Object {
    [string]$_.NAME -ceq "expertise_fast_talk"
})
Assert-Contract ($smugglerTrickMappings.Count -eq
        [int]$contract.expected.retainedNgeSmugglerTrickEffectMappingRows -and
    $slyLieMapping.Count -eq 1 -and
    [string]$slyLieMapping[0].TYPE -ceq "slyLie" -and
    [string]$slyLieMapping[0].SUBTYPE -ceq "expertise_sly_lie" -and
    $fastTalkMapping.Count -eq 1 -and
    [string]$fastTalkMapping[0].TYPE -ceq "fastTalk" -and
    [string]$fastTalkMapping[0].SUBTYPE -ceq "expertise_fast_talk" -and
    $smugglerTrickBuffRows.Count -eq
        [int]$contract.expected.retainedNgeSmugglerTrickBuffRows -and
    @($smugglerTrickBuffRows | Select-Object -ExpandProperty NAME) -contains
        "sm_sly_lie" -and
    @($smugglerTrickBuffRows | Select-Object -ExpandProperty NAME) -contains
        "sm_fast_talk" -and
    @($smugglerTrickBuffRows | Where-Object {
        [string]$_.DURATION -ceq "600" -and [string]$_.IS_PERSISTENT -ceq "1"
    }).Count -eq 2 -and
    $smugglerTrickSkillRows.Count -eq
        [int]$contract.expected.retainedNgeSmugglerTrickSkillRows -and
    @($smugglerTrickSkillRows | Select-Object -ExpandProperty NAME) -contains
        "class_smuggler_phase1_04" -and
    @($smugglerTrickSkillRows | Select-Object -ExpandProperty NAME) -contains
        "class_smuggler_phase1_master" -and
    $precuSmugglerSkillRows.Count -eq
        [int]$contract.expected.retainedPrecuSmugglerSkillRows -and
    [bool]$contract.expected.precuSmugglerCommandsPreserved) `
    "p14.combat-expertise-isolation.buff.smuggler-trick-data-and-precu-boundary-authenticated"

$smugglerTrickEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerSmugglerTrickEffect(String effectName)"
$smugglerTrickBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerSmugglerTrickBuff(obj_id target, buff_data data)"
$smugglerTrickModifierCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerSmugglerTrickModifiers(obj_id player)"
$smugglerTrickStateCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerSmugglerTrickState(obj_id player)"
$smugglerTrickProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$smugglerTrickCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$smugglerTrickAdmissionGate = $smugglerTrickCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerSmugglerTrickBuff(target, bdata)",
    [StringComparison]::Ordinal)
$smugglerTrickExistingBuffReturn = $smugglerTrickCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        "RETIRED_POST_NGE_PLAYER_SMUGGLER_TRICK_EFFECTS") -and
    $buffLibrary.Contains('"expertise_sly_lie"') -and
    $buffLibrary.Contains('"expertise_fast_talk"') -and
    $smugglerTrickEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_SMUGGLER_TRICK_EFFECTS") -and
    $smugglerTrickBuffPredicate.Contains("!isPlayer(target)") -and
    $smugglerTrickBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $smugglerTrickBuffPredicate.Contains(
        "isRetiredPostNgePlayerSmugglerTrickEffect(getEffectParam(data, effect))") -and
    $smugglerTrickModifierCleanup.Contains('"slyLieDodge"') -and
    $smugglerTrickModifierCleanup.Contains('"innocentCargoStrikethrough"') -and
    $smugglerTrickModifierCleanup.Contains('"fastTalkAgility"') -and
    $smugglerTrickModifierCleanup.Contains("removeAttribOrSkillModModifier") -and
    $smugglerTrickStateCleanup.Contains("!isPlayer(player)") -and
    $smugglerTrickStateCleanup.Contains("getAllBuffs(player)") -and
    $smugglerTrickStateCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $smugglerTrickStateCleanup.Contains("removeBuff(player, activeBuff)") -and
    $smugglerTrickStateCleanup.Contains(
        "clearPostNgePlayerSmugglerTrickModifiers(player);") -and
    $smugglerTrickProgressionCleanup.Contains(
        "retirePostNgePlayerSmugglerTrickState(player);") -and
    $smugglerTrickAdmissionGate -ge 0 -and
    $smugglerTrickExistingBuffReturn -gt $smugglerTrickAdmissionGate -and
    $smugglerPlayerAction.Contains('actionName.startsWith("sm_")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeSmugglerPlayerAction(self, actionName)") -and
    -not [bool]$contract.expected.playerNgeSmugglerTrickCommandExecutionReachable -and
    -not [bool]$contract.expected.playerNgeSmugglerTrickBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeSmugglerTrickStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeSmugglerTrickModifiersRemoved) `
    "p14.combat-expertise-isolation.buff.smuggler-trick-admission-persistence-and-command-fail-closed"

$slyLieAddHandler = Get-BracedBlock $buffHandler "public int slyLieAddBuffHandler("
$slyLieRemoveHandler = Get-BracedBlock $buffHandler "public int slyLieRemoveBuffHandler("
$fastTalkAddHandler = Get-BracedBlock $buffHandler "public int fastTalkAddBuffHandler("
$fastTalkRemoveHandler = Get-BracedBlock $buffHandler "public int fastTalkRemoveBuffHandler("
$slyLieGuard = $slyLieAddHandler.IndexOf("if (isPlayer(self) &&", [StringComparison]::Ordinal)
$slyLiePredicate = $slyLieAddHandler.IndexOf(
    "buff.isRetiredPostNgePlayerSmugglerTrickEffect(effectName)", [StringComparison]::Ordinal)
$slyLieCleanup = $slyLieAddHandler.IndexOf(
    "buff.clearPostNgePlayerSmugglerTrickModifiers(self);", [StringComparison]::Ordinal)
$slyLieReturn = $slyLieAddHandler.IndexOf("return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$slyLieDodgeRead = $slyLieAddHandler.IndexOf(
    'getSkillStatisticModifier(self, "expertise_half_truth")', [StringComparison]::Ordinal)
$slyLieDodgeWrite = $slyLieAddHandler.IndexOf(
    'skillAddBuffHandler(self, "slyLieDodge", "combat_dodge"', [StringComparison]::Ordinal)
$slyLieStrikeRead = $slyLieAddHandler.IndexOf(
    'getSkillStatisticModifier(self, "expertise_innocent_cargo")', [StringComparison]::Ordinal)
$slyLieStrikeWrite = $slyLieAddHandler.IndexOf(
    'skillAddBuffHandler(self, "innocentCargoStrikethrough", "combat_strikethrough_chance"',
    [StringComparison]::Ordinal)
$fastTalkGuard = $fastTalkAddHandler.IndexOf("if (isPlayer(self) &&", [StringComparison]::Ordinal)
$fastTalkPredicate = $fastTalkAddHandler.IndexOf(
    "buff.isRetiredPostNgePlayerSmugglerTrickEffect(effectName)", [StringComparison]::Ordinal)
$fastTalkCleanup = $fastTalkAddHandler.IndexOf(
    "buff.clearPostNgePlayerSmugglerTrickModifiers(self);", [StringComparison]::Ordinal)
$fastTalkReturn = $fastTalkAddHandler.IndexOf("return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$fastTalkExpertiseRead = $fastTalkAddHandler.IndexOf(
    'getSkillStatisticModifier(self, "expertise_fake_id")', [StringComparison]::Ordinal)
$fastTalkWriter = $fastTalkAddHandler.IndexOf(
    'skillAddBuffHandler(self, "fastTalkAgility", "agility_modified"', [StringComparison]::Ordinal)
Assert-Contract ($slyLieGuard -ge 0 -and
    $slyLiePredicate -gt $slyLieGuard -and
    $slyLieCleanup -gt $slyLiePredicate -and
    $slyLieReturn -gt $slyLieCleanup -and
    $slyLieDodgeRead -gt $slyLieReturn -and
    $slyLieDodgeWrite -gt $slyLieDodgeRead -and
    $slyLieStrikeRead -gt $slyLieDodgeWrite -and
    $slyLieStrikeWrite -gt $slyLieStrikeRead -and
    $fastTalkGuard -ge 0 -and
    $fastTalkPredicate -gt $fastTalkGuard -and
    $fastTalkCleanup -gt $fastTalkPredicate -and
    $fastTalkReturn -gt $fastTalkCleanup -and
    $fastTalkExpertiseRead -gt $fastTalkReturn -and
    $fastTalkWriter -gt $fastTalkExpertiseRead -and
    $slyLieRemoveHandler.Contains('removeAttribOrSkillModModifier(self, "slyLieDodge")') -and
    $slyLieRemoveHandler.Contains(
        'removeAttribOrSkillModModifier(self, "innocentCargoStrikethrough")') -and
    $fastTalkRemoveHandler.Contains(
        'removeAttribOrSkillModModifier(self, "fastTalkAgility")') -and
    [int]$contract.expected.productionSmugglerTrickHandlersGuarded -eq 2 -and
    -not [bool]$contract.expected.playerNgeSmugglerTrickModifierWritesReachable -and
    [bool]$contract.expected.nonPlayerNgeSmugglerTrickCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.smuggler-trick-handlers-player-fail-closed"

$aggroChannelMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.TYPE -ceq "aggroChannel" })
$aggroChannelEffectNames = @($aggroChannelMappings |
    Select-Object -ExpandProperty NAME)
$aggroChannelBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $effectParameters = @($_.EFFECT1_PARAM, $_.EFFECT2_PARAM, $_.EFFECT3_PARAM,
        $_.EFFECT4_PARAM, $_.EFFECT5_PARAM)
    @($effectParameters | Where-Object {
        $aggroChannelEffectNames -ccontains [string]$_
    }).Count -gt 0
})
$aggroChannelSkillRows = @(Import-SwgTab -Path $paths.skillsTable | Where-Object {
    [string]$_.NAME -cmatch '^expertise_of_aggro_channel_[123]$'
})
$aggroChannelCommandOwners = @($aggroChannelSkillRows | Where-Object {
    @(([string]$_.COMMANDS).Trim('"') -split ',') -ccontains "of_aggro_channel"
})
Assert-Contract ($aggroChannelMappings.Count -eq
        [int]$contract.expected.retainedNgeAggroChannelEffectMappingRows -and
    $aggroChannelEffectNames -ccontains "aggro_channel_self" -and
    $aggroChannelEffectNames -ccontains "aggro_channel_target" -and
    @($aggroChannelMappings | Where-Object {
        [string]$_.NAME -ceq "aggro_channel_self" -and
        [string]$_.SUBTYPE -ceq "self"
    }).Count -eq 1 -and
    @($aggroChannelMappings | Where-Object {
        [string]$_.NAME -ceq "aggro_channel_target" -and
        [string]$_.SUBTYPE -ceq "target"
    }).Count -eq 1 -and
    $aggroChannelBuffRows.Count -eq
        [int]$contract.expected.retainedNgeAggroChannelBuffRows -and
    @($aggroChannelBuffRows | Select-Object -ExpandProperty NAME) -ccontains
        "aggroChannelTarget" -and
    @($aggroChannelBuffRows | Select-Object -ExpandProperty NAME) -ccontains
        "aggroChannelself" -and
    @($aggroChannelBuffRows | Where-Object {
        [string]$_.DURATION -ceq "-1" -and
        [string]$_.IS_PERSISTENT -ceq "1" -and
        [string]$_.GROUP1 -ceq "of_aggro_channel"
    }).Count -eq 2 -and
    $aggroChannelSkillRows.Count -eq
        [int]$contract.expected.retainedNgeAggroChannelExpertiseSkillRows -and
    $aggroChannelCommandOwners.Count -eq 1 -and
    @($aggroChannelSkillRows | Where-Object {
        [string]$_.SKILL_MODS -match 'expertise_aggro_channel='
    }).Count -eq 3) `
    "p14.combat-expertise-isolation.buff.aggro-channel-data-and-expertise-ownership-authenticated"

$aggroChannelEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerAggroChannelEffect(String effectName)"
$aggroChannelBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerAggroChannelBuff(obj_id target, buff_data data)"
$aggroChannelStateCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerAggroChannelState(obj_id player)"
$aggroChannelProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$aggroChannelCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$aggroChannelAdmissionGate = $aggroChannelCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerAggroChannelBuff(target, bdata)",
    [StringComparison]::Ordinal)
$aggroChannelExistingBuffReturn = $aggroChannelCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$officerPlayerAction = Get-BracedBlock $combatBase `
    "public static boolean isRetiredPostNgeOfficerPlayerAction(obj_id self, String actionName)"
Assert-Contract ($buffLibrary.Contains(
        "RETIRED_POST_NGE_PLAYER_AGGRO_CHANNEL_EFFECTS") -and
    $buffLibrary.Contains('"aggro_channel_self"') -and
    $buffLibrary.Contains('"aggro_channel_target"') -and
    $aggroChannelEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_AGGRO_CHANNEL_EFFECTS") -and
    $aggroChannelBuffPredicate.Contains("!isPlayer(target)") -and
    $aggroChannelBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $aggroChannelBuffPredicate.Contains(
        "isRetiredPostNgePlayerAggroChannelEffect(getEffectParam(data, effect))") -and
    $aggroChannelStateCleanup.Contains("!isPlayer(player)") -and
    $aggroChannelStateCleanup.Contains("getAllBuffs(player)") -and
    $aggroChannelStateCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $aggroChannelStateCleanup.Contains("removeBuff(player, activeBuff)") -and
    $aggroChannelStateCleanup.Contains(
        "utils.removeScriptVar(player, AGGRO_TRANSFER_TO);") -and
    $aggroChannelProgressionCleanup.Contains(
        "retirePostNgePlayerAggroChannelState(player);") -and
    $aggroChannelAdmissionGate -ge 0 -and
    $aggroChannelExistingBuffReturn -gt $aggroChannelAdmissionGate -and
    $officerPlayerAction.Contains('actionName.startsWith("of_")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeOfficerPlayerAction(self, actionName)") -and
    -not [bool]$contract.expected.playerNgeAggroChannelCommandExecutionReachable -and
    -not [bool]$contract.expected.playerNgeAggroChannelBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeAggroChannelStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeAggroChannelScriptVarRemoved) `
    "p14.combat-expertise-isolation.buff.aggro-channel-admission-persistence-and-command-fail-closed"

$aggroChannelAddHandler = Get-BracedBlock $buffHandler `
    "public int aggroChannelAddBuffHandler("
$aggroChannelRemoveHandler = Get-BracedBlock $buffHandler `
    "public int aggroChannelRemoveBuffHandler("
$aggroChannelGuard = $aggroChannelAddHandler.IndexOf(
    "if (isPlayer(self) &&", [StringComparison]::Ordinal)
$aggroChannelPredicate = $aggroChannelAddHandler.IndexOf(
    "buff.isRetiredPostNgePlayerAggroChannelEffect(effectName)",
    [StringComparison]::Ordinal)
$aggroChannelCleanup = $aggroChannelAddHandler.IndexOf(
    "buff.retirePostNgePlayerAggroChannelState(self);",
    [StringComparison]::Ordinal)
$aggroChannelReturn = $aggroChannelAddHandler.IndexOf(
    "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
$aggroChannelCasterCheck = $aggroChannelAddHandler.IndexOf(
    "if (!exists(caster) || !isIdValid(caster))", [StringComparison]::Ordinal)
$aggroChannelCounterpartWrite = $aggroChannelAddHandler.IndexOf(
    'buff.applyBuff(caster, self, "aggroChannelself");',
    [StringComparison]::Ordinal)
$aggroChannelScriptVarWrite = $aggroChannelAddHandler.IndexOf(
    "utils.setScriptVar(self, buff.AGGRO_TRANSFER_TO, caster);",
    [StringComparison]::Ordinal)
$aggroChannelHateConsumer = Get-BracedBlock $combatLibrary `
    "public static void addHateProcess(obj_id attacker, obj_id defender, hit_result hitData, combat_data actionData)"
$aggroChannelConsumerCleanup = $aggroChannelHateConsumer.IndexOf(
    "buff.retirePostNgePlayerAggroChannelState(attacker);",
    [StringComparison]::Ordinal)
$aggroChannelConsumerExpertiseRead = $aggroChannelHateConsumer.IndexOf(
    'getEnhancedSkillStatisticModifier(attacker, "expertise_aggro_channel")',
    [StringComparison]::Ordinal)
$aggroChannelConsumerTransfer = $aggroChannelHateConsumer.IndexOf(
    "addHate(defender, transferTo, hateTransfered);",
    [StringComparison]::Ordinal)
Assert-Contract ($aggroChannelGuard -ge 0 -and
    $aggroChannelPredicate -gt $aggroChannelGuard -and
    $aggroChannelCleanup -gt $aggroChannelPredicate -and
    $aggroChannelReturn -gt $aggroChannelCleanup -and
    $aggroChannelCasterCheck -gt $aggroChannelReturn -and
    $aggroChannelCounterpartWrite -gt $aggroChannelCasterCheck -and
    $aggroChannelScriptVarWrite -gt $aggroChannelCounterpartWrite -and
    $aggroChannelRemoveHandler.Contains(
        'buff.removeBuff(caster, "aggroChannelself")') -and
    $aggroChannelRemoveHandler.Contains(
        'buff.removeBuff(buffed, "aggroChannelTarget")') -and
    $aggroChannelRemoveHandler.Contains(
        "utils.removeScriptVar(self, buff.AGGRO_TRANSFER_TO)") -and
    $aggroChannelHateConsumer.Contains("if (isPlayer(attacker) &&") -and
    $aggroChannelHateConsumer.Contains(
        "utils.hasScriptVar(attacker, buff.AGGRO_TRANSFER_TO)") -and
    $aggroChannelConsumerCleanup -ge 0 -and
    $aggroChannelConsumerExpertiseRead -gt $aggroChannelConsumerCleanup -and
    $aggroChannelConsumerTransfer -gt $aggroChannelConsumerExpertiseRead -and
    [int]$contract.expected.productionAggroChannelHandlersGuarded -eq 1 -and
    [int]$contract.expected.productionAggroChannelConsumersGuarded -eq 1 -and
    -not [bool]$contract.expected.playerNgeAggroChannelHateTransferReachable -and
    [bool]$contract.expected.nonPlayerNgeAggroChannelCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.aggro-channel-handler-and-hate-consumer-player-fail-closed"

$commandoDeferredActions = @(
    "kill_meter_co_it_burns_proc",
    "kill_meter_co_armor_splash_proc",
    "kill_meter_co_youll_regret_that_reac",
    "expertise_co_burst_fire_proc"
)
$commandoDeferredCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object { $commandoDeferredActions -ccontains [string]$_.commandName })
$commandoDeferredCombatRows = @(Import-SwgTab -Path $paths.combatData |
    Where-Object { $commandoDeferredActions -ccontains [string]$_.actionName })
$commandoDeferredActionHandlers = @([regex]::Matches($combatActions,
        'public int (kill_meter_co_(?:it_burns_proc|armor_splash_proc|youll_regret_that_reac)|expertise_co_burst_fire_proc)\('))
$commandoSnareArmorMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.TYPE -ceq "commandoSnareBonus" })
$commandoSnareArmorBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    [string]$_.EFFECT1_PARAM -ceq "commando_snare_bonus"
})
$commandoSnareArmorSkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object { [string]$_.NAME -cmatch '^expertise_co_youll_regret_that_[1-4]$' })
Assert-Contract ($commandoDeferredCommandRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoDeferredCommandRows -and
    @($commandoDeferredCommandRows | Where-Object {
        [string]$_.scriptHook -ceq [string]$_.commandName -and
        [string]$_.fromServerOnly -ceq "1" -and
        [string]$_.toolbarOnly -ceq "1"
    }).Count -eq $commandoDeferredCommandRows.Count -and
    $commandoDeferredCombatRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoDeferredCombatRows -and
    @($commandoDeferredCombatRows | Where-Object {
        [string]$_.commandType -ceq "LEFT_CLICK_DEFAULT"
    }).Count -eq $commandoDeferredCombatRows.Count -and
    @($commandoDeferredCombatRows | Where-Object {
        [string]$_.actionName -ceq "kill_meter_co_youll_regret_that_reac" -and
        [string]$_.buffNameSelf -ceq "co_youll_regret_that"
    }).Count -eq 1 -and
    $commandoDeferredActionHandlers.Count -eq
        [int]$contract.expected.retainedNgeCommandoDeferredActionHandlers -and
    $commandoSnareArmorMappings.Count -eq
        [int]$contract.expected.retainedNgeCommandoSnareArmorEffectMappingRows -and
    [string]$commandoSnareArmorMappings[0].NAME -ceq "commando_snare_bonus" -and
    [string]$commandoSnareArmorMappings[0].SUBTYPE -ceq "commando_snare_bonus" -and
    $commandoSnareArmorBuffRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoSnareArmorBuffRows -and
    [string]$commandoSnareArmorBuffRows[0].NAME -ceq "co_youll_regret_that" -and
    [string]$commandoSnareArmorBuffRows[0].GROUP1 -ceq "youll_regret_that" -and
    [string]$commandoSnareArmorBuffRows[0].DURATION -ceq "30" -and
    [string]$commandoSnareArmorBuffRows[0].IS_PERSISTENT -ceq "1" -and
    $commandoSnareArmorSkillRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoSnareArmorExpertiseSkillRows -and
    @($commandoSnareArmorSkillRows | Where-Object {
        [string]$_.SKILL_MODS -match 'expertise_youll_regret_that=1000'
    }).Count -eq 4 -and
    @($commandoSnareArmorSkillRows | Where-Object {
        [string]$_.NAME -ceq "expertise_co_youll_regret_that_1" -and
        [string]$_.SKILL_MODS -match 'kill_meter_co_youll_regret_that_reac=100'
    }).Count -eq 1) `
    "p14.combat-expertise-isolation.buff.commando-snare-armor-data-and-action-ownership-authenticated"

$commandoPlayerAction = Get-BracedBlock $combatBase `
    "public static boolean isRetiredPostNgeCommandoPlayerAction(obj_id self, String actionName)"
$commandoSnareArmorEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerCommandoSnareArmorEffect(String effectName)"
$commandoSnareArmorBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerCommandoSnareArmorBuff(obj_id target, buff_data data)"
$commandoSnareArmorModifierCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerCommandoSnareArmorModifier(obj_id player)"
$commandoSnareArmorStateCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerCommandoSnareArmorState(obj_id player)"
$commandoSnareArmorProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$commandoSnareArmorCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$commandoSnareArmorAdmissionGate = $commandoSnareArmorCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerCommandoSnareArmorBuff(target, bdata)",
    [StringComparison]::Ordinal)
$commandoSnareArmorExistingBuffReturn = $commandoSnareArmorCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($commandoPlayerAction.Contains('actionName.startsWith("co_")') -and
    $commandoPlayerAction.Contains('actionName.startsWith("kill_meter_co_")') -and
    $commandoPlayerAction.Contains('actionName.startsWith("expertise_co_")') -and
    $commandoPlayerAction.Contains('actionName.equals("banner_buff_commando")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeCommandoPlayerAction(self, actionName)") -and
    $buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_COMMANDO_SNARE_ARMOR_EFFECT = "commando_snare_bonus"') -and
    $buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_COMMANDO_SNARE_ARMOR_MODIFIER = "commandoInnateArmorBonus"') -and
    $commandoSnareArmorEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_COMMANDO_SNARE_ARMOR_EFFECT") -and
    $commandoSnareArmorBuffPredicate.Contains("!isPlayer(target)") -and
    $commandoSnareArmorBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $commandoSnareArmorBuffPredicate.Contains(
        "isRetiredPostNgePlayerCommandoSnareArmorEffect(getEffectParam(data, effect))") -and
    $commandoSnareArmorModifierCleanup.Contains("!isPlayer(player)") -and
    $commandoSnareArmorModifierCleanup.Contains(
        "RETIRED_POST_NGE_PLAYER_COMMANDO_SNARE_ARMOR_MODIFIER") -and
    $commandoSnareArmorModifierCleanup.Contains("hasSkillModModifier") -and
    $commandoSnareArmorModifierCleanup.Contains("removeAttribOrSkillModModifier") -and
    $commandoSnareArmorStateCleanup.Contains("getAllBuffs(player)") -and
    $commandoSnareArmorStateCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $commandoSnareArmorStateCleanup.Contains("removeBuff(player, activeBuff)") -and
    $commandoSnareArmorStateCleanup.Contains(
        "clearPostNgePlayerCommandoSnareArmorModifier(player);") -and
    $commandoSnareArmorProgressionCleanup.Contains(
        "retirePostNgePlayerCommandoSnareArmorState(player);") -and
    $commandoSnareArmorAdmissionGate -ge 0 -and
    $commandoSnareArmorExistingBuffReturn -gt $commandoSnareArmorAdmissionGate -and
    -not [bool]$contract.expected.playerNgeCommandoDeferredActionExecutionReachable -and
    -not [bool]$contract.expected.playerNgeCommandoSnareArmorBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeCommandoSnareArmorStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeCommandoSnareArmorModifierRemoved) `
    "p14.combat-expertise-isolation.buff.commando-snare-armor-action-admission-and-persistence-fail-closed"

$commandoSnareArmorAddHandler = Get-BracedBlock $buffHandler `
    "public int commandoSnareBonusAddBuffHandler("
$commandoSnareArmorRemoveHandler = Get-BracedBlock $buffHandler `
    "public int commandoSnareBonusRemoveBuffHandler("
$commandoSnareArmorValidity = $commandoSnareArmorAddHandler.IndexOf(
    "if (!isIdValid(self))", [StringComparison]::Ordinal)
$commandoSnareArmorGuard = $commandoSnareArmorAddHandler.IndexOf(
    "if (isPlayer(self) &&", [StringComparison]::Ordinal)
$commandoSnareArmorPredicate = $commandoSnareArmorAddHandler.IndexOf(
    "buff.isRetiredPostNgePlayerCommandoSnareArmorEffect(effectName)",
    [StringComparison]::Ordinal)
$commandoSnareArmorCleanup = $commandoSnareArmorAddHandler.IndexOf(
    "buff.retirePostNgePlayerCommandoSnareArmorState(self);",
    [StringComparison]::Ordinal)
$commandoSnareArmorReturn = $commandoSnareArmorAddHandler.IndexOf(
    "return SCRIPT_OVERRIDE;", $commandoSnareArmorCleanup,
    [StringComparison]::Ordinal)
$commandoSnareArmorMovementRead = $commandoSnareArmorAddHandler.IndexOf(
    "movement.getAllModifiers(self)", [StringComparison]::Ordinal)
$commandoSnareArmorExpertiseRead = $commandoSnareArmorAddHandler.IndexOf(
    'getSkillStatisticModifier(self, "expertise_youll_regret_that")',
    [StringComparison]::Ordinal)
$commandoSnareArmorWriter = $commandoSnareArmorAddHandler.IndexOf(
    'skillAddBuffHandler(self, "commandoInnateArmorBonus", "expertise_innate_protection_all"',
    [StringComparison]::Ordinal)
Assert-Contract ($commandoSnareArmorValidity -ge 0 -and
    $commandoSnareArmorGuard -gt $commandoSnareArmorValidity -and
    $commandoSnareArmorPredicate -gt $commandoSnareArmorGuard -and
    $commandoSnareArmorCleanup -gt $commandoSnareArmorPredicate -and
    $commandoSnareArmorReturn -gt $commandoSnareArmorCleanup -and
    $commandoSnareArmorMovementRead -gt $commandoSnareArmorReturn -and
    $commandoSnareArmorExpertiseRead -gt $commandoSnareArmorMovementRead -and
    $commandoSnareArmorWriter -gt $commandoSnareArmorExpertiseRead -and
    $commandoSnareArmorRemoveHandler.Contains(
        'removeAttribOrSkillModModifier(self, "commandoInnateArmorBonus")') -and
    $commandoSnareArmorRemoveHandler.Contains(
        'messageTo(self, "recalcArmor"') -and
    [int]$contract.expected.productionCommandoSnareArmorHandlersGuarded -eq 1 -and
    -not [bool]$contract.expected.playerNgeCommandoSnareArmorModifierWritesReachable -and
    [bool]$contract.expected.nonPlayerNgeCommandoSnareArmorCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.commando-snare-armor-handler-player-fail-closed"

$commandoSpecializedEffectTypes = [ordered]@{
    expertise_flash_bang = "commandoFlashBang"
    expertise_muscle_spasm = "commandoMuscleSpasm"
    expertise_riddle_armor = "commandoRiddleArmor"
    expertise_on_target = "onTarget"
}
$commandoSpecializedMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { $commandoSpecializedEffectTypes.Contains([string]$_.NAME) })
$commandoSpecializedMappingSignatures = @($commandoSpecializedMappings |
    ForEach-Object {
        "{0}|{1}|{2}" -f $_.NAME, $_.TYPE, $_.SUBTYPE
    } | Sort-Object)
$expectedCommandoSpecializedMappingSignatures = @(
    "expertise_flash_bang|commandoFlashBang|expertise_flash_bang",
    "expertise_muscle_spasm|commandoMuscleSpasm|expertise_muscle_spasm",
    "expertise_on_target|onTarget|expertise_on_target",
    "expertise_riddle_armor|commandoRiddleArmor|expertise_riddle_armor"
)
$commandoSpecializedBuffNames = @(
    "co_armor_cracker",
    "co_base_of_operations",
    "co_flash_bang",
    "co_muscle_spasm",
    "co_pos_sec_action_1",
    "co_pos_sec_action_2",
    "co_pos_sec_action_3",
    "co_pos_sec_critical_1",
    "co_pos_sec_critical_2",
    "co_pos_sec_critical_3",
    "co_pos_sec_critical_4",
    "co_pos_sec_proc_1",
    "co_pos_sec_proc_2",
    "co_position_secured",
    "co_riddle_armor",
    "grenadier_kinetic"
)
$commandoSpecializedBuffRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object { $commandoSpecializedBuffNames -ccontains [string]$_.NAME })
$commandoSpecializedBuffSignatures = @($commandoSpecializedBuffRows |
    ForEach-Object {
        "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}" -f
            $_.NAME, $_.GROUP1, $_.DURATION, $_.DEBUFF, $_.IS_PERSISTENT,
            $_.EFFECT1_PARAM, $_.EFFECT1_VALUE, $_.EFFECT2_PARAM, $_.EFFECT2_VALUE,
            $_.EFFECT3_PARAM, $_.EFFECT3_VALUE, $_.EFFECT4_PARAM, $_.EFFECT4_VALUE,
            $_.EFFECT5_PARAM, $_.EFFECT5_VALUE
    } | Sort-Object)
$expectedCommandoSpecializedBuffSignatures = @(
    "co_armor_cracker|playerArmorReduce|15|1|1|expertise_riddle_armor|0||0||0||0||0",
    "co_base_of_operations|base_of_operations|600|0|0|group|0|expertise_innate_protection_all|1000|expertise_critical_niche_all|5||0||0",
    "co_flash_bang|flash_bang|30|1|1|expertise_flash_bang|0||0||0||0||0",
    "co_muscle_spasm|muscle_spasm|10|1|1|expertise_muscle_spasm|0||0||0||0||0",
    "co_pos_sec_action_1|co_pos_sec_action|-1|0|1|expertise_action_all|10||0||0||0||0",
    "co_pos_sec_action_2|co_pos_sec_action|-1|0|1|expertise_action_all|20||0||0||0||0",
    "co_pos_sec_action_3|co_pos_sec_action|-1|0|1|expertise_action_all|30||0||0||0||0",
    "co_pos_sec_critical_1|co_pos_sec_critical|-1|0|1|expertise_critical_hit_reduction|5|expertise_critical_niche_all|2||0||0||0",
    "co_pos_sec_critical_2|co_pos_sec_critical|-1|0|1|expertise_critical_hit_reduction|10|expertise_critical_niche_all|4||0||0||0",
    "co_pos_sec_critical_3|co_pos_sec_critical|-1|0|1|expertise_critical_hit_reduction|15|expertise_critical_niche_all|6||0||0||0",
    "co_pos_sec_critical_4|co_pos_sec_critical|-1|0|1|expertise_critical_hit_reduction|20|expertise_critical_niche_all|8||0||0||0",
    "co_pos_sec_proc_1|co_pos_sec_proc|-1|0|1|expertise_co_burst_fire_proc|10|expertise_devastation_bonus|50||0||0||0",
    "co_pos_sec_proc_2|co_pos_sec_proc|-1|0|1|expertise_co_burst_fire_proc|20|expertise_devastation_bonus|100||0||0||0",
    "co_position_secured|position_secured|600|0|0|precision_modified|200|strength_modified|200|movement|0|expertise_on_target|0||0",
    "co_riddle_armor|playerArmorReduce|15|1|1|expertise_riddle_armor|0||0||0||0||0",
    "grenadier_kinetic|krix_grenadier_kinetic|15|1|1|expertise_riddle_armor|-2250||0||0||0||0"
)
$commandoSpecializedCommandNames = @(
    "co_armor_cracker", "co_position_secured", "co_riddle_armor"
)
$commandoSpecializedCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object { $commandoSpecializedCommandNames -ccontains [string]$_.commandName })
$commandoSpecializedCombatNames = @(
    "co_armor_cracker", "co_base_of_operations", "co_position_secured", "co_riddle_armor"
)
$commandoSpecializedCombatRows = @(Import-SwgTab -Path $paths.combatData |
    Where-Object { $commandoSpecializedCombatNames -ccontains [string]$_.actionName })
$commandoSpecializedSkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object {
        [string]$_.NAME -cmatch '^expertise_co_(?:position_secured_1|imp_position_secured_[1-3]|burst_fire_[1-2]|on_target_[1-4]|base_of_operations_1|flashbang_[1-2]|riddle_armor_1|imp_riddle_armor_[1-2]|armor_cracker_1)$'
    })
$commandoSpecializedSkillModNames = @(
    "expertise_co_flash_bang", "expertise_co_muscle_spasm", "expertise_riddle_armor"
)
$commandoSpecializedSkillModRows = @(Import-SwgTab -Path $paths.skillModListing |
    Where-Object { $commandoSpecializedSkillModNames -ccontains [string]$_.skill_mod })
Assert-Contract ($commandoSpecializedMappings.Count -eq
        [int]$contract.expected.retainedNgeCommandoSpecializedEffectMappingRows -and
    (($commandoSpecializedMappingSignatures -join "`n") -ceq
        ($expectedCommandoSpecializedMappingSignatures -join "`n")) -and
    $commandoSpecializedBuffRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoSpecializedBuffRows -and
    (($commandoSpecializedBuffSignatures -join "`n") -ceq
        ($expectedCommandoSpecializedBuffSignatures -join "`n")) -and
    $commandoSpecializedCommandRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoSpecializedCommandRows -and
    @($commandoSpecializedCommandRows | Where-Object {
        [string]$_.scriptHook -ceq [string]$_.commandName
    }).Count -eq $commandoSpecializedCommandRows.Count -and
    $commandoSpecializedCombatRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoSpecializedCombatRows -and
    $commandoSpecializedSkillRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoSpecializedSkillRows -and
    $commandoSpecializedSkillModRows.Count -eq
        [int]$contract.expected.retainedNgeCommandoSpecializedSkillModListingRows) `
    "p14.combat-expertise-isolation.buff.commando-specialized-data-authenticated"

$commandoSpecializedEffectInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_COMMANDO_SPECIALIZED_EFFECTS"
$commandoSpecializedBuffInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_COMMANDO_SPECIALIZED_BUFFS"
$commandoSpecializedModifierInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_COMMANDO_SPECIALIZED_MODIFIERS"
$commandoSpecializedEffectInventoryNames = @([regex]::Matches(
        $commandoSpecializedEffectInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$commandoSpecializedBuffInventoryNames = @([regex]::Matches(
        $commandoSpecializedBuffInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$commandoSpecializedModifierInventoryNames = @([regex]::Matches(
        $commandoSpecializedModifierInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$commandoSpecializedEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerCommandoSpecializedEffect(String effectName)"
$commandoSpecializedBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerCommandoSpecializedBuff(obj_id target, buff_data data)"
$commandoSpecializedModifierCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerCommandoSpecializedModifiers(obj_id player)"
$commandoSpecializedBuffCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerCommandoSpecializedBuffs(obj_id player)"
$commandoSpecializedStateCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerCommandoSpecializedState(obj_id player)"
$commandoSpecializedProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$commandoSpecializedCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$commandoSpecializedAdmissionGate = $commandoSpecializedCanApplyBuff.IndexOf(
    "isRetiredPostNgePlayerCommandoSpecializedBuff(target, bdata)",
    [StringComparison]::Ordinal)
$commandoSpecializedExistingBuffReturn = $commandoSpecializedCanApplyBuff.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$commandoSpecializedParentRemoval = $commandoSpecializedStateCleanup.IndexOf(
    'removeBuff(player, "co_position_secured")', [StringComparison]::Ordinal)
$commandoSpecializedChildRemoval = $commandoSpecializedStateCleanup.IndexOf(
    "clearPostNgePlayerCommandoSpecializedBuffs(player);", [StringComparison]::Ordinal)
$commandoSpecializedModifierRemoval = $commandoSpecializedStateCleanup.IndexOf(
    "clearPostNgePlayerCommandoSpecializedModifiers(player);", [StringComparison]::Ordinal)
Assert-Contract ($commandoSpecializedEffectInventoryNames.Count -eq
        [int]$contract.expected.retainedNgeCommandoSpecializedEffectMappingRows -and
    (($commandoSpecializedEffectInventoryNames | Sort-Object) -join ([char]0)) -ceq
        (($commandoSpecializedEffectTypes.Keys | Sort-Object) -join ([char]0)) -and
    $commandoSpecializedBuffInventoryNames.Count -eq
        [int]$contract.expected.retainedNgeCommandoSpecializedBuffRows -and
    (($commandoSpecializedBuffInventoryNames | Sort-Object) -join ([char]0)) -ceq
        (($commandoSpecializedBuffNames | Sort-Object) -join ([char]0)) -and
    $commandoSpecializedModifierInventoryNames.Count -eq
        [int]$contract.expected.retiredNgePlayerCommandoSpecializedModifiers -and
    @($commandoSpecializedModifierInventoryNames | Select-Object -Unique).Count -eq
        $commandoSpecializedModifierInventoryNames.Count -and
    $commandoSpecializedEffectPredicate.Contains("effectName.equals(retiredEffect)") -and
    $commandoSpecializedEffectPredicate.Contains('effectName.startsWith(retiredEffect + "_")') -and
    $commandoSpecializedBuffPredicate.Contains("!isPlayer(target)") -and
    $commandoSpecializedBuffPredicate.Contains(
        "isRetiredPostNgePlayerCommandoSpecializedBuffName(data.buffName)") -and
    $commandoSpecializedBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $commandoSpecializedBuffPredicate.Contains(
        "isRetiredPostNgePlayerCommandoSpecializedEffect(getEffectParam(data, effect))") -and
    $commandoSpecializedModifierCleanup.Contains("!isPlayer(player)") -and
    $commandoSpecializedModifierCleanup.Contains("hasSkillModModifier(player, retiredModifier)") -and
    $commandoSpecializedModifierCleanup.Contains('retiredModifier + "_" + effect') -and
    $commandoSpecializedModifierCleanup.Contains("getSkillStatMod(player, retiredModifier)") -and
    $commandoSpecializedModifierCleanup.Contains(
        "applySkillStatisticModifier(player, retiredModifier, -currentValue)") -and
    $commandoSpecializedModifierCleanup.Contains('messageTo(player, "recalcArmor"') -and
    $commandoSpecializedModifierCleanup.Contains("combat.cacheCombatData(player)") -and
    $commandoSpecializedBuffCleanup.Contains('!retiredBuff.equals("co_position_secured")') -and
    $commandoSpecializedBuffCleanup.Contains("removeBuff(player, retiredBuff)") -and
    $commandoSpecializedParentRemoval -ge 0 -and
    $commandoSpecializedChildRemoval -gt $commandoSpecializedParentRemoval -and
    $commandoSpecializedModifierRemoval -gt $commandoSpecializedChildRemoval -and
    $commandoSpecializedProgressionCleanup.Contains(
        "retirePostNgePlayerCommandoSpecializedState(player);") -and
    $commandoSpecializedAdmissionGate -ge 0 -and
    $commandoSpecializedExistingBuffReturn -gt $commandoSpecializedAdmissionGate -and
    $commandoPlayerAction.Contains('actionName.startsWith("co_")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeCommandoPlayerAction(self, actionName)") -and
    -not [bool]$contract.expected.playerNgeCommandoSpecializedActionExecutionReachable -and
    -not [bool]$contract.expected.playerNgeCommandoSpecializedBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeCommandoSpecializedStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeCommandoSpecializedModifiersRemoved) `
    "p14.combat-expertise-isolation.buff.commando-specialized-action-admission-and-state-fail-closed"

$commandoSpecializedHandlerSpecs = @(
    [pscustomobject]@{ Method = "commandoFlashBangAddBuffHandler"; Cleanup = "buff.retirePostNgePlayerCommandoSpecializedState(self);"; AdditionalCleanup = ""; Retained = "effectName = effectName.substring" },
    [pscustomobject]@{ Method = "commandoFlashBangRemoveBuffHandler"; Cleanup = "buff.clearPostNgePlayerCommandoSpecializedModifiers(self);"; AdditionalCleanup = ""; Retained = 'removeAttribOrSkillModModifier(self, "commandoFlashBang")' },
    [pscustomobject]@{ Method = "commandoMuscleSpasmAddBuffHandler"; Cleanup = "buff.retirePostNgePlayerCommandoSpecializedState(self);"; AdditionalCleanup = ""; Retained = "effectName = effectName.substring" },
    [pscustomobject]@{ Method = "commandoMuscleSpasmRemoveBuffHandler"; Cleanup = "buff.clearPostNgePlayerCommandoSpecializedModifiers(self);"; AdditionalCleanup = ""; Retained = 'removeAttribOrSkillModModifier(self, "commandoMuscleSpasm")' },
    [pscustomobject]@{ Method = "commandoRiddleArmorAddBuffHandler"; Cleanup = "buff.retirePostNgePlayerCommandoSpecializedState(self);"; AdditionalCleanup = ""; Retained = "String tempEffectName = effectName.substring" },
    [pscustomobject]@{ Method = "commandoRiddleArmorRemoveBuffHandler"; Cleanup = "buff.clearPostNgePlayerCommandoSpecializedModifiers(self);"; AdditionalCleanup = ""; Retained = "removeAttribOrSkillModModifier(self, effectName)" },
    [pscustomobject]@{ Method = "onTargetAddBuffHandler"; Cleanup = "buff.retirePostNgePlayerCommandoSpecializedState(self);"; AdditionalCleanup = ""; Retained = 'if (subtype.equals("expertise_on_target"))' },
    [pscustomobject]@{ Method = "onTargetRemoveBuffHandler"; Cleanup = "buff.clearPostNgePlayerCommandoSpecializedBuffs(self);"; AdditionalCleanup = "buff.clearPostNgePlayerCommandoSpecializedModifiers(self);"; Retained = "if (hasSkillModModifier(self, effectName))" }
)
$commandoSpecializedGuardedHandlers = 0
foreach ($handlerSpec in $commandoSpecializedHandlerSpecs)
{
    $handlerBlock = Get-BracedBlock $buffHandler ("public int {0}(" -f $handlerSpec.Method)
    $guardIndex = $handlerBlock.IndexOf("isPlayer(self)", [StringComparison]::Ordinal)
    $cleanupIndex = $handlerBlock.IndexOf([string]$handlerSpec.Cleanup,
        [StringComparison]::Ordinal)
    $cleanupEndIndex = $cleanupIndex
    if (-not [string]::IsNullOrEmpty([string]$handlerSpec.AdditionalCleanup))
    {
        $additionalCleanupIndex = $handlerBlock.IndexOf(
            [string]$handlerSpec.AdditionalCleanup, [StringComparison]::Ordinal)
        if ($additionalCleanupIndex -gt $cleanupEndIndex) { $cleanupEndIndex = $additionalCleanupIndex }
    }
    $returnIndex = $handlerBlock.IndexOf("return SCRIPT_OVERRIDE;", $cleanupEndIndex,
        [StringComparison]::Ordinal)
    $retainedIndex = $handlerBlock.IndexOf([string]$handlerSpec.Retained,
        [StringComparison]::Ordinal)
    $effectPredicateRequired = $handlerSpec.Method.StartsWith("onTarget",
        [StringComparison]::Ordinal)
    $effectPredicatePresent = $handlerBlock.Contains(
        "buff.isRetiredPostNgePlayerCommandoSpecializedEffect(effectName)")
    if ($guardIndex -ge 0 -and $cleanupIndex -gt $guardIndex -and
        $returnIndex -gt $cleanupEndIndex -and $retainedIndex -gt $returnIndex -and
        (-not $effectPredicateRequired -or $effectPredicatePresent))
    {
        ++$commandoSpecializedGuardedHandlers
    }
}
Assert-Contract ($commandoSpecializedGuardedHandlers -eq
        [int]$contract.expected.productionCommandoSpecializedHandlersGuarded -and
    -not [bool]$contract.expected.playerNgeCommandoSpecializedHandlerExecutionReachable -and
    [bool]$contract.expected.nonPlayerNgeCommandoSpecializedCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.commando-specialized-eight-handlers-player-fail-closed"

$forceSensitiveExpertiseImmunityEffectTypes = [ordered]@{
    expertise_dot_immunity = "expertiseImmunity|dot_immunity"
    expertise_movement_immunity = "expertiseImmunity|movement_immunity"
}
$forceSensitiveExpertiseImmunityMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { $forceSensitiveExpertiseImmunityEffectTypes.Contains([string]$_.NAME) })
$forceSensitiveExpertiseImmunityMappingSignatures = @(
    $forceSensitiveExpertiseImmunityMappings | ForEach-Object {
        "{0}|{1}|{2}" -f $_.NAME, $_.TYPE, $_.SUBTYPE
    } | Sort-Object)
$expectedForceSensitiveExpertiseImmunityMappingSignatures = @(
    "expertise_dot_immunity|expertiseImmunity|dot_immunity",
    "expertise_movement_immunity|expertiseImmunity|movement_immunity"
)
$forceSensitiveExpertiseImmunityBuffNames = @(
    "fs_dot_immunity_recourse", "fs_sh_0", "fs_sh_1", "fs_sh_2", "fs_sh_3"
)
$forceSensitiveExpertiseImmunityBuffRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object { $forceSensitiveExpertiseImmunityBuffNames -ccontains [string]$_.NAME })
$forceSensitiveExpertiseImmunityBuffSignatures = @(
    $forceSensitiveExpertiseImmunityBuffRows | ForEach-Object {
        "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}" -f $_.NAME, $_.GROUP1, $_.DURATION,
            $_.DEBUFF, $_.IS_PERSISTENT, $_.EFFECT1_PARAM, $_.EFFECT1_VALUE, $_.CALLBACK
    } | Sort-Object)
$expectedForceSensitiveExpertiseImmunityBuffSignatures = @(
    "fs_dot_immunity_recourse|fsCure|25|1|1||0|none",
    "fs_sh_0|fsCure|6|0|1|expertise_dot_immunity|5|fs_dot_immunity_recourse",
    "fs_sh_1|fsCure|10|0|1|expertise_dot_immunity|5|fs_dot_immunity_recourse",
    "fs_sh_2|fsCure|12|0|1|expertise_dot_immunity|5|fs_dot_immunity_recourse",
    "fs_sh_3|fsCure|14|0|1|expertise_dot_immunity|5|fs_dot_immunity_recourse"
)
$forceSensitiveExpertiseImmunityActionNames = @("fs_sh_0", "fs_sh_1", "fs_sh_2", "fs_sh_3")
$forceSensitiveExpertiseImmunityCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object { $forceSensitiveExpertiseImmunityActionNames -ccontains [string]$_.commandName })
$forceSensitiveExpertiseImmunityCombatRows = @(Import-SwgTab -Path $paths.combatData |
    Where-Object { $forceSensitiveExpertiseImmunityActionNames -ccontains [string]$_.actionName })
$forceSensitiveExpertiseImmunityCombatSignatures = @(
    $forceSensitiveExpertiseImmunityCombatRows | ForEach-Object {
        "{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $_.actionName, $_.validTarget, $_.hitType,
            $_.addedDamage, $_.actionCost, $_.specialLine, $_.performance_spam
    } | Sort-Object)
$expectedForceSensitiveExpertiseImmunityCombatSignatures = @(
    "fs_sh_0|NONE|HEAL|800|200|fs_heal|perform_notarget",
    "fs_sh_1|NONE|HEAL|2500|450|fs_heal|perform_notarget",
    "fs_sh_2|NONE|HEAL|3500|800|fs_heal|perform_notarget",
    "fs_sh_3|NONE|HEAL|5000|1150|fs_heal|perform_notarget"
)
$forceSensitiveExpertiseImmunitySkillNames = @(
    "class_forcesensitive_phase1_05", "class_forcesensitive_phase2_04",
    "class_forcesensitive_phase3_04", "class_forcesensitive_phase4_04"
)
$forceSensitiveExpertiseImmunitySkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object { $forceSensitiveExpertiseImmunitySkillNames -ccontains [string]$_.NAME })
Assert-Contract ($forceSensitiveExpertiseImmunityMappings.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveExpertiseImmunityEffectMappingRows -and
    (($forceSensitiveExpertiseImmunityMappingSignatures -join "`n") -ceq
        ($expectedForceSensitiveExpertiseImmunityMappingSignatures -join "`n")) -and
    $forceSensitiveExpertiseImmunityBuffRows.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveExpertiseImmunityBuffRows -and
    (($forceSensitiveExpertiseImmunityBuffSignatures -join "`n") -ceq
        ($expectedForceSensitiveExpertiseImmunityBuffSignatures -join "`n")) -and
    $forceSensitiveExpertiseImmunityCommandRows.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveExpertiseImmunityCommandRows -and
    @($forceSensitiveExpertiseImmunityCommandRows | Where-Object {
        [string]$_.scriptHook -ceq [string]$_.commandName -and
        [string]$_.displayGroup -ceq "combat" -and [int]$_.addToCombatQueue -eq 1
    }).Count -eq $forceSensitiveExpertiseImmunityCommandRows.Count -and
    $forceSensitiveExpertiseImmunityCombatRows.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveExpertiseImmunityCombatRows -and
    (($forceSensitiveExpertiseImmunityCombatSignatures -join "`n") -ceq
        ($expectedForceSensitiveExpertiseImmunityCombatSignatures -join "`n")) -and
    $forceSensitiveExpertiseImmunitySkillRows.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveExpertiseImmunitySkillRows -and
    @($forceSensitiveExpertiseImmunitySkillRows | Where-Object {
        [string]$_.COMMANDS -cmatch '(^|,)fs_sh_[0-3](,|$)'
    }).Count -eq $forceSensitiveExpertiseImmunitySkillRows.Count) `
    "p14.combat-expertise-isolation.buff.fs-expertise-immunity-data-authenticated"

$forceSensitiveExpertiseImmunityEffectInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_FORCE_SENSITIVE_EXPERTISE_IMMUNITY_EFFECTS"
$forceSensitiveExpertiseImmunityBuffInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_FORCE_SENSITIVE_EXPERTISE_IMMUNITY_BUFFS"
$forceSensitiveExpertiseImmunityEffectInventoryNames = @([regex]::Matches(
        $forceSensitiveExpertiseImmunityEffectInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$forceSensitiveExpertiseImmunityBuffInventoryNames = @([regex]::Matches(
        $forceSensitiveExpertiseImmunityBuffInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$forceSensitiveExpertiseImmunityEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect(String effectName)"
$forceSensitiveExpertiseImmunityBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuff(obj_id target, buff_data data)"
$forceSensitiveExpertiseImmunityResidueCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerForceSensitiveExpertiseImmunityResidue(obj_id player)"
$forceSensitiveExpertiseImmunityStateCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerForceSensitiveExpertiseImmunityState(obj_id player)"
$forceSensitiveExpertiseImmunityProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$forceSensitiveExpertiseImmunityCanApplyBuff = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$forceSensitiveExpertiseImmunityAdmissionGate =
    $forceSensitiveExpertiseImmunityCanApplyBuff.IndexOf(
        "isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuff(target, bdata)",
        [StringComparison]::Ordinal)
$forceSensitiveExpertiseImmunityExistingBuffReturn =
    $forceSensitiveExpertiseImmunityCanApplyBuff.IndexOf(
        "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$ordinaryImmunityMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -cin @("dot_immunity", "movement_immunity") })
Assert-Contract ($forceSensitiveExpertiseImmunityEffectInventoryNames.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveExpertiseImmunityEffectMappingRows -and
    (($forceSensitiveExpertiseImmunityEffectInventoryNames | Sort-Object) -join ([char]0)) -ceq
        (($forceSensitiveExpertiseImmunityEffectTypes.Keys | Sort-Object) -join ([char]0)) -and
    $forceSensitiveExpertiseImmunityBuffInventoryNames.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveExpertiseImmunityBuffRows -and
    (($forceSensitiveExpertiseImmunityBuffInventoryNames | Sort-Object) -join ([char]0)) -ceq
        (($forceSensitiveExpertiseImmunityBuffNames | Sort-Object) -join ([char]0)) -and
    $forceSensitiveExpertiseImmunityEffectPredicate.Contains(
        "effectName.equals(retiredEffect)") -and
    -not $forceSensitiveExpertiseImmunityEffectPredicate.Contains("startsWith") -and
    $forceSensitiveExpertiseImmunityBuffPredicate.Contains("!isPlayer(target)") -and
    $forceSensitiveExpertiseImmunityBuffPredicate.Contains(
        "isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuffName(data.buffName)") -and
    $forceSensitiveExpertiseImmunityBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $forceSensitiveExpertiseImmunityBuffPredicate.Contains(
        "isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect(getEffectParam(data, effect))") -and
    $forceSensitiveExpertiseImmunityResidueCleanup.Contains("!isPlayer(player)") -and
    $forceSensitiveExpertiseImmunityResidueCleanup.Contains('"immunity.dot.all"') -and
    $forceSensitiveExpertiseImmunityResidueCleanup.Contains('"immunity.movement.snare"') -and
    $forceSensitiveExpertiseImmunityResidueCleanup.Contains('"immunity.movement.root"') -and
    $forceSensitiveExpertiseImmunityResidueCleanup.Contains(
        'stopClientEffectObjByLabel(player, "expertise_dot")') -and
    $forceSensitiveExpertiseImmunityResidueCleanup.Contains(
        'stopClientEffectObjByLabel(player, "expertise_movement")') -and
    $forceSensitiveExpertiseImmunityStateCleanup.Contains("!isPlayer(player)") -and
    $forceSensitiveExpertiseImmunityStateCleanup.Contains(
        "RETIRED_POST_NGE_PLAYER_FORCE_SENSITIVE_EXPERTISE_IMMUNITY_BUFFS") -and
    $forceSensitiveExpertiseImmunityStateCleanup.Contains("removeBuff(player, retiredBuff)") -and
    $forceSensitiveExpertiseImmunityStateCleanup.Contains(
        "clearPostNgePlayerForceSensitiveExpertiseImmunityResidue(player);") -and
    $forceSensitiveExpertiseImmunityProgressionCleanup.Contains(
        "retirePostNgePlayerForceSensitiveExpertiseImmunityState(player);") -and
    $forceSensitiveExpertiseImmunityAdmissionGate -ge 0 -and
    $forceSensitiveExpertiseImmunityExistingBuffReturn -gt
        $forceSensitiveExpertiseImmunityAdmissionGate -and
    $forceSensitivePlayerAction.Contains('actionName.startsWith("fs_")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeForceSensitivePlayerAction(self, actionName)") -and
    -not [bool]$contract.expected.playerNgeForceSensitiveExpertiseImmunityActionExecutionReachable -and
    -not [bool]$contract.expected.playerNgeForceSensitiveExpertiseImmunityBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeForceSensitiveExpertiseImmunityStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeForceSensitiveExpertiseImmunityResidueRemoved) `
    "p14.combat-expertise-isolation.buff.fs-expertise-immunity-action-admission-and-state-fail-closed"

$forceSensitiveExpertiseImmunityHandlerSpecs = @(
    [pscustomobject]@{ Method = "expertiseImmunityAddBuffHandler"; Cleanup = "buff.retirePostNgePlayerForceSensitiveExpertiseImmunityState(self);"; Retained = "if (!buff.isInStance(self))" },
    [pscustomobject]@{ Method = "expertiseImmunityRemoveBuffHandler"; Cleanup = "buff.clearPostNgePlayerForceSensitiveExpertiseImmunityResidue(self);"; Retained = "return immunityRemoveBuffHandler" }
)
$forceSensitiveExpertiseImmunityGuardedHandlers = 0
foreach ($handlerSpec in $forceSensitiveExpertiseImmunityHandlerSpecs)
{
    $handlerBlock = Get-BracedBlock $buffHandler ("public int {0}(" -f $handlerSpec.Method)
    $guardIndex = $handlerBlock.IndexOf("isPlayer(self)", [StringComparison]::Ordinal)
    $effectPredicateIndex = $handlerBlock.IndexOf(
        "buff.isRetiredPostNgePlayerForceSensitiveExpertiseImmunityEffect(effectName)",
        [StringComparison]::Ordinal)
    $namePredicateIndex = $handlerBlock.IndexOf(
        "buff.isRetiredPostNgePlayerForceSensitiveExpertiseImmunityBuffName(buffName)",
        [StringComparison]::Ordinal)
    $cleanupIndex = $handlerBlock.IndexOf([string]$handlerSpec.Cleanup,
        [StringComparison]::Ordinal)
    $returnIndex = $handlerBlock.IndexOf("return SCRIPT_OVERRIDE;", $cleanupIndex,
        [StringComparison]::Ordinal)
    $retainedIndex = $handlerBlock.IndexOf([string]$handlerSpec.Retained,
        [StringComparison]::Ordinal)
    if ($guardIndex -ge 0 -and $effectPredicateIndex -gt $guardIndex -and
        $namePredicateIndex -gt $guardIndex -and $cleanupIndex -gt $namePredicateIndex -and
        $returnIndex -gt $cleanupIndex -and $retainedIndex -gt $returnIndex)
    {
        ++$forceSensitiveExpertiseImmunityGuardedHandlers
    }
}
$ordinaryImmunityAddHandler = Get-BracedBlock $buffHandler `
    "public int immunityAddBuffHandler(obj_id self"
$ordinaryImmunityRemoveHandler = Get-BracedBlock $buffHandler `
    "public int immunityRemoveBuffHandler(obj_id self"
Assert-Contract ($forceSensitiveExpertiseImmunityGuardedHandlers -eq
        [int]$contract.expected.productionForceSensitiveExpertiseImmunityHandlersGuarded -and
    -not [bool]$contract.expected.playerNgeForceSensitiveExpertiseImmunityHandlerExecutionReachable -and
    $ordinaryImmunityMappings.Count -eq 2 -and
    @($ordinaryImmunityMappings | Where-Object {
        [string]$_.TYPE -ceq "immunity" -and [string]$_.SUBTYPE -ceq [string]$_.NAME
    }).Count -eq 2 -and
    $ordinaryImmunityAddHandler.Contains('case "dot_immunity"') -and
    $ordinaryImmunityAddHandler.Contains('case "movement_immunity"') -and
    $ordinaryImmunityRemoveHandler.Contains('case "dot_immunity"') -and
    $ordinaryImmunityRemoveHandler.Contains('case "movement_immunity"') -and
    [bool]$contract.expected.ordinaryImmunityCompatibilityPreserved -and
    [bool]$contract.expected.nonPlayerNgeForceSensitiveExpertiseImmunityCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.fs-expertise-immunity-two-handlers-player-fail-closed"

$bountyHunterFlawlessBuffNames = @(
    "set_bonus_bh_utility_a_1", "set_bonus_bh_utility_a_2",
    "set_bonus_bh_utility_a_3", "bh_flawless_strike",
    "bh_flawless_proc_chance_1", "flawless_bead_1", "flawless_bead_2",
    "flawless_bead_3"
)
$bountyHunterFlawlessActionNames = @(
    "bh_flawless_strike", "set_bonus_bh_utility_a_1",
    "set_bonus_bh_utility_a_2", "set_bonus_bh_utility_a_3"
)
$bountyHunterFlawlessSetBonusActions = @(
    "set_bonus_bh_utility_a_1", "set_bonus_bh_utility_a_2",
    "set_bonus_bh_utility_a_3"
)
$bountyHunterFlawlessModifierNames = @(
    "bh_flawless_bead", "flawless_bead",
    "expertise_cooldown_line_bh_flawless_strike",
    "set_bonus_bh_utility_a_1", "set_bonus_bh_utility_a_2",
    "set_bonus_bh_utility_a_3"
)
$bountyHunterFlawlessBuffRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object { $bountyHunterFlawlessBuffNames -ccontains [string]$_.NAME })
$bountyHunterFlawlessMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -ceq "bh_flawless_proc_chance" })
$bountyHunterFlawlessCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object { $bountyHunterFlawlessActionNames -ccontains [string]$_.commandName })
$bountyHunterFlawlessCombatRows = @(Import-SwgTab -Path $paths.combatData |
    Where-Object { $bountyHunterFlawlessActionNames -ccontains [string]$_.actionName })
$bountyHunterFlawlessProcRows = @(Import-SwgTab -Path $paths.procTable |
    Where-Object { $bountyHunterFlawlessSetBonusActions -ccontains [string]$_.procString })
$bountyHunterFlawlessItemSetRows = @(Import-SwgTab -Path $paths.itemSets |
    Where-Object { [string]$_.SETID -ceq "10002" })
Assert-Contract ($bountyHunterFlawlessBuffRows.Count -eq
        [int]$contract.expected.retainedNgeBountyHunterFlawlessBuffRows -and
    @($bountyHunterFlawlessBuffRows | Select-Object -ExpandProperty NAME -Unique).Count -eq
        $bountyHunterFlawlessBuffNames.Count -and
    $bountyHunterFlawlessMappings.Count -eq
        [int]$contract.expected.retainedNgeBountyHunterFlawlessSpecialEffectMappingRows -and
    [string]$bountyHunterFlawlessMappings[0].TYPE -ceq "bhFlawless" -and
    [string]$bountyHunterFlawlessMappings[0].SUBTYPE -ceq
        "bh_flawless_proc_chance" -and
    $bountyHunterFlawlessCommandRows.Count -eq
        [int]$contract.expected.retainedNgeBountyHunterFlawlessCommandRows -and
    @($bountyHunterFlawlessCommandRows | Where-Object {
        [string]$_.scriptHook -ceq [string]$_.commandName
    }).Count -eq $bountyHunterFlawlessCommandRows.Count -and
    $bountyHunterFlawlessCombatRows.Count -eq
        [int]$contract.expected.retainedNgeBountyHunterFlawlessCombatRows -and
    $bountyHunterFlawlessProcRows.Count -eq
        [int]$contract.expected.retainedNgeBountyHunterFlawlessProcRows -and
    @($bountyHunterFlawlessProcRows | Where-Object { [int]$_.procChance -eq 10 }).Count -eq
        $bountyHunterFlawlessProcRows.Count -and
    $bountyHunterFlawlessItemSetRows.Count -eq
        [int]$contract.expected.retainedNgeBountyHunterFlawlessItemSetRows -and
    (($bountyHunterFlawlessItemSetRows.EFFECT | Sort-Object) -join ([char]0)) -ceq
        (($bountyHunterFlawlessSetBonusActions | Sort-Object) -join ([char]0))) `
    "p14.combat-expertise-isolation.bounty-hunter-flawless.data-authenticated"

$bountyHunterFlawlessBuffInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_BOUNTY_HUNTER_FLAWLESS_BUFFS"
$bountyHunterFlawlessModifierInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_BOUNTY_HUNTER_FLAWLESS_MODIFIERS"
$bountyHunterFlawlessActionInventory = Get-BracedBlock $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_PLAYER_BOUNTY_HUNTER_FLAWLESS_ACTIONS"
$bountyHunterFlawlessInventoryNames = @([regex]::Matches(
        $bountyHunterFlawlessBuffInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$bountyHunterFlawlessModifierInventoryNames = @([regex]::Matches(
        $bountyHunterFlawlessModifierInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$bountyHunterFlawlessActionInventoryNames = @([regex]::Matches(
        $bountyHunterFlawlessActionInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$bountyHunterFlawlessEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerBountyHunterFlawlessEffect(String effectName)"
$bountyHunterFlawlessBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerBountyHunterFlawlessBuff(obj_id target, buff_data data)"
$bountyHunterFlawlessResidueCleanup = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerBountyHunterFlawlessResidue(obj_id player)"
$bountyHunterFlawlessStateCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerBountyHunterFlawlessState(obj_id player)"
$bountyHunterFlawlessProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$bountyHunterFlawlessCanApply = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$bountyHunterFlawlessAdmissionGate = $bountyHunterFlawlessCanApply.IndexOf(
    "isRetiredPostNgePlayerBountyHunterFlawlessBuff(target, bdata)",
    [StringComparison]::Ordinal)
$bountyHunterFlawlessExistingBuffReturn = $bountyHunterFlawlessCanApply.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$bountyHunterFlawlessActionPredicate = Get-BracedBlock $combatBase `
    "public static boolean isRetiredPostNgeBountyHunterPlayerAction(obj_id self, String actionName)"
Assert-Contract ($bountyHunterFlawlessInventoryNames.Count -eq
        [int]$contract.expected.retainedNgeBountyHunterFlawlessBuffRows -and
    (($bountyHunterFlawlessInventoryNames | Sort-Object) -join ([char]0)) -ceq
        (($bountyHunterFlawlessBuffNames | Sort-Object) -join ([char]0)) -and
    $bountyHunterFlawlessModifierInventoryNames.Count -eq
        [int]$contract.expected.retiredNgePlayerBountyHunterFlawlessModifiers -and
    (($bountyHunterFlawlessModifierInventoryNames | Sort-Object) -join ([char]0)) -ceq
        (($bountyHunterFlawlessModifierNames | Sort-Object) -join ([char]0)) -and
    $bountyHunterFlawlessActionInventoryNames.Count -eq
        [int]$contract.expected.retiredNgePlayerBountyHunterFlawlessActions -and
    (($bountyHunterFlawlessActionInventoryNames | Sort-Object) -join ([char]0)) -ceq
        (($bountyHunterFlawlessActionNames | Sort-Object) -join ([char]0)) -and
    $bountyHunterFlawlessEffectPredicate.Contains(
        'effectName.equals("bh_flawless_proc_chance")') -and
    -not $bountyHunterFlawlessEffectPredicate.Contains("startsWith") -and
    $bountyHunterFlawlessBuffPredicate.Contains("!isPlayer(target)") -and
    $bountyHunterFlawlessBuffPredicate.Contains(
        "isRetiredPostNgePlayerBountyHunterFlawlessBuffName(data.buffName)") -and
    $bountyHunterFlawlessBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $bountyHunterFlawlessBuffPredicate.Contains(
        "isRetiredPostNgePlayerBountyHunterFlawlessEffect(getEffectParam(data, effect))") -and
    $bountyHunterFlawlessResidueCleanup.Contains("!isPlayer(player)") -and
    $bountyHunterFlawlessResidueCleanup.Contains(
        'removeBuff(player, "bh_flawless_proc_chance_1")') -and
    $bountyHunterFlawlessResidueCleanup.Contains(
        "removeAttribOrSkillModModifier(player, retiredModifier)") -and
    $bountyHunterFlawlessResidueCleanup.Contains(
        "applySkillStatisticModifier(player, retiredModifier, -currentValue)") -and
    $bountyHunterFlawlessResidueCleanup.Contains("revokeCommand(player, retiredAction)") -and
    $bountyHunterFlawlessStateCleanup.Contains("!isPlayer(player)") -and
    $bountyHunterFlawlessStateCleanup.Contains(
        "RETIRED_POST_NGE_PLAYER_BOUNTY_HUNTER_FLAWLESS_BUFFS") -and
    $bountyHunterFlawlessStateCleanup.Contains("removeBuff(player, retiredBuff)") -and
    $bountyHunterFlawlessStateCleanup.Contains(
        "clearPostNgePlayerBountyHunterFlawlessResidue(player);") -and
    $bountyHunterFlawlessProgressionCleanup.Contains(
        "retirePostNgePlayerBountyHunterFlawlessState(player);") -and
    $bountyHunterFlawlessAdmissionGate -ge 0 -and
    $bountyHunterFlawlessExistingBuffReturn -gt $bountyHunterFlawlessAdmissionGate -and
    $bountyHunterFlawlessActionPredicate.Contains("isPlayer(self)") -and
    $bountyHunterFlawlessActionPredicate.Contains('actionName.startsWith("bh_")') -and
    @($bountyHunterFlawlessSetBonusActions | Where-Object {
        $bountyHunterFlawlessActionPredicate.Contains('actionName.equals("' + $_ + '")')
    }).Count -eq $bountyHunterFlawlessSetBonusActions.Count -and
    $combatBase.Contains(
        "isRetiredPostNgeBountyHunterPlayerAction(self, actionName)") -and
    -not [bool]$contract.expected.playerNgeBountyHunterFlawlessBuffAdmissionReachable -and
    -not [bool]$contract.expected.playerNgeBountyHunterFlawlessActionsReachable -and
    [bool]$contract.expected.persistedPlayerNgeBountyHunterFlawlessStateRemoved) `
    "p14.combat-expertise-isolation.bounty-hunter-flawless.admission-state-and-actions-fail-closed"

$bountyHunterFlawlessHandlerSpecs = @(
    [pscustomobject]@{ Method = "bhFlawlessAddBuffHandler"; Cleanup = "buff.retirePostNgePlayerBountyHunterFlawlessState(self);"; Retained = 'buff.applyBuff(self, "bh_flawless_proc_chance_1")' },
    [pscustomobject]@{ Method = "bhFlawlessRemoveBuffHandler"; Cleanup = "buff.clearPostNgePlayerBountyHunterFlawlessResidue(self);"; Retained = 'buff.removeBuff(self, "bh_flawless_proc_chance_1")' }
)
$bountyHunterFlawlessGuardedHandlers = 0
foreach ($handlerSpec in $bountyHunterFlawlessHandlerSpecs)
{
    $handlerBlock = Get-BracedBlock $buffHandler ("public int {0}(" -f $handlerSpec.Method)
    $playerIndex = $handlerBlock.IndexOf("isPlayer(self)", [StringComparison]::Ordinal)
    $effectIndex = $handlerBlock.IndexOf(
        "buff.isRetiredPostNgePlayerBountyHunterFlawlessEffect(effectName)",
        [StringComparison]::Ordinal)
    $nameIndex = $handlerBlock.IndexOf(
        "buff.isRetiredPostNgePlayerBountyHunterFlawlessBuffName(buffName)",
        [StringComparison]::Ordinal)
    $cleanupIndex = $handlerBlock.IndexOf([string]$handlerSpec.Cleanup,
        [StringComparison]::Ordinal)
    $overrideIndex = $handlerBlock.IndexOf("return SCRIPT_OVERRIDE;", $cleanupIndex,
        [StringComparison]::Ordinal)
    $retainedIndex = $handlerBlock.IndexOf([string]$handlerSpec.Retained,
        [StringComparison]::Ordinal)
    if ($playerIndex -ge 0 -and $effectIndex -gt $playerIndex -and
        $nameIndex -gt $playerIndex -and $cleanupIndex -gt $nameIndex -and
        $overrideIndex -gt $cleanupIndex -and $retainedIndex -gt $overrideIndex)
    {
        ++$bountyHunterFlawlessGuardedHandlers
    }
}
Assert-Contract ($bountyHunterFlawlessGuardedHandlers -eq
        [int]$contract.expected.productionBountyHunterFlawlessHandlersGuarded -and
    [bool]$contract.expected.nonPlayerNgeBountyHunterFlawlessCompatibilityPreserved) `
    "p14.combat-expertise-isolation.bounty-hunter-flawless.two-handlers-player-fail-closed"

$elementalVulnerabilityEffects = @(
    "dt_vulnerability_acid",
    "dt_vulnerability_cold",
    "dt_vulnerability_electricity",
    "dt_vulnerability_exclusive_acid",
    "dt_vulnerability_exclusive_cold",
    "dt_vulnerability_exclusive_electricity",
    "dt_vulnerability_exclusive_heat",
    "dt_vulnerability_heat"
)
$elementalVulnerabilityMappings = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { $elementalVulnerabilityEffects -ccontains [string]$_.NAME })
$elementalVulnerabilityBuffRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object {
        $row = $_
        @(1..5 | Where-Object {
            $elementalVulnerabilityEffects -ccontains
                [string]$row.("EFFECT$($_)_PARAM")
        }).Count -gt 0
    })
$elementalVulnerabilitySignatures = @($elementalVulnerabilityBuffRows |
    ForEach-Object {
        @(
            [string]$_.NAME,
            [string]$_.DURATION,
            [string]$_.DEBUFF,
            [string]$_.IS_PERSISTENT,
            [string]$_.EFFECT1_PARAM,
            [string]$_.EFFECT1_VALUE
        ) -join "|"
    } | Sort-Object)
$expectedElementalVulnerabilitySignatures = @(
    "acid_aspect|-1|0|1|dt_vulnerability_exclusive_electricity|100",
    "caretaker_blast|30|1|1|dt_vulnerability_electricity|2",
    "closed_fist_burn_debuff_1|60|1|1|dt_vulnerability_heat|2",
    "closed_fist_burn_debuff_2|60|1|1|dt_vulnerability_heat|4",
    "closed_fist_burn_debuff_3|60|1|1|dt_vulnerability_heat|8",
    "cold_aspect|-1|0|1|dt_vulnerability_exclusive_heat|100",
    "elec_aspect|-1|0|1|dt_vulnerability_exclusive_acid|100",
    "heat_aspect|-1|0|1|dt_vulnerability_exclusive_cold|100",
    "kun_wrath_ward_acid|10|0|1|dt_vulnerability_acid|0.1",
    "kun_wrath_ward_cold|10|0|1|dt_vulnerability_cold|0.1",
    "kun_wrath_ward_electrical|10|0|1|dt_vulnerability_electricity|0.1",
    "kun_wrath_ward_heat|10|0|1|dt_vulnerability_heat|0.1"
) | Sort-Object
Assert-Contract ($elementalVulnerabilityMappings.Count -eq
        [int]$contract.expected.retainedNgeElementalVulnerabilityEffectMappingRows -and
    @($elementalVulnerabilityMappings | Where-Object {
        [string]$_.TYPE -ceq "vulnerability" -and
        [string]$_.SUBTYPE -ceq [string]$_.NAME
    }).Count -eq $elementalVulnerabilityMappings.Count -and
    @($elementalVulnerabilityMappings | Select-Object -ExpandProperty NAME -Unique).Count -eq
        $elementalVulnerabilityEffects.Count -and
    @($elementalVulnerabilityEffects | Where-Object {
        @($elementalVulnerabilityMappings.NAME) -ccontains $_
    }).Count -eq $elementalVulnerabilityEffects.Count -and
    $elementalVulnerabilityBuffRows.Count -eq
        [int]$contract.expected.retainedNgeElementalVulnerabilityBuffRows -and
    (($elementalVulnerabilitySignatures -join "`n") -ceq
        ($expectedElementalVulnerabilitySignatures -join "`n"))) `
    "p14.combat-expertise-isolation.buff.elemental-vulnerability-data-inventory-authenticated"

$elementalVulnerabilityEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerElementalVulnerabilityEffect(String effectName)"
$elementalVulnerabilityBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerElementalVulnerabilityBuff(obj_id target, buff_data data)"
$elementalVulnerabilityClear = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerElementalVulnerabilityState(obj_id player)"
$elementalVulnerabilityCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerElementalVulnerabilityState(obj_id player)"
$elementalVulnerabilityProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$elementalVulnerabilityAdmission = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$elementalVulnerabilityAdmissionGate = $elementalVulnerabilityAdmission.IndexOf(
    "isRetiredPostNgePlayerElementalVulnerabilityBuff(target, bdata)",
    [StringComparison]::Ordinal)
$elementalVulnerabilityExistingBuffReturn = $elementalVulnerabilityAdmission.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_EFFECT_PREFIX = "dt_vulnerability_"') -and
    $buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_STATE = "elemental_vulnerability"') -and
    $elementalVulnerabilityEffectPredicate.Contains(
        "RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_EFFECT_PREFIX") -and
    $elementalVulnerabilityEffectPredicate.Contains("effectName.startsWith") -and
    $elementalVulnerabilityBuffPredicate.Contains("!isPlayer(target)") -and
    $elementalVulnerabilityBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $elementalVulnerabilityBuffPredicate.Contains(
        "isRetiredPostNgePlayerElementalVulnerabilityEffect(getEffectParam(data, effect))") -and
    $elementalVulnerabilityClear.Contains("!isPlayer(player)") -and
    $elementalVulnerabilityClear.Contains(
        "utils.removeScriptVarTree(player, RETIRED_POST_NGE_PLAYER_ELEMENTAL_VULNERABILITY_STATE);") -and
    $elementalVulnerabilityCleanup.Contains("getAllBuffs(player)") -and
    $elementalVulnerabilityCleanup.Contains("combat_engine.getBuffData(activeBuff)") -and
    $elementalVulnerabilityCleanup.Contains("removeBuff(player, activeBuff)") -and
    $elementalVulnerabilityCleanup.Contains(
        "clearPostNgePlayerElementalVulnerabilityState(player);") -and
    $elementalVulnerabilityProgressionCleanup.Contains(
        "retirePostNgePlayerElementalVulnerabilityState(player);") -and
    $elementalVulnerabilityAdmissionGate -ge 0 -and
    $elementalVulnerabilityExistingBuffReturn -gt $elementalVulnerabilityAdmissionGate -and
    -not [bool]$contract.expected.playerNgeElementalVulnerabilityBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeElementalVulnerabilityStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeElementalVulnerabilityScriptVarsRemoved -and
    [bool]$contract.expected.nonPlayerNgeElementalVulnerabilityCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.elemental-vulnerability-admission-and-persistence-fail-closed"

$elementalVulnerabilityAdd = Get-BracedBlock $buffHandler `
    "public int vulnerabilityAddBuffHandler("
$elementalVulnerabilityRemove = Get-BracedBlock $buffHandler `
    "public int vulnerabilityRemoveBuffHandler("
$elementalVulnerabilityAddGuard = $elementalVulnerabilityAdd.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$elementalVulnerabilityAddCleanup = $elementalVulnerabilityAdd.IndexOf(
    "buff.retirePostNgePlayerElementalVulnerabilityState(self);",
    [StringComparison]::Ordinal)
$elementalVulnerabilityAddReturn = $elementalVulnerabilityAdd.IndexOf(
    "return SCRIPT_OVERRIDE;", $elementalVulnerabilityAddCleanup,
    [StringComparison]::Ordinal)
$elementalVulnerabilityAddWriter = $elementalVulnerabilityAdd.IndexOf(
    'utils.setScriptVar(self, "elemental_vulnerability.type_" + type, type);',
    [StringComparison]::Ordinal)
$elementalVulnerabilityRemoveGuard = $elementalVulnerabilityRemove.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$elementalVulnerabilityRemoveCleanup = $elementalVulnerabilityRemove.IndexOf(
    "buff.clearPostNgePlayerElementalVulnerabilityState(self);",
    [StringComparison]::Ordinal)
$elementalVulnerabilityRemoveReturn = $elementalVulnerabilityRemove.IndexOf(
    "return SCRIPT_OVERRIDE;", $elementalVulnerabilityRemoveCleanup,
    [StringComparison]::Ordinal)
$elementalVulnerabilityRemoveWriter = $elementalVulnerabilityRemove.IndexOf(
    'utils.removeScriptVar(self, "elemental_vulnerability.type_" + type);',
    [StringComparison]::Ordinal)
$elementalVulnerabilityConsumer = Get-BracedBlock $combatBase `
    "public void doWrappedDamage(obj_id attacker, obj_id defender, weapon_data weaponData, hit_result hitData, combat_data actionData, int overloadDamage)"
$elementalVulnerabilityConsumerGuard = $elementalVulnerabilityConsumer.IndexOf(
    'if (isPlayer(defender) && utils.hasScriptVarTree(defender, "elemental_vulnerability"))',
    [StringComparison]::Ordinal)
$elementalVulnerabilityConsumerCleanup = $elementalVulnerabilityConsumer.IndexOf(
    "buff.retirePostNgePlayerElementalVulnerabilityState(defender);",
    [StringComparison]::Ordinal)
$elementalVulnerabilityFirstRead = $elementalVulnerabilityConsumer.IndexOf(
    'utils.hasScriptVar(defender, "elemental_vulnerability.type_heat")',
    [StringComparison]::Ordinal)
$guardedElementalVulnerabilityReads = ([regex]::Matches(
        $elementalVulnerabilityConsumer,
        'if \(!isPlayer\(defender\) && utils\.hasScriptVar\(defender, "elemental_vulnerability\.type_(?:heat|electrical|cold|acid)"\)\)')).Count
Assert-Contract ($elementalVulnerabilityAddGuard -ge 0 -and
    $elementalVulnerabilityAddCleanup -gt $elementalVulnerabilityAddGuard -and
    $elementalVulnerabilityAddReturn -gt $elementalVulnerabilityAddCleanup -and
    $elementalVulnerabilityAddWriter -gt $elementalVulnerabilityAddReturn -and
    $elementalVulnerabilityRemoveGuard -ge 0 -and
    $elementalVulnerabilityRemoveCleanup -gt $elementalVulnerabilityRemoveGuard -and
    $elementalVulnerabilityRemoveReturn -gt $elementalVulnerabilityRemoveCleanup -and
    $elementalVulnerabilityRemoveWriter -gt $elementalVulnerabilityRemoveReturn -and
    $elementalVulnerabilityConsumerGuard -ge 0 -and
    $elementalVulnerabilityConsumerCleanup -gt $elementalVulnerabilityConsumerGuard -and
    $elementalVulnerabilityFirstRead -gt $elementalVulnerabilityConsumerCleanup -and
    $guardedElementalVulnerabilityReads -eq 4 -and
    ([regex]::Matches($elementalVulnerabilityAdd,
        'utils\.setScriptVar\(self, "elemental_vulnerability\.type_')).Count -eq 3 -and
    [int]$contract.expected.productionElementalVulnerabilityHandlersGuarded -eq 2 -and
    [int]$contract.expected.productionElementalVulnerabilityConsumersGuarded -eq 1 -and
    -not [bool]$contract.expected.playerNgeElementalVulnerabilityDamageMutationReachable -and
    [bool]$contract.expected.nonPlayerNgeElementalVulnerabilityCompatibilityPreserved) `
    "p14.combat-expertise-isolation.buff.elemental-vulnerability-handlers-and-damage-consumer-player-fail-closed"

$medicDeferredDotProcActions = @(
    "expertise_dueterium_rounds_proc",
    "expertise_poison_knuckle_proc"
)
$medicDeferredDotProcCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object { $medicDeferredDotProcActions -ccontains [string]$_.commandName })
$medicDeferredDotProcCombatRows = @(Import-SwgTab -Path $paths.combatData |
    Where-Object { $medicDeferredDotProcActions -ccontains [string]$_.actionName })
$medicDeferredDotProcRows = @(Import-SwgTab -Path $paths.procTable |
    Where-Object { $medicDeferredDotProcActions -ccontains [string]$_.procString })
$medicDeferredDotProcSkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object { [string]$_.NAME -cmatch '^expertise_me_(dueterium_rounds|poison_knuckle)_1$' })
$medicDeferredDotProcHandlers = @([regex]::Matches($combatActions,
        'public int expertise_(?:dueterium_rounds|poison_knuckle)_proc\('))
$precuCombatMedicDotCommands = @("applyPoison", "applyDisease")
$precuCombatMedicDotCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object { $precuCombatMedicDotCommands -ccontains [string]$_.commandName })
$precuCombatMedicDotSkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object { @(
        "science_combatmedic_novice",
        "science_combatmedic_healing_range_02"
    ) -ccontains [string]$_.NAME })
Assert-Contract ($medicDeferredDotProcCommandRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDeferredDotProcCommandRows -and
    @($medicDeferredDotProcCommandRows | Where-Object {
        [string]$_.scriptHook -ceq [string]$_.commandName -and
        [string]$_.failScriptHook -ceq "failProc" -and
        [string]$_.displayGroup -ceq "combat" -and
        [string]$_.addToCombatQueue -ceq "0" -and
        [string]$_.toolbarOnly -ceq "1" -and
        [string]$_.fromServerOnly -ceq "1"
    }).Count -eq $medicDeferredDotProcCommandRows.Count -and
    $medicDeferredDotProcCombatRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDeferredDotProcCombatRows -and
    @($medicDeferredDotProcCombatRows | Where-Object {
        [string]$_.commandType -ceq "LEFT_CLICK_DEFAULT" -and
        [string]$_.validTarget -ceq "STANDARD" -and
        [string]$_.hitType -ceq "ATTACK" -and
        [string]$_.percentAddFromWeapon -ceq "0.55" -and
        [string]$_.dotIntensity -ceq "0" -and
        [string]$_.dotDuration -ceq "6" -and
        [string]$_.specialLine -ceq "no_proc"
    }).Count -eq $medicDeferredDotProcCombatRows.Count -and
    @($medicDeferredDotProcCombatRows | Where-Object {
        [string]$_.actionName -ceq "expertise_dueterium_rounds_proc" -and
        [string]$_.comments -ceq "Medic:ProcFireDoT" -and
        [string]$_.dotType -ceq "fire"
    }).Count -eq 1 -and
    @($medicDeferredDotProcCombatRows | Where-Object {
        [string]$_.actionName -ceq "expertise_poison_knuckle_proc" -and
        [string]$_.comments -ceq "Medic:ProcPoisonDoT" -and
        [string]$_.dotType -ceq "poison"
    }).Count -eq 1 -and
    $medicDeferredDotProcRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDeferredDotProcRows -and
    @($medicDeferredDotProcRows | Where-Object {
        [string]$_.procChance -ceq "5" -and
        [string]$_.explanation -ceq "Medic expertise proc"
    }).Count -eq $medicDeferredDotProcRows.Count -and
    $medicDeferredDotProcSkillRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDeferredDotProcExpertiseSkillRows -and
    @($medicDeferredDotProcSkillRows | Where-Object {
        [string]$_.NAME -ceq "expertise_me_dueterium_rounds_1" -and
        [string]$_.SKILL_MODS -ceq "expertise_dueterium_rounds_proc=5"
    }).Count -eq 1 -and
    @($medicDeferredDotProcSkillRows | Where-Object {
        [string]$_.NAME -ceq "expertise_me_poison_knuckle_1" -and
        [string]$_.SKILL_MODS -ceq "expertise_poison_knuckle_proc=5"
    }).Count -eq 1 -and
    $medicDeferredDotProcHandlers.Count -eq
        [int]$contract.expected.retainedNgeMedicDeferredDotProcActionHandlers -and
    $precuCombatMedicDotCommandRows.Count -eq
        [int]$contract.expected.precuCombatMedicDotCommandsPreserved -and
    $precuCombatMedicDotSkillRows.Count -eq 2 -and
    @($precuCombatMedicDotSkillRows | Where-Object {
        [string]$_.NAME -ceq "science_combatmedic_novice" -and
        [string]$_.COMMANDS -match '(^|,)applyPoison(,|$)'
    }).Count -eq 1 -and
    @($precuCombatMedicDotSkillRows | Where-Object {
        [string]$_.NAME -ceq "science_combatmedic_healing_range_02" -and
        [string]$_.COMMANDS -match '(^|,)applyDisease(,|$)'
    }).Count -eq 1) `
    "p14.combat-expertise-isolation.medic-dot-proc-data-and-precu-continuity-authenticated"

$medicPlayerAction = Get-BracedBlock $combatBase `
    "public static boolean isRetiredPostNgeMedicPlayerAction(obj_id self, String actionName)"
$dueteriumRoundsHandler = Get-BracedBlock $combatActions `
    "public int expertise_dueterium_rounds_proc("
$poisonKnuckleHandler = Get-BracedBlock $combatActions `
    "public int expertise_poison_knuckle_proc("
$genericProcGate = $standardCombatAction.IndexOf(
    "proc.isRetiredPostNgePlayerProcAction(self, actionName)",
    [StringComparison]::Ordinal)
$medicActionGate = $standardCombatAction.IndexOf(
    "isRetiredPostNgeMedicPlayerAction(self, actionName)",
    [StringComparison]::Ordinal)
Assert-Contract ($medicPlayerAction.Contains('actionName.startsWith("me_")') -and
    $medicPlayerAction.Contains(
        'actionName.equals("expertise_dueterium_rounds_proc")') -and
    $medicPlayerAction.Contains(
        'actionName.equals("expertise_poison_knuckle_proc")') -and
    $standardCombatAction.Contains(
        "isRetiredPostNgeMedicPlayerAction(self, actionName)") -and
    $genericProcGate -ge 0 -and
    $medicActionGate -gt $genericProcGate -and
    $dueteriumRoundsHandler.Contains(
        'combatStandardAction("expertise_dueterium_rounds_proc"') -and
    $poisonKnuckleHandler.Contains(
        'combatStandardAction("expertise_poison_knuckle_proc"') -and
    -not [bool]$contract.expected.playerNgeMedicDeferredDotProcExecutionReachable -and
    [bool]$contract.expected.genericPlayerProcGateStillDominatesMedicOwnershipGate -and
    [bool]$contract.expected.nonPlayerNgeMedicDeferredDotProcCompatibilityPreserved) `
    "p14.combat-expertise-isolation.medic-dot-proc-player-action-admission-fail-closed"

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

$entertainerBuildabuffReactiveHealActions = @(
    "expertise_buildabuff_heal_1_reac",
    "expertise_buildabuff_heal_2_reac",
    "expertise_buildabuff_heal_3_reac"
)
$entertainerBuildabuffReactiveHealCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object {
        $entertainerBuildabuffReactiveHealActions -ccontains [string]$_.commandName
    })
$entertainerBuildabuffReactiveHealCombatRows = @(Import-SwgTab -Path $paths.combatData |
    Where-Object {
        $entertainerBuildabuffReactiveHealActions -ccontains [string]$_.actionName
    })
$entertainerBuildabuffReactiveHealProcRows = @(Import-SwgTab -Path $paths.procTable |
    Where-Object {
        $entertainerBuildabuffReactiveHealActions -ccontains [string]$_.procString
    })
$entertainerBuildabuffReactiveHealHandlers = @($entertainerBuildabuffReactiveHealActions |
    ForEach-Object { Get-BracedBlock $combatActions "public int $_(" })
$entertainerBuildabuffExpectedHeal = [ordered]@{
    "expertise_buildabuff_heal_1_reac" = "200"
    "expertise_buildabuff_heal_2_reac" = "400"
    "expertise_buildabuff_heal_3_reac" = "800"
}
$entertainerBuildabuffExpectedComment = [ordered]@{
    "expertise_buildabuff_heal_1_reac" = "Buildabuffreactiveheallvl10"
    "expertise_buildabuff_heal_2_reac" = "Buildabuffreactiveheallvl40"
    "expertise_buildabuff_heal_3_reac" = "Buildabuffreactiveheallvl70"
}
$entertainerBuildabuffExpectedExplanation = [ordered]@{
    "expertise_buildabuff_heal_1_reac" = "Buildabuff Reactive Heal (level 10)"
    "expertise_buildabuff_heal_2_reac" = "Buildabuff Reactive Heal (level 40)"
    "expertise_buildabuff_heal_3_reac" = "Buildabuff Reactive Heal (level 70)"
}
$precuEntertainerCoreSkillNames = @(
    "social_entertainer_novice", "social_entertainer_master",
    "social_dancer_novice", "social_dancer_master",
    "social_musician_novice", "social_musician_master"
)
$precuEntertainerCoreSkillRows = @(Import-SwgTab -Path $paths.skillsTable |
    Where-Object { $precuEntertainerCoreSkillNames -ccontains [string]$_.NAME })
$precuEntertainerCoreCommandHooks = [ordered]@{
    "startDance" = "cmdStartDance"
    "startMusic" = "cmdStartMusic"
    "stopDance" = "cmdStopDance"
    "stopMusic" = "cmdStopMusic"
    "flourish" = "cmdFlourish"
}
$precuEntertainerCoreCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object {
        $precuEntertainerCoreCommandHooks.Keys -ccontains [string]$_.commandName
    })
$precuEntertainerNovice = @($precuEntertainerCoreSkillRows |
    Where-Object { [string]$_.NAME -ceq "social_entertainer_novice" })
Assert-Contract ($entertainerBuildabuffReactiveHealCommandRows.Count -eq
        [int]$contract.expected.retainedNgeEntertainerBuildabuffReactiveHealCommandRows -and
    @($entertainerBuildabuffReactiveHealCommandRows | Where-Object {
        [string]$_.scriptHook -ceq [string]$_.commandName -and
        [string]$_.failScriptHook -ceq "failProc" -and
        [string]$_.displayGroup -ceq "combat" -and
        [string]$_.addToCombatQueue -ceq "0" -and
        [string]$_.cooldownGroup -ceq "reac_heal" -and
        [string]$_.cooldownTime -ceq "3" -and
        [string]$_.toolbarOnly -ceq "1" -and
        [string]$_.fromServerOnly -ceq "1"
    }).Count -eq $entertainerBuildabuffReactiveHealCommandRows.Count -and
    $entertainerBuildabuffReactiveHealCombatRows.Count -eq
        [int]$contract.expected.retainedNgeEntertainerBuildabuffReactiveHealCombatRows -and
    @($entertainerBuildabuffReactiveHealCombatRows | Where-Object {
        [string]$_.validTarget -ceq "NONE" -and
        [string]$_.hitType -ceq "HEAL" -and
        [string]$_.healAttrib -ceq "HEALTH" -and
        [string]$_.attackType -ceq "SINGLE_TARGET" -and
        [string]$_.percentAddFromWeapon -ceq "0" -and
        [string]$_.specialLine -ceq "no_proc" -and
        [string]$_.addedDamage -ceq
            [string]$entertainerBuildabuffExpectedHeal[[string]$_.actionName] -and
        [string]$_.comments -ceq
            [string]$entertainerBuildabuffExpectedComment[[string]$_.actionName]
    }).Count -eq $entertainerBuildabuffReactiveHealCombatRows.Count -and
    $entertainerBuildabuffReactiveHealProcRows.Count -eq
        [int]$contract.expected.retainedNgeEntertainerBuildabuffReactiveHealProcRows -and
    @($entertainerBuildabuffReactiveHealProcRows | Where-Object {
        [string]$_.procChance -ceq "8" -and
        [string]$_.explanation -ceq
            [string]$entertainerBuildabuffExpectedExplanation[[string]$_.procString]
    }).Count -eq $entertainerBuildabuffReactiveHealProcRows.Count -and
    $entertainerBuildabuffReactiveHealHandlers.Count -eq
        [int]$contract.expected.retainedNgeEntertainerBuildabuffReactiveHealActionHandlers -and
    @($entertainerBuildabuffReactiveHealHandlers | Where-Object {
        $_.Contains("combatStandardAction(")
    }).Count -eq $entertainerBuildabuffReactiveHealHandlers.Count -and
    $precuEntertainerCoreSkillRows.Count -eq
        [int]$contract.expected.precuEntertainerCoreSkillRowsPreserved -and
    $precuEntertainerCoreCommandRows.Count -eq
        [int]$contract.expected.precuEntertainerCoreCommandRowsPreserved -and
    @($precuEntertainerCoreCommandRows | Where-Object {
        [string]$_.scriptHook -ceq
            [string]$precuEntertainerCoreCommandHooks[[string]$_.commandName]
    }).Count -eq $precuEntertainerCoreCommandRows.Count -and
    $precuEntertainerNovice.Count -eq 1 -and
    [string]$precuEntertainerNovice[0].COMMANDS -match '(^|,)startDance(,|$)' -and
    [string]$precuEntertainerNovice[0].COMMANDS -match '(^|,)startMusic(,|$)' -and
    [string]$precuEntertainerNovice[0].COMMANDS -match '(^|,)flourish\+1(,|$)' -and
    [string]$precuEntertainerNovice[0].SKILL_MODS -match
        '(^|,)healing_dance_wound=5(,|$)' -and
    [string]$precuEntertainerNovice[0].SKILL_MODS -match
        '(^|,)healing_music_wound=5(,|$)') `
    "p14.combat-expertise-isolation.entertainer-buildabuff-reactive-heal-data-and-precu-continuity-authenticated"

$entertainerPlayerAction = Get-BracedBlock $combatBase `
    "public static boolean isRetiredPostNgeEntertainerPlayerAction(obj_id self, String actionName)"
$entertainerActionGate = $standardCombatAction.IndexOf(
    "isRetiredPostNgeEntertainerPlayerAction(self, actionName)",
    [StringComparison]::Ordinal)
$buildABuffRemove = Get-BracedBlock $buffHandler "public int buildabuffRemoveBuffHandler("
Assert-Contract ($entertainerPlayerAction.Contains('actionName.startsWith("en_")') -and
    $entertainerPlayerAction.Contains(
        'actionName.startsWith("expertise_buildabuff_")') -and
    $genericProcGate -ge 0 -and
    $entertainerActionGate -gt $genericProcGate -and
    $buildABuff.IndexOf("buff.isPostNgeBuffProgressionRetired()",
        [StringComparison]::Ordinal) -ge 0 -and
    $buildABuff.IndexOf("buff.isPostNgeBuffProgressionRetired()",
        [StringComparison]::Ordinal) -lt
        $buildABuff.IndexOf("performance.buildabuff.buffComponentKeys",
            [StringComparison]::Ordinal) -and
    @($entertainerBuildabuffReactiveHealActions | Where-Object {
        -not $buildABuff.Contains('addSkillModModifier(self, "' + $_ + '"') -or
        -not $buildABuffRemove.Contains(
            'removeAttribOrSkillModModifier(self, "' + $_ + '")')
    }).Count -eq 0 -and
    -not [bool]$contract.expected.playerNgeEntertainerBuildabuffReactiveHealExecutionReachable -and
    [bool]$contract.expected.genericPlayerProcGateStillDominatesEntertainerOwnershipGate -and
    [bool]$contract.expected.buildabuffModifierWriterStillFailsClosedBeforePlayerStateReads -and
    [bool]$contract.expected.nonPlayerNgeEntertainerBuildabuffReactiveHealCompatibilityPreserved) `
    "p14.combat-expertise-isolation.entertainer-buildabuff-reactive-heal-player-action-and-writer-fail-closed"

$medicDoomActions = @(
    "me_dm_dot_1", "me_dm_dot_2", "me_dm_dot_3", "me_dm_dot_4",
    "me_dm_dot_5", "me_dm_dot_6", "me_induce_insanity_1",
    "me_bacta_resistance_1", "me_electrolyte_drain_1",
    "me_traumatize_5", "me_thyroid_rupture_1"
)
$medicDoomCommandRows = @(Import-SwgTab -Path $paths.commandTable |
    Where-Object { $medicDoomActions -ccontains [string]$_.commandName })
$medicDoomCombatRows = @(Import-SwgTab -Path $paths.combatData |
    Where-Object { $medicDoomActions -ccontains [string]$_.actionName })
$medicDoomEffectRows = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object { [string]$_.NAME -ceq "me_doom" })
$medicDoomBuffRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object { [string]$_.NAME -ceq "me_doom" })
$medicDoomSetBonusRows = @(Import-SwgTab -Path $paths.buffTable |
    Where-Object { [string]$_.NAME -ceq "set_bonus_medic_utility_b_3" })
$medicDoomSkillModRows = @(Import-SwgTab -Path $paths.skillModListing |
    Where-Object { [string]$_.skill_mod -ceq "me_doom_chance" })
$medicDoomActionHandlers = @($medicDoomActions | ForEach-Object {
    [pscustomobject]@{
        Name = $_
        Text = Get-BracedBlock $combatActions "public int $_("
    }
})
Assert-Contract ($medicDoomCommandRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDoomCommandRows -and
    @($medicDoomCommandRows | Where-Object {
        [string]$_.scriptHook -ceq [string]$_.commandName -and
        [string]$_.displayGroup -ceq "combat" -and
        [string]$_.addToCombatQueue -ceq "1"
    }).Count -eq $medicDoomCommandRows.Count -and
    $medicDoomCombatRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDoomCombatRows -and
    @($medicDoomCombatRows | Where-Object {
        [string]$_.validTarget -ceq "STANDARD" -and
        [string]$_.attackType -ceq "SINGLE_TARGET" -and
        ([string]$_.specialLine -ceq "me_dot" -or
            [string]$_.specialLine -ceq "me_debuff")
    }).Count -eq $medicDoomCombatRows.Count -and
    $medicDoomEffectRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDoomEffectMappingRows -and
    [string]$medicDoomEffectRows[0].TYPE -ceq "meDoom" -and
    [string]$medicDoomEffectRows[0].SUBTYPE -ceq "me_doom" -and
    $medicDoomBuffRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDoomBuffRows -and
    [string]$medicDoomBuffRows[0].GROUP1 -ceq "meDoom" -and
    [string]$medicDoomBuffRows[0].DURATION -ceq "10" -and
    [string]$medicDoomBuffRows[0].EFFECT1_PARAM -ceq "me_doom" -and
    [string]$medicDoomBuffRows[0].EFFECT1_VALUE -ceq "1" -and
    [string]$medicDoomBuffRows[0].DEBUFF -ceq "1" -and
    [string]$medicDoomBuffRows[0].IS_PERSISTENT -ceq "1" -and
    $medicDoomSetBonusRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDoomSetBonusRows -and
    [string]$medicDoomSetBonusRows[0].EFFECT5_PARAM -ceq "me_doom_chance" -and
    [string]$medicDoomSetBonusRows[0].EFFECT5_VALUE -ceq "20" -and
    $medicDoomSkillModRows.Count -eq
        [int]$contract.expected.retainedNgeMedicDoomExpertiseSkillModRows -and
    [string]$medicDoomSkillModRows[0].profession -ceq "medic_1a" -and
    [string]$medicDoomSkillModRows[0].category -ceq "medic" -and
    [string]$medicDoomSkillModRows[0].comment -ceq "DOOM Chance" -and
    $medicDoomActionHandlers.Count -eq
        [int]$contract.expected.retainedNgeMedicDoomActionHandlers -and
    @($medicDoomActionHandlers | Where-Object {
        $combatGate = $_.Text.IndexOf(
            'combatStandardAction("' + $_.Name + '"',
            [StringComparison]::Ordinal)
        $doomCall = $_.Text.IndexOf("doDoom(self, target);",
            [StringComparison]::Ordinal)
        $combatGate -ge 0 -and $doomCall -gt $combatGate
    }).Count -eq $medicDoomActionHandlers.Count) `
    "p14.combat-expertise-isolation.medic-doom-data-and-action-routing-authenticated"

$medicDoomProc = Get-BracedBlock $combatActions `
    "public void doDoom(obj_id attacker, obj_id defender)"
$medicDoomPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerMedicDoomBuff(obj_id target, buff_data data)"
$medicDoomClear = Get-BracedBlock $buffLibrary `
    "public static void clearPostNgePlayerMedicDoomState(obj_id player)"
$medicDoomCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerMedicDoomState(obj_id player)"
$medicDoomProgressionCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgeBuffProgression(obj_id player)"
$medicDoomAdmission = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$medicDoomAdd = Get-BracedBlock $buffHandler `
    "public int meDoomAddBuffHandler("
$medicDoomRemove = Get-BracedBlock $buffHandler `
    "public int meDoomRemoveBuffHandler("
$medicDoomAttackerGuard = $medicDoomProc.IndexOf("isPlayer(attacker)",
    [StringComparison]::Ordinal)
$medicDoomDefenderGuard = $medicDoomProc.IndexOf("isPlayer(defender)",
    [StringComparison]::Ordinal)
$medicDoomChanceRead = $medicDoomProc.IndexOf('"me_doom_chance"',
    [StringComparison]::Ordinal)
$medicDoomAddGuard = $medicDoomAdd.IndexOf("isPlayer(self)",
    [StringComparison]::Ordinal)
$medicDoomAddStateRead = $medicDoomAdd.IndexOf('"me_doom.doom_owner"',
    [StringComparison]::Ordinal)
$medicDoomRemoveGuard = $medicDoomRemove.IndexOf("isPlayer(self)",
    [StringComparison]::Ordinal)
$medicDoomRemoveStateRead = $medicDoomRemove.IndexOf('"me_doom.doom_owner"',
    [StringComparison]::Ordinal)
Assert-Contract ($medicDoomPredicate.Contains("isPlayer(target)") -and
    $medicDoomPredicate.Contains(
        'RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_BUFF.equals(data.buffName)') -and
    $medicDoomClear.Contains(
        'removeScriptVarTree(player, RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_BUFF)') -and
    $medicDoomClear.Contains(
        'hasSkillModModifier(player, RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_MODIFIER)') -and
    $medicDoomClear.Contains(
        'removeAttribOrSkillModModifier(player, RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_MODIFIER)') -and
    $medicDoomCleanup.Contains(
        'removeBuff(player, RETIRED_POST_NGE_PLAYER_MEDIC_DOOM_BUFF)') -and
    $medicDoomCleanup.Contains("clearPostNgePlayerMedicDoomState(player)") -and
    $medicDoomProgressionCleanup.Contains(
        "retirePostNgePlayerMedicDoomState(player);") -and
    $medicDoomAdmission.Contains(
        "isRetiredPostNgePlayerMedicDoomBuff(target, bdata)") -and
    $medicDoomAttackerGuard -ge 0 -and
    $medicDoomDefenderGuard -gt $medicDoomAttackerGuard -and
    $medicDoomChanceRead -gt $medicDoomDefenderGuard -and
    $medicDoomProc.Contains("retirePostNgePlayerMedicDoomState(attacker)") -and
    $medicDoomProc.Contains("retirePostNgePlayerMedicDoomState(defender)") -and
    $medicDoomAddGuard -ge 0 -and
    $medicDoomAddStateRead -gt $medicDoomAddGuard -and
    $medicDoomAdd.Contains("retirePostNgePlayerMedicDoomState(self)") -and
    $medicDoomRemoveGuard -ge 0 -and
    $medicDoomRemoveStateRead -gt $medicDoomRemoveGuard -and
    $medicDoomRemove.Contains("clearPostNgePlayerMedicDoomState(self)") -and
    ([regex]::Matches($medicDoomAdd, "dot.applyDotEffect")).Count -eq 2 -and
    ([regex]::Matches($medicDoomRemove,
        'buff.applyBuff\(self, self, "me_doom", 10\.0f\)')).Count -eq 2 -and
    -not [bool]$contract.expected.playerNgeMedicDoomProcExecutionReachable -and
    -not [bool]$contract.expected.playerNgeMedicDoomBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerNgeMedicDoomStateRemoved -and
    [bool]$contract.expected.stalePlayerNgeMedicDoomModifierRemoved -and
    -not [bool]$contract.expected.playerNgeMedicDoomDelayedDotReachable -and
    [bool]$contract.expected.nonPlayerNgeMedicDoomCompatibilityPreserved) `
    "p14.combat-expertise-isolation.medic-doom-player-proc-buff-and-delayed-dot-fail-closed"

$dotStackEffectRows = @(Import-SwgTab -Path $paths.buffEffectMapping |
    Where-Object {
        [string]$_.TYPE -ceq "dotReduction" -or
        [string]$_.TYPE -ceq "dotDivisor"
    })
$dotStackEffectNames = @($dotStackEffectRows |
    Select-Object -ExpandProperty NAME -Unique)
$dotReductionEffectNames = @($dotStackEffectRows | Where-Object {
    [string]$_.TYPE -ceq "dotReduction"
} | Select-Object -ExpandProperty NAME -Unique)
$dotDivisorEffectNames = @($dotStackEffectRows | Where-Object {
    [string]$_.TYPE -ceq "dotDivisor"
} | Select-Object -ExpandProperty NAME -Unique)
$dotStackBuffRows = @(Import-SwgTab -Path $paths.buffTable | Where-Object {
    $row = $_
    @(1..5 | ForEach-Object { [string]$row.("EFFECT$($_)_PARAM") } |
        Where-Object {
            $_.StartsWith("dot_reduction_", [StringComparison]::Ordinal) -or
            $_.StartsWith("dot_divisor_", [StringComparison]::Ordinal)
        }).Count -gt 0
})
$expectedDotStackBuffNames = @($contract.expected.retainedDotStackMutationBuffNames)
Assert-Contract ($dotStackEffectRows.Count -eq
        [int]$contract.expected.retainedDotStackMutationEffectMappingRows -and
    $dotStackEffectNames.Count -eq
        [int]$contract.expected.retainedDotStackMutationEffectNames -and
    $dotReductionEffectNames.Count -eq
        [int]$contract.expected.retainedDotReductionEffectNames -and
    $dotDivisorEffectNames.Count -eq
        [int]$contract.expected.retainedDotDivisorEffectNames -and
    @($dotStackEffectRows | Group-Object NAME | Where-Object { $_.Count -ne 2 }).Count -eq 0 -and
    $dotStackBuffRows.Count -eq
        [int]$contract.expected.retainedDotStackMutationBuffRows -and
    ((@($dotStackBuffRows | Select-Object -ExpandProperty NAME | Sort-Object) -join "`n") -ceq
        (@($expectedDotStackBuffNames | Sort-Object) -join "`n"))) `
    "p14.combat-expertise-isolation.dot-stack-mutation-data-inventory-authenticated"

$dotStackEffectPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDotStackMutationEffect(String effectName)"
$dotStackBuffPredicate = Get-BracedBlock $buffLibrary `
    "public static boolean isRetiredPostNgePlayerDotStackMutationBuff(obj_id target, buff_data data)"
$dotStackCleanup = Get-BracedBlock $buffLibrary `
    "public static void retirePostNgePlayerDotStackMutationState(obj_id player)"
$dotStackAdmission = Get-BracedBlock $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$dotReductionHandler = Get-BracedBlock $buffHandler `
    "public int dotReductionAddBuffHandler(obj_id self, String effectName, String subtype, float duration, float value, String buffName, obj_id caster)"
$dotDivisorHandler = Get-BracedBlock $buffHandler `
    "public int dotDivisorAddBuffHandler(obj_id self, String effectName, String subtype, float duration, float value, String buffName, obj_id caster)"
$dotReductionGuard = $dotReductionHandler.IndexOf("if (isPlayer(self))",
    [StringComparison]::Ordinal)
$dotReductionMutation = $dotReductionHandler.IndexOf("buff.reduceBuffDotStackCount",
    [StringComparison]::Ordinal)
$dotDivisorGuard = $dotDivisorHandler.IndexOf("if (isPlayer(self))",
    [StringComparison]::Ordinal)
$dotDivisorMutation = $dotDivisorHandler.IndexOf("buff.divideBuffDotStackCount",
    [StringComparison]::Ordinal)
Assert-Contract ($buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_DOT_REDUCTION_EFFECT_PREFIX = "dot_reduction_"') -and
    $buffLibrary.Contains(
        'RETIRED_POST_NGE_PLAYER_DOT_DIVISOR_EFFECT_PREFIX = "dot_divisor_"') -and
    $dotStackBuffPredicate.Contains("isPlayer(target)") -and
    $dotStackBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $dotStackCleanup.Contains("getAllBuffs(player)") -and
    $dotStackCleanup.Contains("removeBuff(player, activeBuff)") -and
    $medicDoomProgressionCleanup.Contains(
        "retirePostNgePlayerDotStackMutationState(player);") -and
    $dotStackAdmission.Contains(
        "isRetiredPostNgePlayerDotStackMutationBuff(target, bdata)") -and
    $dotReductionGuard -ge 0 -and
    $dotReductionMutation -gt $dotReductionGuard -and
    $dotDivisorGuard -ge 0 -and
    $dotDivisorMutation -gt $dotDivisorGuard -and
    ([regex]::Matches($dotReductionHandler, "buff.reduceBuffDotStackCount")).Count -eq 9 -and
    ([regex]::Matches($dotDivisorHandler, "buff.divideBuffDotStackCount")).Count -eq 9 -and
    [int]$contract.expected.productionDotStackMutationHandlersGuarded -eq 2 -and
    -not [bool]$contract.expected.playerDotStackMutationBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerDotStackMutationStateRemoved -and
    -not [bool]$contract.expected.immediatePlayerDotStackMutationReachable -and
    [bool]$contract.expected.nonPlayerDotStackMutationCompatibilityPreserved) `
    "p14.combat-expertise-isolation.dot-stack-mutation-player-path-fails-closed"

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
        [string]$contract.buildEvidence.compiledClassSha256.combatActions -match '^[a-f0-9]{64}$' -and
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
