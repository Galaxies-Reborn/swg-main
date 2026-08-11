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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14AuthoritativeWeaponSpeeds)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param([bool]$Condition, [string]$Name)
    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

function Get-DockerArtifactEvidence
{
    param([string]$Container, [string]$Path)
    $hashOutput = (& docker exec $Container sha256sum $Path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($hashOutput)) { return $null }
    $statOutput = (& docker exec $Container stat -Lc "%s|%i" $Path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($statOutput)) { return $null }
    $statParts = $statOutput.Split('|')
    if ($statParts.Count -ne 2) { return $null }
    return [pscustomobject]@{
        Sha256 = $hashOutput.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[0]
        Bytes = [long]$statParts[0]
        Inode = [long]$statParts[1]
    }
}

function Assert-DockerArtifactSet
{
    param(
        [string]$Container,
        [string]$Root,
        [object]$ArtifactSet,
        [bool]$RequireInode,
        [string]$NamePrefix
    )
    foreach ($property in $ArtifactSet.PSObject.Properties)
    {
        $expected = $property.Value
        $pathProperty = $expected.PSObject.Properties['path']
        $artifactPath = if ($null -ne $pathProperty) { [string]$pathProperty.Value } else { "$Root$($property.Name)" }
        $actual = Get-DockerArtifactEvidence -Container $Container -Path $artifactPath
        $inodeMatches = -not $RequireInode -or ($null -ne $actual -and [long]$expected.inode -eq $actual.Inode)
        Assert-Contract (
            $null -ne $actual -and
            [string]$expected.sha256 -ceq $actual.Sha256 -and
            [long]$expected.bytes -eq $actual.Bytes -and
            $inodeMatches) "$NamePrefix.$($property.Name)"
    }
}

function Get-FunctionSlice
{
    param([string]$Text, [string]$Start, [string]$Next)
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = $paths[[string]$property.Name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.weapon-speed.source.$([IO.Path]::GetFileName($path))"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        Assert-Contract ($sourceHash -ceq [string]$contract.buildEvidence.sourceSha256.([string]$property.Name)) `
            "p14.weapon-speed.source.$([string]$property.Name).authenticated"
    }
}

$speedRows = @(Import-SwgTab -Path $paths.weaponSpeeds)
$familyRows = @($speedRows | Where-Object { [string]$_.templateName -like "__family_*" })
$exactRows = @($speedRows | Where-Object { [string]$_.templateName -notlike "__family_*" })
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths.weaponSpeeds).Hash.ToLowerInvariant()

