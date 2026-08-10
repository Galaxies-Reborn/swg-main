[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14ChroniclesScriptLifecycleRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Get-TextSha256([string]$Text)
{
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash(
            $utf8NoBom.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    Assert-Contract ($start -ge 0) "Missing source surface: $Signature"
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    Assert-Contract ($brace -ge 0) "Missing opening brace: $Signature"
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    throw "Missing closing brace: $Signature"
}

$paths = [ordered]@{}
$texts = @{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $root ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $paths[$property.Name] -PathType Leaf) `
        "Missing Chronicles source: $($property.Name)"
    $texts[$property.Name] = Get-Content -LiteralPath $paths[$property.Name] -Raw
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq
        [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value) `
        "Chronicles source hash drifted: $($property.Name)"
}

$saga = [string]$texts.playerSaga
$storyteller = [string]$texts.storyteller
$attach = Get-BracedSurface $saga "public int OnAttach(obj_id self)"
$retireCallback = Get-BracedSurface $saga `
    "public void retireChroniclesPlayerCallback(obj_id self)"
$initialize = Get-BracedSurface $saga "public int OnInitialize(obj_id self)"
$clientReady = Get-BracedSurface $saga `
    "public int OnNewbieTutorialResponse(obj_id self, String action)"
$abandon = Get-BracedSurface $saga `
    "public int OnAbandonPlayerQuest(obj_id self, obj_id questHolocron)"

Assert-Contract ($attach.Contains("return SCRIPT_CONTINUE;") -and
    -not $attach.Contains("attachScript(") -and
    -not $attach.Contains("messageTo(") -and
    -not $attach.Contains("grantSkill(")) `
    "Player saga OnAttach is not inert."
Assert-Contract ($retireCallback.Contains("pgc_quests.retireChroniclesPlayerProgressionState(self);") -and
    $retireCallback.Contains('detachScript(self, "player.player_saga_quest");') -and
    $initialize.Contains("retireChroniclesPlayerCallback(self);") -and
    $clientReady.Contains("retireChroniclesPlayerCallback(self);") -and
    -not $clientReady.Contains("handleChroniclesTermsOfService") -and
    -not $clientReady.Contains("handleChroniclesReserveReminder") -and
    -not $clientReady.Contains("chroniclesTermsOfServiceShown")) `
    "Player saga initialization/client-ready retirement drifted."

$retirementGuard = $abandon.IndexOf(
    "if (pgc_quests.isRetiredChroniclesPlayerProgression())",
    [StringComparison]::Ordinal)
$abandonMutation = $abandon.IndexOf("pgc_quests.setQuestAbandoned(",
    [StringComparison]::Ordinal)
Assert-Contract ($retirementGuard -ge 0 -and $abandonMutation -gt $retirementGuard -and
    $abandon.Contains("pgc_quests.retireChroniclesPlayerProgressionState(self);") -and
    $abandon.Contains('detachScript(self, "player.player_saga_quest");') -and
    $abandon.Substring($retirementGuard, $abandonMutation - $retirementGuard).
        Contains("return SCRIPT_CONTINUE;") -and
    [int]$contract.expected.unguardedChroniclesAbandonMutations -eq 0) `
    "Chronicles abandonment mutation is not dominated by the retirement guard."

Assert-Contract ([regex]::Matches($saga,
        [regex]::Escape('detachScript(self, "player.player_saga_quest")')).Count -eq
        [int]$contract.expected.playerSagaDetachBoundaries -and
    [regex]::Matches($storyteller,
        [regex]::Escape('detachScript(self, "systems.storyteller.storyteller_commands")')).Count -eq
        [int]$contract.expected.storytellerDetachBoundaries) `
    "Chronicles/Storyteller detach boundary drifted."

$callbackRecords = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading `
    ([string]$contract.abandonCallbackInventory.pattern) $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
        "Invalid OnAbandonPlayerQuest inventory line."
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $callbackRecords.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
}
$callbackRecords = @($callbackRecords | Sort-Object)
$callbackPaths = @($callbackRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Invalid callback record."
    $Matches[1]
} | Sort-Object -Unique)
$expectedPaths = @($contract.abandonCallbackInventory.sourcePaths |
    ForEach-Object { [string]$_ } | Sort-Object)
$productionCallbacks = @($callbackRecords | Where-Object { $_ -notmatch '^test/' })
$testCallbacks = @($callbackRecords | Where-Object { $_ -match '^test/' })
Assert-Contract ($callbackRecords.Count -eq [int]$contract.expected.abandonCallbacks -and
    $productionCallbacks.Count -eq [int]$contract.expected.abandonProductionCallbacks -and
    $testCallbacks.Count -eq [int]$contract.expected.abandonTestCallbacks -and
    ($callbackPaths -join "`n") -ceq ($expectedPaths -join "`n") -and
    (Get-TextSha256 ($callbackRecords -join "`n")) -ceq
        [string]$contract.abandonCallbackInventory.inventorySha256 -and
    (Get-TextSha256 ($callbackPaths -join "`n")) -ceq
        [string]$contract.abandonCallbackInventory.sourceSetSha256) `
    "Complete OnAbandonPlayerQuest inventory drifted."

$playerSagaAttachments = @(& rg -n --no-heading `
    'attachScript\s*\([^;\r\n]*"player\.player_saga_quest"' $scriptRoot --glob "*.java")
