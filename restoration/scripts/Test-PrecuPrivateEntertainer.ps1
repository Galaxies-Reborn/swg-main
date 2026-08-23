[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dsrc = Join-Path $root "dsrc"
$paths = [ordered]@{
    Attributes = Join-Path $dsrc ".gitattributes"
    Bartender = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/npc/bartender/base.java"
    Library = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/library/private_entertainer.java"
    Performer = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/npc/private_entertainer/performer.java"
    Audience = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/player/private_entertainer_audience.java"
    Payment = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/player/private_entertainer_payment.java"
    Fixture = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/test/precu_private_entertainer_fixture.java"
    Performance = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/library/performance.java"
    Buff = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/library/buff.java"
    PerformCommands = Join-Path $dsrc "sku.0/sys.server/compiled/game/script/player/skill/performcommands.java"
    Generator = Join-Path $PSScriptRoot "New-PrecuPrivateEntertainerStringTable.ps1"
    StringTable = Join-Path $root "serverdata/string/en/precu_private_entertainer.stf"
}

foreach ($entry in $paths.GetEnumerator())
{
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf))
    {
        throw "Missing $($entry.Key): $($entry.Value)"
    }
}

$source = @{}
foreach ($key in @(
    "Attributes", "Bartender", "Library", "Performer", "Audience",
    "Payment", "Fixture", "Performance", "Buff", "PerformCommands"))
{
    $source[$key] = [System.IO.File]::ReadAllText($paths[$key])
}

function Assert-Contains(
    [string]$Name,
    [string]$Text,
    [string]$Needle)
{
    if (-not $Text.Contains($Needle))
    {
        throw "$Name is missing required evidence: $Needle"
    }
}

function Assert-NotContains(
    [string]$Name,
    [string]$Text,
    [string]$Needle)
{
    if ($Text.Contains($Needle))
    {
        throw "$Name contains forbidden evidence: $Needle"
    }
}

function Assert-Matches(
    [string]$Name,
    [string]$Text,
    [string]$Pattern)
{
    if ($Text -notmatch $Pattern)
    {
        throw "$Name is missing required pattern: $Pattern"
    }
}

Assert-Contains "attributes" $source.Attributes `
    "sku.0/sys.server/compiled/game/script/npc/bartender/base.java -text whitespace=cr-at-eol"

[byte[]]$bartenderBytes = [System.IO.File]::ReadAllBytes($paths.Bartender)
$lf = 0
$crlf = 0
for ($index = 0; $index -lt $bartenderBytes.Length; $index++)
{
    if ($bartenderBytes[$index] -eq 10)
    {
        $lf++
        if ($index -gt 0 -and $bartenderBytes[$index - 1] -eq 13)
        {
            $crlf++
        }
    }
}
if ($lf -ne $crlf)
{
    throw "Bartender source contains bare LF line endings."
}

foreach ($needle in @(
    '"hire_private_entertainer"',
    "OnObjectMenuRequest(",
    "menu_info_types.SERVER_MENU50",
    "showPrivateEntertainerHireSui",
    "tbl.equals(private_entertainer.STF)",
    'response.equals("hire_private_entertainer")',
    '":hire_dancer"',
    '":hire_musician"',
    '":hire_both"',
    'params.getInt("pageId")',
    'utils.getIntScriptVar(self, root + ".pid") != pageId',
    "setSUIMaxRangeToObject(",
    "private_entertainer.canUseBartender(player, self)"))
{
    Assert-Contains "bartender" $source.Bartender $needle
}

foreach ($needle in @(
    "public static final int BUFF_PRICE = 10000;",
    "public static final float BUFF_STRENGTH_PERCENT = 25.0f;",
    "public static final int HIRE_LIFETIME_SECONDS = 1800;",
    "public static final int OWNER_AWAY_GRACE_SECONDS = 120;",
    "player.isAuthoritative()",
    "getObjIdObjVar(performer, VAR_OWNER) != player",
    "building == getCantinaBuilding(player)",
    "getDistance(player, performer) > PERFORMER_USE_RANGE",
    "performance.applyPrecuEntertainerAttributeBuff(",
    "money.requestPayment(",
    "money.ACCT_PERFORM_ESCROW",
    "PAYMENT_TIMED_OUT",
    "beginPaymentRefund(player, true)",
    "transferBankCreditsFromNamedAccount(",
    "params.getObjId(money.DICT_TARGET_ID) == obj_id.NULL_ID",
    "params.getObjId(money.DICT_PLAYER_ID) == player",
    "params.getObjId(money.DICT_TARGET_ID) != player",
    "params.getObjId(money.DICT_PLAYER_ID) != player",
    "money.ACCT_PERFORM_ESCROW.equals(",
    '"handlePrivateEntertainerRefundSuccess"',
    '"handlePrivateEntertainerRefundFailure"',
    "money.DICT_PAY_HANDLER",
    "money.DICT_NOTIFY",
    "money.HANDLER_PAY_DEPOSIT.equals(transportHandler)",
    "transferAmount > 0 && transferAmount <= BUFF_PRICE",
    "params.getInt(money.DICT_TOTAL) == BUFF_PRICE",
    '!params.containsKey("private_refund_late")',
    "completePaymentRefund(",
    "getSelf() != player",
    "removeObjVar(player, PAYMENT_ROOT)"))
{
    Assert-Contains "library" $source.Library $needle
}
Assert-NotContains "library" $source.Library "buffBuilderStart"
Assert-NotContains "library" $source.Library "openInspireMenu("
Assert-Matches "payment request failure cleanup" $source.Library `
    '(?s)if\s*\(!requested\)\s*\{\s*cleanupPaymentSession\(player\);'
