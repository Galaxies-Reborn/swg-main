[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14NineAttributeRuntime)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
$text = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $name = [string]$property.Name
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized nine-attribute source is missing: $path"
    }
    $paths[$name] = $path
    $text[$name] = Get-Content -LiteralPath $path -Raw
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
    if ($start -lt 0) { return "" }
    $openBrace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($openBrace -lt 0) { return "" }
    $depth = 0
    for ($index = $openBrace; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

Write-Host "Publish 14.1 nine-attribute runtime checks:"

$wireOrder = @($contract.wireOrder | ForEach-Object { [string]$_ })
$expectedWireOrder = @("Health", "Strength", "Constitution", "Action", "Quickness", "Stamina", "Mind", "Focus", "Willpower")
Assert-Contract `
    -Condition ([string]$contract.status -ceq "ready" -and (($wireOrder -join ",") -ceq ($expectedWireOrder -join ","))) `
    -Name "p14.nine-attribute.contract.ready-and-exact-wire-order"

$enumReady = $true
for ($index = 0; $index -lt $expectedWireOrder.Count; $index++)
{
    if (-not [regex]::IsMatch($text.attributes, "const\s+int\s+$($expectedWireOrder[$index])\s*=\s*$index\s*;"))
    {
        $enumReady = $false
    }
}
Assert-Contract `
    -Condition ($enumReady -and [regex]::IsMatch($text.attributes, "const\s+int\s+NumberOfAttributes\s*=\s*9\s*;") -and $text.attributes.Contains("Attributes::Health, Attributes::Action, Attributes::Mind")) `
    -Name "p14.nine-attribute.shared.enum-and-primary-pools"

$javaReady = $true
for ($index = 0; $index -lt $expectedWireOrder.Count; $index++)
{
    if (-not [regex]::IsMatch($text.baseClass, "public\s+static\s+final\s+int\s+$($expectedWireOrder[$index].ToUpperInvariant())\s*=\s*$index\s*;"))
    {
        $javaReady = $false
    }
}
Assert-Contract `
    -Condition ($javaReady -and $text.baseClass.Contains("NUM_ATTRIBUTES = 9") -and $text.baseClass.Contains("NUM_ATTRIBUTES_PER_GROUP = 3")) `
    -Name "p14.nine-attribute.java.enum-and-three-stat-groups"

$tdfReady = $true
$expectedTdfOrder = @("AT_health", "AT_strength", "AT_constitution", "AT_action", "AT_quickness", "AT_stamina", "AT_mind", "AT_focus", "AT_willpower")
foreach ($version in @(9, 10, 11))
{
    $match = [regex]::Match($text.tdf, "(?s)version\s+$version\s+enum\s+Attributes\s*\{(?<body>.*?)\}")
    $values = if ($match.Success) { @([regex]::Matches($match.Groups["body"].Value, "AT_[a-z]+") | ForEach-Object { $_.Value }) } else { @() }
    if (($values -join ",") -cne ($expectedTdfOrder -join ",")) { $tdfReady = $false }
}
Assert-Contract -Condition $tdfReady -Name "p14.nine-attribute.templates.tdf-versions-9-through-11"

$baseTemplatesReady = $true
foreach ($name in @("basePlayerTemplate", "baseCreatureTemplate", "baseNpcTemplate"))
{
    foreach ($attribute in $expectedTdfOrder)
    {
        if (-not $text[$name].Contains("attributes[$attribute]")) { $baseTemplatesReady = $false }
    }
}
Assert-Contract -Condition $baseTemplatesReady -Name "p14.nine-attribute.templates.base-values-cover-nine"

$generatedReady = `
    $text.serverObjectTemplate.Contains("AT_strength") -and `
    $text.serverObjectTemplate.Contains("AT_quickness") -and `
    $text.serverObjectTemplate.Contains("AT_focus") -and `
    $text.compilerObjectTemplate.Contains("AT_strength") -and `
    $text.compilerObjectTemplate.Contains("AT_quickness") -and `
    $text.compilerObjectTemplate.Contains("AT_focus") -and `
    $text.serverCreatureTemplateHeader.Contains("m_attributes[9]") -and `
    $text.serverCreatureTemplateHeader.Contains("m_minAttributes[9]") -and `
    $text.serverCreatureTemplateHeader.Contains("m_maxAttributes[9]") -and `
    $text.compilerCreatureTemplateHeader.Contains("m_attributes[9]") -and `
    $text.compilerCreatureTemplateHeader.Contains("m_minAttributes[9]") -and `
    $text.compilerCreatureTemplateHeader.Contains("m_maxAttributes[9]") -and `
    -not [regex]::IsMatch($text.serverCreatureTemplateCpp, "(?m)(index\s*>=\s*6|index\s*<\s*6|listCount\s*!=\s*6|j\s*<\s*6)") -and `
    -not [regex]::IsMatch($text.compilerCreatureTemplateCpp, "(?m)(index\s*>=\s*6|index\s*<\s*6|listCount\s*!=\s*6|j\s*<\s*6|count\s*=\s*6|i\s*<\s*6)")
Assert-Contract -Condition $generatedReady -Name "p14.nine-attribute.templates.generated-arrays-and-bounds"

$migration = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::migrateSixAttributeStateToNine()"
$load = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::onLoadedFromDatabase()"
$migrationReady = `
    $migration.Contains("m_attributes.size() != 6") -and `
    $migration.Contains("m_maxAttributes.size() != 6") -and `
    $migration.Contains("current[Attributes::Health] = oldCurrent[0]") -and `
    $migration.Contains("current[Attributes::Action] = oldCurrent[2]") -and `
    $migration.Contains("current[Attributes::Mind] = oldCurrent[4]") -and `
    $migration.Contains("current[Attributes::Constitution] = oldMax[1]") -and `
    $migration.Contains("current[Attributes::Stamina] = oldMax[3]") -and `
    $migration.Contains("current[Attributes::Willpower] = oldMax[5]") -and `
    $migration.Contains("Attributes::NumberOfAttributes, 300") -and `
    $load.IndexOf("migrateSixAttributeStateToNine();", [StringComparison]::Ordinal) -ge 0
Assert-Contract -Condition $migrationReady -Name "p14.nine-attribute.persistence.deterministic-six-to-nine-migration"

$regen = Get-BracedBlock -Text $text.creatureCpp -Signature "float CreatureObject::getRegenRate("
Assert-Contract `
    -Condition ($regen.Contains("Attributes::Constitution") -and $regen.Contains("Attributes::Stamina") -and $regen.Contains("Attributes::Willpower") -and $regen.Contains("* 13.0f / 2100.0f") -and $regen.Contains("std::max(1.0f, rate)")) `
    -Name "p14.nine-attribute.regeneration.core3-governors-and-formula"

$damageCallbackReady = $text.creatureCpp.Contains("int damageArray[] = {healthDamage, 0, 0, actionDamage, 0, 0, mindDamage, 0, 0};")
Assert-Contract -Condition $damageCallbackReady -Name "p14.nine-attribute.damage-callback.nine-value-vector"

$combatCost = Get-BracedBlock -Text $text.combatLibrary -Signature "private static int[] getPrecuHamActionCost("
Assert-Contract `
    -Condition ($combatCost.Contains("getAttrib(self, STRENGTH)") -and $combatCost.Contains("getAttrib(self, QUICKNESS)") -and $combatCost.Contains("getAttrib(self, FOCUS)") -and -not $text.combatLibrary.Contains("PRECU_NEUTRAL_GOVERNING_ATTRIBUTE")) `
    -Name "p14.nine-attribute.combat-cost.dynamic-governors"

$levelStats = Get-BracedBlock -Text $text.skillLibrary -Signature "public static void setPlayerStatsForLevel("
$recalcPools = Get-BracedBlock -Text $text.skillLibrary -Signature "public static void recalcPlayerPools("
$combatLevelChanged = Get-BracedBlock -Text $text.basePlayerScript -Signature "public int OnCombatLevelChanged("
Assert-Contract `
    -Condition ($levelStats.Contains("Pre-CU HAM") -and -not [regex]::IsMatch($levelStats, "player_levels|setMaxAttrib|setRegenRate|applySkillStatisticModifier|recalcPlayerPools")) `
    -Name "p14.nine-attribute.progression.level-stat-overwrite-disabled"
Assert-Contract `
    -Condition ($recalcPools.Contains("getMaxAttrib(objPlayer, HEALTH)") -and $recalcPools.Contains("getMaxAttrib(objPlayer, ACTION)") -and $recalcPools.Contains("getMaxAttrib(objPlayer, MIND)") -and -not [regex]::IsMatch($recalcPools, "player_levels|getLevel\(|setMaxAttrib|getPlayerLevelData")) `
    -Name "p14.nine-attribute.progression.pool-recalc-preserves-maxima"
Assert-Contract `
    -Condition ($combatLevelChanged.Contains("recomputeCommandSeries(self)") -and -not [regex]::IsMatch($text.basePlayerScript, "skill\.(setPlayerStatsForLevel|doPlayerLeveling|sendlevelUpStatChangeSystemMessages)\(")) `
    -Name "p14.nine-attribute.progression.base-player-level-hooks-retired"

$creationReady = $true
foreach ($column in @("strength", "quickness", "focus"))
{
    if (-not $text.playerCreation.Contains("getIntValue(`"$column`"") -or -not $text.playerCreation.Contains("modifiers.push_back($column)")) { $creationReady = $false }
}
Assert-Contract -Condition $creationReady -Name "p14.nine-attribute.creation.table-inputs-and-output-vector"

$messageMembers = @([regex]::Matches($text.statMessageHeader, "Archive::AutoVariable<int>\s+m_(?<name>\w+)\s*;") | ForEach-Object { $_.Groups["name"].Value })
$expectedMembers = @("health", "strength", "constitution", "action", "quickness", "stamina", "mind", "focus", "willpower", "pointsLeft")
Assert-Contract `
    -Condition ((($messageMembers -join ",") -ceq ($expectedMembers -join ",")) -and $text.statMessageCpp.Contains("currentTargets[Attributes::Strength]") -and $text.statMessageCpp.Contains("currentTargets[Attributes::Quickness]") -and $text.statMessageCpp.Contains("currentTargets[Attributes::Focus]")) `
    -Name "p14.nine-attribute.stat-migration-message.exact-wire-order"

$ctsGetter = Get-BracedBlock -Text $text.commandCpp -Signature "bool CommandCppFuncs::getPrecuCtsStatAllocation("
$ctsApplier = Get-BracedBlock -Text $text.commandCpp -Signature "bool CommandCppFuncs::applyPrecuCtsStatAllocation("
$ctsSharedApply = Get-BracedBlock -Text $text.commandCpp -Signature "void applyStatMigration(CreatureObject & creature, std::vector<int> const & targets)"
$ctsJniGetter = Get-BracedBlock -Text $text.scriptMethodsAttributes -Signature "jintArray JNICALL ScriptMethodsAttributesNamespace::getPrecuCtsStatAllocation("
$ctsJniApplier = Get-BracedBlock -Text $text.scriptMethodsAttributes -Signature "jboolean JNICALL ScriptMethodsAttributesNamespace::applyPrecuCtsStatAllocation("
$ctsUpload = Get-BracedBlock -Text $text.basePlayerScript -Signature "public int OnUploadCharacter("
$ctsDownload = Get-BracedBlock -Text $text.basePlayerScript -Signature "public int OnDownloadCharacter("

$ctsContractReady = `
    [int]$contract.ctsAllocation.version -eq 1 -and `
    [string]$contract.ctsAllocation.versionKey -ceq "precuCtsStatAllocationVersion" -and `
    [string]$contract.ctsAllocation.allocationKey -ceq "precuCtsStatAllocation" -and `
    [int]$contract.ctsAllocation.attributeCount -eq 9 -and `
    [string]$contract.ctsAllocation.nativeGetterDescriptor -ceq "(J)[I" -and `
    [string]$contract.ctsAllocation.nativeApplierDescriptor -ceq "(J[I)Z"
Assert-Contract -Condition $ctsContractReady -Name "p14.nine-attribute.cts.versioned-exact-nine-contract"

$ctsNativeReady = `
    $text.commandHeader.Contains("getPrecuCtsStatAllocation(NetworkId const & actor, std::vector<int> & allocation)") -and `
    $text.commandHeader.Contains("applyPrecuCtsStatAllocation(NetworkId const & actor, std::vector<int> const & allocation)") -and `
    $ctsGetter.Contains("Attributes::NumberOfAttributes") -and `
    $ctsGetter.Contains("getUnmodifiedMaxAttribute(attribute)") -and `
    $ctsGetter.Contains("validateStatMigrationTargets(*creature, currentAllocation)") -and `
    $ctsGetter.Contains("isPlayerControlled()") -and `
    $ctsApplier.Contains("validateStatMigrationTargets(*creature, allocation)") -and `
    $ctsApplier.Contains("isPlayerControlled()") -and `
    ([regex]::Matches($ctsApplier, [regex]::Escape("applyStatMigration(*creature, allocation)")).Count -eq 1) -and `
    $ctsSharedApply.Contains("int const delta = targets[attribute] - oldMaximum;") -and `
    $ctsSharedApply.Contains("std::max(0, oldCurrent + delta)")
Assert-Contract -Condition $ctsNativeReady -Name "p14.nine-attribute.cts.validated-unmodified-maxima-and-one-atomic-apply"

$ctsBridgeReady = `
    $text.baseClass.Contains("private static native int[] _getPrecuCtsStatAllocation(long target);") -and `
    $text.baseClass.Contains("private static native boolean _applyPrecuCtsStatAllocation(long target, int[] allocation);") -and `
    $text.scriptMethodsAttributes.Contains('JF("_getPrecuCtsStatAllocation", "(J)[I", getPrecuCtsStatAllocation)') -and `
    $text.scriptMethodsAttributes.Contains('JF("_applyPrecuCtsStatAllocation", "(J[I)Z", applyPrecuCtsStatAllocation)') -and `
    $ctsJniGetter.Contains("allocation.size()) != Attributes::NumberOfAttributes") -and `
    $ctsJniGetter.Contains("createNewIntArray(Attributes::NumberOfAttributes)") -and `
    $ctsJniApplier.Contains("GetArrayLength(allocation) != Attributes::NumberOfAttributes") -and `
    $ctsJniApplier.Contains("GetIntArrayRegion(allocation, 0, Attributes::NumberOfAttributes, values)") -and `
    ([regex]::Matches($ctsJniApplier, [regex]::Escape("CommandCppFuncs::applyPrecuCtsStatAllocation")).Count -eq 1)
Assert-Contract -Condition $ctsBridgeReady -Name "p14.nine-attribute.cts.exact-int-array-native-bridge"

$ctsApplyAt = $ctsDownload.IndexOf("applyPrecuCtsStatAllocation(self, precuStatAllocation)", [StringComparison]::Ordinal)
$ctsFlagAt = $ctsDownload.IndexOf('utils.setLocalVar(self, "ctsBeingUnpacked", true)', [StringComparison]::Ordinal)
$ctsTransferredAt = $ctsDownload.IndexOf('setObjVar(self, "hasTransferred", 1)', [StringComparison]::Ordinal)
$ctsSkillAt = $ctsDownload.IndexOf('characterData.getStringArray("skills")', [StringComparison]::Ordinal)
$ctsScriptReady = `
    $ctsUpload.Contains("getPrecuCtsStatAllocation(self)") -and `
    $ctsUpload.Contains("precuStatAllocation.length != NUM_ATTRIBUTES") -and `
    $ctsUpload.Contains("characterData.put(PRECU_CTS_STAT_ALLOCATION_KEY, precuStatAllocation)") -and `
    $ctsDownload.Contains("precuStatAllocation.length != NUM_ATTRIBUTES") -and `
    $ctsApplyAt -ge 0 -and $ctsApplyAt -lt $ctsFlagAt -and `
    $ctsFlagAt -lt $ctsTransferredAt -and $ctsTransferredAt -lt $ctsSkillAt
Assert-Contract -Condition $ctsScriptReady -Name "p14.nine-attribute.cts.exact-nine-applied-before-transfer-replay"

$bonusNamesReady = [regex]::IsMatch($text.tangibleCpp, '(?s)s_attributeBonusNames\[\].*?"health".*?"strength".*?"constitution".*?"action".*?"quickness".*?"stamina".*?"mind".*?"focus".*?"willpower"')
Assert-Contract -Condition $bonusNamesReady -Name "p14.nine-attribute.item-bonus.names-match-wire-order"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 nine-attribute runtime contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 nine-attribute runtime contract passed."
