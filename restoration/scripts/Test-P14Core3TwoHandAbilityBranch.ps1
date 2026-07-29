param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3TwoHandAbilityBranch)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
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
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    overrides = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M318 source: $path"
}
$specs = @(
    @{
        Name = "melee2hSpinAttack2"; Owner = "combat_2hsword_ability_01"
        Damage = "3"; Speed = "2.5"; Health = "1.5"; Action = "2"; Mind = "1.5"
        DefaultTime = "2.5"; CommandRange = "5"; CombatRange = "5"
        Animation = "combo_4b"; AnimationType = "INTENSITY"; Spam = "spinslam"
        PostureDownChance = ""
    },
    @{
        Name = "melee2hSweep2"; Owner = "combat_2hsword_ability_03"
        Damage = "2"; Speed = "2.5"; Health = "0.5"; Action = "2.25"; Mind = "1"
        DefaultTime = "1.5"; CommandRange = "0"; CombatRange = "3"
        Animation = "lower_posture_2hmelee_6"; AnimationType = ""; Spam = "sword2_knockdown"
        PostureDownChance = "100"
    }
)
$commandRows = Rows $paths.command
$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.overrides
$spamRows = Rows $paths.spam
foreach ($spec in $specs) {
    $name = [string]$spec.Name
    $command = @($commandRows | Where-Object commandName -CEQ $name)
    $combat = @($combatRows | Where-Object actionName -CEQ $name)
    $override = @($overrideRows | Where-Object actionName -CEQ $name)
    $spam = @($spamRows | Where-Object actionName -CEQ $name)
    Assert ($command.Count -eq 1 -and $combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "$name tables incomplete"
    $command = $command[0]
    $combat = $combat[0]
    $override = $override[0]
    Assert ($command.scriptHook -ceq $name -and $command.characterAbility -ceq $name -and
        $command.failScriptHook -ceq "failSpecialAttack" -and
        $command.defaultPriority -ceq "normal" -and
        $command.defaultTime -ceq [string]$spec.DefaultTime -and $command.executeTime -ceq "1.5" -and
        $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
        $command.maxRangeToTarget -ceq [string]$spec.CommandRange -and
        $command.commandGroup -ceq "391413347" -and $command.addToCombatQueue -ceq "1" -and
        $command.validWeapon -ceq "2HAND_MELEE") "$name command row drifted"
    Assert ($combat.attackType -ceq "AREA" -and $combat.coneLength -ceq "16" -and
        $combat.maxRange -ceq [string]$spec.CombatRange -and
        $combat.percentAddFromWeapon -ceq [string]$spec.Damage -and
        $combat.animDefault -ceq [string]$spec.Animation -and
        $combat.weaponType -ceq "2HAND_MELEE") "$name combat row drifted"
    Assert ($override.healthCostMultiplier -ceq [string]$spec.Health -and
        $override.actionCostMultiplier -ceq [string]$spec.Action -and
        $override.mindCostMultiplier -ceq [string]$spec.Mind -and
        $override.targetPool -ceq "RANDOM" -and
        $override.speedMultiplier -ceq [string]$spec.Speed -and
        $override.accuracyBonus -ceq "10" -and
        [string]$override.animationType -ceq [string]$spec.AnimationType -and
        [string]$override.postureDownChance -ceq [string]$spec.PostureDownChance) "$name override drifted"
    Assert ($spam[0].combatSpam -ceq [string]$spec.Spam) "$name spam drifted"
}
$skills = Rows $paths.skills
$skillSpecs = @(
    @{ Name = "combat_2hsword_ability_01"; Requires = "combat_2hsword_novice"; Commands = @("melee2hSpinAttack2", "melee_damage_mitigation_1") },
    @{ Name = "combat_2hsword_ability_02"; Requires = "combat_2hsword_ability_01"; Commands = @() },
    @{ Name = "combat_2hsword_ability_03"; Requires = "combat_2hsword_ability_02"; Commands = @("melee2hSweep2", "melee_damage_mitigation_2") },
    @{ Name = "combat_2hsword_ability_04"; Requires = "combat_2hsword_ability_03"; Commands = @() }
)
foreach ($spec in $skillSpecs) {
    $row = @($skills | Where-Object NAME -CEQ $spec.Name)
    Assert ($row.Count -eq 1) "$($spec.Name) row missing or duplicated"
    Assert ([string]$row[0].SKILLS_REQUIRED -ceq [string]$spec.Requires) "$($spec.Name) prerequisite drifted"
    foreach ($command in @($spec.Commands)) {
        Assert ([string]$row[0].COMMANDS -match ("(^|,)" + [regex]::Escape([string]$command) + "(,|$)")) "$command ownership drifted"
    }
}
$actions = Get-Content -LiteralPath $paths.actions -Raw
foreach ($name in @("melee2hSpinAttack2", "melee2hSweep2")) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains('"' + $name + '"')) "$name production hook drifted"
}
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @(
    "TWO_HAND_SWORD_ABILITY_ONE", "TWO_HAND_SWORD_ABILITY_FOUR",
    "ORIGINAL_TWO_HAND_SWORD_ABILITY_ONE", "ORIGINAL_TWO_HAND_SWORD_ABILITY_FOUR",
    "TWO_HAND_SWEEP_TWO_COMMAND", "ORIGINAL_TWO_HAND_SWEEP_TWO_COMMAND",
    "armTwoHandAbility", "twoHandSwordAbilityOne=", "twoHandSwordAbilityFour=",
    "twoHandSweepTwoCommand=", "twoHandSweepTwoCanPerform="
)) {
    Assert ($fixture.Contains($token)) "M318 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/316-p14-core3-two-hand-ability-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M318 overlay hash drifted"
foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties) {
    $key = [string]$entry.Name
    $pathKey = switch ($key) {
        "combat_actions.java" { "actions" }
        "precu_headshot1_fixture.java" { "fixture" }
        "command_table.tab" { "command" }
        "skills.tab" { "skills" }
        "combat_data.tab" { "combat" }
        "precu_combat_overrides.tab" { "overrides" }
        "precu_combat_spam.tab" { "spam" }
        default { throw "Unexpected M318 source hash key: $key" }
    }
    Assert ([string]$entry.Value -ceq (Sha $paths[$pathKey])) "M318 source hash drifted: $key"
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M318 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.twoHandSwordNovice -and
        [bool]$runtime.admission.abilityOne -and [bool]$runtime.admission.abilityTwo -and
        [bool]$runtime.admission.abilityThree -and [bool]$runtime.admission.abilityFour -and
        [int]$runtime.admission.canPerform.melee2hSpinAttack2 -eq 0 -and
        [int]$runtime.admission.canPerform.melee2hSweep2 -eq 0 -and
        [bool]$runtime.admission.clientWeaponStatus.satisfies) "M318 admission proof missing"
    Assert (@($runtime.commands).Count -eq 2) "M318 command proof count drifted"
    $spin = @($runtime.commands | Where-Object name -CEQ "melee2hSpinAttack2")[0]
    $sweep = @($runtime.commands | Where-Object name -CEQ "melee2hSweep2")[0]
    Assert ([bool]$spin.queueAccepted -and [int]$spin.combatResult -eq 1 -and
        [int]$spin.directDamage -gt 0 -and [string]$spin.configuredPool -ceq "RANDOM" -and
        [string]$spin.combatSpam -ceq "spinslam_hit" -and
        [string]$spin.animation -ceq "combo_4b_medium" -and [int]$spin.animationType -eq 2) "M318 Spin Attack II execution proof missing"
    Assert ([bool]$sweep.queueAccepted -and [int]$sweep.directDamage -gt 0 -and
        [string]$sweep.configuredPool -ceq "RANDOM" -and
        [string]$sweep.combatSpam -match '^sword2_knockdown_' -and
        [string]$sweep.animation -ceq "lower_posture_2hmelee_6" -and
        [int]$sweep.animationType -eq 0 -and
        [int]$sweep.postureDown.chance -eq 100 -and [int]$sweep.postureDown.start -eq 0 -and
        [int]$sweep.postureDown.end -eq 1 -and [string]$sweep.postureDown.result -ceq "APPLIED") "M318 Sweep II execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.branchSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and
        [bool]$runtime.persistence.canPerformSurvived -and
        [bool]$runtime.persistence.weaponSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientRecoveryAbsent -and
        [bool]$runtime.persistence.postRestartExecution.queueAccepted -and
        [int]$runtime.persistence.postRestartExecution.directDamage -gt 0 -and
        [string]$runtime.persistence.postRestartExecution.postureDown.result -ceq "APPLIED") "M318 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and
        -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.identityBoundSnapshotsRestored -and
        [bool]$runtime.cleanup.fixtureWeaponAbsent -and
        -not [bool]$runtime.cleanup.postCleanupClientWeaponSatisfies -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Cancelled" -and
        [bool]$runtime.isolatedClientsStopped -and [int]$runtime.connectionServerCount -eq 1) "M318 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 two-hand ability branch contract passed."
