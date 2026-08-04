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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuTcgInstantXpAdapter)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$dataRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables"
$tcgPath = Join-Path $scriptRoot "systems/tcg/tcg_instant_xp_grant.java"
$masterItemPath = Join-Path $dataRoot "item/master_item/master_item.tab"
$itemStatsPath = Join-Path $dataRoot "item/master_item/item_stats.tab"
$xpPath = Join-Path $scriptRoot "library/xp.java"
$collectionPath = Join-Path $scriptRoot "library/collection.java"
$magsealPath = Join-Path $dataRoot "loot/loot_items/collectible/magseal_loot.tab"
$buffHandlerPath = Join-Path $scriptRoot "systems/buff/buff_handler.java"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { return "" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

foreach ($path in @($tcgPath, $masterItemPath, $itemStatsPath, $xpPath,
    $collectionPath, $magsealPath, $buffHandlerPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.tcg-xp-adapter.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$tcg = Get-Content -LiteralPath $tcgPath -Raw
$master = @(Import-Csv -LiteralPath $masterItemPath -Delimiter "`t" | Where-Object {
    $_.name -ceq "item_tcg_loot_reward_series4_t16_toy_02_01"
})
$stats = @(Import-Csv -LiteralPath $itemStatsPath -Delimiter "`t" | Where-Object {
    $_.name -ceq "item_tcg_loot_reward_series4_t16_toy_02_01"
})

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    $path = if ($property.Name -ceq "systems/tcg/tcg_instant_xp_grant.java") {
        $tcgPath
    } else {
        $masterItemPath
    }
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.tcg-xp-adapter.$($property.Name).authenticated"
}

$select = Get-BracedSurface $tcg "public int OnObjectMenuSelect"
Assert-Contract ($select.Contains("utils.getContainingPlayer(self) != player") -and
    $select.Contains('hasObjVar(self, "grant_xp_percent")')) `
    "p14.tcg-xp-adapter.item-ownership-and-authored-guard"
Assert-Contract (-not $tcg.Contains("getLevel(") -and
    -not $tcg.Contains("player_level.iff") -and
    -not $tcg.Contains("dataTableGetInt(") -and
    -not $tcg.Contains("grantXpByTemplate") -and
    -not $tcg.Contains("grantExperiencePoints") -and
    -not $tcg.Contains("reward_xp_amount") -and
    -not $tcg.Contains("xpToGrant")) `
    "p14.tcg-xp-adapter.nge-level-xp-path-retired"

$grantMarker = 'collection.grantRandomCollectionItem(player, "datatables/loot/loot_items/collectible/magseal_loot.iff", "collections")'
$grantIndex = $select.IndexOf($grantMarker, [StringComparison]::Ordinal)
$failureIndex = $select.IndexOf("!isValidId(collectionItem) || !exists(collectionItem)", [StringComparison]::Ordinal)
$failureReturnIndex = $select.IndexOf("return SCRIPT_CONTINUE;", $failureIndex, [StringComparison]::Ordinal)
$effectIndex = $select.IndexOf('playClientEffectObj(player, "clienteffect/tcg_t16_skyhopper_toy_flyby.cef"', [StringComparison]::Ordinal)
$decrementIndex = $select.IndexOf("decrementCount(self);", [StringComparison]::Ordinal)
Assert-Contract ($grantIndex -ge 0 -and $failureIndex -gt $grantIndex -and
    $failureReturnIndex -gt $failureIndex -and $effectIndex -gt $failureReturnIndex -and
    $decrementIndex -gt $effectIndex -and
    [regex]::Matches($select, 'decrementCount\(self\);').Count -eq
        [int]$contract.diagnosis.expectedConsumeCalls) `
    "p14.tcg-xp-adapter.delivery-before-consume"
Assert-Contract ($select.Contains("item was not consumed") -and
    $select.Contains("PRE-CU collection item") -and
    -not $select.Contains("was granted XP")) `
    "p14.tcg-xp-adapter.truthful-result-reporting"

Assert-Contract ($master.Count -eq [int]$contract.diagnosis.authoredItemRows -and
    [string]$master[0].template_name -ceq "object/tangible/tcg/series4/consumable_t16_toy.iff" -and
    @(([string]$master[0].scripts -split ',') | Where-Object {
        $_ -ceq "systems.tcg.tcg_instant_xp_grant"
    }).Count -eq 1 -and
    [string]$master[0].string_detail -like "*grants a random collection item*" -and
    [string]$master[0].comments -like "PRE-CU collection replacement*") `
    "p14.tcg-xp-adapter.authored-item-and-description"
Assert-Contract ($stats.Count -eq 1 -and
    [string]$stats[0].objvars -ceq "float:grant_xp_percent=0.2") `
    "p14.tcg-xp-adapter.authored-compatibility-objvar"

Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $itemStatsPath).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.itemStatsSha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $xpPath).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.xpLibrarySha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $collectionPath).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.collectionLibrarySha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $magsealPath).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.magsealLootSha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $buffHandlerPath).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.buffHandlerSha256) `
    "p14.tcg-xp-adapter.retained-content-continuity"

$xp = Get-Content -LiteralPath $xpPath -Raw
$buffHandler = Get-Content -LiteralPath $buffHandlerPath -Raw
$templateXp = Get-BracedSurface $xp "public static int grantXpByTemplate"
$percentageXp = Get-BracedSurface $xp "public static int grantUnmodifiedXPPercentageOfLevel"
$generalBuff = Get-BracedSurface $buffHandler "public int xpBonusGeneralAddBuffHandler"
$grantedBuff = Get-BracedSurface $buffHandler "public int xpGrantedGeneralAddBuffHandler"
Assert-Contract ($templateXp.Contains("return 0;") -and
    $percentageXp.Contains("return 0;")) "p14.tcg-xp-adapter.generic-xp-abi-still-fails-closed"
Assert-Contract ($generalBuff.Contains("buff.isPostNgeBuffProgressionRetired()") -and
    $grantedBuff.Contains("buff.isPostNgeBuffProgressionRetired()") -and
    $generalBuff.IndexOf("return SCRIPT_CONTINUE;", [StringComparison]::Ordinal) -lt
        $generalBuff.IndexOf("getPrecuEncounterDifficulty", [StringComparison]::Ordinal) -and
    $grantedBuff.IndexOf("return SCRIPT_CONTINUE;", [StringComparison]::Ordinal) -lt
        $grantedBuff.IndexOf("getPrecuEncounterDifficulty", [StringComparison]::Ordinal)) `
    "p14.tcg-xp-adapter.adjacent-nge-buff-xp-unreachable"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.tcg-xp-adapter.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.tcg-xp-adapter.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.tcg-xp-adapter.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.tcg-xp-adapter.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.tcg-xp-adapter.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.tcg-xp-adapter.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU TCG instant-XP adapter failed: $($failures -join ', ')"
}
Write-Host "PRE-CU TCG instant-XP adapter contract passed."
