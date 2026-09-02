[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifestPath = Join-Path $restorationRoot "manifest.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.rebornForceThreadsShadow)
$gatePath = Join-Path $restorationRoot ([string]$manifest.contracts.rebornForceThreadsGate)
$progressionPath = Join-Path $restorationRoot ([string]$manifest.contracts.rebornForceProgressionGate)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$gate = Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json
$progressionContract = Get-Content -LiteralPath $progressionPath -Raw | ConvertFrom-Json
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

function Get-SourceText
{
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = Join-Path $repositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        return ""
    }
    return Get-Content -LiteralPath $path -Raw
}

function Get-JavaMethodBody
{
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$MethodName
    )

    $match = [regex]::Match(
        $Text,
        "(?m)^[ \t]*(?:public|private|protected)[ \t]+(?:static[ \t]+)?[A-Za-z0-9_<>\[\]]+[ \t]+" +
            [regex]::Escape($MethodName) + "[ \t]*\(")
    if (-not $match.Success)
    {
        return ""
    }

    $open = $Text.IndexOf("{", $match.Index + $match.Length)
    if ($open -lt 0)
    {
        return ""
    }

    $depth = 0
    $inString = $false
    $inCharacter = $false
    $escaped = $false
    for ($index = $open; $index -lt $Text.Length; $index++)
    {
        $character = $Text[$index]
        if ($escaped)
        {
            $escaped = $false
            continue
        }
        if (($inString -or $inCharacter) -and $character -eq '\')
        {
            $escaped = $true
            continue
        }
        if (-not $inCharacter -and $character -eq '"')
        {
            $inString = -not $inString
            continue
        }
        if (-not $inString -and $character -eq "'")
        {
            $inCharacter = -not $inCharacter
            continue
        }
        if ($inString -or $inCharacter)
        {
            continue
        }
        if ($character -eq '{')
        {
            $depth++
        }
        elseif ($character -eq '}')
        {
            $depth--
            if ($depth -eq 0)
            {
                return $Text.Substring($open, $index - $open + 1)
            }
        }
    }
    return ""
}

function Test-AllHandlersGuarded
{
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $matches = [regex]::Matches(
        $Text,
        "(?m)^[ \t]*public[ \t]+int[ \t]+(?<name>(?:On|handle)[A-Za-z0-9_]*)[ \t]*\(")
    Assert-Contract -Condition ($matches.Count -gt 0) -Name "$Label.handlers.present"
    foreach ($match in $matches)
    {
        $name = [string]$match.Groups["name"].Value
        $body = Get-JavaMethodBody -Text $Text -MethodName $name
        $guard = [regex]::Match(
            $body,
            "\{[ \t\r\n]*if[ \t]*\([ \t]*!force_threads\.isShadowEnabled\(\)[ \t]*\)")
        Assert-Contract -Condition $guard.Success -Name "$Label.$name.default-off-guard"
    }
}

function Test-ContainsNoTerms
{
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][object[]]$Terms,
        [Parameter(Mandatory = $true)][string]$Label
    )

    foreach ($termObject in $Terms)
    {
        $term = [string]$termObject
        Assert-Contract -Condition (
            $Text.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -lt 0) `
            -Name "$Label.$term.absent"
    }
}

function Assert-JavaIntConstant
{
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $pattern = "(?m)^[ \t]*(?:public[ \t]+)?static[ \t]+final[ \t]+int[ \t]+" +
        [regex]::Escape($Name) + "[ \t]*=[ \t]*" + [string]$Expected + "[ \t]*;"
    Assert-Contract -Condition ([regex]::IsMatch($Text, $pattern)) -Name $Label
}

Write-Host "Reborn Force Threads default-off shadow checks:"

Assert-Contract -Condition (
    [string]$manifest.sourceMode -ceq "direct-branch" -and
    [string]$manifest.contracts.rebornForceThreadsShadow -ceq
        "contracts/reborn-force-threads-shadow.json" -and
    (Test-Path -LiteralPath $contractPath -PathType Leaf)) `
    -Name "reborn.force-threads.shadow.manifest.registration"

Assert-Contract -Condition (
    [int]$contract.schemaVersion -eq 1 -and
    [string]$contract.feature -ceq "reborn-force-threads-shadow" -and
    [string]$contract.status -ceq "implemented-static-pending-compile" -and
    -not [bool]$contract.authority.gameplayActivationAuthorized -and
    -not [bool]$contract.authority.forceSensitiveOrJediAwardAuthorized -and
    -not [bool]$contract.authority.villageHandoffAuthorized) `
    -Name "reborn.force-threads.shadow.static-only-status"

$sourceProperties = @(
    "library",
    "playerReceiver",
    "campProbe",
    "playerHook",
    "advancedCampCraftingHook",
    "advancedCampHook"
)
$sourceTexts = @{}
foreach ($property in $sourceProperties)
{
    $relativePath = [string]$contract.sourceFiles.$property
    $absolutePath = Join-Path $repositoryRoot $relativePath
    Assert-Contract -Condition (Test-Path -LiteralPath $absolutePath -PathType Leaf) `
        -Name "reborn.force-threads.shadow.source.$property"
    $sourceTexts[$property] = Get-SourceText -RelativePath $relativePath
}

