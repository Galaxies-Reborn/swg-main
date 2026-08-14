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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14ObjectMenuTelemetry)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

foreach ($evidence in @($contract.buildEvidence.overlayPatches))
{
    $patchPath = Join-Path $repositoryRoot ([string]$evidence.path)
    $exists = Test-Path -LiteralPath $patchPath -PathType Leaf
    Assert-Contract $exists ("p14.object-menu.overlay." + [string]$evidence.component + ".exists")
    if ($exists)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and
            $sha -ceq [string]$evidence.sha256) `
            ("p14.object-menu.overlay." + [string]$evidence.component + ".authenticated")
    }
}

$controllerPath = Join-Path $source ([string]$contract.sourceFiles.controller)
$configPath = Join-Path $source ([string]$contract.sourceFiles.runtimeConfig)
Assert-Contract (Test-Path -LiteralPath $controllerPath -PathType Leaf) "p14.object-menu.source.controller"
Assert-Contract (Test-Path -LiteralPath $configPath -PathType Leaf) "p14.object-menu.source.config"

$controller = Get-Content -LiteralPath $controllerPath -Raw
$config = Get-Content -LiteralPath $configPath -Raw
Assert-Contract ($controller.Contains('LOG("PreCuObjectMenu", ("request actor=%s target=%s sequence=%u clientItems=%u"') -and
    $controller.Contains('reason=empty') -and
    $controller.Contains('reason=target-not-authoritative') -and
    $controller.Contains('reason=script-complete')) "p14.object-menu.lifecycle-telemetry"
Assert-Contract ($config.Contains("logs/precuObjectMenu.log{c-*:c+PreCuObjectMenu}")) `
    "p14.object-menu.dedicated-log-target"
Assert-Contract ([bool]$contract.expected.behaviorChange -eq $false) `
    "p14.object-menu.observability-only"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.object-menu.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 object-menu telemetry failed: $($failures -join ', ')"
}
Write-Host "Publish 14 object-menu telemetry passed."
