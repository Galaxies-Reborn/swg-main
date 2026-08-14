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
    ([string]$manifest.contracts.p14PrecuLightsaberCrystalItemLevelAuthority)
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

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.crystal-item-level.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$component = Get-Content -LiteralPath $paths.saberComponent -Raw
$jedi = Get-Content -LiteralPath $paths.jediLibrary -Raw
$saberBase = Get-Content -LiteralPath $paths.saberBase -Raw
$attach = Get-BracedSurface $component "public int OnAttach(obj_id self)"
$handler = Get-BracedSurface $component "public int setCrystalLevel(obj_id self, dictionary params)"
$initializer = Get-BracedSurface $component "public void initializePrecuCrystal(obj_id self)"
$jediInitializer = Get-BracedSurface $jedi "public static void initializeCrystal(obj_id crystal, int level)"

Assert-Contract ($attach.Contains("messageTo(self, `"setCrystalLevel`", data, 0.5f, false)") -and
    -not $attach.Contains("jedi.initializeCrystal") -and
    -not $attach.Contains("getContainedBy")) `
    "p14.crystal-item-level.creator-metadata-window"
Assert-Contract ($handler.Contains("static_item.isStaticItem(self)") -and
    $handler.Contains("isIdValid(inv)") -and
    $handler.Contains("initializePrecuCrystal(self)") -and
    $handler.Contains('params.put("attempts", attempts)') -and
    -not $handler.Contains("getContainedBy(inv)")) `
    "p14.crystal-item-level.containment-retry-without-owner-traversal"
Assert-Contract ($initializer.Contains("rand(1, 50)") -and
    $initializer.Contains('jedi.VAR_CRYSTAL_STATS + "." + jedi.VAR_LEVEL') -and
    $initializer.Contains("hasObjVar(self, levelObjVar)") -and
    $initializer.Contains("getIntObjVar(self, levelObjVar)") -and
    $initializer.Contains("jedi.initializeCrystal(self, crystalLevel)")) `
    "p14.crystal-item-level.authored-item-level-and-legacy-fallback"
Assert-Contract (-not $component.Contains("getLevel(") -and
    -not $component.Contains("getCreatureName(") -and
    -not $component.Contains("Inventory contained by")) `
    "p14.crystal-item-level.no-player-level-authority"
Assert-Contract ([regex]::Matches($component,
    [regex]::Escape("jedi.canTuneLightsaberCrystal(player)")).Count -eq
    [int]$contract.expected.crystalTuningCallSites) `
    "p14.crystal-item-level.tuning-gates-preserved"
Assert-Contract ($jediInitializer.Contains("hasObjVar(crystal, VAR_CRYSTAL_STATS + `".`" + VAR_LEVEL)") -and
    $jediInitializer.Contains("getIntObjVar(crystal, VAR_CRYSTAL_STATS + `".`" + VAR_LEVEL)")) `
    "p14.crystal-item-level.library-preserves-authored-level"

$createPearl = $saberBase.IndexOf(
    'createObject("object/tangible/component/weapon/lightsaber/lightsaber_module_krayt_dragon_pearl.iff"',
    [StringComparison]::Ordinal)
$authorPearl = $saberBase.IndexOf(
    'setObjVar(pearl, jedi.VAR_CRYSTAL_STATS + "." + jedi.VAR_LEVEL, pearlLevel)',
    [StringComparison]::Ordinal)
Assert-Contract ($createPearl -ge 0 -and $authorPearl -gt $createPearl) `
    "p14.crystal-item-level.legacy-creator-authors-level-after-create"

$masterItems = @(Import-Csv -LiteralPath $paths.masterItems -Delimiter "`t")
$itemStats = @(Import-Csv -LiteralPath $paths.itemStats -Delimiter "`t")
$families = [ordered]@{
    krayt = '^item_krayt_pearl_04_'
    power = '^item_power_crystal_04_'
    color = '^item_color_crystal_02_'
}
$expectedCounts = [ordered]@{
    krayt = [int]$contract.diagnosis.staticKraytPearlRows
    power = [int]$contract.diagnosis.staticPowerCrystalRows
    color = [int]$contract.diagnosis.staticColorCrystalRows
}
foreach ($family in $families.Keys)
{
    $masterRows = @($masterItems | Where-Object { $_.name -match $families[$family] })
    $statRows = @($itemStats | Where-Object { $_.name -match $families[$family] })
    Assert-Contract ($masterRows.Count -eq $expectedCounts[$family] -and
        @($masterRows | Where-Object {
            $_.scripts -notmatch '(^|,)systems\.jedi\.jedi_saber_component(,|$)'
        }).Count -eq 0 -and
        $statRows.Count -eq $expectedCounts[$family] -and
        @($statRows | Where-Object {
            $_.objvars -notmatch 'int:jedi\.crystal\.stats\.level=-1'
        }).Count -eq 0) "p14.crystal-item-level.static-$family-authorship"
}

$ranges = @(Import-Csv -LiteralPath $paths.componentRanges -Delimiter "`t")
Assert-Contract (@($ranges | Where-Object {
    $_.strTemplateName -match 'lightsaber_module_(force_crystal|krayt_dragon_pearl)\.iff$'
}).Count -eq 2) "p14.crystal-item-level.retained-legacy-range-data"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths.saberComponent).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.crystal-item-level.$($property.Name).authenticated"
}
$continuity = [ordered]@{
    jediLibrarySha256 = $paths.jediLibrary
    saberBaseSha256 = $paths.saberBase
    componentRangesSha256 = $paths.componentRanges
    masterItemsSha256 = $paths.masterItems
    itemStatsSha256 = $paths.itemStats
}
foreach ($name in $continuity.Keys)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $continuity[$name]).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.$name) "p14.crystal-item-level.continuity.$name"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.crystal-item-level.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.crystal-item-level.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.crystal-item-level.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.crystal-item-level.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.crystal-item-level.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU lightsaber crystal item-level authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU lightsaber crystal item-level authority contract passed."
