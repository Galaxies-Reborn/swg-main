[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgeGcwRankRewardRuntimeRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
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
    "library/factions.java" = "library/factions.java"
    "library/skill.java" = "library/skill.java"
    "player/base/base_player.java" = "player/base/base_player.java"
    "player/gcw/pvp_aura_buff_controller.java" = "player/gcw/pvp_aura_buff_controller.java"
    "systems/combat/combat_actions.java" = "systems/combat/combat_actions.java"
    "systems/combat/combat_base.java" = "systems/combat/combat_base.java"
}
Assert-Contract ($relativeSourceMap.Count -eq [int]$contract.expected.authoritativeSourceFiles) `
    "p14.gcw-reward.authoritative-source-count"
$sourceTexts = @{}
$contentRecords = ""
foreach ($entry in $relativeSourceMap.GetEnumerator())
{
    $path = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.gcw-reward.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) "p14.gcw-reward.source.$($entry.Key).authenticated"
        $contentRecords += "sku.0/sys.server/compiled/game/script/$($entry.Value)=$hash`n"
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $path -Raw
    }
}
Assert-Contract ((Get-TextSha256 $contentRecords) -ceq [string]$contract.buildEvidence.sourceContentSha256) "p14.gcw-reward.source-content.authenticated"

$expectedSkills = @(
    "pvp_imperial_retaliation_ability", "pvp_imperial_adrenaline_ability",
    "pvp_imperial_unstoppable_ability", "pvp_imperial_last_man_ability",
    "pvp_imperial_aura_buff_self", "pvp_imperial_airstrike_ability",
    "pvp_rebel_retaliation_ability", "pvp_rebel_adrenaline_ability",
    "pvp_rebel_unstoppable_ability", "pvp_rebel_last_man_ability",
    "pvp_rebel_aura_buff_self", "pvp_rebel_airstrike_ability"
)
$expectedBuffs = @(
    "pvp_aura_buff_self", "pvp_aura_buff_target",
    "pvp_aura_buff_rebel_self", "pvp_aura_buff_rebel_target",
    "pvp_retaliation_ability", "pvp_retaliation_rebel_ability",
    "pvp_adrenaline_ability", "pvp_adrenaline_rebel_ability",
    "pvp_unstoppable_ability", "pvp_unstoppable_rebel_ability",
    "pvp_last_man_ability", "pvp_last_man_rebel_ability"
)
$expectedPlayerActions = @(
    "command_pvp_adrenaline_ability", "command_pvp_adrenaline_rebel_ability",
    "command_pvp_last_man_ability", "command_pvp_last_man_rebel_ability",
    "command_pvp_retaliation_ability", "command_pvp_retaliation_rebel_ability",
    "command_pvp_unstoppable_ability", "command_pvp_unstoppable_rebel_ability",
    "pvp_adrenaline_ability", "pvp_adrenaline_rebel_ability",
    "pvp_airstrike_ability", "pvp_airstrike_rebel_ability",
    "pvp_aura_buff_rebel_self", "pvp_aura_buff_self",
    "pvp_last_man_ability", "pvp_last_man_rebel_ability",
    "pvp_retaliation_ability", "pvp_retaliation_rebel_ability",
    "pvp_unstoppable_ability", "pvp_unstoppable_rebel_ability"
)

$skill = [string]$sourceTexts["library/skill.java"]
$retirementPredicate = Get-SourceSlice $skill "public static boolean isRetiredNgeProgressionSkillName" "public static boolean isRetiredPostNgeSpySkill"
Assert-Contract ($retirementPredicate.Contains("isRetiredPostNgePvpRewardSkill(skillName)") -and
    $retirementPredicate.Contains('skillName.startsWith("pvp_imperial_")') -and
    $retirementPredicate.Contains('skillName.startsWith("pvp_rebel_")')) "p14.gcw-reward.skill-family.retired"
foreach ($surface in @(
    (Get-SourceSlice $skill "public static boolean grant(obj_id target" "public static boolean grantSkillToPlayer"),
    (Get-SourceSlice $skill "public static boolean grantSkillToPlayer" "public static int getSkillPointsLeft"),
    (Get-SourceSlice $skill "public static boolean purchaseSkill" "public static boolean hasRequiredSkillsForSkillPurchase")
))
{
    Assert-Contract ($surface.Contains("isRetiredNgeProgressionSkillName(skillName)") -and $surface.Contains("return false;")) "p14.gcw-reward.skill-admission.generic-retirement"
}

