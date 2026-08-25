function Update-ReleaseDocumentation {
    <#
    .SYNOPSIS
        Generates marker-bounded changelog and release-note content from Git history.
    .DESCRIPTION
        Reads commits after the newest reachable tag that has a GitLab release,
        or an explicitly supplied Git ref, and groups them by Keep a Changelog
        categories. Only content between glmeta markers is replaced.
    .PARAMETER RepositoryRoot
        Repository containing CHANGELOG.md and release-notes.md.
    .PARAMETER FromTag
        Optional reachable Git tag or ref used instead of the latest GitLab
        release tag as the beginning of the range.
    .PARAMETER Version
        Release version. Defaults to package.json.
    .PARAMETER Finalize
        Writes the generated changelog block under a dated version heading
        instead of the Unreleased heading.
    .PARAMETER DryRun
        Reports changes without writing either document.
    .PARAMETER IncludeCommitHash
        Appends the short commit hash to each generated change. Enabled by default.
    .PARAMETER IncludeAuthor
        Appends the commit author after the commit hash. Enabled by default.
    .EXAMPLE
        Update-ReleaseDocumentation -RepositoryRoot $PWD -DryRun
    .EXAMPLE
        Update-ReleaseDocumentation -RepositoryRoot $PWD -FromTag v0.25.0 -Version 0.28.0 -Finalize
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RepositoryRoot = (Get-Location).Path,
        [string]$ConfigPath,
        [string]$FromTag,
        [ValidatePattern('^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
        [string]$Version,
        [string]$Scope,
        [switch]$Finalize,
        [switch]$IncludeCommitHash = $true,
        [switch]$IncludeAuthor = $true,
        [switch]$DryRun
    )

    $ErrorActionPreference = 'Stop'
    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required to generate release documentation.' }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = [System.IO.Path]::Combine($repositoryPath, 'repo_config.json') }
    $config = Get-GlmetaConfiguration -ConfigPath $ConfigPath
    $baseUri = ([string]$config.gitlab.baseUri).TrimEnd('/')
    $projectId = [string]$config.gitlab.projectId
    $projectPath = ([string]$config.project.path).Trim('/')
    $projectName = [string]$config.project.displayName
    $tokenVariable = [string]$config.gitlab.tokenEnvironmentVariable
    $timeoutSeconds = [int]$config.requestTimeoutSeconds

    if ([string]::IsNullOrWhiteSpace($FromTag)) {
        $projectKey = if ([string]::IsNullOrWhiteSpace($projectId)) { [Uri]::EscapeDataString($projectPath) } else { $projectId }
        $headers = @{ Accept = 'application/json' }
        $accessToken = [System.Environment]::GetEnvironmentVariable($tokenVariable)
        if (-not [string]::IsNullOrWhiteSpace($accessToken)) { $headers['PRIVATE-TOKEN'] = $accessToken }

        $releases = [System.Collections.Generic.List[object]]::new()
        $page = 1
        do {
            try {
                $pageResponse = Invoke-RestMethod -Method Get -Uri "$baseUri/api/v4/projects/$projectKey/releases?per_page=100&page=$page" -Headers $headers -TimeoutSec $timeoutSeconds
                $pageItems = @($pageResponse)
            } catch {
                throw "Unable to query GitLab releases; specify -FromTag to use an explicit baseline. $($_.Exception.Message)"
            }
            foreach ($release in $pageItems) { if ($null -ne $release) { [void]$releases.Add($release) } }
            $page++
        } while ($pageItems.Count -eq 100)

        foreach ($release in @($releases | Sort-Object -Property released_at -Descending)) {
            $candidate = [string]$release.tag_name
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            & git -C $repositoryPath merge-base --is-ancestor $candidate HEAD 2>$null
            if ($LASTEXITCODE -eq 0) { $FromTag = $candidate; break }
        }
        if ([string]::IsNullOrWhiteSpace($FromTag)) { throw 'No GitLab release tag is reachable from HEAD; specify -FromTag.' }
    } else {
        & git -C $repositoryPath merge-base --is-ancestor $FromTag HEAD
        if ($LASTEXITCODE -ne 0) { throw "FromTag '$FromTag' is not a reachable ancestor of HEAD." }
    }

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $packagePath = [System.IO.Path]::Combine($repositoryPath, 'package.json')
        $packageDocument = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($packagePath))
        try { $Version = $packageDocument.RootElement.GetProperty('version').GetString() } finally { $packageDocument.Dispose() }
    }
    $Version = $Version.TrimStart('v')

    $format = '%H%x1f%an%x1f%ae%x1f%s%x1f%b%x1e'
    $rawLog = (& git -C $repositoryPath log --no-merges "${FromTag}..HEAD" "--format=$format") -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Unable to read commits in range '$FromTag..HEAD'." }

    $categoryOrder = @('Added', 'Changed', 'Deprecated', 'Removed', 'Fixed', 'Security')
    $entries = [ordered]@{}
    foreach ($category in $categoryOrder) {
        $entries[$category] = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($record in ($rawLog -split [char]0x1e)) {
        if ([string]::IsNullOrWhiteSpace($record)) { continue }
        $fields = $record.Trim() -split [char]0x1f, 5
        if ($fields.Count -lt 4) { continue }
        $commitHash = $fields[0].Trim()
        $author = $fields[1].Trim()
        $authorEmail = $fields[2].Trim()
        $subject = $fields[3].Trim()
        $body = if ($fields.Count -gt 4) { $fields[4] } else { '' }
        $parsed = ConvertFrom-ConventionalCommit -Subject $subject -Body $body
        if (-not [string]::IsNullOrWhiteSpace($Scope) -and $parsed.Scope -ine $Scope) { continue }
        $category = $parsed.Category
        $text = $parsed.ReleaseNote
        $metadata = [System.Collections.Generic.List[string]]::new(2)
        if ($IncludeCommitHash) {
            $shortHash = $commitHash.Substring(0, [Math]::Min(7, $commitHash.Length))
            $metadata.Add("[$shortHash]($baseUri/$projectPath/-/commit/$commitHash)")
        }
        if ($IncludeAuthor) {
            $metadata.Add((Resolve-GitLabAuthorReference -Config $config -Name $author -Email $authorEmail))
        }
        if ($metadata.Count -gt 0) { $text += " ($($metadata -join ' — '))" }
        if (-not $entries[$category].Contains($text)) { [void]$entries[$category].Add($text) }
    }

    $sections = [System.Collections.Generic.List[string]]::new()
    foreach ($category in $categoryOrder) {
        if ($entries[$category].Count -eq 0) { continue }
        $sections.Add("### $category")
        $sections.Add('')
        foreach ($entry in $entries[$category]) { $sections.Add("- $entry") }
        $sections.Add('')
    }
    if ($sections.Count -eq 0) { $sections.Add('- No release-note commits were found in the selected range.') }
    $generatedBody = ($sections -join "`n").TrimEnd()
    $rangeSummary = "Generated from ``$FromTag..HEAD`` for $projectName ``$Version``."

    $changelogPath = [System.IO.Path]::Combine($repositoryPath, 'CHANGELOG.md')
    $releaseNotesPath = [System.IO.Path]::Combine($repositoryPath, 'release-notes.md')
    $changelog = [System.IO.File]::ReadAllText($changelogPath)
    $releaseNotes = [System.IO.File]::ReadAllText($releaseNotesPath)
    $lineEnding = if ($changelog.Contains("`r`n")) { "`r`n" } else { "`n" }

    $changelogStart = '<!-- glmeta:changelog:start -->'
    $changelogEnd = '<!-- glmeta:changelog:end -->'
    $changelogBlock = "$changelogStart`n`n$generatedBody`n`n$changelogEnd".Replace("`n", $lineEnding)
    $changelogPattern = '(?ms)<!-- glmeta:changelog:start -->.*?<!-- glmeta:changelog:end -->'
    $heading = if ($Finalize) { "## [$Version]" } else { '## [Unreleased]' }
    $markerMatch = [regex]::Match($changelog, $changelogPattern)
    $headingMatch = [regex]::Match($changelog, "(?m)^$([regex]::Escape($heading))[ \t]*$")
    $markerInTargetSection = $false
    if ($Finalize -and $markerMatch.Success -and $headingMatch.Success) {
        $releaseHeadingRegex = [regex]::new('^## \[', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        $nextHeading = $releaseHeadingRegex.Match($changelog, $headingMatch.Index + $headingMatch.Length)
        $markerInTargetSection = $markerMatch.Index -gt $headingMatch.Index -and (-not $nextHeading.Success -or $markerMatch.Index -lt $nextHeading.Index)
    }
    if ($markerMatch.Success -and (-not $Finalize -or $markerInTargetSection)) {
        $updatedChangelog = [regex]::Replace($changelog, $changelogPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [void]$match; $changelogBlock }, 1)
    } else {
        $baseChangelog = if ($Finalize) {
            [regex]::Replace($changelog, "(?ms)\r?\n?$changelogPattern\r?\n?", $lineEnding, 1)
        } else {
            $changelog
        }
        $headingPattern = "(?m)^(?<heading>$([regex]::Escape($heading))[ \t]*(?:\r?\n\r?\n> \d{4}-\d{2}-\d{2})?)[ \t]*$"
        if (-not [regex]::IsMatch($baseChangelog, $headingPattern)) {
            $dateLine = if ($Finalize) { "`n`n> $([DateTime]::Today.ToString('yyyy-MM-dd'))" } else { '' }
            $insertion = "$heading$dateLine`n`n$changelogBlock`n`n"
            $firstRelease = [regex]::Match($baseChangelog, '(?m)^## \[')
            if (-not $firstRelease.Success) { throw 'No changelog release heading was found.' }
            $updatedChangelog = $baseChangelog.Insert($firstRelease.Index, $insertion.Replace("`n", $lineEnding))
        } else {
            $updatedChangelog = [regex]::Replace(
                $baseChangelog,
                $headingPattern,
                [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups['heading'].Value + $lineEnding + $lineEnding + $changelogBlock },
                1
            )
        }
    }

    $notesStart = '<!-- glmeta:release-notes:start -->'
    $notesEnd = '<!-- glmeta:release-notes:end -->'
    $notesBlock = @"
$notesStart

$rangeSummary

$generatedBody

$notesEnd
"@.TrimEnd().Replace("`r`n", "`n").Replace("`n", $lineEnding)
    $notesPattern = '(?ms)<!-- glmeta:release-notes:start -->.*?<!-- glmeta:release-notes:end -->'
    $updatedReleaseNotes = if ([regex]::IsMatch($releaseNotes, $notesPattern)) {
        [regex]::Replace($releaseNotes, $notesPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [void]$match; $notesBlock }, 1)
    } else {
        $releaseNotes.TrimEnd() + $lineEnding + $lineEnding + $notesBlock + $lineEnding
    }

    $changedFiles = [System.Collections.Generic.List[string]]::new()
    if ($updatedChangelog -ne $changelog) { $changedFiles.Add('CHANGELOG.md') }
    if ($updatedReleaseNotes -ne $releaseNotes) { $changedFiles.Add('release-notes.md') }
    if ($changedFiles.Count -eq 0) {
        Write-Output "Release documentation is current for $FromTag..HEAD."
        return
    }
    if ($DryRun) {
        Write-Output "Would update $($changedFiles -join ' and ') from $FromTag for $Version."
        return
    }
    if ($PSCmdlet.ShouldProcess(($changedFiles -join ', '), "Generate release documentation from $FromTag..HEAD")) {
        if ($updatedChangelog -ne $changelog) { [System.IO.File]::WriteAllText($changelogPath, $updatedChangelog, [System.Text.UTF8Encoding]::new($false)) }
        if ($updatedReleaseNotes -ne $releaseNotes) { [System.IO.File]::WriteAllText($releaseNotesPath, $updatedReleaseNotes, [System.Text.UTF8Encoding]::new($false)) }
        Write-Output "Updated $($changedFiles -join ' and ') from $FromTag for $Version."
    }
}
