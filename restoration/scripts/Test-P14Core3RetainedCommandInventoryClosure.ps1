param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3RetainedCommandInventoryClosure)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
$commandPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/command/command_table.tab"
$skillsPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
Assert (Test-Path -LiteralPath $commandPath -PathType Leaf) "M330 command table missing"
Assert (Test-Path -LiteralPath $skillsPath -PathType Leaf) "M330 skills table missing"
$commandRows = Rows $commandPath
$skillRows = Rows $skillsPath
Assert ($commandRows.Count -eq [int]$contract.currentProduction.commandTableRows) "M330 command row count drifted"
Assert ($skillRows.Count -eq [int]$contract.currentProduction.skillsRows) "M330 skills row count drifted"
Assert ((Sha $commandPath) -ceq [string]$contract.currentProduction.commandTableSha256) "M330 command table hash drifted"
Assert ((Sha $skillsPath) -ceq [string]$contract.currentProduction.skillsSha256) "M330 skills table hash drifted"

$known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($row in $commandRows) { [void]$known.Add([string]$row.commandName) }
$patches = @(Get-ChildItem -LiteralPath (Join-Path $restorationRoot "patches/dsrc") -File -Filter "*.patch" |
    Where-Object { $_.BaseName -match '^(\d+)-' -and [int]$Matches[1] -ge 272 -and [int]$Matches[1] -le 327 } |
    Sort-Object Name)
Assert ($patches.Count -eq 56) "M330 overlay inventory drifted: $($patches.Count)"
$added = [System.Collections.Generic.List[string]]::new()
foreach ($patch in $patches) {
    $inCommandTable = $false
    foreach ($line in Get-Content -LiteralPath $patch.FullName) {
        if ($line.StartsWith("diff --git ")) {
            $inCommandTable = $line.Contains("/command_table.tab b/")
            continue
        }
        if ($inCommandTable -and $line.StartsWith("+") -and -not $line.StartsWith("+++")) {
            $name = ($line.Substring(1) -split "`t", 2)[0]
            if ($known.Contains($name)) { $added.Add($name) }
        }
    }
}
$addedUnique = @($added | Sort-Object -Unique)
Assert ($added.Count -eq 77 -and $addedUnique.Count -eq 77) "M330 patch-added command inventory drifted"
$audited = @($addedUnique + @($contract.auditBoundary.preexistingRowsRequiringLifecycle) | Sort-Object -Unique)
Assert ($audited.Count -eq 79) "M330 audited command inventory drifted: $($audited.Count)"

$prefixes = @{
    Brawler="combat_brawler_"; Rifleman="combat_rifleman_"; OneHandedSword="combat_1hsword_";
    Polearm="combat_polearm_"; BountyHunter="combat_bountyhunter_"; TwoHandedSword="combat_2hsword_";
    Unarmed="combat_unarmed_"; Smuggler="combat_smuggler_"; Pistol="combat_pistol_"; Marksman="combat_marksman_"
}
$expectedAll = [System.Collections.Generic.List[string]]::new()
foreach ($property in $contract.retainedOwnership.PSObject.Properties) {
    $category = $property.Name
    $commands = @($property.Value | ForEach-Object { [string]$_ })
    Assert ($commands.Count -eq [int]$contract.expectedCategoryCounts.$category) "M330 category count drifted: $category"
    foreach ($command in $commands) {
        $expectedAll.Add($command)
        $row = @($commandRows | Where-Object commandName -CEQ $command)
        Assert ($row.Count -eq 1) "M330 command missing or duplicated: $command"
        Assert ([string]$row[0].commandCategory -ceq "combat") "M330 combat command is not categorized as combat: $command"
        $owners = @($skillRows | Where-Object { @(([string]$_.COMMANDS -split ',') | ForEach-Object { $_.Trim() }) -ccontains $command })
        Assert ($owners.Count -gt 0) "M330 retained owner missing: $command"
        Assert (@($owners | Where-Object { ([string]$_.NAME).StartsWith($prefixes[$category], [System.StringComparison]::Ordinal) }).Count -gt 0) "M330 owner/category drifted: $command"
    }
}
$expectedUnique = @($expectedAll | Sort-Object -Unique)
Assert ($expectedAll.Count -eq 79 -and $expectedUnique.Count -eq 79) "M330 contract command inventory duplicated"
Assert (($audited -join ([char]0)) -ceq ($expectedUnique -join ([char]0))) "M330 overlay and contract inventories differ"

