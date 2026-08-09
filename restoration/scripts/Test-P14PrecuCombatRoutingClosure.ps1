[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuCombatRoutingClosure)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skills)
$combatDataPath = Join-Path $source ([string]$contract.sourceFiles.combatData)
$combatOverridesPath = Join-Path $source ([string]$contract.sourceFiles.combatOverrides)
$combatActionsPath = Join-Path $source ([string]$contract.sourceFiles.combatActions)
$npcCombatDirectory = Join-Path $source ([string]$contract.sourceFiles.npcCombatDirectory)
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-CommaValues([object]$Value)
{
    return @(([string]$Value).Trim('"').Split(',') | Where-Object { $_ -cne "" })
}

function Get-OrdinalUnique([string[]]$Values)
{
    $set = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($value in $Values)
    {
        if (-not [string]::IsNullOrEmpty($value)) { [void]$set.Add($value) }
    }
    return @($set | Sort-Object)
}

function Get-FileSetSha256([System.IO.FileInfo[]]$Files)
{
    $lines = @($Files | Sort-Object Name | ForEach-Object {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
        "$($_.Name):$hash"
    })
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $algorithm.ComputeHash($bytes) }
    finally { $algorithm.Dispose() }
    return (($digest | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$sourcePaths = [ordered]@{
    skills = $skillsPath
    combatData = $combatDataPath
    combatOverrides = $combatOverridesPath
    combatActions = $combatActionsPath
}
foreach ($name in $sourcePaths.Keys)
{
    $path = $sourcePaths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.combat-routing.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) `
            "p14.combat-routing.source.$name.authenticated"
    }
}
Assert-Contract (Test-Path -LiteralPath $npcCombatDirectory -PathType Container) `
    "p14.combat-routing.source.npc-directory.exists"
$npcTables = @(Get-ChildItem -LiteralPath $npcCombatDirectory -Filter "npc_*.tab" -File |
    Sort-Object Name)
Assert-Contract ($npcTables.Count -eq [int]$contract.expected.npcCombatTables) `
    "p14.combat-routing.npc-table-count"
if ($npcTables.Count -gt 0)
{
    Assert-Contract ((Get-FileSetSha256 -Files $npcTables) -ceq
        [string]$contract.buildEvidence.sourceSha256.npcCombatTableSet) `
        "p14.combat-routing.source.npc-table-set.authenticated"
}

$skillRows = @(Import-SwgTab -Path $skillsPath)
$combatRows = @(Import-SwgTab -Path $combatDataPath)
$overrideRows = @(Import-SwgTab -Path $combatOverridesPath)
$retainedRoots = @($skillRows | Where-Object {
    [string]$_.IS_PROFESSION -ceq "1" -and
    [string]$_.NAME -notmatch '^(class_|pilot_|swg_)'
} | ForEach-Object { [string]$_.NAME })
$retainedRows = @($skillRows | Where-Object {
    $name = [string]$_.NAME
    @($retainedRoots | Where-Object {
        $name -ceq $_ -or $name.StartsWith("$_`_", [System.StringComparison]::Ordinal)
    }).Count -gt 0
})
$retainedCommands = @(Get-OrdinalUnique -Values @($retainedRows | ForEach-Object {
    Get-CommaValues $_.COMMANDS
}))
$combatNames = @(Get-OrdinalUnique -Values @($combatRows | ForEach-Object {
    [string]$_.actionName
}))
$overrideNames = @(Get-OrdinalUnique -Values @($overrideRows | ForEach-Object {
    [string]$_.actionName
}))
$retainedCombatActions = @($retainedCommands | Where-Object { $combatNames -ccontains $_ })
$directExceptions = @($contract.expected.directLifecycleExceptions |
    ForEach-Object { [string]$_ })
$missingRetained = @($retainedCombatActions |
    Where-Object { $overrideNames -cnotcontains $_ })
$uncoveredRetained = @($missingRetained |
    Where-Object { $directExceptions -cnotcontains $_ })

Assert-Contract ($retainedRoots.Count -eq [int]$contract.expected.retainedProfessionRoots) `
    "p14.combat-routing.retained-profession-roots"
Assert-Contract ($retainedRows.Count -eq [int]$contract.expected.retainedProfessionRows) `
    "p14.combat-routing.retained-profession-rows"
Assert-Contract ($retainedCommands.Count -eq [int]$contract.expected.retainedUniqueCommands) `
    "p14.combat-routing.retained-command-surface"
Assert-Contract ($retainedCombatActions.Count -eq [int]$contract.expected.retainedCombatActions) `
    "p14.combat-routing.retained-combat-actions"
Assert-Contract ($overrideRows.Count -eq [int]$contract.expected.combatOverrideRows -and
    $overrideNames.Count -eq $overrideRows.Count) `
    "p14.combat-routing.unique-combat-overrides"
Assert-Contract (($missingRetained -join "`n") -ceq ($directExceptions -join "`n") -and
    $uncoveredRetained.Count -eq [int]$contract.expected.uncoveredRetainedCombatActions) `
    "p14.combat-routing.no-player-nge-fallthrough"

$centerRows = @($combatRows | Where-Object { [string]$_.actionName -ceq "centerOfBeing" })
$combatActions = Get-Content -LiteralPath $combatActionsPath -Raw
$centerHandler = Get-SourceSlice $combatActions `
    "public int centerOfBeing(" `
    "public int forceFocus("
Assert-Contract ($centerRows.Count -eq 1 -and
    [string]$centerRows[0].hitType -ceq [string]$contract.expected.centerOfBeingCombatDataHitType -and
    $overrideNames -cnotcontains "centerOfBeing") `
    "p14.combat-routing.center-of-being-non-attack-exception"
Assert-Contract (-not $centerHandler.Contains('combatStandardAction("centerOfBeing"') -and
    $centerHandler.Contains('combat_engine.getCombatData("centerOfBeing")') -and
    $centerHandler.Contains('combat.canDrainCombatActionAttributes(') -and
    $centerHandler.Contains('buff.applyBuff(') -and
    $centerHandler.Contains('combat.drainCombatActionAttributes(')) `
    "p14.combat-routing.center-of-being-direct-lifecycle"

$npcValues = @($npcTables | ForEach-Object {
    Import-SwgTab -Path $_.FullName
} | ForEach-Object {
    $_.PSObject.Properties | ForEach-Object { [string]$_.Value }
})
$npcCombatActions = @(Get-OrdinalUnique -Values @($npcValues |
    Where-Object { $combatNames -ccontains $_ }))
$uncoveredNpc = @($npcCombatActions | Where-Object { $overrideNames -cnotcontains $_ })
Assert-Contract ($npcCombatActions.Count -eq [int]$contract.expected.npcCombatActions) `
    "p14.combat-routing.npc-combat-actions"
Assert-Contract ($uncoveredNpc.Count -eq [int]$contract.expected.uncoveredNpcCombatActions) `
    "p14.combat-routing.no-npc-nge-fallthrough"

$centerContractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14CenterOfBeingLifecycle)
$centerContract = Get-Content -LiteralPath $centerContractPath -Raw | ConvertFrom-Json
Assert-Contract ([string]$centerContract.status -ceq "ready") `
    "p14.combat-routing.center-of-being-adjacent-authority"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.combat-routing.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.combat-routing.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledDataSha256.skills -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledDataSha256.combatData -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledDataSha256.combatOverrides -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledDataSha256.npcCombatTableSet -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledDataPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.combat-routing.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "implemented-build-verified-live-validation-pending", "ready") -contains
        [string]$contract.status) "p14.combat-routing.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.combat-routing.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU combat routing closure failed: $($failures -join ', ')"
}
Write-Host "PRE-CU combat routing closure contract passed."
