param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3ScatterShots)
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
$paths = @{
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    engine = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/combat_engine.java"
    base = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    override = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    command = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M264 source: $path"
}
$commands = Read-Rows $paths.command
$skills = Read-Rows $paths.skills
$combatRows = Read-Rows $paths.combat
$overrides = Read-Rows $paths.override
$spamRows = Read-Rows $paths.spam
$expected = @{
    scatterShot1 = @{
        owner="combat_carbine_accuracy_01"; damage="3.25"; health="1.75";
        action="1.25"; mind="0.5"; rolls="2"; increment="0.5";
        spam="scattershot"
    }
    scatterShot2 = @{
        owner="combat_carbine_accuracy_03"; damage="5"; health="2";
        action="1.25"; mind="0.5"; rolls="3"; increment="0.34";
        spam="scatterblast"
    }
}
foreach ($name in @("scatterShot1","scatterShot2")) {
    $want = $expected[$name]
    $command = @($commands | Where-Object commandName -ceq $name)
    Assert ($command.Count -eq 1 -and
        $command[0].scriptHook -ceq $name -and
        $command[0].defaultTime -ceq "1.5" -and
        $command[0].executeTime -ceq "1.5" -and
        $command[0].target -ceq "other" -and
        $command[0].targetType -ceq "optional" -and
        $command[0].commandGroup -ceq "391413347" -and
        $command[0].addToCombatQueue -ceq "1" -and
        $command[0].validWeapon -ceq "CARBINE") "$name command row drifted"
    $owners = @($skills | Where-Object {
        [string]$_.COMMANDS -match "(^|,)$name(,|$)"
    })
    Assert ($owners.Count -eq 1 -and $owners[0].NAME -ceq $want.owner) `
        "$name retained ownership drifted"
    $combat = @($combatRows | Where-Object actionName -ceq $name)
    Assert ($combat.Count -eq 1 -and
        $combat[0].animDefault -ceq "fire_5_single" -and
        $combat[0].anim_carbine -ceq "fire_5_single" -and
        $combat[0].attackType -ceq "SINGLE_TARGET" -and
        $combat[0].percentAddFromWeapon -ceq $want.damage -and
        $combat[0].weaponType -ceq "CARBINE" -and
        $combat[0].weaponCategory -ceq "RANGED_WEAPON") "$name combat row drifted"
    $override = @($overrides | Where-Object actionName -ceq $name)
    Assert ($override.Count -eq 1 -and
        $override[0].healthCostMultiplier -ceq $want.health -and
        $override[0].actionCostMultiplier -ceq $want.action -and
        $override[0].mindCostMultiplier -ceq $want.mind -and
        $override[0].targetPool -ceq "MULTI" -and
        $override[0].speedMultiplier -ceq "2" -and
        $override[0].accuracyBonus -ceq "25" -and
        $override[0].animationType -ceq "RANGED" -and
        $override[0].poolDamageRolls -ceq $want.rolls -and
        $override[0].poolDamageIncrement -ceq $want.increment) `
        "$name override drifted"
    $spam = @($spamRows | Where-Object actionName -ceq $name)
    Assert ($spam.Count -eq 1 -and $spam[0].combatSpam -ceq $want.spam) `
        "$name spam drifted"
}
$sources = ($paths.actions,$paths.engine,$paths.base,$paths.fixture |
    ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
foreach ($token in @(
    "public int scatterShot1(", "public int scatterShot2(",
    "precuPoolDamageRolls", "precuPoolDamageIncrement",
    "rand(0, 2)", "0.0834f * spillPoolCount",
    "poolDamage.totalApplied", "ORIGINAL_CARBINE_ACCURACY_THREE",
    "ORIGINAL_SCATTER_SHOT_ONE_COMMAND",
    "ORIGINAL_SCATTER_SHOT_TWO_COMMAND"
)) {
    Assert ($sources.Contains($token)) "M264 lifecycle drifted: $token"
}
$patch = Join-Path $restorationRoot "patches/dsrc/262-p14-core3-scatter-shots.patch"
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) `
    "Overlay hash drifted"
$hashes = $contract.buildEvidence.sourceSha256
if ($null -ne $hashes) {
    foreach ($item in $hashes.PSObject.Properties) {
        Assert ((Sha $paths[$item.Name]) -ceq [string]$item.Value) `
            "Source hash drifted: $($item.Name)"
    }
}
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.persistence.observed -and
        [bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) "M264 is not Ready"
}
Write-Host "Publish 14.1 Core3 scatter-shot contract passed."
