[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PgcHolocronVendorRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Get-TextSha256([string]$Text)
{
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    Assert-Contract ($start -ge 0) "Missing source surface: $Signature"
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    Assert-Contract ($brace -ge 0) "Missing opening brace: $Signature"
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
    throw "Missing closing brace: $Signature"
}

Assert-Contract (@($contract.sourceFiles.PSObject.Properties).Count -eq [int]$contract.expected.authoritativeSources) "PGC authoritative source count drifted."
$paths = [ordered]@{}
$texts = @{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $root ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $paths[$property.Name] -PathType Leaf) "Missing PGC source: $($property.Name)"
    $texts[$property.Name] = Get-Content -LiteralPath $paths[$property.Name] -Raw
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value) "PGC source hash drifted: $($property.Name)"
}

$control = [string]$texts.questControlDevice
Assert-Contract (-not $control.Contains("menuInfo.addRootMenu") -and -not $control.Contains("pgc_quests.setQuestAbandoned")) "PGC control-device menu mutation remains."
$credit = [string]$texts.creditItem
foreach ($forbidden in @("mi.addRootMenu", 'money.bankTo("pgc_player_donated_credits"', "destroyObject(self)"))
{
    Assert-Contract (-not $credit.Contains($forbidden)) "PGC donated-credit mutation remains: $forbidden"
}
Assert-Contract ($credit.Contains('detachScript(self, "quest.task.pgc.credit_item")')) "PGC credit item does not detach."

$holocron = [string]$texts.questHolocron
$saga = [string]$texts.playerSaga
Assert-Contract (
    [regex]::Matches($holocron, [regex]::Escape('detachScript(self, "quest.task.pgc.quest_holocron")')).Count -eq [int]$contract.expected.questHolocronDetachBoundaries -and
    [regex]::Matches($saga, [regex]::Escape('detachScript(self, "player.player_saga_quest")')).Count -eq [int]$contract.expected.playerSagaDetachBoundaries
) "PGC holocron/player-saga detach boundary drifted."

