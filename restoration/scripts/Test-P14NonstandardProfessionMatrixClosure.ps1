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
$manifest = Get-Content (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content (
    Join-Path $restorationRoot `
        ([string]$manifest.contracts.p14NonstandardProfessionMatrixClosure)
) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $source)
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$commandPath = Join-Path $source ([string]$contract.sourceFiles.commandTable)
$fixturePath = Join-Path $source ([string]$contract.sourceFiles.liveFixture)
$skillLines = Get-Content $skillPath
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Get-TextSha256
{
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString(
            $sha.ComputeHash($utf8NoBom.GetBytes($Text))
        )).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-OrdinalNames
{
    param([Parameter(Mandatory = $true)]$Values)
    $set = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    foreach ($value in @($Values))
    {
        if (-not [string]::IsNullOrWhiteSpace([string]$value))
        {
            [void]$set.Add([string]$value)
        }
    }
    $names = [string[]]@($set)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return @($names)
}

function Get-NameSetSha256
{
    param([Parameter(Mandatory = $true)]$Values)
    $names = @(Get-OrdinalNames $Values)
    return Get-TextSha256 (($names -join "`n") + "`n")
}

function Test-ExactOrdinalNames
{
    param($Actual, $Expected)
    $actualNames = @(Get-OrdinalNames $Actual)
    $expectedNames = @(Get-OrdinalNames $Expected)
    return $actualNames.Count -eq $expectedNames.Count -and
        (($actualNames -join "`n") -ceq ($expectedNames -join "`n"))
}

function Test-CommandTableFreshRecompile
{
    param([Parameter(Mandatory = $true)][string]$Container)
    $probe = @'
set -eu
tmp_dir="$(mktemp -d /dev/shm/precu-force-command-iff.XXXXXX)"
cleanup() {
    case "${tmp_dir:-}" in
        /dev/shm/precu-force-command-iff.*) ;;
        *) return 97 ;;
    esac
    resolved_tmp="$(readlink -f -- "$tmp_dir")"
    case "$resolved_tmp" in
        /dev/shm/precu-force-command-iff.*) ;;
        *) return 98 ;;
    esac
    rm -rf -- "$resolved_tmp"
}
trap cleanup 0 HUP INT TERM
tool="$SWG_WORK_DIR/build/bin/DataTableTool"
source_tab="$SWG_WORK_DIR/dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
canonical_iff="$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game/datatables/command/command_table.iff"
relative_tab="sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
relative_iff="sku.0/sys.shared/compiled/game/datatables/command/command_table.iff"
temp_tab="$tmp_dir/dsrc/$relative_tab"
fresh_iff="$tmp_dir/data/$relative_iff"
test -x "$tool"
mkdir -p -- "$(dirname "$temp_tab")" "$(dirname "$fresh_iff")"
cp -- "$source_tab" "$temp_tab"
(
    cd "$tmp_dir"
    PATH="$PATH:$SWG_WORK_DIR/build/bin" "$tool" \
        -i "dsrc/$relative_tab" \
        -- -s SharedFile \
        "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game" \
        "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game" \
        "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game"
) >/dev/null
test -s "$fresh_iff"
cmp -s "$fresh_iff" "$canonical_iff"
for command_name in forceArmor1 forceArmor2 forceShield1 forceShield2; do
    test "$(strings -a "$canonical_iff" | grep -Fxc "$command_name" || true)" -eq 1
done
cleanup
trap - 0 HUP INT TERM
test ! -e "$tmp_dir"
'@
    $normalizedProbe = $probe.Replace("`r`n", "`n")
    $normalizedProbe | & docker exec -i $Container sh -c `
        "tr -d '\r' | sh -s" 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

foreach ($family in $contract.families)
{
    $rows = @($skillLines | Where-Object {
        $name = ($_ -split "`t", 2)[0]
        $name -eq [string]$family.root -or
            ($name.StartsWith([string]$family.root + "_") -and
             -not $name.StartsWith([string]$family.root + "_prereq"))
    } | Sort-Object)
    $text = ($rows -join "`n") + "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) |
            ForEach-Object { $_.ToString("x2") }) -join ""
    }
    finally
    {
        $sha.Dispose()
    }
    if ($rows.Count -ne [int]$family.rows -or
        $hash -cne [string]$family.sha256)
    {
        throw "Nonstandard family failed: $($family.root)"
    }
}

