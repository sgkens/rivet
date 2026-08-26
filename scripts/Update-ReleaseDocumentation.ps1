function Update-ReleaseDocumentation {
    <#
    .SYNOPSIS
        Generates marker-bounded changelog and release-note content from Git history.
    .DESCRIPTION
        Reads commits after the newest reachable tag that has a GitLab release,
        or an explicitly supplied Git ref, and groups them by Keep a Changelog
        categories. Only content between rivet markers is replaced.
        Supports full changelog reconstruction across all reachable tags with -Rebuild.
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
    .PARAMETER Rebuild
        Rebuilds the entire CHANGELOG.md and changelog.json across all reachable Git tags.
    .PARAMETER DryRun
        Reports changes without writing either document.
    .PARAMETER IncludeCommitHash
        Appends the short commit hash to each generated change. Enabled by default.
    .PARAMETER IncludeAuthor
        Appends the commit author after the commit hash. Enabled by default.
    .PARAMETER WriteChangelogJson
        Writes a curated, structured changelog projection for documentation.
        Only breaking, feat, fix, and perf commits are included.
    .PARAMETER ChangelogJsonPath
        Repository-relative or absolute path for the JSON projection.
    .EXAMPLE
        Update-ReleaseDocumentation -RepositoryRoot $PWD -DryRun
    .EXAMPLE
        Update-ReleaseDocumentation -RepositoryRoot $PWD -FromTag v0.25.0 -Version 0.28.0 -Finalize
    .EXAMPLE
        Update-ReleaseDocumentation -RepositoryRoot $PWD -Rebuild -WriteChangelogJson
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
        [Alias('RebuildChangelog')][switch]$Rebuild,
        [switch]$IncludeCommitHash = $true,
        [switch]$IncludeAuthor = $true,
        [switch]$WriteChangelogJson,
        [string]$ChangelogJsonPath = 'docs/data/changelog.json',
        [switch]$DryRun
    )

    $ErrorActionPreference = 'Stop'
    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required to generate release documentation.' }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = [System.IO.Path]::Combine($repositoryPath, 'repo_config.json') }
    $config = Get-RivetConfiguration -ConfigPath $ConfigPath
    $baseUri = ([string]$config.gitlab.baseUri).TrimEnd('/')
    $projectId = [string]$config.gitlab.projectId
    $projectPath = ([string]$config.project.path).Trim('/')
    $projectName = [string]$config.project.displayName
    $tokenVariable = [string]$config.gitlab.tokenEnvironmentVariable
    $timeoutSeconds = [int]$config.requestTimeoutSeconds

    $categoryOrder = @('Added', 'Changed', 'Deprecated', 'Removed', 'Fixed', 'Security')
    $format = '%H%x1f%an%x1f%ae%x1f%s%x1f%b%x1e'

    function Get-RangeNotes {
        param(
            [string]$GitRange,
            [string]$ExplicitScope
        )

        $entries = [ordered]@{}
        foreach ($cat in $categoryOrder) { $entries[$cat] = [System.Collections.Generic.List[string]]::new() }
        $jsonEntries = [System.Collections.Generic.List[object]]::new()
        $commitsIncluded = 0

        $logArgs = if ($GitRange.Contains('..')) {
            @('log', '--no-merges', $GitRange, "--format=$format")
        } elseif ($GitRange -eq 'HEAD') {
            @('log', '--no-merges', 'HEAD', "--format=$format")
        } else {
            @('log', '--no-merges', $GitRange, "--format=$format")
        }

        $rawLog = (& git -C $repositoryPath @logArgs) -join "`n"
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rawLog)) {
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
                if (-not [string]::IsNullOrWhiteSpace($ExplicitScope) -and $parsed.Scope -ine $ExplicitScope) { continue }
                $commitsIncluded++
                $category = $parsed.Category
                $text = $parsed.ReleaseNote
                $shortHash = $commitHash.Substring(0, [Math]::Min(7, $commitHash.Length))
                $authorReference = Resolve-GitLabAuthorReference -Config $config -Name $author -Email $authorEmail
                $metadata = [System.Collections.Generic.List[string]]::new(2)
                if ($IncludeCommitHash) {
                    $metadata.Add("[$shortHash]($baseUri/$projectPath/-/commit/$commitHash)")
                }
                if ($IncludeAuthor) {
                    $metadata.Add($authorReference)
                }
                if ($metadata.Count -gt 0) { $text += " ($($metadata -join ' — '))" }
                if (-not $entries[$category].Contains($text)) { [void]$entries[$category].Add($text) }

                $isVersionBump = $parsed.Breaking -or ($parsed.IsConventional -and $parsed.Type -in @('feat', 'fix', 'perf'))
                if ($isVersionBump) {
                    $jsonEntries.Add([ordered]@{
                        category = $category
                        type = $parsed.Type
                        scope = $parsed.Scope
                        breaking = [bool]$parsed.Breaking
                        text = $parsed.ReleaseNote
                        commit = [ordered]@{
                            short = $shortHash
                            hash = $commitHash
                            url = "$baseUri/$projectPath/-/commit/$commitHash"
                        }
                        author = [ordered]@{
                            name = $author
                            reference = $authorReference
                        }
                    })
                }
            }
        }

        $sections = [System.Collections.Generic.List[string]]::new()
        foreach ($cat in $categoryOrder) {
            if ($entries[$cat].Count -eq 0) { continue }
            $sections.Add("### $cat")
            $sections.Add('')
            foreach ($entry in $entries[$cat]) { $sections.Add("- $entry") }
            $sections.Add('')
        }
        if ($sections.Count -eq 0) { $sections.Add('- No release-note commits were found in the selected range.') }

        return [PSCustomObject]@{
            Body = ($sections -join "`n").TrimEnd()
            JsonEntries = $jsonEntries
            Included = $commitsIncluded
        }
    }

    $changelogPath = [System.IO.Path]::Combine($repositoryPath, 'CHANGELOG.md')
    $releaseNotesPath = [System.IO.Path]::Combine($repositoryPath, 'release-notes.md')
    $changelog = if ([System.IO.File]::Exists($changelogPath)) { [System.IO.File]::ReadAllText($changelogPath) } else { "# Changelog`n`n## [Unreleased]`n`n<!-- rivet:changelog:start -->`n<!-- rivet:changelog:end -->`n" }
    $releaseNotes = if ([System.IO.File]::Exists($releaseNotesPath)) { [System.IO.File]::ReadAllText($releaseNotesPath) } else { "<!-- rivet:release-notes:start -->`n<!-- rivet:release-notes:end -->`n" }
    $lineEnding = if ($changelog.Contains("`r`n")) { "`r`n" } else { "`n" }

    $changelogStart = '<!-- rivet:changelog:start -->'
    $changelogEnd = '<!-- rivet:changelog:end -->'
    $notesStart = '<!-- rivet:release-notes:start -->'
    $notesEnd = '<!-- rivet:release-notes:end -->'

    if ($Rebuild) {
        $rawTags = @(& git -C $repositoryPath tag --sort=creatordate 2>$null) | Where-Object {
            $_ -match '^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'
        }

        $reachableTags = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $rawTags) {
            & git -C $repositoryPath merge-base --is-ancestor $t HEAD 2>$null
            if ($LASTEXITCODE -eq 0) { [void]$reachableTags.Add($t) }
        }

        $changelogBuilder = [System.Text.StringBuilder]::new()
        $changelogBuilder.AppendLine('# Changelog') | Out-Null
        $changelogBuilder.AppendLine('') | Out-Null
        $changelogBuilder.AppendLine('All notable changes to this project will be documented in this file.') | Out-Null
        $changelogBuilder.AppendLine('') | Out-Null
        $changelogBuilder.AppendLine('The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),') | Out-Null
        $changelogBuilder.AppendLine('and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).') | Out-Null
        $changelogBuilder.AppendLine('') | Out-Null
        $changelogBuilder.AppendLine('## [Unreleased]') | Out-Null
        $changelogBuilder.AppendLine('') | Out-Null
        $changelogBuilder.AppendLine($changelogStart) | Out-Null
        $changelogBuilder.AppendLine('') | Out-Null

        $unreleasedRange = if ($reachableTags.Count -gt 0) { "$($reachableTags[-1])..HEAD" } else { 'HEAD' }
        $unreleasedNotes = Get-RangeNotes -GitRange $unreleasedRange -ExplicitScope $Scope
        $changelogBuilder.AppendLine($unreleasedNotes.Body) | Out-Null
        $changelogBuilder.AppendLine('') | Out-Null
        $changelogBuilder.AppendLine($changelogEnd) | Out-Null

        $jsonVersions = [System.Collections.Generic.List[object]]::new()
        $headHash = ((& git -C $repositoryPath rev-parse HEAD 2>$null) -join '').Trim()

        $jsonVersions.Add([ordered]@{
            version = 'unreleased'
            date = $null
            from = if ($reachableTags.Count -gt 0) { $reachableTags[-1] } else { $null }
            to = $headHash
            entries = @($unreleasedNotes.JsonEntries)
            included = $unreleasedNotes.Included
            excluded_non_version_bump = $unreleasedNotes.Included - $unreleasedNotes.JsonEntries.Count
        })

        # Process tags in reverse order (newest first)
        for ($i = $reachableTags.Count - 1; $i -ge 0; $i--) {
            $currentTag = $reachableTags[$i]
            $tagRange = if ($i -gt 0) { "$($reachableTags[$i - 1])..$currentTag" } else { $currentTag }
            $tagNotes = Get-RangeNotes -GitRange $tagRange -ExplicitScope $Scope
            $tagVersion = $currentTag -replace '^v', ''
            $tagDate = ((& git -C $repositoryPath log -1 --format=%cs $currentTag 2>$null) -join '').Trim()
            $tagHash = ((& git -C $repositoryPath rev-parse $currentTag 2>$null) -join '').Trim()
            $fromRef = if ($i -gt 0) { $reachableTags[$i - 1] } else { $null }

            $changelogBuilder.AppendLine('') | Out-Null
            $changelogBuilder.AppendLine("## [$tagVersion]") | Out-Null
            if (-not [string]::IsNullOrWhiteSpace($tagDate)) {
                $changelogBuilder.AppendLine('') | Out-Null
                $changelogBuilder.AppendLine("> $tagDate") | Out-Null
            }
            $changelogBuilder.AppendLine('') | Out-Null
            $changelogBuilder.AppendLine($tagNotes.Body) | Out-Null

            $jsonVersions.Add([ordered]@{
                version = $tagVersion
                date = if ($tagDate) { $tagDate } else { $null }
                from = $fromRef
                to = $tagHash
                entries = @($tagNotes.JsonEntries)
                included = $tagNotes.Included
                excluded_non_version_bump = $tagNotes.Included - $tagNotes.JsonEntries.Count
            })
        }

        $updatedChangelog = ($changelogBuilder.ToString().TrimEnd() + "`n").Replace("`r`n", "`n").Replace("`n", $lineEnding)

        $rangeSummary = if ($reachableTags.Count -gt 0) {
            "Generated from ``$($reachableTags[-1])..HEAD`` for $projectName."
        } else {
            "Generated from repository history for $projectName."
        }

        $notesBlock = @"
