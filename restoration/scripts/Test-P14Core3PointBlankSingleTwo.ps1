param([Parameter(Mandatory = $true)][string]$SourceRoot, [ValidateSet("Build", "Ready")][string]$Expectation = "Build")
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-DataRows([string]$Path) { $lines = Get-Content -LiteralPath $Path; $header = $lines[0].Split("`t"); @($lines[2..($lines.Count - 1)] | ConvertFrom-Csv -Delimiter "`t" -Header $header) }
$actions = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java") -Raw
$fixture = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_marksman_tier1_fixture.java") -Raw
$commands = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab")
$combat = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab")
$overrides = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab")
$spam = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab")
$skills = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab")
$name = "pointBlankSingle2"
if (-not $actions.Contains("public int pointBlankSingle2(") -or -not $actions.Contains('combatStandardAction("pointBlankSingle2"')) { throw "Action hook drifted." }
$c = @($commands | Where-Object commandName -ceq $name); if ($c.Count -ne 1 -or $c[0].defaultTime -cne "1.8" -or $c[0].validWeapon -cne "PISTOL") { throw "Command row drifted." }
$d = @($combat | Where-Object actionName -ceq $name); if ($d.Count -ne 1 -or $d[0].percentAddFromWeapon -cne "3" -or $d[0].animDefault -cne "fire_5_single" -or $d[0].anim_pistol -cne "fire_5_single" -or $d[0].weaponType -cne "PISTOL" -or $d[0].attackType -cne "SINGLE_TARGET" -or $d[0].maxRange -cne "10") { throw "Combat row drifted." }
$o = @($overrides | Where-Object actionName -ceq $name); if ($o.Count -ne 1 -or $o[0].healthCostMultiplier -cne "1" -or $o[0].actionCostMultiplier -cne "1" -or $o[0].mindCostMultiplier -cne "1" -or $o[0].targetPool -cne "RANDOM" -or $o[0].speedMultiplier -cne "1.8" -or $o[0].accuracyBonus -cne "0" -or $o[0].animationType -cne "RANGED") { throw "Override row drifted." }
$p = @($spam | Where-Object actionName -ceq $name); if ($p.Count -ne 1 -or $p[0].combatSpam -cne "pointblankblast") { throw "Spam row drifted." }
$k = @($skills | Where-Object name -ceq "combat_pistol_accuracy_01"); if ($k.Count -ne 1 -or ([string]$k[0].COMMANDS).Split(",") -cnotcontains $name) { throw "Skill owner drifted." }
foreach ($token in @('PISTOL_ACCURACY_ONE = "combat_pistol_accuracy_01"', 'POINT_BLANK_SINGLE_TWO_COMMAND = "pointBlankSingle2"', 'ORIGINAL_PISTOL_ACCURACY_ONE', 'pistolAccuracyOne=', 'hasPointBlankSingle2=', 'canPointBlankSingle2=')) { if (-not $fixture.Contains($token)) { throw "Fixture drifted: $token" } }
if ($Expectation -eq "Ready") { $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-point-blank-single-two.json") -Raw | ConvertFrom-Json; if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or $contract.runtimeEvidence.queueRemoval -cne "Success" -or $contract.runtimeEvidence.spamKey -cne "pointblankblast_hit" -or $contract.runtimeEvidence.configuredTargetPool -ne 3 -or -not $contract.runtimeEvidence.weaponSatisfies -or -not $contract.runtimeEvidence.pistolAccuracyOneReversible -or -not $contract.runtimeEvidence.serverHealthy) { throw "Runtime evidence is not ready." } }
Write-Host "Publish 14.1 Core3 Point Blank Single II contract passed."
