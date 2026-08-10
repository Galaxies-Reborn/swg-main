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
$tfordTestPath = Join-Path $scriptRoot "test/tford_test.java"
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

function Get-TextSha256([string]$Text)
{
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

Assert-Contract (Test-Path -LiteralPath $journalPath -PathType Leaf) "p14.npe-level.source.journal.exists"
Assert-Contract (Test-Path -LiteralPath $basePlayerPath -PathType Leaf) "p14.npe-level.source.base-player.exists"
Assert-Contract (Test-Path -LiteralPath $tfordTestPath -PathType Leaf) "p14.npe-level.source.tford-test.exists"
$journal = Get-Content -LiteralPath $journalPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$tfordTest = Get-Content -LiteralPath $tfordTestPath -Raw
$sourceMap = [ordered]@{
    triggerJournal = @{ Path = $journalPath; Relative = "npe/trigger_journal.java" }
    basePlayer = @{ Path = $basePlayerPath; Relative = "player/base/base_player.java" }
    tfordTest = @{ Path = $tfordTestPath; Relative = "test/tford_test.java" }
}
$contentRows = [Collections.Generic.List[string]]::new()
foreach ($name in $sourceMap.Keys)
{
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        $sourceMap[$name].Path).Hash.ToLowerInvariant()
    Assert-Contract ($sourceHash -ceq [string]$contract.buildEvidence.sourceSha256.$name) `
        "p14.npe-level.source.$name.authenticated"
    $contentRows.Add("$($sourceMap[$name].Relative)|$sourceHash")
}
Assert-Contract ((Get-TextSha256 (@($contentRows | Sort-Object) -join "`n")) -ceq
    [string]$contract.inventory.sourceContentSha256) "p14.npe-level.source-content.authenticated"

$directCommit = (& git -C $dsrc rev-parse HEAD).Trim()
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($LASTEXITCODE -eq 0 -and $dsrcPin.Count -eq 1 -and
    $directCommit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
    [string]$dsrcPin[0].commit -ceq $directCommit) "p14.npe-level.direct-source-pin"

Assert-Contract ($null -ne (Get-Command rg -ErrorAction SilentlyContinue)) `
    "p14.npe-level.ripgrep-available"
$records = [Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading ([string]$contract.inventory.pattern) `
    $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
        "p14.npe-level.callback-record-parses"
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace('\', '/')
    $records.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
}
$records = @($records | Sort-Object)
$callbackPaths = @($records | ForEach-Object { ($_ -split ':\d+\|', 2)[0] } |
    Sort-Object -Unique)
Assert-Contract ($records.Count -eq [int]$contract.inventory.allCombatLevelChangedCallbacks -and
    $callbackPaths.Count -eq 3 -and
    ($callbackPaths -join "`n") -ceq (@($contract.inventory.callbacks) -join "`n") -and
    (Get-TextSha256 ($records -join "`n")) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 ($callbackPaths -join "`n")) -ceq
        [string]$contract.inventory.sourceSetSha256) "p14.npe-level.complete-callback-inventory"
$excluded = '\\(test|working|beta|gm|content_tools|e3demo)\\'
$productionCallbacks = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java" |
    Where-Object { $_.FullName -notmatch $excluded } |
    Select-String -Pattern 'public int OnCombatLevelChanged\s*\(')
Assert-Contract ($productionCallbacks.Count -eq
    [int]$contract.inventory.productionCombatLevelChangedCallbacks) `
    "p14.npe-level.production-callback-inventory"

$cleanup = Get-BracedSurface $journal "private static void retireNgeLevelGuidance"
$initialize = Get-BracedSurface $journal "public int OnInitialize"
$levelChanged = Get-BracedSurface $journal "public int OnCombatLevelChanged"
$delayed = Get-BracedSurface $journal "public int doDelayed3POMessage"
$baseLevelChanged = Get-BracedSurface $basePlayer "public int OnCombatLevelChanged"
$tfordLevelChanged = Get-BracedSurface $tfordTest "public int OnCombatLevelChanged"
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
Assert-Contract ($tfordLevelChanged.Contains("debugSpeakMsg") -and
    $tfordLevelChanged.Contains("oldCombatLevel") -and
    $tfordLevelChanged.Contains("newCombatLevel") -and
    $tfordLevelChanged -notmatch
        '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate|setMaxAttrib|applyBuff|money\.[A-Za-z0-9_]+)\s*\(' -and
    [int]$contract.expected.dormantTestProgressionMutations -eq 0) `
    "p14.npe-level.dormant-test-diagnostic-only"
$tfordAttachments = @(& rg -n --glob "*.java" --glob "*.tab" --glob "*.tpf" `
    '\battachScript\s*\([^;]*"test\.tford_test"' $dsrc)
$tfordAttachmentExit = $LASTEXITCODE
Assert-Contract ($tfordAttachmentExit -eq 1 -and $tfordAttachments.Count -eq 0 -and
    $tfordTest.Contains('detachScript(self, "test.tford_test")') -and
    [int]$contract.expected.dormantTestProductionAttachments -eq 0) `
    "p14.npe-level.dormant-test-unattached"

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.fullServerBuild -like "passed*" -and
        [int]$contract.buildEvidence.javaSourcesCompiled -eq 5717 -and
        [int]$contract.buildEvidence.javaClassesEmitted -eq 5751 -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [string]$contract.runtimeEvidence.deployedDsrcCommit -ceq $directCommit -and
        @($contract.requiredBeforeReady).Count -eq 0) "p14.npe-level.ready-evidence"

    $container = [string]$contract.runtimeEvidence.container
    $state = (& docker inspect --format `
        "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" `
        $container).Trim()
    $processNames = @(& docker exec $container ps -eo comm= |
        ForEach-Object { $_.Trim() })
    $binaryHash = ((& docker exec $container sha256sum `
        /swg-precu/build/bin/SwgGameServer) -split '\s+')[0]
    $classRoot = "/swg-precu/data/sku.0/sys.server/compiled/game/script"
    $classMap = [ordered]@{
        triggerJournal = "npe/trigger_journal.class"
        basePlayer = "player/base/base_player.class"
        tfordTest = "test/tford_test.class"
    }
    $classesMatch = $true
    foreach ($name in $classMap.Keys)
    {
        $classPath = "$classRoot/$($classMap[$name])"
        $classHash = ((& docker exec $container sha256sum $classPath) -split '\s+')[0]
        $classBytes = [int64]((& docker exec $container stat -c "%s" $classPath).Trim())
        $classesMatch = $classesMatch -and
            $classHash -ceq [string]$contract.buildEvidence.compiledClassSha256.$name -and
            $classBytes -eq [int64]$contract.buildEvidence.compiledClassBytes.$name
    }
    Assert-Contract ($state -ceq "running healthy" -and
        @($processNames | Where-Object { $_ -ceq "SwgGameServer" }).Count -eq 15 -and
        @($processNames | Where-Object { $_ -ceq "PlanetServer" }).Count -eq 15 -and
        $binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $classesMatch) "p14.npe-level.live-x64-class-evidence"
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
