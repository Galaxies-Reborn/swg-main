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
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot `
    ([string]$manifest.contracts.p14PrecuConversationProfessionGates)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$conversationRoot = Join-Path $source "dsrc/sku.0/sys.server/compiled/game/script/conversation"
$skillsPath = Join-Path $source "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Name)
{
    if ($Condition) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name"; $failures.Add($Name) }
}

function Get-Conversation([string]$Name)
{
    return Get-Content -LiteralPath (Join-Path $conversationRoot ($Name + ".java")) -Raw
}

Assert-Contract (Test-Path -LiteralPath $conversationRoot -PathType Container) `
    "p14.precu-conversation-gates.source.package"
Assert-Contract (Test-Path -LiteralPath $skillsPath -PathType Leaf) `
    "p14.precu-conversation-gates.skills.table"

foreach ($evidence in @($contract.buildEvidence.overlayPatches))
{
    $patchPath = Join-Path $repositoryRoot ([string]$evidence.path)
    $exists = Test-Path -LiteralPath $patchPath -PathType Leaf
    Assert-Contract $exists "p14.precu-conversation-gates.overlay.exists"
    if ($exists)
    {
        $patch = Get-Item -LiteralPath $patchPath
        $sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Contract ($patch.Length -eq [long]$evidence.bytes -and
            $sha -ceq [string]$evidence.sha256) "p14.precu-conversation-gates.overlay.authenticated"
    }
}

$conversationFiles = @(Get-ChildItem -LiteralPath $conversationRoot -Filter "*.java" -File)
$retiredReferences = @($conversationFiles | Select-String -SimpleMatch '"class_')
Assert-Contract ($retiredReferences.Count -eq 0) `
    "p14.precu-conversation-gates.zero-class-skill-references"
Assert-Contract (@($contract.sourceFiles).Count -eq 12) `
    "p14.precu-conversation-gates.converted-file-count"
foreach ($relative in @($contract.sourceFiles))
{
    Assert-Contract (Test-Path -LiteralPath (Join-Path $source ([string]$relative)) -PathType Leaf) `
        ("p14.precu-conversation-gates.converted-source." + [IO.Path]::GetFileNameWithoutExtension([string]$relative))
}

$dath = Get-Conversation "dath_bh_wanted_list_01"
Assert-Contract (([regex]::Matches($dath, 'hasSkill\(player, "combat_bountyhunter_novice"\)')).Count -eq 2) `
    "p14.precu-conversation-gates.bounty-hunter"

foreach ($name in @("ep3_kachirho_missing_son", "ep3_rodian_junk_dealer", "ep3_wke_junk_dealer"))
{
    Assert-Contract ((Get-Conversation $name).Contains('hasSkill(player, "combat_smuggler_underworld_01")')) `
        ("p14.precu-conversation-gates.wookiee-language." + $name)
}
foreach ($name in @("ep3_myyydril_pers", "som_kenobi_epo_qetora"))
{
    Assert-Contract ((Get-Conversation $name).Contains('hasSkill(player, "combat_smuggler_novice")')) `
        ("p14.precu-conversation-gates.smuggler." + $name)
}
Assert-Contract ((Get-Conversation "ep3_myyydril_weaponsmith").Contains(
    'hasSkill(player, "crafting_weaponsmith_novice")')) `
    "p14.precu-conversation-gates.weaponsmith"

foreach ($name in @("imperial_empire_day_kaythree", "rebel_remembrance_day_rieekan"))
{
    $holiday = Get-Conversation $name
    $holidaySkills = @(
        "crafting_architect_novice",
        "crafting_droidengineer_novice",
        "crafting_weaponsmith_novice",
        "crafting_armorsmith_novice",
        "crafting_chef_novice",
        "crafting_tailor_novice"
    )
    Assert-Contract ((@($holidaySkills | Where-Object { -not $holiday.Contains($_) })).Count -eq 0) `
        ("p14.precu-conversation-gates.holiday-crafting." + $name)
}

Assert-Contract ((Get-Conversation "mun_quest_marauder").Contains(
    'hasSkill(player, "crafting_armorsmith_master")')) `
    "p14.precu-conversation-gates.marauder-armorsmith"
$crowd = Get-Conversation "quest_crowd_pleaser_manager"
Assert-Contract (([regex]::Matches($crowd, 'hasSkill\(player, "social_entertainer_master"\)')).Count -eq 2) `
    "p14.precu-conversation-gates.crowd-pleaser-entertainer"

$chronicles = Get-Conversation "fan_faire_pgc_c3po"
Assert-Contract ($chronicles.Contains("Chronicle profession progression is unavailable in PRE-CU.") -and
    -not $chronicles.Contains("grantSkill(") -and
    $chronicles.Contains("return false;")) `
    "p14.precu-conversation-gates.chronicles-retired"

$skills = Get-Content -LiteralPath $skillsPath
$expectedSkills = @(
    "combat_bountyhunter_novice",
    "combat_smuggler_novice",
    "combat_smuggler_underworld_01",
    "crafting_weaponsmith_novice",
    "crafting_architect_novice",
    "crafting_droidengineer_novice",
    "crafting_armorsmith_novice",
    "crafting_chef_novice",
    "crafting_tailor_novice",
    "crafting_armorsmith_master",
    "social_entertainer_master"
)
foreach ($skill in $expectedSkills)
{
    Assert-Contract (@($skills | Where-Object { $_ -like ($skill + "`t*") }).Count -eq 1) `
        ("p14.precu-conversation-gates.skill-exists." + $skill)
}

Assert-Contract (@("implemented-build-pending", "ready-for-live-verification", "ready") -contains
    [string]$contract.status) "p14.precu-conversation-gates.contract.status"

if ($failures.Count -gt 0)
{
    throw "Publish 14 PRE-CU conversation profession gates failed: $($failures -join ', ')"
}
Write-Host "Publish 14 PRE-CU conversation profession gates passed."
