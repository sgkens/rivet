function Initialize-RivetRepository {
    <#
    .SYNOPSIS
        Creates missing repository rivet configuration from templates.
    .DESCRIPTION
        Infers safe project defaults from package.json, the current Git branch,
        and the origin remote. Existing files are validated and never replaced.
        Supports Bun runtime template initialization with -Bun while keeping
        package.json as the canonical package and script definition.
        Prefers .rivet/ directory for repo_config.json and repo_meta.json while
        supporting root fallbacks.
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
        [Parameter(Mandatory)][string]$TemplateRoot,
        [switch]$Bun,
        [switch]$DryRun,
        [switch]$Raw
    )

    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $packagePath = [System.IO.Path]::Combine($repositoryPath, 'package.json')
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

    $branch = (& git -C $repositoryPath branch --show-current 2>$null)
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }
    $displayName = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase(($projectName -replace '[-_]+', ' '))
    $tokens = [ordered]@{
        '{{PROJECT_NAME}}' = $projectName
        '{{DISPLAY_NAME}}' = $displayName
        '{{NAMESPACE}}' = $namespace
        '{{PROJECT_PATH}}' = $projectPath
        '{{DEFAULT_BRANCH}}' = $branch.Trim()
        '{{PACKAGE_NAME}}' = $packageName
    }

    $templateFiles = [System.Collections.Generic.List[hashtable]]::new()
    $templateFiles.Add(@{ File = 'repo_config.json'; Template = 'repo_config.json.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $true })
    $templateFiles.Add(@{ File = 'repo_meta.json'; Template = 'repo_meta.json.template'; TokenReplace = $true; Mandatory = $true; RivetManaged = $true })
    $templateFiles.Add(@{ File = 'package.json'; Template = 'package.json'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
    $templateFiles.Add(@{ File = 'jsr.jsonc'; Template = 'jsr.jsonc'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })

    $includeBun = $Bun -or [System.IO.File]::Exists([System.IO.Path]::Combine($repositoryPath, 'bunfig.toml')) -or [System.IO.File]::Exists([System.IO.Path]::Combine($repositoryPath, 'bun.lock'))
    if ($includeBun) {
        $templateFiles.Add(@{ File = 'bunfig.toml'; Template = 'bunfig.toml'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
        $templateFiles.Add(@{ File = 'bun.lock'; Template = 'bun.lock'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
    }

    $templateFiles.Add(@{ File = 'vite.config.js'; Template = 'vite.config.js'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
    $templateFiles.Add(@{ File = 'vite.optional.config.js'; Template = 'vite.optional.config.js'; TokenReplace = $true; Mandatory = $false; RivetManaged = $false })
    $templateFiles.Add(@{ File = 'eslint.config.js'; Template = 'eslint.config.js'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
    $templateFiles.Add(@{ File = '.prettierrc'; Template = '.prettierrc'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
    $templateFiles.Add(@{ File = '.gitignore'; Template = '.gitignore'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
    $templateFiles.Add(@{ File = '.gitlab-ci.yml'; Template = '.gitlab-ci.yml'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
    $templateFiles.Add(@{ File = 'scripts/check-bundle-size.mjs'; Template = 'scripts/check-bundle-size.mjs'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })
    $templateFiles.Add(@{ File = 'scripts/validate-release.mjs'; Template = 'scripts/validate-release.mjs'; TokenReplace = $false; Mandatory = $false; RivetManaged = $false })

    $results = [System.Collections.Generic.List[object]]::new($templateFiles.Count)
    foreach ($entry in $templateFiles) {
        $fileName = $entry.File
        $destination = if ($entry.RivetManaged) {
            Resolve-RivetPath -RepositoryRoot $repositoryPath -ItemName $fileName
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

    if (-not $DryRun) {
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
