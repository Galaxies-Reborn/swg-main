param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)

$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$combatBasePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/systems/combat/combat_base.java"
$headShotFixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$marksmanFixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_marksman_tier1_fixture.java"
$spamTablePath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/combat/precu_combat_spam.tab"

$combatBase = Get-Content -LiteralPath $combatBasePath -Raw
$headShotFixture = Get-Content -LiteralPath $headShotFixturePath -Raw
$marksmanFixture = Get-Content -LiteralPath $marksmanFixturePath -Raw
$spamTable = Get-Content -LiteralPath $spamTablePath

foreach ($required in @(
    'PRECU_COMBAT_SPAM = "datatables/combat/precu_combat_spam.iff"',
    'dataTableGetRow(PRECU_COMBAT_SPAM, actionData.actionName)',
    '!actionData.actionName.equals("creatureMeleeAttack")',
    '!actionData.actionName.equals("creatureRangedAttack")',
    'suffix = "_hit"',
    'suffix = "_miss"',
    'suffix = "_evade"',
    'suffix = "_counter"',
    'suffix = "_block"',
    'hitData[i].damage',
    'hitData[i].rawDamage',
    'new string_id("cbt_spam", spamStem + suffix)',
    'prose.setTU(pp, attackerData.id)',
    'prose.setTT(pp, defenderResults[i].id)',
    'prose.setDI(pp, damage)',
    'boolean creatureDefaultAttack =',
    'if (!creatureDefaultAttack)',
    'new string_id("cmd_n", actionData.actionName)',
    '"cmd_n:" + actionData.actionName',
    'else if (!sendPrecuCombatSpam(attackerData, defenderResults, hitData, actionData))',
    'combat.doBasicCombatSpam'
))
{
    if (-not $combatBase.Contains($required)) { throw "Combat-spam seam is missing: $required" }
}

$expectedRows = @(
    "creatureMeleeAttack`tcreature",
    "creatureRangedAttack`tcreature",
    "headShot1`theadshot",
    "bodyShot1`tbodyshot",
    "legShot1`tleg",
    "unarmedLunge1`tlungeshiak"
)
foreach ($expectedRow in $expectedRows)
{
    if ($spamTable -cnotcontains $expectedRow)
    {
        throw "Combat-spam mapping table lost its original row: $expectedRow"
    }
}

foreach ($required in @(
    'CDEF_CERTIFICATION = "cert_rifle_cdef"',
    'ORIGINAL_CDEF_CERTIFICATION',
    'grantCommand(attacker, CDEF_CERTIFICATION)',
    'revokeCommand(attacker, CDEF_CERTIFICATION)'
))
{
    if (-not $headShotFixture.Contains($required)) { throw "CDEF fixture ownership is missing: $required" }
}
foreach ($required in @(
    '" diagnosticSpamKey="',
    '"spam.key"',
    '" diagnosticSpamResult="',
    '"spam.result"',
    '" diagnosticSpamDamage="',
    '"spam.damage"'
))
{
    if (-not $marksmanFixture.Contains($required)) { throw "Combat-spam live diagnostic is missing: $required" }
}

if ($Expectation -eq "Ready")
{
    $contractPath = Join-Path $restorationRoot "contracts/p14-core3-combat-spam.json"
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.buildEvidence.javaCompile -ne "passed" -or
        $contract.buildEvidence.datatableCompile -ne "passed" -or
        $contract.buildEvidence.staticContract -ne "passed" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        $contract.runtimeEvidence.diagnosticSpamKey -ne "cmd_n:headShot1" -or
        -not $contract.runtimeEvidence.serverHealthy -or
        $contract.runtimeEvidence.fixtureCleanup -ne "passed")
    {
        throw "Core3 combat-spam evidence is not ready."
    }

    $patchPath = Join-Path $restorationRoot "patches/dsrc/200-p14-core3-combat-spam.patch"
    $text = [IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($bytes.Length -ne [int64]$contract.buildEvidence.scriptOverlayBytes -or
        $hash -ne [string]$contract.buildEvidence.scriptOverlaySha256)
    {
        throw "Combat-spam overlay evidence mismatch."
    }
}

Write-Host "Publish 14.1 Core3 combat-spam contract passed."
