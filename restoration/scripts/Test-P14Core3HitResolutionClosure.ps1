[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3HitResolutionClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $base = if ([string]$property.Name -ceq "generator") { $restorationRoot } else { $source }
    $relative = [string]$property.Value
    if ([string]$property.Name -ceq "generator")
    {
        $relative = $relative.Substring("restoration/".Length)
    }
    $paths[[string]$property.Name] = Join-Path $base $relative
}
foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.hit-closure.source.$([IO.Path]::GetFileName($path))"
}

$profiles = @(Import-SwgTab -Path $paths.weaponProfiles)
$exact = @($profiles | Where-Object { -not ([string]$_.templateName).StartsWith("__family_") })
$families = @($profiles | Where-Object { ([string]$_.templateName).StartsWith("__family_") })
$unique = @($profiles | Group-Object templateName | Where-Object Count -ne 1)
$profileHash = (Get-FileHash -LiteralPath $paths.weaponProfiles -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Contract ($profiles.Count -eq [int]$contract.catalog.totalProfileCount -and
    $exact.Count -eq [int]$contract.catalog.exactProfileCount -and
    $families.Count -eq [int]$contract.catalog.familyProfileCount -and
    $unique.Count -eq 0) "p14.hit-closure.catalog.complete-and-unique"
Assert-Contract ($profileHash -ceq [string]$contract.catalog.sha256) "p14.hit-closure.catalog.authenticated-hash"

$generator = Get-Content -LiteralPath $paths.generator -Raw
Assert-Contract ($generator.Contains('expectedCommit = "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8"') -and
    $generator.Contains('if ($orderedRows.Count -ne 342)')) "p14.hit-closure.generator.pinned-core3"

$overrides = @(Import-SwgTab -Path $paths.combatOverrides)
$basicNames = @($contract.authenticatedBasicActions)
$basicRows = @($overrides | Where-Object { $basicNames -ccontains [string]$_.actionName })
$basicValid = $basicRows.Count -eq $basicNames.Count
foreach ($name in $basicNames)
{
    $rows = @($basicRows | Where-Object actionName -ceq $name)
    $basicValid = $basicValid -and $rows.Count -eq 1 -and
        [double]$rows[0].healthCostMultiplier -eq 0 -and
        [double]$rows[0].actionCostMultiplier -eq 0 -and
        [double]$rows[0].mindCostMultiplier -eq 0 -and
        [string]$rows[0].targetPool -ceq "RANDOM" -and
        [double]$rows[0].speedMultiplier -eq 1 -and
        [double]$rows[0].accuracyBonus -eq 0 -and
        [string]$rows[0].animationType -ceq "NONE"
}
Assert-Contract $basicValid "p14.hit-closure.basic-actions.authenticated-zero-cost"

$rifle = @($exact | Where-Object templateName -ceq "object/weapon/ranged/rifle/rifle_cdef.iff")
$unarmed = @($exact | Where-Object templateName -ceq "object/weapon/melee/unarmed/unarmed_default_player.iff")
$twoHand = @($families | Where-Object templateName -ceq "__family_twohandmelee")
Assert-Contract ($rifle.Count -eq 1 -and $rifle[0].accuracySkill -ceq "rifle_accuracy" -and
    $rifle[0].secondaryDefenseResult -ceq "BLOCK" -and
    $unarmed.Count -eq 1 -and $unarmed[0].secondaryDefenseResult -ceq "RANDOM" -and
    $twoHand.Count -eq 1 -and $twoHand[0].armorPiercing -ceq "2") "p14.hit-closure.catalog.representative-profiles"

$combat = Get-Content -LiteralPath $paths.combatBase -Raw
Assert-Contract ($combat.Contains('public int getPrecuWeaponProfileRow(weapon_data weaponData)') -and
    $combat.Contains('public int getPrecuWeaponFamilyProfileRow(int weaponType)') -and
    $combat.Contains('return getPrecuWeaponFamilyProfileRow(weaponData.weaponType);')) "p14.hit-closure.runtime.exact-then-family"
Assert-Contract ($combat.Contains('boolean profiledCreature =') -and
    $combat.Contains('hasObjVar(attackerData.id, "precu.combatProfile")') -and
    -not $combat.Contains('accuracyBonus <= 0')) "p14.hit-closure.runtime.profiled-zero-bonus"
Assert-Contract ($combat.Contains('String defenseSkill2 = dataTableGetString(PRECU_WEAPON_PROFILES, weaponRow, "defenseSkill2")') -and
    $combat.Contains('getPrecuRangedDefenseLocomotionModifier(defenderData.locomotion)') -and
    $combat.Contains('getPrecuMeleeDefenseLocomotionModifier(defenderData.locomotion)')) "p14.hit-closure.runtime.defense-and-posture"
Assert-Contract ($combat.Contains('defenderWeapon = getCurrentWeapon(defenderData.id);') -and
    -not $combat.Contains('FALLBACK_NO_WEAPON')) "p14.hit-closure.runtime.default-unarmed-defense"
Assert-Contract ($combat.Contains('jedi.isLightsaber(defenderWeapon) ||') -and
    $combat.Contains('isPrecuLightsaberWeaponType(getWeaponType(defenderWeapon))')) "p14.hit-closure.runtime.lightsaber-type-safe"
Assert-Contract ($combat.Contains('hasObjVar(attacker, "precu.combatProfile"))') -and
    $combat.Contains('combat.PRECU_TARGET_POOL_RANDOM')) "p14.hit-closure.runtime.profiled-random-pool"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) "p14.hit-closure.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 Core3 hit-resolution closure failed: $($failures -join ', ')"
}
Write-Host "Publish 14 Core3 hit-resolution closure passed."
