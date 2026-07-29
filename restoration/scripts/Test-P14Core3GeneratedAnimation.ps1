param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path

function Read-DataRows([string]$Path)
{
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0].Split("`t")
    return @($lines[2..($lines.Count - 1)] |
        ConvertFrom-Csv -Delimiter "`t" -Header $header)
}

$engine = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/combat_engine.java") -Raw
$combat = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/combat.java") -Raw
$base = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java") -Raw
$fixture = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java") -Raw
$rows = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab")

foreach ($name in @("headShot1", "bodyShot1"))
{
    $row = @($rows | Where-Object actionName -ceq $name)
    if ($row.Count -ne 1 -or $row[0].animationType -cne "RANGED")
    {
        throw "$name generated-animation metadata drifted."
    }
}

foreach ($token in @(
    'dat.precuAnimationType',
    'precu.getInt("animationType")',
    'dict.put("precuAnimationType"',
    'public int		precuAnimationType'))
{
    if (-not $engine.Contains($token)) { throw "combat_engine animation metadata drifted: $token" }
}

foreach ($token in @(
    "getPrecuActionAnimation(",
    "int threshold = Math.max(0, weaponMaxDamage) >> 2",
    'animation += damage > threshold ? "_medium" : "_light"',
    "hitLocation == HIT_LOCATION_HEAD",
    'animation += "_face"',
    'animation.startsWith("*creature_attack")'))
{
    if (-not $combat.Contains($token)) { throw "Core3 generated-animation transform drifted: $token" }
}

foreach ($token in @(
    "combat.getPrecuActionAnimation(",
    "hitData[i].hitLocation",
    "weaponData.maxDamage",
    "hitData[i].damage",
    '"animation.generated"',
    '"animation.type"'))
{
    if (-not $base.Contains($token)) { throw "combat playback integration drifted: $token" }
}

foreach ($token in @("diagnosticAnimation=", "diagnosticAnimationType="))
{
    if (-not $fixture.Contains($token)) { throw "fixture animation diagnostics drifted: $token" }
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-core3-generated-animation.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.buildEvidence.javaCompile -ne "passed" -or
        $contract.buildEvidence.datatableCompile -ne "passed" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        $contract.runtimeEvidence.fixtureCleanup -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Core3 generated-animation evidence is not ready."
    }
}

Write-Host "Publish 14.1 Core3 generated-animation contract passed."
