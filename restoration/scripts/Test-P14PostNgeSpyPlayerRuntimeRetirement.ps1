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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgeSpyPlayerRuntimeRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$sharedRoot = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game"
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

$relativeSourceMap = [ordered]@{
    "library/skill.java" = "library/skill.java"
    "player/base/base_player.java" = "player/base/base_player.java"
    "systems/buff/buff_handler.java" = "systems/buff/buff_handler.java"
    "systems/combat/combat_actions.java" = "systems/combat/combat_actions.java"
    "systems/combat/combat_base.java" = "systems/combat/combat_base.java"
    "systems/skills/stealth/player_stealth.java" = "systems/skills/stealth/player_stealth.java"
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.spy-retirement.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract (
        $patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256
    ) "p14.spy-retirement.overlay.authenticated"
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
) "p14.spy-retirement.overlay.target-set"
Assert-Contract (
    (Get-TextSha256 (($targets -join $lf) + $lf)) -ceq [string]$contract.buildEvidence.sourceSetSha256
) "p14.spy-retirement.source-set.authenticated"

$sourceTexts = @{}
$contentRecords = ""
foreach ($entry in $relativeSourceMap.GetEnumerator())
{
    $sourcePath = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $sourcePath -PathType Leaf) "p14.spy-retirement.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
        Assert-Contract (
            $hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)
        ) "p14.spy-retirement.source.$($entry.Key).authenticated"
        $contentRecords += "sku.0/sys.server/compiled/game/script/$($entry.Value)=$hash$lf"
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $sourcePath -Raw
    }
}
Assert-Contract (
    (Get-TextSha256 $contentRecords) -ceq [string]$contract.buildEvidence.sourceContentSha256
) "p14.spy-retirement.source-content.authenticated"

$shiftySetupSourceMap = [ordered]@{
    "library/buff.java" = "library/buff.java"
    "systems/buff/buff_handler.java" = "systems/buff/buff_handler.java"
    "systems/combat/combat_base.java" = "systems/combat/combat_base.java"
}
foreach ($entry in $shiftySetupSourceMap.GetEnumerator())
{
    $path = Join-Path $scriptRoot $entry.Value
    $expectedHash = [string]$contract.buildEvidence.shiftySetupSourceSha256.PSObject.Properties[$entry.Key].Value
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            $expectedHash) "p14.spy-retirement.shifty-setup.source.$($entry.Key).authenticated"
}

$skillText = [string]$sourceTexts["library/skill.java"]
$skillPredicate = Get-SourceSlice $skillText "public static boolean isRetiredPostNgeSpySkill" "public static boolean grant("
Assert-Contract (
    $skillPredicate.Contains('skillName.startsWith("class_spy_")') -and
    $skillPredicate.Contains('skillName.startsWith("expertise_sp_")')
) "p14.spy-retirement.skill-prefixes"

$grantBody = Get-SourceSlice $skillText "public static boolean grant(" "public static boolean grantSkillToPlayer("
$grantPlayerBody = Get-SourceSlice $skillText "public static boolean grantSkillToPlayer(" "public static boolean purchaseSkill("
$purchaseBody = Get-SourceSlice $skillText "public static boolean purchaseSkill(" "public static boolean hasRequiredXpForSkillPurchase("
Assert-Contract (
    (Is-Before $grantBody "isRetiredNgeProgressionSkillName(skillName)" "grantSkillToPlayer(target, skillName)") -and
    (Is-Before $grantPlayerBody "isRetiredNgeProgressionSkillName(skillName)" "grantSkill(player, skillName)") -and
    (Is-Before $purchaseBody "isRetiredNgeProgressionSkillName(skillName)" "getSkillPointCost(skillName)") -and
    (Is-Before $purchaseBody "isRetiredNgeProgressionSkillName(skillName)" "deductXpCostForSkillPurchase")
) "p14.spy-retirement.skill-entrypoints.fail-closed"

