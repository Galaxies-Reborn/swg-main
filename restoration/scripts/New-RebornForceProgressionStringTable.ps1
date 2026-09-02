[CmdletBinding()]
param(
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# This generator owns one additive table and cannot overwrite a stock table.
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputPath = Join-Path $root "serverdata/string/en/quest/force_sensitive/reborn_progression.stf"
$entries = [System.Collections.Generic.List[object]]::new()
$names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

$add = {
    param([string]$Name, [string]$Value)
    if (-not $names.Add($Name))
    {
        throw "Duplicate localized string name: $Name"
    }
    $entries.Add([pscustomobject]@{
        Id = [uint32]($entries.Count + 1)
        Name = $Name
        Value = $Value
    })
}

$common = [ordered]@{
    unavailable = "The trail is quiet for now. Return after you have reflected on what brought you here."
    convergence_locked = "You sense that this meeting belongs at the end of a path you have not yet walked."
    leave = "Leave the matter alone."
    accept = "Listen and offer to help."
    teach = "Ask what the experience revealed."
    quest_started = "The stranger gives you no instructions, only a problem and the uneasy sense that your choices matter."
    quest_wait = "Nothing more can be learned yet. Give the consequences of your choice time to settle."
    quest_advanced = "Something in the situation shifts. The next choice is yours."
    quest_wrong = "The moment closes around the wrong choice. You will need time before the path reveals itself again."
    quest_completed = "The task is complete. For an instant, the galaxy feels connected by threads you cannot see."
    mentor_taught = "The memory yields a new Force-sensitive insight."
    mentor_cannot_teach = "You do not yet have the Force Insight, prerequisite knowledge, or sensitivity needed for that lesson."
    mentor_ready = "Your shared experience contains a lesson you can now understand."
    mentor_branch_complete = "This experience has taught you everything it can. Other voices elsewhere in the galaxy still call to you."
    mentor_path_complete = "The stranger has nothing more to ask, but the memory of your choices remains strangely vivid."
    skill_learned = "You learn %TO."
    padawan_ready = "Every Force-sensitive discipline now answers you. A more demanding trial awaits."
    hint_cooldown = "Your next deliberate meditation will become clear in %DI day(s)."
    awakening = "You strongly feel the Force. It has been present in every choice that led you here."
    check_strong = "The Force answers you clearly."
    check_insight = "Force Insight available: %DI."
    check_trees = "Force-sensitive trees mastered: %DI of 4."
    check_ready = "Your training is complete enough to begin the Padawan trials."
    check_threshold = "Your path is drawing toward a final convergence."
    check_gathering = "Separate experiences are beginning to form a pattern."
    check_stirring = "You occasionally sense meaning beneath ordinary events."
    check_distant = "Something distant brushes the edge of your awareness."
    check_silent = "You feel no unusual connection to the Force."
    hint_route_service = "Seek someone whose ordinary burden can be eased without promise of reward."
    hint_route_discovery = "Follow a sign that sensible travelers have learned to ignore."
    hint_route_craft = "Find a broken thing whose fault cannot be measured by tools alone."
    hint_route_lore = "Listen for a story that persists even when its evidence disappears."
    hint_route_restraint = "Look for a danger that can be ended without feeding it violence."
    hint_route_fellowship = "A problem divided between strangers may require trust before skill."
    hint_planet = "Your path has become too familiar. Let another world's horizon unsettle your certainty."
    hint_thread = "You have noticed isolated moments. Now seek a choice whose consequences reach other lives."
    hint_convergence = "The paths you have walked now lean toward Mos Espa, where three hands wait over an unfinished machine."
    bartender_tree_0 = "A traveler said Force Insight is hiding in unfinished favors, not in a training hall."
    bartender_tree_1 = "Word is that one kind of discipline has started answering you. Fifteen other lessons are still scattered out there."
    bartender_tree_2 = "I heard the old village schedules do not matter anymore. People with the right stories can teach whenever you find them."
    bartender_tree_3 = "Someone passing through said a nearly trained wanderer should revisit the strangers whose lessons felt incomplete."
    bartender_trials = "A quiet patron swore the Padawan path opens only after every Force-sensitive discipline is mastered."
    migration_complete = "Your former Force-sensitive progress has settled into the new path. Learned disciplines were preserved, and prior Village discoveries became Force Insight credit."
}
foreach ($item in $common.GetEnumerator())
{
    & $add ([string]$item.Key) ([string]$item.Value)
}

$npcNames = [ordered]@{
    coronet_relief_manifest = "Talia Venn, Relief Quartermaster"
    moenia_quiet_ward = "Ione Pell, Night Orderly"
    bestine_dry_well = "Salo Ren, Water Clerk"
    narmle_marsh_rescue = "Veya Orin, Rescue Pilot"
    dantooine_forgotten_beacon = "Kelan Truun, Field Surveyor"
    endor_moonlit_tracks = "Rusk Tal, Trail Reader"
    yavin_echoing_stones = "Mira Doss, Stonecutter"
    lok_saltwind_compass = "Narev Senn, Dust Navigator"
    dearic_broken_harvester = "Pavo Lir, Harvester Mechanic"
    tyrena_signal_lens = "Cira Vos, Lens Grinder"
    kaadara_water_clock = "Oren Nahl, Clockmaker"
    wayfar_power_cell = "Jessa Morn, Cellwright"
    yavin_fragmented_archive = "Dema Quill, Fragment Archivist"
    dathomir_song_shards = "Arra Kesh, Verse Trader"
    nashal_droid_memory = "Perrin Vale, Memory Technician"
    restuss_weathered_tablets = "Sena Rhys, Tablet Historian"
    mos_eisley_unfired_blaster = "Daro Finn, Watchful Guard"
    nyms_debt_without_blood = "Kess Marr, Patient Collector"
    dathomir_night_test = "Doctor Vela Korr"
    bela_vistal_fevered_beast = "Toman Rei, Unarmed Ranger"
    endor_stranded_scout = "Ari Nox, Returning Scout"
    dantooine_shared_lights = "Pella Jorn, Settlement Lamplighter"
    theed_unheard_musician = "Nima Saye, Plaza Musician"
    mos_espa_three_hands = "Ralo Quist, Waiting Racer"
}
foreach ($item in $npcNames.GetEnumerator())
{
    & $add ("npc_" + $item.Key) ([string]$item.Value)
}

$questCues = [ordered]@{
    coronet_relief_manifest = "A quartermaster keeps recounting supplies that never reach the same total."
    moenia_quiet_ward = "A tired orderly asks for silence before asking for medicine."
    bestine_dry_well = "A water clerk insists a functioning well is dry on every official ledger."
    narmle_marsh_rescue = "A rescue pilot returns each night with one unused harness."
    dantooine_forgotten_beacon = "A surveyor hears a beacon that does not appear on the spectrum."
    endor_moonlit_tracks = "Tracks circle the outpost but never point toward it."
    yavin_echoing_stones = "A stonecutter discards pieces that ring before the hammer falls."
    lok_saltwind_compass = "A navigator's compass points away from every marked road."
    dearic_broken_harvester = "A mechanic refuses to replace a machine that only fails near its owner."
    tyrena_signal_lens = "A lens grinder has blueprints for a signal no receiver can detect."
    kaadara_water_clock = "A clock loses time only while someone is watching it."
    wayfar_power_cell = "A power cell arrives charged after being buried empty."
    yavin_fragmented_archive = "An archivist files blank fragments by the dreams they cause."
    dathomir_song_shards = "A trader pays for verses no singer remembers learning."
    nashal_droid_memory = "A droid recites a stranger's childhood when the sun sets."
    restuss_weathered_tablets = "A historian cleans tablets whose markings return with the rain."
    mos_eisley_unfired_blaster = "A guard offers a weapon and quietly hopes it is never fired."
    nyms_debt_without_blood = "A collector wants a debt settled without threats, credits, or bodies."
    dathomir_night_test = "A researcher needs protection from a creature she refuses to harm."
    bela_vistal_fevered_beast = "A ranger tracks a dangerous animal while carrying no ammunition."
    endor_stranded_scout = "Three scouts returned with two stories and one empty chair."
    dantooine_shared_lights = "Settlement lamps fail unless repaired by people who do not know one another."
    theed_unheard_musician = "A musician performs for someone who has never entered the plaza."
    mos_espa_three_hands = "A racer claims a repair requires three hands and no introductions."
}
foreach ($item in $questCues.GetEnumerator())
{
    & $add ("quest_" + $item.Key + "_cue") ([string]$item.Value)
}

$routes = [ordered]@{
    service = @(
        @("The need is greater than the supplies. What do you count first?", @("Who deserves blame", "Who will suffer without help", "What the work will pay")),
        @("One person can be helped immediately; many must wait. What guides you?", @("The harm I can prevent now", "The loudest demand", "The safest explanation")),
        @("No one will know who carried the burden. Why finish it?", @("To be remembered", "To collect a favor", "Because the burden remains"))
    )
    discovery = @(
        @("The instruments deny what your senses suggest. What do you trust?", @("Only the instrument", "Only the rumor", "The contradiction itself")),
        @("The trail turns away from every marked destination. What next?", @("Erase it", "Follow carefully and leave a way back", "Call it meaningless")),
        @("You find no treasure, only a changed understanding. Was the journey wasted?", @("No; discovery can change the seeker", "Yes; value must be carried", "Only witnesses decide"))
    )
    craft = @(
        @("A repair works until its owner returns. Where do you begin?", @("Observe the whole relationship", "Replace every part", "Blame the operator")),
        @("The correct blueprint produces the wrong result. What changes?", @("The goal", "Nothing", "The assumption behind the plan")),
        @("The device works, but not as you intended. What matters now?", @("Who gets credit", "Whether it serves without causing harm", "Whether the design stays secret"))
    )
    lore = @(
        @("A story survives while every record of it vanishes. What do you preserve?", @("Only the paper", "The meaning and the doubt", "A more convenient ending")),
        @("Two witnesses remember opposite truths. How do you listen?", @("Choose the stronger", "Dismiss them both", "Hold both accounts until the pattern appears")),
        @("Knowledge changes the person who receives it. Who owns it then?", @("No one entirely", "The first speaker", "The highest bidder"))
    )
    restraint = @(
        @("You have the power to end the threat immediately. What do you seek first?", @("A witness", "Permission", "A way to end the danger without creating another")),
        @("The opponent mistakes patience for weakness. How do you answer?", @("With control proportionate to the danger", "With overwhelming force", "By abandoning everyone")),
        @("The crisis passes and revenge is still possible. What remains to prove?", @("That fear works", "That you can let the moment end", "That you were stronger"))
    )
    fellowship = @(
        @("No single person has enough knowledge to solve the problem. What comes first?", @("Give each stranger a reason to trust", "Choose a leader in secret", "Hide the missing pieces")),
        @("One voice is being ignored because it is uncertain. What do you do?", @("Move on quickly", "Make room for it and test it together", "Speak for them without asking")),
        @("The shared work succeeds and credit cannot be divided cleanly. Who earned it?", @("The last person", "The planner", "Everyone who carried a necessary part"))
    )
}
foreach ($route in $routes.GetEnumerator())
{
    for ($stageIndex = 0; $stageIndex -lt 3; $stageIndex++)
    {
        $stage = $stageIndex + 1
        $definition = $route.Value[$stageIndex]
        & $add ("route_" + $route.Key + "_step_" + $stage) ([string]$definition[0])
        for ($choice = 0; $choice -lt 3; $choice++)
        {
            & $add ("route_" + $route.Key + "_step_" + $stage + "_choice_" + $choice) ([string]$definition[1][$choice])
        }
    }
}

function Get-Sha256([byte[]]$Bytes)
{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return -join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") })
    }
    finally
    {
        $sha.Dispose()
    }
}

