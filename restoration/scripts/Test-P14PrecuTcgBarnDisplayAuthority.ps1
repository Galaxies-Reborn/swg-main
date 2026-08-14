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
    ([string]$manifest.contracts.p14PrecuTcgBarnDisplayAuthority)
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
        "p14.tcg-barn.source.$([IO.Path]::GetFileName($path)).exists"
}

$tcg = Get-Content -LiteralPath $paths.tcgLibrary -Raw
$beastLibrary = Get-Content -LiteralPath $paths.beastLibrary -Raw
$beastControlDevice = Get-Content -LiteralPath $paths.beastControlDevice -Raw
$barnRanchhand = Get-Content -LiteralPath $paths.barnRanchhand -Raw
$barnLiteDevice = Get-Content -LiteralPath $paths.barnLiteDevice -Raw
$barnBeast = Get-Content -LiteralPath $paths.barnBeast -Raw
$display = Get-BracedBlock $tcg `
    "public static obj_id barnDisplayBeast(obj_id ranchhand, String storageSlot, obj_id barn, location where)"
$initialize = Get-BracedBlock $tcg `
    "public static void initializeBeastStatsFromBarn"
$showRoaming = Get-BracedBlock $tcg `
    "public static boolean showRoamingBeasts"
$displayAttributes = Get-BracedBlock $barnBeast `
    "public int OnGetAttributes"
$runtimeRetired = Get-BracedBlock $beastLibrary `
    "public static boolean isPostNgeBeastMasterPlayerRuntimeRetired"

Assert-Contract (-not $tcg.Contains("expertise_") -and
    -not $tcg.Contains("getExpertiseStat") -and
    -not $tcg.Contains("getExpertiseSpeed") -and
    -not $tcg.Contains("ATTENTION_PENALTY_DEBUFF") -and
    -not $tcg.Contains("buff.applyBuff")) `
    "p14.tcg-barn.nge-expertise-and-attention-authority-absent"

Assert-Contract ($initialize.Contains('utils.dataTableGetRow(beast_lib.BEASTS_STATS, level - 1)') -and
    $initialize.Contains('beastStatsDict.getInt("MinDmg")') -and
    $initialize.Contains('beastStatsDict.getInt("MaxDmg")') -and
    $initialize.Contains('float primarySpeed = beast_lib.BEAST_WEAPON_SPEED') -and
    $initialize.Contains('beastStatsDict.getInt("HP")') -and
    $initialize.Contains('beastStatsDict.getInt("HealthRegen")') -and
    $initialize.Contains('beastStatsDict.getInt("ActionRegen")') -and
    $initialize.Contains('beastStatsDict.getInt("Armor")')) `
    "p14.tcg-barn.authored-base-stat-path-preserved"
Assert-Contract ($initialize.Contains("OBJVAR_BEAST_INCUBATION_BONUSES") -and
    $initialize.Contains("OBJVAR_INCREASE_ARMOR") -and
    $initialize.Contains("OBJVAR_INCREASE_DPS") -and
    $initialize.Contains("OBJVAR_INCREASE_HEALTH") -and
    $initialize.Contains("incubationDamageBonus") -and
    $initialize.Contains("incubationHealthBonus") -and
    $initialize.Contains("incubationArmorBonus")) `
    "p14.tcg-barn.stored-incubation-bonuses-preserved"
Assert-Contract ($initialize.Contains('".beast.health"') -and
    $initialize.Contains("beast_lib.setBeastExperience(beast, exp)") -and
    $initialize.Contains("beast_lib.setBeastCanLevel(beast, canLevel)")) `
    "p14.tcg-barn.stored-state-preserved"

Assert-Contract ($display.Contains("createObject") -and
    $display.Contains("initializeBeastStatsFromBarn") -and
    $display.Contains("setAttributeAttained(beast, attrib.BEAST)") -and
    $display.Contains("attachScript(beast, BARN_BEAST_SCRIPT)") -and
    $display.Contains('attachScript(beast, "ai.ai")') -and
    $display.Contains("setInvulnerable(beast, true)") -and
    $display.Contains('setObjVar(beast, "noEject", true)')) `
    "p14.tcg-barn.cosmetic-display-lifecycle-preserved"
Assert-Contract (([regex]::Matches($showRoaming, '(?:tcg\.)?barnDisplayBeast\(')).Count -eq
        [int]$contract.expected.internalRoamingDisplayBranches) `
    "p14.tcg-barn.roaming-restoration-branches-preserved"
Assert-Contract ($barnRanchhand.Contains("tcg.barnDisplayBeast") -and
    $barnLiteDevice.Contains("tcg.barnDisplayBeast") -and
    [int]$contract.expected.directBarnDisplayCallers -eq 2) `
    "p14.tcg-barn.direct-display-callers-preserved"
Assert-Contract ($barnBeast.Contains("tcg.BEAST_ROAMING") -and
    $barnBeast.Contains("removeObjVar") -and
    $barnBeast.Contains("destroyObject(self)")) `
    "p14.tcg-barn.reclaim-and-pack-preserved"
Assert-Contract (-not $barnBeast.Contains("expertise_") -and
    -not $displayAttributes.Contains("getEnhancedSkillStatisticModifierUncapped") -and
    ([regex]::Matches($displayAttributes, 'getWeaponMinDamage\(')).Count -eq 2 -and
    ([regex]::Matches($displayAttributes, 'getWeaponMaxDamage\(')).Count -eq 2 -and
    $displayAttributes.Contains('names[idx] = "damage"') -and
    $displayAttributes.Contains('names[idx] = "attackspeed"') -and
    $displayAttributes.Contains('names[idx] = "basedps"')) `
    "p14.tcg-barn.displayed-damage-uses-initialized-weapon-values"

Assert-Contract ($runtimeRetired.Contains("return true") -and
    ([regex]::Matches($beastControlDevice, 'beast_lib\.isRetiredPostNgeBeastMasterPlayer\(player\)')).Count -eq 2) `
    "p14.tcg-barn.player-beast-master-runtime-remains-retired"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.tcg-barn.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.tcg-barn.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.tcg-barn.direct-source-pin"
    Assert-Contract (@($contract.buildEvidence.compiledClassSha256.PSObject.Properties |
        Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0 -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.tcg-barn.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.tcg-barn.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.tcg-barn.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU TCG barn-display authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU TCG barn-display authority contract passed."
