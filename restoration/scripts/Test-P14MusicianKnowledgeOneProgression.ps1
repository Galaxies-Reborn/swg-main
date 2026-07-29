[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $root "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content (Join-Path $root ([string]$manifest.contracts.p14MusicianKnowledgeOneProgression)) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$fixturePath = Join-Path $source ([string]$contract.sourceFiles.fixture)
$lines = Get-Content $skillPath
$skills = @(@($lines[0]) + @($lines | Select-Object -Skip 2) | ConvertFrom-Csv -Delimiter "`t")
$fixture = Get-Content $fixturePath -Raw
$e = $contract.publish14Evidence.knowledgeOne
$box = @($skills | Where-Object NAME -CEQ ([string]$e.name))
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-C([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}
Write-Host "Publish 14.1 Musician Knowledge I checks:"
Assert-C (
    $box.Count -eq 1 -and
    [string]$box[0].PARENT -ceq [string]$e.parent -and
    [string]$box[0].GRAPH_TYPE -ceq [string]$e.graphType -and
    [string]$box[0].IS_TITLE -ceq [string]$e.isTitle -and
    [string]$box[0].MONEY_REQUIRED -ceq [string]$e.moneyRequired -and
    [string]$box[0].POINTS_REQUIRED -ceq [string]$e.pointsRequired -and
    [string]$box[0].SKILLS_REQUIRED -ceq [string]$e.skillsRequired -and
    [string]$box[0].XP_TYPE -ceq [string]$e.xpType -and
    [string]$box[0].XP_COST -ceq [string]$e.xpCost -and
    [string]$box[0].XP_CAP -ceq [string]$e.xpCap -and
    [string]$box[0].COMMANDS -ceq [string]$e.commands -and
    [string]$box[0].SKILL_MODS -ceq [string]$e.skillMods -and
    [string]$box[0].SCHEMATICS_GRANTED -ceq [string]$e.schematics -and
    [string]$box[0].SEARCHABLE -ceq [string]$e.searchable
) "p14.musician-knowledge-one.skill.authentic"
Assert-C (
    $fixture.Contains("prepareMusicianKnowledgeOne") -and
    $fixture.Contains("purchaseMusicianKnowledgeOne") -and
    $fixture.Contains("observeSurrenderMusicianKnowledgeOne") -and
    $fixture.Contains("NGE_SWING_ABILITY")
) "p14.musician-knowledge-one.fixture-negative-and-reversible"
if ($Expectation -ceq "Ready") {
    $b = $contract.buildEvidence
    $live = $contract.liveEvidence
    $patch = Join-Path $root ([string]$b.overlayPatch -replace "^restoration/", "")
    Assert-C (
        [string]$contract.status -ceq "ready" -and
        (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.overlayPatchSha256 -and
        (Get-FileHash $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.sourceSha256."precu_entertainer_music_one_fixture.java" -and
        (Get-FileHash $skillPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$b.sourceSha256."skills.tab" -and
        [int]$b.clientNativeBuild.protocolVersion -eq 79
    ) "p14.musician-knowledge-one.build.ready-and-hashed"
    Assert-C (
        [bool]$live.purchase.passed -and
        [int]$live.purchase.musicXpBefore -eq 87500 -and
        [int]$live.purchase.pointCost -eq 5 -and
        [int]$live.purchase.musicModifierDeltaAfter -eq 5 -and
        [bool]$live.purchase.balladCommandGranted -and
        -not [bool]$live.purchase.swingCommandGranted -and
        [bool]$live.surrender.musicianNoviceRetained -and
        [int]$live.surrender.pointsRecovered -eq 5 -and
        [int]$live.surrender.musicXpCapAfter -eq 350000 -and
        [bool]$live.cleanup.idempotent
    ) "p14.musician-knowledge-one.live-purchase-surrender"
}
if ($failures.Count) { throw "Musician Knowledge I contract failed: " + ($failures -join ", ") }
Write-Host "Publish 14.1 Musician Knowledge I contract passed."
