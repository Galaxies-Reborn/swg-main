param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3WildShotTwo)
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
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M269 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "wildShot2")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "wildShot2" -and
    $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "CARBINE") `
    "wildShot2 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)wildShot2(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_carbine_accuracy_04") `
    "wildShot2 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "wildShot2")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "3.0" -and
    $combat[0].attackType -ceq "CONE" -and
    $combat[0].coneLength -ceq "64" -and
    $combat[0].coneWidth -ceq "30" -and
    $combat[0].animDefault -ceq "fire_7_single" -and
    $combat[0].weaponType -ceq "CARBINE") `
    "wildShot2 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "wildShot2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "2.0" -and
    $override[0].actionCostMultiplier -ceq "1.25" -and
    $override[0].mindCostMultiplier -ceq ".5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "2" -and
    $override[0].accuracyBonus -ceq "25" -and
    $override[0].animationType -ceq "RANGED" -and
    $override[0].stateEffect1 -ceq "STUN" -and
    $override[0].stateChance1 -ceq "50" -and
    $override[0].stateStrength1 -ceq "0" -and
    $override[0].stateDuration1 -ceq "30" -and
    $override[0].stateDefense1 -ceq "stun_defense" -and
    $override[0].stateJediDefense1 -ceq "jedi_state_defense" -and
    $override[0].stateResistance1 -ceq "resistance_states") `
    "wildShot2 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "wildShot2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "widewildshot") `
    "wildShot2 spam row drifted"
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int wildShot2\(' -and
    $actionsText -match 'combatStandardAction\("wildShot2"') `
    "wildShot2 production dispatcher is missing"
foreach ($token in @(
    'CARBINE_ACCURACY_FOUR', 'WILD_SHOT_TWO_COMMAND',
    'ORIGINAL_WILD_SHOT_TWO_COMMAND', 'retryCarbineRestoration',
    'wildShotTwoCommand=', 'canPerformWildShotTwo=',
    'wildShotTwoHealthCost=', 'wildShotTwoPrecuHamCostModel=')) {
    Assert ($fixtureText.Contains($token)) "M269 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/267-p14-core3-wild-shot-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M269 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M269 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M269 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M269 runtime evidence is not passed"
}
Write-Host "Publish 14.1 Core3 wildShot2 contract passed."
