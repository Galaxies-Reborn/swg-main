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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgeAutomaticPlayerRewardRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$serverGame = Join-Path $source "dsrc/sku.0/sys.server/compiled/game"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$basePlayerPath = Join-Path $serverGame "script/player/base/base_player.java"
$utilsPath = Join-Path $serverGame "script/library/utils.java"
$giftDataPath = Join-Path $serverGame "datatables/veteran_rewards/publish_gift.tab"
$giftItemScriptRoot = Join-Path $serverGame "script/item/publish_gift"
$giftQuestScriptRoot = Join-Path $serverGame "script/systems/collections/publish_gift"
foreach ($evidence in @(
    @{ Path = $basePlayerPath; Name = "base-player" },
    @{ Path = $utilsPath; Name = "utils" },
    @{ Path = $giftDataPath; Name = "publish-gift-data" },
    @{ Path = $giftItemScriptRoot; Name = "publish-gift-item-scripts" },
    @{ Path = $giftQuestScriptRoot; Name = "publish-gift-quest-scripts" }
))
{
    Assert-Contract (Test-Path -LiteralPath $evidence.Path) "p14.automatic-reward.source.$($evidence.Name).exists"
}

$basePlayerHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $basePlayerPath).Hash.ToLowerInvariant()
Assert-Contract ($basePlayerHash -ceq [string]$contract.buildEvidence.sourceSha256."player/base/base_player.java") "p14.automatic-reward.base-player.authenticated"
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$onInitialize = Get-SourceSlice $basePlayer "public int OnInitialize(obj_id self)" "public int OnLogin(obj_id self)"
$onCombatLevelChanged = Get-SourceSlice $basePlayer "public int OnCombatLevelChanged" "public void retirePostNgeAutomaticRewardState"
$cleanup = Get-SourceSlice $basePlayer "public void retirePostNgeAutomaticRewardState" "public void grantLevelSpecificRewards"
$levelGrant = Get-SourceSlice $basePlayer "public void grantLevelSpecificRewards" "public void createLevelReward"
$levelCreate = Get-SourceSlice $basePlayer "public void createLevelReward" "public int updateGCWStanding"
$publishGift = Get-SourceSlice $basePlayer "public void givePublishGift" "public void respecNewEntertainerSkills"
$smugglerBootstrap = Get-SourceSlice $basePlayer "public void sendSmugglerSystemBootstrap" "public int handleSendSmugglerBootstrapRequest"
$smugglerDelivery = Get-SourceSlice $basePlayer "public int handleSendSmugglerBootstrapRequest" "public int handleSmugglerMissionFailureSignal"
$veteranReplacement = Get-SourceSlice $basePlayer "public int msgFlashSpeederConfirmed" "public int playDelayedClientEffect"

Assert-Contract ($onInitialize.Contains("retirePostNgeAutomaticRewardState(self);") -and
    -not $onInitialize.Contains("givePublishGift(self);") -and
    $onInitialize.Contains("sendSmugglerSystemBootstrap(self);") -and
    $onInitialize.Contains("missions.initializeDailyOnLogin(self);")) "p14.automatic-reward.login-boundary"
Assert-Contract (-not $onCombatLevelChanged.Contains("grantLevelSpecificRewards") -and
    -not $onCombatLevelChanged.Contains("createLevelReward")) "p14.automatic-reward.combat-level-callback-retired"
Assert-Contract ($cleanup.Contains('hasObjVar(player, "level.reward")') -and
    $cleanup.Contains('removeObjVar(player, "level.reward");')) "p14.automatic-reward.stale-state-cleanup"
foreach ($legacy in @(
    @{ Body = $levelGrant; Name = "level-grant" },
    @{ Body = $levelCreate; Name = "level-create" },
    @{ Body = $publishGift; Name = "publish-gift" }
))
{
    Assert-Contract (-not $legacy.Body.Contains("createObject") -and
        -not $legacy.Body.Contains("static_item.createNewItemFunction") -and
        -not $legacy.Body.Contains("setObjVar") -and
        -not $legacy.Body.Contains("showLootBox") -and
        -not $legacy.Body.Contains("money.pay")) "p14.automatic-reward.legacy-helper.$($legacy.Name).no-op"
}
Assert-Contract (-not $publishGift.Contains("dataTableGet") -and
    -not $publishGift.Contains("publish_gift.iff")) "p14.automatic-reward.publish-table-unreachable"

