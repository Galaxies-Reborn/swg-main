[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14StatMigration)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$text = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized stat-migration source is missing: $path"
    }
    $text[[string]$property.Name] = Get-Content -LiteralPath $path -Raw
}

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

function Read-TabTable
{
    param([Parameter(Mandatory = $true)][string]$Value)

    $lines = @($Value -split "`r?`n" | Where-Object { $_.Length -gt 0 })
    if ($lines.Count -lt 2) { throw "Compiled table has no header/type rows." }
    $headers = @($lines[0] -split "`t")
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines[2..($lines.Count - 1)])
    {
        $values = @($line -split "`t")
        $row = [ordered]@{}
        for ($index = 0; $index -lt $headers.Count; $index++)
        {
            $row[$headers[$index]] = if ($index -lt $values.Count) { $values[$index] } else { "" }
        }
        $rows.Add([pscustomobject]$row)
    }
    return $rows.ToArray()
}

Write-Host "Publish 14.1 stat-migration checks:"

$expectedOrder = @("health", "strength", "constitution", "action", "quickness", "stamina", "mind", "focus", "willpower")
$wireOrder = @($contract.wireOrder | ForEach-Object { [string]$_ })
Assert-Contract `
    -Condition ([string]$contract.status -ceq "ready" -and (($wireOrder -join ",") -ceq ($expectedOrder -join ","))) `
    -Name "p14.stat-migration.contract.ready-and-exact-wire-order"

$limits = @(Read-TabTable -Value $text.attributeLimits)
$racial = @(Read-TabTable -Value $text.racialMods)
$professions = @(Read-TabTable -Value $text.professionMods)

$expectedLimitHeader = @("male_template", "female_template")
foreach ($attribute in $expectedOrder) { $expectedLimitHeader += @("min_$attribute", "max_$attribute") }
$expectedLimitHeader += "total"
$actualLimitHeader = @(($text.attributeLimits -split "`r?`n")[0] -split "`t")
Assert-Contract `
    -Condition ($limits.Count -eq 10 -and (($actualLimitHeader -join ",") -ceq ($expectedLimitHeader -join ","))) `
    -Name "p14.stat-migration.tables.attribute-limits-shape"

$totalsReady = $true
foreach ($property in $contract.racialTotals.psobject.Properties)
{
    $row = @($limits | Where-Object { $_.male_template -ceq [string]$property.Name })
    if ($row.Count -ne 1 -or [int]$row[0].total -ne [int]$property.Value) { $totalsReady = $false }
}
Assert-Contract -Condition $totalsReady -Name "p14.stat-migration.tables.authentic-racial-totals"

$human = @($limits | Where-Object { $_.male_template -ceq "human_male" })[0]
$trandoshan = @($limits | Where-Object { $_.male_template -ceq "trandoshan_male" })[0]
$wookiee = @($limits | Where-Object { $_.male_template -ceq "wookiee_male" })[0]
Assert-Contract `
    -Condition ([int]$human.min_health -eq 400 -and [int]$human.max_willpower -eq 1100 -and [int]$trandoshan.min_constitution -eq 700 -and [int]$wookiee.max_health -eq 1350) `
    -Name "p14.stat-migration.tables.authentic-limit-canaries"

$racialHeader = @(($text.racialMods -split "`r?`n")[0] -split "`t")
$expectedRacialHeader = @("male_template", "female_template") + $expectedOrder
$racialHuman = @($racial | Where-Object { $_.male_template -ceq "human_male" })[0]
$racialWookiee = @($racial | Where-Object { $_.male_template -ceq "wookiee_male" })[0]
Assert-Contract `
    -Condition ($racial.Count -eq 10 -and (($racialHeader -join ",") -ceq ($expectedRacialHeader -join ",")) -and [int]$racialHuman.health -eq 100 -and [int]$racialWookiee.strength -eq 350 -and [int]$racialWookiee.focus -eq 150) `
    -Name "p14.stat-migration.tables.authentic-racial-modifiers"

