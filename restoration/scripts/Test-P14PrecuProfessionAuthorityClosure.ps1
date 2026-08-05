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
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuProfessionAuthorityClosure)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
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

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

function Get-SourceText([string]$RelativePath)
{
    return Get-Content -LiteralPath (Join-Path $dsrc $RelativePath) -Raw
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.profession-closure.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.profession-closure.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    (@($targets | Select-Object -Unique).Count -eq $targets.Count)) `
    "p14.profession-closure.overlay.target-set"
$targetSetText = ($targets -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $targetSetText) -ceq [string]$contract.buildEvidence.sourceSetSha256) `
    "p14.profession-closure.source-set.authenticated"

$contentRecords = [System.Collections.Generic.List[string]]::new()
$changedTextBuilder = [System.Text.StringBuilder]::new()
foreach ($target in $targets)
{
    $path = Join-Path $dsrc $target
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.profession-closure.source.$target.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $contentRecords.Add("$target=$hash")
        [void]$changedTextBuilder.AppendLine((Get-Content -LiteralPath $path -Raw))
    }
}
$contentRecordText = ($contentRecords -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $contentRecordText) -ceq [string]$contract.buildEvidence.sourceContentSha256) `
    "p14.profession-closure.source-content.authenticated"
$changedText = $changedTextBuilder.ToString()

$officerRuntimeSources = [ordered]@{
    "sku.0/sys.server/compiled/game/script/ai/officer_pet.java" = "ai/officer_pet.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java" = "systems/combat/combat_base.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java" = "systems/combat/combat_actions.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_supply_drop_controller.java" = "systems/combat/combat_supply_drop_controller.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_supply_drop_crate.java" = "systems/combat/combat_supply_drop_crate.java"
}
Assert-Contract ($officerRuntimeSources.Count -eq [int]$contract.expected.authoritativeOfficerRuntimeFiles -and
    @($contract.buildEvidence.officerRuntimeSourceSha256.PSObject.Properties).Count -eq
        $officerRuntimeSources.Count) `
    "p14.profession-closure.officer-runtime.source-count"
$officerTexts = [ordered]@{}
foreach ($property in $contract.buildEvidence.officerRuntimeSourceSha256.PSObject.Properties)
{
    $path = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        $officerRuntimeSources.Contains($property.Name) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) `
        "p14.profession-closure.officer-runtime.source.$($property.Name).authenticated"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $officerTexts[$officerRuntimeSources[$property.Name]] = Get-Content -LiteralPath $path -Raw
    }
}

$forceSensitiveRuntimeSources = [ordered]@{
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java" =
        "systems/combat/combat_base.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java" =
        "systems/combat/combat_actions.java"
    "sku.0/sys.server/compiled/game/script/library/buff.java" =
        "library/buff.java"
    "sku.0/sys.server/compiled/game/script/systems/buff/buff_handler.java" =
        "systems/buff/buff_handler.java"
    "sku.0/sys.server/compiled/game/script/player/base/base_player.java" =
        "player/base/base_player.java"
}
Assert-Contract ($forceSensitiveRuntimeSources.Count -eq
        [int]$contract.expected.authoritativeForceSensitiveRuntimeFiles -and
    @($contract.buildEvidence.forceSensitiveRuntimeSourceSha256.PSObject.Properties).Count -eq
        $forceSensitiveRuntimeSources.Count) `
    "p14.profession-closure.force-sensitive-runtime.source-count"
$forceSensitiveTexts = [ordered]@{}
foreach ($property in $contract.buildEvidence.forceSensitiveRuntimeSourceSha256.PSObject.Properties)
{
    $path = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        $forceSensitiveRuntimeSources.Contains($property.Name) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) `
        "p14.profession-closure.force-sensitive-runtime.source.$($property.Name).authenticated"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $forceSensitiveTexts[$forceSensitiveRuntimeSources[$property.Name]] =
            Get-Content -LiteralPath $path -Raw
    }
}

$smugglerRuntimeSources = [ordered]@{
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java" =
        "systems/combat/combat_base.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java" =
        "systems/combat/combat_actions.java"
}
Assert-Contract ($smugglerRuntimeSources.Count -eq
        [int]$contract.expected.authoritativeSmugglerRuntimeFiles -and
    @($contract.buildEvidence.smugglerRuntimeSourceSha256.PSObject.Properties).Count -eq
        $smugglerRuntimeSources.Count) `
    "p14.profession-closure.smuggler-runtime.source-count"
foreach ($property in $contract.buildEvidence.smugglerRuntimeSourceSha256.PSObject.Properties)
{
    $path = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        $smugglerRuntimeSources.Contains($property.Name) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) `
        "p14.profession-closure.smuggler-runtime.source.$($property.Name).authenticated"
}

$bountyHunterRuntimeSources = [ordered]@{
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java" =
        "systems/combat/combat_base.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java" =
        "systems/combat/combat_actions.java"
    "sku.0/sys.server/compiled/game/script/library/buff.java" =
        "library/buff.java"
    "sku.0/sys.server/compiled/game/script/systems/buff/buff_handler.java" =
        "systems/buff/buff_handler.java"
    "sku.0/sys.server/compiled/game/script/player/skill/bh_shields.java" =
        "player/skill/bh_shields.java"
}
Assert-Contract ($bountyHunterRuntimeSources.Count -eq
        [int]$contract.expected.authoritativeBountyHunterRuntimeFiles -and
    @($contract.buildEvidence.bountyHunterRuntimeSourceSha256.PSObject.Properties).Count -eq
        $bountyHunterRuntimeSources.Count) `
    "p14.profession-closure.bounty-hunter-runtime.source-count"
$bountyHunterTexts = [ordered]@{}
foreach ($property in $contract.buildEvidence.bountyHunterRuntimeSourceSha256.PSObject.Properties)
{
    $path = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        $bountyHunterRuntimeSources.Contains($property.Name) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) `
        "p14.profession-closure.bounty-hunter-runtime.source.$($property.Name).authenticated"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $bountyHunterTexts[$bountyHunterRuntimeSources[$property.Name]] =
            Get-Content -LiteralPath $path -Raw
    }
}

$commandoRuntimeSources = [ordered]@{
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java" =
        "systems/combat/combat_base.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java" =
        "systems/combat/combat_actions.java"
}
Assert-Contract ($commandoRuntimeSources.Count -eq
        [int]$contract.expected.authoritativeCommandoRuntimeFiles -and
    @($contract.buildEvidence.commandoRuntimeSourceSha256.PSObject.Properties).Count -eq
        $commandoRuntimeSources.Count) `
    "p14.profession-closure.commando-runtime.source-count"
foreach ($property in $contract.buildEvidence.commandoRuntimeSourceSha256.PSObject.Properties)
{
    $path = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        $commandoRuntimeSources.Contains($property.Name) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) `
        "p14.profession-closure.commando-runtime.source.$($property.Name).authenticated"
}

$medicRuntimeSources = [ordered]@{
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java" =
        "systems/combat/combat_base.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java" =
        "systems/combat/combat_actions.java"
}
Assert-Contract ($medicRuntimeSources.Count -eq
        [int]$contract.expected.authoritativeMedicRuntimeFiles -and
    @($contract.buildEvidence.medicRuntimeSourceSha256.PSObject.Properties).Count -eq
        $medicRuntimeSources.Count) `
    "p14.profession-closure.medic-runtime.source-count"