$giftCallCount = [regex]::Matches($basePlayer, '(?m)^\s*(?!public\s+void\s+givePublishGift)givePublishGift\(').Count
$levelGrantCallCount = [regex]::Matches($basePlayer, '(?m)^\s*(?!public\s+void\s+grantLevelSpecificRewards)grantLevelSpecificRewards\(').Count
$levelCreateCallCount = [regex]::Matches($basePlayer, '(?m)^\s*(?!public\s+void\s+createLevelReward)createLevelReward\(').Count
Assert-Contract ($giftCallCount -eq 0 -and $levelGrantCallCount -eq 0 -and $levelCreateCallCount -eq 0) "p14.automatic-reward.no-direct-callers"

$giftRows = @(Import-SwgTab -Path $giftDataPath)
$publishNumbers = @($giftRows | ForEach-Object { [int]$_.PUBLISH })
$giftItems = @($giftRows | ForEach-Object { [string]$_.ITEM } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Assert-Contract ($giftRows.Count -eq [int]$contract.diagnosis.publishGiftTableRows -and
    @($publishNumbers | Sort-Object -Unique).Count -eq [int]$contract.diagnosis.distinctPublishNumbers -and
    ($publishNumbers | Measure-Object -Minimum).Minimum -eq [int]$contract.diagnosis.firstPublishNumber -and
    ($publishNumbers | Measure-Object -Maximum).Maximum -eq [int]$contract.diagnosis.lastPublishNumber) "p14.automatic-reward.publish-table-inventory"
Assert-Contract ($giftItems.Count -eq [int]$contract.diagnosis.nonemptyGiftItems -and
    @($giftItems | Sort-Object -Unique).Count -eq [int]$contract.diagnosis.distinctGiftItems) "p14.automatic-reward.publish-item-inventory"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $giftDataPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.publishGiftDataSha256) "p14.automatic-reward.publish-data-preserved"

$giftItemScripts = @(Get-ChildItem -LiteralPath $giftItemScriptRoot -Recurse -Filter "*.java" -File)
$giftQuestScripts = @(Get-ChildItem -LiteralPath $giftQuestScriptRoot -Recurse -Filter "*.java" -File)
Assert-Contract ($giftItemScripts.Count -eq [int]$contract.diagnosis.retainedPublishGiftItemScripts) "p14.automatic-reward.item-scripts-preserved"
Assert-Contract ($giftQuestScripts.Count -eq [int]$contract.diagnosis.retainedPublishGiftCollectionScripts) "p14.automatic-reward.quest-scripts-preserved"

$utilsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $utilsPath).Hash.ToLowerInvariant()
$utilsSource = Get-Content -LiteralPath $utilsPath -Raw
$professionPredicate = Get-SourceSlice $utilsSource "public static boolean isProfession" "public static boolean isPrecuRetainedItemClass"
Assert-Contract ($utilsHash -ceq [string]$contract.continuityEvidence.professionPredicateSourceSha256 -and
    $professionPredicate.Contains("case SMUGGLER:") -and
    $professionPredicate.Contains('hasSkill(player, "combat_smuggler_novice")')) "p14.automatic-reward.smuggler-precu-profession-gate"
Assert-Contract ($smugglerBootstrap.Contains("utils.isProfession(self, utils.SMUGGLER)") -and
    $smugglerBootstrap.Contains("isInTutorialArea(self)") -and
    $smugglerBootstrap.Contains('hasObjVar(self, "smuggler_bootstrap")') -and
    $smugglerBootstrap.Contains('messageTo(self, "handleSendSmugglerBootstrapRequest"')) "p14.automatic-reward.smuggler-bootstrap-preserved"
Assert-Contract ($smugglerDelivery.Contains('chatSendPersistentMessage("Barak"') -and
    $smugglerDelivery.Contains('"smuggler_broker_barak"') -and
    $smugglerDelivery.Contains('setObjVar(self, "smuggler_bootstrap", 1)')) "p14.automatic-reward.smuggler-delivery-preserved"
Assert-Contract ($veteranReplacement.Contains("veteran_deprecated.FLASH_SPEEDER_COST") -and
    $veteranReplacement.Contains("money.pay(self, money.ACCT_VEHICLE_REPAIRS") -and
    $veteranReplacement.Contains('createObjectInInventoryAllowOverload("object/tangible/deed/vehicle_deed/speederbike_flash_deed.iff"')) "p14.automatic-reward.explicit-veteran-replacement-preserved"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path (Join-Path $serverGame "script") $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.automatic-reward.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "p14.automatic-reward.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) "p14.automatic-reward.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256."player/base/base_player.class" -cne "pending" -and
        [string]$contract.buildEvidence.fullJavaCompile -like "passed*") "p14.automatic-reward.compiled-evidence"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) "p14.automatic-reward.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) "p14.automatic-reward.source-status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgeAutomaticPlayerRewardRetirement)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) "p14.automatic-reward.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "Post-NGE automatic player reward retirement failed: $($failures -join ', ')"
}
Write-Host "Post-NGE automatic player reward retirement contract passed."
