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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuCityInvasionRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$manifestDsrc = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$indexedDsrcCommit = (& git -C $repositoryRoot rev-parse ":dsrc").Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the parent repository's indexed dsrc gitlink." }
$checkedOutDsrcCommit = (& git -C (Join-Path $repositoryRoot "dsrc") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to resolve the checked-out dsrc commit." }
$lf = [char]10

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

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha.Dispose()
    }
}

Assert-Contract ($manifestDsrc.Count -eq 1 -and
    [string]$manifestDsrc[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $indexedDsrcCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $checkedOutDsrcCommit -ceq [string]$contract.buildEvidence.directSourceCommit) `
    "p14.city-invasion.direct-source-commit-synchronized"

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.city-invasion.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.city-invasion.overlay.authenticated"
}

$paths = [ordered]@{
    "script.library.gcw" = "dsrc/sku.0/sys.server/compiled/game/script/library/gcw.java"
    "script.systems.gcw.gcw_city" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/gcw_city.java"
    "script.planet.planet_base" = "dsrc/sku.0/sys.server/compiled/game/script/planet/planet_base.java"
    "script.player.base.base_player" = "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
    "buildout.tatooine_4_3" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/tatooine/tatooine_4_3.tab"
    "buildout.talus_5_3" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/talus/talus_5_3.tab"
    "buildout.naboo_5_6" = "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/naboo/naboo_5_6.tab"
    "retained.mission_terminal" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_terminal.java"
    "retained.mission_base" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
    "retained.battlefield_library" = "dsrc/sku.0/sys.server/compiled/game/script/library/battlefield.java"
    "retained.battlefield_player" = "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/player_battlefield.java"
    "retained.factions" = "dsrc/sku.0/sys.server/compiled/game/script/library/factions.java"
    "retained.gcw_city_kit" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/gcw_city_kit.java"
    "retained.gcw_city_bestine" = "dsrc/sku.0/sys.server/compiled/game/datatables/gcw/gcw_city_bestine.tab"
    "retained.gcw_city_dearic" = "dsrc/sku.0/sys.server/compiled/game/datatables/gcw/gcw_city_dearic.tab"
    "retained.gcw_city_keren" = "dsrc/sku.0/sys.server/compiled/game/datatables/gcw/gcw_city_keren.tab"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = Join-Path $source $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.city-invasion.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) "p14.city-invasion.source.$name.authenticated"
    }
}

$extensionTargets = @($contract.directSourceExtensions | ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract ($extensionTargets.Count -eq [int]$contract.expected.cityAssetTemplatesPreserved -and
    (Get-TextSha256 (($extensionTargets -join $lf) + $lf)) -ceq [string]$contract.buildEvidence.sourceExtensionSetSha256) `
    "p14.city-invasion.template-source-set.authenticated"
$extensionTexts = @{}
$extensionContentRecords = ""
foreach ($relativePath in $extensionTargets)
{
    $path = Join-Path $source $relativePath
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.city-invasion.template.$relativePath.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $extensionContentRecords += "$relativePath=$hash$lf"
        $extensionTexts[$relativePath] = Get-Content -LiteralPath $path -Raw
    }
}
Assert-Contract ((Get-TextSha256 $extensionContentRecords) -ceq [string]$contract.buildEvidence.sourceExtensionContentSha256) `
    "p14.city-invasion.template-source-content.authenticated"

$cityControllerPattern = '(?m)^\s*scripts\s*=.*systems\.gcw\.(?:gcw_city_kit|gcw_barricade|gcw_patrol|gcw_tower|gcw_vehicle|gcw_camp)'
$emptyTemplatePattern = '(?m)^\s*scripts\s*=\s*\+?\s*\[\s*\]\s*$'
$cityControllerTemplates = @($extensionTargets | Where-Object { [regex]::IsMatch([string]$extensionTexts[$_], $cityControllerPattern) })
$inertTemplates = @($extensionTargets | Where-Object { [regex]::IsMatch([string]$extensionTexts[$_], $emptyTemplatePattern) })
$killCreditTemplates = @($extensionTargets | Where-Object { ([string]$extensionTexts[$_]).Contains("systems.combat.credit_for_kills") })
$campTemplates = @($extensionTargets | Where-Object { ([string]$extensionTexts[$_]).Contains("item.camp.camp_advanced") })
Assert-Contract ($cityControllerTemplates.Count -eq 0 -and
    -not [bool]$contract.expected.cityAssetTemplateControllerScriptsAttached) `
    "p14.city-invasion.template-controllers-detached"
Assert-Contract ($inertTemplates.Count -eq [int]$contract.expected.inertCityAssetTemplates) `
    "p14.city-invasion.inert-template-count"
Assert-Contract ($killCreditTemplates.Count -eq [int]$contract.expected.destructibleKillCreditScriptsPreserved -and
    @($killCreditTemplates | Where-Object { -not ([string]$extensionTexts[$_]).Contains("systems.gcw.gcw_barricade") }).Count -eq $killCreditTemplates.Count) `
    "p14.city-invasion.destructible-kill-credit-scripts-preserved"
