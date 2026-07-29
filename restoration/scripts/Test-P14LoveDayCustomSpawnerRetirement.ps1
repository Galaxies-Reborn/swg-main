param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$scriptRoot = "dsrc/sku.0/sys.server/compiled/game/script/event/ewok_festival"
$files = [ordered]@{
    "loveday_cupid_spawner.java" = "event.ewok_festival.loveday_cupid_spawner"
    "loveday_cupid_spawner_manager.java" = "event.ewok_festival.loveday_cupid_spawner_manager"
    "loveday_romance_target_spawner.java" = "event.ewok_festival.loveday_romance_target_spawner"
    "loveday_disillusion_blaire_spawner.java" = "event.ewok_festival.loveday_disillusion_blaire_spawner"
}
$bodies = @{}
foreach ($entry in $files.GetEnumerator())
{
    $source = Join-Path $root "$scriptRoot/$($entry.Key)"
    $body = Get-Content $source -Raw
    $bodies[$entry.Key] = $body
    foreach ($lifecycle in @("OnAttach", "OnInitialize"))
    {
        $method = [regex]::Match($body, "(?s)public int $lifecycle\(.*?(?=\r?\n\s*public)").Value
        if ($method.Contains("messageTo(") -or -not $method.Contains("retire"))
        {
            throw "$($entry.Key) $lifecycle still schedules Love Day work."
        }
    }
    if (-not $body.Contains("detachScript(self, `"$($entry.Value)`")"))
    {
        throw "$($entry.Key) does not detach its exact script."
    }
}

$cupid = $bodies["loveday_cupid_spawner.java"]
foreach ($required in @(
    "despawnHourlyCupidNPCs(self, null)",
    "removeClusterWideData(holiday.LOVEDAY_CUPID_MANAGER_NAME, spawnerId, 0)",
    'if (!hasScript(self, "event.ewok_festival.loveday_cupid_spawner"))'
))
{
    if (-not $cupid.Contains($required)) { throw "Cupid spawner cleanup is missing: $required" }
}
$manager = $bodies["loveday_cupid_spawner_manager.java"]
foreach ($required in @(
    "for (String lovedayLoc : holiday.LOVEDAY_LOCATIONS)",
    "removeClusterWideData(",
    'if (!hasScript(self, "event.ewok_festival.loveday_cupid_spawner_manager"))'
))
{
    if (-not $manager.Contains($required)) { throw "Cupid manager cleanup is missing: $required" }
}
$romance = $bodies["loveday_romance_target_spawner.java"]
foreach ($required in @(
    'cleanupRomanceTargets(self, planet, "loveday_romance_target_male")',
    'cleanupRomanceTargets(self, planet, "loveday_romance_target_female")',
    "destroyObject(target)",
    'if (!hasScript(self, "event.ewok_festival.loveday_romance_target_spawner"))'
))
{
    if (-not $romance.Contains($required)) { throw "Romance-target cleanup is missing: $required" }
}
$blaire = $bodies["loveday_disillusion_blaire_spawner.java"]
foreach ($required in @(
    'destroyNearbyTemplate(self, "object/mobile/loveday_ewok_mister_disillusion.iff")',
    'destroyNearbyTemplate(self, "object/tangible/quest/content/holiday_loveday_disillusion_crossbow.iff")',
    'if (!hasScript(self, "event.ewok_festival.loveday_disillusion_blaire_spawner"))'
))
{
    if (-not $blaire.Contains($required)) { throw "Disillusion-spawner cleanup is missing: $required" }
}

$buildoutRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/datatables/buildout"
$buildoutFiles = @(Get-ChildItem $buildoutRoot -Recurse -Filter "*.tab" | Where-Object {
    (Get-Content $_.FullName -Raw) -match '(?i)loveday|love_day|ewok_festival'
})
$buildoutRows = 0
$customAttachments = 0
foreach ($file in $buildoutFiles)
{
    foreach ($line in Get-Content $file.FullName)
    {
        if ($line -match '(?i)loveday|love_day|ewok_festival') { $buildoutRows++ }
        foreach ($scriptId in $files.Values)
        {
            if ($line.Contains($scriptId)) { $customAttachments++ }
        }
    }
}
if ($buildoutFiles.Count -ne 5 -or $buildoutRows -ne 34 -or $customAttachments -ne 7)
{
    throw "Love Day buildout inventory drifted: tables=$($buildoutFiles.Count), rows=$buildoutRows, custom=$customAttachments."
}

$romanceTables = @(
    "love_day_romance_target_male_corellia.tab",
    "love_day_romance_target_female_corellia.tab",
    "love_day_romance_target_male_naboo.tab",
    "love_day_romance_target_female_naboo.tab"
)
$romanceRows = 0
foreach ($name in $romanceTables)
{
    $table = Get-ChildItem (Join-Path $root "dsrc") -Recurse -Filter $name | Select-Object -First 1
    if ($null -eq $table) { throw "Missing romance-target table: $name" }
    $romanceRows += (Get-Content $table.FullName).Count - 2
}
if ($romanceRows -ne 120) { throw "Romance-target slot inventory drifted: $romanceRows." }

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-love-day-custom-spawner-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or -not $contract.expected.queuedCallbacksFailClosed)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $files.GetEnumerator())
    {
        $actual = (Get-FileHash (Join-Path $root "$scriptRoot/$($entry.Key)") -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/182-p14-love-day-custom-spawner-retirement.patch"
    $actual = (Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item $patch).Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $actual -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 Love Day custom-spawner retirement contract passed."
