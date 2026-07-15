[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9]+$")]
    [string]$PlayerOid,

    [ValidatePattern("^[A-Za-z0-9_.-]+$")]
    [string]$ContainerName = "swg-precu",

    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 15,

    [switch]$ExerciseSurrender
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$probeScript = "test.precu_phase_a_runtime"
$probeMethod = "executeProbe"
$noviceSkill = "crafting_artisan_novice"
$engineeringSkill = "crafting_artisan_engineering_01"
$xpType = "crafting_general"
$expectedCommand = "private_artisan_engineering_1"
$expectedSkillMod = "general_assembly"
$expectedSkillModDelta = 10
$expectedSchematic = "object/draft_schematic/item/item_clothing_tool.iff"
$contractPath = Join-Path (Split-Path -Parent $PSScriptRoot) "contracts\phase-a.json"
$runtimeContract = (Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json).runtimeVerticalSlice
$expectedEngineeringSkillCost = [int]$runtimeContract.skillPointCost
$expectedPreEngineeringXpCap = [int]$runtimeContract.prerequisiteXpCap
$expectedPostEngineeringXpCap = [int]$runtimeContract.trainedXpCap

function Invoke-Probe
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[A-Za-z0-9_./ -]+$")]
        [string]$Arguments
    )

    $serverCommand = "game tatooine runScript $probeScript $probeMethod $Arguments"
    $bashCommand = "cd /swg-precu/exe/linux && printf '%-1024s' '$serverCommand' | ./bin/ServerConsole -- @servercommon.cfg -s ServerConsole serverAddress=127.0.0.1 serverPort=61000"
    # Windows PowerShell 5 surfaces any native stderr as a non-terminating
    # ErrorRecord.  With this script's fail-closed ErrorActionPreference that
    # turns the container's harmless `mesg: ttyname failed` login-shell notice
    # into a terminating exception before LASTEXITCODE can be inspected.
    # Capture both streams under Continue and make the native exit code the
    # authoritative success boundary; real stderr is retained in the failure.
    $previousErrorActionPreference = $ErrorActionPreference
    try
    {
        $ErrorActionPreference = "Continue"
        $output = @(& docker exec $ContainerName bash -lc $bashCommand 2>&1)
        $dockerExitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($dockerExitCode -ne 0)
    {
        throw "ServerConsole failed with exit code $dockerExitCode`: $($output -join [Environment]::NewLine)"
    }

    $text = ($output -join [Environment]::NewLine).Trim()
    $match = [regex]::Match($text, "(?m)(?:^|\s)(?<result>(?:action|oid|error)=[^\r\n]+)")
    if (-not $match.Success)
    {
        throw "ServerConsole returned no probe result: $text"
    }

    $resultText = $match.Groups["result"].Value.Trim()
    $values = @{}
    foreach ($token in [regex]::Matches($resultText, "(?<key>[A-Za-z][A-Za-z0-9]*)=(?<value>\S+)"))
    {
        $key = $token.Groups["key"].Value
        if ($values.ContainsKey($key))
        {
            throw "ServerConsole returned a duplicate '$key' field: $resultText"
        }
        $values[$key] = $token.Groups["value"].Value
    }
    if ($values.ContainsKey("error"))
    {
        throw "Runtime probe rejected '$Arguments': $resultText"
    }

    [pscustomobject]@{
        Text = $resultText
        Values = $values
    }
}

function Assert-Field
{
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Expected
    )

    if (-not $Result.Values.ContainsKey($Name))
    {
        throw "Probe result is missing '$Name': $($Result.Text)"
    }
    if ([string]$Result.Values[$Name] -cne $Expected)
    {
        throw "Probe field '$Name' was '$($Result.Values[$Name])'; expected '$Expected': $($Result.Text)"
    }
}

function Get-IntegerField
{
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $Result.Values.ContainsKey($Name))
    {
        throw "Probe result is missing '$Name': $($Result.Text)"
    }

    $value = 0
    if (-not [int]::TryParse([string]$Result.Values[$Name], [ref]$value))
    {
        throw "Probe field '$Name' is not an integer: $($Result.Text)"
    }
    return $value
}

