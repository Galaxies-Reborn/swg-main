[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$contractPath = Join-Path $restorationRoot "contracts/p14-profession-ownership-predicate.json"
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$utilsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/utils.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_profession_ownership_fixture.java"

foreach ($path in @($utilsPath, $fixturePath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required profession-ownership source is missing: $path"
    }
}

$utilsSource = Get-Content -LiteralPath $utilsPath -Raw
$methodStart = $utilsSource.IndexOf("public static boolean isProfession")
$methodEnd = $utilsSource.IndexOf("public static int getPlayerProfession", $methodStart)
if ($methodStart -lt 0 -or $methodEnd -le $methodStart)
{
    throw "Could not isolate utils.isProfession."
}
$predicate = $utilsSource.Substring($methodStart, $methodEnd - $methodStart)

if ($predicate.Contains("getSkillTemplate(") -or
    $predicate.Contains("professionName"))
{
    throw "NGE class-template classification remains in utils.isProfession."
}

foreach ($required in @(
    'return hasSkill(player, "combat_commando_novice");',
    'return hasSkill(player, "combat_smuggler_novice");',
    'return hasSkill(player, "science_medic_novice");',
    'return hasSkill(player, "outdoors_squadleader_novice");',
    'return hasSkill(player, "combat_bountyhunter_novice");',
    'return hasSkill(player, "crafting_artisan_novice");',
    'return hasSkill(player, "social_entertainer_novice");',
    "return isJediState(player, JEDI_STATE_FORCE_SENSITIVE);",
    "case SPY:",
    "default:"
))
{
    if (-not $predicate.Contains($required))
    {
        throw "Required Publish 14.1 profession predicate is missing: $required"
    }
}

$fixtureSource = Get-Content -LiteralPath $fixturePath -Raw
foreach ($required in @(
    "PLAYER_OID = 39008597L",
    "PLAYER_STATION_ID = 1001",
    "grantSkill(",
    "revokeSkill(",
    "setJediState(player, JEDI_STATE_NONE)",
    "setJediState(player, JEDI_STATE_FORCE_SENSITIVE)",
    "setJediState(player, JEDI_STATE_JEDI)",
    "restored="
))
{
    if (-not $fixtureSource.Contains($required))
    {
        throw "Reversible profession fixture evidence is missing: $required"
    }
}

if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    $expectedSources = $contract.buildEvidence.sourceSha256
    foreach ($entry in @{
        "utils.java" = $utilsPath
        "precu_profession_ownership_fixture.java" = $fixturePath
    }.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $expectedSources.($entry.Key))
        {
            throw "Canonical $($entry.Key) evidence mismatch."
        }
    }

    $patchPath = Join-Path $restorationRoot "patches/dsrc/151-p14-profession-ownership-predicate.patch"
    $patchText = [IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"
    $patchBytes = [Text.Encoding]::UTF8.GetBytes($patchText)
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        $patchHash = ([BitConverter]::ToString(
            $sha.ComputeHash($patchBytes))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha.Dispose()
    }
    if ($patchBytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $patchHash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Canonical overlay evidence mismatch."
    }
}

Write-Host "Publish 14.1 profession-ownership predicate contract passed."
