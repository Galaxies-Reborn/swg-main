[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9]+$")]
    [string]$PlayerOid,

    [ValidateSet("CycleAll", "Arm", "Status", "Show", "Cleanup")]
    [string]$Mode = "CycleAll",

    [string]$Family,

    [ValidatePattern("^[a-f0-9]{32}$")]
    [string]$Token,

    [ValidatePattern("^[A-Za-z0-9_.-]+$")]
    [string]$ContainerName = "swg-precu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$probeScript = "test.precu_nonstandard_profession_fixture"
$probeMethod = "executeProbe"
$families = @(
    "crafting_shipwright",
    "pilot_imperial_navy",
    "pilot_neutral",
    "pilot_rebel_navy",
    "force_sensitive_combat_prowess",
    "force_sensitive_crafting_mastery",
    "force_sensitive_enhanced_reflexes",
    "force_sensitive_heightened_senses",
    "force_discipline_defender",
    "force_discipline_enhancements",
    "force_discipline_healing",
    "force_discipline_light_saber",
    "force_discipline_powers",
    "force_rank_dark",
    "force_rank_light",
    "force_title_jedi",
    "jedi_dark_side_journeyman",
    "jedi_dark_side_master",
    "jedi_light_side_journeyman",
    "jedi_light_side_master",
    "jedi_padawan"
)

function Invoke-Probe
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("arm", "status", "show", "cleanup")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            "crafting_shipwright",
            "pilot_imperial_navy", "pilot_neutral", "pilot_rebel_navy",
            "force_sensitive_combat_prowess",
            "force_sensitive_crafting_mastery",
            "force_sensitive_enhanced_reflexes",
            "force_sensitive_heightened_senses",
            "force_discipline_defender", "force_discipline_enhancements",
            "force_discipline_healing", "force_discipline_light_saber",
            "force_discipline_powers", "force_rank_dark", "force_rank_light",
            "force_title_jedi", "jedi_dark_side_journeyman",
            "jedi_dark_side_master", "jedi_light_side_journeyman",
            "jedi_light_side_master", "jedi_padawan")]
        [string]$SelectedFamily,

        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[a-f0-9]{32}$")]
        [string]$LifecycleToken
    )

    $arguments = "$Action $PlayerOid $SelectedFamily $LifecycleToken"
    $serverCommand =
        "game tatooine runScript $probeScript $probeMethod $arguments"
    $bashCommand =
        "cd /swg-precu/exe/linux && printf '%-1024s' '$serverCommand' | " +
        "./bin/ServerConsole -- @servercommon.cfg -s ServerConsole " +
        "serverAddress=127.0.0.1 serverPort=61000"
    $previousErrorActionPreference = $ErrorActionPreference
    try
    {
        $ErrorActionPreference = "Continue"
        $output = @(& docker exec $ContainerName bash -lc $bashCommand 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0)
    {
        throw "ServerConsole failed with exit code $exitCode`: $($output -join [Environment]::NewLine)"
    }
    $result = @($output | ForEach-Object { [string]$_ } |
        Where-Object { $_ -match '^(?:action|error|usage):?=' -or $_ -match '^usage:' } |
        Select-Object -Last 1)
    if ($result.Count -ne 1)
    {
        throw "No fixture result for '$arguments': $($output -join [Environment]::NewLine)"
    }
    if ($result[0] -match '^(?:error|usage)')
    {
        throw "Fixture rejected '$arguments': $($result[0])"
    }
    return [string]$result[0]
}

if ($Mode -ne "CycleAll")
{
    if ([string]::IsNullOrWhiteSpace($Family) -or
        [string]::IsNullOrWhiteSpace($Token))
    {
        throw "Family and Token are required for $Mode."
    }
    if ($families -notcontains $Family)
    {
        throw "Family '$Family' is not in the exact nonstandard matrix."
    }
    $action = $Mode.ToLowerInvariant()
    $result = Invoke-Probe -Action $action -SelectedFamily $Family `
        -LifecycleToken $Token
    Write-Host $result
    return
}

$proof = @()
foreach ($currentFamily in $families)
{
    $currentToken = [guid]::NewGuid().ToString("N")
    $armed = $false
    try
    {
        $armResult = Invoke-Probe -Action arm -SelectedFamily $currentFamily `
            -LifecycleToken $currentToken
        if ($armResult -notmatch 'armed=true')
        {
            throw "Arm result was not authoritative: $armResult"
        }
        $armed = $true
        $statusResult = Invoke-Probe -Action status `
            -SelectedFamily $currentFamily -LifecycleToken $currentToken
        if ($statusResult -notmatch 'rootOwned=true' -or
            $statusResult -notmatch 'owned=true' -or
            $statusResult -notmatch 'stateMatched=true' -or
            $statusResult -notmatch 'passed=true')
        {
            throw "Status result was not authoritative: $statusResult"
        }
        $cleanupResult = Invoke-Probe -Action cleanup `
            -SelectedFamily $currentFamily -LifecycleToken $currentToken
        if ($cleanupResult -notmatch 'restored=true' -or
            $cleanupResult -notmatch 'cleared=true')
        {
            throw "Cleanup result was not exact: $cleanupResult"
        }
        $armed = $false
        $proof += [pscustomobject]@{
            family = $currentFamily
            token = $currentToken
            arm = $armResult
            status = $statusResult
            cleanup = $cleanupResult
            result = "passed"
        }
        Write-Host "[PASS] $currentFamily"
    }
    finally
    {
        if ($armed)
        {
            Invoke-Probe -Action cleanup -SelectedFamily $currentFamily `
                -LifecycleToken $currentToken | Write-Host
        }
    }
}

Write-Host "All $($proof.Count) nonstandard profession runtime families passed with exact cleanup."
$proof
