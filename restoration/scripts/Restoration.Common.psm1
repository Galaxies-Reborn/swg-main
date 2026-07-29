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

function Get-Sha256HexFromBytes
{
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = $sha256.ComputeHash($Bytes)
    }
    finally
    {
        $sha256.Dispose()
    }

    return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
}

function Get-ByteSequenceCount
{
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [byte[]]$Sequence
    )

    if ($Sequence.Length -eq 0)
    {
        throw "Cannot count an empty byte sequence."
    }

    $count = 0
    $offset = 0
    while ($offset -le ($Bytes.Length - $Sequence.Length))
    {
        $matched = $true
        for ($index = 0; $index -lt $Sequence.Length; $index++)
        {
            if ($Bytes[$offset + $index] -ne $Sequence[$index])
            {
                $matched = $false
                break
            }
        }

        if ($matched)
        {
            $count++
            $offset += $Sequence.Length
        }
        else
        {
            $offset++
        }
    }

    return $count
}

function Replace-ByteSequenceOnce
{
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [byte[]]$OldSequence,

        [Parameter(Mandatory = $true)]
        [byte[]]$NewSequence
    )

    if ((Get-ByteSequenceCount -Bytes $Bytes -Sequence $OldSequence) -ne 1)
    {
        throw "Expected exactly one byte sequence occurrence before replacement."
    }

    $matchOffset = -1
    for ($offset = 0; $offset -le ($Bytes.Length - $OldSequence.Length); $offset++)
    {
        $matched = $true
        for ($index = 0; $index -lt $OldSequence.Length; $index++)
        {
            if ($Bytes[$offset + $index] -ne $OldSequence[$index])
            {
                $matched = $false
                break
            }
        }
        if ($matched)
        {
            $matchOffset = $offset
            break
        }
    }

    if ($matchOffset -lt 0)
    {
        throw "Byte sequence replacement offset was not found."
    }

    $replacementLength = $Bytes.Length - $OldSequence.Length + $NewSequence.Length
    $replacement = New-Object byte[] $replacementLength
    if ($matchOffset -gt 0)
    {
        [System.Array]::Copy($Bytes, 0, $replacement, 0, $matchOffset)
    }
    if ($NewSequence.Length -gt 0)
    {
        [System.Array]::Copy($NewSequence, 0, $replacement, $matchOffset, $NewSequence.Length)
    }
    $suffixOffset = $matchOffset + $OldSequence.Length
    $suffixLength = $Bytes.Length - $suffixOffset
    if ($suffixLength -gt 0)
    {
        [System.Array]::Copy(
            $Bytes,
            $suffixOffset,
            $replacement,
            $matchOffset + $NewSequence.Length,
            $suffixLength
        )
    }

    return $replacement
}

function ConvertTo-BigEndianBytes
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(4, 8)]
        [int]$Width,

        [Parameter(Mandatory = $true)]
        [UInt64]$Value
    )

    if ($Width -eq 4)
    {
        if ($Value -gt [UInt32]::MaxValue)
        {
            throw "Value $Value exceeds the unsigned 32-bit framing limit."
        }
        $bytes = [System.BitConverter]::GetBytes([UInt32]$Value)
    }
    else
    {
        $bytes = [System.BitConverter]::GetBytes([UInt64]$Value)
    }

    if ([System.BitConverter]::IsLittleEndian)
    {
        [System.Array]::Reverse($bytes)
    }
    return $bytes
}

function Write-BytesToStream
{
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $Stream.Write($Bytes, 0, $Bytes.Length)
}

