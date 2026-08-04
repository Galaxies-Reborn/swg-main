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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14NativeNgeCommandSeriesRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$cppPath = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
$seriesPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/command/command_series.tab"
$skillDataPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$basePlayerPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { return "" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

foreach ($path in @($cppPath, $seriesPath, $skillDataPath, $basePlayerPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.command-series.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$cpp = Get-Content -LiteralPath $cppPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $cppPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."CreatureObject.cpp") `
    "p14.command-series.creature-source.authenticated"

$install = Get-BracedSurface $cpp "void CreatureObject::install()"
$recompute = Get-BracedSurface $cpp "void CreatureObject::recomputeCommandSeries()"
Assert-Contract ($install.Length -gt 0 -and -not $install.Contains("loadCommandSeriesTable")) `
    "p14.command-series.table-load-retired"
Assert-Contract (-not $cpp.Contains("CommandSeriesRecord") -and
    -not $cpp.Contains("s_commandSeriesRecords") -and
    -not $cpp.Contains("command_series.iff")) `
    "p14.command-series.native-table-consumer-retired"
Assert-Contract ($recompute.Contains("Link-compatible no-op") -and
    $recompute.Contains("owned skill boxes") -and
    -not $recompute.Contains("getLevel()") -and
    -not $recompute.Contains("grantCommand(") -and
    -not $recompute.Contains("revokeCommand(")) `
    "p14.command-series.compatibility-entrypoint-fails-closed"

$setup = Get-BracedSurface $cpp "void CreatureObject::setupSkillData()"
$grant = Get-BracedSurface $cpp "const bool CreatureObject::grantSkill"
$revoke = Get-BracedSurface $cpp "void CreatureObject::revokeSkill"
Assert-Contract ($setup.Contains("skill->getCommandsProvided ()") -and
    $setup.Contains("grantCommand(*i, true)")) `
    "p14.command-series.skill-load-command-authority-preserved"
Assert-Contract ($grant.Contains("newSkill.getCommandsProvided ()") -and
    $grant.Contains("grantCommand(*i, true)")) `
    "p14.command-series.skill-grant-command-authority-preserved"
Assert-Contract ($revoke.Contains("oldSkill.getCommandsProvided ()") -and
    $revoke.Contains("revokeCommand(*i, true)")) `
    "p14.command-series.skill-surrender-command-authority-preserved"

$series = @(Import-Csv -LiteralPath $seriesPath -Delimiter "`t" |
    Where-Object { $_.commandName -and $_.commandName -cne "s" })
Assert-Contract ($series.Count -eq [int]$contract.diagnosis.commandSeriesRows -and
    @($series.commandName | Sort-Object -Unique).Count -eq
        [int]$contract.diagnosis.uniqueSeriesCommands -and
    [int](($series | Measure-Object level -Minimum).Minimum) -eq
        [int]$contract.diagnosis.minimumLevel -and
    [int](($series | Measure-Object level -Maximum).Maximum) -eq
        [int]$contract.diagnosis.maximumLevel) `
    "p14.command-series.data-inventory"

$prefixCounts = @{}
foreach ($row in $series)
{
    $prefix = if ([string]$row.commandName -match '^([^_]+)_') { $matches[1] } else { "other" }
    if (-not $prefixCounts.ContainsKey($prefix)) { $prefixCounts[$prefix] = 0 }
    ++$prefixCounts[$prefix]
}
foreach ($property in $contract.diagnosis.prefixCounts.PSObject.Properties)
{
    Assert-Contract ($prefixCounts.ContainsKey($property.Name) -and
        [int]$prefixCounts[$property.Name] -eq [int]$property.Value) `
        "p14.command-series.prefix.$($property.Name)"
}

$skills = @(Import-Csv -LiteralPath $skillDataPath -Delimiter "`t" | Where-Object {
    $_.NAME -and $_.NAME -cne "s" -and -not $_.NAME.StartsWith("class_") -and
    $_.NAME -cne "expertise" -and -not $_.NAME.StartsWith("expertise_") -and
    -not $_.NAME.StartsWith("internal_expertise_")
})
$skillCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($skill in $skills)
{
    foreach ($command in ([string]$skill.COMMANDS -split ','))
    {
        if ($command) { [void]$skillCommands.Add($command) }
    }
}
$overlap = @($series | Where-Object {
    $skillCommands.Contains([string]$_.commandName) -or
    $skillCommands.Contains([string]$_.baseCommandName)
})
Assert-Contract ($overlap.Count -eq
    [int]$contract.diagnosis.seriesRowsOverlappingNonRetiredSkillCommands) `
    "p14.command-series.no-precu-skill-command-overlap"

Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $seriesPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.commandSeriesSha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $skillDataPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillDataSha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $basePlayerPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.basePlayerSha256) `
    "p14.command-series.compatibility-data-and-callers-preserved"
Assert-Contract ([regex]::Matches($basePlayer, 'recomputeCommandSeries\(self\);').Count -eq 4) `
    "p14.command-series.player-lifecycle-callers-route-to-safe-noop"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $source ("dsrc/sku.0/sys.server/compiled/game/script/" + $property.Name)
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.command-series.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.command-series.ready-evidence"
    Assert-Contract ($srcPin.Count -eq 1 -and
        [string]$srcPin[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.command-series.direct-source-pin"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.command-series.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.command-series.source-status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14NativeNgeCommandSeriesRetirement)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.command-series.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "Native NGE command-series retirement failed: $($failures -join ', ')"
}
Write-Host "Native NGE command-series retirement contract passed."
