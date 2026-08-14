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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuRetainedSystemLevelAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$priorContractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuRetainedContentLevelAuthority)
$priorContract = Get-Content -LiteralPath $priorContractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

$relativeSources = [ordered]@{
    "script.ai.imperial_presence.harass" = "ai/imperial_presence/harass.java"
    "script.city.imperial_crackdown.imperial_trouble" = "city/imperial_crackdown/imperial_trouble.java"
    "script.event.ewok_festival.loveday_reward_crossbow" = "event/ewok_festival/loveday_reward_crossbow.java"
    "script.event.halloween.song_book" = "event/halloween/song_book.java"
    "script.event.lost_squadron.stolen_fighter" = "event/lost_squadron/stolen_fighter.java"
    "script.library.collection" = "library/collection.java"
    "script.library.groundquests" = "library/groundquests.java"
    "script.library.npe" = "library/npe.java"
    "script.library.performance" = "library/performance.java"
    "script.library.smuggler" = "library/smuggler.java"
    "script.library.space_combat" = "library/space_combat.java"
    "script.library.township" = "library/township.java"
    "script.npc.static_quest.quest_convo" = "npc/static_quest/quest_convo.java"
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.retained-system.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.retained-system.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$expectedTargets = @($relativeSources.Values | ForEach-Object {
    "sku.0/sys.server/compiled/game/script/$_"
} | Sort-Object)
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    ($targets -join "`n") -ceq ($expectedTargets -join "`n")) "p14.retained-system.overlay.target-set"
$targetSetText = ($targets -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $targetSetText) -ceq [string]$contract.buildEvidence.sourceSetSha256) `
    "p14.retained-system.source-set.authenticated"

$texts = [ordered]@{}
foreach ($entry in $relativeSources.GetEnumerator())
{
    $path = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.retained-system.source.$($entry.Key).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$entry.Key] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$entry.Key].Value
    Assert-Contract ($hash -ceq $expectedHash) "p14.retained-system.source.$($entry.Key).authenticated"
}

$contentRecords = [System.Collections.Generic.List[string]]::new()
foreach ($target in $targets)
{
    $targetPath = Join-Path (Join-Path $source "dsrc") $target
    $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
    $contentRecords.Add("$target=$targetHash")
}
$contentRecordText = ($contentRecords -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $contentRecordText) -ceq [string]$contract.buildEvidence.sourceContentSha256) `
    "p14.retained-system.source-content.authenticated"

$allText = $texts.Values -join "`n"
$forbiddenReads = @(
    "getLevel(player)",
    "getLevel(speaker)",
    "getLevel(actor)",
    "getLevel(target)",
    "getLevel(whoTriggeredMe)",
    "getLevel(((obj_id) objPlayer))"
)
$remainingReads = 0
foreach ($read in $forbiddenReads)
{
    $remainingReads += ([regex]::Matches($allText, [regex]::Escape($read))).Count
}
Assert-Contract ($remainingReads -eq [int]$contract.expected.remainingDirectPlayerLevelReads) `
    "p14.retained-system.direct-player-level.retired"

$encounterCalls = ([regex]::Matches($allText, 'getPrecuEncounterDifficulty\(')).Count
$entertainerCalls = ([regex]::Matches($allText, 'getPrecuEntertainerContentDifficulty\(')).Count
Assert-Contract ($encounterCalls -eq [int]$contract.expected.encounterDifficultyCalls) `
    "p14.retained-system.encounter-adapter.call-count"
Assert-Contract ($entertainerCalls -eq [int]$contract.expected.entertainerDifficultyConsumers) `
    "p14.retained-system.entertainer-adapter.call-count"

$groundquestsText = [string]$texts["script.library.groundquests"]
$spaceText = [string]$texts["script.library.space_combat"]
$performanceText = [string]$texts["script.library.performance"]
$songBookText = [string]$texts["script.event.halloween.song_book"]
$lovedayText = [string]$texts["script.event.ewok_festival.loveday_reward_crossbow"]
Assert-Contract ($groundquestsText.Contains("QUEST_EXPERIENCE_TABLE") -and
    $groundquestsText.Contains("getQuestExperienceReward") -and
    -not $groundquestsText.Contains("getQuestXpCap") -and
    -not $groundquestsText.Contains('datatables/player/player_level.iff')) `
    "p14.retained-system.quest-content-without-nge-level-cap"
Assert-Contract ($spaceText.Contains("getPrecuEncounterDifficulty(((obj_id) objPlayer))") -and
    $spaceText.Contains("xp.grantCombatStyleXp(((obj_id) objPlayer), xp.COMBAT_GENERAL, intGroundXp)") -and
    -not $spaceText.Contains('xp.grant(((obj_id) objPlayer), "combat_general", intGroundXp)')) `
    "p14.retained-system.space-ground-xp.precu-adapter"
Assert-Contract ($performanceText.Contains("getPrecuEntertainerContentDifficulty(actor)") -and
    $songBookText.Contains("getPrecuEntertainerContentDifficulty(player)")) `
    "p14.retained-system.entertainer-content.social-authority"
Assert-Contract ($lovedayText.Contains("getLevel(hater)") -and
    -not $lovedayText.Contains("getLevel(player)")) `
    "p14.retained-system.authored-creature-level.preserved"

Assert-Contract ([string]$priorContract.status -ceq "ready" -and
    [string]$priorContract.expected.professionAdapters.combatAndGenericQuest -ceq "skill.getPrecuEncounterDifficulty" -and
    [string]$priorContract.expected.professionAdapters.entertainer -ceq "skill.getPrecuEntertainerContentDifficulty") `
    "p14.retained-system.prior-adapter-contract.ready"

$missionMap = [ordered]@{
    "mission_terminal.java" = (Join-Path $scriptRoot "systems/missions/base/mission_terminal.java")
    "mission_base.java" = (Join-Path $scriptRoot "systems/missions/base/mission_base.java")
    "missions.java" = (Join-Path $scriptRoot "library/missions.java")
}
foreach ($mission in $missionMap.GetEnumerator())
{
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $mission.Value).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$contract.continuityEvidence.missionSourceSha256.($mission.Key)) `
        "p14.retained-system.mission-source.$($mission.Key).unchanged"
}

if ($failures.Count -gt 0)
{
    throw "P14 PRE-CU retained-system level authority contract failed: $($failures -join ', ')"
}

Write-Host "P14 PRE-CU retained-system level authority contract passed."
