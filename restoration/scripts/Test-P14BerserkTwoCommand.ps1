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
    [string]$manifest.contracts.p14BerserkTwoCommand)
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
        "p14.berserk-two.source.$($entry.Key)"
}

$command = Get-Row -Path $paths.commandTable -Key "berserk2"
Assert-Contract ($null -ne $command) "p14.berserk-two.command.unique"
if ($null -ne $command)
{
    Assert-Contract ($command.Header.Count -eq 94 -and
        $command.Values.Count -eq 94) "p14.berserk-two.command.columns-94"
    Assert-Contract ($command.Row.scriptHook -ceq "berserk2" -and
        $command.Row.failScriptHook -ceq "failSpecialAttack" -and
        $command.Row.tempScript -ceq "") "p14.berserk-two.command.hooks"
    Assert-Contract ($command.Row.target -ceq "other" -and
        $command.Row.targetType -ceq "optional" -and
        $command.Row.defaultTime -ceq "1.5" -and
        $command.Row.executeTime -ceq "1.5" -and
        $command.Row.addToCombatQueue -ceq "0" -and
        $command.Row.visible -ceq "2") "p14.berserk-two.command.dispatch"
    Assert-Contract ($command.Row.'S:berserk' -ceq "0") `
        "p14.berserk-two.command.no-reactivation"
}

$skillRow = Get-Row -Path $paths.skillTable -Key "combat_brawler_master"
Assert-Contract ($null -ne $skillRow -and
    $skillRow.Row.COMMANDS -match '(^|,)berserk2(,|"?$)' -and
    $skillRow.Row.SKILL_MODS -match '(^|,)berserk=20(,|"?$)') `
    "p14.berserk-two.skill.ownership-modifier"

$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$runnerPath = Join-Path $restorationRoot `
    "scripts/Invoke-P14BerserkTwoRuntime.ps1"
$runner = Get-Content -LiteralPath $runnerPath -Raw
$patchPath = Join-Path $restorationRoot `
    "patches/dsrc/244-p14-berserk-two-command.patch"

Assert-Contract ($basePlayer.Contains("public int berserk2(") -and
    $basePlayer.Contains("PRECU_BERSERK_TWO_HEALTH_COST = 100") -and
    $basePlayer.Contains("PRECU_BERSERK_TWO_ACTION_COST = 100") -and
    $basePlayer.Contains("PRECU_BERSERK_TWO_MIND_COST = 50") -and
    $basePlayer.Contains("PRECU_BERSERK_TWO_DURATION_SECONDS = 40") -and
    $basePlayer.Contains("fixture ? 5 : rand(0, 100)") -and
    $basePlayer.Contains('getSkillStatMod(self, "berserk")')) `
    "p14.berserk-two.production.policy"
Assert-Contract ($basePlayer.Contains('hasSkill(self, "combat_brawler_master")') -and
    $basePlayer.Contains("combat.isMeleeWeapon(weapon)") -and
    $basePlayer.Contains("drainCombatAttributes(self, healthCost, actionCost, mindCost)") -and
    $basePlayer.Contains("setState(self, STATE_BERSERK, true)") -and
    $basePlayer.Contains("handlePrecuBerserkExpiry") -and
    $basePlayer.Contains("restorePrecuBerserkState(self)") -and
    $basePlayer.Contains("scheduledExpiry != currentExpiry")) `
    "p14.berserk-two.production.transaction-lifecycle"
Assert-Contract ($fixture.Contains("PLAYER_OID = 44003778L") -and
    $fixture.Contains("PLAYER_STATION_ID = 91001") -and
    $fixture.Contains("PROTOCOL_VERSION = 1") -and
    $fixture.Contains('"combat_brawler_master"') -and
    $fixture.Contains('getSkillStatMod(player, "berserk") != 20') -and
    $fixture.Contains("setPreparedAttribute(player, HEALTH, 500)") -and
    $fixture.Contains("setPreparedAttribute(player, MIND, 500)") -and
    $fixture.Contains("alreadyClean=true restored=true")) `
    "p14.berserk-two.fixture.identity-master-lifecycle"
Assert-Contract ($runner.Contains("QueueBerserk2") -and
    $runner.Contains('"berserkModifier"') -and
    $runner.Contains('"healthCost"') -and
    $runner.Contains('"berserkState"') -and
    $runner.Contains('"expiredAt"')) `
    "p14.berserk-two.runner.real-client-proof"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.berserk-two.patch.present"

$hashes = $contract.buildEvidence.sourceSha256
Assert-Contract ((Get-Sha256 $paths.commandTable) -ceq
    [string]$hashes.'command_table.tab') "p14.berserk-two.hash.command-table"
Assert-Contract ((Get-Sha256 $paths.skillTable) -ceq
    [string]$hashes.'skills.tab') "p14.berserk-two.hash.skills"
Assert-Contract ((Get-Sha256 $paths.basePlayer) -ceq
    [string]$hashes.'base_player.java') "p14.berserk-two.hash.base-player"
Assert-Contract ((Get-Sha256 $paths.liveFixture) -ceq
    [string]$hashes.'precu_berserk_two_command_fixture.java') `
    "p14.berserk-two.hash.fixture"
Assert-Contract ((Get-Sha256 $patchPath) -ceq
    [string]$contract.buildEvidence.patchSha256) "p14.berserk-two.hash.patch"
Assert-Contract ((Get-Sha256 $runnerPath) -ceq
    [string]$contract.buildEvidence.runtimeRunnerSha256) `
    "p14.berserk-two.hash.runner"

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        "p14.berserk-two.status.ready"
    Assert-Contract ([string]$contract.buildEvidence.cleanMaterializationFingerprint `
        -cne "pending") "p14.berserk-two.materialization.fingerprint"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 berserk2 contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 berserk2 command contract passed."
