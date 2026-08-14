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
    ([string]$manifest.contracts.p14PrecuGcwCompatibilityLevelAuthority)
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
        "p14.gcw-level.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) `
            "p14.gcw-level.source.$name.authenticated"
    }
}

$gcw = [string]$texts.gcw
$rawPlayerLevelPattern = '(?<![A-Za-z0-9_\.])getLevel\s*\(\s*(player|killer|obj_id)\s*\)'
$precuPlayerLevelPattern = 'skill\.getPrecuEncounterDifficulty\s*\(\s*(player|killer|obj_id)\s*\)'
$authoredNpcLevelPattern = '(?<![A-Za-z0-9_\.])getLevel\s*\(\s*npc\s*\)'
Assert-Contract ([regex]::Matches($gcw, $rawPlayerLevelPattern).Count -eq
        [int]$contract.expected.rawPlayerLevelReadsInGcw -and
    [regex]::Matches($gcw, $precuPlayerLevelPattern).Count -eq
        [int]$contract.expected.precuPlayerDifficultyReadsInGcw) `
    "p14.gcw-level.player-ratios.precu-authority"
Assert-Contract ([regex]::Matches($gcw, $authoredNpcLevelPattern).Count -eq
        [int]$contract.expected.authoredNpcLevelReadsInGcw -and
    $gcw.Contains("double npcLev = getLevel(npc);") -and
    $gcw.Contains("double playLev = skill.getPrecuEncounterDifficulty(player);")) `
    "p14.gcw-level.authored-npc-difficulty-preserved"

$release = Get-SourceSlice $gcw `
    "public static boolean releaseGcwPointCredit(" `
    "public static void notifyPvpRegionWatcherOfDeath("
$npcCredit = Get-SourceSlice $gcw `
    "public static int getNpcKillCredit(" `
    "public static int getModifiedGcwPointValue("
Assert-Contract ([regex]::Matches($release, $precuPlayerLevelPattern).Count -eq 6 -and
    [regex]::Matches($release, $rawPlayerLevelPattern).Count -eq 0 -and
    [regex]::Matches($npcCredit, $precuPlayerLevelPattern).Count -eq 1) `
    "p14.gcw-level.compatibility-surfaces-bounded"

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$releaseReferences = 0
$npcCreditReferences = 0
foreach ($file in @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter "*.java" -File))
{
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $releaseReferences += [regex]::Matches($text, '\breleaseGcwPointCredit\s*\(').Count
    $npcCreditReferences += [regex]::Matches($text, '\bgetNpcKillCredit\s*\(').Count
}
Assert-Contract ($releaseReferences -eq
        [int]$contract.expected.releaseGcwPointCreditReferencesInScriptTree -and
    -not ([string]$texts.pclib).Contains("releaseGcwPointCredit")) `
    "p14.gcw-level.release-helper-dormant"
Assert-Contract ($npcCreditReferences -eq
        [int]$contract.expected.getNpcKillCreditReferencesInScriptTree) `
    "p14.gcw-level.npc-credit-reachability-bounded"

$grant = Get-SourceSlice $gcw `
    "public static void _grantGcwPoints(" `
    "public static void doGcwPointCsLogging("
Assert-Contract ($grant.Contains("return;") -and
    -not $grant.Contains("pvpModifyCurrentGcwPoints") -and
    -not $grant.Contains("gcwInvasionCreditForGCW") -and
    -not $grant.Contains("grantGcwPointsToRegion")) `
    "p14.gcw-level.post-nge-point-pipeline-remains-retired"
$modifier = Get-SourceSlice $gcw `
    "public static int getModifiedGcwPointValue(" `
    "public static void registerPvpRegionControllerWithPlanet("
Assert-Contract ($modifier.Contains("buff.isPostNgeBuffProgressionRetired()") -and
    $modifier.Contains("return passedValue;")) `
    "p14.gcw-level.post-nge-buff-multiplier-remains-retired"

$skill = [string]$texts.skill
Assert-Contract ($skill.Contains("public static int getPrecuEncounterDifficulty(") -and
    $skill.Contains("return Math.max(1, getPrecuCombatSkillScore(player));")) `
    "p14.gcw-level.skill-box-adapter-definition"
$factions = [string]$texts.factions
Assert-Contract ($factions.Contains("awardPrecuNpcCombatFaction(") -and
    $factions.Contains("addFactionStanding(player, enemy, gain)") -and
    $factions.Contains("pvpSetPrecuFactionRank(player, rank)")) `
    "p14.gcw-level.precu-faction-authority-preserved"

$rankContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuFactionRankAuthority)) -Raw | ConvertFrom-Json
$gcwRetirementContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuGcwRatingRetirement)) -Raw | ConvertFrom-Json
$buffRetirementContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgeBuffProgressionRetirement)) -Raw | ConvertFrom-Json
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$allowedGcwRetirementStatuses = if ($Expectation -eq "Ready")
{
    @("ready")
}
else
{
    @("implemented-build-pending", "implemented-build-verified-live-pending", "ready")
}
$allowedBuffRetirementStatuses = if ($Expectation -eq "Ready")
{
    @("ready")
}
else
{
    @("implemented-build-pending", "implemented-build-verified-live-pending", "ready")
}
Assert-Contract ([string]$rankContract.status -ceq "ready" -and
    $allowedGcwRetirementStatuses -ccontains [string]$gcwRetirementContract.status -and
    $allowedBuffRetirementStatuses -ccontains [string]$buffRetirementContract.status -and
    $dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq [string]$buffRetirementContract.buildEvidence.directSourceGitlink) `
    "p14.gcw-level.adjacent-authority-continuity"

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.gcw-level.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.gcw-level.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.gcw -match
            '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.gcw-level.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.gcw-level.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.gcw-level.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU GCW compatibility level authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU GCW compatibility level authority contract passed."
