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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgeBeastMasterPlayerRuntimeRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$sharedRoot = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables"
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$lf = [char]10

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
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    if ([string]::IsNullOrEmpty($EndMarker)) { return $Text.Substring($start) }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

function Is-Before([string]$Text, [string]$First, [string]$Second)
{
    $firstIndex = $Text.IndexOf($First, [System.StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [System.StringComparison]::Ordinal)
    return $firstIndex -ge 0 -and $secondIndex -ge 0 -and $firstIndex -lt $secondIndex
}

$relativeSourceMap = [ordered]@{
    "ai/beast_control_device.java" = "ai/beast_control_device.java"
    "library/beast_lib.java" = "library/beast_lib.java"
    "player/base/base_player.java" = "player/base/base_player.java"
    "player/player_beastmaster.java" = "player/player_beastmaster.java"
    "systems/combat/combat_actions.java" = "systems/combat/combat_actions.java"
    "systems/combat/combat_base.java" = "systems/combat/combat_base.java"
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.beast-retirement.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract (
        $patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256
    ) "p14.beast-retirement.overlay.authenticated"
}

$targets = @(
    [regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object
)
$expectedTargets = @(
    $relativeSourceMap.Values |
        ForEach-Object { "sku.0/sys.server/compiled/game/script/$_" } |
        Sort-Object
)
Assert-Contract (
    $targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    (($targets -join $lf) -ceq ($expectedTargets -join $lf))
) "p14.beast-retirement.overlay.target-set"
Assert-Contract (
    (Get-TextSha256 (($targets -join $lf) + $lf)) -ceq [string]$contract.buildEvidence.sourceSetSha256
) "p14.beast-retirement.source-set.authenticated"

$sourceTexts = @{}
$contentRecords = ""
foreach ($entry in $relativeSourceMap.GetEnumerator())
{
    $sourcePath = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $sourcePath -PathType Leaf) "p14.beast-retirement.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
        Assert-Contract (
            $hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)
        ) "p14.beast-retirement.source.$($entry.Key).authenticated"
        $contentRecords += "sku.0/sys.server/compiled/game/script/$($entry.Value)=$hash$lf"
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $sourcePath -Raw
    }
}
Assert-Contract (
    (Get-TextSha256 $contentRecords) -ceq [string]$contract.buildEvidence.sourceContentSha256
) "p14.beast-retirement.source-content.authenticated"

$beastLibrary = [string]$sourceTexts["library/beast_lib.java"]
$retirementPredicate = Get-SourceSlice $beastLibrary `
    "public static boolean isPostNgeBeastMasterPlayerRuntimeRetired" `
    "public static boolean isBeast("
$playerPredicate = Get-SourceSlice $retirementPredicate `
    "public static boolean isRetiredPostNgeBeastMasterPlayer(" `
    "public static boolean isRetiredPostNgeBeastMasterPlayerAction("
$actionPredicate = Get-SourceSlice $retirementPredicate `
    "public static boolean isRetiredPostNgeBeastMasterPlayerAction(" `
    "public static void retirePostNgeBeastMasterPlayerState("
$cleanup = Get-SourceSlice $retirementPredicate `
    "public static void retirePostNgeBeastMasterPlayerState(" `
    "public static boolean isBeast("

Assert-Contract (
    $retirementPredicate.Contains("return true;") -and
    $playerPredicate.Contains("isIdValid(player) && isPlayer(player)") -and
    $actionPredicate.Contains('actionName.startsWith("bm_")')
) "p14.beast-retirement.player-only-action-predicate"
Assert-Contract (
    $cleanup.Contains("callable.getCallable(player, callable.CALLABLE_TYPE_COMBAT_PET)") -and
    $cleanup.Contains("isValidBeast(activeBeast) && isBeast(activeBeast)") -and
    $cleanup.Contains("storeBeast(bcd)") -and
    $cleanup.Contains("destroyObject(activeBeast)") -and
    $cleanup.Contains("setBeastOnPlayer(player, null)") -and
    $cleanup.Contains("setBeastmasterPet(player, null)")
) "p14.beast-retirement.persisted-active-state-safe"
Assert-Contract (
    $cleanup.Contains('utils.setScriptVar(player, "beast.no_store_message", true)') -and
    $cleanup.Contains('buff.getBuffOnTargetFromGroup(player, "bm_player_buff")') -and
    $cleanup.Contains("removeAttentionPenaltyDebuff(player)") -and
    $cleanup.Contains('detachScript(player, "player.player_beastmaster")')
) "p14.beast-retirement.player-presentation-cleanup"

