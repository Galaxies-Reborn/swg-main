[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgePassiveProfessionRuntimeRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$relativeSourceMap = [ordered]@{
    "library/factions.java" = "library/factions.java"
    "library/skill.java" = "library/skill.java"
    "player/base/base_player.java" = "player/base/base_player.java"
}
$sourceTexts = @{}
$contentRecords = ""
foreach ($entry in $relativeSourceMap.GetEnumerator())
{
    $path = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.passive-profession.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) "p14.passive-profession.source.$($entry.Key).authenticated"
        $contentRecords += "sku.0/sys.server/compiled/game/script/$($entry.Value)=$hash`n"
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $path -Raw
    }
}
Assert-Contract ((Get-TextSha256 $contentRecords) -ceq [string]$contract.buildEvidence.sourceContentSha256) "p14.passive-profession.source-content.authenticated"

$skill = [string]$sourceTexts["library/skill.java"]
foreach ($surface in @(
    (Get-SourceSlice $skill "public static boolean grant(obj_id target" "public static boolean grantSkillToPlayer"),
    (Get-SourceSlice $skill "public static boolean grantSkillToPlayer" "public static int getSkillPointsLeft"),
    (Get-SourceSlice $skill "public static boolean purchaseSkill" "public static boolean hasRequiredSkillsForSkillPurchase")
))
{
    Assert-Contract ($surface.Contains("isRetiredNgeProgressionSkillName(skillName)") -and $surface.Contains("return false;")) "p14.passive-profession.skill-admission.generic-retirement"
}

$player = [string]$sourceTexts["player/base/base_player.java"]
$cleanup = Get-SourceSlice $player "private void retirePostNgePassiveProfessionState" "private void retirePostNgeQueuedBattlefieldPlayerState"
$smugglerCleanup = Get-SourceSlice $player "public void removeSmugglingBuffs" "public int removeSmugglingBonuses"
$retiredBuffNames = @(
    "sm_underworld_boss_1", "sm_underworld_boss_2", "sm_underworld_boss_3",
    "sm_underworld_range_1", "sm_underworld_range_2", "sm_underworld_range_3",
    "sm_underworld_damage_1", "sm_underworld_damage_2", "sm_underworld_damage_3"
)
Assert-Contract ($cleanup.Contains("jedi.JEDI_STANCE") -and $cleanup.Contains("jedi.JEDI_FOCUS") -and $cleanup.Contains("removeSmugglingBuffs(self)")) "p14.passive-profession.central-cleanup"
Assert-Contract (@($retiredBuffNames | Where-Object { -not $smugglerCleanup.Contains('"' + $_ + '"') }).Count -eq 0) "p14.passive-profession.smuggler-buff-inventory"

$initialize = Get-SourceSlice $player "public int OnInitialize(obj_id self)" "public int OnLogin(obj_id self)"
$login = Get-SourceSlice $player "public int OnLogin(obj_id self)" "public int handleDelayedLogin"
$recap = Get-SourceSlice $player "public int OnRecapacitated" "public int handleInstanceTimeRemainingMessage"
Assert-Contract ($initialize.Contains("skill.validateExpertise(self)") -and $initialize.Contains("retirePostNgePassiveProfessionState(self)")) "p14.passive-profession.initialize-cleanup"
Assert-Contract ($login.Contains("retirePostNgePassiveProfessionState(self)") -and -not $login.Contains('messageTo(self, "applyJediStance"') -and -not $login.Contains('messageTo(self, "applySmugglingBonuses"')) "p14.passive-profession.login-cleanup"
Assert-Contract ($recap.Contains("retirePostNgePassiveProfessionState(self)") -and -not $recap.Contains("getLevel(self)")) "p14.passive-profession.recap-cleanup"

$applyJedi = Get-SourceSlice $player "public int applyJediStance" "public int applySmugglingBonuses"
$applySmuggling = Get-SourceSlice $player "public int applySmugglingBonuses" "public int addSmugglingBuffs"
$addSmuggling = Get-SourceSlice $player "public int addSmugglingBuffs" "public int recalcWeaponRange"
foreach ($handler in @($applyJedi, $applySmuggling, $addSmuggling))
{
    Assert-Contract ($handler.Contains("retirePostNgePassiveProfessionState(self)") -and -not $handler.Contains("buff.applyBuff") -and -not $handler.Contains("getSkillStatisticModifier")) "p14.passive-profession.queued-handler-fails-closed"
}

$grant = Get-SourceSlice $player "public int OnSkillGranted" "public int handleStartJediKnightTrials"
$retirementIndex = $grant.IndexOf("skill.isRetiredNgeProgressionSkillName(skillName)", [System.StringComparison]::Ordinal)
$badgeIndex = $grant.IndexOf("badge.grantMasterSkillBadge", [System.StringComparison]::Ordinal)
Assert-Contract ($retirementIndex -ge 0 -and $badgeIndex -gt $retirementIndex -and $grant.Contains("revokeSkillSilent(self, skillName)") -and -not $grant.Contains('skillName.startsWith("expertise_")')) "p14.passive-profession.skill-grant-dominance"
Assert-Contract ($grant.Contains("playClientEffectObj") -and $grant.Contains("showFlyText") -and -not $grant.Contains("getLevel(self)")) "p14.passive-profession.skill-feedback.precu"

$factions = [string]$sourceTexts["library/factions.java"]
Assert-Contract ($factions.Contains("smuggler.checkSmugglerTitleGrants(target, value)") -and $factions.Contains("smuggler.checkRewardQuestGrants(target, value)") -and -not $factions.Contains('messageTo(target, "applySmugglingBonuses"')) "p14.passive-profession.underworld-content-preserved"

$buffTable = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab"
$effectMapping = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/buff/effect_mapping.tab"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $buffTable).Hash.ToLowerInvariant() -ceq [string]$contract.continuityEvidence.buffDataSha256) "p14.passive-profession.buff-data.preserved"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $effectMapping).Hash.ToLowerInvariant() -ceq [string]$contract.continuityEvidence.effectMappingSha256) "p14.passive-profession.effect-mapping.preserved"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path $scriptRoot $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.passive-profession.mission.$($property.Name).unchanged"
}
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ([string]$manifest.sourceMode -ceq "direct-branch" -and $dsrcPin.Count -eq 1 -and [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) "p14.passive-profession.direct-source-pin"
Assert-Contract (@("ready-for-live-verification", "ready") -contains [string]$contract.status) "p14.passive-profession.contract-status"
$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgePassiveProfessionRuntimeRetirement)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) "p14.passive-profession.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Post-NGE passive profession runtime retirement failed: $($failures -join ', ')"
}
Write-Host "Post-NGE passive profession runtime retirement contract passed."
