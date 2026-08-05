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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuSmugglerContentExpertiseAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedBlock([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

$smugglerPath = Join-Path $source ([string]$contract.sourceFiles.smuggler)
$junkDealerSummonPath = Join-Path $source ([string]$contract.sourceFiles.junkDealerSummon)
$skillTablePath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$spaceCombatPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/space_combat.java"
$utilsPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/library/utils.java"
$corpsePath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/corpse/ai_corpse.java"
$combatActionsPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
foreach ($path in @($smugglerPath, $junkDealerSummonPath, $skillTablePath, $spaceCombatPath, $utilsPath,
    $corpsePath, $combatActionsPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.precu-smuggler.source.$([IO.Path]::GetFileName($path)).exists"
}

$smuggler = Get-Content -LiteralPath $smugglerPath -Raw
$smugglerHash = (Get-FileHash -LiteralPath $smugglerPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Contract ($smugglerHash -ceq [string]$contract.buildEvidence.sourceSha256.smuggler) `
    "p14.precu-smuggler.source.smuggler.authenticated"
Assert-Contract (-not $smuggler.Contains("expertise_") -and
    -not $smuggler.Contains("sm_feeling_lucky") -and
    -not $smuggler.Contains("sm_feeling_lucky_recourse")) `
    "p14.precu-smuggler.nge-expertise-and-proc-absent"
Assert-Contract (-not $smuggler.Contains("money.ACCT_RELIC_DEALER") -and
    -not $smuggler.Contains('"smugglerMaster"')) `
    "p14.precu-smuggler.nge-secondary-junk-payout-absent"

$junkDealerSummon = Get-Content -LiteralPath $junkDealerSummonPath -Raw
$junkDealerSummonHash = (Get-FileHash -LiteralPath $junkDealerSummonPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Contract ($junkDealerSummonHash -ceq
    [string]$contract.buildEvidence.sourceSha256.junkDealerSummon) `
    "p14.precu-smuggler.source.junk-dealer-summon.authenticated"
Assert-Contract (-not $junkDealerSummon.Contains("expertise_") -and
    -not $junkDealerSummon.Contains("sm_junk_dealer_") -and
    -not $junkDealerSummon.Contains("buffParty") -and
    -not $junkDealerSummon.Contains("buff.applyBuff") -and
    -not $junkDealerSummon.Contains("getSkillStatisticModifier") -and
    [int]$contract.expected.summonedDealerExpertiseReads -eq 0 -and
    [int]$contract.expected.summonedDealerNgeBuffReferences -eq 0) `
    "p14.precu-smuggler.summoned-dealer-nge-buff-authority-absent"

$dealerAttach = Get-BracedBlock $junkDealerSummon `
    "public int OnAttach(obj_id self)"
$dealerGreeting = Get-BracedBlock $junkDealerSummon `
    "public int handleGreeting(obj_id self, dictionary params)"
$dealerProfit = Get-BracedBlock $junkDealerSummon `
    "public void totalProfits(obj_id self, obj_id player)"
$dealerTimeout = Get-BracedBlock $junkDealerSummon `
    "public int timeUp(obj_id self, dictionary params)"
$dealerDismissal = Get-BracedBlock $junkDealerSummon `
    "public int dismissDealer(obj_id self, dictionary params)"
$dealerRunAway = Get-BracedBlock $junkDealerSummon `
    "public int handleRunAway(obj_id self, dictionary params)"
Assert-Contract ($dealerAttach.Contains('messageTo(self, "timeUp", null, 300, true)') -and
    $dealerAttach.Contains('messageTo(self, "handleGreeting", null, 2.0f, false)') -and
    [int]$contract.expected.summonedDealerLifetimeSeconds -eq 300 -and
    $dealerGreeting.Contains('utils.setScriptVar(self, "smugglerMaster", master)') -and
    $dealerGreeting.Contains('"junk_dealer_greeting_" + phraseId') -and
    $dealerGreeting.Contains('chat.chat(self, master') -and
    [bool]$contract.expected.summonedDealerGreetingAndProfitPreserved) `
    "p14.precu-smuggler.summoned-dealer-greeting-and-lifetime-preserved"
Assert-Contract ($dealerProfit.Contains('utils.getIntScriptVar(self, "totalProfits")') -and
    $dealerProfit.Contains('new string_id("spam", "junk_dealer_total_profits")') -and
    $dealerProfit.Contains("sendSystemMessageProse(player, pp)") -and
    $dealerTimeout.Contains('utils.setScriptVar(self, "dismissed", 1)') -and
    $dealerTimeout.Contains('messageTo(self, "handleRunAway", null, 1, false)') -and
    $dealerTimeout.Contains("totalProfits(self, player)") -and
    $dealerDismissal.Contains('utils.setScriptVar(self, "dismissed", 1)') -and
    $dealerDismissal.Contains('messageTo(self, "handleRunAway", null, 1, false)') -and
    $dealerDismissal.Contains("totalProfits(self, player)")) `
    "p14.precu-smuggler.summoned-dealer-profit-and-dismissal-preserved"
Assert-Contract ($dealerRunAway.Contains('detachScript(self, "conversation.junk_dealer_smuggler")') -and
    $dealerRunAway.Contains('detachScript(self, "npc.converse.junk_dealer")') -and
    $dealerRunAway.Contains("ai_lib.pathAwayFrom(self, master)") -and
    $dealerRunAway.Contains('messageTo(self, "cleanUp", null, 5.0f, false)') -and
    [bool]$contract.expected.summonedDealerDismissalAndCleanupPreserved) `
    "p14.precu-smuggler.summoned-dealer-cleanup-preserved"

$sellJunk = Get-BracedBlock $smuggler `
    "public static void sellJunkItem(obj_id player, obj_id item, boolean fence, boolean reshowSui)"
Assert-Contract ($sellJunk.Contains("getPrice(item)") -and
    $sellJunk.Contains("money.ACCT_JUNK_DEALER") -and
    $sellJunk.Contains('"handleSoldJunk"') -and
    $sellJunk.Contains("FENCE_MULTIPLIER_LOW") -and
    $sellJunk.Contains("FENCE_MULTIPLIER_HIGH")) `
    "p14.precu-smuggler.junk-base-content-preserved"

$spaceDrop = Get-BracedBlock $smuggler `
    "public static void spaceContrabandDropCheck(obj_id player)"
Assert-Contract ($spaceDrop.Contains('factions.getFactionStanding(player, "underworld")') -and
    $spaceDrop.Contains("getSmuggleTier(underworldFaction)") -and
    $spaceDrop.Contains("int chance = (12 - tier * 2);") -and
    $spaceDrop.Contains("createRandomContrabandTier(player, tier)") -and
    -not $spaceDrop.Contains("getSkillStatisticModifier")) `
    "p14.precu-smuggler.space-contraband-base-chance-preserved"

$corpseDrop = Get-BracedBlock $smuggler `
    "public static void contrabandDropCheck(obj_id player, obj_id target, int tier, int corpseLevel)"
Assert-Contract ($corpseDrop.Contains("int chance = (12 - (dropTier * 2));") -and
    $corpseDrop.Contains("createRandomContrabandTier(player, dropTier)") -and
    -not $corpseDrop.Contains("getSkillStatisticModifier")) `
    "p14.precu-smuggler.compatibility-drop-base-chance-preserved"

$skillRows = Get-Content -LiteralPath $skillTablePath
$precuSmugglerRows = @($skillRows | Where-Object {
    $name = ([regex]::Split($_, "`t"))[0]
    ($name -ceq "combat_smuggler" -or $name.StartsWith("combat_smuggler_")) -and
        -not $name.StartsWith("combat_smuggler_prereq")
})
$precuSmugglerText = $precuSmugglerRows -join "`n"
Assert-Contract ($precuSmugglerRows.Count -eq [int]$contract.expected.canonicalPrecuSmugglerRows -and
    -not $precuSmugglerText.Contains("expertise_") -and
    -not $precuSmugglerText.Contains("sm_off_the_books") -and
    $precuSmugglerText.Contains("slice_containers") -and
    $precuSmugglerText.Contains("slice_terminals") -and
    $precuSmugglerText.Contains("slice_weaponsbasic") -and
    $precuSmugglerText.Contains("slice_weaponsadvanced") -and
    $precuSmugglerText.Contains("slice_armor")) `
    "p14.precu-smuggler.skill-family-authenticated"

$spaceCombat = Get-Content -LiteralPath $spaceCombatPath -Raw
$spaceLoot = Get-BracedBlock $spaceCombat `
    "public static void createSpaceLoot(obj_id objAttacker, obj_id objDefender)"
if ([string]::IsNullOrEmpty($spaceLoot))
{
    $spaceLoot = $spaceCombat
}
Assert-Contract ($spaceLoot.Contains("utils.isProfession(objPilot, utils.SMUGGLER)") -and
    $spaceLoot.Contains("smuggler.spaceContrabandDropCheck(objPilot)")) `
    "p14.precu-smuggler.retained-space-content-admission"

$utils = Get-Content -LiteralPath $utilsPath -Raw
$isProfession = Get-BracedBlock $utils `
    "public static boolean isProfession(obj_id player, int profession)"
Assert-Contract ($isProfession.Contains("case SMUGGLER:") -and
    $isProfession.Contains('hasSkill(player, "combat_smuggler_novice")') -and
    -not $isProfession.Contains("class_smuggler")) `
    "p14.precu-smuggler.profession-admission-skill-box-owned"

$corpse = Get-Content -LiteralPath $corpsePath -Raw
Assert-Contract (-not $corpse.Contains("inspectCorpseForContraband") -and
    -not $corpse.Contains("mnu_find_illicit_goods") -and
    $corpse.Contains("menu_info_types.LOOT") -and $corpse.Contains("canHarvest(self, player)")) `
    "p14.precu-smuggler.corpse-menu-retired-loot-preserved"

$combatActions = Get-Content -LiteralPath $combatActionsPath -Raw
$compatibilityHandler = Get-BracedBlock $combatActions `
    "public int sm_inspect_cargo(obj_id self, obj_id target, String params, float defaultTime)"
Assert-Contract ($compatibilityHandler.Contains("smuggler.inspectCorpseForContraband(player, target)") -and
    $compatibilityHandler.Contains("return SCRIPT_CONTINUE")) `
    "p14.precu-smuggler.ungranted-compatibility-handler-preserved"
$summonedDealerCompatibilityHandler = Get-BracedBlock $combatActions `
    "public int sm_off_the_books(obj_id self, obj_id target, String params, float defaultTime)"
Assert-Contract ($summonedDealerCompatibilityHandler.Contains('combatStandardAction("sm_off_the_books"') -and
    $summonedDealerCompatibilityHandler.Contains("callJunkDealer(self)") -and
    $summonedDealerCompatibilityHandler.Contains("return SCRIPT_CONTINUE")) `
    "p14.precu-smuggler.ungranted-summoned-dealer-handler-preserved"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.precu-smuggler.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.precu-smuggler.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.smuggler -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.junkDealerSummon -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.precu-smuggler.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.precu-smuggler.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.precu-smuggler.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU Smuggler content expertise authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU Smuggler content expertise authority contract passed."
