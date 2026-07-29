[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$skillPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/skill.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_skill_library_retirement_fixture.java"
$skill = Get-Content -LiteralPath $skillPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw

$statStart = $skill.IndexOf("public static int getPlayerStatForLevel")
$statEnd = $skill.IndexOf("public static void sendlevelUpStatChangeSystemMessages", $statStart)
$messageEnd = $skill.IndexOf("public static String getProfessionName", $statEnd)
$expertiseStart = $skill.IndexOf("public static boolean validateExpertise")
$expertiseEnd = $skill.LastIndexOf("`n}")
if ($statStart -lt 0 -or $statEnd -le $statStart -or
    $messageEnd -le $statEnd -or $expertiseStart -lt 0 -or
    $expertiseEnd -le $expertiseStart)
{
    throw "Could not isolate skill-library retirement surfaces."
}
$statSurface = $skill.Substring($statStart, $statEnd - $statStart)
$messageSurface = $skill.Substring($statEnd, $messageEnd - $statEnd)
$expertiseSurface = $skill.Substring($expertiseStart, $expertiseEnd - $expertiseStart)

foreach ($required in @(
    "14.1 HAM and secondary statistics are not derived from combat level.",
    "return 0;",
    "skill-box acquisition feedback",
    "resetExpertises(player);",
    "precuExpertiseRetirement:",
    "return false;"
))
{
    if (-not ($statSurface + $messageSurface + $expertiseSurface).Contains($required))
    {
        throw "Required Publish 14.1 retirement behavior is missing: $required"
    }
}
foreach ($retired in @(
    "getSkillTemplate(",
    "getPlayerLevelData(",
    "sendSystemMessageProse(",
    "utils.fullExpertiseReset(",
    "DATATABLE_EXPERTISE"
))
{
    if (($statSurface + $messageSurface + $expertiseSurface).Contains($retired))
    {
        throw "Later progression behavior remains on retired surfaces: $retired"
    }
}
foreach ($proof in @(
    "skill.validateExpertise(player)",
    'skill.getPlayerStatForLevel(player, 1, "health")',
    'skill.getPlayerStatForLevel(player, 90, "health")',
    'skill.getPlayerStatForLevel(player, 90, "luck")',
    "skill.sendlevelUpStatChangeSystemMessages(player, 89, 90)"
))
{
    if (-not $fixture.Contains($proof))
    {
        throw "Fixture proof is missing: $proof"
    }
}

if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-skill-library-progression-retirement.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in @{
        "skill.java" = $skillPath
        "precu_skill_library_retirement_fixture.java" = $fixturePath
    }.GetEnumerator())
    {
        $sourceBytes = [Text.Encoding]::UTF8.GetBytes(
            ([IO.File]::ReadAllText($entry.Value) -replace "`r`n", "`n"))
        $sourceSha = [Security.Cryptography.SHA256]::Create()
        try
        {
            $actual = ([BitConverter]::ToString(
                $sourceSha.ComputeHash($sourceBytes))).Replace(
                    "-", "").ToLowerInvariant()
        }
        finally
        {
            $sourceSha.Dispose()
        }
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/160-p14-skill-library-progression-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha.Dispose()
    }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $hash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 skill-library progression-retirement contract passed."
