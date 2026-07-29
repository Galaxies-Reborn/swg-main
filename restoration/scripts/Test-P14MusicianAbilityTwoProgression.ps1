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
        p14MusicianAbilityTwoProgression)
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
        throw "Required Musician Ability II source is missing: $path"
    }
}

$skills = Import-Tab $skillsPath
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence
$box = @($skills |
    Where-Object NAME -CEQ ([string]$e.abilityTwo.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

Write-Host "Publish 14.1 Musician Ability II checks:"
Assert-Contract (
    $box.Count -eq 1 -and
    [string]$box[0].PARENT -ceq [string]$e.abilityTwo.parent -and
    [string]$box[0].GRAPH_TYPE -ceq
        [string]$e.abilityTwo.graphType -and
    [string]$box[0].IS_TITLE -ceq [string]$e.abilityTwo.isTitle -and
    [string]$box[0].MONEY_REQUIRED -ceq
        [string]$e.abilityTwo.moneyRequired -and
    [string]$box[0].POINTS_REQUIRED -ceq
        [string]$e.abilityTwo.pointsRequired -and
    [string]$box[0].SKILLS_REQUIRED -ceq
        [string]$e.abilityTwo.skillsRequired -and
    [string]$box[0].XP_TYPE -ceq [string]$e.abilityTwo.xpType -and
    [string]$box[0].XP_COST -ceq [string]$e.abilityTwo.xpCost -and
    [string]$box[0].XP_CAP -ceq [string]$e.abilityTwo.xpCap -and
    [string]$box[0].COMMANDS -ceq [string]$e.abilityTwo.commands -and
    [string]$box[0].SKILL_MODS -ceq
        [string]$e.abilityTwo.skillMods -and
    [string]$box[0].SCHEMATICS_GRANTED -ceq
        [string]$e.abilityTwo.schematics -and
    [string]$box[0].SEARCHABLE -ceq
        [string]$e.abilityTwo.searchable
) "p14.musician-ability-two.skill.authentic"

Assert-Contract (
    $fixture.Contains("prepareMusicianAbilityTwo") -and
    $fixture.Contains("purchaseMusicianAbilityTwo") -and
    $fixture.Contains("observeSurrenderMusicianAbilityTwo") -and
    $fixture.Contains("FIREJET_ABILITY") -and
    $fixture.Contains("NGE_LASER_SHOW_ABILITY") -and
    $fixture.Contains("TRAZ_SCHEMATIC")
) "p14.musician-ability-two.fixture-parent-and-reversible"

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
        [int]$b.clientNativeBuild.protocolVersion -eq 68
    ) "p14.musician-ability-two.build.ready-and-hashed"

    Assert-Contract (
        [string]$live.result -ceq "passed" -and
        [bool]$live.purchase.passed -and
        [int]$live.purchase.musicXpBefore -eq 125000 -and
        [int]$live.purchase.musicXpAfter -eq 0 -and
        [int]$live.purchase.pointCost -eq 4 -and
        [bool]$live.purchase.fireJetPresent -and
        -not [bool]$live.purchase.laserShowPresent -and
        [bool]$live.purchase.schematicPresent -and
        [string]$live.purchase.modifierDeltasAfter -ceq "15,10" -and
        [bool]$live.surrender.abilityOneRetained -and
        [string]$live.surrender.abilityOneCommandsRetained -ceq "111" -and
        -not [bool]$live.surrender.fireJetPresent -and
        -not [bool]$live.surrender.laserShowPresent -and
        -not [bool]$live.surrender.schematicPresent -and
        [int]$live.surrender.pointsRecovered -eq 4 -and
        [int]$live.surrender.musicXpCapAfter -eq 500000 -and
        [int]$live.surrender.healingXpCapAfter -eq 75000 -and
        [string]$live.surrender.modifierDeltasAfter -ceq "0,0" -and
        [bool]$live.cleanup.restored -and
        [bool]$live.cleanup.idempotent
    ) "p14.musician-ability-two.live-purchase-surrender"
}
if ($failures.Count)
{
    throw "Musician Ability II contract failed: " +
        ($failures -join ", ")
}
Write-Host ""
Write-Host "Publish 14.1 Musician Ability II contract passed."