function Get-MaterializationFingerprint
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string[]]$RelativePaths,

        [Parameter(Mandatory = $true)]
        [string]$Placeholder,

        [string]$InjectedFingerprint
    )

    if ([string]::IsNullOrWhiteSpace($Placeholder))
    {
        throw "Materialization fingerprint placeholder must not be empty."
    }
    if ($RelativePaths.Count -eq 0)
    {
        throw "Materialization fingerprint must include at least one ordered input."
    }
    if (-not [string]::IsNullOrEmpty($InjectedFingerprint) -and
        $InjectedFingerprint -cnotmatch '^[a-f0-9]{64}$')
    {
        throw "Injected materialization fingerprint must be a lowercase 64-character SHA-256 value."
    }

    $normalizedRoot = Resolve-NormalizedPath -Path $Root
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $placeholderBytes = $utf8.GetBytes($Placeholder)
    $fingerprintBytes = if ([string]::IsNullOrEmpty($InjectedFingerprint))
    {
        $null
    }
    else
    {
        $utf8.GetBytes($InjectedFingerprint)
    }

    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $inputRecords = @()
    $inputBytes = @()
    $ordinal = 0
    foreach ($relativePathValue in $RelativePaths)
    {
        $relativePath = [string]$relativePathValue
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            $relativePath.IndexOf('\') -ge 0 -or
            [System.IO.Path]::IsPathRooted($relativePath))
        {
            throw "Materialization input path must be a non-rooted, forward-slash path: '$relativePath'."
        }
        $segments = @($relativePath.Split('/'))
        if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0)
        {
            throw "Materialization input path contains an empty or traversal segment: '$relativePath'."
        }
        if (-not $seenPaths.Add($relativePath))
        {
            throw "Materialization input path is duplicated: '$relativePath'."
        }

        $absolutePath = Join-Path $normalizedRoot ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not (Test-PathWithin -Candidate $absolutePath -Parent $normalizedRoot) -or
            -not (Test-Path -LiteralPath $absolutePath -PathType Leaf))
        {
            throw "Materialization input is missing or outside its root: '$relativePath'."
        }

        [byte[]]$rawBytes = [System.IO.File]::ReadAllBytes($absolutePath)
        [byte[]]$canonicalInputBytes = $rawBytes
        if ([string]::IsNullOrEmpty($InjectedFingerprint))
        {
            $placeholderCount = Get-ByteSequenceCount -Bytes $rawBytes -Sequence $placeholderBytes
            if ($placeholderCount -ne 1)
            {
                throw "Materialization input '$relativePath' must contain exactly one fingerprint placeholder; found $placeholderCount."
            }
        }
        else
        {
            $placeholderCount = Get-ByteSequenceCount -Bytes $rawBytes -Sequence $placeholderBytes
            $fingerprintCount = Get-ByteSequenceCount -Bytes $rawBytes -Sequence $fingerprintBytes
            if ($placeholderCount -ne 0 -or $fingerprintCount -ne 1)
            {
                throw "Injected materialization input '$relativePath' must contain the fingerprint exactly once and no placeholder; found fingerprint=$fingerprintCount placeholder=$placeholderCount."
            }
            [byte[]]$canonicalInputBytes = @(
                Replace-ByteSequenceOnce -Bytes $rawBytes -OldSequence $fingerprintBytes -NewSequence $placeholderBytes
            )
        }

        $inputRecords += [pscustomobject][ordered]@{
            Ordinal = $ordinal
            Path = $relativePath
            SizeBytes = [UInt64]$canonicalInputBytes.Length
            Sha256 = Get-Sha256HexFromBytes -Bytes $canonicalInputBytes
            PlaceholderOccurrences = 1
        }
        $inputBytes += ,$canonicalInputBytes
        $ordinal++
    }

    $frame = New-Object System.IO.MemoryStream
    try
    {
        $magic = $utf8.GetBytes("SWG-PHASE-A-MATERIALIZATION-FINGERPRINT-V1")
        Write-BytesToStream -Stream $frame -Bytes (ConvertTo-BigEndianBytes -Width 4 -Value $magic.Length)
        Write-BytesToStream -Stream $frame -Bytes $magic
        Write-BytesToStream -Stream $frame -Bytes (ConvertTo-BigEndianBytes -Width 4 -Value $inputRecords.Count)
        for ($index = 0; $index -lt $inputRecords.Count; $index++)
        {
            $pathBytes = $utf8.GetBytes([string]$inputRecords[$index].Path)
            [byte[]]$contentBytes = $inputBytes[$index]
            Write-BytesToStream -Stream $frame -Bytes (ConvertTo-BigEndianBytes -Width 4 -Value $pathBytes.Length)
            Write-BytesToStream -Stream $frame -Bytes $pathBytes
            Write-BytesToStream -Stream $frame -Bytes (ConvertTo-BigEndianBytes -Width 8 -Value $contentBytes.Length)
            Write-BytesToStream -Stream $frame -Bytes $contentBytes
        }
        $framedBytes = $frame.ToArray()
    }
    finally
    {
        $frame.Dispose()
    }

    return [pscustomobject][ordered]@{
        Algorithm = "SHA-256"
        Framing = "u32be magicLength, UTF-8 magic SWG-PHASE-A-MATERIALIZATION-FINGERPRINT-V1, u32be inputCount, then per ordered input: u32be UTF-8 pathLength, path bytes, u64be contentLength, raw placeholder-form content bytes"
        Digest = Get-Sha256HexFromBytes -Bytes $framedBytes
        Inputs = @($inputRecords)
    }
}

