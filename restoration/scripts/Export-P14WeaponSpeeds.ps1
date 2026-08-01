[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Core3Root,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$expectedCommit = "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8"
$core3 = (Resolve-Path -LiteralPath $Core3Root).Path
$actualCommit = (& git -C $core3 rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -cne $expectedCommit)
{
    throw "Core3 source must be pinned at $expectedCommit; found '$actualCommit'."
}

$weaponRoot = Join-Path $core3 "MMOCoreORB/bin/scripts/object/weapon"
if (-not (Test-Path -LiteralPath $weaponRoot -PathType Container))
{
    throw "Core3 weapon template root was not found: $weaponRoot"
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $weaponRoot -Recurse -File -Filter "*.lua")
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $templateMatch = [regex]::Match(
        $text,
        'ObjectTemplates:addTemplate\([^,]+,\s*"([^"]+)"\s*\)')
    $speedMatch = [regex]::Match(
        $text,
        '(?m)^\s*attackSpeed\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*,')
    if (-not $templateMatch.Success -or -not $speedMatch.Success)
    {
        continue
    }

    $speed = [double]::Parse(
        $speedMatch.Groups[1].Value,
        [Globalization.CultureInfo]::InvariantCulture)
    if ($speed -le 0.0)
    {
        continue
    }

    $rows.Add([pscustomobject]@{
        Template = $templateMatch.Groups[1].Value
        Speed = $speed
    })
}

$orderedRows = @($rows | Sort-Object Template -Unique)
if ($orderedRows.Count -ne 342)
{
    throw "Expected 342 positive, unique Core3 weapon speeds; found $($orderedRows.Count)."
}

$familyFallbacks = [ordered]@{
    "__family_default" = 4.0
    "__family_rifle" = 5.9
    "__family_carbine" = 3.6
    "__family_pistol" = 3.6
    "__family_heavy" = 7.8
    "__family_onehandmelee" = 4.5
    "__family_twohandmelee" = 4.8
    "__family_unarmed" = 2.0
    "__family_polearm" = 5.1
    "__family_thrown" = 5.0
    "__family_onehandlightsaber" = 4.5
    "__family_twohandlightsaber" = 4.8
    "__family_polearmlightsaber" = 5.1
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("templateName`tattackSpeed")
$lines.Add("s`tf")
foreach ($entry in $familyFallbacks.GetEnumerator())
{
    $lines.Add("$($entry.Key)`t$(([double]$entry.Value).ToString('0.0###', [Globalization.CultureInfo]::InvariantCulture))")
}
foreach ($row in $orderedRows)
{
    $lines.Add("$($row.Template)`t$($row.Speed.ToString('0.0###', [Globalization.CultureInfo]::InvariantCulture))")
}

$output = [IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent -PathType Container))
{
    New-Item -ItemType Directory -Path $outputParent | Out-Null
}
[IO.File]::WriteAllLines($output, $lines, [Text.UTF8Encoding]::new($false))

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()
Write-Host "PRE-CU weapon speed table exported."
Write-Host "  Core3: $actualCommit"
Write-Host "  exact rows: $($orderedRows.Count)"
Write-Host "  family fallbacks: $($familyFallbacks.Count)"
Write-Host "  SHA-256: $hash"
Write-Host "  output: $output"
