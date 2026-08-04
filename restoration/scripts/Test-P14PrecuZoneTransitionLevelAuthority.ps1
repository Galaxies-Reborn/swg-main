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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuZoneTransitionLevelAuthority)
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
        "p14.zone-transition.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) `
            "p14.zone-transition.source.$name.authenticated"
    }
}

$transition = [string]$texts.transition
$permission = Get-SourceSlice $transition `
    "public static boolean hasPermissionForZone(" `
    "public static void notifyPlayerOfInvalidPermission("
$rawLevelReads = [regex]::Matches($permission,
    '(?<![A-Za-z0-9_\.])getLevel\s*\(\s*player\s*\)').Count
$precuReads = [regex]::Matches($permission,
    'skill\.getPrecuEncounterDifficulty\s*\(\s*player\s*\)').Count
$levelBranches = [regex]::Matches($permission,
    'parse\[0\]\.equals\("level"\)').Count
Assert-Contract ($rawLevelReads -eq [int]$contract.expected.rawPlayerLevelReadsInPermission -and
    $precuReads -eq [int]$contract.expected.precuEncounterDifficultyReadsInPermission -and
    $levelBranches -eq [int]$contract.expected.levelAdmissionBranches) `
    "p14.zone-transition.precu-level-authority"
Assert-Contract ($transition.Contains("public static void zonePlayer(") -and
    $transition.Contains("public static void zonePlayerNoGate(") -and
    ([regex]::Matches($transition, 'hasPermissionForZone\(player, transit, "initialRequiredFlag"\)').Count -eq
        [int]$contract.expected.directTransitionEntryPoints)) `
    "p14.zone-transition.direct-entry-points-preserved"
Assert-Contract ($permission.Contains('parse[0].equals("none")') -and
    $permission.Contains('groundquests.hasCompletedQuest(player, parse[1])') -and
    $permission.Contains('groundquests.isQuestActive(player, parse[1])') -and
    $permission.Contains('space_quest.hasWonQuest(player, parse[1], parse[2])') -and
    $permission.Contains('groundquests.isTaskActive(player, parse[2], parse[3])') -and
    $permission.Contains('utils.playerHasItemByTemplateInInventoryOrEquipped(player, parse[1])') -and
    $permission.Contains('utils.playerHasItemByTemplateWithObjVarInInventoryOrEquipped(player, parse[1], parse[2])') -and
    $permission.Contains('utils.setScriptVar(player, "tempFlag", parse[0])')) `
    "p14.zone-transition.authored-flag-kinds-preserved"

$zoneRows = @(Import-SwgTab -Path $sourcePaths.zoneTable)
$activeLevelRows = @($zoneRows | Where-Object {
    [string]$_.initialRequiredFlag -match '^level:' -or
    [string]$_.finalRequiredFlag -match '^level:'
})
$zoneNames = @($zoneRows | ForEach-Object { [string]$_.zoneLine })
$representativeRoutes = @($contract.expected.representativeRoutes |
    ForEach-Object { [string]$_ })
Assert-Contract ($zoneRows.Count -eq [int]$contract.expected.zoneTransitionRows -and
    $activeLevelRows.Count -eq [int]$contract.expected.activeLevelAdmissionRows) `
    "p14.zone-transition.current-table-boundary"
Assert-Contract (@($representativeRoutes | Where-Object {
    $zoneNames -cnotcontains $_
}).Count -eq 0) "p14.zone-transition.retained-route-surface"
$hunting = @($zoneRows | Where-Object { [string]$_.zoneLine -ceq "kachirho_huntinggrounds" })
$myyydril = @($zoneRows | Where-Object { [string]$_.zoneLine -ceq "deadforest_myyydril" })
$nova = @($zoneRows | Where-Object { [string]$_.zoneLine -ceq "station_nova_orion" })
Assert-Contract ($hunting.Count -eq 1 -and
    [string]$hunting[0].initialRequiredFlag -ceq "has:ep3_hunt_kerssoc_enter_etyyy" -and
    [string]$hunting[0].finalRequiredFlag -ceq "won:ep3_hunt_kerssoc_enter_etyyy" -and
    $myyydril.Count -eq 1 -and [string]$myyydril[0].destination -match '^instance:myyydril_caverns:' -and
    $nova.Count -eq 1 -and [string]$nova[0].destination -match '^instance:nova_orion_station:') `
    "p14.zone-transition.authored-routes-preserved"

$skill = [string]$texts.skill
Assert-Contract ($skill.Contains("public static int getPrecuEncounterDifficulty(") -and
    $skill.Contains("return Math.max(1, getPrecuCombatSkillScore(player));")) `
    "p14.zone-transition.adapter-definition"
Assert-Contract ([string]$texts.movementEntry -match 'transition\.zonePlayer\(self, player\)' -and
    [string]$texts.townshipEntry -match 'transition\.hasPermissionForZone\(player, locations\[i\], "initialRequiredFlag"\)' -and
    [string]$texts.nexusEntry -match 'transition\.hasPermissionForZone\(player, "aurillia_township", "initialRequiredFlag"\)' -and
    [string]$texts.nexusAwayEntry -match 'transition\.hasPermissionForZone\(player, instances\[idx\], "initialRequiredFlag"\)') `
    "p14.zone-transition.production-consumers-preserved"
Assert-Contract ([string]$texts.attributes -match '(?m)^sku\.0/sys\.server/compiled/game/script/library/transition\.java -text\r?$') `
    "p14.zone-transition.no-line-ending-bloat-policy"

$retainedContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuRetainedContentLevelAuthority)) -Raw | ConvertFrom-Json
$encounterContract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuEncounterDifficultyAuthority)) -Raw | ConvertFrom-Json
Assert-Contract ([string]$retainedContract.status -ceq "ready" -and
    [string]$encounterContract.status -ceq "ready") `
    "p14.zone-transition.adjacent-authority-continuity"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.zone-transition.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.zone-transition.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.transition -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledDataSha256.zoneTable -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.compiledDataPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.zone-transition.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.zone-transition.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.zone-transition.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU zone transition level authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU zone transition level authority contract passed."
