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
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuProfessionAuthorityClosure)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$failures = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-TextSha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

function Get-SourceText([string]$RelativePath)
{
    return Get-Content -LiteralPath (Join-Path $dsrc $RelativePath) -Raw
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.profession-closure.overlay.exists"
$patchText = ""
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patchText = Get-Content -LiteralPath $patchPath -Raw
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    $patchLength = (Get-Item -LiteralPath $patchPath).Length
    Assert-Contract ($patchLength -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.profession-closure.overlay.authenticated"
}

$targets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Assert-Contract ($targets.Count -eq [int]$contract.expected.changedSourceFiles -and
    (@($targets | Select-Object -Unique).Count -eq $targets.Count)) `
    "p14.profession-closure.overlay.target-set"
$targetSetText = ($targets -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $targetSetText) -ceq [string]$contract.buildEvidence.sourceSetSha256) `
    "p14.profession-closure.source-set.authenticated"

$contentRecords = [System.Collections.Generic.List[string]]::new()
$changedTextBuilder = [System.Text.StringBuilder]::new()
foreach ($target in $targets)
{
    $path = Join-Path $dsrc $target
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.profession-closure.source.$target.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $contentRecords.Add("$target=$hash")
        [void]$changedTextBuilder.AppendLine((Get-Content -LiteralPath $path -Raw))
    }
}
$contentRecordText = ($contentRecords -join "`n") + "`n"
Assert-Contract ((Get-TextSha256 $contentRecordText) -ceq [string]$contract.buildEvidence.sourceContentSha256) `
    "p14.profession-closure.source-content.authenticated"
$changedText = $changedTextBuilder.ToString()

$officerRuntimeSources = [ordered]@{
    "sku.0/sys.server/compiled/game/script/ai/officer_pet.java" = "ai/officer_pet.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java" = "systems/combat/combat_base.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java" = "systems/combat/combat_actions.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_supply_drop_controller.java" = "systems/combat/combat_supply_drop_controller.java"
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_supply_drop_crate.java" = "systems/combat/combat_supply_drop_crate.java"
}
Assert-Contract ($officerRuntimeSources.Count -eq [int]$contract.expected.authoritativeOfficerRuntimeFiles -and
    @($contract.buildEvidence.officerRuntimeSourceSha256.PSObject.Properties).Count -eq
        $officerRuntimeSources.Count) `
    "p14.profession-closure.officer-runtime.source-count"
$officerTexts = [ordered]@{}
foreach ($property in $contract.buildEvidence.officerRuntimeSourceSha256.PSObject.Properties)
{
    $path = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $path -PathType Leaf) -and
        $officerRuntimeSources.Contains($property.Name) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq
            [string]$property.Value) `
        "p14.profession-closure.officer-runtime.source.$($property.Name).authenticated"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $officerTexts[$officerRuntimeSources[$property.Name]] = Get-Content -LiteralPath $path -Raw
    }
}

$combatBase = [string]$officerTexts["systems/combat/combat_base.java"]
$officerPredicate = Get-FunctionSlice $combatBase `
    "public static boolean isRetiredPostNgeOfficerPlayerAction" `
    "public boolean combatStandardAction"
Assert-Contract ($officerPredicate.Contains("isPlayer(self)") -and
    $officerPredicate.Contains('actionName.startsWith("of_")') -and
    $combatBase.Contains("if (isRetiredPostNgeOfficerPlayerAction(self, actionName))")) `
    "p14.profession-closure.officer-runtime.central-player-action-gate"

$combatActions = [string]$officerTexts["systems/combat/combat_actions.java"]
$officerHandlers = @([regex]::Matches(
    $combatActions,
    '(?ms)^\s*public int (of_[A-Za-z0-9_]+)\(.*?(?=^\s*public int |\z)'))
