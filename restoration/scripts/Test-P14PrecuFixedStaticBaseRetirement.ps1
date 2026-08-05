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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuFixedStaticBaseRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

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

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.fixed-static-base.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.fixed-static-base.overlay.authenticated"
}

$paths = [ordered]@{
    "script.library.gcw" = "dsrc/sku.0/sys.server/compiled/game/script/library/gcw.java"
    "script.player.player_faction" = "dsrc/sku.0/sys.server/compiled/game/script/player/player_faction.java"
    "script.static.master" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/static_base/master.java"
    "script.static.base_master" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/static_base/base_master.java"
    "script.static.base_spawner" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/static_base/base_spawner.java"
    "script.static.spawned_object" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/static_base/spawned_object.java"
    "script.static.control_terminal" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/static_base/control_terminal.java"
    "script.static.control_terminal_player" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/static_base/control_terminal_player.java"
    "script.structure.starport" = "dsrc/sku.0/sys.server/compiled/game/script/structure/municipal/starport.java"
    "script.structure.cloning_facility" = "dsrc/sku.0/sys.server/compiled/game/script/structure/municipal/cloning_facility.java"
    "script.collections.consume_click" = "dsrc/sku.0/sys.server/compiled/game/script/systems/collections/consume_click.java"
    "buildout.corellia_7_2" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/corellia/corellia_7_2.tab"
    "buildout.talus_2_3" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_2_3.tab"
    "buildout.naboo_5_4" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/naboo/naboo_5_4.tab"
    "retained.library.hq" = "dsrc/sku.0/sys.server/compiled/game/script/library/hq.java"
    "retained.hq.loader" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/loader.java"
    "retained.hq.terminal" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/terminal.java"
    "retained.hq.objective_power" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_power_regulator.java"
    "retained.hq.objective_security" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_terminal_security.java"
    "retained.hq.objective_override" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_terminal_override.java"
    "retained.hq.objective_uplink" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_terminal_uplink.java"
    "retained.factions" = "dsrc/sku.0/sys.server/compiled/game/script/library/factions.java"
    "retained.battlefield.player" = "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/player_battlefield.java"
    "retained.mission_terminal" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_terminal.java"
    "retained.mission_base" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
    "retained.table.static_corellia" = "dsrc/sku.0/sys.server/compiled/game/datatables/gcw/static_base/base_spawn_corellia.tab"
    "retained.table.static_talus" = "dsrc/sku.0/sys.server/compiled/game/datatables/gcw/static_base/base_spawn_talus.tab"
    "retained.table.static_naboo" = "dsrc/sku.0/sys.server/compiled/game/datatables/gcw/static_base/base_spawn_naboo.tab"
    "retained.table.static_terminals" = "dsrc/sku.0/sys.server/compiled/game/datatables/gcw/static_base/terminal_spawn.tab"
    "retained.template.faction_hq_base" = "dsrc/sku.0/sys.server/compiled/game/object/building/faction_perk/hq/base/factional_hq_base.tpf"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = Join-Path $source $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.fixed-static-base.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) "p14.fixed-static-base.source.$name.authenticated"
    }
}

$gcw = [string]$texts["script.library.gcw"]
$flag = Get-FunctionSlice $gcw "public static boolean isPostNgeFixedStaticBaseRetired()" "public static final String GCW_TUTORIAL_FLAG"
Assert-Contract ($flag.Contains("Chapter 2") -and $flag.Contains("player-placed faction headquarters") -and
    $flag.Contains("return true;")) "p14.fixed-static-base.authoritative-retirement-flag"
$gcwFunctions = [ordered]@{
    getPub30StaticBaseControllerId = "return obj_id.NULL_ID;"
    getPub30StaticBaseControllingFaction = "return NO_CONTROL;"
    getPub30StaticBaseTimeSinceLastCapture = "return -1;"
    setPub30StaticBaseTimeSinceLastCapture = "return;"
    getPub30StaticBaseCapturePhase = "return 0;"
    getPub30TimeToNextPhaseInt = "return -1;"
    advancePub30StaticBaseCapturePhase = "return 0;"
    regressPub30StaticBaseCapturePhase = "return 0;"
}
foreach ($functionName in $gcwFunctions.Keys)
{
    $pattern = "(?s)public static [^{]+\b$functionName\s*\([^)]*\).*?\{.*?if \(isPostNgeFixedStaticBaseRetired\(\)\).*?" + [regex]::Escape($gcwFunctions[$functionName])
    Assert-Contract ([regex]::IsMatch($gcw, $pattern)) "p14.fixed-static-base.gcw.$functionName.fail-closed"
}

