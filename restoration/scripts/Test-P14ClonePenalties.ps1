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
$manifest =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot "manifest.json"
    ) -Raw | ConvertFrom-Json
$contract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.p14ClonePenalties
        )
    ) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] =
        Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required clone-penalty source is missing: $path"
    }
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

$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$pclib = Get-Content -LiteralPath $paths.playerLibrary -Raw
$cloning = Get-Content -LiteralPath $paths.cloningLibrary -Raw
$decayTable = Get-Content -LiteralPath $paths.decayTable -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw

Write-Host "Publish 14.1 clone-penalty checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [int]$contract.semanticReference.
        alternateFacilityPrimaryWounds.health -eq 100 -and
    [int]$contract.semanticReference.
        alternateFacilityPrimaryWounds.action -eq 100 -and
    [int]$contract.semanticReference.
        alternateFacilityPrimaryWounds.mind -eq 100 -and
    [int]$contract.semanticReference.
        alternateFacilityBattleFatigue -eq 100 -and
    [int]$contract.semanticReference.deathTypes.pveAi -eq 0 -and
    [int]$contract.semanticReference.deathTypes.
        playerDeathBlow -eq 1) `
    -Name "p14.clone.core3.pinned-wounds-fatigue-and-death-types"

Assert-Contract -Condition (
    $decayTable.Contains(
        "death`t1`t5`t1") -and
    [string]$contract.retainedTableReference.sha256 -ceq
        "28be456e66abcdb1e902eb02965da54b84e02d0a521db9ced74b63f5de2d6f90") `
    -Name "p14.clone.retained-table.one-five-percent-and-uninsure"

Assert-Contract -Condition (
    $cloning.Contains(
        "PRECU_CLONE_WOUND_AMOUNT = 100") -and
    $cloning.Contains("PRECU_INSURED_DECAY = 0.01f") -and
    $cloning.Contains(
        "PRECU_UNINSURED_DECAY = 0.05f") -and
    $cloning.Contains(
        "addWound(player, HEALTH, PRECU_CLONE_WOUND_AMOUNT)") -and
    $cloning.Contains(
        "addWound(player, ACTION, PRECU_CLONE_WOUND_AMOUNT)") -and
    $cloning.Contains(
        "addWound(player, MIND, PRECU_CLONE_WOUND_AMOUNT)") -and
    $cloning.Contains(
        "addShockWound(player, PRECU_CLONE_WOUND_AMOUNT)")) `
    -Name "p14.clone.runtime.alternate-facility-wounds-and-fatigue"

Assert-Contract -Condition (
    $cloning.Contains(
        "if (!isDamagedOnClone(player, item))") -and
    $cloning.Contains("if (isInsured(item))") -and
    $cloning.Contains(
        "pclib.damageAndDecayItem(item, PRECU_INSURED_DECAY)") -and
    $cloning.Contains("setInsured(item, false)") -and
    $cloning.Contains(
        "pclib.damageAndDecayItem(item, PRECU_UNINSURED_DECAY)") -and
    $pclib.Contains(
        "damageAndDecayItem(item, (int)(maxHitpoints * percent))") -and
    $pclib.Contains(
        "setHitpoints(item, Math.max(0, hitpoints - amount))")) `
    -Name "p14.clone.runtime.exact-eligible-item-decay"

Assert-Contract -Condition (
    $basePlayer.Contains(
        "utils.setScriptVar(self, pclib.VAR_REVIVE_DAMAGE, damage)") -and
    $basePlayer.Contains(
        "facility == bound") -and
    $basePlayer.Contains(
        "cloninglib.PRECU_CLONE_WOUND_AMOUNT") -and
    $basePlayer.Contains(
        "pclib.playerRevive(self, clone, spawn, damage)") -and
    $pclib.Contains("VAR_PRECU_CLONE_WOUND") -and
    $basePlayer.Contains("boolean hasClonePenalty =") -and
    $basePlayer.Contains(
        "boolean decayItems = !utils.hasScriptVar(self, `"pvp_death`")") -and
    $basePlayer.Contains(
        "cloninglib.applyPrecuClonePenalties(")) `
    -Name "p14.clone.runtime.parallel-selection-and-exactly-once-completion"

Assert-Contract -Condition (
    $pclib.Contains(
        'VAR_REVIVE_SELECTION = "revive.selectedRow"') -and
    $basePlayer.Contains(
        "utils.setScriptVar(self, pclib.VAR_REVIVE_SELECTION, idx)") -and
    $basePlayer.Contains(
        "idx < 0 || options == null || cloneLocs == null") -and
    $basePlayer.Contains(
        "utils.hasScriptVar(self, pclib.VAR_REVIVE_SELECTION)") -and
    $basePlayer.Contains(
        "idx =`r`n                    utils.getIntScriptVar(") -and
    $basePlayer.Contains(
        "utils.removeScriptVar(self, pclib.VAR_REVIVE_SELECTION)")) `
    -Name "p14.clone.runtime.server-observed-selection-close-compatibility"

