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

foreach ($path in @($stealthPath, $xpPath, $aiAggroPath, $combatBasePath, $combatActionsPath, $skillsPath))
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
    "p14.mobile-stealth.force-cloak-adjustment-preserved")
Assert-Contract ($aiAggro.Contains("stealth.passiveDetectHiddenTarget(target, self, 100)") -and
    $stealth.Contains("float finalChanceToDetect = getDetectChance(target, detector, baseChanceToDetect);") -and
    $stealth.Contains("return passiveDetectHiddenTarget(bubbleHolder, breacher, volume);")) (
        "p14.mobile-stealth.production-call-graph")

$skills = @(Import-Csv -LiteralPath $skillsPath -Delimiter ([char]9))
$scoutMovement = @($skills | Where-Object { [string]$_.NAME -ceq "outdoors_scout_movement_02" })
$rangerMovement = @($skills | Where-Object { [string]$_.NAME -ceq "outdoors_ranger_movement_01" })
Assert-Contract ($scoutMovement.Count -eq 1 -and
    [string]$scoutMovement[0].COMMANDS -match '(^|,)maskscent(,|$)' -and
    [string]$scoutMovement[0].SKILL_MODS -match '(^|,)mask_scent=20(,|$)') "p14.mobile-stealth.maskscent-skill-preserved"
Assert-Contract ($rangerMovement.Count -eq 1 -and
    [string]$rangerMovement[0].COMMANDS -match '(^|,)conceal(,|$)' -and
    [string]$rangerMovement[0].SKILL_MODS -match '(^|,)camouflage=40(,|$)') "p14.mobile-stealth.conceal-skill-preserved"

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
