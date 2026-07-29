param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PolearmAbilityBranch)) -Raw | ConvertFrom-Json
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
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M313 source: $path" }
$commandRows = @(Rows $paths.command)
$combatRows = @(Rows $paths.combat)
$overrideRows = @(Rows $paths.overrides)
$spamRows = @(Rows $paths.spam)
$specs = @(
    @{name="polearmSweep1"; damage="2.0"; speed="1.5"; health="1.5"; action="1.0"; mind="1.0"; accuracy="10"; attack="SINGLE_TARGET"; area=""; animation="knockdown_polearm_1"; spam="backcracker"},
    @{name="polearmSweep2"; damage="2.5"; speed="2.5"; health="2.0"; action="1.5"; mind="1.5"; accuracy="15"; attack="AREA"; area="16"; animation="knockdown_polearm_2"; spam="backbreaker"}
)
foreach ($spec in $specs) {
    $name = [string]$spec.name
    $command = @($commandRows | Where-Object commandName -CEQ $name)
    $combat = @($combatRows | Where-Object actionName -CEQ $name)
    $override = @($overrideRows | Where-Object actionName -CEQ $name)
    $spam = @($spamRows | Where-Object actionName -CEQ $name)
    Assert ($command.Count -eq 1 -and $combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "$name tables incomplete"
    $command = $command[0]; $combat = $combat[0]; $override = $override[0]; $spam = $spam[0]
    Assert ($command.scriptHook -ceq $name -and $command.characterAbility -ceq $name -and
        $command.failScriptHook -ceq "failSpecialAttack" -and $command.defaultPriority -ceq "normal" -and
        $command.defaultTime -ceq "1.5" -and $command.executeTime -ceq "1.5" -and
        $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
        $command.commandGroup -ceq "391413347" -and $command.addToCombatQueue -ceq "1" -and
        $command.validWeapon -ceq "POLEARM") "$name command row drifted"
    Assert ($combat.attackType -ceq [string]$spec.attack -and $combat.coneLength -ceq [string]$spec.area -and
        $combat.percentAddFromWeapon -ceq [string]$spec.damage -and $combat.animDefault -ceq [string]$spec.animation -and
        $combat.weaponType -ceq "POLEARM") "$name combat row drifted"
    Assert ($override.healthCostMultiplier -ceq [string]$spec.health -and
        $override.actionCostMultiplier -ceq [string]$spec.action -and
        $override.mindCostMultiplier -ceq [string]$spec.mind -and
        $override.targetPool -ceq "RANDOM" -and $override.speedMultiplier -ceq [string]$spec.speed -and
        $override.accuracyBonus -ceq [string]$spec.accuracy -and $override.animationType -ceq "" -and
        $override.postureDownChance -ceq "100") "$name override drifted"
    Assert ($spam.combatSpam -ceq [string]$spec.spam) "$name spam drifted"
}
$skills = @(Rows $paths.skills)
$names = @("combat_polearm_ability_01", "combat_polearm_ability_02", "combat_polearm_ability_03", "combat_polearm_ability_04")
$requirements = @("combat_polearm_novice", "combat_polearm_ability_01", "combat_polearm_ability_02", "combat_polearm_ability_03")
for ($i = 0; $i -lt 4; $i++) {
    $row = @($skills | Where-Object NAME -CEQ $names[$i])
    Assert ($row.Count -eq 1 -and [string]$row[0].SKILLS_REQUIRED -ceq $requirements[$i]) "$($names[$i]) prerequisite drifted"
}
Assert ([string](@($skills | Where-Object NAME -CEQ $names[0])[0].COMMANDS) -match '(^|,)polearmSweep1(,|$)') "polearmSweep1 ownership drifted"
Assert ([string](@($skills | Where-Object NAME -CEQ $names[2])[0].COMMANDS) -match '(^|,)polearmSweep2(,|$)') "polearmSweep2 ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in @("polearmSweep1", "polearmSweep2")) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains(('"' + $name + '"'))) "$name production hook drifted"
}
foreach ($token in @("POLEARM_ABILITY_ONE", "POLEARM_ABILITY_FOUR", "ORIGINAL_POLEARM_ABILITY_ONE",
    "ORIGINAL_POLEARM_ABILITY_FOUR", "POLEARM_SWEEP_ONE_COMMAND", "POLEARM_SWEEP_TWO_COMMAND",
    "ORIGINAL_POLEARM_SWEEP_ONE_COMMAND", "ORIGINAL_POLEARM_SWEEP_TWO_COMMAND", "armPolearmAbility",
    "polearmAbilityOne=", "polearmAbilityFour=", "polearmSweepOneCommand=", "polearmSweepTwoCommand=",
    "canPerformPolearmSweepOne=", "canPerformPolearmSweepTwo=")) {
    Assert ($fixture.Contains($token)) "M313 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/311-p14-core3-polearm-ability-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M313 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M313 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and [bool]$runtime.admission.abilityBranch -and
        [int]$runtime.admission.canPerform.polearmSweep1 -eq 0 -and
        [int]$runtime.admission.canPerform.polearmSweep2 -eq 0) "M313 admission proof missing"
    foreach ($name in @("polearmSweep1", "polearmSweep2")) {
        $execution = $runtime.commands.$name
        Assert ([string]$execution.queueRemoval -ceq "Success" -and [int]$execution.combatResult -eq 1 -and
            [int]$execution.directDamage -gt 0 -and [string]$execution.postureDown.result -in @("APPLIED", "RECOVERY")) "$name execution proof missing"
    }
    Assert ([bool]$runtime.persistence.fullServerRestart -and [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and [bool]$runtime.persistence.abilityBranchSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientRecoveryAbsent) "M313 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryAbilityBranchAbsent -and [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected) "M313 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 polearm ability branch contract passed."
