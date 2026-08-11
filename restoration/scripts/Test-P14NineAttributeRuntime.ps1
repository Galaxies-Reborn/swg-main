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

function Get-CanonicalInventoryHash
{
    param([Parameter(Mandatory = $true)][string[]]$Lines)

    $payload = ($Lines -join "`n") + "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha.Dispose()
    }
}

function Get-SourceRelativePath
{
    param([Parameter(Mandatory = $true)][string]$Path)

    $rootUri = [Uri]($source.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri](Resolve-Path -LiteralPath $Path).Path
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString())
}

function Get-DockerArtifactEvidence
{
    param(
        [Parameter(Mandatory = $true)][string]$Container,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $hashOutput = (& docker exec $Container sha256sum $Path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($hashOutput)) { return $null }
    $statOutput = (& docker exec $Container stat -Lc "%s|%i" $Path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($statOutput)) { return $null }
    $statParts = $statOutput.Split('|')
    if ($statParts.Count -ne 2) { return $null }
    return [pscustomobject]@{
        Sha256 = $hashOutput.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)[0]
        Bytes = [long]$statParts[0]
        Inode = [long]$statParts[1]
    }
}

function Assert-DockerArtifactSet
{
    param(
        [Parameter(Mandatory = $true)][string]$Container,
        [Parameter(Mandatory = $true)][object]$ArtifactSet,
        [Parameter(Mandatory = $true)][bool]$RequireInode,
        [Parameter(Mandatory = $true)][string]$NamePrefix
    )

    foreach ($property in $ArtifactSet.PSObject.Properties)
    {
        $expected = $property.Value
        $actual = Get-DockerArtifactEvidence -Container $Container -Path ([string]$expected.path)
        $inodeMatches = -not $RequireInode -or ($null -ne $actual -and [long]$expected.inode -eq $actual.Inode)
        Assert-Contract `
            -Condition ($null -ne $actual -and [string]$expected.sha256 -ceq $actual.Sha256 -and
                [long]$expected.bytes -eq $actual.Bytes -and $inodeMatches) `
            -Name "$NamePrefix.$($property.Name)"
    }
}

Write-Host "Publish 14.1 nine-attribute runtime checks:"

$wireOrder = @($contract.wireOrder | ForEach-Object { [string]$_ })
$expectedWireOrder = @("Health", "Strength", "Constitution", "Action", "Quickness", "Stamina", "Mind", "Focus", "Willpower")
Assert-Contract `
    -Condition ([int]$contract.schemaVersion -eq 2 -and [string]$contract.feature -ceq "p14-nine-attribute-runtime" -and
        @("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status -and
        (($wireOrder -join ",") -ceq ($expectedWireOrder -join ","))) `
    -Name "p14.nine-attribute.contract.identity-status-and-exact-wire-order"

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

$armorReference = $contract.armorEncumbranceReference
Assert-Contract `
    -Condition ([string]$armorReference.commit -ceq "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8" -and
        [string]$armorReference.files.playerContainer.blob -ceq "2dfdae1b4f08b0793911438cacc97ccf50ddfa2b" -and
        [string]$armorReference.files.playerManager.blob -ceq "bbc07b8266b762e8484781d0dfd140a848dd1170" -and
        [string]$armorReference.files.creatureAggregate.blob -ceq "4806c0cb5f0c85e6c9eea7996f23169d2fa43382" -and
        [string]$armorReference.files.armorTemplate.blob -ceq "2274158a22ae1e09a3a9d1214da47ac2c4b672a0" -and
        [string]$armorReference.files.armorObject.blob -ceq "6118215912f14bd8f7ff03a892fdd841be1fc3ba" -and
        [string]$armorReference.files.armorRuntime.blob -ceq "12a3f626e4090eb7397e41cc29cda5b655db79e6") `
    -Name "p14.nine-attribute.armor.core3-exact-file-and-blob-pins"
Assert-Contract `
    -Condition ([int]$armorReference.playerContainerTemplates.count -eq 20 -and
        [int]$armorReference.playerContainerTemplates.nonPlayerAssignments -eq 0 -and
        [string]$armorReference.playerContainerTemplates.pathInventorySha256 -ceq "473b721ead08450db8cb2081837a49b9973ea6facbd8301efaa36777934dffab" -and
        [string]$armorReference.playerContainerTemplates.pathBlobInventorySha256 -ceq "38f5f9d26c6899b53f718b8d02a6c6367de7814f22f303f5488edab95048fae9") `
    -Name "p14.nine-attribute.armor.core3-player-only-container-boundary"

$armorHashRows = [System.Collections.Generic.List[string]]::new()
$directArmorHashKeys = @(
    "craftingLibrary", "craftingBase", "craftingBaseClothing", "craftingArmorNovice",
    "craftingArmorClothing", "creatureHeader", "creatureCpp", "tangibleCpp")