$library = [string]$sourceTexts["library"]
$playerReceiver = [string]$sourceTexts["playerReceiver"]
$campProbe = [string]$sourceTexts["campProbe"]
$playerHook = [string]$sourceTexts["playerHook"]
$advancedCampCraftingHook = [string]$sourceTexts["advancedCampCraftingHook"]
$advancedCampHook = [string]$sourceTexts["advancedCampHook"]
$featureSources = $library + "`n" + $playerReceiver + "`n" + $campProbe
$dsrcAddedLines = @($sourceProperties | ForEach-Object {
    $relativePath = [string]$contract.sourceFiles.$_
    if ($relativePath.StartsWith("dsrc/", [StringComparison]::Ordinal))
    {
        $dsrcPath = $relativePath.Substring(5)
        & git -C (Join-Path $repositoryRoot "dsrc") diff --no-ext-diff --unified=0 -- $dsrcPath | Where-Object {
            ([string]$_).StartsWith("+") -and -not ([string]$_).StartsWith("+++")
        } | ForEach-Object { ([string]$_).Substring(1) }
    }
})
$shadowSafetyText = $featureSources + "`n" + ($dsrcAddedLines -join "`n")

$shadowModeBody = Get-JavaMethodBody -Text $library -MethodName "isShadowEnabled"
$expectedModeRead = 'getConfigSetting("' + [string]$contract.modeContract.section + '", "' +
    [string]$contract.modeContract.key + '")'
Assert-Contract -Condition (
    $shadowModeBody.Contains($expectedModeRead) -and
    $shadowModeBody.Contains('"shadow".equals(') -and
    -not $shadowModeBody.Contains("equalsIgnoreCase") -and
    -not $shadowModeBody.Contains("||") -and
    [string]$contract.modeContract.absentMode -ceq "off" -and
    [string]$contract.modeContract.comparison -ceq "case-sensitive-exact" -and
    -not [bool]$contract.modeContract.declaredInRuntimeConfig) `
    -Name "reborn.force-threads.shadow.mode.exact-and-absent-default"

$exeRoot = Join-Path $repositoryRoot "exe"
$configMatches = @(& git -C $exeRoot grep -n -I -- "rebornForceThreadsMode" 2>$null)
$configGrepExit = $LASTEXITCODE
Assert-Contract -Condition ($configGrepExit -eq 1 -and $configMatches.Count -eq 0) `
    -Name "reborn.force-threads.shadow.mode.not-declared-in-exe"

Test-AllHandlersGuarded -Text $playerReceiver -Label "reborn.force-threads.shadow.player-receiver"
Test-AllHandlersGuarded -Text $campProbe -Label "reborn.force-threads.shadow.camp-probe"

$baseOnInitialize = Get-JavaMethodBody -Text $playerHook -MethodName "OnInitialize"
$attachReceiverCall = "force_threads.attachPlayerReceiver(self);"
$attachReceiverIndex = $baseOnInitialize.IndexOf($attachReceiverCall, [StringComparison]::Ordinal)
$attachReceiverBody = Get-JavaMethodBody -Text $library -MethodName "attachPlayerReceiver"
Assert-Contract -Condition (
    $attachReceiverIndex -ge 0 -and
    $attachReceiverBody.Contains("!isShadowEnabled()") -and
    $attachReceiverBody.Contains("attachScript(player, PLAYER_SCRIPT)")) `
    -Name "reborn.force-threads.shadow.player-receiver.ensure-on-initialize"

$craftingHookBody = Get-JavaMethodBody -Text $advancedCampCraftingHook -MethodName "OnManufactureObject"
$craftingSuperIndex = $craftingHookBody.IndexOf("super.OnManufactureObject(", [StringComparison]::Ordinal)
$craftingStampIndex = $craftingHookBody.IndexOf(
    "force_threads.stampCraftedCampDeed(newObject, player);",
    [StringComparison]::Ordinal)
$stampBody = Get-JavaMethodBody -Text $library -MethodName "stampCraftedCampDeed"
$advancedDeedBody = Get-JavaMethodBody -Text $library -MethodName "isAdvancedCampDeed"
Assert-Contract -Condition (
    $craftingSuperIndex -ge 0 -and
    $craftingStampIndex -gt $craftingSuperIndex -and
    $stampBody.Contains("!isShadowEnabled()") -and
    $stampBody.Contains("!isAdvancedCampDeed(newObject)") -and
    $advancedDeedBody.Contains("isAdvancedCampDeedTemplate(getTemplateName(deed))")) `
    -Name "reborn.force-threads.shadow.crafting.super-before-narrow-stamp"