function New-StringTableBytes
{
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream, [System.Text.Encoding]::UTF8, $true)
    try
    {
        $writer.Write([uint32]0xabcd)
        $writer.Write([byte]1)
        $writer.Write([uint32]($entries.Count + 1))
        $writer.Write([uint32]$entries.Count)

        foreach ($entry in $entries)
        {
            $valueBytes = [System.Text.Encoding]::Unicode.GetBytes([string]$entry.Value)
            $writer.Write([uint32]$entry.Id)
            $writer.Write([uint32]::MaxValue)
            $writer.Write([uint32]([string]$entry.Value).Length)
            $writer.Write($valueBytes)
        }

        [string[]]$sortedNames = @($entries | ForEach-Object { [string]$_.Name })
        [System.Array]::Sort($sortedNames, [System.StringComparer]::Ordinal)
        foreach ($name in $sortedNames)
        {
            $entry = $entries | Where-Object { $_.Name -ceq $name } | Select-Object -First 1
            $nameBytes = [System.Text.Encoding]::ASCII.GetBytes($name)
            $writer.Write([uint32]$entry.Id)
            $writer.Write([uint32]$nameBytes.Length)
            $writer.Write($nameBytes)
        }

        $writer.Flush()
        return $stream.ToArray()
    }
    finally
    {
        $writer.Dispose()
        $stream.Dispose()
    }
}

[byte[]]$expectedBytes = New-StringTableBytes
$expectedHash = Get-Sha256 $expectedBytes

if ($Check)
{
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf))
    {
        throw "Missing generated string table: $outputPath"
    }
    [byte[]]$actualBytes = [System.IO.File]::ReadAllBytes($outputPath)
    $actualHash = Get-Sha256 $actualBytes
    if ($actualBytes.Length -ne $expectedBytes.Length -or $actualHash -cne $expectedHash)
    {
        throw "Generated string table is stale. Expected $expectedHash, got $actualHash."
    }
    Write-Host "Verified $outputPath ($($actualBytes.Length) bytes, $($entries.Count) strings, sha256 $actualHash)."
    return
}

$outputDirectory = Split-Path -Parent $outputPath
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
[System.IO.File]::WriteAllBytes($outputPath, $expectedBytes)
Write-Host "Generated $outputPath ($($expectedBytes.Length) bytes, $($entries.Count) strings, sha256 $expectedHash)."
