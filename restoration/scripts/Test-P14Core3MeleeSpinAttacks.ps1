param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path

function Read-DataRows([string]$Path)
{
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0].Split("`t")
    return @($lines[2..($lines.Count - 1)] |
        ConvertFrom-Csv -Delimiter "`t" -Header $header)
}

$actions = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java") -Raw
$fixture = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java") -Raw
$commandRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab")
$combatRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab")
$overrideRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab")
$spamRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab")
$profileRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_profiles.tab")
$costRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_ham_costs.tab")
$skillRows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab")

$cases = @(
    [pscustomobject]@{ Name="melee1hSpinAttack1"; Owner="combat_brawler_1handmelee_04"; Weapon="1HAND_MELEE"; Template="object/weapon/melee/sword/sword_rantok.iff"; Animation="attack_high_right_medium_2"; Accuracy="25"; Health="1"; Action="1"; Mind="1.5"; Spam="slashspin"; Speed="3.3"; Wounds="20"; Armor="0"; BaseHealth="27"; BaseAction="40"; BaseMind="25" },
    [pscustomobject]@{ Name="melee2hSpinAttack1"; Owner="combat_brawler_2handmelee_04"; Weapon="2HAND_MELEE"; Template="object/weapon/melee/2h_sword/2h_sword_cleaver.iff"; Animation="attack_high_right_light_2"; Accuracy="10"; Health="1"; Action="1.5"; Mind="1"; Spam="spinstrike"; Speed="4.1"; Wounds="27"; Armor="2"; BaseHealth="38"; BaseAction="35"; BaseMind="20" }
)

foreach ($case in $cases)
{
    foreach ($token in @("public int $($case.Name)(", "combatStandardAction(`"$($case.Name)`""))
    {
        if (-not $actions.Contains($token)) { throw "$($case.Name) action hook drifted: $token" }
    }
    $command = @($commandRows | Where-Object commandName -ceq $case.Name)
    if ($command.Count -ne 1 -or $command[0].validWeapon -cne $case.Weapon -or $command[0].addToCombatQueue -cne "1") { throw "$($case.Name) command row drifted." }
    $combat = @($combatRows | Where-Object actionName -ceq $case.Name)
    if ($combat.Count -ne 1 -or $combat[0].attackType -cne "AREA" -or $combat[0].coneLength -cne "16" -or $combat[0].percentAddFromWeapon -cne "2.0" -or $combat[0].animDefault -cne $case.Animation -or $combat[0].weaponType -cne $case.Weapon) { throw "$($case.Name) combat row drifted." }
    $override = @($overrideRows | Where-Object actionName -ceq $case.Name)
    if ($override.Count -ne 1 -or $override[0].healthCostMultiplier -cne $case.Health -or $override[0].actionCostMultiplier -cne $case.Action -or $override[0].mindCostMultiplier -cne $case.Mind -or $override[0].targetPool -cne "RANDOM" -or $override[0].speedMultiplier -cne "1.5" -or $override[0].accuracyBonus -cne $case.Accuracy) { throw "$($case.Name) override row drifted." }
    $spam = @($spamRows | Where-Object actionName -ceq $case.Name)
    if ($spam.Count -ne 1 -or $spam[0].combatSpam -cne $case.Spam) { throw "$($case.Name) spam row drifted." }
    $profile = @($profileRows | Where-Object templateName -ceq $case.Template)
    if ($profile.Count -ne 1 -or $profile[0].attackSpeed -cne $case.Speed -or $profile[0].woundsRatio -cne $case.Wounds -or $profile[0].armorPiercing -cne $case.Armor) { throw "$($case.Name) weapon profile drifted." }
    $cost = @($costRows | Where-Object templateName -ceq $case.Template)
    if ($cost.Count -ne 1 -or $cost[0].healthCost -cne $case.BaseHealth -or $cost[0].actionCost -cne $case.BaseAction -or $cost[0].mindCost -cne $case.BaseMind) { throw "$($case.Name) base HAM costs drifted." }
    $skill = @($skillRows | Where-Object name -ceq $case.Owner)
    if ($skill.Count -ne 1 -or ([string]$skill[0].COMMANDS).Split(",") -cnotcontains $case.Name) { throw "$($case.Name) skill owner drifted." }
}

foreach ($token in @(
    'ONE_HAND_AREA_COMMAND = "melee1hSpinAttack1"',
    'TWO_HAND_AREA_COMMAND = "melee2hSpinAttack1"',
    'ONE_HAND_TEMPLATE =',
    'TWO_HAND_TEMPLATE =',
    "destroyFixtureOneHand(attacker)",
    "destroyFixtureTwoHand(attacker)",
    "ORIGINAL_ONE_HAND_CERTIFICATION",
    "ORIGINAL_TWO_HAND_CERTIFICATION"))
{
    if (-not $fixture.Contains($token)) { throw "Melee spin fixture safety drifted: $token" }
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-melee-spin-attacks.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.buildEvidence.datatableCompile -ne "passed" -or $contract.buildEvidence.staticContract -ne "passed" -or $contract.runtimeEvidence.result -ne "passed" -or $contract.runtimeEvidence.fixtureCleanup -ne "passed" -or -not $contract.runtimeEvidence.serverHealthy) { throw "Core3 melee spin evidence is not ready." }
}

Write-Host "Publish 14.1 Core3 melee spin attack contract passed."
