[CmdletBinding()]
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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14Core3CombatAdmissionLifecycleAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$paths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $source ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $paths[$property.Name] -PathType Leaf) `
        "p14.combat-lifecycle.source.$($property.Name)"
}

$combat = Get-Content -LiteralPath $paths.combatBase -Raw
$combatPlayer = Get-Content -LiteralPath $paths.combatPlayer -Raw
$aiCorpse = Get-Content -LiteralPath $paths.aiCorpse -Raw
$queue = Get-Content -LiteralPath $paths.commandQueue -Raw
$queueHeader = Get-Content -LiteralPath $paths.commandQueueHeader -Raw
$aiCadenceRuntime = Get-Content -LiteralPath $paths.aiCadenceRuntime -Raw
$localOptions = Get-Content -LiteralPath $paths.localOptions -Raw

foreach ($evidence in @($contract.buildEvidence.overlayPatches))
{
    $patchPath = Join-Path (Split-Path -Parent $restorationRoot) ([string]$evidence.path)
    $exists = Test-Path -LiteralPath $patchPath -PathType Leaf
    Assert-Contract $exists "p14.combat-lifecycle.overlay.$([string]$evidence.component).exists"
    if ($exists)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and
            $sha -ceq [string]$evidence.sha256) `
            "p14.combat-lifecycle.overlay.$([string]$evidence.component).authenticated"
    }
}

$standardAction = Get-FunctionSlice $combat "public boolean combatStandardAction(" "public boolean isInAttackRange("
$stealthGuard = $standardAction.IndexOf("if (!precuAuthoritativeAction)", [StringComparison]::Ordinal)
$stealthClear = $standardAction.IndexOf("stealth.clearPreviousInvis(self);", [StringComparison]::Ordinal)
$stealthTest = $standardAction.IndexOf("stealth.testInvisCombatAction(self, target, actionData);", [StringComparison]::Ordinal)
Assert-Contract ($stealthGuard -ge 0 -and $stealthClear -gt $stealthGuard -and
    $stealthTest -gt $stealthClear -and
    ([regex]::Matches($combat, "stealth\.reinstateInvisFromCombat\(").Count -eq 1) -and
    $combat.Contains("public void reinstateNgeInvisFromCombat(") -and
    $combat.Contains("if (!precuAuthoritativeAction)")) `
    "p14.combat-lifecycle.nge-stealth-contained"

$range = Get-FunctionSlice $combat "public boolean isInAttackRange(" "public boolean doCombatPreCheck("
Assert-Contract ($range.Contains("if (precuAuthoritativeAction &&") -and
    $range.Contains("combat.isRangedWeapon(weaponData.weaponType)") -and
    $range.Contains("getPosture(attacker) == POSTURE_PRONE") -and
    $range.Contains("dist <= 7.0f") -and
    $range.Contains('"admission.proneRangedTooClose", 1')) `
    "p14.combat-lifecycle.core3-prone-ranged-admission"

Assert-Contract ($combat.Contains("(precuAuthoritativeAttack || hitData[i].success)") -and
    $combat.Contains("startCombat(defenderData[i].id, attackerData.id);") -and
    $combat.Contains('"admission.defenderCombatStarted",')) `
    "p14.combat-lifecycle.defender-starts-on-authenticated-miss"

$hate = Get-FunctionSlice $combat "public void addPrecuCore3HateProcess(" "public int getPrecuSecondaryDefenseResult("
Assert-Contract ($combat.Contains("if (precuAuthoritativeAttack)") -and
    $combat.Contains("addPrecuCore3HateProcess(") -and
    $combat.Contains("combat.addHateProcess(") -and
    $hate.Contains("float hate = hitData.success ?") -and
    $hate.Contains("hitData.damage * actionData.hateDamageModifier : 1.0f") -and
    $hate.Contains("addHate(defender, attacker, hate)")) `
    "p14.combat-lifecycle.core3-base-hate"

