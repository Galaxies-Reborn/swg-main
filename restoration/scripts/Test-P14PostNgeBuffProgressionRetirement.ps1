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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgeBuffProgressionRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$sharedRoot = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game"
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

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

function Is-Before([string]$Text, [string]$First, [string]$Second)
{
    $firstIndex = $Text.IndexOf($First, [System.StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [System.StringComparison]::Ordinal)
    return $firstIndex -ge 0 -and $secondIndex -ge 0 -and $firstIndex -lt $secondIndex
}

$relativeSourceMap = [ordered]@{
    "library/buff.java" = "library/buff.java"
    "library/gcw.java" = "library/gcw.java"
    "library/xp.java" = "library/xp.java"
    "player/base/base_player.java" = "player/base/base_player.java"
    "player/skill/performcommands.java" = "player/skill/performcommands.java"
    "systems/buff/buff_handler.java" = "systems/buff/buff_handler.java"
    "systems/buff_builder/buff_builder_cancel.java" = "systems/buff_builder/buff_builder_cancel.java"
    "systems/buff_builder/buff_builder_response.java" = "systems/buff_builder/buff_builder_response.java"
    "systems/crafting/crafting_base.java" = "systems/crafting/crafting_base.java"
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.buff-progression.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.buff-progression.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$expectedTargets = @($relativeSourceMap.Values | ForEach-Object {
    "sku.0/sys.server/compiled/game/script/$_"
} | Sort-Object)
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    (($targets -join "`n") -ceq ($expectedTargets -join "`n"))) "p14.buff-progression.overlay.target-set"
Assert-Contract ((Get-TextSha256 (($targets -join "`n") + "`n")) -ceq
    [string]$contract.buildEvidence.sourceSetSha256) "p14.buff-progression.source-set.authenticated"

$sourceTexts = @{}
$contentRecords = ""
foreach ($entry in $relativeSourceMap.GetEnumerator())
{
    $sourcePath = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $sourcePath -PathType Leaf) "p14.buff-progression.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
            "p14.buff-progression.source.$($entry.Key).authenticated"
        $contentRecords += "sku.0/sys.server/compiled/game/script/$($entry.Value)=$hash`n"
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $sourcePath -Raw
    }
}
Assert-Contract ((Get-TextSha256 $contentRecords) -ceq [string]$contract.buildEvidence.sourceContentSha256) `
    "p14.buff-progression.source-content.authenticated"

$buffText = [string]$sourceTexts["library/buff.java"]
$flagBody = Get-SourceSlice $buffText "public static boolean isPostNgeBuffProgressionRetired()" "public static void retirePostNgeBuffProgression"
$cleanupBody = Get-SourceSlice $buffText "public static void retirePostNgeBuffProgression" "public static final String DOT_BLEEDING"
$meditationCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostNgeMeditationBuffs" "public static final String DOT_BLEEDING"
$bannerInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_NGE_GCW_BANNER_BUFFS" `
    "public static boolean isRetiredPostNgeGcwBannerBuff"
$bannerCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostNgeGcwBannerBuffState" `
    "private static final String[] RETIRED_POST_NGE_GCW_CONSUMABLE_BUFFS"
$gcwConsumableInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_NGE_GCW_CONSUMABLE_BUFFS" `
    "public static boolean isRetiredPostNgeGcwConsumableBuff"
$gcwConsumableCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostNgeGcwConsumableBuffState" `
    "public static boolean isRetiredPostNgeBountyHunterShieldBuff"
$controlImmunityInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_P14_PLAYER_CONTROL_IMMUNITY_BUFFS" `
    "public static boolean isRetiredPostP14PlayerControlImmunityBuff"
$controlImmunityCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostP14PlayerControlImmunityState" `
    "public static boolean isRetiredPostNgeBountyHunterShieldBuff"
$buffAdmissionBody = Get-SourceSlice $buffText `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static boolean applyBuff(obj_id target, String name)"
$meditationTickBody = Get-SourceSlice ([string]$sourceTexts["player/base/base_player.java"]) `
    "public int handleMeditationTick" "public int msgCoupDeGraceAuthoritativeCheck"