foreach ($property in $contract.buildEvidence.armorSourceSha256.PSObject.Properties)
{
    $name = [string]$property.Name
    $actualHash = (Get-FileHash -LiteralPath $paths[$name] -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Contract ($actualHash -ceq [string]$property.Value) "p14.nine-attribute.armor.source.$name.authenticated"
    if ($directArmorHashKeys -contains $name)
    {
        $armorHashRows.Add("$([string]$contract.sourceFiles.$name)=$actualHash")
    }
}
Assert-Contract `
    -Condition ((Get-CanonicalInventoryHash -Lines @($armorHashRows | Sort-Object)) -ceq
        [string]$contract.buildEvidence.armorDirectSourceAggregateSha256) `
    -Name "p14.nine-attribute.armor.direct-source-aggregate-authenticated"

$craftingProperty = Get-BracedBlock -Text $text.craftingBase -Signature "public boolean calcAndSetPrototypeProperty("
$manufactureObject = Get-BracedBlock -Text $text.craftingBase -Signature "public int OnManufactureObject("
$clothingProducer = Get-BracedBlock -Text $text.craftingBaseClothing -Signature "public void calcAndSetPrototypeProperties(obj_id prototype, draft_schematic.attribute[] itemAttributes)"
$encumbranceKeys = @("armor_health_encumbrance", "armor_action_encumbrance", "armor_mind_encumbrance")
$producerReady = `
    $text.craftingLibrary.Contains('COMPONENT_ATTRIBUTE_OBJVAR_NAME = "crafting_components"') -and `
    ([regex]::Matches($manufactureObject, [regex]::Escape("calcAndSetPrototypeProperties(newObject, schematic.getAttribs());")).Count -eq 1) -and `
    $text.craftingArmorNovice.Contains("extends script.systems.crafting.clothing.crafting_base_clothing") -and `
    $text.craftingArmorClothing.Contains("extends script.systems.crafting.clothing.crafting_base_clothing") -and `
    ([regex]::Matches($clothingProducer, [regex]::Escape("(itemAttribute.maxValue + itemAttribute.minValue) - itemAttribute.currentValue")).Count -eq 3) -and `
    ([regex]::Matches($clothingProducer, [regex]::Escape("setObjVar(prototype, craftinglib.COMPONENT_ATTRIBUTE_OBJVAR_NAME + `".`" + (itemAttribute.name).getAsciiId(), encum_value);")).Count -eq 3)
foreach ($key in $encumbranceKeys)
{
    $producerReady = $producerReady -and
        ([regex]::Matches($clothingProducer, [regex]::Escape('"' + $key + '"')).Count -eq 1) -and
        -not $craftingProperty.Contains($key)
}
Assert-Contract -Condition $producerReady -Name "p14.nine-attribute.armor.final-object-producer-reachability-and-persistence"

$draftRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/object/draft_schematic/clothing"
$schematicCandidates = [System.Collections.Generic.List[object]]::new()
$schematicShapeReady = $true
foreach ($serverPath in [IO.Directory]::EnumerateFiles($draftRoot, "*.tpf", [IO.SearchOption]::AllDirectories))
{
    $serverText = Get-Content -LiteralPath $serverPath -Raw
    $manufactureMatches = [regex]::Matches($serverText,
        'manufactureScripts\s*=\s*\[\s*"systems\.crafting\.clothing\.(?<script>crafting_armor_(?:novice|clothing))"\s*\]')
    if ($manufactureMatches.Count -eq 0) { continue }
    if ($manufactureMatches.Count -ne 1) { $schematicShapeReady = $false; continue }

    $sharedMatches = [regex]::Matches($serverText, '(?m)^sharedTemplate\s*=\s*"(?<path>[^"\r\n]+\.iff)"\s*$')
    $craftedMatches = [regex]::Matches($serverText, '(?m)^craftedObjectTemplate\s*=\s*"(?<path>[^"\r\n]+\.iff)"\s*$')
    if ($sharedMatches.Count -ne 1 -or $craftedMatches.Count -ne 1)
    {
        $schematicShapeReady = $false
        continue
    }

    $sharedRelative = "dsrc/sku.0/sys.shared/compiled/game/" +
        $sharedMatches[0].Groups["path"].Value.Replace(".iff", ".tpf")
    $sharedPath = Join-Path $source $sharedRelative.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $sharedPath -PathType Leaf))
    {
        $schematicShapeReady = $false
        continue
    }

    $sharedText = Get-Content -LiteralPath $sharedPath -Raw
    $keyCounts = @($encumbranceKeys | ForEach-Object { [regex]::Matches($sharedText, [regex]::Escape($_)).Count })
    $schematicCandidates.Add([pscustomobject]@{
        Server = Get-SourceRelativePath -Path $serverPath
        Shared = Get-SourceRelativePath -Path $sharedPath
        Script = $manufactureMatches[0].Groups["script"].Value
        Shape = $keyCounts -join ","
        ServerHash = (Get-FileHash -LiteralPath $serverPath -Algorithm SHA256).Hash.ToLowerInvariant()
        SharedHash = (Get-FileHash -LiteralPath $sharedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}

$schematicCandidates = @($schematicCandidates | Sort-Object Server)
$tripleSchematics = @($schematicCandidates | Where-Object { $_.Shape -ceq "1,1,1" })
$excludedSchematics = @($schematicCandidates | Where-Object { $_.Shape -ceq "0,0,0" })
$invalidSchematics = @($schematicCandidates | Where-Object { $_.Shape -cne "1,1,1" -and $_.Shape -cne "0,0,0" })
$boundary = $contract.armorEncumbrance.schematicProducerBoundary
$excludedExpected = @($boundary.excludedCompatibilityTemplates | ForEach-Object { [string]$_ } | Sort-Object)
$excludedActual = @($excludedSchematics.Server | Sort-Object)
$candidateNovice = @($schematicCandidates | Where-Object { $_.Script -ceq "crafting_armor_novice" }).Count
$candidateClothing = @($schematicCandidates | Where-Object { $_.Script -ceq "crafting_armor_clothing" }).Count
$tripleNovice = @($tripleSchematics | Where-Object { $_.Script -ceq "crafting_armor_novice" }).Count
$tripleClothing = @($tripleSchematics | Where-Object { $_.Script -ceq "crafting_armor_clothing" }).Count
Assert-Contract `
    -Condition ($schematicShapeReady -and $schematicCandidates.Count -eq [int]$boundary.candidateServerTemplates -and
        $candidateNovice -eq [int]$boundary.candidateNovice -and $candidateClothing -eq [int]$boundary.candidateClothing -and
        $tripleSchematics.Count -eq [int]$boundary.exactTripleTemplates -and
        $tripleNovice -eq [int]$boundary.exactTripleNovice -and $tripleClothing -eq [int]$boundary.exactTripleClothing -and
        $invalidSchematics.Count -eq [int]$boundary.partialOrDuplicateTriples -and
        (($excludedActual -join "|") -ceq ($excludedExpected -join "|"))) `
    -Name "p14.nine-attribute.armor.schematic-boundary-112-to-110-plus-2"

$candidatePaths = @($schematicCandidates.Server | Sort-Object)
$excludedPairs = @($excludedSchematics | ForEach-Object { "$($_.Server)|$($_.Shared)" } | Sort-Object)
$tripleServerPaths = @($tripleSchematics.Server | Sort-Object)
$tripleSharedPaths = @($tripleSchematics.Shared | Sort-Object)
$triplePairs = @($tripleSchematics | ForEach-Object { "$($_.Server)|$($_.Shared)|systems.crafting.clothing.$($_.Script)" } | Sort-Object)
$serverContent = @($tripleSchematics | ForEach-Object { "$($_.Server)=$($_.ServerHash)" } | Sort-Object)
$sharedContent = @($tripleSchematics | ForEach-Object { "$($_.Shared)=$($_.SharedHash)" } | Sort-Object)
$combinedPaths = @((@($tripleServerPaths) + @($tripleSharedPaths)) | Sort-Object)
$combinedContent = @((@($serverContent) + @($sharedContent)) | Sort-Object)
Assert-Contract ((Get-CanonicalInventoryHash $candidatePaths) -ceq [string]$boundary.candidatePathInventorySha256) `
    "p14.nine-attribute.armor.schematic-inventory.candidate-paths"
Assert-Contract ((Get-CanonicalInventoryHash $excludedPairs) -ceq [string]$boundary.excludedPairInventorySha256) `
    "p14.nine-attribute.armor.schematic-inventory.excluded-pairs"
Assert-Contract ((Get-CanonicalInventoryHash $tripleServerPaths) -ceq [string]$boundary.tripleServerPathInventorySha256) `
    "p14.nine-attribute.armor.schematic-inventory.triple-server-paths"
Assert-Contract ((Get-CanonicalInventoryHash $tripleSharedPaths) -ceq [string]$boundary.tripleSharedPathInventorySha256) `
    "p14.nine-attribute.armor.schematic-inventory.triple-shared-paths"
Assert-Contract ((Get-CanonicalInventoryHash $triplePairs) -ceq [string]$boundary.triplePairInventorySha256) `
    "p14.nine-attribute.armor.schematic-inventory.triple-pairs"
Assert-Contract ((Get-CanonicalInventoryHash $serverContent) -ceq [string]$boundary.serverSourceContentSha256) `
    "p14.nine-attribute.armor.schematic-inventory.server-content"
Assert-Contract ((Get-CanonicalInventoryHash $sharedContent) -ceq [string]$boundary.sharedSourceContentSha256) `
    "p14.nine-attribute.armor.schematic-inventory.shared-content"
Assert-Contract ((Get-CanonicalInventoryHash $combinedPaths) -ceq [string]$boundary.combinedPathInventorySha256) `
    "p14.nine-attribute.armor.schematic-inventory.combined-paths"
Assert-Contract ((Get-CanonicalInventoryHash $combinedContent) -ceq [string]$boundary.combinedSourceContentSha256) `
    "p14.nine-attribute.armor.schematic-inventory.combined-content"

$getEncumbrances = Get-BracedBlock -Text $text.tangibleCpp -Signature "bool TangibleObject::getEncumbrances("
$hasEncumbrances = Get-BracedBlock -Text $text.tangibleCpp -Signature "bool TangibleObject::hasEncumbrances() const"
$craftedAt = $getEncumbrances.IndexOf("OBJVAR_PRECU_ARMOR_HEALTH_ENCUMBRANCE", [StringComparison]::Ordinal)
$staticAt = $getEncumbrances.IndexOf("serverTemplate->getArmor()", [StringComparison]::Ordinal)
$laterAt = $getEncumbrances.IndexOf("haveLaterObjVars", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($craftedAt -ge 0 -and $staticAt -gt $craftedAt -and $laterAt -gt $staticAt -and
        $getEncumbrances.Contains("OBJVAR_PRECU_ARMOR_ACTION_ENCUMBRANCE") -and
        $getEncumbrances.Contains("OBJVAR_PRECU_ARMOR_MIND_ENCUMBRANCE") -and
        ([regex]::Matches($getEncumbrances, 'getNonnegativeEncumbranceObjVar').Count -eq 3) -and
        $getEncumbrances.Contains("armorTemplate->getEncumbrance(0)") -and
        $getEncumbrances.Contains("armorTemplate->getEncumbrance(1)") -and
        $getEncumbrances.Contains("armorTemplate->getEncumbrance(2)") -and
        $getEncumbrances.Contains("OBJVAR_ARMOR_ENCUMBRANCE") -and
        $getEncumbrances.Contains("OBJVAR_ENCUMBRANCE_SPLIT") -and
        $getEncumbrances.Contains("OBJVAR_ARMOR_LEVEL") -and
        $getEncumbrances.Contains("DATATABLE_ARMOR") -and
        $hasEncumbrances.Contains("getEncumbrances(encumbrances)")) `
    -Name "p14.nine-attribute.armor.crafted-static-later-authority-precedence"
Assert-Contract `
    -Condition ($text.tangibleCpp.Contains("int integerValue = 0;") -and
        $text.tangibleCpp.Contains("float realValue = 0.0f;") -and
        $text.tangibleCpp.Contains("realValue != realValue") -and
        $text.tangibleCpp.Contains("std::numeric_limits<int>::max()") -and
        $text.tangibleCpp.Contains("value = static_cast<int>(realValue);") -and
        $getEncumbrances.Contains("haveStaticZeroEncumbrance")) `
    -Name "p14.nine-attribute.armor.atomic-nonnegative-crafted-numeric-policy"

$encumbranceGetter = Get-BracedBlock -Text $text.creatureCpp -Signature "int CreatureObject::getPreCuArmorEncumbrance("
$encumbranceRescan = Get-BracedBlock -Text $text.creatureCpp -Signature "bool CreatureObject::recomputePreCuArmorEncumbrances()"
$getAttribute = Get-BracedBlock -Text $text.creatureCpp -Signature "Attributes::Value CreatureObject::getAttribute("
$getAdjusted = Get-BracedBlock -Text $text.creatureCpp -Signature "Attributes::Value CreatureObject::getAdjustedAttribute("
$getMax = Get-BracedBlock -Text $text.creatureCpp -Signature "Attributes::Value CreatureObject::getMaxAttribute("
$armorAdmission = Get-BracedBlock -Text $text.creatureCpp -Signature "int CreatureObject::onContainerAboutToGainItem("
$armorLoad = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::onLoadedFromDatabase()"
$armorGain = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::onContainerGainItem("
$armorLoss = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::onContainerLostItem("
$armorAuthority = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::setAuthority()"
$childGain = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::onContainerChildGainItem("
$childLoss = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::onContainerChildLostItem("
$totalAttributes = Get-BracedBlock -Text $text.creatureCpp -Signature "void CreatureObject::computeTotalAttributes ()"
$memberAt = $text.creatureHeader.IndexOf("std::vector<int>                                 m_preCuArmorEncumbrances", [StringComparison]::Ordinal)
$persistedAt = $text.creatureHeader.IndexOf("// BPM CreatureObject : TangibleObject // Begin persisted members.", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($memberAt -ge 0 -and $persistedAt -gt $memberAt -and
        -not $text.creatureHeader.Contains("AutoDeltaVector<int>                         m_preCuArmorEncumbrances") -and
        $text.creatureCpp.Contains("m_preCuArmorEncumbrances(3, 0)") -and
        -not $encumbranceRescan.Contains("m_attribBonus")) `
    -Name "p14.nine-attribute.armor.dedicated-nonpersistent-derived-aggregate"
$armorDerivedClosure = @($encumbranceGetter, $encumbranceRescan, $armorAdmission) -join "`n"
$armorPlacementClosure = @($getEncumbrances, $hasEncumbrances, $encumbranceGetter, $encumbranceRescan, $armorAdmission) -join "`n"
Assert-Contract `
    -Condition (-not [regex]::IsMatch($armorDerivedClosure,
        'm_attributes\s*[.]\s*set\s*[(]|m_maxAttributes\s*[.]\s*set\s*[(]|\bsetAttribute\s*[(]|\bsetMaxAttribute\s*[(]|\balterAttribute\s*[(]|m_attribBonus\s*(?:\[|[.]\s*set|=|[+][+]|--|[+]=|-=)')) `
    -Name "p14.nine-attribute.armor.derived-closure-does-not-mutate-persisted-or-bonus-state"
Assert-Contract `
    -Condition ($encumbranceRescan.Contains("!isAuthoritative() || !isPlayerControlled()") -and
        $encumbranceRescan.Contains("ContainerInterface::getContainer(*this)") -and
        $encumbranceRescan.Contains("isArmorObject(*item)") -and
        $encumbranceRescan.Contains("totals[group]") -and
        -not [regex]::IsMatch($armorPlacementClosure, "isInAppearanceSlot|isAppearanceArrangement|getCurrentArrangement|getAppearanceInventory") -and
        -not [regex]::IsMatch($encumbranceRescan, "onContainerChild|recursive") -and
        -not $childGain.Contains("recomputePreCuArmorEncumbrances") -and
        -not $childLoss.Contains("recomputePreCuArmorEncumbrances")) `
    -Name "p14.nine-attribute.armor.player-authority-direct-container-not-appearance"
Assert-Contract `
    -Condition ($armorAdmission.Contains("isAuthoritative() && isPlayerControlled() && isArmorObject(*object)") -and
        $armorAdmission.Contains("health >= getAttribute(Attributes::Strength)") -and
        $armorAdmission.Contains("health >= getAttribute(Attributes::Constitution)") -and
        $armorAdmission.Contains("action >= getAttribute(Attributes::Quickness)") -and
        $armorAdmission.Contains("action >= getAttribute(Attributes::Stamina)") -and
        $armorAdmission.Contains("mind >= getAttribute(Attributes::Focus)") -and
        $armorAdmission.Contains("mind >= getAttribute(Attributes::Willpower)") -and
        $getAttribute.Contains("getAdjustedAttribute(attribute, m_attributes[attribute])")) `
    -Name "p14.nine-attribute.armor.adjusted-six-secondary-strict-admission"
Assert-Contract `
    -Condition ($encumbranceGetter.Contains("Attributes::Strength") -and $encumbranceGetter.Contains("Attributes::Constitution") -and
        $encumbranceGetter.Contains("Attributes::Quickness") -and $encumbranceGetter.Contains("Attributes::Stamina") -and
        $encumbranceGetter.Contains("Attributes::Focus") -and $encumbranceGetter.Contains("Attributes::Willpower") -and
        -not $encumbranceGetter.Contains("case Attributes::Health:") -and
        -not $encumbranceGetter.Contains("case Attributes::Action:") -and
        -not $encumbranceGetter.Contains("case Attributes::Mind:") -and
        $getAdjusted.Contains("getPreCuArmorEncumbrance(attribute)") -and
        $getMax.Contains("getPreCuArmorEncumbrance(attribute)") -and
        $totalAttributes.Contains("m_totalAttributes.set(i, getAttribute(i))") -and
        $totalAttributes.Contains("m_totalMaxAttributes.set(i, getMaxAttribute(i))")) `
    -Name "p14.nine-attribute.armor.exact-six-secondary-current-max-publication"
Assert-Contract `
    -Condition (([regex]::Matches($armorLoad, "recomputePreCuArmorEncumbrances")).Count -eq 1 -and
        $armorLoad.IndexOf("TangibleObject::onLoadedFromDatabase();", [StringComparison]::Ordinal) -ge 0 -and
        $armorLoad.IndexOf("recomputePreCuArmorEncumbrances()", [StringComparison]::Ordinal) -ge 0 -and
        $armorLoad.IndexOf("TangibleObject::onLoadedFromDatabase();", [StringComparison]::Ordinal) -lt
            $armorLoad.IndexOf("recomputePreCuArmorEncumbrances()", [StringComparison]::Ordinal) -and
        ([regex]::Matches($armorGain, "recomputePreCuArmorEncumbrances")).Count -eq 1 -and
        ([regex]::Matches($armorLoss, "recomputePreCuArmorEncumbrances")).Count -eq 1 -and
        ([regex]::Matches($armorAuthority, "recomputePreCuArmorEncumbrances")).Count -eq 1) `
    -Name "p14.nine-attribute.armor.full-rescan-load-gain-loss-authority"

$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
Assert-Contract `
    -Condition ($dsrcPin.Count -eq 1 -and $srcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
        [string]$srcPin[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    -Name "p14.nine-attribute.armor.direct-source-gitlinks"

$status = [string]$contract.status
$requirements = @($contract.requiredBeforeReady)
$statusEvidenceReady = switch ($status)
{
    "implemented-build-pending" {
        [string]$contract.buildEvidence.result -ceq "pending" -and
        [string]$contract.runtimeEvidence.result -ceq "pending" -and $requirements.Count -ge 2
    }
    "implemented-build-verified-live-pending" {
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and $requirements.Count -ge 1
    }
    "ready" {
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.liveArmorEncumbranceTest -ceq "passed" -and $requirements.Count -eq 0
    }
    default { $false }
}
Assert-Contract -Condition $statusEvidenceReady -Name "p14.nine-attribute.armor.truthful-status-evidence-transition"

if ($Expectation -in @("Build", "Ready"))
{
    Assert-Contract `
        -Condition ($status -in @("implemented-build-verified-live-pending", "ready") -and
            [string]$contract.buildEvidence.sourceWorkParity.result -ceq "passed" -and
            [string]$contract.buildEvidence.fullJavaCompile.result -ceq "passed" -and
            [string]$contract.buildEvidence.compiledJavaArtifacts.result -ceq "passed" -and
            [string]$contract.buildEvidence.compiledDataArtifacts.result -ceq "passed" -and
            [string]$contract.buildEvidence.nativeObjectArtifacts.result -ceq "passed" -and
            [string]$contract.buildEvidence.nativeArchiveArtifacts.result -ceq "passed" -and
            [string]$contract.buildEvidence.serverBinary.result -ceq "passed" -and
            [string]$contract.buildEvidence.fullX64Build -ceq "passed") `
        -Name "p14.nine-attribute.armor.build-artifact-evidence"

    $container = [string]$contract.runtimeEvidence.container
    Assert-Contract `
        -Condition (-not [string]::IsNullOrWhiteSpace($container) -and
            [int]$contract.buildEvidence.sourceWorkParity.directCheckedFiles -eq 8 -and
            [int]$contract.buildEvidence.sourceWorkParity.schematicCheckedFiles -eq 224 -and
            [int]$contract.buildEvidence.sourceWorkParity.matchedFiles -eq 232 -and
            [bool]$contract.buildEvidence.fullJavaCompile.zeroClassDependencyClean -and
            [int]$contract.buildEvidence.fullJavaCompile.expectedSourceCount -eq 5717 -and
            [int]$contract.buildEvidence.fullJavaCompile.expectedClassCount -eq 5751 -and
            [int]$contract.buildEvidence.fullJavaCompile.sourceCount -eq 5717 -and
            [int]$contract.buildEvidence.fullJavaCompile.classCount -eq 5751) `
        -Name "p14.nine-attribute.armor.clean-build-and-parity-cardinality"

    $directParityMatches = 0
    foreach ($name in $directArmorHashKeys)
    {
        $relativePath = ([string]$contract.sourceFiles.$name).Replace('\', '/')
        & docker exec $container cmp -s "/swg-precu-source/$relativePath" "/swg-precu/$relativePath"
        if ($LASTEXITCODE -eq 0) { ++$directParityMatches }
    }
    Assert-Contract ($directParityMatches -eq 8) "p14.nine-attribute.armor.live-direct-source-work-parity"

    $schematicParityMatches = 0
    foreach ($schematic in $schematicCandidates)
    {
        foreach ($relativePath in @([string]$schematic.Server, [string]$schematic.Shared))
        {
            & docker exec $container cmp -s "/swg-precu-source/$relativePath" "/swg-precu/$relativePath"
            if ($LASTEXITCODE -eq 0) { ++$schematicParityMatches }
        }
    }
    Assert-Contract ($schematicParityMatches -eq 224) "p14.nine-attribute.armor.live-schematic-source-work-parity"

    $javaArtifacts = $contract.buildEvidence.compiledJavaArtifacts.artifacts
    $nativeObjects = $contract.buildEvidence.nativeObjectArtifacts.artifacts
    $nativeArchives = $contract.buildEvidence.nativeArchiveArtifacts.artifacts
    Assert-Contract `
        -Condition (@($javaArtifacts.PSObject.Properties).Count -eq 4 -and
            @($nativeObjects.PSObject.Properties).Count -eq 2 -and
            @($nativeArchives.PSObject.Properties).Count -eq 1) `
        -Name "p14.nine-attribute.armor.focused-artifact-cardinality"
    Assert-DockerArtifactSet -Container $container -ArtifactSet $javaArtifacts -RequireInode $false `
        -NamePrefix "p14.nine-attribute.armor.class"
    Assert-DockerArtifactSet -Container $container -ArtifactSet $nativeObjects -RequireInode $true `
        -NamePrefix "p14.nine-attribute.armor.native-object"
    Assert-DockerArtifactSet -Container $container -ArtifactSet $nativeArchives -RequireInode $true `
        -NamePrefix "p14.nine-attribute.armor.native-archive"

    $focusedArtifactProbe = @'
set -eu
class_root=/swg-precu/data/sku.0/sys.server/compiled/game
creature_object=/swg-precu/build/engine/server/library/serverGame/src/CMakeFiles/serverGame.dir/shared/object/CreatureObject.cpp.o
tangible_object=/swg-precu/build/engine/server/library/serverGame/src/CMakeFiles/serverGame.dir/shared/object/TangibleObject.cpp.o
server_game_archive=/swg-precu/build/engine/server/library/serverGame/src/libserverGame.a
binary=/swg-precu/build/bin/SwgGameServer
for armor_class in \
    "$class_root/script/library/craftinglib.class" \
    "$class_root/script/systems/crafting/clothing/crafting_base_clothing.class" \
    "$class_root/script/systems/crafting/clothing/crafting_armor_novice.class" \
    "$class_root/script/systems/crafting/clothing/crafting_armor_clothing.class"
do
    test -f "$armor_class"
done
craftinglib_constants="$(javap -classpath "$class_root" -constants -p script.library.craftinglib)"
printf '%s' "$craftinglib_constants" | grep -Fq 'COMPONENT_ATTRIBUTE_OBJVAR_NAME'
printf '%s' "$craftinglib_constants" | grep -Fq 'crafting_components'
armor_base_bytecode="$(javap -classpath "$class_root" -c -p script.systems.crafting.crafting_base)"
printf '%s' "$armor_base_bytecode" | grep -Fq 'calcAndSetPrototypeProperties'
armor_producer_bytecode="$(javap -classpath "$class_root" -c -p script.systems.crafting.clothing.crafting_base_clothing)"
for armor_key in armor_health_encumbrance armor_action_encumbrance armor_mind_encumbrance
do
    test "$(printf '%s' "$armor_producer_bytecode" | grep -Fc "$armor_key")" -eq 1
done
test "$(printf '%s' "$armor_producer_bytecode" | grep -Fc 'fadd')" -eq 3
test "$(printf '%s' "$armor_producer_bytecode" | grep -Fc 'fsub')" -eq 3
javap -classpath "$class_root" -p script.systems.crafting.clothing.crafting_armor_novice | grep -Fq 'extends script.systems.crafting.clothing.crafting_base_clothing'
javap -classpath "$class_root" -p script.systems.crafting.clothing.crafting_armor_clothing | grep -Fq 'extends script.systems.crafting.clothing.crafting_base_clothing'
for armor_symbol_artifact in "$creature_object" "$server_game_archive"
do
    nm -C "$armor_symbol_artifact" | grep -Fq 'CreatureObject::recomputePreCuArmorEncumbrances()'
    nm -C "$armor_symbol_artifact" | grep -Fq 'CreatureObject::getPreCuArmorEncumbrance(int) const'
    nm -C "$armor_symbol_artifact" | grep -Fq 'CreatureObject::getAdjustedAttribute(int, int) const'
    nm -C "$armor_symbol_artifact" | grep -Fq 'CreatureObject::getMaxAttribute(int, bool) const'
    nm -C "$armor_symbol_artifact" | grep -Fq 'CreatureObject::onContainerAboutToGainItem('
    nm -C "$armor_symbol_artifact" | grep -Fq 'CreatureObject::onLoadedFromDatabase()'
    nm -C "$armor_symbol_artifact" | grep -Fq 'CreatureObject::onContainerGainItem('
    nm -C "$armor_symbol_artifact" | grep -Fq 'CreatureObject::onContainerLostItem('
done
for armor_symbol_artifact in "$tangible_object" "$server_game_archive"
do
    nm -C "$armor_symbol_artifact" | grep -Fq 'TangibleObject::getEncumbrances(std::vector<int, std::allocator<int> >&) const'
    nm -C "$armor_symbol_artifact" | grep -Fq 'TangibleObject::hasEncumbrances() const'
done
strings "$binary" | grep -Fq 'crafting_components.armor_health_encumbrance'
strings "$binary" | grep -Fq 'crafting_components.armor_action_encumbrance'
strings "$binary" | grep -Fq 'crafting_components.armor_mind_encumbrance'
'@
    $focusedArtifactProbe | docker exec -i $container bash
    Assert-Contract ($LASTEXITCODE -eq 0) "p14.nine-attribute.armor.focused-class-native-binary-probes"

    $compiledServerPaths = @($tripleServerPaths | ForEach-Object {
        ($_ -replace '^dsrc/', 'data/') -replace '[.]tpf$', '.iff'
    } | Sort-Object)
    $compiledSharedPaths = @($tripleSharedPaths | ForEach-Object {
        ($_ -replace '^dsrc/', 'data/') -replace '[.]tpf$', '.iff'
    } | Sort-Object)
    $compiledCombinedPaths = @((@($compiledServerPaths) + @($compiledSharedPaths)) | Sort-Object)
    Assert-Contract `
        -Condition ($compiledServerPaths.Count -eq 110 -and $compiledSharedPaths.Count -eq 110 -and
            (Get-CanonicalInventoryHash $compiledServerPaths) -ceq [string]$boundary.compiledServerPathInventorySha256 -and
            (Get-CanonicalInventoryHash $compiledSharedPaths) -ceq [string]$boundary.compiledSharedPathInventorySha256 -and
            (Get-CanonicalInventoryHash $compiledCombinedPaths) -ceq [string]$boundary.compiledCombinedPathInventorySha256) `
        -Name "p14.nine-attribute.armor.compiled-iff-path-inventories"

    $compiledArtifactRows = [System.Collections.Generic.List[string]]::new()
    [long]$compiledArtifactBytes = 0
    foreach ($relativePath in $compiledCombinedPaths)
    {
        $actual = Get-DockerArtifactEvidence -Container $container -Path "/swg-precu/$relativePath"
        if ($null -ne $actual)
        {
            $compiledArtifactRows.Add("$relativePath=$($actual.Sha256)|$($actual.Bytes)")
            $compiledArtifactBytes += $actual.Bytes
        }
    }
    Assert-Contract `
        -Condition ($compiledArtifactRows.Count -eq 220 -and
            [int]$contract.buildEvidence.compiledDataArtifacts.serverCount -eq 110 -and
            [int]$contract.buildEvidence.compiledDataArtifacts.sharedCount -eq 110 -and
            [int]$contract.buildEvidence.compiledDataArtifacts.combinedCount -eq 220 -and
            (Get-CanonicalInventoryHash @($compiledArtifactRows | Sort-Object)) -ceq
                [string]$contract.buildEvidence.compiledDataArtifacts.artifactInventorySha256 -and
            $compiledArtifactBytes -eq [long]$contract.buildEvidence.compiledDataArtifacts.totalBytes) `
        -Name "p14.nine-attribute.armor.220-compiled-iff-identities"

    $binaryExpected = $contract.buildEvidence.serverBinary
    $binaryActual = Get-DockerArtifactEvidence -Container $container -Path ([string]$binaryExpected.path)
    Assert-Contract `
        -Condition ($null -ne $binaryActual -and [string]$binaryExpected.sha256 -ceq $binaryActual.Sha256 -and
            [long]$binaryExpected.bytes -eq $binaryActual.Bytes -and
            [long]$binaryExpected.inode -eq $binaryActual.Inode) `
        -Name "p14.nine-attribute.armor.server-binary-identity"
    $binaryFile = (& docker exec $container file -L ([string]$binaryExpected.path) 2>&1 | Out-String)
    $fileExit = $LASTEXITCODE
    $binaryNotes = (& docker exec $container readelf -n ([string]$binaryExpected.path) 2>&1 | Out-String)
    $notesExit = $LASTEXITCODE
    Assert-Contract `
        -Condition ($fileExit -eq 0 -and $notesExit -eq 0 -and $binaryFile.Contains("ELF 64-bit") -and
            $binaryFile.Contains("x86-64") -and
            $binaryNotes.Contains([string]$binaryExpected.buildIdSha1)) `
        -Name "p14.nine-attribute.armor.server-binary-elf64-build-id"

    $inspection = @((& docker inspect $container 2>&1 | Out-String) | ConvertFrom-Json)[0]
    Assert-Contract `
        -Condition ([string]$inspection.State.Status -ceq "running" -and
            [string]$inspection.State.Health.Status -ceq [string]$contract.runtimeEvidence.containerHealth -and
            [string]$inspection.State.StartedAt -ceq [string]$contract.runtimeEvidence.containerStartedAt -and
            [bool]$contract.runtimeEvidence.clusterReadyForPlayers) `
        -Name "p14.nine-attribute.armor.deployed-container-ready"

    $gamePids = @(& docker exec $container pgrep -f "bin/SwgGameServer")
    $mappedCount = 0
    foreach ($gamePidValue in $gamePids)
    {
        $gamePid = ([string]$gamePidValue).Trim()
        if ([string]::IsNullOrWhiteSpace($gamePid)) { continue }
        $processIdentity = (& docker exec $container stat -Lc "%i|%s" "/proc/$gamePid/exe" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and
            $processIdentity -ceq "$($contract.runtimeEvidence.liveBinaryInode)|$($contract.runtimeEvidence.liveBinarySizeBytes)")
        {
            ++$mappedCount
        }
    }
    Assert-Contract `
        -Condition ($gamePids.Count -eq 15 -and $mappedCount -eq 15 -and
            [int]$contract.runtimeEvidence.liveGameProcessCount -eq 15 -and
            [int]$contract.runtimeEvidence.mappedLiveGameProcessCount -eq 15 -and
            [bool]$contract.runtimeEvidence.allLiveGameProcessesMatchBinary -and
            $null -ne $binaryActual -and [long]$contract.runtimeEvidence.liveBinaryInode -eq $binaryActual.Inode -and
            [long]$contract.runtimeEvidence.liveBinarySizeBytes -eq $binaryActual.Bytes) `
        -Name "p14.nine-attribute.armor.all-15-live-processes-map-binary"

    $logs = (& docker logs --since ([string]$contract.runtimeEvidence.containerStartedAt) $container 2>&1 | Out-String)
    $badLogLines = @($logs -split "`n" | Select-String -Pattern '\bFATAL\b|\bSEVERE\b|\bERROR\b|Exception|undefined symbol|ABI mismatch|ORA-|ConGenericMessage constructed with empty message|Segmentation fault|segfault')
    $readyMarkers = @($logs -split "`n" | Select-String -SimpleMatch "Cluster swg is ready for players.")
    Assert-Contract `
        -Condition ($badLogLines.Count -eq 0 -and $readyMarkers.Count -ge 1 -and
            [string]$contract.runtimeEvidence.postStartLogAudit.result -ceq "passed") `
        -Name "p14.nine-attribute.armor.clean-ready-post-start-logs"

    if ($Expectation -eq "Build")
    {
        Assert-Contract `
            -Condition ($status -ceq "implemented-build-verified-live-pending" -and
                [string]$contract.runtimeEvidence.liveArmorEncumbranceTest -ceq "pending" -and
                $requirements.Count -eq 1) `
            -Name "p14.nine-attribute.armor.build-verified-live-test-pending"
    }
}

if ($Expectation -eq "Ready")
{
    Assert-Contract `
        -Condition ($status -ceq "ready" -and $requirements.Count -eq 0 -and
            [string]$contract.runtimeEvidence.liveArmorEncumbranceTest -ceq "passed") `
        -Name "p14.nine-attribute.armor.controlled-live-test-complete"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 nine-attribute runtime contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 nine-attribute runtime contract passed."
