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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgePassiveProfessionRuntimeRetirement)) -Raw | ConvertFrom-Json
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
    "library/buff.java" = "library/buff.java"
    "systems/buff/buff_handler.java" = "systems/buff/buff_handler.java"
    "systems/combat/combat_actions.java" = "systems/combat/combat_actions.java"
}
Assert-Contract ($relativeSourceMap.Count -eq
    [int]$contract.expected.authoritativeSourceFiles) `
    "p14.passive-profession.authoritative-source-count"
$sourceTexts = @{}
$contentRecords = ""
foreach ($entry in $relativeSourceMap.GetEnumerator())
{
    $path = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.passive-profession.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) "p14.passive-profession.source.$($entry.Key).authenticated"
        $contentRecords += "sku.0/sys.server/compiled/game/script/$($entry.Value)=$hash`n"
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $path -Raw
    }
}
Assert-Contract ((Get-TextSha256 $contentRecords) -ceq [string]$contract.buildEvidence.sourceContentSha256) "p14.passive-profession.source-content.authenticated"

$skill = [string]$sourceTexts["library/skill.java"]
foreach ($surface in @(
    (Get-SourceSlice $skill "public static boolean grant(obj_id target" "public static boolean grantSkillToPlayer"),
    (Get-SourceSlice $skill "public static boolean grantSkillToPlayer" "public static int getSkillPointsLeft"),
    (Get-SourceSlice $skill "public static boolean purchaseSkill" "public static boolean hasRequiredSkillsForSkillPurchase")
))
{
    Assert-Contract ($surface.Contains("isRetiredNgeProgressionSkillName(skillName)") -and $surface.Contains("return false;")) "p14.passive-profession.skill-admission.generic-retirement"
}

$player = [string]$sourceTexts["player/base/base_player.java"]
$cleanup = Get-SourceSlice $player "private void retirePostNgePassiveProfessionState" "private void retirePostNgeQueuedBattlefieldPlayerState"
$smugglerCleanup = Get-SourceSlice $player "public void removeSmugglingBuffs" "public int removeSmugglingBonuses"
$retiredBuffNames = @(
    "sm_underworld_boss_1", "sm_underworld_boss_2", "sm_underworld_boss_3",
    "sm_underworld_range_1", "sm_underworld_range_2", "sm_underworld_range_3",
    "sm_underworld_damage_1", "sm_underworld_damage_2", "sm_underworld_damage_3"
)
Assert-Contract ($cleanup.Contains("buff.retirePostNgeForceSensitiveStanceState(self)") -and
    $cleanup.Contains("removeSmugglingBuffs(self)")) `
    "p14.passive-profession.central-cleanup"
Assert-Contract (@($retiredBuffNames | Where-Object { -not $smugglerCleanup.Contains('"' + $_ + '"') }).Count -eq 0) "p14.passive-profession.smuggler-buff-inventory"

$buffLibrary = [string]$sourceTexts["library/buff.java"]
$buffHandler = [string]$sourceTexts["systems/buff/buff_handler.java"]
$combatActions = [string]$sourceTexts["systems/combat/combat_actions.java"]
$stanceInventory = Get-SourceSlice $buffLibrary `
    "private static final String[] RETIRED_POST_NGE_FORCE_SENSITIVE_STANCE_BUFFS" `
    "public static boolean isRetiredPostNgeForceSensitiveStanceBuff"
$stancePredicate = Get-SourceSlice $buffLibrary `
    "public static boolean isRetiredPostNgeForceSensitiveStanceBuff" `
    "public static void retirePostNgeForceSensitiveStanceState"
$stanceCleanup = Get-SourceSlice $buffLibrary `
    "public static void retirePostNgeForceSensitiveStanceState" `
    "public static boolean isRetiredPostNgeBountyHunterShieldBuff"
$retiredStanceNames = @([regex]::Matches($stanceInventory,
        '"([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
$modifierInventory = Get-SourceSlice $stanceCleanup `
    "String[] retiredModifiers" "for (String retiredModifier"
