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
    ([string]$manifest.contracts.p14PrecuMetricsLevelAuthority)
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
    if ([string]::IsNullOrEmpty($EndMarker)) { return $Text.Substring($start) }
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
        "p14.metrics-level.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) `
            "p14.metrics-level.source.$name.authenticated"
    }
}

$metrics = [string]$texts.metrics
$rawPlayerLevelPattern = '(?<![A-Za-z0-9_\.])getLevel\s*\(\s*(member|killCredit|player)\s*\)'
$precuPlayerPattern = 'skill\.getPrecuEncounterDifficulty\s*\(\s*(member|killCredit|player)\s*\)'
$targetLevelPattern = '(?<![A-Za-z0-9_\.])getLevel\s*\(\s*target\s*\)'
Assert-Contract ([regex]::Matches($metrics, $rawPlayerLevelPattern).Count -eq
        [int]$contract.expected.rawPlayerLevelReadsInMetrics -and
    [regex]::Matches($metrics, $precuPlayerPattern).Count -eq
        [int]$contract.expected.precuPlayerDifficultyReadsInMetrics) `
    "p14.metrics-level.player-fields.precu-authority"
Assert-Contract ([regex]::Matches($metrics, $targetLevelPattern).Count -eq
        [int]$contract.expected.authoredTargetLevelReadsInMetrics -and
    $metrics.Contains("int targetLevel = getLevel(target);")) `
    "p14.metrics-level.authored-target-difficulty-preserved"
Assert-Contract ([regex]::Matches($metrics,
        'skill\.getGroupLevel\s*\(\s*killCredit\s*\)').Count -eq
        [int]$contract.expected.precuGroupDifficultyReadsInMetrics) `
    "p14.metrics-level.group-difficulty-preserved"

$killMetrics = Get-SourceSlice $metrics `
    "public static void doKillMetrics(" `
    "public static void doXpRateMetrics("
$xpMetrics = Get-SourceSlice $metrics `
    "public static void doXpRateMetrics(" `
    "public static void doQuestMetrics("
$questMetrics = Get-SourceSlice $metrics `
    "public static void doQuestMetrics(" `
    ""
Assert-Contract ([regex]::Matches($killMetrics, $precuPlayerPattern).Count -eq 2 -and
    [regex]::Matches($xpMetrics, $precuPlayerPattern).Count -eq 1 -and
    [regex]::Matches($questMetrics, $precuPlayerPattern).Count -eq 1) `
    "p14.metrics-level.entrypoint-field-mapping"
Assert-Contract ($killMetrics.Contains("xp.VAR_DAMAGE_COUNT") -and
    $killMetrics.Contains("xp.VAR_DAMAGE_TALLY") -and
    $killMetrics.Contains("dmgPercent") -and
    $xpMetrics.Contains("xpRateMetrics.") -and
    $xpMetrics.Contains("xpTotal") -and
    $questMetrics.Contains("questGetQuestName(questId)") -and
    [regex]::Matches($killMetrics + $xpMetrics + $questMetrics,
        '\blogBalance\s*\(').Count -eq 3) `
    "p14.metrics-level.schemas-and-accounting-preserved"

$xp = [string]$texts.xp
$basePlayer = [string]$texts.basePlayer
Assert-Contract ($xp.Contains("metrics.doXpRateMetrics(target, xp_type, amt);") -and
    $xp.Contains("metrics.doKillMetrics(killCredit, target);") -and
    $basePlayer.Contains("metrics.doQuestMetrics(self, questCrc, questLevel, questTier, experienceType, experienceAmount);")) `
    "p14.metrics-level.production-call-sites-preserved"
$metricEntrypointCount = [regex]::Matches($metrics,
    'public static void do(Kill|XpRate|Quest)Metrics\s*\(').Count
Assert-Contract ($metricEntrypointCount -eq
        [int]$contract.expected.productionMetricEntrypoints) `
    "p14.metrics-level.production-entrypoints-preserved"

$skill = [string]$texts.skill
Assert-Contract ($skill.Contains("public static int getPrecuEncounterDifficulty(") -and
    $skill.Contains("return Math.max(1, getPrecuCombatSkillScore(player));") -and
    $skill.Contains("return getPrecuGroupCombatDifficulty(objPlayer);")) `
    "p14.metrics-level.skill-box-adapters"
Assert-Contract ([string]$texts.attributes -match
    '(?m)^sku\.0/sys\.server/compiled/game/script/library/metrics\.java -text\r?$') `
    "p14.metrics-level.no-line-ending-bloat-policy"

$encounterContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuEncounterDifficultyAuthority)) -Raw | ConvertFrom-Json
$xpContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuCombatXpAuthority)) -Raw | ConvertFrom-Json
$xpStatus = [string]$xpContract.status
if ($Expectation -eq "Source" -and $xpStatus -ceq "implemented-build-pending")
{
    & (Join-Path $PSScriptRoot "Test-P14PrecuCombatXpAuthority.ps1") `
        -SourceRoot $source
}
Assert-Contract ([string]$encounterContract.status -ceq "ready" -and
    ($xpStatus -ceq "ready" -or
        ($Expectation -eq "Source" -and
            $xpStatus -ceq "implemented-build-pending"))) `
    "p14.metrics-level.adjacent-authority-continuity"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.metrics-level.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.metrics-level.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.metrics -match
            '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.metrics-level.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.metrics-level.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.metrics-level.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU metrics level authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU metrics level authority contract passed."
