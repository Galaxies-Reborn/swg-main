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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuPoliticianProgressionAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$serverGame = Join-Path $source "dsrc/sku.0/sys.server/compiled/game"
$sharedGame = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game"
$scriptRoot = Join-Path $serverGame "script"
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
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$skillPath = Join-Path $scriptRoot "library/skill.java"
$skillDataPath = Join-Path $sharedGame "datatables/skill/skills.tab"
Assert-Contract (Test-Path -LiteralPath $skillPath -PathType Leaf) "p14.politician.source.skill.exists"
Assert-Contract (Test-Path -LiteralPath $skillDataPath -PathType Leaf) "p14.politician.source.skill-data.exists"
$skillHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant()
Assert-Contract ($skillHash -ceq [string]$contract.buildEvidence.sourceSha256."library/skill.java") "p14.politician.source.skill.authenticated"

$skillSource = Get-Content -LiteralPath $skillPath -Raw
$bulkGrant = Get-SourceSlice $skillSource "public static void grantAllPoliticianSkills" "public static int getProfessionPhase"
$purchase = Get-SourceSlice $skillSource "public static boolean purchaseSkill" "public static boolean hasRequiredSkillsForSkillPurchase"
Assert-Contract (-not $bulkGrant.Contains("grantSkill") -and
    -not $bulkGrant.Contains("setObjVar") -and
    -not $bulkGrant.Contains("removeObjVar") -and
    -not $bulkGrant.Contains("revokeSkill") -and
    -not $bulkGrant.Contains("social_politician_")) "p14.politician.bulk-grant.no-op"
Assert-Contract ($purchase.Contains("getAvailableSkillPoints(player)") -and
    $purchase.Contains("hasRequiredSkillsForSkillPurchase(player, skillName)") -and
    $purchase.Contains("hasRequiredXpForSkillPurchase(player, skillName)") -and
    $purchase.Contains("grantSkillToPlayer(player, skillName)") -and
    $purchase.Contains("deductXpCostForSkillPurchase(player, skillName)")) "p14.politician.generic-purchase-authority-preserved"

$bulkGrantSites = 0
$bulkGrantConsumers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($javaFile in Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter "*.java" -File)
{
    $text = Get-Content -LiteralPath $javaFile.FullName -Raw
    $count = [regex]::Matches($text, 'skill\.grantAllPoliticianSkills\(').Count
    if ($count -gt 0)
    {
        $bulkGrantSites += $count
        [void]$bulkGrantConsumers.Add($javaFile.FullName)
    }
}
Assert-Contract ($bulkGrantSites -eq [int]$contract.diagnosis.automaticBulkGrantCallSites -and
    $bulkGrantConsumers.Count -eq [int]$contract.diagnosis.automaticBulkGrantConsumerFiles) "p14.politician.bulk-grant-call-inventory"

$politicianRows = @(Import-SwgTab -Path $skillDataPath | Where-Object { [string]$_.NAME -like "social_politician*" })
$politicianBoxes = @($politicianRows | Where-Object { [string]$_.NAME -cne "social_politician" })
$branchRows = @($politicianRows | Where-Object { [string]$_.NAME -match '^social_politician_(?:fiscal|martial|civic|urban)_0[1-4]$' })
$politicalXpRows = @($branchRows | Where-Object { [string]$_.XP_TYPE -ceq "political" })
Assert-Contract ($politicianRows.Count -eq [int]$contract.diagnosis.politicianSkillRows -and
    $politicianBoxes.Count -eq [int]$contract.diagnosis.politicianSkillBoxes -and
    $branchRows.Count -eq [int]$contract.diagnosis.politicianBranchRows -and
    $politicalXpRows.Count -eq [int]$contract.diagnosis.politicianPoliticalXpRows) "p14.politician.skill-row-inventory"

$novice = @($politicianRows | Where-Object { [string]$_.NAME -ceq "social_politician_novice" })
$master = @($politicianRows | Where-Object { [string]$_.NAME -ceq "social_politician_master" })
Assert-Contract ($novice.Count -eq 1 -and [int]$novice[0].MONEY_REQUIRED -eq [int]$contract.diagnosis.noviceCreditCost -and
    $master.Count -eq 1 -and [int]$master[0].MONEY_REQUIRED -eq [int]$contract.diagnosis.masterCreditCost -and
    [string]$master[0].SKILLS_REQUIRED -ceq "social_politician_fiscal_04,social_politician_martial_04,social_politician_civic_04,social_politician_urban_04") "p14.politician.novice-master-authority"
Assert-Contract ((@($branchRows | ForEach-Object { [int]$_.XP_COST } | Sort-Object -Unique) -join ',') -ceq
        (@($contract.diagnosis.branchXpCosts) -join ',') -and
    (@($branchRows | ForEach-Object { [int]$_.MONEY_REQUIRED } | Sort-Object -Unique) -join ',') -ceq
        (@($contract.diagnosis.branchCreditCosts) -join ',')) "p14.politician.branch-cost-authority"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $skillDataPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillDataSha256) "p14.politician.skill-data-preserved"

foreach ($property in $contract.continuityEvidence.consumerSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.politician.consumer.$($property.Name).unchanged"
}
$cityGateSites = 0
foreach ($property in $contract.continuityEvidence.cityAdmissionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.politician.city.$($property.Name).unchanged"
    $cityGateSites += [regex]::Matches((Get-Content -LiteralPath $path -Raw), 'hasSkill\([^\r\n]*"social_politician_novice"').Count
}
Assert-Contract ($cityGateSites -eq [int]$contract.diagnosis.cityNoviceGateSites) "p14.politician.city-novice-gates-preserved"
foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.politician.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "p14.politician.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) "p14.politician.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256."library/skill.class" -cne "pending" -and
        [string]$contract.buildEvidence.fullJavaCompile -like "passed*") "p14.politician.compiled-evidence"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) "p14.politician.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) "p14.politician.source-status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuPoliticianProgressionAuthority)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) "p14.politician.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU Politician progression authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU Politician progression authority contract passed."
