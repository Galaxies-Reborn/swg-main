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
$avoidIncapInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_P14_PLAYER_AVOID_INCAP_HEAL_BUFFS" `
    "public static boolean isRetiredPostP14PlayerAvoidIncapHealBuff"
$avoidIncapCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostP14PlayerAvoidIncapHealState" `
    "public static boolean isRetiredPostNgeBountyHunterShieldBuff"
$queuedCommunicationIdentityBody = Get-SourceSlice $buffText `
    "private static final String RETIRED_POST_NGE_PLAYER_QUEUED_BATTLEFIELD_COMMUNICATION_BUFF" `
    "private static final String RETIRED_POST_NGE_PLAYER_RADAR_INVISIBILITY_EFFECT"
$groupBuffInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_NGE_PLAYER_GROUP_BUFFS" `
    "public static boolean isRetiredPostNgePlayerGroupBuffName"
$professionInspirationInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_NGE_PLAYER_PROFESSION_INSPIRATION_BUFFS" `
    "public static boolean isRetiredPostNgePlayerProfessionInspirationBuffName"
$professionInspirationScriptVarCleanupBody = Get-SourceSlice $buffText `
    "public static void clearPostNgePlayerProfessionInspirationScriptVars" `
    "public static void retirePostNgePlayerProfessionInspirationState"
$professionInspirationCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostNgePlayerProfessionInspirationState" `
    "private static final String[] RETIRED_POST_NGE_PLAYER_GROUP_BUFFS"
$professionImmunityInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_NGE_PLAYER_PROFESSION_IMMUNITY_BUFFS" `
    "public static boolean isRetiredPostNgePlayerProfessionImmunityBuffName"
$professionImmunityNamePredicateBody = Get-SourceSlice $buffText `
    "public static boolean isRetiredPostNgePlayerProfessionImmunityBuffName" `
    "public static boolean isRetiredPostNgePlayerProfessionImmunityBuff(obj_id target"
$professionImmunityBuffPredicateBody = Get-SourceSlice $buffText `
    "public static boolean isRetiredPostNgePlayerProfessionImmunityBuff(obj_id target" `
    "public static void retirePostNgePlayerProfessionImmunityState"
$professionImmunityCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostNgePlayerProfessionImmunityState" `
    "private static final String[] RETIRED_POST_NGE_PLAYER_PROFESSION_INSPIRATION_BUFFS"
$groupBuffCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostNgePlayerGroupBuffState" `
    "private static final String[] RETIRED_POST_NGE_PLAYER_FLAT_ATTRIBUTE_BUFFS"
$flatAttributeInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_NGE_PLAYER_FLAT_ATTRIBUTE_BUFFS" `
    "public static boolean isRetiredPostNgePlayerFlatAttributeBuffName"
$flatAttributeCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostNgePlayerFlatAttributeState" `
    "private static final String[] RETIRED_POST_NGE_PLAYER_ATTRIBUTE_PERCENT_BUFFS"
$attributePercentInventoryBody = Get-SourceSlice $buffText `
    "private static final String[] RETIRED_POST_NGE_PLAYER_ATTRIBUTE_PERCENT_BUFFS" `
    "public static boolean isRetiredPostNgePlayerAttributePercentBuffName"
$attributePercentCleanupBody = Get-SourceSlice $buffText `
    "public static void retirePostNgePlayerAttributePercentState" `
    "private static final String[] RETIRED_POST_NGE_PLAYER_DAMAGE_REDUCTION_MODIFIERS"
$buffAdmissionBody = Get-SourceSlice $buffText `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static boolean applyBuff(obj_id target, String name)"
$meditationTickBody = Get-SourceSlice ([string]$sourceTexts["player/base/base_player.java"]) `
    "public int handleMeditationTick" "public int msgCoupDeGraceAuthoritativeCheck"
$criticalHealBody = Get-SourceSlice ([string]$sourceTexts["player/base/base_player.java"]) `
    "public boolean performCriticalHeal" "public void sendSmugglerSystemBootstrap"
Assert-Contract ($flagBody.Contains("return true;")) "p14.buff-progression.central-flag.true"
foreach ($buffName in @($contract.expected.retiredBuffs))
{
    $retiredByCentralLifecycle = $cleanupBody.Contains(
        "removeBuff(player, `"$buffName`")")
    if ($buffName -ceq "general_inspiration")
    {
        $retiredByCentralLifecycle =
            $professionInspirationInventoryBody.Contains('"general_inspiration"') -and
            $professionInspirationCleanupBody.Contains(
                "removeBuff(player, activeBuff)") -and
            $cleanupBody.Contains(
                "retirePostNgePlayerProfessionInspirationState(player);")
    }
    Assert-Contract $retiredByCentralLifecycle `
        "p14.buff-progression.cleanup.buff.$buffName"
}
$professionInspirationNames = @([regex]::Matches(
    $professionInspirationInventoryBody, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-Contract ($professionInspirationNames.Count -eq
        [int]$contract.expected.retiredPlayerProfessionInspirationBuffCount -and
    @($professionInspirationNames | Select-Object -Unique).Count -eq
        $professionInspirationNames.Count -and
    [bool]$contract.expected.professionInspirationCleanupCentralized -and
    $professionInspirationCleanupBody.Contains("getAllBuffs(player)") -and
    $professionInspirationCleanupBody.Contains(
        "isRetiredPostNgePlayerProfessionInspirationBuff(player, data)") -and
    $professionInspirationCleanupBody.Contains("removeBuff(player, activeBuff)")) `
    "p14.buff-progression.profession-inspiration.central-lifecycle"
$expectedProfessionImmunityNames = @(
    $contract.expected.retiredPlayerProfessionImmunityBuffs |
        ForEach-Object { [string]$_ })
