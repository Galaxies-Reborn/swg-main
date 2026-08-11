[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrcRoot = Join-Path $root "dsrc"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14JavaPlayerLevelCallsiteInventoryClosure)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

function Assert-Contract
{
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-TextSha256
{
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BracedSurface
{
    param([string]$Text, [string]$Signature)
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing Java surface: $Signature" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { throw "Missing opening brace: $Signature" }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    throw "Missing closing brace: $Signature"
}

function Assert-OrderedGuard
{
    param([string]$Surface, [string]$Guard, [string]$Protected, [string]$Name)
    $guardIndex = $Surface.IndexOf($Guard, [StringComparison]::Ordinal)
    $protectedIndex = $Surface.IndexOf($Protected, [StringComparison]::Ordinal)
    Assert-Contract ($guardIndex -ge 0 -and $protectedIndex -gt $guardIndex) `
        "$Name does not fail closed before its residual level-bearing path."
}

$directPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$nativePin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$directCommit = (& git -C $dsrcRoot rev-parse HEAD).Trim()
$nativeCommit = (& git -C (Join-Path $root "src") rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $directPin.Count -eq 1 -and $nativePin.Count -eq 1 -and
    [string]$directPin[0].commit -ceq $directCommit -and
    [string]$nativePin[0].commit -ceq $nativeCommit -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $nativeCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "Player-level callsite closure is not pinned to the checked-out direct source."

$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"

$pattern = [string]$contract.inventory.pattern
$records = [System.Collections.Generic.List[object]]::new()
$globalCounts = [ordered]@{
    bhTauntDispatch = 0
    fsTauntDispatch = 0
    junkDealerInvocation = 0
    favorInvocation = 0
    externalEarnProfessionSkills = 0
    externalGetPercentageCompletion = 0
    externalSessionConversion = 0
    workingScriptAttachments = 0
}
foreach ($file in $javaFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $lines = $text -split "`r?`n"
    $relative = $file.FullName.Substring($dsrcRoot.Length + 1).Replace("\", "/")
    $globalCounts.bhTauntDispatch += [regex]::Matches($text, 'combat\.doBhTaunt\s*\(').Count
    $globalCounts.fsTauntDispatch += [regex]::Matches($text, 'combat\.dsFsTaunt\s*\(').Count
    $globalCounts.junkDealerInvocation += [regex]::Matches($text, 'if\s*\(\s*!callJunkDealer\(self\)\s*\)').Count
    $globalCounts.favorInvocation += [regex]::Matches($text, 'if\s*\(\s*!callFavor\(self,\s*[01]\)\s*\)').Count
    $globalCounts.externalEarnProfessionSkills += [regex]::Matches($text, 'respec\.earnProfessionSkills\s*\(').Count
    $globalCounts.externalGetPercentageCompletion += [regex]::Matches($text, 'respec\.getPercentageCompletion\s*\(').Count
    $globalCounts.externalSessionConversion += [regex]::Matches($text,
        '\.runOncePerSessionConversions\s*\(').Count
    $globalCounts.workingScriptAttachments += [regex]::Matches($text,
        'attachScript\s*\([^;]*("working\.(balancetest|dantest|difficultytest|reecetest)")').Count
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; ++$lineIndex)
    {
        if ($lines[$lineIndex] -notmatch $pattern) { continue }
        $method = ""
        for ($methodIndex = $lineIndex; $methodIndex -ge 0; --$methodIndex)
        {
            if ($lines[$methodIndex] -match '^\s*(public|private|protected)\s+.*\([^;]*$')
            {
                $method = $lines[$methodIndex].Trim()
                break
            }
        }
        Assert-Contract (-not [string]::IsNullOrWhiteSpace($method)) `
            "Could not classify method for $relative line $($lineIndex + 1)."
        $records.Add([pscustomobject]@{
            Path = $relative
            Line = $lineIndex + 1
            Method = $method
            Expression = $lines[$lineIndex].Trim()
            Category = ""
        })
    }
}

$sourceFiles = @($records.Path | Sort-Object -Unique)
$canonical = (@($records | Sort-Object Path, Line | ForEach-Object {
    "$($_.Path)|$($_.Method)|$($_.Expression)"
}) -join "`n") + "`n"
$sourceSet = ($sourceFiles -join "`n") + "`n"
$sourceContent = (@($sourceFiles | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dsrcRoot $_)).Hash.ToLowerInvariant()
    "$_=$hash"
}) -join "`n") + "`n"
Assert-Contract ($records.Count -eq [int]$contract.inventory.callSites -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-TextSha256 $canonical) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Residual Java player-level callsite inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileProperties = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileProperties.Count) `
    "Residual Java player-level source-file set changed."
foreach ($property in $expectedFileProperties)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Residual Java player-level count drifted: $($property.Name)"
}

foreach ($record in $records)
{
    if ($record.Path -match '/working/')
    {
        $record.Category = "dormantAdminDebug"
    }
    elseif ($record.Path -match '/systems/tcg/' -or
        ($record.Path -match '/ai/' -and $record.Path -notmatch 'beast_control_device'))
    {
        $record.Category = "nonPlayerContentObject"
    }
    elseif ($record.Path -match '/library/combat\.java$' -and
        $record.Method -match 'getActionCost|getDefender|getAttackerStrikethrough|getBlockAmmount')
    {
        $record.Category = "precuBypassedCombatFallback"
    }
    elseif ($record.Path -match '/library/(respec|utils)\.java$' -or
        $record.Path -match '/player/live_conversions\.java$' -or
        $record.Path -match '/systems/skills/auto_level\.java$')
    {
        $record.Category = "retiredProgression"
    }
    elseif ($record.Path -match '/library/combat\.java$' -or
        $record.Path -match '/systems/combat/(combat_actions|combat_base)\.java$')
    {
        $record.Category = "retiredNgeCombat"
    }
    else
    {
        $record.Category = "retiredRetainedContent"
    }
}

$classificationNames = @(
    "nonPlayerContentObject",
    "precuBypassedCombatFallback",
    "retiredProgression",
    "retiredNgeCombat",
    "retiredRetainedContent",
    "dormantAdminDebug"
)
$classifiedCount = 0
foreach ($category in $classificationNames)
{
    $classified = @($records | Where-Object { $_.Category -ceq $category } | Sort-Object Path, Line)
    $categoryCanonical = (@($classified | ForEach-Object {
        "$($_.Path)|$($_.Method)|$($_.Expression)"
    }) -join "`n") + "`n"
    $expected = $contract.classification.$category
    Assert-Contract ($classified.Count -eq [int]$expected.callSites -and
        (Get-TextSha256 $categoryCanonical) -ceq [string]$expected.inventorySha256) `
        "Residual Java player-level classification drifted: $category"
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $records.Count -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    [bool]$contract.expected.allCallSitesClassified -and
    [int]$contract.expected.playerLevelGameplayAuthorityCallSites -eq 0) `
    "Residual Java player-level inventory is not fully closed."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    $dependencyStatus = [string]$dependency.status
    $playerMigrationBuildPending = ($Expectation -ceq "Build" -and
        [string]$dependencyName -ceq "p14-post-nge-player-migration-authority-retirement.json" -and
        $dependencyStatus -ceq "implemented-build-pending")
    if ($playerMigrationBuildPending)
    {
        & (Join-Path $PSScriptRoot "Test-P14PostNgePlayerMigrationAuthorityRetirement.ps1") `
            -SourceRoot $root `
            -Expectation Build
    }
    Assert-Contract ($dependencyStatus -ceq "ready" -or $playerMigrationBuildPending) `
        "Required dependency is not Ready: $dependencyName"
}

