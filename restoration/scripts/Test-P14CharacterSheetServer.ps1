[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $restorationRoot "manifest.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14CharacterSheetServer)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}

foreach ($path in $paths.Values)
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required materialized character-sheet source is missing: $path"
    }
}

$commandCpp = Get-Content -LiteralPath $paths.commandCpp -Raw
$playerHeader = Get-Content -LiteralPath $paths.playerHeader -Raw
$playerCpp = Get-Content -LiteralPath $paths.playerCpp -Raw
$buildingCpp = Get-Content -LiteralPath $paths.buildingCpp -Raw
$creatureCpp = Get-Content -LiteralPath $paths.creatureCpp -Raw
$responseHeader = Get-Content -LiteralPath $paths.responseHeader -Raw
$gameServer = Get-Content -LiteralPath $paths.gameServer -Raw
$packageData = Get-Content -LiteralPath $paths.packageData -Raw
$cloningLibrary = Get-Content -LiteralPath $paths.cloningLibrary -Raw
$bankScript = Get-Content -LiteralPath $paths.bankScript -Raw

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Contract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

function Get-BracedBlock
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Signature
    )

    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0)
    {
        return ""
    }

    $openBrace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($openBrace -lt 0)
    {
        return ""
    }

    $depth = 0
    for ($index = $openBrace; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{')
        {
            $depth++
        }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }

    return ""
}

$producer = Get-BracedBlock -Text $commandCpp -Signature ([string]$contract.producerSignature)
$bornField = [string]$contract.modelFields.bornDate
$playedField = [string]$contract.modelFields.playedTime
$accountMaxLotsAdjustmentField = [string]$contract.modelFields.accountMaxLotsAdjustment
$bindLocationObjvar = [string]$contract.objvars.bindLocation
$bindFacilityObjvar = [string]$contract.objvars.bindFacility
$bankPlanetObjvar = [string]$contract.objvars.lastBankTerminalPlanet
$remoteResidenceRequest = [string]$contract.residence.remoteRequest
$responseConstructor = [string]$contract.responseConstructor

Write-Host "Publish 14.1 character-sheet server checks:"

Assert-Contract `
    -Condition (([bool]$contract.transportAdapter.wireEquivalentToCore3 -eq $false) -and ([string]$contract.transportAdapter.retainedEnvelope -eq [string]$contract.sourceFiles.responseHeader)) `
    -Name "p14.character-sheet.transport.semantic-adapter-not-wire-equivalence"
Assert-Contract `
    -Condition ($responseHeader.Contains("CharacterSheetResponseMessage (int bornDate, int played") -and $responseHeader.Contains("const std::string& citizensOf") -and $responseHeader.Contains("int                    getLotsUsed")) `
    -Name "p14.character-sheet.transport.retained-swgsource-envelope"

Assert-Contract -Condition ($producer.Length -gt 0) -Name "p14.character-sheet.producer-present"
Assert-Contract `
    -Condition ([regex]::IsMatch($packageData, "(?m)^PlayerObject\s+$([regex]::Escape($bornField))\s+shared\s+int\s*$")) `
    -Name "p14.character-sheet.model.born-date-persisted"
Assert-Contract `
    -Condition ([regex]::IsMatch($packageData, "(?m)^PlayerObject\s+$([regex]::Escape($playedField))\s+shared\s+int\s*$")) `
    -Name "p14.character-sheet.model.played-time-persisted"
Assert-Contract `
    -Condition ([regex]::IsMatch($packageData, "(?m)^PlayerObject\s+$([regex]::Escape($accountMaxLotsAdjustmentField))\s+server\s+int\s*$")) `
    -Name "p14.character-sheet.model.account-max-lots-adjustment-persisted"
Assert-Contract `
    -Condition ($playerHeader.Contains("int                  getBornDate() const;") -and $playerHeader.Contains("uint32               getPlayedTime() const;") -and $playerHeader.Contains("int                                 getAccountMaxLotsAdjustment() const;")) `
    -Name "p14.character-sheet.model.accessors-present"