Write-Host "Publish 14 authoritative weapon-speed checks:"
Assert-Contract ([int]$contract.schemaVersion -eq 2 -and [string]$contract.feature -ceq "p14-authoritative-weapon-speeds") `
    "p14.weapon-speed.contract-identity"
Assert-Contract ([string]$contract.semanticReference.weaponDataPinnedCommit -ceq "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8") "p14.weapon-speed.core3-data-pin"
Assert-Contract ($exactRows.Count -eq 342 -and $familyRows.Count -eq 13 -and $speedRows.Count -eq 355) "p14.weapon-speed.row-cardinality"
Assert-Contract (($speedRows.templateName | Sort-Object -Unique).Count -eq $speedRows.Count) "p14.weapon-speed.unique-templates"
Assert-Contract ($hash -ceq [string]$contract.semanticReference.tableSha256) "p14.weapon-speed.table-hash"

foreach ($expected in $contract.representativeSpeeds.psobject.Properties)
{
    $row = @($speedRows | Where-Object { [string]$_.templateName -ceq [string]$expected.Name })
    Assert-Contract ($row.Count -eq 1 -and [Math]::Abs([double]$row[0].attackSpeed - [double]$expected.Value) -lt 0.000001) "p14.weapon-speed.representative.$([IO.Path]::GetFileNameWithoutExtension([string]$expected.Name))"
}

$weaponObject = Get-Content -LiteralPath $paths.weaponObject -Raw
$weaponHeader = Get-Content -LiteralPath $paths.weaponHeader -Raw
$commandQueue = Get-Content -LiteralPath $paths.commandQueue -Raw
$unarmedDefaultPlayer = Get-Content -LiteralPath $paths.unarmedDefaultPlayer -Raw
$basePlayer = Get-Content -LiteralPath $paths.basePlayer -Raw
$onInitialize = Get-FunctionSlice $basePlayer "public int OnInitialize(" "public int handleJediVisibilityDecay("
$generator = Get-Content -LiteralPath (Join-Path $PSScriptRoot "Export-P14WeaponSpeeds.ps1") -Raw

Assert-Contract ($generator.Contains('6ea64f60ef33b89121c2a8d188b93f4bc6f158e8') -and
    $generator.Contains('Expected 342 positive, unique Core3 weapon speeds')) "p14.weapon-speed.generator-pinned"
Assert-Contract ($generator.Contains('(($lines -join "`n") + "`n")') -and
    -not $generator.Contains('WriteAllLines($output, $lines')) "p14.weapon-speed.generator-canonical-lf"
Assert-Contract ($weaponObject.Contains('cs_precuWeaponSpeedsTable = "datatables/combat/precu_weapon_speeds.iff"') -and
    $weaponObject.Contains('normalizePrecuAttackSpeed') -and
    $weaponObject.Contains('currentSpeed < authoritativeSpeed * 0.5f') -and
    ([regex]::Matches($weaponObject, [regex]::Escape('normalizePrecuAttackSpeed(*this);')).Count -eq 2)) "p14.weapon-speed.object-load-migration"
Assert-Contract ($weaponHeader.Contains('getStoredAttackTime(void) const') -and
    $weaponObject.Contains('float WeaponObject::getAttackTime() const') -and
    $weaponObject.Contains('float const currentSpeed = getStoredAttackTime();') -and
    $weaponObject.Contains('? authoritativeSpeed') -and
    $weaponObject.Contains(': currentSpeed;')) "p14.weapon-speed.runtime-fail-closed-accessor"
Assert-Contract ($commandQueue.Contains('cs_combatDataTable = "datatables/combat/combat_data.iff"') -and
    $commandQueue.Contains('return hitType == -1 || hitType == 6;') -and
    $commandQueue.Contains('speedMultiplier = 1.0f;') -and
    $commandQueue.Contains('weapon->getAttackTime(), speedMultiplier') -and
    -not $commandQueue.Contains('cs_precuWeaponProfilesTable')) "p14.weapon-speed.global-attack-routing"
Assert-Contract ($commandQueue.Contains('(1.0f - static_cast<float>(speedModifier) / 100.0f) *') -and
    $commandQueue.Contains('return executeTime > 1.0f ? executeTime : 1.0f;')) "p14.weapon-speed.core3-formula-and-floor"
Assert-Contract ($commandQueue.Contains('if (!owner.isPlayerControlled())') -and
    $commandQueue.Contains('return 2.0f;') -and
    [string]$contract.queuePolicy.aiAttack -match 'two-second Core3') "p14.weapon-speed.core3-ai-two-second-interval"
Assert-Contract (
    [regex]::Matches($unarmedDefaultPlayer, '(?m)^\s*attackSpeed\s*=\s*2\.0\s*$').Count -eq 1 -and
    [regex]::Matches($unarmedDefaultPlayer, '(?m)^\s*attackSpeed\s*=\s*0\.5(?:0)?\s*$').Count -eq 0 -and
    [double]$contract.authoredDefaultPolicy.unarmedTemplateAttackSpeed -eq 2.0) `
    "p14.weapon-speed.authored-default-unarmed-two-seconds"
