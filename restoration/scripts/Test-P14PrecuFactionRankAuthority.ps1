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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuFactionRankAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

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

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

foreach ($component in @("dsrc", "src"))
{
    $evidence = $contract.buildEvidence.overlayPatches.$component
    $patchPath = Join-Path $repositoryRoot ([string]$evidence.path)
    Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.faction-rank.overlay.$component.exists"
    if (Test-Path -LiteralPath $patchPath -PathType Leaf)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and $sha -ceq [string]$evidence.sha256) `
            "p14.faction-rank.overlay.$component.authenticated"
    }
}

$paths = [ordered]@{
    "script.base_class" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/base_class.java"
    "script.library.factions" = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/factions.java"
    "CreatureObject.h" = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/CreatureObject.h"
    "ScriptMethodsPvp.cpp" = Join-Path $source "src/engine/server/library/serverScript/src/shared/ScriptMethodsPvp.cpp"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.faction-rank.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($actualHash -ceq [string]$contract.buildEvidence.sourceSha256.$name) `
            "p14.faction-rank.source.$name.authenticated"
    }
}

$baseClass = [string]$texts["script.base_class"]
$factions = [string]$texts["script.library.factions"]
$creatureHeader = [string]$texts["CreatureObject.h"]
$scriptPvp = [string]$texts["ScriptMethodsPvp.cpp"]

