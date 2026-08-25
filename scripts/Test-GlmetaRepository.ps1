function Test-GlmetaRepository {
    <#
    .SYNOPSIS
        Runs read-only glmeta configuration and repository readiness checks.
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
    try { $config = Get-GlmetaConfiguration -ConfigPath $ConfigPath; Add-Check 'Configuration' $true 'valid' } catch { Add-Check 'Configuration' $false $_.Exception.Message; $config = $null }
    $metadataPath = [System.IO.Path]::Combine($RepositoryRoot, 'repo_meta.json')
    Add-Check 'repo_meta.json' ([System.IO.File]::Exists($metadataPath)) 'repository metadata source'
    $inside = if ($git) { (& git -C $RepositoryRoot rev-parse --is-inside-work-tree 2>$null) -eq 'true' } else { $false }
    Add-Check 'Git worktree' $inside $RepositoryRoot
    foreach ($name in @('package.json', 'jsr.jsonc', 'README.md', 'CHANGELOG.md', 'release-notes.md')) {
        Add-Check $name ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, $name))) 'required repository file'
    }
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
    [Console]::WriteLine((Format-AnsiText -Text 'GLMETA DOCTOR' -Color @(0, 200, 255) -Bold))
    foreach ($check in $checks) {
        $state = if ($check.Passed) { 'OK  ' } elseif (-not $check.Required) { 'WARN' } else { 'FAIL' }
        $color = if ($check.Passed) { @(80, 220, 150) } elseif (-not $check.Required) { @(255, 195, 75) } else { @(255, 90, 105) }
        [Console]::WriteLine("  $(Format-AnsiText -Text $state -Color $color -Bold)  $($check.Name) | $($check.Detail)")
    }
    $failed = @($checks | Where-Object { -not $_.Passed -and $_.Required })
    return [pscustomobject]@{ Ready = $failed.Count -eq 0; Checks = $checks.ToArray(); Failures = $failed }
}
