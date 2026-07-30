param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14CenterOfBeingLifecycle)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path

function Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function BracedBlock([string]$Text, [string]$Signature) {
    $start = $Text.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -eq '{') { $depth++ }
        elseif ($Text[$index] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $index - $start + 1) }
        }
    }
    return ""
}

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties) {
    $paths[[string]$property.Name] = Join-Path $root ([string]$property.Value)
}
foreach ($path in $paths.Values) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing Center of Being source: $path"
}

$commands = Rows $paths.commandTable
$command = @($commands | Where-Object commandName -CEQ "centerOfBeing")
Assert ($command.Count -eq 1) "centerOfBeing command row missing or duplicated"
$command = $command[0]
Assert ($command.scriptHook -ceq "centerOfBeing" -and
    $command.failScriptHook -ceq "failSpecialAttack" -and
    $command.defaultPriority -ceq "normal" -and
    $command.characterAbility -ceq "centerOfBeing" -and
    $command.addToCombatQueue -ceq "1") "centerOfBeing command routing drifted"

$skills = Rows $paths.skillTable
$novice = @($skills | Where-Object NAME -CEQ "combat_brawler_novice")
Assert ($novice.Count -eq 1) "combat_brawler_novice row missing or duplicated"
$novice = $novice[0]
Assert ([string]$novice.COMMANDS -match "(^|,)centerOfBeing(,|$)") "Brawler novice no longer grants Center of Being"
foreach ($family in @($contract.weaponFamilies)) {
    Assert ([string]$novice.SKILL_MODS -match ("(^|,)" + [regex]::Escape([string]$family.durationModifier) + "=[1-9][0-9]*(,|$)")) "Missing positive duration modifier: $($family.durationModifier)"
    Assert ([string]$novice.SKILL_MODS -match ("(^|,)" + [regex]::Escape([string]$family.efficacyModifier) + "=[1-9][0-9]*(,|$)")) "Missing positive efficacy modifier: $($family.efficacyModifier)"
}

$actions = Get-Content -LiteralPath $paths.combatActions -Raw
$handler = BracedBlock $actions "public int centerOfBeing("
Assert ($handler.Length -gt 0) "Center of Being handler missing"
Assert (-not $handler.Contains('combatStandardAction("centerOfBeing"')) "Center of Being still enters the NGE combat/cost path"
Assert ($handler.Contains('buff.hasBuff(self, "centerofbeing")') -and
    $handler.Contains('new string_id("combat_effects", "already_centered")')) "Duplicate-buff admission drifted"
foreach ($family in @($contract.weaponFamilies)) {
    Assert ($handler.Contains([string]$family.type) -and
        $handler.Contains('"' + [string]$family.durationModifier + '"') -and
        $handler.Contains('"' + [string]$family.efficacyModifier + '"')) "Weapon-family routing drifted: $($family.type)"
}
Assert ($handler.Contains('getEnhancedSkillStatisticModifierUncapped(') -and
    $handler.Contains('buff.applyBuff(') -and
    $handler.Contains('self, self, "centerofbeing", duration, efficacy)')) "Timed dynamic buff application drifted"
Assert ($handler.Contains('combat_engine.getCombatData("centerOfBeing")') -and
    $handler.Contains('combat.getActionCost(self, weaponData, actionData)') -and
    $handler.Contains('combat.canDrainCombatActionAttributes(') -and
    $handler.Contains('combat.drainCombatActionAttributes(') -and
    $handler.Contains('buff.removeBuff(self, "centerofbeing")')) "Center Action-cost transaction drifted"
Assert ($handler.Contains('new string_id("combat_effects", "center_start")') -and
    $handler.Contains('new string_id("combat_effects", "center_start_fly")') -and
    $handler.Contains('colors.GREEN')) "Center start feedback drifted"

$player = Get-Content -LiteralPath $paths.player -Raw
$expiry = BracedBlock $player "public int handlePrecuCenterOfBeingExpired("
Assert ($expiry.Contains('new string_id("combat_effects", "center_stop")') -and
    $expiry.Contains('new string_id("combat_effects", "center_stop_fly")') -and
    $expiry.Contains('colors.RED')) "Center expiry feedback drifted"

$buffs = Rows $paths.buffTable
$center = @($buffs | Where-Object NAME -CEQ "centerofbeing")
Assert ($center.Count -eq 1) "centerofbeing buff row missing or duplicated"
$center = $center[0]
Assert ($center.ICON -ceq "command.centerOfBeing" -and
    $center.EFFECT1_PARAM -ceq "private_center_of_being" -and
    $center.CALLBACK -ceq "handlePrecuCenterOfBeingExpired" -and
    $center.VISIBLE -ceq "1" -and
    $center.DEBUFF -ceq "0" -and
    $center.MAX_STACKS -ceq "1") "centerofbeing replication row drifted"

$mappings = Rows $paths.effectMapping
$mapping = @($mappings | Where-Object NAME -CEQ "private_center_of_being")
Assert ($mapping.Count -eq 1 -and
    $mapping[0].TYPE -ceq "skill" -and
    $mapping[0].SUBTYPE -ceq "private_center_of_being") "Center of Being effect mapping drifted"

$combatBase = Get-Content -LiteralPath $paths.combatBase -Raw
$secondary = BracedBlock $combatBase "public int getPrecuSecondaryDefenseResult("
Assert ($secondary.Contains('getEnhancedSkillStatisticModifierUncapped(defenderData.id, "private_center_of_being")')) "Pre-CU defense resolver no longer consumes Center of Being"

$combatActions = Rows $paths.combatData
$centerAction = @($combatActions | Where-Object actionName -CEQ "centerOfBeing")
Assert ($centerAction.Count -eq 1) "centerOfBeing combat-data row missing or duplicated"
Assert ([int]$centerAction[0].actionCost -eq 50) "centerOfBeing Action cost drifted from 50"

if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "Center of Being lifecycle is not Ready"
}
Write-Host "Publish 14.1 Center of Being lifecycle contract passed."
