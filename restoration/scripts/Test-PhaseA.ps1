[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [ValidateSet("Baseline", "Ready")]
    [string]$Expectation = "Baseline"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$superprojectRoot = Split-Path -Parent $restorationRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force

$manifest = Get-RestorationManifest -RestorationRoot $restorationRoot
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.phaseA)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = Resolve-NormalizedPath -Path $SourceRoot

$canonicalPinArgs = @{
    RepositoryRoot = $superprojectRoot
    Manifest = $manifest
}
$sourcePinArgs = @{
    RepositoryRoot = $source
    Manifest = $manifest
    RequireInitialized = $true
}
$canonicalPins = Assert-RestorationPins @canonicalPinArgs
$sourcePins = Assert-RestorationPins @sourcePinArgs

Write-Host "Locked gitlinks:"
foreach ($pin in @($sourcePins))
{
    Write-Host "  [PASS] $($pin.Name) $($pin.Gitlink)"
}

$skillTablePath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$commandTablePath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$schematicGroupTablePath = Join-Path $source ([string]$contract.sourceFiles.schematicGroupTable)
$skills = @(Import-SwgTab -Path $skillTablePath)
$commands = @(Import-SwgTab -Path $commandTablePath)
$schematicGroups = @(Import-SwgTab -Path $schematicGroupTablePath)

$script:checks = @()

function Add-PhaseCheck
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $script:checks += [pscustomobject]@{
        Id = $Id
        Passed = $Passed
        Detail = $Detail
    }
}

function Get-JavaMethodWindow
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$SignaturePattern
    )

    $pattern = "(?s)$SignaturePattern.*?(?=\r?\n\s*(?:public|protected|private)\s+(?:static\s+)?|\z)"
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success)
    {
        return ""
    }

    return $match.Value
}

$pointCap = [int]$contract.skillPointCap
foreach ($scenario in @($contract.pointScenarios))
{
    $usedPoints = 0
    $missingSkills = @()
    $invalidSkills = @()

    foreach ($skillNameValue in @($scenario.heldSkills))
    {
        $skillName = [string]$skillNameValue
        $matches = @($skills | Where-Object { $_.NAME -ceq $skillName })
        if ($matches.Count -ne 1)
        {
            $missingSkills += $skillName
            continue
        }

        $points = 0
        if ((-not [int]::TryParse([string]$matches[0].POINTS_REQUIRED, [ref]$points)) -or ($points -lt 0))
        {
            $invalidSkills += $skillName
            continue
        }

        $usedPoints += $points
    }

    $availablePoints = $pointCap - $usedPoints
    $expectedPoints = [int]$scenario.expectedAvailable
    $scenarioPassed = (
        ($missingSkills.Count -eq 0) -and
        ($invalidSkills.Count -eq 0) -and
        ($availablePoints -eq $expectedPoints) -and
        ($availablePoints -ge 0)
    )
    $detail = "available=$availablePoints expected=$expectedPoints used=$usedPoints"
    if ($missingSkills.Count -gt 0)
    {
        $detail += " missing=$($missingSkills -join ',')"
    }
    if ($invalidSkills.Count -gt 0)
    {
        $detail += " invalid=$($invalidSkills -join ',')"
    }

    Add-PhaseCheck -Id "phaseA.points.$($scenario.name)" -Passed $scenarioPassed -Detail $detail
}

$trainingSkillName = [string]$contract.trainingSkill.name
$trainingRows = @($skills | Where-Object { $_.NAME -ceq $trainingSkillName })
$trainingRowPassed = (
    ($trainingRows.Count -eq 1) -and
    ([int]$trainingRows[0].POINTS_REQUIRED -eq [int]$contract.trainingSkill.pointsRequired) -and
    ([int]$trainingRows[0].MONEY_REQUIRED -eq [int]$contract.trainingSkill.moneyRequired)
)
Add-PhaseCheck -Id "phaseA.training.table-costs" -Passed $trainingRowPassed -Detail "expected $trainingSkillName points=$($contract.trainingSkill.pointsRequired) money=$($contract.trainingSkill.moneyRequired)"

