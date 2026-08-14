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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3CreatureCombatProfiles)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param([bool]$Condition, [string]$Name)
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

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $base = if ([string]$property.Name -in @("overlay", "generator")) { $restorationRoot } else { $source }
    $paths[[string]$property.Name] = Join-Path $base ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.creature-profile.source.$([IO.Path]::GetFileName($path))"
}

$rows = @(Import-SwgTab -Path $paths.profileTable)
$fallbacks = @($rows | Where-Object { [string]$_.creatureName -like "__level_*" })
$exact = @($rows | Where-Object {
    [string]$_.creatureName -notlike "__level_*" -and
    [string]$_.creatureName -ceq [string]$_.sourceKey })
$aliases = @($rows | Where-Object {
    [string]$_.creatureName -notlike "__level_*" -and
    [string]$_.creatureName -cne [string]$_.sourceKey })
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths.profileTable).Hash.ToLowerInvariant()

Write-Host "Publish 14.1 Core3 creature-combat profile checks:"
Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) "p14.creature-profile.status"
Assert-Contract ([string]$contract.semanticReference.pinnedCommit -ceq "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8") "p14.creature-profile.core3-pin"
Assert-Contract ($rows.Count -eq 4205 -and $exact.Count -eq 3622 -and $aliases.Count -eq 83 -and $fallbacks.Count -eq 500) "p14.creature-profile.cardinality"
Assert-Contract (($rows.creatureName | Sort-Object -Unique).Count -eq $rows.Count) "p14.creature-profile.unique-keys"
Assert-Contract ($hash -ceq [string]$contract.semanticReference.tableSha256) "p14.creature-profile.table-hash"

foreach ($expected in $contract.representativeProfiles.psobject.Properties)
{
    $row = @($rows | Where-Object { [string]$_.creatureName -ceq [string]$expected.Name })
    $matches = $row.Count -eq 1
    if ($matches)
    {
        foreach ($field in $expected.Value.psobject.Properties)
        {
            if ([string]$row[0].($field.Name) -cne [string]$field.Value)
            {
                $matches = $false
                break
            }
        }
    }
    Assert-Contract $matches "p14.creature-profile.representative.$($expected.Name)"
}

$create = Get-Content -LiteralPath $paths.createLibrary -Raw
$combat = Get-Content -LiteralPath $paths.combatLibrary -Raw
$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$corpse = Get-Content -LiteralPath $paths.corpseLibrary -Raw
$loot = Get-Content -LiteralPath $paths.lootLibrary -Raw
$generator = Get-Content -LiteralPath $paths.generator -Raw
$runtimeFixture = Get-Content -LiteralPath $paths.runtimeFixture -Raw
$overlayHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths.overlay).Hash.ToLowerInvariant()

Assert-Contract ($generator.Contains("6ea64f60ef33b89121c2a8d188b93f4bc6f158e8") -and
    $generator.Contains("Expected 3622 unique complete Core3 creature profiles") -and
    $generator.Contains('function Read-ResistFields') -and
    $generator.Contains('function Convert-Core3ResistForMitigation') -and
    $generator.Contains('$Value -gt 100.0') -and
    $generator.Contains('$level -le 500')) "p14.creature-profile.generator-pinned"
$missingArmorColumns = @(@(
    "armor",
    "resistKinetic",
    "resistEnergy",
    "resistBlast",
    "resistHeat",
    "resistCold",
    "resistElectric",
    "resistAcid",
    "resistStun",
    "resistLightsaber") | Where-Object {
        -not ($rows[0].psobject.Properties.Name -contains $_)
    })
Assert-Contract ($missingArmorColumns.Count -eq 0) "p14.creature-profile.armor-columns"
Assert-Contract ($create.Contains('PRECU_CREATURE_COMBAT_PROFILE_TABLE = "datatables/mob/precu_creature_combat_profiles.iff"') -and
    $create.Contains('precuCombatProfile.getInt("damageMin")') -and
    $create.Contains('precuCombatProfile.getInt("baseHAM")') -and
    $create.Contains('precuCombatProfile.getFloat("chanceHit") * 100.0f') -and
    $create.Contains('setObjVar(creature, "precu.combatProfile"') -and
    $create.Contains('setObjVar(creature, "precu.armor.rating", precuCombatProfile.getInt("armor"))') -and
    $create.Contains('setObjVar(creature, "precu.armor.kinetic", precuCombatProfile.getInt("resistKinetic"))') -and
    $create.Contains('setObjVar(creature, "precu.armor.lightsaber", precuCombatProfile.getInt("resistLightsaber"))') -and
    $create.Contains('initializeArmor(creature, creatureDict, 0)')) "p14.creature-profile.factory-route"
