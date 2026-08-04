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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuOpenWorldBattlefieldArtisanAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$battlefieldPath = Join-Path $source ([string]$contract.sourceFiles.battlefield)
$playerBattlefieldPath = Join-Path $source ([string]$contract.sourceFiles.playerBattlefield)
$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skills)
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
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$sourcePaths = [ordered]@{
    battlefield = $battlefieldPath
    playerBattlefield = $playerBattlefieldPath
    skills = $skillsPath
}
$texts = @{}
foreach ($name in $sourcePaths.Keys)
{
    $path = $sourcePaths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.open-world-battlefield.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) "p14.open-world-battlefield.source.$name.authenticated"
    }
}

$battlefield = [string]$texts.battlefield
$playerBattlefield = [string]$texts.playerBattlefield
$admission = Get-SourceSlice $battlefield `
    "public static boolean canBuildBattlefieldStructure(" `
    "public static boolean canBuildReinforcement("
$artisanChecks = ([regex]::Matches($admission, 'hasSkill[(]player, "crafting_artisan_novice"[)]')).Count
$traderChecks = ([regex]::Matches($admission, 'utils[.]isProfession[(]player, utils[.]TRADER[)]')).Count
Assert-Contract ($artisanChecks -eq [int]$contract.expected.artisanSkillChecksInAdmissionMethod -and
    $traderChecks -eq [int]$contract.expected.ngeTraderProfessionChecksInAdmissionMethod) `
    "p14.open-world-battlefield.precu-artisan-authority"
Assert-Contract ($admission.Contains("master_object == null") -and
    $admission.Contains("player == null") -and
    $admission.Contains("pvpBattlefieldGetFaction(player, bf)") -and
    $admission.Contains("factions.getFactionNameByHashCode(faction_id)") -and
    $admission.Contains("isNearBattlefieldConstructor(master_object, loc, faction)") -and
    $admission.Contains("isBattlefieldActive(master_object)")) `
    "p14.open-world-battlefield.admission-rules-preserved"
Assert-Contract ($admission.Contains("You must have skill as an artisan") -and
    $admission.Contains("constructor owned by your faction") -and
    $admission.Contains("only build in an active battlefield")) `
    "p14.open-world-battlefield.player-feedback-preserved"

$callSites = ([regex]::Matches($playerBattlefield,
    'battlefield[.]canBuildBattlefieldStructure[(]master_object, self[)]')).Count
Assert-Contract ($callSites -eq [int]$contract.expected.activeAdmissionCallSites -and
    $playerBattlefield.Contains("public int msgBuildStructureSelected(") -and
    $playerBattlefield.Contains("public int placeBattlefieldStructure(") -and
    $playerBattlefield.Contains("battlefield.getFactionBuildPoints(master_object, faction)") -and
    $playerBattlefield.Contains("battlefield.startBuildingConstruction(")) `
    "p14.open-world-battlefield.production-call-path"
Assert-Contract ($battlefield.Contains("decrementFactionBuildPoints(") -and
    $battlefield.Contains("public static boolean repairBattlefieldStructure(") -and
    $battlefield.Contains("public static obj_id buildReinforcement(") -and
    $battlefield.Contains("VAR_REPAIR_COST") -and $battlefield.Contains("VAR_BUILD_RATE")) `
    "p14.open-world-battlefield.downstream-rules-preserved"

$skills = @(Import-Csv -LiteralPath $skillsPath -Delimiter ([char]9))
$artisan = @($skills | Where-Object { [string]$_.NAME -ceq "crafting_artisan_novice" })
Assert-Contract ($artisan.Count -eq 1 -and [string]$artisan[0].PARENT -ceq "crafting_artisan") `
    "p14.open-world-battlefield.novice-artisan-skill-box-authenticated"

$queuedContractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuQueuedBattlefieldRetirement)
$queuedContract = Get-Content -LiteralPath $queuedContractPath -Raw | ConvertFrom-Json
Assert-Contract ([string]$queuedContract.status -ceq "ready" -and
    [bool]$contract.expected.postNgeQueuedBattlefieldRuntimeRetired) `
    "p14.open-world-battlefield.queued-battlefield-retirement-continuity"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.open-world-battlefield.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.open-world-battlefield.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.battlefield -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.open-world-battlefield.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.open-world-battlefield.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.open-world-battlefield.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU open-world battlefield Artisan authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU open-world battlefield Artisan authority contract passed."