$residualRecords = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in @($contract.residualScriptCallbackInventory.sourcePaths | ForEach-Object { [string]$_ }))
{
    $path = Join-Path $scriptRoot $relativePath
    foreach ($match in @(Select-String -LiteralPath $path -Pattern ([string]$contract.residualScriptCallbackInventory.pattern)))
    {
        $residualRecords.Add($relativePath + ":" + $match.LineNumber + "|" + $match.Line.Trim())
    }
}
$residualRecords = @($residualRecords | Sort-Object)
$residualMethods = @($residualRecords | ForEach-Object {
    Assert-Contract ($_ -match '\|\s*public\s+int\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(') "Invalid PGC public-int inventory record."
    $Matches[1]
})
$helperMethods = @($residualMethods | Where-Object { $_ -ceq "performGetTime" } | Sort-Object -Unique)
$callbackMethods = @($residualMethods | Where-Object { $_ -cne "performGetTime" })
$playerSagaRecords = @($residualRecords | Where-Object { $_.StartsWith("player/player_saga_quest.java:") })
$questHolocronRecords = @($residualRecords | Where-Object { $_.StartsWith("quest/task/pgc/quest_holocron.java:") })
$expectedHelperMethods = @($contract.residualScriptCallbackInventory.helperMethodNames | ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract (
    $residualRecords.Count -eq [int]$contract.residualScriptCallbackInventory.publicIntMethods -and
    $playerSagaRecords.Count -eq [int]$contract.residualScriptCallbackInventory.playerSagaPublicIntMethods -and
    $questHolocronRecords.Count -eq [int]$contract.residualScriptCallbackInventory.questHolocronPublicIntMethods -and
    $callbackMethods.Count -eq [int]$contract.residualScriptCallbackInventory.callbackMethods -and
    $helperMethods.Count -eq [int]$contract.residualScriptCallbackInventory.helperMethods -and
    ($helperMethods -join "`n") -ceq ($expectedHelperMethods -join "`n") -and
    (Get-TextSha256 ($residualRecords -join "`n")) -ceq [string]$contract.residualScriptCallbackInventory.inventorySha256
) "Complete PGC player-saga/quest-holocron public-int inventory drifted."

$playerSagaResidualMarkers = [ordered]@{
    handleChroniclesTermsOfService = "sui.createSUIPage("
    OnCreateSaga = "showHolocronCreationCountdownUi("
    handleSharedPgcHolocronOffer = "sui.msgbox("
    handleSharedChroniclesQuestResponse = 'utils.removeScriptVar(self, player + ".sharedHolocron")'
    handleSharedPgcHolocronCreation = "createChronicleQuestObject("
    handlePgcHolocronCreation = "showHolocronCreationCountdownUi("
    handlePgcHolocronCreationCountdownTimer = "createChronicleQuestObject("
    handleCheckForGainedChroniclesLevelDelay = "pgc_quests.checkForGainedChroniclesLevel("
    OnLogin = "pgc_quests.activatePlayerQuestWaypointFromHolocron("
    playerQuestSetLocationTarget = "addLocationTarget("
    playerQuestRemoveLocationTarget = "removeLocationTarget(locationName);"
}
$expectedPlayerSagaResidualMethods = @($contract.residualScriptCallbackInventory.playerSagaResidualMethodNames |
    ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract (
    $playerSagaResidualMarkers.Count -eq [int]$contract.residualScriptCallbackInventory.playerSagaResidualCallbacks -and
    (@($playerSagaResidualMarkers.Keys | Sort-Object) -join "`n") -ceq ($expectedPlayerSagaResidualMethods -join "`n")
) "Player-saga residual callback classification drifted."
foreach ($entry in $playerSagaResidualMarkers.GetEnumerator())
{
    $surface = Get-BracedSurface $saga ("public int " + $entry.Key)
    $guard = $surface.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
    $cleanup = $surface.IndexOf("retireChroniclesPlayerCallback(self);", [StringComparison]::Ordinal)
    $return = $surface.IndexOf("return SCRIPT_CONTINUE;", $cleanup + 1, [StringComparison]::Ordinal)
    $mutation = $surface.IndexOf([string]$entry.Value, [StringComparison]::Ordinal)
    Assert-Contract (
        $guard -ge 0 -and $cleanup -gt $guard -and $return -gt $cleanup -and $mutation -gt $return
    ) "Player-saga residual callback is not dominated by retirement: $($entry.Key)"
}

$questHolocronResidualMarkers = [ordered]@{
    handleCheckCompletedHolocron = "if (hasObjVar("
    OnObjectMenuRequest = "/*"
    OnObjectMenuSelect = "/*"
    OnGetAttributes = "if (!exists(self))"
    OnAboutToReceiveItem = "if (hasObjVar("
    OnAboutToLoseItem = "if (utils.hasScriptVar("
    handleQuestHolocronActivated = "pgc_quests.handlePhaseActived("
    handleQuestHolocronInitializeTaskStatus = "pgc_quests.initializeQuestTasksStatus("
    handleQuestHolocronAbandoned = "if (isIdValid(player))"
    handleHolocronSharedSuccess = "if (params != null"
}
$expectedQuestHolocronResidualMethods = @($contract.residualScriptCallbackInventory.questHolocronResidualMethodNames |
    ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract (
    $questHolocronResidualMarkers.Count -eq [int]$contract.residualScriptCallbackInventory.questHolocronResidualCallbacks -and
    (@($questHolocronResidualMarkers.Keys | Sort-Object) -join "`n") -ceq ($expectedQuestHolocronResidualMethods -join "`n")
) "Quest-holocron residual callback classification drifted."
foreach ($entry in $questHolocronResidualMarkers.GetEnumerator())
{
    $surface = Get-BracedSurface $holocron ("public int " + $entry.Key)
    $guard = $surface.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
    $cleanup = $surface.IndexOf("retireChroniclesHolocronCallback(self,", [StringComparison]::Ordinal)
    $expectedReturn = if ($entry.Key -ceq "OnAboutToReceiveItem") { "return SCRIPT_OVERRIDE;" } else { "return SCRIPT_CONTINUE;" }
    $return = $surface.IndexOf($expectedReturn, $cleanup + 1, [StringComparison]::Ordinal)
    $mutation = $surface.IndexOf([string]$entry.Value, [StringComparison]::Ordinal)
    Assert-Contract (
        $guard -ge 0 -and $cleanup -gt $guard -and $return -gt $cleanup -and $mutation -gt $return
    ) "Quest-holocron residual callback is not dominated by retirement: $($entry.Key)"
}
Assert-Contract (
    [int]$contract.expected.unguardedResidualCallbacks -eq 0 -and
    -not [bool]$contract.expected.retiredHolocronDepositsAllowed -and
    [bool]$contract.expected.persistedHolocronRewardRemovalAllowed
) "PGC residual item-transfer policy drifted."

$pgcQuests = [string]$texts.pgcQuests
$retirementState = Get-BracedSurface $pgcQuests "public static void retireChroniclesPlayerProgressionState"
Assert-Contract (
    $retirementState.Contains('utils.removeScriptVarTree(player, "chronicles");') -and
    $retirementState.Contains('utils.removeScriptVarTree(player, "chroniclesRewards");') -and
    $retirementState.Contains('utils.hasScriptVar(player, "temp_pgcTaskDictionary")') -and
    $retirementState.Contains("forceCloseSUIPage(countdownPage);") -and
    $retirementState.Contains("detachScript(player, sui.COUNTDOWNTIMER_PLAYER_SCRIPT);") -and
    [bool]$contract.expected.stalePgcCountdownCleanup -and
    [bool]$contract.expected.staleChroniclesScriptVarTreesRemoved
) "Chronicles player-state cleanup boundary drifted."

$loot = [string]$texts.loot
$lootRetirementSurfaces = [ordered]@{
    "public static boolean addChronicleLoot" = [ordered]@{ mutation = "String creatureName ="; return = "return false;" }
    "public static obj_id chroniclesCraftingLootDrop" = [ordered]@{ mutation = "if (hasToggledChroniclesLootOff(player))"; return = "return obj_id.NULL_ID;" }
    "public static obj_id chroniclesPvpLootDrop" = [ordered]@{ mutation = "if (hasToggledChroniclesLootOff(player))"; return = "return obj_id.NULL_ID;" }
    "public static obj_id chroniclesNonCorpseLootDrop" = [ordered]@{ mutation = 'String configChance_string = getConfigSetting("GameServer", "chroniclesLootChanceOverride");'; return = "return obj_id.NULL_ID;" }
    "public static boolean hasToggledChroniclesLootOff" = [ordered]@{ mutation = "return hasObjVar(player, CHRONICLES_LOOT_TOGGLE_OBJVAR);"; return = "return true;" }
    "public static void disableChroniclesLoot" = [ordered]@{ mutation = "setObjVar(player, CHRONICLES_LOOT_TOGGLE_OBJVAR, true);"; return = "return;" }
    "public static void enableChroniclesLoot" = [ordered]@{ mutation = "removeObjVar(player, CHRONICLES_LOOT_TOGGLE_OBJVAR);"; return = "return;" }
}
foreach ($entry in $lootRetirementSurfaces.GetEnumerator())
{
    $surface = Get-BracedSurface $loot $entry.Key
    $guard = $surface.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
    $retirementReturn = $surface.IndexOf([string]$entry.Value.return, $guard + 1, [StringComparison]::Ordinal)
    $mutation = $surface.LastIndexOf([string]$entry.Value.mutation, [StringComparison]::Ordinal)
    Assert-Contract (
        $guard -ge 0 -and $retirementReturn -gt $guard -and $mutation -gt $retirementReturn
    ) "Chronicles loot surface is not dominated by retirement: $($entry.Key)"
}
Assert-Contract (
    -not ([string]$texts.baseTool).Contains("loot.chroniclesCraftingLootDrop(") -and
    -not ([string]$texts.gcw).Contains("loot.chroniclesPvpLootDrop(") -and
    [int]$contract.expected.chroniclesCraftingHookCalls -eq 0 -and
    [int]$contract.expected.chroniclesPvpHookCalls -eq 0 -and
    -not [bool]$contract.expected.chroniclesCreatureLootEnabled -and
    -not [bool]$contract.expected.chroniclesCraftingLootEnabled -and
    -not [bool]$contract.expected.chroniclesPvpLootEnabled
) "Normal crafting or PvP flow still invokes Chronicles relic loot."

$addRelic = Get-BracedSurface $pgcQuests "public static void addRelicToQuestBuilder"
$addRelicGuard = $addRelic.IndexOf("if (isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
$addRelicCleanup = $addRelic.IndexOf("retireChroniclesPlayerProgressionState(player);", [StringComparison]::Ordinal)
$addRelicReturn = $addRelic.IndexOf("return;", $addRelicCleanup + 1, [StringComparison]::Ordinal)
$addRelicMutation = $addRelic.IndexOf("if (!utils.isNestedWithin(relic, player))", [StringComparison]::Ordinal)
$canUseRelic = Get-BracedSurface $pgcQuests "public static boolean canUseRelic"
$canUseRelicGuard = $canUseRelic.IndexOf("if (isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
$canUseRelicReturn = $canUseRelic.IndexOf("return false;", $canUseRelicGuard + 1, [StringComparison]::Ordinal)
$canUseRelicMutation = $canUseRelic.IndexOf("getEnhancedSkillStatisticModifierUncapped(", [StringComparison]::Ordinal)
Assert-Contract (
    $addRelicGuard -ge 0 -and $addRelicCleanup -gt $addRelicGuard -and
    $addRelicReturn -gt $addRelicCleanup -and $addRelicMutation -gt $addRelicReturn -and
    $canUseRelicGuard -ge 0 -and $canUseRelicReturn -gt $canUseRelicGuard -and
    $canUseRelicMutation -gt $canUseRelicReturn -and
    -not [bool]$contract.expected.chroniclesRelicCollectionMutationEnabled
) "Central Chronicles relic collection mutation is not dominated by retirement."

$fragment = [string]$texts.consumeFragment
foreach ($signature in @("public int OnInitialize", "public int OnAttach"))
{
    $surface = Get-BracedSurface $fragment $signature
    Assert-Contract ($surface.Contains("retireChroniclesFragment(self, obj_id.NULL_ID);")) "Chronicles fragment does not detach from $signature."
}
$fragmentHelper = Get-BracedSurface $fragment "private void retireChroniclesFragment"
Assert-Contract (
    $fragmentHelper.Contains("forceCloseSUIPage(pid);") -and
    $fragmentHelper.Contains("sui.removePid(player, PID_NAME);") -and
    $fragmentHelper.Contains('detachScript(self, "systems.player_quest.consume_fragment");')
) "Chronicles fragment retirement cleanup drifted."
$fragmentMutationSurfaces = [ordered]@{
    "public int OnObjectMenuRequest" = [ordered]@{ mutation = "mi.addRootMenu("; return = "return SCRIPT_CONTINUE;" }
    "public int OnObjectMenuSelect" = [ordered]@{ mutation = "sendDirtyObjectMenuNotification(self);"; return = "return SCRIPT_CONTINUE;" }
    "public boolean getUiConsumeMessageBox" = [ordered]@{ mutation = "sui.msgbox("; return = "return false;" }
    "public int handlerSuiFragmentReconstruct" = [ordered]@{ mutation = "int bp = sui.getIntButtonPressed(params);"; return = "return SCRIPT_CONTINUE;" }
    "public void reconstructFragment" = [ordered]@{ mutation = "if (!utils.isNestedWithin(self, player))"; return = "return;" }
}
foreach ($entry in $fragmentMutationSurfaces.GetEnumerator())
{
    $surface = Get-BracedSurface $fragment $entry.Key
    $guard = $surface.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
    $cleanup = $surface.IndexOf("retireChroniclesFragment(self, player);", [StringComparison]::Ordinal)
    $retirementReturn = $surface.IndexOf([string]$entry.Value.return, $cleanup + 1, [StringComparison]::Ordinal)
    $mutation = $surface.IndexOf([string]$entry.Value.mutation, [StringComparison]::Ordinal)
    Assert-Contract (
        $guard -ge 0 -and $cleanup -gt $guard -and $retirementReturn -gt $cleanup -and $mutation -gt $retirementReturn
    ) "Chronicles fragment mutation is not dominated by retirement: $($entry.Key)"
}

$relic = [string]$texts.consumeRelic
foreach ($signature in @("public int OnInitialize", "public int OnAttach"))
{
    $surface = Get-BracedSurface $relic $signature
    Assert-Contract ($surface.Contains("retireChroniclesRelic(self, obj_id.NULL_ID);")) "Chronicles relic does not detach from $signature."
}
$relicHelper = Get-BracedSurface $relic "private void retireChroniclesRelic"
Assert-Contract (
    $relicHelper.Contains("forceCloseSUIPage(pid);") -and
    $relicHelper.Contains('utils.removeScriptVar(self, "relic_addQuestBuilderAll");') -and
    $relicHelper.Contains('utils.removeScriptVar(self, "relic_deconstructAll");') -and
    $relicHelper.Contains('detachScript(self, "systems.player_quest.consume_relic");')
) "Chronicles relic retirement cleanup drifted."
$relicMutationSurfaces = [ordered]@{
    "public int OnObjectMenuRequest" = [ordered]@{ mutation = "if (utils.isNestedWithinAPlayer(self))"; return = "return SCRIPT_CONTINUE;" }
    "public int OnObjectMenuSelect" = [ordered]@{ mutation = "sendDirtyObjectMenuNotification(self);"; return = "return SCRIPT_CONTINUE;" }
    "public boolean getUiConsumeMessageBox" = [ordered]@{ mutation = "sui.msgbox("; return = "return false;" }
    "public int handlerSuiAddToQuestBuilder" = [ordered]@{ mutation = "int bp = sui.getIntButtonPressed(params);"; return = "return SCRIPT_CONTINUE;" }
    "public int handlerSuiRelicDeconstruct" = [ordered]@{ mutation = "int bp = sui.getIntButtonPressed(params);"; return = "return SCRIPT_CONTINUE;" }
    "public void deconstructRelic" = [ordered]@{ mutation = "if (!utils.isNestedWithin(self, player))"; return = "return;" }
}
foreach ($entry in $relicMutationSurfaces.GetEnumerator())
{
    $surface = Get-BracedSurface $relic $entry.Key
    $guard = $surface.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
    $cleanup = $surface.IndexOf("retireChroniclesRelic(self, player);", [StringComparison]::Ordinal)
    $retirementReturn = $surface.IndexOf([string]$entry.Value.return, $cleanup + 1, [StringComparison]::Ordinal)
    $mutation = $surface.IndexOf([string]$entry.Value.mutation, [StringComparison]::Ordinal)
    Assert-Contract (
        $guard -ge 0 -and $cleanup -gt $guard -and $retirementReturn -gt $cleanup -and $mutation -gt $retirementReturn
    ) "Chronicles relic mutation is not dominated by retirement: $($entry.Key)"
}
Assert-Contract (
    -not [bool]$contract.expected.chroniclesRelicMenusEnabled -and
    -not [bool]$contract.expected.chroniclesRelicConversionEnabled -and
    [int]$contract.expected.unguardedChroniclesRelicMutations -eq 0
) "Chronicles relic lifecycle policy drifted."

foreach ($signature in @("public int OnObjectMenuRequest", "public int OnObjectMenuSelect"))
{
    $surface = Get-BracedSurface $holocron $signature
    $returnIndex = $surface.IndexOf("return SCRIPT_CONTINUE;", [StringComparison]::Ordinal)
    $commentIndex = $surface.IndexOf("/*", [StringComparison]::Ordinal)
    Assert-Contract ($returnIndex -ge 0 -and ($commentIndex -lt 0 -or $returnIndex -lt $commentIndex)) "PGC holocron menu is not fail closed: $signature"
}

foreach ($name in @("chroniclesRewardVendor", "storytellerVendorConversation", "fanFairePgcC3po"))
{
    $body = [string]$texts[$name]
    foreach ($signature in @("public int OnInitialize", "public int OnAttach"))
    {
        $surface = Get-BracedSurface $body $signature
        Assert-Contract ($surface.Contains("detachScript(self,")) "$name does not detach in $signature."
    }
    $menu = Get-BracedSurface $body "public int OnObjectMenuRequest"
    Assert-Contract (-not $menu.Contains("addRootMenu")) "$name still exposes a conversation menu."
    $conversation = Get-BracedSurface $body "public int OnStartNpcConversation"
    $overrideIndex = $conversation.IndexOf("return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
    $startIndex = $conversation.IndexOf("npcStartConversation(", [StringComparison]::Ordinal)
    Assert-Contract ($overrideIndex -ge 0 -and ($startIndex -lt 0 -or $overrideIndex -lt $startIndex)) "$name can still start a conversation."
}

$controller = [string]$texts.storytellerVendorController
foreach ($signature in @("public int msgStorytellerTokenTypeSelected", "public int msgStorytellerTokenPurchaseSelected", "public int msgStorytellerChargesSelected"))
{
    $surface = Get-BracedSurface $controller $signature
    Assert-Contract (-not $surface.Contains("storyteller.")) "Storyteller vendor callback still mutates state: $signature"
}

$callbackRecords = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading ([string]$contract.craftedPrototypeCallbackInventory.pattern) $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') "Invalid OnCraftedPrototype inventory line."
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $callbackRecords.Add($relativePath + ":" + $Matches[2] + "|" + $Matches[3].Trim())
}
$callbackRecords = @($callbackRecords | Sort-Object)
$callbackPaths = @($callbackRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Invalid callback record."
    $Matches[1]
} | Sort-Object -Unique)
$expectedRetained = @($contract.craftedPrototypeCallbackInventory.retainedPaths | ForEach-Object { [string]$_ } | Sort-Object)
$expectedRetired = @($contract.craftedPrototypeCallbackInventory.retiredPaths | ForEach-Object { [string]$_ } | Sort-Object)
$retainedCallbacks = @($callbackRecords | Where-Object {
    $record = $_
    @($expectedRetained | Where-Object { $record.StartsWith($_ + ":") }).Count -eq 1
})
$retiredCallbacks = @($callbackRecords | Where-Object {
    $record = $_
    @($expectedRetired | Where-Object { $record.StartsWith($_ + ":") }).Count -eq 1
})
Assert-Contract (
    $callbackRecords.Count -eq [int]$contract.expected.craftedPrototypeCallbacks -and
    $callbackPaths.Count -eq [int]$contract.craftedPrototypeCallbackInventory.sourceFiles -and
    $retainedCallbacks.Count -eq [int]$contract.expected.retainedCraftCallbacks -and
    $retiredCallbacks.Count -eq [int]$contract.expected.retiredChroniclesCraftCallbacks -and
    (Get-TextSha256 ($callbackRecords -join [Environment]::NewLine)) -ceq [string]$contract.craftedPrototypeCallbackInventory.inventorySha256 -and
    (Get-TextSha256 ($callbackPaths -join [Environment]::NewLine)) -ceq [string]$contract.craftedPrototypeCallbackInventory.sourceSetSha256
) "Complete OnCraftedPrototype inventory drifted."

$locationRecords = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading ([string]$contract.locationArrivalCallbackInventory.pattern) $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') "Invalid OnArrivedAtLocation inventory line."
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $signature = ($Matches[3].Trim() -replace '\s+', ' ')
    $locationRecords.Add($relativePath + ":" + $Matches[2] + "|" + $signature)
}
$locationRecords = @($locationRecords | Sort-Object)
$locationPaths = @($locationRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Invalid location-arrival callback record."
    $Matches[1]
} | Sort-Object -Unique)
$locationProduction = @($locationRecords | Where-Object { $_ -notmatch '^(test|working)/' })
$locationRetired = @($locationProduction | Where-Object {
    $_.StartsWith(([string]$contract.locationArrivalCallbackInventory.retiredPath) + ":")
})
$locationRetained = @($locationProduction | Where-Object {
    -not $_.StartsWith(([string]$contract.locationArrivalCallbackInventory.retiredPath) + ":")
})
$locationNonProduction = @($locationRecords | Where-Object { $_ -match '^(test|working)/' })
$locationNonProductionPaths = @($locationNonProduction | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Invalid non-production location-arrival callback record."
    $Matches[1]
} | Sort-Object -Unique)
$expectedLocationNonProductionPaths = @($contract.locationArrivalCallbackInventory.nonProductionPaths |
    ForEach-Object { [string]$_ } | Sort-Object)
$locationRetainedPaths = @($locationRetained | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Invalid retained location-arrival callback record."
    $Matches[1]
} | Sort-Object -Unique)
$locationSourceContent = @($locationPaths | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scriptRoot $_)).Hash.ToLowerInvariant()
    "$_|$hash"
} | Sort-Object)
$locationRetainedSourceContent = @($locationRetainedPaths | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scriptRoot $_)).Hash.ToLowerInvariant()
    "$_|$hash"
} | Sort-Object)
Assert-Contract (
    $locationRecords.Count -eq [int]$contract.expected.locationArrivalCallbacks -and
    $locationPaths.Count -eq [int]$contract.locationArrivalCallbackInventory.sourceFiles -and
    $locationProduction.Count -eq [int]$contract.expected.locationArrivalProductionCallbacks -and
    $locationRetained.Count -eq [int]$contract.expected.retainedLocationArrivalProductionCallbacks -and
    $locationRetired.Count -eq [int]$contract.expected.retiredChroniclesLocationArrivalCallbacks -and
    $locationNonProduction.Count -eq [int]$contract.expected.locationArrivalNonProductionCallbacks -and
    ($locationNonProductionPaths -join "`n") -ceq ($expectedLocationNonProductionPaths -join "`n") -and
    $locationRetainedPaths.Count -eq [int]$contract.locationArrivalCallbackInventory.retainedProductionSourceFiles -and
    (Get-TextSha256 ($locationRecords -join "`n")) -ceq [string]$contract.locationArrivalCallbackInventory.inventorySha256 -and
    (Get-TextSha256 ($locationPaths -join "`n")) -ceq [string]$contract.locationArrivalCallbackInventory.sourceSetSha256 -and
    (Get-TextSha256 ($locationSourceContent -join "`n")) -ceq [string]$contract.locationArrivalCallbackInventory.sourceContentSha256 -and
    (Get-TextSha256 ($locationRetainedSourceContent -join "`n")) -ceq [string]$contract.locationArrivalCallbackInventory.retainedProductionSourceContentSha256
) "Complete OnArrivedAtLocation inventory or retained production source set drifted."

