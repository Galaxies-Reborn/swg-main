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
$scriptRoot = Join-Path $dsrcRoot "sku.0/sys.server/compiled/game/script"
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractPath = Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14JavaSkillGrantCallbackInventoryClosure)
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
    if ($start -lt 0) { throw "Missing Java surface: $Signature" }
    $open = $Text.IndexOf("{", $start)
    if ($open -lt 0) { throw "Missing opening brace: $Signature" }
    $depth = 0
    for ($i = $open; $i -lt $Text.Length; $i++)
    {
        if ($Text[$i] -ceq '{') { $depth++ }
        elseif ($Text[$i] -ceq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $i - $start + 1) }
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
    "Skill-grant callback closure is not pinned to checked-out direct source."

$javaFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.java")
Assert-Contract ($javaFiles.Count -eq [int]$contract.inventory.javaSources) `
    "Java source inventory drifted: $($javaFiles.Count)"
Assert-Contract ($null -ne (Get-Command rg -ErrorAction SilentlyContinue)) `
    "ripgrep is required for the exact skill-grant callback inventory."

$records = [Collections.Generic.List[string]]::new()
foreach ($line in @(& rg -n --no-heading '\bOnSkillGranted\s*\(' $scriptRoot --glob "*.java"))
{
    Assert-Contract ($line -match '^(.*?):(\d+):(.*)$') `
        "Could not parse skill-grant callback inventory line."
    $absolutePath = (Resolve-Path -LiteralPath $Matches[1]).Path
    Assert-Contract ($absolutePath.StartsWith($scriptRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) `
        "Skill-grant callback escaped the Java source root."
    $relativePath = $absolutePath.Substring($scriptRoot.Length + 1).Replace("\", "/")
    $records.Add("${relativePath}:$($Matches[2])|$($Matches[3].Trim())")
}
$records = @($records | Sort-Object)
$expectedPaths = @($contract.sourceFiles.PSObject.Properties |
    ForEach-Object { [string]$_.Value } | Sort-Object)
$actualPaths = @($records | ForEach-Object { ($_ -split ':\d+\|', 2)[0] } | Sort-Object)
Assert-Contract ($records.Count -eq [int]$contract.inventory.handlers -and
    $actualPaths.Count -eq [int]$contract.inventory.sourceFiles -and
    ($actualPaths -join "`n") -ceq ($expectedPaths -join "`n") -and
    (Get-TextSha256 ($records -join "`n")) -ceq [string]$contract.inventory.inventorySha256 -and
    (Get-TextSha256 ($actualPaths -join "`n")) -ceq [string]$contract.inventory.sourceSetSha256) `
    "Complete Java skill-grant callback inventory drifted."

$texts = @{}
$contentRows = [Collections.Generic.List[string]]::new()
foreach ($property in $contract.sourceFiles.PSObject.Properties)
{
    $name = [string]$property.Name
    $relativePath = [string]$property.Value
    $path = Join-Path $scriptRoot $relativePath
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "Skill-grant callback source is missing: $relativePath"
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-Contract ($actualHash -ceq [string]$contract.sourceSha256.$name) `
        "Skill-grant callback source evidence drifted: $name"
    $contentRows.Add("$relativePath|$actualHash")
    $texts[$name] = Get-Content -LiteralPath $path -Raw
}
Assert-Contract ((Get-TextSha256 (@($contentRows | Sort-Object) -join "`n")) -ceq
    [string]$contract.inventory.sourceContentSha256) `
    "Skill-grant callback aggregate source evidence drifted."

$baseGrant = Get-BracedSurface $texts.basePlayer "public int OnSkillGranted"
$retiredAt = $baseGrant.IndexOf("skill.isRetiredNgeProgressionSkillName(skillName)",
    [StringComparison]::Ordinal)
$revokeAt = $baseGrant.IndexOf("revokeSkillSilent(self, skillName)",
    [StringComparison]::Ordinal)
$overrideAt = $baseGrant.IndexOf("return SCRIPT_OVERRIDE", $retiredAt,
    [StringComparison]::Ordinal)
$effectAt = $baseGrant.IndexOf("playClientEffectObj", [StringComparison]::Ordinal)
Assert-Contract ($retiredAt -ge 0 -and $revokeAt -gt $retiredAt -and
    $overrideAt -gt $revokeAt -and $effectAt -gt $overrideAt -and
    $baseGrant.Contains("retirePostNgePassiveProfessionState(self)") -and
    $baseGrant.Contains("retirePostNgeSpyPlayerState(self)") -and
    $baseGrant.Contains("badge.grantMasterSkillBadge(self, skillName)") -and
    $baseGrant.Contains("setupNovicePilotSkill(self, skillName)") -and
    $baseGrant.Contains("allowedBySpaceExpansion(self, skillName)") -and
    $baseGrant.Contains("recomputeCommandSeries(self)")) `
    "Base-player skill-grant callback no longer rejects NGE state before PRE-CU effects."

