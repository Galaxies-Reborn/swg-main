[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$contractPath = Join-Path $restorationRoot "contracts/p14-nge-corpse-contraband-retirement.json"
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$corpsePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/corpse/ai_corpse.java"
$combatActionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"

foreach ($path in @($corpsePath, $combatActionsPath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required source is missing: $path"
    }
}

$corpse = Get-Content -LiteralPath $corpsePath -Raw
foreach ($retired in @(
    "getSkillTemplate(",
    "getLevel(",
    "mnu_find_illicit_goods",
    "inspectCorpseForContraband(",
    "contrabandChecked"
))
{
    if ($corpse.Contains($retired))
    {
        throw "NGE corpse contraband surface remains active: $retired"
    }
}

foreach ($preserved in @(
    "menu_info_types.LOOT",
    "canHarvest(self, player)",
    "corpse.SID_HARVEST_MEAT",
    "corpse.SID_HARVEST_HIDE",
    "corpse.SID_HARVEST_BONE",
    "group.MASTER_LOOTER",
    "group.LOTTERY",
    "queueCommand(player, (1880585606), inv"
))
{
    if (-not $corpse.Contains($preserved))
    {
        throw "Required corpse loot/harvest behavior was not preserved: $preserved"
    }
}

$combatActions = Get-Content -LiteralPath $combatActionsPath -Raw
if (-not $combatActions.Contains("public int sm_inspect_cargo("))
{
    throw "Compatibility command handler was unexpectedly removed."
}

if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }

    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $corpsePath).Hash.ToLowerInvariant()
    if ($sourceHash -ne $contract.buildEvidence.sourceSha256."ai_corpse.java")
    {
        throw "Canonical ai_corpse.java evidence mismatch."
    }

    $patchPath = Join-Path $restorationRoot "patches/dsrc/148-p14-nge-corpse-contraband-retirement.patch"
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

Write-Host "Publish 14.1 NGE corpse contraband retirement contract passed."