$isBeast = Get-SourceSlice $beastLibrary "public static boolean isBeast(" "public static boolean isBeastMaster("
$isBeastMaster = Get-SourceSlice $beastLibrary "public static boolean isBeastMaster(" "public static boolean isValidBeast("
$getBeast = Get-SourceSlice $beastLibrary "public static obj_id getBeastOnPlayer(" "public static boolean hasActiveBeast("
$createBeast = Get-SourceSlice $beastLibrary "public static obj_id createBasicBeastFromPlayer(" "public static obj_id createBeastFromBCD("
$verifyBeast = Get-SourceSlice $beastLibrary "public static void verifyAndUpdateCalledBeastStats(" "public static void removeAttentionPenaltyDebuff("
Assert-Contract (
    -not $isBeast.Contains("isRetiredPostNgeBeastMasterPlayer") -and
    (Is-Before $isBeastMaster "isRetiredPostNgeBeastMasterPlayer(player)" 'getSkillStatisticModifier(player, "expertise_bm_base_mod")') -and
    (Is-Before $getBeast "isRetiredPostNgeBeastMasterPlayer(player)" "callable.getCallable") -and
    (Is-Before $createBeast "isRetiredPostNgeBeastMasterPlayer(player)" "isBeastMaster(player)") -and
    $verifyBeast.Contains("retirePostNgeBeastMasterPlayerState(player)")
) "p14.beast-retirement.central-entrypoints-fail-closed"

$basePlayer = [string]$sourceTexts["player/base/base_player.java"]
$baseInitialize = Get-SourceSlice $basePlayer "public int OnInitialize(" 'LOG("base_player - OnInitialize"'
Assert-Contract (
    $baseInitialize.Contains("beast_lib.retirePostNgeBeastMasterPlayerState(self)") -and
    (Is-Before $baseInitialize "beast_lib.retirePostNgeBeastMasterPlayerState(self)" 'attachScript(self, "systems.skills.stealth.player_stealth")') -and
    -not $basePlayer.Contains("beast_lib.verifyAndUpdateCalledBeastStats(self)") -and
    ([regex]::Matches($basePlayer, [regex]::Escape("beast_lib.retirePostNgeBeastMasterPlayerState(self)")).Count -eq 3)
) "p14.beast-retirement.player-lifecycle-cleanup"

$bcd = [string]$sourceTexts["ai/beast_control_device.java"]
$menuRequest = Get-SourceSlice $bcd "public int OnObjectMenuRequest(" "public int OnObjectMenuSelect("
$menuSelect = Get-SourceSlice $bcd "public int OnObjectMenuSelect(" "public int handleBeastStuffingConfirm("
Assert-Contract (
    (Is-Before $menuRequest "isRetiredPostNgeBeastMasterPlayer(player)" "mi.addRootMenu") -and
    $menuRequest.Contains("return SCRIPT_CONTINUE;") -and
    (Is-Before $menuSelect "isRetiredPostNgeBeastMasterPlayer(player)" "getLevel(player)") -and
    $menuSelect.Contains("return SCRIPT_OVERRIDE;")
) "p14.beast-retirement.control-device-ui-and-call-fail-closed"
Assert-Contract (
    $menuSelect.Contains("getLevel(player) < beastLevel - beast_lib.BEAST_LEVEL_MAX_DIFFERENCE") -and
    (Is-Before $menuSelect "isRetiredPostNgeBeastMasterPlayer(player)" "getLevel(player)")
) "p14.beast-retirement.nge-level-rule-retained-but-unreachable"

$playerBeastMaster = [string]$sourceTexts["player/player_beastmaster.java"]
$attach = Get-SourceSlice $playerBeastMaster "public int OnAttach(" "public int OnInitialize("
$initialize = Get-SourceSlice $playerBeastMaster "public int OnInitialize(" "public int handleRetirePostNgeBeastMasterPlayerState("
$detachCallback = Get-SourceSlice $playerBeastMaster "public int handleRetirePostNgeBeastMasterPlayerState(" "public int OnRemovingFromWorld("
Assert-Contract (
    $attach.Contains('messageTo(self, "handleRetirePostNgeBeastMasterPlayerState"') -and
    $initialize.Contains("beast_lib.retirePostNgeBeastMasterPlayerState(self)") -and
    $initialize.Contains("return SCRIPT_OVERRIDE;") -and
    $detachCallback.Contains("beast_lib.retirePostNgeBeastMasterPlayerState(self)")
) "p14.beast-retirement.persisted-script-self-detaches"

$combatBase = [string]$sourceTexts["systems/combat/combat_base.java"]
$combatGate = Get-SourceSlice $combatBase `
    "public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar" `
    "if (weapons.checkForIllegalStorytellerWeapon"
