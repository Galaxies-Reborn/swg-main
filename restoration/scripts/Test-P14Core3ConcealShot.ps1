param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3ConcealShot)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M278 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "concealShot")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "concealShot" -and
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
    "concealShot command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)concealShot(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_rifleman_speed_01") `
    "concealShot retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "concealShot")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2.5" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "fire_1_special_single" -and
    $combat[0].anim_rifle -ceq "fire_1_special_single" -and
    $combat[0].weaponType -ceq "RIFLE" -and
    $combat[0].specialLine -ceq "rifleman") `
    "concealShot combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "concealShot")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "0.5" -and
    $override[0].mindCostMultiplier -ceq "1.5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "2.0" -and
    $override[0].accuracyBonus -ceq "5" -and
    $override[0].animationType -ceq "RANGED") `
    "concealShot override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "concealShot")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "concealedshot") `
    "concealShot spam row drifted"
$baseText = Get-Content -LiteralPath $paths.base -Raw
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int concealShot\(' -and
    $actionsText -match 'combatStandardAction\("concealShot", self, target') `
    "concealShot production dispatcher is missing"
foreach ($token in @(
    'applyPrecuConcealThreat', 'combat.precuConcealMiss.',
    'combatResult == COMBAT_RESULT_MISS', 'distance >= 40.0f',
    'posture == POSTURE_PRONE ? 3', 'posture == POSTURE_CROUCHED ? 2',
    'posture == POSTURE_UPRIGHT ? 1', 'removeHateTarget(defender, attacker)',
    'conceal.hateAfter', 'conceal.result')) {
    Assert ($baseText.Contains($token)) "M278 concealment token missing: $token"
}
foreach ($token in @(
    'RIFLEMAN_SPEED_ONE', 'CONCEAL_SHOT_COMMAND', 'armConceal',
    'CONCEAL_TARGET_CREATURE = "worrt"', 'getHeightAtLocation',
    'canSee(attacker, candidate)', 'pvpSetAttackableOverride(target, true)',
    'create.initializeCreature', 'destroyFixtureConcealTarget')) {
    Assert ($fixtureText.Contains($token)) "M278 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/276-p14-core3-conceal-shot.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M278 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M278 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M278 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M278 runtime evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.concealmentResult.result -ceq "REMOVED") `
        "M278 threat-removal evidence is not ready"
    Assert ([double]$contract.runtimeEvidence.concealmentResult.hateAfter -eq 0.0) `
        "M278 final hate evidence is not zero"
    Assert ([bool]$contract.runtimeEvidence.persistence.diagnosticEvidenceSurvived) `
        "M278 restart persistence evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.cleanup.idempotent) `
        "M278 cleanup evidence is not idempotent"
}
Write-Host "Publish 14.1 Core3 concealShot contract passed."
