[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Core3Root,

    [Parameter(Mandatory = $true)]
    [string]$CreatureTable,

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

$mobileRoot = Join-Path $core3 "MMOCoreORB/bin/scripts/mobile"
if (-not (Test-Path -LiteralPath $mobileRoot -PathType Container))
{
    throw "Core3 mobile template root was not found: $mobileRoot"
}

$creatureTablePath = (Resolve-Path -LiteralPath $CreatureTable).Path
$creatureLines = @(Get-Content -LiteralPath $creatureTablePath)
if ($creatureLines.Count -lt 3)
{
    throw "Creature table is incomplete: $creatureTablePath"
}
$creatureHeaders = @($creatureLines[0] -split "`t")
$currentCreatures = @(
    $creatureLines |
        Select-Object -Skip 2 |
        ConvertFrom-Csv -Delimiter "`t" -Header $creatureHeaders)

function Read-NumericField
{
    param([string]$Text, [string]$Field)

    $match = [regex]::Match(
        $Text,
        "(?m)^\s*$Field\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)\s*,")
    if (-not $match.Success)
    {
        return $null
    }
    return [double]::Parse(
        $match.Groups[1].Value,
        [Globalization.CultureInfo]::InvariantCulture)
}

function Read-ResistFields
{
    param([string]$Text)

    $match = [regex]::Match(
        $Text,
        '(?ms)^\s*resists\s*=\s*\{([^}]*)\}\s*,')
    if (-not $match.Success)
    {
        return $null
    }

    $values = @(
        $match.Groups[1].Value -split ',' |
            ForEach-Object {
                [double]::Parse(
                    $_.Trim(),
                    [Globalization.CultureInfo]::InvariantCulture)
            })
    if ($values.Count -ne 9)
    {
        return $null
    }

    return [pscustomobject][ordered]@{
        resistKinetic = $values[0]
        resistEnergy = $values[1]
        resistBlast = $values[2]
        resistHeat = $values[3]
        resistCold = $values[4]
        resistElectric = $values[5]
        resistAcid = $values[6]
        resistStun = $values[7]
        resistLightsaber = $values[8]
    }
}

function Convert-Core3ResistForMitigation
{
    param([double]$Value)

    # Core3 encodes special protection as 100 + protection. The special bit is
    # presentation metadata; combat uses the value after subtracting 100.
    if ($Value -gt 100.0)
    {
        return $Value - 100.0
    }
    return $Value
}

function Get-LowerMedian
{
    param([double[]]$Values)

    $ordered = @($Values | Sort-Object)
    if ($ordered.Count -eq 0)
    {
        throw "Cannot calculate a median for an empty value set."
    }
    return [double]$ordered[[int](($ordered.Count - 1) / 2)]
}

function Get-NormalizedCreatureKey
{
    param([string]$Key)

    $normalized = $Key.ToLowerInvariant().Replace("womprat", "womp_rat")
    $tokens = @($normalized -split "_" | Where-Object { $_ -ne "" } | Sort-Object)
    return $tokens -join "_"
}

$profileFields = @(
    "level",
    "chanceHit",
    "damageMin",
    "damageMax",
    "baseXp",
    "baseHAM",
    "baseHAMmax",
    "armor")
$resistFields = @(
    "resistKinetic",
    "resistEnergy",
    "resistBlast",
    "resistHeat",
    "resistCold",
    "resistElectric",
    "resistAcid",
    "resistStun",
    "resistLightsaber")
$allProfileFields = @($profileFields + $resistFields)
$profiles = @{}
foreach ($file in Get-ChildItem -LiteralPath $mobileRoot -Recurse -File -Filter "*.lua")
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $keyMatch = [regex]::Match(
        $text,
        'CreatureTemplates:addCreatureTemplate\s*\([^,]+,\s*"([^"]+)"\s*\)')
    if (-not $keyMatch.Success)
    {
        continue
    }

    $values = [ordered]@{
        creatureName = $keyMatch.Groups[1].Value
        sourceKey = $keyMatch.Groups[1].Value
    }
    $complete = $true
    foreach ($field in $profileFields)
    {
        $value = Read-NumericField -Text $text -Field $field
        if ($null -eq $value)
        {
            $complete = $false
            break
        }
        $values[$field] = $value
    }
    if (-not $complete)
    {
        continue
    }

    $resists = Read-ResistFields -Text $text
    if ($null -eq $resists)
    {
        continue
    }
    foreach ($field in $resistFields)
    {
        $values[$field] = [double]$resists.$field
    }

    $key = [string]$values.creatureName
    if ($profiles.ContainsKey($key))
    {
        $existing = $profiles[$key]
        $same = $true
        foreach ($field in $allProfileFields)
        {
            if ([double]$existing.$field -ne [double]$values[$field])
            {
                $same = $false
                break
            }
        }
        if (-not $same)
        {
            throw "Conflicting Core3 creature profile key '$key'."
        }
        continue
    }
    $profiles[$key] = [pscustomobject]$values
}

