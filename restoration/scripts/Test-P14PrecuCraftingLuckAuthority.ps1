[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuCraftingLuckAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$skillsPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
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
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$relativeSources = [ordered]@{
    "script.library.craftinglib" = "library/craftinglib.java"
    "script.library.luck" = "library/luck.java"
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.crafting-luck.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) "p14.crafting-luck.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$expectedTargets = @($relativeSources.Values | ForEach-Object {
    "sku.0/sys.server/compiled/game/script/$_"
} | Sort-Object)
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    ($targets -join "`n") -ceq ($expectedTargets -join "`n")) "p14.crafting-luck.overlay.target-set"
$targetSetText = ($targets -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $targetSetText) -ceq [string]$contract.buildEvidence.sourceSetSha256) `
    "p14.crafting-luck.source-set.authenticated"

$texts = [ordered]@{}
foreach ($entry in $relativeSources.GetEnumerator())
{
    $path = Join-Path $scriptRoot $entry.Value
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.crafting-luck.source.$($entry.Key).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$entry.Key] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$entry.Key].Value
    Assert-Contract ($hash -ceq $expectedHash) "p14.crafting-luck.source.$($entry.Key).authenticated"
}

$contentRecords = [System.Collections.Generic.List[string]]::new()
foreach ($target in $targets)
{
    $targetPath = Join-Path (Join-Path $source "dsrc") $target
    $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
    $contentRecords.Add("$target=$targetHash")
}
Assert-Contract ((Get-TextSha256 (($contentRecords -join "`n") + "`n")) -ceq
    [string]$contract.buildEvidence.sourceContentSha256) "p14.crafting-luck.source-content.authenticated"

$luckText = [string]$texts["script.library.luck"]
$craftingText = [string]$texts["script.library.craftinglib"]
$genericBody = Get-SourceSlice $luckText `
    "public static boolean isLucky(obj_id player, float mod, boolean showFlyText)" `
    "public static int getPrecuCraftingLuckRoll"
$craftingLuckBody = Get-SourceSlice $luckText `
    "public static int getPrecuCraftingLuckRoll" `
    "public static void showLuckyFlyText"
$assemblyBody = Get-SourceSlice $craftingText `
    "public static int calcSkillDesignAssemblyCheck" `
    "public static float calcAssemblySuccessAttributeMultiplier"
$experimentationBody = Get-SourceSlice $craftingText `
    "public static void calcSuccessPerAttributeExperimentation" `
    "public static void storeTissueDataAsObjvars"

$abiOverloads = ([regex]::Matches($luckText, 'public static boolean isLucky\(')).Count
Assert-Contract ($abiOverloads -eq [int]$contract.expected.retainedGenericAbiOverloads -and
    $genericBody.Contains("return false;") -and
    -not $genericBody.Contains("getLevel") -and
    -not $genericBody.Contains("luck_modified") -and
    -not $genericBody.Contains("rand(")) "p14.crafting-luck.generic-nge-proc.fail-closed"
Assert-Contract ($craftingLuckBody.Contains('getSkillStatisticModifier(player, "luck")') -and
    $craftingLuckBody.Contains('getSkillStatisticModifier(player, "force_luck")') -and
    $craftingLuckBody.Contains("Math.max(0") -and
    $craftingLuckBody.Contains("return rand(0, totalLuck);") -and
    -not $craftingLuckBody.Contains("getLevel") -and
    -not $craftingLuckBody.Contains("luck_modified")) "p14.crafting-luck.skill-roll.authenticated"

$craftingConsumers = ([regex]::Matches($craftingText, 'luck\.getPrecuCraftingLuckRoll\(player\)')).Count
$forcedLuckyCrafting = ([regex]::Matches($craftingText, 'luck\.isLucky\(')).Count
Assert-Contract ($craftingConsumers -eq [int]$contract.expected.craftingLuckConsumers -and
    $forcedLuckyCrafting -eq [int]$contract.expected.forcedNgeCraftingCriticalProcs) `
    "p14.crafting-luck.crafting-consumers.exact"
Assert-Contract ($assemblyBody.IndexOf("modifiedDieRoll += luck.getPrecuCraftingLuckRoll(player);") -gt
        $assemblyBody.IndexOf("float modifiedDieRoll") -and
    $assemblyBody.IndexOf("if (dieRoll >= criticalSuccess)") -gt
        $assemblyBody.IndexOf("modifiedDieRoll += luck.getPrecuCraftingLuckRoll(player);") -and
    $assemblyBody.Contains("else if (modifiedDieRoll > greatSuccess)")) "p14.crafting-luck.assembly.result-band"
Assert-Contract ($experimentationBody.IndexOf("modifiedSkillRoll += luck.getPrecuCraftingLuckRoll(player);") -gt
        $experimentationBody.IndexOf("float modifiedSkillRoll") -and
    $experimentationBody.IndexOf("if (dieRoll >= criticalSuccess)") -gt
        $experimentationBody.IndexOf("modifiedSkillRoll += luck.getPrecuCraftingLuckRoll(player);") -and
    $experimentationBody.Contains("successPointScale = 1.15f;") -and
    -not $experimentationBody.Contains("successPointScale = 1.20f;")) "p14.crafting-luck.experimentation.result-band"

$genericConsumerPaths = @(
    "library/healing.java",
    "library/smuggler.java",
    "player/player_utility.java",
    "library/stealth.java"
)
$genericConsumerText = ($genericConsumerPaths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $scriptRoot $_) -Raw
}) -join "`n"
$genericCalls = ([regex]::Matches($genericConsumerText, 'luck\.isLucky\(')).Count
Assert-Contract ($genericCalls -eq [int]$contract.expected.genericNgeLuckyCallSitesFailClosed) `
    "p14.crafting-luck.noncrafting-consumers.fail-closed-centrally"

$skillsText = Get-Content -LiteralPath $skillsPath -Raw
$forceLuckBoxes = ([regex]::Matches($skillsText,
    '(?m)^force_sensitive_heightened_senses_luck_0[1-4]\t[^\r\n]*\tforce_luck=1(?:\t|$)')).Count
Assert-Contract ($forceLuckBoxes -eq [int]$contract.expected.forceLuckSkillBoxes) `
    "p14.crafting-luck.force-luck-skill-boxes.preserved"

$allMilestoneText = $luckText + "`n" + $craftingText
Assert-Contract (-not $allMilestoneText.Contains("getLevel(player)") -and
    -not $allMilestoneText.Contains('"luck_modified"')) "p14.crafting-luck.nge-authority.absent"

$missionMap = [ordered]@{
    "mission_terminal.java" = (Join-Path $scriptRoot "systems/missions/base/mission_terminal.java")
    "mission_base.java" = (Join-Path $scriptRoot "systems/missions/base/mission_base.java")
    "missions.java" = (Join-Path $scriptRoot "library/missions.java")
}
foreach ($mission in $missionMap.GetEnumerator())
{
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $mission.Value).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$contract.continuityEvidence.missionSourceSha256.($mission.Key)) `
        "p14.crafting-luck.mission-source.$($mission.Key).unchanged"
}

if ($failures.Count -gt 0)
{
    throw "P14 PRE-CU crafting Luck authority contract failed: $($failures -join ', ')"
}

Write-Host "P14 PRE-CU crafting Luck authority contract passed."
