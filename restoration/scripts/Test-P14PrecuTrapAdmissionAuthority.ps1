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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuTrapAdmissionAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$trapBasePath = Join-Path $source ([string]$contract.sourceFiles.trapBase)
$skillsPath = Join-Path $source ([string]$contract.sourceFiles.skills)
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

function Get-CommaValues([object]$Value)
{
    return @(([string]$Value).Trim('"').Split(',') | Where-Object { $_ -cne "" })
}

$sourcePaths = [ordered]@{
    trapBase = $trapBasePath
    skills = $skillsPath
}
$texts = @{}
foreach ($name in $sourcePaths.Keys)
{
    $path = $sourcePaths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.trap-admission.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) "p14.trap-admission.source.$name.authenticated"
    }
}

$trapBase = [string]$texts.trapBase
$admission = Get-SourceSlice $trapBase `
    "public int OnObjectMenuSelect(" `
    "public void trapUsed("
$modifierReads = ([regex]::Matches($admission,
    'getSkillStatMod[(]player, "trapping"[)]')).Count
$noviceChecks = ([regex]::Matches($admission,
    'hasSkill[(]player, "outdoors_scout_novice"[)]')).Count
$modifierOnlyChecks = ([regex]::Matches($admission,
    'if\s*[(]skillMod <= 0[)]')).Count
Assert-Contract ($modifierReads -eq [int]$contract.expected.trappingModifierReadsInAdmission -and
    $noviceChecks -eq [int]$contract.expected.noviceScoutSkillChecksInAdmission -and
    $modifierOnlyChecks -eq [int]$contract.expected.skillModifierOnlyAdmissionChecks -and
    $admission.Contains('if (skillMod <= 0 || !hasSkill(player, "outdoors_scout_novice"))')) `
    "p14.trap-admission.novice-scout-and-modifier-authority"
Assert-Contract ($admission.Contains('if (!hasObjVar(self, "droid_trap"))') -and
    $admission.Contains("if (item == menu_info_types.ITEM_USE)") -and
    $admission.Contains('new string_id("trap/trap", "trap_no_skill")')) `
    "p14.trap-admission.ordinary-radial-path"
Assert-Contract ($admission.Contains("getLookAtTarget(player)") -and
    $admission.Contains("isIdValid(objTarget)") -and
    $admission.Contains("canSee(player, objTarget)") -and
    $admission.Contains("ai_lib.isMonster(objTarget)") -and
    $admission.Contains("isIncapacitated(objTarget)") -and
    $admission.Contains("isDead(objTarget)") -and
    $admission.Contains("pet_lib.isPet(objTarget)")) `
    "p14.trap-admission.target-rules-preserved"
$queueSignature = "queueCommand(player, ($([int]$contract.expected.queueCommandCrc)), objTarget, strParams, COMMAND_PRIORITY_NORMAL)"
Assert-Contract ($admission.Contains($queueSignature)) "p14.trap-admission.throw-command-preserved"

$trapLifecycle = Get-SourceSlice $trapBase "public void trapUsed(" "public int trapDone("
$trapExperience = Get-SourceSlice $trapBase "public void grantTrapXP(" "public void assignTrapEffect("
Assert-Contract ($trapLifecycle.Contains("getCount(self) - 1") -and
    $trapLifecycle.Contains("destroyObject(self)") -and
    $trapLifecycle.Contains("setCount(self, intUses)")) `
    "p14.trap-admission.item-consumption-preserved"
Assert-Contract ($trapExperience.Contains("float targetLevel = getLevel(target)") -and
    $trapExperience.Contains("xp.updateCombatXpList(target, player, xp.SCOUT, pseudoDamage)")) `
    "p14.trap-admission.scout-experience-preserved"

$skillRows = @(Import-SwgTab -Path $skillsPath)
$noviceScout = @($skillRows | Where-Object { [string]$_.NAME -ceq "outdoors_scout_novice" })
$noviceMods = if ($noviceScout.Count -eq 1) { @(Get-CommaValues $noviceScout[0].SKILL_MODS) } else { @() }
$noviceSchematics = if ($noviceScout.Count -eq 1) { @(Get-CommaValues $noviceScout[0].SCHEMATICS_GRANTED) } else { @() }
Assert-Contract ($noviceScout.Count -eq 1 -and
    $noviceMods -ccontains [string]$contract.expected.noviceScoutModifier -and
    $noviceSchematics -ccontains [string]$contract.expected.noviceScoutTrapSchematicGroup) `
    "p14.trap-admission.novice-scout-skill-box-authenticated"

$passiveProperties = @($contract.expected.passiveTrappingSpecies.PSObject.Properties)
$passiveRows = @($skillRows | Where-Object { $passiveProperties.Name -ccontains [string]$_.NAME })
foreach ($property in $passiveProperties)
{
    $row = @($passiveRows | Where-Object { [string]$_.NAME -ceq $property.Name })
    $mods = if ($row.Count -eq 1) { @(Get-CommaValues $row[0].SKILL_MODS) } else { @() }
    Assert-Contract ($row.Count -eq 1 -and $mods -ccontains [string]$property.Value) `
        "p14.trap-admission.passive-modifier.$($property.Name)"
}
$speciesRows = @($skillRows | Where-Object { [string]$_.NAME -match '^species_' })
Assert-Contract (@($speciesRows | Where-Object {
    @(Get-CommaValues $_.COMMANDS) -ccontains "outdoors_scout_novice" -or
    @(Get-CommaValues $_.COMMANDS) -ccontains "harvestCorpse"
}).Count -eq [int]$contract.expected.speciesNoviceScoutGrants) `
    "p14.trap-admission.species-do-not-grant-scout-ability"

$speciesContractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuSpeciesPassiveAuthority)
$deviceContractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuRetainedDeviceAuthority)
$speciesContract = Get-Content -LiteralPath $speciesContractPath -Raw | ConvertFrom-Json
$deviceContract = Get-Content -LiteralPath $deviceContractPath -Raw | ConvertFrom-Json
Assert-Contract ([string]$speciesContract.status -ceq "ready" -and
    [string]$deviceContract.status -ceq "ready") `
    "p14.trap-admission.adjacent-authority-continuity"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.trap-admission.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.trap-admission.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.trapBase -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.trap-admission.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.trap-admission.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.trap-admission.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU trap admission authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU trap admission authority contract passed."
