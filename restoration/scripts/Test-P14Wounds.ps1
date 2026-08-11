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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Wounds)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized wound source is missing: $path"
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

Write-Host "Publish 14.1 Core3 wound checks:"
$srcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "src"
})
$dsrcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "dsrc"
})
Assert-Contract -Condition (
    $srcPin.Count -eq 1 -and
    [string]$srcPin[0].commit -ceq
        [string]$contract.buildEvidence.nativeSourceCommit -and
    [string]$srcPin[0].commit -ceq
        "a3c6478673377c7aa2dcc00194af63ee56ee7425") `
    -Name "p14.wounds.native.committed-source-pin"
Assert-Contract -Condition (
    $dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq
        [string]$contract.buildEvidence.javaSourceCommit) `
    -Name "p14.wounds.java.committed-source-pin"
$nativeSourceNames = @(
    "creatureController",
    "creatureSource",
    "creatureHeader",
    "alterAttributeMessageSource",
    "alterAttributeMessageHeader",
    "scriptFunctionTable",
    "scriptFunctionHeader",
    "attributeNatives")
foreach ($nativeSourceName in $nativeSourceNames)
{
    $expectedHash =
        $contract.buildEvidence.nativeSourceSha256.psobject.Properties[
            $nativeSourceName].Value
    $actualHash =
        (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $paths[$nativeSourceName]).Hash.ToLowerInvariant()
    Assert-Contract -Condition (
        [string]$actualHash -ceq [string]$expectedHash) `
        -Name "p14.wounds.native.source.$nativeSourceName.authenticated"
}
$javaSourceNames = @(
    "baseClass",
    "healingLibrary",
    "basePlayer",
    "eventTool")
foreach ($javaSourceName in $javaSourceNames)
{
    $expectedHash =
        $contract.buildEvidence.javaSourceSha256.psobject.Properties[
            $javaSourceName].Value
    $actualHash =
        (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $paths[$javaSourceName]).Hash.ToLowerInvariant()
    Assert-Contract -Condition (
        [string]$actualHash -ceq [string]$expectedHash) `
        -Name "p14.wounds.java.source.$javaSourceName.authenticated"
}
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [int]$contract.semanticReference.rollMinimum -eq 0 -and
    [int]$contract.semanticReference.rollMaximum -eq 100 -and
    [string]$contract.semanticReference.successComparator -ceq
        "roll < woundsRatio" -and
    [int]$contract.semanticReference.woundsPerSuccessfulEvent -eq 3 -and
    [int]$contract.semanticReference.shockAttemptsPerSuccessfulEvent -eq 3) `
    -Name "p14.wounds.core3.pin-roll-and-linked-count"

$profileRows = @(Import-SwgTab -Path $paths.weaponProfiles)
$expectedProfiles = $contract.semanticReference.profiles.psobject.Properties
foreach ($profile in $expectedProfiles)
{
    $rows = @($profileRows | Where-Object {
        [string]$_.templateName -ceq [string]$profile.Name
    })
    Assert-Contract -Condition (
        $rows.Count -eq 1 -and
        [int]$rows[0].woundsRatio -eq [int]$profile.Value) `
        -Name "p14.wounds.profile.$([string]$profile.Name)"
}

$buildFile = Get-Content -LiteralPath $paths.buildFile -Raw
$dockerEntrypoint = Get-Content -LiteralPath $paths.dockerEntrypoint -Raw
$packageData = Get-Content -LiteralPath $paths.packageData -Raw
$databaseConfig = Get-Content -LiteralPath $paths.databaseConfig -Raw
$generatedPackager = Get-Content -LiteralPath $paths.generatedPackager -Raw
$creatureHeader = Get-Content -LiteralPath $paths.creatureHeader -Raw
$creatureSource = Get-Content -LiteralPath $paths.creatureSource -Raw
$creatureController = Get-Content -LiteralPath $paths.creatureController -Raw
$attributeNatives = Get-Content -LiteralPath $paths.attributeNatives -Raw
$scriptFunctionHeader = Get-Content -LiteralPath $paths.scriptFunctionHeader -Raw
$scriptFunctionTable = Get-Content -LiteralPath $paths.scriptFunctionTable -Raw
$alterAttributeMessageHeader = Get-Content -LiteralPath $paths.alterAttributeMessageHeader -Raw
$alterAttributeMessageSource = Get-Content -LiteralPath $paths.alterAttributeMessageSource -Raw
$databaseVersionQuery = Get-Content -LiteralPath $paths.databaseVersionQuery -Raw
$databaseMigration = Get-Content -LiteralPath $paths.databaseMigration -Raw
$baseClass = Get-Content -LiteralPath $paths.baseClass -Raw
$utils = Get-Content -LiteralPath $paths.utils -Raw
$healingLibrary = Get-Content -LiteralPath $paths.healingLibrary -Raw
$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$eventTool = Get-Content -LiteralPath $paths.eventTool -Raw
$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$combatPlayer = Get-Content -LiteralPath $paths.combatPlayer -Raw
$liveFixture = Get-Content -LiteralPath $paths.liveFixture -Raw

