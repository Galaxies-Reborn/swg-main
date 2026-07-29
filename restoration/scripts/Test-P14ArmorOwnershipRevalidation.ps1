[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$utilsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/utils.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_mandalorian_armor_eligibility_fixture.java"
$utils = Get-Content -LiteralPath $utilsPath -Raw
$start = $utils.IndexOf("public static boolean hasSpecialSkills")
$end = $utils.IndexOf("public static int getIntObjVar", $start)
if ($start -lt 0 -or $end -le $start) { throw "Could not isolate armor revalidation surface." }
$surface = $utils.Substring($start, $end - $start)
foreach ($retired in @(
    "class_commando_phase4_master",
    "class_bountyhunter_phase4_master",
    "class_officer_phase4_master",
    "getSkillTemplate("
))
{
    if ($surface.Contains($retired)) { throw "Retired armor gate remains: $retired" }
}
foreach ($required in @(
    "combat_bountyhunter_master",
    "combat_commando_master",
    "outdoors_squadleader_master",
    "outdoors_ranger_master",
    "meetsProfessionRequirement(player, getStringObjVar(curArmor"
))
{
    if (-not $surface.Contains($required)) { throw "Required armor ownership rule is missing: $required" }
}
if (([regex]::Matches(
    $surface,
    [regex]::Escape(
        "meetsProfessionRequirement(player, getStringObjVar(curArmor")
    ).Count) -ne 2)
{
    throw "Both equipped and appearance dynamic-armor paths were not converted."
}
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf))
{
    throw "Mandalorian armor fixture is missing."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-armor-ownership-revalidation.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
}
Write-Host "Publish 14.1 armor ownership revalidation contract passed."