$grant = $contract.jediCommandGrantClosure
$grantFailures = [Collections.Generic.List[string]]::new()
function Assert-JediGrant
{
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $grantFailures.Add($Name) }
}

$skillRows = @(Import-SwgTab -Path $skillPath)
$jediRows = @($skillRows | Where-Object {
    [string]$_.NAME -cmatch [string]$grant.selector
})
$allGrantTokens = @(Get-OrdinalNames ($jediRows | ForEach-Object {
    ([string]$_.COMMANDS).Trim('"') -split ','
}))

$core3Root = Join-Path $workspaceRoot ([string]$grant.core3Reference.checkout)
$core3Commit = if (Test-Path -LiteralPath $core3Root -PathType Container)
{
    (& git -C $core3Root rev-parse HEAD 2>$null | Out-String).Trim()
}
else { "" }
$core3Dirty = if (Test-Path -LiteralPath $core3Root -PathType Container)
{
    (& git -C $core3Root status --porcelain 2>$null | Out-String).Trim()
}
else { "missing" }
$core3CommandRoot = Join-Path $core3Root ([string]$grant.core3Reference.commandDirectory)
$core3CommandNames = if (Test-Path -LiteralPath $core3CommandRoot -PathType Container)
{
    @(Get-ChildItem -LiteralPath $core3CommandRoot -File -Filter "*.lua" |
        ForEach-Object { $_.BaseName })
}
else { @() }
$core3NameSet = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($name in $core3CommandNames) { [void]$core3NameSet.Add([string]$name) }
$authenticatedActions = @(Get-OrdinalNames ($allGrantTokens | Where-Object {
    $core3NameSet.Contains([string]$_)
}))
$classifiedNonCommands = @(Get-OrdinalNames ($allGrantTokens | Where-Object {
    -not $core3NameSet.Contains([string]$_)
}))
$preexistingActions = @(Get-OrdinalNames $grant.preexistingRegisteredActions.names)
$restoredActions = @(Get-OrdinalNames $grant.restoredActions.names)
$preexistingSet = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($name in $preexistingActions) { [void]$preexistingSet.Add($name) }
$restoredSet = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($name in $restoredActions) { [void]$restoredSet.Add($name) }
$actionableGap = @(Get-OrdinalNames ($authenticatedActions | Where-Object {
    -not $preexistingSet.Contains([string]$_)
}))
$residualGap = @(Get-OrdinalNames ($actionableGap | Where-Object {
    -not $restoredSet.Contains([string]$_)
}))

$commandLines = @(Get-Content -LiteralPath $commandPath)
$commandRows = @(Import-SwgTab -Path $commandPath)
$registeredCommandSet = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($row in $commandRows)
{
    [void]$registeredCommandSet.Add([string]$row.commandName)
}
$registeredActions = @(Get-OrdinalNames ($authenticatedActions | Where-Object {
    $registeredCommandSet.Contains([string]$_)
}))
$expectedRegistered = @(Get-OrdinalNames ($preexistingActions + $restoredActions))

Assert-JediGrant ($core3Commit -ceq [string]$grant.core3Reference.commit -and
    [string]::IsNullOrWhiteSpace($core3Dirty)) `
    "p14.nonstandard.jedi-grants.core3-checkout-pin"
Assert-JediGrant ($jediRows.Count -eq [int]$grant.skillRows -and
    $allGrantTokens.Count -eq [int]$grant.allGrantTokens.count -and
    (Get-NameSetSha256 $allGrantTokens) -ceq [string]$grant.allGrantTokens.sha256) `
    "p14.nonstandard.jedi-grants.all-token-inventory"
