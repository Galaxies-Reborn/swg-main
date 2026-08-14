param(
    [string]$SourceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = "Stop"
$dsrc = Join-Path $SourceRoot "dsrc"
$src = Join-Path $SourceRoot "src"

$paths = [ordered]@{
    library = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/library/atmospheric_ship.java"
    shipScript = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/space/ship/atmospheric_ship.java"
    controlDevice = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/space/ship_control_device/ship_control_device.java"
    combatShipPlayer = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/space/combat/combat_ship_player.java"
    playerShipController = Join-Path $src "engine/server/library/serverGame/src/shared/controller/PlayerShipController.cpp"
    intangibleObject = Join-Path $src "engine/server/library/serverGame/src/shared/object/IntangibleObject.cpp"
    shipObject = Join-Path $src "engine/server/library/serverGame/src/shared/object/ShipObject.cpp"
    playerTravel = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/player/player_travel.java"
    spaceTransition = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/library/space_transition.java"
    instantTravelTerminal = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/terminal/terminal_travel_instant.java"
    scykGroundTemplate = Join-Path $dsrc "sku.0/sys.server/compiled/game/object/tangible/terminal/terminal_atmospheric_ship_hutt_light.tpf"
    scykGroundSharedTemplate = Join-Path $dsrc "sku.0/sys.shared/compiled/game/object/tangible/tcg/series5/hangar_ships/shared_hutt_fighter_light_01.tpf"
}

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Missing atmospheric-player-ship source: $($entry.Value)"
    }
}