Assert-Contract ($campTemplates.Count -eq [int]$contract.expected.genericCampScriptsPreserved -and
    @($campTemplates | Where-Object { -not ([string]$extensionTexts[$_]).Contains("systems.gcw.gcw_camp") }).Count -eq $campTemplates.Count) `
    "p14.city-invasion.generic-camp-script-preserved"

$compiledExpectedTargets = @($extensionTargets | ForEach-Object {
    (($_ -replace '^dsrc/sku\.0/sys\.server/compiled/game/', '') -replace '\.tpf$', '.iff')
})
$compiledProperties = @($contract.buildEvidence.compiledTemplateSha256.PSObject.Properties | Sort-Object Name)
$compiledEvidenceTargets = @($compiledProperties | ForEach-Object { [string]$_.Name })
$compiledContentRecords = ""
foreach ($property in $compiledProperties)
{
    $compiledContentRecords += "$([string]$property.Name)=$([string]$property.Value)$lf"
}
Assert-Contract ($compiledEvidenceTargets.Count -eq [int]$contract.expected.cityAssetTemplatesPreserved -and
    ($compiledExpectedTargets -join $lf) -ceq ($compiledEvidenceTargets -join $lf) -and
    (Get-TextSha256 (($compiledEvidenceTargets -join $lf) + $lf)) -ceq [string]$contract.buildEvidence.compiledTemplateSetSha256 -and
    (Get-TextSha256 $compiledContentRecords) -ceq [string]$contract.buildEvidence.compiledTemplateContentSha256) `
    "p14.city-invasion.compiled-template-evidence-authenticated"
Assert-Contract ([int]$contract.buildEvidence.compiledTemplateControllerStrings -eq 0 -and
    [int]$contract.buildEvidence.compiledGenericCampScriptsPreserved -eq [int]$contract.expected.genericCampScriptsPreserved -and
    [int]$contract.buildEvidence.compiledDestructibleKillCreditScriptsPreserved -eq [int]$contract.expected.destructibleKillCreditScriptsPreserved) `
    "p14.city-invasion.compiled-template-script-evidence"
Assert-Contract ([string]$contract.runtimeEvidence.deployedDirectSourceCommit -ceq [string]$contract.buildEvidence.directSourceCommit) `
    "p14.city-invasion.deployed-direct-source-synchronized"

$gcw = [string]$texts["script.library.gcw"]
$city = [string]$texts["script.systems.gcw.gcw_city"]
$planet = [string]$texts["script.planet.planet_base"]
$player = [string]$texts["script.player.base.base_player"]

$retiredFlag = Get-FunctionSlice $gcw `
    "public static boolean isPostNgeCityInvasionRetired()" `
    "public static final String GCW_TUTORIAL_FLAG"
Assert-Contract ($retiredFlag.Contains("return true;") -and
    $retiredFlag.Contains("PRE-CU keeps faction standing/rank, static faction")) `
    "p14.city-invasion.authoritative-retirement-flag"

$retireController = Get-FunctionSlice $city `
    "private void retirePostNgeCityInvasion" `
    "public int OnAttach"
$controllerCleanupMarkers = @(
    'utils.removeScriptVarTree(self, "gcw")',
    'utils.removeScriptVar(planet, "gcw.lastTrackTime." + cityName)',
    'utils.removeScriptVar(planet, "gcw.invasionRunning." + cityName)',
    'messageTo(self, "cleanupSpawn", null, 1.0f, false)',
    'detachScript(self, SCRIPT_NAME)'
)
Assert-Contract (@($controllerCleanupMarkers | Where-Object { -not $retireController.Contains($_) }).Count -eq 0) `
    "p14.city-invasion.persisted-controller-cleans-and-detaches"

