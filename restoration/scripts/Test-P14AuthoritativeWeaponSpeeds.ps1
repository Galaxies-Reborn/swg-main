[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "Restoration.Common.psm1") -Force
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14AuthoritativeWeaponSpeeds)) -Raw | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract
{
    param([bool]$Condition, [string]$Name)
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

$paths = @{}
foreach ($property in $contract.sourceFiles.psobject.Properties)
{
    $paths[[string]$property.Name] = Join-Path $source ([string]$property.Value)
}
foreach ($path in $paths.Values)
{
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) "p14.weapon-speed.source.$([IO.Path]::GetFileName($path))"
}

$speedRows = @(Import-SwgTab -Path $paths.weaponSpeeds)
$familyRows = @($speedRows | Where-Object { [string]$_.templateName -like "__family_*" })
$exactRows = @($speedRows | Where-Object { [string]$_.templateName -notlike "__family_*" })
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $paths.weaponSpeeds).Hash.ToLowerInvariant()

Write-Host "Publish 14 authoritative weapon-speed checks:"
Assert-Contract (@("implemented-build-pending", "ready") -contains [string]$contract.status) "p14.weapon-speed.status"
Assert-Contract ([string]$contract.semanticReference.weaponDataPinnedCommit -ceq "6ea64f60ef33b89121c2a8d188b93f4bc6f158e8") "p14.weapon-speed.core3-data-pin"
Assert-Contract ($exactRows.Count -eq 342 -and $familyRows.Count -eq 13 -and $speedRows.Count -eq 355) "p14.weapon-speed.row-cardinality"
Assert-Contract (($speedRows.templateName | Sort-Object -Unique).Count -eq $speedRows.Count) "p14.weapon-speed.unique-templates"
Assert-Contract ($hash -ceq [string]$contract.semanticReference.tableSha256) "p14.weapon-speed.table-hash"

foreach ($expected in $contract.representativeSpeeds.psobject.Properties)
{
    $row = @($speedRows | Where-Object { [string]$_.templateName -ceq [string]$expected.Name })
    Assert-Contract ($row.Count -eq 1 -and [Math]::Abs([double]$row[0].attackSpeed - [double]$expected.Value) -lt 0.000001) "p14.weapon-speed.representative.$([IO.Path]::GetFileNameWithoutExtension([string]$expected.Name))"
}

$weaponObject = Get-Content -LiteralPath $paths.weaponObject -Raw
$weaponHeader = Get-Content -LiteralPath $paths.weaponHeader -Raw
$commandQueue = Get-Content -LiteralPath $paths.commandQueue -Raw
$generator = Get-Content -LiteralPath (Join-Path $PSScriptRoot "Export-P14WeaponSpeeds.ps1") -Raw

Assert-Contract ($generator.Contains('6ea64f60ef33b89121c2a8d188b93f4bc6f158e8') -and
    $generator.Contains('Expected 342 positive, unique Core3 weapon speeds')) "p14.weapon-speed.generator-pinned"
Assert-Contract ($generator.Contains('(($lines -join "`n") + "`n")') -and
    -not $generator.Contains('WriteAllLines($output, $lines')) "p14.weapon-speed.generator-canonical-lf"
Assert-Contract ($weaponObject.Contains('cs_precuWeaponSpeedsTable = "datatables/combat/precu_weapon_speeds.iff"') -and
    $weaponObject.Contains('normalizePrecuAttackSpeed') -and
    $weaponObject.Contains('currentSpeed < authoritativeSpeed * 0.5f') -and
    ([regex]::Matches($weaponObject, [regex]::Escape('normalizePrecuAttackSpeed(*this);')).Count -eq 2)) "p14.weapon-speed.object-load-migration"
Assert-Contract ($weaponHeader.Contains('getStoredAttackTime(void) const') -and
    $weaponObject.Contains('float WeaponObject::getAttackTime() const') -and
    $weaponObject.Contains('float const currentSpeed = getStoredAttackTime();') -and
    $weaponObject.Contains('? authoritativeSpeed') -and
    $weaponObject.Contains(': currentSpeed;')) "p14.weapon-speed.runtime-fail-closed-accessor"
Assert-Contract ($commandQueue.Contains('cs_combatDataTable = "datatables/combat/combat_data.iff"') -and
    $commandQueue.Contains('return hitType == -1 || hitType == 6;') -and
    $commandQueue.Contains('speedMultiplier = 1.0f;') -and
    $commandQueue.Contains('weapon->getAttackTime(), speedMultiplier') -and
    -not $commandQueue.Contains('cs_precuWeaponProfilesTable')) "p14.weapon-speed.global-attack-routing"
Assert-Contract ($commandQueue.Contains('(1.0f - static_cast<float>(speedModifier) / 100.0f) *') -and
    $commandQueue.Contains('return executeTime > 1.0f ? executeTime : 1.0f;')) "p14.weapon-speed.core3-formula-and-floor"
Assert-Contract ($commandQueue.Contains('if (!owner.isPlayerControlled())') -and
    $commandQueue.Contains('return 2.0f;') -and
    [string]$contract.queuePolicy.aiAttack -match 'two-second Core3') "p14.weapon-speed.core3-ai-two-second-interval"

if ($failures.Count -gt 0)
{
    throw "Publish 14 authoritative weapon-speed contract failed: $($failures -join ', ')"
}

Write-Host "Publish 14 authoritative weapon-speed contract passed."