Assert-Contract ($combat.Contains("if (!precuAuthoritativeAttack && criticalHit") -and
    $combat.Contains("if (!precuAuthoritativeAttack && seriesStrikethrough)") -and
    $combat.Contains("if (!precuAuthoritativeAttack &&`n            utils.hasScriptVar(attackerData.id, buff.ON_ATTACK_REMOVE)") -and
    -not $combatPlayer.Contains("expertise_stance_riposte") -and
    -not $combatPlayer.Contains("bh_relentless_onslaught") -and
    -not $combatPlayer.Contains("expertise_of_last_words_1")) `
    "p14.combat-lifecycle.nge-expertise-lifecycle-contained"

$harvestCallback = Get-FunctionSlice $aiCorpse "public int harvestCorpse(" "public int handleFailedHarvest("
Assert-Contract ($harvestCallback.Contains("!corpse.canPlayerHarvestCreature(player, true)") -and
    $harvestCallback.Contains('LOG("PreCuScoutHarvest"') -and
    $harvestCallback.IndexOf("!corpse.canPlayerHarvestCreature", [StringComparison]::Ordinal) -lt
        $harvestCallback.IndexOf("corpse.harvestCreatureCorpse", [StringComparison]::Ordinal)) `
    "p14.combat-lifecycle.harvest-java-callback-revalidation"

$enqueue = Get-FunctionSlice $queue "void CommandQueue::enqueue(" "void CommandQueue::remove("
$doExecute = Get-FunctionSlice $queue "void CommandQueue::doExecute(" "void CommandQueue::finishExecute("
$executeGate = $doExecute.IndexOf('entry.m_command->m_commandName == "harvestCorpse"', [StringComparison]::Ordinal)
$executeDispatch = $doExecute.IndexOf("executeCommand( *entry.m_command", [StringComparison]::Ordinal)
Assert-Contract ($enqueue.Contains('command.m_commandName == "harvestCorpse"') -and
    $enqueue.Contains("!canHarvestPrecuCreatureResources(*creatureOwner)") -and
    $doExecute.Contains('entry.m_command->m_commandName == "harvestCorpse"') -and
    $doExecute.Contains("!canHarvestPrecuCreatureResources(*creatureOwner)") -and
    $doExecute.Contains("m_status = Command::CEC_Cancelled") -and
    $doExecute.Contains("rejected phase=execute") -and
    $executeGate -ge 0 -and $executeDispatch -gt $executeGate) `
    "p14.combat-lifecycle.harvest-native-enqueue-and-execute-revalidation"

$timing = Get-FunctionSlice $queue "float calculatePrecuAttackTime(" "float getCommandExecuteTime("
Assert-Contract ($timing.Contains("if (!owner.isPlayerControlled())") -and
    $timing.Contains("return 2.0f;") -and
    $timing.Contains("speedMultiplier * weaponAttackSpeed") -and
    $timing.Contains('getEnhancedModValue("private_speed_bonus")') -and
    $timing.Contains('getEnhancedModValue("combat_haste")') -and
    $timing.Contains("executeTime > 1.0f ? executeTime : 1.0f")) `
    "p14.combat-lifecycle.core3-cadence-formula"

Assert-Contract ($queueHeader.Contains("m_lastWeaponCadenceAttackTime") -and
    $queueHeader.Contains("m_lastWeaponCadenceInterval") -and
    $queue.Contains("double const earliestAttackTime") -and
    $queue.Contains("m_nextEventTime = earliestAttackTime") -and
    $doExecute.Contains("primary=%d classified=%d speedSkill=%s familySpeed=%d") -and
    $doExecute.Contains("privateSpeed=%d privateMeleeSpeed=%d meleeSpeed=%d") -and
    $doExecute.Contains("privateRangedSpeed=%d rangedSpeed=%d combatHaste=%d") -and
    $doExecute.Contains("unclassified time=")) `
    "p14.combat-lifecycle.cadence-global-gate-and-diagnostics"

Assert-Contract ($localOptions.Contains(
    "logTarget=file:logs/precuCombatCadence.log{c-*:c+PreCuCombatCadence}") -and
    $localOptions.Contains(
    "logTarget=file:logs/precuScoutHarvest.log{c-*:c+PreCuScoutHarvest}")) `
    "p14.combat-lifecycle.filtered-runtime-log-targets"