function Get-BooleanField
{
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $Result.Values.ContainsKey($Name))
    {
        throw "Probe result is missing '$Name': $($Result.Text)"
    }

    $value = [string]$Result.Values[$Name]
    if ($value -ceq "true")
    {
        return $true
    }
    if ($value -ceq "false")
    {
        return $false
    }
    throw "Probe field '$Name' is not a canonical boolean: $($Result.Text)"
}

function Get-CraftingStateSnapshot
{
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result
    )

    Assert-Field -Result $Result -Name "loaded" -Expected "true"
    Assert-Field -Result $Result -Name "authoritative" -Expected "true"
    Assert-Field -Result $Result -Name "skill" -Expected $engineeringSkill
    Assert-Field -Result $Result -Name "xpType" -Expected $xpType
    Assert-Field -Result $Result -Name "command" -Expected $expectedCommand
    Assert-Field -Result $Result -Name "skillMod" -Expected $expectedSkillMod
    Assert-Field -Result $Result -Name "schematic" -Expected $expectedSchematic

    [pscustomobject]@{
        HasSkill = Get-BooleanField -Result $Result -Name "hasSkill"
        HasCommand = Get-BooleanField -Result $Result -Name "hasCommand"
        HasSchematic = Get-BooleanField -Result $Result -Name "hasSchematic"
        SkillCost = Get-IntegerField -Result $Result -Name "skillCost"
        Points = Get-IntegerField -Result $Result -Name "points"
        Xp = Get-IntegerField -Result $Result -Name "xp"
        Cap = Get-IntegerField -Result $Result -Name "cap"
        SkillModValue = Get-IntegerField -Result $Result -Name "skillModValue"
        Cash = Get-IntegerField -Result $Result -Name "cash"
        Bank = Get-IntegerField -Result $Result -Name "bank"
    }
}

function Assert-CraftingCanaryStateEquals
{
    param(
        [Parameter(Mandatory = $true)]
        [object]$Actual,

        [Parameter(Mandatory = $true)]
        [object]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    foreach ($name in @(
        "HasSkill",
        "HasCommand",
        "HasSchematic",
        "SkillCost",
        "Points",
        "Xp",
        "Cap",
        "SkillModValue",
        "Cash",
        "Bank"
    ))
    {
        if ($Actual.$name -ne $Expected.$name)
        {
            throw "$Context did not restore observed canary '$name': actual=$($Actual.$name) expected=$($Expected.$name)"
        }
    }
}

function Get-AuthoritativeSkillOwnership
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$SkillName
    )

    $status = Invoke-Probe -Arguments "status $PlayerOid $SkillName $xpType"
    Assert-Field -Result $status -Name "authoritative" -Expected "true"
    return Get-BooleanField -Result $status -Name "hasSkill"
}

function Revoke-TemporarySkillIfOwned
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$SkillName
    )

    if (-not (Get-AuthoritativeSkillOwnership -SkillName $SkillName))
    {
        return
    }

    $revoke = Invoke-Probe -Arguments "revoke $PlayerOid $SkillName $lifecycleId"
    Assert-Field -Result $revoke -Name "authoritative" -Expected "true"
    Assert-Field -Result $revoke -Name "hasSkill" -Expected "false"
}

function Clear-AttemptedLifecycleMarker
{
    param([Parameter(Mandatory = $true)] [string]$ExpectedLifecycleId)

    $lastClearError = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++)
    {
        $status = Invoke-Probe -Arguments "craftingStatus $PlayerOid"
        $markerState = [string]$status.Values["lifecycleMarkerState"]
        $attemptId = [string]$status.Values["lifecycleAttemptId"]
        $activeId = [string]$status.Values["lifecycleId"]
        if ($markerState -ceq "none")
        {
            Assert-Field -Result $status -Name "lifecycleAttemptId" -Expected "none"
            Assert-Field -Result $status -Name "lifecycleId" -Expected "none"
            Assert-Field -Result $status -Name "lifecycleBaselineComplete" -Expected "false"
            return
        }
        $ownedPartial = $markerState -ceq "partial" -and
            $attemptId -ceq $ExpectedLifecycleId -and $activeId -ceq "none"
        $ownedComplete = $markerState -ceq "complete" -and
            $attemptId -ceq $ExpectedLifecycleId -and $activeId -ceq $ExpectedLifecycleId
        if (-not $ownedPartial -and -not $ownedComplete)
        {
            throw "Refusing lifecycle recovery for foreign/corrupt marker '$markerState/$attemptId/$activeId'."
        }
        if ($attempt -eq 2)
        {
            $suffix = $(if ($null -ne $lastClearError) { " Last clear error: $($lastClearError.Exception.Message)" } else { "" })
            throw "Exact-owned lifecycle marker remained after authoritative clear retries.$suffix"
        }
        try
        {
            $released = Invoke-Probe -Arguments "clearLifecycle $PlayerOid $ExpectedLifecycleId"
            Assert-Field -Result $released -Name "cleared" -Expected "true"
        }
        catch
        {
            # The response may have been lost after the metadata clear. Never
            # trust the exception or success response; the next status read is
            # the authoritative outcome.
            $lastClearError = $_
        }
    }
}

