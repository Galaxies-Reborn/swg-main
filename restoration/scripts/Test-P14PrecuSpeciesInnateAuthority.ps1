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
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuSpeciesInnateAuthority)
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

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { return "" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
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

function Get-CommaValues([object]$Value)
{
    return @(([string]$Value).Trim('"').Split(',') | Where-Object { $_ -cne "" })
}

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.species-innate.source.$([System.IO.Path]::GetFileName($path)).exists"
}
foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.species-innate.$($property.Name).authenticated"
}

$skillRows = @(Import-SwgTab -Path $paths.skills)
$speciesRows = @($skillRows | Where-Object {
    [string]$_.NAME -match '^species_(bothan|human|moncal|rodian|trandoshan|twilek|wookiee|zabrak|ithorian|sullustan)$'
})
Assert-Contract ($speciesRows.Count -eq 10) "p14.species-innate.all-species-present"
foreach ($property in $contract.expected.speciesInnates.PSObject.Properties)
{
    $row = @($speciesRows | Where-Object { [string]$_.NAME -ceq $property.Name })
    $commands = if ($row.Count -eq 1) { @(Get-CommaValues $row[0].COMMANDS) } else { @() }
    $mods = if ($row.Count -eq 1) { @(Get-CommaValues $row[0].SKILL_MODS) } else { @() }
    $expectedCommands = @($property.Value.commands | ForEach-Object { [string]$_ })
    $expectedMods = @($property.Value.skillMods | ForEach-Object { [string]$_ })
    $actualPrivateMods = @($mods | Where-Object { $_ -like 'private_innate_*' })
    Assert-Contract ($row.Count -eq 1 -and
        @($expectedCommands | Where-Object { $commands -cnotcontains $_ }).Count -eq 0 -and
        ($actualPrivateMods -join "`n") -ceq ($expectedMods -join "`n")) `
        "p14.species-innate.grant.$($property.Name)"
}
$activeInnates = @('regeneration', 'wookieeRoar', 'vitalize', 'equilibrium')
foreach ($speciesName in @($contract.expected.speciesWithNoActiveInnate))
{
    $row = @($speciesRows | Where-Object { [string]$_.NAME -ceq [string]$speciesName })
    $commands = if ($row.Count -eq 1) { @(Get-CommaValues $row[0].COMMANDS) } else { @() }
    Assert-Contract ($row.Count -eq 1 -and
        @($commands | Where-Object { $activeInnates -ccontains $_ }).Count -eq 0) `
        "p14.species-innate.no-cross-species-grant.$speciesName"
}
Assert-Contract (@($speciesRows | Where-Object {
    [string]$_.COMMANDS -match '_ability_1' -or [string]$_.SKILL_MODS -match '_ability_1'
}).Count -eq [int]$contract.expected.ngeSpeciesAbilityGrants) `
    "p14.species-innate.no-nge-species-ability-grants"
Assert-Contract (@($speciesRows | Where-Object {
    [string]$_.COMMANDS -match 'creature_harvesting' -or [string]$_.SKILL_MODS -match 'creature_harvesting'
}).Count -eq [int]$contract.expected.speciesCreatureHarvestingGrants) `
    "p14.species-innate.novice-scout-harvesting-boundary"

$commandRows = @(Import-SwgTab -Path $paths.commandTable)
$retiredSpeciesActions = @($contract.expected.retiredNgeSpeciesAbilityActions |
    ForEach-Object { [string]$_ })
