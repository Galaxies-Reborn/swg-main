[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
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

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf(
        $Next,
        $startIndex + $Start.Length,
        [StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

function Read-ExactBytes([IO.BinaryReader]$Reader, [int]$Count)
{
    [byte[]]$bytes = $Reader.ReadBytes($Count)
    if ($bytes.Length -ne $Count)
    {
        throw "Truncated STF: expected $Count bytes, read $($bytes.Length)."
    }
    return $bytes
}

function Read-StringTable([string]$Path)
{
    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    $stream = [IO.MemoryStream]::new($bytes, $false)
    $reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::UTF8, $true)
    try
    {
        $magic = $reader.ReadUInt32()
        $version = $reader.ReadByte()
        $nextId = $reader.ReadUInt32()
        $count = $reader.ReadUInt32()
        $byId = [Collections.Generic.Dictionary[uint32,string]]::new()
        for ([uint32]$i = 0; $i -lt $count; ++$i)
        {
            $id = $reader.ReadUInt32()
            [void]$reader.ReadUInt32()
            $characters = $reader.ReadUInt32()
            $valueBytes = Read-ExactBytes $reader ([int]$characters * 2)
            $byId.Add($id, [Text.Encoding]::Unicode.GetString($valueBytes))
        }
        $byName = [Collections.Generic.Dictionary[string,string]]::new(
            [StringComparer]::Ordinal)
        for ([uint32]$i = 0; $i -lt $count; ++$i)
        {
            $id = $reader.ReadUInt32()
            $nameBytes = Read-ExactBytes $reader ([int]$reader.ReadUInt32())
            $name = [Text.Encoding]::ASCII.GetString($nameBytes)
            $byName.Add($name, $byId[$id])
        }
        if ($stream.Position -ne $stream.Length)
        {
            throw "STF contains trailing bytes."
        }
        return [pscustomobject]@{
            Magic = $magic
            Version = $version
            NextId = $nextId
            Count = $count
            ByName = $byName
        }
    }
    finally
    {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$scriptRoot = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/script"
$elderLibraryPath = Join-Path $scriptRoot "library/elder_skill.java"
$lifecyclePath = Join-Path $scriptRoot "player/skill/elder_skills.java"
$teachingPath = Join-Path $scriptRoot "player/skill/player_teaching.java"
$trainerPath = Join-Path $scriptRoot "npc/skillteacher/skillteacher.java"
$fixturePath = Join-Path $scriptRoot `
    "test/precu_elder_apprenticeship_fixture.java"
$playerTemplatePath = Join-Path $source `
    "dsrc/sku.0/sys.server/compiled/game/object/creature/player/base/base_player.tpf"
$skillsPath = Join-Path $source `
    "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$generatorPath = Join-Path $source `
    "restoration/scripts/New-PrecuElderStringTable.ps1"
$stringTablePath = Join-Path $source "serverdata/string/en/precu_elder.stf"

foreach ($path in @(
    $elderLibraryPath,
    $lifecyclePath,
    $teachingPath,
    $trainerPath,
    $fixturePath,
    $playerTemplatePath,
    $skillsPath,
    $generatorPath,
    $stringTablePath))
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "precu.elder.source.$([IO.Path]::GetFileName($path))"
}

$expected = [ordered]@{
    elder_combat_rifleman = "combat_rifleman_master"
    elder_combat_pistol = "combat_pistol_master"
    elder_combat_carbine = "combat_carbine_master"
    elder_combat_unarmed = "combat_unarmed_master"
    elder_combat_1hsword = "combat_1hsword_master"
    elder_combat_2hsword = "combat_2hsword_master"
    elder_combat_polearm = "combat_polearm_master"
    elder_combat_bountyhunter = "combat_bountyhunter_master"
    elder_combat_commando = "combat_commando_master"
    elder_combat_smuggler = "combat_smuggler_master"
    elder_outdoors_squadleader = "outdoors_squadleader_master"
    elder_science_doctor = "science_doctor_master"
    elder_science_combatmedic = "science_combatmedic_master"
    elder_outdoors_ranger = "outdoors_ranger_master"
    elder_outdoors_creaturehandler = "outdoors_creaturehandler_master"
    elder_outdoors_bio_engineer = "outdoors_bio_engineer_master"
    elder_crafting_architect = "crafting_architect_master"
    elder_crafting_armorsmith = "crafting_armorsmith_master"
    elder_crafting_weaponsmith = "crafting_weaponsmith_master"
    elder_crafting_chef = "crafting_chef_master"
    elder_crafting_tailor = "crafting_tailor_master"
    elder_crafting_droidengineer = "crafting_droidengineer_master"
    elder_crafting_merchant = "crafting_merchant_master"
    elder_crafting_shipwright = "crafting_shipwright_master"
    elder_social_dancer = "social_dancer_master"
    elder_social_musician = "social_musician_master"
    elder_social_imagedesigner = "social_imagedesigner_master"
    elder_social_politician = "social_politician_master"
}

$allRows = @(Import-Csv -LiteralPath $skillsPath -Delimiter "`t")
$elderRows = @($allRows | Where-Object { $_.NAME -like "elder_*" })
Assert-Contract ($elderRows.Count -eq 28) "precu.elder.roster.exact-count"
Assert-Contract ($elderRows.NAME -contains "elder_social_politician") `
    "precu.elder.roster.politician-included"
Assert-Contract (-not ($elderRows.NAME -match `
    "elder_(combat_(brawler|marksman)|outdoors_scout|science_medic|crafting_artisan|social_entertainer)")) `
    "precu.elder.roster.basic-professions-excluded"

foreach ($entry in $expected.GetEnumerator())
{
    $rows = @($elderRows | Where-Object { $_.NAME -ceq $entry.Key })
    $row = if ($rows.Count -eq 1) { $rows[0] } else { $null }
    Assert-Contract ($rows.Count -eq 1) "precu.elder.row.$($entry.Key).unique"
    if ($null -eq $row) { continue }
    Assert-Contract (
        $row.POINTS_REQUIRED -ceq "0" -and
        $row.SKILLS_REQUIRED -ceq $entry.Value -and
        $row.XP_TYPE -ceq "apprenticeship" -and
        $row.XP_COST -ceq "100" -and
        $row.XP_CAP -ceq "1240") `
        "precu.elder.row.$($entry.Key).cost-and-master-gate"
    Assert-Contract (
        $row.IS_HIDDEN -ceq "1" -and $row.SEARCHABLE -ceq "0" -and
        [string]::IsNullOrEmpty($row.SKILL_ABILITY) -and
        [string]::IsNullOrEmpty($row.COMMANDS) -and
        [string]::IsNullOrEmpty($row.SKILL_MODS) -and
        [string]::IsNullOrEmpty($row.SCHEMATICS_GRANTED) -and
        [string]::IsNullOrEmpty($row.SCHEMATICS_REVOKED)) `
        "precu.elder.row.$($entry.Key).neutral-no-bonus"
}

$elderLibrary = Get-Content -LiteralPath $elderLibraryPath -Raw
$lifecycle = Get-Content -LiteralPath $lifecyclePath -Raw
$teaching = Get-Content -LiteralPath $teachingPath -Raw
$trainer = Get-Content -LiteralPath $trainerPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$playerTemplate = Get-Content -LiteralPath $playerTemplatePath -Raw

$trainingAward = Get-FunctionSlice $teaching `
    "public int msgTeachSkillConfirmed(" `
    "public int teach("
$mentoring = Get-FunctionSlice $elderLibrary `
    "public static int awardGroupMentorPresenceExperience(" `
    "private static boolean isEligibleMentoringMember("
$expiry = Get-FunctionSlice $elderLibrary `
    "public static void handleExpiry(" `
    "private static void expireSkill("
$trainOrRenew = Get-FunctionSlice $elderLibrary `
    "public static int trainOrRenew(" `
    "public static int awardPlayerTrainingExperience("
$trainerMenu = Get-FunctionSlice $trainer `
    "public int OnObjectMenuRequest(" `
    "public int OnIncapacitated("

Assert-Contract (
    $trainingAward.IndexOf("skill.purchaseSkill(self, selected_skill)") -ge 0 -and
    $trainingAward.IndexOf("elder_skill.awardPlayerTrainingExperience") -gt
        $trainingAward.IndexOf("skill.purchaseSkill(self, selected_skill)")) `
    "precu.elder.apprenticeship.player-training-after-success"
Assert-Contract (
    $elderLibrary.Contains("PLAYER_TRAINING_APPRENTICESHIP_XP_AWARD = 10") -and
    $elderLibrary.Contains("getPlayerStationId(teacher)") -and
    $elderLibrary.Contains("teacherStationId == studentStationId")) `
    "precu.elder.apprenticeship.player-training-abuse-guard"

Assert-Contract (
    $playerTemplate.Contains('"player.skill.elder_skills"') -and
    $lifecycle.Contains("public int OnAttach(") -and
    $lifecycle.Contains("public int OnInitialize(") -and
    $lifecycle.Contains("public int OnLogin(")) `
    "precu.elder.lifecycle.always-attached-load-login"
Assert-Contract (
    $elderLibrary.Contains("ELDER_DURATION_SECONDS = 30 * 24 * 60 * 60") -and
    $elderLibrary.Contains("int now = getCalendarTime()") -and
    $elderLibrary.Contains("setObjVar(player, getExpiryObjVar(elderSkill), expiresAt)")) `
    "precu.elder.lifecycle.absolute-thirty-day-expiry"
Assert-Contract (
    $expiry.Contains("isCurrentExpiry(player, elderSkill, expectedExpiry)") -and
    $elderLibrary.Contains("getElderExpiry(player, elderSkill) == expectedExpiry") -and
    $elderLibrary.Contains("if (hasSkill(player, elderSkill))") -and
    $elderLibrary.Contains("removeObjVar(player, expiryPath)")) `
    "precu.elder.lifecycle.stale-safe-idempotent-reset"
Assert-Contract (
    $trainOrRenew.Contains("boolean renewing = hasSkill(player, elderSkill)") -and
    $trainOrRenew.Contains("skill.deductXpCostForSkillPurchase") -and
    $trainOrRenew.Contains("now + ELDER_DURATION_SECONDS")) `
    "precu.elder.lifecycle.retraining-renews-from-now"
Assert-Contract (
    $trainOrRenew.Contains("int priorExpiry = renewing ?") -and
    $trainOrRenew.Contains("if (renewing)") -and
    $trainOrRenew.Contains("setObjVar(player, getExpiryObjVar(elderSkill), priorExpiry)") -and
    $trainOrRenew.Contains("grantExperiencePoints(")) `
    "precu.elder.lifecycle.renewal-rollback-preserves-active-box"

Assert-Contract (
    $lifecycle.Contains("handleElderMentoringPulse") -and
    $lifecycle.Contains("PULSE_TOKEN") -and
    $lifecycle.Contains("GROUP_MENTOR_AWARD_COOLDOWN_SECONDS") -and
    $mentoring.Contains("getGroupObject(mentor)") -and
    $mentoring.Contains("getIntObjVar(mentor, OBJVAR_MENTOR_NEXT_AWARD) > now")) `
    "precu.elder.mentoring.periodic-persistent-throttle"
Assert-Contract (
    $mentoring.Contains("mentorLevel > learnerLevel") -and
    $mentoring.Contains("learnerStationId == mentorStationId") -and
    $mentoring.Contains("distance > GROUP_MENTOR_MAX_RANGE") -and
    $mentoring.Contains("learner.isLoaded()") -eq $false -and
    $elderLibrary.Contains("player.isLoaded()") -and
    $elderLibrary.Contains("!isDead(player)") -and
    $elderLibrary.Contains("!isIncapacitated(player)")) `
    "precu.elder.mentoring.lower-level-alive-range-account-guards"
Assert-Contract (
    $elderLibrary.Contains("GROUP_MENTOR_BASE_XP_PLACEHOLDER") -and
    $elderLibrary.Contains("GROUP_MENTOR_LEVELS_PER_SCALE_PLACEHOLDER") -and
    $elderLibrary.Contains("GROUP_MENTOR_LEVEL_GAP_BONUS_PLACEHOLDER = 0")) `
    "precu.elder.mentoring.named-placeholder-rate-scale"

Assert-Contract (
    $trainerMenu.Contains("ELDER_TRAINING_MENU") -and
    $trainerMenu.Contains("SID_TRAIN_ELDER_SKILLS") -and
    $trainerMenu.Contains("handleElderTrainingConfirmation") -and
    $trainerMenu.Contains("pageId != expectedPid") -and
    $trainerMenu.Contains("distance > ELDER_TRAINING_RANGE")) `
    "precu.elder.trainer.radial-and-fail-closed-confirmation"
Assert-Contract (
    $trainer.Contains('"train_elder_skills"') -and
    $trainer.Contains("elder_skill.trainOrRenew(player, elderSkill)")) `
    "precu.elder.trainer.exact-option-and-purchase"
Assert-Contract ($fixture.Contains("validRows == 28")) `
    "precu.elder.fixture.read-only-roster-lifecycle-audit"

$stf = Read-StringTable $stringTablePath
Assert-Contract (
    $stf.Magic -eq 0xabcd -and $stf.Version -eq 1 -and
    $stf.Count -eq 39 -and $stf.NextId -eq 40) `
    "precu.elder.stf.canonical-header"
Assert-Contract (
    $stf.ByName["train_elder_skills"] -ceq "Train elder skills" -and
    $stf.ByName["elder_expired"] -ceq
        "An Elder skill has reached its 30-day reset and was removed." -and
    $stf.ByName["shipwright_n"] -ceq "Shipwright" -and
    $stf.ByName["politician_n"] -ceq "Politician" -and
    $stf.ByName["elder_training_prompt"].Contains("100 apprenticeship XP") -and
    $stf.ByName["elder_renewal_prompt"].Contains("30-day duration")) `
    "precu.elder.stf.required-values"

[byte[]]$teachingBytes = [IO.File]::ReadAllBytes($teachingPath)
$bareLf = 0
for ($i = 0; $i -lt $teachingBytes.Length; ++$i)
{
    if ($teachingBytes[$i] -eq 10 -and
        ($i -eq 0 -or $teachingBytes[$i - 1] -ne 13))
    {
        ++$bareLf
    }
}
Assert-Contract ($bareLf -eq 0) "precu.elder.eol.player-teaching-crlf"

if ($failures.Count -gt 0)
{
    throw "Elder/apprenticeship regression failed: $($failures -join ', ')"
}
Write-Host "Elder/apprenticeship regression passed ($($expected.Count) Elder boxes)."