$combatPath = Join-Path $scriptRoot "library/combat.java"
$combatActionsPath = Join-Path $scriptRoot "systems/combat/combat_actions.java"
$combatBasePath = Join-Path $scriptRoot "systems/combat/combat_base.java"
$heavyPath = Join-Path $scriptRoot "library/heavyweapons.java"
$respecPath = Join-Path $scriptRoot "library/respec.java"
$utilsPath = Join-Path $scriptRoot "library/utils.java"
$conversionPath = Join-Path $scriptRoot "player/live_conversions.java"
$autoLevelPath = Join-Path $scriptRoot "systems/skills/auto_level.java"
$basePlayerPath = Join-Path $scriptRoot "player/base/base_player.java"
$playerPvpPath = Join-Path $scriptRoot "systems/gcw/player_pvp.java"
$supplyPath = Join-Path $scriptRoot "systems/combat/combat_supply_drop_controller.java"
$beastPath = Join-Path $scriptRoot "library/beast_lib.java"
$beastDevicePath = Join-Path $scriptRoot "ai/beast_control_device.java"
$dantestPath = Join-Path $scriptRoot "working/dantest.java"
$combat = Get-Content -LiteralPath $combatPath -Raw
$combatActions = Get-Content -LiteralPath $combatActionsPath -Raw
$combatBase = Get-Content -LiteralPath $combatBasePath -Raw

