param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$serverGame = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$sharedGame = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game"
$scriptRoot = Join-Path $serverGame "script"
$buildoutRoot = Join-Path $serverGame "datatables/buildout"

$areas = @()
Get-ChildItem (Join-Path $sharedGame "datatables/buildout") -Filter "areas_*.tab" -File | ForEach-Object {
    Get-Content $_.FullName | ForEach-Object {
        $columns = $_ -split "`t", -1
        if ($columns.Count -gt 24 -and $columns[24] -eq "lifeday")
        {
            $areas += $columns[0]
        }
    }
}
$expectedAreas = @("lifeday_dearic", "lifeday_doaba_guerfel", "lifeday_mos_espa", "lifeday_wayfar")
if (Compare-Object ($expectedAreas | Sort-Object) ($areas | Sort-Object))
{
    throw "Life Day event-gated area inventory drifted: $($areas -join ', ')."
}

$mosEspaPath = Join-Path $buildoutRoot "tatooine/lifeday_mos_espa.tab"
$mosEspaRows = @(Get-Content $mosEspaPath | Select-Object -Skip 2)
if ($mosEspaRows.Count -ne 38 -or
    @($mosEspaRows | Where-Object {
        $columns = $_ -split "`t", -1
        $columns[2] -eq "object/static/item/item_wrapped_candy.iff" -and -not $columns[11]
    }).Count -ne 38)
{
    throw "Retained 2004 Mos Espa candy route drifted."
}

$orbFiles = @(
    Join-Path $buildoutRoot "dathomir/dathomir_3_2_ws.tab"
    Join-Path $buildoutRoot "endor/endor_4_4_ws.tab"
    Join-Path $buildoutRoot "yavin4/yavin4_4_3_ws.tab"
)
$orbRows = 0
foreach ($path in $orbFiles)
{
    $orbRows += @(Get-Content $path | Where-Object {
        $columns = $_ -split "`t", -1
        $columns[2] -eq "object/tangible/loot/quest/lifeday_orb.iff" -and -not $columns[11]
    }).Count
}
if ($orbRows -ne 6)
{
    throw "Retained 2004 forest-orb inventory drifted: $orbRows."
}

$conversationMap = [ordered]@{
    "lifeday04a.java" = "conversation/lifeday04a"
    "lifeday04b.java" = "conversation/lifeday04b"
    "lifeday04c.java" = "conversation/lifeday04c"
    "lifeday04d.java" = "conversation/lifeday04d"
    "lifeday04e.java" = "conversation/lifeday04e"
}
foreach ($entry in $conversationMap.GetEnumerator())
{
    $text = Get-Content (Join-Path $scriptRoot "conversation/$($entry.Key)") -Raw
    if (-not $text.Contains("c_stringFile = `"$($entry.Value)`"") -or
        -not $text.Contains("lifeday04.convTracker"))
    {
        throw "Retained 2004 conversation lineage drifted: $($entry.Key)."
    }
}
$elderConversation = Get-Content (Join-Path $scriptRoot "conversation/lifeday04b.java") -Raw
foreach ($reward in @(
    "object/tangible/loot/quest/lifeday_orb.iff",
    "object/tangible/painting/painting_wookiee_m.iff",
    "object/tangible/painting/painting_wookiee_f.iff",
    "object/tangible/painting/painting_trees_s01.iff",
    "object/tangible/wearables/wookiee/wke_lifeday_robe.iff"
))
{
    if (-not $elderConversation.Contains($reward))
    {
        throw "Original Life Day reward evidence is missing: $reward."
    }
}

$anchorMap = [ordered]@{
    "wookiee_lifeday_male1.tpf" = "conversation.lifeday04a"
    "wookiee_lifeday_elder.tpf" = "conversation.lifeday04b"
    "wookiee_lifeday_female2.tpf" = "conversation.lifeday04c"
    "wookiee_lifeday_female1.tpf" = "conversation.lifeday04d"
    "wookiee_lifeday_male2.tpf" = "conversation.lifeday04e"
}
$anchorRoot = Join-Path $serverGame "object/tangible/spawning/static_npc"
foreach ($entry in $anchorMap.GetEnumerator())
{
    $text = Get-Content (Join-Path $anchorRoot $entry.Key) -Raw
    if (-not $text.Contains('scripts = [ "npc.celebrity.lifeday_spawner" ]') -or
        -not $text.Contains("`"quest_script`" = `"$($entry.Value)`""))
    {
        throw "Retained 2004 static-NPC anchor drifted: $($entry.Key)."
    }
}

