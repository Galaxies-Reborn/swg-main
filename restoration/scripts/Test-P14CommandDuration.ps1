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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14CommandDuration)) -Raw | ConvertFrom-Json
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
        throw "Required materialized command-duration source is missing: $path"
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

function Get-ModeledDuration
{
    param(
        [Parameter(Mandatory = $true)][double]$WeaponAttackSpeed,
        [Parameter(Mandatory = $true)][double]$SpeedMultiplier,
        [Parameter(Mandatory = $true)][int]$SpeedModifier,
        [Parameter(Mandatory = $true)][int]$Haste
    )

    $duration = (1.0 - $SpeedModifier / 100.0) * $SpeedMultiplier * $WeaponAttackSpeed
    if ($Haste -gt 0)
    {
        $duration -= $duration * ($Haste / 100.0)
    }
    return [Math]::Max($duration, 1.0)
}

Write-Host "Publish 14.1 weapon-derived command-duration checks:"
Assert-Contract -Condition (
    [string]$contract.status -ceq "ready") -Name "p14.duration.status.ready"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq "6856f315a80b5250635b2272695caec1d64204ed") -Name "p14.duration.core3.pin"

$overrideRows = @(Import-SwgTab -Path $paths.combatOverrides)
$profileRows = @(Import-SwgTab -Path $paths.weaponProfiles)
$skillRows = @(Import-SwgTab -Path $paths.skillTable)
$commandRows = @(Import-SwgTab -Path $paths.commandTable)
$combatRows = @(Import-SwgTab -Path $paths.combatData)
$headRows = @($overrideRows | Where-Object { [string]$_.actionName -ceq [string]$contract.optIn.command })
$controlOverrideRows = @($overrideRows | Where-Object { [string]$_.actionName -ceq [string]$contract.staticControl.command })
$controlCommandRows = @($commandRows | Where-Object { [string]$_.commandName -ceq [string]$contract.staticControl.command })
$controlCombatRows = @($combatRows | Where-Object { [string]$_.actionName -ceq [string]$contract.staticControl.command })
$probeRows = @($overrideRows | Where-Object { [string]$_.actionName -ceq "__precu_runtime_probe" })
$profile = @($profileRows | Where-Object { [string]$_.templateName -ceq [string]$contract.optIn.weaponTemplate })
$rifleOne = @($skillRows | Where-Object { [string]$_.NAME -ceq "combat_marksman_rifle_01" })
$novice = @($skillRows | Where-Object { [string]$_.NAME -ceq "combat_marksman_novice" })

Assert-Contract -Condition (
    $headRows.Count -eq 1 -and
    [double]$headRows[0].speedMultiplier -eq [double]$contract.optIn.speedMultiplier) -Name "p14.duration.headshot1.opt-in"
Assert-Contract -Condition (
    $probeRows.Count -eq 1 -and
    [double]$probeRows[0].speedMultiplier -eq 0) -Name "p14.duration.runtime-probe.inert"
Assert-Contract -Condition (
    $profile.Count -eq 1 -and
    [double]$profile[0].attackSpeed -eq [double]$contract.optIn.weaponAttackSpeed -and
    [string]$profile[0].speedSkill -ceq [string]$contract.optIn.weaponSpeedSkill) -Name "p14.duration.cdef-rifle.authenticated-profile"
Assert-Contract -Condition (
    $rifleOne.Count -eq 1 -and [string]$rifleOne[0].SKILL_MODS -match 'rifle_speed=5' -and
    $novice.Count -eq 1 -and [string]$novice[0].SKILL_MODS -match 'ranged_speed=5') -Name "p14.duration.fixture.speed-modifiers"
Assert-Contract -Condition (
    $controlCommandRows.Count -eq 1 -and
    [string]$controlCommandRows[0].characterAbility -ceq "headShot2" -and
    [string]$controlCommandRows[0].scriptHook -ceq "headShot2" -and
    [int]$controlCommandRows[0].disabled -eq 0 -and
    [int]$controlCommandRows[0].addToCombatQueue -eq 1 -and
    [string]$controlCommandRows[0].validWeapon -ceq "RIFLE" -and
    [Math]::Abs([double]$controlCommandRows[0].executeTime - 1.5) -lt 0.000001) -Name "p14.duration.control.authentic-static-command"
Assert-Contract -Condition (
    $controlOverrideRows.Count -eq 0 -and
    -not [bool]$contract.staticControl.overridePresent) -Name "p14.duration.control.absent-from-opt-in"