$activityRecords = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading ([string]$contract.activityCompletionCallbackInventory.pattern) $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') "Invalid PGC activity/completion inventory line."
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $signature = ($Matches[3].Trim() -replace '\s+', ' ')
    $activityRecords.Add($relativePath + ":" + $Matches[2] + "|" + $signature)
}
$activityRecords = @($activityRecords | Sort-Object)
$activityPaths = @($activityRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Invalid activity/completion callback record."
    $Matches[1]
} | Sort-Object -Unique)
$activityProduction = @($activityRecords | Where-Object { $_ -notmatch '^(test|working)/' })
$activityRetiredPaths = @($contract.activityCompletionCallbackInventory.retiredPaths |
    ForEach-Object { [string]$_ } | Sort-Object)
$activityRetired = @($activityProduction | Where-Object {
    $record = $_
    @($activityRetiredPaths | Where-Object { $record.StartsWith($_ + ":") }).Count -eq 1
})
$activityRetained = @($activityProduction | Where-Object {
    $record = $_
    @($activityRetiredPaths | Where-Object { $record.StartsWith($_ + ":") }).Count -eq 0
})
$activityNonProduction = @($activityRecords | Where-Object { $_ -match '^(test|working)/' })
$activityNonProductionPaths = @($activityNonProduction | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Invalid non-production activity/completion callback record."
    $Matches[1]
} | Sort-Object -Unique)
$expectedActivityNonProductionPaths = @($contract.activityCompletionCallbackInventory.nonProductionPaths |
    ForEach-Object { [string]$_ } | Sort-Object)
