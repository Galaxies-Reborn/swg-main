[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$files = [ordered]@{
    "quest_control_device.java" = "dsrc/sku.0/sys.server/compiled/game/script/quest/task/pgc/quest_control_device.java"
    "quest_holocron.java" = "dsrc/sku.0/sys.server/compiled/game/script/quest/task/pgc/quest_holocron.java"
    "credit_item.java" = "dsrc/sku.0/sys.server/compiled/game/script/quest/task/pgc/credit_item.java"
    "chronicles_reward_vendor.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/chronicles_reward_vendor.java"
    "storyteller_vendor_conversation.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/storyteller_vendor.java"
    "fan_faire_pgc_c3po.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/fan_faire_pgc_c3po.java"
    "storyteller_vendor_controller.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/storyteller/storyteller_vendor.java"
}
$text = [ordered]@{}
foreach ($entry in $files.GetEnumerator())
{
    $text[$entry.Key] = Get-Content -LiteralPath (Join-Path $root $entry.Value) -Raw
}
function Get-MethodText([string]$Body, [string]$Signature)
{
    $start = $Body.IndexOf($Signature)
    if ($start -lt 0)
    {
        throw "Method is missing: $Signature"
    }
    $next = $Body.IndexOf("`n    public ", $start + $Signature.Length)
    if ($next -lt 0)
    {
        $next = $Body.Length
    }
    return $Body.Substring($start, $next - $start)
}
$control = $text["quest_control_device.java"]
if ($control.Contains("menuInfo.addRootMenu") -or
    $control.Contains("pgc_quests.setQuestAbandoned"))
{
    throw "PGC control-device menu mutation remains."
}
$credit = $text["credit_item.java"]
foreach ($forbidden in @("mi.addRootMenu", 'money.bankTo("pgc_player_donated_credits"', "destroyObject(self)"))
{
    if ($credit.Contains($forbidden))
    {
        throw "PGC donated-credit mutation remains: $forbidden"
    }
}
if (-not $credit.Contains('detachScript(self, "quest.task.pgc.credit_item")'))
{
    throw "PGC credit item does not detach."
}
$holocron = $text["quest_holocron.java"]
if (([regex]::Matches(
    $holocron,
    [regex]::Escape('detachScript(self, "quest.task.pgc.quest_holocron")'))).Count -ne 2)
{
    throw "PGC holocron does not detach at attach and initialize."
}
foreach ($method in @("public int OnObjectMenuRequest", "public int OnObjectMenuSelect"))
{
    $body = Get-MethodText $holocron $method
    if ($body.IndexOf("return SCRIPT_CONTINUE;") -lt 0 -or
        $body.IndexOf("return SCRIPT_CONTINUE;") -gt $body.IndexOf("/*"))
    {
        throw "PGC holocron menu is not fail closed: $method"
    }
}
foreach ($name in @(
    "chronicles_reward_vendor.java",
    "storyteller_vendor_conversation.java",
    "fan_faire_pgc_c3po.java"
))
{
    $body = $text[$name]
    foreach ($method in @("public int OnInitialize", "public int OnAttach"))
    {
        $section = Get-MethodText $body $method
        if (-not $section.Contains("detachScript(self,"))
        {
            throw "$name does not detach in $method."
        }
    }
    $menu = Get-MethodText $body "public int OnObjectMenuRequest"
    if ($menu.Contains("addRootMenu"))
    {
        throw "$name still exposes a conversation menu."
    }
    $start = Get-MethodText $body "public int OnStartNpcConversation"
    if (-not $start.Contains("return SCRIPT_OVERRIDE;") -or
        ($start.Contains("npcStartConversation(") -and -not $start.Contains("/*")))
    {
        throw "$name can still start a conversation."
    }
}
$controller = $text["storyteller_vendor_controller.java"]
foreach ($method in @(
    "public int msgStorytellerTokenTypeSelected",
    "public int msgStorytellerTokenPurchaseSelected",
    "public int msgStorytellerChargesSelected"
))
{
    $section = Get-MethodText $controller $method
    if ($section.Contains("storyteller."))
    {
        throw "Storyteller vendor callback still mutates state: $method"
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-pgc-holocron-vendor-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $files.GetEnumerator())
    {
        $path = Join-Path $root $entry.Value
        $bytes = [Text.Encoding]::UTF8.GetBytes(
            ([IO.File]::ReadAllText($path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try
        {
            $actual = ([BitConverter]::ToString(
                $sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
        }
        finally
        {
            $sha.Dispose()
        }
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/168-p14-pgc-holocron-vendor-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(
        ([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = ([BitConverter]::ToString(
            $sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha.Dispose()
    }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $hash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 PGC holocron/vendor retirement contract passed."