$actualProfessionImmunityNames = @([regex]::Matches(
    $professionImmunityInventoryBody, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$professionImmunityAdmissionGate = $buffAdmissionBody.IndexOf(
    "isRetiredPostNgePlayerProfessionImmunityBuff(target, bdata)",
    [StringComparison]::Ordinal)
$professionImmunityExistingBuffReturn = $buffAdmissionBody.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($actualProfessionImmunityNames.Count -eq
        $expectedProfessionImmunityNames.Count -and
    (($actualProfessionImmunityNames -join "`n") -ceq
        ($expectedProfessionImmunityNames -join "`n")) -and
    $professionImmunityNamePredicateBody.Contains(
        "buffName.equals(retiredBuff)") -and
    $professionImmunityBuffPredicateBody.Contains("isPlayer(target)") -and
    $professionImmunityBuffPredicateBody.Contains(
        "isRetiredPostNgePlayerProfessionImmunityBuffName(data.buffName)") -and
    $professionImmunityCleanupBody.Contains("!isPlayer(player)") -and
    $professionImmunityCleanupBody.Contains("getAllBuffs(player)") -and
    $professionImmunityCleanupBody.Contains(
        "combat_engine.getBuffData(activeBuff)") -and
    $professionImmunityCleanupBody.Contains("removeBuff(player, activeBuff)") -and
    $cleanupBody.Contains(
        "retirePostNgePlayerProfessionImmunityState(player);") -and
    $professionImmunityAdmissionGate -ge 0 -and
    $professionImmunityExistingBuffReturn -gt $professionImmunityAdmissionGate -and
    -not [bool]$contract.expected.playerProfessionImmunityBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerProfessionImmunityStateRemoved) `
    "p14.buff-progression.profession-immunity.admission-and-central-lifecycle"
$queuedCommunicationAdmissionGate = $buffAdmissionBody.IndexOf(
    "isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuff(target, bdata)",
    [StringComparison]::Ordinal)
$queuedCommunicationExistingBuffReturn = $buffAdmissionBody.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($queuedCommunicationIdentityBody.Contains(
        'RETIRED_POST_NGE_PLAYER_QUEUED_BATTLEFIELD_COMMUNICATION_BUFF = "battlefield_communication_run"') -and
    $queuedCommunicationIdentityBody.Contains("isPlayer(target) && data != null") -and
    $queuedCommunicationIdentityBody.Contains(
        "hasBuff(player, RETIRED_POST_NGE_PLAYER_QUEUED_BATTLEFIELD_COMMUNICATION_BUFF)") -and
    $queuedCommunicationIdentityBody.Contains(
        "removeBuff(player, RETIRED_POST_NGE_PLAYER_QUEUED_BATTLEFIELD_COMMUNICATION_BUFF)") -and
    $cleanupBody.Contains(
        "retirePostNgePlayerQueuedBattlefieldCommunicationState(player);") -and
    $queuedCommunicationAdmissionGate -ge 0 -and
    $queuedCommunicationExistingBuffReturn -gt $queuedCommunicationAdmissionGate -and
    -not [bool]$contract.expected.playerQueuedBattlefieldCommunicationBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerQueuedBattlefieldCommunicationBuffStateRemoved) `
    "p14.buff-progression.queued-battlefield-communication.admission-and-central-lifecycle"
$expectedGroupBuffs = @($contract.expected.retiredPlayerGroupBuffs | Sort-Object)
$actualGroupBuffs = @([regex]::Matches($groupBuffInventoryBody, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($actualGroupBuffs.Count -eq
        [int]$contract.expected.retiredPlayerGroupBuffCount -and
    @($actualGroupBuffs | Select-Object -Unique).Count -eq
        $actualGroupBuffs.Count -and
    (($actualGroupBuffs -join "`n") -ceq
        ($expectedGroupBuffs -join "`n")) -and
    $groupBuffCleanupBody.Contains("isPlayer(player)") -and
    $groupBuffCleanupBody.Contains("removeBuff(player, activeBuff)") -and
    $cleanupBody.Contains("retirePostNgePlayerGroupBuffState(player);") -and
    (Is-Before $buffAdmissionBody "isRetiredPostNgePlayerGroupBuff(target, bdata)" "hasBuff(target, nameCrc)") -and
    -not [bool]$contract.expected.playerGroupBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerGroupBuffsRemoved) `
    "p14.buff-progression.group-buff.player-state-and-admission-retired"
$expectedFlatAttributeBuffs = @($contract.expected.retiredPlayerFlatAttributeBuffs | Sort-Object)
$actualFlatAttributeBuffs = @([regex]::Matches($flatAttributeInventoryBody, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($actualFlatAttributeBuffs.Count -eq
        [int]$contract.expected.retiredPlayerFlatAttributeBuffCount -and
    @($actualFlatAttributeBuffs | Select-Object -Unique).Count -eq
        $actualFlatAttributeBuffs.Count -and
    (($actualFlatAttributeBuffs -join "`n") -ceq
        ($expectedFlatAttributeBuffs -join "`n")) -and
    $flatAttributeCleanupBody.Contains("isPlayer(player)") -and
    $flatAttributeCleanupBody.Contains("removeBuff(player, activeBuff)") -and
    $cleanupBody.Contains("retirePostNgePlayerFlatAttributeState(player);") -and
    (Is-Before $buffAdmissionBody "isRetiredPostNgePlayerFlatAttributeBuff(target, bdata)" "hasBuff(target, nameCrc)") -and
    -not [bool]$contract.expected.playerFlatAttributeBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerFlatAttributeBuffsRemoved) `
    "p14.buff-progression.flat-attribute.player-state-and-admission-retired"
$expectedAttributePercentBuffs = @($contract.expected.retiredPlayerAttributePercentBuffs | Sort-Object)
$actualAttributePercentBuffs = @([regex]::Matches($attributePercentInventoryBody, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($actualAttributePercentBuffs.Count -eq
        [int]$contract.expected.retiredPlayerAttributePercentBuffCount -and
    @($actualAttributePercentBuffs | Select-Object -Unique).Count -eq
        $actualAttributePercentBuffs.Count -and
    (($actualAttributePercentBuffs -join "`n") -ceq
        ($expectedAttributePercentBuffs -join "`n")) -and
    $attributePercentCleanupBody.Contains("isPlayer(player)") -and
    $attributePercentCleanupBody.Contains("removeBuff(player, activeBuff)") -and
    $cleanupBody.Contains("retirePostNgePlayerAttributePercentState(player);") -and
    (Is-Before $buffAdmissionBody "isRetiredPostNgePlayerAttributePercentBuff(target, bdata)" "hasBuff(target, nameCrc)") -and
    -not [bool]$contract.expected.playerAttributePercentBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerAttributePercentBuffsRemoved) `
    "p14.buff-progression.attribute-percent.player-state-and-admission-retired"
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
$expectedAvoidIncapBuffs = @($contract.expected.retiredPlayerAvoidIncapHealBuffs | Sort-Object)
$actualAvoidIncapBuffs = @([regex]::Matches($avoidIncapInventoryBody, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($actualAvoidIncapBuffs.Count -eq [int]$contract.expected.retiredPlayerAvoidIncapHealBuffCount -and
    @($actualAvoidIncapBuffs | Select-Object -Unique).Count -eq $actualAvoidIncapBuffs.Count -and
    (($actualAvoidIncapBuffs -join "`n") -ceq ($expectedAvoidIncapBuffs -join "`n")) -and
    -not [bool]$contract.expected.postP14PlayerAvoidIncapHealBuffAdmissionReachable -and
    $avoidIncapCleanupBody.Contains("isPlayer(player)") -and
    $avoidIncapCleanupBody.Contains("removeBuff(player, retiredBuff)") -and
    $avoidIncapCleanupBody.Contains('utils.removeScriptVar(player, "buff_handler.gcw_critical_heal")') -and
    $cleanupBody.Contains("retirePostP14PlayerAvoidIncapHealState(player);") -and
    (Is-Before $buffAdmissionBody "isRetiredPostP14PlayerAvoidIncapHealBuff(bdata.buffName)" "hasBuff(target, nameCrc)")) `
    "p14.buff-progression.avoid-incap-heal.player-state-and-admission-retired"
