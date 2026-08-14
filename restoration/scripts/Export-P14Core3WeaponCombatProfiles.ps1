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

function Get-Scalar
{
    param([string]$Text, [string]$Name, [switch]$Optional)

    $match = [regex]::Match(
        $Text,
        "(?m)^\s*$([regex]::Escape($Name))\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)\s*,")
    if (-not $match.Success)
    {
        if ($Optional)
        {
            return $null
        }
        throw "Required numeric field '$Name' is missing."
    }
    return [double]::Parse(
        $match.Groups[1].Value,
        [Globalization.CultureInfo]::InvariantCulture)
}

function Get-Identifier
{
    param([string]$Text, [string]$Name, [switch]$Optional)

    $match = [regex]::Match(
        $Text,
        "(?m)^\s*$([regex]::Escape($Name))\s*=\s*([A-Za-z0-9_]+)\s*,")
    if (-not $match.Success)
    {
        if ($Optional)
        {
            return ""
        }
        throw "Required identifier field '$Name' is missing."
    }
    return $match.Groups[1].Value
}

function Get-FirstArrayString
{
    param([string]$Text, [string]$Name, [switch]$Optional)

    $match = [regex]::Match(
        $Text,
        "(?m)^\s*$([regex]::Escape($Name))\s*=\s*\{([^}]*)\}")
    if ($match.Success)
    {
        $stringMatch = [regex]::Match($match.Groups[1].Value, '"([^"]+)"')
        if ($stringMatch.Success)
        {
            return $stringMatch.Groups[1].Value
        }
    }
    if ($Optional)
    {
        return ""
    }
    throw "Required array field '$Name' is missing or empty."
}

