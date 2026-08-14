[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Source", "Build", "Ready")][string]$Expectation = "Source",
    [string]$Container = "swg-precu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$dsrc = Join-Path $root "dsrc"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw |
    ConvertFrom-Json
$contractProperty = $manifest.contracts.psobject.Properties |
    Where-Object { $_.Name -ceq "p14PrecuBurstRunAuthority" }
if ($null -eq $contractProperty)
{
    throw "Burst Run authority is absent from restoration/manifest.json."
}
$contract = Get-Content -LiteralPath (
    Join-Path $restorationRoot ([string]$contractProperty.Value)) -Raw |
    ConvertFrom-Json
$failures = [Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Message)
{
    if ($Condition)
    {
        Write-Host "  [PASS] $Message"
    }
    else
    {
        Write-Host "  [FAIL] $Message"
        $failures.Add($Message)
    }
}

function Get-Sha256([string]$Path)
{
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256([string]$Text)
{
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try
    {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $algorithm.Dispose()
    }
}

function Get-TableRow([string]$Path, [string]$Key)
{
    $lines = Get-Content -LiteralPath $Path
    $header = [string[]]($lines[0] -split "`t", -1)
    $matches = @($lines | Select-Object -Skip 2 | Where-Object {
        $values = [string[]]($_ -split "`t", -1)
        $values.Count -gt 0 -and $values[0] -ceq $Key
    })
    if ($matches.Count -ne 1) { return $null }
    $values = [string[]]($matches[0] -split "`t", -1)
    $map = @{}
    for ($index = 0; $index -lt [Math]::Min($header.Count, $values.Count); ++$index)
    {
        $map[$header[$index]] = $values[$index]
    }
    return [pscustomobject]@{
        Header = $header
        Values = $values
        Row = $map
        Raw = [string]$matches[0]
    }
}

function Get-BracedSurface([string]$Text, [string]$Marker)
{
    $start = $Text.IndexOf($Marker, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $open = $Text.IndexOf("{", $start, [StringComparison]::Ordinal)
    if ($open -lt 0) { return "" }
    $depth = 0
    for ($index = $open; $index -lt $Text.Length; ++$index)
    {
        if ($Text[$index] -eq '{') { ++$depth }
        elseif ($Text[$index] -eq '}')
        {
            --$depth
            if ($depth -eq 0)
            {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    return ""
}

function Test-ExactOrdinalList($Actual, $Expected)
{
    $actualList = [string[]]@($Actual)
    $expectedList = [string[]]@($Expected)
    [Array]::Sort($actualList, [StringComparer]::Ordinal)
    [Array]::Sort($expectedList, [StringComparer]::Ordinal)
    return $actualList.Count -eq $expectedList.Count -and
        ($actualList -join "`n") -ceq ($expectedList -join "`n")
}

function Test-IsoTimestamp([string]$Value)
{
    $parsed = [DateTimeOffset]::MinValue
    return -not [string]::IsNullOrWhiteSpace($Value) -and
        [DateTimeOffset]::TryParse(
            $Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$parsed)
}

function Test-NearlyEqual([double]$Actual, [double]$Expected,
    [double]$Tolerance = 0.001)
{
    return [Math]::Abs($Actual - $Expected) -le $Tolerance
}

function Get-BurstRunCost([double]$GoverningValue, [double]$SkillMod)
{
    $adjusted = 100.0 - (($GoverningValue - 300.0) / 1200.0) * 100.0
    $adjusted = [Math]::Max(0.0, $adjusted)
    $boundedSkillMod = [Math]::Min(100.0, $SkillMod)
    return [int][Math]::Truncate($adjusted * (1.0 - $boundedSkillMod / 100.0))
}

function Get-ExpectedArtifactMap($ClassArtifacts, $DeterministicIff)
{
    $map = [ordered]@{}
    foreach ($artifact in @($ClassArtifacts))
    {
        $map[[string]$artifact.path] = $artifact
    }
    foreach ($property in $DeterministicIff.psobject.Properties)
    {
        $artifact = $property.Value
        $map[[string]$artifact.path] = $artifact
    }
    return $map
}

function Test-ArtifactIdentitySet($Actual, [Collections.IDictionary]$Expected)
{
    $actualList = @($Actual)
    if ($actualList.Count -ne $Expected.Count) { return $false }
    foreach ($path in @($Expected.Keys))
    {
        $matches = @($actualList | Where-Object { [string]$_.path -ceq [string]$path })
        if ($matches.Count -ne 1) { return $false }
        $wanted = $Expected[$path]
        if ([int64]$matches[0].bytes -ne [int64]$wanted.bytes -or
            [string]$matches[0].sha256 -cne [string]$wanted.sha256)
        {
            return $false
        }
    }
    return $true
}

function Test-NineAttributeSnapshot($Snapshot)
{
    $entries = @($Snapshot)
    $expectedNames = @("health", "strength", "constitution", "action",
        "quickness", "stamina", "mind", "focus", "willpower")
    if ($entries.Count -ne $expectedNames.Count) { return $false }
    foreach ($name in $expectedNames)
    {
        $matches = @($entries | Where-Object { [string]$_.name -ceq $name })
        if ($matches.Count -ne 1 -or [int]$matches[0].current -lt 0 -or
            [int]$matches[0].maximum -le 0 -or
            [int]$matches[0].current -gt [int]$matches[0].maximum)
        {
            return $false
        }
    }
    return $true
}

function Test-Sha256Fingerprint([string]$Value)
{
    return $Value -cmatch '^[0-9a-f]{64}$'
}

function Test-JsonExact($Left, $Right)
{
    return ($Left | ConvertTo-Json -Depth 8 -Compress) -ceq
        ($Right | ConvertTo-Json -Depth 8 -Compress)
}

function Test-CommitInputParity([string]$EvidenceCommit, [string]$CurrentCommit,
    [string[]]$RelativePaths)
{
    if ($EvidenceCommit -cnotmatch '^[0-9a-f]{40}$' -or
        $CurrentCommit -cnotmatch '^[0-9a-f]{40}$')
    {
        return $false
    }
    $type = (& git -C $dsrc cat-file -t $EvidenceCommit 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $type -cne "commit") { return $false }
    & git -C $dsrc merge-base --is-ancestor $EvidenceCommit $CurrentCommit
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($path in $RelativePaths)
    {
        $evidenceBlob = (& git -C $dsrc rev-parse "${EvidenceCommit}:$path" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $evidenceBlob -cnotmatch '^[0-9a-f]{40}$') { return $false }
        $currentBlob = (& git -C $dsrc rev-parse "${CurrentCommit}:$path" 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $currentBlob -cne $evidenceBlob) { return $false }
    }
    return $true
}

Write-Host "Verifying the immutable universal PRE-CU Burst Run source owner..."
$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $path = Join-Path $root ([string]$property.Value)
    $paths[[string]$property.Name] = $path
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "p14.burst-run.source.$($property.Name)"
}
if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Burst Run contract failed: $($failures -join ', ')"
}

# The direct commit and all changed-file hashes are deliberately mandatory.
# A pending token therefore fails closed until the dsrc commit is immutable.
$expectedCommit = [string]$contract.buildEvidence.directSourceCommit
$pinReady = $expectedCommit -cmatch '^[0-9a-f]{40}$'
Assert-Contract $pinReady "p14.burst-run.pin.full-immutable-dsrc-sha"
$dsrcPins = @($manifest.gitlinks | Where-Object { [string]$_.name -ceq "dsrc" })
Assert-Contract ($pinReady -and $dsrcPins.Count -eq 1 -and
    [string]$dsrcPins[0].commit -ceq $expectedCommit) `
    "p14.burst-run.pin.manifest-parity"
$actualCommit = (& git -C $dsrc rev-parse HEAD 2>&1 | Out-String).Trim()
Assert-Contract ($pinReady -and $LASTEXITCODE -eq 0 -and
    $actualCommit -ceq $expectedCommit) "p14.burst-run.pin.checked-out-parity"
# command_table.tab is shared with the independently authenticated ITV
# restoration.  Its complete current hash and the exact Burst Run row are
# validated below; require cleanliness only for Burst Run's implementation
# sources so an unrelated, reviewed command-row edit cannot invalidate this
# feature owner.
$burstRunRelativePaths = @($contract.sourceFiles.psobject.Properties |
    Where-Object { $_.Name -cne "commandTable" } |
    ForEach-Object { ([string]$_.Value).Substring("dsrc/".Length) })
$null = & git -C $dsrc diff --quiet -- @burstRunRelativePaths
$ownedWorktreeClean = $LASTEXITCODE -eq 0
$null = & git -C $dsrc diff --cached --quiet -- @burstRunRelativePaths
$ownedIndexClean = $LASTEXITCODE -eq 0
Assert-Contract ($ownedWorktreeClean -and $ownedIndexClean) `
    "p14.burst-run.pin.clean-owned-implementation-worktree"
if ($pinReady)
{
    $implementationCommit = [string]$contract.buildEvidence.implementationCommit
    $commitFiles = @(& git -C $dsrc show --format= --name-only $implementationCommit 2>&1 |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $commandTableRelativePath = ([string]$contract.sourceFiles.commandTable).Substring("dsrc/".Length)
    $immutableImplementationPaths = @($contract.expected.directSourceChangedFiles |
        Where-Object { [string]$_ -cne $commandTableRelativePath })
    Assert-Contract ($LASTEXITCODE -eq 0 -and
        # command_table.tab is now also shared by the reviewed Royal ITV
        # admission row.  Its exact Burst Run row is authenticated below;
        # retain blob parity for the three exclusively owned inputs.
        (Test-CommitInputParity $implementationCommit $expectedCommit $immutableImplementationPaths) -and
        (Test-ExactOrdinalList $commitFiles @($contract.expected.directSourceChangedFiles))) `
        "p14.burst-run.pin.exact-four-file-owner"
}

$sourceKeys = @($contract.sourceFiles.psobject.Properties.Name)
$hashKeys = @($contract.buildEvidence.sourceSha256.psobject.Properties.Name)
Assert-Contract (Test-ExactOrdinalList $sourceKeys $hashKeys) `
    "p14.burst-run.hash.key-parity"
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $key = [string]$property.Name
    $expectedHash = [string]$contract.buildEvidence.sourceSha256.$key
    $hashReady = $expectedHash -cmatch '^[0-9a-f]{64}$'
    Assert-Contract $hashReady "p14.burst-run.hash.$key.pinned"
    Assert-Contract ($hashReady -and (Get-Sha256 $paths[$key]) -ceq $expectedHash) `
        "p14.burst-run.hash.$key.exact"
}

$command = Get-TableRow $paths.commandTable "burstRun"
Assert-Contract ($null -ne $command) "p14.burst-run.command.unique"
Assert-Contract (((Get-Content -LiteralPath $paths.commandTable).Count - 2) -eq
    [int]$contract.expected.command.tableRows) `
    "p14.burst-run.command.server-table-row-count"
if ($null -ne $command)
{
    Assert-Contract ($command.Header.Count -eq [int]$contract.expected.command.columns -and
        $command.Values.Count -eq [int]$contract.expected.command.columns) `
        "p14.burst-run.command.full-94-column-bridge"
    Assert-Contract ([Text.Encoding]::UTF8.GetByteCount($command.Raw) -eq
        [int]$contract.expected.command.rawRowBytes -and
        (Get-TextSha256 $command.Raw) -ceq [string]$contract.expected.command.rawRowSha256) `
        "p14.burst-run.command.exact-full-row"
    foreach ($key in @("characterAbility", "defaultPriority", "scriptHook",
        "defaultTime", "target", "targetType", "visible", "disabled",
        "addToCombatQueue", "validWeapon", "invalidWeapon", "warmupTime",
        "executeTime", "cooldownTime", "toolbarOnly", "fromServerOnly"))
    {
        Assert-Contract ([string]$command.Row[$key] -ceq
            [string]$contract.expected.command.$key) "p14.burst-run.command.$key"
    }
    Assert-Contract ($command.Row.'L:standing' -ceq "1" -and
        $command.Row.'L:walking' -ceq "1" -and
        $command.Row.'L:running' -ceq "1" -and
        $command.Row.'L:sneaking' -ceq "0" -and
        $command.Row.'L:ridingCreature' -ceq "0" -and
        $command.Row.'L:incapacitated' -ceq "0" -and
        $command.Row.'L:dead' -ceq "0") "p14.burst-run.command.locomotion-mask"
    Assert-Contract ($command.Row.'S:combat' -ceq "1" -and
        $command.Row.'S:peace' -ceq "1" -and
        $command.Row.'S:alert' -ceq "0" -and
        $command.Row.'S:feignDeath' -ceq "0" -and
        $command.Row.'S:dizzy' -ceq "0" -and
        $command.Row.'S:immobilized' -ceq "0" -and
        $command.Row.'S:ridingMount' -ceq "0" -and
        $command.Row.'S:pilotingShip' -ceq "0") "p14.burst-run.command.publish14-state-mask"
}

$skillLines = Get-Content -LiteralPath $paths.skillTable
$skillHeader = [string[]]($skillLines[0] -split "`t", -1)
$commandsIndex = [Array]::IndexOf($skillHeader, "COMMANDS")
$skillGrants = @()
if ($commandsIndex -ge 0)
{
    $skillGrants = @($skillLines | Select-Object -Skip 2 | Where-Object {
        $values = [string[]]($_ -split "`t", -1)
        if ($values.Count -le $commandsIndex) { return $false }
        $commands = ([string]$values[$commandsIndex]).Trim('"') -split ','
        return @($commands | Where-Object { $_ -ceq "burstRun" }).Count -gt 0
    })
}
Assert-Contract ($commandsIndex -ge 0 -and $skillGrants.Count -eq 0) `
    "p14.burst-run.universal.no-skill-box-grant"

$buff = Get-TableRow $paths.buffTable "burstRun"
Assert-Contract ($null -ne $buff) "p14.burst-run.buff.unique"
Assert-Contract (((Get-Content -LiteralPath $paths.buffTable).Count - 2) -eq
    [int]$contract.expected.buff.tableRows) `
    "p14.burst-run.buff.server-table-row-count"
if ($null -ne $buff)
{
    Assert-Contract ($buff.Header.Count -eq [int]$contract.expected.buff.columns -and
        $buff.Values.Count -eq [int]$contract.expected.buff.columns -and
        [Text.Encoding]::UTF8.GetByteCount($buff.Raw) -eq [int]$contract.expected.buff.rawRowBytes -and
        (Get-TextSha256 $buff.Raw) -ceq [string]$contract.expected.buff.rawRowSha256) `
        "p14.burst-run.buff.exact-full-row"
    Assert-Contract ($buff.Row.DURATION -ceq [string]$contract.expected.buff.duration -and
        $buff.Row.EFFECT1_PARAM -ceq [string]$contract.expected.buff.effect -and
        $buff.Row.EFFECT1_VALUE -ceq [string]$contract.expected.buff.value -and
        $buff.Row.CALLBACK -ceq [string]$contract.expected.buff.callback) `
        "p14.burst-run.buff.duration-movement-callback"
    Assert-Contract ($buff.Row.VISIBLE -ceq [string]$contract.expected.buff.visible -and
        $buff.Row.DEBUFF -ceq [string]$contract.expected.buff.debuff -and
        $buff.Row.REMOVE_ON_DEATH -ceq [string]$contract.expected.buff.removeOnDeath -and
        $buff.Row.PLAYER_REMOVABLE -ceq [string]$contract.expected.buff.playerRemovable -and
        $buff.Row.IS_PERSISTENT -ceq [string]$contract.expected.buff.persistent -and
        $buff.Row.DECAY_ON_PVP_DEATH -ceq [string]$contract.expected.buff.decayOnPvpDeath -and
        $buff.Row.PARTICLE -ceq "" -and $buff.Row.PARTICLE_HARDPOINT -ceq "") `
        "p14.burst-run.buff.persistence-removal-and-no-particle"
}

$movement = Get-TableRow $paths.movementTable "burstRun"
Assert-Contract ($null -ne $movement -and
    [Text.Encoding]::UTF8.GetByteCount($movement.Raw) -eq
        [int]$contract.expected.authoredMovement.rawRowBytes -and
    (Get-TextSha256 $movement.Raw) -ceq
        [string]$contract.expected.authoredMovement.rawRowSha256 -and
    $movement.Row.type -ceq [string]$contract.expected.authoredMovement.type -and
    $movement.Row.strength -ceq [string]$contract.expected.authoredMovement.strength -and
    $movement.Row.affects_onfoot -ceq "" -and
    $movement.Row.affects_vehicle -ceq "" -and
    $movement.Row.affects_mount -ceq "") `
    "p14.burst-run.movement.authored-75-and-blank-affects-boundary"

$player = Get-Content -LiteralPath $paths.basePlayer -Raw
$handler = Get-BracedSurface $player "public int burstRun("
$cost = Get-BracedSurface $player "private int calculatePrecuBurstRunCost("
$conflict = Get-BracedSurface $player "private boolean hasPrecuBurstRunConflict("
$remove = Get-BracedSurface $player "public int removeBurstRun("
$expiry = Get-BracedSurface $player "public int handlePrecuBurstRunExpiry("
$ready = Get-BracedSurface $player "public int handlePrecuBurstRunReady("
$restore = Get-BracedSurface $player "private void restorePrecuBurstRunState("
$login = Get-BracedSurface $player "public int OnLogin("
$posture = Get-BracedSurface $player "public int OnChangedPosture("
$mountState = Get-BracedSurface $player "public int handlePrecuBurstRunMountState("
$mountSchedule = Get-BracedSurface $player "private void schedulePrecuBurstRunMountState("
$handlerCompact = $handler -replace '\s+', ''
$costCompact = $cost -replace '\s+', ''

Assert-Contract ($handler.Length -gt 0 -and $cost.Length -gt 0 -and
    $conflict.Length -gt 0 -and $remove.Length -gt 0 -and
    $expiry.Length -gt 0 -and $ready.Length -gt 0 -and
    $restore.Length -gt 0) "p14.burst-run.production.complete-handler-surface"
Assert-Contract ($player.Contains("PRECU_BURST_RUN_BASE_COST = 100") -and
    $player.Contains("PRECU_BURST_RUN_DURATION_SECONDS = 30") -and
    $player.Contains("PRECU_BURST_RUN_RECOVERY_SECONDS = 300") -and
    $player.Contains("PRECU_BURST_RUN_SPEED_STRENGTH = 82.2f") -and
    $player.Contains("PRECU_BURST_RUN_ACCEL_MULTIPLIER = 1.822f")) `
    "p14.burst-run.production.exact-constants"
Assert-Contract (-not $handler.Contains("hasSkill(") -and
    -not $handler.Contains("hasCommand(") -and
    $handler.Contains('getSkillStatisticModifier(self, "burst_run")')) `
    "p14.burst-run.production.universal-skillmod-only"
Assert-Contract ($handler.Contains("getMountId(self)") -and
    $handler.Contains("STATE_RIDING_MOUNT") -and
    $handler.Contains('new string_id("cbt_spam", "no_burst")') -and
    $handler.Contains('"dungeon1".equals(playerLocation.area)') -and
    $handler.Contains('"burst_run_space_dungeon"')) `
    "p14.burst-run.production.mount-and-dungeon-gates"
foreach ($name in @($contract.expected.conflicts))
{
    Assert-Contract ($conflict.Contains('"' + [string]$name + '"') -or
        ([string]$name -ceq "retreat" -and $conflict.Contains("PRECU_RETREAT_MODIFIER")) -or
        ([string]$name -ceq "burstRun" -and $conflict.Contains("PRECU_BURST_RUN_BUFF"))) `
        "p14.burst-run.production.conflict.$name"
}
Assert-Contract ($handlerCompact.Contains('floatskillMod=Math.min(100.0f,getSkillStatisticModifier(self,"burst_run"));') -and
    $handlerCompact.Contains('calculatePrecuBurstRunCost(getAttrib(self,STRENGTH),skillMod)') -and
    $handlerCompact.Contains('calculatePrecuBurstRunCost(getAttrib(self,QUICKNESS),skillMod)') -and
    $handlerCompact.Contains('calculatePrecuBurstRunCost(getAttrib(self,FOCUS),skillMod)')) `
    "p14.burst-run.production.strength-quickness-focus-routing"
Assert-Contract ($costCompact.Contains('adjustedCost-=((governingValue-300.0f)/1200.0f)*adjustedCost;') -and
    $costCompact.Contains('adjustedCost=Math.max(0.0f,adjustedCost);') -and
    $costCompact.Contains('return(int)(adjustedCost*(1.0f-skillMod/100.0f));')) `
    "p14.burst-run.production.exact-cost-formula-cast-last"
Assert-Contract ($handlerCompact.Contains('getAttrib(self,HEALTH)<=healthCost') -and
    $handlerCompact.Contains('getAttrib(self,ACTION)<=actionCost') -and
    $handlerCompact.Contains('getAttrib(self,MIND)<=mindCost') -and
    ([regex]::Matches($handlerCompact,
        'drainCombatAttributes\(self,healthCost,actionCost,mindCost\)').Count -eq 1)) `
    "p14.burst-run.production.strict-affordability-atomic-three-pool-drain"
Assert-Contract ($handlerCompact.Contains('buff.applyBuff(self,self,PRECU_BURST_RUN_BUFF,PRECU_BURST_RUN_DURATION_SECONDS,PRECU_BURST_RUN_SPEED_STRENGTH)') -and
    $handlerCompact.Contains('setAccelPercent(self,baseAcceleration*PRECU_BURST_RUN_ACCEL_MULTIPLIER)') -and
    $handlerCompact.Contains('intcooldownUntil=expiresAt+PRECU_BURST_RUN_RECOVERY_SECONDS;')) `
    "p14.burst-run.production.30-plus-300-movement-lifecycle"
Assert-Contract ($handler.Contains('"burstrun_start_single"') -and
    $handler.Contains('"burstrun_start"') -and
    ($handlerCompact.Contains('newstring_id("cbt_spam","burstrun_start"),true,false,true)'))) `
    "p14.burst-run.production.start-feedback"
Assert-Contract ($remove.Contains('"burstrun_stop_single"') -and
    $remove.Contains('"burstrun_stop"') -and
    -not $remove.Contains("PRECU_BURST_RUN_COOLDOWN_UNTIL") -and
    $ready.Contains('"burst_run_not_tired"')) `
    "p14.burst-run.production.stop-feedback-retains-cooldown"
Assert-Contract ($login.Contains("restorePrecuBurstRunState(self)") -and
    $restore.Contains("schedulePrecuBurstRunExpiry") -and
    $restore.Contains("schedulePrecuBurstRunReady") -and
    $restore.Contains("PRECU_BURST_RUN_EFFECT_ROOT") -and
    $restore.Contains("PRECU_BURST_RUN_COOLDOWN_UNTIL")) `
    "p14.burst-run.production.relog-effect-and-recovery-persistence"
Assert-Contract ($mountState.Contains("accelerationSuspended") -and
    $mountState.Contains("mountPollVersion") -and
    $mountSchedule.Contains("PRECU_BURST_RUN_MOUNT_POLL_SECONDS") -and
    $restore.Contains("schedulePrecuBurstRunMountState")) `
    "p14.burst-run.production.mount-transition-acceleration-safety"
Assert-Contract ($posture.Contains("POSTURE_KNOCKED_DOWN") -and
    $posture.Contains("buff.removeBuff(self, PRECU_BURST_RUN_BUFF)")) `
    "p14.burst-run.production.posture-callback-cleanup"

$combat = Get-Content -LiteralPath $paths.combatBase -Raw
$postureDown = Get-BracedSurface $combat "public int applyPrecuPostureDown("
$knockdown = Get-BracedSurface $combat "public int applyPrecuKnockdown("
Assert-Contract ($postureDown.Contains('"APPLIED"') -and
    $postureDown.Contains('buff.removeBuff(defender, "burstRun")') -and
    $postureDown.Contains('buff.removeBuff(defender, "retreat")')) `
    "p14.burst-run.combat-base.applied-posture-down-cleanup"
Assert-Contract ($knockdown.Contains('"APPLIED"') -and
    $knockdown.Contains('buff.removeBuff(defender, "burstRun")') -and
    $knockdown.Contains('buff.removeBuff(defender, "retreat")')) `
    "p14.burst-run.combat-base.applied-knockdown-cleanup"

$payload = $contract.liveAcceptancePayload
Assert-Contract ([string]$payload.id -ceq
    "p14-burst-run-single-player-reversible-v1" -and
    [bool]$payload.identityBound -and -not [bool]$payload.skillMutationAllowed -and
    [int]$payload.boundedSeconds -le 360 -and @($payload.steps).Count -eq 5 -and
    (Test-ExactOrdinalList @($payload.cleanup.ownedStateOnly) @(
        "buff:burstRun", "objvar:precu.burstRun.effect",
        "objvar:precu.burstRun.cooldownUntil"))) `
    "p14.burst-run.live.single-bounded-reversible-payload"
if ([string]$contract.status -cne "ready")
{
    Assert-Contract ([string]$contract.status -cmatch 'live-pending$' -and
        [string]$contract.liveEvidence.result -ceq "pending" -and
        [string]$payload.result -ceq "pending" -and
        [string]$payload.cleanup.result -ceq "pending" -and
        @($contract.requiredBeforeReady).Count -eq 1) `
        "p14.burst-run.live.ready-remains-pending"
}
$java8Preflight = $contract.buildEvidence.java8Preflight
$requiredClassPaths = @(
    "sku.0/sys.server/compiled/game/script/player/base/base_player.class",
    "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.class"
)
$java8PreflightPaths = @($java8Preflight.artifacts | ForEach-Object {
    [string]$_.path
})
$javaInputPaths = @(
    ([string]$contract.sourceFiles.basePlayer).Substring("dsrc/".Length),
    ([string]$contract.sourceFiles.combatBase).Substring("dsrc/".Length)
)
Assert-Contract ([string]$java8Preflight.result -ceq "passed" -and
    (Test-CommitInputParity ([string]$java8Preflight.sourceCommit) $expectedCommit $javaInputPaths) -and
    [int]$java8Preflight.classMajorVersion -eq 52 -and
    @($java8Preflight.artifacts).Count -eq 2 -and
    (Test-ExactOrdinalList $java8PreflightPaths $requiredClassPaths) -and
    @($java8Preflight.artifacts | Where-Object {
        [int64]$_.bytes -le 0 -or
        [string]$_.sha256 -cnotmatch '^[0-9a-f]{64}$'
    }).Count -eq 0) "p14.burst-run.build.java8-preflight"
$compiledArtifactPaths = @($contract.buildEvidence.requiredCompiledArtifacts)
$preflightArtifactMap = Get-ExpectedArtifactMap `
    -ClassArtifacts @($java8Preflight.artifacts) `
    -DeterministicIff $contract.buildEvidence.deterministicIff
Assert-Contract (Test-ExactOrdinalList $compiledArtifactPaths @($preflightArtifactMap.Keys)) `
    "p14.burst-run.build.required-artifact-identity-parity"
$movementIff = $contract.buildEvidence.deterministicIff.movementTable
Assert-Contract ([string]$movementIff.path -ceq
        "sku.0/sys.server/compiled/game/datatables/movement/movement.iff" -and
    [int64]$movementIff.bytes -eq 8892 -and
    [string]$movementIff.sha256 -ceq
        "cfcac24a10339582859c21144115603550cc80f9e7b9e6019321e1f76667cfd0") `
    "p14.burst-run.build.movement-iff-exact-identity"

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Burst Run contract failed: $($failures -join ', ')"
}

if ($Expectation -in @("Build", "Ready"))
{
    $commandIff = $contract.buildEvidence.deterministicIff.commandTable
    $buffIff = $contract.buildEvidence.deterministicIff.buffTable
    $movementIff = $contract.buildEvidence.deterministicIff.movementTable
    foreach ($value in @([string]$commandIff.sha256,
        [string]$buffIff.sha256, [string]$movementIff.sha256))
    {
        if ($value -cnotmatch '^[0-9a-f]{64}$') { throw "Invalid Burst Run server IFF SHA-256 contract value." }
    }
    $canonical = $contract.buildEvidence.canonicalBuild
    $currentParentCommit = (& git -C $root rev-parse HEAD 2>&1 | Out-String).Trim()
    $currentParentResolved = $LASTEXITCODE -eq 0 -and
        $currentParentCommit -cmatch '^[0-9a-f]{40}$'
    $recordedDeploymentCommit =
        [string]$contract.buildEvidence.deploymentParentCommit
    $canonicalDeploymentCommit =
        [string]$canonical.deploymentParentCommit
    $recordedDeploymentCommitReady =
        $recordedDeploymentCommit -cmatch '^[0-9a-f]{40}$' -and
        $canonicalDeploymentCommit -ceq $recordedDeploymentCommit
    $recordedDeploymentCommitExists = $false
    $recordedDeploymentIsAncestor = $false
    if ($currentParentResolved -and $recordedDeploymentCommitReady)
    {
        $recordedDeploymentType = (& git -C $root cat-file -t `
            $recordedDeploymentCommit 2>&1 | Out-String).Trim()
        $recordedDeploymentCommitExists = $LASTEXITCODE -eq 0 -and
            $recordedDeploymentType -ceq "commit"
        if ($recordedDeploymentCommitExists)
        {
            & git -C $root merge-base --is-ancestor `
                $recordedDeploymentCommit $currentParentCommit
            $recordedDeploymentIsAncestor = $LASTEXITCODE -eq 0
        }
    }
    $canonicalClassArtifacts = @($canonical.freshClassBytecode.artifacts)
    $canonicalClassPaths = @($canonicalClassArtifacts | ForEach-Object {
        [string]$_.path
    })
    $canonicalClassSchemaValid = $canonicalClassArtifacts.Count -eq 2 -and
        (Test-ExactOrdinalList $canonicalClassPaths $requiredClassPaths) -and
        @($canonicalClassArtifacts | Where-Object {
            [int64]$_.bytes -le 0 -or
            [string]$_.sha256 -cnotmatch '^[0-9a-f]{64}$'
        }).Count -eq 0
    $expectedArtifactMap = Get-ExpectedArtifactMap `
        -ClassArtifacts $canonicalClassArtifacts `
        -DeterministicIff $contract.buildEvidence.deterministicIff
    $iffExpectedMap = [ordered]@{}
    foreach ($property in $contract.buildEvidence.deterministicIff.psobject.Properties)
    {
        $artifact = $property.Value
        $iffExpectedMap[[string]$artifact.path] = $artifact
    }
    $canonicalIffIdentityExact = Test-ArtifactIdentitySet `
        -Actual @($canonical.deterministicIffRecompile.artifacts) `
        -Expected $iffExpectedMap
    $canonicalInputPaths = @(
        ([string]$contract.sourceFiles.commandTable).Substring("dsrc/".Length),
        ([string]$contract.sourceFiles.buffTable).Substring("dsrc/".Length),
        ([string]$contract.sourceFiles.movementTable).Substring("dsrc/".Length),
        ([string]$contract.sourceFiles.basePlayer).Substring("dsrc/".Length),
        ([string]$contract.sourceFiles.combatBase).Substring("dsrc/".Length)
    )
    Assert-Contract ($currentParentResolved -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$canonical.result -ceq "passed" -and
        $recordedDeploymentCommitReady -and
        $recordedDeploymentCommitExists -and
        $recordedDeploymentIsAncestor -and
        (Test-CommitInputParity ([string]$canonical.sourceCommit) $expectedCommit $canonicalInputPaths) -and
        [string]$canonical.mode -ceq "canonical-no-skip-build" -and
        [bool]$canonical.skipBuild -eq $false -and
        (Test-IsoTimestamp ([string]$canonical.completedAt)) -and
        [string]$canonical.container -ceq $Container) `
        "p14.burst-run.build.recorded-parent-and-canonical-no-skip-owner"
    Assert-Contract ([string]$canonical.zeroClassDependencyClean.result -ceq "passed" -and
        [int]$canonical.zeroClassDependencyClean.classCountBeforeDelete -gt 0 -and
        [int]$canonical.zeroClassDependencyClean.classCountAfterDelete -eq 0 -and
        [int]$canonical.zeroClassDependencyClean.rebuiltClassCount -gt 0 -and
        [string]$canonical.sourceWorkParity.result -ceq "passed" -and
        [int]$canonical.sourceWorkParity.checkedFiles -eq 5 -and
        [int]$canonical.sourceWorkParity.matchedFiles -eq 5 -and
        [string]$canonical.freshClassBytecode.result -ceq "passed" -and
        [int]$canonical.freshClassBytecode.classMajorVersion -eq 55 -and
        $canonicalClassSchemaValid -and
        [string]$canonical.deterministicIffRecompile.result -ceq "passed" -and
        $canonicalIffIdentityExact -and
        [string]$canonical.artifactProbe.result -ceq "passed" -and
        (Test-IsoTimestamp ([string]$canonical.artifactProbe.capturedAt))) `
        "p14.burst-run.build.exact-zero-class-parity-class-and-iff-evidence"
    $baseClassEvidence = @($canonicalClassArtifacts | Where-Object {
        [string]$_.path -ceq
            "sku.0/sys.server/compiled/game/script/player/base/base_player.class"
    })
    $combatClassEvidence = @($canonicalClassArtifacts | Where-Object {
        [string]$_.path -ceq
            "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.class"
    })
    if ($baseClassEvidence.Count -ne 1 -or $combatClassEvidence.Count -ne 1)
    {
        throw "Burst Run canonical class evidence must identify each exact required class once."
    }
    $probe = @'
set -eu
test "${SWG_SOURCE_DIR:-}" = "/swg-precu-source"
test "${SWG_WORK_DIR:-}" = "/swg-precu"
source_root="$SWG_SOURCE_DIR/dsrc"
work_root="$SWG_WORK_DIR/dsrc"
class_root="$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game"
for relative in \
  sku.0/sys.server/compiled/game/script/player/base/base_player.java \
  sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java \
  sku.0/sys.server/compiled/game/datatables/movement/movement.tab \
  sku.0/sys.shared/compiled/game/datatables/command/command_table.tab \
  sku.0/sys.shared/compiled/game/datatables/buff/buff.tab
do
  cmp -s "$source_root/$relative" "$work_root/$relative"
done
awk -F '\t' '$1 == "burstRun" {
  found++
  if ($2 != "boost" || $3 != 75 || $4 != "" || $5 != "" || $6 != "") exit 2
} END { if (found != 1) exit 3 }' \
  "$work_root/sku.0/sys.server/compiled/game/datatables/movement/movement.tab"
base_source="$work_root/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
combat_source="$work_root/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
base_class="$class_root/script/player/base/base_player.class"
combat_class="$class_root/script/systems/combat/combat_base.class"
test -s "$base_class"
test -s "$combat_class"
test ! "$base_class" -ot "$base_source"
test ! "$combat_class" -ot "$combat_source"
test "$(stat -Lc '%s' "$base_class")" -eq __BASE_CLASS_BYTES__
test "$(sha256sum "$base_class" | awk '{print $1}')" = "__BASE_CLASS_SHA__"
test "$(od -An -tu1 -j6 -N2 "$base_class" | awk '{print $1 * 256 + $2}')" -eq __CLASS_MAJOR__
test "$(stat -Lc '%s' "$combat_class")" -eq __COMBAT_CLASS_BYTES__
test "$(sha256sum "$combat_class" | awk '{print $1}')" = "__COMBAT_CLASS_SHA__"
test "$(od -An -tu1 -j6 -N2 "$combat_class" | awk '{print $1 * 256 + $2}')" -eq __CLASS_MAJOR__
base_signatures="$(javap -classpath "$class_root" -p script.player.base.base_player)"
printf '%s\n' "$base_signatures" | grep -Fq ' int burstRun('
printf '%s\n' "$base_signatures" | grep -Fq ' int removeBurstRun('
printf '%s\n' "$base_signatures" | grep -Fq ' int handlePrecuBurstRunExpiry('
printf '%s\n' "$base_signatures" | grep -Fq ' int handlePrecuBurstRunReady('
printf '%s\n' "$base_signatures" | grep -Fq ' int handlePrecuBurstRunMountState('
base_constants="$(javap -classpath "$class_root" -constants -p script.player.base.base_player)"
for constant in \
  'PRECU_BURST_RUN_BASE_COST = 100' \
  'PRECU_BURST_RUN_DURATION_SECONDS = 30' \
  'PRECU_BURST_RUN_RECOVERY_SECONDS = 300' \
  'PRECU_BURST_RUN_SPEED_STRENGTH = 82.2f' \
  'PRECU_BURST_RUN_ACCEL_MULTIPLIER = 1.822f'
do
  printf '%s\n' "$base_constants" | grep -Fq "$constant"
done
base_verbose="$(javap -classpath "$class_root" -v script.player.base.base_player)"
for token in precu.burstRun.effect precu.burstRun.cooldownUntil burst_run_wait burst_run_not_tired burst_run_space_dungeon burstrun_start_single burstrun_stop_single; do
  printf '%s\n' "$base_verbose" | grep -Fq "$token"
done
combat_code="$(javap -classpath "$class_root" -c -p script.systems.combat.combat_base)"
for method in applyPrecuPostureDown applyPrecuKnockdown; do
  method_code="$(printf '%s\n' "$combat_code" | awk -v method="$method" '
$0 ~ "^  public int " method "\\(" { capture = 1 }
capture && seen && /^  (public|private|protected) / { exit }
capture { print; seen = 1 }
')"
  test -n "$method_code"
  printf '%s\n' "$method_code" | grep -Fq '// String burstRun'
done
command_iff="$SWG_WORK_DIR/data/__COMMAND_IFF_PATH__"
buff_iff="$SWG_WORK_DIR/data/__BUFF_IFF_PATH__"
movement_iff="$SWG_WORK_DIR/data/__MOVEMENT_IFF_PATH__"
test "$(stat -Lc '%s' "$command_iff")" -eq __COMMAND_IFF_BYTES__
test "$(sha256sum "$command_iff" | awk '{print $1}')" = "__COMMAND_IFF_SHA__"
test "$(stat -Lc '%s' "$buff_iff")" -eq __BUFF_IFF_BYTES__
test "$(sha256sum "$buff_iff" | awk '{print $1}')" = "__BUFF_IFF_SHA__"
test "$(stat -Lc '%s' "$movement_iff")" -eq __MOVEMENT_IFF_BYTES__
test "$(sha256sum "$movement_iff" | awk '{print $1}')" = "__MOVEMENT_IFF_SHA__"
test "$(strings -a "$command_iff" | grep -Fxc burstRun || true)" -eq 2
test "$(strings -a "$buff_iff" | grep -Fxc burstRun || true)" -eq 1
test "$(strings -a "$movement_iff" | grep -Fxc burstRun || true)" -eq 1
test "$(strings -a "$movement_iff" | grep -Fxc 'e(boost=1,snare=2,permaboost=3,permasnare=4,root=5,stun=6)[root]' || true)" -eq 1
temp_root="$(mktemp -d /dev/shm/precu-burst-run-iff.XXXXXX)"
cleanup_burst_run_iff() {
  case "${temp_root:-}" in /dev/shm/precu-burst-run-iff.*) ;; *) return 97 ;; esac
  resolved="$(readlink -f -- "$temp_root")"
  case "$resolved" in /dev/shm/precu-burst-run-iff.*) ;; *) return 98 ;; esac
  rm -rf -- "$resolved"
}
trap cleanup_burst_run_iff 0 HUP INT TERM
datatable_tool="$SWG_WORK_DIR/build/bin/DataTableTool"
test -x "$datatable_tool"
compile_and_compare() {
  source_tab="$1"
  canonical_iff="$2"
  relative_tab="$3"
  relative_iff="$4"
  temp_tab="$temp_root/dsrc/$relative_tab"
  fresh_iff="$temp_root/data/$relative_iff"
  mkdir -p -- "$(dirname "$temp_tab")" "$(dirname "$fresh_iff")"
  cp -- "$source_tab" "$temp_tab"
  (
    cd "$temp_root"
    PATH="$PATH:$SWG_WORK_DIR/build/bin" "$datatable_tool" \
      -i "dsrc/$relative_tab" -- -s SharedFile \
      "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.shared/compiled/game" \
      "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game" \
      "searchPath10=$SWG_WORK_DIR/data/sku.0/sys.server/compiled/game"
  ) >/dev/null
  test -s "$fresh_iff"
  cmp -s "$fresh_iff" "$canonical_iff"
}
compile_and_compare \
  "$work_root/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab" \
  "$command_iff" \
  sku.0/sys.shared/compiled/game/datatables/command/command_table.tab \
  sku.0/sys.shared/compiled/game/datatables/command/command_table.iff
compile_and_compare \
  "$work_root/sku.0/sys.shared/compiled/game/datatables/buff/buff.tab" \
  "$buff_iff" \
  sku.0/sys.shared/compiled/game/datatables/buff/buff.tab \
  sku.0/sys.shared/compiled/game/datatables/buff/buff.iff
compile_and_compare \
  "$work_root/sku.0/sys.server/compiled/game/datatables/movement/movement.tab" \
  "$movement_iff" \
  sku.0/sys.server/compiled/game/datatables/movement/movement.tab \
  sku.0/sys.server/compiled/game/datatables/movement/movement.iff
cleanup_burst_run_iff
trap - 0 HUP INT TERM
test ! -e "$temp_root"
'@
    $probe = $probe.Replace("__COMMAND_IFF_PATH__", [string]$commandIff.path).
        Replace("__BUFF_IFF_PATH__", [string]$buffIff.path).
        Replace("__MOVEMENT_IFF_PATH__", [string]$movementIff.path).
        Replace("__COMMAND_IFF_BYTES__", [string]$commandIff.bytes).
        Replace("__BUFF_IFF_BYTES__", [string]$buffIff.bytes).
        Replace("__MOVEMENT_IFF_BYTES__", [string]$movementIff.bytes).
        Replace("__COMMAND_IFF_SHA__", [string]$commandIff.sha256).
        Replace("__BUFF_IFF_SHA__", [string]$buffIff.sha256).
        Replace("__MOVEMENT_IFF_SHA__", [string]$movementIff.sha256).
        Replace("__BASE_CLASS_BYTES__", [string]$baseClassEvidence[0].bytes).
        Replace("__BASE_CLASS_SHA__", [string]$baseClassEvidence[0].sha256).
        Replace("__COMBAT_CLASS_BYTES__", [string]$combatClassEvidence[0].bytes).
        Replace("__COMBAT_CLASS_SHA__", [string]$combatClassEvidence[0].sha256).
        Replace("__CLASS_MAJOR__", [string]$canonical.freshClassBytecode.classMajorVersion).
        Replace("`r`n", "`n")
    $probe.Replace("`r`n", "`n") |
        & docker exec -i $Container sh -c "tr -d '\r' | sh -s"
    Assert-Contract ($LASTEXITCODE -eq 0) `
        "p14.burst-run.build.current-canonical-artifacts"
}

if ($Expectation -ceq "Ready")
{
    $payload = $contract.liveAcceptancePayload
    $deployment = $contract.deploymentEvidence
    $live = $contract.liveEvidence
    Assert-Contract ([string]$contract.status -ceq "ready" -and
        @($contract.requiredBeforeReady).Count -eq 0 -and
        [string]$deployment.result -ceq "passed" -and
        [string]$deployment.deploymentParentCommit -ceq
            $recordedDeploymentCommit -and
        [string]$deployment.directSourceCommit -ceq $expectedCommit -and
        [string]$deployment.container -ceq $Container -and
        [string]$deployment.containerId -cmatch '^[0-9a-f]{64}$' -and
        [string]$deployment.containerImage -cne "pending" -and
        [string]$deployment.containerImageId -cmatch '^sha256:[0-9a-f]{64}$' -and
        (Test-IsoTimestamp ([string]$deployment.containerStartedAt)) -and
        [bool]$deployment.sourceMountReadOnly -and
        [string]$deployment.dockerWorkVolume -ceq "swg-precu-work-x64" -and
        [string]$deployment.containerHealth -ceq "healthy" -and
        [bool]$deployment.clusterReadyForPlayers -and
        [int]$deployment.clusterReadyMarkerCount -ge 1) `
        "p14.burst-run.ready.current-deployment-identity"
    $processPids = @($deployment.liveGameProcessPids)
    $deploymentArtifactIdentityExact = Test-ArtifactIdentitySet `
        -Actual @($deployment.artifactIdentities) -Expected $expectedArtifactMap
    $deploymentArtifactMetadataExact = $true
    foreach ($artifact in @($deployment.artifactIdentities))
    {
        if ([int64]$artifact.inode -le 0)
        {
            $deploymentArtifactMetadataExact = $false
        }
        if ([string]$artifact.path -in $requiredClassPaths -and
            [int]$artifact.classMajorVersion -ne
                [int]$canonical.freshClassBytecode.classMajorVersion)
        {
            $deploymentArtifactMetadataExact = $false
        }
    }
    Assert-Contract ([int]$deployment.liveGameProcessCount -eq 15 -and
        $processPids.Count -eq 15 -and
        @($processPids | Where-Object { [int]$_ -le 0 }).Count -eq 0 -and
        (@($processPids | Sort-Object -Unique).Count -eq 15) -and
        [bool]$deployment.allLiveGameProcessesMatchBinary -and
        [string]$deployment.serverBinary.path -ceq
            "/swg-precu/build/bin/SwgGameServer" -and
        (Test-Sha256Fingerprint ([string]$deployment.serverBinary.sha256)) -and
        [string]$deployment.serverBinary.buildIdSha1 -cmatch '^[0-9a-f]{40}$' -and
        [int64]$deployment.serverBinary.bytes -gt 0 -and
        [int64]$deployment.serverBinary.inode -gt 0 -and
        [int64]$deployment.serverBinary.device -gt 0 -and
        $deploymentArtifactIdentityExact -and $deploymentArtifactMetadataExact) `
        "p14.burst-run.ready.current-process-binary-and-artifact-identities"
    Assert-Contract ([string]$deployment.postStartLogAudit.result -ceq "passed" -and
        (Test-IsoTimestamp ([string]$deployment.postStartLogAudit.capturedAt)) -and
        [int]$deployment.postStartLogAudit.lineCount -gt 0 -and
        [int]$deployment.postStartLogAudit.fatalSevereExceptionUndefinedSymbolOracleOrEmptyGenericMessageMatches -eq 0 -and
        [int]$deployment.postStartLogAudit.playerReadyMarkerCount -ge 1) `
        "p14.burst-run.ready.post-start-log-audit"

    $preflight = $payload.preflightCapture
    $actor = $payload.actor
    Assert-Contract ([string]$payload.result -ceq "passed" -and
        [string]$payload.id -ceq "p14-burst-run-single-player-reversible-v1" -and
        [int]$payload.boundedSeconds -le 360 -and [bool]$payload.identityBound -and
        -not [bool]$payload.skillMutationAllowed -and
        [int64]$actor.playerOid -gt 0 -and [int64]$actor.stationId -gt 0 -and
        [string]$actor.characterName -cne "pending" -and
        (Test-IsoTimestamp ([string]$payload.observedAt)) -and
        [string]$payload.deploymentContainerId -ceq
            [string]$deployment.containerId) `
        "p14.burst-run.ready.acceptance-actor-time-and-deployment-binding"
    Assert-Contract ([string]$preflight.result -ceq "passed" -and
        (Test-NineAttributeSnapshot @($preflight.nineAttributes)) -and
        [double]$preflight.movementPercent -gt 0 -and
        [double]$preflight.accelerationPercent -gt 0 -and
        [int]$preflight.posture -ge 0 -and [string]$preflight.scene -cne "pending" -and
        (Test-Sha256Fingerprint ([string]$preflight.locationFingerprint)) -and
        (Test-Sha256Fingerprint ([string]$preflight.unrelatedBuffFingerprint)) -and
        (Test-Sha256Fingerprint ([string]$preflight.skillFingerprint)) -and
        (Test-Sha256Fingerprint ([string]$preflight.inventoryFingerprint)) -and
        [int]$preflight.ownedBuffCount -eq 0 -and
        [int]$preflight.ownedObjVarCount -eq 0) `
        "p14.burst-run.ready.preflight-exact-reversible-capture"

    $activation = $payload.activation
    $expectedHealthCost = Get-BurstRunCost `
        ([double]$activation.strength) ([double]$activation.burstRunSkillMod)
    $expectedActionCost = Get-BurstRunCost `
        ([double]$activation.quickness) ([double]$activation.burstRunSkillMod)
    $expectedMindCost = Get-BurstRunCost `
        ([double]$activation.focus) ([double]$activation.burstRunSkillMod)
    $activeMovementExact = Test-NearlyEqual `
        -Actual ([double]$activation.activeMovementPercent) `
        -Expected ([double]$preflight.movementPercent * 1.822)
    $baseAccelerationExact = Test-NearlyEqual `
        -Actual ([double]$activation.baseAccelerationPercent) `
        -Expected ([double]$preflight.accelerationPercent)
    $activeAccelerationExact = Test-NearlyEqual `
        -Actual ([double]$activation.activeAccelerationPercent) `
        -Expected ([double]$preflight.accelerationPercent * 1.822)
    Assert-Contract ([string]$activation.result -ceq "passed" -and
        [int]$activation.activationGameTime -gt 0 -and
        [int]$activation.effectExpiresAt -eq
            [int]$activation.activationGameTime + 30 -and
        [int]$activation.cooldownUntil -eq
            [int]$activation.activationGameTime + 330 -and
        [int]$activation.handlerCalls -eq 1 -and
        [int]$activation.healthCost -eq $expectedHealthCost -and
        [int]$activation.actionCost -eq $expectedActionCost -and
        [int]$activation.mindCost -eq $expectedMindCost -and
        [int]$activation.healthBefore -gt [int]$activation.healthCost -and
        [int]$activation.actionBefore -gt [int]$activation.actionCost -and
        [int]$activation.mindBefore -gt [int]$activation.mindCost -and
        [int]$activation.healthAfter -eq
            [int]$activation.healthBefore - [int]$activation.healthCost -and
        [int]$activation.actionAfter -eq
            [int]$activation.actionBefore - [int]$activation.actionCost -and
        [int]$activation.mindAfter -eq
            [int]$activation.mindBefore - [int]$activation.mindCost) `
        "p14.burst-run.ready.exact-three-pool-formula-and-atomic-drain"
    Assert-Contract ([int]$activation.visibleBuffCount -eq 1 -and
        [int]$activation.buffDurationSeconds -eq 30 -and
        $activeMovementExact -and $baseAccelerationExact -and
        $activeAccelerationExact -and
        [int]$activation.startSingleMessageCount -eq 1 -and
        [int]$activation.startBroadcastMessageCount -eq 1) `
        "p14.burst-run.ready.exact-effect-movement-acceleration-and-start-feedback"

    $recast = $payload.immediateRecast
    Assert-Contract ([string]$recast.result -ceq "passed" -and
        [int]$recast.attempts -eq 1 -and [int]$recast.waitMessageCount -eq 1 -and
        [int]$recast.healthBefore -eq [int]$recast.healthAfter -and
        [int]$recast.actionBefore -eq [int]$recast.actionAfter -and
        [int]$recast.mindBefore -eq [int]$recast.mindAfter -and
        [int]$recast.effectExpiresAtBefore -eq [int]$activation.effectExpiresAt -and
        [int]$recast.effectExpiresAtAfter -eq [int]$activation.effectExpiresAt -and
        [int]$recast.cooldownUntilBefore -eq [int]$activation.cooldownUntil -and
        [int]$recast.cooldownUntilAfter -eq [int]$activation.cooldownUntil) `
        "p14.burst-run.ready.immediate-recast-denial-no-mutation"

    $relog = $payload.relog
    $relogMovementExact = Test-NearlyEqual `
        -Actual ([double]$relog.activeMovementPercentAfter) `
        -Expected ([double]$preflight.movementPercent * 1.822)
    $relogAccelerationExact = Test-NearlyEqual `
        -Actual ([double]$relog.activeAccelerationPercentAfter) `
        -Expected ([double]$preflight.accelerationPercent * 1.822)
    Assert-Contract ([string]$relog.result -ceq "passed" -and
        [int]$relog.disconnectGameTime -ge [int]$activation.activationGameTime -and
        [int]$relog.disconnectGameTime -lt [int]$activation.effectExpiresAt -and
        [int]$relog.reconnectGameTime -gt [int]$relog.disconnectGameTime -and
        [int]$relog.reconnectGameTime -lt [int]$activation.effectExpiresAt -and
        [int]$relog.effectExpiresAtBefore -eq [int]$activation.effectExpiresAt -and
        [int]$relog.effectExpiresAtAfter -eq [int]$activation.effectExpiresAt -and
        [int]$relog.cooldownUntilBefore -eq [int]$activation.cooldownUntil -and
        [int]$relog.cooldownUntilAfter -eq [int]$activation.cooldownUntil -and
        [int]$relog.healthBefore -eq [int]$relog.healthAfter -and
        [int]$relog.actionBefore -eq [int]$relog.actionAfter -and
        [int]$relog.mindBefore -eq [int]$relog.mindAfter -and
        -not [bool]$relog.hamRechargedByRelog -and
        [int]$relog.remainingEffectSecondsAfter -gt 0 -and
        [int]$relog.remainingEffectSecondsAfter -le 30 -and
        $relogMovementExact -and $relogAccelerationExact) `
        "p14.burst-run.ready.relog-effect-cooldown-and-ham-persistence"

    $expiryEvidence = $payload.expiry
    $expiryMovementExact = Test-NearlyEqual `
        -Actual ([double]$expiryEvidence.movementPercentAfter) `
        -Expected ([double]$preflight.movementPercent)
    $expiryAccelerationExact = Test-NearlyEqual `
        -Actual ([double]$expiryEvidence.accelerationPercentAfter) `
        -Expected ([double]$preflight.accelerationPercent)
    Assert-Contract ([string]$expiryEvidence.result -ceq "passed" -and
        [int]$expiryEvidence.observedGameTime -ge [int]$activation.effectExpiresAt -and
        [int]$expiryEvidence.stopSingleMessageCount -eq 1 -and
        [int]$expiryEvidence.stopBroadcastMessageCount -eq 1 -and
        [int]$expiryEvidence.buffCountAfter -eq 0 -and
        [int]$expiryEvidence.effectObjVarCountAfter -eq 0 -and
        $expiryMovementExact -and $expiryAccelerationExact -and
        [int]$expiryEvidence.cooldownUntilAfter -eq
            [int]$activation.cooldownUntil) `
        "p14.burst-run.ready.natural-expiry-restores-and-retains-recovery"
    $recovery = $payload.recovery
    Assert-Contract ([string]$recovery.result -ceq "passed" -and
        [int]$recovery.observedGameTime -ge [int]$activation.cooldownUntil -and
        [int]$recovery.activationToReadySeconds -eq 330 -and
        [int]$recovery.readyMessageCount -eq 1 -and
        [int]$recovery.cooldownObjVarCountAfter -eq 0 -and
        [bool]$recovery.firstLegalRecastConfirmed) `
        "p14.burst-run.ready.exact-330-second-recovery"

    $cleanup = $payload.cleanup
    $cleanupSnapshotValid = Test-NineAttributeSnapshot `
        -Snapshot @($cleanup.nineAttributesAfter)
    $cleanupSnapshotExact = Test-JsonExact `
        -Actual @($cleanup.nineAttributesAfter) `
        -Expected @($preflight.nineAttributes)
    $cleanupMovementExact = Test-NearlyEqual `
        -Actual ([double]$cleanup.movementPercentAfter) `
        -Expected ([double]$preflight.movementPercent)
    $cleanupAccelerationExact = Test-NearlyEqual `
        -Actual ([double]$cleanup.accelerationPercentAfter) `
        -Expected ([double]$preflight.accelerationPercent)
    Assert-Contract ([string]$cleanup.result -ceq "passed" -and
        $cleanupSnapshotValid -and $cleanupSnapshotExact -and
        $cleanupMovementExact -and $cleanupAccelerationExact -and
        [int]$cleanup.postureAfter -eq [int]$preflight.posture -and
        [string]$cleanup.locationFingerprintAfter -ceq
            [string]$preflight.locationFingerprint -and
        [string]$cleanup.unrelatedBuffFingerprintAfter -ceq
            [string]$preflight.unrelatedBuffFingerprint -and
        [string]$cleanup.skillFingerprintAfter -ceq
            [string]$preflight.skillFingerprint -and
        [string]$cleanup.inventoryFingerprintAfter -ceq
            [string]$preflight.inventoryFingerprint -and
        [int]$cleanup.ownedBuffCountAfter -eq 0 -and
        [int]$cleanup.ownedObjVarCountAfter -eq 0 -and
        [bool]$cleanup.relogVerified -and [bool]$cleanup.serverHealthy) `
        "p14.burst-run.ready.identity-bound-exact-reversible-cleanup"
    Assert-Contract ([string]$live.result -ceq "passed" -and
        [string]$live.payloadId -ceq [string]$payload.id -and
        [int64]$live.playerOid -eq [int64]$actor.playerOid -and
        [int64]$live.stationId -eq [int64]$actor.stationId -and
        [string]$live.characterName -ceq [string]$actor.characterName -and
        [string]$live.observedAt -ceq [string]$payload.observedAt -and
        [string]$live.deploymentContainerId -ceq
            [string]$deployment.containerId -and
        [bool]$live.serverHealthyAfterCleanup) `
        "p14.burst-run.ready.live-summary-linkage"

    $actualContainerId = (& docker inspect --format "{{.Id}}" $Container 2>&1 |
        Out-String).Trim()
    $actualImageId = (& docker inspect --format "{{.Image}}" $Container 2>&1 |
        Out-String).Trim()
    $actualImage = (& docker inspect --format "{{.Config.Image}}" $Container 2>&1 |
        Out-String).Trim()
    $actualStartedAt = (& docker inspect --format "{{.State.StartedAt}}" $Container 2>&1 |
        Out-String).Trim()
    $actualHealth = (& docker inspect --format `
        "{{if .State.Health}}{{.State.Health.Status}}{{end}}" $Container 2>&1 |
        Out-String).Trim()
    Assert-Contract ($actualContainerId -ceq [string]$deployment.containerId -and
        $actualImageId -ceq [string]$deployment.containerImageId -and
        $actualImage -ceq [string]$deployment.containerImage -and
        $actualStartedAt -ceq [string]$deployment.containerStartedAt -and
        $actualHealth -ceq "healthy") `
        "p14.burst-run.ready.live-container-still-current"

    $mountsJson = (& docker inspect --format "{{json .Mounts}}" $Container 2>&1 |
        Out-String).Trim()
    $parsedMounts = $mountsJson | ConvertFrom-Json
    $mounts = @()
    foreach ($mount in $parsedMounts) { $mounts += $mount }
    $sourceMount = @($mounts | Where-Object {
        [string]$_.Destination -ceq "/swg-precu-source"
    })
    $workMount = @($mounts | Where-Object {
        [string]$_.Destination -ceq "/swg-precu"
    })
    Assert-Contract ($sourceMount.Count -eq 1 -and -not [bool]$sourceMount[0].RW -and
        $workMount.Count -eq 1 -and [string]$workMount[0].Type -ceq "volume" -and
        [string]$workMount[0].Name -ceq [string]$deployment.dockerWorkVolume) `
        "p14.burst-run.ready.live-mount-boundary"

    $actualPids = @(& docker exec $Container pgrep -x SwgGameServer 2>&1 |
        ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -cmatch '^[0-9]+$' })
    Assert-Contract (Test-ExactOrdinalList $actualPids @($processPids | ForEach-Object {
        [string]$_
    })) "p14.burst-run.ready.live-pid-inventory-current"
    $actualArtifacts = [Collections.Generic.List[object]]::new()
    $classBinaryNames = @{
        "sku.0/sys.server/compiled/game/script/player/base/base_player.class" =
            "script.player.base.base_player"
        "sku.0/sys.server/compiled/game/script/systems/combat/combat_base.class" =
            "script.systems.combat.combat_base"
    }
    foreach ($path in @($expectedArtifactMap.Keys))
    {
        $absolute = "/swg-precu/data/$path"
        $statOutput = (& docker exec $Container stat -Lc "%s|%i" $absolute 2>&1 |
            Out-String).Trim()
        $statParts = $statOutput -split '\|'
        $hashOutput = (& docker exec $Container sha256sum $absolute 2>&1 |
            Out-String).Trim()
        $hash = ($hashOutput -split '\s+')[0]
        $actualArtifact = [ordered]@{
            path = [string]$path
            bytes = [int64]$statParts[0]
            sha256 = [string]$hash
            inode = [int64]$statParts[1]
        }
        if ($classBinaryNames.ContainsKey([string]$path))
        {
            $verbose = (& docker exec $Container javap -classpath `
                "/swg-precu/data/sku.0/sys.server/compiled/game" -verbose `
                $classBinaryNames[[string]$path] 2>&1 | Out-String)
            $majorMatch = [regex]::Match($verbose, 'major version:\s+([0-9]+)')
            $actualArtifact.classMajorVersion = if ($majorMatch.Success) {
                [int]$majorMatch.Groups[1].Value
            } else { -1 }
        }
        $actualArtifacts.Add([pscustomobject]$actualArtifact)
    }
    $liveArtifactIdentityExact = Test-ArtifactIdentitySet `
        -Actual @($actualArtifacts) -Expected $expectedArtifactMap
    $liveArtifactMetadataExact = $true
    foreach ($recorded in @($deployment.artifactIdentities))
    {
        $actual = @($actualArtifacts | Where-Object {
            [string]$_.path -ceq [string]$recorded.path
        })
        if ($actual.Count -ne 1 -or
            [int64]$actual[0].inode -ne [int64]$recorded.inode -or
            ([string]$recorded.path -in $requiredClassPaths -and
                [int]$actual[0].classMajorVersion -ne
                    [int]$recorded.classMajorVersion))
        {
            $liveArtifactMetadataExact = $false
        }
    }
    Assert-Contract ($liveArtifactIdentityExact -and $liveArtifactMetadataExact) `
        "p14.burst-run.ready.live-artifacts-still-current"
    $binaryPath = [string]$deployment.serverBinary.path
    $actualBinaryBytes = (& docker exec $Container stat -Lc "%s" $binaryPath 2>&1 |
        Out-String).Trim()
    $actualBinaryInode = (& docker exec $Container stat -Lc "%i" $binaryPath 2>&1 |
        Out-String).Trim()
    $actualBinaryDevice = (& docker exec $Container stat -Lc "%d" $binaryPath 2>&1 |
        Out-String).Trim()
    $actualBinaryHashOutput = (& docker exec $Container sha256sum $binaryPath 2>&1 |
        Out-String).Trim()
    $actualBinaryHash = ($actualBinaryHashOutput -split '\s+')[0]
    $readelf = (& docker exec $Container readelf -n $binaryPath 2>&1 | Out-String)
    $buildIdMatch = [regex]::Match($readelf, 'Build ID: ([0-9a-f]{40})')
    Assert-Contract ([int64]$actualBinaryBytes -eq
            [int64]$deployment.serverBinary.bytes -and
        [int64]$actualBinaryInode -eq [int64]$deployment.serverBinary.inode -and
        [int64]$actualBinaryDevice -eq [int64]$deployment.serverBinary.device -and
        $actualBinaryHash -ceq [string]$deployment.serverBinary.sha256 -and
        $buildIdMatch.Success -and $buildIdMatch.Groups[1].Value -ceq
            [string]$deployment.serverBinary.buildIdSha1) `
        "p14.burst-run.ready.live-server-binary-still-current"
    foreach ($gamePid in $actualPids)
    {
        $processPath = (& docker exec $Container readlink -f "/proc/$gamePid/exe" 2>&1 |
            Out-String).Trim()
        $processBytes = (& docker exec $Container stat -Lc "%s" "/proc/$gamePid/exe" 2>&1 |
            Out-String).Trim()
        $processInode = (& docker exec $Container stat -Lc "%i" "/proc/$gamePid/exe" 2>&1 |
            Out-String).Trim()
        $processDevice = (& docker exec $Container stat -Lc "%d" "/proc/$gamePid/exe" 2>&1 |
            Out-String).Trim()
        Assert-Contract ($processPath -ceq $binaryPath -and
            [int64]$processBytes -eq [int64]$actualBinaryBytes -and
            [int64]$processInode -eq [int64]$actualBinaryInode -and
            [int64]$processDevice -eq [int64]$actualBinaryDevice) `
            "p14.burst-run.ready.live-process-$gamePid-binary-identity"
    }

    $logLines = @(& docker logs --since ([string]$deployment.containerStartedAt) `
        $Container 2>&1 | ForEach-Object { [string]$_ } |
        Where-Object { $_.Trim().Length -gt 0 })
    $readyMarkers = @($logLines | Where-Object {
        $_ -match 'Cluster swg is ready for players\.'
    })
    $prohibitedLogPattern =
        '(?i)(fatal|severe|exception|undefined symbol|unsatisfiedlink|' +
        'ORA-[0-9]+|segmentation fault|core dump|' +
        'ConGenericMessage\s*\(\s*\)|' +
        'ConGenericMessage constructed with empty message|\[exec\]\s*error)'
    $prohibitedLogMatches = @($logLines | Where-Object {
        $_ -match $prohibitedLogPattern
    })
    Assert-Contract ($logLines.Count -ge
            [int]$deployment.postStartLogAudit.lineCount -and
        $readyMarkers.Count -ge
            [int]$deployment.postStartLogAudit.playerReadyMarkerCount -and
        $prohibitedLogMatches.Count -eq 0) `
        "p14.burst-run.ready.live-post-start-log-audit-current"
}

if ($failures.Count -gt 0)
{
    throw "Publish 14.1 Burst Run contract failed: $($failures -join ', ')"
}
Write-Host "Publish 14.1 universal Burst Run authority contract passed ($Expectation)."