Assert-Contract (-not [bool]$contract.expected.postP14ReactiveCriticalHealReachable -and
    $criticalHealBody.Contains("buff.isPostNgeBuffProgressionRetired()") -and
    $criticalHealBody.Contains("buff.retirePostP14PlayerAvoidIncapHealState(self);") -and
    (Is-Before $criticalHealBody "buff.isPostNgeBuffProgressionRetired()" "buff.getAllBuffs(self)") -and
    (Is-Before $criticalHealBody "return false;" 'type.equals("avoid_incap_heal")') -and
    -not $criticalHealBody.Contains("avoidIncapacitation")) `
    "p14.buff-progression.avoid-incap-heal.reactive-heal-fails-closed"
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
    $treeRetired = ($cleanupBody + $gcwConsumableCleanupBody +
        $professionInspirationScriptVarCleanupBody).Contains(
            "removeScriptVarTree(player, `"$tree`")")
    if ($tree -ceq "buff.general_inspiration")
    {
        $treeRetired = $professionInspirationInventoryBody.Contains(
                '"general_inspiration"') -and
            $professionInspirationScriptVarCleanupBody.Contains(
                'removeScriptVarTree(player, "buff." + retiredBuff)')
    }
    Assert-Contract $treeRetired `
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
$avoidIncapAddBody = Get-SourceSlice $handlerText "public int onIncapHealAddBuffHandler" "public int onIncapHealRemoveBuffHandler"
$avoidIncapRemoveBody = Get-SourceSlice $handlerText "public int onIncapHealRemoveBuffHandler" "public int healEffectAddBuffHandler"
$queuedCommunicationAddBody = Get-SourceSlice $handlerText `
    "public int battlefieldCommuncationsGlowAddBuffHandler" `
    "public int battlefieldCommuncationsGlowRemoveBuffHandler"
$queuedCommunicationRemoveBody = Get-SourceSlice $handlerText `
    "public int battlefieldCommuncationsGlowRemoveBuffHandler" `
    "public int empireDayImperialRecruitmentAddBuffHandler"
$groupBuffAddBody = Get-SourceSlice $handlerText `
    "public int groupAddBuffHandler" `
    "public int groupRemoveBuffHandler"
$groupBuffRemoveBody = Get-SourceSlice $handlerText `
    "public int groupRemoveBuffHandler" `
    "public int OnTriggerVolumeEntered"
$flatAttributeAddBody = Get-SourceSlice $handlerText `
    "public int attribAddBuffHandler" `
    "public int attribRemoveBuffHandler"
$flatAttributeRemoveBody = Get-SourceSlice $handlerText `
    "public int attribRemoveBuffHandler" `
    "public int attribPercentAddBuffHandler"
$attributePercentAddBody = Get-SourceSlice $handlerText `
    "public int attribPercentAddBuffHandler" `
    "public int attribPercentRemoveBuffHandler"
$attributePercentRemoveBody = Get-SourceSlice $handlerText `
    "public int attribPercentRemoveBuffHandler" `
    "public int skillAddBuffHandler"
$healEffectAddBody = Get-SourceSlice $handlerText `
    "public int healEffectAddBuffHandler" `
    "public int healEffectRemoveBuffHandler"
$healEffectRemoveBody = Get-SourceSlice $handlerText `
    "public int healEffectRemoveBuffHandler" `
    "public int buildabuffAddBuffHandler"
$immunityAddBody = Get-SourceSlice $handlerText `
    "public int immunityAddBuffHandler" `
    "public int dotReductionAddBuffHandler"
$immunityRemoveBody = Get-SourceSlice $handlerText `
    "public int immunityRemoveBuffHandler" `
    "public int actionBurnAddBuffHandler"
$healEffectGuard = $healEffectAddBody.IndexOf(
    "if (isPlayer(self))", [StringComparison]::Ordinal)
$healEffectInspirationPredicate = $healEffectAddBody.IndexOf(
    "buff.isRetiredPostNgePlayerProfessionInspirationBuffName(buffName)",
    [StringComparison]::Ordinal)
$healEffectInspirationCleanup = $healEffectAddBody.IndexOf(
    "buff.retirePostNgePlayerProfessionInspirationState(self);",
    [StringComparison]::Ordinal)
$healEffectInspirationReturn = $healEffectAddBody.IndexOf(
    "return SCRIPT_OVERRIDE;", $healEffectInspirationCleanup,
    [StringComparison]::Ordinal)
$healEffectProxyPredicate = $healEffectAddBody.IndexOf(
    "buff.isRetiredPostNgePlayerProfessionProxyBuffName(buffName)",
    [StringComparison]::Ordinal)
$healEffectProxyCleanup = $healEffectAddBody.IndexOf(
    "buff.retirePostNgePlayerProfessionProxyState(self);",
    [StringComparison]::Ordinal)
$healEffectProxyReturn = $healEffectAddBody.IndexOf(
    "return SCRIPT_OVERRIDE;", $healEffectProxyCleanup,
    [StringComparison]::Ordinal)
$healEffectSpyPredicate = $healEffectAddBody.IndexOf(
    "player_stealth.isRetiredPostNgeSpyBuffName(buffName)",
    [StringComparison]::Ordinal)
$healEffectSpyCleanup = $healEffectAddBody.IndexOf(
    "player_stealth.retirePostNgeSpyPlayerState(self);",
    [StringComparison]::Ordinal)
$healEffectSpyReturn = $healEffectAddBody.IndexOf(
    "return SCRIPT_OVERRIDE;", $healEffectSpyCleanup,
    [StringComparison]::Ordinal)
$healEffectActionWriter = $healEffectAddBody.IndexOf(
    "healing.healDamage(self, ACTION, (int)value);",
    [StringComparison]::Ordinal)
$healEffectHealthWriter = $healEffectAddBody.IndexOf(
    "healing.healDamage(caster, self, HEALTH, (int)value);",
    [StringComparison]::Ordinal)
$professionImmunityHandlerGuard = $immunityAddBody.IndexOf(
    "if (isPlayer(self) && buff.isRetiredPostNgePlayerProfessionImmunityBuffName(buffName))",
    [StringComparison]::Ordinal)
$professionImmunityHandlerCleanup = $immunityAddBody.IndexOf(
    "buff.retirePostNgePlayerProfessionImmunityState(self);",
    [StringComparison]::Ordinal)
$professionImmunityHandlerReturn = $immunityAddBody.IndexOf(
    "return SCRIPT_OVERRIDE;", $professionImmunityHandlerCleanup,
    [StringComparison]::Ordinal)
$professionImmunityWriters = @(
    $immunityAddBody.IndexOf("buff.performBuffDotImmunity", [StringComparison]::Ordinal),
    $immunityAddBody.IndexOf("removeAllModifiersOfType", [StringComparison]::Ordinal),
    $immunityAddBody.IndexOf("getAllBuffs(self)", [StringComparison]::Ordinal),
    $immunityAddBody.IndexOf("setScriptVar(self", [StringComparison]::Ordinal)
)
Assert-Contract (([regex]::Matches($handlerText,
        'buff[.]isRetiredPostNgePlayerGroupBuffName\(buffName\)')).Count -eq
        [int]$contract.expected.productionGroupAddHandlersGuarded -and
    $groupBuffAddBody.Contains("isPlayer(self)") -and
    (Is-Before $groupBuffAddBody "buff.isRetiredPostNgePlayerGroupBuffName(buffName)" "effectName = effectName.substring") -and
    (Is-Before $groupBuffAddBody "return SCRIPT_OVERRIDE;" "buff.applyBuff(") -and
    -not $groupBuffRemoveBody.Contains(
        "isRetiredPostNgePlayerGroupBuffName") -and
    $groupBuffRemoveBody.Contains("utils.removeScriptVar(self, var)") -and
    $groupBuffRemoveBody.Contains("messageTo(groupMember, `"setGroupBuffs`"") -and
    $groupBuffRemoveBody.Contains("removeTriggerVolume(`"group_buff_breach`")") -and
    [bool]$contract.expected.groupRemoveCleanupPreserved -and
    [bool]$contract.expected.npcGroupBuffCompatibilityPreserved) `
    "p14.buff-progression.group-buff.handler-fails-closed-for-players"
Assert-Contract (([regex]::Matches($handlerText,
        'buff[.]isRetiredPostNgePlayerFlatAttributeBuffName\(buffName\)')).Count -eq
        [int]$contract.expected.productionFlatAttributeAddHandlersGuarded -and
    $flatAttributeAddBody.Contains("isPlayer(self)") -and
    (Is-Before $flatAttributeAddBody "buff.isRetiredPostNgePlayerFlatAttributeBuffName(buffName)" "int attribute = ATTRIB_ERROR") -and
    (Is-Before $flatAttributeAddBody "return SCRIPT_OVERRIDE;" "addAttribModifier(self, am)") -and
    -not $flatAttributeRemoveBody.Contains(
        "isRetiredPostNgePlayerFlatAttributeBuffName") -and
    $flatAttributeRemoveBody.Contains("removeAttribOrSkillModModifier(self, effectName)") -and
    [bool]$contract.expected.flatAttributeRemoveCleanupPreserved -and
    [bool]$contract.expected.nonPlayerFlatAttributeCompatibilityPreserved) `
    "p14.buff-progression.flat-attribute.handler-fails-closed-for-players"
Assert-Contract (([regex]::Matches($handlerText,
        'buff[.]isRetiredPostNgePlayerAttributePercentBuffName\(buffName\)')).Count -eq
        [int]$contract.expected.productionAttributePercentAddHandlersGuarded -and
    $attributePercentAddBody.Contains("isPlayer(self)") -and
    (Is-Before $attributePercentAddBody "buff.isRetiredPostNgePlayerAttributePercentBuffName(buffName)" "int attribute = ATTRIB_ERROR") -and
    (Is-Before $attributePercentAddBody "return SCRIPT_OVERRIDE;" "addAttribModifier(self, am)") -and
    -not $attributePercentRemoveBody.Contains(
        "isRetiredPostNgePlayerAttributePercentBuffName") -and
    $attributePercentRemoveBody.Contains("removeAttribOrSkillModModifier(self, effectName)") -and
    [bool]$contract.expected.attributePercentRemoveCleanupPreserved -and
    [bool]$contract.expected.nonPlayerAttributePercentCompatibilityPreserved) `
    "p14.buff-progression.attribute-percent.handler-fails-closed-for-players"
Assert-Contract ($healEffectGuard -ge 0 -and
    $healEffectInspirationPredicate -gt $healEffectGuard -and
    $healEffectInspirationCleanup -gt $healEffectInspirationPredicate -and
    $healEffectInspirationReturn -gt $healEffectInspirationCleanup -and
    $healEffectProxyPredicate -gt $healEffectInspirationReturn -and
    $healEffectProxyCleanup -gt $healEffectProxyPredicate -and
    $healEffectProxyReturn -gt $healEffectProxyCleanup -and
    $healEffectSpyPredicate -gt $healEffectProxyReturn -and
    $healEffectSpyCleanup -gt $healEffectSpyPredicate -and
    $healEffectSpyReturn -gt $healEffectSpyCleanup -and
    $healEffectActionWriter -gt $healEffectSpyReturn -and
    $healEffectHealthWriter -gt $healEffectSpyReturn -and
    [int]$contract.expected.productionProfessionHealEffectHandlersGuarded -eq 1 -and
    -not [bool]$contract.expected.playerProfessionHealEffectWriterReachable -and
    $healEffectRemoveBody.Contains("return SCRIPT_CONTINUE;") -and
    -not $healEffectRemoveBody.Contains("isRetiredPostNgePlayerProfession") -and
    -not $healEffectRemoveBody.Contains("isRetiredPostNgeSpyBuffName") -and
    [bool]$contract.expected.professionHealEffectRemoveCompatibilityPreserved -and
    [bool]$contract.expected.nonPlayerProfessionHealEffectCompatibilityPreserved) `
    "p14.buff-progression.profession-heal-effect.direct-writers-fail-closed-for-players"
Assert-Contract ($professionImmunityHandlerGuard -ge 0 -and
    $professionImmunityHandlerCleanup -gt $professionImmunityHandlerGuard -and
    $professionImmunityHandlerReturn -gt $professionImmunityHandlerCleanup -and
    @($professionImmunityWriters | Where-Object {
        $_ -le $professionImmunityHandlerReturn
    }).Count -eq 0 -and
    @($professionImmunityWriters | Where-Object { $_ -lt 0 }).Count -eq 0 -and
    [int]$contract.expected.productionProfessionImmunityHandlersGuarded -eq 1 -and
    -not [bool]$contract.expected.playerProfessionImmunityWriterReachable -and
    $immunityRemoveBody.Contains("return SCRIPT_CONTINUE;") -and
    -not $immunityRemoveBody.Contains(
        "isRetiredPostNgePlayerProfessionImmunityBuffName") -and
    [bool]$contract.expected.professionImmunityRemoveCompatibilityPreserved -and
    [bool]$contract.expected.nonPlayerProfessionImmunityCompatibilityPreserved) `
    "p14.buff-progression.profession-immunity.direct-writers-fail-closed-for-players"
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
Assert-Contract ([int]$contract.expected.directAvoidIncapHealAddWriters -eq 1 -and
    -not [bool]$contract.expected.directAvoidIncapHealAddWriterPlayerReachable -and
    $avoidIncapAddBody.Contains("if (isPlayer(self))") -and
    $avoidIncapAddBody.Contains("buff.retirePostP14PlayerAvoidIncapHealState(self);") -and
    (Is-Before $avoidIncapAddBody "buff.retirePostP14PlayerAvoidIncapHealState(self);" "return SCRIPT_OVERRIDE;") -and
    (Is-Before $avoidIncapAddBody "return SCRIPT_OVERRIDE;" 'utils.setScriptVar(self, "buff_handler." + subtype, value)') -and
    [bool]$contract.expected.avoidIncapHealRemoveCleanupPreserved -and
    -not $avoidIncapRemoveBody.Contains("retirePostP14PlayerAvoidIncapHealState") -and
    $avoidIncapRemoveBody.Contains('utils.removeScriptVar(self, "buff_handler." + subtype)') -and
    [bool]$contract.expected.nonPlayerAvoidIncapHealCompatibilityPreserved) `
    "p14.buff-progression.avoid-incap-heal.direct-writer-fails-closed"
Assert-Contract ([int]$contract.expected.directQueuedBattlefieldCommunicationAddWriters -eq 1 -and
    -not [bool]$contract.expected.directQueuedBattlefieldCommunicationAddWriterPlayerReachable -and
    $queuedCommunicationAddBody.Contains("if (isPlayer(self)") -and
    $queuedCommunicationAddBody.Contains(
        "buff.isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuffName(buffName)") -and
    $queuedCommunicationAddBody.Contains(
        "buff.retirePostNgePlayerQueuedBattlefieldCommunicationState(self);") -and
    (Is-Before $queuedCommunicationAddBody `
        "buff.retirePostNgePlayerQueuedBattlefieldCommunicationState(self);" `
        "return SCRIPT_OVERRIDE;") -and
    (Is-Before $queuedCommunicationAddBody "return SCRIPT_OVERRIDE;" `
        'buff.removeBuff(self, "battlefield_radar_invisibility")') -and
    [bool]$contract.expected.queuedBattlefieldCommunicationRemoveCompatibilityPreserved -and
    -not $queuedCommunicationRemoveBody.Contains(
        "isRetiredPostNgePlayerQueuedBattlefieldCommunicationBuffName") -and
    $queuedCommunicationRemoveBody.Contains(
        'buff.applyBuff(self, "battlefield_radar_invisibility");') -and
    [bool]$contract.expected.nonPlayerQueuedBattlefieldCommunicationCompatibilityPreserved) `
    "p14.buff-progression.queued-battlefield-communication.direct-writer-fails-closed"

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
$allBuffRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t")
$queuedCommunicationRows = @($allBuffRows | Where-Object {
    $_.NAME -ceq "battlefield_communication_run"
})
$queuedCommunicationMappings = @(Import-Csv -LiteralPath $effectMapPath -Delimiter "`t" |
    Where-Object { $_.NAME -ceq "battlefield_communcations_glow" })
