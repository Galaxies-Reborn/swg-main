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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14WeaponCertificationOwnership)
) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$combatPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.combatLibrary)
$fixturePath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.liveFixture)
$weaponRoot = Join-Path $resolvedRoot ([string]$contract.sourceFiles.sharedWeaponRoot)

foreach ($path in @($combatPath, $fixturePath, $weaponRoot))
{
    if (-not (Test-Path -LiteralPath $path))
    {
        throw "Required certification source path is missing: $path"
    }
}

$combat = Get-Content -LiteralPath $combatPath -Raw
$methodStart = $combat.IndexOf(
    "public static boolean hasCertification(obj_id objPlayer, obj_id objWeapon, boolean verbose)",
    [StringComparison]::Ordinal
)
$methodEnd = $combat.IndexOf(
    "public static void applyCombatSpeedDelay",
    $methodStart + 1,
    [StringComparison]::Ordinal
)
if ($methodStart -lt 0 -or $methodEnd -lt 0)
{
    throw "Unable to isolate combat.hasCertification."
}
$method = $combat.Substring($methodStart, $methodEnd - $methodStart)

foreach ($required in @(
    "getRequiredCertifications(objWeapon)",
    "hasCommand(objPlayer, requirement)",
    "hasSkill(objPlayer, requirement)"
))
{
    if (-not $method.Contains($required))
    {
        throw "combat.hasCertification is missing '$required'."
    }
}
foreach ($forbidden in @(
    "getSkillTemplate(",
    "utils.isProfession(",
    "getLevel(",
    "weapon_level",
    "required_skill",
    "secondary_restriction",
    "dynamic_item.intLevelRequired"
))
{
    if ($method.Contains($forbidden))
    {
        throw "combat.hasCertification still contains inherited NGE gate '$forbidden'."
    }
}

$templateFiles = @(Get-ChildItem -LiteralPath $weaponRoot -Recurse -File -Filter "shared_*.tpf")
$certificationFiles = [System.Collections.Generic.List[object]]::new()
foreach ($file in $templateFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $matches = [regex]::Matches(
        $text,
        '(?m)^[ \t]*certificationsRequired[ \t]*=[ \t]*\[(?<requirements>[^\]]+)\][ \t]*(?=\r?$)'
    )
    if ($matches.Count -gt 1)
    {
        throw "Multiple certificationsRequired declarations found in $($file.FullName)."
    }
    if ($matches.Count -eq 1)
    {
        $classMatch = [regex]::Match(
            $text,
            '(?m)^@class tangible_object_template (?<version>[0-9]+)[ \t]*(?=\r?$)'
        )
        if (-not $classMatch.Success -or
            [int]$classMatch.Groups["version"].Value -lt
                [int]$contract.expected.minimumTangibleSchemaRevision)
        {
            throw "Certification template $($file.FullName) does not declare the required tangible schema revision."
        }
        $requirements = @(
            [regex]::Matches($matches[0].Groups["requirements"].Value, '"([^"]+)"') |
                ForEach-Object { $_.Groups[1].Value }
        )
        if ($requirements.Count -eq 0 -or $requirements -contains "")
        {
            throw "Empty weapon certification declaration found in $($file.FullName)."
        }
        $certificationFiles.Add([pscustomobject]@{
            Path = $file.FullName
            Requirements = $requirements
        })
    }
}
if ($certificationFiles.Count -ne [int]$contract.expected.matchedSharedTemplates)
{
    throw "Expected $($contract.expected.matchedSharedTemplates) shared weapon certification templates; found $($certificationFiles.Count)."
}

foreach ($representative in $contract.expected.representativeTemplates)
{
    $path = Join-Path $resolvedRoot ([string]$representative.path)
    $text = Get-Content -LiteralPath $path -Raw
    $expectedLine = 'certificationsRequired = ["' +
        ((@($representative.requirements) -join '", "')) + '"]'
    if (-not $text.Contains($expectedLine))
    {
        throw "Representative template $($representative.path) does not contain '$expectedLine'."
    }
}

$fixture = Get-Content -LiteralPath $fixturePath -Raw
foreach ($required in @(
    "combat.hasCertification(player, cdef, false)",
    "combat.hasCertification(player, lightsaber, false)",
    "getRequiredCertifications(cdef)",
    "getRequiredCertifications(lightsaber)",
    "grantCommand(player, CDEF_CERTIFICATION)",
    "revokeCommand(player, CDEF_CERTIFICATION)",
    "destroyObject(cdef)",
    "destroyObject(lightsaber)"
))
{
    if (-not $fixture.Contains($required))
    {
        throw "Observation-only certification fixture is missing '$required'."
    }
}

foreach ($entry in $contract.buildEvidence.sourceSha256.psobject.Properties)
{
    $path = switch ($entry.Name)
    {
        "combat.java" { $combatPath }
        "precu_weapon_certification_fixture.java" { $fixturePath }
        default { throw "Unknown certification source hash entry '$($entry.Name)'." }
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actual -cne [string]$entry.Value)
    {
        throw "$($entry.Name) hash mismatch. Expected $($entry.Value), got $actual."
    }
}

$importerPath = Join-Path $restorationRoot (
    [string]$contract.buildEvidence.importer -replace "^restoration/", ""
)
$actualImporterHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $importerPath).Hash.ToLowerInvariant()
if ($actualImporterHash -cne [string]$contract.buildEvidence.importerSha256)
{
    throw "Weapon certification importer hash mismatch. Expected $($contract.buildEvidence.importerSha256), got $actualImporterHash."
}

if ($Expectation -eq "Ready")
{
    if ([string]$contract.status -cne "ready" -or
        [string]$contract.runtimeEvidence.result -cne "passed" -or
        [string]$contract.clientAssetEvidence.result -cne "passed")
    {
        throw "Weapon certification ownership does not yet contain passed runtime and client-asset evidence."
    }
    $patchPath = Join-Path $restorationRoot (
        [string]$contract.buildEvidence.overlayPatch -replace "^restoration/", ""
    )
    $actualPatchHash =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne
            [long]$contract.buildEvidence.overlayPatchBytes -or
        $actualPatchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "Weapon certification overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 weapon certification ownership contract passed."
