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
$skills = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab")
$specs = @(
 @{N="polearmLegHit2";T="1.75";D="2";H="1.5";A="1";M="1";S="1.75";I="combo_3c";P="legsmasher";O="combat_polearm_speed_01"},
 @{N="polearmLegHit3";T="2.25";D="2.5";H="2";A="1.5";M="1.5";S="2.25";I="combo_3b";P="legbreaker";O="combat_polearm_speed_03"}
)
foreach($s in $specs) {
 if(-not $actions.Contains("public int $($s.N)(") -or -not $actions.Contains("combatStandardAction(`"$($s.N)`"")){throw "$($s.N) hook drifted."}
 $c=@($commands|Where-Object commandName -ceq $s.N); if($c.Count-ne 1-or$c[0].defaultTime-cne$s.T-or$c[0].validWeapon-cne"POLEARM"){throw "$($s.N) command drifted."}
 $d=@($combat|Where-Object actionName -ceq $s.N); if($d.Count-ne 1-or$d[0].percentAddFromWeapon-cne$s.D-or$d[0].animDefault-cne$s.I-or$d[0].weaponType-cne"POLEARM"-or$d[0].attackType-cne"SINGLE_TARGET"){throw "$($s.N) combat drifted."}
 $o=@($overrides|Where-Object actionName -ceq $s.N); if($o.Count-ne 1-or$o[0].healthCostMultiplier-cne$s.H-or$o[0].actionCostMultiplier-cne$s.A-or$o[0].mindCostMultiplier-cne$s.M-or$o[0].targetPool-cne"ACTION"-or$o[0].speedMultiplier-cne$s.S-or$o[0].accuracyBonus-cne"10"-or$o[0].animationType-cne"INTENSITY"){throw "$($s.N) override drifted."}
 $p=@($spam|Where-Object actionName -ceq $s.N); if($p.Count-ne 1-or$p[0].combatSpam-cne$s.P){throw "$($s.N) spam drifted."}
 $k=@($skills|Where-Object name -ceq $s.O); if($k.Count-ne 1-or([string]$k[0].COMMANDS).Split(",")-cnotcontains$s.N){throw "$($s.N) owner drifted."}
}
foreach($token in @('POLEARM_LEG_TWO_COMMAND = "polearmLegHit2"','POLEARM_LEG_THREE_COMMAND = "polearmLegHit3"','ORIGINAL_POLEARM_LEG_TWO_COMMAND','ORIGINAL_POLEARM_LEG_THREE_COMMAND','canPerformPolearmLegTwo=','canPerformPolearmLegThree=')){if(-not$fixture.Contains($token)){throw "Fixture drifted: $token"}}
if($Expectation-eq"Ready"){$contract=Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-polearm-leg-hit-continuation.json") -Raw|ConvertFrom-Json;if($contract.status-ne"ready"-or$contract.runtimeEvidence.result-ne"passed"-or$contract.runtimeEvidence.commands.Count-ne 2-or@($contract.runtimeEvidence.commands|Where-Object queueRemoval -cne "Success").Count-ne 0-or-not$contract.runtimeEvidence.serverHealthy){throw "Runtime evidence is not ready."}}
Write-Host "Publish 14.1 Core3 polearm leg-hit continuation contract passed."
