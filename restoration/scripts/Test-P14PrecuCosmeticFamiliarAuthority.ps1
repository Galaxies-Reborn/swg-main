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
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuCosmeticFamiliarAuthority)
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

foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.cosmetic-familiar.source.$([System.IO.Path]::GetFileName($path)).exists"
}

$familiar = Get-Content -LiteralPath $paths.familiar -Raw
$pet = Get-Content -LiteralPath $paths.pet -Raw
$petLibrary = Get-Content -LiteralPath $paths.petLibrary -Raw
$travel = Get-Content -LiteralPath $paths.travelLibrary -Raw
$deed = Get-Content -LiteralPath $paths.rewardPetDeed -Raw
$cleanup = Get-BracedSurface $familiar "public void removePetBuff"
$setup = Get-BracedSurface $familiar "public int handleSetupPet"
$detach = Get-BracedSurface $familiar "public int OnDetach"
$repack = Get-BracedSurface $familiar "public void repackPet"
$destroy = Get-BracedSurface $familiar "public int OnDestroy"
$pack = Get-BracedSurface $familiar "public int handlePackRequest"
$petAttach = Get-BracedSurface $pet "public int OnAttach"

Assert-Contract (-not $familiar.Contains("getLevel(") -and
    -not $familiar.Contains("buff.applyBuff") -and
    -not $familiar.Contains("public boolean applyBuff") -and
    -not $familiar.Contains("datatables/familiar/familiar_buff.iff")) `
    "p14.cosmetic-familiar.no-nge-buff-authority"
Assert-Contract ($cleanup.Contains("if (!isIdValid(master))") -and
    $cleanup.Contains('buff.getBuffOnTargetFromGroup(master, "vr_familiar")') -and
    $cleanup.Contains("if (numbuff != 0)") -and
    $cleanup.Contains("buff.removeBuff(master, numbuff)") -and
    -not $cleanup.Contains("buff.applyBuff")) `
    "p14.cosmetic-familiar.remove-stale-group"
Assert-Contract ($setup.Contains("pet_lib.hasMaster(self)") -and
    $setup.Contains('setObjVar(master, "familiar", self)') -and
    $setup.Contains("pet_lib.addToPetList(master, self)") -and
    $setup.Contains("removePetBuff(master)") -and
    $setup.Contains("ai_lib.aiFollow(self, master") -and
    $setup.Contains('messageTo(self, "doFamiliarTrick"')) `
    "p14.cosmetic-familiar.cosmetic-lifecycle"
Assert-Contract ($detach.Contains("if (isIdValid(master))") -and
    -not $detach.Contains("if (!isIdValid(master))") -and
    $detach.Contains("removePetBuff(master)") -and
    $repack.Contains("removePetBuff(master)") -and
    $destroy.Contains("removePetBuff(master)") -and
    $pack.Contains("removePetBuff(master)")) `
    "p14.cosmetic-familiar.cleanup-lifecycle"
Assert-Contract ($petAttach.Contains("pet_lib.getPetType(self) == pet_lib.PET_TYPE_FAMILIAR") -and
    $petAttach.Contains('attachScript(self, "ai.familiar")') -and
    $petAttach.Contains('detachScript(self, "systems.combat.combat_actions")') -and
    $petAttach.Contains('detachScript(self, "ai.ai")')) `
    "p14.cosmetic-familiar.non-combat-routing"
Assert-Contract ($petLibrary.Contains("generatePetOfTypeFamiliar") -and
    $petLibrary.Contains('setObjVar(familiarControlDevice, "ai.pet.type", pet_lib.PET_TYPE_FAMILIAR)') -and
    $deed.Contains("pet_lib.generatePetOfTypeFamiliar(creatureType, player)") -and
    $travel.Contains('buff.getBuffOnTargetFromGroup(player, "vr_familiar")')) `
    "p14.cosmetic-familiar.reward-summon-travel-routing"

$familiarMap = @(Import-Csv -LiteralPath $paths.familiarBuffMap -Delimiter "`t" | Where-Object {
    $_.familiar_name -and $_.familiar_name -ne "s"
})
$nonCombat = @(Import-Csv -LiteralPath $paths.nonCombatFamiliars -Delimiter "`t" | Where-Object {
    $_.creatureName -and $_.creatureName -ne "s"
})
$buffDefinitions = @(Import-Csv -LiteralPath $paths.buffDefinitions -Delimiter "`t" | Where-Object {
    $_.NAME -match '^vr_familiar_(accuracy|health|defense)_[1-8]$|^loveday_ewok_familiar$'
})
Assert-Contract ($familiarMap.Count -eq [int]$contract.expected.familiarBuffMapRowsRetainedAsDataOnly -and
    @($familiarMap | Where-Object { [int]$_.level_up -eq 1 }).Count -eq 5 -and
    @($familiarMap | Where-Object { [int]$_.level_up -eq 0 }).Count -eq 1) `
    "p14.cosmetic-familiar.buff-map-data-preserved"
Assert-Contract ($nonCombat.Count -eq [int]$contract.expected.nonCombatFamiliarRowsPreserved -and
    @($nonCombat | Where-Object { -not $_.controlDeviceTemplate }).Count -eq 0) `
    "p14.cosmetic-familiar.non-combat-definitions-preserved"
