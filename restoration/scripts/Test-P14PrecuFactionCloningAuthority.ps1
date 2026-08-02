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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuFactionCloningAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.faction-cloning.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $sha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.faction-cloning.overlay.authenticated"
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$paths = [ordered]@{
    "script.library.factions" = Join-Path $scriptRoot "library/factions.java"
    "script.library.xp" = Join-Path $scriptRoot "library/xp.java"
    "script.library.pclib" = Join-Path $scriptRoot "library/pclib.java"
    "script.player.base.base_player" = Join-Path $scriptRoot "player/base/base_player.java"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.faction-cloning.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($actualHash -ceq [string]$contract.buildEvidence.sourceSha256.$name) `
            "p14.faction-cloning.source.$name.authenticated"
    }
}

$factions = [string]$texts["script.library.factions"]
$xp = [string]$texts["script.library.xp"]
$pclib = [string]$texts["script.library.pclib"]
$basePlayer = [string]$texts["script.player.base.base_player"]

$standing = Get-FunctionSlice $factions `
    "public static boolean addUnmodifiedFactionStanding(obj_id target, String factionName, float value, boolean verbose)" `
    "public static boolean addUnmodifiedFactionStanding(obj_id target, String factionName, float value)"
$award = Get-FunctionSlice $factions `
    "public static boolean awardFactionStanding(" `
    "public static void grantCombatFaction("
$combatFaction = Get-FunctionSlice $factions `
    "public static void grantCombatFaction(" `
    "private static void awardPrecuNpcCombatFaction("
$npcFaction = Get-FunctionSlice $factions `
    "private static void awardPrecuNpcCombatFaction(" `
    "private static boolean isPrecuGcwFaction("
Assert-Contract (-not $standing.Contains("buff.general_inspiration.value") -and
    -not $award.Contains("luck.isLucky") -and
    $combatFaction.Contains("awardFactionStanding(killer, killerFaction, 30)") -and
    $combatFaction.Contains("addFactionStanding(killer, targetFaction, -45)") -and
    $combatFaction.Contains("addFactionStanding(target, targetFaction, -45)") -and
    -not $combatFaction.Contains("getLevel(killer)") -and
    -not $combatFaction.Contains("pvpGetCurrentGcwRank") -and
    -not $combatFaction.Contains("class_smuggler") -and
    -not $combatFaction.Contains("incrementGCWStanding")) `
    "p14.faction-cloning.fixed-pvp-standing-no-nge-multipliers"

Assert-Contract ($combatFaction.Contains("!isPlayer(target)") -and
    $combatFaction.Contains("awardPrecuNpcCombatFaction(killer, targetFaction, getLevel(target))") -and
    -not $combatFaction.Contains("Math.max(1, getLevel(target))") -and
    $npcFaction.Contains('dataTableGetFloat(FACTION_TABLE, defeatedRow, "combatFactor")') -and
    $npcFaction.Contains("float loss = gain * 2.0f") -and
    $npcFaction.Contains('dataTableGetString(FACTION_TABLE, defeatedRow, "enemies")') -and
    $npcFaction.Contains('dataTableGetString(FACTION_TABLE, defeatedRow, "allies")')) `
    "p14.faction-cloning.authored-npc-standing-ratios"

$grantXp = Get-FunctionSlice $xp `
    "public static obj_var[] grantCombatXp(" `
    "private static obj_id getPrecuFactionKillRecipient("
$recipient = Get-FunctionSlice $xp `
    "private static obj_id getPrecuFactionKillRecipient(" `
    "public static void grantCombatXpPerAttackType("
Assert-Contract (([regex]::Matches($grantXp, "factions\.grantCombatFaction\(")).Count -eq 1 -and
    $grantXp.Contains("getPrecuFactionKillRecipient(target, killers, killList)") -and
    -not $grantXp.Contains("grantModifiedGcwPoints") -and
    -not $grantXp.Contains("GCW_POINT_TYPE_GROUND_PVE") -and
    -not $grantXp.Contains("adjustSocialStanding") -and
    $recipient.Contains("dictionary playerDamage") -and
    $recipient.Contains("getMaster(player)") -and
    $recipient.Contains("attackerDamage.getIntData()") -and
    $recipient.Contains("getDistance(player, target)")) `
    "p14.faction-cloning.single-highest-damage-recipient-no-gcw-score"

$cloneCure = Get-FunctionSlice $pclib `
    "public static int getCloningSicknessCureCost(" `
    "public static obj_id grantWayPoint("
$deathblow = Get-FunctionSlice $pclib `
    "public static void coupDeGrace(obj_id victim, obj_id killer, boolean playAnim, boolean usePVPRules)" `
    "public static void coupDeGrace(obj_id victim, obj_id killer)"
$playerDeath = Get-FunctionSlice $pclib `
    "public static boolean playerDeath(" `
    "public static void clearAllHate("
Assert-Contract ($cloneCure.Contains("return 0;") -and
    $cloneCure.Contains("return true;") -and
    $cloneCure.Contains('buff.removeBuff(player, "cloning_sickness")') -and
    -not $cloneCure.Contains("getLevel(") -and
    -not $cloneCure.Contains("cityHasSpec") -and
    -not $cloneCure.Contains("requestPayment") -and
    -not $cloneCure.Contains("ACCT_CLONING") -and
    -not $cloneCure.Contains("pt_cure_cloning_sickness")) `
    "p14.faction-cloning.nge-sickness-cure-price-inert"
Assert-Contract (-not $deathblow.Contains("releaseGcwPointCredit") -and
    $playerDeath.Contains("if (!dueling)") -and
    $playerDeath.Contains("skill.getPrecuEncounterDifficulty(killer) >= 20") -and
    -not $playerDeath.Contains("getLevel(killer)")) `
    "p14.faction-cloning.pvp-death-boundary"

$login = Get-FunctionSlice $basePlayer `
    "public int OnLogin(" `
    "public int handleLoginLocResolved("
$revive = Get-FunctionSlice $basePlayer `
    "public int handlePlayerRevive(" `
    "public int handlePlayerResuscitated("
$unmodifiedXp = Get-FunctionSlice $basePlayer `
    "public int grantUnmodifiedExperienceOnSelf(" `
    "public int grantSquadLeaderXpResult("
Assert-Contract ($login.Contains('buff.removeBuff(self, "cloning_sickness")') -and
    $revive.Contains("cloninglib.applyPrecuClonePenalties") -and
    $revive.Contains('buff.removeBuff(self, "cloning_sickness")')) `
    "p14.faction-cloning.precu-clone-penalties-and-legacy-cleanup"
Assert-Contract ($unmodifiedXp.Contains("xp._grantUnmodifiedExperience") -and
    -not $unmodifiedXp.Contains("TRIAL_LEVEL_CAP") -and
    -not $unmodifiedXp.Contains("hasReachedMaxTutorialLevel") -and
    -not $unmodifiedXp.Contains("isFreeTrialAccount") -and
    -not $unmodifiedXp.Contains("getLevel(") -and
    -not $unmodifiedXp.Contains("luck.isLucky")) `
    "p14.faction-cloning.clean-build-xp-callback-closure"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.faction-cloning.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU faction and cloning authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU faction and cloning authority passed."
