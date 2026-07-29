[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (
    Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot (
    [string]$manifest.contracts.p14FormupCommand)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
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

function Get-Row
{
    param([string]$Path, [string]$Key)
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $matches = @($lines | Select-Object -Skip 2 | Where-Object {
        (($_ -split "`t", -1)[0]) -ceq $Key
    })
    if ($matches.Count -ne 1)
    {
        return $null
    }
    $values = $matches[0] -split "`t", -1
    $row = @{}
    for ($index = 0; $index -lt $header.Count; ++$index)
    {
        $row[$header[$index]] = $values[$index]
    }
    return [pscustomobject]@{ Header = $header; Values = $values; Row = $row }
}

function Get-Sha256
{
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.formup.source.$($entry.Key)"
}

$command = Get-Row -Path $paths.commandTable -Key "formup"
Assert-Contract ($null -ne $command) "p14.formup.command.unique"
if ($null -ne $command)
{
    Assert-Contract ($command.Header.Count -eq 94 -and
        $command.Values.Count -eq 94) "p14.formup.command.columns-94"
    Assert-Contract ($command.Row.scriptHook -ceq "formup" -and
        $command.Row.failScriptHook -ceq "failSpecialAttack" -and
        $command.Row.tempScript -ceq "") "p14.formup.command.hooks"
    Assert-Contract ($command.Row.target -ceq "other" -and
        $command.Row.targetType -ceq "none" -and
        $command.Row.defaultTime -ceq "1.5" -and
        $command.Row.executeTime -ceq "1.5" -and
        $command.Row.addToCombatQueue -ceq "0" -and
        $command.Row.visible -ceq "2") "p14.formup.command.dispatch"
    Assert-Contract ($command.Row.'S:stunned' -ceq "1" -and
        $command.Row.'S:dizzy' -ceq "0") `
        "p14.formup.command.retained-state-admission"
}

$skillRow = Get-Row -Path $paths.skillTable `
    -Key "outdoors_squadleader_defense_01"
Assert-Contract ($null -ne $skillRow -and
    $skillRow.Row.COMMANDS -match '(^|,)formup(,|"?$)') `
    "p14.formup.skill.defense-one-ownership"

$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$runnerPath = Join-Path $restorationRoot "scripts/Invoke-P14FormupRuntime.ps1"
$runner = Get-Content -LiteralPath $runnerPath -Raw
$patchPath = Join-Path $restorationRoot `
    "patches/dsrc/245-p14-formup-command.patch"

Assert-Contract ($basePlayer.Contains("public int formup(") -and
    $basePlayer.Contains("PRECU_FORMUP_BASE_COST = 50") -and
    $basePlayer.Contains('hasSkill(self, "outdoors_squadleader_defense_01")') -and
    $basePlayer.Contains("members.length / 20.0f") -and
    $basePlayer.Contains("calculatePrecuBerserkCost(") -and
    $basePlayer.Contains("drainCombatAttributes(self, healthCost, actionCost, mindCost)")) `
    "p14.formup.production.leader-group-cost-policy"
Assert-Contract ($basePlayer.Contains("isValidPrecuSquadTarget") -and
    $basePlayer.Contains("setState(member, STATE_DIZZY, false)") -and
    $basePlayer.Contains("setState(member, STATE_STUNNED, false)") -and
    $basePlayer.Contains("pvpCanHelp(leader, member)") -and
    $basePlayer.Contains("pvpHelpPerformed(self, member)")) `
    "p14.formup.production.member-filter-state-help"
Assert-Contract ($fixture.Contains("LEADER_OID = 44003778L") -and
    $fixture.Contains("LEADER_STATION_ID = 91001") -and
    $fixture.Contains("MEMBER_OID = 207005062L") -and
    $fixture.Contains("MEMBER_STATION_ID = 1391050504") -and
    $fixture.Contains('"outdoors_squadleader_defense_01"') -and
    $fixture.Contains("EXPECTED_GROUP_SIZE = 2") -and
    $fixture.Contains("EXPECTED_BASE_COST = 55") -and
    $fixture.Contains("calculateExpectedCost") -and
    $fixture.Contains("originalLeader[0] > expectedHealthCost") -and
    $fixture.Contains("purgedOrphanedMarker=true") -and
    $fixture.Contains("hasPreparedState") -and
    $fixture.Contains("OWNED_SUFFIXES") -and
    $fixture.Contains("clearFixtureVariables") -and
    -not $fixture.Contains("persistObject(") -and
    $fixture.Contains("setAttrib(player, HEALTH, attributes[0])") -and
    $fixture.Contains("setAttrib(player, ACTION, attributes[2])") -and
    $fixture.Contains("setAttrib(player, MIND, attributes[4])") -and
    -not $fixture.Contains("setAttrib(player, ATTRIBUTES[index]") -and
    -not $fixture.Contains("setMaxAttrib(player, ATTRIBUTES[index]") -and
    $fixture.Contains("groupStillActiveUseRealClientDisband") -and
    $fixture.Contains("alreadyClean=true restored=true")) `
    "p14.formup.fixture.two-identity-reversible-lifecycle"
Assert-Contract ($runner.Contains("TargetSquadCounterpart") -and
    $runner.Contains("InviteTarget") -and
    $runner.Contains("JoinGroup") -and
    $runner.Contains("QueueFormup") -and
    $runner.Contains("DisbandGroup") -and
    $runner.Contains('"membersApplied"') -and
    $runner.Contains('"adjustedBaseCost"')) `
    "p14.formup.runner.real-two-client-proof"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.formup.patch.present"

$hashes = $contract.buildEvidence.sourceSha256
Assert-Contract ((Get-Sha256 $paths.commandTable) -ceq
    [string]$hashes.'command_table.tab') "p14.formup.hash.command-table"
Assert-Contract ((Get-Sha256 $paths.skillTable) -ceq
    [string]$hashes.'skills.tab') "p14.formup.hash.skills"
Assert-Contract ((Get-Sha256 $paths.basePlayer) -ceq
    [string]$hashes.'base_player.java') "p14.formup.hash.base-player"
Assert-Contract ((Get-Sha256 $paths.liveFixture) -ceq
    [string]$hashes.'precu_formup_command_fixture.java') `
    "p14.formup.hash.fixture"
Assert-Contract ((Get-Sha256 $patchPath) -ceq
    [string]$contract.buildEvidence.patchSha256) "p14.formup.hash.patch"
Assert-Contract ((Get-Sha256 $runnerPath) -ceq
    [string]$contract.buildEvidence.runtimeRunnerSha256) `
    "p14.formup.hash.runner"

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        "p14.formup.status.ready"
    Assert-Contract ([string]$contract.buildEvidence.cleanMaterializationFingerprint `
        -cne "pending") "p14.formup.materialization.fingerprint"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 formup contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 formup command contract passed."