Assert-Contract ($flagBody.Contains("return true;")) "p14.buff-progression.central-flag.true"
foreach ($buffName in @($contract.expected.retiredBuffs))
{
    Assert-Contract ($cleanupBody.Contains("removeBuff(player, `"$buffName`")")) "p14.buff-progression.cleanup.buff.$buffName"
}
Assert-Contract ($cleanupBody.Contains("retirePostNgeMeditationBuffs(player);") -and
    $meditationCleanupBody.Contains("removeBuff(player, retiredBuff);") -and
    ([regex]::Matches($meditationCleanupBody, '"fs_meditate_[123]"')).Count -eq
        @($contract.expected.retiredMeditationBuffs).Count) `
    "p14.buff-progression.cleanup.meditation-buffs"
foreach ($buffName in @($contract.expected.retiredMeditationBuffs))
{
    Assert-Contract ($meditationCleanupBody.Contains("`"$buffName`"")) `
        "p14.buff-progression.cleanup.meditation.$buffName"
}
$expectedBannerBuffs = @($contract.expected.retiredGcwBannerBuffs | Sort-Object)
$actualBannerBuffs = @([regex]::Matches($bannerInventoryBody, '"(banner_buff_[^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($actualBannerBuffs.Count -eq [int]$contract.expected.retiredGcwBannerBuffCount -and
    @($actualBannerBuffs | Select-Object -Unique).Count -eq $actualBannerBuffs.Count -and
    (($actualBannerBuffs -join "`n") -ceq ($expectedBannerBuffs -join "`n")) -and
    $bannerCleanupBody.Contains("isPlayer(player)") -and
    $bannerCleanupBody.Contains("removeBuff(player, retiredBuff)") -and
    $cleanupBody.Contains("retirePostNgeGcwBannerBuffState(player);") -and
    (Is-Before $buffAdmissionBody "isRetiredPostNgeGcwBannerBuff(bdata.buffName)" "hasBuff(target, nameCrc)")) `
    "p14.buff-progression.gcw-banner.player-state-retired"
$expectedGcwConsumableBuffs = @($contract.expected.retiredGcwConsumableBuffs | Sort-Object)
$actualGcwConsumableBuffs = @([regex]::Matches($gcwConsumableInventoryBody, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($actualGcwConsumableBuffs.Count -eq [int]$contract.expected.retiredGcwConsumableBuffCount -and
    @($actualGcwConsumableBuffs | Select-Object -Unique).Count -eq $actualGcwConsumableBuffs.Count -and
    (($actualGcwConsumableBuffs -join "`n") -ceq ($expectedGcwConsumableBuffs -join "`n")) -and
    $gcwConsumableCleanupBody.Contains("isPlayer(player)") -and
    $gcwConsumableCleanupBody.Contains("removeBuff(player, retiredBuff)") -and
    $gcwConsumableCleanupBody.Contains('removeScriptVarTree(player, "buff.gcwBonusGeneral")') -and
    $cleanupBody.Contains("retirePostNgeGcwConsumableBuffState(player);") -and
    (Is-Before $buffAdmissionBody "isRetiredPostNgeGcwConsumableBuff(bdata.buffName)" "hasBuff(target, nameCrc)")) `
    "p14.buff-progression.gcw-consumable.player-state-and-admission-retired"
$expectedControlImmunityBuffs = @($contract.expected.retiredPlayerControlImmunityBuffs | Sort-Object)
$actualControlImmunityBuffs = @([regex]::Matches($controlImmunityInventoryBody, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($actualControlImmunityBuffs.Count -eq [int]$contract.expected.retiredPlayerControlImmunityBuffCount -and
    @($actualControlImmunityBuffs | Select-Object -Unique).Count -eq $actualControlImmunityBuffs.Count -and
    (($actualControlImmunityBuffs -join "`n") -ceq ($expectedControlImmunityBuffs -join "`n")) -and
    -not [bool]$contract.expected.postP14PlayerControlImmunityBuffAdmissionReachable -and
    $controlImmunityCleanupBody.Contains("isPlayer(player)") -and
    $controlImmunityCleanupBody.Contains("removeBuff(player, retiredBuff)") -and
    $cleanupBody.Contains("retirePostP14PlayerControlImmunityState(player);") -and
    (Is-Before $buffAdmissionBody "isRetiredPostP14PlayerControlImmunityBuff(bdata.buffName)" "hasBuff(target, nameCrc)")) `
    "p14.buff-progression.control-immunity.player-state-and-admission-retired"
Assert-Contract ([bool]$contract.expected.randomMeditationTickGrantRetired -and
    $meditationTickBody.Contains("meditation.trance(self)") -and
    $meditationTickBody.Contains("messageTo(self, meditation.HANDLER_MEDITATION_TICK") -and
    -not $meditationTickBody.Contains("MEDITATE_BUFFS") -and
    -not $meditationTickBody.Contains("fs_meditate_") -and
    -not $meditationTickBody.Contains("buff.applyBuff") -and
    -not $meditationTickBody.Contains("utils.isProfession(self, utils.FORCE_SENSITIVE)") -and
    -not $meditationTickBody.Contains("utils.setScriptVar(self, meditation.VAR_MEDITATION_BASE")) `
    "p14.buff-progression.meditation.random-tick-grant-retired"
foreach ($tree in @($contract.expected.retiredScriptVarTrees))
{
    Assert-Contract (($cleanupBody + $gcwConsumableCleanupBody).Contains("removeScriptVarTree(player, `"$tree`")")) `
        "p14.buff-progression.cleanup.scriptvar.$tree"
}
foreach ($scriptName in @($contract.expected.retiredBuilderScripts))
{
    Assert-Contract ($cleanupBody.Contains("detachScript(player, `"$scriptName`")")) "p14.buff-progression.cleanup.script.$scriptName"
}

$performText = [string]$sourceTexts["player/skill/performcommands.java"]
$inspireBody = Get-SourceSlice $performText "public int cmdInspire" ""
Assert-Contract ((Is-Before $inspireBody "buff.isPostNgeBuffProgressionRetired()" "getIntendedTarget(self)") -and
    (Is-Before $inspireBody "buff.retirePostNgeBuffProgression(self)" "attachScript(self, SCRIPT_BUFF_BUILDER_RESPONSE)") -and
    (Is-Before $inspireBody "buff.retirePostNgeBuffProgression(self)" "buffBuilderStart(self, inspireTarget)")) `
    "p14.buff-progression.inspire.fail-closed-before-builder"

$responseText = [string]$sourceTexts["systems/buff_builder/buff_builder_response.java"]
$responseMarkers = @(
    @("public int OnInitialize", "public int OnLogin"),
    @("public int OnLogin", "public int OnImmediateLogout"),
    @("public int OnImmediateLogout", "public int OnBuffBuilderValidate"),
    @("public int OnBuffBuilderValidate", "public int OnBuffBuilderCompleted"),
    @("public int OnBuffBuilderCompleted", "public int OnBuffBuilderCanceled"),
    @("public int OnBuffBuilderCanceled", "")
)
$guardedResponses = 0
foreach ($markers in $responseMarkers)
{
    $body = Get-SourceSlice $responseText $markers[0] $markers[1]
    if ($body.Contains("buff.isPostNgeBuffProgressionRetired()") -and
        $body.Contains("buff.retirePostNgeBuffProgression(self)") -and
        $body.Contains("return SCRIPT_CONTINUE;")) { $guardedResponses++ }
}
Assert-Contract ($guardedResponses -eq [int]$contract.expected.guardedResponseCallbacks) `
    "p14.buff-progression.builder-response.callbacks-guarded"
$validateBody = Get-SourceSlice $responseText "public int OnBuffBuilderValidate" "public int OnBuffBuilderCompleted"
$completeBody = Get-SourceSlice $responseText "public int OnBuffBuilderCompleted" "public int OnBuffBuilderCanceled"
Assert-Contract ((Is-Before $validateBody "buff.isPostNgeBuffProgressionRetired()" "buffBuilderValidated(") -and
    (Is-Before $completeBody "buff.isPostNgeBuffProgressionRetired()" "money.pay(") -and
    (Is-Before $completeBody "buff.isPostNgeBuffProgressionRetired()" "setScriptVar(") -and
    (Is-Before $completeBody "buff.isPostNgeBuffProgressionRetired()" "buff.applyBuff(") -and
    (Is-Before $completeBody "buff.isPostNgeBuffProgressionRetired()" "scheduled_drop")) `
    "p14.buff-progression.builder-response.sensitive-effects-dominated"

$cancelText = [string]$sourceTexts["systems/buff_builder/buff_builder_cancel.java"]
$cancelCleanupCount = ([regex]::Matches($cancelText, 'buff\.retirePostNgeBuffProgression\(self\)')).Count
Assert-Contract ($cancelCleanupCount -eq [int]$contract.expected.guardedCancelEntrypoints -and
    $cancelText.Contains("public int OnInitialize") -and $cancelText.Contains("public int OnLogin") -and
    $cancelText.Contains("public int OnBuffBuilderCanceled")) "p14.buff-progression.builder-cancel.entrypoints-guarded"

$basePlayerText = [string]$sourceTexts["player/base/base_player.java"]
$loginBody = Get-SourceSlice $basePlayerText "public int OnLogin(obj_id self)" "public int OnLogout"
Assert-Contract ($basePlayerText.Contains("buff.retirePostNgeBuffProgression(self);") -and
    (Is-Before $loginBody "buff.retirePostNgeBuffProgression(self);" "return SCRIPT_CONTINUE;")) `
    "p14.buff-progression.login.cleanup"

$handlerText = [string]$sourceTexts["systems/buff/buff_handler.java"]
$xpBonusBody = Get-SourceSlice $handlerText "public int xpBonusGeneralAddBuffHandler" "public int xpBonusGeneralRemoveBuffHandler"
$xpGrantBody = Get-SourceSlice $handlerText "public int xpGrantedGeneralAddBuffHandler" "public int xpGrantedGeneralRemoveBuffHandler"
$buildBody = Get-SourceSlice $handlerText "public int buildabuffAddBuffHandler" "public int buildabuffRemoveBuffHandler"
$gcwBonusBody = Get-SourceSlice $handlerText "public int gcwBonusGeneralAddBuffHandler" "public int gcwBonusGeneralRemoveBuffHandler"
$gcwMiniTurretBody = Get-SourceSlice $handlerText "public int gcwMiniTurretAddBuffHandler" "public int gcwMiniTurretRemoveBuffHandler"
Assert-Contract ((Is-Before $xpBonusBody "buff.isPostNgeBuffProgressionRetired()" "skill.getPrecuEncounterDifficulty(self)") -and
    (Is-Before $xpGrantBody "buff.isPostNgeBuffProgressionRetired()" "skill.getPrecuEncounterDifficulty(self)") -and
    (Is-Before $buildBody "buff.isPostNgeBuffProgressionRetired()" "performance.buildabuff.buffComponentKeys") -and
    -not $xpBonusBody.Contains("getLevel(self)") -and -not $xpGrantBody.Contains("getLevel(self)") -and
    -not $buildBody.Contains("getLevel(self)")) "p14.buff-progression.handlers.fail-closed-before-later-authority"
Assert-Contract ($xpBonusBody.Contains('removeScriptVarTree(self, "buff.xpBonusGeneral")') -and
    $buildBody.Contains("buildabuffRemoveBuffHandler(") -and
    $buildBody.Contains('removeScriptVarTree(self, "performance.buildabuff")')) `
    "p14.buff-progression.handlers.cleanup"
Assert-Contract ((Is-Before $gcwBonusBody "buff.isPostNgeBuffProgressionRetired()" 'setScriptVar(self, "buff.gcwBonusGeneral.value"') -and
    $gcwBonusBody.Contains('removeScriptVarTree(self, "buff.gcwBonusGeneral")') -and
    (Is-Before $gcwMiniTurretBody "buff.isPostNgeBuffProgressionRetired()" "advanced_turret.createTurret(") -and
    $gcwMiniTurretBody.Contains("buff.removeBuff(self, buffName)") -and
    -not [bool]$contract.expected.postNgeGcwConsumableBuffAdmissionReachable -and
    -not [bool]$contract.expected.postNgeMiniTurretCreationReachable -and
    [bool]$contract.expected.staleGcwBonusGeneralStateScrubbed) `
    "p14.buff-progression.gcw-consumable.handlers-fail-closed"

$xpText = [string]$sourceTexts["library/xp.java"]
$applyXpBody = Get-SourceSlice $xpText "public static int applyInspirationBuffXpModifier" "public static float getGroupXpModifier"
$getXpBody = Get-SourceSlice $xpText "public static float getInspirationBuffXpModifier" "public static void grantSquadLeaderXp"
Assert-Contract ((Is-Before $applyXpBody "buff.isPostNgeBuffProgressionRetired()" "getInspirationBuffXpModifier(") -and
    $applyXpBody.Contains("return amt;") -and
    (Is-Before $getXpBody "buff.isPostNgeBuffProgressionRetired()" 'hasScriptVar(target, "buff.xpBonus.types")') -and
    $getXpBody.Contains("return 1.0f;")) "p14.buff-progression.general-xp.identity"

$percentageApiBody = Get-SourceSlice $xpText `
    "public static int grantUnmodifiedXPPercentageOfLevel" `
    "public static void applyHealingCredit"
$percentageCallers = [System.Collections.Generic.List[string]]::new()
$scriptRootPrefix = $scriptRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
foreach ($javaFile in @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java"))
{
    $relativeJavaPath = $javaFile.FullName.Substring($scriptRootPrefix.Length).Replace('\', '/')
    if ($relativeJavaPath.StartsWith("test/", [System.StringComparison]::Ordinal)) { continue }
    $javaText = Get-Content -LiteralPath $javaFile.FullName -Raw
    $occurrences = ([regex]::Matches($javaText, 'grantUnmodifiedXPPercentageOfLevel\s*\(')).Count
    if ($relativeJavaPath -ceq "library/xp.java") { $occurrences-- }
    for ($index = 0; $index -lt $occurrences; $index++) { $percentageCallers.Add($relativeJavaPath) }
}
Assert-Contract ($percentageApiBody.Contains("return 0;") -and
    -not $percentageApiBody.Contains("getLevel(") -and
    -not $percentageApiBody.Contains("getSkillTemplate") -and
    -not $percentageApiBody.Contains("player_level.iff") -and
    [bool]$contract.expected.percentageOfLevelXpApiReturnsZero) `
    "p14.buff-progression.percentage-of-level-api-fails-closed"
Assert-Contract ($percentageCallers.Count -eq [int]$contract.expected.productionPercentageOfLevelXpCallers -and
    $percentageCallers.Count -eq 1 -and
    $percentageCallers[0] -ceq [string]$contract.expected.productionPercentageOfLevelXpCaller -and
    (Is-Before $xpGrantBody "buff.isPostNgeBuffProgressionRetired()" "xp.grantUnmodifiedXPPercentageOfLevel(") -and
    -not [bool]$contract.expected.levelPercentageBuffXpWriterReachable -and
    [bool]$contract.expected.levelPercentageBuffXpAuditClosed) `
    "p14.buff-progression.production-level-percentage-xp-surface-closed"

$craftingText = [string]$sourceTexts["systems/crafting/crafting_base.java"]
$craftingBody = Get-SourceSlice $craftingText "public int getInspirationBuffXpBonus" "public int OnManufactureObject"
Assert-Contract ((Is-Before $craftingBody "buff.isPostNgeBuffProgressionRetired()" 'hasScriptVar(self, "buff.general_inspiration.value")') -and
    $craftingBody.Contains("return 0;")) "p14.buff-progression.crafting-xp.zero"

$gcwText = [string]$sourceTexts["library/gcw.java"]
$gcwBody = Get-SourceSlice $gcwText "public static int getModifiedGcwPointValue" "public static void registerPvpRegionControllerWithPlanet"
Assert-Contract ((Is-Before $gcwBody "buff.isPostNgeBuffProgressionRetired()" 'hasScriptVar(player, "buff.xpBonus.value")') -and
    $gcwBody.Contains("return passedValue;")) "p14.buff-progression.gcw.identity"

$buffTablePath = Join-Path $sharedRoot "datatables/buff/buff.tab"
$effectMapPath = Join-Path $sharedRoot "datatables/buff/effect_mapping.tab"
$buffTable = Get-Content -LiteralPath $buffTablePath -Raw
$effectMap = Get-Content -LiteralPath $effectMapPath -Raw
Assert-Contract ($buffTable.Contains("general_inspiration`t") -and
    $buffTable.Contains("buildabuff_inspiration`t") -and $buffTable.Contains("tcg_series1_radtrooper_badge`t") -and
    $buffTable.Contains("tcg_series1_nuna_ball_advertisement`t")) "p14.buff-progression.compatibility.buff-rows-preserved"
$bannerRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t" |
    Where-Object { $_.NAME -like "banner_buff_*" })
Assert-Contract ($bannerRows.Count -eq [int]$contract.expected.retainedGcwBannerBuffRows -and
    ((@($bannerRows.NAME | Sort-Object) -join "`n") -ceq ($expectedBannerBuffs -join "`n"))) `
    "p14.buff-progression.compatibility.gcw-banner-rows-preserved"
$gcwConsumableRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t" |
    Where-Object { $_.NAME -in $expectedGcwConsumableBuffs })
Assert-Contract ($gcwConsumableRows.Count -eq [int]$contract.expected.retainedGcwConsumableBuffRows -and
    ((@($gcwConsumableRows.NAME | Sort-Object) -join "`n") -ceq ($expectedGcwConsumableBuffs -join "`n"))) `
    "p14.buff-progression.compatibility.gcw-consumable-buff-rows-preserved"
$controlImmunityRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t" |
    Where-Object { $_.NAME -in $expectedControlImmunityBuffs })
Assert-Contract ($controlImmunityRows.Count -eq [int]$contract.expected.retainedPlayerControlImmunityBuffRows -and
    ((@($controlImmunityRows.NAME | Sort-Object) -join "`n") -ceq ($expectedControlImmunityBuffs -join "`n"))) `
    "p14.buff-progression.compatibility.control-immunity-rows-preserved"
$towMoveRow = @($controlImmunityRows | Where-Object { $_.NAME -ceq "towHk47MoveImmuneItem" })
$towMezRow = @($controlImmunityRows | Where-Object { $_.NAME -ceq "towMafosaMezImmune" })
$treasureSnareRow = @($controlImmunityRows | Where-Object { $_.NAME -ceq "treasure_bonus_snare_immunity" })
Assert-Contract ($towMoveRow.Count -eq 1 -and $towMoveRow[0].GROUP1 -ceq "snare" -and
    $towMoveRow[0].GROUP2 -ceq "root" -and $towMoveRow[0].BLOCK -ceq "nullification" -and
    $towMezRow.Count -eq 1 -and $towMezRow[0].GROUP1 -ceq "mez" -and
    $towMezRow[0].GROUP2 -ceq "root" -and $towMezRow[0].BLOCK -ceq "nullification" -and
    $treasureSnareRow.Count -eq 1 -and $treasureSnareRow[0].EFFECT1_PARAM -ceq "movement" -and
    [float]$treasureSnareRow[0].EFFECT1_VALUE -eq 0.0) `
    "p14.buff-progression.compatibility.expansion-control-items-authenticated"
$bossImmunityNames = @("boss_snare_immunity", "boss_root_immunity", "boss_mez_immunity")
$bossImmunityRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t" |
    Where-Object { $_.NAME -in $bossImmunityNames })
$bossMovementScript = Get-Content -LiteralPath (Join-Path $scriptRoot "npc/boss/boss_movement_buff.java") -Raw
Assert-Contract ([bool]$contract.expected.legitimateNpcControlImmunityPreserved -and
    $bossImmunityRows.Count -eq 3 -and
    @($bossImmunityNames | Where-Object { $actualControlImmunityBuffs -contains $_ }).Count -eq 0 -and
    @($bossImmunityNames | Where-Object { -not $bossMovementScript.Contains("buff.applyBuff(self, `"$_`")") }).Count -eq 0) `
    "p14.buff-progression.compatibility.npc-control-immunity-preserved"
foreach ($mapping in @("buildabuff`t", "xp_bonus_general`t", "xp_granted_general`t", "tcg_xp_bonus`t", "tcg_xp_granted`t"))
{
    Assert-Contract ($effectMap.Contains($mapping)) "p14.buff-progression.compatibility.effect.$($mapping.Trim())"
}
Assert-Contract ($effectMap.Contains("tcg_gcw_bonus`tgcwBonusGeneral`t") -and
    $effectMap.Contains("gcw_mini_turret`tgcwMiniTurret`t")) `
    "p14.buff-progression.compatibility.gcw-consumable-effect-mappings-preserved"

$masterItemPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/master_item.tab"
$itemStatsPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/item/master_item/item_stats.tab"
$clickItemPath = Join-Path $scriptRoot "item/buff_click_item.java"
$masterItemText = Get-Content -LiteralPath $masterItemPath -Raw
$itemStatsText = Get-Content -LiteralPath $itemStatsPath -Raw
$clickItemText = Get-Content -LiteralPath $clickItemPath -Raw
$retainedGcwConsumableItems = @(
    @{ item = "item_tcg_loot_reward_series3_hh_15_torpedo_warhead"; buff = "tcg_series3_hh_15_torpedo_warhead" },
    @{ item = "item_tcg_loot_reward_series7_rocket_launcher"; buff = "tcg_series7_rocket_launcher" },
    @{ item = "item_gcw_mini_turret_consumable"; buff = "gcw_mini_turret" }
)
$retainedClickItems = 0
foreach ($entry in $retainedGcwConsumableItems)
{
    if ($masterItemText.Contains("$($entry.item)`t") -and
        $itemStatsText.Contains("$($entry.item)`t") -and
        $itemStatsText.Contains("`t$($entry.buff)`t")) { $retainedClickItems++ }
}
$clickUseBody = Get-SourceSlice $clickItemText "if (buff.canApplyBuff(player, buffName))" "return SCRIPT_CONTINUE;`r`n    }"
Assert-Contract ($retainedClickItems -eq [int]$contract.expected.retainedGcwConsumableClickItems -and
    (Is-Before $clickUseBody "if (buff.canApplyBuff(player, buffName))" "static_item.decrementStaticItem(self)") -and
    $clickUseBody.Contains("else") -and $clickUseBody.Contains("CANT_APPLY_BUFF") -and
    -not [bool]$contract.expected.gcwConsumableItemsDecrementedOnRejectedUse) `
    "p14.buff-progression.compatibility.gcw-click-items-preserved-without-rejected-consumption"
$retainedControlImmunityItems = @(
    @{ item = "item_tow_hk47_move_immune_06_01"; buff = "towHk47MoveImmuneItem" },
    @{ item = "item_tow_mafosa_mez_immune_06_01"; buff = "towMafosaMezImmune" },
    @{ item = "item_treasure_map_bonus_consumable_04_03"; buff = "treasure_bonus_snare_immunity" }
)
$retainedControlImmunityClickItems = 0
foreach ($entry in $retainedControlImmunityItems)
{
    if ($masterItemText.Contains("$($entry.item)`t") -and
        $itemStatsText.Contains("$($entry.item)`t") -and
        $itemStatsText.Contains("`t$($entry.buff)`t")) { $retainedControlImmunityClickItems++ }
}
Assert-Contract ($retainedControlImmunityClickItems -eq [int]$contract.expected.retainedPlayerControlImmunityClickItems -and
    (Is-Before $clickUseBody "if (buff.canApplyBuff(player, buffName))" "static_item.decrementStaticItem(self)") -and
    -not [bool]$contract.expected.playerControlImmunityItemsDecrementedOnRejectedUse) `
    "p14.buff-progression.compatibility.control-immunity-click-items-preserved-without-rejected-consumption"

$performancePath = Join-Path $scriptRoot "library/performance.java"
$performanceText = Get-Content -LiteralPath $performancePath -Raw
Assert-Contract ($performanceText.Contains("healing_dance_mind") -and
    $performanceText.Contains("healing_music_mind") -and $performanceText.Contains("private_buff_mind") -and
    $performanceText.Contains("getUnmodifiedMaxAttrib")) "p14.buff-progression.precu-attribute-session.preserved"

$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
    "p14.buff-progression.direct-source-pin"

$missionMap = [ordered]@{
    "mission_terminal.java" = (Join-Path $scriptRoot "systems/missions/base/mission_terminal.java")
    "mission_base.java" = (Join-Path $scriptRoot "systems/missions/base/mission_base.java")
    "missions.java" = (Join-Path $scriptRoot "library/missions.java")
}
foreach ($mission in $missionMap.GetEnumerator())
{
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $mission.Value).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$contract.continuityEvidence.missionSourceSha256.($mission.Key)) `
        "p14.buff-progression.mission-source.$($mission.Key).unchanged"
}

if ($failures.Count -gt 0)
{
    throw "P14 post-NGE buff progression retirement contract failed: $($failures -join ', ')"
}

Write-Host "P14 post-NGE buff progression retirement contract passed."
