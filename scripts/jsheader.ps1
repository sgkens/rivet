function Update-JSHeader {
    <#
    .SYNOPSIS
        Builds the configured README project header from repository metadata.
    .DESCRIPTION
        Replaces the leading aligned div block in README.md. Project
        identity, package paths, badge presentation, URLs, and colors come from
        repo_config.json. The description comes from repo_meta.json and is also
        consumed by GitLab metadata synchronization.
    .PARAMETER RepositoryRoot
        Repository containing README.md and tools/glmeta.
    .PARAMETER ConfigPath
        Path to repo_config.json. Defaults to the repository-local file.
    .PARAMETER TemplatePath
        Optional path to the reusable README header template.
    .PARAMETER DryRun
        Reports whether the header would change without writing README.md.
    .EXAMPLE
        Update-JSHeader -RepositoryRoot $PWD
    .EXAMPLE
        Update-JSHeader -RepositoryRoot $PWD -DryRun
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RepositoryRoot = (Get-Location).Path,
        [string]$ConfigPath,
        [string]$TemplatePath,
        [switch]$DryRun
    )

    $ErrorActionPreference = 'Stop'
    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $readmePath = [System.IO.Path]::Combine($repositoryPath, 'README.md')
    if (-not [System.IO.File]::Exists($readmePath)) { throw "README not found: $readmePath" }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = [System.IO.Path]::Combine($repositoryPath, 'repo_config.json')
    }
    $configFullPath = [System.IO.Path]::GetFullPath($ConfigPath)
    if (-not [System.IO.File]::Exists($configFullPath)) { throw "Repository configuration not found: $configFullPath" }

    $config = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($configFullPath))
    try {
        $root = $config.RootElement
        $project = $root.GetProperty('project')
        $header = $root.GetProperty('readmeHeader')
        $gitlab = $root.GetProperty('gitlab')
        $metadataSource = $root.GetProperty('metadataSource').GetString()
        $metadataPath = if ([System.IO.Path]::IsPathRooted($metadataSource)) {
            [System.IO.Path]::GetFullPath($metadataSource)
        } else {
            [System.IO.Path]::GetFullPath([System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($configFullPath), $metadataSource))
        }
        $metadata = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($metadataPath))
        try {
            $description = $metadata.RootElement.GetProperty('project').GetProperty('description').GetString()
        } finally {
            $metadata.Dispose()
        }

        $name = $project.GetProperty('displayName').GetString()
        $projectPath = $project.GetProperty('path').GetString()
        $artifactPath = $project.GetProperty('artifactPath').GetString()
        $defaultBranch = $project.GetProperty('defaultBranch').GetString()
        $npmPackage = $project.GetProperty('npmPackage').GetString()
        $jsrPackage = $project.GetProperty('jsrPackage').GetString()
        $bannerUrl = $project.GetProperty('bannerUrl').GetString()
        $documentationUrl = $project.GetProperty('documentationUrl').GetString()
        $baseUri = $gitlab.GetProperty('baseUri').GetString().TrimEnd('/')
        $alignmentElement = [System.Text.Json.JsonElement]::new()
        $alignment = if ($header.TryGetProperty('alignment', [ref]$alignmentElement)) { $alignmentElement.GetString() } else { 'center' }
        if ($alignment -notin @('left', 'center', 'right')) { throw "readmeHeader.alignment must be left, center, or right; received '$alignment'." }
        $badgeStyle = $header.GetProperty('badgeStyle').GetString()
        $badgeColor = $header.GetProperty('badgeColor').GetString().TrimStart('#').ToLowerInvariant()
        $labelColor = $header.GetProperty('labelColor').GetString().TrimStart('#').ToLowerInvariant()
        $logoColor = $header.GetProperty('logoColor').GetString().TrimStart('#').ToLowerInvariant()
        $codecovToken = $header.GetProperty('codecovToken').GetString()
    } finally {
        $config.Dispose()
    }

    if (-not $description.StartsWith("$name is ", [System.StringComparison]::Ordinal)) {
        throw "repo_meta.json project.description must begin with '$name is '."
    }

    $tagLines = & git -C $repositoryPath tag --merged HEAD --list 'v[0-9]*' --sort=-version:refname
    if ($LASTEXITCODE -ne 0) { throw "Unable to read Git tags from '$repositoryPath'." }
    $latestTag = $tagLines | Where-Object { $_ -match '^v\d+\.\d+\.\d+(?:-release)?$' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($latestTag)) { throw 'No stable SemVer tag is reachable from HEAD.' }

    $encodedProjectPath = [Uri]::EscapeDataString($artifactPath)
    $encodedJsrPackage = $jsrPackage.Replace('@', '%40')
    $badgeQuery = "style=$badgeStyle&logo=gitlab&labelColor=%23$labelColor&color=%23$badgeColor&logoColor=%23$logoColor"
    $packageBadgeQuery = "style=$badgeStyle&logo=npm&labelColor=%23$labelColor&color=%23$badgeColor&logoColor=%23$logoColor"
    $jsrBadgeQuery = "style=$badgeStyle&logo=jsr&labelColor=%23$labelColor&color=%23$badgeColor&logoColor=%23$logoColor"
    $jsdelivrBadgeQuery = "style=$badgeStyle&logo=jsdelivr&labelColor=%23$labelColor&color=%23$badgeColor&logoColor=%23$logoColor"
    $descriptionSuffix = $description.Substring($name.Length)

    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = [System.IO.Path]::Combine($PSScriptRoot, '..', 'templates', 'js', 'README.header.md.template')
    }
    $templateFullPath = [System.IO.Path]::GetFullPath($TemplatePath)
    if (-not [System.IO.File]::Exists($templateFullPath)) { throw "README header template not found: $templateFullPath" }
    $generatedHeader = [System.IO.File]::ReadAllText($templateFullPath)
    $replacements = [ordered]@{
        '{{ALIGNMENT}}' = $alignment
        '{{DISPLAY_NAME}}' = $name
        '{{BANNER_URL}}' = $bannerUrl
        '{{PROJECT_PATH}}' = $projectPath
        '{{GITLAB_BASE_URI}}' = $baseUri
        '{{BADGE_QUERY}}' = $badgeQuery
        '{{LATEST_TAG}}' = $latestTag
        '{{CODECOV_TOKEN}}' = $codecovToken
        '{{BADGE_COLOR}}' = $badgeColor
        '{{BADGE_STYLE}}' = $badgeStyle
        '{{LOGO_COLOR}}' = $logoColor
        '{{DOCUMENTATION_URL}}' = $documentationUrl
        '{{NPM_PACKAGE}}' = $npmPackage
        '{{PACKAGE_BADGE_QUERY}}' = $packageBadgeQuery
        '{{ENCODED_JSR_PACKAGE}}' = $encodedJsrPackage
        '{{JSR_BADGE_QUERY}}' = $jsrBadgeQuery
        '{{JSDELIVR_BADGE_QUERY}}' = $jsdelivrBadgeQuery
        '{{ENCODED_ARTIFACT_PATH}}' = $encodedProjectPath
        '{{DEFAULT_BRANCH}}' = $defaultBranch
        '{{DESCRIPTION_SUFFIX}}' = $descriptionSuffix
    }
    foreach ($entry in $replacements.GetEnumerator()) { $generatedHeader = $generatedHeader.Replace($entry.Key, [string]$entry.Value) }
    if ($generatedHeader -match '\{\{[A-Z0-9_]+\}\}') { throw "README header template contains unresolved token '$($Matches[0])'." }

    $original = [System.IO.File]::ReadAllText($readmePath)
    $lineEnding = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
    $generatedHeader = $generatedHeader.Replace("`r`n", "`n").Replace("`n", $lineEnding)
    $pattern = '(?ms)\A<div align="(?:left|center|right)">\r?\n.*?\r?\n</div>'
    if (-not [regex]::IsMatch($original, $pattern)) { throw 'A leading aligned README header was not found.' }
    $content = [regex]::Replace($original, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [void]$match; $generatedHeader.TrimEnd("`r", "`n") }, 1)

    if ($content -eq $original) {
        Write-Output "README header already matches configuration for $latestTag."
        return
    }
    if ($DryRun) {
        Write-Output "Would rebuild README header for $latestTag."
    } elseif ($PSCmdlet.ShouldProcess($readmePath, "Rebuild $alignment-aligned project header for $latestTag")) {
        [System.IO.File]::WriteAllText($readmePath, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Output "Rebuilt README header for $latestTag."
    }
}
