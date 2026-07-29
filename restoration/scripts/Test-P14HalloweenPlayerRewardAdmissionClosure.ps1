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

$dependency = Get-Content (Join-Path $restorationRoot "contracts/p14-halloween-buildout-admission-closure.json") -Raw | ConvertFrom-Json
if ($dependency.status -ne "ready" -or $dependency.expected.vendorSpawnerRows -ne 2 -or
    $dependency.expected.halloweenStartEntrypoints -ne 0)
{
    throw "Halloween buildout-admission dependency is not ready."
}

$areaFiles = @(
    Join-Path $sharedGame "datatables/buildout/areas_naboo.tab"
    Join-Path $sharedGame "datatables/buildout/areas_tatooine.tab"
)
$buildoutFiles = @(
    Join-Path $serverGame "datatables/buildout/naboo/server_halloween_moenia.tab"
    Join-Path $serverGame "datatables/buildout/tatooine/server_halloween_mos_eisley.tab"
)
$eventAreas = 0
foreach ($path in $areaFiles)
{
    $eventAreas += @(Get-Content $path | Where-Object {
        $columns = $_ -split "`t", -1
        $columns[0] -match '^server_halloween_(moenia|mos_eisley)$' -and $columns[24] -eq "halloween"
    }).Count
}
$vendorSpawners = 0
foreach ($path in $buildoutFiles)
{
    $vendorSpawners += @(Get-Content $path | Where-Object {
        $_ -match 'strSpawns\|4\|halloween_vendor\|'
    }).Count
}
if ($eventAreas -ne 2 -or $vendorSpawners -ne 2)
{
    throw "Halloween vendor world-admission inventory drifted: areas=$eventAreas spawners=$vendorSpawners."
}

$creaturesPath = Join-Path $serverGame "datatables/mob/creatures.tab"
$vendorCreatureRows = @(Get-Content $creaturesPath | Where-Object {
    $columns = $_ -split "`t", -1
    $columns[0] -eq "halloween_vendor" -and
    $_ -match 'string:item\.vendor\.vendor_table=halloween_vendor' -and
    $_ -match 'string:item\.token\.type=item_event_halloween_coin' -and
    $_ -match 'npc\.vendor\.vendor,conversation\.halloween_vendor'
})
if ($vendorCreatureRows.Count -ne 1)
{
    throw "Halloween vendor creature definition drifted."
}

$vendorTablePath = Join-Path $serverGame "datatables/item/vendor/halloween_vendor.tab"
$vendorRows = @(Get-Content $vendorTablePath | Select-Object -Skip 2)
if ($vendorRows.Count -ne 46 -or
    @($vendorRows | Where-Object { $_ -match '2008' }).Count -ne 22 -or
    @($vendorRows | Where-Object { $_ -match '2009' }).Count -ne 6 -or
    @($vendorRows | Where-Object { $_ -match '2010' }).Count -ne 5 -or
    @($vendorRows | Where-Object { $_ -match '2011' }).Count -ne 11)
{
    throw "Post-Publish-14.1 Halloween vendor catalog drifted."
}

$vendorPath = Join-Path $scriptRoot "conversation/halloween_vendor.java"
$vendor = Get-Content $vendorPath -Raw
foreach ($required in @(
    'String[] costumes =',
    '"jawa"',
    '"toydarian"',
    '"hutt_female"',
    '"droid"',
    '"kowakian"',
    'String newCostume = "event_halloween_costume_" + costumes[costumeRandom]',
    'buff.applyBuff(player, newCostume)',
    'static_item.createNewItemFunction("item_event_halloween_trick_device_01_01", inventory)',
    'static_item.createNewItemFunction("item_event_halloween_trick_device_03_01", inventory)',
    'messageTo(npc, "showInventorySUI", d, 0, false)'
))
{
    if (-not $vendor.Contains($required))
    {
        throw "Halloween vendor chain evidence is missing: $required"
    }
}

$buffTablePath = Join-Path $sharedGame "datatables/buff/buff.tab"
$primaryCostumes = @(Get-Content $buffTablePath | Where-Object {
    ($_ -split "`t", -1)[0] -match '^event_halloween_costume_(jawa|toydarian|hutt_female|droid|kowakian)$'
})
if ($primaryCostumes.Count -ne 5)
{
    throw "Primary Halloween costume-buff inventory drifted."
}

$buffHandlerPath = Join-Path $scriptRoot "systems/buff/buff_handler.java"
$buffHandler = Get-Content $buffHandlerPath -Raw
if (-not $buffHandler.Contains('attachScript(self, "event.halloween.trick_or_treater")') -or
    -not $buffHandler.Contains('detachScript(self, "event.halloween.trick_or_treater")'))
{
    throw "Costume effect no longer owns trick-or-treater script lifecycle."
}