foreach ($command in @($contract.commandBrowserClassification.nonCombatExamples)) {
    $row = @($commandRows | Where-Object commandName -CEQ ([string]$command))
    Assert ($row.Count -eq 1) "M330 non-combat command missing or duplicated: $command"
    Assert ([string]$row[0].commandCategory -cne "combat") "M330 non-combat command is incorrectly categorized as combat: $command"
}

$readyContractTexts = [System.Collections.Generic.List[string]]::new()
foreach ($path in Get-ChildItem -LiteralPath (Join-Path $restorationRoot "contracts") -File -Filter "*.json") {
    if ($path.Name -ceq "p14-core3-retained-command-inventory-closure.json") { continue }
    $raw = Get-Content -LiteralPath $path.FullName -Raw
    $data = $raw | ConvertFrom-Json
    if ([string]$data.status -ceq "ready") { $readyContractTexts.Add($raw) }
}
foreach ($command in $expectedUnique) {
    Assert (@($readyContractTexts | Where-Object { $_.Contains($command) }).Count -gt 0) "M330 Ready contract evidence missing: $command"
}

if ($Expectation -ceq "Ready") {
    $directCommit = (& git -C (Join-Path $root "dsrc") rev-parse HEAD).Trim()
    Assert ([string]$contract.status -ceq "ready" -and [string]$contract.auditEvidence.result -ceq "passed") "M330 is not Ready"
    Assert ([int]$contract.auditBoundary.remainingCommands -eq 0 -and
        [bool]$contract.historicalAudit.publish12Verified -and
        [bool]$contract.historicalAudit.allCommandsPresentExactlyOnce -and
        [bool]$contract.currentProduction.allCommandsRegisteredExactlyOnce -and
        [bool]$contract.currentProduction.allCommandsRetainOwners -and
        [bool]$contract.commandBrowserClassification.allRetainedCommandsCategorizedCombat -and
        [bool]$contract.commandBrowserClassification.nonCombatExamplesRemainOther -and
        [bool]$contract.evidenceClosure.readyContractsVerified -and
        [bool]$contract.evidenceClosure.mcpEvidenceVerified) "M330 closure evidence missing"
    Assert ($LASTEXITCODE -eq 0 -and
        [string]$contract.deploymentEvidence.result -ceq "passed" -and
        [string]$contract.deploymentEvidence.directSourceCommit -ceq $directCommit -and
        [string]$contract.deploymentEvidence.architecture -like "ELF 64-bit*" -and
        [int]$contract.deploymentEvidence.javaSources -eq 5713 -and
        [int]$contract.deploymentEvidence.javaClasses -eq 5747 -and
        [string]$contract.deploymentEvidence.commandTableIffSha256 -match '^[a-f0-9]{64}$' -and
        [int]$contract.deploymentEvidence.commandTableIffBytes -gt 0 -and
        [bool]$contract.deploymentEvidence.clusterReadyForPlayers -and
        [int]$contract.deploymentEvidence.liveGameProcessCount -eq 15 -and
        [int]$contract.deploymentEvidence.livePlanetProcessCount -eq 15 -and
        [int]$contract.deploymentEvidence.liveGameProcessesMappedBuiltBinary -eq 15 -and
        [int]$contract.deploymentEvidence.readyMarkers -eq 1 -and
        [int]$contract.deploymentEvidence.suspiciousLogLines -eq 0 -and
        [int]$contract.deploymentEvidence.devShmEntries -eq 0) "M330 deployment evidence missing"
}
Write-Host "Publish 14.1 Core3 retained-command inventory closure passed."
