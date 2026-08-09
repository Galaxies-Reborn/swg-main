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
    ([string]$manifest.contracts.p14PostNgePlayerXpBuffAdmissionRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$serverGame = Join-Path $dsrc "sku.0/sys.server/compiled/game"
$sharedGame = Join-Path $dsrc "sku.0/sys.shared/compiled/game"
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

$paths = [ordered]@{
    "library/buff.java" = Join-Path $serverGame "script/library/buff.java"
    "datatables/buff/buff.tab" = Join-Path $sharedGame "datatables/buff/buff.tab"
    "datatables/buff/effect_mapping.tab" = Join-Path $sharedGame "datatables/buff/effect_mapping.tab"
    "datatables/item/master_item/item_stats.tab" = Join-Path $serverGame "datatables/item/master_item/item_stats.tab"
    "datatables/item/master_item/master_item.tab" = Join-Path $serverGame "datatables/item/master_item/master_item.tab"
    "datatables/veteran_rewards/items.tab" = Join-Path $serverGame "datatables/veteran_rewards/items.tab"
    "datatables/item/vendor/imperial_emperorsday_stuff.tab" = Join-Path $serverGame "datatables/item/vendor/imperial_emperorsday_stuff.tab"
    "datatables/item/vendor/loveday_stuff.tab" = Join-Path $serverGame "datatables/item/vendor/loveday_stuff.tab"
    "datatables/item/vendor/rebel_emperorsday_stuff.tab" = Join-Path $serverGame "datatables/item/vendor/rebel_emperorsday_stuff.tab"
    "object/tangible/food/mtp_meatlump_xp_wine.tpf" = Join-Path $serverGame "object/tangible/food/mtp_meatlump_xp_wine.tpf"
}
$text = @{}
foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) "p14.xp-buff.$($entry.Key).exists"
    if (Test-Path -LiteralPath $entry.Value -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
            "p14.xp-buff.$($entry.Key).authenticated"
        $text[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
    }
}

$directCommit = (& git -C $dsrc rev-parse HEAD).Trim()
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($LASTEXITCODE -eq 0 -and $dsrcPin.Count -eq 1 -and
    $directCommit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
    [string]$dsrcPin[0].commit -ceq $directCommit) "p14.xp-buff.direct-source-pin"

$buffNames = @($contract.inventory.retiredBuffs | ForEach-Object { [string]$_ } | Sort-Object)
$buffTable = [string]$text["datatables/buff/buff.tab"]
$rows = @([regex]::Matches($buffTable,
    '(?m)^(buddy_xp_buff|event_ewok_berry|event_imperial_cookies|event_rebel_drink|ice_cream_xp_bonus|mtp_meatlump_wine_xp_buff|vet_exp_buff_item_buff)\t[^\r\n]+$') |
    ForEach-Object { $_.Value })
$rowNames = @($rows | ForEach-Object { ($_ -split "`t")[0] } | Sort-Object)
Assert-Contract ($rows.Count -eq [int]$contract.expected.retiredBuffRows -and
    (($rowNames -join "`n") -ceq ($buffNames -join "`n")) -and
    @($rows | Where-Object { $_ -notmatch "`txp_bonus_general`t" }).Count -eq 0) `
    "p14.xp-buff.data-inventory-authenticated"

$mapping = [string]$text["datatables/buff/effect_mapping.tab"]
$mappingRows = @([regex]::Matches($mapping, '(?m)^xp_bonus_general\txpBonusGeneral\txp_bonus_general\t[^\r\n]*$'))
Assert-Contract ($mappingRows.Count -eq [int]$contract.expected.retiredEffectMappings) `
    "p14.xp-buff.effect-mapping-authenticated"

$itemStats = [string]$text["datatables/item/master_item/item_stats.tab"]
$itemStatNames = @($contract.inventory.retainedItemStatConsumers | ForEach-Object { [string]$_ })
$itemStatRows = 0
foreach ($name in $itemStatNames)
{
    if ($itemStats -match "(?m)^$([regex]::Escape($name))`t") { $itemStatRows++ }
}
$masterItems = [string]$text["datatables/item/master_item/master_item.tab"]
$masterItemRows = @([regex]::Matches($masterItems,
    '(?m)^(item_cs_exp_buff_item_03_01|item_event_ewok_berry_01_02|item_event_imperial_cookies_01_01|item_event_rebel_drink_01_01|item_ice_cream_buff_xp_bonus_01_01|item_mtp_meatlump_xp_wine_02_01|item_reward_buddy_xp_chip_06_01|item_vet_exp_buff_item_03_01)\t')).Count
$veteranRows = @([regex]::Matches([string]$text["datatables/veteran_rewards/items.tab"],
    '(?m)^cybernetic_xp_chip\t')).Count