Assert-JediGrant ($authenticatedActions.Count -eq [int]$grant.authenticatedCore3Actions.count -and
    (Get-NameSetSha256 $authenticatedActions) -ceq
        [string]$grant.authenticatedCore3Actions.sha256) `
    "p14.nonstandard.jedi-grants.core3-authenticated-action-inventory"
Assert-JediGrant ($classifiedNonCommands.Count -eq [int]$grant.classifiedNonCommandTokens.count -and
    (Test-ExactOrdinalNames $classifiedNonCommands $grant.classifiedNonCommandTokens.names) -and
    (Get-NameSetSha256 $classifiedNonCommands) -ceq
        [string]$grant.classifiedNonCommandTokens.sha256 -and
    ($authenticatedActions.Count + $classifiedNonCommands.Count) -eq
        $allGrantTokens.Count -and
    @($authenticatedActions | Where-Object {
        $classifiedNonCommands -ccontains [string]$_
    }).Count -eq [int]$grant.unclassifiedGrantTokens) `
    "p14.nonstandard.jedi-grants.exact-disjoint-classification"
Assert-JediGrant ($actionableGap.Count -eq [int]$grant.actionableGapBefore.count -and
    (Get-NameSetSha256 $actionableGap) -ceq
        [string]$grant.actionableGapBefore.sha256 -and
    $restoredActions.Count -eq [int]$grant.restoredActions.count -and
    (Get-NameSetSha256 $restoredActions) -ceq
        [string]$grant.restoredActions.sha256 -and
    $residualGap.Count -eq [int]$grant.residualActionableGap.count -and
    (Get-NameSetSha256 $residualGap) -ceq
        [string]$grant.residualActionableGap.sha256) `
    "p14.nonstandard.jedi-grants.112-to-4-to-108-boundary"
Assert-JediGrant ($preexistingActions.Count -eq [int]$grant.preexistingRegisteredActions.count -and
    (Get-NameSetSha256 $preexistingActions) -ceq
        [string]$grant.preexistingRegisteredActions.sha256 -and
    (Test-ExactOrdinalNames $registeredActions $expectedRegistered) -and
    $registeredActions.Count -eq [int]$grant.registeredActionsAfter.count -and
    (Get-NameSetSha256 $registeredActions) -ceq
        [string]$grant.registeredActionsAfter.sha256) `
    "p14.nonstandard.jedi-grants.current-registration-is-two-plus-four"

