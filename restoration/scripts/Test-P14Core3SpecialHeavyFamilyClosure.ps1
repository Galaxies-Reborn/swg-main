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
$specs = @(
    @{ Name="fireAcidCone1"; Fixture="AcidConeOne"; Owner="combat_commando_support_02"; Damage="5"; Time="4"; Costs=@("1.5","0.5","0.5"); Anim="fire_acid_rifle_single_1"; Spam="fireacidcone1"; Weapon="HEAVY"; Attack="CONE"; Width="45"; Template="object/weapon/ranged/heavy/heavy_acid_beam.iff" },
    @{ Name="fireAcidCone2"; Fixture="AcidConeTwo"; Owner="combat_commando_master"; Damage="6"; Time="4"; Costs=@("2","0.5","0.5"); Anim="fire_acid_rifle_single_2"; Spam="fireacidcone2"; Weapon="HEAVY"; Attack="CONE"; Width="45"; Template="object/weapon/ranged/heavy/heavy_acid_beam.iff" },
    @{ Name="fireAcidSingle2"; Fixture="AcidSingleTwo"; Owner="combat_commando_support_04"; Damage="8"; Time="4"; Costs=@("2","0.5","0.5"); Anim="fire_acid_rifle_single_2"; Spam="fireacidsingle2"; Weapon="HEAVY"; Attack="SINGLE_TARGET"; Width=""; Template="object/weapon/ranged/heavy/heavy_acid_beam.iff" },
    @{ Name="fireLightningCone1"; Fixture="LightningConeOne"; Owner="combat_bountyhunter_support_02"; Damage="3"; Time="2"; Costs=@("1","1","1"); Anim="fire_area"; Spam="firelightningcone1"; Weapon="RIFLE"; Attack="CONE"; Width="60"; Template="object/weapon/ranged/rifle/rifle_lightning.iff" },
    @{ Name="fireLightningCone2"; Fixture="LightningConeTwo"; Owner="combat_bountyhunter_master"; Damage="4"; Time="2"; Costs=@("1","1","1"); Anim="fire_area"; Spam="firelightningcone2"; Weapon="RIFLE"; Attack="CONE"; Width="60"; Template="object/weapon/ranged/rifle/rifle_lightning.iff" },
    @{ Name="fireLightningSingle2"; Fixture="LightningSingleTwo"; Owner="combat_bountyhunter_support_04"; Damage="5"; Time="2"; Costs=@("1","1","1"); Anim="fire_lightning_rifle_single_2"; Spam="firelightningsingle2"; Weapon="RIFLE"; Attack="SINGLE_TARGET"; Width=""; Template="object/weapon/ranged/rifle/rifle_lightning.iff" }
)
foreach ($spec in $specs) {
    $name = $spec.Name
    if (-not $actions.Contains("public int $name(") -or
        -not $actions.Contains("combatStandardAction(`"$name`"") -or
        -not $actions.Contains($spec.Template)) { throw "Action hook drifted: $name" }
    $c = @($commands | Where-Object commandName -ceq $name)
    if ($c.Count -ne 1 -or $c[0].defaultTime -cne $spec.Time -or
        $c[0].executeTime -cne $spec.Time -or $c[0].validWeapon -cne $spec.Weapon -or
        $c[0].maxRangeToTarget -cne "16") { throw "Command row drifted: $name" }
    $d = @($combat | Where-Object actionName -ceq $name)
    if ($d.Count -ne 1 -or $d[0].percentAddFromWeapon -cne $spec.Damage -or
        $d[0].animDefault -cne $spec.Anim -or $d[0].attackType -cne $spec.Attack -or
        $d[0].maxRange -cne "16" -or $d[0].weaponType -cne $spec.Weapon -or
        $d[0].weaponCategory -cne "RANGED_WEAPON") { throw "Combat row drifted: $name" }
    $weaponAnim = if ($spec.Weapon -ceq "HEAVY") { $d[0].anim_heavyweapon } else { $d[0].anim_rifle }
    if ($weaponAnim -cne $spec.Anim) { throw "Weapon animation drifted: $name" }
    if ($spec.Attack -ceq "CONE" -and
        ($d[0].coneLength -cne "16" -or $d[0].coneWidth -cne $spec.Width)) {
        throw "Cone geometry drifted: $name"
    }
    $o = @($overrides | Where-Object actionName -ceq $name)
    if ($o.Count -ne 1 -or $o[0].healthCostMultiplier -cne $spec.Costs[0] -or
        $o[0].actionCostMultiplier -cne $spec.Costs[1] -or
        $o[0].mindCostMultiplier -cne $spec.Costs[2] -or
        $o[0].targetPool -cne "RANDOM" -or $o[0].speedMultiplier -cne $spec.Time -or
        $o[0].accuracyBonus -cne "0" -or $o[0].animationType -cne "INTENSITY") {
        throw "Override row drifted: $name"
    }
    $s = @($spam | Where-Object actionName -ceq $name)
    if ($s.Count -ne 1 -or $s[0].combatSpam -cne $spec.Spam) { throw "Spam row drifted: $name" }
    $k = @($skills | Where-Object name -ceq $spec.Owner)
    if ($k.Count -ne 1 -or ([string]$k[0].COMMANDS).Split(",") -cnotcontains $name) {
        throw "Skill owner drifted: $name"
    }
    if (-not $fixture.Contains("`"$name`"") -or
        -not $fixture.Contains("canPerform$($spec.Fixture)=")) {
        throw "Fixture drifted: $name"
    }
}
if ($Expectation -eq "Ready") {
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-special-heavy-family-closure.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        $contract.frontierEvidence.remainingCandidates -ne 0 -or
        @($contract.runtimeEvidence.commands).Count -ne 6 -or
        @($contract.runtimeEvidence.commands | Where-Object result -ne "passed").Count -ne 0 -or
        -not $contract.runtimeEvidence.serverHealthy) { throw "Runtime evidence is not ready." }
}
Write-Host "Publish 14.1 Core3 special-heavy family closure contract passed."
