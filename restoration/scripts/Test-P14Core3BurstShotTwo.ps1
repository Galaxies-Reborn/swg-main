param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path

function Read-DataRows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0].Split("`t")
    @($lines[2..($lines.Count - 1)] | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}

$actions = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java") -Raw
$fixture = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_marksman_tier1_fixture.java") -Raw
$commands = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab")
$combat = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab")
$overrides = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab")
$spam = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab")
$skills = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab")
$name = "burstShot2"

if (-not $actions.Contains("public int burstShot2(") -or
    -not $actions.Contains('combatStandardAction("burstShot2"')) {
    throw "Action hook drifted."
}

$c = @($commands | Where-Object commandName -ceq $name)
if ($c.Count -ne 1 -or $c[0].defaultTime -cne "2" -or
    $c[0].validWeapon -cne "CARBINE" -or
    $c[0].maxRangeToTarget -cne "64") {
    throw "Command row drifted."
}

$d = @($combat | Where-Object actionName -ceq $name)
if ($d.Count -ne 1 -or $d[0].percentAddFromWeapon -cne "4" -or
    $d[0].animDefault -cne "fire_7_single" -or
    $d[0].anim_carbine -cne "fire_7_single" -or
    $d[0].weaponType -cne "CARBINE" -or
    $d[0].weaponCategory -cne "RANGED_WEAPON" -or
    $d[0].attackType -cne "CONE" -or
    $d[0].coneLength -cne "64" -or $d[0].coneWidth -cne "30" -or
    $d[0].maxRange -cne "64") {
    throw "Combat row drifted."
}

$o = @($overrides | Where-Object actionName -ceq $name)
if ($o.Count -ne 1 -or $o[0].healthCostMultiplier -cne "2" -or
    $o[0].actionCostMultiplier -cne "1.25" -or
    $o[0].mindCostMultiplier -cne "0.5" -or
    $o[0].targetPool -cne "RANDOM" -or
    $o[0].speedMultiplier -cne "2" -or
    $o[0].accuracyBonus -cne "25" -or
    $o[0].animationType -cne "RANGED") {
    throw "Override row drifted."
}

$p = @($spam | Where-Object actionName -ceq $name)
if ($p.Count -ne 1 -or $p[0].combatSpam -cne "burstblast") {
    throw "Spam row drifted."
}

$k = @($skills | Where-Object name -ceq "combat_carbine_ability_03")
if ($k.Count -ne 1 -or ([string]$k[0].COMMANDS).Split(",") -cnotcontains $name) {
    throw "Skill owner drifted."
}

foreach ($token in @(
    'CARBINE_ABILITY_ONE = "combat_carbine_ability_01"',
    'CARBINE_ABILITY_TWO = "combat_carbine_ability_02"',
    'CARBINE_ABILITY_THREE = "combat_carbine_ability_03"',
    'BURST_TWO_COMMAND = "burstShot2"',
    'ORIGINAL_CARBINE_ABILITY_TWO',
    'ORIGINAL_CARBINE_ABILITY_THREE',
    'hasBurstShot2=',
    'canBurstShot2='
)) {
    if (-not $fixture.Contains($token)) {
        throw "Fixture drifted: $token"
    }
}

if ($Expectation -eq "Ready") {
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-burst-shot-two.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        $contract.runtimeEvidence.queueRemoval -cne "Success" -or
        $contract.runtimeEvidence.spamKey -cne "burstblast_hit" -or
        $contract.runtimeEvidence.configuredTargetPool -ne 3 -or
        -not $contract.runtimeEvidence.weaponSatisfies -or
        -not $contract.runtimeEvidence.serverHealthy) {
        throw "Runtime evidence is not ready."
    }
}

Write-Host "Publish 14.1 Core3 Burst Shot II contract passed."
