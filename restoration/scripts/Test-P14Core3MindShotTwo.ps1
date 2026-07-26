param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3MindShotTwo)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M275 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "mindShot2")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "mindShot2" -and
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
    "mindShot2 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)mindShot2(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_rifleman_accuracy_01") `
    "mindShot2 retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "mindShot2")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "2" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "fire_1_special_single" -and
    $combat[0].anim_rifle -ceq "fire_1_special_single" -and
    $combat[0].weaponType -ceq "RIFLE" -and
    $combat[0].specialLine -ceq "rifleman" -and
    $combat[0].dotType -ceq "bleeding" -and
    $combat[0].dotIntensity -ceq "60" -and
    $combat[0].dotDuration -ceq "180") `
    "mindShot2 combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "mindShot2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "0.5" -and
    $override[0].mindCostMultiplier -ceq "1.5" -and
    $override[0].targetPool -ceq "MIND" -and
    $override[0].speedMultiplier -ceq "1.5" -and
    $override[0].accuracyBonus -ceq "5" -and
    $override[0].animationType -ceq "RANGED" -and
    $override[0].dotAttribute -ceq "MIND") `
    "mindShot2 override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "mindShot2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "mindbender") `
    "mindShot2 spam row drifted"
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int mindShot2\(' -and
    $actionsText -match '"mindShot2", self, target') `
    "mindShot2 production dispatcher is missing"
foreach ($token in @(
    'RIFLEMAN_ACCURACY_ONE', 'MIND_SHOT_TWO_COMMAND',
    'ORIGINAL_MIND_SHOT_TWO_COMMAND', 'canPerformMindShotTwo=',
    'mindShotTwoHealthCost=', 'mindShotTwoPrecuHamCostModel=',
    'mindShotTwoDotAttribute=', 'mindShotTwoDotIntensity=',
    'mindShotTwoDotDuration=', 'cleanupRiflemanSkills=')) {
    Assert ($fixtureText.Contains($token)) "M275 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/273-p14-core3-mind-shot-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M275 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M275 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M275 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M275 runtime evidence is not passed"
}
Write-Host "Publish 14.1 Core3 mindShot2 contract passed."
