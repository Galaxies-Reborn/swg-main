param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3ChargeShotTwo)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M273 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "chargeShot2")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "chargeShot2" -and
    $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and
    $command[0].'L:kneeling' -ceq "0" -and
    $command[0].'L:prone' -ceq "0" -and
    $command[0].'S:berserk' -ceq "0" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "CARBINE") `
    "chargeShot2 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)chargeShot2(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_carbine_support_04") `
    "chargeShot2 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "chargeShot2")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2.5" -and
    $combat[0].attackType -ceq "CONE" -and
    $combat[0].coneLength -ceq "64" -and
    $combat[0].coneWidth -ceq "30" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "charge" -and
    [string]::IsNullOrEmpty($combat[0].anim_carbine) -and
    $combat[0].weaponType -ceq "CARBINE") `
    "chargeShot2 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "chargeShot2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "1.5" -and
    $override[0].mindCostMultiplier -ceq "0.5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "2.0" -and
    $override[0].accuracyBonus -ceq "25" -and
    $override[0].animationType -ceq "NONE" -and
    $override[0].postureDownChance -ceq "" -and
    $override[0].knockdownChance -ceq "100") `
    "chargeShot2 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "chargeShot2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "chargeblast") `
    "chargeShot2 spam row drifted"
$text = @{}
foreach ($key in @("engine", "base", "actions", "fixture")) {
    $text[$key] = Get-Content -LiteralPath $paths[$key] -Raw
}
foreach ($token in @('precuKnockdownChance', 'knockdownChance')) {
    Assert ($text.engine.Contains($token)) "M273 combat engine token missing: $token"
}
foreach ($token in @(
    'PRECU_KNOCKDOWN_RECOVERY', 'PRECU_KNOCKDOWN_ORIGINAL_POSTURE',
    'applyPrecuKnockdown', 'knockdown_defense', 'knockdown.result')) {
    Assert ($text.base.Contains($token)) "M273 combat runtime token missing: $token"
}
Assert ($text.actions -match 'public int chargeShot2\(' -and
    $text.actions -match '"chargeShot2", self, target') `
    "chargeShot2 production dispatcher is missing"
foreach ($token in @(
    'CARBINE_SUPPORT_FOUR', 'CHARGE_SHOT_TWO_COMMAND',
    'ORIGINAL_CHARGE_SHOT_TWO_COMMAND', 'chargeShotTwoCommand=',
    'canPerformChargeShotTwo=', 'chargeShotTwoHealthCost=',
    'chargeShotTwoKnockdownChance=', 'diagnosticKnockdownResult=')) {
    Assert ($text.fixture.Contains($token)) "M273 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/271-p14-core3-charge-shot-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M273 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M273 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M273 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M273 runtime evidence is not passed"
}
Write-Host "Publish 14.1 Core3 chargeShot2 contract passed."