$initialResult = Invoke-Probe -Arguments "craftingStatus $PlayerOid"
$initialState = Get-CraftingStateSnapshot -Result $initialResult

Write-Host "[PASS] Artisan authoritative status: $($initialResult.Text)"
Assert-Field -Result $initialResult -Name "lifecycleAttemptId" -Expected "none"
Assert-Field -Result $initialResult -Name "lifecycleId" -Expected "none"
Assert-Field -Result $initialResult -Name "lifecycleMarkerState" -Expected "none"
Assert-Field -Result $initialResult -Name "lifecycleBaselineComplete" -Expected "false"
Assert-Field -Result $initialResult -Name "operationAttemptId" -Expected "none"
Assert-Field -Result $initialResult -Name "operationId" -Expected "none"
Assert-Field -Result $initialResult -Name "relogNoncePresent" -Expected "false"
Assert-Field -Result $initialResult -Name "restartNoncePresent" -Expected "false"
if (-not $ExerciseSurrender)
{
    Write-Host "Observation-only smoke passed. Re-run with -ExerciseSurrender to grant a temporary Artisan engineering box and verify production queued surrender."
    exit 0
}

if ($initialState.HasSkill)
{
    throw "Fixture already owns $engineeringSkill; refusing to mutate pre-existing state: $($initialResult.Text)"
}
$noviceStatus = Invoke-Probe -Arguments "status $PlayerOid $noviceSkill $xpType"
Assert-Field -Result $noviceStatus -Name "authoritative" -Expected "true"
$noviceWasOwned = Get-BooleanField -Result $noviceStatus -Name "hasSkill"
$noviceMutationAttempted = $false
$engineeringMutationAttempted = $false
$exerciseFailure = $null
$cleanupFailure = $null
$lifecycleId = [guid]::NewGuid().ToString("N")
$lifecycleAttempted = $false

