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
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14NativeNgePlayerLevelServiceRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$setupPath = Join-Path $source "src/engine/server/library/serverGame/src/shared/core/SetupServerGame.cpp"
$expertisePath = Join-Path $source "src/engine/shared/library/sharedSkillSystem/src/shared/ExpertiseManager.cpp"
$levelPath = Join-Path $source "src/engine/shared/library/sharedSkillSystem/src/shared/LevelManager.cpp"
$creaturePath = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
$creatureHeaderPath = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/CreatureObject.h"
$playerLevelPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/player/player_level.tab"
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

foreach ($path in @($setupPath, $expertisePath, $levelPath, $creaturePath,
    $creatureHeaderPath, $playerLevelPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.native-level-service.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$setup = Get-Content -LiteralPath $setupPath -Raw
$expertise = Get-Content -LiteralPath $expertisePath -Raw
$level = Get-Content -LiteralPath $levelPath -Raw
$creature = Get-Content -LiteralPath $creaturePath -Raw

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    $path = switch ($property.Name)
    {
        "SetupServerGame.cpp" { $setupPath }
        "ExpertiseManager.cpp" { $expertisePath }
        "LevelManager.cpp" { $levelPath }
        default { "" }
    }
    Assert-Contract ($path -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) "p14.native-level-service.$($property.Name).authenticated"
}

$setupInstall = Get-BracedSurface $setup "void SetupServerGame::install()"
Assert-Contract ($setupInstall.Length -gt 0 -and
    -not $setup.Contains('#include "sharedSkillSystem/LevelManager.h"') -and
    -not $setupInstall.Contains("LevelManager::install()")) `
    "p14.native-level-service.level-manager-startup-retired"

$externalLevelConsumers = [System.Collections.Generic.List[string]]::new()
$nativeCppRoot = Join-Path $source "src/engine"
foreach ($file in Get-ChildItem -LiteralPath $nativeCppRoot -Recurse -File -Filter "*.cpp")
{
    if ($file.FullName -ceq $levelPath) { continue }
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if ($text.Contains("LevelManager::") -or
        $text.Contains('#include "sharedSkillSystem/LevelManager.h"'))
    {
        $externalLevelConsumers.Add($file.FullName)
    }
}
Assert-Contract ($externalLevelConsumers.Count -eq
    [int]$contract.diagnosis.nativeLevelManagerExternalConsumersAfter) `
    "p14.native-level-service.no-external-level-manager-consumers"

Assert-Contract ($level.Contains("void LevelManager::install()") -and
    $level.Contains('datatables/player/player_level.iff')) `
    "p14.native-level-service.dormant-link-compatibility-preserved"

$expertiseInstall = Get-BracedSurface $expertise "void ExpertiseManager::install()"
$expertisePoints = Get-BracedSurface $expertise "int ExpertiseManager::getExpertisePointsForLevel"
Assert-Contract (-not $expertise.Contains('datatables/player/player_level.iff') -and
    -not $expertise.Contains("loadExpertisePointsTable") -and
    -not $expertise.Contains("LevelToPointsMap") -and
    -not $expertise.Contains("s_expertisePointsForLevel")) `
    "p14.native-level-service.expertise-level-table-retired"
Assert-Contract ($expertisePoints.Contains("UNREF(level);") -and
    $expertisePoints.Contains("compatibility symbol inert") -and
    $expertisePoints.Contains("return 0;")) `
    "p14.native-level-service.expertise-points-inert"
foreach ($metadataLoader in @("loadSkillTemplateTable", "loadExpertiseTreesTable", "loadExpertiseTable"))
{
    Assert-Contract ($expertiseInstall.Contains("$metadataLoader(cs_unusedDataTable)") -and
        $expertiseInstall.Contains("&$metadataLoader")) `
        "p14.native-level-service.cleanup-metadata.$metadataLoader.preserved"
}

$remainingExpertise = Get-BracedSurface $creature "int CreatureObject::getRemainingExpertisePoints() const"
$expertiseRequest = Get-BracedSurface $creature "bool CreatureObject::processExpertiseRequest"
Assert-Contract ($remainingExpertise.Contains("return 0;") -and
    $expertiseRequest.Contains("Rejected retired NGE expertise request") -and
    $expertiseRequest.Contains("return false;") -and
    $creature.Contains("bool CreatureObject::clearAllExpertises()")) `
    "p14.native-level-service.expertise-admission-and-cleanup-boundary"

Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $playerLevelPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.playerLevelDataSha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $creaturePath).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.creatureObjectSha256 -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $creatureHeaderPath).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.creatureObjectHeaderSha256) `
    "p14.native-level-service.progression-and-retained-data-continuity"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $source ("dsrc/sku.0/sys.server/compiled/game/script/" + $property.Name)
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.native-level-service.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.native-level-service.ready-evidence"
    Assert-Contract ($srcPin.Count -eq 1 -and
        [string]$srcPin[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.native-level-service.direct-source-pin"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.native-level-service.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.native-level-service.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.native-level-service.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "Native NGE player-level service retirement failed: $($failures -join ', ')"
}
Write-Host "Native NGE player-level service retirement contract passed."
