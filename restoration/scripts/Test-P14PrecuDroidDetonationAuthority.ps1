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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuDroidDetonationAuthority)
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

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { return "" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
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
        "p14.droid-detonation.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$bomb = Get-Content -LiteralPath $paths.droidBomb -Raw
$petMaster = Get-Content -LiteralPath $paths.petMaster -Raw
$detonate = Get-BracedSurface $bomb "public void detonateDroid"
$menuRequest = Get-BracedSurface $bomb "public int OnObjectMenuRequest"
$menuSelect = Get-BracedSurface $bomb "public int OnObjectMenuSelect"
$command = Get-BracedSurface $petMaster "public int cmdDetonateDroid"

Assert-Contract (-not $bomb.Contains("getLevel(") -and
    -not $bomb.Contains("level / 90.0f") -and
    -not $bomb.Contains("pet_lib.DETONATION_DROID_MIN_DAMAGE") -and
    -not $bomb.Contains("pet_lib.DETONATION_DROID_MAX_DAMAGE")) `
    "p14.droid-detonation.no-nge-victim-level-authority"
Assert-Contract ($bomb.Contains("PRECU_DETONATION_MIN_DAMAGE = 150") -and
    $bomb.Contains("PRECU_DETONATION_MAX_DAMAGE = 200") -and
    $bomb.Contains("PRECU_DETONATION_RADIUS = 17") -and
    $bomb.Contains("PRECU_PLAYER_DAMAGE_MULTIPLIER = 0.25f")) `
    "p14.droid-detonation.core3-constants"
Assert-Contract ($detonate.Contains('getIntObjVar(droid, "module_data.bomb_level")') -and
    $detonate.Contains('getIntObjVar(droid, "module_data.bomb_level_bonus")') -and
    $detonate.Contains("int min_dam = PRECU_DETONATION_MIN_DAMAGE * bomb_level") -and
    $detonate.Contains("int max_dam = PRECU_DETONATION_MAX_DAMAGE * bomb_level")) `
    "p14.droid-detonation.module-rating-authority"
Assert-Contract ($detonate.Contains("getAttackableTargetsInRadius(droid, PRECU_DETONATION_RADIUS, true)") -and
    -not $detonate.Contains("20 + (int)(0.3f * bomb_level)")) `
    "p14.droid-detonation.fixed-radius"
Assert-Contract ($detonate.Contains("int target_min_damage = min_dam") -and
    $detonate.Contains("int target_max_damage = max_dam") -and
    $detonate.Contains("target_min_damage * PRECU_PLAYER_DAMAGE_MULTIPLIER") -and
    $detonate.Contains("target_max_damage * PRECU_PLAYER_DAMAGE_MULTIPLIER") -and
    $detonate.Contains("rand(target_min_damage, target_max_damage)") -and
    $detonate.Contains("weaponData.minDamage = target_min_damage") -and
    $detonate.Contains("weaponData.maxDamage = target_max_damage")) `
    "p14.droid-detonation.independent-fixed-pvp-range"
Assert-Contract ($menuRequest.Contains('hasSkill(player, "combat_smuggler_novice")') -and
    $menuRequest.Contains('hasSkill(player, "combat_bountyhunter_novice")') -and
    $menuSelect.Contains('hasSkill(player, "combat_smuggler_novice")') -and
    $menuSelect.Contains('hasSkill(player, "combat_bountyhunter_novice")') -and
    $command.Contains('hasSkill(self, "combat_smuggler_novice")') -and
    $command.Contains('hasSkill(self, "combat_bountyhunter_novice")') -and
    -not $menuRequest.Contains("class_") -and -not $menuSelect.Contains("class_") -and
    -not $command.Contains("class_")) `
    "p14.droid-detonation.precu-admission"
Assert-Contract ($detonate.Contains("callable.getCallableCD(droid)") -and
    $detonate.Contains("combat.applyArmorProtection") -and
    $detonate.Contains("combat.assignDamageCredit") -and
    $detonate.Contains("xp.updateCombatXpList") -and
    $detonate.Contains("pvpAttackPerformed") -and
    $detonate.Contains("destroyObject(pet_control)")) `
    "p14.droid-detonation.lifecycle-preserved"

$moduleMaxima = @()
for ($index = 1; $index -le 5; ++$index)
{
    $text = Get-Content -LiteralPath $paths["detonationModule$index"] -Raw
    if ($text -match 'name = "crafting" "bomb_level"[^\r\n]*value = 1\.\.([0-9]+)')
    {
        $moduleMaxima += [int]$Matches[1]
    }
}
Assert-Contract ($moduleMaxima.Count -eq [int]$contract.expected.retainedDetonationSchematicTiers -and
    (($moduleMaxima -join ",") -ceq (($contract.authoredModuleRatingMaxima | ForEach-Object { [int]$_ }) -join ","))) `
    "p14.droid-detonation.retained-schematic-ratings"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.droid-detonation.$($property.Name).authenticated"
}
$continuity = [ordered]@{
    petMasterSha256 = $paths.petMaster
    petControlDeviceSha256 = $paths.petControlDevice
    droidDeedSha256 = $paths.droidDeed
    petLibrarySha256 = $paths.petLibrary
    detonationModule1Sha256 = $paths.detonationModule1
    detonationModule2Sha256 = $paths.detonationModule2
    detonationModule3Sha256 = $paths.detonationModule3
    detonationModule4Sha256 = $paths.detonationModule4
    detonationModule5Sha256 = $paths.detonationModule5
}
foreach ($name in $continuity.Keys)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $continuity[$name]).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.$name) "p14.droid-detonation.continuity.$name"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.droid-detonation.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.droid-detonation.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.droid-detonation.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.droid-detonation.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.droid-detonation.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU droid detonation authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU droid detonation authority contract passed."
