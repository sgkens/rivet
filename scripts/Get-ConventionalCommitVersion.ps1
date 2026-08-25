function Get-ConventionalCommitVersion {
    <#
    .SYNOPSIS
        Calculates the next SemVer version from Conventional Commits.
    .DESCRIPTION
        Finds the nearest SemVer tag reachable from HEAD, scans commits since
        that tag, and applies every Conventional Commit bump in sequence. This
        preserves the canonical Get-ConventionalCommitVersion behavior.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string[]]$MinorTypes = @('feat'),
        [string[]]$PatchTypes = @('fix', 'perf'),
        [string]$RepositoryRoot = (Get-Location).Path
    )

    $ErrorActionPreference = 'Stop'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is required to calculate the repository version.'
    }

    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $tagOutput = @(& git -C $repositoryPath describe --tags --abbrev=0 2>$null)
    $lastTag = if ($LASTEXITCODE -eq 0 -and $tagOutput.Count -gt 0) { [string]$tagOutput[0] } else { $null }

    if ($lastTag -and $lastTag -match '^v(\d+)\.(\d+)\.(\d+)(?:-release)?$') {
        [int]$major = $Matches[1]
        [int]$minor = $Matches[2]
        [int]$patch = $Matches[3]
        $range = "$lastTag..HEAD"
    } else {
        [int]$major = 0
        [int]$minor = 1
        [int]$patch = 0
        $range = $null
    }

    $logArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @('-C', $repositoryPath, 'log', '--no-color', '--format=%s%x1f%b%x1e')) {
        $logArguments.Add($argument)
    }
    if ($range) { $logArguments.Add($range) }
    $rawLog = (& git @logArguments) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Unable to read Git history from '$repositoryPath'." }

    $minorLookup = [System.Collections.Generic.HashSet[string]]::new($MinorTypes, [System.StringComparer]::OrdinalIgnoreCase)
    $patchLookup = [System.Collections.Generic.HashSet[string]]::new($PatchTypes, [System.StringComparer]::OrdinalIgnoreCase)
    $bumpType = 'none'
    $commitsScanned = 0

    foreach ($commit in ($rawLog -split [char]0x1e)) {
        if ([string]::IsNullOrWhiteSpace($commit)) { continue }
        $commitsScanned++
        $parts = $commit -split [char]0x1f, 2
        $subject = $parts[0].Trim()
        $body = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $parsedCommit = ConvertFrom-ConventionalCommit -Subject $subject -Body $body

        if ($parsedCommit.Breaking) {
            $major++
            $minor = 0
            $patch = 0
            $bumpType = 'major'
            continue
        }
        if ($parsedCommit.IsConventional -and $minorLookup.Contains($parsedCommit.Type)) {
            $minor++
            $patch = 0
            if ($bumpType -ne 'major') { $bumpType = 'minor' }
            continue
        }
        if ($parsedCommit.IsConventional -and $patchLookup.Contains($parsedCommit.Type)) {
            $patch++
            if ($bumpType -eq 'none') { $bumpType = 'patch' }
        }
    }

    [PSCustomObject]@{
        Version        = "$major.$minor.$patch"
        LastTag        = $lastTag
        CommitsScanned = $commitsScanned
        BumpType       = $bumpType
    }
}