function Get-ArrayStrings
{
    param([string]$Text, [string]$Name)

    $match = [regex]::Match(
        $Text,
        "(?m)^\s*$([regex]::Escape($Name))\s*=\s*\{([^}]*)\}")
    if (-not $match.Success)
    {
        return @()
    }
    return @([regex]::Matches($match.Groups[1].Value, '"([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value })
}

function Get-Family
{
    param([string]$Template, [string]$SpeedSkill)

    switch -Regex ($SpeedSkill)
    {
        '^rifle_speed$' { return "rifle" }
        '^carbine_speed$' { return "carbine" }
        '^pistol_speed$' { return "pistol" }
        '^heavy_' { return "heavy" }
        '^onehandmelee_speed$' { return "onehandmelee" }
        '^twohandmelee_speed$' { return "twohandmelee" }
        '^unarmed_speed$' { return "unarmed" }
        '^polearm_speed$' { return "polearm" }
        '^thrown_speed$' { return "thrown" }
        '^onehandlightsaber_speed$' { return "onehandlightsaber" }
        '^twohandlightsaber_speed$' { return "twohandlightsaber" }
        '^polearmlightsaber_speed$' { return "polearmlightsaber" }
    }

    if ($Template -match '/mine/' -or $Template -match '/ranged/grenade/')
    {
        return "thrown"
    }
    throw "Unable to derive a PRE-CU weapon family for '$Template' (speed modifier '$SpeedSkill')."
}

function Get-FamilyDefaults
{
    param([string]$Family)

    $ranged = @("rifle", "carbine", "pistol", "heavy", "thrown") -contains $Family
    $secondarySkill = "unarmed_passive_defense"
    $secondaryResult = "RANDOM"
    $postureMultiplier = 1.0
    switch ($Family)
    {
        "rifle" { $secondarySkill = "block"; $secondaryResult = "BLOCK"; $postureMultiplier = 2.5 }
        "carbine" { $secondarySkill = "counterattack"; $secondaryResult = "COUNTER"; $postureMultiplier = 2.0 }
        "pistol" { $secondarySkill = "dodge"; $secondaryResult = "DODGE"; $postureMultiplier = 1.5 }
        "heavy" { $postureMultiplier = 3.0 }
        "onehandmelee" { $secondarySkill = "dodge"; $secondaryResult = "DODGE" }
        "twohandmelee" { $secondarySkill = "counterattack"; $secondaryResult = "COUNTER" }
        "polearm" { $secondarySkill = "block"; $secondaryResult = "BLOCK" }
        "onehandlightsaber" { $secondarySkill = "saber_block"; $secondaryResult = "RICOCHET" }
        "twohandlightsaber" { $secondarySkill = "saber_block"; $secondaryResult = "RICOCHET" }
        "polearmlightsaber" { $secondarySkill = "saber_block"; $secondaryResult = "RICOCHET" }
    }

    $categoryAccuracySkill = "melee_accuracy"
    $defenseSkill = "melee_defense"
    if ($ranged)
    {
        $categoryAccuracySkill = "ranged_accuracy"
        $defenseSkill = "ranged_defense"
    }
    $accuracySkill = ""
    $speedSkill = ""
    $damageSkill = ""
    $toughnessSkill = ""
    switch ($Family)
    {
        "rifle" { $accuracySkill = "rifle_accuracy"; $speedSkill = "rifle_speed" }
        "carbine" { $accuracySkill = "carbine_accuracy"; $speedSkill = "carbine_speed" }
        "pistol" { $accuracySkill = "pistol_accuracy"; $speedSkill = "pistol_speed" }
        "heavy" { $accuracySkill = "heavyweapon_accuracy"; $speedSkill = "heavyweapon_speed" }
        "onehandmelee" { $accuracySkill = "onehandmelee_accuracy"; $speedSkill = "onehandmelee_speed" }
        "twohandmelee" { $accuracySkill = "twohandmelee_accuracy"; $speedSkill = "twohandmelee_speed" }
        "unarmed" { $accuracySkill = "unarmed_accuracy"; $speedSkill = "unarmed_speed"; $damageSkill = "unarmed_damage"; $toughnessSkill = "unarmed_toughness" }
        "polearm" { $accuracySkill = "polearm_accuracy"; $speedSkill = "polearm_speed" }
        "thrown" { $accuracySkill = "thrown_accuracy"; $speedSkill = "thrown_speed" }
        "onehandlightsaber" { $accuracySkill = "onehandlightsaber_accuracy"; $speedSkill = "onehandlightsaber_speed" }
        "twohandlightsaber" { $accuracySkill = "twohandlightsaber_accuracy"; $speedSkill = "twohandlightsaber_speed" }
        "polearmlightsaber" { $accuracySkill = "polearmlightsaber_accuracy"; $speedSkill = "polearmlightsaber_speed" }
    }
    switch ($Family)
    {
        "onehandmelee" { $toughnessSkill = "onehandmelee_toughness" }
        "twohandmelee" { $toughnessSkill = "twohandmelee_toughness" }
        "polearm" { $toughnessSkill = "polearm_toughness" }
        "onehandlightsaber" { $toughnessSkill = "lightsaber_toughness" }
        "twohandlightsaber" { $toughnessSkill = "lightsaber_toughness" }
        "polearmlightsaber" { $toughnessSkill = "lightsaber_toughness" }
    }
    return [pscustomobject]@{
        AccuracySkill = $accuracySkill
        SpeedSkill = $speedSkill
        DamageSkill = $damageSkill
        ToughnessSkill = $toughnessSkill
        CategoryAccuracySkill = $categoryAccuracySkill
        DefenseSkill = $defenseSkill
        SecondaryDefenseSkill = $secondarySkill
        SecondaryDefenseResult = $secondaryResult
        PostureMultiplier = $postureMultiplier
    }
}

function Get-Median
{
    param([object[]]$Values)

    $ordered = @($Values | Sort-Object)
    if ($ordered.Count -eq 0)
    {
        throw "Cannot calculate a median from an empty set."
    }
    $middle = [int][Math]::Floor($ordered.Count / 2.0)
    if (($ordered.Count % 2) -eq 1)
    {
        return [double]$ordered[$middle]
    }
    return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
}

function Format-Number
{
    param([double]$Value)
    return $Value.ToString('0.0###', [Globalization.CultureInfo]::InvariantCulture)
}

$armorPiercingMap = @{
    "NONE" = 0
    "LIGHT" = 1
    "MEDIUM" = 2
    "HEAVY" = 3
}
$rows = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $weaponRoot -Recurse -File -Filter "*.lua")
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $templateMatch = [regex]::Match(
        $text,
        'ObjectTemplates:addTemplate\([^,]+,\s*"([^"]+)"\s*\)')
    $speed = Get-Scalar -Text $text -Name "attackSpeed" -Optional
    if (-not $templateMatch.Success -or $null -eq $speed -or $speed -le 0.0)
    {
        continue
    }

    $template = $templateMatch.Groups[1].Value
    $speedSkill = Get-FirstArrayString -Text $text -Name "speedModifiers" -Optional
    $accuracySkill = Get-FirstArrayString -Text $text -Name "creatureAccuracyModifiers" -Optional
    $damageSkill = Get-FirstArrayString -Text $text -Name "damageModifiers" -Optional
    $toughnessSkill = Get-FirstArrayString -Text $text -Name "defenderToughnessModifiers" -Optional
    $defenseSkills = @(Get-ArrayStrings -Text $text -Name "defenderDefenseModifiers")
    $defenseSkill = ""
    $defenseSkill2 = ""
    if ($defenseSkills.Count -gt 0) { $defenseSkill = $defenseSkills[0] }
    if ($defenseSkills.Count -gt 1) { $defenseSkill2 = $defenseSkills[1] }
    $secondarySkill = Get-FirstArrayString -Text $text -Name "defenderSecondaryDefenseModifiers" -Optional
    if ($template -match '/mine/' -or $template -match '/ranged/grenade/')
    {
        if ($speedSkill.Length -eq 0) { $speedSkill = "thrown_speed" }
        if ($accuracySkill.Length -eq 0) { $accuracySkill = "thrown_accuracy" }
    }
    $family = Get-Family -Template $template -SpeedSkill $speedSkill
    $defaults = Get-FamilyDefaults -Family $family
    if ($defenseSkill.Length -eq 0) { $defenseSkill = $defaults.DefenseSkill }
    if ($secondarySkill.Length -eq 0) { $secondarySkill = $defaults.SecondaryDefenseSkill }

    $armorIdentifier = Get-Identifier -Text $text -Name "armorPiercing" -Optional
    if ($armorIdentifier.Length -eq 0 -and
        ($template -match '/mine/' -or $template -match '/ranged/grenade/'))
    {
        $armorIdentifier = "NONE"
    }
    if (-not $armorPiercingMap.ContainsKey($armorIdentifier))
    {
        throw "Unknown armor-piercing value '$armorIdentifier' in '$template'."
    }

    $rows.Add([pscustomobject]@{
        Template = $template
        Family = $family
        AttackSpeed = [double]$speed
        SpeedSkill = $speedSkill
        DamageSkill = $damageSkill
        ToughnessSkill = $toughnessSkill
        PointBlankRange = Get-Scalar -Text $text -Name "pointBlankRange"
        PointBlankAccuracy = Get-Scalar -Text $text -Name "pointBlankAccuracy"
        IdealRange = Get-Scalar -Text $text -Name "idealRange"
        IdealAccuracy = Get-Scalar -Text $text -Name "idealAccuracy"
        MaxRange = Get-Scalar -Text $text -Name "maxRange"
        MaxRangeAccuracy = Get-Scalar -Text $text -Name "maxRangeAccuracy"
        AccuracySkill = $accuracySkill
        CategoryAccuracySkill = $defaults.CategoryAccuracySkill
        DefenseSkill = $defenseSkill
        DefenseSkill2 = $defenseSkill2
        PostureMultiplier = [double]$defaults.PostureMultiplier
        SecondaryDefenseSkill = $secondarySkill
        SecondaryDefenseResult = $defaults.SecondaryDefenseResult
        WoundsRatio = Get-Scalar -Text $text -Name "woundsRatio" -Optional
        ArmorPiercing = [int]$armorPiercingMap[$armorIdentifier]
    })
}

