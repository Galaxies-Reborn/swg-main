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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuRetainedContentLevelAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$scriptRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/script"
$conversationRoot = Join-Path $scriptRoot "conversation"
$themeParkRoot = Join-Path $scriptRoot "theme_park"
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
    try
    {
        return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "p14.retained-level.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.retained-level.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$uniqueTargets = @($targets | Select-Object -Unique)
$conversationTargets = @($targets | Where-Object { $_ -match '/conversation/' })
$themeParkTargets = @($targets | Where-Object { $_ -match '/theme_park/' })
$skillTargets = @($targets | Where-Object { $_ -ceq 'sku.0/sys.server/compiled/game/script/library/skill.java' })
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    $uniqueTargets.Count -eq $targets.Count -and
    $conversationTargets.Count -eq [int]$contract.expected.conversationFiles -and
    $themeParkTargets.Count -eq [int]$contract.expected.themeParkFiles -and
    $skillTargets.Count -eq [int]$contract.expected.skillLibraryFiles) `
    "p14.retained-level.overlay.target-set"
$targetSetText = ($targets -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $targetSetText) -ceq [string]$contract.buildEvidence.sourceSetSha256) `
    "p14.retained-level.source-set.authenticated"

$contentRecords = [System.Collections.Generic.List[string]]::new()
foreach ($target in $targets)
{
    $path = Join-Path $dsrc $target
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.retained-level.source.$target.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $contentRecords.Add("$target=$hash")
    }
}
$contentRecordText = ($contentRecords -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $contentRecordText) -ceq [string]$contract.buildEvidence.sourceContentSha256) `
    "p14.retained-level.source-content.authenticated"

$skillPath = Join-Path $scriptRoot "library/skill.java"
$skillHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant()
Assert-Contract ($skillHash -ceq [string]$contract.buildEvidence.sourceSha256.'script.library.skill') `
    "p14.retained-level.skill-source.authenticated"
$skillText = Get-Content -LiteralPath $skillPath -Raw
$professionScore = Get-FunctionSlice $skillText `
    "public static int getPrecuProfessionSkillScore(" `
    "public static int getPrecuCraftingContentDifficulty("
$craftingDifficulty = Get-FunctionSlice $skillText `
    "public static int getPrecuCraftingContentDifficulty(" `
    "public static int getPrecuEntertainerContentDifficulty("
$entertainerDifficulty = Get-FunctionSlice $skillText `
    "public static int getPrecuEntertainerContentDifficulty(" `
    "public static int getPrecuEncounterDifficulty("
$encounterDifficulty = Get-FunctionSlice $skillText `
    "public static int getPrecuEncounterDifficulty(" `
    "public static int getPrecuGroupCombatDifficulty("

Assert-Contract ($skillText.Contains("public static boolean isPrecuSkillBoxInFamilies(") -and
    $professionScore.Contains("getSkillListingForPlayer(player)") -and
    $professionScore.Contains('dataTableGetInt(TBL_SKILL, learnedSkill, "POINTS_REQUIRED")') -and
    $professionScore.Contains("points *= PRECU_ADVANCED_COMBAT_SKILL_WEIGHT") -and
    $professionScore.Contains("Math.min(score, PRECU_COMBAT_SKILL_SCORE_MAX)") -and
    -not $professionScore.Contains("getLevel(")) `
    "p14.retained-level.skill-box-score-authority"
Assert-Contract ($craftingDifficulty.Contains('{ "crafting_" }') -and
    $craftingDifficulty.Contains('{ "crafting_artisan_" }') -and
    $craftingDifficulty.Contains("getPrecuProfessionSkillScore")) `
    "p14.retained-level.crafting-adapter"
Assert-Contract ($entertainerDifficulty.Contains('"social_entertainer_"') -and
    $entertainerDifficulty.Contains('"social_dancer_"') -and
    $entertainerDifficulty.Contains('"social_musician_"') -and
    $entertainerDifficulty.Contains('"social_imagedesigner_"') -and
    $entertainerDifficulty.Contains("getPrecuProfessionSkillScore")) `
    "p14.retained-level.entertainer-adapter"
Assert-Contract ($encounterDifficulty.Contains("getPrecuCombatSkillScore(player)") -and
    -not $encounterDifficulty.Contains("getPrecuProfessionSkillScore")) `
    "p14.retained-level.combat-adapter-remains-separated"

