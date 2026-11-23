# Profile handlers run inside Rivet's module scope; only this selected file is loaded.
@{
    TemplateRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'templates', 'js'))
    ValidateConfig = {
        param($Config)
        if ($Config.PSObject.Properties['js']) {
            $js = $Config.js
            if ($js.PSObject.Properties['entry']) {
                $entry = [string]$js.entry
                if ([string]::IsNullOrWhiteSpace($entry) -or [System.IO.Path]::IsPathRooted($entry) -or $entry -match '(^|[/\\])\.\.([/\\]|$)') {
                    throw 'js.entry must be a repository-relative path inside the repository.'
                }
            }
            if ($js.PSObject.Properties['bundleSize'] -and $js.bundleSize.PSObject.Properties['maxGzipBytes'] -and [long]$js.bundleSize.maxGzipBytes -lt 0) {
                throw 'js.bundleSize.maxGzipBytes cannot be negative.'
            }
        }
        if ($Config.PSObject.Properties['releaseValidation']) {
            $validation = $Config.releaseValidation
            if ($validation.PSObject.Properties['minimumArchiveCount'] -and [int]$validation.minimumArchiveCount -lt 0) {
                throw 'releaseValidation.minimumArchiveCount cannot be negative.'
            }
        }
    }
    Identity = {
        param($RepositoryRoot, $ProjectName, $Namespace, $Manifest)
        if ($Manifest) { throw '-Manifest is not used by the jsm profile.' }
        $packagePath = [System.IO.Path]::Combine($RepositoryRoot, 'package.json')
        $packageName = "@$namespace/$projectName"
        if ([System.IO.File]::Exists($packagePath)) {
            try {
                $package = [System.IO.File]::ReadAllText($packagePath) | ConvertFrom-Json
                if ($package.name) {
                    $packageName = [string]$package.name
                    $projectName = ($packageName -split '/')[-1]
                    if ($packageName.StartsWith('@')) { $namespace = ($packageName -split '/')[0].TrimStart('@') }
                }
            } catch { }
        } else {
            $packageName = "@$namespace/$projectName"
        }

        @{ ProjectName = $projectName; Namespace = $namespace; Tokens = @{ '{{PACKAGE_NAME}}' = $packageName } }
    }
    Templates = {
        param($RepositoryRoot, $Tokens, $Bun)
        $templateFiles = [System.Collections.Generic.List[hashtable]]::new()
        $templateFiles.Add(@{ File = 'repo_config.json'; Template = 'repo_config.json.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $true })
        $templateFiles.Add(@{ File = 'repo_meta.json'; Template = 'repo_meta.json.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $true })
        $templateFiles.Add(@{ File = 'package.json'; Template = 'package.json'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'jsr.jsonc'; Template = 'jsr.jsonc'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'src/{{PROJECT_NAME}}.js'; Template = 'src/library.js.template'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })

        $includeBun = $Bun -or [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'bunfig.toml')) -or [System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'bun.lock'))
        if ($includeBun) {
            $templateFiles.Add(@{ File = 'bunfig.toml'; Template = 'bunfig.toml'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        }

        $templateFiles.Add(@{ File = 'vite.config.js'; Template = 'vite.config.js'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'eslint.config.js'; Template = 'eslint.config.js'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = '.prettierrc'; Template = '.prettierrc'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = '.gitignore'; Template = '.gitignore'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = '.gitlab-ci.yml'; Template = '.gitlab-ci.yml'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'scripts/check-bundle-size.mjs'; Template = 'scripts/check-bundle-size.mjs'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'scripts/validate-release.mjs'; Template = 'scripts/validate-release.mjs'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })

        $templateFiles.ToArray()
    }
    UpdateVersion = {
        param($RepositoryRoot, $Config, $Version, $DryRun)
        Update-JSLibSemver -RepositoryRoot $RepositoryRoot -Version $Version -DryRun:$DryRun
    }
    ReadVersion = {
        param($RepositoryRoot, $Config)
        $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText([System.IO.Path]::Combine($RepositoryRoot, 'package.json')))
        try { $document.RootElement.GetProperty('version').GetString() } finally { $document.Dispose() }
    }
    UpdateHeader = {
        param($RepositoryRoot, $Config, $ConfigPath, $DryRun)
        Update-JSHeader -RepositoryRoot $RepositoryRoot -ConfigPath $ConfigPath -DryRun:$DryRun
    }
    Checks = {
        param($RepositoryRoot, $Config)
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

        Add-Check 'package.json' ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'package.json'))) 'required repository file'
        if ([System.IO.File]::Exists([System.IO.Path]::Combine($RepositoryRoot, 'jsr.jsonc'))) {
            Add-Check 'jsr.jsonc' $true 'optional JSR manifest'
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

    }
    ReleaseChecklist = {
        param($Version)
        "- [ ] Update configured JavaScript package manifests to ``$Version``."
    }
    ReviewVersions = {
        param($RepositoryRoot, $Config)
        $manifestVersions = [System.Collections.Generic.List[string]]::new(2)
        foreach ($manifestName in @('package.json', 'jsr.jsonc')) {
            $manifestPath = [System.IO.Path]::Combine($RepositoryRoot, $manifestName)
            if (-not [System.IO.File]::Exists($manifestPath)) { continue }
            $documentOptions = [System.Text.Json.JsonDocumentOptions]@{ CommentHandling = 'Skip'; AllowTrailingCommas = $true }
            $document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($manifestPath), $documentOptions)
            try { $manifestVersions.Add("$manifestName=$($document.RootElement.GetProperty('version').GetString())") } finally { $document.Dispose() }
        }

        $manifestVersions.ToArray()
    }
    ReleaseFiles = {
        param($RepositoryRoot, $Config)
        'package.json', 'package-lock.json', 'jsr.jsonc', 'bun.lock', 'bunfig.toml', 'README-npm.md'
    }
}
