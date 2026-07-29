[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$contract = Get-Content (Join-Path $restorationRoot "contracts/p14-nge-inspiration-retirement.json") -Raw | ConvertFrom-Json
$root = (Resolve-Path $SourceRoot).Path
$performancePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/performance.java"
$pulsePaths = @(
    "active_music.java", "active_dance.java", "active_juggle.java"
) | ForEach-Object {
    Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/skills/performance/$_"
}
$performance = Get-Content $performancePath -Raw
$durationStart = $performance.IndexOf("public static float inspireGetMaxDuration")
$inspireStart = $performance.IndexOf("public static boolean inspire(", $durationStart)
$duration = $performance.Substring($durationStart, $inspireStart - $durationStart)
if (-not $duration.Contains("return 0.0f;") -or
    $duration.Contains("getSkillTemplate(") -or
    $duration.Contains("getPercentageCompletion("))
{
    throw "NGE inspiration duration remains active."
}
if (-not $performance.Contains("if (!isNgeInspirationEnabled())") -or
    -not $performance.Contains("private static boolean isNgeInspirationEnabled()") -or
    -not $performance.Contains("return false;"))
{
    throw "NGE inspiration does not fail closed."
}
$pulseText = ($pulsePaths | ForEach-Object {
    if (-not (Test-Path $_)) { throw "Missing performance pulse source: $_" }
    Get-Content $_ -Raw
}) -join "`n"
if ($pulseText.Contains("performance.inspire("))
{
    throw "An active performance pulse still invokes NGE inspiration."
}
if ([regex]::Matches($pulseText, "performance\.performanceHeal\(").Count -ne
    [int]$contract.expected.precuHealingCallsPreserved)
{
    throw "Authentic music/dance healing calls were not preserved."
}
if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/146-p14-nge-inspiration-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patch) -replace "`r`n","`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $hash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Canonical overlay evidence mismatch."
    }
}
Write-Host "Publish 14.1 NGE inspiration retirement contract passed."
