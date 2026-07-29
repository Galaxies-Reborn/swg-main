param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3StrafeShotOne)
) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 |
        ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
$paths = @{
    base = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M274 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "strafeShot1")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "strafeShot1" -and
    $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and
    $command[0].'L:kneeling' -ceq "1" -and
    $command[0].'L:prone' -ceq "1" -and
    $command[0].'S:berserk' -ceq "0" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "RIFLE") `
    "strafeShot1 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)strafeShot1(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_rifleman_novice") `
    "strafeShot1 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "strafeShot1")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "fire_5_special_single" -and
    $combat[0].anim_rifle -ceq "fire_5_special_single" -and
    $combat[0].weaponType -ceq "RIFLE" -and
    $combat[0].specialLine -ceq "rifleman") `
    "strafeShot1 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "strafeShot1")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "0.5" -and
    $override[0].mindCostMultiplier -ceq "1.5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "2.0" -and
    $override[0].accuracyBonus -ceq "5" -and
    $override[0].animationType -ceq "RANGED" -and
    $override[0].stateEffect1 -ceq "REMOVE_COVER" -and
    $override[0].stateChance1 -ceq "75" -and
    $override[0].stateDuration1 -ceq "10") `
    "strafeShot1 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "strafeShot1")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "strafeshot") `
    "strafeShot1 spam row drifted"
$text = @{}
foreach ($key in @("base", "actions", "fixture")) {
    $text[$key] = Get-Content -LiteralPath $paths[$key] -Raw
}
foreach ($token in @(
    'PRECU_STATE_EFFECT_REMOVE_COVER', 'PRECU_NEXT_ATTACK_DELAY_UNTIL',
    'isPrecuNextAttackDelayed', 'strafe_system', '"BLOCKED"', '"EXPIRED"')) {
    Assert ($text.base.Contains($token)) "M274 combat runtime token missing: $token"
}
Assert ($text.actions -match 'public int strafeShot1\(' -and
    $text.actions -match '"strafeShot1", self, target') `
    "strafeShot1 production dispatcher is missing"
foreach ($token in @(
    'RIFLEMAN_NOVICE', 'STRAFE_SHOT_ONE_COMMAND',
    'ORIGINAL_STRAFE_SHOT_ONE_COMMAND', 'armStrafeCover',
    'probeStrafeDelay', 'canPerformStrafeShotOne=',
    'strafeShotOneHealthCost=', 'nextAttackDelayResult=')) {
    Assert ($text.fixture.Contains($token)) "M274 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/272-p14-core3-strafe-shot-one.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M274 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M274 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M274 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M274 runtime evidence is not passed"
}
Write-Host "Publish 14.1 Core3 strafeShot1 contract passed."
