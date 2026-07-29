param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PolearmStunOne)) -Raw | ConvertFrom-Json
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
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M292 source: $path" }
$command = @(Rows $paths.command | Where-Object commandName -ceq "polearmStun1")
Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq "polearmStun1" -and $command[0].defaultPriority -ceq "normal" -and $command[0].defaultTime -ceq "1.5" -and $command[0].executeTime -ceq "1.5" -and $command[0].'L:kneeling' -ceq "1" -and $command[0].'L:prone' -ceq "1" -and $command[0].'S:berserk' -ceq "0" -and $command[0].target -ceq "other" -and $command[0].targetType -ceq "optional" -and $command[0].commandGroup -ceq "391413347" -and $command[0].maxRangeToTarget -ceq "0" -and $command[0].addToCombatQueue -ceq "1" -and $command[0].validWeapon -ceq "POLEARM") "polearmStun1 command row drifted"
$owners = @(Rows $paths.skills | Where-Object { [string]$_.COMMANDS -match "(^|,)polearmStun1(,|$)" })
Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_brawler_polearm_03" -and $owners[0].PARENT -ceq "combat_brawler_polearm_02") "polearmStun1 owner drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -ceq "polearmStun1")
Assert ($combat.Count -eq 1 -and $combat[0].percentAddFromWeapon -ceq "1.5" -and $combat[0].attackType -ceq "SINGLE_TARGET" -and $combat[0].maxRange -ceq "3" -and $combat[0].animDefault -ceq "combo_4a" -and $combat[0].anim_onehandmelee -ceq "" -and $combat[0].anim_twohandmelee -ceq "" -and $combat[0].anim_polearm -ceq "combo_4a" -and $combat[0].weaponType -ceq "POLEARM" -and $combat[0].specialLine -ceq "brawler") "polearmStun1 combat row drifted"
$override = @(Rows $paths.override | Where-Object actionName -ceq "polearmStun1")
Assert ($override.Count -eq 1 -and $override[0].healthCostMultiplier -ceq "1.0" -and $override[0].actionCostMultiplier -ceq "0.5" -and $override[0].mindCostMultiplier -ceq "0.5" -and $override[0].targetPool -ceq "RANDOM" -and $override[0].speedMultiplier -ceq "1.5" -and $override[0].accuracyBonus -ceq "10" -and $override[0].animationType -ceq "INTENSITY" -and $override[0].stateEffect1 -ceq "STUN" -and $override[0].stateChance1 -ceq "100" -and $override[0].stateDuration1 -ceq "30" -and $override[0].stateDefense1 -ceq "stun_defense") "polearmStun1 overrides drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -ceq "polearmStun1")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "breathtaker") "polearmStun1 spam drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains('public int polearmStun1(') -and $actions.Contains('"polearmStun1", self, target')) "polearmStun1 dispatcher missing"
foreach ($token in @('BRAWLER_POLEARM_ONE', 'BRAWLER_POLEARM_TWO', 'BRAWLER_POLEARM_THREE', 'POLEARM_STUN_ONE_COMMAND', 'ORIGINAL_POLEARM_STUN_ONE_COMMAND', 'polearmStunOneCanPerform=', 'polearmStunOneHealthCost=', 'polearmStunOneDamageMultiplier=')) { Assert ($fixture.Contains($token)) "M292 fixture token missing: $token" }
$overlay = Join-Path $restorationRoot "patches/dsrc/290-p14-core3-polearm-stun-one.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M292 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M292 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M292 build evidence failed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M292 runtime evidence failed"
    Assert ([string]$contract.runtimeEvidence.attack.stateEffect.result -ceq "APPLIED") "M292 STUN application missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.fullServerRestart) "M292 restart persistence missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.transientStunAbsent) "M292 transient STUN cleanup missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) "M292 cleanup idempotence missing"
}
Write-Output "Publish 14.1 Core3 polearmStun1 contract passed."
