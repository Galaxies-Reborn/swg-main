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
$cases = @(
    [pscustomobject]@{ Name="headShot2"; Owner="combat_marksman_rifle_03"; Damage="2.5"; Speed="1.5"; Health="0.5"; Action="0.5"; Mind="1.5"; Spam="expertheadshot" },
    [pscustomobject]@{ Name="headShot3"; Owner="combat_rifleman_accuracy_02"; Damage="3"; Speed="2"; Health="0.5"; Action="0.5"; Mind="2.5"; Spam="masterheadshot" }
)
foreach ($case in $cases) {
    foreach ($token in @("public int $($case.Name)(", "combatStandardAction(`"$($case.Name)`"")) { if (-not $actions.Contains($token)) { throw "$($case.Name) hook drifted: $token" } }
    $command = @($commandRows | Where-Object commandName -ceq $case.Name); if ($command.Count -ne 1 -or $command[0].defaultTime -cne $case.Speed -or $command[0].validWeapon -cne "RIFLE" -or $command[0].addToCombatQueue -cne "1") { throw "$($case.Name) command row drifted." }
    $combat = @($combatRows | Where-Object actionName -ceq $case.Name); if ($combat.Count -ne 1 -or $combat[0].percentAddFromWeapon -cne $case.Damage -or $combat[0].animDefault -cne "fire_1_special_single" -or $combat[0].weaponType -cne "RIFLE") { throw "$($case.Name) combat row drifted." }
    $override = @($overrideRows | Where-Object actionName -ceq $case.Name); if ($override.Count -ne 1 -or $override[0].healthCostMultiplier -cne $case.Health -or $override[0].actionCostMultiplier -cne $case.Action -or $override[0].mindCostMultiplier -cne $case.Mind -or $override[0].targetPool -cne "MIND" -or $override[0].speedMultiplier -cne $case.Speed -or $override[0].accuracyBonus -cne "5" -or $override[0].animationType -cne "RANGED") { throw "$($case.Name) override row drifted." }
    $spam = @($spamRows | Where-Object actionName -ceq $case.Name); if ($spam.Count -ne 1 -or $spam[0].combatSpam -cne $case.Spam) { throw "$($case.Name) spam row drifted." }
    $skill = @($skillRows | Where-Object name -ceq $case.Owner); if ($skill.Count -ne 1 -or ([string]$skill[0].COMMANDS).Split(",") -cnotcontains $case.Name) { throw "$($case.Name) owner drifted." }
}
foreach ($token in @('HEAD_SHOT_THREE_COMMAND = "headShot3"','ORIGINAL_HEAD_SHOT_THREE_COMMAND','canPerformHeadShotTwo=','canPerformHeadShotThree=')) { if (-not $fixture.Contains($token)) { throw "Head-shot fixture drifted: $token" } }
if ($Expectation -eq "Ready") { $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-head-shot-continuation.json") -Raw | ConvertFrom-Json; if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or $contract.runtimeEvidence.fixtureCleanup -ne "passed" -or $contract.runtimeEvidence.idempotentCleanup -ne "passed" -or -not $contract.runtimeEvidence.serverHealthy) { throw "Core3 head-shot continuation evidence is not ready." } }
Write-Host "Publish 14.1 Core3 head-shot continuation contract passed."
