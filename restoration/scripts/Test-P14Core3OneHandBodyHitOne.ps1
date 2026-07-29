param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-DataRows([string]$Path) { $lines = Get-Content -LiteralPath $Path; $header = $lines[0].Split("`t"); return @($lines[2..($lines.Count - 1)] | ConvertFrom-Csv -Delimiter "`t" -Header $header) }

$actions = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java") -Raw
$fixture = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java") -Raw
$commandRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab")
$combatRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab")
$overrideRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab")
$spamRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab")
$skillRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab")
$name = "melee1hBodyHit1"

foreach ($token in @("public int $name(", "combatStandardAction(`"$name`"")) { if (-not $actions.Contains($token)) { throw "$name hook drifted: $token" } }
$command = @($commandRows | Where-Object commandName -ceq $name)
if ($command.Count -ne 1 -or $command[0].defaultTime -cne "1.5" -or $command[0].validWeapon -cne "1HAND_MELEE" -or $command[0].addToCombatQueue -cne "1") { throw "$name command row drifted." }
$combat = @($combatRows | Where-Object actionName -ceq $name)
if ($combat.Count -ne 1 -or $combat[0].percentAddFromWeapon -cne "1.5" -or $combat[0].animDefault -cne "counter_high_right" -or $combat[0].weaponType -cne "1HAND_MELEE" -or $combat[0].attackType -cne "SINGLE_TARGET") { throw "$name combat row drifted." }
$override = @($overrideRows | Where-Object actionName -ceq $name)
if ($override.Count -ne 1 -or $override[0].healthCostMultiplier -cne "0.5" -or $override[0].actionCostMultiplier -cne "0.5" -or $override[0].mindCostMultiplier -cne "0.625" -or $override[0].targetPool -cne "HEALTH" -or $override[0].speedMultiplier -cne "1.5" -or $override[0].accuracyBonus -cne "25" -or $override[0].animationType -cne "INTENSITY") { throw "$name override row drifted." }
$spam = @($spamRows | Where-Object actionName -ceq $name)
if ($spam.Count -ne 1 -or $spam[0].combatSpam -cne "saimai") { throw "$name spam row drifted." }
$skill = @($skillRows | Where-Object name -ceq "combat_brawler_1handmelee_02")
if ($skill.Count -ne 1 -or ([string]$skill[0].COMMANDS).Split(",") -cnotcontains $name) { throw "$name owner drifted." }
foreach ($token in @('ONE_HAND_BODY_ONE_COMMAND = "melee1hBodyHit1"','ORIGINAL_ONE_HAND_BODY_ONE_COMMAND','canPerformOneHandBodyOne=')) { if (-not $fixture.Contains($token)) { throw "One-hand body-hit fixture drifted: $token" } }
if ($Expectation -eq "Ready") { $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-one-hand-body-hit-one.json") -Raw | ConvertFrom-Json; if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or $contract.runtimeEvidence.queueRemoval -ne "Success" -or $contract.runtimeEvidence.fixtureCleanup -ne "passed" -or $contract.runtimeEvidence.idempotentCleanup -ne "passed" -or -not $contract.runtimeEvidence.serverHealthy) { throw "Core3 one-hand body-hit evidence is not ready." } }
Write-Host "Publish 14.1 Core3 one-hand body-hit-one contract passed."
