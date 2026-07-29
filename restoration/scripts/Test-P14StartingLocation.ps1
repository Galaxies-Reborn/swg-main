[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $restorationRoot "manifest.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14StartingLocation)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
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
        throw "Required materialized starting-location source is missing: $path"
    }
}

$gameServer = Get-Content -LiteralPath $paths.gameServer -Raw
$newbieTutorial = Get-Content -LiteralPath $paths.newbieTutorial -Raw
$creatureObject = Get-Content -LiteralPath $paths.creatureObject -Raw
$newbieHallSkipped = Get-Content -LiteralPath $paths.newbieHallSkipped -Raw
$travelTerminal = Get-Content -LiteralPath $paths.travelTerminal -Raw
$newbieSkipped = Get-Content -LiteralPath $paths.newbieSkipped -Raw
$tutorialBase = Get-Content -LiteralPath $paths.tutorialBase -Raw

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

    $openBrace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($openBrace -lt 0)
    {
        return ""
    }

    $depth = 0
    for ($index = $openBrace; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{')
        {
            $depth++
        }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }

    return ""
}

$sceneId = [string]$contract.sharedSkippedHall.sceneId
$buildingTemplate = [string]$contract.sharedSkippedHall.buildingTemplate
$startCell = [string]$contract.sharedSkippedHall.startCell
$worldCoordinatesMarker = [string]$contract.sharedSkippedHall.worldCoordinatesMarker
$startCoordinatesMarker = [string]$contract.sharedSkippedHall.startCoordinatesMarker
$skipMarker = [string]$contract.sharedSkippedHall.skipMarker
$openMarker = [string]$contract.selection.openScriptVar
$pendingMarker = [string]$contract.selection.pendingMarker
$transferNameMarker = [string]$contract.selection.transferNameMarker
$transferPollMarker = [string]$contract.selection.transferPollMarker
$requestCommand = [string]$contract.selection.requestCommand
$selectCommand = [string]$contract.selection.selectCommand
$endHandler = [string]$contract.selection.endHandler

$createHandler = Get-BracedBlock -Text $gameServer -Signature "void GameServer::handleCharacterCreateNameVerification("
$createSkippedSetup = Get-BracedBlock -Text $newbieTutorial -Signature "void NewbieTutorial::setupCharacterToSkipTutorial("
$createFullSetup = Get-BracedBlock -Text $newbieTutorial -Signature "void NewbieTutorial::setupCharacterForTutorial("
$getOrCreateHall = Get-BracedBlock -Text $newbieTutorial -Signature "ServerObject *NewbieTutorial::getOrCreateSkippedTutorial("
$isInTutorial = Get-BracedBlock -Text $newbieTutorial -Signature "bool NewbieTutorial::isInTutorial("
$transition = Get-BracedBlock -Text $creatureObject -Signature "void CreatureObject::handleTutorialTransition("
$receivedItem = Get-BracedBlock -Text $newbieHallSkipped -Signature "public int OnReceivedItem("
$menuSelect = Get-BracedBlock -Text $travelTerminal -Signature "public int OnObjectMenuSelect("
$leaveTutorial = Get-BracedBlock -Text $travelTerminal -Signature "public void leaveTutorial("
$requestLocations = Get-BracedBlock -Text $newbieSkipped -Signature "public int $requestCommand("
$selectLocation = Get-BracedBlock -Text $newbieSkipped -Signature "public int $selectCommand("
$handleEndTutorial = Get-BracedBlock -Text $newbieSkipped -Signature "public int $endHandler("
$onDetach = Get-BracedBlock -Text $newbieSkipped -Signature "public int OnDetach("
$onLogin = Get-BracedBlock -Text $newbieSkipped -Signature "public int OnLogin("
$sendToStartLocation = Get-BracedBlock -Text $tutorialBase -Signature "public boolean sendToStartLocation("
$sendThoseStartLocs = Get-BracedBlock -Text $tutorialBase -Signature "public void sendThoseStartLocs("

Write-Host "Publish 14.1 skipped-hall/starting-location checks:"

Assert-Contract -Condition ($createHandler.Length -gt 0) -Name "p14.starting-location.creation-handler-present"
Assert-Contract `
    -Condition ($createHandler.Contains("tr.setPosition_p(NewbieTutorial::getSkippedTutorialLocation());") -and -not $createHandler.Contains("tr.setPosition_p(createMessage->getCoordinates());")) `
    -Name "p14.starting-location.unchecked-creation-uses-shared-hall-location"
