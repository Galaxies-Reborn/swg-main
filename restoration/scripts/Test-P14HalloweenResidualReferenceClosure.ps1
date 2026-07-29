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

foreach ($contractName in @(
    "p14-later-holiday-control-plane-retirement.json",
    "p14-halloween-buildout-admission-closure.json",
    "p14-halloween-player-reward-admission-closure.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required Halloween closure is not ready: $contractName"
    }
}

$eventBuildouts = @(
    Join-Path $buildoutRoot "naboo/server_halloween_moenia.tab"
    Join-Path $buildoutRoot "tatooine/server_halloween_mos_eisley.tab"
)
$eventRows = 0
foreach ($path in $eventBuildouts)
{
    $eventRows += @(Get-Content $path | Select-Object -Skip 2).Count
}
if ($eventRows -ne 664)
{
    throw "Halloween event-city row inventory drifted: $eventRows."
}

$outsideBuildoutReferences = @()
Get-ChildItem $buildoutRoot -Recurse -Filter *.tab -File | Where-Object {
    $_.FullName -notin $eventBuildouts
} | ForEach-Object {
    $path = $_.FullName
    Get-Content $path | Where-Object {
        $_ -match '(?i)halloween|galactic moon|gmf_'
    } | ForEach-Object {
        $outsideBuildoutReferences += [pscustomobject]@{ Path = $path; Line = $_ }
    }
}
if ($outsideBuildoutReferences.Count -ne 1 -or
    -not $outsideBuildoutReferences[0].Path.EndsWith("dathomir_1_1.tab") -or
    -not $outsideBuildoutReferences[0].Line.Contains("object/static/halloween/item_skull_candle1.iff"))
{
    throw "Outside-event Halloween buildout boundary drifted."
}
$incidentalColumns = $outsideBuildoutReferences[0].Line -split "`t", -1
if ($incidentalColumns[11])
{
    throw "Incidental Dathomir Halloween prop unexpectedly carries a script."
}

$creaturesPath = Join-Path $serverGame "datatables/mob/creatures.tab"
$halloweenCreatures = @(Get-Content $creaturesPath | Where-Object {
    ($_ -split "`t", -1)[0] -match '^halloween_'
})
if ($halloweenCreatures.Count -ne 2 -or
    @($halloweenCreatures | Where-Object { ($_ -split "`t", -1)[0] -eq "halloween_vendor" }).Count -ne 1 -or
    @($halloweenCreatures | Where-Object { ($_ -split "`t", -1)[0] -eq "halloween_skeleton" }).Count -ne 1)
{
    throw "Halloween creature-definition inventory drifted."
}

$vendorTablePath = Join-Path $serverGame "datatables/item/vendor/halloween_vendor.tab"
$vendorRows = @(Get-Content $vendorTablePath | Select-Object -Skip 2)
if ($vendorRows.Count -ne 46)
{
    throw "Halloween vendor catalog drifted."
}
$masterItemPath = Join-Path $serverGame "datatables/item/master_item/master_item.tab"
$masterItemRows = @(Get-Content $masterItemPath | Where-Object {
    ($_ -split "`t", -1)[0] -match '^item_event_halloween_'
})
if ($masterItemRows.Count -ne 21)
{
    throw "Halloween master-item compatibility inventory drifted: $($masterItemRows.Count)."
}
$buffTablePath = Join-Path $sharedGame "datatables/buff/buff.tab"
$buffRows = @(Get-Content $buffTablePath | Where-Object {
    ($_ -split "`t", -1)[0] -match '^event_halloween_'
})
if ($buffRows.Count -ne 13)
{
    throw "Halloween buff compatibility inventory drifted: $($buffRows.Count)."
}

$expectedScripts = @(
    "conversation\halloween_vendor.java",
    "event\halloween\song_book.java",
    "event\halloween\trick_device.java",
    "event\halloween\trick_or_treater.java",
    "event\holiday_controller.java",
    "library\event_perk.java",
    "library\player_structure.java",
    "player\base\base_player.java",
    "structure\permanent_structure.java",
    "systems\buff\buff_handler.java",
    "terminal\terminal_character_builder.java",
    "working\jhaskell_test.java"
)
$actualScripts = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | Where-Object {
    (Get-Content $_.FullName -Raw) -match '(?i)halloween|galactic moon|gmf_'
} | ForEach-Object {
    $_.FullName.Substring($scriptRoot.Length + 1)
} | Sort-Object)
if (Compare-Object ($expectedScripts | Sort-Object) $actualScripts)
{
    throw "Halloween-bearing server script inventory has an unclassified member."
}

