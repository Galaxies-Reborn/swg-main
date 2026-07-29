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
    [string]$manifest.contracts.p14EmboldenPetsCommand)
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
        "p14.embolden-pets.source.$($entry.Key)"
}

$command = Get-Row -Path $paths.commandTable -Key "emboldenpets"
Assert-Contract ($null -ne $command) "p14.embolden-pets.command.unique"
if ($null -ne $command)
{
    Assert-Contract ($command.Header.Count -eq 94 -and
        $command.Values.Count -eq 94) "p14.embolden-pets.command.columns-94"
    Assert-Contract ($command.Row.scriptHook -ceq "emboldenPets" -and
        $command.Row.failScriptHook -ceq "failPetBuff" -and
        $command.Row.tempScript -ceq "") `
        "p14.embolden-pets.command.hooks"
    Assert-Contract ($command.Row.target -ceq "other" -and
        $command.Row.targetType -ceq "optional" -and
        $command.Row.defaultTime -ceq "1.5" -and
        $command.Row.addToCombatQueue -ceq "0" -and
        $command.Row.visible -ceq "2") `
        "p14.embolden-pets.command.dispatch-contract"
}

$skill = Get-Row -Path $paths.skillTable `
    -Key "outdoors_creaturehandler_healing_02"
Assert-Contract ($null -ne $skill -and
    $skill.Row.COMMANDS -match '(^|,)emboldenpets(,|"?$)') `
    "p14.embolden-pets.skill.ownership"

$buff = Get-Row -Path $paths.buffTable -Key "emboldenPet"
Assert-Contract ($null -ne $buff) "p14.embolden-pets.buff.unique"
if ($null -ne $buff)
{
    Assert-Contract ($buff.Row.DURATION -ceq "60" -and
        $buff.Row.EFFECT1_PARAM -ceq "healthPercent" -and
        $buff.Row.EFFECT1_VALUE -ceq "15" -and
        $buff.Row.EFFECT2_PARAM -ceq "actionPercent" -and
        $buff.Row.EFFECT2_VALUE -ceq "15" -and
        $buff.Row.EFFECT3_PARAM -ceq "mindPercent" -and
        $buff.Row.EFFECT3_VALUE -ceq "15") `
        "p14.embolden-pets.buff.three-pool-contract"
}

$petMaster = Get-Content -LiteralPath $paths.petMaster -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$runnerPath = Join-Path $restorationRoot `
    "scripts/Invoke-P14EmboldenPetsRuntime.ps1"
$runner = Get-Content -LiteralPath $runnerPath -Raw
$patchPath = Join-Path $restorationRoot `
    "patches/dsrc/241-p14-embolden-pets-command.patch"

Assert-Contract ($petMaster.Contains("public int emboldenPets(") -and
    $petMaster.Contains("PRECU_EMBOLDEN_RANGE = 50.0f") -and
    $petMaster.Contains("PRECU_EMBOLDEN_DURATION = 60.0f") -and
    $petMaster.Contains("PRECU_EMBOLDEN_COOLDOWN_SECONDS = 300") -and
    $petMaster.Contains("PRECU_EMBOLDEN_BASE_MIND_COST = 100")) `
    "p14.embolden-pets.production.policy"
Assert-Contract ($petMaster.Contains("buff.applyBuff(") -and
    $petMaster.Contains("getPrecuEmboldenMindCost") -and
    $petMaster.Contains("callable.getCallable(") -and
    $petMaster.Contains("getDistance(self, pet)") -and
    $petMaster.Contains("setAttrib(self, MIND, mindBefore - mindCost)")) `
    "p14.embolden-pets.production.transaction"
Assert-Contract ($fixture.Contains("PLAYER_OID = 44003778L") -and
    $fixture.Contains("PLAYER_STATION_ID = 91001") -and
    $fixture.Contains("PROTOCOL_VERSION = 1") -and
    $fixture.Contains("prepare|status|cleanup|recover") -and
    $fixture.Contains("getDatapadCallablesByType") -and
    $fixture.Contains("ORIGINAL_MIND_MAX") -and
    $fixture.Contains("alreadyClean=true restored=true") -and
    $fixture.Contains("public int OnLogin")) `
    "p14.embolden-pets.fixture.identity-lifecycle"
Assert-Contract ($runner.Contains("QueueEmboldenPets") -and
    $runner.Contains("expectedMindCost") -and
    $runner.Contains('"healthMaxDelta"') -and
    $runner.Contains('"cooldownRemaining"')) `
    "p14.embolden-pets.runner.real-client-proof"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.embolden-pets.patch.present"

$hashes = $contract.buildEvidence.sourceSha256
Assert-Contract ((Get-Sha256 $paths.commandTable) -ceq
    [string]$hashes.'command_table.tab') "p14.embolden-pets.hash.command-table"
Assert-Contract ((Get-Sha256 $paths.skillTable) -ceq
    [string]$hashes.'skills.tab') "p14.embolden-pets.hash.skills"
Assert-Contract ((Get-Sha256 $paths.buffTable) -ceq
    [string]$hashes.'buff.tab') "p14.embolden-pets.hash.buff-table"
Assert-Contract ((Get-Sha256 $paths.petMaster) -ceq
    [string]$hashes.'pet_master.java') "p14.embolden-pets.hash.pet-master"
Assert-Contract ((Get-Sha256 $paths.liveFixture) -ceq
    [string]$hashes.'precu_embolden_pets_command_fixture.java') `
    "p14.embolden-pets.hash.fixture"
Assert-Contract ((Get-Sha256 $patchPath) -ceq
    [string]$contract.buildEvidence.patchSha256) "p14.embolden-pets.hash.patch"
Assert-Contract ((Get-Sha256 $runnerPath) -ceq
    [string]$contract.buildEvidence.runtimeRunnerSha256) `
    "p14.embolden-pets.hash.runner"

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        "p14.embolden-pets.status.ready"
    Assert-Contract ([string]$contract.buildEvidence.cleanMaterializationFingerprint `
        -cne "pending") "p14.embolden-pets.materialization.fingerprint"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 emboldenPets contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 emboldenPets command contract passed."
