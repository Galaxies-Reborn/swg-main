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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostP14ArmorConversionRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$conversionRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/item/conversion"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Marker)
{
    $start = $Text.IndexOf($Marker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf('{', $start)
    if ($open -lt 0) { return "" }
    $depth = 1
    for ($index = $open + 1; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

function Test-GuardDominates(
    [string]$Surface,
    [string]$Predicate,
    [string[]]$ProtectedTokens,
    [string]$ReturnToken)
{
    $guard = $Surface.IndexOf($Predicate, [System.StringComparison]::Ordinal)
    if ($guard -lt 0) { return $false }
    $return = $Surface.IndexOf($ReturnToken, $guard, [System.StringComparison]::Ordinal)
    if ($return -lt 0) { return $false }
    foreach ($token in $ProtectedTokens)
    {
        $mutation = $Surface.IndexOf($token, [System.StringComparison]::Ordinal)
        if ($mutation -ge 0 -and $return -gt $mutation) { return $false }
    }
    return $true
}

function Get-Sha256Text([string]$Text)
{
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}

Assert-Contract (Test-Path -LiteralPath $conversionRoot -PathType Container) "p14.armor-conversion.source-root"
$javaSources = @(Get-ChildItem -LiteralPath $conversionRoot -Filter "*.java" | Sort-Object Name)
Assert-Contract ($javaSources.Count -eq [int]$contract.expected.conversionJavaSources) `
    "p14.armor-conversion.source-inventory-count"
$inventoryRecords = @($javaSources | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    "$($_.Name)|$hash"
})
$aggregate = Get-Sha256Text ($inventoryRecords -join "`n")
Assert-Contract ($aggregate -ceq [string]$contract.buildEvidence.conversionSourceInventorySha256 -and
    $aggregate -ceq [string]$contract.buildEvidence.sourceSha256.aggregate) `
    "p14.armor-conversion.source-inventory-authenticated"

$authorityNames = @(
    "armor_base_conversion.java",
    "armor_mand.java",
    "armor_ris.java",
    "armor_wookiee.java",
    "bounty_hunter.java",
    "medicine.java"
)
$texts = @{}
foreach ($name in $authorityNames)
{
    $path = Join-Path $conversionRoot $name
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.armor-conversion.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.$name) `
            "p14.armor-conversion.$name.authenticated"
        $texts[$name] = Get-Content -LiteralPath $path -Raw
    }
}

$directCommit = (& git -C $dsrc rev-parse HEAD).Trim()
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($LASTEXITCODE -eq 0 -and $dsrcPin.Count -eq 1 -and
    $directCommit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
    [string]$dsrcPin[0].commit -ceq $directCommit) "p14.armor-conversion.direct-source-pin"

$base = [string]$texts["armor_base_conversion.java"]
$retiredRefitScripts = @([regex]::Matches($base, '"item\.conversion\.armor_[a-z0-9_]+"') |
    ForEach-Object { $_.Value.Trim('"') } | Sort-Object -Unique)
Assert-Contract ($base.Contains("POST_P14_ARMOR_REFIT_RETIRED = true") -and
    $base.Contains("public static boolean isPostP14ArmorRefitRetired") -and
    $retiredRefitScripts.Count -eq [int]$contract.expected.inheritedArmorRefitScripts) `
    "p14.armor-conversion.refit-retirement-inventory"
$baseLifecycle = @("OnAttach", "OnInitialize", "OnObjectMenuRequest", "OnObjectMenuSelect")
$baseCleanupCount = 0
foreach ($callback in $baseLifecycle)
{
    $surface = Get-BracedSurface $base "public int $callback"
    if ($surface.Contains("retirePostP14ArmorRefitScriptState(self)")) { $baseCleanupCount++ }
}
Assert-Contract ($baseCleanupCount -eq [int]$contract.expected.baseLifecycleCleanupEntrypoints) `
    "p14.armor-conversion.refit-lifecycle-cleanup"

$baseRefit = Get-BracedSurface $base "public void refitArmor"
$baseMenuRequest = Get-BracedSurface $base "public int OnObjectMenuRequest"
$baseMenuSelect = Get-BracedSurface $base "public int OnObjectMenuSelect"
$baseSetPid = Get-BracedSurface $base "public void setWindowPid"
$baseCallbacks = @(
    (Get-BracedSurface $base "public void showConfirmationWindow"),
    (Get-BracedSurface $base "public int handleConfirmationSelect"),
    (Get-BracedSurface $base "public int handleArmorType"),
    (Get-BracedSurface $base "public int handleAssaultSelect"),
    (Get-BracedSurface $base "public int handleBattleSelect"),
    (Get-BracedSurface $base "public int handleReconSelect")
) -join "`n"
$baseForbidden = @("createObject(", "destroyObject(", "copyObjVar(", "setObjVar(",
    "setMaxHitpoints(", "setHitpoints(", "setCraftedId(", "setCrafter(", "setSkillModSockets(",
    "armor.setArmor", "armor.removeArmor", "attachScript(")
$baseMutationCount = 0
foreach ($token in $baseForbidden)
{
    $baseMutationCount += [regex]::Matches($baseRefit, [regex]::Escape($token)).Count
}
Assert-Contract ($baseRefit.Contains("return;") -and
    $baseMutationCount -eq [int]$contract.expected.baseMutationCallsAfterRetirement -and
    -not $baseMenuRequest.Contains("addRootMenu(") -and
    -not $baseMenuSelect.Contains("showConfirmationWindow(") -and
    -not $baseSetPid.Contains("setScriptVar(") -and
    -not $baseCallbacks.Contains("sui.") -and
    -not $baseCallbacks.Contains("refitArmor(")) "p14.armor-conversion.refit-surfaces-inert"

$families = @(
    [pscustomobject]@{ File="armor_mand.java"; Predicate="isPostP14MandalorianDismantleRetired()"; Retire="retirePostP14MandalorianDismantleScript"; Mutator="dismantleMand"; Handler="handleConfirmationSelect"; Script="item.conversion.armor_mand" },
    [pscustomobject]@{ File="armor_ris.java"; Predicate="isPostP14RisDismantleRetired()"; Retire="retirePostP14RisDismantleScript"; Mutator="dismantleRis"; Handler="handleConfirmationSelect"; Script="item.conversion.armor_ris" },
    [pscustomobject]@{ File="armor_wookiee.java"; Predicate="isPostP14WookieeCyberneticResizeRetired()"; Retire="retirePostP14WookieeCyberneticResizeScript"; Mutator="dismantleWookiee"; Handler="handleWookieeConfirmationSelect"; Script="item.conversion.armor_wookiee" },
    [pscustomobject]@{ File="bounty_hunter.java"; Predicate="isPostP14BountyHunterDismantleRetired()"; Retire="retirePostP14BountyHunterDismantleScript"; Mutator="dismantleBountyHunter"; Handler="handleConfirmationSelect"; Script="item.conversion.bounty_hunter" }
)
$lifecycleCleanup = 0
$guardedMenus = 0
$guardedSuiAndMutation = 0
foreach ($family in $families)
{
    $text = [string]$texts[$family.File]
    Assert-Contract ($text.Contains("= true;") -and $text.Contains($family.Script)) `
        "p14.armor-conversion.$($family.File).retirement-predicate"
    foreach ($callback in @("OnAttach", "OnInitialize"))
    {
        $surface = Get-BracedSurface $text "public int $callback"
        if ($surface.Contains("$($family.Retire)(self)")) { $lifecycleCleanup++ }
    }
    $request = Get-BracedSurface $text "public int OnObjectMenuRequest"
    if (Test-GuardDominates $request $family.Predicate @("addRootMenu(") "return SCRIPT_CONTINUE;") { $guardedMenus++ }
    $select = Get-BracedSurface $text "public int OnObjectMenuSelect"
    if (Test-GuardDominates $select $family.Predicate @("showConfirmationWindow(") "return SCRIPT_CONTINUE;") { $guardedMenus++ }
    $show = Get-BracedSurface $text "public void showConfirmationWindow"
    if (Test-GuardDominates $show $family.Predicate @("sui.msgbox(") "return;") { $guardedSuiAndMutation++ }
    $mutator = Get-BracedSurface $text "public void $($family.Mutator)"
    if (Test-GuardDominates $mutator $family.Predicate @("createObject(", "destroyObject(") "return;") { $guardedSuiAndMutation++ }
    $setPid = Get-BracedSurface $text "public void setWindowPid"
    if (Test-GuardDominates $setPid $family.Predicate @("setScriptVar(") "return;") { $guardedSuiAndMutation++ }
    $handler = Get-BracedSurface $text "public int $($family.Handler)"
    if (Test-GuardDominates $handler $family.Predicate @("$($family.Mutator)(") "return SCRIPT_CONTINUE;") { $guardedSuiAndMutation++ }
}
$medicine = [string]$texts["medicine.java"]
foreach ($callback in @("OnAttach", "OnInitialize"))
{
    $surface = Get-BracedSurface $medicine "public int $callback"
    if ($surface.Contains("retirePostP14MedicineConversionScript(self)")) { $lifecycleCleanup++ }
}
Assert-Contract ($families.Count + 1 -eq [int]$contract.expected.standaloneRetirementFamilies -and
    $lifecycleCleanup -eq [int]$contract.expected.standaloneLifecycleCleanupEntrypoints) `
    "p14.armor-conversion.standalone-lifecycle-cleanup"
Assert-Contract ($guardedMenus -eq [int]$contract.expected.guardedStandaloneMenuEntrypoints) `
    "p14.armor-conversion.standalone-menu-guards"
Assert-Contract ($guardedSuiAndMutation -eq [int]$contract.expected.guardedStandaloneSuiAndMutationEntrypoints) `
    "p14.armor-conversion.standalone-sui-and-mutation-guards"

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.fullServerBuild -like "passed*" -and
        [string]$contract.buildEvidence.deployedBytecodeAudit -like "passed*" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        @($contract.requiredBeforeReady).Count -eq 0) "p14.armor-conversion.ready-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status -and
        [string]$contract.buildEvidence.result -ceq "passed") "p14.armor-conversion.source-status"
}

if ($failures.Count -gt 0)
{
    throw "Post-Publish-14 armor conversion retirement failed: $($failures -join ', ')"
}
Write-Host "Post-Publish-14 armor conversion retirement passed."
