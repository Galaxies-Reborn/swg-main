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
    ([string]$manifest.contracts.p14PrecuSpaceReverseEngineeringAuthority)
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
        "p14.space-reverse.source.$([IO.Path]::GetFileName($path)).exists"
}

$analysis = Get-Content -LiteralPath $paths.analysisTool -Raw
$skills = Get-Content -LiteralPath $paths.skills -Raw
$genericTemplate = Get-Content -LiteralPath $paths.genericToolTemplate -Raw
$armorTemplate = Get-Content -LiteralPath $paths.armorToolTemplate -Raw
$levelBonus = Get-BracedBlock $analysis `
    "public float getLevelBonus(obj_id player, int level)"
$menuSelect = Get-BracedBlock $analysis `
    "public int OnObjectMenuSelect(obj_id self, obj_id player, int item)"
$receiveItem = Get-BracedBlock $analysis `
    "public int OnAboutToReceiveItem(obj_id self, obj_id srcContainer, obj_id transferer, obj_id item)"
$finish = Get-BracedBlock $analysis `
    "public void finishReverseEngineering"

Assert-Contract (-not $analysis.Contains("expertise_") -and
    -not $analysis.Contains("getReverseEngineeringExpertiseBonus") -and
    -not $analysis.Contains("getEnhancedSkillStatisticModifier")) `
    "p14.space-reverse.nge-expertise-authority-absent"

$expectedBands = @(
    @{ Condition = 'level == 1'; Value = 'fltBonus = 0.01f;' },
    @{ Condition = 'level == 2 || level == 3'; Value = 'fltBonus = 0.02f;' },
    @{ Condition = 'level == 4 || level == 5'; Value = 'fltBonus = 0.03f;' },
    @{ Condition = 'level == 6 || level == 7'; Value = 'fltBonus = 0.04f;' },
    @{ Condition = 'level == 8 || level == 9'; Value = 'fltBonus = 0.05f;' },
    @{ Condition = 'level == 10'; Value = 'fltBonus = 0.06f;' }
)
$bandsPresent = $levelBonus.Contains('float fltBonus = 0;') -and
    $levelBonus.Contains('return fltBonus;')
foreach ($band in $expectedBands)
{
    $bandsPresent = $bandsPresent -and
        $levelBonus.Contains([string]$band.Condition) -and
        $levelBonus.Contains([string]$band.Value)
}
Assert-Contract ($bandsPresent -and
    ([regex]::Matches($levelBonus, 'fltBonus = 0\.0[1-6]f;')).Count -eq 6 -and
    -not $levelBonus.Contains("expertise")) `
    "p14.space-reverse.authored-one-through-six-percent-curve"

Assert-Contract (([regex]::Matches($analysis,
    'public obj_id reverseEngineer(?:Armor|Booster|Capacitor|DroidInterface|Engine|Reactor|Shield|Weapon)\(')).Count -eq
    [int]$contract.expected.categoryOutputMethods) `
    "p14.space-reverse.eight-component-output-methods"
Assert-Contract (([regex]::Matches($analysis,
    'float fltBonus = getLevelBonus\(player, level\);')).Count -eq
    [int]$contract.expected.levelBonusCallSites) `
    "p14.space-reverse.all-output-methods-use-authored-curve"

$reverseModifiers = @("engineering_reverse", "propulsion_reverse", "systems_reverse", "defense_reverse")
$modifierAuthority = $skills.Contains("crafting_shipwright_novice") -and
    $skills.Contains("crafting_shipwright_master")
foreach ($modifier in $reverseModifiers)
{
    $modifierAuthority = $modifierAuthority -and
        $skills.Contains($modifier) -and
        $analysis.Contains('getSkillStatisticModifier(player, "' + $modifier + '")')
}
Assert-Contract ($modifierAuthority -and $reverseModifiers.Count -eq
    [int]$contract.expected.shipwrightReverseModifiers) `
    "p14.space-reverse.precu-shipwright-reverse-modifiers-preserved"

Assert-Contract ($receiveItem.Contains("SCF_reverse_engineered") -and
    $receiveItem.Contains("getShipComponentStringType") -and
    ([regex]::Matches($receiveItem, 'getReverseEngineeringLevel\(')).Count -ge 2 -and
    $menuSelect.Contains("level > toolContents.length") -and
    $menuSelect.Contains("level < toolContents.length") -and
    $menuSelect.Contains("switch (componentType)")) `
    "p14.space-reverse.component-type-level-and-count-admission-preserved"
Assert-Contract (([regex]::Matches($menuSelect,
    'flags \|= ship_component_flags\.SCF_reverse_engineered;')).Count -eq
    [int]$contract.expected.reverseEngineeredFlagAssignments -and
    ([regex]::Matches($menuSelect,
    'setObjVar\(self, "reverse_engineering\.charges", charges\);')).Count -eq 8 -and
    $menuSelect.Contains("charges--") -and
    $menuSelect.Contains("if (charges <= 0)")) `
    "p14.space-reverse.charges-and-output-flags-preserved"
Assert-Contract ($finish.Contains("destroyObject(objComponent)") -and
    $menuSelect.Contains("calculateFiresprayGrant") -and
    $menuSelect.Contains('"firespray_schematic"') -and
    $analysis.Contains("public obj_id createLegendaryLoot")) `
    "p14.space-reverse.source-consumption-firespray-and-legendary-paths-preserved"

Assert-Contract ($genericTemplate.Contains('"space.crafting.analysis_tool"') -and
    $armorTemplate.Contains('"space.crafting.analysis_tool"') -and
    [int]$contract.expected.liveToolTemplates -eq 2) `
    "p14.space-reverse.live-analysis-tool-template-bindings"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.space-reverse.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.space-reverse.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.space-reverse.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.space-reverse.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.space-reverse.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.space-reverse.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU space reverse-engineering authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU space reverse-engineering authority contract passed."
