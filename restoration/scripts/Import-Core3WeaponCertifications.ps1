[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Core3Root,

    [string]$ServerRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,

    [string]$ExpectedCore3Commit = "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8",

    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-Core3WeaponCertificationRows {
    param([Parameter(Mandatory = $true)][string]$WeaponScriptRoot)

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $WeaponScriptRoot -Recurse -File -Filter "*.lua") {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $templateMatch = [regex]::Match(
            $text,
            'ObjectTemplates:addTemplate\([^,]+,\s*"(?<template>object/weapon/[^"]+\.iff)"\s*\)'
        )
        $certificationMatch = [regex]::Match(
            $text,
            'certificationsRequired\s*=\s*\{(?<certifications>[^}]*)\}',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        if (-not $templateMatch.Success -or -not $certificationMatch.Success) {
            continue
        }

        $certifications = @(
            [regex]::Matches($certificationMatch.Groups["certifications"].Value, '"([^"]+)"') |
                ForEach-Object { $_.Groups[1].Value }
        )
        if ($certifications.Count -eq 0) {
            continue
        }

        $templateName = $templateMatch.Groups["template"].Value
        $slash = $templateName.LastIndexOf("/")
        $sharedTemplate = (
            $templateName.Substring(0, $slash + 1) +
            "shared_" +
            $templateName.Substring($slash + 1)
        ) -replace '\.iff$', '.tpf'

        $rows.Add([pscustomobject]@{
            Core3Path = $file.FullName
            Template = $templateName
            SharedTemplate = $sharedTemplate
            Certifications = $certifications
        })
    }

    return @($rows | Sort-Object SharedTemplate)
}

function Get-ExpectedTemplateText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Certifications,
        [Parameter(Mandatory = $true)][string]$TemplatePath
    )

    $lineEnding = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $certificationLine = 'certificationsRequired = [' +
        (($Certifications | ForEach-Object { '"' + $_ + '"' }) -join ", ") +
        ']'
    $classPattern =
        '(?m)^@class tangible_object_template (?<version>[0-9]+)[ \t]*(?=\r?$)'
    $classMatch = [regex]::Match($Text, $classPattern)
    if (-not $classMatch.Success) {
        throw "No tangible_object_template class declaration found in $TemplatePath"
    }

    # certificationsRequired entered the shared tangible template schema at
    # version 8. Many ground weapon TPFs still declare older class revisions;
    # setting the field under those revisions makes TemplateCompiler emit
    # "cannot find parameter certificationsRequired" while Ant continues.
    # Promote only this inherited class layer and preserve all versions newer
    # than the minimum.
    if ([int]$classMatch.Groups["version"].Value -lt 8) {
        $Text = $Text.Substring(0, $classMatch.Index) +
            "@class tangible_object_template 8" +
            $Text.Substring($classMatch.Index + $classMatch.Length)
        $classMatch = [regex]::Match($Text, $classPattern)
    }

    $existing = [regex]::Matches(
        $Text,
        '(?m)^[ \t]*certificationsRequired[ \t]*=.*(?:\r?\n|$)'
    )
    if ($existing.Count -gt 1) {
        throw "Multiple certificationsRequired declarations found in $TemplatePath"
    }

    if ($existing.Count -eq 1) {
        return [regex]::Replace(
            $Text,
            '(?m)^[ \t]*certificationsRequired[ \t]*=.*?(?=\r?$)',
            $certificationLine,
            1
        )
    }

    return $Text.Insert(
        $classMatch.Index + $classMatch.Length,
        $lineEnding + $certificationLine
    )
}

$core3RootPath = Get-NormalizedPath -Path $Core3Root
$serverRootPath = Get-NormalizedPath -Path $ServerRoot
$weaponScriptRoot = Join-Path $core3RootPath "MMOCoreORB\bin\scripts\object\weapon"
$sharedTemplateRoot = Join-Path $serverRootPath "dsrc\sku.0\sys.shared\compiled\game"

if (-not (Test-Path -LiteralPath $weaponScriptRoot -PathType Container)) {
    throw "Core3 weapon-script root does not exist: $weaponScriptRoot"
}
if (-not (Test-Path -LiteralPath $sharedTemplateRoot -PathType Container)) {
    throw "SWGSource shared-template root does not exist: $sharedTemplateRoot"
}

$actualCommit = (& git -C $core3RootPath rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve the Core3 source commit at $core3RootPath"
}
if ($actualCommit -cne $ExpectedCore3Commit) {
    throw "Core3 commit mismatch: expected $ExpectedCore3Commit, found $actualCommit"
}

$rows = Get-Core3WeaponCertificationRows -WeaponScriptRoot $weaponScriptRoot
$matched = 0
$missing = [System.Collections.Generic.List[string]]::new()
$changed = [System.Collections.Generic.List[string]]::new()

foreach ($row in $rows) {
    $relativePath = $row.SharedTemplate.Replace("/", "\")
    $targetPath = Join-Path $sharedTemplateRoot $relativePath
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        $missing.Add($row.SharedTemplate)
        continue
    }

    $matched++
    $current = Get-Content -LiteralPath $targetPath -Raw
    $expected = Get-ExpectedTemplateText `
        -Text $current `
        -Certifications $row.Certifications `
        -TemplatePath $targetPath

    if ($current -cne $expected) {
        $changed.Add($row.SharedTemplate)
        if ($Apply) {
            [System.IO.File]::WriteAllText(
                $targetPath,
                $expected,
                [System.Text.UTF8Encoding]::new($false)
            )
        }
    }
}

$mode = if ($Apply) { "apply" } else { "validate" }
Write-Output (
    "Core3 weapon certification import: mode={0} commit={1} mapped={2} matched={3} missing={4} changed={5}" -f
        $mode,
        $actualCommit,
        $rows.Count,
        $matched,
        $missing.Count,
        $changed.Count
)

if ($missing.Count -gt 0) {
    Write-Output "Core3 templates absent from this SWGSource baseline:"
    $missing | ForEach-Object { Write-Output "  $_" }
}

if (-not $Apply -and $changed.Count -gt 0) {
    Write-Output "Templates requiring import:"
    $changed | ForEach-Object { Write-Output "  $_" }
    exit 2
}