$holidayControllerPath = Join-Path $scriptRoot "event/holiday_controller.java"
$holidayController = Get-Content $holidayControllerPath -Raw
if (-not $holidayController.Contains('retireHolidayEvent("halloween")') -or
    $holidayController.Contains('startUniverseWideEvent("halloween")'))
{
    throw "Halloween control-plane cleanup/rejection classification drifted."
}
$basePlayerPath = Join-Path $scriptRoot "player/base/base_player.java"
$basePlayer = Get-Content $basePlayerPath -Raw
if (-not $basePlayer.Contains('getConfigSetting("GameServer", "halloween")') -or
    -not $basePlayer.Contains("removeObjVar(self, event_perk.COUNTER_TIMESTAMP)") -or
    -not $basePlayer.Contains("removeObjVar(self, event_perk.COUNTER_RESTARTTIME)"))
{
    throw "Base-player Halloween residual is not cleanup-only."
}

$playerStructurePath = Join-Path $scriptRoot "library/player_structure.java"
$permanentStructurePath = Join-Path $scriptRoot "structure/permanent_structure.java"
$playerStructure = Get-Content $playerStructurePath -Raw
$permanentStructure = Get-Content $permanentStructurePath -Raw
if (-not $playerStructure.Contains("revertCustomSign") -or
    -not $playerStructure.Contains("item_special_sign_halloween_hanging_sign") -or
    -not $playerStructure.Contains("item_special_sign_halloween_standing_sign") -or
    -not $permanentStructure.Contains("REMOVING OLD HALLOWEEN SIGN"))
{
    throw "Halloween structure references are not retained sign compatibility."
}

$characterBuilderPath = Join-Path $scriptRoot "terminal/terminal_character_builder.java"
$jhaskellPath = Join-Path $scriptRoot "working/jhaskell_test.java"
$characterBuilder = Get-Content $characterBuilderPath -Raw
$jhaskell = Get-Content $jhaskellPath -Raw
if (-not $characterBuilder.Contains('"Halloween tokens"') -or
    -not $characterBuilder.Contains('createNewItemFunction("item_event_halloween_coin"') -or
    -not $jhaskell.Contains('sendSystemMessageTestingOnly') -or
    -not $jhaskell.Contains('special_sign_halloween_hanging_sign') -or
    $jhaskell.Contains('createNewItemFunction("item_event_halloween'))
{
    throw "Halloween privileged diagnostic classification drifted."
}

$directStarts = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File |
    Select-String -Pattern 'startUniverseWideEvent\("halloween"\)')
if ($directStarts.Count -ne 0)
{
    throw "A direct Halloween universe-event start remains."
}
$questReferences = @(Get-ChildItem (Join-Path $serverGame "datatables/quest") -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".tab", ".tpf") } |
    Select-String -Pattern 'halloween|galactic moon|gmf_' -CaseSensitive:$false)
if ($questReferences.Count -ne 0)
{
    throw "A Halloween quest-table admission path exists."
}

$coinProducerFiles = @(Get-ChildItem $scriptRoot -Recurse -Filter *.java -File | Where-Object {
    (Get-Content $_.FullName -Raw).Contains('createNewItemFunction("item_event_halloween_coin"')
} | ForEach-Object {
    $_.FullName.Substring($scriptRoot.Length + 1)
} | Sort-Object)
$expectedCoinProducerFiles = @(
    "conversation\halloween_vendor.java",
    "library\event_perk.java",
    "terminal\terminal_character_builder.java"
) | Sort-Object
if (Compare-Object $expectedCoinProducerFiles $coinProducerFiles)
{
    throw "An unclassified Halloween coin producer remains."
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-halloween-residual-reference-closure.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or -not $contract.buildEvidence.evidenceOnly -or
        $contract.expected.unclassifiedWorldProducers -ne 0 -or
        -not $contract.expected.passiveTemplateDataRetained -or
        -not $contract.expected.existingRewardCompatibilityRetained -or
        -not $contract.expected.lifeDayAdmissionRetained)
    {
        throw "Halloween residual-reference evidence is not ready."
    }
    $hashFiles = [ordered]@{
        "holiday_controller.java" = $holidayControllerPath
        "base_player.java" = $basePlayerPath
        "player_structure.java" = $playerStructurePath
        "permanent_structure.java" = $permanentStructurePath
        "jhaskell_test.java" = $jhaskellPath
        "no_trade_shared.tab" = Join-Path $serverGame "datatables/no_trade/no_trade_shared.tab"
        "dressed_species_h.tab" = Join-Path $serverGame "datatables/npc_customization/dressed_species_h.tab"
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
Write-Host "Publish 14.1 Halloween residual-reference closure contract passed."