$standardOfficerHandlers = @($officerHandlers | Where-Object { $_.Value.Contains("combatStandardAction(") })
$directOfficerHandlers = @($officerHandlers | Where-Object { -not $_.Value.Contains("combatStandardAction(") })
$expectedDirectOfficerHandlers = @("of_last_words_recourse", "of_rally_point_def", "of_rally_point_off")
$actualDirectOfficerHandlers = @($directOfficerHandlers | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$directOfficerHandlersGuarded = @($directOfficerHandlers | Where-Object {
    $_.Value.Contains("isRetiredPostNgeOfficerPlayerAction(")
}).Count -eq $directOfficerHandlers.Count
Assert-Contract ($officerHandlers.Count -eq [int]$contract.expected.postNgeOfficerPlayerActionHandlers -and
    $standardOfficerHandlers.Count -eq [int]$contract.expected.postNgeOfficerStandardActionHandlers -and
    $directOfficerHandlers.Count -eq [int]$contract.expected.postNgeOfficerDirectCallbacks -and
    ($actualDirectOfficerHandlers -join "`n") -ceq ($expectedDirectOfficerHandlers -join "`n") -and
    $directOfficerHandlersGuarded) `
    "p14.profession-closure.officer-runtime.all-player-actions-covered"

$officerPet = [string]$officerTexts["ai/officer_pet.java"]
Assert-Contract (-not $officerPet.Contains("expertise_of_reinforcements_1") -and
    $officerPet.Contains("retirePostNgeOfficerPet") -and
    $officerPet.Contains("pet_lib.destroyOfficerPets(master)") -and
    $officerPet.Contains("destroyObject(self)")) `
    "p14.profession-closure.officer-runtime.persisted-pet-retired"

$supplyController = [string]$officerTexts["systems/combat/combat_supply_drop_controller.java"]
$controllerCallbacks = @("startLandingSequence", "dropReinforcements", "dropSupplies")
$controllerCallbacksGuarded = $true
foreach ($callback in $controllerCallbacks)
{
    $slice = Get-FunctionSlice $supplyController "public int $callback" "public int"
    if (-not $slice.Contains("retirePostNgeOfficerSupplyDrop(self, owner)"))
    {
        $controllerCallbacksGuarded = $false
    }
}
$summonOfficerPet = Get-FunctionSlice $supplyController "public void summonOfficerPet" `
    "public boolean retirePostNgeOfficerSupplyDrop"
Assert-Contract ($controllerCallbacksGuarded -and
    $summonOfficerPet.Contains("isPlayer(owner)") -and
    $summonOfficerPet.Contains("pet_lib.destroyOfficerPets(owner)") -and
    $summonOfficerPet.Contains("return;")) `
    "p14.profession-closure.officer-runtime.delayed-drops-and-hirelings-retired"

$supplyCrate = [string]$officerTexts["systems/combat/combat_supply_drop_crate.java"]
$crateTransfer = Get-FunctionSlice $supplyCrate "public int OnAboutToLoseItem" `
    "public boolean retirePostNgeOfficerSupplyCrate"
Assert-Contract ($supplyCrate.Contains("public int OnAttach") -and
    $supplyCrate.Contains("public int OnInitialize") -and
    $supplyCrate.Contains("retirePostNgeOfficerSupplyCrate(self)") -and
    $crateTransfer.Contains("isPlayer(transferer)") -and
    $crateTransfer.Contains("return SCRIPT_OVERRIDE;")) `
    "p14.profession-closure.officer-runtime.persisted-crate-retired"

$officerExpertiseReaders = @(Get-ChildItem -LiteralPath `
        (Join-Path $dsrc "sku.0/sys.server/compiled/game/script") -Recurse -File -Filter "*.java" |
    Where-Object { $_.FullName -notmatch '[\\/](?:test|working|beta)[\\/]' } |
    Select-String -SimpleMatch 'expertise_of_reinforcements_1')
Assert-Contract ($officerExpertiseReaders.Count -eq
    [int]$contract.expected.productionOfficerReinforcementExpertiseReaders) `
    "p14.profession-closure.officer-runtime.production-expertise-reader-absent"

$ngePattern = 'class_(?:bountyhunter|commando|domestics|engineering|entertainer|forcesensitive|medic|munitions|officer|smuggler|spy|structures|trader)'
$executableAuthorityText = [regex]::Replace(
    $changedText,
    '(?s)public static boolean isRetiredPostNgeSpySkill\(.*?(?=public static boolean grant\()',
    ''
)
Assert-Contract (-not [regex]::IsMatch($executableAuthorityText, $ngePattern)) `
    "p14.profession-closure.changed-executable-nge-authority.absent"

$productionRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/script"
$residual = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $productionRoot -Recurse -File -Filter "*.java")
{
    $relative = $file.FullName.Substring($dsrc.Length + 1).Replace('\', '/')
    if ($relative -match '/(?:test|working|beta)/') { continue }
    $matches = [regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), $ngePattern)
    if ($matches.Count -gt 0) { $residual[$relative] = $matches.Count }
}
$expectedResidual = $contract.expected.retainedCompatibilityBreakdown
$expectedResidualNames = @($expectedResidual.PSObject.Properties.Name | Sort-Object)
$actualResidualNames = @($residual.Keys | Sort-Object)
$residualCountsMatch = ($expectedResidualNames -join "`n") -ceq ($actualResidualNames -join "`n")
$residualTotal = 0
foreach ($name in $actualResidualNames)
{
    $residualTotal += [int]$residual[$name]
    $expectedProperty = $expectedResidual.PSObject.Properties[$name]
    if ($null -eq $expectedProperty -or [int]$expectedProperty.Value -ne [int]$residual[$name])
    {
        $residualCountsMatch = $false
    }
}
Assert-Contract ($residualCountsMatch -and
    $actualResidualNames.Count -eq [int]$contract.expected.retainedCompatibilityReferenceFiles -and
    $residualTotal -eq [int]$contract.expected.retainedCompatibilityReferences) `
    "p14.profession-closure.compatibility-only-residuals.exact"

$skillText = Get-SourceText "sku.0/sys.server/compiled/game/script/library/skill.java"
$phaseSlice = Get-FunctionSlice $skillText "public static int getProfessionPhase" "public static boolean validateExpertise"
Assert-Contract ($skillText.Contains("PRECU_PHASE_TWO_COMBAT_SCORE = 25") -and
    $skillText.Contains("PRECU_PHASE_THREE_COMBAT_SCORE = 50") -and
    $skillText.Contains("PRECU_PHASE_FOUR_COMBAT_SCORE = 75") -and
    $phaseSlice.Contains("getPrecuCombatSkillScore(player)") -and
    -not [regex]::IsMatch($phaseSlice, $ngePattern)) `
    "p14.profession-closure.phase.hidden-precu-combat-score"

$officerSkillsTable = Get-SourceText "sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$commandTable = Get-SourceText "sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatTable = Get-SourceText "sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$commandSeries = Get-SourceText "sku.0/sys.server/compiled/game/datatables/command/command_series.tab"
$creatureTable = Get-SourceText "sku.0/sys.server/compiled/game/datatables/mob/creatures.tab"
Assert-Contract (([regex]::Matches($officerSkillsTable, '(?m)^class_officer_').Count -eq
        [int]$contract.expected.retainedOfficerClassSkillRows) -and
    ([regex]::Matches($officerSkillsTable, '(?m)^expertise_of_').Count -eq
        [int]$contract.expected.retainedOfficerExpertiseSkillRows) -and
    ([regex]::Matches($commandTable, '(?m)^of_').Count -eq
        [int]$contract.expected.retainedOfficerCommandRows) -and
    ([regex]::Matches($combatTable, '(?m)^of_').Count -eq
        [int]$contract.expected.retainedOfficerCombatRows) -and
    ([regex]::Matches($commandSeries, '(?m)^of_').Count -eq
        [int]$contract.expected.retainedOfficerCommandSeriesRows) -and
    ([regex]::Matches($creatureTable, '(?m)^officer_reinforcement_').Count -eq
        [int]$contract.expected.retainedOfficerReinforcementCreatureRows)) `
    "p14.profession-closure.officer-runtime.compatibility-data-retained"

$utilsText = Get-SourceText "sku.0/sys.server/compiled/game/script/library/utils.java"
$professionSlice = Get-FunctionSlice $utilsText "public static int getPlayerProfession" "public static byte[] packObject"
$professionOrder = @("FORCE_SENSITIVE", "BOUNTY_HUNTER", "SMUGGLER", "COMMANDO", "OFFICER", "MEDIC", "ENTERTAINER", "TRADER")
$professionCursor = -1
$professionOrderValid = $true
foreach ($profession in $professionOrder)
{
    $professionCursor = $professionSlice.IndexOf("isProfession(player, $profession)", $professionCursor + 1, [System.StringComparison]::Ordinal)
    if ($professionCursor -lt 0) { $professionOrderValid = $false; break }
}
Assert-Contract ($professionOrderValid -and $professionSlice.Contains("return TRADER;") -and
    $professionSlice.Contains("return NO_PROFESSION;") -and
    -not [regex]::IsMatch($professionSlice, $ngePattern)) `
    "p14.profession-closure.singular-adapter.precu-ownership"
Assert-Contract ($utilsText.Contains('hasSkill(player, "combat_smuggler_underworld_01")') -and
    $utilsText.Contains('hasSkill(player, "social_language_wookiee_comprehend")')) `
    "p14.profession-closure.wookiee-language.precu-authority"

$singularConsumerFiles = @()
foreach ($file in Get-ChildItem -LiteralPath $productionRoot -Recurse -File -Filter "*.java")
{
    $relative = $file.FullName.Substring($dsrc.Length + 1).Replace('\', '/')
    if ($relative.EndsWith("/library/utils.java") -or $relative -match '/(?:test|working|beta)/') { continue }
    if ((Get-Content -LiteralPath $file.FullName -Raw).Contains("getPlayerProfession(")) { $singularConsumerFiles += $relative }
}
Assert-Contract ($singularConsumerFiles.Count -eq [int]$contract.expected.externalSingularCompatibilityConsumers -and
    ($singularConsumerFiles -contains "sku.0/sys.server/compiled/game/script/item/gcw_buff_banner/banner_buff_manager.java")) `
    "p14.profession-closure.singular-adapter.consumers-bounded"

$multiProfessionTokens = @(
    "utils.isProfession(breacher, utils.SMUGGLER)",
    "utils.isProfession(target, utils.SMUGGLER)",
    "utils.isProfession(target, utils.BOUNTY_HUNTER)",
    "utils.isProfession(objPilot, utils.SMUGGLER)",
    "!utils.isProfession(player, utils.SMUGGLER)"
)
$multiProfessionValid = $true
foreach ($token in $multiProfessionTokens) { if (-not $changedText.Contains($token)) { $multiProfessionValid = $false } }
Assert-Contract $multiProfessionValid "p14.profession-closure.multi-profession-predicates"

$skillsTable = Get-SourceText "sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$requiredSkills = @(
    "combat_smuggler_novice", "combat_smuggler_underworld_01", "combat_smuggler_underworld_02",
    "combat_smuggler_underworld_03", "combat_smuggler_underworld_04", "combat_smuggler_master",
    "combat_bountyhunter_novice", "combat_bountyhunter_investigation_01", "combat_bountyhunter_investigation_02",
    "combat_bountyhunter_investigation_04", "combat_bountyhunter_master", "outdoors_squadleader_novice",
    "social_entertainer_novice", "social_dancer_novice", "social_musician_novice",
    "crafting_artisan_novice", "crafting_artisan_domestic_04", "crafting_chef_novice", "crafting_tailor_novice",
    "crafting_armorsmith_novice", "crafting_armorsmith_master", "crafting_weaponsmith_novice",
    "crafting_weaponsmith_munitions_04", "crafting_weaponsmith_techniques_02", "crafting_weaponsmith_master",
    "crafting_droidengineer_novice", "crafting_droidengineer_techniques_01", "crafting_droidengineer_techniques_02",
    "crafting_droidengineer_master", "crafting_architect_novice", "crafting_shipwright_novice",
    "force_sensitive_crafting_mastery_novice", "science_medic_master", "science_doctor_novice", "science_doctor_master",
    "combat_commando_novice", "combat_commando_support_01", "combat_commando_support_02",
    "combat_commando_support_03", "combat_commando_support_04", "jedi_padawan_novice"
)
$allRequiredSkillsExist = $true
foreach ($skillName in $requiredSkills)
{
    if (-not [regex]::IsMatch($skillsTable, "(?m)^" + [regex]::Escape($skillName) + "`t")) { $allRequiredSkillsExist = $false }
}
Assert-Contract $allRequiredSkillsExist "p14.profession-closure.skills-table.authority-exists"

$saberFiles = @(Get-ChildItem -LiteralPath (Join-Path $productionRoot "systems/crafting/weapon/lightsaber") -File -Filter "crafting_melee_lightsaber*.java" |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw).Contains("REQUIRED_SKILLS") })
$saberAuthorityValid = $true
foreach ($file in $saberFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if (-not $text.Contains('"jedi_padawan_novice"') -or [regex]::IsMatch($text, $ngePattern)) { $saberAuthorityValid = $false }
}
Assert-Contract ($saberFiles.Count -eq [int]$contract.expected.lightsaberSchematicFiles -and $saberAuthorityValid) `
    "p14.profession-closure.lightsabers.padawan-root"

$groupText = (Get-SourceText "sku.0/sys.server/compiled/game/script/player/base/base_player.java") + "`n" +
    (Get-SourceText "sku.0/sys.server/compiled/game/script/library/xp.java")
