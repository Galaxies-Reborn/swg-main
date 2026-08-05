[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuBattlefieldVehicleArmorAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$paths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $source ([string]$property.Value)
}
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedBlock([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.battlefield-vehicle-armor.source.$([IO.Path]::GetFileName($path)).exists"
}

$vehicleScript = Get-Content -LiteralPath $paths.vehicleScript -Raw
$armor = Get-Content -LiteralPath $paths.armor -Raw
$onAttach = Get-BracedBlock $vehicleScript `
    "public int OnAttach(obj_id self)"
$setArmor = Get-BracedBlock $vehicleScript `
    "public void setArmor(obj_id target, int amount)"
$recalculateMob = Get-BracedBlock $armor `
    "public static void recalculateArmorForMob(obj_id mob)"

Assert-Contract ($onAttach.Contains('dataTableGetInt(TABLE, getVehicleType(self), "default_armor")') -and
    $onAttach.Contains("setArmor(self,")) `
    "p14.battlefield-vehicle-armor.production-initialization"
Assert-Contract ($setArmor.Contains('setObjVar(target, armor.OBJVAR_ARMOR_BASE + "." + armor.OBJVAR_GENERAL_PROTECTION, amount)') -and
    $setArmor.Contains("armor.recalculateArmorForMob(target);") -and
    -not $setArmor.Contains("expertise_") -and
    -not $setArmor.Contains("SkillStatisticModifier")) `
    "p14.battlefield-vehicle-armor.authored-protection-route"
Assert-Contract ($recalculateMob.Contains("SCRIPTVAR_CACHED_GENERAL_PROTECTION") -and
    $recalculateMob.Contains('getFloatObjVar(mob, OBJVAR_ARMOR_BASE + "." + OBJVAR_GENERAL_PROTECTION)') -and
    -not $recalculateMob.Contains("SkillStatisticModifier")) `
    "p14.battlefield-vehicle-armor.precu-mob-consumer"
Assert-Contract (-not $vehicleScript.Contains("expertise_innate_protection_all") -and
    ([regex]::Matches($setArmor, "setObjVar\(")).Count -eq
        [int]$contract.expected.authoredProtectionObjvarWrites -and
    ([regex]::Matches($setArmor, "armor\.recalculateArmorForMob\(")).Count -eq
        [int]$contract.expected.mobArmorRecalculations) `
    "p14.battlefield-vehicle-armor.nge-authority-retired"

$vehicleRows = @(Import-Csv -LiteralPath $paths.vehicleTable -Delimiter "`t" |
    Where-Object { [string]$_.vehicle_name -in @("snowspeeder.iff", "hoth_at_st.iff") })
$snowspeeder = @($vehicleRows | Where-Object { [string]$_.vehicle_name -ceq "snowspeeder.iff" })
$hothAtst = @($vehicleRows | Where-Object { [string]$_.vehicle_name -ceq "hoth_at_st.iff" })
Assert-Contract ($vehicleRows.Count -eq [int]$contract.expected.vehicleDataRows -and
    $snowspeeder.Count -eq 1 -and $hothAtst.Count -eq 1 -and
    [int]$snowspeeder[0].default_armor -eq [int]$contract.expected.snowspeederAuthoredArmor -and
    [int]$hothAtst[0].default_armor -eq [int]$contract.expected.hothAtstAuthoredArmor -and
    [string]$snowspeeder[0].allowed_zones -ceq "adventure2" -and
    [string]$hothAtst[0].allowed_zones -ceq "adventure2") `
    "p14.battlefield-vehicle-armor.authored-vehicle-table"

$echoRows = @(Get-Content -LiteralPath $paths.echoBaseSpawns |
    Where-Object { $_ -match "systems\.vehicle_system\.battlefield_vehicle" })
$snowRows = @($echoRows | Where-Object { $_ -match '^object/mobile/vehicle/snowspeeder[.]iff\t' })
$atstRows = @($echoRows | Where-Object { $_ -match '^object/mobile/vehicle/hoth_at_st[.]iff\t' })
Assert-Contract ($echoRows.Count -eq [int]$contract.expected.echoBaseVehicleSpawns -and
    $snowRows.Count -eq [int]$contract.expected.echoBaseSnowspeederSpawns -and
    $atstRows.Count -eq [int]$contract.expected.echoBaseHothAtstSpawns) `
    "p14.battlefield-vehicle-armor.echo-base-reachability"