$notesStart

$rangeSummary

$($unreleasedNotes.Body)

$notesEnd
"@.TrimEnd().Replace("`r`n", "`n").Replace("`n", $lineEnding)

        $notesPattern = '(?ms)<!-- (?:rivet|glmeta):release-notes:start -->.*?<!-- (?:rivet|glmeta):release-notes:end -->'
        $updatedReleaseNotes = if ([regex]::IsMatch($releaseNotes, $notesPattern)) {
            [regex]::Replace($releaseNotes, $notesPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [void]$match; $notesBlock }, 1)
        } else {
            $releaseNotes.TrimEnd() + $lineEnding + $lineEnding + $notesBlock + $lineEnding
        }

        $updatedChangelogJson = $null
        $changelogJsonAbsolutePath = if ([System.IO.Path]::IsPathRooted($ChangelogJsonPath)) {
            [System.IO.Path]::GetFullPath($ChangelogJsonPath)
        } else {
            [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repositoryPath, $ChangelogJsonPath))
        }

        if ($WriteChangelogJson) {
            $jsonDocument = [ordered]@{
                schema_version = 2
                source = [ordered]@{
                    history = 'git'
                    canonical_record = 'CHANGELOG.md'
                }
                projection = 'Complete canonical changelog notes reconstructed from Git tag history.'
                project = $projectPath
                versions = @($jsonVersions)
            }
            $updatedChangelogJson = ($jsonDocument | ConvertTo-Json -Depth 12) + "`n"
        }

        $changedFiles = [System.Collections.Generic.List[string]]::new()
        if ($updatedChangelog -ne $changelog) { $changedFiles.Add('CHANGELOG.md') }
        if ($updatedReleaseNotes -ne $releaseNotes) { $changedFiles.Add('release-notes.md') }
        if ($WriteChangelogJson) {
            $existingChangelogJson = if ([System.IO.File]::Exists($changelogJsonAbsolutePath)) { [System.IO.File]::ReadAllText($changelogJsonAbsolutePath) } else { '' }
            if ($updatedChangelogJson -ne $existingChangelogJson) { $changedFiles.Add($ChangelogJsonPath) }
        }

        if ($changedFiles.Count -eq 0) {
            Write-Output "Changelog is already current across all reachable Git tags."
            return
        }
        if ($DryRun) {
            Write-Output "Would rebuild $($changedFiles -join ' and ') across $($reachableTags.Count) release tag(s)."
            return
        }
        if ($PSCmdlet.ShouldProcess(($changedFiles -join ', '), "Rebuild changelog across $($reachableTags.Count) release tags")) {
            [System.IO.File]::WriteAllText($changelogPath, $updatedChangelog, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($releaseNotesPath, $updatedReleaseNotes, [System.Text.UTF8Encoding]::new($false))
            if ($WriteChangelogJson) {
                $jsonDirectory = [System.IO.Path]::GetDirectoryName($changelogJsonAbsolutePath)
                if (-not [System.IO.Directory]::Exists($jsonDirectory)) { [System.IO.Directory]::CreateDirectory($jsonDirectory) | Out-Null }
                [System.IO.File]::WriteAllText($changelogJsonAbsolutePath, $updatedChangelogJson, [System.Text.UTF8Encoding]::new($false))
            }
            Write-Output "Rebuilt $($changedFiles -join ' and ') across $($reachableTags.Count) release tag(s)."
        }
        return
    }

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

    $headHash = ((& git -C $repositoryPath rev-parse HEAD) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headHash)) {
        throw 'Unable to resolve the current HEAD commit.'
    }
    $fromHash = ((& git -C $repositoryPath rev-parse $FromTag) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fromHash)) {
        throw "Unable to resolve release-document baseline '$FromTag'."
    }
    $fromVersionMatch = [regex]::Match($FromTag, '^v?(?<version>\d+\.\d+\.\d+)(?:-(?:release|snapshot))?$')
    if ($Finalize -and $fromVersionMatch.Success -and $fromVersionMatch.Groups['version'].Value -eq $Version -and $fromHash -ne $headHash) {
        throw "Cannot finalize $Version from $FromTag because that version is already tagged. Generate an Unreleased draft or add a version-bumping commit before preparing another release."
    }

    $rangeResult = Get-RangeNotes -GitRange "${FromTag}..HEAD" -ExplicitScope $Scope
    $generatedBody = $rangeResult.Body
    $jsonEntries = $rangeResult.JsonEntries
    $commitsIncludedInMarkdown = $rangeResult.Included

    $rangeSummary = "Generated from ``$FromTag..HEAD`` for $projectName ``$Version``."

    $changelogBlock = "$changelogStart`n`n$generatedBody`n`n$changelogEnd".Replace("`n", $lineEnding)
    $changelogPattern = '(?ms)<!-- (?:rivet|glmeta):changelog:start -->\s*(?<body>.*?)\s*<!-- (?:rivet|glmeta):changelog:end -->'
    $heading = if ($Finalize) { "## [$Version]" } else { '## [Unreleased]' }
    $markerMatch = [regex]::Match($changelog, $changelogPattern)
    $headingMatch = [regex]::Match($changelog, "(?m)^$([regex]::Escape($heading))[ \t]*$")
    $markerInTargetSection = $false
    if ($markerMatch.Success -and $headingMatch.Success) {
        $releaseHeadingRegex = [regex]::new('^## \[', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        $nextHeading = $releaseHeadingRegex.Match($changelog, $headingMatch.Index + $headingMatch.Length)
        $markerInTargetSection = $markerMatch.Index -gt $headingMatch.Index -and (-not $nextHeading.Success -or $markerMatch.Index -lt $nextHeading.Index)
    }
    if ($markerMatch.Success -and $markerInTargetSection) {
        $updatedChangelog = [regex]::Replace($changelog, $changelogPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [void]$match; $changelogBlock }, 1)
    } else {
        $baseChangelog = if ($markerMatch.Success) {
            [regex]::Replace(
                $changelog,
                $changelogPattern,
                [System.Text.RegularExpressions.MatchEvaluator]{
                    param($match)
                    $match.Groups['body'].Value.Trim()
                },
                1
            )
        } else { $changelog }
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

    $notesBlock = @"
$notesStart

$rangeSummary

$generatedBody

$notesEnd
"@.TrimEnd().Replace("`r`n", "`n").Replace("`n", $lineEnding)
    $notesPattern = '(?ms)<!-- (?:rivet|glmeta):release-notes:start -->.*?<!-- (?:rivet|glmeta):release-notes:end -->'
    $updatedReleaseNotes = if ([regex]::IsMatch($releaseNotes, $notesPattern)) {
        [regex]::Replace($releaseNotes, $notesPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [void]$match; $notesBlock }, 1)
    } else {
        $releaseNotes.TrimEnd() + $lineEnding + $lineEnding + $notesBlock + $lineEnding
    }

    $updatedChangelogJson = $null
    $changelogJsonAbsolutePath = $null
    if ($WriteChangelogJson) {
        $changelogJsonAbsolutePath = if ([System.IO.Path]::IsPathRooted($ChangelogJsonPath)) {
            [System.IO.Path]::GetFullPath($ChangelogJsonPath)
        } else {
            [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repositoryPath, $ChangelogJsonPath))
        }
        $existingByVersion = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ([System.IO.File]::Exists($changelogJsonAbsolutePath)) {
            $existingDocument = [System.IO.File]::ReadAllText($changelogJsonAbsolutePath) | ConvertFrom-Json
            foreach ($existingVersion in @($existingDocument.versions)) {
                $existingIdentity = [string]$existingVersion.version
                if (-not [string]::IsNullOrWhiteSpace($existingIdentity)) { $existingByVersion[$existingIdentity] = $existingVersion }
            }
        }
        $versionIdentity = if ($Finalize) { $Version } else { 'unreleased' }
        $releaseDate = if ($Finalize) {
            $dateMatch = [regex]::Match($updatedChangelog, "(?ms)^$([regex]::Escape($heading))\s*\r?\n\s*>\s*(?<date>\d{4}-\d{2}-\d{2})")
            if ($dateMatch.Success) { $dateMatch.Groups['date'].Value } else { [DateTime]::Today.ToString('yyyy-MM-dd') }
        } else { $null }
        $currentEntriesByText = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($entry in $jsonEntries) { $currentEntriesByText[[string]$entry.text] = $entry }
        $versions = [System.Collections.Generic.List[object]]::new()
        $releasePattern = '(?ms)^## \[(?<version>[^\]]+)\][^\r\n]*\r?\n(?<content>.*?)(?=^## \[|\z)'
        foreach ($releaseMatch in [regex]::Matches($updatedChangelog, $releasePattern)) {
            $identity = $releaseMatch.Groups['version'].Value.Trim()
            $identityKey = if ($identity -ieq 'Unreleased') { 'unreleased' } else { $identity }
            $content = $releaseMatch.Groups['content'].Value
            $dateValue = [regex]::Match($content, '(?m)^>\s*(?<date>\d{4}-\d{2}-\d{2})\s*$').Groups['date'].Value
            if ([string]::IsNullOrWhiteSpace($dateValue)) { $dateValue = $null }
            $markdownEntries = [System.Collections.Generic.List[object]]::new()
            $category = $null
            foreach ($line in ($content -split '\r?\n')) {
                $categoryMatch = [regex]::Match($line, '^###\s+(Added|Changed|Deprecated|Removed|Fixed|Security)\s*$')
                if ($categoryMatch.Success) { $category = $categoryMatch.Groups[1].Value; continue }
                if ([string]::IsNullOrWhiteSpace($category) -or $line -notmatch '^-\s+(?<note>.+)$') { continue }
                $note = $Matches['note'].Trim()
                $metadataMatch = [regex]::Match($note, '^(?<text>.*) \(\[(?<short>[0-9a-f]{7,40})\]\((?<url>https?://[^)]+/(?<hash>[0-9a-f]{40}))\)(?: — (?<author>[^)]+))?\)$')
                $noteText = if ($metadataMatch.Success) { $metadataMatch.Groups['text'].Value } else { $note }
                if ($identityKey -ieq $versionIdentity -and $currentEntriesByText.ContainsKey($noteText)) {
                    $markdownEntries.Add($currentEntriesByText[$noteText])
                    continue
                }
                $markdownEntries.Add([ordered]@{
                    category = $category
                    type = $null
                    scope = $null
                    breaking = $noteText.StartsWith('Breaking:', [System.StringComparison]::OrdinalIgnoreCase)
                    text = $noteText
                    commit = if ($metadataMatch.Success) { [ordered]@{
                        short = $metadataMatch.Groups['short'].Value
                        hash = $metadataMatch.Groups['hash'].Value
                        url = $metadataMatch.Groups['url'].Value
                    } } else { $null }
                    author = if ($metadataMatch.Success -and $metadataMatch.Groups['author'].Success) { [ordered]@{
                        name = $null
                        reference = $metadataMatch.Groups['author'].Value
                    } } else { $null }
                })
            }
            $isCurrent = $identityKey -ieq $versionIdentity
            $existingVersion = if ($existingByVersion.ContainsKey($identityKey)) { $existingByVersion[$identityKey] } else { $null }
            $versions.Add([ordered]@{
                version = $identityKey
                date = if ($isCurrent -and $releaseDate) { $releaseDate } else { $dateValue }
                from = if ($isCurrent) { $FromTag } elseif ($null -ne $existingVersion) { $existingVersion.from } else { $null }
                to = if ($isCurrent) { $headHash } elseif ($null -ne $existingVersion) { $existingVersion.to } else { $null }
                entries = @($markdownEntries)
                included = $markdownEntries.Count
                excluded_non_version_bump = if ($isCurrent) { $commitsIncludedInMarkdown - $jsonEntries.Count } else { 0 }
            })
        }
        $jsonDocument = [ordered]@{
            schema_version = 2
            source = [ordered]@{
                history = 'git'
                canonical_record = 'CHANGELOG.md'
            }
            projection = 'Complete canonical changelog notes with Git metadata when available.'
            project = $projectPath
            versions = @($versions)
        }
        $updatedChangelogJson = ($jsonDocument | ConvertTo-Json -Depth 12) + "`n"
    }

    $changedFiles = [System.Collections.Generic.List[string]]::new()
    if ($updatedChangelog -ne $changelog) { $changedFiles.Add('CHANGELOG.md') }
    if ($updatedReleaseNotes -ne $releaseNotes) { $changedFiles.Add('release-notes.md') }
    if ($WriteChangelogJson) {
        $existingChangelogJson = if ([System.IO.File]::Exists($changelogJsonAbsolutePath)) { [System.IO.File]::ReadAllText($changelogJsonAbsolutePath) } else { '' }
        if ($updatedChangelogJson -ne $existingChangelogJson) { $changedFiles.Add($ChangelogJsonPath) }
    }
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
        if ($WriteChangelogJson) {
            $jsonDirectory = [System.IO.Path]::GetDirectoryName($changelogJsonAbsolutePath)
            if (-not [System.IO.Directory]::Exists($jsonDirectory)) { [System.IO.Directory]::CreateDirectory($jsonDirectory) | Out-Null }
            [System.IO.File]::WriteAllText($changelogJsonAbsolutePath, $updatedChangelogJson, [System.Text.UTF8Encoding]::new($false))
        }
        Write-Output "Updated $($changedFiles -join ' and ') from $FromTag for $Version."
    }
}
