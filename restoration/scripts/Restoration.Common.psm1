Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-NormalizedPath
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return $fullPath.TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ))
}

function Test-PathWithin
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate,

        [Parameter(Mandatory = $true)]
        [string]$Parent
    )

    $candidatePath = Resolve-NormalizedPath -Path $Candidate
    $parentPath = Resolve-NormalizedPath -Path $Parent
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    if ($candidatePath.Equals($parentPath, $comparison))
    {
        return $true
    }

    $prefix = $parentPath + [System.IO.Path]::DirectorySeparatorChar
    return $candidatePath.StartsWith($prefix, $comparison)
}

function Invoke-GitChecked
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    try
    {
        $ErrorActionPreference = "Continue"
        $gitOutput = & git -C $Repository @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $previousErrorAction
    }
    $text = [string]::Join(
        [System.Environment]::NewLine,
        @($gitOutput | ForEach-Object { $_.ToString() })
    ).Trim()

    if ($exitCode -ne 0)
    {
        throw "git -C '$Repository' $($Arguments -join ' ') failed ($exitCode): $text"
    }

    return $text
}

function Get-RestorationManifest
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$RestorationRoot
    )

    $manifestPath = Join-Path $RestorationRoot "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf))
    {
        throw "Restoration manifest not found: $manifestPath"
    }

    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Assert-RestorationPins
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [psobject]$Manifest,

        [switch]$RequireInitialized
    )

    $root = Resolve-NormalizedPath -Path $RepositoryRoot
    $results = @()

    foreach ($pin in @($Manifest.gitlinks))
    {
        $treeLine = Invoke-GitChecked -Repository $root -Arguments @(
            "ls-tree",
            "HEAD",
            "--",
            [string]$pin.path
        )
        $treeParts = @($treeLine -split "\s+")

        if (($treeParts.Count -lt 4) -or ($treeParts[0] -ne "160000") -or ($treeParts[1] -ne "commit"))
        {
            throw "Expected '$($pin.path)' to be a gitlink in $root; got '$treeLine'."
        }

        $actualGitlink = $treeParts[2]
        if ($actualGitlink -ne [string]$pin.commit)
        {
            throw "Gitlink drift for '$($pin.path)' in $root. Expected $($pin.commit), got $actualGitlink."
        }

        $worktreeCommit = $null
        if ($RequireInitialized)
        {
            $componentRoot = Join-Path $root ([string]$pin.path)
            if (-not (Test-Path -LiteralPath $componentRoot -PathType Container))
            {
                throw "Pinned component is not initialized: $componentRoot"
            }

            $worktreeCommit = Invoke-GitChecked -Repository $componentRoot -Arguments @(
                "rev-parse",
                "HEAD"
            )
            if ($worktreeCommit -ne [string]$pin.commit)
            {
                throw "Initialized component drift for '$($pin.path)'. Expected $($pin.commit), got $worktreeCommit."
            }
        }

        $results += [pscustomobject]@{
            Name = [string]$pin.name
            Gitlink = $actualGitlink
            Worktree = $worktreeCommit
        }
    }

    return $results
}

function Import-SwgTab
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "SWG data table not found: $Path"
    }

    $lines = [System.IO.File]::ReadAllLines((Resolve-NormalizedPath -Path $Path))
    if ($lines.Count -lt 2)
    {
        throw "SWG data table has no header/type rows: $Path"
    }

    $headers = $lines[0].Split([char]9)
    $dataLines = @($lines | Select-Object -Skip 2 | Where-Object { $_.Length -gt 0 })
    if ($dataLines.Count -eq 0)
    {
        return @()
    }

    return @($dataLines | ConvertFrom-Csv -Delimiter ([char]9) -Header $headers)
}

Export-ModuleMember -Function @(
    "Resolve-NormalizedPath",
    "Test-PathWithin",
    "Invoke-GitChecked",
    "Get-RestorationManifest",
    "Assert-RestorationPins",
    "Import-SwgTab"
)
