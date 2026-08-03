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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuPlayerEquipmentLevelAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$scriptRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/script"
$objectRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/object/tangible/scout"
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

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.player-equipment.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.player-equipment.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$expectedTargets = @(
    "sku.0/sys.server/compiled/game/script/library/utils.java",
    "sku.0/sys.server/compiled/game/script/library/weapons.java",
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_weapon.java"
) | Sort-Object
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    ($targets -join "`n") -ceq ($expectedTargets -join "`n")) "p14.player-equipment.overlay.target-set"

$utilsPath = Join-Path $scriptRoot "library/utils.java"
$weaponsPath = Join-Path $scriptRoot "library/weapons.java"
$combatWeaponPath = Join-Path $scriptRoot "systems/combat/combat_weapon.java"
$sourceMap = [ordered]@{
    "script.library.utils" = $utilsPath
    "script.library.weapons" = $weaponsPath
    "script.systems.combat.combat_weapon" = $combatWeaponPath
}
foreach ($property in $sourceMap.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $property.Value -PathType Leaf) "p14.player-equipment.source.$($property.Key).exists"
    if (Test-Path -LiteralPath $property.Value -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $property.Value).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($property.Key)) `
            "p14.player-equipment.source.$($property.Key).authenticated"
    }
}

$utilsText = Get-Content -LiteralPath $utilsPath -Raw
$weaponsText = Get-Content -LiteralPath $weaponsPath -Raw
$combatWeaponText = Get-Content -LiteralPath $combatWeaponPath -Raw
$attributeSlice = Get-FunctionSlice $utilsText "public static int addClassRequirementAttributes(" "public static boolean testItemClassRequirements("
$levelSlice = Get-FunctionSlice $utilsText "public static boolean testItemLevelRequirements(" "public static boolean testItemAbilityRequirements("
$classSlice = Get-FunctionSlice $utilsText "public static boolean testItemClassRequirements(" "public static boolean testItemLevelRequirements("
$abilitySlice = Get-FunctionSlice $utilsText "public static boolean testItemAbilityRequirements(" "public static boolean hasAbility("
Assert-Contract ($levelSlice.Contains("return true;") -and
    -not $levelSlice.Contains("getLevel(") -and
    -not $levelSlice.Contains("levelRequired") -and
    -not $levelSlice.Contains('new string_id("spam", "levelrequired")')) `
    "p14.player-equipment.generic-level-admission.retired"
Assert-Contract (-not $attributeSlice.Contains("levelRequired") -and
    -not $attributeSlice.Contains('names[firstFree] = "levelrequired"')) `
    "p14.player-equipment.generic-level-presentation.retired"
Assert-Contract ($classSlice.Contains("requiredClasses") -and $classSlice.Contains("isProfession(") -and
    $abilitySlice.Contains("hasCommand(") -and $utilsText.Contains("testItemSkillRequirements(") -and
    $utilsText.Contains("hasSkill(player, skillRequired)")) `
    "p14.player-equipment.nonlevel-admission.preserved"

$levelHelperMatches = [regex]::Matches($utilsText + $weaponsText + $combatWeaponText, 'utils\.testItemLevelRequirements\(').Count
$allScriptMatches = 0
foreach ($file in Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
{
    $allScriptMatches += [regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), '(?<![A-Za-z0-9_])(?:utils\.)?testItemLevelRequirements\(').Count
}
$callSites = $allScriptMatches - 1
Assert-Contract ($levelHelperMatches -eq 0 -and $callSites -eq [int]$contract.expected.genericLevelHelperCallSitesPreserved) `
    "p14.player-equipment.generic-level-consumers.preserved"

$metadataFiles = @(Get-ChildItem -LiteralPath $objectRoot -Recurse -File -Filter "*.tpf" |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw).Contains("levelRequired") })
Assert-Contract ($metadataFiles.Count -eq [int]$contract.expected.retainedScoutMetadataFiles) `
    "p14.player-equipment.compatibility-metadata.preserved"

