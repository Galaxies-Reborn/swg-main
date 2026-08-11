[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Build", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot "manifest.json"
    ) -Raw | ConvertFrom-Json
$contract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.p14ArmorMitigationOrdering
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$utf8NoBom = [Text.UTF8Encoding]::new($false)

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
        throw "Required armor-mitigation source is missing: $path"
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

function Get-TableRows
{
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $rows = @()
    foreach ($line in @($lines | Select-Object -Skip 2))
    {
        $values = $line -split "`t", -1
        $fields = @{}
        for ($index = 0; $index -lt $header.Count; ++$index)
        {
            $fields[$header[$index]] =
                if ($index -lt $values.Count) { $values[$index] } else { "" }
        }
        $rows += [pscustomobject]@{ Fields = $fields }
    }
    return @($rows)
}

function Get-TextSha256
{
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString(
            $sha.ComputeHash($utf8NoBom.GetBytes($Text))
        )).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BracedSurface
{
    param([string]$Text, [string]$Marker)
    $start = $Text.IndexOf($Marker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf('{', $start)
    if ($open -lt 0) { return "" }
    $depth = 1
    for ($index = $open + 1; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
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

function Get-OrdinalNames
{
    param($Values)
    $set = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    foreach ($value in @($Values))
    {
        if (-not [string]::IsNullOrWhiteSpace([string]$value))
        {
            [void]$set.Add([string]$value)
        }
    }
    $names = [string[]]@($set)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return @($names)
}

function Test-ExactOrdinalNames
{
    param($Actual, $Expected)
    $actualNames = @(Get-OrdinalNames $Actual)
    $expectedNames = @(Get-OrdinalNames $Expected)
    return $actualNames.Count -eq $expectedNames.Count -and
        (($actualNames -join "`n") -ceq ($expectedNames -join "`n"))
}

function Test-ForceTableFreshRecompile
{
    param([Parameter(Mandatory = $true)][string]$Container)
    $probe = @'
set -eu
tmp_dir="$(mktemp -d /dev/shm/precu-force-defense-iff.XXXXXX)"
cleanup() {
    case "${tmp_dir:-}" in
        /dev/shm/precu-force-defense-iff.*) ;;
        *) return 97 ;;
    esac
    resolved_tmp="$(readlink -f -- "$tmp_dir")"
    case "$resolved_tmp" in
        /dev/shm/precu-force-defense-iff.*) ;;
        *) return 98 ;;
    esac
    rm -rf -- "$resolved_tmp"
}
trap cleanup 0 HUP INT TERM
tool="$SWG_WORK_DIR/build/bin/DataTableTool"
test -x "$tool"
compile_and_compare() {
    source_tab="$1"
    canonical_iff="$2"
    relative_tab="$3"
    relative_iff="$4"
    temp_tab="$tmp_dir/dsrc/$relative_tab"
    fresh_iff="$tmp_dir/data/$relative_iff"
    mkdir -p -- "$(dirname "$temp_tab")" "$(dirname "$fresh_iff")"
    cp -- "$source_tab" "$temp_tab"
    (
        cd "$tmp_dir"
        PATH="$PATH:$SWG_WORK_DIR/build/bin" "$tool" \
            -i "dsrc/$relative_tab" \
            -- -s SharedFile \
            "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game" \
            "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game" \
            "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game"
    ) >/dev/null
    test -s "$fresh_iff"
    cmp -s "$fresh_iff" "$canonical_iff"
}
compile_and_compare \
    "$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab" \
    "$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/buff/buff.iff" \
    sku.0/sys.shared/compiled/game/datatables/buff/buff.tab \
    sku.0/sys.shared/compiled/game/datatables/buff/buff.iff
compile_and_compare \
    "$SWG_WORK_DIR/dsrc/sku.0/sys.server/compiled/game/datatables/jedi/jedi_actions.tab" \
    "$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game/datatables/jedi/jedi_actions.iff" \
    sku.0/sys.server/compiled/game/datatables/jedi/jedi_actions.tab \
    sku.0/sys.server/compiled/game/datatables/jedi/jedi_actions.iff
cleanup
trap - 0 HUP INT TERM
test ! -e "$tmp_dir"
'@
    $normalizedProbe = $probe.Replace("`r`n", "`n")
    $normalizedProbe | & docker exec -i $Container sh -c `
        "tr -d '\r' | sh -s" 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

$combat = Get-Content -LiteralPath $paths.combatLibrary -Raw
$jedi = Get-Content -LiteralPath $paths.jediLibrary -Raw
$combatActions = Get-Content -LiteralPath $paths.combatActions -Raw
$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$legacyCombat = Get-Content -LiteralPath $paths.legacyCombatBase -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$profileRows = @(Get-TableRows -Path $paths.weaponProfiles)
$buffLines = @(Get-Content -LiteralPath $paths.buffTable)
$jediActionLines = @(Get-Content -LiteralPath $paths.jediActions)

Write-Host "Publish 14.1 armor/mitigation ordering checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [double]$contract.semanticReference.conditionWearRatio -eq 0.2 -and
    [int]$contract.semanticReference.cdefArmorPiercing -eq 0 -and
    (@($contract.semanticReference.playerLayerOrder) -join ",") -ceq
        "Force Armor/Force Shield,personal shield generator," +
        "hit-location armor piece," +
        "food mitigate_damage,target HAM pool,wound roll") `
    -Name "p14.armor.core3.pinned-order-and-ratios"

Assert-Contract -Condition (
    $combat.Contains(
        "public static int selectPrecuHitLocationForPool(") -and
    $combat -match
        "HIT_LOCATION_BODY,\s+HIT_LOCATION_BODY" -and
    $combat.Contains("HIT_LOCATION_L_LEG") -and
    $combat.Contains("return HIT_LOCATION_HEAD;")) `
    -Name "p14.armor.runtime.pool-aligned-hit-locations"

Assert-Contract -Condition (
    $combat.Contains("obj_id psg = getPsgArmor(defender);") -and
    $combat.IndexOf("obj_id psg = getPsgArmor(defender);") -lt
        $combat.IndexOf(
            "obj_id armorPiece = getArmorPieceHit(defender, hitData.hitLocation);") -and
    $combat.Contains("Math.pow(1.25f, difference)") -and
    $combat.Contains("Math.pow(0.50f, difference)") -and
    $combat.Contains("incomingDamage * 0.20f")) `
    -Name "p14.armor.runtime.psg-piece-rating-and-condition-order"

$force = $contract.forceDefenseContract
$sourceHashMap = [ordered]@{
    "combat.java" = $paths.combatLibrary
    "jedi.java" = $paths.jediLibrary
    "combat_actions.java" = $paths.combatActions
    "combat_base.java" = $paths.combatBase
    "buff.tab" = $paths.buffTable
    "jedi_actions.tab" = $paths.jediActions
}
$sourceHashesExact = $true
foreach ($entry in $sourceHashMap.GetEnumerator())
{
    $sourceHashesExact = $sourceHashesExact -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).
            Hash.ToLowerInvariant() -ceq
            [string]$force.sourceSha256.($entry.Key)
}
$dsrcCommit = (& git -C (Join-Path $source "dsrc") rev-parse HEAD 2>$null |
    Out-String).Trim()
