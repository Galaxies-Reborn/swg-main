param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3AimCommand)) -Raw | ConvertFrom-Json
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
$basePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$skillPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$buffPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
$paths = @($basePath,$actionsPath,$fixturePath,$commandPath,$combatPath,$overridePath,$spamPath,$skillPath,$buffPath)
foreach ($path in $paths) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M259 source: $path" }
$base = Get-Content -LiteralPath $basePath -Raw
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$combat = Read-Rows $combatPath
$overrides = Read-Rows $overridePath
$spam = Read-Rows $spamPath
$skills = Read-Rows $skillPath
$buffs = Read-Rows $buffPath
$command = @($commands | Where-Object commandName -ceq "aim")
Assert ($command.Count -eq 1 -and $command[0].defaultTime -ceq "1.5" -and
    $command[0].executeTime -ceq "1.5" -and $command[0].validWeapon -ceq "RANGED" -and
    $command[0].addToCombatQueue -ceq "1") "Aim command row drifted"
$data = @($combat | Where-Object actionName -ceq "aim")
Assert ($data.Count -eq 1 -and $data[0].percentAddFromWeapon -ceq "0" -and
    $data[0].attackType -ceq "SINGLE_TARGET" -and $data[0].maxRange -ceq "64" -and
    $data[0].weaponType -ceq "RIFLE" -and $data[0].specialLine -ceq "marksman") "Aim combat row drifted"
$override = @($overrides | Where-Object actionName -ceq "aim")
Assert ($override.Count -eq 1 -and $override[0].healthCostMultiplier -ceq "3" -and
    $override[0].actionCostMultiplier -ceq "0" -and $override[0].mindCostMultiplier -ceq "0" -and
    $override[0].targetPool -ceq "HEALTH" -and $override[0].speedMultiplier -ceq "1" -and
    $override[0].accuracyBonus -ceq "0" -and $override[0].animationType -ceq "NONE") "Aim override drifted"
$spamRow = @($spam | Where-Object actionName -ceq "aim")
Assert ($spamRow.Count -eq 1 -and $spamRow[0].combatSpam -ceq "aim") "Aim spam row drifted"
$owner = @($skills | Where-Object NAME -ceq "combat_marksman_support_01")
Assert ($owner.Count -eq 1 -and [string]$owner[0].COMMANDS -match "(^|,)aim(,|$)" -and
    [string]$owner[0].SKILL_MODS -match "(^|,)aim=10(,|$)") "Aim skill ownership drifted"
$retainedBuff = @($buffs | Where-Object NAME -ceq "aim")
Assert ($retainedBuff.Count -eq 1 -and $retainedBuff[0].DURATION -ceq "15" -and
    $retainedBuff[0].EFFECT1_PARAM -ceq "private_accuracy_bonus") "Retained aim buff evidence drifted"
foreach ($token in @(
    'public static final String PRECU_AIM_MODIFIER = "precu_aim"',
    'recordPrecuLiveDiagnostic(self, "aim.consumed", 1)',
    'removeAttribOrSkillModModifier(self, PRECU_AIM_MODIFIER)',
    'setState(self, STATE_AIMING, false)'
)) {
    Assert ($base.Contains($token)) "Aim consumption lifecycle drifted: $token"
}
foreach ($token in @(
    "public int aim(",
    'getEnhancedSkillStatisticModifierUncapped(self, "aim")',
    'weaponFamily + "_aim"',
    '"private_aim", aimBonus, 5.0f, true, false',
    "boolean alreadyAiming",
    'recordPrecuLiveDiagnostic(self, "aim.alreadyActive"',
    "public int OnSkillModDone(",
    'recordPrecuLiveDiagnostic(self, "aim.expired", 1)'
)) {
    Assert ($actions.Contains($token)) "Aim command lifecycle drifted: $token"
}
foreach ($token in @(
    "MARKSMAN_SUPPORT_ONE","AIM_COMMAND","ORIGINAL_SUPPORT_ONE","ORIGINAL_AIM_COMMAND",
    "supportOne=","aimHealthCost=","aimState=","aimModifierPresent=","aimPrivateBonus=",
    "aimConfiguredBonus=","aimAlreadyActive=","aimConsumed=","aimExpired=",
    "diagnosticAccuracyPrivate=","canPerformAim="
)) {
    Assert ($fixture.Contains($token)) "Aim fixture drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
$hashChecks = @{
    "combat_base.java"=$basePath; "combat_actions.java"=$actionsPath;
    "precu_headshot1_fixture.java"=$fixturePath; "command_table.tab"=$commandPath;
    "combat_data.tab"=$combatPath; "precu_combat_overrides.tab"=$overridePath;
    "precu_combat_spam.tab"=$spamPath
}
foreach ($item in $hashChecks.GetEnumerator()) {
    Assert ((Sha $item.Value) -ceq [string]$hashes.($item.Key)) "Source hash drifted: $($item.Key)"
}
$patch = Join-Path $restorationRoot "patches/dsrc/257-p14-core3-aim-command.patch"
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M259 is not Ready"
    $proof = $contract.runtimeEvidence.command
    Assert ($proof.name -ceq "aim" -and $proof.adjustedHamCosts[0] -eq 12 -and
        $proof.adjustedHamCosts[1] -eq 0 -and $proof.adjustedHamCosts[2] -eq 0 -and
        $proof.queueRemoval -ceq "Success" -and $proof.active.state -eq 1 -and
        [bool]$proof.active.modifierPresent -and $proof.active.privateAimBonus -eq 30 -and
        $proof.expiry.expired -eq 1 -and [bool]$proof.repeatNoRefresh.expiredOnOriginalDeadline -and
        $proof.nextSuccessfulCombatAction.aimContribution -eq 30 -and
        $proof.nextSuccessfulCombatAction.consumed -eq 1) "Authenticated aim lifecycle proof drifted"
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) "Runtime cleanup boundary drifted"
}
Write-Host "Publish 14.1 Core3 aim-command contract passed."
