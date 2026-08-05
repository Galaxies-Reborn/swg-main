[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Source", "Ready")]
    [string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuTargetDummyDefenseAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$paths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $source ([string]$property.Value)
}
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedBlock([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.target-defense.source.$([IO.Path]::GetFileName($path)).exists"
}

$targetDummy = Get-Content -LiteralPath $paths.targetDummyLibrary -Raw
$targetSimulator = Get-Content -LiteralPath $paths.targetSimulator -Raw
$create = Get-Content -LiteralPath $paths.createLibrary -Raw
$combat = Get-Content -LiteralPath $paths.combatLibrary -Raw
$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$targetDefenses = Get-BracedBlock $targetDummy `
    "public static final String[] TARGET_DUMMY_DEFENSES"
$setDefense = Get-BracedBlock $targetDummy `
    "public static void setTargetDummyDefensiveValue(obj_id targetDummy, obj_id player, int value, String defenseName)"
$restoreDefenses = Get-BracedBlock $targetDummy `
    "public static void applyPersistedTargetDummyDefenses"
$initializeTarget = Get-BracedBlock $targetDummy `
    "public static boolean initializeTargetDummy"
$setupTarget = Get-BracedBlock $targetSimulator `
    "public int handleTargetCreatureSetUp"
$inputTarget = Get-BracedBlock $targetSimulator `
    "public int handleTargetDummyDefensiveSkillModSet"

$armorControls = @(
    "precu_armor_rating", "precu_armor_kinetic", "precu_armor_energy",
    "precu_armor_blast", "precu_armor_heat", "precu_armor_cold",
    "precu_armor_electricity", "precu_armor_acid", "precu_armor_stun",
    "precu_armor_lightsaber"
)
$skillControls = @("ranged_defense", "melee_defense", "unarmed_passive_defense")
$configuredControls = @([regex]::Matches($targetDefenses, '"([^"\r\n]+)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-Contract ($configuredControls.Count -eq [int]$contract.expected.targetDefenseControls -and
    @($configuredControls | Where-Object { $_ -notin ($armorControls + $skillControls) }).Count -eq 0 -and
    @($armorControls | Where-Object { $_ -notin $configuredControls }).Count -eq 0 -and
    @($skillControls | Where-Object { $_ -notin $configuredControls }).Count -eq 0) `
    "p14.target-defense.exact-precu-control-set"
Assert-Contract (-not $targetDummy.Contains("expertise_") -and
    -not $targetDummy.Contains("armor.recalculateArmorForMob")) `
    "p14.target-defense.nge-expertise-controls-absent"

Assert-Contract ($setDefense.Contains('defenseName.equals("precu_armor_rating")') -and
    $setDefense.Contains("value < 0 || value > 3") -and
    $setDefense.Contains('setObjVar(targetDummy, "precu.armor.rating", value)') -and
    $setDefense.Contains("value < -1 || value > 200") -and
    $setDefense.Contains("getPrecuTargetDummyArmorObjVar(defenseName)") -and
    $setDefense.Contains("value < 0 || value > 125") -and
    $setDefense.Contains("applySkillStatisticModifier(targetDummy, defenseName, value)") -and
    $setDefense.Contains('"target_dummy_defense." + defenseName')) `
    "p14.target-defense.authentic-ranges-and-writes"
Assert-Contract ($initializeTarget.Contains("create.initializeCreature") -and
    $initializeTarget.Contains("applyPersistedTargetDummyDefenses(targetDummy)") -and
    $initializeTarget.IndexOf("applyPersistedTargetDummyDefenses", [StringComparison]::Ordinal) -gt
        $initializeTarget.IndexOf("create.initializeCreature", [StringComparison]::Ordinal) -and
    $restoreDefenses.Contains('"target_dummy_defense." + defenseName') -and
    $restoreDefenses.Contains("setTargetDummyDefensiveValue")) `
    "p14.target-defense.reinitialization-persistence"
Assert-Contract (-not $setupTarget.Contains("TARGET_DUMMY_DEFENSES") -and
    $setupTarget.Contains("initializeTargetDummy") -and
    $inputTarget.Contains('text.trim().equals("-1")') -and
    $inputTarget.Contains("Enter a whole-number PRE-CU defense value.")) `
    "p14.target-defense.single-restore-path-and-strict-input"

$armorObjVars = @(
    "rating", "kinetic", "energy", "blast", "heat", "cold",
    "electricity", "acid", "stun", "lightsaber"
)
Assert-Contract (@($armorObjVars | Where-Object {
        -not $create.Contains('setObjVar(creature, "precu.armor.' + $_ + '"')
    }).Count -eq 0 -and
    $combat.Contains("applyPrecuCreatureArmorProtection") -and
    $combat.Contains('"precu.armor.rating"') -and
    $combat.Contains('String resistanceObjVar = "precu.armor." + damageString') -and
    $combat.Contains("rawResistance > 100 ? rawResistance - 100 : rawResistance") -and
    $combatBase.Contains('hasObjVar(defender, "precu.combatProfile")') -and
    $combatBase.Contains("combat.applyPrecuCreatureArmorProtection")) `
    "p14.target-defense.precu-creature-armor-consumer"
Assert-Contract ($combatBase.Contains('String defenseSkill = dataTableGetString(PRECU_WEAPON_PROFILES') -and
    $combatBase.Contains("getEnhancedSkillStatisticModifierUncapped(defenderData.id, defenseSkill)") -and
    $combatBase.Contains('String secondaryDefenseSkill = dataTableGetString(PRECU_WEAPON_PROFILES') -and
    $combatBase.Contains("getEnhancedSkillStatisticModifierUncapped(defenderData.id, secondaryDefenseSkill)") -and
    $combatBase.Contains("if (defenseSkillValue > 125)") -and
    $combatBase.Contains("if (evadeSkill > 125)")) `
    "p14.target-defense.precu-defense-skill-consumers"

$weaponProfiles = @(Import-Csv -LiteralPath $paths.weaponProfiles -Delimiter "`t")
$defaultProfile = @($weaponProfiles | Where-Object { $_.templateName -ceq "__family_default" })
$creatureWeapon = @($weaponProfiles | Where-Object {
    $_.templateName -ceq "object/weapon/creature/creature_default_weapon.iff"
})
Assert-Contract ($defaultProfile.Count -eq 1 -and
    $defaultProfile[0].defenseSkill -ceq "melee_defense" -and
    $defaultProfile[0].secondaryDefenseSkill -ceq "unarmed_passive_defense" -and
    $creatureWeapon.Count -eq 1 -and
    $creatureWeapon[0].defenseSkill -ceq "unarmed_passive_defense" -and
    $creatureWeapon[0].defenseSkill2 -ceq "melee_defense" -and
    $creatureWeapon[0].secondaryDefenseSkill -ceq "unarmed_passive_defense" -and
    $creatureWeapon[0].secondaryDefenseResult -ceq "RANDOM") `
    "p14.target-defense.authenticated-default-weapon-profile"

$creatureProfiles = @(Import-Csv -LiteralPath $paths.creatureProfiles -Delimiter "`t" |
    Where-Object { $_.creatureName -ne "s" })
function Get-ProfileRange([string]$Column)
{
    $values = @($creatureProfiles | ForEach-Object { [int]($_.$Column) })
    return [ordered]@{
        minimum = ($values | Measure-Object -Minimum).Minimum
        maximum = ($values | Measure-Object -Maximum).Maximum
    }
}
$armorRange = Get-ProfileRange "armor"
$resistanceColumns = @(
    "resistKinetic", "resistEnergy", "resistBlast", "resistHeat",
    "resistCold", "resistElectric", "resistAcid", "resistStun"
)
$resistanceRanges = @($resistanceColumns | ForEach-Object { Get-ProfileRange $_ })
Assert-Contract ($armorRange.minimum -eq [int]$contract.expected.armorRatingMinimum -and
    $armorRange.maximum -eq [int]$contract.expected.armorRatingMaximum -and
    @($resistanceRanges | Where-Object {
        $_.minimum -ne [int]$contract.expected.rawResistanceMinimum -or
        $_.maximum -ne [int]$contract.expected.rawResistanceMaximum
    }).Count -eq 0) "p14.target-defense.authenticated-creature-profile-ranges"

$skills = Get-Content -LiteralPath $paths.skillTable -Raw
Assert-Contract ($skills.Contains("ranged_defense") -and
    $skills.Contains("melee_defense") -and
    $skills.Contains("unarmed_passive_defense")) `
    "p14.target-defense.classic-skill-mods-present"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.target-defense.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.target-defense.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.target-defense.direct-source-pin"
    Assert-Contract (@($contract.buildEvidence.compiledClassSha256.PSObject.Properties |
        Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0 -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.target-defense.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.target-defense.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.target-defense.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU target-dummy defense authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU target-dummy defense authority contract passed."