Assert-Contract -Condition ($sourceHashesExact -and
    $dsrcCommit -ceq [string]$force.directSourceCommit) `
    -Name "p14.armor.force-defense.direct-source-authenticated"

$callbacksExact = $true
foreach ($rank in $force.ranks)
{
    $command = [string]$rank.command
    $body = Get-BracedSurface $combatActions (
        "public int $command(obj_id self, obj_id target, String params, " +
        "float defaultTime)")
    $delegate = 'jedi.performPrecuForceDefenseCommand(self, "' + $command + '")'
    $delegateIndex = $body.IndexOf($delegate, [StringComparison]::Ordinal)
    $overrideIndex = $body.IndexOf(
        "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
    $continueIndex = $body.IndexOf(
        "return SCRIPT_CONTINUE;", [StringComparison]::Ordinal)
    $callbacksExact = $callbacksExact -and
        -not [string]::IsNullOrWhiteSpace($body) -and
        ([regex]::Matches($body, [regex]::Escape($delegate))).Count -eq 1 -and
        $delegateIndex -ge 0 -and
        $overrideIndex -gt $delegateIndex -and
        $continueIndex -gt $overrideIndex
}
Assert-Contract -Condition $callbacksExact `
    -Name "p14.armor.force-defense.four-exact-direct-callbacks"

$activation = Get-BracedSurface $jedi `
    "public static boolean performPrecuForceDefenseCommand("
$toggleIndex = $activation.IndexOf(
    "if (buff.hasBuff(player, buffName))", [StringComparison]::Ordinal)
$deadIndex = $activation.IndexOf(
    "if (isDead(player) || isIncapacitated(player))",
    [StringComparison]::Ordinal)
$armorIndex = $activation.IndexOf(
    "utils.getIntScriptVar(player, armor.SCRIPTVAR_ARMOR_COUNT)",
    [StringComparison]::Ordinal)
$tierIndex = $activation.IndexOf(
    "if (!rankTwo && buff.hasBuff(player, higherBuffName))",
    [StringComparison]::Ordinal)
$forceIndex = $activation.IndexOf(
    "if (getForcePower(player) < forceCost)",
    [StringComparison]::Ordinal)
Assert-Contract -Condition (
    $toggleIndex -ge 0 -and $toggleIndex -lt $deadIndex -and
    $deadIndex -lt $armorIndex -and $armorIndex -lt $tierIndex -and
    $tierIndex -lt $forceIndex -and
    -not $activation.Contains("getForcePower(player) <= forceCost") -and
    $activation.Contains("boolean hadLowerBuff = rankTwo &&") -and
    $activation.Contains(
        "!isIdValid(player) || !exists(player) || !isPlayer(player)") -and
    $activation.Contains("buff.applyBuff(player, player, buffName, duration, buffStrength)") -and
    $activation.Contains("baseStrength + (int)((controlModifier * frsBuffModifier) + 0.5f)") -and
    $activation.Contains("alterForcePower(player, -forceCost)")) `
    -Name "p14.armor.force-defense.activation-toggle-tier-force-and-frs-order"

$derivedLocalizationKeys = @($force.ranks | ForEach-Object {
    $lower = ([string]$_.command).ToLowerInvariant()
    "apply_$lower"
    "remove_$lower"
})
Assert-Contract -Condition (
    (Test-ExactOrdinalNames $derivedLocalizationKeys `
        $force.activation.localizationKeys) -and
    ([regex]::Matches($activation, [regex]::Escape(
        '"jedi_spam", "apply_" + commandName.toLowerCase()'))).Count -eq 1 -and
    ([regex]::Matches($activation, [regex]::Escape(
        '"jedi_spam", "remove_" + commandName.toLowerCase()'))).Count -eq 1) `
    -Name "p14.armor.force-defense.exact-numbered-localization-keys"

Assert-Contract -Condition (
    $jedi.Contains("PRECU_FORCE_DEFENSE_1_COST = 75") -and
    $jedi.Contains("PRECU_FORCE_DEFENSE_2_COST = 150") -and
    $jedi.Contains("PRECU_FORCE_DEFENSE_1_DURATION = 900.0f") -and
    $jedi.Contains("PRECU_FORCE_DEFENSE_2_DURATION = 1800.0f") -and
    $jedi.Contains("PRECU_FORCE_DEFENSE_1_STRENGTH = 25") -and
    $jedi.Contains("PRECU_FORCE_DEFENSE_2_STRENGTH = 45") -and
    $jedi.Contains("PRECU_FORCE_DEFENSE_1_FRS_BUFF_MODIFIER = 0.25f") -and
    $jedi.Contains("PRECU_FORCE_DEFENSE_2_FRS_BUFF_MODIFIER = 0.35f") -and
    $jedi.Contains("PRECU_FORCE_DEFENSE_FRS_DRAIN_MODIFIER = -0.003f")) `
    -Name "p14.armor.force-defense.exact-rank-and-frs-constants"

$buffRows = @(Get-TableRows -Path $paths.buffTable)
$jediActionRows = @(Get-TableRows -Path $paths.jediActions)
$rankRowsExact = $true
foreach ($rank in $force.ranks)
{
    $buffRaw = @($buffLines | Where-Object {
        ($_ -split "`t", 2)[0] -ceq [string]$rank.buff
    })
    $actionRaw = @($jediActionLines | Where-Object {
        ($_ -split "`t", 2)[0] -ceq [string]$rank.buff
    })
    $buffRow = @($buffRows | Where-Object {
        [string]$_.Fields["NAME"] -ceq [string]$rank.buff
    })
    $actionRow = @($jediActionRows | Where-Object {
        [string]$_.Fields["actionName"] -ceq [string]$rank.buff
    })
    $rankRowsExact = $rankRowsExact -and
        $buffRaw.Count -eq 1 -and
        ($buffRaw[0] -split "`t", -1).Count -eq 34 -and
        (Get-TextSha256 $buffRaw[0]) -ceq [string]$rank.buffRowSha256 -and
        $actionRaw.Count -eq 1 -and
        ($actionRaw[0] -split "`t", -1).Count -eq 45 -and
        (Get-TextSha256 $actionRaw[0]) -ceq [string]$rank.actionRowSha256 -and
        $buffRow.Count -eq 1 -and $actionRow.Count -eq 1 -and
        [int]$buffRow[0].Fields["PRIORITY"] -eq [int]$rank.rank -and
        [int]$buffRow[0].Fields["DURATION"] -eq [int]$rank.durationSeconds -and
        [int]$buffRow[0].Fields["EFFECT1_VALUE"] -eq
            [int]$rank.protectionPercent -and
        [int]$buffRow[0].Fields["IS_PERSISTENT"] -eq 1 -and
        [int]$actionRow[0].Fields["intJediPowerCost"] -eq
            [int]$rank.activationCost -and
        [double]$actionRow[0].Fields["extraForceCost"] -eq
            [double]$rank.extraForceCost -and
        [string]$actionRow[0].Fields["buffName"] -ceq [string]$rank.buff -and
        [int]$actionRow[0].Fields["buffAmount1"] -eq
            [int]$rank.protectionPercent
}
Assert-Contract -Condition $rankRowsExact `
    -Name "p14.armor.force-defense.exact-persistent-buff-and-drain-rows"

$classification = Get-BracedSurface $jedi `
    "public static boolean isPrecuForceAttackAction("
$classifiedNames = @([regex]::Matches(
    $classification,
    'case "(?<name>[A-Za-z0-9_]+)":') | ForEach-Object {
        $_.Groups['name'].Value
    })
$sortedClassifiedNames = @(Get-OrdinalNames $classifiedNames)
$classificationHash = Get-TextSha256 (
    ($sortedClassifiedNames -join "`n") + "`n")