$stealthText = [string]$sourceTexts["systems/skills/stealth/player_stealth.java"]
$buffPredicate = Get-SourceSlice $stealthText "public static boolean isRetiredPostNgeSpyBuffName" "public static void retirePostNgeSpyPlayerState"
$cleanupBody = Get-SourceSlice $stealthText "public static void retirePostNgeSpyPlayerState" "public int OnAttach"
Assert-Contract (
    $buffPredicate.Contains('buffName.startsWith("invis_sp_")') -and
    $buffPredicate.Contains('buffName.startsWith("sp_")') -and
    $buffPredicate.Contains('buffName.equals("no_break_invis")')
) "p14.spy-retirement.buff-families"
Assert-Contract (
    $cleanupBody.Contains("!isPlayer(self)") -and
    $cleanupBody.Contains("buff.getAllBuffs(self)") -and
    $cleanupBody.Contains("buff.removeBuff(self, activeBuff)") -and
    $cleanupBody.Contains('utils.removeScriptVar(self, "sp_smoke_bomb")') -and
    $cleanupBody.Contains('utils.removeScriptVar(self, "sp_without_a_trace")') -and
    $cleanupBody.Contains("skill.isRetiredPostNgeSpySkill(playerSkill)") -and
    $cleanupBody.Contains("revokeSkillSilent(self, playerSkill)") -and
    $cleanupBody.Contains("recomputeCommandSeries(self)")
) "p14.spy-retirement.player-state.cleanup"

$attachBody = Get-SourceSlice $stealthText "public int OnAttach" "public int OnInitialize"
$initializeBody = Get-SourceSlice $stealthText "public int OnInitialize" "public int smokeBombTimerExpired"
$smokeBody = Get-SourceSlice $stealthText "public int smokeBombTimerExpired" "public int withoutTraceTimerExpired"
$traceBody = Get-SourceSlice $stealthText "public int withoutTraceTimerExpired" "public int invisibilityUpkeep"
Assert-Contract (
    $attachBody.Contains("retirePostNgeSpyPlayerState(self)") -and
    $initializeBody.Contains("retirePostNgeSpyPlayerState(self)")
) "p14.spy-retirement.attach-initialize.cleanup"
Assert-Contract (
    (Is-Before $smokeBody "if (isPlayer(self))" 'utils.hasScriptVar(self, "sp_smoke_bomb")') -and
    (Is-Before $traceBody "if (isPlayer(self))" 'utils.hasScriptVar(self, "sp_without_a_trace")')
) "p14.spy-retirement.timer-callbacks.fail-closed"

$upkeepBody = Get-SourceSlice $stealthText "public int invisibilityUpkeep" "public int msgMotionSensorTripped"
Assert-Contract (
    (Is-Before $upkeepBody "isRetiredPostNgeSpyBuffName(invisBuff)" "switch (invis)") -and
    $stealthText.Contains("public int msgMotionSensorTripped") -and
    $stealthText.Contains("public int msgTrackingBeaconLocationRequest")
) "p14.spy-retirement.upkeep-and-device-callback-boundary"

$cashSuccess = Get-SourceSlice $stealthText "public int handleStealCashSuccess" "public int handleStealCashFail"
$cashFail = Get-SourceSlice $stealthText "public int handleStealCashFail" "public int handleStealCashFinal"
$cashFinal = Get-SourceSlice $stealthText "public int handleStealCashFinal" ""
Assert-Contract (
    (Is-Before $cashSuccess "if (isPlayer(self))" "withdrawCashFromBank") -and
    (Is-Before $cashFail "if (isPlayer(self))" "CustomerServiceLog") -and
    (Is-Before $cashFinal "if (isPlayer(self))" "sendSystemMessageProse")
) "p14.spy-retirement.cash-callbacks.fail-closed"

