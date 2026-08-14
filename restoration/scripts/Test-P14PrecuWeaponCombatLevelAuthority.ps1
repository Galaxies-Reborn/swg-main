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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuWeaponCombatLevelAuthority)
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
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.weapon-combat-level.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $sha -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.weapon-combat-level.overlay.authenticated"
}

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$xpPath = Join-Path $scriptRoot "library/xp.java"
$combatBasePath = Join-Path $scriptRoot "systems/combat/combat_base.java"
$combatActionsPath = Join-Path $scriptRoot "systems/combat/combat_actions.java"
$skillsTablePath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"

foreach ($path in @($xpPath, $combatBasePath, $combatActionsPath, $skillsTablePath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.weapon-combat-level.source.$([IO.Path]::GetFileName($path)).exists"
}

$xp = Get-Content -LiteralPath $xpPath -Raw
$combatBase = Get-Content -LiteralPath $combatBasePath -Raw
$combatActions = Get-Content -LiteralPath $combatActionsPath -Raw

$sourceHashes = [ordered]@{
    "script.library.xp" = $xpPath
    "script.systems.combat.combat_base" = $combatBasePath
    "script.systems.combat.combat_actions" = $combatActionsPath
}
foreach ($name in $sourceHashes.Keys)
{
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHashes[$name]).Hash.ToLowerInvariant()
    Assert-Contract ($actualHash -ceq [string]$contract.buildEvidence.sourceSha256.$name) `
        "p14.weapon-combat-level.source.$name.authenticated"
}

$weaponLevel = Get-FunctionSlice $xp `
    "public static int getPrecuWeaponCombatLevel(" `
    "public static int getPrecuCombatLevel("
$objectLevel = Get-FunctionSlice $xp `
    "public static int getPrecuCombatLevel(" `
    "public static int getPrecuCombatXpDifficulty("
$xpDifficulty = Get-FunctionSlice $xp `
    "public static int getPrecuCombatXpDifficulty(" `
    "public static int capPrecuCombatXp("

Assert-Contract ($weaponLevel.Contains("getCurrentWeapon(player)") -and
    $weaponLevel.Contains("getWeaponType(weapon)") -and
    $weaponLevel.Contains("combat.getWeaponStringType(weaponType)") -and
    $weaponLevel.Contains('"private_" + weaponTypeName + "_combat_difficulty"') -and
    $weaponLevel.Contains("isJedi(player) && combat.isLightsaberWeapon(weaponType)") -and
    $weaponLevel.Contains('"private_jedi_difficulty"') -and
    $weaponLevel.Contains("Math.min(PRECU_COMBAT_XP_DIFFICULTY_CAP, (skillMod / 100) + 1)") -and
    -not $weaponLevel.Contains("getLevel(") -and
    -not $weaponLevel.Contains("getPrecuEncounterDifficulty")) `
    "p14.weapon-combat-level.core3-current-weapon-formula"

Assert-Contract (([regex]::Matches($weaponLevel, "return 0;")).Count -ge 3 -and
    $objectLevel.Contains("if (isPlayer(creature))") -and
    $objectLevel.Contains("return getPrecuWeaponCombatLevel(creature)") -and
    $objectLevel.Contains("return Math.max(0, getLevel(creature))")) `
    "p14.weapon-combat-level.player-npc-boundary"

Assert-Contract ($xpDifficulty.Contains('xpType == null || xpType.equals("") || xpType.equals(JEDI_GENERAL)') -and
    $xpDifficulty.Contains("return getPrecuWeaponCombatLevel(player)") -and
    $xpDifficulty.Contains('xpType.contains("onehand")') -and
    $xpDifficulty.Contains('xpType.contains("polearm")') -and
    $xpDifficulty.Contains('xpType.contains("twohand")') -and
    $xpDifficulty.Contains('xpType.contains("unarmed")') -and
    $xpDifficulty.Contains('xpType.contains("carbine")') -and
    $xpDifficulty.Contains('xpType.contains("pistol")') -and
    $xpDifficulty.Contains('xpType.contains("rifle")') -and
    -not $xpDifficulty.Contains("private_jedi_difficulty")) `
    "p14.weapon-combat-level.xp-overloads-converged"

$stateLevelPattern = 'xp\.getPrecuWeaponCombatLevel\(defender\)\s*-\s*5'
Assert-Contract (([regex]::Matches($combatBase, $stateLevelPattern)).Count -eq 4 -and
    -not [regex]::IsMatch($combatBase, 'getLevel\(defender\)\s*-\s*5')) `
    "p14.weapon-combat-level.state-application-routed"

$taunt = Get-FunctionSlice $combatActions `
    "public int taunt(obj_id self, obj_id target" `
    "public int precuTauntExpire("
Assert-Contract ($taunt.Contains("xp.getPrecuCombatLevel(self)") -and
    $taunt.Contains("xp.getPrecuCombatLevel(target)") -and
    $taunt.Contains("int levelCombine = Math.max(1, attackerLevel + targetLevel)") -and
    -not [regex]::IsMatch($taunt, 'getLevel\s*\(\s*(self|target)\s*\)')) `
    "p14.weapon-combat-level.taunt-routed"

$skills = Import-Csv -LiteralPath $skillsTablePath -Delimiter ([char]9)
$brawlerNovice = @($skills | Where-Object { $_.NAME -ceq "combat_brawler_novice" })[0]
$marksmanNovice = @($skills | Where-Object { $_.NAME -ceq "combat_marksman_novice" })[0]
$commandoNovice = @($skills | Where-Object { $_.NAME -ceq "combat_commando_novice" })[0]
$saberNovice = @($skills | Where-Object { $_.NAME -ceq "force_discipline_light_saber_novice" })[0]
Assert-Contract ($brawlerNovice.SKILL_MODS.Contains("private_unarmed_combat_difficulty=100") -and
    $marksmanNovice.SKILL_MODS.Contains("private_rifle_combat_difficulty=100") -and
    $commandoNovice.SKILL_MODS.Contains("private_heavyweapon_combat_difficulty=1700") -and
    $saberNovice.SKILL_MODS.Contains("private_onehandlightsaber_combat_difficulty=200")) `
    "p14.weapon-combat-level.authored-skillmods-present"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.weapon-combat-level.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU weapon combat-level authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU weapon combat-level authority passed."
