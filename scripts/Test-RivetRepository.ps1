function Test-RivetRepository {
    <#
    .SYNOPSIS
        Runs read-only rivet configuration and repository readiness checks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ConfigPath
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    function Add-Check([string]$Name, [bool]$Passed, [string]$Detail, [bool]$Required = $true) {
        $checks.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail; Required = $Required })
    }

    Add-Check 'PowerShell' ($PSVersionTable.PSVersion.Major -ge 7) $PSVersionTable.PSVersion.ToString()

    $git = Get-Command git -ErrorAction SilentlyContinue
    Add-Check 'Git' ($null -ne $git) $(if ($git) { (& git --version) } else { 'not installed' })

    try {
        $config = Get-RivetConfiguration -ConfigPath $ConfigPath
        Add-Check 'Configuration' $true 'valid'
    } catch {
        Add-Check 'Configuration' $false $_.Exception.Message
        $config = $null
    }

    $metadataPath = Resolve-RivetPath -RepositoryRoot $RepositoryRoot -ItemName 'repo_meta.json'
    Add-Check 'repo_meta.json' ([System.IO.File]::Exists($metadataPath)) 'repository metadata source'

    $inside = if ($git) { (& git -C $RepositoryRoot rev-parse --is-inside-work-tree 2>$null) -eq 'true' } else { $false }
    Add-Check 'Git worktree' $inside $RepositoryRoot

    if ($inside) {
        $gitUser = (& git -C $RepositoryRoot config user.name 2>$null)
        $gitEmail = (& git -C $RepositoryRoot config user.email 2>$null)
        $hasGitIdentity = -not [string]::IsNullOrWhiteSpace($gitUser) -and -not [string]::IsNullOrWhiteSpace($gitEmail)
        $identityDetail = if ($hasGitIdentity) { "$gitUser <$gitEmail>" } else { 'missing user.name or user.email' }
        Add-Check 'Git identity' $hasGitIdentity $identityDetail $false
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    $bun = Get-Command bun -ErrorAction SilentlyContinue
    $hasBunConfig = [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'bunfig.toml')) -or [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'bun.lock'))
    if ($hasBunConfig) {
        Add-Check 'Bun runtime' ($null -ne $bun) $(if ($bun) { (& bun --version) } else { 'bunfig.toml/bun.lock present but bun not found in PATH' }) $true
    } elseif ($null -ne $bun) {
        Add-Check 'Bun runtime' $true (& bun --version) $false
    }
    if ($null -ne $node) {
        Add-Check 'Node.js runtime' $true (& node --version) $false
    } elseif (-not $hasBunConfig) {
        Add-Check 'Node.js runtime' $false 'node not found in PATH' $false
    }

    foreach ($name in @('package.json', 'jsr.jsonc', 'README.md', 'CHANGELOG.md', 'release-notes.md')) {
        Add-Check $name ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, $name))) 'required repository file'
    }

    $pkgPath = [System.IO.Path]::Combine($RepositoryRoot, 'package.json')
    $jsrPath = [System.IO.Path]::Combine($RepositoryRoot, 'jsr.jsonc')
    if ([System.IO.File]::Exists($pkgPath) -and [System.IO.File]::Exists($jsrPath)) {
        try {
            $pkgJson = [System.IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json
            $jsrText = [System.IO.File]::ReadAllText($jsrPath)
            $jsrMatch = [regex]::Match($jsrText, '"version"\s*:\s*"([^"]+)"')
            $pkgVer = [string]$pkgJson.version
            $jsrVer = if ($jsrMatch.Success) { $jsrMatch.Groups[1].Value } else { $null }
            $versionsMatch = ($pkgVer -eq $jsrVer) -and -not [string]::IsNullOrWhiteSpace($pkgVer)
            Add-Check 'Manifest versions' $versionsMatch $(if ($versionsMatch) { "$pkgVer (in sync)" } else { "package.json ($pkgVer) != jsr.jsonc ($jsrVer)" }) $true
        } catch {
            Add-Check 'Manifest versions' $false $_.Exception.Message $false
        }
    }

    $hasLock = [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'package-lock.json')) -or [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'bun.lock'))
    $lockDetail = if ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'bun.lock'))) { 'bun.lock present' } elseif ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'package-lock.json'))) { 'package-lock.json present' } else { 'no lockfile found' }
    Add-Check 'Lockfile' $hasLock $lockDetail $false

    if ($null -ne $config) {
        $tokenName = [string]$config.gitlab.tokenEnvironmentVariable
        Add-Check 'GitLab token' (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($tokenName))) "optional environment variable $tokenName" $false
        $typeNames = @($config.commit.types.name)
        $scopeNames = @($config.commit.scopes.name)
        Add-Check 'Commit defaults' ($config.commit.defaultType -in $typeNames -and $config.commit.defaultScope -in $scopeNames) 'default type and scope exist in their catalogs'
        try {
            $readmeResult = Test-ReadmeStructure -RepositoryRoot $RepositoryRoot -ConfigPath $ConfigPath -Quiet
            Add-Check 'README requirements' $readmeResult.Ready "$(@($readmeResult.Requirements).Count - @($readmeResult.Missing).Count)/$(@($readmeResult.Requirements).Count) required headings"
        } catch {
            Add-Check 'README requirements' $false $_.Exception.Message
        }
    }

    [Console]::WriteLine((Format-AnsiText -Text 'RIVET DOCTOR' -Color @(0, 200, 255) -Bold))
    foreach ($check in $checks) {
        $state = if ($check.Passed) { 'OK  ' } elseif (-not $check.Required) { 'WARN' } else { 'FAIL' }
        $color = if ($check.Passed) { @(80, 220, 150) } elseif (-not $check.Required) { @(255, 195, 75) } else { @(255, 90, 105) }
        [Console]::WriteLine("  $(Format-AnsiText -Text $state -Color $color -Bold)  $($check.Name) | $($check.Detail)")
    }
    $failed = @($checks | Where-Object { -not $_.Passed -and $_.Required })
    return [pscustomobject]@{ Ready = $failed.Count -eq 0; Checks = $checks.ToArray(); Failures = $failed }
}