$factions = [string]$sourceTexts["library/factions.java"]
$buffInventory = Get-SourceSlice $factions `
    "private static final String[] RETIRED_POST_NGE_PVP_REWARD_BUFFS" `
    "public static boolean isRetiredPostNgePvpRewardBuff"
$skillCleanup = Get-SourceSlice $factions "public static void removeAllPvpSkills" "public static void retirePostNgePvpRewardState"
$runtimeCleanup = Get-SourceSlice $factions "public static void retirePostNgePvpRewardState" "public static boolean shareSocialGroup"
$actualBuffs = @([regex]::Matches($buffInventory, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract (@($expectedSkills | Where-Object { -not $skillCleanup.Contains('"' + $_ + '"') }).Count -eq 0) "p14.gcw-reward.persisted-skills.cleaned"
Assert-Contract ($actualBuffs.Count -eq [int]$contract.expected.retiredActiveBuffs -and
    @($actualBuffs | Select-Object -Unique).Count -eq $actualBuffs.Count -and
    (($actualBuffs -join "`n") -ceq (($expectedBuffs | Sort-Object) -join "`n")) -and
    $runtimeCleanup.Contains("RETIRED_POST_NGE_PVP_REWARD_BUFFS")) `
    "p14.gcw-reward.active-buffs.cleaned"
Assert-Contract ($runtimeCleanup.Contains('detachScript(player, "player.gcw.pvp_aura_buff_controller")') -and
    $runtimeCleanup.Contains('removeObjVar(player, "pvp_aura_buff.faction")')) "p14.gcw-reward.aura-runtime.cleaned"

$buffLibrary = [string]$sourceTexts["library/buff.java"]
$buffAdmission = Get-SourceSlice $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static boolean applyBuff(obj_id target, String name)"
Assert-Contract ([bool]$contract.expected.genericRetiredBuffAdmissionDominates -and
    (Is-Before $buffAdmission "factions.isRetiredPostNgePvpRewardBuff(bdata.buffName)" "hasBuff(target, nameCrc)")) `
    "p14.gcw-reward.buff-admission.generic-retirement"

$combatBase = [string]$sourceTexts["systems/combat/combat_base.java"]
$combatInventory = Get-SourceSlice $combatBase `
    "private static final String[] RETIRED_POST_NGE_PVP_REWARD_PLAYER_ACTIONS" `
    "public static boolean isRetiredPostNgePvpRewardPlayerAction"
$actualPlayerActions = @([regex]::Matches($combatInventory, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$standardAction = Get-SourceSlice $combatBase `
    "public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)" `
    "combat.revealPrecuFeignDeath(self, `"combatCommand`")"
Assert-Contract ($actualPlayerActions.Count -eq [int]$contract.expected.retiredPlayerCombatActions -and
    @($actualPlayerActions | Select-Object -Unique).Count -eq $actualPlayerActions.Count -and
    (($actualPlayerActions -join "`n") -ceq (($expectedPlayerActions | Sort-Object) -join "`n")) -and
    $standardAction.Contains("isRetiredPostNgePvpRewardPlayerAction(self, actionName)") -and
    $standardAction.Contains("factions.retirePostNgePvpRewardState(self)") -and
    [bool]$contract.expected.genericRetiredCombatActionAdmissionDominates) `
    "p14.gcw-reward.combat-action.generic-retirement"

$combatActions = [string]$sourceTexts["systems/combat/combat_actions.java"]
$pvpHandlers = @([regex]::Matches($combatActions,
    '(?ms)^\s*public int ((?:command_)?pvp_(?:aura_buff_(?:rebel_)?self|retaliation(?:_rebel)?_ability|adrenaline(?:_rebel)?_ability|unstoppable(?:_rebel)?_ability|last_man(?:_rebel)?_ability|airstrike(?:_rebel)?_ability))\(.*?(?=^\s*public int |\z)'))
Assert-Contract ($pvpHandlers.Count -eq [int]$contract.expected.retiredPlayerCombatActions -and
    @($pvpHandlers | Where-Object { -not $_.Value.Contains("combatStandardAction(") }).Count -eq 0) `
    "p14.gcw-reward.combat-action.all-handlers-covered"

$auraController = [string]$sourceTexts["player/gcw/pvp_aura_buff_controller.java"]
$auraHandlers = @([regex]::Matches($auraController,
    '(?ms)^\s*public int (OnAttach|buffAlly|removeFactionObjVar)\(.*?(?=^\s*public int |\z)'))
Assert-Contract ($auraHandlers.Count -eq [int]$contract.expected.retainedAuraControllerCallbacks -and
    @($auraHandlers | Where-Object {
        -not $_.Value.Contains("if (isPlayer(self))") -or
        -not $_.Value.Contains("factions.retirePostNgePvpRewardState(self)") -or
        -not (Is-Before $_.Value "factions.retirePostNgePvpRewardState(self)" "return SCRIPT_CONTINUE;")
    }).Count -eq 0 -and [bool]$contract.expected.auraPlayerCallbacksFailClosed) `
    "p14.gcw-reward.aura-player-callbacks.fail-closed"
Assert-Contract ([bool]$contract.expected.nonPlayerCompatibilityPreserved -and
    $combatBase.Contains("if (!isPlayer(self) || actionName == null)") -and
    $auraController.Contains("isMob(self) && !isPlayer(self)") -and
    $auraController.Contains('buff.applyBuff(players, "pvp_aura_buff_rebel_target")') -and
    $auraController.Contains('buff.applyBuff(players, "pvp_aura_buff_target")')) `
    "p14.gcw-reward.non-player-compatibility.preserved"

$player = [string]$sourceTexts["player/base/base_player.java"]
$centralCleanup = Get-SourceSlice $player "private void retirePostNgePassiveProfessionState" "private void retirePostNgeQueuedBattlefieldPlayerState"
$rankChange = Get-SourceSlice $player "public int OnPvpRankingChanged" "public int OnEnvironmentalDeath"
Assert-Contract ($centralCleanup.Contains("factions.retirePostNgePvpRewardState(self)")) "p14.gcw-reward.player-lifecycle.cleanup"
Assert-Contract ($rankChange.Contains("factions.retirePostNgePvpRewardState(self)") -and
    -not $rankChange.Contains("skill.grantSkill(self, faction + PVP_SKILL_")) "p14.gcw-reward.rank-change.no-ability-grants"
$expectedBadges = @(
    "pvp_imperial_lieutenant", "pvp_rebel_lieutenant",
    "pvp_imperial_captain", "pvp_rebel_captain",
    "pvp_imperial_major", "pvp_rebel_major",
    "pvp_imperial_lt_colonel", "pvp_rebel_commander",
    "pvp_imperial_colonel", "pvp_rebel_colonel",
    "pvp_imperial_general", "pvp_rebel_general"
)
Assert-Contract (@($expectedBadges | Where-Object { -not $rankChange.Contains('"' + $_ + '"') }).Count -eq 0) "p14.gcw-reward.rank-badges.preserved"

$skillsPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$combatPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$buffPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $skillsPath).Hash.ToLowerInvariant() -ceq [string]$contract.continuityEvidence.skillDataSha256) "p14.gcw-reward.skill-data.preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $combatPath).Hash.ToLowerInvariant() -ceq [string]$contract.continuityEvidence.combatDataSha256) "p14.gcw-reward.combat-data.preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $buffPath).Hash.ToLowerInvariant() -ceq [string]$contract.continuityEvidence.buffDataSha256) "p14.gcw-reward.buff-data.preserved"
$skillRows = @(Import-SwgTab -Path $skillsPath | Where-Object { ([string]$_.NAME).StartsWith("pvp_imperial_") -or ([string]$_.NAME).StartsWith("pvp_rebel_") })
Assert-Contract ($skillRows.Count -eq 12 -and @($expectedSkills | Where-Object { [string]$name = $_; -not ($skillRows.NAME -ccontains $name) }).Count -eq 0) "p14.gcw-reward.compatibility-skill-rows.retained"
$rewardCommands = @($skillRows.COMMANDS | Sort-Object -Unique)
$combatRows = @(Import-SwgTab -Path $combatPath | Where-Object { $rewardCommands -ccontains [string]$_.actionName })
Assert-Contract ($rewardCommands.Count -eq 12 -and $combatRows.Count -eq 12) "p14.gcw-reward.compatibility-combat-rows.retained"
$buffRows = @(Import-SwgTab -Path $buffPath | Where-Object { $expectedBuffs -ccontains [string]$_.NAME })
Assert-Contract ($buffRows.Count -eq 12) "p14.gcw-reward.compatibility-buff-rows.retained"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.gcw-reward.mission.$($property.Name).unchanged"
}
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ([string]$manifest.sourceMode -ceq "direct-branch" -and $dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) "p14.gcw-reward.direct-source-pin"
Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) "p14.gcw-reward.contract-status"
$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgeGcwRankRewardRuntimeRetirement)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) "p14.gcw-reward.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Post-NGE GCW rank reward runtime retirement failed: $($failures -join ', ')"
}
Write-Host "Post-NGE GCW rank reward runtime retirement contract passed."
