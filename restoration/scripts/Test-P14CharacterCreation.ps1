[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$contractPath = Join-Path $restorationRoot "contracts\p14-character-creation.json"
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$connectionServerPath = Join-Path $source ([string]$contract.ctsTransferProfessionSelection.connectionServerSource)
$pseudoClientPath = Join-Path $source ([string]$contract.ctsTransferProfessionSelection.pseudoClientSource)
$centralServerPath = Join-Path $source ([string]$contract.ctsTransferProfessionSelection.centralServerSource)
$gameServerPath = Join-Path $source ([string]$contract.ctsTransferProfessionSelection.gameServerSource)
$creationPath = Join-Path $source "src\engine\server\library\serverGame\src\shared\core\PlayerCreationManagerServer.cpp"
$tutorialCppPath = Join-Path $source "src\engine\server\library\serverGame\src\shared\core\NewbieTutorial.cpp"
$basePlayerPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\player\base\base_player.java"
$liveConversionsPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\player\live_conversions.java"
$sagaQuestPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\player\player_saga_quest.java"
$respecPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\systems\respec\click_combat_respec.java"
$newbieRoot = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\theme_park\newbie_tutorial"
$newbiePath = Join-Path $newbieRoot "newbie.java"
$skillPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\library\skill.java"
$skillTeacherPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\npc\skillteacher\skillteacher.java"

$requiredPaths = @($connectionServerPath, $pseudoClientPath, $centralServerPath, $gameServerPath, $creationPath, $tutorialCppPath, $basePlayerPath, $liveConversionsPath, $sagaQuestPath, $respecPath, $newbieRoot, $newbiePath, $skillPath, $skillTeacherPath)
foreach ($path in $requiredPaths)
{
    if (-not (Test-Path -LiteralPath $path))
    {
        throw "Required materialized path is missing: $path"
    }
}

$connectionServer = Get-Content -LiteralPath $connectionServerPath -Raw
$pseudoClient = Get-Content -LiteralPath $pseudoClientPath -Raw
$centralServer = Get-Content -LiteralPath $centralServerPath -Raw
$gameServer = Get-Content -LiteralPath $gameServerPath -Raw
$creation = Get-Content -LiteralPath $creationPath -Raw
$tutorialCpp = Get-Content -LiteralPath $tutorialCppPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$liveConversions = Get-Content -LiteralPath $liveConversionsPath -Raw
$sagaQuest = Get-Content -LiteralPath $sagaQuestPath -Raw
$newbie = Get-Content -LiteralPath $newbiePath -Raw
$skillScript = Get-Content -LiteralPath $skillPath -Raw
$skillTeacher = Get-Content -LiteralPath $skillTeacherPath -Raw
$dsrcText = @(
    $basePlayer
    Get-Content -LiteralPath $respecPath -Raw
    Get-ChildItem -LiteralPath $newbieRoot -File -Filter "*.java" |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
) -join "`n"

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

function Test-GuardedScriptDetach
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$ScriptName
    )

    $guard = "if (hasScript(self, `"$ScriptName`"))"
    $detach = "detachScript(self, `"$ScriptName`");"
    $guardAt = $Text.IndexOf($guard, [StringComparison]::Ordinal)
    $detachAt = $Text.IndexOf($detach, [StringComparison]::Ordinal)
    return $guardAt -ge 0 -and $detachAt -gt $guardAt -and ($detachAt - $guardAt) -lt 256
}

function Get-ScriptHandlerText
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$HandlerName
    )

    $signature = "public int $HandlerName("
    $start = $Text.IndexOf($signature, [StringComparison]::Ordinal)
    if ($start -lt 0)
    {
        return ""
    }

    $next = $Text.IndexOf("public int ", $start + $signature.Length, [StringComparison]::Ordinal)
    if ($next -lt 0)
    {
        return $Text.Substring($start)
    }

    return $Text.Substring($start, $next - $start)
}

function Get-SourceSlice
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker
    )

    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0)
    {
        return ""
    }

    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0)
    {
        return $Text.Substring($start)
    }

    return $Text.Substring($start, $end - $start)
}

