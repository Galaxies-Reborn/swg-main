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
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgeBeastMasterCreationPlayerRuntimeRetirement)
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
    try
    {
        return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
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

function Is-Before([string]$Text, [string]$First, [string]$Second)
{
    $firstIndex = $Text.IndexOf($First, [System.StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [System.StringComparison]::Ordinal)
    return $firstIndex -ge 0 -and $secondIndex -ge 0 -and $firstIndex -lt $secondIndex
}

function Assert-MethodGuard([string]$Text, [string]$MethodName, [string]$Guard, [string]$Name)
{
    $pattern = "(?ms)^\s*public\s+(?:static\s+)?[^\r\n{]+\b$([regex]::Escape($MethodName))\s*\([^\r\n]*\).*?\{(.{0,500})"
    $match = [regex]::Match($Text, $pattern)
    Assert-Contract ($match.Success -and $match.Groups[1].Value.Contains($Guard)) $Name
}

$relativeSourceMap = [ordered]@{
    "ai/pet_control_device.java" = "ai/pet_control_device.java"
    "library/beast_lib.java" = "library/beast_lib.java"
    "library/incubator.java" = "library/incubator.java"
    "npc/pet_deed/pet_deed.java" = "npc/pet_deed/pet_deed.java"
    "player/base/base_player.java" = "player/base/base_player.java"
    "player/player_utility.java" = "player/player_utility.java"
    "systems/beast/base_incubator.java" = "systems/beast/base_incubator.java"
    "systems/beast/beast_dye.java" = "systems/beast/beast_dye.java"
    "systems/beast/beast_egg.java" = "systems/beast/beast_egg.java"
    "systems/beast/beast_food.java" = "systems/beast/beast_food.java"
    "systems/beast/beast_steroid_injector.java" = "systems/beast/beast_steroid_injector.java"
    "systems/beast/decoration_item.java" = "systems/beast/decoration_item.java"
    "systems/beast/enzyme_crafting_base.java" = "systems/beast/enzyme_crafting_base.java"
    "systems/beast/enzyme_crafting_centrifuge.java" = "systems/beast/enzyme_crafting_centrifuge.java"
    "systems/beast/enzyme_crafting_combiner.java" = "systems/beast/enzyme_crafting_combiner.java"
    "systems/beast/enzyme_crafting_processor.java" = "systems/beast/enzyme_crafting_processor.java"
    "systems/beast/enzyme_extractor.java" = "systems/beast/enzyme_extractor.java"
}
Assert-Contract ($relativeSourceMap.Count -eq [int]$contract.expected.authoritativeSourceFiles) `
    "p14.beast-creation-retirement.direct-source.target-count"

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.beast-creation-retirement.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    Assert-Contract (
        (Get-Item -LiteralPath $patchPath).Length -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant() -ceq
            [string]$contract.buildEvidence.overlayPatch.sha256
    ) "p14.beast-creation-retirement.overlay.authenticated"
}

$targets = @(
    [regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object
)
$expectedTargets = @(
    $relativeSourceMap.Values |
        ForEach-Object { "sku.0/sys.server/compiled/game/script/$_" } |
        Sort-Object
)
Assert-Contract (
    $targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    (($targets -join $lf) -ceq ($expectedTargets -join $lf))
) "p14.beast-creation-retirement.overlay.target-set"
Assert-Contract (
    (Get-TextSha256 (($targets -join $lf) + $lf)) -ceq [string]$contract.buildEvidence.sourceSetSha256
) "p14.beast-creation-retirement.source-set.authenticated"
Assert-Contract (
    -not $patchText.Contains("materialize-") -and
    -not $patchText.Contains("E:\SWG")
) "p14.beast-creation-retirement.overlay.portable-paths"

$sourceTexts = @{}
$contentRecords = ""
foreach ($entry in $relativeSourceMap.GetEnumerator())
{
    $sourcePath = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $sourcePath -PathType Leaf) "p14.beast-creation-retirement.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) "p14.beast-creation-retirement.source.$($entry.Key).authenticated"
        $contentRecords += "sku.0/sys.server/compiled/game/script/$($entry.Value)=$hash$lf"
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $sourcePath -Raw
    }
}
Assert-Contract (
    (Get-TextSha256 $contentRecords) -ceq [string]$contract.buildEvidence.sourceContentSha256
) "p14.beast-creation-retirement.source-content.authenticated"

$creationAuthorityText = @(
    [string]$sourceTexts["library/beast_lib.java"],
    [string]$sourceTexts["library/incubator.java"],
    [string]$sourceTexts["systems/beast/base_incubator.java"],
    [string]$sourceTexts["systems/beast/beast_egg.java"],
    [string]$sourceTexts["systems/beast/enzyme_crafting_base.java"]
) -join $lf
Assert-Contract (
    -not $creationAuthorityText.Contains("expertise_bm_") -and
    -not $creationAuthorityText.Contains('getSkillStatisticModifier(player, "incubation_time_reduction")') -and
    -not ([string]$sourceTexts["systems/beast/base_incubator.java"]).Contains('getEnhancedSkillStatisticModifier') -and
    -not ([string]$sourceTexts["systems/beast/enzyme_crafting_base.java"]).Contains('getEnhancedSkillStatisticModifier') -and
    -not ([string]$sourceTexts["systems/beast/beast_egg.java"]).Contains('hasSkill(player, "expertise_bm_') -and
    [int]$contract.expected.creationExpertiseBmReferences -eq 0 -and
    [int]$contract.expected.creationBeastMasterSkillModifierReaders -eq 0
) "p14.beast-creation-retirement.expertise-and-skillmod-authority-absent"

$incubator = [string]$sourceTexts["library/incubator.java"]
$predicate = Get-SourceSlice $incubator "public static final boolean POST_NGE_BEAST_MASTER_CREATION_PLAYER_RUNTIME_RETIRED" "public static void retirePostNgeBeastMasterCreationPlayerState"
$playerCleanup = Get-SourceSlice $incubator "public static void retirePostNgeBeastMasterCreationPlayerState" "public static void retirePostNgeIncubatorStationState"
$stationCleanup = Get-SourceSlice $incubator "public static void retirePostNgeIncubatorStationState" "public static final int MAX_ADJUSTED_POINTS_PER_SESSION"
Assert-Contract (
    $predicate.Contains("POST_NGE_BEAST_MASTER_CREATION_PLAYER_RUNTIME_RETIRED = true") -and
    $predicate.Contains("isIdValid(player) && exists(player) && isPlayer(player)")
) "p14.beast-creation-retirement.player-only-predicate"
Assert-Contract (
    $playerCleanup.Contains("getActiveIncubator(player)") -and
    $playerCleanup.Contains("stopAllSessionParticles(station)") -and
    $playerCleanup.Contains("removeObjVar(player, BASE_INCUBATOR_OBJVAR)") -and
    $playerCleanup.Contains("utils.removeScriptVar(player, GUI_SCRIPT_VAR)") -and
    $stationCleanup.Contains("removeObjVar(station, BASE_INCUBATOR_OBJVAR)") -and
    -not $playerCleanup.Contains("destroyObject(") -and
    -not $stationCleanup.Contains("destroyObject(") -and
    -not $stationCleanup.Contains("getContents(")
) "p14.beast-creation-retirement.persisted-incubator-safe-cleanup"

foreach ($method in @(
    "setActiveUser", "setNextSessionTime", "isSessionEligible", "extractDna",
    "startSession", "convertDnaToEgg", "addPowerIncubator", "removeAllPowerIncubator",
    "convertPcdIntoPetItem", "convertDeedIntoPetItem", "convertPetItemToDna",
    "stampEggAsMount", "convertEggToMount"
))
{
    Assert-MethodGuard $incubator $method "isRetiredPostNgeBeastMasterCreationPlayer" "p14.beast-creation-retirement.incubator.$method.guarded"
}
Assert-Contract (
    $incubator.Contains("awardEnzymeCollection") -and
    $incubator.Contains('removeObjVar(enzyme, "collection_enzyme")') -and
    (Is-Before (Get-SourceSlice $incubator "public static void awardEnzymeCollection" "") "isRetiredPostNgeBeastMasterCreationPlayer(player)" "modifyCollectionSlotValue")
) "p14.beast-creation-retirement.enzyme-collection-award-retired"

$basePlayer = [string]$sourceTexts["player/base/base_player.java"]
Assert-Contract (
    [regex]::Matches($basePlayer, [regex]::Escape("incubator.retirePostNgeBeastMasterCreationPlayerState(self)")).Count -eq 3
) "p14.beast-creation-retirement.player-lifecycle-cleanup"

$baseIncubator = [string]$sourceTexts["systems/beast/base_incubator.java"]
Assert-Contract (
    [regex]::Matches($baseIncubator, "isPostNgeBeastMasterCreationPlayerRuntimeRetired").Count -ge 12 -and
    [regex]::Matches($baseIncubator, "isRetiredPostNgeBeastMasterCreationPlayer").Count -ge 2 -and
    $baseIncubator.Contains("public int OnIncubatorCommitted") -and
    $baseIncubator.Contains("public int OnAboutToReceiveItem") -and
    $baseIncubator.Contains("public int OnAboutToLoseItem")
) "p14.beast-creation-retirement.incubator-callback-surface-guarded"
$receive = Get-SourceSlice $baseIncubator "public int OnAboutToReceiveItem" "public int OnAboutToLoseItem"
$lose = Get-SourceSlice $baseIncubator "public int OnAboutToLoseItem" "public int handleObjectStored"
Assert-Contract (
    (Is-Before $receive "isPostNgeBeastMasterCreationPlayerRuntimeRetired" "return SCRIPT_OVERRIDE") -and
    $lose.Contains("return SCRIPT_CONTINUE")
) "p14.beast-creation-retirement.incubator-rejects-input-allows-recovery"

$enzymeBase = [string]$sourceTexts["systems/beast/enzyme_crafting_base.java"]
$terminate = Get-SourceSlice $enzymeBase "public void terminateProcess" "public boolean canBeTransfered"
Assert-Contract (
    $enzymeBase.Contains("import script.library.incubator") -and
    [regex]::Matches($enzymeBase, "isPostNgeBeastMasterCreationPlayerRuntimeRetired").Count -ge 6 -and
    [regex]::Matches($enzymeBase, "isRetiredPostNgeBeastMasterCreationPlayer").Count -ge 4 -and
    $terminate.Contains("removeObjVar(getSelf(), SYSTEM)") -and
    -not $terminate.Contains("destroyObject(") -and
    -not $terminate.Contains("getContents(")
) "p14.beast-creation-retirement.enzyme-machine-lifecycle-safe-retirement"
foreach ($method in @("startProcess", "startCentrifuge", "startProcessor", "startCombiner"))
{
    Assert-MethodGuard $enzymeBase $method "isRetiredPostNgeBeastMasterCreationPlayer" "p14.beast-creation-retirement.enzyme.$method.guarded"
}

foreach ($key in @(
    "systems/beast/enzyme_crafting_centrifuge.java",
    "systems/beast/enzyme_crafting_combiner.java",
    "systems/beast/enzyme_crafting_processor.java"
))
{
    $text = [string]$sourceTexts[$key]
    Assert-Contract (
        $text.Contains("isRetiredPostNgeBeastMasterCreationPlayer") -and
        $text.Contains("terminateProcess()") -and
        $text.Contains("public int OnObjectMenuRequest") -and
        $text.Contains("public int OnObjectMenuSelect")
    ) "p14.beast-creation-retirement.$key.menu-and-process-retired"
}

foreach ($key in @(
    "systems/beast/beast_dye.java",
    "systems/beast/beast_egg.java",
    "systems/beast/beast_food.java",
    "systems/beast/beast_steroid_injector.java",
    "systems/beast/decoration_item.java",
    "systems/beast/enzyme_extractor.java"
))
{
    Assert-Contract (([string]$sourceTexts[$key]).Contains("isRetiredPostNgeBeastMasterCreationPlayer")) "p14.beast-creation-retirement.$key.player-use-retired"
}

$beastLibrary = [string]$sourceTexts["library/beast_lib.java"]
foreach ($method in @(
    "createBCDFromEgg", "getEnzymeExtractionReturnCode", "createHolopetCubeFromEgg",
    "createBeastHolopet", "useBeastInjector", "getBeastMasterExamineInfo"
))
{
    Assert-MethodGuard $beastLibrary $method "isRetiredPostNgeBeastMasterPlayer" "p14.beast-creation-retirement.beast-library.$method.guarded"
}
$generateEnzyme = Get-SourceSlice $beastLibrary "public static obj_id generateTypeThreeEnzyme(obj_id player, obj_id target" "public static int getEnzymeExtractionReturnCode"
Assert-Contract (
    (Is-Before $generateEnzyme "isRetiredPostNgeBeastMasterPlayer(player)" "createObjectInInventoryAllowOverload")
) "p14.beast-creation-retirement.beast-library.generateTypeThreeEnzyme.guarded"

$petControlDevice = [string]$sourceTexts["ai/pet_control_device.java"]
Assert-Contract (
    [regex]::Matches($petControlDevice, "isRetiredPostNgeBeastMasterCreationPlayer").Count -eq 3 -and
    $petControlDevice.Contains("pet_lib.canCallCreaturePet") -and
    $petControlDevice.Contains("callable.storeCallable") -and
    $petControlDevice.Contains("pet_lib.createPetFromData")
) "p14.beast-creation-retirement.only-nge-pcd-conversion-retired"

$petDeed = [string]$sourceTexts["npc/pet_deed/pet_deed.java"]
Assert-Contract (
    [regex]::Matches($petDeed, "isRetiredPostNgeBeastMasterCreationPlayer").Count -ge 3 -and
    $petDeed.Contains("SID_CONVERT_PET_ITEM_TO_DNA")
) "p14.beast-creation-retirement.old-deed-conversion-retired"

$playerUtility = [string]$sourceTexts["player/player_utility.java"]
$collectDna = Get-SourceSlice $playerUtility "public int bm_collect_dna" "public int forage"
Assert-Contract (
    (Is-Before $collectDna "isRetiredPostNgeBeastMasterCreationPlayer(self)" "beast_lib.isBeastMaster(self)") -and
    $collectDna.Contains("return SCRIPT_OVERRIDE")
) "p14.beast-creation-retirement.collect-dna-command-fails-before-nge-flow"

foreach ($property in $contract.continuityEvidence.precuBioEngineerSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract (
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value
    ) "p14.beast-creation-retirement.precu-bio-engineer.$($property.Name).unchanged"
}
foreach ($property in $contract.continuityEvidence.precuCreatureHandlerSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract (
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value
    ) "p14.beast-creation-retirement.precu-creature-handler.$($property.Name).unchanged"
}
foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract (
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value
    ) "p14.beast-creation-retirement.mission.$($property.Name).unchanged"
}
Assert-Contract (
    [string]$contract.continuityEvidence.missionTerminalUserVerification -like "working in-world*"
) "p14.beast-creation-retirement.mission-terminal-user-baseline-recorded"
Assert-Contract (
    -not $patchText.Contains("systems/crafting/bio_engineer/") -and
    -not $patchText.Contains("systems/missions/") -and
    -not $patchText.Contains("library/missions.java")
) "p14.beast-creation-retirement.overlay-excludes-precu-bio-engineer-and-missions"

Assert-Contract (
    @("implemented-build-verified-live-pending", "ready") -ccontains [string]$contract.status
) "p14.beast-creation-retirement.contract.status"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "dsrc" })
    Assert-Contract (
        [string]$manifest.sourceMode -ceq "direct-branch" -and
        $dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink
    ) "p14.beast-creation-retirement.direct-source-pin"
    Assert-Contract (
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        [string]$contract.buildEvidence.result -ceq "passed"
    ) "p14.beast-creation-retirement.live-evidence"
}

if ($failures.Count -gt 0)
{
    throw "Post-NGE Beast Master creation player runtime retirement contract failed: $($failures -join ', ')"
}
Write-Host "Post-NGE Beast Master creation player runtime retirement contract passed."
