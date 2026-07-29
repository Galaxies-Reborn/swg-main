param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3FullAutoSingleTwo)
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
    base = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M266 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$command = @($commands | Where-Object commandName -ceq "fullAutoSingle2")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "fullAutoSingle2" -and
    $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "CARBINE") `
    "fullAutoSingle2 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)fullAutoSingle2(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_carbine_novice") `
    "fullAutoSingle2 retained skill ownership drifted"
$combat = @($combatRows | Where-Object actionName -ceq "fullAutoSingle2")
Assert ($combat.Count -eq 1 -and
    $combat[0].animDefault -ceq "fire_7_single" -and
    $combat[0].anim_carbine -ceq "fire_7_single" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].percentAddFromWeapon -ceq "3.5" -and
    $combat[0].weaponType -ceq "CARBINE" -and
    $combat[0].weaponCategory -ceq "RANGED_WEAPON") `
    "fullAutoSingle2 combat-data row drifted"
$override = @($overrides | Where-Object actionName -ceq "fullAutoSingle2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "2" -and
    $override[0].actionCostMultiplier -ceq "2.5" -and
    $override[0].mindCostMultiplier -ceq ".5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "1.5" -and
    $override[0].accuracyBonus -ceq "25" -and
    $override[0].animationType -ceq "RANGED") `
    "fullAutoSingle2 combat override drifted"
$expectedStates = @(
    @("DIZZY","30","0","30","dizzy_defense"),
    @("BLIND","30","0","40","blind_defense"),
    @("STUN","30","0","30","stun_defense")
)
for ($slot = 1; $slot -le 3; ++$slot) {
    $expected = $expectedStates[$slot - 1]
    Assert (
        [string]$override[0].PSObject.Properties["stateEffect$slot"].Value -ceq $expected[0] -and
        [string]$override[0].PSObject.Properties["stateChance$slot"].Value -ceq $expected[1] -and
        [string]$override[0].PSObject.Properties["stateStrength$slot"].Value -ceq $expected[2] -and
        [string]$override[0].PSObject.Properties["stateDuration$slot"].Value -ceq $expected[3] -and
        [string]$override[0].PSObject.Properties["stateDefense$slot"].Value -ceq $expected[4] -and
        [string]$override[0].PSObject.Properties["stateJediDefense$slot"].Value -ceq "jedi_state_defense" -and
        [string]$override[0].PSObject.Properties["stateResistance$slot"].Value -ceq "resistance_states"
    ) "fullAutoSingle2 state slot $slot drifted"
}
$spam = @($spamRows | Where-Object actionName -ceq "fullAutoSingle2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "s_auto") `
    "fullAutoSingle2 combat spam drifted"
$sources = ($paths.actions, $paths.base, $paths.fixture |
    ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
foreach ($token in @(
    "public int fullAutoSingle2(",
    "applyPrecuStateEffects(",
    "PRECU_STATE_EFFECT_DIZZY",
    "PRECU_STATE_EFFECT_BLIND",
    "PRECU_STATE_EFFECT_STUN",
    "ORIGINAL_DIZZY_BUFF",
    "ORIGINAL_BLIND_BUFF",
    "ORIGINAL_STUN_BUFF",
    "ORIGINAL_CARBINE_NOVICE",
    "ORIGINAL_FULL_AUTO_SINGLE_TWO_COMMAND",
    "canPerformFullAutoSingleTwo",
    "fullAutoSingleTwoHealthCost"
)) {
    Assert ($sources.Contains($token)) "fullAutoSingle2 lifecycle drifted: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/264-p14-core3-full-auto-single-two.patch"
Assert ((Sha $overlay) -ceq [string]$contract.buildEvidence.overlaySha256) `
    "Overlay hash drifted"
$hashes = $contract.buildEvidence.sourceSha256
if ($null -ne $hashes) {
    foreach ($item in $hashes.PSObject.Properties) {
        Assert ((Sha $paths[$item.Name]) -ceq [string]$item.Value) `
            "Source hash drifted: $($item.Name)"
    }
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.persistence.observed -and
        [bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) "M266 is not Ready"
}
Write-Host "Publish 14.1 Core3 fullAutoSingle2 contract passed."