$addWound = Get-BracedBlock -Text $creatureSource -Signature "int CreatureObject::addWound("
$healWound = Get-BracedBlock -Text $creatureSource -Signature "int CreatureObject::healWound("
$nativeHealDamage = Get-BracedBlock -Text $creatureSource -Signature "int CreatureObject::healDamage("
$alterAttribute = Get-BracedBlock -Text $creatureSource -Signature "int CreatureObject::alterAttribute("
$sourceAwareFourArgumentHeal = Get-BracedBlock -Text $healingLibrary `
    -Signature "public static int healDamage(obj_id source, obj_id target, int attrib, int amount)"
$sourceLessHeal = Get-BracedBlock -Text $healingLibrary `
    -Signature "public static boolean healDamage(obj_id player, int attrib, int amt)"
$avoidIncapRestore = Get-BracedBlock -Text $basePlayer `
    -Signature "public boolean performCriticalHeal("
$eventDamageShim = Get-BracedBlock -Text $eventTool `
    -Signature "public int eventDamage("
$scriptWounds = Get-BracedBlock -Text $combatBase -Signature "public void applyPrecuWounds("
$damage = Get-BracedBlock -Text $combatBase -Signature "public void doWrappedDamage(obj_id attacker, obj_id defender, weapon_data weaponData, hit_result hitData, combat_data actionData, int overloadDamage)"
$exitedCombat = Get-BracedBlock -Text $combatPlayer -Signature "public int OnExitedCombat("
$fixtureRestore = Get-BracedBlock -Text $liveFixture -Signature "private boolean restoreFixtureWounds("
$updateDatabaseStart = $buildFile.IndexOf('<target name="update_database"', [StringComparison]::Ordinal)
$updateDatabaseEnd = if ($updateDatabaseStart -ge 0)
{
    $buildFile.IndexOf("</target>", $updateDatabaseStart, [StringComparison]::Ordinal)
}
else
{
    -1
}
$updateDatabase = if ($updateDatabaseStart -ge 0 -and $updateDatabaseEnd -gt $updateDatabaseStart)
{
    $buildFile.Substring(
        $updateDatabaseStart,
        $updateDatabaseEnd - $updateDatabaseStart)
}
else
{
    ""
}
$allWoundColumnsReset = $true
foreach ($column in 18..26)
{
    $allWoundColumnsReset = $allWoundColumnsReset -and
        $databaseMigration.Contains("attribute_$column = 0")
}

Assert-Contract -Condition (
    $creatureHeader.Contains("int                 getWoundAmount") -and
    $creatureHeader.Contains("int                 addWound") -and
    $creatureHeader.Contains("int                 healWound") -and
    $creatureHeader.Contains(
        "Archive::AutoDeltaVector<Attributes::Value>      m_wounds")) `
    -Name "p14.wounds.native.explicit-api"
Assert-Contract -Condition (
    $packageData.Contains(
        "m_wounds                 server               Attributes::Value - encodeAttributes(objectId,data,18); decodeAttributes(objectId,data,isBaseline,18);") -and
    $generatedPackager.Contains("addServerVariable    (m_wounds);") -and
    $creatureSource.Contains("m_wounds(Attributes::NumberOfAttributes)") -and
    $creatureSource.Contains("m_wounds.set(i, 0);") -and
    $creatureSource.Contains("return m_wounds[attribute];")) `
    -Name "p14.wounds.native.persistent-autodelta-vector"