Write-Host "Publish 14.1 character-creation checks:"
foreach ($property in $contract.professionSkills.psobject.Properties)
{
    $profession = [string]$property.Name
    $skill = [string]$property.Value
    Assert-Contract `
        -Condition ($creation.Contains("profession == `"$profession`"") -and $creation.Contains("return `"$skill`"")) `
        -Name "p14.creation.$profession.$skill"
}

$professionTable = Get-SourceSlice `
    -Text (Get-SourceSlice -Text $connectionServer -StartMarker 'case constcrc("RequestTransferData") :' -EndMarker 'case constcrc("ApplyTransferData") :') `
    -StartMarker "static PrecuStartingProfession const s_precuStartingProfessions[]" `
    -EndMarker "std::string professionName;"
$professionSelection = Get-SourceSlice `
    -Text $connectionServer `
    -StartMarker 'case constcrc("RequestTransferData") :' `
    -EndMarker 'case constcrc("ApplyTransferData") :'
$professionSearch = Get-SourceSlice `
    -Text $professionSelection `
    -StartMarker "std::string professionName;" `
    -EndMarker "if (professionName.empty())"
$actualPriority = @(
    [regex]::Matches($professionTable, '\{\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\}') |
        ForEach-Object { "$($_.Groups[1].Value)|$($_.Groups[2].Value)" }
)
$expectedPriority = @(
    $contract.ctsTransferProfessionSelection.priority |
        ForEach-Object { "$([string]$_.noviceSkill)|$([string]$_.profession)" }
)
Assert-Contract `
    -Condition (
        [int]$contract.ctsTransferProfessionSelection.exactPriorityEntries -eq 6 -and
        $actualPriority.Count -eq 6 -and
        (($actualPriority -join "`n") -ceq ($expectedPriority -join "`n")) -and
        @($contract.professionSkills.psobject.Properties).Count -eq 6 -and
        @($contract.ctsTransferProfessionSelection.priority | Where-Object {
            [string]$contract.professionSkills.($_.profession) -cne [string]$_.noviceSkill
        }).Count -eq 0
    ) `
    -Name "p14.creation.cts-profession.fixed-six-priority"

$ownedSkillAt = $professionSearch.IndexOf('CreatureObject::SkillList const & skills = character->getSkillList();', [StringComparison]::Ordinal)
$directCompareAt = $professionSearch.IndexOf('(*skill)->getSkillName() == s_precuStartingProfessions[professionIndex].noviceSkill', [StringComparison]::Ordinal)
$assignAt = $professionSearch.IndexOf('professionName = s_precuStartingProfessions[professionIndex].profession;', [StringComparison]::Ordinal)
$breakAt = if ($assignAt -ge 0) { $professionSearch.IndexOf('break;', $assignAt, [StringComparison]::Ordinal) } else { -1 }
Assert-Contract `
    -Condition (
        [bool]$contract.ctsTransferProfessionSelection.ownedNoviceComparisonIsDirect -and
        $ownedSkillAt -ge 0 -and
        $directCompareAt -gt $ownedSkillAt -and
        $assignAt -gt $directCompareAt -and
        $breakAt -gt $assignAt -and
        $professionSearch.Contains('professionIndex < sizeof(s_precuStartingProfessions) / sizeof(s_precuStartingProfessions[0]) && professionName.empty()') -and
        [regex]::Matches($professionSearch, [regex]::Escape('break;')).Count -eq 1 -and
        [regex]::Matches($professionSelection, 'professionName\s*=').Count -eq 1 -and
        -not [regex]::IsMatch($professionSelection, 'professionName\s*=\s*"')
    ) `
    -Name "p14.creation.cts-profession.direct-owned-novice-first-match"

