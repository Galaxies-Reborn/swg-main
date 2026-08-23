[CmdletBinding()]
param(
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Bounded, deterministic generator for the additive Elder/apprenticeship UI.
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputPath = Join-Path $root "serverdata/string/en/precu_elder.stf"

$entries = @(
    [pscustomobject]@{ Id = [uint32]1; Name = "train_elder_skills"; Value = "Train elder skills" },
    [pscustomobject]@{ Id = [uint32]2; Name = "elder_training_title"; Value = "Train Elder Skills" },
    [pscustomobject]@{ Id = [uint32]3; Name = "requires_master"; Value = "You must own this profession's Master skill box before training its Elder box." },
    [pscustomobject]@{ Id = [uint32]4; Name = "trainer_too_far"; Value = "You must remain near the profession trainer." },
    [pscustomobject]@{ Id = [uint32]5; Name = "insufficient_apprenticeship_xp"; Value = "You do not have enough apprenticeship experience." },
    [pscustomobject]@{ Id = [uint32]6; Name = "elder_trained"; Value = "Elder skill trained. It will reset 30 days from now." },
    [pscustomobject]@{ Id = [uint32]7; Name = "elder_renewed"; Value = "Elder skill renewed. Its 30-day duration now starts again." },
    [pscustomobject]@{ Id = [uint32]8; Name = "elder_training_failed"; Value = "Elder skill training could not be completed." },
    [pscustomobject]@{ Id = [uint32]9; Name = "elder_expired"; Value = "An Elder skill has reached its 30-day reset and was removed." },
    [pscustomobject]@{ Id = [uint32]10; Name = "rifleman_n"; Value = "Rifleman" },
    [pscustomobject]@{ Id = [uint32]11; Name = "pistoleer_n"; Value = "Pistoleer" },
    [pscustomobject]@{ Id = [uint32]12; Name = "carbineer_n"; Value = "Carbineer" },
    [pscustomobject]@{ Id = [uint32]13; Name = "teras_kasi_artist_n"; Value = "Teras Kasi Artist" },
    [pscustomobject]@{ Id = [uint32]14; Name = "fencer_n"; Value = "Fencer" },
    [pscustomobject]@{ Id = [uint32]15; Name = "swordsman_n"; Value = "Swordsman" },
    [pscustomobject]@{ Id = [uint32]16; Name = "pikeman_n"; Value = "Pikeman" },
    [pscustomobject]@{ Id = [uint32]17; Name = "bounty_hunter_n"; Value = "Bounty Hunter" },
    [pscustomobject]@{ Id = [uint32]18; Name = "commando_n"; Value = "Commando" },
    [pscustomobject]@{ Id = [uint32]19; Name = "smuggler_n"; Value = "Smuggler" },
    [pscustomobject]@{ Id = [uint32]20; Name = "squad_leader_n"; Value = "Squad Leader" },
    [pscustomobject]@{ Id = [uint32]21; Name = "doctor_n"; Value = "Doctor" },
    [pscustomobject]@{ Id = [uint32]22; Name = "combat_medic_n"; Value = "Combat Medic" },
    [pscustomobject]@{ Id = [uint32]23; Name = "ranger_n"; Value = "Ranger" },
    [pscustomobject]@{ Id = [uint32]24; Name = "creature_handler_n"; Value = "Creature Handler" },
    [pscustomobject]@{ Id = [uint32]25; Name = "bio_engineer_n"; Value = "Bio-Engineer" },
    [pscustomobject]@{ Id = [uint32]26; Name = "architect_n"; Value = "Architect" },
    [pscustomobject]@{ Id = [uint32]27; Name = "armorsmith_n"; Value = "Armorsmith" },
    [pscustomobject]@{ Id = [uint32]28; Name = "weaponsmith_n"; Value = "Weaponsmith" },
    [pscustomobject]@{ Id = [uint32]29; Name = "chef_n"; Value = "Chef" },
    [pscustomobject]@{ Id = [uint32]30; Name = "tailor_n"; Value = "Tailor" },
    [pscustomobject]@{ Id = [uint32]31; Name = "droid_engineer_n"; Value = "Droid Engineer" },
    [pscustomobject]@{ Id = [uint32]32; Name = "merchant_n"; Value = "Merchant" },
    [pscustomobject]@{ Id = [uint32]33; Name = "shipwright_n"; Value = "Shipwright" },
    [pscustomobject]@{ Id = [uint32]34; Name = "dancer_n"; Value = "Dancer" },
    [pscustomobject]@{ Id = [uint32]35; Name = "musician_n"; Value = "Musician" },
    [pscustomobject]@{ Id = [uint32]36; Name = "image_designer_n"; Value = "Image Designer" },
    [pscustomobject]@{ Id = [uint32]37; Name = "elder_training_prompt"; Value = "Train this profession's Elder skill box for 100 apprenticeship XP? It costs zero skill points and resets 30 days after training." },
    [pscustomobject]@{ Id = [uint32]38; Name = "elder_renewal_prompt"; Value = "Renew this profession's Elder skill box for 100 apprenticeship XP? Its 30-day duration will restart now." },
    [pscustomobject]@{ Id = [uint32]39; Name = "politician_n"; Value = "Politician" }
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
            [byte[]]$valueBytes = [System.Text.Encoding]::Unicode.GetBytes(
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
            [byte[]]$nameBytes = [System.Text.Encoding]::ASCII.GetBytes($name)
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