$beastGrant = Get-BracedSurface $texts.playerBeastmaster "public int OnSkillGranted"
Assert-Contract ($beastGrant.Contains("retirePostNgeBeastMasterPlayerState(self)") -and
    $beastGrant.Contains("return SCRIPT_OVERRIDE") -and
    $beastGrant -notmatch '\b(grantSkill|grantExperiencePoints|setLevel|applyBuff)\s*\(') `
    "Retired Beast Master skill-grant callback regained mutation authority."

$petGrant = Get-BracedSurface $texts.petMaster "public int OnSkillGranted"
Assert-Contract ($petGrant.Contains('hasObjVar(self, "familiar")') -and
    $petGrant.Contains('messageTo(pet, "doFamiliarTrick"') -and
    $petGrant -notmatch '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|applyBuff)\s*\(') `
    "Retained familiar callback escaped cosmetic-only authority."

$npeGrant = Get-BracedSurface $texts.npeJournal "public int OnSkillGranted"
Assert-Contract ($npeGrant.Contains("utils.isProfession(self, utils.TRADER)") -and
    $npeGrant.Contains("utils.isProfession(self, utils.ENTERTAINER)") -and
    $npeGrant.Contains("npe.sendDelayed3poPopup") -and
    $npeGrant.Contains("newbieTutorialHighlightUIElement") -and
    $npeGrant -notmatch '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
    "Retained NPE skill callback gained progression mutation authority."

$forceRankGrant = Get-BracedSurface $texts.playerForceRank "public int OnSkillGranted"
$rankTitleGrantCount = ([regex]::Matches($forceRankGrant, '\bgrantSkill\s*\(')).Count
Assert-Contract ($rankTitleGrantCount -eq [int]$contract.expected.retainedForceRankTitleGrantRules -and
    $forceRankGrant.Contains('skill.equals("force_rank_dark_rank_09")') -and
    $forceRankGrant.Contains('skill.equals("force_rank_light_rank_09")') -and
    $forceRankGrant.Contains('skill.equals("force_rank_dark_rank_05")') -and
    $forceRankGrant.Contains('skill.equals("force_rank_light_rank_05")') -and
    $forceRankGrant.Contains("JEDI_MASTER_TITLE_SKILL") -and
    $forceRankGrant.Contains("JEDI_GUARDIAN_TITLE_SKILL") -and
    $forceRankGrant -notmatch '\b(grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
    "Publish 14.1 Force Rank title callback drifted."

$workingGrant = Get-BracedSurface $texts.workingTriggerTest "public int OnSkillGranted"
Assert-Contract ($workingGrant.Contains("debugSpeakMsg") -and
    $workingGrant.Contains('hasObjVar(self, "override_test")') -and
    $workingGrant -notmatch '\b(grantSkill|revokeSkill|grantExperiencePoints|setLevel|setSkillTemplate)\s*\(') `
    "Dormant working skill callback gained mutation authority."
$workingReferences = @(& rg -l -i --glob "*.java" --glob "*.tab" --glob "*.tpf" `
    'working\.cmayer\.trigtest|working/cmayer/trigtest' $dsrcRoot)
$workingReferenceExit = $LASTEXITCODE
Assert-Contract ($workingReferenceExit -eq 1 -and $workingReferences.Count -eq 0 -and
    [int]$contract.expected.dormantWorkingProductionAttachments -eq 0) `
    "Dormant working callback acquired a production attachment reference."

foreach ($dependencyKey in @($contract.requiredReadyContractKeys))
{
    $dependencyKey = [string]$dependencyKey
    $property = @($manifest.contracts.PSObject.Properties |
        Where-Object { $_.Name -ceq $dependencyKey })
    Assert-Contract ($property.Count -eq 1) `
        "Required contract key is missing from the manifest: $dependencyKey"
    $dependencyPath = Join-Path $restorationRoot ([string]$property[0].Value)
    Assert-Contract (Test-Path -LiteralPath $dependencyPath -PathType Leaf) `
        "Required Ready contract is missing: $dependencyKey"
    $dependency = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
    Assert-Contract ([string]$dependency.status -ceq "ready") `
        "Required dependency is not Ready: $dependencyKey"
}

