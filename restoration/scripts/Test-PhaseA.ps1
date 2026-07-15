[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Baseline", "Ready")]
    [string]$Expectation = "Baseline"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$superprojectRoot = Split-Path -Parent $restorationRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force

$manifest = Get-RestorationManifest -RestorationRoot $restorationRoot
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.phaseA)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = Resolve-NormalizedPath -Path $SourceRoot

$canonicalFingerprint = $contract.runtimeVerticalSlice.materializationFingerprint
$canonicalFingerprintAlgorithm = [string]$canonicalFingerprint.algorithm
$canonicalFingerprintPlaceholder = [string]$canonicalFingerprint.placeholder
$canonicalFingerprintValue = [string]$canonicalFingerprint.value
$canonicalFingerprintFiles = @($canonicalFingerprint.files | ForEach-Object { [string]$_ })
$expectedFingerprintFiles = @(
    [string]$contract.sourceFiles.runtimeProbe,
    [string]$contract.sourceFiles.teacherScript,
    [string]$contract.sourceFiles.playerMoneyScript
)
$fingerprintPathsMatch = (
    $canonicalFingerprintFiles.Count -eq $expectedFingerprintFiles.Count -and
    (($canonicalFingerprintFiles -join ([char]0)) -ceq ($expectedFingerprintFiles -join ([char]0)))
)
$canonicalPatchPlaceholderCount = 0
foreach ($patchFile in @(Get-ChildItem -LiteralPath (Join-Path $restorationRoot "patches\dsrc") -File -Filter "*.patch"))
{
    $canonicalPatchPlaceholderCount += [regex]::Matches(
        (Get-Content -LiteralPath $patchFile.FullName -Raw),
        [regex]::Escape($canonicalFingerprintPlaceholder)
    ).Count
}
$canonicalRuntimePatchLines = @(
    Get-Content -LiteralPath (Join-Path $restorationRoot "patches\dsrc\002-phase-a-runtime-probe.patch")
)
$canonicalRuntimeHunkIndex = -1
$canonicalRuntimeDeclaredAdditions = -1
for ($index = 0; $index -lt $canonicalRuntimePatchLines.Count; $index++)
{
    $hunkMatch = [regex]::Match(
        [string]$canonicalRuntimePatchLines[$index],
        '^@@\s+-0,0\s+\+1,(?<count>[0-9]+)\s+@@$'
    )
    if ($hunkMatch.Success)
    {
        $canonicalRuntimeHunkIndex = $index
        $canonicalRuntimeDeclaredAdditions = [int]$hunkMatch.Groups['count'].Value
        break
    }
}
$canonicalRuntimeActualAdditions = $(if ($canonicalRuntimeHunkIndex -ge 0)
{
    @($canonicalRuntimePatchLines[($canonicalRuntimeHunkIndex + 1)..($canonicalRuntimePatchLines.Count - 1)] |
        Where-Object { ([string]$_).StartsWith('+', [System.StringComparison]::Ordinal) }).Count
}
else { -1 })
$canonicalRuntimeTargetMatch = [regex]::Match(
    ($canonicalRuntimePatchLines -join "`n"),
    '(?m)^index\s+0000000\.\.(?<target>[a-f0-9]+)$'
)
$canonicalRuntimeComputedBlob = ""
if ($canonicalRuntimeHunkIndex -ge 0)
{
    $runtimeBodyLines = @(
        $canonicalRuntimePatchLines[($canonicalRuntimeHunkIndex + 1)..($canonicalRuntimePatchLines.Count - 1)] |
            ForEach-Object { ([string]$_).Substring(1) }
    )
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $runtimeBodyBytes = $utf8.GetBytes(($runtimeBodyLines -join "`n") + "`n")
    $runtimeBlobHeaderBytes = $utf8.GetBytes("blob $($runtimeBodyBytes.Length)`0")
    $runtimeBlobBytes = New-Object byte[] ($runtimeBlobHeaderBytes.Length + $runtimeBodyBytes.Length)
    [System.Buffer]::BlockCopy($runtimeBlobHeaderBytes, 0, $runtimeBlobBytes, 0, $runtimeBlobHeaderBytes.Length)
    [System.Buffer]::BlockCopy($runtimeBodyBytes, 0, $runtimeBlobBytes, $runtimeBlobHeaderBytes.Length, $runtimeBodyBytes.Length)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try
    {
        $canonicalRuntimeComputedBlob = ([System.BitConverter]::ToString($sha1.ComputeHash($runtimeBlobBytes))).Replace('-', '').ToLowerInvariant()
    }
    finally
    {
        $sha1.Dispose()
    }
}
$canonicalRuntimePatchHunkReady = (
    $canonicalRuntimeHunkIndex -ge 0 -and
    $canonicalRuntimeDeclaredAdditions -eq $canonicalRuntimeActualAdditions -and
    $canonicalRuntimeTargetMatch.Success -and
    $canonicalRuntimeComputedBlob.StartsWith(
        [string]$canonicalRuntimeTargetMatch.Groups['target'].Value,
        [System.StringComparison]::Ordinal
    )
)
$canonicalFingerprintReady = (
    $canonicalFingerprintAlgorithm -ceq "SHA-256" -and
    -not [string]::IsNullOrWhiteSpace($canonicalFingerprintPlaceholder) -and
    $canonicalFingerprintValue -ceq $canonicalFingerprintPlaceholder -and
    $canonicalFingerprintFiles.Count -eq 3 -and
    @($canonicalFingerprintFiles | Sort-Object -Unique).Count -eq 3 -and
    $fingerprintPathsMatch -and
    $canonicalRuntimePatchHunkReady -and
    $canonicalPatchPlaceholderCount -eq 3
)
if (-not $canonicalFingerprintReady)
{
    throw "Canonical Phase-A sources must retain exactly three ordered Java fingerprint placeholders and a placeholder-valued contract."
}

$canonicalAcceptanceBundle = @(Get-RestorationAcceptanceBundle -RestorationRoot $restorationRoot)
$canonicalAcceptancePaths = @($canonicalAcceptanceBundle | ForEach-Object { [string]$_.Path })
$requiredAcceptancePaths = @(
    "restoration/manifest.json",
    "restoration/README.md",
    "restoration/contracts/phase-a.json",
    "restoration/patches/root/README.md",
    "restoration/patches/root/001-dedicated-transfer-server.patch",
    "restoration/patches/exe/README.md",
    "restoration/patches/exe/001-p14-xp-rate.patch",
    "restoration/patches/dsrc/README.md",
    "restoration/patches/dsrc/002-phase-a-runtime-probe.patch",
    "restoration/patches/dsrc/002a-phase-a-operation-markers.patch",
    "restoration/patches/dsrc/007-phase-a-attached-bank-dispatch.patch",
    "restoration/patches/dsrc/006-p14-mos-eisley-artisan-trainer.patch",
    "restoration/patches/src/README.md",
    "restoration/scripts/Invoke-RestorationMaterializer.ps1",
    "restoration/scripts/Restoration.Common.psm1",
    "restoration/scripts/Test-PhaseA.ps1",
    ("restoration/" + ([string]$contract.runtimeSmokeScript).Replace('\', '/')),
    ("restoration/" + ([string]$contract.runtimeTrainerPersistenceScript).Replace('\', '/'))
)
$missingCanonicalAcceptance = @($requiredAcceptancePaths | Where-Object { $_ -cnotin $canonicalAcceptancePaths })
if ($missingCanonicalAcceptance.Count -gt 0)
{
    throw "Canonical restoration acceptance bundle is incomplete: $($missingCanonicalAcceptance -join ', ')."
}

$canonicalPinArgs = @{
    RepositoryRoot = $superprojectRoot
    Manifest = $manifest
}
$sourcePinArgs = @{
    RepositoryRoot = $source
    Manifest = $manifest
    RequireInitialized = $true
}
$canonicalPins = Assert-RestorationPins @canonicalPinArgs
$sourcePins = Assert-RestorationPins @sourcePinArgs

Write-Host "Locked gitlinks:"
foreach ($pin in @($sourcePins))
{
    Write-Host "  [PASS] $($pin.Name) $($pin.Gitlink)"
}

$skillTablePath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$commandTablePath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$schematicGroupTablePath = Join-Path $source ([string]$contract.sourceFiles.schematicGroupTable)
$tatooineBuildoutPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/buildout/tatooine/tatooine_6_2.tab"
$creaturesTablePath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/datatables/mob/creatures.tab"
$localOptionsPath = Join-Path $source "exe/linux/localOptions.cfg"
$execPath = Join-Path $source "exec.sh"
$skills = @(Import-SwgTab -Path $skillTablePath)
$commands = @(Import-SwgTab -Path $commandTablePath)
$schematicGroups = @(Import-SwgTab -Path $schematicGroupTablePath)
$tatooineBuildout = @(Import-SwgTab -Path $tatooineBuildoutPath)
$creatures = @(Import-SwgTab -Path $creaturesTablePath)

$script:checks = @()

function Add-PhaseCheck
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $script:checks += [pscustomobject]@{
        Id = $Id
        Passed = $Passed
        Detail = $Detail
    }
}

function Get-JavaMethodWindow
{
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$SignaturePattern
    )

    $pattern = "(?s)$SignaturePattern.*?(?=\r?\n\s*(?:public|protected|private)\s+(?:static\s+)?|\z)"
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success)
    {
        return ""
    }

    return $match.Value
}

function Test-OrderedStrings
{
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Actual,

        [Parameter(Mandatory = $true)]
        [string[]]$Expected
    )

    if ($Actual.Count -ne $Expected.Count)
    {
        return $false
    }
    for ($index = 0; $index -lt $Expected.Count; $index++)
    {
        if ($Actual[$index] -cne $Expected[$index])
        {
            return $false
        }
    }
    return $true
}

$pointCap = [int]$contract.skillPointCap
foreach ($scenario in @($contract.pointScenarios))
{
    $usedPoints = 0
    $missingSkills = @()
    $invalidSkills = @()

    foreach ($skillNameValue in @($scenario.heldSkills))
    {
        $skillName = [string]$skillNameValue
        $matches = @($skills | Where-Object { $_.NAME -ceq $skillName })
        if ($matches.Count -ne 1)
        {
            $missingSkills += $skillName
            continue
        }

        $points = 0
        if ((-not [int]::TryParse([string]$matches[0].POINTS_REQUIRED, [ref]$points)) -or ($points -lt 0))
        {
            $invalidSkills += $skillName
            continue
        }

        $usedPoints += $points
    }

    $availablePoints = $pointCap - $usedPoints
    $expectedPoints = [int]$scenario.expectedAvailable
    $scenarioPassed = (
        ($missingSkills.Count -eq 0) -and
        ($invalidSkills.Count -eq 0) -and
        ($availablePoints -eq $expectedPoints) -and
        ($availablePoints -ge 0)
    )
    $detail = "available=$availablePoints expected=$expectedPoints used=$usedPoints"
    if ($missingSkills.Count -gt 0)
    {
        $detail += " missing=$($missingSkills -join ',')"
    }
    if ($invalidSkills.Count -gt 0)
    {
        $detail += " invalid=$($invalidSkills -join ',')"
    }

    Add-PhaseCheck -Id "phaseA.points.$($scenario.name)" -Passed $scenarioPassed -Detail $detail
}

$trainingSkillName = [string]$contract.trainingSkill.name
$trainingRows = @($skills | Where-Object { $_.NAME -ceq $trainingSkillName })
$trainingRowPassed = (
    ($trainingRows.Count -eq 1) -and
    ([int]$trainingRows[0].POINTS_REQUIRED -eq [int]$contract.trainingSkill.pointsRequired) -and
    ([int]$trainingRows[0].MONEY_REQUIRED -eq [int]$contract.trainingSkill.moneyRequired)
)
Add-PhaseCheck -Id "phaseA.training.table-costs" -Passed $trainingRowPassed -Detail "expected $trainingSkillName points=$($contract.trainingSkill.pointsRequired) money=$($contract.trainingSkill.moneyRequired)"

$artisanTrainerSpawners = @($tatooineBuildout | Where-Object {
    [string]$_.objid -ceq "-1894400000"
})
$artisanTrainerDefinitions = @($creatures | Where-Object {
    [string]$_.creatureName -ceq "trainer_artisan"
})
$artisanTrainerSpawnReady = (
    $artisanTrainerSpawners.Count -eq 1 -and
    [string]$artisanTrainerSpawners[0].container -ceq "0" -and
    [string]$artisanTrainerSpawners[0].server_template_crc -ceq "object/tangible/ground_spawning/area_spawner.iff" -and
    [string]$artisanTrainerSpawners[0].cell_index -ceq "0" -and
    [string]$artisanTrainerSpawners[0].px -ceq "1455" -and
    [string]$artisanTrainerSpawners[0].py -ceq "5" -and
    [string]$artisanTrainerSpawners[0].pz -ceq "1335" -and
    [string]$artisanTrainerSpawners[0].scripts -ceq "systems.spawning.spawner_area" -and
    [string]$artisanTrainerSpawners[0].objvars -cmatch '(?:^|\|)fltRadius\|2\|0\.000000(?:\||$)' -and
    [string]$artisanTrainerSpawners[0].objvars -cmatch '(?:^|\|)intDefaultBehavior\|0\|1(?:\||$)' -and
    [string]$artisanTrainerSpawners[0].objvars -cmatch '(?:^|\|)intSpawnCount\|0\|1(?:\||$)' -and
    [string]$artisanTrainerSpawners[0].objvars -cmatch '(?:^|\|)strSpawns\|4\|trainer_artisan(?:\||$)' -and
    $artisanTrainerDefinitions.Count -eq 1 -and
    ([string]$artisanTrainerDefinitions[0].objvars).Split(',') -ccontains "string:trainer=trainer_artisan" -and
    ([string]$artisanTrainerDefinitions[0].scripts).Split(',') -ccontains "npc.skillteacher.skillteacher"
)
Add-PhaseCheck -Id "phaseA.training.mos-eisley-artisan-spawn" -Passed $artisanTrainerSpawnReady -Detail "durable buildout spawner must create one sentinel trainer_artisan at global Core3/P14 coordinates (3503, 5, -4809) with its stock skillteacher script"

$localOptions = Get-Content -LiteralPath $localOptionsPath -Raw
$xpMultiplierLines = @($localOptions -split "\r?\n" | Where-Object {
    $_.StartsWith('xpMultiplier=', [System.StringComparison]::Ordinal)
})
$xpMultiplierReady = (
    $xpMultiplierLines.Count -eq 1 -and
    $xpMultiplierLines[0] -ceq 'xpMultiplier=1'
)
Add-PhaseCheck -Id "phaseA.training.p14-xp-rate" -Passed $xpMultiplierReady -Detail "dedicated Pre-CU runtime must use exactly one xpMultiplier=1 setting"

$execScript = Get-Content -LiteralPath $execPath -Raw
$transferServerRuntimeReady = (
    @($localOptions -split "\r?\n" | Where-Object { $_ -ceq 'transferServerAddress=HOSTIP' }).Count -eq 1 -and
    @($localOptions -split "\r?\n" | Where-Object { $_ -ceq 'transferServerPort=44469' }).Count -eq 1 -and
    @($localOptions -split "\r?\n" | Where-Object { $_ -ceq 'centralServerServiceBindInterface=eth0' }).Count -eq 1 -and
    @($localOptions -split "\r?\n" | Where-Object { $_ -ceq 'centralServerServiceBindPort=44469' }).Count -eq 1 -and
    $execScript -match '(?m)^start_transfer_server\s*\(\)' -and
    $execScript -match 'pgrep\s+-x\s+CentralServer' -and
    $execScript -match '\./bin/TransferServer\s+--\s+@servercommon\.cfg' -and
    $execScript -match '\./bin/TaskManager\s+--\s+@servercommon\.cfg\s+&' -and
    $execScript -match 'wait\s+"\$task_manager_pid"'
)
Add-PhaseCheck -Id "phaseA.runtime.transfer-server" -Passed $transferServerRuntimeReady -Detail "dedicated cluster must configure and supervise the TransferServer required for named-account bank transfers"

$skillScriptPath = Join-Path $source ([string]$contract.sourceFiles.skillScript)
$teacherScriptPath = Join-Path $source ([string]$contract.sourceFiles.teacherScript)
$playerMoneyScriptPath = Join-Path $source ([string]$contract.sourceFiles.playerMoneyScript)
$runtimeProbePath = Join-Path $source ([string]$contract.sourceFiles.runtimeProbe)
$bankDispatchScriptPath = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/test/precu_phase_a_bank_dispatch.java"
$commandCppPath = Join-Path $source ([string]$contract.sourceFiles.commandCpp)
$playerObjectCppPath = Join-Path $source ([string]$contract.sourceFiles.playerObjectCpp)
$skillScript = Get-Content -LiteralPath $skillScriptPath -Raw
$teacherScript = Get-Content -LiteralPath $teacherScriptPath -Raw
$playerMoneyScript = Get-Content -LiteralPath $playerMoneyScriptPath -Raw
$runtimeProbe = if (Test-Path -LiteralPath $runtimeProbePath -PathType Leaf) { Get-Content -LiteralPath $runtimeProbePath -Raw } else { "" }
$bankDispatchScript = if (Test-Path -LiteralPath $bankDispatchScriptPath -PathType Leaf) { Get-Content -LiteralPath $bankDispatchScriptPath -Raw } else { "" }
$commandCpp = Get-Content -LiteralPath $commandCppPath -Raw
$playerObjectCpp = Get-Content -LiteralPath $playerObjectCppPath -Raw

