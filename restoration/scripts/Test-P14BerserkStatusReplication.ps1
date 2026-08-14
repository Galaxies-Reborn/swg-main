param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14BerserkStatusReplication)) -Raw | ConvertFrom-Json
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
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing Berserk status source: $path"
}
$repositoryRoot = Split-Path -Parent $restorationRoot
Assert (Test-Path -LiteralPath (Join-Path $repositoryRoot ([string]$contract.overlay)) -PathType Leaf) "Berserk status overlay is missing"

$buffs = Rows $paths.buffTable
$status = @($buffs | Where-Object NAME -CEQ "precu_berserk_status")
Assert ($status.Count -eq 1) "precu_berserk_status row missing or duplicated"
$status = $status[0]
Assert ($status.GROUP1 -ceq "precuBerserkStatus" -and
    $status.ICON -ceq "command.berserk" -and
    $status.DURATION -ceq "0" -and
    $status.STATE -ceq "STATE_NONE" -and
    $status.CALLBACK -ceq "none" -and
    $status.VISIBLE -ceq "1" -and
    $status.DEBUFF -ceq "0" -and
    $status.MAX_STACKS -ceq "1" -and
    $status.IS_PERSISTENT -ceq "0") "Berserk presentation row drifted"
foreach ($number in 1..5) {
    Assert ($status.("EFFECT${number}_PARAM") -ceq "" -and
        $status.("EFFECT${number}_VALUE") -ceq "0") "Berserk status unexpectedly changes gameplay through effect $number"
}

$player = Get-Content -LiteralPath $paths.player -Raw
foreach ($handlerName in @("berserk1", "berserk2")) {
    $handler = BracedBlock $player ("public int " + $handlerName + "(")
    Assert ($handler.Length -gt 0) "Missing $handlerName handler"
    $apply = $handler.IndexOf("buff.applyBuff(self, self, PRECU_BERSERK_STATUS_BUFF", [StringComparison]::Ordinal)
    $drain = $handler.IndexOf("drainCombatAttributes(self, healthCost, actionCost, mindCost)", [StringComparison]::Ordinal)
    Assert ($apply -ge 0 -and $drain -gt $apply) "$handlerName no longer applies status before its HAM transaction"
    Assert ($handler.Contains('"buffApplyFailed"') -and
        $handler.Contains("buff.removeBuff(self, PRECU_BERSERK_STATUS_BUFF)")) "$handlerName replication rollback drifted"
}

$expiry = BracedBlock $player "public int handlePrecuBerserkExpiry("
Assert ($expiry.Contains("buff.removeBuff(self, PRECU_BERSERK_STATUS_BUFF)") -and
    $expiry.IndexOf("buff.removeBuff", [StringComparison]::Ordinal) -lt
    $expiry.IndexOf("setState(self, STATE_BERSERK, false)", [StringComparison]::Ordinal)) "Berserk expiry no longer removes presentation before state"
$restore = BracedBlock $player "private void restorePrecuBerserkState("
Assert ($restore.Contains("buff.applyBuff(player, player, PRECU_BERSERK_STATUS_BUFF") -and
    $restore.Contains("expiresAt - getGameTime()") -and
    $restore.Contains("buff.removeBuff(player, PRECU_BERSERK_STATUS_BUFF)")) "Berserk relog restoration drifted"

foreach ($fixturePath in @($paths.berserkOneFixture, $paths.berserkTwoFixture)) {
    $fixture = Get-Content -LiteralPath $fixturePath -Raw
    Assert ($fixture.Contains('BERSERK_STATUS_BUFF = "precu_berserk_status"') -and
        $fixture.Contains("buff.removeBuff(player, BERSERK_STATUS_BUFF)") -and
        $fixture.Contains("!buff.hasBuff(player, BERSERK_STATUS_BUFF)")) "Berserk fixture cleanup drifted: $fixturePath"
}

if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "Berserk status replication is not Ready"
}
Write-Host "Publish 14.1 Berserk status replication contract passed."