Assert-Contract ($queuedCommunicationRows.Count -eq
        [int]$contract.expected.retainedQueuedBattlefieldCommunicationBuffRows -and
    [string]$queuedCommunicationRows[0].GROUP1 -ceq "battlefield_communication_run" -and
    [float]$queuedCommunicationRows[0].DURATION -eq 90.0 -and
    [string]$queuedCommunicationRows[0].EFFECT1_PARAM -ceq "battlefield_communcations_glow" -and
    [string]$queuedCommunicationRows[0].PARTICLE -ceq "appearance/pt_battlefield_runner.prt" -and
    [int]$queuedCommunicationRows[0].VISIBLE -eq 1 -and
    [int]$queuedCommunicationRows[0].REMOVE_ON_DEATH -eq 1 -and
    [int]$queuedCommunicationRows[0].IS_PERSISTENT -eq 1 -and
    $queuedCommunicationMappings.Count -eq
        [int]$contract.expected.retainedQueuedBattlefieldCommunicationEffectMappingRows -and
    [string]$queuedCommunicationMappings[0].TYPE -ceq "battlefieldCommuncationsGlow" -and
    [string]$queuedCommunicationMappings[0].SUBTYPE -ceq "battlefield_communcations_glow") `
    "p14.buff-progression.queued-battlefield-communication.data-authenticated"
$healEffectMappings = @(Import-Csv -LiteralPath $effectMapPath -Delimiter "`t" |
    Where-Object { $_.TYPE -ceq "healEffect" })
