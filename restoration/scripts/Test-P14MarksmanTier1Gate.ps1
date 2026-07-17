[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14MarksmanTier1Matrix)) -Raw | ConvertFrom-Json
$headShotContract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14HeadShot1)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized Marksman tier-I source is missing: $path"
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

function Get-ModeledCost
{
    param(
        [Parameter(Mandatory = $true)][int]$Governor,
        [Parameter(Mandatory = $true)][int]$BaseCost,
        [Parameter(Mandatory = $true)][double]$Multiplier
    )

    $cost = $BaseCost * $Multiplier
    $cost -= (($Governor - 300.0) / 1200.0) * $cost
    return [Math]::Max(0, [int][Math]::Truncate($cost))
}

function Get-CommaValues
{
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value))
    {
        return @()
    }

    return @(
        $Value.Trim('"').Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne "" }
    )
}

Write-Host "Publish 14.1 Marksman tier-I activation checks:"
Assert-Contract -Condition (
    [string]$contract.status -ceq "implemented-build-verified-live-partial") -Name "p14.marksman-tier1.status.live-execution-verified"
Assert-Contract -Condition ([bool]$contract.semanticReference.currentMatchesPinned) -Name "p14.marksman-tier1.core3.current-matches-pin"
Assert-Contract -Condition (-not [bool]$contract.excludedPriorReconstruction.balanceAuthority) -Name "p14.marksman-tier1.prior-balance-reconstruction-excluded"
Assert-Contract -Condition ([string]$headShotContract.status -ceq "ready") -Name "p14.marksman-tier1.prerequisite.headshot1-ready"
Assert-Contract -Condition (
    @($headShotContract.acceptanceBoundary.deferredToMarksmanTier1Matrix).Count -eq 2) -Name "p14.marksman-tier1.prerequisite.deferred-seams-owned"

$runtimeStatuses = @(
    [string]$contract.runtimeSeams.commandDuration.status
    [string]$contract.runtimeSeams.primaryAccuracy.status
    [string]$contract.runtimeSeams.secondaryDefense.status
    [string]$contract.runtimeSeams.ricochetDefense.status
    [string]$contract.runtimeSeams.attackerWeaponProfiles.status
)
Assert-Contract -Condition (
    @($runtimeStatuses | Where-Object { $_ -cne "implemented-build-verified-live-pending" }).Count -eq 0) -Name "p14.marksman-tier1.runtime-seams.build-verified"

$blockedTokens = @($contract.materializerPolicy.rejectPatchTextWhileBlocked | ForEach-Object { [string]$_ })
Assert-Contract -Condition (
    $blockedTokens.Count -eq 2 -and
    $blockedTokens -contains "bodyShot1" -and
    $blockedTokens -contains "legShot1") -Name "p14.marksman-tier1.materializer.fail-closed-policy-retained"
Assert-Contract -Condition (
    [string]$contract.clientAssetPublication.status -ceq "published" -and
    [string]$contract.clientAssetPublication.branch -ceq "x64-dx9" -and
    [string]$contract.clientAssetPublication.commit -ceq "f3a6fc3f5edd04dd116b498d11cc41ce9ce3accc") -Name "p14.marksman-tier1.client-assets.published"
Assert-Contract -Condition (
    [string]$contract.clientAssetPublication.artifacts.'datatables/combat/combat_data.iff' -ceq "b10370723f639746b385eb10c4f3c39c36440d640342c58da3cfa1fd9ca405cd" -and
    [string]$contract.clientAssetPublication.artifacts.'datatables/command/command_table.iff' -ceq "683e65f2d3c80c7feaa4a9609849d29ec2221832d81edcd8d93bea79b9895ff4" -and
    [string]$contract.clientAssetPublication.artifacts.'datatables/skill/skills.iff' -ceq "eb62b893658e550bd18b3f6c8173a6f76f04db982a6dfd0b04bd8f0a53cb10e6") -Name "p14.marksman-tier1.client-assets.exact-hashes"
