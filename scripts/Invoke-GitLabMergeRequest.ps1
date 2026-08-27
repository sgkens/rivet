function Invoke-GitLabMergeRequest {
    <#
    .SYNOPSIS
        Creates or updates a GitLab merge request from repository-root mr.md.
    .DESCRIPTION
        Parses the generated title, source branch, target branch, IID placeholder,
        and Markdown body. Update mode selects the matching merge request by
        IID or source and target branch. When created or updated, the merge
        request IID and web link are written back to mr.md. Tokens are read from
        repository configuration and are never written to output.
    .EXAMPLE
        Invoke-GitLabMergeRequest -RepositoryRoot $PWD -ConfigPath ./repo_config.json -Mode Create -DryRun
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$ConfigPath,
        [Parameter(Mandatory)][ValidateSet('Create', 'Update')][string]$Mode,
        [switch]$DryRun
    )

    $repoFullPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Resolve-RivetPath -RepositoryRoot $repoFullPath -ItemName 'repo_config.json'
    }
    $config = Get-RivetConfiguration -ConfigPath $ConfigPath
    $documentPath = Resolve-RivetPath -RepositoryRoot $repoFullPath -ItemName 'mr.md'
    if (-not [System.IO.File]::Exists($documentPath)) { throw "Merge-request document not found: $documentPath" }
    $content = [System.IO.File]::ReadAllText($documentPath)

    function Get-MrFieldValue([string]$Name) {
        $tablePattern = '(?m)\|\s*(?:\*\*)?' + [regex]::Escape($Name) + '(?::?\*\*|\*\*:?|:)?\s*\|\s*([^|\r\n]+?)\s*\|'
        $tableMatch = [regex]::Match($content, $tablePattern)
        if ($tableMatch.Success) {
            $val = $tableMatch.Groups[1].Value.Trim().Trim('`').Trim()
            if ($val -notin @('date-here', 'count here', 'link here', 'id here', 'source-branch', 'target-branch', 'Merge Request Title', 'closes', 'milestone', '')) {
                return $val
            }
        }
        $sectionPattern = "(?ms)^## \*{0,2}" + [regex]::Escape($Name) + "\*{0,2}\s*\r?\n\s*(.+?)(?=\r?\n## |\z)"
        $sectionMatch = [regex]::Match($content, $sectionPattern)
        if ($sectionMatch.Success) {
            return $sectionMatch.Groups[1].Value.Trim().Trim('`').Trim()
        }
        return $null
    }

    $title = Get-MrFieldValue 'Title'
    $sourceBranch = Get-MrFieldValue 'Source branch'
    $targetBranch = Get-MrFieldValue 'Target branch'
    if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($sourceBranch) -or [string]::IsNullOrWhiteSpace($targetBranch)) {
        throw 'mr.md must define non-empty Title, Source branch, and Target branch sections.'
    }

    $rawIid = Get-MrFieldValue 'Gitlab Merge Request IID'
    $existingIid = if ($rawIid -and $rawIid -match '(?:!)?(\d+)') { [int]$Matches[1] } else { $null }

    $description = [regex]::Replace($content, '(?ms)\A.*?(?=^## \*{0,2}(?:Closes|Milestones|Change range))', '').Trim()
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = [regex]::Replace($content, '(?ms)^# Merge Request\s*.*?(?=^## Change range)', '').Trim()
    }

    $baseUri = ([string]$config.gitlab.baseUri).TrimEnd('/')
    $projectId = [string]$config.gitlab.projectId
    $projectPath = [string]$config.project.path
    $projectKey = if ([string]::IsNullOrWhiteSpace($projectId)) { [uri]::EscapeDataString($projectPath) } else { $projectId }
    $tokenVariable = [string]$config.gitlab.tokenEnvironmentVariable
    if ([string]::IsNullOrWhiteSpace($tokenVariable)) { $tokenVariable = 'GITLAB_API_KEY' }
    $token = [System.Environment]::GetEnvironmentVariable($tokenVariable)
    if ([string]::IsNullOrWhiteSpace($token)) { throw "GitLab token not found. Set '$tokenVariable'." }
    $headers = @{ 'PRIVATE-TOKEN' = $token; Accept = 'application/json' }
    $apiRoot = "$baseUri/api/v4/projects/$projectKey/merge_requests"
    $timeout = [int]$config.requestTimeoutSeconds
    if ($timeout -lt 1) { $timeout = 30 }

    $targetIid = $existingIid
    if ($null -eq $targetIid) {
        $query = "state=opened&source_branch=$([uri]::EscapeDataString($sourceBranch))&target_branch=$([uri]::EscapeDataString($targetBranch))"
        $matches = @(Invoke-RestMethod -Method Get -Uri "$apiRoot`?$query" -Headers $headers -TimeoutSec $timeout)
        if ($Mode -eq 'Create' -and $matches.Count) {
            throw "An open merge request already exists for '$sourceBranch' into '$targetBranch' (iid $($matches[0].iid)); use update mode."
        }
        if ($Mode -eq 'Update' -and $matches.Count -eq 0) {
            throw "No open merge request exists for '$sourceBranch' into '$targetBranch'; use create mode."
        }
        if ($matches.Count -gt 1) { throw "More than one open merge request matches '$sourceBranch' into '$targetBranch'." }
        if ($matches.Count -eq 1) { $targetIid = [int]$matches[0].iid }
    } else {
        if ($Mode -eq 'Create') {
            try {
                $existingMr = Invoke-RestMethod -Method Get -Uri "$apiRoot/$targetIid" -Headers $headers -TimeoutSec $timeout
                if ($existingMr -and $existingMr.state -eq 'opened') {
                    throw "An open merge request already exists for '$sourceBranch' into '$targetBranch' (iid $targetIid); use update mode."
                }
            } catch {
                if ($_.Exception.Message -match 'already exists') { throw $_ }
            }
        }
    }

    $operation = if ($Mode -eq 'Create') { 'create' } else { "update iid $targetIid" }
    if ($DryRun) {
        [Console]::WriteLine("Would $operation merge request '$title' from $sourceBranch into $targetBranch.")
        return [pscustomobject]@{ Mode = $Mode; Title = $title; SourceBranch = $sourceBranch; TargetBranch = $targetBranch; Applied = $false; Iid = $targetIid }
    }

    $body = @{ title = $title; description = $description; source_branch = $sourceBranch; target_branch = $targetBranch; remove_source_branch = $true }
    $uri = if ($Mode -eq 'Create') { $apiRoot } else { "$apiRoot/$targetIid" }
    $method = if ($Mode -eq 'Create') { 'Post' } else { 'Put' }
    $response = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 4 -Compress) -TimeoutSec $timeout

    $updatedContent = [System.IO.File]::ReadAllText($documentPath)
    $updatedContent = [regex]::Replace($updatedContent, '(?m)(\|\s*(?:\*\*)?Gitlab Merge Request IID(?::?\*\*|\*\*:?|:)?\s*\|\s*)`?[^`|\r\n]*`?(\s*\|)', "`$1``!$($response.iid)```$2")
    $updatedContent = [regex]::Replace($updatedContent, '(?m)(\|\s*(?:\*\*)?Gitlab Merge Link(?::?\*\*|\*\*:?|:)?\s*\|\s*)`?[^`|\r\n]*`?(\s*\|)', "`$1``$($response.web_url)```$2")
    if ($updatedContent -ne $content) {
        [System.IO.File]::WriteAllText($documentPath, $updatedContent, [System.Text.UTF8Encoding]::new($false))
    }

    [Console]::WriteLine("GitLab merge request !$($response.iid) $($Mode.ToLowerInvariant())d: $($response.web_url)")
    return [pscustomobject]@{ Mode = $Mode; Title = $title; SourceBranch = $sourceBranch; TargetBranch = $targetBranch; Applied = $true; Iid = $response.iid; WebUrl = $response.web_url }
}