Assert-Contract (
    $combatBase.Contains("public static boolean isRetiredPostNgeBeastMasterPlayerAction") -and
    $combatBase.Contains("beast_lib.isRetiredPostNgeBeastMasterPlayerAction(self, actionName)") -and
    (Is-Before $combatGate "isRetiredPostNgeBeastMasterPlayerAction(self, actionName)" 'combat.revealPrecuFeignDeath(self, "combatCommand")')
) "p14.beast-retirement.standard-combat-gate"

$combatActions = [string]$sourceTexts["systems/combat/combat_actions.java"]
$handlerMatches = [regex]::Matches($combatActions, '(?ms)^\s*public int (bm_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)')
$standardHandlers = 0
$coveredHandlers = 0
foreach ($match in $handlerMatches)
{
    $body = $match.Value
    if ($body.Contains("combatStandardAction("))
    {
        $standardHandlers++
        $coveredHandlers++
    }
    elseif ($match.Groups[1].Value -ceq "bm_paralytic_poison_recourse" -and
        $body.Contains("beast_lib.isRetiredPostNgeBeastMasterPlayer(self)") -and
        $body.Contains("return SCRIPT_OVERRIDE;"))
    {
        $coveredHandlers++
    }
}
Assert-Contract (
    $handlerMatches.Count -eq [int]$contract.expected.bmActionHandlers -and
    $standardHandlers -eq [int]$contract.expected.standardActionHandlersGated -and
    $coveredHandlers -eq $handlerMatches.Count
) "p14.beast-retirement.all-bm-action-handlers-covered"

$skills = Import-Csv -LiteralPath (Join-Path $sharedRoot "skill/skills.tab") -Delimiter ([char]9)
$commands = Import-Csv -LiteralPath (Join-Path $sharedRoot "command/command_table.tab") -Delimiter ([char]9)
$combatRows = Import-Csv -LiteralPath (Join-Path $sharedRoot "combat/combat_data.tab") -Delimiter ([char]9)
$expertiseBm = @($skills | Where-Object { $_.NAME -like "expertise_bm_*" })
$bmCommands = @($commands | Where-Object { $_.commandName -like "bm_*" })
$bmCombatRows = @($combatRows | Where-Object { $_.actionName -like "bm_*" })
Assert-Contract (
    $expertiseBm.Count -eq [int]$contract.expected.expertiseBmCompatibilityRows -and
    $bmCommands.Count -eq [int]$contract.expected.bmCommandCompatibilityRows -and
    $bmCombatRows.Count -eq [int]$contract.expected.bmCombatDataCompatibilityRows
) "p14.beast-retirement.compatibility-data-retained"

foreach ($entry in $contract.continuityEvidence.precuCreatureHandlerSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $entry.Name
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$entry.Value) "p14.beast-retirement.precu-pet-source.$($entry.Name).unchanged"
}
$petLibrary = Get-Content -LiteralPath (Join-Path $scriptRoot "library/pet_lib.java") -Raw
Assert-Contract (
    $petLibrary.Contains('getSkillStatMod(player, "tame_level")') -and
    $petLibrary.Contains('getSkillStatMod(player, "tame_aggro")') -and
    $petLibrary.Contains('hasSkill(player, "outdoors_creaturehandler_novice")') -and
    -not $patchText.Contains("library/pet_lib.java") -and
    -not $patchText.Contains("ai/pet_control_device.java") -and
    -not $patchText.Contains("player/skill/taming.java")
) "p14.beast-retirement.precu-creature-handler-authority-preserved"
$petMaster = Get-Content -LiteralPath (Join-Path $scriptRoot "ai/pet_master.java") -Raw
Assert-Contract (
    $petMaster.Contains("public int emboldenPets(") -and
    $petMaster.Contains('PRECU_EMBOLDEN_BUFF = "emboldenPet"') -and
    -not $patchText.Contains("ai/pet_master.java")
) "p14.beast-retirement.precu-emboldenpets-preserved"

foreach ($entry in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $entry.Name
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$entry.Value) "p14.beast-retirement.mission-source.$($entry.Name).unchanged"
}
Assert-Contract (-not $patchText.Contains("systems/missions/") -and -not $patchText.Contains("library/missions.java")) `
    "p14.beast-retirement.mission-core-continuity"

Assert-Contract (
    @("implemented-build-pending", "ready") -ccontains [string]$contract.status
) "p14.beast-retirement.contract.status"

if ($failures.Count -gt 0)
{
    throw "P14 post-NGE Beast Master player-runtime retirement contract failed: $($failures -join ', ')"
}

Write-Host "P14 post-NGE Beast Master player-runtime retirement contract passed."
