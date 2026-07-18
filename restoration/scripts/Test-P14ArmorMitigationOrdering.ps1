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
            [string]$manifest.contracts.p14ArmorMitigationOrdering
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
        throw "Required armor-mitigation source is missing: $path"
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

function Get-TableRows
{
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $rows = @()
    foreach ($line in @($lines | Select-Object -Skip 2))
    {
        $values = $line -split "`t", -1
        $fields = @{}
        for ($index = 0; $index -lt $header.Count; ++$index)
        {
            $fields[$header[$index]] =
                if ($index -lt $values.Count) { $values[$index] } else { "" }
        }
        $rows += [pscustomobject]@{ Fields = $fields }
    }
    return @($rows)
}

$combat = Get-Content -LiteralPath $paths.combatLibrary -Raw
$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$legacyCombat = Get-Content -LiteralPath $paths.legacyCombatBase -Raw
$fixture = Get-Content -LiteralPath $paths.fixture -Raw
$profileRows = @(Get-TableRows -Path $paths.weaponProfiles)

Write-Host "Publish 14.1 armor/mitigation ordering checks:"
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [double]$contract.semanticReference.conditionWearRatio -eq 0.2 -and
    [int]$contract.semanticReference.cdefArmorPiercing -eq 0 -and
    (@($contract.semanticReference.playerLayerOrder) -join ",") -ceq
        "personal shield generator,hit-location armor piece," +
        "food mitigate_damage,target HAM pool,wound roll") `
    -Name "p14.armor.core3.pinned-order-and-ratios"

Assert-Contract -Condition (
    $combat.Contains(
        "public static int selectPrecuHitLocationForPool(") -and
    $combat -match
        "HIT_LOCATION_BODY,\s+HIT_LOCATION_BODY" -and
    $combat.Contains("HIT_LOCATION_L_LEG") -and
    $combat.Contains("return HIT_LOCATION_HEAD;")) `
    -Name "p14.armor.runtime.pool-aligned-hit-locations"

Assert-Contract -Condition (
    $combat.Contains("obj_id psg = getPsgArmor(defender);") -and
    $combat.IndexOf("obj_id psg = getPsgArmor(defender);") -lt
        $combat.IndexOf(
            "obj_id armorPiece = getArmorPieceHit(defender, hitData.hitLocation);") -and
    $combat.Contains("Math.pow(1.25f, difference)") -and
    $combat.Contains("Math.pow(0.50f, difference)") -and
    $combat.Contains("incomingDamage * 0.20f")) `
    -Name "p14.armor.runtime.psg-piece-rating-and-condition-order"

$armorCallIndex = $combatBase.IndexOf("combat.applyPrecuArmorProtection(")
$foodCallIndex = $combatBase.IndexOf(
    "combat.applyPrecuFoodMitigation(",
    [Math]::Max(0, $armorCallIndex)
)
$poolDamageIndex = $combatBase.IndexOf(
    "doDamageToPool(",
    [Math]::Max(0, $foodCallIndex)
)
Assert-Contract -Condition (
    $legacyCombat.Contains('"food.mitigate_damage.eff"') -and
    $legacyCombat.Contains('"food.mitigate_damage.dur"') -and
    $combat.Contains(
        'getEnhancedSkillStatisticModifier(defender, "mitigate_damage")') -and
    $combat.Contains('utils.hasScriptVar(defender, "food.mitigate_damage.eff")') -and
    $armorCallIndex -ge 0 -and
    $armorCallIndex -lt $foodCallIndex -and
    $foodCallIndex -lt $poolDamageIndex) `
    -Name "p14.armor.runtime.food-after-armor-before-pool-damage"

$profilesMatch = $profileRows.Count -eq 4
foreach ($row in $profileRows)
{
    $template = [string]$row.Fields["templateName"]
    $expected = $contract.weaponProfiles.psobject.Properties |
        Where-Object { $_.Name -ceq $template } |
        Select-Object -First 1
    $profilesMatch = $profilesMatch -and
        $null -ne $expected -and
        [int]$row.Fields["armorPiercing"] -eq [int]$expected.Value
}
Assert-Contract -Condition $profilesMatch `
    -Name "p14.armor.table.exact-opt-in-armor-piercing-profiles"

Assert-Contract -Condition (
    $combatBase.Contains("if (actionData.precuTargetPool >= 0)") -and
    $combatBase.Contains(
        "combat.selectPrecuHitLocationForPool(actionData.precuTargetPool)") -and
    $combatBase -match
        "else\s*\{\s*hitData\.blockedDamage \+= combat\.applyArmorProtection\(" -and
    [bool]$contract.runtimeContract.defaultNgePathUnchanged) `
    -Name "p14.armor.runtime.authenticated-opt-in-and-nge-fallback"

