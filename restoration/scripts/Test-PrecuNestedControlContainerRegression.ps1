[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
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

function Get-FunctionSlice(
    [string]$Text,
    [string]$Start,
    [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0)
    {
        return ""
    }
    $nextIndex = $Text.IndexOf(
        $Next,
        $startIndex + $Start.Length,
        [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0)
    {
        return $Text.Substring($startIndex)
    }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

function Read-ExactBytes(
    [System.IO.BinaryReader]$Reader,
    [int]$Count)
{
    [byte[]]$bytes = $Reader.ReadBytes($Count)
    if ($bytes.Length -ne $Count)
    {
        throw "Truncated STF: expected $Count bytes, read $($bytes.Length)."
    }
    return $bytes
}

function Read-PrecuStringTable([string]$Path)
{
    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
    $stream = [System.IO.MemoryStream]::new($bytes, $false)
    $reader = [System.IO.BinaryReader]::new(
        $stream,
        [System.Text.Encoding]::UTF8,
        $true)
    try
    {
        $magic = $reader.ReadUInt32()
        $version = $reader.ReadByte()
        $nextUniqueId = $reader.ReadUInt32()
        $entryCount = $reader.ReadUInt32()
        $stringsById = [System.Collections.Generic.Dictionary[uint32,string]]::new()
        $sourceCrcById = [System.Collections.Generic.Dictionary[uint32,uint32]]::new()

        for ([uint32]$i = 0; $i -lt $entryCount; ++$i)
        {
            $id = $reader.ReadUInt32()
            $sourceCrc = $reader.ReadUInt32()
            $characterCount = $reader.ReadUInt32()
            [byte[]]$valueBytes = Read-ExactBytes $reader ([int]$characterCount * 2)
            $stringsById.Add(
                $id,
                [System.Text.Encoding]::Unicode.GetString($valueBytes))
            $sourceCrcById.Add($id, $sourceCrc)
        }

        $valuesByName = [System.Collections.Generic.Dictionary[string,string]]::new(
            [System.StringComparer]::Ordinal)
        for ([uint32]$i = 0; $i -lt $entryCount; ++$i)
        {
            $id = $reader.ReadUInt32()
            $nameLength = $reader.ReadUInt32()
            [byte[]]$nameBytes = Read-ExactBytes $reader ([int]$nameLength)
            $name = [System.Text.Encoding]::ASCII.GetString($nameBytes)
            if (-not $stringsById.ContainsKey($id))
            {
                throw "STF name '$name' references missing id $id."
            }
            $valuesByName.Add($name, $stringsById[$id])
        }

        if ($stream.Position -ne $stream.Length)
        {
            throw "STF has $($stream.Length - $stream.Position) trailing bytes."
        }

        return [pscustomobject]@{
            Magic = $magic
            Version = $version
            NextUniqueId = $nextUniqueId
            EntryCount = $entryCount
            ValuesByName = $valuesByName
            SourceCrcById = $sourceCrcById
        }
    }
    finally
    {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$scriptRoot = "dsrc/sku.0/sys.server/compiled/game/script"
$petLibraryPath = Join-Path $source "$scriptRoot/library/pet_lib.java"
$spaceCombatPath = Join-Path $source "$scriptRoot/library/space_combat.java"
$accountContainersPath = Join-Path $source "$scriptRoot/library/account_containers.java"
$armorLibraryPath = Join-Path $source "$scriptRoot/library/armor.java"
$petControlPath = Join-Path $source "$scriptRoot/ai/pet_control_device.java"
$vehicleControlPath = Join-Path $source "$scriptRoot/systems/vehicle_system/vehicle_control_device.java"
$basePlayerPath = Join-Path $source "$scriptRoot/player/base/base_player.java"
$noDestroyPath = Join-Path $source "$scriptRoot/item/special/nodestroy.java"
$workerDroidPath = Join-Path $source "$scriptRoot/item/droid/worker_droid.java"
$workerDroidTargetPath = Join-Path $source "$scriptRoot/structure/worker_droid_target.java"
$surveyDroidDevicePath = Join-Path $source `
    "$scriptRoot/item/survey_droid/survey_droid_device.java"
$featureFixturePath = Join-Path $source `
    "$scriptRoot/test/precu_container_droid_feature_fixture.java"
$consumablePath = Join-Path $source "$scriptRoot/library/consumable.java"
$generatorPath = Join-Path $source "restoration/scripts/New-PrecuContainerDroidStringTable.ps1"
$stringTablePath = Join-Path $source "serverdata/string/en/precu_container_droid.stf"
$sharedObjectRoot = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/object"
$resourceContainerTemplatePath = Join-Path $sharedObjectRoot `
    "intangible/container/shared_resource_container.tpf"
$craftContainerTemplatePath = Join-Path $sharedObjectRoot `
    "intangible/container/shared_craft_component_container.tpf"
$vehicleContainerTemplatePath = Join-Path $sharedObjectRoot `
    "intangible/container/shared_vehicle_container.tpf"
$droidContainerTemplatePath = Join-Path $sharedObjectRoot `
    "intangible/container/shared_droid_container.tpf"
$workerDroidTemplatePath = Join-Path $sharedObjectRoot `
    "tangible/mission/shared_mission_worker_droid.tpf"
$surveyDroidTemplatePath = Join-Path $sharedObjectRoot `
    "tangible/mission/shared_mission_survey_droid.tpf"
$shipContainerTemplatePaths = @(1000, 2000, 3000, 4000, 5000 | ForEach-Object {
    Join-Path $sharedObjectRoot `
        "intangible/container/shared_ship_part_container_$_.tpf"
})

foreach ($path in @(
    $petLibraryPath,
    $spaceCombatPath,
    $accountContainersPath,
    $armorLibraryPath,
    $petControlPath,
    $vehicleControlPath,
    $basePlayerPath,
    $noDestroyPath,
    $workerDroidPath,
    $workerDroidTargetPath,
    $surveyDroidDevicePath,
    $featureFixturePath,
    $consumablePath,
    $generatorPath,
    $stringTablePath,
    $resourceContainerTemplatePath,
    $craftContainerTemplatePath,
    $vehicleContainerTemplatePath,
    $droidContainerTemplatePath,
    $workerDroidTemplatePath,
    $surveyDroidTemplatePath) + $shipContainerTemplatePaths)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "precu.nested-control.source.$([System.IO.Path]::GetFileName($path))"
}

$petLibrary = Get-Content -LiteralPath $petLibraryPath -Raw
$spaceCombat = Get-Content -LiteralPath $spaceCombatPath -Raw
$accountContainers = Get-Content -LiteralPath $accountContainersPath -Raw
$armorLibrary = Get-Content -LiteralPath $armorLibraryPath -Raw
$petControl = Get-Content -LiteralPath $petControlPath -Raw
$vehicleControl = Get-Content -LiteralPath $vehicleControlPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$noDestroy = Get-Content -LiteralPath $noDestroyPath -Raw
$workerDroid = Get-Content -LiteralPath $workerDroidPath -Raw
$workerDroidTarget = Get-Content -LiteralPath $workerDroidTargetPath -Raw
$surveyDroidDevice = Get-Content -LiteralPath $surveyDroidDevicePath -Raw
$featureFixture = Get-Content -LiteralPath $featureFixturePath -Raw
$consumable = Get-Content -LiteralPath $consumablePath -Raw

$petCreate = Get-FunctionSlice $petLibrary `
    "public static void createPetFromData(obj_id petControlDevice, obj_id objContainer)" `
    "public static void customizationFadeToWhite("
$flightCreate = Get-FunctionSlice $spaceCombat `
    "public static void createFlightDroidFromData(" `
    "public static boolean removeFlightDroidFromShip("
$petTransfer = Get-FunctionSlice $petControl `
    "public int OnAboutToBeTransferred(" `
    "public int getLevelFromPetControlDevice("
$vehicleTransfer = Get-FunctionSlice $vehicleControl `
    "public int OnAboutToBeTransferred(" `
    "public int getLevelFromPetControlDevice("
$componentAdmission = Get-FunctionSlice $accountContainers `
    "public static boolean mayHoldItem(" `
    "public static String getContainerKind("
$componentMigration = Get-FunctionSlice $accountContainers `
    "private static void migrateLegacyCraftComponents(" `
    "private static obj_id findContainer("
$armorComponentTypes = Get-FunctionSlice $armorLibrary `
    "public static boolean isArmorComponent(int armorGOT)" `
    "public static boolean isArmorLayer("
$pcdDiscovery = Get-FunctionSlice $petLibrary `
    "public static obj_id[] getPcdsForType(" `
    "public static obj_id validateDroidCommand("
$downloadCharacter = Get-FunctionSlice $basePlayer `
    "public int OnDownloadCharacter(obj_id self, byte[] packedData)" `
    "public int OnSkillModDone("
$packItem = Get-FunctionSlice $basePlayer `
    "public dictionary packItem(obj_id item, int objectType, boolean allowOverride," `
    "public int OnUploadCharacter("
$unpackItem = Get-FunctionSlice $basePlayer `
    "public obj_id unpackItem(obj_id container, dictionary itemDictionary)" `
    "public boolean itemIsAllowedToTransfer("
$workerDispatch = Get-FunctionSlice $workerDroid `
    "public int handleWorkerDroidActionSelection(obj_id self, dictionary params)" `
    "public int workerDroidLocateTimeout("
$workerBegin = Get-FunctionSlice $workerDroid `
    "public int beginWorkerDroidSearch(obj_id self, obj_id player)" `
    "public int handleWorkerDroidLocateResponse("
$workerCleanup = Get-FunctionSlice $workerDroid `
    "public void cleanupFlow(obj_id self, obj_id player)" `
    "public void clearStaleHandoff("
$workerGrant = Get-FunctionSlice $workerDroidTarget `
    "public boolean grantMatches(obj_id self, obj_id player, obj_id workerDroid, int token)" `
    "public boolean isEligibleTarget("
$decrementCharges = Get-FunctionSlice $consumable `
    "public static boolean decrementCharges(obj_id item, obj_id player)" `
    "public static boolean decrementSpecificObjectRecursive("
$surveyDispatch = Get-FunctionSlice $surveyDroidDevice `
    "public int handlePlanetSelection(obj_id self, dictionary params)" `
    "public boolean canLaunch("

Assert-Contract ($petCreate.Contains(
    "obj_id master = utils.getContainingPlayer(petControlDevice);") -and
    $petCreate.Contains("if (!isPlayer(master))") -and
    -not $petCreate.Contains("obj_id master = getContainedBy(datapad);")) `
    "precu.nested-control.creature-call-recursive-owner"

Assert-Contract ($flightCreate.Contains(
    "obj_id master = utils.getContainingPlayer(petControlDevice);") -and
    $flightCreate.Contains("if (!isPlayer(master))") -and
    -not $flightCreate.Contains("obj_id master = getContainedBy(datapad);")) `
    "precu.nested-control.flight-droid-call-recursive-owner"

$petGuardIndex = $petTransfer.IndexOf(
    "boolean alreadyStoredInDatapad = isIdValid(currentDatapad) && utils.isNestedWithin(self, currentDatapad);",
    [System.StringComparison]::Ordinal)
$petCapIndex = $petTransfer.IndexOf(
    "pet_lib.hasMaxStoredPetsOfType(newMaster, petType)",
    [System.StringComparison]::Ordinal)
Assert-Contract ($petGuardIndex -ge 0 -and $petCapIndex -gt $petGuardIndex -and
    $petTransfer.Contains("newMaster == currentMaster &&") -and
    $petTransfer.Contains("alreadyStoredInDatapad &&") -and
    $petTransfer.Contains(
        "(destinationIsDroidContainer || currentIsDroidContainer)")) `
    "precu.nested-control.droid-cap-bypass-closed"

$vehicleGuardIndex = $vehicleTransfer.IndexOf(
    "boolean alreadyStoredInDatapad = isIdValid(currentDatapad) && utils.isNestedWithin(self, currentDatapad);",
    [System.StringComparison]::Ordinal)
$vehicleCapIndex = $vehicleTransfer.IndexOf(
    "vehicle.hasMaxStoredVehicles(newMaster)",
    [System.StringComparison]::Ordinal)
Assert-Contract ($vehicleGuardIndex -ge 0 -and
    $vehicleCapIndex -gt $vehicleGuardIndex -and
    $vehicleTransfer.Contains("newMaster == currentMaster &&") -and
    $vehicleTransfer.Contains("alreadyStoredInDatapad &&") -and
    $vehicleTransfer.Contains(
        "(destinationIsVehicleContainer || currentIsVehicleContainer)")) `
    "precu.nested-control.vehicle-cap-bypass-closed"

Assert-Contract ($componentAdmission.Contains(
    "isGameObjectTypeOf(got, GOT_component) || armor.isArmorComponent(got)") -and
    $armorComponentTypes.Contains("GOT_armor_layer") -and
    $armorComponentTypes.Contains("GOT_armor_segment") -and
    $armorComponentTypes.Contains("GOT_armor_core")) `
    "precu.nested-control.armor-component-admission"

Assert-Contract ($componentMigration.Contains(
    "isGameObjectTypeOf(got, GOT_component) || armor.isArmorComponent(got)")) `
    "precu.nested-control.armor-component-migration"

Assert-Contract ($componentAdmission.Contains(
    "TEMPLATE_WALKER_AT_RT_REG_PCD.equals(getTemplateName(item))") -and
    $accountContainers.Contains(
        '"object/intangible/vehicle/walker_at_rt_reg_pcd.iff";')) `
    "precu.nested-control.legacy-vehicle-pcd-admission"

Assert-Contract ($pcdDiscovery.Contains(
    "obj_id[] dPadContents = utils.getContents(pDataPad, true);") -and
    -not $pcdDiscovery.Contains(
        "obj_id[] dPadContents = utils.getContents(pDataPad, false);")) `
    "precu.nested-control.droid-pcd-discovery-recursive"

$ctsManagedIndex = $downloadCharacter.IndexOf(
    "boolean managedAccountContainer = account_containers.isManagedContainer(datapadObject);",
    [System.StringComparison]::Ordinal)
$ctsDetachIndex = $downloadCharacter.IndexOf(
    "detachScript(datapadObject, account_containers.SCRIPT_NO_DESTROY);",
    [System.StringComparison]::Ordinal)
$ctsDestroyIndex = $downloadCharacter.IndexOf(
    "if (!destroyObject(datapadObject))",
    [System.StringComparison]::Ordinal)
$ctsRestoreIndex = $downloadCharacter.IndexOf(
    "attachScript(datapadObject, account_containers.SCRIPT_NO_DESTROY);",
    $ctsDestroyIndex,
    [System.StringComparison]::Ordinal)
$ctsFailureIndex = $downloadCharacter.IndexOf(
    'TRANSFER FAILED");',
    $ctsDestroyIndex,
    [System.StringComparison]::Ordinal)
$ctsOverrideIndex = $downloadCharacter.IndexOf(
    "return SCRIPT_OVERRIDE;",
    $ctsDestroyIndex,
    [System.StringComparison]::Ordinal)
$ctsUnpackIndex = $downloadCharacter.IndexOf(
    "OnDownloadCharacter : unpacking datapad items",
    [System.StringComparison]::Ordinal)
$ctsReprovisionIndex = $downloadCharacter.IndexOf(
    "account_containers.ensureContainers(self);",
    $ctsUnpackIndex,
    [System.StringComparison]::Ordinal)
Assert-Contract ($ctsManagedIndex -ge 0 -and
    $ctsDetachIndex -gt $ctsManagedIndex -and
    $ctsDestroyIndex -gt $ctsDetachIndex -and
    $ctsRestoreIndex -gt $ctsDestroyIndex -and
    $ctsFailureIndex -gt $ctsDestroyIndex -and
    $ctsOverrideIndex -gt $ctsDestroyIndex -and
    $ctsRestoreIndex -lt $ctsOverrideIndex -and
    $ctsOverrideIndex -lt $ctsUnpackIndex -and
    $ctsReprovisionIndex -gt $ctsUnpackIndex -and
    $downloadCharacter.Contains(
        "managedAccountContainer && exists(datapadObject) && !hasScript(datapadObject, account_containers.SCRIPT_NO_DESTROY)")) `
    "precu.nested-control.cts-replace-without-duplicates"

Assert-Contract ($packItem.Contains("(containerType == 2 ||") -and
    $packItem.Contains(
        "(containerType == 3 && account_containers.isManagedContainer(item)))") -and
    $packItem.Contains("contents = getContents(item);") -and
    -not $packItem.Contains("containerType == 3 && !isGameObjectTypeOf")) `
    "precu.nested-control.cts-managed-intangible-contents-packed"

$ctsPackedObjvarsIndex = $unpackItem.IndexOf(
    "setPackedObjvars(newItem, packedObjvars);",
    [System.StringComparison]::Ordinal)
$ctsEarlyManagedIndex = $unpackItem.IndexOf(
    "container == destinationDatapad && account_containers.isManagedContainer(newItem)",
    $ctsPackedObjvarsIndex,
    [System.StringComparison]::Ordinal)
$ctsEarlyStationIndex = $unpackItem.IndexOf(
    "int destinationStationId = getPlayerStationId(self);",
    $ctsEarlyManagedIndex,
    [System.StringComparison]::Ordinal)
$ctsEarlyRemoveIndex = $unpackItem.IndexOf(
    "removeObjVar(newItem, account_containers.VAR_STATION_ID);",
    $ctsEarlyStationIndex,
    [System.StringComparison]::Ordinal)
$ctsEarlyBindIndex = $unpackItem.IndexOf(
    "account_containers.bindContainer(newItem, self);",
    $ctsEarlyRemoveIndex,
    [System.StringComparison]::Ordinal)
$ctsEarlyExactIndex = $unpackItem.IndexOf(
    "getIntObjVar(newItem, account_containers.VAR_STATION_ID) != destinationStationId",
    $ctsEarlyBindIndex,
    [System.StringComparison]::Ordinal)
$ctsContentsIndex = $unpackItem.IndexOf(
    'if (itemDictionary.containsKey("contents"))',
    $ctsEarlyExactIndex,
    [System.StringComparison]::Ordinal)
Assert-Contract ($ctsPackedObjvarsIndex -ge 0 -and
    $ctsEarlyManagedIndex -gt $ctsPackedObjvarsIndex -and
    $ctsEarlyStationIndex -gt $ctsEarlyManagedIndex -and
    $unpackItem.Contains("if (destinationStationId <= 0)") -and
    $ctsEarlyRemoveIndex -gt $ctsEarlyStationIndex -and
    $ctsEarlyBindIndex -gt $ctsEarlyRemoveIndex -and
    $ctsEarlyExactIndex -gt $ctsEarlyBindIndex -and
    $unpackItem.Contains("!account_containers.isBoundToPlayer(newItem, self)") -and
    $ctsContentsIndex -gt $ctsEarlyExactIndex) `
    "precu.nested-control.cts-rebound-before-content-unpack"

$ctsUnpackedContainerIndex = $downloadCharacter.IndexOf(
    "if (account_containers.isManagedContainer(unpackedItem))",
    [System.StringComparison]::Ordinal)
$ctsDestinationStationIndex = $downloadCharacter.IndexOf(
    "int destinationStationId = getPlayerStationId(self);",
    $ctsUnpackedContainerIndex,
    [System.StringComparison]::Ordinal)
$ctsPositiveStationIndex = $downloadCharacter.IndexOf(
    "if (destinationStationId <= 0)",
    $ctsDestinationStationIndex,
    [System.StringComparison]::Ordinal)
$ctsExactBindingIndex = $downloadCharacter.IndexOf(
    "getIntObjVar(unpackedItem, account_containers.VAR_STATION_ID) != destinationStationId",
    $ctsPositiveStationIndex,
    [System.StringComparison]::Ordinal)
$ctsImportedTranslationIndex = $downloadCharacter.IndexOf(
    "datapadItemOidTranslation.put(key, unpackedItem);",
    $ctsExactBindingIndex,
    [System.StringComparison]::Ordinal)
Assert-Contract ($ctsUnpackedContainerIndex -ge 0 -and
    $ctsDestinationStationIndex -gt $ctsUnpackedContainerIndex -and
    $ctsPositiveStationIndex -gt $ctsDestinationStationIndex -and
    $ctsExactBindingIndex -gt $ctsPositiveStationIndex -and
    $downloadCharacter.Contains(
        "!account_containers.isBoundToPlayer(unpackedItem, self)") -and
    $ctsImportedTranslationIndex -gt $ctsExactBindingIndex -and
    $ctsReprovisionIndex -gt $ctsImportedTranslationIndex) `
    "precu.nested-control.cts-import-rebound-before-reprovision"

Assert-Contract ($accountContainers.Contains(
    "attachScript(container, SCRIPT_NO_DESTROY);") -and
    $noDestroy.Contains("public int OnDestroy(obj_id self)") -and
    $noDestroy.Contains("return SCRIPT_OVERRIDE;")) `
    "precu.nested-control.normal-no-destroy-preserved"

$workerPendingStoreIndex = $workerDispatch.IndexOf(
    "storePendingAction(",
    [System.StringComparison]::Ordinal)
$workerAckIndex = $workerDispatch.IndexOf(
    "public int handleWorkerDroidActionAck(",
    [System.StringComparison]::Ordinal)
$workerConsumeIndex = $workerDispatch.IndexOf(
    "if (!consumable.decrementCharges(self, player))",
    [System.StringComparison]::Ordinal)
Assert-Contract ($workerPendingStoreIndex -ge 0 -and
    $workerDispatch.Contains("ITEM_PENDING_ACTION_ROOT") -and
    $workerDispatch.Contains("ACTION_DELIVERY_DELAY_SECONDS") -and
    $workerAckIndex -gt $workerPendingStoreIndex -and
    $workerConsumeIndex -gt $workerAckIndex -and
    $workerDispatch.Contains("PENDING_STATE_ACKNOWLEDGED") -and
    $workerDispatch.Contains("countBefore < 0") -and
    $workerDispatch.Contains("countBefore <= 1") -and
    $workerDispatch.Contains("destroyObject(self)") -and
    $workerDispatch.Contains("PLAYER_PENDING_ITEM") -and
    $decrementCharges.Contains("else if (charges > 1)") -and
    $decrementCharges.Contains("destroyObject(item);") -and
    $workerGrant.Contains(
        "token <= 0 || !isValidId(player) || isIdNull(workerDroid)") -and
    $workerGrant.Contains("String grantRoot = getGrantRoot(token);") -and
    $workerGrant.Contains(
        "getObjIdObjVar(self, grantRoot + GRANT_DROID_SUFFIX) == workerDroid") -and
    -not $workerGrant.Contains("isValidId(workerDroid)")) `
    "precu.worker-droid.final-charge-dispatch"

$workerDeadlineStoreIndex = $workerDispatch.IndexOf(
    "ITEM_PENDING_DEADLINE,",
    $workerPendingStoreIndex,
    [System.StringComparison]::Ordinal)
$workerPendingCommitIndex = $workerDispatch.IndexOf(
    "ITEM_PENDING_STATE, PENDING_STATE_DISPATCHED",
    $workerDeadlineStoreIndex,
    [System.StringComparison]::Ordinal)
$workerResumePending = Get-FunctionSlice $workerDispatch `
    "public void resumePendingAction(" "public boolean armPendingActionRetry("
$workerExpirePending = Get-FunctionSlice $workerDispatch `
    "public int expirePendingWorkerDroidAction(" `
    "public boolean dispatchPendingAction("
$workerDispatchPending = Get-FunctionSlice $workerDispatch `
    "public boolean dispatchPendingAction(" `
    "public int retryPendingWorkerDroidAction("
$workerForceTimeout = Get-FunctionSlice $workerDispatch `
    "public boolean forcePendingActionTimeout(" `
    "public boolean recoverTerminalPendingAction("
$workerRecoverTerminal = Get-FunctionSlice $workerDispatch `
    "public boolean recoverTerminalPendingAction(" `
    "public boolean completeTerminalPendingAction("
$workerResumeDeadlineIndex = $workerResumePending.IndexOf(
    "if (!armPendingActionDeadline(",
    [System.StringComparison]::Ordinal)
$workerResumeHoldIndex = $workerResumePending.IndexOf(
    "if (!holdPendingActionFlow(",
    [System.StringComparison]::Ordinal)
$workerTimeoutFixture = Get-FunctionSlice $featureFixture `
    "private String workerTimeout(" "private String workerSelect("
$workerTimeoutDestroyIndex = $workerTimeoutFixture.IndexOf(
    "destroyObject(structure)",
    [System.StringComparison]::Ordinal)
$workerTimeoutExpireIndex = $workerTimeoutFixture.IndexOf(
    '"expirePendingWorkerDroidAction"',
    [System.StringComparison]::Ordinal)
Assert-Contract ($workerDeadlineStoreIndex -gt $workerPendingStoreIndex -and
    $workerPendingCommitIndex -gt $workerDeadlineStoreIndex -and
    $workerDroid.Contains("ACTION_CONFIRMATION_TIMEOUT_SECONDS") -and
    $workerDroid.Contains("PENDING_STATE_TIMED_OUT") -and
    $workerDispatch.Contains(
        "!isIdNull(getObjIdObjVar(self, ITEM_PENDING_TARGET))") -and
    $workerDispatch.Contains("boolean deadlineQueued = armPendingActionDeadline(") -and
    $workerDispatch.Contains("if (!deadlineQueued)") -and
    $workerDispatch.Contains("if (!dispatchQueued)") -and
    $workerResumeDeadlineIndex -ge 0 -and
    $workerResumeHoldIndex -gt $workerResumeDeadlineIndex -and
    $workerResumePending.Contains("if (!armPendingActionRetry(") -and
    $workerExpirePending.Contains("if (!armPendingActionDeadline(") -and
    $workerExpirePending.Contains("forcePendingActionTimeout(") -and
    $workerDispatchPending.Contains("if (!armPendingActionRetry(") -and
    $workerDispatchPending.Contains("if (!armPendingActionDeadline(") -and
    $workerDispatchPending.Contains("forcePendingActionTimeout(") -and
    $workerForceTimeout.Contains("if (!setObjVar(") -and
    $workerForceTimeout.Contains("if (!armPendingActionDeadline(") -and
    $workerForceTimeout.Contains("clearPendingActionFlow(self, player)") -and
    $workerRecoverTerminal.Contains("&& !armPendingActionDeadline(") -and
    $workerRecoverTerminal.Contains("clearPendingActionFlow(self, player)") -and
    $workerDispatch.Contains(
        "public int expirePendingWorkerDroidAction(") -and
    $workerDispatch.Contains("completeTerminalPendingAction(") -and
    $workerDispatch.Contains(
        "exhausted its confirmation deadline") -and
    $workerDispatch.Contains(
        "already-dispatched droid is being consumed") -and
    $featureFixture.Contains('"workerTimeout".equalsIgnoreCase(action)') -and
    $featureFixture.Contains("ITEM_PENDING_DEADLINE") -and
    $featureFixture.Contains("getCalendarTime() - 1") -and
    $featureFixture.Contains('"expirePendingWorkerDroidAction"') -and
    $workerTimeoutDestroyIndex -ge 0 -and
    $workerTimeoutExpireIndex -gt $workerTimeoutDestroyIndex -and
    $workerTimeoutFixture.Contains("STRUCTURE_REMOVED, 1") -and
    $workerTimeoutFixture.Contains("deadlineExpiredQueued=true") -and
    -not $workerTimeoutFixture.Contains(
        "deadlineExpiredQueued=true valid=true") -and
    $featureFixture.Contains("timeoutComplete=") -and
    $workerTimeoutFixture.Contains("WORKER_TIMEOUT_EXPECTED") -and
    $workerTimeoutFixture.Contains("1.0f") -and
    $workerTimeoutFixture.Contains("if (!messageTo(")) `
    "precu.worker-droid.no-ack-deadline"

Assert-Contract ($workerDroidTarget.Contains(
        'return GRANT_ROOT + "." + token;') -and
    $workerDroidTarget.Contains(
        'removeObjVar(self, getGrantRoot(params.getInt("token")));') -and
    $workerDroidTarget.Contains("GRANT_STATE_PENDING") -and
    $workerDroidTarget.Contains("GRANT_STATE_COMPLETED") -and
    $workerDroidTarget.Contains("replayCompletedGrantAction(") -and
    -not $workerDroidTarget.Contains(
        "utils.removeScriptVarTree(self, GRANT_ROOT);") -and
    -not $workerDroidTarget.Contains(
        "removeObjVar(self, GRANT_ROOT);")) `
    "precu.worker-droid.concurrent-grants-token-keyed"

Assert-Contract ($workerDroidTarget.Contains(
    "setObjVar(self, grantRoot + GRANT_PLAYER_SUFFIX, player);") -and
    $workerDroidTarget.Contains(
        "grantRoot + GRANT_EXPIRES_SUFFIX") -and
    $workerDroidTarget.Contains(
        '"clearWorkerDroidGrant",') -and
    $workerDroidTarget.Contains("GRANT_TIMEOUT_SECONDS,") -and
    $workerDroidTarget.Contains(
        "public int OnInitialize(obj_id self)") -and
    $workerDroidTarget.Contains(
        "clearExpiredWorkerDroidGrants(self);") -and
    $workerDroidTarget.Contains("GRANT_ACTION_SUFFIX") -and
    $workerDroidTarget.Contains("GRANT_SUCCESS_SUFFIX") -and
    $workerDroidTarget.Contains("queueStoredActionAck(") -and
    $workerDroidTarget.Contains("ACTION_ACK_DELAY_SECONDS") -and
    -not $workerDroidTarget.Contains(
        "utils.setScriptVar(self, grantRoot + GRANT_PLAYER_SUFFIX")) `
    "precu.worker-droid.grants-survive-target-restart"

Assert-Contract ($workerCleanup.Contains(
    "if (ownsHandoff && sui.hasPid(player, PID_NAME))") -and
    -not $workerCleanup.Contains(
        "if (sui.hasPid(player, PID_NAME))")) `
    "precu.worker-droid.unrelated-stack-preserves-sui"

$workerQueueIndex = $workerBegin.IndexOf(
    "boolean queued = queueCommand(",
    [System.StringComparison]::Ordinal)
$workerCooldownSetIndex = $workerBegin.IndexOf(
    "PLAYER_LOCATE_COOLDOWN,",
    $workerQueueIndex,
    [System.StringComparison]::Ordinal)
Assert-Contract ($workerBegin.Contains(
    "if (hasObjVar(player, PLAYER_LOCATE_COOLDOWN))") -and
    $workerBegin.Contains("cooldownUntil > now") -and
    $workerBegin.Contains('getStringCrc("locatestructure")') -and
    $workerQueueIndex -ge 0 -and
    $workerCooldownSetIndex -gt $workerQueueIndex -and
    $workerDroid.Contains("LOCATE_COOLDOWN_SECONDS = 60")) `
    "precu.worker-droid.locate-fanout-rate-limited"

Assert-Contract ($workerDroid.Contains(
    'new string_id("precu_container_droid", "worker_droid_n")') -and
    $surveyDroidDevice.Contains(
        'new string_id("precu_container_droid", "survey_droid_n")') -and
    $accountContainers.Contains(
        "new string_id(NAME_TABLE, defaultNameKey)") -and
    -not $workerDroid.Contains('setName(self, "Worker Droid")') -and
    -not $surveyDroidDevice.Contains('setName(self, "Survey Droid")')) `
    "precu.static-name.runtime-setters-localized"

Assert-Contract (-not $workerDroid.Contains("setCount(self,") -and
    -not $surveyDroidDevice.Contains("setCount(self,") -and
    $featureFixture.Contains("getCount(seeker) == 20") -and
    $featureFixture.Contains(
        "getCount(worker) == 0 && getCount(survey) == 0") -and
    $featureFixture.Contains(
        "sameStringId(workerNameId, getNameStringId(worker))") -and
    $featureFixture.Contains(
        "getString(workerNameId)") -and
    $featureFixture.Contains(
        '"Worker Droid".equals(workerLocalizedName)') -and
    $featureFixture.Contains(
        "sameStringId(surveyNameId, getNameStringId(survey))") -and
    $featureFixture.Contains(
        "getString(surveyNameId)") -and
    $featureFixture.Contains(
        '"Survey Droid".equals(surveyLocalizedName)')) `
    "precu.droid.unstacked-single-use-and-localized-name"

$surveyQueueIndex = $surveyDispatch.IndexOf(
    "boolean queued = messageTo(",
    [System.StringComparison]::Ordinal)
$surveyConsumeIndex = $surveyDispatch.IndexOf(
    "consumable.decrementCharges(self, player);",
    [System.StringComparison]::Ordinal)
Assert-Contract ($surveyQueueIndex -ge 0 -and
    $surveyDispatch.Contains("if (!queued)") -and
    $surveyConsumeIndex -gt $surveyQueueIndex) `
    "precu.survey-droid.enqueue-before-consume"

Assert-Contract ($featureFixture.Contains("getWaypointsInDatapad(player)") -and
    -not $featureFixture.Contains(
        "getGameObjectType(object) == GOT_data_waypoint")) `
    "precu.survey-droid.native-waypoint-enumeration"

Assert-Contract ($featureFixture.Contains(
        "String footprint = HARVESTER_TEMPLATE;") -and
    $featureFixture.Contains("float[][] anchors") -and
    $featureFixture.Contains("setOwner(structure, player)") -and
    $featureFixture.Contains("structure.isAuthoritative()") -and
    $featureFixture.Contains("isInWorldCell(structure)") -and
    $featureFixture.Contains("persistObject(structure)") -and
    $featureFixture.Contains("beginFixtureWorker") -and
    $featureFixture.Contains("selectFixtureWorker") -and
    $featureFixture.Contains("boolean ownsHandoff = false;") -and
    $featureFixture.Contains("if (ownsHandoff &&") -and
    $featureFixture.Contains("failWorkerPrepare(") -and
    $featureFixture.Contains("FIXTURE_HANDLER_TIMEOUT_SECONDS") -and
    $featureFixture.Contains("refreshWorkerFixtureState(player)") -and
    $featureFixture.Contains("consumed ? 2 : -1") -and
    -not $featureFixture.Contains("remoteActionResultTimeout") -and
    $featureFixture.Contains("remoteActionUnconfirmed") -and
    $featureFixture.Contains("boolean productionPending") -and
    $featureFixture.Contains("selectionState == 2 ||") -and
    $featureFixture.Contains("ITEM_PENDING_ACTION") -and
    $featureFixture.Contains("PLAYER_PENDING_ITEM") -and
    $featureFixture.Contains("workerActionPending") -and
    $featureFixture.Contains("destroyObject(structure)") -and
    ([regex]::Matches($featureFixture, 'targetNotFixture').Count -ge 2) -and
    ([regex]::Matches($featureFixture, '1\.0f,\s*\r?\n\s*true\)\)?').Count -ge 2) -and
    -not $featureFixture.Contains("initializeFixtureStructure") -and
    -not $featureFixture.Contains("initializeStructure(") -and
    -not $featureFixture.Contains("removeStructure(") -and
    -not $featureFixture.Contains(
        "player_structure.getFootprintTemplate(")) `
    "precu.worker-droid.fixture-console-safe-placement"

$generator = Get-Content -LiteralPath $generatorPath -Raw
Assert-Contract ($generator.Contains(
    '$outputPath = Join-Path $root "serverdata/string/en/precu_container_droid.stf"') -and
    $generator.Contains('[switch]$Check') -and
    -not $generator.Contains('[string]$OutputPath')) `
    "precu.static-name.generator-bounded-output"

$expectedStrings = [ordered]@{
    resource_crates_n = "Resource Crates"
    resource_crates_d = "An account-bound datapad container for storing resource crates."
    spaceship_parts_n = "Spaceship Parts"
    spaceship_parts_d = "An account-bound datapad container for storing spaceship parts."
    craft_components_n = "Craft Components"
    craft_components_d = "An account-bound datapad container for storing crafted components."
    vehicles_n = "Vehicles"
    vehicles_d = "An account-bound datapad container for storing vehicle control devices."
    droids_n = "Droids"
    droids_d = "An account-bound datapad container for storing droid control devices."
    worker_droid_n = "Worker Droid"
    worker_droid_d = "A single-use droid that remotely manages one of its owner's factories or harvesters."
    survey_droid_n = "Survey Droid"
    survey_droid_d = "A single-use droid that remotely surveys a planet and returns with a waypoint to a resource concentration of 50% or greater."
}
$stringTable = Read-PrecuStringTable $stringTablePath
$stringValuesMatch = $stringTable.ValuesByName.Count -eq $expectedStrings.Count
foreach ($entry in $expectedStrings.GetEnumerator())
{
    $stringValuesMatch = $stringValuesMatch -and
        $stringTable.ValuesByName.ContainsKey([string]$entry.Key) -and
        $stringTable.ValuesByName[[string]$entry.Key] -ceq [string]$entry.Value
}
$englishSourceCrcs = @($stringTable.SourceCrcById.Values | Where-Object {
    $_ -ne [uint32]::MaxValue
}).Count -eq 0
Assert-Contract ($stringTable.Magic -eq [uint32]0xabcd -and
    $stringTable.Version -eq 1 -and
    $stringTable.NextUniqueId -eq 15 -and
    $stringTable.EntryCount -eq 14 -and
    $englishSourceCrcs -and
    $stringValuesMatch) `
    "precu.static-name.stf-exact-values"

$templateReferences = [ordered]@{
    $resourceContainerTemplatePath = @("resource_crates_n", "resource_crates_d")
    $craftContainerTemplatePath = @("craft_components_n", "craft_components_d")
    $vehicleContainerTemplatePath = @("vehicles_n", "vehicles_d")
    $droidContainerTemplatePath = @("droids_n", "droids_d")
}
foreach ($path in $shipContainerTemplatePaths)
{
    $templateReferences[$path] = @("spaceship_parts_n", "spaceship_parts_d")
}

$containerReferencesMatch = $true
foreach ($reference in $templateReferences.GetEnumerator())
{
    $template = Get-Content -LiteralPath ([string]$reference.Key) -Raw
    $keys = [string[]]$reference.Value
    $containerReferencesMatch = $containerReferencesMatch -and
        $template.Contains(
            "objectName = `"precu_container_droid`" `"$($keys[0])`"") -and
        $template.Contains(
            "detailedDescription = `"precu_container_droid`" `"$($keys[1])`"")
}
Assert-Contract $containerReferencesMatch `
    "precu.static-name.account-container-references"

$workerDroidTemplate = Get-Content -LiteralPath $workerDroidTemplatePath -Raw
$surveyDroidTemplate = Get-Content -LiteralPath $surveyDroidTemplatePath -Raw
Assert-Contract ($workerDroidTemplate.Contains(
    'objectName = "precu_container_droid" "worker_droid_n"') -and
    $workerDroidTemplate.Contains(
        'detailedDescription = "precu_container_droid" "worker_droid_d"') -and
    $workerDroidTemplate.Contains(
        'lookAtText = "precu_container_droid" "worker_droid_n"') -and
    -not $workerDroidTemplate.Contains('"legacy_utility"')) `
    "precu.static-name.worker-droid-reference"
Assert-Contract ($surveyDroidTemplate.Contains(
    'objectName = "precu_container_droid" "survey_droid_n"') -and
    $surveyDroidTemplate.Contains(
        'detailedDescription = "precu_container_droid" "survey_droid_d"') -and
    $surveyDroidTemplate.Contains(
        'lookAtText = "precu_container_droid" "survey_droid_n"') -and
    -not $surveyDroidTemplate.Contains('"interplanetary_survey_droid"')) `
    "precu.static-name.survey-droid-reference"

if ($failures.Count -gt 0)
{
    throw "PRE-CU nested control-container regression failed: $($failures -join ', ')"
}

Write-Host "PRE-CU nested control-container regression passed."
