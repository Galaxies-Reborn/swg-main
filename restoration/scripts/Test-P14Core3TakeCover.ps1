param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3TakeCover)
) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 |
        ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
$actionsPath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_actions.java"
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$skillPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
foreach ($path in @($actionsPath,$fixturePath,$commandPath,$skillPath)) {
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing M262 source: $path"
}
$actions = Get-Content -LiteralPath $actionsPath -Raw
$fixture = Get-Content -LiteralPath $fixturePath -Raw
$commands = Read-Rows $commandPath
$skills = Read-Rows $skillPath
$row = @($commands | Where-Object commandName -ceq "takeCover")
Assert ($row.Count -eq 1 -and $row[0].scriptHook -ceq "takeCover" -and
    $row[0].defaultTime -ceq "4" -and $row[0].executeTime -ceq "4" -and
    $row[0].targetType -ceq "optional" -and $row[0].commandGroup -ceq "-560185247" -and
    $row[0].addToCombatQueue -ceq "1" -and $row[0].validWeapon -ceq "ALL") `
    "takeCover command row drifted"
$owners = @($skills | Where-Object {
    [string]$_.COMMANDS -match "(^|,)takeCover(,|$)"
})
Assert ($owners.Count -eq 1 -and
    $owners[0].NAME -ceq "combat_marksman_rifle_02") `
    "takeCover retained skill ownership drifted"
foreach ($token in @(
    "public int takeCover(",
    "getAttrib(self, QUICKNESS) - 300",
    "/ 1200.0f",
    "actionBefore < actionCost",
    "setAttrib(self, ACTION, actionBefore - actionCost)",
    "getState(self, STATE_DIZZY) > 0",
    "rand(0, 100) < 85",
    "10 + getSkillStatisticModifier(self, `"take_cover`")",
    "roll > chance",
    "setState(self, STATE_COVER, true)",
    "cover_fail_single",
    "cover_success",
    "takeCover.result",
    "ORIGINAL_COVER_STATE",
    "ORIGINAL_RIFLE_TWO",
    "ORIGINAL_TAKE_COVER_COMMAND",
    "takeCoverDiagnosticResult="
)) {
    Assert ($actions.Contains($token) -or $fixture.Contains($token)) `
        "takeCover lifecycle drifted: $token"
}
$hashes = $contract.buildEvidence.sourceSha256
if ($null -ne $hashes -and
    @($hashes.PSObject.Properties).Count -gt 0) {
    $hashChecks = @{
        "combat_actions.java"=$actionsPath
        "precu_headshot1_fixture.java"=$fixturePath
        "command_table.tab"=$commandPath
        "skills.tab"=$skillPath
    }
    foreach ($item in $hashChecks.GetEnumerator()) {
        Assert ((Sha $item.Value) -ceq [string]$hashes.($item.Key)) `
            "Source hash drifted: $($item.Key)"
    }
}
$patch = Join-Path $restorationRoot "patches/dsrc/260-p14-core3-take-cover.patch"
Assert ((Sha $patch) -ceq [string]$contract.buildEvidence.overlaySha256) `
    "Overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") `
        "M262 is not Ready"
    Assert ([string]$contract.runtimeEvidence.queueRemoval -ceq "Success" -and
        [bool]$contract.runtimeEvidence.outOfCombat -and
        [int]$contract.runtimeEvidence.coverStateAfter -eq 1 -and
        [string]$contract.runtimeEvidence.diagnosticResult -ceq "SUCCESS" -and
        [bool]$contract.runtimeEvidence.actionDebitExact -and
        [bool]$contract.runtimeEvidence.persistence.observed -and
        [bool]$contract.runtimeEvidence.cleanup.restored -and
        [bool]$contract.runtimeEvidence.cleanup.idempotent -and
        [bool]$contract.runtimeEvidence.serverHealthy -and
        [bool]$contract.runtimeEvidence.userClientUntouched) `
        "Authenticated takeCover evidence drifted"
}
Write-Host "Publish 14.1 Core3 takeCover contract passed."