Assert-Contract -Condition (
    [string]$contract.buildEvidence.javaResult -ceq "passed" -and
    [string]$contract.buildEvidence.tableResult -ceq "passed") -Name "p14.marksman-tier1.prototype-build.passed"
Assert-Contract -Condition (
    [string]$contract.liveFixture.status -ceq "live-verified" -and
    [int]$contract.liveEvidence.clientBridgeProtocol -eq 11 -and
    [string]$contract.liveEvidence.clientExeSha256 -ceq "9da0a60cc52d02d9eb2e2ea866c692c39e69b6dd42ad9467f60fd1594e022bf2" -and
    [string]$contract.liveEvidence.serverBinarySha256 -ceq "2c309c5ede3d4bc417fc6094110c4135dacc621272b31e3b2247a340c4d5f001" -and
    [string]$contract.liveEvidence.compiledFixtureSha256 -ceq "790d928bb76d166d5956f330207e95a5413f46eec942d3d17c1048830930abcc") -Name "p14.marksman-tier1.live.identity-and-artifacts"
Assert-Contract -Condition (
    [string]$contract.liveEvidence.positiveExecution.bodyShot1.queueResult -ceq "Success" -and
    [int]$contract.liveEvidence.positiveExecution.bodyShot1.attackerHealthCost -eq 2 -and
    [int]$contract.liveEvidence.positiveExecution.bodyShot1.attackerActionCost -eq 11 -and
    [int]$contract.liveEvidence.positiveExecution.bodyShot1.attackerMindCost -eq 5 -and
    [string]$contract.liveEvidence.positiveExecution.bodyShot1.defenderPool -ceq "HEALTH" -and
    [int]$contract.liveEvidence.positiveExecution.bodyShot1.defenderAfter -lt [int]$contract.liveEvidence.positiveExecution.bodyShot1.defenderBefore -and
    [string]$contract.liveEvidence.positiveExecution.legShot1.queueResult -ceq "Success" -and
    [int]$contract.liveEvidence.positiveExecution.legShot1.attackerHealthCost -eq 9 -and
    [int]$contract.liveEvidence.positiveExecution.legShot1.attackerActionCost -eq 18 -and
    [int]$contract.liveEvidence.positiveExecution.legShot1.attackerMindCost -eq 5 -and
    [string]$contract.liveEvidence.positiveExecution.legShot1.defenderPool -ceq "ACTION" -and
    [int]$contract.liveEvidence.positiveExecution.legShot1.defenderAfter -lt [int]$contract.liveEvidence.positiveExecution.legShot1.defenderBefore) -Name "p14.marksman-tier1.live.positive-execution"
Assert-Contract -Condition (
    @($contract.liveEvidence.wrongWeaponMatrix).Count -eq 6 -and
    [int]$contract.liveEvidence.wrongWeaponResult.serverCanPerformAction -eq 2 -and
    [string]$contract.liveEvidence.wrongWeaponResult.queueResult -ceq "Cancelled" -and
    -not [bool]$contract.liveEvidence.wrongWeaponResult.attackerHamChanged -and
    -not [bool]$contract.liveEvidence.wrongWeaponResult.defenderHamChanged) -Name "p14.marksman-tier1.live.wrong-weapon-matrix"
Assert-Contract -Condition (
    [int]$contract.liveEvidence.noPartialResult.bodyShot1.serverCanPerformAction -eq 3 -and
    [string]$contract.liveEvidence.noPartialResult.bodyShot1.queueResult -ceq "Cancelled" -and
    -not [bool]$contract.liveEvidence.noPartialResult.bodyShot1.attackerHamChanged -and
    -not [bool]$contract.liveEvidence.noPartialResult.bodyShot1.defenderHamChanged -and
    [int]$contract.liveEvidence.noPartialResult.legShot1.serverCanPerformAction -eq 3 -and
    [string]$contract.liveEvidence.noPartialResult.legShot1.queueResult -ceq "Cancelled" -and
    -not [bool]$contract.liveEvidence.noPartialResult.legShot1.attackerHamChanged -and
    -not [bool]$contract.liveEvidence.noPartialResult.legShot1.defenderHamChanged) -Name "p14.marksman-tier1.live.strict-no-partial"