foreach ($marker in @($contract.ctsTransferProfessionSelection.forbiddenConnectionServerMarkers))
{
    Assert-Contract `
        -Condition (-not $professionSelection.Contains([string]$marker)) `
        -Name "p14.creation.cts-profession.no-fallback.$marker"
}
Assert-Contract `
    -Condition (-not $connectionServer.Contains('#include "sharedGame/PlayerCreationManager.h"')) `
    -Name "p14.creation.cts-profession.no-legacy-profession-manager-include"

$missingProfessionAt = $professionSelection.IndexOf('if (professionName.empty())', [StringComparison]::Ordinal)
$failureLogAt = $professionSelection.IndexOf('owns none of the six direct PRE-CU novice profession skills', [StringComparison]::Ordinal)
$playerBranchAt = $professionSelection.IndexOf('else if (playerObject)', [StringComparison]::Ordinal)
$uploadAt = $professionSelection.IndexOf('character->uploadCharacterData(', [StringComparison]::Ordinal)
$setProfessionAt = $professionSelection.IndexOf('replyData.setProfession(professionName);', [StringComparison]::Ordinal)
$succeededFalseAt = $professionSelection.IndexOf('bool succeeded = false;', [StringComparison]::Ordinal)
$succeededTrueAt = $professionSelection.IndexOf('succeeded = true;', [StringComparison]::Ordinal)
$failureTailAt = $professionSelection.IndexOf('if(! succeeded)', [StringComparison]::Ordinal)
Assert-Contract `
    -Condition (
        [bool]$contract.ctsTransferProfessionSelection.missingOwnedNoviceFailsBeforeUpload -and
        $missingProfessionAt -ge 0 -and
        $failureLogAt -gt $missingProfessionAt -and
        $playerBranchAt -gt $failureLogAt -and
        $uploadAt -gt $playerBranchAt -and
        $setProfessionAt -gt $uploadAt -and
        $succeededFalseAt -ge 0 -and
        $succeededFalseAt -lt $missingProfessionAt -and
        $succeededTrueAt -gt $setProfessionAt -and
        $failureTailAt -gt $succeededTrueAt -and
        -not $professionSelection.Substring($missingProfessionAt, $playerBranchAt - $missingProfessionAt).Contains('uploadCharacterData(') -and
        [regex]::Matches($professionSelection, [regex]::Escape('uploadCharacterData(')).Count -eq 1 -and
        $professionSelection.Contains('if(! succeeded)') -and
        $professionSelection.Contains('GenericValueTypeMessage<TransferCharacterData> reply("ReplyTransferDataFail"')
    ) `
    -Name "p14.creation.cts-profession.missing-skill-fails-before-upload"

$pseudoCreate = Get-SourceSlice `
    -Text $pseudoClient `
    -StartMarker 'case constcrc("TransferLoginCharacterToDestinationServer") :' `
    -EndMarker 'case constcrc("CtsSrcCharWrongPlanet") :'
$centralCreate = Get-SourceSlice `
    -Text $centralServer `
    -StartMarker "void CharacterCreationTracker::handleCreateNewCharacter" `
    -EndMarker "void CharacterCreationTracker::handleDatabaseCreateCharacterSuccess"