$healEffectMappingNames = @($healEffectMappings.NAME | Sort-Object)
$healEffectUses = @(
    foreach ($row in $allBuffRows)
    {
        foreach ($effect in 1..5)
        {
            $parameter = [string]$row.("EFFECT${effect}_PARAM")
            if ($healEffectMappingNames -ccontains $parameter)
            {
                [pscustomobject]@{
                    Name = [string]$row.NAME
                    Parameter = $parameter
                }
            }
        }
    }
)
$healEffectRowNames = @($healEffectUses.Name | Sort-Object -Unique)
$retiredHealEffectNames = @(
    $contract.expected.retiredPlayerProfessionHealEffectBuffs |
        ForEach-Object { [string]$_ })
$preservedHealEffectNames = @(
    $contract.expected.preservedLaterContentHealEffectBuffs |
        ForEach-Object { [string]$_ })
$retiredHealEffectUses = @($healEffectUses | Where-Object {
    $retiredHealEffectNames -ccontains [string]$_.Name })
$preservedHealEffectUses = @($healEffectUses | Where-Object {
    $preservedHealEffectNames -ccontains [string]$_.Name })
Assert-Contract ($healEffectMappings.Count -eq
        [int]$contract.expected.retainedHealEffectMappingRows -and
    (($healEffectMappingNames -join "`n") -ceq
        ((@("healing_action", "healing_health") | Sort-Object) -join "`n")) -and
    $healEffectRowNames.Count -eq [int]$contract.expected.retainedHealEffectBuffRows -and
    $healEffectUses.Count -eq [int]$contract.expected.retainedHealEffectUses -and
    @($retiredHealEffectUses.Name | Sort-Object -Unique).Count -eq
        [int]$contract.expected.retiredPlayerProfessionHealEffectBuffRows -and
    $retiredHealEffectUses.Count -eq
        [int]$contract.expected.retiredPlayerProfessionHealEffectUses -and
    @($preservedHealEffectUses.Name | Sort-Object -Unique).Count -eq
        [int]$contract.expected.preservedLaterContentHealEffectBuffRows -and
    $preservedHealEffectUses.Count -eq
        [int]$contract.expected.preservedLaterContentHealEffectUses -and
    ((@($retiredHealEffectUses.Name | Sort-Object -Unique) -join "`n") -ceq
        ((@($retiredHealEffectNames | Sort-Object)) -join "`n")) -and
    ((@($preservedHealEffectUses.Name | Sort-Object -Unique) -join "`n") -ceq
        ((@($preservedHealEffectNames | Sort-Object)) -join "`n")) -and
    @($healEffectRowNames | Where-Object {
        $retiredHealEffectNames -cnotcontains $_ -and
        $preservedHealEffectNames -cnotcontains $_
    }).Count -eq 0) `
    "p14.buff-progression.profession-heal-effect.complete-data-inventory-authenticated"
$immunityMappings = @(Import-Csv -LiteralPath $effectMapPath -Delimiter "`t" |
    Where-Object { $_.TYPE -ceq "immunity" })
