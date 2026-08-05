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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuAxkvaNandinaHealingAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$paths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $source ([string]$property.Value)
}
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedBlock([string]$Text, [string]$Signature)
{
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
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.nandina.source.$([IO.Path]::GetFileName($path)).exists"
}

$combatActions = Get-Content -LiteralPath $paths.combatActions -Raw
$nandinaHeal = Get-BracedBlock $combatActions `
    "public int nandina_heal(obj_id self, obj_id target, String params, float defaultTime)"
$combatData = Get-Content -LiteralPath $paths.combatData -Raw
$commandTable = Get-Content -LiteralPath $paths.commandTable -Raw
$aiProfiles = Get-Content -LiteralPath $paths.aiProfiles -Raw
$spawnRows = @(Import-Csv -LiteralPath $paths.spawnTable -Delimiter "`t")
$creatureRows = @(Import-Csv -LiteralPath $paths.creatures -Delimiter "`t")
$javaRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$healingReductionConsumers = @(Get-ChildItem -LiteralPath $javaRoot -Recurse -File -Filter "*.java" |
    Select-String -SimpleMatch "expertise_healing_reduction")

Assert-Contract ($healingReductionConsumers.Count -eq
    [int]$contract.expected.serverJavaHealingReductionConsumers) `
    "p14.nandina.server-java-healing-reduction-consumers-closed"
Assert-Contract (-not $nandinaHeal.Contains("expertise_") -and
    -not $nandinaHeal.Contains("getEnhancedSkillStatisticModifierUncapped") -and
    -not $nandinaHeal.Contains("healingReduction") -and
    -not $nandinaHeal.Contains("redux")) `
    "p14.nandina.nge-healing-reduction-authority-absent"
Assert-Contract (([regex]::Matches($nandinaHeal,
    'healing\.healDamage\(gorvo, HEALTH, 50000\);')).Count -eq 1 -and
    [int]$contract.expected.authoredNandinaHeal -eq 50000) `
    "p14.nandina.authored-heal"
Assert-Contract ($nandinaHeal.Contains('trial.getObjectsInDungeonWithObjVar(trial.getTop(self), "spawn_id")') -and
    $nandinaHeal.Contains('equals("gorvo")') -and
    $nandinaHeal.Contains("!isIdValid(gorvo) || ai_lib.isDead(gorvo)")) `
    "p14.nandina.gorvo-resolution-and-admission-preserved"
Assert-Contract ($nandinaHeal.Contains('playClientEffectLoc(gorvo, "clienteffect/bacta_bomb.cef"')) `
    "p14.nandina.client-effect-preserved"

Assert-Contract (([regex]::Matches($commandTable, '(?m)^nandina_heal\t')).Count -eq 1 -and
    ([regex]::Matches($combatData, '(?m)^nandina_heal\t')).Count -eq 1) `
    "p14.nandina.command-and-combat-routing-preserved"
Assert-Contract (([regex]::Matches($aiProfiles,
    '(?m)^heroic_axkva_nandina\t.*\tnandina_heal\t10\t100(?:\t|$)')).Count -eq 1) `
    "p14.nandina.authored-ai-cadence-preserved"

$nandinaSpawns = @($spawnRows | Where-Object { [string]$_.object -ceq "heroic_axkva_nandina" })
$gorvoSpawns = @($spawnRows | Where-Object { [string]$_.object -ceq "heroic_axkva_gorvo" })
Assert-Contract ($nandinaSpawns.Count -eq [int]$contract.expected.initialAndResetSpawnRowsPerActor -and
    $gorvoSpawns.Count -eq [int]$contract.expected.initialAndResetSpawnRowsPerActor -and
    @($nandinaSpawns | Where-Object { [string]$_.spawn_id -cne "nandina" -or
        [string]$_.script -cne "theme_park.heroic.axkva_min.nandina" }).Count -eq 0 -and
    @($gorvoSpawns | Where-Object { [string]$_.spawn_id -cne "gorvo" -or
        [string]$_.script -cne "theme_park.heroic.axkva_min.gorvo" }).Count -eq 0) `
    "p14.nandina.initial-and-reset-spawns-preserved"

$nandinaCreatures = @($creatureRows | Where-Object { [string]$_.creatureName -ceq "heroic_axkva_nandina" })
$gorvoCreatures = @($creatureRows | Where-Object { [string]$_.creatureName -ceq "heroic_axkva_gorvo" })
Assert-Contract ($nandinaCreatures.Count -eq 1 -and $gorvoCreatures.Count -eq 1 -and
    [int]$nandinaCreatures[0].BaseLevel -eq [int]$contract.expected.nandinaCreatureLevel -and
    [int]$gorvoCreatures[0].BaseLevel -eq [int]$contract.expected.gorvoCreatureLevel -and
    [string]$nandinaCreatures[0].difficultyClass -ceq [string]$contract.expected.creatureDifficulty -and
    [string]$gorvoCreatures[0].difficultyClass -ceq [string]$contract.expected.creatureDifficulty -and
    [string]$nandinaCreatures[0].primary_weapon_specials -ceq "heroic_axkva_nandina" -and
    [string]$gorvoCreatures[0].primary_weapon_specials -ceq "heroic_axkva_gorvo") `
    "p14.nandina.live-creature-definitions"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.nandina.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.nandina.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.nandina.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.nandina.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.nandina.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.nandina.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU Axkva Nandina healing authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU Axkva Nandina healing authority contract passed."
