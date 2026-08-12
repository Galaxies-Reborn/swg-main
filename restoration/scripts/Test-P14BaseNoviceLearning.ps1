[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Source", "Build", "Ready")][string]$Expectation = "Source",
    [string]$Container = "swg-precu"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$restorationRoot = Join-Path $root "restoration"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractRelative = [string]$manifest.contracts.p14PrecuBaseNoviceLearning
if ([string]::IsNullOrWhiteSpace($contractRelative)) {
    throw "Base novice learning contract is absent from restoration/manifest.json."
}
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot $contractRelative) -Raw | ConvertFrom-Json
$dsrc = Join-Path $root "dsrc"
$failures = [Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ExactOrdinalList([object[]]$Actual, [object[]]$Expected) {
    if ($Actual.Count -ne $Expected.Count) { return $false }
    for ($i = 0; $i -lt $Expected.Count; $i++) {
        if ([string]$Actual[$i] -cne [string]$Expected[$i]) { return $false }
    }
    return $true
}

function Read-DataRows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    if ($lines.Count -lt 3) { throw "SWG table is truncated: $Path" }
    $header = $lines[0].Split("`t")
    @($lines[2..($lines.Count - 1)] | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}

function Get-UniqueRow([object[]]$Rows, [string]$Name) {
    $matches = @($Rows | Where-Object NAME -CEQ $Name)
    Assert-Contract ($matches.Count -eq 1) "p14.base-novice.row.$Name.unique"
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
}

function Get-Commands([object]$Row) {
    if ($null -eq $Row) { return @() }
    @(([string]$Row.COMMANDS).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
}

function Get-ContainerEvidence([string]$AbsolutePath) {
    $output = (& docker exec $Container sh -c "test -f '$AbsolutePath' && sha256sum '$AbsolutePath' && stat -Lc '%s' '$AbsolutePath'" 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { return $null }
    $lines = @($output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 2) { return $null }
    $sha = (($lines[0] -split '\s+')[0]).ToLowerInvariant()
    $bytes = 0L
    if (-not [int64]::TryParse($lines[$lines.Count - 1].Trim(), [ref]$bytes)) { return $null }
    [pscustomobject]@{ Sha256 = $sha; Bytes = $bytes }
}

Write-Host "Publish 14.1 / Galaxies Reborn base novice learning checks ($Expectation):"
Assert-Contract ([int]$contract.schemaVersion -eq 1 -and
    [string]$contract.feature -ceq "precu-base-novice-learning" -and
    [bool]$contract.authority.userDirectedOverride -and
    [bool]$contract.authority.publish14BaselinePreserved) "p14.base-novice.contract.identity"

$expectedCommit = [string]$contract.authority.directSourceCommit
Assert-Contract ($expectedCommit -cmatch '^[0-9a-f]{40}$' -and
    [string]$contract.buildEvidence.directSourceCommit -ceq $expectedCommit) "p14.base-novice.pin.full-immutable-dsrc-sha"
$pins = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($pins.Count -eq 1 -and [string]$pins[0].commit -ceq $expectedCommit) "p14.base-novice.pin.manifest-parity"
$checkedOutCommit = (& git -C $dsrc rev-parse HEAD 2>&1 | Out-String).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and $checkedOutCommit -ceq $expectedCommit) "p14.base-novice.pin.checked-out-parity"
$dsrcStatus = (& git -C $dsrc status --porcelain=v1 2>&1 | Out-String).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and [string]::IsNullOrEmpty($dsrcStatus)) "p14.base-novice.pin.clean-dsrc-worktree"
$commitFiles = @(& git -C $dsrc show --format= --name-only $expectedCommit 2>&1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Assert-Contract ($LASTEXITCODE -eq 0 -and
    (Test-ExactOrdinalList $commitFiles @($contract.authority.directSourceChangedFiles))) "p14.base-novice.pin.exact-three-file-owner"

$paths = @{}
$sourceKeys = @($contract.sourceFiles.psobject.Properties.Name)
$hashKeys = @($contract.buildEvidence.sourceSha256.psobject.Properties.Name)
Assert-Contract (Test-ExactOrdinalList $sourceKeys $hashKeys) "p14.base-novice.source.hash-key-parity"
foreach ($property in $contract.sourceFiles.psobject.Properties) {
    $key = [string]$property.Name
    $path = Join-Path $root ([string]$property.Value)
    $paths[$key] = $path
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Assert-Contract $exists "p14.base-novice.source.$key.exists"
    if ($exists) {
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.$key
        Assert-Contract ($expectedHash -cmatch '^[0-9a-f]{64}$' -and
            (Get-Sha256 $path) -ceq $expectedHash) "p14.base-novice.source.$key.exact-hash"
    }
}
if ($failures.Count -gt 0) {
    throw "Publish 14.1 base novice learning contract failed: $($failures -join ', ')"
}

$skills = Read-DataRows $paths.skillTable
$qualification = $contract.expected.baseNoviceQualification
foreach ($skillName in @($contract.expected.baseNoviceSkills)) {
    $row = Get-UniqueRow $skills ([string]$skillName)
    if ($null -ne $row) {
        Assert-Contract ([string]$row.GRAPH_TYPE -ceq [string]$qualification.graphType -and
            [int]$row.MONEY_REQUIRED -eq [int]$qualification.moneyRequired -and
            [int]$row.POINTS_REQUIRED -eq [int]$qualification.pointsRequired -and
            [string]$row.SKILLS_REQUIRED -ceq [string]$qualification.skillsRequired -and
            [string]$row.XP_TYPE -ceq [string]$qualification.xpType -and
            [int]$row.XP_COST -eq [int]$qualification.xpCost -and
            [int]$row.XP_CAP -eq [int]$qualification.xpCap) "p14.base-novice.qualification.$skillName.no-xp"
    }
}

$artisan = Get-UniqueRow $skills "crafting_artisan_novice"
$brawler = Get-UniqueRow $skills "combat_brawler_novice"
$marksman = Get-UniqueRow $skills "combat_marksman_novice"
$artisanCommands = @(Get-Commands $artisan)
$brawlerCerts = @(Get-Commands $brawler | Where-Object { $_.StartsWith("cert_") })
$marksmanCerts = @(Get-Commands $marksman | Where-Object { $_.StartsWith("cert_") })
Assert-Contract (Test-ExactOrdinalList $artisanCommands @($contract.expected.artisanCommands)) "p14.base-novice.artisan.sample-survey-exact"
Assert-Contract (Test-ExactOrdinalList $brawlerCerts @($contract.expected.brawlerCertifications)) "p14.base-novice.brawler.wood-staff-heavy-axe-survival-knife-exact"
Assert-Contract (Test-ExactOrdinalList $marksmanCerts @($contract.expected.marksmanCertifications)) "p14.base-novice.marksman.cdef-pistol-rifle-carbine-exact"
Assert-Contract ("cert_knife_dagger" -cnotin $brawlerCerts) "p14.base-novice.brawler.no-dagger-substitution"

$advancedExpected = $contract.expected.advancedNoviceControl
$advanced = Get-UniqueRow $skills ([string]$advancedExpected.name)
if ($null -ne $advanced) {
    Assert-Contract ([int]$advanced.MONEY_REQUIRED -eq [int]$advancedExpected.moneyRequired -and
        [int]$advanced.POINTS_REQUIRED -eq [int]$advancedExpected.pointsRequired -and
        [string]$advanced.SKILLS_REQUIRED -ceq [string]$advancedExpected.skillsRequired -and
        [string]$advanced.XP_TYPE -ceq [string]$advancedExpected.xpType -and
        [int]$advanced.XP_COST -eq [int]$advancedExpected.xpCost -and
        [int]$advanced.XP_CAP -eq [int]$advancedExpected.xpCap) "p14.base-novice.advanced-pistoleer-boundary-retained"
}

$xpLimits = Read-DataRows $paths.xpLimitTable
$phaseA = $contract.expected.phaseA
$xpLimitRows = @($xpLimits | Where-Object NAME -CEQ ([string]$phaseA.xpType))
$engineering = Get-UniqueRow $skills ([string]$phaseA.engineeringSkill)
Assert-Contract ($xpLimitRows.Count -eq 1 -and [int]$xpLimitRows[0].LIMIT -eq [int]$phaseA.prepurchaseXpCap) "p14.base-novice.phase-a.default-crafting-xp-cap-1000"
if ($null -ne $engineering) {
    Assert-Contract ([string]$engineering.SKILLS_REQUIRED -ceq "crafting_artisan_novice" -and
        [string]$engineering.XP_TYPE -ceq [string]$phaseA.xpType -and
        [int]$engineering.XP_COST -eq [int]$phaseA.engineeringXpCost -and
        [int]$engineering.XP_CAP -eq [int]$phaseA.engineeringXpCap) "p14.base-novice.phase-a.engineering-one-advanced-cost-retained"
}
$skillTeacher = Get-Content -LiteralPath $paths.skillTeacher -Raw
$phaseARuntime = Get-Content -LiteralPath $paths.phaseARuntime -Raw
foreach ($javaSource in @($skillTeacher, $phaseARuntime)) {
    Assert-Contract ($javaSource.Contains('"private_artisan_novice"') -and
        $javaSource.Contains('"sample"') -and
        $javaSource.Contains('"survey"') -and
        $javaSource.Contains('"private_artisan_engineering_1"')) "p14.base-novice.phase-a.java-complete-command-vector"
}
Assert-Contract ($skillTeacher.Contains("PRECU_PREPURCHASE_XP_CAP = 1000") -and
    -not $skillTeacher.Contains("PRECU_PREPURCHASE_XP_CAP = 1500")) "p14.base-novice.phase-a.skillteacher-prepurchase-cap"
Assert-Contract ($phaseARuntime -match 'preCap\s*==\s*1000' -and
    $phaseARuntime -notmatch 'preCap\s*==\s*1500') "p14.base-novice.phase-a.runtime-prepurchase-cap"

if ($failures.Count -gt 0) {
    throw "Publish 14.1 base novice learning contract failed: $($failures -join ', ')"
}

if ($Expectation -in @("Build", "Ready")) {
    & docker inspect $Container *> $null
    Assert-Contract ($LASTEXITCODE -eq 0) "p14.base-novice.build.container-exists"
    $workDir = (& docker exec $Container printenv SWG_WORK_DIR 2>&1 | Out-String).Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $workDir.StartsWith("/")) "p14.base-novice.build.work-directory"

    $parityKeys = @($contract.buildEvidence.canonicalBuild.sourceWorkParity.requiredSourceKeys)
    Assert-Contract (Test-ExactOrdinalList $parityKeys $sourceKeys) "p14.base-novice.build.source-work-required-set"
    $matched = 0
    foreach ($key in $parityKeys) {
        $sourceRelative = [string]$contract.sourceFiles.$key
        $workRelative = $sourceRelative.Substring("dsrc/".Length)
        $workPath = "$workDir/dsrc/$workRelative"
        $workEvidence = Get-ContainerEvidence $workPath
        $parity = $null -ne $workEvidence -and $workEvidence.Sha256 -ceq (Get-Sha256 $paths[$key])
        if ($parity) { $matched++ }
        Assert-Contract $parity "p14.base-novice.build.source-work-parity.$key"
    }
    Assert-Contract ([string]$contract.buildEvidence.canonicalBuild.sourceWorkParity.result -ceq "passed" -and
        $matched -eq $parityKeys.Count) "p14.base-novice.build.source-work-parity-recorded"

    $artifactPaths = @($contract.buildEvidence.canonicalBuild.compiledArtifacts | ForEach-Object { [string]$_.path })
    $requiredArtifactPaths = @(
        "sku.0/sys.shared/compiled/game/datatables/skill/skills.iff",
        "sku.0/sys.server/compiled/game/script/npc/skillteacher/skillteacher.class",
        "sku.0/sys.server/compiled/game/script/test/precu_phase_a_runtime.class"
    )
    Assert-Contract (Test-ExactOrdinalList $artifactPaths $requiredArtifactPaths) "p14.base-novice.build.exact-artifact-set"
    foreach ($artifact in @($contract.buildEvidence.canonicalBuild.compiledArtifacts)) {
        $artifactPath = [string]$artifact.path
        $evidence = Get-ContainerEvidence "$workDir/data/$artifactPath"
        if ($null -ne $evidence) {
            Write-Host "  [CAPTURE] $artifactPath|bytes=$($evidence.Bytes)|sha256=$($evidence.Sha256)"
        }
        $pinned = [int64]$artifact.bytes -gt 0 -and [string]$artifact.sha256 -cmatch '^[0-9a-f]{64}$'
        Assert-Contract $pinned "p14.base-novice.build.artifact.$artifactPath.evidence-pinned"
        Assert-Contract ($pinned -and $null -ne $evidence -and
            [int64]$artifact.bytes -eq [int64]$evidence.Bytes -and
            [string]$artifact.sha256 -ceq [string]$evidence.Sha256) "p14.base-novice.build.artifact.$artifactPath.exact-identity"
    }
    Assert-Contract ([string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.canonicalBuild.result -ceq "passed") "p14.base-novice.build.canonical-result-recorded"
}

if ($Expectation -ceq "Ready") {
    $deployment = $contract.deploymentEvidence
    $live = $contract.liveEvidence
    $payload = $contract.liveAcceptancePayload
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0) "p14.base-novice.ready.status"
    Assert-Contract ([string]$deployment.result -ceq "passed" -and
        [string]$deployment.directSourceCommit -ceq $expectedCommit -and
        [string]$deployment.deploymentParentCommit -cmatch '^[0-9a-f]{40}$' -and
        [string]$deployment.container -ceq $Container -and
        [string]$deployment.containerId -cmatch '^[0-9a-f]{64}$' -and
        [bool]$deployment.clusterReadyForPlayers -and
        [int]$deployment.liveGameProcessCount -gt 0 -and
        [bool]$deployment.allLiveGameProcessesMatchBinary) "p14.base-novice.ready.deployment"
    Assert-Contract ([string]$payload.id -ceq "p14-base-novice-single-player-reversible-v1" -and
        [string]$payload.result -ceq "passed" -and [bool]$payload.identityBound -and
        [int]$payload.boundedSeconds -le 300 -and @($payload.steps).Count -eq 5) "p14.base-novice.ready.acceptance-payload"
    Assert-Contract ([string]$live.result -ceq "passed" -and
        [string]$live.payloadId -ceq [string]$payload.id -and
        [int64]$live.playerOid -gt 0 -and [int64]$live.stationId -gt 0 -and
        [string]$live.characterName -cne "pending" -and
        [string]$live.testedSkill -cin @($contract.expected.baseNoviceSkills) -and
        [string]$live.xpBefore -cne "pending" -and
        [string]$live.xpAfterPurchase -ceq [string]$live.xpBefore -and
        [int]$live.pointsAfterPurchase -eq [int]$live.pointsBefore - 15 -and
        [int64]$live.creditsAfterPurchase -eq [int64]$live.creditsBefore - 100 -and
        [string]$live.cleanupResult -ceq "passed" -and
        [bool]$live.serverHealthyAfterCleanup) "p14.base-novice.ready.identity-bound-live-proof"
}

if ($failures.Count -gt 0) {
    throw "Publish 14.1 base novice learning contract failed: $($failures -join ', ')"
}
Write-Host "Publish 14.1 / Galaxies Reborn base novice learning contract passed ($Expectation)."
