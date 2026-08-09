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
    ([string]$manifest.contracts.p14PostNgeRareLootPlayerRuntimeRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$gameRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game"
$scriptRoot = Join-Path $gameRoot "script"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Marker)
{
    $start = $Text.IndexOf($Marker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf('{', $start)
    if ($open -lt 0) { return "" }
    $depth = 1
    for ($index = $open + 1; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

$sourceMap = [ordered]@{
    "library/loot.java" = Join-Path $scriptRoot "library/loot.java"
    "player/base/base_player.java" = Join-Path $scriptRoot "player/base/base_player.java"
    "systems/loot/rare_loot_chest.java" = Join-Path $scriptRoot "systems/loot/rare_loot_chest.java"
}
$texts = @{}
foreach ($entry in $sourceMap.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) "p14.rls.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $entry.Value -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
            "p14.rls.source.$($entry.Key).authenticated"
        $texts[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
    }
}

$directCommit = (& git -C $dsrc rev-parse HEAD).Trim()
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($LASTEXITCODE -eq 0 -and $dsrcPin.Count -eq 1 -and
    $directCommit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
    [string]$dsrcPin[0].commit -ceq $directCommit) "p14.rls.direct-source-pin"

$loot = [string]$texts["library/loot.java"]
$basePlayer = [string]$texts["player/base/base_player.java"]
$chest = [string]$texts["systems/loot/rare_loot_chest.java"]
$addRareLoot = Get-BracedSurface $loot "public static boolean addRareLoot"
$cleanup = Get-BracedSurface $loot "public static void retirePostNgeRareLootPlayerState"
$createChest = Get-BracedSurface $loot "public static obj_id createRareLootChest"
Assert-Contract ($loot.Contains("POST_NGE_RARE_LOOT_SYSTEM_RETIRED = true") -and
    $loot.Contains("public static boolean isPostNgeRareLootSystemRetired")) "p14.rls.retirement-predicate"
Assert-Contract ($addRareLoot.Contains("retirePostNgeRareLootPlayerState") -and
    $addRareLoot.Contains("return false;") -and
    -not $addRareLoot.Contains("rlsEnabled") -and
    -not $addRareLoot.Contains("createRareLootChest")) "p14.rls.producer-fails-closed"
Assert-Contract ($cleanup.Contains('hasObjVar(player, "loot.rls")') -and
    $cleanup.Contains('removeObjVar(player, "loot.rls")') -and
    $cleanup.Contains("isPlayer(player)")) "p14.rls.persisted-player-state-cleanup"
Assert-Contract ($createChest.Contains("return null;") -and
    -not $createChest.Contains("static_item") -and
    -not $loot.Contains("rlsDropChance") -and
    -not $loot.Contains("rlsRareDropChance") -and
    -not $loot.Contains("rlsExceptionalDropChance") -and
    -not $loot.Contains("rlsLegendaryDropChance") -and
    -not $loot.Contains("rare_loot_chest_quality_") -and
    -not $loot.Contains('setObjVar(player, "loot.rls')) "p14.rls.creation-and-persistence-writers-absent"

$initialize = Get-BracedSurface $basePlayer "public int OnInitialize"
$login = Get-BracedSurface $basePlayer "public int OnLogin"
Assert-Contract (([regex]::Matches($basePlayer, [regex]::Escape("loot.retirePostNgeRareLootPlayerState(self)")).Count -eq
        [int]$contract.expected.playerRlsLifecycleCleanupEntrypoints) -and
    $initialize.Contains("loot.retirePostNgeRareLootPlayerState(self)") -and
    $login.Contains("loot.retirePostNgeRareLootPlayerState(self)")) "p14.rls.player-lifecycle-cleanup"

$retireChest = Get-BracedSurface $chest "private boolean retirePlayerOwnedChest"
Assert-Contract ($retireChest.Contains("loot.isPostNgeRareLootSystemRetired()") -and
    $retireChest.Contains("utils.getContainingPlayer(self)") -and
    $retireChest.Contains("loot.retirePostNgeRareLootPlayerState(player)") -and
    $retireChest.Contains("isPlayer(player)") -and
    $retireChest.Contains("destroyObject(self)")) "p14.rls.player-owned-chest-cleanup"
$callbackNames = @("OnAttach", "OnInitialize", "OnTransferred", "OnObjectMenuRequest", "OnObjectMenuSelect")
$guardedCallbacks = 0
foreach ($callback in $callbackNames)
{
    $surface = Get-BracedSurface $chest "public int $callback"
    if ($surface.Contains("retirePlayerOwnedChest(self)")) { $guardedCallbacks++ }
}
Assert-Contract ($guardedCallbacks -eq [int]$contract.expected.playerOwnedChestRetirementCallbacks -and
    -not $chest.Contains("ITEM_USE") -and
    -not $chest.Contains("makeRareLootItem") -and
    -not $chest.Contains("showLootBox") -and
    -not $chest.Contains("modifyCollectionSlotValue") -and
    -not $chest.Contains("handleRareLootCollection") -and
    -not $chest.Contains('"rls/')) "p14.rls.chest-use-and-collection-awards-retired"

$retained = [ordered]@{
    "datatables/item/master_item/master_item.tab" = Join-Path $gameRoot "datatables/item/master_item/master_item.tab"
    "datatables/collection/rewards.tab" = Join-Path $gameRoot "datatables/collection/rewards.tab"
    "datatables/loot/loot_types/rls/rare_loot.tab" = Join-Path $gameRoot "datatables/loot/loot_types/rls/rare_loot.tab"
    "datatables/loot/loot_types/rls/exceptional_loot.tab" = Join-Path $gameRoot "datatables/loot/loot_types/rls/exceptional_loot.tab"
    "datatables/loot/loot_types/rls/legendary_loot.tab" = Join-Path $gameRoot "datatables/loot/loot_types/rls/legendary_loot.tab"
    "object/tangible/item/rare_loot_chest_1.tpf" = Join-Path $gameRoot "object/tangible/item/rare_loot_chest_1.tpf"
    "object/tangible/item/rare_loot_chest_2.tpf" = Join-Path $gameRoot "object/tangible/item/rare_loot_chest_2.tpf"
    "object/tangible/item/rare_loot_chest_3.tpf" = Join-Path $gameRoot "object/tangible/item/rare_loot_chest_3.tpf"
}
foreach ($entry in $retained.GetEnumerator())
{
    Assert-Contract ((Test-Path -LiteralPath $entry.Value -PathType Leaf) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant() -ceq
            [string]$contract.buildEvidence.retainedContentSha256.($entry.Key)) "p14.rls.retained.$($entry.Key).authenticated"
}
$masterItems = Get-Content -LiteralPath $retained["datatables/item/master_item/master_item.tab"] -Raw
$rewards = Get-Content -LiteralPath $retained["datatables/collection/rewards.tab"] -Raw
Assert-Contract (([regex]::Matches($masterItems, '(?m)^rare_loot_chest_quality_[123]\t')).Count -eq
        [int]$contract.expected.retainedStaticItemRows -and
    ([regex]::Matches($rewards, '(?m)^col_(?:rare|exceptional|legendary)_loot_five\t')).Count -eq
        [int]$contract.expected.retainedCollectionRewardRows) "p14.rls.serialized-row-compatibility"

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.fullServerBuild -like "passed*" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        @($contract.requiredBeforeReady).Count -eq 0) "p14.rls.ready-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status -and
        [string]$contract.buildEvidence.result -ceq "passed") "p14.rls.source-status"
}

if ($failures.Count -gt 0)
{
    throw "Post-NGE Rare Loot player runtime retirement failed: $($failures -join ', ')"
}
Write-Host "Post-NGE Rare Loot player runtime retirement passed."
