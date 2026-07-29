[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $restorationRoot "manifest.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$contractPath = Join-Path $restorationRoot ([string]$manifest.contracts.p14TutorialStartup)
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$newbiePath = Join-Path $source ([string]$contract.sourceFile)

if (-not (Test-Path -LiteralPath $newbiePath -PathType Leaf))
{
    throw "Required materialized tutorial script is missing: $newbiePath"
}

$newbie = Get-Content -LiteralPath $newbiePath -Raw
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Condition)
    {
        Write-Host "  [PASS] $Name"
    }
    else
    {
        Write-Host "  [FAIL] $Name"
        $failures.Add($Name)
    }
}

function Get-JavaVoidMethodText
{
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$MethodName
    )

    $signature = "public void $MethodName("
    $start = $Text.IndexOf($signature, [StringComparison]::Ordinal)
    if ($start -lt 0)
    {
        return ""
    }

    $openBrace = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($openBrace -lt 0)
    {
        return ""
    }

    $depth = 0
    for ($index = $openBrace; $index -lt $Text.Length; $index++)
    {
        if ($Text[$index] -eq '{')
        {
            $depth++
        }
        elseif ($Text[$index] -eq '}')
        {
            $depth--
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }

    return ""
}

Write-Host "Publish 14.1 tutorial-startup checks:"
$startupMethod = Get-JavaVoidMethodText -Text $newbie -MethodName ([string]$contract.startup.methodName)
Assert-Contract -Condition ($startupMethod.Length -gt 0) -Name "p14.tutorial.startup-method-present"

foreach ($marker in @($contract.startup.requiredMarkers))
{
    Assert-Contract -Condition ($startupMethod.Contains([string]$marker)) -Name "p14.tutorial.startup-required.$marker"
}

foreach ($marker in @($contract.startup.forbiddenMarkers))
{
    Assert-Contract -Condition (-not $startupMethod.Contains([string]$marker)) -Name "p14.tutorial.startup-absent.$marker"
}

foreach ($marker in @($contract.fileForbiddenMarkers))
{
    Assert-Contract -Condition (-not $newbie.Contains([string]$marker)) -Name "p14.tutorial.file-absent.$marker"
}

foreach ($marker in @($contract.roomProtocolRequiredMarkers))
{
    Assert-Contract -Condition ($newbie.Contains([string]$marker)) -Name "p14.tutorial.room-protocol-retained.$marker"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 tutorial-startup contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Publish 14.1 tutorial-startup contract passed."
