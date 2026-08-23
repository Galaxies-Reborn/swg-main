[CmdletBinding()]
param(
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Deliberately bounded to this one additive table. No output path is accepted,
# so the generator cannot overwrite a stock localized-string table.
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputPath = Join-Path $root "serverdata/string/en/precu_hire_merc.stf"

$entries = @(
    [pscustomobject]@{ Id = [uint32]1;  Name = "hire_merc"; Value = "Hire a Merc" },
    [pscustomobject]@{ Id = [uint32]2;  Name = "hire_merc_title"; Value = "Hire a Merc" },
    [pscustomobject]@{ Id = [uint32]3;  Name = "hire_merc_prompt"; Value = "Choose a combat mercenary. Every offer is scaled to your combat level and costs %DI credits." },
    [pscustomobject]@{ Id = [uint32]4;  Name = "roster_entry"; Value = "%TT - combat level %DI" },
    [pscustomobject]@{ Id = [uint32]5;  Name = "already_hired"; Value = "You already have an active mercenary." },
    [pscustomobject]@{ Id = [uint32]6;  Name = "payment_pending"; Value = "Your previous mercenary payment is still being resolved. Late callbacks remain locked to that request." },
    [pscustomobject]@{ Id = [uint32]7;  Name = "group_full"; Value = "Your party has no room for another member." },
    [pscustomobject]@{ Id = [uint32]8;  Name = "invalid_selection"; Value = "That mercenary offer is no longer available." },
    [pscustomobject]@{ Id = [uint32]9;  Name = "out_of_range"; Value = "Move closer to the combat mission terminal to hire a mercenary." },
    [pscustomobject]@{ Id = [uint32]10; Name = "payment_failed"; Value = "You do not have enough credits to hire that mercenary." },
    [pscustomobject]@{ Id = [uint32]11; Name = "spawn_failed_refund"; Value = "The mercenary could not join your party. Your payment is being refunded." },
    [pscustomobject]@{ Id = [uint32]12; Name = "refund_failed"; Value = "Your mercenary refund is being retried. Customer Service has been notified." },
    [pscustomobject]@{ Id = [uint32]13; Name = "hired"; Value = "%TO has joined your party." },
    [pscustomobject]@{ Id = [uint32]14; Name = "dismiss_merc"; Value = "Dismiss Mercenary" },
    [pscustomobject]@{ Id = [uint32]15; Name = "dismissed"; Value = "Your mercenary has been dismissed." },
    [pscustomobject]@{ Id = [uint32]16; Name = "expired"; Value = "Your mercenary's two-hour contract has ended." },
    [pscustomobject]@{ Id = [uint32]17; Name = "party_lost"; Value = "Your mercenary could not remain in your party and has departed." },
    [pscustomobject]@{ Id = [uint32]18; Name = "archetype_novice_brawler"; Value = "Novice Brawler" },
    [pscustomobject]@{ Id = [uint32]19; Name = "archetype_novice_marksman"; Value = "Novice Marksman" },
    [pscustomobject]@{ Id = [uint32]20; Name = "archetype_novice_medic"; Value = "Novice Medic" },
    [pscustomobject]@{ Id = [uint32]21; Name = "archetype_bounty_hunter"; Value = "Bounty Hunter" },
    [pscustomobject]@{ Id = [uint32]22; Name = "archetype_carbineer"; Value = "Carbineer" },
    [pscustomobject]@{ Id = [uint32]23; Name = "archetype_combat_medic"; Value = "Combat Medic" },
    [pscustomobject]@{ Id = [uint32]24; Name = "archetype_commando"; Value = "Commando" },
    [pscustomobject]@{ Id = [uint32]25; Name = "archetype_creature_handler"; Value = "Creature Handler" },
    [pscustomobject]@{ Id = [uint32]26; Name = "archetype_doctor"; Value = "Doctor" },
    [pscustomobject]@{ Id = [uint32]27; Name = "archetype_fencer"; Value = "Fencer" },
    [pscustomobject]@{ Id = [uint32]28; Name = "archetype_pikeman"; Value = "Pikeman" },
    [pscustomobject]@{ Id = [uint32]29; Name = "archetype_pistoleer"; Value = "Pistoleer" },
    [pscustomobject]@{ Id = [uint32]30; Name = "archetype_rifleman"; Value = "Rifleman" },
    [pscustomobject]@{ Id = [uint32]31; Name = "archetype_ranger"; Value = "Ranger" },
    [pscustomobject]@{ Id = [uint32]32; Name = "archetype_smuggler"; Value = "Smuggler" },
    [pscustomobject]@{ Id = [uint32]33; Name = "archetype_squad_leader"; Value = "Squad Leader" },
    [pscustomobject]@{ Id = [uint32]34; Name = "archetype_swordsman"; Value = "Swordsman" },
    [pscustomobject]@{ Id = [uint32]35; Name = "archetype_teras_kasi_artist"; Value = "Teras Kasi Artist" }
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
        [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
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
