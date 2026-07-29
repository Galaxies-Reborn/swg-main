param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PolearmSpeedBranch)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
$paths = @{
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    overrides = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
}
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M312 source: $path" }
$command = @(Rows $paths.command | Where-Object commandName -CEQ "polearmArea2")
Assert ($command.Count -eq 1) "polearmArea2 command row missing or duplicated"
$command = $command[0]
Assert ($command.scriptHook -ceq "polearmArea2" -and $command.characterAbility -ceq "polearmArea2" -and
    $command.failScriptHook -ceq "failSpecialAttack" -and $command.defaultPriority -ceq "normal" -and
    $command.defaultTime -ceq "1.5" -and $command.executeTime -ceq "1.5" -and
    $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
    $command.commandGroup -ceq "391413347" -and $command.addToCombatQueue -ceq "1" -and
    $command.validWeapon -ceq "POLEARM") "polearmArea2 command row drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -CEQ "polearmArea2")
$override = @(Rows $paths.overrides | Where-Object actionName -CEQ "polearmArea2")
$spam = @(Rows $paths.spam | Where-Object actionName -CEQ "polearmArea2")
Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "polearmArea2 tables incomplete"
$combat = $combat[0]; $override = $override[0]
Assert ($combat.attackType -ceq "AREA" -and $combat.coneLength -ceq "16" -and
    $combat.percentAddFromWeapon -ceq "2.75" -and $combat.animDefault -ceq "lower_posture_2hmelee_6" -and
    $combat.weaponType -ceq "POLEARM") "polearmArea2 combat row drifted"
Assert ($override.healthCostMultiplier -ceq "2.0" -and $override.actionCostMultiplier -ceq "1.5" -and
    $override.mindCostMultiplier -ceq "1.5" -and $override.targetPool -ceq "RANDOM" -and
    $override.speedMultiplier -ceq "2.5" -and $override.accuracyBonus -ceq "10" -and
    $override.animationType -ceq "" -and $override.stateEffect1 -ceq "DIZZY" -and
    $override.stateChance1 -ceq "75" -and $override.stateDuration1 -ceq "30" -and
    $override.stateDefense1 -ceq "dizzy_defense" -and $override.stateEffect2 -ceq "STUN" -and
    $override.stateChance2 -ceq "75" -and $override.stateDuration2 -ceq "30" -and
    $override.stateDefense2 -ceq "stun_defense") "polearmArea2 dual-state override drifted"
Assert ($spam[0].combatSpam -ceq "tornado") "polearmArea2 spam drifted"
$skills = Rows $paths.skills
$names = 1..4 | ForEach-Object { "combat_polearm_speed_0$_" }
for ($i = 0; $i -lt 4; $i++) {
    $row = @($skills | Where-Object NAME -CEQ $names[$i])
    Assert ($row.Count -eq 1) "$($names[$i]) missing or duplicated"
    $required = if ($i -eq 0) { "combat_polearm_novice" } else { $names[$i - 1] }
    Assert ([string]$row[0].SKILLS_REQUIRED -ceq $required) "$($names[$i]) prerequisite drifted"
}
$expectedCommands = @("polearmLegHit2", "polearmArea1", "polearmLegHit3", "polearmArea2")
for ($i = 0; $i -lt 4; $i++) {
    $row = @($skills | Where-Object NAME -CEQ $names[$i])[0]
    Assert ([string]$row.COMMANDS -match ("(^|,)" + $expectedCommands[$i] + "(,|$)")) "$($expectedCommands[$i]) ownership drifted"
}
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains("public int polearmArea2(") -and $actions.Contains('"polearmArea2"')) "polearmArea2 production hook drifted"
foreach ($token in @("POLEARM_SPEED_ONE", "POLEARM_SPEED_FOUR", "ORIGINAL_POLEARM_SPEED_ONE",
    "ORIGINAL_POLEARM_SPEED_FOUR", "POLEARM_AREA_TWO_COMMAND", "ORIGINAL_POLEARM_AREA_TWO_COMMAND",
    "armPolearmSpeed", "polearmSpeedOne=", "polearmSpeedFour=", "polearmAreaTwoCommand=",
    "canPerformPolearmAreaTwo=")) { Assert ($fixture.Contains($token)) "M312 fixture token missing: $token" }
$overlay = Join-Path $restorationRoot "patches/dsrc/310-p14-core3-polearm-speed-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M312 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M312 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and [bool]$runtime.admission.speedBranch -and
        [int]$runtime.admission.canPerform.polearmArea2 -eq 0) "M312 admission proof missing"
    $execution = $runtime.command
    Assert ([string]$execution.queueRemoval -ceq "Success" -and [int]$execution.combatResult -eq 1 -and
        [int]$execution.directDamage -gt 0 -and @($execution.states).Count -eq 2) "polearmArea2 execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and [bool]$runtime.persistence.speedBranchSurvived -and
        [bool]$runtime.persistence.commandSurvived -and [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientStatesAbsent) "M312 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporarySpeedBranchAbsent -and [bool]$runtime.cleanup.temporaryCommandAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M312 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 polearm speed branch contract passed."