$gameCreate = Get-SourceSlice `
    -Text $gameServer `
    -StartMarker "void GameServer::handleCharacterCreateNameVerification" `
    -EndMarker "void GameServer::handleVerifyAndLockNameVerification"
$gameProfessionGateAt = $gameCreate.IndexOf('isValidStartingProfession(createMessage->getProfession())', [StringComparison]::Ordinal)
$gameAllocationAt = $gameCreate.IndexOf('TangibleObject *newCharacterObject', [StringComparison]::Ordinal)
$gameSetupProfessionAt = $gameCreate.IndexOf('PlayerCreationManagerServer::setupPlayer(*creature, createMessage->getProfession()', [StringComparison]::Ordinal)
Assert-Contract `
    -Condition (
        [bool]$contract.ctsTransferProfessionSelection.professionForwardedUnchanged -and
        $setProfessionAt -ge 0 -and
        [regex]::Matches($pseudoCreate, [regex]::Escape('m_transferCharacterData.getProfession()')).Count -eq 1 -and
        -not $pseudoCreate.Contains('setProfession(') -and
        -not $pseudoCreate.Contains('professionName') -and
        [regex]::IsMatch($pseudoCreate, 'm_transferCharacterData\.getHairAppearanceData\(\),\s*m_transferCharacterData\.getProfession\(\),\s*false,', [Text.RegularExpressions.RegexOptions]::Singleline) -and
        [regex]::Matches($centralCreate, [regex]::Escape('msg.getProfession()')).Count -eq 1 -and
        [regex]::IsMatch($centralCreate, 'msg\.getHairAppearanceData\(\),\s*msg\.getProfession\(\),\s*msg\.getBiography\(\)', [Text.RegularExpressions.RegexOptions]::Singleline) -and
        [bool]$contract.ctsTransferProfessionSelection.strictGameServerAdmissionAndSetup -and
        $gameProfessionGateAt -ge 0 -and
        $gameProfessionGateAt -lt $gameAllocationAt -and
        $gameSetupProfessionAt -gt $gameAllocationAt
    ) `
    -Name "p14.creation.cts-profession.forwarded-unchanged-through-strict-game-gate"

$strictCreationMap = Get-SourceSlice `
    -Text $creation `
    -StartMarker "char const * getStartingSkill" `
    -EndMarker "using namespace PlayerCreationManagerServerNamespace;"
$actualCreationMap = @(
    [regex]::Matches($strictCreationMap, 'if\s*\(profession\s*==\s*"([^"]+)"\)\s*return\s*"([^"]+)";', [Text.RegularExpressions.RegexOptions]::Singleline) |
        ForEach-Object { "$($_.Groups[2].Value)|$($_.Groups[1].Value)" }
)
$creationAdmission = Get-SourceSlice `
    -Text $creation `
    -StartMarker "bool PlayerCreationManagerServer::isValidStartingProfession" `
    -EndMarker "void PlayerCreationManagerServer::remove"
Assert-Contract `
    -Condition (
        $actualCreationMap.Count -eq 6 -and
        (($actualCreationMap -join "`n") -ceq ($expectedPriority -join "`n")) -and
        $strictCreationMap.Contains('return 0;') -and
        $creationAdmission.Contains('return getStartingSkill(profession) != 0;') -and
        $creationAdmission.Contains('char const * const expectedStartingSkill = getStartingSkill(profession);') -and
        $creationAdmission.Contains('if (!expectedStartingSkill)') -and
        $creationAdmission.Contains('skills->size() != 1') -and
        $creationAdmission.Contains('skills->front() != expectedStartingSkill')
    ) `
    -Name "p14.creation.cts-profession.strict-six-map-and-setup-revalidation"

$validateAt = $gameServer.IndexOf("isValidStartingProfession(createMessage->getProfession())", [StringComparison]::Ordinal)
$characterAt = $gameServer.IndexOf("TangibleObject *newCharacterObject", [StringComparison]::Ordinal)
$playerObjectAt = $gameServer.IndexOf("createNewObject(ConfigServerGame::getPlayerObjectTemplate()", [StringComparison]::Ordinal)
$setupAt = $gameServer.IndexOf("PlayerCreationManagerServer::setupPlayer", [StringComparison]::Ordinal)
$persistAt = $gameServer.IndexOf("play->persist()", [StringComparison]::Ordinal)
$biographyAt = $gameServer.IndexOf("BiographyManager::setBiography", [StringComparison]::Ordinal)
$tutorialSetupAt = $gameServer.IndexOf("NewbieTutorial::setupCharacterForTutorial(newCharacterObject)", [StringComparison]::Ordinal)
$skipSetupAt = $gameServer.IndexOf("NewbieTutorial::setupCharacterToSkipTutorial(newCharacterObject)", [StringComparison]::Ordinal)
$tutorialSceneSetter = "newCharacterObject->setSceneIdOnThisAndContents(NewbieTutorial::getSceneId());"
$tutorialSceneAt = $gameServer.IndexOf($tutorialSceneSetter, [StringComparison]::Ordinal)
$skippedLocationAt = $gameServer.IndexOf("tr.setPosition_p(NewbieTutorial::getSkippedTutorialLocation());", [StringComparison]::Ordinal)
$creationCoordinatesAt = $gameServer.IndexOf("tr.setPosition_p(createMessage->getCoordinates());", [StringComparison]::Ordinal)
$directPlanetSceneAt = $gameServer.IndexOf("newCharacterObject->setSceneIdOnThisAndContents(createMessage->getPlanetName());", [StringComparison]::Ordinal)
$addCharacterAt = $gameServer.IndexOf("AddCharacterMessage const acm", [StringComparison]::Ordinal)
$characterPersistAt = $gameServer.IndexOf("newCharacterObject->persist()", [StringComparison]::Ordinal)
$sceneSetterCount = [regex]::Matches($gameServer, [regex]::Escape("newCharacterObject->setSceneIdOnThisAndContents(")).Count
$tutorialChoicePattern = 'if\s*\(createMessage->getUseNewbieTutorial\(\)\)\s*NewbieTutorial::setupCharacterForTutorial\(newCharacterObject\);\s*else\s*NewbieTutorial::setupCharacterToSkipTutorial\(newCharacterObject\);'
$clearValueExpression = [string]$contract.roadmap.clearValueExpression
$skillTemplateClear = "play->setSkillTemplate($clearValueExpression, true);"
$workingSkillClear = "play->setWorkingSkill($clearValueExpression, true);"
$skillTemplateClearAt = $gameServer.IndexOf($skillTemplateClear, [StringComparison]::Ordinal)
$workingSkillClearAt = $gameServer.IndexOf($workingSkillClear, [StringComparison]::Ordinal)
$skipConditionalAt = $creation.IndexOf("if (!useNewbieTutorial)", [StringComparison]::Ordinal)
$grantAt = $creation.IndexOf("obj.grantSkill(*startingSkill)", [StringComparison]::Ordinal)
$skipCleanupAt = $creation.IndexOf("removeObjVarItem(`"newbie.hasSkill`")", [StringComparison]::Ordinal)