$basePlayerText = [string]$sourceTexts["player/base/base_player.java"]
$skillGrantedBody = Get-SourceSlice $basePlayerText "public int OnSkillGranted" "public int handleStartJediKnightTrials"
Assert-Contract (
    (Is-Before $skillGrantedBody "skill.isRetiredNgeProgressionSkillName(skillName)" "badge.grantMasterSkillBadge") -and
    $skillGrantedBody.Contains("skill.isRetiredPostNgeSpySkill(skillName)") -and
    $skillGrantedBody.Contains("revokeSkillSilent(self, skillName)") -and
    $skillGrantedBody.Contains("player_stealth.retirePostNgeSpyPlayerState(self)") -and
    $skillGrantedBody.Contains("return SCRIPT_OVERRIDE;")
) "p14.spy-retirement.direct-grant-hook.fail-closed"

$combatBaseText = [string]$sourceTexts["systems/combat/combat_base.java"]
$actionPredicate = Get-SourceSlice $combatBaseText "public static boolean isRetiredPostNgeSpyPlayerAction" "public boolean combatStandardAction("
Assert-Contract (
    $actionPredicate.Contains("!isPlayer(self)") -and
    (Is-Before $actionPredicate 'actionName.equals("sp_hide_device_1")' 'actionName.startsWith("sp_")') -and
    (Is-Before $actionPredicate 'actionName.equals("sp_neutralize_device_1")' 'actionName.startsWith("sp_")') -and
    $actionPredicate.Contains('actionName.equals("steal")')
) "p14.spy-retirement.player-only-action-boundary"
$finalCombatAction = Get-SourceSlice $combatBaseText "public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon" "public boolean verifyCombatAction"
Assert-Contract (
    (Is-Before $finalCombatAction "isRetiredPostNgeSpyPlayerAction(self, actionName)" 'combat.revealPrecuFeignDeath(self, "combatCommand")') -and
    $finalCombatAction.Contains("return false;")
) "p14.spy-retirement.combat-admission.dominates-effects"

