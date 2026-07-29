param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14Core3OneHandSupportTerminal)) -Raw | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
function Rows([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $header = $lines[0] -split "`t", -1
    @($lines | Select-Object -Skip 2 | ConvertFrom-Csv -Delimiter "`t" -Header $header)
}
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
$fixturePath = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script/test/precu_headshot1_fixture.java"
$skillsPath = Join-Path $root "dsrc/sku.0/sys.shared/compiled/game/datatables/skill/skills.tab"
Assert (Test-Path -LiteralPath $fixturePath -PathType Leaf) "Missing M308 fixture"
Assert (Test-Path -LiteralPath $skillsPath -PathType Leaf) "Missing M308 skill table"
$skills = Rows $skillsPath
$novice = @($skills | Where-Object NAME -CEQ "combat_1hsword_novice")[0]
$one = @($skills | Where-Object NAME -CEQ "combat_1hsword_support_01")[0]
$two = @($skills | Where-Object NAME -CEQ "combat_1hsword_support_02")[0]
$three = @($skills | Where-Object NAME -CEQ "combat_1hsword_support_03")[0]
$four = @($skills | Where-Object NAME -CEQ "combat_1hsword_support_04")[0]
Assert ($novice.SKILLS_REQUIRED -ceq "combat_brawler_1handmelee_04" -and
    $one.SKILLS_REQUIRED -ceq "combat_1hsword_novice" -and
    [string]$one.COMMANDS -match "(^|,)melee1hBlindHit1(,|$)" -and
    $two.SKILLS_REQUIRED -ceq "combat_1hsword_support_01" -and
    [string]$two.SKILL_MODS -match "(^|,)combat_equillibrium=10(,|$)" -and
    [string]$two.SKILL_MODS -match "(^|,)onehandmelee_accuracy=30(,|$)" -and
    $three.SKILLS_REQUIRED -ceq "combat_1hsword_support_02" -and
    [string]$three.COMMANDS -match "(^|,)melee1hBlindHit2(,|$)" -and
    $four.SKILLS_REQUIRED -ceq "combat_1hsword_support_03" -and
    [string]$four.COMMANDS -match "(^|,)private_1hand_support_4(,|$)" -and
    [string]$four.SKILL_MODS -match "(^|,)combat_equillibrium=10(,|$)" -and
    [string]$four.SKILL_MODS -match "(^|,)onehandmelee_accuracy=30(,|$)") "M308 ownership chain drifted"
$fixture = Get-Content -LiteralPath $fixturePath -Raw
foreach ($token in @("ONE_HAND_SWORD_SUPPORT_FOUR",
    "ORIGINAL_ONE_HAND_SWORD_SUPPORT_FOUR", "armOneHandSupport",
    "oneHandSwordSupportFour=")) {
    Assert ($fixture.Contains($token)) "M308 fixture token missing: $token"
}
$overlay = Join-Path $restorationRoot "patches/dsrc/306-p14-core3-one-hand-support-terminal.patch"
Assert ([string]$contract.buildEvidence.overlaySha256 -ceq (Sha $overlay)) "M308 overlay hash drifted"
if ($Expectation -ceq "Ready") {
    Assert ([string]$contract.status -ceq "ready" -and
        [string]$contract.buildEvidence.result -ceq "passed" -and
        [string]$contract.runtimeEvidence.result -ceq "passed") "M308 is not Ready"
    $runtime = $contract.runtimeEvidence
    Assert ([bool]$runtime.admission.freshDualAuthentication -and
        [bool]$runtime.admission.oneHandSupportFour -and
        [int]$runtime.admission.canPerform.melee1hBlindHit2 -eq 0) "M308 admission proof missing"
    Assert ([string]$runtime.command.queueRemoval -ceq "Success" -and
        [int]$runtime.command.combatResult -eq 1 -and
        [int]$runtime.command.directDamage -gt 0 -and
        [string]$runtime.command.state.result -ceq "APPLIED") "M308 execution proof missing"
    Assert ([bool]$runtime.persistence.fullServerRestart -and
        [bool]$runtime.persistence.freshDualAuthentication -and
        [bool]$runtime.persistence.lifecycleSurvived -and
        [bool]$runtime.persistence.supportFourSurvived -and
        [bool]$runtime.persistence.terminalDiagnosticsSurvived -and
        [bool]$runtime.persistence.transientBlindAbsent) "M308 restart proof missing"
    Assert ([bool]$runtime.cleanup.restored -and [bool]$runtime.cleanup.idempotent -and
        [bool]$runtime.cleanup.temporaryOneHandSkillsAbsent -and
        [bool]$runtime.cleanup.temporaryCommandsAbsent -and
        [bool]$runtime.cleanup.postCleanupAbilityRejected -and
        [string]$runtime.cleanup.postCleanupQueueStatus -ceq "Ability") "M308 cleanup proof missing"
}
Write-Host "Publish 14.1 Core3 one-hand Support IV terminal contract passed."