Assert-Contract -Condition (
    $classifiedNames.Count -eq [int]$force.forceActionClassification.count -and
    (Test-ExactOrdinalNames $classifiedNames $force.forceActionClassification.names) -and
    $classificationHash -ceq [string]$force.forceActionClassification.sha256 -and
    -not $classification.Contains("toLowerCase") -and
    -not $classification.Contains("equalsIgnoreCase") -and
    -not $classification.Contains("weaponType") -and
    $combatBase.Contains(
        "jedi.isPrecuForceAttackAction(actionData.actionName)")) `
    -Name "p14.armor.force-defense.exact-action-name-classification-no-weapon-inference"

$mitigation = Get-BracedSurface $jedi `
    "public static int applyPrecuForceDefenseMitigation("
$remainingIndex = $mitigation.IndexOf(
    "int remainingDamage = (int)(incomingDamage * remainingMultiplier);",
    [StringComparison]::Ordinal)
$actualBlockedIndex = $mitigation.IndexOf(
    "int mitigatedDamage = incomingDamage - remainingDamage;",
    [StringComparison]::Ordinal)
$observerIndex = $mitigation.IndexOf(
    "int observerAbsorbedDamage =", [StringComparison]::Ordinal)
$costIndex = $mitigation.IndexOf(
    "int forceCost = (int)(observerAbsorbedDamage * extraForceCost);",
    [StringComparison]::Ordinal)
$strictRemoveIndex = $mitigation.IndexOf(
    "if (getForcePower(defender) <= forceCost)",
    [StringComparison]::Ordinal)
$drainIndex = $mitigation.IndexOf(
    "alterForcePower(defender, -forceCost);",
    [StringComparison]::Ordinal)
$returnIndex = $mitigation.IndexOf(
    "return mitigatedDamage;", [StringComparison]::Ordinal)
$shieldHitEffectIndex = $mitigation.IndexOf(
    'playClientEffectObj(defender, "clienteffect/pl_force_shield_hit.cef"',
    [StringComparison]::Ordinal)
$armorHitEffectIndex = $mitigation.IndexOf(
    'playClientEffectObj(defender, "clienteffect/pl_force_armor_hit.cef"',
    [StringComparison]::Ordinal)
$canary = $force.oddDamageObserverCanary
$remainingCanary = [int][Math]::Truncate(
    [double]$canary.incomingDamage *
    (1.0 - ([double]$canary.mitigationPercent / 100.0)))
$actualBlockedCanary = [int]$canary.incomingDamage - $remainingCanary
$observerCanary = [int][Math]::Truncate(
    [double]$canary.incomingDamage *
    ([double]$canary.mitigationPercent / 100.0))
$debitCanary = [int][Math]::Truncate(
    $observerCanary * [double]$canary.rank1ExtraForceCost)
Assert-Contract -Condition (
    $remainingIndex -ge 0 -and $remainingIndex -lt $actualBlockedIndex -and
    $actualBlockedIndex -lt $observerIndex -and $observerIndex -lt $costIndex -and
    $shieldHitEffectIndex -gt $observerIndex -and
    $armorHitEffectIndex -gt $observerIndex -and
    $shieldHitEffectIndex -lt $costIndex -and
    $armorHitEffectIndex -lt $costIndex -and
    $costIndex -lt $strictRemoveIndex -and $strictRemoveIndex -lt $drainIndex -and
    $drainIndex -lt $returnIndex -and
    $mitigation.Contains(
        "!isIdValid(defender) || !isPlayer(defender)") -and
    ([regex]::Matches($mitigation, [regex]::Escape(
        '"jedi_spam", "remove_" + commandName.toLowerCase()'))).Count -eq 1 -and
    -not $mitigation.Contains("weaponType") -and
    $remainingCanary -eq [int]$canary.remainingDamage -and
    $actualBlockedCanary -eq [int]$canary.actualBlockedDamage -and
    $observerCanary -eq [int]$canary.observerAbsorbedDamage -and
    $debitCanary -eq [int]$canary.forceDebit) `
    -Name "p14.armor.force-defense.actual-blocked-versus-observer-drain-rounding"

$damage = Get-BracedSurface $combatBase (
    "public void doWrappedDamage(obj_id attacker, obj_id defender, " +
    "weapon_data weaponData, hit_result hitData, combat_data actionData, " +
    "int overloadDamage)")
$forceCalls = @([regex]::Matches(
    $damage, [regex]::Escape("jedi.applyPrecuForceDefenseMitigation(")))
$armorCalls = @([regex]::Matches(
    $damage, [regex]::Escape("combat.applyPrecuArmorProtection(")))
$foodCalls = @([regex]::Matches(
    $damage, [regex]::Escape("combat.applyPrecuFoodMitigation(")))
$orderedBranches = $forceCalls.Count -eq 2 -and
    $armorCalls.Count -eq 2 -and $foodCalls.Count -eq 2
for ($index = 0; $orderedBranches -and $index -lt 2; ++$index)
{
    $orderedBranches = $forceCalls[$index].Index -lt $armorCalls[$index].Index -and
        $armorCalls[$index].Index -lt $foodCalls[$index].Index
}
Assert-Contract -Condition (
    $orderedBranches -and
    $damage.IndexOf("if (isPlayer(defender))", [StringComparison]::Ordinal) -lt
        $forceCalls[0].Index -and
    $damage.Contains("boolean precuForceAttack =") -and
    $damage.Contains("jedi.isPrecuForceAttackAction(actionData.actionName)") -and
    ([regex]::Matches($damage,
        [regex]::Escape("combat.getPrecuFoodMitigationEffectiveness(defender)"))).Count -eq 1 -and
    ([regex]::Matches($damage,
        [regex]::Escape("combat.consumePrecuFoodMitigationUse(defender)"))).Count -eq 1 -and
    $damage -match
        'combat\.applyPrecuFoodMitigation\(\s*poolMitigationHit,\s*precuPerPoolFoodEffectiveness\)' -and
    ([regex]::Matches($damage,
        [regex]::Escape("weaponData.elementalValue ="))).Count -ge 2 -and
    $combat.Contains("public static int getPrecuFoodMitigationEffectiveness(") -and
    $combat.Contains("public static void consumePrecuFoodMitigationUse(") -and
    $combat -match
        'public static int applyPrecuFoodMitigation\(\s*hit_result hitData,\s*int effectiveness\)') `
    -Name "p14.armor.force-defense.single-and-multi-pool-force-psg-armor-food-order"

$armorCallIndex = $combatBase.IndexOf("combat.applyPrecuArmorProtection(")
$foodCallIndex = $combatBase.IndexOf(
    "combat.applyPrecuFoodMitigation(",
    [Math]::Max(0, $armorCallIndex)
)
$poolDamageIndex = $combatBase.IndexOf(
    "doDamageToPool(",
    [Math]::Max(0, $foodCallIndex)
)
Assert-Contract -Condition (
    $legacyCombat.Contains('"food.mitigate_damage.eff"') -and
    $legacyCombat.Contains('"food.mitigate_damage.dur"') -and
    $combat -match
        'getEnhancedSkillStatisticModifier\(\s*defender,\s*"mitigate_damage"\)' -and
    $combat.Contains('utils.hasScriptVar(defender, "food.mitigate_damage.eff")') -and
    $armorCallIndex -ge 0 -and
    $armorCallIndex -lt $foodCallIndex -and
    $foodCallIndex -lt $poolDamageIndex) `
    -Name "p14.armor.runtime.food-after-armor-before-pool-damage"

$profilesMatch = $profileRows.Count -eq
    [int]$contract.authoritativeWeaponProfileRows
foreach ($expected in $contract.weaponProfiles.psobject.Properties)
{
    $matchingRows = @($profileRows | Where-Object {
        [string]$_.Fields["templateName"] -ceq [string]$expected.Name
    })
    $profilesMatch = $profilesMatch -and
        $matchingRows.Count -eq 1 -and
        [int]$matchingRows[0].Fields["armorPiercing"] -eq [int]$expected.Value
}
Assert-Contract -Condition $profilesMatch `
    -Name "p14.armor.table.exact-opt-in-armor-piercing-profiles"