Assert-Contract (@($commandRows | Where-Object {
    $retiredSpeciesActions -ccontains [string]$_.commandName
}).Count -eq [int]$contract.expected.retainedNgeSpeciesAbilityCommandRows) `
    "p14.species-innate.nge-command-compatibility-rows-preserved"
$commandExpected = [ordered]@{
    equilibrium = @('innate_equilibrium', '3600')
    regeneration = @('innate_regeneration', '3600')
    vitalize = @('innate_vitalize', '3600')
}
foreach ($name in $commandExpected.Keys)
{
    $row = @($commandRows | Where-Object { [string]$_.commandName -ceq $name })
    Assert-Contract ($row.Count -eq 1 -and
        [string]$row[0].cooldownGroup -ceq $commandExpected[$name][0] -and
        [string]$row[0].cooldownTime -ceq $commandExpected[$name][1]) `
        "p14.species-innate.cooldown.$name"
}
$roarCommand = @($commandRows | Where-Object { [string]$_.commandName -ceq 'wookieeRoar' })
Assert-Contract ($roarCommand.Count -eq 1 -and
    [string]$roarCommand[0].commandCategory -ceq 'combat' -and
    [string]$roarCommand[0].target -ceq 'enemy' -and
    [string]$roarCommand[0].targetType -ceq 'required' -and
    [string]$roarCommand[0].commandGroup -ceq 'combat_general' -and
    [string]$roarCommand[0].displayGroup -ceq 'combat' -and
    [string]$roarCommand[0].addToCombatQueue -ceq '1' -and
    [string]$roarCommand[0].validWeapon -ceq 'ALL' -and
    [string]$roarCommand[0].cooldownGroup -ceq 'innate_roar' -and
    [string]$roarCommand[0].warmupTime -ceq '0' -and
    [string]$roarCommand[0].executeTime -ceq '1' -and
    [string]$roarCommand[0].cooldownTime -ceq '300') `
    "p14.species-innate.wookiee-roar-command"

$buffRows = @(Import-SwgTab -Path $paths.buffTable)
$retiredSpeciesBuffRows = @($buffRows | Where-Object {
    $retiredSpeciesActions -ccontains [string]$_.NAME -or
        [string]$_.NAME -ceq 'invis_bothan_ability_1'
})
Assert-Contract ($retiredSpeciesBuffRows.Count -eq
    [int]$contract.expected.retainedNgeSpeciesAbilityBuffRows) `
    "p14.species-innate.nge-buff-compatibility-rows-preserved"
$regenBuff = @($buffRows | Where-Object { [string]$_.NAME -ceq 'innate_regeneration' })
$vitalizeBuff = @($buffRows | Where-Object { [string]$_.NAME -ceq 'innate_vitalize' })
$roarBuff = @($buffRows | Where-Object { [string]$_.NAME -ceq 'innate_wookiee_roar' })
Assert-Contract ($regenBuff.Count -eq 1 -and
    [string]$regenBuff[0].DURATION -ceq '300' -and
    [string]$regenBuff[0].EFFECT1_PARAM -ceq 'constitution' -and
    [string]$regenBuff[0].EFFECT1_VALUE -ceq '175') `
    "p14.species-innate.regeneration-effect"
Assert-Contract ($vitalizeBuff.Count -eq 1 -and
    [string]$vitalizeBuff[0].DURATION -ceq '600' -and
    [string]$vitalizeBuff[0].EFFECT1_PARAM -ceq 'health' -and
    [string]$vitalizeBuff[0].EFFECT1_VALUE -ceq '50' -and
    [string]$vitalizeBuff[0].EFFECT2_PARAM -ceq 'action' -and
    [string]$vitalizeBuff[0].EFFECT2_VALUE -ceq '50' -and
    [string]$vitalizeBuff[0].EFFECT3_PARAM -ceq 'mind' -and
    [string]$vitalizeBuff[0].EFFECT3_VALUE -ceq '50') `
    "p14.species-innate.vitalize-effect"
