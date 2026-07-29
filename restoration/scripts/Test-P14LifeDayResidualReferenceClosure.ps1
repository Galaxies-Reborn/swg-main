param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$serverGame = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$sharedGame = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game"
$scriptRoot = Join-Path $serverGame "script"

foreach ($contractName in @(
    "p14-life-day-lineage-boundary.json",
    "p14-later-life-day-city-spawner-retirement.json",
    "p14-life-day-2004-admission-restoration.json",
    "p14-life-day-2004-quest-state-machine.json",
    "p14-later-life-day-scoreboard-retirement.json",
    "p14-later-life-day-stap-admission-retirement.json",
    "p14-later-life-day-gcw-override-retirement.json",
    "p14-life-day-level-up-loot-retirement.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required Life Day dependency is not ready: $contractName."
    }
}

$targetScripts = @(
    "conversation\lifeday04a.java",
    "conversation\lifeday04b.java",
    "conversation\lifeday04c.java",
    "conversation\lifeday04d.java",
    "conversation\lifeday04e.java",
    "event\holiday_controller.java",
    "event\lifeday\city_spawner.java",
    "event\lifeday\lifeday_spawner.java",
    "npc\celebrity\lifeday_spawner.java",
    "planet\planet_base.java",
    "test\precu_lifeday_2004_fixture.java",
    "test\precu_profession_requirement_fixture.java"
)
$closedLaterScripts = @(
    "conversation\imperial_life_day_vendor.java",
    "conversation\lifeday_vendor.java",
    "conversation\rebel_life_day_vendor.java",
    "conversation\stap_quest_jawa_droid.java",
    "conversation\stap_quest_master_1.java",
    "conversation\stap_quest_master_2.java",
    "conversation\stap_quest_tk555.java",
    "conversation\tatooine_espa_watto.java",
    "event\lifeday\lifeday_objective.java",
    "event\lifeday\lifeday_tree.java",
    "event\planet_event_handler.java",
    "library\spawning.java",
    "systems\buff\buff_handler.java"
)
$compatibilityScripts = @(
    "event\lifeday\lifeday_gift.java",
    "event\lifeday\lifeday_gift_06.java",
    "event\lifeday\monkey_pet.java",
    "event\lifeday\proton_chair.java",
    "library\utils.java"
)
$incidentalScripts = @(
    "conversation\emp_day_imperial_commander.java",
    "conversation\emp_day_imperial_guard.java",
    "conversation\emp_day_reb_colonel.java",
    "event\emp_day\crash_site_requisition.java",
    "event\emp_day\imperial_empty_sign.java",
    "event\emp_day\imperial_recruitment_sign.java",
    "event\emp_day\rebel_empty_sign.java",
    "event\emp_day\rebel_resistance_sign.java",
    "library\holiday.java",
    "player\base\base_player.java",
    "player\player_utility.java",
    "systems\city\city_flag.java"
)
$diagnosticScripts = @(
    "terminal\terminal_character_builder.java",
    "working\dantest.java",
    "working\jhaskell_test.java"
)
$expectedScripts = @(
    $targetScripts + $closedLaterScripts + $compatibilityScripts +
    $incidentalScripts + $diagnosticScripts
) | Sort-Object
$actualScripts = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | Where-Object {
    (Get-Content $_.FullName -Raw) -match '(?i)life_day|lifeday'
} | ForEach-Object {
    $_.FullName.Substring($scriptRoot.Length + 1)
} | Sort-Object)
if ($expectedScripts.Count -ne 45 -or
    (Compare-Object $expectedScripts $actualScripts))
{
    throw "Life Day server-script residual partition drifted."
}

$laterBuildouts = @(
    Join-Path $serverGame "datatables/buildout/corellia/lifeday_doaba_guerfel.tab"
    Join-Path $serverGame "datatables/buildout/talus/lifeday_dearic.tab"
    Join-Path $serverGame "datatables/buildout/tatooine/lifeday_wayfar.tab"
)
$later = [ordered]@{ generic = 0; band = 0; other = 0 }
foreach ($path in $laterBuildouts)
{
    foreach ($line in Get-Content $path | Select-Object -Skip 2)
    {
        $columns = $line -split "`t", -1
        if ($columns[11] -match 'systems\.spawning\.spawner_(area|random)' -and
            $columns[12].Contains("eventRequired|4|life_day"))
        {
            $later.generic++
        }
        elseif ($columns[11].Contains("systems.storyteller.events.figrin_dan_band_spawner") -and
            $columns[11].Contains("event.lifeday.lifeday_tree"))
        {
            $later.band++
        }
        else
        {
            $later.other++
        }
    }
}
if ($later.generic -ne 24 -or $later.band -ne 3 -or $later.other -ne 0)
{
    throw "Later factional Life Day buildout partition drifted."
}

