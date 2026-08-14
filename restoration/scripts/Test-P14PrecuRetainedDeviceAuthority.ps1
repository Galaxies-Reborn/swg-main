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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuRetainedDeviceAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$objectRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/object/tangible/scout"
$skillsPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

function Get-SkillRow([string]$SkillName)
{
    return @(Get-Content -LiteralPath $skillsPath | Where-Object { $_.StartsWith($SkillName + "`t") })
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.retained-device.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.retained-device.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$expectedTargets = @(
    "sku.0/sys.server/compiled/game/script/library/stealth.java",
    "sku.0/sys.server/compiled/game/script/library/utils.java"
) | Sort-Object
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    ($targets -join "`n") -ceq ($expectedTargets -join "`n")) "p14.retained-device.overlay.target-set"

$utilsPath = Join-Path $scriptRoot "library/utils.java"
$stealthPath = Join-Path $scriptRoot "library/stealth.java"
$sourceMap = [ordered]@{
    "script.library.utils" = $utilsPath
    "script.library.stealth" = $stealthPath
    "datatables.skill.skills" = $skillsPath
}
foreach ($property in $sourceMap.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $property.Value -PathType Leaf) "p14.retained-device.source.$($property.Key).exists"
    if (Test-Path -LiteralPath $property.Value -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $property.Value).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($property.Key)) `
            "p14.retained-device.source.$($property.Key).authenticated"
    }
}

$utilsText = Get-Content -LiteralPath $utilsPath -Raw
$stealthText = Get-Content -LiteralPath $stealthPath -Raw
$attributeSlice = Get-FunctionSlice $utilsText "public static int addClassRequirementAttributes(" "public static boolean testItemClassRequirements("
$classTestSlice = Get-FunctionSlice $utilsText "public static boolean testItemClassRequirements(obj_id player, String requiredClasses" "public static boolean testItemClassRequirements(obj_id player, obj_id thing"
$professionSlice = Get-FunctionSlice $utilsText "public static boolean isProfession(" "public static boolean isPrecuRetainedItemClass("
$adapterSlice = Get-FunctionSlice $utilsText "public static boolean isPrecuRetainedItemClass(" "public static boolean meetsProfessionRequirement("
$requirementSlice = Get-FunctionSlice $utilsText "public static boolean meetsProfessionRequirement(" "public static int getPlayerProfession("

Assert-Contract ($attributeSlice.Contains("getPrecuRetainedItemClassName(requiredClass)") -and
    $attributeSlice.Contains("isPrecuRetainedItemClass(player, requiredClass)")) `
    "p14.retained-device.class-presentation.adapter"
Assert-Contract ($classTestSlice.Contains("isPrecuRetainedItemClass(player") -and
    -not $classTestSlice.Contains("isProfession(player")) "p14.retained-device.class-admission.adapter"
Assert-Contract ($adapterSlice.Contains("profession == SPY") -and
    $adapterSlice.Contains('hasSkill(player, "outdoors_ranger_novice")') -and
    $adapterSlice.Contains("return isProfession(player, profession);") -and
    $adapterSlice.Contains('return "@skl_n:outdoors_ranger_novice";')) `
    "p14.retained-device.spy-slot.maps-to-ranger"
$presentationSlice = Get-FunctionSlice $utilsText `
    "public static String getPrecuRetainedItemClassName(" `
    "public static boolean meetsProfessionRequirement("
$presentationMappingsValid = -not $presentationSlice.Contains('"@skl_n:class_"')
foreach ($mapping in $contract.expected.precuClassPresentation.PSObject.Properties)
{
    $caseMarker = "case {0}:" -f $mapping.Name
    $returnMarker = 'return "{0}";' -f [string]$mapping.Value
    if (-not $presentationSlice.Contains($caseMarker) -or
        -not $presentationSlice.Contains($returnMarker))
    {
        $presentationMappingsValid = $false
    }
}
Assert-Contract ($presentationMappingsValid -and
    $presentationSlice.Contains('default:') -and
    $presentationSlice.Contains('return "";')) `
    "p14.retained-device.class-presentation.precu-skill-labels"