$skillGrantRowsExact = $true
foreach ($expected in $grant.skillGrantRows)
{
    $raw = @($skillLines | Where-Object {
        ($_ -split "`t", 2)[0] -ceq [string]$expected.name
    })
    $parsed = @($skillRows | Where-Object {
        [string]$_.NAME -ceq [string]$expected.name
    })
    $actualCommands = if ($parsed.Count -eq 1)
    {
        @(Get-OrdinalNames (([string]$parsed[0].COMMANDS).Trim('"') -split ','))
    }
    else { @() }
    $skillGrantRowsExact = $skillGrantRowsExact -and
        $raw.Count -eq 1 -and
        ($raw[0] -split "`t", -1).Count -eq [int]$expected.columns -and
        (Get-TextSha256 $raw[0]) -ceq [string]$expected.rawRowSha256 -and
        (Test-ExactOrdinalNames $actualCommands $expected.commands)
}
Assert-JediGrant $skillGrantRowsExact `
    "p14.nonstandard.jedi-grants.exact-four-skill-grant-rows"

$commandRowsExact = $true
foreach ($expected in $grant.commandRows)
{
    $raw = @($commandLines | Where-Object {
        ($_ -split "`t", 2)[0] -ceq [string]$expected.name
    })
    $parsed = @($commandRows | Where-Object {
        [string]$_.commandName -ceq [string]$expected.name
    })
    $commandRowsExact = $commandRowsExact -and
        $raw.Count -eq 1 -and
        ($raw[0] -split "`t", -1).Count -eq [int]$expected.columns -and
        (Get-TextSha256 $raw[0]) -ceq [string]$expected.rawRowSha256 -and
        $parsed.Count -eq 1 -and
        [string]$parsed[0].commandCategory -ceq "combat" -and
        [string]$parsed[0].scriptHook -ceq [string]$expected.name -and
        [string]$parsed[0].failScriptHook -ceq "failSpecialAttack" -and
        [double]$parsed[0].defaultTime -eq 1.5 -and
        [double]$parsed[0].executeTime -eq 1.5 -and
        [string]$parsed[0].target -ceq "other" -and
        [string]$parsed[0].targetType -ceq "optional" -and
        [int]$parsed[0].visible -eq 2 -and
        [int]$parsed[0].displayGroup -eq -1478973933 -and
        [int]$parsed[0].addToCombatQueue -eq 1 -and
        [string]$parsed[0].validWeapon -ceq "ALL" -and
        [string]$parsed[0].invalidWeapon -ceq "NONE"
}
Assert-JediGrant $commandRowsExact `
    "p14.nonstandard.jedi-grants.exact-four-publish-command-rows"

$provenance = $grant.commandRowProvenance
$legacyTable = Join-Path $workspaceRoot ([string]$provenance.legacyTable)
$publishExtract = Join-Path $workspaceRoot ([string]$provenance.publish12Extract)
Assert-JediGrant ((Test-Path -LiteralPath $legacyTable -PathType Leaf) -and
    (Get-Item -LiteralPath $legacyTable).Length -eq [long]$provenance.legacyTableBytes -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $legacyTable).Hash.ToLowerInvariant() -ceq
        [string]$provenance.legacyTableSha256 -and
    (Test-Path -LiteralPath $publishExtract -PathType Leaf) -and
    (Get-Item -LiteralPath $publishExtract).Length -eq [long]$provenance.publish12ExtractBytes -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $publishExtract).Hash.ToLowerInvariant() -ceq
        [string]$provenance.publish12ExtractSha256) `
    "p14.nonstandard.jedi-grants.command-row-provenance"

