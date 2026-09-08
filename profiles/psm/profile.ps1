@{
    TemplateRoot = [System.IO.Path]::Combine($PSScriptRoot, 'templates')
    ValidateConfig = {
        param($Config)
        if (-not $Config.PSObject.Properties['psm'] -or -not $Config.psm.PSObject.Properties['manifest'] -or [string]::IsNullOrWhiteSpace([string]$Config.psm.manifest)) {
            throw 'The psm profile requires psm.manifest (a repository-relative .psd1 path).'
        }
        $manifest = [string]$Config.psm.manifest
        if ([System.IO.Path]::IsPathRooted($manifest) -or $manifest -match '(^|[/\\])\.\.([/\\]|$)' -or [System.IO.Path]::GetExtension($manifest) -ine '.psd1') {
            throw 'psm.manifest must be a repository-relative .psd1 path inside the repository.'
        }
    }
    Identity = {
        param($RepositoryRoot, $ProjectName, $Namespace, $Manifest)
        if ([string]::IsNullOrWhiteSpace($Manifest)) {
            $candidates = @([System.IO.Directory]::GetFiles($RepositoryRoot, '*.psd1') | Where-Object {
                try { $data = Import-PowerShellDataFile -LiteralPath $_ -ErrorAction Stop; $data.ContainsKey('ModuleVersion') } catch { $false }
            })
            if ($candidates.Count -gt 1) { throw 'Multiple module manifests found. Specify -Manifest when initializing psm.' }
            $Manifest = if ($candidates.Count -eq 1) { [System.IO.Path]::GetFileName($candidates[0]) } else { "$ProjectName.psd1" }
        }
        if ([System.IO.Path]::IsPathRooted($Manifest) -or $Manifest -match '(^|[/\\])\.\.([/\\]|$)' -or [System.IO.Path]::GetExtension($Manifest) -ine '.psd1') {
            throw '-Manifest must be a repository-relative .psd1 path inside the repository.'
        }
        $Manifest = $Manifest.Replace('\', '/')
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($Manifest)
        # Names become PowerShell string literals in scaffolded files.
        if ($moduleName -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Module filenames must contain only letters, numbers, dots, underscores, and hyphens.' }
        $manifestPath = [System.IO.Path]::Combine($RepositoryRoot, $Manifest)
        if ([System.IO.File]::Exists($manifestPath)) { $null = Get-RivetPSModuleManifest -RepositoryRoot $RepositoryRoot -Manifest $Manifest }
        @{ ProjectName = $moduleName; Namespace = $Namespace; Tokens = @{
            '{{MANIFEST}}' = $Manifest
            '{{MODULE_NAME}}' = $moduleName
            '{{MODULE_FILE}}' = [System.IO.Path]::ChangeExtension($Manifest, '.psm1').Replace('\', '/')
            '{{MODULE_GUID}}' = [guid]::NewGuid().ToString()
        } }
    }
    Templates = {
        param($RepositoryRoot, $Tokens, $Bun)
        if ($Bun) { throw '-Bun is only supported by the jsm profile.' }
        @(
            @{ File = 'repo_config.json'; Template = 'repo_config.json.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $true }
            @{ File = 'repo_meta.json'; Template = 'repo_meta.json.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $true }
            @{ File = '{{MANIFEST}}'; Template = 'module.psd1.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $false }
            if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, $Tokens['{{MANIFEST}}']))) {
                @{ File = '{{MODULE_FILE}}'; Template = 'module.psm1.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $false }
            }
            @{ File = 'README.md'; Template = 'README.md.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $false }
            @{ File = 'CHANGELOG.md'; Template = 'CHANGELOG.md.template'; TokenReplace = $false; Mandatory = $true; RivetManaged = $false }
            @{ File = 'release-notes.md'; Template = 'release-notes.md.template'; TokenReplace = $false; Mandatory = $true; RivetManaged = $false }
        )
    }
    UpdateVersion = {
        param($RepositoryRoot, $Config, $Version, $DryRun)
        if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'psm ModuleVersion requires a stable major.minor.patch version.' }
        $manifest = Get-RivetPSModuleManifest -RepositoryRoot $RepositoryRoot -Manifest $Config.psm.manifest
        if ($manifest.Version -eq $Version) { return "$($manifest.RelativePath) already uses $Version" }
        $updated = $manifest.Content.Substring(0, $manifest.Start) + "'$Version'" + $manifest.Content.Substring($manifest.End)
        if ($DryRun) { return "Would update $($manifest.RelativePath) to $Version" }
        [System.IO.File]::WriteAllText($manifest.Path, $updated, [System.Text.UTF8Encoding]::new($false))
        "Updated $($manifest.RelativePath) to $Version"
    }
    ReadVersion = {
        param($RepositoryRoot, $Config)
        (Get-RivetPSModuleManifest -RepositoryRoot $RepositoryRoot -Manifest $Config.psm.manifest).Version
    }
    UpdateHeader = {
        param($RepositoryRoot, $Config, $ConfigPath, $DryRun)
        $manifest = Get-RivetPSModuleManifest -RepositoryRoot $RepositoryRoot -Manifest $Config.psm.manifest
        $path = [System.IO.Path]::Combine($RepositoryRoot, 'README.md')
        $content = [System.IO.File]::ReadAllText($path)
        $pattern = '(?s)<!-- rivet:header:start -->.*?<!-- rivet:header:end -->'
        $matches = [regex]::Matches($content, $pattern)
        if ($matches.Count -eq 0) { return 'README header preserved (no rivet:header markers).' }
        if ($matches.Count -ne 1) { throw 'Expected one rivet:header block in README.md.' }
        $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $header = @('<!-- rivet:header:start -->', "# $($Config.project.displayName)", '', "PowerShell module | Version $($manifest.Version)", '<!-- rivet:header:end -->') -join $newline
        $match = $matches[0]
        $updated = $content.Substring(0, $match.Index) + $header + $content.Substring($match.Index + $match.Length)
        if ($DryRun) { return 'Would synchronize the PowerShell README header.' }
        if ($updated -ne $content) { [System.IO.File]::WriteAllText($path, $updated, [System.Text.UTF8Encoding]::new($false)) }
    }
    Checks = {
        param($RepositoryRoot, $Config)
        try {
            $manifest = Get-RivetPSModuleManifest -RepositoryRoot $RepositoryRoot -Manifest $Config.psm.manifest
            Add-Check 'Module manifest' $true "$($manifest.RelativePath) | $($manifest.Version)"
            if ($manifest.Data.ContainsKey('RootModule') -and $manifest.Data.RootModule) {
                $rootModulePath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($manifest.Path), [string]$manifest.Data.RootModule)
                Add-Check 'Root module' ([System.IO.File]::Exists($rootModulePath)) ([string]$manifest.Data.RootModule)
            }
        } catch { Add-Check 'Module manifest' $false $_.Exception.Message }
    }
    ReleaseChecklist = {
        param($Version)
        "- [ ] Update repository manifest versions to ``$Version``."
    }
    ReviewVersions = {
        param($RepositoryRoot, $Config)
        $manifest = Get-RivetPSModuleManifest -RepositoryRoot $RepositoryRoot -Manifest $Config.psm.manifest
        "$($manifest.RelativePath)=$($manifest.Version)"
    }
    ReleaseFiles = {
        param($RepositoryRoot, $Config)
        ([string]$Config.psm.manifest).Replace('\', '/')
    }
}
