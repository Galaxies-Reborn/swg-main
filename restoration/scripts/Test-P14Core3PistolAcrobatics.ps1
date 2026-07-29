param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PistolAcrobatics)
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
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$skillPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
foreach ($path in @($actionsPath,$fixturePath,$commandPath,$combatPath,$overridePath,$spamPath,$skillPath)) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M261 source: $path"
}
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$combat = Read-Rows $combatPath
$overrides = Read-Rows $overridePath
$spam = Read-Rows $spamPath
$skills = Read-Rows $skillPath
$expected = @(
    @{name="rollShot"; spam="rollshot"; posture="POSTURE_CROUCHED"},
    @{name="diveShot"; spam="diveshot"; posture="POSTURE_PRONE"},
    @{name="kipUpShot"; spam="kipup"; posture="POSTURE_UPRIGHT"}
)
foreach ($item in $expected) {
    $name = $item.name
    Assert ($actions.Contains("public int $name(") -and
        $actions.Contains("combatStandardAction(`"$name`"") -and
        $actions.Contains("applyPrecuAcrobaticPosture(self, $($item.posture), `"$name`")")) `
        "$name wrapper drifted"
    $c = @($commands | Where-Object commandName -ceq $name)
    Assert ($c.Count -eq 1 -and $c[0].defaultTime -ceq "1.5" -and
        $c[0].executeTime -ceq "1.5" -and $c[0].validWeapon -ceq "PISTOL" -and
        $c[0].addToCombatQueue -ceq "1") "$name command row drifted"
    $d = @($combat | Where-Object actionName -ceq $name)
    Assert ($d.Count -eq 1 -and $d[0].percentAddFromWeapon -ceq "2.5" -and
        $d[0].animDefault -ceq "fire_acrobatic" -and
        $d[0].attackType -ceq "SINGLE_TARGET" -and
        $d[0].weaponType -ceq "PISTOL") "$name combat row drifted"
    $o = @($overrides | Where-Object actionName -ceq $name)
    Assert ($o.Count -eq 1 -and $o[0].healthCostMultiplier -ceq "0.5" -and
        $o[0].actionCostMultiplier -ceq "0.75" -and
        $o[0].mindCostMultiplier -ceq "0.5" -and
        $o[0].targetPool -ceq "RANDOM" -and
        $o[0].speedMultiplier -ceq "1.5" -and
        $o[0].accuracyBonus -ceq "50" -and
        $o[0].animationType -ceq "NONE") "$name override drifted"
    $s = @($spam | Where-Object actionName -ceq $name)
    Assert ($s.Count -eq 1 -and $s[0].combatSpam -ceq $item.spam) `
        "$name spam row drifted"
}
$owner = @($skills | Where-Object NAME -ceq "combat_marksman_pistol_02")
foreach ($item in $expected) {
    Assert ($owner.Count -eq 1 -and
        [string]$owner[0].COMMANDS -match "(^|,)$($item.name)(,|$)") `
        "Skill owner drifted: $($item.name)"
}
foreach ($token in @(
    "getState(self, STATE_DIZZY) > 0",
    "rand(0, 100) < 85",
    "dizzy_fall_down_single",
    "diagnosticAttackerPostureResult=",
    "ORIGINAL_PISTOL_TWO",
    "ORIGINAL_ROLL_SHOT_COMMAND",
    "ORIGINAL_DIVE_SHOT_COMMAND",
    "ORIGINAL_KIP_UP_SHOT_COMMAND"
)) {
    Assert ($actions.Contains($token) -or $fixture.Contains($token)) `
        "Pistol-acrobatics lifecycle drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
$hashChecks = @{
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
    "patches/dsrc/259-p14-core3-pistol-acrobatics.patch")
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) `
    "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "M261 is not Ready"
    $steps = @($contract.runtimeEvidence.commands)
    Assert ($steps.Count -eq 3) "Authenticated posture sequence is incomplete"
    for ($i = 0; $i -lt $steps.Count; ++$i) {
        Assert ($steps[$i].name -ceq $expected[$i].name -and
            $steps[$i].queueRemoval -ceq "Success" -and
            [bool]$steps[$i].weaponSatisfies -and
            $steps[$i].animation -ceq "fire_acrobatic" -and
            $steps[$i].posture.result -ceq "APPLIED") `
            "Authenticated evidence drifted: $($expected[$i].name)"
    }
    Assert ($steps[0].posture.start -eq 0 -and $steps[0].posture.end -eq 1 -and
        $steps[1].posture.start -eq 1 -and $steps[1].posture.end -eq 2 -and
        $steps[2].posture.start -eq 2 -and $steps[2].posture.end -eq 0) `
        "Natural acrobatic posture lifecycle drifted"
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) `
        "Runtime cleanup boundary drifted"
}
Write-Host "Publish 14.1 Core3 pistol-acrobatics contract passed."