$dsrcRoot = Join-Path $repositoryRoot "dsrc"
$stampCallFiles = @(& git -C $dsrcRoot grep -l -F -- "force_threads.stampCraftedCampDeed(" -- "*.java" 2>$null)
$expectedStampCallFile = "sku.0/sys.server/compiled/game/script/systems/crafting/camp/crafting_camp.java"
Assert-Contract -Condition (
    $stampCallFiles.Count -eq 1 -and
    ([string]$stampCallFiles[0]).Replace("\", "/") -ceq $expectedStampCallFile) `
    -Name "reborn.force-threads.shadow.crafting.advanced-camp-hook-only"

$campInitializeHookBody = Get-JavaMethodBody -Text $advancedCampHook -MethodName "initializeAdvancedCamp"
$probeInitializeIndex = $campInitializeHookBody.IndexOf(
    "force_threads.initializeAdvancedCamp(deed, camp, player);",
    [StringComparison]::Ordinal)
$stockCampAttachIndex = $campInitializeHookBody.IndexOf(
    'attachScript(camp, "item.camp.camp_advanced");',
    [StringComparison]::Ordinal)
$probeInitializeBody = Get-JavaMethodBody -Text $library -MethodName "initializeAdvancedCamp"
Assert-Contract -Condition (
    $probeInitializeIndex -ge 0 -and
    $stockCampAttachIndex -gt $probeInitializeIndex -and
    $probeInitializeBody.Contains("!isShadowEnabled()") -and
    $probeInitializeBody.Contains("attachScript(camp, CAMP_PROBE_SCRIPT)") -and
    $probeInitializeBody.IndexOf("attachScript(camp, CAMP_PROBE_SCRIPT)", [StringComparison]::Ordinal) -lt
        $probeInitializeBody.IndexOf("setObjVar(camp, CAMP_READY, 1)", [StringComparison]::Ordinal)) `
    -Name "reborn.force-threads.shadow.camp.probe-before-stock-script"

$domains = @($contract.verticalSlice.domains | ForEach-Object { [string]$_ })
$allowlist = @($contract.provisionalOutcomeAllowlist.questNames | ForEach-Object { [string]$_ })
$expectedAllowlist = @(
    "quest/purvis_recon_one",
    "quest/purvis_kill_warriors",
    "quest/purvis_kill_soldiers"
)
Assert-Contract -Condition (
    ($domains -join ",") -ceq "PROVENANCE,SHELTER,OUTCOME" -and
    [int]$contract.verticalSlice.minimumContinuousDwellSeconds -eq 180 -and
    [bool]$contract.verticalSlice.positiveHealingBenefitRequired -and
    [bool]$contract.verticalSlice.sameAdvancedCampRequired -and
    [string]$contract.verticalSlice.participants -ceq "three-distinct-positive-station-ids" -and
    -not [bool]$contract.verticalSlice.sameAccountCredit) `
    -Name "reborn.force-threads.shadow.vertical-slice.contract"
Assert-Contract -Condition (
    ($allowlist -join ",") -ceq ($expectedAllowlist -join ",") -and
    [string]$contract.provisionalOutcomeAllowlist.authority -ceq
        "shadow-instrumentation-only-not-final-design-authority" -and
    -not [bool]$contract.provisionalOutcomeAllowlist.forceSensitiveVillagePvpOrLegacyThemeParkEntries) `
    -Name "reborn.force-threads.shadow.outcome.allowlist-contract"

$healingHandlerBody = Get-JavaMethodBody -Text $playerReceiver -MethodName "OnHealingReceived"
$healingObserverBody = Get-JavaMethodBody -Text $library -MethodName "observeAdvancedCampHealing"
$visitBeginBody = Get-JavaMethodBody -Text $library -MethodName "beginAdvancedCampVisit"
$visitEndBody = Get-JavaMethodBody -Text $library -MethodName "endAdvancedCampVisit"
$dwellBody = Get-JavaMethodBody -Text $library -MethodName "completeAdvancedCampDwell"
Assert-Contract -Condition (
    $healingHandlerBody.Contains("force_threads.observeAdvancedCampHealing(self, actualDelta);") -and
    $healingObserverBody.Contains("actualDelta <= 0") -and
    $healingObserverBody.Contains("camping.getCurrentAdvancedCamp(player)") -and
    $healingObserverBody.Contains("isInTriggerVolume(camp, CAMP_VOLUME, player)") -and
    $healingObserverBody.Contains('"|1"')) `
    -Name "reborn.force-threads.shadow.shelter.positive-healing-benefit"
Assert-Contract -Condition (
    $visitBeginBody.Contains("enteredAt = getCalendarTime()") -and
    $visitBeginBody.Contains('messageTo(camp, "handleForceThreadsDwell"') -and
    $visitEndBody.Contains("removeVisitor(getArray(camp, CAMP_VISITORS), visitor)") -and
    $dwellBody.Contains("getCalendarTime() - enteredAt < DWELL_SECONDS") -and
    $dwellBody.Contains("camping.getCurrentAdvancedCamp(visitor) != camp") -and
    $dwellBody.Contains('!fields[3].equals("1")')) `
    -Name "reborn.force-threads.shadow.shelter.continuous-dwell-same-camp"

$threeStationValidation = @(
    "holderStation <= 0",
    "originStation <= 0",
    "deployerStation <= 0",
    "holderStation == originStation",
    "holderStation == deployerStation",
    "originStation == deployerStation"
)
$allDwellStationChecksPresent = $true
foreach ($stationCheck in $threeStationValidation)
{
    if (-not $dwellBody.Contains($stationCheck))
    {
        $allDwellStationChecksPresent = $false
    }
}
$outcomeBody = Get-JavaMethodBody -Text $library -MethodName "observeOutcome"
Assert-Contract -Condition (
    $allDwellStationChecksPresent -and
    $outcomeBody.Contains("playerStation <= 0") -and
    $outcomeBody.Contains("originStation <= 0") -and
    $outcomeBody.Contains("deployerStation <= 0") -and
    $outcomeBody.Contains("originStation == deployerStation") -and
    $outcomeBody.Contains("originStation == holderStation") -and
    $outcomeBody.Contains("deployerStation == holderStation")) `
    -Name "reborn.force-threads.shadow.identity.three-distinct-positive-stations"
Assert-Contract -Condition (
    $dwellBody.Contains("createdAt + TOKEN_LIFETIME_SECONDS") -and
    (Get-JavaMethodBody -Text $library -MethodName "pruneTokens").Contains("utils.stringToInt(fields[9]) >= now") -and
    $library.Contains('"PROVENANCE>SHELTER"') -and
    $library.Contains('"PROVENANCE>SHELTER>OUTCOME"') -and
    -not $library.Contains("PROVENANCE>SHELTER>OUTCOME>")) `
    -Name "reborn.force-threads.shadow.token.ttl-and-maximum-causal-depth"

$expectedLeaves = @("schema", "state", "tokens", "ledger", "outbox", "quarantineReason", "lastReconcile")
$actualLeaves = @($contract.persistenceContract.requiredLeaves | ForEach-Object { [string]$_ })
Assert-Contract -Condition (
    [string]$contract.persistenceContract.root -ceq [string]$gate.persistenceContract.root -and
    ($actualLeaves -join ",") -ceq ($expectedLeaves -join ",") -and
    [int]$contract.persistenceContract.maximumDepth -eq [int]$gate.provisionalLimits.maximumDepth -and
    [int]$contract.persistenceContract.maximumActiveTokens -eq [int]$gate.provisionalLimits.maximumActiveTokens -and
    [int]$contract.persistenceContract.maximumOutboxRecords -eq [int]$gate.provisionalLimits.maximumOutboxRecords -and
    [int]$contract.persistenceContract.maximumSealedSummaries -eq [int]$gate.provisionalLimits.maximumSealedSummaries -and
    [int]$contract.persistenceContract.maximumDedupeIds -eq [int]$gate.provisionalLimits.maximumDedupeIds -and
    [int]$contract.persistenceContract.maximumOfflineMailboxRecords -eq [int]$gate.provisionalLimits.maximumOfflineMailboxRecords -and
    [int]$contract.persistenceContract.tokenLifetimeHours -eq [int]$gate.provisionalLimits.tokenLifetimeHours -and
    [int]$contract.persistenceContract.tokenLifetimeSeconds -eq 259200 -and
    [int]$contract.persistenceContract.maximumPersistentBytes -eq [int]$gate.provisionalLimits.maximumPersistentBytes) `
    -Name "reborn.force-threads.shadow.persistence.matches-blocked-gate"

Assert-JavaIntConstant -Text $library -Name "SCHEMA_VERSION" -Expected 1 `
    -Label "reborn.force-threads.shadow.source-constant.schema"
Assert-JavaIntConstant -Text $library -Name "MINIMUM_SHELTER_SECONDS" -Expected 180 `
    -Label "reborn.force-threads.shadow.source-constant.dwell"
Assert-JavaIntConstant -Text $library -Name "DWELL_SECONDS" -Expected 180 `
    -Label "reborn.force-threads.shadow.source-constant.dwell-runtime-alias"
Assert-JavaIntConstant -Text $library -Name "TOKEN_TTL_SECONDS" -Expected 259200 `
    -Label "reborn.force-threads.shadow.source-constant.ttl-72h"
Assert-JavaIntConstant -Text $library -Name "TOKEN_LIFETIME_SECONDS" -Expected 259200 `
    -Label "reborn.force-threads.shadow.source-constant.ttl-runtime-alias"
Assert-JavaIntConstant -Text $library -Name "MAX_DEPTH" -Expected 3 `
    -Label "reborn.force-threads.shadow.source-constant.depth"
Assert-JavaIntConstant -Text $library -Name "MAX_ACTIVE_TOKENS" -Expected 8 `
    -Label "reborn.force-threads.shadow.source-constant.tokens"
Assert-JavaIntConstant -Text $library -Name "MAX_OUTBOX_RECORDS" -Expected 8 `
    -Label "reborn.force-threads.shadow.source-constant.outbox"
Assert-JavaIntConstant -Text $library -Name "MAX_LEDGER_RECORDS" -Expected 32 `
    -Label "reborn.force-threads.shadow.source-constant.ledger"
Assert-JavaIntConstant -Text $library -Name "MAX_DEDUPE_IDS" -Expected 64 `
    -Label "reborn.force-threads.shadow.source-constant.dedupe"
Assert-JavaIntConstant -Text $library -Name "MAX_MAILBOX_RECORDS" -Expected 16 `
    -Label "reborn.force-threads.shadow.source-constant.mailbox"
Assert-Contract -Condition $library.Contains("MAX_CAMP_VISITORS = MAX_MAILBOX_RECORDS;") `
    -Name "reborn.force-threads.shadow.source-constant.camp-visitors"
Assert-JavaIntConstant -Text $library -Name "MAX_PERSISTENT_BYTES" -Expected 16384 `
    -Label "reborn.force-threads.shadow.source-constant.persistent-bytes"

$sourcePersistenceLeavesPresent = $library.Contains('PERSISTENT_ROOT = "reborn.forceThreads"')
foreach ($requiredLeaf in $expectedLeaves)
{
    if (-not $library.Contains('".' + $requiredLeaf + '"'))
    {
        $sourcePersistenceLeavesPresent = $false
    }
}
Assert-Contract -Condition $sourcePersistenceLeavesPresent `
    -Name "reborn.force-threads.shadow.source.persistence-root-and-leaves"

$advancedCampTemplates = @($contract.verticalSlice.advancedCampDeedTemplates | ForEach-Object { [string]$_ })
$advancedTemplateBody = Get-JavaMethodBody -Text $library -MethodName "isAdvancedCampDeedTemplate"
foreach ($advancedCampTemplate in $advancedCampTemplates)
{
    Assert-Contract -Condition $library.Contains('"' + $advancedCampTemplate + '"') `
        -Name "reborn.force-threads.shadow.advanced-template.$([IO.Path]::GetFileName($advancedCampTemplate))"
}
$advancedTemplateLiterals = @([regex]::Matches(
    $library,
    '"(?<value>object/tangible/deed/camp_deed/[^"\r\n]+)"') | ForEach-Object {
    [string]$_.Groups["value"].Value
} | Select-Object -Unique)
Assert-Contract -Condition (
    $advancedCampTemplates.Count -eq 6 -and
    ($advancedTemplateLiterals -join ",") -ceq ($advancedCampTemplates -join ",") -and
    $advancedTemplateBody.Length -gt 0 -and
    -not $advancedTemplateBody.Contains("startsWith(") -and
    -not $advancedTemplateBody.Contains("contains(") -and
    -not $advancedTemplateBody.Contains("matches(")) `
    -Name "reborn.force-threads.shadow.advanced-template.exact-allowlist"

$outcomeAllowlistBody = Get-JavaMethodBody -Text $library -MethodName "isAllowedOutcome"
foreach ($outcomeQuest in $expectedAllowlist)
{
    Assert-Contract -Condition $library.Contains('"' + $outcomeQuest + '"') `
        -Name "reborn.force-threads.shadow.outcome.$($outcomeQuest.Replace('/', '.'))"
}
$outcomeQuestLiterals = @([regex]::Matches($library, '"(?<value>quest/[^"\r\n]+)"') | ForEach-Object {
    [string]$_.Groups["value"].Value
} | Select-Object -Unique)
Assert-Contract -Condition (
    ($outcomeQuestLiterals -join ",") -ceq ($expectedAllowlist -join ",") -and
    $outcomeAllowlistBody.Length -gt 0 -and
    -not $outcomeAllowlistBody.Contains("startsWith(") -and
    -not $outcomeAllowlistBody.Contains("contains(") -and
    -not $outcomeAllowlistBody.Contains("matches(")) `
    -Name "reborn.force-threads.shadow.outcome.exact-allowlist"

$outboxWriteIndex = $outcomeBody.IndexOf("writeArray(player, VAR_OUTBOX, outbox)", [StringComparison]::Ordinal)
$outboxReadbackIndex = $outcomeBody.IndexOf(
    "containsEvent(getArray(player, VAR_OUTBOX), eventId)",
    [StringComparison]::Ordinal)
$deliveryPublishIndex = $outcomeBody.IndexOf("publishDelivery(event);", [StringComparison]::Ordinal)
$outboxTokenCollisionIndex = $outcomeBody.IndexOf("containsTokenReference(outbox, fields[1])", [StringComparison]::Ordinal)
$tokenConsumptionWriteIndex = $outcomeBody.LastIndexOf(
    "writeArray(player, VAR_TOKENS, removeTokenById(tokens, fields[1]))",
    [StringComparison]::Ordinal)
$tokenConsumptionReadbackIndex = $outcomeBody.IndexOf(
    "containsTokenId(getArray(player, VAR_TOKENS), fields[1])",
    [StringComparison]::Ordinal)
Assert-Contract -Condition (
    [bool]$contract.persistenceContract.exactlyOnceCausalTokenConsumption -and
    [bool]$contract.persistenceContract.outboxTokenCollisionDetection -and
    [bool]$contract.persistenceContract.tokenConsumptionReadbackBeforeFirstPublish -and
    $outboxTokenCollisionIndex -ge 0 -and
    $outboxTokenCollisionIndex -lt $outboxWriteIndex -and
    $outboxWriteIndex -ge 0 -and
    $outboxReadbackIndex -gt $outboxWriteIndex -and
    $tokenConsumptionWriteIndex -gt $outboxReadbackIndex -and
    $tokenConsumptionReadbackIndex -gt $tokenConsumptionWriteIndex -and
    $deliveryPublishIndex -gt $tokenConsumptionReadbackIndex) `
    -Name "reborn.force-threads.shadow.cwd.outbox-write-readback-before-publish"

$acceptDeliveryBody = Get-JavaMethodBody -Text $library -MethodName "acceptDelivery"
$dedupeAdmissionIndex = $acceptDeliveryBody.IndexOf("if (!contains(dedupe, eventId))", [StringComparison]::Ordinal)
$ledgerLoadIndex = $acceptDeliveryBody.IndexOf("String[] ledger = getArray(origin, VAR_LEDGER)", [StringComparison]::Ordinal)
$ledgerPartialCommitCheckIndex = $acceptDeliveryBody.IndexOf("contains(ledger, ledgerRecord)", [StringComparison]::Ordinal)
$ledgerAppendIndex = $acceptDeliveryBody.IndexOf("appendRolling(ledger, ledgerRecord, MAX_LEDGER_RECORDS)", [StringComparison]::Ordinal)
$ledgerWriteIndex = $acceptDeliveryBody.IndexOf("writeArray(origin, VAR_LEDGER, ledger)", [StringComparison]::Ordinal)
$dedupeWriteIndex = $acceptDeliveryBody.IndexOf("writeArray(origin, VAR_DEDUPE, dedupe)", [StringComparison]::Ordinal)
$ledgerReadbackIndex = $acceptDeliveryBody.LastIndexOf("getArray(origin, VAR_LEDGER)", [StringComparison]::Ordinal)
$dedupeReadbackIndex = $acceptDeliveryBody.LastIndexOf("getArray(origin, VAR_DEDUPE)", [StringComparison]::Ordinal)
$ackPublishIndex = $acceptDeliveryBody.IndexOf(
    "replaceClusterWideData(CWD_MANAGER, ackKey(",
    [StringComparison]::Ordinal)
Assert-Contract -Condition (
    [bool]$contract.clusterMailboxContract.partialCommitLedgerDeduplication -and
    $dedupeAdmissionIndex -ge 0 -and
    $ledgerLoadIndex -gt $dedupeAdmissionIndex -and
    $ledgerPartialCommitCheckIndex -gt $ledgerLoadIndex -and
    $ledgerAppendIndex -gt $ledgerPartialCommitCheckIndex -and
    $ledgerWriteIndex -gt $dedupeAdmissionIndex -and
    $dedupeWriteIndex -ge $ledgerWriteIndex -and
    $ledgerReadbackIndex -gt $ledgerWriteIndex -and
    $dedupeReadbackIndex -gt $dedupeWriteIndex -and
    $ackPublishIndex -gt $ledgerReadbackIndex -and
    $ackPublishIndex -gt $dedupeReadbackIndex) `
    -Name "reborn.force-threads.shadow.cwd.ledger-dedupe-readback-before-ack"

$acceptAckBody = Get-JavaMethodBody -Text $library -MethodName "acceptAck"
$ackIdentityIndex = $acceptAckBody.IndexOf("name.equals(ackKey(", [StringComparison]::Ordinal)
$ackAlreadyAbsentIndex = $acceptAckBody.IndexOf("if (remaining.length == outbox.length)", [StringComparison]::Ordinal)
$outboxRemovalWriteIndex = $acceptAckBody.IndexOf("writeArray(carrier, VAR_OUTBOX, remaining)", [StringComparison]::Ordinal)
$firstAckRemovalIndex = $acceptAckBody.IndexOf("removeClusterWideData(CWD_MANAGER, name, lockKey)", [StringComparison]::Ordinal)
$lastAckRemovalIndex = $acceptAckBody.LastIndexOf("removeClusterWideData(CWD_MANAGER, name, lockKey)", [StringComparison]::Ordinal)
Assert-Contract -Condition (
    [bool]$contract.clusterMailboxContract.ackCleanupWhenOutboxAlreadyAbsent -and
    $ackIdentityIndex -ge 0 -and
    $ackAlreadyAbsentIndex -gt $ackIdentityIndex -and
    $firstAckRemovalIndex -gt $ackAlreadyAbsentIndex -and
    $firstAckRemovalIndex -lt $outboxRemovalWriteIndex -and
    $outboxRemovalWriteIndex -gt $ackIdentityIndex -and
    $lastAckRemovalIndex -gt $outboxRemovalWriteIndex -and
    $lastAckRemovalIndex -gt $firstAckRemovalIndex) `
    -Name "reborn.force-threads.shadow.cwd.ack-before-outbox-removal-and-cleanup"

$reconcileBody = Get-JavaMethodBody -Text $library -MethodName "reconcile"
$reconcileRepublishIndex = $reconcileBody.IndexOf("publishDelivery(event);", [StringComparison]::Ordinal)
$reconcileQueryIndex = $reconcileBody.IndexOf("getClusterWideData(CWD_MANAGER", [StringComparison]::Ordinal)
$reconcileTokenRemoveIndex = $reconcileBody.IndexOf("removeTokenById(tokens, fields[8])", [StringComparison]::Ordinal)
$reconcileTokenWriteIndex = $reconcileBody.IndexOf("writeArray(player, VAR_TOKENS, tokens)", [StringComparison]::Ordinal)
$reconcileTokenReadbackIndex = $reconcileBody.IndexOf(
    "containsTokenId(getArray(player, VAR_TOKENS), fields[8])",
    [StringComparison]::Ordinal)
$deliveryKeyBody = Get-JavaMethodBody -Text $library -MethodName "deliveryKey"
Assert-Contract -Condition (
    [bool]$contract.clusterMailboxContract.implemented -and
    [bool]$contract.persistenceContract.atLeastOnceTransportExactlyOnceCredit -and
    [bool]$contract.clusterMailboxContract.centralServerRestartLimitationDocumented -and
    ([string]$contract.clusterMailboxContract.centralServerRestartLimitation).Length -gt 80 -and
    $library.Contains('CWD_MANAGER = "reborn_force_threads"') -and
    $library.Contains('DELIVERY_PREFIX = "delivery_"') -and
    $library.Contains('ACK_PREFIX = "ack_"') -and
    $reconcileRepublishIndex -ge 0 -and
    [bool]$contract.persistenceContract.reconcileTokenConsumptionBeforeRepublish -and
    $reconcileTokenRemoveIndex -ge 0 -and
    $reconcileTokenWriteIndex -gt $reconcileTokenRemoveIndex -and
    $reconcileTokenReadbackIndex -gt $reconcileTokenWriteIndex -and
    $reconcileRepublishIndex -gt $reconcileTokenReadbackIndex -and
    $reconcileQueryIndex -gt $reconcileRepublishIndex -and
    $deliveryKeyBody.Contains("DELIVERY_PREFIX + origin") -and
    $deliveryKeyBody.Contains("getStringCrc(eventId)")) `
    -Name "reborn.force-threads.shadow.cwd.per-event-republish-contract"

$clusterHandlerBody = Get-JavaMethodBody -Text $playerReceiver -MethodName "OnClusterWideDataResponse"
$clusterResponseBody = Get-JavaMethodBody -Text $library -MethodName "handleClusterResponse"
$ownedReleaseBody = Get-JavaMethodBody -Text $library -MethodName "releaseOwnedClusterResponse"
$publishDeliveryBody = Get-JavaMethodBody -Text $library -MethodName "publishDelivery"
$clusterOwnershipIndex = $clusterResponseBody.IndexOf("!CWD_MANAGER.equals(manager)", [StringComparison]::Ordinal)
$clusterReleaseIndex = $clusterResponseBody.IndexOf("releaseClusterWideDataLock(manager, lockKey)", [StringComparison]::Ordinal)
Assert-Contract -Condition (
    $clusterHandlerBody.Contains("force_threads.releaseOwnedClusterResponse(self, manager, requestId, lockKey);") -and
    -not $clusterHandlerBody.Contains("releaseClusterWideDataLock(") -and
    $clusterResponseBody.Contains("names.length > MAX_MAILBOX_RECORDS") -and
    $clusterResponseBody.IndexOf("names.length > MAX_MAILBOX_RECORDS", [StringComparison]::Ordinal) -lt
        $clusterResponseBody.IndexOf("for (int i = 0; i < names.length; ++i)", [StringComparison]::Ordinal) -and
    $clusterOwnershipIndex -ge 0 -and
    $clusterReleaseIndex -gt $clusterOwnershipIndex -and
    $clusterResponseBody.Contains("lockKey > 0") -and
    $ownedReleaseBody.Contains("!CWD_MANAGER.equals(manager)") -and
    $ownedReleaseBody.Contains("utils.getStringScriptVar(player, requestPath)") -and
    $ownedReleaseBody.Contains("REQUEST_DELIVERY.equals(requestKind)") -and
    $ownedReleaseBody.Contains("REQUEST_ACK.equals(requestKind)") -and
    $ownedReleaseBody.Contains("lockKey > 0") -and
    $acceptDeliveryBody.Contains("ack, false, 0)") -and
    $publishDeliveryBody.Contains("delivery, false, 0)") -and
    -not $featureSources.Contains("false, -1") -and
    -not $featureSources.Contains("lockKey >= 0")) `
    -Name "reborn.force-threads.shadow.cwd.owned-positive-lock-release-only"

$outcomeQuarantineIndex = $outcomeBody.IndexOf("hasObjVar(player, VAR_QUARANTINE)", [StringComparison]::Ordinal)
$reconcileQuarantineIndex = $reconcileBody.IndexOf("hasObjVar(player, VAR_QUARANTINE)", [StringComparison]::Ordinal)
$deliveryQuarantineIndex = $acceptDeliveryBody.IndexOf("hasObjVar(origin, VAR_QUARANTINE)", [StringComparison]::Ordinal)
Assert-Contract -Condition (
    $outcomeQuarantineIndex -ge 0 -and $outcomeQuarantineIndex -lt $outboxWriteIndex -and
    $reconcileQuarantineIndex -ge 0 -and $reconcileQuarantineIndex -lt $reconcileRepublishIndex -and
    $deliveryQuarantineIndex -ge 0 -and $deliveryQuarantineIndex -lt $ledgerWriteIndex) `
    -Name "reborn.force-threads.shadow.quarantine.fail-closed-credit"

$codecCoverage = @($contract.persistenceContract.implementedStrictCodecCoverage | ForEach-Object { [string]$_ })
$expectedCodecCoverage = @("root-schema", "active-token", "carrier-outbox", "cluster-delivery")
$addTokenBody = Get-JavaMethodBody -Text $library -MethodName "addToken"
$validTokenCollectionBody = Get-JavaMethodBody -Text $library -MethodName "areValidTokens"
$validTokenBody = Get-JavaMethodBody -Text $library -MethodName "isValidTokenRecord"
$validOutboxCollectionBody = Get-JavaMethodBody -Text $library -MethodName "areValidOutboxRecords"
$validOutboxBody = Get-JavaMethodBody -Text $library -MethodName "isValidOutboxRecord"
$ensureStateBody = Get-JavaMethodBody -Text $library -MethodName "ensurePlayerState"
$observeTokenValidationIndex = $outcomeBody.IndexOf("if (!areValidTokens(storedTokens))", [StringComparison]::Ordinal)
$observeTokenPruneIndex = $outcomeBody.IndexOf("pruneTokens(storedTokens)", [StringComparison]::Ordinal)
$addTokenValidationIndex = $addTokenBody.IndexOf("if (!areValidTokens(storedTokens))", [StringComparison]::Ordinal)
$addTokenPruneIndex = $addTokenBody.IndexOf("pruneTokens(storedTokens)", [StringComparison]::Ordinal)
$outboxValidationIndex = $reconcileBody.IndexOf("if (!areValidOutboxRecords(outbox, player))", [StringComparison]::Ordinal)
$outcomeOutboxValidationIndex = $outcomeBody.IndexOf("if (!areValidOutboxRecords(outbox, player))", [StringComparison]::Ordinal)
Assert-Contract -Condition (
    ($codecCoverage -join ",") -ceq ($expectedCodecCoverage -join ",") -and
    $ensureStateBody.Contains("getIntObjVar(player, VAR_SCHEMA) != SCHEMA_VERSION") -and
    $ensureStateBody.Contains('quarantine(player, "player-schema")') -and
    $validTokenBody.Contains("fields.length != 11") -and
    $validTokenBody.Contains('!fields[0].equals("1")') -and
    $validTokenBody.Contains('!fields[10].equals("PROVENANCE>SHELTER")') -and
    $validTokenCollectionBody.Contains("tokens.length > MAX_ACTIVE_TOKENS") -and
    $validTokenCollectionBody.IndexOf("tokens.length > MAX_ACTIVE_TOKENS", [StringComparison]::Ordinal) -lt
        $validTokenCollectionBody.IndexOf("for (String token : tokens)", [StringComparison]::Ordinal) -and
    $observeTokenValidationIndex -ge 0 -and
    $observeTokenPruneIndex -gt $observeTokenValidationIndex -and
    $addTokenValidationIndex -ge 0 -and
    $addTokenPruneIndex -gt $addTokenValidationIndex -and
    $validOutboxBody.Contains("fields.length != 12") -and
    $validOutboxBody.Contains('!fields[0].equals("1")') -and
    $validOutboxBody.Contains('!fields[11].equals("PROVENANCE>SHELTER>OUTCOME")') -and
    $validOutboxCollectionBody.Contains("records.length > MAX_OUTBOX_RECORDS") -and
    $validOutboxCollectionBody.IndexOf("records.length > MAX_OUTBOX_RECORDS", [StringComparison]::Ordinal) -lt
        $validOutboxCollectionBody.IndexOf("for (String record : records)", [StringComparison]::Ordinal) -and
    $validOutboxCollectionBody.Contains("carrier != utils.stringToObjId(fields[6])") -and
    $validOutboxCollectionBody.Contains("getPlayerStationId(carrier) != utils.stringToInt(fields[7])") -and
    $outboxValidationIndex -ge 0 -and
    $outboxValidationIndex -lt $reconcileRepublishIndex -and
    $outcomeOutboxValidationIndex -ge 0 -and
    $outcomeOutboxValidationIndex -lt $outboxWriteIndex -and
    $acceptDeliveryBody.Contains("!isValidOutboxRecord(event)")) `
    -Name "reborn.force-threads.shadow.codec.malformed-future-token-outbox-delivery-quarantine"

$forbiddenSymbols = @($contract.safetyBoundary.forbiddenSymbols | ForEach-Object { [string]$_ })
$forbiddenCallNameFragments = @($contract.safetyBoundary.forbiddenCallNameFragments | ForEach-Object { [string]$_ })
$playerFacingSymbols = @($contract.safetyBoundary.playerFacingMessageSymbols | ForEach-Object { [string]$_ })
Test-ContainsNoTerms -Text $shadowSafetyText -Terms $forbiddenSymbols `
    -Label "reborn.force-threads.shadow.no-forbidden-call"
Test-ContainsNoTerms -Text $shadowSafetyText -Terms $playerFacingSymbols `
    -Label "reborn.force-threads.shadow.no-player-message"
foreach ($callNameFragmentObject in $forbiddenCallNameFragments)
{
    $callNameFragment = [string]$callNameFragmentObject
    $forbiddenCallPattern = "(?i)\b[A-Za-z0-9_]*" + [regex]::Escape($callNameFragment) +
        "[A-Za-z0-9_]*[ \t]*\("
    Assert-Contract -Condition (-not [regex]::IsMatch($shadowSafetyText, $forbiddenCallPattern)) `
        -Name "reborn.force-threads.shadow.no-$callNameFragment-call"
}

$srcStatus = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all -- src)
$exeStatus = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all -- exe)
Assert-Contract -Condition ($srcStatus.Count -eq 0 -and $exeStatus.Count -eq 0) `
    -Name "reborn.force-threads.shadow.no-src-or-exe-worktree-changes"

$dsrcStatus = @(& git -C (Join-Path $repositoryRoot "dsrc") status --porcelain=v1 --untracked-files=all)
$allowedDsrcPaths = @($contract.changeBoundary.allowedDsrcFiles | ForEach-Object {
    ([string]$_).Replace("\", "/")
})
$progressionDsrcPaths = @($progressionContract.sourceIncrement.PSObject.Properties | ForEach-Object {
    $relativePath = [string]$_.Value
    if ($relativePath.StartsWith("dsrc/", [StringComparison]::Ordinal))
    {
        $relativePath.Substring(5).Replace("\", "/")
    }
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$allowedDsrcPaths = @($allowedDsrcPaths + $progressionDsrcPaths | Sort-Object -Unique)
$unexpectedDsrcChanges = [System.Collections.Generic.List[string]]::new()
foreach ($statusEntryObject in $dsrcStatus)
{
    $statusEntry = [string]$statusEntryObject
    if ($statusEntry.Length -lt 4)
    {
        $unexpectedDsrcChanges.Add($statusEntry)
        continue
    }
    $changedPath = $statusEntry.Substring(3).Replace("\", "/")
    if ($changedPath.Contains(" -> "))
    {
        $changedPath = $changedPath.Substring($changedPath.LastIndexOf(" -> ") + 4)
    }
    if ($allowedDsrcPaths -notcontains $changedPath)
    {
        $unexpectedDsrcChanges.Add($changedPath)
    }
}
Assert-Contract -Condition ($unexpectedDsrcChanges.Count -eq 0) `
    -Name "reborn.force-threads.shadow.dsrc-change-boundary"

$unregisteredForceChanges = @($dsrcStatus | ForEach-Object {
    $changedPath = ([string]$_).Substring(3).Replace("\", "/")
    $normalized = $changedPath.ToLowerInvariant()
    if (($normalized.Contains("/jedi/") -or $normalized.Contains("/fs_quest/") -or $normalized.Contains("/force_sensitive/")) -and
        $progressionDsrcPaths -notcontains $changedPath)
    {
        $changedPath
    }
})
Assert-Contract -Condition ($unregisteredForceChanges.Count -eq 0) `
    -Name "reborn.force-threads.shadow.no-unregistered-jedi-or-fs-dsrc-changes"

# Source-specific hook, causal validation, and mailbox ordering checks are kept
# below this marker so their exact assertions remain easy to review with the
# implementation they admit.

if ($failures.Count -gt 0)
{
    throw "Reborn Force Threads shadow acceptance failed: $($failures -join ', ')"
}

Write-Host "Reborn Force Threads default-off shadow acceptance passed; compile and live verification remain pending."
