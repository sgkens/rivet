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
        Includes Bun runtime files (bunfig.toml and bun.lock).
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
    $namespace = 'staticcanvas'

    $remoteUrl = (& git -C $repositoryPath remote get-url origin 2>$null)
    if ($LASTEXITCODE -eq 0 -and $remoteUrl -match '(?i)gitlab\.com[:/](?<path>[^\s]+?)(?:\.git)?$') {
        $projectPath = $Matches.path -replace '\.git$', ''
        $pathParts = $projectPath -split '/'
        if ($pathParts.Count -gt 1) {
            $namespace = $pathParts[0]
            $projectName = $pathParts[1]
        }
    } else {
        $projectPath = "$namespace/$projectName"
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
    }

    foreach ($key in $identity.Tokens.Keys) { $tokens[$key] = [string]$identity.Tokens[$key] }
    $templateFiles = @(& $repositoryProfile.Templates $repositoryPath $tokens ([bool]$Bun))

    $results = [System.Collections.Generic.List[object]]::new($templateFiles.Count)
    foreach ($entry in $templateFiles) {
        $fileName = $entry.File
        foreach ($tokenEntry in $tokens.GetEnumerator()) { $fileName = $fileName.Replace($tokenEntry.Key, $tokenEntry.Value) }
        $destination = if ($entry.RivetManaged) {
            if ($fileName -eq 'repo_config.json') { $ConfigPath } else { Resolve-RivetPath -RepositoryRoot $repositoryPath -ItemName $fileName }
        } else {
            [System.IO.Path]::Combine($repositoryPath, ($fileName -replace '/', [System.IO.Path]::DirectorySeparatorChar))
        }

        $template = [System.IO.Path]::Combine($TemplateRoot, ($entry.Template -replace '/', [System.IO.Path]::DirectorySeparatorChar))
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
