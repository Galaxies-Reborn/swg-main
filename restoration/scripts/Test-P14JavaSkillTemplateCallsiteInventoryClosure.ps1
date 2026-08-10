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
$srcRoot = Join-Path $root "src"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14JavaSkillTemplateCallsiteInventoryClosure)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

function Assert-Contract
{
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-TextSha256
{
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
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
    if ($start -lt 0) { throw "Missing source surface: $Signature" }
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

$directPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$nativePin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$directCommit = (& git -C $dsrcRoot rev-parse HEAD).Trim()
$nativeCommit = (& git -C $srcRoot rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $directPin.Count -eq 1 -and $nativePin.Count -eq 1 -and
    [string]$directPin[0].commit -ceq $directCommit -and
    [string]$nativePin[0].commit -ceq $nativeCommit -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $nativeCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "Skill-template callsite closure is not pinned to the checked-out direct source."

$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"
$pattern = [string]$contract.inventory.pattern
$records = [System.Collections.Generic.List[object]]::new()
$playerLevelTableRecords = [System.Collections.Generic.List[object]]::new()
foreach ($file in $javaFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $lines = $text -split "`r?`n"
    $relative = $file.FullName.Substring($dsrcRoot.Length + 1).Replace("\", "/")
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; ++$lineIndex)
    {
        if ($lines[$lineIndex] -match '"datatables/player/player_level\.iff"')
        {
            $playerLevelTableRecords.Add([pscustomobject]@{
                Path = $relative
                Line = $lineIndex + 1
            })
        }
        if ($lines[$lineIndex] -notmatch $pattern) { continue }
        $records.Add([pscustomobject]@{
            Path = $relative
            Line = $lineIndex + 1
            Expression = $lines[$lineIndex].Trim()
            Category = ""
        })
    }
}

$sourceFiles = @($records.Path | Sort-Object -Unique)
$canonical = (@($records | Sort-Object Path, Line | ForEach-Object {
    "$($_.Path)|$($_.Expression)"
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
    "Residual Java skill-template/working-skill inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileProperties = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileProperties.Count) `
    "Residual Java template source-file set changed."
foreach ($property in $expectedFileProperties)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Residual Java template reference count drifted: $($property.Name)"
}

$actualLevelPaths = @($playerLevelTableRecords.Path | Sort-Object -Unique)
$expectedLevelPaths = @($contract.inventory.directPlayerLevelTablePaths | ForEach-Object { [string]$_ } | Sort-Object)
Assert-Contract ($playerLevelTableRecords.Count -eq [int]$contract.inventory.directPlayerLevelTableReads -and
    ($actualLevelPaths -join ([char]0)) -ceq ($expectedLevelPaths -join ([char]0))) `
    "Direct NGE player-level table consumer inventory drifted."

foreach ($record in $records)
{
    if ($record.Path -ceq "sku.0/sys.server/compiled/game/script/base_class.java")
    {
        $record.Category = "nativeScriptBridge"
    }
    elseif ($record.Path -match '/library/(respec|skill|skill_template|utils)\.java$' -or
        $record.Path -match '/player/live_conversions\.java$')
    {
        $record.Category = "retiredProductionCompatibility"
    }
    else
    {
        $record.Category = "adminTestDiagnostics"
    }
}
$classificationNames = @("nativeScriptBridge", "retiredProductionCompatibility", "adminTestDiagnostics")
$classifiedCount = 0
foreach ($category in $classificationNames)
{
    $classified = @($records | Where-Object { $_.Category -ceq $category } | Sort-Object Path, Line)
    $categoryCanonical = (@($classified | ForEach-Object {
        "$($_.Path)|$($_.Expression)"
    }) -join "`n") + "`n"
    $expected = $contract.classification.$category
    Assert-Contract ($classified.Count -eq [int]$expected.callSites -and
        (Get-TextSha256 $categoryCanonical) -ceq [string]$expected.inventorySha256) `
        "Residual Java template classification drifted: $category"
    $classifiedCount += $classified.Count
}
Assert-Contract ($classifiedCount -eq $records.Count -and
    [int]$contract.classification.unclassifiedCallSites -eq 0 -and
    [bool]$contract.expected.allCallSitesClassified -and
    [int]$contract.expected.productionTemplateProgressionAuthorityCallSites -eq 0) `
    "Residual Java template inventory is not fully closed."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required dependency is not Ready: $dependencyName"
}

$playerObjectPath = Join-Path $srcRoot "engine/server/library/serverGame/src/shared/object/PlayerObject.cpp"
$gameServerPath = Join-Path $srcRoot "engine/server/library/serverGame/src/shared/core/GameServer.cpp"
$controllerPath = Join-Path $srcRoot "engine/server/library/serverGame/src/shared/controller/PlayerCreatureController.cpp"
$playerObject = Get-Content -LiteralPath $playerObjectPath -Raw
$skillTemplateSetter = Get-BracedSurface $playerObject "bool PlayerObject::setSkillTemplate("
$workingSkillSetter = Get-BracedSurface $playerObject "bool PlayerObject::setWorkingSkill("
Assert-Contract ($skillTemplateSetter.Contains("m_skillTemplate.set(std::string());") -and
    -not $skillTemplateSetter.Contains("m_skillTemplate.set(templateName)") -and
    -not $skillTemplateSetter.Contains("TRIG_SKILL_TEMPLATE_CHANGED") -and
    $skillTemplateSetter.Contains("LfgCharacterData::Prof_Unknown") -and
    $workingSkillSetter.Contains("m_workingSkill.set(std::string());") -and
    -not $workingSkillSetter.Contains("m_workingSkill.set(skillName)") -and
    -not $workingSkillSetter.Contains("TRIG_WORKING_SKILL_CHANGED") -and
    -not [bool]$contract.expected.nativeSkillTemplateWritesNonEmpty -and
    -not [bool]$contract.expected.nativeWorkingSkillWritesNonEmpty) `
    "Native PlayerObject can repopulate retired NGE roadmap state."
$playerObjectHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $playerObjectPath).Hash.ToLowerInvariant()
Assert-Contract ($playerObjectHash -ceq [string]$contract.buildEvidence.nativePlayerObjectSha256) `
    "Native PlayerObject template authority source drifted."

$gameServer = Get-Content -LiteralPath $gameServerPath -Raw
$creationStart = $gameServer.IndexOf("play->setSkillTemplate(std::string(), true);", [StringComparison]::Ordinal)
$creationWorking = $gameServer.IndexOf("play->setWorkingSkill(std::string(), true);", $creationStart, [StringComparison]::Ordinal)
$creationSetup = $gameServer.IndexOf("PlayerCreationManagerServer::setupPlayer", $creationWorking, [StringComparison]::Ordinal)
Assert-Contract ($creationStart -ge 0 -and $creationWorking -gt $creationStart -and
    $creationSetup -gt $creationWorking) `
    "Character creation can persist retained client roadmap defaults."

$controller = Get-Content -LiteralPath $controllerPath -Raw
Assert-Contract (([regex]::Matches($controller,
        'playerOwner->setWorkingSkill\(msg->getCurrentWorkingSkill\(\), true\)')).Count -eq 1 -and
    ([regex]::Matches($controller,
        'playerOwner->setSkillTemplate\(msg->getProfessionTemplate\(\), true\)')).Count -eq 1 -and
    -not [bool]$contract.expected.clientMutationCallbacksBypassNativeClear) `
    "Client roadmap mutation messages bypass the native empty-state authority."

$baseClass = Get-Content -LiteralPath (Join-Path $scriptRoot "base_class.java") -Raw
foreach ($bridge in @(
    "_getSkillTemplate", "_setSkillTemplate", "_getWorkingSkill", "_setWorkingSkill"
))
{
    Assert-Contract ($baseClass.Contains($bridge)) "Generated native template bridge is missing: $bridge"
}

$respec = Get-Content -LiteralPath (Join-Path $scriptRoot "library/respec.java") -Raw
$utils = Get-Content -LiteralPath (Join-Path $scriptRoot "library/utils.java") -Raw
$conversions = Get-Content -LiteralPath (Join-Path $scriptRoot "player/live_conversions.java") -Raw
$skill = Get-Content -LiteralPath (Join-Path $scriptRoot "library/skill.java") -Raw
$basePlayer = Get-Content -LiteralPath (Join-Path $scriptRoot "player/base/base_player.java") -Raw
Assert-Contract ($respec.Contains("NGE_PLAYER_RESPEC_RUNTIME_RETIRED = true") -and
    ([regex]::Matches($respec, [regex]::Escape("if (retireNgePlayerRespecEntrypoint(player))"))).Count -eq 5 -and
    $utils.Contains("public static boolean isPostNgeCtsProgressionRestorationRetired()") -and
    $utils.Contains("if (isPostNgeCtsProgressionRestorationRetired())") -and
    $conversions.Contains("POST_NGE_PLAYER_MIGRATION_RUNTIME_RETIRED = true") -and
    (Get-BracedSurface $conversions "public int OnAttach(obj_id self)").Contains("return SCRIPT_CONTINUE;") -and
    ([regex]::Matches($basePlayer,
        'live_conversions\.retirePostNgePlayerMigrationState\(self\)')).Count -ge 4) `
    "Persisted or compatibility roadmap state can regain a production lifecycle entrypoint."
Assert-Contract ($skill.Contains("public static boolean grantPrecuSkillWithPrerequisites") -and
    $skill.Contains("isPrecuPublicProfessionSkillName(skillName)") -and
    $skill.Contains("public static boolean purchaseWorkingPrecuSkillForTesting") -and
    $skill.Contains("if (!isPrecuPublicProfessionSkillName(skillName))")) `
    "PRE-CU test helpers can grant an NGE class or expertise skill."

$diagnosticWrites = @($records | Where-Object {
    $_.Category -ceq "adminTestDiagnostics" -and
    $_.Path -notmatch '/test/precu_marksman_tier1_fixture\.java$' -and
    $_.Expression -match '(setSkillTemplate|setWorkingSkill)\s*\('
})
Assert-Contract ($diagnosticWrites.Count -eq 0) `
    "A retained admin diagnostic can write retired roadmap state."

Assert-Contract ([int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [bool]$contract.expected.laterContentAndDiagnosticsPreserved) `
    "The aggregate template closure claims an invalid mutation boundary."

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
        "Residual Java skill-template callsite closure is not Ready."
}

Write-Host "Publish 14.1 Java skill-template callsite inventory closure passed."
