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
    [string]$manifest.contracts.p14HealMindCommand)
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

function Get-BracedBlock
{
    param([string]$Text, [string]$Signature)
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    return ""
}

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($entry in $paths.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.heal-mind.source.$($entry.Key)"
}
$dsrcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "dsrc"
})
Assert-Contract ($dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq
        [string]$contract.buildEvidence.directSourceCommit) `
    "p14.heal-mind.direct-source-pin"

$command = Get-Row -Path $paths.commandTable -Key "healMind"
Assert-Contract ($null -ne $command) "p14.heal-mind.command.unique"
if ($null -ne $command)
{
    Assert-Contract ($command.Header.Count -eq 94 -and
        $command.Values.Count -eq 94) "p14.heal-mind.command.columns-94"
    Assert-Contract ($command.Row.scriptHook -ceq "healMind" -and
        $command.Row.failScriptHook -ceq "" -and
        $command.Row.tempScript -ceq "") "p14.heal-mind.command.hooks"
    Assert-Contract ($command.Row.target -ceq "other" -and
        $command.Row.targetType -ceq "optional" -and
        $command.Row.defaultTime -ceq "5" -and
        $command.Row.addToCombatQueue -ceq "0" -and
        $command.Row.visible -ceq "2") "p14.heal-mind.command.dispatch"
}

$skillRow = Get-Row -Path $paths.skillTable `
    -Key "science_combatmedic_healing_range_speed_04"
Assert-Contract ($null -ne $skillRow -and
    $skillRow.Row.COMMANDS -match '(^|,)healMind(,|"?$)') `
    "p14.heal-mind.skill.ownership"

$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$healing = Get-Content -LiteralPath $paths.healingLibrary -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$runnerPath = Join-Path $restorationRoot "scripts/Invoke-P14HealMindRuntime.ps1"
$runner = Get-Content -LiteralPath $runnerPath -Raw
$patchPath = Join-Path $restorationRoot `
    "patches/dsrc/242-p14-heal-mind-command.patch"
$healMind = Get-BracedBlock -Text $basePlayer `
    -Signature "public int healMind("
$sourceAwareFourArgumentHeal = Get-BracedBlock -Text $healing `
    -Signature "public static int healDamage(obj_id source, obj_id target, int attrib, int amount)"

Assert-Contract ($basePlayer.Contains("public int healMind(") -and
    $basePlayer.Contains("PRECU_HEAL_MIND_COST = 250") -and
    $basePlayer.Contains("PRECU_HEAL_MIND_RANGE = 5.0f") -and
    $basePlayer.Contains('rand(0, 500)') -and
    $basePlayer.Contains('combat_medic_effectiveness')) `
    "p14.heal-mind.production.policy"
Assert-Contract ($basePlayer.Contains("pvpCanHelp(self, target)") -and
    $basePlayer.Contains("canSee(self, target)") -and
    $basePlayer.Contains("healing.healDamage(self, target, MIND, healPower)") -and
    $basePlayer.Contains("addWound(self, MIND, woundCost)") -and
    $basePlayer.Contains("addShockWound(self, woundCost)") -and
    $basePlayer.Contains("pvpHelpPerformed(self, target)")) `
    "p14.heal-mind.production.transaction"