$immunityMappingNames = @($immunityMappings.NAME | Sort-Object)
$immunityUses = @(
    foreach ($row in $allBuffRows)
    {
        foreach ($effect in 1..5)
        {
            $parameter = [string]$row.("EFFECT${effect}_PARAM")
            if ($immunityMappingNames -ccontains $parameter)
            {
                [pscustomobject]@{
                    Name = [string]$row.NAME
                    Parameter = $parameter
                }
            }
        }
    }
)
$immunityRowNames = @($immunityUses.Name | Sort-Object -Unique)
$preservedProfessionImmunityNames = @(
    $contract.expected.preservedLaterContentImmunityBuffs |
        ForEach-Object { [string]$_ })
$retiredProfessionImmunityUses = @($immunityUses | Where-Object {
    $expectedProfessionImmunityNames -ccontains [string]$_.Name })
$preservedProfessionImmunityUses = @($immunityUses | Where-Object {
    $preservedProfessionImmunityNames -ccontains [string]$_.Name })
Assert-Contract ($immunityMappings.Count -eq
        [int]$contract.expected.retainedImmunityEffectMappingRows -and
    (($immunityMappingNames -join "`n") -ceq
        ((@("buff_purge", "debuff_purge", "dot_immunity",
            "movement_immunity", "state_immunity") | Sort-Object) -join "`n")) -and
    $immunityRowNames.Count -eq [int]$contract.expected.retainedImmunityBuffRows -and
    $immunityUses.Count -eq [int]$contract.expected.retainedImmunityEffectUses -and
    @($retiredProfessionImmunityUses.Name | Sort-Object -Unique).Count -eq
        [int]$contract.expected.retiredPlayerProfessionImmunityBuffRows -and
    $retiredProfessionImmunityUses.Count -eq
        [int]$contract.expected.retiredPlayerProfessionImmunityEffectUses -and
    @($preservedProfessionImmunityUses.Name | Sort-Object -Unique).Count -eq
        [int]$contract.expected.preservedLaterContentImmunityBuffRows -and
    $preservedProfessionImmunityUses.Count -eq
        [int]$contract.expected.preservedLaterContentImmunityEffectUses -and
    ((@($retiredProfessionImmunityUses.Name | Sort-Object -Unique) -join "`n") -ceq
        ((@($expectedProfessionImmunityNames | Sort-Object)) -join "`n")) -and
    ((@($preservedProfessionImmunityUses.Name | Sort-Object -Unique) -join "`n") -ceq
        ((@($preservedProfessionImmunityNames | Sort-Object)) -join "`n")) -and
    @($immunityRowNames | Where-Object {
        $expectedProfessionImmunityNames -cnotcontains $_ -and
        $preservedProfessionImmunityNames -cnotcontains $_
    }).Count -eq 0) `
    "p14.buff-progression.profession-immunity.complete-data-inventory-authenticated"
$groupBuffMappings = @(Import-Csv -LiteralPath $effectMapPath -Delimiter "`t" |
    Where-Object { $_.TYPE -ceq "group" })
$groupBuffEffectNames = @($groupBuffMappings.NAME)
$groupBuffRows = @($allBuffRows | Where-Object {
    $parameters = @($_.EFFECT1_PARAM, $_.EFFECT2_PARAM, $_.EFFECT3_PARAM,
        $_.EFFECT4_PARAM, $_.EFFECT5_PARAM)
    @($parameters | Where-Object { $groupBuffEffectNames -ccontains $_ }).Count -gt 0
})
$retiredGroupBuffRows = @($groupBuffRows |
    Where-Object { $expectedGroupBuffs -ccontains $_.NAME })
