param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$serverRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$sharedRoot = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game"
$barrelTemplate = "object/tangible/quest/content/holiday_loveday_barrel.iff"

$controllerPath = Join-Path $serverRoot "script/quest/task/ground/wave_event_controller.java"
$controller = Get-Content $controllerPath -Raw
foreach ($required in @(
    'hasScript(player, "quest.task.ground.wave_event_player")',
    'groundquests.playerNeedsToRetrieveThisItem(player, self, TASK_TYPE)',
    'dictionary tasks = groundquests.getActiveTasksForTaskType(player, TASK_TYPE)',
    'String retrieveTemplateName = groundquests.getTaskStringDataEntry(tempQuestCrc, tempTaskId, "SERVER_TEMPLATE")',
    'itemTemplateName.equals(retrieveTemplateName)'
))
{
    if (-not $controller.Contains($required))
    {
        throw "Generic wave-event admission boundary is missing: $required"
    }
}
if ($controller -match '(?i)loveday|love_day|holiday_loveday_barrel')
{
    throw "The shared wave controller contains an event-specific Love Day branch."
}

$buildoutPath = Join-Path $serverRoot "datatables/buildout/corellia/corellia_2_3.tab"
$barrelRows = @(Get-Content $buildoutPath | Where-Object {
    $_.Contains($barrelTemplate) -and $_.Contains("quest.task.ground.wave_event_controller")
})
if ($barrelRows.Count -ne 3)
{
    throw "Love Day barrel buildout inventory drifted: expected 3, found $($barrelRows.Count)."
}

$questRoot = Join-Path $sharedRoot "datatables/questtask/quest"
$questFiles = @(
    "loveday_disillusion_mr_hate.tab",
    "loveday_disillusion_mr_hate_v2.tab",
    "loveday_disillusion_mr_hate_v2_noloot.tab"
)
$matchingTables = @()
foreach ($questFile in $questFiles)
{
    $path = Join-Path $questRoot $questFile
    $rows = @(Get-Content $path | Where-Object {
        $_.Contains("quest.task.ground.wave_event_player") -and $_.Contains($barrelTemplate)
    })
    if ($rows.Count -ne 1)
    {
        throw "$questFile does not contain exactly one Love Day barrel wave task."
    }
    $matchingTables += $questFile
}
$unexpected = @(Get-ChildItem $questRoot -Filter *.tab -File | Where-Object {
    $_.Name -notin $questFiles -and (Get-Content $_.FullName -Raw).Contains($barrelTemplate)
})
if ($unexpected.Count -ne 0)
{
    throw "Unexpected quest tables target the Love Day barrel: $($unexpected.Name -join ', ')"
}

$scriptRoot = Join-Path $serverRoot "script"
$grantHits = @()
Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | ForEach-Object {
    $matches = @(Select-String -LiteralPath $_.FullName -Pattern 'requestGrantQuest\(player, "loveday_disillusion_mr_hate_v2(?:_noloot)?"\)' -AllMatches)
    foreach ($match in $matches)
    {
        foreach ($capture in $match.Matches)
        {
            $grantHits += [pscustomobject]@{ Path = $_.FullName; Value = $capture.Value }
        }
    }
}
$blairePath = Join-Path $scriptRoot "conversation/loveday_disillusion_blaire.java"
if ($grantHits.Count -ne 2 -or @($grantHits | Where-Object { $_.Path -ne $blairePath }).Count -ne 0)
{
    throw "Mr. Hate quest grant inventory drifted: expected two Blaire-only grants, found $($grantHits.Count)."
}
if ((Get-ChildItem $scriptRoot -Recurse -Filter *.java -File |
    Select-String -Pattern 'requestGrantQuest\(player, "loveday_disillusion_mr_hate"\)|grantQuest\(player, "loveday_disillusion_mr_hate"\)').Count -ne 0)
{
    throw "The legacy Mr. Hate quest unexpectedly has a direct grant producer."
}

$spawnerPath = Join-Path $scriptRoot "event/ewok_festival/loveday_disillusion_blaire_spawner.java"
$spawner = Get-Content $spawnerPath -Raw
foreach ($lifecycle in @("OnAttach", "OnInitialize"))
{
    $method = [regex]::Match($spawner, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    if (-not $method.Contains("retireDisillusionSpawner(self)"))
    {
        throw "Blaire producer is not retired at $lifecycle."
    }
}
foreach ($required in @(
    'destroyNearbyTemplate(self, "object/mobile/loveday_ewok_mister_disillusion.iff")',
    'destroyNearbyTemplate(self, "object/tangible/quest/content/holiday_loveday_disillusion_crossbow.iff")',
    'detachScript(self, "event.ewok_festival.loveday_disillusion_blaire_spawner")'
))
{
    if (-not $spawner.Contains($required))
    {
        throw "Blaire retirement helper is missing: $required"
    }
}

if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-love-day-wave-barrel-admission-closure.json"
    $contract = Get-Content $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or -not $contract.buildEvidence.evidenceOnly -or
        $contract.expected.passiveBarrelAnchorsRetained -ne 3 -or
        $contract.expected.matchingQuestTaskTables -ne 3 -or
        $contract.expected.survivingGrantProducers -ne 0 -or
        $contract.expected.loveDayWaveAdmissionReachable)
    {
        throw "Love Day wave-barrel closure evidence is not ready."
    }
    $hashFiles = [ordered]@{
        "wave_event_controller.java" = $controllerPath
        "corellia_2_3.tab" = $buildoutPath
        "loveday_disillusion_mr_hate.tab" = Join-Path $questRoot "loveday_disillusion_mr_hate.tab"
        "loveday_disillusion_mr_hate_v2.tab" = Join-Path $questRoot "loveday_disillusion_mr_hate_v2.tab"
        "loveday_disillusion_mr_hate_v2_noloot.tab" = Join-Path $questRoot "loveday_disillusion_mr_hate_v2_noloot.tab"
        "loveday_disillusion_blaire.java" = $blairePath
        "loveday_disillusion_blaire_spawner.java" = $spawnerPath
    }
    foreach ($entry in $hashFiles.GetEnumerator())
    {
        $actual = (Get-FileHash $entry.Value -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
}
Write-Host "Publish 14.1 Love Day wave-barrel admission closure contract passed."
