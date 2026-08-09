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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PlayerOwnedRetainedContentControllerClosure)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $source "dsrc"
$scriptRoot = Join-Path $dsrc "sku.0/sys.server/compiled/game/script"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-BracedSurface([string]$Text, [string]$Marker)
{
    $start = $Text.IndexOf($Marker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf('{', $start)
    if ($open -lt 0) { return "" }
    $depth = 1
    for ($index = $open + 1; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

function Get-ReferencedContract([string]$ManifestKey)
{
    $relativePath = [string]$manifest.contracts.$ManifestKey
    return Get-Content -LiteralPath (Join-Path $restorationRoot $relativePath) -Raw | ConvertFrom-Json
}

$sourceMap = [ordered]@{
    "ai/beast.java" = Join-Path $scriptRoot "ai/beast.java"
    "library/beast_lib.java" = Join-Path $scriptRoot "library/beast_lib.java"
    "ai/pet.java" = Join-Path $scriptRoot "ai/pet.java"
    "library/pet_lib.java" = Join-Path $scriptRoot "library/pet_lib.java"
    "ai/officer_pet.java" = Join-Path $scriptRoot "ai/officer_pet.java"
    "systems/combat/combat_supply_drop_controller.java" = Join-Path $scriptRoot "systems/combat/combat_supply_drop_controller.java"
    "systems/combat/combat_supply_drop_crate.java" = Join-Path $scriptRoot "systems/combat/combat_supply_drop_crate.java"
    "systems/buff/buff_handler.java" = Join-Path $scriptRoot "systems/buff/buff_handler.java"
    "ai/familiar.java" = Join-Path $scriptRoot "ai/familiar.java"
    "library/faction_perk.java" = Join-Path $scriptRoot "library/faction_perk.java"
}
Assert-Contract ($sourceMap.Count -eq [int]$contract.expected.authoritativeSourceFiles) `
    "p14.player-owned-controller.authoritative-source-count"
$sourceTexts = @{}
foreach ($entry in $sourceMap.GetEnumerator())
{
    Assert-Contract (Test-Path -LiteralPath $entry.Value -PathType Leaf) `
        "p14.player-owned-controller.source.$($entry.Key).exists"
    if (Test-Path -LiteralPath $entry.Value -PathType Leaf)
    {
        $sourceTexts[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        Assert-Contract ($hash -ceq [string]$contract.buildEvidence.sourceSha256.($entry.Key)) `
            "p14.player-owned-controller.source.$($entry.Key).authenticated"
    }
}

$beastAi = [string]$sourceTexts["ai/beast.java"]
$beastLibrary = [string]$sourceTexts["library/beast_lib.java"]
$retirementHelper = Get-BracedSurface $beastAi "public boolean retirePostNgePlayerOwnedRuntime(obj_id self)"
$retiredPredicate = Get-BracedSurface $beastLibrary "public static boolean isRetiredPostNgeBeastMasterPlayer(obj_id player)"
$playerOwnedPredicate = Get-BracedSurface $beastLibrary "public static boolean isRetiredPostNgePlayerOwnedBeast(obj_id beast)"
Assert-Contract (
    $retirementHelper.Contains("beast_lib.isRetiredPostNgePlayerOwnedBeast(self)") -and
    $retirementHelper.Contains("beast_lib.retirePostNgeBeastMasterPlayerState(master)") -and
    $retirementHelper.Contains("isIdValid(self) && exists(self)") -and
    $retirementHelper.Contains("destroyObject(self)") -and
    $retirementHelper.IndexOf("retirePostNgeBeastMasterPlayerState", [System.StringComparison]::Ordinal) -lt
        $retirementHelper.IndexOf("destroyObject(self)", [System.StringComparison]::Ordinal)
) "p14.player-owned-controller.beast-safe-store-unlink-destroy-order"
Assert-Contract (
    $retiredPredicate.Contains("isPostNgeBeastMasterPlayerRuntimeRetired()") -and
    $retiredPredicate.Contains("isPlayer(player)") -and
    $playerOwnedPredicate.Contains("getMaster(beast)") -and
    $playerOwnedPredicate.Contains("isRetiredPostNgeBeastMasterPlayer")
) "p14.player-owned-controller.beast-player-only-ownership-predicate"

$beastRoots = @(
    @{ Name = "OnAttach"; Signature = "public int OnAttach(obj_id self)"; Mutation = 'setObjVar(self, "beast.pingMessageNumber"' },
    @{ Name = "OnAddedToWorld"; Signature = "public int OnAddedToWorld(obj_id self)"; Mutation = 'messageTo(self, "handleSetupBeast"' },
    @{ Name = "handleSetupBeast"; Signature = "public int handleSetupBeast(obj_id self, dictionary params)"; Mutation = "isMob(self)" },
    @{ Name = "beastPing"; Signature = "public int beastPing(obj_id self, dictionary params)"; Mutation = 'getIntObjVar(self, "beast.pingMessageNumber"' }
)
Assert-Contract ($beastRoots.Count -eq [int]$contract.expected.beastControllerAdmissionAndLifecycleRoots) `
    "p14.player-owned-controller.beast-root-count"
foreach ($root in $beastRoots)
{
    $body = Get-BracedSurface $beastAi $root.Signature
    $guard = $body.IndexOf("retirePostNgePlayerOwnedRuntime(self)", [System.StringComparison]::Ordinal)
    $return = $body.IndexOf("return SCRIPT_OVERRIDE;", [System.StringComparison]::Ordinal)
    $mutation = $body.IndexOf($root.Mutation, [System.StringComparison]::Ordinal)
    Assert-Contract ($guard -ge 0 -and $return -gt $guard -and $mutation -gt $return) `
        "p14.player-owned-controller.beast-root.$($root.Name).fails-closed"
}
Assert-Contract (
    -not (Get-BracedSurface $beastAi "public int OnDetach(obj_id self)").Contains("retirePostNgePlayerOwnedRuntime") -and
    -not (Get-BracedSurface $beastAi "public int OnDestroy(obj_id self)").Contains("retirePostNgePlayerOwnedRuntime") -and
    $beastLibrary.Contains('attachScript(beast, "ai.beast")')
) "p14.player-owned-controller.beast-cleanup-and-nonplayer-compatibility-preserved"

$petAi = [string]$sourceTexts["ai/pet.java"]
$petLibrary = [string]$sourceTexts["library/pet_lib.java"]
$petAttach = Get-BracedSurface $petAi "public int OnAttach(obj_id self)"
Assert-Contract (
    $petAttach.Contains("pet_lib.PET_TYPE_FAMILIAR") -and
    $petAttach.Contains('attachScript(self, "ai.familiar")') -and
    $petAttach.Contains('detachScript(self, "systems.combat.combat_actions")') -and
    $petAttach.Contains('detachScript(self, "ai.ai")')
) "p14.player-owned-controller.familiar-routes-to-cosmetic-controller"
Assert-Contract (
    $petLibrary.Contains('getSkillStatMod(player, "tame_level")') -and
    $petLibrary.Contains('getSkillStatMod(player, "tame_aggro")') -and
    $petLibrary.Contains('hasSkill(player, "outdoors_creaturehandler_novice")') -and
    $petLibrary.Contains("PET_TYPE_DROID")
) "p14.player-owned-controller.precu-pet-and-droid-control-preserved"

$officerPet = [string]$sourceTexts["ai/officer_pet.java"]
$supplyController = [string]$sourceTexts["systems/combat/combat_supply_drop_controller.java"]
$supplyCrate = [string]$sourceTexts["systems/combat/combat_supply_drop_crate.java"]
Assert-Contract (
    $officerPet.Contains("retirePostNgeOfficerPet") -and
    ([regex]::Matches($officerPet, "retirePostNgeOfficerPet\(self, master\)").Count -eq 2) -and
    $officerPet.Contains("isPlayer(master)") -and
    $supplyController.Contains("retirePostNgeOfficerSupplyDrop") -and
    $supplyCrate.Contains("retirePostNgeOfficerSupplyCrate")
) "p14.player-owned-controller.officer-pet-and-supply-controller-retirement"

$buffHandler = [string]$sourceTexts["systems/buff/buff_handler.java"]
$miniTurret = Get-BracedSurface $buffHandler "public int gcwMiniTurretAddBuffHandler"
Assert-Contract (
    $miniTurret.IndexOf("buff.isPostNgeBuffProgressionRetired()", [System.StringComparison]::Ordinal) -ge 0 -and
    $miniTurret.IndexOf("return SCRIPT_CONTINUE;", [System.StringComparison]::Ordinal) -lt
        $miniTurret.IndexOf("advanced_turret.createTurret", [System.StringComparison]::Ordinal)
) "p14.player-owned-controller.autonomous-gcw-consumable-turret-retired"

$referenced = [ordered]@{
    Beast = Get-ReferencedContract "p14PostNgeBeastMasterPlayerRuntimeRetirement"
    DroidModules = Get-ReferencedContract "p14PostNgeDroidCombatModuleRuntimeRetirement"
    Officer = Get-ReferencedContract "p14PrecuProfessionAuthorityClosure"
    GcwTurret = Get-ReferencedContract "p14PostNgeBuffProgressionRetirement"
    Familiar = Get-ReferencedContract "p14PrecuCosmeticFamiliarAuthority"
    PetControl = Get-ReferencedContract "p14PrecuPetControlAuthority"
    DroidDetonation = Get-ReferencedContract "p14PrecuDroidDetonationAuthority"
    FactionHireling = Get-ReferencedContract "p14PrecuFactionReinforcementAuthority"
    BarnDisplay = Get-ReferencedContract "p14PrecuTcgBarnDisplayAuthority"
}
foreach ($entry in $referenced.GetEnumerator())
{
    Assert-Contract ([string]$entry.Value.status -ceq "ready") `
        "p14.player-owned-controller.referenced-contract.$($entry.Key).ready"
}
Assert-Contract (
    -not [bool]$referenced.Beast.expected.playerOwnedBeastExperienceWritersReachable -and
    [bool]$referenced.Beast.expected.nonPlayerBeastFamilyCompatibilityPreserved -and
    [bool]$referenced.DroidModules.expected.playerOwnedRuntimeFailsClosed -and
    [bool]$referenced.DroidModules.expected.classicDroidControlsPreserved -and
    [bool]$referenced.Officer.expected.postNgeOfficerPersistedPetsRetired -and
    [bool]$referenced.Officer.expected.postNgeOfficerDelayedDropsRetired -and
    -not [bool]$referenced.GcwTurret.expected.postNgeMiniTurretCreationReachable -and
    [int]$referenced.Familiar.expected.familiarBuffApplicationCalls -eq 0 -and
    [bool]$referenced.PetControl.expected.activeCreatureLevelsCountAgainstControl -and
    [bool]$referenced.DroidDetonation.expected.droidConsumptionAndCombatCreditPreserved -and
    [int]$referenced.FactionHireling.expected.playerLevelReads -eq 0 -and
    [bool]$referenced.BarnDisplay.expected.playerBeastMasterRuntimeRetirementPreserved
) "p14.player-owned-controller.six-family-contract-boundary"

Assert-Contract ([int]$contract.expected.auditedControllerFamilies -eq 6 -and
    -not [bool]$contract.expected.postNgePlayerOwnedBeastControllerReachable -and
    -not [bool]$contract.expected.postNgePlayerDroidCombatModulesReachable -and
    -not [bool]$contract.expected.postNgePlayerOfficerControllersReachable -and
    -not [bool]$contract.expected.postNgePlayerAutonomousGcwTurretCreationReachable -and
    -not [bool]$contract.expected.familiarCombatAuthorityReachable -and
    [bool]$contract.expected.precuCreatureHandlerPetRuntimePreserved -and
    [bool]$contract.expected.nonPlayerExpansionControllerCompatibilityPreserved) `
    "p14.player-owned-controller.expected-boundary"

$directCommit = (& git -C $dsrc rev-parse HEAD).Trim()
Assert-Contract ($LASTEXITCODE -eq 0 -and $directCommit -ceq [string]$contract.buildEvidence.directSourceCommit) `
    "p14.player-owned-controller.direct-source-pin"
Assert-Contract ([string]$contract.status -in @("source-ready", "ready") -and
    [string]$contract.buildEvidence.result -ceq "passed") "p14.player-owned-controller.contract-status"
if ($Expectation -eq "Ready")
{
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        [string]$contract.runtimeEvidence.result -ceq "passed" -and
        [bool]$contract.runtimeEvidence.clusterReadyForPlayers -and
        [bool]$contract.runtimeEvidence.liveProcessMappedBuiltBinary -and
        [string]$contract.runtimeEvidence.deployedDirectSourceCommit -ceq $directCommit -and
        $contract.requiredBeforeReady.Count -eq 0) "p14.player-owned-controller.ready-evidence"
}
Assert-Contract (-not (Test-Path -LiteralPath (Join-Path $source "Artifacts")) -and
    -not (Test-Path -LiteralPath (Join-Path $source "Staging"))) `
    "p14.player-owned-controller.no-host-staging"

if ($failures.Count -gt 0)
{
    throw "Player-owned retained-content controller closure failed: $($failures -join ', ')"
}
Write-Host "Publish 14.1 player-owned retained-content controller closure passed (six families)."