Assert-Contract -Condition (
    $addWound.Contains("getUnmodifiedMaxAttribute(attribute) - 1") -and
    $addWound.Contains("m_wounds.set(attribute") -and
    $addWound.Contains("Attributes::isAttribPool(attribute)") -and
    $addWound.Contains("current > woundedMax") -and
    $creatureSource.Contains("if (!Attributes::isAttribPool(attribute))") -and
    $creatureSource.Contains("m_attribBonus[attribute] - m_wounds[attribute]")) `
    -Name "p14.wounds.native.cap-primary-and-secondary-semantics"
Assert-Contract -Condition (
    $healWound.Contains("int const wound = getWoundAmount(attribute);") -and
    $healWound.Contains("int const healed = value < wound ? value : wound;") -and
    $healWound.Contains("m_wounds.set(attribute") -and
    $healWound.Contains("computeTotalAttributes();")) `
    -Name "p14.wounds.native.attribute-scoped-healing"
Assert-Contract -Condition (
    $databaseConfig.Contains("KEY_INT     (expectedDBVersion, 272);") -and
    $databaseVersionQuery.Contains(
        "select version_number from version_number;") -and
    $allWoundColumnsReset -and
    $databaseMigration.Contains(
        "update version_number set version_number=272, min_version_number=272;")) `
    -Name "p14.wounds.database.versioned-columns-18-through-26"
Assert-Contract -Condition (
    $updateDatabase.Contains('failonerror="true"') -and
    $dockerEntrypoint.Contains("run_ant update_database") -and
    $dockerEntrypoint.IndexOf(
        "run_ant update_database", [StringComparison]::Ordinal) -lt
        $dockerEntrypoint.IndexOf(
            "run_ant update_configs", [StringComparison]::Ordinal)) `
    -Name "p14.wounds.database.fail-closed-runtime-migration"
Assert-Contract -Condition (
    $attributeNatives.Contains('JF("_addWound", "(JII)I", addWound)') -and
    $attributeNatives.Contains('JF("_healWound", "(JII)I", healWound)') -and
    $attributeNatives.Contains(
        "creature->getMaxAttribute(attribute) + creature->getWoundAmount(attribute)") -and
    $baseClass.Contains("private static native int _addWound") -and
    $baseClass.Contains("private static native int _healWound")) `
    -Name "p14.wounds.native.script-bridge-and-max-distinction"
Assert-Contract -Condition (
    $scriptFunctionHeader.Contains("TRIG_HEALING_RECEIVED = 308,") -and
    $scriptFunctionTable.Contains('{Scripting::TRIG_HEALING_RECEIVED, "OnHealingReceived", "Oi"}') -and
    $attributeNatives.Contains('JF("_healDamage", "(JJIIZ)I", healDamage)') -and
    $attributeNatives.Contains("jint JNICALL ScriptMethodsAttributesNamespace::healDamage") -and
    $attributeNatives.Contains("Attributes::isAttribPool(attrib)") -and
    $attributeNatives.Contains("amount <= 0") -and
    $attributeNatives.Contains("creature->healDamage") -and
    $attributeNatives.Contains("notifyHealingReceived != JNI_FALSE") -and
    $creatureHeader.Contains("healDamage               (Attributes::Enumerator attribute, int amount, NetworkId const & healer, bool notifyHealingReceived)") -and
    $nativeHealDamage.Contains("Attributes::isAttribPool(attribute)") -and
    $nativeHealDamage.Contains("amount <= 0 || !healer.isValid()") -and
    $nativeHealDamage.Contains("return alterAttribute(attribute, amount, true, healer, false,") -and
    $baseClass.Contains("private static native int _healDamage(long target, long healer, int attrib, int amount, boolean notifyHealingReceived);") -and
    $baseClass.Contains("public static int applyDamageHealing(obj_id target, obj_id healer, int attrib, int amount, boolean notifyHealingReceived)")) `
    -Name "p14.wounds.native.explicit-healing-observer-jni-and-trigger"
