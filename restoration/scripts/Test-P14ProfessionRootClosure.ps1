[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $root ([string]$manifest.contracts.p14ProfessionRootClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$lines = Get-Content $skillPath
$skills = @(@($lines[0]) + @($lines | Select-Object -Skip 2) | ConvertFrom-Csv -Delimiter "`t")
$searchableNames = @($contract.publish14Evidence.searchableRoots | ForEach-Object { [string]$_ })
$hiddenNames = @($contract.publish14Evidence.hiddenRoots | ForEach-Object { [string]$_ })
$rootNames = @($searchableNames + $hiddenNames)
$rootNameSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$rootNames | ForEach-Object { [void]$rootNameSet.Add($_) }
$rootRows = @($skills | Where-Object { $rootNameSet.Contains([string]$_.NAME) })
$rootLines = @($lines | Where-Object {
    $name = ($_ -split "`t", 2)[0]
    $rootNameSet.Contains($name)
} | Sort-Object)
$rootText = ($rootLines -join "`n") + "`n"
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $rootHash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rootText)) | ForEach-Object { $_.ToString("x2") }) -join "")
}
finally {
    $sha.Dispose()
}
$failures = [Collections.Generic.List[string]]::new()
function Assert-C([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}
Write-Host "Publish 14.1 profession-root closure checks:"
Assert-C (
    $rootNames.Count -eq [int]$contract.publish14Evidence.rootCount -and
    $rootNameSet.Count -eq [int]$contract.publish14Evidence.rootCount -and
    $searchableNames.Count -eq 33 -and
    $hiddenNames.Count -eq 9
) "p14.profession-roots.contract.partition"
Assert-C (
    $rootRows.Count -eq [int]$contract.publish14Evidence.rootCount -and
    $rootLines.Count -eq [int]$contract.publish14Evidence.rootCount -and
    [Text.Encoding]::UTF8.GetByteCount($rootText) -eq [int]$contract.publish14Evidence.normalizedSortedRowsBytes -and
    $rootHash -ceq [string]$contract.publish14Evidence.normalizedSortedRowsSha256
) "p14.profession-roots.all-42-rows-exact"
$structuralRows = @($rootRows | Where-Object {
    [string]$_.GRAPH_TYPE -ceq "fourByFour" -and
    [string]$_.IS_PROFESSION -ceq "1" -and
    [string]$_.GOD_ONLY -ceq "0" -and
    [string]$_.IS_HIDDEN -ceq "0" -and
    [string]$_.SKILLS_REQUIRED_COUNT -ceq "0" -and
    [string]$_.XP_COST -ceq "0" -and
    [string]$_.APPRENTICESHIPS_REQUIRED -ceq "0"
})
Assert-C ($structuralRows.Count -eq 42) "p14.profession-roots.graph-and-cost-shape"
$searchableRows = @($rootRows | Where-Object {
    $searchableNames -ccontains [string]$_.NAME -and [string]$_.SEARCHABLE -ceq "1"
})
$hiddenRows = @($rootRows | Where-Object {
    $hiddenNames -ccontains [string]$_.NAME -and [string]$_.SEARCHABLE -ceq "0"
})
Assert-C (
    $searchableRows.Count -eq 33 -and
    $hiddenRows.Count -eq 9
) "p14.profession-roots.searchable-33-hidden-9"
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
    ) "p14.profession-roots.build.ready-and-hashed"
    Assert-C (
        [string]$asset.commit -ne "" -and
        [string]$asset.skillsIffSha256 -ceq [string]$b.clientTableBuild.compiledSha256
    ) "p14.profession-roots.asset-publication"
    Assert-C (
        [string]$runtime.result -ceq "passed" -and
        [int]$runtime.allProfessionRows -eq [int]$contract.clientPresentation.expectedVisibleRows -and
        [bool]$runtime.clientLoadedCompiledTable -and
        [bool]$runtime.skillsWindowOpenedOffFocus -and
        [bool]$runtime.serverHealthy -and
        [string]$runtime.screenshot -ne "" -and
        [string]$runtime.screenshotSha256 -ne ""
    ) "p14.profession-roots.runtime-searchability"
}
if ($failures.Count) { throw "Profession-root closure failed: " + ($failures -join ", ") }
Write-Host "Publish 14.1 profession-root closure passed."
