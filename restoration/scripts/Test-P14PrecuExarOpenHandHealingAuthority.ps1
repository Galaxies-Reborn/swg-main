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
    ([string]$manifest.contracts.p14PrecuExarOpenHandHealingAuthority)
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

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.open-hand.source.$([IO.Path]::GetFileName($path)).exists"
}

$openHand = Get-Content -LiteralPath $paths.openHand -Raw
$sacrifice = Get-BracedBlock $openHand `
    "public int sacrificeAdd(obj_id self, dictionary params)"
$sacrificeBuff = Get-BracedBlock $openHand `
    "public String getSacrificeBuff(obj_id self)"
$spawnRows = @(Import-Csv -LiteralPath $paths.spawnTable -Delimiter "`t" |
    Where-Object { [string]$_.object -ceq "heroic_exar_open_hand" })
$creatureRows = @(Import-Csv -LiteralPath $paths.creatures -Delimiter "`t" |
    Where-Object { [string]$_.creatureName -ceq "heroic_exar_open_hand" })
$mobileTemplate = Get-Content -LiteralPath $paths.mobileTemplate -Raw

Assert-Contract (-not $openHand.Contains("expertise_") -and
    -not $openHand.Contains("getEnhancedSkillStatisticModifierUncapped") -and
    -not $sacrifice.Contains("healingReduction") -and
    -not $sacrifice.Contains("redux")) `
    "p14.open-hand.nge-healing-reduction-authority-absent"
Assert-Contract (([regex]::Matches($sacrifice,
    'healing\.healDamage\(self, HEALTH, 125000\);')).Count -eq 1 -and
    [int]$contract.expected.authoredSacrificeHeal -eq 125000) `
    "p14.open-hand.authored-sacrifice-heal"
Assert-Contract ($sacrifice.Contains('params.getObjId("sacrifice")') -and
    $sacrifice.Contains("incrementAddsKilled(self)") -and
    $sacrifice.Contains("getSacrificeBuff(self)") -and
    $sacrifice.Contains("kill(add)") -and
    $sacrifice.Contains("buff.applyBuff(self, sacBuff)")) `
    "p14.open-hand.sacrifice-selection-state-kill-and-buff-preserved"
Assert-Contract (([regex]::Matches($sacrificeBuff,
    'sacrifice = "kun_(?:one|two|three|four|five|six|seven|eight)_sacrifice";')).Count -eq
    [int]$contract.expected.sacrificeBuffTiers) `
    "p14.open-hand.eight-sacrifice-buff-tiers-preserved"
Assert-Contract ($sacrifice.Contains('playClientEffectLoc(self, "clienteffect/bacta_bomb.cef"')) `
    "p14.open-hand.sacrifice-client-effect-preserved"

Assert-Contract ($spawnRows.Count -eq [int]$contract.expected.spawnRows -and
    [string]$spawnRows[0].spawn_id -ceq "open" -and
    [string]$spawnRows[0].triggerId -ceq "spawn_open" -and
    [string]$spawnRows[0].room -ceq "r2" -and
    [string]$spawnRows[0].script -ceq [string]$contract.expected.spawnScript -and
    [string]$spawnRows[0].isInvulnerable -ceq "1" -and
    [string]$spawnRows[0].trigger_event -match "OnDeath:triggerId:open_won") `
    "p14.open-hand.live-instance-spawn-binding"
Assert-Contract ($creatureRows.Count -eq 1 -and
    [int]$creatureRows[0].BaseLevel -eq [int]$contract.expected.creatureLevel -and
    [string]$creatureRows[0].difficultyClass -ceq [string]$contract.expected.creatureDifficulty -and
    [string]$creatureRows[0].template -ceq "exar_kun_open_hand.iff" -and
    [string]$creatureRows[0].primary_weapon_specials -ceq "heroic_exar_open_hand") `
    "p14.open-hand.live-creature-definition"
Assert-Contract ($mobileTemplate.Contains('sharedTemplate = "object/mobile/shared_exar_kun_open_hand.iff"')) `
    "p14.open-hand.live-mobile-template"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.open-hand.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.open-hand.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.open-hand.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.open-hand.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.open-hand.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.open-hand.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU Exar Open Hand healing authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU Exar Open Hand healing authority contract passed."
