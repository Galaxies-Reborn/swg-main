[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$paths = @(
    "library/utils.java",
    "library/content.java",
    "library/static_item.java",
    "item/armor/dynamic_armor.java",
    "item/static_item_base.java",
    "item/skillmod_click_item.java",
    "item/loot_schematic/loot_schematic.java"
)
foreach ($relative in $paths)
{
    $path = Join-Path $root ("dsrc/sku.0/sys.server/compiled/game/script/" + $relative)
    $source = Get-Content -LiteralPath $path -Raw
    if ($relative -ne "library/utils.java" -and $source.Contains("getSkillTemplate("))
    {
        throw "Direct class-template requirement remains in $relative"
    }
}
$utils = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/utils.java") -Raw
foreach ($required in @(
    "meetsProfessionRequirement",
    "hasSkill(player, requirement)",
    'requirement.equals("trader")',
    'requirement.equals("entertainer")',
    'requirement.equals("spy")'
))
{
    if (-not $utils.Contains($required)) { throw "Missing requirement boundary: $required" }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "contracts/p14-profession-requirement-gates.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
}
Write-Host "Publish 14.1 profession requirement gates contract passed."
