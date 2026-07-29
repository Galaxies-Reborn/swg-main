[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content (
    Join-Path $restorationRoot `
        ([string]$manifest.contracts.p14NonstandardProfessionMatrixClosure)
) -Raw | ConvertFrom-Json
$source = (Resolve-Path $SourceRoot).Path
$skillPath = Join-Path $source ([string]$contract.sourceFiles.skillTable)
$fixturePath = Join-Path $source ([string]$contract.sourceFiles.liveFixture)
$skillLines = Get-Content $skillPath

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

if ($Expectation -eq "Ready")
{
    $runtime = $contract.runtimeEvidence
    $proof = @($runtime.familyProof)
    $proofFamilies = @($proof | ForEach-Object { [string]$_.family })
    $screenshots = @($runtime.screenshots)
    $screenshotKinds = @($screenshots | ForEach-Object { [string]$_.kind })
    $runtimeReady = (
        [string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
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
