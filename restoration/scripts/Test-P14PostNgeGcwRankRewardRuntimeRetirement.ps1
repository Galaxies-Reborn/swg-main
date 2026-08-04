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

$relativeSourceMap = [ordered]@{
    "library/factions.java" = "library/factions.java"
    "library/skill.java" = "library/skill.java"
    "player/base/base_player.java" = "player/base/base_player.java"
}
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
$skillCleanup = Get-SourceSlice $factions "public static void removeAllPvpSkills" "public static void retirePostNgePvpRewardState"
$runtimeCleanup = Get-SourceSlice $factions "public static void retirePostNgePvpRewardState" "public static boolean shareSocialGroup"
Assert-Contract (@($expectedSkills | Where-Object { -not $skillCleanup.Contains('"' + $_ + '"') }).Count -eq 0) "p14.gcw-reward.persisted-skills.cleaned"
Assert-Contract (@($expectedBuffs | Where-Object { -not $runtimeCleanup.Contains('"' + $_ + '"') }).Count -eq 0) "p14.gcw-reward.active-buffs.cleaned"
Assert-Contract ($runtimeCleanup.Contains('detachScript(player, "player.gcw.pvp_aura_buff_controller")') -and
    $runtimeCleanup.Contains('removeObjVar(player, "pvp_aura_buff.faction")')) "p14.gcw-reward.aura-runtime.cleaned"

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
