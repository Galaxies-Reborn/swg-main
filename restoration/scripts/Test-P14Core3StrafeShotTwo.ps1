param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3StrafeShotTwo)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M281 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "strafeShot2")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "strafeShot2" -and
    $command[0].defaultPriority -ceq "normal" -and
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
    "strafeShot2 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)strafeShot2(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_rifleman_master" -and
    $owners[0].SKILLS_REQUIRED -ceq
        "combat_rifleman_accuracy_04,combat_rifleman_speed_04,combat_rifleman_ability_04,combat_rifleman_support_04") `
    "strafeShot2 retained master ownership drifted"
$combat = @($combatRows | Where-Object actionName -ceq "strafeShot2")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "5.0" -and
    $combat[0].attackType -ceq "CONE" -and
    $combat[0].coneLength -ceq "64" -and
    $combat[0].coneWidth -ceq "60" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "fire_area" -and
    $combat[0].anim_rifle -ceq "fire_area" -and
    $combat[0].weaponType -ceq "RIFLE" -and
    $combat[0].specialLine -ceq "rifleman") `
    "strafeShot2 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "strafeShot2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "0.5" -and
    $override[0].mindCostMultiplier -ceq "2.0" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "2.0" -and
    $override[0].accuracyBonus -ceq "5" -and
    $override[0].animationType -ceq "INTENSITY" -and
    $override[0].stateEffect1 -ceq "REMOVE_COVER" -and
    $override[0].stateChance1 -ceq "75" -and
    $override[0].stateStrength1 -ceq "0" -and
    $override[0].stateDuration1 -ceq "10") `
    "strafeShot2 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "strafeShot2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "advancedstrafe") `
    "strafeShot2 spam row drifted"
$text = @{}
foreach ($key in @("base", "actions", "fixture")) {
    $text[$key] = Get-Content -LiteralPath $paths[$key] -Raw
}
foreach ($token in @(
    'PRECU_STATE_EFFECT_REMOVE_COVER', 'PRECU_NEXT_ATTACK_DELAY_UNTIL',
    'stateEffect.appliedTotal', 'appliedRoll', 'appliedStateBefore',
    'isPrecuNextAttackDelayed', 'strafe_system', '"BLOCKED"', '"EXPIRED"')) {
    Assert ($text.base.Contains($token)) "M281 combat runtime token missing: $token"
}
Assert ($text.actions -match 'public int strafeShot2\(' -and
    $text.actions -match '"strafeShot2", self, target') `
    "strafeShot2 production dispatcher is missing"
foreach ($token in @(
    'RIFLEMAN_SPEED_FOUR', 'RIFLEMAN_ABILITY_FOUR',
    'RIFLEMAN_SUPPORT_FOUR', 'RIFLEMAN_MASTER',
    'STRAFE_SHOT_TWO_COMMAND', 'ORIGINAL_STRAFE_SHOT_TWO_COMMAND',
    'armStrafeCover', 'probeStrafeDelay', 'riflemanMaster=',
    'canPerformStrafeShotTwo=', 'strafeShotTwoHealthCost=',
    'strafeShotTwoDamageMultiplier=', 'stateEffectAppliedTotal=',
    'stateEffect1AppliedRoll=')) {
    Assert ($text.fixture.Contains($token)) "M281 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/279-p14-core3-strafe-shot-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M281 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M281 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") `
        "M281 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") `
        "M281 runtime evidence is not passed"
    Assert ([int]$contract.runtimeEvidence.removeCover.cumulativeApplied -eq 1) `
        "M281 successful cover application is not ready"
    Assert ([string]$contract.runtimeEvidence.removeCover.blockedResult -ceq "BLOCKED") `
        "M281 delay block evidence is not ready"
    Assert ([string]$contract.runtimeEvidence.removeCover.expiredResult -ceq "EXPIRED") `
        "M281 delay expiry evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.persistence.diagnosticEvidenceSurvived) `
        "M281 restart persistence evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) `
        "M281 cleanup evidence is not idempotent"
}
Write-Host "Publish 14.1 Core3 strafeShot2 contract passed."
