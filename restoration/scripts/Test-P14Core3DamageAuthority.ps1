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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3DamageAuthority)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

$combatPath = Join-Path $source ([string]$contract.sourceFiles.combatBase)
$profilesPath = Join-Path $source ([string]$contract.sourceFiles.weaponProfiles)
$generatorPath = Join-Path $restorationRoot (([string]$contract.sourceFiles.generator).Substring("restoration/".Length))
foreach ($path in @($combatPath, $profilesPath, $generatorPath))
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
Assert-Contract (-not $combat.Contains('minDamage = 5;') -and
    -not $combat.Contains('maxDamage = 10;')) "p14.damage-authority.runtime.uncertified-policy"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) "p14.damage-authority.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 Core3 damage authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 Core3 damage authority passed."
