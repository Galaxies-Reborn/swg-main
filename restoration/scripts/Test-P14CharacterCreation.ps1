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
$respecPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\systems\respec\click_combat_respec.java"
$newbieRoot = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\theme_park\newbie_tutorial"
$newbiePath = Join-Path $newbieRoot "newbie.java"
$skillPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\library\skill.java"
$skillTeacherPath = Join-Path $source "dsrc\sku.0\sys.server\compiled\game\script\npc\skillteacher\skillteacher.java"

$requiredPaths = @($gameServerPath, $creationPath, $tutorialCppPath, $basePlayerPath, $respecPath, $newbieRoot, $newbiePath, $skillPath, $skillTeacherPath)
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
$newbie = Get-Content -LiteralPath $newbiePath -Raw
$skillScript = Get-Content -LiteralPath $skillPath -Raw
$skillTeacher = Get-Content -LiteralPath $skillTeacherPath -Raw
$dsrcText = @(
    Get-Content -LiteralPath $basePlayerPath -Raw
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
$skipConditionalAt = $creation.IndexOf("if (!useNewbieTutorial)", [StringComparison]::Ordinal)
$grantAt = $creation.IndexOf("obj.grantSkill(*startingSkill)", [StringComparison]::Ordinal)
$skipCleanupAt = $creation.IndexOf("removeObjVarItem(`"newbie.hasSkill`")", [StringComparison]::Ordinal)

Assert-Contract -Condition ($validateAt -ge 0 -and $validateAt -lt $characterAt) -Name "p14.creation.validate-before-allocation"
Assert-Contract -Condition ($playerObjectAt -ge 0 -and $playerObjectAt -lt $setupAt -and $setupAt -lt $persistAt) -Name "p14.creation.player-before-skill-before-persist"
Assert-Contract -Condition ($biographyAt -gt $setupAt) -Name "p14.creation.biography-after-setup"
Assert-Contract -Condition ($creation.Contains("skills->size() != 1") -and $creation.Contains("skills->front() != expectedStartingSkill")) -Name "p14.creation.exactly-one-selected-novice"
Assert-Contract -Condition ($creation.Contains("obj.grantSkill(*startingSkill)") -and $creation.Contains("obj.hasSkill(*startingSkill)")) -Name "p14.creation.verified-authoritative-grant"
Assert-Contract -Condition ($skipConditionalAt -ge 0 -and $skipConditionalAt -lt $grantAt -and $grantAt -lt $skipCleanupAt) -Name "p14.creation.skip-grant-clears-handoff"
Assert-Contract -Condition (-not $gameServer.Contains("permanentlyDestroy(DeleteReasons::SetupFailed)")) -Name "p14.creation.transient-failure-teardown"

Assert-Contract -Condition ($tutorialCpp.Contains([string]$contract.tutorial.buildingTemplate)) -Name "p14.tutorial.newbie-hall-template"
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

Assert-Contract -Condition ((Get-Content -LiteralPath $respecPath -Raw).Contains("detachScript(self, `"systems.respec.click_combat_respec`")")) -Name "p14.login.retired-respec-attach-point"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 character-creation contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 character-creation contract passed."
