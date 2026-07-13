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
$skills = @(Import-SwgTab -Path $skillTablePath)
$commands = @(Import-SwgTab -Path $commandTablePath)

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
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$SignaturePattern
    )

    $pattern = "(?s)$SignaturePattern.*?(?=\r?\n\s*public\s+static\s+|\z)"
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success)
    {
        return ""
    }

    return $match.Value
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

$skillScriptPath = Join-Path $source ([string]$contract.sourceFiles.skillScript)
$teacherScriptPath = Join-Path $source ([string]$contract.sourceFiles.teacherScript)
$commandCppPath = Join-Path $source ([string]$contract.sourceFiles.commandCpp)
$skillScript = Get-Content -LiteralPath $skillScriptPath -Raw
$teacherScript = Get-Content -LiteralPath $teacherScriptPath -Raw
$commandCpp = Get-Content -LiteralPath $commandCppPath -Raw

$teachableWindow = Get-JavaMethodWindow -Source $skillScript -SignaturePattern "public\s+static\s+String\[\]\s+getTeachableSkills\s*\("
$teachableImplemented = (
    ($teachableWindow.Length -gt 0) -and
    ($teachableWindow -notmatch "\breturn\s+null\s*;") -and
    ($teachableWindow -match "\b(deltaTeacherSkills|getTeacherSkills)\s*\(")
)
Add-PhaseCheck -Id "phaseA.training.teachable-list" -Passed $teachableImplemented -Detail "getTeachableSkills must derive the trainer-minus-player list"

$moneyDerived = (
    ($teacherScript -match [regex]::Escape("MONEY_REQUIRED")) -and
    ($teacherScript -notmatch "\bint\s+cost\s*=\s*1\s*;")
)
Add-PhaseCheck -Id "phaseA.training.money-derived" -Passed $moneyDerived -Detail "trainer money must come from MONEY_REQUIRED, never a literal"

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
    ($surrenderRows[0].cppHook -ceq "surrenderSkill") -and
    ([int]$surrenderRows[0].godLevel -eq 0)
)
Add-PhaseCheck -Id "phaseA.surrender.command-table" -Passed $surrenderCommandReady -Detail "surrenderSkill must be a separate player-safe cppHook at godLevel 0"

$surrenderNativeReady = (
    ($commandCpp -match "\bcommandFuncSurrenderSkill\b") -and
    ($commandCpp -match 'addCppFunction\s*\(\s*"surrenderSkill"\s*,\s*commandFuncSurrenderSkill\s*\)')
)
Add-PhaseCheck -Id "phaseA.surrender.native-handler" -Passed $surrenderNativeReady -Detail "native handler and CommandTable registration must both exist"

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

        $definitions = @($commands | Where-Object { $_.commandName -ieq $grant })
        Add-PhaseCheck -Id "phaseA.commands.$scope.$grant" -Passed ($definitions.Count -eq 1) -Detail "actionable skill grant must resolve to exactly one command_table row; found $($definitions.Count)"
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
