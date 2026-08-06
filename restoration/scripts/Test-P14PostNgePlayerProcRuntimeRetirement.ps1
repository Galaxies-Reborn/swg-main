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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgePlayerProcRuntimeRetirement)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$serverGame = Join-Path $source "dsrc/sku.0/sys.server/compiled/game"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$procPath = Join-Path $serverGame "script/library/proc.java"
$expertisePath = Join-Path $serverGame "script/library/expertise.java"
$cyberneticPath = Join-Path $serverGame "script/library/cybernetic.java"
$procDataPath = Join-Path $serverGame "datatables/proc/proc.tab"
$cyberneticDataPath = Join-Path $serverGame "datatables/cybernetic/cybernetic.tab"
$weaponDataPath = Join-Path $serverGame "datatables/item/master_item/weapon_stats.tab"
$armorDataPath = Join-Path $serverGame "datatables/item/master_item/armor_stats.tab"
foreach ($path in @($procPath, $expertisePath, $cyberneticPath, $procDataPath, $cyberneticDataPath, $weaponDataPath, $armorDataPath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.player-proc.source.$([IO.Path]::GetFileName($path)).exists"
}

$procHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $procPath).Hash.ToLowerInvariant()
Assert-Contract ($procHash -ceq [string]$contract.buildEvidence.sourceSha256."library/proc.java") "p14.player-proc.source.authenticated"
$expertiseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $expertisePath).Hash.ToLowerInvariant()
Assert-Contract ($expertiseHash -ceq [string]$contract.buildEvidence.sourceSha256."library/expertise.java") "p14.player-proc.expertise-source.authenticated"
$cyberneticHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $cyberneticPath).Hash.ToLowerInvariant()
Assert-Contract ($cyberneticHash -ceq [string]$contract.buildEvidence.sourceSha256."library/cybernetic.java") "p14.player-proc.cybernetic-source.authenticated"
$procSource = Get-Content -LiteralPath $procPath -Raw
$expertiseSource = Get-Content -LiteralPath $expertisePath -Raw
$cyberneticSource = Get-Content -LiteralPath $cyberneticPath -Raw
$retirementFlag = Get-SourceSlice $procSource `
    "public static boolean isPostNgePlayerProcRuntimeRetired" `
    "public static boolean isRetiredPostNgePlayerProcActor"
$actorPredicate = Get-SourceSlice $procSource `
    "public static boolean isRetiredPostNgePlayerProcActor" `
    "public static void retirePostNgePlayerProcState"
$cleanup = Get-SourceSlice $procSource `
    "public static void retirePostNgePlayerProcState" `
    "public static void executeProcEffects(obj_id attacker, obj_id defender)"
$execute = Get-SourceSlice $procSource `
    "public static void executeProcEffects(obj_id attacker, obj_id defender, combat_data actionData)" `
    "public static void buildCurrentProcList"
$buildProc = Get-SourceSlice $procSource `
    "public static void buildCurrentProcList" `
    "public static void buildCurrentReacList"
$buildReac = Get-SourceSlice $procSource `
    "public static void buildCurrentReacList" `
    "}`n}"

Assert-Contract ($retirementFlag.Contains("return true;")) "p14.player-proc.retirement-flag"
Assert-Contract ($actorPredicate.Contains("isPostNgePlayerProcRuntimeRetired()") -and
    $actorPredicate.Contains("isIdValid(actor) && isPlayer(actor)")) "p14.player-proc.player-only-boundary"
foreach ($scriptVar in @("expertiseProcReacList", "currentProcList", "currentReacList", "procBuffEffects", "reacBuffEffects"))
{
    Assert-Contract ($cleanup.Contains('"' + $scriptVar + '"')) "p14.player-proc.cleanup.$scriptVar"
}
Assert-Contract ($cleanup.Contains('utils.removeScriptVarTree(player, "reactive_proc");')) "p14.player-proc.cleanup.reactive-cooldowns"
Assert-Contract ($execute.Contains("retirePostNgePlayerProcState(attacker);") -and
    $execute.Contains("retirePostNgePlayerProcState(defender);") -and
    $execute.IndexOf("retirePostNgePlayerProcState(attacker);", [System.StringComparison]::Ordinal) -lt
        $execute.IndexOf('utils.hasScriptVar(attacker, "currentProcList")', [System.StringComparison]::Ordinal) -and
    $execute.IndexOf("retirePostNgePlayerProcState(defender);", [System.StringComparison]::Ordinal) -lt
        $execute.IndexOf('utils.hasScriptVar(defender, "currentReacList")', [System.StringComparison]::Ordinal)) "p14.player-proc.execution-dominated"