Assert-Contract -Condition (
    $combatBase.Contains(
        "if (precuResolvedTargetPool >= 0 || precuMultiPoolDamage)") -and
    $combatBase -match
        'combat\.selectPrecuHitLocationForPool\(\s*precuResolvedTargetPool\)' -and
    $combatBase -match
        "else\s*\{\s*hitData\.blockedDamage \+= combat\.applyArmorProtection\(" -and
    [bool]$contract.runtimeContract.defaultNgePathUnchanged) `
    -Name "p14.armor.runtime.authenticated-opt-in-and-nge-fallback"

Assert-Contract -Condition (
    $fixture.Contains("ATTACKER_OID = 44003778L") -and
    $fixture.Contains("ATTACKER_STATION_ID = 91001") -and
    $fixture.Contains("DEFENDER_OID = 39008597L") -and
    $fixture.Contains("DEFENDER_STATION_ID = 1001") -and
    $fixture -match
        "armor\.setAbsoluteArmorData\(\s*fixtureArmor,\s*AL_basic,\s*" +
        "AC_battle,\s*2000,\s*1000\)" -and
    $fixture.Contains("expectedPostArmorDamage=400 expectedFinalDamage=300") -and
    $fixture.Contains('"item.armor.new_armor"') -and
    $fixture.Contains("detachScript(fixtureArmor, ARMOR_TRANSFER_SCRIPT)") -and
    $fixture.Contains("attachScript(fixtureArmor, ARMOR_TRANSFER_SCRIPT)") -and
    $fixture.Contains("destroyObject(fixtureArmor)") -and
    $fixture.Contains("equipOverride(originalHat, defender)") -and
    $fixture.Contains("removeObjVar(attacker, ROOT)") -and
    $fixture.Contains("removeObjVar(defender, ROOT)")) `
    -Name "p14.armor.fixture.identity-bound-real-armor-and-reversible-cleanup"

Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    [string]$contract.buildEvidence.sourceCommit -ceq "cd54de43e" -and
    [string]$contract.buildEvidence.patchSha256 -ceq
        "502aa72ebf0225ec8bf946fff820e80335eec7973fbcee59f57c1f264636e356" -and
    [string]$contract.buildEvidence.compiledSha256.
        "precu_armor_mitigation_fixture.class" -ceq
        "4e2817ecdeac96b41f269bf861310e33156c08540372cdf85426cd4cfb3c81d0") `
    -Name "p14.armor.build.clean-java-and-table-evidence"

Assert-Contract -Condition (
    @("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -ccontains
        [string]$contract.status) `
    -Name "p14.armor.force-defense.status"

