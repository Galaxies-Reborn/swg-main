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
    ([string]$manifest.contracts.p14PrecuResourceSamplingCadenceAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

$surveyPath = Join-Path $source ([string]$contract.sourceFiles.surveyTool)
Assert-Contract (Test-Path -LiteralPath $surveyPath -PathType Leaf) `
    "p14.resource-sampling-cadence.source.exists"
if (Test-Path -LiteralPath $surveyPath -PathType Leaf)
{
    $survey = Get-Content -LiteralPath $surveyPath -Raw
    $hash = (Get-FileHash -LiteralPath $surveyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.surveyTool) `
        "p14.resource-sampling-cadence.source.authenticated"

    $fixedDelayPattern = '(?s)public int getSurveyToolDelay\(obj_id player\).*?\{\s*return SURVEY_TOOL_DELAY;\s*\}'
    Assert-Contract ($survey.Contains("public static final int SURVEY_TOOL_DELAY = 25;") -and
        -not $survey.Contains("MIN_SURVEY_TOOL_DELAY") -and
        -not $survey.Contains("expertise_resource_sampling_time_decrease") -and
        [regex]::IsMatch($survey, $fixedDelayPattern)) `
        "p14.resource-sampling-cadence.fixed-precu-delay"

    $delayCalls = ([regex]::Matches($survey, 'getSurveyToolDelay\(player\)')).Count
    Assert-Contract ($delayCalls -eq [int]$contract.expected.delayHelperCallSites -and
        $survey.Contains('messageTo(self, "samplingEffect", params, getSurveyToolDelay(player), false)') -and
        $survey.Contains('messageTo(self, "resourceHarvest", params, getSurveyToolDelay(player) + 2, false)') -and
        $survey.Contains('"surveying.outstandingHarvestMessage"')) `
        "p14.resource-sampling-cadence.loop-and-watchdog-preserved"

    Assert-Contract ($survey.Contains("PRECU_SAMPLE_ACTION_BASE_COST = 124") -and
        $survey.Contains("PRECU_SAMPLE_QUICKNESS_DIVISOR = 12.5f") -and
        $survey.Contains("getAttrib(player, QUICKNESS)") -and
        $survey.Contains("Math.max(0, PRECU_SAMPLE_ACTION_BASE_COST") -and
        $survey.Contains("drainAttributes(player, actioncost, 0)") -and
        $survey.Contains("resource.getSample(player, self, resource_type)")) `
        "p14.resource-sampling-cadence.precu-action-and-results-preserved"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.resource-sampling-cadence.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.resource-sampling-cadence.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.surveyTool -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.resource-sampling-cadence.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.resource-sampling-cadence.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.resource-sampling-cadence.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU resource sampling cadence authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU resource sampling cadence authority contract passed."
