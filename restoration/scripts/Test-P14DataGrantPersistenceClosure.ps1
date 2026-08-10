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
    ([string]$manifest.contracts.p14DataGrantPersistenceClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
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

$sourceMap = [ordered]@{
    "CreatureObject.cpp" = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
    "CreatureObject.h" = Join-Path $source "src/engine/server/library/serverGame/src/shared/object/CreatureObject.h"
    "skill.java" = Join-Path $scriptRoot "library/skill.java"
    "xp.java" = Join-Path $scriptRoot "library/xp.java"
    "pgc_quests.java" = Join-Path $scriptRoot "library/pgc_quests.java"
    "base_player.java" = Join-Path $scriptRoot "player/base/base_player.java"
    "player_saga_quest.java" = Join-Path $scriptRoot "player/player_saga_quest.java"
    "storyteller_commands.java" = Join-Path $scriptRoot "systems/storyteller/storyteller_commands.java"
    "collection.java" = Join-Path $scriptRoot "library/collection.java"
    "cybernetic.java" = Join-Path $scriptRoot "library/cybernetic.java"
    "respec.java" = Join-Path $scriptRoot "library/respec.java"
    "xp_purchase.java" = Join-Path $scriptRoot "item/special/xp_purchase.java"
    "loot_schematic.java" = Join-Path $scriptRoot "item/loot_schematic/loot_schematic.java"
    "buff_handler.java" = Join-Path $scriptRoot "systems/buff/buff_handler.java"
}
Assert-Contract ($sourceMap.Count -eq [int]$contract.expected.authoritativeSourceFiles) `
    "p14.data-grant.authoritative-source-count"
$texts = @{}
foreach ($entry in $sourceMap.GetEnumerator())
{
    $exists = Test-Path -LiteralPath $entry.Value -PathType Leaf
    Assert-Contract $exists "p14.data-grant.source.$($entry.Key).exists"
    if ($exists)
    {
        $texts[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
            "p14.data-grant.source.$($entry.Key).authenticated"
    }
}

$srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($srcPin.Count -eq 1 -and $dsrcPin.Count -eq 1 -and
    [string]$srcPin[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit -and
    [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.dsrcSourceCommit) `
    "p14.data-grant.direct-source-pins"

$excluded = '\\(test|working|beta|gm|content_tools|e3demo)\\'
$grantLines = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
{
    if ($file.FullName -match $excluded) { continue }
    foreach ($match in @(Select-String -LiteralPath $file.FullName -Pattern '\b(grantSkill|grantCommand)\s*\('))
    {
        $grantLines.Add([pscustomobject]@{
            Path = $file.FullName.Substring($scriptRoot.Length + 1).Replace('\', '/')
            LineNumber = $match.LineNumber
            Line = $match.Line
        })
    }
}
$grantFiles = @($grantLines.Path | Sort-Object -Unique)
$skillLines = @($grantLines | Where-Object { $_.Line -match '\bgrantSkill\s*\(' })
$commandLines = @($grantLines | Where-Object { $_.Line -match '\bgrantCommand\s*\(' })
$records = @($grantLines | ForEach-Object {
    "$($_.Path):$($_.LineNumber)|$($_.Line.Trim())"
} | Sort-Object)
$inventoryBytes = [System.Text.Encoding]::UTF8.GetBytes($records -join "`n")
$inventoryHasher = [System.Security.Cryptography.SHA256]::Create()
$inventoryHash = ([System.BitConverter]::ToString($inventoryHasher.ComputeHash($inventoryBytes))).Replace('-', '').ToLowerInvariant()
Assert-Contract ($grantLines.Count -eq [int]$contract.inventory.grantSourceLines -and
    $grantFiles.Count -eq [int]$contract.inventory.grantSourceFiles -and
    $skillLines.Count -eq [int]$contract.inventory.grantSkillSourceLines -and
    (@($skillLines.Path | Sort-Object -Unique)).Count -eq [int]$contract.inventory.grantSkillSourceFiles -and
    $commandLines.Count -eq [int]$contract.inventory.grantCommandSourceLines -and
    (@($commandLines.Path | Sort-Object -Unique)).Count -eq [int]$contract.inventory.grantCommandSourceFiles -and
    $inventoryHash -ceq [string]$contract.inventory.normalizedInventorySha256) `
    "p14.data-grant.inventory-exact-and-classified"

$creature = [string]$texts["CreatureObject.cpp"]
$header = [string]$texts["CreatureObject.h"]
$nativePredicate = Get-BracedSurface $creature "bool isRetiredNgeProgressionCommandName"
$skillOnlyPredicate = Get-BracedSurface $creature "bool isPreCuSkillOnlyCommandName"
$nativeGrant = Get-BracedSurface $creature "bool CreatureObject::grantCommand"
$nativeCleanup = Get-BracedSurface $creature "void CreatureObject::clearRetiredNgeProgressionCommands"
$nativeLoad = Get-BracedSurface $creature "void CreatureObject::onClientAboutToLoad"
$nativeWarmup = Get-BracedSurface $creature "void CreatureObject::doWarmupChecks"
Assert-Contract (([regex]::Matches($nativePredicate, 'commandName == "')).Count -eq
    [int]$contract.expected.retiredNativeCommandNames) "p14.data-grant.native-command-inventory"
Assert-Contract (([regex]::Matches($skillOnlyPredicate, 'commandName == "')).Count -eq
        [int]$contract.expected.preCuSkillOnlyCommandNames -and
    $skillOnlyPredicate.Contains('commandName == "meditate"')) `
    "p14.data-grant.precu-skill-only-command-inventory"
Assert-Contract ($nativeGrant.Contains("isPlayerControlled()") -and
    $nativeGrant.Contains("isRetiredNgeProgressionCommandName(commandName)") -and
    $nativeGrant.Contains("!fromSkill && CreatureObjectNamespace::isPreCuSkillOnlyCommandName(commandName)") -and
    $nativeGrant.IndexOf("return false;", [System.StringComparison]::Ordinal) -lt
        $nativeGrant.IndexOf("setObjVarItem", [System.StringComparison]::Ordinal)) `
    "p14.data-grant.authoritative-command-writer-fails-before-persistence"
Assert-Contract ($header.Contains("void clearRetiredNgeProgressionCommands();") -and
    $nativeLoad.Contains("clearRetiredNgeProgressionCommands();") -and
    $nativeCleanup.Contains("DynamicVariableList::NestedList") -and
    $nativeCleanup.Contains("isRetiredNgeProgressionCommandName(iter.getName())") -and
    $nativeCleanup.Contains("revokeCommand(*iter, false, true)") -and
    $nativeCleanup.Contains("isPreCuSkillOnlyCommandName(iter.getName())") -and
    $nativeCleanup.Contains("revokeCommand(*iter, false, false)") -and
    $nativeCleanup.Contains('removeObjVarItem(OBJVAR_NOT_SKILL_COMMANDS + "." + *iter)') -and
    $nativeWarmup.Contains("isRetiredNgeProgressionCommandName(command.m_commandName)")) `
    "p14.data-grant.persisted-and-executable-command-boundaries"
Assert-Contract ([bool]$contract.expected.nonSkillPreCuCommandGrantsRejectedBeforePersistence -and
    [bool]$contract.expected.persistedNonSkillPreCuCommandCopiesRemovedOnLoad -and
    [bool]$contract.expected.skillProvidedPreCuCommandPreserved -and
    $nativeGrant.Contains("!fromSkill") -and
    $nativeCleanup.Contains("revokeCommand(*iter, false, false)") -and
    -not $nativeWarmup.Contains("isPreCuSkillOnlyCommandName(command.m_commandName)")) `
    "p14.data-grant.precu-skill-command-owned-only-by-skill"

$skill = [string]$texts["skill.java"]
$skillPredicate = Get-BracedSurface $skill "public static boolean isRetiredNgeProgressionSkillName"
$skillGrant = Get-BracedSurface $skill "public static boolean grant(obj_id target, String skillName)"
$skillPurchase = Get-BracedSurface $skill "public static boolean purchaseSkill"
Assert-Contract ($skillPredicate.Contains('skillName.startsWith("class_")') -and
    $skillPredicate.Contains('skillName.equals("expertise")') -and
    $skillGrant.Contains("isRetiredNgeProgressionSkillName(skillName)") -and
    $skillPurchase.Contains("isRetiredNgeProgressionSkillName(skillName)")) `
    "p14.data-grant.shared-skill-admission"

$xp = [string]$texts["xp.java"]
$xpPredicate = Get-BracedSurface $xp "public static boolean isRetiredNgeProgressionExperienceType"
Assert-Contract ($xpPredicate.Contains('xpType.equals("chronicles")') -and
    ([regex]::Matches($xp, [regex]::Escape("amt > 0 && isPlayer(target) && isRetiredNgeProgressionExperienceType(xp_type)"))).Count -eq 3) `
    "p14.data-grant.chronicles-xp-admission"

$pgc = [string]$texts["pgc_quests.java"]
$pgcCleanup = Get-BracedSurface $pgc "public static void retireChroniclesPlayerProgressionState"
$pgcXp = Get-BracedSurface $pgc "public static int grantChronicleXp"
$pgcLevel = Get-BracedSurface $pgc "public static void checkForGainedChroniclesLevel"
$pgcRoadmap = Get-BracedSurface $pgc "public static boolean grantChroniclesRoadmapItem"
$pgcTokens = Get-BracedSurface $pgc "public static obj_id grantChroniclesRewardTokens"
Assert-Contract ($pgcCleanup.Contains("PGC_STORED_CHRONICLE_XP_INDEX") -and
    $pgcCleanup.Contains("PGC_STORED_CHRONICLE_SILVER_TOKENS_INDEX") -and
    $pgcCleanup.Contains("PGC_STORED_CHRONICLE_GOLD_TOKENS_INDEX") -and
    $pgcCleanup.Contains("pgcAdjustRatingData") -and
    $pgcCleanup.Contains("PGC_GRANTED_ROADMAP_REWARDS_OBJVAR") -and
    $pgcXp.Contains("isRetiredNgeProgressionExperienceType") -and
    $pgcLevel.Contains("isRetiredNgeProgressionExperienceType") -and
    $pgcRoadmap.IndexOf("return false;", [System.StringComparison]::Ordinal) -lt
        $pgcRoadmap.IndexOf("createObjectInInventoryAllowOverload", [System.StringComparison]::Ordinal) -and
    $pgcTokens.IndexOf("return obj_id.NULL_ID;", [System.StringComparison]::Ordinal) -lt
        $pgcTokens.IndexOf("createNewItemFunction", [System.StringComparison]::Ordinal)) `
    "p14.data-grant.chronicles-central-state-and-reward-boundaries"

$saga = [string]$texts["player_saga_quest.java"]
$sagaGuards = @(
    @{ Signature = "public int handleChroniclesReserveReminder"; Mutation = "pgcGetRatingData" },
    @{ Signature = "public int handleChronicleProfessionGranted"; Mutation = "grantSkill" },
    @{ Signature = "public int checkForMissedRoadmapRewards"; Mutation = "skill_template.getSkillTemplateSkillsByTemplateName" },
    @{ Signature = "public int OnRatingFinished"; Mutation = "pgcAdjustRating" }
)
foreach ($guard in $sagaGuards)
{
    $surface = Get-BracedSurface $saga $guard.Signature
    Assert-Contract ($surface.Contains("isRetiredChroniclesPlayerProgression()") -and
        $surface.IndexOf("return SCRIPT_CONTINUE;", [System.StringComparison]::Ordinal) -lt
            $surface.IndexOf($guard.Mutation, [System.StringComparison]::Ordinal)) `
        "p14.data-grant.saga-callback.$($guard.Signature).fails-closed"
}

$storyteller = [string]$texts["storyteller_commands.java"]
foreach ($signature in @("public int chroniclerGetStoredXp", "public int handleChroniclerGetStoredXp"))
{
    $surface = Get-BracedSurface $storyteller $signature
    Assert-Contract ($surface.Contains("isRetiredChroniclesPlayerProgression()") -and
        $surface.Contains("retireChroniclesPlayerProgressionState(self)") -and
        $surface.IndexOf("return SCRIPT_CONTINUE;", [System.StringComparison]::Ordinal) -lt
            $surface.IndexOf("pgcGetRatingData", [System.StringComparison]::Ordinal)) `
        "p14.data-grant.storyteller-callback.$signature.fails-closed"
}

$basePlayer = [string]$texts["base_player.java"]
$collection = [string]$texts["collection.java"]
$cybernetic = [string]$texts["cybernetic.java"]
$respec = [string]$texts["respec.java"]
$xpPurchase = [string]$texts["xp_purchase.java"]
$lootSchematic = [string]$texts["loot_schematic.java"]
$buffHandler = [string]$texts["buff_handler.java"]
Assert-Contract ($basePlayer.Contains("pgc_quests.retireChroniclesPlayerProgressionState(self);") -and
    $collection.Contains("if (grantCommand(player, command1))") -and
    $collection.Contains("was rejected by PRE-CU progression authority") -and
    [bool]$contract.expected.collectionCommandGrantLoggingAccurate -and
    $cybernetic.Contains("isRetiredPostNgePlayerCyberneticCommandActor(player)") -and
    $respec.Contains("retireNgePlayerRespecEntrypoint(player)") -and
    $xpPurchase.Contains("xp.grantUnmodifiedExperience(player, xpType, xpAmt)") -and
    $lootSchematic.Contains("skill.grantSkillToPlayer(player, item_skill)") -and
    $buffHandler.Contains("buff.isRetiredPostNgePlayerBuffCommandGrant(subType)")) `
    "p14.data-grant.dynamic-writers-centralized-or-source-guarded"
Assert-Contract (-not $nativePredicate.Contains('"groupdance"') -and
    -not $nativePredicate.Contains('"imagedesign"') -and
    $collection.Contains("groundquests.sendSignal") -and
    $lootSchematic.Contains("grantSchematic") -and
    [bool]$contract.expected.nonPlayerExpansionCompatibilityPreserved -and
    [bool]$contract.expected.preCuSkillBoxAndXpProgressionPreserved -and
    [bool]$contract.expected.retainedQuestBadgeFactionPilotEntertainerAndItemRewardsPreserved) `
    "p14.data-grant.retained-precu-and-expansion-rewards-preserved"

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.fullServerBuild -like "passed*" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        @($contract.requiredBeforeReady).Count -eq 0) "p14.data-grant.ready-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) `
        "p14.data-grant.source-status"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 data-grant and persistence closure failed: $($failures -join ', ')"
}
Write-Host "Publish 14.1 data-grant and persistence closure passed."