Assert-Matches "payment script attach failure cleanup" $source.Library `
    '(?s)attachScript\(player, SCRIPT_PAYMENT\).*?if\s*\(attachResult != SCRIPT_CONTINUE.*?cleanupPaymentSession\(player\);'
Assert-NotContains "private audience path" `
    ($source.Library + $source.Audience + $source.Performer) `
    "beginPrecuEntertainerBuffSession"

foreach ($needle in @(
    '"buff_yourself"',
    '"@performance:inspire_menu_title"',
    '"@performance:inspire_menu_prompt "',
    'params.getInt("pageId")',
    "utils.getIntScriptVar(self, BUFF_UI_PID) != pageId",
    "utils.hasScriptVar(self, BUFF_UI_NONCE)",
    "selectionNonce.length() < 16",
    "private_entertainer.canPlayerUse(player, self, type)",
    "private_entertainer.beginPaidBuff(",
    "handlePrivateEntertainerLifecycle",
    "private_entertainer.OWNER_AWAY_GRACE_SECONDS",
    "private_entertainer.cleanupAudience(self)"))
{
    Assert-Contains "performer" $source.Performer $needle
}

foreach ($needle in @(
    "getSelf() != player",
    "setPerformanceWatchTarget(player, performer)",
    "setPerformanceListenTarget(player, performer)",
    'listenToMessage(performer, "handlePerformerStopPerforming")',
    'createTriggerVolume(',
    '"performance_watch_volume"',
    '"performance_listen_volume"',
    "addTriggerVolumeEventSource(",
    "performance.startEntertainingPlayer(player)",
    "performance.PERFORMANCE_ENTERTAINED_SCRIPT"))
{
    Assert-Contains "audience setup" `
        ($source.Library + $source.Audience) $needle
}
Assert-Contains "audience coexistence" $source.Audience `
    "watchTarget == activeDancer"
Assert-Contains "audience coexistence" $source.Audience `
    "listenTarget == activeMusician"
