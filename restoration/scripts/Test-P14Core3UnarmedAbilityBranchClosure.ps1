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
    fixture = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_unarmed_ability_runtime.java"
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
    runtimeFixture = $paths.fixture
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
$fixture = Get-Content -LiteralPath $paths.fixture -Raw

foreach ($token in @(
    "PLAYER_OID = 44003778L",
    "PLAYER_STATION_ID = 91001",
    "PROTOCOL_VERSION = 3",
    "COMMAND_REPETITIONS = 2",
    "playerOid != PLAYER_OID",
    "player.getValue() == PLAYER_OID",
    "getPlayerStationId(player) == PLAYER_STATION_ID",
    'value.matches("[a-f0-9]{32}")',
    '"combat_brawler", "combat_brawler_novice"',
    '"combat_unarmed_ability_01", "combat_unarmed_ability_02"',
    '"combat_unarmed_ability_03", "combat_unarmed_ability_04"',
    '"111111111111".equals(buildSkillBits(player))',
    '"object/weapon/melee/unarmed/unarmed_default_player.iff"',
    "attachScript(player, COMBAT_ACTIONS_SCRIPT)",
    "attachScript(player, FIXTURE_SCRIPT)",
    "public int failSpecialAttack(",
    "getHeightAtLocation(1000.0f, 1000.0f)",
    "combat.cachedCanSee(player, target)",
    "pvpCanAttack(player, target)",
    "utils.removeScriptVar(target, factions.IGNORE_PLAYER)",
    "setInvulnerable(target, false)",
    "COMMAND_PRIORITY_DEFAULT",
    "ORIGINAL_SKILL_POINTS",
    "restorePlayer(player)",
    '"action=cleanup alreadyClean=true restored=true"',
    '"action=cleanup alreadyClean=false restored=true"')) {
    Assert ($fixture.Contains($token)) "Runtime fixture authority drifted: $token"
}
Assert (([regex]::Matches($fixture, [regex]::Escape("queueCommand("))).Count -eq 1) `
    "Runtime fixture must use one production queue call inside its bounded repetition loop"
foreach ($forbidden in @("apply_patch", "Artifacts", "Staging")) {
    Assert (-not $fixture.Contains($forbidden)) "Runtime fixture contains non-source workflow residue: $forbidden"
}

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
    $runtime = $contract.runtimeEvidence
    $fixtureEvidence = $runtime.fixture
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$runtime.result -ceq "passed" -and
        @($contract.requiredBeforeReady).Count -eq 0) "Unarmed ability branch lacks ready live evidence"
    Assert ([string]$contract.buildEvidence.directSourceCommit -ceq
            "a1bbeb92123e54fab5074f2d7384d2318c340abb" -and
        [string]$contract.buildEvidence.compiledClassSha256.'combat_actions.class' -ceq
            "a50d4207df6b1924f43c01802833133329bfa943e80f7ad4cea99bf43c50f5c2" -and
        [string]$contract.buildEvidence.compiledClassSha256.'combat_base.class' -ceq
            "9d26b6788a5c8794381c066ca49137c45bf62d1cb1ef6d36595e127570b56964" -and
        [string]$contract.buildEvidence.compiledClassSha256.'precu_unarmed_ability_runtime.class' -ceq
            "89a10f5588b38ad663b02cd49fac11808d1997acad0775f0738b787e3b409bd7" -and
        [string]$contract.buildEvidence.x64ServerBuild -match
            '833f654838826bb894778e644781c2af095d2b98d1cd4cac9c0250f206af4f44' -and
        [string]$contract.buildEvidence.x64ServerBuild -match
            '93fc0a7b6d6c5d8aebb7705e901510ac83959e1f') `
        "Unarmed ability build identity is not pinned"
    Assert ([bool]$runtime.containerHealthy -and
        [bool]$runtime.clusterReadyForPlayers -and
        [bool]$runtime.liveProcessMappedBuiltBinary -and
        [int]$runtime.processCounts.PlanetServer -eq 15 -and
        [int]$runtime.processCounts.SwgGameServer -eq 15 -and
        [int]$runtime.serverProcessId -eq 373 -and
        [long]$runtime.liveBinaryInode -eq 12141822 -and
        [long]$runtime.liveBinarySize -eq 22587656 -and
        [bool]$runtime.primaryClient.remainedOpenAndResponsive -and
        [int]$runtime.primaryClient.processId -eq 52252 -and
        [int]$runtime.primaryClient.stationId -eq 91001 -and
        [long]$runtime.primaryClient.playerOid -eq 44003778) `
        "Unarmed ability live environment identity is incomplete"
    Assert ([int]$fixtureEvidence.protocolVersion -eq 3 -and
        [string]$fixtureEvidence.lifecycle -match '^[a-f0-9]{32}$' -and
        [bool]$fixtureEvidence.authoritative -and
        [long]$fixtureEvidence.playerOid -eq 44003778 -and
        [int]$fixtureEvidence.stationId -eq 91001 -and
        [long]$fixtureEvidence.targetOid -gt 0 -and
        [string]$fixtureEvidence.targetCreature -ceq "worrt" -and
        [bool]$fixtureEvidence.targetDisposable -and
        [bool]$fixtureEvidence.targetVisible -and
        [bool]$fixtureEvidence.pvpAdmissionReassertedBeforeEveryArm -and
        [string]$fixtureEvidence.skillBits -ceq "111111111111" -and
        [string]$fixtureEvidence.commandBits -ceq "111" -and
        [int]$fixtureEvidence.preparedAvailableSkillPoints -eq 51 -and
        [int]$fixtureEvidence.originalAvailableSkillPoints -eq 100 -and
        [string]$fixtureEvidence.weaponTemplate -ceq
            "object/weapon/melee/unarmed/unarmed_default_player.iff" -and
        [int]$fixtureEvidence.weaponType -eq 6 -and
        [string]$fixtureEvidence.heldWeapon -ceq "none" -and
        [bool]$fixtureEvidence.combatActionsScriptRemainedProductionHandler -and
        [bool]$fixtureEvidence.fixtureObservedFailureHookOnly) `
        "Unarmed ability fixture boundary evidence is incomplete"

    $liveSpecs = @(
        [pscustomobject]@{ name="unarmedDizzy1"; costs="6,15,17"; animation="attack_special_wookiee_slap_medium"; gap=1.109 },
        [pscustomobject]@{ name="unarmedCombo1"; costs="6,15,17"; animation="combo_4b_medium"; gap=1.102 },
        [pscustomobject]@{ name="unarmedCombo2"; costs="8,20,23"; animation="combo_4a_medium"; gap=1.101 }
    )
    foreach ($spec in $liveSpecs) {
        $evidence = $runtime.commands.($spec.name)
        Assert ([string]$evidence.result -ceq "passed" -and
            [int]$evidence.queuedExecutions -eq 2 -and
            [string]$evidence.failureHook -ceq "none" -and
            [string]$evidence.traceStage -ceq "HIT_ENGINE" -and
            [string]$evidence.diagnosticAction -ceq $spec.name -and
            [string]$evidence.primaryResult -ceq "HIT" -and
            (@($evidence.expectedHamCosts) -join ',') -ceq $spec.costs -and
            (@($evidence.observedHamCosts) -join ',') -ceq $spec.costs -and
            [bool]$evidence.costsMatch -and
            [string]$evidence.animation -ceq $spec.animation -and
            [int]$evidence.animationType -eq 2 -and
            [string]$evidence.spamKey -ceq ("cmd_n:" + $spec.name) -and
            [string]$evidence.damagePipeline -ceq "PRECU_CORE3" -and
            @($evidence.cadence.executionTimes).Count -eq 2 -and
            [double]$evidence.cadence.observedGapSeconds -eq $spec.gap -and
            [double]$evidence.cadence.observedGapSeconds -ge 1.0 -and
            [double]$evidence.cadence.assignedIntervalSeconds -eq 1.0 -and
            [double]$evidence.cadence.weaponSpeed -eq 2.0 -and
            [int]$evidence.cadence.familySpeedModifier -eq 95 -and
            [int]$evidence.cadence.otherSpeedModifiers -eq 0) `
            "Unarmed ability live command evidence drifted: $($spec.name)"
    }
    $liveDizzy = $runtime.commands.unarmedDizzy1
    Assert ([int]$liveDizzy.targetPoolConfigured -eq 3 -and
        [int]$liveDizzy.targetPoolResolved -eq 1 -and
        [int]$liveDizzy.stateType -eq 1 -and
        [int]$liveDizzy.stateDurationBaseSeconds -eq 30 -and
        [int]$liveDizzy.stateResolvedDurationSeconds -eq 30 -and
        [string]$liveDizzy.stateResult -ceq "APPLIED" -and
        [bool]$liveDizzy.targetDizzyState -and
        [bool]$liveDizzy.targetDizzyBuff) "Unarmed Dizzy live state evidence drifted"
    foreach ($name in @("unarmedCombo1", "unarmedCombo2")) {
        $combo = $runtime.commands.$name
        $damage = @($combo.poolDamageApplied | ForEach-Object { [int]$_ })
        Assert ([int]$combo.targetPoolConfigured -eq 4 -and
            [int]$combo.targetPoolResolved -eq 4 -and
            @($combo.poolMultipliers).Count -eq 3 -and
            [math]::Abs([double]$combo.multiplierTotal - 1.0) -lt 0.0001 -and
            $damage.Count -eq 3 -and
            @($damage | Where-Object { $_ -gt 0 }).Count -eq 3) `
            "Unarmed combo live distribution evidence drifted: $name"
    }
    Assert ([math]::Abs([double]$runtime.commands.unarmedCombo1.poolMultipliers[1] - 0.1) -lt 0.0001) `
        "Unarmed Combo 1 action distribution drifted"
    $cleanup = $runtime.cleanup
    Assert (-not [bool]$cleanup.firstCleanupAlreadyClean -and
        [bool]$cleanup.firstCleanupRestored -and
        [bool]$cleanup.secondCleanupAlreadyClean -and
        [bool]$cleanup.secondCleanupRestored -and
        [int]$cleanup.availableSkillPointsRestored -eq 100 -and
        [bool]$cleanup.exactSkillAndCommandBitsRestored -and
        [bool]$cleanup.exactLocationPostureLocomotionHamWoundsRegenShockWeaponAndScriptsRestored -and
        [bool]$cleanup.disposableTargetDestroyed -and
        [string]$runtime.delayedErrorAudit.result -ceq "passed" -and
        [int]$runtime.delayedErrorAudit.fatalLines -eq 0 -and
        [int]$runtime.delayedErrorAudit.exceptionLines -eq 0 -and
        [int]$runtime.delayedErrorAudit.errorLines -eq 0 -and
        [int]$runtime.delayedErrorAudit.restorationFailureLines -eq 0) `
        "Unarmed ability cleanup or delayed error evidence drifted"
}

Write-Host "Publish 14.1 Core3 unarmed ability branch closure contract passed."
