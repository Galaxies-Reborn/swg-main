[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Source", "Ready")][string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrcRoot = Join-Path $root "dsrc"
$srcRoot = Join-Path $root "src"
$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuVillageQuestAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
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
    if ($start -lt 0) { throw "Missing source surface: $Signature" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { throw "Missing opening brace: $Signature" }
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

function Get-Inventory([string]$Pattern)
{
    $records = [Collections.Generic.List[string]]::new()
    foreach ($line in @(& rg -n --no-heading $Pattern $scriptRoot --glob "*.java"))
    {
        Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
            "Could not parse Village inventory line: $line"
        $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
        Assert-Contract ($absolutePath.StartsWith(
                $scriptRoot + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) `
            "Village inventory escaped the Java source root: $absolutePath"
        $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
        $records.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
    }
    Assert-Contract ($LASTEXITCODE -le 1) "ripgrep failed while inventorying Village authority."
    return @($records | Sort-Object)
}

$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$nativePin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$dsrcCommit = (& git -C $dsrcRoot rev-parse HEAD).Trim()
$nativeCommit = (& git -C $srcRoot rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $dsrcPin.Count -eq 1 -and $nativePin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq $dsrcCommit -and
    [string]$nativePin[0].commit -ceq $nativeCommit -and
    $dsrcCommit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
    $nativeCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "Village authority is not pinned to the checked-out direct source."

$paths = [ordered]@{}
$texts = @{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $root ([string]$property.Value)
    $paths[$property.Name] = $path
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "Village source is missing: $($property.Name)"
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-Contract ($actualHash -ceq [string]$contract.buildEvidence.sourceSha256.($property.Name)) `
        "Village source hash drifted: $($property.Name)"
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
}

Assert-Contract ([string]$texts.attributes -match
    '(?m)^sku\.0/sys\.server/compiled/game/script/library/fs_quests\.java -text whitespace=cr-at-eol\r?$') `
    "Village source lost its narrow legacy line-ending exception."

$callbackRecords = @(Get-Inventory ([string]$contract.callbackInventory.pattern))
$callbackPaths = @($callbackRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Could not isolate Village callback path: $_"
    $Matches[1]
} | Sort-Object -Unique)
$expectedCallbackPaths = @($contract.callbackInventory.sourcePaths |
    ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract ($callbackRecords.Count -eq [int]$contract.callbackInventory.handlers -and
    $callbackRecords.Count -eq [int]$contract.expected.callbackHandlers -and
    $callbackPaths.Count -eq [int]$contract.callbackInventory.sourceFiles -and
    ($callbackPaths -join "`n") -ceq ($expectedCallbackPaths -join "`n") -and
    (Get-TextSha256 ($callbackRecords -join "`n")) -ceq
        [string]$contract.callbackInventory.inventorySha256 -and
    (Get-TextSha256 ($callbackPaths -join "`n")) -ceq
        [string]$contract.callbackInventory.sourceSetSha256) `
    "OnForceSensitiveQuestCompleted inventory drifted."

$consumerRecords = @(Get-Inventory ([string]$contract.eligibilityConsumerInventory.pattern))
$consumerPaths = @($consumerRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Could not isolate Village consumer path: $_"
    $Matches[1]
} | Sort-Object -Unique)
$consumerContent = @($consumerPaths | ForEach-Object {
    "$_=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scriptRoot $_)).Hash.ToLowerInvariant()
}) -join "`n"
Assert-Contract ($consumerRecords.Count -eq
        [int]$contract.eligibilityConsumerInventory.callSites -and
    $consumerPaths.Count -eq [int]$contract.eligibilityConsumerInventory.sourceFiles -and
    (Get-TextSha256 ($consumerRecords -join "`n")) -ceq
        [string]$contract.eligibilityConsumerInventory.inventorySha256 -and
    (Get-TextSha256 ($consumerPaths -join "`n")) -ceq
        [string]$contract.eligibilityConsumerInventory.sourceSetSha256 -and
    (Get-TextSha256 $consumerContent) -ceq
        [string]$contract.eligibilityConsumerInventory.sourceContentSha256) `
    "Village eligibility consumer inventory drifted."

$fsQuests = [string]$texts.fsQuests
$eligibility = Get-BracedSurface $fsQuests `
    "public static boolean isVillageEligible(obj_id player)"
$makeEligible = Get-BracedSurface $fsQuests `
    "public static boolean makeVillageEligible(obj_id player)"
$forbiddenEligibility = @('getLevel(', 'getSkillTemplate(', 'setSkillTemplate(',
    'expertise.', 'profession.')
Assert-Contract ($eligibility.Contains("if (!isIdValid(player))") -and
    $eligibility.Contains("return false;") -and
    $eligibility.Contains("return hasObjVar(player, VAR_VILLAGE_ELIGIBLE);") -and
    @($forbiddenEligibility | Where-Object { $eligibility.Contains($_) }).Count -eq 0 -and
    $makeEligible.Contains("setObjVar(player, VAR_VILLAGE_ELIGIBLE, 1);") -and
    [string]$contract.expected.villageEligibilityFlag -ceq "fs_quest.village_eligible" -and
    [bool]$contract.expected.invalidPlayerFailsClosed) `
    "Village admission is not owned by its authenticated PRE-CU flag."

$fsKickoff = [string]$texts.fsKickoff
$kickoffActivation = Get-BracedSurface $fsKickoff "public int OnQuestActivated(obj_id self, int questRow)"
Assert-Contract ($kickoffActivation.Contains('quests.getQuestId("fs_village_elder")') -and
    $kickoffActivation.Contains("fs_quests.makeVillageEligible(self);") -and
    $kickoffActivation.Contains("setJediState(self, JEDI_STATE_FORCE_SENSITIVE);") -and
    $kickoffActivation.Contains('grantSkill(self, "force_title_jedi_novice");')) `
    "Village elder activation no longer establishes Publish 14.1 Village state."

$fsCsCallback = Get-BracedSurface ([string]$texts.fsCsPlayer) `
    "public int OnForceSensitiveQuestCompleted(obj_id self, String questName, boolean succeeded)"
$waitCallback = Get-BracedSurface ([string]$texts.legacyWaitForTasks) `
    "public int OnForceSensitiveQuestCompleted(obj_id self, String questName, boolean succeeded)"
$progressionPatterns = @('\bgrantSkill\s*\(', '\brevokeSkill\s*\(',
    '\bsetJediState\s*\(', '\bunlockBranch\s*\(', '\bgetLevel\s*\(',
    '\bgetSkillTemplate\s*\(', '\bsetSkillTemplate\s*\(', '\bexpertise\.',
    '\bprofession\.')
$progressionMatches = @($progressionPatterns | Where-Object {
    [regex]::IsMatch($fsCsCallback + "`n" + $waitCallback, $_)
})
Assert-Contract ($fsCsCallback.Contains('questName.equals("fs_cs_kill5_guards")') -and
    $fsCsCallback.Contains('quests.isActive("fs_cs_intro", thisGuy)') -and
    $fsCsCallback.Contains('new string_id("fs_quest_village", "groupmate_powered_down")') -and
    [regex]::Matches($waitCallback, 'quests\.complete\s*\(').Count -eq
        [int]$contract.expected.legacyCompositeCompletionCallSites -and
    $waitCallback.Contains('quests.isMyQuest(quests.getQuestId(questName), "quest.task.wait_for_tasks")') -and
    $progressionMatches.Count -eq [int]$contract.expected.callbackProgressionMutations) `
    "Force-sensitive completion callbacks gained non-PRE-CU progression authority."

$attachLines = @(& rg -n --no-heading `
    '\battachScript\s*\([^;\r\n]*"systems\.fs_quest\.fs_cs_player"' `
    $scriptRoot --glob "*.java")
Assert-Contract ($LASTEXITCODE -le 1 -and
    $attachLines.Count -eq [int]$contract.expected.fsCounterstrikeProductionAttachCallSites -and
    @($attachLines | Where-Object { $_ -match 'library\\fs_counterstrike\.java:' }).Count -eq 1 -and
    @($attachLines | Where-Object { $_ -match 'conversation\\combat_quest_p3\.java:' }).Count -eq 1) `
    "Counterstrike player-script attachment inventory drifted."

$questRows = @(Get-Content -LiteralPath $paths.questTable)
$counterstrikeRows = @($questRows | Where-Object { $_ -match '^fs_cs_' })
$waitRows = @($questRows | Where-Object {
    $_ -match '\tquest\.task\.wait_for_tasks\t'
})
Assert-Contract ($counterstrikeRows.Count -eq [int]$contract.authoredQuestRows.counterstrikeRows -and
    (Get-TextSha256 ($counterstrikeRows -join "`n")) -ceq
        [string]$contract.authoredQuestRows.counterstrikeRowsSha256 -and
    $waitRows.Count -eq [int]$contract.authoredQuestRows.legacyWaitForTasksRows -and
    (Get-TextSha256 ($waitRows -join "`n")) -ceq
        [string]$contract.authoredQuestRows.legacyWaitForTasksRowsSha256) `
    "Authored Village counterstrike or composite-defense quest rows drifted."

$quests = [string]$texts.quests
$productionDispatches = [regex]::Matches($quests,
    'script_entry\.runScripts\("OnForceSensitiveQuestCompleted", params\);').Count
$allDispatchLines = @(& rg -n --no-heading `
    'script_entry\.runScripts.*OnForceSensitiveQuestCompleted' `
    $scriptRoot --glob "*.java")
Assert-Contract ($LASTEXITCODE -le 1 -and
    $productionDispatches -eq [int]$contract.expected.javaProductionDispatchers -and
    $allDispatchLines.Count -eq
        ([int]$contract.expected.javaProductionDispatchers +
            [int]$contract.expected.javaDeveloperDispatchers) -and
    @($allDispatchLines | Where-Object { $_ -match 'working\\justin\\utilities\.java:' }).Count -eq
        [int]$contract.expected.javaDeveloperDispatchers) `
    "Force-sensitive Java dispatcher inventory drifted."

$nativeRegistrations = [regex]::Matches([string]$texts.scriptFunctionTable,
    '\{Scripting::TRIG_FSQUEST_COMPLETED,\s*"OnForceSensitiveQuestCompleted",\s*"sb"\}').Count
Assert-Contract ($nativeRegistrations -eq [int]$contract.expected.nativeTriggerRegistrations) `
    "Native Force-sensitive completion trigger registration drifted."

$groundWait = [string]$texts.groundWaitForTasks
$groundDetach = Get-BracedSurface $groundWait "public int OnDetach(obj_id self)"
Assert-Contract ($groundDetach.Contains('String legacyObjVarName = "quest.wait_for_tasks";') -and
    $groundDetach.Contains("legacyObjVarValue = getResizeableStringArrayObjVar") -and
    $groundDetach.Contains("setObjVar(self, legacyObjVarName, legacyObjVarValue);") -and
    [bool]$contract.expected.laterGroundWaitForTasksPreserved -and
    [bool]$contract.expected.laterZonesQuestsConversationsAndNpcCompatibilityPreserved) `
    "Later groundquest wait-for-tasks compatibility was not preserved."

$eligibilityDependency = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14ForceSensitiveEligibility)) -Raw | ConvertFrom-Json
Assert-Contract ([string]$eligibilityDependency.status -ceq "ready" -and
    [bool]$contract.expected.forceSensitiveEligibilityDependencyReady) `
    "The native Force-sensitive eligibility dependency is not Ready."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.fullServerBuild -like "passed*" -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.buildEvidence.compiledFsQuestsClassSha256 -match '^[a-f0-9]{64}$' -and
        [int]$contract.buildEvidence.compiledFsQuestsClassBytes -gt 0 -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        [bool]$contract.runtimeEvidence.clientResponsive -and
        [int]$contract.runtimeEvidence.hostArtifactOrStagingDirectories -eq 0 -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Village authority lacks complete Ready evidence."

    $container = [string]$contract.runtimeEvidence.container
    $health = (& docker inspect $container --format '{{.State.Health.Status}}').Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $health -ceq "healthy") `
        "Village runtime container is not healthy."
    & docker exec $container cmp -s `
        "/swg-precu-source/dsrc/sku.0/sys.server/compiled/game/script/library/fs_quests.java" `
        "/swg-precu/dsrc/sku.0/sys.server/compiled/game/script/library/fs_quests.java"
    Assert-Contract ($LASTEXITCODE -eq 0) "Village source/work parity failed."

    $classPath = "/swg-precu/data/sku.0/sys.server/compiled/game/script/library/fs_quests.class"
    $classHash = ((& docker exec $container sha256sum $classPath).Trim() -split '\s+')[0]
    $classBytes = [int]((& docker exec $container stat -c '%s' $classPath).Trim())
    Assert-Contract ($classHash -ceq [string]$contract.buildEvidence.compiledFsQuestsClassSha256 -and
        $classBytes -eq [int]$contract.buildEvidence.compiledFsQuestsClassBytes) `
        "Deployed Village bytecode identity drifted."

    $serverPid = (& docker exec $container pgrep -n SwgGameServer).Trim()
    $serverExe = (& docker exec $container readlink -f "/proc/$serverPid/exe").Trim()
    $binaryHash = ((& docker exec $container sha256sum $serverExe).Trim() -split '\s+')[0]
    $buildLine = @(& docker exec $container readelf -n $serverExe | Select-String 'Build ID:')
    $buildId = ($buildLine[0].Line -replace '^.*Build ID:\s*', '').Trim()
    Assert-Contract ($binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $buildId -ceq [string]$contract.buildEvidence.serverBinaryBuildId) `
        "Deployed Village server binary identity drifted."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) `
        "Village source status is invalid."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Village authority references prohibited host staging."
Write-Host "Publish 14.1 PRE-CU Village quest authority passed."
