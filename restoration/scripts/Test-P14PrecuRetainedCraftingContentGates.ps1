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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuRetainedCraftingContentGates)
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
    Assert-Contract $exists "p14.precu-retained-crafting-gates.overlay.exists"
    if ($exists)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and
            $sha -ceq [string]$evidence.sha256) "p14.precu-retained-crafting-gates.overlay.authenticated"

        $patchText = Get-Content -LiteralPath $patchPath -Raw
        Assert-Contract (([regex]::Matches($patchText, '(?m)^diff --git ')).Count -eq 9 -and
            -not $patchText.Contains("/systems/combat/") -and
            -not $patchText.Contains("expertise")) "p14.precu-retained-crafting-gates.overlay.scope"
    }
}

Assert-Contract (@($contract.sourceFiles).Count -eq 9) "p14.precu-retained-crafting-gates.file-count"
$texts = @{}
foreach ($relative in @($contract.sourceFiles))
{
    $path = Join-Path $source ([string]$relative)
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $label = ([string]$relative).Replace('/', '.')
    Assert-Contract $exists ("p14.precu-retained-crafting-gates.source." + $label)
    if ($exists)
    {
        $text = Get-Content -LiteralPath $path -Raw
        $texts[[string]$relative] = $text
        Assert-Contract (-not $text.Contains("class_")) ("p14.precu-retained-crafting-gates.zero-class." + $label)
    }
}

$dwb = "dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/death_watch_bunker/"
Assert-Contract ($texts[$dwb + "craft_armorsmith_droid.java"].Contains('hasSkill(giver, "crafting_armorsmith_master")') -and
    $texts[$dwb + "door_lock_crafting_armor.java"].Contains('hasSkill(player, "crafting_armorsmith_master")')) "p14.precu-retained-crafting-gates.death-watch-armorsmith"
Assert-Contract ($texts[$dwb + "craft_droidengineer_droid.java"].Contains('hasSkill(giver, "crafting_droidengineer_master")') -and
    $texts[$dwb + "door_lock_crafting_de.java"].Contains('hasSkill(player, "crafting_droidengineer_master")')) "p14.precu-retained-crafting-gates.death-watch-droidengineer"
Assert-Contract ($texts[$dwb + "craft_jetpack_droid.java"].Contains('hasSkill(giver, "crafting_artisan_master")')) "p14.precu-retained-crafting-gates.death-watch-jetpack"
Assert-Contract ($texts[$dwb + "craft_tailor_droid.java"].Contains('hasSkill(giver, "crafting_tailor_master")') -and
    $texts[$dwb + "door_lock_crafting_tailor.java"].Contains('hasSkill(player, "crafting_tailor_master")')) "p14.precu-retained-crafting-gates.death-watch-tailor"

$mustafar = $texts["dsrc/sku.0/sys.server/compiled/game/script/theme_park/dungeon/mustafar_trials/valley_battleground/mining_droid.java"]
$armorsmithQuest = $texts["dsrc/sku.0/sys.server/compiled/game/script/npc/static_quest/quest_armorsmith.java"]
Assert-Contract ($mustafar.Contains('hasSkill(player, "crafting_droidengineer_novice")')) "p14.precu-retained-crafting-gates.mustafar-droidengineer"
Assert-Contract ($armorsmithQuest.Contains('hasSkill(player, "crafting_armorsmith_master")')) "p14.precu-retained-crafting-gates.armorsmith-quest"

$skills = Get-Content -LiteralPath $skillsPath
foreach ($skillName in @("crafting_armorsmith_master", "crafting_droidengineer_master",
    "crafting_artisan_master", "crafting_tailor_master", "crafting_droidengineer_novice"))
{
    Assert-Contract (@($skills | Where-Object { $_.StartsWith($skillName + [char]9) }).Count -eq 1) ("p14.precu-retained-crafting-gates.skill-exists." + $skillName)
}

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.precu-retained-crafting-gates.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU retained crafting-content gates failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU retained crafting-content gates passed."