Assert-Contract ($combat.Contains('applyPrecuCreatureArmorProtection(') -and
    $combat.Contains('getPrecuCreatureArmorResistance(') -and
    $combat.Contains('return rawResistance > 100 ? rawResistance - 100 : rawResistance;') -and
    $combat.Contains('if (resistance < 0)') -and
    $combat.Contains('if (damageString == null)') -and
    $combat.Contains('getPrecuArmorPiercingMultiplier(armorPiercing, armorRating)') -and
    $combatBase.Contains('else if (hasObjVar(defender, "precu.combatProfile"))') -and
    $combatBase.Contains('combat.applyPrecuCreatureArmorProtection(') -and
    $combatBase.Contains('combat.getPrecuCreatureArmorRating(defender)') -and
    $combatBase.Contains('combat.getPrecuCreatureArmorResistance(')) "p14.creature-profile.armor-route"
Assert-Contract ((-not $create.Contains('float damagePerSecond = dataTableGetFloat(STAT_BALANCE_TABLE')) -and
    (-not $create.Contains('int avgAttribHealth = dataTableGetInt(STAT_BALANCE_TABLE')) -and
    (-not $create.Contains('int avgAttribAction = dataTableGetInt(STAT_BALANCE_TABLE'))) "p14.creature-profile.nge-scaling-retired"
Assert-Contract ($corpse.Contains('Rejected creature resource extraction without Novice Scout') -and
    $corpse.Contains('!canPlayerHarvestCreature(harvestingPlayer, true)')) "p14.creature-profile.harvest-final-gate"
Assert-Contract ($loot.Contains('Rejected NGE creature-resource loot injection') -and
    (-not $loot.Contains('finalAmount += corpse.extractCorpseResource'))) "p14.creature-profile.resource-loot-retired"
