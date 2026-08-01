[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force

function Read-Source
{
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $path = Join-Path $root ($RelativePath -replace "/", "\")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing source: $path" }
    return Get-Content -LiteralPath $path -Raw
}

function Get-BracedSurface
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Signature
    )
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing surface: $Signature" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { throw "Missing opening brace: $Signature" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    throw "Missing closing brace: $Signature"
}

$paths = [ordered]@{
    "CommandCppFuncs.cpp" = "src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.cpp"
    "CreatureObject.cpp" = "src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
    "GroupObject.cpp" = "src/engine/server/library/serverGame/src/shared/object/GroupObject.cpp"
    "PlayerObject.cpp" = "src/engine/server/library/serverGame/src/shared/object/PlayerObject.cpp"
    "travel.java" = "dsrc/sku.0/sys.server/compiled/game/script/library/travel.java"
    "player_travel.java" = "dsrc/sku.0/sys.server/compiled/game/script/player/player_travel.java"
    "command_table.tab" = "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) { $text[$entry.Key] = Read-Source $entry.Value }

foreach ($name in @("CreateGroupPickup", "UseGroupPickup"))
{
    $surface = Get-BracedSurface $text["CommandCppFuncs.cpp"] "static void commandFunc$name"
    if (-not $surface.Contains("Ignored retired NGE")) { throw "$name does not fail closed." }
    foreach ($retired in @("GroupPickupPoint", "setGroupPickup", "trigAllScripts", "transferBankCreditsTo", "createOrUpdateReusableWaypoint"))
    {
        if ($surface.Contains($retired)) { throw "$name retains later-era behavior: $retired" }
    }
}
foreach ($registration in @(
    'CommandTable::addCppFunction("createGroupPickup", commandFuncCreateGroupPickup)',
    'CommandTable::addCppFunction("useGroupPickup", commandFuncUseGroupPickup)'
))
{
    if (-not $text["CommandCppFuncs.cpp"].Contains($registration)) { throw "Compatibility registration missing: $registration" }
}
foreach ($retired in @("sharedGame/GroupPickupPoint.h", "sharedGame/TravelPoint.h", "getNearestTravelPoint"))
{
    if ($text["CommandCppFuncs.cpp"].Contains($retired)) { throw "Retired group-pickup helper remains: $retired" }
}

$seconds = Get-BracedSurface $text["GroupObject.cpp"] "unsigned int GroupObject::getSecondsLeftOnGroupPickup() const"
if (-not $seconds.Contains("return 0;") -or $seconds.Contains("::time")) { throw "Persisted group-pickup timer can become active." }
$timer = Get-BracedSurface $text["GroupObject.cpp"] "void GroupObject::setGroupPickupTimer"
if (-not $timer.Contains("std::make_pair(0, 0)") -or $timer.Contains("static_cast<int32>(startTime)")) { throw "Group-pickup timer is not normalized to zero." }
$location = Get-BracedSurface $text["GroupObject.cpp"] "void GroupObject::setGroupPickupLocation"
if (-not $location.Contains("std::make_pair(std::string(), Vector())") -or $location.Contains("std::make_pair(planetName, location)")) { throw "Group-pickup location is not normalized to empty." }

$setGroup = Get-BracedSurface $text["CreatureObject.cpp"] "void CreatureObject::setGroup(GroupObject *group, bool disbandingCurrentGroup)"
if ($setGroup.Contains("groupPickup")) { throw "Group join still recreates group-pickup state." }
$messageStart = $text["CreatureObject.cpp"].IndexOf('else if (message.getMethod() == "C++GroupPickupPointCreated")', [StringComparison]::Ordinal)
$messageEnd = $text["CreatureObject.cpp"].IndexOf('else if (message.getMethod() == "C++OccupyUnlockedSlotRsp")', $messageStart, [StringComparison]::Ordinal)
if ($messageStart -lt 0 -or $messageEnd -le $messageStart) { throw "Could not isolate group-pickup message compatibility branch." }
$message = $text["CreatureObject.cpp"].Substring($messageStart, $messageEnd - $messageStart)
if (-not $message.Contains("Ignored retired NGE") -or $message.Contains("createOrUpdateReusableWaypoint") -or $message.Contains("Unicode::tokenize")) { throw "Group-pickup message can still create a waypoint." }

$loaded = Get-BracedSurface $text["PlayerObject.cpp"] "void PlayerObject::onLoadedFromDatabase()"
foreach ($required in @("reuseableWp.groupPickupWp", "destroyWaypoint(waypointId)", "removeObjVarItem(retiredGroupPickupWaypointObjvar)"))
{
    if (-not $loaded.Contains($required)) { throw "Persisted group-pickup waypoint cleanup is incomplete: $required" }
}

foreach ($handler in @("OnAboutToTravelToGroupPickupPoint", "OnTravelToGroupPickupPoint"))
{
    $surface = Get-BracedSurface $text["player_travel.java"] "public int $handler"
    if (-not $surface.Contains("Ignored retired NGE") -or -not $surface.Contains("return SCRIPT_OVERRIDE;") -or $surface.Contains("movePlayerToDestination")) { throw "$handler does not fail closed." }
}
$travel = Get-BracedSurface $text["travel.java"] "public static boolean movePlayerToDestination(obj_id player, String planet, String point, boolean groupPickupPointTravel)"
if (([regex]::Matches($travel, "groupPickupPointTravel")).Count -ne 2 -or
    -not $travel.Contains("rejected retired NGE group-pickup travel") -or
    $travel.Contains("if (!groupPickupPointTravel)") -or
    -not $travel.Contains('warpPlayer(player, planet, arrival.x, arrival.y, arrival.z, null, 0.0f, 0.0f, 0.0f, "msgTravelComplete")'))
{
    throw "Shared travel library still exposes the group-pickup bypass."
}
foreach ($ordinary in @("isTravelBlocked(player, false)", "features.hasMustafarExpansionRetail(player)", "features.hasEpisode3Expansion(player)", "getPlanetTravelPointLocation(planet, point)"))
{
    if (-not $travel.Contains($ordinary)) { throw "Ordinary ticket/starport travel regression: $ordinary" }
}

$commandTablePath = Join-Path $root ($paths["command_table.tab"] -replace "/", "\")
$rows = @(Import-SwgTab -Path $commandTablePath | Where-Object { $_.commandName -in @("createGroupPickup", "useGroupPickup") })
if ($rows.Count -ne 2) { throw "Expected exactly two retained compatibility command rows." }
foreach ($row in $rows)
{
    if ([string]$row.disabled -ne "1" -or [string]$row.visible -eq "1") { throw "$($row.commandName) is not disabled and hidden." }
}

if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-nge-group-pickup-retirement.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.buildEvidence.cppCompile -ne "passed" -or
        $contract.buildEvidence.javaCompile -ne "passed" -or $contract.buildEvidence.architecture -ne "x86-64" -or
        $contract.runtimeEvidence.result -ne "passed" -or -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "NGE group-pickup retirement evidence is not ready."
    }
    foreach ($entry in $paths.GetEnumerator())
    {
        $path = Join-Path $root ($entry.Value -replace "/", "\")
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    foreach ($patchEntry in $contract.buildEvidence.overlayPatches.psobject.Properties)
    {
        $path = Join-Path $restorationRoot ([string]$patchEntry.Value.path)
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $actualBytes = (Get-Item -LiteralPath $path).Length
        if ($actualHash -ne [string]$patchEntry.Value.sha256 -or $actualBytes -ne [long]$patchEntry.Value.bytes) { throw "Patch evidence mismatch: $($patchEntry.Name)" }
    }
}

Write-Host "Publish 14.1 NGE group-pickup retirement contract passed."