Assert-Contract -Condition ($validateAt -ge 0 -and $validateAt -lt $characterAt) -Name "p14.creation.validate-before-allocation"
Assert-Contract -Condition ($playerObjectAt -ge 0 -and $playerObjectAt -lt $setupAt -and $setupAt -lt $persistAt) -Name "p14.creation.player-before-skill-before-persist"
Assert-Contract -Condition ($biographyAt -gt $setupAt) -Name "p14.creation.biography-after-setup"
Assert-Contract -Condition ($skillTemplateClearAt -gt $playerObjectAt -and $workingSkillClearAt -gt $skillTemplateClearAt -and $workingSkillClearAt -lt $setupAt) -Name "p14.creation.roadmap-fields-explicitly-cleared"
foreach ($accessor in @($contract.roadmap.forbiddenClientAccessors))
{
    Assert-Contract -Condition (-not $gameServer.Contains([string]$accessor)) -Name "p14.creation.roadmap-client-accessor-absent.$accessor"
}
Assert-Contract -Condition ($creation.Contains("skills->size() != 1") -and $creation.Contains("skills->front() != expectedStartingSkill")) -Name "p14.creation.exactly-one-selected-novice"
Assert-Contract -Condition ($creation.Contains("obj.grantSkill(*startingSkill)") -and $creation.Contains("obj.hasSkill(*startingSkill)")) -Name "p14.creation.verified-authoritative-grant"
Assert-Contract -Condition ($skipConditionalAt -ge 0 -and $skipConditionalAt -lt $grantAt -and $grantAt -lt $skipCleanupAt) -Name "p14.creation.skip-grant-clears-handoff"
Assert-Contract -Condition (-not $gameServer.Contains("permanentlyDestroy(DeleteReasons::SetupFailed)")) -Name "p14.creation.transient-failure-teardown"

