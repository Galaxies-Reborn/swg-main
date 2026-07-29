param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$serverGame = Join-Path $root "dsrc/sku.0/sys.server/compiled/game"
$conversationRoot = Join-Path $serverGame "script/conversation"

foreach ($contractName in @(
    "p14-life-day-lineage-boundary.json",
    "p14-life-day-2004-admission-restoration.json"
))
{
    $dependency = Get-Content (Join-Path $restorationRoot "contracts/$contractName") -Raw | ConvertFrom-Json
    if ($dependency.status -ne "ready")
    {
        throw "Required 2004 Life Day dependency is not ready: $contractName."
    }
}

$paths = [ordered]@{}
$source = [ordered]@{}
foreach ($suffix in @("a", "b", "c", "d", "e"))
{
    $name = "lifeday04$suffix.java"
    $paths[$name] = Join-Path $conversationRoot $name
    $source[$name] = Get-Content $paths[$name] -Raw
}

$intro = $source["lifeday04a.java"]
foreach ($required in @(
    'setObjVar(player, "lifeday04.convTracker", 0)',
    '"dathomir"',
    '"endor"',
    '"yavin4"',
    "rand(0, 2)",
    "createWaypointInDatapad"
))
{
    if (-not $intro.Contains($required))
    {
        throw "Life Day introduction/waypoint state drifted: $required."
    }
}

$elder = $source["lifeday04b.java"]
foreach ($required in @(
    "convTracker == 15",
    '"object/tangible/loot/quest/lifeday_orb.iff"',
    '"object/tangible/painting/painting_wookiee_m.iff"',
    '"object/tangible/painting/painting_wookiee_f.iff"',
    '"object/tangible/painting/painting_trees_s01.iff"',
    '"object/tangible/wearables/wookiee/wke_lifeday_robe.iff"',
    "rand(0, 3)",
    'setObjVar(player, "lifeday04.rewarded", 1)',
    'removeObjVar(player, "lifeday04.convTracker")',
    '"full_inv"'
))
{
    if (-not $elder.Contains($required))
    {
        throw "Life Day elder completion/reward state drifted: $required."
    }
}
foreach ($methodName in @(
    "lifeday04b_condition_isOldEnoughNotaWookiee",
    "lifeday04b_condition_isOldEnoughIsaWookiee"
))
{
    $method = [regex]::Match(
        $elder,
        "(?s)public boolean $methodName\(.*?(?=\r?\n\s*public )").Value
    if (-not $method.Contains("int delta = rightNow - timeData") -or
        -not $method.Contains("SPECIES_WOOKIEE") -or
        $method -match "delta\s*(?:<|>|==|!=|<=|>=)")
    {
        throw "Historical Life Day age/species quirk drifted: $methodName."
    }
}
$rewardMethods = @(
    [regex]::Match($elder, "(?s)public void lifeday04b_action_giveRandomGift\(.*?(?=\r?\n\s*public )").Value,
    [regex]::Match($elder, "(?s)public void lifeday04b_action_giveLifeDayRobe\(.*?(?=\r?\n\s*public )").Value
)
foreach ($method in $rewardMethods)
{
    $validIndex = $method.IndexOf("if (isIdValid(createdObject))")
    $rewardedIndex = $method.IndexOf('setObjVar(player, "lifeday04.rewarded", 1)')
    $fullIndex = $method.IndexOf('"full_inv"')
    if ($validIndex -lt 0 -or $rewardedIndex -lt $validIndex -or $fullIndex -lt $rewardedIndex)
    {
        throw "Life Day inventory-full retry boundary drifted."
    }
}

$bitScripts = [ordered]@{
    "lifeday04c.java" = [ordered]@{ bit = 2; terminals = @(3, 7, 11, 15) }
    "lifeday04d.java" = [ordered]@{ bit = 4; terminals = @(5, 7, 13, 15) }
    "lifeday04e.java" = [ordered]@{ bit = 8; terminals = @(9, 11, 13, 15) }
}
foreach ($entry in $bitScripts.GetEnumerator())
{
    $body = $source[$entry.Key]
    if (-not $body.Contains("convTracker += $($entry.Value.bit)") -or
        -not $body.Contains('!hasObjVar(player, "lifeday04.rewarded")'))
    {
        throw "Life Day conversation bit drifted: $($entry.Key)."
    }
    foreach ($terminal in $entry.Value.terminals)
    {
        if (-not $body.Contains("convTracker != $terminal"))
        {
            throw "Life Day duplicate-bit guard drifted: $($entry.Key) / $terminal."
        }
    }
}

$allConversationText = ($source.Values -join "`n")
if ($allConversationText.Contains('removeObjVar(player, "lifeday04.rewarded")'))
{
    throw "The original one-time Life Day reward marker became repeatable."
}

$orbPath = Join-Path $serverGame "object/tangible/loot/quest/lifeday_orb.tpf"
$candyPath = Join-Path $serverGame "object/static/item/item_wrapped_candy.tpf"
$robePath = Join-Path $serverGame "object/tangible/wearables/wookiee/wke_lifeday_robe.tpf"
foreach ($passivePath in @($orbPath, $candyPath))
{
    $body = Get-Content $passivePath -Raw
    if ($body.Contains("scripts =") -or $body.Contains("objvars ="))
    {
        throw "Passive Life Day scenery gained objective behavior: $passivePath."
    }
}

if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-life-day-2004-quest-state-machine.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.expected.completionMask -ne 15 -or
        $contract.expected.randomRewardChoices -ne 4 -or
        $contract.expected.repeatable -or
        -not $contract.expected.inventoryFullRetainsProgress -or
        $contract.expected.candyCollectionObjective -or
        $contract.expected.orbCollectionObjective -or
        $contract.expected.historicalAgeFallbackReachable)
    {
        throw "Life Day 2004 quest-state evidence is not ready."
    }
    $hashPaths = [ordered]@{}
    foreach ($entry in $paths.GetEnumerator())
    {
        $hashPaths[$entry.Key] = $entry.Value
    }
    $hashPaths["lifeday_orb.tpf"] = $orbPath
    $hashPaths["item_wrapped_candy.tpf"] = $candyPath
    $hashPaths["wke_lifeday_robe.tpf"] = $robePath
    foreach ($entry in $hashPaths.GetEnumerator())
    {
        $actual = (Get-FileHash $entry.Value -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)."
        }
    }
}
Write-Host "Publish 14.1 Life Day 2004 quest-state contract passed."
