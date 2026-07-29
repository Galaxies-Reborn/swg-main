[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restoration = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restoration "manifest.json") -Raw | ConvertFrom-Json
$contractPath = Join-Path $restoration $manifest.contracts.p14ImageDesignerLiveFixture
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$patchPath = Join-Path $restoration "patches/dsrc/011-p14-image-designer-live-fixture.patch"
$patch = Get-Content -LiteralPath $patchPath -Raw

if ($contract.status -ne "ready") { throw "Live fixture contract is not ready." }
if ($contract.script -ne "test.precu_image_designer_fixture") { throw "Unexpected fixture script." }
if ($contract.method -ne "executeFixture") { throw "Unexpected fixture method." }

$requiredTokens = @(
    "DESIGNER_OID = 44003778L",
    "DESIGNER_STATION_ID = 91001",
    "RECIPIENT_OID = 39008597L",
    "RECIPIENT_STATION_ID = 1001",
    "SALON_OID = 7106005L",
    'SALON_CELL = "r1"',
    'hasObjVar(salon, "salon")',
    "getGoodLocation(salon, SALON_CELL)",
    "setLocation(designer, designerDestination)",
    "setLocation(recipient, recipientDestination)",
    "error=salonMoveFailed",
    "setLocation(designer, designerOriginal)",
    "setLocation(recipient, recipientOriginal)",
    "error=fixtureRestoreFailed",
    "getLocationObjVar(designer, ORIGINAL_LOCATION)",
    "getLocationObjVar(recipient, ORIGINAL_LOCATION)",
    "removeObjVar(designer, ROOT)",
    "removeObjVar(recipient, ROOT)",
    'lifecycleId.matches("[a-f0-9]{32}")'
)
foreach ($token in $requiredTokens) {
    if (-not $patch.Contains($token)) { throw "Fixture patch is missing required token: $token" }
}

$forbiddenTokens = @("grantSkill(", "revokeSkill(", "setGroupObject(", "imagedesignStart(", "warpPlayer(")
foreach ($token in $forbiddenTokens) {
    if ($patch.Contains($token)) { throw "Fixture patch crosses its non-goal boundary: $token" }
}

[pscustomobject]@{
    Contract = $contract.script
    Status = "pass"
    Designer = $contract.identityBoundary.designer.objectId
    Recipient = $contract.identityBoundary.recipient.objectId
    Salon = $contract.salon.objectId
}
