param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3FlurryShotTwo)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M280 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "flurryShot2")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "flurryShot2" -and
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
    "flurryShot2 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)flurryShot2(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_rifleman_support_03") `
    "flurryShot2 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "flurryShot2")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2.5" -and
    $combat[0].attackType -ceq "CONE" -and
    $combat[0].coneLength -ceq "64" -and
    $combat[0].coneWidth -ceq "15" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "fire_area" -and
    $combat[0].anim_rifle -ceq "fire_area" -and
    $combat[0].weaponType -ceq "RIFLE" -and
    $combat[0].specialLine -ceq "rifleman") `
    "flurryShot2 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "flurryShot2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "0.5" -and
    $override[0].mindCostMultiplier -ceq "2.0" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "2.0" -and
    $override[0].accuracyBonus -ceq "5" -and
    $override[0].animationType -ceq "INTENSITY" -and
    $override[0].stateEffect1 -ceq "DIZZY" -and
    $override[0].stateChance1 -ceq "100" -and
    $override[0].stateStrength1 -ceq "0" -and
    $override[0].stateDuration1 -ceq "30" -and
    $override[0].stateDefense1 -ceq "dizzy_defense" -and
    $override[0].stateJediDefense1 -ceq "jedi_state_defense" -and
    $override[0].stateResistance1 -ceq "resistance_states") `
    "flurryShot2 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "flurryShot2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "flurry") `
    "flurryShot2 spam row drifted"
$baseText = Get-Content -LiteralPath $paths.base -Raw
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int flurryShot2\(' -and
    $actionsText -match 'combatStandardAction\("flurryShot2", self, target') `
    "flurryShot2 production dispatcher is missing"
foreach ($token in @(
    'applyPrecuStateEffect', 'PRECU_STATE_EFFECT_DIZZY',
    'buff.applyBuff(defender, attacker, buffName', 'stateEffect.appliedCount')) {
    Assert ($baseText.Contains($token)) "M280 state-effect token missing: $token"
}
foreach ($token in @(
    'RIFLEMAN_SUPPORT_ONE', 'RIFLEMAN_SUPPORT_TWO',
    'RIFLEMAN_SUPPORT_THREE', 'FLURRY_SHOT_TWO_COMMAND',
    'ORIGINAL_FLURRY_SHOT_TWO_COMMAND', 'flurryShotTwo=',
    'canPerformFlurryShotTwo=', 'flurryShotTwoHealthCost=',
    'flurryShotTwoDamageMultiplier=')) {
    Assert ($fixtureText.Contains($token)) "M280 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/278-p14-core3-flurry-shot-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M280 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M280 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") `
        "M280 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") `
        "M280 runtime evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.stateEffectResult.result -ceq "APPLIED") `
        "M280 dizzy application evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.stateEffectResult.timedRecoveryObserved) `
        "M280 timed recovery evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.persistence.diagnosticEvidenceSurvived) `
        "M280 restart persistence evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) `
        "M280 cleanup evidence is not idempotent"
}
Write-Host "Publish 14.1 Core3 flurryShot2 contract passed."
