[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuDroidDeedCallAdmission)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch)
$droidPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/npc/pet_deed/droid_deed.java"
$petLibraryPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/pet_lib.java"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.droid-deed.overlay.exists"
Assert-Contract (Test-Path -LiteralPath $droidPath -PathType Leaf) "p14.droid-deed.source.exists"
Assert-Contract (Test-Path -LiteralPath $petLibraryPath -PathType Leaf) "p14.droid-deed.pet-library.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $sha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.droid-deed.overlay.authenticated"
}

$droid = Get-Content -LiteralPath $droidPath -Raw
$petLibrary = Get-Content -LiteralPath $petLibraryPath -Raw
$selectMethod = Get-FunctionSlice $droid `
    "public int OnObjectMenuSelect(" `
    "public obj_id createCraftedCreatureDevice("
$createMethod = Get-FunctionSlice $droid `
    "public obj_id createCraftedCreatureDevice(" `
    "public int"

Assert-Contract (-not [regex]::IsMatch($selectMethod, 'getLevel\s*\(\s*player\s*\)') -and
    -not $selectMethod.Contains("MAX_PET_LEVELS_ABOVE_CALLER") -and
    -not $selectMethod.Contains("SID_SYS_CANT_CALL_LEVEL") -and
    -not $petLibrary.Contains("MAX_PET_LEVELS_ABOVE_CALLER") -and
    -not $petLibrary.Contains("SID_SYS_CANT_CALL_LEVEL")) `
    "p14.droid-deed.nge-level-admission-zero"

Assert-Contract ($selectMethod.Contains("pet_lib.hasMaxStoredPetsOfType(player, petType)") -and
    $selectMethod.Contains("pet_lib.hasMaxPets(player, petType)")) `
    "p14.droid-deed.capacity-checks-preserved"
Assert-Contract ($selectMethod.Contains("createCraftedCreatureDevice(player, self)") -and
    $selectMethod.Contains("if (isIdValid(pet))") -and
    $selectMethod.Contains("destroyObject(self)")) `
    "p14.droid-deed.successful-conversion-lifecycle"
Assert-Contract ($createMethod.Contains("canManipulate(player, deed, true, true, 15, true)") -and
    $createMethod.Contains("utils.getPlayerDatapad(player)") -and
    $createMethod.Contains("createObject(controlTemplate, datapad")) `
    "p14.droid-deed.manipulation-and-datapad-revalidation"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.droid-deed.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU droid deed call admission failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU droid deed call admission passed."
