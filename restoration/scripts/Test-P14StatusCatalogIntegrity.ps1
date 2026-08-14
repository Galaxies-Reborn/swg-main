param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14StatusCatalogIntegrity)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path

function Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$buffPath = Join-Path $root ([string]$contract.sourceFiles.buffTable)
$effectPath = Join-Path $root ([string]$contract.sourceFiles.effectMapping)
$scriptRoot = Join-Path $root ([string]$contract.sourceFiles.serverScripts)
foreach ($path in @($buffPath, $effectPath, $scriptRoot)) {
    Assert (Test-Path -LiteralPath $path) "Missing status catalog source: $path"
}
$repositoryRoot = Split-Path -Parent $restorationRoot
Assert (Test-Path -LiteralPath (Join-Path $repositoryRoot ([string]$contract.overlay)) -PathType Leaf) "Status catalog overlay is missing"

$buffs = @(Rows $buffPath)
$visible = @($buffs | Where-Object VISIBLE -CEQ "1")
$positive = @($visible | Where-Object DEBUFF -CEQ "0")
$debuff = @($visible | Where-Object DEBUFF -CEQ "1")
Assert ($buffs.Count -eq [int]$contract.catalog.rawRows) "Raw status row count drifted"
Assert ($visible.Count -eq [int]$contract.catalog.visibleRows) "Visible status row count drifted"
Assert ($positive.Count -eq [int]$contract.catalog.positiveRows) "Positive status row count drifted"
Assert ($debuff.Count -eq [int]$contract.catalog.debuffRows) "Debuff status row count drifted"

foreach ($row in $visible) {
    Assert (-not [string]::IsNullOrWhiteSpace([string]$row.NAME)) "Visible status has a blank name"
    Assert (-not [string]::IsNullOrWhiteSpace([string]$row.ICON)) "Visible status '$($row.NAME)' has a blank icon"
    Assert ([string]$row.DEBUFF -cin @("0", "1")) "Visible status '$($row.NAME)' has invalid polarity"
    Assert ([int]$row.MAX_STACKS -ge 1) "Visible status '$($row.NAME)' has invalid stack metadata"
    Assert (-not [string]::IsNullOrWhiteSpace([string]$row.CALLBACK)) "Visible status '$($row.NAME)' has a blank callback"
}

$effectNames = @{}
foreach ($row in @(Rows $effectPath)) { $effectNames[[string]$row.NAME] = $true }
$internal = @{}
foreach ($name in $contract.catalog.internalHandlerParameters) { $internal[[string]$name] = $true }
$missingEffects = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($row in $visible) {
    foreach ($number in 1..5) {
        $effect = [string]$row.("EFFECT${number}_PARAM")
        if ($effect.Length -gt 0 -and -not $effectNames.ContainsKey($effect) -and -not $internal.ContainsKey($effect)) {
            [void]$missingEffects.Add($effect)
        }
    }
}
Assert ($missingEffects.Count -eq 0) "Visible statuses have unmapped display effects: $([string]::Join(', ', $missingEffects))"

$clientColumns = @(
    "GROUP1", "GROUP2", "PRIORITY", "ICON", "DURATION",
    "EFFECT1_PARAM", "EFFECT1_VALUE", "EFFECT2_PARAM", "EFFECT2_VALUE",
    "EFFECT3_PARAM", "EFFECT3_VALUE", "EFFECT4_PARAM", "EFFECT4_VALUE",
    "EFFECT5_PARAM", "EFFECT5_VALUE", "STATE", "CALLBACK", "VISIBLE",
    "DEBUFF", "DISPELL_PLAYER", "IS_CELESTIAL", "MAX_STACKS", "DISPLAY_ORDER"
)
foreach ($group in @($buffs | Group-Object NAME | Where-Object Count -gt 1)) {
    $expected = [string]::Join([char]31, @($clientColumns | ForEach-Object { [string]$group.Group[0].$_ }))
    foreach ($row in @($group.Group | Select-Object -Skip 1)) {
        $actual = [string]::Join([char]31, @($clientColumns | ForEach-Object { [string]$row.$_ }))
        Assert ($actual -ceq $expected) "Duplicate status '$($group.Name)' has ambiguous client metadata"
    }
}

$byName = @{}
foreach ($row in $visible) { $byName[[string]$row.NAME] = $row }
$positiveFixture = $byName[[string]$contract.lifecycleFixtures.positive]
$debuffFixture = $byName[[string]$contract.lifecycleFixtures.debuffStackable]
Assert ($null -ne $positiveFixture -and $positiveFixture.DEBUFF -ceq "0" -and [int]$positiveFixture.MAX_STACKS -eq 1) "Positive lifecycle fixture drifted"
Assert ($null -ne $debuffFixture -and $debuffFixture.DEBUFF -ceq "1" -and [int]$debuffFixture.MAX_STACKS -gt 1) "Stacked debuff lifecycle fixture drifted"

$literalBuffNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$literalPattern = 'buff\.applyBuff(?:WithStackCount)?\s*\([^;\r\n]*?"([^"]+)"'
foreach ($file in Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter *.java -File) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($text, $literalPattern)) { [void]$literalBuffNames.Add($match.Groups[1].Value) }
}
$catalogNames = @($buffs.NAME)
$missingLiterals = @($literalBuffNames | Where-Object {
    $candidate = $_
    -not $byName.ContainsKey($candidate) -and
    -not ($catalogNames -ccontains $candidate) -and
    @($catalogNames | Where-Object { $_.StartsWith($candidate, [StringComparison]::Ordinal) }).Count -eq 0
})
Assert ($missingLiterals.Count -eq 0) "Server applies literal statuses absent from the catalog: $([string]::Join(', ', $missingLiterals))"

$analyzer = Join-Path $PSScriptRoot "analyze_p14_status_applications.py"
Assert (Test-Path -LiteralPath $analyzer -PathType Leaf) "Balanced status-application analyzer is missing"
$python = Get-Command python -ErrorAction SilentlyContinue
Assert ($null -ne $python) "Python is required for the balanced status-application audit"
$analysisJson = (& $python.Source $analyzer --buff-table $buffPath --script-root $scriptRoot | Out-String)
Assert ($LASTEXITCODE -eq 0) "Balanced status-application audit found missing catalog rows"
$analysis = $analysisJson | ConvertFrom-Json
Assert ([int]$analysis.callCount -eq [int]$contract.serverApplications.directCalls) "Direct status-application count drifted"
Assert ([int]$analysis.methodCounts.applyBuff -eq [int]$contract.serverApplications.applyBuffCalls) "applyBuff call count drifted"
Assert ([int]$analysis.methodCounts.applyBuffWithStackCount -eq [int]$contract.serverApplications.stackCalls) "stacked applyBuff call count drifted"
Assert ([int]$analysis.resolvedStatusCount -eq [int]$contract.serverApplications.resolvedStatuses) "Resolved server status set drifted"
Assert ([int]$analysis.resolutionCounts.dynamic -eq [int]$contract.serverApplications.dynamicCalls) "Dynamic status boundary count drifted"
Assert (@($analysis.missingStatuses).Count -eq 0) "Balanced status-application audit found missing catalog rows"

if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and [string]$contract.runtimeEvidence.result -ceq "passed") "Status catalog integrity is not Ready"
}
Write-Host "Publish 14.1 status catalog integrity contract passed ($($visible.Count) visible rows; $($analysis.callCount) direct server applications; $($analysis.resolvedStatusCount) resolved statuses; $($analysis.unresolvedExpressionCount) data-driven expressions)."