$skillScriptPath = Join-Path $source ([string]$contract.sourceFiles.skillScript)
$teacherScriptPath = Join-Path $source ([string]$contract.sourceFiles.teacherScript)
$runtimeProbePath = Join-Path $source ([string]$contract.sourceFiles.runtimeProbe)
$commandCppPath = Join-Path $source ([string]$contract.sourceFiles.commandCpp)
$playerObjectCppPath = Join-Path $source ([string]$contract.sourceFiles.playerObjectCpp)
$skillScript = Get-Content -LiteralPath $skillScriptPath -Raw
$teacherScript = Get-Content -LiteralPath $teacherScriptPath -Raw
$runtimeProbe = if (Test-Path -LiteralPath $runtimeProbePath -PathType Leaf) { Get-Content -LiteralPath $runtimeProbePath -Raw } else { "" }
$commandCpp = Get-Content -LiteralPath $commandCppPath -Raw
$playerObjectCpp = Get-Content -LiteralPath $playerObjectCppPath -Raw

$teachableWindow = Get-JavaMethodWindow -Source $skillScript -SignaturePattern "public\s+static\s+String\[\]\s+getTeachableSkills\s*\("
$trainerExclusionsPresent = $true
foreach ($excludedValue in @($contract.trainerPolicy.excludedPrefixes))
{
    $pattern = 'startsWith\s*\(\s*"' + [regex]::Escape([string]$excludedValue) + '"\s*\)'
    if ($teachableWindow -notmatch $pattern)
    {
        $trainerExclusionsPresent = $false
        break
    }
}
foreach ($excludedValue in @($contract.trainerPolicy.excludedExact))
{
    $pattern = 'equals\s*\(\s*"' + [regex]::Escape([string]$excludedValue) + '"\s*\)'
    if ($teachableWindow -notmatch $pattern)
    {
        $trainerExclusionsPresent = $false
        break
    }
}
$teachableImplemented = (
    ($teachableWindow.Length -gt 0) -and
    ($teachableWindow -match "\bdeltaTeacherSkills\s*\(") -and
    ($teachableWindow -match "\bgetSkillPrerequisiteSkills\s*\(") -and
    ($teachableWindow -match "\butils\.isSubset\s*\(") -and
    ($teachableWindow -match [regex]::Escape("newbie.hasSkill")) -and
    $trainerExclusionsPresent
)
Add-PhaseCheck -Id "phaseA.training.teachable-list" -Passed $teachableImplemented -Detail "trainer-minus-player skills must be filtered by prerequisites and protected training families"

$statusWindow = Get-JavaMethodWindow -Source $teacherScript -SignaturePattern "public\s+boolean\s+checkSkillStatus\s*\("
$conversationReachable = (
    ($statusWindow -match [regex]::Escape("getAvailableSkillPoints")) -and
    ($statusWindow -match "(?s)getAvailableSkillPoints\s*\(.*?return\s+true\s*;")
)
Add-PhaseCheck -Id "phaseA.training.conversation-reachable" -Passed $conversationReachable -Detail "ordinary qualified trainers must reach a true return with derived points available"

$qualifiedWindow = Get-JavaMethodWindow -Source $skillScript -SignaturePattern "public\s+static\s+String\[\]\s+getQualifiedTeachableSkills\s*\("
$speciesPolicyReady = (
    ($qualifiedWindow -match "species\s*!=\s*null\s*&&\s*!species\.isEmpty\s*\(\s*\)") -and
    ($qualifiedWindow -match [regex]::Escape("getPlayerSpeciesName")) -and
    ($qualifiedWindow -match "!species\.getBoolean\s*\(") -and
    ($qualifiedWindow -notmatch "assert\s+d\s*!=\s*null")
)
Add-PhaseCheck -Id "phaseA.training.species-policy" -Passed $speciesPolicyReady -Detail "species prerequisites must evaluate the player's species against the species dictionary"

$moneyDerived = (
    ($teacherScript -match [regex]::Escape("MONEY_REQUIRED")) -and
    ($teacherScript -notmatch "\bint\s+cost\s*=\s*1\s*;")
)
Add-PhaseCheck -Id "phaseA.training.money-derived" -Passed $moneyDerived -Detail "trainer money must come from MONEY_REQUIRED, never a literal"

