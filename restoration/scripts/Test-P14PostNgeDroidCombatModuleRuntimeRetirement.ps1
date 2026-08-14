[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Source", "Ready")][string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgeDroidCombatModuleRuntimeRetirement)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$sharedTableRoot = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables"
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
    try
    {
        return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

function Get-QuotedNames([string]$Text)
{
    return @([regex]::Matches($Text, '"([a-z0-9_]+)"') |
        ForEach-Object { $_.Groups[1].Value })
}

function Get-TableNames([string]$Path)
{
    return @(Get-Content -LiteralPath $Path | Select-Object -Skip 2 |
        ForEach-Object {
            if ($_ -ne "") { ($_ -split "`t", 2)[0].Trim('"') }
        } | Where-Object { $_ -ne "" })
}

$sourceMap = [ordered]@{
    "library/pet_lib.java" = Join-Path $scriptRoot "library/pet_lib.java"
    "systems/combat/combat_base.java" = Join-Path $scriptRoot "systems/combat/combat_base.java"
    "player/base/base_player.java" = Join-Path $scriptRoot "player/base/base_player.java"
    "systems/combat/combat_actions.java" = Join-Path $scriptRoot "systems/combat/combat_actions.java"
    "command/command_table.tab" = Join-Path $sharedTableRoot "command/command_table.tab"
    "combat/combat_data.tab" = Join-Path $sharedTableRoot "combat/combat_data.tab"
    "buff/buff.tab" = Join-Path $sharedTableRoot "buff/buff.tab"
}
Assert-Contract ($sourceMap.Count -eq [int]$contract.expected.authoritativeSourceFiles) `
    "p14.droid-module.authoritative-source-count"
foreach ($entry in $sourceMap.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.droid-module.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $entry.Value -PathType Leaf)
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        Assert-Contract ($actual -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
            "p14.droid-module.source.$($entry.Key).authenticated"
    }
}

$droidProgrammingRecords = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading ([string]$contract.inventory.pattern) $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
        "p14.droid-module.programming-callback.inventory-line-parsed"
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    Assert-Contract ($absolutePath.StartsWith(
        $scriptRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) `
        "p14.droid-module.programming-callback.inventory-contained"
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $droidProgrammingRecords.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
}
$droidProgrammingRecords = @($droidProgrammingRecords | Sort-Object)
$droidProgrammingPaths = @($droidProgrammingRecords | ForEach-Object {
    Assert-Contract ($_ -match '^(.*?):\d+\|') `
        "p14.droid-module.programming-callback.path-isolated"
    $Matches[1]
} | Sort-Object -Unique)
$expectedDroidProgrammingPaths = @($contract.inventory.sourcePaths | ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract ($droidProgrammingRecords.Count -eq [int]$contract.inventory.handlers -and
    $droidProgrammingRecords.Count -eq [int]$contract.expected.droidProgrammingCallbacks -and
    $droidProgrammingPaths.Count -eq [int]$contract.inventory.sourceFiles -and
    ($droidProgrammingPaths -join "`n") -ceq ($expectedDroidProgrammingPaths -join "`n") -and
    (Get-TextSha256 ($droidProgrammingRecords -join "`n")) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 ($droidProgrammingPaths -join "`n")) -ceq [string]$contract.inventory.sourceSetSha256) `
    "p14.droid-module.programming-callback.complete-inventory"

$supportingPaths = [ordered]@{
    "space/combat/combat_ship_player.java" = Join-Path $scriptRoot "space/combat/combat_ship_player.java"
    "test/esebesta_test.java" = Join-Path $scriptRoot "test/esebesta_test.java"
    "player/live_conversions.java" = Join-Path $scriptRoot "player/live_conversions.java"
}
$supportingTexts = @{}
foreach ($entry in $supportingPaths.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.droid-module.supporting-source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $entry.Value -PathType Leaf)
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        Assert-Contract ($actual -ceq [string]$contract.buildEvidence.supportingSourceSha256.($entry.Key)) `
            "p14.droid-module.supporting-source.$($entry.Key).authenticated"
        $supportingTexts[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
    }
}

$shipPlayer = [string]$supportingTexts["space/combat/combat_ship_player.java"]
$developerTest = [string]$supportingTexts["test/esebesta_test.java"]
$liveConversions = [string]$supportingTexts["player/live_conversions.java"]
$productionProgramming = Get-SourceSlice $shipPlayer `
    "public int OnCommitDroidProgramCommands(" `
    "public int commandTimerTimeout("
$developerProgramming = Get-SourceSlice $developerTest `
    "public int OnCommitDroidProgramCommands(" `
    "public int __missing_after_last_method("
$developerAttach = Get-SourceSlice $developerTest `
    "public int OnAttach(" `
    "public int OnFormCreateObject("
$groundCombatPatterns = @(
    '\bpet_lib\.', '\bcombatStandardAction\s*\(', '\bbuff\.apply',
    '\bgrantCommand\s*\(', '\bgrantSkill\s*\(', '\bsetLevel\s*\('
)
$groundCombatMatches = @($groundCombatPatterns | Where-Object {
    [regex]::IsMatch($productionProgramming, $_)
})
$jtlModuleWrites = [regex]::Matches($productionProgramming,
    'space_combat\.(destroyObject|addModuleToDatapad)\s*\(').Count
Assert-Contract ([int]$contract.inventory.productionJtlHandlers -eq
        [int]$contract.expected.droidProgrammingProductionJtlCallbacks -and
    [int]$contract.inventory.guardedDeveloperHandlers -eq
        [int]$contract.expected.droidProgrammingGuardedDeveloperCallbacks -and
    $productionProgramming.Contains("utils.getDatapad(objControlDevice)") -and
    $productionProgramming.Contains("getVolumeFree(objDatapad)") -and
    $jtlModuleWrites -eq [int]$contract.expected.droidProgrammingJtlModuleWrites -and
    $groundCombatMatches.Count -eq [int]$contract.expected.droidProgrammingGroundCombatMutations -and
    $liveConversions.Contains('attachScript(player, "space.combat.combat_ship_player")') -and
    $developerProgramming.Contains('debugSpeakMsg(self, "OnCommitDroidProgramCommands hit")') -and
    $developerAttach.Contains("!isGod(self) || getGodLevel(self) < 50 || !isPlayer(self)") -and
    [regex]::Matches($developerAttach, 'detachScript\(self, "test\.esebesta_test"\)').Count -eq
        [int]$contract.expected.developerDroidProgrammingSelfDetachGuards -and
    [bool]$contract.expected.precuJtlDroidProgrammingPreserved) `
    "p14.droid-module.programming-callback.jtl-preserved-ground-authority-isolated"

$playerActions = @(
    "droid_flame_jet_1", "droid_flame_jet_2", "droid_flame_jet_3",
    "droid_droideka_shield_1", "droid_droideka_shield_2", "droid_droideka_shield_3",
    "droid_battery_dump_1", "droid_battery_dump_2", "droid_battery_dump_3",
    "droid_regenerative_plating_1", "droid_regenerative_plating_2", "droid_regenerative_plating_3",
    "droid_electrical_shock_1", "droid_electrical_shock_2", "droid_electrical_shock_3",
    "droid_torturous_needle_1", "droid_torturous_needle_2", "droid_torturous_needle_3"
)
$serverActions = @(
    "server_droid_flame_jet_1", "server_droid_flame_jet_2", "server_droid_flame_jet_3",
    "server_droid_battery_dump_1", "server_droid_battery_dump_2", "server_droid_battery_dump_3",
    "server_droid_regenerative_plating_1", "server_droid_regenerative_plating_2", "server_droid_regenerative_plating_3",
    "server_droid_electrical_shock_1", "server_droid_electrical_shock_2", "server_droid_electrical_shock_3",
    "server_droid_torturous_needle_1", "server_droid_torturous_needle_2", "server_droid_torturous_needle_3"
)
$retiredBuffs = @("droideka_shield_1", "droideka_shield_2", "droideka_shield_3")
$classicCommands = @(
    "droid_follow", "droid_follow_other", "droid_stay", "droid_store", "droid_transfer",
    "droid_trick_1", "droid_trick_2", "droid_trick_3", "droid_trick_4", "droid_group",
    "droid_patrol_clear", "droid_patrol", "droid_patrol_point", "droid_friend", "droid_guard", "droid_attack"
)
$pet = Get-Content -LiteralPath $sourceMap["library/pet_lib.java"] -Raw
$combatBase = Get-Content -LiteralPath $sourceMap["systems/combat/combat_base.java"] -Raw
$basePlayer = Get-Content -LiteralPath $sourceMap["player/base/base_player.java"] -Raw
$combatActions = Get-Content -LiteralPath $sourceMap["systems/combat/combat_actions.java"] -Raw

$playerInventory = Get-SourceSlice $pet `
    "public static final String[] RETIRED_POST_NGE_DROID_COMBAT_MODULE_PLAYER_ACTIONS" `
    "public static final String[] RETIRED_POST_NGE_DROID_COMBAT_MODULE_SERVER_ACTIONS"
$serverInventory = Get-SourceSlice $pet `
    "public static final String[] RETIRED_POST_NGE_DROID_COMBAT_MODULE_SERVER_ACTIONS" `
    "public static final String[] RETIRED_POST_NGE_DROID_COMBAT_MODULE_BUFFS"
$buffInventory = Get-SourceSlice $pet `
    "public static final String[] RETIRED_POST_NGE_DROID_COMBAT_MODULE_BUFFS" `
    "public static final string_id SID_SYS_CANT_TAME"
$sourcePlayerActions = @(Get-QuotedNames $playerInventory)
$sourceServerActions = @(Get-QuotedNames $serverInventory)
$sourceBuffs = @(Get-QuotedNames $buffInventory)
Assert-Contract ($sourcePlayerActions.Count -eq [int]$contract.expected.retiredPlayerActions -and
    @(Compare-Object $sourcePlayerActions $playerActions).Count -eq 0) "p14.droid-module.player-action-inventory"
Assert-Contract ($sourceServerActions.Count -eq [int]$contract.expected.retiredServerActions -and
    @(Compare-Object $sourceServerActions $serverActions).Count -eq 0) "p14.droid-module.server-action-inventory"
Assert-Contract ($sourceBuffs.Count -eq [int]$contract.expected.retiredPersistentBuffs -and
    @(Compare-Object $sourceBuffs $retiredBuffs).Count -eq 0) "p14.droid-module.buff-inventory"

$validate = Get-SourceSlice $pet "public static obj_id validateDroidCommand" `
    "public static boolean isRetiredPostNgeDroidCombatModuleAction"
$predicate = Get-SourceSlice $pet "public static boolean isRetiredPostNgeDroidCombatModuleAction" `
    "public static void retirePostNgeDroidCombatModuleState"
$cleanup = Get-SourceSlice $pet "public static void retirePostNgeDroidCombatModuleState" "`n}"
Assert-Contract ($validate.Contains("if (isIdValid(player) && isPlayer(player))") -and
    $validate.Contains("retirePostNgeDroidCombatModuleState(player);") -and
    $validate.IndexOf("return null;", [StringComparison]::Ordinal) -lt
        $validate.IndexOf("callable.getCallable", [StringComparison]::Ordinal)) `
    "p14.droid-module.direct-player-command-fails-closed"
Assert-Contract ($predicate.Contains("if (isPlayer(actor))") -and
    $predicate.Contains("obj_id master = getMaster(actor);") -and
    $predicate.Contains("isPlayer(master)") -and
    $predicate.Contains("return false;")) "p14.droid-module.player-owned-boundary"
Assert-Contract ($cleanup.Contains("while (hasCommand(player, retiredAction))") -and
    $cleanup.Contains("revokeCommand(player, retiredAction);") -and
    $cleanup.Contains("callable.getCallable(player, callable.CALLABLE_TYPE_COMBAT_PET)") -and
    $cleanup.Contains("buff.removeBuff(droid, retiredBuff);")) "p14.droid-module.persisted-state-cleanup"

$wrapperCount = 0
foreach ($action in $playerActions)
{
    $method = Get-SourceSlice $combatActions ("public int " + $action + "(") "public int "
    if ($method.Contains("pet_lib.validateDroidCommand(self)")) { $wrapperCount++ }
}
Assert-Contract ($wrapperCount -eq [int]$contract.expected.directPlayerWrappers -and
    ([regex]::Matches($combatActions, 'pet_lib\.validateDroidCommand\(self\)')).Count -eq $wrapperCount) `
    "p14.droid-module.all-direct-wrappers-centralized"

$standardAction = Get-SourceSlice $combatBase `
    "public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)" `
    "public boolean doCombatPreCheck"
$droidGuard = $standardAction.IndexOf("pet_lib.isRetiredPostNgeDroidCombatModuleAction", [StringComparison]::Ordinal)
$laterGuard = $standardAction.IndexOf("isRetiredPostNgeSpeciesPlayerAction", [StringComparison]::Ordinal)
Assert-Contract ($droidGuard -ge 0 -and $droidGuard -lt $laterGuard -and
    $standardAction.Contains("pet_lib.retirePostNgeDroidCombatModuleState(player);") -and
    $standardAction.Contains("return false;")) "p14.droid-module.queued-server-action-fails-closed"
$lifecycle = Get-SourceSlice $basePlayer "private void retirePostNgePassiveProfessionState" `
    "private void retirePostNgeQueuedBattlefieldPlayerState"
Assert-Contract ($lifecycle.Contains("pet_lib.retirePostNgeDroidCombatModuleState(self);")) `
    "p14.droid-module.player-lifecycle-cleanup"

$commandNames = @(Get-TableNames $sourceMap["command/command_table.tab"])
$combatNames = @(Get-TableNames $sourceMap["combat/combat_data.tab"])
$buffNames = @(Get-TableNames $sourceMap["buff/buff.tab"])
$specialActions = @($playerActions + $serverActions)
Assert-Contract (@($commandNames | Where-Object { $specialActions -ccontains $_ }).Count -eq
    [int]$contract.expected.retainedCommandRows) "p14.droid-module.command-data-preserved"
Assert-Contract (@($combatNames | Where-Object { $specialActions -ccontains $_ }).Count -eq
    [int]$contract.expected.retainedCombatRows) "p14.droid-module.combat-data-preserved"
Assert-Contract (@($buffNames | Where-Object { $retiredBuffs -ccontains $_ }).Count -eq
    [int]$contract.expected.retainedShieldBuffRows) "p14.droid-module.buff-data-preserved"
Assert-Contract (@($commandNames | Where-Object { $classicCommands -ccontains $_ }).Count -eq
    [int]$contract.expected.classicDroidCommands) "p14.droid-module.classic-controls-preserved"
Assert-Contract (@($commandNames | Where-Object { $_ -ceq "detonateDroid" }).Count -eq
    [int]$contract.expected.detonateDroidRows -and
    -not ($playerActions + $serverActions -ccontains "detonateDroid")) "p14.droid-module.detonation-preserved"

$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($dsrcPin.Count -eq 1 -and [string]$dsrcPin[0].commit -ceq
    [string]$contract.buildEvidence.directSourceCommit) "p14.droid-module.direct-source-pin"
Assert-Contract (@("source-ready", "ready") -ccontains [string]$contract.status) `
    "p14.droid-module.contract-status"
if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        $contract.requiredBeforeReady.Count -eq 0) "p14.droid-module.ready-evidence"
}
if ($failures.Count -gt 0)
{
    throw "Publish 14.1 post-NGE droid combat-module retirement contract failed: $($failures -join ', ')"
}
Write-Host "Publish 14.1 post-NGE droid combat-module runtime retirement contract passed."