$historicalForce = $force.historicalForceDefenseEvidence
Assert-Contract -Condition (
    [string]$historicalForce.directSourceCommit -ceq
        "6955b771580e324b770c1a8d809a5d094e75a75a" -and
    -not [bool]$historicalForce.authenticatesCurrentSource -and
    [string]$historicalForce.directSourceCommit -cne
        [string]$force.directSourceCommit -and
    [string]$historicalForce.build.result -ceq "passed" -and
    [string]$historicalForce.build.fullJavaCompile.result -ceq "passed" -and
    [string]$historicalForce.build.sourceWorkParity.result -ceq "passed" -and
    [int]$historicalForce.build.sourceWorkParity.checkedFiles -eq 6 -and
    [int]$historicalForce.build.sourceWorkParity.matchedFiles -eq 6 -and
    @($historicalForce.build.compiledArtifacts.PSObject.Properties).Count -eq 6 -and
    @($historicalForce.build.compiledArtifacts.PSObject.Properties |
        Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.Value.sha256) -or
            [long]$_.Value.bytes -le 0
        }).Count -eq 0 -and
    -not [string]::IsNullOrWhiteSpace(
        [string]$historicalForce.build.serverBinary.sha256) -and
    [string]$historicalForce.deployment.result -ceq "passed" -and
    [string]$historicalForce.deployment.directSourceCommit -ceq
        [string]$historicalForce.directSourceCommit -and
    [bool]$historicalForce.deployment.clusterReadyForPlayers -and
    [int]$historicalForce.deployment.liveGameProcessCount -gt 0 -and
    [string]$historicalForce.deployment.postStartLogAudit.result -ceq
        "passed") `
    -Name "p14.armor.force-defense.historical-6955-evidence-noncurrent"

if ($Expectation -in @("Build", "Ready"))
{
    $currentBuild = $force.build
    $canonicalArtifactPaths = [ordered]@{
        "combat.class" = "/swg-precu/data/sku.0/sys.server/compiled/game/script/library/combat.class"
        "jedi.class" = "/swg-precu/data/sku.0/sys.server/compiled/game/script/library/jedi.class"
        "combat_actions.class" = "/swg-precu/data/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.class"
        "combat_base.class" = "/swg-precu/data/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.class"
        "buff.iff" = "/swg-precu/data/sku.0/sys.shared/compiled/game/datatables/buff/buff.iff"
        "jedi_actions.iff" = "/swg-precu/data/sku.0/sys.server/compiled/game/datatables/jedi/jedi_actions.iff"
    }
    $artifactProperties = @($currentBuild.compiledArtifacts.PSObject.Properties)
    $artifactNames = @($artifactProperties | ForEach-Object { [string]$_.Name })
    $requiredPathProperties = @(
        $currentBuild.requiredArtifactPaths.PSObject.Properties)
    $requiredPathNames = @($requiredPathProperties |
        ForEach-Object { [string]$_.Name })
    $requiredPaths = @($requiredPathProperties |
        ForEach-Object { [string]$_.Value })
    $container = [string]$currentBuild.container
    $buildReady = (
        [string]$currentBuild.result -ceq "passed" -and
        [string]$currentBuild.fullJavaCompile.result -ceq "passed" -and
        [string]$currentBuild.sourceWorkParity.result -ceq "passed" -and
        [int]$currentBuild.sourceWorkParity.checkedFiles -eq 6 -and
        [int]$currentBuild.sourceWorkParity.matchedFiles -eq 6 -and
        @("implemented-build-verified-live-pending", "ready") -ccontains
            [string]$contract.status -and
        (Test-ExactOrdinalNames $artifactNames $currentBuild.requiredArtifacts) -and
        (Test-ExactOrdinalNames $requiredPathNames $currentBuild.requiredArtifacts) -and
        (Test-ExactOrdinalNames $requiredPathNames $canonicalArtifactPaths.Keys) -and
        @(Get-OrdinalNames $requiredPaths).Count -eq $requiredPaths.Count -and
        -not [string]::IsNullOrWhiteSpace($container)
    )
    foreach ($entry in $canonicalArtifactPaths.GetEnumerator())
    {
        $buildReady = $buildReady -and
            [string]$currentBuild.requiredArtifactPaths.($entry.Key) -ceq
                [string]$entry.Value
    }
    foreach ($property in $artifactProperties)
    {
        $expected = $property.Value
        $pathProperty = $expected.PSObject.Properties['path']
        $hashProperty = $expected.PSObject.Properties['sha256']
        $bytesProperty = $expected.PSObject.Properties['bytes']
        if ($null -eq $pathProperty -or $null -eq $hashProperty -or
            $null -eq $bytesProperty)
        {
            $buildReady = $false
            continue
        }
        $artifactPath = if ($canonicalArtifactPaths.Contains(
            [string]$property.Name))
        {
            [string]$canonicalArtifactPaths[[string]$property.Name]
        }
        else { "" }
        if ([string]::IsNullOrWhiteSpace($artifactPath) -or
            [string]$pathProperty.Value -cne $artifactPath)
        {
            $buildReady = $false
            continue
        }
        $hashOutput = (& docker exec $container sha256sum `
            $artifactPath 2>&1 | Out-String).Trim()
        $hashExit = $LASTEXITCODE
        $bytesOutput = (& docker exec $container stat -Lc "%s" `
            $artifactPath 2>&1 | Out-String).Trim()
        $bytesExit = $LASTEXITCODE
        $actualHash = if ([string]::IsNullOrWhiteSpace($hashOutput))
        {
            ""
        }
        else
        {
            $hashOutput.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)[0]
        }
        $buildReady = $buildReady -and
            $hashExit -eq 0 -and $bytesExit -eq 0 -and
            [string]$hashProperty.Value -cmatch '^[a-f0-9]{64}$' -and
            $actualHash -ceq [string]$hashProperty.Value -and
            [long]$bytesProperty.Value -gt 0 -and
            [long]$bytesOutput -eq [long]$bytesProperty.Value
    }
    $tableRecompile = $currentBuild.deterministicTableRecompile
    $tableProperties = @($tableRecompile.tables.PSObject.Properties)
    $expectedTableNames = @("buff.iff", "jedi_actions.iff")
    $tableRecompileReady = (
        [string]$tableRecompile.result -ceq "passed" -and
        [string]$tableRecompile.compiler -ceq
            "/swg-precu/build/bin/DataTableTool" -and
        [string]$tableRecompile.temporaryRoot -ceq "/dev/shm" -and
        [bool]$tableRecompile.cleanupVerified -and
        (Test-ExactOrdinalNames `
            ($tableProperties | ForEach-Object { [string]$_.Name }) `
            $expectedTableNames))
    $expectedTableSources = @{
        "buff.iff" = @(
            "/swg-precu/dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab",
            [string]$force.sourceSha256."buff.tab")
        "jedi_actions.iff" = @(
            "/swg-precu/dsrc/sku.0/sys.server/compiled/game/datatables/jedi/jedi_actions.tab",
            [string]$force.sourceSha256."jedi_actions.tab")
    }
    foreach ($tableName in $expectedTableNames)
    {
        $table = $tableRecompile.tables.($tableName)
        $tableRecompileReady = $tableRecompileReady -and
            [string]$table.sourcePath -ceq
                [string]$expectedTableSources[$tableName][0] -and
            [string]$table.sourceSha256 -ceq
                [string]$expectedTableSources[$tableName][1] -and
            [string]$table.canonicalPath -ceq
                [string]$canonicalArtifactPaths[$tableName] -and
            [bool]$table.freshOutputMatchesCanonical
    }
    $buildReady = $buildReady -and $tableRecompileReady

    $binaryPath = "/swg-precu/build/bin/SwgGameServer"
    $binary = $currentBuild.serverBinary
    $binaryHashOutput = (& docker exec $container sha256sum `
        $binaryPath 2>&1 | Out-String).Trim()
    $binaryHashExit = $LASTEXITCODE
    $binaryStatOutput = (& docker exec $container stat -Lc "%s|%i" `
        $binaryPath 2>&1 | Out-String).Trim()
    $binaryStatExit = $LASTEXITCODE
    $binaryFileOutput = (& docker exec $container file -L `
        $binaryPath 2>&1 | Out-String)
    $binaryFileExit = $LASTEXITCODE
    $binaryNotes = (& docker exec $container readelf -n `
        $binaryPath 2>&1 | Out-String)
    $binaryNotesExit = $LASTEXITCODE
    $binaryStat = @($binaryStatOutput -split '\|')
    $actualBinaryHash = if ([string]::IsNullOrWhiteSpace($binaryHashOutput))
    {
        ""
    }
    else
    {
        $binaryHashOutput.Split(
            ' ', [StringSplitOptions]::RemoveEmptyEntries)[0]
    }
    $buildReady = $buildReady -and
        [string]$binary.path -ceq $binaryPath -and
        [string]$binary.sha256 -cmatch '^[a-f0-9]{64}$' -and
        [string]$binary.buildIdSha1 -cmatch '^[a-f0-9]{40}$' -and
        [long]$binary.bytes -gt 0 -and [long]$binary.inode -gt 0 -and
        $binaryHashExit -eq 0 -and $binaryStatExit -eq 0 -and
        $binaryFileExit -eq 0 -and $binaryNotesExit -eq 0 -and
        $binaryStat.Count -eq 2 -and
        $actualBinaryHash -ceq [string]$binary.sha256 -and
        [long]$binaryStat[0] -eq [long]$binary.bytes -and
        [long]$binaryStat[1] -eq [long]$binary.inode -and
        $binaryFileOutput.Contains("ELF 64-bit") -and
        $binaryFileOutput.Contains("x86-64") -and
        $binaryNotes.Contains([string]$binary.buildIdSha1)

    $inspection = @((& docker inspect $container 2>&1 | Out-String) |
        ConvertFrom-Json)[0]
    $buildReady = $buildReady -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$currentBuild.validatedContainerStartedAt) -and
        [string]$inspection.State.StartedAt -ceq
            [string]$currentBuild.validatedContainerStartedAt
    $parityMatches = 0
    foreach ($entry in $sourceHashMap.GetEnumerator())
    {
        $relative = $entry.Value.Substring($source.Length + 1).Replace('\', '/')
        & docker exec $container cmp -s "/swg-precu-source/$relative" `
            "/swg-precu/$relative"
        if ($LASTEXITCODE -eq 0) { ++$parityMatches }
    }
    $buildReady = $buildReady -and $parityMatches -eq 6
    if ($buildReady)
    {
        $buildReady = Test-ForceTableFreshRecompile -Container $container
    }
    if ($buildReady)
    {
        $deployment = $force.deployment
        $inspection = @((& docker inspect $container 2>&1 | Out-String) |
            ConvertFrom-Json)[0]
        $pidOutput = (& docker exec $container pgrep -x SwgGameServer `
            2>&1 | Out-String).Trim()
        $pidExit = $LASTEXITCODE
        $gamePids = @($pidOutput -split '\s+' |
            Where-Object { [string]$_ -cmatch '^[0-9]+$' })
        $mappedCount = 0
        foreach ($gamePid in $gamePids)
        {
            $mappedPath = (& docker exec $container readlink -f `
                "/proc/$gamePid/exe" 2>&1 | Out-String).Trim()
            $mappedStat = (& docker exec $container stat -Lc "%i|%s" `
                "/proc/$gamePid/exe" 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and
                $mappedPath -ceq $binaryPath -and
                $mappedStat -ceq "$($binary.inode)|$($binary.bytes)")
            {
                ++$mappedCount
            }
        }
        $logs = (& docker logs --since `
            ([string]$deployment.containerStartedAt) $container 2>&1 |
            Out-String)
        $logExit = $LASTEXITCODE
        $logLines = @($logs -split "`n" | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        })
        $badLogLines = @($logLines | Select-String -Pattern (
            "FATAL|SEVERE|Exception|\bERROR\b|database conversion|" +
            "undefined symbol|ORA-|" +
            "ConGenericMessage constructed with empty message"))
        $readyMarkers = @($logLines | Select-String `
            -Pattern "Cluster swg is ready for players." -SimpleMatch)
        $buildReady = $buildReady -and
            [string]$deployment.result -ceq "passed" -and
            [string]$deployment.directSourceCommit -ceq
                [string]$force.directSourceCommit -and
            [string]$deployment.container -ceq $container -and
            [string]$inspection.Id -ceq [string]$deployment.containerId -and
            [string]$inspection.Config.Image -ceq
                [string]$deployment.containerImage -and
            [string]$inspection.Image -ceq
                [string]$deployment.containerImageId -and
            [string]$inspection.State.Status -ceq "running" -and
            [string]$inspection.State.Health.Status -ceq "healthy" -and
            [string]$deployment.containerHealth -ceq "healthy" -and
            [string]$inspection.State.StartedAt -ceq
                [string]$deployment.containerStartedAt -and
            [string]$deployment.containerStartedAt -ceq
                [string]$currentBuild.validatedContainerStartedAt -and
            [bool]$deployment.clusterReadyForPlayers -and
            $pidExit -eq 0 -and $gamePids.Count -gt 0 -and
            $gamePids.Count -eq [int]$deployment.liveGameProcessCount -and
            (Test-ExactOrdinalNames $gamePids `
                $deployment.liveGameProcessPids) -and
            $mappedCount -eq $gamePids.Count -and
            [bool]$deployment.allLiveGameProcessesMatchBinary -and
            [string]$deployment.liveBinaryPath -ceq $binaryPath -and
            [long]$deployment.liveBinaryInode -eq [long]$binary.inode -and
            [long]$deployment.liveBinarySizeBytes -eq [long]$binary.bytes -and
            $logExit -eq 0 -and
            [string]$deployment.postStartLogAudit.result -ceq "passed" -and
            [int]$deployment.postStartLogAudit.lineCount -gt 0 -and
            $logLines.Count -ge
                [int]$deployment.postStartLogAudit.lineCount -and
            [int]$deployment.postStartLogAudit.
                fatalSevereExceptionErrorDatabaseConversionUndefinedSymbolOracleOrEmptyGenericMessageMatches -eq 0 -and
            [int]$deployment.postStartLogAudit.playerReadyMarkerCount -ge 1 -and
            $badLogLines.Count -eq 0 -and $readyMarkers.Count -ge 1 -and
            [string]$force.live.directSourceCommit -ceq
                [string]$force.directSourceCommit -and
            (([string]$contract.status -ceq
                    "implemented-build-verified-live-pending" -and
                [string]$force.live.result -ceq "pending" -and
                [string]::IsNullOrWhiteSpace(
                    [string]$force.live.containerStartedAt) -and
                @($force.live.activation).Count -eq 0 -and
                @($contract.requiredBeforeReady).Count -eq 1) -or
             ([string]$contract.status -ceq "ready" -and
                [string]$force.live.result -ceq "passed" -and
                @($contract.requiredBeforeReady).Count -eq 0))
    }
    Assert-Contract -Condition $buildReady `
        -Name "p14.armor.force-defense.current-deployed-build-artifacts-and-parity"
}
elseif ([string]$contract.status -ceq "implemented-build-pending")
{
    Assert-Contract -Condition (
        [string]$force.build.result -ceq "pending" -and
        [string]::IsNullOrWhiteSpace(
            [string]$force.build.validatedContainerStartedAt) -and
        [string]$force.build.fullJavaCompile.result -ceq "pending" -and
        [string]$force.build.sourceWorkParity.result -ceq "pending" -and
        [int]$force.build.sourceWorkParity.checkedFiles -eq 6 -and
        [int]$force.build.sourceWorkParity.matchedFiles -eq 0 -and
        @($force.build.compiledArtifacts.PSObject.Properties |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.Value.sha256) -or
                [long]$_.Value.bytes -ne 0
            }).Count -eq 0 -and
        [string]::IsNullOrWhiteSpace([string]$force.build.serverBinary.sha256) -and
        [string]::IsNullOrWhiteSpace(
            [string]$force.build.serverBinary.buildIdSha1) -and
        [long]$force.build.serverBinary.bytes -eq 0 -and
        [long]$force.build.serverBinary.inode -eq 0 -and
        [string]$force.build.deterministicTableRecompile.result -ceq
            "pending" -and
        -not [bool]$force.build.deterministicTableRecompile.cleanupVerified -and
        -not [bool]$force.build.deterministicTableRecompile.tables.
            "buff.iff".freshOutputMatchesCanonical -and
        -not [bool]$force.build.deterministicTableRecompile.tables.
            "jedi_actions.iff".freshOutputMatchesCanonical -and
        [string]$force.deployment.result -ceq "pending" -and
        [string]$force.deployment.directSourceCommit -ceq
            [string]$force.directSourceCommit -and
        [string]::IsNullOrWhiteSpace([string]$force.deployment.container) -and
        [string]$force.deployment.containerHealth -ceq "pending" -and
        -not [bool]$force.deployment.clusterReadyForPlayers -and
        [int]$force.deployment.liveGameProcessCount -eq 0 -and
        [string]$force.live.result -ceq "pending" -and
        [string]$force.live.directSourceCommit -ceq
            [string]$force.directSourceCommit -and
        [string]::IsNullOrWhiteSpace(
            [string]$force.live.containerStartedAt) -and
        @($force.live.activation).Count -eq 0 -and
        @($contract.requiredBeforeReady).Count -eq 2) `
        -Name "p14.armor.force-defense.pending-evidence-truthful"
}

