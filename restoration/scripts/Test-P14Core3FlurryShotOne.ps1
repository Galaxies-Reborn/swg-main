param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3FlurryShotOne)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M279 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "flurryShot1")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "flurryShot1" -and
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
    "flurryShot1 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)flurryShot1(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_rifleman_support_01") `
    "flurryShot1 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "flurryShot1")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2.0" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "fire_5_special_single" -and
    $combat[0].anim_rifle -ceq "fire_5_special_single" -and
    $combat[0].weaponType -ceq "RIFLE" -and
    $combat[0].specialLine -ceq "rifleman") `
    "flurryShot1 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "flurryShot1")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "0.5" -and
    $override[0].mindCostMultiplier -ceq "1.5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "2.0" -and
    $override[0].accuracyBonus -ceq "5" -and
    $override[0].animationType -ceq "RANGED" -and
    $override[0].stateEffect1 -ceq "DIZZY" -and
    $override[0].stateChance1 -ceq "85" -and
    $override[0].stateStrength1 -ceq "0" -and
    $override[0].stateDuration1 -ceq "45" -and
    $override[0].stateDefense1 -ceq "dizzy_defense" -and
    $override[0].stateJediDefense1 -ceq "jedi_state_defense" -and
    $override[0].stateResistance1 -ceq "resistance_states") `
    "flurryShot1 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "flurryShot1")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "flurryshot") `
    "flurryShot1 spam row drifted"
$baseText = Get-Content -LiteralPath $paths.base -Raw
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int flurryShot1\(' -and
    $actionsText -match 'combatStandardAction\("flurryShot1", self, target') `
    "flurryShot1 production dispatcher is missing"
foreach ($token in @(
    'applyPrecuStateEffect', 'PRECU_STATE_EFFECT_DIZZY',
    'buff.applyBuff(defender, attacker, buffName', 'stateEffect.appliedCount')) {
    Assert ($baseText.Contains($token)) "M279 state-effect token missing: $token"
}
foreach ($token in @(
    'RIFLEMAN_SUPPORT_ONE', 'FLURRY_SHOT_ONE_COMMAND',
    'ORIGINAL_FLURRY_SHOT_ONE_COMMAND', 'flurryShotOne=',
    'canPerformFlurryShotOne=', 'flurryShotOneHealthCost=',
    'flurryShotOneDamageMultiplier=')) {
    Assert ($fixtureText.Contains($token)) "M279 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/277-p14-core3-flurry-shot-one.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M279 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M279 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") `
        "M279 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") `
        "M279 runtime evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.stateEffectResult.result -ceq "APPLIED") `
        "M279 dizzy application evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.stateEffectResult.timedRecoveryObserved) `
        "M279 timed recovery evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.persistence.diagnosticEvidenceSurvived) `
        "M279 restart persistence evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) `
        "M279 cleanup evidence is not idempotent"
}
Write-Host "Publish 14.1 Core3 flurryShot1 contract passed."
