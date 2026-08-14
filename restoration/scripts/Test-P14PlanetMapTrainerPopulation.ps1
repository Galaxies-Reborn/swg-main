[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Source", "Build", "Ready")][string]$Expectation = "Source",
    [string]$Container = "swg-precu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $root "dsrc"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = [string]$manifest.contracts.p14PrecuPlanetMapTrainerAuthority
if ([string]::IsNullOrWhiteSpace($contractPath)) { throw "Planet-map trainer contract is absent from restoration/manifest.json." }
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot $contractPath) -Raw | ConvertFrom-Json

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Get-Source([string]$RelativePath)
{
    $path = Join-Path $dsrc $RelativePath
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "Missing trainer source: $RelativePath"
    return Get-Content -LiteralPath $path -Raw
}

function Get-BracedSurface([string]$Text, [string]$Marker)
{
    $start = $Text.IndexOf($Marker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf('{', $start)
    if ($open -lt 0) { return "" }
    $depth = 1
    for ($index = $open + 1; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

function Test-ExactOrdinalList($Actual, $Expected)
{
    $actualList = [string[]]@($Actual)
    $expectedList = [string[]]@($Expected)
    [Array]::Sort($actualList, [StringComparer]::Ordinal)
    [Array]::Sort($expectedList, [StringComparer]::Ordinal)
    return $actualList.Count -eq $expectedList.Count -and
        (($actualList -join "`n") -ceq ($expectedList -join "`n"))
}

$expectedCommit = "c63df34e9f0a9fbc4e0c267b32aeaadfa1df69dc"
$trainerCommit = "9ddd463d0effcadb33c60c7b27b26cd568192e8a"
$dsrcPins = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($dsrcPins.Count -eq 1 -and [string]$dsrcPins[0].commit -ceq $expectedCommit) `
    "Manifest must pin the immutable planetary-map trainer dsrc commit."
Assert-Contract ([string]$contract.buildEvidence.directSourceCommit -ceq $expectedCommit) `
    "Contract direct-source commit drifted."
$actualCommit = (& git -C $dsrc rev-parse HEAD 2>&1 | Out-String).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and $actualCommit -ceq $expectedCommit) `
    "Checked-out dsrc is not the contracted planetary-map trainer commit."

$commitFiles = @(& git -C $dsrc show --format= --name-only $trainerCommit 2>&1 |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Assert-Contract ($LASTEXITCODE -eq 0 -and
    (Test-ExactOrdinalList $commitFiles @($contract.expected.directSourceChangedFiles))) `
    "Immutable dsrc commit file inventory drifted."

$sourceKeys = @($contract.sourceFiles.psobject.Properties.Name)
$hashKeys = @($contract.buildEvidence.sourceSha256.psobject.Properties.Name)
Assert-Contract (Test-ExactOrdinalList $sourceKeys $hashKeys) `
    "Contract source and SHA-256 key sets must match exactly."
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $root ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "Missing contracted source: $($property.Value)"
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.($property.Name)
    Assert-Contract ($actualHash -ceq $expectedHash) "Source hash drifted: $($property.Value)"
}

# Location authority: Core3 field-map, exact pinned revision used for the 14.1
# city placements below. Coronet and Nashal lack pinned placement records, and
# the P14 Restuss cell is absent from the current buildout topology.
$core3FieldMapPin = "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8"
Assert-Contract ($core3FieldMapPin.Length -eq 40) "Core3 field-map authority pin is not a full SHA."
Assert-Contract ([string]$contract.semanticReference.core3Commit -ceq $core3FieldMapPin) `
    "Core3 placement authority pin drifted."
Assert-Contract (Test-ExactOrdinalList @($contract.expected.noviceTrainerTypes) @(
    "trainer_artisan", "trainer_brawler", "trainer_entertainer", "trainer_marksman", "trainer_medic", "trainer_scout")) `
    "The exact six novice trainer types drifted."

$trainerRoot = "sku.0/sys.server/compiled/game/script/npc/skillteacher"
$spawnContracts = [ordered]@{
    "combat_trainer_spawner.java" = @("spawnMarksman(self);", "spawnScout(self);", "spawnBrawler(self);")
    "commerce_trainer_spawner.java" = @("spawnArtisan(self);")
    "theater_trainer_spawner.java" = @("spawnEntertainer(self);")
    "hospital_trainer_spawner.java" = @("spawnMedic(self);", "spawnMedic2(self);")
    "hospital_02_trainer_spawner.java" = @("spawnMedic(self);")
}
foreach ($entry in $spawnContracts.GetEnumerator())
{
    $text = Get-Source "$trainerRoot/$($entry.Key)"
    $spawnEveryone = Get-BracedSurface $text "public void spawnEveryone("
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($spawnEveryone)) `
        "$($entry.Key) lost spawnEveryone()."
    foreach ($call in $entry.Value)
    {
        Assert-Contract ($spawnEveryone.IndexOf($call, [StringComparison]::Ordinal) -ge 0) `
            "$($entry.Key) lost PRE-CU novice producer call: $call"
    }
}
$addedSpawnerCalls = [Collections.Generic.List[string]]::new()
foreach ($line in @(& git -C $dsrc show --format= --unified=0 $trainerCommit -- `
    "sku.0/sys.server/compiled/game/script/npc/skillteacher/*_trainer_spawner.java" 2>&1))
{
    if ($line -cmatch '^\+\s+(spawn[A-Za-z0-9_]+\(self\);)\s*$')
    {
        $addedSpawnerCalls.Add($Matches[1])
    }
}
Assert-Contract ($LASTEXITCODE -eq 0 -and
    (Test-ExactOrdinalList $addedSpawnerCalls @($contract.expected.restoredNoviceCalls)) -and
    @($contract.expected.restoredEliteCalls).Count -eq 0) `
    "Immutable dsrc change must add exactly eight novice producer calls and no elite producer calls."
$smallHospital = Get-Source "$trainerRoot/hospital_02_trainer_spawner.java"
Assert-Contract ($smallHospital.IndexOf('create.object("trainer_medic"', [StringComparison]::Ordinal) -ge 0 -and
    $smallHospital.IndexOf('create.object("trainer_1hsword"', [StringComparison]::Ordinal) -lt 0) `
    "Small hospital must create the PRE-CU medic trainer, not a one-handed-sword trainer."

$spawnerSource = Get-Source "sku.0/sys.server/compiled/game/script/space/content_tools/npc_spawner.java"
Assert-Contract ($spawnerSource.IndexOf('RANDOM_SHIPWRIGHT_TEMPLATE = "random_space_shipwright_trainer"', [StringComparison]::Ordinal) -ge 0 -and
    $spawnerSource.IndexOf('"object/mobile/space_shipwright_trainer_0" + rand(1, 3) + ".iff"', [StringComparison]::Ordinal) -ge 0) `
    "Shipwright spawner must choose only authentic 01/02/03 appearances at random."
Assert-Contract ($spawnerSource.IndexOf('addPlanetaryMapLocation(self, utils.packStringId(strMapNameId)', [StringComparison]::Ordinal) -ge 0) `
    "Shipwright spawner lost its planetary-map registration path."

$npcTablePath = Join-Path $dsrc "sku.0/sys.server/compiled/game/datatables/space_content/npc_spawners.tab"
$npcRows = @(Get-Content -LiteralPath $npcTablePath -Encoding Default | ConvertFrom-Csv -Delimiter "`t")
$activeIds = @("3795679", "5585426", "1509585", "4295481", "4295476", "1509592", "4295490",
    "3795682", "3795689", "3795696", "8525409", "3725474", "1509584")
$deferredIds = @("1509600", "2636996", "8525413")
Assert-Contract (Test-ExactOrdinalList $activeIds @($contract.expected.activeShipwrightIds)) `
    "The exact 13 active shipwright object IDs drifted."
Assert-Contract (Test-ExactOrdinalList $deferredIds @($contract.expected.deferredShipwrights.psobject.Properties.Value)) `
    "The exact Coronet/Nashal/Restuss deferred boundary drifted."
Assert-Contract ([string]$contract.expected.randomShipwrightTemplate -ceq "random_space_shipwright_trainer" -and
    (Test-ExactOrdinalList @($contract.expected.randomShipwrightVariants) @(
        "object/mobile/space_shipwright_trainer_01.iff",
        "object/mobile/space_shipwright_trainer_02.iff",
        "object/mobile/space_shipwright_trainer_03.iff"))) `
    "The random shipwright template or authentic 01/02/03 variant set drifted."
foreach ($id in $activeIds)
{
    $row = @($npcRows | Where-Object { $_.strObjId -ceq $id })
    Assert-Contract ($row.Count -eq 1 -and
        $row[0].strTemplate -ceq "random_space_shipwright_trainer" -and
        $row[0].strScript1 -ceq "space.content_tools.shipwright_trainer" -and
        $row[0].strScript2 -ceq "npc.skillteacher.skillteacher" -and
        $row[0].strPrimaryCategory -ceq "trainer" -and
        $row[0].strSecondaryCategory -ceq "trainer_shipwright") `
        "Shipwright table contract drifted for object $id."
}
Assert-Contract (@($npcRows | Where-Object { $_.strTemplate -ceq "random_space_shipwright_trainer" }).Count -eq 13) `
    "Exactly 13 authenticated shipwright table rows must be active."
foreach ($id in $deferredIds)
{
    $row = @($npcRows | Where-Object { $_.strObjId -ceq $id })
    Assert-Contract ($row.Count -eq 1 -and $row[0].strTemplate -ceq "unused") `
        "Deferred Coronet/Nashal/Restuss shipwright $id must remain unused."
}

