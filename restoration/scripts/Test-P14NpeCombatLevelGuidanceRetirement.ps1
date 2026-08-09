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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14NpeCombatLevelGuidanceRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$scriptRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/script"
$journalPath = Join-Path $scriptRoot "npe/trigger_journal.java"
$basePlayerPath = Join-Path $scriptRoot "player/base/base_player.java"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Marker)
{
    $start = $Text.IndexOf($Marker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf('{', $start)
    if ($open -lt 0) { return "" }
    $depth = 1
    for ($index = $open + 1; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

Assert-Contract (Test-Path -LiteralPath $journalPath -PathType Leaf) "p14.npe-level.source.journal.exists"
Assert-Contract (Test-Path -LiteralPath $basePlayerPath -PathType Leaf) "p14.npe-level.source.base-player.exists"
$journal = Get-Content -LiteralPath $journalPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $journalPath).Hash.ToLowerInvariant()
Assert-Contract ($sourceHash -ceq [string]$contract.buildEvidence.sourceSha256."trigger_journal.java") `
    "p14.npe-level.source.authenticated"

$directCommit = (& git -C $dsrc rev-parse HEAD).Trim()
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($LASTEXITCODE -eq 0 -and $dsrcPin.Count -eq 1 -and
    $directCommit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
    [string]$dsrcPin[0].commit -ceq $directCommit) "p14.npe-level.direct-source-pin"

$excluded = '\\(test|working|beta|gm|content_tools|e3demo)\\'
$callbacks = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java" |
    Where-Object { $_.FullName -notmatch $excluded } |
    Select-String -Pattern 'public int OnCombatLevelChanged\s*\(')
$callbackPaths = @($callbacks | ForEach-Object {
    $_.Path.Substring($scriptRoot.Length + 1).Replace('\', '/')
} | Sort-Object -Unique)
Assert-Contract ($callbacks.Count -eq [int]$contract.inventory.productionCombatLevelChangedCallbacks -and
    $callbackPaths.Count -eq 2 -and
    $callbackPaths[0] -ceq "npe/trigger_journal.java" -and
    $callbackPaths[1] -ceq "player/base/base_player.java") "p14.npe-level.callback-inventory"

$cleanup = Get-BracedSurface $journal "private static void retireNgeLevelGuidance"
$initialize = Get-BracedSurface $journal "public int OnInitialize"
$levelChanged = Get-BracedSurface $journal "public int OnCombatLevelChanged"
$delayed = Get-BracedSurface $journal "public int doDelayed3POMessage"
$baseLevelChanged = Get-BracedSurface $basePlayer "public int OnCombatLevelChanged"
Assert-Contract ($cleanup.Contains('removeObjVar(player, NGE_LEVEL_GUIDANCE_OBJVAR)') -and
    $cleanup.Contains('utils.removeScriptVar(player, NGE_LEVEL_GUIDANCE_SCRIPTVAR)')) `
    "p14.npe-level.persisted-and-session-state-cleanup"
Assert-Contract ($initialize.Contains("retireNgeLevelGuidance(self)") -and
    $levelChanged.Contains("retireNgeLevelGuidance(self)") -and
    $delayed.Contains("retireNgeLevelGuidance(self)")) "p14.npe-level.cleanup-entrypoints"
Assert-Contract (-not $levelChanged.Contains("newCombatLevel == 2") -and
    -not $levelChanged.Contains("setObjVar(") -and
    -not $levelChanged.Contains("sendDelayed3poPopup(")) "p14.npe-level.callback-fails-closed"
$delayedGuard = $delayed.IndexOf("strMessage.equals(NGE_LEVEL_GUIDANCE_MESSAGE)", [System.StringComparison]::Ordinal)
$delayedMutation = $delayed.IndexOf("npe.commTutorialPlayer", [System.StringComparison]::Ordinal)
Assert-Contract ($delayedGuard -ge 0 -and $delayedMutation -gt $delayedGuard -and
    $delayed.Substring($delayedGuard, $delayedMutation - $delayedGuard).Contains("return SCRIPT_CONTINUE;")) `
    "p14.npe-level.stale-delayed-popup-rejected"
Assert-Contract (([regex]::Matches($journal, 'sendDelayed3poPopup\(')).Count -eq 1 -and
    -not $journal.Contains('"sound/vo_c3po_18c.snd"')) "p14.npe-level.popup-producer-retired"
Assert-Contract (-not $journal.Contains('setObjVar(self, "npe.secondLevelGranted"') -and
    ([regex]::Matches($journal, 'retireNgeLevelGuidance\(')).Count -eq
        ([int]$contract.expected.npeLevelCleanupEntrypoints + 1)) "p14.npe-level.state-writer-retired"

Assert-Contract ($journal.Contains("npe.reGrantReWorkedQuests(self)") -and
    $journal.Contains("npe.clearActiveSpaceQuests(self)") -and
    $journal.Contains('groundquests.sendSignal(self, "npe_elevator_atrium_down")') -and
    $journal.Contains('"pop_first_ability"') -and
    $journal.Contains("npe.movePlayerFromSharedStationToOrdMantellDungeon(player)") -and
    $journal.Contains("npe.movePlayerFromOrdMantellDungeonToSharedStation(player)")) `
    "p14.npe-level.retained-tansarii-content"
Assert-Contract ($baseLevelChanged.Contains("recomputeCommandSeries(self)") -and
    -not $baseLevelChanged.Contains("grantLevelSpecificRewards") -and
    -not $baseLevelChanged.Contains("createLevelReward") -and
    -not $baseLevelChanged.Contains("setMaxAttribute")) "p14.npe-level.base-callback-compatible"

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.fullServerBuild -like "passed*" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        @($contract.requiredBeforeReady).Count -eq 0) "p14.npe-level.ready-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status -and
        [string]$contract.buildEvidence.result -ceq "passed") "p14.npe-level.source-status"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 NPE combat-level guidance retirement failed: $($failures -join ', ')"
}
Write-Host "Publish 14.1 NPE combat-level guidance retirement passed."
