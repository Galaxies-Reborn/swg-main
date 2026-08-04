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
    ([string]$manifest.contracts.p14PrecuRetainedVendorProfessionAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$productionRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
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
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

function Get-VendorTableClasses([string]$Path)
{
    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -lt 2) { return @() }
    $headers = $lines[0].Split([char]9)
    $classIndex = [Array]::IndexOf($headers, "class")
    if ($classIndex -lt 0) { return @() }
    $classes = [System.Collections.Generic.List[int]]::new()
    for ($i = 2; $i -lt $lines.Count; $i++)
    {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        $columns = $lines[$i].Split([char]9)
        $value = if ($classIndex -lt $columns.Length) { $columns[$classIndex] } else { "" }
        $classes.Add($(if ([string]::IsNullOrWhiteSpace($value)) { 0 } else { [int]$value }))
    }
    return @($classes)
}

$sourcePaths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $sourcePaths[$property.Name] = Join-Path $source ([string]$property.Value)
}
$texts = @{}
foreach ($name in $sourcePaths.Keys)
{
    $path = $sourcePaths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.retained-vendor.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) `
            "p14.retained-vendor.source.$name.authenticated"
    }
}

$utils = [string]$texts.utils
$profession = Get-SourceSlice $utils `
    "public static int getPlayerProfession(" `
    "public static byte[] packObject("
Assert-Contract ($utils.Contains("public static final int NO_PROFESSION = 0;") -and
    $profession.Contains("isProfession(player, TRADER)") -and
    $profession.Contains("return TRADER;") -and
    $profession.Contains("return NO_PROFESSION;") -and
    $profession.LastIndexOf("return TRADER;", [System.StringComparison]::Ordinal) -lt
        $profession.LastIndexOf("return NO_PROFESSION;", [System.StringComparison]::Ordinal)) `
    "p14.retained-vendor.unowned-trader-fallback-retired"

$singularConsumers = @()
foreach ($file in Get-ChildItem -LiteralPath $productionRoot -Recurse -File -Filter "*.java")
{
    $relative = $file.FullName.Substring($source.Length + 1).Replace('\', '/')
    if ($relative.EndsWith("/library/utils.java") -or $relative -match '/(?:test|working|beta)/') { continue }
    if ((Get-Content -LiteralPath $file.FullName -Raw).Contains("getPlayerProfession("))
    {
        $singularConsumers += $relative
    }
}
Assert-Contract ($singularConsumers.Count -eq
        [int]$contract.expected.externalSingularCompatibilityConsumers -and
    $singularConsumers[0] -ceq
        "dsrc/sku.0/sys.server/compiled/game/script/item/gcw_buff_banner/banner_buff_manager.java") `
    "p14.retained-vendor.singular-consumer.banner-only"

$vendor = [string]$texts.vendor
$vendorShow = Get-SourceSlice $vendor `
    "public int showInventorySUI(" `
    "public int[] getQualifiedPrecuProfessionInventories("
$vendorQualification = Get-SourceSlice $vendor `
    "public int[] getQualifiedPrecuProfessionInventories(" `
    "public int handlePrecuProfessionInventorySelect("
$vendorSelection = Get-SourceSlice $vendor `
    "public int handlePrecuProfessionInventorySelect(" `
    "public int showNonClassInventory("
Assert-Contract (-not $vendorShow.Contains("getPlayerProfession(") -and
    $vendorShow.Contains("factionInventory = IMPERIAL") -and
    $vendorShow.Contains("factionInventory = REBEL") -and
    $vendorShow.Contains("qualifiedProfessions.length == 1") -and
    $vendorShow.Contains("qualifiedProfessions.length > 1") -and
    $vendorShow.Contains("handlePrecuProfessionInventorySelect") -and
    $vendorShow.Contains("containerList[utils.NO_PROFESSION]")) `
    "p14.retained-vendor.multi-profession-selector"
Assert-Contract ($vendorQualification.Contains("profession = utils.COMMANDO") -and
    $vendorQualification.Contains("profession <= utils.ENTERTAINER") -and
    $vendorQualification.Contains("utils.isPrecuRetainedItemClass(player, profession)") -and
    $vendor.Contains("professionNames[i] = utils.getPrecuRetainedItemClassName") -and
    ([regex]::Matches($vendor, 'utils\.isPrecuRetainedItemClass\(player, profession\)').Count -eq
        [int]$contract.expected.qualifiedVendorRevalidationCalls)) `
    "p14.retained-vendor.precu-item-profession-admission"
Assert-Contract ($vendorSelection.Contains("selectedRow >= qualifiedProfessions.length") -and
    $vendorSelection.Contains("!utils.isPrecuRetainedItemClass(player, profession)") -and
    $vendorSelection.Contains("profession >= containerList.length") -and
    $vendorSelection.Contains("containerList[profession]")) `
    "p14.retained-vendor.selection-revalidated"
Assert-Contract ($vendor.Contains("(reqClass == 0 || reqClass == idx)") -and
    $vendor.Contains("public static final int IMPERIAL = 10;") -and
    $vendor.Contains("public static final int REBEL = 11;")) `
    "p14.retained-vendor.common-and-faction-containers-preserved"

foreach ($name in @("meatlumpVendor", "novaOrionVendor"))
{
    $text = [string]$texts[$name]
    Assert-Contract (-not $text.Contains("getPlayerProfession(") -and
        ([regex]::Matches($text, 'containerList\[utils\.NO_PROFESSION\]').Count -eq 2)) `
        "p14.retained-vendor.$name.all-class"
}

$heroicClasses = @(Get-VendorTableClasses $sourcePaths.heroicVendorTable |
    Sort-Object -Unique)
$expectedHeroicClasses = @($contract.expected.heroicVendorClasses | ForEach-Object { [int]$_ })
Assert-Contract (($heroicClasses -join ',') -ceq ($expectedHeroicClasses -join ',')) `
    "p14.retained-vendor.heroic-class-index-set"
$allClassTablesValid = $true
foreach ($name in @("meatlumpVendorTable", "corelliaTimesVendorTable", "novaVendorTable", "orionVendorTable"))
{
    $classes = @(Get-VendorTableClasses $sourcePaths[$name])
    if ($classes.Count -lt 1 -or @($classes | Where-Object { $_ -ne 0 }).Count -ne 0)
    {
        $allClassTablesValid = $false
    }
}
Assert-Contract $allClassTablesValid "p14.retained-vendor.all-class-table-boundary"

$banner = Get-SourceSlice ([string]$texts.banner) `
    "public String getBannerBuff(" `
    "public int buffPlayers("
Assert-Contract ($banner.Contains("switch (utils.getPlayerProfession(player))") -and
    $banner.Contains('return "banner_buff_trader";') -and
    $banner.Contains("return null;") -and
    -not $banner.Contains("default:")) `
    "p14.retained-vendor.banner-no-false-trader-default"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.retained-vendor.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.retained-vendor.direct-source-pin"
    $compiledHashesValid = $true
    foreach ($property in $contract.buildEvidence.compiledClassSha256.PSObject.Properties)
    {
        if ([string]$property.Value -notmatch '^[a-f0-9]{64}$') { $compiledHashesValid = $false }
    }
    Assert-Contract ($compiledHashesValid -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.retained-vendor.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.retained-vendor.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.retained-vendor.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU retained-vendor profession authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU retained-vendor profession authority contract passed."
