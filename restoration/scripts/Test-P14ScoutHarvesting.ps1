[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    "contracts/p14-scout-harvest-native-admission.json") -Raw | ConvertFrom-Json
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

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$corpsePath = Join-Path $scriptRoot "library/corpse.java"
$aiCorpsePath = Join-Path $scriptRoot "corpse/ai_corpse.java"
$outdoorsmanPath = Join-Path $scriptRoot "player/skill/outdoorsman.java"
$droidHarvesterPath = Join-Path $scriptRoot "systems/crafting/droid/modules/harvest_module.java"
$skillsPath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$commandTablePath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$commandQueuePath = Join-Path $source `
    "src/engine/server/library/serverGame/src/shared/command/CommandQueue.cpp"
$runtimeProbePath = Join-Path $scriptRoot `
    "test/precu_scout_harvest_admission_runtime.java"

foreach ($path in @($corpsePath, $aiCorpsePath, $outdoorsmanPath, $droidHarvesterPath,
    $skillsPath, $commandTablePath, $commandQueuePath, $runtimeProbePath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.scout-harvest.source.$([IO.Path]::GetFileName($path))"
}

$corpse = Get-Content -LiteralPath $corpsePath -Raw
$aiCorpse = Get-Content -LiteralPath $aiCorpsePath -Raw
$outdoorsman = Get-Content -LiteralPath $outdoorsmanPath -Raw
$droidHarvester = Get-Content -LiteralPath $droidHarvesterPath -Raw
$commandQueue = Get-Content -LiteralPath $commandQueuePath -Raw
$runtimeProbe = Get-Content -LiteralPath $runtimeProbePath -Raw

function Get-TabRows
{
    param([string]$Path)
    $lines = @(Get-Content -LiteralPath $Path)
    $header = [regex]::Split($lines[0], "`t")
    $rows = @{}
    foreach ($line in $lines | Select-Object -Skip 2)
    {
        if ([string]::IsNullOrEmpty($line)) { continue }
        $fields = [regex]::Split($line, "`t")
        $row = @{}
        for ($i = 0; $i -lt $header.Count; $i++)
        {
            $row[$header[$i]] = if ($i -lt $fields.Count) { $fields[$i] } else { "" }
        }
        $rows[$fields[0]] = $row
    }
    return $rows
}

$skills = Get-TabRows -Path $skillsPath
$commands = Get-TabRows -Path $commandTablePath

Assert-Contract ($corpse.Contains('SKILL_NOVICE_SCOUT = "outdoors_scout_novice"')) `
    "p14.scout-harvest.exact-skill"
Assert-Contract ($corpse.Contains("public static boolean canPlayerHarvestCreature") -and
    $corpse.Contains("hasSkill(player, SKILL_NOVICE_SCOUT)")) `
    "p14.scout-harvest.shared-admission"
Assert-Contract ($corpse.Contains("if (!canPlayerHarvestCreature(player, true))") -and
    $corpse.Contains("public static boolean harvestCreatureCorpse")) `
    "p14.scout-harvest.extraction-fails-closed"
Assert-Contract ($aiCorpse.Contains("corpse.canPlayerHarvestCreature(player, false) && canHarvest") -and
    $aiCorpse.Contains("harvestMenuItem && !corpse.canPlayerHarvestCreature(player, true)")) `
    "p14.scout-harvest.menu-and-selection-gated"
Assert-Contract ($outdoorsman.Contains("!corpse.canPlayerHarvestCreature(self, true)")) `
    "p14.scout-harvest.command-gated"
Assert-Contract ($droidHarvester.Contains("corpse.canPlayerHarvestCreature(player, false)") -and
    ([regex]::Matches($droidHarvester, [regex]::Escape("!corpse.canPlayerHarvestCreature(player, true)")).Count -eq 2) -and
    $droidHarvester.Contains("!corpse.canPlayerHarvestCreature(master, false)")) `
    "p14.scout-harvest.droid-paths-gated"
Assert-Contract ($commandQueue.Contains('#include "sharedSkillSystem/SkillManager.h"') -and
    $commandQueue.Contains('#include "sharedSkillSystem/SkillObject.h"') -and
    $commandQueue.Contains('cs_precuNoviceScoutSkill = "outdoors_scout_novice"') -and
    $commandQueue.Contains('bool canHarvestPrecuCreatureResources(CreatureObject const & creature)') -and
    $commandQueue.Contains('creature.hasSkill(*noviceScout)')) `
    "p14.scout-harvest.native-owned-skill-helper"
$enqueueStart = $commandQueue.IndexOf("void CommandQueue::enqueue(", [StringComparison]::Ordinal)
$admission = $commandQueue.IndexOf('command.m_commandName == "harvestCorpse"', $enqueueStart, [StringComparison]::Ordinal)
$normalDispatch = $commandQueue.IndexOf("DEBUG_REPORT_LOG( cs_debug", $enqueueStart, [StringComparison]::Ordinal)
Assert-Contract ($enqueueStart -ge 0 -and $admission -gt $enqueueStart -and
    $normalDispatch -gt $admission -and
    $commandQueue.Contains('!canHarvestPrecuCreatureResources(*creatureOwner)') -and
    $commandQueue.Contains('LOG("PreCuScoutHarvest"')) `
    "p14.scout-harvest.native-gate-precedes-queue-dispatch"
Assert-Contract ($commands.ContainsKey("harvestCorpse") -and
    $commands["harvestCorpse"]["characterAbility"] -eq "harvestCorpse") `
    "p14.scout-harvest.native-command-requires-scout-ability"
Assert-Contract ($skills.ContainsKey("outdoors_scout_novice") -and
    $skills["outdoors_scout_novice"]["COMMANDS"].Trim('"').Split(',') -contains "harvestCorpse" -and
    $skills["outdoors_scout_novice"]["SKILL_MODS"].Trim('"').Split(',') -contains "creature_harvesting=15") `
    "p14.scout-harvest.novice-scout-grants-ability-and-mod"

$species = @("bothan", "human", "moncal", "rodian", "trandoshan", "twilek",
    "wookiee", "zabrak", "ithorian", "sullustan")
$speciesAreClean = $true
foreach ($name in $species)
{
    $rowName = "species_$name"
    $speciesAreClean = $speciesAreClean -and $skills.ContainsKey($rowName) -and
        $skills[$rowName]["SKILL_MODS"] -notmatch '(^|,)creature_harvesting(=|,|$)' -and
        $skills[$rowName]["COMMANDS"] -notmatch '(^|,)harvestCorpse(,|$)'
}
Assert-Contract $speciesAreClean "p14.scout-harvest.species-do-not-grant-harvesting"

$probeIsIdentityBound =
    $runtimeProbe.Contains("PLAYER_OID = 1433054682L") -and
    $runtimeProbe.Contains("PLAYER_STATION_ID = 1001") -and
    $runtimeProbe.Contains('NOVICE_SCOUT = "outdoors_scout_novice"') -and
    $runtimeProbe.Contains('HARVEST_COMMAND = "harvestCorpse"') -and
    $runtimeProbe.Contains("playerOid != PLAYER_OID") -and
    $runtimeProbe.Contains("getPlayerStationId(player) != PLAYER_STATION_ID")
Assert-Contract $probeIsIdentityBound `
    "p14.scout-harvest.runtime-probe-identity-bound"

$probeUsesProductionQueue =
    $runtimeProbe.Contains("boolean noviceScoutOwned = hasSkill(player, NOVICE_SCOUT)") -and
    $runtimeProbe.Contains("boolean commandOwned = hasCommand(player, HARVEST_COMMAND)") -and
    $runtimeProbe.Contains("getStringCrc(HARVEST_COMMAND.toLowerCase())") -and
    $runtimeProbe.Contains("obj_id.NULL_ID") -and
    $runtimeProbe.Contains('"meat"') -and
    $runtimeProbe.Contains("COMMAND_PRIORITY_DEFAULT") -and
    $runtimeProbe.Contains('" queued=" + queued')
Assert-Contract $probeUsesProductionQueue `
    "p14.scout-harvest.runtime-probe-production-queue"

$probeIsStateFree = $runtimeProbe.Contains("stateFree=true")
foreach ($forbidden in @("grantSkill(", "revokeSkill(", "createObject(",
    "destroyObject(", "setObjVar(", "removeObjVar("))
{
    $probeIsStateFree = $probeIsStateFree -and -not $runtimeProbe.Contains($forbidden)
}
Assert-Contract $probeIsStateFree `
    "p14.scout-harvest.runtime-probe-state-free"

if ($Expectation -eq "Ready")
{
    $runtime = $contract.runtimeEvidence
    $probe = $runtime.nativeAdmissionProbe
    Assert-Contract ($contract.status -ceq "ready" -and
        $runtime.result -ceq "passed" -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "p14.scout-harvest.ready-evidence-complete"

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
        $checkedOutDsrc -ceq [string]$contract.buildEvidence.directSourceGitlink -and
        $checkedOutSrc -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.scout-harvest.ready-source-pins"

    $sourceHashesMatch = $true
    foreach ($entry in $contract.sourceFiles.PSObject.Properties)
    {
        $path = Join-Path $source ([string]$entry.Value)
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $hashProperty = $contract.buildEvidence.sourceSha256.PSObject.Properties[$entry.Name]
        $sourceHashesMatch = $sourceHashesMatch -and $null -ne $hashProperty -and
            $actualHash -ceq [string]$hashProperty.Value
    }
    Assert-Contract $sourceHashesMatch `
        "p14.scout-harvest.ready-source-hashes"

    Assert-Contract ([bool]$runtime.clusterReadyForPlayers -and
        [bool]$runtime.liveProcessMappedBuiltBinary -and
        [int]$runtime.processCounts.PlanetServer -eq 15 -and
        [int]$runtime.processCounts.SwgGameServer -eq 15 -and
        [bool]$runtime.primaryClient.remainedOpenAndResponsive -and
        [bool]$runtime.nonScoutProofClient.authoritative -and
        [bool]$runtime.nonScoutProofClient.closedAfterProbe) `
        "p14.scout-harvest.ready-live-environment"

    Assert-Contract ([long]$probe.playerOid -eq 1433054682 -and
        [int]$probe.stationId -eq 1001 -and
        [bool]$probe.authoritative -and
        -not [bool]$probe.noviceScoutOwned -and
        -not [bool]$probe.commandOwned -and
        [bool]$probe.queueCommandReturned -and
        [string]$probe.command -ceq "harvestCorpse" -and
        [long]$probe.target -eq 0 -and
        [string]$probe.params -ceq "meat" -and
        [bool]$probe.stateFree -and
        [bool]$probe.rejectedAtNativeEnqueueBeforeTargetValidation -and
        [string]$probe.result -ceq "passed" -and
        [string]$probe.nativeLogLine -match
            '^20260810032022:SwgGameServer:[0-9]+:PreCuScoutHarvest:rejected owner=1433054682 command=harvestCorpse target=0$') `
        "p14.scout-harvest.ready-native-rejection"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14 Scout harvesting contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14 Scout harvesting contract passed."
