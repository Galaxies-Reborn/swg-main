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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuMobileStealthDetectionAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$stealthPath = Join-Path $source ([string]$contract.sourceFiles.stealth)
$xpPath = Join-Path $source ([string]$contract.sourceFiles.xp)
$aiAggroPath = Join-Path $source ([string]$contract.sourceFiles.aiAggro)
$combatBasePath = Join-Path $source ([string]$contract.sourceFiles.combatBase)
$combatActionsPath = Join-Path $source ([string]$contract.sourceFiles.combatActions)
$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skills)
$buffPath = Join-Path $source ([string]$contract.sourceFiles.buff)
$buffHandlerPath = Join-Path $source ([string]$contract.sourceFiles.buffHandler)
$playerStealthPath = Join-Path $source ([string]$contract.sourceFiles.playerStealth)
$hepPath = Join-Path $source ([string]$contract.sourceFiles.hep)
$jediPath = Join-Path $source ([string]$contract.sourceFiles.jedi)
$commandTablePath = Join-Path $source ([string]$contract.sourceFiles.commandTable)
$buffTablePath = Join-Path $source ([string]$contract.sourceFiles.buffTable)
$jediActionsPath = Join-Path $source ([string]$contract.sourceFiles.jediActions)
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

foreach ($path in @(
    $stealthPath, $xpPath, $aiAggroPath, $combatBasePath, $combatActionsPath,
    $skillsPath, $buffPath, $buffHandlerPath, $playerStealthPath, $hepPath,
    $jediPath, $commandTablePath, $buffTablePath, $jediActionsPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) (
        "p14.mobile-stealth.source." + [System.IO.Path]::GetFileName($path) + ".exists")
}
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $stealthPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256.stealth) "p14.mobile-stealth.source.authenticated"

$stealth = Get-Content -LiteralPath $stealthPath -Raw
$xp = Get-Content -LiteralPath $xpPath -Raw
$aiAggro = Get-Content -LiteralPath $aiAggroPath -Raw
$combatBase = Get-Content -LiteralPath $combatBasePath -Raw
$combatActions = Get-Content -LiteralPath $combatActionsPath -Raw
$buff = Get-Content -LiteralPath $buffPath -Raw
$buffHandler = Get-Content -LiteralPath $buffHandlerPath -Raw
$playerStealth = Get-Content -LiteralPath $playerStealthPath -Raw
$hep = Get-Content -LiteralPath $hepPath -Raw
$jedi = Get-Content -LiteralPath $jediPath -Raw
$normal = Get-SourceSlice $stealth "public static float getDetectChance(" "public static float getDetectChanceWithDetailedOutput("
$detailed = Get-SourceSlice $stealth "public static float getDetectChanceWithDetailedOutput(" "public static boolean activeDetectHiddenTarget("
$detectionMethods = @($normal, $detailed)
$adapterCalls = 0
foreach ($method in $detectionMethods)
{
    $calls = ([regex]::Matches($method, 'xp[.]getPrecuCombatLevel[(](target|detector)[)]')).Count
    $adapterCalls += $calls
    Assert-Contract ($calls -eq 2 -and -not $method.Contains("getLevel(")) (
        "p14.mobile-stealth.method." + ($detectionMethods.IndexOf($method) + 1) + ".precu-boundary")
}
Assert-Contract ($detectionMethods.Count -eq [int]$contract.expected.detectionMethods -and
    $adapterCalls -eq [int]$contract.expected.precuCombatLevelCalls) "p14.mobile-stealth.adapter-call-count"

$theft = Get-SourceSlice $stealth "public static boolean doTheftLoot(" "public static boolean hasStealingLootTableEntry("
$decoy = Get-SourceSlice $stealth "public static obj_id createDecoy(" "public static boolean isDecoy("
$compatibilityMethods = @($theft, $decoy)
$compatibilityAdapterCalls = ([regex]::Matches($theft,
    'xp[.]getPrecuCombatLevel[(](mark|thief)[)]')).Count +
    ([regex]::Matches($decoy, 'xp[.]getPrecuCombatLevel[(]spy[)]')).Count
Assert-Contract ($compatibilityMethods.Count -eq [int]$contract.expected.compatibilityMethods -and
    $compatibilityAdapterCalls -eq [int]$contract.expected.compatibilityPrecuCombatLevelCalls -and
    -not $theft.Contains("getLevel(") -and
    -not $decoy.Contains("getLevel(")) "p14.mobile-stealth.compatibility.precu-boundary"