$dictionaryCost = Get-BracedSurface $combat `
    "public static int[] getActionCost(obj_id self, weapon_data weaponData, dictionary actionData)"
$typedCost = Get-BracedSurface $combat `
    "public static int[] getActionCost(obj_id self, weapon_data weaponData, combat_data actionData)"
Assert-OrderedGuard $dictionaryCost 'if (actionData.getInt("precuHamCostModel") > 0)' `
    "getLevel(self)" "dictionary PRE-CU HAM routing"
Assert-OrderedGuard $typedCost "if (actionData.precuHamCostModel > 0)" `
    "getLevel(self)" "typed PRE-CU HAM routing"
foreach ($signature in @(
    "public static float getDefenderDodgeChance(obj_id player)",
    "public static float getDefenderParryChance(obj_id player)",
    "public static float getDefenderBlockChance(obj_id player)",
    "public static int getBlockAmmount(obj_id player)",
    "public static float getDefenderEvasionChance(obj_id player)",
    "public static float getAttackerStrikethroughChance(obj_id player)"
))
{
    $surface = Get-BracedSurface $combat $signature
    Assert-OrderedGuard $surface "isPlayer(player)" "getLevel(player)" $signature
}

$standardAction = Get-BracedSurface $combatBase `
    "public boolean combatStandardAction(String actionName, obj_id self, obj_id target, obj_id objWeapon, String params, combat_data actionData, boolean isTangibleAttacking, boolean testPetBar, int overloadDamage)"
foreach ($predicate in @(
    "isRetiredPostNgeSpeciesPlayerAction",
    "isRetiredPostNgeOfficerPlayerAction",
    "isRetiredPostNgeForceSensitivePlayerAction",
    "isRetiredPostNgeSmugglerPlayerAction",
    "isRetiredPostNgeBountyHunterPlayerAction"
))
{
    Assert-OrderedGuard $standardAction $predicate "combat_engine.getCombatData" `
        "central combat admission predicate $predicate"
}