$activityRetainedPaths = @($activityRetained | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') "Invalid retained activity/completion callback record."
    $Matches[1]
} | Sort-Object -Unique)
$activitySourceContent = @($activityPaths | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scriptRoot $_)).Hash.ToLowerInvariant()
    "$_|$hash"
} | Sort-Object)
$activityRetainedSourceContent = @($activityRetainedPaths | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scriptRoot $_)).Hash.ToLowerInvariant()
    "$_|$hash"
} | Sort-Object)
Assert-Contract (
    $activityRecords.Count -eq [int]$contract.expected.activityCompletionCallbacks -and
    $activityPaths.Count -eq [int]$contract.activityCompletionCallbackInventory.sourceFiles -and
    $activityProduction.Count -eq [int]$contract.expected.activityCompletionProductionCallbacks -and
    $activityRetained.Count -eq [int]$contract.expected.retainedActivityCompletionProductionCallbacks -and
    $activityRetired.Count -eq [int]$contract.expected.retiredChroniclesActivityCompletionCallbacks -and
    $activityNonProduction.Count -eq [int]$contract.expected.activityCompletionNonProductionCallbacks -and
    ($activityNonProductionPaths -join "`n") -ceq ($expectedActivityNonProductionPaths -join "`n") -and
    $activityRetainedPaths.Count -eq [int]$contract.activityCompletionCallbackInventory.retainedProductionSourceFiles -and
    (Get-TextSha256 ($activityRecords -join "`n")) -ceq [string]$contract.activityCompletionCallbackInventory.inventorySha256 -and
    (Get-TextSha256 ($activityPaths -join "`n")) -ceq [string]$contract.activityCompletionCallbackInventory.sourceSetSha256 -and
    (Get-TextSha256 ($activitySourceContent -join "`n")) -ceq [string]$contract.activityCompletionCallbackInventory.sourceContentSha256 -and
    (Get-TextSha256 ($activityRetainedSourceContent -join "`n")) -ceq [string]$contract.activityCompletionCallbackInventory.retainedProductionSourceContentSha256
) "Complete PGC activity/completion inventory or retained production source set drifted."