$combatActionsText = [string]$sourceTexts["systems/combat/combat_actions.java"]
$handlerMatches = @([regex]::Matches($combatActionsText, '(?m)^\s*public int (steal|sp_[A-Za-z0-9_]+)\('))
Assert-Contract ($handlerMatches.Count -eq [int]$contract.expected.allSpyAndStealHandlers) "p14.spy-retirement.handler-inventory"
$retainedCommands = @($contract.expected.retainedDeviceCommands)
$directGuards = @($contract.expected.directPreEffectHandlersGuarded)
$guardedHandlerCount = 0
foreach ($match in $handlerMatches)
{
    $handlerName = $match.Groups[1].Value
    if ($retainedCommands -contains $handlerName) { continue }
    $next = $combatActionsText.IndexOf("public int ", $match.Index + $match.Length, [System.StringComparison]::Ordinal)
    if ($next -lt 0) { $next = $combatActionsText.Length }
    $body = $combatActionsText.Substring($match.Index, $next - $match.Index)
    if ($directGuards -contains $handlerName)
    {
        if ($body.Contains("isRetiredPostNgeSpyPlayerAction(self, `"$handlerName`")")) { $guardedHandlerCount++ }
    }
    elseif ($body.Contains("combatStandardAction("))
    {
        $guardedHandlerCount++
    }
}
Assert-Contract ($guardedHandlerCount -eq [int]$contract.expected.retiredPlayerHandlers) "p14.spy-retirement.all-player-handlers-gated"

$stealBody = Get-SourceSlice $combatActionsText "public int steal(" "public int sp_buff_invis_1"
$stealthBuffBody = Get-SourceSlice $combatActionsText "public int sp_buff_stealth_1" "public int sp_decoy"
$decoyBody = Get-SourceSlice $combatActionsText "public int sp_decoy" "public int sp_assassins_mark"
Assert-Contract (
    (Is-Before $stealBody "isRetiredPostNgeSpyPlayerAction" "stealth.hasInvisibleBuff") -and
    (Is-Before $stealthBuffBody "isRetiredPostNgeSpyPlayerAction" "stealth.getInvisBuff") -and
    (Is-Before $decoyBody "isRetiredPostNgeSpyPlayerAction" "stealth.canPerformSmokeGrenade")
) "p14.spy-retirement.direct-pre-effect-handlers.dominated"

$neutralizeBody = Get-SourceSlice $combatActionsText "public int sp_neutralize_device_1" "public int sp_hide_device_1"
$hideBody = Get-SourceSlice $combatActionsText "public int sp_hide_device_1" "public int saberBlock"
Assert-Contract (
    $neutralizeBody.Contains("stealth.canDisarmTrap") -and
    $neutralizeBody.Contains("stealth.disarmTrap") -and
    $hideBody.Contains('combatStandardAction("sp_hide_device_1"')
) "p14.spy-retirement.retained-device-commands.preserved"

$handlerText = [string]$sourceTexts["systems/buff/buff_handler.java"]
$invisAddBody = Get-SourceSlice $handlerText "public void invisBuffAddBuffHandler" "public void noBreakInvisRemoveBuffHandler"
Assert-Contract (
    (Is-Before $invisAddBody "isRetiredPostNgeSpyBuffName(effectName)" "stealth.invisBuffAdded") -and
    (Is-Before $invisAddBody "buff.isRetiredPostNgeForceSensitiveStanceBuff(buffName)" "stealth.invisBuffAdded") -and
    $invisAddBody.Contains("isPlayer(self)") -and
    $invisAddBody.Contains("buff.removeBuff(self, buffName)")
) "p14.spy-retirement.direct-buff-application.fail-closed"

$buffLibraryText = Get-Content -LiteralPath (Join-Path $scriptRoot "library/buff.java") -Raw
$shiftyEffectPredicate = Get-SourceSlice $buffLibraryText `
    "private static final String RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_EFFECT" `
    "public static boolean isRetiredPostNgePlayerOnAttackRemoveBuff(obj_id target"
$shiftyBuffPredicate = Get-SourceSlice $buffLibraryText `
    "public static boolean isRetiredPostNgePlayerOnAttackRemoveBuff(obj_id target" `
    "public static void clearPostNgePlayerOnAttackRemoveState"
$shiftyStateCleanup = Get-SourceSlice $buffLibraryText `
    "public static void clearPostNgePlayerOnAttackRemoveState" `
    "private static final String[] RETIRED_POST_NGE_PLAYER_LUCK_HIT_OVERRIDE_EFFECTS"
$shiftyProgressionCleanup = Get-SourceSlice $buffLibraryText `
    "public static void retirePostNgeBuffProgression" `
    "public static void retirePostNgeMeditationBuffs"
$shiftyAdmission = Get-SourceSlice $buffLibraryText `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static float getBuffTimeRemaining"
$shiftyAddHandler = Get-SourceSlice $handlerText `
    "public int onAttackRemoveAddBuffHandler" `
    "public int onAttackRemoveRemoveBuffHandler"
$shiftyRemoveHandler = Get-SourceSlice $handlerText `
    "public int onAttackRemoveRemoveBuffHandler" `
    "public int supression_handlerAddBuffHandler"
$shiftyCombatCleanup = $combatBaseText.IndexOf(
    "buff.clearPostNgePlayerOnAttackRemoveState(attackerData.id);",
    [StringComparison]::Ordinal)
$shiftyCombatConsumer = $combatBaseText.IndexOf(
    "utils.hasScriptVar(attackerData.id, buff.ON_ATTACK_REMOVE)",
    [StringComparison]::Ordinal)

$effectMappingRows = @(Import-Csv -LiteralPath `
    (Join-Path $sharedRoot "datatables/buff/effect_mapping.tab") -Delimiter "`t" |
    Select-Object -Skip 1 | Where-Object {
        [string]$_.NAME -ceq "on_attack_remove"
    })
$buffRows = @(Import-Csv -LiteralPath `
    (Join-Path $sharedRoot "datatables/buff/buff.tab") -Delimiter "`t" |
    Select-Object -Skip 1 | Where-Object {
        [string]$_.NAME -ceq "sp_shifty_setup"
    })
$shiftySkillRows = @(Import-Csv -LiteralPath `
    (Join-Path $sharedRoot "datatables/skill/skills.tab") -Delimiter "`t" |
    Select-Object -Skip 1 | Where-Object {
        [string]$_.NAME -ceq "expertise_sp_shifty_setup_1"
    })
Assert-Contract ($effectMappingRows.Count -eq
        [int]$contract.expected.retainedShiftySetupEffectMappingRows -and
    @($effectMappingRows | Where-Object {
        [string]$_.TYPE -ceq "onAttackRemove" -and
        [string]$_.SUBTYPE -ceq "on_attack_remove"
    }).Count -eq $effectMappingRows.Count -and
    $buffRows.Count -eq [int]$contract.expected.retainedShiftySetupBuffRows -and
    [string]$buffRows[0].EFFECT4_PARAM -ceq "on_attack_remove" -and
    $shiftySkillRows.Count -eq
        [int]$contract.expected.retainedShiftySetupExpertiseSkillRows -and
    [string]$shiftySkillRows[0].COMMANDS -ceq "sp_shifty_setup") `
    "p14.spy-retirement.shifty-setup.data-inventory-authenticated"
$shiftyAdmissionDominatesExisting = Is-Before $shiftyAdmission `
    "isRetiredPostNgePlayerOnAttackRemoveBuff(target, bdata)" `
    "hasBuff(target, nameCrc)"
$shiftyAddGuardDominatesCleanup = Is-Before $shiftyAddHandler `
    "isPlayer(self)" "buff.clearPostNgePlayerOnAttackRemoveState(self)"
$shiftyAddCleanupDominatesWriter = Is-Before $shiftyAddHandler `
    "buff.clearPostNgePlayerOnAttackRemoveState(self)" "Vector removeBuffs"
$shiftyRemoveGuardDominatesCleanup = Is-Before $shiftyRemoveHandler `
    "isPlayer(self)" "buff.clearPostNgePlayerOnAttackRemoveState(self)"
$shiftyRemoveCleanupDominatesWriter = Is-Before $shiftyRemoveHandler `
    "buff.clearPostNgePlayerOnAttackRemoveState(self)" "Vector removeBuffs"
Assert-Contract ($shiftyEffectPredicate.Contains(
        'RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_EFFECT = "on_attack_remove"') -and
    $shiftyEffectPredicate.Contains(
        'RETIRED_POST_NGE_PLAYER_ON_ATTACK_REMOVE_BUFF = "sp_shifty_setup"') -and
    $shiftyBuffPredicate.Contains("!isPlayer(target)") -and
    $shiftyBuffPredicate.Contains("effect <= MAX_EFFECTS") -and
    $shiftyBuffPredicate.Contains(
        "isRetiredPostNgePlayerOnAttackRemoveEffect(getEffectParam(data, effect))") -and
    $shiftyStateCleanup.Contains("utils.removeScriptVarTree(player, ON_ATTACK_REMOVE)") -and
    $shiftyStateCleanup.Contains("removeBuff(player, activeBuff)") -and
    $shiftyStateCleanup.Contains("clearPostNgePlayerOnAttackRemoveState(player)") -and
    $shiftyProgressionCleanup.Contains("retirePostNgePlayerOnAttackRemoveState(player);") -and
    $shiftyAdmissionDominatesExisting -and
    -not [bool]$contract.expected.playerShiftySetupBuffAdmissionReachable -and
    [bool]$contract.expected.persistedPlayerShiftySetupStateRemoved) `
    "p14.spy-retirement.shifty-setup.admission-and-state-fail-closed"
Assert-Contract ($shiftyAddGuardDominatesCleanup -and
    $shiftyAddCleanupDominatesWriter -and
    $shiftyRemoveGuardDominatesCleanup -and
    $shiftyRemoveCleanupDominatesWriter -and
    [int]$contract.expected.productionShiftySetupHandlersGuarded -eq 2 -and
    [bool]$contract.expected.nonPlayerShiftySetupCompatibilityPreserved) `
    "p14.spy-retirement.shifty-setup.handlers-player-fail-closed"
Assert-Contract ($shiftyCombatCleanup -ge 0 -and
    $shiftyCombatConsumer -gt $shiftyCombatCleanup -and
    -not [bool]$contract.expected.playerShiftySetupCombatConsumerReachable -and
    [int]$contract.expected.retiredShiftySetupPlayerScriptVars -eq 1) `
    "p14.spy-retirement.shifty-setup.combat-consumer-fail-closed"

$skillsPath = Join-Path $sharedRoot "datatables/skill/skills.tab"
$skillRows = @(Get-Content -LiteralPath $skillsPath)
$classSpyRows = @($skillRows | Where-Object { $_ -match '^class_spy_' })
$expertiseSpyRows = @($skillRows | Where-Object { $_ -match '^expertise_sp_' })
Assert-Contract (
    $classSpyRows.Count -eq [int]$contract.expected.classSpyCompatibilityRows -and
    $expertiseSpyRows.Count -eq [int]$contract.expected.expertiseSpyCompatibilityRows
) "p14.spy-retirement.compatibility-rows-preserved"
$skillTableText = $skillRows -join $lf
Assert-Contract (
    $skillTableText.Contains("outdoors_scout_movement_02") -and
    $skillTableText.Contains("maskscent") -and
    $skillTableText.Contains("mask_scent=20") -and
    $skillTableText.Contains("outdoors_scout_tools_01") -and
    $skillTableText.Contains("trapping=5") -and
    $skillTableText.Contains("outdoors_ranger_movement_01") -and
    $skillTableText.Contains("conceal") -and
    $skillTableText.Contains("camouflage=40") -and
    $skillTableText.Contains("outdoors_ranger_support_01") -and
    $skillTableText.Contains("trapping=10") -and
    $skillTableText.Contains("combat_rifleman_speed_01") -and
    $skillTableText.Contains("concealShot")
) "p14.spy-retirement.precu-skill-mechanics-preserved"

$stealthLibraryText = Get-Content -LiteralPath (Join-Path $scriptRoot "library/stealth.java") -Raw
$hepText = Get-Content -LiteralPath (Join-Path $scriptRoot "systems/skills/stealth/hep.java") -Raw
Assert-Contract (
    $stealthLibraryText.Contains('PRECU_TRAPPING_SKILL_MOD = "trapping"') -and
    $stealthLibraryText.Contains('PRECU_CAMOUFLAGE_SKILL_MOD = "camouflage"') -and
    [bool]$contract.expected.retainedHepCompatibilityAsset -and
    [bool]$contract.expected.hepPlayerUrbanStealthActivationRetired -and
    $hepText.Contains('stealth.isRetiredPostP14PlayerInvisibilityAction(player, "urbanStealth")') -and
    $hepText.Contains('queueCommand(player, getStringCrc(toLower("urbanStealth"))') -and
    $hepText.IndexOf('stealth.isRetiredPostP14PlayerInvisibilityAction(player, "urbanStealth")') -lt
        $hepText.IndexOf('queueCommand(player, getStringCrc(toLower("urbanStealth"))')
) "p14.spy-retirement.retained-hep-asset-player-activation-retired"

$missionMap = [ordered]@{
    "mission_terminal.java" = Join-Path $scriptRoot "systems/missions/base/mission_terminal.java"
    "mission_base.java" = Join-Path $scriptRoot "systems/missions/base/mission_base.java"
    "missions.java" = Join-Path $scriptRoot "library/missions.java"
}
foreach ($mission in $missionMap.GetEnumerator())
{
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $mission.Value).Hash.ToLowerInvariant()
    Assert-Contract (
        $hash -ceq [string]$contract.continuityEvidence.missionSourceSha256.($mission.Key)
    ) "p14.spy-retirement.mission-source.$($mission.Key).unchanged"
}

Assert-Contract (
    @("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status
) "p14.spy-retirement.contract.status"
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq
        [string]$contract.buildEvidence.directSourceGitlink) `
    "p14.spy-retirement.direct-source-pin"

if ($failures.Count -gt 0)
{
    throw "P14 post-NGE Spy player-runtime retirement contract failed: $($failures -join ', ')"
}

Write-Host "P14 post-NGE Spy player-runtime retirement contract passed."