Assert-NotContains "audience coexistence" $source.Audience `
    "removeObjVar("

foreach ($needle in @(
    "schedulePendingTimeout(self)",
    "private_entertainer.markPaymentTimedOut(",
    "private_entertainer.completePaidBuff(self, params)",
    "private_entertainer.completePaymentRefund(self, params)",
    "handlePrivateEntertainerRefundSuccess(",
    "handlePrivateEntertainerRefundFailure(",
    "beginRefundAndRetryIfNeeded(",
    "Native no-dispatch failures do not produce a callback",
    "PAYMENT_REFUND_FAILED",
    "MAX_REFUND_ATTEMPTS = 3",
    "hasExactNonce("))
{
    Assert-Contains "payment coordinator" $source.Payment $needle
}

foreach ($needle in @(
    "PLAYER_OID = 39008597L",
    "PLAYER_STATION_ID = 1001",
    "private_entertainer.BUFF_PRICE == 10000",
    "private_entertainer.applyConfiguredBuff(",
    "durationMatches(",
    "restored="))
{
    Assert-Contains "fixture" $source.Fixture $needle
}

# The stock player-only watch/listen boundary and retired NGE inspiration gate
# must remain untouched; ordinary entertainers cannot enter the NGE builder,
# while the private path is isolated in its own scripts.
Assert-NotContains "performance library" $source.Performance `
    "private_entertainer"
Assert-Contains "performance library" $source.Performance `
    "if (!isPlayer(target))"
Assert-Matches "retired inspiration predicate" $source.Buff `
    '(?s)public static boolean isPostNgeBuffProgressionRetired\(\)\s*\{\s*return true;\s*\}'
$inspireStart = $source.PerformCommands.IndexOf("public int cmdInspire(")
$retiredGate = $source.PerformCommands.IndexOf(
    "if (buff.isPostNgeBuffProgressionRetired())",
    $inspireStart)
$retiredReturn = $source.PerformCommands.IndexOf(
    "return SCRIPT_CONTINUE;",
    $retiredGate)
$builderStart = $source.PerformCommands.IndexOf(
    "buffBuilderStart(self, inspireTarget);",
    $inspireStart)
if ($inspireStart -lt 0 -or $retiredGate -lt $inspireStart -or
    $retiredReturn -lt $retiredGate -or $builderStart -lt $retiredReturn)
{
    throw "Ordinary entertainer inspiration is not fail-closed before the NGE builder."
}

# Persistent callback contracts: a restart re-arms pending timeouts, refunds a
# settling debit, retries only explicit refund failures, and leaves timed-out
# payments intact so a late success can be returned from escrow exactly once.
Assert-Matches "pending restart recovery" $source.Payment `
    '(?s)PAYMENT_PENDING\.equals\(state\).*?schedulePendingTimeout\(self\);'
Assert-Matches "settling restart recovery" $source.Payment `
    '(?s)PAYMENT_SETTLING\.equals\(state\).*?beginRefundAndRetryIfNeeded\(self, false\);'
Assert-Matches "refund failure restart recovery" $source.Payment `
    '(?s)PAYMENT_REFUND_FAILED\.equals\(state\).*?scheduleRefundRetry\(self\);'
$refundHelperStart = $source.Payment.IndexOf(
    "private void beginRefundAndRetryIfNeeded(")
$refundDispatch = $source.Payment.IndexOf(
    "private_entertainer.beginPaymentRefund(self, late);",
    $refundHelperStart)
$refundFailed = $source.Payment.IndexOf(
    "private_entertainer.PAYMENT_REFUND_FAILED.equals(",
    $refundDispatch)
$refundRetry = $source.Payment.IndexOf(
    "scheduleRefundRetry(self);",
    $refundFailed)
$nextPaymentHelper = $source.Payment.IndexOf(
    "private void schedulePendingTimeout(",
    $refundHelperStart)
if ($refundHelperStart -lt 0 -or $refundDispatch -lt $refundHelperStart -or
    $refundFailed -lt $refundDispatch -or $refundRetry -lt $refundFailed -or
    $nextPaymentHelper -lt $refundRetry)
{
    throw "An immediate native refund no-dispatch does not arm the bounded retry."
}
Assert-Matches "late successful debit refund" $source.Library `
    '(?s)PAYMENT_TIMED_OUT\.equals\(state\).*?beginPaymentRefund\(player, true\);'

& $paths.Generator -Check

Write-Host "PASS: private entertainer bartender, owner gate, recipient UI, native audience state, PRE-CU buffs, payment/refund state machine, lifecycle, fixture, and STF are wired."