Assert-Contract ($aiCadenceRuntime.Contains("PLAYER_OID = 44003778L") -and
    $aiCadenceRuntime.Contains("PLAYER_STATION_ID = 91001") -and
    $aiCadenceRuntime.Contains('ATTACK_COMMAND = "meleeHit"') -and
    $aiCadenceRuntime.Contains("queueCommand(") -and
    $aiCadenceRuntime.Contains("createFixtureCreature") -and
    $aiCadenceRuntime.Contains("destroyTracked(") -and
    $aiCadenceRuntime.Contains("playerStateMutated=false")) `
    "p14.combat-lifecycle.ai-runtime-reversible-production-queue"

if ($Expectation -eq "Ready")
{
    $runtime = $contract.runtimeEvidence
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$runtime.result -ceq "passed" -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "p14.combat-lifecycle.ready-evidence-complete"

    $dsrcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "dsrc" })
    $srcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "src" })
    $checkedOutDsrc = (& git -C (Join-Path $source "dsrc") rev-parse HEAD).Trim()
    $checkedOutSrc = (& git -C (Join-Path $source "src") rev-parse HEAD).Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $dsrcPin.Count -eq 1 -and
        $srcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq
            [string]$contract.buildEvidence.directSourceGitlink -and
        [string]$srcPin[0].commit -ceq
            [string]$contract.buildEvidence.nativeSourceCommit -and
        $checkedOutDsrc -ceq
            [string]$contract.buildEvidence.directSourceGitlink -and
        $checkedOutSrc -ceq
            [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.combat-lifecycle.ready-source-pins"

    $hashChecks = [ordered]@{
        combatBase = "combat_base.java"
        combatPlayer = "combat_player.java"
        aiCorpse = "ai_corpse.java"
        commandQueue = "CommandQueue.cpp"
        commandQueueHeader = "CommandQueue.h"
        aiCadenceRuntime = "precu_ai_attack_interval_runtime.java"
    }
    $sourceHashesMatch = $true
    foreach ($entry in $hashChecks.GetEnumerator())
    {
        $actual = (Get-FileHash -LiteralPath $paths[$entry.Key] -Algorithm SHA256).
            Hash.ToLowerInvariant()
        $expectedHash = $contract.buildEvidence.sourceSha256.PSObject.
            Properties[$entry.Value]
        $sourceHashesMatch = $sourceHashesMatch -and
            $null -ne $expectedHash -and
            $actual -ceq [string]$expectedHash.Value
    }
    Assert-Contract $sourceHashesMatch `
        "p14.combat-lifecycle.ready-source-hashes"

    $harvest = $runtime.nonScoutHarvestAdmission
    Assert-Contract (-not [bool]$harvest.noviceScoutOwned -and
        [string]$harvest.command -ceq "harvestCorpse" -and
        [bool]$harvest.queueCommandReturned -and
        [bool]$harvest.rejectedAtNativeEnqueue -and
        [bool]$harvest.stateFree -and
        [string]$harvest.result -ceq "passed" -and
        [string]$harvest.nativeLogLine -match
            '^20260810032022:SwgGameServer:[0-9]+:PreCuScoutHarvest:rejected owner=1433054682 command=harvestCorpse target=0$') `
        "p14.combat-lifecycle.ready-harvest-admission"

    $player = $runtime.playerCadence
    Assert-Contract ([bool]$player.playerControlled -and
        [int]$player.attackEvents -ge 2 -and
        [int]$player.consecutiveSameServerOwnerPairs -ge 1 -and
        [double]$player.minimumObservedConsecutiveSeconds -ge
            [double]$player.assignedIntervalSeconds -and
        [int]$player.pairsBelowAssignedInterval -eq 0 -and
        [string]$player.result -ceq "passed") `
        "p14.combat-lifecycle.ready-player-cadence"

    $ai = $runtime.aiCadence
    Assert-Contract (-not [bool]$ai.playerControlled -and
        [int]$ai.attackEvents -ge 3 -and
        [int]$ai.consecutiveSameServerOwnerPairs -ge 2 -and
        [double]$ai.assignedIntervalSeconds -eq 2.0 -and
        [double]$ai.minimumObservedConsecutiveSeconds -ge 1.95 -and
        [int]$ai.pairsBelow1_95Seconds -eq 0 -and
        [int]$ai.gateEvents -ge 1 -and
        [bool]$ai.cleanupRestored -and
        [bool]$ai.secondCleanupAlreadyClean -and
        -not [bool]$ai.playerStateMutated -and
        [string]$ai.result -ceq "passed") `
        "p14.combat-lifecycle.ready-ai-cadence"

    Assert-Contract ([bool]$runtime.containerHealthy -and
        [bool]$runtime.clusterReadyForPlayers -and
        [bool]$runtime.sourceAndBuildVolumeMatch -and
        [bool]$runtime.liveProcessMappedBuiltBinary -and
        [int]$runtime.processCounts.PlanetServer -eq 15 -and
        [int]$runtime.processCounts.SwgGameServer -eq 15 -and
        [bool]$runtime.primaryClient.remainedOpenAndResponsive) `
        "p14.combat-lifecycle.ready-live-environment"
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
        [string]$contract.status) "p14.combat-lifecycle.contract.status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14Core3CombatAdmissionLifecycleAuthority)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "p14.combat-lifecycle.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Publish 14 Core3 combat-admission/lifecycle authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 Core3 combat-admission/lifecycle authority passed."
