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
    ([string]$manifest.contracts.p14PostP14VeteranRespecItemRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$game = Join-Path $dsrc "sku.0/sys.server/compiled/game"
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

$paths = [ordered]@{
    "player/live_conversions.java" = "script/player/live_conversions.java"
    "systems/veteran_reward/character_respec_reset_device.java" = "script/systems/veteran_reward/character_respec_reset_device.java"
    "systems/veteran_reward/respec_voucher_deed.java" = "script/systems/veteran_reward/respec_voucher_deed.java"
    "object/tangible/veteran_reward/character_respec_reset_device.tpf" = "object/tangible/veteran_reward/character_respec_reset_device.tpf"
    "object/tangible/veteran_reward/respec_voucher_deed.tpf" = "object/tangible/veteran_reward/respec_voucher_deed.tpf"
    "datatables/veteran_rewards/items.tab" = "datatables/veteran_rewards/items.tab"
    "datatables/item/master_item/master_item.tab" = "datatables/item/master_item/master_item.tab"
}
$text = @{}
foreach ($entry in $paths.GetEnumerator())
{
    $path = Join-Path $game $entry.Value
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.veteran-respec.$($entry.Key).exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
            "p14.veteran-respec.$($entry.Key).authenticated"
        $text[$entry.Key] = Get-Content -LiteralPath $path -Raw
    }
}

$directCommit = (& git -C $dsrc rev-parse HEAD).Trim()
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($LASTEXITCODE -eq 0 -and $dsrcPin.Count -eq 1 -and
    $directCommit -ceq [string]$contract.buildEvidence.dsrcSourceCommit -and
    [string]$dsrcPin[0].commit -ceq $directCommit) "p14.veteran-respec.direct-source-pin"

$families = @(
    [pscustomobject]@{
        Key = "systems/veteran_reward/character_respec_reset_device.java"
        Constant = "POST_P14_VETERAN_RESPEC_RESET_RETIRED = true"
        Cleanup = "retirePostP14VeteranRespecResetScript(self)"
        Script = "systems.veteran_reward.character_respec_reset_device"
        Callback = $null
    },
    [pscustomobject]@{
        Key = "systems/veteran_reward/respec_voucher_deed.java"
        Constant = "POST_P14_VETERAN_RESPEC_VOUCHER_RETIRED = true"
        Cleanup = "retirePostP14VeteranRespecVoucherScript(self)"
        Script = "systems.veteran_reward.respec_voucher_deed"
        Callback = "handleRespecChoice"
    }
)
$lifecycle = 0
$menus = 0
$callbacks = 0
foreach ($family in $families)
{
    $body = [string]$text[$family.Key]
    Assert-Contract ($body.Contains($family.Constant) -and $body.Contains($family.Script)) `
        "p14.veteran-respec.$($family.Key).retirement-authority"
    foreach ($method in @("OnAttach", "OnInitialize"))
    {
        $surface = Get-BracedSurface $body "public int $method"
        if ($surface.Contains($family.Cleanup)) { $lifecycle++ }
    }
    foreach ($method in @("OnObjectMenuRequest", "OnObjectMenuSelect"))
    {
        $surface = Get-BracedSurface $body "public int $method"
        if ($surface.Contains($family.Cleanup) -and
            -not $surface.Contains("addRootMenu(") -and
            -not $surface.Contains("destroyObject(") -and
            -not $surface.Contains("setObjVar(") -and
            -not $surface.Contains("sui.msgbox(")) { $menus++ }
    }
    if ($null -ne $family.Callback)
    {
        $surface = Get-BracedSurface $body "public int $($family.Callback)"
        if ($surface.Contains($family.Cleanup) -and
            -not $surface.Contains("destroyObject(") -and
            -not $surface.Contains("setObjVar(") -and
            -not $surface.Contains("sui.")) { $callbacks++ }
    }
    Assert-Contract (-not $body.Contains("destroyObject(") -and
        -not $body.Contains("setObjVar(") -and
        -not $body.Contains("addRootMenu(") -and
        -not $body.Contains("sui.msgbox(")) "p14.veteran-respec.$($family.Key).mutations-inert"
}
Assert-Contract ($families.Count -eq [int]$contract.expected.retiredScriptFamilies -and
    $lifecycle -eq [int]$contract.expected.lifecycleCleanupEntrypoints) `
    "p14.veteran-respec.lifecycle-cleanup"
Assert-Contract ($menus -eq [int]$contract.expected.inertMenuEntrypoints -and
    $callbacks -eq [int]$contract.expected.inertSuiCallbacks) "p14.veteran-respec.player-surfaces-inert"

$live = [string]$text["player/live_conversions.java"]
$migration = Get-BracedSurface $live "public static void retirePostNgePlayerMigrationState"
$stateCleanup = 0
foreach ($name in @($contract.inventory.retiredPersistedState))
{
    if ($migration.Contains("removeObjVar(player, `"$name`")")) { $stateCleanup++ }
}
Assert-Contract ($stateCleanup -eq [int]$contract.expected.staleMigrationStateCleanupEntries) `
    "p14.veteran-respec.persisted-state-cleanup"

$resetTemplate = [string]$text["object/tangible/veteran_reward/character_respec_reset_device.tpf"]
$voucherTemplate = [string]$text["object/tangible/veteran_reward/respec_voucher_deed.tpf"]
$table = [string]$text["datatables/veteran_rewards/items.tab"]
$masterItems = [string]$text["datatables/item/master_item/master_item.tab"]
$templateBindings = 0
if ($resetTemplate.Contains('systems.veteran_reward.character_respec_reset_device')) { $templateBindings++ }
if ($voucherTemplate.Contains('systems.veteran_reward.respec_voucher_deed')) { $templateBindings++ }
$rewardRows = @([regex]::Matches($table, '(?m)^respec_voucher\t')).Count
$masterItemRows = @([regex]::Matches($masterItems, '(?m)^vet_reward_respec_reset\t')).Count
Assert-Contract ($templateBindings -eq [int]$contract.expected.retainedTemplateBindings -and
    $rewardRows -eq [int]$contract.expected.retainedVeteranRewardRows -and
    $masterItemRows -eq [int]$contract.expected.retainedMasterItemRows) `
    "p14.veteran-respec.compatibility-assets-retained"

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.fullServerBuild -like "passed*" -and
        [string]$contract.buildEvidence.deployedBytecodeAudit -like "passed*" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        @($contract.requiredBeforeReady).Count -eq 0) "p14.veteran-respec.ready-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status -and
        [string]$contract.buildEvidence.result -ceq "passed") "p14.veteran-respec.source-status"
}

if ($failures.Count -gt 0)
{
    throw "Post-Publish-14 veteran respec item retirement failed: $($failures -join ', ')"
}
Write-Host "Post-Publish-14 veteran respec item retirement passed."