Assert-Contract -Condition (
    $fixture.Contains("ATTACKER_OID = 44003778L") -and
    $fixture.Contains("ATTACKER_STATION_ID = 91001") -and
    $fixture.Contains("DEFENDER_OID = 39008597L") -and
    $fixture.Contains("DEFENDER_STATION_ID = 1001") -and
    $fixture -match
        "armor\.setAbsoluteArmorData\(\s*fixtureArmor,\s*AL_basic,\s*" +
        "AC_battle,\s*2000,\s*1000\)" -and
    $fixture.Contains("expectedPostArmorDamage=400 expectedFinalDamage=300") -and
    $fixture.Contains('"item.armor.new_armor"') -and
    $fixture.Contains("detachScript(fixtureArmor, ARMOR_TRANSFER_SCRIPT)") -and
    $fixture.Contains("attachScript(fixtureArmor, ARMOR_TRANSFER_SCRIPT)") -and
    $fixture.Contains("destroyObject(fixtureArmor)") -and
    $fixture.Contains("equipOverride(originalHat, defender)") -and
    $fixture.Contains("removeObjVar(attacker, ROOT)") -and
    $fixture.Contains("removeObjVar(defender, ROOT)")) `
    -Name "p14.armor.fixture.identity-bound-real-armor-and-reversible-cleanup"

Assert-Contract -Condition (
    [string]$contract.buildEvidence.result -ceq "passed" -and
    [string]$contract.buildEvidence.sourceCommit -ceq "cd54de43e" -and
    [string]$contract.buildEvidence.patchSha256 -ceq
        "502aa72ebf0225ec8bf946fff820e80335eec7973fbcee59f57c1f264636e356" -and
    [string]$contract.buildEvidence.compiledSha256.
        "precu_armor_mitigation_fixture.class" -ceq
        "4e2817ecdeac96b41f269bf861310e33156c08540372cdf85426cd4cfb3c81d0") `
    -Name "p14.armor.build.clean-java-and-table-evidence"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 29 -and
        [bool]$contract.publicationBoundary.productionGameplayCodeChanged -and
        -not [bool]$contract.publicationBoundary.clientToolsChanged -and
        -not [bool]$contract.publicationBoundary.clientAssetsChanged) `
        -Name "p14.armor.status.ready-server-only-production-repair"
    Assert-Contract -Condition (
        [int]$live.probe.rawDamage -eq 1000 -and
        [int]$live.probe.hitLocation -eq 1 -and
        [int]$live.probe.armorPiercing -eq 0 -and
        [int]$live.probe.armorRating -eq 1 -and
        [double]$live.probe.protection -eq 0.2 -and
        [int]$live.probe.postArmorDamage -eq 400 -and
        [int]$live.probe.finalDamage -eq 300 -and
        [int]$live.probe.conditionDelta -eq 200 -and
        [int]$live.probe.foodDurationDelta -eq 1) `
        -Name "p14.armor.live.deterministic-production-helper-probe"
    Assert-Contract -Condition (
        [int]$live.headShot.hitLocation -eq 1 -and
        [int]$live.headShot.armorPiercing -eq 0 -and
        [int]$live.headShot.armorRating -eq 1 -and
        [double]$live.headShot.protection -eq 0.2 -and
        [int]$live.headShot.postArmorDamage -eq
            [int]$live.headShot.expectedPostArmorDamage -and
        [int]$live.headShot.finalDamage -eq
            [int]$live.headShot.expectedFinalDamage -and
        [int]$live.headShot.mindDelta -eq [int]$live.headShot.finalDamage) `
        -Name "p14.armor.live.off-focus-headshot-ordering-and-pool-delta"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.armor.live.cleanup-and-isolated-container-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 armor contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 armor/mitigation ordering contract passed."