Assert-Contract ($buildProc.Contains("if (isRetiredPostNgePlayerProcActor(player))") -and
    $buildProc.Contains("retirePostNgePlayerProcState(player);") -and
    $buildProc.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $buildProc.IndexOf("getCurrentWeapon(player)", [System.StringComparison]::Ordinal)) "p14.player-proc.list-build-dominated"
Assert-Contract ($buildReac.Contains("if (isRetiredPostNgePlayerProcActor(player))") -and
    $buildReac.Contains("retirePostNgePlayerProcState(player);") -and
    $buildReac.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $buildReac.IndexOf('"chest2"', [System.StringComparison]::Ordinal)) "p14.player-proc.reactive-build-dominated"
$expertiseCache = Get-SourceSlice $expertiseSource `
    "public static void cacheExpertiseProcReacList" `
    "public static void autoAllocateExpertiseByLevel"
Assert-Contract ($expertiseCache.Contains("if (proc.isRetiredPostNgePlayerProcActor(player))") -and
    $expertiseCache.Contains("proc.retirePostNgePlayerProcState(player);") -and
    $expertiseCache.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $expertiseCache.IndexOf("getSkillStatModListingForPlayer(player)", [System.StringComparison]::Ordinal) -and
    $expertiseCache.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $expertiseCache.IndexOf('utils.setScriptVar(player, "expertiseProcReacList"', [System.StringComparison]::Ordinal)) `
    "p14.player-proc.expertise-cache-dominated"

$cyberneticRetirement = Get-SourceSlice $cyberneticSource `
    "public static final String[] POST_NGE_CYBERNETIC_PLAYER_COMMANDS" `
    "public static final int CYBERNETIC_FULL_ARM_COST"
$cyberneticModifierInventory = Get-SourceSlice $cyberneticSource `
    "public static final String[] POST_NGE_CYBERNETIC_PLAYER_SKILL_MODIFIERS" `
    "public static final String[] POST_NGE_CYBERNETIC_PLAYER_BUFFS"
$cyberneticBuffInventory = Get-SourceSlice $cyberneticSource `
    "public static final String[] POST_NGE_CYBERNETIC_PLAYER_BUFFS" `
    "public static boolean isPostNgePlayerCyberneticCommandRuntimeRetired"
$cyberneticRunBoost = Get-SourceSlice $cyberneticSource `
    "public static void applyRunBoostMod" `
    "public static void grantSpecialCommands"
$cyberneticGrant = Get-SourceSlice $cyberneticSource `
    "public static void grantSpecialCommands" `
    "public static void revokeSpecialCommands"
$cyberneticCombatAccessors = Get-SourceSlice $cyberneticSource `
    "public static float getThrowRangeMod" `
    "public static void grantCyberneticSkillMods"
$cyberneticSkillModifiers = Get-SourceSlice $cyberneticSource `
    "public static void grantCyberneticSkillMods" `
    "public static void validateSkillMods"
$cyberneticValidate = Get-SourceSlice $cyberneticSource `
    "public static void validateSkillMods" `
    "public static void revokeAllOccurancesOfCommand"
$cyberneticExecution = Get-SourceSlice $cyberneticSource `
    "public static boolean hasUndamagedCybernetic" `
    "public static void verifyInstallPayment"
Assert-Contract ($cyberneticRetirement.Contains("return true;") -and
    $cyberneticRetirement.Contains("isIdValid(actor) && isPlayer(actor)") -and
    $cyberneticRetirement.Contains("while (hasCommand(player, retiredCommand))") -and
    $cyberneticRetirement.Contains("revokeCommand(player, retiredCommand);") -and
    $cyberneticRetirement.Contains("buff.removeBuff(player, retiredCommand);") -and
    $cyberneticRetirement.Contains("buff.removeBuff(player, retiredBuff);") -and
    $cyberneticRetirement.Contains("int currentValue = getSkillStatMod(player, retiredModifier);") -and
    $cyberneticRetirement.Contains("applySkillStatisticModifier(player, retiredModifier, -currentValue);")) `
    "p14.player-proc.cybernetic-player-cleanup"
