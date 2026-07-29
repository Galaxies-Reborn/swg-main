[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $root ([string]$manifest.contracts.p14MedicProfessionClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$lines = Get-Content $skillPath
$skills = @(@($lines[0]) + @($lines | Select-Object -Skip 2) | ConvertFrom-Csv -Delimiter "`t")
$e = $contract.publish14Evidence
$novice = @($skills | Where-Object NAME -CEQ ([string]$e.novice.name))
$familyRows = @($lines | Where-Object { $_.StartsWith([string]$e.family.prefix) } | Sort-Object)
$familyText = ($familyRows -join "`n") + "`n"
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
Write-Host "Publish 14.1 Medic profession closure checks:"
Assert-C (
    $novice.Count -eq 1 -and
    [string]$novice[0].GRAPH_TYPE -ceq [string]$e.novice.graphType -and
    [string]$novice[0].JEDI_STATE_REQUIRED -ceq [string]$e.novice.jediStateRequired
) "p14.medic-profession.novice.graph-and-jedi-defaults"
Assert-C (
    $familyRows.Count -eq [int]$e.family.rowCount -and
    [Text.Encoding]::UTF8.GetByteCount($familyText) -eq [int]$e.family.normalizedSortedRowsBytes -and
    $familyHash -ceq [string]$e.family.normalizedSortedRowsSha256
) "p14.medic-profession.family.all-19-rows-exact"
if ($Expectation -ceq "Ready") {
    $b = $contract.buildEvidence
    $runtime = $contract.runtimeEvidence
    $asset = $contract.clientAssetPublication
    $patch = Join-Path $root ([string]$b.overlayPatch -replace "^restoration/", "")
    Assert-C (
        [string]$contract.status -ceq "ready" -and
        [string]$b.clientTableBuild.result -ceq "passed" -and
        (Get-Item $patch).Length -eq [int64]$b.overlayPatchBytes -and
        (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.overlayPatchSha256 -and
        (Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.sourceSha256."skills.tab"
    ) "p14.medic-profession.build.ready-and-hashed"
    Assert-C (
        [bool]$b.clientTableBuild.binaryStableFromMilestone119 -and
        [string]$asset.skillsIffSha256 -ceq [string]$b.clientTableBuild.compiledSha256
    ) "p14.medic-profession.compiled-binary-stability"
    Assert-C (
        [string]$runtime.result -ceq "passed" -and
        [string]$runtime.selectedProfession -ceq [string]$e.novice.name -and
        [string]$runtime.graphType -ceq "fourByFour" -and
        [bool]$runtime.graphVisible -and
        [bool]$runtime.clientLoadedCompiledTable -and
        [bool]$runtime.skillsWindowDrivenOffFocus -and
        [bool]$runtime.serverHealthy -and
        [int]$runtime.fatalOrExceptionCount -eq 0 -and
        [string]$runtime.screenshotSha256 -ne ""
    ) "p14.medic-profession.runtime-graph"
}
if ($failures.Count) { throw "Medic profession closure failed: " + ($failures -join ", ") }
Write-Host "Publish 14.1 Medic profession closure passed."
