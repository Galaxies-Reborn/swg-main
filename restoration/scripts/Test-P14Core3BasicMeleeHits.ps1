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
 @{N="melee1hHit1";W="1HAND_MELEE";T="1.5";D="2.5";H="0.5";A="0.5";M="0.625";S="1.5";X="25";I="counter_high_center";P="chomai";O="combat_brawler_1handmelee_01"},
 @{N="melee1hHit2";W="1HAND_MELEE";T="1.5";D="3.5";H="0.75";A="0.75";M="1.25";S="1.5";X="25";I="combo_4a";P="chosun";O="combat_1hsword_novice"},
 @{N="melee2hHit1";W="2HAND_MELEE";T="1.5";D="2";H="0.5";A="1";M="0.5";S="1.5";X="10";I="combo_2c";P="terriblestrike";O="combat_brawler_2handmelee_01"},
 @{N="melee2hHit2";W="2HAND_MELEE";T="2";D="3";H="1";A="1.5";M="1";S="2";X="10";I="combo_2a";P="violentstrike";O="combat_2hsword_novice"}
)
foreach($s in $specs) {
 if(-not $actions.Contains("public int $($s.N)(") -or -not $actions.Contains("combatStandardAction(`"$($s.N)`"")){throw "$($s.N) hook drifted."}
 $c=@($commands|Where-Object commandName -ceq $s.N); if($c.Count-ne 1-or$c[0].defaultTime-cne$s.T-or$c[0].validWeapon-cne$s.W){throw "$($s.N) command drifted."}
 $d=@($combat|Where-Object actionName -ceq $s.N); if($d.Count-ne 1-or$d[0].percentAddFromWeapon-cne$s.D-or$d[0].animDefault-cne$s.I-or$d[0].weaponType-cne$s.W-or$d[0].attackType-cne"SINGLE_TARGET"){throw "$($s.N) combat drifted."}
 $o=@($overrides|Where-Object actionName -ceq $s.N); if($o.Count-ne 1-or$o[0].healthCostMultiplier-cne$s.H-or$o[0].actionCostMultiplier-cne$s.A-or$o[0].mindCostMultiplier-cne$s.M-or$o[0].targetPool-cne"RANDOM"-or$o[0].speedMultiplier-cne$s.S-or$o[0].accuracyBonus-cne$s.X-or$o[0].animationType-cne"INTENSITY"){throw "$($s.N) override drifted."}
 $p=@($spam|Where-Object actionName -ceq $s.N); if($p.Count-ne 1-or$p[0].combatSpam-cne$s.P){throw "$($s.N) spam drifted."}
 $k=@($skills|Where-Object name -ceq $s.O); if($k.Count-ne 1-or([string]$k[0].COMMANDS).Split(",")-cnotcontains$s.N){throw "$($s.N) owner drifted."}
}
foreach($token in @('ONE_HAND_HIT_ONE_COMMAND = "melee1hHit1"','ONE_HAND_HIT_TWO_COMMAND = "melee1hHit2"','TWO_HAND_HIT_ONE_COMMAND = "melee2hHit1"','TWO_HAND_HIT_TWO_COMMAND = "melee2hHit2"','ORIGINAL_ONE_HAND_HIT_ONE_COMMAND','ORIGINAL_ONE_HAND_HIT_TWO_COMMAND','ORIGINAL_TWO_HAND_HIT_ONE_COMMAND','ORIGINAL_TWO_HAND_HIT_TWO_COMMAND','canPerformOneHandHitOne=','canPerformOneHandHitTwo=','canPerformTwoHandHitOne=','canPerformTwoHandHitTwo=')){if(-not$fixture.Contains($token)){throw "Fixture drifted: $token"}}
if($Expectation-eq"Ready"){$contract=Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-basic-melee-hits.json") -Raw|ConvertFrom-Json;if($contract.status-ne"ready"-or$contract.runtimeEvidence.result-ne"passed"-or$contract.runtimeEvidence.commands.Count-ne 4-or@($contract.runtimeEvidence.commands|Where-Object queueRemoval -cne "Success").Count-ne 0-or-not$contract.runtimeEvidence.serverHealthy){throw "Runtime evidence is not ready."}}
Write-Host "Publish 14.1 Core3 basic melee-hit contract passed."