function Set-MaterializationFingerprintToken
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Placeholder,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-f0-9]{64}$')]
        [string]$Fingerprint
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $placeholderBytes = $utf8.GetBytes($Placeholder)
    $fingerprintBytes = $utf8.GetBytes($Fingerprint)
    [byte[]]$rawBytes = [System.IO.File]::ReadAllBytes($Path)
    if ((Get-ByteSequenceCount -Bytes $rawBytes -Sequence $placeholderBytes) -ne 1 -or
        (Get-ByteSequenceCount -Bytes $rawBytes -Sequence $fingerprintBytes) -ne 0)
    {
        throw "Fingerprint injection requires exactly one placeholder and no existing fingerprint: $Path"
    }
    [byte[]]$injectedBytes = @(
        Replace-ByteSequenceOnce -Bytes $rawBytes -OldSequence $placeholderBytes -NewSequence $fingerprintBytes
    )
    [System.IO.File]::WriteAllBytes($Path, $injectedBytes)
}

function Get-RestorationAcceptanceBundle
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$RestorationRoot
    )

    $root = Resolve-NormalizedPath -Path $RestorationRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container))
    {
        throw "Restoration acceptance root not found: $root"
    }

    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
    $relativePaths = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -Force -File))
    {
        $absolutePath = Resolve-NormalizedPath -Path $file.FullName
        if (-not $absolutePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase))
        {
            throw "Restoration acceptance file escaped its root: $absolutePath"
        }

        $insidePath = $absolutePath.Substring($rootPrefix.Length).Replace(
            [System.IO.Path]::DirectorySeparatorChar,
            '/'
        )
        $segments = @($insidePath.Split('/'))
        if ($insidePath -ieq "materialization-fingerprint.json" -or
            @($segments | Where-Object { $_ -ieq ".git" }).Count -gt 0)
        {
            continue
        }
        $relativePaths += "restoration/$insidePath"
    }

    [string[]]$orderedPaths = @($relativePaths)
    [System.Array]::Sort($orderedPaths, [System.StringComparer]::Ordinal)
    $records = @()
    for ($index = 0; $index -lt $orderedPaths.Count; $index++)
    {
        $insidePath = $orderedPaths[$index].Substring("restoration/".Length)
        $absolutePath = Join-Path $root ($insidePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($absolutePath)
        $records += [pscustomobject][ordered]@{
            Ordinal = $index
            Path = $orderedPaths[$index]
            AbsolutePath = $absolutePath
            SizeBytes = [UInt64]$bytes.Length
            Sha256 = Get-Sha256HexFromBytes -Bytes $bytes
        }
    }

    return @($records)
}

Export-ModuleMember -Function @(
    "Resolve-NormalizedPath",
    "Test-PathWithin",
    "Invoke-GitChecked",
    "Get-RestorationManifest",
    "Assert-RestorationPins",
    "Import-SwgTab",
    "Get-Sha256HexFromBytes",
    "Get-MaterializationFingerprint",
    "Set-MaterializationFingerprintToken",
    "Get-RestorationAcceptanceBundle"
)
