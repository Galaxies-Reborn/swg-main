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

$combatActionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$profilePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_profiles.tab"
$hamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_weapon_ham_costs.tab"
$skillsPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"

$actions = Get-Content -LiteralPath $combatActionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
foreach ($name in @("polearmLegHit1", "unarmedHeadHit1"))
{
    foreach ($token in @(
        "public int $name(",
        ('combatStandardAction("{0}"' -f $name)
    ))
    {
        if (-not $actions.Contains($token)) { throw "Missing generated hook token: $token" }
    }
}

$commandRows = Read-DataRows $commandPath
$combatRows = Read-DataRows $combatPath
$overrideRows = Read-DataRows $overridePath
$spamRows = Read-DataRows $spamPath
$profileRows = Read-DataRows $profilePath
$hamRows = Read-DataRows $hamPath
$skillRows = Read-DataRows $skillsPath

$expected = @(
    [pscustomobject]@{
        Name = "polearmLegHit1"; Weapon = "POLEARM"; Damage = "1.5";
        Animation = "attack_low_left_medium_0"; Health = "1"; Action = "0.5";
        Mind = "0.5"; Pool = "ACTION"; Speed = "1.25"; Accuracy = "10";
        Spam = "legbruiser"; Skill = "combat_brawler_polearm_02"
    },
    [pscustomobject]@{
        Name = "unarmedHeadHit1"; Weapon = "UNARMED"; Damage = "2.5";
        Animation = "knockdown_unarmed_1"; Health = "1.75"; Action = "1.75";
        Mind = "1.75"; Pool = "MIND"; Speed = "2"; Accuracy = "15";
        Spam = "nexugrin"; Skill = "combat_unarmed_support_04"
    }
)

foreach ($item in $expected)
{
    $command = @($commandRows | Where-Object commandName -ceq $item.Name)
    if ($command.Count -ne 1 -or $command[0].scriptHook -cne $item.Name -or
        $command[0].characterAbility -cne $item.Name -or
        $command[0].validWeapon -cne $item.Weapon -or
        $command[0].maxRangeToTarget -cne "5" -or
        $command[0].addToCombatQueue -cne "1")
    {
        throw "Command-table row drifted: $($item.Name)"
    }

    $combat = @($combatRows | Where-Object actionName -ceq $item.Name)
    if ($combat.Count -ne 1 -or
        $combat[0].percentAddFromWeapon -cne $item.Damage -or
        $combat[0].animDefault -cne $item.Animation -or
        $combat[0].weaponType -cne $item.Weapon -or
        $combat[0].weaponCategory -cne "MELEE_WEAPON" -or
        $combat[0].maxRange -cne "5")
    {
        throw "Combat-data row drifted: $($item.Name)"
    }

    $override = @($overrideRows | Where-Object actionName -ceq $item.Name)
    if ($override.Count -ne 1 -or
        $override[0].healthCostMultiplier -cne $item.Health -or
        $override[0].actionCostMultiplier -cne $item.Action -or
        $override[0].mindCostMultiplier -cne $item.Mind -or
        $override[0].targetPool -cne $item.Pool -or
        $override[0].speedMultiplier -cne $item.Speed -or
        $override[0].accuracyBonus -cne $item.Accuracy)
    {
        throw "Core3 override row drifted: $($item.Name)"
    }

    $spam = @($spamRows | Where-Object actionName -ceq $item.Name)
    if ($spam.Count -ne 1 -or $spam[0].combatSpam -cne $item.Spam)
    {
        throw "Combat-spam row drifted: $($item.Name)"
    }

    $skill = @($skillRows | Where-Object name -ceq $item.Skill)
    if ($skill.Count -ne 1 -or
        ([string]$skill[0].COMMANDS).Split(",") -cnotcontains $item.Name)
    {
        throw "Authentic skill owner is missing command $($item.Name)."
    }
}

$polearmTemplate = "object/weapon/melee/polearm/lance_staff_wood_s2.iff"
$polearmProfile = @($profileRows | Where-Object templateName -ceq $polearmTemplate)
if ($polearmProfile.Count -ne 1 -or
    $polearmProfile[0].attackSpeed -cne "4.75" -or
    $polearmProfile[0].accuracySkill -cne "polearm_accuracy" -or
    $polearmProfile[0].secondaryDefenseResult -cne "BLOCK")
{
    throw "Core3 polearm representative profile drifted."
}

$expectedHam = @{
    "object/weapon/melee/polearm/lance_staff_wood_s2.iff" = "20,38,15"
    "object/weapon/melee/unarmed/unarmed_default_player.iff" = "10,10,10"
}
foreach ($template in $expectedHam.Keys)
{
    $row = @($hamRows | Where-Object templateName -ceq $template)
    $actual = if ($row.Count -eq 1) {
        "$($row[0].healthCost),$($row[0].actionCost),$($row[0].mindCost)"
    } else { "" }
    if ($actual -cne $expectedHam[$template]) { throw "Core3 HAM row drifted: $template" }
}

foreach ($token in @(
    'POLEARM_COMMAND = "polearmLegHit1"',
    'UNARMED_COMMAND = "unarmedHeadHit1"',
    'POLEARM_CERTIFICATION = "cert_lance_staff_wood_s2"',
    'POLEARM_TEMPLATE =',
    '"object/weapon/melee/polearm/lance_staff_wood_s2.iff"',
    'armGenerated',
    'destroyFixturePolearm',
    'ORIGINAL_POLEARM_COMMAND',
    'ORIGINAL_UNARMED_COMMAND',
    'ORIGINAL_POLEARM_CERTIFICATION'))
{
    if (-not $fixture.Contains($token)) { throw "Generated-command fixture is missing: $token" }
}

if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-core3-generated-combat-hooks.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.buildEvidence.javaCompile -ne "passed" -or
        $contract.buildEvidence.datatableCompile -ne "passed" -or
        $contract.buildEvidence.staticContract -ne "passed" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        $contract.runtimeEvidence.fixtureCleanup -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Generated Core3 combat-hook evidence is not ready."
    }
}

Write-Host "Publish 14.1 generated Core3 combat-hook contract passed."
