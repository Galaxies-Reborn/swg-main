[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14StatMigration)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$text = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized stat-migration source is missing: $path"
    }
    $text[[string]$property.Name] = Get-Content -LiteralPath $path -Raw
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

function Read-TabTable
{
    param([Parameter(Mandatory = $true)][string]$Value)

    $lines = @($Value -split "`r?`n" | Where-Object { $_.Length -gt 0 })
    if ($lines.Count -lt 2) { throw "Compiled table has no header/type rows." }
    $headers = @($lines[0] -split "`t")
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines[2..($lines.Count - 1)])
    {
        $values = @($line -split "`t")
        $row = [ordered]@{}
        for ($index = 0; $index -lt $headers.Count; $index++)
        {
            $row[$headers[$index]] = if ($index -lt $values.Count) { $values[$index] } else { "" }
        }
        $rows.Add([pscustomobject]$row)
    }
    return $rows.ToArray()
}

Write-Host "Publish 14.1 stat-migration checks:"

$expectedOrder = @("health", "strength", "constitution", "action", "quickness", "stamina", "mind", "focus", "willpower")
$wireOrder = @($contract.wireOrder | ForEach-Object { [string]$_ })
Assert-Contract `
    -Condition ([string]$contract.status -ceq "ready" -and (($wireOrder -join ",") -ceq ($expectedOrder -join ","))) `
    -Name "p14.stat-migration.contract.ready-and-exact-wire-order"

$limits = @(Read-TabTable -Value $text.attributeLimits)
$racial = @(Read-TabTable -Value $text.racialMods)
$professions = @(Read-TabTable -Value $text.professionMods)

$expectedLimitHeader = @("male_template", "female_template")
foreach ($attribute in $expectedOrder) { $expectedLimitHeader += @("min_$attribute", "max_$attribute") }
$expectedLimitHeader += "total"
$actualLimitHeader = @(($text.attributeLimits -split "`r?`n")[0] -split "`t")
Assert-Contract `
    -Condition ($limits.Count -eq 10 -and (($actualLimitHeader -join ",") -ceq ($expectedLimitHeader -join ","))) `
    -Name "p14.stat-migration.tables.attribute-limits-shape"

$totalsReady = $true
foreach ($property in $contract.racialTotals.psobject.Properties)
{
    $row = @($limits | Where-Object { $_.male_template -ceq [string]$property.Name })
    if ($row.Count -ne 1 -or [int]$row[0].total -ne [int]$property.Value) { $totalsReady = $false }
}
Assert-Contract -Condition $totalsReady -Name "p14.stat-migration.tables.authentic-racial-totals"

$human = @($limits | Where-Object { $_.male_template -ceq "human_male" })[0]
$trandoshan = @($limits | Where-Object { $_.male_template -ceq "trandoshan_male" })[0]
$wookiee = @($limits | Where-Object { $_.male_template -ceq "wookiee_male" })[0]
Assert-Contract `
    -Condition ([int]$human.min_health -eq 400 -and [int]$human.max_willpower -eq 1100 -and [int]$trandoshan.min_constitution -eq 700 -and [int]$wookiee.max_health -eq 1350) `
    -Name "p14.stat-migration.tables.authentic-limit-canaries"

$racialHeader = @(($text.racialMods -split "`r?`n")[0] -split "`t")
$expectedRacialHeader = @("male_template", "female_template") + $expectedOrder
$racialHuman = @($racial | Where-Object { $_.male_template -ceq "human_male" })[0]
$racialWookiee = @($racial | Where-Object { $_.male_template -ceq "wookiee_male" })[0]
Assert-Contract `
    -Condition ($racial.Count -eq 10 -and (($racialHeader -join ",") -ceq ($expectedRacialHeader -join ",")) -and [int]$racialHuman.health -eq 100 -and [int]$racialWookiee.strength -eq 350 -and [int]$racialWookiee.focus -eq 150) `
    -Name "p14.stat-migration.tables.authentic-racial-modifiers"

