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
    Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract =
    Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.p14TendingCommands)
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
        throw "Required materialized tending source is missing: $path"
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

function Get-BracedBlock
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Signature
    )
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0)
    {
        return ""
    }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0)
    {
        return ""
    }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{')
        {
            ++$depth
        }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    return ""
}

function Test-TendingCommandRow
{
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Hook,
        [Parameter(Mandatory = $true)][string]$TempScript
    )
    return (
        $Row.Matches.Count -eq 1 -and
        $Row.Header.Count -eq 94 -and
        $Row.Values.Count -eq 94 -and
        $Row.Values[0] -ceq $Name -and
        $Row.Values[1] -ceq "combat" -and
        $Row.Values[3] -ceq $Hook -and
        $Row.Values[7] -ceq "5" -and
        $Row.Values[8] -ceq $Name -and
        $Row.Values[33] -ceq "1" -and
        $Row.Values[72] -ceq $TempScript -and
        $Row.Values[73] -ceq "other" -and
        $Row.Values[74] -ceq "optional" -and
        $Row.Values[83] -ceq "1" -and
        $Row.Values[84] -ceq "ALL" -and
        $Row.Values[88] -ceq "5"
    )
}

$healing = Get-Content -LiteralPath $paths.healing -Raw
$damageHandler = Get-Content -LiteralPath $paths.tendDamageHandler -Raw
$woundHandler = Get-Content -LiteralPath $paths.tendWoundHandler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$damageRow = Get-TableRow -Path $paths.commandTable -Key "tendDamage"
$woundRow = Get-TableRow -Path $paths.commandTable -Key "tendWound"
$skillRow =
    Get-TableRow -Path $paths.skillTable -Key "science_medic_novice"
$tendDamage = Get-BracedBlock -Text $healing `
    -Signature "public static boolean performTendDamage("
$tendWound = Get-BracedBlock -Text $healing `
    -Signature "public static boolean performTendWound("

Write-Host "Publish 14.1 tending command checks:"
$dsrcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "dsrc"
})
Assert-Contract -Condition (
    $dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq
        [string]$contract.buildEvidence.directSourceCommit) `
    -Name "p14.tending.direct-source-pin"
foreach ($property in
    $contract.buildEvidence.currentSourceSha256.psobject.Properties)
{
    $actualHash =
        (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $paths[[string]$property.Name]).Hash.ToLowerInvariant()
    Assert-Contract -Condition (
        [string]$actualHash -ceq [string]$property.Value) `
        -Name "p14.tending.source.$([string]$property.Name).authenticated"
}
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.commonSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/TendCommand.h" -and
    [string]$contract.semanticReference.tendDamageSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/TendDamageCommand.h" -and
    [string]$contract.semanticReference.tendWoundSource -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/TendWoundCommand.h") `
    -Name "p14.tending.core3.pinned-commands"

Assert-Contract -Condition (
    (Test-TendingCommandRow `
        -Row $damageRow `
        -Name "tendDamage" `
        -Hook "cmdTendDamage" `
        -TempScript "player.cmd.tend_damage") -and
    (Test-TendingCommandRow `
        -Row $woundRow `
        -Name "tendWound" `
        -Hook "cmdTendWound" `
        -TempScript "player.cmd.tend_wound")) `
    -Name "p14.tending.table.authentic-five-second-queue"

Assert-Contract -Condition (
    $skillRow.Matches.Count -eq 1 -and
    $skillRow.Values.Count -eq 27 -and
    ([string]$skillRow.Values[21]).Contains("tendDamage") -and
    ([string]$skillRow.Values[21]).Contains("tendWound") -and
    ([string]$skillRow.Values[22]).Contains(
        "healing_injury_treatment=5") -and
    ([string]$skillRow.Values[22]).Contains(
        "healing_wound_treatment=5")) `
    -Name "p14.tending.skill.medic-novice-grants"

