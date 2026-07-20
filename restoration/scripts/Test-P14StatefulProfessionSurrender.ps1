param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$cppPath = Join-Path $root "src/engine/server/library/serverGame/src/shared/command/CommandCppFuncs.cpp"
$basePlayerPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_stateful_surrender_fixture.java"

$cpp = Get-Content -LiteralPath $cppPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw

foreach ($required in @(
    'skillName.find("pilot_") == 0',
    'client != nullptr && !client->isGod()',
    'creature->revokeSkill(*skill)'
))
{
    if (-not $cpp.Contains($required)) { throw "Native pilot dispatch is missing: $required" }
}
if ($cpp.Contains('"outdoors_squadleader_",') -or
    $cpp.Contains('skillName == "combat_bountyhunter_investigation_03"'))
{
    throw "A restored stateful profession is still blocked by the generic surrender predicate."
}
foreach ($protected in @('"force_",', '"pilot_",'))
{
    if (-not $cpp.Contains($protected)) { throw "Protected family drifted: $protected" }
}

foreach ($required in @(
    'strSkill.equals("combat_bountyhunter_investigation_03")',
    'messageTo(bountyMission, "abortMission", null, 0, false)',
    'strSkill.startsWith("outdoors_squadleader_")',
    'combat.VAR_GROUP_VOLLEY_TARGET',
    'combat.VAR_GROUP_LAST_VOLLEY_TIME',
    'squad_leader.clearRallyPoint(self)',
    'xp.notifySquadLeaderXp(self)'
))
{
    if (-not $basePlayer.Contains($required)) { throw "Stateful script cleanup is missing: $required" }
}
foreach ($required in @(
    'combat_bountyhunter_investigation_03',
    'outdoors_squadleader_offense_03',
    'pilot_neutral_novice',
    'getStringCrc("surrenderskill")',
    'utils.setScriptVar(player, "revokePilotSkill", 1)'
))
{
    if (-not $fixture.Contains($required)) { throw "Live fixture coverage is missing: $required" }
}

if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-stateful-profession-surrender.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.buildEvidence.javaCompile -ne "passed" -or
        $contract.buildEvidence.nativeCompile -ne "passed" -or
        $contract.buildEvidence.staticContract -ne "passed" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Stateful profession surrender evidence is not ready."
    }

    $sourceMap = @{
        "CommandCppFuncs.cpp" = $cppPath
        "base_player.java" = $basePlayerPath
        "precu_stateful_surrender_fixture.java" = $fixturePath
    }
    foreach ($name in $sourceMap.Keys)
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceMap[$name]).Hash.ToLowerInvariant()
        if ($actual -ne [string]$contract.buildEvidence.sourceSha256.$name)
        {
            throw "Materialized source hash mismatch: $name"
        }
    }

    foreach ($patch in @(
        @{ Path = $contract.buildEvidence.nativeOverlay; Bytes = $contract.buildEvidence.nativeOverlayBytes; Hash = $contract.buildEvidence.nativeOverlaySha256 },
        @{ Path = $contract.buildEvidence.scriptOverlay; Bytes = $contract.buildEvidence.scriptOverlayBytes; Hash = $contract.buildEvidence.scriptOverlaySha256 }
    ))
    {
        $path = Join-Path $restorationRoot ([string]$patch.Path -replace "^restoration/", "")
        $text = [IO.File]::ReadAllText($path) -replace "`r`n", "`n"
        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($bytes.Length -ne [int64]$patch.Bytes -or $hash -ne [string]$patch.Hash)
        {
            throw "Overlay evidence mismatch: $path"
        }
    }
}

Write-Host "Publish 14.1 stateful profession surrender contract passed."
