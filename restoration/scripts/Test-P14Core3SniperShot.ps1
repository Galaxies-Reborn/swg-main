param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3SniperShot)
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
    engine = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/combat_engine.java"
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M277 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "sniperShot")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "sniperShot" -and
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
    "sniperShot command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)sniperShot(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_rifleman_accuracy_04") `
    "sniperShot retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "sniperShot")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "1" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "fire_1_special_single_medium_face" -and
    $combat[0].anim_rifle -ceq "fire_1_special_single_medium_face" -and
    $combat[0].weaponType -ceq "RIFLE" -and
    $combat[0].specialLine -ceq "rifleman" -and
    [string]::IsNullOrEmpty([string]$combat[0].dotType)) `
    "sniperShot combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "sniperShot")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "0.5" -and
    $override[0].mindCostMultiplier -ceq "2.0" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "1.0" -and
    $override[0].accuracyBonus -ceq "5" -and
    $override[0].animationType -ceq "NONE" -and
    $override[0].hitIncapacitatedTarget -ceq "1" -and
    $override[0].fixedMinDamage -ceq "135" -and
    $override[0].fixedMaxDamage -ceq "135" -and
    $override[0].dotAttribute -ceq "NONE") `
    "sniperShot override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "sniperShot")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "snipershot") `
    "sniperShot spam row drifted"
$engineText = Get-Content -LiteralPath $paths.engine -Raw
$baseText = Get-Content -LiteralPath $paths.base -Raw
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @(
    'precuHitIncapacitatedTarget', 'precuFixedMinDamage',
    'precuFixedMaxDamage')) {
    Assert ($engineText.Contains($token)) "M277 combat-engine token missing: $token"
}
Assert ($baseText.Contains('actionData.precuHitIncapacitatedTarget == 0') -and
    $baseText.Contains('actionData.precuFixedMinDamage') -and
    $baseText.Contains('minDamage != maxDamage')) `
    "M277 combat-base admission or fixed-damage primitive is missing"
Assert ($actionsText -match 'public int sniperShot\(' -and
    $actionsText -match '"sniperShot", self, target' -and
    $actionsText -match 'pclib\.killPlayer\(target, self, true\)') `
    "sniperShot production dispatcher or deathblow branch is missing"
foreach ($token in @(
    'RIFLEMAN_ACCURACY_FOUR', 'SNIPER_SHOT_COMMAND',
    'ORIGINAL_SNIPER_SHOT_COMMAND', 'canPerformSniperShot=',
    'sniperShotHealthCost=', 'sniperShotFixedMinDamage=',
    'sniperShotHitIncapacitatedTarget=', 'cleanupRiflemanSkills=')) {
    Assert ($fixtureText.Contains($token)) "M277 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/275-p14-core3-sniper-shot.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M277 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M277 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M277 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M277 runtime evidence is not passed"
    Assert ([bool]$contract.runtimeEvidence.incapacitatedTargetResult.endingDead) `
        "M277 deathblow evidence is not ready"
    Assert ([bool]$contract.runtimeEvidence.incapacitatedTargetResult.beenCoupDeGraced) `
        "M277 coup-de-grace marker evidence is not ready"
}
Write-Host "Publish 14.1 Core3 sniperShot contract passed."