$playerFaction = [string]$texts["script.player.player_faction"]
$playerCleanup = Get-FunctionSlice $playerFaction "public void cleanupRetiredFixedStaticBaseState" "public int OnAttach"
Assert-Contract ($playerCleanup.Contains('String[] planets = {"corellia", "talus", "naboo"}') -and
    $playerCleanup.Contains('destroyWaypointInDatapad') -and $playerCleanup.Contains('removeObjVar(self, waypointVar)') -and
    $playerCleanup.Contains('utils.removeScriptVarTree(self, "gcw.static_base")')) `
    "p14.fixed-static-base.player-waypoints-and-state-cleaned"
foreach ($entrypoint in @("OnAttach", "OnInitialize", "OnLogin"))
{
    Assert-Contract ([regex]::IsMatch($playerFaction, "(?s)public int $entrypoint\([^}]+cleanupRetiredFixedStaticBaseState\(self\)")) `
        "p14.fixed-static-base.player-entrypoint.$entrypoint.cleans"
}
$enterRegion = Get-FunctionSlice $playerFaction "public int OnEnterRegion" "public int OnExitRegion"
Assert-Contract ($enterRegion.Contains("gcw.isPostNgeFixedStaticBaseRetired()") -and
    $enterRegion.Contains("cleanupRetiredFixedStaticBaseState(self)") -and $enterRegion.Contains("return SCRIPT_CONTINUE;")) `
    "p14.fixed-static-base.player-region-trigger-inert"

$staticRequirements = [ordered]@{
    "script.static.master" = @("cleanupRetiredFixedStaticBase", 'removeObjVar(self, "gcw.static_base")', 'detachScript(self, "systems.gcw.static_base.master")')
    "script.static.base_master" = @("cleanupRetiredFixedStaticBase", "removePlanetaryMapLocation(terminal)", "destroyObject(terminal)", 'detachScript(self, "systems.gcw.static_base.base_master")')
    "script.static.base_spawner" = @("cleanupRetiredFixedStaticBaseSpawns", "destroyObject(spawned)", 'removeObjVar(self, SPAWNED_LIST)', 'detachScript(self, "systems.gcw.static_base.base_spawner")')
    "script.static.spawned_object" = @("cleanupRetiredFixedStaticBaseSpawn", 'detachScript(self, "systems.gcw.static_base.spawned_object")', "destroyObject(self)")
    "script.static.control_terminal" = @("cleanupRetiredFixedStaticBaseTerminal", "removePlanetaryMapLocation(self)", "destroyObject(icon)", 'detachScript(self, "systems.gcw.static_base.control_terminal")', "destroyObject(self)")
    "script.static.control_terminal_player" = @("cleanupRetiredFixedStaticBaseCapture", 'utils.removeScriptVarTree(self, "gcw.static_base.control_terminal")', 'detachScript(self, "systems.gcw.static_base.control_terminal_player")')
}
foreach ($name in $staticRequirements.Keys)
{
    $text = [string]$texts[$name]
    $missing = @($staticRequirements[$name] | Where-Object { -not $text.Contains($_) })
    Assert-Contract ($text.Contains("gcw.isPostNgeFixedStaticBaseRetired()") -and $missing.Count -eq 0) `
        "p14.fixed-static-base.persisted.$name.cleans-and-retires"
}

$starport = [string]$texts["script.structure.starport"]
$cloner = [string]$texts["script.structure.cloning_facility"]
$collection = [string]$texts["script.collections.consume_click"]
Assert-Contract ($starport.Contains('"object/tangible/gcw/static_base/invisible_beacon.iff".equals(getTemplateName(self))') -and
    $starport.Contains("travel.removeTravelPoint(self)") -and $starport.Contains('detachScript(self, "structure.municipal.starport")')) `
    "p14.fixed-static-base.generic-starport-cleanup-exact-template-scoped"
Assert-Contract ($cloner.Contains('template.startsWith("object/tangible/gcw/static_base/invisible_cloner_")') -and
    $cloner.Contains("structure.destroyStructureTerminals(self)") -and $cloner.Contains("detachScript(self, SCRIPT_CLONING_FACILITY)")) `
    "p14.fixed-static-base.generic-cloner-cleanup-template-scoped"
