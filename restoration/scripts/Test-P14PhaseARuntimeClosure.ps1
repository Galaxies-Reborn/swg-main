param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-DataRows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0].Split("`t")
    @($lines[2..($lines.Count - 1)] | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
$skills = Read-DataRows (Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab")
$artisan = @($skills | Where-Object NAME -ceq "crafting_artisan_novice")
if ($artisan.Count -ne 1) { throw "Artisan novice row is not unique." }
$row = $artisan[0]
if ($row.GRAPH_TYPE -cne "fourByFour" -or $row.XP_TYPE -cne "" -or
    $row.XP_COST -cne "0" -or $row.XP_CAP -cne "0" -or
    (([string]$row.COMMANDS).Split(",") -join ",") -cne "private_artisan_novice,sample,survey" -or
    ([string]$row.SKILL_MODS).Split(",") -cnotcontains "slope_move=25") {
    throw "Server-authoritative Artisan novice progression drifted."
}
$runtime = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_phase_a_runtime.java") -Raw
$money = Get-Content -LiteralPath (Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/player/player_money.java") -Raw
$requiredRuntime = @(
    "reconcileLegacyLifecycleBaseline",
    "clearStalePurchaseEnqueueing",
    "money.HANDLER_PAYMENT_REQUEST",
    "0.01f",
    "script.npc.skillteacher.skillteacher",
    "handler.OnStartNpcConversation(trainer, player)",
    "queuePath=",
    "LEGACY_PRE_M239_BASE_POINTS = 220",
    "M239_BASE_POINTS = 191"
)
foreach ($token in $requiredRuntime) {
    if (-not $runtime.Contains($token)) { throw "Phase-A runtime closure token is missing: $token" }
}
if ($runtime.Contains('" operationId=" + args[4] +')) {
    throw "Trainer purchase result still duplicates operationId."
}
$requiredMoney = @(
    "public int OnLogin(obj_id self)",
    "utils.hasScriptVar(self, PRECU_RELOG_NONCE)",
    '"purchaseSucceeded".equals(getStringObjVar(self, PRECU_OP_STATE))',
    '"SUCCESS".equals(getStringObjVar(self, PRECU_OP_ACCOUNTING_OUTCOME))',
    "hasExactHeldPhaseACraftingVector(self)",
    "utils.removeScriptVar(self, PRECU_RELOG_NONCE)"
)
foreach ($token in $requiredMoney) {
    if (-not $money.Contains($token)) { throw "Phase-A relog boundary token is missing: $token" }
}
$phaseA = Get-Content -LiteralPath (Join-Path $root "restoration/contracts/phase-a.json") -Raw | ConvertFrom-Json
if (@($phaseA.surrenderPolicy.protectedExact).Count -ne 0 -or
    @($phaseA.surrenderPolicy.protectedPrefixes) -contains "outdoors_squadleader_") {
    throw "Phase-A surrender policy still protects a restored profession family."
}
$runner = Get-Content -LiteralPath (Join-Path $root "restoration/scripts/Invoke-PhaseATrainerPersistence.ps1") -Raw
if (-not $runner.Contains("Adopted the exact terminal trainer callback after interrupted probe parsing.")) {
    throw "Terminal callback adoption recovery is missing."
}
if ($Expectation -eq "Ready") {
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-phase-a-runtime-closure.json") -Raw | ConvertFrom-Json
    if ($contract.status -cne "ready" -or
        $contract.evidenceRole -cne "historical-publish14-phase-a-snapshot" -or
        $contract.currentAuthority.ownerContract -cne "contracts/p14-precu-base-novice-learning.json" -or
        $contract.currentAuthority.directSourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
        $contract.runtimeEvidence.result -cne "passed" -or
        $contract.runtimeEvidence.accountingOutcome -cne "SUCCESS" -or
        $contract.runtimeEvidence.sameProcessRelogBoundary -cne "passed" -or
        $contract.runtimeEvidence.serverRestartBoundary -cne "passed" -or
        $contract.runtimeEvidence.productionSurrender -cne "passed" -or
        $contract.runtimeEvidence.exactBaselineRestoration -cne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy -or
        [int]$contract.closureEvidence.phaseABaselineBlockers -ne 0 -or
        [int]$contract.closureEvidence.remainingDocumentedAcceptanceBlockers -ne 0 -or
        [int]$contract.closureEvidence.remainingMilestoneCandidates -ne 0) {
        throw "Phase-A runtime closure evidence is not ready."
    }
}
Write-Host "Publish 14.1 Phase-A runtime closure contract passed."
