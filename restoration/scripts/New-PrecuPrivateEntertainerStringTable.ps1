[CmdletBinding()]
param(
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Deliberately bounded to this additive table. No output path is accepted and
# no stock string table can be rewritten by this generator.
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputPath = Join-Path $root `
    "serverdata/string/en/precu_private_entertainer.stf"

$entries = @(
    [pscustomobject]@{ Id = [uint32]1;  Name = "hire_private_entertainer"; Value = "Hire a Private Entertainer" },
    [pscustomobject]@{ Id = [uint32]2;  Name = "hire_title"; Value = "Private Entertainment" },
    [pscustomobject]@{ Id = [uint32]3;  Name = "hire_prompt"; Value = "Choose a private entertainer to perform in a cantina side room. Each performer remains for 30 minutes while you stay nearby." },
    [pscustomobject]@{ Id = [uint32]4;  Name = "hire_dancer"; Value = "Hire a private dancer" },
    [pscustomobject]@{ Id = [uint32]5;  Name = "hire_musician"; Value = "Hire a private musician" },
    [pscustomobject]@{ Id = [uint32]6;  Name = "hire_both"; Value = "Hire a dancer and musician" },
    [pscustomobject]@{ Id = [uint32]7;  Name = "dismiss_all"; Value = "Dismiss my private entertainers" },
    [pscustomobject]@{ Id = [uint32]8;  Name = "private_dancer_name"; Value = "Private Dancer" },
    [pscustomobject]@{ Id = [uint32]9;  Name = "private_musician_name"; Value = "Private Musician" },
    [pscustomobject]@{ Id = [uint32]10; Name = "hired_dancer"; Value = "Your private dancer is waiting in a cantina side room." },
    [pscustomobject]@{ Id = [uint32]11; Name = "hired_musician"; Value = "Your private musician is waiting in a cantina side room." },
    [pscustomobject]@{ Id = [uint32]12; Name = "already_hired_dancer"; Value = "You already have a private dancer in this cantina." },
    [pscustomobject]@{ Id = [uint32]13; Name = "already_hired_musician"; Value = "You already have a private musician in this cantina." },
    [pscustomobject]@{ Id = [uint32]14; Name = "hire_busy"; Value = "Your previous entertainer request is still being processed." },
    [pscustomobject]@{ Id = [uint32]15; Name = "no_side_room"; Value = "This cantina has no suitable side room for a private performance." },
    [pscustomobject]@{ Id = [uint32]16; Name = "hire_failed"; Value = "The bartender could not arrange a private performance." },
    [pscustomobject]@{ Id = [uint32]17; Name = "dismissed_all"; Value = "Your private entertainers have been dismissed." },
    [pscustomobject]@{ Id = [uint32]18; Name = "watch_performance"; Value = "Watch performance" },
    [pscustomobject]@{ Id = [uint32]19; Name = "listen_performance"; Value = "Listen to performance" },
    [pscustomobject]@{ Id = [uint32]20; Name = "buff_yourself"; Value = "Buff yourself" },
    [pscustomobject]@{ Id = [uint32]21; Name = "dismiss_performer"; Value = "Dismiss performer" },
    [pscustomobject]@{ Id = [uint32]22; Name = "not_your_performer"; Value = "Only the player who hired this performer may use that option." },
    [pscustomobject]@{ Id = [uint32]23; Name = "watch_started"; Value = "You begin watching your private dancer." },
    [pscustomobject]@{ Id = [uint32]24; Name = "listen_started"; Value = "You begin listening to your private musician." },
    [pscustomobject]@{ Id = [uint32]25; Name = "buff_prompt"; Value = "Select your restored PRE-CU attribute enhancement. The selected package costs 10,000 credits and is charged only after final validation." },
    [pscustomobject]@{ Id = [uint32]26; Name = "buff_dancer_option"; Value = "Dancer enhancement: +25% Mind for 120 minutes" },
    [pscustomobject]@{ Id = [uint32]27; Name = "buff_musician_option"; Value = "Musician enhancement: +25% Focus and Willpower for 120 minutes" },
    [pscustomobject]@{ Id = [uint32]28; Name = "buff_not_available"; Value = "That enhancement cannot be applied in your current state." },
    [pscustomobject]@{ Id = [uint32]29; Name = "buff_busy"; Value = "A previous private entertainer payment is still being resolved." },
    [pscustomobject]@{ Id = [uint32]30; Name = "insufficient_funds"; Value = "You need 10,000 credits in cash or bank to purchase this enhancement." },
    [pscustomobject]@{ Id = [uint32]31; Name = "payment_unavailable"; Value = "The 10,000-credit payment could not be dispatched. No enhancement was applied." },
    [pscustomobject]@{ Id = [uint32]32; Name = "buff_applied_dancer"; Value = "Your dancer enhancement has been applied for 10,000 credits." },
    [pscustomobject]@{ Id = [uint32]33; Name = "buff_applied_musician"; Value = "Your musician enhancement has been applied for 10,000 credits." },
    [pscustomobject]@{ Id = [uint32]34; Name = "buff_refunded"; Value = "The enhancement could not be applied, so your 10,000 credits were refunded." },
    [pscustomobject]@{ Id = [uint32]35; Name = "late_payment_refunded"; Value = "A late private entertainer payment response was refunded without applying an enhancement." },
    [pscustomobject]@{ Id = [uint32]36; Name = "refund_failed"; Value = "Your private entertainer refund is being retried. Customer Service has been notified." },
    [pscustomobject]@{ Id = [uint32]37; Name = "performer_expired"; Value = "Your private entertainer's engagement has ended." },
    [pscustomobject]@{ Id = [uint32]38; Name = "payment_timeout"; Value = "The private entertainer payment timed out. Any late successful debit will be refunded automatically." }
)

function Get-Sha256([byte[]]$Bytes)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return -join ($sha.ComputeHash($Bytes) |
            ForEach-Object { $_.ToString("x2") })
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

        [string[]]$names = @(
            $entries | ForEach-Object { [string]$_.Name })
        [System.Array]::Sort(
            $names,
            [System.StringComparer]::Ordinal)
        foreach ($name in $names)
        {
            $entry = $entries |
                Where-Object { $_.Name -ceq $name } |
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
