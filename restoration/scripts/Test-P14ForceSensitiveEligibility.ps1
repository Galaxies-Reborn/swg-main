[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14ForceSensitiveEligibility)
) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$jediPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.jediLibrary)
$saberPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.saberComponent)
$fixturePath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.liveFixture)
$sadBasicTaskPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.sadBasicTask)
$questTablePath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.questTable)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($path in @($jediPath, $saberPath, $fixturePath, $sadBasicTaskPath, $questTablePath))
{
    if (-not (Test-Path -LiteralPath $path))
    {
        throw "Required Force-sensitive source path is missing: $path"
    }
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

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$scriptRoot = Join-Path $resolvedRoot "dsrc/sku.0/sys.server/compiled/game/script"
$sadCallbackRecords = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading ([string]$contract.inventory.pattern) $scriptRoot --glob "*.java"))
{
    if ($line -notmatch '^(.*?):(\d+):(.*)$')
    {
        throw "Could not parse Force-sensitive killable callback inventory line: $line"
    }
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    if (-not $absolutePath.StartsWith(
            $scriptRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase))
    {
        throw "Force-sensitive killable callback escaped the Java source root: $absolutePath"
    }
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $sadCallbackRecords.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
}
$sadCallbackRecords = @($sadCallbackRecords | Sort-Object)
$sadCallbackPaths = @($sadCallbackRecords | ForEach-Object {
    if ($_ -notmatch '^(.*?):\d+\|') { throw "Could not isolate Force-sensitive callback path: $_" }
    $Matches[1]
} | Sort-Object -Unique)
$expectedSadCallbackPaths = @($contract.inventory.sourcePaths | ForEach-Object { [string]$_ } | Sort-Object)
if ($sadCallbackRecords.Count -ne [int]$contract.inventory.handlers -or
    $sadCallbackRecords.Count -ne [int]$contract.expected.sadKillableCallbacks -or
    $sadCallbackPaths.Count -ne [int]$contract.inventory.sourceFiles -or
    ($sadCallbackPaths -join "`n") -cne ($expectedSadCallbackPaths -join "`n") -or
    (Get-TextSha256 ($sadCallbackRecords -join "`n")) -cne [string]$contract.inventory.inventorySha256 -or
    (Get-TextSha256 ($sadCallbackPaths -join "`n")) -cne [string]$contract.inventory.sourceSetSha256)
{
    throw "Force-sensitive killable callback inventory drifted."
}

$sadBasicTask = Get-Content -LiteralPath $sadBasicTaskPath -Raw
$createdKillable = Get-SourceSlice $sadBasicTask `
    "public int OnCreatedKillableObject(" `
    "public int OnIncapacitatedKillableObject("
$incapacitatedKillable = Get-SourceSlice $sadBasicTask `
    "public int OnIncapacitatedKillableObject(" `
    "public void checkForPhaseChange("
$ngeProgressionPatterns = @(
    '(?<![A-Za-z0-9_\.])getLevel\s*\(', '\bsetLevel\s*\(',
    '\bgetSkillTemplate\s*\(', '\bsetSkillTemplate\s*\(',
    '\bgrantSkill\s*\(', '\brevokeSkill\s*\(', '\bexpertise\.', '\bprofession\.'
)
$ngeProgressionMatches = @($ngeProgressionPatterns | Where-Object {
    [regex]::IsMatch($createdKillable + $incapacitatedKillable, $_)
})
$sadQuestRows = @(Get-Content -LiteralPath $questTablePath | Where-Object {
    $_ -match 'quest\.task\.fs_quest_sad\.basic_task'
})
if ([int]$contract.inventory.createdHandlers -ne [int]$contract.expected.sadCreatedCallbacks -or
    [int]$contract.inventory.incapacitatedHandlers -ne [int]$contract.expected.sadIncapacitatedCallbacks -or
    -not $createdKillable.Contains("quantityKillable++;") -or
    -not $incapacitatedKillable.Contains("quantityKillable--;") -or
    -not $incapacitatedKillable.Contains('dataTableGetNumRows("datatables/player/quests.iff")') -or
    -not $incapacitatedKillable.Contains('quests.isMyQuest(iter, "quest.task.fs_quest_sad.basic_task")') -or
    -not $incapacitatedKillable.Contains("completeTask(self, questName, true);") -or
    $sadQuestRows.Count -ne [int]$contract.expected.sadAuthoredQuestRows -or
    $ngeProgressionMatches.Count -ne [int]$contract.expected.sadNgePlayerProgressionMutations -or
    -not [bool]$contract.expected.sadVillageQuestLifecyclePreserved)
{
    throw "Force-sensitive Village killable-object callbacks do not preserve the authenticated PRE-CU quest boundary."
}

