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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuCreatureAutoActionAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$serverGame = Join-Path $source "dsrc/sku.0/sys.server/compiled/game"
$sharedGame = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$combatPath = Join-Path $serverGame "script/ai/creature_combat.java"
$creaturePath = Join-Path $serverGame "datatables/mob/creatures.tab"
$profilePath = Join-Path $serverGame "datatables/ai/ai_combat_profiles.tab"
$overridePath = Join-Path $sharedGame "datatables/combat/precu_combat_overrides.tab"
$combatDataPath = Join-Path $sharedGame "datatables/combat/combat_data.tab"
foreach ($path in @($combatPath, $creaturePath, $profilePath, $overridePath, $combatDataPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.creature-auto-action.source.$([IO.Path]::GetFileName($path)).exists"
}

$combatSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $combatPath).Hash.ToLowerInvariant()
Assert-Contract ($combatSourceHash -ceq [string]$contract.buildEvidence.sourceSha256."ai/creature_combat.java") "p14.creature-auto-action.source.authenticated"
$combatSource = Get-Content -LiteralPath $combatPath -Raw
$attack = Get-SourceSlice $combatSource "public void attack(obj_id target)" "public int OnCreatureDamaged"
Assert-Contract ($attack.Contains('final boolean precuProfiledAttacker = hasObjVar(self, "precu.combatProfile");')) "p14.creature-auto-action.profile-boundary"
Assert-Contract ($attack.Contains('else if (pendingActionString != null && !precuProfiledAttacker)')) "p14.creature-auto-action.pending-nge-branch-retired"
Assert-Contract ($attack.Contains('if (precuProfiledAttacker)') -and
    $attack.Contains('removeObjVar(self, "ai.combat.pendingAction");') -and
    $attack.Contains('removeObjVar(self, "ai.combat.pendingActionTime");') -and
    $attack.Contains('currentActionString = DEFAULT_ATTACK;')) "p14.creature-auto-action.profiled-default-route"
Assert-Contract (($attack.Split(@('aiGetCombatAction(self)'), [System.StringSplitOptions]::None).Count - 1) -eq 1 -and
    $attack.IndexOf('if (precuProfiledAttacker)', [System.StringComparison]::Ordinal) -lt
        $attack.IndexOf('aiGetCombatAction(self)', [System.StringComparison]::Ordinal)) "p14.creature-auto-action.compatibility-selection-contained"
Assert-Contract ($attack.Contains('String forcedActionString = getStringObjVar(self, "ai.combat.forcedAction");') -and
    $attack.Contains('String oneShotActionString = getStringObjVar(self, "ai.combat.oneShotAction");') -and
    $attack.Contains('if (forcedActionString != null)') -and
    $attack.Contains('currentActionString = forcedActionString;')) "p14.creature-auto-action.encounter-actions-preserved"

$creatures = @(Import-SwgTab -Path $creaturePath)
$profiles = @(Import-SwgTab -Path $profilePath)
$overrides = @(Import-SwgTab -Path $overridePath)
$combatRows = @(Import-SwgTab -Path $combatDataPath)
$profileIds = @($creatures | ForEach-Object {
    @([string]$_.primary_weapon_specials, [string]$_.secondary_weapon_specials)
} | Where-Object { $_ -and $_ -cne "none" } | Sort-Object -Unique)
$profiledCreatures = @($creatures | Where-Object {
    (([string]$_.primary_weapon_specials) -and ([string]$_.primary_weapon_specials -cne "none")) -or
    (([string]$_.secondary_weapon_specials) -and ([string]$_.secondary_weapon_specials -cne "none"))
})
$usedProfiles = @($profiles | Where-Object { $profileIds -ccontains [string]$_.profile_id })
$actions = @($usedProfiles | ForEach-Object {
    $row = $_
    1..14 | ForEach-Object { [string]$row.("action$_") }
} | Where-Object { $_ } | Sort-Object -Unique)
$mappedActions = @($actions | Where-Object { $overrides.actionName -ccontains $_ })
$usedCombatRows = @($combatRows | Where-Object { $actions -ccontains [string]$_.actionName })
$hitTypes = @{}
foreach ($group in @($usedCombatRows | Group-Object hitType)) { $hitTypes[[string]$group.Name] = $group.Count }
Assert-Contract ($creatures.Count -eq [int]$contract.diagnosis.creatureRows -and
    $profiledCreatures.Count -eq [int]$contract.diagnosis.creaturesWithAutomaticProfiles -and
    $profileIds.Count -eq [int]$contract.diagnosis.usedAutomaticProfileIds) "p14.creature-auto-action.profile-inventory"
Assert-Contract ($actions.Count -eq [int]$contract.diagnosis.distinctAutomaticActions -and
    $mappedActions.Count -eq [int]$contract.diagnosis.automaticActionsInPrecuOverrides -and
    $usedCombatRows.Count -eq [int]$contract.diagnosis.combatRowsFound) "p14.creature-auto-action.action-inventory"
Assert-Contract ($hitTypes[""] -eq [int]$contract.diagnosis.combatHitTypes.blank -and
    $hitTypes["ATTACK"] -eq [int]$contract.diagnosis.combatHitTypes.ATTACK -and
    $hitTypes["DELAY_ATTACK"] -eq [int]$contract.diagnosis.combatHitTypes.DELAY_ATTACK -and
    $hitTypes["HEAL"] -eq [int]$contract.diagnosis.combatHitTypes.HEAL -and
    $hitTypes["NON_ATTACK"] -eq [int]$contract.diagnosis.combatHitTypes.NON_ATTACK) "p14.creature-auto-action.hit-type-inventory"

foreach ($evidence in @(
    @{ Path = $creaturePath; Hash = [string]$contract.continuityEvidence.creatureTableSha256; Name = "creatures" },
    @{ Path = $profilePath; Hash = [string]$contract.continuityEvidence.aiCombatProfilesSha256; Name = "profiles" },
    @{ Path = $overridePath; Hash = [string]$contract.continuityEvidence.precuCombatOverridesSha256; Name = "overrides" },
    @{ Path = $combatDataPath; Hash = [string]$contract.continuityEvidence.combatDataSha256; Name = "combat-data" }
))
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $evidence.Path).Hash.ToLowerInvariant() -ceq $evidence.Hash) "p14.creature-auto-action.$($evidence.Name).preserved"
}
foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path (Join-Path $serverGame "script") $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.creature-auto-action.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "p14.creature-auto-action.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) "p14.creature-auto-action.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256."ai/creature_combat.class" -cne "pending" -and
        [string]$contract.buildEvidence.fullJavaCompile -like "passed*") "p14.creature-auto-action.compiled-evidence"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) "p14.creature-auto-action.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) "p14.creature-auto-action.source-status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuCreatureAutoActionAuthority)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) "p14.creature-auto-action.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU creature automatic-action authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU creature automatic-action authority contract passed."
