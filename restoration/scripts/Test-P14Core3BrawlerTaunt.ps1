param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3BrawlerTaunt)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M300 source: $path"
}
$command = @(Rows $paths.command | Where-Object commandName -CEQ "taunt")
Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq "taunt" -and
    $command[0].defaultPriority -ceq "normal" -and
    $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and
    $command[0].target -ceq "other" -and
    $command[0].targetType -ceq "optional" -and
    $command[0].commandGroup -ceq "391413347" -and
    $command[0].maxRangeToTarget -ceq "0" -and
    $command[0].addToCombatQueue -ceq "1" -and
    $command[0].validWeapon -ceq "ALL") "taunt command row drifted"
$combat = @(Rows $paths.combat | Where-Object actionName -CEQ "taunt")
Assert ($combat.Count -eq 1 -and $combat[0].hitType -ceq "ATTACK" -and
    $combat[0].attackType -ceq "SINGLE_TARGET" -and
    $combat[0].maxRange -ceq "64" -and
    $combat[0].percentAddFromWeapon -ceq "1.0" -and
    $combat[0].triggerEffect -ceq "clienteffect/combat_special_attacker_taunt.cef") "taunt combat row drifted"
$override = @(Rows $paths.override | Where-Object actionName -CEQ "taunt")
Assert ($override.Count -eq 1 -and
    $override[0].healthCostMultiplier -ceq "1.0" -and
    $override[0].actionCostMultiplier -ceq "1.0" -and
    $override[0].mindCostMultiplier -ceq "1.0" -and
    $override[0].targetPool -ceq "NO_ATTRIBUTE" -and
    $override[0].speedMultiplier -ceq "1.0" -and
    $override[0].animationType -ceq "NONE") "taunt override row drifted"
$spam = @(Rows $paths.spam | Where-Object actionName -CEQ "taunt")
Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq "taunt") "taunt spam drifted"
$owners = @(Rows $paths.skills | Where-Object { [string]$_.COMMANDS -match "(^|,)taunt(,|$)" })
Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_brawler_novice" -and
    $owners[0].PARENT -ceq "combat_brawler" -and
    [string]$owners[0].SKILLS_REQUIRED -ceq "" -and
    [string]$owners[0].SKILL_MODS -match "(^|,)taunt=10(,|$)") "taunt skill owner drifted"
$actions = Get-Content -LiteralPath $paths.actions -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($token in @('public int taunt(', 'ai_lib.isTauntable(target)',
    'upperRoll >= lowerRoll', 'tauntMod * 10', 'precuTauntExpire',
    'taunt_success_single', 'taunt_fail_single')) {
    Assert ($actions.Contains($token)) "M300 production token missing: $token"
}
foreach ($token in @('TAUNT_COMMAND', 'ORIGINAL_TAUNT_COMMAND', 'armTaunt',
    'tauntModifier >= 10', 'tauntModifier=', 'initialDefenderHate=',
    'tauntCanPerform=', 'diagnosticTauntUpperRoll=',
    'diagnosticTauntHateAfterExpiry=')) {
    Assert ($fixture.Contains($token)) "M300 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/298-p14-core3-brawler-taunt.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M300 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M300 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M300 build evidence failed"
    Assert ([string]$contract.buildEvidence.cleanApplyCheck -ceq "passed" -and
        [string]$contract.buildEvidence.reverseApplyCheck -ceq "passed") "M300 replay checks missing"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M300 runtime evidence failed"
    Assert ([bool]$contract.runtimeEvidence.taunt.success -and
        [bool]$contract.runtimeEvidence.taunt.aiTarget -and
        [bool]$contract.runtimeEvidence.taunt.temporaryHateLeader -and
        [bool]$contract.runtimeEvidence.taunt.expired) "M300 taunt lifecycle proof missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.fullServerRestart -and
        [bool]$contract.runtimeEvidence.persistence.freshDualAuthentication) "M300 restart proof missing"
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent) "M300 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 Brawler taunt contract passed."
