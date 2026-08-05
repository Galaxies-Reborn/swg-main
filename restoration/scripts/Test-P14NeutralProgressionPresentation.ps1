[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14NeutralProgressionPresentation)) -Raw | ConvertFrom-Json
$gcwPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/gcw.java"
$instancePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/player_instance.java"
$gcw = Get-Content -LiteralPath $gcwPath -Raw
$instance = Get-Content -LiteralPath $instancePath -Raw

function Get-FunctionSlice([string]$Text, [string]$StartMarker, [string]$EndMarker)
{
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}
$gcwStart = $gcw.IndexOf("public static void gcwSetCredits")
$gcwEnd = $gcw.IndexOf("public static void gcwInvasionCreditForGCW", $gcwStart)
$instanceStart = $instance.IndexOf("public int movePlayerToInstance")
$instanceEnd = $instance.IndexOf("public int cmdShowInstanceInformation", $instanceStart)
if ($gcwStart -lt 0 -or $gcwEnd -le $gcwStart -or $instanceStart -lt 0 -or $instanceEnd -le $instanceStart) { throw "Could not isolate presentation surfaces." }
$surface = $gcw.Substring($gcwStart, $gcwEnd - $gcwStart) + "`n" + $instance.Substring($instanceStart, $instanceEnd - $instanceStart)
foreach ($retired in @("getSkillTemplate(", "getProfessionName(", "@ui_roadmap:", "Players Is:"))
{
    if ($surface.Contains($retired)) { throw "NGE presentation remains: $retired" }
}
foreach ($required in @(
    'String playerProfession = "Publish 14.1 skills";',
    "int playerLevel = 0;",
    "Progression: Publish 14.1 skills, Faction:",
    "gcw_score.setPlayerGcwData(",
    "instance.sendToEnterOne(",
    "instance.sendToEnterTwo("
))
{
    if (-not $surface.Contains($required)) { throw "Required neutral presentation or behavior is missing: $required" }
}
foreach ($counter in @("playerGCW","playerPvpKills","playerKills","playerAssists","playerCraftedItems","playerDestroyedItems"))
{
    if (-not $surface.Contains("$counter = currentData.$counter + $counter;")) { throw "GCW counter accumulation is missing: $counter" }
}

$nativePaths = [ordered]@{
    "PlayerObject.cpp" = Join-Path $root ([string]$contract.sourceFiles.nativePlayerObject)
    "CreatureObject.cpp" = Join-Path $root ([string]$contract.sourceFiles.nativeCreatureObject)
    "GuildObject.cpp" = Join-Path $root ([string]$contract.sourceFiles.nativeGuildObject)
    "CityObject.cpp" = Join-Path $root ([string]$contract.sourceFiles.nativeCityObject)
}
foreach ($nativePath in $nativePaths.Values)
{
    if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf))
    {
        throw "Native progression-presentation source is missing: $nativePath"
    }
}
$nativePlayer = Get-Content -LiteralPath $nativePaths["PlayerObject.cpp"] -Raw
$nativeCreature = Get-Content -LiteralPath $nativePaths["CreatureObject.cpp"] -Raw
$nativeGuild = Get-Content -LiteralPath $nativePaths["GuildObject.cpp"] -Raw
$nativeCity = Get-Content -LiteralPath $nativePaths["CityObject.cpp"] -Raw