Assert-Contract -Condition (
    $controlCombatRows.Count -eq 1 -and
    [string]$controlCombatRows[0].weaponType -ceq "RIFLE" -and
    [string]$controlCombatRows[0].attackType -ceq "SINGLE_TARGET" -and
    [int]$controlCombatRows[0].actionCost -eq 150 -and
    [int]$controlCombatRows[0].mindCost -eq 60 -and
    [string]$controlCombatRows[0].buffNameTarget -ceq "" -and
    [string]$controlCombatRows[0].buffNameSelf -ceq "") -Name "p14.duration.control.authentic-combat-data"

$commandQueue = Get-Content -LiteralPath $paths.commandQueue -Raw
$helper = Get-BracedBlock -Text $commandQueue -Signature "float getCommandExecuteTime("
$combatActions = Get-Content -LiteralPath $paths.combatActions -Raw
$controlAction = Get-BracedBlock -Text $combatActions -Signature "public int headShot2("
$liveFixture = Get-Content -LiteralPath $paths.liveFixture -Raw

Assert-Contract -Condition (
    $helper.Contains('datatables/combat/precu_combat_overrides.iff') -or
    $commandQueue.Contains('cs_precuCombatOverridesTable = "datatables/combat/precu_combat_overrides.iff"')) -Name "p14.duration.runtime.command-opt-in-table"
Assert-Contract -Condition (
    $commandQueue.Contains('cs_precuWeaponProfilesTable = "datatables/combat/precu_weapon_profiles.iff"') -and
    $helper.Contains('weaponTable->searchColumnString(0, weaponTemplateName)')) -Name "p14.duration.runtime.weapon-profile-table"
Assert-Contract -Condition (
    ([regex]::Matches($helper, [regex]::Escape('return command.m_execTime;')).Count -ge 4) -and
    $helper.Contains('if (speedMultiplier <= 0.0f)')) -Name "p14.duration.runtime.fail-closed-static-fallback"
Assert-Contract -Condition (
    $helper.Contains('!owner.isPlayerControlled()') -and
    $helper.Contains('command.m_commandName == "creatureMeleeAttack"') -and
    $helper.Contains('command.m_commandName == "creatureRangedAttack"') -and
    $helper.Contains('creatureWeapon->getAttackTime()') -and
    $helper.Contains('return attackTime > 1.0f ? attackTime : 1.0f;')) -Name "p14.duration.runtime.creature-default-weapon-timing"
Assert-Contract -Condition (
    $helper.Contains('return 4.0f;') -and
    $helper.Contains('return executeTime > 1.0f ? executeTime : 1.0f;')) -Name "p14.duration.runtime.null-and-floor"
Assert-Contract -Condition (
    $helper.Contains('owner.getEnhancedModValue(speedSkill)') -and
    $helper.Contains('owner.getEnhancedModValue("private_speed_bonus")') -and
    $helper.Contains('owner.getEnhancedModValue("private_ranged_speed_bonus")') -and
    $helper.Contains('owner.getEnhancedModValue("ranged_speed")') -and
    $helper.Contains('owner.getEnhancedModValue("combat_haste")')) -Name "p14.duration.runtime.core3-modifier-stack"
Assert-Contract -Condition (
    $helper.Contains('(1.0f - static_cast<float>(speedModifier) / 100.0f) * speedMultiplier * weaponAttackSpeed') -and
    $helper.Contains('executeTime -= executeTime * haste;')) -Name "p14.duration.runtime.core3-formula"
Assert-Contract -Condition (
    $commandQueue.Contains('timeValues.push_back( m_commandTimes[ TimerClass_Execute ] );') -and
    [regex]::Matches($commandQueue, [regex]::Escape('s_currentTime + m_commandTimes[ TimerClass_Execute ]')).Count -eq 2 -and
    -not $commandQueue.Contains('s_currentTime + entry.m_command->m_execTime')) -Name "p14.duration.queue.authoritative-derived-timer"
Assert-Contract -Condition (
    $controlAction.Contains('combatStandardAction("headShot2", self, target, params, "", "")') -and
    -not $controlAction.Contains("buff")) -Name "p14.duration.control.standard-action-wrapper"