foreach ($handler in @(
    [pscustomobject]@{ Signature="public int of_pistol_dm("; Guard='combatStandardAction("of_pistol_dm"'; Protected="getLevel(self)" },
    [pscustomobject]@{ Signature="public int of_pistol_bleed("; Guard='combatStandardAction("of_pistol_bleed"'; Protected="getLevel(self)" },
    [pscustomobject]@{ Signature="public int sm_buff_invis_ally_1("; Guard='combatStandardAction("sm_buff_invis_ally_1"'; Protected="getLevel(self)" },
    [pscustomobject]@{ Signature="public int ithorian_ability_1("; Guard='combatStandardAction("ithorian_ability_1"'; Protected="getLevel(self)" },
    [pscustomobject]@{ Signature="public int trandoshan_ability_1("; Guard='combatStandardAction("trandoshan_ability_1"'; Protected="getLevel(self)" },
    [pscustomobject]@{ Signature="public int zabrak_ability_1("; Guard='combatStandardAction("zabrak_ability_1"'; Protected="getLevel(self)" },
    [pscustomobject]@{ Signature="public int bh_taunt_1("; Guard='combatStandardAction("bh_taunt_1"'; Protected="combat.doBhTaunt" },
    [pscustomobject]@{ Signature="public int fs_taunt("; Guard='combatStandardAction("fs_taunt"'; Protected="combat.dsFsTaunt" },
    [pscustomobject]@{ Signature="public int sm_summon_smuggler("; Guard='combatStandardAction("sm_summon_smuggler"'; Protected="callFavor(self, 0)" },
    [pscustomobject]@{ Signature="public int sm_summon_medic("; Guard='combatStandardAction("sm_summon_medic"'; Protected="callFavor(self, 1)" },
    [pscustomobject]@{ Signature="public int sm_off_the_books("; Guard='combatStandardAction("sm_off_the_books"'; Protected="callJunkDealer(self)" }
))
{
    $surface = Get-BracedSurface $combatActions $handler.Signature
    Assert-OrderedGuard $surface $handler.Guard $handler.Protected $handler.Signature
}
Assert-Contract ($globalCounts.bhTauntDispatch -eq 1 -and
    $globalCounts.fsTauntDispatch -eq 1 -and
    $globalCounts.junkDealerInvocation -eq 1 -and
    $globalCounts.favorInvocation -eq 2) `
    "A residual level-bearing NGE combat helper gained an unclassified caller."

$heavy = Get-Content -LiteralPath $heavyPath -Raw
$heavyResolver = Get-BracedSurface $heavy `
    "public static String getHeavyWeaponDotName(obj_id player, int elementalDamageType, boolean singleTarget)"
Assert-OrderedGuard $heavyResolver "if (isPlayer(player))" "getLevel(player)" `
    "player heavy-weapon DOT tier retirement"

$utils = Get-Content -LiteralPath $utilsPath -Raw
$cts = Get-BracedSurface $utils "public static void updateRespecCTSObjvars"
Assert-OrderedGuard $cts "if (isPostNgeCtsProgressionRestorationRetired())" `
    "getLevel(player)" "CTS NGE progression retirement"

$respec = Get-Content -LiteralPath $respecPath -Raw
Assert-Contract ($respec.Contains("NGE_PLAYER_RESPEC_RUNTIME_RETIRED = true") -and
    ([regex]::Matches($respec, [regex]::Escape("if (retireNgePlayerRespecEntrypoint(player))"))).Count -eq 5 -and
    $globalCounts.externalEarnProfessionSkills -eq 0 -and
    $globalCounts.externalGetPercentageCompletion -eq 0) `
    "NGE respec compatibility helpers regained player progression authority."

$conversions = Get-Content -LiteralPath $conversionPath -Raw
$conversionAttach = Get-BracedSurface $conversions "public int OnAttach(obj_id self)"
$conversionInitialize = Get-BracedSurface $conversions "public int OnInitialize(obj_id self)"
$conversionLogin = Get-BracedSurface $conversions "public int OnLogin(obj_id self)"
Assert-Contract ($conversionAttach.Contains("return SCRIPT_CONTINUE;") -and
    -not $conversionAttach.Contains("runOncePerSessionConversions") -and
    $conversionInitialize.Contains('detachScript(self, "player.live_conversions")') -and
    $conversionLogin.Contains('detachScript(self, "player.live_conversions")') -and
    $globalCounts.externalSessionConversion -eq 0) `
    "NGE live-conversion callbacks or session conversion regained player authority."

