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
            [string]$manifest.contracts.p14RevivePlayerCommand
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
        throw "Required materialized Revive Player source is missing: $path"
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

function Get-TableRow
{
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $matches = @(
        $lines |
            Select-Object -Skip 2 |
            Where-Object {
                (($_ -split "`t", -1)[0]) -ceq $Key
            })
    return [pscustomobject]@{
        Header = $header
        Matches = $matches
        Values = if ($matches.Count -eq 1)
        {
            $matches[0] -split "`t", -1
        }
        else
        {
            @()
        }
    }
}

$healing = Get-Content -LiteralPath $paths.healingLibrary -Raw
$consumable = Get-Content -LiteralPath $paths.consumableLibrary -Raw
$handler = Get-Content -LiteralPath $paths.handler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$row = Get-TableRow -Path $paths.commandTable -Key "revivePlayer"

Write-Host "Publish 14.1 Revive Player command checks:"
$dsrcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "dsrc"
})
Assert-Contract -Condition (
    $dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq
        [string]$contract.buildEvidence.directSourceCommit) `
    -Name "p14.revive-player.direct-source-pin"
foreach ($property in
    $contract.buildEvidence.currentSourceSha256.psobject.Properties)
{
    $actualHash =
        (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $paths[[string]$property.Name]).Hash.ToLowerInvariant()
    Assert-Contract -Condition (
        [string]$actualHash -ceq [string]$property.Value) `
        -Name "p14.revive-player.source.$([string]$property.Name).authenticated"
}
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.specialization -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/RevivePlayerCommand.h") `
    -Name "p14.revive-player.core3.pinned-command"

Assert-Contract -Condition (
    $row.Matches.Count -eq 1 -and
    $row.Header.Count -eq 94 -and
    $row.Values.Count -eq 94 -and
    $row.Values[0] -ceq "revivePlayer" -and
    $row.Values[1] -ceq "combat" -and
    $row.Values[3] -ceq "cmdRevivePlayer" -and
    $row.Values[7] -ceq "10" -and
    $row.Values[8] -ceq "revivePlayer" -and
    $row.Values[72] -ceq "player.cmd.revive_player" -and
    $row.Values[73] -ceq "other" -and
    $row.Values[74] -ceq "optional" -and
    $row.Values[76] -ceq "2" -and
    $row.Values[80] -ceq "16" -and
    $row.Values[83] -ceq "0" -and
    $row.Values[84] -ceq "ALL" -and
    $row.Values[85] -ceq "NONE" -and
    $row.Values[88] -ceq "10") `
    -Name "p14.revive-player.table.original-hook-optional-nonqueued"

Assert-Contract -Condition (
    $handler.Contains("public int cmdRevivePlayer(") -and
    $handler.Contains("RANGE = 7.0f") -and
    $handler.Contains("!isPlayer(target)") -and
    $handler.Contains("!isDead(target)") -and
    $handler.Contains("target == self") -and
    $handler.Contains("getDistance(self, target)") -and
    $handler.Contains("canSee(self, target)") -and
    $handler.Contains("pvpCanHelp(self, target)") -and
    $handler.Contains("factions.pvpDoAllowedHelpCheck") -and
    $handler.Contains("group.inSameGroup(self, target)") -and
    $handler.Contains("pclib.hasConsent(self, target)")) `
    -Name "p14.revive-player.runtime.player-range-help-and-consent-gates"

Assert-Contract -Condition (
    $handler.Contains("parsePack(self, params)") -and
    $handler.Contains("healing.getRevivePack(self)") -and
    $handler.Contains("healing.getMedicalMindCost") -and
    $handler.Contains("healing.COST_MIND_REVIVE") -and
    $handler.Contains("healing.resuscitatePlayer") -and
    $handler.Contains('doAnimationAction(self, "heal_other")') -and
    $handler.Contains('"clienteffect/healing_healwound.cef"')) `
    -Name "p14.revive-player.runtime.pack-cost-and-presentation"

Assert-Contract -Condition (
    $healing.Contains("COST_MIND_REVIVE = 200") -and
    $healing.Contains('HEAL_TYPE_MEDICAL_REVIVE = "medical_revive"') -and
    $healing.Contains("!isPlayer(target) || !isDead(target)") -and
    $healing.Contains("pclib.VAR_BEEN_COUPDEGRACED") -and
    $healing.Contains("pclib.VAR_DEATHBLOW_STAMP") -and
    $healing.Contains("stamp + REVIVE_TIMER") -and
    $healing.Contains("isJedi(target) && !pclib.hasConsent") -and
    $healing.Contains("consumable.consumeItem(") -and
    $healing.Contains("true,") -and
    $healing.Contains("7.0f)")) `
    -Name "p14.revive-player.runtime.resuscitation-window-and-consumption"

