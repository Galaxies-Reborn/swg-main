param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3HealthShotTwo)) -Raw | ConvertFrom-Json
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
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M301 source: $path"
}
$command = @(Rows $paths.command | Where-Object commandName -CEQ "healthShot2")
Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq "healthShot2" -and
    $command[0].defaultPriority -ceq "normal" -and
    $command[0].defaultTime -ceq "2" -and
    $command[0].executeTime -ceq "2" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].maxRangeToTarget -ceq "0" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "PISTOL") "healthShot2 command row drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -CEQ "healthShot2")
Assert ($combat.Count -eq 1 -and $combat[0].validTarget -ceq "STANDARD" -and
    $combat[0].hitType -ceq "ATTACK" -and $combat[0].healAttrib -ceq "HEALTH" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and $combat[0].maxRange -ceq "64" -and
    $combat[0].percentAddFromWeapon -ceq "3.0" -and
    $combat[0].animDefault -ceq "fire_1_special_single" -and
    $combat[0].anim_pistol -ceq "fire_1_special_single" -and
    $combat[0].weaponType -ceq "PISTOL" -and $combat[0].specialLine -ceq "pistoleer" -and
    $combat[0].dotType -ceq "bleeding" -and $combat[0].dotIntensity -ceq "100" -and
    $combat[0].dotDuration -ceq "60") "healthShot2 combat/DOT row drifted"
$override = @(Rows $paths.override | Where-Object actionName -CEQ "healthShot2")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "0.5" -and
    $override[0].actionCostMultiplier -ceq "1" -and
    $override[0].mindCostMultiplier -ceq "0.5" -and
    $override[0].targetPool -ceq "HEALTH" -and
    $override[0].speedMultiplier -ceq "2" -and
    $override[0].accuracyBonus -ceq "50" -and
    $override[0].animationType -ceq "RANGED" -and
    $override[0].dotAttribute -ceq "HEALTH") "healthShot2 override row drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -CEQ "healthShot2")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "sapblast") "healthShot2 spam drifted"
$owners = @(Rows $paths.skills | Where-Object { [string]$_.COMMANDS -match "(^|,)healthShot2(,|$)" })
Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_pistol_novice" -and
    $owners[0].PARENT -ceq "combat_pistol" -and
    [string]$owners[0].SKILLS_REQUIRED -ceq "combat_marksman_pistol_04" -and
    [string]$owners[0].SKILL_MODS -match "(^|,)pistol_accuracy=5(,|$)" -and
    [string]$owners[0].SKILL_MODS -match "(^|,)pistol_speed=5(,|$)") "healthShot2 skill owner drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains('public int healthShot2(') -and
    $actions.Contains('combatStandardAction("healthShot2"')) "healthShot2 production wrapper drifted"
foreach ($token in @('HEALTH_SHOT_TWO_COMMAND', 'ORIGINAL_HEALTH_SHOT_TWO_COMMAND',
    'armHealthShotTwo', 'MARKSMAN_PISTOL_FOUR', 'PISTOL_NOVICE',
    'healthShotTwoDotAttribute=', 'healthShotTwoDotIntensity=',
    'healthShotTwoDotDuration=', 'healthShotTwoDamageMultiplier=',
    'healthShotTwoHealthCost=', 'healthShotTwoActionCost=',
    'healthShotTwoMindCost=', 'canPerformHealthShotTwo=')) {
    Assert ($fixture.Contains($token)) "M301 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/299-p14-core3-health-shot-two.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M301 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M301 is not Ready"
    Assert ([bool]$contract.runtimeEvidence.admission.freshDualAuthentication -and
        [bool]$contract.runtimeEvidence.admission.marksmanPistolFour -and
        [bool]$contract.runtimeEvidence.admission.pistoleerNovice -and
        [bool]$contract.runtimeEvidence.admission.weaponSatisfies -and
        [int]$contract.runtimeEvidence.admission.canPerform -eq 0) "M301 admission proof missing"
    Assert ([string]$contract.runtimeEvidence.command.queueRemoval -ceq "Success" -and
        [string]$contract.runtimeEvidence.command.combatSpam -ceq "sapblast_hit" -and
        [int]$contract.runtimeEvidence.command.configuredTargetPool -eq 0 -and
        [int]$contract.runtimeEvidence.command.resolvedTargetPool -eq 0 -and
        [int]$contract.runtimeEvidence.command.bleedingDot.strength -eq 100 -and
        [int]$contract.runtimeEvidence.command.bleedingDot.attribute -eq 0 -and
        [int]$contract.runtimeEvidence.command.healthObservation.second -lt
            [int]$contract.runtimeEvidence.command.healthObservation.first -and
        [int]$contract.runtimeEvidence.command.healthObservation.first -lt
            [int]$contract.runtimeEvidence.command.healthObservation.before) "M301 HEALTH bleeding lifecycle proof missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.fullServerRestart -and
        [bool]$contract.runtimeEvidence.persistence.freshDualAuthentication -and
        [bool]$contract.runtimeEvidence.persistence.lifecycleSurvived -and
        [bool]$contract.runtimeEvidence.persistence.terminalDiagnosticsSurvived -and
        [bool]$contract.runtimeEvidence.persistence.transientBleedingDotAbsent) "M301 restart proof missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.cleanup.postCleanupAbilityRejected -and
        [string]$contract.runtimeEvidence.cleanup.postCleanupQueueStatus -ceq "Ability") "M301 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 healthShot2 contract passed."