$orderedRows = @($rows | Sort-Object Template -Unique)
if ($orderedRows.Count -ne 342)
{
    throw "Expected 342 positive, unique Core3 weapon profiles; found $($orderedRows.Count)."
}

$fallbackSpeeds = [ordered]@{
    "default" = 4.0
    "rifle" = 5.9
    "carbine" = 3.6
    "pistol" = 3.6
    "heavy" = 7.8
    "onehandmelee" = 4.5
    "twohandmelee" = 4.8
    "unarmed" = 2.0
    "polearm" = 5.1
    "thrown" = 5.0
    "onehandlightsaber" = 4.5
    "twohandlightsaber" = 4.8
    "polearmlightsaber" = 5.1
}
$fallbackRows = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $fallbackSpeeds.GetEnumerator())
{
    $family = [string]$entry.Key
    $sourceFamily = $family
    if ($family -eq "default")
    {
        $sourceFamily = "unarmed"
    }
    $familyRows = @($orderedRows | Where-Object { $_.Family -ceq $sourceFamily })
    if ($familyRows.Count -eq 0)
    {
        throw "No Core3 rows are available for family fallback '$family'."
    }
    $defaults = Get-FamilyDefaults -Family $sourceFamily
    $sample = $familyRows[0]
    $fallbackRows.Add([pscustomobject]@{
        Template = "__family_$family"
        Family = $family
        AttackSpeed = [double]$entry.Value
        SpeedSkill = $defaults.SpeedSkill
        DamageSkill = $defaults.DamageSkill
        ToughnessSkill = $defaults.ToughnessSkill
        PointBlankRange = Get-Median @($familyRows.PointBlankRange)
        PointBlankAccuracy = Get-Median @($familyRows.PointBlankAccuracy)
        IdealRange = Get-Median @($familyRows.IdealRange)
        IdealAccuracy = Get-Median @($familyRows.IdealAccuracy)
        MaxRange = Get-Median @($familyRows.MaxRange)
        MaxRangeAccuracy = Get-Median @($familyRows.MaxRangeAccuracy)
        AccuracySkill = $defaults.AccuracySkill
        CategoryAccuracySkill = $defaults.CategoryAccuracySkill
        DefenseSkill = $defaults.DefenseSkill
        DefenseSkill2 = ""
        PostureMultiplier = [double]$defaults.PostureMultiplier
        SecondaryDefenseSkill = $defaults.SecondaryDefenseSkill
        SecondaryDefenseResult = $defaults.SecondaryDefenseResult
        WoundsRatio = Get-Median @($familyRows | Where-Object { $null -ne $_.WoundsRatio } | ForEach-Object { $_.WoundsRatio })
        ArmorPiercing = [int](Get-Median @($familyRows.ArmorPiercing))
    })
}

