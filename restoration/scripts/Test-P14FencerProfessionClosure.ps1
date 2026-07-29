[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $root ([string]$manifest.contracts.p14FencerProfessionClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$lines = Get-Content $skillPath
$skills = @(@($lines[0]) + @($lines | Select-Object -Skip 2) | ConvertFrom-Csv -Delimiter "`t")
$e = $contract.publish14Evidence
$prefix = [string]$e.family.prefix
$excludedPrefix = [string]$e.excludedCompatibilityPrefix
$familyRows = @($lines | Where-Object {
    $_.StartsWith($prefix) -and -not $_.StartsWith($excludedPrefix)
} | Sort-Object)
$familyText = ($familyRows -join "`n") + "`n"
$familyObjects = @($skills | Where-Object {
    ([string]$_.NAME).StartsWith($prefix) -and
    -not ([string]$_.NAME).StartsWith($excludedPrefix)
})
$rootObject = @($familyObjects | Where-Object NAME -CEQ ([string]$e.professionRoot))
$childObjects = @($familyObjects | Where-Object NAME -CNE ([string]$e.professionRoot))
$compatibilityRows = @($skills | Where-Object { ([string]$_.NAME).StartsWith($excludedPrefix) })
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $familyHash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($familyText)) | ForEach-Object { $_.ToString("x2") }) -join "")
}
finally {
    $sha.Dispose()
}
$failures = [Collections.Generic.List[string]]::new()
function Assert-C([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}
Write-Host "Publish 14.1 Fencer profession closure checks:"
$authenticChildren = @($childObjects | Where-Object {
    [string]$_.GRAPH_TYPE -ceq "fourByFour" -and
    [string]$_.JEDI_STATE_REQUIRED -ceq "none"
})
Assert-C (
    $rootObject.Count -eq 1 -and
    $childObjects.Count -eq [int]$e.restoredRowCount -and
    $authenticChildren.Count -eq [int]$e.restoredRowCount
) "p14.fencer-profession.complete-four-by-four-shape"
Assert-C (
    $familyRows.Count -eq [int]$e.family.rowCount -and
    [Text.Encoding]::UTF8.GetByteCount($familyText) -eq [int]$e.family.normalizedSortedRowsBytes -and
    $familyHash -ceq [string]$e.family.normalizedSortedRowsSha256
) "p14.fencer-profession.family.all-19-rows-exact"
Assert-C ($compatibilityRows.Count -eq 7) "p14.fencer-profession.compatibility-prereqs-isolated"
if ($Expectation -ceq "Ready") {
    $b = $contract.buildEvidence
    $runtime = $contract.runtimeEvidence
    $asset = $contract.clientAssetPublication
    $tools = $contract.clientToolPublication
    $patch = Join-Path $root ([string]$b.overlayPatch -replace "^restoration/", "")
    Assert-C (
        [string]$contract.status -ceq "ready" -and
        [string]$b.clientTableBuild.result -ceq "passed" -and
        (Get-Item $patch).Length -eq [int64]$b.overlayPatchBytes -and
        (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.overlayPatchSha256 -and
        (Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.sourceSha256."skills.tab"
    ) "p14.fencer-profession.build.ready-and-hashed"
    Assert-C (
        [string]$asset.commit -ne "" -and
        [string]$asset.skillsIffSha256 -ceq [string]$b.clientTableBuild.compiledSha256 -and
        [int]$tools.protocolVersion -eq 85
    ) "p14.fencer-profession.client-publications"
    Assert-C (
        [string]$runtime.result -ceq "passed" -and
        [int]$runtime.allProfessionRows -eq 33 -and
        [int]$runtime.selectedProfessionRow -eq [int]$tools.selectionIndex -and
        [string]$runtime.selectedProfession -ceq "combat_1hsword_novice" -and
        [string]$runtime.graphType -ceq "fourByFour" -and
        [bool]$runtime.graphVisible -and
        [bool]$runtime.clientLoadedCompiledTable -and
        [bool]$runtime.skillsWindowDrivenOffFocus -and
        [bool]$runtime.serverHealthy -and
        [int]$runtime.fatalOrExceptionCount -eq 0 -and
        [string]$runtime.screenshotSha256 -ne ""
    ) "p14.fencer-profession.runtime-graph"
}
if ($failures.Count) { throw "Fencer profession closure failed: " + ($failures -join ", ") }
Write-Host "Publish 14.1 Fencer profession closure passed."
