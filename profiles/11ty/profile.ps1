# Profile handlers run inside Rivet's module scope; only this selected file is loaded.
@{
    TemplateRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'templates', '11ty'))
    ValidateConfig = {
        param($Config)
        if ($Config.PSObject.Properties['eleventy']) {
            $eleventy = $Config.eleventy
            if ($eleventy.PSObject.Properties['configFile'] -and [string]::IsNullOrWhiteSpace([string]$eleventy.configFile)) {
                throw 'eleventy.configFile cannot be empty.'
            }
        }
    }
    Identity = {
        param($RepositoryRoot, $ProjectName, $Namespace, $Manifest)
        if ($Manifest) { throw '-Manifest is not used by the 11ty profile.' }
        $packagePath = [System.IO.Path]::Combine($RepositoryRoot, 'package.json')
        $packageName = if ($Namespace) { "@$Namespace/$ProjectName" } else { $ProjectName }
        if ([System.IO.File]::Exists($packagePath)) {
            try {
                $package = [System.IO.File]::ReadAllText($packagePath) | ConvertFrom-Json
                if ($package.name) {
                    $packageName = [string]$package.name
                    $projectName = ($packageName -split '/')[-1]
                    if ($packageName.StartsWith('@')) { $Namespace = ($packageName -split '/')[0].TrimStart('@') }
                }
            } catch { }
        } else {
            $packageName = if ($Namespace) { "@$Namespace/$ProjectName" } else { $ProjectName }
        }

        @{ ProjectName = $projectName; Namespace = $Namespace; Tokens = @{
            '{{PACKAGE_NAME}}' = $packageName
            '{{THEME_NAME}}'   = $projectName
        } }
    }
    Templates = {
        param($RepositoryRoot, $Tokens, $Bun)
        $templateFiles = [System.Collections.Generic.List[hashtable]]::new()
        $templateFiles.Add(@{ File = 'repo_config.json'; Template = 'repo_config.json.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $true })
        $templateFiles.Add(@{ File = 'repo_meta.json'; Template = 'repo_meta.json.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $true })
        $templateFiles.Add(@{ File = 'package.json'; Template = 'package.json'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'eleventy.config.js'; Template = 'eleventy.config.js'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'README.md'; Template = 'README.md.template'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'CHANGELOG.md'; Template = 'CHANGELOG.md.template'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'release-notes.md'; Template = 'release-notes.md.template'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = '.gitignore'; Template = '.gitignore'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = '.gitlab-ci.yml'; Template = '.gitlab-ci.yml'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'scripts/check.js'; Template = 'scripts/check.js'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })

        $templateFiles.ToArray()
    }
    UpdateVersion = {
        param($RepositoryRoot, $Config, $Version, $DryRun)
        if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid SemVer version: $Version" }
        $pkgPath = [System.IO.Path]::Combine($RepositoryRoot, 'package.json')
        if (-not [System.IO.File]::Exists($pkgPath)) { throw "Required version file not found: $pkgPath" }

        $content = [System.IO.File]::ReadAllText($pkgPath)
        $pattern = '(?s)^(\s*\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"version"\s*:\s*)"[^"]+"'
        if (-not [regex]::IsMatch($content, $pattern)) {
            $pattern = '("version"\s*:\s*)"[^"]+"'
        }
        $updated = [regex]::Replace($content, $pattern, "`$1`"$Version`"", 1)
        if ($updated -ne $content) {
            if ($DryRun) {
                Write-Output "Would update package.json to $Version"
            } else {
                [System.IO.File]::WriteAllText($pkgPath, $updated, [System.Text.UTF8Encoding]::new($false))
                Write-Output "Updated package.json to $Version"
            }
        } else {
            Write-Output "package.json already uses $Version"
        }

        $lockPath = [System.IO.Path]::Combine($RepositoryRoot, 'package-lock.json')
        if ([System.IO.File]::Exists($lockPath)) {
            $lockContent = [System.IO.File]::ReadAllText($lockPath)
            $rootPattern = '(?m)^(  "version"\s*:\s*")[^"]+("\s*,)$'
            $packagePattern = '(?ms)("packages"\s*:\s*\{\s*""\s*:\s*\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"version"\s*:\s*")[^"]+("\s*,)'
            if ([regex]::IsMatch($lockContent, $rootPattern) -and [regex]::IsMatch($lockContent, $packagePattern)) {
                $updatedLock = [regex]::Replace($lockContent, $rootPattern, "`${1}$Version`${2}", 1)
                $updatedLock = [regex]::Replace($updatedLock, $packagePattern, "`${1}$Version`${2}", 1)
                if ($updatedLock -ne $lockContent) {
                    if ($DryRun) {
                        Write-Output "Would update package-lock.json to $Version"
                    } else {
                        [System.IO.File]::WriteAllText($lockPath, $updatedLock, [System.Text.UTF8Encoding]::new($false))
                        Write-Output "Updated package-lock.json to $Version"
                    }
                } else {
                    Write-Output "package-lock.json already uses $Version"
                }
            }
        }
    }
    ReadVersion = {
        param($RepositoryRoot, $Config)
        $pkgPath = [System.IO.Path]::Combine($RepositoryRoot, 'package.json')
        if (-not [System.IO.File]::Exists($pkgPath)) { throw "package.json not found: $pkgPath" }
        $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($pkgPath))
        try { $document.RootElement.GetProperty('version').GetString() } finally { $document.Dispose() }
    }
    UpdateHeader = {
        param($RepositoryRoot, $Config, $ConfigPath, $DryRun)
        $readmePath = [System.IO.Path]::Combine($RepositoryRoot, 'README.md')
        if (-not [System.IO.File]::Exists($readmePath)) { return }
        $content = [System.IO.File]::ReadAllText($readmePath)
        $pattern = '(?s)<!-- rivet:header:start -->.*?<!-- rivet:header:end -->'
        $matches = [regex]::Matches($content, $pattern)
        if ($matches.Count -eq 0) { return 'README header preserved (no rivet:header markers).' }
        if ($matches.Count -ne 1) { throw 'Expected one rivet:header block in README.md.' }

        $headerTemplatePath = [System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'templates', '11ty', 'README.header.md.template')
        if ([System.IO.File]::Exists($headerTemplatePath)) {
            Update-JSHeader -RepositoryRoot $RepositoryRoot -ConfigPath $ConfigPath -TemplatePath $headerTemplatePath -DryRun:$DryRun
            return
        }
        $version = try {
            $pkgDoc = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText([System.IO.Path]::Combine($RepositoryRoot, 'package.json')))
            try { $pkgDoc.RootElement.GetProperty('version').GetString() } finally { $pkgDoc.Dispose() }
        } catch { '0.1.0' }
        $displayName = if ($Config -and $Config.project -and $Config.project.displayName) { $Config.project.displayName } else { 'Eleventy Theme' }
        $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $header = @('<!-- rivet:header:start -->', "# $displayName", '', "Eleventy (11ty) theme | Version $version", '<!-- rivet:header:end -->') -join $newline
        $match = $matches[0]
        $updated = $content.Substring(0, $match.Index) + $header + $content.Substring($match.Index + $match.Length)
        if ($DryRun) { return 'Would synchronize the 11ty README header.' }
        if ($updated -ne $content) { [System.IO.File]::WriteAllText($readmePath, $updated, [System.Text.UTF8Encoding]::new($false)) }
        '11ty README header synchronized'
    }
    Checks = {
        param($RepositoryRoot, $Config)
        $node = Get-Command node -ErrorAction SilentlyContinue
        if ($null -ne $node) {
            Add-Check 'Node.js runtime' $true (& node --version) $true
        } else {
            Add-Check 'Node.js runtime' $false 'node not found in PATH' $true
        }

        $pkgPath = [System.IO.Path]::Combine($RepositoryRoot, 'package.json')
        $hasPkg = [System.IO.File]::Exists($pkgPath)
        Add-Check 'package.json' $hasPkg 'required package manifest' $true

        $has11tyConfig = [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'eleventy.config.js')) -or
                         [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'eleventy.config.mjs')) -or
                         [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'eleventy.config.cjs')) -or
                         [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, '.eleventy.js'))
        Add-Check 'Eleventy configuration' $has11tyConfig $(if ($has11tyConfig) { 'eleventy config found' } else { 'eleventy.config.js or .eleventy.js missing' }) $true

        if ($hasPkg) {
            try {
                $pkg = [System.IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json
                $has11tyDep = ($null -ne $pkg.dependencies -and $pkg.dependencies.PSObject.Properties['@11ty/eleventy']) -or
                              ($null -ne $pkg.devDependencies -and $pkg.devDependencies.PSObject.Properties['@11ty/eleventy'])
                $depVersion = if ($has11tyDep) {
                    if ($pkg.dependencies -and $pkg.dependencies.PSObject.Properties['@11ty/eleventy']) { [string]$pkg.dependencies.'@11ty/eleventy' }
                    else { [string]$pkg.devDependencies.'@11ty/eleventy' }
                } else { 'not found' }
                Add-Check '@11ty/eleventy' $has11tyDep $(if ($has11tyDep) { "@11ty/eleventy $depVersion" } else { '@11ty/eleventy not listed in package.json' }) $false
            } catch {
                Add-Check '@11ty/eleventy' $false $_.Exception.Message $false
            }
        }

        $hasLock = [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'package-lock.json')) -or
                   [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'bun.lock')) -or
                   [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'pnpm-lock.yaml')) -or
                   [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'yarn.lock'))
        $lockDetail = if ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'package-lock.json'))) { 'package-lock.json present' }
                      elseif ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'bun.lock'))) { 'bun.lock present' }
                      elseif ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'pnpm-lock.yaml'))) { 'pnpm-lock.yaml present' }
                      elseif ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'yarn.lock'))) { 'yarn.lock present' }
                      else { 'no lockfile found' }
        Add-Check 'Lockfile' $hasLock $lockDetail $false
    }
    ReleaseChecklist = {
        param($Version)
        "- [ ] Update npm ``package.json`` package version to ``$Version``."
    }
    ReviewVersions = {
        param($RepositoryRoot, $Config)
        $manifestPath = [System.IO.Path]::Combine($RepositoryRoot, 'package.json')
        if (-not [System.IO.File]::Exists($manifestPath)) { throw 'package.json not found' }
        $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($manifestPath))
        try {
            $ver = $document.RootElement.GetProperty('version').GetString()
            @("package.json=$ver")
        } finally {
            $document.Dispose()
        }
    }
    ReleaseFiles = {
        param($RepositoryRoot, $Config)
        'package.json', 'package-lock.json'
    }
}
