param(
    [Parameter(Mandatory = $true)]
    [string]$ClientToolsRoot,

    [Parameter(Mandatory = $true)]
    [string]$ClientAssetsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$restorationRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $restorationRoot "manifest.json") -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath (Join-Path $restorationRoot ([string]$manifest.contracts.p14ProgressionSurfaceRetirement)) -Raw | ConvertFrom-Json
$toolsRoot = (Resolve-Path -LiteralPath $ClientToolsRoot).Path
$assetsRoot = (Resolve-Path -LiteralPath $ClientAssetsRoot).Path

$buttonBarPath = Join-Path $toolsRoot "src/game/client/library/swgClientUserInterface/src/shared/page/SwgCuiButtonBar.cpp"
$hudActionPath = Join-Path $toolsRoot "src/game/client/library/swgClientUserInterface/src/shared/page/SwgCuiHudAction.cpp"
$groundAssetPath = Join-Path $assetsRoot "ui/ui_ground_hud_buttonbar_skinned.inc"
$spaceAssetPath = Join-Path $assetsRoot "ui/ui_hud_space.inc"

foreach ($path in @($buttonBarPath, $hudActionPath, $groundAssetPath, $spaceAssetPath))
{
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        throw "Required progression-surface source is missing: $path"
    }
}

$buttonBar = Get-Content -LiteralPath $buttonBarPath -Raw
$hudAction = Get-Content -LiteralPath $hudActionPath -Raw

foreach ($needle in @(
    "hideNgeProgressionButton(m_roadmapButton)",
    "hideNgeProgressionButton(m_expertiseButton)",
    "button->SetEnabled(false)",
    "button->SetVisible(false)",
    "parent->SetEnabled(false)",
    "parent->SetVisible(false)"
))
{
    if (-not $buttonBar.Contains($needle))
    {
        throw "The client button-bar retirement contract is missing: $needle"
    }
}

if ($buttonBar.Contains("m_roadmapButton->GetParentWidget()->SetVisible(true)") -or
    $buttonBar.Contains("m_expertiseButton->GetParentWidget()->SetVisible(true)"))
{
    throw "The client can still re-enable an NGE progression button."
}

$roadmapStart = $hudAction.IndexOf("else if (id == CuiActions::roadmap)", [StringComparison]::Ordinal)
$expertiseStart = $hudAction.IndexOf("else if (id == CuiActions::expertise)", [StringComparison]::Ordinal)
$ticketStart = $hudAction.IndexOf("else if (id == CuiActions::ticketPurchase)", [StringComparison]::Ordinal)
if ($roadmapStart -lt 0 -or $expertiseStart -le $roadmapStart -or $ticketStart -le $expertiseStart)
{
    throw "Unable to isolate inherited progression actions."
}
$roadmapAction = $hudAction.Substring($roadmapStart, $expertiseStart - $roadmapStart)
$expertiseAction = $hudAction.Substring($expertiseStart, $ticketStart - $expertiseStart)
foreach ($action in @($roadmapAction, $expertiseAction))
{
    if (-not $action.Contains("CuiMediatorTypes::WS_Skills") -or
        $action.Contains("CuiMediatorTypes::WS_Roadmap") -or
        $action.Contains("CuiMediatorTypes::WS_Expertise"))
    {
        throw "An inherited progression action does not route exclusively to the Pre-CU Skills window."
    }
}

foreach ($assetPath in @($groundAssetPath, $spaceAssetPath))
{
    $asset = Get-Content -LiteralPath $assetPath -Raw
    foreach ($name in @("buttonRoadmapComposite", "buttonExpertiseComposite"))
    {
        $pattern = "(?s)<Composite\s+(?=[^>]*Name='$([regex]::Escape($name))')(?=[^>]*Visible='false')(?=[^>]*Enabled='false')[^>]*>"
        if (-not [regex]::IsMatch($asset, $pattern))
        {
            throw "$name is not retained, hidden, and disabled in $assetPath."
        }
    }
    foreach ($anchor in @("buttonRoadmap=", "buttonExpertise=", "effectorExpertise="))
    {
        if (-not $asset.Contains($anchor))
        {
            throw "Required CodeData anchor $anchor is missing from $assetPath."
        }
    }
}

$expectedToolsHashes = $contract.clientToolsPublication.sourceSha256
$expectedAssetHashes = $contract.clientAssetsPublication.sourceSha256
$hashChecks = @(
    @($buttonBarPath, [string]$expectedToolsHashes."SwgCuiButtonBar.cpp"),
    @($hudActionPath, [string]$expectedToolsHashes."SwgCuiHudAction.cpp"),
    @($groundAssetPath, [string]$expectedAssetHashes."ui_ground_hud_buttonbar_skinned.inc"),
    @($spaceAssetPath, [string]$expectedAssetHashes."ui_hud_space.inc")
)
foreach ($check in $hashChecks)
{
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $check[0]).Hash.ToLowerInvariant()
    if ($actual -cne $check[1])
    {
        throw "Progression-surface hash mismatch for $($check[0]). Expected $($check[1]), got $actual."
    }
}

Write-Host "Publish 14.1 progression-surface retirement contract passed."
