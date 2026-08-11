[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrcRoot = Join-Path $root "dsrc"
$srcRoot = Join-Path $root "src"
$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14JavaSkillGrantCallbackInventoryClosure)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Get-TextSha256([string]$Text)
{
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing Java surface: $Signature" }
    $open = $Text.IndexOf("{", $start)
    if ($open -lt 0) { throw "Missing opening brace: $Signature" }
    $depth = 0
    for ($i = $open; $i -lt $Text.Length; $i++)
    {
        if ($Text[$i] -ceq '{') { $depth++ }
        elseif ($Text[$i] -ceq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $i - $start + 1) }
        }
    }
    throw "Missing closing brace: $Signature"
}

$directPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$nativePin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$directCommit = (& git -C $dsrcRoot rev-parse HEAD).Trim()
$nativeCommit = (& git -C $srcRoot rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $directPin.Count -eq 1 -and $nativePin.Count -eq 1 -and
    [string]$directPin[0].commit -ceq $directCommit -and
    [string]$nativePin[0].commit -ceq $nativeCommit -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $nativeCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "Skill lifecycle callback closure is not pinned to checked-out direct source."

$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"
Assert-Contract ($null -ne (Get-Command rg -ErrorAction SilentlyContinue)) `
    "ripgrep is required for the exact skill lifecycle callback inventory."

$records = [Collections.Generic.List[string]]::new()
$callbackPatterns = [ordered]@{
    AboutToBeGranted = [string]$contract.inventory.patterns.aboutToBeGranted
    AboutToBeRevoked = [string]$contract.inventory.patterns.aboutToBeRevoked
    Granted = [string]$contract.inventory.patterns.granted
    Revoked = [string]$contract.inventory.patterns.revoked
    ModDone = [string]$contract.inventory.patterns.modDone
    ModsChanged = [string]$contract.inventory.patterns.modsChanged
    TemplateChanged = [string]$contract.inventory.patterns.templateChanged
}
$callbackCounts = @{
    AboutToBeGranted = [int]$contract.inventory.aboutToBeGrantedHandlers
    AboutToBeRevoked = [int]$contract.inventory.aboutToBeRevokedHandlers
    Granted = [int]$contract.inventory.grantedHandlers
    Revoked = [int]$contract.inventory.revokedHandlers
    ModDone = [int]$contract.inventory.modDoneHandlers
    ModsChanged = [int]$contract.inventory.modsChangedHandlers
    TemplateChanged = [int]$contract.inventory.templateChangedHandlers
}
$callbackHashes = @{
    AboutToBeGranted = [string]$contract.inventory.aboutToBeGrantedInventorySha256
    AboutToBeRevoked = [string]$contract.inventory.aboutToBeRevokedInventorySha256
    Granted = [string]$contract.inventory.grantedInventorySha256
    Revoked = [string]$contract.inventory.revokedInventorySha256
    ModDone = [string]$contract.inventory.modDoneInventorySha256
    ModsChanged = [string]$contract.inventory.modsChangedInventorySha256
    TemplateChanged = [string]$contract.inventory.templateChangedInventorySha256
}
foreach ($callbackKind in $callbackPatterns.Keys)
{
    $kindRecords = [Collections.Generic.List[string]]::new()
    foreach ($line in @(& rg -n --no-heading $callbackPatterns[$callbackKind] `
        $scriptRoot --glob "*.java"))
    {
        Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
            "Could not parse $callbackKind callback inventory line."
        $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
        Assert-Contract ($absolutePath.StartsWith(
            $scriptRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) `
            "$callbackKind callback escaped the Java source root."
        $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
        $record = "${relativePath}:$($Matches[2])|$($Matches[3].Trim())"
        $kindRecords.Add($record)
        $records.Add("$callbackKind|$record")
    }
    $kindRecords = @($kindRecords | Sort-Object)
    Assert-Contract ($kindRecords.Count -eq $callbackCounts[$callbackKind] -and
        (Get-TextSha256 ($kindRecords -join "`n")) -ceq $callbackHashes[$callbackKind]) `
        "Complete Java $callbackKind callback inventory drifted."
}
$records = @($records | Sort-Object)
$expectedPaths = @($contract.sourceFiles.PSObject.Properties |
    ForEach-Object { [string]$_.Value } | Sort-Object)
$actualPaths = @($records | ForEach-Object {
    Assert-Contract ($_ -match '^[^|]+\|(.*?):\d+\|') `
        "Could not isolate a lifecycle callback source path."
    $Matches[1]
} | Sort-Object -Unique)
Assert-Contract ($records.Count -eq [int]$contract.inventory.handlers -and
    $actualPaths.Count -eq [int]$contract.inventory.sourceFiles -and
    ($actualPaths -join "`n") -ceq ($expectedPaths -join "`n") -and
    (Get-TextSha256 ($records -join "`n")) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 ($actualPaths -join "`n")) -ceq [string]$contract.inventory.sourceSetSha256) `
    "Complete Java skill lifecycle callback inventory drifted."

$texts = @{}
$contentRows = [Collections.Generic.List[string]]::new()
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $name = [string]$property.Name
    $relativePath = [string]$property.Value
    $path = Join-Path $scriptRoot $relativePath
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "Skill lifecycle callback source is missing: $relativePath"
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-Contract ($actualHash -ceq [string]$contract.sourceSha256.$name) `
        "Skill lifecycle callback source evidence drifted: $name"
    $contentRows.Add("$relativePath|$actualHash")
    $texts[$name] = Get-Content -LiteralPath $path -Raw
}
Assert-Contract ((Get-TextSha256 (@($contentRows | Sort-Object) -join "`n")) -ceq
    [string]$contract.inventory.sourceContentSha256) `
    "Skill lifecycle callback aggregate source evidence drifted."

$supportingTexts = @{}
foreach ($property in $contract.supportingSourceFiles.PSObject.Properties)
{
    $name = [string]$property.Name
    $relativePath = [string]$property.Value
    $path = Join-Path $scriptRoot $relativePath
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "Skill lifecycle supporting source is missing: $relativePath"
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-Contract ($actualHash -ceq [string]$contract.supportingSourceSha256.$name) `
        "Skill lifecycle supporting source evidence drifted: $name"
    $supportingTexts[$name] = Get-Content -LiteralPath $path -Raw
}

$baseGrant = Get-BracedSurface $texts.basePlayer "public int OnSkillGranted"
$retiredAt = $baseGrant.IndexOf("skill.isRetiredNgeProgressionSkillName(skillName)",
    [StringComparison]::Ordinal)
$revokeAt = $baseGrant.IndexOf("revokeSkillSilent(self, skillName)",
    [StringComparison]::Ordinal)
$overrideAt = $baseGrant.IndexOf("return SCRIPT_OVERRIDE", $retiredAt,
    [StringComparison]::Ordinal)
$effectAt = $baseGrant.IndexOf("playClientEffectObj", [StringComparison]::Ordinal)
Assert-Contract ($retiredAt -ge 0 -and $revokeAt -gt $retiredAt -and
    $overrideAt -gt $revokeAt -and $effectAt -gt $overrideAt -and
    $baseGrant.Contains("retirePostNgePassiveProfessionState(self)") -and
    $baseGrant.Contains("retirePostNgeSpyPlayerState(self)") -and
    $baseGrant.Contains("badge.grantMasterSkillBadge(self, skillName)") -and
    $baseGrant.Contains("setupNovicePilotSkill(self, skillName)") -and
    $baseGrant.Contains("allowedBySpaceExpansion(self, skillName)") -and
    $baseGrant.Contains("recomputeCommandSeries(self)")) `
    "Base-player skill-grant callback no longer rejects NGE state before PRE-CU effects."

$baseAboutToRevoke = Get-BracedSurface $texts.basePlayer "public int OnSkillAboutToBeRevoked"
Assert-Contract ($baseAboutToRevoke.Contains('(toLower(skill)).startsWith("pilot")') -and
    $baseAboutToRevoke.Contains('utils.hasScriptVar(self, "revokePilotSkill")') -and
    $baseAboutToRevoke.Contains("godLevel < 50") -and
    $baseAboutToRevoke.Contains("space_skill.retireWarning(self, skill)") -and
    $baseAboutToRevoke.Contains("return SCRIPT_OVERRIDE") -and
    $baseAboutToRevoke -notmatch '\b(getLevel|setLevel|setSkillTemplate|grantExperiencePoints)\s*\(') `
    "Base-player pre-revoke callback no longer protects authenticated JTL retirement."

$baseRevoke = Get-BracedSurface $texts.basePlayer "public int OnSkillRevoked"
foreach ($required in @(
    'strSkill.startsWith("force_sensitive_")',
    "jedi.recalculateForcePower(self)",
    'strSkill.equals("combat_bountyhunter_investigation_03")',
    "bounty_hunter.getBountyMission(self)",
    'strSkill.startsWith("outdoors_squadleader_")',
    "squad_leader.clearRallyPoint(self)",
    "space_skill.revokeExperienceForRetire(self, strSkill)",
    "utils.unequipAndNotifyUncerted(self)",
    "skill.isRetiredNgeProgressionSkillName(strSkill)",
    "retirePostNgePassiveProfessionState(self)",
    "recomputeCommandSeries(self)",
    "beast_lib.retirePostNgeBeastMasterPlayerState(self)",
    "incubator.retirePostNgeBeastMasterCreationPlayerState(self)"
))
{
    Assert-Contract ($baseRevoke.Contains($required)) `
        "Base-player revoke callback lost retained PRE-CU cleanup: $required"
}
Assert-Contract ($baseRevoke -notmatch
    '\b(grantSkill|grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Base-player revoke callback regained NGE progression mutation authority."

$baseModDone = Get-BracedSurface $texts.basePlayer "public int OnSkillModDone"
Assert-Contract ($baseModDone.Contains('modName.indexOf("food_") == 0') -and
    $baseModDone.Contains("utils.removeScriptVar(self, modName)") -and
    $baseModDone.Contains('trial.bumpSession(self, "displayDefensiveMods")') -and
    $baseModDone.Contains('messageTo(self, "setDisplayOnlyDefensiveMods"') -and
    $baseModDone -notmatch
        '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Base-player skill-mod completion escaped PRE-CU cleanup/presentation authority."

$baseModsChanged = Get-BracedSurface $texts.basePlayer "public int OnSkillModsChanged"
Assert-Contract ($baseModsChanged.Contains('modName.startsWith("constitution")') -and
    $baseModsChanged.Contains('modName.startsWith("stamina")') -and
    $baseModsChanged.Contains("skill.recalcPlayerPools(self, false)") -and
    $baseModsChanged.Contains('modName.startsWith("movement_resist")') -and
    $baseModsChanged.Contains('messageTo(self, "check_movement_immunity"') -and
    $baseModsChanged.Contains('messageTo(self, "setDisplayOnlyDefensiveMods"') -and
    $baseModsChanged -notmatch
        '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Base-player skill-mod change escaped PRE-CU HAM/presentation authority."

$baseTemplateChanged = Get-BracedSurface $texts.basePlayer "public int OnSkillTemplateChanged"
Assert-Contract ($baseTemplateChanged.Contains('hasObjVar(self, "clickRespec")') -and
    $baseTemplateChanged.Contains('removeObjVar(self, "clickRespec")') -and
    $baseTemplateChanged.Contains('hasObjVar(self, "npcRespec")') -and
    $baseTemplateChanged.Contains('removeObjVar(self, "npcRespec")') -and
    $baseTemplateChanged.Contains(
        'detachScript(self, "systems.respec.click_combat_respec")') -and
    $baseTemplateChanged -notmatch
        '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Base-player template-change callback regained NGE template or respec authority."

$beastGrant = Get-BracedSurface $texts.playerBeastmaster "public int OnSkillGranted"
Assert-Contract ($beastGrant.Contains("retirePostNgeBeastMasterPlayerState(self)") -and
    $beastGrant.Contains("return SCRIPT_OVERRIDE") -and
    $beastGrant -notmatch '\b(grantSkill|grantExperiencePoints|setLevel|applyBuff)\s*\(') `
    "Retired Beast Master skill-grant callback regained mutation authority."

$beastRevoke = Get-BracedSurface $texts.playerBeastmaster "public int OnSkillRevoked"
Assert-Contract ($beastRevoke.Contains("retirePostNgeBeastMasterPlayerState(self)") -and
    $beastRevoke.Contains("return SCRIPT_OVERRIDE") -and
    $beastRevoke -notmatch '\b(grantSkill|grantExperiencePoints|setLevel|applyBuff)\s*\(') `
    "Retired Beast Master skill-revoke callback regained mutation authority."

$petGrant = Get-BracedSurface $texts.petMaster "public int OnSkillGranted"
Assert-Contract ($petGrant.Contains('hasObjVar(self, "familiar")') -and
    $petGrant.Contains('messageTo(pet, "doFamiliarTrick"') -and
    $petGrant -notmatch '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|applyBuff)\s*\(') `
    "Retained familiar callback escaped cosmetic-only authority."

$npeGrant = Get-BracedSurface $texts.npeJournal "public int OnSkillGranted"
Assert-Contract ($npeGrant.Contains("utils.isProfession(self, utils.TRADER)") -and
    $npeGrant.Contains("utils.isProfession(self, utils.ENTERTAINER)") -and
    $npeGrant.Contains("npe.sendDelayed3poPopup") -and
    $npeGrant.Contains("newbieTutorialHighlightUIElement") -and
    $npeGrant -notmatch '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
    "Retained NPE skill callback gained progression mutation authority."

$newPlayerRevoke = Get-BracedSurface $texts.newPlayer "public int OnSkillRevoked"
foreach ($required in @(
    "NOVICE_MARKSMAN", "NOVICE_BRAWLER", "NOVICE_MEDIC", "NOVICE_ARTISAN",
    "NOVICE_ENTERTAINER", "NOVICE_SCOUT", "removeObjVar(self"
))
{
    Assert-Contract ($newPlayerRevoke.Contains($required)) `
        "Classic novice quest cleanup drifted: $required"
}
Assert-Contract ($newPlayerRevoke -notmatch
    '\b(grantSkill|grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Classic novice quest cleanup gained progression mutation authority."

$padawanRevoke = Get-BracedSurface $texts.padawanTrials "public int OnSkillRevoked"
Assert-Contract ($padawanRevoke.Contains('skillName.startsWith("force_sensitive")') -and
    $padawanRevoke.Contains("jedi_trials.isEligibleForJediPadawanTrials(self)") -and
    $padawanRevoke.Contains("SID_PADAWAN_TRIALS_NO_LONGER_ELIGIBLE") -and
    $padawanRevoke -notmatch '\b(grantSkill|grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
    "Publish 14.1 Padawan trial revocation warning drifted."

$knightRevoke = Get-BracedSurface $texts.knightTrials "public int OnSkillRevoked"
Assert-Contract ($knightRevoke.Contains('skillName.startsWith("force_discipline")') -and
    $knightRevoke.Contains("jedi_trials.isEligibleForJediKnightTrials(self)") -and
    $knightRevoke.Contains("SID_KNIGHT_TRIALS_NO_LONGER_ELIGIBLE") -and
    $knightRevoke -notmatch '\b(grantSkill|grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
    "Publish 14.1 Knight trial revocation warning drifted."

$forceRankGrant = Get-BracedSurface $texts.playerForceRank "public int OnSkillGranted"
$rankTitleGrantCount = ([regex]::Matches($forceRankGrant, '\bgrantSkill\s*\(')).Count
Assert-Contract ($rankTitleGrantCount -eq [int]$contract.expected.retainedForceRankTitleGrantRules -and
    $forceRankGrant.Contains('skill.equals("force_rank_dark_rank_09")') -and
    $forceRankGrant.Contains('skill.equals("force_rank_light_rank_09")') -and
    $forceRankGrant.Contains('skill.equals("force_rank_dark_rank_05")') -and
    $forceRankGrant.Contains('skill.equals("force_rank_light_rank_05")') -and
    $forceRankGrant.Contains("JEDI_MASTER_TITLE_SKILL") -and
    $forceRankGrant.Contains("JEDI_GUARDIAN_TITLE_SKILL") -and
    $forceRankGrant -notmatch '\b(grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
    "Publish 14.1 Force Rank title callback drifted."

$forceRankRevoke = Get-BracedSurface $texts.playerForceRank "public int OnSkillRevoked"
Assert-Contract ($forceRankRevoke.Contains("force_rank.SCRIPT_VAR_SKILL_RESYNC") -and
    $forceRankRevoke.Contains("force_rank.getForceRank(self)") -and
    $forceRankRevoke.Contains("force_rank.getCouncilAffiliation(self)") -and
    $forceRankRevoke.Contains("force_rank.demoteForceRank(self, skill_rank - 1)") -and
    $forceRankRevoke.Contains("force_rank.removeFromForceRankSystem(self, true)") -and
    $forceRankRevoke -notmatch '\b(grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Publish 14.1 Force Rank revocation callback drifted."

$forceKickoff = $texts.forceSensitiveKickoff
$canonicalKickoffId = 'quest.force_sensitive.fs_kickoff'
$incorrectKickoffId = 'quest.force_sensitive_fs_kickoff'
$canonicalDetach = 'detachScript(self, "' + $canonicalKickoffId + '")'
$canonicalDetachCount = ([regex]::Matches($forceKickoff,
    [regex]::Escape($canonicalDetach))).Count
$login = Get-BracedSurface $forceKickoff "public int OnLogin"
$stageClearAt = $login.IndexOf('removeObjVar(self, "fs_kickoff_stage")',
    [StringComparison]::Ordinal)
$loginDetachAt = $login.IndexOf($canonicalDetach, [StringComparison]::Ordinal)
$forceAboutToRevoke = Get-BracedSurface $forceKickoff "public int OnSkillAboutToBeRevoked"
Assert-Contract ($canonicalDetachCount -eq
        [int]$contract.expected.forceSensitiveCanonicalDetachCalls -and
    -not $forceKickoff.Contains($incorrectKickoffId) -and
    [int]$contract.expected.forceSensitiveIncorrectDetachCalls -eq 0 -and
    $stageClearAt -ge 0 -and $loginDetachAt -gt $stageClearAt -and
    $forceAboutToRevoke.Contains('strSkill.startsWith("force_title")') -and
    $forceAboutToRevoke.Contains('!hasObjVar(self, "clickRespec.granting")') -and
    $forceAboutToRevoke.Contains('new string_id("jedi_spam", "revoke_force_title")') -and
    $forceAboutToRevoke.Contains("return SCRIPT_OVERRIDE") -and
    $forceAboutToRevoke -notmatch
        '\b(grantSkill|grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Force-sensitive kickoff lifecycle no longer detaches canonically or protects PRE-CU titles."

$forceQuestLibrary = $supportingTexts.forceSensitiveQuestLibrary
Assert-Contract ($forceQuestLibrary.Contains(
        'hasScript(player, "quest.force_sensitive.fs_kickoff")') -and
    $forceQuestLibrary.Contains(
        'detachScript(player, "quest.force_sensitive.fs_kickoff")') -and
    -not $forceQuestLibrary.Contains($incorrectKickoffId)) `
    "Force-sensitive full cleanup no longer uses the canonical kickoff script identifier."

$combatModDone = Get-BracedSurface $texts.combatActions "public int OnSkillModDone"
Assert-Contract ($combatModDone.Contains("PRECU_AIM_MODIFIER.equals(modName)") -and
    $combatModDone.Contains("PRECU_TUMBLE_MELEE_MODIFIER.equals(modName)") -and
    $combatModDone.Contains("PRECU_TUMBLE_RANGED_MODIFIER.equals(modName)") -and
    $combatModDone.Contains("setState(self, STATE_AIMING, false)") -and
    $combatModDone.Contains("setState(self, STATE_TUMBLING, false)") -and
    $combatModDone -notmatch
        '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Combat skill-mod completion no longer owns only PRE-CU Aim/Tumble expiry."

$workingGrant = Get-BracedSurface $texts.workingTriggerTest "public int OnSkillGranted"
Assert-Contract ($workingGrant.Contains("debugSpeakMsg") -and
    $workingGrant.Contains('hasObjVar(self, "override_test")') -and
    $workingGrant -notmatch '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
    "Dormant working skill callback gained mutation authority."
$workingRevoke = Get-BracedSurface $texts.workingTriggerTest "public int OnSkillRevoked"
$workingAboutToGrant = Get-BracedSurface $texts.workingTriggerTest `
    "public int OnSkillAboutToBeGranted"
$workingAboutToRevoke = Get-BracedSurface $texts.workingTriggerTest `
    "public int OnSkillAboutToBeRevoked"
foreach ($workingCallback in @(
    $workingAboutToGrant, $workingGrant, $workingRevoke, $workingAboutToRevoke))
{
    Assert-Contract ($workingCallback.Contains("debugSpeakMsg") -and
        $workingCallback.Contains('hasObjVar(self, "override_test")') -and
        $workingCallback -notmatch
            '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
        "Dormant working lifecycle callback gained mutation authority."
}
$workingReferences = @(& rg -l -i --glob "*.java" --glob "*.tab" --glob "*.tpf" `
    'working\.cmayer\.trigtest|working/cmayer/trigtest' $dsrcRoot)
$workingReferenceExit = $LASTEXITCODE
Assert-Contract ($workingReferenceExit -eq 1 -and $workingReferences.Count -eq 0 -and
    [int]$contract.expected.dormantWorkingProductionAttachments -eq 0) `
    "Dormant working callback acquired a production attachment reference."

$workingSteveModsChanged = Get-BracedSurface $texts.workingSteveDiagnostic `
    "public int OnSkillModsChanged"
Assert-Contract ($workingSteveModsChanged.Contains("debugSpeakMsg") -and
    $workingSteveModsChanged -notmatch
        '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate|applyBuff)\s*\(') `
    "Dormant Steve skill-mod diagnostic gained progression authority."
$workingSteveAttachments = @(& rg -n --glob "*.java" --glob "*.tab" --glob "*.tpf" `
    '\battachScript\s*\([^;]*"working\.steve\.myscript"' $dsrcRoot)
$workingSteveAttachmentExit = $LASTEXITCODE
Assert-Contract ($workingSteveAttachmentExit -eq 1 -and
    $workingSteveAttachments.Count -eq 0 -and
    $texts.workingSteveDiagnostic.Contains(
        'detachScript(self, "working.steve.myscript")') -and
    [int]$contract.expected.dormantWorkingSelfDetachGuards -eq 1) `
    "Dormant Steve diagnostic acquired a production attachment or lost its player guard."

foreach ($dependencyKey in @($contract.requiredReadyContractKeys))
{
    $dependencyKey = [string]$dependencyKey
    $property = @($manifest.contracts.PSObject.Properties |
        Where-Object { $_.Name -ceq $dependencyKey })
    Assert-Contract ($property.Count -eq 1) `
        "Required contract key is missing from the manifest: $dependencyKey"
    $dependencyPath = Join-Path $restorationRoot ([string]$property[0].Value)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyKey"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    $dependencyStatus = [string]$dependency.status
    $dependencyEligible = $dependencyStatus -ceq "ready" -or
        ($Expectation -ceq "Build" -and
            $dependencyStatus -ceq "implemented-build-pending" -and
            @($dependency.requiredBeforeReady).Count -gt 0)
    Assert-Contract $dependencyEligible `
        "Required dependency is not eligible for $Expectation verification: $dependencyKey"
}

$classifiedHandlerCount =
    [int]$contract.classification.basePlayerPrecuAuthority.handlers +
    [int]$contract.classification.retainedPrecuAndContentCallbacks.handlers +
    [int]$contract.classification.forceSensitiveKickoffLifecycle.handlers +
    [int]$contract.classification.retiredBeastMasterCallback.handlers +
    [int]$contract.classification.precuCombatModifierLifecycle.handlers +
    [int]$contract.classification.dormantWorkingDiagnostic.handlers
Assert-Contract ([bool]$contract.expected.allHandlersClassified -and
    $classifiedHandlerCount -eq [int]$contract.inventory.handlers -and
    [int]$contract.inventory.productionHandlers +
        [int]$contract.inventory.dormantWorkingHandlers -eq
        [int]$contract.inventory.handlers -and
    [int]$contract.classification.unclassifiedHandlers -eq 0 -and
    [int]$contract.expected.retiredNgeSkillSideEffectsBeforeRevocation -eq 0 -and
    [int]$contract.expected.retiredBeastMasterCallbackMutations -eq 0 -and
    [int]$contract.expected.retainedFamiliarTrickCallbacks -eq 1 -and
    [int]$contract.expected.npeGuidanceProgressionMutations -eq 0 -and
    [int]$contract.expected.basePlayerRevocationNgeProgressionMutations -eq 0 -and
    [int]$contract.expected.retainedCallbackCombatLevelMutations -eq 0 -and
    [int]$contract.expected.retainedCallbackAutomaticRewards -eq 0 -and
    [int]$contract.expected.precuCombatModifierCompletionCallbacks -eq 1 -and
    [int]$contract.expected.skillTemplateProgressionMutations -eq 0 -and
    [int]$contract.expected.skillModifierNgeProgressionMutations -eq 0 -and
    [int]$contract.expected.gameplaySourceFilesChanged -eq 1 -and
    [bool]$contract.expected.laterZonesQuestsConversationsNpcsJtlAndForceRankPreserved) `
    "Skill lifecycle callback expected PRE-CU boundary is incomplete."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.javaCompile -ceq "passed" -and
        [string]$contract.buildEvidence.fsKickoffClassSha256 -match '^[a-f0-9]{64}$' -and
        [int64]$contract.buildEvidence.fsKickoffClassBytes -gt 0 -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.containerHealth -ceq "healthy" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [int]$contract.runtimeEvidence.javaSources -eq 5717 -and
        [int]$contract.runtimeEvidence.javaClasses -eq 5751 -and
        [int]$contract.runtimeEvidence.liveGameProcessCount -eq 15 -and
        [int]$contract.runtimeEvidence.livePlanetProcessCount -eq 15 -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Skill lifecycle callback closure lacks Ready evidence."
    $container = [string]$contract.runtimeEvidence.container
    $state = (& docker inspect --format `
        "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $container).Trim()
    $processNames = @(& docker exec $container ps -eo comm= | ForEach-Object { $_.Trim() })
    $binaryHash = ((& docker exec $container sha256sum /swg-precu/build/bin/SwgGameServer) -split '\s+')[0]
    $classRoot = "/swg-precu/data/sku.0/sys.server/compiled/game"
    $classPath = "$classRoot/script/quest/force_sensitive/fs_kickoff.class"
    $classHash = ((& docker exec $container sha256sum $classPath) -split '\s+')[0]
    $classBytes = [int64]((& docker exec $container stat -c "%s" $classPath).Trim())
    $bytecode = (& docker exec $container javap -classpath $classRoot -c -p `
        script.quest.force_sensitive.fs_kickoff | Out-String)
    Assert-Contract ($state -ceq "running healthy" -and
        @($processNames | Where-Object { $_ -ceq "SwgGameServer" }).Count -eq 15 -and
        @($processNames | Where-Object { $_ -ceq "PlanetServer" }).Count -eq 15 -and
        $binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256 -and
        $classHash -ceq [string]$contract.buildEvidence.fsKickoffClassSha256 -and
        $classBytes -eq [int64]$contract.buildEvidence.fsKickoffClassBytes -and
        $bytecode.Contains($canonicalKickoffId) -and
        -not $bytecode.Contains($incorrectKickoffId)) `
        "Deployed PRE-CU x64 runtime topology, binary, or kickoff bytecode drifted."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) `
        "Skill lifecycle callback closure is not build-eligible."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Skill lifecycle callback closure references forbidden host staging."

Write-Host "Complete Publish 14.1 Java skill lifecycle callback inventory closure passed."