if ($profiles.Count -ne 3622)
{
    throw "Expected 3622 unique complete Core3 creature profiles; found $($profiles.Count)."
}

$normalizedCore3 = @{}
foreach ($key in $profiles.Keys)
{
    $normalized = Get-NormalizedCreatureKey -Key $key
    if (-not $normalizedCore3.ContainsKey($normalized))
    {
        $normalizedCore3[$normalized] = [System.Collections.Generic.List[string]]::new()
    }
    $normalizedCore3[$normalized].Add($key)
}

$manualAliases = @{
    "kreetle_over" = "overkreetle"
    "kreetle_swarming" = "kreetle_swarmling"
}
$aliases = @{}
foreach ($creature in $currentCreatures)
{
    $name = [string]$creature.creatureName
    if ($profiles.ContainsKey($name))
    {
        continue
    }

    $sourceKey = $null
    if ($manualAliases.ContainsKey($name))
    {
        $sourceKey = [string]$manualAliases[$name]
    }
    else
    {
        $normalized = Get-NormalizedCreatureKey -Key $name
        if ($normalizedCore3.ContainsKey($normalized) -and
            $normalizedCore3[$normalized].Count -eq 1)
        {
            $sourceKey = [string]$normalizedCore3[$normalized][0]
        }
    }

    if ($null -ne $sourceKey -and $profiles.ContainsKey($sourceKey))
    {
        $source = $profiles[$sourceKey]
        $aliases[$name] = [pscustomobject][ordered]@{
            creatureName = $name
            sourceKey = $sourceKey
            level = [double]$source.level
            chanceHit = [double]$source.chanceHit
            damageMin = [double]$source.damageMin
            damageMax = [double]$source.damageMax
            baseXp = [double]$source.baseXp
            baseHAM = [double]$source.baseHAM
            baseHAMmax = [double]$source.baseHAMmax
            armor = [double]$source.armor
            resistKinetic = [double]$source.resistKinetic
            resistEnergy = [double]$source.resistEnergy
            resistBlast = [double]$source.resistBlast
            resistHeat = [double]$source.resistHeat
            resistCold = [double]$source.resistCold
            resistElectric = [double]$source.resistElectric
            resistAcid = [double]$source.resistAcid
            resistStun = [double]$source.resistStun
            resistLightsaber = [double]$source.resistLightsaber
        }
    }
}

$safeProfiles = @(
    $profiles.Values |
        Where-Object {
            [int]$_.level -gt 0 -and
            [double]$_.chanceHit -gt 0.0 -and
            [double]$_.chanceHit -le 2.0 -and
            [double]$_.damageMin -le [Math]::Max(100.0, ([double]$_.level * 20.0) + 100.0)
        })
$levelMedians = @{}
foreach ($group in $safeProfiles | Group-Object { [int]$_.level })
{
    $level = [int]$group.Name
    $levelMedians[$level] = [pscustomobject][ordered]@{
        creatureName = "__level_$level"
        sourceKey = "__core3_level_median"
        level = [double]$level
        chanceHit = Get-LowerMedian -Values @($group.Group | ForEach-Object { [double]$_.chanceHit })
        damageMin = Get-LowerMedian -Values @($group.Group | ForEach-Object { [double]$_.damageMin })
        damageMax = Get-LowerMedian -Values @($group.Group | ForEach-Object { [double]$_.damageMax })
        baseXp = Get-LowerMedian -Values @($group.Group | ForEach-Object { [double]$_.baseXp })
        baseHAM = Get-LowerMedian -Values @($group.Group | ForEach-Object { [double]$_.baseHAM })
        baseHAMmax = Get-LowerMedian -Values @($group.Group | ForEach-Object { [double]$_.baseHAMmax })
        armor = Get-LowerMedian -Values @($group.Group | ForEach-Object { [double]$_.armor })
        resistKinetic = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistKinetic) })
        resistEnergy = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistEnergy) })
        resistBlast = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistBlast) })
        resistHeat = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistHeat) })
        resistCold = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistCold) })
        resistElectric = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistElectric) })
        resistAcid = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistAcid) })
        resistStun = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistStun) })
        resistLightsaber = Get-LowerMedian -Values @($group.Group | ForEach-Object { Convert-Core3ResistForMitigation -Value ([double]$_.resistLightsaber) })
    }
}

$knownLevels = @($levelMedians.Keys | Sort-Object)
if ($knownLevels.Count -lt 100 -or $knownLevels[0] -ne 1)
{
    throw "Core3 fallback profile coverage is unexpectedly sparse."
}

