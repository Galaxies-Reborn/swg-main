param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3SuppressionFireOne)
) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 |
        ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
$basePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$skillPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$paths = @(
    $basePath,$actionsPath,$fixturePath,$commandPath,$combatPath,
    $overridePath,$spamPath,$skillPath
)
foreach ($path in $paths) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M260 source: $path"
}
$base = Get-Content -LiteralPath $basePath -Raw
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$combat = Read-Rows $combatPath
$overrides = Read-Rows $overridePath
$spam = Read-Rows $spamPath
$skills = Read-Rows $skillPath
$name = "suppressionFire1"
Assert ($actions.Contains("public int suppressionFire1(") -and
    $actions.Contains("combatStandardAction(`"suppressionFire1`"")) `
    "SuppressionFire1 wrapper drifted"
$c = @($commands | Where-Object commandName -ceq $name)
Assert ($c.Count -eq 1 -and $c[0].defaultTime -ceq "1.5" -and
    $c[0].executeTime -ceq "1.5" -and $c[0].validWeapon -ceq "RANGED" -and
    $c[0].addToCombatQueue -ceq "1") "Command row drifted"
$d = @($combat | Where-Object actionName -ceq $name)
Assert ($d.Count -eq 1 -and $d[0].percentAddFromWeapon -ceq "1.5" -and
    $d[0].animDefault -ceq "fire_defender_posture_change_down" -and
    $d[0].attackType -ceq "SINGLE_TARGET") "Combat row drifted"
$o = @($overrides | Where-Object actionName -ceq $name)
Assert ($o.Count -eq 1 -and $o[0].healthCostMultiplier -ceq "1.75" -and
    $o[0].actionCostMultiplier -ceq "1.25" -and
    $o[0].mindCostMultiplier -ceq "0.5" -and
    $o[0].targetPool -ceq "HEALTH" -and
    $o[0].speedMultiplier -ceq "1.5" -and
    $o[0].accuracyBonus -ceq "25" -and
    $o[0].animationType -ceq "NONE" -and
    $o[0].postureDownChance -ceq "100") "Override drifted"
$s = @($spam | Where-Object actionName -ceq $name)
Assert ($s.Count -eq 1 -and $s[0].combatSpam -ceq "suppressionfire") `
    "Spam row drifted"
$owner = @($skills |
    Where-Object NAME -ceq "combat_marksman_support_04")
Assert ($owner.Count -eq 1 -and
    [string]$owner[0].COMMANDS -match "(^|,)suppressionFire1(,|$)") `
    "Skill owner drifted"
foreach ($token in @(
    "PRECU_POSTURE_DOWN_RECOVERY",
    "applyPrecuPostureDown(",
    "`"postureDown.result`", `"APPLIED`"",
    "`"postureDown.result`", `"RECOVERY`""
)) {
    Assert ($base.Contains($token)) "Posture-down resolver drifted: $token"
}
foreach ($token in @(
    "MARKSMAN_SUPPORT_FOUR",
    "SUPPRESSION_FIRE_ONE_COMMAND",
    "supportFour=",
    "suppressionFireOneHealthCost=",
    "suppressionFireOnePostureDownChance=",
    "diagnosticPostureDownResult=",
    "ORIGINAL_SUPPORT_FOUR",
    "ORIGINAL_SUPPRESSION_FIRE_ONE_COMMAND"
)) {
    Assert ($fixture.Contains($token)) "Fixture drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
$hashChecks = @{
    "combat_base.java"=$basePath
    "combat_actions.java"=$actionsPath
    "precu_headshot1_fixture.java"=$fixturePath
    "command_table.tab"=$commandPath
    "combat_data.tab"=$combatPath
    "precu_combat_overrides.tab"=$overridePath
    "precu_combat_spam.tab"=$spamPath
}
foreach ($item in $hashChecks.GetEnumerator()) {
    Assert ((Sha $item.Value) -ceq [string]$hashes.($item.Key)) `
        "Source hash drifted: $($item.Key)"
}
$patch = Join-Path $restorationRoot (
    "patches/dsrc/258-p14-core3-suppression-fire-one.patch")
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) `
    "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "M260 is not Ready"
    $command = $contract.runtimeEvidence.command
    Assert ($command.name -ceq $name -and
        $command.queueRemoval -ceq "Success" -and
        [bool]$command.weaponSatisfies -and
        $command.adjustedHamCosts[0] -eq 7 -and
        $command.adjustedHamCosts[1] -eq 18 -and
        $command.adjustedHamCosts[2] -eq 5 -and
        $command.configuredTargetPool -eq 0 -and
        $command.resolvedTargetPool -eq 0) `
        "Authenticated suppression-fire combat evidence drifted"
    Assert ($command.animation -ceq "fire_defender_posture_change_down" -and
        $command.animationType -eq 0 -and
        $command.postureDown.chance -eq 100 -and
        $command.postureDown.result -ceq "APPLIED" -and
        $command.postureDown.end -gt $command.postureDown.start -and
        $command.recovery.result -ceq "RECOVERY" -and
        $command.recovery.start -gt $command.recovery.end) `
        "Posture application/recovery evidence drifted"
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) `
        "Runtime cleanup boundary drifted"
}
Write-Host "Publish 14.1 Core3 suppressionFire1 contract passed."