Assert-Contract -Condition (
    $liveFixture.Contains('DURATION_CONTROL_COMMAND = "headShot2"') -and
    $liveFixture.Contains('setObjVar(player, ORIGINAL_DURATION_CONTROL,') -and
    $liveFixture.Contains('grantCommand(attacker, DURATION_CONTROL_COMMAND)') -and
    $liveFixture.Contains('revokeCommand(attacker, DURATION_CONTROL_COMMAND)')) -Name "p14.duration.control.fixture-reversible-ownership"

$neutral = Get-ModeledDuration -WeaponAttackSpeed 3.5 -SpeedMultiplier 1.5 -SpeedModifier 0 -Haste 0
$marksman = Get-ModeledDuration -WeaponAttackSpeed 3.5 -SpeedMultiplier 1.5 -SpeedModifier 10 -Haste 0
$hasted = Get-ModeledDuration -WeaponAttackSpeed 3.5 -SpeedMultiplier 1.5 -SpeedModifier 10 -Haste 20
$floored = Get-ModeledDuration -WeaponAttackSpeed 3.5 -SpeedMultiplier 1.5 -SpeedModifier 100 -Haste 0
Assert-Contract -Condition ([Math]::Abs($neutral - [double]$contract.modeledAcceptance.neutralSeconds) -lt 0.000001) -Name "p14.duration.model.neutral"
Assert-Contract -Condition ([Math]::Abs($marksman - [double]$contract.modeledAcceptance.marksmanNoviceAndRifleOneSeconds) -lt 0.000001) -Name "p14.duration.model.marksman"
Assert-Contract -Condition ([Math]::Abs($hasted - [double]$contract.modeledAcceptance.twentyPercentHasteSeconds) -lt 0.000001) -Name "p14.duration.model.haste"
Assert-Contract -Condition ([Math]::Abs($floored - [double]$contract.modeledAcceptance.floorSeconds) -lt 0.000001) -Name "p14.duration.model.floor"
Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    @($contract.buildEvidence.targets).Count -eq 10) -Name "p14.duration.isolated-build.evidence"
Assert-Contract -Condition (
    [string]$contract.liveEvidence.lifecycle -ceq "d7a6c3e59f874b77a217202607170007" -and
    [string]$contract.liveEvidence.container -ceq "swg-precu" -and
    [string]$contract.liveEvidence.containerHealthAfterCleanup -ceq "healthy" -and
    [int]$contract.liveEvidence.clientBridgeProtocol -eq 13 -and
    [string]$contract.liveEvidence.clientSha256 -ceq "10F643B881239550AD4C479D706D32EAB7326670CE987BB5288CE316063BB909") -Name "p14.duration.live.identity-and-deployment"
Assert-Contract -Condition (
    [string]$contract.liveEvidence.staticControl.command -ceq "headShot2" -and
    [int]$contract.liveEvidence.staticControl.queueCountAfterAdmission -eq 1 -and
    [int]$contract.liveEvidence.staticControl.authoritativeTimerMaxMs -eq 1500 -and
    [int]$contract.liveEvidence.staticControl.commandTableExecuteMs -eq 1500 -and
    [string]$contract.liveEvidence.staticControl.authoritativeRemoval -ceq "Success") -Name "p14.duration.live.static-control-1500ms-success"
Assert-Contract -Condition (
    [string]$contract.liveEvidence.optedCommand.command -ceq "headShot1" -and
    [int]$contract.liveEvidence.optedCommand.queueCountAfterAdmission -eq 1 -and
    [int]$contract.liveEvidence.optedCommand.authoritativeTimerMaxMs -eq 4725 -and
    [int]$contract.liveEvidence.optedCommand.modeledTimerMaxMs -eq 4725 -and
    [string]$contract.liveEvidence.optedCommand.authoritativeRemoval -ceq "Success") -Name "p14.duration.live.opted-headshot1-4725ms-success"
Assert-Contract -Condition (
    [string]$contract.liveEvidence.cleanup.result -ceq "restored" -and
    [bool]$contract.liveEvidence.cleanup.durationControlRevoked -and
    [bool]$contract.liveEvidence.cleanup.rifleOneRestoredAbsent -and
    [bool]$contract.liveEvidence.cleanup.fixtureWeaponDestroyed -and
    [bool]$contract.liveEvidence.cleanup.pvpAndCombatCleared -and
    [bool]$contract.liveEvidence.cleanup.regenRestored -and
    @($contract.requiredBeforeReady).Count -eq 0) -Name "p14.duration.live.cleanup-and-readiness"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 command-duration contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 weapon-derived command-duration contract is ready with live static-fallback and opted-in timing evidence."
