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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14JavaPlayerLevelTableServiceRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Get-TextSha256([string]$Text)
{
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        return ([BitConverter]::ToString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
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
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    throw "Missing closing brace: $Signature"
}

function Assert-Ordered([string]$Text, [string[]]$Needles, [string]$Label)
{
    $cursor = -1
    foreach ($needle in $Needles)
    {
        $cursor = $Text.IndexOf($needle, $cursor + 1, [StringComparison]::Ordinal)
        Assert-Contract ($cursor -ge 0) "$Label lost ordered boundary: $needle"
    }
}

$directPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$directCommit = (& git -C $dsrcRoot rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    $directPin.Count -eq 1 -and
    [string]$directPin[0].commit -ceq $directCommit -and
    $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit) `
    "Java player-level table retirement is not pinned to checked-out direct source."

$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"
$pattern = [string]$contract.inventory.pattern
$records = [System.Collections.Generic.List[object]]::new()
$allText = [Text.StringBuilder]::new()
foreach ($file in $javaFiles)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    [void]$allText.Append($text).Append("`n")
    $lines = $text -split "`r?`n"
    $relative = $file.FullName.Substring($dsrcRoot.Length + 1).Replace("\", "/")
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
        $category = if ($relative -match '/player_levels\.java$')
        {
            "compatibilityImplementation"
        }
        else
        {
            "retiredRespecConsumer"
        }
        $records.Add([pscustomobject]@{
            Path = $relative
            Line = $lineIndex + 1
            Method = $method
            Expression = $lines[$lineIndex].Trim()
            Category = $category
        })
    }
}

$sourceFiles = @($records.Path | Sort-Object -Unique)
$canonical = (@($records | Sort-Object Path, Line | ForEach-Object {
    "$($_.Path)|$($_.Method)|$($_.Expression)"
}) -join "`n") + "`n"
$sourceSet = ($sourceFiles -join "`n") + "`n"
$sourceContent = (@($sourceFiles | ForEach-Object {
    "$_=" + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dsrcRoot $_)).Hash.ToLowerInvariant()
}) -join "`n") + "`n"
Assert-Contract ($records.Count -eq [int]$contract.inventory.callSites -and
    $sourceFiles.Count -eq [int]$contract.inventory.sourceFiles -and
    (Get-TextSha256 $canonical) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 $sourceSet) -ceq [string]$contract.inventory.sourceSetSha256 -and
    (Get-TextSha256 $sourceContent) -ceq [string]$contract.inventory.sourceContentSha256) `
    "Java player-level table callsite inventory drifted."

$actualFileCounts = @{}
foreach ($group in @($records | Group-Object Path)) { $actualFileCounts[$group.Name] = $group.Count }
$expectedFileProperties = @($contract.inventory.fileCounts.PSObject.Properties)
Assert-Contract ($actualFileCounts.Count -eq $expectedFileProperties.Count) `
    "Java player-level table source-file set changed."
foreach ($property in $expectedFileProperties)
{
    Assert-Contract ($actualFileCounts.ContainsKey($property.Name) -and
        [int]$actualFileCounts[$property.Name] -eq [int]$property.Value) `
        "Java player-level table count drifted: $($property.Name)"
}
foreach ($category in @("compatibilityImplementation", "retiredRespecConsumer"))
{
    $classified = @($records | Where-Object { $_.Category -ceq $category } | Sort-Object Path, Line)
    $categoryCanonical = (@($classified | ForEach-Object {
        "$($_.Path)|$($_.Method)|$($_.Expression)"
    }) -join "`n") + "`n"
    $expected = $contract.classification.$category
    Assert-Contract ($classified.Count -eq [int]$expected.callSites -and
        (Get-TextSha256 $categoryCanonical) -ceq [string]$expected.inventorySha256) `
        "Java player-level table classification drifted: $category"
}
Assert-Contract ([int]$contract.classification.unclassifiedCallSites -eq 0) `
    "Java player-level table inventory is not completely classified."

$playerLevelsPath = Join-Path $scriptRoot "player_levels.java"
$skillPath = Join-Path $scriptRoot "library/skill.java"
$respecPath = Join-Path $scriptRoot "library/respec.java"
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $playerLevelsPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."player_levels.java" -and
    (Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant() -ceq
    [string]$contract.buildEvidence.sourceSha256."skill.java") `
    "Java player-level table source evidence drifted."

