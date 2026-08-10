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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3ActionPreparationAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

$combatPath = Join-Path $source ([string]$contract.sourceFiles.combatBase)
$combatDataPath = Join-Path $source ([string]$contract.sourceFiles.combatData)
$overridesPath = Join-Path $source ([string]$contract.sourceFiles.combatOverrides)
$runtimeFixturePath = Join-Path $source ([string]$contract.sourceFiles.runtimeFixture)
foreach ($path in @($combatPath, $combatDataPath, $overridesPath, $runtimeFixturePath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.action-preparation.source.$([IO.Path]::GetFileName($path))"
}

$combat = Get-Content -LiteralPath $combatPath -Raw
$runtimeFixture = Get-Content -LiteralPath $runtimeFixturePath -Raw
$overlayPath = Join-Path (Split-Path -Parent $restorationRoot) `
    ([string]$contract.buildEvidence.overlayPatch)
Assert-Contract (Test-Path -LiteralPath $overlayPath -PathType Leaf) `
    "p14.action-preparation.overlay.exists"
if (Test-Path -LiteralPath $overlayPath -PathType Leaf)
{
    $overlay = Get-Item -LiteralPath $overlayPath
    $overlayHash = (Get-FileHash -LiteralPath $overlayPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Contract ($overlay.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
        $overlayHash -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
        "p14.action-preparation.overlay.authenticated"
}

$overrideCall = $combat.IndexOf('actionData = attackOverrideByBuff(self, actionData);', [StringComparison]::Ordinal)
$authorityBeforeOverride = $combat.LastIndexOf('isPrecuAuthoritativeAttack(self, actionData);', $overrideCall, [StringComparison]::Ordinal)
Assert-Contract ($overrideCall -gt 0 -and $authorityBeforeOverride -ge 0 -and
    $combat.Contains('if (!precuAuthoritativeAction)')) "p14.action-preparation.command-identity"

Assert-Contract ($combat.Contains('if (!isTangibleAttacking && !precuAuthoritativeAction)') -and
    $combat.Contains('actionData = modifyActionDataByExpertise(self, actionData);') -and
    $combat.Contains('int killMeterCost = precuAuthoritativeAction ? 0 :') -and
    $combat.Contains('if (!precuAuthoritativeAction && killMeterCost > 0)')) "p14.action-preparation.expertise-and-vigor-contained"

Assert-Contract ($combat.Contains('!isPrecuAuthoritativeAttack(objOwner, actionData)') -and
    $combat.Contains('"preparation.ngeDelayApplied", 0')) "p14.action-preparation.delay.authored"

Assert-Contract ($combat.Contains('actionData.maxRange : Math.max(10.0f, weaponData.maxRange)') -and
    $combat.Contains('else if (actionData.overloadWeaponType == WEAPON_TYPE_THROWN)') -and
    $combat.Contains('"preparation.ngeRangeApplied", 0')) "p14.action-preparation.range.core3"

$rangeStart = $combat.IndexOf('public boolean isInAttackRange(', [StringComparison]::Ordinal)
$rangeEnd = $combat.IndexOf('public boolean doCombatPreCheck(', $rangeStart, [StringComparison]::Ordinal)
$rangeMethod = if ($rangeStart -ge 0 -and $rangeEnd -gt $rangeStart) {
    $combat.Substring($rangeStart, $rangeEnd - $rangeStart)
} else { "" }
$ngeRangeGuard = $rangeMethod.IndexOf('if (!precuAuthoritativeAction)', [StringComparison]::Ordinal)
$ngeRangeBonus = $rangeMethod.IndexOf('"expertise_range_bonus_"', [StringComparison]::Ordinal)
$ngeRangeLine = $rangeMethod.IndexOf('"expertise_range_line_"', [StringComparison]::Ordinal)
$rangeGuardEnd = $rangeMethod.IndexOf('if (precuAuthoritativeAction &&', $ngeRangeGuard, [StringComparison]::Ordinal)
if ($rangeGuardEnd -lt 0)
{
    $rangeGuardEnd = $rangeMethod.IndexOf('if (dist > (weaponData.maxRange', $ngeRangeGuard, [StringComparison]::Ordinal)
}
Assert-Contract ($ngeRangeGuard -ge 0 -and
    $ngeRangeBonus -gt $ngeRangeGuard -and
    $ngeRangeLine -gt $ngeRangeBonus -and
    $rangeGuardEnd -gt $ngeRangeLine -and
    ([regex]::Matches($rangeMethod, '"expertise_range_(?:bonus|line)_"').Count -eq 2)) `
    "p14.action-preparation.range.nge-modifiers-scoped"

Assert-Contract ($combat.Contains('if (!precuAuthoritativeAction)') -and
    $combat.Contains('"expertise_cone_length_single_"') -and
    $combat.Contains('"expertise_area_size_single_"') -and
    $combat.Contains('"preparation.ngeGeometryApplied", 0')) "p14.action-preparation.geometry.authored"

$precuWeaponBranch = $combat.IndexOf('weapon_data precuWeaponData = weapons.getNewWeaponData(objWeapon);', [StringComparison]::Ordinal)
$ngeOverloadBranch = $combat.IndexOf('if (actionData.overloadWeapon > 0)', $precuWeaponBranch, [StringComparison]::Ordinal)
$ngeElementBranch = $combat.IndexOf('weaponData.elementalValue = isPlayer(self) ? weaponData.elementalValue * 2', $ngeOverloadBranch, [StringComparison]::Ordinal)
Assert-Contract ($precuWeaponBranch -gt 0 -and $ngeOverloadBranch -gt $precuWeaponBranch -and
    $ngeElementBranch -gt $ngeOverloadBranch -and
    $combat.Contains('"preparation.ngeElementalMultiplierApplied", 0') -and
    $combat.Contains('"preparation.ngeWeaponOverloadApplied", 0')) "p14.action-preparation.weapon-values.raw"

$rampageBranch = $combat.IndexOf('int rampageAttacks = getEnhancedSkillStatisticModifierUncapped', [StringComparison]::Ordinal)
$rampageGuard = $combat.LastIndexOf('if (!precuAuthoritativeAttack)', $rampageBranch, [StringComparison]::Ordinal)
Assert-Contract ($rampageBranch -gt 0 -and $rampageGuard -ge 0) "p14.action-preparation.rampage.contained"

$combatRows = @(Import-SwgTab -Path $combatDataPath)
$burst = @($combatRows | Where-Object actionName -ceq 'burstShot1')
$lunge = @($combatRows | Where-Object actionName -ceq 'unarmedLunge1')
$flame = @($combatRows | Where-Object actionName -ceq 'flameCone1')
$autoArea = @($combatRows | Where-Object actionName -ceq 'fullAutoArea1')
$rowsValid = $burst.Count -eq 1 -and [double]$burst[0].maxRange -eq 64 -and
    [string]$burst[0].attackType -ceq 'SINGLE_TARGET' -and
    $lunge.Count -eq 1 -and [double]$lunge[0].maxRange -eq 20 -and
    [string]$lunge[0].attackType -ceq 'SINGLE_TARGET' -and
    $flame.Count -eq 1 -and [double]$flame[0].coneLength -eq 16 -and
    [double]$flame[0].coneWidth -eq 45 -and
    [string]$flame[0].attackType -ceq 'CONE' -and
    $autoArea.Count -eq 1 -and [double]$autoArea[0].coneLength -eq 64 -and
    [double]$autoArea[0].coneWidth -eq 30 -and
    [string]$autoArea[0].attackType -ceq 'CONE'
Assert-Contract $rowsValid "p14.action-preparation.authored-command-values"

$overrides = @(Import-SwgTab -Path $overridesPath)
$authenticated = @($overrides | Where-Object { @('burstShot1', 'unarmedLunge1', 'flameCone1', 'fullAutoArea1') -ccontains [string]$_.actionName })
Assert-Contract ($authenticated.Count -eq 4) "p14.action-preparation.actions.authenticated"
Assert-Contract ($runtimeFixture.Contains("PLAYER_OID = 44003778L") -and
    $runtimeFixture.Contains('ATTACK_COMMAND = "creatureMeleeAttack"') -and
    $runtimeFixture.Contains('action=armCombatDiagnostics') -and
    $runtimeFixture.Contains('action=diagnostics result=') -and
    $runtimeFixture.Contains('action=cleanup alreadyClean=true restored=true') -and
    $runtimeFixture.Contains('forceDestroy(object);')) `
    "p14.action-preparation.runtime-fixture-identity-bound-and-reversible"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) "p14.action-preparation.contract.status"

if ($Expectation -eq "Ready")
{
    $runtime = $contract.liveEvidence
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$runtime.result -ceq "passed" -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "p14.action-preparation.ready-evidence-complete"

    $fixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeFixturePath).
        Hash.ToLowerInvariant()
    Assert-Contract ($fixtureHash -ceq
        [string]$contract.buildEvidence.runtimeFixtureSourceSha256 -and
        [string]$contract.buildEvidence.runtimeFixtureJavaCompile -ceq "passed") `
        "p14.action-preparation.ready-fixture-build"

    $dsrcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "dsrc" })
    $srcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "src" })
    $checkedOutDsrc = (& git -C (Join-Path $source "dsrc") rev-parse HEAD).Trim()
    $dsrcExit = $LASTEXITCODE
    $checkedOutSrc = (& git -C (Join-Path $source "src") rev-parse HEAD).Trim()
    $srcExit = $LASTEXITCODE
    Assert-Contract ($dsrcExit -eq 0 -and $srcExit -eq 0 -and
        $dsrcPin.Count -eq 1 -and $srcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq
            [string]$contract.buildEvidence.directSourceGitlink -and
        [string]$srcPin[0].commit -ceq
            [string]$contract.buildEvidence.nativeSourceCommit -and
        $checkedOutDsrc -ceq
            [string]$contract.buildEvidence.directSourceGitlink -and
        $checkedOutSrc -ceq
            [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.action-preparation.ready-source-pins"

    $preparation = $runtime.preparation
    Assert-Contract ([string]$runtime.command -ceq "creatureMeleeAttack" -and
        [string]$runtime.attackerProfile -ceq "rancor" -and
        [double]$preparation.delay -eq 0.0 -and
        [double]$preparation.maxRange -eq 10.0 -and
        [int]$preparation.elementalValue -eq 0 -and
        [int]$preparation.ngeDelayApplied -eq 0 -and
        [int]$preparation.ngeRangeApplied -eq 0 -and
        [int]$preparation.ngeElementalMultiplierApplied -eq 0 -and
        [int]$preparation.ngeWeaponOverloadApplied -eq 0 -and
        [string]$preparation.result -ceq "passed") `
        "p14.action-preparation.ready-live-preparation"

    $cadence = $runtime.cadence
    Assert-Contract ([int]$cadence.attackEvents -ge 3 -and
        [double]$cadence.assignedIntervalSeconds -eq 2.0 -and
        [double]$cadence.minimumObservedConsecutiveSeconds -ge 1.95 -and
        [int]$cadence.pairsBelow1_95Seconds -eq 0 -and
        [string]$cadence.result -ceq "passed") `
        "p14.action-preparation.ready-live-cadence"

    Assert-Contract ([bool]$runtime.fixtureCleanup.firstCleanupRestored -and
        [bool]$runtime.fixtureCleanup.secondCleanupAlreadyClean -and
        [bool]$runtime.fixtureCleanup.cadenceStableAfterCleanup -and
        [int]$runtime.fixtureCleanup.delayedErrorCount -eq 0 -and
        -not [bool]$runtime.fixtureCleanup.playerStateMutated -and
        [bool]$runtime.environment.sourceAndBuildVolumeMatch -and
        [bool]$runtime.environment.liveProcessMappedBuiltBinary -and
        [bool]$runtime.environment.serverHealthy -and
        [bool]$runtime.environment.clusterReadyForPlayers -and
        [int]$runtime.environment.PlanetServer -eq 15 -and
        [int]$runtime.environment.SwgGameServer -eq 15 -and
        [bool]$runtime.environment.primaryClientRemainedOpenAndResponsive) `
        "p14.action-preparation.ready-live-environment-and-cleanup"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14Core3ActionPreparationAuthority)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "p14.action-preparation.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Publish 14 Core3 action-preparation authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 Core3 action-preparation authority passed."
