function Initialize-RivetRepository {
    <#
    .SYNOPSIS
        Creates missing repository rivet configuration from templates.
    .DESCRIPTION
        Uses the selected repository profile and Git origin to infer defaults.
        Creates missing files and preserves existing files. Missing profile
        configuration defaults to jsm for compatibility.
    .PARAMETER Profile
        Installed profile name, used by init and bootstrap. Defaults to the existing configuration or jsm.
    .PARAMETER Manifest
        Repository-relative manifest path for profiles that require one (psm).
    .PARAMETER ConfigPath
        Optional destination for repo_config.json.
    .PARAMETER RepositoryRoot
        Directory where repository files will be initialized.
    .PARAMETER TemplateRoot
        Path to the template files directory.
    .PARAMETER Bun
        Includes the Bun runtime configuration. The package manager creates its lockfile.
    .PARAMETER DryRun
        Reports actions without writing files.
    .PARAMETER Raw
        Suppresses console output and returns structured initialization records.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$TemplateRoot,
        [string]$Profile,
        [string]$Manifest,
        [string]$ConfigPath,
        [switch]$Bun,
        [switch]$DryRun,
        [switch]$Raw
    )

    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Resolve-RivetPath -RepositoryRoot $repositoryPath -ItemName 'repo_config.json' }
    $existingConfig = if ([System.IO.File]::Exists($ConfigPath)) { Get-RivetConfiguration -ConfigPath $ConfigPath } else { $null }
    $repositoryProfile = Get-RivetProfile -Name $Profile -Config $existingConfig
    if ($null -ne $existingConfig -and $Profile -and (Get-RivetProfile -Config $existingConfig).Name -ne $repositoryProfile.Name) {
        throw 'Initialization cannot change an existing repository profile. Edit repo_config.json explicitly.'
    }
    if ([string]::IsNullOrWhiteSpace($TemplateRoot)) { $TemplateRoot = $repositoryProfile.TemplateRoot }
    $projectName = (Split-Path $repositoryPath -Leaf)
    $namespace = 'local'
    $projectPath = "$namespace/$projectName"
    $gitLabBaseUri = 'https://gitlab.com'
    if ($null -ne $existingConfig -and $existingConfig.PSObject.Properties['gitlab'] -and $existingConfig.gitlab.PSObject.Properties['baseUri']) {
        $gitLabBaseUri = ([string]$existingConfig.gitlab.baseUri).TrimEnd('/')
    }

    $remoteUrl = (& git -C $repositoryPath remote get-url origin 2>$null)
    $remotePath = $null
    if ($LASTEXITCODE -eq 0 -and $remoteUrl -match '(?i)^(?<base>https?://[^/\s]+)/(?<path>[^\s]+?)(?:\.git)?$') {
        $remotePath = $Matches.path
        if ($null -eq $existingConfig) { $gitLabBaseUri = $Matches.base.TrimEnd('/') }
    } elseif ($LASTEXITCODE -eq 0 -and $remoteUrl -match '(?i)^(?:ssh://)?[^@\s]+@(?<host>[^:/\s]+)(?::|/)(?<path>[^\s]+?)(?:\.git)?$') {
        $remotePath = $Matches.path
        if ($null -eq $existingConfig) { $gitLabBaseUri = "https://$($Matches.host)" }
    }
    if (-not [string]::IsNullOrWhiteSpace($remotePath)) {
        $projectPath = $remotePath.Trim('/') -replace '\.git$', ''
        $pathParts = $projectPath -split '/'
        if ($pathParts.Count -gt 1) {
            $namespace = $pathParts[0]
            $projectName = $pathParts[-1]
        }
    }

    if ($null -ne $existingConfig -and $existingConfig.PSObject.Properties[$repositoryProfile.Name]) {
        $settings = $existingConfig.($repositoryProfile.Name)
        if ($settings.PSObject.Properties['manifest']) {
            if ($Manifest -and $Manifest.Replace('\', '/') -ne ([string]$settings.manifest).Replace('\', '/')) {
                throw 'Initialization cannot change an existing manifest setting. Edit repo_config.json explicitly.'
            }
            $Manifest = [string]$settings.manifest
        }
    }
    $identity = & $repositoryProfile.Identity $repositoryPath $projectName $namespace $Manifest
    $projectName = $identity.ProjectName
    $namespace = $identity.Namespace
    if ([string]::IsNullOrWhiteSpace($remotePath) -and $null -eq $existingConfig) {
        $projectPath = "$namespace/$projectName"
    }
    if ($null -ne $existingConfig -and $existingConfig.PSObject.Properties['project']) {
        if ($existingConfig.project.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$existingConfig.project.name)) { $projectName = [string]$existingConfig.project.name }
        if ($existingConfig.project.PSObject.Properties['namespace'] -and -not [string]::IsNullOrWhiteSpace([string]$existingConfig.project.namespace)) { $namespace = [string]$existingConfig.project.namespace }
        if ($existingConfig.project.PSObject.Properties['path'] -and -not [string]::IsNullOrWhiteSpace([string]$existingConfig.project.path)) { $projectPath = [string]$existingConfig.project.path }
    }
    $branch = (& git -C $repositoryPath branch --show-current 2>$null)
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }
    $displayName = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase(($projectName -replace '[-_]+', ' '))
    $tokens = [ordered]@{
        '{{PROJECT_NAME}}' = $projectName
        '{{DISPLAY_NAME}}' = $displayName
        '{{NAMESPACE}}' = $namespace
        '{{PROJECT_PATH}}' = $projectPath
        '{{DEFAULT_BRANCH}}' = $branch.Trim()
        '{{PROFILE}}' = $repositoryProfile.Name
        '{{GITLAB_BASE_URI}}' = $gitLabBaseUri
        '{{PROJECT_URL}}' = "$gitLabBaseUri/$projectPath"
    }

    foreach ($key in $identity.Tokens.Keys) { $tokens[$key] = [string]$identity.Tokens[$key] }
    $templateFiles = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($profileTemplate in @(& $repositoryProfile.Templates $repositoryPath $tokens ([bool]$Bun))) {
        $templateFiles.Add($profileTemplate)
    }

    if ($null -ne $existingConfig -and $existingConfig.PSObject.Properties['scaffold']) {
        $scaffold = $existingConfig.scaffold
        $excludedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $configuredExclusions = if ($scaffold.PSObject.Properties['exclude']) { @($scaffold.exclude) } else { @() }
        foreach ($excludedFile in $configuredExclusions) {
            if (-not [string]::IsNullOrWhiteSpace([string]$excludedFile)) { [void]$excludedFiles.Add(([string]$excludedFile).Replace('\', '/')) }
        }
        if ($excludedFiles.Count) {
            for ($index = $templateFiles.Count - 1; $index -ge 0; $index--) {
                if ($excludedFiles.Contains(([string]$templateFiles[$index].File).Replace('\', '/'))) {
                    $templateFiles.RemoveAt($index)
                }
            }
        }

        $configuredTemplates = if ($scaffold.PSObject.Properties['templates']) { @($scaffold.templates) } else { @() }
        foreach ($customTemplate in $configuredTemplates) {
            $destinationName = [string]$customTemplate.file
            $sourceName = [string]$customTemplate.template
            foreach ($candidate in @($destinationName, $sourceName)) {
                if ([string]::IsNullOrWhiteSpace($candidate) -or [System.IO.Path]::IsPathRooted($candidate) -or $candidate -match '(^|[/\\])\.\.([/\\]|$)') {
                    throw 'scaffold template file and template paths must be repository-relative paths inside the repository.'
                }
            }
            $templateFiles.Add(@{
                File = $destinationName
                Template = $sourceName
                TemplateRoot = $repositoryPath
                TokenReplace = -not ($customTemplate.PSObject.Properties['tokenReplace'] -and -not [bool]$customTemplate.tokenReplace)
                Mandatory = -not ($customTemplate.PSObject.Properties['mandatory'] -and -not [bool]$customTemplate.mandatory)
                RivetManaged = $false
            })
        }
    }

    $results = [System.Collections.Generic.List[object]]::new($templateFiles.Count)
    foreach ($entry in $templateFiles) {
        $fileName = $entry.File
        foreach ($tokenEntry in $tokens.GetEnumerator()) { $fileName = $fileName.Replace($tokenEntry.Key, $tokenEntry.Value) }
        $destination = if ($entry.RivetManaged) {
            if ($fileName -eq 'repo_config.json') { $ConfigPath } else { Resolve-RivetPath -RepositoryRoot $repositoryPath -ItemName $fileName }
        } else {
            [System.IO.Path]::Combine($repositoryPath, ($fileName -replace '/', [System.IO.Path]::DirectorySeparatorChar))
        }

        $entryTemplateRoot = if ($entry.ContainsKey('TemplateRoot')) { [string]$entry.TemplateRoot } else { $TemplateRoot }
        $template = [System.IO.Path]::Combine($entryTemplateRoot, ($entry.Template -replace '/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not [System.IO.File]::Exists($template)) {
            if ($entry.Mandatory) { throw "rivet template not found: $template" }
            continue
        }
        if ([System.IO.File]::Exists($destination)) {
            if ($fileName -eq 'repo_config.json') { $null = Get-RivetConfiguration -ConfigPath $destination }
            $results.Add([pscustomobject]@{ File = $fileName; State = 'EXISTS'; Path = $destination })
            continue
        }
        $content = [System.IO.File]::ReadAllText($template)
        if ($entry.TokenReplace) {
            foreach ($tokenEntry in $tokens.GetEnumerator()) { $content = $content.Replace($tokenEntry.Key, $tokenEntry.Value) }
        }
        if ($DryRun) {
            $results.Add([pscustomobject]@{ File = $fileName; State = 'WOULD CREATE'; Path = $destination })
        } elseif ($PSCmdlet.ShouldProcess($destination, "Create repository $fileName")) {
            $dir = [System.IO.Path]::GetDirectoryName($destination)
            if (-not [System.IO.Directory]::Exists($dir)) { [System.IO.Directory]::CreateDirectory($dir) | Out-Null }
            [System.IO.File]::WriteAllText($destination, $content, [System.Text.UTF8Encoding]::new($false))
            $results.Add([pscustomobject]@{ File = $fileName; State = 'CREATED'; Path = $destination })
        }
    }

    if (-not $DryRun -and -not $WhatIfPreference) {
        $workItemsDir = [System.IO.Path]::Combine($repositoryPath, '.rivet', 'work-items')
        if (-not [System.IO.Directory]::Exists($workItemsDir)) {
            [System.IO.Directory]::CreateDirectory($workItemsDir) | Out-Null
        }
    }

    if (-not $Raw) {
        foreach ($result in $results) { [Console]::WriteLine(('  {0,-12} {1}' -f @($result.State, $result.File))) }
    }
    return $results.ToArray()
}
