param([Parameter(Mandatory = $true)][string]$SourceRoot, [ValidateSet("Build", "Ready")][string]$Expectation = "Build")
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-DataRows([string]$Path) { $lines = Get-Content -LiteralPath $Path; $header = $lines[0].Split("`t"); @($lines[2..($lines.Count - 1)] | ConvertFrom-Csv -Delimiter "`t" -Header $header) }
$actions = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java") -Raw
$fixture = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java") -Raw
$commands = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab")
$combat = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab")
$overrides = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab")
$spam = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab")
$costs = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_ham_costs.tab")
$skills = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab")
$name = "fireAcidSingle1"
if (-not $actions.Contains("public int fireAcidSingle1(") -or -not $actions.Contains('combatStandardAction("fireAcidSingle1"') -or -not $actions.Contains('"object/weapon/ranged/heavy/heavy_acid_beam.iff"')) { throw "Action hook or subtype gate drifted." }
$c = @($commands | Where-Object commandName -ceq $name)
if ($c.Count -ne 1 -or $c[0].defaultTime -cne "4" -or $c[0].executeTime -cne "4" -or $c[0].validWeapon -cne "HEAVY" -or $c[0].maxRangeToTarget -cne "16") { throw "Command row drifted." }
$d = @($combat | Where-Object actionName -ceq $name)
if ($d.Count -ne 1 -or $d[0].percentAddFromWeapon -cne "5" -or $d[0].animDefault -cne "fire_acid_rifle_single_1" -or $d[0].anim_heavyweapon -cne "fire_acid_rifle_single_1" -or $d[0].weaponType -cne "HEAVY" -or $d[0].weaponCategory -cne "RANGED_WEAPON" -or $d[0].attackType -cne "SINGLE_TARGET" -or $d[0].maxRange -cne "16") { throw "Combat row drifted." }
$o = @($overrides | Where-Object actionName -ceq $name)
if ($o.Count -ne 1 -or $o[0].healthCostMultiplier -cne "1.5" -or $o[0].actionCostMultiplier -cne "0.5" -or $o[0].mindCostMultiplier -cne "0.5" -or $o[0].targetPool -cne "RANDOM" -or $o[0].speedMultiplier -cne "4" -or $o[0].accuracyBonus -cne "0" -or $o[0].animationType -cne "INTENSITY") { throw "Override row drifted." }
$s = @($spam | Where-Object actionName -ceq $name)
if ($s.Count -ne 1 -or $s[0].combatSpam -cne "fireacidsingle1") { throw "Spam row drifted." }
$w = @($costs | Where-Object templateName -ceq "object/weapon/ranged/heavy/heavy_acid_beam.iff")
if ($w.Count -ne 1 -or $w[0].healthCost -cne "60" -or $w[0].actionCost -cne "60" -or $w[0].mindCost -cne "15") { throw "Weapon HAM row drifted." }
$k = @($skills | Where-Object name -ceq "combat_commando_support_01")
if ($k.Count -ne 1 -or ([string]$k[0].COMMANDS).Split(",") -cnotcontains $name) { throw "Skill owner drifted." }
foreach ($token in @('ACID_SINGLE_ONE_COMMAND = "fireAcidSingle1"', 'ORIGINAL_ACID_SINGLE_ONE_COMMAND', 'ACID_CERTIFICATION = "cert_heavy_acid_beam"', 'object/weapon/ranged/heavy/heavy_acid_beam.iff', 'FIXTURE_ACID', 'equipFixtureAcid', 'equipOverride(weapon, attacker)', 'acidSingleOneCommand=', 'canPerformAcidSingleOne=')) { if (-not $fixture.Contains($token)) { throw "Fixture drifted: $token" } }
if ($Expectation -eq "Ready") { $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-fire-acid-single-one.json") -Raw | ConvertFrom-Json; if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or $contract.runtimeEvidence.queueRemoval -cne "Success" -or $contract.runtimeEvidence.spamKey -cne "fireacidsingle1_hit" -or $contract.runtimeEvidence.configuredTargetPool -ne 3 -or -not $contract.runtimeEvidence.weaponSatisfies -or -not $contract.runtimeEvidence.serverHealthy) { throw "Runtime evidence is not ready." } }
Write-Host "Publish 14.1 Core3 Fire Acid Single I contract passed."
