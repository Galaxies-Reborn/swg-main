[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param([bool]$Condition, [string]$Name)
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

function Get-FunctionSlice
{
    param([string]$Text, [string]$Start, [string]$Next)
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$queuePath = Join-Path $source `
    "src/engine/server/library/serverGame/src/shared/command/CommandQueue.cpp"
$queueHeaderPath = Join-Path $source `
    "src/engine/server/library/serverGame/src/shared/command/CommandQueue.h"
$combatBasePath = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
$localOptionsPath = Join-Path $source "exe/linux/localOptions.cfg"
Assert-Contract (Test-Path -LiteralPath $queuePath -PathType Leaf) "p14.cadence.command-queue-source"
Assert-Contract (Test-Path -LiteralPath $queueHeaderPath -PathType Leaf) "p14.cadence.command-queue-header"
Assert-Contract (Test-Path -LiteralPath $combatBasePath -PathType Leaf) "p14.cadence.combat-base-source"
Assert-Contract (Test-Path -LiteralPath $localOptionsPath -PathType Leaf) "p14.cadence.log-target-source"

$queue = Get-Content -LiteralPath $queuePath -Raw
$queueHeader = Get-Content -LiteralPath $queueHeaderPath -Raw
$combatBase = Get-Content -LiteralPath $combatBasePath -Raw
$localOptions = Get-Content -LiteralPath $localOptionsPath -Raw
$timing = Get-FunctionSlice -Text $queue -Start "float calculatePrecuAttackTime(" -Next "float getCommandExecuteTime("
$execute = Get-FunctionSlice -Text $queue -Start "float getCommandExecuteTime(" -Next "using namespace CommandQueueNamespace;"
$isFull = Get-FunctionSlice -Text $queue -Start "bool CommandQueue::isFull() const" -Next "void CommandQueue::enqueue("
$enqueue = Get-FunctionSlice -Text $queue -Start "void CommandQueue::enqueue(" -Next "void CommandQueue::remove("
$cooldown = Get-FunctionSlice -Text $queue -Start "float CommandQueue::getCooldownTime(" -Next "void CommandQueue::resetCooldowns()"

foreach ($skill in @("rifle_speed", "carbine_speed", "pistol_speed", "heavyweapon_speed",
    "onehandmelee_speed", "twohandmelee_speed", "unarmed_speed", "polearm_speed",
    "onehandlightsaber_speed", "twohandlightsaber_speed", "polearmlightsaber_speed"))
{
    Assert-Contract ($queue.Contains('return "' + $skill + '";')) "p14.cadence.skill-family.$skill"
}
Assert-Contract ($timing.Contains("speedMultiplier * weaponAttackSpeed") -and
    $timing.Contains('getEnhancedModValue("private_speed_bonus")') -and
    $timing.Contains('getEnhancedModValue("combat_haste")') -and
    $timing.Contains("executeTime > 1.0f ? executeTime : 1.0f")) `
    "p14.cadence.precu-formula-and-floor"
Assert-Contract ($timing.Contains("if (!owner.isPlayerControlled())") -and
    $timing.IndexOf("return 2.0f;") -lt $timing.IndexOf("int speedModifier")) `
    "p14.cadence.core3-ai-two-second-interval"
Assert-Contract ($queue.Contains('LOG("PreCuCombatCadence"') -and
    $queue.Contains("s_currentTime") -and
    $queue.Contains("m_commandTimes[TimerClass_Execute]") -and
    $queue.Contains("weapon->getAttackTime()")) `
    "p14.cadence.live-execute-telemetry"
Assert-Contract ($localOptions.Contains(
    "logTarget=file:logs/precuCombatCadence.log{c-*:c+PreCuCombatCadence}")) `
    "p14.cadence.filtered-runtime-log-target"
Assert-Contract ($execute.Contains("command.isPrimaryCommand()") -and
    $execute.Contains("weapon->getAttackTime()") -and
    $execute.Contains("getPrecuWeaponSpeedSkill(*weapon)")) `
    "p14.cadence.primary-uses-live-weapon"
Assert-Contract ($cooldown.Contains("return 0.0f;") -and
    -not $cooldown.Contains("weapon->getAttackTime()")) `
    "p14.cadence.primary-interval-counted-once"
Assert-Contract ($queue.Contains("cs_maxQueuedCombatCommands = 2") -and
    $isFull.Contains("creatureOwner->isPlayerControlled()") -and
    $isFull.Contains("m_combatCount.get() >= cs_maxQueuedCombatCommands")) `
    "p14.cadence.npc-bounded-player-unlimited"
Assert-Contract ($enqueue.Contains("command.m_addToCombatQueue && isFull()") -and
    $enqueue.Contains("Command::CEC_Cancelled")) `
    "p14.cadence.npc-admission-enforced"
Assert-Contract (-not $combatBase.Contains("setCommandTimerValue(self, TIMER_COOLDOWN, 0.0f)")) `
    "p14.cadence.ai-script-cannot-clear-timer"
Assert-Contract ($queueHeader.Contains("m_lastWeaponCadenceAttackTime") -and
    $queueHeader.Contains("m_lastWeaponCadenceInterval") -and
    $queue.Contains("m_lastWeaponCadenceAttackTime = s_currentTime") -and
    $queue.Contains("m_lastWeaponCadenceInterval = m_commandTimes[TimerClass_Execute]") -and
    $queue.Contains("m_state.get() == State_Waiting") -and
    $queue.Contains("double const earliestAttackTime") -and
    $queue.Contains("m_nextEventTime = earliestAttackTime") -and
    $queue.Contains("gate time=")) `
    "p14.cadence.retarget-clear-preserves-last-interval"

if ($failures.Count -gt 0)
{
    throw "Publish 14 combat cadence contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14 combat cadence contract passed."
