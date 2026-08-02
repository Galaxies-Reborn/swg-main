[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuPetControlAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
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

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$petLibraryPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/pet_lib.java"
$pcdPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/ai/pet_control_device.java"
$skillsPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$patchPath = Join-Path (Split-Path -Parent $restorationRoot) ([string]$contract.buildEvidence.overlayPatch)

Assert-Contract (Test-Path -LiteralPath $petLibraryPath -PathType Leaf) "p14.pet-control.source.pet-library"
Assert-Contract (Test-Path -LiteralPath $pcdPath -PathType Leaf) "p14.pet-control.source.pcd"
Assert-Contract (Test-Path -LiteralPath $skillsPath -PathType Leaf) "p14.pet-control.source.skills"
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.pet-control.overlay.exists"

$patchBytes = (Get-Item -LiteralPath $patchPath).Length
$patchSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
Assert-Contract ($patchBytes -eq [long]$contract.buildEvidence.overlayPatchBytes -and
    $patchSha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
    "p14.pet-control.overlay.authenticated"

$petLibrary = Get-Content -LiteralPath $petLibraryPath -Raw
$pcd = Get-Content -LiteralPath $pcdPath -Raw
$controlHelper = Get-FunctionSlice $petLibrary `
    "public static boolean canCallCreaturePet(" `
    "public static boolean canControlPetsOfLevel("
$maxTame = Get-FunctionSlice $petLibrary `
    "public static int getMaxTameLevel(" `
    "public static int getModifiedAttribDamage("
$callAdmission = Get-FunctionSlice $pcd `
    "if (item == menu_info_types.PET_CALL)" `
    "else if (item == menu_info_types.SERVER_HEAL_WOUND)"

Assert-Contract ($maxTame.Contains('getSkillStatMod(player, "tame_level")') -and
    $maxTame.Contains("Math.max(0,") -and
    -not $maxTame.Contains("getLevel(") -and
    -not $maxTame.Contains("tame_level_bonus")) `
    "p14.pet-control.tame-level-skill-authority"

Assert-Contract ($controlHelper.Contains("MAX_NONCH_PET_LEVEL") -and
    $controlHelper.Contains('hasSkill(player, "outdoors_creaturehandler_novice")') -and
    $controlHelper.Contains('getSkillStatMod(player, "tame_aggro")') -and
    $controlHelper.Contains("getCurrentPetLevels(player) + petLevel") -and
    $controlHelper.Contains('"control_exceeded"') -and
    $controlHelper.Contains('"lack_skill"')) `
    "p14.pet-control.call-helper-precu-rules"

Assert-Contract ($controlHelper.Contains("petType != PET_TYPE_NON_AGGRO && petType != PET_TYPE_AGGRO") -and
    $controlHelper.Contains("return true;")) `
    "p14.pet-control.non-creature-call-types-preserved"

Assert-Contract ($callAdmission.Contains("pet_lib.canCallCreaturePet") -and
    $callAdmission.Contains("pet_lib.getPetType(petObjVar)") -and
    $callAdmission.Contains("!isGod(player)") -and
    -not $callAdmission.Contains("getLevel(player)") -and
    -not $callAdmission.Contains("MAX_PET_LEVELS_ABOVE_CALLER") -and
    -not $callAdmission.Contains("SID_SYS_CANT_CALL_LEVEL")) `
    "p14.pet-control.pcd-admission-routed"

Assert-Contract ($callAdmission.Contains("pet_lib.isInValidUnpackLocation") -and
    $callAdmission.Contains("validatePetStats") -and
    $callAdmission.Contains("petIsDead") -and
    $callAdmission.Contains("pet_lib.hasMaxPets") -and
    $callAdmission.Contains("isSameFaction") -and
    $callAdmission.Contains('messageTo(self, "delayCreatePet"')) `
    "p14.pet-control.call-lifecycle-preserved"

Assert-Contract (-not $petLibrary.Contains("MAX_PET_LEVELS_ABOVE_CALLER") -and
    -not $petLibrary.Contains("SID_SYS_CANT_CALL_LEVEL") -and
    -not $petLibrary.Contains("tame_level_bonus") -and
    -not [regex]::IsMatch($petLibrary + "`n" + $pcd, 'getLevel\s*\((player|master)\)')) `
    "p14.pet-control.nge-owner-level-surface-zero"

$creatureHandlerRows = @(Get-Content -LiteralPath $skillsPath | Where-Object {
    $_ -match '^outdoors_creaturehandler_(novice|master|taming_\d\d|training_\d\d|healing_\d\d|support_\d\d)\t'
})
$controlTotal = 0
$allRowsHaveControl = $creatureHandlerRows.Count -eq 18
foreach ($row in $creatureHandlerRows)
{
    $match = [regex]::Match($row, '(?:^|,)tame_level=(\d+)(?:,|"|$)')
    if (-not $match.Success)
    {
        $allRowsHaveControl = $false
        continue
    }
    $controlTotal += [int]$match.Groups[1].Value
}
Assert-Contract ($allRowsHaveControl -and $controlTotal -eq 70 -and
    ($creatureHandlerRows -join "`n").Contains("tame_level=12")) `
    "p14.pet-control.skill-table-control-70"

function Test-ControlModel(
    [bool]$CreatureHandler,
    [bool]$Aggressive,
    [int]$PetLevel,
    [int]$CurrentLevels,
    [int]$TameLevel,
    [int]$TameAggro)
{
    $maximum = if ($CreatureHandler) { $TameLevel } else { 10 }
    if ($PetLevel -gt $maximum) { return $false }
    if ($Aggressive -and (-not $CreatureHandler -or $TameAggro -le 0)) { return $false }
    return ($CurrentLevels + $PetLevel) -le $maximum
}

Assert-Contract ((Test-ControlModel $false $false 10 0 0 0) -and
    -not (Test-ControlModel $false $false 11 0 0 0) -and
    -not (Test-ControlModel $false $true 5 0 0 0) -and
    (Test-ControlModel $true $false 12 0 12 0) -and
    -not (Test-ControlModel $true $false 13 0 12 0) -and
    -not (Test-ControlModel $true $true 10 0 12 0) -and
    (Test-ControlModel $true $true 10 0 12 10) -and
    -not (Test-ControlModel $true $false 7 6 12 0)) `
    "p14.pet-control.control-model-matrix"

Assert-Contract (([string]$contract.status -ceq "implemented-build-pending" -or
    [string]$contract.status -ceq "ready") -and
    [int]$contract.expected.nonCreatureHandlerDocilePetCap -eq 10 -and
    [int]$contract.expected.creatureHandlerMasterControlLevel -eq 70) `
    "p14.pet-control.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU pet-control authority failed: $($failures -join ', ')"
}

Write-Host "Publish 14 PRE-CU pet-control authority passed."
