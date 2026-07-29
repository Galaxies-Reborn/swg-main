param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$gameRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$buildoutRoot = Join-Path $gameRoot "datatables/buildout"
$scriptRoot = Join-Path $gameRoot "script"

$counts = [ordered]@{
    all = 0
    generic = 0
    custom = 0
    customAttachments = 0
    fountain = 0
    barrel = 0
    unclassified = 0
}
$customScripts = @(
    "event.ewok_festival.loveday_disillusion_blaire_spawner",
    "event.ewok_festival.loveday_cupid_spawner",
    "event.ewok_festival.loveday_cupid_spawner_manager",
    "event.ewok_festival.loveday_romance_target_spawner"
)
Get-ChildItem $buildoutRoot -Recurse -Filter *.tab -File | ForEach-Object {
    foreach ($line in Get-Content $_.FullName)
    {
        if ($line -notmatch '(?i)loveday|love_day|ewok_festival') { continue }
        $counts.all++
        if ($line.Contains("systems.spawning.spawner_area") -or $line.Contains("systems.spawning.spawner_random"))
        {
            $retired = $line.Contains("eventRequired|4|loveday")
            if (-not $retired -and $line -match 'strSpawns\|4\|([^|]+)')
            {
                $retired = $Matches[1].StartsWith("loveday_")
            }
            if ($retired) { $counts.generic++ } else { $counts.unclassified++ }
            continue
        }
        $attachmentCount = 0
        foreach ($scriptName in $customScripts)
        {
            if ($line.Contains($scriptName)) { $attachmentCount++ }
        }
        if ($attachmentCount -gt 0)
        {
            $counts.custom++
            $counts.customAttachments += $attachmentCount
            continue
        }
        if ($line.Contains("object/tangible/storyteller/event_props/pr_love_day_fountain.iff") -and
            $line.Contains("systems.storyteller.events.figrin_dan_band_spawner") -and
            $line.Contains("event.ewok_festival.fountain"))
        {
            $counts.fountain++
            continue
        }
        if ($line.Contains("object/tangible/quest/content/holiday_loveday_barrel.iff") -and
            $line.Contains("quest.task.ground.wave_event_controller"))
        {
            $counts.barrel++
            continue
        }
        $counts.unclassified++
    }
}
if ($counts.all -ne 34 -or $counts.generic -ne 22 -or $counts.custom -ne 6 -or
    $counts.customAttachments -ne 7 -or $counts.fountain -ne 3 -or
    $counts.barrel -ne 3 -or $counts.unclassified -ne 0)
{
    throw "Love Day buildout partition drifted: $($counts | ConvertTo-Json -Compress)"
}

$requiredContracts = @(
    "p14-later-holiday-reward-anchor-retirement.json",
    "p14-later-holiday-control-plane-retirement.json",
    "p14-love-day-custom-spawner-retirement.json",
    "p14-love-day-generic-spawner-retirement.json",
    "p14-love-day-wave-barrel-admission-closure.json"
)
foreach ($contractName in $requiredContracts)
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required Love Day closure is not ready: $contractName"
    }
}

$loveDayScripts = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | Where-Object {
    (Get-Content $_.FullName -Raw) -match '(?i)loveday|love_day|ewok_festival'
})
if ($loveDayScripts.Count -ne 37)
{
    throw "Love Day-bearing server script inventory drifted: expected 37, found $($loveDayScripts.Count)."
}

$holidayController = Get-Content (Join-Path $scriptRoot "event/holiday_controller.java") -Raw
foreach ($required in @(
    'retireHolidayEvent("loveday")',
    'retireLaterHolidayEvent(speaker, "loveday", true)',
    'retireLaterHolidayEvent(speaker, "loveday", false)'
))
{
    if (-not $holidayController.Contains($required))
    {
        throw "Love Day control-plane rejection drifted: $required"
    }
}
$directStarts = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File |
    Select-String -Pattern '\bstartLoveDay\s*\(')
if ($directStarts.Count -ne 0)
{
    throw "A direct Love Day universe-event start remains."
}

$literalGrantFiles = @()
Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | ForEach-Object {
    if (Select-String -LiteralPath $_.FullName -Pattern 'groundquests\.(?:requestGrantQuest|grantQuest)\([^\r\n]*"loveday_[^"]+"' -Quiet)
    {
        $literalGrantFiles += $_.Name
    }
}
$expectedGrantFiles = @(
    "loveday_disillusion_blaire.java",
    "loveday_disillusion_herald.java",
    "loveday_ewok_cardless_child.java",
    "loveday_matchmaker_droid.java",
    "loveday_romance_seeker.java"
)
$actualGrantFileSet = (@($literalGrantFiles | Sort-Object) -join "|")
$expectedGrantFileSet = (@($expectedGrantFiles | Sort-Object) -join "|")
if ($actualGrantFileSet -ne $expectedGrantFileSet)
{
    throw "Love Day literal quest-grant file inventory drifted: $($literalGrantFiles -join ', ')"
}
$chief = Get-Content (Join-Path $scriptRoot "event/ewok_festival/chief.java") -Raw
if (-not $chief.Contains('OBJ_BOUQUET_QUEST = "loveday_flowers_2010"') -or
    -not $chief.Contains("groundquests.requestGrantQuest(speaker, OBJ_BOUQUET_QUEST)"))
{
    throw "The retained chief compatibility grant drifted."
}

$characterBuilder = Get-Content (Join-Path $scriptRoot "terminal/terminal_character_builder.java") -Raw
if (-not $characterBuilder.Contains('"Loveday hearts"') -or
    -not $characterBuilder.Contains('static_item.createNewItemFunction("item_event_loveday_chak_heart", pInv, 100)'))
{
    throw "Privileged character-builder Love Day diagnostic inventory drifted."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-love-day-residual-reference-closure.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or -not $contract.buildEvidence.evidenceOnly -or
        $contract.expected.unclassifiedBuildoutRows -ne 0 -or
        $contract.expected.unclassifiedWorldProducers -ne 0)
    {
        throw "Love Day residual closure evidence is not ready."
    }
    $hashFiles = [ordered]@{
        "corellia_2_3.tab" = Join-Path $buildoutRoot "corellia/corellia_2_3.tab"
        "corellia_loveday.tab" = Join-Path $buildoutRoot "corellia/corellia_loveday.tab"
        "loveday_tyrena.tab" = Join-Path $buildoutRoot "corellia/loveday_tyrena.tab"
        "loveday_endor.tab" = Join-Path $buildoutRoot "endor/loveday_endor.tab"
        "loveday_kaadara.tab" = Join-Path $buildoutRoot "naboo/loveday_kaadara.tab"
        "holiday_controller.java" = Join-Path $scriptRoot "event/holiday_controller.java"
        "spawning.java" = Join-Path $scriptRoot "library/spawning.java"
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
Write-Host "Publish 14.1 Love Day residual-reference closure contract passed."
