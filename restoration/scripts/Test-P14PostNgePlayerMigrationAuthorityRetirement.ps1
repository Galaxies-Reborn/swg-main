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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgePlayerMigrationAuthorityRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$lf = [char]10

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    if ([string]::IsNullOrEmpty($EndMarker)) { return $Text.Substring($start) }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$relativeSourceMap = [ordered]@{
    "cureward/cureward.java" = "cureward/cureward.java"
    "library/skill.java" = "library/skill.java"
    "player/base/base_player.java" = "player/base/base_player.java"
    "player/live_conversions.java" = "player/live_conversions.java"
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.archivedOverlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.player-migration.archived-overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    Assert-Contract (
        (Get-Item -LiteralPath $patchPath).Length -eq [long]$contract.buildEvidence.archivedOverlayPatch.bytes -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant() -ceq [string]$contract.buildEvidence.archivedOverlayPatch.sha256
    ) "p14.player-migration.archived-overlay.authenticated"
}

$targets = @(
    [regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object
)
$expectedTargets = @($relativeSourceMap.Values | ForEach-Object { "sku.0/sys.server/compiled/game/script/$_" } | Sort-Object)
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and (($targets -join $lf) -ceq ($expectedTargets -join $lf))) "p14.player-migration.archived-overlay.target-set"
Assert-Contract ((Get-TextSha256 (($targets -join $lf) + $lf)) -ceq [string]$contract.buildEvidence.sourceSetSha256) "p14.player-migration.source-set.authenticated"
Assert-Contract (-not $patchText.Contains("materialize-") -and -not $patchText.Contains("E:\SWG")) "p14.player-migration.archived-overlay.portable-paths"

$sourceTexts = @{}
$contentRecords = ""
foreach ($entry in $relativeSourceMap.GetEnumerator())
{
    $sourcePath = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $sourcePath -PathType Leaf) "p14.player-migration.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) "p14.player-migration.source.$($entry.Key).authenticated"
        $contentRecords += "sku.0/sys.server/compiled/game/script/$($entry.Value)=$hash$lf"
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $sourcePath -Raw
    }
}
Assert-Contract ((Get-TextSha256 $contentRecords) -ceq [string]$contract.buildEvidence.sourceContentSha256) "p14.player-migration.source-content.authenticated"

$skill = [string]$sourceTexts["library/skill.java"]
$retiredSkillPredicate = Get-SourceSlice $skill "public static boolean isRetiredNgeProgressionSkillName" "public static boolean isRetiredPostNgeSpySkill"
Assert-Contract (
    $retiredSkillPredicate.Contains('skillName.startsWith("class_")') -and
    $retiredSkillPredicate.Contains('skillName.equals("expertise")') -and
    $retiredSkillPredicate.Contains('skillName.startsWith("expertise_")') -and
    $retiredSkillPredicate.Contains('skillName.startsWith("internal_expertise_")')
) "p14.player-migration.retired-skill-families"

$conversions = [string]$sourceTexts["player/live_conversions.java"]
$cleanup = Get-SourceSlice $conversions "public static void retirePostNgePlayerMigrationState" "public int OnAttach"
Assert-Contract (
    $conversions.Contains("POST_NGE_PLAYER_MIGRATION_RUNTIME_RETIRED = true") -and
    $cleanup.Contains('setSkillTemplate(player, "")') -and
    $cleanup.Contains('setWorkingSkill(player, "")') -and
    $cleanup.Contains('removeObjVar(player, "combatLevel")') -and
    $cleanup.Contains('removeObjVar(player, "clickRespec")') -and
    $cleanup.Contains('detachScript(player, "cureward.cureward")') -and
    $cleanup.Contains('detachScript(player, "player.live_conversions")')
) "p14.player-migration.persisted-state-cleanup"
$conversionCallbacks = Get-SourceSlice $conversions "public int OnAttach" "public void runOncePerSessionConversions"
Assert-Contract (
    -not $conversionCallbacks.Contains("runOncePerSessionConversions(") -and
    -not $conversionCallbacks.Contains("runOncePerTravelConversions(") -and
    -not $conversionCallbacks.Contains("updateBountyHunterMissions(") -and
    -not $conversionCallbacks.Contains("updateChangedQuests(") -and
    -not $conversionCallbacks.Contains("updateCollectionSlots(") -and
    [regex]::Matches($conversionCallbacks, [regex]::Escape('detachScript(self, "player.live_conversions")')).Count -eq 3
) "p14.player-migration.automatic-callbacks-retired"

$cuReward = [string]$sourceTexts["cureward/cureward.java"]
Assert-Contract (
    $cuReward.Contains("COMBAT_UPGRADE_REWARD_RUNTIME_RETIRED = true") -and
    [regex]::Matches($cuReward, [regex]::Escape('detachScript(self, "cureward.cureward")')).Count -eq 4 -and
    -not $cuReward.Contains("createObjectInInventoryAllowOverload") -and
    -not $cuReward.Contains("combatUpgradeReward")
) "p14.player-migration.combat-upgrade-reward-retired"