$fallbacks = @{}
for ($level = 1; $level -le 500; $level++)
{
    if ($levelMedians.ContainsKey($level))
    {
        $fallbacks[$level] = $levelMedians[$level]
        continue
    }

    $lower = @($knownLevels | Where-Object { $_ -lt $level } | Select-Object -Last 1)
    $upper = @($knownLevels | Where-Object { $_ -gt $level } | Select-Object -First 1)
    if ($lower.Count -gt 0 -and $upper.Count -gt 0)
    {
        $lowerLevel = [int]$lower[0]
        $upperLevel = [int]$upper[0]
        $low = $levelMedians[$lowerLevel]
        $high = $levelMedians[$upperLevel]
        $ratio = ([double]$level - $lowerLevel) / ($upperLevel - $lowerLevel)
        $row = [ordered]@{
            creatureName = "__level_$level"
            sourceKey = "__core3_level_interpolation"
            level = [double]$level
        }
        foreach ($field in $allProfileFields | Where-Object { $_ -ne "level" })
        {
            $row[$field] = [double]$low.$field + (([double]$high.$field - [double]$low.$field) * $ratio)
        }
        $fallbacks[$level] = [pscustomobject]$row
        continue
    }

    $nearestLevel = if ($lower.Count -gt 0) { [int]$lower[0] } else { [int]$upper[0] }
    $nearest = $levelMedians[$nearestLevel]
    $scale = [double]$level / [Math]::Max(1.0, [double]$nearestLevel)
    $fallbacks[$level] = [pscustomobject][ordered]@{
        creatureName = "__level_$level"
        sourceKey = "__core3_level_scaled"
        level = [double]$level
        chanceHit = [double]$nearest.chanceHit
        damageMin = [double]$nearest.damageMin * $scale
        damageMax = [double]$nearest.damageMax * $scale
        baseXp = [double]$nearest.baseXp * $scale
        baseHAM = [double]$nearest.baseHAM * $scale
        baseHAMmax = [double]$nearest.baseHAMmax * $scale
        armor = [double]$nearest.armor
        resistKinetic = [double]$nearest.resistKinetic
        resistEnergy = [double]$nearest.resistEnergy
        resistBlast = [double]$nearest.resistBlast
        resistHeat = [double]$nearest.resistHeat
        resistCold = [double]$nearest.resistCold
        resistElectric = [double]$nearest.resistElectric
        resistAcid = [double]$nearest.resistAcid
        resistStun = [double]$nearest.resistStun
        resistLightsaber = [double]$nearest.resistLightsaber
    }
}

function Format-Integer
{
    param([double]$Value)
    return ([Math]::Round($Value)).ToString([Globalization.CultureInfo]::InvariantCulture)
}

function Format-Float
{
    param([double]$Value)
    return $Value.ToString("0.0###", [Globalization.CultureInfo]::InvariantCulture)
}

$allRows = [System.Collections.Generic.List[object]]::new()
foreach ($row in $profiles.Values | Sort-Object creatureName)
{
    $allRows.Add($row)
}
foreach ($row in $aliases.Values | Sort-Object creatureName)
{
    $allRows.Add($row)
}
for ($level = 1; $level -le 500; $level++)
{
    $allRows.Add($fallbacks[$level])
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("creatureName`tsourceKey`tlevel`tchanceHit`tdamageMin`tdamageMax`tbaseXp`tbaseHAM`tbaseHAMmax`tarmor`tresistKinetic`tresistEnergy`tresistBlast`tresistHeat`tresistCold`tresistElectric`tresistAcid`tresistStun`tresistLightsaber")
$lines.Add("s`ts`ti`tf`ti`ti`ti`ti`ti`ti`ti`ti`ti`ti`ti`ti`ti`ti`ti")
foreach ($row in $allRows)
{
    $lines.Add((@(
        [string]$row.creatureName,
        [string]$row.sourceKey,
        (Format-Integer -Value ([double]$row.level)),
        (Format-Float -Value ([double]$row.chanceHit)),
        (Format-Integer -Value ([double]$row.damageMin)),
        (Format-Integer -Value ([double]$row.damageMax)),
        (Format-Integer -Value ([double]$row.baseXp)),
        (Format-Integer -Value ([double]$row.baseHAM)),
        (Format-Integer -Value ([double]$row.baseHAMmax)),
        (Format-Integer -Value ([double]$row.armor)),
        (Format-Integer -Value ([double]$row.resistKinetic)),
        (Format-Integer -Value ([double]$row.resistEnergy)),
        (Format-Integer -Value ([double]$row.resistBlast)),
        (Format-Integer -Value ([double]$row.resistHeat)),
        (Format-Integer -Value ([double]$row.resistCold)),
        (Format-Integer -Value ([double]$row.resistElectric)),
        (Format-Integer -Value ([double]$row.resistAcid)),
        (Format-Integer -Value ([double]$row.resistStun)),
        (Format-Integer -Value ([double]$row.resistLightsaber))
    ) -join "`t"))
}

$output = [IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent -PathType Container))
{
    New-Item -ItemType Directory -Path $outputParent | Out-Null
}
[IO.File]::WriteAllText($output, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()
Write-Host "PRE-CU creature combat profile table exported."
Write-Host "  Core3: $actualCommit"
Write-Host "  exact profiles: $($profiles.Count)"
Write-Host "  current-name aliases: $($aliases.Count)"
Write-Host "  level fallbacks: $($fallbacks.Count)"
Write-Host "  SHA-256: $hash"
Write-Host "  output: $output"