Assert-Contract ($runtimeFixture.Contains("PLAYER_OID = 44003778L") -and
    $runtimeFixture.Contains("PLAYER_STATION_ID = 91001") -and
    $runtimeFixture.Contains('createFixtureCreature("kreetle"') -and
    $runtimeFixture.Contains('createFixtureCreature("rancor"') -and
    $runtimeFixture.Contains("combat.applyPrecuCreatureArmorProtection(") -and
    $runtimeFixture.Contains("corpse.getHarvestCorpseResources(") -and
    $runtimeFixture.Contains("corpse.canPlayerHarvestCreature(") -and
    $runtimeFixture.Contains("queueCommand(") -and
    $runtimeFixture.Contains("inventoryMutated=false skillStateMutated=false") -and
    $runtimeFixture.Contains("action=cleanup alreadyClean=true restored=true")) `
    "p14.creature-profile.runtime-fixture-reversible-production-routes"
Assert-Contract ($overlayHash -ceq [string]$contract.buildEvidence.overlaySha256 -and
    (Get-Item -LiteralPath $paths.overlay).Length -eq [int64]$contract.buildEvidence.overlayBytes) "p14.creature-profile.overlay-evidence"

if ($Expectation -eq "Ready")
{
    $runtime = $contract.liveEvidence
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$runtime.result -ceq "passed" -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "p14.creature-profile.ready-evidence-complete"

    $fixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths.runtimeFixture).
        Hash.ToLowerInvariant()
    Assert-Contract ($fixtureHash -ceq
        [string]$contract.buildEvidence.runtimeFixtureSourceSha256 -and
        [string]$contract.buildEvidence.runtimeFixtureJavaCompile -ceq "passed") `
        "p14.creature-profile.ready-fixture-build"

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
        "p14.creature-profile.ready-source-pins"

    $kreetle = $runtime.profileInitialization.kreetle
    $rancor = $runtime.profileInitialization.rancor
    Assert-Contract ([string]$runtime.profileInitialization.result -ceq "passed" -and
        [string]$kreetle.profile -ceq "kreetle" -and
        [int]$kreetle.level -eq 3 -and [int]$kreetle.difficulty -eq 3 -and
        [int]$kreetle.damageMin -eq 35 -and [int]$kreetle.damageMax -eq 45 -and
        [double]$kreetle.speed -eq 2.0 -and [int]$kreetle.xp -eq 45 -and
        [int]$kreetle.accuracy -eq 23 -and
        [int]$kreetle.health -ge [int]$kreetle.hamMinimum -and
        [int]$kreetle.health -le [int]$kreetle.hamMaximum -and
        [int]$kreetle.action -ge [int]$kreetle.hamMinimum -and
        [int]$kreetle.action -le [int]$kreetle.hamMaximum -and
        [int]$kreetle.mind -ge [int]$kreetle.hamMinimum -and
        [int]$kreetle.mind -le [int]$kreetle.hamMaximum -and
        [int]$kreetle.armor -eq 0 -and [int]$kreetle.kinetic -eq 0 -and
        [int]$kreetle.stun -eq -1 -and
        [string]$rancor.profile -ceq "rancor" -and
        [int]$rancor.level -eq 50 -and [int]$rancor.difficulty -eq 50 -and
        [int]$rancor.damageMin -eq 420 -and [int]$rancor.damageMax -eq 550 -and
        [double]$rancor.speed -eq 2.0 -and [int]$rancor.xp -eq 4916 -and
        [int]$rancor.accuracy -eq 50 -and
        [int]$rancor.health -ge [int]$rancor.hamMinimum -and
        [int]$rancor.health -le [int]$rancor.hamMaximum -and
        [int]$rancor.action -ge [int]$rancor.hamMinimum -and
        [int]$rancor.action -le [int]$rancor.hamMaximum -and
        [int]$rancor.mind -ge [int]$rancor.hamMinimum -and
        [int]$rancor.mind -le [int]$rancor.hamMaximum -and
        [int]$rancor.armor -eq 1 -and [int]$rancor.kineticRaw -eq 130 -and
        [int]$rancor.blastRaw -eq -1) `
        "p14.creature-profile.ready-live-profile-initialization"

    $armorRuntime = $runtime.armorResolution
    Assert-Contract ([string]$armorRuntime.result -ceq "passed" -and
        [int]$armorRuntime.rawDamage -eq 1000 -and
        [int]$armorRuntime.armorPiercing -eq 0 -and
        [int]$armorRuntime.kreetleKineticFinal -eq 1000 -and
        [int]$armorRuntime.kreetleStunFinal -eq 1000 -and
        [int]$armorRuntime.rancorKineticFinal -eq 350 -and
        [int]$armorRuntime.rancorBlastFinal -eq 1000 -and
        [int]$armorRuntime.specialProtectionDecoded -eq 30 -and
        [bool]$armorRuntime.vulnerabilityBypassedRatingAndResistance -and
        [string]$armorRuntime.productionResolver -ceq
            "combat.applyPrecuCreatureArmorProtection") `
        "p14.creature-profile.ready-live-armor-resolution"

    $nonScout = $runtime.nonScoutHarvestAdmission
    $scout = $runtime.scoutHarvestAdmission
    Assert-Contract (-not [bool]$nonScout.noviceScoutOwned -and
        [bool]$nonScout.rejectedAtNativeEnqueue -and
        [bool]$nonScout.stateFree -and
        [string]$nonScout.result -ceq "passed" -and
        [string]$nonScout.nativeLogLine -match
            '^20260810032022:SwgGameServer:[0-9]+:PreCuScoutHarvest:rejected owner=1433054682 command=harvestCorpse target=0$' -and
        [bool]$scout.noviceScoutOwned -and [bool]$scout.commandOwned -and
        [string]$scout.family -ceq "kreetle" -and
        [string]$scout.resourceClass -ceq "meat_insect" -and
        [bool]$scout.familyResolved -and [bool]$scout.libraryAdmitted -and
        [bool]$scout.queueCommandReturned -and
        -not [bool]$scout.nativeRejectionObserved -and
        -not [bool]$scout.inventoryMutated -and
        -not [bool]$scout.skillStateMutated -and
        [string]$scout.result -ceq "passed") `
        "p14.creature-profile.ready-live-scout-harvest-admission"

    $playerCadence = $runtime.playerCadence
    $aiCadence = $runtime.aiCadence
    Assert-Contract ([bool]$playerCadence.playerControlled -and
        [int]$playerCadence.attackEvents -ge 2 -and
        [int]$playerCadence.pairsBelowAssignedInterval -eq 0 -and
        [double]$playerCadence.minimumObservedConsecutiveSeconds -ge
            [double]$playerCadence.assignedIntervalSeconds -and
        [string]$playerCadence.result -ceq "passed" -and
        -not [bool]$aiCadence.playerControlled -and
        [double]$aiCadence.assignedIntervalSeconds -eq 2.0 -and
        [int]$aiCadence.attackEvents -ge 3 -and
        [int]$aiCadence.pairsBelow1_95Seconds -eq 0 -and
        [double]$aiCadence.minimumObservedConsecutiveSeconds -ge 1.95 -and
        [string]$aiCadence.result -ceq "passed") `
        "p14.creature-profile.ready-live-cadence"

    Assert-Contract ([bool]$runtime.fixtureCleanup.firstCleanupRestored -and
        [bool]$runtime.fixtureCleanup.secondCleanupAlreadyClean -and
        [int]$runtime.fixtureCleanup.delayedErrorCount -eq 0 -and
        -not [bool]$runtime.fixtureCleanup.playerStateMutated -and
        [bool]$runtime.serverHealthy -and [bool]$runtime.clusterReadyForPlayers -and
        [bool]$runtime.sourceAndBuildVolumeMatch -and
        [bool]$runtime.liveProcessMappedBuiltBinary -and
        [int]$runtime.processCounts.PlanetServer -eq 15 -and
        [int]$runtime.processCounts.SwgGameServer -eq 15 -and
        [bool]$runtime.primaryClient.remainedOpenAndResponsive) `
        "p14.creature-profile.ready-live-environment-and-cleanup"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14Core3CreatureCombatProfiles)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "p14.creature-profile.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Core3 creature-combat profile contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14.1 Core3 creature-combat profile contract passed."
