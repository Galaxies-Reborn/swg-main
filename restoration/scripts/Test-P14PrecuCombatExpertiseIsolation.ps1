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
$dictionaryCost = Get-BracedBlock $combatLibrary `
    "public static int[] getActionCost(obj_id self, weapon_data weaponData, dictionary actionData)"
$typedCost = Get-BracedBlock $combatLibrary `
    "public static int[] getActionCost(obj_id self, weapon_data weaponData, combat_data actionData)"
$successCost = Get-BracedBlock $combatLibrary `
    "public static int[] getSuccessBasedSingleTargetActionCost("
$hitEngine = Get-BracedBlock $combatBase `
    "public hit_result[] runHitEngine(attacker_data attackerData, weapon_data weaponData, defender_data[] defenderData, attacker_results attackerResults, defender_results[] defenderResults, combat_data actionData, boolean isTangibleAttacking, boolean isAutoAiming, int overloadDamage)"

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
Assert-Contract ($hitEngine.Contains("if (!precuAuthoritativeAttack)") -and
    $hitEngine.Contains("combat.getDevastationChance") -and
    $hitEngine.Contains("addPrecuCore3HateProcess") -and
    $hitEngine.Contains("combat.addHateProcess")) `
    "p14.combat-expertise-isolation.hit.damage-and-hate-era-gates-preserved"

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
$expertiseCleanup = Get-BracedBlock $buffHandler `
    "public void retireNgeExpertiseModifier(obj_id self, String effectName)"
Assert-Contract ($expertisePredicate.Contains('modifierName.startsWith("expertise_")') -and
    $expertiseCleanup.Contains("hasSkillModModifier(self, effectName)") -and
    $expertiseCleanup.Contains("removeAttribOrSkillModModifier(self, effectName)")) `
    "p14.combat-expertise-isolation.buff.central-cleanup-authority"

$genericExpertiseHandlers = @(
    (Get-BracedBlock $buffHandler "public int skillAddBuffHandler(")
    (Get-BracedBlock $buffHandler "public int skillPercentAddBuffHandler(")
    (Get-BracedBlock $buffHandler "public int forcePowerAddBuffHandler(")
)
$guardedGenericHandlers = @($genericExpertiseHandlers | Where-Object {
    $guard = $_.IndexOf("isRetiredNgeExpertiseModifier(subtype)", [StringComparison]::Ordinal)
    $cleanup = $_.IndexOf("retireNgeExpertiseModifier(self, effectName)", [StringComparison]::Ordinal)
    $writer = $_.IndexOf("addSkillModModifier", [StringComparison]::Ordinal)
    $guard -ge 0 -and $cleanup -gt $guard -and $writer -gt $guard
})
$percentHandler = $genericExpertiseHandlers[1]
Assert-Contract ($genericExpertiseHandlers.Count + 1 -eq
        [int]$contract.expected.productionExpertiseBuffWriterHandlersGuarded -and
    $guardedGenericHandlers.Count -eq 3 -and
    $percentHandler.IndexOf("isRetiredNgeExpertiseModifier(subtype)", [StringComparison]::Ordinal) -lt
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