Assert-Contract -Condition (
    $creatureHeader.Contains("bool notifyHealingReceived = false") -and
    $alterAttribute.Contains("notifyHealingReceived && delta > 0 && source.isValid()") -and
    $alterAttribute.Contains("int const appliedDelta = delta + attribModChange + regenChange;") -and
    $alterAttribute.Contains("ServerWorld::findObjectByNetworkId(source)") -and
    $alterAttribute.Contains("params.addParam(healer->getNetworkId());") -and
    $alterAttribute.Contains("params.addParam(appliedDelta);") -and
    $alterAttribute.Contains("Scripting::TRIG_HEALING_RECEIVED") -and
    -not $alterAttribute.Contains("appliedDelta > 0") -and
    $alterAttribute.IndexOf("int const appliedDelta", [StringComparison]::Ordinal) -lt
        $alterAttribute.IndexOf("Scripting::TRIG_HEALING_RECEIVED", [StringComparison]::Ordinal)) `
    -Name "p14.wounds.native.post-mutation-observer-including-zero-applied-delta"
Assert-Contract -Condition (
    $alterAttributeMessageHeader.Contains("bool notifyHealingReceived = false") -and
    $alterAttributeMessageHeader.Contains("bool              getNotifyHealingReceived() const;") -and
    $alterAttributeMessageHeader.Contains("NetworkId         m_source;") -and
    -not $alterAttributeMessageHeader.Contains("const NetworkId & m_source;") -and
    $alterAttributeMessageHeader.Contains("bool              m_notifyHealingReceived;") -and
    $alterAttributeMessageSource.Contains("Archive::put(target, msg->m_notifyHealingReceived);") -and
    $alterAttributeMessageSource.Contains("Archive::get(source, notifyHealingReceived);") -and
    $alterAttributeMessageSource.Contains("attacker, notifyHealingReceived)") -and
    $creatureController.Contains("msg->getNotifyHealingReceived()")) `
    -Name "p14.wounds.native-controller-message-preserves-healer-and-notify-flag"
$javaObserverRouting = $contract.nativeContract.javaObserverRouting
Assert-Contract -Condition (
    [bool]$javaObserverRouting.sourceAwareFourArgumentDefaultNotifies -and
    [int]$javaObserverRouting.sourceAwareFourArgumentBattleFatigueCreditsPerPositiveHeal -eq 1 -and
    -not [bool]$javaObserverRouting.sourceLessAttributeHelpersNotify -and
    -not [bool]$javaObserverRouting.avoidIncapRestoreNotifies -and
    -not [bool]$javaObserverRouting.eventToolAdminShimNotifies -and
    -not [string]::IsNullOrEmpty($sourceAwareFourArgumentHeal) -and
    $sourceAwareFourArgumentHeal.Contains(
        "healDamage(source, target, attrib, amount, true)") -and
    [regex]::Matches(
        $sourceAwareFourArgumentHeal,
        'pvp\.bfCreditForHealing\s*\(\s*source\s*,\s*delta\s*\)').Count -eq 1 -and
    -not [string]::IsNullOrEmpty($sourceLessHeal) -and
    $sourceLessHeal.Contains(
        "return addAttribModifier(player, attrib, amt, 0, 0, MOD_POOL);") -and
    -not $sourceLessHeal.Contains("applyDamageHealing") -and
    -not [string]::IsNullOrEmpty($avoidIncapRestore) -and
    [regex]::Matches(
        $avoidIncapRestore,
        '(?s)healing\.healDamage\s*\(\s*self\s*,\s*self\s*,\s*HEALTH\s*,\s*\(int\)\s*value\s*,\s*false\s*\)').Count -eq 1 -and
    -not [string]::IsNullOrEmpty($eventDamageShim) -and
    [regex]::Matches(
        $eventDamageShim,
        '(?s)healing\.healDamage\s*\(\s*self\s*,\s*myTarget\s*,\s*HEALTH\s*,\s*damage\s*,\s*false\s*\)').Count -eq 1) `
    -Name "p14.wounds.java-default-and-explicit-silent-observer-routing"
Assert-Contract -Condition (
    $utils.Contains("litmus = healWound(target, attrib, amt) != ATTRIB_ERROR;") -and
    $utils.Contains("else if (am.getDecay() == MOD_WOUND)") -and
    $utils.Contains("litmus = addWound(target, attrib, amt) != ATTRIB_ERROR;")) `
    -Name "p14.wounds.legacy-medicine-shares-native-seam"

