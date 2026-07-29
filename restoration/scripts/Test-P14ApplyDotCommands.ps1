[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content (Join-Path $restorationRoot ([string]$manifest.contracts.p14ApplyDotCommands)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized Apply DOT source is missing: $path"
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}
function Get-Row([string]$Path, [string]$Key)
{
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    $matches = @($lines | Select-Object -Skip 2 | Where-Object {
        (($_ -split "`t", -1)[0]) -ceq $Key })
    [pscustomobject]@{Header=$header; Matches=$matches; Values=$(if (
        $matches.Count -eq 1) {$matches[0] -split "`t", -1} else {@()})}
}

$poison = Get-Row $paths.commandTable "applyPoison"
$disease = Get-Row $paths.commandTable "applyDisease"
$skills = Get-Content $paths.skillTable -Raw
$healing = Get-Content $paths.healingLibrary -Raw
$handler = Get-Content $paths.handler -Raw
$fixture = Get-Content $paths.liveFixture -Raw
Write-Host "Publish 14.1 Apply Poison / Apply Disease checks:"
Assert-Contract (
    [string]$contract.semanticReference.pinnedCommit -ceq
        "b3f81c104acf9851def65bab5f0638e68a0cdede" -and
    [string]$contract.semanticReference.sharedCommand -ceq
        "MMOCoreORB/src/server/zone/objects/creature/commands/DotPackCommand.h") `
    "p14.apply-dot.core3.pinned-shared-command"
foreach ($pair in @(@("applyPoison", $poison), @("applyDisease", $disease)))
{
    $name = [string]$pair[0]; $row = $pair[1]
    Assert-Contract ($row.Matches.Count -eq 1 -and
        $row.Header.Count -eq 94 -and $row.Values.Count -eq 94 -and
        $row.Values[0] -ceq $name -and $row.Values[3] -ceq $name -and
        $row.Values[7] -ceq "5" -and $row.Values[8] -ceq $name -and
        $row.Values[72] -ceq "player.cmd.apply_dot" -and
        $row.Values[73] -ceq "other" -and $row.Values[74] -ceq "optional" -and
        $row.Values[76] -ceq "2" -and $row.Values[88] -ceq "5") `
        "p14.apply-dot.table.$($name.ToLowerInvariant())"
}
Assert-Contract ($skills.Contains("science_combatmedic_novice") -and
    $skills.Contains("`tapplyPoison`t") -and
    $skills.Contains("science_combatmedic_healing_range_02") -and
    $skills.Contains("`tapplyDisease`t")) `
    "p14.apply-dot.skill-ownership"
Assert-Contract ($handler.Contains("factions.pvpDoAllowedAttackCheck") -and
    $handler.Contains("canSee(self, target)") -and
    $handler.Contains("healing.findApplyDotMedicine") -and
    $handler.Contains("healing.performApplyPosion") -and
    $handler.Contains("healing.performApplyDisease") -and
    $handler.Contains("getCombatMedicMindCost") -and
    $handler.Contains("healing.can_apply_poison") -and
    $handler.Contains("healing.can_apply_disease") -and
    $handler.Contains("12.0f - 6.0f * speed / 100.0f")) `
    "p14.apply-dot.runtime-admission-cost-and-recovery"
Assert-Contract ($healing.Contains('getSkillStatMod(medic, "healing_range")') -and
    $healing.Contains('getSkillStatMod(medic, "combat_medic_effectiveness")') -and
    $healing.Contains("dot.applyDotEffect") -and
    $healing.Contains("consumable.decrementCharges") -and
    $healing.Contains("getAttackableTargetsInArea") -and
    $healing.Contains("grantHealingExperience") -and
    $healing.Contains("getCombatMedicMindCost")) `
    "p14.apply-dot.retained-dot-pack-lifecycle"
Assert-Contract ($fixture.Contains("PLAYER_OID = 44003778L") -and
    $fixture.Contains("PLAYER_STATION_ID = 91001") -and
    $fixture.Contains("DOT_POTENCY = -1") -and
    $fixture.Contains("ORIGINAL_MAX_MIND") -and
    $fixture.Contains("Math.max(500, getMaxAttrib(player, MIND))") -and
    $fixture.Contains("precu_apply_poison_fixture") -and
    $fixture.Contains("precu_apply_disease_fixture") -and
    $fixture.Contains("destroyObject(target)") -and
    $fixture.Contains("revokeSkills(player)") -and
    $fixture.Contains("removeObjVar(player, ROOT)")) `
    "p14.apply-dot.live-identity-bound-reversible-fixture"

if ($Expectation -ceq "Ready")
{
    $live = $contract.liveEvidence
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$live.result -ceq "passed" -and
        [int]$live.clientProtocolVersion -eq 164) `
        "p14.apply-dot.status.ready"
    Assert-Contract ([int]$live.poison.handlerCalls -eq 1 -and
        [int]$live.disease.handlerCalls -eq 1 -and
        [string]$live.poison.outcome -ceq "performed" -and
        [string]$live.disease.outcome -ceq "performed" -and
        [int]$live.poison.chargeCost -eq 1 -and
        [int]$live.disease.chargeCost -eq 1 -and
        [int]$live.poison.strengthAfter -gt 0 -and
        [int]$live.disease.strengthAfter -gt 0) `
        "p14.apply-dot.live.both-dot-packs"
    Assert-Contract ([bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent -and
        [bool]$live.serverHealthyAfterCleanup) `
        "p14.apply-dot.live.cleanup-and-health"
}
if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Apply DOT contract failed: $($failures -join ', ')"
}
Write-Host ""
Write-Host "Publish 14.1 Apply Poison / Apply Disease contract passed."
