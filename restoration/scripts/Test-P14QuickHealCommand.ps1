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
            [string]$manifest.contracts.p14QuickHealCommand)
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
        throw "Required materialized Quick Heal source is missing: $path"
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

$handler = Get-Content -LiteralPath $paths.handler -Raw
$fixture = Get-Content -LiteralPath $paths.liveFixture -Raw
$row = Get-TableRow -Path $paths.commandTable -Key "quickHeal"

Write-Host "Publish 14.1 Quick Heal command checks:"
$dsrcPin = @($manifest.gitlinks | Where-Object {
    [string]$_.name -ceq "dsrc"
})
Assert-Contract -Condition (
    $dsrcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq
        [string]$contract.buildEvidence.directSourceCommit) `
    -Name "p14.quick-heal.direct-source-pin"
foreach ($property in
    $contract.buildEvidence.currentSourceSha256.psobject.Properties)
{
    $actualHash =
        (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $paths[[string]$property.Name]).Hash.ToLowerInvariant()
    Assert-Contract -Condition (
        [string]$actualHash -ceq [string]$property.Value) `
        -Name "p14.quick-heal.source.$([string]$property.Name).authenticated"
}
Assert-Contract -Condition (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "6856f315a80b5250635b2272695caec1d64204ed" -and
    [string]$contract.semanticReference.source -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/QuickHealCommand.h") `
    -Name "p14.quick-heal.core3.pinned-command"

Assert-Contract -Condition (
    $row.Matches.Count -eq 1 -and
    $row.Header.Count -eq 94 -and
    $row.Values.Count -eq 94 -and
    $row.Values[0] -ceq "quickHeal" -and
    $row.Values[1] -ceq "combat" -and
    $row.Values[3] -ceq "quickHeal" -and
    $row.Values[7] -ceq "2" -and
    $row.Values[8] -ceq "quickHeal" -and
    $row.Values[72] -ceq "player.cmd.quick_heal" -and
    $row.Values[73] -ceq "other" -and
    $row.Values[74] -ceq "optional" -and
    $row.Values[76] -ceq "2" -and
    $row.Values[83] -ceq "0" -and
    $row.Values[84] -ceq "ALL" -and
    $row.Values[85] -ceq "NONE" -and
    $row.Values[88] -ceq "2") `
    -Name "p14.quick-heal.table.authentic-optional-nonqueue"

Assert-Contract -Condition (
    $handler.Contains("target = self;") -and
    $handler.Contains("RANGE = 6.0f") -and
    $handler.Contains("getDistance(self, target)") -and
    $handler.Contains("canSee(self, target)") -and
    $handler.Contains("pvpCanHelp(self, target)") -and
    $handler.Contains("factions.pvpDoAllowedHelpCheck") -and
    $handler.Contains("pet_lib.isCreaturePet(target)") -and
    $handler.Contains("!ai_lib.isDroid(target)") -and
    $handler.Contains("!pet_lib.isVehiclePet(target)")) `
    -Name "p14.quick-heal.runtime.organic-six-meter-help-gates"

Assert-Contract -Condition (
    $handler.Contains("BASE_MIND_COST = 1000") -and
    $handler.Contains("focus - 300.0f") -and
    $handler.Contains("/ 1200.0f") -and
    $handler.Contains("MIN_HEAL = 150") -and
    $handler.Contains("MAX_HEAL = 750") -and
    $handler.Contains("rand(MIN_HEAL, MAX_HEAL)") -and
    [regex]::IsMatch(
        $handler,
        '(?s)healing\.healDamage\s*\(\s*self\s*,\s*target\s*,\s*HEALTH\s*,\s*healPower\s*,\s*true\s*\)') -and
    [regex]::IsMatch(
        $handler,
        '(?s)healing\.healDamage\s*\(\s*self\s*,\s*target\s*,\s*ACTION\s*,\s*healPower\s*,\s*true\s*\)') -and
    $handler.Contains("addWound(self, FOCUS, MIND_WOUND_COST)") -and
    $handler.Contains("addWound(self, WILLPOWER, MIND_WOUND_COST)") -and
    -not $handler.Contains("consumeObject(") -and
    -not $handler.Contains("grantExperiencePoints(") -and
    -not $handler.Contains("performQuickHealTool")) `
    -Name "p14.quick-heal.runtime.core3-cost-heal-and-wounds"

$quickHealObserver = $contract.productionContract.campHealingObserver
Assert-Contract -Condition (
    [int]$quickHealObserver.notificationsPerUse -eq 2 -and
    (@($quickHealObserver.notifyingPools) -join ",") -ceq
        "Health,Action" -and
    [bool]$quickHealObserver.eachAuthoredRequestNotifiesWhenClampedDeltaIsZero -and
    [regex]::Matches($handler, 'healing\.healDamage\s*\(').Count -eq 2 -and
    [regex]::Matches(
        $handler,
        '(?s)healing\.healDamage\s*\([^;]+?\btrue\s*\);').Count -eq 2 -and
    -not $handler.Contains("notifyCampHealing")) `
    -Name "p14.quick-heal.runtime.two-authored-pool-observer-events"

Assert-Contract -Condition (
    $fixture.Contains("PLAYER_OID = 39008597L") -and
    $fixture.Contains("PLAYER_STATION_ID = 1001") -and
    $fixture.Contains("PREPARED_HEALTH_CURRENT = 200") -and
    $fixture.Contains("PREPARED_ACTION_CURRENT = 100") -and
    $fixture.Contains("REQUIRED_FOCUS_CAPACITY = 1100") -and
    $fixture.Contains("FOCUS_CAPACITY_MOD") -and
    $fixture.Contains("addAttribModifier(") -and
    $fixture.Contains("removeAttribOrSkillModModifier(") -and
    $fixture.Contains("setWoundExact") -and
    $fixture.Contains("resurrect(player)") -and
    $fixture.Contains("ORIGINAL_COMMAND") -and
    $fixture.Contains("ORIGINAL_MEDICAL_XP") -and
    $fixture.Contains('originalPath(index, "max")') -and
    $fixture.Contains('originalPath(index, "current")') -and
    $fixture.Contains('originalPath(index, "wound")') -and
    $fixture.Contains("incompleteSnapshot=true cleared=true")) `
    -Name "p14.quick-heal.live.identity-bound-reversible-fixture"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract -Condition (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 22 -and
        [int]$live.clientQueueCountAtAdmission -eq 0) `
        -Name "p14.quick-heal.status.ready"
    Assert-Contract -Condition (
        [int]$live.handlerCalls -eq 1 -and
        [long]$live.targetOid -eq 39008597 -and
        [int]$live.observedFocus -eq 1100 -and
        [int]$live.mindCost -eq 333 -and
        [int]$live.healPower -ge 150 -and
        [int]$live.healPower -le 750 -and
        [int]$live.healthHealed -gt 0 -and
        [int]$live.healthHealed -le
            ([int]$live.healPower +
                [int]$live.regenerationTolerance) -and
        [int]$live.actionHealed -gt 0 -and
        [int]$live.actionHealed -le
            ([int]$live.healPower +
                [int]$live.regenerationTolerance) -and
        [bool]$live.sharedHealPowerApplied -and
        [int]$live.focusWounds -eq 10 -and
        [int]$live.willpowerWounds -eq 10 -and
        [int]$live.medicalXpDelta -eq 0 -and
        [string]$live.handlerOutcome -ceq "performed") `
        -Name "p14.quick-heal.live.production-cost-heal-wounds-zero-xp"
    Assert-Contract -Condition (
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [int]$live.clientQueueCountAfterCleanup -eq 0 -and
        [bool]$live.serverHealthyAfterCleanup -and
        [bool]$live.oracleHealthyAfterCleanup) `
        -Name "p14.quick-heal.live.cleanup-and-health"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Quick Heal contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 Quick Heal command contract passed."
