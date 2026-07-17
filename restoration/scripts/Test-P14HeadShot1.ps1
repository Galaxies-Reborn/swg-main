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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14HeadShot1)) -Raw | ConvertFrom-Json
$gate = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.headShot1Gate)) -Raw | ConvertFrom-Json
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
        throw "Required materialized headShot1 source is missing: $path"
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

function Get-BracedBlock
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Signature
    )

    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0)
    {
        return ""
    }
    $openBrace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($openBrace -lt 0)
    {
        return ""
    }

    $depth = 0
    for ($index = $openBrace; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{')
        {
            $depth++
        }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    return ""
}

function Get-UniqueRow
{
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Column,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $matches = @($Rows | Where-Object { [string]$_.$Column -ceq $Value })
    Assert-Contract -Condition ($matches.Count -eq 1) -Name $Name
    if ($matches.Count -eq 1)
    {
        return $matches[0]
    }
    return $null
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

function Invoke-ModeledAtomicDrain
{
    param(
        [Parameter(Mandatory = $true)][int[]]$Pools,
        [Parameter(Mandatory = $true)][int[]]$Costs
    )

    $result = @($Pools)
    for ($index = 0; $index -lt 3; $index++)
    {
        if ($Costs[$index] -lt 0 -or ($Costs[$index] -gt 0 -and $result[$index] -le $Costs[$index]))
        {
            return [pscustomobject]@{ Success = $false; Pools = $result }
        }
    }
    for ($index = 0; $index -lt 3; $index++)
    {
        $result[$index] -= $Costs[$index]
    }
    return [pscustomobject]@{ Success = $true; Pools = $result }
}

Write-Host "Publish 14.1 headShot1 vertical-slice checks:"
Assert-Contract -Condition ([string]$contract.status -ceq "ready") -Name "p14.headshot1.contract.ready"
Assert-Contract -Condition ([string]$gate.status -ceq "ready") -Name "p14.headshot1.gate.ready"
Assert-Contract -Condition ([bool]$contract.semanticReference.currentMatchesPinned) -Name "p14.headshot1.core3.current-matches-pin"
Assert-Contract -Condition (
    @($contract.acceptanceBoundary.deferredToMarksmanTier1Matrix).Count -eq 2 -and
    @($contract.acceptanceBoundary.deferredToMarksmanTier1Matrix) -contains "weapon-derived queue duration from speedMultiplier" -and
    @($contract.acceptanceBoundary.deferredToMarksmanTier1Matrix) -contains "per-action accuracyBonus in an authenticated Pre-CU hit equation") -Name "p14.headshot1.acceptance.speed-and-accuracy-deferred"

$commandRows = @(Import-SwgTab -Path $paths.commandTable)
$combatRows = @(Import-SwgTab -Path $paths.combatData)
$skillRows = @(Import-SwgTab -Path $paths.skillTable)
$overrideRows = @(Import-SwgTab -Path $paths.combatOverrides)
$weaponRows = @(Import-SwgTab -Path $paths.weaponCosts)

$command = Get-UniqueRow -Rows $commandRows -Column "commandName" -Value "headShot1" -Name "p14.headshot1.command.unique"
if ($null -ne $command)
{
    Assert-Contract -Condition (
        [string]$command.commandCategory -ceq "combat" -and
        [string]$command.scriptHook -ceq "headShot1" -and
        [string]$command.failScriptHook -ceq "failSpecialAttack" -and
        [double]$command.defaultTime -eq 1.5 -and
        [string]$command.characterAbility -ceq "headShot1") -Name "p14.headshot1.command.authenticated-hook"
    Assert-Contract -Condition (
        [int]$command.addToCombatQueue -eq [int]$contract.command.addToCombatQueue -and
        [string]$command.target -ceq [string]$contract.command.target -and
        [string]$command.targetType -ceq [string]$contract.command.targetType -and
        [double]$command.executeTime -eq [double]$contract.command.executeTime -and
        [int]$command.disabled -eq 0 -and
        [int]$command.fromServerOnly -eq 0) -Name "p14.headshot1.command.queued-client-entry"
}

$combatData = Get-UniqueRow -Rows $combatRows -Column "actionName" -Value "headShot1" -Name "p14.headshot1.combat-data.unique"
if ($null -ne $combatData)
{
    Assert-Contract -Condition (
        [string]$combatData.commandType -ceq "RIGHT_CLICK_SPECIAL" -and
        [string]$combatData.validTarget -ceq "STANDARD" -and
        [string]$combatData.hitType -ceq "ATTACK" -and
        [string]$combatData.attackType -ceq [string]$contract.combat.attackType -and
        [string]$combatData.weaponType -ceq [string]$contract.combat.weaponType) -Name "p14.headshot1.combat.rifle-single-target"
    Assert-Contract -Condition (
        [double]$combatData.percentAddFromWeapon -eq [double]$contract.combat.damageMultiplier -and
        [string]$combatData.animDefault -ceq [string]$contract.combat.animation -and
        [string]$combatData.anim_rifle -ceq [string]$contract.combat.animation -and
        [int]$combatData.doClientAnim -eq 1 -and
        [int]$combatData.forcesCharacterIntoCombat -eq 1) -Name "p14.headshot1.combat.damage-animation-state"
}

$skill = Get-UniqueRow -Rows $skillRows -Column "NAME" -Value ([string]$contract.skillGrant.skill) -Name "p14.headshot1.skill.unique"
if ($null -ne $skill)
{
    $commands = @(([string]$skill.COMMANDS).Trim('"').Split(',') | Where-Object { $_ -ne "" })
    Assert-Contract -Condition (@($commands | Where-Object { $_ -ceq [string]$contract.skillGrant.command }).Count -eq 1) -Name "p14.headshot1.skill.rifle-one-grants-command"
}

$override = Get-UniqueRow -Rows $overrideRows -Column "actionName" -Value "headShot1" -Name "p14.headshot1.override.unique"
if ($null -ne $override)
{
    Assert-Contract -Condition (
        [double]$override.healthCostMultiplier -eq [double]$contract.combat.healthCostMultiplier -and
        [double]$override.actionCostMultiplier -eq [double]$contract.combat.actionCostMultiplier -and
        [double]$override.mindCostMultiplier -eq [double]$contract.combat.mindCostMultiplier -and
        [string]$override.targetPool -ceq [string]$contract.combat.targetPool) -Name "p14.headshot1.override.core3-costs-and-mind"
}

$weapon = Get-UniqueRow -Rows $weaponRows -Column "templateName" -Value ([string]$contract.cdefFixture.template) -Name "p14.headshot1.weapon.cdef-unique"
if ($null -ne $weapon)
{
    Assert-Contract -Condition (
        [int]$weapon.healthCost -eq [int]$contract.cdefFixture.baseHealthCost -and
        [int]$weapon.actionCost -eq [int]$contract.cdefFixture.baseActionCost -and
        [int]$weapon.mindCost -eq [int]$contract.cdefFixture.baseMindCost) -Name "p14.headshot1.weapon.cdef-base-costs"
}

$combatActions = Get-Content -LiteralPath $paths.combatActions -Raw
$handler = Get-BracedBlock -Text $combatActions -Signature "public int headShot1("
Assert-Contract -Condition (
    $handler.Contains('combatStandardAction("headShot1", self, target, params, "", "")') -and
    $handler.Contains("return SCRIPT_OVERRIDE;") -and
    $handler.Contains("return SCRIPT_CONTINUE;")) -Name "p14.headshot1.script.standard-combat-hook"

$combatLibrary = Get-Content -LiteralPath $paths.combatLibrary -Raw
$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
Assert-Contract -Condition (
    $combatLibrary.Contains("getAttrib(self, STRENGTH)") -and
    $combatLibrary.Contains("getAttrib(self, QUICKNESS)") -and
    $combatLibrary.Contains("getAttrib(self, FOCUS)") -and
    $combatBase.Contains("actionData.precuHamCostModel > 0")) -Name "p14.headshot1.runtime.authoritative-three-cost-governors"
Assert-Contract -Condition (
    $combatBase.Contains("if (actionData.precuTargetPool >= 0)") -and
    [regex]::IsMatch(
        $combatBase,
        'doDamageToPool\s*\(\s*attacker,\s*defender,\s*hitData,\s*actionData\.precuTargetPool\s*\)')) -Name "p14.headshot1.runtime.explicit-mind-routing"

$liveFixture = Get-Content -LiteralPath $paths.liveFixture -Raw
Assert-Contract -Condition (
    $liveFixture.Contains("ATTACKER_OID = 44003778L") -and
    $liveFixture.Contains("ATTACKER_STATION_ID = 91001") -and
    $liveFixture.Contains("DEFENDER_OID = 39008597L") -and
    $liveFixture.Contains("DEFENDER_STATION_ID = 1001") -and
    $liveFixture.Contains("pvpSetPermanentPersonalEnemyFlag(attacker, defender)") -and
    $liveFixture.Contains("setLocation(attacker, attackerDestination)") -and
    $liveFixture.Contains("setAttribAndVerify(attacker, HEALTH, getMaxAttrib(attacker, HEALTH))") -and
    [bool]$contract.liveFixture.costGovernorPreparation.usesAuthoritativeExistingValues -and
    $liveFixture.Contains('" attackerStrength=" + getAttrib(attacker, STRENGTH)') -and
    $liveFixture.Contains('" attackerQuickness=" + getAttrib(attacker, QUICKNESS)') -and
    $liveFixture.Contains('" attackerFocus=" + getAttrib(attacker, FOCUS)') -and
    -not $liveFixture.Contains("setAttribAndVerify(attacker, STRENGTH") -and
    -not $liveFixture.Contains("setAttribAndVerify(attacker, QUICKNESS") -and
    -not $liveFixture.Contains("setAttribAndVerify(attacker, FOCUS") -and
    $liveFixture.Contains("setRegenRate(attacker, HEALTH, 0.0f)") -and
    $liveFixture.Contains("setRegenRate(attacker, ACTION, 0.0f)") -and
    $liveFixture.Contains("setRegenRate(attacker, MIND, 0.0f)") -and
    $liveFixture.Contains("setLocomotion(attacker, LOCOMOTION_STANDING)") -and
    $liveFixture.Contains("setPostureClientImmediate(attacker, POSTURE_UPRIGHT)") -and
    $liveFixture.Contains("reassertPreparedState(attacker, defender)")) -Name "p14.headshot1.live-fixture.identity-and-combat-preparation"
Assert-Contract -Condition (
    $liveFixture.Contains('equalsIgnoreCase("inspect")') -and
    $liveFixture.Contains('return "action=inspect " + buildStatus') -and
    $liveFixture.Contains('" attackerMaxHealth=" + getMaxAttrib(attacker, HEALTH)') -and
    $liveFixture.Contains('" attackerMaxStrength=" + getMaxAttrib(attacker, STRENGTH)') -and
    $liveFixture.Contains('" defenderMaxMind=" + getMaxAttrib(defender, MIND)')) -Name "p14.headshot1.live-fixture.read-only-inspection"
Assert-Contract -Condition (
    $liveFixture.Contains('equalsIgnoreCase("recover")') -and
    $liveFixture.Contains("recoverPartial(attacker, defender, args[3])") -and
    $liveFixture.Contains("snapshotOwnershipFailed") -and
    $liveFixture.Contains("hasCompleteSnapshot(attacker)") -and
    $liveFixture.Contains("hasCompleteSnapshot(defender)") -and
    $liveFixture.Contains("attackerHadRoot=") -and
    $liveFixture.Contains("defenderHadRoot=")) -Name "p14.headshot1.live-fixture.partial-recovery"
Assert-Contract -Condition (
    $liveFixture.Contains("restorePlayer(attacker)") -and
    $liveFixture.Contains("restorePlayer(defender)") -and
    $liveFixture.Contains("ORIGINAL_STRENGTH") -and
    $liveFixture.Contains("ORIGINAL_QUICKNESS") -and
    $liveFixture.Contains("ORIGINAL_FOCUS") -and
    $liveFixture.Contains("ORIGINAL_HEALTH_REGEN") -and
    $liveFixture.Contains("ORIGINAL_ACTION_REGEN") -and
    $liveFixture.Contains("ORIGINAL_MIND_REGEN") -and
    $liveFixture.Contains("ORIGINAL_POSTURE") -and
    $liveFixture.Contains("ORIGINAL_LOCOMOTION") -and
    $liveFixture.Contains("stopCombat(attacker)") -and
    $liveFixture.Contains("stopCombat(defender)") -and
    $liveFixture.Contains("combat.clearCombatDebuffs(attacker)") -and
    $liveFixture.Contains("combat.clearCombatDebuffs(defender)") -and
    $liveFixture.Contains("revokeSkill(attacker, RIFLE_ONE)") -and
    $liveFixture.Contains("pvpRemovePersonalEnemyFlags(attacker, defender)") -and
    $liveFixture.Contains("removeObjVar(attacker, ROOT)") -and
    $liveFixture.Contains("removeObjVar(defender, ROOT)")) -Name "p14.headshot1.live-fixture.reversible-owned-state"
Assert-Contract -Condition (
    $liveFixture.Contains('equalsIgnoreCase("armNoPartial")') -and
    $liveFixture.Contains("setAttribAndVerify(attacker, HEALTH, 3)") -and
    $liveFixture.Contains("setAttribAndVerify(attacker, ACTION, 7)") -and
    $liveFixture.Contains("setAttribAndVerify(attacker, MIND, 12)") -and
    [int]$contract.liveFixture.noPartialBoundary.attackerHealth -eq 3 -and
    [int]$contract.liveFixture.noPartialBoundary.attackerAction -eq 7 -and
    [int]$contract.liveFixture.noPartialBoundary.attackerMind -eq 12) -Name "p14.headshot1.live-fixture.no-partial-boundary"
Assert-Contract -Condition (
    -not $liveFixture.Contains("queueCommand(") -and
    -not $liveFixture.Contains("combatStandardAction(") -and
    -not $liveFixture.Contains("doDamage")) -Name "p14.headshot1.live-fixture.never-queues-or-fabricates-combat"

$neutralCosts = @(
    Get-ModeledCost -Governor ([int]$contract.cdefFixture.neutralGovernor) -BaseCost ([int]$contract.cdefFixture.baseHealthCost) -Multiplier ([double]$contract.combat.healthCostMultiplier)
    Get-ModeledCost -Governor ([int]$contract.cdefFixture.neutralGovernor) -BaseCost ([int]$contract.cdefFixture.baseActionCost) -Multiplier ([double]$contract.combat.actionCostMultiplier)
    Get-ModeledCost -Governor ([int]$contract.cdefFixture.neutralGovernor) -BaseCost ([int]$contract.cdefFixture.baseMindCost) -Multiplier ([double]$contract.combat.mindCostMultiplier)
)
$expectedCosts = @([int]$contract.cdefFixture.expectedHealthCost, [int]$contract.cdefFixture.expectedActionCost, [int]$contract.cdefFixture.expectedMindCost)
Assert-Contract -Condition (($neutralCosts -join ',') -ceq ($expectedCosts -join ',')) -Name "p14.headshot1.cost.neutral-cdef-is-5-7-10"

$successDrain = Invoke-ModeledAtomicDrain -Pools @(6, 8, 11) -Costs $neutralCosts
$failedDrain = Invoke-ModeledAtomicDrain -Pools @(6, 7, 11) -Costs $neutralCosts
Assert-Contract -Condition ($successDrain.Success -and (($successDrain.Pools -join ',') -ceq "1,1,1")) -Name "p14.headshot1.cost.strict-positive-success"
Assert-Contract -Condition ((-not $failedDrain.Success) -and (($failedDrain.Pools -join ',') -ceq "6,7,11")) -Name "p14.headshot1.cost.atomic-failure-no-partial-drain"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 headShot1 vertical-slice contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 headShot1 vertical-slice contract passed."
