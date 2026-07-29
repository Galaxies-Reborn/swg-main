param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3FullAutoSingleOne)
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
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$basePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$skillPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
foreach ($path in @(
    $actionsPath,$basePath,$fixturePath,$combatPath,$overridePath,$spamPath,
    $commandPath,$skillPath
)) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M263 source: $path"
}
$actions = Get-Content -LiteralPath $actionsPath -Raw
$base = Get-Content -LiteralPath $basePath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$skills = Read-Rows $skillPath
$combatRows = Read-Rows $combatPath
$overrides = Read-Rows $overridePath
$spamRows = Read-Rows $spamPath
$command = @($commands | Where-Object commandName -ceq "fullAutoSingle1")
Assert ($command.Count -eq 1 -and
    $command[0].scriptHook -ceq "fullAutoSingle1" -and
    $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "CARBINE") `
    "fullAutoSingle1 command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)fullAutoSingle1(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_marksman_carbine_02") `
    "fullAutoSingle1 retained skill ownership drifted"
$combat = @($combatRows | Where-Object actionName -ceq "fullAutoSingle1")
Assert ($combat.Count -eq 1 -and
    $combat[0].animDefault -ceq "fire_5_special_single" -and
    $combat[0].anim_carbine -ceq "fire_5_special_single" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].percentAddFromWeapon -ceq "2" -and
    $combat[0].healthCost -ceq "0" -and
    $combat[0].actionCost -ceq "100" -and
    $combat[0].mindCost -ceq "40" -and
    $combat[0].weaponType -ceq "CARBINE" -and
    $combat[0].weaponCategory -ceq "RANGED_WEAPON") `
    "fullAutoSingle1 combat-data row drifted"
$override = @($overrides | Where-Object actionName -ceq "fullAutoSingle1")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "1.75" -and
    $override[0].actionCostMultiplier -ceq "2.5" -and
    $override[0].mindCostMultiplier -ceq "0.5" -and
    $override[0].targetPool -ceq "RANDOM" -and
    $override[0].speedMultiplier -ceq "1.5" -and
    $override[0].accuracyBonus -ceq "25" -and
    $override[0].animationType -ceq "RANGED") `
    "fullAutoSingle1 combat override drifted"
$expectedStates = @(
    @("DIZZY","30","0","30","dizzy_defense"),
    @("BLIND","30","0","40","blind_defense"),
    @("STUN","30","0","30","stun_defense")
)
for ($slot = 1; $slot -le 3; ++$slot) {
    $expected = $expectedStates[$slot - 1]
    $stateEffect = [string]$override[0].PSObject.Properties["stateEffect$slot"].Value
    $stateChance = [string]$override[0].PSObject.Properties["stateChance$slot"].Value
    $stateStrength = [string]$override[0].PSObject.Properties["stateStrength$slot"].Value
    $stateDuration = [string]$override[0].PSObject.Properties["stateDuration$slot"].Value
    $stateDefense = [string]$override[0].PSObject.Properties["stateDefense$slot"].Value
    $stateJediDefense =
        [string]$override[0].PSObject.Properties["stateJediDefense$slot"].Value
    $stateResistance =
        [string]$override[0].PSObject.Properties["stateResistance$slot"].Value
    Assert (
        $stateEffect -ceq $expected[0] -and
        $stateChance -ceq $expected[1] -and
        $stateStrength -ceq $expected[2] -and
        $stateDuration -ceq $expected[3] -and
        $stateDefense -ceq $expected[4] -and
        $stateJediDefense -ceq "jedi_state_defense" -and
        $stateResistance -ceq "resistance_states"
    ) "fullAutoSingle1 state slot $slot drifted"
}
$spam = @($spamRows | Where-Object actionName -ceq "fullAutoSingle1")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "fullautoattack") `
    "fullAutoSingle1 combat spam drifted"
foreach ($token in @(
    "public int fullAutoSingle1(",
    "return combatStandardAction(",
    "applyPrecuStateEffects(",
    "PRECU_STATE_EFFECT_DIZZY",
    "PRECU_STATE_EFFECT_BLIND",
    "PRECU_STATE_EFFECT_STUN",
    "rand(0, 100)",
    "chance - ((float)defense / 1.5f) - playerLevel",
    "Math.max(",
    "buff.applyBuff(defender, attacker, buffName, (float)duration)",
    "ORIGINAL_DIZZY_BUFF",
    "ORIGINAL_BLIND_BUFF",
    "ORIGINAL_STUN_BUFF",
    "ORIGINAL_CARBINE_TWO",
    "ORIGINAL_FULL_AUTO_SINGLE_ONE_COMMAND",
    "stateEffectAppliedCount="
)) {
    Assert ($actions.Contains($token) -or $base.Contains($token) -or
        $fixture.Contains($token)) "fullAutoSingle1 lifecycle drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
if ($null -ne $hashes -and @($hashes.PSObject.Properties).Count -gt 0) {
    $hashChecks = @{
        "combat_actions.java"=$actionsPath
        "combat_base.java"=$basePath
        "precu_headshot1_fixture.java"=$fixturePath
        "combat_data.tab"=$combatPath
        "precu_combat_overrides.tab"=$overridePath
        "precu_combat_spam.tab"=$spamPath
        "command_table.tab"=$commandPath
        "skills.tab"=$skillPath
    }
    foreach ($item in $hashChecks.GetEnumerator()) {
        Assert ((Sha $item.Value) -ceq [string]$hashes.($item.Key)) `
            "Source hash drifted: $($item.Key)"
    }
}
$patch = Join-Path $restorationRoot "patches/dsrc/261-p14-core3-full-auto-single-one.patch"
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) `
    "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "M263 is not Ready"
    $runtime = $contract.runtimeEvidence
    $stateEffects = @($runtime.stateEffects)
    Assert ([bool]$runtime.weaponAdmission.commandFound -and
        [bool]$runtime.weaponAdmission.satisfies -and
        [int]$runtime.clientQueueAdmission.countAfterAdmission -eq 1 -and
        [bool]$runtime.clientQueueAdmission.inCombatAfterAdmission -and
        [bool]$runtime.clientQueueAdmission.hasTargetAfterAdmission -and
        [int]$runtime.canPerformAction -eq 0 -and
        [int]$runtime.combatResult.damage -gt 0 -and
        [string]$runtime.combatResult.spamKey -ceq "fullautoattack_hit" -and
        [int]$runtime.combatResult.configuredTargetPool -eq 3 -and
        [int]$runtime.combatResult.animationType -eq 1 -and
        $stateEffects.Count -eq 3 -and
        [string]$stateEffects[0].state -ceq "DIZZY" -and
        [string]$stateEffects[1].state -ceq "BLIND" -and
        [string]$stateEffects[2].state -ceq "STUN" -and
        @($stateEffects | Where-Object {
            [int]$_.chance -eq 30 -and
            [int]$_.strength -eq 0 -and
            [string]$_.result -in @("APPLIED", "RESISTED")
        }).Count -eq 3 -and
        [int]$runtime.stateEffectAppliedCount -gt 0 -and
        [bool]$contract.runtimeEvidence.persistence.observed -and
        [bool]$contract.runtimeEvidence.persistence.lifecycleSnapshotSurvived -and
        [bool]$contract.runtimeEvidence.persistence.diagnosticEvidenceSurvived -and
        [bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) `
        "Authenticated fullAutoSingle1 evidence drifted"
}
Write-Host "Publish 14.1 Core3 fullAutoSingle1 contract passed."