Assert-Contract ($roarBuff.Count -eq 1 -and
    @('EFFECT1_PARAM','EFFECT2_PARAM','EFFECT3_PARAM','EFFECT4_PARAM','EFFECT5_PARAM' |
        Where-Object { -not [string]::IsNullOrEmpty([string]$roarBuff[0].$_) }).Count -eq 0) `
    "p14.species-innate.nge-wookiee-self-buff-retired"

$combatRows = @(Import-SwgTab -Path $paths.combatData)
Assert-Contract (@($combatRows | Where-Object {
    $retiredSpeciesActions -ccontains [string]$_.actionName
}).Count -eq [int]$contract.expected.retainedNgeSpeciesAbilityCombatRows) `
    "p14.species-innate.nge-combat-compatibility-rows-preserved"
$roarCombat = @($combatRows | Where-Object { [string]$_.actionName -ceq 'wookieeRoar' })
Assert-Contract ($roarCombat.Count -eq 1 -and
    [string]$roarCombat[0].attackType -ceq 'CONE' -and
    [string]$roarCombat[0].coneLength -ceq '15' -and
    [string]$roarCombat[0].coneWidth -ceq '90' -and
    [string]$roarCombat[0].maxRange -ceq '15' -and
    [string]$roarCombat[0].healthCost -ceq '0' -and
    [string]$roarCombat[0].actionCost -ceq '0' -and
    [string]$roarCombat[0].mindCost -ceq '0' -and
    [string]$roarCombat[0].weaponType -ceq 'UNARMED' -and
    [string]$roarCombat[0].weaponCategory -ceq 'MELEE_WEAPON' -and
    [string]$roarCombat[0].hit_spam -ceq 'ACTION_NAME') `
    "p14.species-innate.wookiee-roar-combat-shape"
$overrideRows = @(Import-SwgTab -Path $paths.combatOverrides)
$roarOverride = @($overrideRows | Where-Object { [string]$_.actionName -ceq 'wookieeRoar' })
Assert-Contract ($roarOverride.Count -eq 1 -and
    [string]$roarOverride[0].targetPool -ceq 'NO_ATTRIBUTE' -and
    [string]$roarOverride[0].stateEffect1 -ceq 'INTIMIDATE' -and
    [string]$roarOverride[0].stateChance1 -ceq '100' -and
    [string]$roarOverride[0].stateDuration1 -ceq '60' -and
    [string]$roarOverride[0].stateDefense1 -ceq 'intimidate_defense' -and
    [string]$roarOverride[0].stateJediDefense1 -ceq 'jedi_state_defense' -and
    [string]$roarOverride[0].stateResistance1 -ceq 'resistance_states' -and
    [string]$roarOverride[0].accuracySkillMod -ceq 'intimidate') `
    "p14.species-innate.wookiee-roar-intimidate"
$spamRows = @(Import-SwgTab -Path $paths.combatSpam)
Assert-Contract (@($spamRows | Where-Object { [string]$_.actionName -ceq 'wookieeRoar' }).Count -eq 0 -and
    [bool]$contract.expected.wookieeRoarLocalizedActionNameFallback) `
    "p14.species-innate.wookiee-roar-localized-command-name"

$innateSource = Get-Content -LiteralPath $paths.innateLibrary -Raw
$speciesSource = Get-Content -LiteralPath $paths.speciesInnate -Raw
$combatSource = Get-Content -LiteralPath $paths.combatActions -Raw
$combatBaseSource = Get-Content -LiteralPath $paths.combatBase -Raw
$basePlayerSource = Get-Content -LiteralPath $paths.basePlayer -Raw
$equalize = Get-BracedSurface $innateSource 'public static void equalizeEffect'
$regenHandler = Get-BracedSurface $speciesSource 'public int cmdRegeneration'
$vitalizeHandler = Get-BracedSurface $speciesSource 'public int cmdVitalize'
$equilibriumHandler = Get-BracedSurface $speciesSource 'public int cmdEquilibrium'
$roarHandler = Get-BracedSurface $combatSource 'public int wookieeRoar'
Assert-Contract ($innateSource.Contains('DURATION_VIT = 600.0f') -and
    -not $innateSource.Contains('VALUE_EQUALIZE_AMOUNT') -and
    $equalize.Contains('int balancedValue = (health + action + mind) / 3') -and
    [regex]::Matches($equalize, 'addAttribModifier\(player, (HEALTH|ACTION|MIND),').Count -eq 3 -and
    -not $equalize.Contains('getLevel(')) "p14.species-innate.equilibrium-current-ham-authority"
Assert-Contract ($regenHandler.Contains('getSpecies(self) == SPECIES_TRANDOSHAN') -and
    $regenHandler.Contains('private_innate_regeneration') -and
    $vitalizeHandler.Contains('getSpecies(self) == SPECIES_ZABRAK') -and
    $vitalizeHandler.Contains('private_innate_vitalize') -and
    $equilibriumHandler.Contains('getSpecies(self) == SPECIES_ZABRAK') -and
    $equilibriumHandler.Contains('private_innate_equilibrium')) `
    "p14.species-innate.redundant-species-admission"