$controllerHandlers = [ordered]@{
    OnAttach = @("public int OnAttach", "public void qaInstabuild")
    OnHearSpeech = @("public int OnHearSpeech", "public int OnInitialize")
    OnInitialize = @("public int OnInitialize", "public int checkForInvasion")
    checkForInvasion = @("public int checkForInvasion", "public int beginInvasion")
    beginInvasion = @("public int beginInvasion", "public void setAnnouncementLocation")
}
foreach ($name in $controllerHandlers.Keys)
{
    $markers = $controllerHandlers[$name]
    $slice = Get-FunctionSlice $city $markers[0] $markers[1]
    $retireIndex = $slice.IndexOf("retirePostNgeCityInvasion(self);", [System.StringComparison]::Ordinal)
    $returnIndex = $slice.IndexOf("return SCRIPT_CONTINUE;", [System.StringComparison]::Ordinal)
    Assert-Contract ($slice.Contains("gcw.isPostNgeCityInvasionRetired()") -and
        $retireIndex -ge 0 -and $returnIndex -gt $retireIndex) `
        "p14.city-invasion.controller-entrypoint.$name.retired"
}

$planetCleanup = Get-FunctionSlice $planet `
    "private void retirePostNgeCityInvasionState" `
    "public void gcwInvasionMessage"
Assert-Contract ($planetCleanup.Contains("for (String cityName : gcw.INVASION_CITIES)") -and
    $planetCleanup.Contains('utils.removeScriptVar(self, "gcw.object." + cityName)') -and
    $planetCleanup.Contains('utils.removeScriptVar(self, "gcw.calendar_time." + cityName)') -and
    $planetCleanup.Contains('utils.removeScriptVar(self, "gcw.factionDefending." + cityName)')) `
    "p14.city-invasion.stale-planet-state-scrub"

$planetHandlers = [ordered]@{
    gcwInvasionMessage = @("public void gcwInvasionMessage", "public int gcwInvasionTracker")
    gcwInvasionTracker = @("public int gcwInvasionTracker", "public int gcwGetInvasionObject")
    gcwGetInvasionObject = @("public int gcwGetInvasionObject", "`n}")
}
foreach ($name in $planetHandlers.Keys)
{
    $markers = $planetHandlers[$name]
    $slice = Get-FunctionSlice $planet $markers[0] $markers[1]
    Assert-Contract ($slice.Contains("gcw.isPostNgeCityInvasionRetired()") -and
        $slice.Contains("retirePostNgeCityInvasionState(self);")) `
        "p14.city-invasion.planet-entrypoint.$name.retired"
}

$buildoutExpectations = [ordered]@{
    "buildout.tatooine_4_3" = "datatables/gcw/gcw_city_bestine.iff"
    "buildout.talus_5_3" = "datatables/gcw/gcw_city_dearic.iff"
    "buildout.naboo_5_6" = "datatables/gcw/gcw_city_keren.iff"
}
foreach ($name in $buildoutExpectations.Keys)
{
    $table = $buildoutExpectations[$name]
    $rows = @(([string]$texts[$name] -split "`r?`n") | Where-Object { $_.Contains($table) })
    Assert-Contract ($rows.Count -eq 1 -and
        $rows[0].Contains("systems.dungeon_sequencer.sequence_controller") -and
        -not $rows[0].Contains("systems.gcw.gcw_city")) `
        "p14.city-invasion.buildout.$name.controller-detached-assets-retained"
}

Assert-Contract (-not $player.Contains("gcw.invasionRunning.bestine") -and
    -not $player.Contains("gcw.invasionRunning.dearic") -and
    -not $player.Contains("gcw.invasionRunning.keren") -and
    -not $player.Contains("gcw.factionDefending.bestine") -and
    -not $player.Contains("gcw.factionDefending.dearic") -and
    -not $player.Contains("gcw.factionDefending.keren")) `
    "p14.city-invasion.invasion-only-cloning-filter-removed"

$missionTerminal = [string]$texts["retained.mission_terminal"]
$missionBase = [string]$texts["retained.mission_base"]
$battlefieldLibrary = [string]$texts["retained.battlefield_library"]
$battlefieldPlayer = [string]$texts["retained.battlefield_player"]
$factions = [string]$texts["retained.factions"]
Assert-Contract ($missionTerminal.Contains("menu_info_types.MISSION_TERMINAL_LIST") -and
    $missionTerminal.Contains("public int OnObjectMenuRequest") -and
    $missionBase.Contains("MAX_MISSIONS = 10") -and
    $missionBase.Contains("fullRewardEach=") -and
    $missionBase.Contains("split=false dailyCashPenalty=false")) `
    "p14.city-invasion.live-confirmed-mission-board-and-rewards-retained"
Assert-Contract ($battlefieldLibrary.Contains('SCRIPT_BATTLEFIELD_REGION = "systems.battlefield.battlefield_region"') -and
    $battlefieldPlayer.Contains("factions.addFactionStanding(self, faction, standing)") -and
    -not $battlefieldPlayer.Contains("item_battlefield_rebel_token_") -and
    -not $battlefieldPlayer.Contains("item_battlefield_imperial_token_")) `
    "p14.city-invasion.precu-open-world-battlefield-standing-retained"
Assert-Contract ($factions.Contains("awardPrecuNpcCombatFaction") -and
    $factions.Contains("pvpSetPrecuFactionRank")) `
    "p14.city-invasion.precu-faction-standing-and-rank-retained"

$patchText = if (Test-Path -LiteralPath $patchPath) { Get-Content -LiteralPath $patchPath -Raw } else { "" }
Assert-Contract (-not $patchText.Contains("systems/missions/") -and
    -not $patchText.Contains("mission_terminal") -and
    -not $patchText.Contains("mission_base.java") -and
    -not $patchText.Contains("systems/gcw/player_pvp.java") -and
    -not $patchText.Contains("systems/battlefield/")) `
    "p14.city-invasion.mission-and-battlefield-source-untouched"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) `
    "p14.city-invasion.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU city-invasion retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU city-invasion retirement passed."