$unclassifiedGroupBuffRows = @($groupBuffRows | Where-Object {
    $expectedGroupBuffs -cnotcontains $_.NAME
})
Assert-Contract ($groupBuffMappings.Count -eq
        [int]$contract.expected.retainedGroupEffectMappingRows -and
    $groupBuffRows.Count -eq
        [int]$contract.expected.retainedGroupBuffRowCount -and
    $retiredGroupBuffRows.Count -eq
        [int]$contract.expected.retiredPlayerGroupBuffCount -and
    $unclassifiedGroupBuffRows.Count -eq 0 -and
    ((@($retiredGroupBuffRows.NAME | Sort-Object) -join "`n") -ceq
        ($expectedGroupBuffs -join "`n"))) `
    "p14.buff-progression.group-buff.complete-data-inventory-authenticated"
Assert-Contract ([bool]$contract.expected.precuSquadLeaderCommandsPreserved -and
    [bool]$contract.expected.laterContentGroupRowsPreserved -and
    $expectedGroupBuffs -ccontains "sl_group_run" -and
    $expectedGroupBuffs -ccontains "sl_group_retreat" -and
    $expectedGroupBuffs -ccontains "of_buff_def_1" -and
    $expectedGroupBuffs -ccontains "veteranPlayerBuff" -and
    $expectedGroupBuffs -cnotcontains "formup" -and
    $expectedGroupBuffs -cnotcontains "rally" -and
    $expectedGroupBuffs -cnotcontains "retreat") `
    "p14.buff-progression.group-buff.precu-command-boundary-preserved"
$flatAttributeMappings = @(Import-Csv -LiteralPath $effectMapPath -Delimiter "`t" |
    Where-Object { $_.TYPE -ceq "attrib" })
$flatAttributeEffectNames = @($flatAttributeMappings.NAME)
$flatAttributeRows = @($allBuffRows | Where-Object {
    $parameters = @($_.EFFECT1_PARAM, $_.EFFECT2_PARAM, $_.EFFECT3_PARAM,
        $_.EFFECT4_PARAM, $_.EFFECT5_PARAM)
    @($parameters | Where-Object { $flatAttributeEffectNames -ccontains $_ }).Count -gt 0
})
$retiredFlatAttributeRows = @($flatAttributeRows |
    Where-Object { $expectedFlatAttributeBuffs -ccontains $_.NAME })
$expectedPreservedFlatAttributeBuffs = @(
    $contract.expected.preservedFlatAttributeBuffs | Sort-Object)
$preservedFlatAttributeRows = @($flatAttributeRows |
    Where-Object { $expectedPreservedFlatAttributeBuffs -ccontains $_.NAME })
$unclassifiedFlatAttributeRows = @($flatAttributeRows | Where-Object {
    $expectedFlatAttributeBuffs -cnotcontains $_.NAME -and
    $expectedPreservedFlatAttributeBuffs -cnotcontains $_.NAME
})
Assert-Contract ($flatAttributeMappings.Count -eq
        [int]$contract.expected.retainedFlatAttributeEffectMappingRows -and
    $flatAttributeRows.Count -eq
        [int]$contract.expected.retainedFlatAttributeBuffRowCount -and
    $retiredFlatAttributeRows.Count -eq
        [int]$contract.expected.retiredPlayerFlatAttributeBuffCount -and
    $preservedFlatAttributeRows.Count -eq
        [int]$contract.expected.preservedFlatAttributeBuffCount -and
    $unclassifiedFlatAttributeRows.Count -eq 0 -and
    ((@($retiredFlatAttributeRows.NAME | Sort-Object) -join "`n") -ceq
        ($expectedFlatAttributeBuffs -join "`n")) -and
    ((@($preservedFlatAttributeRows.NAME | Sort-Object) -join "`n") -ceq
        ($expectedPreservedFlatAttributeBuffs -join "`n"))) `
    "p14.buff-progression.flat-attribute.complete-data-inventory-authenticated"
Assert-Contract ([bool]$contract.expected.precuFlatAttributeCommandsPreserved -and
    [bool]$contract.expected.qaFlatAttributeFixturesPreserved -and
    [bool]$contract.expected.legitimateNpcFlatAttributeCompatibilityPreserved -and
    [bool]$contract.expected.laterContentFlatAttributeRowsPreserved -and
    $expectedPreservedFlatAttributeBuffs -ccontains "innate_regeneration" -and
    $expectedPreservedFlatAttributeBuffs -ccontains "innate_vitalize" -and
    $expectedPreservedFlatAttributeBuffs -ccontains "powerBoost" -and
    $expectedPreservedFlatAttributeBuffs -ccontains "testHealthBuff1" -and
    $expectedPreservedFlatAttributeBuffs -ccontains "minder_add_debuff" -and
    $expectedPreservedFlatAttributeBuffs -ccontains "jedi_statue_self_dps_debuff" -and
    $expectedFlatAttributeBuffs -cnotcontains "innate_regeneration" -and
    $expectedFlatAttributeBuffs -cnotcontains "powerBoost") `
    "p14.buff-progression.flat-attribute.precu-qa-npc-exceptions-preserved"
$attributePercentMappings = @(Import-Csv -LiteralPath $effectMapPath -Delimiter "`t" |
    Where-Object { $_.TYPE -ceq "attribPercent" })
$attributePercentEffectNames = @($attributePercentMappings.NAME)
$attributePercentRows = @($allBuffRows | Where-Object {
    $parameters = @($_.EFFECT1_PARAM, $_.EFFECT2_PARAM, $_.EFFECT3_PARAM,
        $_.EFFECT4_PARAM, $_.EFFECT5_PARAM)
    @($parameters | Where-Object { $attributePercentEffectNames -ccontains $_ }).Count -gt 0
})
$retiredAttributePercentRows = @($attributePercentRows |
    Where-Object { $expectedAttributePercentBuffs -ccontains $_.NAME })
$expectedPreservedAttributePercentBuffs = @(
    $contract.expected.preservedAttributePercentBuffs | Sort-Object)
$preservedAttributePercentRows = @($attributePercentRows |
    Where-Object { $expectedPreservedAttributePercentBuffs -ccontains $_.NAME })