$jedi = Get-Content -LiteralPath $jediPath -Raw
$forceStart = $jedi.IndexOf(
    "public static boolean isForceSensitive(obj_id player)",
    [StringComparison]::Ordinal
)
$levelStart = $jedi.IndexOf(
    "public static boolean isForceSensitiveLevelRequired",
    $forceStart + 1,
    [StringComparison]::Ordinal
)
$tuningStart = $jedi.IndexOf(
    "public static boolean canTuneLightsaberCrystal",
    $levelStart + 1,
    [StringComparison]::Ordinal
)
$tuningEnd = $jedi.IndexOf(
    "public static boolean hasAnyUltraCloak",
    $tuningStart + 1,
    [StringComparison]::Ordinal
)
if ($forceStart -lt 0 -or $levelStart -lt 0 -or
    $tuningStart -lt 0 -or $tuningEnd -lt 0)
{
    throw "Unable to isolate the Force-sensitive eligibility methods."
}

$forceMethod = $jedi.Substring($forceStart, $levelStart - $forceStart)
$levelMethod = $jedi.Substring($levelStart, $tuningStart - $levelStart)
$tuningMethod = $jedi.Substring($tuningStart, $tuningEnd - $tuningStart)
if (-not $forceMethod.Contains(
        "isJediState(player, JEDI_STATE_FORCE_SENSITIVE)"))
{
    throw "Force-sensitive eligibility does not use the native Jedi state."
}
foreach ($forbidden in @("getSkillTemplate(", "getLevel(", "startsWith("))
{
    if ($forceMethod.Contains($forbidden))
    {
        throw "Force-sensitive eligibility still contains '$forbidden'."
    }
}
if (-not $levelMethod.Contains("return false;") -or
    $levelMethod.Contains("getLevel(") -or
    $levelMethod.Contains("getSkillTemplate("))
{
    throw "The inherited level entry point does not fail closed."
}
if (-not $tuningMethod.Contains(
        'hasSkill(player, "force_title_jedi_rank_01")') -or
    $tuningMethod.Contains("getLevel(") -or
    $tuningMethod.Contains("getSkillTemplate("))
{
    throw "Crystal tuning does not use the exact Pre-CU rank skill."
}

$saber = Get-Content -LiteralPath $saberPath -Raw
$callCount = [regex]::Matches(
    $saber,
    [regex]::Escape("jedi.canTuneLightsaberCrystal(player)")
).Count
if ($callCount -ne [int]$contract.expected.saberComponentCallSites)
{
    throw "Expected $($contract.expected.saberComponentCallSites) crystal-tuning gates; found $callCount."
}
if ($saber.Contains("jedi.isForceSensitiveLevelRequired("))
{
    throw "The saber component still calls the NGE level gate."
}

$fixture = Get-Content -LiteralPath $fixturePath -Raw
foreach ($required in @(
    "setJediState(player, JEDI_STATE_FORCE_SENSITIVE)",
    "setJediState(player, JEDI_STATE_JEDI)",
    "grantSkill(player, CRYSTAL_TUNING_SKILL)",
    "revokeSkill(player, CRYSTAL_TUNING_SKILL)",
    "setJediState(player, originalState)",
    "restoredTuningSkill == tuningSkillBefore"
))
{
    if (-not $fixture.Contains($required))
    {
        throw "Reversible Force-sensitive fixture is missing '$required'."
    }
}

foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties)
{
    $path = switch ($entry.Name)
    {
        "jedi.java" { $jediPath }
        "jedi_saber_component.java" { $saberPath }
        "precu_force_sensitive_eligibility_fixture.java" { $fixturePath }
        "basic_task.java" { $sadBasicTaskPath }
        "quests.tab" { $questTablePath }
        default { throw "Unknown Force-sensitive source hash '$($entry.Name)'." }
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actual -cne [string]$entry.Value)
    {
        throw "$($entry.Name) hash mismatch. Expected $($entry.Value), got $actual."
    }
}

if ($Expectation -eq "Ready")
{
    if ([string]$contract.status -cne "ready" -or
        [string]$contract.runtimeEvidence.result -cne "passed" -or
        -not [bool]$contract.runtimeEvidence.restored)
    {
        throw "Force-sensitive eligibility does not contain passed, restored runtime evidence."
    }
    $patchPath = Join-Path $restorationRoot (
        [string]$contract.buildEvidence.overlayPatch -replace "^restoration/", ""
    )
    $canonicalPatch = (
        [IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"
    )
    $canonicalPatchBytes = [Text.Encoding]::UTF8.GetBytes($canonicalPatch)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try
    {
        $actualPatchHash = (
            [BitConverter]::ToString($sha256.ComputeHash($canonicalPatchBytes))
        ).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha256.Dispose()
    }
    if ($canonicalPatchBytes.Length -ne
            [long]$contract.buildEvidence.overlayPatchBytes -or
        $actualPatchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "Force-sensitive eligibility overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 Force-sensitive eligibility contract passed."