Assert-Contract (([regex]::Matches($groupText, 'hasSkill\([^\r\n]+"outdoors_squadleader_novice"\)').Count -ge 3) -and
    -not $groupText.Contains("class_officer_phase")) `
    "p14.profession-closure.squad-leader.command-and-xp"
$registerText = Get-SourceText "sku.0/sys.server/compiled/game/script/player/cmd/register.java"
Assert-Contract ($registerText.Contains('hasSkill(self, "social_dancer_novice")') -and
    $registerText.Contains('hasSkill(self, "social_musician_novice")')) `
    "p14.profession-closure.entertainer.registration"

foreach ($property in $contract.buildEvidence.missionSourceSha256.PSObject.Properties)
{
    $missionPath = Join-Path $dsrc $property.Name
    Assert-Contract ((Test-Path -LiteralPath $missionPath -PathType Leaf) -and
        ((Get-FileHash -Algorithm SHA256 -LiteralPath $missionPath).Hash.ToLowerInvariant() -ceq [string]$property.Value)) `
        "p14.profession-closure.mission-source.$($property.Name).unchanged"
}
$missionTerminal = Get-SourceText "sku.0/sys.server/compiled/game/script/systems/missions/base/mission_terminal.java"
$missionBase = Get-SourceText "sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
Assert-Contract ($missionTerminal.Contains("menu_info_types.MISSION_TERMINAL_LIST") -and
    $missionBase.Contains("MAX_MISSIONS = 10") -and $missionBase.Contains("fullRewardEach=") -and
    $missionBase.Contains("split=false dailyCashPenalty=false")) `
    "p14.profession-closure.mission-terminal.continuity"

Assert-Contract (@("implemented-build-verified-live-pending", "ready") -ccontains
    [string]$contract.status) "p14.profession-closure.contract.status"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    $officerClassHashesValid = $null -ne $contract.buildEvidence.officerRuntimeClassEvidence -and
        @($contract.buildEvidence.officerRuntimeClassEvidence.PSObject.Properties |
            Where-Object { [string]$_.Value -notmatch '^[a-f0-9]{64}$' }).Count -eq 0
    Assert-Contract ([string]$manifest.sourceMode -ceq "direct-branch" -and
        $dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.profession-closure.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        $officerClassHashesValid -and
        [bool]$contract.runtimeEvidence.deployment.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.deployment.mappedNewlyBuiltBinary) `
        "p14.profession-closure.live-evidence"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.profession-closure.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "PRE-CU profession-authority closure contract failed: $($failures -join ', ')"
}
Write-Host "PRE-CU profession-authority closure contract passed ($($targets.Count) source files, $residualTotal compatibility-only NGE references)."
