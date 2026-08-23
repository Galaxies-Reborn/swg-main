[CmdletBinding()]
param(
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# This generator is deliberately bounded to the one additive PRE-CU table.
# It does not accept an output path and never rewrites an existing game table.
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputPath = Join-Path $root "serverdata/string/en/precu_container_droid.stf"

$entries = @(
    [pscustomobject]@{ Id = [uint32]1;  Name = "resource_crates_n";    Value = "Resource Crates" },
    [pscustomobject]@{ Id = [uint32]2;  Name = "resource_crates_d";    Value = "An account-bound datapad container for storing resource crates." },
    [pscustomobject]@{ Id = [uint32]3;  Name = "spaceship_parts_n";    Value = "Spaceship Parts" },
    [pscustomobject]@{ Id = [uint32]4;  Name = "spaceship_parts_d";    Value = "An account-bound datapad container for storing spaceship parts." },
    [pscustomobject]@{ Id = [uint32]5;  Name = "craft_components_n";   Value = "Craft Components" },
    [pscustomobject]@{ Id = [uint32]6;  Name = "craft_components_d";   Value = "An account-bound datapad container for storing crafted components." },
    [pscustomobject]@{ Id = [uint32]7;  Name = "vehicles_n";           Value = "Vehicles" },
    [pscustomobject]@{ Id = [uint32]8;  Name = "vehicles_d";           Value = "An account-bound datapad container for storing vehicle control devices." },
    [pscustomobject]@{ Id = [uint32]9;  Name = "droids_n";             Value = "Droids" },
    [pscustomobject]@{ Id = [uint32]10; Name = "droids_d";             Value = "An account-bound datapad container for storing droid control devices." },
    [pscustomobject]@{ Id = [uint32]11; Name = "worker_droid_n";       Value = "Worker Droid" },
    [pscustomobject]@{ Id = [uint32]12; Name = "worker_droid_d";       Value = "A single-use droid that remotely manages one of its owner's factories or harvesters." },
    [pscustomobject]@{ Id = [uint32]13; Name = "survey_droid_n";       Value = "Survey Droid" },
    [pscustomobject]@{ Id = [uint32]14; Name = "survey_droid_d";       Value = "A single-use droid that remotely surveys a planet and returns with a waypoint to a resource concentration of 50% or greater." }
)

function Get-Sha256([byte[]]$Bytes)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return -join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") })
    }
    finally
    {
        $sha.Dispose()
    }
}

function New-StringTableBytes
{
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new(
        $stream,
        [System.Text.Encoding]::UTF8,
        $true)
    try
    {
        # LocalizedStringTable version 1: little-endian magic/version/header,
        # id-ordered UTF-16LE values, then ordinal name-to-id records.
        $writer.Write([uint32]0xabcd)
        $writer.Write([byte]1)
        $writer.Write([uint32]($entries.Count + 1))
        $writer.Write([uint32]$entries.Count)

        foreach ($entry in $entries)
        {
            $valueBytes = [System.Text.Encoding]::Unicode.GetBytes(
                [string]$entry.Value)
            $writer.Write([uint32]$entry.Id)
            $writer.Write([uint32]::MaxValue)
            $writer.Write([uint32]([string]$entry.Value).Length)
            $writer.Write($valueBytes)
        }

        [string[]]$names = @($entries | ForEach-Object { [string]$_.Name })
        [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
        foreach ($name in $names)
        {
            $entry = $entries | Where-Object { $_.Name -ceq $name } |
                Select-Object -First 1
            $nameBytes = [System.Text.Encoding]::ASCII.GetBytes($name)
            $writer.Write([uint32]$entry.Id)
            $writer.Write([uint32]$nameBytes.Length)
            $writer.Write($nameBytes)
        }

        $writer.Flush()
        return $stream.ToArray()
    }
    finally
    {
        $writer.Dispose()
        $stream.Dispose()
    }
}

[byte[]]$expectedBytes = New-StringTableBytes
$expectedHash = Get-Sha256 $expectedBytes

if ($Check)
{
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf))
    {
        throw "Missing generated string table: $outputPath"
    }

    [byte[]]$actualBytes = [System.IO.File]::ReadAllBytes($outputPath)
    $actualHash = Get-Sha256 $actualBytes
    if ($actualBytes.Length -ne $expectedBytes.Length -or
        $actualHash -cne $expectedHash)
    {
        throw "Generated string table is stale. Expected $expectedHash, got $actualHash."
    }

    Write-Host "Verified $outputPath ($($actualBytes.Length) bytes, sha256 $actualHash)."
    return
}

[System.IO.File]::WriteAllBytes($outputPath, $expectedBytes)
Write-Host "Generated $outputPath ($($expectedBytes.Length) bytes, sha256 $expectedHash)."