$sagaCraft = Get-BracedSurface $saga "public int OnCraftedPrototype"
$sagaGuard = $sagaCraft.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
$sagaMutation = $sagaCraft.IndexOf("pgc_quests.getActivateQuestHolocrons(", [StringComparison]::Ordinal)
Assert-Contract (
    $sagaGuard -ge 0 -and $sagaMutation -gt $sagaGuard -and
    $sagaCraft.Contains("pgc_quests.retireChroniclesPlayerProgressionState(self);") -and
    $sagaCraft.Contains('detachScript(self, "player.player_saga_quest");') -and
    $sagaCraft.Substring($sagaGuard, $sagaMutation - $sagaGuard).Contains("return SCRIPT_CONTINUE;")
) "Player-saga crafted-prototype mutation is not dominated by retirement."

$holocronCraft = Get-BracedSurface $holocron "public int OnCraftedPrototype"
$holocronGuard = $holocronCraft.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
$holocronMutation = $holocronCraft.IndexOf("pgc_quests.incrementTaskCounter(", [StringComparison]::Ordinal)
Assert-Contract (
    $holocronGuard -ge 0 -and $holocronMutation -gt $holocronGuard -and
    $holocronCraft.Contains("pgc_quests.retireChroniclesPlayerProgressionState(player);") -and
    $holocronCraft.Contains('detachScript(self, "quest.task.pgc.quest_holocron");') -and
    $holocronCraft.Substring($holocronGuard, $holocronMutation - $holocronGuard).Contains("return SCRIPT_CONTINUE;") -and
    [int]$contract.expected.unguardedRetiredCraftMutations -eq 0
) "PGC holocron crafted-prototype mutation is not dominated by retirement."

