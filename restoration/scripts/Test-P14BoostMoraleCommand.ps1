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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot (
    [string]$manifest.contracts.p14BoostMoraleCommand)) -Raw |
    ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-Row
{
    param([string]$Path, [string]$Key)
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $matches = @($lines | Select-Object -Skip 2 | Where-Object {
        (($_ -split "`t", -1)[0]) -ceq $Key
    })
    if ($matches.Count -ne 1) { return $null }
    $values = $matches[0] -split "`t", -1
    $row = @{}
    for ($index = 0; $index -lt $header.Count; ++$index)
    {
        $row[$header[$index]] = $values[$index]
    }
    return [pscustomobject]@{Header=$header; Values=$values; Row=$row}
}

function Get-Sha256
{
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.boost-morale.source.$($entry.Key)"
}

$command = Get-Row -Path $paths.commandTable -Key "boostmorale"
Assert-Contract ($null -ne $command) "p14.boost-morale.command.unique"
if ($null -ne $command)
{
    Assert-Contract ($command.Header.Count -eq 94 -and
        $command.Values.Count -eq 94) "p14.boost-morale.command.columns-94"
    Assert-Contract ($command.Row.scriptHook -ceq "boostmorale" -and
        $command.Row.failScriptHook -ceq "failSpecialAttack" -and
        $command.Row.target -ceq "other" -and
        $command.Row.targetType -ceq "none") `
        "p14.boost-morale.command.dispatch"
    Assert-Contract ($command.Row.defaultTime -ceq "1.5" -and
        $command.Row.executeTime -ceq "1.5" -and
        $command.Row.addToCombatQueue -ceq "0" -and
        $command.Row.visible -ceq "2") `
        "p14.boost-morale.command.timing-visibility"
}

$skill = Get-Row -Path $paths.skillTable `
    -Key "outdoors_squadleader_defense_04"
Assert-Contract ($null -ne $skill -and
    $skill.Row.COMMANDS -match '(^|,)boostmorale(,|"?$)') `
    "p14.boost-morale.skill.defense-four-ownership"

$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$runnerPath = Join-Path $restorationRoot `
    "scripts/Invoke-P14BoostMoraleRuntime.ps1"
$runner = Get-Content -LiteralPath $runnerPath -Raw
$patchPath = Join-Path $restorationRoot `
    "patches/dsrc/247-p14-boost-morale-command.patch"

Assert-Contract ($basePlayer.Contains("public int boostmorale(") -and
    $basePlayer.Contains("PRECU_BOOST_MORALE_BASE_COST = 100") -and
    $basePlayer.Contains('hasSkill(self, "outdoors_squadleader_defense_04")') -and
    $basePlayer.Contains("members.length / 20.0f") -and
    $basePlayer.Contains("calculatePrecuBerserkCost(") -and
    $basePlayer.Contains("drainCombatAttributes(self, healthCost, actionCost, mindCost)")) `
    "p14.boost-morale.production.leader-group-ham-policy"
Assert-Contract ($basePlayer.Contains("for (int attribute = HEALTH; attribute <= WILLPOWER; ++attribute)") -and
    $basePlayer.Contains("totalWounds / (float)eligible.size())") -and
    $basePlayer.Contains("Math.ceil(woundsPerMember / 9.0f)") -and
    $basePlayer.Contains("totalWoundsApplied + woundsToApply > totalWounds") -and
    $basePlayer.Contains("pvpHelpPerformed(self, member)")) `
    "p14.boost-morale.production.exact-nine-attribute-conservation"
Assert-Contract ($fixture.Contains("LEADER_OID = 44003778L") -and
    $fixture.Contains("MEMBER_OID = 207005062L") -and
    $fixture.Contains("EXPECTED_TOTAL_WOUNDS = 91") -and
    $fixture.Contains("EXPECTED_WOUNDS_PER_MEMBER = 46") -and
    $fixture.Contains("EXPECTED_WOUNDS_PER_ATTRIBUTE = 6") -and
    $fixture.Contains("LEADER_EXPECTED_WOUNDS") -and
    $fixture.Contains("MEMBER_EXPECTED_WOUNDS") -and
    $fixture.Contains("observeCommand") -and
    $fixture.Contains("alreadyClean=true restored=true")) `
    "p14.boost-morale.fixture.two-identity-reversible-conservation"
Assert-Contract ($runner.Contains("TargetSquadCounterpart") -and
    $runner.Contains("InviteTarget") -and
    $runner.Contains("JoinGroup") -and
    $runner.Contains("QueueBoostMorale") -and
    $runner.Contains("DisbandGroup") -and
    $runner.Contains('$expectedHealthCost = 46') -and
    $runner.Contains('$expectedActionCost = 110') -and
    $runner.Contains('$expectedMindCost = 129')) `
    "p14.boost-morale.runner.real-two-client-proof"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.boost-morale.patch.present"

$hashes = $contract.buildEvidence.sourceSha256
Assert-Contract ((Get-Sha256 $paths.commandTable) -ceq
    [string]$hashes.'command_table.tab') "p14.boost-morale.hash.command-table"
Assert-Contract ((Get-Sha256 $paths.skillTable) -ceq
    [string]$hashes.'skills.tab') "p14.boost-morale.hash.skills"
Assert-Contract ((Get-Sha256 $paths.basePlayer) -ceq
    [string]$hashes.'base_player.java') "p14.boost-morale.hash.base-player"
Assert-Contract ((Get-Sha256 $paths.liveFixture) -ceq
    [string]$hashes.'precu_boost_morale_command_fixture.java') `
    "p14.boost-morale.hash.fixture"
Assert-Contract ((Get-Sha256 $patchPath) -ceq
    [string]$contract.buildEvidence.patchSha256) `
    "p14.boost-morale.hash.patch"
Assert-Contract ((Get-Sha256 $runnerPath) -ceq
    [string]$contract.buildEvidence.runtimeRunnerSha256) `
    "p14.boost-morale.hash.runner"

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        "p14.boost-morale.status.ready"
    Assert-Contract ([string]$contract.buildEvidence.cleanMaterializationFingerprint `
        -cne "pending") "p14.boost-morale.materialization.fingerprint"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 boostmorale contract failed: $($failures -join ', ')"
}
Write-Host ""
Write-Host "Publish 14.1 boostmorale command contract passed."