$trickOrTreaterPath = Join-Path $scriptRoot "event/halloween/trick_or_treater.java"
$trickOrTreater = Get-Content $trickOrTreaterPath -Raw
foreach ($costume in @("jawa", "toydarian", "hutt_female", "droid", "kowakian"))
{
    if (-not $trickOrTreater.Contains("event_halloween_costume_$costume"))
    {
        throw "Trick-or-treater costume predicate is missing $costume."
    }
}
foreach ($required in @(
    'if (!costumeBuffExists(self))',
    'detachScript(self, "event.halloween.trick_or_treater")',
    'regionName.endsWith("mos_eisley")',
    'regionName.endsWith("moenia")',
    'event_perk.handlePayout(self, target)'
))
{
    if (-not $trickOrTreater.Contains($required))
    {
        throw "Trick-or-treater admission evidence is missing: $required"
    }
}

$eventPerkPath = Join-Path $scriptRoot "library/event_perk.java"
$characterBuilderPath = Join-Path $scriptRoot "terminal/terminal_character_builder.java"
$eventPerk = Get-Content $eventPerkPath -Raw
$characterBuilder = Get-Content $characterBuilderPath -Raw
if ([regex]::Matches($eventPerk, 'createNewItemFunction\("item_event_halloween_coin"').Count -ne 2 -or
    [regex]::Matches($vendor, 'createNewItemFunction\("item_event_halloween_coin"').Count -ne 1 -or
    [regex]::Matches($characterBuilder, 'createNewItemFunction\("item_event_halloween_coin"').Count -ne 1 -or
    -not $vendor.Contains('halloween_vendor_condition_godMode') -or
    -not $characterBuilder.Contains('"Halloween tokens"'))
{
    throw "Halloween coin producer/diagnostic partition drifted."
}

$coinProducerFiles = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | Where-Object {
    (Get-Content $_.FullName -Raw).Contains('createNewItemFunction("item_event_halloween_coin"')
})
$expectedCoinProducers = @(
    "conversation\halloween_vendor.java",
    "library\event_perk.java",
    "terminal\terminal_character_builder.java"
)
$actualCoinProducers = @($coinProducerFiles | ForEach-Object {
    $_.FullName.Substring($scriptRoot.Length + 1)
} | Sort-Object)
if (Compare-Object ($expectedCoinProducers | Sort-Object) $actualCoinProducers)
{
    throw "An unclassified Halloween coin producer exists."
}

$songBookPath = Join-Path $scriptRoot "event/halloween/song_book.java"
$trickDevicePath = Join-Path $scriptRoot "event/halloween/trick_device.java"
$songBook = Get-Content $songBookPath -Raw
$trickDevice = Get-Content $trickDevicePath -Raw
$masterItemPath = Join-Path $serverGame "datatables/item/master_item/master_item.tab"
$masterItem = Get-Content $masterItemPath -Raw
if (-not $songBook.Contains('grantCommand(player, "startMusic+dirge")') -or
    -not $songBook.Contains("destroyObject(self)") -or
    -not $masterItem.Contains("item_event_halloween_song_book") -or
    -not $masterItem.Contains("event.halloween.song_book") -or
    -not $masterItem.Contains("event.halloween.trick_device") -or
    -not $trickDevice.Contains("received_halloween_reward"))
{
    throw "Owned Halloween reward compatibility drifted."
}

$playerStructurePath = Join-Path $scriptRoot "library/player_structure.java"
$playerStructure = Get-Content $playerStructurePath -Raw
if (-not $playerStructure.Contains('item_event_halloween_house_sign') -or
    -not $playerStructure.Contains('item_special_sign_halloween_hanging_sign') -or
    -not $playerStructure.Contains('item_special_sign_halloween_standing_sign'))
{
    throw "Existing Halloween house-sign compatibility drifted."
}

$halloweenQuestTables = @(Get-ChildItem (Join-Path $serverGame "datatables/quest") -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".tab", ".tpf") } |
    Select-String -Pattern 'halloween|galactic moon|gmf_' -CaseSensitive:$false)
if ($halloweenQuestTables.Count -ne 0)
{
    throw "A Halloween quest-table admission path exists."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-halloween-player-reward-admission-closure.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or -not $contract.buildEvidence.evidenceOnly -or
        $contract.expected.survivingNormalAdmissionPaths -ne 0 -or
        -not $contract.expected.existingRewardBehaviorRetained -or
        -not $contract.expected.houseSignCompatibilityRetained -or
        -not $contract.expected.lifeDayAdmissionRetained)
    {
        throw "Halloween player/reward admission evidence is not ready."
    }
    $hashFiles = [ordered]@{
        "halloween_vendor.java" = $vendorPath
        "trick_or_treater.java" = $trickOrTreaterPath
        "trick_device.java" = $trickDevicePath
        "song_book.java" = $songBookPath
        "event_perk.java" = $eventPerkPath
        "buff_handler.java" = $buffHandlerPath
        "terminal_character_builder.java" = $characterBuilderPath
        "halloween_vendor.tab" = $vendorTablePath
        "buff.tab" = $buffTablePath
        "master_item.tab" = $masterItemPath
        "creatures.tab" = $creaturesPath
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
Write-Host "Publish 14.1 Halloween player/reward-admission closure contract passed."