$unclassifiedAttributePercentRows = @($attributePercentRows | Where-Object {
    $expectedAttributePercentBuffs -cnotcontains $_.NAME -and
    $expectedPreservedAttributePercentBuffs -cnotcontains $_.NAME
})
Assert-Contract ($attributePercentMappings.Count -eq
        [int]$contract.expected.retainedAttributePercentEffectMappingRows -and
    $attributePercentRows.Count -eq
        [int]$contract.expected.retainedAttributePercentBuffRowCount -and
    $retiredAttributePercentRows.Count -eq
        [int]$contract.expected.retiredPlayerAttributePercentBuffCount -and
    $preservedAttributePercentRows.Count -eq
        [int]$contract.expected.preservedAttributePercentBuffCount -and
    $unclassifiedAttributePercentRows.Count -eq 0 -and
    ((@($retiredAttributePercentRows.NAME | Sort-Object) -join "`n") -ceq
        ($expectedAttributePercentBuffs -join "`n")) -and
    ((@($preservedAttributePercentRows.NAME | Sort-Object) -join "`n") -ceq
        ($expectedPreservedAttributePercentBuffs -join "`n"))) `
    "p14.buff-progression.attribute-percent.complete-data-inventory-authenticated"
Assert-Contract ([bool]$contract.expected.precuCreatureHandlerEmboldenPreserved -and
    [bool]$contract.expected.precuCloningSicknessPreserved -and
    [bool]$contract.expected.laterContentAttributePercentMechanicsPreserved -and
    $expectedPreservedAttributePercentBuffs -ccontains "emboldenPet" -and
    $expectedPreservedAttributePercentBuffs -ccontains "cloning_sickness" -and
    $expectedPreservedAttributePercentBuffs -ccontains "biological_suppression" -and
    $expectedPreservedAttributePercentBuffs -ccontains "death_troopers_infection_3" -and
    $expectedAttributePercentBuffs -cnotcontains "emboldenPet" -and
    $expectedAttributePercentBuffs -cnotcontains "cloning_sickness") `
    "p14.buff-progression.attribute-percent.precu-and-later-content-exceptions-preserved"
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
$avoidIncapRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t" |
    Where-Object { $_.NAME -in $expectedAvoidIncapBuffs })
$avoidIncapMappings = @(Import-Csv -LiteralPath $effectMapPath -Delimiter "`t" |
    Where-Object { $_.TYPE -ceq "onIncapHeal" })
Assert-Contract ($avoidIncapMappings.Count -eq [int]$contract.expected.retainedAvoidIncapHealEffectMappingRows -and
    [string]$avoidIncapMappings[0].NAME -ceq "avoid_incap_heal" -and
    [string]$avoidIncapMappings[0].SUBTYPE -ceq "gcw_critical_heal" -and
    $avoidIncapRows.Count -eq [int]$contract.expected.retainedPlayerAvoidIncapHealBuffRows -and
    ((@($avoidIncapRows.NAME | Sort-Object) -join "`n") -ceq ($expectedAvoidIncapBuffs -join "`n")) -and
    @($avoidIncapRows | Where-Object { $_.EFFECT1_PARAM -cne "avoid_incap_heal" }).Count -eq 0) `
    "p14.buff-progression.compatibility.avoid-incap-heal-rows-preserved"
$precuJediAvoidRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t" |
    Where-Object { $_.NAME -match '^avoidIncapacitation(_[1-5])?$' })
$jediLibrary = Get-Content -LiteralPath (Join-Path $scriptRoot "library/jedi.java") -Raw
$terasKasiScript = Get-Content -LiteralPath (Join-Path $scriptRoot "player/skill/teraskasi.java") -Raw
Assert-Contract ([bool]$contract.expected.precuJediAvoidIncapacitationPreserved -and
    $precuJediAvoidRows.Count -eq [int]$contract.expected.precuJediAvoidIncapacitationBuffRows -and
    @($precuJediAvoidRows | Where-Object { $_.EFFECT1_PARAM -cne "avoid_incap" }).Count -eq 0 -and
    @($precuJediAvoidRows.NAME | Where-Object { $actualAvoidIncapBuffs -contains $_ }).Count -eq 0 -and
    $jediLibrary.Contains('buff.hasBuff(player, "avoidIncapacitation")') -and
    $terasKasiScript.Contains("meditation.forceOfWill(self, delta)")) `
    "p14.buff-progression.compatibility.precu-jedi-and-teras-kasi-incapacitation-preserved"
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
$retainedAvoidIncapItems = @(
    @{ item = "item_gcw_base_reactive_critical_heal_a_03_01"; buff = "gcw_base_critical_heal_a" },
    @{ item = "item_gcw_base_reactive_critical_heal_b_03_01"; buff = "gcw_base_critical_heal_b" },
    @{ item = "item_gcw_base_reactive_critical_heal_c_03_01"; buff = "gcw_base_critical_heal_c" },
    @{ item = "item_gcw_base_reactive_critical_heal_d_03_01"; buff = "gcw_base_critical_heal_d" },
    @{ item = "item_gcw_base_reactive_critical_heal_e_04_01"; buff = "gcw_base_critical_heal_e" },
    @{ item = "item_cs_reactive_critical_heal_e_04_01"; buff = "gcw_base_critical_heal_e" }
)
$retainedAvoidIncapClickItems = 0
foreach ($entry in $retainedAvoidIncapItems)
{
    if ($masterItemText.Contains("$($entry.item)`t") -and
        $itemStatsText.Contains("$($entry.item)`t") -and
        $itemStatsText.Contains("`t$($entry.buff)`t")) { $retainedAvoidIncapClickItems++ }
}
$pvpCommandTable = Get-Content -LiteralPath (Join-Path $sharedRoot "datatables/command/command_table.tab") -Raw
$tuskenCloningTable = Get-Content -LiteralPath (Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/spawning/heroic/tusken/cloning.tab") -Raw
Assert-Contract ($retainedAvoidIncapClickItems -eq [int]$contract.expected.retainedPlayerAvoidIncapHealClickItems -and
    -not [bool]$contract.expected.playerAvoidIncapHealItemsDecrementedOnRejectedUse -and
    $pvpCommandTable.Contains("command_pvp_last_man_ability`t") -and
    $pvpCommandTable.Contains("command_pvp_last_man_rebel_ability`t") -and
    $tuskenCloningTable.Contains("buffHandler:add:tusken_endurance:player")) `
    "p14.buff-progression.compatibility.avoid-incap-content-preserved-without-rejected-consumption"

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