$sagaArrival = Get-BracedSurface $saga "public int OnArrivedAtLocation"
$sagaArrivalGuard = $sagaArrival.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
$sagaArrivalMutation = $sagaArrival.IndexOf("pgc_quests.getActivateQuestHolocrons(", [StringComparison]::Ordinal)
Assert-Contract (
    $sagaArrivalGuard -ge 0 -and $sagaArrivalMutation -gt $sagaArrivalGuard -and
    $sagaArrival.Contains("pgc_quests.retireChroniclesPlayerProgressionState(self);") -and
    $sagaArrival.Contains('detachScript(self, "player.player_saga_quest");') -and
    $sagaArrival.Substring($sagaArrivalGuard, $sagaArrivalMutation - $sagaArrivalGuard).Contains("return SCRIPT_CONTINUE;")
) "Player-saga location-arrival mutation is not dominated by retirement."

$holocronArrival = Get-BracedSurface $holocron "public int pqOnArrivedAtLocation"
$holocronArrivalGuard = $holocronArrival.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
$holocronArrivalMutation = $holocronArrival.IndexOf("pgc_quests.setTaskComplete(", [StringComparison]::Ordinal)
Assert-Contract (
    $holocronArrivalGuard -ge 0 -and $holocronArrivalMutation -gt $holocronArrivalGuard -and
    $holocronArrival.Contains("pgc_quests.retireChroniclesPlayerProgressionState(player);") -and
    $holocronArrival.Contains('detachScript(self, "quest.task.pgc.quest_holocron");') -and
    $holocronArrival.Substring($holocronArrivalGuard, $holocronArrivalMutation - $holocronArrivalGuard).Contains("return SCRIPT_CONTINUE;") -and
    [int]$contract.expected.unguardedRetiredLocationArrivalMutations -eq 0
) "PGC holocron location-arrival mutation is not dominated by retirement."

