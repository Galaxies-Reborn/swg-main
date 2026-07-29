param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3FlameDotFamily)) -Raw | ConvertFrom-Json
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
$hamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_ham_costs.tab"
$paths = @($actionsPath,$fixturePath,$commandPath,$combatPath,$overridePath,$spamPath,$hamPath)
foreach ($path in $paths) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M253 source: $path" }
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$combat = Read-Rows $combatPath
$overrides = Read-Rows $overridePath
$spam = Read-Rows $spamPath
$ham = Read-Rows $hamPath
$specs = @(
    @{Name="flameSingle1"; Owner="combat_commando_support_01"; Damage="5"; Costs=@("1.5","0.5","0.5"); Anim="fire_flame_thrower_single_1"; Spam="flamesingle1"; Attack="SINGLE_TARGET"; Width=""},
    @{Name="flameSingle2"; Owner="combat_commando_support_04"; Damage="8"; Costs=@("2","0.5","0.5"); Anim="fire_flame_thrower_single_2"; Spam="flamesingle2"; Attack="SINGLE_TARGET"; Width=""},
    @{Name="flameCone1"; Owner="combat_commando_support_02"; Damage="5"; Costs=@("1.5","0.5","0.5"); Anim="fire_flame_thrower_cone_1"; Spam="flamecone1"; Attack="CONE"; Width="45"},
    @{Name="flameCone2"; Owner="combat_commando_master"; Damage="6"; Costs=@("2","0.5","0.5"); Anim="fire_flame_thrower_cone_2"; Spam="flamecone2"; Attack="CONE"; Width="45"}
)
foreach ($spec in $specs) {
    $name = $spec.Name
    Assert ($actions.Contains("public int $name(") -and
        $actions.Contains("combatStandardAction(`"$name`"") -and
        $actions.Contains('"object/weapon/ranged/rifle/rifle_flame_thrower.iff"')) "Action wrapper drifted: $name"
    $c = @($commands | Where-Object commandName -ceq $name)
    Assert ($c.Count -eq 1 -and $c[0].defaultTime -ceq "4" -and
        $c[0].executeTime -ceq "4" -and $c[0].validWeapon -ceq "HEAVY" -and
        $c[0].maxRangeToTarget -ceq "16" -and $c[0].addToCombatQueue -ceq "1") "Command row drifted: $name"
    $d = @($combat | Where-Object actionName -ceq $name)
    Assert ($d.Count -eq 1 -and $d[0].percentAddFromWeapon -ceq $spec.Damage -and
        $d[0].animDefault -ceq $spec.Anim -and $d[0].anim_heavyweapon -ceq $spec.Anim -and
        $d[0].attackType -ceq $spec.Attack -and $d[0].maxRange -ceq "16" -and
        $d[0].weaponType -ceq "HEAVY" -and $d[0].dotType -ceq "fire" -and
        $d[0].dotIntensity -ceq "100" -and $d[0].dotDuration -ceq "60") "Combat/DOT row drifted: $name"
    if ($spec.Attack -ceq "CONE") {
        Assert ($d[0].coneLength -ceq "16" -and $d[0].coneWidth -ceq $spec.Width) "Cone geometry drifted: $name"
    }
    $o = @($overrides | Where-Object actionName -ceq $name)
    Assert ($o.Count -eq 1 -and $o[0].healthCostMultiplier -ceq $spec.Costs[0] -and
        $o[0].actionCostMultiplier -ceq $spec.Costs[1] -and
        $o[0].mindCostMultiplier -ceq $spec.Costs[2] -and
        $o[0].targetPool -ceq "RANDOM" -and $o[0].speedMultiplier -ceq "4" -and
        $o[0].animationType -ceq "INTENSITY") "Override drifted: $name"
    $s = @($spam | Where-Object actionName -ceq $name)
    Assert ($s.Count -eq 1 -and $s[0].combatSpam -ceq $spec.Spam) "Spam row drifted: $name"
}
$w = @($ham | Where-Object templateName -ceq "object/weapon/ranged/rifle/rifle_flame_thrower.iff")
Assert ($w.Count -eq 1 -and $w[0].healthCost -ceq "80" -and
    $w[0].actionCost -ceq "25" -and $w[0].mindCost -ceq "25") "Flame weapon HAM row drifted"
foreach ($token in @("FIXTURE_FLAME","equipFixtureFlame","flamePrecuHamCostModel=",
    "flameHealthCost=","fireDotStrength=","fireDotDuration=","prepareFixtureHam",
    "ORIGINAL_MAX_HEALTH","setMaxAttrib(player, HEALTH")) {
    Assert ($fixture.Contains($token)) "Fixture drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
$hashChecks = @{
    "combat_actions.java"=$actionsPath; "precu_headshot1_fixture.java"=$fixturePath;
    "command_table.tab"=$commandPath; "combat_data.tab"=$combatPath;
    "precu_combat_overrides.tab"=$overridePath; "precu_combat_spam.tab"=$spamPath;
    "precu_weapon_ham_costs.tab"=$hamPath
}
foreach ($item in $hashChecks.GetEnumerator()) {
    Assert ((Sha $item.Value) -ceq [string]$hashes.($item.Key)) "Source hash drifted: $($item.Key)"
}
$patch = Join-Path $restorationRoot "patches/dsrc/251-p14-core3-flame-dot-family.patch"
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M253 is not Ready"
    Assert (@($contract.runtimeEvidence.commands).Count -eq 4 -and
        @($contract.runtimeEvidence.commands | Where-Object {
            $_.queueRemoval -ceq "Success" -and $_.fireDotStrength -eq 100 -and
            $_.animationType -eq 2 -and $_.configuredTargetPool -eq 3
        }).Count -eq 4) "Four-command authenticated flame/DOT evidence drifted"
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) "Runtime cleanup boundary drifted"
}
Write-Host "Publish 14.1 Core3 flame/DOT family contract passed."
