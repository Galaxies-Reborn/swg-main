[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$patchPath = Join-Path $restorationRoot "patches\src\333-precu-radial-menu-recovery.patch"
$patchText = Get-Content -LiteralPath $patchPath -Raw

$requiredSourceFragments = @(
    "void PlayerCreatureController::sendEmptyObjectMenuResponse",
    "RadialMenuManager::DataVector emptyMenuInfo;",
    "msg->getTargetId(),",
    "msg->m_sequence),",
    "if (!target)",
    "sendEmptyObjectMenuResponse(msg);",
    "has no script object; returning an empty response"
)

if (-not $patchText.Contains("void sendEmptyObjectMenuResponse(MessageQueueObjectMenuRequest const *msg);"))
{
    throw "PlayerCreatureController does not declare the empty radial response helper."
}

foreach ($fragment in $requiredSourceFragments)
{
    if (-not $patchText.Contains($fragment))
    {
        throw "Missing radial recovery contract fragment: $fragment"
    }
}

$emptyResponseCalls = ([regex]::Matches($patchText, "sendEmptyObjectMenuResponse\(msg\);")).Count
if ($emptyResponseCalls -lt 3)
{
    throw "Expected empty radial responses for missing targets, holocrons, and missing script objects."
}

Write-Host "Pre-CU radial menu server recovery contract passed."