foreach ($property in $contract.buildEvidence.medicRuntimeSourceSha256.PSObject.Properties)
{
    $path = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        $medicRuntimeSources.Contains($property.Name) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) `
        "p14.profession-closure.medic-runtime.source.$($property.Name).authenticated"
}

$entertainerRuntimeSources = [ordered]@{
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java" =
        "systems/combat/combat_base.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java" =
        "systems/combat/combat_actions.java"
}
Assert-Contract ($entertainerRuntimeSources.Count -eq
        [int]$contract.expected.authoritativeEntertainerRuntimeFiles -and
    @($contract.buildEvidence.entertainerRuntimeSourceSha256.PSObject.Properties).Count -eq
        $entertainerRuntimeSources.Count) `
    "p14.profession-closure.entertainer-runtime.source-count"
foreach ($property in $contract.buildEvidence.entertainerRuntimeSourceSha256.PSObject.Properties)
{
    $path = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        $entertainerRuntimeSources.Contains($property.Name) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) `
        "p14.profession-closure.entertainer-runtime.source.$($property.Name).authenticated"
}

$combatBase = [string]$officerTexts["systems/combat/combat_base.java"]
$officerPredicate = Get-FunctionSlice $combatBase `
    "public static boolean isRetiredPostNgeOfficerPlayerAction" `
    "public boolean combatStandardAction"
Assert-Contract ($officerPredicate.Contains("isPlayer(self)") -and
    $officerPredicate.Contains('actionName.startsWith("of_")') -and
    $combatBase.Contains("if (isRetiredPostNgeOfficerPlayerAction(self, actionName))")) `
    "p14.profession-closure.officer-runtime.central-player-action-gate"

$combatActions = [string]$officerTexts["systems/combat/combat_actions.java"]
$officerHandlers = @([regex]::Matches(
    $combatActions,
    '(?ms)^\s*public int (of_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)'))