$vendorRows = 0
foreach ($vendor in @(
    @{ Path = "datatables/item/vendor/imperial_emperorsday_stuff.tab"; Item = "item_event_imperial_cookies_01_01" },
    @{ Path = "datatables/item/vendor/loveday_stuff.tab"; Item = "item_event_ewok_berry_01_01" },
    @{ Path = "datatables/item/vendor/rebel_emperorsday_stuff.tab"; Item = "item_event_rebel_drink_01_01" }
))
{
    if ([string]$text[$vendor.Path] -match "(?m)^$([regex]::Escape($vendor.Item))`t") { $vendorRows++ }
}
$templateRows = @([regex]::Matches([string]$text["object/tangible/food/mtp_meatlump_xp_wine.tpf"],
    '"buff_name"="mtp_meatlump_wine_xp_buff"')).Count
Assert-Contract ($itemStatRows -eq [int]$contract.expected.retainedItemStatConsumers -and
    $masterItemRows -eq [int]$contract.expected.retainedMasterItemConsumers -and
    $veteranRows -eq [int]$contract.expected.retainedVeteranRewardRows -and
    $vendorRows -eq [int]$contract.expected.retainedVendorConsumers -and
    $templateRows -eq [int]$contract.expected.retainedTemplateConsumers) `
    "p14.xp-buff.content-consumers-retained"

$buff = [string]$text["library/buff.java"]
$inventoryStart = $buff.IndexOf("RETIRED_POST_NGE_PLAYER_XP_BONUS_BUFFS", [StringComparison]::Ordinal)
$inventoryEnd = $buff.IndexOf("public static boolean isRetiredPostNgePlayerXpBonusBuffName", $inventoryStart,
    [StringComparison]::Ordinal)
$inventorySource = if ($inventoryStart -ge 0 -and $inventoryEnd -gt $inventoryStart) {
    $buff.Substring($inventoryStart, $inventoryEnd - $inventoryStart)
} else { "" }
$sourceNames = @([regex]::Matches($inventorySource, '"([a-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Assert-Contract ($sourceNames.Count -eq [int]$contract.expected.retiredBuffRows -and
    (($sourceNames -join "`n") -ceq ($buffNames -join "`n"))) "p14.xp-buff.source-inventory-exact"

$predicate = Get-BracedSurface $buff "public static boolean isRetiredPostNgePlayerXpBonusBuff(obj_id target"
$cleanup = Get-BracedSurface $buff "public static void retirePostNgePlayerXpBonusBuffState"
$lifecycle = Get-BracedSurface $buff "public static void retirePostNgeBuffProgression"
$admission = Get-BracedSurface $buff "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)"
$application = Get-BracedSurface $buff "public static boolean applyBuff(obj_id target, obj_id owner, int nameCrc, float duration, float customValue, int stack)"
$guard = $admission.IndexOf("isRetiredPostNgePlayerXpBonusBuff(target, bdata)", [StringComparison]::Ordinal)
$existing = $admission.IndexOf("hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
Assert-Contract ($predicate.Contains("isPlayer(target)") -and
    $predicate.Contains("isRetiredPostNgePlayerXpBonusBuffName(data.buffName)")) `
    "p14.xp-buff.player-only-predicate"
Assert-Contract ($cleanup.Contains("RETIRED_POST_NGE_PLAYER_XP_BONUS_BUFFS") -and
    $cleanup.Contains("removeBuff(player, retiredBuff)") -and
    $cleanup.Contains('removeScriptVarTree(player, "buff.xpBonusGeneral")') -and
    $lifecycle.Contains("retirePostNgePlayerXpBonusBuffState(player)")) `
    "p14.xp-buff.persistence-and-login-cleanup"
Assert-Contract ($guard -ge 0 -and $existing -gt $guard -and
    $application.IndexOf("canApplyBuff(target, owner, nameCrc)", [StringComparison]::Ordinal) -ge 0 -and
    -not [bool]$contract.expected.genericPlayerAdmissionReachable -and
    -not [bool]$contract.expected.refreshReadmissionReachable -and
    -not [bool]$contract.expected.emptyStatusIconReachable -and
    -not [bool]$contract.expected.itemConsumptionAfterRejectedAdmission) `
    "p14.xp-buff.admission-application-refresh-fail-closed"
Assert-Contract (-not [bool]$contract.expected.preCuExplicitSkillXpAffected -and
    -not [bool]$contract.expected.retainedExpansionContentAffected) `
    "p14.xp-buff.precu-and-content-boundary"

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.fullServerBuild -like "passed*" -and
        [string]$contract.buildEvidence.deployedBytecodeAudit -like "passed*" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        @($contract.requiredBeforeReady).Count -eq 0) "p14.xp-buff.ready-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status -and
        [string]$contract.buildEvidence.result -ceq "passed") "p14.xp-buff.source-status"
}

if ($failures.Count -gt 0)
{
    throw "Post-NGE player XP-buff admission retirement failed: $($failures -join ', ')"
}
Write-Host "Post-NGE player XP-buff admission retirement passed."
