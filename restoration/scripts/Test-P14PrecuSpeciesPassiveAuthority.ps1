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
    ([string]$manifest.contracts.p14PrecuSpeciesPassiveAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skills)
$squadLeaderPath = Join-Path $source ([string]$contract.sourceFiles.squadLeader)
$petLibraryPath = Join-Path $source ([string]$contract.sourceFiles.petLibrary)
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

foreach ($path in @($skillsPath, $squadLeaderPath, $petLibraryPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.species-passive.source.$([System.IO.Path]::GetFileName($path)).exists"
}
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $skillsPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256.skills) `
    "p14.species-passive.skills.authenticated"

$skillRows = @(Import-SwgTab -Path $skillsPath)
$expectedProperties = @($contract.expected.speciesModifiers.PSObject.Properties)
$speciesRows = @($skillRows | Where-Object {
    [string]$_.NAME -match '^species_(bothan|human|moncal|rodian|trandoshan|twilek|wookiee|zabrak|ithorian|sullustan)$'
})
Assert-Contract ($speciesRows.Count -eq $expectedProperties.Count -and $speciesRows.Count -eq 10) `
    "p14.species-passive.all-species-present"
$commonCommands = @($contract.expected.commonCommands | ForEach-Object { [string]$_ })
$activeInnates = @('regeneration', 'wookieeRoar', 'vitalize', 'equilibrium')
foreach ($property in $expectedProperties)
{
    $row = @($speciesRows | Where-Object { [string]$_.NAME -ceq $property.Name })
    $mods = if ($row.Count -eq 1) { @(Get-CommaValues $row[0].SKILL_MODS) } else { @() }
    $commands = if ($row.Count -eq 1) { @(Get-CommaValues $row[0].COMMANDS) } else { @() }
    $schematics = if ($row.Count -eq 1) { @(Get-CommaValues $row[0].SCHEMATICS_GRANTED) } else { @() }
    $expectedMods = @($property.Value | ForEach-Object { [string]$_ })
    $activeProperty = $contract.expected.activeInnateCommands.PSObject.Properties[$property.Name]
    $expectedActive = if ($null -ne $activeProperty) {
        @($activeProperty.Value | ForEach-Object { [string]$_ })
    } else { @() }
    $expectedCommands = @($expectedActive) + @($commonCommands)
    $expectedSchematics = if ($property.Name -ceq 'species_wookiee') {
        @($contract.expected.wookieeSchematics | ForEach-Object { [string]$_ })
    } else {
        @($contract.expected.otherSpeciesSchematics | ForEach-Object { [string]$_ })
    }
    Assert-Contract ($row.Count -eq 1 -and
        ($mods -join "`n") -ceq ($expectedMods -join "`n")) `
        "p14.species-passive.modifiers.$($property.Name)"
    Assert-Contract (($commands -join "`n") -ceq ($expectedCommands -join "`n") -and
        ($schematics -join "`n") -ceq ($expectedSchematics -join "`n")) `
        "p14.species-passive.preserved-surfaces.$($property.Name)"
}
Assert-Contract (@($speciesRows | Where-Object {
    [string]$_.COMMANDS -match '_ability_1' -or [string]$_.SKILL_MODS -match '_ability_1'
}).Count -eq [int]$contract.expected.ngeSpeciesAbilityGrants) `
    "p14.species-passive.no-nge-species-ability-grants"
Assert-Contract (@($speciesRows | Where-Object {
    [string]$_.COMMANDS -match 'creature_harvesting' -or [string]$_.SKILL_MODS -match 'creature_harvesting'
}).Count -eq [int]$contract.expected.speciesCreatureHarvestingGrants) `
    "p14.species-passive.novice-scout-harvesting-boundary"
$noviceScout = @($skillRows | Where-Object { [string]$_.NAME -ceq 'outdoors_scout_novice' })
Assert-Contract ($noviceScout.Count -eq 1 -and
    @(Get-CommaValues $noviceScout[0].COMMANDS) -ccontains [string]$contract.expected.noviceScoutHarvestCommand -and
    @(Get-CommaValues $noviceScout[0].SKILL_MODS) -ccontains [string]$contract.expected.noviceScoutHarvestingModifier) `
    "p14.species-passive.novice-scout-retains-harvesting"

$squadLeader = Get-Content -LiteralPath $squadLeaderPath -Raw
$petLibrary = Get-Content -LiteralPath $petLibraryPath -Raw
Assert-Contract ($squadLeader.Contains('getEnhancedSkillStatisticModifier(player, "leadership")')) `
    "p14.species-passive.leadership-runtime-consumer"
Assert-Contract ([regex]::Matches($petLibrary,
    'getEnhancedSkillStatisticModifier\(player, "tame_bonus"\)').Count -ge 4) `
    "p14.species-passive.tame-bonus-runtime-consumer"

if ($Expectation -eq 'Ready')
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq 'dsrc' })
    Assert-Contract ([string]$contract.status -ceq 'ready' -and
        [string]$contract.buildEvidence.result -ceq 'passed' -and
        [string]$contract.runtimeEvidence.result -ceq 'passed') `
        "p14.species-passive.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.species-passive.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledDataSha256.skills -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledDataPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.species-passive.live-evidence"
}
else
{
    Assert-Contract (@('implemented-build-pending', 'implemented-build-verified-live-pending', 'ready') -contains
        [string]$contract.status) "p14.species-passive.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains('/Artifacts/') -and
    -not $contractText.Contains('/Staging/')) "p14.species-passive.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU species passive authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU species passive authority contract passed."
