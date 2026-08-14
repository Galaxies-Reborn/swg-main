[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $restorationRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14PrecuPlayerHqProfessionAuthority)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-FunctionSlice([string]$Text, [string]$Start, [string]$Next)
{
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return "" }
    $nextIndex = $Text.IndexOf($Next, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($nextIndex -lt 0) { return $Text.Substring($startIndex) }
    return $Text.Substring($startIndex, $nextIndex - $startIndex)
}

$patchPath = Join-Path $repositoryRoot ([string]$contract.buildEvidence.overlayPatch.path)
Assert-Contract (Test-Path -LiteralPath $patchPath -PathType Leaf) "p14.player-hq.overlay.exists"
if (Test-Path -LiteralPath $patchPath -PathType Leaf)
{
    $patch = Get-Item -LiteralPath $patchPath
    $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    Assert-Contract ($patch.Length -eq [long]$contract.buildEvidence.overlayPatch.bytes -and
        $patchHash -ceq [string]$contract.buildEvidence.overlayPatch.sha256) `
        "p14.player-hq.overlay.authenticated"
}

$paths = [ordered]@{
    "hq.objective_override" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_terminal_override.java"
    "hq.objective_power" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_power_regulator.java"
    "hq.objective_security" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_terminal_security.java"
    "hq.objective_uplink" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_terminal_uplink.java"
    "hq.terminal" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/terminal.java"
    "skills.table" = "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
    "hq.library" = "dsrc/sku.0/sys.server/compiled/game/script/library/hq.java"
    "hq.loader" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/loader.java"
    "hq.objective_manager" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/objective_manager.java"
    "hq.deed" = "dsrc/sku.0/sys.server/compiled/game/script/faction_perk/hq/deed.java"
    "hq.template" = "dsrc/sku.0/sys.server/compiled/game/object/building/faction_perk/hq/base/factional_hq_base.tpf"
    "factions.library" = "dsrc/sku.0/sys.server/compiled/game/script/library/factions.java"
    "battlefield.player" = "dsrc/sku.0/sys.server/compiled/game/script/systems/battlefield/player_battlefield.java"
    "mission.terminal" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_terminal.java"
    "mission.base" = "dsrc/sku.0/sys.server/compiled/game/script/systems/missions/base/mission_base.java"
    "static.master" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/static_base/master.java"
    "static.base_master" = "dsrc/sku.0/sys.server/compiled/game/script/systems/gcw/static_base/base_master.java"
}
$texts = @{}
foreach ($name in $paths.Keys)
{
    $path = Join-Path $source $paths[$name]
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.player-hq.source.$name.exists"
    if (Test-Path -LiteralPath $path -PathType Leaf)
    {
        $texts[$name] = Get-Content -LiteralPath $path -Raw
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $expectedHash = [string]$contract.buildEvidence.sourceSha256.PSObject.Properties[$name].Value
        Assert-Contract ($actualHash -ceq $expectedHash) "p14.player-hq.source.$name.authenticated"
    }
}

$override = [string]$texts["hq.objective_override"]
$power = [string]$texts["hq.objective_power"]
$security = [string]$texts["hq.objective_security"]
$uplink = [string]$texts["hq.objective_uplink"]
$terminal = [string]$texts["hq.terminal"]
$changedHqText = $override + "`n" + $power + "`n" + $security + "`n" + $uplink + "`n" + $terminal

Assert-Contract (-not [regex]::IsMatch($changedHqText,
    'class_(?:medic|commando|smuggler|bountyhunter|officer)_phase[0-9]+_novice')) `
    "p14.player-hq.nge-class-phase-gates.absent"
Assert-Contract ($override.Contains('hasSkill(player, "outdoors_bio_engineer_novice")')) `
    "p14.player-hq.override.bio-engineer-novice-admission"
Assert-Contract ($power.Contains('hasSkill(player, "combat_commando_heavyweapon_speed_02")')) `
    "p14.player-hq.power.commando-heavy-support-two-admission"
Assert-Contract ($security.Contains('hasSkill(player, "combat_smuggler_slicing_01")')) `
    "p14.player-hq.security.smuggler-slicing-one-admission"
Assert-Contract ($uplink.Contains('hasSkill(player, "combat_bountyhunter_investigation_02")')) `
    "p14.player-hq.uplink.bounty-hunter-investigation-two-admission"
Assert-Contract ($terminal.Contains('hasSkill(player, "outdoors_squadleader_novice")')) `
    "p14.player-hq.terminal.squad-leader-novice-admission"

$dna = Get-FunctionSlice $override "private void doSequencing" "public int handleSequencing"
$dnaOrder = @(
    'int chainlength = 3;',
    'hasSkill(player, "outdoors_bio_engineer_master")', 'chainlength = 8;',
    'hasSkill(player, "outdoors_bio_engineer_dna_harvesting_04")', 'chainlength = 7;',
    'hasSkill(player, "outdoors_bio_engineer_dna_harvesting_03")', 'chainlength = 6;',
    'hasSkill(player, "outdoors_bio_engineer_dna_harvesting_02")', 'chainlength = 5;',
    'hasSkill(player, "outdoors_bio_engineer_dna_harvesting_01")', 'chainlength = 4;'
)
$dnaCursor = -1
$dnaProgressionValid = $true
foreach ($token in $dnaOrder)
{
    $dnaCursor = $dna.IndexOf($token, $dnaCursor + 1, [System.StringComparison]::Ordinal)
    if ($dnaCursor -lt 0) { $dnaProgressionValid = $false; break }
}
Assert-Contract $dnaProgressionValid "p14.player-hq.override.dna-skill-box-progression"

$repair = Get-FunctionSlice $security "public int handleSlicingRepair" "public int handleObjectiveDisabled"
Assert-Contract ($repair.Contains('hasSkill(player, "combat_smuggler_slicing_04")') -and
    $repair.Contains('hasSkill(player, "combat_smuggler_slicing_03")') -and
    $repair.Contains('hasSkill(player, "combat_smuggler_slicing_02")') -and
    $repair.Contains("max = 4;") -and $repair.Contains("max = 3;") -and
    $repair.Contains("max = 2;") -and $repair.Contains("int max = 1;")) `
    "p14.player-hq.security.repair-skill-box-progression"

Assert-Contract ($override.Contains('xp.grant(player, xp.BIO_ENGINEER_DNA_HARVESTING, 1000);') -and
    $uplink.Contains('xp.grant(player, xp.BOUNTYHUNTER, 1000);') -and
    $power.Contains('xp.grant(player, xp.COMBAT_RANGEDSPECIALIZE_HEAVY, 1000);')) `
    "p14.player-hq.objective-authored-xp-restored"

foreach ($name in @("hq.objective_override", "hq.objective_power", "hq.objective_security", "hq.objective_uplink"))
{
    $text = [string]$texts[$name]
    Assert-Contract ($text.Contains("pvpAreFactionsOpposed") -and
        $text.Contains("hq.getNextObjective") -and $text.Contains("hq.getPriorObjective") -and
        $text.Contains("hq.VAR_IS_DISABLED")) "p14.player-hq.$name.order-and-faction-admission-retained"
}
Assert-Contract ($terminal.Contains("hq.VAR_OBJECTIVE_TRACKING") -and
    $terminal.Contains('getSkillStatMod(player, "group_melee_defense")') -and
    $terminal.Contains('getSkillStatMod(player, "group_range_defense")') -and
    $terminal.Contains("startCountdown(self, player)")) `
    "p14.player-hq.terminal.objective-and-countdown-lifecycle-retained"

$skills = [string]$texts["skills.table"]
foreach ($skillName in @(
    "outdoors_bio_engineer_novice", "outdoors_bio_engineer_dna_harvesting_01",
    "outdoors_bio_engineer_dna_harvesting_02", "outdoors_bio_engineer_dna_harvesting_03",
    "outdoors_bio_engineer_dna_harvesting_04", "outdoors_bio_engineer_master",
    "combat_commando_heavyweapon_speed_02", "combat_smuggler_slicing_01",
    "combat_smuggler_slicing_02", "combat_smuggler_slicing_03", "combat_smuggler_slicing_04",
    "combat_bountyhunter_investigation_02", "outdoors_squadleader_novice"))
{
    Assert-Contract ([regex]::IsMatch($skills, "(?m)^" + [regex]::Escape($skillName) + "`t")) `
        "p14.player-hq.skills-table.$skillName.exists"
}

$hqLibrary = [string]$texts["hq.library"]
$hqLoader = [string]$texts["hq.loader"]
$hqManager = [string]$texts["hq.objective_manager"]
$hqDeed = [string]$texts["hq.deed"]
$hqTemplate = [string]$texts["hq.template"]
Assert-Contract ($hqLibrary.Contains('public static final String VAR_HQ_BASE = "hq"') -and
    $hqLibrary.Contains('public static final String[] OBJECTIVE_TEMPLATE') -and
    $hqLoader.Contains("public int OnAttach") -and $hqManager.Contains("hq.loadVulnerability(self)") -and
    $hqManager.Contains("hq.unloadVulnerability(self)") -and
    $hqDeed.Contains("extends script.faction_perk.base.factional_deed") -and
    $hqTemplate.Contains("shared_factional_hq_base.iff") -and
    $hqTemplate.Contains('"faction_perk.hq.objective_manager"')) `
    "p14.player-hq.placement-objectives-and-template-retained"

$staticMaster = [string]$texts["static.master"]
$staticBaseMaster = [string]$texts["static.base_master"]
Assert-Contract ($staticMaster.Contains("gcw.isPostNgeFixedStaticBaseRetired()") -and
    $staticMaster.Contains('detachScript(self, "systems.gcw.static_base.master")') -and
    $staticBaseMaster.Contains("gcw.isPostNgeFixedStaticBaseRetired()") -and
    $staticBaseMaster.Contains('detachScript(self, "systems.gcw.static_base.base_master")')) `
    "p14.player-hq.post-nge-fixed-static-bases-remain-retired"

$battlefield = [string]$texts["battlefield.player"]
$missionTerminal = [string]$texts["mission.terminal"]
$missionBase = [string]$texts["mission.base"]
Assert-Contract ($battlefield.Contains("factions.addFactionStanding") -and
    $missionTerminal.Contains("menu_info_types.MISSION_TERMINAL_LIST") -and
    $missionBase.Contains("MAX_MISSIONS = 10") -and $missionBase.Contains("fullRewardEach=") -and
    $missionBase.Contains("split=false dailyCashPenalty=false")) `
    "p14.player-hq.open-world-battlefield-and-missions-retained"

$patchText = if (Test-Path -LiteralPath $patchPath) { Get-Content -LiteralPath $patchPath -Raw } else { "" }
$diffTargets = @([regex]::Matches($patchText, '(?m)^diff --git a/([^ ]+) b/[^\r\n]+$') | ForEach-Object { $_.Groups[1].Value })
$expectedTargets = @($contract.sourceFiles | ForEach-Object { ([string]$_).Substring(5) })
Assert-Contract (($diffTargets -join "`n") -ceq ($expectedTargets -join "`n")) `
    "p14.player-hq.overlay-targets-exactly-five-hq-scripts"
Assert-Contract (-not [regex]::IsMatch($patchText,
    '(?m)^diff --git a/(?:.*script/systems/gcw/static_base/|.*script/systems/battlefield/|.*script/systems/missions/|.*script/library/)')) `
    "p14.player-hq.overlay-does-not-touch-static-base-battlefield-mission-or-library"
Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains [string]$contract.status) `
    "p14.player-hq.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU player-HQ profession authority failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU player-HQ profession authority passed."
