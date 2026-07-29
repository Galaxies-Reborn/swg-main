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
        p14MusicianNoviceProgression)
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
        throw "Required Musician novice source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$novice = @($skills |
    Where-Object NAME -CEQ ([string]$e.novice.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Musician novice checks:"
Assert-Contract (
    $novice.Count -eq 1 -and
    [string]$novice[0].PARENT -ceq [string]$e.novice.parent -and
    [string]$novice[0].GRAPH_TYPE -ceq
        [string]$e.novice.graphType -and
    [string]$novice[0].IS_TITLE -ceq [string]$e.novice.isTitle -and
    [string]$novice[0].IS_PROFESSION -ceq
        [string]$e.novice.isProfession -and
    [string]$novice[0].MONEY_REQUIRED -ceq
        [string]$e.novice.moneyRequired -and
    [string]$novice[0].POINTS_REQUIRED -ceq
        [string]$e.novice.pointsRequired -and
    [string]$novice[0].SKILLS_REQUIRED -ceq
        [string]$e.novice.skillsRequired -and
    [string]$novice[0].XP_TYPE -ceq [string]$e.novice.xpType -and
    [string]$novice[0].XP_COST -ceq [string]$e.novice.xpCost -and
    [string]$novice[0].XP_CAP -ceq [string]$e.novice.xpCap -and
    [string]$novice[0].COMMANDS -ceq [string]$e.novice.commands -and
    [string]$novice[0].SKILL_MODS -ceq [string]$e.novice.skillMods -and
    [string]$novice[0].SCHEMATICS_GRANTED -ceq
        [string]$e.novice.schematics -and
    [string]$novice[0].SEARCHABLE -ceq [string]$e.novice.searchable
) "p14.musician-novice.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareMusicianNovice") -and
    $fixture.Contains("purchaseMusicianNovice") -and
    $fixture.Contains("observeSurrenderMusicianNovice") -and
    $fixture.Contains("TRAZ_ABILITY") -and
    $fixture.Contains("KLOO_HORN_SCHEMATIC") -and
    $fixture.Contains("MUSIC_SHOCK_MOD") -and
    $fixture.Contains("MUSIC_MIND_MOD") -and
    $fixture.Contains("INSTRUMENT_ASSEMBLY_MOD")
) "p14.musician-novice.fixture-prerequisite-and-reversible"

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
                "precu_entertainer_music_one_fixture.java" -and
        (Get-FileHash $skillsPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            [string]$b.sourceSha256."skills.tab" -and
        [int]$b.clientNativeBuild.protocolVersion -eq 66
    ) "p14.musician-novice.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.musicXpBefore -eq 50000 -and
        [int]$live.purchase.musicXpAfter -eq 0 -and
        [int]$live.purchase.pointCost -eq 6 -and
        [string]$live.purchase.noviceCommandsAfter -ceq "111" -and
        [bool]$live.purchase.parentKlooHornRetained -and
        [bool]$live.purchase.schematicPresent -and
        [string]$live.purchase.modifierDeltasAfter -ceq
            "5,5,10,10,10" -and
        [bool]$live.surrender.musicFourRetained -and
        [bool]$live.surrender.healingFourRetained -and
        [bool]$live.surrender.parentKlooHornRetained -and
        [int]$live.surrender.pointsRecovered -eq 6 -and
        [string]$live.surrender.noviceCommandsAfter -ceq "000" -and
        -not [bool]$live.surrender.schematicPresent -and
        [int]$live.surrender.musicXpCapAfter -eq 150000 -and
        [int]$live.surrender.healingXpCapAfter -eq 75000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq
            "0,0,0,0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.musician-novice.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Musician novice contract failed: " + ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Musician novice contract passed."
