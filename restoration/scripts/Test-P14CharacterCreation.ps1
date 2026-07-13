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

$gameServerPath = Join-Path $source "src\engine\server\library\serverGame\src\shared\core\GameServer.cpp"
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

$requiredPaths = @($gameServerPath, $creationPath, $tutorialCppPath, $basePlayerPath, $liveConversionsPath, $sagaQuestPath, $respecPath, $newbieRoot, $newbiePath, $skillPath, $skillTeacherPath)
foreach ($path in $requiredPaths)
{
    if (-not (Test-Path -LiteralPath $path))
    {
        throw "Required materialized path is missing: $path"
    }
}

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

Write-Host "Publish 14.1 character-creation checks:"
foreach ($property in $contract.professionSkills.psobject.Properties)
{
    $profession = [string]$property.Name
    $skill = [string]$property.Value
    Assert-Contract `
        -Condition ($creation.Contains("profession == `"$profession`"") -and $creation.Contains("return `"$skill`"")) `
        -Name "p14.creation.$profession.$skill"
}

$validateAt = $gameServer.IndexOf("isValidStartingProfession(createMessage->getProfession())", [StringComparison]::Ordinal)
$characterAt = $gameServer.IndexOf("TangibleObject *newCharacterObject", [StringComparison]::Ordinal)
$playerObjectAt = $gameServer.IndexOf("createNewObject(ConfigServerGame::getPlayerObjectTemplate()", [StringComparison]::Ordinal)
$setupAt = $gameServer.IndexOf("PlayerCreationManagerServer::setupPlayer", [StringComparison]::Ordinal)
$persistAt = $gameServer.IndexOf("play->persist()", [StringComparison]::Ordinal)
$biographyAt = $gameServer.IndexOf("BiographyManager::setBiography", [StringComparison]::Ordinal)
$tutorialSetupAt = $gameServer.IndexOf("NewbieTutorial::setupCharacterForTutorial(newCharacterObject)", [StringComparison]::Ordinal)
$skipSetupAt = $gameServer.IndexOf("NewbieTutorial::setupCharacterToSkipTutorial(newCharacterObject)", [StringComparison]::Ordinal)
$tutorialSceneSetter = "newCharacterObject->setSceneIdOnThisAndContents(NewbieTutorial::getSceneId());"
$skipSceneSetter = "newCharacterObject->setSceneIdOnThisAndContents(createMessage->getPlanetName());"
$tutorialSceneAt = $gameServer.IndexOf($tutorialSceneSetter, [StringComparison]::Ordinal)
$skipSceneAt = $gameServer.IndexOf($skipSceneSetter, [StringComparison]::Ordinal)
$addCharacterAt = $gameServer.IndexOf("AddCharacterMessage const acm", [StringComparison]::Ordinal)
$characterPersistAt = $gameServer.IndexOf("newCharacterObject->persist()", [StringComparison]::Ordinal)
$sceneSetterCount = [regex]::Matches($gameServer, [regex]::Escape("newCharacterObject->setSceneIdOnThisAndContents(")).Count
$sceneBranchPattern = 'if\s*\(createMessage->getUseNewbieTutorial\(\)\)\s*newCharacterObject->setSceneIdOnThisAndContents\(NewbieTutorial::getSceneId\(\)\);\s*else\s*newCharacterObject->setSceneIdOnThisAndContents\(createMessage->getPlanetName\(\)\);'
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

Assert-Contract -Condition ([regex]::IsMatch($gameServer, $sceneBranchPattern)) -Name "p14.creation.scene-routed-by-tutorial-choice"
Assert-Contract -Condition ($tutorialSceneAt -gt $tutorialSetupAt -and $tutorialSceneAt -gt $biographyAt -and $tutorialSceneAt -lt $addCharacterAt) -Name "p14.creation.tutorial-scene-before-database-handoff"
Assert-Contract -Condition ($skipSceneAt -gt $skipSetupAt -and $skipSceneAt -gt $tutorialSceneAt -and $skipSceneAt -lt $addCharacterAt) -Name "p14.creation.skip-scene-before-database-handoff"
Assert-Contract -Condition ($addCharacterAt -gt $skipSceneAt -and $characterPersistAt -gt $addCharacterAt) -Name "p14.creation.scene-before-character-persist"
Assert-Contract -Condition ($sceneSetterCount -eq 2) -Name "p14.creation.no-unconditional-scene-overwrite"

Assert-Contract -Condition ($tutorialCpp.Contains([string]$contract.tutorial.buildingTemplate)) -Name "p14.tutorial.newbie-hall-template"
Assert-Contract -Condition ($tutorialCpp.Contains("s_sceneId(`"$([string]$contract.tutorial.sceneId)`")")) -Name "p14.tutorial.scene-id"
Assert-Contract -Condition ($tutorialCpp.Contains("s_startCellName(`"$([string]$contract.tutorial.startCell)`")")) -Name "p14.tutorial.room-one-start"
Assert-Contract -Condition ($tutorialCpp.Contains([string]$contract.tutorial.startObjVar)) -Name "p14.tutorial.precu-state"
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
Assert-Contract -Condition ($sagaInitializeHandler.Contains($initializeRequiredMarker) -and -not $sagaInitializeHandler.Contains($chroniclesGrantHandler)) -Name "p14.login.chronicles-on-initialize-self-retires"
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
