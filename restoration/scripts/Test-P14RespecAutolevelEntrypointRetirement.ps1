[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [ValidateSet("Build", "Ready")][string]$Expectation = "Build"
)
$ErrorActionPreference = "Stop"
$restorationRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$files = [ordered]@{
    "respecseller.java" = "dsrc/sku.0/sys.server/compiled/game/script/conversation/respecseller.java"
    "click_combat_token.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/respec/click_combat_token.java"
    "antidecay.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/veteran_reward/antidecay.java"
    "auto_level.java" = "dsrc/sku.0/sys.server/compiled/game/script/systems/skills/auto_level.java"
    "base_player.java" = "dsrc/sku.0/sys.server/compiled/game/script/player/base/base_player.java"
}
$text = [ordered]@{}
foreach ($entry in $files.GetEnumerator())
{
    $text[$entry.Key] = Get-Content -LiteralPath (Join-Path $root $entry.Value) -Raw
}
$guards = [ordered]@{
    "respecseller.java" = [pscustomobject]@{ Helper = "isNgeRespecSellerEnabled"; Count = 5 }
    "click_combat_token.java" = [pscustomobject]@{ Helper = "isNgeCombatRespecTokenEnabled"; Count = 2 }
    "antidecay.java" = [pscustomobject]@{ Helper = "isNgeAntidecayRespecEnabled"; Count = 2 }
    "auto_level.java" = [pscustomobject]@{ Helper = "isNgeAutoLevelItemEnabled"; Count = 3 }
}
foreach ($entry in $guards.GetEnumerator())
{
    $helper = $entry.Value.Helper
    $body = $text[$entry.Key]
    if (-not $body.Contains("private static boolean $helper()") -or
        -not $body.Contains("if (!$helper())") -or
        ([regex]::Matches($body, [regex]::Escape("if (!$helper())"))).Count -ne $entry.Value.Count)
    {
        throw "Fail-closed entrypoint count is wrong for $($entry.Key)."
    }
    $start = $body.IndexOf("private static boolean $helper()")
    $end = $body.IndexOf("`n    }", $start)
    if ($start -lt 0 -or $end -le $start -or
        -not $body.Substring($start, $end - $start).Contains("return false;"))
    {
        throw "$helper does not fail closed."
    }
}
$base = $text["base_player.java"]
foreach ($forbidden in @(
    "respec.handleNpcRespec(self, skillTemplateName)",
    "respec.earnProfessionSkills(self, skillTemplateName",
    "static_item.decrementStaticItem(token)",
    "messageTo(self, `"finishEntertainerRespec`"",
    "setSkillTemplate(self, `"entertainer_1a`")",
    "setSkillTemplate(self, newTemplate)"
))
{
    if ($base.Contains($forbidden))
    {
        throw "Base-player NGE template mutation remains: $forbidden"
    }
}
foreach ($required in @(
    'removeObjVar(self, "clickRespec")',
    'removeObjVar(self, "npcRespec")',
    'detachScript(self, "systems.respec.click_combat_respec")',
    "A queued pre-restoration NGE callback must not rewrite skill boxes."
))
{
    if (-not $base.Contains($required))
    {
        throw "Base-player compatibility cleanup is missing: $required"
    }
}
$scriptRoot = Join-Path $root "dsrc/sku.0/sys.server/compiled/game/script"
$expectedByPath = [ordered]@{
    "base_class.java" = 3
    "library/dump.java" = 1
    "library/qa.java" = 1
    "library/respec.java" = 9
    "library/skill_template.java" = 3
    "library/utils.java" = 1
    "player/live_conversions.java" = 2
    "player/base/base_player.java" = 1
    "player/player_utility.java" = 2
    "terminal/terminal_character_builder.java" = 2
    "test/dwhite_test.java" = 1
    "test/precu_marksman_tier1_fixture.java" = 5
    "test/qa_character.java" = 2
    "test/qaitem.java" = 1
    "test/qaxp.java" = 1
    "test/thicks_test.java" = 1
    "working/ahunter/my_script.java" = 2
    "working/jbenjtest.java" = 3
}
$actualByPath = @{}
Get-ChildItem -LiteralPath $scriptRoot -Recurse -Filter "*.java" | ForEach-Object {
    $count = ([regex]::Matches(
        (Get-Content -LiteralPath $_.FullName -Raw),
        [regex]::Escape("getSkillTemplate("))).Count
    if ($count -gt 0)
    {
        $relative = $_.FullName.Substring($scriptRoot.Length + 1).Replace("\", "/")
        $actualByPath[$relative] = $count
    }
}
if (($actualByPath.Values | Measure-Object -Sum).Sum -ne 41)
{
    throw "Residual skill-template reference total changed."
}
$actualPaths = (($actualByPath.Keys | Sort-Object) -join "`n")
$expectedPaths = (($expectedByPath.Keys | Sort-Object) -join "`n")
if ($actualPaths -cne $expectedPaths)
{
    throw "Residual skill-template reference path inventory changed."
}
foreach ($entry in $expectedByPath.GetEnumerator())
{
    if ($actualByPath[$entry.Key] -ne $entry.Value)
    {
        throw "Residual reference count changed for $($entry.Key)."
    }
}
if ($Expectation -eq "Ready")
{
    $contract = Get-Content -LiteralPath (Join-Path $restorationRoot "contracts/p14-respec-autolevel-entrypoint-retirement.json") -Raw | ConvertFrom-Json
    if ($contract.status -ne "ready" -or
        $contract.runtimeEvidence.result -ne "passed" -or
        -not $contract.runtimeEvidence.serverHealthy)
    {
        throw "Runtime evidence is not ready."
    }
    foreach ($entry in $files.GetEnumerator())
    {
        $path = Join-Path $root $entry.Value
        $bytes = [Text.Encoding]::UTF8.GetBytes(
            ([IO.File]::ReadAllText($path) -replace "`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try
        {
            $actual = ([BitConverter]::ToString(
                $sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
        }
        finally
        {
            $sha.Dispose()
        }
        if ($actual -ne $contract.buildEvidence.sourceSha256.($entry.Key))
        {
            throw "Source evidence mismatch: $($entry.Key)"
        }
    }
    $patchPath = Join-Path $restorationRoot "patches/dsrc/166-p14-respec-autolevel-entrypoint-retirement.patch"
    $bytes = [Text.Encoding]::UTF8.GetBytes(
        ([IO.File]::ReadAllText($patchPath) -replace "`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = ([BitConverter]::ToString(
            $sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally
    {
        $sha.Dispose()
    }
    if ($bytes.Length -ne $contract.buildEvidence.overlayPatchBytes -or
        $hash -ne $contract.buildEvidence.overlayPatchSha256)
    {
        throw "Patch evidence mismatch."
    }
}
Write-Host "Publish 14.1 respec/auto-level entrypoint retirement contract passed."
