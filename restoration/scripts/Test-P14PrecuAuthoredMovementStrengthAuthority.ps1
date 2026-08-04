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
    ([string]$manifest.contracts.p14PrecuAuthoredMovementStrengthAuthority)
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
        "p14.authored-movement.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.authored-movement.source.$($property.Name).authenticated"
}

$attributes = [string]$texts.attributes
Assert-Contract ($attributes.Contains('script/library/movement.java -text whitespace=cr-at-eol')) `
    "p14.authored-movement.no-line-ending-bloat-policy"

$movement = [string]$texts.movement
$apply = Get-SourceSlice $movement "public static boolean applyMovementModifier(obj_id target, String name, float strength)" `
    "public static boolean removeMovementModifier(obj_id target, String name)"
$current = Get-SourceSlice $movement "public static float getCurrentStrength(obj_id target, String name)" `
    "public static boolean isValidModifier(String name)"
Assert-Contract (-not $movement.Contains("expertise_movement_buff_") -and
    -not $apply.Contains("getSkillStatisticModifier")) `
    "p14.authored-movement.nge-expertise.retired"
Assert-Contract ($apply.Contains("if (strength == -1)") -and
    $apply.Contains("customStr = false;") -and
    $apply.Contains("strength = getStrength(name);") -and
    $apply.Contains('MOVEMENT_OBJVAR + "." + name + ".time"') -and
    $apply.Contains("if (customStr)") -and
    $apply.Contains('MOVEMENT_OBJVAR + "." + name + ".strength"') -and
    $apply.Contains("return refresh(target);")) `
    "p14.authored-movement.table-and-explicit-strength.preserved"
Assert-Contract ($movement.Contains("canApplyMovementModifier(target, name)") -and
    $movement.Contains("checkForMovementImmunity(target, name)") -and
    $movement.Contains("removeMovementModifier") -and
    $movement.Contains("removeAllModifiersOfType") -and
    $movement.Contains("_recalculateMovementModifiers(target)")) `
    "p14.authored-movement.lifecycle.preserved"
Assert-Contract ($current.Contains("hasObjVar") -and $current.Contains("hasScriptVar") -and
    $current.Contains("return getStrength(name);")) `
    "p14.authored-movement.current-strength.precedence"

$table = [string]$texts.movementTable
Assert-Contract ($table.Contains("burstRun`tboost`t75") -and
    $table.Contains("retreat`tboost`t82.2") -and
    $table.Contains("fs_force_run`tboost`t125")) `
    "p14.authored-movement.table.examples"

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$consumerText = ((Get-Content -LiteralPath (Join-Path $scriptRoot "player/base/base_player.java") -Raw) +
    (Get-Content -LiteralPath (Join-Path $scriptRoot "systems/buff/buff_handler.java") -Raw))
$directCalls = ([regex]::Matches($consumerText, 'movement\.applyMovementModifier\(')).Count
Assert-Contract ($directCalls -eq [int]$contract.expected.productionDirectCallSites -and
    $consumerText.Contains('PRECU_RETREAT_MODIFIER = "retreat"')) `
    "p14.authored-movement.production-reachability"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.authored-movement.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.authored-movement.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.movement -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.authored-movement.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.authored-movement.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.authored-movement.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU authored movement strength authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU authored movement strength authority contract passed."