$surfaceFiles = @(
    Get-ChildItem -LiteralPath @($conversationRoot, $themeParkRoot) -Recurse -Filter "*.java" -File
)
$surfaceTextBuilder = [System.Text.StringBuilder]::new()
$craftingConsumerNames = [System.Collections.Generic.List[string]]::new()
$entertainerConsumerNames = [System.Collections.Generic.List[string]]::new()
foreach ($file in $surfaceFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    [void]$surfaceTextBuilder.Append($text)
    if ($text.Contains("script.library.skill.getPrecuCraftingContentDifficulty("))
    {
        $craftingConsumerNames.Add($file.Name)
    }
    if ($text.Contains("script.library.skill.getPrecuEntertainerContentDifficulty("))
    {
        $entertainerConsumerNames.Add($file.Name)
    }
}
$surfaceText = $surfaceTextBuilder.ToString()
$directPattern = '(?<![A-Za-z0-9_\.])(?:combat\.|utils\.)?getLevel\s*\(\s*(?:player|whoTriggeredMe)\s*\)'
$directCount = [regex]::Matches($surfaceText, $directPattern).Count
$encounterCount = [regex]::Matches($surfaceText, 'script\.library\.skill\.getPrecuEncounterDifficulty\(').Count
$craftingCount = [regex]::Matches($surfaceText, 'script\.library\.skill\.getPrecuCraftingContentDifficulty\(').Count
$entertainerCount = [regex]::Matches($surfaceText, 'script\.library\.skill\.getPrecuEntertainerContentDifficulty\(').Count
Assert-Contract ($directCount -eq [int]$contract.expected.remainingDirectPlayerLevelReads -and
    $encounterCount -eq [int]$contract.expected.encounterDifficultyConsumers -and
    $craftingCount -eq [int]$contract.expected.craftingDifficultyConsumers -and
    $entertainerCount -eq [int]$contract.expected.entertainerDifficultyConsumers) `
    "p14.retained-level.closed-surface-routing"

$expectedCraftingConsumers = @($contract.expected.craftingConsumers | Sort-Object)
$actualCraftingConsumers = @($craftingConsumerNames | Sort-Object)
$expectedEntertainerConsumers = @($contract.expected.entertainerConsumers | Sort-Object)
$actualEntertainerConsumers = @($entertainerConsumerNames | Sort-Object)
Assert-Contract (($expectedCraftingConsumers -join "`n") -ceq ($actualCraftingConsumers -join "`n")) `
    "p14.retained-level.crafting-consumers-bounded"
Assert-Contract (($expectedEntertainerConsumers -join "`n") -ceq ($actualEntertainerConsumers -join "`n")) `
    "p14.retained-level.entertainer-consumers-bounded"

$removedDirectCount = [regex]::Matches($patchText,
    '(?m)^-(?!--).*(?<![A-Za-z0-9_\.])(?:combat\.|utils\.)?getLevel\s*\(\s*(?:player|whoTriggeredMe)\s*\)').Count
Assert-Contract ($removedDirectCount -eq [int]$contract.expected.retiredDirectPlayerLevelReads) `
    "p14.retained-level.overlay-retired-count"

foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $missionPath = switch ($property.Name)
    {
        "mission_terminal.java" { Join-Path $scriptRoot "systems/missions/base/mission_terminal.java" }
        "mission_base.java" { Join-Path $scriptRoot "systems/missions/base/mission_base.java" }
        "missions.java" { Join-Path $scriptRoot "library/missions.java" }
    }
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $missionPath).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.retained-level.mission-source.$($property.Name).unchanged"
}

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.retained-level.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU retained-content level authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU retained-content level authority passed ($($targets.Count) sources, $encounterCount combat, $craftingCount crafting, $entertainerCount entertainer adapters)."