Assert-Contract (@($buffDefinitions | Where-Object { $_.NAME -match '^vr_familiar_' }).Count -eq
        [int]$contract.expected.levelScaledBuffDefinitionsRetainedAsDataOnly -and
    @($buffDefinitions | Where-Object { $_.NAME -eq "loveday_ewok_familiar" }).Count -eq
        [int]$contract.expected.fixedLoveDayBuffDefinitionsRetainedAsDataOnly -and
    @($buffDefinitions | Where-Object { $_.GROUP1 -ne "vr_familiar" }).Count -eq 0) `
    "p14.cosmetic-familiar.combat-buff-data-only"

$veteranRewards = @(Import-Csv -LiteralPath $paths.veteranRewards -Delimiter "`t" | Where-Object {
    $_.'Object Template' -match 'vr_(nightspider|mouse_droid|bearded_jax|gacklebat|mynock)_deed\.iff$'
})
$masterItems = @(Import-Csv -LiteralPath $paths.masterItems -Delimiter "`t")
$masterRewardNames = @($masterItems | Where-Object {
    $_.scripts -match '(^|,)npc\.pet_deed\.reward_pet_deed(,|$)'
} | ForEach-Object { $_.name })
$nonCombatNames = @($nonCombat | ForEach-Object { $_.creatureName })
$familiarDeedStats = @(Import-Csv -LiteralPath $paths.itemStats -Delimiter "`t" | Where-Object {
    if ($masterRewardNames -notcontains $_.name -or $_.objvars -notmatch 'string:creatureName=([^,]+)') { return $false }
    return $nonCombatNames -contains $Matches[1]
})
Assert-Contract ($veteranRewards.Count -eq [int]$contract.expected.veteranRewardFamiliarRowsPreserved -and
    $familiarDeedStats.Count -eq [int]$contract.expected.masterItemFamiliarDeedsPreserved) `
    "p14.cosmetic-familiar.reward-content-preserved"

foreach ($property in $contract.buildEvidence.sourceSha256.PSObject.Properties)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $paths[$property.Name]).Hash.ToLowerInvariant() -ceq
        [string]$property.Value) "p14.cosmetic-familiar.$($property.Name).authenticated"
}
$continuity = [ordered]@{
    petSha256 = $paths.pet
    petMasterSha256 = $paths.petMaster
    petLibrarySha256 = $paths.petLibrary
    travelLibrarySha256 = $paths.travelLibrary
    rewardPetDeedSha256 = $paths.rewardPetDeed
    familiarBuffMapSha256 = $paths.familiarBuffMap
    nonCombatFamiliarsSha256 = $paths.nonCombatFamiliars
    buffDefinitionsSha256 = $paths.buffDefinitions
    veteranRewardsSha256 = $paths.veteranRewards
    masterItemsSha256 = $paths.masterItems
    itemStatsSha256 = $paths.itemStats
}
foreach ($name in $continuity.Keys)
{
    Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $continuity[$name]).Hash.ToLowerInvariant() -ceq
        [string]$contract.continuityEvidence.$name) "p14.cosmetic-familiar.continuity.$name"
}

if ($Expectation -eq "Ready")
{
    $dsrcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "p14.cosmetic-familiar.ready-evidence"
    Assert-Contract ($dsrcPin.Count -eq 1 -and
        [string]$dsrcPin[0].commit -ceq [string]$contract.buildEvidence.directSourceGitlink) `
        "p14.cosmetic-familiar.direct-source-pin"
    Assert-Contract ([string]$contract.buildEvidence.compiledClassSha256 -match '^[a-f0-9]{64}$' -and
        [bool]$contract.runtimeEvidence.compiledClassPresent -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary) `
        "p14.cosmetic-familiar.live-evidence"
}
else
{
    Assert-Contract (@("implemented-build-verified-live-pending", "ready") -contains
        [string]$contract.status) "p14.cosmetic-familiar.source-status"
}

$contractText = Get-Content -LiteralPath $contractPath -Raw
Assert-Contract (-not $contractText.Contains("/Artifacts/") -and
    -not $contractText.Contains("/Staging/")) "p14.cosmetic-familiar.no-host-staging"
if ($failures.Count -gt 0)
{
    throw "PRE-CU cosmetic familiar authority failed: $($failures -join ', ')"
}
Write-Host "PRE-CU cosmetic familiar authority contract passed."
