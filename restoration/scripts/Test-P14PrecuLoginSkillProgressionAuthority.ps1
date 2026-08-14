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
    ([string]$manifest.contracts.p14PrecuLoginSkillProgressionAuthority)) -Raw | ConvertFrom-Json
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

$basePlayerPath = Join-Path $scriptRoot "player/base/base_player.java"
$skillPath = Join-Path $scriptRoot "library/skill.java"
$trainerPath = Join-Path $scriptRoot "npc/skillteacher/skillteacher.java"
$skillDataPath = Join-Path $sharedGame "datatables/skill/skills.tab"
foreach ($path in @($basePlayerPath, $skillPath, $trainerPath, $skillDataPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.login-skill.source.$([System.IO.Path]::GetFileName($path)).exists"
}
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $basePlayerPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."player/base/base_player.java") "p14.login-skill.base-player.authenticated"

$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$onLogin = Get-SourceSlice $basePlayer "public int OnLogin(obj_id self)" "public int disconnectPlayerCtsCompletedOrInProgress"
Assert-Contract ($onLogin.Length -gt 0) "p14.login-skill.on-login.isolated"
Assert-Contract (-not $onLogin.Contains("needsPrerequisites") -and
    -not $onLogin.Contains("getSkillPrerequisiteSkills") -and
    -not $onLogin.Contains("grantSkill(self, prereqs[j])") -and
    -not $onLogin.Contains("attempts < 100")) "p14.login-skill.recursive-repair-retired"
Assert-Contract ([regex]::Matches($onLogin, '\bgrantSkill\s*\(').Count -eq
    [int]$contract.expected.loginRawSkillGrantSites) "p14.login-skill.raw-login-grants-retired"
Assert-Contract ($onLogin.Contains('revokeSkill(self, "demo_combat")') -and
    $onLogin.Contains("slicing.clearSlicing(self)") -and
    $onLogin.Contains("hq.ejectEnemyFactionOnLogin(self)")) "p14.login-skill.unrelated-login-cleanup-preserved"

$skillSource = Get-Content -LiteralPath $skillPath -Raw
$purchase = Get-SourceSlice $skillSource "public static boolean purchaseSkill" "public static boolean hasRequiredSkillsForSkillPurchase"
Assert-Contract ($purchase.Contains("getAvailableSkillPoints(player)") -and
    $purchase.Contains("hasRequiredSkillsForSkillPurchase(player, skillName)") -and
    $purchase.Contains("hasRequiredXpForSkillPurchase(player, skillName)") -and
    $purchase.Contains("grantSkillToPlayer(player, skillName)") -and
    $purchase.Contains("deductXpCostForSkillPurchase(player, skillName)")) "p14.login-skill.purchase-authority-preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillLibrarySha256) "p14.login-skill.skill-library-preserved"

$trainerSource = Get-Content -LiteralPath $trainerPath -Raw
Assert-Contract ($trainerSource.Contains('dataTableGetInt(skill.TBL_SKILL, skillRow, "MONEY_REQUIRED")') -and
    $trainerSource.Contains('money.requestPayment(speaker, self, cost, "attemptedPayment", d, true)') -and
    $trainerSource.Contains("skill.purchaseSkill(player, skillName)")) "p14.login-skill.trainer-credit-authority-preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $trainerPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillTrainerSha256) "p14.login-skill.trainer-source-preserved"

$skillRows = @(Import-SwgTab -Path $skillDataPath)
$withPrerequisites = @($skillRows | Where-Object { [string]$_.SKILLS_REQUIRED -ne "" })
$withXp = @($skillRows | Where-Object { [int]$_.XP_COST -gt 0 })
$withMoney = @($skillRows | Where-Object { [int]$_.MONEY_REQUIRED -gt 0 })
Assert-Contract ($skillRows.Count -eq [int]$contract.diagnosis.skillTableRows -and
    $withPrerequisites.Count -eq [int]$contract.diagnosis.rowsWithPrerequisites -and
    $withXp.Count -eq [int]$contract.diagnosis.rowsWithXpCost -and
    $withMoney.Count -eq [int]$contract.diagnosis.rowsWithMoneyCost) "p14.login-skill.skill-table-gate-inventory"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $skillDataPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.continuityEvidence.skillDataSha256) "p14.login-skill.skill-data-preserved"

Assert-Contract ($basePlayer.Contains('characterData.put("skills", getSkillListingForPlayer(self));') -and
    $basePlayer.Contains("grantSkill(self, transferredSkill)")) "p14.login-skill.cts-skill-box-transfer-preserved"
foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.login-skill.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "p14.login-skill.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) "p14.login-skill.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256."player/base/base_player.class" -cne "pending" -and
        [string]$contract.buildEvidence.fullJavaCompile -like "passed*") "p14.login-skill.compiled-evidence"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) "p14.login-skill.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.login-skill.source-status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuLoginSkillProgressionAuthority)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.login-skill.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU login skill progression authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU login skill progression authority contract passed."