$professionHeader = @(($text.professionMods -split "`r?`n")[0] -split "`t")
$expectedProfessionHeader = @("profession") + $expectedOrder
$artisan = @($professions | Where-Object { $_.profession -ceq "crafting_artisan" })[0]
$medic = @($professions | Where-Object { $_.profession -ceq "science_medic" })[0]
Assert-Contract `
    -Condition ($professions.Count -eq 7 -and (($professionHeader -join ",") -ceq ($expectedProfessionHeader -join ",")) -and [int]$artisan.action -eq 800 -and [int]$artisan.mind -eq 900 -and [int]$medic.mind -eq 1000 -and [int]$medic.focus -eq 500) `
    -Name "p14.stat-migration.tables.authentic-profession-allocations"

$commandsReady = $true
foreach ($command in @($contract.commands))
{
    if (-not $text.commandCpp.Contains("CommandTable::addCppFunction(`"$command`"")) { $commandsReady = $false }
}
Assert-Contract -Condition $commandsReady -Name "p14.stat-migration.commands.four-retained-entry-points"

$sessionReady = `
    $text.commandCpp.Contains("StatMigrationSessionMap s_statMigrationSessions") -and `
    $text.commandCpp.Contains("PlayerCreationManager::getRacialMinMaxes") -and `
    $text.commandCpp.Contains("PlayerCreationManager::getRacialTotal") -and `
    $text.commandCpp.Contains("creature.getUnmodifiedMaxAttribute(attribute)") -and `
    $text.commandCpp.Contains("session.pointsLeft = total - assigned")
Assert-Contract -Condition $sessionReady -Name "p14.stat-migration.session.server-owned-bounds-and-normalization"

$validationReady = `
    $text.commandCpp.Contains("targets.size()) != Attributes::NumberOfAttributes") -and `
    $text.commandCpp.Contains("targets[attribute] < limits[attribute].first") -and `
    $text.commandCpp.Contains("targets[attribute] > limits[attribute].second") -and `
    $text.commandCpp.Contains("return assigned == total") -and `
    $text.commandCpp.Contains("targets.reserve(Attributes::NumberOfAttributes)") -and `
    $text.commandCpp.Contains("pointsLeft as a tenth integer. It is advisory")
Assert-Contract -Condition $validationReady -Name "p14.stat-migration.submit.nine-target-bounds-and-authoritative-sum"

$responseReady = `
    $text.commandCpp.Contains("StatMigrationTargetsMessage const message(session->targets, session->pointsLeft)") -and `
    $text.commandCpp.Contains("creature->getClient()->send(message, true)")
Assert-Contract -Condition $responseReady -Name "p14.stat-migration.response.server-owned-target-vector"

$tutorialReady = `
    $text.commandCpp.Contains("if (creature->isInTutorial())") -and `
    -not $text.commandCpp.Contains('if (creature->getSceneId() == "newbie_hall")') -and `
    $text.commandCpp.Contains("applyStatMigration(*creature, targets)") -and `
    $text.commandCpp.Contains("s_statMigrationSessions.erase(actor)") -and `
    $text.commandCpp.Contains("World allocations remain pending for an entertainer")
Assert-Contract -Condition $tutorialReady -Name "p14.stat-migration.commit.fresh-character-tutorial-immediate-and-consumed"

$tutorialLifecycleReady = `
    $text.newbieTutorial.Contains("return shouldStartTutorial(character) || shouldStartSkippedTutorial(character);") -and `
    $text.fullTutorialPlayer.Contains('removeObjVar(self, "newbie");') -and `
    $text.skippedTutorialPlayer.Contains('if (!loc.area.equals("tutorial"))') -and `
    $text.skippedTutorialPlayer.Contains('removeObjVar(self, "newbie.startSkippedTutorial");')
Assert-Contract -Condition $tutorialLifecycleReady -Name "p14.stat-migration.admission.first-planet-retires-free-migration"

$nativeCommitReady = `
    $text.commandHeader.Contains("canCommitStatMigration") -and `
    $text.commandHeader.Contains("commitStatMigration") -and `
    $text.commandCpp.Contains("session->pointsLeft == 0") -and `
    $text.commandCpp.Contains("validateStatMigrationTargets(*creature, session->targets)") -and `
    $text.commandCpp.Contains("applyStatMigration(*creature, session->second.targets)") -and `
    $text.commandCpp.Contains("s_statMigrationSessions.erase(session)")
Assert-Contract -Condition $nativeCommitReady -Name "p14.stat-migration.commit.revalidated-and-consumed-once"

$controllerAuthenticationReady = `
    $text.playerController.Contains("SharedImageDesignerManager::Session authenticatedSession") -and `
    $text.playerController.Contains("authenticatedSession.designerId == designerId") -and `
    $text.playerController.Contains("authenticatedSession.recipientId == recipientId") -and `
    $text.playerController.Contains("authenticatedSession.terminalId == inMsg->getTerminalId()") -and `
    $text.playerController.Contains("designerId != recipientId") -and `
    $text.playerController.Contains("session.startingTime = authenticatedSession.startingTime") -and `
    $text.playerController.Contains("cancelSession(session.designerId, session.recipientId)")
Assert-Contract -Condition $controllerAuthenticationReady -Name "p14.stat-migration.image-designer.controller-session-identity"

$venueTransactionReady = `
    $text.imageDesignerManager.Contains("session.designType == ImageDesignChangeMessage::DT_STAT_MIGRATION") -and `
    $text.imageDesignerManager.Contains("designer != recipient") -and `
    $text.imageDesignerManager.Contains('designer->hasCommand("imagedesign")') -and `
    $text.imageDesignerManager.Contains("!recipient->isInTutorial()") -and `
    $text.imageDesignerManager.Contains('statMigrationVenue->getObjVars().hasItem("salon")') -and `
    $text.imageDesignerManager.Contains('statMigrationVenue->getObjVars().hasItem("modules.entertainer")') -and `
    $text.imageDesignerManager.Contains('statMigrationVenue->getTriggerVolume("campsite")') -and `
    $text.imageDesignerManager.Contains("entertainmentCampVolume->hasObject(*designer)") -and `
    $text.imageDesignerManager.Contains("entertainmentCampVolume->hasObject(*recipient)") -and `
    $text.imageDesignerManager.Contains("designerTopmost->getNetworkId() == session.terminalId") -and `
    $text.imageDesignerManager.Contains("recipientTopmost->getNetworkId() == session.terminalId") -and `
    $text.playerImageDesigner.Contains("import script.library.camping;") -and `
    $text.playerImageDesigner.Contains("camping.getCurrentAdvancedCamp(self)") -and `
    $text.playerImageDesigner.Contains("camping.isInEntertainmentCamp(design_target, entertainmentCamp)") -and `
    $text.imageDesignerScript.Contains("import script.library.camping;") -and `
    $text.imageDesignerScript.Contains("boolean validEntertainmentCamp") -and `
    $text.imageDesignerScript.Contains("camping.isInEntertainmentCamp(target, entertainmentCamp)") -and `
    $text.imageDesignerScript.Contains("designType == 2 && !validSalon && !validEntertainmentCamp") -and `
    $text.imageDesignerManager.Contains("CommandCppFuncs::canCommitStatMigration(recipient->getNetworkId())") -and `
    $text.imageDesignerManager.Contains("CommandCppFuncs::commitStatMigration(recipient->getNetworkId())")
Assert-Contract -Condition $venueTransactionReady -Name "p14.stat-migration.image-designer.normal-world-entertainer-salon-or-camp-transaction"

$nativeCallbackReady = `
    $text.imageDesignerNative.Contains("SharedImageDesignerManager::getSession(session.designerId, authenticatedSession)") -and `
    $text.imageDesignerNative.Contains("authenticatedSession.startingTime == session.startingTime") -and `
    $text.imageDesignerNative.Contains("authenticatedSession.designType == session.designType") -and `
    $text.imageDesignerNative.Contains("return JNI_FALSE")
Assert-Contract -Condition $nativeCallbackReady -Name "p14.stat-migration.image-designer.java-native-authentication"

$retailTimingAndRewardReady = `
    $text.sharedImageDesigner.Contains("ConfigSharedGame::getImageDesignerStatMigrationSessionTimeSeconds()") -and `
    $text.sharedImageDesigner.Contains("statMigrationRequested") -and `
    $text.sharedImageDesigner.Contains("ImageDesignChangeMessage::DT_STAT_MIGRATION") -and `
    $text.imageDesignerScript.Contains("IMAGE_DESIGN_EXPERIENCE_STAT_MIG = 2000") -and `
    $text.imageDesignerScript.Contains('if (designType == 2 || newHairSet || !holoEmote.equals("") || morphChangesKeys.length != 0 || indexChangesKeys.length != 0)') -and `
    $text.imageDesignerScript.Contains('xp.grant(self, xp.IMAGEDESIGNER, experience)') -and `
    -not $text.imageDesignerScript.Contains('xp.grantSocialStyleXp(self, xp.IMAGEDESIGNER, experience)') -and `
    $text.imageDesignerScript.Contains('utils.hasObjVar(structure, "salon")')
Assert-Contract -Condition $retailTimingAndRewardReady -Name "p14.stat-migration.image-designer.retail-timer-salon-and-reward"

$retailWireTimeReady = `
    $text.imageDesignerWireMessage.Contains("int const startingTimeWire = static_cast<int>(msg->getStartingTime())") -and `
    $text.imageDesignerWireMessage.Contains("Archive::put(target, startingTimeWire)") -and `
    $text.imageDesignerWireMessage.Contains("int tempTimeWire = 0") -and `
    $text.imageDesignerWireMessage.Contains("msg->setStartingTime(static_cast<time_t>(tempTimeWire))") -and `
    -not $text.imageDesignerWireMessage.Contains("Archive::put(target, msg->getStartingTime())")
Assert-Contract -Condition $retailWireTimeReady -Name "p14.stat-migration.image-designer.retail-32-bit-start-time-wire"

$persistentSessionReady = `
    $text.commandCpp.Contains('cms_statMigrationObjVarRoot = "precu.statMigration"') -and `
    $text.commandCpp.Contains("setObjVarItem(cms_statMigrationObjVarTargets, session.targets)") -and `
    $text.commandCpp.Contains("setObjVarItem(cms_statMigrationObjVarState, cms_statMigrationStatePending)") -and `
    $text.commandCpp.Contains("loadPersistentStatMigration(creature, restored)") -and `
    $text.commandCpp.Contains("validateStatMigrationTargets(creature, targets)") -and `
    $text.commandCpp.Contains("beginPersistentStatMigrationCommit(*creature)") -and `
    $text.commandCpp.Contains("clearPersistentStatMigration(*creature)")
Assert-Contract -Condition $persistentSessionReady -Name "p14.stat-migration.session.restart-persistent-fail-closed"

$ctsGetter = Get-BracedBlock -Text $text.commandCpp -Signature "bool CommandCppFuncs::getPrecuCtsStatAllocation("
$ctsApplier = Get-BracedBlock -Text $text.commandCpp -Signature "bool CommandCppFuncs::applyPrecuCtsStatAllocation("
$sharedApply = Get-BracedBlock -Text $text.commandCpp -Signature "void applyStatMigration(CreatureObject & creature, std::vector<int> const & targets)"
$jniGetter = Get-BracedBlock -Text $text.scriptMethodsAttributes -Signature "jintArray JNICALL ScriptMethodsAttributesNamespace::getPrecuCtsStatAllocation("
$jniApplier = Get-BracedBlock -Text $text.scriptMethodsAttributes -Signature "jboolean JNICALL ScriptMethodsAttributesNamespace::applyPrecuCtsStatAllocation("
$ctsUpload = Get-BracedBlock -Text $text.basePlayer -Signature "public int OnUploadCharacter("
$ctsDownload = Get-BracedBlock -Text $text.basePlayer -Signature "public int OnDownloadCharacter("
$ctsObjVarList = [regex]::Match($ctsUpload, '(?s)final\s+String\[\]\s+strObjVarLists\s*=\s*\{(?<body>.*?)\};')

$ctsContractReady = `
    [int]$contract.ctsAllocation.version -eq 1 -and `
    [string]$contract.ctsAllocation.versionKey -ceq "precuCtsStatAllocationVersion" -and `
    [string]$contract.ctsAllocation.allocationKey -ceq "precuCtsStatAllocation" -and `
    [int]$contract.ctsAllocation.attributeCount -eq 9 -and `
    [string]$contract.ctsAllocation.pendingMigrationPolicy -ceq "reject-transfer"
Assert-Contract -Condition $ctsContractReady -Name "p14.stat-migration.cts.versioned-nine-attribute-contract"

$ctsNativeReady = `
    $text.commandHeader.Contains("getPrecuCtsStatAllocation(NetworkId const & actor, std::vector<int> & allocation)") -and `
    $text.commandHeader.Contains("applyPrecuCtsStatAllocation(NetworkId const & actor, std::vector<int> const & allocation)") -and `
    $ctsGetter.Contains("Attributes::NumberOfAttributes") -and `
    $ctsGetter.Contains("getUnmodifiedMaxAttribute(attribute)") -and `
    $ctsGetter.Contains("validateStatMigrationTargets(*creature, currentAllocation)") -and `
    $ctsGetter.Contains("cms_statMigrationObjVarRoot") -and `
    $ctsGetter.Contains("isAuthoritative()") -and `
    $ctsGetter.Contains("isPlayerControlled()") -and `
    $ctsApplier.Contains("validateStatMigrationTargets(*creature, allocation)") -and `
    $ctsApplier.Contains("cms_statMigrationObjVarRoot") -and `
    $ctsApplier.Contains("isAuthoritative()") -and `
    $ctsApplier.Contains("isPlayerControlled()") -and `
    ([regex]::Matches($ctsApplier, [regex]::Escape("applyStatMigration(*creature, allocation)")).Count -eq 1) -and `
    $sharedApply.Contains("int const delta = targets[attribute] - oldMaximum;") -and `
    $sharedApply.Contains("std::max(0, oldCurrent + delta)")
Assert-Contract -Condition $ctsNativeReady -Name "p14.stat-migration.cts.shared-validation-and-atomic-application"

$ctsJniReady = `
    $text.scriptMethodsAttributes.Contains('JF("_getPrecuCtsStatAllocation", "(J)[I", getPrecuCtsStatAllocation)') -and `
    $text.scriptMethodsAttributes.Contains('JF("_applyPrecuCtsStatAllocation", "(J[I)Z", applyPrecuCtsStatAllocation)') -and `
    $jniGetter.Contains("allocation.size()) != Attributes::NumberOfAttributes") -and `
    $jniGetter.Contains("createNewIntArray(Attributes::NumberOfAttributes)") -and `
    $jniGetter.Contains("CommandCppFuncs::getPrecuCtsStatAllocation") -and `
    $jniApplier.Contains("GetArrayLength(allocation) != Attributes::NumberOfAttributes") -and `
    $jniApplier.Contains("GetIntArrayRegion(allocation, 0, Attributes::NumberOfAttributes, values)") -and `
    ([regex]::Matches($jniApplier, [regex]::Escape("CommandCppFuncs::applyPrecuCtsStatAllocation")).Count -eq 1) -and `
    $text.baseClass.Contains("private static native int[] _getPrecuCtsStatAllocation(long target);") -and `
    $text.baseClass.Contains("private static native boolean _applyPrecuCtsStatAllocation(long target, int[] allocation);") -and `
    $text.baseClass.Contains("public static int[] getPrecuCtsStatAllocation(obj_id target)") -and `
    $text.baseClass.Contains("public static boolean applyPrecuCtsStatAllocation(obj_id target, int[] allocation)")
Assert-Contract -Condition $ctsJniReady -Name "p14.stat-migration.cts.exact-native-int-array-bridge"

$uploadPendingAt = $ctsUpload.IndexOf("hasObjVar(self, PRECU_STAT_MIGRATION_OBJVAR_ROOT)", [StringComparison]::Ordinal)
$uploadGetterAt = $ctsUpload.IndexOf("getPrecuCtsStatAllocation(self)", [StringComparison]::Ordinal)
$uploadVersionAt = $ctsUpload.IndexOf("characterData.put(PRECU_CTS_STAT_ALLOCATION_VERSION_KEY", [StringComparison]::Ordinal)
$uploadAllocationAt = $ctsUpload.IndexOf("characterData.put(PRECU_CTS_STAT_ALLOCATION_KEY", [StringComparison]::Ordinal)
$uploadSkillsAt = $ctsUpload.IndexOf('characterData.put("skills"', [StringComparison]::Ordinal)
$downloadUnpackAt = $ctsDownload.IndexOf("dictionary.unpack(packedData)", [StringComparison]::Ordinal)
$downloadTypeAt = $ctsDownload.IndexOf("characterData.isInt(PRECU_CTS_STAT_ALLOCATION_VERSION_KEY)", [StringComparison]::Ordinal)
$downloadArrayAt = $ctsDownload.IndexOf("characterData.getIntArray(PRECU_CTS_STAT_ALLOCATION_KEY)", [StringComparison]::Ordinal)
$downloadApplyAt = $ctsDownload.IndexOf("applyPrecuCtsStatAllocation(self, precuStatAllocation)", [StringComparison]::Ordinal)
$downloadLocalAt = $ctsDownload.IndexOf('utils.setLocalVar(self, "ctsBeingUnpacked", true)', [StringComparison]::Ordinal)
$downloadTransferredAt = $ctsDownload.IndexOf('setObjVar(self, "hasTransferred", 1)', [StringComparison]::Ordinal)
$downloadSkillsAt = $ctsDownload.IndexOf('characterData.getStringArray("skills")', [StringComparison]::Ordinal)
$ctsScriptReady = `
    $text.basePlayer.Contains('PRECU_CTS_STAT_ALLOCATION_VERSION_KEY = "precuCtsStatAllocationVersion"') -and `
    $text.basePlayer.Contains('PRECU_CTS_STAT_ALLOCATION_KEY = "precuCtsStatAllocation"') -and `
    $text.basePlayer.Contains("PRECU_CTS_STAT_ALLOCATION_VERSION = 1") -and `
    $uploadPendingAt -ge 0 -and $uploadPendingAt -lt $uploadGetterAt -and `
    $uploadGetterAt -lt $uploadVersionAt -and $uploadVersionAt -lt $uploadAllocationAt -and $uploadAllocationAt -lt $uploadSkillsAt -and `
    $ctsObjVarList.Success -and -not $ctsObjVarList.Groups["body"].Value.Contains("precu.statMigration") -and `
    $downloadUnpackAt -ge 0 -and $downloadUnpackAt -lt $downloadTypeAt -and `
    $downloadTypeAt -lt $downloadArrayAt -and $downloadArrayAt -lt $downloadApplyAt -and `
    $downloadApplyAt -lt $downloadLocalAt -and $downloadLocalAt -lt $downloadTransferredAt -and $downloadTransferredAt -lt $downloadSkillsAt -and `
    $ctsDownload.Contains("precuStatAllocation.length != NUM_ATTRIBUTES")
Assert-Contract -Condition $ctsScriptReady -Name "p14.stat-migration.cts.pending-session-rejected-and-allocation-precedes-replay"

$persistenceFixtureReady = `
    $text.persistenceFixture.Contains("private static final long RECIPIENT_OID = 39008597L") -and `
    $text.persistenceFixture.Contains("private static final int RECIPIENT_STATION_ID = 1001") -and `
    $text.persistenceFixture.Contains('private static final String ROOT = "precu.statMigration"') -and `
    $text.persistenceFixture.Contains("getIntArrayObjVar(recipient, TARGETS)") -and `
    $text.persistenceFixture.Contains('return "oid=" + recipient + " present=" + present') -and `
    -not $text.persistenceFixture.Contains("setObjVar") -and `
    -not $text.persistenceFixture.Contains("removeObjVar")
Assert-Contract -Condition $persistenceFixtureReady -Name "p14.stat-migration.fixture.read-only-identity-bound-persistence-status"

Assert-Contract `
    -Condition ([string]$contract.knownLimitations.imageDesignerCommit -like "Restored*" -and [string]$contract.knownLimitations.sessionPersistence -like "Validated*") `
    -Name "p14.stat-migration.boundary.image-designer-and-restart-persistence-restored"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 stat-migration contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 stat-migration contract passed."