Assert-Contract ([bool]$contract.expected.allHandlersClassified -and
    [int]$contract.classification.unclassifiedHandlers -eq 0 -and
    [int]$contract.expected.retiredNgeSkillSideEffectsBeforeRevocation -eq 0 -and
    [int]$contract.expected.retiredBeastMasterCallbackMutations -eq 0 -and
    [int]$contract.expected.retainedFamiliarTrickCallbacks -eq 1 -and
    [int]$contract.expected.npeGuidanceProgressionMutations -eq 0 -and
    [int]$contract.expected.gameplaySourceFilesChanged -eq 0 -and
    [bool]$contract.expected.laterZonesQuestsConversationsNpcsJtlAndForceRankPreserved) `
    "Skill-grant callback expected PRE-CU boundary is incomplete."

if ($Expectation -ceq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.buildEvidence.serverBinarySha256 -match '^[a-f0-9]{64}$' -and
        [string]$contract.buildEvidence.serverBinaryBuildId -match '^[a-f0-9]{40}$' -and
        [string]$contract.buildEvidence.architecture -ceq "ELF 64-bit LSB x86-64" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.containerHealth -ceq "healthy" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [int]$contract.runtimeEvidence.javaSources -eq 5717 -and
        [int]$contract.runtimeEvidence.javaClasses -eq 5751 -and
        [int]$contract.runtimeEvidence.liveGameProcessCount -eq 15 -and
        [int]$contract.runtimeEvidence.livePlanetProcessCount -eq 15 -and
        @($contract.requiredBeforeReady).Count -eq 0) `
        "Skill-grant callback closure lacks Ready evidence."
    $container = [string]$contract.runtimeEvidence.container
    $state = (& docker inspect --format `
        "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" $container).Trim()
    $processNames = @(& docker exec $container ps -eo comm= | ForEach-Object { $_.Trim() })
    $binaryHash = ((& docker exec $container sha256sum /swg-precu/build/bin/SwgGameServer) -split '\s+')[0]
    Assert-Contract ($state -ceq "running healthy" -and
        @($processNames | Where-Object { $_ -ceq "SwgGameServer" }).Count -eq 15 -and
        @($processNames | Where-Object { $_ -ceq "PlanetServer" }).Count -eq 15 -and
        $binaryHash -ceq [string]$contract.buildEvidence.serverBinarySha256) `
        "Deployed PRE-CU x64 runtime topology or binary drifted."
}
else
{
    Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) `
        "Skill-grant callback closure is not build-eligible."
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) `
    "Skill-grant callback closure references forbidden host staging."

Write-Host "Complete Publish 14.1 Java skill-grant callback inventory closure passed."