Assert-Contract -Condition (
    [bool]$contract.liveEvidence.cleanup.tier1Restored -and
    [bool]$contract.liveEvidence.cleanup.headShotLayerRestored -and
    [bool]$contract.liveEvidence.cleanup.skillsRemoved -and
    [bool]$contract.liveEvidence.cleanup.fixtureWeaponsRemoved -and
    [bool]$contract.liveEvidence.cleanup.pvpRestored -and
    [bool]$contract.liveEvidence.cleanup.hamRestored -and
    @($contract.requiredBeforeReady).Count -eq 1) -Name "p14.marksman-tier1.live.cleanup-and-remaining-boundary"

$commandRows = @(Import-SwgTab -Path $paths.commandTable)
$combatRows = @(Import-SwgTab -Path $paths.combatData)
$skillRows = @(Import-SwgTab -Path $paths.skillTable)
$overrideRows = @(Import-SwgTab -Path $paths.combatOverrides)
$weaponCostRows = @(Import-SwgTab -Path $paths.weaponCosts)
$weaponProfileRows = @(Import-SwgTab -Path $paths.weaponProfiles)
$combatActions = Get-Content -LiteralPath $paths.combatActions -Raw

$weapons = @($contract.commands | ForEach-Object { [string]$_.weaponType })
$pools = @($contract.commands | ForEach-Object { [string]$_.targetPool })
Assert-Contract -Condition (
    ($weapons -join ',') -ceq "PISTOL,CARBINE" -and
    ($pools -join ',') -ceq "HEALTH,ACTION") -Name "p14.marksman-tier1.matrix.pistol-health-carbine-action"

$headShotCommandMatches = @($commandRows | Where-Object { [string]$_.commandName -ceq "headShot1" })
Assert-Contract -Condition (
    $headShotCommandMatches.Count -eq 1 -and
    [string]$headShotCommandMatches[0].validWeapon -ceq "RIFLE") -Name "p14.marksman-tier1.headShot1.command-weapon-gate"

foreach ($skillContract in @($contract.authenticTier1Skills))
{
    $skillName = [string]$skillContract.name
    $matches = @($skillRows | Where-Object { [string]$_.NAME -ceq $skillName })
    $commands = if ($matches.Count -eq 1) { @(Get-CommaValues -Value ([string]$matches[0].COMMANDS)) } else { @() }
    $skillMods = if ($matches.Count -eq 1) { @(Get-CommaValues -Value ([string]$matches[0].SKILL_MODS)) } else { @() }
    $expectedCommands = @($skillContract.commands | ForEach-Object { [string]$_ })
    $expectedMods = @($skillContract.skillMods | ForEach-Object { [string]$_ })

    Assert-Contract -Condition (
        $matches.Count -eq 1 -and
        [string]$matches[0].PARENT -ceq "combat_marksman" -and
        [string]$matches[0].GOD_ONLY -ceq "0" -and
        [string]$matches[0].IS_TITLE -ceq "0" -and
        [string]$matches[0].IS_PROFESSION -ceq "0" -and
        [string]$matches[0].IS_HIDDEN -ceq "0" -and
        [string]$matches[0].POINTS_REQUIRED -ceq "2" -and
        [string]$matches[0].SKILLS_REQUIRED_COUNT -ceq "0" -and
        [string]$matches[0].SKILLS_REQUIRED -ceq "combat_marksman_novice" -and
        [string]$matches[0].XP_TYPE -ceq [string]$skillContract.xpType -and
        [string]$matches[0].XP_COST -ceq "1000" -and
        [string]$matches[0].XP_CAP -ceq "10000" -and
        [string]$matches[0].APPRENTICESHIPS_REQUIRED -ceq "0" -and
        [string]$matches[0].SEARCHABLE -ceq "1" -and
        [string]$matches[0].ENDER -ceq "0") -Name "p14.marksman-tier1.$skillName.authentic-flags-and-costs"

    Assert-Contract -Condition (
        ($commands -join ',') -ceq ($expectedCommands -join ',') -and
        ($skillMods -join ',') -ceq ($expectedMods -join ',')) -Name "p14.marksman-tier1.$skillName.authentic-grants-and-mods"
}

