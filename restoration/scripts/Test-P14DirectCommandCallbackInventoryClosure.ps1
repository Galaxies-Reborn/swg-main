[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14DirectCommandCallbackInventoryClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$scriptRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/script"
$sharedRoot = Join-Path $dsrc "sku.0/sys.shared/compiled/game/datatables"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Marker)
{
    $start = $Text.IndexOf($Marker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf('{', $start)
    if ($open -lt 0) { return "" }
    $depth = 1
    for ($index = $open + 1; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

function Test-ExactNames($Actual, $Expected)
{
    $actualNames = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)
    $expectedNames = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)
    return $actualNames.Count -eq $expectedNames.Count -and
        (($actualNames -join "`n") -ceq ($expectedNames -join "`n"))
}

$sourceMap = [ordered]@{
    "systems/combat/combat_actions.java" = Join-Path $scriptRoot "systems/combat/combat_actions.java"
    "systems/combat/combat_base.java" = Join-Path $scriptRoot "systems/combat/combat_base.java"
    "library/beast_lib.java" = Join-Path $scriptRoot "library/beast_lib.java"
    "command/command_table.tab" = Join-Path $sharedRoot "command/command_table.tab"
    "combat/combat_data.tab" = Join-Path $sharedRoot "combat/combat_data.tab"
    "skill/skills.tab" = Join-Path $sharedRoot "skill/skills.tab"
    "terminal/terminal_character_builder.java" = Join-Path $scriptRoot "terminal/terminal_character_builder.java"
    "test/qatool.java" = Join-Path $scriptRoot "test/qatool.java"
}
Assert-Contract ($sourceMap.Count -eq [int]$contract.expected.authoritativeSourceFiles) `
    "p14.direct-callback.authoritative-source-count"
foreach ($entry in $sourceMap.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.direct-callback.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $entry.Value -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
            "p14.direct-callback.source.$($entry.Key).authenticated"
    }
}

$combatActions = Get-Content -LiteralPath $sourceMap["systems/combat/combat_actions.java"] -Raw
$handlerPattern = '(?m)^\s*public int (?<name>[A-Za-z0-9_]+)\(obj_id self, obj_id target, String params, float defaultTime\) throws InterruptedException\s*\{'
$handlerRecords = @(
    foreach ($match in [regex]::Matches($combatActions, $handlerPattern))
    {
        $name = $match.Groups['name'].Value
        $body = Get-BracedSurface $combatActions "public int $name(obj_id self, obj_id target, String params, float defaultTime)"
        [pscustomobject]@{
            Name = $name
            Body = $body
            Standard = $body.Contains("combatStandardAction(")
        }
    }
)
$standardRecords = @($handlerRecords | Where-Object Standard)
$directRecords = @($handlerRecords | Where-Object { -not $_.Standard })
Assert-Contract ($handlerRecords.Count -eq [int]$contract.expected.commandSignatureHandlers) `
    "p14.direct-callback.command-handler-count"
Assert-Contract ($standardRecords.Count -eq [int]$contract.expected.standardCombatHandlers) `
    "p14.direct-callback.standard-handler-count"
Assert-Contract ($directRecords.Count -eq [int]$contract.expected.directHandlers) `
    "p14.direct-callback.direct-handler-count"

$precuSystem = @($contract.expected.precuAndSystemHandlers)
$explicitRetired = @($contract.expected.explicitPlayerRetirementHandlers)
$droidRetired = @($contract.expected.droidPlayerRetirementHandlers)
$beastRetired = @($contract.expected.beastPlayerRetirementHandlers)
$retainedContent = @($contract.expected.retainedContentHandlers)
$classified = @($precuSystem + $explicitRetired + $droidRetired + $beastRetired + $retainedContent)
Assert-Contract ((@($classified | Sort-Object -Unique).Count -eq $classified.Count) -and
    (Test-ExactNames $directRecords.Name $classified)) "p14.direct-callback.exact-disjoint-classification"
Assert-Contract (($explicitRetired.Count + $droidRetired.Count + $beastRetired.Count) -eq
    [int]$contract.expected.playerRetiredDirectHandlers) "p14.direct-callback.retired-count"
Assert-Contract ($precuSystem.Count -eq [int]$contract.expected.precuAndSystemDirectHandlers) `
    "p14.direct-callback.precu-system-count"
Assert-Contract ($retainedContent.Count -eq [int]$contract.expected.retainedDirectHandlers) `
    "p14.direct-callback.retained-content-count"
Assert-Contract ([int]$contract.expected.unclassifiedDirectHandlers -eq 0) `
    "p14.direct-callback.unclassified-zero"

$commandRows = @(Import-Csv -Delimiter "`t" -LiteralPath $sourceMap["command/command_table.tab"] | Select-Object -Skip 1)
$rowlessInternal = @($contract.expected.rowlessInternalHandlers)
$failScriptNames = @($contract.expected.failScriptHandlers.PSObject.Properties.Name)
$routingOnly = @($rowlessInternal + $failScriptNames)
$primaryCommandNames = @($classified | Where-Object { $_ -notin $routingOnly })
Assert-Contract ($primaryCommandNames.Count -eq [int]$contract.expected.primaryCommandHandlers) `
    "p14.direct-callback.primary-command-count"
foreach ($name in $primaryCommandNames)
{
    $matches = @($commandRows | Where-Object { [string]$_.scriptHook -ceq [string]$name })
    Assert-Contract ($matches.Count -eq 1 -and [string]$matches[0].commandName -ceq [string]$name) `
        "p14.direct-callback.command-row.$name.exact"
}
foreach ($property in $contract.expected.failScriptHandlers.PSObject.Properties)
{
    $matches = @($commandRows | Where-Object { [string]$_.failScriptHook -ceq [string]$property.Name })
    Assert-Contract ($matches.Count -eq [int]$property.Value) `
        "p14.direct-callback.fail-script-hook.$($property.Name).exact"
}
foreach ($name in $rowlessInternal)
{
    $matches = @($commandRows | Where-Object {
        [string]$_.commandName -ceq [string]$name -or
        [string]$_.scriptHook -ceq [string]$name -or
        [string]$_.failScriptHook -ceq [string]$name
    })
    Assert-Contract ($matches.Count -eq 0) "p14.direct-callback.rowless-internal.$name"
}

foreach ($name in $explicitRetired)
{
    $body = [string]($directRecords | Where-Object Name -CEQ $name).Body
    $gate = $body.IndexOf("isRetired", [System.StringComparison]::Ordinal)
    $override = $body.IndexOf("return SCRIPT_OVERRIDE;", [System.StringComparison]::Ordinal)
    Assert-Contract ($gate -ge 0 -and $override -gt $gate -and $body.Contains('"' + $name + '"')) `
        "p14.direct-callback.explicit-retirement.$name"
}

