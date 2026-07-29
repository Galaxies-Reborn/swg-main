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
$fixture = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java") -Raw
$commands = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab")
$combat = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab")
$overrides = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab")
$spam = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab")
$skills = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab")
$name = "unarmedHit2"

if (-not $actions.Contains("public int unarmedHit2(") -or
    -not $actions.Contains('combatStandardAction("unarmedHit2"')) {
    throw "Action hook drifted."
}

$c = @($commands | Where-Object commandName -ceq $name)
if ($c.Count -ne 1 -or $c[0].defaultTime -cne "2.5" -or
    $c[0].executeTime -cne "2.5" -or
    $c[0].validWeapon -cne "UNARMED" -or
    $c[0].maxRangeToTarget -cne "5") {
    throw "Command row drifted."
}

$d = @($combat | Where-Object actionName -ceq $name)
if ($d.Count -ne 1 -or $d[0].percentAddFromWeapon -cne "3" -or
    $d[0].animDefault -cne "combo_3a" -or
    $d[0].anim_unarmed -cne "combo_3a" -or
    $d[0].weaponType -cne "UNARMED" -or
    $d[0].weaponCategory -cne "MELEE_WEAPON" -or
    $d[0].attackType -cne "SINGLE_TARGET" -or
    $d[0].maxRange -cne "5") {
    throw "Combat row drifted."
}

$o = @($overrides | Where-Object actionName -ceq $name)
if ($o.Count -ne 1 -or $o[0].healthCostMultiplier -cne "1.5" -or
    $o[0].actionCostMultiplier -cne "1.5" -or
    $o[0].mindCostMultiplier -cne "1.5" -or
    $o[0].targetPool -cne "RANDOM" -or
    $o[0].speedMultiplier -cne "2.5" -or
    $o[0].accuracyBonus -cne "15" -or
    $o[0].animationType -cne "INTENSITY") {
    throw "Override row drifted."
}

$p = @($spam | Where-Object actionName -ceq $name)
if ($p.Count -ne 1 -or $p[0].combatSpam -cne "goraxsmash") {
    throw "Spam row drifted."
}

$k = @($skills | Where-Object name -ceq "combat_unarmed_novice")
if ($k.Count -ne 1 -or ([string]$k[0].COMMANDS).Split(",") -cnotcontains $name) {
    throw "Skill owner drifted."
}

foreach ($token in @(
    'UNARMED_HIT_TWO_COMMAND = "unarmedHit2"',
    'ORIGINAL_UNARMED_HIT_TWO_COMMAND',
    'unarmedHitTwoCommand=',
    'canPerformUnarmedHitTwo='
)) {
    if (-not $fixture.Contains($token)) {
        throw "Fixture drifted: $token"
    }
}

if ($Expectation -eq "Ready") {
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-unarmed-hit-two.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        $contract.runtimeEvidence.queueRemoval -cne "Success" -or
        $contract.runtimeEvidence.spamKey -cne "goraxsmash_hit" -or
        $contract.runtimeEvidence.configuredTargetPool -ne 3 -or
        -not $contract.runtimeEvidence.weaponSatisfies -or
        -not $contract.runtimeEvidence.serverHealthy) {
        throw "Runtime evidence is not ready."
    }
}

Write-Host "Publish 14.1 Core3 Unarmed Hit II contract passed."