Assert-Contract -Condition (
    $healing.Contains(
        "public static final int VAR_TEND_DAMAGE_COST = 200;") -and
    $healing.Contains(
        "public static final int VAR_TEND_WOUND_COST = 400;") -and
    $healing.Contains(
        "public static final int VAR_TEND_DAMAGE_WOUND_COST = 5;") -and
    $healing.Contains(
        "public static final int VAR_TEND_WOUND_WOUND_COST = 5;") -and
    $healing.Contains(
        "heal_type.equals(HEAL_TYPE_MEDICAL_TEND_WOUND) ||") -and
    $healing.Contains(
        "heal_type.equals(HEAL_TYPE_MEDICAL_TEND_DAMAGE)") -and
    $healing.Contains("getMedicalMindCost(player, cost)")) `
    -Name "p14.tending.runtime.focus-adjusted-organic-costs"

Assert-Contract -Condition (
    $healing.Contains(
        'getSkillStatMod(medic, "healing_injury_treatment")') -and
    $healing.Contains(
        'getSkillStatMod(medic, "healing_wound_treatment")') -and
    $healing.Contains("getSkillStatMod(medic, skillMod) / 3.0f +") -and
    $healing.Contains(
        "Math.round(applyShockWoundModifier(power, target))") -and
    $healing.Contains(
        "int healthHealed = healDamage(") -and
    $healing.Contains(
        "int actionHealed = healDamage(")) `
    -Name "p14.tending.runtime.skill-power-battle-fatigue-and-ha"

$tendingObserver = $contract.productionContract.campHealingObserver
$tendHealthPattern =
    '(?s)healDamage\s*\(\s*medic\s*,\s*target\s*,\s*HEALTH\s*,\s*power\s*,\s*true\s*\)'
$tendActionPattern =
    '(?s)healDamage\s*\(\s*medic\s*,\s*target\s*,\s*ACTION\s*,\s*power\s*,\s*false\s*\)'
Assert-Contract -Condition (
    [int]$tendingObserver.tendDamageNotificationsPerUse -eq 1 -and
    [string]$tendingObserver.tendDamageNotifyingPool -ceq
        "Health request" -and
    -not [bool]$tendingObserver.tendDamageActionPoolNotifies -and
    -not [bool]$tendingObserver.tendWoundNotifies -and
    [bool]$tendingObserver.clampedHealthDeltaZeroStillNotifies -and
    -not [string]::IsNullOrEmpty($tendDamage) -and
    [regex]::Matches($tendDamage, $tendHealthPattern).Count -eq 1 -and
    [regex]::Matches($tendDamage, $tendActionPattern).Count -eq 1 -and
    [regex]::Matches(
        $tendDamage,
        'healDamage\s*\(').Count -eq 2 -and
    -not [string]::IsNullOrEmpty($tendWound) -and
    $tendWound.Contains(
        "healWound(target, attribute, Math.min(power, woundBefore));") -and
    -not [regex]::IsMatch($tendWound, 'healDamage\s*\(')) `
    -Name "p14.tending.runtime.exact-damage-and-wound-observer-cardinality"

Assert-Contract -Condition (
    $healing.Contains(
        "for (int attribute = HEALTH; attribute < MIND; ++attribute)") -and
    $healing.Contains(
        "attribute < HEALTH || attribute >= MIND") -and
    $healing.Contains(
        "healWound(target, attribute, Math.min(power, woundBefore))") -and
    $healing.Contains(
        "HEAL_TYPE_MEDICAL_TEND_WOUND);") -and
    $healing.Contains(
        "experience = (int) (total_healed * 2.5f);")) `
    -Name "p14.tending.runtime.wound-selection-and-xp"

Assert-Contract -Condition (
    $healing.Contains(
        "addWound(medic, FOCUS, VAR_TEND_DAMAGE_WOUND_COST);") -and
    $healing.Contains(
        "addWound(medic, WILLPOWER, VAR_TEND_DAMAGE_WOUND_COST);") -and
    $healing.Contains(
        "addWound(medic, FOCUS, VAR_TEND_WOUND_WOUND_COST);") -and
    $healing.Contains(
        "addWound(medic, WILLPOWER, VAR_TEND_WOUND_WOUND_COST);") -and
    $healing.Contains(
        "case HEAL_TYPE_MEDICAL_TEND_DAMAGE:") -and
    $healing.Contains(
        "case HEAL_TYPE_MEDICAL_TEND_WOUND:")) `
    -Name "p14.tending.runtime.focus-willpower-wounds-and-xp-boundary"

Assert-Contract -Condition (
    $damageHandler.Contains("TEND_RANGE = 6.0f") -and
    $woundHandler.Contains("TEND_RANGE = 6.0f") -and
    $damageHandler.Contains("if (!canSee(healer, target))") -and
    $woundHandler.Contains("if (!canSee(healer, target))") -and
    $damageHandler.Contains("factions.pvpDoAllowedHelpCheck") -and
    $woundHandler.Contains("factions.pvpDoAllowedHelpCheck") -and
    -not $damageHandler.Contains("getState(self, STATE_COMBAT)") -and
    -not $woundHandler.Contains("getState(self, STATE_COMBAT)") -and
    -not $damageHandler.Contains("consumeItem") -and
    -not $woundHandler.Contains("consumeItem") -and
    -not $damageHandler.Contains("medikit") -and
    -not $woundHandler.Contains("medikit")) `
    -Name "p14.tending.runtime.patient-gates-and-no-medicine"

