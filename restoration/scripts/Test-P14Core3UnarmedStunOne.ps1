param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3UnarmedStunOne)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Rows([string]$Path) { $lines = Get-Content -LiteralPath $Path; $header = $lines[0] -split "`t", -1; @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header) }
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
$paths = @{
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M294 source: $path" }
$command = @(Rows $paths.command | Where-Object commandName -ceq "unarmedStun1")
Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq "unarmedStun1" -and $command[0].defaultPriority -ceq "normal" -and $command[0].defaultTime -ceq "1.5" -and $command[0].executeTime -ceq "1.5" -and $command[0].'L:kneeling' -ceq "1" -and $command[0].'L:prone' -ceq "1" -and $command[0].'S:berserk' -ceq "0" -and $command[0].target -ceq "other" -and $command[0].targetType -ceq "optional" -and $command[0].commandGroup -ceq "391413347" -and $command[0].maxRangeToTarget -ceq "0" -and $command[0].addToCombatQueue -ceq "1" -and $command[0].validWeapon -ceq "UNARMED") "unarmedStun1 command row drifted"
$owners = @(Rows $paths.skills | Where-Object { [string]$_.COMMANDS -match "(^|,)unarmedStun1(,|$)" })
Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_brawler_unarmed_02" -and $owners[0].PARENT -ceq "combat_brawler_unarmed_01") "unarmedStun1 owner drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -ceq "unarmedStun1")
Assert ($combat.Count -eq 1 -and $combat[0].percentAddFromWeapon -ceq "1.25" -and $combat[0].attackType -ceq "SINGLE_TARGET" -and $combat[0].maxRange -ceq "5" -and $combat[0].animDefault -ceq "combo_4c" -and $combat[0].anim_unarmed -ceq "combo_4c" -and $combat[0].weaponType -ceq "UNARMED" -and $combat[0].specialLine -ceq "brawler") "unarmedStun1 combat row drifted"
$override = @(Rows $paths.override | Where-Object actionName -ceq "unarmedStun1")
Assert ($override.Count -eq 1 -and $override[0].healthCostMultiplier -ceq "1.5" -and $override[0].actionCostMultiplier -ceq "1.5" -and $override[0].mindCostMultiplier -ceq "1.5" -and $override[0].targetPool -ceq "RANDOM" -and $override[0].speedMultiplier -ceq "2.0" -and $override[0].accuracyBonus -ceq "15" -and $override[0].animationType -ceq "INTENSITY" -and $override[0].stateEffect1 -ceq "STUN" -and $override[0].stateChance1 -ceq "100" -and $override[0].stateStrength1 -ceq "0" -and $override[0].stateDuration1 -ceq "60" -and $override[0].stateDefense1 -ceq "stun_defense" -and $override[0].stateJediDefense1 -ceq "jedi_state_defense" -and $override[0].stateResistance1 -ceq "resistance_states") "unarmedStun1 overrides drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -ceq "unarmedStun1")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "screamingsquill") "unarmedStun1 spam drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains('public int unarmedStun1(') -and $actions.Contains('"unarmedStun1", self, target')) "unarmedStun1 dispatcher missing"
foreach ($token in @('BRAWLER_UNARMED_ONE', 'BRAWLER_UNARMED_TWO', 'UNARMED_STUN_ONE_COMMAND', 'ORIGINAL_UNARMED_STUN_ONE_COMMAND', 'unarmedStunOneCanPerform=', 'unarmedStunOneHealthCost=', 'unarmedStunOneDamageMultiplier=')) { Assert ($fixture.Contains($token)) "M294 fixture token missing: $token" }
$overlay = Join-Path $restorationRoot "patches/dsrc/292-p14-core3-unarmed-stun-one.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M294 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M294 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M294 build evidence failed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M294 runtime evidence failed"
    Assert ([string]$contract.runtimeEvidence.attack.stateEffect.result -ceq "APPLIED") "M294 STUN application missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.fullServerRestart) "M294 restart persistence missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.transientStunAbsent) "M294 transient STUN cleanup missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) "M294 cleanup idempotence missing"
}
Write-Output "Publish 14.1 Core3 unarmedStun1 contract passed."
