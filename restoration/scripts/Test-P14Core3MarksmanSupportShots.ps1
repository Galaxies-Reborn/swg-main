param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3MarksmanSupportShots)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$skillPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$paths = @($actionsPath,$fixturePath,$commandPath,$combatPath,$overridePath,$spamPath,$skillPath)
foreach ($path in $paths) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M258 source: $path" }
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$combat = Read-Rows $combatPath
$overrides = Read-Rows $overridePath
$spam = Read-Rows $spamPath
$skills = Read-Rows $skillPath
$expectations = @(
    @{
        name="threatenShot"; owner="combat_marksman_support_01";
        animation="fire_1_special_single"; animationType="RANGED"; spam="threatenshot"
    },
    @{
        name="warningShot"; owner="combat_marksman_support_03";
        animation="fire_area"; animationType="INTENSITY"; spam="warningshot"
    }
)
foreach ($expected in $expectations) {
    $name = [string]$expected.name
    Assert ($actions.Contains("public int $name(") -and
        $actions.Contains("combatStandardAction(`"$name`"")) "Action wrapper drifted: $name"
    $c = @($commands | Where-Object commandName -ceq $name)
    Assert ($c.Count -eq 1 -and $c[0].defaultTime -ceq "1.5" -and
        $c[0].executeTime -ceq "1.5" -and $c[0].validWeapon -ceq "RANGED" -and
        $c[0].addToCombatQueue -ceq "1") "Command row drifted: $name"
    $d = @($combat | Where-Object actionName -ceq $name)
    Assert ($d.Count -eq 1 -and $d[0].percentAddFromWeapon -ceq "0.25" -and
        $d[0].animDefault -ceq [string]$expected.animation -and
        $d[0].attackType -ceq "SINGLE_TARGET" -and $d[0].maxRange -ceq "64" -and
        $d[0].weaponType -ceq "RIFLE" -and $d[0].specialLine -ceq "marksman") "Combat row drifted: $name"
    $o = @($overrides | Where-Object actionName -ceq $name)
    Assert ($o.Count -eq 1 -and $o[0].healthCostMultiplier -ceq "1" -and
        $o[0].actionCostMultiplier -ceq "1" -and $o[0].mindCostMultiplier -ceq "1" -and
        $o[0].targetPool -ceq "RANDOM" -and $o[0].speedMultiplier -ceq "2" -and
        $o[0].accuracyBonus -ceq "15" -and
        $o[0].animationType -ceq [string]$expected.animationType) "Override drifted: $name"
    $s = @($spam | Where-Object actionName -ceq $name)
    Assert ($s.Count -eq 1 -and $s[0].combatSpam -ceq [string]$expected.spam) "Spam row drifted: $name"
    $ownerName = [string]$expected.owner
    $owner = @($skills | Where-Object NAME -ceq $ownerName)
    Assert ($owner.Count -eq 1 -and
        [string]$owner[0].COMMANDS -match "(^|,)$name(,|$)") "Skill ownership drifted: $name"
}
foreach ($token in @("THREATEN_SHOT_COMMAND","WARNING_SHOT_COMMAND",
    "ORIGINAL_THREATEN_SHOT_COMMAND","ORIGINAL_WARNING_SHOT_COMMAND",
    "threatenShotHealthCost=","warningShotHealthCost=",
    "canPerformThreatenShot=","canPerformWarningShot=")) {
    Assert ($fixture.Contains($token)) "Fixture drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
$hashChecks = @{
    "combat_actions.java"=$actionsPath; "precu_headshot1_fixture.java"=$fixturePath;
    "command_table.tab"=$commandPath; "combat_data.tab"=$combatPath;
    "precu_combat_overrides.tab"=$overridePath; "precu_combat_spam.tab"=$spamPath
}
foreach ($item in $hashChecks.GetEnumerator()) {
    Assert ((Sha $item.Value) -ceq [string]$hashes.($item.Key)) "Source hash drifted: $($item.Key)"
}
$patch = Join-Path $restorationRoot "patches/dsrc/256-p14-core3-marksman-support-shots.patch"
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M258 is not Ready"
    foreach ($name in @("threatenShot","warningShot")) {
        $proof = $contract.runtimeEvidence.commands.$name
        Assert ($proof.name -ceq $name -and $proof.queueRemoval -ceq "Success" -and
            [bool]$proof.weaponSatisfies -and $proof.configuredTargetPool -eq 3 -and
            $proof.resolvedTargetPool -ge 0 -and $proof.resolvedTargetPool -le 2 -and
            $proof.directDamage -gt 0) "Authenticated RANDOM-pool proof drifted: $name"
    }
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) "Runtime cleanup boundary drifted"
}
Write-Host "Publish 14.1 Core3 Marksman support-shot contract passed."
