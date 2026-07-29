[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content (
    Join-Path $root ([string]$manifest.contracts.
        p14DancerAbilityOneProgression)
) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path

function Import-Tab([string]$Path)
{
    $lines = Get-Content $Path
    return @(@($lines[0]) + @($lines | Select-Object -Skip 2) |
        ConvertFrom-Csv -Delimiter "`t")
}

$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$fixturePath = Join-Path $source ([string]$contract.sourceFiles.fixture)
foreach ($path in @($skillsPath, $fixturePath))
{
    if (-not (Test-Path $path -PathType Leaf))
    {
        throw "Required Dancer Ability I source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$ability = @($skills |
    Where-Object NAME -CEQ ([string]$e.abilityOne.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Dancer Ability I checks:"
Assert-Contract (
    $ability.Count -eq 1 -and
    [string]$ability[0].PARENT -ceq [string]$e.abilityOne.parent -and
    [string]$ability[0].GRAPH_TYPE -ceq
        [string]$e.abilityOne.graphType -and
    [string]$ability[0].IS_TITLE -ceq
        [string]$e.abilityOne.isTitle -and
    [string]$ability[0].IS_PROFESSION -ceq
        [string]$e.abilityOne.isProfession -and
    [string]$ability[0].MONEY_REQUIRED -ceq
        [string]$e.abilityOne.moneyRequired -and
    [string]$ability[0].POINTS_REQUIRED -ceq
        [string]$e.abilityOne.pointsRequired -and
    [string]$ability[0].SKILLS_REQUIRED -ceq
        [string]$e.abilityOne.skillsRequired -and
    [string]$ability[0].XP_TYPE -ceq [string]$e.abilityOne.xpType -and
    [string]$ability[0].XP_COST -ceq [string]$e.abilityOne.xpCost -and
    [string]$ability[0].XP_CAP -ceq [string]$e.abilityOne.xpCap -and
    [string]$ability[0].COMMANDS -ceq
        [string]$e.abilityOne.commands -and
    [string]$ability[0].SKILL_MODS -ceq
        [string]$e.abilityOne.skillMods -and
    [string]$ability[0].SCHEMATICS_GRANTED -ceq
        [string]$e.abilityOne.schematics -and
    [string]$ability[0].SEARCHABLE -ceq
        [string]$e.abilityOne.searchable
) "p14.dancer-ability-one.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareDancerAbilityOne") -and
    $fixture.Contains("purchaseDancerAbilityOne") -and
    $fixture.Contains("observeSurrenderDancerAbilityOne") -and
    $fixture.Contains("SPOTLIGHT_ABILITY") -and
    $fixture.Contains("COLOR_LIGHTS_ABILITY") -and
    $fixture.Contains("DAZZLE_ABILITY")
) "p14.dancer-ability-one.fixture.production-and-reversible"

if ($Expectation -ceq "Ready")
{
    $b = $contract.buildEvidence
    $live = $contract.liveEvidence
    $patch = Join-Path $root (
        [string]$b.overlayPatch -replace "^restoration/", "")
    Assert-Contract (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.overlayPatchSha256 -and
        (Get-FileHash $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.sourceSha256.
                "precu_entertainer_dance_one_fixture.java" -and
        (Get-FileHash $skillsPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.sourceSha256."skills.tab" -and
        [int]$b.clientNativeBuild.protocolVersion -eq 49
    ) "p14.dancer-ability-one.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.danceXpBefore -eq 87500 -and
        [int]$live.purchase.pointCost -eq 5 -and
        [string]$live.purchase.commandsAfter -ceq "111" -and
        [int]$live.purchase.danceAbilityDelta -eq 0 -and
        [int]$live.purchase.danceWoundDelta -eq 0 -and
        [int]$live.purchase.danceShockDelta -eq 0 -and
        [int]$live.purchase.danceMindDelta -eq 10 -and
        [int]$live.purchase.xpCapAfter -eq 500000 -and
        [bool]$live.surrender.dancerNoviceRetained -and
        [string]$live.surrender.dancerNoviceCommandsAfter -ceq "111" -and
        [string]$live.surrender.abilityOneCommandsAfter -ceq "000" -and
        [int]$live.surrender.pointsRecovered -eq 5 -and
        [int]$live.surrender.dancerNoviceXpCapAfter -eq 350000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0,0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.dancer-ability-one.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Dancer Ability I contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Dancer Ability I contract passed."
