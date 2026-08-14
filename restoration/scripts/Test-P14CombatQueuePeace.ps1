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
    if ($startIndex -lt 0)
    {
        return ""
    }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length,
        [StringComparison]::Ordinal)
    if ($nextIndex -lt 0)
    {
        return $Text.Substring($startIndex)
    }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$queuePath = Join-Path $source `
    "src/engine/server/library/serverGame/src/shared/command/CommandQueue.cpp"
$playerPath = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_player.java"
$tablePath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"

foreach ($path in @($queuePath, $playerPath, $tablePath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.combat-queue-peace.source.$([IO.Path]::GetFileName($path))"
}

$queueText = Get-Content -LiteralPath $queuePath -Raw
$isFull = Get-FunctionSlice -Text $queueText `
    -Start "bool CommandQueue::isFull() const" `
    -Next "void CommandQueue::enqueue("
$enqueue = Get-FunctionSlice -Text $queueText `
    -Start "void CommandQueue::enqueue(" `
    -Next "void CommandQueue::remove("
$clear = Get-FunctionSlice -Text $queueText `
    -Start "void CommandQueue::clearPendingCombatCommands()" `
    -Next "void CommandQueue::persistCooldown("

Assert-Contract ($queueText.Contains("cs_maxQueuedCombatCommands = 2")) `
    "p14.combat-queue-peace.npc-count-ceiling"
Assert-Contract ($isFull.Contains("creatureOwner->isPlayerControlled()") -and
    $isFull.Contains("return false;")) `
    "p14.combat-queue-peace.player-queue-unlimited"
Assert-Contract ($enqueue.Contains("command.m_addToCombatQueue && isFull()")) `
    "p14.combat-queue-peace.npc-admission-bounded"
Assert-Contract ($clear.Contains("cancelCurrentCommand();") -and
    $clear.Contains("handleEntryRemoved(*removed);") -and
    -not $clear.Contains("m_state.get() != State_Execute")) `
    "p14.combat-queue-peace.clear-includes-current"

$playerText = Get-Content -LiteralPath $playerPath -Raw
$peace = Get-FunctionSlice -Text $playerText `
    -Start "public int peace(" `
    -Next "public int OnExitedCombat("
Assert-Contract ($peace.Contains("queueClear(self);") -and
    $peace.Contains("stopCombat(self);") -and
    -not $peace.Contains("clearHate")) `
    "p14.combat-queue-peace.stop-without-hate-reset"

$lines = Get-Content -LiteralPath $tablePath
$header = $lines[0] -split "`t", -1
$matches = @($lines | Select-Object -Skip 2 | Where-Object {
    (($_ -split "`t", -1)[0]) -ceq "peace"
})
Assert-Contract ($matches.Count -eq 1) "p14.combat-queue-peace.command.unique"
if ($matches.Count -eq 1)
{
    $values = $matches[0] -split "`t", -1
    $row = @{}
    for ($index = 0; $index -lt $header.Count; ++$index)
    {
        $row[$header[$index]] = $values[$index]
    }
    Assert-Contract ($header.Count -eq 94 -and $values.Count -eq 94) `
        "p14.combat-queue-peace.command.columns-94"
    Assert-Contract ($row.defaultPriority -ceq "immediate" -and
        $row.scriptHook -ceq "peace" -and
        $row.targetType -ceq "none" -and
        $row.addToCombatQueue -ceq "0" -and
        $row.fromServerOnly -ceq "0") `
        "p14.combat-queue-peace.command.immediate-player-entry"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14 combat queue/peace contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14 combat queue/peace contract passed."