$lfg = Get-FunctionSlice $nativeCreature "void CreatureObject::getLfgCharacterData" `
    "GroupMemberParam const CreatureObjectNamespace::GroupHelpers::buildGroupMemberParam"
$groupMember = Get-FunctionSlice $nativeCreature `
    "GroupMemberParam const CreatureObjectNamespace::GroupHelpers::buildGroupMemberParam" `
    "void CreatureObjectNamespace::GroupHelpers::buildGroupMemberParamsFromCreatures"
if ($lfg.Contains("convertSkillTemplateToProfession") -or
    -not $lfg.Contains("lfgCharacterData.profession = LfgCharacterData::Prof_Unknown;") -or
    -not $lfg.Contains("lfgCharacterData.level = isPlayerControlled() ? 0 : getLevel();"))
{
    throw "Native LFG data still publishes a singular NGE player profession or combat level."
}
if ($groupMember.Contains("convertSkillTemplateToProfession") -or
    -not $groupMember.Contains("int const level = memberIsPC ? 0 : creatureObject->getLevel();") -or
    -not $groupMember.Contains("LfgCharacterData::Profession profession = LfgCharacterData::Prof_Unknown;"))
{
    throw "Native group member data still publishes a singular NGE player profession or combat level."
}

$membershipSync = Get-FunctionSlice $nativePlayer `
    "// if the character is a guild member" `
    "// if necessary, force a title check"
if ($membershipSync.Contains("getSkillTemplate()") -or $membershipSync.Contains("owner->getLevel()") -or
    ([regex]::Matches($membershipSync, [regex]::Escape("std::string const professionSkillTemplate;"))).Count -ne 2 -or
    ([regex]::Matches($membershipSync, [regex]::Escape("int const level = 0;"))).Count -ne 2)
{
    throw "Native guild/city login synchronization still republishes NGE progression fields."
}

$guildCreator = Get-FunctionSlice $nativeGuild "void GuildObject::addGuildCreatorMember" `
    "void GuildObject::addGuildSponsorMember"
$guildSponsor = Get-FunctionSlice $nativeGuild "void GuildObject::addGuildSponsorMember" `
    "void GuildObject::removeGuildSponsorMember"
$guildUpdate = Get-FunctionSlice $nativeGuild "void GuildObject::setGuildMemberProfessionInfo" `
    "void GuildObject::addGuildMemberRank"
foreach ($guildAdmission in @($guildCreator, $guildSponsor))
{
    if ($guildAdmission.Contains("getSkillTemplate()") -or $guildAdmission.Contains("getLevel()") -or
        -not $guildAdmission.Contains("std::string const realMemberProfessionSkillTemplate;") -or
        -not $guildAdmission.Contains("int const realMemberLevel = 0;"))
    {
        throw "Native guild admission still derives NGE profession or combat-level data."
    }
}
if (-not $guildUpdate.Contains("std::string const precuMemberProfessionSkillTemplate;") -or
    -not $guildUpdate.Contains("int const precuMemberLevel = 0;") -or
    $guildUpdate.Contains("std::make_pair(memberProfessionSkillTemplate, memberLevel)"))
{
    throw "Native guild member updates can still persist NGE progression data."
}

$cityAdmission = Get-FunctionSlice $nativeCity "void CityObject::setCitizen(int cityId" `
    "void CityObject::setCitizenProfessionInfo"
$cityUpdate = Get-FunctionSlice $nativeCity "void CityObject::setCitizenProfessionInfo" `
    "void CityObject::addCitizenRank"
if (-not $cityAdmission.Contains("std::string(), 0, permissions") -or
    -not $cityAdmission.Contains("updatedInfo.m_citizenProfessionSkillTemplate.clear();") -or
    -not $cityAdmission.Contains("updatedInfo.m_citizenLevel = 0;"))
{
    throw "Native city admission can still preserve NGE progression data."
}
if (-not $cityUpdate.Contains("std::string const precuCitizenProfessionSkillTemplate;") -or
    -not $cityUpdate.Contains("int const precuCitizenLevel = 0;") -or
    $cityUpdate.Contains("std::make_pair(citizenProfessionSkillTemplate, citizenLevel)"))
{
    throw "Native city member updates can still persist NGE progression data."
}

foreach ($entry in $nativePaths.GetEnumerator())
{
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
    if ($actual -ne [string]$contract.buildEvidence.sourceSha256.($entry.Key))
    {
        throw "Native source evidence mismatch: $($entry.Key)"
    }
}
if ($Expectation -eq "Ready")
{
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed") { throw "Runtime evidence is not ready." }
    $srcPin = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "src" })
    if ($srcPin.Count -ne 1 -or
        [string]$srcPin[0].commit -cne [string]$contract.buildEvidence.nativeSourceCommit)
    {
        throw "The native source gitlink does not match the authenticated neutral-presentation source."
    }
    foreach ($entry in @{"gcw.java"=$gcwPath;"player_instance.java"=$instancePath}.GetEnumerator())
    {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash.ToLowerInvariant()
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/159-p14-neutral-progression-presentation.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or $hash -ne $contract.buildEvidence.overlayPatchSha256) { throw "Patch evidence mismatch." }
}
Write-Host "Publish 14.1 neutral progression-presentation contract passed."