$healMindObserver = $contract.productionContract.campHealingObserver
Assert-Contract (
    [int]$healMindObserver.notificationsPerSuccessfulUse -eq 1 -and
    [string]$healMindObserver.notifyingPool -ceq "Mind" -and
    [bool]$healMindObserver.transitiveFourArgumentSourceAwareDefault -and
    -not [bool]$healMindObserver.redundantFiveArgumentCallRequired -and
    [int]$healMindObserver.battleFatigueCreditsPerPositiveHeal -eq 1 -and
    [bool]$healMindObserver.clampedAppliedDeltaZeroStillCountsAsAuthoredEvent -and
    [int]$healMindObserver.rejectedOrNoDamageNotifications -eq 0 -and
    [string]$healMindObserver.payload -ceq
        "target receives healer object id plus native authoritative applied Mind delta" -and
    -not [string]::IsNullOrEmpty($healMind) -and
    [regex]::Matches(
        $healMind,
        '(?s)healing\.healDamage\s*\(\s*self\s*,\s*target\s*,\s*MIND\s*,\s*healPower\s*\)').Count -eq 1 -and
    -not [regex]::IsMatch(
        $healMind,
        '(?s)healing\.healDamage\s*\([^;]+?\b(?:true|false)\s*\);') -and
    $healMind.IndexOf(
        'recordPrecuHealMindOutcome(self, fixture, "noMindDamage");',
        [StringComparison]::Ordinal) -lt
        $healMind.IndexOf(
            "int healedMind = healing.healDamage(",
            [StringComparison]::Ordinal) -and
    -not [string]::IsNullOrEmpty($sourceAwareFourArgumentHeal) -and
    $sourceAwareFourArgumentHeal.Contains(
        "healDamage(source, target, attrib, amount, true)") -and
    [regex]::Matches(
        $sourceAwareFourArgumentHeal,
        'pvp\.bfCreditForHealing\s*\(\s*source\s*,\s*delta\s*\)').Count -eq 1) `
    "p14.heal-mind.production.transitive-observer-and-single-bf-credit"
Assert-Contract ($fixture.Contains("PLAYER_OID = 44003778L") -and
    $fixture.Contains("PLAYER_STATION_ID = 91001") -and
    $fixture.Contains("PROTOCOL_VERSION = 1") -and
    $fixture.Contains("science_combatmedic_healing_range_speed_04") -and
    $fixture.Contains("makeTamedCreature") -and
    $fixture.Contains("ORIGINAL_WILLPOWER_WOUND") -and
    $fixture.Contains("alreadyClean=true restored=true") -and
    $fixture.Contains("public int OnLogin")) `
    "p14.heal-mind.fixture.identity-lifecycle"
Assert-Contract ($runner.Contains("QueueHealMind") -and
    $runner.Contains('"targetMindBefore"') -and
    $runner.Contains('"healerMindAfterWounds"') -and
    $runner.Contains('"battleFatigueDelta"')) `
    "p14.heal-mind.runner.real-client-proof"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.heal-mind.patch.present"

$hashes = $contract.buildEvidence.sourceSha256
Assert-Contract ((Get-Sha256 $paths.commandTable) -ceq
    [string]$hashes.'command_table.tab') "p14.heal-mind.hash.command-table"
Assert-Contract ((Get-Sha256 $paths.skillTable) -ceq
    [string]$hashes.'skills.tab') "p14.heal-mind.hash.skills"
Assert-Contract ((Get-Sha256 $paths.basePlayer) -ceq
    [string]$hashes.'base_player.java') "p14.heal-mind.hash.base-player"
Assert-Contract ((Get-Sha256 $paths.healingLibrary) -ceq
    [string]$hashes.'healing.java') "p14.heal-mind.hash.healing-library"
Assert-Contract ((Get-Sha256 $paths.liveFixture) -ceq
    [string]$hashes.'precu_heal_mind_command_fixture.java') `
    "p14.heal-mind.hash.fixture"
Assert-Contract ((Get-Sha256 $patchPath) -ceq
    [string]$contract.buildEvidence.patchSha256) "p14.heal-mind.hash.patch"
Assert-Contract ((Get-Sha256 $runnerPath) -ceq
    [string]$contract.buildEvidence.runtimeRunnerSha256) `
    "p14.heal-mind.hash.runner"

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        "p14.heal-mind.status.ready"
    Assert-Contract ([string]$contract.buildEvidence.cleanMaterializationFingerprint `
        -cne "pending") "p14.heal-mind.materialization.fingerprint"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 healMind contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 healMind command contract passed."
