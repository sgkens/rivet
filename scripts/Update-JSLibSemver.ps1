function Update-JSLibSemver {
    <#
    .SYNOPSIS
        Synchronizes package.json, jsr.jsonc, and the root package-lock.json
        package identity to one SemVer version.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
        [string]$Version,
        [string]$RepositoryRoot = (Get-Location).Path,
        [switch]$DryRun
    )

    $ErrorActionPreference = 'Stop'
    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $versionInfo = Get-ConventionalCommitVersion -RepositoryRoot $repositoryPath
        $Version = $versionInfo.Version
    }

    foreach ($relativePath in @('package.json', 'jsr.jsonc')) {
        $path = [System.IO.Path]::Combine($repositoryPath, $relativePath)
        if (-not [System.IO.File]::Exists($path)) { throw "Required version file not found: $path" }
        $content = [System.IO.File]::ReadAllText($path)
        $pattern = if ($relativePath -eq 'package.json') {
            '(?s)^(\s*\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"version"\s*:\s*)"[^"]+"'
        } else {
            '("version"\s*:\s*)"[^"]+"'
        }
        $versionMatches = [regex]::Matches($content, $pattern)
        if ($versionMatches.Count -ne 1) { throw "Expected one top-level version field in '$relativePath'; found $($versionMatches.Count)." }
        $updated = [regex]::Replace($content, $pattern, "`$1`"$Version`"", 1)
        if ($updated -eq $content) {
            Write-Output "$relativePath already uses $Version"
            continue
        }
        if ($DryRun) {
            Write-Output "Would update $relativePath to $Version"
        } elseif ($PSCmdlet.ShouldProcess($path, "Set version to $Version")) {
            [System.IO.File]::WriteAllText($path, $updated, [System.Text.UTF8Encoding]::new($false))
            Write-Output "Updated $relativePath to $Version"
        }
    }

    $lockPath = [System.IO.Path]::Combine($repositoryPath, 'package-lock.json')
    if ([System.IO.File]::Exists($lockPath)) {
        $lockContent = [System.IO.File]::ReadAllText($lockPath)
        $rootPattern = '(?m)^(  "version"\s*:\s*")[^"]+("\s*,)$'
        $packagePattern = '(?ms)("packages"\s*:\s*\{\s*""\s*:\s*\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"version"\s*:\s*")[^"]+("\s*,)'
        if (-not [regex]::IsMatch($lockContent, $rootPattern) -or -not [regex]::IsMatch($lockContent, $packagePattern)) {
            throw "Unable to locate root package versions in 'package-lock.json'."
        }
        $updatedLock = [regex]::Replace($lockContent, $rootPattern, "`${1}$Version`${2}", 1)
        $updatedLock = [regex]::Replace($updatedLock, $packagePattern, "`${1}$Version`${2}", 1)
        if ($updatedLock -eq $lockContent) {
            Write-Output "package-lock.json already uses $Version"
        } elseif ($DryRun) {
            Write-Output "Would update package-lock.json to $Version"
        } elseif ($PSCmdlet.ShouldProcess($lockPath, "Set root package versions to $Version")) {
            [System.IO.File]::WriteAllText($lockPath, $updatedLock, [System.Text.UTF8Encoding]::new($false))
            Write-Output "Updated package-lock.json to $Version"
        }
    }
}