Assert-Contract ($speciesSource.Contains('queueCommand(self, (-1223315403), target') -and
    $roarHandler.Contains('getSpecies(self) != SPECIES_WOOKIEE') -and
    $roarHandler.Contains('private_innate_roar') -and
    $roarHandler.Contains('combatStandardAction("wookieeRoar"') -and
    $roarHandler.Contains('innate.SID_ROAR_ACTIVE') -and
    -not $roarHandler.Contains('getLevel(')) "p14.species-innate.wookiee-roar-runtime"

$retiredListStart = $combatBaseSource.IndexOf(
    'private static final String[] RETIRED_POST_NGE_SPECIES_PLAYER_ACTIONS',
    [StringComparison]::Ordinal)
$retiredListEnd = $combatBaseSource.IndexOf(
    'public static boolean isRetiredPostNgeSpeciesPlayerAction',
    [StringComparison]::Ordinal)
$retiredList = if ($retiredListStart -ge 0 -and $retiredListEnd -gt $retiredListStart)
{
    $combatBaseSource.Substring($retiredListStart, $retiredListEnd - $retiredListStart)
}
else { '' }
$listedActions = @([regex]::Matches($retiredList, '"([a-z]+_ability_1)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-Contract ($listedActions.Count -eq $retiredSpeciesActions.Count -and
    @($retiredSpeciesActions | Where-Object { $listedActions -cnotcontains $_ }).Count -eq 0 -and
    @('regeneration','wookieeRoar','vitalize','equilibrium' | Where-Object {
        $retiredList.Contains('"' + $_ + '"')
    }).Count -eq 0) "p14.species-innate.exact-nge-player-action-family"

$speciesGate = Get-BracedSurface $combatBaseSource `
    'public static boolean isRetiredPostNgeSpeciesPlayerAction'
$speciesCleanup = Get-BracedSurface $combatBaseSource `
    'public static void retirePostNgeSpeciesAbilityState'
$standardAction = Get-BracedSurface $combatBaseSource `
    'public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)'
$initializeHandler = Get-BracedSurface $basePlayerSource 'public int OnInitialize'
$loginHandler = Get-BracedSurface $basePlayerSource 'public int OnLogin'
$gateIndex = $standardAction.IndexOf(
    'isRetiredPostNgeSpeciesPlayerAction(self, actionName)', [StringComparison]::Ordinal)
$cleanupIndex = $standardAction.IndexOf(
    'retirePostNgeSpeciesAbilityState(self)', [StringComparison]::Ordinal)
$returnIndex = $standardAction.IndexOf('return false;', $cleanupIndex,
    [StringComparison]::Ordinal)
$combatEntryIndex = $standardAction.IndexOf('combat.revealPrecuFeignDeath',
    [StringComparison]::Ordinal)
Assert-Contract ($speciesGate.Contains('isPlayer(self)') -and
    $speciesGate.Contains('RETIRED_POST_NGE_SPECIES_PLAYER_ACTIONS') -and
    $speciesCleanup.Contains('while (hasCommand(player, retiredAction))') -and
    $speciesCleanup.Contains('revokeCommand(player, retiredAction)') -and
    $speciesCleanup.Contains('buff.removeBuff(player, retiredAction)') -and
    $speciesCleanup.Contains('buff.removeBuff(player, "invis_bothan_ability_1")') -and
    $speciesCleanup.Contains('utils.removeScriptVar(player, healing.VAR_PLAYER_HOT_ID)') -and
    $gateIndex -ge 0 -and $cleanupIndex -gt $gateIndex -and
    $returnIndex -gt $cleanupIndex -and $combatEntryIndex -gt $returnIndex) `
    "p14.species-innate.nge-player-runtime-fails-before-combat"
$loginCleanupIndex = $loginHandler.IndexOf(
    'script.systems.combat.combat_base.retirePostNgeSpeciesAbilityState(self)',
    [StringComparison]::Ordinal)
$loginMigrationIndex = $loginHandler.IndexOf(
    'script.player.live_conversions.retirePostNgePlayerMigrationState(self)',
    [StringComparison]::Ordinal)
$initializeCleanupIndex = $initializeHandler.IndexOf(
    'script.systems.combat.combat_base.retirePostNgeSpeciesAbilityState(self)',
    [StringComparison]::Ordinal)
$expertiseIndex = $initializeHandler.IndexOf('skill.validateExpertise(self)',
    [StringComparison]::Ordinal)
Assert-Contract ($loginMigrationIndex -ge 0 -and
    $loginCleanupIndex -gt $loginMigrationIndex -and
    $initializeCleanupIndex -ge 0 -and $expertiseIndex -gt $initializeCleanupIndex) `
    "p14.species-innate.login-scrubs-stale-command-and-buff-state"
$retiredHandlers = @($retiredSpeciesActions | ForEach-Object {
    Get-BracedSurface $combatSource ("public int " + $_)
})
Assert-Contract (@($retiredHandlers | Where-Object {
    [string]::IsNullOrEmpty($_) -or -not $_.Contains('combatStandardAction("')
}).Count -eq 0 -and
    ([regex]::Matches(($retiredHandlers -join "`n"), 'getLevel\(self\)').Count -eq
        [int]$contract.diagnosis.retainedNgeLevelScaledSpeciesAbilityHandlers) -and
    [int]$contract.expected.ngeSpeciesAbilityLevelReadsReachableByPlayers -eq 0) `
    "p14.species-innate.all-retained-handlers-dominated-by-player-gate"

if ($Expectation -eq 'Ready')
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq 'dsrc' })
    Assert-Contract ([string]$contract.status -ceq 'ready' -and
        [string]$contract.buildEvidence.result -ceq 'passed' -and
        [string]$contract.runtimeEvidence.result -ceq 'passed') `
        "p14.species-innate.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.species-innate.direct-source-pin"
    Assert-Contract (@($contract.buildEvidence.compiledClassSha256.PSObject.Properties |
        Where-Object { [string]$_.Value -match '^[a-f0-9]{64}$' }).Count -eq 5 -and
        @($contract.buildEvidence.compiledDataSha256.PSObject.Properties |
        Where-Object { [string]$_.Value -match '^[a-f0-9]{64}$' }).Count -eq 5 -and
        [bool]$contract.runtimeEvidence.compiledClassesPresent -and
        [bool]$contract.runtimeEvidence.compiledDataPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.species-innate.live-evidence"
}
else
{
    Assert-Contract (@('implemented-build-pending', 'implemented-build-verified-live-pending', 'ready') -contains
        [string]$contract.status) "p14.species-innate.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains('/Artifacts/') -and
    -not $contractText.Contains('/Staging/')) "p14.species-innate.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU species innate authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU species innate authority contract passed."