$rangeWrapper = Get-FunctionSlice $weaponsText "public static void adjustWeaponRangeForExpertise(" "public static void restorePrecuWeaponRange("
$rangeRestore = Get-FunctionSlice $weaponsText "public static void restorePrecuWeaponRange(" "public static float getWeaponMaxRange("
Assert-Contract ($rangeWrapper.Contains("restorePrecuWeaponRange(self);") -and
    -not $rangeWrapper.Contains("getSkillStatisticModifier") -and
    -not $rangeWrapper.Contains("expertise_range_bonus")) `
    "p14.player-equipment.expertise-range-authority.retired"
Assert-Contract ($rangeRestore.Contains('hasObjVar(self, "weapon.original_max_range")') -and
    $rangeRestore.Contains('getFloatObjVar(self, "weapon.original_max_range")') -and
    $rangeRestore.Contains("rangeData.maxRange = originalRange;") -and
    $rangeRestore.Contains("setWeaponRangeInfo(self, rangeData);") -and
    $rangeRestore.Contains("setWeaponData(self);")) `
    "p14.player-equipment.authored-range.restored"

$onInitialize = Get-FunctionSlice $combatWeaponText "public int OnInitialize(" "public int weaponConversion("
$conversion = Get-FunctionSlice $combatWeaponText "public int weaponConversion(" "public int OnAttach("
$transferred = Get-FunctionSlice $combatWeaponText "public int OnTransferred(" "public void retireNgeWeaponDamageSkillMods("
$damageRetirement = Get-FunctionSlice $combatWeaponText "public void retireNgeWeaponDamageSkillMods(" "public int OnGetAttributes("
Assert-Contract (-not $combatWeaponText.Contains("getLevel(") -and
    -not $combatWeaponText.Contains("PLAYER_ATTACKER_DAMAGE_LEVEL_MULTIPLIER") -and
    -not $combatWeaponText.Contains("PLAYER_COMBAT_BASE_DAMAGE") -and
    -not $combatWeaponText.Contains("setDamageSkillMods(")) `
    "p14.player-equipment.level-scaled-damage-authority.retired"
Assert-Contract ($damageRetirement.Contains('getSkillStatisticModifier(player, "minDamage")') -and
    $damageRetirement.Contains('applySkillStatisticModifier(player, "minDamage", 0 - oldMin)') -and
    $damageRetirement.Contains('getSkillStatisticModifier(player, "maxDamage")') -and
    $damageRetirement.Contains('applySkillStatisticModifier(player, "maxDamage", 0 - oldMax)') -and
    -not [regex]::IsMatch($damageRetirement, 'applySkillStatisticModifier\([^\r\n]+,\s*(?:minDamage|maxDamage)\s*\);')) `
    "p14.player-equipment.stale-damage-modifiers.retired"
Assert-Contract ($onInitialize.Contains("restorePrecuWeaponRange(self);") -and
    $onInitialize.Contains("retireNgeWeaponDamageSkillMods(owner);") -and
    $conversion.Contains("retireNgeWeaponDamageSkillMods(owner);") -and
    $transferred.Contains("restorePrecuWeaponRange(self);") -and
    ([regex]::Matches($transferred, 'retireNgeWeaponDamageSkillMods\(').Count -eq 2)) `
    "p14.player-equipment.cleanup-lifecycle.complete"
Assert-Contract (-not $combatWeaponText.Contains("expertiseRangeModify(")) `
    "p14.player-equipment.legacy-range-mutation.absent"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $missionPath = switch ($property.Name)
    {
        "mission_terminal.java" { Join-Path $scriptRoot "systems/missions/base/mission_terminal.java" }
        "mission_base.java" { Join-Path $scriptRoot "systems/missions/base/mission_base.java" }
        "missions.java" { Join-Path $scriptRoot "library/missions.java" }
    }
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $missionPath).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.player-equipment.mission-source.$($property.Name).unchanged"
}

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.player-equipment.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU player equipment level authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU player equipment level authority passed ($($targets.Count) sources, $callSites inert compatibility call sites, $($metadataFiles.Count) retained metadata files)."
