param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3TwoHandSupportBranch)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M319 source: $path"
}
$specs = @(
    @{
        Name = "melee2hMindHit1"; Owner = "combat_2hsword_support_01"
        Damage = "1"; Speed = "1.25"; Health = "0.5"; Action = "1"; Mind = "0.5"
        Animation = "combo_2b"; Spam = "mindstrike"; DotIntensity = "30"; DotDuration = "30"
    },
    @{
        Name = "melee2hMindHit2"; Owner = "combat_2hsword_support_03"
        Damage = "2"; Speed = "2"; Health = "1"; Action = "1.5"; Mind = "1"
        Animation = "combo_3c"; Spam = "mindslam"; DotIntensity = "60"; DotDuration = "60"
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
        $command.failScriptHook -ceq "failSpecialAttack" -and $command.defaultPriority -ceq "normal" -and
        $command.defaultTime -ceq "1.5" -and $command.executeTime -ceq "1.5" -and
        $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
        $command.maxRangeToTarget -ceq "0" -and $command.commandGroup -ceq "391413347" -and
        $command.addToCombatQueue -ceq "1" -and $command.validWeapon -ceq "2HAND_MELEE") "$name command row drifted"
    Assert ($combat.attackType -ceq "SINGLE_TARGET" -and $combat.maxRange -ceq "3" -and
        $combat.percentAddFromWeapon -ceq [string]$spec.Damage -and
        $combat.animDefault -ceq [string]$spec.Animation -and $combat.dotType -ceq "bleeding" -and
        $combat.dotIntensity -ceq [string]$spec.DotIntensity -and
        $combat.dotDuration -ceq [string]$spec.DotDuration -and
        $combat.weaponType -ceq "2HAND_MELEE") "$name combat row drifted"
    Assert ($override.healthCostMultiplier -ceq [string]$spec.Health -and
        $override.actionCostMultiplier -ceq [string]$spec.Action -and
        $override.mindCostMultiplier -ceq [string]$spec.Mind -and $override.targetPool -ceq "MIND" -and
        $override.speedMultiplier -ceq [string]$spec.Speed -and $override.accuracyBonus -ceq "10" -and
        $override.animationType -ceq "INTENSITY" -and $override.dotAttribute -ceq "MIND") "$name override drifted"
    Assert ($spam[0].combatSpam -ceq [string]$spec.Spam) "$name spam drifted"
}
$skills = Rows $paths.skills
$skillSpecs = @(
    @{ Name = "combat_2hsword_support_01"; Requires = "combat_2hsword_novice"; Commands = @("melee2hMindHit1") },
    @{ Name = "combat_2hsword_support_02"; Requires = "combat_2hsword_support_01"; Commands = @() },
    @{ Name = "combat_2hsword_support_03"; Requires = "combat_2hsword_support_02"; Commands = @("melee2hMindHit2", "cert_sword_2h_scythe") },
    @{ Name = "combat_2hsword_support_04"; Requires = "combat_2hsword_support_03"; Commands = @() }
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
foreach ($name in @("melee2hMindHit1", "melee2hMindHit2")) {
    Assert ($actions.Contains("public int $name(") -and $actions.Contains('"' + $name + '"')) "$name production hook drifted"
}
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @(
    "TWO_HAND_SWORD_SUPPORT_ONE", "TWO_HAND_SWORD_SUPPORT_FOUR",
    "ORIGINAL_TWO_HAND_SWORD_SUPPORT_ONE", "ORIGINAL_TWO_HAND_SWORD_SUPPORT_FOUR",
    "TWO_HAND_MIND_HIT_ONE_COMMAND", "TWO_HAND_MIND_HIT_TWO_COMMAND",
    "ORIGINAL_TWO_HAND_MIND_HIT_ONE_COMMAND", "ORIGINAL_TWO_HAND_MIND_HIT_TWO_COMMAND",
    "armTwoHandSupport", "twoHandSwordSupportOne=", "twoHandSwordSupportFour=",
    "twoHandMindHitOneCanPerform=", "twoHandMindHitTwoCanPerform=",
    "twoHandMindHitOneDotIntensity=", "twoHandMindHitTwoDotIntensity="
)) {
    Assert ($fixture.Contains($token)) "M319 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/317-p14-core3-two-hand-support-branch.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M319 overlay hash drifted"
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
        default { throw "Unexpected M319 source hash key: $key" }
    }
    Assert ([string]$entry.Value -ceq (Sha $paths[$pathKey])) "M319 source hash drifted: $key"
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M319 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and [bool]$runtime.admission.twoHandSwordNovice -and
        [bool]$runtime.admission.supportOne -and [bool]$runtime.admission.supportTwo -and
        [bool]$runtime.admission.supportThree -and [bool]$runtime.admission.supportFour -and
        [int]$runtime.admission.canPerform.melee2hMindHit1 -eq 0 -and
        [int]$runtime.admission.canPerform.melee2hMindHit2 -eq 0 -and
        [bool]$runtime.admission.clientWeaponStatus.satisfies) "M319 admission proof missing"
    Assert (@($runtime.commands).Count -eq 2) "M319 command proof count drifted"
    $mindOne = @($runtime.commands | Where-Object name -CEQ "melee2hMindHit1")[0]
    $mindTwo = @($runtime.commands | Where-Object name -CEQ "melee2hMindHit2")[0]
    Assert ([string]$mindOne.queueStatus -ceq "Success" -and [int]$mindOne.combatResult -eq 1 -and
        [int]$mindOne.directDamage -gt 0 -and [string]$mindOne.configuredPool -ceq "MIND" -and
        [string]$mindOne.resolvedPool -ceq "MIND" -and [string]$mindOne.combatSpam -ceq "mindstrike_hit" -and
        [string]$mindOne.animation -ceq "combo_2b_medium" -and [int]$mindOne.animationType -eq 2 -and
        [string]$mindOne.bleeding.attribute -ceq "MIND" -and [int]$mindOne.bleeding.strength -eq 30) "M319 Mind Hit I proof missing"
    Assert ([string]$mindTwo.queueStatus -ceq "Success" -and [int]$mindTwo.combatResult -eq 1 -and
        [int]$mindTwo.directDamage -gt 0 -and [string]$mindTwo.configuredPool -ceq "MIND" -and
        [string]$mindTwo.resolvedPool -ceq "MIND" -and [string]$mindTwo.combatSpam -ceq "mindslam_hit" -and
        [string]$mindTwo.animation -ceq "combo_3c_medium" -and [int]$mindTwo.animationType -eq 2 -and
        [string]$mindTwo.bleeding.attribute -ceq "MIND" -and [int]$mindTwo.bleeding.strength -eq 60) "M319 Mind Hit II proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and [bool]$runtime.persistence.supportBranchSurvived -and
        [bool]$runtime.persistence.commandsSurvived -and [bool]$runtime.persistence.canPerformSurvived -and
        [bool]$runtime.persistence.weaponSurvived -and [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientBleedingAbsent -and
        [string]$runtime.persistence.postRestartExecution.queueStatus -ceq "Success" -and
        [int]$runtime.persistence.postRestartExecution.directDamage -gt 0 -and
        [int]$runtime.persistence.postRestartExecution.bleeding.strength -eq 60) "M319 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and -not [bool]$runtime.cleanup.firstCleanupAlreadyClean -and
        [bool]$runtime.cleanup.secondCleanupAlreadyClean -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.identityBoundSnapshotsRestored -and [bool]$runtime.cleanup.fixtureWeaponAbsent -and
        -not [bool]$runtime.cleanup.postCleanupClientWeaponSatisfies -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability" -and
        [bool]$runtime.isolatedClientsStopped -and [int]$runtime.connectionServerCount -eq 1) "M319 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 two-hand support branch contract passed."
