param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3FeignDeathLifecycle)) -Raw | ConvertFrom-Json
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
    combat = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/combat.java"
    player = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    base = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    buffs = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M329 source: $path"
}
$commandRows = Rows $paths.command
$skillRows = Rows $paths.skills
$buffRows = Rows $paths.buffs
$row = @($commandRows | Where-Object commandName -CEQ "feignDeath")
Assert ($row.Count -eq 1) "feignDeath command row missing or duplicated"
$row = $row[0]
Assert ([string]$row.commandCategory -ceq "combat" -and
    [string]$row.defaultPriority -ceq "normal" -and
    [string]$row.scriptHook -ceq "feignIncapacitation" -and
    [string]$row.failScriptHook -ceq "failSpecialAttack" -and
    [double]$row.defaultTime -eq 3 -and
    [string]$row.characterAbility -ceq "feignDeath" -and
    [string]$row.target -ceq "other" -and
    [string]$row.targetType -ceq "optional" -and
    [int]$row.visible -eq 2 -and
    [int]$row.commandGroup -eq -560185247 -and
    [int]$row.addToCombatQueue -eq 1 -and
    [string]$row.validWeapon -ceq "ALL" -and
    [string]$row.invalidWeapon -ceq "NONE" -and
    [string]$row.cooldownGroup -ceq "command_message" -and
    [double]$row.executeTime -eq 3 -and [double]$row.cooldownTime -eq 5) "feignDeath command metadata drifted"
$owners = @{
    combat_smuggler_combat_01 = @{commands="feignDeath,ranged_damage_mitigation_1"; mod=45}
    combat_smuggler_combat_02 = @{commands="panicShot"; mod=5}
    combat_smuggler_combat_03 = @{commands="lowBlow,melee_damage_mitigation_1"; mod=10}
    combat_smuggler_combat_04 = @{commands="lastDitch"; mod=10}
}
foreach ($skillName in $owners.Keys) {
    $skill = @($skillRows | Where-Object NAME -CEQ $skillName)
    Assert ($skill.Count -eq 1 -and [string]$skill[0].COMMANDS -ceq $owners[$skillName].commands -and
        [string]$skill[0].SKILL_MODS -match "(^|,)feign_death=$($owners[$skillName].mod)(,|$)") "$skillName feign ownership drifted"
}
$buff = @($buffRows | Where-Object NAME -CEQ "feign_death")
Assert ($buff.Count -eq 1 -and [string]$buff[0].STATE -ceq "STATE_FEIGN_DEATH" -and
    [int]$buff[0].IS_PERSISTENT -eq 1) "feign_death buff missing or drifted"
$combat = Get-Content -LiteralPath $paths.combat -Raw
$player = Get-Content -LiteralPath $paths.player -Raw
$actions = Get-Content -LiteralPath $paths.actions -Raw
$base = Get-Content -LiteralPath $paths.base -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @("armPrecuFeignDeath", "consumePrecuFeignDeathOnDamage", "revealPrecuFeignDeath",
    "restorePrecuFeignDeathOnLoad", "precuFinalizeFeignDeath", "PRECU_FEIGN_FINALIZING",
    "PRECU_FEIGN_PENDING_DEFENSE_MODIFIER", "private_defense", "-99999999", "PRECU_FEIGN_MAX_DEFENDERS = 5",
    "feign_death", "POSTURE_INCAPACITATED", "stopCombat")) {
    Assert ($combat.Contains($token)) "Combat lifecycle token missing: $token"
}
Assert ($player.Contains("public int feignIncapacitation(") -and
    $player.Contains("combat.armPrecuFeignDeath(self)") -and
    $player.Contains("public int precuFinalizeFeignDeath(") -and
    $player.Contains("combat.restorePrecuFeignDeathOnLoad(self)")) "feignIncapacitation lifecycle wrappers missing"
Assert ($actions.Contains('combat.revealPrecuFeignDeath(self, "failedCombatCommand")')) "failed-command reveal fallback missing"
Assert ($base.Contains('combat.revealPrecuFeignDeath(self, "combatCommand")') -and
    $base.Contains("combat.consumePrecuFeignDeathOnDamage(")) "combat execution seams missing"
foreach ($token in @("prepareFeignDeath", "statusFeignDeath", "armFeignDeathNoCombat",
    "armFeignDeathFailure", "armFeignDeathSuccess", "cleanupFeignDeath", "forcedRoll")) {
    Assert ($fixture.Contains($token)) "Fixture token missing: $token"
}
$hashNames = @{
    combat="combat.java"; player="base_player.java"; actions="combat_actions.java";
    base="combat_base.java"; fixture="precu_headshot1_fixture.java"; command="command_table.tab"
}
foreach ($key in $hashNames.Keys) {
    Assert ((Sha $paths[$key]) -ceq [string]$contract.buildEvidence.sourceSha256.($hashNames[$key])) "M329 source hash mismatch: $key"
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M329 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.noCombat.rejected -and
        [bool]$runtime.failure.consumed -and -not [bool]$runtime.failure.feigned -and
        [bool]$runtime.success.consumed -and [bool]$runtime.success.feigned -and
        [bool]$runtime.persistence.fullServerRestart -and [bool]$runtime.persistence.freshDualReauthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and [bool]$runtime.persistence.loadRehydrated -and
        [bool]$runtime.reveal.revealed -and [bool]$runtime.cleanup.restored -and
        [bool]$runtime.cleanup.idempotent -and [bool]$runtime.rollback.allHashesExact -and
        [bool]$runtime.rollback.completeCombatEngineFamilyRestored -and
        [bool]$runtime.isolatedClientsStopped -and [int]$runtime.connectionServerCount -eq 1) "M329 runtime proof missing"
}
Write-Host "Publish 14.1 Core3 feign-death lifecycle contract passed."
