[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.precuExpansionWorlds)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

function Read-SourceText
{
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $path = Join-Path $source ($RelativePath -replace "/", "\")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required expansion-world source is missing: $path"
    }
    return Get-Content -LiteralPath $path -Raw
}

function Read-TabTable
{
    param([Parameter(Mandatory = $true)][string]$Value)
    $lines = @($Value -split "`r?`n" | Where-Object { $_.Length -gt 0 })
    $headers = @($lines[0] -split "`t")
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines[2..($lines.Count - 1)])
    {
        $values = @($line -split "`t")
        $row = [ordered]@{}
        for ($index = 0; $index -lt $headers.Count; ++$index)
        {
            $row[$headers[$index]] = if ($index -lt $values.Count) { $values[$index] } else { "" }
        }
        $rows.Add([pscustomobject]$row)
    }
    return $rows.ToArray()
}

function Get-IniSectionText
{
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$SectionName
    )

    $currentSection = ""
    $sectionLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($Value -split "`r?`n"))
    {
        if ($line -match '^\s*\[([^\]]+)\]\s*$')
        {
            $currentSection = [string]$Matches[1]
            continue
        }
        if ($currentSection -ceq $SectionName)
        {
            $sectionLines.Add([string]$line)
        }
    }
    return $sectionLines -join "`n"
}

$text = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $text[[string]$property.Name] = Read-SourceText -RelativePath ([string]$property.Value)
}

Write-Host "Pre-CU expansion-world server checks:"
Assert-Contract `
    -Condition ([string]$contract.status -ceq "ready") `
    -Name "precu.expansion-worlds.contract.ready"

$allScenes = @($contract.groundScenes) + @($contract.spaceScenes) + @($contract.instanceScenes)
$planetNames = @($text.planetCrc -split "`r?`n" | Where-Object { $_.Length -gt 0 })
$missingPlanetCrc = @($allScenes | Where-Object { $planetNames -cnotcontains [string]$_ })
Assert-Contract `
    -Condition ($missingPlanetCrc.Count -eq 0) `
    -Name "precu.expansion-worlds.planet-crc.complete-scene-registration"

$centralServerConfig = Get-IniSectionText -Value $text.localOptions -SectionName "CentralServer"
$disabledScenes = @()
foreach ($scene in $allScenes)
{
    if ($centralServerConfig -notmatch "(?m)^startPlanet=$([regex]::Escape([string]$scene))$")
    {
        $disabledScenes += [string]$scene
    }
}
Assert-Contract `
    -Condition ($disabledScenes.Count -eq 0) `
    -Name "precu.expansion-worlds.central-server.full-scene-source-profile-available"

$allRegisteredScenes = @($planetNames | Sort-Object -Unique)
$invalidAcceptanceScenes = @($contract.localAcceptanceScenes | Where-Object {
    $allRegisteredScenes -cnotcontains [string]$_
})
$expectedLocalProfile = @($contract.localAcceptanceScenes) -join ','
$entrypointProfileReady = `
    $text.entrypoint.Contains('SWG_START_PLANETS="${SWG_START_PLANETS:-}"') -and `
    $text.entrypoint.Contains('apply_runtime_scene_profile()') -and `
    $text.entrypoint.Contains('grep -Fxc "startPlanet=${scene}"') -and `
    $text.entrypoint.Contains('while IFS= read -r line || [ -n "${line}" ]') -and `
    $text.entrypoint.Contains('case " ${requested} " in') -and `
    -not $text.entrypoint.Contains('awk -v requested=')
Assert-Contract `
    -Condition ($invalidAcceptanceScenes.Count -eq 0 -and $entrypointProfileReady -and $expectedLocalProfile.Length -gt 0) `
    -Name "precu.expansion-worlds.local-acceptance-profile.bounded-and-reproducible"

$ordScenes = @($contract.spaceScenes | Where-Object { [string]$_ -like "space_ord_mantell*" })
$ordEnabledExactlyOnce = $true
foreach ($scene in $ordScenes)
{
    $matches = [regex]::Matches($centralServerConfig, "(?m)^startPlanet=$([regex]::Escape([string]$scene))$")
    if ($matches.Count -ne 1) { $ordEnabledExactlyOnce = $false }
}
Assert-Contract `
    -Condition ($ordScenes.Count -eq 6 -and $ordEnabledExactlyOnce) `
    -Name "precu.expansion-worlds.ord-mantell.six-shards-enabled-once"

