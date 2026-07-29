param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$path = Join-Path (Resolve-Path $SourceRoot).Path "dsrc/sku.0/sys.server/compiled/game/script/systems/storyteller/invitation_terminal.java"
$body = Get-Content $path -Raw
$detach = 'detachScript(self, "systems.storyteller.invitation_terminal")'
if (([regex]::Matches($body, [regex]::Escape($detach))).Count -ne 2)
{
    throw "Invitation terminal must detach at attach and initialize."
}
foreach ($method in @("OnAttach", "OnInitialize"))
{
    $match = [regex]::Match($body, "(?s)public int $method\(obj_id self\).*?(?=\r?\n\s*public int|\z)")
    if (-not $match.Success -or -not $match.Value.Contains($detach) -or $match.Value.Contains("messageTo("))
    {
        throw "Invitation terminal lifecycle is not inert: $method"
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content (Join-Path $restorationRoot "contracts/p14-storyteller-invitation-terminal-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or $contract.runtimeEvidence.result -ne "passed")
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($item in @(
        @{ Path = $path; Sha = $contract.buildEvidence.sourceSha256.'invitation_terminal.java'; Bytes = 0 },
        @{ Path = (Join-Path $restorationRoot "patches/dsrc/171-p14-storyteller-invitation-terminal-retirement.patch"); Sha = $contract.buildEvidence.overlayPatchSha256; Bytes = $contract.buildEvidence.overlayPatchBytes }
    ))
    {
        $bytes = [Text.Encoding]::UTF8.GetBytes(([IO.File]::ReadAllText($item.Path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($actual -ne $item.Sha -or ($item.Bytes -gt 0 -and $bytes.Length -ne $item.Bytes))
        {
            throw "Evidence mismatch: $($item.Path)"
        }
    }
}
Write-Host "Publish 14.1 Storyteller invitation-terminal retirement contract passed."