$playerLevels = Get-Content -LiteralPath $playerLevelsPath -Raw
$skill = Get-Content -LiteralPath $skillPath -Raw
$respec = Get-Content -LiteralPath $respecPath -Raw
$levelPublic = Get-BracedSurface $playerLevels "public static level_data getPlayerLevelData"
$templatePublic = Get-BracedSurface $playerLevels "public static skill_template_data getSkillTemplateData"
$levelPrivate = Get-BracedSurface $playerLevels "private static level_data loadLevelData"
$templatePrivate = Get-BracedSurface $playerLevels "private static skill_template_data loadSkillTemplateData"
foreach ($surface in @($levelPublic, $templatePublic))
{
    Assert-Contract ($surface.Contains("return null;") -and
        -not $surface.Contains("dataTableGetRow") -and
        -not $surface.Contains("Cache") -and
        -not $surface.Contains("loadLevelData(") -and
        -not $surface.Contains("loadSkillTemplateData(")) `
        "A public Java player-level loader regained NGE data authority."
}
Assert-Contract ($levelPrivate.Contains('datatables/skill/levels.iff') -and
    $templatePrivate.Contains('datatables/skill_template/skill_template.iff') -and
    [bool]$contract.expected.privateCompatibilityLoadersPreserved) `
    "Private later-era compatibility loaders were not preserved."

$globalJava = $allText.ToString()
Assert-Contract (([regex]::Matches($globalJava, 'player_levels\.getPlayerLevelData\s*\(')).Count -eq
    [int]$contract.expected.externalPlayerLevelDataConsumers -and
    ([regex]::Matches($globalJava, 'player_levels\.getSkillTemplateData\s*\(')).Count -eq
    [int]$contract.expected.externalSkillTemplateDataConsumers -and
    ([regex]::Matches($globalJava, 'skill\.getProfessionName\s*\(')).Count -eq
    [int]$contract.expected.skillProfessionNameConsumers) `
    "Java player-level table service gained an unclassified external consumer."

$professionName = Get-BracedSurface $skill "public static String getProfessionName(String strTemplate)"
Assert-Ordered $professionName @(
    "player_levels.getSkillTemplateData(strTemplate)",
    "if (professionData == null)",
    "return null;",
    "return professionData.strClassName;"
) "skill profession-name compatibility bridge"
$setVersion = Get-BracedSurface $respec "public static boolean setRespecVersion(obj_id player)"
$getVersion = Get-BracedSurface $respec "public static int getRespecVersion(obj_id player)"
Assert-Ordered $setVersion @(
    "getSkillTemplate(player)",
    "skill.getProfessionName(skillTemplate)",
    "if (profession == null || skillTemplate == null)",
    "return false;",
    "setObjVar(player, EXPERTISE_VERSION_OBJVAR, version)"
) "respec version writer"
Assert-Ordered $getVersion @(
    "getSkillTemplate(player)",
    "skill.getProfessionName(skillTemplate)",
    "if (profession == null || skillTemplate == null)",
    "return -1;",
    "dataTableSearchColumnForString"
) "respec version reader"
Assert-Contract (-not [bool]$contract.expected.respecVersionMutationReachable) `
    "Contract unexpectedly authorizes NGE respec-version mutation."

foreach ($dependency in @($contract.requiredReadyContracts))
{
    $dependencyContract = Get-Content -LiteralPath (Join-Path $restorationRoot ("contracts/" + $dependency)) -Raw |
        ConvertFrom-Json
    Assert-Contract ([string]$dependencyContract.status -ceq "ready") `
        "Required player-level retirement contract is not Ready: $dependency"
}

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Java player-level table retirement lacks Ready evidence."
    $container = [string]$contract.runtimeEvidence.container
    $classRoot = "/swg-precu/data/sku.0/sys.server/compiled/game"
    $classPath = "$classRoot/script/player_levels.class"
    $classHash = ((& docker exec $container sha256sum $classPath) -split '\s+')[0]
    $classBytes = [int64]((& docker exec $container stat -c "%s" $classPath).Trim())
    $bytecode = (& docker exec $container javap -classpath $classRoot -c -p script.player_levels | Out-String)
    $publicLevelBytecode = $bytecode.Substring($bytecode.IndexOf(
        "public static script.player_levels`$level_data getPlayerLevelData"))
    $publicLevelBytecode = $publicLevelBytecode.Substring(0,
        $publicLevelBytecode.IndexOf("private static script.player_levels`$level_data loadLevelData"))
    $publicTemplateBytecode = $bytecode.Substring($bytecode.IndexOf(
        "public static script.player_levels`$skill_template_data getSkillTemplateData"))
    $publicTemplateBytecode = $publicTemplateBytecode.Substring(0,
        $publicTemplateBytecode.IndexOf("private static script.player_levels`$skill_template_data loadSkillTemplateData"))
    Assert-Contract ($classHash -ceq [string]$contract.buildEvidence.classSha256 -and
        $classBytes -eq [int64]$contract.buildEvidence.classBytes -and
        $publicLevelBytecode -match '0:\s+aconst_null\s+1:\s+areturn' -and
        $publicTemplateBytecode -match '0:\s+aconst_null\s+1:\s+areturn') `
        "Deployed player_levels bytecode does not hard-retire both public loaders."
    & docker exec $container cmp -s "/swg-precu-source/dsrc/sku.0/sys.server/compiled/game/script/player_levels.java" `
        "/swg-precu/dsrc/sku.0/sys.server/compiled/game/script/player_levels.java"
    Assert-Contract ($LASTEXITCODE -eq 0) "Direct/work player_levels source parity failed."
    $state = (& docker inspect --format "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $container).Trim()
    $processNames = @(& docker exec $container ps -eo comm= | ForEach-Object { $_.Trim() })
    Assert-Contract ($state -ceq "running healthy" -and
        @($processNames | Where-Object { $_ -ceq "SwgGameServer" }).Count -eq
            [int]$contract.runtimeEvidence.liveGameProcessCount -and
        @($processNames | Where-Object { $_ -ceq "PlanetServer" }).Count -eq
            [int]$contract.runtimeEvidence.livePlanetProcessCount) `
        "Deployed PRE-CU x64 runtime topology drifted."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) `
        "Java player-level table retirement is not build-eligible."
}

Write-Host "Publish 14.1 Java player-level table service retirement passed."
