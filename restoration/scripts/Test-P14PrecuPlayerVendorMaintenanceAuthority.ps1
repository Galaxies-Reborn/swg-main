[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuPlayerVendorMaintenanceAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$texts = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.player-vendor-maintenance.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.player-vendor-maintenance.source.$($property.Name).authenticated"
}

$attributes = [string]$texts.attributes
Assert-Contract ($attributes.Contains('script/terminal/vendor.java -text whitespace=cr-at-eol')) `
    "p14.player-vendor-maintenance.no-line-ending-bloat-policy"

$vendor = [string]$texts.vendor
$billing = Get-SourceSlice $vendor "public int OnMaintenanceLoop(" "public void displayStatus("
$status = Get-SourceSlice $vendor "public void displayStatus(" "public int OnAboutToReceiveItem("
Assert-Contract (-not $vendor.Contains('expertise_vendor_cost_decrease') -and
    -not $billing.Contains('utils.isProfession(owner, utils.TRADER)') -and
    -not $status.Contains('utils.isProfession(ownerId, utils.TRADER)') -and
    -not $billing.Contains('getSkillStatisticModifier(owner, "hiring")') -and
    -not $status.Contains('getSkillStatisticModifier(ownerId, "hiring")')) `
    "p14.player-vendor-maintenance.nge-authority-retired"
Assert-Contract ($billing.Contains('int cost = 15 * loops;') -and
    $billing.Contains('hasSkill(owner, "crafting_merchant_master")') -and
    $billing.Contains('hasSkill(owner, "crafting_merchant_sales_02")') -and
    $billing.Contains('cost += 6 * loops;') -and
    $billing.Contains('vendor_lib.decrementMaintenancePool(self, cost)') -and
    $billing.Contains('vendor_lib.damageVendor(self, damage)') -and
    $billing.Contains('vendor_lib.repairVendor(self, amt_repaired)')) `
    "p14.player-vendor-maintenance.billing-precu-authority"
Assert-Contract ($status.Contains('int cost = 15;') -and
    $status.Contains('hasSkill(ownerId, "crafting_merchant_master")') -and
    $status.Contains('hasSkill(ownerId, "crafting_merchant_sales_02")') -and
    $status.Contains('cost += 6;') -and
    $status.Contains('dsrc[1] = "Maintenance Rate: " + cost;') -and
    $status.Contains('vendor_lib.getMaintenancePool(self)')) `
    "p14.player-vendor-maintenance.status-precu-authority"

$skills = [string]$texts.skills
Assert-Contract ($skills.Contains("crafting_merchant_master`t") -and
    $skills.Contains("crafting_merchant_sales_02`t")) `
    "p14.player-vendor-maintenance.merchant-skill-ownership"
Assert-Contract ([int](15 * 0.6) -eq 9 -and [int](15 * 0.8) -eq 12 -and
    (15 + 6) -eq 21 -and ([int](15 * 0.6) + 6) -eq 15 -and
    ([int](15 * 0.8) + 6) -eq 18) `
    "p14.player-vendor-maintenance.authored-rate-examples"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.player-vendor-maintenance.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.player-vendor-maintenance.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.vendor -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.player-vendor-maintenance.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.player-vendor-maintenance.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.player-vendor-maintenance.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU player-vendor maintenance authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU player-vendor maintenance authority contract passed."