$citySpawnerPath = Join-Path $scriptRoot "event/lifeday/city_spawner.java"
$forestSpawnerPath = Join-Path $scriptRoot "event/lifeday/lifeday_spawner.java"
$celebritySpawnerPath = Join-Path $scriptRoot "npc/celebrity/lifeday_spawner.java"
$citySpawner = Get-Content $citySpawnerPath -Raw
$forestSpawner = Get-Content $forestSpawnerPath -Raw
$celebritySpawner = Get-Content $celebritySpawnerPath -Raw
foreach ($scene in @('"tatooine"', '"corellia"', '"naboo"'))
{
    if (-not $citySpawner.Contains("planetName.equals($scene)"))
    {
        throw "Original Life Day city-spawner scene is missing: $scene."
    }
}
foreach ($scene in @('"dathomir"', '"endor"', '"yavin4"'))
{
    if (-not $forestSpawner.Contains("planetName.equals($scene)"))
    {
        throw "Original Life Day forest-spawner scene is missing: $scene."
    }
}
foreach ($anchor in $anchorMap.Keys)
{
    $template = $anchor.Replace(".tpf", ".iff")
    if (-not ($citySpawner.Contains($template) -or $forestSpawner.Contains($template)))
    {
        throw "Original Life Day anchor spawner omits $template."
    }
}
if (-not $celebritySpawner.Contains('getConfigSetting("EventTeam", "lifeday")') -or
    -not $celebritySpawner.Contains('attachScript(celeb, script)'))
{
    throw "Original Life Day static-NPC materializer drifted."
}

$attachmentPatterns = @("event.lifeday.city_spawner", "event.lifeday.lifeday_spawner")
$templatePaths = @(Get-ChildItem (Join-Path $serverGame "object") -Recurse -Filter *.tpf -File |
    Select-Object -ExpandProperty FullName)
$buildoutPaths = @(Get-ChildItem $buildoutRoot -Recurse -Filter *.tab -File |
    Select-Object -ExpandProperty FullName)
$automaticAttachments = @(
    Select-String -Path ($templatePaths + $buildoutPaths) -Pattern $attachmentPatterns -SimpleMatch |
    Select-Object -ExpandProperty Path -Unique
)
if ($automaticAttachments.Count -ne 0)
{
    throw "Original Life Day automatic-spawner boundary changed."
}

$laterBuildouts = @(
    Join-Path $buildoutRoot "corellia/lifeday_doaba_guerfel.tab"
    Join-Path $buildoutRoot "talus/lifeday_dearic.tab"
    Join-Path $buildoutRoot "tatooine/lifeday_wayfar.tab"
)
$laterCounts = [ordered]@{ all = 0; random = 0; area = 0; tree = 0; unclassified = 0 }
foreach ($path in $laterBuildouts)
{
    foreach ($line in Get-Content $path | Select-Object -Skip 2)
    {
        $laterCounts.all++
        $columns = $line -split "`t", -1
        if ($columns[11] -eq "systems.spawning.spawner_random" -and
            $columns[12].Contains("eventRequired|4|life_day"))
        {
            $laterCounts.random++
        }
        elseif ($columns[11] -eq "systems.spawning.spawner_area" -and
            $columns[12].Contains("eventRequired|4|life_day"))
        {
            $laterCounts.area++
        }
        elseif ($columns[2] -eq "object/tangible/holiday/life_day/main_lifeday_tree.iff" -and
            $columns[11].Contains("event.lifeday.lifeday_tree") -and
            $columns[12].Contains("eventRequired|4|lifeday"))
        {
            $laterCounts.tree++
        }
        else
        {
            $laterCounts.unclassified++
        }
    }
}
if ($laterCounts.all -ne 27 -or $laterCounts.random -ne 6 -or
    $laterCounts.area -ne 18 -or $laterCounts.tree -ne 3 -or
    $laterCounts.unclassified -ne 0)
{
    throw "Later factional Life Day partition drifted: $($laterCounts | ConvertTo-Json -Compress)."
}

$vendorRows = 0
foreach ($file in @("life_day_faction_vendor.tab", "life_day_faction_vendor_rebel.tab"))
{
    $vendorRows += @(Get-Content (Join-Path $serverGame "datatables/item/vendor/$file") | Select-Object -Skip 2).Count
}
if ($vendorRows -ne 42)
{
    throw "Later factional Life Day vendor inventory drifted."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-life-day-lineage-boundary.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or -not $contract.buildEvidence.evidenceOnly -or
        $contract.expected.automaticTargetSpawnerAnchors -ne 0 -or
        -not $contract.expected.targetAdmissionRestorationRequired -or
        -not $contract.expected.lifeDayControlPlaneRetained)
    {
        throw "Life Day lineage-boundary evidence is not ready."
    }
    $hashFiles = [ordered]@{
        "areas_tatooine.tab" = Join-Path $sharedGame "datatables/buildout/areas_tatooine.tab"
        "areas_corellia.tab" = Join-Path $sharedGame "datatables/buildout/areas_corellia.tab"
        "areas_talus.tab" = Join-Path $sharedGame "datatables/buildout/areas_talus.tab"
        "lifeday_mos_espa.tab" = $mosEspaPath
        "lifeday_doaba_guerfel.tab" = $laterBuildouts[0]
        "lifeday_dearic.tab" = $laterBuildouts[1]
        "lifeday_wayfar.tab" = $laterBuildouts[2]
        "city_spawner.java" = $citySpawnerPath
        "lifeday_spawner.java" = $forestSpawnerPath
        "celebrity_lifeday_spawner.java" = $celebritySpawnerPath
        "lifeday04b.java" = Join-Path $scriptRoot "conversation/lifeday04b.java"
    }
    foreach ($entry in $hashFiles.GetEnumerator())
    {
        $actual = (Get-FileHash $entry.Value -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)."
        }
    }
}
Write-Host "Publish 14.1 Life Day lineage-boundary contract passed."
