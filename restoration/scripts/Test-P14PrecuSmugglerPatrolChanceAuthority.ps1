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
    ([string]$manifest.contracts.p14PrecuSmugglerPatrolChanceAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$paths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $source ([string]$property.Value)
}
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedBlock([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.smuggler-patrol.source.$([IO.Path]::GetFileName($path)).exists"
}

$patrol = Get-Content -LiteralPath $paths.patrolAi -Raw
$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$utils = Get-Content -LiteralPath $paths.utils -Raw
$groundquests = Get-Content -LiteralPath $paths.groundquests -Raw
$commandTable = Get-Content -LiteralPath $paths.commandTable -Raw
$combatData = Get-Content -LiteralPath $paths.combatData -Raw
$contraband = Get-BracedBlock $patrol `
    "public int contrabandCheckResult(obj_id self, dictionary params)"
$fastTalk = Get-BracedBlock $patrol `
    "public int fastTalkReaction(obj_id self, dictionary params)"
$trigger = Get-BracedBlock $patrol `
    "public int OnTriggerVolumeEntered(obj_id self, String volumeName, obj_id breacher)"
$startCheck = Get-BracedBlock $patrol `
    "public int startContrabandCheck(obj_id self, dictionary params)"
$bootstrap = Get-BracedBlock $basePlayer `
    "public void sendSmugglerSystemBootstrap(obj_id self)"

Assert-Contract (-not $patrol.Contains("expertise_") -and
    -not $patrol.Contains("getSkillStatisticModifier") -and
    -not $patrol.Contains("getEnhancedSkillStatisticModifier") -and
    -not $patrol.Contains("getSmugglerRank") -and
    -not $patrol.Contains("getFactionStanding")) `
    "p14.smuggler-patrol.nge-expertise-rank-authority-absent"
Assert-Contract ($patrol.Contains("public static final int CONTRABAND_BASE_PASS_CHANCE = 5;") -and
    $patrol.Contains("public static final int SLY_LIE_BASE_BONUS = 10;") -and
    $patrol.Contains("public static final int FAST_TALK_BASE_CHANCE = 25;") -and
    [int]$contract.expected.normalContrabandPassChancePercent -eq 5 -and
    [int]$contract.expected.slyLieBaseBonusPercent -eq 10 -and
    [int]$contract.expected.slyLieTotalPassChancePercent -eq 15 -and
    [int]$contract.expected.fastTalkBaseChancePercent -eq 25) `
    "p14.smuggler-patrol.authored-baseline-constants"
Assert-Contract ($contraband.Contains("int passChance = CONTRABAND_BASE_PASS_CHANCE;") -and
    $contraband.Contains('utils.hasScriptVar(self, "slyLie")') -and
    $contraband.Contains("passChance += SLY_LIE_BASE_BONUS;") -and
    $contraband.Contains("boolean usedSlyLie = false;") -and
    $contraband.Contains("if (rand(1, 100) > passChance)") -and
    $contraband.Contains('"bark_attack"') -and
    $contraband.Contains('"bark_lies_failed"') -and
    $contraband.Contains("startCombat(self, playerSmuggler)") -and
    $contraband.Contains("broadcastCondition(playerSmuggler, self, FLAG_ATTACK)")) `
    "p14.smuggler-patrol.contraband-flow-preserved"
Assert-Contract ($fastTalk.Contains("int roll = rand(1, 100);") -and
    $fastTalk.Contains("if (roll > FAST_TALK_BASE_CHANCE)") -and
    $fastTalk.Contains('"bark_fast_talk_failed"') -and
    $fastTalk.Contains("doConfuse(playerSmuggler, self);") -and
    -not $fastTalk.Contains("doConfuseAttack")) `
    "p14.smuggler-patrol.fast-talk-baseline"
Assert-Contract ($trigger.Contains("utils.isProfession(breacher, utils.SMUGGLER)") -and
    $trigger.Contains("groundquests.isDoingSmugglerMission(breacher)") -and
    $startCheck.Contains('hasObjVar(self, "quest.owner")') -and
    $startCheck.Contains('messageTo(self, "contrabandCheckResult", null, 11.0f, false)')) `
    "p14.smuggler-patrol.live-mission-entrypoints-preserved"
Assert-Contract ($basePlayer.Contains("sendSmugglerSystemBootstrap(self);") -and
    $bootstrap.Contains("utils.isProfession(self, utils.SMUGGLER)") -and
    $bootstrap.Contains("isInTutorialArea(self)") -and
    $bootstrap.Contains('messageTo(self, "handleSendSmugglerBootstrapRequest", null, 120.0f, false)') -and
    $utils.Contains('case SMUGGLER:') -and
    $utils.Contains('return hasSkill(player, "combat_smuggler_novice");')) `
    "p14.smuggler-patrol.precu-profession-bootstrap"

$missionNames = @(
    "smuggle_generic_1", "smuggle_generic_2", "smuggle_generic_3", "smuggle_generic_4", "smuggle_generic_5",
    "smuggle_illicit_1", "smuggle_illicit_2", "smuggle_illicit_3", "smuggle_illicit_4", "smuggle_illicit_5"
)
$missionsPresent = @($missionNames | Where-Object { $groundquests.Contains('"' + $_ + '"') })
Assert-Contract ($missionsPresent.Count -eq $missionNames.Count) `
    "p14.smuggler-patrol.retained-mission-families"

$creatureRows = @(Import-Csv -LiteralPath $paths.creatures -Delimiter "`t")
$patrolRows = @($creatureRows | Where-Object {
    [string]$_.scripts -match '(^|,)ai\.smuggler_spawn_enemy(,|$)'
})
Assert-Contract ($patrolRows.Count -eq [int]$contract.expected.patrolCreatureRows -and
    @($patrolRows | Where-Object { -not ([string]$_.creatureName).StartsWith("smuggler_patrol_") }).Count -eq 0) `
    "p14.smuggler-patrol.live-creature-definitions"

$skillRows = Get-Content -LiteralPath $paths.skills
$precuSmugglerRows = @($skillRows | Where-Object {
    $name = ([regex]::Split($_, "`t"))[0]
    $name -ceq "combat_smuggler" -or $name.StartsWith("combat_smuggler_")
})
$precuSmugglerText = $precuSmugglerRows -join "`n"
Assert-Contract ($precuSmugglerRows.Count -eq [int]$contract.expected.canonicalPrecuSmugglerRows -and
    -not $precuSmugglerText.Contains("sm_sly_lie") -and
    -not $precuSmugglerText.Contains("sm_fast_talk") -and
    -not $precuSmugglerText.Contains("expertise_")) `
    "p14.smuggler-patrol.compatibility-actions-ungranted"
foreach ($action in @("sm_sly_lie", "sm_fast_talk"))
{
    Assert-Contract (([regex]::Matches($commandTable, "(?m)^$action`t")).Count -eq 1 -and
        ([regex]::Matches($combatData, "(?m)^$action`t")).Count -eq 1) `
        "p14.smuggler-patrol.$action.compatibility-data-preserved"
}

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.smuggler-patrol.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.smuggler-patrol.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.smuggler-patrol.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.smuggler-patrol.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.smuggler-patrol.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.smuggler-patrol.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU Smuggler patrol chance authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU Smuggler patrol chance authority contract passed."
