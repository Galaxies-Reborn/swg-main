param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build",

    [string]$Container = "swg-precu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14JediConversionLifecycleRetirement)) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$conversionPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.jediConversion)
$gmPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.gmLibrary)

foreach ($path in @($conversionPath, $gmPath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required source file is missing: $path"
    }
}

$conversion = Get-Content -LiteralPath $conversionPath -Raw
$gm = Get-Content -LiteralPath $gmPath -Raw

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0)
    {
        throw "Missing method signature: $Signature"
    }
    $open = $Text.IndexOf('{', $start)
    if ($open -lt 0)
    {
        throw "Missing method body: $Signature"
    }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{')
        {
            $depth++
        }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    throw "Unterminated method body: $Signature"
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message)
{
    if (-not $Text.Contains($Needle))
    {
        throw $Message
    }
}

function Assert-Excludes([string]$Text, [string[]]$Needles, [string]$Surface)
{
    foreach ($needle in $Needles)
    {
        if ($Text.Contains($needle))
        {
            throw "$Surface still contains retired mutation '$needle'."
        }
    }
}

$cleanup = Get-BracedSurface $conversion "public static void retireNgeJediConversionState(obj_id player)"
Assert-Contains $cleanup '!isIdValid(player) || !exists(player) || !isPlayer(player)' `
    "The Jedi conversion cleanup does not fail closed for invalid or non-player objects."
Assert-Contains $cleanup 'if (hasObjVar(player, "jedi.conversionSui"))' `
    "The Jedi conversion cleanup does not detect a persisted conversion SUI."
Assert-Contains $cleanup 'forceCloseSUIPage(pid);' `
    "The Jedi conversion cleanup does not close a persisted conversion SUI."
Assert-Contains $cleanup 'removeObjVar(player, retiredObjVar);' `
    "The Jedi conversion cleanup does not remove its bounded objvar inventory."
Assert-Contains $cleanup 'utils.removeScriptVar(player, retiredScriptVar);' `
    "The Jedi conversion cleanup does not remove its bounded scriptvar inventory."

$objVarCount = 0
foreach ($name in @($contract.inventory.retiredObjVars))
{
    if ($cleanup.Contains('"' + [string]$name + '"'))
    {
        $objVarCount++
    }
}
$scriptVarCount = 0
foreach ($name in @($contract.inventory.retiredScriptVars))
{
    if ($cleanup.Contains('"' + [string]$name + '"'))
    {
        $scriptVarCount++
    }
}
if ($objVarCount -ne [int]$contract.expected.retiredObjVars -or
    $scriptVarCount -ne [int]$contract.expected.retiredScriptVars)
{
    throw "The Jedi conversion cleanup inventory does not match the contract."
}
Assert-Excludes $cleanup @("setObjVar(", "grantSkill(", "revokeSkill(", "grantExperiencePoints(") `
    "Jedi conversion cleanup helper"

$scriptSurfaces = @(
    @{ Name = "OnAttach"; Signature = "public int OnAttach(obj_id self)"; Detach = $true },
    @{ Name = "convertOldJedi"; Signature = "public void convertOldJedi(obj_id self)"; Detach = $true },
    @{ Name = "OnLogin"; Signature = "public int OnLogin(obj_id self)"; Detach = $true },
    @{ Name = "OnInitialize"; Signature = "public int OnInitialize(obj_id self)"; Detach = $true },
    @{ Name = "OnDetach"; Signature = "public int OnDetach(obj_id self)"; Detach = $false }
)
$scriptCleanupCalls = 0
foreach ($entry in $scriptSurfaces)
{
    $surface = Get-BracedSurface $conversion ([string]$entry.Signature)
    Assert-Contains $surface "retireNgeJediConversionState(self);" `
        "$($entry.Name) does not invoke the canonical Jedi conversion cleanup."
    $scriptCleanupCalls++
    if ([bool]$entry.Detach)
    {
        Assert-Contains $surface 'detachScript(self, "player.player_jedi_conversion");' `
            "$($entry.Name) does not detach the retired conversion script."
    }
    Assert-Excludes $surface @("setObjVar(", "setSkillTemplate(", "setWorkingSkill(", "forceSensitiveSui(", "jediSui(", "regularSkillSui(") `
        ([string]$entry.Name)
}
if ($scriptCleanupCalls -ne [int]$contract.expected.scriptLifecycleCleanupEntrypoints)
{
    throw "The script lifecycle cleanup entrypoint count does not match the contract."
}

$convertCallCount = ([regex]::Matches($conversion, "\bconvertOldJedi\s*\(")).Count
if ($convertCallCount -ne 1)
{
    throw "convertOldJedi must remain an uncalled fail-closed compatibility method; found $convertCallCount references."
}
if ([regex]::IsMatch($conversion, 'setObjVar\s*\([^;\r\n]*"combatLevel"'))
{
    throw "The Jedi conversion script still writes the retired combatLevel objvar."
}

$gmReset = Get-BracedSurface $gm "public static void cmdResetJedi(obj_id player)"
Assert-Contains $gmReset '!isIdValid(player) || !exists(player) || !isPlayer(player)' `
    "The GM Jedi cleanup does not validate its player target."