$vendorRows = 0
foreach ($name in @("life_day_faction_vendor.tab", "life_day_faction_vendor_rebel.tab"))
{
    $vendorRows += @(Get-Content (Join-Path $serverGame "datatables/item/vendor/$name") | Select-Object -Skip 2).Count
}
$giftRows = @(Get-Content (Join-Path $serverGame "datatables/event/lifeday/lifeday_gift.tab") | Select-Object -Skip 2)
$giftYears = @($giftRows | ForEach-Object { ($_ -split "`t", -1)[0] })
if ($vendorRows -ne 42 -or $giftRows.Count -ne 7 -or
    (Compare-Object @("2005","2006","2007","2008","2009","2010","2011") $giftYears))
{
    throw "Later Life Day reward-data inventory drifted."
}

$tree = Get-Content (Join-Path $scriptRoot "event/lifeday/lifeday_tree.java") -Raw
$band = Get-Content (Join-Path $scriptRoot "systems/storyteller/events/figrin_dan_band_spawner.java") -Raw
foreach ($lifecycle in @("OnAttach", "OnInitialize"))
{
    $treeMethod = [regex]::Match($tree, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    $bandMethod = [regex]::Match($band, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
    if (-not $treeMethod.Contains('detachScript(self, "event.lifeday.lifeday_tree")') -or
        -not $bandMethod.Contains('detachScript(self, "systems.storyteller.events.figrin_dan_band_spawner")'))
    {
        throw "Later annual gift or vendor producer is no longer inert: $lifecycle."
    }
}
$utilsGrantCallers = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | Where-Object {
    (Get-Content $_.FullName -Raw).Contains("utils.grantGift(")
})
if ($utilsGrantCallers.Count -ne 0)
{
    throw "The dormant 2006 annual-gift helper gained a caller."
}

$buildingSpawns = Join-Path $serverGame "datatables/spawning/building_spawns"
if (@(Get-ChildItem $buildingSpawns -Recurse -Filter *.tab -File |
    Select-String -SimpleMatch "stormtrooper_fat_tk555").Count -ne 0)
{
    throw "A TK-555 normal world producer remains."
}
$gcw = Get-Content (Join-Path $scriptRoot "library/gcw.java") -Raw
$spaceCombat = Get-Content (Join-Path $scriptRoot "library/space_combat.java") -Raw
if ($gcw -match '(?i)life_day|lifeday' -or
    $spaceCombat -match '(?i)life_day|lifeday')
{
    throw "A retired Life Day gameplay-system override remains."
}

$basePlayer = Get-Content (Join-Path $scriptRoot "player/base/base_player.java") -Raw
if ($basePlayer.Contains('setObjVar(self, "lifeday') -or
    -not $basePlayer.Contains('removeObjVar(self, "lifeday")'))
{
    throw "Base-player Life Day residual is not cleanup-only."
}
$holidayController = Get-Content (Join-Path $scriptRoot "event/holiday_controller.java") -Raw
$elder = Get-Content (Join-Path $scriptRoot "conversation/lifeday04b.java") -Raw
if (-not $holidayController.Contains("refreshPrecuLifeDayPlanets(true)") -or
    -not $holidayController.Contains("refreshPrecuLifeDayPlanets(false)") -or
    -not $elder.Contains("lifeday04.convTracker") -or
    -not $elder.Contains("lifeday04.rewarded"))
{
    throw "Original 2004 Life Day route drifted."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-life-day-residual-reference-closure.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or -not $contract.buildEvidence.evidenceOnly -or
        $contract.expected.identifierBearingServerScripts -ne 45 -or
        $contract.expected.unclassifiedNormalWorldProducers -ne 0 -or
        -not $contract.expected.existingObjectCompatibilityRetained -or
        -not $contract.expected.original2004AdmissionRetained -or
        -not $contract.expected.original2004QuestRetained)
    {
        throw "Life Day residual-reference closure evidence is not ready."
    }
    $hashFiles = [ordered]@{
        "lifeday_gift.java" = Join-Path $scriptRoot "event/lifeday/lifeday_gift.java"
        "lifeday_objective.java" = Join-Path $scriptRoot "event/lifeday/lifeday_objective.java"
        "monkey_pet.java" = Join-Path $scriptRoot "event/lifeday/monkey_pet.java"
        "proton_chair.java" = Join-Path $scriptRoot "event/lifeday/proton_chair.java"
        "base_player.java" = Join-Path $scriptRoot "player/base/base_player.java"
        "utils.java" = Join-Path $scriptRoot "library/utils.java"
        "creatures.tab" = Join-Path $serverGame "datatables/mob/creatures.tab"
        "figrin_dan_lifeday.tab" = Join-Path $serverGame "datatables/spawning/holiday/figrin_dan_lifeday.tab"
        "lifeday_gift.tab" = Join-Path $serverGame "datatables/event/lifeday/lifeday_gift.tab"
        "master_item.tab" = Join-Path $serverGame "datatables/item/master_item/master_item.tab"
        "lifeday_stap_1_quest.tab" = Join-Path $sharedGame "datatables/questlist/quest/lifeday_stap_1.tab"
        "lifeday_stap_1_task.tab" = Join-Path $sharedGame "datatables/questtask/quest/lifeday_stap_1.tab"
    }
    foreach ($entry in $hashFiles.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)."
        }
    }
}
Write-Host "Publish 14.1 Life Day residual-reference closure contract passed."