$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $text[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Assert-Contains([string]$Name, [string]$Needle, [string]$Message) {
    if (-not $text[$Name].Contains($Needle)) {
        throw $Message
    }
}

function Assert-NotContains([string]$Name, [string]$Needle, [string]$Message) {
    if ($text[$Name].Contains($Needle)) {
        throw $Message
    }
}

# The exact persistent ShipObject remains authoritative for rendering, flight,
# paint, installed components, cargo and interiors on both ground and space.
Assert-Contains library 'setLocation(ship, callLocation);' "Call-down must move the real ship into the ground scene."
Assert-Contains library 'boolean movedToWorld = setLocation(ship, callLocation);' "Call-down must observe whether world insertion was accepted."
Assert-Contains library 'obj_id postCallContainer = getContainedBy(ship);' "Call-down must verify that the ship actually left its datapad control device."
Assert-Contains library 'if (!movedToWorld || isIdValid(postCallContainer))' "A half-called, still-contained ship must fail closed."
Assert-Contains library 'rollbackFailedCall(controlDevice, ship);' "Failed call-down must restore stored state instead of leaving an invisible active ship."
Assert-Contains library 'ITV_CALL_DELAY_SECONDS = 2.0f' "Player-ship call-down must retain the authentic two-second ITV summon cadence."
Assert-Contains library 'doAnimationAction(player, "manipulate_low")' "Player-ship call-down must play its ITV-style summon animation."
Assert-Contains library 'playClientEffectObj(player, "clienteffect/space_command/sys_manipulation.cef", player, "")' "Player-ship call-down must play an immediate summon cue."
Assert-NotContains library 'clienteffect/probot_delivery.cef' "Player-ship call-down must not use the explosive probe-droid delivery effect."
Assert-Contains library 'messageTo(ship, "playAtmosphericArrivalEffect", arrivalParams, 0.25f, false)' "The arrival cue must target the authoritative rendered ShipObject."
Assert-Contains shipScript 'playClientEffectObj(player, "clienteffect/space_command/shp_dock_release.cef", self, "")' "The called ship must use the retail ship dock-release arrival effect."
Assert-Contains library 'sendSystemMessage(player, SID_CALLING_FOR_PICKUP)' "Player-ship call-down must show the authentic ITV summon message."
Assert-Contains library 'messageTo(controlDevice, "completeAtmosphericShipCall", params, ITV_CALL_DELAY_SECONDS, false)' "The real ship must appear only after the ITV summon timer completes."
Assert-Contains library 'params.put("callLocation", callLocation)' "The delayed ITV completion must retain the exact placement that already passed admission."
Assert-Contains library 'completeCallDown(obj_id controlDevice, obj_id player, obj_id requestedShip, location requestedCallLocation)' "Delayed call-down must revalidate the exact requested persistent ship and admitted location."
Assert-Contains library 'location callLocation = requestedCallLocation' "The delayed completion must not run a second nondeterministic terrain search."
Assert-Contains controlDevice 'params.getLocation("callLocation")' "The control-device timer must return the originally admitted call location."
Assert-Contains controlDevice 'completeAtmosphericShipCall' "The ship control device must own the delayed ITV completion handler."
Assert-Contains library '!putIn(ship, controlDevice) || getContainedBy(ship) != controlDevice' "Failed call rollback and store must verify exact control-device containment."
Assert-Contains library 'preserving active world state' "A failed rollback must preserve a recoverable visible ship rather than delete it."
Assert-Contains library 'setObjVar(ship, "shipControlDevice", controlDevice);' "The deployed ship must retain its canonical control-device link."
Assert-Contains library 'The persistent ShipObject is the ground representation.' "Ground rendering must use the authoritative ship rather than a decorative proxy."
Assert-Contains library 'destroyGroundProxy(ship);' "Call and pack boundaries must remove any stale decorative proxy that could hide authoritative paint and components."
Assert-NotContains shipScript 'ensureGroundProxy(controlDevice, self);' "An active real ShipObject must not be covered by a base-hull proxy."
Assert-Contains playerTravel 'setName(pickupCraft, "Royal Instant Travel Vehicle");' "The restored Royal ITV must not expose an unresolved retail terminal title."
Assert-Contains instantTravelTerminal 'getTemplateName(self).equals(ROYAL_ITV_TEMPLATE)' "Only the explicitly restored Royal ITV may re-enter the retired terminal interaction path."
Assert-Contains instantTravelTerminal 'enterClientTicketPurchaseMode(player, planet, travelPoint, true)' "The Royal ITV Use radial must open the owner travel interface."
Assert-Contains shipScript 'monitorAtmosphericFlight' "The authoritative rendered ship must retain atmospheric lifecycle monitoring."
Assert-Contains shipScript 'mi.addRootMenu(MENU_PILOT, script.library.atmospheric_ship.SID_PILOT)' "The visible ship must expose atmospheric piloting through its authoritative real ShipObject."
Assert-Contains shipScript 'script.library.atmospheric_ship.pilot(player, interactionShip);' "The atmospheric pilot radial must use the ownership, certification, distance, and no-build guarded lifecycle."
Assert-Contains shipScript 'mi.addRootMenu(MENU_LAUNCH_SPACE, script.library.atmospheric_ship.SID_LAUNCH_SPACE)' "The visible ship must expose an explicit canonical space-launch radial."
Assert-Contains shipScript 'script.library.atmospheric_ship.launchToSpace(controlDevice, player);' "The visible-ship space radial must launch its linked authoritative ship."
Assert-Contains controlDevice 'mi.addRootMenu(MENU_ATMOSPHERIC_PILOT, atmospheric_ship.SID_PILOT)' "The active datapad ship must expose atmospheric flight."
Assert-Contains controlDevice 'mi.addRootMenu(MENU_ATMOSPHERIC_LAUNCH_SPACE, atmospheric_ship.SID_LAUNCH_SPACE)' "The active datapad ship must expose direct space launch."
Assert-Contains library 'getDistance(player, ship) > 64.0f' "Remote datapad interaction must not pilot a called ship from outside its ITV interaction range."
Assert-Contains library 'return transitionToSpace(ship);' "Direct space launch must converge on the canonical atmospheric handoff."
Assert-Contains spaceTransition 'MAX_LAUNCH_PILOT_RETRIES = 40' "Cross-zone ship authority handoff must have a bounded load-and-authority retry window."
Assert-Contains spaceTransition 'messageTo(player, "retrySpaceLaunchPilot", null, 0.5f, false);' "Space launch must retry while the player and persistent ship converge on one authoritative server."
Assert-Contains spaceTransition 'boolean shipLoaded = launchedShip.isLoaded();' "Space launch must retry valid ship identities that are not loaded on the destination server yet."
Assert-Contains spaceTransition 'clearLaunchPilotHandoff(player);' "Launch metadata must be cleared only after success or bounded final failure."
Assert-NotContains spaceTransition 'LOG("space", "NO piloting");\n            }\n            packShip(ship);' "A transient pilot handoff failure must not invoke the destructive legacy pack fallback."
Assert-Contains combatShipPlayer 'public int retrySpaceLaunchPilot(obj_id self, dictionary params)' "The player space lifecycle must own delayed pilot handoff retries."
Assert-Contains shipScript 'enter(player, interactionShip)' "POB entry on the display must route to the real ship interior."
Assert-NotContains library 'terminal_travel_instant_xwing' "Player ships must not use the generic ITV X-wing proxy."
Assert-NotContains library 'terminal_travel_instant_tie' "Player ships must not use the generic ITV TIE proxy."
Assert-NotContains library 'terminal_travel_instant_royal_ship' "Player ships must not use the generic ITV Naboo proxy."
Assert-NotContains library 'terminal_travel_instant_jalopy' "Player ships must not use the generic ITV Rattletrap proxy."
Assert-Contains library 'normalizeStoredShipState(controlDevice, linkedShip);' "Loaded control devices must reconcile stale stored-ship state."
Assert-Contains library 'getContainedBy(ship) != controlDevice || isParkedHousing(ship)' "Stored-state repair must require direct matching-PCD containment and preserve parked POB housing."
Assert-Contains library 'removeObjVar(ship, VAR_WORLD_VISIBLE);' "Stored-state repair must clear stale world visibility."
Assert-Contains library '!isOwner(player, ship)' "Call-down must reject a stale or mismatched ship ownership link."
Assert-Contains controlDevice 'menu_info_types.VEHICLE_GENERATE' "Ship control devices must expose call-down."
Assert-Contains controlDevice 'atmospheric_ship.getControlState(self)' "The datapad icon must use persisted stored/active/parked state."
Assert-Contains playerShipController 'ContainerInterface::transferItemToWorld(*ship, goal, nullptr, error)' "The persistent ship must leave datapad containment before ground-world teleport."
Assert-Contains shipObject 'void ShipObject::onContainerTransferComplete(ServerObject *oldContainer, ServerObject *newContainer)' "Ship visibility refresh must be owned by the authoritative container-transfer boundary."
Assert-Contains shipObject 'sendCreateAndBaselinesToClient(*client)' "Existing datapad observers must receive a fresh world transform create/baseline."
Assert-Contains shipObject 'UpdateContainmentMessage const worldContainment' "Existing datapad observers must receive an explicit detach from their ship control device into the world."
Assert-Contains shipObject 'client->send(worldContainment, true)' "The explicit world-containment transition must be delivered reliably."
Assert-Contains shipObject 'ObserveTracker::onObjectMadeVisibleTo(*this, observers)' "A called ship must be admitted to every nearby ground client's visibility set."

# The called world object and every datapad preview are sourced from the same
# exact player ShipObject.  Its shared template selects the actual chassis,
# while the appearance snapshot preserves paint when the ship is outside AOI.
Assert-Contains intangibleObject 'ship->getClientSharedTemplateName()' "The datapad preview must publish the called ship's exact client chassis template."
Assert-Contains intangibleObject 'ship->getAppearanceData()' "The datapad preview must publish the called ship's exact paint/customization snapshot."
Assert-Contains intangibleObject 'void IntangibleObject::onContainerLostItem' "The final ship appearance must be captured before call-down leaves the datapad."

# Unlike fixed-size ITV proxy models, real player ships range from small
# fighters to POB hulls.  Call placement therefore uses the real ship's
# collision radius and the native water/slope/static-collidable search.
Assert-Contains library 'getObjectCollisionRadius(ship)' "Call placement must derive its footprint from the selected real ship."
Assert-Contains library 'MAXIMUM_FIGHTER_CALL_FOOTPRINT = 16.0f' "Ordinary fighters must not inherit enormous space-scene collision spheres as ground placement lots."
Assert-Contains library 'MAXIMUM_POB_CALL_FOOTPRINT = 48.0f' "POB ships must retain a larger ground placement footprint than fighters."
Assert-Contains library 'space_utils.isShipWithInterior(ship) ? MAXIMUM_POB_CALL_FOOTPRINT : MAXIMUM_FIGHTER_CALL_FOOTPRINT' "Ground placement must distinguish POB hulls from ordinary fighters."
Assert-Contains library 'locations.getGoodLocationAroundLocationAvoidCollidables' "Call placement must reject water, slope, and static-collidable overlap."
Assert-Contains library 'float diameter = footprint * 2.0f' "The clear placement rectangle must use full hull diameter, not radius as width."
Assert-Contains library 'Math.max(CALL_DISTANCE, footprint + playerRadius + CALL_SEARCH_PADDING)' "Large hulls must be called farther from the player than fixed ITV proxies."
Assert-Contains library 'isCallFootprintAllowed(player, clearLocation, footprint)' "The complete hull perimeter must remain outside no-build regions."
Assert-Contains library 'if (callLocation == null || !isCallPathAllowed' "Call-down must fail when no hull-safe landing point is available."

# Call-down, landing, permanent parking and every accepted flight segment use
# the authoritative no-build region system.  Segment sampling prevents a fast
# transform from tunneling through a protected city.
Assert-Contains library 'getRegionsWithBuildableAtPoint(where, regions.BUILD_FALSE)' "Java placement must enforce build-false regions."
Assert-Contains library 'isCallPathAllowed' "Call-down must validate the complete path to the spawn point."
Assert-Contains library 'isHousingFootprintAllowed' "POB parking must validate the full housing footprint."
Assert-Contains playerShipController 'RegionMaster::getRegionsAtPoint' "Native flight must query authoritative regions."
Assert-Contains playerShipController 'region->getBuildable() == 0' "Native flight must reject no-build regions."
Assert-Contains playerShipController 'ceil(distance / s_atmosphericRegionSampleDistance)' "Native flight must sample the complete movement segment."

# Atmospheric flight uses the normal client/server ship controller.  Java
# hands the real ship to the planet's launch-table space scene at 1000m AGL;
# native validation leaves bounded headroom for the one-second monitor.
Assert-Contains library 'ATMOSPHERE_EXIT_AGL = 1000.0f' "Atmospheric transition height must remain 1000m AGL."
Assert-Contains playerShipController 's_atmosphericMaximumHeight = 1500.0f' "Native safety ceiling must retain transition headroom."
Assert-Contains library 'dataTableSearchColumnForString(groundScene, "groundScene", LAUNCH_TABLE)' "Planet-to-space routing must use the launch table."
Assert-Contains library 'space_transition.launch(pilot, ship, passengers, spaceDestination, groundLocation);' "Atmospheric exit must use the canonical launch lifecycle."
Assert-Contains library 'storeIntoControlDevice(controlDevice, ship, "Packed atmospheric ship for space transition")' "Atmospheric exit must transactionally pack the exact real ship before launch."
Assert-NotContains library 'space_transition.packShip(ship);' "Atmospheric lifecycle must never use the destructive void packShip fallback."
Assert-Contains shipScript 'monitorAtmosphericFlight' "Deployed ships must monitor atmospheric altitude."

# POB ground use is the actual ship interior.  Parking consumes exactly one
# lot, charges the small-house rate, supports maintenance/residence/access,
# and is protected from piloting and logout packing while static.
Assert-Contains library 'space_transition.getShipBoardingDestination(ship)' "Ground POB entry must use its real interior entrance."
Assert-Contains library 'SMALL_HOUSE_LOTS = 1' "A parked POB must consume one lot."
Assert-Contains library 'SMALL_HOUSE_MAINTENANCE_RATE = 4' "A parked POB must use the small-house maintenance rate."
Assert-Contains library 'MAINTENANCE_HEARTBEAT_SECONDS = 1800' "POB maintenance must use the structure heartbeat."
Assert-Contains library 'permissionsMakePrivate(ship)' "POB parking must initialize structure-style access control."
Assert-Contains library 'setHouseId(player, ship)' "A parked POB must support declared residence."
Assert-Contains controlDevice 'player_structure.payMaintenance(player, ship, amount)' "The ship datapad icon must own maintenance payment."
Assert-Contains controlDevice 'showAtmosphericHousingAccess' "The ship datapad icon must own access management."
Assert-Contains combatShipPlayer 'atmospheric_ship.isParkedHousing(ship)' "Every pilot command must reject parked POB housing."
Assert-Contains combatShipPlayer 'atmospheric_ship.forceStoreForLogout(atmosphericShip)' "Active atmospheric ships must pack safely when the owner logs out."
Assert-Contains combatShipPlayer 'space_transition.findShipControlDevicesForPlayer(self)' "Logout must discover an active called ship even when its owner is standing outside it."
Assert-Contains combatShipPlayer 'atmospheric_ship.forceStoreForLogout(calledShip)' "Every owned active nonparked datapad ship must store on logout."
Assert-Contains library 'Vector occupants = space_transition.getContainedPlayers(ship, null)' "Logout store must enumerate and evacuate ship occupants before datapad containment."
Assert-Contains library 'unpilotShip(occupant);' "Logout store must unpilot its owner before putting the ship into that owner's datapad."
Assert-Contains library 'setLocation(occupant, shipLocation);' "Logout store must break every ship-to-player containment cycle before packing."
Assert-Contains shipObject 'galaxiesReborn.atmosphericShip.worldVisible' "Called and parked ships must be visible in ground scenes."

foreach ($path in $paths.Values) {
    if ($path -match '[\\/]x32[\\/]') {
        throw "Atmospheric-player-ship authority must remain x64-only: $path"
    }
}

Write-Host "PASS: x64 atmospheric player ships, no-build flight policy, space handoff, and POB housing authority are present."