$retiredStanceModifiers = @([regex]::Matches($modifierInventory,
        '"([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
Assert-Contract ($retiredStanceNames.Count -eq
        [int]$contract.expected.retiredForceSensitiveStanceStateBuffs -and
    @($retiredStanceNames | Select-Object -Unique).Count -eq
        $retiredStanceNames.Count -and
    $stancePredicate.Contains(
        "for (String retiredBuff : RETIRED_POST_NGE_FORCE_SENSITIVE_STANCE_BUFFS)") -and
    $stanceCleanup.Contains("!isPlayer(player)") -and
    $stanceCleanup.Contains("removeBuff(player, retiredBuff);") -and
    $retiredStanceModifiers.Count -eq
        [int]$contract.expected.retiredForceSensitiveStanceModifiers -and
    $stanceCleanup.Contains('utils.removeScriptVarTree(player, "expertise_stance_critical")') -and
    $stanceCleanup.Contains('utils.removeScriptVarTree(player, "stance.expertise_stance")') -and
    $stanceCleanup.Contains('utils.removeScriptVarTree(player, "stance.expertise_focus")')) `
    "p14.passive-profession.force-sensitive.persisted-state-inventory"

$canApply = Get-SourceSlice $buffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static boolean applyBuff(obj_id target, String name)"
$genericGate = $canApply.IndexOf(
    "isRetiredPostNgeForceSensitiveStanceBuff(bdata.buffName)",
    [StringComparison]::Ordinal)
$existingBuffReturn = $canApply.IndexOf("hasBuff(target, nameCrc)",
    [StringComparison]::Ordinal)
$stanceAdd = Get-SourceSlice $buffHandler `
    "public int stanceAddBuffHandler" "public int stanceRemoveBuffHandler"
$stanceHandlerGate = $stanceAdd.IndexOf(
    "buff.isRetiredPostNgeForceSensitiveStanceBuff(buffName)",
    [StringComparison]::Ordinal)
$stanceHandlerCleanup = $stanceAdd.IndexOf(
    "buff.retirePostNgeForceSensitiveStanceState(self);",
    [StringComparison]::Ordinal)
$stanceVisual = $stanceAdd.IndexOf("buff.playStanceVisual(self, effectName);",
    [StringComparison]::Ordinal)
$isInStance = Get-SourceSlice $buffLibrary `
    "public static boolean isInStance" "public static boolean isInFocus"
$isInFocus = Get-SourceSlice $buffLibrary `
    "public static boolean isInFocus" "public static boolean playStanceVisual"
Assert-Contract ([bool]$contract.expected.genericRetiredBuffAdmissionFailsClosed -and
    $genericGate -ge 0 -and $existingBuffReturn -gt $genericGate -and
    [bool]$contract.expected.stanceHandlerFailsClosedBeforeVisualAndExpertiseReads -and
    $stanceHandlerGate -ge 0 -and $stanceHandlerCleanup -gt $stanceHandlerGate -and
    $stanceVisual -gt $stanceHandlerCleanup -and
    $stanceAdd.Contains('subtype.equals("expertise_stance")') -and
    $stanceAdd.Contains('subtype.equals("expertise_focus")') -and
    [bool]$contract.expected.stanceAndFocusQueriesFailClosedForPlayers -and
    $isInStance.Contains("if (isPlayer(player))") -and
    $isInStance.Contains("retirePostNgeForceSensitiveStanceState(player);") -and
    $isInStance.Contains("return false;") -and
    $isInFocus.Contains("if (isPlayer(player))") -and
    $isInFocus.Contains("retirePostNgeForceSensitiveStanceState(player);") -and
    $isInFocus.Contains("return false;") -and
    [bool]$contract.expected.nonPlayerStanceCompatibilityPreserved -and
    $isInStance.TrimEnd().EndsWith("}") -and $isInStance.Contains("return true;") -and
    $isInFocus.Contains("return true;")) `
    "p14.passive-profession.force-sensitive.all-player-writers-and-queries-fail-closed"

$buffTablePath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
$buffRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter "`t")
$retiredStanceRows = @($buffRows | Where-Object {
    $retiredStanceNames -ccontains [string]$_.NAME
})
$centerRows = @($buffRows | Where-Object { [string]$_.NAME -ceq "centerofbeing" })
$centerOfBeing = Get-SourceSlice $combatActions `
    "public int centerOfBeing" "public int forceFocus"
Assert-Contract ($retiredStanceRows.Count -eq
        [int]$contract.expected.retainedForceSensitiveStanceCompatibilityRows -and
    @($retiredStanceRows | Select-Object -ExpandProperty NAME -Unique).Count -eq
        [int]$contract.expected.retainedForceSensitiveStanceCompatibilityRows -and
    @($retiredStanceNames | Where-Object {
        $_ -cnotin @($retiredStanceRows | Select-Object -ExpandProperty NAME)
    }).Count -eq [int]$contract.expected.historicalForceSensitiveStanceCleanupOnlyNames -and
    $retiredStanceNames -ccontains "fs_imp_force_drain_4" -and
    -not ($retiredStanceNames -ccontains "centerofbeing") -and
    $centerRows.Count -eq 1 -and
    [bool]$contract.expected.precuCenterOfBeingPreserved -and
    $centerOfBeing.Contains('hasSkill(self, "combat_brawler_novice")') -and
    $centerOfBeing.Contains('"centerofbeing"') -and
    $centerOfBeing.Contains('"center_of_being_duration_') -and
    $centerOfBeing.Contains("_center_of_being_efficacy") -and
    $centerOfBeing.Contains("combat.drainCombatActionAttributes") -and
    -not $centerOfBeing.Contains("fs_buff_def_1_1") -and
    -not $centerOfBeing.Contains("fs_buff_ca_1")) `
    "p14.passive-profession.force-sensitive.compatibility-and-precu-center-boundary"

$initialize = Get-SourceSlice $player "public int OnInitialize(obj_id self)" "public int OnLogin(obj_id self)"
$login = Get-SourceSlice $player "public int OnLogin(obj_id self)" "public int handleDelayedLogin"
$recap = Get-SourceSlice $player "public int OnRecapacitated" "public int handleInstanceTimeRemainingMessage"
Assert-Contract ($initialize.Contains("skill.validateExpertise(self)") -and $initialize.Contains("retirePostNgePassiveProfessionState(self)")) "p14.passive-profession.initialize-cleanup"
Assert-Contract ($login.Contains("retirePostNgePassiveProfessionState(self)") -and -not $login.Contains('messageTo(self, "applyJediStance"') -and -not $login.Contains('messageTo(self, "applySmugglingBonuses"')) "p14.passive-profession.login-cleanup"
Assert-Contract ($recap.Contains("retirePostNgePassiveProfessionState(self)") -and -not $recap.Contains("getLevel(self)")) "p14.passive-profession.recap-cleanup"

$applyJedi = Get-SourceSlice $player "public int applyJediStance" "public int applySmugglingBonuses"
$applySmuggling = Get-SourceSlice $player "public int applySmugglingBonuses" "public int addSmugglingBuffs"
$addSmuggling = Get-SourceSlice $player "public int addSmugglingBuffs" "public int recalcWeaponRange"
foreach ($handler in @($applyJedi, $applySmuggling, $addSmuggling))
{
    Assert-Contract ($handler.Contains("retirePostNgePassiveProfessionState(self)") -and -not $handler.Contains("buff.applyBuff") -and -not $handler.Contains("getSkillStatisticModifier")) "p14.passive-profession.queued-handler-fails-closed"
}

$grant = Get-SourceSlice $player "public int OnSkillGranted" "public int handleStartJediKnightTrials"
$retirementIndex = $grant.IndexOf("skill.isRetiredNgeProgressionSkillName(skillName)", [System.StringComparison]::Ordinal)
$badgeIndex = $grant.IndexOf("badge.grantMasterSkillBadge", [System.StringComparison]::Ordinal)
Assert-Contract ($retirementIndex -ge 0 -and $badgeIndex -gt $retirementIndex -and $grant.Contains("revokeSkillSilent(self, skillName)") -and -not $grant.Contains('skillName.startsWith("expertise_")')) "p14.passive-profession.skill-grant-dominance"
Assert-Contract ($grant.Contains("playClientEffectObj") -and $grant.Contains("showFlyText") -and -not $grant.Contains("getLevel(self)")) "p14.passive-profession.skill-feedback.precu"

$factions = [string]$sourceTexts["library/factions.java"]
Assert-Contract ($factions.Contains("smuggler.checkSmugglerTitleGrants(target, value)") -and $factions.Contains("smuggler.checkRewardQuestGrants(target, value)") -and -not $factions.Contains('messageTo(target, "applySmugglingBonuses"')) "p14.passive-profession.underworld-content-preserved"

$buffTable = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
$effectMapping = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/effect_mapping.tab"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $buffTable).Hash.ToLowerInvariant() -ceq [string]$contract.continuityEvidence.buffDataSha256) "p14.passive-profession.buff-data.preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $effectMapping).Hash.ToLowerInvariant() -ceq [string]$contract.continuityEvidence.effectMappingSha256) "p14.passive-profession.effect-mapping.preserved"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.passive-profession.mission.$($property.Name).unchanged"
}
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ([string]$manifest.sourceMode -ceq "direct-branch" -and $dsrcPin.Count -eq 1 -and [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) "p14.passive-profession.direct-source-pin"
if ($Expectation -eq "Ready")
{
    $compiledHashes = @($contract.buildEvidence.compiledClassSha256.PSObject.Properties)
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        $compiledHashes.Count -eq [int]$contract.expected.authoritativeSourceFiles -and
        @($compiledHashes | Where-Object {
            [string]$_.Value -notmatch '^[a-f0-9]{64}$'
        }).Count -eq 0 -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.passive-profession.ready-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending",
            "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.passive-profession.source-status"
}
$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgePassiveProfessionRuntimeRetirement)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) "p14.passive-profession.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Post-NGE passive profession runtime retirement failed: $($failures -join ', ')"
}
Write-Host "Post-NGE passive profession runtime retirement contract passed."
