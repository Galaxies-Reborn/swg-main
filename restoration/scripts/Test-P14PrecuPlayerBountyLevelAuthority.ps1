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
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuPlayerBountyLevelAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Signature)
{
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $brace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($brace -lt 0) { return "" }
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
    return ""
}

$paths = [ordered]@{}
$texts = @{}
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $paths[$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($name in $paths.Keys)
{
    $path = $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.player-bounty.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) "p14.player-bounty.source.$name.authenticated"
    }
}

$missionBoard = Get-BracedSurface ([string]$texts.missionPlayer) "public int OnPlayerRequestMissionBoard("
Assert-Contract ($missionBoard.Contains('hasObjVar(objMissionTerminal, "intBounty")') -and $missionBoard.Contains('!hasSkill(self, "combat_bountyhunter_novice")') -and $missionBoard.Contains("createDynamicBountyMission")) "p14.player-bounty.novice-terminal-and-npc-fallback"

$playerBounty = Get-BracedSurface ([string]$texts.missionDynamic) "public obj_id createJediBountyMission(obj_id objMissionData, obj_id objCreator, String strFaction, int hunterLevel, obj_id bountyHunterId, int flag)"
Assert-Contract ($playerBounty.Contains('!hasSkill(bountyHunterId, "combat_bountyhunter_investigation_03")')) "p14.player-bounty.investigation-three-admission"
Assert-Contract ($playerBounty.Contains("requestJedi(IGNORE_JEDI_STAT, 15000, IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, IGNORE_JEDI_STAT, -3)") -and -not $playerBounty.Contains("bhMin") -and -not $playerBounty.Contains("bhMax") -and -not [regex]::IsMatch($playerBounty, 'hunterLevel\s*[<>]=?')) "p14.player-bounty.no-hunter-or-target-level-band"
Assert-Contract ($playerBounty.Contains("boolOnline") -and $playerBounty.Contains("bountyHunterId") -and $playerBounty.Contains("jediFaction") -and $playerBounty.Contains("BOUNTY_FLAG_SMUGGLER")) "p14.player-bounty.script-filters-and-content-preserved"

$investigationRow = ([string]$texts.skillTable -split "\r?\n" | Where-Object { $_.StartsWith("combat_bountyhunter_investigation_03" + [char]9) })
Assert-Contract (@($investigationRow).Count -eq 1 -and [string]$investigationRow -match 'combat_bountyhunter_investigation_02' -and [string]$investigationRow -match 'droid_track') "p14.player-bounty.investigation-three-authored-skill"

$jediManager = [string]$texts.jediManager
$addJedi = Get-BracedSurface $jediManager "void JediManagerObject::addJedi("
Assert-Contract ($addJedi.Contains("UNREF(level);") -and $addJedi.Contains("int const preCuPlayerLevel = 0;") -and $addJedi.Contains("m_jediLevel.push_back(preCuPlayerLevel)") -and $addJedi.Contains("m_jediLevel.set(index, preCuPlayerLevel)") -and -not $addJedi.Contains("m_jediLevel.push_back(level)") -and -not $addJedi.Contains("m_jediLevel.set(index,level)")) "p14.player-bounty.registry-write-neutralized"

$updateJedi = Get-BracedSurface $jediManager "void JediManagerObject::updateJedi(const NetworkId & id, int visibility,"
Assert-Contract ($updateJedi.Contains("UNREF(level);") -and $updateJedi.Contains("if (m_jediLevel.get(index) != 0)") -and $updateJedi.Contains("m_jediLevel.set(index, 0)") -and $updateJedi.Contains('Unicode::emptyString, Vector(), "", visibility, bountyValue, 0, hoursAlive')) "p14.player-bounty.persisted-level-normalization"

$queryJedi = Get-BracedSurface $jediManager "void JediManagerObject::getJedi(int visibility, int bountyValue, int minLevel, int maxLevel,"
Assert-Contract ($queryJedi.Contains("UNREF(minLevel);") -and $queryJedi.Contains("UNREF(maxLevel);") -and -not [regex]::IsMatch($queryJedi, 'm_jediLevel[^;\r\n]*(?:minLevel|maxLevel)') -and $queryJedi.Contains("jediLevel->push_back(0)")) "p14.player-bounty.registry-query-level-filter-retired"
Assert-Contract ($queryJedi.Contains("m_jediVisibility") -and $queryJedi.Contains("m_jediBountyValue") -and $queryJedi.Contains("m_jediBounties") -and $queryJedi.Contains("m_jediHoursAlive") -and $queryJedi.Contains("m_jediState") -and $queryJedi.Contains("m_jediOnline")) "p14.player-bounty.native-validity-filters-preserved"

$singleJedi = Get-BracedSurface $jediManager "void JediManagerObject::getJedi(const NetworkId & id,"
Assert-Contract ($singleJedi.Contains('returnParams.addParam(0, "level")')) "p14.player-bounty.single-query-level-neutralized"
$databaseBounties = Get-BracedSurface $jediManager "void JediManagerObject::addJediBounties("
Assert-Contract ([regex]::Matches($databaseBounties, 'm_jediLevel\.(?:push_back|set)\([^\r\n]*0\)').Count -eq 2) "p14.player-bounty.database-load-level-neutralized"

$scriptProducer = Get-BracedSurface ([string]$texts.scriptMethodsJedi) "jboolean JNICALL ScriptMethodsJediNamespace::setJediBountyValue("
Assert-Contract ($scriptProducer.Contains("bountyValue, 0,") -and -not $scriptProducer.Contains("creature->getLevel()")) "p14.player-bounty.script-producer-neutralized"

$baselineProducer = Get-BracedSurface ([string]$texts.swgCreature) "void SwgCreatureObject::endBaselines()"
$levelProducer = Get-BracedSurface ([string]$texts.swgCreature) "void SwgCreatureObject::levelChanged() const"
Assert-Contract ($baselineProducer.Contains("bountyValue, 0,") -and $levelProducer.Contains("updateJedi(getNetworkId(), -1, -1, 0, -1)") -and -not $baselineProducer.Contains("getLevel()") -and -not $levelProducer.Contains("getLevel()")) "p14.player-bounty.creature-producers-neutralized"

$controller = [string]$texts.jediController
Assert-Contract (-not $controller.Contains("msg->getLevel()") -and [regex]::Matches($controller, 'msg->getBountyValue\(\),\s*\r?\n\s*0,').Count -eq 2) "p14.player-bounty.cross-server-level-neutralized"

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and [string]$contract.buildEvidence.result -ceq "passed" -and [string]$contract.runtimeEvidence.result -ceq "passed" -and $contract.requiredBeforeReady.Count -eq 0) "p14.player-bounty.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and $srcPin.Count -eq 1 -and [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink -and [string]$srcPin[0].commit -ceq [string]$contract.buildEvidence.nativeSourceCommit) "p14.player-bounty.direct-source-pins"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) "p14.player-bounty.live-x64-evidence"
}
else
{
    Assert-Contract (@("implemented-build-pending", "implemented-build-verified-live-pending", "ready") -contains [string]$contract.status) "p14.player-bounty.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and -not $contractText.Contains("/Staging/")) "p14.player-bounty.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU player bounty level authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU player bounty level authority contract passed."
