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
