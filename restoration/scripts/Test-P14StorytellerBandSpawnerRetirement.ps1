param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$path = Join-Path (Resolve-Path $SourceRoot).Path "dsrc/sku.0/sys.server/compiled/game/script/systems/storyteller/events/figrin_dan_band_spawner.java"
$body = Get-Content $path -Raw
$detach = 'detachScript(self, "systems.storyteller.events.figrin_dan_band_spawner")'
$init = [regex]::Match($body, '(?s)public int OnInitialize\(obj_id self\).*?(?=\r?\n\s*public int)').Value
$attach = [regex]::Match($body, '(?s)public int OnAttach\(obj_id self\).*?(?=\r?\n\s*public int)').Value
if (([regex]::Matches($body, [regex]::Escape($detach))).Count -ne 2 -or
    $init.IndexOf("destroyTheBand(self);") -lt 0 -or
    $init.IndexOf("destroyTheBand(self);") -gt $init.IndexOf($detach) -or
    -not $attach.Contains($detach))
{
    throw "Band spawner lifecycle does not clean up before detaching."
}
foreach ($lifecycle in @($init, $attach))
{
    foreach ($forbidden in @("spawnFigrinDanBand", "createTriggerVolume", "spawnEveryone", "messageTo("))
    {
        if ($lifecycle.Contains($forbidden)) { throw "Band spawn remains in lifecycle: $forbidden" }
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-storyteller-band-spawner-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed") { throw "Runtime evidence is not ready." }
    foreach ($item in @(
        @{Path=$path; Sha=$contract.buildEvidence.sourceSha256.'figrin_dan_band_spawner.java'; Bytes=0},
        @{Path=(Join-Path $restorationRoot "patches/dsrc/172-p14-storyteller-band-spawner-retirement.patch"); Sha=$contract.buildEvidence.overlayPatchSha256; Bytes=$contract.buildEvidence.overlayPatchBytes}
    ))
    {
        $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($item.Path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($actual -ne $item.Sha -or ($item.Bytes -gt 0 -and $bytes.Length -ne $item.Bytes)) { throw "Evidence mismatch: $($item.Path)" }
    }
}
Write-Host "Publish 14.1 Storyteller band-spawner retirement contract passed."
