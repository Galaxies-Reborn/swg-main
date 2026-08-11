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

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$surveyPath = Join-Path $source ([string]$contract.sourceFiles.surveyTool)
$resourcePath = Join-Path $source ([string]$contract.sourceFiles.resourceLibrary)
$basePlayerPath = Join-Path $source ([string]$contract.sourceFiles.basePlayer)
Assert-Contract (Test-Path -LiteralPath $surveyPath -PathType Leaf) `
    "p14.resource-sampling-cadence.source.survey-tool.exists"
Assert-Contract (Test-Path -LiteralPath $resourcePath -PathType Leaf) `
    "p14.resource-sampling-cadence.source.resource-library.exists"
Assert-Contract (Test-Path -LiteralPath $basePlayerPath -PathType Leaf) `
    "p14.resource-sampling-cadence.source.base-player.exists"
if (Test-Path -LiteralPath $surveyPath -PathType Leaf)
{
    $survey = Get-Content -LiteralPath $surveyPath -Raw
    $hash = (Get-FileHash -LiteralPath $surveyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.surveyTool) `
        "p14.resource-sampling-cadence.source.survey-tool.authenticated"

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

if ((Test-Path -LiteralPath $surveyPath -PathType Leaf) -and
    (Test-Path -LiteralPath $resourcePath -PathType Leaf) -and
    (Test-Path -LiteralPath $basePlayerPath -PathType Leaf))
{
    $resourceSource = Get-Content -LiteralPath $resourcePath -Raw
    $basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
    $resourceHash = (Get-FileHash -LiteralPath $resourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $basePlayerHash = (Get-FileHash -LiteralPath $basePlayerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Contract ($resourceHash -ceq
            [string]$contract.buildEvidence.sourceSha256.resourceLibrary) `
        "p14.resource-sampling-cadence.source.resource-library.authenticated"
    Assert-Contract ($basePlayerHash -ceq
            [string]$contract.buildEvidence.sourceSha256.basePlayer) `
        "p14.resource-sampling-cadence.source.base-player.authenticated"

    $getSample = Get-SourceSlice $resourceSource `
        "public static int getSample(obj_id user, obj_id tool, String type)" `
        "public static String getResourceContainerTemplate(obj_id typeId)"
    $nodeHandler = Get-SourceSlice $basePlayer `
        "public int handleSurveyNodeChoice(obj_id self, dictionary params)" `
        "public int handleSurveyGambleChoice(obj_id self, dictionary params)"
    $gambleHandler = Get-SourceSlice $basePlayer `
        "public int handleSurveyGambleChoice(obj_id self, dictionary params)" `
        "public int cmdHarvestDNA(obj_id self, obj_id target, String params"
    Assert-Contract (-not [string]::IsNullOrEmpty($getSample) -and
        -not [string]::IsNullOrEmpty($nodeHandler) -and
        -not [string]::IsNullOrEmpty($gambleHandler)) `
        "p14.resource-sampling-cadence.event-method-boundaries"

    Assert-Contract ($resourceSource.Contains(
            "public static final int PRECU_GAMBLE_ACTION_COST = 300;") -and
        ([regex]::Matches($getSample, 'new String\[2\]')).Count -eq 2 -and
        ([regex]::Matches($getSample, 'new String\[3\]')).Count -eq 0 -and
        ([regex]::Matches($getSample, '"handleSurveyNodeChoice"')).Count -eq 1 -and
        ([regex]::Matches($getSample, '"handleSurveyGambleChoice"')).Count -eq 1 -and
        ([regex]::Matches($getSample, 'return SAMPLE_PAUSE_LOOP_EVENT;')).Count -eq 2) `
        "p14.resource-sampling-cadence.precu-two-choice-event-shape"

    $laterEventTokens = @(
        "beast_lib.getBeastOnPlayer",
        "hasCompletedCollectionSlot",
        "modifyCollectionSlotValue",
        "cnode_collection",
        "gnode_collection",
        "sampling_pet_collection",
        "col_pet_resource_sampling",
        "col_resource_",
        "SID_PET_SEARCH_SUCCESS",
        "SID_PET_SEARCH_FAIL",
        "SID_GAMBLE_RARE",
        "gamble == 3",
        "gamble == 4",
        "gamble == 5"
    )
    $laterGetSampleMatches = @($laterEventTokens | Where-Object {
        $getSample.Contains($_)
    })
    Assert-Contract ($laterGetSampleMatches.Count -eq 0) `
        "p14.resource-sampling-cadence.nge-resource-event-authority-retired"

    Assert-Contract ($nodeHandler.Contains("idx != 1") -and
        -not $nodeHandler.Contains("sui.getPlayerId") -and
        -not $nodeHandler.Contains("modifyCollectionSlotValue") -and
        -not $nodeHandler.Contains("hasCompletedCollection") -and
        -not $nodeHandler.Contains("survey_event.gamble") -and
        $nodeHandler.Contains('messageTo(tool, "continueSampleLoop"') -and
        $nodeHandler.Contains('messageTo(tool, "stopSampleEvent"') -and
        $nodeHandler.Contains('utils.setScriptVar(self, "survey_event.location", point)')) `
        "p14.resource-sampling-cadence.precu-node-callback"

    Assert-Contract ($gambleHandler.Contains("idx != 1") -and
        $gambleHandler.Contains(
            "drainAttributes(self, resource.PRECU_GAMBLE_ACTION_COST, 0)") -and
        -not $gambleHandler.Contains("sui.getPlayerId") -and
        -not $gambleHandler.Contains("2000") -and
        -not $gambleHandler.Contains("modifyCollectionSlotValue") -and
        -not $gambleHandler.Contains("hasCompletedCollection") -and
        -not $gambleHandler.Contains("col_resource_") -and
        $gambleHandler.Contains('utils.setScriptVar(self, "survey_event.gamble", 1)') -and
        $gambleHandler.Contains('utils.setScriptVar(self, "survey_event.gamble", 2)')) `
        "p14.resource-sampling-cadence.precu-gamble-callback"

    $eventSurface = $resourceSource + "`n" + $basePlayer + "`n" + $survey
    Assert-Contract (([regex]::Matches($eventSurface,
            'SAMPLE_PAUSE_LOOP_EVENT')).Count -eq
            [int]$contract.expected.samplePauseReferences -and
        ([regex]::Matches($eventSurface, '"handleSurveyNodeChoice"')).Count -eq 1 -and
        ([regex]::Matches($eventSurface, '"handleSurveyGambleChoice"')).Count -eq 1 -and
        ([regex]::Matches($basePlayer,
            'public int handleSurveyNodeChoice\(')).Count -eq 1 -and
        ([regex]::Matches($basePlayer,
            'public int handleSurveyGambleChoice\(')).Count -eq 1) `
        "p14.resource-sampling-cadence.complete-event-callback-inventory"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    $dsrcCommit = (& git -C (Join-Path $source "dsrc") rev-parse HEAD).Trim()
    $srcCommit = (& git -C (Join-Path $source "src") rev-parse HEAD).Trim()
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.resource-sampling-cadence.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        $srcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq $dsrcCommit -and
        [string]$srcPin[0].commit -ceq $srcCommit -and
        $dsrcCommit -ceq [string]$contract.buildEvidence.directSourceGitlink -and
        $srcCommit -ceq [string]$contract.buildEvidence.nativeSourceGitlink -and
        [string]$contract.buildEvidence.parentCommitAtDeployment -match '^[a-f0-9]{40}$') `
        "p14.resource-sampling-cadence.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.surveyTool -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.resourceLibrary -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.basePlayer -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.resource-sampling-cadence.live-evidence"

    $container = [string]$contract.runtimeEvidence.container
    $containerState = (& docker inspect $container --format `
        '{{.State.StartedAt}}|{{.State.Status}}|{{.State.Health.Status}}').Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and
        $containerState -ceq (([string]$contract.runtimeEvidence.containerStartedAt) +
            "|running|healthy")) `
        "p14.resource-sampling-cadence.live-container-health"

    $sourceCount = [int]((& docker exec $container sh -lc `
        "find /swg-precu-source/dsrc/sku.0/sys.server/compiled/game/script -type f -name '*.java' | wc -l").Trim())
    $classCount = [int]((& docker exec $container sh -lc `
        "find /swg-precu/data/sku.0/sys.server/compiled/game/script -type f -name '*.class' | wc -l").Trim())
    Assert-Contract ($sourceCount -eq [int]$contract.runtimeEvidence.javaSources -and
        $classCount -eq [int]$contract.runtimeEvidence.javaClasses) `
        "p14.resource-sampling-cadence.live-java-inventory"

    $binaryPath = [string]$contract.runtimeEvidence.liveBinaryPath
    $binaryHash = ((& docker exec $container sha256sum $binaryPath).Trim() -split '\s+')[0]
    $binaryStat = ((& docker exec $container stat -c '%s|%i' $binaryPath).Trim() -split '\|')
    $binaryNotes = (& docker exec $container readelf -n $binaryPath | Out-String)
    Assert-Contract ($LASTEXITCODE -eq 0 -and
        $binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $binaryHash -ceq [string]$contract.runtimeEvidence.liveBinarySha256 -and
        [int64]$binaryStat[0] -eq [int64]$contract.runtimeEvidence.liveBinarySize -and
        [int64]$binaryStat[1] -eq [int64]$contract.runtimeEvidence.liveBinaryInode -and
        $binaryNotes.Contains([string]$contract.buildEvidence.serverBinaryBuildId) -and
        $binaryNotes.Contains([string]$contract.runtimeEvidence.liveBinaryBuildId)) `
        "p14.resource-sampling-cadence.live-binary"

    $gamePids = @(& docker exec $container pgrep -x SwgGameServer |
        Where-Object { $_ -match '^\d+$' })
    $planetPids = @(& docker exec $container pgrep -x PlanetServer |
        Where-Object { $_ -match '^\d+$' })
    $mappedGameProcesses = 0
    $mapEntries = 0
    foreach ($gamePid in $gamePids)
    {
        $mappedPath = (& docker exec $container readlink "/proc/$gamePid/exe").Trim()
        if ($mappedPath -ceq $binaryPath) { $mappedGameProcesses++ }
        $entries = (& docker exec $container sh -lc `
            "grep -Fc '$binaryPath' /proc/$gamePid/maps").Trim()
        if ($entries -match '^\d+$') { $mapEntries += [int]$entries }
    }
    Assert-Contract ($gamePids.Count -eq
            [int]$contract.runtimeEvidence.processCounts.SwgGameServer -and
        $planetPids.Count -eq [int]$contract.runtimeEvidence.processCounts.PlanetServer -and
        $mappedGameProcesses -eq
            [int]$contract.runtimeEvidence.liveGameProcessesMappedBuiltBinary -and
        $mapEntries -eq [int]$contract.runtimeEvidence.liveBinaryMapEntries -and
        $gamePids -contains ([string]$contract.runtimeEvidence.liveGameProcessPid)) `
        "p14.resource-sampling-cadence.live-process-topology"

    $freshLogs = @(& docker logs --since `
        ([string]$contract.runtimeEvidence.containerStartedAt) $container 2>&1)
    $readyMarkers = @($freshLogs | Where-Object {
        $_ -match '^\s*\[exec\] Cluster swg is ready for players\.\s*$'
    })
    $flaggedLogs = @($freshLogs | Where-Object {
        $_ -match '(?i)fatal|severe|exception|\berror\b|ConGenericMessage constructed with empty message|undefined symbol|ABI|ORA-[0-9]+|segmentation fault|core dump'
    })
    Assert-Contract ($freshLogs.Count -ge [int]$contract.runtimeEvidence.postStartLogLines -and
        $readyMarkers.Count -eq [int]$contract.runtimeEvidence.playerReadyMarkers -and
        $flaggedLogs.Count -eq
            [int]$contract.runtimeEvidence.structuredLogFatalSevereExceptionCount) `
        "p14.resource-sampling-cadence.post-start-log-audit"

    foreach ($property in $contract.sourceFiles.PSObject.Properties)
    {
        $relativePath = ([string]$property.Value).Replace("\", "/")
        & docker exec $container cmp -s "/swg-precu-source/$relativePath" `
            "/swg-precu/$relativePath"
        Assert-Contract ($LASTEXITCODE -eq 0) `
            "p14.resource-sampling-cadence.source-work-parity.$($property.Name)"
    }

    $classRoot = "/swg-precu/data/sku.0/sys.server/compiled/game"
    $classPaths = [ordered]@{
        surveyTool = "$classRoot/script/item/survey_tool/survey_tool_script.class"
        resourceLibrary = "$classRoot/script/library/resource.class"
        basePlayer = "$classRoot/script/player/base/base_player.class"
    }
    foreach ($name in $classPaths.Keys)
    {
        $classHash = ((& docker exec $container sha256sum $classPaths[$name]).Trim() -split '\s+')[0]
        $classBytes = [int64]((& docker exec $container stat -c '%s' $classPaths[$name]).Trim())
        Assert-Contract ($LASTEXITCODE -eq 0 -and
            $classHash -ceq [string]$contract.buildEvidence.compiledClassSha256.$name -and
            $classBytes -eq [int64]$contract.buildEvidence.compiledClassBytes.$name) `
            "p14.resource-sampling-cadence.live-bytecode.$name"
    }

    $resourceBytecode = (& docker exec $container javap -classpath $classRoot -c -p `
        script.library.resource | Out-String)
    $sampleBytecode = Get-SourceSlice $resourceBytecode `
        "public static int getSample(script.obj_id, script.obj_id, java.lang.String)" `
        "public static java.lang.String getResourceContainerTemplate(script.obj_id)"
    Assert-Contract (-not [string]::IsNullOrEmpty($sampleBytecode) -and
        $sampleBytecode.Contains("handleSurveyNodeChoice") -and
        $sampleBytecode.Contains("handleSurveyGambleChoice") -and
        -not $sampleBytecode.Contains("beast_lib") -and
        -not $sampleBytecode.Contains("hasCompletedCollectionSlot") -and
        -not $sampleBytecode.Contains("SID_PET_SEARCH") -and
        -not $sampleBytecode.Contains("SID_GAMBLE_RARE")) `
        "p14.resource-sampling-cadence.deployed-resource-event-bytecode"

    $baseBytecode = (& docker exec $container javap -classpath $classRoot -c -p `
        script.player.base.base_player | Out-String)
    $callbackBytecode = Get-SourceSlice $baseBytecode `
        "public int handleSurveyNodeChoice(script.obj_id, script.dictionary)" `
        "public int cmdHarvestDNA(script.obj_id, script.obj_id, java.lang.String, float)"
    Assert-Contract (-not [string]::IsNullOrEmpty($callbackBytecode) -and
        $callbackBytecode -match '\bsipush\s+300\b' -and
        $callbackBytecode -notmatch '\bsipush\s+2000\b' -and
        -not $callbackBytecode.Contains("getPlayerId") -and
        -not $callbackBytecode.Contains("modifyCollectionSlotValue") -and
        -not $callbackBytecode.Contains("hasCompletedCollection")) `
        "p14.resource-sampling-cadence.deployed-callback-bytecode"
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