$availableHelper = [string]$contract.pointImplementation.availableHelper
$costHelper = [string]$contract.pointImplementation.costHelper
$pointColumn = [string]$contract.pointImplementation.tableColumn
$purchaseWindow = Get-JavaMethodWindow -Source $skillScript -SignaturePattern "public\s+static\s+boolean\s+purchaseSkill\s*\("
$pointsDerived = (
    ($skillScript -match [regex]::Escape($pointColumn)) -and
    ($skillScript -match [regex]::Escape($availableHelper)) -and
    ($skillScript -match [regex]::Escape($costHelper)) -and
    ($purchaseWindow -match [regex]::Escape($availableHelper)) -and
    ($purchaseWindow -match [regex]::Escape($costHelper)) -and
    ($teacherScript -notmatch "\bint\s+ptsLeft\s*=\s*0\s*;") -and
    ($teacherScript -notmatch "\bint\s+ptsCost\s*=\s*1\s*;")
)
Add-PhaseCheck -Id "phaseA.training.points-derived" -Passed $pointsDerived -Detail "derive 250 minus held POINTS_REQUIRED and enforce it inside purchaseSkill"

$surrenderRows = @($commands | Where-Object { $_.commandName -ieq "surrenderSkill" })
$surrenderCommandReady = (
    ($surrenderRows.Count -eq 1) -and
    ($surrenderRows[0].defaultPriority -ceq "immediate") -and
    ($surrenderRows[0].cppHook -ceq "surrenderSkill") -and
    ($surrenderRows[0].targetType -ceq "none") -and
    ([string]::IsNullOrEmpty([string]$surrenderRows[0].stringId)) -and
    ([int]$surrenderRows[0].visible -eq 1) -and
    ([int]$surrenderRows[0].callOnTarget -eq 0) -and
    ([int]$surrenderRows[0].disabled -eq 0) -and
    ([int]$surrenderRows[0].godLevel -eq 0) -and
    ([int]$surrenderRows[0].addToCombatQueue -eq 0) -and
    ([int]$surrenderRows[0].toolbarOnly -eq 0) -and
    ([int]$surrenderRows[0].fromServerOnly -eq 0)
)
Add-PhaseCheck -Id "phaseA.surrender.command-table" -Passed $surrenderCommandReady -Detail "surrenderSkill must retain the authentic client-visible, immediate, actor-routed command contract"

$protectedPolicyPresent = $true
foreach ($prefixValue in @($contract.surrenderPolicy.protectedPrefixes))
{
    if ($commandCpp.IndexOf(('"' + [string]$prefixValue + '"'), [System.StringComparison]::Ordinal) -lt 0)
    {
        $protectedPolicyPresent = $false
        break
    }
}
foreach ($fragmentValue in @($contract.surrenderPolicy.protectedFragments))
{
    $pattern = 'skillName\.find\s*\(\s*"' + [regex]::Escape([string]$fragmentValue) + '"\s*\)\s*!=\s*std::string::npos'
    if ($commandCpp -notmatch $pattern)
    {
        $protectedPolicyPresent = $false
        break
    }
}
foreach ($exactValue in @($contract.surrenderPolicy.protectedExact))
{
    $pattern = 'skillName\s*==\s*"' + [regex]::Escape([string]$exactValue) + '"'
    if ($commandCpp -notmatch $pattern)
    {
        $protectedPolicyPresent = $false
        break
    }
}
$surrenderHandlerMatch = [regex]::Match($commandCpp, "(?s)static\s+void\s+commandFuncSurrenderSkill\s*\(.*?(?=\r?\n//\s+-{5,})")
$surrenderHandler = if ($surrenderHandlerMatch.Success) { $surrenderHandlerMatch.Value } else { "" }
$ownershipCheckCount = [regex]::Matches($surrenderHandler, "hasSkill\s*\(\s*\*skill\s*\)").Count
$schematicGuardReady = $playerObjectCpp -match "(?s)found\s*==\s*m_draftSchematics\.end\s*\(\s*\).*?return\s+false\s*;"
$surrenderNativeReady = (
    ($commandCpp -match "\bcommandFuncSurrenderSkill\b") -and
    ($commandCpp -match 'addCppFunction\s*\(\s*"surrenderSkill"\s*,\s*commandFuncSurrenderSkill\s*\)') -and
    ($surrenderHandler -match "getCreatureObject\s*\(\s*actor\s*\)") -and
    ($surrenderHandler -notmatch "getCreatureObject\s*\(\s*target\s*\)") -and
    ($surrenderHandler -match "isAuthoritative\s*\(") -and
    ($ownershipCheckCount -ge 2) -and
    ($surrenderHandler -match "dependsUponSkill\s*\(") -and
    ($surrenderHandler -match "revokeSkill\s*\(\s*\*skill\s*\)") -and
    ($commandCpp -match "findProfessionForSkill\s*\(") -and
    ($commandCpp -match "getExperienceLimit\s*\(") -and
    ($commandCpp -match "grantExperiencePoints\s*\(") -and
    $protectedPolicyPresent -and
    $schematicGuardReady
)
Add-PhaseCheck -Id "phaseA.surrender.native-handler" -Passed $surrenderNativeReady -Detail "actor-only native handler must reject protected/dependent skills, verify removal, clamp XP, and retain safe cleanup"