$autoLevel = Get-Content -LiteralPath $autoLevelPath -Raw
foreach ($signature in @("public int OnObjectMenuSelect(", "public int handlerSuiAutoLevel("))
{
    $surface = Get-BracedSurface $autoLevel $signature
    Assert-OrderedGuard $surface "if (!isNgeAutoLevelItemEnabled())" `
        "getLevel(player)" "NGE auto-level item retirement"
}

$basePlayer = Get-Content -LiteralPath $basePlayerPath -Raw
$enterRegion = Get-BracedSurface $basePlayer "public int OnEnterRegion("
Assert-OrderedGuard $enterRegion "if (gcw.isPostNgeQueuedBattlefieldRetired()" `
    "getLevel(self)" "queued battlefield region retirement"
$playerPvp = Get-Content -LiteralPath $playerPvpPath -Raw
$battlefieldSui = Get-BracedSurface $playerPvp "public void battlefieldCommandSui("
Assert-OrderedGuard $battlefieldSui "if (gcw.isPostNgeQueuedBattlefieldRetired())" `
    "getLevel(self)" "queued battlefield command retirement"

$supply = Get-Content -LiteralPath $supplyPath -Raw
$drop = Get-BracedSurface $supply "public int dropSupplies("
Assert-OrderedGuard $drop "if (retirePostNgeOfficerSupplyDrop(self, owner))" `
    "getLevel(owner)" "Officer supply-drop retirement"

$beast = Get-Content -LiteralPath $beastPath -Raw
$enzyme = Get-BracedSurface $beast `
    "public static obj_id generateTypeThreeEnzyme(obj_id player, obj_id target, float enzymePurity, float enzymeMutagen, String trait)"
Assert-OrderedGuard $enzyme "if (isRetiredPostNgeBeastMasterPlayer(player))" `
    "getLevel(player)" "Beast Master enzyme retirement"
$beastDevice = Get-Content -LiteralPath $beastDevicePath -Raw
$beastMenu = Get-BracedSurface $beastDevice "public int OnObjectMenuSelect("
Assert-OrderedGuard $beastMenu "if (beast_lib.isRetiredPostNgeBeastMasterPlayer(player))" `
    "getLevel(player)" "Beast Master control-device retirement"

$dantest = Get-Content -LiteralPath $dantestPath -Raw
Assert-Contract ($globalCounts.workingScriptAttachments -eq 0 -and
    $dantest.Contains('if (!isGod(self) || getGodLevel(self) < 50 || !isPlayer(self))') -and
    $dantest.Contains('detachScript(self, "working.dantest")')) `
    "Dormant working-script level reads gained production player attachment authority."

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [bool]$contract.expected.laterZonesQuestsConversationsAndNpcCompatibilityPreserved) `
    "The aggregate closure claims an invalid mutation boundary."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.architecture -like "ELF 64-bit*" -and
        [string]$contract.buildEvidence.serverBinarySha256 -ceq
            "e126d8f5b0ff65bb908d2bce7922282aaceb4d2eaf454adbeb3eb51ff61720f8" -and
        [string]$contract.buildEvidence.serverBinaryBuildId -ceq
            "0ac0c8a439a388150c4a0f687874d1b38edc9eed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.containerHealth -ceq "healthy" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [int]$contract.runtimeEvidence.javaSources -eq 5717 -and
        [int]$contract.runtimeEvidence.javaClasses -eq 5751 -and
        [int]$contract.runtimeEvidence.liveGameProcessCount -eq 15 -and
        [int]$contract.runtimeEvidence.livePlanetProcessCount -eq 15 -and
        [long]$contract.runtimeEvidence.liveBinaryInode -eq 12141610 -and
        [long]$contract.runtimeEvidence.liveBinaryBytes -eq 22561064 -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Residual Java player-level callsite closure is not Ready."
}

Write-Host "Publish 14.1 Java player-level callsite inventory closure passed."
