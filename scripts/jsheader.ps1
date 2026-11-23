function Update-JSHeader {
    <#
    .SYNOPSIS
        Builds the configured README project header from repository metadata.
    .DESCRIPTION
        Replaces the generated headers in README.md and README-npm.md when the
        npm README exists. Project
        identity, package paths, badge presentation, URLs, and colors come from
        repo_config.json. The description comes from repo_meta.json and is also
        consumed by GitLab metadata synchronization.
    .PARAMETER RepositoryRoot
        Repository containing README.md and repo_config.json.
    .PARAMETER ConfigPath
        Path to repo_config.json. Defaults to the repository-local file.
    .PARAMETER TemplatePath
        Optional path to the reusable README header template.
    .PARAMETER NpmTemplatePath
        Optional path to the reusable npm README header template.
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
        [string]$NpmTemplatePath,
        [switch]$DryRun
    )

    $ErrorActionPreference = 'Stop'
    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $readmePath = [System.IO.Path]::Combine($repositoryPath, 'README.md')
    if (-not [System.IO.File]::Exists($readmePath)) { throw "README not found: $readmePath" }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Resolve-RivetPath -RepositoryRoot $repositoryPath -ItemName 'repo_config.json'
    }
    $configFullPath = [System.IO.Path]::GetFullPath($ConfigPath)
    if (-not [System.IO.File]::Exists($configFullPath)) { throw "Repository configuration not found: $configFullPath" }

    $config = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($configFullPath))
    try {
        $root = $config.RootElement
        $project = $root.GetProperty('project')
        $header = $root.GetProperty('readmeHeader')
        $gitlab = $root.GetProperty('gitlab')
        $tagging = $root.GetProperty('tagging')
        $metadataSource = $root.GetProperty('metadataSource').GetString()
        $metadataPath = if ([System.IO.Path]::IsPathRooted($metadataSource)) {
            [System.IO.Path]::GetFullPath($metadataSource)
        } else {
            $resolvedMeta = Resolve-RivetPath -RepositoryRoot $repositoryPath -ItemName $metadataSource
            if ([System.IO.File]::Exists($resolvedMeta)) {
                $resolvedMeta
            } else {
                [System.IO.Path]::GetFullPath([System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($configFullPath), $metadataSource))
            }
        }
        $metadata = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($metadataPath))
        try {
            $description = $metadata.RootElement.GetProperty('project').GetProperty('description').GetString()
        } finally {
            $metadata.Dispose()
        }

        $projectName = $project.GetProperty('name').GetString()
        $name = $project.GetProperty('displayName').GetString()
        $projectPath = $project.GetProperty('path').GetString()
        $artifactPath = $project.GetProperty('artifactPath').GetString()
        $defaultBranch = $project.GetProperty('defaultBranch').GetString()
        $npmElement = [System.Text.Json.JsonElement]::new()
        $npmPackage = if ($project.TryGetProperty('npmPackage', [ref]$npmElement)) { $npmElement.GetString() } else { '' }
        $jsrElement = [System.Text.Json.JsonElement]::new()
        $jsrPackage = if ($project.TryGetProperty('jsrPackage', [ref]$jsrElement)) { $jsrElement.GetString() } else { '' }
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
        $tagPrefix = $tagging.GetProperty('prefix').GetString()
        $releaseSuffix = $tagging.GetProperty('releaseSuffix').GetString()
    } finally {
        $config.Dispose()
    }

    $tagLines = & git -C $repositoryPath tag --merged HEAD --list 'v[0-9]*' --sort=-version:refname
    if ($LASTEXITCODE -ne 0) { throw "Unable to read Git tags from '$repositoryPath'." }
    $latestTag = $tagLines | Where-Object { $_ -match '^v\d+\.\d+\.\d+(?:-release)?$' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($latestTag)) { throw 'No stable SemVer tag is reachable from HEAD.' }

    $packagePath = [System.IO.Path]::Combine($repositoryPath, 'package.json')
    if (-not [System.IO.File]::Exists($packagePath)) { throw "Package manifest not found: $packagePath" }
    $packageDocument = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($packagePath))
    try {
        $packageVersion = $packageDocument.RootElement.GetProperty('version').GetString()
    } finally {
        $packageDocument.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($packageVersion)) { throw 'package.json version must not be empty.' }
    $codecovRef = "$tagPrefix$packageVersion$releaseSuffix"

    $encodedProjectPath = [Uri]::EscapeDataString($artifactPath)
    $encodedJsrPackage = if ($jsrPackage) { $jsrPackage.Replace('@', '%40') } else { '' }
    $badgeQuery = "style=$badgeStyle&logo=gitlab&labelColor=%23$labelColor&color=%23$badgeColor&logoColor=%23$logoColor"
    $packageBadgeQuery = "style=$badgeStyle&logo=npm&labelColor=%23$labelColor&color=%23$badgeColor&logoColor=%23$logoColor"
    $jsrBadgeQuery = "style=$badgeStyle&logo=jsr&labelColor=%23$labelColor&color=%23$badgeColor&logoColor=%23$logoColor"
    $jsdelivrBadgeQuery = "style=$badgeStyle&logo=jsdelivr&labelColor=%23$labelColor&color=%23$badgeColor&logoColor=%23$logoColor"
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = [System.IO.Path]::Combine($PSScriptRoot, '..', 'templates', 'js', 'README.header.md.template')
    }
    $templateFullPath = [System.IO.Path]::GetFullPath($TemplatePath)
    if (-not [System.IO.File]::Exists($templateFullPath)) { throw "README header template not found: $templateFullPath" }
    $generatedHeader = [System.IO.File]::ReadAllText($templateFullPath)
    $replacements = [ordered]@{
        '{{ALIGNMENT}}' = $alignment
        '{{PROJECT_NAME}}' = $projectName
        '{{DISPLAY_NAME}}' = $name
        '{{BANNER_URL}}' = $bannerUrl
        '{{PROJECT_PATH}}' = $projectPath
        '{{GITLAB_BASE_URI}}' = $baseUri
        '{{BADGE_QUERY}}' = $badgeQuery
        '{{LATEST_TAG}}' = $latestTag
        '{{CODECOV_REF}}' = $codecovRef
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
        '{{DESCRIPTION}}' = $description
    }
    foreach ($entry in $replacements.GetEnumerator()) { $generatedHeader = $generatedHeader.Replace($entry.Key, [string]$entry.Value) }
    if ($generatedHeader -match '\{\{[A-Z0-9_]+\}\}') { throw "README header template contains unresolved token '$($Matches[0])'." }

    $targets = [System.Collections.Generic.List[object]]::new()
    $targets.Add([pscustomobject]@{
        Name = 'README.md'; Path = $readmePath; Header = $generatedHeader
        Pattern = '(?ms)\A<div align="(?:left|center|right)">\r?\n.*?\r?\n</div>'
        MissingMessage = 'A leading aligned README header was not found.'
    })

    $npmReadmePath = [System.IO.Path]::Combine($repositoryPath, 'README-npm.md')
    if ([System.IO.File]::Exists($npmReadmePath)) {
        if ([string]::IsNullOrWhiteSpace($NpmTemplatePath)) {
            $NpmTemplatePath = [System.IO.Path]::Combine($PSScriptRoot, '..', 'templates', 'js', 'README-npm.header.md.template')
        }
        $npmTemplateFullPath = [System.IO.Path]::GetFullPath($NpmTemplatePath)
        if (-not [System.IO.File]::Exists($npmTemplateFullPath)) { throw "npm README header template not found: $npmTemplateFullPath" }
        $npmHeader = [System.IO.File]::ReadAllText($npmTemplateFullPath)
        foreach ($entry in $replacements.GetEnumerator()) { $npmHeader = $npmHeader.Replace($entry.Key, [string]$entry.Value) }
        if ($npmHeader -match '\{\{[A-Z0-9_]+\}\}') { throw "npm README header template contains unresolved token '$($Matches[0])'." }
        $targets.Add([pscustomobject]@{
            Name = 'README-npm.md'; Path = $npmReadmePath; Header = $npmHeader
            Pattern = '(?ms)\A.*?(?=\r?\n---\r?\n)'
            MissingMessage = 'A leading npm README header followed by a horizontal rule was not found.'
        })
    }

    foreach ($target in $targets) {
        $original = [System.IO.File]::ReadAllText($target.Path)
        if (-not [regex]::IsMatch($original, $target.Pattern)) { throw $target.MissingMessage }
        $lineEnding = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
        $targetHeader = $target.Header.Replace("`r`n", "`n").Replace("`n", $lineEnding).TrimEnd("`r", "`n")
        if ($target.Name -eq 'README-npm.md') { $targetHeader += $lineEnding }
        $content = [regex]::Replace($original, $target.Pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [void]$match; $targetHeader }, 1)

        if ($content -eq $original) {
            Write-Output "$($target.Name) header already matches configuration for $latestTag."
        } elseif ($DryRun) {
            Write-Output "Would rebuild $($target.Name) header for $latestTag."
        } elseif ($PSCmdlet.ShouldProcess($target.Path, "Rebuild project header for $latestTag")) {
            [System.IO.File]::WriteAllText($target.Path, $content, [System.Text.UTF8Encoding]::new($false))
            Write-Output "Rebuilt $($target.Name) header for $latestTag."
        }
    }
}
