function Update-MergeRequestDocumentation {
    <#
    .SYNOPSIS
        Updates generated fields in the repository merge-request document.
    .DESCRIPTION
        Uses the existing mr.md section layout as the template and refreshes
        release identity, branch, range, commit changes, and the package-version
        checklist item from repository state.
    .PARAMETER RepositoryRoot
        Repository containing mr.md and package.json.
    .PARAMETER FromTag
        Optional reachable Git ref used as the beginning of the change range.
    .PARAMETER Version
        Release version. Defaults to package.json.
    .PARAMETER TargetBranch
        Merge-request target branch. Defaults to main.
    .PARAMETER IncludeCommitHash
        Appends the short commit hash to each generated change. Enabled by default.
    .PARAMETER IncludeAuthor
        Appends the commit author after the commit hash. Enabled by default.
    .PARAMETER DryRun
        Reports changes without writing mr.md.
    .EXAMPLE
        Update-MergeRequestDocumentation -RepositoryRoot $PWD -FromTag v0.27.3
    .EXAMPLE
        Update-MergeRequestDocumentation -RepositoryRoot $PWD -IncludeAuthor:$false -DryRun
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RepositoryRoot = (Get-Location).Path,
        [string]$ConfigPath,
        [string]$FromTag,
        [ValidatePattern('^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
        [string]$Version,
        [string]$Scope,
        [string]$TargetBranch = 'main',
        [switch]$IncludeCommitHash = $true,
        [switch]$IncludeAuthor = $true,
        [switch]$DryRun
    )

    $ErrorActionPreference = 'Stop'
    $repositoryPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required to generate merge-request documentation.' }
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = [System.IO.Path]::Combine($repositoryPath, 'repo_config.json') }
    $config = Get-GlmetaConfiguration -ConfigPath $ConfigPath
    $baseUri = ([string]$config.gitlab.baseUri).TrimEnd('/')
    $projectPath = ([string]$config.project.path).Trim('/')
    $projectName = [string]$config.project.displayName

    if ([string]::IsNullOrWhiteSpace($FromTag)) {
        $FromTag = @(& git -C $repositoryPath tag --merged HEAD --list 'v[0-9]*' --sort=-version:refname) |
            Where-Object { $_ -match '^v\d+\.\d+\.\d+(?:-release)?$' } |
            Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($FromTag)) { throw 'No reachable stable SemVer tag was found; specify -FromTag.' }
    }
    & git -C $repositoryPath merge-base --is-ancestor $FromTag HEAD
    if ($LASTEXITCODE -ne 0) { throw "FromTag '$FromTag' is not a reachable ancestor of HEAD." }

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $packagePath = [System.IO.Path]::Combine($repositoryPath, 'package.json')
        $packageDocument = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($packagePath))
        try { $Version = $packageDocument.RootElement.GetProperty('version').GetString() } finally { $packageDocument.Dispose() }
    }
    $Version = $Version.TrimStart('v')
    $sourceBranch = (& git -C $repositoryPath branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($sourceBranch)) { $sourceBranch = 'HEAD' }

    $changes = [System.Collections.Generic.List[string]]::new()
    $rawLog = (& git -C $repositoryPath log --no-merges "${FromTag}..HEAD" '--format=%H%x1f%an%x1f%ae%x1f%s%x1e') -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Unable to read commits in range '$FromTag..HEAD'." }
    foreach ($record in ($rawLog -split [char]0x1e)) {
        if ([string]::IsNullOrWhiteSpace($record)) { continue }
        $fields = $record.Trim() -split [char]0x1f, 4
        if ($fields.Count -lt 4) { continue }
        $hash = $fields[0].Trim()
        $author = $fields[1].Trim()
        $authorEmail = $fields[2].Trim()
        $parsed = ConvertFrom-ConventionalCommit -Subject $fields[3].Trim()
        if (-not [string]::IsNullOrWhiteSpace($Scope) -and $parsed.Scope -ine $Scope) { continue }
        $text = $parsed.ReleaseNote
        $metadata = [System.Collections.Generic.List[string]]::new(2)
        if ($IncludeCommitHash) {
            $shortHash = $hash.Substring(0, [Math]::Min(7, $hash.Length))
            $metadata.Add("[$shortHash]($baseUri/$projectPath/-/commit/$hash)")
        }
        if ($IncludeAuthor) { $metadata.Add((Resolve-GitLabAuthorReference -Config $config -Name $author -Email $authorEmail)) }
        if ($metadata.Count -gt 0) { $text += " ($($metadata -join ' — '))" }
        $changes.Add("- $text")
    }
    if ($changes.Count -eq 0) { $changes.Add('- No non-merge commits were found in the selected range.') }

    $path = [System.IO.Path]::Combine($repositoryPath, 'mr.md')
    $templatePath = [System.IO.Path]::Combine($repositoryPath, 'tools', 'glmeta', 'templates', 'mr.md')
    if ([System.IO.File]::Exists($path)) {
        $content = [System.IO.File]::ReadAllText($path)
    } elseif ([System.IO.File]::Exists($templatePath)) {
        $content = [System.IO.File]::ReadAllText($templatePath)
    } else {
        throw "Merge-request template not found: $templatePath"
    }
    $lineEnding = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $updated = $content
    $updated = [regex]::Replace($updated, '(?ms)(^## Title\s+).*?(?=^## Source branch)', "`$1Release $projectName $Version`n`n".Replace("`n", $lineEnding), 1)
    $updated = [regex]::Replace($updated, '(?ms)(^## Source branch\s+).*?(?=^## Target branch)', "`$1``$sourceBranch```n`n".Replace("`n", $lineEnding), 1)
    $updated = [regex]::Replace($updated, '(?ms)(^## Target branch\s+).*?(?=^## Change range)', "`$1``$TargetBranch```n`n".Replace("`n", $lineEnding), 1)
    $updated = [regex]::Replace($updated, '(?ms)(^## Change range\s+).*?(?=^## Summary)', "`$1All changes after ``$FromTag`` through the current ``$sourceBranch`` branch.`n`n".Replace("`n", $lineEnding), 1)

    $summaryStart = '<!-- glmeta:mr-changes:start -->'
    $summaryEnd = '<!-- glmeta:mr-changes:end -->'
    $summaryBlock = "$summaryStart`n`n$($changes -join "`n")`n`n$summaryEnd".Replace("`n", $lineEnding)
    $summaryPattern = '(?ms)<!-- glmeta:mr-changes:start -->.*?<!-- glmeta:mr-changes:end -->'
    if ([regex]::IsMatch($updated, $summaryPattern)) {
        $updated = [regex]::Replace($updated, $summaryPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) [void]$match; $summaryBlock }, 1)
    } else {
        $updated = [regex]::Replace($updated, '(?ms)(^## Summary\s+).*?(?=^## Compatibility)', "`$1$summaryBlock`n`n".Replace("`n", $lineEnding), 1)
    }

    $packageChecklist = "- [ ] Update npm ``package.json`` and JSR ``jsr.jsonc`` package versions to ``$Version``."
    $updated = [regex]::Replace($updated, '(?m)^- \[[ xX]\] Update npm `package\.json` and JSR `jsr\.jsonc` package versions(?: to `[^`]+`)?\.\r?\n?', '')
    $checklistMatch = [regex]::Match($updated, '(?ms)(^## Release checklist\s+)(?<items>.*?)(?=^## Review notes)')
    if (-not $checklistMatch.Success) { throw 'The mr.md Release checklist section was not found.' }
    $items = $checklistMatch.Groups['items'].Value.TrimEnd()
    $replacement = $checklistMatch.Groups[1].Value + $items + $lineEnding + $packageChecklist + $lineEnding + $lineEnding
    $updated = $updated.Remove($checklistMatch.Index, $checklistMatch.Length).Insert($checklistMatch.Index, $replacement)

    if ($updated -eq $content) { Write-Output "mr.md is current for $FromTag..HEAD."; return }
    if ($DryRun) { Write-Output "Would update mr.md from $FromTag for $Version."; return }
    if ($PSCmdlet.ShouldProcess($path, "Generate merge-request documentation from $FromTag..HEAD")) {
        [System.IO.File]::WriteAllText($path, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Output "Updated mr.md from $FromTag for $Version."
    }
}
