param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3SuppressionFireTwo)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M267 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "suppressionFire2")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "suppressionFire2" -and
    $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "CARBINE") `
    "suppressionFire2 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)suppressionFire2(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_carbine_ability_04") `
    "suppressionFire2 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "suppressionFire2")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2.5" -and
    $combat[0].animDefault -ceq "fire_defender_posture_change_down" -and
    $combat[0].weaponType -ceq "CARBINE") `
    "suppressionFire2 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "suppressionFire2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "2" -and
    $override[0].actionCostMultiplier -ceq "1.25" -and
    $override[0].mindCostMultiplier -ceq ".5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "1.5" -and
    $override[0].accuracyBonus -ceq "25" -and
    $override[0].animationType -ceq "NONE" -and
    $override[0].postureDownChance -ceq "100") `
    "suppressionFire2 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "suppressionFire2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "sup_fire") `
    "suppressionFire2 spam row drifted"
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int suppressionFire2\(' -and
    $actionsText -match 'combatStandardAction\("suppressionFire2"') `
    "suppressionFire2 production dispatcher is missing"
foreach ($token in @(
    'CARBINE_ABILITY_ONE', 'CARBINE_ABILITY_THREE',
    'CARBINE_ABILITY_FOUR', 'SUPPRESSION_FIRE_TWO_COMMAND',
    'ORIGINAL_CARBINE_ABILITY_FOUR', 'ORIGINAL_SUPPRESSION_FIRE_TWO_COMMAND',
    'retryCarbineRestoration',
    'suppressionFireTwoCommand=', 'canPerformSuppressionFireTwo=',
    'suppressionFireTwoHealthCost=', 'suppressionFireTwoPostureDownChance=')) {
    Assert ($fixtureText.Contains($token)) "M267 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/265-p14-core3-suppression-fire-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M267 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M267 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M267 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M267 runtime evidence is not passed"
}
Write-Host "Publish 14.1 Core3 suppressionFire2 contract passed."