Assert-Contract -Condition (
    $pclib.Contains(
        'utils.setScriptVar(player, "waitingOnCloneRespawn", 1)') -and
    $pclib.Contains(
        "messageTo(player, HANDLER_CLONE_RESPAWN, null, 5, true)") -and
    $basePlayer.Contains(
        "if (!isDead(self) &&") -and
    $basePlayer.Contains(
        '!utils.hasScriptVar(self, "waitingOnCloneRespawn")') -and
    $basePlayer.Contains(
        "!utils.hasScriptVar(self, pclib.VAR_PRECU_CLONE_WOUND)") -and
    $basePlayer.Contains(
        '!hasObjVar(self, "fullHealClone")')) `
    -Name "p14.clone.runtime.same-scene-transfer-fallback-idempotence"

Assert-Contract -Condition (
    -not $basePlayer.Contains(
        'buff.applyBuff(self, "cloning_sickness")') -and
    $basePlayer.Contains(
        'buff.removeBuff(self, "cloning_sickness")')) `
    -Name "p14.clone.runtime.nge-cloning-sickness-retired"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains('equalsIgnoreCase("unboundPve")') -and
    $fixture.Contains('equalsIgnoreCase("boundPve")') -and
    $fixture.Contains('equalsIgnoreCase("unboundPvp")') -and
    $fixture.Contains(
        "cloninglib.applyPrecuClonePenalties(") -and
    $fixture.Contains("snapshotEligibleItems(player)") -and
    $fixture.Contains("restoreEligibleItems(player)") -and
    $fixture.Contains("destroyIfValid(") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    -Name "p14.clone.fixture.three-modes-all-item-preimages-and-cleanup"

Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    [string]$contract.buildEvidence.sourceCommit -ceq
        "58964fb24" -and
    [string]$contract.buildEvidence.patchSha256 -ceq
        "dae4c907662bff7b35822b13cac092759fe005d2a96dd90ed8a7ef39ac65bd79" -and
    [int]$contract.buildEvidence.sourceCount -eq 5675 -and
    -not [string]::IsNullOrWhiteSpace(
        [string]$contract.buildEvidence.compiledSha256.
            "precu_clone_penalty_fixture.class")) `
    -Name "p14.clone.build.clean-java-evidence"

Assert-Contract -Condition (
    [string]$contract.selectionCompatibilityBuildEvidence.result -ceq
        "passed" -and
    [string]$contract.selectionCompatibilityBuildEvidence.
        overlayPatchSha256 -ceq
        "6296c5ec685c56d61a2628004f4a22b3afdca8fdc874126e797d32cfdf7d235" -and
    [string]$contract.selectionCompatibilityBuildEvidence.
        cleanApplyCheck -ceq "passed" -and
    [int]$contract.selectionCompatibilityBuildEvidence.
        finalIncrementalBuild.compiledSourceCount -eq 2 -and
    -not [string]::IsNullOrWhiteSpace(
        [string]$contract.selectionCompatibilityBuildEvidence.
            compiledSha256."pclib.class") -and
    -not [string]::IsNullOrWhiteSpace(
        [string]$contract.selectionCompatibilityBuildEvidence.
            compiledSha256."base_player.class")) `
    -Name "p14.clone.build.selection-and-transfer-compatibility"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 30) `
        -Name "p14.clone.status.ready-protocol-thirty"
    Assert-Contract -Condition (
        [bool]$live.unboundPve.passed -and
        [int]$live.unboundPve.healthWound -eq 100 -and
        [int]$live.unboundPve.actionWound -eq 100 -and
        [int]$live.unboundPve.mindWound -eq 100 -and
        [int]$live.unboundPve.shock -eq 100 -and
        [int]$live.unboundPve.insuredHp -eq 990 -and
        -not [bool]$live.unboundPve.insuredFlag -and
        [int]$live.unboundPve.uninsuredHp -eq 950 -and
        [int]$live.unboundPve.autoInsuredHp -eq 1000) `
        -Name "p14.clone.live.unbound-pve-wounds-and-decay"
    Assert-Contract -Condition (
        [bool]$live.boundPve.passed -and
        [int]$live.boundPve.healthWound -eq 0 -and
        [int]$live.boundPve.shock -eq 0 -and
        [int]$live.boundPve.insuredHp -eq 990 -and
        [int]$live.boundPve.uninsuredHp -eq 950 -and
        [bool]$live.unboundPvp.passed -and
        [int]$live.unboundPvp.healthWound -eq 100 -and
        [int]$live.unboundPvp.insuredHp -eq 1000 -and
        [bool]$live.unboundPvp.insuredFlag) `
        -Name "p14.clone.live.bound-and-pvp-death-type-split"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.cleanup.fixtureRootAbsent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.clone.live.exact-cleanup-and-container-health"
    $selection = $live.selectionCompatibility
    Assert-Contract -Condition (
        [string]$selection.result -ceq "passed" -and
        [int]$selection.clientProtocolVersion -eq 31 -and
        [int]$selection.selectionIndex -eq 0 -and
        [bool]$selection.serverPromptRoundTrip -and
        [bool]$selection.realOkCallback -and
        -not [bool]$selection.victimDead -and
        [int]$selection.victimPosture -eq 0 -and
        [int]$selection.healthWound -eq 100 -and
        [int]$selection.actionWound -eq 100 -and
        [int]$selection.mindWound -eq 100 -and
        [int]$selection.shock -eq 100 -and
        [int]$selection.insuredHp -eq 1000 -and
        [bool]$selection.insuredFlag -and
        [int]$selection.uninsuredHp -eq 1000 -and
        [int]$selection.autoInsuredHp -eq 1000) `
        -Name "p14.clone.live.protocol-thirty-one-selection-and-completion"
    Assert-Contract -Condition (
        [bool]$selection.cleanup.restored -and
        [bool]$selection.cleanup.idempotent -and
        [bool]$selection.cleanup.allRootsAbsent -and
        [bool]$selection.serverHealthyAfterCleanup -and
        [bool]$selection.oracleHealthyAfterCleanup -and
        [bool]$contract.publicationBoundary.clientToolsChanged -and
        [int]$contract.publicationBoundary.clientProtocolVersion -eq 31) `
        -Name "p14.clone.live.protocol-thirty-one-cleanup-and-boundary"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 clone-penalty contract failed: " +
        ($failures -join ", ")
}

Write-Host ""
Write-Host "Publish 14.1 clone-penalty contract passed."
