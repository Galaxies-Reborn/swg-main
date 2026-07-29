param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3LegShotContinuation)
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M265 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$expected = @{
    legShot2 = @{ owner="combat_marksman_carbine_03"; health=".5"; action="1.5";
        mind="1.5"; chance="85"; duration="45"; spam="legshot" }
    legShot3 = @{ owner="combat_carbine_speed_01"; health=".5"; action="2";
        mind="2"; chance="100"; duration="30"; spam="kneecapshot" }
}
foreach ($name in @("legShot2", "legShot3")) {
    $want = $expected[$name]
    $command = @($commands | Where-Object commandName -ceq $name)
    Assert ($command.Count -eq 1 -and
        $command[0].scriptHook -ceq $name -and
        $command[0].defaultTime -ceq "1.5" -and
        $command[0].executeTime -ceq "1.5" -and
        $command[0].target -ceq "other" -and
        $command[0].targetType -ceq "optional" -and
        $command[0].commandGroup -ceq "391413347" -and
        $command[0].addToCombatQueue -ceq "1" -and
        $command[0].validWeapon -ceq "CARBINE") "$name command row drifted"
    $owners = @($skills | Where-Object {
        [string]$_.COMMANDS -match "(^|,)$name(,|$)"
    })
    Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq $want.owner) `
        "$name retained ownership drifted"
    $combat = @($combatRows | Where-Object actionName -ceq $name)
    Assert ($combat.Count -eq 1 -and
        $combat[0].animDefault -ceq "test_homing" -and
        $combat[0].anim_carbine -ceq "test_homing" -and
        $combat[0].attackType -ceq "SINGLE_TARGET" -and
        $combat[0].percentAddFromWeapon -ceq "2" -and
        $combat[0].weaponType -ceq "CARBINE" -and
        $combat[0].weaponCategory -ceq "RANGED_WEAPON") "$name combat row drifted"
    $override = @($overrides | Where-Object actionName -ceq $name)
    Assert ($override.Count -eq 1 -and
        $override[0].healthCostMultiplier -ceq $want.health -and
        $override[0].actionCostMultiplier -ceq $want.action -and
        $override[0].mindCostMultiplier -ceq $want.mind -and
        $override[0].targetPool -ceq "ACTION" -and
        $override[0].speedMultiplier -ceq "2" -and
        $override[0].accuracyBonus -ceq "25" -and
        $override[0].animationType -ceq "NONE" -and
        $override[0].stateEffect1 -ceq "STUN" -and
        $override[0].stateChance1 -ceq $want.chance -and
        $override[0].stateStrength1 -ceq "0" -and
        $override[0].stateDuration1 -ceq $want.duration -and
        $override[0].stateDefense1 -ceq "stun_defense" -and
        $override[0].stateJediDefense1 -ceq "jedi_state_defense" -and
        $override[0].stateResistance1 -ceq "resistance_states") `
        "$name override drifted"
    $spam = @($spamRows | Where-Object actionName -ceq $name)
    Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq $want.spam) `
        "$name spam drifted"
}
$sources = ($paths.actions, $paths.fixture |
    ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
foreach ($token in @(
    "public int legShot2(", "public int legShot3(",
    "CARBINE_SPEED_ONE", "ORIGINAL_CARBINE_SPEED_ONE",
    "ORIGINAL_LEG_SHOT_TWO_COMMAND", "ORIGINAL_LEG_SHOT_THREE_COMMAND",
    "canPerformLegShotTwo", "canPerformLegShotThree"
)) {
    Assert ($sources.Contains($token)) "M265 lifecycle drifted: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/263-p14-core3-leg-shot-continuation.patch"
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
        [bool]$contract.runtimeEvidence.userClientUntouched) "M265 is not Ready"
}
Write-Host "Publish 14.1 Core3 leg-shot continuation contract passed."
