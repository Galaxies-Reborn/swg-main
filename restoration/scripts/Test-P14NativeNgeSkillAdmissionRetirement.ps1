[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot "contracts/p14-native-nge-skill-admission-retirement.json"
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$clientPath = Join-Path $root "src/engine/server/library/serverGame/src/shared/core/Client.cpp"
$creaturePath = Join-Path $root "src/engine/server/library/serverGame/src/shared/object/CreatureObject.cpp"
$skillsPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$commandTablePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$client = Get-Content -LiteralPath $clientPath -Raw
$creature = Get-Content -LiteralPath $creaturePath -Raw

$srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$checkedOutSrcCommit = (& git -C (Join-Path $root "src") rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or
    [string]$manifest.sourceMode -cne "direct-branch" -or
    $srcPin.Count -ne 1 -or
    [string]$srcPin[0].commit -cne [string]$contract.buildEvidence.nativeSourceCommit -or
    $checkedOutSrcCommit -cne [string]$contract.buildEvidence.nativeSourceCommit)
{
    throw "The native NGE admission contract is not pinned to the checked-out direct source revision."
}

function Get-BracedSurface
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Signature
    )

    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing native surface: $Signature" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { throw "Missing opening brace for: $Signature" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    throw "Missing closing brace for: $Signature"
}

$messageStart = $client.IndexOf('case constcrc("ExpertiseRequestMessage")', [StringComparison]::Ordinal)
$messageEnd = $client.IndexOf('case constcrc("UpdateSessionPlayTimeInfo")', $messageStart, [StringComparison]::Ordinal)
if ($messageStart -lt 0 -or $messageEnd -le $messageStart)
{
    throw "Could not isolate the native expertise message case."
}
$messageSurface = $client.Substring($messageStart, $messageEnd - $messageStart)
if (-not $messageSurface.Contains("Ignored retired NGE ExpertiseRequestMessage"))
{
    throw "The native expertise packet is not explicitly retired."
}
foreach ($retired in @(
    "Archive::ReadIterator",
    "ExpertiseRequestMessage const",
    "getAddExpertisesList",
    "getClearAllExpertisesFirst",
    "processExpertiseRequest"
))
{
    if ($messageSurface.Contains($retired))
    {
        throw "The native expertise packet still dispatches later-era behavior: $retired"
    }
}
if ($client.Contains('#include "sharedNetworkMessages/ExpertiseRequestMessage.h"'))
{
    throw "The retired expertise message implementation include remains."
}

$nameGuard = Get-BracedSurface -Text $creature -Signature "bool isRetiredNgeProgressionSkillName"
foreach ($required in @('find("class_") == 0', 'skillName == "expertise"', 'find("expertise_") == 0', 'find("internal_expertise_") == 0'))
{
    if (-not $nameGuard.Contains($required)) { throw "NGE skill-name guard is incomplete: $required" }
}

$skills = @(Import-SwgTab -Path $skillsPath)
$commandRows = @(Import-SwgTab -Path $commandTablePath)
$retiredCommands = @{}
$retainedCommands = @{}
foreach ($skill in $skills)
{
    $skillName = [string]$skill.NAME
    $isRetired = $skillName.StartsWith("class_", [StringComparison]::Ordinal) -or
        $skillName -ceq "expertise" -or
        $skillName.StartsWith("expertise_", [StringComparison]::Ordinal) -or
        $skillName.StartsWith("internal_expertise_", [StringComparison]::Ordinal)
    foreach ($commandName in @(([string]$skill.COMMANDS -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }))
    {
        if ($isRetired) { $retiredCommands[$commandName] = $true }
        else { $retainedCommands[$commandName] = $true }
    }
}
$retiredOnly = @($retiredCommands.Keys | Where-Object { -not $retainedCommands.ContainsKey($_) } | Sort-Object)
$retiredOnlySet = @{}
foreach ($commandName in $retiredOnly) { $retiredOnlySet[$commandName] = $true }
$blankAbility = @($commandRows | Where-Object {
    $retiredOnlySet.ContainsKey([string]$_.commandName) -and
    [string]::IsNullOrWhiteSpace([string]$_.characterAbility)
})
$blankAbilityNames = @($blankAbility.commandName | Sort-Object)
$retiredPlayerCommands = @($contract.diagnosis.retiredPlayerCommands | ForEach-Object { [string]$_ } | Sort-Object)
$retiredDirectGrantPlayerCommands = @($contract.diagnosis.retiredDirectGrantPlayerCommands | ForEach-Object { [string]$_ } | Sort-Object)
$retiredCyberneticPlayerCommands = @($contract.diagnosis.retiredCyberneticPlayerCommands | ForEach-Object { [string]$_ } | Sort-Object)
$retainedPreCuExceptions = @($contract.diagnosis.retainedPreCuExceptions | ForEach-Object { [string]$_ } | Sort-Object)
$classifiedBlankAbilityNames = @(($retiredPlayerCommands + $retainedPreCuExceptions) | Sort-Object)
if ($retiredCommands.Count -ne [int]$contract.diagnosis.retiredSkillCommands -or
    $retainedCommands.Count -ne [int]$contract.diagnosis.retainedSkillCommands -or
    $retiredOnly.Count -ne [int]$contract.diagnosis.retiredOnlyCommands -or
    $blankAbility.Count -ne [int]$contract.diagnosis.retiredOnlyBlankAbilityCommands -or
    ($blankAbilityNames -join ([char]0)) -cne ($classifiedBlankAbilityNames -join ([char]0)))
{
    throw "The NGE-only blank-ability command inventory changed or is incompletely classified."
}

