function Initialize-GlmetaRepository {
    <#
    .SYNOPSIS
        Creates missing repository-root glmeta configuration from templates.
    .DESCRIPTION
        Infers safe project defaults from package.json, the current Git branch,
        and the origin remote. Existing files are validated and never replaced.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$TemplateRoot,
        [switch]$DryRun
    )

    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $packagePath = [System.IO.Path]::Combine($repositoryPath, 'package.json')
    if (-not [System.IO.File]::Exists($packagePath)) { throw "package.json not found: $packagePath" }
    $package = [System.IO.File]::ReadAllText($packagePath) | ConvertFrom-Json
    $packageName = [string]$package.name
    $projectName = ($packageName -split '/')[-1]
    $namespace = if ($packageName.StartsWith('@')) { ($packageName -split '/')[0].TrimStart('@') } else { 'namespace' }
    $remoteUrl = (& git -C $repositoryPath remote get-url origin 2>$null)
    if ($LASTEXITCODE -eq 0 -and $remoteUrl -match '(?i)gitlab\.com[:/](?<path>[^\s]+?)(?:\.git)?$') {
        $projectPath = $Matches.path -replace '\.git$', ''
        $pathParts = $projectPath -split '/'
        if ($pathParts.Count -gt 1) { $namespace = $pathParts[0] }
    } else {
        $projectPath = "$namespace/$projectName"
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

    $results = [System.Collections.Generic.List[object]]::new(2)
    foreach ($fileName in @('repo_config.json', 'repo_meta.json')) {
        $destination = [System.IO.Path]::Combine($repositoryPath, $fileName)
        $template = [System.IO.Path]::Combine($TemplateRoot, "$fileName.template")
        if (-not [System.IO.File]::Exists($template)) { throw "glmeta template not found: $template" }
        if ([System.IO.File]::Exists($destination)) {
            if ($fileName -eq 'repo_config.json') { $null = Get-GlmetaConfiguration -ConfigPath $destination }
            $results.Add([pscustomobject]@{ File = $fileName; State = 'EXISTS'; Path = $destination })
            continue
        }
        $content = [System.IO.File]::ReadAllText($template)
        foreach ($entry in $tokens.GetEnumerator()) { $content = $content.Replace($entry.Key, $entry.Value) }
        if ($DryRun) {
            $results.Add([pscustomobject]@{ File = $fileName; State = 'WOULD CREATE'; Path = $destination })
        } elseif ($PSCmdlet.ShouldProcess($destination, 'Create repository glmeta configuration')) {
            [System.IO.File]::WriteAllText($destination, $content, [System.Text.UTF8Encoding]::new($false))
            $results.Add([pscustomobject]@{ File = $fileName; State = 'CREATED'; Path = $destination })
        }
    }
    foreach ($result in $results) { [Console]::WriteLine(('  {0,-12} {1}' -f @($result.State, $result.File))) }
    return $results.ToArray()
}