$professionHeader = @(($text.professionMods -split "`r?`n")[0] -split "`t")
$expectedProfessionHeader = @("profession") + $expectedOrder
$artisan = @($professions | Where-Object { $_.profession -ceq "crafting_artisan" })[0]
$medic = @($professions | Where-Object { $_.profession -ceq "science_medic" })[0]
Assert-Contract `
    -Condition ($professions.Count -eq 7 -and (($professionHeader -join ",") -ceq ($expectedProfessionHeader -join ",")) -and [int]$artisan.action -eq 800 -and [int]$artisan.mind -eq 900 -and [int]$medic.mind -eq 1000 -and [int]$medic.focus -eq 500) `
    -Name "p14.stat-migration.tables.authentic-profession-allocations"

$commandsReady = $true
foreach ($command in @($contract.commands))
{
    if (-not $text.commandCpp.Contains("CommandTable::addCppFunction(`"$command`"")) { $commandsReady = $false }
}
Assert-Contract -Condition $commandsReady -Name "p14.stat-migration.commands.four-retained-entry-points"

$sessionReady = `
    $text.commandCpp.Contains("StatMigrationSessionMap s_statMigrationSessions") -and `
    $text.commandCpp.Contains("PlayerCreationManager::getRacialMinMaxes") -and `
    $text.commandCpp.Contains("PlayerCreationManager::getRacialTotal") -and `
    $text.commandCpp.Contains("creature.getUnmodifiedMaxAttribute(attribute)") -and `
    $text.commandCpp.Contains("session.pointsLeft = total - assigned")
Assert-Contract -Condition $sessionReady -Name "p14.stat-migration.session.server-owned-bounds-and-normalization"

$validationReady = `
    $text.commandCpp.Contains("targets.size()) != Attributes::NumberOfAttributes") -and `
    $text.commandCpp.Contains("targets[attribute] < limits[attribute].first") -and `
    $text.commandCpp.Contains("targets[attribute] > limits[attribute].second") -and `
    $text.commandCpp.Contains("return assigned == total") -and `
    $text.commandCpp.Contains("targets.reserve(Attributes::NumberOfAttributes)") -and `
    $text.commandCpp.Contains("pointsLeft as a tenth integer. It is advisory")
Assert-Contract -Condition $validationReady -Name "p14.stat-migration.submit.nine-target-bounds-and-authoritative-sum"

$responseReady = `
    $text.commandCpp.Contains("StatMigrationTargetsMessage const message(session.targets, session.pointsLeft)") -and `
    $text.commandCpp.Contains("creature->getClient()->send(message, true)")
Assert-Contract -Condition $responseReady -Name "p14.stat-migration.response.server-owned-target-vector"

$tutorialReady = `
    $text.commandCpp.Contains('if (creature->getSceneId() == "newbie_hall")') -and `
    $text.commandCpp.Contains("applyStatMigration(*creature, targets)") -and `
    $text.commandCpp.Contains("s_statMigrationSessions.erase(actor)") -and `
    $text.commandCpp.Contains("remain pending for the Image Designer workflow")
Assert-Contract -Condition $tutorialReady -Name "p14.stat-migration.commit.tutorial-immediate-and-consumed"

$nativeCommitReady = `
    $text.commandHeader.Contains("canCommitStatMigration") -and `
    $text.commandHeader.Contains("commitStatMigration") -and `
    $text.commandCpp.Contains("session->second.pointsLeft == 0") -and `
    $text.commandCpp.Contains("validateStatMigrationTargets(*creature, session->second.targets)") -and `
    $text.commandCpp.Contains("applyStatMigration(*creature, session->second.targets)") -and `
    $text.commandCpp.Contains("s_statMigrationSessions.erase(session)")
Assert-Contract -Condition $nativeCommitReady -Name "p14.stat-migration.commit.revalidated-and-consumed-once"

$controllerAuthenticationReady = `
    $text.playerController.Contains("SharedImageDesignerManager::Session authenticatedSession") -and `
    $text.playerController.Contains("authenticatedSession.designerId == designerId") -and `
    $text.playerController.Contains("authenticatedSession.recipientId == recipientId") -and `
    $text.playerController.Contains("authenticatedSession.terminalId == inMsg->getTerminalId()") -and `
    $text.playerController.Contains("designerId != recipientId") -and `
    $text.playerController.Contains("session.startingTime = authenticatedSession.startingTime") -and `
    $text.playerController.Contains("cancelSession(session.designerId, session.recipientId)")
Assert-Contract -Condition $controllerAuthenticationReady -Name "p14.stat-migration.image-designer.controller-session-identity"

$salonTransactionReady = `
    $text.imageDesignerManager.Contains("session.designType == ImageDesignChangeMessage::DT_STAT_MIGRATION") -and `
    $text.imageDesignerManager.Contains("designer != recipient") -and `
    $text.imageDesignerManager.Contains("designerTopmost->getNetworkId() == session.terminalId") -and `
    $text.imageDesignerManager.Contains("recipientTopmost->getNetworkId() == session.terminalId") -and `
    $text.imageDesignerManager.Contains("CommandCppFuncs::canCommitStatMigration(recipient->getNetworkId())") -and `
    $text.imageDesignerManager.Contains("CommandCppFuncs::commitStatMigration(recipient->getNetworkId())")
Assert-Contract -Condition $salonTransactionReady -Name "p14.stat-migration.image-designer.non-self-salon-transaction"

$nativeCallbackReady = `
    $text.imageDesignerNative.Contains("SharedImageDesignerManager::getSession(session.designerId, authenticatedSession)") -and `
    $text.imageDesignerNative.Contains("authenticatedSession.startingTime == session.startingTime") -and `
    $text.imageDesignerNative.Contains("authenticatedSession.designType == session.designType") -and `
    $text.imageDesignerNative.Contains("return JNI_FALSE")
Assert-Contract -Condition $nativeCallbackReady -Name "p14.stat-migration.image-designer.java-native-authentication"

$retailTimingAndRewardReady = `
    $text.sharedImageDesigner.Contains("ConfigSharedGame::getImageDesignerStatMigrationSessionTimeSeconds()") -and `
    $text.sharedImageDesigner.Contains("statMigrationRequested") -and `
    $text.sharedImageDesigner.Contains("ImageDesignChangeMessage::DT_STAT_MIGRATION") -and `
    $text.imageDesignerScript.Contains("IMAGE_DESIGN_EXPERIENCE_STAT_MIG = 2000") -and `
    $text.imageDesignerScript.Contains('if (designType == 2 || newHairSet || !holoEmote.equals("") || morphChangesKeys.length != 0 || indexChangesKeys.length != 0)') -and `
    $text.imageDesignerScript.Contains('xp.grant(self, xp.IMAGEDESIGNER, experience)') -and `
    -not $text.imageDesignerScript.Contains('xp.grantSocialStyleXp(self, xp.IMAGEDESIGNER, experience)') -and `
    $text.imageDesignerScript.Contains('utils.hasObjVar(structure, "salon")')
Assert-Contract -Condition $retailTimingAndRewardReady -Name "p14.stat-migration.image-designer.retail-timer-salon-and-reward"

$retailWireTimeReady = `
    $text.imageDesignerWireMessage.Contains("int const startingTimeWire = static_cast<int>(msg->getStartingTime())") -and `
    $text.imageDesignerWireMessage.Contains("Archive::put(target, startingTimeWire)") -and `
    $text.imageDesignerWireMessage.Contains("int tempTimeWire = 0") -and `
    $text.imageDesignerWireMessage.Contains("msg->setStartingTime(static_cast<time_t>(tempTimeWire))") -and `
    -not $text.imageDesignerWireMessage.Contains("Archive::put(target, msg->getStartingTime())")
Assert-Contract -Condition $retailWireTimeReady -Name "p14.stat-migration.image-designer.retail-32-bit-start-time-wire"

Assert-Contract `
    -Condition ([string]$contract.knownLimitations.imageDesignerCommit -like "Restored*" -and [string]$contract.knownLimitations.sessionPersistence -like "Pending*") `
    -Name "p14.stat-migration.boundary.image-designer-restored-process-local-persistence-explicit"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 stat-migration contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 stat-migration contract passed."