Assert-Contract -Condition (
    $healing.Contains("HEALTH,") -and
    $healing.Contains("ACTION,") -and
    $healing.Contains("MIND") -and
    $healing.Contains("woundBefore[index]") -and
    $healing.Contains("Math.round((actualHealing + 250) * 0.5f)") -and
    $healing.Contains("xp.grant(medic, xp.MEDICAL, medicalXp)") -and
    $healing.Contains('"precu_private_groggy_" + attribute') -and
    $healing.Contains("-100,") -and
    $healing.Contains("60.0f")) `
    -Name "p14.revive-player.runtime.six-channel-xp-and-grogginess"

$reviveObserver = $contract.productionContract.campHealingObserver
$reviveObserverPattern =
    '(?s)healing\.healDamage\s*\(\s*player\s*,\s*target\s*,\s*attrib_mod\.getAttribute\(\)\s*,\s*attrib_mod\.getValue\(\)\s*,\s*notifyCampHealing\s*\)'
Assert-Contract -Condition (
    [int]$reviveObserver.damagePoolNotificationsPerUse -eq 3 -and
    (@($reviveObserver.notifyingPools) -join ",") -ceq
        "Health,Action,Mind" -and
    [int]$reviveObserver.woundHealingNotifications -eq 0 -and
    [bool]$reviveObserver.eachPositiveAuthoredPoolRequestNotifiesWhenClampedDeltaIsZero -and
    [regex]::IsMatch(
        $healing,
        '(?s)int\[\]\s+primary\s*=\s*\{\s*HEALTH\s*,\s*ACTION\s*,\s*MIND\s*\}') -and
    $healing.Contains("consumable.consumeItem(") -and
    $consumable.Contains("boolean revivePack = healing.isRevivePack(item);") -and
    $consumable.Contains("attrib_mod.getValue() > 0") -and
    $consumable.Contains("attrib_mod.getDuration() <= 0.0f") -and
    $consumable.Contains(
        "(int)attrib_mod.getDecay() == (int)MOD_POOL") -and
    [regex]::IsMatch(
        $consumable,
        '(?s)boolean notifyCampHealing\s*=\s*revivePack\s*\|\|') -and
    [regex]::Matches($consumable, $reviveObserverPattern).Count -eq 1 -and
    [regex]::IsMatch(
        $consumable,
        '(?s)else\s*\{\s*utils\.addAttribMod\(target, attrib_mod\);') -and
    $fixture.Contains("attrib_mod[6]") -and
    $fixture.Contains("modifiers[index * 2] =") -and
    $fixture.Contains("utils.createHealWoundAttribMod(") -and
    $fixture.Contains("modifiers[index * 2 + 1] =") -and
    $fixture.Contains("utils.createHealDamageAttribMod(")) `
    -Name "p14.revive-player.runtime.three-damage-zero-wound-observer-events"

Assert-Contract -Condition (
    $healing.Contains("attribute_int >= NUM_ATTRIBUTES") -and
    $healing.Contains('"STRENGTH"') -and
    $healing.Contains('"QUICKNESS"') -and
    $healing.Contains('"FOCUS"') -and
    -not $healing.Contains("attribute_int >= NUM_ATTRIBUTES + 2")) `
    -Name "p14.revive-player.runtime.nine-attribute-death-cleanup"

Assert-Contract -Condition (
    $fixture.Contains("MEDIC_OID = 39008597L") -and
    $fixture.Contains("MEDIC_STATION_ID = 1001") -and
    $fixture.Contains("PATIENT_OID = 44003778L") -and
    $fixture.Contains("PATIENT_STATION_ID = 91001") -and
    $fixture.Contains("DAMAGE_POWER = 100") -and
    $fixture.Contains("WOUND_POWER = 40") -and
    $fixture.Contains('"object/tangible/medicine/medpack_revive.iff"') -and
    $fixture.Contains("setCount(pack, 2)") -and
    $fixture.Contains("ORIGINAL_ATTRIBUTES") -and
    $fixture.Contains("ORIGINAL_WOUNDS") -and
    $fixture.Contains("ORIGINAL_MODIFIERS") -and
    $fixture.Contains("ORIGINAL_MEDICAL_XP") -and
    $fixture.Contains("revokeSkills(medic)") -and
    $fixture.Contains("removeObjVar(medic, ROOT)") -and
    $fixture.Contains("removeObjVar(patient, ROOT)")) `
    -Name "p14.revive-player.live.identity-bound-reversible-two-player-fixture"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 29 -and
        [string]$contract.clientToolsPublication.commit -ceq
            "1d08e71370e51e8e4ad45b08a7ec87e4846cc461" -and
        [string]$contract.clientAssetPublication.commit -ceq
            "0a143d7414374c4f8b714205ac773a8f8b22608f") `
        -Name "p14.revive-player.status.ready"
    Assert-Contract -Condition (
        [int]$live.successfulHandlerCall -eq 1 -and
        [long]$live.medicOid -eq 39008597 -and
        [long]$live.patientOid -eq 44003778 -and
        [bool]$live.sameGroup -and
        -not [bool]$live.consented -and
        [int]$live.distanceCentimeters -le 700 -and
        -not [bool]$live.targetDeadAfter -and
        [int]$live.targetPostureAfter -eq 0 -and
        -not [bool]$live.deathMarkerAfter -and
        [int]$live.actualHealing -eq
            ([int]$live.damageHealing + [int]$live.woundHealing)) `
        -Name "p14.revive-player.live.grouped-recovery"
    Assert-Contract -Condition (
        [int]$live.appliedMindCost -eq
            [int]$live.expectedMindCost -and
        [int]$live.appliedChargeCost -eq 1 -and
        [int]$live.observedMedicalXpDelta -eq
            [int]$live.expectedMedicalXp -and
        [int]$live.expectedMedicalXp -eq
            [math]::Round(
                ([int]$live.actualHealing + 250) * 0.5) -and
        [int]$live.groggyModifierCount -eq 9 -and
        [int]$live.clientQueueCountAtAdmission -eq 0 -and
        [string]$live.handlerOutcome -ceq "Success") `
        -Name "p14.revive-player.live.cost-xp-groggy-and-queue"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup -and
        [string]$contract.clientAssetPublication.commandTableIffSha256 -ceq
            [string]$live.commandTableIffSha256) `
        -Name "p14.revive-player.live.cleanup-health-and-publication"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Revive Player contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Revive Player command contract passed."