Assert-Contract ($professionSlice -match '(?s)case SPY:\s*return false;' -and
    -not $professionSlice.Contains("outdoors_ranger_novice") -and
    $requirementSlice -match '(?s)requirement[.]equals[(]"spy"[)].*?return isPrecuRetainedItemClass[(]player, SPY[)];') `
    "p14.retained-device.global-spy-identity.unchanged"

$disarmSlice = Get-FunctionSlice $stealthText "public static void disarmTrap(" "public static boolean canDetectCamouflage("
$concealSlice = Get-FunctionSlice $stealthText "public static void concealDevice(" "public static void unconcealDevice("
$setTrapSlice = Get-FunctionSlice $stealthText "public static boolean setTrap(" "public static obj_id getTrigger("
Assert-Contract ($disarmSlice.Contains("PRECU_TRAPPING_SKILL_MOD") -and
    $disarmSlice.Contains("MIN_CHANCE_TO_DISARM") -and
    $disarmSlice.Contains("MAX_CHANCE_TO_DISARM") -and
    -not $disarmSlice.Contains("getLevel(") -and
    -not $disarmSlice.Contains("ranger_trap") -and
    -not $disarmSlice.Contains("utils.SPY")) "p14.retained-device.disarm.precu-skill-authority"
Assert-Contract ($concealSlice.Contains("PRECU_CAMOUFLAGE_SKILL_MOD") -and
    $concealSlice.Contains("removeObjVar(target, CAMOUFLAGED_AT_LEVEL)") -and
    -not $concealSlice.Contains("getLevel(") -and
    -not $concealSlice.Contains('"stealth"')) "p14.retained-device.conceal.precu-skill-authority"
Assert-Contract ($setTrapSlice.Contains("PRECU_TRAPPING_SKILL_MOD") -and
    $setTrapSlice.Contains("removeObjVar(trap, TRAP_LEVEL)") -and
    -not $setTrapSlice.Contains("getLevel(") -and
    -not $setTrapSlice.Contains("ranger_trap") -and
    -not $setTrapSlice.Contains("setObjVar(trap, TRAP_LEVEL")) "p14.retained-device.arming.precu-skill-authority"
Assert-Contract (-not $stealthText.Contains("ranger_trap")) "p14.retained-device.nge-ranger-trap-mod.retired"

$scoutNovice = @(Get-SkillRow "outdoors_scout_novice")
$scoutMaster = @(Get-SkillRow "outdoors_scout_master")
$rangerNovice = @(Get-SkillRow "outdoors_ranger_novice")
$rangerMovement = @(Get-SkillRow "outdoors_ranger_movement_01")
$rangerSupport = @(Get-SkillRow "outdoors_ranger_support_01")
$rangerMaster = @(Get-SkillRow "outdoors_ranger_master")
Assert-Contract ($scoutNovice.Count -eq 1 -and $scoutNovice[0].Contains("trapping=5") -and
    $scoutMaster.Count -eq 1 -and $scoutMaster[0].Contains("trapping=20")) `
    "p14.retained-device.skills.scout-trapping-root"
Assert-Contract ($rangerNovice.Count -eq 1 -and $rangerNovice[0].Contains("outdoors_scout_master") -and
    $rangerMovement.Count -eq 1 -and $rangerMovement[0].Contains("conceal") -and $rangerMovement[0].Contains("camouflage=40") -and
    $rangerSupport.Count -eq 1 -and $rangerSupport[0].Contains("trapping=10") -and
    $rangerMaster.Count -eq 1 -and $rangerMaster[0].Contains("camouflage=20") -and $rangerMaster[0].Contains("trapping=10")) `
    "p14.retained-device.skills.ranger-role-authenticated"

$classMetadata = @(Get-ChildItem -LiteralPath $objectRoot -Recurse -File -Filter *.tpf |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw).Contains("classRequired") })
$levelMetadata = @($classMetadata | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw).Contains("levelRequired") })
$hepPath = Join-Path $objectRoot "misc/hep.tpf"
$hepText = Get-Content -LiteralPath $hepPath -Raw
Assert-Contract ($classMetadata.Count -eq [int]$contract.expected.retainedClassMetadataFiles -and
    $levelMetadata.Count -eq [int]$contract.expected.retainedLevelMetadataFiles) `
    "p14.retained-device.compatibility-metadata.preserved"
Assert-Contract ($hepText.Contains('abilityRequired" = "urbanStealth"')) `
    "p14.retained-device.hep-ability-metadata.preserved"

$missionMap = [ordered]@{
    "mission_terminal.java" = (Join-Path $scriptRoot "systems/missions/base/mission_terminal.java")
    "mission_base.java" = (Join-Path $scriptRoot "systems/missions/base/mission_base.java")
    "missions.java" = (Join-Path $scriptRoot "library/missions.java")
}
foreach ($mission in $missionMap.GetEnumerator())
{
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $mission.Value).Hash.ToLowerInvariant()
    Assert-Contract ($hash -ceq [string]$contract.continuityEvidence.missionSourceSha256.($mission.Key)) `
        "p14.retained-device.mission-source.$($mission.Key).unchanged"
}

if ($failures.Count -gt 0)
{
    throw "P14 PRE-CU retained-device authority contract failed: $($failures -join ', ')"
}

Write-Host "P14 PRE-CU retained-device authority contract passed."