Assert-Contract -Condition (
    $scriptWounds.Contains("!damageApplied") -and
    $scriptWounds.Contains(
        "(targetPoolMask & 0x7) == 0") -and
    $scriptWounds.Contains(
        "pool = combat.PRECU_TARGET_POOL_HEALTH") -and
    $scriptWounds.Contains(
        "pool <= combat.PRECU_TARGET_POOL_MIND") -and
    $scriptWounds.Contains("isDead(defender)") -and
    $scriptWounds.Contains("isIncapacitated(defender)")) `
    -Name "p14.wounds.runtime.post-damage-survivor-gate"
Assert-Contract -Condition (
    $scriptWounds.Contains(
        'dataTableSearchColumnForString(') -and
    $scriptWounds.Contains('"templateName", PRECU_WEAPON_PROFILES') -and
    $scriptWounds.Contains('"FALLBACK_NO_PROFILE"')) `
    -Name "p14.wounds.runtime.exact-profile-or-inert"
Assert-Contract -Condition (
    $scriptWounds.Contains("int woundRoll = rand(0, 100);") -and
    $scriptWounds.Contains("if (woundsRatio <= 0 || woundRoll >= woundsRatio)")) `
    -Name "p14.wounds.runtime.authentic-exclusive-roll"
Assert-Contract -Condition (
    $scriptWounds.Contains("int primaryAttribute = targetPool * 3;") -and
    $scriptWounds.Contains(
        "attribute < primaryAttribute + NUM_ATTRIBUTES_PER_GROUP") -and
    $scriptWounds.Contains("addWound(defender, attribute, 1)") -and
    $scriptWounds.Contains("addShockWound(defender, 1)")) `
    -Name "p14.wounds.runtime.three-linked-wounds-and-shock"
Assert-Contract -Condition (
    $damage.Contains("boolean damageApplied = false;") -and
    $damage.Contains("damageApplied =") -and
    $damage.Contains("doDamageToPool(") -and
    $damage.Contains("applyPrecuWounds(") -and
    $damage.IndexOf("applyPrecuWounds(", [StringComparison]::Ordinal) -gt
        $damage.IndexOf("doDamageToPool(", [StringComparison]::Ordinal)) `
    -Name "p14.wounds.runtime.after-real-damage"
Assert-Contract -Condition (
    -not $exitedCombat.Contains("setShockWound(self, 0)") -and
    -not $exitedCombat.Contains("healShockWound(self")) `
    -Name "p14.wounds.runtime.shock-persists-after-combat"
Assert-Contract -Condition (
    -not $basePlayer.Contains("setShockWound(self, 0)") -and
    $basePlayer.Contains(
        "Publish 14.1 battle fatigue is persistent character state.")) `
    -Name "p14.wounds.runtime.shock-persists-after-login"

Assert-Contract -Condition (
    $liveFixture.Contains('equalsIgnoreCase("armWounds")') -and
    $liveFixture.Contains("ORIGINAL_DEFENDER_WOUNDS") -and
    $liveFixture.Contains("ORIGINAL_DEFENDER_SHOCK") -and
    $liveFixture.Contains("new int[NUM_ATTRIBUTES]") -and
    $liveFixture.Contains("diagnosticWoundRoll=") -and
    $liveFixture.Contains("defenderShockWound=")) `
    -Name "p14.wounds.live.snapshot-arm-and-observation"
Assert-Contract -Condition (
    $fixtureRestore.Contains("current - originalWounds[attribute]") -and
    $fixtureRestore.Contains("healWound(defender, attribute, delta) != delta") -and
    $fixtureRestore.Contains("setShockWound(defender, originalShock)")) `
    -Name "p14.wounds.live.exact-reversible-cleanup"

if ($Expectation -ceq "Ready")
{
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        -Name "p14.wounds.status.ready"
    Assert-Contract -Condition (
        [string]$contract.buildEvidence.result -ceq "passed" -and
        @($contract.buildEvidence.targets).Count -ge 3 -and
        [string]$contract.buildEvidence.materializationFingerprint -match
            "^[a-f0-9]{64}$") `
        -Name "p14.wounds.isolated-build.evidence"
    Assert-Contract -Condition (
        [string]$contract.liveEvidence.result -ceq "passed" -and
        [string]$contract.liveEvidence.container -ceq "swg-precu" -and
        [int]$contract.liveEvidence.woundEvent.woundsApplied -eq 3 -and
        [int]$contract.liveEvidence.woundEvent.shockAdded -eq 3 -and
        [bool]$contract.liveEvidence.restartPersistence.retained -and
        [bool]$contract.liveEvidence.cleanup.restored) `
        -Name "p14.wounds.live-event-persistence-and-cleanup"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 wound contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Core3 wound build/static contract passed."
