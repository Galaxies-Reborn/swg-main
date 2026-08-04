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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14NativePrecuPlayerDifficultyAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$cppPath = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
$headerPath = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/CreatureObject.h"
$basePlayerPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
$skillPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/skill.java"
$skillDataPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
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

foreach ($path in @($cppPath, $headerPath, $basePlayerPath, $skillPath, $skillDataPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.native-player-difficulty.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$cpp = Get-Content -LiteralPath $cppPath -Raw
$header = Get-Content -LiteralPath $headerPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$skill = Get-Content -LiteralPath $skillPath -Raw
$skillData = Get-Content -LiteralPath $skillDataPath -Raw

Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $cppPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."CreatureObject.cpp") `
    "p14.native-player-difficulty.creature-source.authenticated"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $headerPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."CreatureObject.h") `
    "p14.native-player-difficulty.creature-header.authenticated"

$helper = Get-BracedSurface $cpp "int getPreCuPlayerCombatDifficulty"
Assert-Contract ($helper.Length -gt 0 -and
    $helper.Contains('difficulty / 100 + 1') -and
    $helper.Contains('std::max(1, std::min(25,')) `
    "p14.native-player-difficulty.core3-formula"
foreach ($property in $contract.expected.weaponDifficultyMods.PSObject.Properties)
{
    $mapping = "case ServerWeaponObjectTemplate::$($property.Name):"
    Assert-Contract ($helper.Contains($mapping) -and $helper.Contains('difficultyMod = "' +
        [string]$property.Value + '"')) "p14.native-player-difficulty.weapon.$($property.Name)"
    Assert-Contract ($skillData.Contains([string]$property.Value)) `
        "p14.native-player-difficulty.skill-mod.$($property.Name).authored"
}
Assert-Contract ($helper.Contains('difficulty += player.getModValue("private_jedi_difficulty")') -and
    ([regex]::Matches($helper, 'jediWeapon = true').Count -eq 3)) `
    "p14.native-player-difficulty.jedi-mod-only-for-sabers"

Assert-Contract (-not $cpp.Contains("LevelManager::") -and
    -not $cpp.Contains('#include "sharedSkillSystem/LevelManager.h"')) `
    "p14.native-player-difficulty.nge-level-manager-retired"

$experience = Get-BracedSurface $cpp "const int CreatureObject::grantExperiencePoints"
Assert-Contract ($experience.Contains("playerObject->grantExperiencePoints(experienceType, amount)") -and
    $experience.Contains("setLevelData(0, 0, 0);") -and
    -not $experience.Contains("LevelManager")) `
    "p14.native-player-difficulty.named-xp-preserved-without-level-xp"

$grant = Get-BracedSurface $cpp "const bool CreatureObject::grantSkill"
$revoke = Get-BracedSurface $cpp "void CreatureObject::revokeSkill"
Assert-Contract ($grant.Contains("setLevelData(0, 0, 0);") -and
    $revoke.Contains("setLevelData(0, 0, 0);") -and
    -not $grant.Contains("LevelManager") -and -not $revoke.Contains("LevelManager")) `
    "p14.native-player-difficulty.skill-box-refresh"

$weapon = Get-BracedSurface $cpp "void CreatureObject::setCurrentWeapon"
Assert-Contract ($weapon.Contains("PlayerCreatureController::getPlayerObject(this) != nullptr") -and
    $weapon.Contains("setLevelData(0, 0, 0);")) `
    "p14.native-player-difficulty.weapon-change-refresh"

$setLevel = Get-BracedSurface $cpp "void CreatureObject::setLevel(int level)"
Assert-Contract ($setLevel.Contains("m_level = (int16) level;") -and
    $setLevel.Contains("setLevelData(0, 0, 0);") -and -not $setLevel.Contains("LevelManager")) `
    "p14.native-player-difficulty.player-force-rejected-npc-level-preserved"

$recalculate = Get-BracedSurface $cpp "void CreatureObject::recalculateLevel()"
Assert-Contract ($recalculate.Contains("setLevelData(0, 0, 0);") -and
    -not $recalculate.Contains("calculateLevelData") -and -not $recalculate.Contains("LevelManager")) `
    "p14.native-player-difficulty.recalculate-authority"

$levelData = Get-BracedSurface $cpp "void CreatureObject::setLevelData"
Assert-Contract ($levelData.Contains("getPreCuPlayerCombatDifficulty(*this)") -and
    $levelData.Contains("m_totalLevelXp = 0;") -and
    $levelData.Contains("m_levelHealthGranted = 0;") -and
    $levelData.Contains("m_level = preCuDifficulty;") -and
    $levelData.Contains("group->setMemberLevel(getNetworkId(), preCuDifficulty)")) `
    "p14.native-player-difficulty.zero-level-xp-health"

$fixup = Get-BracedSurface $cpp "void CreatureObject::fixupLevelXpAfterLoading()"
Assert-Contract ($fixup.Contains("getPreCuPlayerCombatDifficulty(*this)") -and
    $fixup.Contains("m_previousLevel      = preCuDifficulty;") -and
    $fixup.Contains("m_totalLevelXp       = 0;") -and
    $fixup.Contains("m_levelHealthGranted = 0;") -and
    -not $fixup.Contains("getExperiencePoints") -and -not $fixup.Contains("LevelManager")) `
    "p14.native-player-difficulty.load-fixup"

Assert-Contract ($header.Contains("Attributes::Health == attribute && !isPlayerControlled()")) `
    "p14.native-player-difficulty.player-health-hard-guard"

$initialize = Get-BracedSurface $basePlayer "public int OnInitialize(obj_id self)"
$levelChanged = Get-BracedSurface $basePlayer "public int OnCombatLevelChanged"
Assert-Contract ($initialize.Contains("recalculateLevel(self);") -and
    $levelChanged.Contains("recomputeCommandSeries(self);") -and
    -not $levelChanged.Contains("grantLevelSpecificRewards") -and
    -not $levelChanged.Contains("modifyMaxAttrib")) `
    "p14.native-player-difficulty.script-hook-safe"

$encounter = Get-BracedSurface $skill "public static int getPrecuEncounterDifficulty"
Assert-Contract ($encounter.Contains("getPrecuCombatSkillScore(player)")) `
    "p14.native-player-difficulty.retained-encounter-score-preserved"

Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $basePlayerPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.basePlayerSha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillLibrarySha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $skillDataPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillDataSha256) `
    "p14.native-player-difficulty.progression-continuity-authenticated"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $source ("dsrc/sku.0/sys.server/compiled/game/script/" + $property.Name)
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.native-player-difficulty.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.native-player-difficulty.ready-evidence"
    Assert-Contract ($srcPin.Count -eq 1 -and
        [string]$srcPin[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.native-player-difficulty.direct-source-pin"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.native-player-difficulty.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.native-player-difficulty.source-status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14NativePrecuPlayerDifficultyAuthority)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.native-player-difficulty.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "Native PRE-CU player difficulty authority failed: $($failures -join ', ')"
}
Write-Host "Native PRE-CU player difficulty authority contract passed."
