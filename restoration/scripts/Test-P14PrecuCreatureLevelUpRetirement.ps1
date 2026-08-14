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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuCreatureLevelUpRetirement)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
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
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
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
    "Creature level-up retirement is not pinned to the checked-out direct source."

$paths = [ordered]@{}
$texts = @{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $root ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "Creature level-up source is missing: $($property.Name)"
    $paths[$property.Name] = $path
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($actualHash -ceq $expectedHash) `
        "Creature level-up source evidence drifted: $($property.Name)"
}

$patchPath = Join-Path $root ([string]$contract.buildEvidence.overlayPatch)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) `
    "Creature level-up retirement overlay is missing."
$patch = Get-Item -LiteralPath $patchPath
$patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatchBytes -and
    $patchHash -ceq [string]$contract.buildEvidence.overlayPatchSha256) `
    "Creature level-up retirement overlay evidence drifted."
& git -C $dsrcRoot apply --check --reverse --ignore-space-change --ignore-whitespace -- $patchPath
Assert-Contract ($LASTEXITCODE -eq 0) `
    "Creature level-up retirement overlay does not reverse cleanly from direct source."

$callback = Get-BracedSurface ([string]$texts.ai) `
    "public int OnIncapacitateTarget(obj_id self, obj_id victim) throws InterruptedException"
Assert-Contract ($callback.Contains("return SCRIPT_CONTINUE;") -and
    -not $callback.Contains("creatureLevelUp") -and
    -not $callback.Contains('"experienced"') -and
    -not $callback.Contains("rand(") -and
    -not $callback.Contains("setScriptVar") -and
    -not $callback.Contains("initializeCreature") -and
    -not $callback.Contains("getLevel(")) `
    "The production incapacitate callback regained kill-triggered creature progression."

$helper = Get-BracedSurface ([string]$texts.aiLibrary) `
    "public static void creatureLevelUp(obj_id creature, obj_id victim) throws InterruptedException"
$helperCode = [regex]::Replace($helper, '(?m)//.*$', '')
Assert-Contract (-not $helperCode.Contains(";") -and
    -not $helper.Contains("showFlyText") -and
    -not $helper.Contains("playClientEffectObj") -and
    -not $helper.Contains("initializeCreature") -and
    -not $helper.Contains("getLevel(") -and
    -not $helper.Contains("getCreatureName") -and
    -not $helper.Contains("setObjVar") -and
    -not $helper.Contains("setScriptVar") -and
    -not $helper.Contains("rand(")) `
    "The compatibility creatureLevelUp helper is not an inert link-compatible surface."

$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
$methodReferences = 0
$declarations = 0
$productionInvocations = 0
$diagnosticInvocations = 0
foreach ($javaFile in $javaFiles)
{
    $text = Get-Content -LiteralPath $javaFile.FullName -Raw
    $relative = $javaFile.FullName.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $methodReferences += [regex]::Matches($text, [string]$contract.inventory.methodPattern).Count
    $declarations += [regex]::Matches($text,
        '\bpublic\s+static\s+void\s+creatureLevelUp\s*\(').Count
    $invocations = [regex]::Matches($text, '\bai_lib\.creatureLevelUp\s*\(').Count
    if ($relative -match '^working/') { $diagnosticInvocations += $invocations }
    else { $productionInvocations += $invocations }
}
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources -and
    $methodReferences -eq [int]$contract.inventory.methodReferences -and
    $declarations -eq [int]$contract.inventory.declarations -and
    $productionInvocations -eq [int]$contract.inventory.productionInvocations -and
    $diagnosticInvocations -eq [int]$contract.inventory.dormantDiagnosticInvocations -and
    [regex]::Matches([string]$texts.diagnosticCaller,
        '\bai_lib\.creatureLevelUp\s*\(').Count -eq 1) `
    "Creature level-up callsite inventory drifted."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required creature level-up dependency is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required creature level-up dependency is not Ready: $dependencyName"
}

Assert-Contract ([string]$contract.semanticReference.pinnedCommit -ceq
        "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8" -and
    [int]$contract.expected.randomKillLevelRolls -eq 0 -and
    [int]$contract.expected.experiencedScriptVarReadsOrWrites -eq 0 -and
    [int]$contract.expected.creatureReinitializations -eq 0 -and
    [int]$contract.expected.levelUpFlyTextOrEffects -eq 0 -and
    [bool]$contract.expected.incapacitateCallbackReturnsWithoutMutation -and
    [bool]$contract.expected.compatibilityHelperSignaturePreserved -and
    [bool]$contract.expected.authoredCreatureProfilePreserved -and
    [bool]$contract.expected.laterZonesQuestsConversationsAndNpcContentPreserved) `
    "Creature level-up retirement expectation boundary is incomplete."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [string]$contract.buildEvidence.compiledClassSha256.ai -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.aiLibrary -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.sourceWorkParity -and
        [int]$contract.runtimeEvidence.productionKillLevelMutationCalls -eq 0 -and
        [int]$contract.runtimeEvidence.hostArtifactOrStagingDirectories -eq 0 -and
        $contract.requiredBeforeReady.Count -eq 0) `
        "Creature level-up retirement lacks complete Ready evidence."

    $container = [string]$contract.runtimeEvidence.container
    $health = (& docker inspect $container --format '{{.State.Health.Status}}').Trim()
    Assert-Contract ($LASTEXITCODE -eq 0 -and $health -ceq "healthy") `
        "Creature level-up runtime container is not healthy."
    $classHashes = @(& docker exec $container sh -c `
        "sha256sum /swg-precu/data/sku.0/sys.server/compiled/game/script/ai/ai.class /swg-precu/data/sku.0/sys.server/compiled/game/script/library/ai_lib.class")
    Assert-Contract ($LASTEXITCODE -eq 0 -and $classHashes.Count -eq 2 -and
        $classHashes[0].Split(' ', [StringSplitOptions]::RemoveEmptyEntries)[0] -ceq
            [string]$contract.buildEvidence.compiledClassSha256.ai -and
        $classHashes[1].Split(' ', [StringSplitOptions]::RemoveEmptyEntries)[0] -ceq
            [string]$contract.buildEvidence.compiledClassSha256.aiLibrary) `
        "Deployed creature level-up classes do not match Ready evidence."
    & docker exec $container sh -c `
        "cmp -s /swg-precu-source/dsrc/sku.0/sys.server/compiled/game/script/ai/ai.java /swg-precu/dsrc/sku.0/sys.server/compiled/game/script/ai/ai.java && cmp -s /swg-precu-source/dsrc/sku.0/sys.server/compiled/game/script/library/ai_lib.java /swg-precu/dsrc/sku.0/sys.server/compiled/game/script/library/ai_lib.java"
    Assert-Contract ($LASTEXITCODE -eq 0) `
        "Creature level-up source/work parity failed."
    $readyMarker = @(& docker logs $container 2>&1 | Select-String -SimpleMatch `
        "Cluster swg is ready for players.")
    Assert-Contract ($readyMarker.Count -ge 1) `
        "Creature level-up runtime lacks the player-ready cluster marker."
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "Creature level-up retirement source status is invalid."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Creature level-up retirement references prohibited host staging."
Write-Host "Publish 14.1 creature level-up retirement passed."