$storytellerAttachments = @(& rg -n --no-heading `
    'attachScript\s*\([^;\r\n]*"systems\.storyteller\.storyteller_commands"' `
    $scriptRoot --glob "*.java")
Assert-Contract ($playerSagaAttachments.Count -eq
        [int]$contract.expected.activePlayerSagaAttachmentCalls -and
    $storytellerAttachments.Count -eq
        [int]$contract.expected.compatibilityStorytellerAttachmentCalls -and
    @($storytellerAttachments | Where-Object {
        $_ -match 'player\\live_conversions\.java:'
    }).Count -eq 1 -and
    ([string]$texts.basePlayer).Contains('detachScript(self, "player.player_saga_quest")') -and
    ([string]$texts.liveConversions).Contains('detachScript(self, "player.live_conversions")')) `
    "Chronicles/Storyteller attachment frontier drifted."

$nativeRegistrationCount = [regex]::Matches([string]$texts.scriptFunctionTable,
    '\{Scripting::TRIG_ON_ABANDON_PLAYER_QUEST,\s*"OnAbandonPlayerQuest",\s*"O"\}').Count
$nativeDispatcherCount = [regex]::Matches([string]$texts.creatureController,
    'trigAllScripts\(Scripting::TRIG_ON_ABANDON_PLAYER_QUEST, params\)').Count
Assert-Contract ($nativeRegistrationCount -eq
        [int]$contract.expected.nativeAbandonTriggerRegistrations -and
    $nativeDispatcherCount -eq [int]$contract.expected.nativeAbandonDispatchers -and
    [bool]$contract.expected.retainedGroundQuestLifecycleUnaffected) `
    "Native Chronicles abandonment boundary drifted."

$dataGrantContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14DataGrantPersistenceClosure)) -Raw | ConvertFrom-Json
Assert-Contract ([string]$dataGrantContract.status -ceq "ready" -and
    [bool]$contract.expected.dataGrantDependencyReady) `
    "Chronicles data-grant dependency is not Ready."

$obsoletePatch = Join-Path $restorationRoot `
    "patches/dsrc/167-p14-chronicles-script-lifecycle-retirement.patch"
Assert-Contract (-not (Test-Path -LiteralPath $obsoletePatch) -and
    [int]$contract.expected.obsoleteOverlayPatchFiles -eq 0) `
    "Obsolete Chronicles overlay patch still exists."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        [bool]$contract.runtimeEvidence.clientResponsive -and
        [int]$contract.runtimeEvidence.hostArtifactOrStagingDirectories -eq 0 -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Chronicles retirement lacks complete Ready evidence."

    $container = [string]$contract.runtimeEvidence.container
    $health = (& docker inspect $container --format '{{.State.Health.Status}}').Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $health -ceq "healthy") `
        "Chronicles runtime container is not healthy."
    foreach ($property in $contract.sourceFiles.PSObject.Properties)
    {
        $relativePath = ([string]$property.Value).Replace("\", "/")
        & docker exec $container cmp -s "/swg-precu-source/$relativePath" `
            "/swg-precu/$relativePath"
        Assert-Contract ($LASTEXITCODE -eq 0) `
            "Chronicles source/work parity failed: $($property.Name)"
    }

    $classPaths = [ordered]@{
        playerSaga = "/swg-precu/data/sku.0/sys.server/compiled/game/script/player/player_saga_quest.class"
        storyteller = "/swg-precu/data/sku.0/sys.server/compiled/game/script/systems/storyteller/storyteller_commands.class"
    }
    foreach ($name in $classPaths.Keys)
    {
        $hash = ((& docker exec $container sha256sum $classPaths[$name]).Trim() -split '\s+')[0]
        $bytes = [int]((& docker exec $container stat -c '%s' $classPaths[$name]).Trim())
        Assert-Contract ($hash -ceq
                [string]$contract.buildEvidence.classSha256.PSObject.Properties[$name].Value -and
            $bytes -eq [int]$contract.buildEvidence.classBytes.PSObject.Properties[$name].Value) `
            "Chronicles deployed bytecode drifted: $name"
    }

    $serverPid = (& docker exec $container pgrep -n SwgGameServer).Trim()
    $serverExe = (& docker exec $container readlink -f "/proc/$serverPid/exe").Trim()
    $binaryHash = ((& docker exec $container sha256sum $serverExe).Trim() -split '\s+')[0]
    $buildLine = @(& docker exec $container readelf -n $serverExe | Select-String 'Build ID:')
    $buildId = ($buildLine[0].Line -replace '^.*Build ID:\s*', '').Trim()
    Assert-Contract ($binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $buildId -ceq [string]$contract.buildEvidence.serverBinaryBuildId) `
        "Chronicles deployed server binary drifted."

    $client = Get-Process -Id ([int]$contract.runtimeEvidence.clientProcessId) `
        -ErrorAction SilentlyContinue
    Assert-Contract ($null -ne $client -and $client.Responding -and
        $client.ProcessName -ceq [string]$contract.runtimeEvidence.clientProcessName) `
        "Chronicles client is not responsive."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains
        [string]$contract.status) "Chronicles source status is invalid."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("overlayPatch") -and
    -not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Chronicles contract references retired artifact/staging evidence."
Write-Host "Publish 14.1 Chronicles script lifecycle retirement contract passed."