if ($Expectation -ceq "Ready")
{
    $currentBuild = $force.build
    $deployment = $force.deployment
    $forceLive = $force.live
    $container = [string]$deployment.container
    $inspection = @((& docker inspect $container 2>&1 | Out-String) |
        ConvertFrom-Json)[0]
    Assert-Contract -Condition (
        [string]$deployment.result -ceq "passed" -and
        [string]$deployment.directSourceCommit -ceq
            [string]$force.directSourceCommit -and
        [string]$container -ceq [string]$currentBuild.container -and
        [string]$inspection.Id -ceq [string]$deployment.containerId -and
        [string]$inspection.Config.Image -ceq
            [string]$deployment.containerImage -and
        [string]$inspection.Image -ceq [string]$deployment.containerImageId -and
        [string]$inspection.State.Status -ceq "running" -and
        [string]$inspection.State.Health.Status -ceq "healthy" -and
        [string]$deployment.containerHealth -ceq "healthy" -and
        [string]$inspection.State.StartedAt -ceq
            [string]$deployment.containerStartedAt -and
        [string]$deployment.containerStartedAt -ceq
            [string]$currentBuild.validatedContainerStartedAt -and
        [bool]$deployment.clusterReadyForPlayers) `
        -Name "p14.armor.force-defense.current-same-start-deployment"

    $binary = $currentBuild.serverBinary
    $binaryPath = "/swg-precu/build/bin/SwgGameServer"
    $pidOutput = (& docker exec $container pgrep -x SwgGameServer `
        2>&1 | Out-String).Trim()
    $gamePids = @($pidOutput -split '\s+' |
        Where-Object { [string]$_ -cmatch '^[0-9]+$' })
    $mappedCount = 0
    foreach ($gamePid in $gamePids)
    {
        $mappedPath = (& docker exec $container readlink -f `
            "/proc/$gamePid/exe" 2>&1 | Out-String).Trim()
        $mappedStat = (& docker exec $container stat -Lc "%i|%s" `
            "/proc/$gamePid/exe" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and
            $mappedPath -ceq $binaryPath -and
            $mappedStat -ceq "$($binary.inode)|$($binary.bytes)")
        {
            ++$mappedCount
        }
    }
    Assert-Contract -Condition (
        $gamePids.Count -gt 0 -and
        $gamePids.Count -eq [int]$deployment.liveGameProcessCount -and
        (Test-ExactOrdinalNames $gamePids $deployment.liveGameProcessPids) -and
        $mappedCount -eq $gamePids.Count -and
        [bool]$deployment.allLiveGameProcessesMatchBinary -and
        [string]$deployment.liveBinaryPath -ceq $binaryPath -and
        [long]$deployment.liveBinaryInode -eq [long]$binary.inode -and
        [long]$deployment.liveBinarySizeBytes -eq [long]$binary.bytes) `
        -Name "p14.armor.force-defense.all-live-processes-map-current-binary"

    $logs = (& docker logs --since ([string]$deployment.containerStartedAt) `
        $container 2>&1 | Out-String)
    $logLines = @($logs -split "`n" | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    })
    $badLogLines = @($logLines | Select-String -Pattern (
        "FATAL|SEVERE|Exception|\bERROR\b|database conversion|" +
        "undefined symbol|ORA-|" +
        "ConGenericMessage constructed with empty message"))
    $readyMarkers = @($logLines | Select-String `
        -Pattern "Cluster swg is ready for players." -SimpleMatch)
    Assert-Contract -Condition (
        [string]$deployment.postStartLogAudit.result -ceq "passed" -and
        [int]$deployment.postStartLogAudit.lineCount -gt 0 -and
        $logLines.Count -ge [int]$deployment.postStartLogAudit.lineCount -and
        [int]$deployment.postStartLogAudit.
            fatalSevereExceptionErrorDatabaseConversionUndefinedSymbolOracleOrEmptyGenericMessageMatches -eq 0 -and
        [int]$deployment.postStartLogAudit.playerReadyMarkerCount -ge 1 -and
        $badLogLines.Count -eq 0 -and $readyMarkers.Count -ge 1) `
        -Name "p14.armor.force-defense.clean-ready-same-start-logs"

    $runtimeBinding = $forceLive.runtimeBinding
    Assert-Contract -Condition (
        [string]$forceLive.result -ceq "passed" -and
        [string]$forceLive.directSourceCommit -ceq
            [string]$force.directSourceCommit -and
        -not [string]::IsNullOrWhiteSpace([string]$forceLive.sessionId) -and
        [long]$forceLive.characterObjectId -gt 0 -and
        [long]$forceLive.targetObjectId -gt 0 -and
        [string]$forceLive.containerStartedAt -ceq
            [string]$deployment.containerStartedAt -and
        [string]$runtimeBinding.deploymentEvidence -ceq
            "forceDefenseContract.deployment" -and
        [string]$runtimeBinding.containerStartedAt -ceq
            [string]$deployment.containerStartedAt -and
        [string]$runtimeBinding.serverBinarySha256 -ceq
            [string]$binary.sha256 -and
        [string]$runtimeBinding.serverBinaryBuildIdSha1 -ceq
            [string]$binary.buildIdSha1 -and
        [long]$runtimeBinding.serverBinaryInode -eq [long]$binary.inode -and
        [long]$runtimeBinding.serverBinarySizeBytes -eq [long]$binary.bytes -and
        [int]$runtimeBinding.liveGameProcessCount -eq $gamePids.Count -and
        [bool]$runtimeBinding.allLiveGameProcessesMatchBinary) `
        -Name "p14.armor.force-defense.live-session-current-runtime-binding"

    $activationFields = @(
        "command", "activationCost", "durationSeconds",
        "baseProtectionPercent", "controlModifier",
        "observedProtectionPercent", "equalForceActivationPassed",
        "sameRankTogglePassed", "skillGrantExposedCommand",
        "skillRevokeRemovedCommand", "applyLocalizationKey",
        "removeLocalizationKey")
    $activationValid = @($forceLive.activation).Count -eq 4
    foreach ($rank in $force.ranks)
    {
        $entries = @($forceLive.activation | Where-Object {
            [string]$_.command -ceq [string]$rank.command
        })
        if ($entries.Count -ne 1)
        {
            $activationValid = $false
            continue
        }
        $entry = $entries[0]
        $entryFields = @($entry.PSObject.Properties |
            ForEach-Object { [string]$_.Name })
        if (-not (Test-ExactOrdinalNames $entryFields $activationFields))
        {
            $activationValid = $false
            continue
        }
        $coefficient = if ([int]$rank.rank -eq 1)
        {
            [double]$force.forceRankModifiers.rank1ProtectionPerControl
        }
        else
        {
            [double]$force.forceRankModifiers.rank2ProtectionPerControl
        }
        $expectedProtection = [int]$rank.protectionPercent +
            [int][Math]::Truncate(
                ([int]$entry.controlModifier * $coefficient) + 0.5)
        $activationValid = $activationValid -and
            [int]$entry.activationCost -eq [int]$rank.activationCost -and
            [int]$entry.durationSeconds -eq [int]$rank.durationSeconds -and
            [int]$entry.baseProtectionPercent -eq
                [int]$rank.protectionPercent -and
            [int]$entry.observedProtectionPercent -eq
                $expectedProtection -and
            [bool]$entry.equalForceActivationPassed -and
            [bool]$entry.sameRankTogglePassed -and
            [bool]$entry.skillGrantExposedCommand -and
            [bool]$entry.skillRevokeRemovedCommand -and
            [string]$entry.applyLocalizationKey -ceq
                "apply_$(([string]$rank.command).ToLowerInvariant())" -and
            [string]$entry.removeLocalizationKey -ceq
                "remove_$(([string]$rank.command).ToLowerInvariant())"
    }
    Assert-Contract -Condition $activationValid `
        -Name "p14.armor.force-defense.live-all-four-activation-grant-toggle"

    Assert-Contract -Condition (
        [bool]$forceLive.tierLifecycle.armorRank1BlockedByRank2 -and
        [bool]$forceLive.tierLifecycle.armorRank2ReplacedRank1 -and
        [bool]$forceLive.tierLifecycle.shieldRank1BlockedByRank2 -and
        [bool]$forceLive.tierLifecycle.shieldRank2ReplacedRank1 -and
        [bool]$forceLive.tierLifecycle.sameRankToggleBeforeOtherAdmissionChecks -and
        [bool]$forceLive.tierLifecycle.armorEquipmentRejected -and
        [int]$forceLive.domainMitigation.forceArmor1NonForcePercent -eq 25 -and
        [int]$forceLive.domainMitigation.forceArmor2NonForcePercent -eq 45 -and
        [int]$forceLive.domainMitigation.forceArmorAgainstForcePercent -eq 0 -and
        [int]$forceLive.domainMitigation.forceShield1ForcePercent -eq 25 -and
        [int]$forceLive.domainMitigation.forceShield2ForcePercent -eq 45 -and
        [int]$forceLive.domainMitigation.forceShieldAgainstNonForcePercent -eq 0) `
        -Name "p14.armor.force-defense.live-tier-and-force-domain-split"

    $frsFields = @(
        "rank", "controlModifier", "baseProtectionPercent",
        "protectionCoefficient", "observedProtectionPercent",
        "manipulationModifier", "observerAbsorbedDamage",
        "baseDrainMultiplier", "drainCoefficient", "observedForceDebit")
    $frsValid = @($forceLive.frsCases).Count -eq 2
    foreach ($rankNumber in @(1, 2))
    {
        $cases = @($forceLive.frsCases | Where-Object {
            [int]$_.rank -eq $rankNumber
        })
        if ($cases.Count -ne 1)
        {
            $frsValid = $false
            continue
        }
        $case = $cases[0]
        $caseFields = @($case.PSObject.Properties |
            ForEach-Object { [string]$_.Name })
        if (-not (Test-ExactOrdinalNames $caseFields $frsFields))
        {
            $frsValid = $false
            continue
        }
        $baseProtection = if ($rankNumber -eq 1) { 25 } else { 45 }
        $protectionCoefficient = if ($rankNumber -eq 1) { 0.25 } else { 0.35 }
        $baseDrain = if ($rankNumber -eq 1) { 0.5 } else { 0.3 }
        $expectedProtection = $baseProtection +
            [int][Math]::Truncate(
                ([int]$case.controlModifier * $protectionCoefficient) + 0.5)
        $effectiveDrain = $baseDrain +
            ([int]$case.manipulationModifier * -0.003)
        $expectedDebit = [int][Math]::Truncate(
            [int]$case.observerAbsorbedDamage * $effectiveDrain)
        $frsValid = $frsValid -and
            [int]$case.controlModifier -gt 0 -and
            [double]$case.protectionCoefficient -eq $protectionCoefficient -and
            [int]$case.baseProtectionPercent -eq $baseProtection -and
            [int]$case.observedProtectionPercent -eq $expectedProtection -and
            [int]$case.manipulationModifier -gt 0 -and
            [int]$case.observerAbsorbedDamage -gt 0 -and
            $effectiveDrain -gt 0 -and $expectedDebit -gt 0 -and
            [double]$case.baseDrainMultiplier -eq $baseDrain -and
            [double]$case.drainCoefficient -eq -0.003 -and
            [int]$case.observedForceDebit -eq $expectedDebit
    }
    Assert-Contract -Condition $frsValid `
        -Name "p14.armor.force-defense.live-frs-protection-and-drain"

    $odd = $forceLive.oddDamageCanary
    Assert-Contract -Condition (
        [int]$odd.incomingDamage -eq 7 -and
        [int]$odd.mitigationPercent -eq 25 -and
        [int]$odd.remainingDamage -eq 5 -and
        [int]$odd.actualBlockedDamage -eq 2 -and
        [int]$odd.observerAbsorbedDamage -eq 1 -and
        [double]$odd.extraForceCost -eq 0.5 -and
        [int]$odd.forceDebit -eq 0 -and
        [bool]$forceLive.forceDrain.atOrBelowCostRemovedBuffWithoutSubtract -and
        [bool]$forceLive.forceDrain.atOrBelowHitEffectPlayed -and
        [string]$forceLive.forceDrain.atOrBelowRemoveLocalizationKey `
            -clike "remove_*" -and
        $force.activation.localizationKeys -ccontains
            [string]$forceLive.forceDrain.atOrBelowRemoveLocalizationKey -and
        [int]$forceLive.forceDrain.atOrBelowComputedCost -gt 0 -and
        [int]$forceLive.forceDrain.atOrBelowForceBefore -le
            [int]$forceLive.forceDrain.atOrBelowComputedCost -and
        [int]$forceLive.forceDrain.atOrBelowForceAfter -eq
            [int]$forceLive.forceDrain.atOrBelowForceBefore -and
        [bool]$forceLive.forceDrain.aboveCostSubtractedAndRetainedBuff -and
        [int]$forceLive.forceDrain.aboveComputedCost -gt 0 -and
        [int]$forceLive.forceDrain.aboveForceBefore -gt
            [int]$forceLive.forceDrain.aboveComputedCost -and
        [int]$forceLive.forceDrain.aboveForceAfter -eq
            ([int]$forceLive.forceDrain.aboveForceBefore -
                [int]$forceLive.forceDrain.aboveComputedCost) -and
        [double]$forceLive.forceDrain.rank1BaseMultiplier -eq 0.5 -and
        [double]$forceLive.forceDrain.rank2BaseMultiplier -eq 0.3 -and
        [double]$forceLive.forceDrain.frsDrainPerManipulation -eq -0.003) `
        -Name "p14.armor.force-defense.live-truncation-and-force-removal"

    $expectedLayerTrace = @(
        "forceDefense", "personalShieldGenerator", "hitLocationArmor",
        "foodMitigation", "hamPool")
    Assert-Contract -Condition (
        (Test-ExactOrdinalNames $forceLive.singlePool.layerTrace `
            $expectedLayerTrace) -and
        (($forceLive.singlePool.layerTrace -join ([char]0)) -ceq
            ($expectedLayerTrace -join ([char]0))) -and
        [int]$forceLive.singlePool.forceMitigationApplications -eq 1 -and
        [int]$forceLive.singlePool.foodUsesConsumed -eq 1 -and
        [bool]$forceLive.singlePool.elementalDamageRestored -and
        (Test-ExactOrdinalNames $forceLive.multiPool.layerTrace `
            $expectedLayerTrace) -and
        (($forceLive.multiPool.layerTrace -join ([char]0)) -ceq
            ($expectedLayerTrace -join ([char]0))) -and
        [int]$forceLive.multiPool.activePools -ge 2 -and
        [int]$forceLive.multiPool.forceMitigationApplications -eq
            [int]$forceLive.multiPool.activePools -and
        [int]$forceLive.multiPool.foodEffectivenessReads -eq 1 -and
        [int]$forceLive.multiPool.foodUsesConsumed -eq 1 -and
        [bool]$forceLive.multiPool.elementalDamageRestored) `
        -Name "p14.armor.force-defense.live-single-multi-layer-order"

    Assert-Contract -Condition (
        [bool]$forceLive.cleanup.allFourCommandsGrantedAndRevokedExactly -and
        [bool]$forceLive.cleanup.buffsRemoved -and
        [bool]$forceLive.cleanup.forcePowerRestored -and
        [bool]$forceLive.cleanup.skillStateRestored -and
        [bool]$forceLive.cleanup.targetStateRestored -and
        [bool]$forceLive.cleanup.relogVerified -and
        [bool]$forceLive.cleanup.serverHealthy) `
        -Name "p14.armor.force-defense.live-reversible-cleanup-relog-health"

    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$force.build.result -ceq "passed" -and
        [string]$force.deployment.result -ceq "passed" -and
        [string]$force.live.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 29 -and
        [bool]$contract.publicationBoundary.productionGameplayCodeChanged -and
        -not [bool]$contract.publicationBoundary.clientToolsChanged -and
        -not [bool]$contract.publicationBoundary.clientAssetsChanged) `
        -Name "p14.armor.status.ready-server-only-production-repair"
    Assert-Contract -Condition (
        [int]$live.probe.rawDamage -eq 1000 -and
        [int]$live.probe.hitLocation -eq 1 -and
        [int]$live.probe.armorPiercing -eq 0 -and
        [int]$live.probe.armorRating -eq 1 -and
        [double]$live.probe.protection -eq 0.2 -and
        [int]$live.probe.postArmorDamage -eq 400 -and
        [int]$live.probe.finalDamage -eq 300 -and
        [int]$live.probe.conditionDelta -eq 200 -and
        [int]$live.probe.foodDurationDelta -eq 1) `
        -Name "p14.armor.live.deterministic-production-helper-probe"
    Assert-Contract -Condition (
        [int]$live.headShot.hitLocation -eq 1 -and
        [int]$live.headShot.armorPiercing -eq 0 -and
        [int]$live.headShot.armorRating -eq 1 -and
        [double]$live.headShot.protection -eq 0.2 -and
        [int]$live.headShot.postArmorDamage -eq
            [int]$live.headShot.expectedPostArmorDamage -and
        [int]$live.headShot.finalDamage -eq
            [int]$live.headShot.expectedFinalDamage -and
        [int]$live.headShot.mindDelta -eq [int]$live.headShot.finalDamage) `
        -Name "p14.armor.live.off-focus-headshot-ordering-and-pool-delta"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.armor.live.cleanup-and-isolated-container-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 armor contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 armor/mitigation ordering contract passed."
