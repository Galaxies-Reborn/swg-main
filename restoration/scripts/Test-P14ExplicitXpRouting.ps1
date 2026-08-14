param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14ExplicitXpRouting)) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$xpPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.xpLibrary)
$basePlayerPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.playerInitialization)
$runtimeProbePath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.runtimeProbe)
$baseClassPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.baseClass)
$campingPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.campingLibrary)
$healingPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.healingLibrary)
$consumablePath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.consumableLibrary)
$campMasterPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.campMaster)
$campControlPanelPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.campControlPanel)
$quickHealPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.quickHealCommand)

foreach ($path in @(
        $xpPath,
        $basePlayerPath,
        $runtimeProbePath,
        $baseClassPath,
        $campingPath,
        $healingPath,
        $consumablePath,
        $campMasterPath,
        $campControlPanelPath,
        $quickHealPath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required source file is missing: $path"
    }
}

$xp = Get-Content -LiteralPath $xpPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$runtimeProbe = Get-Content -LiteralPath $runtimeProbePath -Raw
$baseClass = Get-Content -LiteralPath $baseClassPath -Raw
$camping = Get-Content -LiteralPath $campingPath -Raw
$healing = Get-Content -LiteralPath $healingPath -Raw
$consumable = Get-Content -LiteralPath $consumablePath -Raw
$campMaster = Get-Content -LiteralPath $campMasterPath -Raw
$campControlPanel = Get-Content -LiteralPath $campControlPanelPath -Raw
$quickHeal = Get-Content -LiteralPath $quickHealPath -Raw

$dsrcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "dsrc"
})
if ($dsrcPin.Count -ne 1 -or
    [string]$dsrcPin[0].commit -cne
        [string]$contract.buildEvidence.directSourceCommit)
{
    throw "The explicit XP-routing contract is not pinned to the committed Java source."
}
$currentSourcePaths = [ordered]@{
    xpLibrary = $xpPath
    playerInitialization = $basePlayerPath
    runtimeProbe = $runtimeProbePath
    baseClass = $baseClassPath
    campingLibrary = $campingPath
    healingLibrary = $healingPath
    consumableLibrary = $consumablePath
    campMaster = $campMasterPath
    campControlPanel = $campControlPanelPath
    quickHealCommand = $quickHealPath
}
foreach ($entry in $currentSourcePaths.GetEnumerator())
{
    $actualHash =
        (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $entry.Value).Hash.ToLowerInvariant()
    $expectedHash =
        $contract.buildEvidence.currentSourceSha256.psobject.Properties[
            $entry.Key].Value
    if ([string]$actualHash -cne [string]$expectedHash)
    {
        throw "Committed explicit XP-routing source hash mismatch: $($entry.Key)."
    }
}

function Get-Section([string]$Text, [string]$Start, [string]$End)
{
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0)
    {
        throw "Missing section start: $Start"
    }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($endIndex -lt 0)
    {
        throw "Missing section end: $End"
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Get-BracedBlock([string]$Text, [string]$Signature)
{
    $startIndex = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($startIndex -lt 0)
    {
        throw "Missing braced block: $Signature"
    }
    $openIndex = $Text.IndexOf("{", $startIndex, [StringComparison]::Ordinal)
    if ($openIndex -lt 0)
    {
        throw "Missing opening brace for: $Signature"
    }
    $depth = 0
    for ($index = $openIndex; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{')
        {
            ++$depth
        }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0)
            {
                return $Text.Substring(
                    $startIndex,
                    $index - $startIndex + 1)
            }
        }
    }
    throw "Missing closing brace for: $Signature"
}

