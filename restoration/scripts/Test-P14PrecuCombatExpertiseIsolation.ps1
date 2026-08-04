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
    ([string]$manifest.contracts.p14PrecuCombatExpertiseIsolation)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
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

$texts = [ordered]@{}
$paths = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    $paths[$property.Name] = $path
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.combat-expertise-isolation.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.combat-expertise-isolation.source.$($property.Name).authenticated"
}

$combatLibrary = [string]$texts.combatLibrary
$combatBase = [string]$texts.combatBase
$dictionaryCost = Get-BracedBlock $combatLibrary `
    "public static int[] getActionCost(obj_id self, weapon_data weaponData, dictionary actionData)"
$typedCost = Get-BracedBlock $combatLibrary `
    "public static int[] getActionCost(obj_id self, weapon_data weaponData, combat_data actionData)"
$successCost = Get-BracedBlock $combatLibrary `
    "public static int[] getSuccessBasedSingleTargetActionCost("
$hitEngine = Get-BracedBlock $combatBase `
    "public hit_result[] runHitEngine(attacker_data attackerData, weapon_data weaponData, defender_data[] defenderData, attacker_results attackerResults, defender_results[] defenderResults, combat_data actionData, boolean isTangibleAttacking, boolean isAutoAiming, int overloadDamage)"

foreach ($entry in @(
    @{ Name = "dictionary"; Block = $dictionaryCost },
    @{ Name = "typed"; Block = $typedCost }
))
{
    $precu = $entry.Block.IndexOf("precuHamCostModel", [StringComparison]::Ordinal)
    $expertise = $entry.Block.IndexOf("expertise_action_", [StringComparison]::Ordinal)
    Assert-Contract ($precu -ge 0 -and $expertise -gt $precu -and
        $entry.Block.Contains("return getPrecuHamActionCost")) `
        "p14.combat-expertise-isolation.ham.$($entry.Name)-precu-before-expertise"
}

$areaReturn = $successCost.IndexOf("if (!isSingleTargetAttack)", [StringComparison]::Ordinal)
$precuReturn = $successCost.IndexOf("if (actionData.precuHamCostModel > 0)", [StringComparison]::Ordinal)
$freeshotRead = $successCost.IndexOf('"freeshot_case_miss"', [StringComparison]::Ordinal)
Assert-Contract ($areaReturn -ge 0 -and $precuReturn -gt $areaReturn -and
    $freeshotRead -gt $precuReturn -and
    $successCost.Contains("return getActionCost(attacker, weaponData, actionData);")) `
    "p14.combat-expertise-isolation.ham.single-precu-bypasses-freeshot"
Assert-Contract (([regex]::Matches($successCost, '"freeshot_case_(miss|dodge|parry|crit|strikethrough)"')).Count -eq
    [int]$contract.expected.ngeFreeshotModifierReadsBypassedForPrecu) `
    "p14.combat-expertise-isolation.ham.five-nge-freeshot-reads-bounded"

$precuBranch = $hitEngine.IndexOf("if (precuAuthoritativeAttack)", [StringComparison]::Ordinal)
$precuPrimary = $hitEngine.IndexOf("precuPrimaryResult = getPrecuPrimaryAttackResult(", [StringComparison]::Ordinal)
$precuSecondary = $hitEngine.IndexOf("precuSecondaryResult = getPrecuSecondaryDefenseResult(", [StringComparison]::Ordinal)
$ngeDefender = $hitEngine.IndexOf("defResult = getDefenderResult(", [StringComparison]::Ordinal)
$ngeAttacker = $hitEngine.IndexOf("atkResult = getAttackerResult(", [StringComparison]::Ordinal)
Assert-Contract ($precuBranch -ge 0 -and $precuPrimary -gt $precuBranch -and
    $precuSecondary -gt $precuPrimary -and $ngeDefender -gt $precuSecondary -and
    $ngeAttacker -gt $ngeDefender) `
    "p14.combat-expertise-isolation.hit.precu-and-nge-mutually-exclusive"
Assert-Contract ($hitEngine.Contains("precuPrimaryResult = HIT_RESULT_HIT;") -and
    $hitEngine.Contains("precuSecondaryResult = HIT_RESULT_HIT;") -and
    -not $hitEngine.Contains("precuPrimaryResult == PRECU_PRIMARY_RESULT_FALLBACK ?")) `
    "p14.combat-expertise-isolation.hit.precu-fallback-fails-closed"
Assert-Contract ($hitEngine.Contains("if (!precuAuthoritativeAttack)") -and
    $hitEngine.Contains("combat.getDevastationChance") -and
    $hitEngine.Contains("addPrecuCore3HateProcess") -and
    $hitEngine.Contains("combat.addHateProcess")) `
    "p14.combat-expertise-isolation.hit.damage-and-hate-era-gates-preserved"

$overrides = @(Import-SwgTab -Path $paths.combatOverrides)
$validPools = @("HEALTH", "ACTION", "MIND", "RANDOM", "MULTI", "NO_ATTRIBUTE")
$invalidPools = @($overrides | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.targetPool) -or
    $validPools -cnotcontains [string]$_.targetPool
})
Assert-Contract ($overrides.Count -eq [int]$contract.expected.authenticatedCombatOverrideRows -and
    $invalidPools.Count -eq 0) `
    "p14.combat-expertise-isolation.data.all-overrides-explicit-target-pool"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.combat-expertise-isolation.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.combat-expertise-isolation.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.combatLibrary -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.combatBase -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.combat-expertise-isolation.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.combat-expertise-isolation.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "p14.combat-expertise-isolation.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU combat expertise isolation failed: $($failures -join ', ')"
}
Write-Host "PRE-CU combat expertise isolation contract passed."