$forceEvidence = $contract.forceDefenseRestorationEvidence
$dsrcRoot = Join-Path $source "dsrc"
$dsrcCommit = (& git -C $dsrcRoot rev-parse HEAD 2>$null | Out-String).Trim()
Assert-JediGrant ($dsrcCommit -ceq [string]$forceEvidence.directSourceCommit -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant() -ceq
        [string]$forceEvidence.sourceSha256."skills.tab" -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $commandPath).Hash.ToLowerInvariant() -ceq
        [string]$forceEvidence.sourceSha256."command_table.tab") `
    "p14.nonstandard.jedi-grants.direct-source-pin"
Assert-JediGrant (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -ccontains
    [string]$contract.status) "p14.nonstandard.jedi-grants.status"

if ($grantFailures.Count -gt 0)
{
    throw "Jedi command-grant closure failed: $($grantFailures -join ', ')"
}

$build = $contract.buildEvidence
$matrixOverlay = Join-Path $restorationRoot (
    [string]$build.overlayPatch -replace "^restoration/", "")
$fixtureOverlay = Join-Path $restorationRoot (
    [string]$build.runtimeFixtureOverlay -replace "^restoration/", "")
$runnerPath = Join-Path $restorationRoot (
    [string]$build.runtimeRunner -replace "^restoration/", "")
if ((Get-FileHash $matrixOverlay -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        [string]$build.overlayPatchSha256 -or
    (Get-FileHash $fixtureOverlay -Algorithm SHA256).Hash.ToUpperInvariant() -cne
        [string]$build.runtimeFixtureOverlaySha256 -or
    (Get-FileHash $fixturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne
        [string]$build.runtimeFixtureSha256 -or
    (Get-FileHash $runnerPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne
        [string]$build.runtimeRunnerSha256 -or
    [int]$build.globalProfessionAudit.divergences -ne 0)
{
    throw "Nonstandard matrix build evidence failed."
}

$fixture = Get-Content $fixturePath -Raw
$contractFamilies = @($contract.families | ForEach-Object { [string]$_.root })
$fixtureFamilies = @([regex]::Matches(
    $fixture,
    '(?m)^\s{8}"(?<family>(?:crafting_shipwright|pilot_[a-z_]+|force_[a-z_]+|jedi_[a-z_]+))",?\r?$'
) | ForEach-Object { $_.Groups['family'].Value })
$fixtureReady = (
    $contractFamilies.Count -eq 21 -and
    $fixtureFamilies.Count -eq 21 -and
    ((($contractFamilies | Sort-Object) -join ([char]0)) -ceq
        (($fixtureFamilies | Sort-Object) -join ([char]0))) -and
    ($fixture -match 'PLAYER_OID\s*=\s*44003778L') -and
    ($fixture -match 'PLAYER_STATION_ID\s*=\s*91001') -and
    ($fixture -match 'PROTOCOL_VERSION\s*=\s*1') -and
    ($fixture -match 'hasObjVar\s*\(\s*player\s*,\s*ROOT\s*\)') -and
    ($fixture -match 'setObjVar\s*\(\s*player\s*,\s*PRE_OWNED') -and
    ($fixture -match 'setObjVar\s*\(\s*player\s*,\s*PRE_ROOT_OWNED') -and
    ($fixture -match 'setObjVar\s*\(\s*player\s*,\s*PRE_JEDI_STATE') -and
    ($fixture -match 'grantSkill\s*\(\s*player\s*,\s*skillName\s*\)') -and
    ($fixture -match 'revokeSkill\s*\(\s*player\s*,\s*skillName\s*\)') -and
    ($fixture -match '(?s)rootSkillName\.startsWith\s*\(\s*"pilot_"\s*\).*?utils\.setScriptVar\s*\(\s*player\s*,\s*"revokePilotSkill".*?restoreSkillOwnership\s*\(\s*player\s*,\s*skillName.*?restoreSkillOwnership\s*\(\s*player\s*,\s*rootSkillName.*?finally.*?utils\.removeScriptVar\s*\(\s*player\s*,\s*"revokePilotSkill"') -and
    ($fixture -match 'setJediState\s*\(\s*player\s*,\s*preJediState\s*\)') -and
    ($fixture -match '(?s)boolean\s+restored\s*=\s*restore\s*\(\s*player\s*\).*?if\s*\(\s*!restored\s*\).*?removeObjVar\s*\(\s*player\s*,\s*ROOT\s*\)') -and
    ($fixture -match 'token\.matches\s*\(\s*"\^\[a-f0-9\]\{32\}\$"\s*\)') -and
    ($fixture -match 'JEDI_STATE_FORCE_SENSITIVE') -and
    ($fixture -match 'JEDI_STATE_JEDI') -and
    ($fixture -match 'sendConsoleCommand\s*\(\s*"/ui action skills"\s*,\s*player\s*\)') -and
    ($fixture -notmatch 'setSkillTemplate|setLevel|getLevel')
)
if (-not $fixtureReady)
{
    throw "Nonstandard runtime fixture is not exact or reversible."
}

if ($Expectation -in @("Build", "Ready"))
{
    $currentBuild = $forceEvidence.build
    $artifactProperties = @($currentBuild.compiledArtifacts.PSObject.Properties)
    $artifactNames = @($artifactProperties | ForEach-Object { [string]$_.Name })
    $requiredPathProperties = @(
        $currentBuild.requiredArtifactPaths.PSObject.Properties)
    $requiredPathNames = @($requiredPathProperties |
        ForEach-Object { [string]$_.Name })
    $requiredPaths = @($requiredPathProperties |
        ForEach-Object { [string]$_.Value })
    $canonicalCommandIff =
        "/swg-precu/data/sku.0/sys.shared/compiled/game/datatables/command/command_table.iff"
    $containerProperty = $currentBuild.PSObject.Properties['container']
    $container = if ($null -ne $containerProperty)
    {
        [string]$containerProperty.Value
    }
    else { "" }
    $buildReady = (
        [string]$currentBuild.result -ceq "passed" -and
        [string]$currentBuild.sourceWorkParity.result -ceq "passed" -and
        [int]$currentBuild.sourceWorkParity.checkedFiles -eq 2 -and
        [int]$currentBuild.sourceWorkParity.matchedFiles -eq 2 -and
        (Test-ExactOrdinalNames $currentBuild.sourceWorkParity.files @(
            [string]$contract.sourceFiles.skillTable,
            [string]$contract.sourceFiles.commandTable
        )) -and
        @("implemented-build-verified-live-pending", "ready") -ccontains
            [string]$contract.status -and
        (Test-ExactOrdinalNames $artifactNames $currentBuild.requiredArtifacts) -and
        (Test-ExactOrdinalNames $requiredPathNames $currentBuild.requiredArtifacts) -and
        $requiredPaths.Count -eq 1 -and
        @(Get-OrdinalNames $requiredPaths).Count -eq $requiredPaths.Count -and
        [string]$currentBuild.requiredArtifactPaths."command_table.iff" -ceq
            $canonicalCommandIff -and
        -not [string]::IsNullOrWhiteSpace($container)
    )
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
        $artifactPath = if ([string]$property.Name -ceq "command_table.iff")
        {
            $canonicalCommandIff
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
    $recompile = $currentBuild.deterministicTableRecompile
    $recompileTables = @($recompile.tables.PSObject.Properties)
    $recompileReady = (
        [string]$recompile.result -ceq "passed" -and
        [string]$recompile.compiler -ceq
            "/swg-precu/build/bin/DataTableTool" -and
        [string]$recompile.temporaryRoot -ceq "/dev/shm" -and
        [bool]$recompile.cleanupVerified -and
        $recompileTables.Count -eq 1 -and
        [string]$recompileTables[0].Name -ceq "command_table.iff" -and
        [string]$recompileTables[0].Value.sourcePath -ceq
            "/swg-precu/dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab" -and
        [string]$recompileTables[0].Value.sourceSha256 -ceq
            [string]$forceEvidence.sourceSha256."command_table.tab" -and
        [string]$recompileTables[0].Value.canonicalPath -ceq
            $canonicalCommandIff -and
        [bool]$recompileTables[0].Value.freshOutputMatchesCanonical)
    $buildReady = $buildReady -and $recompileReady
    $parityPaths = @($currentBuild.sourceWorkParity.files)
    $parityMatches = 0
    foreach ($relativePath in $parityPaths)
    {
        $normalizedPath = $relativePath.Replace('\', '/')
        & docker exec $container cmp -s "/swg-precu-source/$normalizedPath" `
            "/swg-precu/$normalizedPath"
        if ($LASTEXITCODE -eq 0) { ++$parityMatches }
    }
    $buildReady = $buildReady -and $parityMatches -eq 2
    if ($buildReady)
    {
        $buildReady = Test-CommandTableFreshRecompile -Container $container
    }
    if (-not $buildReady)
    {
        throw "Current Force-defense command-table build evidence is incomplete or does not match the deployed artifact."
    }
}
elseif ([string]$contract.status -ceq "implemented-build-pending")
{
    if ([string]$forceEvidence.build.result -cne "pending" -or
        [string]$forceEvidence.build.sourceWorkParity.result -cne "pending" -or
        [int]$forceEvidence.build.sourceWorkParity.checkedFiles -ne 2 -or
        [int]$forceEvidence.build.sourceWorkParity.matchedFiles -ne 0 -or
        -not (Test-ExactOrdinalNames `
            $forceEvidence.build.sourceWorkParity.files @(
                [string]$contract.sourceFiles.skillTable,
                [string]$contract.sourceFiles.commandTable
            )) -or
        [string]$forceEvidence.build.deterministicTableRecompile.result -cne
            "pending" -or
        [bool]$forceEvidence.build.deterministicTableRecompile.cleanupVerified -or
        [bool]$forceEvidence.build.deterministicTableRecompile.tables.
            "command_table.iff".freshOutputMatchesCanonical -or
        [string]$forceEvidence.live.result -cne "pending" -or
        [string]$forceEvidence.live.acceptanceOwner -cne
            "p14-armor-mitigation-ordering" -or
        [string]$forceEvidence.live.requiredOwnerStatus -cne "ready" -or
        [string]$forceEvidence.live.directSourceCommit -cne
            [string]$forceEvidence.directSourceCommit -or
        @($contract.requiredBeforeReady).Count -ne 2)
    {
        throw "Pending Force-defense source evidence is not truthful."
    }
}

if ($Expectation -eq "Ready")
{
    & (Join-Path $PSScriptRoot "Test-P14ArmorMitigationOrdering.ps1") `
        -SourceRoot $source `
        -Expectation Ready
    $armorContract = Get-Content (
        Join-Path $restorationRoot `
            ([string]$manifest.contracts.p14ArmorMitigationOrdering)
    ) -Raw | ConvertFrom-Json
    $armorForce = $armorContract.forceDefenseContract
    if ([string]$forceEvidence.live.result -cne "passed" -or
        [string]$forceEvidence.live.acceptanceOwner -cne
            "p14-armor-mitigation-ordering" -or
        [string]$forceEvidence.live.requiredOwnerStatus -cne "ready" -or
        [string]$forceEvidence.live.directSourceCommit -cne
            [string]$forceEvidence.directSourceCommit -or
        [string]$armorContract.status -cne "ready" -or
        [string]$armorForce.directSourceCommit -cne
            [string]$forceEvidence.directSourceCommit -or
        [string]$armorForce.build.result -cne "passed" -or
        [string]$armorForce.deployment.result -cne "passed" -or
        [string]$armorForce.live.result -cne "passed" -or
        [string]$armorForce.live.containerStartedAt -cne
            [string]$armorForce.deployment.containerStartedAt)
    {
        throw "Nonstandard Ready is not bound to the independently validated current Force-defense live owner."
    }
    $runtime = $contract.runtimeEvidence
    $proof = @($runtime.familyProof)
    $proofFamilies = @($proof | ForEach-Object { [string]$_.family })
    $screenshots = @($runtime.screenshots)
    $screenshotKinds = @($screenshots | ForEach-Object { [string]$_.kind })
    $runtimeReady = (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$forceEvidence.build.result -ceq "passed" -and
        [string]$forceEvidence.live.result -ceq "passed" -and
        [string]$runtime.result -ceq "passed" -and
        $proof.Count -eq 21 -and
        ((($proofFamilies | Sort-Object) -join ([char]0)) -ceq
            (($contractFamilies | Sort-Object) -join ([char]0))) -and
        @($proof | Where-Object {
            [string]$_.result -cne "passed" -or
            [string]$_.cleanup -cne "restored"
        }).Count -eq 0 -and
        [string]$runtime.boundaries.relog -ceq "passed" -and
        [string]$runtime.boundaries.restart -ceq "passed" -and
        [string]$runtime.exactCleanup -ceq "passed" -and
        $screenshots.Count -eq 4 -and
        (($screenshotKinds -join ",") -ceq
            "shipwright,pilot,force_sensitive,jedi") -and
        @($screenshots | Where-Object {
            [string]$_.sha256 -notmatch '^[A-F0-9]{64}$' -or
            [int64]$_.bytes -le 0
        }).Count -eq 0 -and
        [bool]$runtime.serverHealthy
    )
    if (-not $runtimeReady)
    {
        throw "Specialized runtime evidence is incomplete."
    }
}

Write-Host "Publish 14.1 nonstandard profession matrix $Expectation closure passed."