$woundsFallback = @{}
foreach ($fallback in $fallbackRows)
{
    $woundsFallback[$fallback.Family] = [int][Math]::Round($fallback.WoundsRatio)
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("templateName`tattackSpeed`tspeedSkill`tdamageSkill`ttoughnessSkill`tpointBlankRange`tpointBlankAccuracy`tidealRange`tidealAccuracy`tmaxRange`tmaxRangeAccuracy`taccuracySkill`tcategoryAccuracySkill`tdefenseSkill`tdefenseSkill2`tweaponFamily`tpostureMultiplier`tsecondaryDefenseSkill`tsecondaryDefenseResult`twoundsRatio`tarmorPiercing")
$lines.Add("s`tf`ts`ts`ts`tf`tf`tf`tf`tf`tf`ts`ts`ts`ts`ts`tf`ts`ts`ti`ti")
foreach ($row in @($fallbackRows) + @($orderedRows))
{
    $woundsRatio = [int]$woundsFallback[$row.Family]
    if ($null -ne $row.WoundsRatio)
    {
        $woundsRatio = [int][Math]::Round([double]$row.WoundsRatio)
    }
    $lines.Add((@(
        $row.Template,
        (Format-Number $row.AttackSpeed),
        $row.SpeedSkill,
        $row.DamageSkill,
        $row.ToughnessSkill,
        (Format-Number $row.PointBlankRange),
        (Format-Number $row.PointBlankAccuracy),
        (Format-Number $row.IdealRange),
        (Format-Number $row.IdealAccuracy),
        (Format-Number $row.MaxRange),
        (Format-Number $row.MaxRangeAccuracy),
        $row.AccuracySkill,
        $row.CategoryAccuracySkill,
        $row.DefenseSkill,
        $row.DefenseSkill2,
        $row.Family,
        (Format-Number $row.PostureMultiplier),
        $row.SecondaryDefenseSkill,
        $row.SecondaryDefenseResult,
        $woundsRatio,
        $row.ArmorPiercing
    ) -join "`t"))
}

$output = [IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent -PathType Container))
{
    New-Item -ItemType Directory -Path $outputParent | Out-Null
}
[IO.File]::WriteAllText(
    $output,
    (($lines -join "`n") + "`n"),
    [Text.UTF8Encoding]::new($false))

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()
Write-Host "PRE-CU Core3 weapon combat profile table exported."
Write-Host "  Core3: $actualCommit"
Write-Host "  exact rows: $($orderedRows.Count)"
Write-Host "  family fallbacks: $($fallbackRows.Count)"
Write-Host "  SHA-256: $hash"
Write-Host "  output: $output"
