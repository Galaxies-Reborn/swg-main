param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path $SourceRoot).Path
$files = [ordered]@{
    "yoda_fountain.java" = @{Path="dsrc/sku.0/sys.server/compiled/game/script/event/emperorsday/yoda_fountain.java"; Script="event.emperorsday.yoda_fountain"}
    "emperor_statue.java" = @{Path="dsrc/sku.0/sys.server/compiled/game/script/event/emperorsday/emperor_statue.java"; Script="event.emperorsday.emperor_statue"}
}
foreach ($entry in $files.GetEnumerator())
{
    $body = Get-Content (Join-Path $root $entry.Value.Path) -Raw
    $detach = "detachScript(self, `"$($entry.Value.Script)`")"
    $init = [regex]::Match($body, '(?s)public int OnInitialize\(obj_id self\).*?(?=\r?\n\s*public int)').Value
    $attach = [regex]::Match($body, '(?s)public int OnAttach\(obj_id self\).*?(?=\r?\n\s*public int)').Value
    if (([regex]::Matches($body, [regex]::Escape($detach))).Count -ne 2 -or
        $init.IndexOf("OnDestroy(self);") -lt 0 -or
        $init.IndexOf("OnDestroy(self);") -gt $init.IndexOf($detach) -or
        -not $attach.Contains($detach))
    {
        throw "$($entry.Key) does not clean up before detaching."
    }
    foreach ($forbidden in @("prepareParade", "createObject(MUSIC_", "messageTo(self"))
    {
        if ($init.Contains($forbidden) -or $attach.Contains($forbidden)) { throw "$($entry.Key) lifecycle still starts parade state: $forbidden" }
    }
}
$emperor = Get-Content (Join-Path $root $files["emperor_statue.java"].Path) -Raw
$emperorInit = [regex]::Match($emperor, '(?s)public int OnInitialize\(obj_id self\).*?(?=\r?\n\s*public int)').Value
if (-not $emperorInit.Contains('utils.getObjIdScriptVar(self, "lambdaShuttle")') -or
    -not $emperorInit.Contains('messageTo(lambda, "takeOff"') -or
    -not $emperorInit.Contains('utils.removeScriptVar(self, "lambdaShuttle")'))
{
    throw "Imperial Lambda cleanup is not retained."
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-empire-day-parade-controller-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed" -or -not $contract.expected.trackedDropshipsReleased) { throw "Runtime evidence is not ready." }
    foreach ($entry in $files.GetEnumerator())
    {
        $path = Join-Path $root $entry.Value.Path
        $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key)) { throw "Source evidence mismatch: $($entry.Key)" }
    }
    $patch = Join-Path $restorationRoot "patches/dsrc/175-p14-empire-day-parade-controller-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($patch) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or $actual -ne $contract.buildEvidence.overlayPatchSha256) { throw "Patch evidence mismatch." }
}
Write-Host "Publish 14.1 Empire/Remembrance Day parade-controller retirement contract passed."
