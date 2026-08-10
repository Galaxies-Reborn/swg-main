[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Source", "Ready")][string]$Expectation = "Source"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuAiAggroRadiusAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing surface: $Signature" }
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

$paths = [ordered]@{}
$texts = @{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $root ([string]$property.Value)
}
foreach ($name in $paths.Keys)
{
    Assert-Contract (Test-Path -LiteralPath $paths[$name] -PathType Leaf) `
        "PRE-CU AI aggro source is missing: $name"
    $texts[$name] = Get-Content -LiteralPath $paths[$name] -Raw
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$name]).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
    Assert-Contract ($actualHash -ceq $expectedHash) `
        "PRE-CU AI aggro source evidence drifted: $name"
}

$dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
$srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
$dsrcCommit = (& git -C (Join-Path $root "dsrc") rev-parse HEAD).Trim()
$srcCommit = (& git -C (Join-Path $root "src") rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and
    $dsrcPin.Count -eq 1 -and $srcPin.Count -eq 1 -and
    [string]$dsrcPin[0].commit -ceq $dsrcCommit -and
    [string]$srcPin[0].commit -ceq $srcCommit -and
    $dsrcCommit -ceq [string]$contract.buildEvidence.directSourceCommit -and
    $srcCommit -ceq [string]$contract.buildEvidence.nativeSourceCommit) `
    "PRE-CU AI aggro authority is not pinned to checked-out source."

$aggroStatus = Get-BracedSurface ([string]$texts.aiAggro) `
    "public static int getAggroStatus(obj_id target)"
Assert-Contract ([regex]::Matches($aggroStatus, 'aiGetAggroRadius\(self\)').Count -eq
        [int]$contract.expected.productionAggroRadiusCallsInDistanceGate -and
    -not $aggroStatus.Contains("aiGetRespectRadius") -and
    $aggroStatus.Contains("final float distanceToTarget = getDistance(self, target);") -and
    $aggroStatus.Contains("if (distanceToTarget > aggroRadius)") -and
    $aggroStatus.Contains("OUT OF AGGRO RADIUS")) `
    "Production AI still uses post-P14 level-difference respect radius."
foreach ($preserved in @(
    "AGGRO_RADIUS_INTERIOR_VERTICAL",
    "pvpCanAttack(self, target)",
    "pvpIsEnemy(self, target)",
    "pet_lib.isCreaturePet(target)",
    "canSee(self, target)",
    "stealth.hasServerCoverState(target)",
    "storyteller.storytellerCombatCheck(self, target)"
))
{
    Assert-Contract ($aggroStatus.Contains($preserved)) `
        "PRE-CU AI aggro preserved behavior drifted: $preserved"
}

$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$productionRespectCalls = 0
foreach ($javaFile in @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java"))
{
    $relative = $javaFile.FullName.Substring($scriptRoot.Length + 1).Replace("\", "/")
    if ($relative -ceq "base_class.java" -or $relative -match '^test/') { continue }
    $productionRespectCalls += [regex]::Matches(
        (Get-Content -LiteralPath $javaFile.FullName -Raw), '\baiGetRespectRadius\s*\(').Count
}
Assert-Contract ($productionRespectCalls -eq [int]$contract.expected.productionRespectRadiusCalls -and
    [regex]::Matches([string]$texts.respectDiagnostic, '\baiGetRespectRadius\s*\(').Count -eq
        [int]$contract.expected.respectRadiusDiagnosticCalls) `
    "Respect-radius Java compatibility boundary drifted."

$aggroRadius = Get-BracedSurface ([string]$texts.aiController) `
    "float AICreatureController::getAggroRadius() const"
Assert-Contract ($aggroRadius.Contains("ConfigServerGame::getAiBaseAggroRadius()") -and
    $aggroRadius.Contains("m_aiCreatureData->m_aggressive") -and
    $aggroRadius.Contains("ConfigServerGame::getAiMaxAggroRadius()") -and
    -not $aggroRadius.Contains("getLevel()")) `
    "Authored/configured AI aggro radius authority drifted."
Assert-Contract ([string]$texts.aiLibrary -match 'createTriggerVolume\(ai_lib\.AGGRO_VOLUME_NAME, aiGetAggroRadius\(self\), false\)' -and
    [string]$texts.baseClass -match 'public static float aiGetAggroRadius\(obj_id ai\)' -and
    [string]$texts.scriptMethodsAi -match 'return aiCreatureController->getAggroRadius\(\);') `
    "AI aggro-radius transport is incomplete."

foreach ($dependencyName in @($contract.requiredReadyContracts))
{
    $dependencyPath = Join-Path $restorationRoot ("contracts/" + [string]$dependencyName)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required AI aggro dependency is missing: $dependencyName"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required AI aggro dependency is not Ready: $dependencyName"
}

if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        $contract.requiredBeforeReady.Count -eq 0) `
        "PRE-CU AI aggro authority lacks Ready evidence."
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "PRE-CU AI aggro authority lacks authenticated live x64 evidence."
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "PRE-CU AI aggro source status is invalid."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "PRE-CU AI aggro authority references prohibited host staging."
Write-Host "PRE-CU AI aggro-radius authority contract passed."