$basePlayer = [string]$sourceTexts["player/base/base_player.java"]
$initialize = Get-SourceSlice $basePlayer "public int OnInitialize(obj_id self)" "public int OnLogin(obj_id self)"
$login = Get-SourceSlice $basePlayer "public int OnLogin(obj_id self)" "public int handleDelayedLogin"
$upload = Get-SourceSlice $basePlayer "public int OnUploadCharacter" "public void logItemDictionary"
$download = Get-SourceSlice $basePlayer "public int OnDownloadCharacter" "public int OnSkillModDone"
Assert-Contract (
    $initialize.Contains("retirePostNgePlayerMigrationState(self)") -and
    $login.Contains("retirePostNgePlayerMigrationState(self)") -and
    -not $login.Contains('attachScript(self, "cureward.cureward")') -and
    -not $login.Contains('setObjVar(self, "combatLevel"')
) "p14.player-migration.player-lifecycle-authority"
Assert-Contract (
    $upload.Contains('characterData.put("skills", getSkillListingForPlayer(self))') -and
    $upload.Contains('characterData.put("experience_points", experiencePoints)') -and
    -not $upload.Contains('characterData.put("skillTemplate"') -and
    -not $upload.Contains('characterData.put("workingSkill"') -and
    -not $upload.Contains('characterData.put("combatLevel"') -and
    -not $upload.Contains('characterData.put("commands"') -and
    -not $upload.Contains("getCommandListingForPlayer")
) "p14.player-migration.cts-upload-precu-progression"
Assert-Contract (
    $download.Contains("skill.isRetiredNgeProgressionSkillName(transferredSkill)") -and
    $download.Contains("ignored retired NGE progression skill") -and
    $download.Contains("ignored legacy raw command list") -and
    -not $download.Contains("setSkillTemplate(self") -and
    -not $download.Contains('setObjVar(self, "clickRespec') -and
    -not $download.Contains("grantCommand(self, command)") -and
    [regex]::Matches($download, [regex]::Escape("retirePostNgePlayerMigrationState(self)")).Count -eq 2
) "p14.player-migration.cts-download-precu-progression"
Assert-Contract (
    $upload.Contains('characterData.put("quests", quests)') -and
    $upload.Contains('characterData.put("collections", collections)') -and
    $download.Contains('setAutoVariableFromByteStream(playerObject, "quests", quests)') -and
    $download.Contains("groundquests.reattachQuestScripts(self)") -and
    $download.Contains('setAutoVariableFromByteStream(playerObject, "collections", collections)') -and
    $download.Contains("unpackWaypoint(waypointDict)") -and
    $download.Contains("unpackItem(playerInventory, itemDictionary)")
) "p14.player-migration.retained-content-transfer-preserved"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.player-migration.mission.$($property.Name).unchanged"
}
Assert-Contract ([string]$contract.continuityEvidence.missionTerminalUserVerification -like "working in-world*") "p14.player-migration.mission-terminal-user-baseline-recorded"
Assert-Contract (-not $patchText.Contains("systems/missions/") -and -not $patchText.Contains("library/missions.java")) "p14.player-migration.archived-overlay-excludes-missions"

$dsrcGitlink = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$compiledClassProperties = @($contract.buildEvidence.compiledClassSha256.PSObject.Properties)
Assert-Contract (
    [string]$contract.status -ceq "ready" -and
    [string]$contract.buildEvidence.staticContract -ceq "passed" -and
    [string]$contract.buildEvidence.result -ceq "passed" -and
    $contract.requiredBeforeReady.Count -eq 0
) "p14.player-migration.ready-contract"
Assert-Contract (
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    [string]$contract.buildEvidence.sourceMode -ceq "direct-branch" -and
    $dsrcGitlink.Count -eq 1 -and
    [string]$contract.buildEvidence.directSourceGitlink -ceq [string]$dsrcGitlink[0].commit -and
    [string]$contract.buildEvidence.hostMaterializationWorkflow -like "retired*" -and
    [string]$contract.buildEvidence.directSourceBuild -like "passed*"
) "p14.player-migration.direct-source-build-authority"
Assert-Contract (
    [string]$contract.buildEvidence.fullJavaCompile -like "passed*" -and
    [string]$contract.buildEvidence.architecture -like "ELF 64-bit LSB x86-64*" -and
    [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
    [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
    $compiledClassProperties.Count -eq $relativeSourceMap.Count -and
    @($compiledClassProperties | Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0 -and
    [string]$contract.buildEvidence.deploymentProbe -like "passed*"
) "p14.player-migration.compiled-x64-deployment"
Assert-Contract (
    ([string]$contract.runtimeEvidence.sourceMount).Replace('\', '/').Contains('/Source/pre-cu-reborn-server-x64 -> /swg-precu-source') -and
    [bool]$contract.runtimeEvidence.sourceMountReadOnly -and
    [string]$contract.runtimeEvidence.containerHealth -ceq "healthy" -and
    [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
    [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
    [string]$contract.runtimeEvidence.postStartLogAudit -like "*zero fatal*" -and
    [string]$contract.runtimeEvidence.result -ceq "passed"
) "p14.player-migration.runtime-ready"

if ($failures.Count -gt 0)
{
    throw "Post-NGE player migration authority retirement contract failed: $($failures -join ', ')"
}
Write-Host "Post-NGE player migration authority retirement contract passed."
