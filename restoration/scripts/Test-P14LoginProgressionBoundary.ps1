param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Build", "Ready")]
    [string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14LoginProgressionBoundary)) -Raw | ConvertFrom-Json
$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$basePlayerPath = Join-Path $resolvedRoot ([string]$contract.sourceFiles.playerInitialization)

if (-not (Test-Path -LiteralPath $basePlayerPath -PathType Leaf))
{
    throw "Required source file is missing: $basePlayerPath"
}

$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw

function Get-Section([string]$Text, [string]$Start, [string]$End)
{
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0)
    {
        throw "Missing section start: $Start"
    }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($endIndex -lt 0)
    {
        throw "Missing section end: $End"
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message)
{
    if (-not $Text.Contains($Needle))
    {
        throw $Message
    }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message)
{
    if ($Text.Contains($Needle))
    {
        throw $Message
    }
}

$onInitialize = Get-Section $basePlayer `
    "public int OnInitialize(obj_id self)" `
    "public int OnLogin(obj_id self)"

Assert-NotContains $onInitialize 'grantSkill(self, "class_trader")' "Normal login still grants the NGE class_trader pseudo-skill."
Assert-NotContains $onInitialize "respecNewEntertainerSkills(self);" "Normal login still invokes the NGE entertainer respec."
Assert-NotContains $onInitialize "respecNewCrafterSkills(self);" "Normal login still invokes the NGE crafter respec."
Assert-NotContains $onInitialize 'hasSkill(self, "jedi_padawan_novice")' "Normal login still treats the Pre-CU Jedi novice skill as an NGE conversion trigger."
Assert-NotContains $onInitialize "setSkillTemplate(self," "Normal login still mutates the retired NGE skill template."
Assert-NotContains $onInitialize 'attachScript(self, "player.player_jedi_conversion")' "Normal login still attaches the NGE Jedi conversion script."

Assert-Contains $basePlayer "public void respecNewEntertainerSkills(obj_id self)" "The historical entertainer conversion helper was removed instead of being isolated."
Assert-Contains $basePlayer "public void respecNewCrafterSkills(obj_id self)" "The historical crafter conversion helper was removed instead of being isolated."
Assert-NotContains $basePlayer 'characterData.put("skillTemplate"' "CTS still serializes the retired NGE skill template."
Assert-NotContains $basePlayer 'characterData.put("workingSkill"' "CTS still serializes the retired NGE working skill."
Assert-Contains $basePlayer 'characterData.put("skills", getSkillListingForPlayer(self));' "CTS no longer serializes authoritative PRE-CU skill-box ownership."
Assert-Contains $basePlayer 'groundquests.reattachQuestScripts(self);' "CTS no longer reattaches retained expansion quest scripts."

$actualSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $basePlayerPath).Hash.ToLowerInvariant()
if ($actualSourceHash -cne [string]$contract.buildEvidence.sourceSha256."base_player.java")
{
    throw "base_player.java hash mismatch. Expected $($contract.buildEvidence.sourceSha256.'base_player.java'), got $actualSourceHash."
}

if ($Expectation -eq "Ready")
{
    if ([string]$contract.status -cne "ready" -or [string]$contract.runtimeEvidence.result -cne "passed")
    {
        throw "The login progression boundary does not yet contain passed runtime evidence."
    }
    $patchPath = Join-Path $restorationRoot ([string]$contract.buildEvidence.overlayPatch -replace "^restoration/", "")
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $patchPath).Length -ne [long]$contract.buildEvidence.overlayPatchBytes -or
        $patchHash -cne [string]$contract.buildEvidence.overlayPatchSha256)
    {
        throw "The login progression boundary overlay patch does not match its locked evidence."
    }
}

Write-Host "Publish 14.1 login progression boundary contract passed."