Assert-Contract ($collection.Contains('template.startsWith("object/tangible/collection/col_gcw_static_base_")') -and
    $collection.Contains('detachScript(self, "systems.collections.consume_click")')) `
    "p14.fixed-static-base.generic-collection-cleanup-template-scoped"

$buildoutIds = [ordered]@{
    "buildout.corellia_7_2" = @("-1950861366", "-1861947162", "-1704050194", "-1583793873", "-1043449019", "-899991077", "-485623403")
    "buildout.talus_2_3" = @("-2064109315", "-1916708911", "-1610009447", "-1839426456", "-1682065689", "-376575756", "-336486068")
    "buildout.naboo_5_4" = @("-1946025983", "-949623093", "-1925852435", "-1288314132", "-1202557081", "-1156051021", "-859124609")
}
$pvpRegionWatcherIds = [ordered]@{
    "buildout.corellia_7_2" = "-537065502"
    "buildout.talus_2_3" = "-1324255298"
    "buildout.naboo_5_4" = "-529152824"
}
$bunkerPortalCrc = [ordered]@{
    "-899991077" = "portalProperty.crc|0|1682376097|$|"
    "-1916708911" = "portalProperty.crc|0|-2111613717|$|"
    "-1946025983" = "portalProperty.crc|0|-1266970242|$|"
}
foreach ($name in $buildoutIds.Keys)
{
    $lines = @(([string]$texts[$name]) -split "`r?`n")
    $valid = $true
    foreach ($id in $buildoutIds[$name])
    {
        $matches = @($lines | Where-Object { $_.StartsWith($id + "`t", [System.StringComparison]::Ordinal) })
        if ($matches.Count -ne 1) { $valid = $false; continue }
        $columns = $matches[0].Split("`t", [System.StringSplitOptions]::None)
        if ($columns.Count -lt 13 -or $columns[11].Length -ne 0) { $valid = $false; continue }
        if ($bunkerPortalCrc.Contains($id))
        {
            if ($columns[12] -cne [string]$bunkerPortalCrc[$id]) { $valid = $false }
        }
        elseif ($columns[12] -cne '$|') { $valid = $false }
    }
    $text = [string]$texts[$name]
    Assert-Contract ($valid -and -not $text.Contains("systems.gcw.static_base") -and
        -not $text.Contains("gcw.static_base.master") -and -not $text.Contains("collection.gcw_control_check")) `
        "p14.fixed-static-base.$name.seven-rows-inert-scenery-retained"

    $watcherRows = @($lines | Where-Object { $_.StartsWith([string]$pvpRegionWatcherIds[$name] + "`t", [System.StringComparison]::Ordinal) })
    $watcherValid = $watcherRows.Count -eq 1
    if ($watcherValid)
    {
        $watcherColumns = $watcherRows[0].Split("`t", [System.StringSplitOptions]::None)
        $watcherValid = $watcherColumns.Count -eq 13 -and
            $watcherColumns[2] -ceq "object/tangible/gcw/pvp_region_watcher.iff" -and
            $watcherColumns[11].Length -eq 0
    }
    Assert-Contract ($watcherValid -and
        -not [bool]$contract.expected.coLocatedPvpRegionWatcherScriptsAttached) `
        "p14.fixed-static-base.$name.pvp-region-watcher-inert-scenery-retained"
}
Assert-Contract ([int]$contract.expected.coLocatedPvpRegionWatcherSceneryPreserved -eq 3) `
    "p14.fixed-static-base.pvp-region-watcher-scenery-count"

$hqLibrary = [string]$texts["retained.library.hq"]
$hqLoader = [string]$texts["retained.hq.loader"]
$hqTerminal = [string]$texts["retained.hq.terminal"]
$hqTemplate = [string]$texts["retained.template.faction_hq_base"]
$battlefieldPlayer = [string]$texts["retained.battlefield.player"]
$missionTerminal = [string]$texts["retained.mission_terminal"]
$missionBase = [string]$texts["retained.mission_base"]
Assert-Contract ($hqLibrary.Contains('public static final String VAR_HQ_BASE = "hq"') -and
    $hqLibrary.Contains('public static final String[] OBJECTIVE_TEMPLATE') -and
    $hqLoader.Contains("public int OnAttach") -and $hqTerminal.Contains("public int OnObjectMenuRequest") -and
    $hqTemplate.Contains("shared_factional_hq_base.iff")) `
    "p14.fixed-static-base.player-placed-faction-headquarters-retained"
Assert-Contract ($battlefieldPlayer.Contains("factions.addFactionStanding") -and
    $missionTerminal.Contains("menu_info_types.MISSION_TERMINAL_LIST") -and
    $missionBase.Contains("MAX_MISSIONS = 10") -and $missionBase.Contains("fullRewardEach=") -and
    $missionBase.Contains("split=false dailyCashPenalty=false")) `
    "p14.fixed-static-base.open-world-battlefield-and-missions-retained"

$patchText = if (Test-Path -LiteralPath $patchPath) { Get-Content -LiteralPath $patchPath -Raw } else { "" }
$diffTargets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') | ForEach-Object { $_.Groups[1].Value })
$expectedTargets = @($contract.sourceFiles | ForEach-Object { ([string]$_).Substring(5) })
Assert-Contract (($diffTargets -join "`n") -ceq ($expectedTargets -join "`n")) `
    "p14.fixed-static-base.overlay-targets-exactly-bounded"
Assert-Contract (-not [regex]::IsMatch($patchText,
    '(?m)^diff --git a/(?:.*script/faction_perk/hq/|.*script/library/hq\.java|.*script/systems/battlefield/|.*script/systems/missions/|.*datatables/gcw/static_base/)')) `
    "p14.fixed-static-base.hq-battlefield-mission-and-dormant-tables-untouched-by-overlay"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) `
    "p14.fixed-static-base.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU fixed-static-base retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU fixed-static-base retirement passed."
