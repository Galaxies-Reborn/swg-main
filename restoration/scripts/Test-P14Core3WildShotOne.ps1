param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3WildShotOne)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M268 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "wildShot1")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "wildShot1" -and
    $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "CARBINE") `
    "wildShot1 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)wildShot1(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_carbine_accuracy_02") `
    "wildShot1 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "wildShot1")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2.25" -and
    $combat[0].animDefault -ceq "fire_7_single" -and
    $combat[0].weaponType -ceq "CARBINE") `
    "wildShot1 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "wildShot1")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "1.75" -and
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
    "wildShot1 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "wildShot1")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "wildshot") `
    "wildShot1 spam row drifted"
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int wildShot1\(' -and
    $actionsText -match 'combatStandardAction\("wildShot1"') `
    "wildShot1 production dispatcher is missing"
foreach ($token in @(
    'CARBINE_ACCURACY_ONE', 'CARBINE_ACCURACY_TWO',
    'WILD_SHOT_ONE_COMMAND', 'ORIGINAL_WILD_SHOT_ONE_COMMAND',
    'retryCarbineRestoration',
    'wildShotOneCommand=', 'canPerformWildShotOne=',
    'wildShotOneHealthCost=', 'wildShotOnePrecuHamCostModel=')) {
    Assert ($fixtureText.Contains($token)) "M268 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/266-p14-core3-wild-shot-one.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M268 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M268 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M268 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M268 runtime evidence is not passed"
}
Write-Host "Publish 14.1 Core3 wildShot1 contract passed."
