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
    [string]$manifest.contracts.p14TameCommandLifecycle)
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
    return [pscustomobject]@{
        Header = $header
        Values = $values
        Row = $row
    }
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
        "p14.tame.source.$($entry.Key)"
}

$command = Get-Row -Path $paths.commandTable -Key "tame"
Assert-Contract ($null -ne $command) "p14.tame.command.unique"
if ($null -ne $command)
{
    Assert-Contract ($command.Header.Count -eq 94 -and
        $command.Values.Count -eq 94) "p14.tame.command.columns-94"
    Assert-Contract ($command.Row.scriptHook -ceq "cmdTame" -and
        $command.Row.tempScript -ceq "player.skill.taming") `
        "p14.tame.command.hook-and-script"
    Assert-Contract ($command.Row.target -ceq "other" -and
        $command.Row.targetType -ceq "required" -and
        $command.Row.maxRangeToTarget -ceq "32") `
        "p14.tame.command.target-and-client-range"
    Assert-Contract ($command.Row.defaultTime -ceq "0.5" -and
        $command.Row.addToCombatQueue -ceq "0" -and
        $command.Row.validWeapon -ceq "ALL" -and
        $command.Row.visible -ceq "2") `
        "p14.tame.command.dispatch-contract"
}

$skillRow = Get-Row -Path $paths.skillTable `
    -Key "outdoors_creaturehandler_novice"
Assert-Contract ($null -ne $skillRow) "p14.tame.skill.novice-row"
if ($null -ne $skillRow)
{
    Assert-Contract ($skillRow.Row.COMMANDS -match '(^|,)tame(,|"?$)' -and
        $skillRow.Row.SKILL_MODS -match 'stored_pets=4' -and
        $skillRow.Row.SKILL_MODS -match 'keep_creature=1' -and
        $skillRow.Row.SKILL_MODS -match 'tame_non_aggro=5' -and
        $skillRow.Row.SKILL_MODS -match 'tame_level=12') `
        "p14.tame.skill.ownership-and-mods"
}

$taming = Get-Content -LiteralPath $paths.taming -Raw
$tamingTask = Get-Content -LiteralPath $paths.tamingTask -Raw
$petLibrary = Get-Content -LiteralPath $paths.petLibrary -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$runnerPath = Join-Path $restorationRoot "scripts/Invoke-P14TameRuntime.ps1"
$runner = Get-Content -LiteralPath $runnerPath -Raw
$patchPath = Join-Path $restorationRoot `
    "patches/dsrc/240-p14-tame-command-lifecycle.patch"

Assert-Contract ($taming.Contains("public int cmdTame(") -and
    $taming.Contains("handlePrecuTamePhase") -and
    $taming.Contains("handlePrecuTameHold") -and
    $taming.Contains("TAME_PHASE_DELAY = 10.0f") -and
    $taming.Contains("TAME_HOLD_DELAY = 1.0f") -and
    $taming.Contains("TAME_RANGE = 8.0f")) `
    "p14.tame.production.phased-handler"
Assert-Contract ($taming.Contains('TAME_SCRIPT = "player.skill.taming_task"') -and
    $taming.Contains("attachScript(self, TAME_SCRIPT)") -and
    $taming.Contains("detachScript(self, TAME_SCRIPT)") -and
    $tamingTask.Contains("extends script.player.skill.taming")) `
    "p14.tame.production.owned-task-receiver"
Assert-Contract ($taming.Contains("canBeginTame") -and
    $taming.Contains("canContinueTame") -and
    $taming.Contains("canCommitTame") -and
    $taming.Contains("TAME_TARGET_LOCK")) `
    "p14.tame.production.transaction-revalidation"
Assert-Contract ($taming.Contains("getTameRoll") -and
    $taming.Contains("roll >= chance") -and
    $taming.Contains("sourceLevel * 20") -and
    $taming.Contains("xp.CREATUREHANDLER")) `
    "p14.tame.production.roll-and-xp"
Assert-Contract (-not $taming.Contains(
    "setDefaultCalmBehavior(target, ai_lib.BEHAVIOR_STOP)")) `
    "p14.tame.production.no-persistent-stop"
Assert-Contract ($petLibrary.Contains("makeTamedCreature") -and
    $petLibrary.Contains("persistObject(pet)") -and
    $petLibrary.Contains("ai.petAdvance.growthStage") -and
    $petLibrary.Contains("callable.setCallableLinks") -and
    $petLibrary.Contains("setupDefaultCommands") -and
    $petLibrary.Contains("savePetInfo") -and
    $petLibrary.Contains("petFollow")) `
    "p14.tame.production.pcd-persistence-and-callable"

Assert-Contract ($fixture.Contains("PLAYER_OID = 44003778L") -and
    $fixture.Contains("PLAYER_STATION_ID = 91001") -and
    $fixture.Contains("PROTOCOL_VERSION = 1") -and
    $fixture.Contains('CREATURE_TYPE = "worrt"')) `
    "p14.tame.fixture.identity-bound"
Assert-Contract ($fixture.Contains("prepare|status|store|call|cleanup") -and
    $fixture.Contains("pet_lib.storePet") -and
    $fixture.Contains("pet_lib.createPetFromData") -and
    $fixture.Contains("public int OnLogin") -and
    $fixture.Contains("handlePrecuTameFixturePoll") -and
    $fixture.Contains("alreadyClean=true restored=true")) `
    "p14.tame.fixture.lifecycle-and-idempotence"
Assert-Contract ($runner.Contains('"PrepareStore"') -and
    $runner.Contains('"VerifyRecall"') -and
    $runner.Contains("QueueTame") -and
    $runner.Contains("phaseCallbacks") -and
    $runner.Contains("Assert-Stored")) `
    "p14.tame.runner.restart-split-proof"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.tame.patch.present"

$hashes = $contract.buildEvidence.sourceSha256
Assert-Contract ((Get-Sha256 $paths.commandTable) -ceq
    [string]$hashes.'command_table.tab') "p14.tame.hash.command-table"
Assert-Contract ((Get-Sha256 $paths.skillTable) -ceq
    [string]$hashes.'skills.tab') "p14.tame.hash.skills"
Assert-Contract ((Get-Sha256 $paths.taming) -ceq
    [string]$hashes.'taming.java') "p14.tame.hash.taming"
Assert-Contract ((Get-Sha256 $paths.tamingTask) -ceq
    [string]$hashes.'taming_task.java') "p14.tame.hash.taming-task"
Assert-Contract ((Get-Sha256 $paths.petLibrary) -ceq
    [string]$hashes.'pet_lib.java') "p14.tame.hash.pet-library"
Assert-Contract ((Get-Sha256 $paths.liveFixture) -ceq
    [string]$hashes.'precu_tame_command_fixture.java') `
    "p14.tame.hash.fixture"
Assert-Contract ((Get-Sha256 $patchPath) -ceq
    [string]$contract.buildEvidence.patchSha256) "p14.tame.hash.patch"
Assert-Contract ((Get-Sha256 $runnerPath) -ceq
    [string]$contract.buildEvidence.runtimeRunnerSha256) `
    "p14.tame.hash.runner"

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        "p14.tame.status.ready"
    Assert-Contract ([string]$contract.buildEvidence.cleanMaterializationFingerprint `
        -cne "pending") "p14.tame.materialization.fingerprint"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 tame lifecycle contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 tame command lifecycle contract passed."