try
{
    # Record intent before the first lifecycle RPC so response loss and partial
    # establishment are always routed through authoritative marker recovery.
    $lifecycleAttempted = $true
    $begun = Invoke-Probe -Arguments "beginLifecycle $PlayerOid $lifecycleId"
    Assert-Field -Result $begun -Name "established" -Expected "true"
    Assert-Field -Result $begun -Name "lifecycleMarkerState" -Expected "complete"

    if (-not $noviceWasOwned)
    {
        $noviceMutationAttempted = $true
        $grantNovice = Invoke-Probe -Arguments "grant $PlayerOid $noviceSkill $lifecycleId"
        Assert-Field -Result $grantNovice -Name "authoritative" -Expected "true"
        Assert-Field -Result $grantNovice -Name "result" -Expected "true"
        Assert-Field -Result $grantNovice -Name "hasSkill" -Expected "true"
    }

    $beforeEngineeringResult = Invoke-Probe -Arguments "craftingStatus $PlayerOid"
    $beforeEngineeringState = Get-CraftingStateSnapshot -Result $beforeEngineeringResult
    if ($beforeEngineeringState.HasSkill)
    {
        throw "Fixture gained $engineeringSkill before the engineering grant step: $($beforeEngineeringResult.Text)"
    }
    if ($beforeEngineeringState.HasCommand -or $beforeEngineeringState.HasSchematic)
    {
        throw "Fixture already exposes the Engineering I command or selected schematic; refusing an ambiguous lifecycle test: $($beforeEngineeringResult.Text)"
    }
    if ($beforeEngineeringState.Xp -gt $beforeEngineeringState.Cap)
    {
        throw "Fixture crafting XP is already above its pre-test cap; refusing a surrender that could clamp it: $($beforeEngineeringResult.Text)"
    }
    if ($beforeEngineeringState.SkillCost -ne $expectedEngineeringSkillCost)
    {
        throw "Artisan Engineering I runtime skill cost was $($beforeEngineeringState.SkillCost); expected contract value $expectedEngineeringSkillCost`: $($beforeEngineeringResult.Text)"
    }
    if ($beforeEngineeringState.Cap -ne $expectedPreEngineeringXpCap)
    {
        throw "Artisan Engineering I prerequisite XP cap was $($beforeEngineeringState.Cap); expected current canary value $expectedPreEngineeringXpCap`: $($beforeEngineeringResult.Text)"
    }

    $engineeringMutationAttempted = $true
    $grantEngineering = Invoke-Probe -Arguments "grant $PlayerOid $engineeringSkill $lifecycleId"
    Assert-Field -Result $grantEngineering -Name "authoritative" -Expected "true"
    Assert-Field -Result $grantEngineering -Name "result" -Expected "true"
    Assert-Field -Result $grantEngineering -Name "hasSkill" -Expected "true"

    $afterGrantResult = Invoke-Probe -Arguments "craftingStatus $PlayerOid"
    $afterGrantState = Get-CraftingStateSnapshot -Result $afterGrantResult
    if (-not $afterGrantState.HasSkill -or -not $afterGrantState.HasCommand -or -not $afterGrantState.HasSchematic)
    {
        throw "Artisan Engineering I did not expose its skill, command, and concrete schematic: $($afterGrantResult.Text)"
    }
    if ($afterGrantState.SkillModValue -ne ($beforeEngineeringState.SkillModValue + $expectedSkillModDelta))
    {
        throw "Artisan engineering did not add $expectedSkillModDelta ${expectedSkillMod}: $($afterGrantResult.Text)"
    }
    $expectedPointsAfterGrant = $beforeEngineeringState.Points - $beforeEngineeringState.SkillCost
    if ($afterGrantState.Points -ne $expectedPointsAfterGrant)
    {
        throw "Artisan Engineering I did not consume its runtime-probed $($beforeEngineeringState.SkillCost)-point cost: before=$($beforeEngineeringState.Points) after=$($afterGrantState.Points) expected=$expectedPointsAfterGrant`: $($afterGrantResult.Text)"
    }
    if ($afterGrantState.Cap -ne $expectedPostEngineeringXpCap)
    {
        throw "Artisan Engineering I XP cap was $($afterGrantState.Cap) after grant; expected current canary value $expectedPostEngineeringXpCap`: $($afterGrantResult.Text)"
    }
    if ($afterGrantState.Xp -ne $beforeEngineeringState.Xp)
    {
        throw "Administrative Artisan Engineering I grant unexpectedly changed crafting XP: before=$($beforeEngineeringState.Xp) after=$($afterGrantState.Xp)"
    }
    if ($afterGrantState.Cash -ne $beforeEngineeringState.Cash -or
        $afterGrantState.Bank -ne $beforeEngineeringState.Bank)
    {
        throw "Administrative setup unexpectedly changed credits: $($afterGrantResult.Text)"
    }
    Write-Host "[PASS] Artisan skill grant consumed $expectedEngineeringSkillCost points, changed the XP cap from $expectedPreEngineeringXpCap to $expectedPostEngineeringXpCap, and exposed the selected command/mod/schematic canaries."

    $queued = Invoke-Probe -Arguments "queueSurrender $PlayerOid $engineeringSkill $lifecycleId"
    Assert-Field -Result $queued -Name "queued" -Expected "true"
    Assert-Field -Result $queued -Name "verification" -Expected "pending"

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $verified = $null
    do
    {
        Start-Sleep -Milliseconds 250
        $verified = Invoke-Probe -Arguments "verifySurrender $PlayerOid $engineeringSkill $xpType"
        if (Get-BooleanField -Result $verified -Name "surrendered")
        {
            break
        }
    }
    while ([DateTime]::UtcNow -lt $deadline)

    Assert-Field -Result $verified -Name "authoritative" -Expected "true"
    Assert-Field -Result $verified -Name "completion" -Expected "removed"
    Assert-Field -Result $verified -Name "surrendered" -Expected "true"

    $afterSurrenderResult = Invoke-Probe -Arguments "craftingStatus $PlayerOid"
    $afterSurrenderState = Get-CraftingStateSnapshot -Result $afterSurrenderResult
    Assert-CraftingCanaryStateEquals -Actual $afterSurrenderState -Expected $beforeEngineeringState -Context "Post-surrender Artisan state"
    Write-Host "[PASS] Production queued surrender restored all observed Artisan canary fields (ownership, selected command/mod/schematic, points, XP/cap, and credits)."
}
catch
{
    $exerciseFailure = $_
}
finally
{
    if ($engineeringMutationAttempted)
    {
        try
        {
            Revoke-TemporarySkillIfOwned -SkillName $engineeringSkill
        }
        catch
        {
            if ($null -eq $cleanupFailure)
            {
                $cleanupFailure = $_
            }
        }
    }
    if ($noviceMutationAttempted -and -not $noviceWasOwned)
    {
        try
        {
            if (Get-AuthoritativeSkillOwnership -SkillName $engineeringSkill)
            {
                throw "Refusing to revoke temporary $noviceSkill while dependent $engineeringSkill is still authoritatively owned"
            }
            Revoke-TemporarySkillIfOwned -SkillName $noviceSkill
        }
        catch
        {
            if ($null -eq $cleanupFailure)
            {
                $cleanupFailure = $_
            }
        }
    }
}