Assert-Contract `
    -Condition ($createHandler.Contains("newCharacterObject->setSceneIdOnThisAndContents(NewbieTutorial::getSceneId());") -and -not $createHandler.Contains("setSceneIdOnThisAndContents(createMessage->getPlanetName())")) `
    -Name "p14.starting-location.unchecked-creation-persists-tutorial-scene"

Assert-Contract -Condition ($newbieTutorial.Contains($buildingTemplate)) -Name "p14.starting-location.shared-hall-template"
Assert-Contract -Condition ($newbieTutorial.Contains("s_sceneId(`"$sceneId`")")) -Name "p14.starting-location.tutorial-scene"
Assert-Contract -Condition ($newbieTutorial.Contains("s_skippedTutorialStartCellName(`"$startCell`")")) -Name "p14.starting-location.shared-hall-room-one"
Assert-Contract -Condition ($newbieTutorial.Contains($worldCoordinatesMarker)) -Name "p14.starting-location.shared-hall-world-coordinates"
Assert-Contract -Condition ($newbieTutorial.Contains($startCoordinatesMarker)) -Name "p14.starting-location.shared-hall-entry-coordinates"
Assert-Contract `
    -Condition ($getOrCreateHall.Contains("s_skippedTutorial.getObject()") -and $getOrCreateHall.Contains("ServerWorld::createNewObject(") -and $getOrCreateHall.Contains("s_skippedTutorialTemplate") -and $getOrCreateHall.Contains("skippedTutorial->addToWorld();") -and $getOrCreateHall.Contains("s_skippedTutorial = CachedNetworkId(*skippedTutorial);")) `
    -Name "p14.starting-location.shared-hall-reused-and-created-natively"
Assert-Contract `
    -Condition ($createSkippedSetup.Contains("removeObjVarItem(s_tutorialObjVar)") -and $createSkippedSetup.Contains("setObjVarItem(s_skippedTutorialObjVar, 1)")) `
    -Name "p14.starting-location.skip-marker-created-exclusively"
Assert-Contract -Condition ($createFullSetup.Contains("removeObjVarItem(s_skippedTutorialObjVar)")) -Name "p14.starting-location.full-tutorial-clears-skip-marker"
Assert-Contract `
    -Condition ($isInTutorial.Contains("shouldStartTutorial(character) || shouldStartSkippedTutorial(character)")) `
    -Name "p14.starting-location.skip-marker-counts-as-tutorial-state"

Assert-Contract `
    -Condition ($transition.Contains("NewbieTutorial::shouldStartSkippedTutorial(this)") -and $transition.Contains("(startTutorial || startSkippedTutorial) && currentScene == NewbieTutorial::getSceneId()")) `
    -Name "p14.starting-location.native-transition-recognizes-skip-marker"
Assert-Contract `
    -Condition ($transition.Contains("NewbieTutorial::getOrCreateSkippedTutorial()") -and $transition.Contains("NewbieTutorial::getSkippedTutorialStartCellName()") -and $transition.Contains("NewbieTutorial::getSkippedTutorialStartCoords()") -and $transition.Contains("teleportObject(newLocation, tutorial->getNetworkId(), startCellName, startCoords, `"`", true);")) `
    -Name "p14.starting-location.native-transition-enters-shared-hall-r1"
Assert-Contract `
    -Condition ($transition.Contains("((startTutorial || startSkippedTutorial) && isFromLogin) &&") -and $transition.Contains("startSkippedTutorial ? NewbieTutorial::getSkippedTutorialLocation() : NewbieTutorial::getTutorialLocation()")) `
    -Name "p14.starting-location.relog-before-selection-returns-to-shared-hall"
Assert-Contract `
    -Condition ($transition.Contains("!(startSkippedTutorial && currentScene != NewbieTutorial::getSceneId() && getObjVars().hasItem(`"$pendingMarker`"))")) `
    -Name "p14.starting-location.pending-world-login-bypasses-tutorial-rewarp"

Assert-Contract `
    -Condition ($receivedItem.Contains("getCellId(self, `"$startCell`")") -and $receivedItem.Contains("if (room1 == yourCell)") -and $receivedItem.Contains("attachScript(item, NEWBIE_SCRIPT_SKIPPED);")) `
    -Name "p14.starting-location.room-one-attaches-skipped-script"
Assert-Contract `
    -Condition (-not $newbieHallSkipped.Contains("warp_player_now") -and -not $receivedItem.Contains("messageTo(terminal")) `
    -Name "p14.starting-location.no-automatic-arrival-warp"

