[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuQueuedBattlefieldRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$manifestDsrc = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$manifestSrc = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$indexedDsrcCommit = (& git -C $repositoryRoot rev-parse ":dsrc").Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the parent repository's indexed dsrc gitlink." }
$checkedOutDsrcCommit = (& git -C (Join-Path $repositoryRoot "dsrc") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out dsrc commit." }
$indexedSrcCommit = (& git -C $repositoryRoot rev-parse ":src").Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the parent repository's indexed src gitlink." }
$checkedOutSrcCommit = (& git -C (Join-Path $repositoryRoot "src") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out src commit." }

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

function Assert-RetiredEntrypoint(
    [string]$Text,
    [string]$Start,
    [string]$Next,
    [string]$RetireCall,
    [string]$Name)
{
    $slice = Get-FunctionSlice $Text $Start $Next
    $flagIndex = $slice.IndexOf("gcw.isPostNgeQueuedBattlefieldRetired()", [System.StringComparison]::Ordinal)
    $retireIndex = $slice.IndexOf($RetireCall, [System.StringComparison]::Ordinal)
    $returnIndex = $slice.IndexOf("return", [System.StringComparison]::Ordinal)
    Assert-Contract ($flagIndex -ge 0 -and $retireIndex -gt $flagIndex -and $returnIndex -gt $retireIndex) $Name
}

Assert-Contract ($manifestDsrc.Count -eq 1 -and
    [string]$manifestDsrc[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $indexedDsrcCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $checkedOutDsrcCommit -ceq [string]$contract.buildEvidence.directSourceCommit) `
    "p14.queued-battlefield.direct-source-commit-synchronized"
Assert-Contract ($manifestSrc.Count -eq 1 -and
    [string]$manifestSrc[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit -and
    $indexedSrcCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit -and
    $checkedOutSrcCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "p14.queued-battlefield.native-source-commit-synchronized"

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.queued-battlefield.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.queued-battlefield.overlay.authenticated"
}

$paths = [ordered]@{
    "script.library.gcw" = "dsrc/sku.0/sys.server/compiled/game/script/library/gcw.java"
    "script.player.base.base_player" = "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
    "script.player.live_conversions" = "dsrc/sku.0/sys.server/compiled/game/script/player/live_conversions.java"
    "script.systems.gcw.battlefield_terminal" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/battlefield_terminal.java"
    "script.systems.gcw.player_pvp" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/player_pvp.java"
    "script.systems.gcw.pvp_battlefield" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/pvp_battlefield.java"
    "template.gcw.battlefield_terminal" = "dsrc/sku.0/sys.server/compiled/game/object/tangible/gcw/battlefield_terminal.tpf"
    "template.gcw.battlefield_beacon" = "dsrc/sku.0/sys.server/compiled/game/object/tangible/gcw/battlefield_beacon.tpf"
    "script.terminal.terminal_gcw_publish_gift" = "dsrc/sku.0/sys.server/compiled/game/script/terminal/terminal_gcw_publish_gift.java"
    "buildout.endor_1_1" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/endor/endor_1_1.tab"
    "buildout.endor_1_8" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/endor/endor_1_8.tab"
    "buildout.yavin4_3_1" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/yavin4/yavin4_3_1.tab"
    "buildout.yavin4_5_5" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/yavin4/yavin4_5_5.tab"
    "retained.library.battlefield" = "dsrc/sku.0/sys.server/compiled/game/script/library/battlefield.java"
    "retained.systems.battlefield.region" = "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/battlefield_region.java"
    "retained.systems.battlefield.player" = "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/player_battlefield.java"
    "retained.table.battlefield" = "dsrc/sku.0/sys.server/compiled/game/datatables/battlefield/battlefield.tab"
    "retained.factions" = "dsrc/sku.0/sys.server/compiled/game/script/library/factions.java"
    "retained.mission_terminal" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_terminal.java"
    "retained.mission_base" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = Join-Path $source $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.queued-battlefield.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) "p14.queued-battlefield.source.$name.authenticated"
    }
}

$gcw = [string]$texts["script.library.gcw"]
$controller = [string]$texts["script.systems.gcw.pvp_battlefield"]
$terminal = [string]$texts["script.systems.gcw.battlefield_terminal"]
$playerPvp = [string]$texts["script.systems.gcw.player_pvp"]
$battlefieldTerminalTemplate = [string]$texts["template.gcw.battlefield_terminal"]
$battlefieldBeaconTemplate = [string]$texts["template.gcw.battlefield_beacon"]
$warTerminal = [string]$texts["script.terminal.terminal_gcw_publish_gift"]
$conversions = [string]$texts["script.player.live_conversions"]
$basePlayer = [string]$texts["script.player.base.base_player"]

$retiredFlag = Get-FunctionSlice $gcw `
    "public static boolean isPostNgeQueuedBattlefieldRetired()" `
    "public static final String GCW_TUTORIAL_FLAG"
Assert-Contract ($retiredFlag.Contains("Game Update 10") -and
    $retiredFlag.Contains("older open-world") -and $retiredFlag.Contains("return true;")) `
    "p14.queued-battlefield.authoritative-retirement-flag"

$controllerRetire = Get-FunctionSlice $controller `
    "private void retirePostNgeQueuedBattlefield" `
    "public void doLogging"
$controllerCleanup = @(
    "bfActiveKickOutPlayers(controller)", "bfQueueClear(controller)",
    'removeClusterWideData("pvp", battlefieldName, 0)',
    "gcw.getBattlefieldRegionName(controller)", "gcw.getPushbackRegionName(controller)",
    "utils.removeBatchScriptVar(controller, PVP_AREA_RECORD)",
    'utils.removeScriptVarTree(controller, "battlefield")', "detachScript(controller, SCRIPT_NAME)"
)
Assert-Contract (@($controllerCleanup | Where-Object { -not $controllerRetire.Contains($_) }).Count -eq 0) `
    "p14.queued-battlefield.persisted-controller-cleans-queue-regions-state-and-detaches"
$controllerHandlers = [ordered]@{
    OnClusterWideDataResponse = @("public int OnClusterWideDataResponse", "public int OnAttach")
    OnAttach = @("public int OnAttach", "public int OnInitialize")
    OnInitialize = @("public int OnInitialize", "public int checkBattlefieldState")
    checkBattlefieldState = @("public int checkBattlefieldState", "public void bfUpdateQueue")
}
foreach ($name in $controllerHandlers.Keys)
{
    $markers = $controllerHandlers[$name]
    Assert-RetiredEntrypoint $controller $markers[0] $markers[1] `
        "retirePostNgeQueuedBattlefield(self);" "p14.queued-battlefield.controller-entrypoint.$name.retired"
}

$terminalRetire = Get-FunctionSlice $terminal `
    "private void retirePostNgeQueuedBattlefieldTerminal" `
    "public void blog"
Assert-Contract ($terminalRetire.Contains('utils.removeScriptVarTree(self, "battlefield")') -and
    $terminalRetire.Contains('utils.removeScriptVarTree(self, "gcw.static_base.control_terminal")') -and
    $terminalRetire.Contains("detachScript(self, SCRIPT_NAME)")) `
    "p14.queued-battlefield.persisted-terminal-cleans-and-detaches"
$terminalHandlers = [ordered]@{
    OnAttach = @("public int OnAttach", "public int OnInitialize")
    OnInitialize = @("public int OnInitialize", "public int OnHearSpeech")
    OnHearSpeech = @("public int OnHearSpeech", "public int registerTerminal")
    registerTerminal = @("public int registerTerminal", "public void registerTerminalWithController")
    OnObjectMenuRequest = @("public int OnObjectMenuRequest", "public int OnObjectMenuSelect")
    OnObjectMenuSelect = @("public int OnObjectMenuSelect", "public obj_id getLocalBattlefieldController")
}
foreach ($name in $terminalHandlers.Keys)
{
    $markers = $terminalHandlers[$name]
    Assert-RetiredEntrypoint $terminal $markers[0] $markers[1] `
        "retirePostNgeQueuedBattlefieldTerminal(self);" "p14.queued-battlefield.terminal-entrypoint.$name.retired"
}

$playerRetire = Get-FunctionSlice $playerPvp `
    "private void retirePostNgeQueuedBattlefieldPlayer" `
    "public void blog"
Assert-Contract ($playerRetire.Contains('buff.removeBuff(self, "battlefield_communication_run")') -and
    $playerRetire.Contains('buff.removeBuff(self, "battlefield_radar_invisibility")') -and
    $playerRetire.Contains('utils.removeScriptVarTree(self, "battlefield")') -and
    $playerRetire.Contains("detachScript(self, SCRIPT_NAME)")) `
    "p14.queued-battlefield.persisted-player-cleans-and-detaches"
$playerHandlers = [ordered]@{
    OnSpeaking = @("public int OnSpeaking", "public int OnAttach")
    OnAttach = @("public int OnAttach", "public int OnLogin")
    OnLogin = @("public int OnLogin", "public int OnEnteredCombat")
    OnInitialize = @("public int OnInitialize", "public int OnDetach")
    cmdBattlefield = @("public int cmdBattlefield", "public int displayBattlefieldSui")
    displayBattlefieldSui = @("public int displayBattlefieldSui", "public void battlefieldCommandSui")
    battlefieldCommandSui = @("public void battlefieldCommandSui", "public int handleBattlefieldSui")
}
foreach ($name in $playerHandlers.Keys)
{
    $markers = $playerHandlers[$name]
    Assert-RetiredEntrypoint $playerPvp $markers[0] $markers[1] `
        "retirePostNgeQueuedBattlefieldPlayer(self);" "p14.queued-battlefield.player-entrypoint.$name.retired"
}

$warTerminalRetire = Get-FunctionSlice $warTerminal `
    "private void retirePostNgeWarTerminalState" `
    "public int OnObjectMenuRequest"
$warTerminalMenuRequest = Get-FunctionSlice $warTerminal `
    "public int OnObjectMenuRequest" `
    "public int OnObjectMenuSelect"
$warTerminalMenuSelect = Get-FunctionSlice $warTerminal `
    "public int OnObjectMenuSelect" `
    "public int OnClusterWideDataResponse"
$warTerminalStaleSelection = Get-FunctionSlice $warTerminal `
    "else if (item == menu_info_types.SERVER_MENU1 || item == menu_info_types.SERVER_MENU3)" `
    "else if (item == menu_info_types.SERVER_MENU2)"
Assert-Contract ($warTerminalRetire.Contains("action == menu_info_types.SERVER_MENU1 || action == menu_info_types.SERVER_MENU3") -and
    $warTerminalRetire.Contains('removeObjVar(self, "gcwWarIntelPadMostRecentAction")') -and
    -not $warTerminalMenuRequest.Contains("menu_info_types.SERVER_MENU1") -and
    $warTerminalStaleSelection.Contains("retirePostNgeWarTerminalState(self, player);") -and
    $warTerminalStaleSelection.Contains("return SCRIPT_CONTINUE;") -and
    -not $warTerminal.Contains("displayBattlefieldSui") -and
    -not [bool]$contract.expected.warTerminalQueueMenuReachable -and
    [bool]$contract.expected.staleWarIntelpadQueueActionScrubbed) `
    "p14.queued-battlefield.war-terminal-queue-action-retired"
Assert-Contract ($warTerminalMenuRequest.Contains("SERVER_MENU6, SID_MENU_GCW_REPORT") -and
    $warTerminalMenuSelect.Contains("openSui(player);") -and
    [bool]$contract.expected.warTerminalReportPreserved) `
    "p14.queued-battlefield.war-terminal-report-preserved"

$addPlayerScripts = Get-FunctionSlice $conversions "public void addPlayerScripts" "public void addPlayerCommandScripts"
Assert-Contract ($addPlayerScripts.Contains("gcw.isPostNgeQueuedBattlefieldRetired()") -and
    $addPlayerScripts.Contains('detachScript(player, "systems.gcw.player_pvp")') -and
    $addPlayerScripts.Contains('utils.removeScriptVarTree(player, "battlefield")') -and
    $addPlayerScripts.Contains('else if (!hasScript(player, "systems.gcw.player_pvp"))')) `
    "p14.queued-battlefield.live-conversion-does-not-attach-later-player-script"

$baseRetire = Get-FunctionSlice $basePlayer `
    "private void retirePostNgeQueuedBattlefieldPlayerState" `
    "public static final int TIME_DEATH"
$login = Get-FunctionSlice $basePlayer "public int OnLogin" "public int handleLoginLocResolved"
$logout = Get-FunctionSlice $basePlayer "public int OnLogout" "public int handleLogout"
$revive = Get-FunctionSlice $basePlayer "public int handlePlayerRevive" "public int handlePlayerResuscitated"
$enterRegion = Get-FunctionSlice $basePlayer "public int OnEnterRegion" "public int OnExitRegion"
$exitRegion = Get-FunctionSlice $basePlayer "public int OnExitRegion" "public int handlePvpRegionExit"
Assert-Contract ($baseRetire.Contains('detachScript(self, "systems.gcw.player_pvp")') -and
    $login.Contains("retirePostNgeQueuedBattlefieldPlayerState(self)") -and
    $logout.Contains("retirePostNgeQueuedBattlefieldPlayerState(self)")) `
    "p14.queued-battlefield.base-player-login-logout-cleans-persisted-state"
Assert-Contract ($basePlayer.Contains('if (!gcw.isPostNgeQueuedBattlefieldRetired() && isIdValid(controller) && exists(controller))') -and
    $revive.Contains('(!gcw.isPostNgeQueuedBattlefieldRetired() && utils.hasScriptVar(self, "battlefield.active"))')) `
    "p14.queued-battlefield.clone-override-and-delay-unreachable"
foreach ($regionCase in @($enterRegion, $exitRegion))
{
    Assert-Contract ($regionCase.Contains("gcw.isPostNgeQueuedBattlefieldRetired()") -and
        $regionCase.Contains("regionName.startsWith(gcw.PVP_BATTLEFIELD_REGION)") -and
        $regionCase.Contains("regionName.startsWith(gcw.PVP_PUSHBACK_REGION)") -and
        $regionCase.Contains("retirePostNgeQueuedBattlefieldPlayerState(self)") -and
        $regionCase.Contains("return SCRIPT_CONTINUE;")) `
        "p14.queued-battlefield.region-boundary.$([array]::IndexOf(@($enterRegion, $exitRegion), $regionCase)).fail-closed"
}