foreach ($name in $droidRetired)
{
    $body = [string]($directRecords | Where-Object Name -CEQ $name).Body
    $gate = $body.IndexOf("pet_lib.validateDroidCommand(self)", [System.StringComparison]::Ordinal)
    $firstRead = $body.IndexOf("getIntObjVar(", [System.StringComparison]::Ordinal)
    $dispatch = $body.IndexOf("queueCommand(", [System.StringComparison]::Ordinal)
    Assert-Contract ($gate -ge 0 -and $firstRead -gt $gate -and $dispatch -gt $firstRead -and
        $body.Contains("return SCRIPT_OVERRIDE;")) `
        "p14.direct-callback.droid-retirement.$name"
}

$beastLibrary = Get-Content -LiteralPath $sourceMap["library/beast_lib.java"] -Raw
$getBeast = Get-BracedSurface $beastLibrary "public static obj_id getBeastOnPlayer(obj_id player)"
Assert-Contract ($getBeast.IndexOf("isRetiredPostNgeBeastMasterPlayer(player)", [System.StringComparison]::Ordinal) -ge 0 -and
    $getBeast.IndexOf("callable.getCallable", [System.StringComparison]::Ordinal) -gt
        $getBeast.IndexOf("isRetiredPostNgeBeastMasterPlayer(player)", [System.StringComparison]::Ordinal)) `
    "p14.direct-callback.beast-lookup-player-fails-closed"
foreach ($name in $beastRetired)
{
    $body = [string]($directRecords | Where-Object Name -CEQ $name).Body
    Assert-Contract ($body.Contains("beast_lib.getBeastOnPlayer(self)")) `
        "p14.direct-callback.beast-retirement.$name"
}

$neutralize = [string]($directRecords | Where-Object Name -CEQ "sp_neutralize_device_1").Body
$comlink = [string]($directRecords | Where-Object Name -CEQ "gcw_reward_comlink").Body
Assert-Contract ($neutralize.Contains("stealth.canDisarmTrap") -and $neutralize.Contains("stealth.disarmTrap")) `
    "p14.direct-callback.spy-device-content-preserved"
Assert-Contract ($comlink.Contains("faction_perk.executeComlinkReinforcements(self)")) `
    "p14.direct-callback.precu-faction-comlink-preserved"

foreach ($name in @($contract.expected.serverOnlyHeroicHandlers))
{
    $row = @($commandRows | Where-Object { [string]$_.commandName -ceq [string]$name })
    Assert-Contract ($row.Count -eq 1 -and [string]$row[0].fromServerOnly -ceq "1") `
        "p14.direct-callback.heroic-server-only.$name"
}
foreach ($name in @($contract.expected.hothContentHandlers))
{
    $row = @($commandRows | Where-Object { [string]$_.commandName -ceq [string]$name })
    Assert-Contract ($row.Count -eq 1 -and [string]$row[0].toolbarOnly -ceq "1" -and
        [string]::IsNullOrEmpty([string]$row[0].characterAbility)) `
        "p14.direct-callback.hoth-content-boundary.$name"
}
$combatRows = @(Import-Csv -Delimiter "`t" -LiteralPath $sourceMap["combat/combat_data.tab"] | Select-Object -Skip 1)
$retainedCombatNames = @(@($contract.expected.serverOnlyHeroicHandlers) + @($contract.expected.hothContentHandlers))
foreach ($name in $retainedCombatNames)
{
    Assert-Contract (@($combatRows | Where-Object { [string]$_.actionName -ceq [string]$name }).Count -eq 1) `
        "p14.direct-callback.retained-combat-data.$name"
}

$skills = Get-Content -LiteralPath $sourceMap["skill/skills.tab"] -Raw
$characterBuilder = Get-Content -LiteralPath $sourceMap["terminal/terminal_character_builder.java"] -Raw
$qaTool = Get-Content -LiteralPath $sourceMap["test/qatool.java"] -Raw
Assert-Contract (-not $skills.Contains("blueGlowie") -and
    $characterBuilder.Contains('grantCommand(player, "blueGlowie")') -and
    $qaTool.Contains('grantCommand(self, "blueGlowie")')) "p14.direct-callback.blue-glowie-qa-only"

$directCommit = (& git -C $dsrc rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit) `
    "p14.direct-callback.direct-source-pin"
Assert-Contract ([string]$contract.status -in @("source-ready", "ready")) `
    "p14.direct-callback.contract-status"
if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        $contract.requiredBeforeReady.Count -eq 0) "p14.direct-callback.ready-evidence"
}
Assert-Contract (-not (Test-Path -LiteralPath (Join-Path $source "Artifacts")) -and
    -not (Test-Path -LiteralPath (Join-Path $source "Staging"))) "p14.direct-callback.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Direct command callback inventory closure failed: $($failures -join ', ')"
}
Write-Host "Publish 14.1 direct command callback inventory closure passed ($($handlerRecords.Count) handlers, $($directRecords.Count) direct, zero unclassified)."
