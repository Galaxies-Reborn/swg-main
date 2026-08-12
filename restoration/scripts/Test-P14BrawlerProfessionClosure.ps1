[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $root ([string]$manifest.contracts.p14BrawlerProfessionClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$lines = Get-Content $skillPath
$skills = @(@($lines[0]) + @($lines | Select-Object -Skip 2) | ConvertFrom-Csv -Delimiter "`t")
$e = $contract.publish14Evidence
$override = $contract.galaxiesRebornOverride
$familyRows = @($lines | Where-Object { $_.StartsWith([string]$e.family.prefix) } | Sort-Object)
$familyText = ($familyRows -join "`n") + "`n"
$familyObjects = @($skills | Where-Object { ([string]$_.NAME).StartsWith([string]$e.family.prefix) })
$rootObject = @($familyObjects | Where-Object NAME -CEQ ([string]$e.professionRoot))
$childObjects = @($familyObjects | Where-Object NAME -CNE ([string]$e.professionRoot))
$noviceObject = @($familyObjects | Where-Object NAME -CEQ "combat_brawler_novice")
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
Write-Host "Publish 14.1 Brawler profession closure checks:"
$authenticChildren = @($childObjects | Where-Object {
    [string]$_.GRAPH_TYPE -ceq "fourByFour" -and
    [string]$_.JEDI_STATE_REQUIRED -ceq "none"
})
Assert-C (
    $rootObject.Count -eq 1 -and
    $childObjects.Count -eq [int]$e.restoredRowCount -and
    $authenticChildren.Count -eq [int]$e.restoredRowCount
) "p14.brawler-profession.complete-four-by-four-shape"
Assert-C (
    $familyRows.Count -eq [int]$e.family.rowCount -and
    [Text.Encoding]::UTF8.GetByteCount($familyText) -eq [int]$override.currentFamily.normalizedSortedRowsBytes -and
    $familyHash -ceq [string]$override.currentFamily.normalizedSortedRowsSha256 -and
    [int]$override.historicalPublish14Family.normalizedSortedRowsBytes -eq [int]$e.family.normalizedSortedRowsBytes -and
    [string]$override.historicalPublish14Family.normalizedSortedRowsSha256 -ceq [string]$e.family.normalizedSortedRowsSha256
) "p14.brawler-profession.current-family-with-historical-p14-baseline"
$noviceCerts = @()
if ($noviceObject.Count -eq 1) {
    $noviceCerts = @(([string]$noviceObject[0].COMMANDS).Split(",") | Where-Object { $_.StartsWith("cert_") })
}
Assert-C (
    $noviceObject.Count -eq 1 -and
    [int]$noviceObject[0].MONEY_REQUIRED -eq [int]$override.noviceQualification.moneyRequired -and
    [int]$noviceObject[0].POINTS_REQUIRED -eq [int]$override.noviceQualification.pointsRequired -and
    [string]$noviceObject[0].SKILLS_REQUIRED -ceq [string]$override.noviceQualification.skillsRequired -and
    [string]$noviceObject[0].XP_TYPE -ceq [string]$override.noviceQualification.xpType -and
    [int]$noviceObject[0].XP_COST -eq [int]$override.noviceQualification.xpCost -and
    [int]$noviceObject[0].XP_CAP -eq [int]$override.noviceQualification.xpCap -and
    ($noviceCerts -join ",") -ceq (@($override.noviceCertifications) -join ",")
) "p14.brawler-profession.gr-base-novice-override"
Assert-C (
    [string]$override.ownerContract -ceq "contracts/p14-precu-base-novice-learning.json" -and
    [string]$override.directSourceCommit -cmatch '^[0-9a-f]{40}$' -and
    (Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$override.sourceSha256
) "p14.brawler-profession.gr-override-owner-and-source"
if ($Expectation -ceq "Ready") {
    $b = $contract.buildEvidence
    $runtime = $contract.runtimeEvidence
    $asset = $contract.clientAssetPublication
    $tools = $contract.clientToolPublication
    $patch = Join-Path $root ([string]$b.overlayPatch -replace "^restoration/", "")
    Assert-C (
        [string]$contract.status -ceq "ready" -and
        [string]$e.evidenceRole -ceq "historical-publish14-baseline" -and
        [string]$b.clientTableBuild.result -ceq "passed" -and
        (Get-Item $patch).Length -eq [int64]$b.overlayPatchBytes -and
        (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.overlayPatchSha256 -and
        [string]$b.sourceSha256."skills.tab" -cmatch '^[0-9a-f]{64}$' -and
        [string]$b.sourceSha256."skills.tab" -cne [string]$override.sourceSha256
    ) "p14.brawler-profession.historical-build-ready-and-preserved"
    Assert-C (
        [string]$asset.commit -ne "" -and
        [string]$asset.skillsIffSha256 -ceq [string]$b.clientTableBuild.compiledSha256 -and
        [int]$tools.protocolVersion -eq 85
    ) "p14.brawler-profession.client-publications"
    Assert-C (
        [string]$runtime.result -ceq "passed" -and
        [int]$runtime.allProfessionRows -eq 33 -and
        [int]$runtime.selectedProfessionRow -eq [int]$tools.selectionIndex -and
        [string]$runtime.selectedProfession -ceq "combat_brawler_novice" -and
        [string]$runtime.graphType -ceq "fourByFour" -and
        [bool]$runtime.graphVisible -and
        [bool]$runtime.clientLoadedCompiledTable -and
        [bool]$runtime.skillsWindowDrivenOffFocus -and
        [bool]$runtime.serverHealthy -and
        [int]$runtime.fatalOrExceptionCount -eq 0 -and
        [string]$runtime.screenshotSha256 -ne ""
    ) "p14.brawler-profession.runtime-graph"
}
if ($failures.Count) { throw "Brawler profession closure failed: " + ($failures -join ", ") }
Write-Host "Publish 14.1 Brawler profession closure passed."
