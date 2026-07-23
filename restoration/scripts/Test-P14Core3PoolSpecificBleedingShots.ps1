param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3PoolSpecificBleedingShots)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
$enginePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/combat_engine.java"
$dotPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/library/dot.java"
$basePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$combatPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/combat_data.tab"
$overridePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_overrides.tab"
$spamPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"
$skillPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
$paths = @($enginePath,$dotPath,$basePath,$actionsPath,$fixturePath,$commandPath,$combatPath,$overridePath,$spamPath,$skillPath)
foreach ($path in $paths) { Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M254 source: $path" }
$engine = Get-Content -LiteralPath $enginePath -Raw
$dot = Get-Content -LiteralPath $dotPath -Raw
$base = Get-Content -LiteralPath $basePath -Raw
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$combat = Read-Rows $combatPath
$overrides = Read-Rows $overridePath
$spam = Read-Rows $spamPath
$skills = Read-Rows $skillPath
$specs = @(
    @{Name="healthShot1"; Owner="combat_marksman_pistol_04"; Weapon="PISTOL"; Time="2"; Damage="1.5"; Costs=@("0.5","0.75","0.5"); Accuracy="50"; Pool="HEALTH"; Attribute="HEALTH"; Spam="sapshot"; Duration="60"},
    @{Name="mindShot1"; Owner="combat_marksman_rifle_04"; Weapon="RIFLE"; Time="1"; Damage="1.5"; Costs=@("0.5","0.5","2"); Accuracy="5"; Pool="MIND"; Attribute="MIND"; Spam="distractshot"; Duration="120"}
)
foreach ($spec in $specs) {
    $name = $spec.Name
    Assert ($actions.Contains("public int $name(") -and
        $actions.Contains("combatStandardAction(`"$name`"")) "Action wrapper drifted: $name"
    $c = @($commands | Where-Object commandName -ceq $name)
    Assert ($c.Count -eq 1 -and $c[0].defaultTime -ceq $spec.Time -and
        $c[0].executeTime -ceq $spec.Time -and $c[0].validWeapon -ceq $spec.Weapon -and
        $c[0].addToCombatQueue -ceq "1") "Command row drifted: $name"
    $d = @($combat | Where-Object actionName -ceq $name)
    Assert ($d.Count -eq 1 -and $d[0].percentAddFromWeapon -ceq $spec.Damage -and
        $d[0].animDefault -ceq "fire_1_special_single" -and
        $d[0].attackType -ceq "SINGLE_TARGET" -and $d[0].weaponType -ceq $spec.Weapon -and
        $d[0].dotType -ceq "bleeding" -and $d[0].dotIntensity -ceq "60" -and
        $d[0].dotDuration -ceq $spec.Duration) "Combat/DOT row drifted: $name"
    $o = @($overrides | Where-Object actionName -ceq $name)
    Assert ($o.Count -eq 1 -and $o[0].healthCostMultiplier -ceq $spec.Costs[0] -and
        $o[0].actionCostMultiplier -ceq $spec.Costs[1] -and
        $o[0].mindCostMultiplier -ceq $spec.Costs[2] -and
        $o[0].targetPool -ceq $spec.Pool -and $o[0].speedMultiplier -ceq $spec.Time -and
        $o[0].accuracyBonus -ceq $spec.Accuracy -and $o[0].animationType -ceq "RANGED" -and
        $o[0].dotAttribute -ceq $spec.Attribute) "Override drifted: $name"
    $s = @($spam | Where-Object actionName -ceq $name)
    Assert ($s.Count -eq 1 -and $s[0].combatSpam -ceq $spec.Spam) "Spam row drifted: $name"
    $owner = @($skills | Where-Object NAME -ceq $spec.Owner)
    Assert ($owner.Count -eq 1 -and [string]$owner[0].COMMANDS -match "(^|,)$name(,|$)") "Skill owner drifted: $name"
}
foreach ($token in @("precuDotAttribute","dict.put(`"precuDotAttribute`"",
    "dict.getInt(`"precuDotAttribute`"")) {
    Assert ($engine.Contains($token)) "Combat-data bridge drifted: $token"
}
foreach ($token in @("actionData.precuDotAttribute >= 0","dot.applyDotEffect")) {
    Assert ($base.Contains($token)) "Initial DOT pool routing drifted: $token"
}
foreach ($token in @("int dotAttribute = getDotAttribute(target, dot_id)",
    "int dotPool = dotAttribute / 3","doDamageToPool(attacker, target, hit, dotPool)")) {
    Assert ($dot.Contains($token)) "Retained DOT pulse routing drifted: $token"
}
foreach ($token in @("healthShotOne","mindShotOne","healthShotDotAttribute=",
    "mindShotDotAttribute=","bleedingDotAttribute=","ORIGINAL_HEALTH_SHOT_ONE",
    "ORIGINAL_MIND_SHOT_ONE")) {
    Assert ($fixture.Contains($token)) "Fixture drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
$hashChecks = @{
    "combat_engine.java"=$enginePath; "dot.java"=$dotPath; "combat_base.java"=$basePath;
    "combat_actions.java"=$actionsPath; "precu_headshot1_fixture.java"=$fixturePath;
    "command_table.tab"=$commandPath; "combat_data.tab"=$combatPath;
    "precu_combat_overrides.tab"=$overridePath; "precu_combat_spam.tab"=$spamPath
}
foreach ($item in $hashChecks.GetEnumerator()) {
    Assert ((Sha $item.Value) -ceq [string]$hashes.($item.Key)) "Source hash drifted: $($item.Key)"
}
$patch = Join-Path $restorationRoot "patches/dsrc/252-p14-core3-pool-specific-bleeding-shots.patch"
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M254 is not Ready"
    Assert (@($contract.runtimeEvidence.commands).Count -eq 2 -and
        @($contract.runtimeEvidence.commands | Where-Object {
            $_.queueRemoval -ceq "Success" -and $_.weaponSatisfies -and
            $_.bleedingDot.strength -eq 60
        }).Count -eq 2) "Two-command authenticated bleeding evidence drifted"
    $health = @($contract.runtimeEvidence.commands | Where-Object command -ceq "healthShot1")[0]
    $mind = @($contract.runtimeEvidence.commands | Where-Object command -ceq "mindShot1")[0]
    Assert ($health.configuredTargetPool -eq 0 -and $health.bleedingDot.attribute -eq 0 -and
        $health.poolObservation.health[1] -lt $health.poolObservation.health[0] -and
        $health.poolObservation.action[1] -eq $health.poolObservation.action[0] -and
        $health.poolObservation.mind[1] -eq $health.poolObservation.mind[0]) "Health-pool proof drifted"
    Assert ($mind.configuredTargetPool -eq 2 -and $mind.bleedingDot.attribute -eq 6 -and
        $mind.poolObservation.mind[2] -lt $mind.poolObservation.mind[1] -and
        $mind.poolObservation.health[1] -eq $mind.poolObservation.health[0] -and
        $mind.poolObservation.action[1] -eq $mind.poolObservation.action[0]) "Mind-pool proof drifted"
    Assert ([bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) "Runtime cleanup boundary drifted"
}
Write-Host "Publish 14.1 Core3 pool-specific bleeding shots contract passed."