$placements = @(
    @("1509585", "corellia/corellia_6_7_ws.tab", "9665356", "4", "1.28595", "0.639421", "66.8733", "0", "1"),
    @("1509592", "corellia/corellia_3_6_ws.tab", "4255423", "4", "-0.1", "0.6", "67.4", "0.0348995", "0.999391"),
    @("1509584", "corellia/corellia_2_3_ws.tab", "1935687", "4", "0.1", "0.6", "67.2", "0", "1"),
    @("4295481", "naboo/naboo_7_8_ws.tab", "1741539", "4", "5.1", "0.6", "66.6", "0.507538", "0.861629"),
    @("4295476", "naboo/naboo_5_6_ws.tab", "2125382", "4", "-0.5", "0.6", "67.2", "0", "1"),
    @("4295490", "naboo/naboo_7_2_ws.tab", "4215410", "4", "-0.4", "0.6", "67.1", "0.0261769", "-0.999657"),
    @("8525409", "rori/rori_2_3_ws.tab", "4635437", "4", "6.2", "0.6", "67", "0.358368", "-0.93358"),
    @("5585426", "talus/talus_5_3_ws.tab", "3175353", "1", "0.1", "0.6", "73", "1", "0"),
    @("3795679", "tatooine/tatooine_4_3_ws.tab", "1026828", "4", "-3.2", "0.6", "67.9", "0.309017", "0.951057"),
    @("3795682", "tatooine/tatooine_6_2_ws.tab", "1106372", "4", "-3.2", "0.6", "67.6", "0.173648", "0.984808"),
    @("3795689", "tatooine/tatooine_5_6_ws.tab", "4005520", "4", "1", "0.6", "66.7", "0.913545", "0.406737"),
    @("3795696", "tatooine/tatooine_3_6_ws.tab", "1261655", "4", "-3.2", "0.6", "67.7", "0.0261769", "0.999657"),
    @("3725474", "naboo/naboo_2_7.tab", "1692101", "2", "-0.238734", "0.749357", "-71.8383", "-0.0257935", "0.999667")
)
$declaredPlacements = @($placements | ForEach-Object { $_ -join "|" })
$authorityPlacements = @($contract.expected.shipwrightPlacements | ForEach-Object {
    $sourcePath = [string]$contract.sourceFiles.([string]$_.sourceKey)
    $relativePath = $sourcePath.Substring($sourcePath.IndexOf("datatables/buildout/") + 20)
    @([string]$_.id, $relativePath, [string]$_.container, [string]$_.cell,
        [string]$_.x, [string]$_.y, [string]$_.z, [string]$_.qw, [string]$_.qy) -join "|"
})
Assert-Contract ($placements.Count -eq 13 -and
    (Test-ExactOrdinalList $declaredPlacements $authorityPlacements)) `
    "The exact 13 authenticated shipwright placement records drifted."
$buildoutRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/datatables/buildout"
foreach ($placement in $placements)
{
    $path = Join-Path $buildoutRoot $placement[1]
    $rows = @(Get-Content -LiteralPath $path | Where-Object { $_ -match "^$($placement[0])`t" })
    Assert-Contract ($rows.Count -eq 1) "Expected one buildout row for shipwright $($placement[0])."
    $fields = $rows[0].Split("`t")
    Assert-Contract ($fields[1] -ceq $placement[2] -and
        $fields[2] -ceq "object/tangible/space/content_infrastructure/ground_npc_spawner.iff" -and
        $fields[3] -ceq $placement[3] -and $fields[4] -ceq $placement[4] -and
        $fields[5] -ceq $placement[5] -and $fields[6] -ceq $placement[6] -and
        $fields[7] -ceq $placement[7] -and $fields[9] -ceq $placement[8] -and
        $fields[11] -ceq "space.content_tools.npc_spawner") `
        "Authenticated buildout placement drifted for shipwright $($placement[0])."
}
$restussMatches = @(Get-ChildItem -LiteralPath $buildoutRoot -Recurse -File -Filter "*.tab" |
    Select-String -Pattern '^8525413\t')
Assert-Contract ($restussMatches.Count -eq 0) "Restuss shipwright must stay absent from later buildout topology."

$expectedArtifacts = @($contract.expected.compiledJavaClasses) +
    @($contract.expected.compiledDataTables) + @($contract.expected.compiledBuildouts)
Assert-Contract (@($contract.expected.compiledJavaClasses).Count -eq 6 -and
    @($contract.expected.compiledDataTables).Count -eq 1 -and
    @($contract.expected.compiledBuildouts).Count -eq 13 -and
    $expectedArtifacts.Count -eq 20) `
    "Compiled trainer artifact inventory must remain exactly 6 classes, 1 table, and 13 buildouts."