$bornGetter = Get-BracedBlock -Text $playerHeader -Signature "inline int PlayerObject::getBornDate() const"
$lotsAdjustmentGetter = Get-BracedBlock -Text $playerHeader -Signature "inline int PlayerObject::getAccountMaxLotsAdjustment() const"
$playedGetter = Get-BracedBlock -Text $playerCpp -Signature "uint32 PlayerObject::getPlayedTime() const"
$playedAccumulator = Get-BracedBlock -Text $playerCpp -Signature "void PlayerObject::alterPlayedTime(float time)"
Assert-Contract `
    -Condition ($bornGetter.Contains("return m_bornDate.get();") -and $gameServer.Contains("play->setBornDate();")) `
    -Name "p14.character-sheet.model.born-date-initialized-and-readable"
Assert-Contract `
    -Condition ($playedGetter.Contains("m_playedTime.get() + m_playedTimeAccum") -and $playedAccumulator.Contains("m_playedTime = m_playedTime.get()")) `
    -Name "p14.character-sheet.model.played-time-includes-current-accumulator"
Assert-Contract `
    -Condition ($lotsAdjustmentGetter.Contains("return m_accountMaxLotsAdjustment.get();")) `
    -Name "p14.character-sheet.model.account-max-lots-adjustment-readable"

$playerAt = $producer.IndexOf("PlayerCreatureController::getPlayerObject(creatureActor)", [StringComparison]::Ordinal)
$bornAt = $producer.IndexOf("player ? player->getBornDate() : 0", [StringComparison]::Ordinal)
$playedAt = $producer.IndexOf("player ? static_cast<int>(player->getPlayedTime()) : 0", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($playerAt -ge 0 -and $bornAt -gt $playerAt -and $playedAt -gt $bornAt) `
    -Name "p14.character-sheet.response.persisted-born-and-played"
Assert-Contract `
    -Condition (-not $producer.Contains("TODO get the born and played times") -and -not $producer.Contains("int born = 0;") -and -not $producer.Contains("int played = 0;")) `
    -Name "p14.character-sheet.response.no-placeholder-born-or-played"

$bindLocationAt = $producer.IndexOf("getItem(`"$bindLocationObjvar`", bindLocation)", [StringComparison]::Ordinal)
$bindPositionAt = $producer.IndexOf("bindLoc = bindLocation.pos;", [StringComparison]::Ordinal)
$bindSceneAt = $producer.IndexOf("bindPlanet = bindLocation.scene;", [StringComparison]::Ordinal)
$bindFacilityAt = $producer.IndexOf("getItem(`"$bindFacilityObjvar`", bindId)", [StringComparison]::Ordinal)
$bindFallbackAt = $producer.IndexOf("ServerObject::getServerObject(bindId)", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($bindLocationAt -ge 0 -and $bindPositionAt -gt $bindLocationAt -and $bindSceneAt -gt $bindPositionAt -and $bindFacilityAt -gt $bindSceneAt -and $bindFallbackAt -gt $bindFacilityAt) `
    -Name "p14.character-sheet.bind.persisted-location-with-facility-fallback"
Assert-Contract `
    -Condition ($cloningLibrary.Contains("setObjVar(player, VAR_BIND_FACILITY, cloningFacility);") -and $cloningLibrary.Contains("setObjVar(player, VAR_BIND_LOCATION, cloneLoc);")) `
    -Name "p14.character-sheet.bind.objvars-populated-together"

Assert-Contract `
    -Condition ($producer.Contains("Vector bankLoc(0, 0, 0);") -and $producer.Contains("getItem(`"$bankPlanetObjvar`", bankPlanet)") -and -not $producer.Contains("open_bank_location")) `
    -Name "p14.character-sheet.bank.persisted-planet-without-fabricated-coordinates"
Assert-Contract `
    -Condition ($bankScript.Contains("setObjVar(player, `"$bankPlanetObjvar`", getCurrentSceneName());")) `
    -Name "p14.character-sheet.bank.planet-populated-by-terminal"