function Get-LiteralCount([string]$Text, [string]$Needle)
{
    return [regex]::Matches(
        $Text,
        [regex]::Escape($Needle),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message)
{
    if (-not $Text.Contains($Needle))
    {
        throw $Message
    }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message)
{
    if ($Text.Contains($Needle))
    {
        throw $Message
    }
}

$unmodified = Get-Section $xp `
    "public static boolean _grantUnmodifiedExperience" `
    "public static boolean grantCraftingXpChance"
$activeRoutes = Get-Section $xp `
    "public static int grantSocialStyleXp" `
    "public static void displayXpMsg"

Assert-NotContains $unmodified "skill_template.isQualifiedForWorkingSkill" "XP accumulation still qualifies an NGE working skill."
Assert-NotContains $unmodified "skill_template.earnWorkingSkill" "XP accumulation still auto-awards an NGE working skill."
Assert-NotContains $activeRoutes "skill_template." "An active style XP route still consults the retired class template."
Assert-NotContains $basePlayer "skill_template.validateWorkingSkill(self);" "Player initialization still validates the retired working skill."
Assert-NotContains $xp "TRADER_XP_MOD" "The fixed NGE trader XP multiplier is still present."
Assert-NotContains $xp "ENTERTAINER_XP_MOD" "The fixed NGE entertainer XP multiplier is still present."
Assert-NotContains $xp "CRAFTING_MERCHANT_EXCHANGE_RATE" "The NGE crafting-to-merchant template exchange is still present."

Assert-Contains $activeRoutes "return grant(player, directXpType, amount, false);" "Explicit style XP routes do not grant their normalized XP type."
Assert-Contains $activeRoutes "return grant(player, CRAFTING_GENERAL, amount, false);" "Generic crafting quest XP does not fall back to crafting_general."
Assert-Contains $xp "return COMBAT_GENERAL;" "Generic combat quest XP does not fall back to combat_general."
Assert-Contains $xp "return ENTERTAINER;" "Generic social quest XP does not fall back to entertainer."
Assert-Contains $xp "return CRAFTING_GENERAL;" "Generic crafting XP does not fall back to crafting_general."
Assert-Contains $xp "xpType = COMBAT_GENERAL;" "Combined combat XP messages still depend on a working class template."
Assert-Contains $runtimeProbe "int baselineSkills = getSkillCount(player);" "The XP-routing runtime probe does not lock its pre-grant skill count."
Assert-Contains $runtimeProbe "boolean skillsStable = observedSkills == baselineSkills;" "The XP-routing runtime probe does not verify that XP cannot auto-award a skill."
Assert-Contains $runtimeProbe "grantExperiencePoints(player, effectiveType, -delta);" "The XP-routing runtime probe does not restore its XP mutation."

$registerVisitor = Get-BracedBlock $camping `
    "public static boolean registerCampVisitor"
$recordHealing = Get-BracedBlock $camping `
    "public static boolean recordCampHealingEvent"
$calculateCampXp = Get-BracedBlock $camping `
    "public static int calculateCampExperience"
$claimCampXp = Get-BracedBlock $camping `
    "public static boolean claimCampExperience"
$awardCampXp = Get-BracedBlock $camping `
    "public static boolean awardCampExperienceAndNuke"
$beginOwnerAbsence = Get-BracedBlock $camping `
    "public static boolean beginCampOwnerAbsence"
$cancelOwnerAbsence = Get-BracedBlock $camping `
    "public static boolean cancelCampOwnerAbsence"
$campAbandoned = Get-BracedBlock $camping `
    "public static boolean campAbandoned"
$campAttach = Get-BracedBlock $campMaster `
    "public int OnAttach(obj_id self)"
$addCampMember = Get-BracedBlock $campMaster `
    "public void addCampMember"
$campExit = Get-BracedBlock $campMaster `
    "public int OnTriggerVolumeExited"
$campHealingHandler = Get-BracedBlock $campMaster `
    "public int handleCampHealingReceived"
$naturalExpiry = Get-BracedBlock $campMaster `
    "public int handleCampNaturalExpiry"
$ownerAbsenceCallback = Get-BracedBlock $campMaster `
    "public int handleCampRestoreHeartbeat"
$radialSelect = Get-BracedBlock $campControlPanel `
    "public int OnObjectMenuSelect"
$healingReceived = Get-BracedBlock $basePlayer `
    "public int OnHealingReceived"
$hotTick = Get-BracedBlock $basePlayer `
    "public int handleHealOverTimeTick"
$combatHeal = Get-BracedBlock $healing `
    "public static boolean performHealDamage"
$startHot = Get-BracedBlock $healing `
    "public static void startHealOverTime(obj_id medic"
$legacyHeal = Get-BracedBlock $healing `
    "public static int healDamage(obj_id source, obj_id target, int attrib, int amount)"
$explicitHeal = Get-BracedBlock $healing `
    "public static int healDamage(obj_id source, obj_id target, int attrib, int amount, boolean notifyHealingReceived)"

$campContract = $contract.campXpContract
if (
    [string]$campContract.experienceType -cne "camp" -or
    [bool]$campContract.loginConversionToScout -or
    (@($campContract.campPowerBaseXp) -join ",") -cne
        "360,640,800,1000,1100,1250" -or
    [int]$campContract.authoredDurationSeconds -ne 3600 -or
    [int]$campContract.fullDurationCreditSeconds -ne 900 -or
    [int]$campContract.naturalExpirySeconds -ne 3300 -or
    [int]$campContract.ownerAbandonGraceSeconds -ne 60 -or
    [int]$campContract.awardPaths.cleanupOrAbandonCallsites -ne 12 -or
    [bool]$campContract.awardPaths.cleanupOrAbandonAwards)
{
    throw "The explicit XP-routing contract no longer records the exact Publish 14.1 camp constants and no-award cleanup count."
}

Assert-NotContains $basePlayer 'getExperiencePoints(self, "camp")' "Player login still reads camp XP for conversion."
Assert-NotContains $basePlayer 'grantExperiencePoints(self, "scout"' "Player login still converts camp XP into scout XP."
Assert-NotContains $basePlayer 'grantExperiencePoints(self, "camp", -' "Player login still removes stored camp XP."
Assert-Contains $baseClass "public static final int TRIG_HEALING_RECEIVED = 308;" "The Java trigger id for camp healing observation is missing."
Assert-Contains $baseClass "private static native int _healDamage(long target, long healer, int attrib, int amount, boolean notifyHealingReceived);" "The explicit damage-healing JNI declaration is missing."
Assert-Contains $baseClass "return _healDamage(getLongWithNull(target), getLongWithNull(healer), attrib, amount, notifyHealingReceived);" "The Java damage-healing wrapper does not preserve healer identity and the notification flag."

if (-not [regex]::IsMatch(
        $camping,
        '(?s)CAMP_BASE_XP\s*=\s*\{\s*360\s*,\s*640\s*,\s*800\s*,\s*1000\s*,\s*1100\s*,\s*1250\s*\}'))
{
    throw "Camp-power base XP is not the exact Publish 14.1 360/640/800/1000/1100/1250 table."
}
Assert-Contains $camping "public static final int CAMP_XP_DURATION = 3600;" "The authored camp XP duration is not 3600 seconds."
Assert-Contains $camping "public static final int CAMP_XP_FULL_DURATION = CAMP_XP_DURATION / 4;" "Full camp XP is not reached at one quarter of the authored duration."
Assert-Contains $camping "public static final float CAMP_NATURAL_EXPIRY = 3300.0f;" "Natural camp expiry is not 3300 seconds."
Assert-Contains $camping "public static final float HEARTBEAT_RESTORE = 60.0f;" "Owner absence grace is not 60 seconds."

Assert-Contains $camping "registerCampVisitor(master, creator);" "Camp creation does not register the owner as the implicit first occupant."
Assert-Contains $campAttach "camping.registerCampVisitor(self, owner);" "Camp attach does not idempotently restore the owner visitor record."
Assert-Contains $addCampMember "camping.registerCampVisitor(self, who);" "Camp entry does not register a unique visitor."
Assert-Contains $registerVisitor "if (recorded == visitor)" "Camp visitors are not de-duplicated by player object id."
Assert-Contains $registerVisitor "new obj_id[visitors.length + 1]" "A distinct visitor is not appended to persistent camp visitor state."
Assert-NotContains $registerVisitor "msgGrantXP" "Visitor registration grants XP directly instead of deferring to the owner claim."
Assert-Contains $calculateCampXp "Math.max(0, getUniqueCampVisitorCount(master) - 1)" "The owner is not excluded from the unique-visitor bonus."
Assert-Contains $calculateCampXp "(int)(uniqueVisitors * (baseXp / 30) * durationUsed)" "The unique-visitor term is not the exact integer base/30 duration-scaled formula."

Assert-Contains $recordHealing "getStatus(master) != STATUS_MAINTAIN" "Camp healing can accrue outside maintained status."
Assert-Contains $recordHealing "hasObjVar(master, VAR_CAMP_XP_CLAIMED)" "Camp healing can accrue after an XP claim."
Assert-Contains $recordHealing "healingXp + (CAMP_BASE_XP[baseIndex] / 180)" "A real healing event does not immediately store the exact integer baseXp/180 amount."
Assert-Contains $calculateCampXp "Math.min(1.0f, elapsed / (float)CAMP_XP_FULL_DURATION)" "Camp XP does not use the exact capped duration scale."
Assert-Contains $calculateCampXp "(int)(baseXp * durationUsed)" "Camp XP is missing its duration-scaled base term."
Assert-Contains $calculateCampXp "(int)(healingXp * durationUsed)" "Accumulated baseXp/180 healing credit is not duration-scaled at payout."
Assert-NotContains $recordHealing "actualDelta" "Camp healing XP incorrectly scales with the applied heal amount instead of authored event count."
if ((Get-LiteralCount $campMaster "camping.recordCampHealingEvent(self);") -ne 1)
{
    throw "Camp healing accrual must have exactly one maintained-camp event handler callsite."
}
Assert-Contains $healingReceived "!isIdValid(healer)" "The player healing observer accepts an invalid healer identity."
Assert-Contains $healingReceived "camping.getCurrentCamp(self)" "The player healing observer does not resolve current camp membership."
Assert-Contains $healingReceived "camping.getStatus(camp) != camping.STATUS_MAINTAIN" "The player healing observer accepts a non-maintained camp."
Assert-Contains $healingReceived 'isInTriggerVolume(camp, "camp_" + camp, self)' "The player healing observer does not require real trigger-volume occupancy."
Assert-Contains $healingReceived "camping.HANDLER_CAMP_HEALING" "The player healing observer does not forward the native event to the camp master."
Assert-Contains $campHealingHandler "camping.getCurrentCamp(player) != self" "The camp master does not revalidate current camp membership."
Assert-Contains $campHealingHandler 'isInTriggerVolume(self, "camp_" + self, player)' "The camp master does not revalidate physical camp occupancy."
Assert-NotContains $campHealingHandler "actualDelta > 0" "A clamped zero-delta authored healing event is incorrectly discarded."

Assert-Contains $claimCampXp "hasObjVar(master, VAR_CAMP_XP_CLAIMED)" "Camp XP claims are not guarded by an at-most-once marker."
$claimMarkerIndex = $claimCampXp.IndexOf(
    "setObjVar(master, VAR_CAMP_XP_CLAIMED, true);",
    [StringComparison]::Ordinal)
$ownerGrantIndex = $claimCampXp.IndexOf(
    'pclib.msgGrantXP(owner, "camp", amount)',
    [StringComparison]::Ordinal)
$failedGrantRollbackIndex = $claimCampXp.IndexOf(
    "removeObjVar(master, VAR_CAMP_XP_CLAIMED);",
    [StringComparison]::Ordinal)
if ($claimMarkerIndex -lt 0 -or
    $ownerGrantIndex -le $claimMarkerIndex -or
    $failedGrantRollbackIndex -le $ownerGrantIndex)
{
    throw "The at-most-once claim marker is not written before owner camp XP grant and rolled back only after a failed grant."
}
Assert-Contains $claimCampXp "obj_id owner = getCampOwner(master);" "Camp XP is not routed exclusively through the camp owner."
Assert-Contains $claimCampXp '!owner.isLoaded()' "Camp XP attempts a grant without a loaded owner."
Assert-NotContains ($calculateCampXp + $claimCampXp + $awardCampXp) "group." "Camp XP is split or modified through group state."
Assert-NotContains ($calculateCampXp + $claimCampXp + $awardCampXp) "getGroupObject" "Camp XP consults a group recipient."
if ((Get-LiteralCount $camping 'pclib.msgGrantXP(owner, "camp", amount)') -ne 1)
{
    throw "Camp XP must have exactly one owner-only grant call using the camp pool."
}
Assert-Contains $awardCampXp "return claimCampExperience(master) && nukeCamp(master);" "The award path does not claim before destroying the camp."
Assert-Contains $awardCampXp "if (hasObjVar(master, VAR_CAMP_XP_CLAIMED))" "A claimed camp cannot retry cleanup without attempting a second grant."

Assert-Contains $campAttach "camping.HANDLER_CAMP_NATURAL_EXPIRY" "Camp attach does not schedule natural expiry."
Assert-Contains $campAttach "camping.CAMP_NATURAL_EXPIRY" "Natural expiry is not scheduled with the canonical 3300-second constant."
Assert-Contains $naturalExpiry "camping.getStatus(self) == camping.STATUS_MAINTAIN" "Natural expiry is not restricted to a maintained camp."
Assert-Contains $naturalExpiry "camping.awardCampExperienceAndNuke(self)" "Natural expiry does not use the award-bearing path."
Assert-NotContains $naturalExpiry "VAR_CAMP_ABANDON_PENDING" "Natural expiry is incorrectly suppressed during the owner-exit grace window."
Assert-Contains $radialSelect "if (owner == player)" "Camp disband is not owner-only."
Assert-Contains $radialSelect "camping.awardCampExperienceAndNuke(master);" "Owner radial disband does not use the award-bearing path."
if ((Get-LiteralCount ($campMaster + $campControlPanel) "camping.awardCampExperienceAndNuke(") -ne 2)
{
    throw "Camp XP must be reachable only from natural expiry and owner radial disband."
}
if ((Get-LiteralCount $campMaster "camping.nukeCamp(self);") -ne 12)
{
    throw "The camp master no longer has exactly 12 direct cleanup/abandon nuke callsites."
}
Assert-NotContains $campAbandoned "claimCampExperience" "Camp abandonment incorrectly claims XP."
Assert-NotContains $campAbandoned "awardCampExperienceAndNuke" "Camp abandonment incorrectly uses an award-bearing cleanup path."
Assert-NotContains $campAbandoned "msgGrantXP" "Camp abandonment grants XP directly."
Assert-Contains $campAbandoned "setObjVar(master, VAR_CAMP_HEALING_XP, 0);" "Camp abandonment does not zero accumulated healing XP."
Assert-Contains $campAbandoned "setObjVar(master, VAR_CAMP_XP, 0);" "Camp abandonment does not zero the retired aggregate camp XP state."
Assert-Contains $campAbandoned "setStatus(master, STATUS_ABANDONED);" "Camp abandonment does not transition to abandoned status."

Assert-Contains $campExit "camping.beginCampOwnerAbsence(self);" "Owner exit does not start the 60-second sequence-bound grace period."
Assert-NotContains $campExit "camping.campAbandoned(self)" "Owner exit abandons the camp immediately instead of preserving maintained status."
Assert-NotContains $campExit "camping.nukeCamp(self)" "Owner exit destroys the camp before the grace callback."
Assert-Contains $beginOwnerAbsence "getStatus(master) != STATUS_MAINTAIN" "Owner absence may start outside maintained status."
Assert-Contains $beginOwnerAbsence "hasObjVar(master, VAR_CAMP_ABANDON_PENDING)" "Duplicate owner-absence callbacks are not suppressed."
Assert-Contains $beginOwnerAbsence "VAR_CAMP_ABANDON_SEQUENCE) + 1" "Owner absence does not advance its sequence token."
Assert-Contains $beginOwnerAbsence "setObjVar(master, VAR_CAMP_ABANDON_PENDING, true);" "Owner absence does not record a pending callback."
Assert-Contains $beginOwnerAbsence "sendCampRestoreHeartbeat(master, sequence);" "Owner absence does not schedule the sequence-bound 60-second callback."
Assert-NotContains $beginOwnerAbsence "setStatus" "Beginning owner absence changes maintained status before grace expires."
Assert-Contains $cancelOwnerAbsence "VAR_CAMP_ABANDON_SEQUENCE) + 1" "Owner reentry does not invalidate the pending callback sequence."
Assert-Contains $cancelOwnerAbsence "removeObjVar(master, VAR_CAMP_ABANDON_PENDING);" "Owner reentry does not clear pending absence state."
Assert-Contains $addCampMember "camping.cancelCampOwnerAbsence(self);" "Owner reentry does not cancel the pending grace callback."
Assert-Contains $ownerAbsenceCallback "sequence !=" "The owner-absence callback does not require the matching sequence."
Assert-Contains $ownerAbsenceCallback "camping.getStatus(self) != camping.STATUS_MAINTAIN" "The owner-absence callback can abandon a camp outside maintained status."
Assert-Contains $ownerAbsenceCallback "!hasObjVar(self, camping.VAR_CAMP_ABANDON_PENDING)" "The owner-absence callback does not require pending state."
Assert-Contains $ownerAbsenceCallback "camping.cancelCampOwnerAbsence(self);" "A returned owner does not invalidate the delayed callback."
if ((Get-LiteralCount $ownerAbsenceCallback "camping.campAbandoned(self);") -ne 1)
{
    throw "Only the matching unresolved owner-absence callback may take the no-award abandonment branch."
}
Assert-NotContains $ownerAbsenceCallback "awardCampExperienceAndNuke" "The owner-absence callback incorrectly awards camp XP."

$combatHealPattern =
    '(?s)healDamage\s*\(\s*medic\s*,\s*defenderDatum\.id\s*,\s*action_data\.attribute\s*,\s*toHeal\s*,\s*true\s*\)'
if ([regex]::Matches($combatHeal, $combatHealPattern).Count -ne 1)
{
    throw "Normal combat healing does not request exactly one native observer event per authored target/pool call."
}
Assert-Contains $combatHeal "pvp.bfCreditForHealing(medic, totalDelta);" "Normal combat healing lost its existing aggregate battle-fatigue credit."
Assert-NotContains $explicitHeal "bfCreditForHealing" "The explicit five-argument healing seam duplicates caller battle-fatigue credit."
Assert-Contains $legacyHeal "healDamage(source, target, attrib, amount, true)" "The source-aware four-argument PRE-CU healing helper does not request its Core3-default observer event."
if ((Get-LiteralCount $legacyHeal "pvp.bfCreditForHealing(source, delta);") -ne 1)
{
    throw "The source-aware four-argument PRE-CU healing helper must preserve exactly one positive battle-fatigue credit."
}
Assert-Contains $explicitHeal "applyDamageHealing(" "The explicit Java heal does not reach the authoritative native damage-healing method."
Assert-Contains $startHot "if (!isIdValid(medic))" "Source-less healing-over-time does not detect a missing healer."
Assert-Contains $startHot "medic = target;" "Source-less healing-over-time does not normalize to target-as-healer."
$initialHotPattern =
    '(?s)healDamage\s*\(\s*medic\s*,\s*target\s*,\s*HEALTH\s*,\s*healPerTick\s*,\s*true\s*\)'
if ([regex]::Matches($startHot, $initialHotPattern).Count -ne 1)
{
    throw "Healing-over-time does not request exactly one observer event for its authored initial tick."
}
Assert-Contains $startHot 'd.put("notifyCampHealing", true);' "Healing-over-time does not propagate observer authority to delayed ticks."
$delayedHotPattern =
    '(?s)healing\.healDamage\s*\(\s*medic\s*,\s*self\s*,\s*HEALTH\s*,\s*heal\s*,\s*notifyCampHealing\s*\)'
if ([regex]::Matches($hotTick, $delayedHotPattern).Count -ne 1)
{
    throw "A delayed healing-over-time tick does not request exactly one propagated observer event."
}
Assert-Contains $hotTick 'd.put("notifyCampHealing", notifyCampHealing);' "Healing-over-time does not preserve the observer flag for each later authored tick."

$expectedHashes = $contract.buildEvidence.sourceSha256
$actualProbeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeProbePath).Hash.ToLowerInvariant()
if ($actualProbeHash -cne [string]$expectedHashes."precu_xp_routing_runtime.java")
{
    throw "precu_xp_routing_runtime.java hash mismatch. Expected $($expectedHashes.'precu_xp_routing_runtime.java'), got $actualProbeHash."
}

if ($Expectation -eq "Ready")
{
    $patchPath = Join-Path $restorationRoot ([string]$contract.buildEvidence.overlayPatch -replace "^restoration/", "")
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne [long]$contract.buildEvidence.overlayPatchBytes -or
        $patchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "The explicit XP-routing overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 explicit XP-routing contract passed."
