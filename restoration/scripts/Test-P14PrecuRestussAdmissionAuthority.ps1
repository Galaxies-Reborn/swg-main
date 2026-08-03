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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuRestussAdmissionAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$basePlayerPath = Join-Path $scriptRoot "player/base/base_player.java"
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.restuss-admission.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.restuss-admission.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$expectedTarget = "sku.0/sys.server/compiled/game/script/player/base/base_player.java"
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    $targets[0] -ceq $expectedTarget) "p14.restuss-admission.overlay.target-set"
Assert-Contract ((Get-TextSha256 (($targets -join "`n") + "`n")) -ceq
    [string]$contract.buildEvidence.sourceSetSha256) "p14.restuss-admission.source-set.authenticated"

Assert-Contract (Test-Path -LiteralPath $basePlayerPath -PathType Leaf) "p14.restuss-admission.source.exists"
$basePlayerText = Get-Content -LiteralPath $basePlayerPath -Raw
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $basePlayerPath).Hash.ToLowerInvariant()
Assert-Contract ($sourceHash -ceq [string]$contract.buildEvidence.sourceSha256.'script.player.base.base_player') `
    "p14.restuss-admission.source.authenticated"
$contentRecord = "$expectedTarget=$sourceHash`n"
Assert-Contract ((Get-TextSha256 $contentRecord) -ceq [string]$contract.buildEvidence.sourceContentSha256) `
    "p14.restuss-admission.source-content.authenticated"

$restussBody = Get-SourceSlice $basePlayerText `
    "if (regionName.equals(restuss_event.PVP_REGION_NAME))" `
    "else if (regionName.startsWith(gcw.PVP_BATTLEFIELD_REGION))"
$enterMethod = Get-SourceSlice $basePlayerText `
    "public int OnEnterRegion" `
    "public int OnExitRegion"
Assert-Contract (([regex]::Matches($restussBody, 'skill\.getPrecuEncounterDifficulty\(self\)')).Count -eq
        [int]$contract.expected.restussEncounterDifficultyCalls -and
    -not $restussBody.Contains("getLevel(self)") -and
    $restussBody.Contains("precuCombatDifficulty < 75")) "p14.restuss-admission.precu-skill-authority"
Assert-Contract ($restussBody.Contains("!factions.isImperial(self) && !factions.isRebel(self)") -and
    $restussBody.Contains("!factions.isCovert(self)") -and
    $restussBody.Contains('"pvp_advanced_region_level_low"') -and
    $restussBody.Contains('"pvp_advanced_region_not_allowed"') -and
    $restussBody.Contains("pvpMakeDeclared(self)") -and
    $restussBody.Contains('warpPlayer(self, "rori", 5305, 80, 6188')) `
    "p14.restuss-admission.authored-flow.preserved"
Assert-Contract ($enterMethod.Contains("gcw.isPostNgeQueuedBattlefieldRetired()") -and
    $enterMethod.IndexOf("gcw.isPostNgeQueuedBattlefieldRetired()") -lt
        $enterMethod.IndexOf("regionName.startsWith(gcw.PVP_BATTLEFIELD_REGION)")) `
    "p14.restuss-admission.queued-battlefields.remain-retired"

$missionMap = [ordered]@{
    "mission_terminal.java" = (Join-Path $scriptRoot "systems/missions/base/mission_terminal.java")
    "mission_base.java" = (Join-Path $scriptRoot "systems/missions/base/mission_base.java")
    "missions.java" = (Join-Path $scriptRoot "library/missions.java")
}
foreach ($mission in $missionMap.GetEnumerator())
{
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $mission.Value).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$contract.continuityEvidence.missionSourceSha256.($mission.Key)) `
        "p14.restuss-admission.mission-source.$($mission.Key).unchanged"
}

if ($failures.Count -gt 0)
{
    throw "P14 PRE-CU Restuss admission authority contract failed: $($failures -join ', ')"
}

Write-Host "P14 PRE-CU Restuss admission authority contract passed."
