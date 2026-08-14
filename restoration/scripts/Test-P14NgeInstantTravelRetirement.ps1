[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$restorationRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-Slice([string]$Text, [string]$Start, [string]$Next)
{
    $a = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($a -lt 0) { return "" }
    $b = $Text.IndexOf($Next, $a + $Start.Length, [StringComparison]::Ordinal)
    if ($b -lt 0) { return $Text.Substring($a) }
    return $Text.Substring($a, $b - $a)
}

$dsrc = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$shared = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$nativePath = Join-Path $root "src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.cpp"
$travelPath = Join-Path $dsrc "library/travel.java"
$playerPath = Join-Path $dsrc "player/player_travel.java"
$surfacePaths = @(
    (Join-Path $dsrc "terminal/terminal_travel_instant.java"),
    (Join-Path $dsrc "terminal/terminal_travel_instant_one_use.java"),
    (Join-Path $dsrc "terminal/terminal_travel_instant_ttgm.java"),
    (Join-Path $dsrc "systems/tcg/tcg_instant_travel.java"),
    (Join-Path $dsrc "systems/veteran_reward/instant_travel_terminal_deed.java")
)

foreach ($path in @($nativePath, $travelPath, $playerPath, $shared) + $surfacePaths)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.instant-travel.source.$([IO.Path]::GetFileName($path))"
}

$native = Get-Content -LiteralPath $nativePath -Raw
$travel = Get-Content -LiteralPath $travelPath -Raw
$player = Get-Content -LiteralPath $playerPath -Raw
$purchase = Get-Slice $native "static void commandFuncPurchaseTicket(" "static void commandFuncPurchaseTicketResponse("
$instant = Get-Slice $travel "public static boolean instantTravel(" "public static boolean isTravelBlocked("
$instantDispatch = Get-Slice $player "public int OnPurchaseTicketInstantTravel(" "public int OnAboutToTravelToGroupPickupPoint("
$pickupAdmission = Get-Slice $player "public boolean canCallForPickup(" "public boolean spawnPickupCraft("
$pickupSpawn = Get-Slice $player "public boolean spawnPickupCraft(" "public int groupMemberLocationRequestHandler("

Assert-Contract ($purchase.Contains("instantTravel") -and
    $purchase.Contains("Scripting::TRIG_PURCHASE_TICKET_INSTANT_TRAVEL") -and
    $purchase.Contains("Scripting::TRIG_PURCHASE_TICKET")) `
    "p14.instant-travel.native-dispatch-script-authoritative"
Assert-Contract ($instant.Contains("planet1.equals(planet2)") -and
    $instant.Contains("callable.hasAnyCallable(player)") -and
    $instant.Contains("movePlayerToDestination(player, planet2, point2)")) `
    "p14.instant-travel.library-same-planet-guarded"
Assert-Contract ($instantDispatch.Contains("terminal_travel_instant_royal_ship.iff") -and
    $instantDispatch.Contains("playerOwner") -and
    $instantDispatch.Contains("travel.MAXIMUM_TERMINAL_DISTANCE") -and
    $instantDispatch.Contains("travel.instantTravel(") -and
    $instantDispatch.Contains("return SCRIPT_OVERRIDE;")) `
    "p14.instant-travel.player-dispatch-royal-only"
Assert-Contract ($pickupAdmission.Contains("Rejected retired NGE instant-travel pickup admission") -and
    $pickupAdmission.Contains("return false;")) `
    "p14.instant-travel.pickup-admission-retired"
Assert-Contract ($pickupSpawn.Contains("Rejected retired NGE instant-travel craft spawn") -and
    $pickupSpawn.Contains("return false;")) `
    "p14.instant-travel.pickup-spawn-retired"

$surfaceText = ($surfacePaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
foreach ($marker in @(
    "Ignored retired NGE instant-travel terminal menu request",
    "Ignored retired NGE one-use instant-travel menu request",
    "Ignored retired NGE teleport-to-group-member menu request",
    "Ignored retired NGE stationary instant-travel menu request",
    "Ignored retired NGE instant-travel deed menu request"
))
{
    Assert-Contract ($surfaceText.Contains($marker)) "p14.instant-travel.surface.$marker"
}

$lines = @(Get-Content -LiteralPath $shared)
$header = [regex]::Split($lines[0], "`t")
$disabledIndex = [array]::IndexOf($header, "disabled")
$rows = @{}
foreach ($line in $lines | Select-Object -Skip 2)
{
    if ([string]::IsNullOrEmpty($line)) { continue }
    $fields = [regex]::Split($line, "`t")
    $rows[$fields[0]] = $fields
}
foreach ($command in @("callforpickup", "callforprivateerpickup",
    "callforrattletrappickup", "callforsolarsailerpickup", "callforg9riggerpickup",
    "callforsnowspeeder", "callforslave1pickup"))
{
    Assert-Contract ($rows.ContainsKey($command) -and
        $rows[$command][$disabledIndex] -eq "1") "p14.instant-travel.command-disabled.$command"
}
Assert-Contract ($rows.ContainsKey("callforroyalpickup") -and
    $rows["callforroyalpickup"][$disabledIndex] -eq "0") `
    "p14.instant-travel.royal-itv-bounded-restoration"
Assert-Contract ($player.Contains("public boolean canCallForRoyalPickup(") -and
    $player.Contains("spawnRoyalPickupCraft(self);") -and
    $surfaceText.Contains("ROYAL_ITV_TEMPLATE") -and
    $surfaceText.Contains("enterClientTicketPurchaseMode(player, planet, travelPoint, true)")) `
    "p14.instant-travel.royal-itv-owner-interaction-restored"

Assert-Contract ($player.Contains("public int OnPurchaseTicket(") -and
    $purchase.Contains("Scripting::TRIG_PURCHASE_TICKET")) `
    "p14.instant-travel.normal-paid-ticket-path-retained"

if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
        "contracts/p14-nge-instant-travel-retirement.json") -Raw | ConvertFrom-Json
    Assert-Contract ($contract.status -eq "ready" -and
        $contract.buildEvidence.cppCompile -eq "passed" -and
        $contract.buildEvidence.javaBytecode -eq "passed" -and
        $contract.runtimeEvidence.serverHealthy -eq $true) `
        "p14.instant-travel.ready-evidence"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14 NGE instant-travel retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14 NGE instant-travel retirement contract passed."
