[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Build", "Ready")]
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
            Standard = $body.Contains("combatStandardAction(") -or
                $body.Contains("performPrecuUnarmedCombo(")
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

foreach ($name in @("forceArmor1", "forceArmor2", "forceShield1", "forceShield2"))
{
    $body = [string]($directRecords | Where-Object Name -CEQ $name).Body
    $delegate = 'jedi.performPrecuForceDefenseCommand(self, "' + $name + '")'
    $delegateIndex = $body.IndexOf($delegate, [StringComparison]::Ordinal)
    $overrideIndex = $body.IndexOf(
        "return SCRIPT_OVERRIDE;", [StringComparison]::Ordinal)
    $continueIndex = $body.IndexOf(
        "return SCRIPT_CONTINUE;", [StringComparison]::Ordinal)
    Assert-Contract ($delegateIndex -ge 0 -and
        ([regex]::Matches($body, [regex]::Escape($delegate))).Count -eq 1 -and
        $overrideIndex -gt $delegateIndex -and
        $continueIndex -gt $overrideIndex) `
        "p14.direct-callback.force-defense.$name.exact-delegate"
}

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
Assert-Contract (@(
        "implemented-build-pending",
        "implemented-build-verified-live-pending",
        "ready") -ccontains [string]$contract.status) `
    "p14.direct-callback.contract-status"
if ($Expectation -in @("Build", "Ready"))
{
    $currentBuild = $contract.currentBuildEvidence
    $canonicalArtifactPaths = [ordered]@{
        "combat_actions.class" = "/swg-precu/data/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.class"
        "command_table.iff" = "/swg-precu/data/sku.0/sys.shared/compiled/game/datatables/command/command_table.iff"
    }
    $parityPaths = @(
        "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java",
        "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java",
        "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
    )
    $artifactProperties = @($currentBuild.compiledArtifacts.PSObject.Properties)
    $artifactNames = @($artifactProperties | ForEach-Object { [string]$_.Name })
    $requiredPathProperties = @(
        $currentBuild.requiredArtifactPaths.PSObject.Properties)
    $requiredPathNames = @($requiredPathProperties |
        ForEach-Object { [string]$_.Name })
    $pathSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    foreach ($property in $requiredPathProperties)
    {
        [void]$pathSet.Add([string]$property.Value)
    }
    $container = [string]$currentBuild.container
    $buildReady = (
        [string]$currentBuild.result -ceq "passed" -and
        [string]$currentBuild.directSourceCommit -ceq $directCommit -and
        [string]$currentBuild.fullJavaCompile.result -ceq "passed" -and
        [string]$currentBuild.sourceWorkParity.result -ceq "passed" -and
        [int]$currentBuild.sourceWorkParity.checkedFiles -eq 3 -and
        [int]$currentBuild.sourceWorkParity.matchedFiles -eq 3 -and
        (Test-ExactNames $currentBuild.sourceWorkParity.files $parityPaths) -and
        @("implemented-build-verified-live-pending", "ready") -ccontains
            [string]$contract.status -and
        (Test-ExactNames $artifactNames $currentBuild.requiredArtifacts) -and
        (Test-ExactNames $requiredPathNames $currentBuild.requiredArtifacts) -and
        (Test-ExactNames $requiredPathNames $canonicalArtifactPaths.Keys) -and
        $pathSet.Count -eq $requiredPathProperties.Count -and
        [string]$currentBuild.compiledDataBuildOwner -ceq
            "p14-nonstandard-profession-matrix-closure" -and
        -not [string]::IsNullOrWhiteSpace($container)
    )
    foreach ($entry in $canonicalArtifactPaths.GetEnumerator())
    {
        $buildReady = $buildReady -and
            [string]$currentBuild.requiredArtifactPaths.($entry.Key) -ceq
                [string]$entry.Value
    }
    foreach ($property in $artifactProperties)
    {
        $expected = $property.Value
        $pathProperty = $expected.PSObject.Properties['path']
        $hashProperty = $expected.PSObject.Properties['sha256']
        $bytesProperty = $expected.PSObject.Properties['bytes']
        if ($null -eq $pathProperty -or $null -eq $hashProperty -or
            $null -eq $bytesProperty)
        {
            $buildReady = $false
            continue
        }
        $artifactPath = if ($canonicalArtifactPaths.Contains(
            [string]$property.Name))
        {
            [string]$canonicalArtifactPaths[[string]$property.Name]
        }
        else { "" }
        if ([string]::IsNullOrWhiteSpace($artifactPath) -or
            [string]$pathProperty.Value -cne $artifactPath)
        {
            $buildReady = $false
            continue
        }
        $hashOutput = (& docker exec $container sha256sum `
            $artifactPath 2>&1 | Out-String).Trim()
        $hashExit = $LASTEXITCODE
        $bytesOutput = (& docker exec $container stat -Lc "%s" `
            $artifactPath 2>&1 | Out-String).Trim()
        $bytesExit = $LASTEXITCODE
        $actualHash = if ([string]::IsNullOrWhiteSpace($hashOutput))
        {
            ""
        }
        else
        {
            $hashOutput.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)[0]
        }
        $buildReady = $buildReady -and
            $hashExit -eq 0 -and $bytesExit -eq 0 -and
            [string]$hashProperty.Value -cmatch '^[a-f0-9]{64}$' -and
            $actualHash -ceq [string]$hashProperty.Value -and
            [long]$bytesProperty.Value -gt 0 -and
            [long]$bytesOutput -eq [long]$bytesProperty.Value
    }
    $binaryPath = "/swg-precu/build/bin/SwgGameServer"
    $binary = $currentBuild.serverBinary
    $binaryHashOutput = (& docker exec $container sha256sum `
        $binaryPath 2>&1 | Out-String).Trim()
    $binaryHashExit = $LASTEXITCODE
    $binaryStatOutput = (& docker exec $container stat -Lc "%s|%i" `
        $binaryPath 2>&1 | Out-String).Trim()
    $binaryStatExit = $LASTEXITCODE
    $binaryFileOutput = (& docker exec $container file -L `
        $binaryPath 2>&1 | Out-String)
    $binaryFileExit = $LASTEXITCODE
    $binaryNotes = (& docker exec $container readelf -n `
        $binaryPath 2>&1 | Out-String)
    $binaryNotesExit = $LASTEXITCODE
    $binaryStat = @($binaryStatOutput -split '\|')
    $actualBinaryHash = if ([string]::IsNullOrWhiteSpace($binaryHashOutput))
    {
        ""
    }
    else
    {
        $binaryHashOutput.Split(
            ' ', [StringSplitOptions]::RemoveEmptyEntries)[0]
    }
    $buildReady = $buildReady -and
        [string]$binary.path -ceq $binaryPath -and
        [string]$binary.sha256 -cmatch '^[a-f0-9]{64}$' -and
        [string]$binary.buildIdSha1 -cmatch '^[a-f0-9]{40}$' -and
        [long]$binary.bytes -gt 0 -and [long]$binary.inode -gt 0 -and
        $binaryHashExit -eq 0 -and $binaryStatExit -eq 0 -and
        $binaryFileExit -eq 0 -and $binaryNotesExit -eq 0 -and
        $binaryStat.Count -eq 2 -and
        $actualBinaryHash -ceq [string]$binary.sha256 -and
        [long]$binaryStat[0] -eq [long]$binary.bytes -and
        [long]$binaryStat[1] -eq [long]$binary.inode -and
        $binaryFileOutput.Contains("ELF 64-bit") -and
        $binaryFileOutput.Contains("x86-64") -and
        $binaryNotes.Contains([string]$binary.buildIdSha1)
    $inspection = @((& docker inspect $container 2>&1 | Out-String) |
        ConvertFrom-Json)[0]
    $buildReady = $buildReady -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$currentBuild.validatedContainerStartedAt) -and
        [string]$inspection.State.StartedAt -ceq
            [string]$currentBuild.validatedContainerStartedAt
    $parityMatches = 0
    foreach ($relativePath in $parityPaths)
    {
        & docker exec $container cmp -s "/swg-precu-source/$relativePath" `
            "/swg-precu/$relativePath"
        if ($LASTEXITCODE -eq 0) { ++$parityMatches }
    }
    $buildReady = $buildReady -and $parityMatches -eq 3
    if ($buildReady)
    {
        & (Join-Path $PSScriptRoot `
            "Test-P14NonstandardProfessionMatrixClosure.ps1") `
            -SourceRoot $source `
            -Expectation Build
        $nonstandardContract = Get-Content -LiteralPath (
            Join-Path $restorationRoot (
                [string]$manifest.contracts.p14NonstandardProfessionMatrixClosure)
        ) -Raw | ConvertFrom-Json
        $ownerArtifact = $nonstandardContract.forceDefenseRestorationEvidence.
            build.compiledArtifacts."command_table.iff"
        $directArtifact = $currentBuild.compiledArtifacts."command_table.iff"
        $buildReady =
            @("implemented-build-verified-live-pending", "ready") -ccontains
                [string]$nonstandardContract.status -and
            [string]$nonstandardContract.forceDefenseRestorationEvidence.
                build.result -ceq "passed" -and
            [string]$ownerArtifact.path -ceq
                [string]$directArtifact.path -and
            [string]$ownerArtifact.sha256 -ceq
                [string]$directArtifact.sha256 -and
            [long]$ownerArtifact.bytes -eq [long]$directArtifact.bytes
    }
    Assert-Contract $buildReady "p14.direct-callback.current-build-and-parity"
}
elseif ([string]$contract.status -ceq "implemented-build-pending")
{
    Assert-Contract (
        [string]$contract.currentBuildEvidence.result -ceq "pending" -and
        [string]$contract.currentBuildEvidence.directSourceCommit -ceq
            $directCommit -and
        [string]$contract.currentBuildEvidence.fullJavaCompile.result -ceq
            "pending" -and
        [string]$contract.currentBuildEvidence.sourceWorkParity.result -ceq
            "pending" -and
        [int]$contract.currentBuildEvidence.sourceWorkParity.checkedFiles -eq 3 -and
        [int]$contract.currentBuildEvidence.sourceWorkParity.matchedFiles -eq 0 -and
        (Test-ExactNames `
            $contract.currentBuildEvidence.sourceWorkParity.files @(
                "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java",
                "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java",
                "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
            )) -and
        [string]$contract.currentDeploymentEvidence.result -ceq "pending" -and
        [string]$contract.currentDeploymentEvidence.directSourceCommit -ceq
            $directCommit -and
        [string]$contract.currentDeploymentEvidence.forceLiveAcceptanceOwner -ceq
            "p14-armor-mitigation-ordering" -and
        [string]$contract.currentDeploymentEvidence.containerHealth -ceq
            "pending" -and
        $contract.requiredBeforeReady.Count -eq 2) `
        "p14.direct-callback.pending-evidence-truthful"
}
if ($Expectation -eq "Ready")
{
    & (Join-Path $PSScriptRoot "Test-P14ArmorMitigationOrdering.ps1") `
        -SourceRoot $source `
        -Expectation Ready
    $armorContract = Get-Content -LiteralPath (
        Join-Path $restorationRoot (
            [string]$manifest.contracts.p14ArmorMitigationOrdering)
    ) -Raw | ConvertFrom-Json
    $deployment = $contract.currentDeploymentEvidence
    $currentBuild = $contract.currentBuildEvidence
    $binary = $currentBuild.serverBinary
    $container = [string]$deployment.container
    $inspection = @((& docker inspect $container 2>&1 | Out-String) |
        ConvertFrom-Json)[0]
    $pidOutput = (& docker exec $container pgrep -f "bin/SwgGameServer" `
        2>&1 | Out-String).Trim()
    $gamePids = @($pidOutput -split '\s+' |
        Where-Object { [string]$_ -cmatch '^[0-9]+$' })
    $mappedCount = 0
    foreach ($gamePid in $gamePids)
    {
        $mappedPath = (& docker exec $container readlink -f `
            "/proc/$gamePid/exe" 2>&1 | Out-String).Trim()
        $mappedStat = (& docker exec $container stat -Lc "%i|%s" `
            "/proc/$gamePid/exe" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and
            $mappedPath -ceq "/swg-precu/build/bin/SwgGameServer" -and
            $mappedStat -ceq "$($binary.inode)|$($binary.bytes)")
        {
            ++$mappedCount
        }
    }
    $logs = (& docker logs --since ([string]$deployment.containerStartedAt) `
        $container 2>&1 | Out-String)
    $logLines = @($logs -split "`n" | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    })
    $badLogLines = @($logLines | Select-String -Pattern (
        "FATAL|SEVERE|Exception|\bERROR\b|database conversion|" +
        "undefined symbol|ORA-|" +
        "ConGenericMessage constructed with empty message"))
    $readyMarkers = @($logLines | Select-String -SimpleMatch
        "Cluster swg is ready for players.")
    Assert-Contract (
        [string]$deployment.result -ceq "passed" -and
        [string]$deployment.directSourceCommit -ceq $directCommit -and
        [string]$deployment.container -ceq [string]$currentBuild.container -and
        [string]$inspection.Id -ceq [string]$deployment.containerId -and
        [string]$inspection.Config.Image -ceq
            [string]$deployment.containerImage -and
        [string]$inspection.Image -ceq [string]$deployment.containerImageId -and
        [string]$inspection.State.Status -ceq "running" -and
        [string]$inspection.State.Health.Status -ceq "healthy" -and
        [string]$deployment.containerHealth -ceq "healthy" -and
        [string]$inspection.State.StartedAt -ceq
            [string]$deployment.containerStartedAt -and
        [string]$deployment.containerStartedAt -ceq
            [string]$currentBuild.validatedContainerStartedAt -and
        [bool]$deployment.clusterReadyForPlayers -and
        $gamePids.Count -gt 0 -and
        $gamePids.Count -eq [int]$deployment.liveGameProcessCount -and
        (Test-ExactNames $gamePids $deployment.liveGameProcessPids) -and
        $mappedCount -eq $gamePids.Count -and
        [bool]$deployment.allLiveGameProcessesMatchBinary -and
        [string]$deployment.liveBinaryPath -ceq
            "/swg-precu/build/bin/SwgGameServer" -and
        [long]$deployment.liveBinaryInode -eq [long]$binary.inode -and
        [long]$deployment.liveBinarySizeBytes -eq [long]$binary.bytes -and
        [string]$deployment.postStartLogAudit.result -ceq "passed" -and
        [int]$deployment.postStartLogAudit.lineCount -gt 0 -and
        $logLines.Count -ge [int]$deployment.postStartLogAudit.lineCount -and
        [int]$deployment.postStartLogAudit.
            fatalSevereExceptionErrorDatabaseConversionUndefinedSymbolOracleOrEmptyGenericMessageMatches -eq 0 -and
        [int]$deployment.postStartLogAudit.playerReadyMarkerCount -ge 1 -and
        $badLogLines.Count -eq 0 -and $readyMarkers.Count -ge 1) `
        "p14.direct-callback.current-same-start-runtime-and-binary"
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "historical-passed" -and
        [string]$contract.currentBuildEvidence.result -ceq "passed" -and
        [string]$contract.currentDeploymentEvidence.result -ceq "passed" -and
        [string]$contract.currentDeploymentEvidence.forceLiveAcceptanceOwner -ceq
            "p14-armor-mitigation-ordering" -and
        [string]$armorContract.status -ceq "ready" -and
        [string]$armorContract.forceDefenseContract.directSourceCommit -ceq
            $directCommit -and
        [string]$armorContract.forceDefenseContract.build.serverBinary.sha256 -ceq
            [string]$binary.sha256 -and
        [string]$armorContract.forceDefenseContract.deployment.containerId -ceq
            [string]$deployment.containerId -and
        [string]$armorContract.forceDefenseContract.deployment.containerImage -ceq
            [string]$deployment.containerImage -and
        [string]$armorContract.forceDefenseContract.deployment.containerImageId -ceq
            [string]$deployment.containerImageId -and
        [string]$armorContract.forceDefenseContract.deployment.containerStartedAt -ceq
            [string]$deployment.containerStartedAt -and
        [int]$armorContract.forceDefenseContract.deployment.liveGameProcessCount -eq
            [int]$deployment.liveGameProcessCount -and
        (Test-ExactNames `
            $armorContract.forceDefenseContract.deployment.liveGameProcessPids `
            $deployment.liveGameProcessPids) -and
        [long]$armorContract.forceDefenseContract.deployment.liveBinaryInode -eq
            [long]$deployment.liveBinaryInode -and
        [long]$armorContract.forceDefenseContract.deployment.liveBinarySizeBytes -eq
            [long]$deployment.liveBinarySizeBytes -and
        [string]$armorContract.forceDefenseContract.live.result -ceq "passed" -and
        $contract.requiredBeforeReady.Count -eq 0) "p14.direct-callback.ready-evidence"
}
Assert-Contract (-not (Test-Path -LiteralPath (Join-Path $source "Artifacts")) -and
    -not (Test-Path -LiteralPath (Join-Path $source "Staging"))) "p14.direct-callback.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Direct command callback inventory closure failed: $($failures -join ', ')"
}
Write-Host "Publish 14.1 direct command callback inventory closure passed ($($handlerRecords.Count) handlers, $($directRecords.Count) direct, zero unclassified)."
