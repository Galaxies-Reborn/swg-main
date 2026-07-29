param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$serverGame = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$scriptRoot = Join-Path $serverGame "script"

foreach ($contractName in @(
    "p14-life-day-2004-admission-restoration.json",
    "p14-life-day-2004-quest-state-machine.json",
    "p14-later-life-day-gcw-override-retirement.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required Life Day dependency is not ready: $contractName."
    }
}

$spaceCombatPath = Join-Path $scriptRoot "library/space_combat.java"
$spaceCombat = Get-Content -LiteralPath $spaceCombatPath -Raw
foreach ($retired in @("levelup_lifeday_orb", "enableLevelUpLoot"))
{
    if ($spaceCombat.Contains($retired))
    {
        throw "Post-era space-combat Life Day loot path remains: $retired."
    }
}
foreach ($retained in @(
    "int intRoll = rand(0, strColumns.length - 1)",
    "int intRoll2 = rand(0, strItems.length - 1)",
    "String itemTemplateName = strItems[intRoll2]",
    "attemptToGrantLootItem(itemTemplateName, objAttacker, objContainer)"
))
{
    if (-not $spaceCombat.Contains($retained))
    {
        throw "Ordinary space-combat loot selection drifted: $retained."
    }
}

$elder = Get-Content (Join-Path $scriptRoot "conversation/lifeday04b.java") -Raw
$levelUpTemplate = Join-Path $serverGame "object/tangible/loot/quest/levelup_lifeday_orb.tpf"
if (-not $elder.Contains("object/tangible/loot/quest/lifeday_orb.iff") -or
    -not (Test-Path -LiteralPath $levelUpTemplate))
{
    throw "Original reward orb or persisted level-up orb compatibility was not retained."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-life-day-level-up-loot-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.expected.spaceCombatLifeDayReferences -ne 0 -or
        -not $contract.expected.ordinaryLootTableSelectionRetained -or
        -not $contract.expected.original2004RewardOrbRetained -or
        -not $contract.expected.levelUpOrbTemplateRetainedForPersistedObjects -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Life Day level-up-loot retirement evidence is not ready."
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $spaceCombatPath).Hash.ToLowerInvariant()
    if ($actual -ne $contract.buildEvidence.sourceSha256."space_combat.java")
    {
        throw "Space-combat source evidence mismatch."
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/196-p14-life-day-level-up-loot-retirement.patch"
    $patchText = [IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"
    $patchBytes = [Text.Encoding]::UTF8.GetBytes($patchText)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $patchHash = ([BitConverter]::ToString($sha.ComputeHash($patchBytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($patchBytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $patchHash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Overlay evidence mismatch."
    }
}
Write-Host "Publish 14.1 Life Day level-up-loot retirement contract passed."
