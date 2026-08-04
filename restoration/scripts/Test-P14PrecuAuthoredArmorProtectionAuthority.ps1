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
    ([string]$manifest.contracts.p14PrecuAuthoredArmorProtectionAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
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
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$texts = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.authored-armor.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.authored-armor.source.$($property.Name).authenticated"
}

$armor = [string]$texts.armor
$combat = [string]$texts.combat
$mob = Get-SourceSlice $armor "public static void recalculateArmorForMob(" `
    "public static void recalculateArmorForPlayer("
$player = Get-SourceSlice $armor "public static void recalculateArmorForPlayer(" `
    "public static void recalculatePseudoArmorForPlayer("
$pseudo = Get-SourceSlice $armor "public static void recalculatePseudoArmorForPlayer(" `
    "public static String getPseudoArmorLevel("
$precuArmor = Get-SourceSlice $combat "public static int applyPrecuArmorProtection(" `
    "public static int applyPrecuCreatureArmorProtection("

Assert-Contract (-not $armor.Contains("expertise_") -and
    -not $armor.Contains('"elemental_resistance"')) `
    "p14.authored-armor.nge-protection-authority.retired"
Assert-Contract ($mob.Contains("getFloatObjVar(mob, OBJVAR_ARMOR_BASE") -and
    $mob.Contains("SCRIPTVAR_CACHED_GENERAL_PROTECTION") -and
    -not $mob.Contains("getSkillStatisticModifier")) `
    "p14.authored-armor.mob-authored-base"
Assert-Contract ($player.Contains('"chest2"') -and
    $player.Contains('"pants2"') -and
    $player.Contains("getArmorSpecialProtections(objArmor)") -and
    $player.Contains("combat.getArmorDecayPercentage(objArmor)") -and
    $player.Contains("fltSpecialProts[intJ] += fltWeight * fltSpecialProt") -and
    $player.Contains("fltGeneralProtection += fltWeight * fltArmorGeneralProtection") -and
    $player.Contains("applySkillStatisticModifier(objPlayer") -and
    $player.Contains('"armor.armor_set_worn"') -and
    $player.Contains('"armor.armor_type_tally"')) `
    "p14.authored-armor.weighted-piece-lifecycle.preserved"
Assert-Contract ($pseudo.Contains('"armor.general_protection_clothing"') -and
    $pseudo.Contains("if (applyArmor)") -and
    $pseudo.Contains("armorValue = intProtection") -and
    $pseudo.Contains("applySkillStatisticModifier(objPlayer") -and
    $pseudo.Contains("recalculateArmorForPlayer(objPlayer)")) `
    "p14.authored-armor.pseudo-armor.preserved"
Assert-Contract ($precuArmor.Contains("getPsgArmor(defender)") -and
    $precuArmor.IndexOf("getPsgArmor(defender)", [System.StringComparison]::Ordinal) -lt
        $precuArmor.IndexOf("getArmorPieceHit(defender, hitData.hitLocation)", [System.StringComparison]::Ordinal) -and
    $precuArmor.Contains("getPrecuArmorObjectProtection") -and
    $precuArmor.Contains("getPrecuArmorRating") -and
    $precuArmor.Contains("decayPrecuArmorPiece")) `
    "p14.authored-armor.precu-hit-location-path.preserved"

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$qualifiedCalls = 0
foreach ($path in [System.IO.Directory]::EnumerateFiles($scriptRoot, "*.java",
    [System.IO.SearchOption]::AllDirectories))
{
    $text = Get-Content -LiteralPath $path -Raw
    $qualifiedCalls += ([regex]::Matches($text,
        'armor\.recalculateArmorFor(?:Player|Mob)\(')).Count
}
Assert-Contract ($qualifiedCalls -eq
    [int]$contract.expected.qualifiedProductionRecalculationCallSites) `
    "p14.authored-armor.production-reachability"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.authored-armor.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.authored-armor.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.armor -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.combat -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.authored-armor.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.authored-armor.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.authored-armor.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU authored armor protection authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU authored armor protection authority contract passed."
