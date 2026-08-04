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
    ([string]$manifest.contracts.p14PrecuAuthoredHealingBuffAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
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
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

$texts = [ordered]@{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $path = Join-Path $source ([string]$property.Value)
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.authored-healing-buff.source.$($property.Name).exists"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $texts[$property.Name] = Get-Content -LiteralPath $path -Raw
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$property.Name].Value
    Assert-Contract ($hash -ceq $expectedHash) `
        "p14.authored-healing-buff.source.$($property.Name).authenticated"
}

$combat = [string]$texts.combat
$healing = [string]$texts.healing
$combatBuffs = Get-SourceSlice $combat "public static boolean applyDefenderCombatBuffs(" `
    "public static boolean applyCombatMovementModifier("
$healingActions = Get-SourceSlice $healing "public static boolean performHealDamage(" `
    "public static boolean canUseAbility("
$lifeSiphon = Get-SourceSlice $healing "public static void applyLifeSiphonHeal(" `
    "public static int doDiminishingReturns("

$forbiddenCombatAuthority = @(
    "expertiseRandomBuffChance",
    "getExpertiseBuffDurationMods",
    "expertise_use_buff_chance_line_",
    "private_use_buff_chance_line_",
    "expertise_buff_chance_line_",
    "expertise_buff_duration_line_",
    "expertise_buff_duration_group_",
    "expertise_buff_duration_single_"
)
$combatAuthorityRetired = $true
foreach ($marker in $forbiddenCombatAuthority)
{
    if ($combatBuffs.Contains($marker)) { $combatAuthorityRetired = $false }
}
Assert-Contract $combatAuthorityRetired "p14.authored-healing-buff.combat-expertise.retired"
Assert-Contract (-not $healing.Contains("expertise_") -and
    -not $healing.Contains("getExpertiseModifiedHealing") -and
    -not $healing.Contains("getHealingAfterReductions") -and
    -not $healing.Contains("getTargetHealingBonus")) `
    "p14.authored-healing-buff.healing-expertise.retired"

$authoredCalls = ([regex]::Matches(($combatBuffs + $healingActions),
    'buffDuration = (?:combat\.)?getAuthoredBuffDuration\(')).Count
Assert-Contract ($authoredCalls -eq [int]$contract.expected.authoredDurationCallSites -and
    ([regex]::Matches($combatBuffs, 'public static float getAuthoredBuffDuration\(')).Count -eq
        [int]$contract.expected.authoredDurationDefinitions) `
    "p14.authored-healing-buff.authored-duration.call-surface"
Assert-Contract ($combatBuffs.Contains("if (buffDuration != 0)") -and
    $combatBuffs.Contains("return buffDuration;") -and
    $combatBuffs.Contains("dataTableGetRow(buff.BUFF_TABLE, buffName)") -and
    $combatBuffs.Contains('return dic.getFloat("DURATION");') -and
    -not $combatBuffs.Contains("buffDuration +=")) `
    "p14.authored-healing-buff.authored-duration.precedence"
Assert-Contract ($combatBuffs.Contains("applyDefenderCombatBuffs") -and
    $combatBuffs.Contains("applyAttackerCombatBuffs") -and
    $combatBuffs.Contains("dot.attemptDotResist") -and
    $combatBuffs.Contains("buff.applyBuff(defender, attacker") -and
    $combatBuffs.Contains("buff.applyBuff(attacker, attacker")) `
    "p14.authored-healing-buff.combat-lifecycle.preserved"
Assert-Contract ($healingActions.Contains("int toHeal = action_data.addedDamage;") -and
    $healingActions.Contains("luck.isLucky") -and
    $healingActions.Contains("float modifiedHate = delta / HEALING_AGGRO_REDUCER;") -and
    $healingActions.Contains("int maxHeal = action_data.addedDamage;") -and
    $healingActions.Contains("int duration = action_data.dotDuration;") -and
    $healingActions.Contains("int perTick = action_data.dotIntensity;") -and
    $healingActions.Contains("startHealOverTime") -and
    $healingActions.Contains("applyDefenderHealBuffs") -and
    $healingActions.Contains("applyMedicHealBuffs") -and
    $healingActions.Contains("pvpHelpPerformed")) `
    "p14.authored-healing-buff.healing-values-and-lifecycle.preserved"
Assert-Contract ($lifeSiphon.Contains("Math.round(damage * percentToHeal)") -and
    $lifeSiphon.Contains("healDamage(attacker, attacker, HEALTH, damageToHeal)")) `
    "p14.authored-healing-buff.life-siphon.preserved"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.authored-healing-buff.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.authored-healing-buff.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.combat -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.healing -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.authored-healing-buff.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.authored-healing-buff.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.authored-healing-buff.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU authored healing/buff authority failed: $($failures -join ', ')"
}

Write-Host "PRE-CU authored healing/buff authority contract passed."
