[CmdletBinding()]
param(
    [string]$FixtureRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($FixtureRoot))
{
    $FixtureRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "fixtures/reborn-force-threads"
}
$resolvedFixtureRoot = (Resolve-Path -LiteralPath $FixtureRoot).Path
$configPath = Join-Path $resolvedFixtureRoot "model-config.json"
$scenariosPath = Join-Path $resolvedFixtureRoot "scenarios.json"

foreach ($path in @($configPath, $scenariosPath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required Force Threads model fixture is missing: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$scenarioDocument = Get-Content -LiteralPath $scenariosPath -Raw | ConvertFrom-Json
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$activeLimits = $null

function Assert-Model([bool]$Condition, [string]$Message)
{
    if (-not $Condition) { throw $Message }
}

function Test-Property([object]$Object, [string]$Name)
{
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-RequiredString([object]$Object, [string]$Name)
{
    if (-not (Test-Property $Object $Name))
    {
        throw "missing_$Name"
    }

    $value = [string]$Object.$Name
    if ([string]::IsNullOrWhiteSpace($value))
    {
        throw "empty_$Name"
    }
    return $value
}

function Get-RequiredInt64([object]$Object, [string]$Name)
{
    $text = Get-RequiredString $Object $Name
    [long]$value = 0
    if (-not [long]::TryParse(
            $text,
            [System.Globalization.NumberStyles]::Integer,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$value))
    {
        throw "invalid_$Name"
    }
    return $value
}

function Get-Station([object]$Object, [string]$Name)
{
    $value = Get-RequiredString $Object $Name
    if ($value -cnotmatch '^[1-9][0-9]{0,18}$')
    {
        throw "invalid_$Name"
    }
    return $value
}

function Get-Domain([object]$Object, [string]$Name)
{
    $value = (Get-RequiredString $Object $Name).ToUpperInvariant()
    if ($value -cnotmatch '^[A-Z][A-Z0-9_]{0,31}$')
    {
        throw "invalid_$Name"
    }

    if (@($config.domains | ForEach-Object { [string]$_ }).IndexOf($value) -lt 0)
    {
        throw "unknown_$Name"
    }
    return $value
}

function Get-Sha256([string]$Text)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return ([System.BitConverter]::ToString(
                $sha.ComputeHash($utf8NoBom.GetBytes($Text))
            )).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-OrdinalSortedStrings([object[]]$Values)
{
    [string[]]$result = @($Values | ForEach-Object { [string]$_ })
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return ,$result
}

function New-ModelState([int]$SchemaVersion)
{
    return [pscustomobject]@{
        SchemaVersion = $SchemaVersion
        Quarantined = $false
        QuarantineReason = ""
        Tokens = @()
        Mailbox = @{}
        Ledger = @{}
        SealedTotals = @{}
        Dedupe = @()
        PairHistory = @{}
        ReasonCounts = @{}
        Stats = [pscustomobject]@{
            Accepted = 0
            Rejected = 0
            Duplicates = 0
            Ignored = 0
            Expired = 0
            Sealed = 0
            Reconciled = 0
        }
        Peaks = [pscustomobject]@{
            TokensPerStation = 0
            MailboxPerStation = 0
            LedgerPerStation = 0
        }
    }
}

function Add-Reason([object]$State, [string]$Reason)
{
    if (-not $State.ReasonCounts.ContainsKey($Reason))
    {
        $State.ReasonCounts[$Reason] = 0
    }
    $State.ReasonCounts[$Reason] = [int]$State.ReasonCounts[$Reason] + 1
}

function Reject-Event([object]$State, [string]$Reason)
{
    $State.Stats.Rejected++
    Add-Reason $State $Reason
}

function Quarantine-State([object]$State, [string]$Reason)
{
    if (-not $State.Quarantined)
    {
        $State.Quarantined = $true
        $State.QuarantineReason = $Reason
        Add-Reason $State $Reason
    }
}

function Get-PairKey([string]$First, [string]$Second)
{
    [string[]]$stations = @($First, $Second)
    [Array]::Sort($stations, [StringComparer]::Ordinal)
    return "$($stations[0])~$($stations[1])"
}

function Test-PairAdmission(
    [object]$State,
    [string]$First,
    [string]$Second,
    [long]$At,
    [ref]$Reason
)
{
    $pairKey = Get-PairKey $First $Second
    if (-not $State.PairHistory.ContainsKey($pairKey))
    {
        return $true
    }

    [long]$lastAt = $State.PairHistory[$pairKey]
    if ($At -lt $lastAt)
    {
        $Reason.Value = "out_of_order"
        return $false
    }
    if (($At - $lastAt) -lt [long]$config.repeatedPairCooldownSeconds)
    {
        $Reason.Value = "repeated_pair_cooldown"
        return $false
    }
    return $true
}

function Set-PairAdmission([object]$State, [string]$First, [string]$Second, [long]$At)
{
    $State.PairHistory[(Get-PairKey $First $Second)] = $At
    $limit = [int]$activeLimits.pairHistory
    if ($State.PairHistory.Count -le $limit) { return }

    $victims = @($State.PairHistory.GetEnumerator() |
        Sort-Object @{ Expression = { [long]$_.Value } }, @{ Expression = { [string]$_.Key } } |
        Select-Object -First ($State.PairHistory.Count - $limit))
    foreach ($victim in $victims)
    {
        $State.PairHistory.Remove([string]$victim.Key)
    }
}

function Test-Duplicate([object]$State, [string]$EventId)
{
    return @($State.Dedupe | Where-Object { [string]$_.Id -ceq $EventId }).Count -gt 0
}

function Add-Dedupe([object]$State, [string]$EventId, [long]$At)
{
    $State.Dedupe = @($State.Dedupe) + [pscustomobject]@{ Id = $EventId; At = $At }
    $limit = [int]$activeLimits.dedupe
    if ($State.Dedupe.Count -gt $limit)
    {
        $State.Dedupe = @($State.Dedupe |
            Sort-Object @{ Expression = { [long]$_.At } }, @{ Expression = { [string]$_.Id } } |
            Select-Object -Last $limit)
    }
}

function Expire-Tokens([object]$State, [long]$At)
{
    $live = @($State.Tokens | Where-Object { [long]$_.ExpiresAt -gt $At })
    $expired = $State.Tokens.Count - $live.Count
    if ($expired -gt 0)
    {
        $State.Stats.Expired += $expired
        Add-Reason $State "token_expired"
    }
    $State.Tokens = $live
}

function Get-StationEntryCount([hashtable]$Map, [string]$Station)
{
    if (-not $Map.ContainsKey($Station)) { return 0 }
    return @($Map[$Station]).Count
}

function Update-PeaksAndAssertBounds([object]$State)
{
    $tokenGroups = @($State.Tokens | Group-Object CurrentStation)
    foreach ($group in $tokenGroups)
    {
        $State.Peaks.TokensPerStation = [Math]::Max(
            [int]$State.Peaks.TokensPerStation,
            [int]$group.Count
        )
        Assert-Model ($group.Count -le [int]$activeLimits.activeTokensPerStation) `
            "Active-token bound exceeded for station $($group.Name)."
    }

    foreach ($entry in @($State.Mailbox.GetEnumerator()))
    {
        $count = @($entry.Value).Count
        $State.Peaks.MailboxPerStation = [Math]::Max(
            [int]$State.Peaks.MailboxPerStation,
            $count
        )
        Assert-Model ($count -le [int]$activeLimits.mailboxPerStation) `
            "Mailbox bound exceeded for station $($entry.Key)."
    }

    foreach ($entry in @($State.Ledger.GetEnumerator()))
    {
        $count = @($entry.Value).Count
        $State.Peaks.LedgerPerStation = [Math]::Max(
            [int]$State.Peaks.LedgerPerStation,
            $count
        )
        Assert-Model ($count -le [int]$activeLimits.ledgerPerStation) `
            "Ledger bound exceeded for station $($entry.Key)."
    }

    Assert-Model ($State.Dedupe.Count -le [int]$activeLimits.dedupe) `
        "Dedupe bound exceeded."
    Assert-Model ($State.PairHistory.Count -le [int]$activeLimits.pairHistory) `
        "Pair-history bound exceeded."
}

function Add-Support([object]$State, [object]$Event, [string]$EventId, [long]$At)
{
    $from = Get-Station $Event "from"
    $to = Get-Station $Event "to"
    $domain = Get-Domain $Event "domain"

    if ($from -ceq $to)
    {
        Reject-Event $State "same_station"
        return
    }

    $pairReason = ""
    if (-not (Test-PairAdmission $State $from $to $At ([ref]$pairReason)))
    {
        Reject-Event $State $pairReason
        return
    }

    if (@($State.Tokens | Where-Object { [string]$_.CurrentStation -ceq $to }).Count -ge
        [int]$activeLimits.activeTokensPerStation)
    {
        Reject-Event $State "token_capacity"
        return
    }

    $tokenId = Get-Sha256 "token-v1|$EventId|$At|$from|$to|$domain"
    $State.Tokens = @($State.Tokens) + [pscustomobject]@{
        TokenId = $tokenId
        RootId = $tokenId
        OriginStation = $from
        CurrentStation = $to
        Participants = @($from, $to)
        Domains = @($domain)
        Depth = 1
        CreatedAt = $At
        LastAt = $At
        ExpiresAt = $At + [long]$config.tokenTtlSeconds
    }
    Set-PairAdmission $State $from $to $At
    $State.Stats.Accepted++
}

function Add-Relay([object]$State, [object]$Event, [string]$EventId, [long]$At)
{
    $from = Get-Station $Event "from"
    $to = Get-Station $Event "to"
    $domain = Get-Domain $Event "domain"

    if ($from -ceq $to)
    {
        Reject-Event $State "same_station"
        return
    }

    $candidates = @($State.Tokens | Where-Object {
        [string]$_.CurrentStation -ceq $from
    })
    if ($candidates.Count -eq 0)
    {
        Reject-Event $State "no_token"
        return
    }

    $ordered = @($candidates |
        Sort-Object @{ Expression = { [long]$_.LastAt } }, @{ Expression = { [string]$_.TokenId } })
    $ordered = @($ordered | Where-Object { $At -ge [long]$_.LastAt })
    if ($ordered.Count -eq 0)
    {
        Reject-Event $State "out_of_order"
        return
    }

    $ordered = @($ordered | Where-Object { @($_.Participants).IndexOf($to) -lt 0 })
    if ($ordered.Count -eq 0)
    {
        Reject-Event $State "same_station"
        return
    }

    $ordered = @($ordered | Where-Object { @($_.Domains).IndexOf($domain) -lt 0 })
    if ($ordered.Count -eq 0)
    {
        Reject-Event $State "same_domain"
        return
    }

    $ordered = @($ordered | Where-Object { [int]$_.Depth -lt [int]$config.maximumEdges })
    if ($ordered.Count -eq 0)
    {
        Reject-Event $State "maximum_depth"
        return
    }

    $pairReason = ""
    if (-not (Test-PairAdmission $State $from $to $At ([ref]$pairReason)))
    {
        Reject-Event $State $pairReason
        return
    }

    if (@($State.Tokens | Where-Object {
            [string]$_.CurrentStation -ceq $to
        }).Count -ge [int]$activeLimits.activeTokensPerStation)
    {
        Reject-Event $State "token_capacity"
        return
    }

    $token = $ordered[0]
    $State.Tokens = @($State.Tokens | Where-Object {
        [string]$_.TokenId -cne [string]$token.TokenId
    })
    $newTokenId = Get-Sha256 "relay-v1|$($token.TokenId)|$EventId|$At|$from|$to|$domain"
    $State.Tokens = @($State.Tokens) + [pscustomobject]@{
        TokenId = $newTokenId
        RootId = [string]$token.RootId
        OriginStation = [string]$token.OriginStation
        CurrentStation = $to
        Participants = @($token.Participants) + $to
        Domains = @($token.Domains) + $domain
        Depth = [int]$token.Depth + 1
        CreatedAt = [long]$token.CreatedAt
        LastAt = $At
        ExpiresAt = [long]$token.ExpiresAt
    }
    Set-PairAdmission $State $from $to $At
    $State.Stats.Accepted++
}

function Add-Outcome([object]$State, [object]$Event, [string]$EventId, [long]$At)
{
    $actor = Get-Station $Event "actor"
    $domain = Get-Domain $Event "domain"
    $candidates = @($State.Tokens | Where-Object {
        [string]$_.CurrentStation -ceq $actor
    })
    if ($candidates.Count -eq 0)
    {
        Reject-Event $State "no_token"
        return
    }

    $candidates = @($candidates | Where-Object { $At -ge [long]$_.LastAt })
    if ($candidates.Count -eq 0)
    {
        Reject-Event $State "out_of_order"
        return
    }

    $candidates = @($candidates | Where-Object {
        [int]$_.Depth -ge [int]$config.minimumEdges
    })
    if ($candidates.Count -eq 0)
    {
        Reject-Event $State "insufficient_depth"
        return
    }

    $candidates = @($candidates | Where-Object { @($_.Domains).IndexOf($domain) -lt 0 })
    if ($candidates.Count -eq 0)
    {
        Reject-Event $State "same_domain"
        return
    }

    $token = @($candidates |
        Sort-Object @{ Expression = { [long]$_.LastAt } }, @{ Expression = { [string]$_.TokenId } })[0]
    $origin = [string]$token.OriginStation
    if ((Get-StationEntryCount $State.Mailbox $origin) -ge [int]$activeLimits.mailboxPerStation)
    {
        Reject-Event $State "mailbox_capacity"
        return
    }

    $participants = @($token.Participants)
    $domains = @($token.Domains)
    $threadId = Get-Sha256 (
        "thread-v1|$($token.RootId)|$EventId|$At|" +
        "$($participants -join '>')|$($domains -join '>')|$domain"
    )
    $record = [pscustomobject]@{
        ThreadId = $threadId
        OriginStation = $origin
        Participants = $participants
        Domains = $domains
        OutcomeDomain = $domain
        SealedAt = $At
    }

    if (-not $State.Mailbox.ContainsKey($origin))
    {
        $State.Mailbox[$origin] = @()
    }
    $State.Mailbox[$origin] = @($State.Mailbox[$origin]) + $record
    $State.Tokens = @($State.Tokens | Where-Object {
        [string]$_.TokenId -cne [string]$token.TokenId
    })
    $State.Stats.Accepted++
    $State.Stats.Sealed++
}

function Invoke-Reconcile([object]$State, [object]$Event)
{
    $station = Get-Station $Event "station"
    $records = if ($State.Mailbox.ContainsKey($station)) {
        @($State.Mailbox[$station] | Sort-Object ThreadId)
    }
    else { @() }

    if (-not $State.Ledger.ContainsKey($station))
    {
        $State.Ledger[$station] = @()
    }
    if (-not $State.SealedTotals.ContainsKey($station))
    {
        $State.SealedTotals[$station] = 0
    }

    foreach ($record in $records)
    {
        $alreadyPresent = @($State.Ledger[$station] | Where-Object {
            [string]$_.ThreadId -ceq [string]$record.ThreadId
        }).Count -gt 0
        if ($alreadyPresent) { continue }

        $State.Ledger[$station] = @($State.Ledger[$station]) + $record
        $State.SealedTotals[$station] = [int]$State.SealedTotals[$station] + 1
        $State.Stats.Reconciled++
    }

    $limit = [int]$activeLimits.ledgerPerStation
    if (@($State.Ledger[$station]).Count -gt $limit)
    {
        $State.Ledger[$station] = @($State.Ledger[$station] |
            Sort-Object @{ Expression = { [long]$_.SealedAt } }, @{ Expression = { [string]$_.ThreadId } } |
            Select-Object -Last $limit)
    }
    $State.Mailbox[$station] = @()
    $State.Stats.Accepted++
}

function Invoke-ModelEvent([object]$State, [object]$Event)
{
    if ($State.Quarantined)
    {
        $State.Stats.Ignored++
        return
    }

    try
    {
        $eventSchema = Get-RequiredInt64 $Event "schemaVersion"
        if ($eventSchema -ne [int]$config.schemaVersion)
        {
            Quarantine-State $State "unknown_event_schema"
            return
        }

        $eventId = Get-RequiredString $Event "eventId"
        if ($eventId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}$')
        {
            throw "invalid_eventId"
        }
        $at = Get-RequiredInt64 $Event "at"
        if ($at -lt 0) { throw "invalid_at" }
        $type = (Get-RequiredString $Event "type").ToLowerInvariant()

        if (Test-Duplicate $State $eventId)
        {
            $State.Stats.Duplicates++
            Add-Reason $State "duplicate_event"
            return
        }
        Add-Dedupe $State $eventId $at
        Expire-Tokens $State $at

        switch ($type)
        {
            "support" { Add-Support $State $Event $eventId $at }
            "relay" { Add-Relay $State $Event $eventId $at }
            "outcome" { Add-Outcome $State $Event $eventId $at }
            "reconcile" { Invoke-Reconcile $State $Event }
            default { throw "unknown_type" }
        }
    }
    catch
    {
        Quarantine-State $State ("malformed_event:" + $_.Exception.Message)
    }
    finally
    {
        Update-PeaksAndAssertBounds $State
    }
}

function Get-RecordCanonical([object]$Record)
{
    return @(
        [string]$Record.ThreadId,
        [string]$Record.OriginStation,
        (@($Record.Participants) -join '>'),
        (@($Record.Domains) -join '>'),
        [string]$Record.OutcomeDomain,
        [string][long]$Record.SealedAt
    ) -join '|'
}

function Get-StateDigest([object]$State)
{
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("schema|$($State.SchemaVersion)")
    $lines.Add("quarantine|$([int][bool]$State.Quarantined)|$($State.QuarantineReason)")

    $tokens = @($State.Tokens | ForEach-Object {
        @(
            [string]$_.TokenId,
            [string]$_.RootId,
            [string]$_.OriginStation,
            [string]$_.CurrentStation,
            (@($_.Participants) -join '>'),
            (@($_.Domains) -join '>'),
            [string][int]$_.Depth,
            [string][long]$_.CreatedAt,
            [string][long]$_.LastAt,
            [string][long]$_.ExpiresAt
        ) -join '|'
    })
    foreach ($value in (Get-OrdinalSortedStrings $tokens)) { $lines.Add("token|$value") }

    foreach ($station in (Get-OrdinalSortedStrings @($State.Mailbox.Keys)))
    {
        $records = @($State.Mailbox[$station] | ForEach-Object { Get-RecordCanonical $_ })
        foreach ($value in (Get-OrdinalSortedStrings $records))
        {
            $lines.Add("mailbox|$station|$value")
        }
    }
    foreach ($station in (Get-OrdinalSortedStrings @($State.Ledger.Keys)))
    {
        $records = @($State.Ledger[$station] | ForEach-Object { Get-RecordCanonical $_ })
        foreach ($value in (Get-OrdinalSortedStrings $records))
        {
            $lines.Add("ledger|$station|$value")
        }
    }
    foreach ($station in (Get-OrdinalSortedStrings @($State.SealedTotals.Keys)))
    {
        $lines.Add("sealed-total|$station|$($State.SealedTotals[$station])")
    }
    foreach ($entry in @($State.Dedupe | ForEach-Object { "$($_.Id)|$($_.At)" }) |
        Get-OrdinalSortedStrings)
    {
        $lines.Add("dedupe|$entry")
    }
    foreach ($pair in (Get-OrdinalSortedStrings @($State.PairHistory.Keys)))
    {
        $lines.Add("pair|$pair|$($State.PairHistory[$pair])")
    }

    return Get-Sha256 ([string]::Join("`n", $lines))
}

function Invoke-Scenario([object]$Scenario)
{
    $script:activeLimits = [pscustomobject]@{
        activeTokensPerStation = [int]$config.limits.activeTokensPerStation
        mailboxPerStation = [int]$config.limits.mailboxPerStation
        ledgerPerStation = [int]$config.limits.ledgerPerStation
        dedupe = [int]$config.limits.dedupe
        pairHistory = [int]$config.limits.pairHistory
    }
    if (Test-Property $Scenario "limitOverrides")
    {
        foreach ($entry in @($Scenario.limitOverrides.PSObject.Properties))
        {
            if ($null -eq $activeLimits.PSObject.Properties[$entry.Name])
            {
                throw "$($Scenario.name) has an unknown limit override '$($entry.Name)'."
            }
            $activeLimits.$($entry.Name) = [int]$entry.Value
        }
    }
    foreach ($limit in @(
        [int]$activeLimits.activeTokensPerStation,
        [int]$activeLimits.mailboxPerStation,
        [int]$activeLimits.ledgerPerStation,
        [int]$activeLimits.dedupe,
        [int]$activeLimits.pairHistory
    ))
    {
        if ($limit -le 0)
        {
            throw "$($Scenario.name) has a non-positive active limit."
        }
    }

    $initialSchema = if (Test-Property $Scenario "initialSchemaVersion") {
        [int]$Scenario.initialSchemaVersion
    }
    else { [int]$config.schemaVersion }
    $state = New-ModelState $initialSchema
    if ($state.SchemaVersion -ne [int]$config.schemaVersion)
    {
        Quarantine-State $state "unknown_state_schema"
    }

    foreach ($event in @($Scenario.events))
    {
        Invoke-ModelEvent $state $event
    }
    Update-PeaksAndAssertBounds $state
    return [pscustomobject]@{
        State = $state
        Digest = Get-StateDigest $state
    }
}

function Get-TotalMapEntries([hashtable]$Map)
{
    $total = 0
    foreach ($value in @($Map.Values)) { $total += @($value).Count }
    return $total
}

function Get-TotalMapValues([hashtable]$Map)
{
    $total = 0
    foreach ($value in @($Map.Values)) { $total += [int]$value }
    return $total
}

function Assert-ExpectedMap(
    [string]$ScenarioName,
    [hashtable]$ActualMap,
    [object]$ExpectedMap,
    [string]$Label
)
{
    foreach ($entry in @($ExpectedMap.PSObject.Properties))
    {
        $actual = if ($ActualMap.ContainsKey([string]$entry.Name)) {
            [int]$ActualMap[[string]$entry.Name]
        }
        else { 0 }
        Assert-Model ($actual -eq [int]$entry.Value) `
            "$ScenarioName expected $Label '$($entry.Name)'=$($entry.Value); got $actual."
    }
}

function Assert-Scenario([object]$Scenario, [object]$Result)
{
    $name = [string]$Scenario.name
    $state = $Result.State
    $expect = $Scenario.expect
    $actual = @{
        quarantined = [bool]$state.Quarantined
        quarantineReason = [string]$state.QuarantineReason
        tokens = @($state.Tokens).Count
        mailbox = Get-TotalMapEntries $state.Mailbox
        ledger = Get-TotalMapEntries $state.Ledger
        sealedTotal = Get-TotalMapValues $state.SealedTotals
        accepted = [int]$state.Stats.Accepted
        rejected = [int]$state.Stats.Rejected
        duplicates = [int]$state.Stats.Duplicates
        ignored = [int]$state.Stats.Ignored
        expired = [int]$state.Stats.Expired
        sealed = [int]$state.Stats.Sealed
        reconciled = [int]$state.Stats.Reconciled
        peakTokensPerStation = [int]$state.Peaks.TokensPerStation
        peakMailboxPerStation = [int]$state.Peaks.MailboxPerStation
        peakLedgerPerStation = [int]$state.Peaks.LedgerPerStation
        digest = [string]$Result.Digest
    }

    foreach ($entry in @($expect.PSObject.Properties | Where-Object {
        $_.Name -notin @("reasonCounts", "mailboxStations", "ledgerStations", "sealedStations")
    }))
    {
        Assert-Model ($actual.ContainsKey([string]$entry.Name)) `
            "$name has an unsupported expectation '$($entry.Name)'."
        $expectedValue = $entry.Value
        if ($expectedValue -is [bool])
        {
            Assert-Model ([bool]$actual[$entry.Name] -eq [bool]$expectedValue) `
                "$name expected $($entry.Name)=$expectedValue; got $($actual[$entry.Name])."
        }
        elseif ($expectedValue -is [string])
        {
            Assert-Model ([string]$actual[$entry.Name] -ceq [string]$expectedValue) `
                "$name expected $($entry.Name)='$expectedValue'; got '$($actual[$entry.Name])'."
        }
        else
        {
            Assert-Model ([long]$actual[$entry.Name] -eq [long]$expectedValue) `
                "$name expected $($entry.Name)=$expectedValue; got $($actual[$entry.Name])."
        }
    }

    if (Test-Property $expect "reasonCounts")
    {
        Assert-ExpectedMap $name $state.ReasonCounts $expect.reasonCounts "reason count"
    }
    if (Test-Property $expect "mailboxStations")
    {
        $counts = @{}
        foreach ($key in @($state.Mailbox.Keys)) { $counts[$key] = @($state.Mailbox[$key]).Count }
        Assert-ExpectedMap $name $counts $expect.mailboxStations "mailbox station"
    }
    if (Test-Property $expect "ledgerStations")
    {
        $counts = @{}
        foreach ($key in @($state.Ledger.Keys)) { $counts[$key] = @($state.Ledger[$key]).Count }
        Assert-ExpectedMap $name $counts $expect.ledgerStations "ledger station"
    }
    if (Test-Property $expect "sealedStations")
    {
        Assert-ExpectedMap $name $state.SealedTotals $expect.sealedStations "sealed station"
    }
}

Assert-Model ([int]$config.schemaVersion -eq 1) "The reference model currently supports schema version 1 only."
Assert-Model ([int]$scenarioDocument.fixtureSchemaVersion -eq 1) `
    "The scenario document has an unsupported fixture schema."
Assert-Model ([int]$config.minimumEdges -ge 2) "A Thread must require at least two causal edges."
Assert-Model ([int]$config.maximumEdges -ge [int]$config.minimumEdges) "Maximum edge depth is invalid."
Assert-Model ([long]$config.tokenTtlSeconds -gt 0) "Token TTL must be positive."
Assert-Model ([long]$config.repeatedPairCooldownSeconds -gt 0) "Pair cooldown must be positive."
foreach ($limit in @(
    [int]$config.limits.activeTokensPerStation,
    [int]$config.limits.mailboxPerStation,
    [int]$config.limits.ledgerPerStation,
    [int]$config.limits.dedupe,
    [int]$config.limits.pairHistory
))
{
    Assert-Model ($limit -gt 0) "Every reference-model bound must be positive."
}

$scenarios = @($scenarioDocument.scenarios)
Assert-Model ($scenarios.Count -gt 0) "No Force Threads model scenarios were supplied."
$names = @($scenarios | ForEach-Object { [string]$_.name })
Assert-Model ((Get-OrdinalSortedStrings $names | Select-Object -Unique).Count -eq $names.Count) `
    "Force Threads scenario names must be unique."

$digestGroups = @{}
$results = [System.Collections.Generic.List[object]]::new()
foreach ($scenario in $scenarios)
{
    $name = Get-RequiredString $scenario "name"
    Assert-Model (Test-Property $scenario "events") "$name is missing its event table."
    Assert-Model (Test-Property $scenario "expect") "$name is missing its expectation table."

    $first = Invoke-Scenario $scenario
    $second = Invoke-Scenario $scenario
    Assert-Model ([string]$first.Digest -ceq [string]$second.Digest) `
        "$name did not produce a deterministic digest across identical replays."
    Assert-Scenario $scenario $first

    if (Test-Property $scenario "digestGroup")
    {
        $group = [string]$scenario.digestGroup
        if ($digestGroups.ContainsKey($group))
        {
            Assert-Model ([string]$digestGroups[$group] -ceq [string]$first.Digest) `
                "$name diverged from deterministic digest group '$group'."
        }
        else
        {
            $digestGroups[$group] = [string]$first.Digest
        }
    }

    $results.Add([pscustomobject]@{
        Name = $name
        Digest = [string]$first.Digest
        Tokens = @($first.State.Tokens).Count
        Mailbox = Get-TotalMapEntries $first.State.Mailbox
        Ledger = Get-TotalMapEntries $first.State.Ledger
        Quarantined = [bool]$first.State.Quarantined
    })
}

Write-Host "Reborn Force Threads reference model passed $($results.Count) table-driven scenarios."
$results | Format-Table -AutoSize