$standardOfficerHandlers = @($officerHandlers | Where-Object { $_.Value.Contains("combatStandardAction(") })
$directOfficerHandlers = @($officerHandlers | Where-Object { -not $_.Value.Contains("combatStandardAction(") })
$expectedDirectOfficerHandlers = @("of_last_words_recourse", "of_rally_point_def", "of_rally_point_off")
$actualDirectOfficerHandlers = @($directOfficerHandlers | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$directOfficerHandlersGuarded = @($directOfficerHandlers | Where-Object {
    $_.Value.Contains("isRetiredPostNgeOfficerPlayerAction(")
}).Count -eq $directOfficerHandlers.Count
Assert-Contract ($officerHandlers.Count -eq [int]$contract.expected.postNgeOfficerPlayerActionHandlers -and
    $standardOfficerHandlers.Count -eq [int]$contract.expected.postNgeOfficerStandardActionHandlers -and
    $directOfficerHandlers.Count -eq [int]$contract.expected.postNgeOfficerDirectCallbacks -and
    ($actualDirectOfficerHandlers -join "`n") -ceq ($expectedDirectOfficerHandlers -join "`n") -and
    $directOfficerHandlersGuarded) `
    "p14.profession-closure.officer-runtime.all-player-actions-covered"

$forceSensitivePredicate = Get-FunctionSlice $combatBase `
    "public static boolean isRetiredPostNgeForceSensitivePlayerAction" `
    "public static boolean isRetiredPostNgeSmugglerPlayerAction"
Assert-Contract ($forceSensitivePredicate.Contains("isPlayer(self)") -and
    $forceSensitivePredicate.Contains('actionName.startsWith("fs_")') -and
    $combatBase.Contains("if (isRetiredPostNgeForceSensitivePlayerAction(self, actionName))")) `
    "p14.profession-closure.force-sensitive-runtime.central-player-action-gate"

$forceSensitiveHandlers = @([regex]::Matches(
    $combatActions,
    '(?ms)^\s*public int (fs_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)'))
$standardForceSensitiveHandlers = @($forceSensitiveHandlers | Where-Object {
    $_.Value.Contains("combatStandardAction(")
})
$directForceSensitiveHandlers = @($forceSensitiveHandlers | Where-Object {
    -not $_.Value.Contains("combatStandardAction(")
})
$directForceSensitiveHandlerNames = @($directForceSensitiveHandlers | ForEach-Object {
    $_.Groups[1].Value
})
$directForceSensitiveGuarded = $directForceSensitiveHandlers.Count -eq 1 -and
    $directForceSensitiveHandlers[0].Value.Contains(
        'isRetiredPostNgeForceSensitivePlayerAction(self, "fs_dot_immunity_recourse")') -and
    $directForceSensitiveHandlers[0].Value.Contains(
        'buff.removeBuff(self, "fs_dot_immunity_recourse")')
Assert-Contract ($forceSensitiveHandlers.Count -eq
        [int]$contract.expected.postNgeForceSensitivePlayerActionHandlers -and
    $standardForceSensitiveHandlers.Count -eq
        [int]$contract.expected.postNgeForceSensitiveStandardActionHandlers -and
    $directForceSensitiveHandlers.Count -eq
        [int]$contract.expected.postNgeForceSensitiveDirectCallbacks -and
    ($directForceSensitiveHandlerNames -join "`n") -ceq "fs_dot_immunity_recourse" -and
    $directForceSensitiveGuarded) `
    "p14.profession-closure.force-sensitive-runtime.all-player-actions-covered"

$forceSensitiveBuff = [string]$forceSensitiveTexts["library/buff.java"]
$forceSensitiveBuffHandler = [string]$forceSensitiveTexts["systems/buff/buff_handler.java"]
$forceSensitiveBasePlayer = [string]$forceSensitiveTexts["player/base/base_player.java"]
$forceSensitiveStanceInventory = Get-FunctionSlice $forceSensitiveBuff `
    "private static final String[] RETIRED_POST_NGE_FORCE_SENSITIVE_STANCE_BUFFS" `
    "public static boolean isRetiredPostNgeForceSensitiveStanceBuff"
$forceSensitiveStanceCleanup = Get-FunctionSlice $forceSensitiveBuff `
    "public static void retirePostNgeForceSensitiveStanceState" `
    "public static boolean isRetiredPostNgeBountyHunterShieldBuff"
$forceSensitiveCanApply = Get-FunctionSlice $forceSensitiveBuff `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static boolean applyBuff(obj_id target, String name)"
$forceSensitiveStanceHandler = Get-FunctionSlice $forceSensitiveBuffHandler `
    "public int stanceAddBuffHandler" "public int stanceRemoveBuffHandler"
$forceSensitiveStanceQuery = Get-FunctionSlice $forceSensitiveBuff `
    "public static boolean isInStance" "public static boolean isInFocus"
$forceSensitiveFocusQuery = Get-FunctionSlice $forceSensitiveBuff `
    "public static boolean isInFocus" "public static boolean playStanceVisual"
$retiredForceSensitiveStanceNames = @([regex]::Matches(
        $forceSensitiveStanceInventory, '"([A-Za-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$forceSensitiveGenericGate = $forceSensitiveCanApply.IndexOf(
    "isRetiredPostNgeForceSensitiveStanceBuff(bdata.buffName)",
    [StringComparison]::Ordinal)
$forceSensitiveExistingBuffReturn = $forceSensitiveCanApply.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$forceSensitiveHandlerGate = $forceSensitiveStanceHandler.IndexOf(
    "buff.isRetiredPostNgeForceSensitiveStanceBuff(buffName)",
    [StringComparison]::Ordinal)
$forceSensitiveHandlerCleanup = $forceSensitiveStanceHandler.IndexOf(
    "buff.retirePostNgeForceSensitiveStanceState(self);",
    [StringComparison]::Ordinal)
$forceSensitiveHandlerVisual = $forceSensitiveStanceHandler.IndexOf(
    "buff.playStanceVisual(self, effectName);", [StringComparison]::Ordinal)
Assert-Contract ($retiredForceSensitiveStanceNames.Count -eq
        [int]$contract.expected.retiredNgeForceSensitiveStanceStateBuffs -and
    @($retiredForceSensitiveStanceNames | Select-Object -Unique).Count -eq
        $retiredForceSensitiveStanceNames.Count -and
    $forceSensitiveStanceCleanup.Contains("!isPlayer(player)") -and
    $forceSensitiveStanceCleanup.Contains("removeBuff(player, retiredBuff);") -and
    $forceSensitiveBasePlayer.Contains(
        "buff.retirePostNgeForceSensitiveStanceState(self);") -and
    $forceSensitiveGenericGate -ge 0 -and
    $forceSensitiveExistingBuffReturn -gt $forceSensitiveGenericGate -and
    $forceSensitiveHandlerGate -ge 0 -and
    $forceSensitiveHandlerCleanup -gt $forceSensitiveHandlerGate -and
    $forceSensitiveHandlerVisual -gt $forceSensitiveHandlerCleanup -and
    $forceSensitiveStanceQuery.Contains(
        "retirePostNgeForceSensitiveStanceState(player);") -and
    $forceSensitiveStanceQuery.Contains("return false;") -and
    $forceSensitiveStanceQuery.Contains("return true;") -and
    $forceSensitiveFocusQuery.Contains(
        "retirePostNgeForceSensitiveStanceState(player);") -and
    $forceSensitiveFocusQuery.Contains("return false;") -and
    $forceSensitiveFocusQuery.Contains("return true;")) `
    "p14.profession-closure.force-sensitive-runtime.persisted-stances-fail-closed"

$smugglerPredicate = Get-FunctionSlice $combatBase `
    "public static boolean isRetiredPostNgeSmugglerPlayerAction" `
    "public static boolean isRetiredPostNgeBountyHunterPlayerAction"
Assert-Contract ($smugglerPredicate.Contains("isPlayer(self)") -and
    $smugglerPredicate.Contains('actionName.startsWith("sm_")') -and
    $combatBase.Contains("if (isRetiredPostNgeSmugglerPlayerAction(self, actionName))")) `
    "p14.profession-closure.smuggler-runtime.central-player-action-gate"

$smugglerHandlers = @([regex]::Matches(
    $combatActions,
    '(?ms)^\s*public int (sm_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)'))
$standardSmugglerHandlers = @($smugglerHandlers | Where-Object {
    $_.Value.Contains("combatStandardAction(")
})
$directSmugglerHandlers = @($smugglerHandlers | Where-Object {
    -not $_.Value.Contains("combatStandardAction(")
})
$expectedDirectSmugglerHandlers = @(
    "sm_break_the_deal_recourse",
    "sm_disarm_trap_1",
    "sm_feeling_lucky_recourse",
    "sm_inspect_cargo",
    "sm_lucky_break_recourse",
    "sm_melee_stun_recourse"
)
$actualDirectSmugglerHandlers = @($directSmugglerHandlers | ForEach-Object {
    $_.Groups[1].Value
} | Sort-Object)
$directSmugglerHandlersGuarded = $true
foreach ($handler in $directSmugglerHandlers)
{
    $name = $handler.Groups[1].Value
    if (-not $handler.Value.Contains(
        "isRetiredPostNgeSmugglerPlayerAction(self, `"$name`")"))
    {
        $directSmugglerHandlersGuarded = $false
    }
    if ($name.EndsWith("_recourse") -and
        -not $handler.Value.Contains("buff.removeBuff(self, `"$name`")"))
    {
        $directSmugglerHandlersGuarded = $false
    }
    if (-not $name.EndsWith("_recourse") -and
        -not $handler.Value.Contains("return SCRIPT_OVERRIDE;"))
    {
        $directSmugglerHandlersGuarded = $false
    }
}
Assert-Contract ($smugglerHandlers.Count -eq
        [int]$contract.expected.postNgeSmugglerPlayerActionHandlers -and
    $standardSmugglerHandlers.Count -eq
        [int]$contract.expected.postNgeSmugglerStandardActionHandlers -and
    $directSmugglerHandlers.Count -eq
        [int]$contract.expected.postNgeSmugglerDirectCallbacks -and
    ($actualDirectSmugglerHandlers -join "`n") -ceq
        ($expectedDirectSmugglerHandlers -join "`n") -and
    $directSmugglerHandlersGuarded) `
    "p14.profession-closure.smuggler-runtime.all-player-actions-covered"

$bountyHunterPredicate = Get-FunctionSlice $combatBase `
    "public static boolean isRetiredPostNgeBountyHunterPlayerAction" `
    "public static boolean isRetiredPostNgeCommandoPlayerAction"
Assert-Contract ($bountyHunterPredicate.Contains("isPlayer(self)") -and
    $bountyHunterPredicate.Contains('actionName.startsWith("bh_")') -and
    $combatBase.Contains("if (isRetiredPostNgeBountyHunterPlayerAction(self, actionName))")) `
    "p14.profession-closure.bounty-hunter-runtime.central-player-action-gate"
$bountyHunterHandlers = @([regex]::Matches(
    $combatActions,
    '(?ms)^\s*public int (bh_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)'))
$standardBountyHunterHandlers = @($bountyHunterHandlers | Where-Object {
    $_.Value.Contains("combatStandardAction(")
})
$directBountyHunterHandlers = @($bountyHunterHandlers | Where-Object {
    -not $_.Value.Contains("combatStandardAction(")
})
Assert-Contract ($bountyHunterHandlers.Count -eq
        [int]$contract.expected.postNgeBountyHunterPlayerActionHandlers -and
    $standardBountyHunterHandlers.Count -eq
        [int]$contract.expected.postNgeBountyHunterStandardActionHandlers -and
    $directBountyHunterHandlers.Count -eq
        [int]$contract.expected.postNgeBountyHunterDirectCallbacks) `
    "p14.profession-closure.bounty-hunter-runtime.all-player-actions-covered"

$bountyHunterBuffLibrary = [string]$bountyHunterTexts["library/buff.java"]
$bountyHunterBuffHandler = [string]$bountyHunterTexts["systems/buff/buff_handler.java"]
$bountyHunterShieldScript = [string]$bountyHunterTexts["player/skill/bh_shields.java"]
$bountyHunterShieldPredicate = Get-FunctionSlice $bountyHunterBuffLibrary `
    "public static boolean isRetiredPostNgeBountyHunterShieldBuff" `
    "public static void retirePostNgeBountyHunterShieldState"
$bountyHunterShieldCleanup = Get-FunctionSlice $bountyHunterBuffLibrary `
    "public static void retirePostNgeBountyHunterShieldState" `
    "public static void retirePostNgeBuffProgression"
$bountyHunterShieldHandler = Get-FunctionSlice $bountyHunterBuffHandler `
    "public int bhShieldsAddBuffHandler" `
    "public int bhShieldsRemoveBuffHandler"
$bountyHunterCanApply = Get-FunctionSlice $bountyHunterBuffLibrary `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static boolean applyBuff(obj_id target, String name)"
$bountyHunterGenericGate = $bountyHunterCanApply.IndexOf(
    "isRetiredPostNgeBountyHunterShieldBuff(bdata.buffName)",
    [StringComparison]::Ordinal)
$bountyHunterExistingBuffReturn = $bountyHunterCanApply.IndexOf(
    "hasBuff(target, nameCrc)", [StringComparison]::Ordinal)
$retiredBountyHunterShieldBuffs = @(
    "bh_shields_handler", "bh_shields", "bh_shields_block", "bh_shields_charged"
)
$shieldPredicateNames = @($retiredBountyHunterShieldBuffs | Where-Object {
    $bountyHunterShieldPredicate.Contains('buffName.equals("' + $_ + '")')
})
Assert-Contract ($shieldPredicateNames.Count -eq
        [int]$contract.expected.retiredNgeBountyHunterShieldBuffs -and
    $bountyHunterShieldCleanup.Contains("!isPlayer(player)") -and
    $bountyHunterShieldCleanup.Contains("removeBuff(player, retiredBuff);") -and
    $bountyHunterShieldCleanup.Contains('detachScript(player, "player.skill.bh_shields");') -and
    $bountyHunterCanApply.Contains("isPlayer(target)") -and
    $bountyHunterGenericGate -ge 0 -and
    $bountyHunterExistingBuffReturn -gt $bountyHunterGenericGate -and
    $bountyHunterShieldHandler.Contains("if (isPlayer(self))") -and
    $bountyHunterShieldHandler.IndexOf("retirePostNgeBountyHunterShieldState",
        [StringComparison]::Ordinal) -lt
        $bountyHunterShieldHandler.IndexOf("attachScript", [StringComparison]::Ordinal) -and
    ([regex]::Matches($bountyHunterShieldScript,
        'buff\.retirePostNgeBountyHunterShieldState\(self\);')).Count -eq
        [int]$contract.expected.retiredBountyHunterShieldScriptCallbacks -and
    ([regex]::Matches($bountyHunterShieldScript, 'if \(isPlayer\(self\)\)')).Count -eq
        [int]$contract.expected.retiredBountyHunterShieldScriptCallbacks -and
    $bountyHunterShieldScript.IndexOf("retirePostNgeBountyHunterShieldState",
        [StringComparison]::Ordinal) -lt
        $bountyHunterShieldScript.IndexOf("buff.applyBuff", [StringComparison]::Ordinal)) `
    "p14.profession-closure.bounty-hunter-runtime.persisted-shields-retired"

$commandoPredicate = Get-FunctionSlice $combatBase `
    "public static boolean isRetiredPostNgeCommandoPlayerAction" `
    "public static boolean isRetiredPostNgeMedicPlayerAction"
Assert-Contract ($commandoPredicate.Contains("isPlayer(self)") -and
    $commandoPredicate.Contains('actionName.startsWith("co_")') -and
    $combatBase.Contains("if (isRetiredPostNgeCommandoPlayerAction(self, actionName))")) `
    "p14.profession-closure.commando-runtime.central-player-action-gate"
$commandoHandlers = @([regex]::Matches(
    $combatActions,
    '(?ms)^\s*public int (co_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)'))
$standardCommandoHandlers = @($commandoHandlers | Where-Object {
    $_.Value.Contains("combatStandardAction(")
})
$directCommandoHandlers = @($commandoHandlers | Where-Object {
    -not $_.Value.Contains("combatStandardAction(")
})
$directCommandoGuarded = $directCommandoHandlers.Count -eq 1 -and
    $directCommandoHandlers[0].Groups[1].Value -ceq "co_kill_trap_1" -and
    $directCommandoHandlers[0].Value.Contains(
        'isRetiredPostNgeCommandoPlayerAction(self, "co_kill_trap_1")') -and
    $directCommandoHandlers[0].Value.Contains("return SCRIPT_OVERRIDE;")
Assert-Contract ($commandoHandlers.Count -eq
        [int]$contract.expected.postNgeCommandoPlayerActionHandlers -and
    $standardCommandoHandlers.Count -eq
        [int]$contract.expected.postNgeCommandoStandardActionHandlers -and
    $directCommandoHandlers.Count -eq
        [int]$contract.expected.postNgeCommandoDirectCallbacks -and
    $directCommandoGuarded) `
    "p14.profession-closure.commando-runtime.all-player-actions-covered"

$medicPredicate = Get-FunctionSlice $combatBase `
    "public static boolean isRetiredPostNgeMedicPlayerAction" `
    "public static boolean isRetiredPostNgeEntertainerPlayerAction"
Assert-Contract ($medicPredicate.Contains("isPlayer(self)") -and
    $medicPredicate.Contains('actionName.startsWith("me_")') -and
    $combatBase.Contains("if (isRetiredPostNgeMedicPlayerAction(self, actionName))")) `
    "p14.profession-closure.medic-runtime.central-player-action-gate"
$medicHandlers = @([regex]::Matches(
    $combatActions,
    '(?ms)^\s*public int (me_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)'))
$standardMedicHandlers = @($medicHandlers | Where-Object {
    $_.Value.Contains("combatStandardAction(")
})
$directMedicHandlers = @($medicHandlers | Where-Object {
    -not $_.Value.Contains("combatStandardAction(")
})
$directMedicHandlersGuarded = @($directMedicHandlers | Where-Object {
    $_.Value.Contains('isRetiredPostNgeMedicPlayerAction(self, "' +
        $_.Groups[1].Value + '")') -and
    $_.Value.Contains("return SCRIPT_OVERRIDE;")
}).Count -eq $directMedicHandlers.Count
Assert-Contract ($medicHandlers.Count -eq
        [int]$contract.expected.postNgeMedicPlayerActionHandlers -and
    $standardMedicHandlers.Count -eq
        [int]$contract.expected.postNgeMedicStandardActionHandlers -and
    $directMedicHandlers.Count -eq
        [int]$contract.expected.postNgeMedicDirectCallbacks -and
    $directMedicHandlersGuarded) `
    "p14.profession-closure.medic-runtime.all-player-actions-covered"

$entertainerPredicate = Get-FunctionSlice $combatBase `
    "public static boolean isRetiredPostNgeEntertainerPlayerAction" `
    "public boolean combatStandardAction"
Assert-Contract ($entertainerPredicate.Contains("isPlayer(self)") -and
    $entertainerPredicate.Contains('actionName.startsWith("en_")') -and
    $combatBase.Contains("if (isRetiredPostNgeEntertainerPlayerAction(self, actionName))")) `
    "p14.profession-closure.entertainer-runtime.central-player-action-gate"
$entertainerHandlers = @([regex]::Matches(
    $combatActions,
    '(?ms)^\s*public int (en_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)'))
$standardEntertainerHandlers = @($entertainerHandlers | Where-Object {
    $_.Value.Contains("combatStandardAction(")
})
$directEntertainerHandlers = @($entertainerHandlers | Where-Object {
    -not $_.Value.Contains("combatStandardAction(")
})
$directEntertainerHandlersGuarded = @($directEntertainerHandlers | Where-Object {
    $_.Value.Contains('isRetiredPostNgeEntertainerPlayerAction(self, "' +
        $_.Groups[1].Value + '")') -and
    $_.Value.Contains("return SCRIPT_OVERRIDE;")
}).Count -eq $directEntertainerHandlers.Count
Assert-Contract ($entertainerHandlers.Count -eq
        [int]$contract.expected.postNgeEntertainerPlayerActionHandlers -and
    $standardEntertainerHandlers.Count -eq
        [int]$contract.expected.postNgeEntertainerStandardActionHandlers -and
    $directEntertainerHandlers.Count -eq
        [int]$contract.expected.postNgeEntertainerDirectCallbacks -and
    $directEntertainerHandlersGuarded) `
    "p14.profession-closure.entertainer-runtime.all-player-actions-covered"

$officerPet = [string]$officerTexts["ai/officer_pet.java"]
Assert-Contract (-not $officerPet.Contains("expertise_of_reinforcements_1") -and
    $officerPet.Contains("retirePostNgeOfficerPet") -and
    $officerPet.Contains("pet_lib.destroyOfficerPets(master)") -and
    $officerPet.Contains("destroyObject(self)")) `
    "p14.profession-closure.officer-runtime.persisted-pet-retired"

$supplyController = [string]$officerTexts["systems/combat/combat_supply_drop_controller.java"]
$controllerCallbacks = @("startLandingSequence", "dropReinforcements", "dropSupplies")
$controllerCallbacksGuarded = $true
foreach ($callback in $controllerCallbacks)
{
    $slice = Get-FunctionSlice $supplyController "public int $callback" "public int"
    if (-not $slice.Contains("retirePostNgeOfficerSupplyDrop(self, owner)"))
    {
        $controllerCallbacksGuarded = $false
    }
}
$summonOfficerPet = Get-FunctionSlice $supplyController "public void summonOfficerPet" `
    "public boolean retirePostNgeOfficerSupplyDrop"
Assert-Contract ($controllerCallbacksGuarded -and
    $summonOfficerPet.Contains("isPlayer(owner)") -and
    $summonOfficerPet.Contains("pet_lib.destroyOfficerPets(owner)") -and
    $summonOfficerPet.Contains("return;")) `
    "p14.profession-closure.officer-runtime.delayed-drops-and-hirelings-retired"

$supplyCrate = [string]$officerTexts["systems/combat/combat_supply_drop_crate.java"]
$crateTransfer = Get-FunctionSlice $supplyCrate "public int OnAboutToLoseItem" `
    "public boolean retirePostNgeOfficerSupplyCrate"
Assert-Contract ($supplyCrate.Contains("public int OnAttach") -and
    $supplyCrate.Contains("public int OnInitialize") -and
    $supplyCrate.Contains("retirePostNgeOfficerSupplyCrate(self)") -and
    $crateTransfer.Contains("isPlayer(transferer)") -and
    $crateTransfer.Contains("return SCRIPT_OVERRIDE;")) `
    "p14.profession-closure.officer-runtime.persisted-crate-retired"

$officerExpertiseReaders = @(Get-ChildItem -LiteralPath `
        (Join-Path $dsrc "sku.0/sys.server/compiled/game/script") -Recurse -File -Filter "*.java" |
    Where-Object { $_.FullName -notmatch '[\\/](?:test|working|beta)[\\/]' } |
    Select-String -SimpleMatch 'expertise_of_reinforcements_1')
Assert-Contract ($officerExpertiseReaders.Count -eq
    [int]$contract.expected.productionOfficerReinforcementExpertiseReaders) `
    "p14.profession-closure.officer-runtime.production-expertise-reader-absent"

$ngePattern = 'class_(?:bountyhunter|commando|domestics|engineering|entertainer|forcesensitive|medic|munitions|officer|smuggler|spy|structures|trader)'
$executableAuthorityText = [regex]::Replace(
    $changedText,
    '(?s)public static boolean isRetiredPostNgeSpySkill\(.*?(?=public static boolean grant\()',
    ''
)
Assert-Contract (-not [regex]::IsMatch($executableAuthorityText, $ngePattern)) `
    "p14.profession-closure.changed-executable-nge-authority.absent"

$productionRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/script"
$residual = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $productionRoot -Recurse -File -Filter "*.java")
{
    $relative = $file.FullName.Substring($dsrc.Length + 1).Replace('\', '/')
    if ($relative -match '/(?:test|working|beta)/') { continue }
    $matches = [regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), $ngePattern)
    if ($matches.Count -gt 0) { $residual[$relative] = $matches.Count }
}
$expectedResidual = $contract.expected.retainedCompatibilityBreakdown
$expectedResidualNames = @($expectedResidual.PSObject.Properties.Name | Sort-Object)
$actualResidualNames = @($residual.Keys | Sort-Object)
$residualCountsMatch = ($expectedResidualNames -join "`n") -ceq ($actualResidualNames -join "`n")
$residualTotal = 0
foreach ($name in $actualResidualNames)
{
    $residualTotal += [int]$residual[$name]
    $expectedProperty = $expectedResidual.PSObject.Properties[$name]
    if ($null -eq $expectedProperty -or [int]$expectedProperty.Value -ne [int]$residual[$name])
    {
        $residualCountsMatch = $false
    }
}
Assert-Contract ($residualCountsMatch -and
    $actualResidualNames.Count -eq [int]$contract.expected.retainedCompatibilityReferenceFiles -and
    $residualTotal -eq [int]$contract.expected.retainedCompatibilityReferences) `
    "p14.profession-closure.compatibility-only-residuals.exact"

$skillText = Get-SourceText "sku.0/sys.server/compiled/game/script/library/skill.java"
$phaseSlice = Get-FunctionSlice $skillText "public static int getProfessionPhase" "public static boolean validateExpertise"
Assert-Contract ($skillText.Contains("PRECU_PHASE_TWO_COMBAT_SCORE = 25") -and
    $skillText.Contains("PRECU_PHASE_THREE_COMBAT_SCORE = 50") -and
    $skillText.Contains("PRECU_PHASE_FOUR_COMBAT_SCORE = 75") -and
    $phaseSlice.Contains("getPrecuCombatSkillScore(player)") -and
    -not [regex]::IsMatch($phaseSlice, $ngePattern)) `
    "p14.profession-closure.phase.hidden-precu-combat-score"

$officerSkillsTable = Get-SourceText "sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$commandTable = Get-SourceText "sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatTable = Get-SourceText "sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$commandSeries = Get-SourceText "sku.0/sys.server/compiled/game/datatables/command/command_series.tab"
$creatureTable = Get-SourceText "sku.0/sys.server/compiled/game/datatables/mob/creatures.tab"
Assert-Contract (([regex]::Matches($officerSkillsTable, '(?m)^class_officer_').Count -eq
        [int]$contract.expected.retainedOfficerClassSkillRows) -and
    ([regex]::Matches($officerSkillsTable, '(?m)^expertise_of_').Count -eq
        [int]$contract.expected.retainedOfficerExpertiseSkillRows) -and
    ([regex]::Matches($commandTable, '(?m)^of_').Count -eq
        [int]$contract.expected.retainedOfficerCommandRows) -and
    ([regex]::Matches($combatTable, '(?m)^of_').Count -eq
        [int]$contract.expected.retainedOfficerCombatRows) -and
    ([regex]::Matches($commandSeries, '(?m)^of_').Count -eq
        [int]$contract.expected.retainedOfficerCommandSeriesRows) -and
    ([regex]::Matches($creatureTable, '(?m)^officer_reinforcement_').Count -eq
        [int]$contract.expected.retainedOfficerReinforcementCreatureRows)) `
    "p14.profession-closure.officer-runtime.compatibility-data-retained"

$skillTablePath = Join-Path $dsrc "sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$skillTableLines = @(Get-Content -LiteralPath $skillTablePath)
$skillTableHeaders = $skillTableLines[0] -split "`t"
$skillRows = @($skillTableLines | Select-Object -Skip 2 |
    ConvertFrom-Csv -Delimiter "`t" -Header $skillTableHeaders)
$precuJediAndVillageRows = @($skillRows | Where-Object {
    [string]$_.NAME -match '^(?:jedi_|force_sensitive_)'
})
$precuJediAndVillageCommands = @($precuJediAndVillageRows | ForEach-Object {
    ([string]$_.COMMANDS).Trim('"') -split ','
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
Assert-Contract (([regex]::Matches($officerSkillsTable, '(?m)^class_forcesensitive_').Count -eq
        [int]$contract.expected.retainedForceSensitiveClassSkillRows) -and
    ([regex]::Matches($officerSkillsTable, '(?m)^expertise_fs_').Count -eq
        [int]$contract.expected.retainedForceSensitiveExpertiseSkillRows) -and
    ([regex]::Matches($commandTable, '(?m)^fs_').Count -eq
        [int]$contract.expected.retainedForceSensitiveCommandRows) -and
    ([regex]::Matches($combatTable, '(?m)^fs_').Count -eq
        [int]$contract.expected.retainedForceSensitiveCombatRows) -and
    ([regex]::Matches($commandSeries, '(?m)^fs_').Count -eq
        [int]$contract.expected.retainedForceSensitiveCommandSeriesRows) -and
    $precuJediAndVillageRows.Count -eq [int]$contract.expected.precuJediAndVillageSkillRows -and
    $precuJediAndVillageCommands.Count -eq [int]$contract.expected.precuJediAndVillageCommands -and
    @($precuJediAndVillageCommands | Where-Object { $_ -match '^fs_' }).Count -eq
        [int]$contract.expected.precuJediAndVillageFsCommands) `
    "p14.profession-closure.force-sensitive-runtime.data-and-precu-command-boundary"

$buffTablePath = Join-Path $dsrc `
    "sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
$buffTableLines = @(Get-Content -LiteralPath $buffTablePath)
$buffTableHeaders = $buffTableLines[0] -split "`t"
$buffRows = @($buffTableLines | Select-Object -Skip 2 |
    ConvertFrom-Csv -Delimiter "`t" -Header $buffTableHeaders)
$retiredForceSensitiveStanceRows = @($buffRows | Where-Object {
    $retiredForceSensitiveStanceNames -ccontains [string]$_.NAME
})
$precuCenterOfBeing = Get-FunctionSlice $combatActions `
    "public int centerOfBeing" "public int forceFocus"
Assert-Contract ($retiredForceSensitiveStanceRows.Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveStanceCompatibilityRows -and
    @($retiredForceSensitiveStanceRows | Select-Object -ExpandProperty NAME -Unique).Count -eq
        [int]$contract.expected.retainedNgeForceSensitiveStanceCompatibilityRows -and
    @($retiredForceSensitiveStanceNames | Where-Object {
        $_ -cnotin @($retiredForceSensitiveStanceRows |
            Select-Object -ExpandProperty NAME)
    }).Count -eq
        [int]$contract.expected.historicalForceSensitiveStanceCleanupOnlyNames -and
    $retiredForceSensitiveStanceNames -ccontains "fs_imp_force_drain_4" -and
    [bool]$contract.expected.precuCenterOfBeingPreserved -and
    -not ($retiredForceSensitiveStanceNames -ccontains "centerofbeing") -and
    @($buffRows | Where-Object {
        [string]$_.NAME -ceq "centerofbeing" -and
        [string]$_.EFFECT1_PARAM -ceq "private_center_of_being"
    }).Count -eq 1 -and
    $precuCenterOfBeing.Contains('hasSkill(self, "combat_brawler_novice")') -and
    $precuCenterOfBeing.Contains('"centerofbeing"') -and
    $precuCenterOfBeing.Contains('"center_of_being_duration_') -and
    $precuCenterOfBeing.Contains("_center_of_being_efficacy") -and
    $precuCenterOfBeing.Contains("combat.drainCombatActionAttributes") -and
    -not $precuCenterOfBeing.Contains("fs_buff_def_1_1") -and
    -not $precuCenterOfBeing.Contains("fs_buff_ca_1")) `
    "p14.profession-closure.force-sensitive-runtime.compatibility-and-precu-center-boundary"

$precuSmugglerRows = @($skillRows | Where-Object {
    [string]$_.NAME -match '^combat_smuggler(?:_|$)'
})
$precuSmugglerCommands = @($precuSmugglerRows | ForEach-Object {
    ([string]$_.COMMANDS).Trim('"') -split ','
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
Assert-Contract (([regex]::Matches($officerSkillsTable, '(?m)^class_smuggler_').Count -eq
        [int]$contract.expected.retainedSmugglerClassSkillRows) -and
    ([regex]::Matches($officerSkillsTable, '(?m)^expertise_sm_').Count -eq
        [int]$contract.expected.retainedSmugglerExpertiseSkillRows) -and
    ([regex]::Matches($commandTable, '(?m)^sm_').Count -eq
        [int]$contract.expected.retainedSmugglerCommandRows) -and
    ([regex]::Matches($combatTable, '(?m)^sm_').Count -eq
        [int]$contract.expected.retainedSmugglerCombatRows) -and
    ([regex]::Matches($commandSeries, '(?m)^sm_').Count -eq
        [int]$contract.expected.retainedSmugglerCommandSeriesRows) -and
    $precuSmugglerRows.Count -eq [int]$contract.expected.precuSmugglerSkillRows -and
    $precuSmugglerCommands.Count -eq [int]$contract.expected.precuSmugglerCommands -and
    @($precuSmugglerCommands | Where-Object { $_ -match '^sm_' }).Count -eq
        [int]$contract.expected.precuSmugglerSmCommands) `
    "p14.profession-closure.smuggler-runtime.data-and-precu-command-boundary"

$precuBountyHunterRows = @($skillRows | Where-Object {
    [string]$_.NAME -match '^combat_bountyhunter(?:_|$)'
})
$precuBountyHunterCommands = @($precuBountyHunterRows | ForEach-Object {
    ([string]$_.COMMANDS).Trim('"') -split ','
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
Assert-Contract (([regex]::Matches($officerSkillsTable, '(?m)^class_bountyhunter_').Count -eq
        [int]$contract.expected.retainedBountyHunterClassSkillRows) -and
    ([regex]::Matches($officerSkillsTable, '(?m)^expertise_bh_').Count -eq
        [int]$contract.expected.retainedBountyHunterExpertiseSkillRows) -and
    ([regex]::Matches($commandTable, '(?m)^bh_').Count -eq
        [int]$contract.expected.retainedBountyHunterCommandRows) -and
    ([regex]::Matches($combatTable, '(?m)^bh_').Count -eq
        [int]$contract.expected.retainedBountyHunterCombatRows) -and
    ([regex]::Matches($commandSeries, '(?m)^bh_').Count -eq
        [int]$contract.expected.retainedBountyHunterCommandSeriesRows) -and
    $precuBountyHunterRows.Count -eq [int]$contract.expected.precuBountyHunterSkillRows -and
    $precuBountyHunterCommands.Count -eq [int]$contract.expected.precuBountyHunterCommands -and
    @($precuBountyHunterCommands | Where-Object { $_ -match '^bh_' }).Count -eq
        [int]$contract.expected.precuBountyHunterBhCommands) `
    "p14.profession-closure.bounty-hunter-runtime.data-and-precu-command-boundary"

$precuCommandoRows = @($skillRows | Where-Object {
    [string]$_.NAME -match '^combat_commando(?:_|$)'
})
$precuCommandoCommands = @($precuCommandoRows | ForEach-Object {
    ([string]$_.COMMANDS).Trim('"') -split ','
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
Assert-Contract (([regex]::Matches($officerSkillsTable, '(?m)^class_commando_').Count -eq
        [int]$contract.expected.retainedCommandoClassSkillRows) -and
    ([regex]::Matches($officerSkillsTable, '(?m)^expertise_co_').Count -eq
        [int]$contract.expected.retainedCommandoExpertiseSkillRows) -and
    ([regex]::Matches($commandTable, '(?m)^co_').Count -eq
        [int]$contract.expected.retainedCommandoCommandRows) -and
    ([regex]::Matches($combatTable, '(?m)^co_').Count -eq
        [int]$contract.expected.retainedCommandoCombatRows) -and
    ([regex]::Matches($commandSeries, '(?m)^co_').Count -eq
        [int]$contract.expected.retainedCommandoCommandSeriesRows) -and
    $precuCommandoRows.Count -eq [int]$contract.expected.precuCommandoSkillRows -and
    $precuCommandoCommands.Count -eq [int]$contract.expected.precuCommandoCommands -and
    @($precuCommandoCommands | Where-Object { $_ -match '^co_' }).Count -eq
        [int]$contract.expected.precuCommandoCoCommands) `
    "p14.profession-closure.commando-runtime.data-and-precu-command-boundary"

$precuMedicRows = @($skillRows | Where-Object {
    [string]$_.NAME -match '^(science_medic|science_doctor|science_combatmedic)(?:_|$)'
})
$precuMedicCommands = @($precuMedicRows | ForEach-Object {
    ([string]$_.COMMANDS).Trim('"') -split ','
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
Assert-Contract (([regex]::Matches($officerSkillsTable, '(?m)^class_medic_').Count -eq
        [int]$contract.expected.retainedMedicClassSkillRows) -and
    ([regex]::Matches($officerSkillsTable, '(?m)^expertise_me_').Count -eq
        [int]$contract.expected.retainedMedicExpertiseSkillRows) -and
    ([regex]::Matches($commandTable, '(?m)^me_').Count -eq
        [int]$contract.expected.retainedMedicCommandRows) -and
    ([regex]::Matches($combatTable, '(?m)^me_').Count -eq
        [int]$contract.expected.retainedMedicCombatRows) -and
    ([regex]::Matches($commandSeries, '(?m)^me_').Count -eq
        [int]$contract.expected.retainedMedicCommandSeriesRows) -and
    $precuMedicRows.Count -eq [int]$contract.expected.precuMedicSkillRows -and
    $precuMedicCommands.Count -eq [int]$contract.expected.precuMedicCommands -and
    @($precuMedicCommands | Where-Object { $_ -match '^me_' }).Count -eq
        [int]$contract.expected.precuMedicMeCommands) `
    "p14.profession-closure.medic-runtime.data-and-precu-command-boundary"

$precuEntertainerRows = @($skillRows | Where-Object {
    [string]$_.NAME -match '^(social_entertainer|social_dancer|social_musician|social_imagedesigner)(?:_|$)'
})
$precuEntertainerCommands = @($precuEntertainerRows | ForEach-Object {
    ([string]$_.COMMANDS).Trim('"') -split ','
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
Assert-Contract (([regex]::Matches($officerSkillsTable, '(?m)^class_entertainer_').Count -eq
        [int]$contract.expected.retainedEntertainerClassSkillRows) -and
    ([regex]::Matches($officerSkillsTable, '(?m)^expertise_en_').Count -eq
        [int]$contract.expected.retainedEntertainerExpertiseSkillRows) -and
    ([regex]::Matches($commandTable, '(?m)^en_').Count -eq
        [int]$contract.expected.retainedEntertainerCommandRows) -and
    ([regex]::Matches($combatTable, '(?m)^en_').Count -eq
        [int]$contract.expected.retainedEntertainerCombatRows) -and
    ([regex]::Matches($commandSeries, '(?m)^en_').Count -eq
        [int]$contract.expected.retainedEntertainerCommandSeriesRows) -and
    $precuEntertainerRows.Count -eq [int]$contract.expected.precuEntertainerSkillRows -and
    $precuEntertainerCommands.Count -eq [int]$contract.expected.precuEntertainerCommands -and
    @($precuEntertainerCommands | Where-Object { $_ -match '^en_' }).Count -eq
        [int]$contract.expected.precuEntertainerEnCommands) `
    "p14.profession-closure.entertainer-runtime.data-and-precu-command-boundary"

$utilsText = Get-SourceText "sku.0/sys.server/compiled/game/script/library/utils.java"
$professionSlice = Get-FunctionSlice $utilsText "public static int getPlayerProfession" "public static byte[] packObject"
$professionOrder = @("FORCE_SENSITIVE", "BOUNTY_HUNTER", "SMUGGLER", "COMMANDO", "OFFICER", "MEDIC", "ENTERTAINER", "TRADER")
$professionCursor = -1
$professionOrderValid = $true
foreach ($profession in $professionOrder)
{
    $professionCursor = $professionSlice.IndexOf("isProfession(player, $profession)", $professionCursor + 1, [System.StringComparison]::Ordinal)
    if ($professionCursor -lt 0) { $professionOrderValid = $false; break }
}
Assert-Contract ($professionOrderValid -and $professionSlice.Contains("return TRADER;") -and
    $professionSlice.Contains("return NO_PROFESSION;") -and
    -not [regex]::IsMatch($professionSlice, $ngePattern)) `
    "p14.profession-closure.singular-adapter.precu-ownership"
Assert-Contract ($utilsText.Contains('hasSkill(player, "combat_smuggler_underworld_01")') -and
    $utilsText.Contains('hasSkill(player, "social_language_wookiee_comprehend")')) `
    "p14.profession-closure.wookiee-language.precu-authority"

$singularConsumerFiles = @()
foreach ($file in Get-ChildItem -LiteralPath $productionRoot -Recurse -File -Filter "*.java")
{
    $relative = $file.FullName.Substring($dsrc.Length + 1).Replace('\', '/')
    if ($relative.EndsWith("/library/utils.java") -or $relative -match '/(?:test|working|beta)/') { continue }
    if ((Get-Content -LiteralPath $file.FullName -Raw).Contains("getPlayerProfession(")) { $singularConsumerFiles += $relative }
}
Assert-Contract ($singularConsumerFiles.Count -eq [int]$contract.expected.externalSingularCompatibilityConsumers -and
    ($singularConsumerFiles -contains "sku.0/sys.server/compiled/game/script/item/gcw_buff_banner/banner_buff_manager.java")) `
    "p14.profession-closure.singular-adapter.consumers-bounded"

$multiProfessionTokens = @(
    "utils.isProfession(breacher, utils.SMUGGLER)",
    "utils.isProfession(target, utils.SMUGGLER)",
    "utils.isProfession(target, utils.BOUNTY_HUNTER)",
    "utils.isProfession(objPilot, utils.SMUGGLER)",
    "!utils.isProfession(player, utils.SMUGGLER)"
)
$multiProfessionValid = $true
foreach ($token in $multiProfessionTokens) { if (-not $changedText.Contains($token)) { $multiProfessionValid = $false } }
Assert-Contract $multiProfessionValid "p14.profession-closure.multi-profession-predicates"

$skillsTable = Get-SourceText "sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$requiredSkills = @(
    "combat_smuggler_novice", "combat_smuggler_underworld_01", "combat_smuggler_underworld_02",
    "combat_smuggler_underworld_03", "combat_smuggler_underworld_04", "combat_smuggler_master",
    "combat_bountyhunter_novice", "combat_bountyhunter_investigation_01", "combat_bountyhunter_investigation_02",
    "combat_bountyhunter_investigation_04", "combat_bountyhunter_master", "outdoors_squadleader_novice",
    "social_entertainer_novice", "social_dancer_novice", "social_musician_novice",
    "crafting_artisan_novice", "crafting_artisan_domestic_04", "crafting_chef_novice", "crafting_tailor_novice",
    "crafting_armorsmith_novice", "crafting_armorsmith_master", "crafting_weaponsmith_novice",
    "crafting_weaponsmith_munitions_04", "crafting_weaponsmith_techniques_02", "crafting_weaponsmith_master",
    "crafting_droidengineer_novice", "crafting_droidengineer_techniques_01", "crafting_droidengineer_techniques_02",
    "crafting_droidengineer_master", "crafting_architect_novice", "crafting_shipwright_novice",
    "force_sensitive_crafting_mastery_novice", "science_medic_master", "science_doctor_novice", "science_doctor_master",
    "combat_commando_novice", "combat_commando_support_01", "combat_commando_support_02",
    "combat_commando_support_03", "combat_commando_support_04", "jedi_padawan_novice"
)
$allRequiredSkillsExist = $true
foreach ($skillName in $requiredSkills)
{
    if (-not [regex]::IsMatch($skillsTable, "(?m)^" + [regex]::Escape($skillName) + "`t")) { $allRequiredSkillsExist = $false }
}
Assert-Contract $allRequiredSkillsExist "p14.profession-closure.skills-table.authority-exists"

$saberFiles = @(Get-ChildItem -LiteralPath (Join-Path $productionRoot "systems/crafting/weapon/lightsaber") -File -Filter "crafting_melee_lightsaber*.java" |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw).Contains("REQUIRED_SKILLS") })
$saberAuthorityValid = $true
foreach ($file in $saberFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if (-not $text.Contains('"jedi_padawan_novice"') -or [regex]::IsMatch($text, $ngePattern)) { $saberAuthorityValid = $false }
}
Assert-Contract ($saberFiles.Count -eq [int]$contract.expected.lightsaberSchematicFiles -and $saberAuthorityValid) `
    "p14.profession-closure.lightsabers.padawan-root"

$groupText = (Get-SourceText "sku.0/sys.server/compiled/game/script/player/base/base_player.java") + "`n" +
    (Get-SourceText "sku.0/sys.server/compiled/game/script/library/xp.java")
Assert-Contract (([regex]::Matches($groupText, 'hasSkill\([^\r\n]+"outdoors_squadleader_novice"\)').Count -ge 3) -and
    -not $groupText.Contains("class_officer_phase")) `
    "p14.profession-closure.squad-leader.command-and-xp"
$registerText = Get-SourceText "sku.0/sys.server/compiled/game/script/player/cmd/register.java"
Assert-Contract ($registerText.Contains('hasSkill(self, "social_dancer_novice")') -and
    $registerText.Contains('hasSkill(self, "social_musician_novice")')) `
    "p14.profession-closure.entertainer.registration"

foreach ($property in $contract.buildEvidence.missionSourceSha256.PSObject.Properties)
{
    $missionPath = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $missionPath -PathType Leaf) -and
        ((Get-FileHash -Algorithm SHA256 -LiteralPath $missionPath).Hash.ToLowerInvariant() -ceq [string]$property.Value)) `
        "p14.profession-closure.mission-source.$($property.Name).unchanged"
}
$missionTerminal = Get-SourceText "sku.0/sys.server/compiled/game/script/systems/missions/base/mission_terminal.java"
$missionBase = Get-SourceText "sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
Assert-Contract ($missionTerminal.Contains("menu_info_types.MISSION_TERMINAL_LIST") -and
    $missionBase.Contains("MAX_MISSIONS = 10") -and $missionBase.Contains("fullRewardEach=") -and
    $missionBase.Contains("split=false dailyCashPenalty=false")) `
    "p14.profession-closure.mission-terminal.continuity"

Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -ccontains
    [string]$contract.status) "p14.profession-closure.contract.status"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    $officerClassHashesValid = $null -ne $contract.buildEvidence.officerRuntimeClassEvidence -and
        @($contract.buildEvidence.officerRuntimeClassEvidence.PSObject.Properties |
            Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0
    $forceSensitiveClassHashesValid =
        $null -ne $contract.buildEvidence.forceSensitiveRuntimeClassEvidence -and
        @($contract.buildEvidence.forceSensitiveRuntimeClassEvidence.PSObject.Properties |
            Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0
    $smugglerClassHashesValid =
        $null -ne $contract.buildEvidence.smugglerRuntimeClassEvidence -and
        @($contract.buildEvidence.smugglerRuntimeClassEvidence.PSObject.Properties |
            Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0
    $bountyHunterClassHashesValid =
        $null -ne $contract.buildEvidence.bountyHunterRuntimeClassEvidence -and
        @($contract.buildEvidence.bountyHunterRuntimeClassEvidence.PSObject.Properties |
            Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0
    $commandoClassHashesValid =
        $null -ne $contract.buildEvidence.commandoRuntimeClassEvidence -and
        @($contract.buildEvidence.commandoRuntimeClassEvidence.PSObject.Properties |
            Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0
    $medicClassHashesValid =
        $null -ne $contract.buildEvidence.medicRuntimeClassEvidence -and
        @($contract.buildEvidence.medicRuntimeClassEvidence.PSObject.Properties |
            Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0
    $entertainerClassHashesValid =
        $null -ne $contract.buildEvidence.entertainerRuntimeClassEvidence -and
        @($contract.buildEvidence.entertainerRuntimeClassEvidence.PSObject.Properties |
            Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0
    Assert-Contract ([string]$manifest.sourceMode -ceq "direct-branch" -and
        $dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.profession-closure.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        $officerClassHashesValid -and
        $forceSensitiveClassHashesValid -and
        $smugglerClassHashesValid -and
        $bountyHunterClassHashesValid -and
        $commandoClassHashesValid -and
        $medicClassHashesValid -and
        $entertainerClassHashesValid -and
        [bool]$contract.runtimeEvidence.deployment.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.deployment.mappedNewlyBuiltBinary) `
        "p14.profession-closure.live-evidence"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.profession-closure.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "PRE-CU profession-authority closure contract failed: $($failures -join ', ')"
}
Write-Host "PRE-CU profession-authority closure contract passed ($($targets.Count) source files, $residualTotal compatibility-only NGE references)."
