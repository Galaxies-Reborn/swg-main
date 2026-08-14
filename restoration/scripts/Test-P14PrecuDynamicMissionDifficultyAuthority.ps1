[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuDynamicMissionDifficultyAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$sourcePaths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $sourcePaths[$property.Name] = Join-Path $source ([string]$property.Value)
}
$texts = @{}
foreach ($name in $sourcePaths.Keys)
{
    $path = $sourcePaths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.dynamic-mission.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) `
            "p14.dynamic-mission.source.$name.authenticated"
    }
}

$missionDynamic = [string]$texts.missionDynamic
$planetCheck = Get-SourceSlice $missionDynamic `
    "public boolean isPlanetHuntingViable(" `
    "public void msgWrongHuntingPlanet("
$planetMessage = Get-SourceSlice $missionDynamic `
    "public void msgWrongHuntingPlanet(" `
    "}`n}`n"
$rawMissionLevelPattern = '(?<![A-Za-z0-9_\.])getLevel\s*\(\s*player\s*\)'
$adapterPattern = 'skill\.getPrecuEncounterDifficulty\s*\(\s*player\s*\)'
Assert-Contract (([regex]::Matches($planetCheck, $adapterPattern).Count +
        [regex]::Matches($planetMessage, $adapterPattern).Count) -eq
        [int]$contract.expected.precuEncounterDifficultyReadsInPlanetHelpers -and
    [regex]::Matches($planetCheck + $planetMessage, $rawMissionLevelPattern).Count -eq 0) `
    "p14.dynamic-mission.planet-helpers.precu-authority"
Assert-Contract ($planetCheck.Contains('area.equals("tatooine")') -and
    $planetCheck.Contains('area.equals("dathomir")') -and
    $planetMessage.Contains("SID_MISSION_TATOOINE") -and
    $planetMessage.Contains("SID_MISSION_YAVIN_ENDOR_DATHOMIR")) `
    "p14.dynamic-mission.authored-planet-bands-preserved"

$missionEscort = [string]$texts.missionEscort
$escortRequest = Get-SourceSlice $missionEscort `
    'if ((response.getAsciiId()).equals("npc_job_request"))' `
    "public int escort_Accepted("
Assert-Contract (-not $escortRequest.Contains("intPlayerDifficulty") -and
    -not $escortRequest.Contains("getLevel(") -and
    $escortRequest.Contains("getMyMission(self)")) `
    "p14.dynamic-mission.escort-unused-level-read-removed"
$escortMission = Get-SourceSlice $missionEscort `
    "public obj_id getMyMission(" `
    "public int destroySelf("
Assert-Contract ($escortMission.Contains('getIntObjVar(self, "intDifficulty")') -and
    $escortMission.Contains("intDifficulty = rand(1, 20)") -and
    $escortMission.Contains("createEscortTargetMission")) `
    "p14.dynamic-mission.escort-authored-difficulty-preserved"

$missionScriptRoot = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/script/systems/missions"
$missionJava = @(Get-ChildItem -LiteralPath $missionScriptRoot -Recurse -Filter "*.java" -File)
$rawMissionReads = 0
foreach ($file in $missionJava)
{
    $rawMissionReads += [regex]::Matches(
        [System.IO.File]::ReadAllText($file.FullName), $rawMissionLevelPattern).Count
}
Assert-Contract ($rawMissionReads -eq [int]$contract.expected.rawPlayerLevelReadsInMissionTree) `
    "p14.dynamic-mission.mission-tree.no-raw-player-level"

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$planetCheckReferences = 0
$planetMessageReferences = 0
foreach ($file in @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter "*.java" -File))
{
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $planetCheckReferences += [regex]::Matches($text, '\bisPlanetHuntingViable\s*\(').Count
    $planetMessageReferences += [regex]::Matches($text, '\bmsgWrongHuntingPlanet\s*\(').Count
}
Assert-Contract ($planetCheckReferences -eq [int]$contract.expected.dormantPlanetHelperReferences -and
    $planetMessageReferences -eq [int]$contract.expected.dormantPlanetHelperReferences) `
    "p14.dynamic-mission.dormant-helper-reachability"

$missionPlayer = [string]$texts.missionPlayer
Assert-Contract ([regex]::Matches($missionPlayer,
        'missions\.getPrecuMissionGroupCombatScore\s*\(\s*self\s*\)').Count -eq
        [int]$contract.expected.missionBoardCombatScoreReads -and
    -not $missionPlayer.Contains("getLevel(")) `
    "p14.dynamic-mission.board-precu-score-preserved"

$npcMissionNames = @("npcMission", "npcMission01", "npcMission02", "npcMission03",
    "npcMission04", "npcMission05")
$npcAdapterReads = 0
foreach ($name in $npcMissionNames)
{
    $text = [string]$texts[$name]
    $npcAdapterReads += [regex]::Matches($text, $adapterPattern).Count
    Assert-Contract (-not [regex]::IsMatch($text, $rawMissionLevelPattern)) `
        "p14.dynamic-mission.npc-conversation.$name.no-raw-level"
}
Assert-Contract ($npcMissionNames.Count -eq
        [int]$contract.expected.retainedNpcMissionConversationFiles -and
    $npcAdapterReads -eq [int]$contract.expected.precuNpcMissionAdapterReads) `
    "p14.dynamic-mission.npc-conversations.precu-authority"

$skill = [string]$texts.skill
Assert-Contract ($skill.Contains("public static int getPrecuEncounterDifficulty(") -and
    $skill.Contains("return Math.max(1, getPrecuCombatSkillScore(player));")) `
    "p14.dynamic-mission.adapter-definition"
Assert-Contract ([string]$texts.attributes -match
    '(?m)^sku\.0/sys\.server/compiled/game/script/systems/missions/dynamic/mission_escort_npc\.java -text\r?$') `
    "p14.dynamic-mission.no-line-ending-bloat-policy"

$missionContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuMissionBoardGroupRewards)) -Raw | ConvertFrom-Json
$encounterContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuEncounterDifficultyAuthority)) -Raw | ConvertFrom-Json
Assert-Contract ([string]$missionContract.status -ceq "ready" -and
    [string]$encounterContract.status -ceq "ready") `
    "p14.dynamic-mission.adjacent-authority-continuity"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.dynamic-mission.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.dynamic-mission.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.missionDynamic -match
            '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.missionEscort -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassesPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.dynamic-mission.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.dynamic-mission.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.dynamic-mission.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU dynamic mission difficulty authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU dynamic mission difficulty authority contract passed."