$runtimeSlice = $contract.runtimeVerticalSlice
$runtimeSkillName = [string]$runtimeSlice.skill
$runtimeCommand = [string]$runtimeSlice.command
$runtimeSkillModName = [string]$runtimeSlice.skillMod.name
$runtimeSkillModDelta = [int]$runtimeSlice.skillMod.delta
$runtimeSchematicGroup = [string]$runtimeSlice.schematicGroup
$runtimeSchematic = [string]$runtimeSlice.schematic
$runtimeRows = @($skills | Where-Object { $_.NAME -ceq $runtimeSkillName })
$runtimePrerequisiteRows = @($skills | Where-Object { $_.NAME -ceq [string]$runtimeSlice.prerequisiteSkill })
$runtimeSkillContractReady = $false
if ($runtimeRows.Count -eq 1 -and $runtimePrerequisiteRows.Count -eq 1)
{
    $runtimeCommands = @(([string]$runtimeRows[0].COMMANDS).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $runtimeSkillMods = @(([string]$runtimeRows[0].SKILL_MODS).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $runtimeGrantedGroups = @(([string]$runtimeRows[0].SCHEMATICS_GRANTED).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $runtimeSkillContractReady = (
        ([string]$runtimeRows[0].SKILLS_REQUIRED -ceq [string]$runtimeSlice.prerequisiteSkill) -and
        ([string]$runtimeRows[0].XP_TYPE -ceq [string]$runtimeSlice.xpType) -and
        ([int]$runtimeRows[0].POINTS_REQUIRED -eq [int]$runtimeSlice.skillPointCost) -and
        ([int]$runtimePrerequisiteRows[0].XP_CAP -eq [int]$runtimeSlice.prerequisiteXpCap) -and
        ([int]$runtimeRows[0].XP_CAP -eq [int]$runtimeSlice.trainedXpCap) -and
        ($runtimeCommand -cin $runtimeCommands) -and
        (("$runtimeSkillModName=$runtimeSkillModDelta") -cin $runtimeSkillMods) -and
        ($runtimeSchematicGroup -cin $runtimeGrantedGroups)
    )
}
$runtimeSchematicMappings = @(
    $schematicGroups |
        Where-Object {
            ([string]$_.GroupId -ceq $runtimeSchematicGroup) -and
            ([string]$_.SchematicName -ceq $runtimeSchematic)
        }
)
$runtimeSkillContractReady = $runtimeSkillContractReady -and ($runtimeSchematicMappings.Count -eq 1)
Add-PhaseCheck -Id "phaseA.runtime.crafting-contract" -Passed $runtimeSkillContractReady -Detail "Artisan engineering cost, prerequisite/trained XP caps, command, skill-mod delta, and concrete group-derived schematic must resolve from authoritative tables"

$runtimeProbeReady = (
    ($runtimeProbe -match "class\s+precu_phase_a_runtime\s+extends\s+script\.base_script") -and
    ($runtimeProbe -match "public\s+String\s+executeProbe\s*\(\s*String\s+params\s*\)") -and
    ($runtimeProbe -match ("RUNTIME_STATION_ID\s*=\s*" + [int]$runtimeSlice.stationId + "\s*;")) -and
    ($runtimeProbe -match "getPlayerStationId\s*\(\s*player\s*\)\s*!=\s*RUNTIME_STATION_ID") -and
    ($runtimeProbe -match "skill\.purchaseSkill\s*\(") -and
    ($runtimeProbe -match "getAvailableSkillPoints\s*\(") -and
    ($runtimeProbe -match "getExperiencePoints\s*\(") -and
    ($runtimeProbe -match "getExperienceCap\s*\(") -and
    ($runtimeProbe -match 'getStringCrc\s*\(\s*"surrenderskill"\s*\)') -and
    ($runtimeProbe -match "queueCommand\s*\(") -and
    ($runtimeProbe -match "obj_id\.NULL_ID") -and
    ($runtimeProbe -match "COMMAND_PRIORITY_IMMEDIATE") -and
    ($runtimeProbe -notmatch "\bOnAttach\s*\(") -and
    ($runtimeProbe -notmatch "public\s+(?:int|String)\s+On[A-Z][A-Za-z0-9_]*\s*\(")
)
Add-PhaseCheck -Id "phaseA.runtime.console-probe" -Passed $runtimeProbeReady -Detail "trusted console probe must be fixture-bound, query state, and drive purchase/surrender through production services without an attached-object entry point"

$craftingProbeReady = (
    ($runtimeProbe -match ('CRAFTING_SKILL\s*=\s*"' + [regex]::Escape($runtimeSkillName) + '"')) -and
    ($runtimeProbe -match ('CRAFTING_XP_TYPE\s*=\s*"' + [regex]::Escape([string]$runtimeSlice.xpType) + '"')) -and
    ($runtimeProbe -match ('CRAFTING_COMMAND\s*=\s*"' + [regex]::Escape($runtimeCommand) + '"')) -and
    ($runtimeProbe -match ('CRAFTING_SKILL_MOD\s*=\s*"' + [regex]::Escape($runtimeSkillModName) + '"')) -and
    ($runtimeProbe -match ('CRAFTING_SCHEMATIC_GROUP\s*=\s*"' + [regex]::Escape($runtimeSchematicGroup) + '"')) -and
    ($runtimeProbe -match [regex]::Escape($runtimeSchematic)) -and
    ($runtimeProbe -match "getCashBalance\s*\(\s*player\s*\)") -and
    ($runtimeProbe -match "getBankBalance\s*\(\s*player\s*\)") -and
    ($runtimeProbe -match "hasCommand\s*\(\s*player\s*,\s*CRAFTING_COMMAND\s*\)") -and
    ($runtimeProbe -match "getSkillStatisticModifier\s*\(\s*player\s*,\s*CRAFTING_SKILL_MOD\s*\)") -and
    ($runtimeProbe -match "hasSchematic\s*\(\s*player\s*,\s*CRAFTING_SCHEMATIC\s*\)")
)
Add-PhaseCheck -Id "phaseA.runtime.crafting-observability" -Passed $craftingProbeReady -Detail "fixture-bound status must expose credits plus an Artisan command, skill mod, and concrete draft schematic"

$surrenderVerificationReady = (
    ($runtimeProbe -match 'action\.equalsIgnoreCase\s*\(\s*"verifySurrender"\s*\)') -and
    ($runtimeProbe -match 'action=queueSurrender queued=') -and
    ($runtimeProbe -match 'verification="\s*\+\s*\(queued\s*\?\s*"pending"\s*:\s*"notQueued"\)') -and
    ($runtimeProbe -match 'action=verifySurrender completion=') -and
    ($runtimeProbe -match 'surrendered="\s*\+\s*surrendered') -and
    ($runtimeProbe -match '\(surrendered\s*\?\s*"removed"\s*:\s*"stillOwned"\)')
)
Add-PhaseCheck -Id "phaseA.runtime.surrender-verification" -Passed $surrenderVerificationReady -Detail "queue acceptance must be pending until a later authoritative status proves the skill was removed"

$runtimeSmokePath = Join-Path $restorationRoot ([string]$contract.runtimeSmokeScript)
$runtimeSmoke = if (Test-Path -LiteralPath $runtimeSmokePath -PathType Leaf) { Get-Content -LiteralPath $runtimeSmokePath -Raw } else { "" }
$runtimeSmokeReady = (
    ($runtimeSmoke -match 'ContainerName\s*=\s*"swg-precu"') -and
    ($runtimeSmoke -match '\[switch\]\$ExerciseSurrender') -and
    ($runtimeSmoke -match 'game\s+tatooine\s+runScript') -and
    ($runtimeSmoke -match "printf\s+'%-1024s'") -and
    ($runtimeSmoke -match 'craftingStatus\s+\$PlayerOid') -and
    ($runtimeSmoke -match 'queueSurrender\s+\$PlayerOid\s+\$engineeringSkill') -and
    ($runtimeSmoke -match 'verifySurrender\s+\$PlayerOid\s+\$engineeringSkill') -and
    ($runtimeSmoke -match 'Assert-Field\s+-Result\s+\$queued\s+-Name\s+"verification"\s+-Expected\s+"pending"') -and
    ($runtimeSmoke -match 'Assert-Field\s+-Result\s+\$verified\s+-Name\s+"completion"\s+-Expected\s+"removed"') -and
    ($runtimeSmoke -match 'Assert-Field\s+-Result\s+\$Result\s+-Name\s+"xpType"\s+-Expected\s+\$xpType') -and
    ($runtimeSmoke -match '\$expectedEngineeringSkillCost\s*=\s*\[int\]\$runtimeContract\.skillPointCost') -and
    ($runtimeSmoke -match '\$expectedPreEngineeringXpCap\s*=\s*\[int\]\$runtimeContract\.prerequisiteXpCap') -and
    ($runtimeSmoke -match '\$expectedPostEngineeringXpCap\s*=\s*\[int\]\$runtimeContract\.trainedXpCap') -and
    ($runtimeSmoke -match '\$expectedPointsAfterGrant\s*=\s*\$beforeEngineeringState\.Points\s*-\s*\$beforeEngineeringState\.SkillCost') -and
    ($runtimeSmoke -match '\$afterGrantState\.Points\s+-ne\s+\$expectedPointsAfterGrant') -and
    ($runtimeSmoke -match '\$beforeEngineeringState\.Cap\s+-ne\s+\$expectedPreEngineeringXpCap') -and
    ($runtimeSmoke -match '\$afterGrantState\.Cap\s+-ne\s+\$expectedPostEngineeringXpCap') -and
    ($runtimeSmoke -match '(?s)\$noviceMutationAttempted\s*=\s*\$true.*?Invoke-Probe\s+-Arguments\s+"grant\s+\$PlayerOid\s+\$noviceSkill"') -and
    ($runtimeSmoke -match '(?s)\$engineeringMutationAttempted\s*=\s*\$true.*?Invoke-Probe\s+-Arguments\s+"grant\s+\$PlayerOid\s+\$engineeringSkill"') -and
    ($runtimeSmoke -match 'Get-AuthoritativeSkillOwnership\s+-SkillName\s+\$SkillName') -and
    ($runtimeSmoke -match '(?s)Get-AuthoritativeSkillOwnership\s+-SkillName\s+\$SkillName.*?Invoke-Probe\s+-Arguments\s+"revoke\s+\$PlayerOid\s+\$SkillName"') -and
    ($runtimeSmoke -match '\$noviceMutationAttempted\s+-and\s+-not\s+\$noviceWasOwned') -and
    ($runtimeSmoke -match '(?s)if\s*\(Get-AuthoritativeSkillOwnership\s+-SkillName\s+\$engineeringSkill\).*?throw\s+"Refusing to revoke temporary.*?Revoke-TemporarySkillIfOwned\s+-SkillName\s+\$noviceSkill') -and
    ($runtimeSmoke -match '\$beforeEngineeringState\.HasCommand\s+-or\s+\$beforeEngineeringState\.HasSchematic') -and
    ($runtimeSmoke -match 'Assert-CraftingCanaryStateEquals\s+-Actual\s+\$afterSurrenderState\s+-Expected\s+\$beforeEngineeringState') -and
    ($runtimeSmoke -match 'Assert-CraftingCanaryStateEquals\s+-Actual\s+\$restoredState\s+-Expected\s+\$initialState') -and
    ($runtimeSmoke -match '"HasSkill"[\s\S]+"HasCommand"[\s\S]+"HasSchematic"[\s\S]+"SkillCost"[\s\S]+"Points"[\s\S]+"Xp"[\s\S]+"Cap"[\s\S]+"SkillModValue"[\s\S]+"Cash"[\s\S]+"Bank"') -and
    ($runtimeSmoke -match 'finally\s*\{') -and
    ($runtimeSmoke -match 'Revoke-TemporarySkillIfOwned\s+-SkillName\s+\$engineeringSkill') -and
    ($runtimeSmoke -match 'Revoke-TemporarySkillIfOwned\s+-SkillName\s+\$noviceSkill') -and
    ($runtimeSmoke -match '\$cleanupFailure') -and
    ($runtimeSmoke -notmatch 'Assert-Field[^\r\n]+-Name\s+"connected"')
)
Add-PhaseCheck -Id "phaseA.runtime.live-smoke" -Passed $runtimeSmokeReady -Detail "opt-in smoke must assert the canary point/cap transition, snapshot all exposed canary fields, guard prerequisite cleanup with dependent-skill absence, preserve original novice ownership, and never use connected as readiness"

foreach ($scopeValue in @($contract.commandAudit.scopedSkills))
{
    $scope = [string]$scopeValue
    $scopeRows = @($skills | Where-Object { $_.NAME -ceq $scope })
    if ($scopeRows.Count -ne 1)
    {
        Add-PhaseCheck -Id "phaseA.commands.$scope.skill-row" -Passed $false -Detail "expected exactly one scoped skill row"
        continue
    }

    $grants = @(([string]$scopeRows[0].COMMANDS).Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    foreach ($grant in $grants)
    {
        $nonCommand = $false
        foreach ($prefixValue in @($contract.commandAudit.nonCommandPrefixes))
        {
            if ($grant.StartsWith([string]$prefixValue, [System.StringComparison]::OrdinalIgnoreCase))
            {
                $nonCommand = $true
                break
            }
        }
        if ($nonCommand)
        {
            continue
        }

        $definitions = @($commands | Where-Object { $_.commandName -ieq $grant })
        Add-PhaseCheck -Id "phaseA.commands.$scope.$grant" -Passed ($definitions.Count -eq 1) -Detail "actionable skill grant must resolve to exactly one command_table row; found $($definitions.Count)"
    }
}

Write-Host ""
Write-Host "Phase-A checks:"
foreach ($check in @($script:checks))
{
    $label = if ($check.Passed) { "PASS" } else { "BLOCKED" }
    Write-Host "  [$label] $($check.Id): $($check.Detail)"
}

$failedIds = @(
    $script:checks |
        Where-Object { -not $_.Passed } |
        ForEach-Object { [string]$_.Id } |
        Sort-Object -Unique
)

if ($Expectation -eq "Ready")
{
    if ($failedIds.Count -gt 0)
    {
        throw "Phase A is not ready. Blocking checks: $($failedIds -join ', ')"
    }

    Write-Host ""
    Write-Host "Phase-A ready contract passed."
    exit 0
}

$expectedBlockers = @($contract.baselineBlockers | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$missingBlockers = @($expectedBlockers | Where-Object { $_ -notin $failedIds })
$unexpectedBlockers = @($failedIds | Where-Object { $_ -notin $expectedBlockers })

if (($missingBlockers.Count -gt 0) -or ($unexpectedBlockers.Count -gt 0))
{
    throw "Baseline changed. Missing expected blockers: $($missingBlockers -join ', '). Unexpected blockers: $($unexpectedBlockers -join ', ')."
}

Write-Host ""
Write-Host "Current x64-dx9 baseline matched: $($failedIds.Count) known Phase-A blockers remain."
