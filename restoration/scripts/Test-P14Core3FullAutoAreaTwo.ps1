param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3FullAutoAreaTwo)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M272 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "fullAutoArea2")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "fullAutoArea2" -and
    $command[0].defaultTime -ceq "0.0" -and
    $command[0].executeTime -ceq "0.0" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "CARBINE") `
    "fullAutoArea2 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)fullAutoArea2(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_carbine_support_03") `
    "fullAutoArea2 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "fullAutoArea2")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2" -and
    $combat[0].attackType -ceq "CONE" -and
    $combat[0].coneLength -ceq "64" -and
    $combat[0].coneWidth -ceq "30" -and
    $combat[0].animDefault -ceq "fire_area" -and
    $combat[0].anim_carbine -ceq "fire_area" -and
    $combat[0].weaponType -ceq "CARBINE") `
    "fullAutoArea2 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "fullAutoArea2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "2.5" -and
    $override[0].actionCostMultiplier -ceq "2.5" -and
    $override[0].mindCostMultiplier -ceq "0.5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "1.5" -and
    $override[0].accuracyBonus -ceq "25" -and
    $override[0].animationType -ceq "INTENSITY" -and
    $override[0].stateEffect1 -ceq "DIZZY" -and
    $override[0].stateChance1 -ceq "30" -and
    $override[0].stateDuration1 -ceq "30" -and
    $override[0].stateEffect2 -ceq "BLIND" -and
    $override[0].stateChance2 -ceq "30" -and
    $override[0].stateDuration2 -ceq "40" -and
    $override[0].stateEffect3 -ceq "STUN" -and
    $override[0].stateChance3 -ceq "30" -and
    $override[0].stateDuration3 -ceq "30") `
    "fullAutoArea2 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "fullAutoArea2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "a_auto") `
    "fullAutoArea2 spam row drifted"
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int fullAutoArea2\(' -and
    $actionsText -match '"fullAutoArea2", self, target') `
    "fullAutoArea2 production dispatcher is missing"
foreach ($token in @(
    'CARBINE_SUPPORT_THREE', 'FULL_AUTO_AREA_TWO_COMMAND',
    'ORIGINAL_FULL_AUTO_AREA_TWO_COMMAND', 'retryCarbineRestoration',
    'fullAutoAreaTwoCommand=', 'canPerformFullAutoAreaTwo=',
    'fullAutoAreaTwoHealthCost=', 'fullAutoAreaTwoPrecuHamCostModel=')) {
    Assert ($fixtureText.Contains($token)) "M272 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/270-p14-core3-full-auto-area-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M272 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M272 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M272 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M272 runtime evidence is not passed"
}
Write-Host "Publish 14.1 Core3 fullAutoArea2 contract passed."
