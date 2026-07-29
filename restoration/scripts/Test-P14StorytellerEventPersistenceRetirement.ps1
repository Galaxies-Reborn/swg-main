param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$path = Join-Path (Resolve-Path $SourceRoot).Path "dsrc/sku.0/sys.server/compiled/game/script/systems/storyteller/events/anniversary_event_nyms.java"
$body = Get-Content $path -Raw
$detach = 'detachScript(self, "systems.storyteller.events.anniversary_event_nyms")'
$init = [regex]::Match($body, '(?s)public int OnInitialize\(obj_id self\).*?(?=\r?\n\s*public int)').Value
$attach = [regex]::Match($body, '(?s)public int OnAttach\(obj_id self\).*?(?=\r?\n\s*public int)').Value
if (([regex]::Matches($body, [regex]::Escape($detach))).Count -ne 2 -or
    -not $init.Contains('getConfigSetting("GameServer", "deleteEventProps")') -or
    -not $init.Contains("destroyObject(self);") -or
    -not $init.Contains($detach) -or
    -not $attach.Contains($detach))
{
    throw "Event persistence retirement lifecycle is incomplete."
}
foreach ($lifecycle in @($init, $attach))
{
    foreach ($forbidden in @("persistObject(", "handlePersistEventProp", "messageTo("))
    {
        if ($lifecycle.Contains($forbidden)) { throw "Event persistence remains in lifecycle: $forbidden" }
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-storyteller-event-persistence-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or -not $contract.expected.operatorDeleteSwitchRetained)
    {
        throw "Runtime evidence or cleanup boundary is not ready."
    }
    foreach ($item in @(
        @{Path=$path; Sha=$contract.buildEvidence.sourceSha256.'anniversary_event_nyms.java'; Bytes=0},
        @{Path=(Join-Path $restorationRoot "patches/dsrc/173-p14-storyteller-event-persistence-retirement.patch"); Sha=$contract.buildEvidence.overlayPatchSha256; Bytes=$contract.buildEvidence.overlayPatchBytes}
    ))
    {
        $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($item.Path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($actual -ne $item.Sha -or ($item.Bytes -gt 0 -and $bytes.Length -ne $item.Bytes)) { throw "Evidence mismatch: $($item.Path)" }
    }
}
Write-Host "Publish 14.1 Storyteller event-persistence retirement contract passed."
