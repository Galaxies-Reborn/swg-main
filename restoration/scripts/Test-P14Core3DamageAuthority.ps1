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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3DamageAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

$combatPath = Join-Path $source ([string]$contract.sourceFiles.combatBase)
$combatLibraryPath = Join-Path $source ([string]$contract.sourceFiles.combatLibrary)
$xpPath = Join-Path $source ([string]$contract.sourceFiles.xp)
$gcwPath = Join-Path $source ([string]$contract.sourceFiles.gcw)
$combatActionsPath = Join-Path $source ([string]$contract.sourceFiles.combatActions)
$basePlayerPath = Join-Path $source ([string]$contract.sourceFiles.basePlayer)
$profilesPath = Join-Path $source ([string]$contract.sourceFiles.weaponProfiles)
$generatorPath = Join-Path $restorationRoot (([string]$contract.sourceFiles.generator).Substring("restoration/".Length))
$runtimeFixturePath = Join-Path $source ([string]$contract.sourceFiles.runtimeFixture)
foreach ($path in @($combatPath, $combatLibraryPath, $xpPath, $gcwPath,
    $combatActionsPath, $basePlayerPath, $profilesPath, $generatorPath,
    $runtimeFixturePath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.damage-authority.source.$([IO.Path]::GetFileName($path))"
}

$profiles = @(Import-SwgTab -Path $profilesPath)
$exact = @($profiles | Where-Object { -not ([string]$_.templateName).StartsWith("__family_") })
$families = @($profiles | Where-Object { ([string]$_.templateName).StartsWith("__family_") })
$profileHash = (Get-FileHash -LiteralPath $profilesPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Contract ($profiles.Count -eq [int]$contract.catalog.totalProfileCount -and
    $exact.Count -eq [int]$contract.catalog.exactProfileCount -and
    $families.Count -eq [int]$contract.catalog.familyProfileCount -and
    $profileHash -ceq [string]$contract.catalog.sha256) "p14.damage-authority.catalog.authenticated"

$unarmed = @($exact | Where-Object templateName -ceq "object/weapon/melee/unarmed/unarmed_default_player.iff")
$oneHand = @($families | Where-Object templateName -ceq "__family_onehandmelee")
$rifle = @($exact | Where-Object templateName -ceq "object/weapon/ranged/rifle/rifle_cdef.iff")
Assert-Contract ($unarmed.Count -eq 1 -and
    [string]$unarmed[0].damageSkill -ceq "unarmed_damage" -and
    [string]$unarmed[0].toughnessSkill -ceq "unarmed_toughness" -and
    $oneHand.Count -eq 1 -and
    [string]$oneHand[0].toughnessSkill -ceq "onehandmelee_toughness" -and
    $rifle.Count -eq 1 -and
    [string]$rifle[0].damageSkill -ceq "" -and
    [string]$rifle[0].toughnessSkill -ceq "") "p14.damage-authority.catalog.modifiers"

$generator = Get-Content -LiteralPath $generatorPath -Raw
Assert-Contract ($generator.Contains('expectedCommit = "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8"') -and
    $generator.Contains('DamageSkill') -and
    $generator.Contains('ToughnessSkill') -and
    $generator.Contains('damageModifiers') -and
    $generator.Contains('defenderToughnessModifiers')) "p14.damage-authority.generator.pinned-core3"

$combat = Get-Content -LiteralPath $combatPath -Raw
$combatLibrary = Get-Content -LiteralPath $combatLibraryPath -Raw
$xp = Get-Content -LiteralPath $xpPath -Raw
$gcw = Get-Content -LiteralPath $gcwPath -Raw
$combatActions = Get-Content -LiteralPath $combatActionsPath -Raw
$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$runtimeFixture = Get-Content -LiteralPath $runtimeFixturePath -Raw
$precuPrimaryStart = $combat.IndexOf(
    "public int getPrecuPrimaryAttackResult", [StringComparison]::Ordinal)
$precuPrimaryEnd = $combat.IndexOf(
    "public float getPrecuPrimaryHitChance", $precuPrimaryStart,
    [StringComparison]::Ordinal)
$precuPrimary = if ($precuPrimaryStart -ge 0 -and
    $precuPrimaryEnd -gt $precuPrimaryStart) {
    $combat.Substring($precuPrimaryStart,
        $precuPrimaryEnd - $precuPrimaryStart)
} else { "" }
Assert-Contract ($combat.Contains('public boolean isPrecuAuthoritativeAttack(') -and
    $combat.Contains('return getPrecuCore3RawDamage(') -and
    $combat.Contains('"damage.pipeline", "PRECU_CORE3"')) "p14.damage-authority.runtime.authoritative-route"
Assert-Contract ($combat.Contains('"ranged_damage_mitigation_"') -and
    $combat.Contains('"melee_damage_mitigation_"') -and
    $combat.Contains('"private_damage_multiplier"') -and
    $combat.Contains('"private_damage_divisor_intimidate"') -and
    $combat.Contains('"private_damage_susceptibility"') -and
    $combat.Contains('"jedi_toughness"') -and
    $combat.Contains('minDamage *= actionMultiplier;')) "p14.damage-authority.runtime.core3-envelope"
Assert-Contract ($combat.Contains('"HIT_NO_PROFILE"') -and
    $combat.Contains('return precuAuthoritativeAttack ?') -and
    $combat.Contains('HIT_RESULT_HIT : PRECU_SECONDARY_RESULT_FALLBACK')) "p14.damage-authority.runtime.no-authenticated-hit-fallback"
Assert-Contract ($combat.Contains('if (!precuAuthoritativeAttack)') -and
    $combat.Contains('"damage.ngeExpertiseApplied", 0') -and
    $combat.Contains('healing.applyLifeSiphonHeal(') -and
    $combat.Contains('doKillMeterUpdate(attacker, defender, hitData.damage);')) "p14.damage-authority.runtime.nge-modifiers-contained"
Assert-Contract ([int]$contract.expected.precuPrimaryCriticalOutcomes -eq 0 -and
    [bool]$contract.expected.ngeCriticalEffectsCompatibilityOnly -and
    -not $precuPrimary.Contains("HIT_RESULT_CRITICAL") -and
    $combat.Contains("if (!precuAuthoritativeAttack && hitData[i].critical)") -and
    ([regex]::Matches($combat, 'combat\.doCriticalHitEffect\(')).Count -eq 1) `
    "p14.damage-authority.runtime.nge-critical-effects-contained"
$killMeterUpdate = $combat.Substring(
    $combat.IndexOf("public void doKillMeterUpdate", [StringComparison]::Ordinal))
$killMeterCleanupStart = $combatLibrary.IndexOf(
    "public static void retirePostNgeKillMeterPlayerState",
    [StringComparison]::Ordinal)
$killMeterCleanupEnd = $combatLibrary.IndexOf(
    "public static boolean setKillMeter", $killMeterCleanupStart,
    [StringComparison]::Ordinal)
$killMeterCleanup = if ($killMeterCleanupStart -ge 0 -and
    $killMeterCleanupEnd -gt $killMeterCleanupStart) {
    $combatLibrary.Substring($killMeterCleanupStart,
        $killMeterCleanupEnd - $killMeterCleanupStart)
} else { "" }
Assert-Contract ([bool]$contract.expected.ngeKillMeterPlayerStateRetired -and
    $killMeterCleanup.Contains("if (!isPlayer(player))") -and
    $killMeterCleanup.Contains("incrementKillMeter(player, -current)") -and
    $killMeterCleanup.Contains('utils.removeScriptVarTree(player, "km")') -and
    $killMeterUpdate.Contains("boolean compatibleAttacker = !playerAttacker") -and
    $killMeterUpdate.Contains("boolean compatibleDefender = !playerDefender") -and
    -not ($xp + $gcw + $combatActions + $combat).Contains("incrementKillMeter(") -and
    $basePlayer.Contains("combat.retirePostNgeKillMeterPlayerState(self)")) `
    "p14.damage-authority.runtime.nge-kill-meter-player-state-retired"
Assert-Contract (-not $combat.Contains('minDamage = 5;') -and
    -not $combat.Contains('maxDamage = 10;')) "p14.damage-authority.runtime.uncertified-policy"
Assert-Contract ($runtimeFixture.Contains("PLAYER_OID = 44003778L") -and
    $runtimeFixture.Contains('ATTACK_COMMAND = "creatureMeleeAttack"') -and
    $runtimeFixture.Contains('action=armCombatDiagnostics') -and
    $runtimeFixture.Contains('action=diagnostics result=') -and
    $runtimeFixture.Contains('action=cleanup alreadyClean=true restored=true') -and
    $runtimeFixture.Contains('forceDestroy(object);')) `
    "p14.damage-authority.runtime-fixture-identity-bound-and-reversible"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) "p14.damage-authority.contract.status"

if ($Expectation -eq "Ready")
{
    $runtime = $contract.liveEvidence
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$runtime.result -ceq "passed" -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "p14.damage-authority.ready-evidence-complete"

    $fixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeFixturePath).
        Hash.ToLowerInvariant()
    Assert-Contract ($fixtureHash -ceq
        [string]$contract.buildEvidence.runtimeFixtureSourceSha256 -and
        [string]$contract.buildEvidence.runtimeFixtureJavaCompile -ceq "passed") `
        "p14.damage-authority.ready-fixture-build"

    $dsrcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "dsrc" })
    $srcPin = @($manifest.gitlinks | Where-Object { $_.name -ceq "src" })
    $checkedOutDsrc = (& git -C (Join-Path $source "dsrc") rev-parse HEAD).Trim()
    $dsrcExit = $LASTEXITCODE
    $checkedOutSrc = (& git -C (Join-Path $source "src") rev-parse HEAD).Trim()
    $srcExit = $LASTEXITCODE
    Assert-Contract ($dsrcExit -eq 0 -and $srcExit -eq 0 -and
        $dsrcPin.Count -eq 1 -and $srcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq
            [string]$contract.buildEvidence.directSourceCommit -and
        [string]$srcPin[0].commit -ceq
            [string]$contract.buildEvidence.nativeSourceCommit -and
        $checkedOutDsrc -ceq
            [string]$contract.buildEvidence.directSourceCommit -and
        $checkedOutSrc -ceq
            [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.damage-authority.ready-source-pins"

    Assert-Contract ([int]$runtime.actionCost.health -eq 0 -and
        [int]$runtime.actionCost.action -eq 0 -and
        [int]$runtime.actionCost.mind -eq 0 -and
        [string]$runtime.actionCost.result -ceq "passed") `
        "p14.damage-authority.ready-live-action-cost"
    Assert-Contract ([string]$runtime.damage.pipeline -ceq "PRECU_CORE3" -and
        [double]$runtime.damage.minimum -eq 525.0 -and
        [double]$runtime.damage.maximum -eq 687.5 -and
        [int]$runtime.damage.ngeExpertiseApplied -eq 0 -and
        [int]$runtime.damage.ngeKillMeterApplied -eq 0 -and
        [int]$runtime.damage.ngeNicheApplied -eq 0 -and
        [string]$runtime.damage.result -ceq "passed") `
        "p14.damage-authority.ready-live-core3-damage"

    $cadence = $runtime.cadence
    Assert-Contract ([int]$cadence.attackEvents -ge 3 -and
        [double]$cadence.assignedIntervalSeconds -eq 2.0 -and
        [double]$cadence.minimumObservedConsecutiveSeconds -ge 1.95 -and
        [int]$cadence.pairsBelow1_95Seconds -eq 0 -and
        [string]$cadence.result -ceq "passed") `
        "p14.damage-authority.ready-live-cadence"

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
        "p14.damage-authority.ready-live-environment-and-cleanup"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14Core3DamageAuthority)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "p14.damage-authority.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Publish 14 Core3 damage authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 Core3 damage authority passed."