$travelRows = @(Read-TabTable -Value $text.travelMatrix)
$travelHeader = @(($text.travelMatrix -split "`r?`n")[0] -split "`t")
$corellia = @($travelRows | Where-Object { $_.Planet -ceq "corellia" })[0]
$mustafar = @($travelRows | Where-Object { $_.Planet -ceq "mustafar" })[0]
$kashyyyk = @($travelRows | Where-Object { $_.Planet -ceq "kashyyyk_main" })[0]
$travelReady = `
    ($travelRows.Count -eq 12) -and `
    ($travelHeader -ccontains "mustafar") -and `
    ($travelHeader -ccontains "kashyyyk_main") -and `
    ([int]$corellia.mustafar -eq 1000) -and `
    ([int]$corellia.kashyyyk_main -eq 2000) -and `
    ([int]$mustafar.corellia -eq 1000) -and `
    ([int]$kashyyyk.corellia -eq 1250)
Assert-Contract `
    -Condition $travelReady `
    -Name "precu.expansion-worlds.starports.authentic-mustafar-kashyyyk-matrix"

$mustafarStarport = [string]$contract.travelSemantics.starports.mustafar
$kashyyykStarport = [string]$contract.travelSemantics.starports.kashyyyk_main
$starportRegistrationReady = `
    $text.mustafarBuildout.Contains("structure.municipal.starport") -and `
    $text.mustafarBuildout.Contains("travel.point_name|4|$mustafarStarport") -and `
    $text.mustafarBuildout.Contains("mustafar 0|travel.base_object") -and `
    $text.kashyyykBuildout.Contains("structure.municipal.starport") -and `
    $text.kashyyykBuildout.Contains("travel.point_name|4|$kashyyykStarport") -and `
    $text.kashyyykBuildout.Contains("kashyyyk_main 0|travel.base_object")
Assert-Contract `
    -Condition $starportRegistrationReady `
    -Name "precu.expansion-worlds.starports.live-travel-points-registered-by-buildouts"

$widthRows = @(Read-TabTable -Value $text.planetWidth)
$mustafarWidth = @($widthRows | Where-Object { $_.Planet -ceq "mustafar" })[0]
$kashyyykWidth = @($widthRows | Where-Object { $_.Planet -ceq "kashyyyk_main" })[0]
Assert-Contract `
    -Condition ([int][float]$mustafarWidth.Width -eq 8000 -and [int][float]$kashyyykWidth.Width -eq 4096) `
    -Name "precu.expansion-worlds.starports.planet-map-widths"

$buildoutsPresent = $true
foreach ($relativePath in @($contract.instanceBuildouts))
{
    $path = Join-Path $source ("serverdata\" + ([string]$relativePath -replace "/", "\"))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $buildoutsPresent = $false }
}
Assert-Contract `
    -Condition $buildoutsPresent `
    -Name "precu.expansion-worlds.instances.all-buildouts-present"

$terrainPresent = $true
foreach ($scene in @($contract.groundScenes) + @($contract.spaceScenes) + @($contract.instanceScenes))
{
    $path = Join-Path $source "serverdata\terrain\$scene.trn"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $terrainPresent = $false }
}
Assert-Contract `
    -Condition $terrainPresent `
    -Name "precu.expansion-worlds.terrain.complete-scene-set"

$tansariiReady = `
    $text.npeLibrary.Contains('BUILDOUT_NAME_SHARED_STATION = "npe_shared_station"') -and `
    $text.npeLibrary.Contains('DUNGEON_SPACE_STATION = "npe_space_station"') -and `
    $text.npeLibrary.Contains('movePlayerFromFalconToSharedStation') -and `
    $text.npeLibrary.Contains('getClusterWideData(DUNGEON_PUBLIC_MANAGER_NAME, DUNGEON_SPACE_STATION + "*"')
Assert-Contract `
    -Condition $tansariiReady `
    -Name "precu.expansion-worlds.tansarii.instanced-dungeon1-transport"

$ordRoutingReady = `
    $text.npeLibrary.Contains('getNumberOfOrdSpaceScenes()') -and `
    $text.npeLibrary.Contains('SCENE_SPACE_ORD_MANTELL + "_" + i') -and `
    $text.npeLibrary.Contains('getOpenOrdMantellSpaceZone()')
Assert-Contract `
    -Condition $ordRoutingReady `
    -Name "precu.expansion-worlds.ord-mantell.load-balanced-routing"

$hothReady = `
    $text.echoBaseLaunch.Contains('instance.requestInstanceMovement(player, "echo_base", 1, "rebel")') -and `
    $text.echoBaseLaunch.Contains('instance.requestInstanceMovement(player, "echo_base", 2, "imperial")')
Assert-Contract `
    -Condition $hothReady `
    -Name "precu.expansion-worlds.hoth.echo-base-instance-routing"

$spaceTerminalReady = `
    $text.spaceTerminal.Contains('if (planet.equals("kashyyyk_main"))') -and `
    $text.spaceTerminal.Contains('travel.SID_KASHYYYK_UNAUTHORIZED')
Assert-Contract `
    -Condition $spaceTerminalReady `
    -Name "precu.expansion-worlds.kashyyyk.original-space-terminal-gate-retained"

Assert-Contract `
    -Condition ($text.multiserver.Contains('sceneID=mustafar') -and $text.multiserver.Contains('sceneID=kashyyyk_main') -and $text.multiserver.Contains('sceneID=adventure1') -and $text.multiserver.Contains('sceneID=adventure2') -and $text.multiserver.Contains('sceneID=space_nova_orion')) `
    -Name "precu.expansion-worlds.multiserver.primary-scenes-assigned"

if ($failures.Count -gt 0)
{
    throw "Pre-CU expansion-world contract failed: $($failures -join ', ')"
}

Write-Host "Pre-CU expansion-world contract passed."