$restoreFailure = $null
try
{
    $restoredResult = Invoke-Probe -Arguments "craftingStatus $PlayerOid"
    $restoredState = Get-CraftingStateSnapshot -Result $restoredResult
    Assert-CraftingCanaryStateEquals -Actual $restoredState -Expected $initialState -Context "Final Artisan fixture state"

    $restoredNoviceOwned = Get-AuthoritativeSkillOwnership -SkillName $noviceSkill
    if ($restoredNoviceOwned -ne $noviceWasOwned)
    {
        throw "Final novice ownership was '$restoredNoviceOwned'; expected original value '$noviceWasOwned'"
    }
    if ($lifecycleAttempted)
    {
        Clear-AttemptedLifecycleMarker -ExpectedLifecycleId $lifecycleId
        $releasedStatus = Invoke-Probe -Arguments "craftingStatus $PlayerOid"
        Assert-Field -Result $releasedStatus -Name "lifecycleMarkerState" -Expected "none"
        Assert-Field -Result $releasedStatus -Name "lifecycleAttemptId" -Expected "none"
        Assert-Field -Result $releasedStatus -Name "lifecycleId" -Expected "none"
        Assert-Field -Result $releasedStatus -Name "lifecycleBaselineComplete" -Expected "false"
    }
}
catch
{
    $restoreFailure = $_
}

if ($null -ne $exerciseFailure)
{
    $message = "Runtime smoke failed: $($exerciseFailure.Exception.Message)"
    if ($null -ne $cleanupFailure)
    {
        $message += " Cleanup also failed after all authoritative ownership checks were attempted: $($cleanupFailure.Exception.Message)"
    }
    if ($null -ne $restoreFailure)
    {
        $message += " Final observed-canary restoration verification also failed: $($restoreFailure.Exception.Message)"
    }
    throw $message
}
if ($null -ne $cleanupFailure)
{
    $message = "Runtime smoke cleanup failed after all authoritative ownership checks were attempted: $($cleanupFailure.Exception.Message)"
    if ($null -ne $restoreFailure)
    {
        $message += " Final observed-canary restoration verification also failed: $($restoreFailure.Exception.Message)"
    }
    throw $message
}
if ($null -ne $restoreFailure)
{
    throw "Final observed-canary restoration verification failed: $($restoreFailure.Exception.Message)"
}
Write-Host "Phase-A Artisan runtime smoke passed and all observed fixture canary fields were restored."