$buildoutExpectations = [ordered]@{
    "buildout.endor_1_1" = 5
    "buildout.endor_1_8" = 2
    "buildout.yavin4_3_1" = 7
    "buildout.yavin4_5_5" = 6
}
foreach ($name in $buildoutExpectations.Keys)
{
    $rows = @(([string]$texts[$name] -split "`r?`n") | Where-Object { $_ -match "battlefieldName|terminalName" })
    $badScripts = @($rows | Where-Object {
        $columns = $_.Split("`t", [System.StringSplitOptions]::None)
        $columns.Count -lt 13 -or $columns[11].Length -ne 0
    })
    Assert-Contract ($rows.Count -eq [int]$buildoutExpectations[$name] -and $badScripts.Count -eq 0 -and
        -not ([string]$texts[$name]).Contains("systems.gcw.pvp_battlefield") -and
        -not ([string]$texts[$name]).Contains("systems.gcw.battlefield_terminal")) `
        "p14.queued-battlefield.buildout.$name.scripts-detached-scenery-retained"
}

Assert-Contract ($battlefieldTerminalTemplate.Contains('sharedTemplate = "object/tangible/gcw/shared_battlefield_terminal.iff"') -and
    [regex]::IsMatch($battlefieldTerminalTemplate, '(?m)^scripts\s*=\s*\+\s*\[\s*\]\s*$') -and
    -not $battlefieldTerminalTemplate.Contains("systems.gcw.battlefield_terminal") -and
    -not [bool]$contract.expected.captureTerminalTemplateScriptsAttached) `
    "p14.queued-battlefield.capture-terminal-template-controller-detached"
Assert-Contract ($battlefieldBeaconTemplate.Contains('sharedTemplate = "object/tangible/gcw/shared_battlefield_beacon.iff"') -and
    [regex]::IsMatch($battlefieldBeaconTemplate, '(?m)^scripts\s*=\s*\+\s*\[\s*\]\s*$') -and
    -not $battlefieldBeaconTemplate.Contains("systems.gcw.battlefield_terminal") -and
    -not [bool]$contract.expected.battlefieldBeaconTemplateScriptsAttached) `
    "p14.queued-battlefield.beacon-template-controller-detached"

$openWorldLibrary = [string]$texts["retained.library.battlefield"]
$openWorldRegion = [string]$texts["retained.systems.battlefield.region"]
$openWorldPlayer = [string]$texts["retained.systems.battlefield.player"]
$openWorldTable = [string]$texts["retained.table.battlefield"]
$factions = [string]$texts["retained.factions"]
$missionTerminal = [string]$texts["retained.mission_terminal"]
$missionBase = [string]$texts["retained.mission_base"]
Assert-Contract ($openWorldLibrary.Contains('SCRIPT_BATTLEFIELD_REGION = "systems.battlefield.battlefield_region"') -and
    $openWorldRegion.Contains("OnTriggerVolumeEntered") -and
    $openWorldPlayer.Contains("factions.addFactionStanding") -and
    $openWorldTable.Contains("two_fortresses")) `
    "p14.queued-battlefield.precu-open-world-battlefield-and-standing-retained"
Assert-Contract ($factions.Contains("awardPrecuNpcCombatFaction") -and
    $missionTerminal.Contains("menu_info_types.MISSION_TERMINAL_LIST") -and
    $missionBase.Contains("MAX_MISSIONS = 10") -and
    $missionBase.Contains("fullRewardEach=") -and $missionBase.Contains("split=false dailyCashPenalty=false")) `
    "p14.queued-battlefield.faction-and-mission-authority-retained"

$patchText = if (Test-Path -LiteralPath $patchPath) { Get-Content -LiteralPath $patchPath -Raw } else { "" }
Assert-Contract (-not $patchText.Contains("script/systems/battlefield/") -and
    -not $patchText.Contains("datatables/battlefield/") -and
    -not $patchText.Contains("script/systems/missions/")) `
    "p14.queued-battlefield.open-world-battlefield-and-missions-untouched-by-overlay"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) `
    "p14.queued-battlefield.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU queued-battlefield retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU queued-battlefield retirement passed."
