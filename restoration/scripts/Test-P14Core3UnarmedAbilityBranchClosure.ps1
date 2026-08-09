param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-unarmed-ability-branch-closure.json") -Raw | ConvertFrom-Json

function Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 |
        ConvertFrom-Csv -Delimiter "`t" -Header $header)
}

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function BracedBlock([string]$Text, [string]$Signature) {
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    return ""
}

$paths = @{
    actions = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
    commands = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    combat = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
    overrides = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
    spam = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
    skills = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing direct source: $path"
}
$hashPaths = [ordered]@{
    combatActions = $paths.actions
    commandTable = $paths.commands
    combatData = $paths.combat
    combatOverrides = $paths.overrides
    combatSpam = $paths.spam
}
foreach ($entry in $hashPaths.GetEnumerator()) {
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
    Assert ($actualHash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) "Direct-source hash drifted: $($entry.Key)"
}
$directCommit = (& git -C (Join-Path $root "dsrc") rev-parse HEAD).Trim()
Assert ($LASTEXITCODE -eq 0 -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit) "Direct-source commit pin drifted"

$commands = Rows $paths.commands
$combat = Rows $paths.combat
$overrides = Rows $paths.overrides
$spam = Rows $paths.spam
$skills = Rows $paths.skills
$actions = Get-Content -LiteralPath $paths.actions -Raw

$specs = @(
    [pscustomobject]@{
        name = "unarmedDizzy1"; owner = "combat_unarmed_ability_01"
        time = "2"; damage = "1.5"; animation = "attack_special_wookiee_slap"
        costs = @("1.5", "1.5", "1.5"); pool = "RANDOM"; spam = "gundarkslap"
    },
    [pscustomobject]@{
        name = "unarmedCombo1"; owner = "combat_unarmed_ability_02"
        time = "2"; damage = "2"; animation = "combo_4b"
        costs = @("1.5", "1.5", "1.5"); pool = "MULTI"; spam = "shenbitbonecrusher"
    },
    [pscustomobject]@{
        name = "unarmedCombo2"; owner = "combat_unarmed_ability_04"
        time = "4"; damage = "3"; animation = "combo_4a"
        costs = @("2", "2", "2"); pool = "MULTI"; spam = "deathweave"
    }
)

foreach ($spec in $specs) {
    $command = @($commands | Where-Object commandName -CEQ $spec.name)
    Assert ($command.Count -eq 1) "$($spec.name) command row missing or duplicated"
    $command = $command[0]
    Assert ($command.commandCategory -ceq "combat" -and
        $command.scriptHook -ceq $spec.name -and
        $command.characterAbility -ceq $spec.name -and
        $command.defaultTime -ceq $spec.time -and
        $command.executeTime -ceq $spec.time -and
        $command.validWeapon -ceq "UNARMED" -and
        $command.maxRangeToTarget -ceq "5" -and
        $command.addToCombatQueue -ceq "1") "$($spec.name) command routing drifted"

    $action = @($combat | Where-Object actionName -CEQ $spec.name)
    Assert ($action.Count -eq 1) "$($spec.name) combat row missing or duplicated"
    $action = $action[0]
    Assert ($action.percentAddFromWeapon -ceq $spec.damage -and
        $action.animDefault -ceq $spec.animation -and
        $action.anim_unarmed -ceq $spec.animation -and
        $action.attackType -ceq "SINGLE_TARGET" -and
        $action.maxRange -ceq "5" -and
        $action.weaponType -ceq "UNARMED" -and
        $action.weaponCategory -ceq "MELEE_WEAPON" -and
        $action.specialLine -ceq "teras_kasi") "$($spec.name) combat data drifted"

    $override = @($overrides | Where-Object actionName -CEQ $spec.name)
    Assert ($override.Count -eq 1) "$($spec.name) PRE-CU override missing or duplicated"
    $override = $override[0]
    Assert ($override.healthCostMultiplier -ceq $spec.costs[0] -and
        $override.actionCostMultiplier -ceq $spec.costs[1] -and
        $override.mindCostMultiplier -ceq $spec.costs[2] -and
        $override.targetPool -ceq $spec.pool -and
        $override.speedMultiplier -ceq $spec.time -and
        $override.accuracyBonus -ceq "15" -and
        $override.animationType -ceq "INTENSITY") "$($spec.name) PRE-CU override drifted"

    $spamRow = @($spam | Where-Object actionName -CEQ $spec.name)
    Assert ($spamRow.Count -eq 1 -and
        $spamRow[0].combatSpam -ceq $spec.spam) "$($spec.name) spam metadata drifted"

    $owner = @($skills | Where-Object NAME -CEQ $spec.owner)
    Assert ($owner.Count -eq 1 -and
        ([string]$owner[0].COMMANDS -match
            ("(^|,)" + [regex]::Escape($spec.name) + "(,|$)"))) "$($spec.name) skill ownership drifted"
}

$dizzy = BracedBlock $actions "public int unarmedDizzy1("
Assert ($dizzy.Contains('combatStandardAction("unarmedDizzy1"')) "unarmedDizzy1 handler drifted"
$dizzyOverride = @($overrides | Where-Object actionName -CEQ "unarmedDizzy1")[0]
Assert ($dizzyOverride.stateEffect1 -ceq "DIZZY" -and
    $dizzyOverride.stateChance1 -ceq "100" -and
    $dizzyOverride.stateStrength1 -ceq "0" -and
    $dizzyOverride.stateDuration1 -ceq "30" -and
    $dizzyOverride.stateDefense1 -ceq "dizzy_defense" -and
    $dizzyOverride.stateJediDefense1 -ceq "jedi_state_defense" -and
    $dizzyOverride.stateResistance1 -ceq "resistance_states") "unarmedDizzy1 state effect drifted"

$comboOne = BracedBlock $actions "public int unarmedCombo1("
Assert ($comboOne.Contains("int healthRoll = rand(0, 50);") -and
    $comboOne.Contains("(90.0f - (float)healthRoll) / 100.0f") -and
    $comboOne.Contains("float actionMultiplier = 0.1f;") -and
    $comboOne.Contains("1.0f - healthMultiplier - actionMultiplier")) "unarmedCombo1 server roll drifted"

$comboTwo = BracedBlock $actions "public int unarmedCombo2("
Assert (([regex]::Matches($comboTwo, [regex]::Escape("rand(10, 80)"))).Count -eq 3 -and
    $comboTwo.Contains("healthWeight + actionWeight + mindWeight") -and
    $comboTwo.Contains("healthWeight / totalWeight") -and
    $comboTwo.Contains("actionWeight / totalWeight") -and
    $comboTwo.Contains("mindWeight / totalWeight")) "unarmedCombo2 normalized server rolls drifted"

$comboHelper = BracedBlock $actions "private boolean performPrecuUnarmedCombo("
foreach ($token in @(
    "combat_engine.getCombatData(actionName)",
    "actionData.precuTargetPool = PRECU_TARGET_POOL_MULTI",
    "actionData.precuHealthDamageMultiplier = healthMultiplier",
    "actionData.precuActionDamageMultiplier = actionMultiplier",
    "Math.max(0.000001f, mindMultiplier)",
    'getCurrentWeapon(self), ""')) {
    Assert ($comboHelper.Contains($token)) "Unarmed combo authority drifted: $token"
}
Assert (-not $comboHelper.Contains("String params")) "Unarmed combo damage distribution became client-parameterized"

if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "Unarmed ability branch lacks ready live evidence"
}

Write-Host "Publish 14.1 Core3 unarmed ability branch closure contract passed."
