[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot))
{
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$composePath = Join-Path $root "docker-compose.precu.yml"
$entrypointPath = Join-Path $root "docker\entrypoint.sh"

foreach ($path in @($composePath, $entrypointPath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required Pre-CU Docker file is missing: $path"
    }
}

$compose = Get-Content -LiteralPath $composePath -Raw
$entrypoint = Get-Content -LiteralPath $entrypointPath -Raw
$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0

function Assert-NetworkContract
{
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Condition)
    {
        $script:passed++
        Write-Host "  [PASS] $Name"
    }
    else
    {
        $script:failures.Add($Name)
        Write-Host "  [FAIL] $Name"
    }
}

Write-Host "Isolated Pre-CU Docker network checks:"

Assert-NetworkContract `
    -Condition ($compose.Contains('SWG_CENTRAL_LOGIN_SERVICE_PORT: ${SWG_PRECU_CENTRAL_LOGIN_SERVICE_PORT:-44452}')) `
    -Name "precu.network.compose-central-login-service-port"
Assert-NetworkContract `
    -Condition ($compose.Contains('SWG_PUBLIC_CONNECTION_PING_PORT: ${SWG_PRECU_PUBLIC_CONNECTION_PING_PORT:-45462}')) `
    -Name "precu.network.compose-ping-port"
Assert-NetworkContract `
    -Condition ($compose.Contains('SWG_PUBLIC_CONNECTION_PORT: ${SWG_PRECU_PUBLIC_CONNECTION_PORT:-45463}')) `
    -Name "precu.network.compose-public-port"
Assert-NetworkContract `
    -Condition ($compose.Contains('SWG_PRIVATE_CONNECTION_PORT: ${SWG_PRECU_PRIVATE_CONNECTION_PORT:-45464}')) `
    -Name "precu.network.compose-private-port"
Assert-NetworkContract `
    -Condition ($compose.Contains('"45450-45461:44450-44461/tcp"') -and $compose.Contains('"45450-45461:44450-44461/udp"')) `
    -Name "precu.network.login-45453-to-44453"
Assert-NetworkContract `
    -Condition (
        $compose.Contains('"${SWG_PRECU_PUBLIC_CONNECTION_PING_PORT:-45462}:${SWG_PRECU_PUBLIC_CONNECTION_PING_PORT:-45462}/udp"') -and
        $compose.Contains('"${SWG_PRECU_PUBLIC_CONNECTION_PORT:-45463}:${SWG_PRECU_PUBLIC_CONNECTION_PORT:-45463}/udp"') -and
        $compose.Contains('"${SWG_PRECU_PRIVATE_CONNECTION_PORT:-45464}:${SWG_PRECU_PRIVATE_CONNECTION_PORT:-45464}/udp"')
    ) `
    -Name "precu.network.embedded-ports-same-to-same"
Assert-NetworkContract `
    -Condition (-not $compose.Contains('45450-45465:44450-44465')) `
    -Name "precu.network.no-translated-connection-range"
Assert-NetworkContract `
    -Condition ($entrypoint.Contains('pingPort=${SWG_PUBLIC_CONNECTION_PING_PORT}')) `
    -Name "precu.network.runtime-ping-override"
Assert-NetworkContract `
    -Condition ($entrypoint.Contains('clientServicePortPublic=${SWG_PUBLIC_CONNECTION_PORT}')) `
    -Name "precu.network.runtime-public-override"
Assert-NetworkContract `
    -Condition ($entrypoint.Contains('clientServicePortPrivate=${SWG_PRIVATE_CONNECTION_PORT}')) `
    -Name "precu.network.runtime-private-override"
Assert-NetworkContract `
    -Condition ($entrypoint.Contains('SWG_CENTRAL_LOGIN_SERVICE_PORT="${SWG_CENTRAL_LOGIN_SERVICE_PORT:-44452}"')) `
    -Name "precu.network.central-login-service-port-default"
Assert-NetworkContract `
    -Condition ($entrypoint.Contains('for port_name in SWG_CENTRAL_LOGIN_SERVICE_PORT SWG_PUBLIC_CONNECTION_PING_PORT SWG_PUBLIC_CONNECTION_PORT SWG_PRIVATE_CONNECTION_PORT')) `
    -Name "precu.network.all-service-ports-validated"
Assert-NetworkContract `
    -Condition ($entrypoint.Contains('ConnectionServer ping, public, and private ports must be distinct.')) `
    -Name "precu.network.embedded-ports-distinct"
Assert-NetworkContract `
    -Condition (
        $entrypoint.Contains('port_value >= 45450 && port_value <= 45461') -and
        $entrypoint.Contains('port_value == 45465')
    ) `
    -Name "precu.network.embedded-ports-avoid-fixed-host-mappings"
Assert-NetworkContract `
    -Condition (
        $entrypoint.Contains('port = ${SWG_CENTRAL_LOGIN_SERVICE_PORT}') -and
        -not $entrypoint.Contains('port = ${SWG_PUBLIC_CONNECTION_PORT}')
    ) `
    -Name "precu.network.cluster-list-uses-central-login-service-port"
Assert-NetworkContract `
    -Condition (
        $entrypoint.Contains('loginServerPort=${SWG_CENTRAL_LOGIN_SERVICE_PORT}') -and
        $entrypoint.Contains('loginServicePort=${SWG_CENTRAL_LOGIN_SERVICE_PORT}') -and
        $entrypoint.Contains('centralServicePort=${SWG_CENTRAL_LOGIN_SERVICE_PORT}')
    ) `
    -Name "precu.network.runtime-central-login-service-port"

if ($failures.Count -gt 0)
{
    throw "Isolated Pre-CU Docker network contract failed: $($failures -join ', ')"
}

Write-Host ""
Write-Host "Isolated Pre-CU Docker network contract passed ($passed/16)."