$supportingRelativeSourceMap = [ordered]@{
    "player/base/base_player.java" = "player/base/base_player.java"
    "player/player_faction.java" = "player/player_faction.java"
    "systems/turret/turret_ai.java" = "systems/turret/turret_ai.java"
}
$supportingTexts = @{}
foreach ($entry in $supportingRelativeSourceMap.GetEnumerator())
{
    $path = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.faction-rank.pvp-state.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($actualHash -ceq [string]$contract.buildEvidence.supportingSourceSha256.($entry.Key)) `
            "p14.faction-rank.pvp-state.source.$($entry.Key).authenticated"
        $supportingTexts[$entry.Key] = Get-Content -LiteralPath $path -Raw
    }
}

$callbackRecords = [System.Collections.Generic.List[string]]::new()
$callbackRecordsByKind = @{}
foreach ($property in $contract.callbackInventory.patterns.PSObject.Properties)
{
    $kind = [string]$property.Name
    $kindRecords = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(& rg -n --no-heading ([string]$property.Value) $scriptRoot --glob "*.java"))
    {
        Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
            "p14.faction-rank.pvp-state.$kind.inventory-line-parsed"
        $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
        Assert-Contract ($absolutePath.StartsWith(
            $scriptRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) `
            "p14.faction-rank.pvp-state.$kind.inventory-contained"
        $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
        $record = "${relativePath}:$($Matches[2])|$($Matches[3].Trim())"
        $kindRecords.Add($record)
        $callbackRecords.Add("$kind|$record")
    }
    if ($LASTEXITCODE -gt 1) { throw "rg failed while inventorying $kind PvP state callbacks." }
    $callbackRecordsByKind[$kind] = @($kindRecords | Sort-Object)
}
$callbackRecords = @($callbackRecords | Sort-Object)
$callbackPaths = @($callbackRecords | ForEach-Object {
    Assert-Contract ($_ -match '^[^|]+\|(.*?):\d+\|') `
        "p14.faction-rank.pvp-state.path-isolated"
    $Matches[1]
} | Sort-Object -Unique)
$expectedCallbackPaths = @($contract.callbackInventory.sourcePaths | ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract ($callbackRecords.Count -eq [int]$contract.callbackInventory.handlers -and
    $callbackRecords.Count -eq [int]$contract.expected.pvpStateCallbacks -and
    $callbackPaths.Count -eq [int]$contract.callbackInventory.sourceFiles -and
    ($callbackPaths -join "`n") -ceq ($expectedCallbackPaths -join "`n") -and
    (Get-TextSha256 ($callbackRecords -join "`n")) -ceq [string]$contract.callbackInventory.inventorySha256 -and
    (Get-TextSha256 ($callbackPaths -join "`n")) -ceq [string]$contract.callbackInventory.sourceSetSha256 -and
    $callbackRecordsByKind.faction.Count -eq [int]$contract.callbackInventory.factionHandlers -and
    $callbackRecordsByKind.type.Count -eq [int]$contract.callbackInventory.typeHandlers -and
    (Get-TextSha256 ($callbackRecordsByKind.faction -join "`n")) -ceq [string]$contract.callbackInventory.factionInventorySha256 -and
    (Get-TextSha256 ($callbackRecordsByKind.type -join "`n")) -ceq [string]$contract.callbackInventory.typeInventorySha256) `
    "p14.faction-rank.pvp-state.complete-inventory"

$basePlayerTypeChange = Get-FunctionSlice ([string]$supportingTexts["player/base/base_player.java"]) `
    "public int OnPvpTypeChanged" `
    "public int OnQuestActivated"
$playerFactionTypeChange = Get-FunctionSlice ([string]$supportingTexts["player/player_faction.java"]) `
    "public int OnPvpTypeChanged" `
    "public int OnPvpFactionChanged"
$playerFactionChange = Get-FunctionSlice ([string]$supportingTexts["player/player_faction.java"]) `
    "public int OnPvpFactionChanged" `
    "public int OnEnterRegion"
$turretFactionChange = Get-FunctionSlice ([string]$supportingTexts["systems/turret/turret_ai.java"]) `
    "public int OnPvpFactionChanged" `
    "public void setTurretAttributes"
$playerStateCallbacks = $basePlayerTypeChange + "`n" + $playerFactionTypeChange + "`n" + $playerFactionChange
$rewardOrProgressionPatterns = @(
    '\bgrantSkill\b', '\brevokeSkill\b', '\bskill\.', '\bbuff\.apply',
    '\baddGcw', '\bmodifyGcw', '\bsetGcw', '\bsetLevel\b', '\bgetLevel\b',
    '\bexpertise\b', '\bprofession\b', '\bsetSkillTemplate\b', '\bgrantExperiencePoints\b'
)
$rewardOrProgressionMatches = @($rewardOrProgressionPatterns | Where-Object {
    [regex]::IsMatch($playerStateCallbacks, $_, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
})
Assert-Contract ([int]$contract.callbackInventory.playerHandlers -eq [int]$contract.expected.pvpStatePlayerCallbacks -and
    $rewardOrProgressionMatches.Count -eq [int]$contract.expected.pvpStateRewardOrProgressionMutations -and
    $basePlayerTypeChange.Contains("oldType == PVPTYPE_DECLARED") -and
    $basePlayerTypeChange.Contains("newType == PVPTYPE_COVERT") -and
    $basePlayerTypeChange.Contains("newType == PVPTYPE_NEUTRAL") -and
    $basePlayerTypeChange.Contains("getMountId(self)") -and
    $basePlayerTypeChange.Contains("group.isGrouped(self)")) `
    "p14.faction-rank.pvp-state.player-callbacks-precu-only"
Assert-Contract ([int]$contract.expected.newlyDeclaredTimestampWriters -eq 1 -and
    $playerFactionTypeChange.Contains("utils.setScriptVar(self, factions.VAR_NEWLY_DECLARED, getGameTime())") -and
    $playerFactionTypeChange.Contains('messageTo(self, "msgNewlyDeclared", null, factions.NEWLY_DECLARED_INTERVAL, false)') -and
    [regex]::IsMatch($playerFactionChange,
        '(?s)^public int OnPvpFactionChanged.*?\{\s*return SCRIPT_CONTINUE;\s*\}\s*$')) `
    "p14.faction-rank.pvp-state.declaration-and-inert-faction-change"
Assert-Contract ([int]$contract.callbackInventory.nonPlayerTurretHandlers -eq [int]$contract.expected.pvpStateTurretCallbacks -and
    [int]$contract.expected.turretFactionReconfigurationCallbacks -eq 1 -and
    $turretFactionChange.Contains("setTurretAttributes(self, newFaction);") -and
    $turretFactionChange.Contains("return SCRIPT_CONTINUE;")) `
    "p14.faction-rank.pvp-state.turret-compatibility-preserved"

Assert-Contract ($creatureHeader.Contains("getPrecuFactionRank() const") -and
    $creatureHeader.Contains("setPrecuFactionRank(int rank)") -and
    $creatureHeader.Contains("m_rank.get()") -and
    $creatureHeader.Contains("rank < 0 || rank > 15") -and
    $creatureHeader.Contains("m_rank = static_cast<uint8>(rank)")) `
    "p14.faction-rank.persisted-shared-creature-authority"

$rankRead = Get-FunctionSlice $scriptPvp `
    "jint JNICALL ScriptMethodsPvpNamespace::pvpGetCurrentGcwRank" `
    "jboolean JNICALL ScriptMethodsPvpNamespace::pvpSetPrecuFactionRank"
$rankWrite = Get-FunctionSlice $scriptPvp `
    "jboolean JNICALL ScriptMethodsPvpNamespace::pvpSetPrecuFactionRank" `
    "jint JNICALL ScriptMethodsPvpNamespace::pvpGetMaxGcwImperialRank"
Assert-Contract ($scriptPvp.Contains('JF("_pvpSetPrecuFactionRank", "(JI)Z", pvpSetPrecuFactionRank)') -and
    $rankRead.Contains("creature->getPrecuFactionRank()") -and
    -not $rankRead.Contains("getCurrentGcwRank()") -and
    -not $rankRead.Contains("PlayerCreatureController::getPlayerObject") -and
    $rankWrite.Contains("creature->setPrecuFactionRank")) `
    "p14.faction-rank.native-jni-read-write"

Assert-Contract ($baseClass.Contains("private static native boolean _pvpSetPrecuFactionRank(long target, int rank)") -and
    $baseClass.Contains("public static boolean pvpSetPrecuFactionRank(obj_id target, int rank)")) `
    "p14.faction-rank.java-native-bridge"

$setRank = Get-FunctionSlice $factions `
    "public static boolean setRank(obj_id player, int rank)" `
    "public static boolean releaseFactionHirelings"
$qualifies = Get-FunctionSlice $factions `
    "public static boolean qualifiesForPromotion" `
    "public static void applyPromotion"
$promotion = Get-FunctionSlice $factions `
    "public static void applyPromotion" `
    "public static boolean isSmuggler"
$resign = Get-FunctionSlice $factions `
    "public static void resignFromFaction(obj_id player, String resign_faction)" `
    "public static void resignFromFaction(obj_id player)"
$join = Get-FunctionSlice $factions `
    "public static boolean joinFaction(obj_id player, int faction_id, boolean returnFromReserves)" `
    "public static boolean joinFaction(obj_id player, int faction_id)"

Assert-Contract ($setRank.Contains("rank < 0 || rank > MAXIMUM_RANK") -and
    $setRank.Contains("pvpSetPrecuFactionRank(player, rank)")) `
    "p14.faction-rank.validated-script-setter"
Assert-Contract ($qualifies.Contains("getRankCost(current_rank + 1)") -and
    $qualifies.Contains("cost + (int)FACTION_RATING_DECLARABLE_MIN") -and
    -not $qualifies.Contains("getLevel(")) `
    "p14.faction-rank.authored-cost-and-membership-reserve"
Assert-Contract ($promotion.Contains("addUnmodifiedFactionStanding") -and
    $promotion.Contains("factions.setRank(objPlayer, current_rank + 1)") -and
    $promotion.Contains("cost, false") -and
    -not $promotion.Contains("addFactionStanding(objPlayer")) `
    "p14.faction-rank.transaction-and-failed-write-refund"
Assert-Contract ($resign.Contains("setRank(player, 0)") -and
    $resign.IndexOf("setRank(player, 0)", [System.StringComparison]::Ordinal) -lt
        $resign.IndexOf("pvpMakeNeutral(player)", [System.StringComparison]::Ordinal) -and
    $join.Contains("setRank(player, 0)")) `
    "p14.faction-rank.join-resign-reset"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.faction-rank.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU faction rank authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU faction rank authority passed."