$commandGuard = Get-BracedSurface -Text $creature -Signature "bool isRetiredNgeProgressionCommandName"
foreach ($commandName in $retiredPlayerCommands)
{
    if (-not $commandGuard.Contains('commandName == "' + $commandName + '"'))
    {
        throw "Retired blank-ability command is not denied: $commandName"
    }
}
foreach ($commandName in $retiredDirectGrantPlayerCommands)
{
    if (-not $commandGuard.Contains('commandName == "' + $commandName + '"'))
    {
        throw "Retired direct-grant command is not denied: $commandName"
    }
}
foreach ($commandName in $retiredCyberneticPlayerCommands)
{
    if (-not $commandGuard.Contains('commandName == "' + $commandName + '"'))
    {
        throw "Retired cybernetic player command is not denied: $commandName"
    }
}
foreach ($commandName in $retainedPreCuExceptions)
{
    if ($commandGuard.Contains('"' + $commandName + '"'))
    {
        throw "Retained PRE-CU command was added to the native deny set: $commandName"
    }
}

$warmup = Get-BracedSurface -Text $creature -Signature "void CreatureObject::doWarmupChecks"
$retiredCommandAdmission = 'isPlayerControlled() && CreatureObjectNamespace::isRetiredNgeProgressionCommandName(command.m_commandName)'
$abilityAdmission = 'isPlayerControlled() && command.m_characterAbility.size() && !hasCommand(command.m_characterAbility)'
if (-not $warmup.Contains($retiredCommandAdmission) -or
    -not $warmup.Contains('ignored as a retired NGE progression command') -or
    -not $warmup.Contains('status = Command::CEC_Ability;') -or
    $warmup.IndexOf($retiredCommandAdmission, [StringComparison]::Ordinal) -gt
        $warmup.IndexOf($abilityAdmission, [StringComparison]::Ordinal))
{
    throw "Native NGE command admission does not fail closed before the blank character-ability bypass."
}

$grant = Get-BracedSurface -Text $creature -Signature "const bool CreatureObject::grantSkill"
foreach ($required in @("isPlayerControlled()", "isRetiredNgeProgressionSkillName", "return false;"))
{
    if (-not $grant.Contains($required)) { throw "Authoritative skill admission guard is incomplete: $required" }
}

$remaining = Get-BracedSurface -Text $creature -Signature "int CreatureObject::getRemainingExpertisePoints() const"
if (-not $remaining.Contains("return 0;")) { throw "The retired expertise point pool is not fixed at zero." }
foreach ($retired in @("ExpertiseManager", "getLevel()", "getExpertisesForPlayer"))
{
    if ($remaining.Contains($retired)) { throw "Combat-level expertise accounting remains: $retired" }
}

$request = Get-BracedSurface -Text $creature -Signature "bool CreatureObject::processExpertiseRequest"
foreach ($required in @("UNREF(addExpertisesNamesList)", "UNREF(clearAllExpertisesFirst)", "Rejected retired NGE expertise request", "return false;"))
{
    if (-not $request.Contains($required)) { throw "Native expertise request does not fail closed: $required" }
}
foreach ($retired in @("grantSkill", "ExpertiseManager", "isGod()", "return true;"))
{
    if ($request.Contains($retired)) { throw "Native expertise request still admits later-era behavior: $retired" }
}

$loaded = Get-BracedSurface -Text $creature -Signature "void CreatureObject::onLoadedFromDatabase()"
foreach ($retired in @("remainingExpertisePoints", "getRemainingExpertisePoints()", "more expertises than level"))
{
    if ($loaded.Contains($retired)) { throw "Combat-level expertise validation remains on player load: $retired" }
}
if (-not $creature.Contains("bool CreatureObject::clearAllExpertises()"))
{
    throw "Persisted later-era expertise cleanup compatibility was removed."
}

if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or
        $contract.buildEvidence.cppCompile -ne "passed" -or
        $contract.buildEvidence.architecture -ne "x86-64" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Native NGE skill-admission evidence is not ready."
    }
    foreach ($entry in @{
        "Client.cpp" = $clientPath
        "CreatureObject.cpp" = $creaturePath
    }.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/src/341-p14-native-nge-skill-admission-retirement.patch"
    $patch = Get-Item -LiteralPath $patchPath
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ($patch.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $patchHash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}

Write-Host "Publish 14.1 native NGE skill-admission retirement contract passed."