if ($Expectation -in @("Build", "Ready"))
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -ccontains [string]$contract.status) `
        "Build verification requires build-verified or ready contract status."
    Assert-Contract ([string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.fullJavaCompile.result -ceq "passed") `
        "Canonical full Java/data build evidence is not passed."
    Assert-Contract ([string]$contract.buildEvidence.sourceWorkParity.result -ceq "passed" -and
        [int]$contract.buildEvidence.sourceWorkParity.checkedFiles -eq 20 -and
        [int]$contract.buildEvidence.sourceWorkParity.matchedFiles -eq 20) `
        "Exact 20-file source/work parity evidence is not passed."

    $artifactEvidence = @($contract.buildEvidence.compiledArtifacts)
    Assert-Contract (Test-ExactOrdinalList @($artifactEvidence | ForEach-Object { [string]$_.path }) $expectedArtifacts) `
        "Compiled artifact evidence paths do not match the exact contracted inventory."
    foreach ($artifact in $artifactEvidence)
    {
        $relativePath = [string]$artifact.path
        Assert-Contract ([string]$artifact.sha256 -cmatch '^[0-9a-f]{64}$' -and [long]$artifact.bytes -gt 0) `
            "Compiled artifact evidence is incomplete: $relativePath"
        $artifactPath = "/swg-precu/data/$relativePath"
        $identity = (& docker exec $Container sh -c `
            "test -s '$artifactPath' && printf '%s|%s' `$(sha256sum '$artifactPath' | cut -d' ' -f1) `$(stat -Lc %s '$artifactPath')" 2>&1 | Out-String).Trim()
        Assert-Contract ($LASTEXITCODE -eq 0 -and
            $identity -ceq "$([string]$artifact.sha256)|$([long]$artifact.bytes)") `
            "Compiled artifact does not match evidence: $relativePath"
    }

    $parityMatches = 0
    foreach ($relativePath in @($contract.expected.directSourceChangedFiles))
    {
        & docker exec $Container cmp -s "/swg-precu-source/dsrc/$relativePath" "/swg-precu/dsrc/$relativePath"
        if ($LASTEXITCODE -eq 0) { ++$parityMatches }
    }
    Assert-Contract ($parityMatches -eq 20) "Live source/work parity failed for the immutable commit inventory."

    if ($Expectation -eq "Ready")
    {
        $liveFlags = @($contract.liveEvidence.psobject.Properties |
            Where-Object { $_.Name -ne "result" } | ForEach-Object { [bool]$_.Value })
        Assert-Contract ([string]$contract.status -ceq "ready" -and
            [string]$contract.deploymentEvidence.result -ceq "passed" -and
            [string]$contract.deploymentEvidence.containerHealth -ceq "healthy" -and
            [bool]$contract.deploymentEvidence.clusterReadyForPlayers -and
            [int]$contract.deploymentEvidence.liveGameProcessCount -gt 0 -and
            [bool]$contract.deploymentEvidence.allLiveGameProcessesMatchBinary -and
            [string]$contract.liveEvidence.result -ceq "passed" -and
            @($liveFlags | Where-Object { -not $_ }).Count -eq 0 -and
            @($contract.requiredBeforeReady).Count -eq 0) `
            "Ready requires canonical deployment plus complete live map/trainer acceptance."
    }
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -ccontains [string]$contract.status) `
        "Planet-map trainer source status is invalid."
    if ([string]$contract.status -ceq "implemented-build-pending")
    {
        Assert-Contract ([string]$contract.buildEvidence.result -ceq "pending" -and
            [string]$contract.buildEvidence.fullJavaCompile.result -ceq "pending" -and
            [string]$contract.buildEvidence.sourceWorkParity.result -ceq "pending" -and
            [int]$contract.buildEvidence.sourceWorkParity.matchedFiles -eq 0 -and
            @($contract.buildEvidence.compiledArtifacts).Count -eq 0 -and
            [string]$contract.deploymentEvidence.result -ceq "pending" -and
            [string]$contract.liveEvidence.result -ceq "pending" -and
            @($contract.requiredBeforeReady).Count -eq 3) `
            "Implemented-build-pending evidence must remain truthful and fail closed."
    }
}

Write-Host "P14 planetary-map trainer population $Expectation verification passed (13 shipwrights; 3 deferred)."