Assert-Contract -Condition ($menuSelect.Contains("leaveTutorial(self, player);")) -Name "p14.starting-location.terminal-use-opens-handoff"
$terminalOpenAt = $leaveTutorial.IndexOf("utils.setScriptVar(player, newbie_skipped.STARTING_LOCATION_SELECTION_OPEN, true);", [StringComparison]::Ordinal)
$terminalSendAt = $leaveTutorial.IndexOf("sendThoseStartLocs(player);", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($terminalOpenAt -ge 0 -and $terminalSendAt -gt $terminalOpenAt) `
    -Name "p14.starting-location.terminal-opens-gate-before-list"
foreach ($marker in @($contract.terminalForbiddenMarkers))
{
    Assert-Contract -Condition (-not $travelTerminal.Contains([string]$marker)) -Name "p14.starting-location.terminal-absent.$marker"
}

$canonicalLookup = [string]$contract.canonicalStartingLocations.tableMethod
$canonicalSend = [string]$contract.canonicalStartingLocations.sendMethod
$canonicalBypass = [string]$contract.canonicalStartingLocations.forbiddenBypass
$canonicalLookupAt = $sendThoseStartLocs.IndexOf($canonicalLookup, [StringComparison]::Ordinal)
$canonicalSendAt = $sendThoseStartLocs.IndexOf($canonicalSend, [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($canonicalLookupAt -ge 0 -and $canonicalSendAt -gt $canonicalLookupAt) `
    -Name "p14.starting-location.canonical-location-list-sent"
Assert-Contract `
    -Condition (-not $sendThoseStartLocs.Contains($canonicalBypass) -and -not $sendThoseStartLocs.Contains("warpPlayer(")) `
    -Name "p14.starting-location.no-fixed-location-bypass"

$lookupAt = $sendToStartLocation.IndexOf("loc = getStartingLocationInfo(name);", [StringComparison]::Ordinal)
$nullAt = $sendToStartLocation.IndexOf("if (loc == null)", [StringComparison]::Ordinal)
$failureAt = $sendToStartLocation.IndexOf("newbieTutorialSendStartingLocationSelectionResult(self, name, false);", [StringComparison]::Ordinal)
$successAt = $sendToStartLocation.IndexOf("newbieTutorialSendStartingLocationSelectionResult(self, name, true);", [StringComparison]::Ordinal)
$warpAt = $sendToStartLocation.IndexOf("warpPlayer(", [StringComparison]::Ordinal)
$returnTrueAt = $sendToStartLocation.LastIndexOf("return true;", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($lookupAt -ge 0 -and $nullAt -gt $lookupAt -and $failureAt -gt $nullAt -and $successAt -gt $failureAt -and $warpAt -gt $successAt -and $returnTrueAt -gt $warpAt) `
    -Name "p14.starting-location.validate-before-success-and-warp"
Assert-Contract `
    -Condition ($sendToStartLocation.Contains("return false;") -and -not $sendToStartLocation.Contains("boolean available = true")) `
    -Name "p14.starting-location.invalid-choice-rejected"
Assert-Contract `
    -Condition ($sendToStartLocation.Contains('"tutorial".equals(currentLocation.area)') -and $sendToStartLocation.Contains("isStartingLocationAvailable(name)")) `
    -Name "p14.starting-location.choice-requires-tutorial-and-availability"

$requestSceneAt = $requestLocations.IndexOf('"tutorial".equals(getLocation(self).area)', [StringComparison]::Ordinal)
$requestAuthorizationAt = $requestLocations.IndexOf("utils.hasScriptVar(self, STARTING_LOCATION_SELECTION_OPEN)", [StringComparison]::Ordinal)
$requestPendingAt = $requestLocations.IndexOf("!hasObjVar(self, STARTING_LOCATION_TRANSFER_PENDING)", [StringComparison]::Ordinal)
$requestSendAt = $requestLocations.IndexOf("sendThoseStartLocs(self);", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($requestSceneAt -ge 0 -and $requestAuthorizationAt -gt $requestSceneAt -and $requestPendingAt -gt $requestAuthorizationAt -and $requestSendAt -gt $requestPendingAt -and -not $requestLocations.Contains("setObjVar(self, STARTING_LOCATION_SELECTION_OPEN") -and -not $requestLocations.Contains("utils.setScriptVar(self, STARTING_LOCATION_SELECTION_OPEN")) `
    -Name "p14.starting-location.request-command-cannot-authorize-selection"

$replayGuardAt = $selectLocation.IndexOf("hasObjVar(self, STARTING_LOCATION_TRANSFER_PENDING) || !utils.hasScriptVar(self, STARTING_LOCATION_SELECTION_OPEN)", [StringComparison]::Ordinal)
$replayRejectAt = $selectLocation.IndexOf("newbieTutorialSendStartingLocationSelectionResult(self, params, false);", [StringComparison]::Ordinal)
$consumeGateAt = $selectLocation.IndexOf("utils.removeScriptVar(self, STARTING_LOCATION_SELECTION_OPEN);", [StringComparison]::Ordinal)
$validatedTransferAt = $selectLocation.IndexOf("if (!sendToStartLocation(self, params))", [StringComparison]::Ordinal)
$reopenGateAt = $selectLocation.IndexOf("utils.setScriptVar(self, STARTING_LOCATION_SELECTION_OPEN, true);", [StringComparison]::Ordinal)
$setPendingAt = $selectLocation.IndexOf("setObjVar(self, STARTING_LOCATION_TRANSFER_PENDING, true);", [StringComparison]::Ordinal)
$setTransferNameAt = $selectLocation.IndexOf("setObjVar(self, STARTING_LOCATION_TRANSFER_NAME, params);", [StringComparison]::Ordinal)
$setTransferPollsAt = $selectLocation.IndexOf("setObjVar(self, STARTING_LOCATION_TRANSFER_POLLS, 0);", [StringComparison]::Ordinal)
$endAt = $selectLocation.IndexOf("messageTo(self, `"$endHandler`"", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($replayGuardAt -ge 0 -and $replayRejectAt -gt $replayGuardAt -and $consumeGateAt -gt $replayRejectAt -and $validatedTransferAt -gt $consumeGateAt) `
    -Name "p14.starting-location.selection-gate-blocks-replay"
Assert-Contract `
    -Condition ($reopenGateAt -gt $validatedTransferAt -and $setPendingAt -gt $reopenGateAt -and $setTransferNameAt -gt $setPendingAt -and $setTransferPollsAt -gt $setTransferNameAt -and $endAt -gt $setTransferPollsAt -and -not $selectLocation.Contains("removeObjVar(self, `"$skipMarker`");")) `
    -Name "p14.starting-location.valid-selection-starts-confirmed-transfer"
$confirmedWorldAt = $handleEndTutorial.IndexOf("if (!loc.area.equals(`"$sceneId`"))", [StringComparison]::Ordinal)
$confirmedRemoveAt = $handleEndTutorial.IndexOf("removeObjVar(self, `"$skipMarker`");", [StringComparison]::Ordinal)
$confirmedDetachAt = $handleEndTutorial.IndexOf("detachScript(self, `"theme_park.newbie_tutorial.newbie_skipped`");", [StringComparison]::Ordinal)
$retryAt = $handleEndTutorial.LastIndexOf("messageTo(self, `"$endHandler`"", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($confirmedWorldAt -ge 0 -and $confirmedRemoveAt -gt $confirmedWorldAt -and $confirmedDetachAt -gt $confirmedRemoveAt -and $retryAt -gt $confirmedDetachAt) `
    -Name "p14.starting-location.marker-cleared-after-world-confirmation"
Assert-Contract `
    -Condition ($handleEndTutorial.Contains("STARTING_LOCATION_TRANSFER_MAX_POLLS") -and $handleEndTutorial.Contains("newbieTutorialSendStartingLocationSelectionResult(self, selection, false);") -and $handleEndTutorial.Contains("sendThoseStartLocs(self);")) `
    -Name "p14.starting-location.failed-transfer-reopens-selection"
Assert-Contract `
    -Condition ($onDetach.Contains("removeObjVar(self, `"newbie`");") -and $onDetach.Contains("utils.removeScriptVar(self, STARTING_LOCATION_SELECTION_OPEN);") -and $onDetach.Contains("removeObjVar(self, STARTING_LOCATION_TRANSFER_PENDING);")) `
    -Name "p14.starting-location.detach-cleans-selection-state"
Assert-Contract `
    -Condition ($onLogin.Contains("if (!area.equals(`"$sceneId`"))") -and $onLogin.Contains("removeObjVar(self, `"$skipMarker`");") -and $onLogin.Contains("detachScript(self, `"theme_park.newbie_tutorial.newbie_skipped`");")) `
    -Name "p14.starting-location.relog-after-transfer-retires-skipped-script"

Assert-Contract -Condition ($newbieSkipped.Contains("`"$openMarker`"") -and $newbieSkipped.Contains("`"$pendingMarker`"") -and $newbieSkipped.Contains("`"$transferNameMarker`"") -and $newbieSkipped.Contains("`"$transferPollMarker`"")) -Name "p14.starting-location.selection-state-marker-names"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 starting-location contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 starting-location contract passed."
