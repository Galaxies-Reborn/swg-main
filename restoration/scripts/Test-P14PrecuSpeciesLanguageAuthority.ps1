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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuSpeciesLanguageAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$serverGame = Join-Path $source "dsrc/sku.0/sys.server/compiled/game"
$sharedGame = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game"
$scriptRoot = Join-Path $serverGame "script"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$basePlayerPath = Join-Path $scriptRoot "player/base/base_player.java"
$speciesPath = Join-Path $scriptRoot "player/species_innate.java"
$skillPath = Join-Path $scriptRoot "library/skill.java"
$teachingPath = Join-Path $scriptRoot "player/skill/player_teaching.java"
$utilsPath = Join-Path $scriptRoot "library/utils.java"
$skillDataPath = Join-Path $sharedGame "datatables/skill/skills.tab"
foreach ($path in @($basePlayerPath, $speciesPath, $skillPath, $teachingPath,
    $utilsPath, $skillDataPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.species-language.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$species = Get-Content -LiteralPath $speciesPath -Raw
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $basePlayerPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."player/base/base_player.java") `
    "p14.species-language.base-player.authenticated"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $speciesPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."player/species_innate.java") `
    "p14.species-language.species-script.authenticated"

$initialize = Get-SourceSlice $basePlayer "public int OnInitialize(obj_id self)" `
    "public int handleRetireWarning"
Assert-Contract ($initialize.Length -gt 0 -and
    -not $initialize.Contains('grantSkill(self, "social_language_wookiee_comprehend")')) `
    "p14.species-language.universal-player-init-grant-retired"

$onAttach = Get-SourceSlice $species "public int OnAttach(obj_id self)" `
    "public int cmdInnate(obj_id self"
$expectedProperties = @($contract.expected.speciesDefaults.PSObject.Properties)
for ($i = 0; $i -lt $expectedProperties.Count; $i++)
{
    $property = $expectedProperties[$i]
    $startMarker = "case $($property.Name):"
    $endMarker = if ($i + 1 -lt $expectedProperties.Count) {
        "case $($expectedProperties[$i + 1].Name):"
    } else { "default:" }
    $caseSlice = Get-SourceSlice $onAttach $startMarker $endMarker
    $actual = @([regex]::Matches($caseSlice, 'grantSkill\(self, "([^"]+)"\)') |
        ForEach-Object { $_.Groups[1].Value })
    $expected = @($property.Value)
    Assert-Contract ($caseSlice.Length -gt 0 -and
        ($actual -join "`n") -ceq ($expected -join "`n")) `
        "p14.species-language.defaults.$($property.Name)"
}
Assert-Contract ([regex]::Matches($onAttach,
    'grantSkill\(self, "social_language_wookiee_comprehend"\)').Count -eq
    [int]$contract.diagnosis.expectedSpeciesAttachShyriiwookGrantSites) `
    "p14.species-language.only-wookiee-starts-with-shyriiwook"

$skillSource = Get-Content -LiteralPath $skillPath -Raw
$teachable = Get-SourceSlice $skillSource "public static String[] getTeachableSkills" `
    "public static String[] getQualifiedTeachableSkills"
Assert-Contract ($teachable.Length -gt 0 -and
    -not $teachable.Contains('social_language_wookiee_comprehend')) `
    "p14.species-language.wookiee-comprehension-remains-teachable"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillLibrarySha256) `
    "p14.species-language.skill-library-preserved"

$teachingSource = Get-Content -LiteralPath $teachingPath -Raw
Assert-Contract ($teachingSource.Contains("skill.getQualifiedTeachableSkills(target, self)") -and
    $teachingSource.Contains("skill.purchaseSkill(self, selected_skill)")) `
    "p14.species-language.player-teaching-authority-preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $teachingPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.playerTeachingSha256) `
    "p14.species-language.player-teaching-source-preserved"

$utilsSource = Get-Content -LiteralPath $utilsPath -Raw
Assert-Contract ($utilsSource.Contains('!hasSkill(player, "social_language_wookiee_comprehend")')) `
    "p14.species-language.ep3-language-condition-preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $utilsPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.wookieeLanguageUtilitySha256) `
    "p14.species-language.language-utility-preserved"

foreach ($property in $contract.continuityEvidence.ep3ConversationSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    $text = Get-Content -LiteralPath $path -Raw
    Assert-Contract ($text.Contains('grantSkill(player, "social_language_wookiee_comprehend")') -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.species-language.ep3.$($property.Name).preserved"
}

$skillRows = @(Import-SwgTab -Path $skillDataPath)
$wookieeComprehension = @($skillRows | Where-Object {
    [string]$_.NAME -ceq "social_language_wookiee_comprehend"
})
Assert-Contract ($wookieeComprehension.Count -eq 1 -and
    [string]$wookieeComprehension[0].SKILL_MODS -ceq "language_wookiee_comprehend=100") `
    "p14.species-language.skill-data-row-preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $skillDataPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillDataSha256) `
    "p14.species-language.skill-data-preserved"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.species-language.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.species-language.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) `
        "p14.species-language.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256."player/base/base_player.class" -cne "pending" -and
        [string]$contract.buildEvidence.compiledClassSha256."player/species_innate.class" -cne "pending" -and
        [string]$contract.buildEvidence.fullJavaCompile -like "passed*") `
        "p14.species-language.compiled-evidence"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.species-language.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.species-language.source-status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuSpeciesLanguageAuthority)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.species-language.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU species language authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU species language authority contract passed."
