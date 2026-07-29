[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$relativeFiles = [ordered]@{
    "trigger_journal.java" = "dsrc/sku.0/sys.server/compiled/game/script/npe/trigger_journal.java"
    "handoff_to_tatooine.java" = "dsrc/sku.0/sys.server/compiled/game/script/npe/handoff_to_tatooine.java"
    "npe_force_sensitive.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_force_sensitive.java"
    "npe_commando.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_commando.java"
    "npe_profession_trader.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_profession_trader.java"
    "npe_profession_entertainer.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_profession_entertainer.java"
    "npe_medic2.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_medic2.java"
    "npe_spy.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_spy.java"
    "npe_station_inaldra2.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_station_inaldra2.java"
    "npe_main_bartender.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_main_bartender.java"
    "npe_entertainer_1_questgiver.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/npe_entertainer_1_questgiver.java"
}
$texts = [ordered]@{}
foreach ($entry in $relativeFiles.GetEnumerator())
{
    $texts[$entry.Key] = Get-Content -LiteralPath (Join-Path $root $entry.Value) -Raw
}
$surface = $texts.Values -join "`n"
if ($surface.Contains("getSkillTemplate("))
{
    throw "An NPE class-template read remains."
}
$handoff = $texts["handoff_to_tatooine.java"]
$handoffStart = $handoff.IndexOf("public int OnLogin")
$handoffEnd = $handoff.IndexOf("`n    }", $handoffStart)
$handoffSurface = $handoff.Substring($handoffStart, $handoffEnd - $handoffStart)
foreach ($retired in @("grantQuest(", "requestGrantQuest(", "newbieTutorialSetToolbarElement(", "newbieTutorialEnableHudElement("))
{
    if ($handoffSurface.Contains($retired))
    {
        throw "NPE handoff behavior remains: $retired"
    }
}
if (-not $handoffSurface.Contains('detachScript(self, "npe.handoff_to_tatooine")'))
{
    throw "NPE handoff does not detach."
}
$entertainer = $texts["npe_entertainer_1_questgiver.java"]
$actionStart = $entertainer.IndexOf("public void npe_entertainer_1_questgiver_action_giveQuest")
$actionEnd = $entertainer.IndexOf("public int npe_entertainer_1_questgiver_handleBranch2", $actionStart)
$action = $entertainer.Substring($actionStart, $actionEnd - $actionStart)
foreach ($retired in @("grantQuest(", "sendSignal(", "newbieTutorialSetToolbarElement(", "newbieTutorialHighlightUIElement("))
{
    if ($action.Contains($retired))
    {
        throw "NPE entertainer action remains: $retired"
    }
}
$failClosedCount = ([regex]::Matches(
    $surface,
    "condition_[A-Za-z0-9_]+\(obj_id player, obj_id npc\) throws InterruptedException\s*\{\s*return false;\s*\}")).Count
if ($failClosedCount -lt 10)
{
    throw "Expected at least ten fail-closed NPE class gates; found $failClosedCount."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-npe-class-progression-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $relativeFiles.GetEnumerator())
    {
        $path = Join-Path $root $entry.Value
        $bytes = [Text.Encoding]::UTF8.GetBytes(
            ([IO.File]::ReadAllText($path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try
        {
            $actual = ([BitConverter]::ToString(
                $sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
        }
        finally
        {
            $sha.Dispose()
        }
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/163-p14-npe-class-progression-retirement.patch"
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
Write-Host "Publish 14.1 NPE class-progression retirement contract passed."
