param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3ActionShotPostureDown)) -Raw | ConvertFrom-Json
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
$enginePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/combat_engine.java"
$basePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$skillPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$paths = @($enginePath,$basePath,$actionsPath,$fixturePath,$commandPath,$combatPath,$overridePath,$spamPath,$skillPath)
foreach ($path in $paths) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M255 source: $path" }
$engine = Get-Content -LiteralPath $enginePath -Raw
$base = Get-Content -LiteralPath $basePath -Raw
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$combat = Read-Rows $combatPath
$overrides = Read-Rows $overridePath
$spam = Read-Rows $spamPath
$skills = Read-Rows $skillPath
$name = "actionShot1"
Assert ($actions.Contains("public int actionShot1(") -and
    $actions.Contains("combatStandardAction(`"actionShot1`"")) "Action wrapper drifted"
$c = @($commands | Where-Object commandName -ceq $name)
Assert ($c.Count -eq 1 -and $c[0].defaultTime -ceq "1.5" -and
    $c[0].executeTime -ceq "1.5" -and $c[0].validWeapon -ceq "CARBINE" -and
    $c[0].addToCombatQueue -ceq "1") "Command row drifted"
$d = @($combat | Where-Object actionName -ceq $name)
Assert ($d.Count -eq 1 -and $d[0].percentAddFromWeapon -ceq "1.0" -and
    $d[0].animDefault -ceq "fire_3_single" -and
    $d[0].attackType -ceq "SINGLE_TARGET" -and $d[0].weaponType -ceq "CARBINE" -and
    $d[0].dotType -ceq "bleeding" -and $d[0].dotIntensity -ceq "60" -and
    $d[0].dotDuration -ceq "60") "Combat/DOT row drifted"
$o = @($overrides | Where-Object actionName -ceq $name)
Assert ($o.Count -eq 1 -and $o[0].healthCostMultiplier -ceq "1.75" -and
    $o[0].actionCostMultiplier -ceq "1.25" -and
    $o[0].mindCostMultiplier -ceq "0.5" -and $o[0].targetPool -ceq "ACTION" -and
    $o[0].speedMultiplier -ceq "1.5" -and $o[0].accuracyBonus -ceq "25" -and
    $o[0].animationType -ceq "RANGED" -and $o[0].dotAttribute -ceq "ACTION" -and
    $o[0].postureDownChance -ceq "100") "Override drifted"
$s = @($spam | Where-Object actionName -ceq $name)
Assert ($s.Count -eq 1 -and $s[0].combatSpam -ceq "sapshot") "Spam row drifted"
$owner = @($skills | Where-Object NAME -ceq "combat_marksman_carbine_04")
Assert ($owner.Count -eq 1 -and [string]$owner[0].COMMANDS -match "(^|,)actionShot1(,|$)") "Skill owner drifted"
foreach ($token in @("precuPostureDownChance","dict.put(`"precuPostureDownChance`"",
    "dict.getInt(`"precuPostureDownChance`"")) {
    Assert ($engine.Contains($token)) "Combat-data posture bridge drifted: $token"
}
foreach ($token in @("PRECU_POSTURE_DOWN_RECOVERY","applyPrecuPostureDown(",
    "`"postureDown.result`", `"APPLIED`"","`"postureDown.result`", `"RECOVERY`"",
    "`"force_posture_change_1`"","`"force_posture_change_2`"")) {
    Assert ($base.Contains($token)) "Posture-down resolver drifted: $token"
}
foreach ($token in @("ACTION_SHOT_ONE_COMMAND","CARBINE_CDEF_CERTIFICATION",
    "CDEF_CARBINE_TEMPLATE","actionShotPostureDownChance=","diagnosticPostureDownResult=",
    "ORIGINAL_POSTURE_DOWN_RECOVERY")) {
    Assert ($fixture.Contains($token)) "Fixture drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
$hashChecks = @{
    "combat_engine.java"=$enginePath; "combat_base.java"=$basePath;
    "combat_actions.java"=$actionsPath; "precu_headshot1_fixture.java"=$fixturePath;
    "command_table.tab"=$commandPath; "combat_data.tab"=$combatPath;
    "precu_combat_overrides.tab"=$overridePath; "precu_combat_spam.tab"=$spamPath
}
foreach ($item in $hashChecks.GetEnumerator()) {
    Assert ((Sha $item.Value) -ceq [string]$hashes.($item.Key)) "Source hash drifted: $($item.Key)"
}
$patch = Join-Path $restorationRoot "patches/dsrc/253-p14-core3-action-shot-posture-down.patch"
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M255 is not Ready"
    $command = $contract.runtimeEvidence.command
    Assert ($command.name -ceq "actionShot1" -and $command.queueRemoval -ceq "Success" -and
        [bool]$command.weaponSatisfies -and $command.configuredTargetPool -eq 1 -and
        $command.resolvedTargetPool -eq 1 -and $command.bleedingDot.attribute -eq 3 -and
        $command.bleedingDot.strength -eq 60) "Authenticated Action-only combat evidence drifted"
    Assert ($command.poolObservation.health[1] -eq $command.poolObservation.health[0] -and
        $command.poolObservation.action[1] -lt $command.poolObservation.action[0] -and
        $command.poolObservation.mind[1] -eq $command.poolObservation.mind[0]) "Action-pool proof drifted"
    Assert ($command.postureDown.chance -eq 100 -and
        $command.postureDown.result -ceq "APPLIED" -and
        $command.postureDown.end -gt $command.postureDown.start -and
        $command.recovery.result -ceq "RECOVERY" -and
        $command.recovery.start -gt $command.recovery.end) "Posture application/recovery proof drifted"
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) "Runtime cleanup boundary drifted"
}
Write-Host "Publish 14.1 Core3 action-shot posture-down contract passed."