Assert-Contract -Condition ([regex]::IsMatch($gameServer, $tutorialChoicePattern)) -Name "p14.creation.onboarding-choice-recorded"
Assert-Contract -Condition ($skippedLocationAt -gt $characterAt -and $skippedLocationAt -lt $skipSetupAt -and $creationCoordinatesAt -lt 0) -Name "p14.creation.skip-path-uses-shared-hall-location"
Assert-Contract -Condition ($tutorialSceneAt -gt $tutorialSetupAt -and $tutorialSceneAt -gt $skipSetupAt -and $tutorialSceneAt -gt $biographyAt -and $tutorialSceneAt -lt $addCharacterAt) -Name "p14.creation.both-paths-use-tutorial-scene-before-database-handoff"
Assert-Contract -Condition ($directPlanetSceneAt -lt 0) -Name "p14.creation.no-direct-world-scene-from-creation-message"
Assert-Contract -Condition ($addCharacterAt -gt $tutorialSceneAt -and $characterPersistAt -gt $addCharacterAt) -Name "p14.creation.scene-before-character-persist"
Assert-Contract -Condition ($sceneSetterCount -eq 1) -Name "p14.creation.single-authoritative-scene-write"

Assert-Contract -Condition ($tutorialCpp.Contains([string]$contract.tutorial.buildingTemplate)) -Name "p14.tutorial.newbie-hall-template"
Assert-Contract -Condition ($tutorialCpp.Contains([string]$contract.tutorial.skippedBuildingTemplate)) -Name "p14.tutorial.skipped-newbie-hall-template"
Assert-Contract -Condition ($tutorialCpp.Contains("s_sceneId(`"$([string]$contract.tutorial.sceneId)`")")) -Name "p14.tutorial.scene-id"
Assert-Contract -Condition ($tutorialCpp.Contains("s_startCellName(`"$([string]$contract.tutorial.startCell)`")")) -Name "p14.tutorial.room-one-start"
Assert-Contract -Condition ($tutorialCpp.Contains([string]$contract.tutorial.startObjVar)) -Name "p14.tutorial.precu-state"
Assert-Contract -Condition ($tutorialCpp.Contains([string]$contract.tutorial.skipStartObjVar)) -Name "p14.tutorial.skipped-precu-state"
Assert-Contract -Condition (-not $tutorialCpp.Contains("npe_hangar_1.iff") -and -not $tutorialCpp.Contains("npe.phase_number")) -Name "p14.tutorial.no-nge-hangar-state"
Assert-Contract -Condition ($skillScript.Contains("hasObjVar(target, `"newbie.hasSkill`")") -and $skillScript.Contains("!hasObjVar(target, `"newbie.trained`")")) -Name "p14.tutorial.selected-trainer-handoff"
Assert-Contract -Condition ($skillTeacher.Contains("setObjVar(speaker, `"newbie.trained`", true)")) -Name "p14.tutorial.trainer-completion-state"
Assert-Contract -Condition ($newbie.Contains("if (!hasSkill(self, skillName))") -and $newbie.Contains("grantSkill(self, skillName)")) -Name "p14.tutorial.relog-exit-fallback"

foreach ($marker in @($contract.forbiddenDsrcMarkers))
{
    Assert-Contract -Condition (-not $dsrcText.Contains([string]$marker)) -Name "p14.login.absent.$marker"
}

foreach ($marker in @($contract.ngeCreationResidue.forbiddenBasePlayerMarkers))
{
    Assert-Contract -Condition (-not $basePlayer.Contains([string]$marker)) -Name "p14.login.base-player-absent.$marker"
}

foreach ($scriptName in @($contract.ngeCreationResidue.retiredScripts))
{
    Assert-Contract -Condition (Test-GuardedScriptDetach -Text $basePlayer -ScriptName ([string]$scriptName)) -Name "p14.login.base-player-retires.$scriptName"
    Assert-Contract -Condition (-not $basePlayer.Contains("attachScript(self, `"$([string]$scriptName)`")")) -Name "p14.login.base-player-does-not-attach.$scriptName"
}

$chroniclesScript = [string]$contract.ngeCreationResidue.chroniclesScript
$chroniclesGrantHandler = [string]$contract.ngeCreationResidue.chroniclesGrantHandler
$sagaAttachHandler = Get-ScriptHandlerText -Text $sagaQuest -HandlerName "OnAttach"
$sagaInitializeHandler = Get-ScriptHandlerText -Text $sagaQuest -HandlerName "OnInitialize"
$sagaRetirementHelper = Get-SourceSlice -Text $sagaQuest -StartMarker "public void retireChroniclesPlayerCallback" -EndMarker "public int OnAttach"
$liveAttachHandler = Get-ScriptHandlerText -Text $liveConversions -HandlerName "OnAttach"
$liveInitializeHandler = Get-ScriptHandlerText -Text $liveConversions -HandlerName "OnInitialize"
$attachRequiredMarker = [string]$contract.ngeCreationResidue.chroniclesLifecycle.onAttachRequiredMarker
$initializeRequiredMarker = [string]$contract.ngeCreationResidue.chroniclesLifecycle.onInitializeRequiredMarker
$queuedChroniclesGrant = "messageTo(self, `"$chroniclesGrantHandler`""
Assert-Contract -Condition (-not $liveConversions.Contains("attachScript(player, `"$chroniclesScript`")")) -Name "p14.login.live-conversions-does-not-attach-chronicles"
Assert-Contract -Condition ($sagaAttachHandler.Contains($attachRequiredMarker)) -Name "p14.login.chronicles-on-attach-inert-return"
foreach ($marker in @($contract.ngeCreationResidue.chroniclesLifecycle.onAttachForbiddenMarkers))
{
    Assert-Contract -Condition (-not $sagaAttachHandler.Contains([string]$marker)) -Name "p14.login.chronicles-on-attach-absent.$marker"
}
$sagaRetirementHelperReady = $true
foreach ($marker in @($contract.ngeCreationResidue.chroniclesLifecycle.retirementHelperRequiredMarkers))
{
    if (-not $sagaRetirementHelper.Contains([string]$marker))
    {
        $sagaRetirementHelperReady = $false
    }
}
Assert-Contract -Condition ($sagaInitializeHandler.Contains($initializeRequiredMarker) -and $sagaRetirementHelperReady -and -not $sagaInitializeHandler.Contains($chroniclesGrantHandler)) -Name "p14.login.chronicles-on-initialize-self-retires"
Assert-Contract -Condition (-not $sagaQuest.Contains($queuedChroniclesGrant)) -Name "p14.login.no-queued-$([string]$contract.ngeCreationResidue.chroniclesStartingSkill)-grant"

$liveAttachRequiredMarker = [string]$contract.ngeCreationResidue.liveConversionsLifecycle.onAttachRequiredMarker
Assert-Contract -Condition ($liveAttachHandler.Contains($liveAttachRequiredMarker)) -Name "p14.login.live-conversions-on-attach-inert-return"
foreach ($marker in @($contract.ngeCreationResidue.liveConversionsLifecycle.onAttachForbiddenMarkers))
{
    Assert-Contract -Condition (-not $liveAttachHandler.Contains([string]$marker)) -Name "p14.login.live-conversions-on-attach-absent.$marker"
}
foreach ($marker in @($contract.ngeCreationResidue.liveConversionsLifecycle.onInitializeRequiredMarkers))
{
    Assert-Contract -Condition ($liveInitializeHandler.Contains([string]$marker)) -Name "p14.login.live-conversions-on-initialize-required.$marker"
}
foreach ($marker in @($contract.ngeCreationResidue.liveConversionsLifecycle.onInitializeForbiddenMarkers))
{
    Assert-Contract -Condition (-not $liveInitializeHandler.Contains([string]$marker)) -Name "p14.login.live-conversions-on-initialize-absent.$marker"
}

Assert-Contract -Condition ((Get-Content -LiteralPath $respecPath -Raw).Contains("detachScript(self, `"systems.respec.click_combat_respec`")")) -Name "p14.login.retired-respec-attach-point"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 character-creation contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 character-creation contract passed."