foreach ($candidate in @($contract.commands))
{
    $name = [string]$candidate.name
    $skillName = [string]$candidate.skill
    $templateName = [string]$candidate.weaponTemplate
    $animationColumn = [string]$candidate.animationColumn
    $commandMatches = @($commandRows | Where-Object { [string]$_.commandName -ceq $name })
    $combatMatches = @($combatRows | Where-Object { [string]$_.actionName -ceq $name })
    $overrideMatches = @($overrideRows | Where-Object { [string]$_.actionName -ceq $name })
    $weaponCostMatches = @($weaponCostRows | Where-Object { [string]$_.templateName -ceq $templateName })
    $weaponProfileMatches = @($weaponProfileRows | Where-Object { [string]$_.templateName -ceq $templateName })
    $skillMatches = @($skillRows | Where-Object { [string]$_.NAME -ceq $skillName })

    Assert-Contract -Condition (
        $commandMatches.Count -eq 1 -and
        [string]$commandMatches[0].scriptHook -ceq $name -and
        [string]$commandMatches[0].failScriptHook -ceq "failSpecialAttack" -and
        [string]$commandMatches[0].characterAbility -ceq $name -and
        [string]$commandMatches[0].target -ceq "other" -and
        [string]$commandMatches[0].targetType -ceq "optional" -and
        [string]$commandMatches[0].addToCombatQueue -ceq "1" -and
        [string]$commandMatches[0].validWeapon -ceq [string]$candidate.weaponType -and
        [double]$commandMatches[0].executeTime -eq 1.5) -Name "p14.marksman-tier1.$name.command-queue-contract"

    $combatAnimation = if ($combatMatches.Count -eq 1) {
        [string]$combatMatches[0].psobject.Properties[$animationColumn].Value
    } else {
        ""
    }
    Assert-Contract -Condition (
        $combatMatches.Count -eq 1 -and
        [string]$combatMatches[0].actionNameCrc -ceq $name -and
        [string]$combatMatches[0].attackType -ceq "SINGLE_TARGET" -and
        [string]$combatMatches[0].weaponType -ceq [string]$candidate.weaponType -and
        [double]$combatMatches[0].percentAddFromWeapon -eq [double]$candidate.damageMultiplier -and
        [string]$combatMatches[0].animDefault -ceq [string]$candidate.animation -and
        $combatAnimation -ceq [string]$candidate.animation) -Name "p14.marksman-tier1.$name.combat-data"

    Assert-Contract -Condition (
        $overrideMatches.Count -eq 1 -and
        [double]$overrideMatches[0].healthCostMultiplier -eq [double]$candidate.healthCostMultiplier -and
        [double]$overrideMatches[0].actionCostMultiplier -eq [double]$candidate.actionCostMultiplier -and
        [double]$overrideMatches[0].mindCostMultiplier -eq [double]$candidate.mindCostMultiplier -and
        [string]$overrideMatches[0].targetPool -ceq [string]$candidate.targetPool -and
        [double]$overrideMatches[0].speedMultiplier -eq [double]$candidate.speedMultiplier -and
        [int]$overrideMatches[0].accuracyBonus -eq [int]$candidate.accuracyBonus) -Name "p14.marksman-tier1.$name.runtime-override"

    Assert-Contract -Condition (
        $weaponCostMatches.Count -eq 1 -and
        [int]$weaponCostMatches[0].healthCost -eq [int]$contract.fixture.baseHealthCost -and
        [int]$weaponCostMatches[0].actionCost -eq [int]$contract.fixture.baseActionCost -and
        [int]$weaponCostMatches[0].mindCost -eq [int]$contract.fixture.baseMindCost) -Name "p14.marksman-tier1.$name.cdef-ham-costs"

    Assert-Contract -Condition (
        $weaponProfileMatches.Count -eq 1 -and
        [double]$weaponProfileMatches[0].attackSpeed -eq [double]$candidate.attackSpeed -and
        [string]$weaponProfileMatches[0].speedSkill -ceq [string]$candidate.speedSkill -and
        [double]$weaponProfileMatches[0].pointBlankRange -eq [double]$candidate.pointBlankRange -and
        [double]$weaponProfileMatches[0].pointBlankAccuracy -eq [double]$candidate.pointBlankAccuracy -and
        [double]$weaponProfileMatches[0].idealRange -eq [double]$candidate.idealRange -and
        [double]$weaponProfileMatches[0].idealAccuracy -eq [double]$candidate.idealAccuracy -and
        [double]$weaponProfileMatches[0].maxRange -eq [double]$candidate.maxRange -and
        [double]$weaponProfileMatches[0].maxRangeAccuracy -eq [double]$candidate.maxRangeAccuracy -and
        [string]$weaponProfileMatches[0].accuracySkill -ceq [string]$candidate.accuracySkill -and
        [string]$weaponProfileMatches[0].categoryAccuracySkill -ceq [string]$candidate.categoryAccuracySkill -and
        [string]$weaponProfileMatches[0].defenseSkill -ceq [string]$candidate.defenseSkill -and
        [string]$weaponProfileMatches[0].weaponFamily -ceq [string]$candidate.weaponFamily -and
        [double]$weaponProfileMatches[0].postureMultiplier -eq [double]$candidate.postureMultiplier -and
        [string]$weaponProfileMatches[0].secondaryDefenseSkill -ceq [string]$candidate.secondaryDefenseSkill -and
        [string]$weaponProfileMatches[0].secondaryDefenseResult -ceq [string]$candidate.secondaryDefenseResult) -Name "p14.marksman-tier1.$name.cdef-weapon-profile"

    $skillCommands = if ($skillMatches.Count -eq 1) { @(Get-CommaValues -Value ([string]$skillMatches[0].COMMANDS)) } else { @() }
    Assert-Contract -Condition (
        $skillMatches.Count -eq 1 -and
        @($skillCommands | Where-Object { $_ -ceq $name }).Count -eq 1) -Name "p14.marksman-tier1.$name.skill-grant-active"

    Assert-Contract -Condition (
        $combatActions.Contains("public int $name(") -and
        $combatActions.Contains("combatStandardAction(`"$name`", self, target, params")) -Name "p14.marksman-tier1.$name.standard-combat-wrapper"

    $costs = @(
        Get-ModeledCost -Governor ([int]$contract.fixture.governingStrength) -BaseCost ([int]$contract.fixture.baseHealthCost) -Multiplier ([double]$candidate.healthCostMultiplier)
        Get-ModeledCost -Governor ([int]$contract.fixture.governingQuickness) -BaseCost ([int]$contract.fixture.baseActionCost) -Multiplier ([double]$candidate.actionCostMultiplier)
        Get-ModeledCost -Governor ([int]$contract.fixture.governingFocus) -BaseCost ([int]$contract.fixture.baseMindCost) -Multiplier ([double]$candidate.mindCostMultiplier)
    )
    $expected = @(
        [int]$candidate.expectedFixtureHealthCost,
        [int]$candidate.expectedFixtureActionCost,
        [int]$candidate.expectedFixtureMindCost
    )
    Assert-Contract -Condition (($costs -join ',') -ceq ($expected -join ',')) -Name "p14.marksman-tier1.$name.modeled-fixture-cost"
}

$liveFixture = Get-Content -LiteralPath $paths.liveFixture -Raw
Assert-Contract -Condition (
    $liveFixture.Contains("ATTACKER_OID = 44003778L") -and
    $liveFixture.Contains("ATTACKER_STATION_ID = 91001") -and
    $liveFixture.Contains("DEFENDER_OID = 39008597L") -and
    $liveFixture.Contains("DEFENDER_STATION_ID = 1001") -and
    $liveFixture.Contains("validateHeadShotLayer(attacker, defender, lifecycle)") -and
    $liveFixture.Contains("HEADSHOT_PREPARED") -and
    [bool]$contract.liveFixture.dependency.sameLifecycleRequired) -Name "p14.marksman-tier1.live-fixture.identity-and-layer-dependency"
Assert-Contract -Condition (
    $liveFixture.Contains("grantSkill(attacker, PISTOL_ONE)") -and
    $liveFixture.Contains("grantSkill(attacker, CARBINE_ONE)") -and
    $liveFixture.Contains("createObjectInInventoryAllowOverload(PISTOL_TEMPLATE, attacker)") -and
    $liveFixture.Contains("createObjectInInventoryAllowOverload(CARBINE_TEMPLATE, attacker)") -and
    $liveFixture.Contains("hasCommand(attacker, BODY_COMMAND)") -and
    $liveFixture.Contains("hasCommand(attacker, LEG_COMMAND)")) -Name "p14.marksman-tier1.live-fixture.skills-weapons-and-commands"
Assert-Contract -Condition (
    $liveFixture.Contains('equalsIgnoreCase("armSuccess")') -and
    $liveFixture.Contains('equalsIgnoreCase("armNoPartialBody")') -and
    $liveFixture.Contains('equalsIgnoreCase("armNoPartialLeg")') -and
    $liveFixture.Contains("health = 3;") -and
    $liveFixture.Contains("action = 11;") -and
    $liveFixture.Contains("mind = 6;") -and
    $liveFixture.Contains("health = 10;") -and
    $liveFixture.Contains("action = 18;") -and
    [int]$contract.liveFixture.noPartialBoundaries.bodyShot1.attackerAction -eq 11 -and
    [int]$contract.liveFixture.noPartialBoundaries.legShot1.attackerAction -eq 18) -Name "p14.marksman-tier1.live-fixture.success-and-no-partial-arms"
Assert-Contract -Condition (
    $liveFixture.Contains("ORIGINAL_PISTOL_ONE") -and
    $liveFixture.Contains("ORIGINAL_CARBINE_ONE") -and
    $liveFixture.Contains("destroyOwnedWeapon(attacker, PISTOL_WEAPON, PISTOL_TEMPLATE)") -and
    $liveFixture.Contains("destroyOwnedWeapon(attacker, CARBINE_WEAPON, CARBINE_TEMPLATE)") -and
    $liveFixture.Contains("revokeSkill(attacker, CARBINE_ONE)") -and
    $liveFixture.Contains("revokeSkill(attacker, PISTOL_ONE)") -and
    $liveFixture.Contains("removeObjVar(attacker, ROOT)") -and
    $liveFixture.Contains("removeObjVar(defender, ROOT)")) -Name "p14.marksman-tier1.live-fixture.reversible-owned-state"
Assert-Contract -Condition (
    $liveFixture.Contains('" canBodyShot1="') -and
    $liveFixture.Contains('" canLegShot1="') -and
    $liveFixture.Contains('" attackerHealth="') -and
    $liveFixture.Contains('" defenderAction="') -and
    $liveFixture.Contains('" distanceCentimeters="')) -Name "p14.marksman-tier1.live-fixture.observable-status"
Assert-Contract -Condition (
    -not $liveFixture.Contains("queueCommand(") -and
    -not $liveFixture.Contains("combatStandardAction(") -and
    -not $liveFixture.Contains("doDamage") -and
    -not $liveFixture.Contains("equip(") -and
    [bool]$contract.liveFixture.neverQueuesOrFabricatesCombat) -Name "p14.marksman-tier1.live-fixture.never-queues-equips-or-fabricates-combat"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Marksman tier-I activation failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Marksman tier-I build/static and live execution acceptance passed; diagnostic seam acceptance remains pending."
