param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PolearmSupportBranch)) -Raw | ConvertFrom-Json
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
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M314 source: $path" }
$commandRows = @(Rows $paths.command)
$combatRows = @(Rows $paths.combat)
$overrideRows = @(Rows $paths.overrides)
$spamRows = @(Rows $paths.spam)
$specs = @(
    @{name="polearmActionHit1"; damage="1.0"; speed="1.5"; health="1.0"; action="0.5"; mind="0.5"; animation="attack_low_right_medium_0"; spam="kneecracker"; intensity="30"; duration="30"},
    @{name="polearmActionHit2"; damage="2.0"; speed="2.0"; health="1.5"; action="1.0"; mind="1.0"; animation="lower_posture_2hmelee_2"; spam="kneesmasher"; intensity="60"; duration="60"}
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
    Assert ($combat.attackType -ceq "SINGLE_TARGET" -and $combat.percentAddFromWeapon -ceq [string]$spec.damage -and
        $combat.animDefault -ceq [string]$spec.animation -and $combat.weaponType -ceq "POLEARM" -and
        $combat.dotType -ceq "bleeding" -and $combat.dotIntensity -ceq [string]$spec.intensity -and
        $combat.dotDuration -ceq [string]$spec.duration) "$name combat row drifted"
    Assert ($override.healthCostMultiplier -ceq [string]$spec.health -and
        $override.actionCostMultiplier -ceq [string]$spec.action -and
        $override.mindCostMultiplier -ceq [string]$spec.mind -and
        $override.targetPool -ceq "ACTION" -and $override.speedMultiplier -ceq [string]$spec.speed -and
        $override.accuracyBonus -ceq "10" -and $override.dotAttribute -ceq "ACTION") "$name override drifted"
    Assert ($spam.combatSpam -ceq [string]$spec.spam) "$name spam drifted"
}
$skills = @(Rows $paths.skills)
$names = @("combat_polearm_support_01", "combat_polearm_support_02", "combat_polearm_support_03", "combat_polearm_support_04")
$requirements = @("combat_polearm_novice", "combat_polearm_support_01", "combat_polearm_support_02", "combat_polearm_support_03")
for ($i = 0; $i -lt 4; $i++) {
    $row = @($skills | Where-Object NAME -CEQ $names[$i])
    Assert ($row.Count -eq 1 -and [string]$row[0].SKILLS_REQUIRED -ceq $requirements[$i]) "$($names[$i]) prerequisite drifted"
}
Assert ([string](@($skills | Where-Object NAME -CEQ $names[0])[0].COMMANDS) -match '(^|,)polearmActionHit1(,|$)') "polearmActionHit1 ownership drifted"
Assert ([string](@($skills | Where-Object NAME -CEQ $names[2])[0].COMMANDS) -match '(^|,)polearmActionHit2(,|$)') "polearmActionHit2 ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in @("polearmActionHit1", "polearmActionHit2")) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains(('"' + $name + '"'))) "$name production hook drifted"
}
foreach ($token in @("POLEARM_SUPPORT_ONE", "POLEARM_SUPPORT_FOUR", "ORIGINAL_POLEARM_SUPPORT_ONE",
    "ORIGINAL_POLEARM_SUPPORT_FOUR", "POLEARM_ACTION_HIT_ONE_COMMAND", "POLEARM_ACTION_HIT_TWO_COMMAND",
    "ORIGINAL_POLEARM_ACTION_HIT_ONE_COMMAND", "ORIGINAL_POLEARM_ACTION_HIT_TWO_COMMAND", "armPolearmSupport",
    "polearmSupportOne=", "polearmSupportFour=", "polearmActionHitOneCommand=", "polearmActionHitTwoCommand=",
    "canPerformPolearmActionHitOne=", "canPerformPolearmActionHitTwo=")) {
    Assert ($fixture.Contains($token)) "M314 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/312-p14-core3-polearm-support-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M314 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M314 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and [bool]$runtime.admission.supportBranch -and
        [int]$runtime.admission.canPerform.polearmActionHit1 -eq 0 -and
        [int]$runtime.admission.canPerform.polearmActionHit2 -eq 0) "M314 admission proof missing"
    foreach ($name in @("polearmActionHit1", "polearmActionHit2")) {
        $execution = $runtime.commands.$name
        Assert ([string]$execution.queueRemoval -ceq "Success" -and [int]$execution.combatResult -eq 1 -and
            [int]$execution.directDamage -gt 0 -and [string]$execution.bleeding.attribute -ceq "ACTION" -and
            [int]$execution.bleeding.strength -gt 0) "$name execution proof missing"
    }
    Assert ([bool]$runtime.persistence.fullServerRestart -and [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and [bool]$runtime.persistence.supportBranchSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientBleedingAbsent) "M314 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporarySupportBranchAbsent -and [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected) "M314 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 polearm support branch contract passed."