Assert-Contains $gmReset 'script.player.player_jedi_conversion.retireNgeJediConversionState(player);' `
    "The GM Jedi cleanup does not use the canonical conversion-state cleanup."
Assert-Contains $gmReset 'detachScript(player, "player.player_jedi_conversion");' `
    "The GM Jedi cleanup does not detach a persisted conversion script."
Assert-Excludes $gmReset @("attachScript(", "setObjVar(", "grantSkill(", "revokeSkill(", "grantExperiencePoints(") `
    "GM Jedi cleanup"

$allJava = Get-ChildItem -LiteralPath (Join-Path $resolvedRoot "dsrc/sku.0/sys.server/compiled/game/script") `
    -Recurse -File -Filter "*.java"
$conversionAttachCount = 0
$convertOldJediReferenceCount = 0
foreach ($javaFile in $allJava)
{
    $java = Get-Content -LiteralPath $javaFile.FullName -Raw
    $conversionAttachCount += ([regex]::Matches($java, 'attachScript\s*\([^;\r\n]*"player\.player_jedi_conversion"')).Count
    $convertOldJediReferenceCount += ([regex]::Matches($java, '\bconvertOldJedi\s*\(')).Count
}
if ($conversionAttachCount -ne 0 -or $convertOldJediReferenceCount -ne 1)
{
    throw "The inherited Jedi conversion UI is reachable: attach=$conversionAttachCount, convertOldJedi references=$convertOldJediReferenceCount."
}
if (([int]$contract.expected.cleanupEntrypoints) -ne ($scriptCleanupCalls + 1))
{
    throw "The total Jedi conversion cleanup entrypoint count does not match the contract."
}

$sourceHashes = @{
    "player_jedi_conversion.java" = (Get-FileHash -Algorithm SHA256 -LiteralPath $conversionPath).Hash.ToLowerInvariant()
    "gm.java" = (Get-FileHash -Algorithm SHA256 -LiteralPath $gmPath).Hash.ToLowerInvariant()
}
foreach ($name in @($sourceHashes.Keys))
{
    if ([string]$sourceHashes[$name] -cne [string]$contract.buildEvidence.sourceSha256.$name)
    {
        throw "$name hash mismatch. Expected $($contract.buildEvidence.sourceSha256.$name), got $($sourceHashes[$name])."
    }
}

$patchPath = Join-Path $restorationRoot ([string]$contract.buildEvidence.overlayPatch -replace "^restoration/", "")
$patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
if ((Get-Item -LiteralPath $patchPath).Length -ne [long]$contract.buildEvidence.overlayPatchBytes -or
    $patchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
{
    throw "The Jedi conversion lifecycle overlay patch does not match its locked evidence."
}

if ($Expectation -eq "Ready")
{
    if ([string]$contract.status -cne "ready" -or
        [string]$contract.runtimeEvidence.result -cne "passed" -or
        [string]$contract.buildEvidence.fullJavaBuild.result -cne "passed")
    {
        throw "The Jedi conversion lifecycle retirement is not backed by passed build and runtime evidence."
    }
    $state = (& docker inspect --format "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $Container).Trim()
    if ($LASTEXITCODE -ne 0 -or $state -cne "running healthy")
    {
        throw "PRE-CU x64 server is not running and healthy."
    }
    $deployedClasses = @{
        "player_jedi_conversion.class" = "/swg-precu/data/sku.0/sys.server/compiled/game/script/player/player_jedi_conversion.class"
        "gm.class" = "/swg-precu/data/sku.0/sys.server/compiled/game/script/library/gm.class"
    }
    foreach ($name in @($deployedClasses.Keys))
    {
        $output = (& docker exec $Container sha256sum ([string]$deployedClasses[$name]))
        if ($LASTEXITCODE -ne 0)
        {
            throw "Unable to hash deployed $name."
        }
        $actualHash = ([string]$output).Split(' ', [StringSplitOptions]::RemoveEmptyEntries)[0].ToLowerInvariant()
        if ($actualHash -cne [string]$contract.buildEvidence.fullJavaBuild.$name.sha256)
        {
            throw "Deployed $name hash mismatch. Expected $($contract.buildEvidence.fullJavaBuild.$name.sha256), got $actualHash."
        }
    }
}

Write-Host "Publish 14.1 Jedi conversion lifecycle retirement contract passed."
