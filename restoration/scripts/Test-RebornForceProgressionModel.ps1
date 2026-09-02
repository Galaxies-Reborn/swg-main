[CmdletBinding()]
param(
    [string]$FixtureRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($FixtureRoot))
{
    $FixtureRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "fixtures/reborn-force-progression"
}
$config = Get-Content -LiteralPath (Join-Path $FixtureRoot "model-config.json") -Raw | ConvertFrom-Json
$document = Get-Content -LiteralPath (Join-Path $FixtureRoot "scenarios.json") -Raw | ConvertFrom-Json

function Test-Property([object]$Object, [string]$Name)
{
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function New-State
{
    return [pscustomobject]@{
        Events = [System.Collections.Generic.List[object]]::new()
        EventIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        LastHintAt = 0L
        HintsGranted = 0
        HintsDenied = 0
        ForceSensitive = $false
        LastBartenderRollAt = 0L
        BartenderHints = 0
        BartenderMisses = 0
        PointsEarned = 0
        PointsSpent = 0
        MigrationCredit = 0
        AwardIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        PurchaseIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        MasteredTrees = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        Accepted = 0
        Rejected = 0
        ReasonCounts = @{}
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

function Reject([object]$State, [string]$Reason)
{
    $State.Rejected++
    Add-Reason $State $Reason
}

function Get-TypeCount([object]$State, [string]$EventType)
{
    return @($State.Events | Where-Object { [string]$_.EventType -ceq $EventType }).Count
}

function Get-DistinctRoutes([object]$State)
{
    return @($State.Events | ForEach-Object { [string]$_.Route } | Sort-Object -Unique).Count
}

function Get-DistinctPlanets([object]$State)
{
    return @($State.Events |
        ForEach-Object { [string]$_.Planet } |
        Where-Object { $_ -cne "galactic" } |
        Sort-Object -Unique).Count
}

function Test-PreConvergence([object]$State)
{
    return (Get-TypeCount $State "ECHO") -ge [int]$config.required.echoes -and
        (Get-TypeCount $State "THREAD") -ge [int]$config.required.threads -and
        (Get-TypeCount $State "CONVERGENCE") -eq 0 -and
        (Get-DistinctRoutes $State) -ge [int]$config.required.routeFamilies -and
        (Get-DistinctPlanets $State) -ge [int]$config.required.planets
}

function Add-Event(
    [object]$State,
    [string]$Id,
    [string]$EventType,
    [string]$Route,
    [string]$Planet,
    [long]$At
)
{
    $normalizedType = $EventType.ToUpperInvariant()
    $normalizedRoute = $Route.ToUpperInvariant()
    $normalizedPlanet = $Planet.ToLowerInvariant()
    $normalizedId = $Id.ToLowerInvariant()

    foreach ($fragmentObject in @($config.legacyEventFragments))
    {
        if ($normalizedId.Contains([string]$fragmentObject))
        {
            Reject $State "legacy_event"
            return
        }
    }
    if ($State.EventIds.Contains($Id))
    {
        Reject $State "duplicate_event"
        return
    }
    if (@("ECHO", "THREAD", "CONVERGENCE") -cnotcontains $normalizedType -or
        @($config.routeFamilies | ForEach-Object { [string]$_ }) -cnotcontains $normalizedRoute -or
        @($config.creditablePlanets | ForEach-Object { [string]$_ }) -cnotcontains $normalizedPlanet -or
        $At -le 0)
    {
        Reject $State "invalid_event"
        return
    }
    if ($normalizedType -ceq "CONVERGENCE" -and -not (Test-PreConvergence $State))
    {
        Reject $State "convergence_prerequisites"
        return
    }
    if ($State.Events.Count -ge [int]$config.maximumObservedEvents)
    {
        Reject $State "event_capacity"
        return
    }

    [void]$State.EventIds.Add($Id)
    $State.Events.Add([pscustomobject]@{
        Id = $Id
        EventType = $normalizedType
        Route = $normalizedRoute
        Planet = $normalizedPlanet
        At = $At
    })
    $State.Accepted++
}

function Use-Hint([object]$State, [long]$At)
{
    if ($At -le 0 -or ($State.LastHintAt -gt 0 -and
        ($At -lt $State.LastHintAt -or $At - $State.LastHintAt -lt [long]$config.hintCooldownSeconds)))
    {
        $State.HintsDenied++
        Reject $State "hint_cooldown"
        return
    }
    $State.LastHintAt = $At
    $State.HintsGranted++
    $State.Accepted++
}

function Roll-Bartender([object]$State, [long]$At, [int]$Roll)
{
    if (-not $State.ForceSensitive)
    {
        $State.BartenderMisses++
        Reject $State "not_force_sensitive"
        return
    }
    if ($At -le 0 -or ($State.LastBartenderRollAt -gt 0 -and
        ($At -lt $State.LastBartenderRollAt -or $At - $State.LastBartenderRollAt -lt [long]$config.bartenderRollCooldownSeconds)))
    {
        $State.BartenderMisses++
        Reject $State "bartender_cooldown"
        return
    }
    $State.LastBartenderRollAt = $At
    $State.Accepted++
    if ($Roll -ge 1 -and $Roll -le [int]$config.bartenderHintChancePercent)
    {
        $State.BartenderHints++
    }
    else
    {
        $State.BartenderMisses++
        Add-Reason $State "bartender_roll_miss"
    }
}

function Award-Points([object]$State, [string]$Id, [int]$Points)
{
    if (-not $State.ForceSensitive)
    {
        Reject $State "not_force_sensitive"
        return
    }
    if ($State.AwardIds.Contains($Id))
    {
        Reject $State "duplicate_award"
        return
    }
    if ($Points -ne [int]$config.fsLearning.pointsPerQuestChain)
    {
        Reject $State "invalid_award"
        return
    }
    if ($State.AwardIds.Count -ge [int]$config.fsLearning.maximumQuestChains -or
        $State.PointsEarned + $Points -gt [int]$config.fsLearning.maximumPoints)
    {
        Reject $State "award_capacity"
        return
    }
    [void]$State.AwardIds.Add($Id)
    $State.PointsEarned += $Points
    $State.Accepted++
}

function Spend-Point([object]$State, [string]$Id)
{
    if ($State.PurchaseIds.Contains($Id))
    {
        Reject $State "duplicate_purchase"
        return
    }
    if (-not $State.ForceSensitive -or
        $State.PointsEarned + $State.MigrationCredit - $State.PointsSpent -lt [int]$config.fsLearning.pointsPerTierBox -or
        $State.PointsSpent -ge [int]$config.fsLearning.pointsRequired)
    {
        Reject $State "insufficient_fs_points"
        return
    }
    [void]$State.PurchaseIds.Add($Id)
    $State.PointsSpent += [int]$config.fsLearning.pointsPerTierBox
    $State.Accepted++
}

function Migrate-Legacy([object]$State, [int]$LearnedTierBoxes, [int]$UnlockedBranches)
{
    if (-not $State.ForceSensitive -or $LearnedTierBoxes -lt 0 -or $LearnedTierBoxes -gt [int]$config.fsLearning.pointsRequired -or
        $UnlockedBranches -lt 0 -or $UnlockedBranches -gt 16 -or $State.PurchaseIds.Count -gt 0)
    {
        Reject $State "invalid_migration"
        return
    }
    for ($index = 1; $index -le $LearnedTierBoxes; ++$index)
    {
        [void]$State.PurchaseIds.Add("legacy_fs_box_$index")
    }
    $State.PointsSpent = $LearnedTierBoxes
    $State.MigrationCredit = [Math]::Min([int]$config.fsLearning.pointsRequired, [Math]::Max($LearnedTierBoxes, $UnlockedBranches * 4))
    $State.Accepted++
}

function Master-Tree([object]$State, [string]$Tree)
{
    $validTrees = @("combat_prowess", "enhanced_reflexes", "crafting_mastery", "heightened_senses")
    if (-not $State.ForceSensitive -or $validTrees -cnotcontains $Tree -or $State.MasteredTrees.Contains($Tree))
    {
        Reject $State "invalid_tree_mastery"
        return
    }
    [void]$State.MasteredTrees.Add($Tree)
    $State.Accepted++
}

function Invoke-Action([object]$State, [object]$Action)
{
    switch ([string]$Action.type)
    {
        "event"
        {
            Add-Event $State ([string]$Action.id) ([string]$Action.eventType) ([string]$Action.route) ([string]$Action.planet) ([long]$Action.at)
        }
        "eventSeries"
        {
            $routes = @($Action.routes | ForEach-Object { [string]$_ })
            $planets = @($Action.planets | ForEach-Object { [string]$_ })
            if ($routes.Count -ne $planets.Count) { throw "eventSeries route/planet mismatch" }
            for ($index = 0; $index -lt $routes.Count; ++$index)
            {
                Add-Event $State (([string]$Action.prefix) + ($index + 1)) ([string]$Action.eventType) $routes[$index] $planets[$index] ([long]$Action.at + ([long]$Action.step * $index))
            }
        }
        "hint" { Use-Hint $State ([long]$Action.at) }
        "setForceSensitive" { $State.ForceSensitive = $true }
        "migrateLegacy" { Migrate-Legacy $State ([int]$Action.learnedTierBoxes) ([int]$Action.unlockedBranches) }
        "bartender" { Roll-Bartender $State ([long]$Action.at) ([int]$Action.roll) }
        "award" { Award-Points $State ([string]$Action.id) ([int]$Action.points) }
        "awardSeries"
        {
            for ($index = 1; $index -le [int]$Action.count; ++$index)
            {
                Award-Points $State (([string]$Action.prefix) + $index) ([int]$Action.points)
            }
        }
        "spend" { Spend-Point $State ([string]$Action.id) }
        "spendSeries"
        {
            for ($index = 1; $index -le [int]$Action.count; ++$index)
            {
                Spend-Point $State (([string]$Action.prefix) + $index)
            }
        }
        "masterTree" { Master-Tree $State ([string]$Action.tree) }
        default { throw "Unknown progression model action: $($Action.type)" }
    }
}

function Get-Result([object]$State)
{
    $eligible = (Get-TypeCount $State "ECHO") -ge [int]$config.required.echoes -and
        (Get-TypeCount $State "THREAD") -ge [int]$config.required.threads -and
        (Get-TypeCount $State "CONVERGENCE") -ge [int]$config.required.convergences -and
        (Get-DistinctRoutes $State) -ge [int]$config.required.routeFamilies -and
        (Get-DistinctPlanets $State) -ge [int]$config.required.planets
    return [pscustomobject]@{
        Events = $State.Events.Count
        Echoes = Get-TypeCount $State "ECHO"
        Threads = Get-TypeCount $State "THREAD"
        Convergences = Get-TypeCount $State "CONVERGENCE"
        Routes = Get-DistinctRoutes $State
        Planets = Get-DistinctPlanets $State
        Eligible = $eligible
        HintsGranted = $State.HintsGranted
        HintsDenied = $State.HintsDenied
        LastHintAt = $State.LastHintAt
        BartenderHints = $State.BartenderHints
        BartenderMisses = $State.BartenderMisses
        LastBartenderRollAt = $State.LastBartenderRollAt
        PointsEarned = $State.PointsEarned
        PointsSpent = $State.PointsSpent
        MigrationCredit = $State.MigrationCredit
        PointsAvailable = $State.PointsEarned + $State.MigrationCredit - $State.PointsSpent
        AwardIds = $State.AwardIds.Count
        PurchaseIds = $State.PurchaseIds.Count
        MasteredTrees = $State.MasteredTrees.Count
        PadawanReady = $State.ForceSensitive -and $State.MasteredTrees.Count -eq [int]$config.fsLearning.treeCount
        Accepted = $State.Accepted
        Rejected = $State.Rejected
        ReasonCounts = $State.ReasonCounts
    }
}

function Assert-Expected([string]$ScenarioName, [object]$Result, [object]$Expected)
{
    foreach ($property in @($Expected.PSObject.Properties))
    {
        if ($property.Name -ceq "reasonCounts") { continue }
        $actualProperty = $Result.PSObject.Properties[$property.Name.Substring(0, 1).ToUpperInvariant() + $property.Name.Substring(1)]
        if ($null -eq $actualProperty -or [string]$actualProperty.Value -cne [string]$property.Value)
        {
            throw "$ScenarioName expected $($property.Name)=$($property.Value), actual=$($actualProperty.Value)"
        }
    }
    if (Test-Property $Expected "reasonCounts")
    {
        foreach ($reasonProperty in @($Expected.reasonCounts.PSObject.Properties))
        {
            $actual = if ($Result.ReasonCounts.ContainsKey($reasonProperty.Name)) { [int]$Result.ReasonCounts[$reasonProperty.Name] } else { 0 }
            if ($actual -ne [int]$reasonProperty.Value)
            {
                throw "$ScenarioName expected reason $($reasonProperty.Name)=$($reasonProperty.Value), actual=$actual"
            }
        }
    }
}

if ([int]$config.schemaVersion -ne 1 -or [int]$document.fixtureSchemaVersion -ne 1)
{
    throw "Unsupported Force progression fixture schema."
}

Write-Host "Reborn Force progression reference model:"
foreach ($scenario in @($document.scenarios))
{
    $state = New-State
    foreach ($action in @($scenario.actions))
    {
        Invoke-Action $state $action
    }
    $result = Get-Result $state
    Assert-Expected ([string]$scenario.name) $result $scenario.expect
    Write-Host "  [PASS] $($scenario.name)"
}

Write-Host "Reborn Force progression reference model passed $(@($document.scenarios).Count) scenarios."