$sagaActivityMethods = @(
    "receiveCreditForKill",
    "recivedGcwCreditForKill",
    "startPerform",
    "stopPerform"
)
Assert-Contract ($sagaActivityMethods.Count -eq [int]$contract.expected.playerSagaActivityRelays) `
    "Player-saga activity relay inventory drifted."
foreach ($method in $sagaActivityMethods)
{
    $surface = Get-BracedSurface $saga ("public int " + $method)
    $guard = $surface.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
    $mutation = $surface.IndexOf("messageTo(questHolocron,", [StringComparison]::Ordinal)
    Assert-Contract (
        $guard -ge 0 -and $mutation -gt $guard -and
        $surface.Contains("pgc_quests.retireChroniclesPlayerProgressionState(self);") -and
        $surface.Contains('detachScript(self, "player.player_saga_quest");') -and
        $surface.Substring($guard, $mutation - $guard).Contains("return SCRIPT_CONTINUE;")
    ) "Player-saga activity relay is not dominated by retirement: $method"
}

$holocronActivityMethods = [ordered]@{
    receiveCreditForKill = "pgc_quests.checkForKillTaskCredit("
    recivedGcwCreditForKill = "pgc_quests.handlePvpPlayerKillCredit("
    handleCommMessageTaskCompletion = "pgc_quests.setTaskComplete("
    ChroniclesMessageBoxCompleted = "pgc_quests.setTaskComplete("
    startPerform = "utils.setScriptVar("
    stopPerform = "clearPerformScriptVars("
    CheckPerformanceComplete = "pgc_quests.setTaskComplete("
}
Assert-Contract ($holocronActivityMethods.Count -eq [int]$contract.expected.questHolocronActivityCompletionCallbacks) `
    "PGC holocron activity/completion method inventory drifted."
foreach ($entry in $holocronActivityMethods.GetEnumerator())
{
    $surface = Get-BracedSurface $holocron ("public int " + $entry.Key)
    $guard = $surface.IndexOf("if (pgc_quests.isRetiredChroniclesPlayerProgression())", [StringComparison]::Ordinal)
    $mutation = $surface.IndexOf([string]$entry.Value, [StringComparison]::Ordinal)
    Assert-Contract (
        $guard -ge 0 -and $mutation -gt $guard -and
        $surface.Contains("pgc_quests.retireChroniclesPlayerProgressionState(player);") -and
        $surface.Contains('detachScript(self, "quest.task.pgc.quest_holocron");') -and
        $surface.Substring($guard, $mutation - $guard).Contains("return SCRIPT_CONTINUE;") -and
        [int]$contract.expected.unguardedRetiredActivityCompletionMutations -eq 0
    ) "PGC holocron activity/completion mutation is not dominated by retirement: $($entry.Key)"
}

$legacyCraft = Get-BracedSurface ([string]$texts.legacyCraft) "public int OnCraftedPrototype"
$groundCraft = Get-BracedSurface ([string]$texts.groundCraft) "public int OnCraftedPrototype"
Assert-Contract (
    $legacyCraft.Contains("quests.complete(") -and
    $groundCraft.Contains("questCompleteTask(") -and
    [bool]$contract.expected.legacyQuestCraftCompletionPreserved -and
    [bool]$contract.expected.groundQuestCraftCompletionPreserved
) "Normal quest-crafting completion authority drifted."

$nativeRegistrationCount = [regex]::Matches([string]$texts.scriptFunctionTable, '\{Scripting::TRIG_CRAFTED_PROTOTYPE,\s*"OnCraftedPrototype",\s*"OD"\}').Count
$nativeDispatcherCount = [regex]::Matches([string]$texts.playerObject, 'trigAllScripts\(Scripting::TRIG_CRAFTED_PROTOTYPE,\s*craftparams\)').Count
$nativeLocationArrivalRegistrationCount = [regex]::Matches([string]$texts.scriptFunctionTable, '\{Scripting::TRIG_ARRIVE_AT_LOCATION,\s*"OnArrivedAtLocation",\s*"u"\}').Count
Assert-Contract (
    $nativeRegistrationCount -eq [int]$contract.expected.nativeCraftedPrototypeRegistrations -and
    $nativeDispatcherCount -eq [int]$contract.expected.nativeCraftedPrototypeDispatchers -and
    $nativeLocationArrivalRegistrationCount -eq [int]$contract.expected.nativeLocationArrivalRegistrations
) "Native crafted-prototype or location-arrival registration/dispatcher boundary drifted."

$chroniclesPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14ChroniclesScriptLifecycleRetirement)
$chroniclesContract = Get-Content -LiteralPath $chroniclesPath -Raw | ConvertFrom-Json
$eligibleChroniclesStates = if ($Expectation -ceq "Ready") { @("ready") } else { @("implemented-build-pending", "ready") }
Assert-Contract (
    $eligibleChroniclesStates -contains [string]$chroniclesContract.status -and
    [bool]$contract.expected.chroniclesLifecycleDependencyBuildEligible
) "Chronicles lifecycle dependency is not build eligible."

$obsoletePatch = Join-Path $restorationRoot "patches/dsrc/168-p14-pgc-holocron-vendor-retirement.patch"
Assert-Contract (
    -not (Test-Path -LiteralPath $obsoletePatch) -and
    [int]$contract.expected.obsoleteOverlayPatchFiles -eq 0
) "Obsolete PGC overlay patch still exists."

if ($Expectation -ceq "Ready")
{
    Assert-Contract (
        [string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        [bool]$contract.runtimeEvidence.clientResponsive -and
        [int]$contract.runtimeEvidence.hostArtifactOrStagingDirectories -eq 0 -and
        @($contract.requiredBeforeReady).Count -eq 0
    ) "PGC retirement lacks complete Ready evidence."

    $container = [string]$contract.runtimeEvidence.container
    $health = (& docker inspect $container --format '{{.State.Health.Status}}').Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $health -ceq "healthy") "PGC runtime container is not healthy."
    foreach ($property in $contract.sourceFiles.PSObject.Properties)
    {
        $relativePath = ([string]$property.Value).Replace("\", "/")
        & docker exec $container cmp -s "/swg-precu-source/$relativePath" "/swg-precu/$relativePath"
        Assert-Contract ($LASTEXITCODE -eq 0) "PGC source/work parity failed: $($property.Name)"
    }

    $classPaths = [ordered]@{
        playerSaga = "/swg-precu/data/sku.0/sys.server/compiled/game/script/player/player_saga_quest.class"
        questHolocron = "/swg-precu/data/sku.0/sys.server/compiled/game/script/quest/task/pgc/quest_holocron.class"
        legacyCraft = "/swg-precu/data/sku.0/sys.server/compiled/game/script/quest/task/craft.class"
        groundCraft = "/swg-precu/data/sku.0/sys.server/compiled/game/script/quest/task/ground/craft.class"
        pgcQuests = "/swg-precu/data/sku.0/sys.server/compiled/game/script/library/pgc_quests.class"
        loot = "/swg-precu/data/sku.0/sys.server/compiled/game/script/library/loot.class"
        gcw = "/swg-precu/data/sku.0/sys.server/compiled/game/script/library/gcw.class"
        baseTool = "/swg-precu/data/sku.0/sys.server/compiled/game/script/systems/crafting/base_tool.class"
        consumeFragment = "/swg-precu/data/sku.0/sys.server/compiled/game/script/systems/player_quest/consume_fragment.class"
        consumeRelic = "/swg-precu/data/sku.0/sys.server/compiled/game/script/systems/player_quest/consume_relic.class"
        questControlDevice = "/swg-precu/data/sku.0/sys.server/compiled/game/script/quest/task/pgc/quest_control_device.class"
        creditItem = "/swg-precu/data/sku.0/sys.server/compiled/game/script/quest/task/pgc/credit_item.class"
        chroniclesRewardVendor = "/swg-precu/data/sku.0/sys.server/compiled/game/script/conversation/chronicles_reward_vendor.class"
        storytellerVendorConversation = "/swg-precu/data/sku.0/sys.server/compiled/game/script/conversation/storyteller_vendor.class"
        fanFairePgcC3po = "/swg-precu/data/sku.0/sys.server/compiled/game/script/conversation/fan_faire_pgc_c3po.class"
        storytellerVendorController = "/swg-precu/data/sku.0/sys.server/compiled/game/script/systems/storyteller/storyteller_vendor.class"
    }
    foreach ($name in $classPaths.Keys)
    {
        $hash = ((& docker exec $container sha256sum $classPaths[$name]).Trim() -split '\s+')[0]
        $bytes = [int]((& docker exec $container stat -c '%s' $classPaths[$name]).Trim())
        Assert-Contract (
            $hash -ceq [string]$contract.buildEvidence.classSha256.PSObject.Properties[$name].Value -and
            $bytes -eq [int]$contract.buildEvidence.classBytes.PSObject.Properties[$name].Value
        ) "PGC deployed bytecode drifted: $name"
    }

    $serverPid = (& docker exec $container pgrep -n SwgGameServer).Trim()
    $serverExe = (& docker exec $container readlink -f "/proc/$serverPid/exe").Trim()
    $binaryHash = ((& docker exec $container sha256sum $serverExe).Trim() -split '\s+')[0]
    $buildLine = @(& docker exec $container readelf -n $serverExe | Select-String 'Build ID:')
    $buildId = ($buildLine[0].Line -replace '^.*Build ID:\s*', '').Trim()
    Assert-Contract (
        $binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $buildId -ceq [string]$contract.buildEvidence.serverBinaryBuildId
    ) "PGC deployed server binary drifted."

    $client = Get-Process -Id ([int]$contract.runtimeEvidence.clientProcessId) -ErrorAction SilentlyContinue
    Assert-Contract (
        $null -ne $client -and $client.Responding -and
        $client.ProcessName -ceq [string]$contract.runtimeEvidence.clientProcessName
    ) "PGC client is not responsive."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) "PGC source status is invalid."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (
    -not $contractText.Contains("overlayPatch") -and
    -not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")
) "PGC contract references retired artifact/staging evidence."
Write-Host "Publish 14.1 PGC holocron/vendor and complete player-saga/quest-holocron callback retirement passed."
