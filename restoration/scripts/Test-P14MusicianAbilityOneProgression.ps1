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
        p14MusicianAbilityOneProgression)
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
        throw "Required Musician Ability I source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$box = @($skills |
    Where-Object NAME -CEQ ([string]$e.abilityOne.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Musician Ability I checks:"
Assert-Contract (
    $box.Count -eq 1 -and
    [string]$box[0].PARENT -ceq [string]$e.abilityOne.parent -and
    [string]$box[0].GRAPH_TYPE -ceq
        [string]$e.abilityOne.graphType -and
    [string]$box[0].IS_TITLE -ceq [string]$e.abilityOne.isTitle -and
    [string]$box[0].MONEY_REQUIRED -ceq
        [string]$e.abilityOne.moneyRequired -and
    [string]$box[0].POINTS_REQUIRED -ceq
        [string]$e.abilityOne.pointsRequired -and
    [string]$box[0].SKILLS_REQUIRED -ceq
        [string]$e.abilityOne.skillsRequired -and
    [string]$box[0].XP_TYPE -ceq [string]$e.abilityOne.xpType -and
    [string]$box[0].XP_COST -ceq [string]$e.abilityOne.xpCost -and
    [string]$box[0].XP_CAP -ceq [string]$e.abilityOne.xpCap -and
    [string]$box[0].COMMANDS -ceq [string]$e.abilityOne.commands -and
    [string]$box[0].SKILL_MODS -ceq
        [string]$e.abilityOne.skillMods -and
    [string]$box[0].SCHEMATICS_GRANTED -ceq
        [string]$e.abilityOne.schematics -and
    [string]$box[0].SEARCHABLE -ceq
        [string]$e.abilityOne.searchable
) "p14.musician-ability-one.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareMusicianAbilityOne") -and
    $fixture.Contains("purchaseMusicianAbilityOne") -and
    $fixture.Contains("observeSurrenderMusicianAbilityOne") -and
    $fixture.Contains("SPOTLIGHT_ABILITY") -and
    $fixture.Contains("COLORLIGHTS_ABILITY") -and
    $fixture.Contains("DAZZLE_ABILITY")
) "p14.musician-ability-one.fixture-parent-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 67
    ) "p14.musician-ability-one.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.musicXpBefore -eq 87500 -and
        [int]$live.purchase.musicXpAfter -eq 0 -and
        [int]$live.purchase.pointCost -eq 5 -and
        [string]$live.purchase.commandsAfter -ceq "111" -and
        [string]$live.purchase.modifierDeltasAfter -ceq "10,10" -and
        [bool]$live.surrender.musicianNoviceRetained -and
        [string]$live.surrender.noviceCommandsRetained -ceq "111" -and
        [bool]$live.surrender.parentKlooHornRetained -and
        [int]$live.surrender.pointsRecovered -eq 5 -and
        [string]$live.surrender.commandsAfter -ceq "000" -and
        [int]$live.surrender.musicXpCapAfter -eq 350000 -and
        [int]$live.surrender.healingXpCapAfter -eq 75000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.musician-ability-one.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Musician Ability I contract failed: " +
        ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Musician Ability I contract passed."
