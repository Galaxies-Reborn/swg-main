param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3BrawlerLungeTwoFamily)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Rows([string]$Path) { $lines = Get-Content -LiteralPath $Path; $header = $lines[0] -split "`t", -1; @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header) }
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
$paths = @{
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    base = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M299 source: $path" }
$expected = @{
    polearmLunge2 = @{ weapon = "POLEARM"; damage = "2.0"; speed = "2.5"; health = "0.625"; action = "1.5"; mind = "0.625"; accuracy = "10"; animation = "lower_posture_polearm_2"; spam = "lungestrike" }
    unarmedLunge2 = @{ weapon = "UNARMED"; damage = "3.0"; speed = "2.0"; health = "1.5"; action = "1.5"; mind = "1.5"; accuracy = "15"; animation = "knockdown_unarmed_1"; spam = "lungeshiak" }
    melee1hLunge2 = @{ weapon = "1HAND_MELEE"; damage = "3.0"; speed = "2.5"; health = "0.625"; action = "0.625"; mind = "1.5"; accuracy = "25"; animation = "knockdown_1hmelee_1"; spam = "lungestab" }
    melee2hLunge2 = @{ weapon = "2HAND_MELEE"; damage = "1.0"; speed = "2.5"; health = "1.5"; action = "0.625"; mind = "0.625"; accuracy = "10"; animation = "knockdown_2hmelee_1"; spam = "lungeslam" }
}
$commandRows = Rows $paths.command
$combatRows = Rows $paths.combat
$overrideRows = Rows $paths.override
$spamRows = Rows $paths.spam
$skillRows = Rows $paths.skills
foreach ($name in $expected.Keys) {
    $value = $expected[$name]
    $command = @($commandRows | Where-Object commandName -ceq $name)
    Assert ($command.Count -eq 1 -and $command[0].scriptHook -ceq $name -and $command[0].defaultPriority -ceq "normal" -and $command[0].defaultTime -ceq "1.5" -and $command[0].executeTime -ceq "1.5" -and $command[0].'L:standing' -ceq "1" -and $command[0].'L:walking' -ceq "1" -and $command[0].'L:running' -ceq "1" -and $command[0].'L:kneeling' -ceq "1" -and $command[0].'L:prone' -ceq "1" -and $command[0].'L:crawling' -ceq "1" -and $command[0].'S:berserk' -ceq "0" -and $command[0].target -ceq "other" -and $command[0].targetType -ceq "optional" -and $command[0].commandGroup -ceq "391413347" -and $command[0].maxRangeToTarget -ceq "0" -and $command[0].addToCombatQueue -ceq "1" -and $command[0].validWeapon -ceq $value.weapon) "$name command row drifted"
    $owners = @($skillRows | Where-Object { [string]$_.COMMANDS -match "(^|,)$name(,|$)" })
    Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq "combat_brawler_master" -and [string]$owners[0].PARENT -ceq "combat_brawler" -and [string]$owners[0].SKILLS_REQUIRED -ceq "combat_brawler_unarmed_04,combat_brawler_1handmelee_04,combat_brawler_2handmelee_04,combat_brawler_polearm_04") "$name owner drifted"
    $combat = @($combatRows | Where-Object actionName -ceq $name)
    Assert ($combat.Count -eq 1 -and $combat[0].percentAddFromWeapon -ceq $value.damage -and $combat[0].hitType -ceq "ATTACK" -and $combat[0].attackType -ceq "SINGLE_TARGET" -and $combat[0].minRange -ceq "0" -and $combat[0].maxRange -ceq "20" -and $combat[0].animDefault -ceq $value.animation -and $combat[0].weaponType -ceq $value.weapon -and $combat[0].specialLine -ceq "brawler") "$name combat row drifted"
    $override = @($overrideRows | Where-Object actionName -ceq $name)
    Assert ($override.Count -eq 1 -and $override[0].healthCostMultiplier -ceq $value.health -and $override[0].actionCostMultiplier -ceq $value.action -and $override[0].mindCostMultiplier -ceq $value.mind -and $override[0].targetPool -ceq "RANDOM" -and $override[0].speedMultiplier -ceq $value.speed -and $override[0].accuracyBonus -ceq $value.accuracy -and $override[0].animationType -ceq "NONE" -and $override[0].knockdownChance -ceq "100" -and [string]$override[0].stateEffect1 -ceq "") "$name override row drifted"
    $spam = @($spamRows | Where-Object actionName -ceq $name)
    Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq $value.spam) "$name spam drifted"
}
$actions = Get-Content -LiteralPath $paths.actions -Raw
$base = Get-Content -LiteralPath $paths.base -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
foreach ($name in $expected.Keys) { Assert ($actions.Contains("public int $name(") -and $actions.Contains("`"$name`", self, target")) "$name dispatcher missing" }
foreach ($token in @('PRECU_KNOCKDOWN_RECOVERY', 'PRECU_KNOCKDOWN_ORIGINAL_POSTURE', '"knockdown_defense"', '"APPLIED"')) { Assert ($base.Contains($token)) "M299 combat-base token missing: $token" }
foreach ($token in @('POLEARM_LUNGE_TWO_COMMAND', 'UNARMED_LUNGE_TWO_COMMAND', 'ONE_HAND_LUNGE_TWO_COMMAND', 'TWO_HAND_LUNGE_TWO_COMMAND', 'ORIGINAL_POLEARM_LUNGE_TWO_COMMAND', 'ORIGINAL_UNARMED_LUNGE_TWO_COMMAND', 'ORIGINAL_ONE_HAND_LUNGE_TWO_COMMAND', 'ORIGINAL_TWO_HAND_LUNGE_TWO_COMMAND', 'armLungeTwoFamily', 'polearmLungeTwoCanPerform=', 'unarmedLungeTwoCanPerform=', 'oneHandLungeTwoCanPerform=', 'twoHandLungeTwoCanPerform=', 'diagnosticKnockdownResult=')) { Assert ($fixture.Contains($token)) "M299 fixture token missing: $token" }
$overlay = Join-Path $restorationRoot "patches/dsrc/297-p14-core3-brawler-lunge-two-family.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M299 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready") "M299 contract is not ready"
    Assert ([string]$contract.buildEvidence.result -ceq "passed") "M299 build evidence failed"
    Assert ([string]$contract.buildEvidence.cleanApplyCheck -ceq "passed" -and [string]$contract.buildEvidence.reverseApplyCheck -ceq "passed") "M299 replay checks missing"
    Assert ([string]$contract.runtimeEvidence.result -ceq "passed") "M299 runtime evidence failed"
    Assert (@($contract.runtimeEvidence.attacks).Count -eq 4) "M299 four-command runtime family proof missing"
    foreach ($attack in @($contract.runtimeEvidence.attacks)) { Assert ([int]$attack.canPerform -eq 0 -and [bool]$attack.satisfies -and [int]$attack.combatResult -eq 1) "M299 runtime attack admission failed: $($attack.command)" }
    Assert ([string]$contract.runtimeEvidence.sharedKnockdown.result -ceq "APPLIED") "M299 knockdown application missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.fullServerRestart -and [bool]$contract.runtimeEvidence.persistence.freshDualAuthentication -and [bool]$contract.runtimeEvidence.persistence.diagnosticEvidenceSurvived) "M299 restart persistence missing"
    Assert ([bool]$contract.runtimeEvidence.persistence.transientRecoveryAbsent) "M299 transient recovery persisted"
    Assert ([bool]$contract.runtimeEvidence.cleanup.postCleanupAbilityRejected -and [bool]$contract.runtimeEvidence.cleanup.idempotent) "M299 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 Brawler Lunge II family contract passed."