Assert-Contract -Condition (
    $damageHandler.Contains('"precu.tendingCommandFixture"') -and
    $woundHandler.Contains('"precu.tendingCommandFixture"') -and
    $damageHandler.Contains(
        'FIXTURE_ROOT + ".tendDamageExpectedMindCost"') -and
    $woundHandler.Contains(
        'FIXTURE_ROOT + ".tendWoundExpectedMindCost"') -and
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("resetTelemetry(player);") -and
    $fixture.Contains("isFixtureActive(player)") -and
    $fixture.Contains("EXPECTED_DAMAGE_COST") -and
    $fixture.Contains("EXPECTED_WOUND_COST") -and
    -not $fixture.Contains('create.CREATURE_TABLE') -and
    $fixture.Contains('"prepare"') -and
    $fixture.Contains('"status"') -and
    $fixture.Contains('"cleanup"')) `
    -Name "p14.tending.live.identity-and-opt-in-telemetry"

Assert-Contract -Condition (
    $fixture.Contains("ORIGINAL_MIND") -and
    $fixture.Contains("ORIGINAL_FOCUS") -and
    $fixture.Contains("ORIGINAL_WILLPOWER") -and
    $fixture.Contains("ORIGINAL_FOCUS_WOUND") -and
    $fixture.Contains("ORIGINAL_WILLPOWER_WOUND") -and
    $fixture.Contains("ORIGINAL_MEDICAL_XP") -and
    $fixture.Contains("clearFixtureVariables(player);") -and
    $fixture.Contains("getExperiencePoints(player, xp.MEDICAL) ==") -and
    -not $fixture.Contains("destroyObject(patient);")) `
    -Name "p14.tending.live.reversible-owned-state"

if ($Expectation -ceq "Ready")
{
    $damage = $contract.liveEvidence.tendDamage
    $wound = $contract.liveEvidence.tendWound
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.liveEvidence.result -ceq "passed") `
        -Name "p14.tending.status.ready"
    Assert-Contract -Condition (
        [string]$damage.handlerOutcome -ceq "performed" -and
        [int]$damage.appliedHealthHeal -eq
            [int]$damage.expectedTreatmentPower -and
        [int]$damage.appliedActionHeal -eq
            [int]$damage.expectedTreatmentPower -and
        [int]$damage.appliedMindCost -eq
            [int]$damage.expectedMindCost -and
        [int]$damage.appliedFocusWoundCost -eq 5 -and
        [int]$damage.appliedWillpowerWoundCost -eq 5 -and
        [int]$damage.appliedMedicalXp -eq 0) `
        -Name "p14.tending.live.tend-damage"
    Assert-Contract -Condition (
        [string]$wound.handlerOutcome -ceq "performed" -and
        [string]$wound.attribute -ceq "Health" -and
        [int]$wound.appliedWoundHeal -eq
            [int]$wound.expectedTreatmentPower -and
        [int]$wound.appliedMindCost -eq
            [int]$wound.expectedMindCost -and
        [int]$wound.appliedFocusWoundCost -eq 5 -and
        [int]$wound.appliedWillpowerWoundCost -eq 5 -and
        [int]$wound.appliedMedicalXp -eq 55 -and
        [int]$wound.commandExecuteTimeSeconds -eq 5 -and
        [int]$wound.clientQueueCountAtObservation -eq 0) `
        -Name "p14.tending.live.tend-wound"
    Assert-Contract -Condition (
        [bool]$contract.liveEvidence.cleanup.restored -and
        [int]$contract.liveEvidence.cleanup.clientQueueCount -eq 0) `
        -Name "p14.tending.live.cleanup-restored"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 tending contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 tending command contract passed."
