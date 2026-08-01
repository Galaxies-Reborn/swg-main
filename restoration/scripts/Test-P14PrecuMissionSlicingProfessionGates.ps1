[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuMissionSlicingProfessionGates)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$skillsPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

foreach ($evidence in @($contract.buildEvidence.overlayPatches))
{
    $patchPath = Join-Path $repositoryRoot ([string]$evidence.path)
    $exists = Test-Path -LiteralPath $patchPath -PathType Leaf
    Assert-Contract $exists "p14.precu-mission-slicing-gates.overlay.exists"
    if ($exists)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and
            $sha -ceq [string]$evidence.sha256) "p14.precu-mission-slicing-gates.overlay.authenticated"

        $patchText = Get-Content -LiteralPath $patchPath -Raw
        Assert-Contract (([regex]::Matches($patchText, '(?m)^diff --git ')).Count -eq 9 -and
            -not $patchText.Contains("/systems/combat/") -and
            -not $patchText.Contains("expertise")) "p14.precu-mission-slicing-gates.overlay.scope"
    }
}

Assert-Contract (@($contract.sourceFiles).Count -eq 9) "p14.precu-mission-slicing-gates.file-count"
$texts = @{}
foreach ($relative in @($contract.sourceFiles))
{
    $path = Join-Path $source ([string]$relative)
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Assert-Contract $exists ("p14.precu-mission-slicing-gates.source." +
        [IO.Path]::GetFileNameWithoutExtension([string]$relative))
    if ($exists)
    {
        $text = Get-Content -LiteralPath $path -Raw
        $texts[[string]$relative] = $text
        Assert-Contract (-not $text.Contains("class_")) ("p14.precu-mission-slicing-gates.zero-class." +
            [IO.Path]::GetFileNameWithoutExtension([string]$relative))
    }
}

$missionTerminal = $texts["dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_terminal.java"]
$missionPlayer = $texts["dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_player.java"]
$bountyDroid = $texts["dsrc/sku.0/sys.server/compiled/game/script/systems/missions/dynamic/mission_bounty_droid_terminal.java"]
$bountyInformant = $texts["dsrc/sku.0/sys.server/compiled/game/script/systems/missions/dynamic/mission_bounty_informant.java"]
$slicing = $texts["dsrc/sku.0/sys.server/compiled/game/script/library/slicing.java"]
$locked = $texts["dsrc/sku.0/sys.server/compiled/game/script/item/container/locked_slicable.java"]
$keypad = $texts["dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/keypad_handler.java"]
$officeKeypad = $texts["dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/geonosian_madbio_bunker/office_keypad.java"]
$corvette = $texts["dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/corvette/computer.java"]

$bountyGateCount = ([regex]::Matches(
    ($missionPlayer + $bountyDroid + $bountyInformant),
    'hasSkill\([^\)]*"combat_bountyhunter_novice"\)')).Count
Assert-Contract ($bountyGateCount -eq 4) "p14.precu-mission-slicing-gates.bounty-admission"

Assert-Contract (([regex]::Matches($missionTerminal,
    'hasSkill\(player, "combat_smuggler_slicing_01"\)')).Count -eq 2 -and
    $keypad.Contains('hasSkill(player, "combat_smuggler_slicing_01")') -and
    $officeKeypad.Contains('hasSkill(player, "combat_smuggler_slicing_01")')) "p14.precu-mission-slicing-gates.terminal-and-keypad"

Assert-Contract ($slicing.Contains('hasSkill(player, "combat_smuggler_novice")') -and
    ([regex]::Matches($locked, 'hasSkill\(player, "combat_smuggler_novice"\)')).Count -eq 2) "p14.precu-mission-slicing-gates.container"

$corvetteSkills = @(
    "combat_smuggler_slicing_01",
    "combat_smuggler_slicing_02",
    "combat_smuggler_slicing_03",
    "combat_smuggler_slicing_04",
    "combat_smuggler_master"
)
Assert-Contract ((@($corvetteSkills | Where-Object { -not $corvette.Contains($_) })).Count -eq 0 -and
    ([regex]::Matches($corvette, 'slicability = slicability \+ 1;')).Count -eq 3 -and
    ([regex]::Matches($corvette, 'slicability = slicability \+ 2;')).Count -eq 2) "p14.precu-mission-slicing-gates.corvette-weight-seven"

$skills = Get-Content -LiteralPath $skillsPath
foreach ($skillName in @("combat_bountyhunter_novice", "combat_smuggler_novice",
    "combat_smuggler_slicing_01", "combat_smuggler_slicing_02",
    "combat_smuggler_slicing_03", "combat_smuggler_slicing_04", "combat_smuggler_master"))
{
    Assert-Contract (@($skills | Where-Object { $_.StartsWith($skillName + [char]9) }).Count -eq 1) ("p14.precu-mission-slicing-gates.skill-exists." + $skillName)
}
$noviceRow = @($skills | Where-Object { $_.StartsWith("combat_smuggler_novice" + [char]9) })[0]
$slicingOneRow = @($skills | Where-Object { $_.StartsWith("combat_smuggler_slicing_01" + [char]9) })[0]
Assert-Contract ($noviceRow.Contains("slice_containers") -and
    $slicingOneRow.Contains("slice_terminals")) "p14.precu-mission-slicing-gates.command-ownership"

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.precu-mission-slicing-gates.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU mission/slicing profession gates failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU mission/slicing profession gates passed."
