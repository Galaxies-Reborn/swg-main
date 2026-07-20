[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $root ([string]$manifest.contracts.p14DoctorProfessionClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$lines = Get-Content $skillPath
$skills = @(@($lines[0]) + @($lines | Select-Object -Skip 2) | ConvertFrom-Csv -Delimiter "`t")
$e = $contract.publish14Evidence
$excludedPrefix = [string]$e.excludedCompatibilityPrefix
$familyRows = @($lines | Where-Object {
    $_.StartsWith([string]$e.family.prefix) -and
    -not $_.StartsWith($excludedPrefix)
} | Sort-Object)
$familyText = ($familyRows -join "`n") + "`n"
$familyObjects = @($skills | Where-Object {
    ([string]$_.NAME).StartsWith([string]$e.family.prefix) -and
    -not ([string]$_.NAME).StartsWith($excludedPrefix)
})
$previouslyExact = @($e.previouslyExactRows | ForEach-Object { [string]$_ })
$restoredObjects = @($familyObjects | Where-Object { $previouslyExact -cnotcontains [string]$_.NAME })
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
Write-Host "Publish 14.1 Doctor profession closure checks:"
$shape = $e.restoredShape
$authenticRestored = @($restoredObjects | Where-Object {
    [string]$_.GRAPH_TYPE -ceq [string]$shape.graphType -and
    [string]$_.JEDI_STATE_REQUIRED -ceq [string]$shape.jediStateRequired
})
Assert-C (
    $restoredObjects.Count -eq [int]$e.restoredRowCount -and
    $authenticRestored.Count -eq [int]$e.restoredRowCount
) "p14.doctor-profession.restored-17-row-shape"
Assert-C (
    $familyRows.Count -eq [int]$e.family.rowCount -and
    [Text.Encoding]::UTF8.GetByteCount($familyText) -eq [int]$e.family.normalizedSortedRowsBytes -and
    $familyHash -ceq [string]$e.family.normalizedSortedRowsSha256
) "p14.doctor-profession.family.all-19-rows-exact"
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
    ) "p14.doctor-profession.build.ready-and-hashed"
    Assert-C (
        [bool]$b.clientTableBuild.binaryStableFromMilestone121 -and
        [string]$asset.skillsIffSha256 -ceq [string]$b.clientTableBuild.compiledSha256 -and
        [int]$tools.protocolVersion -eq 85
    ) "p14.doctor-profession.client-publications"
    Assert-C (
        [string]$runtime.result -ceq "passed" -and
        [int]$runtime.selectedProfessionRow -eq [int]$tools.selectionIndex -and
        [string]$runtime.selectedProfession -ceq "science_doctor_novice" -and
        [string]$runtime.graphType -ceq "fourByFour" -and
        [bool]$runtime.graphVisible -and
        [bool]$runtime.clientLoadedCompiledTable -and
        [bool]$runtime.skillsWindowDrivenOffFocus -and
        [bool]$runtime.serverHealthy -and
        [int]$runtime.fatalOrExceptionCount -eq 0 -and
        [string]$runtime.screenshotSha256 -ne ""
    ) "p14.doctor-profession.runtime-graph"
}
if ($failures.Count) { throw "Doctor profession closure failed: " + ($failures -join ", ") }
Write-Host "Publish 14.1 Doctor profession closure passed."
