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
$specs = @(
    @{ Name = "melee1hBodyHit2"; Time = "2"; Damage = "2.5"; Animation = "combo_4b"; Health = "0.75"; Action = "0.75"; Mind = "1.25"; Speed = "2"; Spam = "saisun"; Owner = "combat_1hsword_ability_01" },
    @{ Name = "melee1hBodyHit3"; Time = "2.25"; Damage = "3.5"; Animation = "combo_3a"; Health = "1"; Action = "1"; Mind = "2"; Speed = "2.25"; Spam = "saitok"; Owner = "combat_1hsword_ability_03" }
)

foreach ($spec in $specs) {
    $name = $spec.Name
    foreach ($token in @("public int $name(", "combatStandardAction(`"$name`"")) { if (-not $actions.Contains($token)) { throw "$name hook drifted: $token" } }
    $command = @($commandRows | Where-Object commandName -ceq $name)
    if ($command.Count -ne 1 -or $command[0].defaultTime -cne $spec.Time -or $command[0].validWeapon -cne "1HAND_MELEE" -or $command[0].addToCombatQueue -cne "1") { throw "$name command row drifted." }
    $combat = @($combatRows | Where-Object actionName -ceq $name)
    if ($combat.Count -ne 1 -or $combat[0].percentAddFromWeapon -cne $spec.Damage -or $combat[0].animDefault -cne $spec.Animation -or $combat[0].weaponType -cne "1HAND_MELEE" -or $combat[0].attackType -cne "SINGLE_TARGET") { throw "$name combat row drifted." }
    $override = @($overrideRows | Where-Object actionName -ceq $name)
    if ($override.Count -ne 1 -or $override[0].healthCostMultiplier -cne $spec.Health -or $override[0].actionCostMultiplier -cne $spec.Action -or $override[0].mindCostMultiplier -cne $spec.Mind -or $override[0].targetPool -cne "HEALTH" -or $override[0].speedMultiplier -cne $spec.Speed -or $override[0].accuracyBonus -cne "25" -or $override[0].animationType -cne "INTENSITY") { throw "$name override row drifted." }
    $spam = @($spamRows | Where-Object actionName -ceq $name)
    if ($spam.Count -ne 1 -or $spam[0].combatSpam -cne $spec.Spam) { throw "$name spam row drifted." }
    $skill = @($skillRows | Where-Object name -ceq $spec.Owner)
    if ($skill.Count -ne 1 -or ([string]$skill[0].COMMANDS).Split(",") -cnotcontains $name) { throw "$name owner drifted." }
}
foreach ($token in @('ONE_HAND_BODY_TWO_COMMAND = "melee1hBodyHit2"','ONE_HAND_BODY_THREE_COMMAND = "melee1hBodyHit3"','ORIGINAL_ONE_HAND_BODY_TWO_COMMAND','ORIGINAL_ONE_HAND_BODY_THREE_COMMAND','canPerformOneHandBodyTwo=','canPerformOneHandBodyThree=')) { if (-not $fixture.Contains($token)) { throw "One-hand continuation fixture drifted: $token" } }
if ($Expectation -eq "Ready") {
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-one-hand-body-hit-continuation.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or $contract.runtimeEvidence.commands.Count -ne 2 -or @($contract.runtimeEvidence.commands | Where-Object queueRemoval -cne "Success").Count -ne 0 -or $contract.runtimeEvidence.fixtureCleanup -ne "passed" -or $contract.runtimeEvidence.idempotentCleanup -ne "passed" -or -not $contract.runtimeEvidence.serverHealthy) { throw "Core3 one-hand body-hit continuation evidence is not ready." }
}
Write-Host "Publish 14.1 Core3 one-hand body-hit continuation contract passed."