Assert-Contract (
    $onInitialize.Contains('object/weapon/melee/unarmed/unarmed_default_player.iff') -and
    -not $onInitialize.Contains('float fltWeaponSpeed = getWeaponAttackSpeed(objWeapon)') -and
    -not $onInitialize.Contains('setWeaponAttackSpeed(objWeapon, 0.50f)') -and
    -not $onInitialize.Contains('fltWeaponSpeed != 0.50f') -and
    -not [bool]$contract.authoredDefaultPolicy.playerInitializationNgeRewrite) `
    "p14.weapon-speed.player-initialization-does-not-rewrite-unarmed-to-nge-speed"

if ($Expectation -in @("Build", "Ready"))
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    Assert-Contract (
        $dsrcPin.Count -eq 1 -and
        $srcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink -and
        [string]$srcPin[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
        "p14.weapon-speed.ready-source-pins"
    Assert-Contract (
        [string]$contract.buildEvidence.deploymentParentCommit -ceq "b4eff3c83f4234f5c1d46237b7cd94f1cf66a001" -and
        [string]$contract.buildEvidence.fullJavaCompile.result -ceq "passed" -and
        [int]$contract.buildEvidence.fullJavaCompile.sourceCount -eq 5717 -and
        [int]$contract.buildEvidence.fullJavaCompile.classCount -eq 5751 -and
        [bool]$contract.buildEvidence.fullJavaCompile.zeroClassDependencyClean -and
        [string]$contract.buildEvidence.result -ceq "passed") `
        "p14.weapon-speed.clean-build-evidence"
    Assert-Contract (
        [string]$contract.buildEvidence.sourceWorkParity.result -ceq "passed" -and
        [int]$contract.buildEvidence.sourceWorkParity.checkedFiles -eq 8 -and
        [int]$contract.buildEvidence.sourceWorkParity.matchedFiles -eq 8) `
        "p14.weapon-speed.source-work-parity-evidence"
    Assert-Contract (
        @($contract.buildEvidence.compiledJavaArtifacts.PSObject.Properties).Count -eq 1 -and
        @($contract.buildEvidence.compiledDataArtifacts.PSObject.Properties).Count -eq 4 -and
        @($contract.buildEvidence.nativeObjectArtifacts.PSObject.Properties).Count -eq 2 -and
        @($contract.buildEvidence.nativeArchiveArtifacts.PSObject.Properties).Count -eq 1) `
        "p14.weapon-speed.artifact-cardinality"

    $container = [string]$contract.deploymentEvidence.container
    Assert-DockerArtifactSet -Container $container -Root "/swg-precu/data/sku.0/sys.server/compiled/game/" `
        -ArtifactSet $contract.buildEvidence.compiledJavaArtifacts -RequireInode $false -NamePrefix "p14.weapon-speed.class"
    Assert-DockerArtifactSet -Container $container -Root "/swg-precu/data/" `
        -ArtifactSet $contract.buildEvidence.compiledDataArtifacts -RequireInode $false -NamePrefix "p14.weapon-speed.iff"
    Assert-DockerArtifactSet -Container $container -Root "" `
        -ArtifactSet $contract.buildEvidence.nativeObjectArtifacts -RequireInode $true -NamePrefix "p14.weapon-speed.native-object"
    Assert-DockerArtifactSet -Container $container -Root "" `
        -ArtifactSet $contract.buildEvidence.nativeArchiveArtifacts -RequireInode $true -NamePrefix "p14.weapon-speed.native-archive"
    $binary = Get-DockerArtifactEvidence -Container $container -Path ([string]$contract.buildEvidence.serverBinary.path)
    Assert-Contract (
        $null -ne $binary -and
        [string]$contract.buildEvidence.serverBinary.sha256 -ceq $binary.Sha256 -and
        [long]$contract.buildEvidence.serverBinary.bytes -eq $binary.Bytes -and
        [long]$contract.buildEvidence.serverBinary.inode -eq $binary.Inode) `
        "p14.weapon-speed.server-binary-identity"
    $binaryFile = (& docker exec $container file -L ([string]$contract.buildEvidence.serverBinary.path) 2>&1 | Out-String)
    $binaryNotes = (& docker exec $container readelf -n ([string]$contract.buildEvidence.serverBinary.path) 2>&1 | Out-String)
    Assert-Contract (
        $LASTEXITCODE -eq 0 -and
        $binaryFile.Contains("ELF 64-bit") -and
        $binaryFile.Contains("x86-64") -and
        $binaryNotes.Contains([string]$contract.buildEvidence.serverBinary.buildIdSha1)) `
        "p14.weapon-speed.server-binary-elf64-build-id"

    $parityMatches = 0
    foreach ($property in $contract.sourceFiles.PSObject.Properties)
    {
        $relativePath = ([string]$property.Value).Replace('\', '/')
        & docker exec $container cmp -s "/swg-precu-source/$relativePath" "/swg-precu/$relativePath"
        if ($LASTEXITCODE -eq 0) { ++$parityMatches }
    }
    Assert-Contract ($parityMatches -eq 8) "p14.weapon-speed.live-source-work-parity"

    $inspection = @((& docker inspect $container 2>&1 | Out-String) | ConvertFrom-Json)[0]
    Assert-Contract (
        [string]$inspection.State.Status -ceq "running" -and
        [string]$inspection.State.Health.Status -ceq [string]$contract.deploymentEvidence.containerHealth -and
        [string]$inspection.State.StartedAt -ceq [string]$contract.deploymentEvidence.containerStartedAt -and
        [string]$contract.deploymentEvidence.result -ceq "passed" -and
        [bool]$contract.deploymentEvidence.clusterReadyForPlayers) `
        "p14.weapon-speed.container-runtime-evidence"
    $gamePids = @(& docker exec $container pgrep -x SwgGameServer)
    $mappedCount = 0
    foreach ($gamePidValue in $gamePids)
    {
        $processIdentity = (& docker exec $container stat -Lc "%i|%s" "/proc/$gamePidValue/exe" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $processIdentity -ceq "$($contract.deploymentEvidence.liveBinaryInode)|$($contract.deploymentEvidence.liveBinarySizeBytes)") { ++$mappedCount }
    }
    Assert-Contract (
        $gamePids.Count -eq [int]$contract.deploymentEvidence.liveGameProcessCount -and
        $mappedCount -eq $gamePids.Count -and
        [bool]$contract.deploymentEvidence.allLiveGameProcessesMatchBinary) `
        "p14.weapon-speed.all-live-processes-map-binary"
    $logs = (& docker logs --since ([string]$contract.deploymentEvidence.containerStartedAt) $container 2>&1 | Out-String)
    $badLogLines = @($logs -split "`n" | Select-String -Pattern "FATAL|SEVERE|Exception|undefined symbol|ORA-|ConGenericMessage constructed with empty message")
    $readyMarkers = @($logs -split "`n" | Select-String -SimpleMatch "Cluster swg is ready for players.")
    Assert-Contract (
        $badLogLines.Count -eq 0 -and
        $readyMarkers.Count -ge 1 -and
        [string]$contract.deploymentEvidence.postStartLogAudit.result -ceq "passed") `
        "p14.weapon-speed.clean-ready-post-start-logs"

    if ($Expectation -eq "Ready")
    {
        Assert-Contract (
            [string]$contract.status -ceq "ready" -and
            [string]$contract.liveAfterEvidence.result -ceq "passed" -and
            $contract.requiredBeforeReady.Count -eq 0) `
            "p14.weapon-speed.ready-evidence"
    }
    else
    {
        Assert-Contract (
            [string]$contract.status -ceq "implemented-build-verified-live-pending" -and
            [string]$contract.liveAfterEvidence.result -ceq "pending" -and
            [bool]$contract.liveAfterEvidence.clientClosedDuringDeploymentEvidenceCapture -and
            $contract.requiredBeforeReady.Count -eq 1) `
            "p14.weapon-speed.build-verified-live-pending-truthful"
    }
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) `
        "p14.weapon-speed.source-status"
    if ([string]$contract.status -ceq "implemented-build-pending")
    {
        Assert-Contract (
            [string]$contract.buildEvidence.result -ceq "pending" -and
            [string]$contract.liveAfterEvidence.result -ceq "pending" -and
            $contract.requiredBeforeReady.Count -gt 0) `
            "p14.weapon-speed.pending-evidence-truthful"
    }
    elseif ([string]$contract.status -ceq "implemented-build-verified-live-pending")
    {
        Assert-Contract (
            [string]$contract.buildEvidence.result -ceq "passed" -and
            [string]$contract.deploymentEvidence.result -ceq "passed" -and
            [string]$contract.liveAfterEvidence.result -ceq "pending" -and
            $contract.requiredBeforeReady.Count -eq 1) `
            "p14.weapon-speed.deployed-evidence-truthful"
    }
}

if ($failures.Count -gt 0)
{
    throw "Publish 14 authoritative weapon-speed contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14 authoritative weapon-speed contract passed."