$residenceAt = $producer.IndexOf("NetworkId houseNetworkId = creatureActor->getHouse();", [StringComparison]::Ordinal)
$residencePositionAt = $producer.IndexOf("resLoc = resObject->getPosition_w();", [StringComparison]::Ordinal)
$residenceSceneAt = $producer.IndexOf("resPlanet = resObject->getSceneId();", [StringComparison]::Ordinal)
$remoteResidenceAt = $producer.IndexOf($remoteResidenceRequest, [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($residenceAt -ge 0 -and $residencePositionAt -gt $residenceAt -and $residenceSceneAt -gt $residencePositionAt -and $remoteResidenceAt -gt $residenceSceneAt) `
    -Name "p14.character-sheet.residence.local-data-and-remote-fallback"
Assert-Contract `
    -Condition (-not $producer.Contains("resPlanet = ServerWorld::getSceneId();")) `
    -Name "p14.character-sheet.residence.scene-owned-by-residence"

$buildingHandler = Get-BracedBlock -Text $buildingCpp -Signature "void BuildingObject::handleCMessageTo(const MessageToPayload &message)"
$creatureHandler = Get-BracedBlock -Text $creatureCpp -Signature "void CreatureObject::handleCMessageTo(MessageToPayload const &message)"
$buildingRequestAt = $buildingHandler.IndexOf($remoteResidenceRequest, [StringComparison]::Ordinal)
$buildingRequesterAt = $buildingHandler.IndexOf("NetworkId const idRequester(packedData);", [StringComparison]::Ordinal)
$buildingResponseAt = $buildingHandler.IndexOf("C++CharacterSheetInfoResidenceLocationRsp", [StringComparison]::Ordinal)
$buildingSendAt = $buildingHandler.IndexOf("sendMessageToC(idRequester", [StringComparison]::Ordinal)
$creatureResponseAt = $creatureHandler.IndexOf("C++CharacterSheetInfoResidenceLocationRsp", [StringComparison]::Ordinal)
$clientResponseAt = $creatureHandler.IndexOf('GenericValueTypeMessage<std::pair<std::string, std::string> > message("CharacterSheetResponseResLoc"', [StringComparison]::Ordinal)
$actorClientAt = $creatureHandler.IndexOf("Client * const client = getClient();", [StringComparison]::Ordinal)
$actorSendAt = $creatureHandler.IndexOf("client->send(message, true);", [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($buildingRequestAt -ge 0 -and $buildingRequesterAt -gt $buildingRequestAt -and $buildingSendAt -gt $buildingRequesterAt -and $buildingResponseAt -gt $buildingSendAt) `
    -Name "p14.character-sheet.residence.remote-building-response"
Assert-Contract `
    -Condition ($creatureResponseAt -ge 0 -and $clientResponseAt -gt $creatureResponseAt -and $actorClientAt -gt $clientResponseAt -and $actorSendAt -gt $actorClientAt) `
    -Name "p14.character-sheet.residence.remote-actor-client-delivery"

$maxLotsAt = $producer.IndexOf("int lots = ConfigServerGame::getMaxLotsPerAccount();", [StringComparison]::Ordinal)
$adjustedLotsAt = $producer.IndexOf("lots += player->getAccountMaxLotsAdjustment();", [StringComparison]::Ordinal)
$usedLotsAt = $producer.IndexOf("player->getAccountNumLots();", [StringComparison]::Ordinal)
$remainingLotsAt = $producer.IndexOf("lots -= lotsUsed;", [StringComparison]::Ordinal)
$responseAt = $producer.IndexOf($responseConstructor, [StringComparison]::Ordinal)
Assert-Contract `
    -Condition ($maxLotsAt -ge 0 -and $adjustedLotsAt -gt $maxLotsAt -and $usedLotsAt -gt $adjustedLotsAt -and $remainingLotsAt -gt $usedLotsAt -and $responseAt -gt $remainingLotsAt -and -not $producer.Contains("creatureActor->getMaxNumberOfLots()")) `
    -Name "p14.character-sheet.lots.authoritative-adjusted-remaining-sent"
Assert-Contract `
    -Condition ($producer.Contains($responseConstructor)) `
    -Name "p14.character-sheet.response.field-order"

Assert-Contract `
    -Condition (-not [string]::IsNullOrWhiteSpace([string]$contract.knownLimitations.bankCoordinates)) `
    -Name "p14.character-sheet.limit.bank-coordinates-documented"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 character-sheet server contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 character-sheet server contract passed."