$retiredCyberneticModifiers = @([regex]::Matches($cyberneticModifierInventory, '"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$expectedCyberneticModifiers = @($contract.diagnosis.retiredCyberneticPlayerSkillModifiers |
    ForEach-Object { [string]$_ } | Sort-Object -Unique)
$retiredCyberneticBuffs = @([regex]::Matches($cyberneticBuffInventory, '"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$expectedCyberneticBuffs = @($contract.diagnosis.retiredCyberneticPlayerBuffs |
    ForEach-Object { [string]$_ } | Sort-Object -Unique)
Assert-Contract (($retiredCyberneticModifiers -join ([char]0)) -ceq
    ($expectedCyberneticModifiers -join ([char]0)) -and
    ($retiredCyberneticBuffs -join ([char]0)) -ceq ($expectedCyberneticBuffs -join ([char]0))) `
    "p14.player-proc.cybernetic-modifier-inventory"
Assert-Contract ([regex]::Matches($cyberneticRunBoost,
        'if \(isRetiredPostNgePlayerCyberneticCommandActor\(player\)\)').Count -eq 2 -and
    [regex]::Matches($cyberneticRunBoost,
        'retirePostNgePlayerCyberneticCommandState\(player\);').Count -eq 2 -and
    $cyberneticRunBoost.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $cyberneticRunBoost.IndexOf("dataTableGetString", [System.StringComparison]::Ordinal) -and
    $cyberneticRunBoost.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $cyberneticRunBoost.IndexOf("buff.applyBuff", [System.StringComparison]::Ordinal)) `
    "p14.player-proc.cybernetic-movement-buff-dominated"
Assert-Contract ($cyberneticGrant.Contains("if (isRetiredPostNgePlayerCyberneticCommandActor(player))") -and
    $cyberneticGrant.Contains("retirePostNgePlayerCyberneticCommandState(player);") -and
    $cyberneticGrant.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $cyberneticGrant.IndexOf("dataTableGetString", [System.StringComparison]::Ordinal) -and
    $cyberneticGrant.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $cyberneticGrant.IndexOf("grantCommand", [System.StringComparison]::Ordinal)) `
    "p14.player-proc.cybernetic-grant-dominated"
Assert-Contract ([regex]::Matches($cyberneticCombatAccessors,
        'if \(isRetiredPostNgePlayerCyberneticCommandActor\(player\)\)').Count -eq 7 -and
    [regex]::Matches($cyberneticCombatAccessors, 'return maxRange;').Count -eq 4 -and
    [regex]::Matches($cyberneticCombatAccessors, 'return baseAccuracy;').Count -eq 4 -and
    [regex]::Matches($cyberneticCombatAccessors, 'return baseDefense;').Count -eq 2 -and
    $cyberneticCombatAccessors.Contains("return false;")) `
    "p14.player-proc.cybernetic-combat-consumers-neutral"
Assert-Contract ([regex]::Matches($cyberneticSkillModifiers,
        'if \(isRetiredPostNgePlayerCyberneticCommandActor\(player\)\)').Count -eq 2 -and
    [regex]::Matches($cyberneticSkillModifiers,
        'retirePostNgePlayerCyberneticCommandState\(player\);').Count -eq 2 -and
    $cyberneticSkillModifiers.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $cyberneticSkillModifiers.IndexOf("dataTableGetRow", [System.StringComparison]::Ordinal)) `
    "p14.player-proc.cybernetic-skill-modifier-writers-dominated"
Assert-Contract ($cyberneticValidate.Contains("retirePostNgePlayerCyberneticCommandState(player);") -and
    $cyberneticValidate.Contains("if (isRetiredPostNgePlayerCyberneticCommandActor(player))") -and
    $cyberneticValidate.IndexOf("retirePostNgePlayerCyberneticCommandState(player);", [System.StringComparison]::Ordinal) -lt
        $cyberneticValidate.IndexOf("getSkillStatMod", [System.StringComparison]::Ordinal) -and
    $cyberneticValidate.IndexOf("return;", [System.StringComparison]::Ordinal) -lt
        $cyberneticValidate.IndexOf("getInstalledCybernetics", [System.StringComparison]::Ordinal)) `
    "p14.player-proc.cybernetic-login-cleanup"
Assert-Contract ($cyberneticExecution.Contains("isRetiredPostNgePlayerCyberneticCommandActor(player)") -and
    $cyberneticExecution.Contains("isRetiredPostNgePlayerCyberneticCommand(commandName)") -and
    $cyberneticExecution.IndexOf("return false;", [System.StringComparison]::Ordinal) -lt
        $cyberneticExecution.IndexOf("getSpecificCybernetic", [System.StringComparison]::Ordinal)) `
    "p14.player-proc.cybernetic-execution-dominated"

$scriptRoot = Join-Path $serverGame "script"
$rebuildSites = 0
$rebuildConsumers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$expertiseCacheSites = 0
$expertiseCacheConsumers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$executionSites = 0
foreach ($javaFile in Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter "*.java" -File)
{
    $text = Get-Content -LiteralPath $javaFile.FullName -Raw
    $rebuildCount = [regex]::Matches($text, 'proc\.buildCurrent(?:Proc|Reac)List\(').Count
    if ($rebuildCount -gt 0)
    {
        $rebuildSites += $rebuildCount
        [void]$rebuildConsumers.Add($javaFile.FullName)
    }
    $expertiseCacheCount = [regex]::Matches($text, 'expertise\.cacheExpertiseProcReacList\(').Count
    if ($expertiseCacheCount -gt 0)
    {
        $expertiseCacheSites += $expertiseCacheCount
        [void]$expertiseCacheConsumers.Add($javaFile.FullName)
    }
    $executionSites += [regex]::Matches($text, 'proc\.executeProcEffects\(').Count
}
Assert-Contract ($rebuildSites -eq [int]$contract.diagnosis.directPlayerListRebuildCallSites -and
    $rebuildConsumers.Count -eq [int]$contract.diagnosis.directPlayerListRebuildConsumerFiles) "p14.player-proc.rebuild-inventory"
Assert-Contract ($executionSites -eq [int]$contract.diagnosis.combatProcExecutionCallSites) "p14.player-proc.execution-inventory"
Assert-Contract ($expertiseCacheSites -eq [int]$contract.diagnosis.directExpertiseCacheCallSites -and
    $expertiseCacheConsumers.Count -eq [int]$contract.diagnosis.directExpertiseCacheConsumerFiles) `
    "p14.player-proc.expertise-cache-inventory"

$procRows = @(Import-SwgTab -Path $procDataPath)
$cyberneticRows = @(Import-SwgTab -Path $cyberneticDataPath)
$weaponRows = @(Import-SwgTab -Path $weaponDataPath)
$armorRows = @(Import-SwgTab -Path $armorDataPath)
$weaponProcRows = @($weaponRows | Where-Object { [string]$_.proc_effect })
$cyberneticProcRows = @($cyberneticRows | Where-Object { [string]$_.procEffectString })
$cyberneticCommandRows = @($cyberneticRows | Where-Object { [string]$_.specialCommand })
$cyberneticMovementBuffRows = @($cyberneticRows | Where-Object { [string]$_.moveRateBuff })
$cyberneticCommandNames = @($cyberneticCommandRows.specialCommand | Sort-Object -Unique)
$expectedCyberneticCommandNames = @($contract.diagnosis.retiredCyberneticPlayerCommands | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$armorReactiveRows = @($armorRows | Where-Object { [string]$_.reactive_effect })
Assert-Contract ($procRows.Count -eq [int]$contract.diagnosis.procTableRows -and
    @($procRows.procString | Sort-Object -Unique).Count -eq [int]$contract.diagnosis.distinctProcCommands -and
    @($procRows | Where-Object { [string]$_.procChance -ceq "100" }).Count -eq [int]$contract.diagnosis.guaranteedProcRows) "p14.player-proc.proc-data-inventory"
Assert-Contract ($weaponProcRows.Count -eq [int]$contract.diagnosis.weaponRowsWithProcEffects -and
    @($weaponProcRows.proc_effect | Sort-Object -Unique).Count -eq [int]$contract.diagnosis.distinctWeaponProcEffects) "p14.player-proc.weapon-data-inventory"
Assert-Contract ($cyberneticRows.Count -eq [int]$contract.diagnosis.cyberneticRows -and
    $cyberneticProcRows.Count -eq [int]$contract.diagnosis.cyberneticRowsWithProcEffects -and
    $armorReactiveRows.Count -eq [int]$contract.diagnosis.armorRowsWithReactiveEffects) "p14.player-proc.equipment-data-inventory"
Assert-Contract ($cyberneticCommandRows.Count -eq [int]$contract.diagnosis.cyberneticRowsWithSpecialCommands -and
    $cyberneticCommandNames.Count -eq [int]$contract.diagnosis.distinctCyberneticSpecialCommands -and
    ($cyberneticCommandNames -join ([char]0)) -ceq ($expectedCyberneticCommandNames -join ([char]0))) `
    "p14.player-proc.cybernetic-command-data-inventory"
Assert-Contract ($cyberneticMovementBuffRows.Count -eq [int]$contract.diagnosis.cyberneticRowsWithMovementBuffs -and
    (@($cyberneticMovementBuffRows.moveRateBuff | Sort-Object -Unique) -join ([char]0)) -ceq
        ($expectedCyberneticBuffs -join ([char]0))) `
    "p14.player-proc.cybernetic-movement-buff-data-inventory"
foreach ($commandName in $expectedCyberneticCommandNames)
{
    Assert-Contract ($cyberneticRetirement.Contains('"' + $commandName + '"')) "p14.player-proc.cybernetic-command.$commandName.retired"
}

foreach ($evidence in @(
    @{ Path = $procDataPath; Hash = [string]$contract.continuityEvidence.procDataSha256; Name = "proc-data" },
    @{ Path = $cyberneticDataPath; Hash = [string]$contract.continuityEvidence.cyberneticDataSha256; Name = "cybernetic-data" },
    @{ Path = $weaponDataPath; Hash = [string]$contract.continuityEvidence.weaponDataSha256; Name = "weapon-data" },
    @{ Path = $armorDataPath; Hash = [string]$contract.continuityEvidence.armorDataSha256; Name = "armor-data" }
))
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $evidence.Path).Hash.ToLowerInvariant() -ceq $evidence.Hash) "p14.player-proc.$($evidence.Name).preserved"
}
foreach ($property in $contract.continuityEvidence.missionSourceSha256.PSObject.Properties)
{
    $path = Join-Path (Join-Path $serverGame "script") $property.Name
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ceq [string]$property.Value) "p14.player-proc.mission.$($property.Name).unchanged"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "p14.player-proc.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceCommit) "p14.player-proc.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256."library/proc.class" -cne "pending" -and
        [string]$contract.buildEvidence.compiledClassSha256."library/expertise.class" -cne "pending" -and
        [string]$contract.buildEvidence.compiledClassSha256."library/cybernetic.class" -cne "pending" -and
        [string]$contract.buildEvidence.fullJavaCompile -like "passed*") "p14.player-proc.compiled-evidence"
    Assert-Contract ([bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) "p14.player-proc.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) "p14.player-proc.source-status"
}

$contractText = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PostNgePlayerProcRuntimeRetirement)) -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) "p14.player-proc.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "Post-NGE player proc runtime retirement failed: $($failures -join ', ')"
}
Write-Host "Post-NGE player proc runtime retirement contract passed."
