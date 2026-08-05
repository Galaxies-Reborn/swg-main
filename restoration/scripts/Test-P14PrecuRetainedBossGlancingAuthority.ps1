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
    ([string]$manifest.contracts.p14PrecuRetainedBossGlancingAuthority)
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

function Get-SourceSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length,
        [StringComparison]::Ordinal)
    if ($end -lt 0) { return "" }
    return $Text.Substring($start, $end - $start)
}

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.retained-boss-glancing.source.$([IO.Path]::GetFileName($path)).exists"
}

$wampa = Get-Content -LiteralPath $paths.wampaBoss -Raw
$outbreak = Get-Content -LiteralPath $paths.outbreakBoss -Raw
$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$wampaAttach = Get-BracedBlock $wampa "public int OnAttach(obj_id self)"
$outbreakAttach = Get-BracedBlock $outbreak "public int OnAttach(obj_id self)"
$precuPrimary = Get-BracedBlock $combatBase "public int getPrecuPrimaryAttackResult("
$precuSecondary = Get-BracedBlock $combatBase "public int getPrecuSecondaryDefenseResult("
$resolution = Get-SourceSlice $combatBase "int precuPrimaryResult =" "switch (defResult)"

Assert-Contract ($wampaAttach.Contains("trial.setHp(self, trial.HP_UNCLE_JOE);") -and
    -not $wampaAttach.Contains("expertise_") -and
    -not $wampaAttach.Contains("SkillStatisticModifier") -and
    $wampa.Contains('buff.applyBuff(self, "open_balance_buff", -1.0f)') -and
    $wampa.Contains("handleUncleJoeDistanceCheck") -and
    $wampa.Contains("summon_adds") -and
    $wampa.Contains("WAMPA_DNA_LOOT_ITEM")) `
    "p14.retained-boss-glancing.uncle-joe-lifecycle-preserved"
Assert-Contract ($outbreakAttach.Contains("moveCreatureToWaypoint(self);") -and
    $outbreakAttach.Contains("trial.setHp(self, trial.HP_UNCLE_JOE);") -and
    $outbreakAttach.Contains('messageTo(self, "warnPlayerTimerBegin", null, 1, false)') -and
    $outbreakAttach.Contains('messageTo(self, "warnPlayerTimerEnd", null, 540, false)') -and
    -not $outbreakAttach.Contains("expertise_") -and
    -not $outbreakAttach.Contains("SkillStatisticModifier") -and
    $outbreak.Contains("handleBossDistanceCheck") -and
    $outbreak.Contains("getRandomCombatTarget")) `
    "p14.retained-boss-glancing.outbreak-lifecycle-preserved"

$scriptRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script"
$legacyReferences = [System.Collections.Generic.List[string]]::new()
$writerCount = 0
foreach ($javaPath in [IO.Directory]::EnumerateFiles($scriptRoot, "*.java",
    [IO.SearchOption]::AllDirectories))
{
    $javaText = Get-Content -LiteralPath $javaPath -Raw
    if ($javaText.Contains("expertise_glancing_blow_reduction"))
    {
        $legacyReferences.Add(($javaPath.Replace('\', '/')))
    }
    $writerCount += ([regex]::Matches($javaText,
        'applySkillStatisticModifier\([^\r\n]*expertise_glancing_blow_reduction')).Count
}
Assert-Contract ($writerCount -eq [int]$contract.expected.remainingBossGlancingExpertiseWriters -and
    $legacyReferences.Count -eq [int]$contract.expected.remainingLegacyGlancingExpertiseReaders -and
    $legacyReferences[0].EndsWith("/library/combat.java", [StringComparison]::Ordinal)) `
    "p14.retained-boss-glancing.nge-writers-retired-reader-isolated"
Assert-Contract ($resolution.Contains("if (precuAuthoritativeAttack)") -and
    $resolution.Contains("getPrecuPrimaryAttackResult") -and
    $resolution.Contains("getPrecuSecondaryDefenseResult") -and
    $resolution.Contains("else") -and
    $resolution.Contains("getDefenderResult") -and
    $resolution.Contains("getAttackerResult")) `
    "p14.retained-boss-glancing.hit-table-era-separation"
Assert-Contract (-not $precuPrimary.Contains("HIT_RESULT_GLANCING") -and
    -not $precuPrimary.Contains("getGlancingBlowChance") -and
    -not $precuSecondary.Contains("HIT_RESULT_GLANCING") -and
    -not $precuSecondary.Contains("getGlancingBlowChance") -and
    ([regex]::Matches($precuPrimary, "HIT_RESULT_GLANCING")).Count -eq
        [int]$contract.expected.precuPrimaryGlancingOutcomes -and
    ([regex]::Matches($precuSecondary, "HIT_RESULT_GLANCING")).Count -eq
        [int]$contract.expected.precuSecondaryGlancingOutcomes) `
    "p14.retained-boss-glancing.precu-results-no-glancing"

$creatureLines = Get-Content -LiteralPath $paths.creatures
$bossRows = @($creatureLines | Where-Object {
    $_ -match '^(heroic_echo_wampa_boss|outbreak_afflicted_rancor)\t'
})
Assert-Contract ($bossRows.Count -eq [int]$contract.expected.retainedBossCreatureRows -and
    @($bossRows | Where-Object { $_ -match '^heroic_echo_wampa_boss\t' -and
        $_ -match 'theme_park[.]heroic[.]echo_base[.]wampa_boss' }).Count -eq 1 -and
    @($bossRows | Where-Object { $_ -match '^outbreak_afflicted_rancor\t' -and
        $_ -match 'theme_park[.]outbreak[.]boss_fight_functionality' }).Count -eq 1) `
    "p14.retained-boss-glancing.creature-bindings"

$aiRows = @(Get-Content -LiteralPath $paths.aiProfiles | Where-Object {
    $_ -match '^(echo_base_wampa_boss|outbreak_afflicted_rancor)\t'
})
Assert-Contract ($aiRows.Count -eq [int]$contract.expected.retainedBossAiProfiles -and
    @($aiRows | Where-Object { $_ -match 'wampa_boss_ice_throw_prep' }).Count -eq 1 -and
    @($aiRows | Where-Object { $_ -match 'death_troopers_afflicted_toss' }).Count -eq 1) `
    "p14.retained-boss-glancing.ai-profiles-preserved"

$echoBossSpawns = @(Get-Content -LiteralPath $paths.echoBaseSpawns | Where-Object {
    $_ -match '^heroic_echo_wampa_boss\t' -and $_ -match '\tuncle_joe_id\t'
})
Assert-Contract ($echoBossSpawns.Count -eq [int]$contract.expected.echoBaseBossSpawns) `
    "p14.retained-boss-glancing.echo-base-spawn"
$outbreakLines = Get-Content -LiteralPath $paths.outbreakBuildout
$outbreakTerminals = @($outbreakLines | Where-Object {
    $_ -match 'object/tangible/quest/outbreak/group_boss_fight_terminal[.]iff' -and
    $_ -match 'rancor_boss_fight_controller'
})
$outbreakNodes = @($outbreakLines | Where-Object {
    $_ -match 'object/tangible/spawning/event/outbreak_rescue_survivor_path[.]iff' -and
    $_ -match 'outbreak_afflicted_rancor'
})
Assert-Contract ($outbreakTerminals.Count -eq [int]$contract.expected.outbreakBossTerminals -and
    $outbreakNodes.Count -eq [int]$contract.expected.outbreakBossNodes) `
    "p14.retained-boss-glancing.outbreak-wave-route"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.retained-boss-glancing.$($property.Name).authenticated"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.retained-boss-glancing.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.retained-boss-glancing.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256.wampaBoss -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.compiledClassSha256.outbreakBoss -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.retained-boss-glancing.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.retained-boss-glancing.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.retained-boss-glancing.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU retained boss glancing authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU retained boss glancing authority contract passed."