$vehicleMineScript = Get-Content -LiteralPath $paths.vehicleMineScript -Raw
Assert-Contract (-not $vehicleMineScript.Contains("strength_modified") -and
    -not $vehicleMineScript.Contains("addSkillModModifier")) `
    "p14.battlefield-vehicle-armor.mine-nge-primary-writer-retired"
Assert-Contract (([regex]::Matches($vehicleMineScript,
            'createTriggerVolume\("hoth_vehicle_mine", 10[.]0f, true\)')).Count -eq 1 -and
    ([regex]::Matches($vehicleMineScript,
            'queueCommand\(self, \(-1220440242\),')).Count -eq
        [int]$contract.expected.vehicleMineQueueSites -and
    ([regex]::Matches($vehicleMineScript,
            'removeTriggerVolume\("hoth_vehicle_mine"\)')).Count -eq 2 -and
    $vehicleMineScript.Contains("stealth.checkForAndMakeVisible(breacher);") -and
    [int]$contract.expected.vehicleMineTriggerRadius -eq 10 -and
    [int]$contract.expected.vehicleMineQueuedCommandCrc -eq -1220440242) `
    "p14.battlefield-vehicle-armor.mine-lifecycle-preserved"

$echoBaseText = Get-Content -LiteralPath $paths.echoBaseSpawns
$mineSpawnRows = @($echoBaseText |
    Where-Object { $_ -match '^heroic_echo_vehicle_mine\t' })
$mineCleanupRows = @($echoBaseText |
    Where-Object { $_ -match '^deleteSpawn:vehicle_mine_[0-9]{2}:combat_explosion_lair_large[.]cef\t' })
Assert-Contract ($mineSpawnRows.Count -eq [int]$contract.expected.echoBaseVehicleMineSpawns -and
    $mineCleanupRows.Count -eq [int]$contract.expected.echoBaseVehicleMineCleanupRows) `
    "p14.battlefield-vehicle-armor.mine-spawn-cleanup-reachability"

$creatureRows = @(Import-Csv -LiteralPath $paths.creatures -Delimiter "`t" |
    Where-Object { [string]$_.creatureName -ceq "heroic_echo_vehicle_mine" })
Assert-Contract ($creatureRows.Count -eq 1 -and
    [int]$creatureRows[0].BaseLevel -eq 91 -and
    [string]$creatureRows[0].template -ceq "vehicle_mine.iff" -and
    [string]$creatureRows[0].scripts -ceq "theme_park.heroic.echo_base.vehicle_mine") `
    "p14.battlefield-vehicle-armor.mine-creature-binding"

$commandRows = @(Import-Csv -LiteralPath $paths.commandTable -Delimiter "`t" |
    Where-Object { [string]$_.commandName -ceq "hoth_sapper_detonate" })
Assert-Contract ($commandRows.Count -eq [int]$contract.expected.vehicleMineCommandRows -and
    [string]$commandRows[0].scriptHook -ceq "hoth_sapper_detonate" -and
    [string]$commandRows[0].commandGroup -ceq "combat_ranged" -and
    [string]$commandRows[0].target -ceq "other" -and
    [string]$commandRows[0].targetType -ceq "all") `
    "p14.battlefield-vehicle-armor.mine-command-binding"

$combatRows = @(Import-Csv -LiteralPath $paths.combatData -Delimiter "`t" |
    Where-Object { [string]$_.actionName -ceq "hoth_sapper_detonate" })
Assert-Contract ($combatRows.Count -eq [int]$contract.expected.vehicleMineCombatRows -and
    [string]$combatRows[0].attackType -ceq "AREA" -and
    [int]$combatRows[0].coneLength -eq [int]$contract.expected.vehicleMineTriggerRadius -and
    [int]$combatRows[0].addedDamage -eq [int]$contract.expected.vehicleMineAuthoredAddedDamage -and
    [string]$combatRows[0].weaponType -ceq "RIFLE" -and
    [string]$combatRows[0].weaponCategory -ceq "RANGED_WEAPON" -and
    [string]$combatRows[0].damageType -ceq "ENERGY" -and
    [string]$combatRows[0].specialLine -ceq "sapper") `
    "p14.battlefield-vehicle-armor.mine-combat-data-preserved"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.battlefield-vehicle-armor.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.battlefield-vehicle-armor.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.battlefield-vehicle-armor.direct-source-pin"
    $compiledHashes = $contract.buildEvidence.compiledClassSha256
    Assert-Contract ($null -ne $compiledHashes -and
        [string]$compiledHashes.vehicleScript -match '^[a-f0-9]{64}$' -and
        [string]$compiledHashes.vehicleMineScript -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.battlefield-vehicle-armor.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.battlefield-vehicle-armor.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.battlefield-vehicle-armor.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU battlefield vehicle armor authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU battlefield vehicle armor authority contract passed."
