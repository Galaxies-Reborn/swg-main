param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3SurpriseShot)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M276 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "surpriseShot")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "surpriseShot" -and
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
    "surpriseShot command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)surpriseShot(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_rifleman_accuracy_03") `
    "surpriseShot retained skill owner drifted"
$combat = @($combatRows | Where-Object actionName -ceq "surpriseShot")
Assert ($combat.Count -eq 1 -and
    $combat[0].percentAddFromWeapon -ceq "3" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].animDefault -ceq "fire_1_special_single" -and
    $combat[0].anim_rifle -ceq "fire_1_special_single" -and
    $combat[0].weaponType -ceq "RIFLE" -and
    $combat[0].specialLine -ceq "rifleman" -and
    [string]::IsNullOrEmpty([string]$combat[0].dotType)) `
    "surpriseShot combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "surpriseShot")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "0.5" -and
    $override[0].mindCostMultiplier -ceq "1.5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "3.0" -and
    $override[0].accuracyBonus -ceq "5" -and
    $override[0].animationType -ceq "RANGED" -and
    [string]::IsNullOrEmpty([string]$override[0].dotAttribute)) `
    "surpriseShot override row drifted"
$spam = @($spamRows | Where-Object actionName -ceq "surpriseShot")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "surpriseshot") `
    "surpriseShot spam row drifted"
$actionsText = Get-Content -LiteralPath $paths.actions -Raw
$fixtureText = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actionsText -match 'public int surpriseShot\(' -and
    $actionsText -match '"surpriseShot", self, target') `
    "surpriseShot production dispatcher is missing"
foreach ($token in @(
    'RIFLEMAN_ACCURACY_TWO', 'RIFLEMAN_ACCURACY_THREE',
    'SURPRISE_SHOT_COMMAND', 'ORIGINAL_SURPRISE_SHOT_COMMAND',
    'canPerformSurpriseShot=', 'surpriseShotHealthCost=',
    'surpriseShotPrecuHamCostModel=', 'cleanupRiflemanSkills=')) {
    Assert ($fixtureText.Contains($token)) "M276 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/274-p14-core3-surprise-shot.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) `
    "M276 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M276 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M276 build evidence is not passed"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M276 runtime evidence is not passed"
}
Write-Host "Publish 14.1 Core3 surpriseShot contract passed."
