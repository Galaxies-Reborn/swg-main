[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $root ([string]$manifest.contracts.p14MusicianProfessionClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$lines = Get-Content $skillPath
$skills = @(@($lines[0]) + @($lines | Select-Object -Skip 2) | ConvertFrom-Csv -Delimiter "`t")
$e = $contract.publish14Evidence.professionRoot
$rootRow = @($skills | Where-Object NAME -CEQ ([string]$e.name))
$familyRows = @($lines | Where-Object { $_.StartsWith([string]$contract.publish14Evidence.family.prefix) } | Sort-Object)
$familyText = ($familyRows -join "`n") + "`n"
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $familyHash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($familyText)) | ForEach-Object { $_.ToString("x2") }) -join "")
}
finally {
    $sha.Dispose()
}
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-C([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}
Write-Host "Publish 14.1 Musician profession closure checks:"
Assert-C (
    $rootRow.Count -eq 1 -and
    [string]$rootRow[0].PARENT -ceq [string]$e.parent -and
    [string]$rootRow[0].GRAPH_TYPE -ceq [string]$e.graphType -and
    [string]$rootRow[0].IS_PROFESSION -ceq [string]$e.isProfession -and
    [string]$rootRow[0].SKILLS_REQUIRED_COUNT -ceq [string]$e.skillsRequiredCount -and
    [string]$rootRow[0].XP_COST -ceq [string]$e.xpCost -and
    [string]$rootRow[0].APPRENTICESHIPS_REQUIRED -ceq [string]$e.apprenticeshipsRequired -and
    [string]$rootRow[0].JEDI_STATE_REQUIRED -ceq [string]$e.jediStateRequired -and
    [string]$rootRow[0].SEARCHABLE -ceq [string]$e.searchable
) "p14.musician-profession.root.authentic"
Assert-C (
    $familyRows.Count -eq [int]$contract.publish14Evidence.family.rowCount -and
    [Text.Encoding]::UTF8.GetByteCount($familyText) -eq [int]$contract.publish14Evidence.family.normalizedSortedRowsBytes -and
    $familyHash -ceq [string]$contract.publish14Evidence.family.normalizedSortedRowsSha256
) "p14.musician-profession.family.all-19-rows-exact"
if ($Expectation -ceq "Ready") {
    $b = $contract.buildEvidence
    $runtime = $contract.runtimeEvidence
    $patch = Join-Path $root ([string]$b.overlayPatch -replace "^restoration/", "")
    Assert-C (
        [string]$contract.status -ceq "ready" -and
        (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.overlayPatchSha256 -and
        (Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.sourceSha256."skills.tab"
    ) "p14.musician-profession.build.ready-and-hashed"
    Assert-C (
        [bool]$runtime.clientLoadedCompiledTable -and
        [bool]$runtime.skillsWindowOpenedOffFocus -and
        [int]$runtime.availableSkillPoints -eq 250 -and
        [bool]$runtime.serverHealthy
    ) "p14.musician-profession.runtime-load"
}
if ($failures.Count) { throw "Musician profession closure failed: " + ($failures -join ", ") }
Write-Host "Publish 14.1 Musician profession closure passed."