$materializationReady = $canonicalFingerprintReady
$materializationDetail = "canonical contract and overlays retain three ordered placeholders"
if ($Expectation -eq "Ready")
{
    $materializationReady = $false
    try
    {
        $expectedStagedContractRelativePath = "restoration/" + ([string]$manifest.contracts.phaseA).Replace('\', '/')
        $stagedContractPath = Join-Path $source ($expectedStagedContractRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        $artifactManifestPath = Join-Path $source "restoration\materialization-fingerprint.json"
        if (-not (Test-Path -LiteralPath $stagedContractPath -PathType Leaf))
        {
            throw "Staged Phase-A contract is missing: $stagedContractPath"
        }
        if (-not (Test-Path -LiteralPath $artifactManifestPath -PathType Leaf))
        {
            throw "Materialization artifact manifest is missing: $artifactManifestPath"
        }

        $stagedContractText = Get-Content -LiteralPath $stagedContractPath -Raw
        $stagedContract = $stagedContractText | ConvertFrom-Json
        $stagedFingerprint = $stagedContract.runtimeVerticalSlice.materializationFingerprint
        $injectedFingerprint = [string]$stagedFingerprint.value
        $stagedFingerprintFiles = @($stagedFingerprint.files | ForEach-Object { [string]$_ })
        if ([string]$stagedFingerprint.algorithm -cne "SHA-256" -or
            $injectedFingerprint -cnotmatch '^[a-f0-9]{64}$' -or
            $injectedFingerprint -ceq $canonicalFingerprintPlaceholder -or
            [string]$stagedFingerprint.placeholder -cne $canonicalFingerprintPlaceholder -or
            -not (Test-OrderedStrings -Actual $stagedFingerprintFiles -Expected $canonicalFingerprintFiles))
        {
            throw "Staged Phase-A contract does not contain the expected injected SHA-256 definition."
        }
        # The sole literal placeholder remaining in the staged JSON is its metadata
        # definition; materializationFingerprint.value must be fully injected.
        if ([regex]::Matches($stagedContractText, [regex]::Escape($canonicalFingerprintPlaceholder)).Count -ne 1)
        {
            throw "Staged Phase-A contract contains an unresolved or duplicated fingerprint placeholder."
        }

        $constantNames = @("BUILD_FINGERPRINT", "PRECU_BUILD_FINGERPRINT", "PRECU_BUILD_FINGERPRINT")
        $loadedJava = @($runtimeProbe, $teacherScript, $playerMoneyScript)
        for ($index = 0; $index -lt $loadedJava.Count; $index++)
        {
            $constantPattern = '(?m)private\s+static\s+final\s+String\s+' +
                [regex]::Escape($constantNames[$index]) + '\s*=\s*"' +
                [regex]::Escape($injectedFingerprint) + '"\s*;'
            if ([regex]::Matches($loadedJava[$index], $constantPattern).Count -ne 1 -or
                $loadedJava[$index].IndexOf($canonicalFingerprintPlaceholder, [System.StringComparison]::Ordinal) -ge 0)
            {
                throw "Materialized Java input '$($canonicalFingerprintFiles[$index])' does not contain its one matching injected constant."
            }
        }

        $recomputedFingerprint = Get-MaterializationFingerprint `
            -Root $source `
            -RelativePaths $canonicalFingerprintFiles `
            -Placeholder $canonicalFingerprintPlaceholder `
            -InjectedFingerprint $injectedFingerprint
        if ([string]$recomputedFingerprint.Digest -cne $injectedFingerprint)
        {
            throw "Materialized Java inputs do not reproduce the injected input digest."
        }

        $artifactManifestText = Get-Content -LiteralPath $artifactManifestPath -Raw
        $artifactManifest = $artifactManifestText | ConvertFrom-Json
        if ([int]$artifactManifest.schemaVersion -ne 2 -or
            [string]$artifactManifest.algorithm -cne "SHA-256" -or
            [string]$artifactManifest.framing -cne [string]$recomputedFingerprint.Framing -or
            [string]$artifactManifest.placeholder -cne $canonicalFingerprintPlaceholder -or
            [string]$artifactManifest.inputDigest -cne $injectedFingerprint)
        {
            throw "Materialization artifact manifest header is inconsistent with the staged contract and inputs."
        }

        $manifestInputs = @($artifactManifest.orderedInputs)
        $recomputedInputs = @($recomputedFingerprint.Inputs)
        if ($manifestInputs.Count -ne $canonicalFingerprintFiles.Count -or
            $recomputedInputs.Count -ne $canonicalFingerprintFiles.Count)
        {
            throw "Materialization artifact manifest does not contain the exact ordered input set."
        }
        for ($index = 0; $index -lt $canonicalFingerprintFiles.Count; $index++)
        {
            if ([int]$manifestInputs[$index].ordinal -ne $index -or
                [string]$manifestInputs[$index].path -cne $canonicalFingerprintFiles[$index] -or
                [UInt64]$manifestInputs[$index].sizeBytes -ne [UInt64]$recomputedInputs[$index].SizeBytes -or
                [string]$manifestInputs[$index].sha256 -cne [string]$recomputedInputs[$index].Sha256 -or
                [int]$manifestInputs[$index].placeholderOccurrences -ne 1)
            {
                throw "Materialization ordered input record $index is inconsistent with reconstructed placeholder-form bytes."
            }
        }

        $manifestArtifacts = @($artifactManifest.artifacts)
        if ($manifestArtifacts.Count -ne $canonicalFingerprintFiles.Count)
        {
            throw "Materialization artifact manifest must contain exactly three injected Java artifacts."
        }
        for ($index = 0; $index -lt $canonicalFingerprintFiles.Count; $index++)
        {
            $artifactPath = Join-Path $source ($canonicalFingerprintFiles[$index].Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            [byte[]]$artifactBytes = [System.IO.File]::ReadAllBytes($artifactPath)
            $artifactHash = Get-Sha256HexFromBytes -Bytes $artifactBytes
            if ([int]$manifestArtifacts[$index].ordinal -ne $index -or
                [string]$manifestArtifacts[$index].path -cne $canonicalFingerprintFiles[$index] -or
                [UInt64]$manifestArtifacts[$index].sizeBytes -ne [UInt64]$artifactBytes.Length -or
                [string]$manifestArtifacts[$index].sha256 -cne $artifactHash)
            {
                throw "Materialization final artifact record $index does not match its injected Java file."
            }
        }

        $stagedRestorationRoot = Join-Path $source "restoration"
        $stagedGitMetadata = @(
            Get-ChildItem -LiteralPath $stagedRestorationRoot -Recurse -Force |
                Where-Object { $_.Name -ieq ".git" }
        )
        if ($stagedGitMetadata.Count -gt 0)
        {
            throw "Staged restoration acceptance bundle must not contain .git metadata."
        }
        $stagedAcceptanceBundle = @(Get-RestorationAcceptanceBundle -RestorationRoot $stagedRestorationRoot)
        $manifestAcceptanceFiles = @($artifactManifest.acceptanceBundle.files)
        $manifestAcceptanceExclusions = @($artifactManifest.acceptanceBundle.exclusions | ForEach-Object { [string]$_ })
        if ([string]$artifactManifest.acceptanceBundle.policy -cne "canonical-byte-identity-except-staged-phase-a-fingerprint-value" -or
            -not (Test-OrderedStrings -Actual $manifestAcceptanceExclusions -Expected @("restoration/materialization-fingerprint.json", "**/.git/**")) -or
            $stagedAcceptanceBundle.Count -ne $canonicalAcceptanceBundle.Count -or
            $manifestAcceptanceFiles.Count -ne $canonicalAcceptanceBundle.Count)
        {
            throw "Staged restoration acceptance bundle count, policy, or exclusions are inconsistent."
        }
        for ($index = 0; $index -lt $canonicalAcceptanceBundle.Count; $index++)
        {
            $canonicalBundleFile = $canonicalAcceptanceBundle[$index]
            $stagedBundleFile = $stagedAcceptanceBundle[$index]
            $manifestBundleFile = $manifestAcceptanceFiles[$index]
            $expectedMutation = if ([string]$canonicalBundleFile.Path -ceq $expectedStagedContractRelativePath)
            {
                "materializationFingerprint.value"
            }
            else
            {
                "none"
            }
            if ([int]$canonicalBundleFile.Ordinal -ne $index -or
                [string]$stagedBundleFile.Path -cne [string]$canonicalBundleFile.Path -or
                [int]$manifestBundleFile.ordinal -ne $index -or
                [string]$manifestBundleFile.path -cne [string]$canonicalBundleFile.Path -or
                [UInt64]$manifestBundleFile.canonicalSizeBytes -ne [UInt64]$canonicalBundleFile.SizeBytes -or
                [string]$manifestBundleFile.canonicalSha256 -cne [string]$canonicalBundleFile.Sha256 -or
                [UInt64]$manifestBundleFile.stagedSizeBytes -ne [UInt64]$stagedBundleFile.SizeBytes -or
                [string]$manifestBundleFile.stagedSha256 -cne [string]$stagedBundleFile.Sha256 -or
                [string]$manifestBundleFile.mutation -cne $expectedMutation)
            {
                throw "Staged restoration acceptance bundle record $index is inconsistent: $($canonicalBundleFile.Path)"
            }
            if ($expectedMutation -ceq "none" -and
                ([UInt64]$stagedBundleFile.SizeBytes -ne [UInt64]$canonicalBundleFile.SizeBytes -or
                 [string]$stagedBundleFile.Sha256 -cne [string]$canonicalBundleFile.Sha256))
            {
                throw "Staged restoration acceptance file differs from canonical current bytes: $($canonicalBundleFile.Path)"
            }
        }

        $stagedRunnerPath = Join-Path $source (("restoration/" + ([string]$contract.runtimeTrainerPersistenceScript).Replace('\', '/')).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        $stagedRunnerText = Get-Content -LiteralPath $stagedRunnerPath -Raw
        if ([int]$stagedContract.runtimeVerticalSlice.runnerSchemaVersion -ne 8 -or
            [int]$stagedContract.runtimeVerticalSlice.snapshotSchemaVersion -ne 8 -or
            [string]$stagedContract.runtimeVerticalSlice.runtimeContractId -cne "phase-a-trainer-persistence-v6.4" -or
            $stagedRunnerText -notmatch '\[switch\]\$OfflineSelfTest' -or
            $stagedRunnerText -notmatch 'OFFLINE_TRANSITION_TESTS=PASS' -or
            $stagedRunnerText -notmatch '\$runnerSchemaVersion\s*=\s*\[int\]\$runtimeContract\.runnerSchemaVersion')
        {
            throw "Staged runner/contract pair is not the required schema-v8 offline-capable acceptance bundle."
        }

        [byte[]]$stagedContractBytes = [System.IO.File]::ReadAllBytes($stagedContractPath)
        if ([string]$artifactManifest.stagedContract.path -cne $expectedStagedContractRelativePath -or
            [UInt64]$artifactManifest.stagedContract.sizeBytes -ne [UInt64]$stagedContractBytes.Length -or
            [string]$artifactManifest.stagedContract.sha256 -cne (Get-Sha256HexFromBytes -Bytes $stagedContractBytes) -or
            [string]$artifactManifest.stagedContract.fingerprintValue -cne $injectedFingerprint)
        {
            throw "Materialization staged-contract artifact record is inconsistent."
        }

        $materializationReady = $true
        $materializationDetail = "injected=$injectedFingerprint orderedInputs=$($canonicalFingerprintFiles.Count) artifacts=$($manifestArtifacts.Count) acceptanceFiles=$($canonicalAcceptanceBundle.Count)"
    }
    catch
    {
        $materializationDetail = $_.Exception.Message
    }
}

$teachableWindow = Get-JavaMethodWindow -Source $skillScript -SignaturePattern "public\s+static\s+String\[\]\s+getTeachableSkills\s*\("
$trainerExclusionsPresent = $true
foreach ($excludedValue in @($contract.trainerPolicy.excludedPrefixes))
{
    $pattern = 'startsWith\s*\(\s*"' + [regex]::Escape([string]$excludedValue) + '"\s*\)'
    if ($teachableWindow -notmatch $pattern)
    {
        $trainerExclusionsPresent = $false
        break
    }
}
foreach ($excludedValue in @($contract.trainerPolicy.excludedExact))
{
    $pattern = 'equals\s*\(\s*"' + [regex]::Escape([string]$excludedValue) + '"\s*\)'
    if ($teachableWindow -notmatch $pattern)
    {
        $trainerExclusionsPresent = $false
        break
    }
}
$teachableImplemented = (
    ($teachableWindow.Length -gt 0) -and
    ($teachableWindow -match "\bdeltaTeacherSkills\s*\(") -and
    ($teachableWindow -match "\bgetSkillPrerequisiteSkills\s*\(") -and
    ($teachableWindow -match "\butils\.isSubset\s*\(") -and
    ($teachableWindow -match [regex]::Escape("newbie.hasSkill")) -and
    $trainerExclusionsPresent
)
Add-PhaseCheck -Id "phaseA.training.teachable-list" -Passed $teachableImplemented -Detail "trainer-minus-player skills must be filtered by prerequisites and protected training families"

$statusWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "public\s+boolean\s+checkSkillStatus\s*\("
$conversationReachable = (
    ($statusWindow -match [regex]::Escape("getAvailableSkillPoints")) -and
    ($statusWindow -match "(?s)getAvailableSkillPoints\s*\(.*?return\s+true\s*;")
)
Add-PhaseCheck -Id "phaseA.training.conversation-reachable" -Passed $conversationReachable -Detail "ordinary qualified trainers must reach a true return with derived points available"

$qualifiedWindow = Get-JavaMethodWindow -Source $skillScript -SignaturePattern "public\s+static\s+String\[\]\s+getQualifiedTeachableSkills\s*\("
$speciesPolicyReady = (
    ($qualifiedWindow -match "species\s*!=\s*null\s*&&\s*!species\.isEmpty\s*\(\s*\)") -and
    ($qualifiedWindow -match [regex]::Escape("getPlayerSpeciesName")) -and
    ($qualifiedWindow -match "!species\.getBoolean\s*\(") -and
    ($qualifiedWindow -notmatch "assert\s+d\s*!=\s*null")
)
Add-PhaseCheck -Id "phaseA.training.species-policy" -Passed $speciesPolicyReady -Detail "species prerequisites must evaluate the player's species against the species dictionary"

$moneyDerived = (
    ($teacherScript -match [regex]::Escape("MONEY_REQUIRED")) -and
    ($teacherScript -notmatch "\bint\s+cost\s*=\s*1\s*;")
)

$attemptedPaymentWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "public\s+int\s+attemptedPayment\s*\("
$trainerPaymentLifecycleReady = (
    ($teacherScript -match 'money\.requestPayment\s*\(\s*speaker\s*,\s*self\s*,\s*cost\s*,\s*"attemptedPayment"') -and
    ($attemptedPaymentWindow -match 'money\.getReturnCode\s*\(\s*params\s*\)') -and
    ($attemptedPaymentWindow -match 'retCode\s*!=\s*money\.RET_SUCCESS') -and
    ($attemptedPaymentWindow -match 'completeSkillPurchase\s*\(\s*player\s*,\s*skillName\s*\)') -and
    ($attemptedPaymentWindow -match 'money\.bankTo\s*\(\s*self\s*,\s*money\.ACCT_SKILL_TRAINING\s*,\s*cost\s*\)') -and
    ($attemptedPaymentWindow -match 'money\.bankTo\s*\(\s*self\s*,\s*player\s*,\s*cost\s*\)')
)
$moneyDerived = $moneyDerived -and $trainerPaymentLifecycleReady
Add-PhaseCheck -Id "phaseA.training.money-derived" -Passed $moneyDerived -Detail "trainer money must derive MONEY_REQUIRED and retain the request, callback, purchase, accounting, and refund lifecycle"

$availableHelper = [string]$contract.pointImplementation.availableHelper
$costHelper = [string]$contract.pointImplementation.costHelper
$pointColumn = [string]$contract.pointImplementation.tableColumn
$purchaseWindow = Get-JavaMethodWindow -Source $skillScript -SignaturePattern "public\s+static\s+boolean\s+purchaseSkill\s*\("
$pointsDerived = (
    ($skillScript -match [regex]::Escape($pointColumn)) -and
    ($skillScript -match [regex]::Escape($availableHelper)) -and
    ($skillScript -match [regex]::Escape($costHelper)) -and
    ($purchaseWindow -match [regex]::Escape($availableHelper)) -and
    ($purchaseWindow -match [regex]::Escape($costHelper)) -and
    ($teacherScript -notmatch "\bint\s+ptsLeft\s*=\s*0\s*;") -and
    ($teacherScript -notmatch "\bint\s+ptsCost\s*=\s*1\s*;")
)
Add-PhaseCheck -Id "phaseA.training.points-derived" -Passed $pointsDerived -Detail "derive 250 minus held POINTS_REQUIRED and enforce it inside purchaseSkill"

$surrenderRows = @($commands | Where-Object { $_.commandName -ieq "surrenderSkill" })
$surrenderCommandReady = (
    ($surrenderRows.Count -eq 1) -and
    ($surrenderRows[0].defaultPriority -ceq "immediate") -and
    ($surrenderRows[0].cppHook -ceq "surrenderSkill") -and
    ($surrenderRows[0].targetType -ceq "none") -and
    ([string]::IsNullOrEmpty([string]$surrenderRows[0].stringId)) -and
    ([int]$surrenderRows[0].visible -eq 1) -and
    ([int]$surrenderRows[0].callOnTarget -eq 0) -and
    ([int]$surrenderRows[0].disabled -eq 0) -and
    ([int]$surrenderRows[0].godLevel -eq 0) -and
    ([int]$surrenderRows[0].addToCombatQueue -eq 0) -and
    ([int]$surrenderRows[0].toolbarOnly -eq 0) -and
    ([int]$surrenderRows[0].fromServerOnly -eq 0)
)
Add-PhaseCheck -Id "phaseA.surrender.command-table" -Passed $surrenderCommandReady -Detail "surrenderSkill must retain the authentic client-visible, immediate, actor-routed command contract"

$protectedPolicyPresent = $true
foreach ($prefixValue in @($contract.surrenderPolicy.protectedPrefixes))
{
    if ($commandCpp.IndexOf(('"' + [string]$prefixValue + '"'), [System.StringComparison]::Ordinal) -lt 0)
    {
        $protectedPolicyPresent = $false
        break
    }
}
foreach ($fragmentValue in @($contract.surrenderPolicy.protectedFragments))
{
    $pattern = 'skillName\.find\s*\(\s*"' + [regex]::Escape([string]$fragmentValue) + '"\s*\)\s*!=\s*std::string::npos'
    if ($commandCpp -notmatch $pattern)
    {
        $protectedPolicyPresent = $false
        break
    }
}
foreach ($exactValue in @($contract.surrenderPolicy.protectedExact))
{
    $pattern = 'skillName\s*==\s*"' + [regex]::Escape([string]$exactValue) + '"'
    if ($commandCpp -notmatch $pattern)
    {
        $protectedPolicyPresent = $false
        break
    }
}
$surrenderHandlerMatch = [regex]::Match($commandCpp, "(?s)static\s+void\s+commandFuncSurrenderSkill\s*\(.*?(?=\r?\n//\s+-{5,})")
$surrenderHandler = if ($surrenderHandlerMatch.Success) { $surrenderHandlerMatch.Value } else { "" }
$ownershipCheckCount = [regex]::Matches($surrenderHandler, "hasSkill\s*\(\s*\*skill\s*\)").Count
$schematicGuardReady = $playerObjectCpp -match "(?s)found\s*==\s*m_draftSchematics\.end\s*\(\s*\).*?return\s+false\s*;"
$surrenderNativeReady = (
    ($commandCpp -match "\bcommandFuncSurrenderSkill\b") -and
    ($commandCpp -match 'addCppFunction\s*\(\s*"surrenderSkill"\s*,\s*commandFuncSurrenderSkill\s*\)') -and
    ($surrenderHandler -match "getCreatureObject\s*\(\s*actor\s*\)") -and
    ($surrenderHandler -notmatch "getCreatureObject\s*\(\s*target\s*\)") -and
    ($surrenderHandler -match "isAuthoritative\s*\(") -and
    ($ownershipCheckCount -ge 2) -and
    ($surrenderHandler -match "dependsUponSkill\s*\(") -and
    ($surrenderHandler -match "revokeSkill\s*\(\s*\*skill\s*\)") -and
    ($commandCpp -match "findProfessionForSkill\s*\(") -and
    ($commandCpp -match "getExperienceLimit\s*\(") -and
    ($commandCpp -match "grantExperiencePoints\s*\(") -and
    $protectedPolicyPresent -and
    $schematicGuardReady
)
Add-PhaseCheck -Id "phaseA.surrender.native-handler" -Passed $surrenderNativeReady -Detail "actor-only native handler must reject protected/dependent skills, verify removal, clamp XP, and retain safe cleanup"

$runtimeSlice = $contract.runtimeVerticalSlice
$runtimeSkillName = [string]$runtimeSlice.skill
$runtimeCommand = [string]$runtimeSlice.command
$runtimeSkillModName = [string]$runtimeSlice.skillMod.name
$runtimeSkillModDelta = [int]$runtimeSlice.skillMod.delta
$runtimeSchematicGroup = [string]$runtimeSlice.schematicGroup
$runtimeSchematic = [string]$runtimeSlice.schematic
$runtimeRows = @($skills | Where-Object { $_.NAME -ceq $runtimeSkillName })
$runtimePrerequisiteRows = @($skills | Where-Object { $_.NAME -ceq [string]$runtimeSlice.prerequisiteSkill })
$runtimeSkillContractReady = $false
if ($runtimeRows.Count -eq 1 -and $runtimePrerequisiteRows.Count -eq 1)
{
    $runtimeCommands = @(([string]$runtimeRows[0].COMMANDS).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $runtimeSkillMods = @(([string]$runtimeRows[0].SKILL_MODS).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $runtimeGrantedGroups = @(([string]$runtimeRows[0].SCHEMATICS_GRANTED).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $runtimeSkillContractReady = (
        ([string]$runtimeRows[0].SKILLS_REQUIRED -ceq [string]$runtimeSlice.prerequisiteSkill) -and
        ([string]$runtimeRows[0].XP_TYPE -ceq [string]$runtimeSlice.xpType) -and
        ([int]$runtimeRows[0].MONEY_REQUIRED -eq [int]$runtimeSlice.moneyCost) -and
        ([int]$runtimeRows[0].XP_COST -eq [int]$runtimeSlice.xpCost) -and
        ([int]$runtimeRows[0].POINTS_REQUIRED -eq [int]$runtimeSlice.skillPointCost) -and
        ([int]$runtimePrerequisiteRows[0].XP_CAP -eq [int]$runtimeSlice.prerequisiteXpCap) -and
        ([int]$runtimeRows[0].XP_CAP -eq [int]$runtimeSlice.trainedXpCap) -and
        ($runtimeCommand -cin $runtimeCommands) -and
        (("$runtimeSkillModName=$runtimeSkillModDelta") -cin $runtimeSkillMods) -and
        ($runtimeSchematicGroup -cin $runtimeGrantedGroups)
    )
}
$runtimeSchematicMappings = @(
    $schematicGroups |
        Where-Object {
            ([string]$_.GroupId -ceq $runtimeSchematicGroup) -and
            ([string]$_.SchematicName -ceq $runtimeSchematic)
        }
)
$runtimeSkillContractReady = $runtimeSkillContractReady -and ($runtimeSchematicMappings.Count -eq 1)
Add-PhaseCheck -Id "phaseA.runtime.crafting-contract" -Passed $runtimeSkillContractReady -Detail "Artisan engineering cost, prerequisite/trained XP caps, command, skill-mod delta, and concrete group-derived schematic must resolve from authoritative tables"

$completeVectorReady = $false
if ($runtimeRows.Count -eq 1 -and $runtimePrerequisiteRows.Count -eq 1)
{
    $vectorRows = @($runtimePrerequisiteRows[0], $runtimeRows[0])
    $actualVectorCommands = @(
        $vectorRows |
            ForEach-Object { ([string]$_.COMMANDS).Split(",") } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_.Length -gt 0 } |
            Sort-Object -Unique
    )
    $expectedVectorCommands = @(
        $runtimeSlice.completeGrantVector.commands |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )

    $actualVectorMods = @{}
    foreach ($row in $vectorRows)
    {
        foreach ($entry in @(([string]$row.SKILL_MODS).Split(",")))
        {
            $parts = @($entry.Trim().Split("="))
            if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]))
            {
                continue
            }
            $value = 0
            if (-not [int]::TryParse($parts[1], [ref]$value))
            {
                continue
            }
            if (-not $actualVectorMods.ContainsKey($parts[0]))
            {
                $actualVectorMods[$parts[0]] = 0
            }
            $actualVectorMods[$parts[0]] = [int]$actualVectorMods[$parts[0]] + $value
        }
    }
    $expectedModProperties = @($runtimeSlice.completeGrantVector.skillMods.psobject.Properties)
    $modsMatch = ($actualVectorMods.Count -eq $expectedModProperties.Count)
    foreach ($property in $expectedModProperties)
    {
        if (-not $actualVectorMods.ContainsKey($property.Name) -or
            [int]$actualVectorMods[$property.Name] -ne [int]$property.Value)
        {
            $modsMatch = $false
            break
        }
    }

    $actualVectorGroups = @(
        $vectorRows |
            ForEach-Object { ([string]$_.SCHEMATICS_GRANTED).Split(",") } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_.Length -gt 0 } |
            Sort-Object -Unique
    )
    $expectedVectorGroups = @(
        $runtimeSlice.completeGrantVector.schematicGroups |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )
    $concreteSchematics = @(
        $schematicGroups |
            Where-Object { [string]$_.GroupId -cin $expectedVectorGroups } |
            ForEach-Object { [string]$_.SchematicName } |
            Sort-Object -Unique
    )
    $expectedConcreteSchematics = @(
        $runtimeSlice.completeGrantVector.concreteSchematics |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )
    $purchaseGroups = @(
        ([string]$runtimeRows[0].SCHEMATICS_GRANTED).Split(",") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_.Length -gt 0 }
    )
    $actualPurchaseSchematics = @(
        $schematicGroups |
            Where-Object { [string]$_.GroupId -cin $purchaseGroups } |
            ForEach-Object { [string]$_.SchematicName } |
            Sort-Object -Unique
    )
    $expectedPurchaseSchematics = @(
        $runtimeSlice.completeGrantVector.purchaseSchematics |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )
    $actualPurchaseModDeltas = @{}
    foreach ($property in @($runtimeSlice.completeGrantVector.purchaseSkillModDeltas.psobject.Properties))
    {
        $actualPurchaseModDeltas[$property.Name] = 0
    }
    foreach ($entry in @(([string]$runtimeRows[0].SKILL_MODS).Split(",")))
    {
        $parts = @($entry.Trim().Split("="))
        $parsedDelta = 0
        if ($parts.Count -eq 2 -and [int]::TryParse($parts[1], [ref]$parsedDelta))
        {
            $actualPurchaseModDeltas[$parts[0]] = $parsedDelta
        }
    }
    $purchaseModsMatch = $true
    foreach ($property in @($runtimeSlice.completeGrantVector.purchaseSkillModDeltas.psobject.Properties))
    {
        if (-not $actualPurchaseModDeltas.ContainsKey($property.Name) -or
            [int]$actualPurchaseModDeltas[$property.Name] -ne [int]$property.Value)
        {
            $purchaseModsMatch = $false
            break
        }
    }

    $completeVectorReady = (
        (($actualVectorCommands -join "|") -ceq ($expectedVectorCommands -join "|")) -and
        $modsMatch -and
        (($actualVectorGroups -join "|") -ceq ($expectedVectorGroups -join "|")) -and
        (($concreteSchematics -join "|") -ceq ($expectedConcreteSchematics -join "|")) -and
        (($actualPurchaseSchematics -join "|") -ceq ($expectedPurchaseSchematics -join "|")) -and
        $purchaseModsMatch -and
        ($concreteSchematics.Count -eq [int]$runtimeSlice.completeGrantVector.concreteSchematicCount)
    )
}
Add-PhaseCheck -Id "phaseA.runtime.complete-vector" -Passed $completeVectorReady -Detail "Novice plus Engineering I must resolve to the complete two-command, six-mod, 35-concrete-schematic authoritative vector"

$runtimeProbeReady = (
    ($runtimeProbe -match "class\s+precu_phase_a_runtime\s+extends\s+script\.base_script") -and
    ($runtimeProbe -match "public\s+String\s+executeProbe\s*\(\s*String\s+params\s*\)") -and
    ($runtimeProbe -match ("RUNTIME_STATION_ID\s*=\s*" + [int]$runtimeSlice.stationId + "\s*;")) -and
    ($runtimeProbe -match "getPlayerStationId\s*\(\s*player\s*\)\s*!=\s*RUNTIME_STATION_ID") -and
    ($runtimeProbe -match "skill\.purchaseSkill\s*\(") -and
    ($runtimeProbe -match "getAvailableSkillPoints\s*\(") -and
    ($runtimeProbe -match "getExperiencePoints\s*\(") -and
    ($runtimeProbe -match "getExperienceCap\s*\(") -and
    ($runtimeProbe -match 'getStringCrc\s*\(\s*"surrenderskill"\s*\)') -and
    ($runtimeProbe -match "queueCommand\s*\(") -and
    ($runtimeProbe -match "obj_id\.NULL_ID") -and
    ($runtimeProbe -match "COMMAND_PRIORITY_IMMEDIATE") -and
    ($runtimeProbe -notmatch "\bOnAttach\s*\(") -and
    ($runtimeProbe -notmatch "public\s+(?:int|String)\s+On[A-Z][A-Za-z0-9_]*\s*\(")
)
Add-PhaseCheck -Id "phaseA.runtime.console-probe" -Passed $runtimeProbeReady -Detail "trusted console probe must be fixture-bound, query state, and drive purchase/surrender through production services without an attached-object entry point"

$craftingProbeReady = (
    ($runtimeProbe -match ('CRAFTING_SKILL\s*=\s*"' + [regex]::Escape($runtimeSkillName) + '"')) -and
    ($runtimeProbe -match ('CRAFTING_XP_TYPE\s*=\s*"' + [regex]::Escape([string]$runtimeSlice.xpType) + '"')) -and
    ($runtimeProbe -match ('CRAFTING_COMMAND\s*=\s*"' + [regex]::Escape($runtimeCommand) + '"')) -and
    ($runtimeProbe -match ('CRAFTING_SKILL_MOD\s*=\s*"' + [regex]::Escape($runtimeSkillModName) + '"')) -and
    ($runtimeProbe -match ('CRAFTING_SCHEMATIC_GROUP\s*=\s*"' + [regex]::Escape($runtimeSchematicGroup) + '"')) -and
    ($runtimeProbe -match [regex]::Escape($runtimeSchematic)) -and
    ($runtimeProbe -match "getCashBalance\s*\(\s*player\s*\)") -and
    ($runtimeProbe -match "getBankBalance\s*\(\s*player\s*\)") -and
    ($runtimeProbe -match "hasCommand\s*\(\s*player\s*,\s*CRAFTING_COMMAND\s*\)") -and
    ($runtimeProbe -match "getSkillStatisticModifier\s*\(\s*player\s*,\s*CRAFTING_SKILL_MOD\s*\)") -and
    ($runtimeProbe -match "hasSchematic\s*\(\s*player\s*,\s*CRAFTING_SCHEMATIC\s*\)") -and
    ($runtimeProbe -match "vectorCommandsOwned=") -and
    ($runtimeProbe -match "vectorModsMatched=") -and
    ($runtimeProbe -match "vectorSchematicsOwned=") -and
    ($runtimeProbe -match "vectorCommands=") -and
    ($runtimeProbe -match "vectorMods=") -and
    ($runtimeProbe -match "vectorSchematics=") -and
    ($runtimeProbe -match "java\.util\.Arrays\.sort\s*\(\s*vectorSchematicNames\s*\)") -and
    ($runtimeProbe -match "vectorComplete=") -and
    ($runtimeProbe -match "lifecycleAttemptId=") -and
    ($runtimeProbe -match "lifecycleMarkerState=") -and
    ($runtimeProbe -match "lifecycleBaselineComplete=") -and
    ($runtimeProbe -match "operationAttemptId=") -and
    ($runtimeProbe -match "operationMarkerComplete=") -and
    ($runtimeProbe -match "operationPreimageMatches=") -and
    ($runtimeProbe -match "operationProtocolVersion=") -and
    ($runtimeProbe -match "operationRefundGeneration=") -and
    ($runtimeProbe -match "operationRefundAttemptKey=") -and
    ($runtimeProbe -match "operationRefundRetryConsumed=") -and
    ($runtimeProbe -match "operationAccountingAttemptKey=") -and
    ($runtimeProbe -match "operationAccountingAccount=") -and
    ($runtimeProbe -match "operationAccountingOutcome=") -and
    ($runtimeProbe -match "dataTableGetStringColumnNoDefaults\s*\(\s*SCHEMATIC_GROUP_TABLE")
)
Add-PhaseCheck -Id "phaseA.runtime.crafting-observability" -Passed $craftingProbeReady -Detail "fixture-bound status must expose credits plus the complete Artisan novice/Engineering command, mod, and concrete-schematic vector"

$phaseAOperationCallbacksReady = (
    ($teacherScript -match 'PRECU_PARAM_ID\s*=\s*"precuPhaseAOperationId"') -and
    ($teacherScript -match 'PRECU_PROTOCOL_VERSION\s*=\s*64') -and
    ($teacherScript -match 'hasAnyPhaseATag\s*\(') -and
    ($teacherScript -match 'params\.containsKey\s*\(\s*PRECU_PARAM_ID\s*\)') -and
    ($teacherScript -match 'params\.containsKey\s*\(\s*PRECU_PARAM_KIND\s*\)') -and
    ($teacherScript -match 'params\.containsKey\s*\(\s*PRECU_LIFECYCLE_PARAM_ID\s*\)') -and
    ($teacherScript -match 'phaseATagged\s*&&\s*!phaseAOperation') -and
    ($teacherScript -match 'isExactActivePhaseAOperation\s*\(') -and
    ($teacherScript -match 'PRECU_OP_ATTEMPT_ID') -and
    ($teacherScript -match 'PRECU_LIFECYCLE_ATTEMPT_ID') -and
    ($teacherScript -match '"established"\.equals\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*PRECU_LIFECYCLE_STATE') -and
    ($teacherScript -match '(?s)"paymentSucceededCallback".*?"purchaseApplying".*?PRECU_VECTOR_DEBIT.*?completeSkillPurchase\s*\(.*?claimPhaseAAccountingRequest.*?"precuPhaseARequestAccounting"') -and
    ($teacherScript -match '(?s)claimInitialPhaseARefund.*?"refundInitialClaiming".*?dispatchClaimedPhaseARefund') -and
    ($teacherScript -match '(?s)precuPhaseARefundSucceeded\s*\(.*?transitionExactPhaseARefund\s*\(.*?family\s*\+\s*"Dispatching".*?family\s*\+\s*"Pending".*?"purchaseRefunded".*?PRECU_VECTOR_REFUND') -and
    ($teacherScript -match '(?s)precuPhaseARefundFailed\s*\(.*?transitionExactPhaseARefund\s*\(.*?family\s*\+\s*"Dispatching".*?family\s*\+\s*"Pending".*?family\s*\+\s*"Failed".*?PRECU_VECTOR_DEBIT') -and
    ($teacherScript -match 'precuPhaseARefundSucceeded\s*\(') -and
    ($teacherScript -match 'precuPhaseARefundFailed\s*\(') -and
    ($teacherScript -match 'transferBankCreditsTo\s*\(') -and
    ($playerMoneyScript -match 'precuPhaseARequestAccounting\s*\(') -and
    ($playerMoneyScript -match 'transferBankCreditsToNamedAccount\s*\(') -and
    ($playerMoneyScript -match 'money\.ACCT_SKILL_TRAINING') -and
    ($playerMoneyScript -match 'precuPhaseAAccountingSucceeded\s*\(') -and
    ($playerMoneyScript -match 'precuPhaseAAccountingFailed\s*\(') -and
    ($playerMoneyScript -match '(?s)hasAnyPhaseATag\s*\(\s*params\s*\).*?!transitionPhaseAPurchaseStage\s*\(') -and
    ($playerMoneyScript -match 'PRECU_OP_ATTEMPT_ID') -and
    ($playerMoneyScript -match 'PRECU_LIFECYCLE_ATTEMPT_ID') -and
    ($playerMoneyScript -match 'return\s+terminalState\.equals\s*\(\s*getStringObjVar')
)
$persistentPurchaseVectorWindow = $(if ([string]::IsNullOrEmpty($runtimeProbe))
{
    ""
}
else
{
    Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactPersistentCraftingGrantVector\s*\("
})
$clearLifecycleWindowMatch = [regex]::Match(
    $runtimeProbe,
    '(?s)if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"clearLifecycle"\s*\)\s*\).*?(?=if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"craftingStatus"\s*\))'
)
$clearLifecycleWindow = $(if ($clearLifecycleWindowMatch.Success) { $clearLifecycleWindowMatch.Value } else { "" })

$beginLifecycleWindowMatch = [regex]::Match(
    $runtimeProbe,
    '(?s)if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"beginLifecycle"\s*\)\s*\).*?(?=if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"clearLifecycle"\s*\))'
)
$beginLifecycleWindow = $(if ($beginLifecycleWindowMatch.Success) { $beginLifecycleWindowMatch.Value } else { "" })
$beginLifecycleWrites = @([regex]::Matches($beginLifecycleWindow, 'setObjVar\s*\([^;]+;'))
$lifecycleMarkerStateWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+String\s+getLifecycleMarkerState\s*\("
$clearTerminalOperationWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+String\s+clearTerminalOperation\s*\("
$operationAttemptOnlyWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+isOperationAttemptOnly\s*\("
$operationMarkerCompleteWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+isOperationMarkerComplete\s*\("
$operationReservationPrefixWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactOperationReservationWritePrefix\s*\("
$rollbackOperationReservationWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+String\s+rollbackOperationReservation\s*\("
$beginOperationWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+String\s+beginOperation\s*\("
$teacherAttemptedPaymentWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "public\s+int\s+attemptedPayment\s*\("
$payDepositWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "public\s+int\s+handlePayDeposit\s*\("
$payPassWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "public\s+int\s+handlePayPass\s*\("
$payFailWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "public\s+int\s+handlePayFail\s*\("
$paymentRequestWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "public\s+int\s+handlePaymentRequest\s*\("
$purchaseStageWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "private\s+boolean\s+isExactActivePhaseAPurchaseStage\s*\("
$teacherPhaseAOperationWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "private\s+boolean\s+isExactActivePhaseAOperation\s*\("
$teacherTransitionWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "private\s+boolean\s+transitionPhaseAOperation\s*\("
$teacherRefundSuccessWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "public\s+int\s+precuPhaseARefundSucceeded\s*\("
$teacherRefundFailureWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "public\s+int\s+precuPhaseARefundFailed\s*\("
$teacherRefundCheckpointWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "private\s+boolean\s+checkpointPhaseARefundPending\s*\("
$teacherAttemptedEnvelopeWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "private\s+boolean\s+hasExactAttemptedPaymentEnvelope\s*\("
$teacherAccountingClaimWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "private\s+boolean\s+claimPhaseAAccountingRequest\s*\("
$teacherRefundClaimWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "private\s+boolean\s+claimInitialPhaseARefund\s*\("
$teacherRefundDispatchWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "private\s+boolean\s+dispatchClaimedPhaseARefund\s*\("
$paymentHandlerEnvelopeWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "private\s+boolean\s+hasExactHandlerEnvelope\s*\("
$nativePaymentEnvelopeWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "private\s+boolean\s+hasExactNativePaymentEnvelope\s*\("
$accountingRequestWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "public\s+int\s+precuPhaseARequestAccounting\s*\("
$accountingSuccessWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "public\s+int\s+precuPhaseAAccountingSucceeded\s*\("
$accountingFailureWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "public\s+int\s+precuPhaseAAccountingFailed\s*\("
$accountingAttemptWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "private\s+boolean\s+hasExactPhaseAAccountingAttempt\s*\("
$teacherSchematicVectorWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "private\s+boolean\s+hasExactPhaseASchematicVector\s*\("
$playerSchematicVectorWindow = Get-JavaMethodWindow -Source $playerMoneyScript -SignaturePattern "private\s+boolean\s+hasExactPhaseASchematicVector\s*\("
$positiveTrainerOidWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+isValidPositiveTrainerOid\s*\("
$validatePurchaseOperationWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+String\s+validateExactPurchaseOperation\s*\("
$purchaseLineageWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactPurchasePreimageLineage\s*\("
$purchasePreVectorWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactPurchasePreVector\s*\("
$purchaseDebitVectorWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactPurchaseDebitVector\s*\("
$purchaseRefundVectorWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactPurchaseRefundVector\s*\("
$purchaseHeldVectorWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactPurchaseHeldVector\s*\("
$purchaseCallbackDictionaryWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+dictionary\s+buildExactPurchaseCallbackParams\s*\("
$purchaseVectorDispatchWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactPurchaseVector\s*\("
$purchaseTransitionWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+transitionExactPurchaseState\s*\("
$persistedRefundStateWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+isExactPersistedRefundState\s*\("
$dispatchClaimedRefundWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+dispatchExactClaimedRefund\s*\("
$clearableTerminalVectorWindow = Get-JavaMethodWindow -Source $runtimeProbe -SignaturePattern "private\s+boolean\s+hasExactClearableTerminalVector\s*\("
$requeuePurchaseCallbackWindowMatch = [regex]::Match(
    $runtimeProbe,
    '(?s)if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"requeuePurchaseCallback"\s*\)\s*\).*?(?=if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"reconcileRefundOutcome"\s*\))'
)
$requeuePurchaseCallbackWindow = $(if ($requeuePurchaseCallbackWindowMatch.Success) { $requeuePurchaseCallbackWindowMatch.Value } else { "" })
$reconcileRefundOutcomeWindowMatch = [regex]::Match(
    $runtimeProbe,
    '(?s)if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"reconcileRefundOutcome"\s*\)\s*\).*?(?=if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"retryPurchaseRefund"\s*\))'
)
$reconcileRefundOutcomeWindow = $(if ($reconcileRefundOutcomeWindowMatch.Success) { $reconcileRefundOutcomeWindowMatch.Value } else { "" })
$retryPurchaseRefundWindowMatch = [regex]::Match(
    $runtimeProbe,
    '(?s)if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"retryPurchaseRefund"\s*\)\s*\).*?(?=if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"resumePurchaseAccounting"\s*\))'
)
$retryPurchaseRefundWindow = $(if ($retryPurchaseRefundWindowMatch.Success) { $retryPurchaseRefundWindowMatch.Value } else { "" })
$resumePurchaseAccountingWindowMatch = [regex]::Match(
    $runtimeProbe,
    '(?s)if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"resumePurchaseAccounting"\s*\)\s*\).*?(?=if\s*\(\s*action\.equalsIgnoreCase\s*\(\s*"armRestartBoundary"\s*\))'
)
$resumePurchaseAccountingWindow = $(if ($resumePurchaseAccountingWindowMatch.Success) { $resumePurchaseAccountingWindowMatch.Value } else { "" })
$phaseAReconcileCorrelationReady = (
    ($operationMarkerCompleteWindow -match 'getIntObjVar\s*\(\s*player\s*,\s*OP_UPDATED\s*\)\s*>\s*0') -and
    ($clearTerminalOperationWindow -match '(?s)!preDispatch\s*&&.*?!isOperationMarkerComplete\s*\(\s*player\s*\).*?!hasExactClearableTerminalVector') -and
    ($teacherPhaseAOperationWindow -match 'getIntObjVar\s*\(\s*player\s*,\s*PRECU_OP_UPDATED\s*\)\s*<=\s*0') -and
    ($purchaseStageWindow -match 'getIntObjVar\s*\(\s*self\s*,\s*PRECU_OP_UPDATED\s*\)\s*<=\s*0') -and
    ($validatePurchaseOperationWindow -match 'validateLifecycle\s*\(\s*player\s*,\s*lifecycleId\s*\)') -and
    ($validatePurchaseOperationWindow -match '!isOperationMarkerComplete\s*\(\s*player\s*\)') -and
    ($validatePurchaseOperationWindow -match '!operationId\.equals\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*OP_ATTEMPT_ID') -and
    ($validatePurchaseOperationWindow -match '!CRAFTING_SKILL\.equals\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*OP_SKILL_NAME') -and
    ($validatePurchaseOperationWindow -match 'getIntObjVar\s*\(\s*player\s*,\s*OP_COST\s*\)\s*!=\s*CRAFTING_TRAINER_COST') -and
    ($validatePurchaseOperationWindow -match '!isValidPositiveTrainerOid\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*OP_TRAINER_OID') -and
    ($validatePurchaseOperationWindow -match 'hasExactPurchasePreimageLineage\s*\(\s*player\s*\)') -and
    ($validatePurchaseOperationWindow -match 'OP_PROTOCOL_VERSION') -and
    ($resumePurchaseAccountingWindow -match '(?s)hasExactAccountingSuccessProvenance\s*\(\s*player\s*\).*?"accountingDispatching".*?"accountingPending".*?"accountingSucceededCallback".*?setObjVar\s*\(\s*player\s*,\s*OP_STATE\s*,\s*"purchaseSucceeded"') -and
    ($resumePurchaseAccountingWindow -match '(?s)"purchaseApplying"\.equals\s*\(\s*operationState\s*\).*?claimExactAccountingRequest.*?"accountingRequested".*?hasExactPendingAccountingProvenance.*?messageTo\s*\(\s*player\s*,\s*"precuPhaseARequestAccounting"') -and
    ($resumePurchaseAccountingWindow -notmatch 'transitionExactPurchaseState\s*\(.*?"purchaseSucceeded"|money\.requestPayment|money\.pay\s*\(|transferBankCreditsToNamedAccount\s*\(') -and
    ($positiveTrainerOidWindow -match 'trainerOid\.matches\s*\(\s*"\[0-9\]\+"\s*\)') -and
    ($positiveTrainerOidWindow -match 'Long\.parseLong\s*\(\s*trainerOid\s*\)\s*>\s*0L') -and
    ($positiveTrainerOidWindow -match 'catch\s*\(\s*NumberFormatException\s+exception\s*\)')
)

$lifecycleIdCommitCount = [regex]::Matches(
    $beginLifecycleWindow,
    'setObjVar\s*\(\s*player\s*,\s*LIFECYCLE_ID\s*,'
).Count
$lifecycleCommitTail = ""
if ($lifecycleIdCommitCount -eq 1)
{
    $commitMatch = [regex]::Match($beginLifecycleWindow, 'setObjVar\s*\(\s*player\s*,\s*LIFECYCLE_ID\s*,')
    $lifecycleCommitTail = $beginLifecycleWindow.Substring($commitMatch.Index + $commitMatch.Length)
}
$phaseALifecycleCommitReady = (
    $beginLifecycleWrites.Count -gt 0 -and
    $lifecycleIdCommitCount -eq 1 -and
    ($beginLifecycleWrites[$beginLifecycleWrites.Count - 1].Value -match 'LIFECYCLE_ID') -and
    ($beginLifecycleWindow -match '(?s)setObjVar\s*\(\s*player\s*,\s*LIFECYCLE_STATE\s*,\s*"established"\s*\).*?isLifecycleBaselineComplete\s*\(\s*player\s*\).*?lifecycleBaselineEquals\s*\(.*?lifecycleBaselineMatchesCurrent\s*\(\s*player\s*\).*?setObjVar\s*\(\s*player\s*,\s*LIFECYCLE_ID\s*,') -and
    ($lifecycleCommitTail -notmatch 'setObjVar\s*\(|removeObjVar\s*\(|rollbackLifecycleEstablishment\s*\(') -and
    ($lifecycleMarkerStateWindow -match '(?s)"none"\.equals\s*\(\s*lifecycleId\s*\).*?"missing"\.equals\s*\(\s*storedState\s*\).*?"establishing"\.equals\s*\(\s*storedState\s*\).*?"established"\.equals\s*\(\s*storedState\s*\).*?return\s+"partial"')
)

$operationAttemptOnlyReady = ($operationAttemptOnlyWindow -match 'hasObjVar\s*\(\s*player\s*,\s*OP_ATTEMPT_ID\s*\)')
foreach ($leaf in @(
    "OP_ID", "OP_KIND", "OP_STATE", "OP_UPDATED", "OP_LIFECYCLE_ID",
    "OP_TRAINER_OID", "OP_SKILL_NAME", "OP_COST", "OP_PRE_CREDITS",
    "OP_PRE_CASH", "OP_PRE_BANK", "OP_PRE_XP", "OP_PRE_POINTS", "OP_PRE_CAP",
    "OP_PRE_NOVICE", "OP_PRE_SKILL", "OP_PROTOCOL_VERSION",
    "OP_REFUND_GENERATION", "OP_REFUND_ATTEMPT_KEY", "OP_REFUND_RETRY_CONSUMED",
    "OP_ACCOUNTING_ATTEMPT_KEY", "OP_ACCOUNTING_ACCOUNT", "OP_ACCOUNTING_OUTCOME"))
{
    $operationAttemptOnlyReady = $operationAttemptOnlyReady -and
        ($operationAttemptOnlyWindow -match ('!hasObjVar\s*\(\s*player\s*,\s*' + [regex]::Escape($leaf) + '\s*\)'))
}
$expectedOperationReservationWrites = @(
    "OP_ATTEMPT_ID", "OP_STATE", "OP_KIND", "OP_UPDATED", "OP_LIFECYCLE_ID",
    "OP_TRAINER_OID", "OP_SKILL_NAME", "OP_COST", "OP_PRE_CREDITS", "OP_PRE_CASH",
    "OP_PRE_BANK", "OP_PRE_XP", "OP_PRE_POINTS", "OP_PRE_CAP", "OP_PRE_NOVICE",
    "OP_PRE_SKILL", "OP_PROTOCOL_VERSION", "OP_REFUND_GENERATION",
    "OP_REFUND_ATTEMPT_KEY", "OP_REFUND_RETRY_CONSUMED", "OP_ACCOUNTING_ATTEMPT_KEY",
    "OP_ACCOUNTING_ACCOUNT", "OP_ACCOUNTING_OUTCOME", "OP_ID", "OP_STATE"
)
$actualOperationReservationWrites = @(
    [regex]::Matches(
        $beginOperationWindow,
        'setObjVar\s*\(\s*player\s*,\s*(OP_[A-Z_]+)\s*,'
    ) | ForEach-Object { [string]$_.Groups[1].Value }
)
$operationReservationWriteOrderReady = (
    $actualOperationReservationWrites.Count -eq $expectedOperationReservationWrites.Count -and
    (($actualOperationReservationWrites -join ([char]0)) -ceq
        ($expectedOperationReservationWrites -join ([char]0)))
)
$operationReservationWriterOwnershipReady = $true
foreach ($leaf in @(
    "OP_ATTEMPT_ID", "OP_ID", "OP_KIND", "OP_LIFECYCLE_ID", "OP_TRAINER_OID",
    "OP_SKILL_NAME", "OP_COST", "OP_PRE_CREDITS", "OP_PRE_CASH", "OP_PRE_BANK",
    "OP_PRE_XP", "OP_PRE_POINTS", "OP_PRE_CAP", "OP_PRE_NOVICE", "OP_PRE_SKILL",
    "OP_PROTOCOL_VERSION"))
{
    $operationReservationWriterOwnershipReady =
        $operationReservationWriterOwnershipReady -and
        ([regex]::Matches(
            $runtimeProbe,
            ('setObjVar\s*\(\s*player\s*,\s*' + [regex]::Escape($leaf) + '\s*,')
        ).Count -eq 1)
}
$operationReservationWriterOwnershipReady =
    $operationReservationWriterOwnershipReady -and
    ([regex]::Matches($runtimeProbe, 'removeObjVar\s*\(\s*player\s*,\s*OP_ROOT\s*\)').Count -eq 2) -and
    ($rollbackOperationReservationWindow -match 'removeObjVar\s*\(\s*player\s*,\s*OP_ROOT\s*\)') -and
    ($clearTerminalOperationWindow -match 'removeObjVar\s*\(\s*player\s*,\s*OP_ROOT\s*\)')
$operationReservationPrefixReady = (
    $operationReservationWriteOrderReady -and
    $operationReservationWriterOwnershipReady -and
    ($operationReservationPrefixWindow -match '(?s)!isValidOperationId\s*\(\s*operationId\s*\).*?!hasObjVar\s*\(\s*player\s*,\s*OP_ATTEMPT_ID\s*\).*?!operationId\.equals\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*OP_ATTEMPT_ID') -and
    ($operationReservationPrefixWindow -match '(?s)kindPresent\s*&&\s*!statePresent.*?updatedPresent\s*&&\s*!kindPresent.*?lifecyclePresent\s*&&\s*!updatedPresent.*?trainerPresent\s*&&\s*!lifecyclePresent.*?skillPresent\s*&&\s*!trainerPresent.*?costPresent\s*&&\s*!skillPresent.*?preCreditsPresent\s*&&\s*!costPresent.*?preCashPresent\s*&&\s*!preCreditsPresent.*?preBankPresent\s*&&\s*!preCashPresent.*?preXpPresent\s*&&\s*!preBankPresent.*?prePointsPresent\s*&&\s*!preXpPresent.*?preCapPresent\s*&&\s*!prePointsPresent.*?preNovicePresent\s*&&\s*!preCapPresent.*?preSkillPresent\s*&&\s*!preNovicePresent.*?protocolPresent\s*&&\s*!preSkillPresent.*?refundGenerationPresent\s*&&\s*!protocolPresent.*?refundAttemptKeyPresent\s*&&\s*!refundGenerationPresent.*?refundRetryConsumedPresent\s*&&\s*!refundAttemptKeyPresent.*?accountingAttemptKeyPresent\s*&&\s*!refundRetryConsumedPresent.*?accountingAccountPresent\s*&&\s*!accountingAttemptKeyPresent.*?accountingOutcomePresent\s*&&\s*!accountingAccountPresent.*?idPresent\s*&&\s*!accountingOutcomePresent') -and
    ($operationReservationPrefixWindow -match '(?s)"reserving"\.equals\s*\(\s*operationState\s*\).*?"reserved"\.equals\s*\(\s*operationState\s*\).*?"reserved"\.equals\s*\(\s*operationState\s*\)\s*&&\s*!idPresent') -and
    ($operationReservationPrefixWindow -match '(?s)"fund"\.equals\s*\(\s*operationKind\s*\).*?"drain"\.equals\s*\(\s*operationKind\s*\).*?"purchase"\.equals\s*\(\s*operationKind\s*\).*?isValidPositiveTrainerOid.*?CRAFTING_SKILL\.equals.*?CRAFTING_TRAINER_COST.*?partialOperationPreimageMatchesCurrent.*?PROTOCOL_VERSION.*?OP_REFUND_GENERATION.*?OP_REFUND_RETRY_CONSUMED.*?OP_ACCOUNTING_OUTCOME.*?operationId\.equals\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*OP_ID') -and
    ($rollbackOperationReservationWindow -match 'hasExactOperationReservationWritePrefix\s*\(\s*player\s*,\s*operationId\s*\)') -and
    ($clearTerminalOperationWindow -match 'hasExactOperationReservationWritePrefix\s*\(\s*player\s*,\s*operationId\s*\)')
)
$phaseAAttemptOnlyRecoveryReady = (
    $operationAttemptOnlyReady -and
    $operationReservationPrefixReady -and
    ($clearTerminalOperationWindow -match '(?s)"missing"\.equals\s*\(\s*operationState\s*\).*?isOperationAttemptOnly\s*\(\s*player\s*\)') -and
    ($clearTerminalOperationWindow -match 'operationId\.equals\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*OP_ATTEMPT_ID\s*\)\s*\)') -and
    ($clearTerminalOperationWindow -match 'preDispatch\s*=\s*attemptOnly\s*\|\|') -and
    ($clearTerminalOperationWindow -match 'partialOperationPreimageMatchesCurrent\s*\(\s*player\s*\)') -and
    ($clearTerminalOperationWindow -match 'RELOG_NONCE') -and
    ($clearTerminalOperationWindow -match 'RESTART_NONCE') -and
    ($clearTerminalOperationWindow -match 'removeObjVar\s*\(\s*player\s*,\s*OP_ROOT\s*\)')
)

$teacherCallbackLeavesReady = $true
foreach ($leaf in @(
    "PRECU_OP_ATTEMPT_ID", "PRECU_OP_ID", "PRECU_OP_KIND", "PRECU_OP_STATE",
    "PRECU_OP_UPDATED", "PRECU_OP_LIFECYCLE_ID", "PRECU_OP_TRAINER_OID",
    "PRECU_OP_SKILL_NAME", "PRECU_OP_COST", "PRECU_OP_PRE_CREDITS",
    "PRECU_OP_PRE_CASH", "PRECU_OP_PRE_BANK", "PRECU_OP_PRE_XP",
    "PRECU_OP_PRE_POINTS", "PRECU_OP_PRE_CAP", "PRECU_OP_PRE_NOVICE",
    "PRECU_OP_PRE_SKILL", "PRECU_OP_PROTOCOL_VERSION",
    "PRECU_OP_REFUND_GENERATION", "PRECU_OP_REFUND_ATTEMPT_KEY",
    "PRECU_OP_REFUND_RETRY_CONSUMED", "PRECU_OP_ACCOUNTING_ATTEMPT_KEY",
    "PRECU_OP_ACCOUNTING_ACCOUNT", "PRECU_OP_ACCOUNTING_OUTCOME",
    "PRECU_LIFECYCLE_ATTEMPT_ID", "PRECU_LIFECYCLE_ID",
    "PRECU_LIFECYCLE_STATE", "PRECU_LIFECYCLE_BASE_CASH",
    "PRECU_LIFECYCLE_BASE_BANK", "PRECU_LIFECYCLE_BASE_XP",
    "PRECU_LIFECYCLE_BASE_POINTS", "PRECU_LIFECYCLE_BASE_CAP",
    "PRECU_LIFECYCLE_BASE_NOVICE", "PRECU_LIFECYCLE_BASE_SKILL"))
{
    $teacherCallbackLeavesReady = $teacherCallbackLeavesReady -and
        ($teacherPhaseAOperationWindow -match ('hasObjVar\s*\(\s*player\s*,\s*' + [regex]::Escape($leaf) + '\s*\)'))
}
$trainerCallbackPolicy = $contract.phaseATrainerCallbackPolicy
$expectedTrainerPreimageLeaves = @(
    "preCredits", "preCash", "preBank", "preXp", "prePoints", "preCap",
    "preNovice", "preSkill"
)
$contractTrainerPreimageLeaves = @($trainerCallbackPolicy.requiredOperationPreimageLeaves | ForEach-Object { [string]$_ })
$trainerCallbackContractReady = (
    $contractTrainerPreimageLeaves.Count -eq $expectedTrainerPreimageLeaves.Count -and
    (($contractTrainerPreimageLeaves -join ([char]0)) -ceq ($expectedTrainerPreimageLeaves -join ([char]0))) -and
    [string]$trainerCallbackPolicy.successBalances -ceq "exact-bank-first-post-debit" -and
    [string]$trainerCallbackPolicy.failureBalances -ceq "exact-no-debit-preimage" -and
    [string]$trainerCallbackPolicy.invalidTaggedCallbackDisposition -ceq "quarantine-before-side-effects"
)
$purchaseProtocol = $contract.phaseAPurchaseProtocol
$protocolReplayStates = @($purchaseProtocol.changedProcessRecovery.callbackReplayStates | ForEach-Object { [string]$_ })
$protocolRefundRequirements = @($purchaseProtocol.refund.debitRetryRequirements | ForEach-Object { [string]$_ })
$protocolAccountingFailures = @($purchaseProtocol.accounting.failureStates | ForEach-Object { [string]$_ })
$protocolInitialRefundStates = @($purchaseProtocol.refund.initialStates | ForEach-Object { [string]$_ })
$protocolRecoveryRefundStates = @($purchaseProtocol.refund.recoveryStates | ForEach-Object { [string]$_ })
$protocolSafeRefundResumeStates = @($purchaseProtocol.refund.safeResumeStates | ForEach-Object { [string]$_ })
$protocolPersistentLeaves = @($purchaseProtocol.persistentOperationLeaves | ForEach-Object { [string]$_ })
$trainerEnvelopeCodes = @($trainerCallbackPolicy.requiredEnvelope.explicitReturnCodes | ForEach-Object { [int]$_ })
$runnerRecovery = $purchaseProtocol.runnerRecoveryCheckpointing
$accountingRecoveryPair = $runnerRecovery.allowedRecoveryPairs.restartAccountingResume
$callbackRecoveryPair = $runnerRecovery.allowedRecoveryPairs.restartCallbackReplay
$refundOutcomeRecoveryPair = $runnerRecovery.allowedRecoveryPairs.restartRefundOutcome
$refundRetryRecoveryPair = $runnerRecovery.allowedRecoveryPairs.restartRefundRetry
$expectedReservationWriteOrder = @(
    "attemptId", "state=reserving", "kind", "updated", "lifecycleId", "trainerOid",
    "skillName", "cost", "preCredits", "preCash", "preBank", "preXp", "prePoints",
    "preCap", "preNovice", "preSkill", "protocolVersion", "refundGeneration",
    "refundAttemptKey", "refundRetryConsumed", "accountingAttemptKey",
    "accountingAccount", "accountingOutcome", "id", "state=reserved"
)
$runnerRecoveryContractReady = (
    [int]$runtimeSlice.runnerSchemaVersion -eq 8 -and
    [int]$runtimeSlice.snapshotSchemaVersion -eq 8 -and
    [string]$runtimeSlice.runtimeContractId -ceq "phase-a-trainer-persistence-v6.4" -and
    [string]$runnerRecovery.runnerSemanticsVersion -ceq "6.5" -and
    [string]$runnerRecovery.serverProtocolCompatibility -ceq "v6.4-protocol-64-unchanged" -and
    (@($runnerRecovery.settlementOrdering | ForEach-Object { [string]$_ }) -join ',') -ceq "synchronize-authoritative-marker,evaluate-recoverable-settled-failures,evaluate-generic-terminal-or-fail-closed" -and
    (@($runnerRecovery.recoverableSettledStates | ForEach-Object { [string]$_ }) -join ',') -ceq "refundInitialFailed,refundRecoveryFailed" -and
    [string]$runnerRecovery.candidatePolicy -ceq "clone-state-plus-seven-provenance-leaves-normalize-full-validate-json-roundtrip-full-validate" -and
    [string]$runnerRecovery.intentPolicy -ceq "validated-atomic-snapshot-before-recovery-rpc" -and
    (@($runnerRecovery.postActionPolicy.refreshOn | ForEach-Object { [string]$_ }) -join ',') -ceq "success,timeout,exception" -and
    [string]$runnerRecovery.postActionPolicy.correlatedStateDisposition -ceq "normalize-validate-and-atomically-save-before-return-or-rethrow" -and
    [string]$runnerRecovery.postActionPolicy.invalidRefreshDisposition -ceq "retain-last-valid-intent-snapshot" -and
    [string]$runnerRecovery.postActionPolicy.actionErrorDisposition -ceq "rethrow-original-after-best-effort-refresh" -and
    [string]$runnerRecovery.recoveryAuditPolicy -ceq "retain-latest-action-source-and-process-token-across-reachable-advanced-states" -and
    [string]$runnerRecovery.targetNormalizationPolicy -ceq "clear-advanced-callback-accounting-and-retry-targets;retain-active-synchronous-refund-reconcile-target-until-purchaseRefunded" -and
    (@($runnerRecovery.reservationWriteOrder | ForEach-Object { [string]$_ }) -join ',') -ceq ($expectedReservationWriteOrder -join ',') -and
    [string]$runnerRecovery.preDispatchPartialPolicy -ceq "missing-or-reserving-requires-gap-free-observable-write-prefix-neutral-provenance-unchanged-preimage-and-no-volatile-nonces" -and
    [string]$runnerRecovery.serverReservationPrefixPolicy -ceq "recompute-exact-25-write-prefix-values-immediately-before-rollback-or-clear" -and
    [string]$runnerRecovery.completeMarkerTimestampPolicy -ceq "all-complete-and-terminal-markers-require-positive-operation-updated" -and
    [string]$runnerRecovery.clearSuccessPolicy -ceq "require-cleared-true-plus-authoritative-marker-absent-readback" -and
    [string]$runnerRecovery.markerAbsentPolicy -ceq "require-zero-operation-instrumentation-before-discard-or-clear" -and
    [string]$accountingRecoveryPair.activeTarget -ceq "resumePurchaseAccounting" -and
    (@($accountingRecoveryPair.activeStates | ForEach-Object { [string]$_ }) -join ',') -ceq "purchaseApplying,accountingRequested,accountingDispatching,accountingPending,accountingSucceededCallback" -and
    (@($accountingRecoveryPair.blankTargetStates | ForEach-Object { [string]$_ }) -join ',') -ceq "purchaseApplying,accountingRequested,accountingRequestQueueFailed,accountingDispatching,accountingPending,accountingQueueFailed,accountingFailed,accountingSucceededCallback,purchaseSucceeded" -and
    [string]$callbackRecoveryPair.activeTarget -ceq "requeuePurchaseCallback" -and
    (@($callbackRecoveryPair.activeStates | ForEach-Object { [string]$_ }) -join ',') -ceq "paymentDispatching,paymentSucceededCallback,purchaseApplying" -and
    (@($callbackRecoveryPair.blankTargetStates | ForEach-Object { [string]$_ }) -join ',') -ceq "paymentDispatching,paymentSucceededCallback,purchaseApplying,accountingRequested,accountingRequestQueueFailed,accountingDispatching,accountingPending,accountingQueueFailed,accountingFailed,accountingSucceededCallback,purchaseSucceeded,refundInitialClaiming,refundInitialDispatching,refundInitialPending,refundInitialFailed,purchaseRefunded" -and
    [string]$refundOutcomeRecoveryPair.activeTarget -ceq "reconcileRefundOutcome" -and
    (@($refundOutcomeRecoveryPair.activeStates | ForEach-Object { [string]$_ }) -join ',') -ceq "refundInitialClaiming,refundInitialDispatching,refundInitialPending,refundInitialFailed,refundRecoveryClaiming,refundRecoveryDispatching,refundRecoveryPending,refundRecoveryFailed" -and
    (@($refundOutcomeRecoveryPair.blankTargetStates | ForEach-Object { [string]$_ }) -join ',') -ceq "purchaseRefunded" -and
    [string]$refundRetryRecoveryPair.activeTarget -ceq "retryPurchaseRefund" -and
    (@($refundRetryRecoveryPair.activeStates | ForEach-Object { [string]$_ }) -join ',') -ceq "refundInitialClaiming,refundInitialFailed,refundRecoveryClaiming" -and
    (@($refundRetryRecoveryPair.blankTargetStates | ForEach-Object { [string]$_ }) -join ',') -ceq "refundInitialClaiming,refundInitialDispatching,refundInitialPending,refundInitialFailed,refundRecoveryClaiming,refundRecoveryDispatching,refundRecoveryPending,refundRecoveryFailed,purchaseRefunded"
)
$phaseAPurchaseProtocolContractReady = (
    $runnerRecoveryContractReady -and
    [int]$purchaseProtocol.protocolVersion -eq 64 -and
    [string]$purchaseProtocol.authoritativeVectors.PRE -ceq "full-lifecycle-relative-bank-funded-preimage-plus-exact-prepared-command-mod-35-schematic-vector-no-target-grant" -and
    [string]$purchaseProtocol.authoritativeVectors.DEBIT -ceq "exact-bank-first-post-debit-plus-exact-prepared-command-mod-35-schematic-vector-no-target-grant" -and
    [string]$purchaseProtocol.authoritativeVectors.HELD -ceq "exact-post-debit-complete-two-command-six-mod-35-schematic-grant-trained-cap-2000" -and
    [string]$purchaseProtocol.authoritativeVectors.REFUND -ceq "exact-restored-pre-balances-plus-exact-prepared-command-mod-35-schematic-vector-no-target-grant" -and
    [string]$trainerCallbackPolicy.requiredEnvelope.handler -ceq "attemptedPayment" -and
    [string]$trainerCallbackPolicy.requiredEnvelope.payHandler -ceq "attemptedPayment" -and
    (($trainerEnvelopeCodes -join ',') -ceq "0,1") -and
    [string]$trainerCallbackPolicy.requiredEnvelope.trainerMissingReturnCodeDisposition -ceq "quarantine-before-stock-normalization" -and
    [string]$trainerCallbackPolicy.requiredEnvelope.nativeMissingReturnCodeDisposition -ceq "accept-only-when-getReturnCode-is-minus-one" -and
    [string]$trainerCallbackPolicy.requiredEnvelope.unknownReturnCodeDisposition -ceq "quarantine" -and
    (($protocolPersistentLeaves -join ',') -ceq "protocolVersion,refundGeneration,refundAttemptKey,refundRetryConsumed,accountingAttemptKey,accountingAccount,accountingOutcome") -and
    [string]$purchaseProtocol.playerMoneyDispatch.requiredVector -ceq "PRE" -and
    [bool]$purchaseProtocol.playerMoneyDispatch.requiresFullLifecycleRelativePreimage -and
    [string]$purchaseProtocol.playerMoneyDispatch.sideEffectAfterProof -ceq "money.pay" -and
    (($protocolReplayStates -join ([char]0)) -ceq (@("paymentDispatching", "paymentSucceededCallback", "purchaseApplying") -join ([char]0))) -and
    [string]$purchaseProtocol.changedProcessRecovery.callbackReplayVector -ceq "DEBIT" -and
    [string]$purchaseProtocol.changedProcessRecovery.callbackReplayAction -ceq "requeuePurchaseCallback" -and
    [string]$purchaseProtocol.changedProcessRecovery.callbackReplayPath -ceq "exact-reconstructed-attemptedPayment-only" -and
    [string]$purchaseProtocol.changedProcessRecovery.purchaseApplyingHeldAction -ceq "resumePurchaseAccounting" -and
    -not [bool]$purchaseProtocol.changedProcessRecovery.heldAloneProvesSuccess -and
    [string]$purchaseProtocol.changedProcessRecovery.sameProcessInference -ceq "forbidden" -and
    [string]$purchaseProtocol.changedProcessRecovery.sameRecoveryProcessInference -ceq "forbidden" -and
    [string]$purchaseProtocol.changedProcessRecovery.partialGrantDisposition -ceq "quarantine" -and
    [string]$purchaseProtocol.changedProcessRecovery.duplicateDisposition -ceq "one-shot-state-claim-then-quarantine" -and
    [string]$purchaseProtocol.refund.entryVector -ceq "DEBIT" -and
    [string]$purchaseProtocol.refund.successVector -ceq "REFUND" -and
    [string]$purchaseProtocol.refund.failureVector -ceq "DEBIT" -and
    [string]$purchaseProtocol.refund.successMessageTiming -ceq "after-verified-terminal-transition" -and
    [string]$purchaseProtocol.refund.restoredInFlightAction -ceq "reconcileRefundOutcome-without-transfer" -and
    [string]$purchaseProtocol.refund.debitRetryAction -ceq "retryPurchaseRefund" -and
    [string]$purchaseProtocol.refund.resumeHandler -ceq "precuPhaseAResumeRefund" -and
    -not [bool]$purchaseProtocol.refund.runtimeNativeTransferAllowed -and
    (($protocolRefundRequirements -join ([char]0)) -ceq (@("changed-process", "generation-1-initial-failure-or-exact-claiming-cut", "deterministic-attempt-key", "exact-DEBIT-vector") -join ([char]0))) -and
    [int]$purchaseProtocol.refund.initialGeneration -eq 1 -and
    [int]$purchaseProtocol.refund.recoveryGeneration -eq 2 -and
    [string]$purchaseProtocol.refund.attemptKey -ceq "<operationId>.refund.<generation>" -and
    [int]$purchaseProtocol.refund.retryConsumedByGeneration -eq 2 -and
    (($protocolInitialRefundStates -join ',') -ceq "refundInitialClaiming,refundInitialDispatching,refundInitialPending,refundInitialFailed") -and
    (($protocolRecoveryRefundStates -join ',') -ceq "refundRecoveryClaiming,refundRecoveryDispatching,refundRecoveryPending,refundRecoveryFailed") -and
    (($protocolSafeRefundResumeStates -join ',') -ceq "refundInitialClaiming,refundRecoveryClaiming") -and
    [string]$purchaseProtocol.refund.queueFailureDisposition -ceq "retain-generation-family-failed-DEBIT" -and
    [string]$purchaseProtocol.refund.usedRetryIntentDisposition -ceq "retain-consumed-fail-closed" -and
    [string]$purchaseProtocol.refund.staleGenerationDisposition -ceq "quarantine" -and
    [string]$purchaseProtocol.refund.ambiguousRetryDisposition -ceq "retain-fail-closed-DEBIT" -and
    [string]$purchaseProtocol.accounting.attemptKey -ceq "<operationId>.accounting.1" -and
    [string]$purchaseProtocol.accounting.namedAccount -ceq "skillTrainingSystem" -and
    [string]$purchaseProtocol.accounting.requestHandler -ceq "precuPhaseARequestAccounting" -and
    [string]$purchaseProtocol.accounting.nativeTransfer -ceq "transferBankCreditsToNamedAccount" -and
    [string]$purchaseProtocol.accounting.successHandler -ceq "precuPhaseAAccountingSucceeded" -and
    [string]$purchaseProtocol.accounting.failureHandler -ceq "precuPhaseAAccountingFailed" -and
    [string]$purchaseProtocol.accounting.resumeAction -ceq "resumePurchaseAccounting" -and
    -not [bool]$purchaseProtocol.accounting.runtimeNativeTransferAllowed -and
    [string]$purchaseProtocol.accounting.stateOutcomes.accountingRequested -ceq "none-or-REQUEST_QUEUE_FAILED-cut" -and
    [string]$purchaseProtocol.accounting.stateOutcomes.accountingDispatching -ceq "none-or-QUEUE_FAILED-or-FAILED-or-SUCCESS-callback-cut" -and
    [string]$purchaseProtocol.accounting.stateOutcomes.accountingPending -ceq "none-or-FAILED-or-SUCCESS-callback-cut" -and
    [string]$purchaseProtocol.accounting.stateOutcomes.accountingRequestQueueFailed -ceq "REQUEST_QUEUE_FAILED" -and
    [string]$purchaseProtocol.accounting.stateOutcomes.accountingQueueFailed -ceq "QUEUE_FAILED" -and
    [string]$purchaseProtocol.accounting.stateOutcomes.accountingFailed -ceq "FAILED" -and
    [string]$purchaseProtocol.accounting.stateOutcomes.accountingSucceededCallback -ceq "SUCCESS" -and
    [string]$purchaseProtocol.accounting.stateOutcomes.purchaseSucceeded -ceq "SUCCESS" -and
    [string]$purchaseProtocol.accounting.failureCutDisposition -ceq "retain-fail-closed-non-clearable" -and
    [bool]$purchaseProtocol.accounting.successRequiresCallback -and
    (($protocolAccountingFailures -join ',') -ceq "accountingRequestQueueFailed,accountingQueueFailed,accountingFailed") -and
    [string]$purchaseProtocol.accounting.failureDisposition -ceq "retain-non-clearable" -and
    [string]$purchaseProtocol.clearPolicy.purchaseSuccessRequires -ceq "HELD-plus-accounting-SUCCESS-provenance" -and
    [string]$purchaseProtocol.clearPolicy.purchaseRefundRequires -ceq "REFUND-plus-current-generation-provenance" -and
    [string]$purchaseProtocol.clearPolicy.accountingFailureDisposition -ceq "refuse-clear" -and
    [string]$purchaseProtocol.clearPolicy.refundFailureDisposition -ceq "refuse-clear"
)
$phaseAExactSchematicVectorsReady = (
    ($teacherScript -match 'PRECU_CRAFTING_SCHEMATIC_COUNT\s*=\s*35') -and
    ($playerMoneyScript -match 'PRECU_CRAFTING_SCHEMATIC_COUNT\s*=\s*35')
)
foreach ($schematicVectorWindow in @($teacherSchematicVectorWindow, $playerSchematicVectorWindow))
{
    $phaseAExactSchematicVectorsReady = $phaseAExactSchematicVectorsReady -and
        ($schematicVectorWindow -match '(?s)groupIds\s*==\s*null\s*\|\|\s*schematicNames\s*==\s*null.*?groupIds\.length\s*!=\s*schematicNames\.length') -and
        ($schematicVectorWindow -match '(?s)schematicName\s*==\s*null\s*\|\|\s*schematicName\.length\s*\(\s*\)\s*==\s*0.*?seen\.contains\s*\(\s*schematicName\s*\)') -and
        ($schematicVectorWindow -match 'return\s+seen\.size\s*\(\s*\)\s*==\s*PRECU_CRAFTING_SCHEMATIC_COUNT')
}
$phaseATrainerCallbackQuarantineReady = (
    $trainerCallbackContractReady -and
    $phaseAPurchaseProtocolContractReady -and
    $phaseAExactSchematicVectorsReady -and
    $teacherCallbackLeavesReady -and
    ($teacherPhaseAOperationWindow -match '!trainer\.isLoaded\s*\(\s*\)\s*\|\|\s*!trainer\.isAuthoritative\s*\(\s*\)') -and
    ($teacherPhaseAOperationWindow -match '!player\.isLoaded\s*\(\s*\)\s*\|\|\s*!player\.isAuthoritative\s*\(\s*\)') -and
    ($teacherPhaseAOperationWindow -match 'taggedPlayer\s*==\s*null\s*\|\|\s*!player\.equals\s*\(\s*taggedPlayer\s*\)') -and
    ($teacherPhaseAOperationWindow -match 'taggedTrainer\s*==\s*null\s*\|\|\s*!trainer\.equals\s*\(\s*taggedTrainer\s*\)') -and
    ($teacherPhaseAOperationWindow -match 'operationCost\s*!=\s*PRECU_CRAFTING_TRAINER_COST') -and
    ($teacherPhaseAOperationWindow -match 'params\.getInt\s*\(\s*money\.DICT_AMOUNT\s*\)\s*!=\s*operationCost') -and
    ($teacherPhaseAOperationWindow -match 'params\.getInt\s*\(\s*money\.DICT_TOTAL\s*\)\s*!=\s*operationCost') -and
    ($teacherPhaseAOperationWindow -match '!PRECU_CRAFTING_SKILL\.equals\s*\(\s*skillName\s*\)') -and
    ($teacherPhaseAOperationWindow -match '\(long\)preCredits\s*!=\s*\(long\)preCash\s*\+\s*\(long\)preBank') -and
    ($teacherPhaseAOperationWindow -match 'preCash\s*!=\s*baseCash') -and
    ($teacherPhaseAOperationWindow -match '\(long\)preBank\s*!=\s*\(long\)baseBank\s*\+\s*\(long\)operationCost') -and
    ($teacherPhaseAOperationWindow -match '\(long\)preXp\s*!=\s*\(long\)baseXp\s*\+\s*\(long\)PRECU_CRAFTING_XP_COST') -and
    ($teacherPhaseAOperationWindow -match 'prePoints\s*!=\s*expectedPrePoints') -and
    ($teacherPhaseAOperationWindow -match 'preCap\s*!=\s*PRECU_PREPURCHASE_XP_CAP') -and
    ($teacherPhaseAOperationWindow -match 'preNovice\s*!=\s*1\s*\|\|\s*preSkill\s*!=\s*0') -and
    ($teacherPhaseAOperationWindow -match 'bankDebit\s*=\s*preBank\s*<\s*operationCost\s*\?\s*preBank\s*:\s*operationCost') -and
    ($teacherPhaseAOperationWindow -match 'hasExactPreparedPhaseACraftingVector\s*\(\s*player\s*\)') -and
    ($teacherPhaseAOperationWindow -match 'hasExactHeldPhaseACraftingVector\s*\(\s*player\s*\)') -and
    ($teacherPhaseAOperationWindow -match 'PRECU_OP_PROTOCOL_VERSION') -and
    ($teacherTransitionWindow -match '(?s)isExactActivePhaseAOperation\s*\(.*?expectedVector\s*\).*?setObjVar\s*\(\s*player\s*,\s*PRECU_OP_STATE') -and
    ($teacherAttemptedEnvelopeWindow -match '(?s)params\.containsKey\s*\(\s*money\.DICT_HANDLER\s*\).*?params\.containsKey\s*\(\s*money\.DICT_PAY_HANDLER\s*\).*?params\.containsKey\s*\(\s*money\.DICT_CODE\s*\).*?"attemptedPayment"\.equals\s*\(\s*params\.getString\s*\(\s*money\.DICT_HANDLER\s*\)\s*\).*?"attemptedPayment"\.equals\s*\(\s*params\.getString\s*\(\s*money\.DICT_PAY_HANDLER\s*\)\s*\).*?code\s*==\s*money\.RET_SUCCESS\s*\|\|\s*code\s*==\s*money\.RET_FAIL') -and
    ($teacherAttemptedPaymentWindow -match '(?s)phaseATagged\s*&&\s*!hasExactAttemptedPaymentEnvelope\s*\(\s*params\s*\).*?return\s+SCRIPT_CONTINUE.*?int\s+retCode\s*=\s*money\.getReturnCode') -and
    ($teacherAttemptedPaymentWindow -match '(?s)retCode\s*==\s*money\.RET_SUCCESS\s*\?\s*PRECU_VECTOR_DEBIT\s*:\s*PRECU_VECTOR_PRE') -and
    ($teacherAttemptedPaymentWindow -match '(?s)"paymentSucceededCallback".*?"purchaseApplying".*?PRECU_VECTOR_DEBIT.*?completeSkillPurchase') -and
    ($teacherAttemptedPaymentWindow -match '(?s)claimPhaseAAccountingRequest.*?money\.ACCT_SKILL_TRAINING.*?messageTo\s*\(\s*player\s*,\s*"precuPhaseARequestAccounting"') -and
    ($teacherAttemptedPaymentWindow -notmatch '"purchaseApplying"\s*,\s*""\s*,\s*"purchaseSucceeded"') -and
    ($teacherAccountingClaimWindow -match '(?s)"purchaseApplying".*?PRECU_VECTOR_HELD.*?buildPhaseAAttemptKey\s*\(\s*operationId\s*,\s*"accounting"\s*,\s*1\s*\).*?"accountingRequested"') -and
    ($teacherRefundClaimWindow -match '(?s)"purchaseApplying".*?PRECU_VECTOR_DEBIT.*?buildPhaseAAttemptKey\s*\(.*?"refund"\s*,\s*1\s*\).*?"refundInitialClaiming"') -and
    ($teacherRefundDispatchWindow -match '(?s)family\s*\+\s*"Claiming".*?family\s*\+\s*"Dispatching".*?transferBankCreditsTo\s*\(.*?"precuPhaseARefundSucceeded".*?"precuPhaseARefundFailed".*?if\s*\(\s*!queued\s*\).*?family\s*\+\s*"Failed".*?else.*?checkpointPhaseARefundPending') -and
    ($teacherRefundSuccessWindow -match '(?s)generation\s*==\s*1\s*\|\|\s*generation\s*==\s*2.*?family\s*\+\s*"Dispatching".*?family\s*\+\s*"Pending".*?"purchaseRefunded".*?PRECU_VECTOR_REFUND.*?sendSystemMessageProse') -and
    ($teacherRefundFailureWindow -match '(?s)generation\s*==\s*1\s*\|\|\s*generation\s*==\s*2.*?family\s*\+\s*"Dispatching".*?family\s*\+\s*"Pending".*?family\s*\+\s*"Failed".*?PRECU_VECTOR_DEBIT') -and
    ($teacherRefundCheckpointWindow -match '(?s)family\s*\+\s*"Dispatching".*?PRECU_VECTOR_DEBIT.*?family\s*\+\s*"Pending"')
)

$phaseATaggedPaymentStagesReady = (
    $phaseATrainerCallbackQuarantineReady -and
    ($paymentHandlerEnvelopeWindow -match '(?s)params\.containsKey\s*\(\s*money\.DICT_HANDLER\s*\).*?params\.containsKey\s*\(\s*money\.DICT_PAY_HANDLER\s*\).*?"attemptedPayment"\.equals.*?PRECU_PROTOCOL_VERSION') -and
    ($nativePaymentEnvelopeWindow -match '(?s)!params\.containsKey\s*\(\s*money\.DICT_CODE\s*\).*?money\.getReturnCode\s*\(\s*params\s*\)\s*==\s*-1') -and
    ($paymentRequestWindow -match '(?s)hasAnyPhaseATag\s*\(\s*params\s*\).*?!hasExactPaymentRequestEnvelope\s*\(\s*params\s*\).*?transitionPhaseAPurchaseStage\s*\(.*?"enqueueing".*?"paymentDispatching".*?money\.pay\s*\(') -and
    ($payDepositWindow -match '(?s)hasAnyPhaseATag\s*\(\s*params\s*\)\s*\)\s*\{\s*return\s+SCRIPT_CONTINUE\s*;\s*\}.*?obj_id\s+target') -and
    ($payPassWindow -match '"paymentSucceededCallback"') -and
    ($payPassWindow -match 'hasExactNativePaymentEnvelope') -and
    ($payPassWindow -match '(?s)transitionPhaseAPurchaseStage\s*\(.*?money\.decrementPayTally\s*\(.*?params\.put\s*\(\s*money\.DICT_CODE\s*,\s*money\.RET_SUCCESS') -and
    ($payFailWindow -match '"paymentDispatching"') -and
    ($payFailWindow -match '"paymentFailedCallback"') -and
    ($payFailWindow -match 'hasExactNativePaymentEnvelope') -and
    ($payFailWindow -match '(?s)transitionPhaseAPurchaseStage\s*\(.*?money\.decrementPayTally\s*\(.*?params\.put\s*\(\s*money\.DICT_CODE\s*,\s*money\.RET_FAIL') -and
    ($teacherAttemptedPaymentWindow -match '(?s)hasExactAttemptedPaymentEnvelope\s*\(\s*params\s*\).*?money\.getReturnCode\s*\(\s*params\s*\).*?"paymentSucceededCallback"\s*:\s*"paymentFailedCallback"') -and
    ($teacherAttemptedPaymentWindow -match '(?s)phaseATagged\s*&&\s*!phaseAOperation\s*\)\s*\{\s*return\s+SCRIPT_CONTINUE') -and
    ($teacherAttemptedPaymentWindow -match '(?s)"paymentFailedCallback".*?"paymentFailed".*?return\s+SCRIPT_CONTINUE') -and
    ($teacherAttemptedPaymentWindow -match '(?s)transitionPhaseAOperation\s*\(.*?"paymentSucceededCallback".*?"purchaseApplying".*?completeSkillPurchase\s*\(') -and
    ($teacherAttemptedPaymentWindow -notmatch '"queued"') -and
    ($accountingAttemptWindow -match '(?s)buildPhaseAAttemptKey\s*\(.*?"accounting"\s*,\s*1\s*\).*?money\.ACCT_SKILL_TRAINING.*?PRECU_OP_REFUND_GENERATION.*?PRECU_OP_REFUND_ATTEMPT_KEY.*?PRECU_OP_REFUND_RETRY_CONSUMED') -and
    ($accountingRequestWindow -match '(?s)"accountingRequested".*?"accountingDispatching".*?transferBankCreditsToNamedAccount\s*\(.*?money\.ACCT_SKILL_TRAINING.*?"precuPhaseAAccountingSucceeded".*?"precuPhaseAAccountingFailed".*?"accountingQueueFailed".*?"accountingPending"') -and
    ($accountingSuccessWindow -match '(?s)PRECU_ACCOUNTING_OUTCOME_SUCCESS.*?"accountingSucceededCallback".*?"purchaseSucceeded"') -and
    ($accountingFailureWindow -match '(?s)PRECU_ACCOUNTING_OUTCOME_FAILED.*?"accountingFailed"')
)

$purchaseStageLeavesReady = $true
foreach ($leaf in @(
    "PRECU_OP_ATTEMPT_ID", "PRECU_OP_ID", "PRECU_OP_KIND", "PRECU_OP_STATE",
    "PRECU_OP_LIFECYCLE_ID", "PRECU_OP_TRAINER_OID", "PRECU_OP_SKILL_NAME",
    "PRECU_OP_COST", "PRECU_OP_PRE_CREDITS", "PRECU_OP_PRE_CASH",
    "PRECU_OP_PRE_BANK", "PRECU_OP_PRE_XP", "PRECU_OP_PRE_POINTS",
    "PRECU_OP_PRE_CAP", "PRECU_OP_PRE_NOVICE", "PRECU_OP_PRE_SKILL",
    "PRECU_OP_PROTOCOL_VERSION", "PRECU_OP_REFUND_GENERATION",
    "PRECU_OP_REFUND_ATTEMPT_KEY", "PRECU_OP_REFUND_RETRY_CONSUMED",
    "PRECU_OP_ACCOUNTING_ATTEMPT_KEY", "PRECU_OP_ACCOUNTING_ACCOUNT",
    "PRECU_OP_ACCOUNTING_OUTCOME",
    "PRECU_LIFECYCLE_ATTEMPT_ID", "PRECU_LIFECYCLE_ID", "PRECU_LIFECYCLE_STATE",
    "PRECU_LIFECYCLE_BASE_CASH", "PRECU_LIFECYCLE_BASE_BANK",
    "PRECU_LIFECYCLE_BASE_XP", "PRECU_LIFECYCLE_BASE_POINTS",
    "PRECU_LIFECYCLE_BASE_CAP", "PRECU_LIFECYCLE_BASE_NOVICE",
    "PRECU_LIFECYCLE_BASE_SKILL"))
{
    $purchaseStageLeavesReady = $purchaseStageLeavesReady -and ($purchaseStageWindow -match [regex]::Escape($leaf))
}
$phaseAExactBalancesReady = (
    $purchaseStageLeavesReady -and
    ($purchaseStageWindow -match '!self\.isLoaded\s*\(\s*\)\s*\|\|\s*!self\.isAuthoritative\s*\(\s*\)') -and
    ($purchaseStageWindow -match 'operationId\.matches\s*\(\s*"\[a-f0-9\]\{32\}"\s*\)') -and
    ($purchaseStageWindow -match 'lifecycleId\.matches\s*\(\s*"\[a-f0-9\]\{32\}"\s*\)') -and
    ($purchaseStageWindow -match '!taggedTrainer\.isLoaded\s*\(\s*\)\s*\|\|\s*!taggedTrainer\.isAuthoritative\s*\(\s*\)') -and
    ($purchaseStageWindow -match 'cost\s*!=\s*PRECU_CRAFTING_TRAINER_COST') -and
    ($purchaseStageWindow -match 'getIntObjVar\s*\(\s*self\s*,\s*PRECU_OP_UPDATED\s*\)\s*<=\s*0') -and
    ($purchaseStageWindow -match '\(long\)preCredits\s*!=\s*\(long\)preCash\s*\+\s*\(long\)preBank') -and
    ($purchaseStageWindow -match 'preCash\s*!=\s*baseCash') -and
    ($purchaseStageWindow -match '\(long\)preBank\s*!=\s*\(long\)baseBank\s*\+\s*\(long\)cost') -and
    ($purchaseStageWindow -match '\(long\)preXp\s*!=\s*\(long\)baseXp\s*\+\s*\(long\)PRECU_CRAFTING_XP_COST') -and
    ($purchaseStageWindow -match 'prePoints\s*!=\s*expectedPrePoints\s*\|\|\s*prePoints\s*<\s*targetPointCost') -and
    ($purchaseStageWindow -match 'preCap\s*!=\s*PRECU_PREPURCHASE_XP_CAP') -and
    ($purchaseStageWindow -match 'baseSkill\s*!=\s*0') -and
    ($purchaseStageWindow -match 'taggedPlayer\s*==\s*null\s*\|\|\s*!self\.equals\s*\(\s*taggedPlayer\s*\)') -and
    ($purchaseStageWindow -match 'taggedTrainer\.toString\s*\(\s*\)\.equals\s*\(\s*getStringObjVar\s*\(\s*self\s*,\s*PRECU_OP_TRAINER_OID\s*\)\s*\)') -and
    ($purchaseStageWindow -match 'PRECU_CRAFTING_SKILL\.equals\s*\(\s*skillName\s*\)') -and
    ($purchaseStageWindow -match 'params\.getInt\s*\(\s*money\.DICT_AMOUNT\s*\)\s*!=\s*cost') -and
    ($purchaseStageWindow -match 'params\.getInt\s*\(\s*money\.DICT_TOTAL\s*\)\s*!=\s*cost') -and
    ($purchaseStageWindow -match 'bankDebit\s*=\s*preBank\s*<\s*cost\s*\?\s*preBank\s*:\s*cost') -and
    ($purchaseStageWindow -match 'cashDebit\s*=\s*cost\s*-\s*bankDebit') -and
    ($purchaseStageWindow -match '(?s)PRECU_VECTOR_PRE\.equals\s*\(\s*expectedVector\s*\)\s*\|\|\s*PRECU_VECTOR_DEBIT\.equals\s*\(\s*expectedVector\s*\).*?getExperiencePoints\s*\(\s*self\s*,\s*PRECU_CRAFTING_XP_TYPE\s*\)\s*==\s*preXp.*?skill\.getAvailableSkillPoints\s*\(\s*self\s*\)\s*==\s*prePoints.*?getExperienceCap\s*\(\s*self\s*,\s*PRECU_CRAFTING_XP_TYPE\s*\)\s*==\s*preCap.*?\(hasSkill\s*\(\s*self\s*,\s*PRECU_CRAFTING_NOVICE_SKILL\s*\)\s*\?\s*1\s*:\s*0\s*\)\s*==\s*preNovice.*?\(hasSkill\s*\(\s*self\s*,\s*PRECU_CRAFTING_SKILL\s*\)\s*\?\s*1\s*:\s*0\s*\)\s*==\s*preSkill.*?hasExactPreparedPhaseACraftingVector') -and
    ($purchaseStageWindow -match '(?s)getCashBalance\s*\(\s*self\s*\)\s*==\s*\(\s*debit\s*\?\s*preCash\s*-\s*cashDebit\s*:\s*preCash\s*\).*?getBankBalance\s*\(\s*self\s*\)\s*==\s*\(\s*debit\s*\?\s*preBank\s*-\s*bankDebit\s*:\s*preBank\s*\).*?getTotalMoney\s*\(\s*self\s*\)\s*==\s*\(\s*debit\s*\?\s*preCredits\s*-\s*cost\s*:\s*preCredits\s*\)') -and
    ($purchaseStageWindow -match '(?s)return\s+getCashBalance\s*\(\s*self\s*\)\s*==\s*preCash\s*-\s*cashDebit.*?getBankBalance\s*\(\s*self\s*\)\s*==\s*preBank\s*-\s*bankDebit.*?getTotalMoney\s*\(\s*self\s*\)\s*==\s*preCredits\s*-\s*cost.*?getExperiencePoints.*?preXp\s*-\s*PRECU_CRAFTING_XP_COST.*?skill\.getAvailableSkillPoints.*?prePoints\s*-\s*targetPointCost.*?PRECU_TRAINED_XP_CAP.*?hasExactHeldPhaseACraftingVector') -and
    ($purchaseLineageWindow -match '(?s)preCash\s*==\s*baseCash.*?preBank\s*==\s*\(long\)baseBank\s*\+\s*\(long\)cost.*?preXp\s*==\s*\(long\)baseXp\s*\+\s*\(long\)CRAFTING_XP_COST.*?preCap\s*==\s*1500.*?preNovice\s*==\s*1\s*&&\s*preSkill\s*==\s*0') -and
    ($purchasePreVectorWindow -match '(?s)hasExactPurchasePreimageLineage.*?OP_PRE_CASH.*?OP_PRE_BANK.*?OP_PRE_CREDITS.*?hasExactPurchasePreGameplayVector.*?!utils\.hasScriptVar\s*\(\s*player\s*,\s*RELOG_NONCE') -and
    ($purchaseDebitVectorWindow -match '(?s)hasExactPurchasePreimageLineage.*?OP_PRE_CASH\s*\)\s*-\s*cashDebit.*?preBank\s*-\s*bankDebit.*?OP_PRE_CREDITS\s*\)\s*-\s*cost.*?hasExactPurchasePreGameplayVector') -and
    ($purchaseRefundVectorWindow -match 'return\s+hasExactPurchasePreVector\s*\(\s*player\s*\)') -and
    ($purchaseHeldVectorWindow -match '(?s)hasExactPurchasePreimageLineage.*?OP_PRE_XP\s*\)\s*-\s*CRAFTING_XP_COST.*?getSkillPointCost\s*\(\s*CRAFTING_SKILL\s*\).*?==\s*2000.*?hasExactPersistentCraftingGrantVector.*?!utils\.hasScriptVar\s*\(\s*player\s*,\s*RELOG_NONCE')
)
$phaseAV64RecoveryReady = (
    $phaseAPurchaseProtocolContractReady -and
    ($purchaseVectorDispatchWindow -match '(?s)"PRE"\.equals\s*\(\s*vector\s*\).*?hasExactPurchasePreVector.*?"DEBIT"\.equals\s*\(\s*vector\s*\).*?hasExactPurchaseDebitVector.*?"HELD"\.equals\s*\(\s*vector\s*\).*?hasExactPurchaseHeldVector.*?"REFUND"\.equals\s*\(\s*vector\s*\).*?hasExactPurchaseRefundVector') -and
    ($purchaseTransitionWindow -match '(?s)validateExactPurchaseOperation\s*\(\s*player\s*,\s*operationId\s*,\s*lifecycleId\s*\).*?!expectedState\.equals\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*OP_STATE\s*\)\s*\).*?!hasExactPurchaseVector\s*\(\s*player\s*,\s*expectedVector\s*\).*?setObjVar\s*\(\s*player\s*,\s*OP_STATE\s*,\s*operationState\s*\)') -and
    ($purchaseCallbackDictionaryWindow -match '(?s)callback\.put\s*\(\s*"skillName"\s*,\s*CRAFTING_SKILL\s*\).*?callback\.put\s*\(\s*OP_PARAM_ID.*?callback\.put\s*\(\s*OP_PARAM_KIND\s*,\s*"purchase"\s*\).*?callback\.put\s*\(\s*LIFECYCLE_PARAM_ID.*?callback\.put\s*\(\s*OP_PROTOCOL_PARAM_VERSION\s*,\s*PROTOCOL_VERSION\s*\).*?callback\.put\s*\(\s*money\.DICT_PLAYER_ID\s*,\s*player\s*\).*?callback\.put\s*\(\s*money\.DICT_TARGET_ID\s*,\s*trainer\s*\).*?callback\.put\s*\(\s*money\.DICT_AMOUNT\s*,\s*CRAFTING_TRAINER_COST\s*\).*?callback\.put\s*\(\s*money\.DICT_TOTAL\s*,\s*CRAFTING_TRAINER_COST\s*\).*?callback\.put\s*\(\s*money\.DICT_HANDLER\s*,\s*"attemptedPayment"\s*\).*?callback\.put\s*\(\s*money\.DICT_PAY_HANDLER\s*,\s*"attemptedPayment"\s*\).*?callback\.put\s*\(\s*money\.DICT_NOTIFY\s*,\s*true\s*\).*?callback\.put\s*\(\s*money\.DICT_CODE\s*,\s*returnCode\s*\)') -and
    ($requeuePurchaseCallbackWindow -match '(?s)validateExactPurchaseOperation.*?"paymentDispatching"\.equals\s*\(\s*operationState\s*\).*?"paymentSucceededCallback"\.equals\s*\(\s*operationState\s*\).*?"purchaseApplying"\.equals\s*\(\s*operationState\s*\).*?hasExactPurchaseDebitVector.*?transitionExactPurchaseState\s*\(.*?operationState.*?"paymentSucceededCallback".*?"DEBIT".*?buildExactPurchaseCallbackParams.*?money\.RET_SUCCESS.*?hasExactPurchaseDebitVector.*?messageTo\s*\(\s*trainer\s*,\s*"attemptedPayment"') -and
    ($requeuePurchaseCallbackWindow -notmatch 'money\.requestPayment|money\.pay\s*\(|transferBankCreditsTo\s*\(') -and
    ($reconcileRefundOutcomeWindow -match '(?s)validateExactPurchaseOperation.*?isExactPersistedRefundState\s*\(\s*player\s*,\s*operationState\s*\).*?hasExactPurchaseRefundVector.*?transitionExactPurchaseState\s*\(.*?operationState.*?"purchaseRefunded".*?"REFUND".*?transferRetried=false') -and
    ($reconcileRefundOutcomeWindow -notmatch 'transferBankCreditsTo\s*\(|money\.requestPayment|money\.pay\s*\(') -and
    ($retryPurchaseRefundWindow -match '(?s)args\.length\s*!=\s*6.*?expectedGeneration\s*!=\s*getIntObjVar\s*\(\s*player\s*,\s*OP_REFUND_GENERATION\s*\).*?!args\[5\]\.equals\s*\(\s*getStringObjVar\s*\(\s*player\s*,\s*OP_REFUND_ATTEMPT_KEY\s*\)\s*\).*?isValidRefundAttemptKey.*?hasExactPurchaseDebitVector') -and
    ($retryPurchaseRefundWindow -match '(?s)expectedGeneration\s*==\s*1\s*&&\s*"refundInitialFailed".*?claimExactRecoveryRefund.*?"refundInitialClaiming".*?"refundRecoveryClaiming".*?dispatchExactClaimedRefund') -and
    ($retryPurchaseRefundWindow -match '(?s)putExactRefundParams.*?queued=.*?refundGeneration=.*?refundAttemptKey=.*?refundRetryConsumed=') -and
    ($retryPurchaseRefundWindow -notmatch 'transferBankCreditsTo\s*\(|money\.requestPayment|money\.pay\s*\(') -and
    ($persistedRefundStateWindow -match '(?s)"refundInitialClaiming".*?"refundInitialDispatching".*?"refundInitialPending".*?"refundInitialFailed".*?"refundRecoveryClaiming".*?"refundRecoveryDispatching".*?"refundRecoveryPending".*?"refundRecoveryFailed"') -and
    ($persistedRefundStateWindow -match '(?s)generation\s*==\s*1.*?OP_REFUND_RETRY_CONSUMED\s*\)\s*==\s*0.*?generation\s*==\s*2.*?OP_REFUND_RETRY_CONSUMED\s*\)\s*==\s*1.*?isValidRefundAttemptKey.*?OP_ACCOUNTING_ATTEMPT_KEY.*?OP_ACCOUNTING_ACCOUNT.*?OP_ACCOUNTING_OUTCOME') -and
    ($dispatchClaimedRefundWindow -match '(?s)generation\s*==\s*1\s*\?.*?"refundInitialClaiming"\s*:\s*"refundRecoveryClaiming".*?validateExactPurchaseOperation.*?isExactPersistedRefundState.*?REFUND_PARAM_GENERATION.*?OP_REFUND_ATTEMPT_KEY.*?REFUND_PARAM_ATTEMPT_KEY.*?REFUND_PARAM_RETRY_CONSUMED.*?generation\s*==\s*2.*?hasExactPurchaseDebitVector.*?messageTo\s*\(\s*trainer\s*,\s*"precuPhaseAResumeRefund"') -and
    ($dispatchClaimedRefundWindow -notmatch 'transferBankCreditsTo\s*\(|money\.requestPayment|money\.pay\s*\(') -and
    ($clearableTerminalVectorWindow -match '(?s)"paymentFailed".*?"paymentQueueFailed".*?"purchaseRejected".*?hasExactNeutralSubAttemptProvenance.*?hasExactPurchasePreVector.*?"purchaseSucceeded".*?hasExactAccountingSuccessProvenance.*?"purchaseRefunded".*?hasExactPurchaseRefundVector.*?hasExactRefundTerminalProvenance.*?return\s+false') -and
    ($clearableTerminalVectorWindow -notmatch '"refundInitialFailed"|"refundRecoveryFailed"|"accountingRequestQueueFailed"|"accountingQueueFailed"|"accountingFailed"') -and
    ($runtimeProbe -match '(?s)claimExactRecoveryRefund\s*\(.*?"refundInitialFailed".*?buildPhaseAAttemptKey\s*\(\s*operationId\s*,\s*"refund"\s*,\s*2\s*\).*?OP_REFUND_RETRY_CONSUMED\s*,\s*1.*?"refundRecoveryClaiming"') -and
    ($runtimeProbe -match '(?s)dispatchExactClaimedRefund\s*\(.*?"refundInitialClaiming"\s*:\s*"refundRecoveryClaiming".*?messageTo\s*\(\s*trainer\s*,\s*"precuPhaseAResumeRefund"') -and
    ($resumePurchaseAccountingWindow -match '(?s)hasExactAccountingSuccessProvenance.*?"accountingDispatching".*?"accountingPending".*?"accountingSucceededCallback".*?"purchaseSucceeded".*?reconciled=true\s+transferRetried=false') -and
    ($resumePurchaseAccountingWindow -match '(?s)"purchaseApplying".*?claimExactAccountingRequest.*?"accountingRequested".*?hasExactPendingAccountingProvenance.*?messageTo\s*\(\s*player\s*,\s*"precuPhaseARequestAccounting".*?publishAccountingRequestQueueFailure') -and
    ($runtimeProbe -match '(?s)retryPurchaseRefund\s+"\s*\+\s*"<playerOid> <operationId> <lifecycleId> <generation> <refundAttemptKey>; "')
)

$trainerProbeReady = (
    $phaseAOperationCallbacksReady -and
    ($runtimeProbe -match ('RUNTIME_CONTRACT_ID\s*=\s*"' + [regex]::Escape([string]$runtimeSlice.runtimeContractId) + '"')) -and
    ($runtimeProbe -match 'action\.equalsIgnoreCase\s*\(\s*"trainerPurchase"\s*\)') -and
    ($runtimeProbe -match 'hasScript\s*\(\s*trainer\s*,\s*SKILLTEACHER_SCRIPT\s*\)') -and
    ($runtimeProbe -match 'skill\.getTeacherSkills\s*\(\s*trainer\s*,\s*player\s*\)') -and
    ($runtimeProbe -match 'skill\.getQualifiedTeachableSkills\s*\(\s*player\s*,\s*trainer\s*\)') -and
    ($runtimeProbe -match 'TRAINER_INTERACTION_RANGE') -and
    ($runtimeProbe -match 'TRAINER_INSPECTION_RANGE') -and
    ($runtimeProbe -match 'action\.equalsIgnoreCase\s*\(\s*"inspectTrainer"\s*\)') -and
    ($runtimeProbe -match 'scene="\s*\+\s*trainerLocation\.area') -and
    ($runtimeProbe -match 'String\s+validationError\s*=\s*validateCraftingTrainer\s*\(\s*player\s*,\s*trainer\s*\)') -and
    ($runtimeProbe -match 'if\s*\(\s*validationError\s*==\s*null\s*\)') -and
    ($runtimeProbe -match 'newbieFreeTrainingRouteActive=') -and
    ($runtimeProbe -match 'error=newbieFreeTrainingRouteActive') -and
    ($runtimeProbe -match 'error=fixtureNotInExactPreparedState') -and
    ($runtimeProbe -match 'dataTableGetInt\s*\(\s*skill\.TBL_SKILL\s*,\s*skillRow\s*,\s*"MONEY_REQUIRED"\s*\)') -and
    ($runtimeProbe -match 'dataTableGetInt\s*\(\s*skill\.TBL_SKILL\s*,\s*skillRow\s*,\s*"XP_COST"\s*\)') -and
    ($runtimeProbe -match 'money\.requestPayment\s*\(') -and
    ($runtimeProbe -match '"attemptedPayment"') -and
    ($runtimeProbe -match 'path=skillteacherPaymentHandler conversationUi=false') -and
    ($runtimeProbe -match 'getStringCrc\s*\(\s*"npcConversationStart"\s*\)') -and
    ($runtimeProbe -match 'trainer\s*,\s*"0 "\s*,\s*COMMAND_PRIORITY_IMMEDIATE') -and
    ($runtimeProbe -match 'action=queueTrainerConversation queued=') -and
    ($runtimeProbe -match 'conversationUi=pending purchaseMutation=false') -and
    ($runtimeProbe -match 'attachScript\s*\(\s*player\s*,\s*"test\.precu_phase_a_bank_dispatch"') -and
    ($bankDispatchScript -match 'public\s+int\s+OnAttach') -and
    ($bankDispatchScript -match 'public\s+int\s+OnLogin') -and
    ($bankDispatchScript -match 'public\s+int\s+OnArrivedAtLocation') -and
    ($bankDispatchScript -match 'public\s+String\s+executeDispatch') -and
    ($bankDispatchScript -match 'action=attachBankDispatch queued=true') -and
    ($bankDispatchScript -match 'messageTo\s*\(\s*self\s*,\s*"precuPhaseADispatchBankTransfer"') -and
    ($bankDispatchScript -match 'detachScript\s*\(\s*player\s*,\s*SCRIPT_NAME\s*\)') -and
    ($playerMoneyScript -match 'public\s+int\s+precuPhaseADispatchBankTransfer') -and
    ($playerMoneyScript -match 'public\s+int\s+OnLogin') -and
    ($playerMoneyScript -match 'private\s+boolean\s+isExactPhaseABankDispatch') -and
    ($playerMoneyScript -match 'currentXp\s*==\s*PRECU_CRAFTING_XP_COST') -and
    ($playerMoneyScript -match 'currentXp\s*==\s*getIntObjVar\s*\(\s*self\s*,\s*PRECU_LIFECYCLE_BASE_XP\s*\)') -and
    ($playerMoneyScript -match 'transferBankCreditsFromNamedAccount\s*\(') -and
    ($playerMoneyScript -match 'transferBankCreditsToNamedAccount\s*\(') -and
    ($runtimeProbe -match 'beginOperation\s*\(') -and
    ($runtimeProbe -match 'clearTerminalOperation\s*\(') -and
    ($runtimeProbe -match 'LIFECYCLE_ATTEMPT_ID') -and
    $phaseALifecycleCommitReady -and
    $phaseAAttemptOnlyRecoveryReady -and
    $phaseATaggedPaymentStagesReady -and
    $phaseAExactBalancesReady -and
    $phaseAReconcileCorrelationReady -and
    $phaseAV64RecoveryReady -and
    ($runtimeProbe -match 'isLifecycleEstablished\s*\(') -and
    ($runtimeProbe -match 'rollbackLifecycleEstablishment\s*\(') -and
    ($runtimeProbe -match 'partialLifecycleBaselineMatchesCurrent\s*\(') -and
    ($clearLifecycleWindow -match 'removeObjVar\s*\(\s*player\s*,\s*LIFECYCLE_ROOT\s*\)') -and
    ($clearLifecycleWindow -notmatch 'grantSkill|revokeSkill|purchaseSkill|grantExperience|queueCommand|money\.|transferBank') -and
    ($runtimeProbe -match 'OP_ATTEMPT_ID') -and
    ($runtimeProbe -match '(?s)setObjVar\s*\(\s*player\s*,\s*OP_ATTEMPT_ID\s*,\s*operationId\s*\).*?setObjVar\s*\(\s*player\s*,\s*OP_PRE_CREDITS.*?setObjVar\s*\(\s*player\s*,\s*OP_ID\s*,\s*operationId\s*\).*?setObjVar\s*\(\s*player\s*,\s*OP_STATE\s*,\s*"reserved"\s*\)') -and
    ($runtimeProbe -match 'rollbackOperationReservation\s*\(') -and
    ($runtimeProbe -match 'operationPreimageMatchesCurrent\s*\(') -and
    ($runtimeProbe -match 'OP_PRE_CASH') -and
    ($runtimeProbe -match 'OP_PRE_BANK') -and
    ($runtimeProbe -match 'OP_PRE_NOVICE') -and
    ($runtimeProbe -match 'OP_PRE_SKILL') -and
    ($runtimeProbe -match 'hasExactPersistentCraftingGrantVector\s*\(') -and
    ($persistentPurchaseVectorWindow -notmatch 'RELOG_NONCE|RESTART_NONCE') -and
    ($runtimeProbe -match '(?s)action\.equalsIgnoreCase\s*\(\s*"resumePurchaseAccounting"\s*\).*?"purchaseApplying"\.equals\s*\(\s*operationState\s*\).*?claimExactAccountingRequest') -and
    ($runtimeProbe -notmatch 'markOperationQueued\s*\(') -and
    ($runtimeProbe -notmatch 'getRuntimeBootToken|runtimeBootToken|bootToken=') -and
    ($runtimeProbe -match 'RELOG_NONCE') -and
    ($runtimeProbe -match 'RESTART_NONCE') -and
    ($runtimeProbe -match 'getTotalMoney\s*\(\s*player\s*\)\s*!=\s*0') -and
    ($runtimeProbe -match 'getTotalMoney\s*\(\s*player\s*\)\s*!=\s*CRAFTING_TRAINER_COST') -and
    ($runtimeProbe -match 'error=fixtureNotReadyForXpSetup') -and
    ($runtimeProbe -match 'error=fixtureNotReadyForXpCleanup')
)

$trainerPersistencePath = if ($Expectation -eq "Ready")
{
    Join-Path $source (("restoration/" + ([string]$contract.runtimeTrainerPersistenceScript).Replace('\', '/')).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
}
else
{
    Join-Path $restorationRoot ([string]$contract.runtimeTrainerPersistenceScript)
}
$trainerPersistence = if (Test-Path -LiteralPath $trainerPersistencePath -PathType Leaf) { Get-Content -LiteralPath $trainerPersistencePath -Raw } else { "" }
$requiredOfflineCoverage = @(
    "lock-contention-two-snapshots-one-player",
    "case-sensitive-per-kind-schemas",
    "early-cleanup-origins",
    "releasePending-replay",
    "terminal-noop-zero-mutations",
    "lifecycle-mismatch",
    "runner-hash-drift",
    "fingerprint-drift",
    "reserved-recovery",
    "ambiguous-enqueueing-queued-fail-closed",
    "callback-before-queued-non-downgrade",
    "negative-held-relations"
)
$offlineSelfTestReady = $false
$offlineSelfTestDetail = "runner missing"
if (Test-Path -LiteralPath $trainerPersistencePath -PathType Leaf)
{
    try
    {
        $powerShellExecutable = (Get-Process -Id $PID).Path
        if (-not (Test-Path -LiteralPath $powerShellExecutable -PathType Leaf))
        {
            $powerShellExecutable = Join-Path $PSHOME "powershell.exe"
        }

        $previousErrorActionPreference = $ErrorActionPreference
        try
        {
            $ErrorActionPreference = "Continue"
            $offlineOutput = @(
                & $powerShellExecutable `
                    -NoLogo `
                    -NoProfile `
                    -NonInteractive `
                    -ExecutionPolicy Bypass `
                    -File $trainerPersistencePath `
                    -OfflineSelfTest 2>&1
            )
            $offlineExitCode = $LASTEXITCODE
        }
        finally
        {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $offlineText = [string]::Join(
            [System.Environment]::NewLine,
            @($offlineOutput | ForEach-Object { $_.ToString() })
        )
        $actualCoverage = @(
            [regex]::Matches($offlineText, '(?m)^\[PASS\]\s+([A-Za-z0-9-]+)\r?$') |
                ForEach-Object { [string]$_.Groups[1].Value }
        )
        $missingCoverage = @(
            $requiredOfflineCoverage |
                Where-Object { [regex]::Matches($offlineText, '(?m)^\[PASS\]\s+' + [regex]::Escape($_) + '\r?$').Count -ne 1 }
        )
        $unexpectedCoverage = @($actualCoverage | Where-Object { $_ -cnotin $requiredOfflineCoverage })
        $finalMarkerCount = [regex]::Matches($offlineText, '(?m)^OFFLINE_TRANSITION_TESTS=PASS\r?$').Count
        $offlineSelfTestReady = (
            $offlineExitCode -eq 0 -and
            $missingCoverage.Count -eq 0 -and
            $unexpectedCoverage.Count -eq 0 -and
            $actualCoverage.Count -eq $requiredOfflineCoverage.Count -and
            $finalMarkerCount -eq 1
        )
        $offlineSelfTestDetail = "exit=$offlineExitCode coverage=$($actualCoverage.Count)/$($requiredOfflineCoverage.Count) marker=$finalMarkerCount"
        if ($missingCoverage.Count -gt 0)
        {
            $offlineSelfTestDetail += " missing=$($missingCoverage -join ',')"
        }
        if ($unexpectedCoverage.Count -gt 0)
        {
            $offlineSelfTestDetail += " unexpected=$($unexpectedCoverage -join ',')"
        }
    }
    catch
    {
        $offlineSelfTestDetail = $_.Exception.Message
    }
}

$preparedRelationWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-PreparedRelation\s*\{.*?(?=\r?\nfunction\s+)'
)
$preparedRelationWindow = $(if ($preparedRelationWindowMatch.Success) { $preparedRelationWindowMatch.Value } else { "" })
$heldRelationWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-HeldRelation\s*\{.*?(?=\r?\nfunction\s+)'
)
$heldRelationWindow = $(if ($heldRelationWindowMatch.Success) { $heldRelationWindowMatch.Value } else { "" })
$reservedClearWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-ReservedOperationClearable\s*\{.*?(?=\r?\nfunction\s+)'
)
$reservedClearWindow = $(if ($reservedClearWindowMatch.Success) { $reservedClearWindowMatch.Value } else { "" })
$unqueuedOperationWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-UnqueuedOperationDiscardable\s*\{.*?(?=\r?\nfunction\s+)'
)
$unqueuedOperationWindow = $(if ($unqueuedOperationWindowMatch.Success) { $unqueuedOperationWindowMatch.Value } else { "" })
$resolveOperationWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Resolve-TrackedOperationForCleanup\s*\{.*?(?=\r?\nfunction\s+)'
)
$resolveOperationWindow = $(if ($resolveOperationWindowMatch.Success) { $resolveOperationWindowMatch.Value } else { "" })
$confirmTerminalWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Confirm-TerminalOperationEffect\s*\{.*?(?=\r?\nfunction\s+)'
)
$confirmTerminalWindow = $(if ($confirmTerminalWindowMatch.Success) { $confirmTerminalWindowMatch.Value } else { "" })
$purchaseLineageRunnerWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-ExactPurchaseOperationLineage\s*\{.*?(?=\r?\nfunction\s+)'
)
$purchaseLineageRunnerWindow = $(if ($purchaseLineageRunnerWindowMatch.Success) { $purchaseLineageRunnerWindowMatch.Value } else { "" })
$purchaseDebitRunnerWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-ExactPurchaseDebitVector\s*\{.*?(?=\r?\nfunction\s+)'
)
$purchaseDebitRunnerWindow = $(if ($purchaseDebitRunnerWindowMatch.Success) { $purchaseDebitRunnerWindowMatch.Value } else { "" })
$purchaseRefundRunnerWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-ExactPurchaseRefundVector\s*\{.*?(?=\r?\nfunction\s+)'
)
$purchaseRefundRunnerWindow = $(if ($purchaseRefundRunnerWindowMatch.Success) { $purchaseRefundRunnerWindowMatch.Value } else { "" })
$purchaseRecoveryDecisionWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Get-PurchaseRecoveryDecision\s*\{.*?(?=\r?\nfunction\s+)'
)
$purchaseRecoveryDecisionWindow = $(if ($purchaseRecoveryDecisionWindowMatch.Success) { $purchaseRecoveryDecisionWindowMatch.Value } else { "" })
$saveSnapshotAtomicWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Save-SnapshotAtomic\s*\{.*?(?=\r?\nfunction\s+)'
)
$saveSnapshotAtomicWindow = $(if ($saveSnapshotAtomicWindowMatch.Success) { $saveSnapshotAtomicWindowMatch.Value } else { "" })
$newTrackedOperationWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+New-TrackedOperation\s*\{.*?(?=\r?\nfunction\s+)'
)
$newTrackedOperationWindow = $(if ($newTrackedOperationWindowMatch.Success) { $newTrackedOperationWindowMatch.Value } else { "" })
$exactTrackedMarkerWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-ExactTrackedOperationMarker\s*\{.*?(?=\r?\nfunction\s+)'
)
$exactTrackedMarkerWindow = $(if ($exactTrackedMarkerWindowMatch.Success) { $exactTrackedMarkerWindowMatch.Value } else { "" })
$setTrackedOperationWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Set-TrackedOperationFromState\s*\{.*?(?=\r?\nfunction\s+)'
)
$setTrackedOperationWindow = $(if ($setTrackedOperationWindowMatch.Success) { $setTrackedOperationWindowMatch.Value } else { "" })
$trackedOperationCandidateWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+New-ValidatedTrackedOperationStateCandidate\s*\{.*?(?=\r?\nfunction\s+)'
)
$trackedOperationCandidateWindow = $(if ($trackedOperationCandidateWindowMatch.Success) { $trackedOperationCandidateWindowMatch.Value } else { "" })
$settlementPlanWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Get-TrackedOperationSettlementPlan\s*\{.*?(?=\r?\nfunction\s+)'
)
$settlementPlanWindow = $(if ($settlementPlanWindowMatch.Success) { $settlementPlanWindowMatch.Value } else { "" })
$trackedRecoveryWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Invoke-TrackedPurchaseRecovery\s*\{.*?(?=\r?\nfunction\s+)'
)
$trackedRecoveryWindow = $(if ($trackedRecoveryWindowMatch.Success) { $trackedRecoveryWindowMatch.Value } else { "" })
$assertLifecycleSnapshotWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-LifecycleSnapshot\s*\{.*?(?=\r?\nfunction\s+)'
)
$assertLifecycleSnapshotWindow = $(if ($assertLifecycleSnapshotWindowMatch.Success) { $assertLifecycleSnapshotWindowMatch.Value } else { "" })
$assertStateShapeWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Assert-StateShape\s*\{.*?(?=\r?\nfunction\s+)'
)
$assertStateShapeWindow = $(if ($assertStateShapeWindowMatch.Success) { $assertStateShapeWindowMatch.Value } else { "" })
$runnerClearTerminalWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+Clear-TerminalOperation\s*\{.*?(?=\r?\nfunction\s+)'
)
$runnerClearTerminalWindow = $(if ($runnerClearTerminalWindowMatch.Success) { $runnerClearTerminalWindowMatch.Value } else { "" })
$settledOperationStatesWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)\$settledOperationStates\s*=\s*@\(.*?\)\s*\r?\n\$recoverableSettledOperationStates'
)
$settledOperationStatesWindow = $(if ($settledOperationStatesWindowMatch.Success) { $settledOperationStatesWindowMatch.Value } else { "" })
$clearableOperationStatesWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)\$clearableOperationStates\s*=\s*@\(.*?\)\s*\r?\n\r?\nif'
)
$clearableOperationStatesWindow = $(if ($clearableOperationStatesWindowMatch.Success) { $clearableOperationStatesWindowMatch.Value } else { "" })
$preparedCandidateWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+New-ValidatedPreparedLifecycleCandidate\s*\{.*?(?=\r?\nfunction\s+)'
)
$preparedCandidateWindow = $(if ($preparedCandidateWindowMatch.Success) { $preparedCandidateWindowMatch.Value } else { "" })
$heldCandidateWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+New-ValidatedHeldLifecycleCandidate\s*\{.*?(?=\r?\nfunction\s+)'
)
$heldCandidateWindow = $(if ($heldCandidateWindowMatch.Success) { $heldCandidateWindowMatch.Value } else { "" })
$lastErrorCandidateWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)function\s+New-ValidatedLastErrorLifecycleCandidate\s*\{.*?(?=\r?\nfunction\s+)'
)
$lastErrorCandidateWindow = $(if ($lastErrorCandidateWindowMatch.Success) { $lastErrorCandidateWindowMatch.Value } else { "" })
$prepareModeWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)if\s*\(\$Mode\s+-ceq\s+"Prepare"\s*\).*?(?=\r?\n\s*\$lifecycle\s*=\s*Get-Snapshot)'
)
$prepareModeWindow = $(if ($prepareModeWindowMatch.Success) { $prepareModeWindowMatch.Value } else { "" })
$purchaseModeWindowMatch = [regex]::Match(
    $trainerPersistence,
    '(?s)if\s*\(\$Mode\s+-ceq\s+"Purchase"\s*\).*?(?=\r?\n\s*if\s*\(\$Mode\s+-ceq\s+"VerifyBoundary")'
)
$purchaseModeWindow = $(if ($purchaseModeWindowMatch.Success) { $purchaseModeWindowMatch.Value } else { "" })
$runnerCandidateCommitReady = (
    ($preparedCandidateWindow -match '(?s)\$candidate\s*=\s*Copy-OfflineObject\s+-Value\s+\$Lifecycle.*?\$candidate\.setup\.funding\s*=\s*"complete".*?\$candidate\.prepared\s*=\s*New-StateSnapshot.*?\$candidate\.phase\s*=\s*"prepared".*?Assert-PreparedRelation\s+-Lifecycle\s+\$candidate.*?Assert-LifecycleSnapshot\s+-Lifecycle\s+\$candidate.*?return\s+\$candidate') -and
    ($preparedCandidateWindow -notmatch '\$Lifecycle\.(?:setup|prepared|phase)\s*=') -and
    ($heldCandidateWindow -match '(?s)\$candidate\s*=\s*Copy-OfflineObject\s+-Value\s+\$Lifecycle.*?\$candidate\.purchaseEvidence\s*=\s*New-PurchaseEvidence.*?\$candidate\.held\s*=\s*New-StateSnapshot.*?\$candidate\.phase\s*=\s*"held".*?Assert-HeldRelation\s+-Lifecycle\s+\$candidate\s+-Held\s+\$candidate\.held.*?Assert-LifecycleSnapshot\s+-Lifecycle\s+\$candidate.*?return\s+\$candidate') -and
    ($heldCandidateWindow -notmatch '\$Lifecycle\.(?:purchaseEvidence|held|phase)\s*=') -and
    ($lastErrorCandidateWindow -match '(?s)\$candidate\s*=\s*Copy-OfflineObject\s+-Value\s+\$Lifecycle.*?\$candidate\.lastError\s*=\s*\$Message.*?Assert-LifecycleSnapshot\s+-Lifecycle\s+\$candidate.*?return\s+\$candidate') -and
    ($lastErrorCandidateWindow -notmatch '\$Lifecycle\.lastError\s*=') -and
    ($prepareModeWindow -match '(?s)Clear-TerminalOperation.*?\$lifecycle\s*=\s*New-ValidatedPreparedLifecycleCandidate.*?Save-SnapshotAtomic\s+-Snapshot\s+\$lifecycle') -and
    ($prepareModeWindow -match '(?s)catch\s*\{\s*\$lifecycle\s*=\s*New-ValidatedLastErrorLifecycleCandidate.*?Save-SnapshotAtomic\s+-Snapshot\s+\$lifecycle') -and
    ($prepareModeWindow -notmatch '\$lifecycle\.(?:prepared|phase)\s*=\s*(?:New-StateSnapshot|"prepared")') -and
    ($purchaseModeWindow -match '(?s)\$lifecycle\s*=\s*New-ValidatedHeldLifecycleCandidate.*?Save-SnapshotAtomic\s+-Snapshot\s+\$lifecycle') -and
    ($purchaseModeWindow -match '(?s)catch\s*\{\s*\$lifecycle\s*=\s*New-ValidatedLastErrorLifecycleCandidate.*?Save-SnapshotAtomic\s+-Snapshot\s+\$lifecycle') -and
    ($purchaseModeWindow -notmatch '\$lifecycle\.(?:purchaseEvidence|held|phase)\s*=\s*(?:New-PurchaseEvidence|New-StateSnapshot|"held")') -and
    ($confirmTerminalWindow -match '(?s)\$validatedLifecycle\s*=\s*Copy-OfflineObject.*?\$validatedLifecycle\.purchaseEvidence\s*=\s*New-PurchaseEvidence.*?\$validatedLifecycle\.held\s*=\s*New-StateSnapshot.*?Assert-HeldRelation.*?\$Lifecycle\.purchaseEvidence\s*=\s*\$validatedLifecycle\.purchaseEvidence.*?\$Lifecycle\.held\s*=\s*\$validatedLifecycle\.held') -and
    ($trainerPersistence -match 'Prepare assertion catch did not preserve a reload-valid prior snapshot') -and
    ($trainerPersistence -match 'Purchase assertion catch did not preserve a reload-valid prior snapshot')
)
$runnerV65RecoveryReady = (
    ($purchaseLineageRunnerWindow -match '(?s)Assert-PreparedRelation\s+-Lifecycle\s+\$Lifecycle.*?Assert-StateGameplayEquals\s+-Actual\s+\$operation\.before\s+-Expected\s+\$Lifecycle\.prepared') -and
    ($purchaseDebitRunnerWindow -match '(?s)Assert-ExactPurchaseOperationLineage.*?\$bankDebit\s*=\s*\[Math\]::Min.*?Assert-GameplayExceptBalances.*?State\.Cash\s+-ne\s+\(\[int\]\$before\.Cash\s*-\s*\$cashDebit\).*?State\.Bank\s+-ne\s+\(\[int\]\$before\.Bank\s*-\s*\$bankDebit\).*?State\.Credits\s+-ne\s+\(\[int\]\$before\.Credits\s*-\s*\$trainerCost\).*?RelogNoncePresent.*?RestartNoncePresent') -and
    ($purchaseRefundRunnerWindow -match '(?s)Assert-ExactPurchaseOperationLineage.*?Assert-StateGameplayEquals\s+-Actual\s+\$State\s+-Expected\s+\$Lifecycle\.operation\.before.*?RelogNoncePresent.*?RestartNoncePresent') -and
    ($purchaseRecoveryDecisionWindow -match '(?s)State\.ServerProcessToken\s+-ceq\s+\[string\]\$operation\.serverProcessToken.*?return\s+"".*?operation\.recovery\.serverProcessToken.*?return\s+""') -and
    ($purchaseRecoveryDecisionWindow -match '(?s)"purchaseApplying".*?"accountingRequested".*?"accountingDispatching".*?"accountingPending".*?"accountingSucceededCallback".*?Assert-PersistentAccountingResumeEffect') -and
    ($purchaseRecoveryDecisionWindow -match '(?s)OperationAccountingAttemptKey.*?accounting\.1.*?OperationAccountingAccount.*?skillTrainingSystem.*?OperationAccountingOutcome.*?SUCCESS.*?return\s+"resumePurchaseAccounting"') -and
    ($purchaseRecoveryDecisionWindow -match '(?s)"paymentDispatching".*?"paymentSucceededCallback".*?"purchaseApplying".*?Assert-ExactPurchaseDebitVector.*?return\s+"requeuePurchaseCallback"') -and
    ($purchaseRecoveryDecisionWindow -match '(?s)"refundInitialClaiming".*?"refundInitialDispatching".*?"refundInitialPending".*?"refundInitialFailed".*?"refundRecoveryClaiming".*?"refundRecoveryDispatching".*?"refundRecoveryPending".*?"refundRecoveryFailed".*?Assert-ExactPurchaseRefundVector.*?return\s+"reconcileRefundOutcome"') -and
    ($purchaseRecoveryDecisionWindow -match '(?s)"refundInitialClaiming".*?"refundInitialFailed".*?OperationRefundGeneration\s+-eq\s+1.*?refund\.1.*?OperationRefundRetryConsumed.*?"refundRecoveryClaiming".*?OperationRefundGeneration\s+-eq\s+2.*?refund\.2.*?OperationRefundRetryConsumed.*?Assert-ExactPurchaseDebitVector.*?return\s+"retryPurchaseRefund"') -and
    ($settlementPlanWindow -match '(?s)\$sameProcessBoundary\s*=.*?operation\.serverProcessToken.*?operation\.recovery\.serverProcessToken.*?if\s*\(\$sameProcessBoundary\).*?settledOperationStates.*?"terminal".*?"wait".*?recoverableSettledOperationStates.*?Get-PurchaseRecoveryDecision.*?action\s*=\s*"recover".*?settledOperationStates.*?action\s*=\s*"terminal".*?action\s*=\s*"failClosed"') -and
    ($resolveOperationWindow -match '(?s)New-ValidatedTrackedOperationStateCandidate.*?Save-SnapshotAtomic\s+-Snapshot\s+\$liveCandidate.*?Get-TrackedOperationSettlementPlan.*?plan\.action\s+-ceq\s+"recover".*?Invoke-TrackedPurchaseRecovery.*?plan\.action\s+-ceq\s+"failClosed".*?New-ValidatedTrackedOperationStateCandidate.*?Save-SnapshotAtomic\s+-Snapshot\s+\$terminalCandidate.*?Clear-TerminalOperation') -and
    ($trackedRecoveryWindow -match '(?s)resumePurchaseAccounting\s*=\s*"restartAccountingResume".*?requeuePurchaseCallback\s*=\s*"restartCallbackReplay".*?reconcileRefundOutcome\s*=\s*"restartRefundOutcome".*?retryPurchaseRefund\s*=\s*"restartRefundRetry"') -and
    ($trackedRecoveryWindow -match '(?s)\$intent\s*=\s*New-ValidatedTrackedOperationStateCandidate.*?-RecoverySource.*?-RecoveryProcessToken.*?&\s*\$SnapshotWriter\s+\$intent.*?\$Lifecycle\.operation\s*=\s*\$intent\.operation.*?try') -and
    ($trackedRecoveryWindow -match '"resumePurchaseAccounting\s+\$PlayerOid\s+\$operationId\s+\$\(\$Lifecycle\.lifecycleId\)"') -and
    ($trackedRecoveryWindow -match '"requeuePurchaseCallback\s+\$PlayerOid\s+\$operationId\s+\$\(\$Lifecycle\.lifecycleId\)"') -and
    ($trackedRecoveryWindow -match '"reconcileRefundOutcome\s+\$PlayerOid\s+\$operationId\s+\$\(\$Lifecycle\.lifecycleId\)"') -and
    ($trackedRecoveryWindow -match '"retryPurchaseRefund\s+\$PlayerOid\s+\$operationId\s+\$\(\$Lifecycle\.lifecycleId\)\s+\$generation\s+\$attemptKey"') -and
    ($trackedRecoveryWindow -match 'Assert-Field\s+-Result\s+\$(?:resumed|reconciled)\s+-Name\s+"transferRetried"\s+-Expected\s+"false"') -and
    ($trackedRecoveryWindow -match '(?s)catch\s*\{\s*\$actionError\s*=\s*\$_.*?\$refreshedState\s*=\s*&\s*\$StateReader.*?New-ValidatedTrackedOperationStateCandidate.*?&\s*\$SnapshotWriter\s+\$postAction.*?if\s*\(\$null\s+-ne\s+\$actionError\)\s*\{\s*throw\s+\$actionError') -and
    ($confirmTerminalWindow -match '(?s)terminal\s+-cin\s+@\("refundInitialFailed",\s*"refundRecoveryFailed"\).*?durable compensation provenance') -and
    ($confirmTerminalWindow -match '(?s)terminal\s+-cin\s+@\("accountingRequestQueueFailed",\s*"accountingQueueFailed",\s*"accountingFailed"\).*?unsettled named-account outcome') -and
    ($confirmTerminalWindow -match '(?s)terminal\s+-ceq\s+"purchaseSucceeded".*?refundGeneration\s+-ne\s+0.*?refundAttemptKey\s+-cne\s+"none".*?refundRetryConsumed.*?accountingAttemptKey\s+-cne\s+"\$\(\$operation\.id\)\.accounting\.1".*?accountingAccount\s+-cne\s+"skillTrainingSystem".*?accountingOutcome\s+-cne\s+"SUCCESS"') -and
    ($confirmTerminalWindow -match '(?s)terminal\s+-ceq\s+"purchaseRefunded".*?refundGeneration\s+-notin\s+@\(1,\s*2\).*?refundAttemptKey\s+-cne\s+"\$\(\$operation\.id\)\.refund\.\$\(\$operation\.refundGeneration\)".*?refundRetryConsumed\s+-ne\s+\(\[int\]\$operation\.refundGeneration\s+-eq\s+2\).*?accountingAttemptKey\s+-cne\s+"none"') -and
    ($trainerPersistence -match 'Accounting dispatch with no callback outcome escaped ambiguity quarantine') -and
    ($trainerPersistence -match 'Durable accounting SUCCESS callback cut was not safely finalizable') -and
    ($trainerPersistence -match 'Accounting failure crash cut.*became recoverable') -and
    ($trainerPersistence -match 'accounting-requested-invalid-failure-cut') -and
    ($trainerPersistence -match 'accounting-pending-invalid-request-cut') -and
    ($trainerPersistence -match 'accounting-pending-invalid-queue-cut') -and
    ($trainerPersistence -match 'escaped one-shot refund ambiguity quarantine') -and
    ($trainerPersistence -match 'Same-process callback state was unsafely inferred recoverable') -and
    ($trainerPersistence -match 'Partial purchase grant was not quarantined') -and
    ($trainerPersistence -match 'Semantically invalid but internally consistent preimage escaped lifecycle quarantine') -and
    ($trainerPersistence -match 'Same recovery-process callback state was unsafely inferred recoverable') -and
    ($trainerPersistence -match 'Completed refund retry was not terminalized from authoritative REFUND') -and
    ($trainerPersistence -match 'refund-success-still-debited') -and
    ($trainerPersistence -match 'refund-failure-retains-intent') -and
    ($trainerPersistence -match 'replay-same-process-evidence') -and
    ($trainerPersistence -match 'replay-missing-relog') -and
    ($trainerPersistence -match 'restartAccountingResume') -and
    ($trainerPersistence -match 'restartCallbackReplay') -and
    ($trainerPersistence -match 'restartRefundOutcome') -and
    ($trainerPersistence -match 'restartRefundRetry') -and
    ($trainerPersistence -match 'Settled generation-one refund failure was handled as terminal before its one-shot retry') -and
    ($trainerPersistence -match 'Consumed generation-one refund retry was reusable after another restart') -and
    ($trainerPersistence -match 'Recovery wait timeout did not refresh/checkpoint generation-two live state before rethrow') -and
    ($trainerPersistence -match 'Invalid authoritative refresh did not preserve the last valid recovery intent') -and
    ($trainerPersistence -match 'Accounting resume did not terminalize only the durable SUCCESS outcome')
)
$runnerV8RecoveryReady = (
    ($preparedRelationWindow -match 'prepared\.Cash\s+-ne\s+\[int\]\$baseline\.Cash') -and
    ($preparedRelationWindow -match 'prepared\.Bank\s+-ne\s+\(\[int\]\$baseline\.Bank\s*\+\s*\$trainerCost\)') -and
    ($preparedRelationWindow -match 'prepared\.Credits\s+-ne\s+\(\[int\]\$baseline\.Credits\s*\+\s*\$trainerCost\)') -and
    ($heldRelationWindow -match '\$bankDebit\s*=\s*\[Math\]::Min\s*\(\s*\[int\]\$prepared\.Bank\s*,\s*\$trainerCost\s*\)') -and
    ($heldRelationWindow -match '\$cashDebit\s*=\s*\$trainerCost\s*-\s*\$bankDebit') -and
    ($heldRelationWindow -match '(?s)Held\.Cash\s+-ne\s+\(\[int\]\$prepared\.Cash\s*-\s*\$cashDebit\).*?Held\.Bank\s+-ne\s+\(\[int\]\$prepared\.Bank\s*-\s*\$bankDebit\).*?Held\.Credits\s+-ne\s+\(\[int\]\$prepared\.Credits\s*-\s*\$trainerCost\)') -and
    ($reservedClearWindow -match 'OperationState\s+-cnotin\s+@\("missing",\s*"reserving",\s*"reserved"\)') -and
    ($reservedClearWindow -match '(?s)@\("OperationId",\s*"none".*?@\("OperationKind",\s*"missing".*?@\("OperationLifecycleId",\s*"missing".*?@\("OperationTrainerOid",\s*"missing".*?@\("OperationSkillName",\s*"missing"') -and
    ($reservedClearWindow -match 'OperationPreimageMatches') -and
    ($reservedClearWindow -match 'Assert-StateGameplayEquals') -and
    ($reservedClearWindow -match '(?s)OperationRefundGeneration\s+-ne\s+0.*?OperationRefundRetryConsumed.*?partialStringLeaves.*?"missing",\s*"none"') -and
    ($reservedClearWindow -match '(?s)visibleReservationPrefix\s*=\s*@\(.*?OperationKind\s+-cne\s+"missing".*?OperationUpdated\s+-gt\s+0.*?OperationLifecycleId\s+-cne\s+"missing".*?OperationTrainerOid\s+-cne\s+"missing".*?OperationSkillName\s+-cne\s+"missing".*?OperationCost\s+-ne\s+0.*?OperationProtocolVersion\s+-ne\s+0.*?OperationRefundAttemptKey\s+-cne\s+"missing".*?OperationAccountingAttemptKey\s+-cne\s+"missing".*?OperationAccountingAccount\s+-cne\s+"missing".*?OperationAccountingOutcome\s+-cne\s+"missing".*?OperationId\s+-cne\s+"none"') -and
    ($reservedClearWindow -match '(?s)foreach\s*\(\$leaf\s+in\s+\$visibleReservationPrefix\).*?if\s*\(-not\s+\$leaf\.Present\).*?\$prefixGap\s*=\s*\$true.*?elseif\s*\(\$prefixGap\).*?visible write-order gap') -and
    ($reservedClearWindow -match '(?s)operationState\s+-ceq\s+"missing".*?OperationMarkerComplete.*?visibleReservationPrefix.*?Present.*?Attempt-only operation contains leaves') -and
    ($reservedClearWindow -match '(?s)operationState\s+-ceq\s+"reserving".*?OperationMarkerComplete.*?operationState\s+-ceq\s+"reserved".*?-not\s+\$State\.OperationMarkerComplete.*?visibleReservationPrefix.*?-not\s+\$_.Present') -and
    ($unqueuedOperationWindow -match 'Assert-NoOperationInstrumentation') -and
    ($resolveOperationWindow -match 'Confirm-TerminalOperationEffect\s+-Lifecycle\s+\$Lifecycle\s+-State\s+\$State\s+-MarkerAlreadyCleared') -and
    ($confirmTerminalWindow -match '(?s)if\s*\(\$MarkerAlreadyCleared\).*?Assert-NoOperationInstrumentation.*?operation\.lifecycleId\s+-cne\s+\[string\]\$Lifecycle\.lifecycleId.*?State\.LifecycleAttemptId.*?State\.LifecycleId.*?State\.LifecycleMarkerState\s+-cne\s+"complete"') -and
    ($confirmTerminalWindow -match '(?s)"fundSucceeded".*?State\.Cash\s+-ne\s+\[int\]\$operation\.before\.Cash.*?State\.Bank\s+-ne\s+\(\[int\]\$operation\.before\.Bank\s*\+\s*\$trainerCost\).*?State\.Credits\s+-ne\s+\(\[int\]\$operation\.before\.Credits\s*\+\s*\$trainerCost\)') -and
    ($confirmTerminalWindow -match '(?s)"drainSucceeded".*?State\.Cash\s+-ne\s+\[int\]\$operation\.before\.Cash.*?State\.Bank\s+-ne\s+\(\[int\]\$operation\.before\.Bank\s*-\s*\$trainerCost\).*?State\.Credits\s+-ne\s+\(\[int\]\$operation\.before\.Credits\s*-\s*\$trainerCost\)') -and
    ($confirmTerminalWindow -match '(?s)if\s*\(\$MarkerAlreadyCleared\).*?Assert-StateGameplayEquals.*?purchaseEvidence\.operationId.*?purchaseEvidence\.lifecycleId.*?purchaseEvidence\.trainerOid.*?purchaseEvidence\.skillName.*?purchaseEvidence\.cost.*?else\s*\{\s*Assert-StatePersistentEquals') -and
    ($trainerPersistence -match 'attempt-only-residual') -and
    ($trainerPersistence -match 'Checkpointed-to-attempt-only crash recovery decision drifted') -and
    ($trainerPersistence -match 'Observable reservation prefix cut') -and
    ($trainerPersistence -match 'visible-reservation-prefix-gap-') -and
    ($trainerPersistence -match 'resolve-visible-reservation-prefix-gap') -and
    ($trainerPersistence -match 'Impossible visible reservation prefix crossed a Resolve mutation boundary') -and
    ($trainerPersistence -match 'fund-bank-only-split') -and
    ($trainerPersistence -match 'drain-bank-only-split') -and
    ($trainerPersistence -match 'prepared-cash-bank-split') -and
    ($trainerPersistence -match 'held-cash-bank-split') -and
    ($trainerPersistence -match 'Compensating cash/bank drift was unsafely reconciled from total credits') -and
    ($trainerPersistence -match 'marker-present-operation-drift') -and
    ($trainerPersistence -match 'marker-cleared-instrumentation') -and
    ($trainerPersistence -match 'marker-cleared-gameplay-drift') -and
    ($trainerPersistence -match 'marker-cleared-lineage') -and
    ($trainerPersistence -match 'Impossible tagged pay-deposit stage was not quarantined') -and
    ($trainerPersistence -match 'Trainer callback missing a durable preimage leaf escaped quarantine') -and
    ($trainerPersistence -match 'Trainer callback with lifecycle/preimage drift escaped quarantine') -and
    ($trainerPersistence -match 'Inter-handler trainer callback balance drift escaped quarantine') -and
    ($trainerPersistence -match 'Inter-handler trainer callback gameplay drift escaped quarantine') -and
    ($trainerPersistence -match 'Failed-payment callback with a debit escaped quarantine') -and
    ($settledOperationStatesWindow -match '(?s)"refundInitialFailed".*?"refundRecoveryFailed".*?"accountingRequestQueueFailed".*?"accountingQueueFailed".*?"accountingFailed"') -and
    ($clearableOperationStatesWindow -notmatch '"refundInitialFailed"|"refundRecoveryFailed"|"accountingRequestQueueFailed"|"accountingQueueFailed"|"accountingFailed"') -and
    ($saveSnapshotAtomicWindow -match '(?s)\$normalizedSnapshot\s*=\s*Copy-OfflineObject\s+-Value\s+\$Snapshot.*?Assert-LifecycleSnapshot\s+-Lifecycle\s+\$normalizedSnapshot.*?ConvertTo-Json') -and
    ($newTrackedOperationWindow -match '(?s)protocolVersion\s*=\s*64.*?refundGeneration\s*=\s*0.*?refundAttemptKey\s*=\s*"none".*?refundRetryConsumed\s*=\s*\$false.*?accountingAttemptKey\s*=\s*"none".*?accountingAccount\s*=\s*"none".*?accountingOutcome\s*=\s*"none"') -and
    ($exactTrackedMarkerWindow -match '(?s)OperationAttemptId.*?operation\.id.*?OperationId.*?operation\.id.*?OperationKind.*?operation\.kind.*?OperationLifecycleId.*?operation\.lifecycleId.*?OperationTrainerOid.*?operation\.trainerOid.*?OperationSkillName.*?operation\.skillName.*?OperationCost.*?operation\.cost.*?OperationProtocolVersion.*?operation\.protocolVersion.*?OperationMarkerComplete') -and
    ($exactTrackedMarkerWindow -match '\[int\]\$State\.OperationUpdated\s+-le\s+0') -and
    ($assertStateShapeWindow -match '(?s)State\.OperationMarkerComplete\s+-and.*?\[int\]\$State\.OperationUpdated\s+-le\s+0') -and
    ($heldRelationWindow -match '\[int\]\$Held\.OperationUpdated\s+-le\s+0') -and
    ($purchaseLineageRunnerWindow -match '\[int\]\$State\.OperationUpdated\s+-le\s+0') -and
    ($trackedOperationCandidateWindow -match '(?s)\$candidate\s*=\s*Copy-OfflineObject\s+-Value\s+\$Lifecycle.*?operation\.state\s*=\s*\[string\]\$State\.OperationState.*?operation\.protocolVersion\s*=\s*\[int\]\$State\.OperationProtocolVersion.*?operation\.refundGeneration\s*=\s*\[int\]\$State\.OperationRefundGeneration.*?operation\.refundAttemptKey\s*=\s*\[string\]\$State\.OperationRefundAttemptKey.*?operation\.refundRetryConsumed\s*=\s*\[bool\]\$State\.OperationRefundRetryConsumed.*?operation\.accountingAttemptKey\s*=\s*\[string\]\$State\.OperationAccountingAttemptKey.*?operation\.accountingAccount\s*=\s*\[string\]\$State\.OperationAccountingAccount.*?operation\.accountingOutcome\s*=\s*\[string\]\$State\.OperationAccountingOutcome.*?operation\.reconcileTarget\s*=\s*\$ReconcileTarget') -and
    ($trackedOperationCandidateWindow -match '(?s)New-StateSnapshot\s+-State\s+\$State.*?Assert-StateShape.*?Assert-ExactTrackedOperationMarker') -and
    ($trackedOperationCandidateWindow -match '(?s)Assert-LifecycleSnapshot\s+-Lifecycle\s+\$candidate.*?\$roundTrip\s*=\s*Copy-OfflineObject\s+-Value\s+\$candidate.*?Assert-LifecycleSnapshot\s+-Lifecycle\s+\$roundTrip.*?return\s+\$roundTrip') -and
    ($trackedOperationCandidateWindow -notmatch '\$Lifecycle\.operation\.(?:state|protocolVersion|refundGeneration|refundAttemptKey|refundRetryConsumed|accountingAttemptKey|accountingAccount|accountingOutcome|reconcileTarget)\s*=') -and
    ($setTrackedOperationWindow -match '(?s)New-ValidatedTrackedOperationStateCandidate.*?\$Lifecycle\.operation\s*=\s*\$candidate\.operation') -and
    ($assertLifecycleSnapshotWindow -match '(?s)snapshotSchemaVersion.*?this v8 runner.*?"protocolVersion".*?"refundGeneration".*?"refundAttemptKey".*?"refundRetryConsumed".*?"accountingAttemptKey".*?"accountingAccount".*?"accountingOutcome"') -and
    ($assertStateShapeWindow -match '(?s)accountingRequested\s*=\s*@\("none",\s*"REQUEST_QUEUE_FAILED"\).*?accountingDispatching\s*=\s*@\("none",\s*"QUEUE_FAILED",\s*"FAILED",\s*"SUCCESS"\).*?accountingPending\s*=\s*@\("none",\s*"FAILED",\s*"SUCCESS"\)') -and
    ($assertLifecycleSnapshotWindow -match '(?s)accountingRequested\s*=\s*@\("none",\s*"REQUEST_QUEUE_FAILED"\).*?accountingDispatching\s*=\s*@\("none",\s*"QUEUE_FAILED",\s*"FAILED",\s*"SUCCESS"\).*?accountingPending\s*=\s*@\("none",\s*"FAILED",\s*"SUCCESS"\)') -and
    ($assertLifecycleSnapshotWindow -match '(?s)expectedGeneration.*?refundGeneration\s+-ne\s+\$expectedGeneration.*?refundAttemptKey\s+-cne\s+"\$\(\$Lifecycle\.operation\.id\)\.refund\.\$expectedGeneration".*?refundRetryConsumed\s+-ne\s+\(\$expectedGeneration\s+-eq\s+2\)') -and
    ($runnerClearTerminalWindow -match '(?s)OperationAttemptId\s+-ceq\s+"none".*?operation\.state\s+-cnotin\s+\$clearableOperationStates.*?Confirm-TerminalOperationEffect.*?-MarkerAlreadyCleared.*?Lifecycle\.operation\s*=\s*\$null') -and
    ($runnerClearTerminalWindow -match '(?s)OperationAttemptId\s+-ceq\s+"none".*?Assert-NoOperationInstrumentation') -and
    ($assertLifecycleSnapshotWindow -match '(?s)\$callbackReplayStates\s*=.*?accountingRequestQueueFailed.*?accountingQueueFailed.*?accountingFailed.*?refundInitialFailed.*?purchaseRefunded.*?\$refundRetryStates\s*=.*?refundInitialFailed.*?refundRecoveryClaiming.*?refundRecoveryDispatching.*?refundRecoveryPending.*?refundRecoveryFailed.*?purchaseRefunded') -and
    ($assertLifecycleSnapshotWindow -match '(?s)recoverySource\s+-ceq\s+"restartCallbackReplay".*?reconcileTarget\s+-ceq\s+"requeuePurchaseCallback".*?state\s+-cin\s+@\("paymentDispatching",\s*"paymentSucceededCallback",\s*"purchaseApplying"\)') -and
    ($assertLifecycleSnapshotWindow -match '(?s)recoverySource\s+-ceq\s+"restartRefundRetry".*?reconcileTarget\s+-ceq\s+"retryPurchaseRefund".*?state\s+-cin\s+@\("refundInitialClaiming",\s*"refundInitialFailed",\s*"refundRecoveryClaiming"\)') -and
    ($assertLifecycleSnapshotWindow -match 'recovery\.serverProcessToken\s+-notmatch\s+''\^\[a-f0-9-\]\{36\}\\\|\[0-9\]\+\\\|\[0-9\]\+\$''') -and
    ($trainerPersistence -match 'callback-active-target-advanced-state') -and
    ($trainerPersistence -match 'retry-active-target-\$illegalRetryStateName') -and
    ($trainerPersistence -match 'recovery-generation-attempt-key') -and
    ($trainerPersistence -match 'recovery-generation-consumed-flag') -and
    ($runnerClearTerminalWindow -match '(?s)Set-TrackedOperationFromState.*?Save-SnapshotAtomic\s+-Snapshot\s+\$Lifecycle.*?State\.OperationState\s+-cnotin\s+\$clearableOperationStates.*?Confirm-TerminalOperationEffect\s+-Lifecycle\s+\$Lifecycle\s+-State\s+\$State.*?clearOperation.*?Confirm-TerminalOperationEffect.*?-MarkerAlreadyCleared') -and
    ($runnerClearTerminalWindow -match '(?s)Confirm-TerminalOperationEffect\s+-Lifecycle\s+\$Lifecycle\s+-State\s+\$State\s*.*?Save-SnapshotAtomic\s+-Snapshot\s+\$Lifecycle.*?Invoke-Probe\s+-Arguments\s+"clearOperation') -and
    ($resolveOperationWindow -match 'Assert-ExactTrackedOperationMarker\s+-Lifecycle\s+\$Lifecycle\s+-State\s+\$State') -and
    ($resolveOperationWindow -match '(?s)OperationState\s+-cin\s+@\("missing",\s*"reserving",\s*"reserved"\).*?Assert-ReservedOperationClearable.*?return\s+\$State.*?Assert-ExactTrackedOperationMarker') -and
    ($resolveOperationWindow -match '(?s)OperationAttemptId\s+-ceq\s+"none".*?Assert-NoOperationInstrumentation.*?Assert-UnqueuedOperationDiscardable') -and
    ($resolveOperationWindow -match '(?s)ReservedStateReader.*?OperationAttemptId\s+-cne\s+"none".*?Assert-NoOperationInstrumentation.*?Assert-StateGameplayEquals') -and
    ($runnerClearTerminalWindow -match 'Assert-ExactTrackedOperationMarker\s+-Lifecycle\s+\$Lifecycle\s+-State\s+\$State') -and
    ($confirmTerminalWindow -match '(?s)Assert-ExactTrackedOperationMarker.*?OperationTrainerOid\s*=\s*\[string\]\$operation\.trainerOid.*?OperationSkillName\s*=\s*\[string\]\$operation\.skillName.*?OperationCost\s*=\s*\[int\]\$operation\.cost') -and
    ($trainerPersistence -match 'immutable-sync-\$\(\$immutableDrift\.Name\)') -and
    ($trainerPersistence -match 'immutable-terminal-\$\(\$immutableDrift\.Name\)') -and
    ($trainerPersistence -match 'complete-marker-zero-updated-shape') -and
    ($trainerPersistence -match 'complete-marker-zero-updated-sync') -and
    ($trainerPersistence -match 'Rejected zero-updated operation synchronization mutated the source lifecycle') -and
    ($trainerPersistence -match 'complete-marker-zero-updated-held-candidate') -and
    ($trainerPersistence -match 'complete-marker-zero-updated-terminal') -and
    ($trainerPersistence -match 'complete-marker-zero-updated-fund-terminal') -and
    ($trainerPersistence -match 'complete-marker-zero-updated-drain-terminal') -and
    ($trainerPersistence -match 'Pre-clear durable snapshot omitted synthesized purchase lineage') -and
    ($trainerPersistence -match 'Resolve control path rejected or incompletely cleared checkpointed->\$partialControlStateName recovery') -and
    ($trainerPersistence -match 'resolve-residual-partial-provenance') -and
    ($trainerPersistence -match 'Residual partial provenance crossed a Resolve mutation boundary') -and
    $runnerV65RecoveryReady -and
    $runnerCandidateCommitReady
)

$trainerPersistenceReady = (
    $trainerProbeReady -and
    $materializationReady -and
    $offlineSelfTestReady -and
    $runnerV8RecoveryReady -and
    ($trainerPersistence -match 'ValidateSet\("Observe",\s*"Prepare",\s*"Conversation",\s*"Purchase",\s*"VerifyBoundary",\s*"Surrender",\s*"Cleanup"\)') -and
    ($trainerPersistence -match 'ValidateSet\("Relog",\s*"Restart"\)') -and
    ($trainerPersistence -match '\[string\]\$Mode\s*=\s*"Observe"') -and
    ($trainerPersistence -match 'trainerPurchase\s+\$PlayerOid\s+\$selectedTrainer\s+\$engineeringSkill\s+\$\(\$lifecycle\.operation\.id\)') -and
    ($trainerPersistence -match 'queueTrainerConversation\s+\$PlayerOid\s+\$selectedTrainer') -and
    ($trainerPersistence -match '\$selectedTrainer\s*=\s*\[string\]\$lifecycle\.conversation\.trainerOid') -and
    ($trainerPersistence -match '\$lifecycle\.conversation\s*=\s*\[pscustomobject\]') -and
    ($trainerPersistence -match 'Assert-Field\s+-Result\s+\$conversation\s+-Name\s+"purchaseMutation"\s+-Expected\s+"false"') -and
    ($trainerPersistence -match 'Assert-Field\s+-Result\s+\$purchase\s+-Name\s+"path"\s+-Expected\s+"skillteacherPaymentHandler"') -and
    ($trainerPersistence -match 'Assert-Field\s+-Result\s+\$purchase\s+-Name\s+"conversationUi"\s+-Expected\s+"false"') -and
    ($trainerPersistence -match 'Wait-ForTerminalOperation') -and
    ($trainerPersistence -match 'Wait-ForQuietState') -and
    ($trainerPersistence -match 'purchaseSucceeded') -and
    ($trainerPersistence -match 'purchaseRefunded') -and
    ($trainerPersistence -match 'refundInitialPending') -and
    ($trainerPersistence -match 'refundRecoveryPending') -and
    ($trainerPersistence -match 'No cleanup occurs until the tracked payment/refund callback is terminal') -and
    ($trainerPersistence -match '\$lifecycle\.phase\s*=\s*"relogVerified"') -and
    ($trainerPersistence -match '\$lifecycle\.phase\s*=\s*"restartVerified"') -and
    ($trainerPersistence -match 'RelogNoncePresent') -and
    ($trainerPersistence -match 'RestartNoncePresent') -and
    ($trainerPersistence -match 'function\s+Get-TatooineServerProcessToken') -and
    ($trainerPersistence -match "SwgGameServer\.\*sceneID=tatooine") -and
    ($trainerPersistence -match '/proc/`\$pid/stat') -and
    ($trainerPersistence -match '/proc/sys/kernel/random/boot_id') -and
    ($trainerPersistence -match '\$processTokenBefore\s*=\s*Get-TatooineServerProcessToken') -and
    ($trainerPersistence -match '\$processTokenAfter\s*=\s*Get-TatooineServerProcessToken') -and
    ($trainerPersistence -match 'ServerProcessToken') -and
    ($trainerPersistence -match 'Surrender requires both ordered relog and server-restart boundaries') -and
    ($trainerPersistence -match 'Assert-HeldRelation') -and
    ($trainerPersistence -match 'purchaseModDeltas') -and
    ($trainerPersistence -match 'Convert-IdentityMap') -and
    ($trainerPersistence -match 'Surrendered\.\$name\s+-cne\s*\[string\]\$Lifecycle\.prepared\.\$name') -and
    ($trainerPersistence -match 'Invoke-BaselineCleanup') -and
    ($trainerPersistence -match 'Refusing ambiguous XP cleanup delta') -and
    ($trainerPersistence -match 'Refusing ambiguous credit cleanup delta') -and
    ($trainerPersistence -match 'schemaVersion\s*=\s*\$snapshotSchemaVersion') -and
    ($trainerPersistence -match 'Assert-LifecycleSnapshot') -and
    ($trainerPersistence -match 'Assert-ExecutionIdentity') -and
    ($trainerPersistence -match 'ContractSha256') -and
    ($trainerPersistence -match 'ContainerId') -and
    ($trainerPersistence -match 'Save-SnapshotAtomic') -and
    ($trainerPersistence -match '\[System\.IO\.File\]::Replace') -and
    ($trainerPersistence -match '\$stream\.Flush\s*\(\s*\$true\s*\)') -and
    ($trainerPersistence -match 'function\s+Resolve-ExternalSnapshotPath') -and
    ($trainerPersistence -match 'Snapshot must remain outside the implementation repository') -and
    ($trainerPersistence -match 'LifecycleAttemptId') -and
    ($trainerPersistence -match 'LifecycleMarkerState') -and
    ($trainerPersistence -match 'lifecyclePending zero-gameplay cleanup') -and
    ($trainerPersistence -match 'OperationAttemptId') -and
    ($trainerPersistence -match 'OperationProtocolVersion') -and
    ($trainerPersistence -match 'OperationRefundGeneration') -and
    ($trainerPersistence -match 'OperationRefundAttemptKey') -and
    ($trainerPersistence -match 'OperationRefundRetryConsumed') -and
    ($trainerPersistence -match 'OperationAccountingAttemptKey') -and
    ($trainerPersistence -match 'OperationAccountingAccount') -and
    ($trainerPersistence -match 'OperationAccountingOutcome') -and
    ($trainerPersistence -match '"reserving"') -and
    ($trainerPersistence -match 'Assert-PersistentAccountingResumeEffect') -and
    ($trainerPersistence -match 'restartAccountingResume') -and
    ($trainerPersistence -match 'purchaseEvidence') -and
    ($trainerPersistence -match 'cleanup\.stage\s*=\s*"surrenderPending"') -and
    ($trainerPersistence -match 'cleanup\.stage\s*=\s*"surrendered"') -and
    ($trainerPersistence -match 'snapshot-lock-exclusion') -and
    ($trainerPersistence -match 'stale-id') -and
    ($trainerPersistence -match 'stale-kind') -and
    ($trainerPersistence -match 'stale-lifecycle') -and
    ($trainerPersistence -match 'terminal-replay') -and
    ($trainerPersistence -notmatch 'else\s*\{\s*\$[Ll]ifecycle\.operation\.state\s*=\s*"queued"\s*\}') -and
    ($trainerPersistence -notmatch 'return\s+"queued"') -and
    ($trainerPersistence -notmatch 'Assert-Field[^\r\n]+-Name\s+"connected"')
)
Add-PhaseCheck -Id "phaseA.runtime.trainer-persistence" -Passed $trainerPersistenceReady -Detail "offline=$offlineSelfTestDetail; materialization=$materializationDetail; checkpointed tooling must correlate visible conversation, terminal callbacks, exact grants, ordered boundaries, and strict external recovery"

$surrenderVerificationReady = (
    ($runtimeProbe -match 'action\.equalsIgnoreCase\s*\(\s*"verifySurrender"\s*\)') -and
    ($runtimeProbe -match 'action=queueSurrender queued=') -and
    ($runtimeProbe -match 'verification="\s*\+\s*\(queued\s*\?\s*"pending"\s*:\s*"notQueued"\)') -and
    ($runtimeProbe -match 'action=verifySurrender completion=') -and
    ($runtimeProbe -match 'surrendered="\s*\+\s*surrendered') -and
    ($runtimeProbe -match '\(surrendered\s*\?\s*"removed"\s*:\s*"stillOwned"\)')
)
Add-PhaseCheck -Id "phaseA.runtime.surrender-verification" -Passed $surrenderVerificationReady -Detail "queue acceptance must be pending until a later authoritative status proves the skill was removed"

$runtimeSmokePath = Join-Path $restorationRoot ([string]$contract.runtimeSmokeScript)
$runtimeSmoke = if (Test-Path -LiteralPath $runtimeSmokePath -PathType Leaf) { Get-Content -LiteralPath $runtimeSmokePath -Raw } else { "" }
$runtimeSmokeReady = (
    ($runtimeSmoke -match 'ContainerName\s*=\s*"swg-precu"') -and
    ($runtimeSmoke -match '\[switch\]\$ExerciseSurrender') -and
    ($runtimeSmoke -match 'game\s+tatooine\s+runScript') -and
    ($runtimeSmoke -match "printf\s+'%-1024s'") -and
    ($runtimeSmoke -match 'craftingStatus\s+\$PlayerOid') -and
    ($runtimeSmoke -match 'queueSurrender\s+\$PlayerOid\s+\$engineeringSkill') -and
    ($runtimeSmoke -match 'verifySurrender\s+\$PlayerOid\s+\$engineeringSkill') -and
    ($runtimeSmoke -match 'Assert-Field\s+-Result\s+\$queued\s+-Name\s+"verification"\s+-Expected\s+"pending"') -and
    ($runtimeSmoke -match 'Assert-Field\s+-Result\s+\$verified\s+-Name\s+"completion"\s+-Expected\s+"removed"') -and
    ($runtimeSmoke -match 'Assert-Field\s+-Result\s+\$Result\s+-Name\s+"xpType"\s+-Expected\s+\$xpType') -and
    ($runtimeSmoke -match '\$expectedEngineeringSkillCost\s*=\s*\[int\]\$runtimeContract\.skillPointCost') -and
    ($runtimeSmoke -match '\$expectedPreEngineeringXpCap\s*=\s*\[int\]\$runtimeContract\.prerequisiteXpCap') -and
    ($runtimeSmoke -match '\$expectedPostEngineeringXpCap\s*=\s*\[int\]\$runtimeContract\.trainedXpCap') -and
    ($runtimeSmoke -match '\$expectedPointsAfterGrant\s*=\s*\$beforeEngineeringState\.Points\s*-\s*\$beforeEngineeringState\.SkillCost') -and
    ($runtimeSmoke -match '\$afterGrantState\.Points\s+-ne\s+\$expectedPointsAfterGrant') -and
    ($runtimeSmoke -match '\$beforeEngineeringState\.Cap\s+-ne\s+\$expectedPreEngineeringXpCap') -and
    ($runtimeSmoke -match '\$afterGrantState\.Cap\s+-ne\s+\$expectedPostEngineeringXpCap') -and
    ($runtimeSmoke -match '(?s)\$noviceMutationAttempted\s*=\s*\$true.*?Invoke-Probe\s+-Arguments\s+"grant\s+\$PlayerOid\s+\$noviceSkill\s+\$lifecycleId"') -and
    ($runtimeSmoke -match '(?s)\$engineeringMutationAttempted\s*=\s*\$true.*?Invoke-Probe\s+-Arguments\s+"grant\s+\$PlayerOid\s+\$engineeringSkill\s+\$lifecycleId"') -and
    ($runtimeSmoke -match 'Get-AuthoritativeSkillOwnership\s+-SkillName\s+\$SkillName') -and
    ($runtimeSmoke -match '(?s)Get-AuthoritativeSkillOwnership\s+-SkillName\s+\$SkillName.*?Invoke-Probe\s+-Arguments\s+"revoke\s+\$PlayerOid\s+\$SkillName\s+\$lifecycleId"') -and
    ($runtimeSmoke -match '(?s)try\s*\{.*?\$lifecycleAttempted\s*=\s*\$true.*?beginLifecycle\s+\$PlayerOid\s+\$lifecycleId') -and
    ($runtimeSmoke -match 'function\s+Clear-AttemptedLifecycleMarker') -and
    ($runtimeSmoke -match 'clearLifecycle\s+\$PlayerOid\s+\$ExpectedLifecycleId') -and
    ($runtimeSmoke -match 'lifecycleMarkerState') -and
    ($runtimeSmoke -match 'lifecycleAttemptId') -and
    ($runtimeSmoke -match 'ownedPartial') -and
    ($runtimeSmoke -match 'ownedComplete') -and
    ($runtimeSmoke -match '(?s)if\s*\(\$markerState\s+-ceq\s+"none"\).*?lifecycleBaselineComplete"\s+-Expected\s+"false"') -and
    ($runtimeSmoke -notmatch 'lifecycleEstablished') -and
    ($runtimeSmoke -match '\$noviceMutationAttempted\s+-and\s+-not\s+\$noviceWasOwned') -and
    ($runtimeSmoke -match '(?s)if\s*\(Get-AuthoritativeSkillOwnership\s+-SkillName\s+\$engineeringSkill\).*?throw\s+"Refusing to revoke temporary.*?Revoke-TemporarySkillIfOwned\s+-SkillName\s+\$noviceSkill') -and
    ($runtimeSmoke -match '\$beforeEngineeringState\.HasCommand\s+-or\s+\$beforeEngineeringState\.HasSchematic') -and
    ($runtimeSmoke -match 'Assert-CraftingCanaryStateEquals\s+-Actual\s+\$afterSurrenderState\s+-Expected\s+\$beforeEngineeringState') -and
    ($runtimeSmoke -match 'Assert-CraftingCanaryStateEquals\s+-Actual\s+\$restoredState\s+-Expected\s+\$initialState') -and
    ($runtimeSmoke -match '"HasSkill"[\s\S]+"HasCommand"[\s\S]+"HasSchematic"[\s\S]+"SkillCost"[\s\S]+"Points"[\s\S]+"Xp"[\s\S]+"Cap"[\s\S]+"SkillModValue"[\s\S]+"Cash"[\s\S]+"Bank"') -and
    ($runtimeSmoke -match 'finally\s*\{') -and
    ($runtimeSmoke -match 'Revoke-TemporarySkillIfOwned\s+-SkillName\s+\$engineeringSkill') -and
    ($runtimeSmoke -match 'Revoke-TemporarySkillIfOwned\s+-SkillName\s+\$noviceSkill') -and
    ($runtimeSmoke -match '\$cleanupFailure') -and
    ($runtimeSmoke -notmatch 'Assert-Field[^\r\n]+-Name\s+"connected"')
)
Add-PhaseCheck -Id "phaseA.runtime.live-smoke" -Passed $runtimeSmokeReady -Detail "opt-in smoke must assert the canary point/cap transition, snapshot all exposed canary fields, guard prerequisite cleanup with dependent-skill absence, preserve original novice ownership, and never use connected as readiness"

foreach ($scopeValue in @($contract.commandAudit.scopedSkills))
{
    $scope = [string]$scopeValue
    $scopeRows = @($skills | Where-Object { $_.NAME -ceq $scope })
    if ($scopeRows.Count -ne 1)
    {
        Add-PhaseCheck -Id "phaseA.commands.$scope.skill-row" -Passed $false -Detail "expected exactly one scoped skill row"
        continue
    }

    $grants = @(([string]$scopeRows[0].COMMANDS).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $actionableGrantCount = 0
    foreach ($grant in $grants)
    {
        $nonCommand = $false
        foreach ($prefixValue in @($contract.commandAudit.nonCommandPrefixes))
        {
            if ($grant.StartsWith([string]$prefixValue, [System.StringComparison]::OrdinalIgnoreCase))
            {
                $nonCommand = $true
                break
            }
        }
        if ($nonCommand)
        {
            continue
        }

        $actionableGrantCount++
        $definitions = @($commands | Where-Object { $_.commandName -ieq $grant })
        Add-PhaseCheck -Id "phaseA.commands.$scope.$grant" -Passed ($definitions.Count -eq 1) -Detail "actionable skill grant must resolve to exactly one command_table row; found $($definitions.Count)"
    }
    if ($actionableGrantCount -eq 0)
    {
        Add-PhaseCheck -Id "phaseA.commands.$scope.non-command-grants" -Passed $true -Detail "all scoped grants are explicitly classified as non-command identities"
    }
}

Write-Host ""
Write-Host "Phase-A checks:"
foreach ($check in @($script:checks))
{
    $label = if ($check.Passed) { "PASS" } else { "BLOCKED" }
    Write-Host "  [$label] $($check.Id): $($check.Detail)"
}

$failedIds = @(
    $script:checks |
        Where-Object { -not $_.Passed } |
        ForEach-Object { [string]$_.Id } |
        Sort-Object -Unique
)

if ($Expectation -eq "Ready")
{
    if ($failedIds.Count -gt 0)
    {
        throw "Phase A is not ready. Blocking checks: $($failedIds -join ', ')"
    }

    Write-Host ""
    Write-Host "Phase-A ready contract passed."
    exit 0
}

$expectedBlockers = @($contract.baselineBlockers | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$missingBlockers = @($expectedBlockers | Where-Object { $_ -notin $failedIds })
$unexpectedBlockers = @($failedIds | Where-Object { $_ -notin $expectedBlockers })

if (($missingBlockers.Count -gt 0) -or ($unexpectedBlockers.Count -gt 0))
{
    throw "Baseline changed. Missing expected blockers: $($missingBlockers -join ', '). Unexpected blockers: $($unexpectedBlockers -join ', ')."
}

Write-Host ""
Write-Host "Current x64-dx9 baseline matched: $($failedIds.Count) known Phase-A blockers remain."