Assert-Contract ($theft.Contains("int markLevel = xp.getPrecuCombatLevel(mark);") -and
    $theft.Contains("int thiefLevel = xp.getPrecuCombatLevel(thief);") -and
    $theft.Contains("if (isPlayer(mark))") -and
    $theft.Contains("STEAL_MARKED_ITEMS") -and
    $theft.Contains("getNpcCash(mark)")) "p14.mobile-stealth.theft-compatibility-preserved"
Assert-Contract ($decoy.Contains("int hologramLevel = xp.getPrecuCombatLevel(spy);") -and
    $decoy.Contains('setObjVar(hologram, "intCombatDifficulty", hologramLevel)') -and
    $decoy.Contains("setLevel(hologram, hologramLevel)") -and
    $decoy.Contains('attachScript(hologram, "ai.spy_decoy")')) "p14.mobile-stealth.decoy-compatibility-preserved"

$spyActionPredicate = Get-SourceSlice $combatBase `
    "public static boolean isRetiredPostNgeSpyPlayerAction(" `
    "public static boolean isRetiredPostNgeBeastMasterPlayerAction("
$stealAction = Get-SourceSlice $combatActions "public int steal(" "public int sp_buff_invis_1("
$decoyAction = Get-SourceSlice $combatActions "public int sp_decoy(" "public int sp_assassins_mark("
Assert-Contract ($spyActionPredicate.Contains("if (!isPlayer(self) || actionName == null)") -and
    $spyActionPredicate.Contains('actionName.equals("steal")') -and
    $spyActionPredicate.Contains('actionName.startsWith("sp_")') -and
    $stealAction.Contains('isRetiredPostNgeSpyPlayerAction(self, "steal")') -and
    $decoyAction.Contains('isRetiredPostNgeSpyPlayerAction(self, "sp_decoy")')) `
    "p14.mobile-stealth.player-theft-decoy-retired"
Assert-Contract ($stealAction.Contains("stealth.canSteal(self, target)") -and
    $stealAction.Contains("stealth.steal(self, target)") -and
    $decoyAction.Contains("stealth.createDecoy(self)")) `
    "p14.mobile-stealth.npc-entrypoints-preserved"

$weaponLevel = Get-SourceSlice $xp "public static int getPrecuWeaponCombatLevel(" "public static int getPrecuCombatLevel("
$combatLevel = Get-SourceSlice $xp "public static int getPrecuCombatLevel(" "public static int getPrecuCombatXpDifficulty("
Assert-Contract ($weaponLevel.Contains("getCurrentWeapon(player)") -and
    $weaponLevel.Contains('"private_" + weaponTypeName + "_combat_difficulty"') -and
    $weaponLevel.Contains("private_jedi_difficulty") -and
    $weaponLevel.Contains("Math.min(PRECU_COMBAT_XP_DIFFICULTY_CAP, (skillMod / 100) + 1)")) (
        "p14.mobile-stealth.player-level.core3-formula")
Assert-Contract ($combatLevel.Contains("if (isPlayer(creature))") -and
    $combatLevel.Contains("return getPrecuWeaponCombatLevel(creature);") -and
    $combatLevel.Contains("return Math.max(0, getLevel(creature));")) "p14.mobile-stealth.player-npc-boundary"

foreach ($method in $detectionMethods)
{
    Assert-Contract ($method.Contains("getApplicableInvisSkillMod") -and
        $method.Contains('"detect_hidden"') -and
        $method.Contains('"difficultyClass"') -and
        $method.Contains("MAX_CHANCE_TO_DETECT_HIDDEN") -and
        $method.Contains("MIN_CHANCE_TO_DETECT_HIDDEN")) "p14.mobile-stealth.probability-inputs-preserved"
}
Assert-Contract ($normal.Contains("invis_forceCloak") -and $detailed.Contains("invis_forceCloak")) (
    "p14.mobile-stealth.retained-content-force-cloak-adjustment-preserved")
Assert-Contract ($aiAggro.Contains("stealth.passiveDetectHiddenTarget(target, self, 100)") -and
    $stealth.Contains("float finalChanceToDetect = getDetectChance(target, detector, baseChanceToDetect);") -and
    $stealth.Contains("return passiveDetectHiddenTarget(bubbleHolder, breacher, volume);")) (
        "p14.mobile-stealth.production-call-graph")

$retiredNames = Get-SourceSlice $stealth `
    "private static final String[] RETIRED_POST_P14_PLAYER_INVISIBILITY_NAMES" `
    "public static final int MIN_MOVEMENT_PRIORITY"
