param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PolearmNoviceAttack)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M310 source: $path"
}
$command = @(Rows $paths.command | Where-Object commandName -CEQ "polearmHit2")
Assert ($command.Count -eq 1) "polearmHit2 command row missing or duplicated"
$command = $command[0]
Assert ($command.scriptHook -ceq "polearmHit2" -and
    $command.characterAbility -ceq "polearmHit2" -and
    $command.failScriptHook -ceq "failSpecialAttack" -and
    $command.defaultPriority -ceq "normal" -and
    $command.defaultTime -ceq "1.5" -and $command.executeTime -ceq "1.5" -and
    $command.target -ceq "other" -and $command.targetType -ceq "optional" -and
    $command.commandGroup -ceq "391413347" -and
    $command.addToCombatQueue -ceq "1" -and
    $command.validWeapon -ceq "POLEARM") "polearmHit2 command row drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -CEQ "polearmHit2")
$override = @(Rows $paths.overrides | Where-Object actionName -CEQ "polearmHit2")
$spam = @(Rows $paths.spam | Where-Object actionName -CEQ "polearmHit2")
Assert ($combat.Count -eq 1 -and $override.Count -eq 1 -and $spam.Count -eq 1) "M310 combat tables are incomplete"
$combat = $combat[0]
$override = $override[0]
Assert ($combat.attackType -ceq "SINGLE_TARGET" -and $combat.maxRange -ceq "5" -and
    $combat.percentAddFromWeapon -ceq "2.5" -and $combat.animDefault -ceq "combo_3a" -and
    $combat.weaponType -ceq "POLEARM") "polearmHit2 combat row drifted"
Assert ($override.healthCostMultiplier -ceq "1.5" -and
    $override.actionCostMultiplier -ceq "1" -and
    $override.mindCostMultiplier -ceq "1" -and
    $override.targetPool -ceq "RANDOM" -and
    $override.speedMultiplier -ceq "2.0" -and
    $override.accuracyBonus -ceq "10" -and
    $override.animationType -ceq "INTENSITY" -and
    $override.stateEffect1 -ceq "STUN" -and
    $override.stateChance1 -ceq "75" -and
    $override.stateStrength1 -ceq "0" -and
    $override.stateDuration1 -ceq "45" -and
    $override.stateDefense1 -ceq "stun_defense" -and
    $override.stateJediDefense1 -ceq "jedi_state_defense" -and
    $override.stateResistance1 -ceq "resistance_states") "polearmHit2 override drifted"
Assert ($spam[0].combatSpam -ceq "bonesmasher") "polearmHit2 spam drifted"
$skills = Rows $paths.skills
$novice = @($skills | Where-Object NAME -CEQ "combat_polearm_novice")[0]
Assert ([string]$novice.SKILLS_REQUIRED -ceq "combat_brawler_polearm_04") "M310 novice prerequisite drifted"
Assert ([string]$novice.COMMANDS -match "(^|,)polearmHit2(,|$)") "M310 novice command ownership drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
Assert ($actions.Contains("public int polearmHit2(") -and $actions.Contains('"polearmHit2"')) "polearmHit2 production hook drifted"
foreach ($token in @("POLEARM_NOVICE", "ORIGINAL_POLEARM_NOVICE",
    "POLEARM_HIT_TWO_COMMAND", "ORIGINAL_POLEARM_HIT_TWO_COMMAND",
    "armPolearmNovice", "polearmNovice=", "polearmHitTwoCommand=",
    "canPerformPolearmHitTwo=")) {
    Assert ($fixture.Contains($token)) "M310 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/308-p14-core3-polearm-novice-attack.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M310 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M310 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.polearmNovice -and
        [int]$runtime.admission.canPerform.polearmHit2 -eq 0) "M310 admission proof missing"
    Assert ([string]$runtime.command.queueRemoval -ceq "Success" -and
        [int]$runtime.command.combatResult -eq 1 -and
        [int]$runtime.command.directDamage -gt 0 -and
        [string]$runtime.command.state.result -in @("APPLIED", "RESISTED")) "M310 execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.noviceSurvived -and
        [bool]$runtime.persistence.commandSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientStunAbsent) "M310 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryPolearmNoviceAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M310 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 polearm novice attack contract passed."