$retiredNameInventory = @([regex]::Matches($retiredNames, '"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$expectedRetiredNames = @(
    "urbanStealth", "wildernessStealth", "forceCloak",
    "invis_urbanStealth", "invis_wildernessStealth", "invis_forceCloak")
Assert-Contract ($retiredNameInventory.Count -eq
        [int]$contract.expected.retiredPostP14PlayerInvisibilityNames -and
    @($retiredNameInventory | Select-Object -Unique).Count -eq $retiredNameInventory.Count -and
    @($expectedRetiredNames | Where-Object { $_ -cnotin $retiredNameInventory }).Count -eq 0) `
    "p14.mobile-stealth.post-p14-invisibility.exact-name-inventory"

$retiredPredicate = Get-SourceSlice $stealth `
    "public static boolean isRetiredPostP14PlayerInvisibilityAction(" `
    "public static void retirePostP14PlayerInvisibilityState("
$retiredCleanup = Get-SourceSlice $stealth `
    "public static void retirePostP14PlayerInvisibilityState(" `
    "public static void setBioProbeData("
Assert-Contract ($retiredPredicate.Contains("isPlayer(actor)") -and
    $retiredPredicate.Contains("isRetiredPostP14PlayerInvisibilityName(actionName)") -and
    $retiredCleanup.Contains("!isPlayer(player)") -and
    $retiredCleanup.Contains('"invis_urbanStealth"') -and
    $retiredCleanup.Contains('"invis_wildernessStealth"') -and
    $retiredCleanup.Contains('"invis_forceCloak"') -and
    $retiredCleanup.Contains("utils.clearNoDropFromItem(hep)") -and
    $retiredCleanup.Contains("removeObjVar(player, ACTIVE_HEP)") -and
    $retiredCleanup.Contains("_makeVisible(player, null, null)")) `
    "p14.mobile-stealth.post-p14-invisibility.player-only-state-cleanup"

$guardedStealthMethods = @(
    @("public static boolean canPerformForceCloak(", "public static boolean canPerformHide(", '"forceCloak"'),
    @("public static void forceCloak(", "public static void hide(", '"forceCloak"'),
    @("public static boolean canPerformUrbanStealth(", "public static void urbanStealth(", '"urbanStealth"'),
    @("public static void urbanStealth(", "public static boolean canPerformWildernessStealth(", '"urbanStealth"'),
    @("public static boolean canPerformWildernessStealth(", "public static void wildernessStealth(", '"wildernessStealth"'),
    @("public static void wildernessStealth(", "public static boolean canPerformCover(", '"wildernessStealth"'),
    @("public static boolean checkUrbanStealthUpkeep(", "public static boolean checkWildernessStealthUpkeep(", '"urbanStealth"'),
    @("public static boolean checkWildernessStealthUpkeep(", "public static boolean checkForceCloakUpkeep(", '"wildernessStealth"'),
    @("public static boolean checkForceCloakUpkeep(", "public static boolean checkForAndMakeVisible(", '"forceCloak"')
)
foreach ($guard in $guardedStealthMethods)
{
    $method = Get-SourceSlice $stealth $guard[0] $guard[1]
    Assert-Contract ($method.Contains("isRetiredPostP14PlayerInvisibilityAction") -and
        $method.Contains($guard[2]) -and
        $method.Contains("retirePostP14PlayerInvisibilityState")) (
            "p14.mobile-stealth.post-p14-invisibility.method." +
            ($guardedStealthMethods.IndexOf($guard) + 1) + ".player-fail-closed")
}

$combatStandardAction = Get-SourceSlice $combatBase `
    "public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)" `
    "public void startDelayedAttack("
$canApplyBuff = Get-SourceSlice $buff `
    "public static boolean canApplyBuff(obj_id target, obj_id owner, int nameCrc)" `
    "public static boolean applyBuff(obj_id target, String name)"
$invisAddHandler = Get-SourceSlice $buffHandler `
    "public void invisBuffAddBuffHandler(" `
    "public void noBreakInvisRemoveBuffHandler("
$performJediBuff = Get-SourceSlice $jedi `
    "public static boolean performJediBuffCommand(" `
    "public static boolean doBuffAction("
$doJediBuff = Get-SourceSlice $jedi `
    "public static boolean doBuffAction(" `
    "public static boolean doForceRun("
Assert-Contract ($combatStandardAction.Contains(
        "stealth.isRetiredPostP14PlayerInvisibilityAction(self, actionName)") -and
    $combatStandardAction.Contains("stealth.retirePostP14PlayerInvisibilityState(self)") -and
    $canApplyBuff.Contains(
        "stealth.isRetiredPostP14PlayerInvisibilityName(bdata.buffName)") -and
    $invisAddHandler.Contains("stealth.isRetiredPostP14PlayerInvisibilityName(buffName)") -and
    $invisAddHandler.Contains("stealth.retirePostP14PlayerInvisibilityState(self)") -and
    $performJediBuff.Contains("isRetiredPostP14PlayerInvisibilityAction(player, actionName)") -and
    $doJediBuff.Contains("isRetiredPostP14PlayerInvisibilityAction(self, actionName)")) `
    "p14.mobile-stealth.post-p14-invisibility.central-admission-fail-closed"
Assert-Contract ($playerStealth.Contains("stealth.retirePostP14PlayerInvisibilityState(self)") -and
    $playerStealth.Contains("stealth.isRetiredPostP14PlayerInvisibilityName(invisBuff)") -and
    $hep.Contains('stealth.isRetiredPostP14PlayerInvisibilityAction(player, "urbanStealth")') -and
    $hep.Contains('queueCommand(player, getStringCrc(toLower("urbanStealth"))') -and
    $hep.IndexOf('stealth.isRetiredPostP14PlayerInvisibilityAction(player, "urbanStealth")') -lt
        $hep.IndexOf('queueCommand(player, getStringCrc(toLower("urbanStealth"))')) `
    "p14.mobile-stealth.post-p14-invisibility.lifecycle-and-hep-fail-closed"

$skills = @(Import-Csv -LiteralPath $skillsPath -Delimiter ([char]9))
$scoutMovement = @($skills | Where-Object { [string]$_.NAME -ceq "outdoors_scout_movement_02" })
$rangerMovement = @($skills | Where-Object { [string]$_.NAME -ceq "outdoors_ranger_movement_01" })
$rangerMaster = @($skills | Where-Object { [string]$_.NAME -ceq "outdoors_ranger_master" })
$jediMentalFour = @($skills | Where-Object { [string]$_.NAME -ceq "force_discipline_powers_mental_04" })
Assert-Contract ($scoutMovement.Count -eq 1 -and
    [string]$scoutMovement[0].COMMANDS -match '(^|,)maskscent(,|$)' -and
    [string]$scoutMovement[0].SKILL_MODS -match '(^|,)mask_scent=20(,|$)') "p14.mobile-stealth.maskscent-skill-preserved"
Assert-Contract ($rangerMovement.Count -eq 1 -and
    [string]$rangerMovement[0].COMMANDS -match '(^|,)conceal(,|$)' -and
    [string]$rangerMovement[0].SKILL_MODS -match '(^|,)camouflage=40(,|$)') "p14.mobile-stealth.conceal-skill-preserved"
Assert-Contract ($rangerMaster.Count -eq 1 -and
    [string]$rangerMaster[0].COMMANDS -notmatch '(^|,)(urbanStealth|wildernessStealth)(,|$)' -and
    $jediMentalFour.Count -eq 1 -and
    [string]$jediMentalFour[0].COMMANDS -match '(^|,)animalAttack(,|$)' -and
    [string]$jediMentalFour[0].COMMANDS -notmatch '(^|,)forceCloak(,|$)') `
    "p14.mobile-stealth.post-p14-invisibility.absent-from-p14-skills"

$commandRows = @(Import-Csv -LiteralPath $commandTablePath -Delimiter ([char]9))
$buffRows = @(Import-Csv -LiteralPath $buffTablePath -Delimiter ([char]9))
$jediActionRows = @(Import-Csv -LiteralPath $jediActionsPath -Delimiter ([char]9))
Assert-Contract (@($commandRows | Where-Object {
        [string]$_.commandName -in @("urbanStealth", "wildernessStealth")
    }).Count -eq [int]$contract.expected.retainedPostP14CommandRows -and
    @($buffRows | Where-Object {
        [string]$_.NAME -in @("invis_urbanStealth", "invis_wildernessStealth", "invis_forceCloak")
    }).Count -eq [int]$contract.expected.retainedPostP14BuffRows -and
    @($jediActionRows | Where-Object {
        [string]$_.actionName -ceq "forceCloak"
    }).Count -eq [int]$contract.expected.retainedPostP14JediActionRows) `
    "p14.mobile-stealth.post-p14-invisibility.compatibility-data-preserved"

$spyContractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PostNgeSpyPlayerRuntimeRetirement)
$spyContract = Get-Content -LiteralPath $spyContractPath -Raw | ConvertFrom-Json
Assert-Contract ([string]$spyContract.status -ceq "ready" -and
    [bool]$contract.expected.postNgeSpyPlayerRuntimeRetired -and
    @($spyContract.expected.precuMechanicsPreserved) -contains "maskScent" -and
    @($spyContract.expected.precuMechanicsPreserved) -contains "conceal") "p14.mobile-stealth.spy-retirement-continuity"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "p14.mobile-stealth.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) (
            "p14.mobile-stealth.direct-source-pin")
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.stealth -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) "p14.mobile-stealth.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.mobile-stealth.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.mobile-stealth.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU mobile stealth detection authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU mobile stealth detection authority contract passed."
